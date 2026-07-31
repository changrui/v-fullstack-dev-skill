# veb 0.5.x — web server & templates, deep detail

Companion to `v-fullstack-dev` SKILL.md. All patterns verified on V 0.5.x.

## Route attribute syntax (VERIFIED)
The parser reads attrs left-to-right, splitting `@[...]` on `;`/space. Working:
- Path-only GET: `@['/path']` (method inferred GET).
- Method-only (path from fn name): `[post]` → route `/fn_name`.
- **POST-with-path (the form that works): `@['/path'; post]` and `@['/path'; get]` —
  path FIRST, then `;` + space, then method.**
- **INVALID (panic `unexpected extra attributes`):** `@[post: '/path']`,
  `@[post; '/path']`, `@[get: '/']`. The combined MUST be exactly `@['/path'; post]`.

Path params: `@['/country/:iso3']` → handler arg `iso3 string` CAN compile, but
see the codegen quirk below — prefer `?id=` query params in this build.

## Template variable scope (CRITICAL)
`$veb.html()` inherits the HANDLER'S LOCAL SCOPE. `@foo` resolves against locals
declared in the handler, NOT `App`/`Context` struct fields. Declaring page data on
struct fields → `undefined ident: foo`. `before_request` sets `Context` fields
(e.g. `ctx.lang`); the handler copies them into locals (`lang := ctx.lang`) for
`@lang` to work.

## `$veb.html()` path resolution
Relative to COMPILE-TIME cwd. With explicit path it first looks next to the .v
file, then falls back to searching from the `v.mod` root. Build
`v -o bin cmd/serve/main.v` from the project root with
`return $veb.html('internal/server/templates/index.html')`. (`v build` rejected — use
`v -o <out> <file>`.)

## `ctx.json()` payload
- Anonymous struct literal `{ error: 'x' }` fails (`undefined ident: error`). Use
  `mut m := map[string]string{}; m['message'] = '...'; return ctx.json(m)`, or a
  named struct.
- `ctx.redirect(url, veb.RedirectParams{})` works.

## Static files
- `mut sh := veb.StaticHandler{}; sh.handle_static(path, true) or {}` does NOTHING —
  veb finds the `StaticHandler` only by reflecting on the `App` struct's embedded
  fields. So `App` MUST embed `veb.StaticHandler` and you call
  `app.handle_static(path, root)` on the `app` value:
```v
struct App { veb.StaticHandler; mut: repo repository.Repository }
fn main() {
    mut app := &App{ ... }
    app.handle_static('./internal/server/static', true) or {}
    veb.run_at[App, Context](mut app, port: 8080, family: .ip) or { panic(err) }
}
```
- `root=true` mounts at `/` preserving subdirs (`static/css/x.css` → `/css/x.css`).
  `root=false` mounts under `/<dir>`.
- **CRITICAL: `handle_static` PANICS on any file with an unknown extension** (`.bak`,
  `.tmp`). A stray `app.js.bak` in the static dir silently drops every file scanned
  AFTER it. Keep the static dir free of non-standard extensions.

## veb.tr / i18n
- `veb.tr(lang, key)` where `lang` is `string`. Startup walks `translations/*.tr`
  from cwd (`os.walk_ext('translations', '.tr')`). `.tr` format: each entry
  `key\nvalue`, entries separated by `-----`. Templates use `%key`. Missing key →
  `NO TRANSLATION FOR KEY`.
- **`veb.tr` returns the value WITH a trailing newline** — trim it:
  `m[k] = veb.tr(lang, k).trim('\\n')`.
- **CRITICAL `.tr` format pitfall:** veb's `parse_tr_text` splits on `-----\n`,
  then takes the first `\n` in each section as the key/value boundary. If multiple
  key-value pairs land in the SAME section (missing `-----` separator), ALL
  subsequent keys become part of the preceding value — the handler sees empty
  strings for those keys. **Every key-value pair MUST be in its own section:**
  ```
  key1
  value1
  -----
  key2
  value2
  -----
  ```
  Adding a key without its `-----` prefix silently merges it into the previous
  value. Validate: split on `-----\n`, assert each section has exactly one `\n`
  separating a non-empty key from a non-empty value.

## run_at[A, X] generics
- `X` MUST embed `veb.Context` as a field literally named `Context` (veb codegens
  `X{ Context: ctx }`). Declare:
```v
pub struct WebCtx { veb.Context }
pub fn (mut app WebApp) handler(mut ctx WebCtx) veb.Result { ... }
```
- The handler's 2nd param is `mut ctx WebCtx` (the embedding type), NOT
  `veb.Context` directly.

## Path-param routes hit a codegen quirk
- `@['/sessions/:id']` with `(mut ctx WebCtx, id string)` compiled but dispatch
  errored (`cannot use agent.WebCtx as &veb.Context`). Fix: drop `:id`; use query
  params — `@['/sessions']` + `id := ctx.query['id'] or { return ctx.text('missing id') }`.
  `ctx.query['id']` is reliable; path params are not in this veb.
- `ctx.get_cookie(key) ?string` (NOT `ctx.cookie()`). `set_cookie` takes named args:
  `ctx.set_cookie(name: 'x', value: 'y', path: '/', max_age: 31536000)`.

## SSE streaming (veb.sse)
```v
@['/api/stream'; post]
pub fn (mut app WebApp) stream(mut ctx WebCtx) veb.Result {
    raw := ctx.req.data
    ctx.takeover_conn()
    mut sse_conn := sse.start_connection(mut ctx)
    sse_conn.send_message(data: '{"role":"assistant"}') or {}
    sse_conn.send_message(event: 'done', data: 'END') or {}
    sse_conn.close()
    return veb.no_result()
}
```
- `veb.no_result()` means "I sent the response myself over the taken-over conn".
- Client reads `data:` lines; close with `event: done` then `data: END`.

