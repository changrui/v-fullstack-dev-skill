# vaiv self-update script — reusable `.vsh` template (form C)

A V script (`v run scripts/vaiv_update.vsh`) that self-updates a compiled V project:
locate repo root → guard uncommitted changes → `.bak` the old binaries → `git pull
--ff-only` → recompile → run tests → rollback on failure. Invoked both standalone and
by the `vaiv update` CLI command (via `os.execute('v run ...')`).

## Key lessons baked into the template
- Multi-return `:=` reuse must use DISTINCT var names (`c2, out2`), not `c, out = ...`.
- `mv -f src src.bak` for backup — no `rm`. Honors the "never delete files" rule.
- `--force` skips the git-status guard; `--dry-run` prints steps without executing;
  `--self-test` runs pure-function assertions (no git/compile).
- `find_v()` resolves `~/v/v` then falls back to PATH `v`.

## Skeleton (condensed)
```v
import os

fn sh(cmd string) (int, string) {
	res := os.execute(cmd)
	return res.exit_code, res.output
}
fn is_clean(status string) bool { return status.trim_space() == '' }
fn parse_version(content string) string {
	for line in content.split('\n') {
		t := line.trim_space()
		if t.starts_with('version:') {
			mut rest := t.after('version:').trim_space()
			return rest.replace("'", '').trim_space()
		}
	}
	return 'unknown'
}
fn backup(src string, dry bool) {
	bak := src + '.bak'
	if !os.exists(src) { return }
	if dry { println('[dry-run] would backup ${src}') ; return }
	os.execute('mv -f "${src}" "${bak}"')   // overwrite stale .bak, never rm
}
fn main() {
	// args: --force --dry-run --self-test
	code, root := sh('git rev-parse --show-toplevel')
	root = root.trim_space()
	_, status := sh('git status --porcelain')
	if !is_clean(status) && !force {
		eprintln('uncommitted changes — aborting'); exit(1)
	}
	backup(bin_vaiv, dry); backup(bin_web, dry)
	if !dry { _, out := sh('git pull --ff-only'); ... }
	vbin := find_v()
	if !dry {
		c, out := sh('${vbin} -o ${bin_vaiv} main.v')
		if c != 0 { restore...; exit(1) }
		c2, out2 := sh('${vbin} -o ${bin_web} cmd/web/main.v')  // DISTINCT names
		if c2 != 0 { restore...; exit(1) }
		c, out := sh('${vbin} -silent test .')   // c reused OK here (new scope)
		...
	}
	mut ver := 'unknown'
	if vm := os.read_file(join(root,'v.mod')) { ver = parse_version(vm) }
	println('updated to v${ver}')
}
```
Note: the two `c, out :=` lines above are in SEPARATE `if` blocks (separate scopes),
so reuse is fine there — only reuse *within the same scope* needs distinct names.

Full source: `/home/iqdo/VcodeAgenntinV/scripts/vaiv_update.vsh` (tag v0.6.1).
