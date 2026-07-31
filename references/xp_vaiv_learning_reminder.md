# vaiv learning-reminder pattern (Phase 9.5, v0.6.5)

A reusable pattern for an AI-coding agent (or any CLI tool) that wants to
**proactively remind the user to capture learnings** as durable conventions,
without becoming annoying. Implemented in `agent/conventions_learning.v`.

## Why
The user wanted vaiv to "remind me to extract programming experience / improve my
skills so future coding takes fewer detours." The fix is NOT to auto-write
conventions (that risks mis-recording) but to **nudge** the user after a useful
turn, leaving the actual `convention_add` call to them or to an explicit "记住：".

## Design rules (non-nagging, zero-block, cheap)
1. **Gate on real tool use + sparse store.** Only suggest when:
   - `stats.tools.len > 0` (the run actually *executed* a tool — not just
     `stats.tool_calls`, which is "LLM requested"; `record_tool_exec` fills the
     map, `record_tool_call` fills the count, and they are separate in V 0.5.x),
   - AND total convention entries across all layers `< quiet_threshold` (3).
   Once the user has captured enough, the reminder retires automatically.
2. **Name the tools that fired.** Pull keys from `stats.tools` and list them in
   the hint so the nudge feels relevant ("本次用到 list_files、web_search…").
3. **Never pollute machine output.** Print the `[tip]` line only in plain / REPL
   success branches of the turn runner; skip it entirely in `--json` mode.
4. **No extra LLM call.** Pure local heuristic — offline-safe, free.
5. **Keep it in the CLI entry, not the agent core.** The agent module stays
   pure; `main.v`'s `run_turn()` calls `maybe_suggest_learning(store, stats)` and
   prints iff non-empty. This keeps `v test .` for the agent module isolated.

## V 0.5.x pitfalls hit while building it
- A local `s := new_run_stats(...)` must be `mut s` if you call a `mut` method
  like `s.record_tool_exec(...)` — V 0.5.x locals are immutable by default
  (`'s' is immutable, declare it with 'mut'`).
- `ConventionsStore.count()` = `list(.system).len + list(.project).len` — reuse
  the existing `list()` parser rather than re-reading files.

## Test shape (3 tests in `conventions_learning_test.v`)
- sparse store + tool exec → suggestion returned AND contains the tool name.
- store with >= 3 conventions → returns `''` (nudge retired).
- hint lists the tools that fired.
Use a temp dir via `new_conventions_store(sys, proj)` to keep tests off the real
`~/.vaiv`. Assert against the parsed result, not a subprocess, for determinism.
