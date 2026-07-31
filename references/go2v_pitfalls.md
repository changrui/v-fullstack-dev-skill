# V Pitfalls: Go → V porting (reference for v-go2v-port)

Each row: Go idiom → V equivalent, with the gotcha. Verified on V 0.5.x (2026-07).

## Control flow / declarations
```go
// Go: short-decl in if
if idx := strings.Index(s, sub); idx >= 0 { ... }
```
```v
// V: no short decl in if
idx := s.index(sub) or { -1 }
if idx >= 0 { ... }
```

```go
// Go: multiple return
func find(c, s string) (int, int, bool) { ... }
```
```v
// V: tuple return is fine, but Index returns ?int not -1
pub fn find(c string, s string) (int, int, bool) {
    idx := c.index(s) or { -1 }
    if idx >= 0 { return idx, idx + s.len, true }
    ...
}
```

## Strings / builders
```go
var b strings.Builder
b.Grow(n)
b.WriteString(line)
return b.String()
```
```v
mut b := strings.new_builder(n)   // size at creation, NO Grow()
b.write_string(line)
return b.str()
```

```go
line = strings.TrimRightFunc(line, unicode.IsSpace)
```
```v
line = line.trim_right(' \t')     // V has no TrimRightFunc; pass a cutset
```

```go
idx := strings.Index(norm, sub)
if idx < 0 { ... }
```
```v
idx := norm.index(sub) or { -1 }  // V returns ?int, unwrap with or{}
if idx < 0 { ... }
```

```go
return strings.Replace(content, old, new, 1)  // first only
```
```v
// V replace() takes 2 args and replaces ALL. For first-only:
if idx := content.index(old) or { -1 }; idx >= 0 {
    return content[..idx] + new + content[idx + old.len..]
}
```

## Arrays / slices
```go
prev, curr = curr, prev   // swap two slices
```
```v
mut tmp := prev.clone()
prev = curr.clone()
curr = tmp.clone()        // V forbids raw array assign/swap (ownership)
```

```go
a = b                     // slice copy
```
```v
a = b.clone()             // required for []T too
```

```go
make([]int64, n)
```
```v
[]i64{len: n, init: 0}   // or {cap: n}
```

## Errors
```go
func ErrorString(e error) string {
    if e == nil { return "" }
    return e.Error()
}
```
```v
pub fn error_string(e IError) string {
    if isnil(e) { return '' }
    return e.str()         // NOT e.error_(), NOT e.msg
}
```

```go
data, err := os.ReadFile(p)
if err != nil { return err }
```
```v
data := os.read_file(p) or { return err }   // V uses ! (Result), not (val, err) tuple
```

```go
os.WriteFile(p, []byte("hi"), 0644)
```
```v
os.write_file(p, 'hi'.bytestr())   // 2nd arg is string; []u8 -> string via .bytestr()
```

```go
os.MkdirAll(dir, 0755)
```
```v
os.mkdir_all(dir, os.MkdirParams{})   // 2nd arg is a struct, not a mode int
```

## Paths (NO path/filepath module in V)
```go
real, _ := filepath.EvalSymlinks(p)
dir := filepath.Dir(p); base := filepath.Base(p)
abs := filepath.Join(dir, base)
```
```v
abs := os.abs_path(p)
dir := os.dir(abs); base := os.base(abs)
key := os.join_path(dir, base)   // V: path funcs live in `os`, no EvalSymlinks
```

## Concurrency
```go
var mu sync.Mutex
mu.Lock(); defer mu.Unlock()
```
```v
mut mu sync.Mutex
mu.lock(); defer { mu.unlock() }   // method names are lock()/unlock(), NO underscore
```

```go
fmq.queues[key] = l          // map[string]*FileLock
```
```v
fmq.queues[key] = l          // &FileLock works as map value, but index-assign is finicky;
                              // prefer `if key in m { l = m[key] } else { ... }`
```

```go
fmq.withFile(p, func() error { content = read(p); return nil })
```
```v
// Closure capture [mut content] is COPY — does NOT sync back to outer var.
// FIX: inline the lock logic, or pass a `mut struct` ARG (not captured):
fmq.with_file(p, fn (mut b ReadBox, pp string) ! {
    b.content = os.read_file(pp) or { return err }
})
```

## Types / interfaces
```go
type Source = string
type Metadata map[string]any
```
```v
pub type Source = string
// `any` -> json2.Any (NOT components.Any which go2v emits)
metadata map[string]json2.Any     // or concrete map[string]string
```

```go
type Loader interface {
    Load(ctx context.Context, src Source) ([]*Document, error)
}
```
```v
// V 有基础的 context 模块（vlib/context/）但与 Go 的 context.Context 不兼容。
// 建议去掉 context 参数，改用 chan/flag 传递取消信号。
pub interface Loader {
    load(src Source) ![]&Document
}
```

