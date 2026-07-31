# V 0.5.x MySQL C Driver — Buffer Corruption Bug

## The Bug

`db.exec_param_many()` returns `[]Row` where each `Row.vals[i]` is a `mystring` — a V wrapper around a **shared C string pointer** to the MySQL C library's internal result buffer.

When you iterate over rows AND then call `exec_param_many` AGAIN inside the loop (the classic N+1 query pattern), the MySQL C library's result buffer gets **overwritten** on each new query. By the time you access `row.vals[N]` in later iterations, earlier rows' data may be corrupted.

## Symptoms

1. First row of result prints correctly; second row crashes or returns garbage.
2. `v_stable_sort` segfault during iteration — V tries to sort/copy corrupted string pointers.
3. `println('hello $var')` sometimes outputs `$var` literally instead of value (printf parser conflict with `$` in interpolated string).
4. Database definitely has data, but handler returns empty arrays.

## The Fix — Snapshot Pattern

**Before iterating:** Copy all `Row.vals[i]` values into native V structs (heap-allocated strings):

```v
// Define snapshot struct (module-level, not inside function)
pub struct IndicatorSnapshot {
pub:
    id string
    slug string
    name string
    description string
    unit string
    source string
    sort_order int
}

// Query indicators
ind_rows := db.exec_param_many(
    'SELECT id, slug, name, description, unit, source, sort_order FROM indicators WHERE topic_id = ? ORDER BY name',
    [topic_id]
) or { return ... }

// ⚠️ IMMEDIATELY snapshot before any nested query
mut snapshots := []IndicatorSnapshot{}
for ir in ind_rows {
    snapshots << IndicatorSnapshot{
        id: ir.vals[0],
        slug: if ir.vals.len > 1 { ir.vals[1] } else { '' },
        name: if ir.vals.len > 2 { ir.vals[2] } else { '' },
        // ... copy ALL fields needed later
    }
}

// NOW safe to do N+1 queries per snapshot
mut results := []ResultType{}
for snap in snapshots {
    dr := db.exec_param_many('SELECT ... WHERE indicator_id = ?', [snap.id]) or { continue }
    // snap fields are V strings — safe from buffer corruption
    results << build_result(snap, dr)
}
```

## Why This Works

Converting `mystring` → `string` (V native string) creates an independent heap copy. Subsequent `exec_param_many` calls overwrite the C buffer, but our V strings are untouched.

## Checklist

When working with `db.mysql`:
- [ ] Any nested/sequential DB queries after reading rows? → Snapshot first.
- [ ] Using `println` with `$var` in loops? → Use explicit `print` + `println(val.str())`.
- [ ] String interpolation `${expr}` with complex expressions? → Use `'${(expr)}'` with parentheses.
- [ ] `string.int()` or `string.f64()` returns plain type — NO `or {}` blocks.

## References

- V mysql.c.v source: `exec_param_many` → `exec_param_many_result` → prepared statement execute.
- MySQL C API: `mysql_store_result` returns a `MYSQL_RES*` with internal buffers shared across calls.
