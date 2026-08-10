# dnsprobe 使用说明

> 本文档由源码仓库 README 拆分而来，随 Release 自动同步到发布仓库。
> 源码为私有仓库；此处仅提供使用说明与命令参考（另见 [CLI_COMMANDS.md](CLI_COMMANDS.md)、[TUI_COMMANDS.md](TUI_COMMANDS.md)、[docs/api.md](docs/api.md)）。

## 拨测列表格式

每行至少 `域名 类型`（空白分隔）。空行与 `#` 注释忽略。

可选扩展列（expect 模式）：

```text
domain  type  tag  expected
example.com. A sp 192.0.2.1,198.51.100.2
```

- 第 1–2 列：域名、记录类型（必填）
- 第 3 列：标签（如 `ga`/`sp`/`rr`），**忽略**，不写入结果
- 第 4 列：预期答案；多项用 `,` 分隔。判定规则：实际答案均落在预期集合内（actual ⊆ expected）；list/batch 缺列或空 → 「不符合预期」（不报错）。TUI 敲域名或 domain 任务则必须显式给出预期（`expected=` / 任务字段），否则报错不 dig。

示例（每行 `域名 类型`，可带 `tag`/`expected`）：

```text
# sample bocelist: domain type
example.com A
example.com AAAA
www.example.com CNAME
example.com MX
example.com NS
example.com TXT
```

## CLI

共用拨测参数（适用处）：`--dns`（多服务器，**主字段**）、`--dns1`/`--dns2`（旧 shim，有 `--dns` 时忽略）、`--qps`（默认 10，`0`=不限）、`--timeout`、`--retries`、`--retry-interval`、`--rd`、`--tcp`、`--edns`、`--subnet`。各命令 `dnsprobe <cmd> -h` 有中文说明；完整对照与边界见 **[CLI_COMMANDS.md](CLI_COMMANDS.md)**。

> 显示语言：任意位置可加 `--lang zh|en|auto`（默认 `auto`）。`zh` 强制中文、`en` 强制英文（用于缺 CJK 字形、中文显示成「框框」的终端）；`auto` 自动判定：语言偏好为中文（`LANG` 以 `zh` 开头，未设时看 `LC_ALL`/`LC_MESSAGES`，Windows 按系统 UI 语言）**且**系统装有 CJK 字体 → 中文，否则英文。**`--lang` 只影响终端控制台展示（verdict 等），CSV 导出固定中文**（表头与 verdict，带 UTF-8 BOM / CRLF 便于 Excel）；中英切换仅为解决不支持中文显示终端的乱码，根治仍是终端安装/切换支持中文的字体。

### `query` — 单次 dig

```bash
./dnsprobe query -n example.com -t A --dns 8.8.8.8
./dnsprobe query @1.1.1.1 example.com AAAA +tcp
./dnsprobe query --dns 8.8.8.8,1.1.1.1 -n example.com --detail   # 多 DNS 每服务器一行
./dnsprobe query -n example.com --dns 8.8.8.8 -o ./out.csv         # 显式落盘
```

默认不写 CSV（对齐 TUI 敲域名）；显式 `-o` / `--outdir` 才落盘。`--detail` 打印完整 dig 文本。

### `vs` — 双 DNS 对比（shim）

```bash
./dnsprobe vs -n example.com -t A --dns1 8.8.8.8 --dns2 1.1.1.1
./dnsprobe vs --domain example.com --dns 8.8.8.8,1.1.1.1
# 推荐：dnsprobe run --mode compare --dns a,b[,c…] --domain example.com
```

### `run` — 批量 / 单域名（主路径）

```bash
./dnsprobe run --mode query -f list.txt --dns 8.8.8.8
./dnsprobe run --mode compare --dns 8.8.8.8,1.1.1.1 --domain example.com
./dnsprobe run --mode expect --domain x.com --expected 1.2.3.4 --dns 8.8.8.8
./dnsprobe run -f - --mode query --dns 8.8.8.8 < list.txt
./dnsprobe run --mode query -f list.txt --watch --interval 2s --qps 10
./dnsprobe run --vs --dns 8.8.8.8,1.1.1.1 --domain example.com --fail-on-mismatch
```

