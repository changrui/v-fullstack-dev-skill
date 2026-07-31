# vaiv mock-provider testing recipe (VERIFIED 2026-07-13)

`vaiv` ships a deterministic mock LLM (`VCA_PROVIDER=mock`) so `v test .` and
offline CLI runs need no API key. But the mock has ONE behavior that makes
single-shot telemetry assertions misleading when a session is already populated.

## The artifact

`agent/llm.v` `mock_chat` returns a tool call (e.g. `read_file`) only when the
history has NO `role: .tool` message; the moment it sees a tool result in history
it returns the final "MOCK: I have completed the task" message with zero tool
calls. So:

- A *fresh* session → `vaiv --json "read v.mod"` shows
  `steps:2, tool_calls:1, tools:{read_file:1}, finish:ok`.
- A session that already contains a tool message (from prior runs persisted in
  `data/session.sqlite`) → shows `tool_calls:0, finish:ok` because the mock
  short-circuits. **This is correct mock behavior, not a regression.**

The agent's `last_run` telemetry is computed correctly in both cases; the `0` is
purely an artifact of the loaded history.

## How to get a clean single-shot run

Option A — move the persisted session aside for the test, then restore:

    mv data/session.sqlite /tmp/vaiv-session.bak
    env -u VCA_API_KEY VCA_PROVIDER=mock ./bin/vaiv --json "read v.mod"
    mv /tmp/vaiv-session.bak data/session.sqlite

Option B — force pure mock offline by clearing the key (the project's
`finalize()` upgrades `mock`→`openrouter` when a key is present, so a live
`VCA_API_KEY` would make `mock` silently become a real remote call):

    env -u VCA_API_KEY VCA_PROVIDER=mock ./bin/vaiv --json "read v.mod"

## Parallel mode is immune to the artifact

`agent/orchestrate` spins up FRESH `Agent` instances per subtask (each with its
own `ToolCtx`, no `Session`), so the persisted CLI session does NOT affect them.
That's why `VCA_PARALLEL=1 vaiv --json "1. do A\n2. do B"` correctly shows
`subtasks:N, subtask_errors:0` and each sub-agent fires its tool — even when the
CLI single-shot path shows `tool_calls:0`. Use parallel mode to confirm a tool
actually executes when the persisted session looks "polluted".

## Shell-newline caveat

When passing a multi-line numbered prompt to test the planner heuristic, do NOT
put a literal `\n` inside double quotes — bash does not expand it, so the prompt
arrives as one line and the heuristic sees a single item (subtasks=1, not N).
Use a real newline:

    printf '1. do alpha\n2. do beta\n3. do gamma\n' > /tmp/p.txt
    env -u VCA_API_KEY VCA_PROVIDER=mock VCA_PARALLEL=1 ./bin/vaiv --json "$(cat /tmp/p.txt)"

The heuristic splits on lines starting with `1.`/`1)`/`2.` (digit + `.`/`)`),
or `- ` bullets; needs >= 2 items to decompose.
