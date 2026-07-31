# V 0.5.x json2/yaml Generic Inference Bug

> Created 2026-07-24 from actual V 0.5.2 (b07c40e) testing.

## The Bug

`json2.decode<T>(text)!` and `yaml.decode<T>(text)` where T is a **user-defined struct** compile but silently fail — the compiler reports `"expression evaluated but not used"`. The Result value is dropped, `T` defaults to empty/uninitialized, and no compile-time error occurs.

This also affects `yaml.decode<User>(text)!` — same symptom, different error message (`"User must be initialized"`).

## Confirmed Workarounds

### 1. json2 → Use json2.Any + ValueKind matching

```v
import json2

any_val := json2.decode[json2.Any]('{"x": 42, "y": 3.14}')!
match any_val {
    json2.Number { println(any_val.f64()) }
    json2.String { println(any_val.str()) }
    else { println(any_val) }
}
```

### 2. yaml → Use parse_text + doc.decode[T]()

```v
import yaml

struct User { name string; age int }

doc := yaml.parse_text("name: Alice\nage: 30")!
user := doc.decode<User>()!     // ← This works reliably
println(user.name)
```

### 3. Manual parsing for simple cases

Construct structs field-by-field after extracting raw data.

## Root Cause

V 0.5.2 generic function type inference has a known issue where decoder functions (`decode[T](string) !T`) fail to properly infer T when the assignment target is complex (user-defined struct), especially when combined with `!` Result unwrapping.

## References

- Both `vlib/json2` and `x/json2` affected equally
- `yaml` module uses `json2` internally for decode, so inherits same limitation
- Affects all JSON/YAML decoding into custom structs via generic syntax