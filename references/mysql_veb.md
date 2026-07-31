# MySQL + veb 0.5.x — 全栈 Web 应用实战

与 `v-fullstack-dev` SKILL.md 配套。所有结论基于 OWID 全球发展数据观察项目实际编译/运行验证（V 0.5.2, MySQL 8.0, WSL2）。

## 模块命名：避免与标准库冲突

`import db.mysql` 是 V 标准库的 MySQL 驱动模块。如果自定义包也叫 `db`（如 `module db`），会冲突。**解决方案**：将自定义包命名为 `database` 或其他不冲突的名字。引用：`import database`。

## MySQL 连接：值类型 vs 指针类型

`mysql.connect()` 返回 **值类型 `mysql.DB`**，不是指针 `&mysql.DB`。

### 正确模式：`__global` 值类型 + 连接标志

```v
module database
import db.mysql

__global global_db mysql.DB          // 值类型，无初始值
__global global_connected bool

pub fn connect(host string, port int, username string, password string, dbname string) bool {
    conn := mysql.connect(
        host:     host
        port:     u32(port)          // port 需要 u32() 显式转换
        username: username
        password: password
        dbname:   dbname
    ) or {
        eprintln('数据库连接失败: ${err}')
        return false
    }
    global_db = conn
    global_connected = true
    create_tables()
    return true
}

pub fn db() &mysql.DB {
    return &global_db                 // 取地址返回指针
}

pub fn is_connected() bool {
    return global_connected
}
```

### 关键要点

| 要点 | 说明 |
|------|------|
| `__global` 无需初始值 | V 0.5.2 不支持 `__global x Type = unsafe { nil }` |
| 编译标志 | 必须加 `-enable-globals`：`v -enable-globals run .` |
| nil 检查 | 值类型不能 `isnil()`，改用独立 bool 标志 |
| `port` 参数 | 需 `u32(port)` 显式转换 |
| `db()` 返回指针 | 用 `return &global_db` |

## 数据库查询

```v
// exec — 无参数，返回 []mysql.Row
rows := db.exec('SELECT id, name FROM topics ORDER BY sort_order') or { ... }

// exec_param_many — 参数化查询（[]string 参数）
rows := db.exec_param_many('SELECT * FROM topics WHERE slug = ?', [slug]) or { ... }

// exec_none — 无返回结果（DDL, INSERT, UPDATE, DELETE）
db.exec_none('CREATE TABLE IF NOT EXISTS topics (...)')
```

### LEFT JOIN + NULL 值陷阱

`db.exec_param_many()` 处理 LEFT JOIN 返回的 SQL NULL 值时，可能在 MySQL C 客户端内部触发崩溃（`v_stable_sort` segfault）。

**解决方案**：用 `COALESCE()` + 字符串拼接：

```v
query := "SELECT i.name, " +
    "COALESCE(e.code, ''), COALESCE(dp.value, 0.0) " +
    "FROM indicators i " +
    "LEFT JOIN data_points dp ON dp.indicator_id = i.id " +
    "LEFT JOIN entities e ON e.id = dp.entity_id " +
    "WHERE i.topic_id = '${topic_id}' "
rows := db.exec(query) or { ... }
```

### 读取查询结果

```v
for row in rows {
    id    := row.vals[0]           // string
    name  := row.vals[1]           // string
    count := row.vals[2].int()     // string → int
    value := row.vals[3].f64()     // string → f64
}
```

## Veb 路由处理器

### 标准模式

```v
module main
import veb

pub struct Context { veb.Context }
pub struct App { veb.StaticHandler }

// GET / — 所有模板变量必须是 handler 局部变量
@['/']
pub fn (mut app App) index(mut ctx Context) veb.Result {
    title := app.home_data.title
    topics := app.home_data.topics
    return $veb.html('views/index.html')
}

// GET /topic?slug=xxx — 使用查询参数而非路径参数
@['/topic']
pub fn (mut app App) topic(mut ctx Context) veb.Result {
    slug := ctx.query['slug'] or { return ctx.redirect('/') }
    page := app.topic_cache[slug]
    if page.topic.id == '' { return ctx.not_found() }
    title := page.topic.name
    indicators_data := page.indicators
    return $veb.html('views/topic.html')
}

// POST 路由
@['/api/data'; post]
pub fn (mut app App) post_data(mut ctx Context) veb.Result {
    body := ctx.req.data
    return ctx.text('received: ${body.len}')
}
```

