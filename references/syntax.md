# V 0.5.x Syntax — deep detail

Companion to `v-fullstack-dev` SKILL.md. Covers the non-obvious compiler
behaviors that cost iterations. Each item was hit and fixed in real V ports.

## Module naming & imports
- Import path uses DOT separators (`import internal.worldbank`), never slashes.
- One `import` keyword per line. `cannot import multiple modules at a time` fires
  if two imports end up on the same logical line.
- User preference: keep module names SHORT, WITHOUT project-name prefix
  (`module worldbank`, not `module myproject.worldbank`). Import as
  `import internal.worldbank`.
- Rename an internal `db` package to `dbase` to avoid clashing with stdlib `db`.
- `module cmd.agent` is ILLEGAL (no dotted module names) — keep `main.v` at root.
- **Prefer a STANDALONE top-level module for a self-contained utility** (e.g. a
  syntax highlighter, parser, formatter) rather than embedding it inside a larger
  module like `agent`. The user explicitly preferred `module syntax` over
  `agent/syntax.v` — a standalone module keeps the utility decoupled, independently
  unit-testable, and its name short. When adding such a utility, create
  `syntax/syntax.v` (`module syntax`) and import it (`import syntax`) where needed.

## Result vs Option: `!` and `?` are SPLIT
- `!T` = Result (error). `?T` = Option.
- `foo()?` propagation ONLY legal when enclosing fn returns `?T`. Fn returning
  `!T` must use `or { return err }`, NOT `?`.
- `return error('msg: ${err}')` — but `error(err)` where `err` is `IError` is a
  TYPE error; just `return err`.
- `(T, bool)` tuple is NOT an Option — call `v, ok := f(x)`, never `f(x) or {...}`.

## Struct mutability
```v
pub struct Series {
pub:
    country_code string
mut:
    points []YearValue
}
```
- `mut` field at top level → SYNTAX ERROR (`missing ':' after mut`). Use a `mut:`
  section.
- Method mutating a field must take `mut self`: `pub fn (mut db DB) close() !`.
- `mut` args only for arrays/interfaces/maps/pointers/structs — NOT int/string.
- A `pub:` field is IMMUTABLE. Mutable-but-readable state → `mut:` + `pub fn` getter
  returning a COPY:
```v
pub struct Agent {
pub:
    client Client
mut:
    last_run RunStats
}
pub fn (a Agent) stats() RunStats { return a.last_run }
```
- Only ONE `pub:` and ONE `mut:` section per struct.

## const
- Grouped `const ( a = 1 b = 2 )` is DEPRECATED. Use one per line.
- `const` may call functions (`const p = os.home_dir() + '/.x'`) — evaluated at
  startup.

## time
- `time.now().year` / `.month` / `.day` etc. are **struct fields** (NOT methods).
  See `references/std_time.md` for full API.
- Milliseconds: `time.now().unix_milli()` (i64). `unix_time_milli()` does NOT
  exist. `unix()` = seconds.
- Build a Duration: `5 * time.second` or `time.Duration(ms)`.
- There is `time.second`/`time.millisecond` const but `int.millisecond` (method)
  does NOT exist — multiply a `Duration`.

## slice assignment needs `.clone()`
- `a = b` → ERROR "use `array2 = array1.clone()`". Write `a = b.clone()`.
- `a = b[0..limit]` → `a = b[0..limit].clone()`. Same for `.keys()` copies.
- Fires for plain `[]string` reassignments too.

## string builtins
- Single-quoted literals. `s == ''` (not `s.len == 0`), `s != ''` (not `s.len > 0`)
  — vet warns on the `.len` form.
- `s.trim()` REQUIRES a cutset: `s.trim('\n')` / `s.trim_space()`. `s[0..n]` is
  STRICT substr — out-of-bounds PANICS. Guard: `if t.len > 40 { t = t[0..40] }`.
- `last_index(s) ?int` (use `or { -1 }`); there is no `last_index_of`.

## enum
- Members need NO `@` unless a reserved keyword (`system` is fine, not `@system`).
- `@[json: 'x']` tags honored by x.json2; omitting uses bare field name.

## Option struct fields
- `?f64` assigned `none` can cause a low-level C error. Prefer `f64` + `has_value bool`.

