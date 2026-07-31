# V 0.5.x 内建转换与字符串/数学 API（无需 import）

> Updated 2026-07-24: Major correction based on live testing with clean per-test dirs.
> Previous claims about `.int()` returning void and yaml/json2 generic bugs were FALSE — caused by test harness issues (multiple .v files in same directory, stale cache).

## 1. 数值 ↔ 字符串 转换（ALL CONFIRMED WORKING ✅）

```v
// int → string
n := 42
s := n.str()              // "42"

// string → int — works fine!
i := '123'.int()          // 123

// float64 → string
f := 3.14
s := f.str(2)             // "3.14"

// string → float64 — works fine!
x := '3.14'.f64()         // 3.14
```

## 2. 字符串内建方法（ALL CONFIRMED WORKING ✅）

V 0.5.x **字符串本身就是类型**，有大量内建方法。无需 `import strings`。

```v
s := 'hello world'

// 大小写
up := s.to_upper()        // "HELLO WORLD"
lo := s.to_lower()        // "hello world"

// 查找
has := s.contains('wor')       // true

// 计数与重复
count := s.count('l')          // 3
repeat_s := 'ab'.repeat(3)     // "ababab"

// 分割与修剪
parts := s.split(' ')           // ['hello', 'world']
trimmed := '  hello  '.trim_space() // "hello"
```

实测确认可用：`.to_upper()`, `.to_lower()`, `.repeat(n)`, `.contains(sub)`, `.split(sep)`, `.trim_space()`。

## 3. 数学内建方法（部分 ✅）

```v
// abs — on variables, literal needs parens
n := -5
a := n.abs()              // 5

// ceil/floor
c := 3.14.ceil()          // 4.0
fl := 3.99.floor()        // 3.0

// max/min
m := 3.max(7)             // 7
mi := 3.min(7)            // 3

// sqrt/pow
sq := 16.0.sqrt()         // 4.0
p := 2.0.pow(10)          // 1024.0
```

## 4. json2/yaml 泛型 decode（CONFIRMED WORKING ✅）

```v
struct Data { x int; y f64 }

// json2.decode[T] works for custom structs
data := json2.decode[Data]('{"x": 42, "y": 3.14}')!
println(data.x)  // 42

// yaml.decode[T] also works
yaml_str := "x: 42\ny: 3.14"
user := yaml.decode[Data](yaml_str)!
println(user.x)  // 42
```

**关键：** 使用 `[T]` 语法（不是 `<T>`），后面跟 `!` unwrap Result。两个模块的泛型都正常工作。

## 5. ⚠️ 陷阱 & 注意事项

- **在干净的目录中测试单个文件**：V 编译器在同一目录下如果有多个 `.v` 文件，可能产生缓存/编译干扰。使用独立 temp 目录隔离每个测试。
- **字符串字面量调方法需括号**：`(42).str()` 更稳妥，避免解析歧义。
- **`strings` 模块只有极少数函数**（`random`, `find_between_pair_*`, `split_capital`）：主要字符串操作通过内置方法，无需 import `strings`。
- **`strconv` 模块无公共函数**：所有转换走内建方法（`str()`、`.int()`、`.f64()`）。
