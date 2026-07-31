# V 0.5.2 Compile-Time Pitfalls (live-hit bank)

Consolidated from the csv2mysql build session. These are *compile* errors that
bit real code — keep them next to `syntax.md`. Each entry: symptom → fix.

## Module / build layout
- **No `src/` directory in modern V.** Library-module `.v` files go directly in
  the project root — OR in a named submodule dir (e.g. `./csv2mysql/`) with
  `v.mod` at root and a `module main` entry (`main.v`) at root that
  `import csv2mysql`. Either way: NO `src/` wrapper. This was corrected by the
  user twice; honor it.
- **Build a multi-file module with `v .`**, not `v file.v`. Compiling a single
  `.v` while other `.v` files sit in the dir yields
  `project must include a main module` and `unknown function` cascades.

## Types & mutability
- `byte` is **deprecated** → use `u8`. (`separator byte = ','` fails.)
- **`mut` args only for arrays/maps/structs/pointers.** Scalar `mut err_msg string`
  / `mut total int` is ILLEGAL. Pass `&string` / `&int` and write via pointer
  inside `unsafe { *p = x }`. Deref-assignment (`*total += n`) MUST be in `unsafe{}`.
- **Struct fields default immutable.** A field you reassign on a `mut` local
  (e.g. `opt.truncate = true`, `cfg.table = 'x'`) must live in a `mut:` section,
  not `pub:`. `pub:` fields are also immutable. Put runtime-set fields in `mut:`.
- **`unsafe` blocks cannot be nested.** `data := unsafe { ([]u8(unsafe { &u8(a) }))[0..n] }`
  errors with "already inside unsafe" — collapse to one: `([]u8(unsafe { &u8(a) }))[0..n]`.

## Integer / float literals
- FNV-style const `2166136261u` is ILLEGAL → write `u32(2166136261)`. Same for
  `16777619u` → `u32(16777619)`.

## String interpolation
- **NO format specifiers** like `${x:>7}` or `${x:.2f}`. They break the parser.
  Pad manually (`for s.len < 7 { s += ' ' }`) and cast to int for display
  (`ms := int(elapsed_ms)`).

## Channels
- **No `close(chan)` builtin.** Drain with `<-ch` in a loop; the channel is GC'd.
  A two-channel pattern (work `chan T` + done `chan int`) avoids needing `close`.
- `chan` carries ONE type. To fan out work AND collect completions, use two
  channels (e.g. `work_ch chan Chunk`, `done_ch chan int`).

## Struct naming
- Non-builtin struct names MUST start with a capital letter. `struct chunk` → `Chunk`.

## stdlib API gotchas (this V build)
- `db.exec_none(q)` returns **`int` (rc), not `!`/Option**. Check `if db.exec_none(q) != 0 { ... }`.
  `or {}` on it is a compile error.
- `os.File.writeln(s)` returns **`!int`** → must end with `or {}` (or `!`).
- **`os.getenv(k)` returns a plain `string`** (empty if unset) — NOT a Result.
  `os.getenv(k) or { ... }` is a compile error. Guard with `if v == ''`.
- **`os.read_bytes(path)` returns `![]u8`** (use `!`); but `f.read_bytes(n)` on an
  open `os.File` returns a plain `[]u8` (NO `!`). Mixing these up → "does not
  return a Result" / "no value" cascades.
- **`string(byte_slice)` is ILLEGAL** → `byte_slice.bytestr()`.
- **`f64(i64_val) / 1000.0`** — wrap the numerator in `f64()`, else an
  `i64 / f64-literal` type mismatch surfaces on `elapsed_ms` (ImportResult field).
- **`for {}` infinite loop** needs a `return` AFTER the loop (even unreachable) or
  the checker errors "missing return at end of function" (e.g. open-addressing
  hash set `contains`/`insert` probe loops → add `return false`).
- **Cross-module setters:** fields a `main` module reassign must be `pub mut:`
  (plain `mut:` is module-private → "field is not public" from another module).
  Fns called from `main` must be `pub`.
- `os.File.fd` is NOT accessible from user code → for `mmap` open the fd yourself
  via `C.open(&char(path.str), 0, 0)` (declare `fn C.open(...)`), and `C.close(fd)`.
- **`arr.join(sep)` METHOD exists** (e.g. `cells.join(', ')`); the free fn
  `strings.join(arr, sep)` does NOT exist in this build → use the method or a
  local helper. Same for `col_list.join(', ')`, `defs.join('\n  ')`.
- `os.execute('nproc')` is a workable `cpu_count()` stand-in (no stdlib `cpu_count`
  in 0.5.2); parse the int from `out.output`.

