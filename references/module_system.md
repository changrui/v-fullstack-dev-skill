# V 0.5.x 模块系统与发布 — module_system.md

V 的模块系统以目录结构和 `v.mod` 清单文件为基础。理解模块解析规则、命名约定和发布机制对组织全栈项目至关重要。

---

## 1. `v.mod` 清单文件

每个 V 项目根目录必须有一个 `v.mod` 文件。

```v
Module {
    name:        'myproject'
    description: 'A web API for ...'
    version:     '0.1.0'
    license:     'MIT'
    dependencies: []
}
```

### 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 模块名称，也是导入路径的根。使用纯小写，不用项目名前缀。 |
| `description` | 否 | 简短描述。 |
| `version` | 否 | 语义化版本。 |
| `license` | 否 | SPDX 许可证标识符。 |
| `dependencies` | 否 | 依赖列表（当前仅 `v install` 使用）。 |

### `v.mod` 搜索规则

V 编译器从当前目录向上遍历父目录搜索 `v.mod`，找到的第一个 `v.mod` 所在目录被视为项目根（`@VMODROOT`）。

```v
// 在代码中使用 @VMODROOT 访问项目根路径
// 例如加载模板文件：
fn load_template() string {
    return os.read_file('@VMODROOT/templates/page.html') or { panic(err) }
}
```

---

## 2. 模块命名与目录结构

### 目录即模块

V 中 **一个目录就是一个模块**。目录中的 `module xxx` 声明定义了模块名。

```v
// 目录结构：
// myproject/
// ├── v.mod
// ├── main.v           (module main)
// ├── handler/
// │   └── user.v       (module handler)
// └── internal/
//     └── db/
//         └── sqlite.v (module db)

// 导入方式：
import handler
import internal.db
```

### 命名规则

- 模块名使用小写 + 下划线（如 `worldbank`、`telemetry_store`）
- 目录名与模块名必须匹配（`worldbank/` → `module worldbank`）
- 子模块用点号（`.`）分隔导入路径：`import internal.worldbank`
- **禁止**：`module cmd.agent`（点号在 module 声明中非法）
- `main` 模块的文件放在项目根，不做子目录

### 导入方式

```v
// 正确：点号作为路径分隔符
import os
import db.sqlite
import internal.worldbank
import handler

// 错误：使用斜杠
// import internal/db    // ❌ 编译错误
```

---

## 3. 单文件 vs 模块模式

### 单文件模式

```v
// 直接运行单个文件
v run main.v

// 文件内容无需 module 声明
```

### 模块模式（推荐）

```v
// 从包含 v.mod 的目录运行
v run .

// 此时 V 编译整个目录下的所有 .v 文件
// 模块内的所有文件共享 module 命名空间
```

### 同名函数问题

同一模块下**不能**在不同文件中定义同名函数：

```v
// handler/user.v
fn parse_role(s string) Role { ... }

// handler/admin.v
fn parse_role(s string) Role { ... } // ❌ 重复定义
```

解决方法：要么重名函数只在同一个文件中定义，要么提取为不同模块。

---

## 4. 内部导入限制

V 没有像 Go 那样的 `internal/` 包访问限制机制。`internal/` 目录仅作为约定使用：

```v
// 所有模块都可以互相导入，无论目录位置
import internal.db
import internal.worldbank
```

**约定：** 以 `internal/` 开头的模块表示非公开 API，项目外不应直接依赖。

---

## 5. 依赖管理

### 声明依赖

```v
// v.mod
Module {
    name: 'myapp'
    dependencies: [
        'https://github.com/user/library'
    ]
}
```

### `v install`

```v
// 安装所有依赖
v install

// 安装特定模块
v install https://github.com/user/library

// 已安装模块放在 ~/.vmodules/ 目录下
```

### 离线依赖处理

当前 V 0.5.x 的依赖管理仍在发展中。对于模块引用路径不生效的情形：

```v
// 备选：将依赖源码直接复制到项目 vendor/ 目录
// 然后使用相对导入
// 或复制到 ~/.vmodules/<module-name>/ 目录
```

---

## 6. 模块发布

### 发布到 V 模块注册表

```v
// 1. 确保 v.mod 信息完整
// 2. 创建 Git tag
git tag v0.1.0
git push --tags

// 3. 发布（当前仅限官方注册表）
// v publish  // 功能在 0.5.2 中有限支持
```

### 私有模块

对于没有公开注册的模块，推荐以下方式：

```v
// 方式 1：通过 @VMODROOT 相对于项目根导入
import internal.myprivatemod

// 方式 2：设置 VMODROOT 环境变量
// export VMODROOT=/path/to/shared/libs

// 方式 3：将模块放入 ~/.vmodules/
// cp -r mymodule ~/.vmodules/mymodule
// 然后：import mymodule
```

---

## 7. 常见陷阱

### 陷阱 1：`import` 一行只能写一个

```v
// ❌ 错误
// import os, fmt, time

// ✅ 正确
import os
import fmt
import time
```

### 陷阱 2：`v run .` 编译所有 `.v` 文件

```v
// 如果在工作目录中有残留的测试或草稿文件，它们也会被编译
// 删除非模块文件或使用 v -o bin/main main.v 精确指定入口
```

### 陷阱 3：模块名与变量名冲突

```v
// ❌ 模块名 db 与变量 db 冲突
import db.sqlite

fn test() {
    mut db := sqlite.connect('test.db') or { panic(err) }  // db 已被用作导入路径
}

// ✅ 使用别名
import db as database

fn test() {
    mut database := sqlite.connect('test.db') or { panic(err) }
}
```

### 陷阱 4：`v run .` 的路径依赖

`v run .` 必须在 `v.mod` 所在目录执行。在深层嵌套目录执行不会找到 `v.mod`，编译可能失败。

### 陷阱 5：Windows 路径问题

```v
// 导入路径始终使用正斜杠（点号分隔符），V 自动处理 Windows 和 Unix 的路径转换
import internal.submodule // ✅ 跨平台一致
```

---

## 8. 推荐的项目布局

### 中小型项目 (< 15 文件)

```
myproject/
├── v.mod
├── main.v
├── handler.v
├── store.v
└── templates/
```

### 大型项目（多模块、高内聚）

```
myproject/
├── v.mod
├── cmd/
│   └── server/main.v          (module main — 应用入口)
├── internal/
│   ├── worldbank/             (module worldbank)
│   └── repository/            (module repository)
├── dbase/                     (module dbase — sqlite 封装)
├── templates/
└── static/
```
