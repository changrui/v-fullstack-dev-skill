# Go → V 0.5.x Porting (verified translation diffs)

This reference is for porting a Go codebase to V — the systematic set of
differences that recur on EVERY Go file, proven by porting covonaut's
`fuzzy.go` (169 LoC, pure algorithm) to V 0.5.2 and compiling/running it
(`-prod`, zero errors, assertions passed). A worked demo lives at
`/home/iqdo/covonaut/v_demo/fuzzy/fuzzy.v` — `v run .` reproduces it.

## Methodology (do this, not a blind 1:1 sed)

1. **Port ONE small pure module first** (no net/context/reflect) to shake out
   the mechanical diffs. `fuzzy` is ideal: ~170 LoC, zero deps.
2. Compile with `v run .` (catches syntax/type errors), then `v -prod run .`
   (catches unused-var errors that plain `v run` only warns on), then `v vet .`
   (catches deprecated-inline-comment + unused warnings).
3. **Never 1:1 translate blindly** — these 7 diffs appear on nearly every file
   and each is a hard compile error in V:

## The 7 systematic Go→V translation diffs

| # | Go | V 0.5.x | Fix |
|---|-----|---------|-----|
| 1 | `if x := f(); cond { }` | illegal (unexpected `;`) | pre-declare: `mut x := def; x = f() or {..}` then `if cond` |
| 2 | `strings.Index(s, sub)` -> `int` (use `-1`) | returns `?int` | `idx := s.index(sub) or { -1 }`; unwrap with `if idx := s.index(sub) { .. } else { .. }` (do NOT `== none` then bare-assign) |
| 3 | `strings.Replace(s, old, new, n)` (count arg) | ONLY `s.replace(rep, with)` (global) | "first only" -> `idx := s.index(old) or {-1}; if idx>=0 { return s[..idx]+new+s[idx+old.len..] }` |
| 4 | `x := v` then later `x = other` | `'x' is immutable` | declare `mut x := v` when reassigning |
| 5 | `a, b = b, a` (swap) | "use array2 = array1.clone()" | temp + `.clone()`: `mut t := a.clone(); a = b.clone(); b = t` |
| 6 | `/* inline */` comment | deprecated; vet/`-prod` warn/error | use line comment `//` |
| 7 | unused local var -> just warning | under `-prod` -> **error** | use the value (assert/return it) or `_ = x`; don't leave dead locals |

## Bigger structural gaps (verify BEFORE committing to a full port)

These are NOT mechanical — they change the architecture and are why a 80k-LoC
Go framework is NOT a sensible 1:1 port:

- **`context.Context`**: Go frameworks thread it everywhere for cancel/timeout.
  V has no equivalent — must hand-roll a struct + cancel flag per call site.
- **Generics `[T any]`**: V has generics but the boundary behavior differs;
  expect to rewrite generic containers/Option types.
- **`reflect`** (schema generation, DI, config binding): V's reflect is much
  weaker -> hand-write the schema/structs.
- **`sync` family** (Mutex/RWMutex/WaitGroup/atomic/errgroup): V has `sync`
  (Mutex via `sync.new_mutex()`) but a smaller surface — no `errgroup`, no
  `WaitGroup` (use goroutines + `chan` + `<-ch` collection instead).
- **`net/http`** rich server/client (middleware, streaming, SSE, http2): V's
  `net.http` covers simple GET/POST but streaming/SSE need the `veb` server +
  `veb.sse` (see main SKILL.md). WebSocket: V ships `net.websocket`, so a Go
  dependency on `gorilla/websocket` is REPLACEABLE (covonaut's only external dep).
- **JSON struct tags + custom marshalers**: V uses `@[json: 'x']` tags; omitting
  emits the bare field name (the `type`->`ty` bug in the OpenAI wiring section).
  Prefer `x.json2` for robust decode (user preference).

## Verification recipe (per module)

```
cd <module-dir> && ~/v/v run .            # syntax + type errors
~/v/v -prod run .                          # unused-var errors surface here
~/v/v vet .                                # style: inline comments, unused
```

A clean module passes all three with no output. The covonaut `fuzzy` port is
the reference implementation proving the 7 diffs above are sufficient for a
pure-algorithm module.
