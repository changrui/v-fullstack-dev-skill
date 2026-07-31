# Splitting a single-file `module main` CLI entry into multiple files (V 0.5.2)

## When
A CLI entry `main.v` has grown too large and you want to split it into
`cli_report.v`, `cli_models.v`, `cli_repl.v`, etc. — all still `module main`.

## Hard constraints
- **V does NOT support the same module across subdirectories.** All `module main`
  files MUST live flat in the repo root (next to `v.mod`). You cannot put them in
  `src/` or `cmd/`. (The web entry `cmd/web/main.v` is a SEPARATE build target /
  separate module tree — leave it alone, it keeps `v -o bin/vaiv-web cmd/web`.)
- Cross-file functions are globally visible within the same `module main` — no
  visibility modifiers needed. Splitting is purely cosmetic for the linker; there
  is NO namespace isolation, just shorter files + easier parallel editing.

## The build-command change (the real gotcha)
Compiling a single file `v -o bin/vaiv main.v` **FAILS** once siblings exist:
```
main.v:3:10: error: unknown function: helper
...
If the code of your project is in a folder with multiple .v files, try `v .` instead of `v main.v`
```
You MUST switch to directory compilation: `v -o bin/vaiv .`

## Propagation checklist (easy to miss)
After splitting, grep the WHOLE repo for the old single-file build command and
update EVERY occurrence. Builds break silently for users/CI still using the old
command. Typical spots in a vaiv-style project:
- `AGENTS.md` / `README.md` / `README_zh.md` / `agents.md` build sections
- `scripts/*.vsh` that recompile the CLI (self-update, install, deb build)
- **Do NOT touch** `cmd/web/main.v` references — web uses `v -o bin/vaiv-web cmd/web`

Verification that no CLI build command still points at the old file:
```sh
grep -rn "bin_vaiv.*main\.v\|v -o .*main\.v" . | grep -v "cmd/web/main.v"
# expect: no CLI build commands remain referencing main.v
```

## import hygiene
After moving functions between files, each file must import only what it uses.
`v .` only EMITS WARNINGS (not errors) for unused imports, but `v vet .` is clean
and a tidy build has zero warnings. Drop unused `import time` / `import x.json2`
blocks. Build with `v -o bin/vaiv . 2>&1` and watch for:
```
warning: module 'X' is imported but never used. Use `import X as _`, to silence this warning, or just remove the unused import line
```

## End-to-end verify after split
1. `v fmt -w .` → clean
2. `v vet .` → zero warnings
3. `v -o bin/vaiv .` → zero warnings, exit 0
4. Run the CLI's key subcommands (config, models, `!cat` paging, sessions,
   selfissues, export) to confirm every split file's code path executes. Each
   subcommand hits a different split file, so this exercises the whole split and
   catches any missed cross-file reference.
