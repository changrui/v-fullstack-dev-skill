# Streaming SSE from an OpenAI-compatible endpoint in V 0.5.x

Condensed recipe + pitfalls from wiring real-time token streaming (vaiv to Shangtang
sensenova-6.7-flash-lite). The headline lesson: **V 0.5.x closures copy captured
variables**, so you cannot accumulate streamed state inside `on_progress_body` and
read it after `req.do()`.

## Minimal probe (verifies the endpoint actually streams chunk-by-chunk)

```v
import net.http
import os

fn main() {
    key := os.getenv('VCA_API_KEY')
    body := '{"model":"sensenova-6.7-flash-lite","messages":[{"role":"user","content":"say hi in 3 words"}],"stream":true}'
    mut req := http.Request{
        url: 'https://token.sensenova.cn/v1/chat/completions'
        method: .post
        header: http.new_custom_header_from_map({
            'Authorization': 'Bearer ${key}'
            'Content-Type': 'application/json'
        })!
        data: body
        on_progress_body: fn [mut calls] (req &http.Request, chunk []u8, so_far u64, expected u64, status int) ! {
            calls++
            s := chunk.bytestr()
            head := if s.len > 40 { s[0..40] } else { s }
            println('CALL#${calls} len=${chunk.len} head=${head}')
        }
    }
    resp := req.do() or { println('ERR ${err}'); return }
    println('done status=${resp.status_code} total_calls=${calls}')
}
```
If you see many `CALL#n len~270` lines, streaming works: the callback fires per
received chunk over HTTPS/HTTP2. On Shangtang each chunk is one full `data: {...}`
SSE line followed by `\n\n`.

## Correct streaming structure

```v
pub fn (c Client) chat_stream(messages []Message, tools []ToolDef, on_token fn (kind string, delta string)) !Message {
    // ... build req_body with stream: true ...
    mut tmpbuf := ''          // closure-local scratch only
    mut header := http.new_custom_header_from_map({...})!
    mut req := http.Request{
        url: c.config.base_url + '/chat/completions'
        method: .post
        header: header
        data: body
        on_progress_body: fn [mut tmpbuf, on_token] (req &http.Request, chunk []u8, so_far u64, expected u64, status int) ! {
            tmpbuf += chunk.bytestr()
            for {
                nl := tmpbuf.index('\n') or { -1 }
                if nl < 0 { break }
                line := tmpbuf[0..nl]
                tmpbuf = tmpbuf[nl + 1..]
                if !line.starts_with('data: ') { continue }
                payload := line[6..].trim(' \t')
                // Forward deltas in real time. Do NOT accumulate full/tcs here:
                // closure-copied vars won't survive to after do().
                mut live := StreamState{}
                kind, delta := stream_apply(payload, mut live)
                if delta != '' { on_token(kind, delta) }
            }
        }
    }
    resp := req.do() or { return error('LLM HTTP ${err}') }
    // Assemble the complete reply from resp.body (fully buffered response).
    mut st := StreamState{}
    mut rest := resp.body
    for {
        nl := rest.index('\n') or { -1 }
        if nl < 0 { break }
        line := rest[0..nl]
        rest = rest[nl + 1..]
        if !line.starts_with('data: ') { continue }
        stream_apply(line[6..].trim(' \t'), mut st)
    }
    return Message{ role: .assistant, content: st.full, tool_calls: st.tcs }
}
```

`StreamState` carries the running accumulator and is passed as a `mut` argument
(structs can be `mut` params; plain `string` cannot):

```v
struct StreamState {
mut:
    full string
    tcs  []ToolCall
}
fn stream_apply(payload string, mut st StreamState) (string, string) {
    if payload == '[DONE]' { return '', '' }
    chunk_resp := json2.decode[StreamChunk](payload) or { return '', '' }
    if chunk_resp.choices.len == 0 { return '', '' }
    delta := chunk_resp.choices[0].delta
    if delta.reasoning != '' { st.full += delta.reasoning; return 'reasoning', delta.reasoning }
    if delta.content != ''   { st.full += delta.content;   return 'content',   delta.content }
    for dtc in delta.tool_calls {
        for dtc.index >= st.tcs.len { st.tcs << ToolCall{ id: '', name: '', arguments: '' } }
        tc := st.tcs[dtc.index]
        id := if dtc.id != '' { dtc.id } else { tc.id }
        name := tc.name + dtc.function.name
        args := tc.arguments + dtc.function.arguments
        st.tcs[dtc.index] = ToolCall{ id: id, name: name, arguments: args }
    }
    return '', ''
}
```

## Pitfalls (V 0.5.x)

