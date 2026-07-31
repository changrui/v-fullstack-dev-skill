# REPL line editor + arrow-key command history in V 0.5.x (from scratch)

V 0.5.x stdlib has **no readline / getch / raw terminal API** that survives a
from-scratch REPL. `os.input_opt()` is line-buffered (arrows come through as
literal `^[[A` garbage) and `term.ui` is a full alternate-buffer TUI framework
that fights a `println`-based output model. To get Up/Down history browse + line
editing you must hand-roll it on `term.termios` + `os.fd_read`. This is the
working recipe (built and PTY-tested on vaiv).

## What exists in the stdlib

- `term.termios` (linux): `Termios` struct (`c_iflag/c_oflag/c_cflag/c_lflag/
  c_cc[cclen]`), `tcgetattr(fd, mut t) int`, `tcsetattr(fd, actions, mut t) int`.
  The `C.*` termios constants ARE reachable from `term.termios` (e.g. `C.ECHO`,
  `C.ICANON`, `C.IEXTEN`, `C.ISIG`, `C.OPOST`, `C.ICRNL`, `C.IXON`, `C.BRKINT`,
  `C.INPCK`, `C.ISTRIP`, `C.CS8`, `C.VMIN`, `C.VTIME`, `C.TCSANOW`). No
  `cfmakeraw` wrapper — build raw mode by hand.
- `os.fd_read(fd, maxbytes) (string, int)` — single raw byte read from stdin
  (fd 0). Loop it to assemble keystrokes.
- UTF-8 decode/encode: hand-roll (see pitfalls). `s.bytestr()` converts `[]u8→string`.

## Raw mode setup (cfmakeraw equivalent)

```v
import term.termios
import os

mut t := termios.Termios{}
if termios.tcgetattr(0, mut t) != 0 {
    return os.input_opt(prompt) or { '' }   // NOT a tty → graceful fallback
}
orig := t
t.c_iflag &= termios.invert(C.ICRNL | C.IXON | C.BRKINT | C.INPCK | C.ISTRIP)
t.c_oflag &= termios.invert(C.OPOST)
t.c_cflag |= termios.flag(C.CS8)
t.c_lflag &= termios.invert(C.ECHO | C.ICANON | C.IEXTEN | C.ISIG)
t.c_cc[C.VMIN] = 1
t.c_cc[C.VTIME] = 0
if termios.tcsetattr(0, C.TCSANOW, mut t) != 0 {
    return os.input_opt(prompt) or { '' }
}
defer { mut o := orig; termios.tcsetattr(0, C.TCSANOW, mut o) }  // ALWAYS restore
```

## Read loop skeleton

- Read one byte via `os.fd_read(0, 1)`; `n <= 0` ⇒ EOF (Ctrl-D) ⇒ exit REPL.
- `27` (ESC) → read next bytes to classify: `[A`=up, `[B`=down, `[C`=right,
  `[D`=left, `[H` or `[1~`=home, `[F` or `[4~`=end, `[3~`=delete. (Read until
  `126`/`~` for the `~`-terminated ones; `[1~`/`[4~` need a small loop.)
- Control chars `< 32`: `3`=Ctrl-C (clear line, stay in loop), `4`=Ctrl-D (EOF→
  exit), `21`=Ctrl-U (clear), `1`=Ctrl-A (home), `5`=Ctrl-E (end), `11`=Ctrl-K
  (kill to end), `10`/`13`=Enter (commit).
- Printable / UTF-8 continuation bytes: accumulate into a `[]u8` buffer; when a
  complete rune is assembled, insert it at the cursor.

## Line redraw (must clear-and-repaint; no incremental writes)

```v
redraw := fn (prompt string, line string, cursor int) {
    print('\r\x1b[K${prompt}${line}')   // \r + erase-to-EOL, then repaint
    if cursor < line.len {
        back := line.len - cursor
        if back > 0 { print('\x1b[${back}D') }   // move cursor back
    }
    os.flush()                                       // v has NO flush() on print
}
```

## Persistence-backed history (cap + dedupe)

- Store in `data/history/<session>.txt` (anchor via `agent.project_root()` +
  `'data'`, NOT the bare project root — sessions/telemetry live under `data/`
  too, and forgetting `data/` writes to the wrong place). One command per line.
- Load on REPL start; `add(cmd)` on each committed command.
- Adjacent-dedup: if `items.last() == cmd` skip. Enforce cap (e.g. 20) from the
  front: `items = items[items.len-cap..]`.
- Up/Down walk an `items` index; on browse, replace `line` with the history
  entry and move `cursor` to `line.len`. Past the end ⇒ empty line.

## V 0.5.x pitfalls specific to raw-mode REPLs (hit while building this)

- **`string` is NOT a `mut` arg.** A fn that edits a string must return
  `(new_string, new_cursor)` — e.g. `fn insert_rune(s string, pos int, ch int)
  (string, int)`. Same for reassigning a string inside a loop body: the loop
  variable must be `mut` (`mut p := pos+1; for p < ... { p++ }`).
- **`os.flush_stdout()` does NOT exist** — use `os.flush()` after `print`.
- **`[]u8.bytes_to_string()` does NOT exist** — use `buf.bytestr()`.
- **`string.find(s)` does NOT exist** — use `s.index(s) ?int` (handle the `?`).
- **UTF-8 rune assembly:** decode manually — `first := int(buf[0])`;
  `need = 1` if `<0x80`, `2` if `&0xE0==0xC0`, `3` if `&0xF0==0xE0`, `4` if
  `&0xF8==0xF0`; when `buf.len >= need`, combine bytes with the standard
  masks. Encode back with the inverse shifts (and `&0x3F`/`0x80` continuations).
  Chinese IME composition does NOT work in raw mode — users must paste or type
  ASCII / `!` / `/` commands. English-command REPLs are the sweet spot.
- **A stray `fn main()` probe file in the project root breaks `v .`** (multiple
  main modules). Delete any `*.v` scratch probes before building; build with
  `v -o bin/x .`.
- **Graceful degradation is mandatory:** if `tcgetattr(0)` returns non-zero
  (piped input, CI, the single-shot `vaiv "prompt"` path), fall back to
  `os.input_opt`. This keeps non-interactive use and unit tests working.

## Verification

- PTY test: `timeout 8 script -qfc "./bin/vaiv" /dev/null <<EOF` feeding
  commands + `$(printf '\033[A')` (Up arrow) proves browse + redraw + re-exec.
- Non-tty: `printf 'cmd\n/history\nexit\n' | ./bin/vaiv` proves fallback +
  persistence + dedupe (no raw mode involved).
- `v fmt -w . && v vet . && v -o bin/vaiv .` must stay clean (no `#[0m` stray
  bytes — write ANSI as `'\x1b[...m'`, never literal pasted escapes that can
  corrupt the source; a stray `b[0m'` line appended to a `write_file` is a
  real failure mode — re-save via `write_file` after removing it).
