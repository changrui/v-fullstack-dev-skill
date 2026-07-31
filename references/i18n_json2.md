
# V 0.5.x — NEW modules: `json2` and `i18n`

## `vlib/json2` (canonical) — `x/json2` is now an alias
As of V 0.5.x (b07c40e), the JSON module lives at `vlib/json2`. The old
`vlib/x/json2` still exists but is now purely a compatibility shim:

```v
// vlib/x/json2/alias.v
@[alias: '@VMODROOT/vlib/json2']
module json2
```

**Rule:** write `import json2` (canonical). `import x.json2` still compiles but is
the legacy alias — prefer `json2` going forward so old skills/docs saying
"use x.json2" should be read as "use json2".

### Decode / Encode signatures (verified against ~/v/vlib/json2)
- `pub fn decode[T](val string, params DecoderOptions) !T` — generic, two-arg.
  NO one-arg `decode[T](val) ?T` form exists in 0.5.2. Call:
  `json2.decode[T](body, json2.DecoderOptions{}) !T` and unwrap with `or { }`.
- `pub fn encode[T](val T, config EncoderOptions) string` — generic, two-arg.
  NOT `json2.encode(val)` (one-arg) — that form is gone/renamed.
- Prettified output: use `EncoderOptions{prettify: true}` — there is NO standalone `encode_pretty` function.
- `pub type Any = ...` — `Any` is the dynamic JSON value type (`vlib/json2/types.v`).
  Map index returns `Any`; extract with `.str() / .f64() / .int() / .as_map() /
  .as_array()`.

### Idioms
```v
import json2

// decode typed
req := json2.decode[ChatRequest](body, json2.DecoderOptions{}) or { return err }

// decode dynamic envelope [meta, [rows...]]
arr := json2.decode[[]json2.Any](body, json2.DecoderOptions{}) or { panic(err) }
meta := arr[0].as_map()
data := arr[1].as_array()
for d in data {
    m := d.as_map()
    iso := m['countryiso3code'] or { json2.Any{} }.str()
    val := m['value'] or { json2.Any{} }.f64()
}

// build a JSON object for the OpenAI tool `parameters` field:
params := json2.decode[json2.Any]('{"type":"object","properties":{}}') or { json2.Any{} }

// encode
out := json2.encode[MyStruct](val, json2.EncoderOptions{})
```
- Map index ALWAYS needs `or { json2.Any{} }` even when sure the key exists.

## `vlib/i18n` — internationalization (NEW in 0.5.2)
Module `i18n` provides translation maps + lookup. Unlike veb's `.tr` (which needs
manual language selection), `i18n` is a plain stdlib module you call directly.

### API (verified against ~/v/vlib/i18n/i18n.v)
```v
pub const default_translations_dir = 'translations'

// Load all <lang>.json (or .tr?) translation files from ./translations/
pub fn load_tr_map() map[string]map[string]string
pub fn load_tr_map_from_dir(dir string) map[string]map[string]string

// Lookup: tr(lang, key) -> string  (returns key if missing)
pub fn tr(lang string, key string) string
pub fn tr_from_map(translations map[string]map[string]string, lang string, key string) string

// Pluralization
pub fn tr_plural(lang string, key string, amount int) string
pub fn tr_plural_from_map(translations map[string]map[string]string, lang string, key string, amount int) string
```

### Usage
```v
import i18n

fn main() {
    trs := i18n.load_tr_map()            // reads ./translations/<lang>.json
    println(i18n.tr_from_map(trs, 'en', 'welcome'))
    println(i18n.tr_from_map(trs, 'zh', 'welcome'))
    println(i18n.tr_plural_from_map(trs, 'en', 'item', 3))  // "3 items"
}
```
- Default translations directory is `translations/` (override via
  `load_tr_map_from_dir(dir)`).
- For veb web templates, you can still use the built-in `.tr` system, but wiring
  language selection is manual (a `lang` field on Context + cookie). Prefer
  `vlib/i18n` + passing resolved strings into the template as handler locals.

### Serving i18n with template variable substitution (no template engine)

When using `net.http.Server` (no veb templating), pass translated strings into HTML by
pre-processing a template with `@placeholder` markers:

```v
// In handler:
mut html := app.template_html
html = html.replace('@page_title', app.tr(lang, 'app_title'))
html = html.replace('@nav_home', app.tr(lang, 'nav_home'))
html = html.replace('@btn_search', app.tr(lang, 'search'))
// ... repeat for every dynamic placeholder
return html_response(html)
```

`i18n.tr_from_map` is the lookup helper:
```v
fn (app App) tr(lang string, key string) string {
    return i18n.tr_from_map(app.translations, lang, key)
}
```
Requires `app.translations` loaded at startup via `i18n.load_tr_map_from_dir('translations')`.

## Cross-cutting notes
- `vlib/yaml` exists — use `import yaml`, do NOT hand-roll a YAML parser.
- HTML-escape any user/LLM text before injecting into a template or SSE HTML.
