# V 0.5.x 测试框架 — testing.md

V 内置测试框架，无需外部测试库。约定驱动：文件名以 `_test.v` 结尾，函数以 `test_` 前缀开头。

---

## 1. 测试文件与函数命名

```v
// 文件名：calculator_test.v
// 注意：文件名必须以 _test.v 结尾

fn test_add() {
    assert add(1, 2) == 3
}

fn test_subtract_with_t(t &testing.T) {
    t.assert(add(5, -3) == 2)
    t.eq(add(5, -3), 2)  // t.eq 提供更好的错误信息
}
```

### `testing.T` 核心方法

| 方法 | 用途 |
|------|------|
| `t.assert(cond)` | 断言条件为真 |
| `t.eq(a, b)` | 断言 a == b |
| `t.ne(a, b)` | 断言 a != b |
| `t.ok(val)` | 断言 val 不为空/非零 |
| `t.fail()` | 直接标记失败 |
| `t.skip()` | 跳过当前测试 |

---

## 2. `assert` 表达式

```v
// 基础断言
assert result == expected

// 断言失败时附带消息
assert result == expected, 'result should be ${expected}, got ${result}'

// 复杂断言
assert arr.len > 0
assert arr.contains('key')
assert response.status_code == 200
```

**`assert` 在测试文件外也可使用**，但在非测试代码中失败时会触发 `panic`。测试上下文中失败会优雅报告。

---

## 3. 表驱动测试

```v
fn test_parse_int() {
    tests := [
        { input: '42',  expected: 42 },
        { input: '-1',  expected: -1 },
        { input: '0',   expected: 0  },
        { input: 'abc', expected: 0  }, // 期望解析失败返回 0
    ]
    for test in tests {
        result := parse_int(test.input) or { 0 }
        assert result == test.expected, 'parse_int(${test.input}) = ${result}, want ${test.expected}'
    }
}

// 带命名的表驱动测试
struct CalcTestCase {
    a        int
    b        int
    expected int
    name     string
}

fn test_calc_multiply() {
    cases := [
        CalcTestCase{ 2, 3, 6, 'positive'     },
        CalcTestCase{ -2, 3, -6, 'neg_x_pos'   },
        CalcTestCase{ 0, 5, 0, 'zero'           },
    ]
    for tc in cases {
        assert multiply(tc.a, tc.b) == tc.expected, '${tc.name}: multiply(${tc.a}, ${tc.b}) failed'
    }
}
```

---

## 4. 测试 Fixture 与临时目录

```v
fn setup_temp_dir() string {
    dir := os.join_path(os.temp_dir(), 'v_test_${time.now().unix}')
    os.mkdir_all(dir) or { panic(err) }
    return dir
}

fn test_with_file() {
    dir := setup_temp_dir()
    defer { os.rmdir_all(dir) or {} }

    path := os.join_path(dir, 'test.txt')
    os.write_file(path, 'hello') or { panic(err) }

    content := os.read_file(path) or { panic(err) }
    assert content == 'hello'
}
```

### SQLite 测试隔离

```v
module mydb

fn test_insert_and_query() {
    // 每个测试函数使用独用的临时数据库
    db_path := os.join_path(os.temp_dir(), 'test_${time.now().unix_milli}.db')
    mut db := sqlite.connect(db_path) or { panic(err) }
    defer { db.close() os.rm(db_path) or {} }

    db.exec('CREATE TABLE items (id TEXT PRIMARY KEY, name TEXT)') or { panic(err) }

    db.exec("INSERT INTO items (id, name) VALUES ('1', 'test')") or { panic(err) }

    result := db.exec("SELECT name FROM items WHERE id = '1'") or { panic(err) }
    assert result.len > 0
}
```

---

## 5. `v test` 命令

```v
// 运行当前目录所有测试
v test .

// 运行单个测试文件
v test calculator_test.v

// 静默模式（只显示失败）
v -silent test .

// 输出统计
v test . -stats

// 递归测试所有子目录
v test ./...

// 运行指定名称的测试（过滤）
v test . -- -run TestName
```

### 测试输出解读

```
$ v test .
testing test_calculator   ✓   0.001s
testing test_parser       ✓   0.002s
testing test_validator    ✗   0.001s
------------------------------
  FAIL  total: 3  passed: 2  failed: 1
```

---

## 6. 测试辅助函数

```v
// helper_test.v — 被多个测试文件共享

module mymodule

fn create_test_user(id string) User {
    return User{
        id:   id
        name: 'test_user_${id}'
    }
}

fn assert_user_eq(got User, expected User) {
    assert got.id == expected.id, 'id mismatch'
    assert got.name == expected.name, 'name mismatch'
}

// 非 test_ 前缀的函数不会被自动运行
fn cleanup_temp(dir string) {
    os.rmdir_all(dir) or {}
}
```

```v
// 在 user_test.v 中使用辅助函数
import mymodule

fn test_user_creation() {
    user := create_test_user('42')
    assert_user_eq(user, User{ id: '42', name: 'test_user_42' })
}
```

---

## 7. Benchmark（基准测试）

```v
fn bench_compute(b &testing.B) {
    // 准备数据
    data := prepare_large_data()

    b.reset_timer() // 排除准备工作计时

    for _ in 0 .. b.iterations() {
        result := compute(data)
        assert result > 0 // 防止编译器优化掉调用
    }
}

// 可选：手动设置迭代次数
fn bench_small(b &testing.B) {
    b.set_iterations(100000)
    for _ in 0 .. b.iterations() {
        fast_function()
    }
}
```

运行基准测试：

```v
// 运行所有 benchmark
v bench .

// 运行特定 benchmark
v bench . -- -run bench_compute
```

---

## 8. 常见陷阱

### 陷阱 1：测试函数签名错误

```v
// ❌ 错误 — 测试函数只能无参或仅一个 &testing.T 参数
fn test_bad(x int) {
}

// ✅ 正确
fn test_good() {}
fn test_good_t(t &testing.T) {}
```

### 陷阱 2：依赖测试执行顺序

```v
// ❌ 危险 — V 不保证测试执行顺序
mut global_state := 0
fn test_one() { global_state = 1 }
fn test_two() { assert global_state == 1 } // 可能先于 test_one 执行

// ✅ 正确 — 每个测试自包含
fn test_one() { assert setup_and_check() }
fn test_two() { assert setup_and_check() }
```

### 陷阱 3：`v vet` 对测试文件的影响

`v vet` 也会检查测试文件。所有 `pub fn` 仍需要 doc comment。测试函数本身不需要 `pub`。

### 陷阱 4：测试中的 `or { panic(err) }`

```v
// ✅ 在测试中直接 panic 是可以接受的，会报告失败
data := os.read_file('testdata/input.txt') or { panic(err) }
```

### 陷阱 5：忘记 rebuild

测试是编译后执行的。修改了被测试代码后没有重新 `v test .`，仍然运行的是旧二进制。养成修改后立即运行的习惯，或使用 `v watch test .`。
