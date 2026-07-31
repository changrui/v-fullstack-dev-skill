# veb 0.5.1 — HTTP-level integration test recipe

Verified pattern: boot the real WebApp in a goroutine and hit it with
`net.http`. Covers pages + REST + SSE under the same `v test` gate.

```v
module agent

import net.http
import time
import x.json2

const web_test_port = 13040

fn test_web_http() {
	mut app := &WebApp{
		store:  new_store()
		config: Config{ provider: 'mock', max_steps: 8 }
	}
	app.mount_defaults()      // mount_static etc. (shared with cmd/web)
	spawn veb.run_at[WebApp, WebCtx](mut app,
		port: web_test_port, family: .ip, timeout_in_seconds: 30)
	time.sleep(400 * time.millisecond)

	base := 'http://127.0.0.1:${web_test_port}'

	// page
	home := http.fetch(http.FetchConfig{ url: base + '/' }) or { assert false; return }
	assert home.status_code == 200
	assert home.body.contains('vaiv')

	// static MIME
	css := http.fetch(http.FetchConfig{ url: base + '/style.css' }) or { assert false; return }
	assert css.status_code == 200
	ct := css.header.get(.content_type) or { '' }
	assert ct.contains('text/css')

	// REST create (POST json)
	created := http.post_json(base + '/api/sessions', '{"title":"t"}') or { assert false; return }
	assert created.status_code == 200
	mut cid := ''
	if sess := json2.decode[WebSession](created.body) { cid = sess.id }
	assert cid != ''

	// SSE stream (POST json)
	stream := http.post_json('${base}/api/session/stream?id=${cid}', '{"message":"x"}') or { assert false; return }
	assert stream.status_code == 200
	assert stream.body.contains('data:')
	assert stream.body.contains('event: done')

	// delete
	del := http.post_json('${base}/api/session/delete?id=${cid}', '{}') or { assert false; return }
	assert del.body.contains('"ok":"1"')
}
```

Gotchas that cost iterations (all verified in this build):
- `spawn` forbids mutable non-reference args → app MUST be `&WebApp`.
- `http.fetch` takes ONE positional `config FetchConfig` arg, NOT
  `fetch(config: ...)` (that mis-nests and errors `unknown field config`).
  For JSON body prefer `http.post_json(url, data)` (sets content-type).
- `resp.header.get(.content_type)` is `?string` → unwrap `or { '' }`.
- `x.json2.decode[T](body)` — decode into the struct type that holds
  ALL fields; a `map[string]string` fails if a field is an array (e.g. history).
- `timeout_in_seconds: 30` keeps the server up through all assertions; it dies
  when the test process exits.
- The server's cwd is the test process cwd → `translations/*.tr` and
  `./web/static` must exist there. With `v test .` from the project root
  they do. A single-file run `v test agent/foo_test.v` sets cwd to the
  file's dir and `veb.tr` fails to load translations — run `v test .`.