## C FFI mmap pattern (this build) — WORKING recipe
- Include `<fcntl.h>`, `<sys/mman.h>`, `<unistd.h>`, `<string.h>`; declare
  `fn C.open(path &char, flags i32, mode i32) i32`, `fn C.close(fd i32) i32`,
  `fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr`,
  `fn C.munmap(addr voidptr, len u64) i32`, `fn C.madvise(addr voidptr, len u64, advice i32) i32`,
  `fn C.memcpy(dst voidptr, src voidptr, n u64) voidptr`.
- **Pointer→`[]u8` cast does NOT work** (bit real code for ~6 iterations):
  `[]u8(addr)`, `&u8(addr)`, and `([]u8(&u8(addr)))[0..n]` ALL fail at C level
  with `conversion to non-scalar type requested`; `x := &u8(p); x[0..n]` errors
  "`&u8` does not support slicing". The ONLY working idiom:
  ```v
  mut data := []u8{len: size}
  C.memcpy(data.data, addr, u64(size))
  ```
  Allocate a V-owned array and copy the mapped bytes in. (For true zero-copy you'd
  refactor the parser to consume a `(&u8, len)` pair instead of `[]u8` — not done
  here.) Keep `addr`/`fd` for `munmap_file(addr, size, fd)`.
- `const prot_read = 1 // PROT_READ`; `const map_private = 0x02 // MAP_PRIVATE`;
  `const madv_willneed = 3`; `const o_rdonly = 0`. `C.mmap(voidptr(0), u64(size),
  prot_read, map_private, fd, i64(0))` — the 6th arg MUST be `i64(0)`, not `0`
  (bare `0` infers `void` → "expression does not return a value").
- `mmap_file` returns `(data []u8, addr voidptr, size int, fd int)`; caller does
  `data, addr, size, fd := mmap_file(path)!` then `defer { munmap_file(addr, size, fd) }`.
- SIMD C file: `#include "simd.c"` at top of the `.v` (relative path; absolute
  path breaks once the module is moved); declare `fn C.simd_...(buf &u8, len int) int`.
- **HARD LIMIT — `[]u8.len` is a 32-bit `int` (max 2,147,483,647 bytes ≈ 2.0 GiB).**
  Any file larger than ~2.0 GiB CANNOT be held in a single `[]u8`: `os.read_bytes`
  and `mmap` both overflow. Concretely: `mmap.v` does `size := int(fi.size)` and
  for a 3.8 GB file this panics `int(3991756610) cast results in -303210686`
  (negative). Likewise `medium` path `full := os.read_bytes(path)` can't represent
  a >2 GiB buffer. To handle >2 GiB you MUST stream: open the file and process it
  in bounded `[]u8` windows (e.g. read N MB at a time via `os.open_file`+`seek`+
  `read_bytes(N)`), or access mmap'd memory through the raw `voidptr` + offset with
  a hand-rolled cursor instead of wrapping it in a `[]u8`. Until then, keep test
  CSVs ≤ 2.0 GiB; a 2.25 M-row × 30-col file is ~2.0 GiB and is the safe ceiling.
- **DDL duplicate-column bug:** when adding a synthetic `id` PK, the inferred-CSV
  column already named `id` must be SKIPPED in the column loop, else MySQL errors
  on a duplicate `id` column. General rule: synthetic-PK columns must be excluded
  from the inferred-column definitions.
- **Multi-statement DDL via `exec_none` fails:** `db.exec_none("DROP...; CREATE...;")`
  sends the whole string through `mysql_query`, which (without the
  `client_multi_statements` flag) executes only the FIRST statement and/or errors
  → later "create table failed". Fix: run each `;`-separated statement
  separately (e.g. `exec_ddl` that splits on `;` and calls `exec_none` per
  statement). Single-statement INSERTs/SELECTs are fine with `exec_none`.
  `mysql.DB.query(q)` has the same first-only-statement behavior for
  multi-statement strings.
- **MySQL `BOOLEAN` = `TINYINT(1)`:** inserting the quoted text literal `'true'`
  fails in strict mode with `Incorrect integer value: 'true' for column ...`.
  Render booleans as raw `1`/`0` (unquoted) — add a `bool_literal(cell)` helper
  mapping true/1/yes/on→`1`, else `0`, empty→`NULL`. A SELECT reads the column
  back as the string `"1"`/`"0"`, not `"true"`.
- **Channel deadlock (medium/large fan-out):** V 0.5.2 has NO `close(chan)`. If
  workers `for { c := <-work_ch or { break } }` and the producer never closes
  the channel, workers block forever on the receive and the main drain loop
  blocks too → silent hang (connections sit `Sleep` in `SHOW PROCESSLIST`).
  Fix: send one **sentinel** per worker after all real items (e.g. `Chunk{start:-1}`
  or `ch <- 0`), and have each worker `break` on the sentinel. For the
  single-range worker pattern (`large_worker` imports one [s,e) and sends exactly
  one completion), ensure every error `return` path ALSO sends on the completion
  channel before returning, or main deadlocks waiting for that one value.
