# OpenAI-compatible chat wire-format verification recipe

When a V `x.json2`-serialized `/chat/completions` body gets HTTP 400 from a real
provider (Shangtang sensenova, OpenAI, OpenRouter, Ollama, llama.cpp, ...) but
`v vet` is clean, the bug is almost always one of the three in the SKILL.md
"OpenAI-compatible chat wire format" section. This recipe isolates WHICH one fast,
without rebuilding the V program each time.

## 1. Capture the exact request body the V program sends
Temporarily dump the encoded body (do NOT hand-build it — you want the ACTUAL
serialized output to compare against what the endpoint accepts):

```v
// in the chat() fn, right after `body := json2.encode(req_body, ...)`:
os.write_file('./vaiv_body.json', body) or {}
println('VAIVBODY${body}VAIVBODY')
```

Then run the program once and extract:
```bash
./bin/vaiv "read v.mod" 2>&1 | grep -o 'VAIVBODY.*VAIVBODY' | sed 's/VAIVBODY//g' > /tmp/vaiv_body.json
wc -c /tmp/vaiv_body.json   # must be > 0; if 0, the println went to a buffered
                            # pipe — write to a file in cwd instead and read it.
```
(The `./vaiv_body.json` file write is the reliable path; `println` can be swallowed
by `v run`'s output buffering. Remember to REMOVE the debug lines after.)

## 2. Bisect tools vs messages with a standalone Python probe
Send the captured body AS-IS first; if it 400s, split the cause by sending
subsets. This probe uses only stdlib so it runs anywhere:

```python
import json, os, urllib.request
KEY = os.getenv('VCA_API_KEY')
URL = os.getenv('VCA_BASE_URL', 'https://token.sensenova.cn/v1') + '/chat/completions'

# Paste ONE tool def here (copy from the captured body's "tools" array):
tool = {"type":"function","function":{"name":"read_file",
  "description":"Read a file.","parameters":{"type":"object",
  "properties":{"path":{"type":"string"}},"required":["path"]}}}

def call(tools):
    body = {"model": os.getenv('VCA_MODEL','sensenova-6.7-flash-lite'),
            "messages":[{"role":"user","content":"read v.mod"}],
            "tools": tools}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {KEY}",
                     "Content-Type":"application/json"}, method="POST")
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, r.read().decode()[:120]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:160]

print("NO TOOLS   :", call([]))            # 200 => model/chat path OK
print("1 TOOL obj :", call([tool]))        # 200 => this tool's schema OK
# If 1 TOOL 400s but NO TOOLS 200s -> the tool's `parameters` is a STRING, not object.
```

- NO TOOLS -> 200, WITH tools -> 400 => a tool schema problem (bug #1 `ty` or
  bug #2 string-`parameters`). Send tools ONE AT A TIME (loop `call([t])` over each
  captured tool) to find the exact offender. The offending tool's `parameters` will
  appear as `"parameters":"{...}"` (quoted/escaped) instead of `"parameters":{...}`.
- tools OK but multi-turn 400 (`invalid tool_call_id` / `System message must be at
  the beginning`) => bug #3 — the `messages` array lacks `tool_call_id` on tool
  results or a leading `system` message.

## 3. The three fixes (apply in the V code, not the probe)
- `ty string` -> `ty string @[json: 'type']`  (emits `"type":"function"`)
- `ToolFunction.parameters` `string` -> `json2.Any`, built with
  `json2.decode[json2.Any]('{schema}') or { json2.Any{} }`  (emits object, not string)
- `Message.to_json()` -> return `json2.Any`; emit `tool_calls[]` (with `id`,
  `type:"function"`, `function{name,arguments}`) and `tool_call_id` for tool
  messages; `ChatRequest.messages` -> `[]json2.Any`. Thread `tool_call_id: tc.id`
  (NOT `tc.name`) through the tool executor. `run()` prepends a `system` message
  if `history[0].role != .system`.

## 4. Re-verify against the LIVE endpoint (not the probe)
After fixing, run the real binary with the real key and confirm a tool actually
fires and the loop closes:
```bash
rm -f data/session.sqlite          # avoid stale history without a leading system msg
VCA_PROVIDER=shangtang ./bin/vaiv "read v.mod and tell me the module name"
# Expect: [tool] read_file(...)  then a final answer.
```
WARNING: a 200 from the Python probe with hand-built tools only proves the SCHEMA is
accepted — it does NOT prove the V program emits it correctly. Always finish with
step 4.

## Gotcha: editing tool defs in MANY files
When you change `parameters` from string->`json2.Any`, grep EVERY `parameters:` in
the module. Tools are often split across files (`tools.v`, `devtools.v`,
`patch.v`, ...); a single missed one keeps the whole request at 400. Use:
```bash
grep -rn "parameters:" agent/*.v
```
and confirm none still read `parameters:  '{...}'` (string form).
