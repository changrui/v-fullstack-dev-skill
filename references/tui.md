# Terminal Programming — term & term.ui

V's `term` module (at `~/v/vlib/term/`) provides building blocks for TUI apps.
For more complex apps, use `term.ui` (at `~/v/vlib/term/ui/`) which handles
events, raw input, and is more performant for large draws.

## term — low-level terminal helpers

### Colors & text styling

Functions return a string with embedded ANSI escape codes. You must pass the
result to `println` / `print` to actually display it.

```v
import term

// Basic colors (foreground)
term.black('x'), term.red('x'), term.green('x'), term.yellow('x')
term.blue('x'), term.magenta('x'), term.cyan('x'), term.white('x')

// Bright variants
term.bright_black('x'), term.bright_red('x'), term.bright_green('x'), term.bright_yellow('x')
term.bright_blue('x'), term.bright_magenta('x'), term.bright_cyan('x'), term.bright_white('x')

// Background colors
term.bg_black('x'), term.bg_red('x'), term.bg_green('x'), term.bg_yellow('x')
term.bg_blue('x'), term.bg_magenta('x'), term.bg_cyan('x'), term.bg_white('x')

// Text styles
term.bold('x'), term.dim('x'), term.italic('x'), term.underline('x')
term.slow_blink('x'), term.inverse('x'), term.hidden('x'), term.strikethrough('x')
term.reset('x')

// RGB colors (24-bit)
term.rgb(r, g, b, 'x')      // foreground
term.bg_rgb(r, g, b, 'x')   // background
term.hex(0xff0000, 'x')     // foreground from hex int
term.bg_hex(0xff0000, 'x')  // background from hex int

// Convenience messages
term.ok_message('success')    // green
term.fail_message('error')    // bold white on red
term.warn_message('warning')  // bright yellow
term.highlight_command('v run main.v')  // bright white on cyan

// Compose styles: nest calls freely
term.bold(term.red('FAILED'))
term.underline(term.bright_green('OK'))

// ColorConfig (structured) — write to strings.Builder
mut sb := strings.new_builder(100)
term.writeln_color(mut sb, 'hello', fg: .red, bg: .cyan, styles: [.bold])
// or custom ANSI code: term.writeln_color(mut sb, 'x', custom: '38;5;214')
```

### Enum types (for ColorConfig)

```v
import term

// Styles
term.TextStyle.bold, .dim, .italic, .underline, .blink, .reverse

// Foreground colors
term.FgColor.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white

// Background colors
term.BgColor.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white
```

### Cursor & screen control

```v
import term

// Terminal size
cols, rows := term.get_terminal_size()
// returns (default_columns_size, default_rows_size) if no TTY

// Cursor positioning (uses Coord struct)
term.set_cursor_position(x: 10, y: 5)
pos := term.get_cursor_position()!  // returns !Coord (Result)
// pos.x, pos.y

// Relative cursor movement
term.cursor_up(1)
term.cursor_down(1)
term.cursor_forward(2)
term.cursor_back(2)

// Show/hide cursor
term.hide_cursor()
term.show_cursor()

// Erase
term.erase_clear()              // clear entire screen + cursor to top-left
term.erase_display('0')         // cursor to end
term.erase_display('1')         // cursor to beginning
term.erase_display('2')         // entire screen
term.erase_display('3')         // entire screen + scrollback
term.erase_line('0')            // cursor to end of line
term.erase_line('2')            // entire line
term.erase_toend()              // alias for erase_display('0')
term.erase_line_toend()         // alias for erase_line('0')
term.clear_previous_line()      // \r + up 1 + erase line (good for progress bars)
term.clear()                    // clear screen (returns bool)

// Title
term.set_terminal_title('My App')  // returns bool
term.set_tab_title('Tab Name')     // returns bool (Konsole tabs)

// Support detection
term.can_show_color_on_stdout() bool
term.can_show_color_on_stderr() bool
term.supports_sixel() bool         // returns bool (checks terminal capability)
```

### Layout helpers

```v
import term

// Horizontal divider (fills terminal width)
term.h_divider('-')
term.h_divider('==')

// Header with title
term.header('TITLE', '=')       // centered: ===== TITLE =====
term.header_left('LEFT', '-')   // left-aligned: --- LEFT -----------
```