默认写出详情到 **cwd**（或 `--outdir`）自动命名 `{mode}-{name}-{ts}.csv`；`--no-detail` 仅 stdout。`--vs`/`--expect` 为 `--mode` 别名。`--fail-on-mismatch` 便于 CI。默认 workers：`20`；QPS 默认 `10`/DNS。

### `task` — 永久任务（`~/.dnsprobe/tasks`）

```bash
./dnsprobe task list
./dnsprobe task show check
./dnsprobe task save --name check --mode expect --dns 8.8.8.8 \
  --domain example.com --expected 93.184.216.34
./dnsprobe task run check
./dnsprobe task run check --watch --interval 5s --qps 5
./dnsprobe task delete check
```

同名 `save` 为 upsert；`watch` 不写入任务 JSON。解析：精确 id → 忽略大小写 name → 唯一前缀。

### `config`

```bash
./dnsprobe config path
./dnsprobe config show
./dnsprobe config set dns=8.8.8.8,1.1.1.1 qps=10 type=A
./dnsprobe config set timeout=2s edns=1232
./dnsprobe config clean --yes
```

`set` 键含 `dns`/`type`/`timeout`/`qps`/`outdir` 等（见 `dnsprobe config set -h`）。清理需 `--yes`；TUI 无 clean 菜单。
## TUI（默认入口）

```bash
./dnsprobe        # 无参数 → 交互式 TUI
./dnsprobe tui    # 同上
```

基于 `reeflective/readline` 的 REPL：不进入 alt-screen；日志进终端 scrollback；提示为 `›` + Hint（状态与全部 DNS）。

要点：行内 `@` / 类型 / dig `+` 只覆盖**本次**，不改会话 DNS/type/opts；query 且会话 ≥2 DNS 时敲域名走 job 扇出（**默认不写 CSV**；`+detail` 或 `/detail on` 才落盘）；`+watch` 为引擎内 Continuous 单 job，落盘时**同文件按轮追加**；行内 `@x` 仍只 dig 该服务器；expect 敲域名须带 `expected=`（或清单第 4 列）。完整场景矩阵与命令见 **[TUI_COMMANDS.md](TUI_COMMANDS.md)**（会话内也可 `/help`）。

### 演示动图

TUI 演示动图（启动/查询/对比）见源码仓库 README；此处只提供文字说明。

### 常用操作（摘要）

| 操作 | 方式 |
|---|---|
| 单条查询 | `example.com` / `example.com AAAA`；`+brief`、`@server`、`+tcp` 等见命令参考 |
| 模式 | `/mode query\|compare\|expect\|watch`；任务可持久化 `query\|compare\|expect`（watch 仅会话） |
| 限速 | `/qps 10`（默认每 DNS 10/s）；`/qps off` 关闭 |
| 临时批量 | `/batch`：Enter 换行，F2/Ctrl+D 跑，Ctrl+O/S 载入后 `/run` |
| 永久任务 | `/task new\|edit\|set\|save\|run\|del`；目标 `domain` 与 `list` 互斥 |
| 列表 / 输出 | `/list` `/open` → `/run`（自动 CSV）；敲域名默认不写，`+detail`/`/detail`；目录 `/outdir` |
| 补全 / 历史 | Tab；↑↓ 与 Ctrl+R（`~/.dnsprobe/history`） |
| 退出 | Ctrl+C 两次（2 秒内）；Ctrl+D 退出（`/batch` 中 Ctrl+D 为运行） |

```text
example.com +brief +watch +interval=2s +qps=5
/dns 8.8.8.8,1.1.1.1
/mode compare
/list ./list.txt
/run
```

默认 DNS：已保存配置 → 系统 resolv → `8.8.8.8`。配置与永久任务在 `~/.dnsprobe/`（`DNSPROBE_HOME` 可覆盖）。临时批量不进该目录。配置 CLI：`dnsprobe config path|show|set|clean`（清理需 `--yes`；TUI 无 clean 菜单）。

## Web（`serve`）

