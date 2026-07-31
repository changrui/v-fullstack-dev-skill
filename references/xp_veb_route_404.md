# xp_veb_route_404.md — veb 404 from frontend/backend route-format mismatch

Session-derived debugging playbook (vaiv web UI, veb 0.5.2, compiler at ~/v).

## Symptom
Browser: clicking "Open session" on the index page → `404 Not Found`. The homepage
itself renders fine and **lists existing sessions** (proving the DB store works), so
the session is NOT missing — the navigation target is wrong.

## Root cause
A mismatch between the URL format the frontend generates and the URL format the
backend veb routes are registered with:

- Backend (`agent/webapi.v`) registers **query-style** routes (and the handler even
  comments "The id comes from the query string (?id=...) to avoid path-param codegen
  quirks"):
    - `@['/sessions']`   → reads `ctx.query['id']`
    - `@['/api/session/chat'; post]`    → reads `ctx.query['id']`
    - `@['/api/session/stream'; post]`  → reads `ctx.query['id']`
    - `@['/api/session/delete'; post]`  → reads `ctx.query['id']`
- Frontend generated **path-style** URLs:
    - `index.html`: `<a href="/sessions/@s.id">`  → `/sessions/<id>`
    - `app.js`: `/api/sessions/<id>/chat`, `/api/sessions/<id>/stream`,
      `/api/sessions/<id>/delete`, and `location.href = '/sessions/<id>'`

`/sessions/<id>` has NO registered route → veb returns a raw **HTTP 404**. The app's
own `ctx.text('session not found: …')` fallback never runs (that returns HTTP 200),
which is the key tell that distinguishes "wrong URL shape" (404) from
"session truly absent" (200 + body).

## Why it's easy to miss
- `list()` works → homepage looks healthy, DB looks fine, so you assume the session
  fetch is broken when it's actually the *link target* that 404s.
- veb's 404 is a bare server response, not a styled in-app page, so it reads like a
  server/config problem rather than a front-end string bug.
- Templates + static assets are **compile-time embedded** — fixing `index.html`/
  `app.js` does nothing until you **rebuild the binary** (`~/v/v -o bin/vaiv-web cmd/web`).
  A stale binary keeps serving the old broken links.

## Fix (align frontend → backend's query-style routes; do NOT change backend)
- `web/templates/index.html`:
  `<a href="/sessions/@s.id">` → `<a href="/sessions?id=@s.id">`
- `web/static/app.js` (4 spots):
  - `'/api/sessions/' + sid + '/stream'` → `'/api/session/stream?id=' + sid`
  - `'/api/sessions/' + sid + '/chat'`   → `'/api/session/chat?id=' + sid`
  - `'/api/sessions/' + id + '/delete'`  → `'/api/session/delete?id=' + id`
  - `location.href = '/sessions/' + sess.id` → `'/sessions?id=' + sess.id`

Rationale: backend comment explicitly avoids path params (`/x/:id` codegen quirks in
this veb build), so the durable fix is to keep the frontend on query params, not to
add path-param routes. (If you ever DO want pretty URLs, you must add matching
`@['/sessions/:id']` veb routes that read `ctx.params['id']` AND rebuild.)

## Verification (real, against built binary)
```sh
cd /home/iqdo/VcodeAgenntinV
~/v/v -o bin/vaiv-web cmd/web            # REQUIRED: rebuild (embedded assets)
VAIV_WEB_PORT=3003 ./bin/vaiv-web &
SID=<id from GET /api/sessions json>
curl -s -o /dev/null -w "OLD path-style : %{http_code}\n" http://localhost:3003/sessions/$SID   # expect 404
curl -s -o /dev/null -w "NEW query-style: %{http_code}\n" "http://localhost:3003/sessions?id=$SID"  # expect 200
curl -s -o /dev/null -w "/sessions/new  : %{http_code}\n" http://localhost:3003/sessions/new        # expect 200
curl -s "http://localhost:3003/sessions?id=$SID" | head -c 120   # expect <!doctype html> + title
```
Confirm session page returns rendered HTML (not a `session not found` text body).
Then kill the test server.

## One-line rule for future V/veb work
Frontend URL shape MUST match the registered route shape. When a veb handler reads
`ctx.query['x']`, every link/JS fetch to that resource must use `?x=` — never `/x/`.
And remember: edit HTML/JS → **rebuild** → retest.
