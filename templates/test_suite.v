// test_suite.v — 测试套件模板
//
// 包含: 表驱动测试、测试隔离、mock、benchmark
//
// 运行: ~/v/v -silent test .
// 单个: ~/v/v test test_suite_test.v
module main

import os
import time
import db.sqlite

// ============================================================
// 被测试函数 (示例)
// ============================================================
pub fn add(a int, b int) int {
	return a + b
}

pub fn parse_config(path string) !map[string]string {
	data := os.read_file(path) or { return error('read: ${err}') }
	mut cfg := map[string]string{}
	for line in data.split('\n') {
		line := line.trim_space()
		if line.len == 0 || line.starts_with('#') {
			continue
		}
		parts := line.split('=')
		if parts.len >= 2 {
			cfg[parts[0].trim_space()] = parts[1..].join('=').trim_space()
		}
	}
	return cfg
}

// ============================================================
// 测试 #1: 简单断言
// ============================================================
fn test_add() {
	assert add(1, 2) == 3
	assert add(-1, 1) == 0
	assert add(0, 0) == 0
	assert add(-5, -3) == -8
}

// ============================================================
// 测试 #2: 表驱动测试
// ============================================================
struct AddTestCase {
	a        int
	b        int
	expected int
	name     string
}

fn test_add_table() {
	cases := [
		AddTestCase{1, 2, 3, 'positive'},
		AddTestCase{-1, 1, 0, 'neg_pos'},
		AddTestCase{0, 0, 0, 'zeros'},
		AddTestCase{-5, -3, -8, 'both_neg'},
		AddTestCase{100, 200, 300, 'large'},
	]
	for tc in cases {
		result := add(tc.a, tc.b)
		assert result == tc.expected, '${tc.name}: add(${tc.a}, ${tc.b}) = ${result}, want ${tc.expected}'
	}
}

// ============================================================
// 测试 #3: 使用临时文件
// ============================================================
fn test_parse_config() {
	// 创建临时目录
	tmp_dir := os.join_path(os.temp_dir(), 'v_test_config_${time.now().unix_milli()}')
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer { os.rmdir_all(tmp_dir) or {} }

	// 写测试配置文件
	cfg_path := os.join_path(tmp_dir, 'test.conf')
	cfg_content := '# database config\ndb_host=localhost\ndb_port=5432\n  key  =  value  \n'
	os.write_file(cfg_path, cfg_content) or { panic(err) }

	// 执行测试
	cfg := parse_config(cfg_path) or { panic(err) }

	// 断言
	assert cfg['db_host'] == 'localhost', 'db_host mismatch'
	assert cfg['db_port'] == '5432', 'db_port mismatch'
	assert cfg['key'] == 'value', 'key value with whitespace mismatch'
}

// ============================================================
// 测试 #4: SQLite 测试隔离
// ============================================================
fn test_sqlite_temp() {
	db_path := os.join_path(os.temp_dir(), 'v_test_${time.now().unix_nano()}.db')
	mut db := sqlite.connect(db_path) or { panic(err) }
	defer {
		db.close()
		os.rm(db_path) or {}
	}

	// 建表
	db.exec('CREATE TABLE items (id TEXT PRIMARY KEY, name TEXT)') or { panic(err) }

	// 插入
	db.exec("INSERT INTO items (id, name) VALUES ('1', 'hello')") or { panic(err) }
	db.exec("INSERT INTO items (id, name) VALUES ('2', 'world')") or { panic(err) }

	// 查询
	rows := db.exec('SELECT * FROM items ORDER BY id') or { panic(err) }
	assert rows.len == 2, 'expected 2 rows, got ${rows.len}'

	first := rows[0]
	assert first.get_string('id') == '1', 'first id'
	assert first.get_string('name') == 'hello', 'first name'
}

// ============================================================
// 测试 #5: Option / Result 断言模式
// ============================================================
fn test_option_assert_patterns() {
	// Option: 用 if x :=
	mut m := map[string]int{}
	m['a'] = 1
	if val := m['a'] {
		assert val == 1
	} else {
		assert false, 'key should exist'
	}

	// Result: 用 or { ... }
	fn_that_fails := fn () !int {
		return error('generic fail')
	}
	result := fn_that_fails() or { 0 }
	assert result == 0, 'result should be 0 on failure'
}

// ============================================================
// 测试 #6: 使用 testing.T
// ============================================================
fn test_with_t(t &testing.T) {
	t.assert(add(2, 2) == 4)
	t.eq(add(2, 2), 4)
	t.ne(add(2, 2), 5)

	mut vals := [1, 2, 3]
	t.assert(vals.len == 3)
}

// ============================================================
// Benchmark
// ============================================================
fn bench_add(b &testing.B) {
	b.reset_timer()
	for _ in 0 .. b.iterations() {
		add(100, 200)
	}
}

fn bench_add_many(b &testing.B) {
	b.set_iterations(50000)
	b.reset_timer()
	for _ in 0 .. b.iterations() {
		add(-999999, 999999)
	}
}

// ============================================================
// 测试辅助函数 (不以前缀 test_ 开始)
// ============================================================
fn create_temp_dir() string {
	dir := os.join_path(os.temp_dir(), 'v_test_${time.now().unix_nano()}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn write_tmp_file(dir string, name string, content string) string {
	p := os.join_path(dir, name)
	os.write_file(p, content) or { panic(err) }
	return p
}
