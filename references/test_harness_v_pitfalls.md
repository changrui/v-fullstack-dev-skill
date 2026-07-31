# V 0.5.x Test Harness Pitfalls — execute_code + V compiler cache

> Created 2026-07-24. Lessons from extensively testing V stdlib APIs via Hermes execute_code.

## The Problem

When using `execute_code` to verify V code snippets, **stale `.v` files from prior tests in the same directory corrupt compilation**. This caused several FALSE POSITIVE "bugs" during this session:

1. **`yaml.decode[User](text)!`** — appeared broken ("User must be initialized"), actually works ✅
2. **`json2.decode[Data](text)!`** — appeared broken ("expression evaluated but not used"), actually works ✅  
3. **`'123'.int()`** — appeared broken (claimed void return), actually returns 123 ✅

All three were fixed by writing a SINGLE `main.v` in a CLEAN temp directory.

## Root Cause

V's compiler, when invoked as `v run /tmp/d`, compiles ALL `.v` files in that directory. If multiple test files exist from previous iterations:
- Stale module definitions can shadow/redefine symbols
- Cache files persist across invocations
- The compiler silently drops or mis-routes generic type parameters
- Error messages become misleading ("expression evaluated but not used")

## Correct Pattern

```python
import os, subprocess

d = '/tmp/v_test_clean_' + str(hash(__name__) % 100000)  # unique per call
os.makedirs(d, exist_ok=True)

# STEP 1: Clear all existing .v files from directory
for f2 in os.listdir(d):
    if f2.endswith('.v'):
        try: os.unlink(os.path.join(d, f2))
        except: pass

# STEP 2: Write EXACTLY ONE main.v
with open(os.path.join(d, 'main.v'), 'w') as f:
    f.write('''module main
import json2

struct Data { x int; y f64 }

fn main() {
    data := json2.decode[Data]('{\"x\": 42} ')!
    println(data.x)  # prints 42
}
''')

# STEP 3: Run with clean dir
result = subprocess.run(
    ['/home/iqdo/v/v', 'run', d],
    capture_output=True, text=True, timeout=15
)
```

## Key Rules

1. **Clean before write**: Always `os.listdir(d)` and delete any `.v` files first
2. **One file per test**: Only `main.v` in the directory
3. **Unique dirs**: Each test needs a fresh directory name (hash-based)
4. **Module declaration**: Use `module main` not the default filename-based module
5. **No import loops**: Don't have multiple `.v` files importing each other in tests

## Verification Checklist for Future V Tests

Before declaring something "broken":
- [ ] Is there only one `.v` file in the test directory?
- [ ] Was the directory cleaned before writing?
- [ ] Did I use `module main`?
- [ ] Does the error go away in a completely new dir?

If uncertain, re-test in `/tmp/v_verify_clean_N`.