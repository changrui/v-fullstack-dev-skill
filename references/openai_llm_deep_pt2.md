### 修复步骤（四步，缺一不可）

**① `to_json()` 改返回 `json2.Any`，条件性加字段**（V 的 map 初始化不支持
`map[string]json2.Any{'k': json2.Any(x)}` 这种内联写法，必须 `mut m := map[...]{}`
再逐键赋值）：
```v
pub fn (m Message) to_json() json2.Any {
    mut o := map[string]json2.Any{}
    o['role'] = json2.Any(match m.role {
        .system { 'system' } .user { 'user' }
        .assistant { 'assistant' } .tool { 'tool' }
    })
    o['content'] = json2.Any(m.content)
    if m.tool_calls.len > 0 {
        mut tcs := []json2.Any{}
        for tc in m.tool_calls {
            mut fnm := map[string]json2.Any{}
            fnm['name'] = json2.Any(tc.name)
            fnm['arguments'] = json2.Any(tc.arguments)
            mut tcobj := map[string]json2.Any{}
            tcobj['id'] = json2.Any(tc.id)
            tcobj['type'] = json2.Any('function')
            tcobj['function'] = json2.Any(fnm)
            tcs << json2.Any(tcobj)
        }
        o['tool_calls'] = json2.Any(tcs)
    }
    if m.role == .tool && m.tool_call_id != '' {
        o['tool_call_id'] = json2.Any(m.tool_call_id)
    }
    return json2.Any(o)
}
```

**② `ChatRequest.messages` 由 `[]map[string]string` 改为 `[]json2.Any`**（流式还需 `stream` 字段）：
```v
struct ChatRequest {
    model    string
    messages []json2.Any   // ✅ 不再是 []map[string]string
    tools    []ToolDef
    stream   bool @[json: 'stream'] // ✅ 真流式时置 true（见下"流式输出"段）
}
```

**③ `execute` 接收 `tool_call_id` 并回填正确的 id**（原代码误用 `tc.name`，是 bug）：
```v
pub fn (tools []Tool) execute(name string, args string, ctx &ToolCtx, tool_call_id string) ?Message {
    t := find(tools, name) or { return none }
    r := t.run?(args, ctx)
    content := if r.ok { r.output } else { 'ERROR: ${r.output}' }
    return Message{ role: .tool, content: content, tool_call_id: tool_call_id }
}
// 调用处：res := a.tools.execute(tc.name, tc.arguments, a.ctx, tc.id)
//         ↑ 传 tc.id，不是 tc.name
```

**④ `run()` 保证 history 以 system 消息开头**（商汤硬性要求
"System message must be at the beginning"；持久化 session 残留历史时首条可能不是
system）：
```v
if (history.len == 0 || history[0].role != .system) && a.client.config.system != '' {
    history.prepend(Message{ role: .system, content: a.client.config.system })
}
```

> 配套：mock 模式也要给 tool_calls 一个稳定的 `id`（如 `'call_1'`），否则回填的
> tool 消息 `tool_call_id` 对不上。

---

## 验证手法（不靠猜，靠 curl 二分）

当真实调用 400 时，别逐字段猜。用**最小复现 + 二分**定位：

1. **确认模型本身可用**：发一个**不带 `tools`** 的纯对话请求。
   `curl -s -X POST $BASE/chat/completions -H "Authorization: Bearer $KEY" \
     -H 'Content-Type: application/json' \
     -d '{"model":"...","messages":[{"role":"user","content":"hi"}]}'`
   返回 200 → 模型/鉴权 OK，问题在 tools 或 messages 格式。

2. **二分 tools**：把 N 个 tool 切成两半各发一次，定位是哪个 tool 的 schema 不接收。
   （vaiv 的 8 个工具全发也 200，说明 schema 本身商汤都接受——400 来自别处。）

3. **捕获真实请求体**：在 `llm.chat` 里 `os.write_file('./last_body.json', body)`
   或 `println(body)`，拿实际发出的 JSON 和成功的最小请求对比顶层字段
   （messages 结构、tools 的 parameters 是否为对象、tool 消息是否带 tool_call_id）。

