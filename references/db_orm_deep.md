---
name: v-sqlite-orm-pitfalls
description: Archived deep-dive for V 0.5.x db.sqlite ORM pitfalls. The consolidated summary now lives in v-fullstack-dev (references/db_orm.md). Load this ONLY when you need the full verbose treatment (receiver/column name clash, int-PK UNIQUE trap, test isolation, veb store wiring) that v-fullstack-dev points to, or when debugging a specifically ORM-related compile/runtime error not resolved by the summary. Do NOT load alongside v-fullstack-dev for the same task unless you need the extra detail.
---

# V 0.5.x SQLite ORM — 实战坑与正确写法

适用于 V 0.5.x 的 `db.sqlite` ORM（`sql db { create/select/insert/update/delete }`）。
以下结论均经真实编译/运行验证，坑位是该版本特有的。

## 1. 字符串主键：用 `@[primary]`，不要写 `sql: text`

错误写法（会让 `create table` 静默失败，后续 `select` 报 `no such table`）：
```v
struct WebSessionRow {
    id string @[primary; sql: text]   // ❌ 未加引号的 sql: attr 导致建表失败
    title string
}
```

正确写法（ORM 自动推导 TEXT）：
```v
struct WebSessionRow {
    id string @[primary]   // ✅
    title string
}
```

验证：标准库 vlib 中字符串主键一律写作 `string @[primary]`（见
`vlib/orm/orm_insert_test.v`、`orm_create_and_drop_test.v`）。`int` 主键用
`int @[primary; sql: serial]`。

注意：`create table` 的 `or {}` 会**吞掉**建表错误，所以失败不会立刻暴露，
要等到第一次 `select` 才报 `no such table: xxx`。排错时给 `create table` 的
`or` 块加一行 `eprintln('create err: ${err}')` 即可看到真实原因。

### 1b. `int` 主键：ORM 每次 insert 都写 `id=0` → 第 2 行 UNIQUE 冲突（VERIFIED 2026-07-13）
比 `sql: text` 更隐蔽的坑。若把主键声明为 `int` 并交给 ORM 自增，`insert ... into`
**每一行都把 `id` 列写成 `0`**——第 1 行落库（id=0），**第 2 行直接 UNIQUE 冲突**
（`UNIQUE constraint failed: runrow.id (19)`）。本会话踩到的几种形态：
  - `id int @[primary]` → insert 写 `id=0` → 第 2 行冲突。
  - `id int @[primary; sql: 'auto_increment'` → 更糟：`sql:` 的值被当成**列名**
    （`CREATE TABLE ... \`auto_increment\` INTEGER ... PRIMARY KEY(\`auto_increment\`)`），
    insert 仍往里写 `0` → 同样 UNIQUE 失败。（`sql:` 不是"自增"魔法开关，它就是你
    写的字面列类型/名，**别把 `auto_increment` 放进去**。）
  - 干脆删掉 `id` 字段也不行：ORM 会自动补一个隐式 `id` 列并每次写 `0` → 同样冲突。
  - `int @[primary; sql: serial]` 是本技能此前记录的"可用"形态，但本会话**未复验**，
    对 int 主键一律按可疑处理。
  - **稳健且已验证的修法：用 `string` 主键，在 insert 时自己生成唯一 id**（同
    webstore.v 的 `WebSessionRow` 模式）：
    ```v
    pub struct RunRow {
    pub:
        id string @[primary]   // 在 save() 里显式赋值
        ts i64
        // ... 其他字段
    }
    // save() 内：
    row := RunRow{ id: time.now().unix_nano().str(), ts: time.now().unix_milli(), ... }
    sql ts.db { insert row into RunRow } or { return error('insert: ${err}') }
    ```
    `unix_nano().str()` 跨运行唯一性足够；若担心亚纳秒碰撞，可再拼计数器或
    `rand.u32()`。**不要**指望 ORM 给 `int` 主键自增。

### 1c. ORM `select` 支持 `order by`（更正于 2026-07-30）
**注意：此前的版本错误地声称 ORM 不支持 `order by`。** 实际上 V 0.5.2 的 ORM
`select` 支持单列排序，语法为：
```v
rows := sql db {
    select from RunRow where provider == 'openai' order by ts desc limit 10
} or { []RunRow{} }
```

