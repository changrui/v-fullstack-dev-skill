# Multi-session CLI storage recipe (V 0.5.x)

Distilled from vaiv Phase 11: add named sessions to an existing single-file
SQLite transcript store WITHOUT changing the public `open_session` / `load` /
`replace` API or breaking tests.

## Core idea
Fan out by **file path**, not by a `session_id` column. Keep `MessageRow`
unchanged. Each conversation = `data/sessions/<name>.sqlite`.

```v
// in main(): derive the path from a --session <name> flag (default 'default')
session_path := os.join_path(agent.project_root(), 'data', 'sessions', '${session_name}.sqlite')
os.mkdir_all(os.dir(session_path)) or { eprintln('failed: ${err}'); exit(1) }
sess := agent.open_session(session_path) or { eprintln('open failed: ${err}'); exit(1) }
```

`open_session` returns `!&Session` (it's an `@[heap]` struct). There is NO
`close()` method — just let it go out of scope.

## Backward-compat migration
```sh
mkdir -p data/sessions
mv data/session.sqlite data/sessions/default.sqlite   # rename, never rm
```

## Subcommands (all run WITHOUT the LLM — return before agent setup)

```v
fn sessions_dir() string {
	return os.join_path(agent.project_root(), 'data', 'sessions')
}

fn list_sessions() {
	dir := sessions_dir()
	if !os.exists(dir) { println('[vaiv] no sessions yet (${dir})'); return }
	files := os.ls(dir) or { [] }
	mut names := []string{}
	for f in files {
		if f.ends_with('.sqlite') { names << f.all_before_last('.sqlite') }
	}
	if names.len == 0 { println('[vaiv] no sessions yet (${dir})'); return }
	names.sort()
	println('[vaiv] sessions (${names.len}):')
	for n in names {
		s := agent.open_session(os.join_path(dir, '${n}.sqlite')) or { continue }
		if msgs := s.load() { println('  - ${n}  (${msgs.len} messages)') }
	}
}

fn export_session(name string) {
	path := os.join_path(sessions_dir(), '${name}.sqlite')
	if !os.exists(path) { eprintln('vaiv-export: session not found: ${name}'); exit(1) }
	s := agent.open_session(path) or { eprintln('cannot open: ${err}'); exit(1) }
	msgs := s.load() or { eprintln('cannot load: ${err}'); exit(1) }
	println('# vaiv session: ${name}\n')
	println('_exported at ${time.now().format_ss()}_\n')
	for m in msgs {
		match m.role {
			.system { /* skip system prompt from export body */ }
			.user { println('## User\n\n${m.content}\n') }
			.assistant { println('## Assistant\n\n${m.content}\n') }
			.tool { println('## Tool\n\n```\n${m.content}\n```\n') }
		}
	}
}

fn print_config(c agent.Config) {
	println('[vaiv] resolved configuration')
	println('  provider: ${c.provider}')
	println('  api_key:  ${if c.api_key != '' { '***set***' } else { '(none) -> mock' }}')
	// ... print the rest of the fields
}
```

## Dispatch in `main()`
Parse one bool per subcommand; after the `update` branch and BEFORE opening
telemetry/session, handle them with early `return`:

```v
if config_out   { print_config(config); return }
if sessions_out { list_sessions(); return }
if export_out   { export_session(session_name); return }
```

`--session <name>` consumes the next arg in the parse loop:
```v
'--session' {
	if i + 1 < raw_args.len { session_name = raw_args[i + 1]; i++ }
}
```

## Gotchas hit & fixed this session
- `Session` has no `close()` → omit it (compile error otherwise).
- `time.now().format_ss()` is valid (returns `YYYY-MM-DD HH:MM:SS`); no need for
  `format_rfc3339()` + substring slicing.
- Subcommand dispatch MUST `return` unconditionally — do not fall through into
  the agent/REPL or an `update`-style command will drop into a REPL prompt on
  success (see the "Subprocess delegation" rule in SKILL.md).
- Requires `import time` in `main.v` when using `format_ss()`.
