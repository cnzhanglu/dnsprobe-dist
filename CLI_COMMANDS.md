# CLI 非交互命令参考

基于 `cmd/dnsprobe` 源码与 `help.go` 整理的非交互手册。各命令也可 `dnsprobe <cmd> -h` 看摘要与 flag 默认值。

相关文档：[README.md](README.md)（总览）、[TUI_COMMANDS.md](TUI_COMMANDS.md)（交互 REPL）、[docs/api.md](docs/api.md)（Web API）。拨测列表格式见 README「拨测列表格式」。

---

## 1. 命令总览

```text
dnsprobe                         → 交互式 TUI（默认）
dnsprobe tui
dnsprobe query   […]            → 单次 dig（多 DNS 时每服务器一行）
dnsprobe vs      […]            → 双 DNS 对比（shim；推荐 run --mode compare）
dnsprobe run     […]            → 批量 / 单域名 job（主路径）
dnsprobe task    <subcommand>   → 永久任务 CRUD / run
dnsprobe serve   […]            → 嵌入式 Web API + UI
dnsprobe config  <subcommand>   → 配置路径 / show / set / clean
dnsprobe help
```

帮助分层：

| 入口 | 行为 |
|------|------|
| `dnsprobe` / `help` / `-h` | 顶层中文总览 |
| `dnsprobe <cmd> -h` | 该命令 Usage + `PrintDefaults` |
| `dnsprobe task` / `task <sub> -h` | 嵌套子命令说明 |

未知顶层命令：stderr 提示 + 顶层 usage，退出码 **2**。校验失败通常打一行 `usage: …`（与 TUI `usage: /dns …` 同构）。

---

## 2. 共用拨测 flags

适用：`query` / `vs` / `run` / `task save`（协议项）以及 `run` / `task run` 的限速与输出项。注册集中在 `flags.go`（`addProbeFlags` / `addDNSFlags` / `addQPSFlag`）。

| Flag | 语义 | 默认 |
|------|------|------|
| `--dns` | 逗号分隔多 DNS（**主字段**） | config → resolv → `8.8.8.8` |
| `--dns1` / `--dns2` | 旧 shim；**有 `--dns` 时忽略** | — |
| `--timeout` | 查询超时 | `1s` |
| `--retries` | 超时最大尝试次数 | `2` |
| `--retry-interval` | 重试间隔 | `100ms` |
| `--rd` | 递归期望 RD | `true` |
| `--tcp` | 强制 TCP | `false` |
| `--edns` | EDNS UDP payload；`0`=关闭 | `4096` |
| `--subnet` | EDNS Client Subnet（`addr[/prefix]`） | 空 |
| `--qps` | 每 DNS QPS；`0`=不限（仅 job 路径） | **10** |

DNS 解析：显式 `--dns` / shim → 否则 `config.ResolveDefaultDNS()`（已保存 → 系统 resolv → `8.8.8.8`）。

Compare 时以 `Servers[0]` 为基准（与 TUI / Web 一致）。

### 显示语言（全局 `--lang`）

任意位置可加 `--lang zh|en|auto`（默认 `auto`）。`auto` 自动判定：语言偏好为中文（`LANG` 以 `zh` 开头，未设时看 `LC_ALL`/`LC_MESSAGES`，Windows 按系统 UI 语言）**且**系统装有 CJK 字体 → 中文，否则英文（规避缺 CJK 字形的终端乱码）。`en` 时 CLI 的 verdict 展示（对比/预期）改用英文。

**CSV 导出固定中文**：表头与 verdict 值始终中文（带 UTF-8 BOM / CRLF，便于 Windows Excel），`--lang` 不影响导出内容，只解决终端显示乱码。注意：自动判定只是「系统字体」近似，读不到终端真实渲染能力，根治仍是终端安装/切换中文等宽字体。

---

## 3. `query` — 单次 dig

```text
dnsprobe query [flags] [[@server] name [type] [+opts]]
```

| Flag | 说明 |
|------|------|
| `-n` / `--domain` | 域名 |
| `-t` / `--type` | 记录类型（默认 `A`） |
| `--detail` | 打印完整 dig 文本（`probe.FormatDig`） |
| `-o` | 显式写出 `.csv`/`.json`（**默认不写**） |
| `--outdir` | 写出目录；与 `-o` 二选一，优先 `-o`；自动命名 |

行为要点：

- 支持 dig 风格尾参：`[@server] name [type] [+opts]`，仅作用于本次。
- 行内 `@` 优先：只打该服务器；否则扇出全部 `--dns`，**每个服务器打印一行**（不启 Continuous）。
- 紧凑行：`status | server | name type | brief | latencyms`。
- **默认不写 CSV**（对齐 TUI 敲域名）；显式 `-o` / `--outdir` 才落盘；成功写出时 stderr 有 `detail: <path>`。

