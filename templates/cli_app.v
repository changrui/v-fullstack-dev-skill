// cli_app.v — CLI 应用脚手架模板
//
// 包含: 参数解析、环境变量配置、子命令模式、颜色输出
//
// Build:  ~/v/v -o bin/myapp main.v
// Run:    ./bin/myapp --help
//
// 依赖: V 0.5.x, os (内置), term (内置)
module main

import os
import term
import json2

// ============================================================
// 配置 (环境变量 + 命令行参数)
// ============================================================
pub struct Config {

	// 命令
pub mut:
	command string // subcommand
	args    []string // subcommand args

	// 选项
	verbose bool
	output  string
	limit   int

	// 环境变量覆盖
	db_path string
	port    int
}

// 从环境变量加载默认配置
// config_from_env 从环境变量读取 CLI 配置并返回 Config
pub fn config_from_env() Config {
	return Config{
		verbose: os.getenv('VERBOSE', 'false') == 'true'
		output: os.getenv('OUTPUT_FORMAT', 'text')
		limit: os.getenv('LIMIT', '10').int()
		db_path: os.getenv('DB_PATH', './data/app.db')
		port: os.getenv('PORT', '8080').int()
	}
}

// 从命令行解析
// parse_args 解析命令行参数并填充 Config
pub fn (mut c Config) parse_args() ! {
	if os.args.len < 2 {
		return error('no command provided')
	}

	c.command = os.args[1]

	mut i := 2
	for i < os.args.len {
		arg := os.args[i]
		i++

		match arg {
			'-v', '--verbose' {
				c.verbose = true
			}
			'-o', '--output' {
				if i < os.args.len {
					c.output = os.args[i]
					i++
				}
			}
			'-l', '--limit' {
				if i < os.args.len {
					c.limit = os.args[i].int()
					i++
				}
			}
			'--help', '-h' {
				print_usage()
				exit(0)
			}
			else {
				// 剩余部分作为子命令参数
				c.args = os.args[i - 1..].clone()
				break
			}
		}
	}
}

// print_usage 打印 CLI 使用帮助
pub fn print_usage() {
	println('Usage: ${os.executable().base()} <command> [options]')
	println('')
	println('Commands:')
	println('  init        Initialize project')
	println('  run         Run the application')
	println('  status      Show status')
	println('  export      Export data')
	println('')
	println('Options:')
	println('  -v, --verbose     Enable verbose output')
	println('  -o, --output      Output format (text/json)')
	println('  -l, --limit N     Result limit (default: 10)')
	println('  -h, --help        Show this help')
	println('')
	println('Environment:')
	println('  VERBOSE=true       Verbose mode')
	println('  DB_PATH=<path>     Database path (default: ./data/app.db)')
	println('  PORT=<port>        Server port (default: 8080)')
}

// ============================================================
// 输出帮助函数
// ============================================================
// print_success 打印成功消息（绿色）
pub fn print_success(msg string) {
	println(term.bold(term.green('✓ ')) + msg)
}

// print_error 打印错误消息（红色）
pub fn print_error(msg string) {
	eprintln(term.bold(term.red('✗ ')) + msg)
}

// print_info 打印信息消息（蓝色）
pub fn print_info(msg string) {
	println(term.blue('ℹ ') + msg)
}

// print_warn 打印警告消息（黄色）
pub fn print_warn(msg string) {
	println(term.bold(term.yellow('⚠ ')) + msg)
}

// ============================================================
// 子命令处理
// ============================================================
// cmd_init 初始化命令 — 执行一次性项目初始化动作
pub fn cmd_init(cfg Config) ! {
	print_info('Initializing...')

	// 创建目录
	dirs := ['data', 'output', 'logs']
	for d in dirs {
		if !os.exists(d) {
			os.mkdir_all(d) or { return error('mkdir ${d}: ${err}') }
			print_success('Created ${d}/')
		}
	}

	if cfg.verbose {
		print_info('Config: db_path=${cfg.db_path}')
	}
	print_success('Initialized at ${os.wd_at_startup}')
}

// cmd_run 运行命令 — 启动主服务或守护进程
pub fn cmd_run(cfg Config) ! {
	print_info('Running on port ${cfg.port}...')
	print_info('Database: ${cfg.db_path}')
	_ = cfg
	// 启动 veb server 等...
}

// cmd_status 状态命令 — 显示运行时/服务状态
pub fn cmd_status(cfg Config) ! {
	mut status := map[string]string{}
	status['cwd'] = os.wd_at_startup
	status['executable'] = os.executable()
	status['verbose'] = if cfg.verbose { 'true' } else { 'false' }
	status['db_path'] = cfg.db_path
	status['port'] = cfg.port.str()

	if cfg.output == 'json' {
		println(json2.encode[map[string]string](status, json2.EncoderOptions{}))
	} else {
		for k, v in status {
			println(term.bold(k) + ': ' + v)
		}
	}
}

// cmd_export 导出命令 — 导出数据/报告等
pub fn cmd_export(cfg Config) ! {
	_ = cfg
	// 导出数据到文件
	print_info('Exporting...')
	// ...
	print_success('Export completed')
}

// ============================================================
// 入口
// ============================================================
fn main() {
	mut cfg := config_from_env()
	cfg.parse_args() or {
		print_error('${err}')
		print_usage()
		exit(1)
	}

	if cfg.verbose {
		print_info('Command: ${cfg.command}')
		print_info('Args: ${cfg.args}')
	}

	match cfg.command {
		'init' {
			cmd_init(cfg) or {
				print_error('init: ${err}')
				exit(1)
			}
		}
		'run' {
			cmd_run(cfg) or {
				print_error('run: ${err}')
				exit(1)
			}
		}
		'status' {
			cmd_status(cfg) or {
				print_error('status: ${err}')
				exit(1)
			}
		}
		'export' {
			cmd_export(cfg) or {
				print_error('export: ${err}')
				exit(1)
			}
		}
		else {
			print_error('Unknown command: ${cfg.command}')
			print_usage()
			exit(1)
		}
	}
}
