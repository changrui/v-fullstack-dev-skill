
# Go → V Porting with go2v

Go→V is feasible but NOT 1:1 mechanical. The official `go2v` translator is a
**draft generator**, not a translator: it nails syntax skeletons (option types,
rune iteration, multi-return signatures, type casts) but fails on standard-library
API mapping and all semantic differences (context, any, sync, os/path, regex/bufio).
Rewrite (not fight go2v) where it doesn't pay off.

## TL;DR decision rule
1. Classify every Go module first (A/B/C). Don't blindly run go2v on all.
2. **A — pure logic (only stdlib strings/math/json, no ctx/any/sync/ospath):** run
   go2v, expect 1–4 small fixes. High ROI.
3. **B — has context/sync/os/path/regex/bufio:** go2v output mostly wrong per line —
   faster to NATIVE-REWRITE using V stdlib.
4. **C — depends on unported internal modules:** block until deps ported.
5. go2v NEVER helps with semantic load (context.Context, `any` ubiquity,
   select/timeout, generics). That cost is fixed regardless of tooling.

## go2v install + usage (verified 2026-07)
go2v is a V program that shells out to the Go tool `asty` to build a Go AST JSON.
```bash
# 1. clone + build go2v (needs `go` on PATH; go1.22+ works)
git clone https://github.com/vlang/go2v /tmp/go2v
cd /tmp/go2v && ~/v/v .        # builds ./go2v binary

# 2. asty is auto-installed on first run, BUT default GOPROXY times out behind
#    some networks — pre-install with direct proxy:
export PATH=$PATH:/home/iqdo/go/bin
GOPROXY=direct go install github.com/asty-org/asty@latest

# 3. translate a SINGLE .go FILE (NOT a dir — a dir triggers test-compare mode
#    that needs a .vv expected-output file you don't have):
/tmp/go2v/go2v /abs/path/to/file.go     # writes file.v next to file.go
```
- Passing a **directory** makes go2v look for `<dir>/<name>.vv` expected output and
  compare — that's the CI test path, not ad-hoc ports.
- go2v writes `.v` next to the `.go` (same dir). Move it into your V module tree.
- Output is unformatted (no spacing before `{`). Run `v fmt -w file.v` after fixes
  if desired (harmless; go2v skips vfmt to preserve `Type{` spacing).

## V syntax/runtime checks (correct commands)
- Check a module/dir: `v -check .`  (NOT `v -c`, NOT `v check` — both wrong)
- Build a single module: `v -o <name> <file>.v` (note: `v build-module` does NOT exist in 0.5.2)
- Run: `v run .` from a dir with `main.v` + imported modules as subdirs.

## The Go→V pitfall table (real, from porting covonaut 65k LOC)
These are SYSTEMATIC — go2v gets some wrong, you must fix all manually:

