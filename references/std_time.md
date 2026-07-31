# V 0.5.x `time` 标准库模块 — std_time.md

`time` 模块提供时间获取、格式化、运算和定时功能。与 Go 不同，V 的时间格式模板使用 `YYYY`、`MM`、`DD` 这类直观占位符。

---

## 1. 获取当前时间

```v
import time

// 本地时间（系统时区）
now := time.now()

// UTC 时间
utc := time.utc()

// Unix 时间戳
unix_sec := time.unix()       // i64 — 秒
unix_ms  := time.unix_milli() // i64 — 毫秒
unix_us  := time.unix_micro() // i64 — 微秒

println('now:     ${now}')
println('unix:    ${unix_sec}')
println('unix_ms: ${unix_ms}')
```

---

## 2. `Time` 结构体字段

```v
t := time.now()

t.year         // int — 2024
t.month        // int — 1~12
t.day          // int — 1~31
t.hour         // int — 0~23
t.minute       // int — 0~59
t.second       // int — 0~59
t.microsecond  // int — 0~999999

t.unix         // i64 — Unix 时间戳（秒）
t.unix_milli   // i64 — Unix 时间戳（毫秒）
```

---

## 3. 时间格式化与解析

### 格式化

```v
t := time.now()

// 默认格式（RFC 3339 style）
fmt1 := t.format()
// => "2024-01-15 10:30:00"

// 自定义格式 — 使用 YYYY/MM/DD/HH/mm/ss 占位符
fmt2 := t.format_ss('YYYY-MM-DD HH:mm:ss')
// => "2024-01-15 10:30:00"

fmt3 := t.format_ss('YYYY/MM/DD')
// => "2024/01/15"

fmt4 := t.format_ss('HH:mm')
// => "10:30"

fmt5 := t.format_ss('ISO: YYYY-MM-DDThh:mm:ssZ')
// => "ISO: 2024-01-15T10:30:00Z"
```

### 格式占位符对照表

| 占位符 | 含义 | 示例 |
|--------|------|------|
| `YYYY` | 四位年份 | 2024 |
| `YY` | 两位年份 | 24 |
| `MM` | 月份（补零） | 01 |
| `M` | 月份（无补零） | 1 |
| `DD` | 日期（补零） | 05 |
| `D` | 日期（无补零） | 5 |
| `hh` | 小时（24h，补零） | 09 |
| `h` | 小时（24h，无补零） | 9 |
| `mm` | 分钟（补零） | 05 |
| `m` | 分钟（无补零） | 5 |
| `ss` | 秒（补零） | 05 |

### 解析

```v
// 解析默认格式
parsed := time.parse('2024-01-15 10:30:00') or { panic(err) }

// 自定义格式解析
parsed2 := time.parse_ss('2024/01/15', 'YYYY/MM/DD') or { panic(err) }

// 解析 Unix 时间戳
from_unix := time.unix_to_time(1705300000)
println(from_unix.year) // 2024
```

---

## 4. `Duration` 运算

### 创建 Duration

```v
// 使用时间常量
d1 := 5 * time.second
d2 := 3 * time.minute
d3 := 1 * time.hour + 30 * time.minute

// 组合
delay := time.minute + 30 * time.second // 1m30s
```

### 时间加减

```v
now := time.now()

// 加法
later   := now + 5 * time.minute
tomorrow := now + 24 * time.hour

// 减法
earlier := now - 30 * time.second
yesterday := now - 24 * time.hour

// 两个时间点的差值
start := time.now()
expensive_calc()
elapsed := time.now() - start

println('took ${elapsed.str()}')
```

### Duration 方法

```v
d := 90 * time.second

d.milliseconds()  // i64 — 90000
d.seconds()       // f64 — 90.0
d.minutes()       // f64 — 1.5
d.str()           // string — "1m30s"
```

---

## 5. 睡眠与定时