## Iteration
```go
for _, v := range slice { ... }      // ignore index
for i, r := range s { ... }          // runes
```
```v
for v in slice { ... }               // V ranges directly
for r in s { ... }                   // V iterates runes on a string directly
// or: for r in s.runes() { ... }
```

## I/O scanning (NO bufio in V)
```go
sc := bufio.NewScanner(r)
for sc.Scan() { line := sc.Text() }
if err := sc.Err(); err != nil { ... }
```
```v
for line in r.split_lines() {        // strings.split_lines / a.split_lines()
    // process line
}
// no scanner.Err() — split_lines doesn't surface read errors the same way
```

## Regex (pcre-backed in V)
```go
re := regexp.MustCompile(`^[a-z0-9-]+$`)
if re.MatchString(name) { ... }
```
```v
import regex.pcre
re := regex.pcre.compile(r'^[a-z0-9-]+$') or { panic(err) }
if re.find(name) != none { ... }     // find returns ?Match
```

## String interpolation trap
```v
println('value=$x')     // WRONG: single-quote is a RAW string, $x NOT interpolated
println("value=$x")     // CORRECT: double-quote interpolates
```

## Unused variables
```v
// V errors on unused vars under -prod (Go only warns with _ = x)
_ := someValue        // explicitly discard, or actually use it
```

## Additional pitfalls (from skill native rewrite, 2026-07)
These surfaced porting covonaut's `skill` package (290 LOC frontmatter parsing +
loading) — go2v output was unusable, so this was a clean native rewrite.

```go
key, val, ok := strings.Cut(s, ":")   // (before, after, found)
```
```v
// V has NO string.cut. Write a helper:
fn cut_str(s string, sep string) (string, string, bool) {
    idx := s.index(sep) or { -1 }
    if idx < 0 { return s, '', false }
    return s[..idx], s[idx + sep.len..], true
}
```

```go
rest := strings.TrimPrefix(s, prefix)
```
```v
// V has NO trim_prefix method on string. Use:
rest := s.replace(prefix, '')        // only safe if prefix appears once at front
rest := s[prefix.len..]              // when s.starts_with(prefix) is known true
```

```go
sort.Slice(visible, func(i, j int) bool { return visible[i].Name < visible[j].Name })
```
```v
// V: sort_with_compare, callback params MUST be REFERENCE types (&T):
visible.sort_with_compare(fn (a &Skill, b &Skill) int {
    if a.name < b.name { return -1 }
    if a.name > b.name { return 1 }
    return 0
})
```

```go
for name := range names { name = strings.TrimSpace(name) }  // Go reassigns loop var
```
```v
// V: `for name in names` gives an IMMUTABLE name. Use a local copy:
for name in names {
    n := name.trim_space()   // work with n
}
// `for mut name in names` is NOT allowed when names is a parameter (immutable).
```

```go
func appendField(fields map[string]string, key, value string) { value = strings.TrimSpace(value) }
```
```v
// V: `mut` on a scalar param (string/int) is FORBIDDEN in fn signature.
// Use a local mut variable instead:
pub fn append_field(mut fields map[string]string, key string, value string) {
    mut v := value.trim_space()
    if v == '' { return }
    fields[key] = v
}
```

```go
return []Skill{}, []Diagnostic{}   // Go: empty slices as []
```
```v
// V: empty array literals need explicit type:
return []Skill{}, []Diagnostic{}   // NOT just []
// `&Skill` (ref) vs `Skill` (value) must match declared return type exactly.
```

```go
re := regexp.MustCompile(`^[a-z0-9-]+$`)
if re.MatchString(name) { ... }
```
```v
import regex.pcre
re := pcre.compile(r'^[a-z0-9-]+$') or { panic(err) }
if re.find(name) != none { ... }   // find returns ?Match, NOT a bool
```

```go
scanner := bufio.NewScanner(strings.NewReader(header))
for scanner.Scan() { line := scanner.Text() }
```
```v
// V has NO bufio. Split into lines:
for line in header.split_into_lines() {   // method is split_into_lines, NOT split_lines
    ...
}
```

```go
entries, _ := os.ReadDir(dir)   // []os.DirEntry
for _, e := range entries { if e.IsDir() { walk(...) } }
```
```v
// V: os.ls(dir) returns ![]string (filenames only, no DirEntry type).
entries := os.ls(dir) or { return }
for entry in entries {
    full := os.join_path(dir, entry)
    if os.is_dir(full) { walk(...) }   // os.is_dir(path) bool
}
// os.ReadDir / DirEntry / entry.IsDir() do NOT exist in V 0.5.x
```
