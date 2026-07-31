# V 0.5.x db.sqlite ORM — deep detail

Companion to `v-fullstack-dev` SKILL.md. Applies to `sql db { ... }` comptime ORM.
All conclusions verified by real compile/run on 0.5.1.

## 1. Primary-key attribute differs by type (the #1 silent failure)
- `int @[primary; sql: serial]` → OK (V maps `serial` to autoincrement int).
- `string @[primary]` → OK; V infers `TEXT` automatically. **Do NOT write
  `string @[primary; sql: text]`** — the unquoted `sql: text` makes `create table`
  FAIL (`struct field 'id' requires a primary key field for foreign key reference`),
  and since the failure is swallowed by `or {}` the table silently never exists
  (later `select` errors `no such table`). Use a quoted literal `sql: 'text'` if you
  must override, but `string @[primary]` is enough.
- Verified working shape:
```v
struct WebSessionRow { id string @[primary]; title string; created string; updated string }
struct WebMessageRow { id int @[primary; sql: serial]; session_id string; role string; content string }
```

## 1b. `int` primary key → ORM writes `id=0` every insert → 2nd row UNIQUE conflict
- `id int @[primary]` → insert writes `id=0` → 2nd row UNIQUE conflict
  (`UNIQUE constraint failed: runrow.id (19)`).
- `id int @[primary; sql: 'auto_increment'` → worse: `sql:` value treated as a COLUMN
  NAME (`CREATE TABLE ... \`auto_increment\` INTEGER ... PRIMARY KEY(\`auto_increment\`)`),
  insert still writes `0`.
- Dropping `id` entirely → ORM adds an implicit `id` column and writes `0` → same.
- `int @[primary; sql: serial]` was earlier noted "available" but treat int PK as
  suspect. **Robust + verified fix: use `string` PK, generate a unique id yourself:**
```v
pub struct RunRow { pub: id string @[primary]; ts i64 }
// in save():
row := RunRow{ id: time.now().unix_nano().str(), ts: time.now().unix_milli(), ... }
sql ts.db { insert row into RunRow } or { return error('insert: ${err}') }
```
`unix_nano().str()` is unique enough across runs; add a counter / `rand.u32()` if
worried. Do NOT rely on ORM autoincrement for int PK.

## 1c. `select` DOES support `order by` (corrected 0.5.2)
`select from T order by ts desc limit N` is VALID — contrary to earlier documentation
that claimed otherwise. The ORM comptime engine handles `order by` with a single
column, optionally followed by `asc`/`desc`:

```v
rows := sql db { select from RunRow where provider == 'openai' order by ts desc limit 10 } or { []RunRow{} }
```

Verified against `vlib/orm/orm.v` which defines `OrderType` enum (`.asc`, `.desc`)
and generates SQL `ORDER BY ts DESC` accordingly.

The `order by` clause MUST be a single column (the ORM does not support
multi-column `order by` in 0.5.2). Sort order options:

| Syntax | Effect |
|--------|--------|
| `order by ts` | ascending (default) |
| `order by ts asc` | ascending |
| `order by ts desc` | descending |

If you need multi-field sorting, fall back to post-fetch sort in V (as described
in older versions of this doc).

## 1d. `delete`/`where` parse quirk — root cause is column vs receiver name clash
```v
pub fn (mut ts TelemetryStore) reset() ! {
    sql ts.db { delete from RunRow where ts >= 0 }   // ❌ cannot use int literal as TelemetryStore
}
```
The error looks like the `>= 0` literal confused the parser, but the REAL cause is a
NAME CLASH: `RunRow` has a column `ts`, and the method's receiver is also named `ts`.
ORM's `where` resolves a bare identifier to the RECEIVER var name FIRST, then the
column — so `ts >= 0` becomes "compare a `TelemetryStore` to an int". Fix (either):
- Rename the receiver (most robust): `pub fn (mut st TelemetryStore) reset() ! { sql st.db { delete from RunRow where ts >= 0 } or {} }`.
- Or change the compared column (`where steps >= 0` / `where provider != ''`).

