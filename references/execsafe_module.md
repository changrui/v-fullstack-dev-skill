# Hardened shell-command execution module (V 0.5.2)

When an agent/app needs to run local commands, do it DEFENSE-IN-DEPTH. The
pattern below was extracted from vaiv's `agent/execsafe.v` (Phase 21) and is
reusable for any V tool that shells out.

## Security model (defence in depth)
1. **Policy gate** — `deny` (nothing runs) / `allowlist` (only programs on an
   explicit allow list) / `confirm` (anything not on a `dangerous()` blacklist;
   risky ones need confirmation). Fail closed: unknown env value → the strict
   default.
2. **No shell** — split the command line into an argv vector and run via
   `os.exec(args)` (execvp). NEVER `os.execute('sh -c "..."')`. This removes the
   entire shell-injection class: `;`, `&&`, `$()`, `|`, backticks are inert
   because there is no shell to interpret them. VERIFY: `tokenize("echo hi; rm -rf /")`
   yields one `echo` command with literal args; a probe file is NOT created.
3. **Dangerous-pattern backstop** — even allow-listed programs with hostile
   arguments (e.g. `git push`, `python3 -c '...'`) are still blocked/confirmed
   via a `dangerous()` blacklist (rm-/rmdir/dd/mkfs/chmod -R/chown/fork-bomb/
   >/dev//shutdown/reboot/kill/pkill/killall/truncate/shred — see agent/confirm.v).
4. **Audit trail** — append every decision (allow/deny/exec/error + program +
   exit code + raw command) to a log file (e.g. `data/vaiv-exec.log`, TSV).

## Two policy tiers (vaiv's choice)
- **Agent / tool exec** → default `allowlist` (unattended, strict).
- **Interactive CLI `!` command** → default `confirm` (human at keyboard:
  block destructive, allow normal dev commands like `!pip`, `!docker`,
  `!python3`). Both overridable via `VCA_EXEC_POLICY` / `VCA_CLI_EXEC_POLICY`.
  Rationale: a human typing `!` sees the output immediately, so confirm policy
  is the right ergonomic/security balance; allowlist is too constraining for
  interactive use.

## Tokenizer (shell-free split)
Hand-rolled: iterate bytes, split on whitespace, respect `'` and `"` quoting.
No glob/variable expansion. `for ch in cmd` yields `u8` bytes (see pitfalls).

## V 0.5.2 pitfalls hit while building this (SAVE THESE)
- `cur += ch` where `ch` is `u8` → compile error "invalid operation: string += u8".
  Fix: `cur += ch.ascii_str()`.
- **`os.exec(args []string)` returns `os.Result` directly — NOT a `!T`/`?T`.**
  Do NOT write `res := os.exec(...) or { ... }`; just `res := os.exec(...)` and
  read `res.exit_code` / `res.output`. (`os.execute` also returns Result directly.)
- **Array `<<` does NOT chain:** `argv << 'timeout' << cmd.timeout.str()` errors.
  Use two statements: `argv << 'timeout'` then `argv << cmd.timeout.str()`.
- **`os.append_file` does NOT exist** in this build. For append logging use
  `mut f := os.open_file(path, 'a') or { ... }; f.writeln(line); f.close()`.
- Same-module name clash: two `.v` files in `module agent` both declaring
  `pub struct RunResult` → "another type with this name exists". Reuse the
  existing struct instead of redefining; or name the new one distinctly.
- `confirm()` (from agent/confirm.v) returns `false` when stdin is not a TTY —
  so under `VCA_AUTO_YES=0` + non-interactive, risky commands are BLOCKED, not
  auto-run. Good. But if `VCA_AUTO_YES=1`, ALL dangerous commands auto-run in
  non-interactive contexts — never widen access with `auto` under allowlist/
  deny; only use it to skip the *confirmation* step within `confirm` policy.

## Output truncation — `result_limit` and the `!sed` pagination pattern
Every execsafe output is capped by `result_limit` bytes (default **8000**, set via
`.vaiv/config.yaml` `result_limit:` or the `VCA_RESULT_LIMIT` env var; **config wins
over env** — env only *supplements* a missing field). The cap is applied in
`cap_bytes()` (execsafe.v) and `cap_output()` (tools.v); both append
`\n... [output truncated at N bytes]` when exceeded. So `!cat bigfile` gets silently
chopped at 8000B.

**Pagination pattern (use instead of `!cat`):** the `!` path in single-shot mode
(`vaiv "!cmd"`) goes straight to `exec_local_and_exit` (main.v ~L245) and **exits
without calling the LLM** — zero tokens, never pollutes session history. Page a large
file locally:
```
vaiv "!wc -l file"                # probe total lines first
vaiv "!sed -n '1,200p' file"      # ~200 lines/page stays under 8000 bytes
vaiv "!sed -n '201,400p' file"
vaiv "!tail -n 120 file"
```
~200 lines/page keeps code files comfortably under the cap; a `grep 'truncated at'`
check stays empty across all pages.

**Temporary one-shot raise:** `VCA_RESULT_LIMIT=100000 vaiv "!cat file"` works —
but `0` does NOT disable the cap (it falls back to default 8000). Do NOT permanently
enlarge `result_limit`; it is the safety valve preventing tool output from blowing up
the LLM context window.

## End-to-end verification (do this before claiming done)
Using `subprocess` (NOT the agent's own shell, which may block `rm`-style
strings) call the built binary with `!` commands:
- `!echo hello` → runs (confirm policy allows).
- `!git push origin x` → blocked ("requires confirmation").
- `!echo hi; touch /tmp/probe` → probe file NOT created (proves no shell split).
- `!python3 --version` → runs (confirm allows non-dangerous).
- inspect `data/vaiv-exec.log` → lines present for each decision.