1. **Closures copy captured vars.** `fn [mut x] (...)` modifications inside the
   closure do NOT propagate to the outer scope (verified: `buf`, `full`, `n` all
   stayed empty). `*ptr +=` needs `unsafe` and is forbidden. -> Do real-time
   side-effects only inside the callback (`on_token(...)`); re-parse `resp.body`
   after `do()` to assemble the full reply.
2. **`[heap]` structs don't help.** Tried `StreamSink @[heap]` — still not visible
   after `do()`. Use the `resp.body` re-parse approach.
3. **Shangtang sends `reasoning` before `content`.** `delta.reasoning` is the model
   thinking trace ("Thinking Process..."); `delta.content` is the final answer.
   Capture BOTH. If you only read `content` you'll see empty/blank output while the
   model is "thinking". Front-end: show `reasoning` muted/italic, `content` normal.
4. **`buf.index('\n')` returns `?int`.** Loop as `nl := buf.index('\n') or { -1 }; if nl < 0 { break }`. Do NOT write `if nl := buf.index('\n'); nl >= 0 { ... }` — V
   rejects the short-declaration-plus-condition form.
5. **Array element fields are immutable in place.** `tcs[i].id = x` errors. Either
   replace the element (`tcs[i] = ToolCall{...}`) or pull into `mut tc := tcs[i]`,
   mutate, then `tcs[i] = tc`.
6. **`ChatRequest` needs `stream bool @[json: 'stream']`** for the wire field name.

## SSE wire shape (OpenAI `stream:true`)

Each event: `data: {"id":...,"choices":[{"index":0,"delta":{"role":"assistant","content":"..."}}]}`.
Tool-call deltas arrive fragmented by `index`: `{delta:{tool_calls:[{index:0,id:"call_1",function:{name:"read_file",arguments:""}}]}}` then more chunks append to `arguments`. Align by `index` and concatenate.

## Wiring `chat_stream` into the agent loop (glue)

The streaming client is useless unless the agent calls it. Add an optional
callback to the Agent and switch on it inside `run()`:

```v
pub struct Agent {
    // ...
    on_token ?fn (string, string) // (kind, delta); unset for CLI / mock
}

// inside run(), where you currently call a.chat(history, defs):
mut reply := Message{}
if a.on_token != none && a.client.config.provider != 'mock' {
    cb := a.on_token or { return error('on_token unset') }
    reply = a.client.chat_stream(history, defs, cb) or { return error('LLM error: ${err}') }
} else {
    reply = a.client.chat(history, defs) or { return error('LLM error: ${err}') }
}
history << reply
```

CLI leaves `on_token` unset → `chat()` (non-stream) as before. A web handler sets
`a.on_token = fn [mut sse_conn] (kind string, delta string) { sse_conn.send_message(data: delta_event(kind, delta)) or {} }` before calling `run()`.

## Front-end: rendering streamed deltas (browser)

The server emits two SSE event shapes. Map them in the client:

```jsonc
// incremental token (many per reply)
{ "type": "delta", "kind": "content"|"reasoning", "content": "..." }
// complete message (tool result, or assistant-with-tool_calls)
{ "type": "message", "role": "tool"|"assistant"|"error", "content": "...", "tools": "read_file" }
```

`app.js` — accumulate deltas into the current assistant bubble; reasoning muted:

```js
let curBubble = null;
function renderEvent(obj) {
  if (obj.type === 'delta') { appendDelta(obj.kind || 'content', obj.content || ''); return; }
  if (obj.role === 'user') return;
  if (obj.role === 'tool') { /* tool tag + content */ return; }
  if (obj.role === 'assistant' || obj.role === 'error') { /* fallback full text */ }
}
function appendDelta(kind, text) {
  if (!curBubble) { curBubble = el('div', 'msg assistant'); log.appendChild(curBubble); }
  if (kind === 'reasoning') {
    let span = curBubble.querySelector('.reasoning');
    if (!span) { span = el('span', 'reasoning'); curBubble.appendChild(span); }
    span.appendChild(document.createTextNode(text));
  } else { curBubble.appendChild(document.createTextNode(text)); }
  scroll();
}
// reset at the start of each turn: curBubble = null;
```

```css
.msg.assistant .reasoning { display:block; color:#8a94a6; font-style:italic;
  font-size:12px; white-space:pre-wrap; margin-bottom:6px;
  border-left:2px solid #3a4356; padding-left:8px; }
```

Server side: when emitting the post-run history replay, **skip the final
assistant text message** (it was already streamed via deltas) to avoid
duplication; still emit `tool` messages and assistant messages that carry
`tool_calls` (show them as "calling tool X" status bubbles).