## regex.pcre — capture groups via `.get(i) ?string`
- `pcre.find_all(html)` → `[]pcre.Match` (one per match), NOT `[][]string`.
- Read group `i`: `m.get(i) ?string` (unwraps with `or { '' }`). Do NOT `m[1]`.
- `pcre.compile(pat)` returns `!Regex` (error-returning), NOT `?Regex`. Storing a
  regex in a struct field must use `?pcre.Regex`; the `pcre.Regex{}` zero-value
  literal FAILS to compile inside an `or` block. Use a helper + `?pcre.Regex` field:
  ```v
  fn cre(pat string) ?pcre.Regex { return pcre.compile(pat) or { none } }
  struct Rule { kind string; re ?pcre.Regex }
  // Rule{ kind: 'kw', re: cre('\\bfoo\\b') }
  ```
  (`pcre.compile(pat) or { pcre.Regex{} }` errors — the `or` block must yield a
  `Regex`, and the literal is rejected. Use `none` + a `?pcre.Regex` field instead.)
- `re.find(line)` → `?Match`; `re.find_all(s)` → `[]Match`.
- **Look-ahead `(?=…)` is BROKEN under find/find_from in 0.5.1** (returns no
  match). Use plain patterns. `find_from(s, pos)` finds first match at/after pos;
  check `m.start == pos` to anchor at the scan position.
- **Priority tokenizer pattern (verified in vaiv's `syntax` module):** to tokenize
  left-to-right without overlap, from `pos` call `re.find_from(code, pos)` for each
  rule and keep the match where `m.start == pos` AND length is the LONGEST (so `fn`
  beats a bare identifier match at the same spot). Advance `pos` by that length; if
  no rule matches, `pos++` (plain char). Supports V/Go/JS/HTML/bash highlighting.
- Top-level `import regex` is FULL-anchored (matches entire string only) — use
  `regex.pcre` for grep-like substring search.

## Closure capture does NOT propagate back
- `fn [x] (..) { }` gives the closure its OWN copy of `x`; mutations DON'T sync
  back, even `fn [mut x]`. So `os.walk(root, fn [mut files](fp){ files << fp })`
  leaves outer `files` EMPTY. Fix: explicit recursion with `os.ls`+`os.is_dir`:
```v
fn list_files(root string) []string {
    mut out := []string{}
    for e in os.ls(root) or { return out } {
        p := os.join_path(root, e)
        if os.is_dir(p) && !os.is_link(p) { out << list_files(p) } else { out << p }
    }
    return out
}
```
- `for i, line in arr.enumerate()` does NOT exist — use `for i in 0..arr.len`.

## `?fn` optional function-pointer struct fields
- `run ?fn (args string, ctx &ToolCtx) Ret` → call `r := t.run?(args, ctx)`
  (returns bare `Ret`, NO `or` block). Calling without `?` errors.
- Inside a `?Message`-returning fn, a `?fn` call is accepted without `or`; only
  genuine `?T` needs `or`/`if x :=`.

## File I/O
- `os.open_append(path)` does NOT create the file (mode `ab` fails if missing).
  Pre-create: `if !os.exists(path) { os.write_file(path, '') or {} }` then open.
- `os.walk` callback capture does NOT propagate (see closures).
- `os.file_size(path) u64` exists. `os.is_abs` is NOT public — check
  `path.starts_with('/')` on WSL/Linux.

## yaml — USE IT, do not hand-roll
- `import yaml`; `c := yaml.decode_file[Config](path) !Config`. Field mapping
  REUSES json tags (`@[json: 'name']`, NOT `@[yaml: 'name']`). Missing doc decodes
  to default `T` (safe `or { c }` fallback). Encode with `yaml.encode[T](val)`.

## `v vet` discipline
- Every `pub fn` needs a `//` doc comment.
- `s == ''` over `s.len == 0`; `s != ''` over `s.len > 0`.

## Build / run
- `v build` is rejected — use `v -o bin/app main.v` or `v run main.v`.
- `v fmt -w . && v vet . && v -silent test .` before declaring done.
- `v check-md`: use `v ignore` (skip compile+fmt), `v oksyntax` (syntax only),
  `v nofmt` (compiles, skips fmt). Chinese .md lines MUST be < 100 chars.
