## 3. 同模块内函数不能重名

`fn parse_role(s string) Role` 若在 `session.v` 已定义，`webstore.v` 再定义一份会
`redefinition of function: agent.parse_role`。直接复用已有函数，不要复制。

## 4. `sqlite.DB` 持有方式

`sqlite.DB` 作为**值字段**持有、方法用值接收者（`fn (s T) list()`）与可变接收者
（`fn (mut s T) put()`）都能**正常持久化**到磁盘；相对路径（如 `data/foo.sqlite`）
也能正常建文件。无需 heap 指针（`&T`）。这与 `session.v` 的 `Session` 持 `db` 一致。

最小可工作模板：
```v
import db.sqlite
import os

struct Foo {
    id string @[primary]
    t  string
}

pub struct Store {
    db sqlite.DB
}

pub fn open_store(path string) !Store {
    dir := path.all_before_last('/')
    if dir != '' { os.mkdir_all(dir) or {} }
    db := sqlite.connect(path)!
    sql db { create table Foo } or { eprintln('create err: ${err}') }
    return Store{ db: db }
}

fn (s Store) list() int {
    rows := sql s.db { select from Foo } or { return -1 }
    return rows.len
}
fn (mut s Store) put(f Foo) {
    sql s.db { insert f into Foo } or { 0 }
}
```

## 5. 测试隔离：别让测试共用同一个 on-disk DB

`new_store()` 若固定指向 `data/foo.sqlite`，多次 `v test` 会跨 run 累积行，
导致"列表长度 == N"这类断言抖动。测试应各自用临时文件：
```v
pub fn new_test_store() WebStore {
    mut p := os.temp_dir() + '/foo-test-' + time.utc().unix_nano().str() + '.sqlite'
    return open_web_store(p) or { panic('new_test_store: ${err}') }
}
```
把 helper 放在被测试的模块文件里（`pub fn`），这样同模块的所有 `_test.v` 都能用，
且 `v -silent test .` 按整模块编译时可见（避免跨 _test.v 的 helper 不可见问题）。

## 6. 二进制陈旧陷阱

改完 `.v` 源文件后**必须重新构建二进制**再起服务，否则跑的是旧二进制，会表现为
"数据不落盘 / 重启即丢"等诡异现象（曾一度误判为存储 bug）。排错第一步：
`rm -f <dbfile>` + 重新 `v -o bin/x cmd/x` + 重启。

## 7. 把 ORM store 挂进 veb `WebApp`（可选字段 + 可变解包）

要在 veb Web UI 里复用 CLI 的 ORM store（例如把每次 web 运行也写入同一个
telemetry DB），把 store 作为 `WebApp` 的一个**可选字段**最安全——这样 HTTP
集成测试用 `WebApp{ store, config }`（不带 store）和离线启动都不会崩：

```v
pub struct WebApp {
    veb.StaticHandler
pub mut:
    store     WebStore
    config    Config
    telemetry ?TelemetryStore   // 可选：没配置就不写，页面/API 降级为空聚合
}
```

**两个会踩的编译坑：**

1. **`app.telemetry = open_store(path) or { none }` 是编译错误。**
   `open_store` 返回 `!TelemetryStore`（Result），其 `or` 块必须提供
   `TelemetryStore` 类型的值（或 `return`/`panic`），**不能是 `none`**（那是
   `?TelemetryStore` 的取值）。写成 `or { none }` 报
   "or block must provide a value of type TelemetryStore, not none"。正确写法：
   ```v
   if t := agent.open_telemetry_store(path) {
       app.telemetry = t
   } else {
       app.telemetry = none
   }
   ```
   （`if x := result { ... } else { ... }` 解包 Result，成功分支 `x` 是裸
   `TelemetryStore` 值，可直接赋给 `?TelemetryStore` 字段；失败分支才赋 `none`。）

2. **解包后要调用 store 的 `mut` 方法，必须用 `if mut ts := ...`。**
   `?TelemetryStore` 用 `if ts := app.telemetry { ... }` 解包出的是**不可变**
   值，调 `ts.save(...)`（`save` 是 `mut` 接收者）报 "`ts` is immutable, declare
   it with `mut`"。改成 `if mut ts := app.telemetry { ts.save(...) or {} }` 即可。
   （同理 `by_provider = sum.by_provider` 这类 map 复制要 `.clone()`，见 §8。）

3. **handler 里读取可选 store 并聚合时，map 不能直接赋值复制。**
   `by_provider = sum.by_provider` 报 "cannot copy map: call move or clone"——
   用 `by_provider = sum.by_provider.clone()`。同理 web 前端要注入的 map 字段。

4. **`summarise()` 返回 `!T`（Result）不是 Option**；失败时 `or { ... }` 块里
   不能写 `sum = TelemetrySummary{}`（那是给 Option 的写法，且 `sum` 未声明）。
   改为 `sum := ts.summarise() or { TelemetrySummary{} }`——`or` 块直接返回默认值
   表达式即可（Result 的 or 块返回同类型值）。

**为什么用可选字段而非必填：** veb 的 HTTP 集成测试（`spawn veb.run_at` + `net.http`）
通常直接 `WebApp{ store, config }` 构造，不留 telemetry；让字段为 `?` 使其
缺省为 `none`、handler 内 `if ts := app.telemetry { ... }` 优雅跳过，测试与
离线启动都零成本。

## 8. Map 复制限制（与 ORM store 相关的常见连带错）
从 struct 字段取 map 赋给局部会触发 "cannot copy map"：`by_provider = sum.by_provider`
必须 `.clone()`。这常在第 7 条的 web 聚合 handler 里一起出现，记在此处便于关联。

## 排错 checklist
- `no such table` → 多半是 `create table` 被 `or {}` 吞了；临时加 eprintln 看真因
  （最常见：主键 `sql: text` 写错）。
- insert 编译报 `or block must provide a default value of type int` → 改成 `or { 0 }`。
- `delete from Table` 裸删报 `unexpected token '}'` → ORM 的 delete 强制 `where`；
  全表清空改用 `s.db.exec('DELETE FROM Table') or {}`。
- **第 2 行起 insert 报 `UNIQUE constraint failed: runrow.id`** → 你用了 `int`
  主键（或删了 `id` 让 ORM 补隐式 `id`），ORM 每轮写 `id=0`。改成 `string @[primary]`
  并在 `save()` 里用 `time.now().unix_nano().str()` 生成唯一 id（见 §1b）。
- **`select from T order by ts desc` 编译报 `unexpected name 'order'`** → ORM
  无 `order by`；全选后在 V 里手动排序（见 §1c）。
- **`delete ... where ts >= 0` 报 `cannot use int literal as <Struct>`** → 先查
  **接收者变量名是否与某列名撞车**（§1d 根因）。把接收者改名（如 `ts`→`st`）通常
  立刻好；或换 `where` 列（如 `where steps >= 0` / `where provider != ''`）。
- **`app.field = open_store(path) or { none }` 报 "or block must provide a value
  of type Store, not none"** → 这是把 `!T`（Result）的 `or` 块当 Option 用了。
  改 `if t := open_store(path) { app.field = t } else { app.field = none }`，见 §7。
- **`if ts := app.optional_store { ts.save(...) }` 报 "`ts` is immutable"** →
  `?T` 的 `if` 解包出不可变值；需 `if mut ts := app.optional_store { ... }`，见 §7。
- 数据"不落盘" → 先确认二进制是新的（见第 6 条）。
