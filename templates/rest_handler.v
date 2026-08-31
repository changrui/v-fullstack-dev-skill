// rest_handler.v — Enhanced REST API CRUD 处理器模板
// 适用于 veb 项目的 REST 资源处理器，包含分页、验证、错误标准化、CORS 和认证功能
//
// 集成方式: 复制到项目, 将资源名替换为实际名称,
//          在 app 中挂载对应的 ORM store, 配置中间件
//
// 依赖: V 0.5.x, veb (内置), time (生成 ID/时间戳)
module main

import veb
import net.http
import json2
import time

// ============================================================
// 配置结构
// ============================================================

// RestConfig 配置 REST 处理器的行为
pub struct RestConfig {
	default_limit  int = 20 // 默认每页数量
	max_limit      int = 100 // 最大每页数量（防止过度分页）
	allow_cors     bool = true // 是否启用 CORS
	allowed_origin string = '*' // CORS 允许来源
	require_auth   bool = false // 是否需要认证
	auth_header    string = 'Authorization' // 认证头名称
	auth_prefix    string = 'Bearer ' // 认证前缀
}

// ============================================================
// 数据模型
// ============================================================
pub struct Item {
pub:
	id      string @[primary] // 使用 string PK (避免 int PK 的 id=0 问题)
	name    string
	value   string
	created i64
	updated i64
}

// ============================================================
// 请求/响应结构
// ============================================================

// CreateItemRequest 创建请求体
pub struct CreateItemRequest {
	name  string
	value string
}

// UpdateItemRequest 更新请求体
pub struct UpdateItemRequest {
	name  ?string
	value ?string
}

// ItemResponse 列表响应体
pub struct ItemResponse {
	items    []Item
	total    int // 总记录数
	page     int // 当前页码
	limit    int // 每页数量
	has_prev bool // 是否有上一页
	has_next bool // 是否有下一页
}

// ErrorResponse 统一错误响应体
pub struct ErrorResponse {
	error   string // 错误消息
	code    int // HTTP 状态码
	details ?string // 详细信息（可选）
}

// ============================================================
// 辅助函数：分页参数解析
// ============================================================

// parse_query_int 从 query 字符串解析为 int，带默认值和范围检查
fn parse_query(mut ctx veb.Context, key string, default int, min int, max int) int {
	val := ctx.query[key] or { return default }
	parsed := val.int() or { return default }
	// 确保在有效范围内
	if parsed < min {
		parsed = min
	}
	if parsed > max {
		parsed = max
	}
	return parsed
}

// paginate_items 对结果列表应用分页切片
fn paginate_items(items []Item, page int, limit int) []Item {
	start := (page - 1) * limit
	if start >= items.len {
		return []Item{}
	}
	end := start + limit
	if end > items.len {
		end = items.len
	}
	return items[start..end].clone()
}

// ============================================================
// 辅助函数：请求验证
// ============================================================

// validate_create_item 验证创建请求
fn validate_create_item(req CreateItemRequest) ?string {
	if req.name.len == 0 {
		return some('name is required and must be non-empty')
	}
	if req.name.len > 255 {
		return some('name must be less than 255 characters')
	}
	if req.value.len > 1000 {
		return some('value must be less than 1000 characters')
	}
	return none
}

// validate_update_item 验证更新请求
fn validate_update_item(id string, req UpdateItemRequest) ?string {
	if id.len == 0 {
		return some('id is required')
	}
	// 至少有一个字段提供
	if req.name == '' && req.value == '' {
		return some('at least one field (name or value) must be provided')
	}
	if req.name.len > 255 {
		return some('name must be less than 255 characters')
	}
	if req.value.len > 1000 {
		return some('value must be less than 1000 characters')
	}
	return none
}

// ============================================================
// 辅助函数：认证
// ============================================================

// extract_token 从 Authorization 头提取 token
fn extract_token(mut ctx veb.Context, config RestConfig) ?string {
	auth_header := ctx.req.headers.get(config.auth_header) or { return none }
	if auth_header.startsWith(config.auth_prefix) {
		return some(auth_header[len(config.auth_prefix)..])
	}
	return none
}

// verify_auth 验证认证（示例：实际项目中应连接数据库或外部服务）
fn verify_auth(token string, config RestConfig) bool {
	// TODO: 实现真正的令牌验证逻辑
	// 这里只是一个示例占位符
	return token.len > 0 // 简化验证
}

// require_auth_middleware 认证中间件
fn require_auth_middleware(mut ctx veb.Context, config RestConfig) ?string {
	if !config.require_auth {
		return none // 不需要认证，通过
	}
	token := extract_token(ctx, config) or { return some('missing authorization header') }
	if !verify_auth(token, config) {
		return some('invalid or expired token')
	}
	return none // 认证成功
}

// ============================================================
// 辅助函数：标准化错误响应
// ============================================================

