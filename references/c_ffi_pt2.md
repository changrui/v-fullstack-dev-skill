
For inter-thread data exchange, use `spawn` + `map[string]T` (serializable) rather than channels with complex types:

```v
fn process_chunk_spawned(data &u8, data_len int, start int, end int) map[string]CityStats {
    mut agg := new_thread_agg()
    process_chunk(data, data_len, start, end, mut agg)
    return agg.to_map()
}

// In main:
mut results := []map[string]CityStats{}
for t in 0..num_threads {
    results << spawn process_chunk_spawned(data, size, start, end)
}
// Combine results...
```

**Why maps over channels with complex types?** V 0.5.x's `spawn` returns `[]T` via `.wait()`. Channels work but `spawn` + return is simpler for fan-out/fan-in.

## 8b. mmap thread-split MUST clamp `to` to `size` (SIGBUS pitfall)
When fanning the mmap'd buffer across threads, the chunk-end walk that snaps
`to` to the next `\n` CAN run `to` past EOF on the LAST split — and on
SMALL files it walks past the mapping entirely → **SIGBUS / bus error (core
dumped)**. The robust pattern:

```v
fn process_in_parallel(mf MMapFile, thread_count u32) map[string]CityStats {
	mut threads := []thread map[string]CityStats{}
	approx := mf.size / thread_count
	mut from := u64(0)
	mut to := approx
	for _ in 0 .. thread_count - 1 {
		// snap 'to' to next newline, but NEVER past the mapping
		unsafe {
			for mf.data[to] != `\n` && to < mf.size {
				to++
			}
		}
		threads << spawn process_chunk(mf.data, from, to)
		from = to + 1
		to = from + approx
	}
	to = mf.size          // <-- last chunk ends exactly at EOF, no walk past it
	threads << spawn process_chunk(mf.data, from, to)
	return combine_results(threads.wait())
}
```
Key: the **final** `to = mf.size` is set AFTER the loop (don't let the
in-loop walk compute the last boundary). Also `from = to + 1` can exceed
`size` when `to == size - 1`; guard with `if from < mf.size` before
spawning, or clamp `to` per-iteration. On a 41-byte file with 8 threads
the un-guarded version bus-error'd; the clamped version ran clean.

## 9b. High-performance 1BRC recipe (the "production" version)

A reference `v1brc.v` in the 1brc project hits **140-150 ms @ 100M rows**
and **1.6 s @ 1B rows (12.8GB) on 24 cores** — ~2.3x faster than the
naive `main.v`. The ALGORITHM is identical (mmap + spawn + lock-free
per-thread agg); the gap is entirely **system-layer optimization**:

1. **Integer temperature representation** — store temps as `i32` (25.8 → 258, i.e.
   ×10), do ALL math in integers (zero FP). `parse_temp` branches on
   len 3/4/5 and reads digits directly (`addr[start]-48`). This alone is
   several× faster than `f32` + a C float parser.
2. **`C.memchr` for `;` / `\n` scanning** — libc's memchr is SIMD-vectorized
   internally; calling it from V (`C.memchr(ptr, int(c), count)`) beats a
   hand-written byte-by-byte `for` loop by a wide margin. **Single biggest win.**
3. **Open-addressing hash table (pre-alloc'd array)** — `CityHashMap{ entries:
   []CityHashEntry{len: 4096} }` with linear probing. Zero heap alloc,
   cache-friendly. vs `map[string]T` (string key + hash + heap alloc = slow + fragmented).
4. **`hash_bytes` reads `u64` at a time** — one `&u64(addr[off])` load per 8 bytes
   of the city name, FNV mix, instead of a per-byte loop.
5. **Compile flags**: `-prod -skip-unused -no-bounds-checking -cflags
   "-std=c17 -march=native -mtune=native"`. The `-no-bounds-checking`
   switch (global) removes array bounds checks that `@[direct_array_access]`
   alone does NOT disable. (`-prod` also drops runtime asserts.)
6. **`MAP_POPULATE | MAP_SHARED` + `madvise(addr, size, MADV_SEQUENTIAL)`**
   at mmap time — pre-faults the page tables and tells the kernel the
   access is sequential, cutting page-fault stalls on a 12.8GB mapping.
7. **`runtime.nr_cpus()`** to auto-use ALL physical cores (don't hard-code 8).

Repro:
```bash
v -prod -cc gcc -skip-unused -no-bounds-checking \
   -cflags "-std=c17 -march=native -mtune=native" \
   -o bin/v1brc_user v1brc.v
./bin/v1brc_user measurements.txt    # auto-detects 24 cores
```

Lesson: for perf-critical V, the wins are memchr + integer math + open
addressing + bounds-check-off + mmap prefault — NOT micro-optimizing the
scalar float parse. See `templates/1brc_user.v` (the fast reference).

For short strings (2-5 chars like "5.8"), scalar unrolled loops beat SIMD. The real SIMD speedup in 1BRC comes from parallel LINE SCANNING (finding `;` and `\n` across lanes simultaneously).

See `c_simd.c` and `c_simd.h` in the 1brc project for a complete working example.

## 10. Compilation Flags

```bash
# Optimize for the host CPU
v -cc gcc -cflags '-O3 -march=native -ffast-math' -o bin/app main.v

# Disable garbage collection for maximum performance
v -cc gcc -cflags '-O3 -march=native -ffast-math -g0' -gc none -o bin/app main.v

# Generate intermediate C code for inspection
v -cc gcc -cflags '-O3' -o /tmp/app.c main.v  # -c flag for C-only
```

`-ffast-math` allows floating-point reordering (significant speedup for numeric workloads). `-march=native` enables CPU-specific instructions.