```bash
# 仅本机（无 token）— 强制绑定 127.0.0.1
./dnsprobe serve --listen :8080

# 可远程 — 需要 Bearer token
./dnsprobe serve --listen :8080 --token 'your-secret'
# 或：
export DNSPROBE_TOKEN='your-secret'
./dnsprobe serve --listen 0.0.0.0:8080

# 持久库选项（默认已开启）
#   --store ~/.dnsprobe/runs.db     拨测结果单文件库（off=关闭，退回纯内存）
#   --store-retention 168h          持久库任务保留时长（默认 7 天；0=不自动清理）
#   --job-max 200 / --job-max-age 24h   内存保留策略（防止长驻进程内存无限增长）
```

在监听地址打开 UI（如 `http://127.0.0.1:8080`）。API 前缀 `/api/v1`。更完整的字段说明见 **[docs/api.md](docs/api.md)**。

### 安全说明

| 设置 | 行为 |
|---|---|
| 无 `--token` 且无 `DNSPROBE_TOKEN` | 强制绑定 **`127.0.0.1`**（端口取自 `--listen`）；服务端打警告。适合仅本机使用。 |
| 已设置 token | 按配置地址监听；**`/api/*` 需要** `Authorization: Bearer <token>`（SSE 也可传 `?token=`，因为 EventSource 无法设头）。静态 UI 仍可不鉴权加载。 |

不要在公网接口暴露未鉴权实例。远程访问请用强 token，并在反向代理上做 TLS 终结。永久任务读写的是**服务端** `~/.dnsprobe/tasks`（可用 `DNSPROBE_HOME` 覆盖）。

### API 概要

**Jobs**（批量/持续任务自动落持久库，可回查全历史并带每行拨测时间；单条域名查询不落库）

- `GET /api/v1/jobs` — 列出任务（内存运行中优先 + 持久库历史；含 `rows` 记录行数）
- `POST /api/v1/jobs` — 创建（JSON 或 multipart）
- `GET /api/v1/jobs/{id}` — 状态；`?include=results` 带结果（持久库任务返回全历史，行含 `at`）
- `GET /api/v1/jobs/{id}/events` — SSE
- `GET /api/v1/jobs/{id}/export.csv` / `export.json` — 下载全历史（行尾「时间」列，无轮次概念）
- `POST /api/v1/jobs/{id}/cancel` — 取消（含 Continuous）
- `DELETE /api/v1/jobs/{id}` — 手动清理（内存 + 持久库）

创建常用字段：`servers`（主 DNS，数组或逗号串；优先于 `dns1`/`dns2`）、`mode`（`query`/`compare`/`expect`）、`name`+`type` 或 `list`、`expected`（expect+单域名必填）、`qps`（默认 **10**，`0`=不限）、`continuous` + `interval_ms`、`workers`、协议选项、可选 `output_dir`（服务端落盘）。

Web 记录列表：**运行中 / 已完成分栏**，展示任务开始时间、记录数（行数）、查询模式；任务执行记录额外显示任务名 + JobID。

**Tasks**（永久定义）

- `GET/POST /api/v1/tasks`；`GET /api/v1/tasks?name=`
- `GET/PUT/PATCH/DELETE /api/v1/tasks/{id}`
- `POST /api/v1/tasks/{id}/run` — 生成 job（body 可覆盖 `qps`/`continuous`/`interval_ms`/`workers`）→ `201 {"id": jobId}`

不暴露改 `config.json` / `config clean` 的通用 API。
## 与 Python boce 的差异

探测/对比语义刻意对齐（状态字符串、排序后 `;` 拼接的 rdata、TXT 大小写敏感对比、截断→TCP）。产品侧主要差异：

| 方面 | Python boce（Qt） | dnsprobe |
|---|---|---|
| 并发 | Qt 线程式 worker | 共享 job runner 上的 worker 池（默认 20） |
| UI | 桌面 Qt | CLI + 终端 TUI + 嵌入式 Web/SSE |
| 远程 | 非一等 HTTP 服务 | `serve` + Bearer token，默认仅本机 |
| 任务存储 | 会话 / UI 状态 | 运行 jobs：内存 + 持久库（`~/.dnsprobe/runs.db`，批量/持续落库、7 天清理）；永久任务：`~/.dnsprobe/tasks`（CLI/TUI/Web） |
| Rdata 文本 | dnspython `rdata.to_text()` | miekg/dns 展示形式（通常等价；边界情况可能不同） |

本版本不包含：DoH/DoT、DNSSEC 校验、多用户账号、zonefile→拨测列表转换。