### 关键要点

| 要点 | 说明 |
|------|------|
| 路由语法 | `@['/path']` 推断 GET；`@['/path'; post]` 指定方法 |
| 路径参数 | V 0.5.x 路径参数有 bug，用 `ctx.query['key']` |
| 模板作用域 | `$veb.html()` 只能访问 handler **局部变量**，不能访问 `App`/`Context` 字段 |
| `ctx.redirect` | `return ctx.redirect('/')` |
| `ctx.not_found` | `return ctx.not_found()` |

## Veb 模板系统

模板 `${var}` 只能引用 handler 内的局部变量：

```v
// main.v handler
@['/']
pub fn (mut app App) index(mut ctx Context) veb.Result {
    title := app.home_data.title
    topics := app.home_data.topics
    return $veb.html('views/index.html')
}
```

模板内容：
```html
<h1>${title}</h1>
@for t in topics
    <div class="card"><h2>${t.name}</h2></div>
@end
```

### 预加载数据模式

推荐**启动时预加载所有数据到 App 字段**：

```v
fn main() {
    home := handlers.get_home_data()
    indicators := handlers.get_all_indicators()
    mut app := &App{ home_data: home, all_indicators: indicators }
    app.mount_static_folder_at('static', '/static') or { ... }
    veb.run[App, Context](mut app, cfg.server.port)
}
```

### 模板限制

| 限制 | 解决 |
|------|------|
| `@if` 中不能出现复杂表达式 | 在 handler 中预计算 bool 值 |
| `@for` 结构体字段必须 `pub:` | 加 `pub:` 可见性 |
| 模板中不能调用函数 | handler 中预计算字符串值 |
| `${map.key}` 可能解析失败 | 先赋值给局部变量 |

## 结构体可见性 (pub:)

V 结构体字段默认**私有**。嵌入结构体必须在 `pub:` 之前：

```v
// ✅ 正确
pub struct IndicatorWithData {
    Indicator                   // 嵌入必须最前面
pub:
    entity_code   string
    value         f64
}

// ❌ 错误 — embedding must be at beginning
pub struct IndicatorWithData {
pub:
    Indicator
}
```

## 多文件项目结构

```
project/
├── main.v              # 入口 + 路由
├── v.mod
├── config/config.v     # 配置加载
├── database/init.v     # MySQL 连接 (module database)
├── handlers/handlers.v # 数据访问层
├── models/topic.v      # 数据模型
├── views/*.html        # veb 模板
├── static/css/         # 静态资源
└── tools/seed/main.v   # 种子数据脚本
```

关键规则：
- 每个子目录是一个独立 V 模块
- 模块名用 `database` 而非 `db`（避免标准库冲突）
- **必须用 `v run .`**（不能用 `v run main.v`）
- 独立脚本用 `v run tools/seed/`

## `sql` 是保留关键字

```v
// ❌ 错误
sql := "SELECT ..."
// ✅ 正确
query_sql := "SELECT ..."
```

## 种子数据脚本

```v
module main
import config, database, rand

fn uuid_v4() string {
    buf := rand.bytes(16) or { return 'fallback' }
    return buf.hex()
}
```

运行：`v -enable-globals run tools/seed/`

## `byte` 已弃用，用 `u8`

```v
mut buf := []u8{len: 16}  // 不是 []byte
```

## 编译命令

```bash
v -enable-globals run .                 # 运行
v -enable-globals -o bin/app .          # 编译二进制
v -enable-globals run tools/seed/       # 种子数据
```

## 与 SQLite 的关键差异

| 特性 | `db.sqlite` | `db.mysql` |
|------|-------------|------------|
| 连接返回 | `sqlite.DB`（值类型） | `mysql.DB`（值类型） |
| 全局变量 | `__global db sqlite.DB` | `__global db mysql.DB` |
| nil 检查 | `isnil(db)` 可用 | ⚠️ 不能用 `isnil()`，用 bool 标志 |
| 参数查询 | `exec_param2(sql, p1, p2)` | `exec_param_many(sql, [p1, p2])` |
| ORM | `sql db { select ... }` | 无 ORM，仅原生 SQL |
