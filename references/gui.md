
# V GUI Frameworks (v-gui) — reference

V's two official GUI frameworks. Full API in `references/gui_frameworks.md`.

## Quick decision: which framework?

| Factor | `vlib/ui` | `gui` |
|--------|-----------|-------|
| Maturity | Pre-alpha but widely used; many examples | Early alpha; fewer examples |
| Paradigm | Declarative widget tree (imperative build) | Reactive view generators (view = fn(state)) |
| Layout | Explicit containers (row/column/box/canvas) | Flexbox via Clay algorithm |
| Widget count | 20+ widgets + 4+ uic components | 6 widgets (button, text, input, progress, rectangle, scrollbar) |
| Native widgets | Yes on Windows/macOS | No (pure V drawn) |
| Webview | Built-in (`ui.webview`) | Not yet |
| Theming | Per-widget params | Granular `Theme` struct + `theme_maker` |
| State mgmt | Mutable app struct with pointer refs | `window.state[T]()` typed access |
| Best for | Feature-rich apps, CRUD, webview embedding | Modern reactive UI, simple apps, learning |

## Core patterns

### vlib/ui — Declarative widget tree
```v
import ui

struct App { mut: window &ui.Window = unsafe { nil } }

fn main() {
    mut app := &App{}
    app.window = ui.window(
        width: 600, height: 400, title: 'Demo',
        children: [
            ui.column(children: [
                ui.textbox(text: &app.name, placeholder: 'Name'),
                ui.button(text: 'Submit', on_click: submit_click),
            ])
        ]
    )
    ui.run(app.window)
}
```
- App state must be heap-allocated (`&App{}`) — pointers bind to widget callbacks.
- `on_click` callbacks receive `&ui.Button` — don't store the pointer beyond the cb.
- Platform deps on Linux: `libxi-dev libxcursor-dev mesa-common-dev`.

### gui — Reactive view generator
```v
import gui

@[heap]
struct App { pub mut: clicks int }

fn main() {
    mut window := gui.window(
        state: &App{}, width: 400, height: 300,
        on_init: fn (mut w gui.Window) { w.update_view(main_view) }
    )
    window.run()
}

fn main_view(window &gui.Window) gui.View {
    app := window.state[App]()
    return gui.column(
        width: 400, height: 300, sizing: gui.fixed_fixed,
        h_align: .center, v_align: .middle,
        content: [
            gui.text(text: '${app.clicks} Clicks'),
            gui.button(
                content: [gui.text(text: 'Increment')],
                on_click: fn (_ &gui.ButtonCfg, mut _ gui.Event, mut w gui.Window) {
                    mut app := w.state[App]()
                    app.clicks += 1
                }
            ),
        ]
    )
}
```
- App struct MUST be `@[heap]` — stack allocation causes corruption.
- View generator is called on EVERY event — keep it fast (no heavy I/O).
- `window.state[T]()` returns `&T` — mutation requires `mut`.
- Tab navigation needs sequential `id_focus` values on focusable widgets.
- `gui` module is NOT in `vlib/` — copy `src/examples/gui/` into your project's `src/`.

## Pitfalls
- **Both frameworks use `sokol`** for windowing — they cannot coexist in the same
  binary (both define `sapp` entry points). Pick one.
- **vlib/ui `text` widget** uses `ui.textbox(text: &app.field)` — the pointer MUST
  point to a field in a heap-allocated struct, not a local variable.
- **gui view generator re-entry** — runs on every mouse move; expensive ops inside
  cause lag. Cache layout computations.
- **gui `@[heap]` missing** — without it, state struct is stack-allocated and
  corrupted when accessed from callbacks.
- **gui module import** — `gui` is not bundled. Vendor the `gui/` directory into
  your project's `src/` folder; it does NOT come with `vlib/`.