// respond_error 返回标准化的错误 JSON 响应
fn respond_error(mut ctx veb.Context, code int, message string, details ?string) veb.Result {
	err_resp := ErrorResponse{
		error: message
		code: code
		details: details
	}
	// 设置适当的 CORS 头（如果需要）
	if ctx.config.allow_cors {
		ctx.res.header.add('Access-Control-Allow-Origin', ctx.config.allowed_origin)
		ctx.res.header.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
		ctx.res.header.add('Access-Control-Allow-Headers', 'Content-Type, Authorization')
	}
	// 对于 OPTIONS 预检请求直接响应
	if ctx.req.method == .options {
		return ctx.text('', status: 204)
	}
	return ctx.json(json2.encode[ErrorResponse](err_resp, json2.EncoderOptions{}), status: code)
}

// ============================================================
// 主 App 结构（需嵌入 ItemStore 等）
// ============================================================
pub struct App {
	veb.StaticHandler
pub:
	db     ?ItemStore // 可选的 ORM store
	config RestConfig // REST 配置
}

// ItemStore 是与数据库交互的抽象接口
pub interface ItemStore {
	list(limit int, offset int) ([]Item, int)
	get(id string) ?Item
	create(item Item) ?Item
	delete(id string) ?bool
}

// ============================================================
// 列表: GET /api/items?limit=20&page=1
// ============================================================
// route: /api/items
pub fn (mut app App) list_items(mut ctx veb.Context) veb.Result {
	// 先运行认证中间件（如果启用了）
	auth_err := require_auth_middleware(ctx, app.config)
	if auth_err != none {
		return respond_error(ctx, 401, auth_err.extract(), none)
	}

	// 解析分页参数
	limit := parse_query(ctx, 'limit', app.config.default_limit, 1, app.config.max_limit)
	page := parse_query(ctx, 'page', 1, 1, 100) // 页码从 1 开始

	// 从 ORM 查询（需在 App 中嵌入实际的 ItemStore 实现）
	// mut items := app.db.list(limit, page - 1) or { return respond_error(ctx, 500, 'db query failed', none) }
	// 演示：返回空列表
	mut items := []Item{}
	mut total := 0

	if items.len == 0 {
		return ctx.json(json2.encode[ItemResponse](ItemResponse{
			items: items
			total: total
			page: page
			limit: limit
			has_prev: false
			has_next: false
		}, json2.EncoderOptions{}))
	}

	// 计算分页信息
	has_prev := page > 1
	has_next := (page * limit) < total

	// 应用分页切片
	paginated := paginate_items(items, page, limit)

	return ctx.json(json2.encode[ItemResponse](ItemResponse{
		items: paginated
		total: total
		page: page
		limit: limit
		has_prev: has_prev
		has_next: has_next
	}, json2.EncoderOptions{}))
}

// ============================================================
// 详情: GET /api/items?id=xxx (使用查询参数而非路径参数)
// **注意**: V 0.5.x 路径参数有代码生成问题，改用查询参数
// ============================================================
// route: /api/items/detail
pub fn (mut app App) get_item(mut ctx veb.Context) veb.Result {
	id := ctx.query['id'] or { return respond_error(ctx, 400, 'missing id parameter', none) }

	// 从 ORM 查询
	// row := app.db.get(id) or { return respond_error(ctx, 404, 'item not found', none) }
	// 演示
	_ = id
	return ctx.json('{"id": "", "name": "", "value": "", "created": 0, "updated": 0}')
}

// ============================================================
// 创建: POST /api/items
// ============================================================
// route: POST /api/items
pub fn (mut app App) create_item(mut ctx veb.Context) veb.Result {
	// 先运行认证中间件（如果启用了）
	auth_err := require_auth_middleware(ctx, app.config)
	if auth_err != none {
		return respond_error(ctx, 401, auth_err.extract(), none)
	}

	body := ctx.req.data
	if body.len == 0 {
		return respond_error(ctx, 400, 'empty request body', none)
	}

	req := json2.decode[CreateItemRequest](body, json2.DecoderOptions{}) or {
		return respond_error(ctx, 400, 'invalid json format', none)
	}

	// 验证请求
	validation_err := validate_create_item(req)
	if validation_err != none {
		return respond_error(ctx, 422, 'validation failed', validation_err.extract())
	}

	new_item := Item{
		id: time.now().unix_nano().str() // 用时间戳生成唯一 string PK
		name: req.name
		value: req.value
		created: time.now().unix_milli()
		updated: time.now().unix_milli()
	}

	// sql result := app.db.create(new_item) or { return respond_error(ctx, 500, 'db insert failed', none) }
	// 演示
	_ = new_item

	// 设置 CORS 头
	if app.config.allow_cors {
		ctx.res.header.add('Access-Control-Allow-Origin', app.config.allowed_origin)
	}

	return ctx.json(json2.encode[Item](new_item, json2.EncoderOptions{}), status: 201)
}

