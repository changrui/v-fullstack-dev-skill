# V 0.5.x OpenAI-compatible LLM wiring — deep detail

Companion to `v-fullstack-dev` SKILL.md. When wiring a ReAct agent to any
OpenAI-compatible `/v1/chat/completions` (Shangtang sensenova, OpenRouter, Ollama,
llama.cpp, vLLM, …) in V 0.5.x with `x.json2`, three serialization bugs cause HTTP
400 even when `v vet` is clean. All three hit and fixed when wiring vaiv to a real
provider. Run this checklist before claiming a provider "works".

## Bug 1: `type` field serializes as `ty`
- A struct field `ty string` (OpenAI tool `type: "function"`) with NO json tag makes
  `json2.encode` emit `"ty":"function"` → endpoint 400s. Fix: `ty string @[json: 'type']`
  so it emits `"type":"function"`. (V's json2 honors `@[json: 'x']` tags; omitting
  uses the bare field name.)

## Bug 2: `parameters` must be a JSON OBJECT, not a string
- Typing `ToolFunction.parameters` as `string` (holding JSON-schema text) serializes
  to `"parameters":"{...}"` (an escaped STRING) → `400 invalid arguments`. Fix: type
  it `json2.Any` and construct via
  `json2.decode[json2.Any]('{...schema...}') or { json2.Any{} }` so it serializes as
  `"parameters":{...}` (a real object).
- ⚠️ **Cover EVERY tool definition.** The change must reach ALL `ToolDef`s — the
  obvious ones AND any in OTHER files (e.g. a `patch` tool defined in `patch.v`, not
  `tools.v` — missing it silently breaks the whole request). Bisect by sending
  subsets of tools to the endpoint.
- Verify clean: `grep -rn '"parameters":"' agent/` → ZERO matches (the string form's
  telltale is that escaped double-quote prefix).

## Bug 3: multi-turn tool results need `tool_call_id` + `tool_calls[]`
- Compatible endpoints require the tool-result message to carry `tool_call_id`
  matching the assistant turn's `tool_calls[].id`, else `400 invalid tool_call_id`.
- They also require the FIRST message to be `role: "system"`
  (`400 System message must be at the beginning`).
- V's `map[string]string` can't express `tool_calls` (array) or `tool_call_id`, so:
  - `Message.to_json()` returns `json2.Any` (a `map[string]json2.Any`), conditionally
    adding `tool_calls` (array of `{id, type:"function", function:{name, arguments}}`)
    and `tool_call_id` when present.
  - `ChatRequest.messages` changes `[]map[string]string` → `[]json2.Any`.
  - Thread `tool_call_id` through the executor: `execute(name, args, ctx, tc.id)` and
    set `tool_call_id: tc.id` on the result (NOT `tc.name` — that was a bug). Mock
    mode's `ToolCall{ id: 'call_1', ... }` already supplies the id.
  - `run()` must `prepend` a system message if `history[0].role != .system` (a persisted
    SQLite session may not start with system even when main.v prepends one for fresh
    sessions).
  - **Nested `map[string]json2.Any{}` init**: V rejects the inline literal
    `map[string]json2.Any{ 'k': json2.Any(v) }` inside a larger expression ("explicit
    map initialization does not support parameters"). Build it with
    `mut m := map[string]json2.Any{}; m['k'] = json2.Any(v)` then assign.

## Auth header is independent
- `Authorization: Bearer $KEY` is correct. A 401 means a key problem; a 400 means a
  wire-format problem (use the checklist above).

## Streaming (SSE) — V 0.5.x closure traps (see json_http.md for the core trap)
- Use `http.Request` + `on_progress_body`; the callback is COPY-semantics — don't
  accumulate state inside it, re-parse `resp.body` after `do()`.
- Shangtang emits `reasoning` BEFORE `content`; capture both.
- `ChatRequest` needs `stream bool @[json: 'stream']` for the correct wire field name.

## Verification recipe (curl bisection — don't guess)
When a real call 400s, isolate with minimal repro + bisection:
1. **Confirm the model works:** send a request WITHOUT `tools`:
   `curl -s -X POST $BASE/chat/completions -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{"model":"...","messages":[{"role":"user","content":"hi"}]}'`
   → 200 means model/auth OK; problem is in tools/messages format.
2. **Bisect tools:** split N tools into halves, send each once, locate the rejecting tool.
3. **Capture the real request body:** in `llm.chat`, `os.write_file('./last_body.json', body)`
   or `println(body)`; compare the actual JSON against a working minimal request
   (messages structure, `parameters` object-ness, `tool_call_id` presence).
4. **Reproduce by hand:** save the body, `curl -d @body.json ...`, delete fields until
   400→200; the deleted block is the culprit.
- ⚠️ Remove debug `write_file`/`println` after verifying — `v vet` may error on unused
  `os` import or polluted output.

## Fallback: OpenRouter
If an endpoint perpetually 400s and you can't quickly find the cause, fall back to
OpenRouter (strictest OpenAI adherence; accepts all three fixed formats):
```bash
export VCA_PROVIDER=openrouter
export VCA_BASE_URL=https://openrouter.ai/api/v1
export VCA_API_KEY=sk-or-...
export VCA_MODEL=...
```
Note `provider` spelling: `openAI` (capital I) misroutes to the openai branch and is
non-idiomatic — write `openai` or `openrouter`.

## 400 troubleshooting checklist
- [ ] `Authorization: Bearer $KEY`? → 401 = key problem.
- [ ] Every tool's `type` is `"type"` not `"ty"`? (Bug 1)
- [ ] Every tool's `parameters` is an OBJECT not a string? (`grep '"parameters":"'` → 0)
- [ ] The `patch` tool's `parameters` also fixed? (Bug 2 classic miss, in `patch.v`)
- [ ] Tool-calling turns: assistant has `tool_calls[].id`, tool msg has matching
      `tool_call_id`? (Bug 3)
- [ ] history[0] is `role: system`? (Bug 3-④)
- [ ] All above OK still 400 → curl bisection on the captured body.
