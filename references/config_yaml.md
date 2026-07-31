# vaiv CONFIG / YAML 深度参考

vaiv 的配置解析架构（agent/config.v），以及 V 的 yaml 库特性。

## V 的 yaml 库特性（vlib/yaml，底层是 json2）

- `yaml.decode[T](text)` / `yaml.decode_file[T](path)`：把 YAML 解码进 `T`。
  底层走 `json2.decode[T](d.to_json())`——所以字段名用 `@[json: 'x']` 注解，
  且 **yaml 不会展开环境变量**（`$VAR` 原样保留为字符串）。
- `yaml.parse_file(path) !Doc`：返回一棵 `Doc` 树，`d.root` 是
  `yaml.Any`（`map[string]Any | []Any | string | ...`）。任意键都能用
  `d.root as map[string]yaml.Any` 取到——**不受 struct 声明限制**。
- `Doc.decode[T]()`：在已有 `Doc` 上再做类型解码。

## vaiv 解析流程（config.resolve）

```
yaml.parse_file(path)        -> Doc d
expand_env_in_doc(mut d)     -> Doc doc   // 递归展开所有字符串的 $VAR/${VAR}
doc = expand_env_in_doc(d)
c   = doc.decode[Config]()   // ★ 必须用展开后的 doc，不是 d
finalize(mut c, doc)         // 从 doc 树提取 provider 列表
```

`expand_env_in_doc` 递归遍历 `map[string]Any` / `[]Any`，对每个 `string` 调
`expand_env()`：`$VAR` 取 `os.getenv('VAR')` 并保留尾部；`${VAR}` 同理。
非 `$` 开头或不成形的引用原样返回。

## provider 提取（extract_providers，数据驱动）

- 若 yaml 顶层有 `providers:` 列表（数组 of 含 `provider` 的 map）→ 逐个提取为
  ProviderDef，作为多 provider 回退列表。
- 否则取顶层 `provider:` 字段的值（如 `agnes`），从同名顶层块（如 `agnes:`）读
  base_url/model/api_key。**其他具名块（ollama/llamacpp/shangtang…）不会自动激活**，
  它们只是「当 provider 设为同名时的默认配置源」。
- 未声明 provider 名字的连接块一律忽略——避免 ollama/llamacpp 在本地无服务时
  被误激活去连 localhost 导致 all-providers-failed panic。

## 优先级（config 优先于 env，用户硬性偏好）

`finalize` 里：
- env（`VCA_API_KEY`/`VCA_MODEL`/`VCA_BASE_URL`）只在对应字段为空时*补充*。
- `VCA_PROVIDER` 仅在 config 完全没指定 provider 时才生效（无 config / 无 provider 块）。
- remote provider（非 mock/ollama/llamacpp）无 key → 跳过；全跳过 → 兜底 mock。

## 测试隔离坑

交互 shell 或 CI 常 export `AGNES_API_KEY`/`VCA_API_KEY`，会让 agnes 真连而非降级，
使本应离线的测试（mock）拿到真实 key 去联网失败。验证「降级 / 展开 / 优先级」时必须
用 `env -i`（彻底清掉所有注入变量）再跑 `vaiv config` 或 `v -silent test .`：
```
env -i PATH="$HOME/v:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" ./bin/vaiv config
env -i PATH="$HOME/v:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" v -silent test .
```
注意：只 `VAR= v cmd` 前缀赋值在有些 agent 终端里清不掉 profile 重新注入的变量，
`env -i` 才可靠。

## 常见踩坑

1. 用未展开的 `d` 而非 `doc` 去 `decode` → Config 字段是 `$VAR` 字面量，
   `resolve_provider_def` 误判「有 key」→ provider 不降级、顶层 api_key 写出字面量。
2. 把 ollama/llamacpp 等连接块当 provider 自动激活 → 本地无服务时连 localhost 失败。
3. `expand_any` 里 `map[string]Any` 必须写全 `map[string]yaml.Any`（模块内裸 `Any`
   会被当成 `agent.Any` 而报错）；数组/map 赋值要 `.clone()`（V 0.5.2 特性）。
4. 可选类型解包 `if x := m['k'] { }` 不能加 `else` 分支。
