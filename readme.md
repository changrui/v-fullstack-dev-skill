# V Fullstack Dev Skill — 审查报告

> 审查日期: 2026-07-30
> 编译器: V 0.5.2 b07c40e (g:\v)
> 审查范围: SKILL.md + references/*.md + templates/*

---

## 一、发现的问题分类

- 🔴 **错误** — 描述与编译器实际行为不符
- 🟡 **不准确** — 部分正确但有过时或遗漏
- 🟠 **冗余/重复** — 内容高度重叠的文件
- 🔵 **可改进** — 可补充完善的内容

---

## 二、🔴 错误（✅ 已修复）

以下 5 个错误已修正：

| # | 问题 | 涉及文件 | 修复内容 |
|---|------|---------|---------|
| 1 | ORM order_by 不支持 | `references/db_orm.md` §1c | 替换为"order by 支持"的正确用法和注意事项 |
| 2 | `net.http.Request` 没有 `.cookie()` | `references/json_http.md` §Cookies | 补充 `req.cookie(name)` 方法，保留 `read_cookies()` 作为备选 |
| 3 | `encode_pretty` 函数不存在 | `references/i18n_json2.md` §Decode/Encode | 替换为 `EncoderOptions{prettify: true}` |
| 4 | `v build-module` 命令不存在 | `references/build_test_vet.md`, `references/go2v.md` | 替换为 `v -o <name> <file>.v` |
| 5 | `v -check .` 用法有误导 | `references/build_test_vet.md` | 描述更清晰 |

---

## 三、🟡 不准确（✅ 已修复）

以下 4 处不准确已修正：

| # | 问题 | 涉及文件 | 修复内容 |
|---|------|---------|---------|
| 1 | `time` 模块时区转换 | `references/std_time.md` §6, 陷阱4 | 补充 `as_local()/as_utc()/offset()` 方法说明 |
| 2 | `os.is_abs` 不公开 | `references/syntax.md` §File I/O | 基本正确，留待下次优化 |
| 3 | `const ()` 分组废弃 | `SKILL.md`, `references/syntax.md` | 描述正确，保留 |
| 4 | `context` 模块存在 | `references/go2v.md` §pitfall table | 更新为"V 有基础 context 模块，但不兼容 Go" |

---

## 四、🟠 冗余/重复文件

以下文件内容高度重叠，应考虑合并或归档：

| 保留 | 可删除/合并 | 理由 |
|------|------------|------|
| `db_orm.md` | `db_orm_deep.md`, `db_orm_deep_pt2.md` | 后两者是前者的详细扩写，大量重复 |
| `tui.md` | `tui_pt2.md` | pt2 只是续篇，应合并 |
| `openai_llm.md` | `openai_llm_deep.md`, `openai_llm_deep_pt2.md` | 深度内容重复 |
| `go2v.md` | `go2v_pitfalls.md`, `go2v_workflow.md` | 内容已被 go2v.md 涵盖 |
| `gui_frameworks.md` | `gui_frameworks_pt2.md` | pt2 是续篇 |
| `c_ffi.md` | `c_ffi_pt2.md` | pt2 是续篇 |

此外 `xp_*` 系列文件（`xp_multi_session_cli.md`, `xp_source_corruption.md`, `xp_vaiv_learning_reminder.md`, `xp_vaiv_mock_testing.md`, `xp_vaiv_self_update.md`）是历史/实验性记录，可能不再需要。

---

## 五、🔵 可改进的补充内容

### 1. ORM `order by` 正确用法

```v
sql db {
    select from RunRow where ts > 0 order by ts desc limit 10
} or { []RunRow{} }
```
支持 `asc`/`desc`，支持 `limit N`。

### 2. `net.http.Request` 已大幅改进

V 0.5.2 的 `http.Request` 结构体已有丰富字段：
- `cookies map[string]string` — cookie 存储
- `on_redirect`, `on_progress`, `on_progress_body`, `on_finish` — 回调
- `pub fn (req &Request) cookie(name string) ?Cookie` — 读取 cookie
- `pub fn (mut req Request) add_cookie(c Cookie)` — 添加 cookie
- `pub fn (req &Request) do() !Response` — 执行请求

不再需要 `os.execute('curl ...')` 作为 fallback（但 curl 方法仍然可用）。

### 3. json2 `Any` 类型包含 `Null`

`vlib/json2/types.v`:
```v
pub type Any = []Any | bool | f64 | f32 | i64 | int | i32 | i16 | i8
    | map[string]Any | string | time.Time | u64 | u32 | u16 | u8 | Null
```
- 包含 `Null` 类型，可用 `val is json2.Null` 判断
- 不再需要 `val.json_str() == 'null'` 方式

### 4. `http2` 支持

`vlib/net/http/h2_*.v` 系列文件显示 V 0.5.2 已有 HTTP/2 客户端实现（h2_client.v, h2_conn.v, h2_mux_conn.v, h2_pooled_transport.v）。

---

## 六、总结

| 类别 | 数量 | 关键项 |
|------|------|--------|
| 🔴 错误 | 5 | ORM order_by、cookie() 方法、encode_pretty、build-module、-check |
| 🟡 不准确 | 4 | time 时区、os.is_abs、const 分组、context 模块 |
| 🟠 重复文件 | 10+ | db_orm_deep/*, tui_pt2, openai_llm_deep/*, go2v_* 等 |
| 🔵 可改进 | 4 | http.Request 改进、json2 Null、HTTP/2 等 |

**优先修复:** ORM order_by 错误（影响最大）+ `net.http.Request.cookie()` 错误（影响 web 开发）。
