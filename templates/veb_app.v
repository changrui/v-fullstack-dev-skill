// veb_app.v — Veb web 应用脚手架
// 使用方式: 复制到项目目录, 按需修改 App struct 和路由
//
// Build:
//   ~/v/v -o bin/app cmd/server/main.v
// Run:
//   ./bin/app
//
// 依赖: V 0.5.x, veb (内置)
module main

import veb
import veb.sse
import os
import time

// ============================================================
// 应用状态
// ============================================================
pub struct App {
	veb.StaticHandler

	// 应用级状态: 数据库连接、配置、缓存等
pub mut:
	started_at i64
}

// ============================================================
// 自定义 Context (嵌入 veb.Context)
// ============================================================
pub struct WebCtx {
	veb.Context
pub mut:
	lang string // 通过 before_request 设置
}

// before_request — 每个请求前执行
pub fn (mut app App) before_request(mut ctx WebCtx) ! {
	// 从 cookie 或 query 获取语言偏好
	ctx.lang = ctx.get_cookie('lang') or { 'en' }
}

// after_request — 每个请求后执行
pub fn (mut app App) after_request(mut ctx WebCtx) {
	// 日志、指标等
}

// ============================================================
// 路由: GET /
// ============================================================
@['/']
pub fn (mut app App) index(mut ctx WebCtx) veb.Result {
	// 模板变量来自 handler 局部作用域
	title := 'Welcome'
	message := 'Veb is running'
	return ctx.html('\$veb.html(', templates / index.html, ')')
}

// ============================================================
// 路由: GET /health
// ============================================================
@['/health']
pub fn (mut app App) health(mut ctx WebCtx) veb.Result {
	uptime := (time.now().unix_milli() - app.started_at) / 1000
	return ctx.json({
		'status': 'ok'
		'uptime': '${uptime}s'
	})
}

// ============================================================
// 路由: POST /api/data
// ============================================================
@['/api/data'; post]
pub fn (mut app App) post_data(mut ctx WebCtx) veb.Result {
	body := ctx.req.data
	if body.len == 0 {
		return ctx.text('empty body', status: 400)
	}

	// 处理请求体...
	return ctx.json({
		'received': body.len
	})
}

// ============================================================
// 路由: GET /api/items — 带查询参数
// ============================================================
@['/api/items']
pub fn (mut app App) list_items(mut ctx WebCtx) veb.Result {
	// 使用查询参数而非路径参数 (路径参数在 V 0.5.x 有代码生成问题)
	limit := ctx.query['limit'] or { '10' }
	offset := ctx.query['offset'] or { '0' }
	_ = limit
	_ = offset

	// 查询数据库...
	return ctx.json({
		'items':  '[]'
		'limit':  limit
		'offset': offset
	})
}

// ============================================================
// 路由: GET /api/stream — SSE 流式响应
// ============================================================
@['/api/stream'; post]
pub fn (mut app App) stream(mut ctx WebCtx) veb.Result {
	ctx.takeover_conn()
	mut sse_conn := sse.start_connection(mut ctx)
	defer { sse_conn.close() }

	// 发送事件
	sse_conn.send_message(data: 'chunk 1') or { return veb.no_result() }
	sse_conn.send_message(data: 'chunk 2') or { return veb.no_result() }
	sse_conn.send_message(event: 'done', data: 'END') or { return veb.no_result() }

	return veb.no_result()
}

// ============================================================
// 静态文件处理
// ============================================================
fn handle_static(mut app App) {
	app.handle_static('./static', true) or {
		eprintln('static dir not found, creating...')
		os.mkdir_all('./static') or {}
	}
}

// ============================================================
// 入口
// ============================================================
fn main() {
	mut app := &App{
		started_at: time.now().unix_milli()
	}
	handle_static(mut app)

	veb.run_at[App, WebCtx](mut app, port: 8080, family: .ip) or {
		panic('veb server failed: ${err}')
	}
}
