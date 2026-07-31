### Drawing API (Context methods)

```v
// Buffer accumulation — all drawing goes to an internal buffer
// until flush() is called.

// Colors
app.tui.set_color(r: 255, g: 0, b: 0)        // foreground RGB
app.tui.set_bg_color(r: 0, g: 0, b: 0)       // background RGB
app.tui.reset_color()                         // restore default FG
app.tui.reset_bg_color()                      // restore default BG
app.tui.reset()                               // reset all formatting

// Cursor
app.tui.set_cursor_position(x, y)             // 0-indexed
app.tui.show_cursor()
app.tui.hide_cursor()

// Clearing
app.tui.clear()                               // erase entire terminal

// Text & drawing primitives
app.tui.draw_text(x, y, 'hello')              // string at position
app.tui.draw_point(x, y)                      // single character cell
app.tui.draw_line(x1, y1, x2, y2)             // Bresenham line
app.tui.draw_dashed_line(x1, y1, x2, y2)      // dashed Bresenham
app.tui.draw_rect(x1, y1, x2, y2)             // filled rectangle
app.tui.draw_empty_rect(x1, y1, x2, y2)       // outline rectangle
app.tui.draw_empty_dashed_rect(x1, y1, x2, y2)// dashed outline
app.tui.horizontal_separator(y)               // full-width '-' line

// Advanced
app.tui.bold()                                // set bold attribute
app.tui.set_window_title('My App')            // terminal window title

// Flush — render accumulated buffer to screen
app.tui.flush()
```

### Terminal capabilities (auto-detected)

```v
// Context fields set during init:
ctx.enable_rgb                // 24-bit truecolor supported
ctx.enable_ansi256            // ANSI 256-color supported
ctx.supports_alternate_buffer // alt-screen buffer supported
ctx.supports_sgr_mouse        // SGR mouse tracking supported
ctx.supports_sync_updates     // synchronized updates (no tearing)
ctx.window_width, ctx.window_height  // current terminal size

// Resize events are emitted automatically when the terminal is resized
// (SIGWINCH is caught and forwarded as .resized event).
```

### Platform notes

- **Linux/macOS:** Uses termios raw mode for event capture. Tested with
  gnome-terminal, konsole, Terminal.app, iTerm2.
- **Windows:** Uses Win32 Console API (consoleapi_windows.c.v). Different
  input handling path.
- **`$if unix` / `$if windows`:** Use compile-time conditionals for platform
  specific code.
- **`$if windows { ... } $else { ... }`** for cross-platform modules.

### Known limitations

- `key_up` events are only available on Windows and terminals supporting the
  kitty keyboard protocol. Legacy terminals only emit `key_down`.
- Screen tearing can occur on large draws — use synchronized updates (enabled
  by default if the terminal supports it).
- The `x11` backend is not yet implemented (errors with a message).
- Feature detection can be skipped with `skip_init_checks: true` (risky —
  colors/mouse may not work).

## termios — low-level terminal configuration (Unix only)

```v
import term.termios

// Termios struct — represents terminal state
t := termios.Termios{}
termios.tcgetattr(0, mut t)      // get current state
termios.tcsetattr(0, C.TCSANOW, mut t)  // apply immediately

// Common flags (C.* constants from termios.h)
C.ICANON    // canonical (line-buffered) mode
C.ECHO      // echo input characters
C.VTIME     // read timeout (centiseconds)
C.VMIN      // minimum characters for read

// Helper functions
termios.flag(int(C.ECHO))        // convert int to TcFlag
termios.invert(termios.flag(C.ECHO))  // bitwise NOT for TcFlag
t.disable_echo()                 // disable ECHO in-place
```

## Common patterns

### Password prompt (hidden input)

```v
import term
import term.termios

fn read_password(prompt string) string {
    print(prompt)
    term.enable_echo(false)
    defer { term.enable_echo(true) }

    mut buf := ''
    for {
        ch := term.key_pressed(term.KeyPressedParams{blocking: true, echo: false})
        if ch == 10 || ch == 13 { break }  // Enter
        if ch == 127 || ch == 8 {           // Backspace
            if buf.len > 0 { buf = buf[..buf.len-1] }
        } else if ch > 31 {
            buf << u8(int(ch))
        }
    }
    println('')
    return buf
}
```

### Progress bar

```v
import term

fn progress_bar(current int, total int, width int = 40) {
    pct := current * 100 / total
    filled := current * width / total
    bar := '[' + '='.repeat(filled) + ' '.repeat(width - filled) + ']'
    line := '\r${bar} ${pct}% (${current}/${total})'
    print(line)
    if current == total { println('') }
}
```

### Colored output with graceful fallback

```v
import term

// Safe colored output — returns plain text when colors unsupported
fn colored_error(msg string) string {
    term.fail_message(msg)  // bold white on red, or plain msg
}

fn colored_success(msg string) string {
    term.ok_message(msg)    // green, or plain msg
}

// Custom color via closure
term.colorize(term.yellow, 'warning')
term.ecolorize(term.bright_red, 'error on stderr')
```

### Alternating screen buffer (full-screen app)

```v
// The ui module does this automatically with `use_alternate_buffer: true`
// (the default). It switches to the alt buffer on init and restores
// the main buffer on exit/cleanup.

// Manual approach:
print('\x1b[?1049h')   // switch to alt buffer
// ... your app ...
print('\x1b[?1049l')   // restore main buffer
```

### Sixel graphics (image display in terminal)

```v
import term

if term.supports_sixel() {
    // Terminal supports Sixel — can display images
    // Send Sixel escape sequences to draw raster images
    num_colors := term.graphics_num_colors()
    println('Sixel supported, ${num_colors} color registers')
} else {
    println('Sixel not supported')
}
```

## Workflow tips

- `import term` for simple colored output and cursor control.
- `import term.ui as tui` for full event-driven TUI apps.
- Always call `flush()` after drawing operations to render the buffer.
- Use `set_cursor_position` before `draw_text` — text is placed at the cursor.
- `draw_text` does NOT auto-advance the cursor to the next line — use `println`
  or `set_cursor_position` manually.
- The `Context` struct holds a `print_buf []u8` internally — all drawing methods
  write to this buffer, and `flush()` sends it to stdout in one write.
- For cross-platform code, use `$if windows` / `$if unix` conditionals.
- The `term.ui` module is a submodule of `term` — import as `import term.ui`.
