# 1BRC V Language Benchmark Results

## Hardware
- CPU: 24 cores (AVX2 supported)
- RAM: 15GB
- OS: WSL (Ubuntu 24.04)
- Compiler: V 0.5.x (29a44b9)
- C compiler: GCC 13.3.0
- Naive flags (main.v): `-O3 -march=native -ffast-math`
- Fast flags (v1brc.v): `-prod -skip-unused -no-bounds-checking -cflags "-std=c17 -march=native -mtune=native"`

## Data generator (pure V)
`gen_data.v` generates the dataset in V itself (NOT Python). It uses
`rand.normal(mu:, sigma:)` for realistic temps and `strings.Builder` for
buffered I/O. 1,000,000 rows in ~120ms → ~8.3M rows/sec single-threaded.
Full 1B rows (~13GB) in a few minutes.

```bash
v -cc gcc -cflags '-O3 -march=native' -o bin/gen_data gen_data.v
./bin/gen_data measurements.txt 1000000000
```

## Performance (10M rows, 411 cities, ~131MB file)

| Threads | Time (ms) | Speedup |
|---------|-----------|---------|
| 1       | 400       | 1.00x   |
| 2       | 200       | 2.00x   |
| 4       | 120       | 3.33x   |
| 8       | ~60       | ~6.7x   |

(8-thread figure from `1brc` enhanced build with C FFI temperature parsing.)

## Key Findings (REVISED — 1BRC challenge, 2026-07-14)

1. **Near-linear scaling up to 8 threads** — lock-free per-thread `map[string]CityStats`
   aggregation avoids contention. The merge phase is O(N_cities) (~411), negligible.

2. **mmap + C FFI is viable** — `C.mmap()` from V, cast result to `&u8` via
   `unsafe { cast(&u8 addr) }`. Documented in `references/c_ffi_mmap.md`.

3. **`#flag ./c_simd.o` does NOT link on this V build** (empirically fails with
   "cannot call a function that does not have a body"). The RELIABLE method is
   `#include "c_simd.c"` at the top of main.v + `@[c_extern]` on the `fn C.xxx`
   declaration. See `c_ffi_mmap.md` §3.

4. **C signature `const unsigned char*` CONFLICTS with V's `&u8` = `unsigned char*`**
   → drop `const` in the .c (and keep .h in sync). Otherwise:
   `conflicting types for 'simd_parse_float_fast'; have 'f32(u8*, int)'`.

5. **Scalar float parsing is fast enough** — for short strings (2-5 chars), the
   unrolled scalar loop in C beats AVX2 SIMD (lower overhead). Real SIMD win
   would come from parallel line scanning (find `;`/`\n` across 32 bytes).

6. **`spawn` + return is simpler than channels** for fan-out/fan-in —
   `spawn func()` returns the result directly, collected via `[]T{}.wait()`.

7. **`f64.str(n)` / `f32.str(n)` DON'T EXIST in 0.5.2** — `str()` takes no
   args. Format 1-decimal with `math.round(v*10)/10` then `int.str()`, or a
   hand-rolled `fmt1(v f64) string`.

8. **The 2-second target IS reachable** — but only with the system-layer
   optimizations. Head-to-head on this 24-core/15GB box:

   | Build | 100M rows | 1B rows (12.8GB) |
   |-------|-----------|-------------------|
   | `main.v` (naive: f32 + C FFI parse, `map[string]`, `-O3`) | 329 ms | ~3.4 s |
   | `v1brc.v` (fast: integer temps, `C.memchr`, open-addressing hash, `-no-bounds-checking`, MAP_POPULATE+madvise) | **140-150 ms** | **1.6 s** |

   The algorithm is identical (mmap + spawn + lock-free per-thread agg);
   the gap is entirely memchr scan + integer math + open-addressing +
   bounds-check-off + mmap prefault. See `c_ffi_mmap.md` §9b and
   `templates/1brc_user.v` for the fast reference.

9. **1B rows is swap-bound on a 15GB box** — mmap of 12.8GB pushes
   RSS to ~12.9GB, triggering swap (cold run ~3.2-4.4s, warm ~1.6s).
   With ≥32GB RAM the naive build would also drop under 2s.

## Compilation Commands (VERIFIED)

```bash
# No separate gcc step — c_simd.c is #included and compiled by V's gcc pass
v -cc gcc -cflags '-O3 -march=native -ffast-math' -o bin/1brc main.v
```

## Notes / V 0.5.x gotchas hit during this challenge
- No `while` — use `for cond { }`.
- `byte` deprecated → `u8`.
- Consts snake_case: `max_cities` not `MAX_CITIES`.
- `fn C.xxx()` return type has NO colon (`voidptr` not `: voidptr`).
- `#[cfg(...)]` doesn't exist → `$if windows { } $else { }`.
- `unsafe { cast(&u8 addr) }` required to convert C void* to V byte ptr.
- `#include` at top level of `.v`, NOT inside attributes.
- City name must be captured at the `;` branch (not at `\n`) because `i` has
  already advanced past `;` by then.
- Data format `City;Temp` (no space) vs `City; Temp` (space) — the parser
  tolerates both by skipping an optional leading space in the temp field.
