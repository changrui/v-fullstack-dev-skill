# V 0.5.x JSON & HTTP — deep detail

Companion to `v-fullstack-dev` SKILL.md.

## json2 (typed JSON)
- Use the canonical `import json2` (NOT `x.json2` — it's now a legacy alias).
- See `references/i18n_json2.md` for the authoritative decode/encode signatures.
- World Bank-style `[meta, data]` envelope: decode as `[]json2.Any`, then
  `arr[0].as_map()` (pager) and `arr[1].as_array()` (rows).
- Extract scalars: `.str()`, `.f64()`, `.int()`, `.as_map()`, `.as_array()`,
  `.json_str()` (compare `== 'null'` to detect nulls).
- Map index returns an Option: `m['key'] or { json2.Any{} }`.
- **Indexing `map[string]json2.Any` REQUIRES `or {}` even when sure the key exists**
  (`o['provider'].str()` without `or {}` → warning "or {} block required ...", error
  under `-strict`). Safe pattern: build a string via `o['provider'].json_str()` and
  `assert encoded.contains('"provider":"mock"')`; or `p := o['provider'] or { json2.Any{} }; assert p.str() == 'mock'`.

## net.http
- `http.get(url)` returns `!Response`; body via `.body` (string):
  `resp := http.get(url) or { return err }; body := resp.body`. `resp.status_code`
  available.
- `http.Request` is MINIMAL in 0.5.1: only `filename`, `content_type`, `data` fields.
  NO `user_agent`, `timeout`, `url`, `method`. Don't build a Request struct for GET.
- **`net.http` full-module `Request` builder quirk (0.5.1):** building
  `net.http.Request{ method: .get, url: ..., read_timeout: ... }` then `req.do() !Response`
  and reading the body via `resp.body` (field) OR `resp.text()` (method) can fail with
  `assignment mismatch: 0 values` — the compiler mis-treats `resp.body` as a void
  method. Reliable fallback (also reuses "prefer system tools" + "exec gate" rules):
  `res := os.execute('curl -s --max-time 10 -A "ua" "${url}"')`; on `res.exit_code == 0`
  parse `res.output`. (vaiv's `web_search` hit this exact error and switched to curl.)
  The top-level `import http` + `http.get(url)` form is still fine for simple GETs —
  the quirk is specific to the `net.http.Request` builder path.

## HTML escaping before injection
- Any LLM/user-generated text rendered into a template or SSE HTML MUST be escaped
  (`&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`) to prevent injection. A self-rolled
  highlighter must escape both token text and gaps.

## SSE streaming (real-time token flow) — V 0.5.x traps
- Use `http.Request` with `on_progress_body` callback, set `read_timeout`, then
  `req.do()`.
- **Closure capture is COPY semantics (the #1 killer):** `fn [mut x] (...)` closure
  mutations do NOT reflect to the caller (`buf`/`full`/`n` stay empty). `*ptr +=`
  needs `unsafe` (forbidden). → Do NOT accumulate state inside `on_progress_body`.
  The closure should only do a real-time SIDE EFFECT (call `on_token(kind, delta)` to
  push). Re-assemble the full message from `req.do()`'s returned `resp.body` (the
  complete response) AFTER the call returns.
- `[heap]` struct does NOT fix the copy either — use `resp.body` re-parse.
- Shangtang emits `reasoning` BEFORE `content`: `delta.reasoning` is the thinking
  chain, `delta.content` is the final answer. Capture BOTH (frontend shows reasoning
  in grey italic) — otherwise you see empty content or only the thinking.
- `buf.index('\n')` returns `?int` → `nl := buf.index('\n') or { -1 }; if nl < 0 { break }`
  (not `if nl := ...; nl >= 0` — V doesn't support short-decl+condition combo).
- Array element fields can't be mutated in place (`tcs[i].id = x` → immutable) →
  replace the whole element or take out/modify/put back.
- `ChatRequest` needs `stream bool @[json: 'stream']` for the correct wire field name.

See `references/openai_llm.md` for the full chat/completions wire format, and
`references/streaming_sse_v051.md`-style recipes in the old `v-openai-compatible-llm-wirefmt`
skill if you need the exact probe code.

## net.http Header & Cookie API (verified 0.5.2)

`http.Header` is a **mutable value struct** — `+` operator is NOT supported:

```v
// ❌ WRONG — compile error: undefined operation
// return http.Response{ header: h1 + h2 }

// ✅ CORRECT
mut h := http.new_header()
h.add(.content_type, 'application/json')
h.add(.location, '/')
h.add_custom('Set-Cookie', 'lang=en; Path=/; Max-Age=31536000') or {}
```

**Available `CommonHeader` enum values:** `.content_type`, `.location`, `.cache_control`,
`.authorization`, `.accept`, `.set_cookie`, `.user_agent`, etc.

**`Request` has a `.cookie(name)` method (verified 0.5.2):** Use it directly to get a
single cookie by name:
```v
token := req.cookie('token') or { '' }
```
Or use `http.read_cookies()` if you need multiple cookies with the same name:
```v
cookies := http.read_cookies(req.header, 'lang')
if cookies.len > 0 {
    lang := cookies[0].value  // .value is a FIELD, not a method
}
```

**`http.Response` construction:**
```v
mut h := http.new_header()
h.add(.content_type, 'application/json')
return http.Response{ status_code: 200, body: '{"ok":true}', header: h }
```

## json2.Any building (common pitfall)

`json2.Any` variants: `[]Any | bool | f64 | f32 | i64 | int | i32 | i16 | i8 |
map[string]Any | string | time.Time | u64 | u32 | u16 | u8 | Null`.
**`[]map[string]string` is NOT a valid variant.** Wrap every level:

```v
mut indicators := []json2.Any{}
for ind in src {
    indicators << json2.Any({ 'id': json2.Any(ind.id), 'name': json2.Any(ind.name) })
}
cats << { 'id': json2.Any(cat.id), 'indicators': json2.Any(indicators) }
// Encode:
json2.encode[[]map[string]json2.Any](cats, json2.EncoderOptions{})
```

Check for null: `if val.json_str() == 'null' { /* null */ }`

## `map[string]bool` default immutability

```v
existing_ids := map[string]bool{}       // ❌ immutable
existing_ids['key'] = true              // compile error

mut existing_ids := map[string]bool{}   // ✅ mutable
existing_ids['key'] = true              // OK
```
