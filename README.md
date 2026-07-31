# V Fullstack Dev Skill

> V 0.5.x 全栈开发技能包 — 面向 Hermes Agent 的 V 语言开发参考知识库

## 概述

本仓库是 Hermes Agent 的 `v-fullstack-dev` 技能文件集合，提供 V 语言 0.5.x 全栈开发的完整参考指南。

涵盖范围：
- **语法陷阱** — mutability、`!`/`?` 类型、切片、vet 规则
- **Web 开发** — veb 框架、路由、模板、静态文件、SSE
- **数据库** — db.sqlite ORM 模式、测试隔离、最佳实践
- **JSON/HTTP** — json2 解析、net.http 使用、i18n 国际化
- **并发编程** — go/chan/select、闭包陷阱、Mutex 同步
- **C FFI** — mmap、SIMD、动态链接
- **终端/GUI** — term/term.ui、ui/gui 框架
- **AI 集成** — OpenAI 兼容 LLM 接口、SSE 流式响应
- **Go→V 移植** — go2v 工具使用与陷阱

## 环境要求

- V 编译器：`~/v` (路径可能因安装而异)
- 版本：0.5.2 (b07c40e) 或更高
- 系统：Linux/WSL（Windows 下 veb 有已知限制）

## 文件结构

```
v-fullstack-dev/
├── SKILL.md              # 技能入口文件（Hermes Agent 加载）
├── AGENTS.md             # 工作区指令文件
├── LICENSE               # MIT 许可证
├── README.md             # 本文件
├── references/           # 主题参考文档
│   ├── syntax.md         # 语法陷阱
│   ├── web_veb.md        # veb Web 框架
│   ├── db_orm.md         # SQLite ORM
│   ├── json_http.md      # JSON/HTTP
│   ├── openai_llm.md     # OpenAI LLM 集成
│   ├── c_ffi.md          # C FFI 接口
│   └── ...
├── templates/            # 代码模板
│   ├── veb_app.v         # Web 应用模板
│   ├── cli_app.v         # CLI 应用模板
│   ├── rest_handler.v    # REST API 处理器
│   ├── sqlite_store.v    # SQLite 存储模板
│   └── openai_agent.v    # AI Agent 模板
└── scripts/              # 辅助脚本
```

## 快速开始

### 首次使用

1. 阅读 `references/syntax.md` — 避免编译/运行时错误的核心指南
2. Web 应用：阅读 `references/web_veb.md` + 使用 `templates/veb_app.v`
3. 数据库：阅读 `references/db_orm.md` + 使用 `templates/sqlite_store.v`
4. JSON/HTTP：阅读 `references/json_http.md` + `references/i18n_json2.md`

### 质量门禁

```bash
~/v/v fmt -w . && ~/v/v vet . && ~/v/v -silent test .
```

### 模块检查

```bash
~/v/v -check .
```

## 关键注意事项

### Windows + veb 限制
Windows 环境下 veb 0.5.2 存在编译期崩溃（`expression has no value`）。建议使用 `net.http.Server` + `Handler` 接口作为替代。

### 类型系统
- `!T` = Result（错误类型）
- `?T` = Option（可选类型）
- map 索引返回 `!T`，需用 `or {}` 解包

### 模块命名
- 避免与标准库冲突：`db` → `dbase`
- 短模块名，不含项目前缀

## 许可证

MIT License — 见 [LICENSE](LICENSE)

## 贡献

欢迎提交 Issue 和 Pull Request。请先阅读现有文档确认是否重复，并遵循 V 语言代码规范。

## 相关链接

- [V 语言官网](https://vlang.io)
- [V 编译器仓库](https://github.com/vlang/v)
- [Hermes Agent 文档](https://hermes-agent.nousresearch.com/docs)
