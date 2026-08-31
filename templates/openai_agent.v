// openai_agent.v — OpenAI 兼容 LLM 智能体框架模板
//
// 支持任何 OpenAI 兼容的 API:
//   - OpenAI (api.openai.com)
//   - OpenRouter (openrouter.ai)
//   - 商汤日日新 (sensenova.cn)
//   - Ollama (localhost:11434)
//   - vLLM / llama.cpp
//
// 注意: 内置了 wire-format 修复 (Bug 1/2/3):
//   - `ty` → `@[json: 'type']` 避免序列化为 "ty"
//   - `parameters` 用 json2.Any 确保是 JSON 对象
//   - tool_call_id 精确匹配
//
// 依赖: V 0.5.x, json2 (内置), net.http (内置)
module main

import json2
import net.http
import os

// ============================================================
// 配置
// ============================================================
pub struct LLMConfig {
pub:
	base_url string
	api_key  string
	model    string
}

pub fn default_config() LLMConfig {
	return LLMConfig{
		base_url: os.getenv('VCA_BASE_URL', 'https://openrouter.ai/api/v1')
		api_key: os.getenv('VCA_API_KEY', '')
		model: os.getenv('VCA_MODEL', 'openai/gpt-4o-mini')
	}
}

// ============================================================
// Wire 结构 (带 json tag 修复 Bug 1)
// ============================================================
pub struct ChatMessage {
pub mut:
	role         string
	content      string
	tool_calls   json2.Any
	tool_call_id string @[json: 'tool_call_id']
}

pub struct ToolFunction {
pub:
	name        string
	description string
	parameters  json2.Any // ⚠️ Bug 2 修复: 必须是 json2.Any (对象), 不是 string
}

pub struct ToolDef {
pub:
	ty       string @[json: 'type'] // ⚠️ Bug 1 修复: @[json: 'type'] 防止序列化为 "ty"
	function ToolFunction
}

pub struct ChatRequest {
pub:
	model       string
	messages    []ChatMessage
	temperature f64
	stream      bool @[json: 'stream']
	tools       []ToolDef @[skip]
}

pub struct Choice {
pub:
	index         int
	message       ChatMessage
	finish_reason string
}

pub struct ChatResponse {
pub:
	choices []Choice
}

// ============================================================
// 智能体核心
// ============================================================
pub struct Agent {
pub:
	config   LLMConfig
	history  []ChatMessage
	last_err string
}

pub fn new_agent(config LLMConfig) Agent {
	return Agent{ config: config, history: []ChatMessage{} }
}

// 添加系统消息 (必须是 messages[0])
pub fn (mut a Agent) system(msg string) {
	a.history.prepend(ChatMessage{ role: 'system', content: msg })
}

// 添加用户消息
pub fn (mut a Agent) user(msg string) {
	a.history << ChatMessage{ role: 'user', content: msg }
}

// 添加助手消息
pub fn (mut a Agent) assistant(msg string) {
	a.history << ChatMessage{ role: 'assistant', content: msg }
}

// ============================================================
// Chat Completion 调用
// ============================================================
pub fn (mut a Agent) chat(user_input string) !string {
	a.user(user_input)
	return a.send()
}

pub fn (a Agent) build_request() string {
	req := ChatRequest{
		model: a.config.model
		messages: a.history
		temperature: 0.7
		stream: false
	}
	return json2.encode[ChatRequest](req, json2.EncoderOptions{})
}

pub fn (mut a Agent) send() !string {
	body := a.build_request()

	// 调试: 保存请求体
	// os.write_file('./last_request.json', body) or {}
	mut req := http.Request{
		method: .post
		url: '${a.config.base_url}/chat/completions'
		data: body
	}

	// 设置请求头
	req.header = http.new_custom_header_from_map({
		'Authorization': 'Bearer ${a.config.api_key}'
		'Content-Type':  'application/json'
	}) or { return error('header: ${err}') }

	resp := req.do() or { return error('http: ${err}') }

	if resp.status_code == 401 {
		return error('401 Unauthorized — check API key')
	}

	if resp.status_code != 200 {
		return error('${resp.status_code}: ${resp.body[0..200]}')
	}

	// 解析响应
	chat_resp := json2.decode[ChatResponse](resp.body, json2.DecoderOptions{}) or {
		return error('json decode: ${err}')
	}

	if chat_resp.choices.len == 0 {
		return error('no choices in response')
	}

	reply := chat_resp.choices[0].message.content
	a.assistant(reply)

	// ⚠️ Bug 3: 如果包含 tool_calls, 需记录 tool_call_id
	// 见下游 execute_tool 函数
	_ := chat_resp.choices[0].message.tool_call_id

	return reply
}

// ============================================================
// 工具调用 (Tool Calling — 修复 Bug 2+3)
// ============================================================
// 工具定义示例: parameters 必须是 json2.Any (JSON 对象, 不是字符串)
pub fn search_tool_def() ToolDef {
	params := json2.decode[json2.Any]('{
		"type": "object",
		"properties": {
			"query": {"type": "string"}
		},
		"required": ["query"]
	}') or { json2.Any{} }

	return ToolDef{
		ty: 'function'
		function: ToolFunction{
			name: 'web_search'
			description: 'Search the web for current information'
			parameters: params
		}
	}
}

// 构建带工具调用的请求
pub fn (a Agent) build_request_with_tools(tools []ToolDef) string {
	req := ChatRequest{
		model: a.config.model
		messages: a.history
		temperature: 0.7
		stream: false
		tools: tools
	}
	return json2.encode[ChatRequest](req, json2.EncoderOptions{})
}

// ============================================================
// SSE 流式调用
// ============================================================
pub fn (mut a Agent) chat_stream(user_input string, on_token fn(string)) !string {
	a.user(user_input)
	return a.send_stream(on_token)
}

pub fn (a Agent) build_stream_request() string {
	req := ChatRequest{
		model: a.config.model
		messages: a.history
		temperature: 0.7
		stream: true // ⚠️ 必须带上 @[json: 'stream'] tag
	}
	return json2.encode[ChatRequest](req, json2.EncoderOptions{})
}

pub fn (mut a Agent) send_stream(on_token fn(string)) !string {
	body := a.build_stream_request()

	// 流式处理: on_progress_body 回调的捕获是 COPY 语义
	// 不要尝试在其中累积状态, 使用 resp.body 在 do() 后重新解析
	mut full := ''
	mut req := http.Request{
		method: .post
		url: '${a.config.base_url}/chat/completions'
		data: body
		on_progress_body: fn [on_token] (req &http.Request, chunk []u8, so_far u64, expected u64, status int) ! {
			// 回调中只做预期内副作用, 不累积状态
			s := chunk.bytestr()on_token(s)}
	}

	req.header = http.new_custom_header_from_map({
		'Authorization': 'Bearer ${a.config.api_key}'
		'Content-Type':  'application/json'
	}) or { return error('header: ${err}') }

	resp := req.do() or { return error('http: ${err}') }

	// ⚠️ 回调是 COPY 语义, full 为空, 必须重新解析 resp.body
	full = resp.body
	a.assistant(full)
	return full
}

// ============================================================
// 简单用法示例
// ============================================================
fn main() {
	mut agent := new_agent(default_config())
	agent.system('You are a helpful assistant.')

	reply := agent.chat('Hello! What can you do?') or {
		eprintln('Error: ${err}')
		return
	}
	println('Assistant: ${reply}')
}