### ANSI stripping

```v
import term
plain := term.strip_ansi('\x1b[31mred\x1b[0m')  // 'red'
```

### Input helpers (Unix only)

```v
import term

// Single key press (non-blocking by default)
ch := term.key_pressed(term.KeyPressedParams{blocking: false})
// returns i64: -1 = no key, otherwise the character code

// With echo enabled
ch := term.key_pressed(term.KeyPressedParams{blocking: true, echo: true})

// Enable/disable terminal echo
term.enable_echo(false)   // for password prompts
term.enable_echo(true)

// UTF-8 character
rune := term.utf8_getchar()  // ?rune (Option)
```

## term.ui — event-driven TUI framework

### Quickstart pattern

```v
import term.ui as tui

struct App {
mut:
    tui &tui.Context = unsafe { nil }
}

// Event handler — called for every terminal event
fn event(e &tui.Event, x voidptr) {
    if e.typ == .key_down && e.code == .escape {
        exit(0)
    }
}

// Frame handler — called at frame_rate (default 30 fps)
fn frame(x voidptr) {
    mut app := unsafe { &App(x) }

    app.tui.clear()
    app.tui.set_bg_color(r: 63, g: 81, b: 181)  // Material Dark Blue
    app.tui.draw_rect(20, 6, 60, 14)
    app.tui.set_color(r: 255, g: 255, b: 255)
    app.tui.draw_text(24, 8, 'Hello from V!')
    app.tui.set_cursor_position(0, 0)

    app.tui.reset()
    app.tui.flush()
}

fn main() {
    mut app := &App{}
    app.tui = tui.init(
        user_data:   app
        event_fn:    event
        frame_fn:    frame
        hide_cursor: true
    )
    app.tui.run()!
}
```

### Config fields (all optional)

```v
mut ctx := tui.Config{
    user_data:        app_ptr
    init_fn:          fn(voidptr)    // called after init, before first event/frame
    frame_fn:         fn(voidptr)    // called at frame_rate fps
    event_fn:         fn(&Event, voidptr)
    cleanup_fn:       fn(voidptr)    // called once before exit
    fail_fn:          fn(string)     // called on fatal init error
    buffer_size:      256            // internal read buffer
    frame_rate:       30             // frames per second
    hide_cursor:      false
    capture_events:   false          // raw mode: intercept ctrl+c, ctrl+z
    mouse_enabled:    false          // enable mouse tracking
    use_alternate_buffer: true       // switch to alt screen buffer
    window_title:     ''             // terminal window title
    skip_init_checks: false          // skip TTY/feature detection
    reset:            [...]          // kill signals for cleanup
}
```

### Event types and fields

```v
import term.ui as tui

// EventType enum
.tui.EventType.unknown
.tui.EventType.mouse_down, .mouse_up, .mouse_move, .mouse_drag, .mouse_scroll
.tui.EventType.key_down, .key_up
.tui.EventType.resized

// Event struct
pub struct Event {
pub:
    typ   EventType
    x     int           // mouse x
    y     int           // mouse y
    button MouseButton  // .unknown, .left, .middle, .right
    direction Direction   // .unknown, .up, .down, .left, .right
    code  KeyCode       // key code (see below)
    modifiers Modifiers // .ctrl, .shift, .alt (bitmask)
    ascii u8            // ASCII codepoint
    utf8  string         // UTF-8 text
    width  int          // for .resized events
    height int
}

// KeyCode — printable characters use ASCII values
.tui.KeyCode._0.._9, .a.._z, .enter, .escape, .tab, .space, .backspace
.tui.KeyCode.up, .down, .right, .left, .home, .end, .insert, .delete
.tui.KeyCode.page_up, .page_down
.tui.KeyCode.f1..f24
.tui.KeyCode.exclamation, .double_quote, .hashtag, .dollar, .percent, ...

// Modifiers (bitmask enum)
[tui.Modifiers.ctrl, .shift, .alt]  // use | to combine: .ctrl | .shift

// Direction (mouse scroll)
.tui.Direction.up, .down
```

