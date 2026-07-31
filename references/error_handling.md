# V 0.5.x 错误处理 (`?T` / `!T` / `or` / `?`) — error_handling.md

V 的错误处理体系与 Go 有本质区别：V 使用 **`!T` (Result)** 和 **`?T` (Option)** 两种独立类型，配合 `or { }` 块和 `?` 传播操作符。正确理解这些概念是写出健壮 V 代码的基础。

---

## 1. `?T` (Option) vs `!T` (Result)

| 特性 | `?T` (Option) | `!T` (Result) |
|------|---------------|---------------|
| 语义 | 值**可能存在** | 操作**可能失败** |
| 成功值 | `T` | `T` |
| 失败值 | `none` | `error` |
| 适用场景 | map 查找、类型断言、可能为空的返回值 | 文件读写、网络请求、数据库操作 |

```v
// ?T — 可选值
fn find_user(id int) ?User {
    if id <= 0 {
        return none
    }
    return User{ id: id }
}

// !T — 可错误结果
fn read_config(path string) !string {
    data := os.read_file(path) or { return err }
    return data
}
```

### 类型转换

```v
// ?T → !T
fn opt_to_res(val ?int) !int {
    return val or { error('value is missing') }
}

// !T → ?T
fn res_to_opt(val !int) ?int {
    return val or { none }
}
```

---

## 2. `or { }` 块详解

`or { }` 是 V 错误处理的核心机制。它**仅在调用失败时执行**（懒惰求值）。

### 基本模式

```v
// 提供默认值
count := risky_fn() or { 0 }

// 传播错误（仅在返回 !T 的函数中有效）
data := read_file('x.txt') or { return err }

// 在返回 ?T 的函数中返回 none
val := optional_fn() or { return none }

// 恐慌（适用于无法恢复的错误）
config := load_config() or { panic(err) }

// 跳过 / 继续循环
for item in items {
    process(item) or { continue }
}

// 空块（静默丢弃错误 — 危险！慎用）
cleanup() or {}
```

### 重要规则

- **`or { }` 必须出现在调用表达式之后**，没有分号或换行隔开
- 在 `!T` 函数中，`or { return err }` 中的 `err` 是编译器注入的隐式错误变量
- 在 `?T` 函数中，`or { return none }` 中的 `none` 需要显式写出
- `or {}` （空块）**合法但不推荐**，会静默丢弃错误

```v
// 正确
val := foo() or { return err }

// 错误 — 分号隔开了调用和 or 块
// val := foo(); or { return err }
```

---

## 3. `?` 传播操作符

`?` 是 `or { return err }` 或 `or { return none }` 的语法糖。

```v
// 以下两种写法等价（在返回 !T 的函数中）
data := read_file('x.txt') or { return err }
data := read_file('x.txt')?

// 以下两种写法等价（在返回 ?T 的函数中）
val := optional_fn() or { return none }
val := optional_fn()?
```

### 使用限制

- `?` **只能在返回 `?T` 或 `!T` 的函数中使用**
- 调用 `fn_ret_opt()?` 在 `!T` 函数中 — ✅ 合法（`none` 自动转为错误）
- 调用 `fn_ret_res()?` 在 `?T` 函数中 — ✅ 合法（错误自动转为 `none`）
- 调用 `fn_ret_none_option()?` 在非 Option/Result 函数中 — ❌ 编译错误

```v
fn read_and_parse(path string) !int {
    // ? 自动传播错误
    data := os.read_file(path)?
    return data.int()
}
```

**`!` 操作符类似，但用于 Result 类型：** `foo()!` 等价于 `or { panic(err) }`。

---

## 4. 自定义错误类型

### 实现 `IError` 接口

```v
pub struct ValidationError {
    field string
    msg   string
}

pub fn (e ValidationError) msg() string {
    return '${e.field}: ${e.msg}'
}

pub fn (e ValidationError) code() int {
    return 422
}

// 使用
fn validate_age(age int) !int {
    if age < 0 || age > 150 {
        return ValidationError{ field: 'age', msg: 'out of range' }
    }
    return age
}
```

### 简单错误

```v
fn divide(a, b int) !int {
    if b == 0 {
        return error('division by zero')
    }
    return a / b
}
```

### 错误包装

```v
fn do_complex() !string {
    step1 := step_one() or {
        return error('step_one failed: ${err.msg()}')
    }
    // ...
    return step1
}
```

---

## 5. `none` 与 Option 模式匹配

### `if x :=` 语法

```v
if user := find_user(42) {
    // user 在此作用域内是非 Option 类型
    println(user.name)
} else {
    // 未找到
    println('not found')
}
```

### 与 `or { }` 的关系

```v
// 方式一：if x :=
if data := optional_fn() {
    use(data)
}

// 方式二：or + 默认值
data := optional_fn() or { return }
use(data)

// 方式三：? 传播
data := optional_fn()?
use(data)
```

---

## 6. 常见陷阱

### 陷阱 1：副作用在 `or` 块中意外执行

```v
// ❌ 危险 — count++ 在成功时也会执行！
val := fn() or { count++ return 0 }

// ✅ 正确
val := fn() or {
    count++
    return 0
} // 注意 or 块只在失败时执行
```

### 陷阱 2：`?T` 函数中错误地 `return err`

```v
// ❌ 编译错误 — ?T 函数没有 err 变量
fn opt_fn() ?int {
    val := other() or { return err } // 错误！
}

// ✅ 正确
fn opt_fn() ?int {
    val := other() or { return none }
    return val
}
```

### 陷阱 3：`!T` 函数中错误地 `return none`

```v
// ❌ 编译错误 — !T 函数不能返回 none
fn res_fn() !int {
    val := other() or { return none } // 错误！
}

// ✅ 正确
fn res_fn() !int {
    val := other() or { return err }
    return val
}
```

### 陷阱 4：嵌套调用导致多层 `or` 嵌套

```v
// ❌ 难以阅读
process(load(read(file)) or { return } or { return }) or { return }

// ✅ 使用 ? 传播
data := read(file)?
parsed := load(data)?
process(parsed)?
```

### 陷阱 5：`or` 块的懒惰求值误解

`or` 块只会在错误时执行。以下代码中，`log_error()` 只在 `fallible_fn()` 失败时才被调用：

```v
result := fallible_fn() or {
    log_error() // 仅失败时执行
    'default'
}
```

---

## 7. 总结

| 场景 | 推荐写法 |
|------|---------|
| 快速传播 | `file := os.read_file(path)?` |
| 提供默认值 | `count := parse_int(s) or { 0 }` |
| 不可恢复时恐慌 | `config := load() or { panic(err) }` |
| 循环中跳过错误 | `process(item) or { continue }` |
| 模式匹配 Option | `if val := opt_fn() { }` |
| 静默忽略（慎用） | `cleanup() or {}` |
