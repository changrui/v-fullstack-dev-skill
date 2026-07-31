# OWID Web App — veb + MySQL Pitfalls (Session 2026-07-26)

## Topic pages show "暂无数据" — root causes found

### Problem
Topic pages showed blank "该主题暂无数据" even though DB had ~191k data points.

### Root Causes
1. **Wrong JOIN column**: SQL used `dp.entity_code` but `data_points` table has NO `entity_code`. FK is `dp.entity_id` (UUID varchar(36)) linking to `entities.id`.
2. **MySQL `ONLY_FULL_GROUP_BY`**: SELECT included `e.code, e.name` not in GROUP BY → query rejected with code 1055. Fix: add `e.code, e.name` to GROUP BY.
3. **SQL injection**: Original handler concatenated user data into raw SQL strings. Changed to `exec_param_many`.

### Correct Query Pattern for Topic Indicators
```v
// Step 1: Get indicators for this topic
ind_rows := db.exec_param_many(
    'SELECT id, slug, name, description, unit, source, sort_order FROM indicators WHERE topic_id = ? ORDER BY sort_order ASC, name ASC',
    [topic.id]
) or { return topic, [] }

// Step 2: For each indicator, get latest data point
for row in ind_rows {
    dr := db.exec_param_many(
        "SELECT dp.entity_id, COALESCE(e.name, ''), dp.year_value, dp.value "+
        "FROM data_points dp LEFT JOIN entities e ON e.id = dp.entity_id "+
        "WHERE dp.indicator_id = ? ORDER BY dp.year_value DESC LIMIT 1",
        [row.vals[0]]
    ) or { continue }
}
```

### Veb Template Variables
- `$veb.html()` reads from the **handler's local scope**, NOT App struct fields.
- Handler must declare ALL template vars as locals: `title := app.home_data.title`, `indicators := handlers.get_all_indicators(app.db)`
- The `data.html` template uses `@for i, ind in indicators` — handler MUST have a local named exactly `indicators`.

### `v_stable_sort` Segfault
V 0.5.x can segfault at runtime when map iteration contains unused variables or complex closure patterns.
Fix: remove unused map vars like `entity_names`, keep map operations simple.

### CSS One-Page Homepage
Reduce hero padding, stat card sizes, font sizes; use Bootstrap `min-vh-100`, `flex-grow-1`, `mt-auto` utilities on body wrapper to fit content in one viewport.