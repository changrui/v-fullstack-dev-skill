# veb login wall — worked pattern (V 0.5.2)

A complete, copy-modify template for an authenticated veb web app: bcrypt
register/verify + SQLite user & token tables + middleware guard + cookie
helpers + per-user data isolation.

## 1. App struct MUST embed the middleware

```v
pub struct WebApp {
	veb.StaticHandler
	veb.Middleware[WebCtx]   // REQUIRED — gives the `.Middleware` field
pub mut:
	store        WebStore
	current_user ?User
}
```

Without `veb.Middleware[WebCtx]` embedded, `app.Middleware.use(...)` fails to
compile (`no field or method Middleware`).

## 2. The guard (middleware, not before_request)

`Context.before_request()`'s return value is IGNORED — you cannot block a
request with it. Use an explicit middleware instead.

```v
pub fn (mut app WebApp) auth_guard(mut ctx WebCtx) bool {
	if ctx.query['__health'] != '' { return true }   // optional escape hatch
	token := ctx.get_cookie(session_cookie_name) or { '' }
	if token != '' {
		if u := app.store.user_from_token(token) {
			app.current_user = u
			return true
		}
	}
	// not authenticated
	if ctx.req.path.starts_with('/api/') {
		ctx.res.set_status(.unauthorized)
		ctx.text('unauthorized')
		return false
	}
	ctx.redirect('/login', veb.RedirectParams{})   // NO `or {}` — redirect returns nothing
	return false
}

// PUBLIC whitelist check (use ctx.req.path, NOT ctx.req.url!)
// ctx.req.url INCLUDES the query string, so `path == '/login'` fails for
// `/login?from=/` and the login page gets re-gated into a
// `/login?from=/login?from=/...` redirect loop. Match on ctx.req.path.
fn is_public(p string) bool {
	return p == '/login' || p == '/register' || p.starts_with('/api/login')
		|| p.starts_with('/api/register') || p == '/api/logout' || p == '/lang' || p == '/about'
}
// in auth_guard: if is_public(ctx.req.path) { return true }
```

Register it in `mount_defaults()`:

```v
app.Middleware.use(handler: app.auth_guard)
```

- Middleware signature `fn (mut app A) (mut ctx X) bool`; the `bool` IS honoured
  (`false` short-circuits, `true` continues). The Context-only `before_request`
  cannot reach `app.store` / `app.current_user` — the middleware method can.
- `ctx.redirect(...)` returns **no Result** — do NOT write `or {}` after it
  (compile error: `or` block on a non-Result).
- Setting a cookie via `ctx.set_cookie(...)` inside the guard WORKS: middleware
  runs before the handler writes the response, so the Set-Cookie lands on the
  eventual response.

## 3. Cookie helpers

```v
const session_cookie_name = 'vaiv_session'

fn set_auth_cookie(mut ctx WebCtx, token string) {
	ctx.set_cookie(http.Cookie{
		name:      session_cookie_name
		value:     token
		path:      '/'
		http_only: true
		max_age:   31536000
	})
}
// reading: ctx.get_cookie(session_cookie_name) ?string
```

`ctx.set_cookie` takes an `http.Cookie` STRUCT (import `net.http`), not named args.

## 4. bcrypt + token store (SQLite)

```v
import crypto.bcrypt
import crypto.rand
import db.sqlite

struct WebUserRow {
	// id string @[primary], username string, passhash string, created string
}
struct WebTokenRow {
	// token string @[primary], user_id string, expiry string
}

fn (s WebStore) register_user(username string, password string) !User {
	if password.len == 0 { return error('empty password') }
	if password.len > 72 { return error('password too long (bcrypt max 72)') }
	hash := bcrypt.generate_from_password(password.bytes(), 10) !  // 10 = cost
	mut u := User{ id: gen_id(), username: username }
	s.db.exec("INSERT INTO WebUserRow (id,username,passhash,created) VALUES ('${u.id}','${username}','${hash}','${now()}')")!
	return u
}
fn (s WebStore) verify_login(username string, password string) ?User {
	// SELECT passhash,id FROM WebUserRow WHERE username=username; then
	// bcrypt.compare_hash_and_password(password.bytes(), passhash.bytes()) or { return none }
}
fn (s WebStore) issue_token(user_id string) string {
	raw := rand.bytes(32) or { panic('rand') }
	token := raw.hex()                       // []u8.hex() — NOT raw.bytes().hex()
	// INSERT INTO WebTokenRow (token,user_id,expiry) VALUES (...)
	return token
}
```

- `bcrypt.generate_from_password(pwd []u8, cost int) !string`; input capped at
  72 bytes — reject longer passwords or it errors.
- `crypto.rand.bytes(32)` returns `[]u8`; call `.hex()` directly on it.
- `veb/auth` exists but is sha256+salt (NOT bcrypt) and generic over `sqlite.DB`;
  if your store wraps the DB privately, write your own tables (as above).

## 5. Per-user data isolation (CRITICAL ORM pitfall)

The V ORM silently mishandles a WHERE whose right-hand param is named the same
as the column: `where owner == owner` returns nothing, and
`where id == id && owner == owner_id` IGNORES the `owner` condition (cross-user
GET returned 200 -> data leak). Safe pattern:

```v
fn (s WebStore) get(owner_id string, id string) ?WebSession {
	rows := sql s.db { select from WebSessionRow where id == id } or { return none }
	if rows.len == 0 { return none }
	if rows[0].owner != owner_id { return none }   // enforce in V, not SQL
	r := rows[0]
	// ...build sess, load messages...
}
fn (s WebStore) list(owner_id string) []WebSession {
	rows := sql s.db { select from WebSessionRow where owner == owner_id } or { return [] }
	// ^ param renamed so it differs from the `owner` column
}
```

- `list` with `where owner == owner_id` (param differs from column) works; the
  original `where owner == owner` (same name) silently returned 0.
- `get`/`del`: do the PK lookup in SQL (`where id == id`) then enforce `owner`
  in V. Never rely on `id == id && owner == owner_id`.

## 6. Migration for added columns

`create table` is idempotent — it skips if the table exists, so adding a column
later won't apply to the live DB. On startup:

```v
fn ensure_owner_column(db sqlite.DB) {
	rows := db.exec('PRAGMA table_info(WebSessionRow)') or { return }
	mut has := false
	for r in rows { if r.vals.len >= 2 && r.vals[1] == 'owner' { has = true; break } }
	if !has {
		db.exec('ALTER TABLE WebSessionRow ADD COLUMN owner TEXT DEFAULT \'\'') or { eprintln('migrate failed') }
	}
}
```