**General lesson:** ORM `where`/`set` bare identifiers resolve to the receiver var
name BEFORE the table column. If a method handles a table with short columns
(`id`/`ts`/`db`/`row`/`t`), the receiver var name must AVOID those column names —
otherwise `where` silently parses as the receiver type and errors cryptically.
First reaction to a weird ORM parse error: check receiver name vs column name clash.

## 2. `insert ... into` or-block must be NON-EMPTY and return int
- `sql s.db { insert row into T } or {}` → ERROR "expression requires a non empty `or {}` block" (insert yields `int`).
- `or { eprintln(...) }` → ERROR "or block must provide a default value of type `int`" (eprintln returns void).
- `or { 0 }` → OK. (Or `or { panic(err.msg()) }` to fail hard.)
- `update`/`delete`/`select` are void/array → bare `or {}` is fine there.

## 2b. `delete` requires a `where` clause
- `sql s.db { delete from MessageRow }` → ERROR "unexpected token `}`, expecting name/where".
- 0.5.1 ORM `delete` FORCES `where`. For truncate, fall back to raw exec:
```v
s.db.exec('DELETE FROM MessageRow') or {}   // bare truncate
s.save(msgs)                                // then full insert
```
`s.db` is `sqlite.DB` value field; `.exec(query) !` is the low-level method, mixable
with `sql s.db { ... }`. `exec` returns `!` — handle with `or {}`.

## 3. Same-module function name collision
`fn parse_role(s string) Role` defined in `session.v` cannot be redefined in
`webstore.v` (`redefinition of function`). Reuse the existing fn; don't copy.

## 4. `sqlite.DB` holding
- `sqlite.DB` as a VALUE field, methods with value receiver (`fn (s T) list()`) and
  mut receiver (`fn (mut s T) put()`) both persist to disk fine. Relative paths
  (`data/foo.sqlite`) create files normally. No heap pointer needed.

Minimal working template:
```v
import db.sqlite
import os

struct Foo { id string @[primary]; t string }
pub struct Store { db sqlite.DB }

pub fn open_store(path string) !Store {
    dir := path.all_before_last('/')
    if dir != '' { os.mkdir_all(dir) or {} }
    db := sqlite.connect(path)!
    sql db { create table Foo } or { eprintln('create err: ${err}') }
    return Store{ db: db }
}
fn (s Store) list() int { return (sql s.db { select from Foo } or { return -1 }).len }
fn (mut s Store) put(f Foo) { sql s.db { insert f into Foo } or { 0 } }
```

## 5. Test isolation — don't share an on-disk DB
- `new_store()` at a fixed path accumulates rows across `v test` runs → exact-count
  assertions (`assert list.len == 1`) fail on the 2nd run (`list.len == 4`). Give
  tests a unique temp DB per call:
```v
pub fn new_test_store() WebStore {
    p := os.temp_dir() + '/foo-test-' + time.utc().unix_nano().str() + '.sqlite'
    return open_web_store(p) or { panic('new_test_store: ${err}') }
}
```
- Put shared test helpers in a NON-test module file (e.g. `webstore.v`) so all
  `*_test.v` see them — a helper defined in `webapi_test.v` is "undefined" in
  `webapi_http_test.v`.

## 6. Stale-binary trap
After editing `.v`, ALWAYS rebuild (`v -o bin/x ...`) before running. A stale binary
looks like "data not persisting / lost on restart". Debug step: `rm -f <dbfile>` +
rebuild + restart.

