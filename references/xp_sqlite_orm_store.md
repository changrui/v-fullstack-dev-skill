# SQLite-backed session store (comptime ORM) — V 0.5.1 verified

Verified-compiling pattern for a persistent keyed store using V's comptime
`sql db { ... }` ORM (NOT the raw `exec_param` C-API). Extracted from the vaiv
project's `agent/webstore.v` (WebStore: list / get / put / del), which is
covered by `webapi_test.v` + `webapi_http_test.v` (11/11 tests green).

## Pitfalls baked into this recipe (see SKILL.md "comptime ORM" section)
- `string @[primary]` — NOT `string @[primary; sql: text]` (unquoted `text` breaks `create table`).
- `insert row into T` needs `or { 0 }` (returns int); `update`/`delete`/`select` may use empty `or {}`.
- `select` returns `[]T`; on error `or { return [] }`.
- Tests must use a unique temp DB per call (don't share a fixed path across runs).

## Recipe

```v
module agent

import db.sqlite
import os
import time
import x.json2

// On-disk row shapes. string @[primary] is enough — V infers TEXT.
struct WebSessionRow {
	id      string @[primary]
	title   string
	created string
	updated string
}

struct WebMessageRow {
	id           int    @[primary; sql: serial]
	session_id   string
	role         string
	content      string
	tool_calls   string
	tool_call_id string
}

pub struct WebStore {
	db sqlite.DB
}

// open_web_store connects to (and initializes) a SQLite store at `path`.
pub fn open_web_store(path string) !WebStore {
	dir := path.all_before_last('/')
	if dir != '' {
		os.mkdir_all(dir) or {}
	}
	db := sqlite.connect(path)!
	sql db { create table WebSessionRow } or {}   // void: empty or {} OK
	sql db { create table WebMessageRow } or {}
	return WebStore{ db: db }
}

// new_store points at the shared default file (the real server uses this).
pub fn new_store() WebStore {
	return open_web_store('data/vaiv-web.sqlite') or {
		eprintln('store: open failed: ${err}')
		exit(1)
	}
}

// new_test_store gives each test a fresh, isolated temp DB (no cross-run leak).
pub fn new_test_store() WebStore {
	mut p := os.temp_dir() + '/vaiv-web-test-' + time.utc().unix_nano().str() + '.sqlite'
	return open_web_store(p) or { panic('new_test_store: ${err}') }
}

fn (s WebStore) list() []WebSession {
	rows := sql s.db { select from WebSessionRow } or { return [] }
	mut out := []WebSession{}
	for r in rows {
		out << WebSession{ id: r.id, title: r.title, created: r.created, updated: r.updated, history: [] }
	}
	return out
}

fn (s WebStore) get(id string) ?WebSession {
	rows := sql s.db { select from WebSessionRow where id == id } or { return none }
	if rows.len == 0 { return none }
	r := rows[0]
	return WebSession{ id: r.id, title: r.title, created: r.created, updated: r.updated, history: [...] }
}

fn (mut s WebStore) put(mut sess WebSession) {
	sess.updated = time.utc().format_rfc3339()
	row := WebSessionRow{ id: sess.id, title: sess.title, created: sess.created, updated: sess.updated }
	existing := sql s.db { select from WebSessionRow where id == sess.id } or { [] }
	if existing.len > 0 {
		sql s.db {
			update WebSessionRow set title = sess.title, created = sess.created, updated = sess.updated
			where id == sess.id
		} or {}
	} else {
		sql s.db { insert row into WebSessionRow } or { 0 }   // <-- int default required
	}
	// rewrite transcript: delete old messages, insert current history
	sql s.db { delete from WebMessageRow where session_id == sess.id } or {}
	for m in sess.history {
		mrow := WebMessageRow{ session_id: sess.id, role: ..., content: m.content, tool_calls: ..., tool_call_id: ... }
		sql s.db { insert mrow into WebMessageRow } or { 0 }
	}
}

fn (mut s WebStore) del(id string) {
	sql s.db { delete from WebMessageRow where session_id == id } or {}
	sql s.db { delete from WebSessionRow where id == id } or {}
}
```

## Live-verify checklist (when testing a compiled binary)
1. Rebuild from CURRENT source: `v -o bin/vaiv-web cmd/web/main.v` — check the
   binary mtime; a stale binary makes real fixes look broken.
2. Run the server (mock, key unset): `env -u VCA_API_KEY -u VCA_PROVIDER VCA_PROVIDER=mock ./bin/vaiv-web`.
3. `curl -X POST -d '{"title":"t"}' http://localhost:PORT/api/sessions` -> expect a JSON session.
4. `ls -la data/vaiv-web.sqlite` -> file MUST exist (proves ORM `create table` + `insert` worked).
5. Kill + restart the server, then `GET /api/sessions` -> session + transcript survive = persistence OK.
