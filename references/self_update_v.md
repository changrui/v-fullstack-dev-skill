# Self-update V program — reusable pattern

A V program that clones/pulls from GitHub, compiles, and replaces its own binary.
Written as a single `main.v` with no third-party dependencies.

## Source
`/home/iqdo/auto_update/main.v` (created 2026-07-22, auto_update project)

## Architecture

### ShResult struct wrapper (V 0.5.x pitfall avoidance)
Instead of `fn sh() (int, string)` multi-return (which causes `.0`/`.1` field access
errors when destructured), use a named struct:
```v
struct ShResult {
exit_code int
output    string
}
fn sh(cmd string) ShResult {
    res := os.execute(cmd)
    return ShResult{res.exit_code, res.output}
}
```
Then access as `r.exit_code`, `r.output` — no destructuring ambiguity.

### Compilation fallback chain (4 strategies)
1. `v -o <bin> <dir>/main.v` — single-file compile
2. `v -o <bin> <dir>` — directory-mode compile (multi-file)
3. `v build .` then copy from `build/<name>`
4. `v run -b .` then copy from `build/<name>`

### Update flow
1. Find project root via `git rev-parse --show-toplevel`
2. Safety check: `git status --porcelain` → abort if dirty (unless `--force`)
3. Backup old binary → `<bin>.bak` (never deletes)
4. Clone or pull from remote
5. Parse version from `v.mod`
6. Try compilation strategies in order
7. Run tests (non-fatal)
8. Replace binary, cleanup temp dir
9. On ANY failure: restore from `.bak`

### Flags
- `--dry-run`: print what would happen, no file changes
- `--force`: skip uncommitted-changes safety check
- `-h, --help`: usage info

## V 0.5.x specific pitfalls captured
- `time.now().str` is a FUNCTION REFERENCE, must call as `time.now().str()`
- `const ()` groups deprecated → use individual `const` or accept the warning
- Multi-return `fn() (A, B)` destructured with `:=` creates anonymous fields —
  accessing `.0` fails; use a named struct wrapper instead
- `println()` requires exactly 1 argument — `println('')` not `println()`
- `for i in 1 .. n` not `range(1, n)`
- `Option` (`?T`) uses `or {}` / `?` operator, NOT `.is_none()` / `.val`

## Key differences from vaiv_update.vsh
- This is a STANALONE binary (not a .vsh script)
- Uses `ShResult` struct instead of multi-return tuples
- 4 compilation strategies instead of 2
- More robust pull recovery (fetch + reset + re-clone fallback)
- Uses `cp -f` instead of `mv` for backup (preserves original)
