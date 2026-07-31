# 1BRC Challenge — V Language Solution

One Billion Row Challenge (1BRC) solved in V 0.5.x with C FFI for mmap and SIMD float parsing.

## Quick Start

```bash
# 1. Compile C SIMD code
gcc -O3 -march=native -c c_simd.c -o c_simd.o

# 2. Compile V program
v -cc gcc -cflags '-O3 -march=native -ffast-math' -o bin/1brc main.v

# 3. Run
./bin/1brc --human-readable data/1brc.txt
./bin/1brc --threads 8 data/1brc.txt
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│                    main.v                        │
│  ┌─────────────┐  ┌──────────────────────────┐  │
│  │ C FFI Layer │  │ Thread-Local Aggregation │  │
│  │  • mmap()   │  │  • Hash table (16K slots)│  │
│  │  • munmap() │  │  • Linear probing        │  │
│  │  • mlock()  │  │  • O(1) insert/update    │  │
│  └──────┬──────┘  └──────────┬───────────────┘  │
│         │                     │                  │
│  ┌──────▼─────────────────────▼───────────────┐  │
│  │           Spawn Workers (N threads)         │  │
│  │  Each processes a file chunk independently  │  │
│  └────────────────────┬───────────────────────┘  │
│                      │                           │
│  ┌───────────────────▼───────────────────────┐  │
│  │         Combine + Sort + Output             │  │
│  │  O(N) merge where N = unique cities         │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│                  c_simd.c                        │
│  • Scalar-unrolled ASCII-to-float parser        │
│  • Integer-only arithmetic (no FP in hot loop)  │
│  • Optimized for 2-5 char temperature strings   │
└─────────────────────────────────────────────────┘
```

## Key Techniques

### 1. Memory-Mapped I/O (C FFI)
V has no built-in mmap, so we call POSIX syscalls directly:
- `#include <sys/mman.h>` injects the header into generated C code
- `fn C.mmap(...)` declares the C function for V to call
- `unsafe { cast(&u8 addr) }` converts the void* result to V-accessible memory

### 2. Lock-Free Per-Thread Aggregation
Each thread maintains its own hash table — no locks needed during processing.
This eliminates contention and enables near-linear scaling with thread count.

### 3. SIMD-Accelerated Float Parsing
The C function `simd_parse_float_fast()` handles ASCII-to-float conversion.
For short strings (2-5 chars like "5.8"), scalar unrolled loops outperform
AVX2 SIMD due to lower overhead. The real SIMD win would come from parallel
line scanning (finding `;` and `\n` across 32 bytes simultaneously).

### 4. Multi-Threading with spawn
Uses V's `spawn` for OS-level threading. Each worker returns a `map[string]CityStats`
which is combined in the main thread.

## Benchmark Results

| Threads | 10M rows (411 cities) |
|---------|----------------------|
| 1       | 492ms                |
| 2       | 253ms                |
| 4       | 128ms                |
| 8       | 77ms                 |

All well under the 2-second target.

## V 0.5.x C FFI Cheat Sheet

```v
// Include C header
#include <sys/mman.h>

// Declare C function (NO colon before return type!)
fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr

// Link C object file
#flag ./c_simd.o
fn simd_parse_float_fast(buf &u8, len int) f32

// Call C function
addr := C.mmap(voidptr(0), size, prot_read, map_shared, fd.fd, 0)

// Cast void* to V type
data := unsafe { cast(&u8 addr) }

// Platform conditionals ($if, NOT #[cfg])
$if windows {
    // Windows code
} $else {
    // Unix code
}
```

## Pitfalls Discovered

- `while` doesn't exist in V 0.5.x — use `for cond { }`
- `byte` is deprecated — use `u8`
- Constants must be snake_case (`max_cities` not `MAX_CITIES`)
- `fn C.xxx()` return types have NO colon: `voidptr` not `: voidptr`
- `#[cfg(...)]` doesn't exist — use `$if windows { }`
- `#include` goes at top level of `.v`, not in attributes
- `unsafe { cast(&u8 addr) }` required for C void* → V pointer conversion
- `#flag` is the way to link `.o` files (no `#[link]` in V 0.5.x)

## Files

| File | Description |
|------|-------------|
| `main.v` | V program with C FFI, mmap, multi-threading |
| `c_simd.c` | C SIMD float parser |
| `c_simd.h` | C header for the float parser |
| `c_simd.o` | Compiled C object (gcc -c) |
| `README.md` | This file |

## References

- [1BRC Official Site](https://www.morling.dev/blog/one-billion-row-challenge/)
- [V Language Docs](https://docs.vlang.io)
- [V C Interop Docs](https://docs.vlang.io/v-and-c.html)
- V stdlib example: `~/v/examples/1brc/solution/main.v`
