# V 0.5.x Concurrency — deep detail

Companion to `v-fullstack-dev` SKILL.md.

## go / chan / select
- `go fn () { ... }` spawns a goroutine. `chan T` for typed channels; `select { ... }`
  (V has `select` for channels like Go).
- **`spawn`/`go` cannot take mutable non-reference args.** Pass a `&T` reference or a
  struct holding the data:
```v
mut app := &WebApp{ ... }
spawn fn [mut app] () { veb.run_at[WebApp, WebCtx](mut app, port: p) or { panic(err) } }()
```

## Closure capture is COPY (the core trap)
- `fn [x] (..) { }` gives the closure its OWN copy of `x`; mutations inside
  (`files << fp`, `n++`) do NOT change the caller's `x`. Even `fn [mut x]` does not
  sync back. Consequence: `os.walk(root, fn [mut files] (fp) { files << fp })` leaves
  outer `files` EMPTY — `os.walk` with a callback is useless for collecting.
- Fix: explicit recursion with `os.ls` + `os.is_dir` (see syntax reference), or share
  state via a `chan` / `sync.Mutex`-guarded struct.

## sync.Mutex
- `defer` exists in V 0.5.x. Use it to pair lock/unlock:
```v
mut mu := sync.new_mutex()
mu.lock()
defer { mu.unlock() }
/* critical section */
```
- `get(id)` must return a real `?T`: check `if id !in m { mu.unlock(); return none }`
  BEFORE reading — `m[id]` on a missing key returns the zero value, not `none`.

## `?fn` optional function-pointer struct fields
- Declaring `run ?fn (args string, ctx &ToolCtx) Ret` makes the field an OPTIONAL fn
  ptr. Call it with the `?` unwrap syntax: `r := t.run?(args, ctx)` — this returns the
  plain `Ret` value (NOT an Option), so do NOT add `or { }` after it. Calling
  `t.run(args, ctx)` without `?` errors: "Option function field must be unwrapped first".
- Inside a `?Message`-returning function, calling a `?fn` field is accepted without
  `or`; only genuine `?T` values need `or`/`if x :=`.

## Channel patterns
- `ch := chan int{}`; send `ch <- 1`; receive `v := <-ch` or `if v := <-ch { ... }`.
- For fan-out/fan-in (parallel sub-agents): `mut results := []SubResult{}`; `mut mu := sync.new_mutex()`;
  spawn N goroutines that push to a `chan SubResult{}`, main `for _ in 0..n { r := <-ch; mu.lock(); results << r; mu.unlock() }`.
- Topological waves: compute dependency layers (Kahn), run each layer's tasks
  concurrently, await the layer before the next (see vaiv `orchestrator.v` for a
  worked example).
