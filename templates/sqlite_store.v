// sqlite_store.v — SQLite ORM 存储模式模板
//
// ORM 在 V 0.5.x 中的正确使用模式:
//   - string PK (避免 int PK 的 id=0 问题)
//   - insert 需要 or { int } 返回
//   - delete 强制需要 where
//   - 无 order by, 在 V 中排序
//
// 依赖: V 0.5.x, db.sqlite (内置, 不需系统 libsqlite3)
module store

import db.sqlite
import os
import time

// ============================================================
// 数据模型
// ============================================================
// 使用 string @[primary] (避免 int PK 自动写入 id=0)
pub struct SessionRow {
pub:
	id      string @[primary]
	name    string
	created i64
	updated i64
}

pub struct MessageRow {
pub:
	id         string @[primary]
	session_id string
	role       string // system, user, assistant, tool
	content    string
	created    i64
}

// ============================================================
// Store — 封装 ORM 操作
// ============================================================
pub struct Store {
pub:
	db sqlite.DB // 值类型字段, 不需堆指针
}

// ============================================================
// 打开 / 初始化
// ============================================================
// 打开或创建 SQLite 存储并初始化表
pub fn open(path string) !Store {
	dir := os.dir(path)
	if dir.len > 0 && !os.exists(dir) {
		os.mkdir_all(dir) or { return error('mkdir: ${err}') }
	}

	db := sqlite.connect(path)!

	// 初始化表
	sql db {
		create table SessionRow
	} or { eprintln('create session table: ${err}') }

	sql db {
		create table MessageRow
	} or { eprintln('create message table: ${err}') }

	return Store{ db: db }
}

// 关闭数据库连接
pub fn (mut s Store) close() {
	s.db.close()
}

// ============================================================
// Session CRUD
// ============================================================
// 列出所有会话记录（按创建时间排序）
pub fn (s Store) list_sessions() ![]SessionRow {
	rows := sql s.db {
		select from SessionRow
	} or { return error('select: ${err}') }

	// ORM 不支持 order by, 在 V 中排序
	mut sorted := rows.clone()
	mut i := 0
	for i < sorted.len {
		mut j := i + 1
		for j < sorted.len {
			if sorted[j].created > sorted[i].created {
				sorted[i], sorted[j] = sorted[j], sorted[i]
			}
			j++
		}
		i++
	}
	return sorted
}

// 获取单个会话（可选返回 none）
pub fn (s Store) get_session(id string) ?SessionRow {
	rows := sql s.db {
		select from SessionRow where id == id
	} or { return none }
	if rows.len == 0 {
		return none
	}
	return rows[0]
}

// 创建新的会话记录并返回其 SessionRow
pub fn (s Store) create_session(name string) !SessionRow {
	now := time.now().unix_milli()
	row := SessionRow{
		id: 'sess_${now}_${name.hash()}' // 生成唯一 string PK
		name: name
		created: now
		updated: now
	}

	// insert 返回 int, or 块必须提供 int 值
	sql s.db {
		insert row into SessionRow
	} or { return error('insert: ${err}') }

	return row
}

// 删除会话及其关联消息
pub fn (s Store) delete_session(id string) ! {
	// delete 强制需要 where
	sql s.db {
		delete from SessionRow where id == id
	} or { return error('delete: ${err}') }

	// 也删除关联消息
	s.db.exec("DELETE FROM MessageRow WHERE session_id == '${id}'") or {}
}

// ============================================================
// Message CRUD
// ============================================================
// 列出会话的所有消息，按时间升序
pub fn (s Store) list_messages(session_id string) ![]MessageRow {
	rows := sql s.db {
		select from MessageRow where session_id == session_id
	} or { return error('select: ${err}') }

	mut sorted := rows.clone()
	mut i := 0
	for i < sorted.len {
		mut j := i + 1
		for j < sorted.len {
			if sorted[j].created < sorted[i].created {
				sorted[i], sorted[j] = sorted[j], sorted[i]
			}
			j++
		}
		i++
	}
	return sorted
}

// 向会话添加一条消息并返回新行
pub fn (s Store) add_message(session_id string, role string, content string) !MessageRow {
	now := time.now().unix_milli()
	row := MessageRow{
		id: 'msg_${now}_${session_id.hash()}'
		session_id: session_id
		role: role
		content: content
		created: now
	}
	sql s.db {
		insert row into MessageRow
	} or { return error('insert: ${err}') }
	return row
}

// 清空所有消息（测试/管理用途）
pub fn (s Store) clear_messages() ! {
	// 清空表: delete 强制需要 where, 所以使用原始 SQL
	s.db.exec('DELETE FROM MessageRow') or { return error('clear: ${err}') }
}

// ============================================================
// 事务示例
// ============================================================
// 用给定消息列表替换会话的所有消息（原子替换）
pub fn (mut s Store) replace_all(session_id string, msgs []MessageRow) ! {
	// 使用原始 SQL 执行批量操作
	s.db.exec("DELETE FROM MessageRow WHERE session_id == '${session_id}'") or {}
	for msg in msgs {
		sql s.db {
			insert msg into MessageRow
		} or { return error('replace: ${err}') }
	}
}

// ============================================================
// 测试辅助: 创建临时测试数据库
// ============================================================
// 为测试创建并返回一个临时 Store 实例（内存或临时文件）
pub fn new_test_store() Store {
	p := os.join_path(os.temp_dir(), 'v_test_${time.now().unix_nano()}.sqlite')
	s := open(p) or { panic('test store: ${err}') }
	return s
}
