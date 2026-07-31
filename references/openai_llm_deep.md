---
name: v-openai-compatible-llm-wirefmt
description: Archived deep-dive for OpenAI-compatible LLM wiring in V 0.5.x. The consolidated summary now lives in v-fullstack-dev (references/openai_llm.md). Load this ONLY when you need the exact SSE streaming probe code (references/streaming_sse_v051.md) or the Shangtang curl-verify recipe (references/shangtang_verify.md) that v-fullstack-dev points to. Do NOT load alongside v-fullstack-dev for the same task unless you need those exact files.
---

# V 0.5.x — OpenAI 兼容 LLM wire 格式坑（工具调用闭环）

当用 V 写一个调用 `/v1/chat/completions` 的 ReAct agent、接**任何 OpenAI 兼容端点**
（商汤 sensenova、OpenRouter、Ollama、llama.cpp、本地 vLLM 等）时，json2 的默认
序列化行为会和 OpenAI 规范产生三处冲突，全部表现为 **HTTP 400**。本 skill 是 vaiv
项目接商汤时实测踩平的三个坑 + 验证手法。

## 触发条件（何时加载本 skill）
- 真实 LLM 调用返回 `400 invalid arguments` / `400 invalid tool_call_id` /
  `400 System message must be at the beginning`（mock 模式永远不暴露，因为 mock
  不验证请求体）。
- 排查顺序：先看 Authorization 头（401=密钥问题，400=请求体问题），再按下面三条查。

---

## 坑 1：`ToolDef` 的 `type` 字段被序列化成 `ty`

json2 对**没有 `@[json:]` tag 的字段**用字段名序列化。`ty string` 会输出 `"ty":"function"`，
OpenAI 规范要的是 `"type":"function"`。

错误：
```v
pub struct ToolDef {
    ty       string // 序列化出 "ty":"function" ❌ 商汤 400
    function ToolFunction
}
```
正确：
```v
pub struct ToolDef {
    ty       string @[json: 'type'] // ✅ 输出 "type":"function"
    function ToolFunction
}
```

---

## 坑 2：`ToolFunction.parameters` 必须是 JSON **对象**，不是字符串

最隐蔽的坑。若字段是 `string` 且你存的是手写 JSON 文本，json2 会把它序列化成
转义字符串 `"parameters":"{...}"`，但 OpenAI 规范要的是对象 `"parameters":{...}`。
商汤对此直接 `400 invalid arguments`。

错误：
```v
pub struct ToolFunction {
    name        string
    description string
    parameters  string // ❌ 序列化成 "parameters":"{\"type\":\"object\",...}" → 400
}
// 构造：
parameters: '{"type":"object","properties":{...}}'
```
正确：
```v
import x.json2
pub struct ToolFunction {
    name        string
    description string
    parameters  json2.Any // ✅ 对象
}
// 构造（每个工具定义处都要这样写）：
parameters: json2.decode[json2.Any]('{"type":"object","properties":{...}}') or { json2.Any{} }
```

⚠️ **易漏改点（vaiv 真实踩过的）**：`parameters` 这类改动必须覆盖**所有**
工具定义文件，而工具定义往往分散在多个文件：
- `agent/tools.v`（read/write/search/terminal）
- `agent/devtools.v`（vet/fmt/test）
- `agent/patch.v`（**patch 工具！** 它定义在 patch.v 而非 tools.v，批量替换
  时极容易只扫了 tools.v 漏掉它 → 7 个工具里只有 patch 还是字符串 → 400）

批量替换后用 `grep -rn '"parameters":"' agent/` 确认**零匹配**才算干净
（字符串形式的特征就是这个转义双引号前缀）。

---

## 坑 3：多轮工具对话缺 `tool_call_id` / `tool_calls`

OpenAI 规范要求：assistant 返回 `tool_calls:[{id, type:"function", function:{name,arguments}}]`，
而工具执行结果那条消息必须是 `role:"tool"` **且带 `tool_call_id`**，值等于对应
`tool_calls[].id`。缺了就 `400 invalid tool_call_id`。

原 `Message.to_json()` 返回 `map[string]string` 根本塞不进数组/嵌套字段，是根因。

