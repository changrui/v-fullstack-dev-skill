# Building a Debian (.deb) package from a V project (self-contained, no fpm)

Extracted from vaiv's `scripts/build_deb.vsh` (Phase 21 follow-up). Use this
when you need to ship a V binary as a `.deb` without installing Ruby/fpm.

## What a .deb actually is
An `ar` archive with three members:
- `debian-binary` — the format version (`2.0`).
- `control.tar.gz` — package metadata: at minimum a `control` file (and
  optionally `postinst`/`prerm` maintainer scripts).
- `data.tar.gz` — the actual file tree to install (e.g. `./usr/bin/vaiv`).

`dpkg-deb` builds all three from a **staging directory** you lay out on disk.

## The staging tree
```
vaiv_0.7.2_amd64/
├── DEBIAN/
│   └── control          # required metadata
└── usr/
    └── bin/
        └── vaiv         # the binary, mode 0755
```
Convention: `<name>_<version>_<arch>/`. `dpkg-deb --build --root-owner-group
<staging>` sets all file owners to `root:root` (needed so the package installs
cleanly on the target even if you built it as a normal user).

## Minimal control file
```
Package: vaiv
Version: 0.7.2
Section: utils
Priority: optional
Architecture: amd64
Maintainer: vaiv maintainers <vaiv@users.noreply.github.com>
Depends: libc6 (>= 2.31)
Description: V-language local-first AI agent CLI
 vaiv is a local-first AI coding agent written in V. ...
```
Notes:
- `Architecture` is `amd64`/`arm64`/etc. Query at build time with `--arch`.
- For a **dynamically linked** V binary (`ldd bin/vaiv` shows libm/libc/libmvec),
  `Depends: libc6 (>= 2.31)` is sufficient on any modern Debian/Ubuntu. If you
  statically link, drop `Depends` (or keep `libc6` harmlessly).
- Ship ONLY the binary. Runtime data (`data/`, `~/.vaiv`, config) is created on
  first run — do NOT bundle it.
- Long `Description` lines: the first line is the synopsis; continuation lines
  must be indented by ONE space.

## Build command
```
dpkg-deb --build --root-owner-group vaiv_0.7.2_amd64 vaiv_0.7.2_amd64.deb
```
Verify before installing:
```
dpkg-deb -I vaiv_0.7.2_amd64.deb     # show control metadata
dpkg-deb -c vaiv_0.7.2_amd64.deb     # list files that will be installed
sudo dpkg -i vaiv_0.7.2_amd64.deb    # install
```

## V 0.5.2 / vsh pitfalls when writing the builder script
The builder is a `vsh` script (`v run scripts/build_deb.vsh`) — it has a
NARROWER stdlib scope than a normal `module agent`:
- **`shell_quote` is NOT available** in vsh → define a local
  `fn quote(s string) string { return "'" + s.replace("'", "'\\''") + "'" }`.
- **`os.read_file` returns `!string`** → `os.read_file(p) or { return '' }`.
- **`string.trim(' \t')` errors** in vsh ("trim() returns 0 values") → use
  `line.trim_space()` / `line.trim_space().trim('\'"')`.
- **`code, out := sh(...)` cannot be re-declared with `:=` at the same fn scope
  twice** (nested-block first decl is OK; two flat-level `:=` error). Reuse with
  `code, out =` or distinct names.
- **`os.exec` returns `os.Result` (no `or{}`)**; no `<<` chaining (two statements).
- `os.cp` / `os.rm` / `os.mkdir_all` return `!` → need `or {}`.
- Read name+version from `v.mod` with a tiny `for line in content.split('\n')`
  parser (the `key: 'value'` lines); `content := os.read_file('v.mod') or {…}`.

## Safety convention (vaiv project)
Existing staging trees are renamed to `.bak` (never deleted) before rebuild,
matching the project's "never delete" rule. Output goes to `build/` (git-ignored
so the artifact never enters version control). Add `build/` to `.gitignore`.

## Copy-modify template
`templates/build_deb.vsh` is a known-good, self-contained builder. Copy it,
adjust `Maintainer`/`Depends`/`Description`, and run
`v run scripts/build_deb.vsh`. Supports `--arch / --output / --maintainer /
--dry-run / --help`.