| Go | V | Note |
|----|---|------|
| `if x := f(); cond` | `x := f() or {}; if cond` | V has no short-decl in if |
| `strings.Index(s,sub)` → `-1` | `s.index(sub) or { -1 }` | V returns `?int` |
| `s.Replace(old,new,1)` (first only) | `idx:=s.index(old) or{-1}; if idx>=0 { s[..idx]+new+s[idx+old.len..] }` | V replace() takes 2 args (all) |
| `var b strings.Builder; b.Grow(n)` | `mut b := strings.new_builder(n)` | V has no Grow(); size at creation |
| `line.TrimRightFunc(unicode.IsSpace)` | `line.trim_right(' \t')` | V has no TrimRightFunc |
| `arr2 = arr1` (slice/array) | `arr2 = arr1.clone()` | V forbids raw array assign (ownership) |
| `a, b = b, a` (arrays) | `mut t:=a.clone(); a=b.clone(); b=t` | V forbids swap of arrays |
| `err.Error()` / `ie.Error()` | `err.str()` | IError has no `.error_()` / `.msg` |
| `any` (type) | `json2.Any` or concrete type | go2v emits bogus `components.Any` |
| `context.Context` param | drop it; pass cancellation via `chan`/struct flag | V has a `context` module at `vlib/context/` (basic Context interface, cancel/deadline/value) but it's NOT compatible with Go's context — redesign anyway |
| `sync.Mutex` `mu.Lock()`/`Unlock()` | `mu.lock()` / `mu.unlock()` | go2v emits `lock_()`/`unlock_()` — WRONG |
| `map[string]&T` + index assign | use `&T` carefully; `m[k] or { ... }` | V map of refs is finicky |
| `path/filepath.{Abs,Dir,Base,Join,Clean}` | `os.{abs_path,dir,base,join_path}` (no EvalSymlinks) | `path.filepath` does NOT exist in V |
| `os.ReadFile` → `([]byte, error)` | `os.read_file(p) !string` (returns `!`) | V uses `!`/Result, not tuple |
| `os.WriteFile(p, []byte, 0644)` | `os.write_file(p, data.bytestr())` | 2nd arg is `string`; `[]u8`→string via `.bytestr()` |
| `os.MkdirAll(p, 0755)` | `os.mkdir_all(p, os.MkdirParams{})` | 2nd arg is a struct, not mode int |
| `bufio.NewScanner(r)`+`.Scan()/.Text()` | `r.split_lines()` or `strings.split_lines()` | V has NO bufio |
| `regexp.MustCompile(p)`+`.MatchString` | `import regex.pcre`; `re := regex.pcre.compile(p) or { panic(err) }`; `re.find(s) ?Match` | V regex is pcre-backed |
| `for _, v := range slice` | `for v in slice` | V ranges directly |
| `for i, r := range s` (runes) | `for r in s.runes()` or `for r in s` | V iterates runes on string directly |
| `make([]T, n)` | `[]T{len: n, init: zero}` or `[]T{cap: n}` | V uses struct-literal init |
| closure `[mut x]() { x << .. }` collecting | DOES NOT SYNC BACK (copy semantics) | use return value / struct field / chan |
| `'... $var ...'` (single-quote) | interpolation `$var` only in `"..."` | single-quote is a raw string in V |
| unused var / `_ = x` | V errors on unused at `-prod`; use the var or `_ :=` | V stricter than Go |

## Workflow (proven on covonaut 8-leaf batch)
1. Classify modules (table above). Separate A / B / C.
2. A-class: `go2v file.go` → move `.v` into `vlib/<mod>/` → `v -o <name> <file>.v` (note: `v build-module` does NOT exist) → fix the 1–4 stdlib mappings → `v -check .`.
3. B-class: do NOT patch go2v output line-by-line. Write a clean V module using
   V stdlib (sync, os, regex.pcre, strings) — reference go2v output only for
   structure/field names. Verify with `v run .` + a small main.
4. C-class: leave a `.bak`/stub, record the blocking dependency, move on.
5. Write one `main.v` that imports all ported modules and asserts behavior — this
   is your integration test (catches cross-module signature drift).
6. Keep originals: never delete the `.go`; if replacing, rename `.bak` (user pref).
7. Update the port plan doc with per-module status + the specific fixes applied.

## What go2v gets RIGHT (keep)
- `x.index(s) or { -1 }` option conversion
- `for r in s` rune iteration
- multi-return `(T1, T2, bool)` fn signatures
- `return i64(x)` / `i64(idx)` numeric casts
- `strings.new_builder` detection
- struct field ordering, const blocks, basic control flow

## Gotchas from the real port (covonaut, 2026-07)
- 8 "leaf" modules turned out to be only 5 actually-leaf — 3 imported `agentcore`
  (an unported 7.8k-LOC core). Always grep internal imports before claiming leaf.
- go2v on `filequeue` (sync+os+path) produced ~every line wrong; native rewrite took
  LESS time than patching. Same for `components` (context+any interfaces).
- V closure capture `[mut x]` is COPY — a `with_file(path, fn [mut content]()! { ... })`
  does NOT propagate `content` back out. Inline, or pass a `mut struct` arg, or
  return via a struct field. (Verified — cost a debug cycle.)
- `v run .` swallows module-level warnings; use `v -o /dev/null main.v` to see clean errors (note: `v build-module` does NOT exist in 0.5.2).

## Strategy recommendation (for the user)
A full 1:1 port of a large framework is man-months and creates permanent dual-
maintenance. Prefer **V-native reimplementation of the architecture** for the core,
and use go2v only to accelerate A-class leaf modules into a vlib base layer.