## Template `@(fn())` is BROKEN in this build
- `@(RawHtml(veb.tr(...)))` errors. Fix: compute i18n/derived values as handler
  LOCAL vars, reference with `@var`.
- `@css '/x.css'` / `@js '/x.js'` work, BUT `@css '/x.css?v=1'` breaks the parser —
  use plain `<link href='/style.css'>` / `<script src='/app.js'>` tags.
- `map[key].method()` mis-parses — assign the value to a local first: `v := m['k']; v.trim('\n')`.

## `sync.Mutex` for an in-memory store
- `sync.new_mutex()` returns `&Mutex`; lock/unlock explicitly (no `defer`):
```v
mut mu := sync.new_mutex()
mu.lock(); /* ... */; mu.unlock()
```
- `get(id)` must return a real `?T`: check `if id !in m { mu.unlock(); return none }`
  BEFORE reading — `m[id]` on a missing key returns the zero value, not `none`.

## ⚠️ Windows: veb 0.5.2 comptime bug & `net.http.Server` alternative

On Windows with V 0.5.2 (b07c40e), veb hits an internal comptime error:
```
internal error: expression has no value
```
This is a compiler bug in the Windows codegen path for `veb.run_at[A, X]`. **Do not
attempt to debug or work around it** — the bug is at comptime evaluation, not in user
code.

### Alternative: `net.http.Server` + `Handler` interface

V's `net.http` module provides a `Server` struct that accepts a `Handler` interface
(one method: `handle(req http.Request) http.Response`). This compiles and runs cleanly
on both Windows and Linux:

```v
module main

import net.http
import os

pub struct App {
pub:
    template_html string
}

// Handle implements http.Handler
pub fn (mut app App) handle(req http.Request) http.Response {
    url := req.url
    if url == '/' || url == '' {
        return app.handle_home(req)
    }
    if url.starts_with('/api/') {
        return app.handle_api(req)
    }
    // 404
    mut h := http.new_header()
    h.add(.content_type, 'text/plain')
    return http.Response{ status_code: 404, body: 'Not Found', header: h }
}

fn main() {
    mut app := &App{ template_html: os.read_file('templates/index.html') or { panic(err) } }
    mut server := http.Server{
        addr: ':8080'
        handler: app
        show_startup_message: true
    }
    server.listen_and_serve()
}
```

### Route dispatch patterns (no path-params)

Since `net.http` doesn't support veb-style path-params (`:id`), dispatch manually:

```v
pub fn (mut app App) handle(req http.Request) http.Response {
    url := req.url
    if url == '/' { return app.handle_index(req) }
    if url.starts_with('/set-lang') { return app.handle_set_lang(req) }
    if url.starts_with('/api/countries') { return app.handle_api_countries(req) }
    if url.starts_with('/api/categories') { return app.handle_api_categories(req) }
    if url.starts_with('/api/data') { return app.handle_api_data(req) }
    if url.starts_with('/api/search') { return app.handle_api_search(req) }
    // static
    if url == '/style.css' || url == '/app.js' { return app.serve_static(url) }
    // 404
    ...
}
```

Query params: implement a simple manual parser since `net.urllib` parse is verbose:
```v
fn parse_query(url_str string) map[string]string {
    mut result := map[string]string{}
    qmark := url_str.index('?') or { return result }
    for part in url_str[qmark + 1..].split('&') {
        eq := part.index('=') or { continue }
        result[part[..eq]] = part[eq + 1..]
    }
    return result
}
```

### http.Request / Response API notes (raw `net.http`)
- `req.url` — full URL string including query (e.g. `/api/data?indicator=X&country=Y`)
- `req.method` — `.get` / `.post` etc.
- `req.header` — `http.Header` value struct
- **`req.cookie(name)` 存在** — `req.cookie('token')` 返回 `?Cookie`（单 cookie）。
  如需要多个同名 cookie，用 `http.read_cookies(req.header, 'name')` 返回 `[]&Cookie`
- `resp = http.Response{ status_code: 200, body: '...', header: h }`
- `h := http.new_header()` — then `.add(.content_type, 'text/html')`, `.add(.location, '/')`,
  `.add_custom('Set-Cookie', 'key=val; Path=/')`

### SQLite caching in `net.http` handlers
When building a REST API without veb, use raw `db.sqlite` for caching:
```v
fn (app App) cache_get(key string) ?string {
    rows := app.db.exec_param2('SELECT value FROM cache WHERE key = ? AND created_at > ?',
        key, time.now().unix_milli().str()) or { return none }
    if rows.len == 0 { return none }
    return rows[0].vals[0]
}
fn (app App) cache_set(key string, value string) {
    app.db.exec_param_many('INSERT OR REPLACE INTO cache (key, value, created_at) VALUES (?, ?, ?)',
        [key, value, time.now().unix_milli().str()]) or { eprintln('cache err: ${err}') }
}
```

## HTTP-level integration tests (veb test pattern)
- Boot the real app in a goroutine and hit it with `net.http`.
- `spawn` CANNOT take mutable non-reference args → make the app a reference:
```v
mut app := &WebApp{ store: new_test_store(), config: Config{} }
spawn fn [mut app] () {
    veb.run_at[WebApp, WebCtx](mut app, port: test_port) or { panic(err) }
}()
// then: http.fetch(http.FetchConfig{ url: 'http://localhost:${test_port}/' })
```
- `Config` with default bools (e.g. `allow_write: false`) keeps tests offline-safe.
