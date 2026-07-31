<!--
v-gui-reference  v1.0  2026-07-18
Two official V GUI frameworks: vlib/ui (legacy Sokol-based) and gui (new Clay-based).
This skill covers both. Use vlib/ui for mature, production-ready apps;
use gui for modern reactive/declarative UI.
-->

# V GUI Frameworks Reference

## Overview: Two Official GUI Libraries

V has **two** official GUI frameworks, both cross-platform (Linux/macOS/Windows/Android):

| Feature | `vlib/ui` (legacy) | `gui` (new) |
|---------|-------------------|-------------|
| Repository | `github.com/vlang/ui` (submodule of `vlib/ui`) | `github.com/vlang/gui` |
| Rendering | Immediate mode via Sokol (`gg`) | Immediate mode via Sokol (`gg`) |
| Paradigm | Declarative, stateful widgets | Declarative, reactive view generators |
| Layout | Explicit containers (row/column/box/canvas) | Flexbox-style Clay algorithm |
| Maturity | Pre-alpha but widely used; many examples | Early alpha; fewer examples |
| Theming | Per-widget style params | Granular `Theme` with `theme_maker` |
| Native widgets | Yes on Windows/macOS | No (pure V drawn) |
| Webview | Built-in (`ui.webview`) | No |
| Modal dialogs | `ui.dialog()` | `window.dialog()` (message/confirm/prompt/custom) |
| State management | Mutable app struct | `window.state[T]()` typed access |
| View model | Widget tree built in `main()` | View generator called on every event |

### When to use which

- **`vlib/ui`**: You need a mature library with many widgets (checkbox, radio, dropdown, listbox, slider, progressbar, textbox, button, label, picture, canvas, grid, menu, subwindow, tray, switch, accordion, filebrowser, colorpalette), webview embedding, native widgets on Windows/macOS, and extensive examples (CRUD app, calculator, 7GUIs). API is stable-ish but labeled pre-alpha.
- **`gui`**: You prefer a modern reactive paradigm (view = function(state)), Clay-style flexbox layout, composable buttons-with-nested-content, and granular theming. Fewer widgets but extensible. Still early alpha.

---

## vlib/ui (Legacy Sokol-based)

### Module declaration
```v
// In the app's v.mod:
module myapp

// In source files:
import ui
```

The `ui` module is bundled with the V compiler at `vlib/ui/`. No `v install` needed.

### Core pattern: declarative widget tree

```v
import ui

struct App {
mut:
    window     &ui.Window = unsafe { nil }
    first_name string
    last_name  string
}

fn main() {
    mut app := &App{}
    app.window = ui.window(
        width:  600
        height: 400
        title:  'V UI Demo'
        children: [
            ui.row(
                margin: ui.Margin{10, 10, 10, 10}
                children: [
                    ui.column(
                        width: 200
                        spacing: 13
                        children: [
                            ui.textbox(
                                max_len:  20
                                width:    200
                                placeholder: 'First name'
                                text:      &app.first_name
                            ),
                            ui.textbox(
                                max_len:  50
                                width:    200
                                placeholder: 'Last name'
                                text:      &app.last_name
                            ),
                        ]
                    ),
                ]
            ),
        ]
    )
    ui.run(app.window)
}
```

### Layout containers

| Container | Description | Key params |
|-----------|-------------|------------|
| `ui.column` | Vertical stacking | `width`, `spacing`, `children` |
| `ui.row` | Horizontal stacking | `height`, `spacing`, `children` |
| `ui.box_layout` | Absolute positioning | `width`, `height`, `children` |
| `ui.canvas_layout` | Overlay + absolute | `width`, `height`, `children`, `top_layer` |
| `ui.group` | Grouped widgets with border+title | `title`, `children` |

### Core widgets

| Widget | Purpose | Key params |
|--------|---------|------------|
| `ui.button` | Clickable button | `text`, `width`, `on_click: fn(&ui.Button)`, `tooltip`, `radius` |
| `ui.textbox` | Text input | `text: &string`, `placeholder`, `max_len`, `mode: .multiline|.read_only`, `is_password`, `is_numeric`, `on_change`, `on_enter` |
| `ui.label` | Static text | `text`, `width`, `text_size`, `text_color` |
| `ui.checkbox` | Boolean toggle | `checked: bool`, `text`, `on_click: fn(&ui.CheckBox)` |
| `ui.radio` | Single-select group | `values: []string`, `title`, `on_click: fn(&ui.Radio)` |
| `ui.dropdown` | Select one from list | `values: []string`, `selected_index`, `on_selection_changed` |
| `ui.listbox` | Multi-item list | `items: map[string]string`, `on_change`, `multi`, `scrollview` |
| `ui.slider` | Range selector | `min`, `max`, `val`, `orientation`, `on_value_changed` |
| `ui.progressbar` | Progress indicator | `min`, `max`, `val`, `color`, `bg_color` |
| `ui.picture` | Image display | `path: string`, `width`, `height` |
| `ui.rectangle` | Colored rectangle | `color`, `width`, `height`, `radius`, `border` |
| `ui.canvas` | Custom drawing | `width`, `height`, `draw_fn: fn(&gg.Context, &ui.Canvas)` |
| `ui.subwindow` | Child window | `parent`, `width`, `height`, `title`, `children` |
| `ui.menu` / `ui.menuitem` | Menus | `text`, `action: fn(&ui.MenuItem)` |
| `ui.switch` | Toggle switch | `on`, `on_toggle: fn(&ui.Switch)` |

### Components (`uic` submodule)

Higher-level components:
- `uic.accordion_stack` / `uic.accordion_component`
- `uic.filebrowser_stack` / `uic.filebrowser_component`
- `uic.colorpalette_stack` / `uic.colorpalette_component`
- `uic.tab_stack` / `uic.tab_component`

Pattern: factory function creates root layout; companion function retrieves state struct.

### Window management

```v
// Create window
window := ui.window(width: 800, height: 600, title: 'App', children: [...])

// Run event loop
ui.run(window)

// Modal dialog
ui.dialog(window, 'Title', 'Body text', .message)
ui.dialog(window, 'Confirm?', '', .confirm) {
    // callback on yes/no
}

// Resize window
window.resize(new_width, new_height)

// Set title
window.set_title('New Title')

// Close window
window.close()
```

### Event callbacks

Most widgets accept function callbacks:
```v
ui.button(
    text: 'Click me'
    on_click: fn (btn &ui.Button) {
        println('clicked!')
    }
)
```

### Drawing with `gg`

The `gg` (graphics) context is available in `ui.canvas`:
```v
ui.canvas(
    width: 400
    height: 300
    draw_fn: fn (mut ctx gg.Context, canvas &ui.Canvas) {
        ctx.draw_circle(100, 100, 50, gx.blue)
        ctx.draw_text(200, 100, 'Hello', gx.white)
    }
)
```

### Webview

```v
import ui

window := ui.window(
    width:  800
    height: 600
    children: [
        ui.webview(url: 'https://example.com')
    ]
)
ui.run(window)
```

### Platform dependencies (Linux)

```bash
# Arch: sudo pacman -S libxi libxcursor mesa
# Debian/Ubuntu: sudo apt install libxi-dev libxcursor-dev mesa-common-dev
# Fedora: sudo dnf install libXi-devel libXcursor-devel mesa-libGL-devel
```

---

