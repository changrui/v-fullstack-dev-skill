# Shangtang sensenova — real-call verification recipe (vaiv, 2026-07-12)

Endpoint: `https://token.sensenova.cn/v1/chat/completions`
Auth: `Authorization: Bearer $VCA_API_KEY` (header — 401 = key problem)
Model used: `sensenova-6.7-flash-lite` (supports function calling / tool_calls).

## Observed error → cause → fix map (all HTTP 400)
| Error body | Root cause | Fix |
|---|---|---|
| `{"error":{"message":"invalid arguments","type":"invalid_request_error","code":"3"}}` | `parameters` serialized as STRING `"parameters":"{...}"` (one tool missed) OR `type` key was `ty` | make `parameters` a `json2.Any` object; `ty @[json: 'type']` |
| `{"error":{"message":"invalid tool_call_id",...}}` | tool-result message lacked `tool_call_id` matching assistant `tool_calls[].id` | thread `tool_call_id` through executor (see SKILL.md 坑3) |
| `{"error":{"message":"System message must be at the beginning",...}}` | first history message was not `role:system` (persisted session residue) | `run()` prepends system if `history[0].role != .system` |

Note: with ALL 8 tools as correct objects, Shangtang returns 200 even for a full
tool set — so a 400 `invalid arguments` means ONE tool's schema is wrong, not the
schema shape itself. Bisect by sending tool subsets.

## Minimal curl probes (no V binary needed)
```bash
KEY=$VCA_API_KEY
BASE=https://token.sensenova.cn/v1

# 1) model alive, no tools (200 => key+endpoint OK)
curl -s -o /tmp/r.json -w "%{http_code}\n" -X POST $BASE/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"sensenova-6.7-flash-lite","messages":[{"role":"user","content":"hi"}]}'

# 2) single simple tool (object parameters) => 200
curl -s -o /tmp/r.json -w "%{http_code}\n" -X POST $BASE/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{
    "model":"sensenova-6.7-flash-lite",
    "messages":[{"role":"user","content":"hi"}],
    "tools":[{"type":"function","function":{"name":"t","description":"d",
      "parameters":{"type":"object","properties":{"q":{"type":"string"}},"required":["q"]}}}]}'

# 3) STRING parameters => 400 (proves the bug)
curl -s -o /tmp/r.json -w "%{http_code}\n" -X POST $BASE/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{
    "model":"sensenova-6.7-flash-lite",
    "messages":[{"role":"user","content":"hi"}],
    "tools":[{"type":"function","function":{"name":"t","description":"d",
      "parameters":"{\"type\":\"object\"}"}}]}'   # <-- note the QUOTES
'
```

## Capturing the REAL request body from V
In `agent/llm.v` `chat()`, after `body := json2.encode(...)`:
```v
os.write_file('./last_body.json', body) or {}
```
Then `curl -d @last_body.json ...` and delete fields until 400→200.
**Remove the debug write_file + `os` import afterward** (or `v vet` may flag an
unused import / pollute test output).

## End-to-end via the vaiv binary (CLI + Web)
```bash
# CLI, real Shangtang
VCA_PROVIDER=shangtang ./bin/vaiv "read v.mod and tell me the module name"
# expect: [tool] read_file(...)  then  "The module name is `vaiv`."

# Web (build first!), real Shangtang
VAIV_WEB_PORT=8099 VCA_PROVIDER=shangtang ./bin/vaiv-web &
SID=$(curl -s -X POST http://localhost:8099/api/sessions | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
# sync:
curl -s -X POST "http://localhost:8099/api/session/chat?id=$SID" \
  -H "Content-Type: application/json" -d '{"message":"read v.mod and tell me the module name"}'
# SSE stream (watch for `event: done` / `data: END`):
curl -s -N -X POST "http://localhost:8099/api/session/stream?id=$SID" \
  -H "Content-Type: application/json" -d '{"message":"create a file x.txt with HELLO"}'
```
⚠️ Web chat body field is **`message`** (NOT the CLI's `prompt`) — wrong field ⇒
`{"error":"empty message"}`.