- **`os.File.seek` + `read_bytes` chunking bug:** `read_chunk` via
  `os.open_file(p,'rb'); f.seek(start,.start)!; f.read_bytes(end-start)` returned
  bytes from offset **0**, not `start` (the header leaked into chunk 0, +1 row per
  chunk). The byte COUNT was correct but the OFFSET was wrong. Fix: instead of
  re-reading per chunk, read the whole file ONCE with `os.read_bytes(path)` and
  hand the `[]u8` to workers so they slice `full[c.start..c.end]` — exact and
  faster. (If you must seek, verify the seek actually moved; prefer the slice.)
- **Large-path row index off-by-one:** when building a record-start index, init
  it with the FIRST real record start (`hp`, after the header), NOT `0`. Starting
  at `0` makes worker 0 parse the header line as a data row → +1 imported row, and
  the count `total_records = row_starts.len - 1` then mis-sizes the segments.
  Init `row_starts := [hp]` so `row_starts[0]` is the first data record.
- **`time.Time.unix` / `.unix_milli` are PRIVATE fields.** `f64(time.now().unix)` or
  `time.now().unix_milli` FAILS to compile ("field `time.Time.unix` is not public"
  / "cannot use ... as `fn () i64`"). For elapsed time use `time.new_stopwatch()`
  then `sw.elapsed().milliseconds()` (also `.microseconds()` / `.nanoseconds()`).
  Do NOT hand-roll epoch math from `time.now()`.
- **Two `module main` files in one dir break `v .`.** A second `module main` entry
  (e.g. a benchmark/test harness) placed next to the project's `main.v` makes
  `v .` fail. Put extra runnable harnesses in a `tools/` (or sub) directory so
  `v .` still builds; run them with `v run tools/foo.v` (module import resolution
  walks up to the project `v.mod`).

## Debug-loop traps (csv2mysql build/verify session)
- **Stale-binary confusion:** `v` prints a `v hash: <hex>` that is the COMPILER
  version hash, NOT a source hash. After editing `.v` files the hash stays
  identical even though the binary changed. If a failure "doesn't go away" after
  a fix, don't trust the hash — `rm -f <binary>` then rebuild, confirm the file
  mtime advanced, and re-run. A bad edit can also leave the OLD binary in place
  (build aborted) so the next run silently executes stale code.
- **Live-MySQL authorization:** `csv2mysql import` / `bench` / `selftest` perform
  real DROP/CREATE/INSERT/SELECT against MySQL. Treat them as destructive DB
  operations — do NOT run them (or the `mysql` CLI against the same DB) without
  the user's explicit go-ahead. For benchmarks prefer small datasets
  (1–10×10⁴ rows) and a throwaway test table; the `small` (single-threaded,
  all-in-memory) tier is genuinely slow on 10⁵+ rows, so size the dataset to fit
  the timeout.

## Correctness & deadlock debugging playbook (chunked/parallel CSV→DB)
These are the *diagnostic steps* that found the bugs above — reusable for any
tiered/chunked importer, not just MySQL.

- **Row-count cross-check is the definitive correctness gate.** For a CSV with a
  header, expected data rows = `wc -l file - 1`. After importing under EVERY
  strategy, assert each table's `COUNT(*)` equals that number. If tiers disagree
  (e.g. small=100000, medium=101096, large=100001) the importer is WRONG, not the
  data — bisect:
  1. Full-buffer single-pass parse count (authoritative ground truth).
  2. Per-chunk parse count (does any chunk over/under-count?).
  3. `buf.len` of each chunk vs the expected `end-start` (catches a seek/offset
     bug even when the byte COUNT looks right — the offset can still be 0).
  4. Parse the EXACT same byte range as a `full[a..b]` slice vs the worker's
     `read_chunk(a,b)` — if the slice is correct but the worker is off, the
     read path (not `parse_record`) is the culprit. Prefer slicing `full` over
     re-reading per chunk.
- **Deadlock vs. slowness (silent hang).** If the process runs >2× expected and
  produces nothing: `SHOW PROCESSLIST` (or `ps`). If all its DB connections show
  `Command=Sleep` with NO active query AND CPU ≈ 0%, it is BLOCKED, not working
  — almost always a channel deadlock (missing `close`/sentinel, or an error path
  that `return`s without sending its completion value). If connections show an
  active `Query`, it's genuinely slow (tune batch/workers). A process that's
  CPU-bound-but-wrong is a parse bug; one that's idle-and-wrong is a sync bug.
- **Discipline that prevents both classes:** (a) every fan-out worker must receive
  exactly one termination signal (sentinel value or `close`) AND every error path
  must still send its completion before `return`; (b) row-start / chunk-boundary
  indexes must be initialized to the FIRST REAL record start (after the header),
  never `0`; (c) when re-deriving boundaries, confirm the boundary is a true
  record start (post-`\n`), not a mid-field position.
