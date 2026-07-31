# V C FFI — mmap, SIMD, and Low-Level System Calls

Demonstrates V's C interop for performance-critical code: memory-mapped I/O, SIMD float parsing, and multi-threaded aggregation.

## When to load
- Task involves V calling C syscalls (mmap, pthread, etc.)
- Need to bridge V ↔ C for performance-critical code paths
- Working on competitive programming / algorithm challenges in V

## Prerequisites
- V 0.5.x+ compiler at `~/v`
- GCC/Clang installed on the system
- C source file compiled to `.o` before V compilation

## 1. Including C Headers

```v
#include <sys/mman.h>
// or for local headers:
#include "my_lib.h"
```

`#include` at the top of a `.v` file injects `#include` directly into the generated C code. This is the ONLY way to include C headers in V 0.5.x.

**Key point:** `#include` goes at the TOP LEVEL of the `.v` file, NOT inside `#[...]` attributes. V 0.5.x does NOT support `#[include: '...']` syntax.

## 2. Declaring C Functions

```v
// Syntax: fn C.func_name(params) ReturnType
// NO colon before return type! NO named params with `:` syntax!
fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr
fn C.munmap(addr voidptr, len u64) i32
fn C.mlock(addr voidptr, len u64) i32
```

**CRITICAL syntax rules:**
- Return type has NO colon: `voidptr` not `: voidptr`
- Parameters use `name type` (named) or just `type` (unnamed) — BOTH work
- C functions are accessed via `C.` prefix: `C.mmap(...)`
- For variadic C functions: use `...int` for the variadic part

## 3. Linking External C Code — TWO Working Methods

### Method A (RELIABLE): `#include` the C source + `@[c_extern]` declaration
This is the method that ACTUALLY works in V 0.5.x. `#flag ./x.o` does
NOT link (it silently fails with "cannot call a function that does not have a
body"). Instead, embed the C source directly into the generated C:

```v
#include <sys/mman.h>
#include "/abs/path/to/c_simd.c"   // absolute path, NOT relative

fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr
fn C.munmap(addr voidptr, len u64) i32

// The C definition comes from the #include above. @[c_extern] tells V that
// this symbol is provided by external C (already defined), so V does NOT emit
// a stub for it.
@[c_extern]
fn C.simd_parse_float_fast(buf &u8, len int) f32
```

Then call it as `C.simd_parse_float_fast(addr + pos, len)` inside `unsafe {}`.

### Method B (fragile, usually fails): `#flag` object linking
```v
#flag ./c_simd.o          // <-- does NOT link in 0.5.2; symbol stays undefined
fn simd_parse_float_fast(buf &u8, len int) f32
```
Empirically `#flag /abs/c_simd.o` and `#flag @VMODROOT/c_simd.o` BOTH fail
to link on this build. Prefer Method A.

**Compile sequence (Method A):**
```bash
# No separate gcc step needed — the .c is #included and compiled by V's gcc pass
v -cc gcc -cflags '-O3 -march=native -ffast-math' -o bin/app main.v
```

## 3b. CRITICAL: C signature must match V's generated pointer type
V declares `&u8` as `unsigned char*` in generated C. If your `.c` function
uses `const unsigned char*`, the C compiler errors with:
```
conflicting types for 'simd_parse_float_fast'; have 'f32(u8*, int)'
  previous definition with type 'float(const unsigned char*, int)'
```
**Fix: drop `const` in the C signature** → `float simd_parse_float_fast(unsigned char* buf, int len)`.
Also keep the `.h` declaration in sync (same non-const signature).

## 4. Casting void* to V Types

```v
// Cast C mmap return to V byte pointer
data := unsafe { cast(&u8 addr) }
```

`void*` from C must be cast via `unsafe { cast(Type ptr) }`. V 0.5.x does NOT allow direct `void*` → slice conversion.

**Common casts:**
- `&u8` — pointer to byte (for mmap'd data)
- `&char` — pointer to char (for C strings)
- `voidptr` — opaque pointer (pass back to C)

## 5. Platform Conditionals

```v
$if windows {
    // Windows-only code
} $else {
    // Unix/POSIX code
}
```

V 0.5.x uses `$if` for compile-time platform conditionals, NOT `#[cfg(...)]` attributes. Available conditionals: `$if windows`, `$if linux`, `$if macos`, `$if freebsd`, `$if openbsd`, `$if darwin`, `$if amd64`, `$if x64`, `$if tinyc`.

## 6. Mmap Pattern (Complete Recipe)

```v
#include <sys/mman.h>

fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr
fn C.munmap(addr voidptr, len u64) i32

const prot_read = 1
const map_shared = 0x01

fn mmap_file(path string) (&u8, int, voidptr) {
    fd := os.open_file(path, 'rb') or { panic('Failed: ' + path) }
    file_size := os.file_size(path)
    
    addr := C.mmap(voidptr(0), file_size, prot_read, map_shared, fd.fd, 0)
    if addr == 0 || addr == -1 { panic('mmap failed') }
    
    C.mlock(addr, file_size)  // Pin to memory
    fd.close()  // Close fd — mmap keeps mapping alive
    
    data := unsafe { cast(&u8 addr) }
    return (data, file_size.int, addr)
}
```

## 7. Calling C from V — Common Pitfalls

| Mistake | Fix |
|---------|-----|
| `fn C.mmap(...): voidptr` (colon before return) | Remove colon: `fn C.mmap(...) voidptr` |
| `#[cfg(unix)]` | Use `$if unix { }` instead |
| `#[include: '...']` | Use bare `#include '...'` at top level |
| `#[link: './lib.a']` | Use `#flag ./lib.a` instead (but see §3: `#flag x.o` does NOT link — use `#include`+`@[c_extern]`) |
| `data[pos]` on `&u8` pointer | Wrap in `unsafe { name[i] }` |
| `while cond { }` | Use `for cond { }` (V has no `while`) |
| `2166136261_u32` | Use `2166136261u` or cast with `.int` |
| Keyword args in C calls | Use positional: `C.mmap(voidptr(0), ...)` |
| `byte` type | Use `u8` (byte is deprecated in 0.5.2) |
| `MAX_CITIES` const name | Use `max_cities` (snake_case only) |
| `2166136261.uint` method call | Use `2166136261u` literal or `int(uint_val)` |
| `fn simd_...(buf &u8, len int) f32` (no C def) | Link fails: use `#include "x.c"` + `@[c_extern]` decl, NOT `#flag x.o` |
| C func uses `const unsigned char*` | Drop `const` → `unsigned char*` (conflicts with V's `u8*` = `unsigned char*`) |
| `f64.str(1)` / `f32.str(1)` | NO decimal arg in 0.5.2! Use `math.round(v*10)/10` + `int.str()`, or hand-roll fmt |
| `simd_parse_float_fast` "no body" | You used `#flag x.o` — switch to `#include "x.c"` + `@[c_extern]` |
| mmap with `C.NULL` vs `voidptr(0)` | Both work; `voidptr(0)` is fine, but `C.NULL` is clearer |
| Capturing city name at `\n` using `i - city_len` | `i` already past `;` — capture at `;` branch: `city = tos(addr+city_start, city_len)` |

## 8. Thread Communication Pattern
