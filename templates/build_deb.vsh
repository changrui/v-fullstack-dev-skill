// build_deb.vsh — template: build a Debian (.deb) for a V project.
// Copy-modify: adjust Maintainer/Depends/Description. Run:
//   v run scripts/build_deb.vsh [--arch amd64] [--output DIR]
//                              [--maintainer "Name <e>"] [--dry-run] [--help]
// Needs `dpkg-deb` (every Debian/Ubuntu host) + the V compiler (to build).
import os

fn sh(cmd string) (int, string) {
	res := os.execute(cmd)
	return res.exit_code, res.output
}

// quote wraps a path in single quotes for safe shell interpolation (escapes
// any embedded single quote). vsh scripts don't see agent.shell_quote.
fn quote(s string) string {
	return "'" + s.replace("'", "'\\''") + "'"
}

fn find_v() string {
	mut p := os.getenv('V_EXE')
	if p != '' && os.exists(p) {
		return p
	}
	_, out := sh('command -v v')
	if out.trim_space() != '' {
		return 'v'
	}
	for cand in [os.join_path(os.home_dir(), 'v', 'vnew'), os.join_path(os.home_dir(), 'v', 'v')] {
		if os.exists(cand) {
			return cand
		}
	}
	return 'v'
}

// read_vmod_field pulls a `key: 'value'` line from v.mod.
fn read_vmod_field(field string) string {
	path := os.join_path(os.getwd(), 'v.mod')
	if !os.exists(path) {
		return ''
	}
	content := os.read_file(path) or { return '' }
	for line in content.split('\n') {
		trimmed := line.trim_space()
		if trimmed.starts_with('${field}:') {
			val := trimmed.all_after(':').trim_space().trim('\'"')
			return val
		}
	}
	return ''
}

fn usage() {
	println('usage: v run scripts/build_deb.vsh [--arch amd64] [--output DIR] [--maintainer S] [--dry-run] [--help]')
}

fn main() {
	mut arch := 'amd64'
	mut output_dir := 'build'
	mut maintainer := 'vaiv maintainers <vaiv@users.noreply.github.com>'
	mut dry_run := false
	args := os.args[1..]
	mut i := 0
	for i < args.len {
		a := args[i]
		match a {
			'--arch' {
				if i + 1 < args.len {
					arch = args[i + 1]
					i++
				} else {
					eprintln('build_deb: --arch needs a value')
					exit(1)
				}
			}
			'--output' {
				if i + 1 < args.len {
					output_dir = args[i + 1]
					i++
				} else {
					eprintln('build_deb: --output needs a value')
					exit(1)
				}
			}
			'--maintainer' {
				if i + 1 < args.len {
					maintainer = args[i + 1]
					i++
				} else {
					eprintln('build_deb: --maintainer needs a value')
					exit(1)
				}
			}
			'--dry-run' {
				dry_run = true
			}
			'--help', '-h' {
				usage()
				exit(0)
			}
			else {
				eprintln('build_deb: unknown flag `${a}`')
				usage()
				exit(1)
			}
		}
		i++
	}

	name := read_vmod_field('name')
	version := read_vmod_field('version')
	if name == '' || version == '' {
		eprintln('build_deb: could not read name/version from v.mod')
		exit(1)
	}

	bin_path := os.join_path(os.getwd(), 'bin', name)
	if !os.exists(bin_path) {
		v := find_v()
		println('[build_deb] building ${bin_path} with ${v}')
		if dry_run {
			println('  (dry-run) would run: ${v} -o ${bin_path} main.v')
		} else {
			code, out := sh('${v} -o ${quote(bin_path)} main.v')
			if code != 0 {
				eprintln('build_deb: build failed:\n${out}')
				exit(1)
			}
		}
	} else {
		println('[build_deb] using existing ${bin_path}')
	}

	staging := os.join_path(os.getwd(), 'build', '${name}_${version}_${arch}')
	deb_name := '${name}_${version}_${arch}.deb'
	deb_path := os.join_path(os.getwd(), output_dir, deb_name)

	if dry_run {
		println('[build_deb] (dry-run) staging -> ${staging}')
		println('[build_deb] (dry-run) would build  -> ${deb_path}')
		exit(0)
	}

	if os.exists(staging) {
		bak := staging + '.bak'
		if os.exists(bak) {
			os.rm(bak) or { eprintln('build_deb: warn: could not remove old ${bak}') }
		}
		os.mv(staging, bak) or {
			eprintln('build_deb: could not move existing ${staging} to .bak: ${err}')
			exit(1)
		}
		println('[build_deb] moved existing staging to ${bak}')
	}

	deb_dir := os.join_path(staging, 'DEBIAN')
	usr_bin := os.join_path(staging, 'usr', 'bin')
	os.mkdir_all(deb_dir) or {
		eprintln('build_deb: mkdir DEBIAN failed: ${err}')
		exit(1)
	}
	os.mkdir_all(usr_bin) or {
		eprintln('build_deb: mkdir usr/bin failed: ${err}')
		exit(1)
	}

	os.cp(bin_path, os.join_path(usr_bin, name)) or {
		eprintln('build_deb: copy binary failed: ${err}')
		exit(1)
	}

	control := 'Package: ${name}\n' + 'Version: ${version}\n' + 'Section: utils\n' + 'Priority: optional\n' + 'Architecture: ${arch}\n' + 'Maintainer: ${maintainer}\n' + 'Depends: libc6 (>= 2.31)\n' + 'Description: V-language local-first AI agent CLI\n' + ' vaiv is a local-first AI coding agent written in V. It runs single-shot\n' + ' or REPL prompts against a configurable LLM provider.\n'
	os.write_file(os.join_path(deb_dir, 'control'), control) or {
		eprintln('build_deb: write control failed: ${err}')
		exit(1)
	}

	os.mkdir_all(output_dir) or { eprintln('build_deb: warn: mkdir output failed') }
	staging_q := quote(staging)
	deb_q := quote(deb_path)
	code, out := sh('dpkg-deb --build --root-owner-group ${staging_q} ${deb_q}')
	if code != 0 {
		eprintln('build_deb: dpkg-deb failed:\n${out}')
		exit(1)
	}
	println('[build_deb] built ${deb_path}')
	println('[build_deb] verify: dpkg-deb -I ${deb_name}')
	println('[build_deb] install: sudo dpkg -i ${deb_name}')
}
