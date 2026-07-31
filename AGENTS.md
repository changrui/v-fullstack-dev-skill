# AGENTS.md — V Fullstack Dev Skill (v-fullstack-dev)

> Skill package for V 0.5.x (0.5.2, b07c40e). Compiler at `~/v`.
> This is an instruction asset repo, not a runnable app.

## Commands (must match)

- Quality gate: `~/v/v fmt -w . && ~/v/v vet . && ~/v/v -silent test .`
- Module check: `~/v/v -check .` (NOT `v -c`, NOT `v check`)
- Build: `~/v/v -o bin/out path/to/main.v`
- Test isolation: run from project root (`~/v/v test .`), never single-file when code depends on cwd-loaded assets

## Critical runtime/compile quirks

- Windows + veb 0.5.2 = comptime crash (`expression has no value`). Use `net.http.Server` + `Handler` interface; see `references/web_veb.md` §Windows.
- `!T` (Result) vs `?T` (Option) split. Map index returns `!T`, NOT `?T`. Use `or {}`. `'key' in m` membership check.
- Struct: one `pub:` + one `mut:` section. `mut:` fields only. `mut` args: arrays/maps/structs/pointers, NOT scalars.
- Closure capture is COPY. Mutations inside `fn [mut x](){}` do NOT sync back. Mutations inside `fn [x](){}` do NOT sync back.
- Slice/map assignment needs `.clone()`.
- `const ( ... )` grouped consts are DEPRECATED. Use `const` one per line.
- `defer` exists in 0.5.2.
- `strings.new_builder(n)` initial size; V has no `strings.Builder.grow`.
- `v vet` requires `//` doc comment on every `pub fn`.

## veb / net.http (references/web_veb.md)

- Route attr: `@['/path'; post]` (path FIRST). `@[post: '/path']` PANICS.
- Path params `:id` broken (codegen quirk). Prefer query params (`ctx.query['id']`).
- `X` in `run_at[A, X]` must embed `veb.Context` field named `Context`.
- Template vars come from handler LOCAL scope. Struct fields invisible to `$veb.html()`.
- `$veb.html()` resolves relative to compile-time cwd.
- StaticHandler: `App` MUST embed `veb.StaticHandler`; `handle_static` panics on unknown extensions.
- i18n: prefer `vlib/i18n` (`load_tr_map`, `tr`) over `veb.tr`. `veb.tr` returns value + trailing newline.
- `http.new_header()` then `.add()`/`.add_custom()`. `+` operator NOT supported.
- `http.Request` has NO `.cookies()`. Use `http.read_cookies(req.header, name)`.
- `cookie.value` is a field, not a method.

## JSON (references/json_http.md + i18n_json2.md)

- Use `import json2` (canonical). `x.json2` is legacy alias.
- `json2.decode[T](body, json2.DecoderOptions{}) !T` — 2-arg, unwrap with `or {}`.
- `json2.encode[T](val, json2.EncoderOptions{})` — 2-arg.
- `json2.Any` variants exclude `[]map[string]string`. Wrap nested JSON at every layer.
- `map[string]json2.Any` index: `m['k'] or { json2.Any{} }`.

## DB / ORM (references/db_orm.md)

- String PK: `id string @[primary]` (V infers TEXT). NEVER `string @[primary; sql: text]`.
- `int @[primary]` TRAP → ORM writes `id=0` → 2nd row UNIQUE conflict. Use string PK + generate id.
- `insert ... into T` or-block must be non-empty returning int: `or { 0 }`.
- `delete` requires `where`. Truncate via raw `db.exec('DELETE FROM T') or {}`.
- ORM `select` has NO `order by`. Sort in V.
- ORM `where` bare id resolves RECEIVER name BEFORE column. Rename receiver if clashes.
- Test isolation: unique temp DB per test. Stale binary → rebuild.

## OpenAI / SSE (references/openai_llm.md + json_http.md)

- `type` field → `ty string @[json: 'type']` (else serializes as `ty`).
- `parameters` must be JSON object, NOT string. Type `json2.Any`, build via decode.
- Tool messages need `tool_call_id` matching `tool_calls[].id`. First message must be `role: system`.
- SSE: `http.Request` + `on_progress_body`. Closure is COPY — don't accumulate state inside it. Re-parse `resp.body` after `do()`.
- 401 = key problem. 400 = wire-format.

## C FFI (references/c_ffi.md)

- `#include` paths at top level (NOT inside `#[...]`). Use relative paths; absolute paths break when the module is moved.
- C fn decl: `fn C.mmap(...) voidptr` (NO colon).
- Linking: `#include "x.c"` + `@[c_extern]` fn C.x(...). `#flag x.o` does NOT link in 0.5.2.
- C signature must match V pointer types. Drop `const` in C if V has `&u8`.
- Mmap→V slice: pointer slicing/`unsafe { cast(&u8 addr) }` FAILS at C level. Allocate `[]u8{len: size}` + `C.memcpy(data.data, addr, u64(size))`. `os.File.fd` inaccessible → use `C.open` + `C.close`.

## Go → V (references/go2v.md)

- go2v = draft generator. Classify modules: A (pure logic), B (native rewrite), C (blocked).
- Translate SINGLE .go file (dir mode expects .vv fixtures).
- Install: `git clone https://github.com/vlang/go2v`; pre-install `GOPROXY=direct go install github.com/asty-org/asty@latest`.

## GUI (references/gui.md)

- `vlib/ui` + `gui` both use sokol — cannot coexist in one binary.
- `gui` NOT in vlib/. Vendor `src/examples/gui/` into project. App struct must be `@[heap]`.

## Testing (references/testing.md)

- Conventions: `xxx_test.v`, fn `test_xxx()`, `assert`.
- Gate before declaring done: `~/v/v fmt -w . && ~/v/v vet . && ~/v/v -silent test .`
- Single-file test cwd = test file dir → template/i18n paths break. Run `~v/v test .` from project root.
- Stale `execute_code` binary trap: rebuild after edits. Temp DB per test.

## Skill repo conventions

- Main source of truth: `SKILL.md` (~10KB). Per-topic detail: `references/xxx.md`.
- Templates: `templates/*.v` (veb_app, rest_handler, sqlite_store, openai_agent, cli_app, test_suite).
- Maintenance rule: every V 0.5.x pitfall gets recorded in BOTH `~/.vaiv/conventions.md` and the matching `references/*.md`.
- User pref: module names short, without project prefix. Rename `db` → `dbase` to avoid stdlib clash. Standalone utility → standalone module (e.g. `syntax/syntax.v`).