验证来源：`vlib/orm/orm.v` 定义了 `OrderType` 枚举（`.asc`, `.desc`），
并生成 SQL `ORDER BY ts DESC`。`orm_order_by_custom_field_test.v` 测试通过。

| 语法 | 效果 |
|------|------|
| `order by ts` | 升序（默认） |
| `order by ts asc` | 升序 |
| `order by ts desc` | 降序 |

**限制：** 仅支持单列排序（不支持多列 `order by a, b`）。如需多字段排序，
仍需要用 V 代码在查询后手动排序。

### 1d. `delete`/`where` 子句解析陷阱——**根因是「列名 vs 接收者变量名撞车」**
当必须 `delete` 全表（ORM 强制 `where`）时，下面这条会给出**令人困惑**的解析错误：
```v
pub fn (mut ts TelemetryStore) reset() ! {
    sql ts.db {
        delete from RunRow where ts >= 0   // ❌ error: cannot use int literal as TelemetryStore
    } or {}
}
```
错误看着像 "`>= 0` 字面量把解析器搞晕了"，但**真正的根因是名字冲突**：
`RunRow` 有一列叫 `ts`，而方法的接收者变量也叫 `ts`。ORM 的 `where` 子句会
**优先把 `ts` 解析成接收者（类型 `TelemetryStore`）**，于是 `ts >= 0` 变成
"拿一个 `TelemetryStore` 跟 int 比较"，类型直接错乱，才报出那个文不对题的错。

**修复（二选一）：**
- 把接收者改名（最稳，顺手消除歧义）：
  ```v
  pub fn (mut st TelemetryStore) reset() ! {
      sql st.db { delete from RunRow where ts >= 0 } or {}
  }
  ```
  列名 `ts` 不再与接收者 `st` 冲突，`where ts >= 0` 立刻合法。
- 或换被比较的列/字面量形状（如 `where steps >= 0` 用 int 字段、`where provider != ''`
  用 string 字段），让 `where` 左边不再是那个撞名的列。

**通用教训（比"避开 `>= 0`"更重要）：ORM `where`/`set` 子句里的裸标识符会**
**先按接收者变量名解析，再按表列名解析。** 凡是方法处理一张含 `id`/`ts`/`db`/
`row`/`t` 等短列名的表，接收者变量名务必避开这些列名——否则 `where` 里一引用就
静默解析成接收者类型，报出完全文不对题的错（"cannot use int literal as
<Struct>"、"expected X, found Y"）。调试 ORM 诡异解析错时，第一反应应是
**检查接收者变量名是否与某个列名撞车**，而不只是怀疑字面量形状。

## 2. `insert ... into` 的 or 块必须非空且返回 int

错误：`insert` 表达式的 `or` 块若为空会编译报错：
```v
sql s.db {
    insert row into WebSessionRow
} or {}   // ❌ error: expression requires a non empty `or {}` block
```
而且即便写成 `or { eprintln(...) }` 也会报错，因为 `insert ... into` 返回 `int`，
`or` 块必须提供 `int` 默认值（或 return/break/panic）：
```v
sql s.db {
    insert row into WebSessionRow
} or { 0 }   // ✅
```
对比：`update` / `delete` 表达式是 void，`or {}` 是允许的，不要混为一谈。

### 2b. `delete` 必须有 `where` 子句（裸全表删不被接受）

想清空整张表时，直觉写法是：
```v
sql s.db {
    delete from MessageRow   // ❌ error: unexpected token `}`, expecting name/where
}
```
V 0.5.x 的 ORM `delete` **强制要求 `where` 子句**，裸 `delete from Table` 直接
编译报错（语法层拒绝，不是运行时）。因此"清空表再全量重插"（覆盖式保存）这类
需求不能用 ORM 的 `delete`，要退回原生 exec：
```v
s.db.exec('DELETE FROM MessageRow') or {}   // ✅ 裸全表删
s.save(msgs)                                // 再全量 insert
```
`s.db` 是 `sqlite.DB` 值字段，`.exec(query string) !` 是底层方法，可和 ORM 的
`sql s.db { ... }` 混用。注意 `exec` 返回 `!`，记得 `or {}` 或 `!` 处理。

典型用途：覆盖式持久化（如连续会话每轮把内存 history 镜像回 SQLite）——若用
`insert` 的 append 语义会指数级重复累积行，所以每轮先 `exec('DELETE...')` 再
全量 `insert`。