示例：

```bash
dnsprobe query -n example.com -t A --dns 8.8.8.8
dnsprobe query @1.1.1.1 example.com AAAA +tcp
dnsprobe query --dns 8.8.8.8,1.1.1.1 -n example.com --detail
dnsprobe query -n example.com --dns 8.8.8.8 -o ./out.csv
```

---

## 4. `vs` — 双 DNS 对比（shim）

```text
dnsprobe vs [flags]
```

内部走 `ModeCompare` + `Servers`（可用 `--dns a,b` 或 `--dns1`/`--dns2`）。需至少 2 个 DNS。

推荐主路径：

```bash
dnsprobe run --mode compare --dns a,b[,c…] --domain NAME
```

| Flag | 说明 |
|------|------|
| `-n` / `--domain` | 域名（必填） |
| `-t` / `--type` | 类型（默认 `A`） |
| `-o` / `--outdir` | 可选写出详情 |

示例：

```bash
dnsprobe vs -n example.com -t A --dns1 8.8.8.8 --dns2 1.1.1.1
dnsprobe vs --domain example.com --dns 8.8.8.8,1.1.1.1
```

说明：`vs` 为快捷对比，workers=1；未显式限速（`QPS=0`）。多 DNS / 列表 / watch / QPS 请用 `run`。

---

## 5. `run` — 批量 / 单域名（主路径）

```text
dnsprobe run --mode query|compare|expect \
  (--domain NAME [--type A] [--expected …] | -f LIST | -f -) \
  [--dns a,b…] [flags]
```

| Flag | 说明 |
|------|------|
| `--mode` | `query` / `compare` / `expect`（别名 `vs`→compare，`check`→expect） |
| `--vs` | 布尔别名 → compare（与 `--expect` 互斥；勿与冲突的 `--mode` 叠用） |
| `--expect` | 布尔别名 → expect |
| `--domain` / `-n` | 单域名（与 `-f` 互斥） |
| `--type` / `-t` | 单域名类型（默认 `A`） |
| `--expected` | expect + 单域名时**必填** |
| `-f` / `--list` | 列表文件；`-f -` 读 stdin |
| `--workers` | 并发（默认 **20**） |
| `--qps` | 每 DNS（默认 **10**；`0`=不限） |
| `--watch` | Continuous 持续拨测 |
| `--interval` | watch 轮间间隔（duration，如 `2s`） |
| `-o` | 详情文件路径 |
| `--outdir` | 详情目录（默认 **cwd**；自动 `{mode}-{name}-{ts}.csv`） |
| `--no-detail` | 不写详情，仅 stdout |
| `--fail-on-mismatch` | 结束时若有 mismatch → 非零退出（便于 CI） |

规则（对齐 TUI）：

- `compare`：`len(dns) >= 2`，否则报错退出。
- `expect` + `--domain`：必须 `--expected`；缺则错误、不 dig。
- `expect` + list：用清单第 4 列；缺列 / 空 → 运行时「不符合预期」（不因此拒绝启动）。
- 默认写出详情：有 `-o` 用该路径；否则在 `--outdir`（默认 cwd）自动命名。`--no-detail` 仅 stdout。
- `--watch`：同文件按轮追加；Ctrl+C 取消不截断已写内容。
- stdin：`-f -` 等价临时 batch（不进 taskstore）。

示例：

```bash
dnsprobe run --mode query -f testdata/sample_list.txt --dns 8.8.8.8
dnsprobe run --mode compare --dns 8.8.8.8,1.1.1.1 --domain example.com
dnsprobe run --mode expect --domain x.com --expected 1.2.3.4 --dns 8.8.8.8
dnsprobe run -f - --mode query --dns 8.8.8.8 < list.txt
dnsprobe run --mode query -f list.txt --watch --interval 2s
dnsprobe run --vs --dns 8.8.8.8,1.1.1.1 --domain example.com --fail-on-mismatch
```

---

## 6. `task` — 永久任务

存储：`~/.dnsprobe/tasks/*.json`（`DNSPROBE_HOME` 可覆盖）。镜像 TUI `/task`。

```text
dnsprobe task list
dnsprobe task show   <name|id>
dnsprobe task save   [flags]
dnsprobe task delete <name|id>     # 别名 del / rm
dnsprobe task run    <name|id> [flags]
```

解析顺序：精确 id → 忽略大小写 name → 唯一前缀；歧义报错。

### `task save`

