# V 0.5.x 编译期元编程 — compiler_meta.md

V 支持编译期执行代码 (`$if`、`$for`、`$emit`、`$else`)，用于条件编译、代码生成和反射。这些是 V 区别于 Go 的核心特性之一，但也容易踩坑。

---

## 1. `$if` — 编译期条件

### 目标环境检测

```v
// 操作系统
$if windows {
    println('on Windows')
}
$if linux {
    println('on Linux')
}
$if macos {
    println('on macOS')
}

// 架构
$if x32 {
    println('32-bit')
}
$if x64 {
    println('64-bit')
}
$if arm {
    println('ARM')
}

// 编译器配置
$if debug {
    println('debug build')
}
$if prod {
    println('production build')
}
$if test {
    println('running tests')
}

// 编译器后端
$if c  { println('C backend') }
$if js { println('JS backend') }
$if native { println('native backend') }
```

### 组合条件

```v
$if windows && x64 {
    println('64-bit Windows')
}

$if linux || macos {
    println('Unix-like')
}

$if !windows {
    println('not Windows')
}
```

### 编译期 `$if` vs 运行时 `if`

```v
// 编译期：不满足条件的分支不编译，目标二进制中不存在
$if linux {
    // 这段代码在 Windows 构建中完全不存在
    os.execute('rm -rf /tmp/cache')
}

// 运行时：代码始终存在，条件在运行时判断
if os.user_os() == 'linux' {
    // 代码已编译进二进制，运行时判断
}
```

---

## 2. `$for` — 编译期迭代

### 遍历结构体字段

```v
import reflect

struct User {
    name string
    age  int
    email string
}

fn main() {
    $for field in User.fields {
        println('Field: ${field.name} : ${field.typ}')
    }
    // 输出：
    // Field: name : string
    // Field: age : int
    // Field: email : string
}
```

### 结构体字段的编译期操作

```v
struct Config {
    host string
    port int
    debug bool
}

fn print_config[T](c T) {
    $for field in T.fields {
        $if field.typ is string {
            println('${field.name}: "${c.$(field.name)}"')
        } $else $if field.typ is int {
            println('${field.name}: ${c.$(field.name)}')
        } $else {
            println('${field.name}: ${c.$(field.name)}')
        }
    }
}
```

### 遍历枚举成员

```v
enum Color {
    red
    green
    blue
}

fn main() {
    $for v in Color.values {
        println('Color: ${v}')
    }
}
```

---

## 3. `$emit()` — 生成 V 代码

```v
// $emit() 在编译期将字符串注入为 V 代码

macro := 'println("hello from macro")'
$emit(macro)

// 结合 $for 生成重复代码
struct Point {
    x int
    y int
}

fn (p Point) zero() {
    $for field in Point.fields {
        $emit('p.${field.name} = 0')
    }
}
```

### `$emit` 的限制

- 参数必须是**编译期可知的字符串**（字符串字面量或编译期拼接结果）
- 运行时变量的值不能用于 `$emit`
- 错误的注入代码产生的编译错误指向 `$emit` 行，难以调试

```v
// ✅ 正确
macro := 'println("hello")'
$emit(macro)

// ❌ 错误 — 运行时值不能注入
// x := 'println("bad")'
// $emit(x)  // 编译错误：x 不是编译期常量
```

---

## 4. `$else` — 编译期条件分支

与 `$if` 配套使用：

```v
fn platform_newline() string {
    $if windows {
        return '\r\n'
    } $else {
        return '\n'
    }
}
```

---

## 5. 编译期反射 (`reflect`)

```v
import reflect

struct User {
    name string
    age  int
}

fn main() {
    // 获取结构体字段信息（运行时反射）
    sym := reflect.type_of(User{})
    for i in 0 .. sym.kind_fields() {
        field := sym.field(i)
        println('${field.name}: ${field.typ.kind()}')
    }
}
```

### `$for field in T.fields` vs `reflect`

| 特性 | `$for field in T.fields` | `reflect` |
|------|--------------------------|-----------|
| 时机 | 编译期 | 运行时 |
| 性能 | 无开销 | 有运行时开销 |
| 灵活性 | 有限（简单类型判断） | 可访问完整类型信息 |
| 适用场景 | 代码生成、序列化 | 动态类型处理 |
| 类型匹配 | `$if field.typ is string` | `field.typ.kind()` |

---

## 6. `@` 编译期内置变量

在 veb 模板和 V 代码中可使用 `@` 前缀的编译期变量：

```v
// 源文件信息
@FILE       // string — 当前源文件路径
@LINE       // int — 当前行号
@COLUMN     // int — 当前列号

// 函数/模块信息
@FN         // string — 当前函数名
@MOD        // string — 当前模块名
@STRUCT     // string — 当前结构体名

// 日期时间（编译时刻）
@DATE       // string — 编译日期
@TIME       // string — 编译时间
@VEXE       // string — 编译器路径
@VMODROOT   // string — 项目根目录

// 调试输出
print(@FILE)       // "main.v"
print(@LINE)       // "42"
println('${@FN}')  // "main"
```

### 实用模式

```v
// 日志中记录源码位置
fn debug_log(msg string) {
    $if debug {
        println('${@FILE}:${@LINE} [${@FN}] ${msg}')
    }
}
```

---

## 7. 编译期数组/映射构建

```v
// 编译期构建字符串数组
const names = ['Alice', 'Bob', 'Charlie']

// 编译期 map
const configs = {
    'host': 'localhost'
    'port': '8080'
}
```

`const` 块中可以调用编译期可求值的函数：

```v
const project_root := os.real_path(os.dir(@VMODROOT))
const default_port := os.getenv('PORT', '8080')  // 编译时读取环境变量
```

---

## 8. 编译期方法的泛型特化

```v
fn max[T](a T, b T) T {
    $if T is string || T is int || T is f64 {
        if a > b { return a }
        return b
    } $else {
        $compile_error('max() not supported for this type')
    }
}

fn main() {
    println(max(3, 7))         // 7
    println(max('abc', 'xyz')) // "xyz"
    // max(true, false)        // 编译错误
}
```

---

## 9. 常见陷阱

### 陷阱 1：混淆 `$if` 和运行时 `if`

```v
// ❌ $if 中的变量名拼写错误不会报运行时错误
// 但运行时 if 中的错误会被编译器检查

$if some_typo {  // ⚠️ 静默忽略（条件不满足，分支不编译）
    println('never runs')
}
```

### 陷阱 2：`$for field` 中读取字段值

```v
struct X { name string }

fn print_names[T](items []T) {
    $for field in T.fields {
        // ❌ 不能直接这样访问：items[i].$(field.name) 在编译期不展开
        // ✅ 正确：用编译期拼接
        $if field.name == 'name' {
            // 编译期已知字段名
        }
    }
}
```

### 陷阱 3：`$emit` 注入语法错误

```v
// 如果注入的代码有语法错误，错误指向 $emit 行
// 而非注入内容所在行，很难调试
// 先用普通 V 代码写好逻辑，确认无误后再做成宏
```

### 陷阱 4：`@FILE` 和 `@LINE` 是编译期常量

```v
// @FILE 在编译时确定，不是运行时动态获取
// 你无法在编译期之后改变或覆盖它们
```

### 陷阱 5：`$else` 必须紧跟 `$if`

`$else` 不能独立使用，必须与 `$if` 在同一编译期块中：

```v
$if windows {
    println('windows')
}
$else {  // ✅ 正确：紧跟 $if
    println('not windows')
}
```
