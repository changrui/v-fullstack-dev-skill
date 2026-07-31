# V 0.5.x `os` 标准库模块 — std_os.md

`os` 模块是 V 全栈开发中使用最频繁的标准库之一。它提供文件 I/O、路径操作、环境变量和进程管理等核心功能。

---

## 1. 文件读写

### 简单读写（小文件）

```v
import os

// 读取整个文件到字符串
data := os.read_file('config.json') or { panic(err) }
println(data)

// 写入整个文件（覆盖）
os.write_file('output.txt', 'hello world') or { panic(err) }

// 追加内容
os.append_file('log.txt', '${time.now()}: event logged\n') or { panic(err) }
```

### 按行处理大文件

```v
mut f := os.open('large_file.txt') or { panic(err) }
defer { f.close() }

for line in f.read_lines() {
    println('line: ${line}')
}
```

### 创建并写入

```v
mut f := os.create('new_file.txt') or { panic(err) }
defer { f.close() }

f.write_string('first line\n') or { panic(err) }
f.write_string('second line\n') or { panic(err) }
// 注意：os.create 会覆盖已有文件
```

### 二进制文件

```v
mut f := os.open('data.bin') or { panic(err) }
defer { f.close() }

buf := []byte{len: 1024}
n := f.read(mut buf) or { panic(err) }
println('read ${n} bytes')

// 写入二进制
mut out := os.create('out.bin') or { panic(err) }
defer { out.close() }
out.write(buf) or { panic(err) }
```

---

## 2. 路径操作

```v
// 跨平台路径拼接（Windows: \ Unix: /）
full := os.join_path('dir', 'sub', 'file.txt')
// => 'dir/sub/file.txt' 或 'dir\sub\file.txt'

// 路径组件
dir  := os.dir('/a/b/c.txt')    // => '/a/b'
base := os.base('/a/b/c.txt')   // => 'c.txt'
ext  := os.ext('/a/b/c.txt')    // => '.txt'

// 绝对路径
abs  := os.real_path('relative/path')
// => 'C:\Users\...\relative\path' 或 '/home/.../relative/path'

// 文件名不含扩展名
name := os.file_name('/a/b/archive.tar.gz') // => 'archive.tar'

// 路径是否存在
os.exists('path')  // bool
os.is_dir('path')  // bool
os.is_file('path') // bool
```

### 启动时工作目录（重要）

```v
// os.wd_at_startup 是编译期常量，记录程序启动时的工作目录
// 它不会随运行时 os.chdir() 改变
println(os.wd_at_startup)
```

---

## 3. 环境变量

```v
// 读取环境变量
home := os.getenv('HOME') or { panic('HOME not set') }
port := os.getenv('PORT', '8080') // 带默认值

// 设置环境变量
os.setenv('MY_APP_MODE', 'production') or { panic(err) }
os.unsetenv('TEMP_VAR') // 删除环境变量

// 列出所有环境变量
for entry in os.environ() {
    // entry 格式: "KEY=value"
    parts := entry.split('=')
    key := parts[0]
    val := parts[1..].join('=')
    println('${key}=${val}')
}

// 获取特定环境变量列表
println(os.environ_with_prefix('GO')) // 以 GO 开头的变量
```

**⚠ 大小写敏感：** Linux 上环境变量名是大小写敏感的，Windows 上不敏感。跨平台代码建议统一大写。

---

## 4. 进程与执行

### 执行外部命令

```v
// 同步执行
result := os.execute('ls -la')
println('exit code: ${result.exit_code}')
println('output:\n${result.output}')

if result.exit_code != 0 {
    println('command failed')
}

// 解析 JSON 输出
output := os.execute('curl -s https://api.example.com/data') or { panic(err) }
data := json2.decode[MyModel](output.output) or { panic(err) }
```

### 带环境变量执行

```v
os.execute_with_env('myapp', ['--verbose'], ['PATH=/custom/bin', 'APP_MODE=test'])
```

### 程序自身信息

```v
// 可执行文件路径
exe_path := os.executable()
println('running from: ${exe_path}')

// 命令行参数
for i, arg in os.args {
    println('arg[${i}]: ${arg}')
}
println('total args: ${os.argc}')

// 进程 ID
println('PID: ${os.pid}')
```

---

## 5. 文件系统操作

```v
// 列出目录内容
entries := os.ls('mydir') or { panic(err) }
for entry in entries {
    println(entry)
}

// 创建目录（递归）
os.mkdir_all('a/b/c/d') or { panic(err) }

// 删除文件
os.rm('file.txt') or { panic(err) }

// 递归删除目录
os.rmdir_all('old_dir') or { panic(err) }

// 复制文件
os.cp('source.txt', 'backup/source.txt') or { panic(err) }

// 移动 / 重命名
os.mv('old_name.txt', 'new_name.txt') or { panic(err) }

// 临时目录
tmp := os.temp_dir()

// 用户主目录
home_dir := os.home_dir() or { panic('cannot find home dir') }
```

---

## 6. 路径锚定模式（重要）

在全栈应用中，正确锚定运行时路径是避免生产环境问题的关键。

```v
// ✅ 推荐方案：基于可执行文件位置 + v.mod 哨兵文件
fn find_project_root() string {
    mut dir := os.dir(os.executable())
    for _ in 0 .. 10 {
        if os.exists(os.join_path(dir, 'v.mod')) {
            return dir
        }
        dir = os.dir(dir) // 向上遍历
    }
    panic('project root (v.mod) not found')
}

// ✅ 备选方案：基于编译期工作目录
fn get_data_path() string {
    return os.join_path(os.wd_at_startup, 'data')
}

// ❌ 不推荐：依赖运行时工作目录
// os.getwd() 在用户从不同位置启动程序时会返回不同值
```

---

## 7. 常见陷阱

### 陷阱 1：`os.write_file()` 覆盖

`os.write_file()` 会**覆盖**已有文件。如需追加使用 `os.append_file()`。

### 陷阱 2：跨平台路径分隔符

```v
// ❌ 不要硬编码路径分隔符
path := 'dir/sub/file.txt' // Unix only — Windows 上失败

// ✅ 使用 join_path
path := os.join_path('dir', 'sub', 'file.txt')
```

### 陷阱 3：Windows 下的 `os.execute()`

```v
// ❌ Windows 上可能失败
os.execute('ls -la')

// ✅ Windows 兼容
os.execute('dir')
// 或
os.execute('where python')
```

### 陷阱 4：`os.getwd()` vs `os.wd_at_startup`

- `os.getwd()` 返回**运行时**当前工作目录（可能被 `os.chdir()` 改变）
- `os.wd_at_startup` 是**编译期常量**（启动时快照）
- 在 veb 或长期运行的进程中，`os.wd_at_startup` 更可靠

### 陷阱 5：文件句柄泄漏

```v
// ❌ 忘记 close()
f := os.open('file.txt') or { return }
data := f.read()

// ✅ 使用 defer 确保关闭
mut f := os.open('file.txt') or { return }
defer { f.close() }
data := f.read()
```
