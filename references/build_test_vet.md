
# V Project Structure, Modules, Build / Test / Vet

## v.mod format
```v
Module {
    name: 'myproject'
    description: '...'
    version: '0.1.0'
    license: 'MIT'
    dependencies: []
}
```
- `name` is the module root name; submodules use DOT separators in `import`.

## Project layout
### Flat (common for < 15 files)
```
myproject/
├── v.mod
├── main.v
├── handler.v
├── store.v
└── templates/
```
### Scaled (larger)
```
myproject/
├── v.mod
├── cmd/
│   └── server/main.v
├── internal/
│   ├── worldbank/      (module worldbank)
│   └── repository/     (module repository)
├── dbase/             (module dbase; imports db.sqlite)
└── templates/
```
- Module name in `module` line matches its directory (no hierarchy). Imports use
  the DOT path: `import internal.worldbank` — NOT `import internal/worldbank` (FAILS).

## Module system (most common early failure)
- Nested imports use **DOT** separators, never slashes.
- ONE `import` per line. Two imports on one line → `cannot import multiple modules`.
- `v run .` (module mode) compiles ALL `.v` files in the dir; a stray scratch file
  with a bad import breaks the whole build. Delete probes before `v run .`.

## Core rules (must know)
1. **Immutability by default** — `mut` only on fields in a `mut:` block or local vars.
2. **Only `for` loop** (no `while`). `for i < n {}`, `for i in 0..n {}`, `for v in arr {}`.
3. **Constants:** `const x = ...` one per line. Grouped `const ( ... )` is DEPRECATED.
4. **Strings single-quoted.** `s == ''` not `s.len == 0`.
5. **`!T` vs `?T` are SPLIT** (see master SYNTAX section).

## Build & Run
```bash
~/v/v run file.v                 # compile + run
~/v/v file.v                    # build executable
~/v/v -o bin/app cmd/server/main.v   # build to a path (use for veb templates cwd)
~/v/v -prod file.v              # optimized
~/v/v -g file.v                 # debug info
~/v/v -check .                  # syntax/type check a module (NOT `v -c`/`v check`)
# `v build-module` does NOT exist in 0.5.2 — use `v -o <name> <file>.v` or `v run .`
~/v/v cross   # cross-compile (when supported)
```
### Memory-management flags
- `-gc` / `-no-gc` / `-autofree` — autofree is experimental; usually leave default.

## vfmt / vet
```bash
~/v/v fmt -w .          # format in place
~/v/v fmt -w file.v
~/v/v vet .             # quality gate: every pub fn needs a `//` doc comment
```
- `v vet` requires `pub fn` doc comments that NAME the function, e.g.
  `// run_server starts the HTTP server`.

## Testing
```bash
~/v/v test .                    # all tests in project
~/v/v test path/to/dir/         # specific dir
~/v/v test path/to/file_test.v  # specific file
~/v/v -silent test .            # report only failures
```
- Test files: `xxx_test.v`; test fns named `test_xxx()`.
- Assertions: `assert cond`, `assert a == b`.
- Keep `data/` (SQLite db) dirs intact during iteration for debugging.

## Makefile template (common)
```make
.PHONY: build test fmt vet run

build:
	~/v/v -o bin/app cmd/server/main.v

run: build
	./bin/app

test:
	~/v/v -silent test .

fmt:
	~/v/v fmt -w .

vet:
	~/v/v vet .
```

## Environment variables
- `VFLAGS` — flags passed to every V invocation.
- `VEXE` — path to the compiler (useful in scripts/CI).
- `VMODROOT` — resolved to the vlib root (used by `@[alias]` shims like x/json2).

## Resources
- Official: https://vlang.io ; repo: github.com/vlang/v
- Compiler source (for reading): `~/v/vlib/...`
