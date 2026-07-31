# World Bank API JSON envelope — verified decode recipe (V 0.5.1, x.json2)

## Endpoint shape
World Bank v2 JSON wraps every response in a 2-element array:
`[ { "page":1, "pages":N, "per_page":.., "total":.. }, [ ...rows... ] ]`

For `/country/CHN;USA/indicator/NY.GDP.MKTP.CD?format=json&per_page=10000&page=K`:
- element 0 = pager metadata (object)
- element 1 = array of data rows (objects)

## Decode
```v
import x.json2

arr := json2.decode[[]json2.Any](body, json2.DecoderOptions{}) or { return error('decode: ${err}') }
if arr.len < 2 { return error('unexpected envelope') }
pager := arr[0].as_map()
total_pages := pager['pages'] or { json2.Any{} }.int()
data := arr[1].as_array()
```

## Row fields (indicator data)
```v
for d in data {
    m := d.as_map()
    iso3 := m['countryiso3code'] or { json2.Any{} }.str()
    date := m['date'] or { json2.Any{} }.str()        // year as string e.g. "2024"
    val_any := m['value'] or { json2.Any{} }
    has := val_any.json_str() != 'null' && val_any.json_str() != ''
    val := if has { val_any.f64() } else { 0.0 }
}
```

## Country row fields
`id`, `iso2Code`, `name`, `region` (object → `.value`), `incomeLevel` (object → `.value`),
`capitalCity`, `longitude`, `latitude` (all strings/numbers via `.str()`/`.f64()`).

## Indicator meta row
`id`, `name`, `unit`, `source` (object → `.value`), `sourceNote`.

## Pagination loop (auto-walk all pages)
```v
mut page := 1
for {
    url := '...&page=${page}'
    body := http.get(url) or { return err }
    arr := json2.decode[[]json2.Any](body, json2.DecoderOptions{}) or { ... }
    // ... collect arr[1].as_array() ...
    if page >= total_pages || total_pages == 0 { break }
    page++
}
```
Note: `per_page=10000` means most single indicators fit in one page for <=50 countries.

## Why `x.json2` instead of stdlib `json`

- `x.json2` is **slower** than stdlib `json` (it builds a generic `Any` tree), but it
  parses **arbitrary** JSON without a pre-declared struct. Fields that are missing,
  null, or of varying type are handled with `or { json2.Any{} }` + type probes
  (`str()`/`f64()`/`int()`/`as_map()`/`as_array()`). This is far more robust for
  APIs like World Bank where nested objects (`region.value`), optional scalars,
  and `null` values are common.
- stdlib `json.decode(&T, s)` requires an **exact** struct. A single missing or
  mistyped field aborts the whole decode. For WB `[meta, data]` envelopes (a
  2-element top-level array of heterogeneous types) it is awkward to express.
- **Rule of thumb:** use `x.json2` when the schema is loose / you must be defensive;
  use stdlib `json` only when you control the exact shape and want speed.

## Performance note
`json2.decode` allocates a node per JSON value. For very large responses (e.g.
`per_page=10000` across many pages) it is measurably slower than `json`. The
robustness trade-off is worth it for one-off API ingestion; if you sync the same
response millions of times, pre-define a struct and use stdlib `json` instead.
