# go2v — Go→V 自动转译器实测（2026-07-16）

官方工具 github.com/vlang/go2v。本会话实测它对 covonaut/fuzzy/fuzzy.go (169 行)
的转译质量 + 完整安装/调用流程。结论：它是「初稿生成器」，不是「翻译器」。

## 安装（已实测，含踩坑）
go2v 本身是 **V 程序**，但运行时依赖 Go 工具 `asty` 把 Go 源转成 AST JSON。
环境需要：`go` (≥1.20) 在 PATH，且 V 在 `~/v`。

```bash
# 1. 克隆
git clone --depth 1 https://github.com/vlang/go2v /tmp/go2v
cd /tmp/go2v

# 2. 编译 go2v（需要 go 在场，它会在首次运行时装 asty）
~/v/v .            # 产出二进制 ./go2v（2.6MB）

# 3. 首次运行会自动 `go install github.com/asty-org/asty@latest`
#    ⚠️ 默认 GOPROXY 会超时！必须用 direct：
export PATH=$PATH:/home/iqdo/go/bin
timeout 110 env GOPROXY=direct GONOSUMDB=* \
  go install github.com/asty-org/asty@latest
# 成功后 /home/iqdo/go/bin/asty 存在；之后 go2v 即可离线运行
```

## 调用（关键：传文件路径，不是目录！）
```bash
# ✅ 正确：传 .go 文件路径 → 在同目录生成 <同名>.v
./go2v /path/to/fuzzy.go
#   输出: /path/to/fuzzy.v  （已写出，可直接 v run 验证）

# ❌ 错误：传目录 → go2v 进入 test 对比模式，要求 <dir>/<name>.vv 预期文件
./go2v /path/to/dir/
#   报: Failed to read expected V code: .../<name>.vv
```
准备输入：把目标 .go 放进一个目录（go2v 吃目录里的内容，但参数是文件路径）：
```bash
mkdir -p /tmp/g2v_test/fuzzy && cp fuzzy.go /tmp/g2v_test/fuzzy/
/tmp/go2v/go2v /tmp/g2v_test/fuzzy/fuzzy.go   # → /tmp/g2v_test/fuzzy/fuzzy.v
```

## 转译质量（实测 fuzzy 样本，169 行 → 163 行）
**做对的部分（省键盘，约 20–30% 时间）：**
- `strings.new_builder` / `unicode.is_space` 识别正确
- `s.index(sub) or { -1 }` 正确转成 V option 语法（不用手改）
- `for r in s` 直接迭代 rune（比手写 `s.runes()` 更简洁）
- 多返回值函数签名 `(i64,i64,bool)` 正确
- `return i64(idx)` 类型转换正确

**生成的真实编译错误（必须人工修——6 类，约 7% 行）：**
1. `strings.Builder.grow(s.len)` → V 无此方法 → `strings.new_builder(s.len)` 预分配
2. `line.trim_right_func(unicode.is_space)` → V 无此 API → `line.trim_right(' \t')`
3. `orig_r.str()\n.len` → 换行把 `.len` 拆断（parser 生成 bug）→ 合并成 `orig_r.str().len`
4. `prev, curr = curr, prev` → V 禁止数组直接 swap → `mut t := prev.clone(); prev = curr.clone(); curr = t`
5. `original.runes` 缺括号 → `original.runes()`
6. `content.replace(a,b,1)` → V replace 仅 2 参数 → `find`+切片（见 go_to_v_porting.md diff #3）

## 量化结论
- 纯算法模块：go2v 生成骨架 + option/迭代转换省心，人工修正 6 类标准库映射差异
- 对 **context.Context / any / 泛型 / select** 等语义难点：go2v 按字面直转，**零特殊处理**
  → 这些人工成本一分没少
- **定位**：对「叶子/纯逻辑模块」提速明显；对「context/any 重度的核心」仅省语法键盘时间，
  不改工作量量级。配合 go_to_v_porting.md 的 7 个系统差异 + 结构缺口一起用。

## 验证命令
```bash
cd /tmp/g2v_test/fuzzy
mkdir -p /tmp/demo/fuzzy && cp fuzzy.v /tmp/demo/fuzzy/
# main.v: import fuzzy; println(fuzzy.levenshtein_distance('kitten','sitting'))
cd /tmp/demo && ~/v/v -prod run .    # 修正 6 类错误后应输出 3（编辑距离）
```
