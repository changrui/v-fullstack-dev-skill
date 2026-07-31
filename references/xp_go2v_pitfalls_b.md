# go2v Pitfalls — condensed mapping table

Verified during a real port of `github.com/covoyage/covonaut` (93k LoC Go) to V
0.5.2. go2v handles Go *syntax* (option `or {}`, rune iteration, multi-return
signatures, type casts) well but mangles *standard-library API names*. Every row
below is a real compile error go2v emitted and its fix.

## API mapping (Go → V 0.5.2)

| Go (go2v emits) | V fix | Note |
|---|---|---|
| `strings.Builder{}; b.Grow(n)` | `strings.new_builder(n)` | no `.grow`; pre-size only |
| `b.WriteString(s.TrimRightFunc(unicode.IsSpace))` | `b.write_string(s.trim_right(' \t'))` | `trim_right_func` DNE |
| `prev, curr = curr, prev` | `mut t := prev.clone(); prev = curr.clone(); curr = t` | array swap forbidden |
| `s.Replace(old, new, 1)` | `idx := s.index(old) or {-1}; if idx>=0 { s[..idx]+new+s[idx+old.len..] }` | V replace has 2 args (all) |
| `s.runes` | `s.runes()` | missing parens |
| `err.Error()` / `err.error_()` | `err.str()` | IError has no `.error_()` |
| `mu.Lock()` / `mu.Unlock()` (go2v→`lock_()`) | `mu.lock()` / `mu.unlock()` | drop underscore |
| `path/filepath.Abs/Dir/Base/Join` | `os.abs_path/os.dir/os.base/os.join_path` | module DNE in V |
| `bufio.NewScanner(r)` + `.Scan()/.Text()/.Err()` | `for line in s.split_lines()` | no bufio |
| `regexp.MustCompile(p)` | `regex.regex_opt(p) or { ... }` (or `import regex.pcre`) | different API |
| `os.WriteFile(p, data, 0o755)` | `os.write_file(p, data.bytestr())` | 2nd arg is string; `[]u8`→`.bytestr()` |
| `os.MkdirAll(p, 0o755)` | `os.mkdir_all(p, os.MkdirParams{})` | 2nd arg is struct |
| `map[string]any{...}` | `map[string]json2.Any{...}` or concrete | `any` → use json2 |
| `interface{}` param/field | `json2.Any` or struct/sum type | no `any` |
| `context.Context` param | drop it; model cancel via `chan`/`select`+flag | no equivalent |
| `s.Contains` / `s.Index` returning `-1` | `s.index(x) or {-1}` | returns `?int` |

## go2v output quirks
- Unformatted: no space before `{`. `v fmt -w` cleans it.
- `for r in s {` iterates runes directly (correct, better than `s.runes()`).
- Multi-return fn signatures emitted as `(i64, i64, bool)` — correct V.
- `return i64(x)` casts emitted correctly.
- Sometimes breaks a chained field access across a newline, e.g.
  `orig_r.str()\n.len` — manually rejoin to `orig_r.str().len`.
- Emits `unsafe { nil }` for nil returns of reference types — in V prefer
  `?T` return + `or {}` or an empty struct, not `unsafe { nil }`.

## Module triage example (covonaut, 65k non-test LoC)
Per-module non-test LOC + hard-API hit count drove the class:
- **A (direct):** fuzzy (168 LoC, 0 context/any) — go2v + 4 fixes → -prod PASS.
- **A:** pkg/util (41 LoC) — go2v + 1 fix (`error_()`) → PASS.
- **B:** components (44 LoC, context+any interfaces) — go2v, rewrote interfaces
  (dropped context, `map[string]string` metadata) → PASS.
- **C:** filequeue (100 LoC, sync+os+path) — go2v output wrong on every stdlib
  line; near-total native rewrite (Mutex methods, map-of-ref, closure capture,
  os path funcs) → PASS + runtime assert.
- **C:** skill/frontmatter (541 LoC, regex+bufio+state machine) — go2v unusable;
  deferred to native rewrite.
- **Blocked:** prompt / store / workflow — all `import agentcore`; cannot compile
  until agentcore (7.8k LoC, 330 `context.Context`) is ported first.

Lesson: of 8 "leaf" modules, only 5 were independently portable; 3 were blocked
by a heavy dependency. Triage deps BEFORE estimating.

## Closure capture gotcha (V-general, hits ports hard)
V closure capture `[mut x]` is **copy semantics** for scalars — a callback that
mutates `x` does NOT sync back to the caller. In the filequeue port,
`read_file_safe` first tried `fn [mut content, path] () ! { content = ... }` and
the outer `content` stayed `''`. Fix: do the work inline (lock/unlock + read
inside the method) or pass a `&mut` struct. Never rely on `[mut scalar]` to
return a value out of a closure.
