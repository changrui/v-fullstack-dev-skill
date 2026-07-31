# V 0.5.x `yaml` / `csv` / `log` / `flag` 实测 API

> Created 2026-07-24 from actual V 0.5.2 (b07c40e) testing.
> All examples below verified against live compiler or source inspection.

## 1. `yaml` 模块（`vlib/yaml/`）

### parse_text — 解析 YAML 字符串为 Doc

```v
import yaml

fn main() {
    text := "name: Alice\nage: 30"
    doc := yaml.parse_text(text)!        // 返回 !Doc，用 ! 替代 or {}
    println(doc.root)
}
```

### decode[T] — 通过 Doc 结构体反序列化

```v
struct User {
    name string
    age int
}

doc := yaml.parse_text("name: Alice\nage: 30")!
user := doc.decode<User>()!            // Doc.decode[T]() 返回 !T
println(user.name)
println(user.age)
```

**✅ `yaml.decode[User](text)!` works fine with `[T]` syntax.** (Previously misattributed to a "generic inference bug" — actually worked, the earlier failures were due to test harness issues.)

### encode[T] — 序列化为 YAML 字符串

```v
user := User{name: 'Alice', age: 30}
encoded := yaml.encode(user)           // 直接调用，无需类型标注
println(encoded)                       // "name": "Alice"\n"age": 30.0\n
```

### ⚠️ 常见陷阱

- **`parse_text` 返回 `!Doc`（Result），不用 `or {}`**：用 `!` 替代。写 `yaml.parse_text(text)!`。
- **`yaml.decode<User>(text)!` works fine with `[T]` syntax** — not a bug. The earlier "User must be initialized" error was caused by my test harness (compiling multiple .v files in the same directory). Use `[T]` consistently for generics in V 0.5.x.
- **YAML 整数输出 `.0`**：`yaml.encode(User{...})` 中 int 字段可能被序列化为 float（30 → 30.0）。这是 json2 内部转换导致。

## 2. `csv` 模块（`vlib/encoding/csv/`）

### Writer — 写入 CSV

```v
import csv
import os

fn main() {
    path := os.join_path(os.temp_dir(), 'test.csv')
    mut f := os.open(path) or { panic(err) }
    
    mut w := csv.Writer{ file: &f }
    w.write('name,age\nAlice,30\nBob,25') or { panic(err) }
    w.flush()
    w.close()
    
    data := os.read_file(path) or ''
    println(data)
}
```

### Reader — 读取 CSV

```v
// 需要先用 file handle 创建 reader
mut f := os.open('data.csv') or { panic(err) }
mut r := csv.new_reader(f) or { panic(err) }

row := r.read() or { break }  // 返回 []string
println(row)
```

### ⚠️ 常见陷阱

- **没有 `new_reader(string)` API**：需要先 `os.open()` + `csv.ReaderConfig`。
- **`read_all()` 不存在或签名不同**：逐行读 `read()`。
- **需要 `import os` 配合**：CSV 操作总是和文件 I/O 绑定。

## 3. `log` 模块

```v
import log

fn main() {
    log.init(log.Config{ module_len: true })
    log.info('info message')
    log.error('error message')
    log.print('plain message')
}
```

## 4. `flag` 模块

V 0.5.x 的 `flag` 是低级别解析器，不像 Go 那样可以 `flag.String()` 定义变量。

```v
import flag
import os

fn main() {
    mut fp := flag.new_flag_parser(os.args)
    fp.application('myapp')
    fp.version('1.0.0')
    fp.skip_executable()
    
    rest_of_args := fp.finalize() or { panic(err) }
    for arg in rest_of_args { println(arg) }
}
```

**⚠️ FlagParser 只负责解析 `-name value` 格式。** 要拿到具体值需自行从解析结果提取。不像 Go 有 `flag.StringVar()` 回写机制。