## 7. Wiring an ORM store into a veb WebApp (optional field + mut unwrap)
Make the store an OPTIONAL field so HTTP integration tests (`WebApp{ store, config }`
without store) and offline boots don't crash:
```v
pub struct WebApp {
    veb.StaticHandler
pub mut:
    store     WebStore
    config    Config
    telemetry ?TelemetryStore   // optional: no write if unset
}
```
Two compile traps:
1. `app.telemetry = open_store(path) or { none }` is an ERROR — `open_store` returns
   `!TelemetryStore` (Result); its `or` block must provide a `TelemetryStore` value,
   not `none` (that's for `?T`). Correct:
   ```v
   if t := agent.open_telemetry_store(path) { app.telemetry = t } else { app.telemetry = none }
   ```
2. Calling a `mut` method on the unwrapped store needs `if mut ts := ...` — `?T`
   unwrapped with `if ts :=` is IMMUTABLE (`ts.save(...)` → "ts is immutable, declare
   with mut"). Use `if mut ts := app.telemetry { ts.save(...) or {} }`.

## 8. Map copy limits
`by_provider = sum.by_provider` → "cannot copy map: call move or clone" — use
`by_provider = sum.by_provider.clone()`. Same for map fields injected into templates.

## Raw C-API sqlite — exec / exec_param / exec_param2 / exec_param_many

`import db.sqlite` provides raw SQL access with 4 parameter-binding methods:

| Method | Params | Use case |
|--------|--------|----------|
| `db.exec(sql)` | SQL only | CREATE TABLE, DDL, no-user-input queries |
| `db.exec_param(sql, p1)` | SQL + 1 string param | Single parameter queries |
| `db.exec_param2(sql, p1, p2)` | SQL + 2 string params | **BOTH params MUST be `string`** |
| `db.exec_param_many(sql, params)` | SQL + `[]string` | 3+ params |

**⚠️ `exec_param2` type constraint:** both parameters must be `string`. Convert ints:
```v
db.exec_param2('SELECT ... WHERE key = ? AND ts > ?',
    key, time.now().unix_milli().str()) or { return none }
```

**`exec_param_many` takes `[]string`:**
```v
db.exec_param_many('INSERT OR REPLACE INTO cache (key,value,ts) VALUES (?,?,?)',
    [key, value, time.now().unix_milli().str()]) or { eprintln('err: ${err}') }
```

**Reading rows:** `exec`/`exec_param`/`exec_param2`/`exec_param_many` all return
`!sqlite.Result` which has a `.rows` field (`[]sqlite.Row`):
```v
rows := db.exec_param2('SELECT value FROM cache WHERE key = ?', key) or { return none }
if rows.len > 0 { return rows[0].vals[0] }
```

## Raw sqlite (alternative to ORM)
- `import db.sqlite` (thirdparty amalgamation — no system lib).
- Open: `sqlite.connect(path) or { ... }`; `conn.busy_timeout(5000)`.
- WAL: NOT `conn.journal_mode(.wal)` (enum has no `wal`). Use
  `conn.exec('PRAGMA journal_mode=WAL') or {}` + `conn.exec('PRAGMA foreign_keys=ON') or {}`.
- Query: `conn.exec_param(sql, p1)`, `exec_param2`, `exec_param_many(sql, [][]string{...})`.
- Read: `rows := conn.exec_param_many(q, params) or {...}`; `for row in rows { row.get_string('col') }`.

## Troubleshooting checklist
- `no such table` → `create table` swallowed by `or {}`; temp `eprintln` the cause
  (usually `sql: text` typo on PK).
- insert compile: `or block must provide a default value of type int` → `or { 0 }`.
- `delete from Table` bare → ORM forces `where`; use `s.db.exec('DELETE FROM Table') or {}`.
- 2nd-row `UNIQUE constraint failed: runrow.id` → int PK (or dropped `id`); use
  `string @[primary]` + generated id (§1b).
- `select ... order by` → ORM supports `order by col [asc|desc]` — single column only (§1c).
- `delete ... where ts >= 0` → receiver name clashes with column; rename receiver (§1d).
- `or block must provide a value of type Store, not none` → Result `or { none }`
  misuse; use `if t := ... { } else { none }` (§7).
- `ts is immutable` on `?T` unwrap → use `if mut ts := ...` (§7).
- Data "not persisting" → rebuild the binary first (§6).