| Flag | 说明 |
|------|------|
| `--name` | 任务名（同名 **upsert**） |
| `--mode` | `query` / `compare` / `expect` |
| `--dns`… | 见共用 flags |
| `--domain` **或** `--list` | 互斥 |
| `--expected` | expect + domain 必填 |
| `--type` | 默认 `A` |
| `--outdir` | 详情输出目录（空=运行时 cwd） |
| `--workers` | 默认 20 |
| 协议 flags | `--timeout` 等 |

**watch 不写入**任务 JSON（仅 `task run --watch` 运行时生效）。

```bash
dnsprobe task save --name check --mode expect --dns 8.8.8.8 \
  --domain example.com --expected 93.184.216.34
```

### `task run`

| Flag | 说明 |
|------|------|
| `--qps` | 覆盖运行限速（默认 10） |
| `--watch` / `--interval` | 持续拨测（不写回任务） |
| `-o` / `--outdir` | 覆盖任务 outdir |
| `--no-detail` | 仅 stdout |
| `--workers` | `0`=用任务值 |
| `--fail-on-mismatch` | CI 用 |

默认写出详情（cwd 或任务 `outdir`）。

```bash
dnsprobe task run check
dnsprobe task run check --watch --interval 5s --qps 5
```

---

## 7. `config`

```text
dnsprobe config path|dir|home     # 打印配置根与关键路径
dnsprobe config show              # Settings JSON
dnsprobe config set key=value…    # 写回 config.json
dnsprobe config clean --yes       # 备份后删除配置目录
```

`set` 支持键：`dns`, `type`, `timeout`, `retries`, `retry-interval`, `rd`, `tcp`, `edns`, `subnet`, `qps`, `outdir`|`work_dir`, `format`, `interval`, `detail_auto`。

- `qps=off` 或 `qps=0`：持久化为不限速（与 TUI `/save` 一致，内部存负数哨兵）。
- `clean` 必须 `--yes`（或 `-y`）；先备份为 `.bak.<时间戳>` 再删除。**不要**做进 TUI 菜单。

```bash
dnsprobe config path
dnsprobe config show
dnsprobe config set dns=8.8.8.8,1.1.1.1 qps=10 type=A
dnsprobe config clean --yes
```

---

## 8. `serve`

```text
dnsprobe serve [--listen :8080] [--token TOKEN]
```

- 无 token（且无 `DNSPROBE_TOKEN`）：强制绑定 **127.0.0.1**。
- 有 token：按 `--listen` 监听；`/api/*` 需 `Authorization: Bearer <token>`（SSE 可用 `?token=`）。

API 细节见 [docs/api.md](docs/api.md) 与 README「Web」。

---

## 9. 边界语义

| 主题 | 约定 |
|------|------|
| 结果落盘 | CLI `run` / `task run` 默认写 **cwd**（或 `--outdir` / 任务 outdir）；**禁止**默认写 `~/.dnsprobe/runs` |
| `query` 落盘 | 默认不写；显式 `-o`/`--outdir` |
| `~/.dnsprobe` | 仅 `config.json`、`history`、`tasks/` |
| QPS | 非交互 job 默认 **10/DNS**；`0`=不限 |
| watch | 同详情文件按轮追加；取消保留已写行 |
| expect | 单域名必 `--expected`；list 第 4 列；判定 actual ⊆ expected |
| DNS 主字段 | `--dns` / API `servers`；`dns1`/`dns2` 为 shim |
| 退出码 | 硬错误 ≠0；`--fail-on-mismatch` 时有 mismatch ≠0；`-h` 为 0 |

自动命名示例：`query-example.com-20060102-150405.csv`（`{mode}-{label}-{ts}.csv`）。

---

## 10. 与 TUI 对照

| 能力 | TUI | CLI |
|------|-----|-----|
| 单次 dig | 敲域名 / dig 行 | `query` + dig 尾参 |
| 多 DNS 扇出 | query 且会话 ≥2 DNS | `query --dns a,b` 或 `run --mode query` |
| 对比 | `/mode compare` | `run --mode compare`；`vs` shim |
| 预期 | `/mode expect` + `expected=` | `run --mode expect` + `--expected` / 列表第 4 列 |
| Continuous | `/mode watch`、`+watch` | `--watch [--interval]` |
| 列表 | `/list` + `/run` | `-f` / `--list` |
| 临时批量 | `/batch` | `-f -`（stdin） |
| 永久任务 | `/task …` | `dnsprobe task …` |
| QPS | `/qps`（默认 10） | `--qps`（默认 10） |
| 输出目录 | `/outdir`；`/run` 必写 | `-o` / `--outdir`；`run` 默认写 |
| 偏好 | `/save` | `config show` / `set` |
| 配置清理 | 无 | `config clean --yes` |
| 会话 UX | Hint、Tab、`/clear` | 无（脚本友好） |

故意不对等：CLI 不做缺参交互问答、不做 readline 补全；完整 dig 词法仅 `query` 具备。
