# veb 0.5.1 — live verification recipe + cwd gotcha

## The cwd gotcha (cost real iterations)
`veb.tr` walks `os.walk_ext('translations', '.tr')` from the **cwd at
process start**, NOT the module dir. Consequences:

- **`v test agent/webapi_test.v` (single file) runs with cwd = the
  test file's directory** (`agent/`), so a server/handler that calls
  `veb.tr` finds no `translations/` and returns the key/empty. Symptom:
  i18n asserts fail under single-file `v test` but pass under `v test .`
  run from the project root. **Fix: run `v test .` (whole module) from the
  project root**, OR make the test not depend on cwd-loaded translations.
- **`v -o bin/x cmd/web` / `v run cmd/web/main.v` must be launched
  from the project root** so cwd = root and `translations/` resolves.
  The bin can be moved after build; only the *launch* cwd matters.
- Static files (`/css/*`, `/js/*`) served by `StaticHandler` ARE read
  from disk at request time — they update without recompile. But HTML
  templates (`$veb.html()`) and `.tr` files are inlined at COMPILE
  time (see the existing "stale template cache" pitfall in SKILL.md).

## Reusable live-verification recipe (REST + SSE veb server)
After `v -o bin/vaiv-web cmd/web` from the project root:

```bash
cd /home/iqdo/VcodeAgenntinV   # project root — so translations/ resolves
(./bin/vaiv-web >/tmp/vaiv-web.log 2>&1 &) ; sleep 2
cat /tmp/vaiv-web.log                 # expect: "listening on http://..."

# 1) page routes + static MIME
for p in / /sessions/new "/sessions?id=X" /about /style.css /app.js; do
  printf '%s -> ' "$p"
  curl -s -o /dev/null -w '%{http_code} %{content_type}\n' "http://localhost:8080$p"
done

# 2) REST flow: create -> list -> sync chat
SID=$(curl -s -X POST http://localhost:8080/api/sessions -d '{"title":"t"}' \
      | sed -E 's/.*"id":"([^"]+)".*/\1/')
echo "SID=$SID"
curl -s http://localhost:8080/api/sessions; echo                 # list array
curl -s -X POST "http://localhost:8080/api/session/chat?id=$SID" \
     -d '{"message":"read v.mod"}'; echo                       # sync mock reply
curl -s "http://localhost:8080/api/session?id=$SID" | head -c 300; echo   # full transcript
curl -s -X POST "http://localhost:8080/api/session/delete?id=$SID"; echo  # delete

# 3) SSE stream — expect `data: {...}` events then `event: done` / `data: END`
curl -sN -X POST "http://localhost:8080/api/session/stream?id=$SID" \
     -d '{"message":"again"}' --max-time 5 | head -20
```

Assertions that prove the ReAct loop ran end-to-end through the web layer:
- `GET /api/session?id=` returns `history` with BOTH a `role:user` and a
  `role:assistant` entry, AND a `role:tool` entry when the agent called a
  tool (e.g. `read_file` on `v.mod`). That confirms the mock agent
  actually executed tools via the web request path, not just echoed.
- SSE output contains `data: {"role":"assistant"` and ends with
  `event: done` + `data: END` (then `event: close`).

## Stopping the server between rebuilds
`pkill -f bin/vaiv-web` then rebuild, then restart. (Note: `pkill`
may return a non-zero/negative status in some shells — sequence the
rebuild and restart as SEPARATE terminal calls, not chained with `&&`,
to avoid a failed `pkill` aborting the rebuild.)