// ============================================================
// 更新: PUT /api/items
// ============================================================
// route: PUT /api/items
pub fn (mut app App) update_item(mut ctx veb.Context) veb.Result {
	// 先运行认证中间件（如果启用了）
	auth_err := require_auth_middleware(ctx, app.config)
	if auth_err != none {
		return respond_error(ctx, 401, auth_err.extract(), none)
	}

	body := ctx.req.data
	if body.len == 0 {
		return respond_error(ctx, 400, 'empty request body', none)
	}

	id := ctx.query['id'] or { return respond_error(ctx, 400, 'missing id parameter', none) }

	req := json2.decode[UpdateItemRequest](body, json2.DecoderOptions{}) or {
		return respond_error(ctx, 400, 'invalid json format', none)
	}

	// 验证请求
	validation_err := validate_update_item(id, req)
	if validation_err != none {
		return respond_error(ctx, 422, 'validation failed', validation_err.extract())
	}

	// 更新操作
	// updated := app.db.update(id, Item{id: id, name: req.name, value: req.value, updated: time.now().unix_milli()}) or {
	//     return respond_error(ctx, 500, 'db update failed', none)
	// }
	// if updated == 0 { return respond_error(ctx, 404, 'item not found', none) }
	// 演示
	_ = id
	_ = req

	if app.config.allow_cors {
		ctx.res.header.add('Access-Control-Allow-Origin', app.config.allowed_origin)
	}

	return ctx.json(json2.encode[ItemResponse](ItemResponse{
		items: [
			Item{ id: id, name: req.name, value: req.value, updated: time.now().unix_milli() },
		]
		total: 1
		page: 1
		limit: 1
		has_prev: false
		has_next: false
	}, json2.EncoderOptions{})), status
	200
}

// ============================================================
// 删除: DELETE /api/items
// ============================================================
// route: DELETE /api/items
pub fn (mut app App) delete_item(mut ctx veb.Context) veb.Result {
	// 先运行认证中间件（如果启用了）
	auth_err := require_auth_middleware(ctx, app.config)
	if auth_err != none {
		return respond_error(ctx, 401, auth_err.extract(), none)
	}

	id := ctx.query['id'] or { return respond_error(ctx, 400, 'missing id parameter', none) }

	// deleted := app.db.delete(id) or { return respond_error(ctx, 500, 'db delete failed', none) }
	// if deleted == 0 { return respond_error(ctx, 404, 'item not found', none) }
	// 演示
	_ = id

	if app.config.allow_cors {
		ctx.res.header.add('Access-Control-Allow-Origin', app.config.allowed_origin)
	}

	return ctx.json(json2.encode[ItemResponse](ItemResponse{
		items: []
		total: 0
		page: 1
		limit: 1
		has_prev: false
		has_next: false
	}, json2.EncoderOptions{})), status
	200
}

// ============================================================
// 批量创建: POST /api/items/batch
// ============================================================
// route: POST /api/items/batch
pub fn (mut app App) batch_create(mut ctx veb.Context) veb.Result {
	// 先运行认证中间件（如果启用了）
	auth_err := require_auth_middleware(ctx, app.config)
	if auth_err != none {
		return respond_error(ctx, 401, auth_err.extract(), none)
	}

	body := ctx.req.data
	if body.len == 0 {
		return respond_error(ctx, 400, 'empty request body', none)
	}

	items := json2.decode[[]CreateItemRequest](body, json2.DecoderOptions{}) or {
		return respond_error(ctx, 400, 'invalid json format', none)
	}

	if items.len == 0 {
		return respond_error(ctx, 422, 'empty batch list', none)
	}

	// 批量验证
	for item in items {
		if err := validate_create_item(item) {
			return respond_error(ctx, 422, 'batch validation failed: ${err.extract()}', none)
		}
	}

	// 批量创建（在事务中执行更可靠）
	// mut created_count := 0
	// for item in items {
	//     new_item := Item{
	//         id:      time.now().unix_nano().str(),
	//         name:    item.name,
	//         value:   item.value,
	//         created: time.now().unix_milli(),
	//         updated: time.now().unix_milli(),
	//     }
	//     if res := app.db.create(new_item); res != none {
	//         created_count++
	//     } else {
	//         // 回滚或继续...
	//     }
	// }
	// 演示
	_ = items

	return ctx.text('created ${items.len} items', status: 201)
}

// ============================================================
// OPTIONS 端点：支持 CORS 预检请求
// ============================================================
pub fn (mut app App) options_handler(mut ctx veb.Context) veb.Result {
		if ctx.req.method == .options {
			if app.config.allow_cors {
				ctx.res.header.add('Access-Control-Allow-Origin', app.config.allowed_origin)
				ctx.res.header.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
				ctx.res.header.add('Access-Control-Allow-Headers', 'Content-Type, Authorization')
				ctx.res.header.add('Access-Control-Max-Age', '86400') // 24小时缓存
			}
			return ctx.text('', status: 204)
		}
		return respond_error(ctx, 405, 'method not allowed', none)
	}
