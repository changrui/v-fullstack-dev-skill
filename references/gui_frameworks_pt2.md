## gui (New Clay-based)

### Module declaration
```v
// In the app's v.mod:
module myapp

// In source files:
import gui
```

The `gui` module lives in `src/examples/gui/` within the `github.com/vlang/gui` repo.
Copy the `gui/` directory into your project's `src/` folder or import it directly.

### Core pattern: reactive view generators

```v
import gui

@[heap]
struct App {
pub mut:
    clicks int
}

fn main() {
    mut window := gui.window(
        state:   &App{}
        width:   300
        height:  300
        on_init: fn (mut w gui.Window) {
            w.update_view(main_view)
        }
    )
    window.run()
}

// View generator: called on every event
fn main_view(window &gui.Window) gui.View {
    w, h := window.window_size()
    app := window.state[App]()

    return gui.column(
        width:   w
        height:  h
        sizing:  gui.fixed_fixed
        h_align: .center
        v_align: .middle
        content: [
            gui.text(text: 'Welcome to GUI'),
            gui.button(
                id_focus: 1
                content:  [gui.text(text: '${app.clicks} Clicks')]
                on_click: fn (_ &gui.ButtonCfg, mut _ gui.Event, mut w gui.Window) {
                    mut app := w.state[App]()
                    app.clicks += 1
                }
            ),
        ]
    )
}
```

### Key concepts

1. **View → Layout → Renderer pipeline**: Views are stateless functions that return a `View` interface. The window calls the view generator on every event, producing a `Layout` tree, which is then rendered to `Renderer` draw commands.

2. **State access**: `window.state[AppType]()` returns a mutable reference to the typed state.

3. **View updates**: Call `window.update_view(view_fn)` to re-render from business logic.

4. **Thread-safe**: View updates are thread-safe via mutex in `Window`.

### Layout system

| Function | Description |
|----------|-------------|
| `gui.column(cfg)` | Top-to-bottom layout |
| `gui.row(cfg)` | Left-to-right layout |
| `gui.canvas(cfg)` | No layout (absolute positioning) |

All use `ContainerCfg`:
- `width`, `height`, `min_width`, `max_width`, `min_height`, `max_height`
- `sizing`: `fit_fit`, `fill_fill`, `fixed_fixed`, etc.
- `h_align`: `.left`, `.center`, `.right`
- `v_align`: `.top`, `.middle`, `.bottom`
- `spacing`: gap between children
- `padding`: inset padding
- `content`: `[]View`

### Sizing presets

| Constant | Meaning |
|----------|---------|
| `fit_fit` | Fit content both axes |
| `fill_fill` | Fill parent both axes |
| `fixed_fixed` | Fixed size |
| `fill_fit` | Fill width, fit height |
| `fill_fixed` | Fill width, fixed height |
| `fixed_fill` | Fixed width, fill height |

### Widgets

| Widget | Key params | Notes |
|--------|-----------|-------|
| `gui.button(cfg)` | `content: []View`, `on_click`, `id_focus`, `disabled`, `sizing`, `color`, `radius`, `padding` | Buttons can contain any views (nested content) |
| `gui.text(cfg)` | `text`, `text_style`, `wrap`, `id_focus`, `clip`, `keep_spaces` | Password mode via `is_password` |
| `gui.input(cfg)` | `text`, `placeholder`, `id_focus`, `on_text_changed`, `wrap`, `is_password`, `sizing` | Full edit: undo/redo, Ctrl+C/X/V, copy, cut, paste |
| `gui.progress_bar(cfg)` | `percent: f32` (0-1), `width`, `height`, `vertical`, `color`, `color_bar` | |
| `gui.rectangle(cfg)` | `color`, `width`, `height`, `radius`, `fill` | |
| `gui.scrollbar(cfg)` | `id_track`, `min`, `max`, `value` | |

### Dialogs

```v
// Message dialog
w.dialog(
    dialog_type: .message
    title:       'Title'
    body:        'Body text'
)

// Confirm dialog
w.dialog(
    dialog_type: .confirm
    title:       'Delete?'
    body:        'Are you sure?'
    on_ok_yes:   fn (mut w gui.Window) { /* yes */ }
    on_cancel_no: fn (mut w gui.Window) { /* no */ }
)

// Prompt dialog (with text input)
w.dialog(
    dialog_type: .prompt
    title:       'Enter name'
    body:        'Please type:'
    on_reply:    fn (reply string, mut w gui.Window) { /* ok */ }
    on_cancel_no: fn (mut w gui.Window) { /* cancel */ }
)

// Custom dialog
w.dialog(
    dialog_type: .custom
    custom_content: [
        gui.column(content: [
            gui.text(text: 'Custom UI'),
            gui.button(content: [gui.text(text: 'Close')],
                on_click: fn (_, _, mut w gui.Window) { w.dialog_dismiss() }
            ),
        ])
    ]
)

// Dismiss current dialog
w.dialog_dismiss()
```

### Theming

```v
// Built-in themes
gui.theme_dark       // default
gui.theme_light
gui.theme_dark_no_padding
gui.theme_light_no_padding

// Apply theme to window
window.set_theme(gui.theme_light)

// Custom theme via theme_maker
theme := gui.theme_maker(gui.ThemeCfg{
    name:               'my_theme'
    color_0:            gui.rgb(30, 30, 30)
    color_1:            gui.rgb(50, 50, 60)
    color_text:         gui.rgb(225, 225, 225)
    text_style:         gui.TextStyle{color: gui.rgb(225,225,225), size: 17}
})
window.set_theme(theme)
```

