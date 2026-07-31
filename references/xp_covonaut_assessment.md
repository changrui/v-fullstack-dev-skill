# Covonaut → V 移植评估（实测数据，2026-07-16）

covonaut = github.com/covoyage/covonaut（"Production-ready Agent framework for Go"）。
本会话做了完整的「能否翻译为 V」评估。这是 **"某个 Go 项目要不要移植到 V"** 类问题
的可复用方法论 + 实测样例。完整产物在 `/home/iqdo/covonaut/V_PORT_PLAN.md`。

## 实测基础数据（covonaut 本身）
- 93,205 行 Go（测试 28,106 / 非测试 65,099），20 子模块，320 个 .go 文件
- go.mod：仅 1 个外部依赖 `gorilla/websocket v1.5.3` → V 标准库有对等 `net.websocket`，
  意味着「零外部依赖」对 V 比 Go 还干净
- V 环境：V 0.5.2（~/v），已实测 fuzzy 模块直译编译 -prod 通过

## 各模块非测试 LOC + 难点热点（决定翻译难度）
| 模块 | LOC | CTX | ANY | JSON | SELECT | 难度 |
|------|-----|-----|-----|------|---------|------|
| tui | 18402 | 18 | 42 | 2 | 35 | 高(终端UI重写) |
| tools | 15422 | 225 | 352 | 60 | 7 | 高(any/schema) |
| agentcore | 7815 | 330 | 245 | 14 | 18 | 高(context) |
| provider | 3212 | 44 | 101 | 21 | 13 | 中高 |
| mcp | 3313 | 224 | 291 | 20 | 26 | 高(context/select) |
| a2a | 4248 | 134 | 44 | 50 | 18 | 中高(websocket) |
| server | 1647 | 34 | 66 | 14 | 9 | 中 |
| a2ui/agui | 1684/1207 | 0/3 | 146/101 | 50/4 | 0/0 | 中(数据/绑定) |
| graph | 1645 | 103 | 31 | 3 | 0 | 中(context) |
| session | 1653 | 46 | 5 | 23 | 0 | 中(JSON存) |
| acp | 1766 | 9 | 28 | 18 | 2 | 中 |
| 叶子(零内部依赖)：fuzzy/pkg/components/prompt/store/workflow/skill/filequeue | ~1100 | 0 | 0 | 0 | 0 | 极低(可立即平移) |

CTX=context.* 引用数；ANY=`any` 关键字；JSON=json.(Un|M)arshal；SELECT=`select {`

## 全仓库 Go→V 难点热点（行级命中）
- `context.Context` **783** 处、`any` **1511** 处、`json.Marshal/Unmarshal` 492 处、
  `defer` 699 处、`select{}` **130** 处 — 这些是直译最大阻力点

## 三类难度分级（实测后判定）
- **A 直接直译(<10% 改动)**：fuzzy(已验证)、pkg、components、prompt、store、filequeue、skill、workflow
- **B 直译+局部重写(20–40%)**：graph、session、provider、tools、mcp、a2ui、agui、server、acp
- **C 必须大幅重写(>60%)**：agentcore(330 CTX+245 any)、tools(352 any)、mcp(224 CTX+26 select)、a2a(websocket)、tui(18k 终端引擎)

## 工作量估算（人·天，乐观/现实/保守）
- 全量 1:1 直译：~120 / ~220 / ~350（且不解决长期双份维护 Go 分叉成本）
- **V 原生重写核心(推荐)**：chat loop + tool calling + memory + provider + 少量 tools + planner
  ≈ 3k–5k 行 V，现实 ~15–25 人·天，拿到可用框架
- 微服务桥接：0 移植，1–2 天接 HTTP 客户端

## 方法论（复用给任何 Go→V 评估）
1. `git ls-files` + `wc -l` 拿 LOC；`go.mod` 看外部依赖（V 能否替代）
2. `grep -rc` 统计 CTX/any/select/defer/json/net.http/reflect 热点 → 定难度档
3. 画内部 import 图，找零依赖叶子模块（可立即平移）
4. **先实译一个最小纯算法模块**（如 fuzzy）验证编译链路 + 量化坑密度
5. 再看 go2v 对叶子模块的转译质量（见 references/go2v_tool.md）
6. 给三档分类 + 工作量，推荐「原生重写核心」而非全量直译

## 关键定性结论（可复用）
- Go→V 比大多数语言互译更顺（并发模型/错误处理/语法 V 借鉴 Go），但 **82k 行 1:1 直译不划算**
- 架构核心（chat loop + tool calling + memory + planner）很小，用 V 原生重写约 2k–5k 行即可
- 叶子模块用 go2v + 少量修补可立即平移成 V 基础件