4. **手工 curl 复现**：把捕获的 body 存文件，`curl -d @body.json ...` 反复删字段
   直到 400 变 200，被删掉的那块就是元凶。

⚠️ 调试代码（write_file/println）验证完**务必撤掉**，否则 `v vet` 可能因
`os` import 未使用或污染输出报错。

---

## 兜底：退回 OpenRouter

若某端点始终 400 且短期查不清，可先退回 OpenRouter（它最严格遵循 OpenAI 规范，
本 skill 修的三种格式它都接受）：
```bash
export VCA_PROVIDER=openrouter
export VCA_BASE_URL=https://openrouter.ai/api/v1
export VCA_API_KEY=sk-or-...
export VCA_MODEL=...
```
注意 `provider` 拼写：写 `openAI`（大写 I）会误走 openai 分支且语义不规范，
应写 `openai` 或 `openrouter`。

---

## 排错 checklist（400 时按序查）
- [ ] Authorization 头是 `Bearer $KEY`？→ 401 才是密钥问题
- [ ] tools 里每个 `type` 是 `"type"` 不是 `"ty"`？（坑 1）
- [ ] 每个 tool 的 `parameters` 是**对象**不是字符串？（坑 2，`grep '"parameters":"'` 应零匹配）
- [ ] `patch` 工具的 parameters 也改了吗？（坑 2 易漏点，在 patch.v）
- [ ] 带工具的回合：assistant 有 `tool_calls[].id`，tool 消息有对应 `tool_call_id`？（坑 3）
- [ ] history 首条是 system 消息？（坑 3-④）
- [ ] 上述都 OK 仍 400 → 用 curl 二分法抓真实 body 对比

---

## 流式输出（SSE 真·逐 token）⚠️ V 0.5.x 闭包坑是头号杀手

方向 3 实测：要在 V 里做 `stream:true` 的**真流式**（打字机效果），核心是
`http.Request.on_progress_body` 回调逐 chunk 解析 SSE。但 V 0.5.x 有一组专属坑，
与上面三个非流式坑完全独立。**完整可抄代码（最小探针 + chat_stream 正确骨架 +
StreamState 累积器 + 前端 delta 渲染 + run 接线）在
`references/streaming_sse_v051.md`**，下面只列要点速记：

1. **闭包捕获是复制语义**（最致命）：`fn [mut x] (...)` 闭包内对捕获变量的修改
   **不会**反映到外部（`buf`/`full`/`n` 实测都为空）。`*ptr +=` 改指针需 `unsafe`
   被禁。→ **不能在 `on_progress_body` 闭包里累积状态再给 `do()` 后使用**。正确
   做法：闭包内只做实时副作用（调 `on_token(kind, delta)` 推送），完整状态从
   `req.do()` 返回的 `resp.body`（完整响应体）重新解析组装。
2. **`[heap]` struct 也救不了**（`StreamSink @[heap]` 仍不传回）。用 `resp.body`
   重解析方案。
3. **商汤先发 `reasoning` 后发 `content`**：`delta.reasoning` 是思考链，
   `delta.content` 才是最终答案。两者都要捕获推送（前端 reasoning 灰色斜体），
   否则只看到空内容或只看到思考。
4. `buf.index('\n')` 返回 `?int` → `nl := buf.index('\n') or { -1 }; if nl < 0 { break }`
   （不要 `if nl := ...; nl >= 0` 这种短声明+条件组合，V 不支持）。
5. 数组元素字段不可原位改（`tcs[i].id = x` 报 immutable）→ 整体替换或取出改完放回。
6. `ChatRequest` 需 `stream bool @[json: 'stream']` 才是正确 wire 字段名。

探针验证：商汤 stream 在 https/h2 下每次约 270 字节一个 `data: {...}` 行、回调多次
触发，真流式可行（见 references 里的最小探针代码）。