`Theme` struct has granular per-view-type styles:
- `button_style`, `container_style`, `dialog_style`, `input_style`, `rectangle_style`, `progress_bar_style`
- Text styles: `n1`-`n6` (normal), `b1`-`b6` (bold), `i1`-`i6` (italic), `m1`-`m6` (mono)
- Spacing: `spacing_small`, `spacing_medium`, `spacing_large`
- Padding: `padding_small`, `padding_medium`, `padding_large`, `padding_none`
- Radius: `radius_none`, `radius_small`, `radius_medium`, `radius_large`

### Colors

```v
// Named colors
gui.black, gui.white, gui.red, gui.green, gui.blue, gui.yellow, gui.orange
gui.purple, gui.pink, gui.gray, gui.dark_gray, gui.light_gray
gui.cornflower_blue, gui.dark_blue, gui.light_blue, gui.dark_red, gui.light_red

// Factory functions
gui.rgb(r, g, b)       // opaque
gui.rgba(r, g, b, a)   // with alpha
gui.hex(0xFF0000)      // from int
gui.color_from_string('#FF0000')  // from hex string or name
gui.color_from_string('red')

// Color arithmetic
c1 + c2    // add channels (max 255)
c1 - c2    // subtract channels (min 0)
c1 * c2    // multiply channels
c1 / c2    // divide channels
c1.over(c2) // Porter-Duff over blend
c1.eq(c2)  // equality
c.rgba8()  // int representation
c.to_css_string()  // "rgba(r,g,b,a)"
```

### Event handling

```v
// Global event handler on window creation
window := gui.window(
    ...
    on_event: fn (e &gui.Event, mut w gui.Window) {
        match e.typ {
            .key_down {
                if e.key_code == .escape { w.quit() }
            }
            .resized {
                println('resized to ${e.window_width}x${e.window_height}')
            }
        }
    }
)

// Per-widget callbacks
gui.button(
    on_click: fn (_ &gui.ButtonCfg, mut e gui.Event, mut w gui.Window) {
        // e has mouse position, modifiers, etc.
    }
)
```

### Event types

| Type | Description |
|------|-------------|
| `.key_down` | Key pressed |
| `.key_up` | Key released |
| `.char` | Character input |
| `.mouse_down` | Mouse button pressed |
| `.mouse_up` | Mouse button released |
| `.mouse_scroll` | Scroll wheel |
| `.mouse_move` | Mouse moved |
| `.mouse_enter` / `.mouse_leave` | Cursor entered/left window |
| `.touch_*` | Touch events (Android) |
| `.resized` | Window resized |
| `.focused` / `.unfocused` | Window focus change |
| `.quit_requested` | Window close requested |
| `.clipboard_pasted` | Pasted from clipboard |
| `.files_dropped` | Files dropped on window |

### Clipboard

```v
import gui

// Paste
text := gui.from_clipboard() or { '' }

// Copy
gui.to_clipboard('hello')
```

### Floating layouts

Views can float above the main layout (for dropdowns, menus, tooltips):
```v
gui.container(
    float:       true
    float_anchor: .middle_center   // anchor point
    float_tie_off: .middle_center  // tie-off point
    float_offset_x: 10
    float_offset_y: 0
    content: [...]
)
```

---

## Migration / Coexistence Notes

- Both frameworks use `sokol` for windowing and `gg` for drawing. They cannot coexist in the same binary easily (both define `sapp` entry points).
- `vlib/ui` depends on `clipboard` module (for webview). `gui` has built-in clipboard (`to_clipboard`/`from_clipboard`).
- `vlib/ui` supports native widgets on Windows/macOS. `gui` is pure V drawn.
- `vlib/ui` has `webview` support. `gui` does not.
- `gui` has a more modern reactive paradigm; `vlib/ui` uses imperative widget trees.

---

## Common Pitfalls

### vlib/ui
1. **Callback captures**: `on_click` callbacks receive `&ui.Button` — don't store the pointer beyond the callback.
2. **Pointer binding**: `ui.textbox(text: &app.field)` requires `app` to be a heap-allocated struct reference (`&App{}`).
3. **Platform deps**: On Linux, missing `libxi-dev`/`libxcursor-dev` causes linker errors.
4. **Pre-alpha**: API may change; check examples for current patterns.

### gui
1. **@[heap]**: App state struct must be annotated `@[heap]` to avoid stack allocation issues.
2. **View generator re-entry**: The view generator is called on EVERY event. Do not do expensive work inside it.
3. **State access**: `window.state[App]()` returns `&App` — mutation requires `mut`.
4. **id_focus**: Tab navigation requires sequential `id_focus` values on focusable widgets.
5. **Early alpha**: Fewer widgets than `vlib/ui`; no native widgets, no webview.
6. **Module import**: `gui` is NOT in `vlib/`. Copy `src/examples/gui/` into your project's `src/` or vendor it.

---

## Quick Reference: Hello World

### vlib/ui
```v
import ui

struct App { mut: window &ui.Window = unsafe { nil } }

fn main() {
    mut app := &App{}
    app.window = ui.window(
        width: 400, height: 300, title: 'Hello',
        children: [ui.label(text: 'Hello, V UI!')]
    )
    ui.run(app.window)
}
```

### gui
```v
import gui

fn main() {
    mut window := gui.window(
        width: 400, height: 300,
        on_init: fn (mut w gui.Window) { w.update_view(main_view) }
    )
    window.run()
}

fn main_view(window &gui.Window) gui.View {
    return gui.column(
        width: 400, height: 300, sizing: gui.fixed_fixed,
        h_align: .center, v_align: .middle,
        content: [gui.text(text: 'Hello, GUI!')]
    )
}
```
