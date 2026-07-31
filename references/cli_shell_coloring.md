# CLI shell-output coloring & related V 0.5.2 gotchas (vaiv 2026-07-21)

Captured while adding ANSI terminal coloring to vaiv's `!` shell-result path.

## 1. Reuse the repo's own `syntax` module for CLI ANSI (don't hand-roll)
A V project that already has a `syntax/` module almost certainly ships BOTH
`highlight_html` (web) and `highlight_ansi` (CLI). For a CLI-only coloring task,
call `highlight_ansi` and print directly — no new dependency:

```v
import syntax
out := syntax.highlight_ansi(source_text, syntax.lang_from_name(ext))
// lang_from_name maps 'v'/'go'/'js'/'html'/'bash' → enum; unknown → .plain
// highlight_ansi returns text wrapped in 256-color SGR codes (reset per token)
```

`lang_from_name` takes a language *name* (e.g. `'v'`), not a filename — derive
the ext yourself: `ext := fname.all_after_last('.')`. `.plain` returns the input
unchanged (safe fallback for non-source args).

**Wiring pattern (module main):** add `colorize_shell_output(command, output) string`
in a `cli_highlight.v`; call it from the `!` print sites (`exec_local_and_exit`
+ the REPL `!` branch). Dispatch by command word:
- source-viewers (`cat`/`sed`/`head`/`tail`/`less`/`bat`/`echo`/`printf`/`nl`/`awk`)
  → `highlight_ansi` when the last arg's extension resolves to a known lang
- `ls` → blue dirs / green execs / yellow archives
- `grep`/`rg` → red the `path:line:` prefix
- everything else → unchanged

## 2. The `!` path is LLM-SAFE — color freely
Single-shot `vaiv "!cmd"` calls `exec_local_and_exit` then `exit(0)`; the REPL
`!` does `continue`. Output is NEVER fed back to the agent, so ANSI codes cannot
pollute model context. No need to strip codes before any LLM handoff.

## 3. The `exit=N\n` prepend trap
`execsafe.run_authorized` returns `output: 'exit=${res.exit_code}\n${out}'`
(execsafe.v ~L254). That `exit=0` line is vaiv's own wrapper, NOT command output —
and a source-viewer highlighter will mis-color it as code (`exit` keyword-blue,
`0` number-orange). Harmless but imprecise. For clean coloring, strip the leading
`exit=N\n` line before highlighting and re-prepend after. For "good-enough" use,
leaving it is fine (the user accepted this).

## 4. V 0.5.2 API gotcha: `string.find` does NOT exist
Use `string.index(sub) ?int` (returns byte offset or `none`):
```v
i := s.index(':') or { -1 }
if i > 0 && i < s.len { ... }
```
Writing `s.find(':')` fails to compile:
`unknown method or field: \`string.find\`` + `assignment mismatch: 1 variable
but \`find()\` returns 0 values`. Hit live while writing a grep-output colorizer.

## 5. Temp probe `.v` files with `fn main()` break `v .`
While developing, a scratch `probe.v` (to test e.g. `syntax.highlight_ansi`) that
declares its own `fn main()` makes the root contain TWO `main` functions →
`v -o bin/vaiv .` fails with `multiple \`main\` functions detected`. The real
`main.v` is fine; the probe is the culprit. **Delete scratch probes immediately**
(`rm -f probe.v`). Keep exactly one `main` per `v .` invocation.

## 6. CRITICAL pitfall: detect execsafe truncation on RAW output, not colored
execsafe caps output with `cap_bytes` and appends a marker:
`\n... [output truncated at N bytes]`. When you wrap command output with
`syntax.highlight_ansi`, that module tokenizes the marker's English words
(`output`/`truncated`/`at`/`bytes`) as identifiers and wraps EACH in SGR codes:
`... [^[[38;5;117moutput^[[0m ^[[38;5;117mtruncated^[[0m ^[[38;5;117mat^[[0m 8000 ...`.
So a post-color `s.contains('truncated at')` (or `'[output truncated at'`) is
**FALSE** — the words are no longer adjacent (ANSI bytes sit between them).

FIX: detect truncation on the ORIGINAL (pre-color) `output`, then pass a `bool`
to the hint-appender. Never `contains()` on the colored string:
```v
truncated := output.contains('truncated at')   // RAW output — stable substring
return with_trunc_hint(command, painted, truncated)
```
NOTE: match `truncated at` (not `[output truncated`) even on raw — the leading
`[` is fine on raw but `truncated at` is the most robust substring either way.
This trap cost a round-trip of debugging (grep output showed the hint; cat
output didn't) — encode it so it's never repeated.

## 7. UX pattern: append a paging hint when truncated
When `truncated` is true, append a ONE-LINE yellow tip telling the user to page
with `!sed -n '1,200p' <file>` (which also gets highlighted). Extract a filename
from the command args (best-effort: first arg containing `.` and not starting
with `-`) so the hint is copy-pasteable:
```v
mut hint := '\n${ansi(33)}[vaiv] 输出被 result_limit 截断。改用分页查看（已支持高亮）：${ansi_reset()}'
hint += if file != '' { ' !sed -n \'1,200p\' ${file}' } else { ' 用 !sed -n \'1,200p\' <file> 翻页' }
```
This pairs with the project convention "large files → `!sed -n` paging" (see
`.vaiv/conventions.md` in the vaiv repo). The hint is purely cosmetic and never
alters command output.

## Verification
`v -o bin/vaiv .` then:
- `vaiv "!head -n 8 cli_highlight.v" | cat -v` → shows `\x1b[38;5;...m` escapes
  (keywords/idents/comments colored)
- `vaiv "!ls -la" | cat -v` → `\x1b[34m` on directory names
- `vaiv "!date"` → stays plain (no coloring)
- `vaiv "!cat agent/tools.v" | tail -2` → shows `... [output truncated at 8000
  bytes]` THEN a yellow `[vaiv] 输出被 result_limit 截断...` hint with the
  filename (`!sed -n '1,200p' agent/tools.v`). CONFIRMS the §6 raw-output fix.
- `vaiv "!sed -n '1,30p' agent/tools.v" | tail -1 | grep -c 截断` → 0 (paged
  output must NOT show the hint — guards against false positives).
