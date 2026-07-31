---
name: v-fullstack-dev
description: >-
  Consolidated V 0.5.x fullstack dev (V compiler at ~/WSL). Covers syntax
  pitfalls, veb web server + templates, db.sqlite ORM, json2 + i18n + net.http,
  concurrency, C FFI (mmap/SIMD), terminal (term/term.ui), GUI (ui/gui),
  OpenAI-compatible LLM wiring, Go→V porting. Load on any V task or when a
  project root has v.mod. Deep detail per topic in references/*.md.
version: 2.0.0
author: OWL Agent
license: MIT
enabled: true
modeSlugs:
  - code
  - code-reviewer
---

# V 0.5.x Fullstack Dev (v-fullstack-dev) — CONSOLIDATED

Single authoritative entry point for ALL V dev skills (supersedes v-lang-05x-patterns,
vlang-fullstack/medium-project, v-sqlite-orm-pitfalls, v-openai-compatible-llm-wirefmt,
v-go2v-port, go-to-v-porting, v-gui, vlang-web-dev). Deep recipes live in `references/*.md`.

Authoritative env: V compiler at `~/v` (WSL/Linux); version 0.5.2 (b07c40e).
Bundled sqlite means `import db.sqlite` needs NO system libsqlite3.

## Quick Start — First Time Here?

If you're new to this skill, follow this sequence:

1. **Read the syntax traps first:** `references/syntax.md` — the #1 place to avoid compile/runtime bugs.
2. **For Web apps:** read `references/web_veb.md` (+ use `templates/veb_app.v` as scaffold).
3. **For SQLite DB:** read `references/db_orm.md` (+ use `templates/sqlite_store.v` pattern).
4. **For JSON/HTTP:** read `references/json_http.md` + `references/i18n_json2.md`.
5. **To run the quality gate:** `~/v/v fmt -w . && ~/v/v vet . && ~/v/v -silent test .`.

> 💡 Tip: Use `skill_view(name: 'v-fullstack-dev', file_path: 'references/syntax.md')` to load a specific reference.

## When to load

Task touches V / veb / V CLI / V database / V module / V testing / V build /
V terminal / V GUI, or project root has `v.mod`; OR a compile error / HTTP-400-from-LLM /
Go→V port / GUI / terminal task.

## Topic index (read the reference on demand)

- `references/syntax.md` — syntax/runtime pitfalls (mutability, `!`/`?`, slices, pcre, vet).
- `references/web_veb.md` — veb routes, Context, `$veb.html()`, static, SSE, i18n, HTTP tests.
- `references/db_orm.md` — sqlite ORM PK/`insert`/`delete`/`select` traps, test isolation.
- `references/json_http.md` — `json2` decode/encode, `net.http` quirk, SSE streaming.
 - `references/mysql_veb.md` — MySQL + veb 全栈实战：连接（值类型/__global/nil检查）、查询（LEFT JOIN NULL segfault修复）、路由与模板、项目结构、种子数据。
- `references/i18n_json2.md` — NEW 0.5.2: `json2` canonical (alias of `x/json2`), `vlib/i18n` API. Always use `import json2`.
- `references/concurrency.md` — `go`/`chan`/`select`, closure-copy, `sync.Mutex`, `?fn`.
- `references/openai_llm.md` — three wire-format 400 bugs, SSE streaming, curl bisection.
- `references/c_ffi.md` (+`_pt2.md`) — `#include`/`fn C.xxx()`, mmap, SIMD, `#[c_extern]` linking.
- `references/tui.md` (+`_pt2.md`) — `term` + `term.ui` API, raw mode, progress bar.
- `references/gui.md` — `vlib/ui` vs `gui` decision + pitfalls; full API in `gui_frameworks.md`(+`_pt2`).
- `references/go2v.md` — Go→V porting with go2v: install, A/B/C classification, pitfall table.
- `references/build_test_vet.md` — v.mod, layout, module system, build/run/test/vet, vfmt, Makefile, env vars.
- `references/module_system.md` — 模块命名/目录结构、import 规则、依赖管理、项目布局最佳实践。
- `references/compiler_meta.md` — 编译期元编程：`$if`/`$for`/`$emit` 条件编译与代码生成、反射。
- `references/error_handling.md` — `?T`/`!T`/`or`/?` 错误处理详解，自定义错误类型，常见陷阱。
- `references/testing.md` — 测试框架：`test_` 约定、`assert`、表驱动测试、benchmark、测试隔离。
- `references/std_os.md` — `os` 模块：文件读写、路径操作、进程执行、环境变量、路径锚定。
- `references/std_time.md` — `time` 模块：`Time`/`Duration`、格式化/解析、睡眠、时区限制。
- `references/ARCHIVED.md` — index of all archived skills and cleaned-up `xp_*` files.
- `templates/` — see below for organized templates.

## 🔧 Templates (organized by category)

### Core App Scaffold
- `templates/veb_app.v` — Veb web app scaffold (routes, SSE, static, middleware).
- `templates/cli_app.v` — CLI app scaffold (subcommands, env vars, colored output).

### REST & API
- `templates/rest_handler.v` — Enhanced REST CRUD handler (with pagination, validation, standardized errors, CORS, auth helpers).
- `templates/sqlite_store.v` — SQLite ORM store pattern (string PK, sorting, transactions, test helpers).

### AI/LLM Integration
- `templates/openai_agent.v` — OpenAI compatible LLM agent (chat, streaming, tool calling wire fixes).

### Testing
- `templates/test_suite.v` — Test suite template (table-driven tests, temp isolation, mock, benchmark).

## 📂 Script Utilities

- `scripts/classify_modules.sh` (+ `classify_modules.ps1`) — Go→V module classification script.
- `scripts/validate_tr.py` — Validate translation consistency for i18n.

## ⚠️ SYNTAX — top pitfalls (detail: references/syntax.md)

- **`!T` (Result) vs `?T` (Option) are SPLIT.** `foo()?` only legal when caller returns `?T`; fn returning `!T` must use `or { return err }`.
- **Struct mutability:** `mut` fields go in a `mut:` section. A `pub:` field is IMMUTABLE — mutable state needs `mut:` + a `pub fn` getter returning a copy. Only ONE `pub:` and ONE `mut:` section per struct.
- **`mut` args only for arrays/maps/structs/pointers — NOT scalars.**
- **slice assignment needs `.clone()`:** `a = b[..].clone()`.
- **strings single-quoted.** `s == ''` not `s.len == 0`. `s[0..n]` is strict substr — guard `if s.len > n` first.
- **`defer` DOES exist in 0.5.2** — `defer { cleanup() }` valid.
- **closure capture is COPY:** `fn [mut x](..){ x<<.. }` does NOT mutate caller's `x`.
- **pcre:** `import regex.pcre`; `m.get(i) ?string` (NOT `m[i]`). Look-ahead `(?=…)` BROKEN — avoid.
- **`v vet` requires every `pub fn` to have a `//` doc comment.**
- **`const ()` groups are DEPRECATED** (will error after 2025-01-01). Use individual `const` declarations:
```v
// ❌ const ( cache_ttl_ms = 300000 )
const cache_ttl_ms = 300000
```
- **`os.exec(args []string)` returns `os.Result` directly — NOT a `!T`/`?T`.** Check `res.exit_code` and `res.output`.
- **Array `<<` does NOT chain:** use two statements (`argv << 'timeout'` then `argv << cmd.timeout.str()`).

## 🖥️ VEB / TEMPLATES (detail: references/web_veb.md)

- **Route attr:** `@['/path']` (GET) or `@['/path'; post]`. `[post: '/path']` PANICS (`unexpected extra attributes`). Path params `/x/:id` hit a codegen quirk — prefer `?id=` query params (`ctx.query['id']`).
- **Context struct:** `run_at[A, X]` needs `X` embedding `veb.Context` as a field literally named `Context`. Handler 2nd param is `mut ctx WebCtx`.
- **Template vars come from the HANDLER'S LOCAL SCOPE**, not App/Context fields.
- **`$veb.html()` resolves relative to COMPILE-TIME cwd** — pass explicit path, build from project root.
- **`@(fn())` is BROKEN** — compute as locals, use `@var`. `@css '/x.css?v=1'` **BROKEN** — use plain `<link>`.
- **Static:** `App` must EMBED `veb.StaticHandler`; `handle_static` PANICS on unknown extensions (`.bak`, `.tmp`).
- **i18n:** prefer new `vlib/i18n` (`load_tr_map`, `tr`) over veb's `.tr` — see `references/i18n_json2.md`.

### ⚠️ veb 0.5.2 Windows comptime bug — USE `net.http.Server` INSTEAD

V 0.5.2 on Windows has an internal comptime error (`expression has no value`) that breaks `veb.run_at[A, X]` compilation. **Do not attempt to debug veb on Windows.** Replace veb with `net.http.Server` + `Handler` interface:

```v
pub fn (mut app App) handle(req http.Request) http.Response { ... }
mut server := http.Server{ addr: ':8080', handler: app }
server.listen_and_serve()
```

This pattern works identically on Windows and Linux. Validated with V 0.5.2 (b07c40e). See `references/web_veb.md` §Windows alternative.

- **Path-param NOT supported** in raw `net.http` — manually parse `req.url` with `req.url.starts_with('/api/...')` and `parse_query()`.

## 🗄️ DB / ORM (detail: references/db_orm.md)

- **String PK:** `id string @[primary]` (ORM infers TEXT). NEVER `string @[primary; sql: text]` — swallows `create table` error → later `no such table`.
- **`int` PK is a TRAP:** ORM writes `id=0` every insert → 2nd row UNIQUE conflict. Use `string @[primary]` + generate id yourself.
- **`insert ... into T` or-block NON-EMPTY, returns `int`:** `or { 0 }`. `update`/`delete`/`select` accept bare `or {}`.
- **`delete` requires `where`** — truncate via raw `s.db.exec('DELETE FROM T') or {}`.
- **`select` has NO `order by`** (in older versions; 0.5.2 supports single-column `order by` — see `references/db_orm.md` §1c). Sort in V if multi-column.
- **`where` bare id resolves RECEIVER name BEFORE column** — rename receiver (`ts`→`st`).
- **Test isolation:** unique temp DB per call. **Stale binary trap:** rebuild after edits.

## ☁️ JSON / HTTP / i18n (detail: json_http.md + i18n_json2.md)

- **Use `json2` (canonical):** `import json2`. `x/json2` is now just an alias — write `import json2`. Always use `json2`.
  - Decode: `json2.decode[T](body, json2.DecoderOptions{}) !T` (2-arg, unwrap with `or {}`).
  - Encode: `json2.encode[T](val, json2.EncoderOptions{})` (2-arg). Use `{prettify: true}` for pretty output.
- **Map index needs `or {}`:** `m['k'] or { json2.Any{} }` then `.str()/.f64()/.int()/.as_map()/.as_array()`.
- **`net.http` `Request` builder quirk:** `req.do()` + `.body` can fail (`assignment mismatch`). Fallback: `os.execute('curl -s ...')`; top-level `http.get(url)` is fine for simple GETs.
- **NEW `vlib/i18n`:** `i18n.load_tr_map()` / `i18n.tr('en','key')` / `i18n.tr_plural(...)`. Prefer this over veb's `.tr`.
- **HTML-escape any LLM/user text before injecting into template or SSE HTML.**
- **`json2.Any` sum type does NOT include `[]map[string]string`** — to build nested JSON, wrap every layer:
```v
indicators << json2.Any({ 'id': json2.Any(ind.id), 'name': json2.Any(ind.name) })
cats << { 'id': json2.Any(cat.id), 'indicators': json2.Any(indicators) }
```
- **`http.Header` is a mutable value struct** — use `http.new_header()` then `.add()`/`.add_custom()`/`.set()` methods. `+` operator NOT supported.
- **`http.read_cookies(header, name)`** returns `[]&Cookie` — the `Request` struct has NO `.cookies()` method.
- **`cookie.value` is a field**, not a method.

## 🔄 CONCURRENCY (detail: references/concurrency.md)

- **`go` + `chan` + `select`** exist; `spawn` cannot take mutable non-reference args — pass `&T` or a holder struct.
- **Closure capture is COPY** — share via `chan` or `sync.Mutex`-guarded struct.
- **`sync.Mutex`:** `mu.lock()`/`mu.unlock()` — go2v's `lock_()`/`unlock_()` WRONG.
- **`?fn` optional fn-pointer field** called with `?`: `t.run?(args)` returns bare `Ret`.

## 🎨 GUI — quick decision (detail: references/gui.md)

- **`vlib/ui`** — Sokol, declarative widget tree, 20+ widgets, webview, native on Win/macOS. Mature. **`gui`** — Clay, reactive `view=fn(state)`, flexbox, 6 widgets, NOT in `vlib/` (vendor `src/examples/gui/`).
- **Both use sokol — cannot coexist in one binary.** `vlib/ui` state heap (`&App{}`); `gui` struct MUST be `@[heap]`.

## 🤖 OPENAI-COMPATIBLE LLM (detail: references/openai_llm.md)

Three wire-format bugs → HTTP 400 even when `v vet` clean:

1. **`type` serializes as `ty`** → `ty string @[json: 'type']`.
2. **`parameters` must be JSON OBJECT** → type `json2.Any`, build via `json2.decode[json2.Any]('{...}') or { json2.Any{} }`. Cover EVERY tool def (incl. `patch.v`). `grep -rn '"parameters":"' agent/` → ZERO matches.
3. **Tool-result needs `tool_call_id`** matching `tool_calls[].id`. `messages` must be `[]json2.Any`; first message `role: system`.

- **Streaming (SSE):** `http.Request` + `on_progress_body`; callback COPY-semantics (re-parse `resp.body`). 401=key, 400=wire-format.

## 🐘 PORTING Go → V (detail: references/go2v.md)

- go2v = DRAFT GENERATOR, not translator. Classify: A (pure logic→go2v), B (context/sync/os/path/regex/bufio→native rewrite), C (unported deps→block).
- Install: `git clone https://github.com/vlang/go2v`; first run needs `GOPROXY=direct go install github.com/asty-org/asty@latest`. Translate a SINGLE `.go` file (dir mode needs `.vv` fixtures).
- Systematic failures: `strings.Builder.grow`→`strings.new_builder(n)`; `path/filepath`→`os.*`; `err.error_()`→`err.str()`; `any`→`json2.Any`; no `bufio`/`context` (see reference table).
- **Do NOT 1:1 port a large Go framework — prefer V-native reimplementation.**

## 🏗️ Workflow (build / test / vet)

- Prefer stdlib (`~/v/vlib/`: yaml, json2, regex.pcre, db.sqlite, i18n) over hand-rolling. Use `import yaml`, not a hand-rolled parser.
- Anchor runtime paths to `os.executable()` + `v.mod` sentinel, not `os.getwd()`.
- Check module: `v -check .` (NOT `v -c`/`v check`). Build: `v -o <name> <file>.v` (note: `v build-module` does NOT exist in 0.5.2). End-to-end: `main.v` importing the module + asserts, then `v run .`.
- **Quality gate:** `v fmt -w . && v vet . && v -silent test .`.
- Standing user convention: record each V 0.5.x pitfall into BOTH (1) `~/.vaiv/conventions.md` and (2) this skill's references.

## 🚑 Common Error Quick Reference Table

| Error Message | Likely Cause | Fix / Action |
|--------------|-------------|-------------|
| `no such table` | `create table` swallowed by `or {}`; wrong PK attribute (e.g., `string @[primary; sql: text]`) | Use `string @[primary]` (no extra `sql:`); debug with `eprintln(err.msg())` on `create table` |
| `UNIQUE constraint failed: id` (2nd insert) | `int` PK causes ORM to write `id=0` repeatedly | Use `string @[primary]` + generate ID yourself (e.g., `time.now().unix_nano().str()`) |
| `or block must provide a default value of type int` | `insert ... into` uses empty `or {}` | Change to `or { 0 }` (returns int) |
| `expression has no value` (veb on Windows) | `veb.run_at[A,X]` comptime crash on Windows | Switch to `net.http.Server` + `Handler` interface |
| `cannot copy map: call move or clone` | Map field copied without clone | Use `my_map = other_map.clone()` |
| `ts is immutable` on `?T` unwrap | `if ts := app.telemetry` gives immutable value | Use `if mut ts := app.telemetry { ts.save(...) or {} }` |
| `receiver name clashes with column in where` | ORM parses bare identifier as receiver var instead of column | Rename receiver (e.g., `ts` → `st`) so `where ts >= 0` works correctly |
| `closure modifies outer var but changes not visible` | Closure capture is COPY by default | Use `[mut x]` in closure capture or share via `chan`/`Mutex` |
| `import json2` fails | Module not found | Ensure V compiler at `~/v`; `json2` is in `vlib/json2` (alias `x/json2` also works) |
| `v vet` complains about missing doc comment on pub fn | Every `pub fn` needs a `//` comment | Add doc comment above every public function |
| `Result` from `os.exec` treated as `!T`/`?T` | `os.exec` returns `os.Result`, not `!T` | Access `res.exit_code` and `res.output` directly; do not use `or {}` on the result itself |
| Template variable not rendered | Variable not in handler's local scope (only locals, not App fields) | Compute values in handler and assign to local variables passed to template |
| `select ... order by` not working | Multi-column `order by` unsupported in ORM | Sort in V after fetching, or use single-column `order by` |
