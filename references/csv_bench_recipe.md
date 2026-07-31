# Recipe: large typed CSV + worker/batch benchmark sweep (V 0.5.2)

Reusable technique from the `csv2mysql` project — generating a multi-GB typed
CSV and sweeping `workers x batch_size` to tune a parallel CSV to DB importer.

## 1. Generate a large typed CSV

Write directly with `os.create` + `f.writeln` (streaming; no in-memory buffer).
Keep it deterministic (a tiny LCG) so runs are reproducible.

Schema for >=30 typed columns, cycling the required types:
`int, int, float, float, datetime, datetime, date, date, bool, bool, string...`
(balance low-cardinality strings vs "messy" strings that contain a comma AND a
double-quote, to exercise the quote-aware parser).

**CSV quoting rule (critical):** any field containing the separator or a quote
must be wrapped in `"..."` and inner `"` doubled to `""`. Example field:
`"text value 1 with, comma and ""quote"" and x980"`. Without this, the importer
mis-splits the row. (This is exactly what bit the medium-tier chunk test — once
a quoted field spans a chunk boundary the importer must stay quote-aware.)

Size math: ~30 cols x ~15 B/field approx 450 B/row + newline. For ~2 GB target
approx 4.5e6 rows. `f64(os.file_size(p)) / (1024*1024)` to report MB after
writing. Note `f64(r % 100000) / 100.0` prints full float precision
(`11262.714285714286`) — fine for type inference, but if you want tidy widths
use a fixed formatter.

## 2. Worker/batch sweep harness

Put it as a SEPARATE `module main` in `tools/` (NOT next to `main.v` — two
`module main` files break `v .`). Run with `v run tools/bench_matrix.v file.csv`.

Pattern:
- Force the tier you want to tune. For a >2 GB file `tier_for_size` routes to
  `large`; worker/batch only affect the PARALLEL (`medium`) path, so force
  `opt.tier = .medium` to actually exercise the worker pool.
- Sweep `workers := [1, 4, 8, 16, 0(auto)]` x `batch := [500, 2000, 5000, 10000]`.
- Each combo -> distinct table (`matrix_${w}_${b}`), `truncate`+`create_table`,
  then `csv2mysql.dispatch(cfg, opt, path)`.
- Time with `time.new_stopwatch()` + `sw.elapsed().milliseconds()` (NOT
  `time.now().unix` — that field is private; see pitfalls reference).
- Print a plain-text table (`rows`, `ms`, `rows/s`, `note`) + fastest combo.
- Add a `--quick` flag that generates a ~2e5-row temp file and runs a 2x2
  matrix, so the harness is verifiable fast before the big run.

## 3. Definitive correctness gate

After importing under every strategy, assert each table's `COUNT(*)` equals
`wc -l file - 1` (header). If tiers disagree (small=100000, medium=101096,
large=100001) the importer is wrong, not the data — bisect as in the
"Correctness & deadlock debugging playbook" section of `v_05x_compile_pitfalls.md`.

## 4. Caveats for THIS project

- `small` (single-threaded, all-in-memory) tier is genuinely slow on 1e5+ rows;
  size the dataset to fit the timeout, or test `small` only on modest files.
- `csv2mysql import` / `bench` / `selftest` hit live MySQL (DROP/CREATE/INSERT) —
  treat as destructive; run only with explicit user go-ahead.