```v
// 睡眠指定时长
time.sleep(2 * time.second)  // 阻塞 2 秒
time.sleep_ms(500)            // 阻塞 500 毫秒
time.sleep_us(1000)           // 阻塞 1000 微秒（1 毫秒）

// 实用模式：带间隔的循环
mut ticker := time.new_ticker(5 * time.second)
defer { ticker.stop() }

for _ in 0 .. 10 {
    _ := <-ticker.c // 每 5 秒收到一个信号
    println('tick at ${time.now().format()}')
}
```

---

## 6. 时区

V 0.5.x 的 `time` 模块**没有独立的时区类型**（不像 Go 的 `time.Location`），但提供了本地 ⇄ UTC 的双向转换函数：

```v
local := time.now()
utc   := time.utc()

// 本地时间 → UTC（假设系统时区为 Asia/Shanghai）
utc_from_local := local.utc_to_local()      // 实际上是"解释为本地时间的 UTC 值"
// 正确用法：将本地时间转为 UTC 展示
utc_val := local.as_utc()                   // 返回 UTC 时间
println(utc_val.format())                   // 以 UTC 格式打印

// UTC 时间 → 本地时间
local_val := utc.as_local()                 // 返回本地时间
println(local_val.format())                 // 以本地时区格式打印

// 时区偏移量（分钟）
offset_min := local.offset()                // i64 — 例如 +480（东八区）
println('当前时区偏移: ${offset_min} 分钟')
```

### 可用时区方法

| 方法 | 返回 | 说明 |
|------|------|------|
| `t.as_utc()` | `Time` | 返回 UTC 表示 |
| `t.as_local()` | `Time` | 返回本地时区表示 |
| `t.offset()` | `i64` | 时区偏移量（分钟） |
| `t.local_to_utc()` | `Time` | 本地时间→UTC（已弃用，用 `as_utc()`） |
| `t.utc_to_local()` | `Time` | UTC→本地时间（已弃用，用 `as_local()`） |

**实用策略：** 始终以 UTC 格式存储和传输时间，在展示层使用 `as_local()` 转为系统时区格式化。

---

## 7. 常用常量

```v
time.millisecond  // Duration — 1 毫秒
time.second       // Duration — 1 秒
time.minute       // Duration — 1 分钟
time.hour         // Duration — 1 小时
```

---

## 8. 常见陷阱

### 陷阱 1：`time.unix()` 返回 `i64`，不是 `int`

在 64 位系统上没问题，但在 32 位系统上 `int` 可能只有 32 位。始终用 `i64` 接收。

### 陷阱 2：`time.now()` 受系统时间影响

`time.now()` 返回的是系统时间。如果用户修改系统时间或 NTP 同步导致跳跃，返回值会跳跃。需要单调时钟的场景请自行使用 `time.unix_milli()` 计算差值。

### 陷阱 3：格式模板与 Go 不同

```v
// Go: t.Format("2006-01-02 15:04:05")
// V:   t.format_ss("YYYY-MM-DD HH:mm:ss")
// 不要混淆两者的格式模板！
```

### 陷阱 4：没有独立时区类型（但有本地⇄UTC转换）

V 0.5.x 标准库**没有**像 Go 的 `time.LoadLocation()` / `time.In()` 这样的自定义时区转换。
但提供了 `as_local()` / `as_utc()` / `offset()` 等基本的本地⇄UTC 转换方法
（详见第 6 节）。如果需要其他时区（非系统时区、非 UTC）的支持，建议：
- 自行维护 UTC 偏移量表
- 或调用系统命令（如 `date`）获取
- 或通过 C FFI 调用系统 API

### 陷阱 5：`Duration` 加法不检查溢出

```v
// 可能溢出不会 panic，但结果不正确
max_dur := 1 << 62 * time.hour
overflow := max_dur + 1 * time.hour // 静默溢出
```

### 陷阱 6：`sleep()` 精度

`time.sleep()` 的精度取决于操作系统调度器和系统负载。实时场景不要依赖毫秒级别的睡眠精度。
