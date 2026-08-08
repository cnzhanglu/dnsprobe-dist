# TUI 命令与参数参考

基于 `internal/tui` 源码整理的 readline REPL 完整手册。会话内也可输入 `/help` 看摘要。

相关文档：[README.md](README.md)（总览）、[CLI_COMMANDS.md](CLI_COMMANDS.md)（非交互 CLI）、[TUI_UX_PLAN.md](TUI_UX_PLAN.md)（UX 设计）、拨测列表格式见 README「拨测列表格式」。

---

## 1. 启动与界面

```bash
./dnsprobe          # 无参数 → TUI
./dnsprobe tui      # 同上
```


| 元素         | 说明                                                             |
| ---------- | -------------------------------------------------------------- |
| Primary 提示 | 仅 `›` （单行）                                                     |
| Hint       | 两行：会话状态（type/rd/tcp/mode/format/interval/qps/workers…）+ 全部 DNS |
| 日志         | 写入终端主缓冲（scrollback），**不**进入 alt-screen；终端原生滚动、选中、复制可用          |
| `/clear`   | 只清内存日志跟踪，**不清**终端 scrollback；任务结束也不清日志                         |
| 空回车        | 可留下空行/`›`，不刷 DNS/状态块                                           |


默认 DNS：已保存配置 → 系统 resolv → `8.8.8.8`。配置与历史、永久任务在 `~/.dnsprobe/`（可用 `DNSPROBE_HOME` 覆盖）。

---



## 2. 全局按键


| 按键                  | 行为                                             |
| ------------------- | ---------------------------------------------- |
| **Tab**             | 补全：斜杠命令、参数、任务名、路径、行内 `+…`                      |
| **↑ / ↓**           | 浏览命令历史（`~/.dnsprobe/history`）                  |
| **Ctrl+R**          | 增量搜索历史                                         |
| 粘贴                  | bracketed paste（readline）；路径两端成对引号（含弯引号）会自动去掉  |
| **Ctrl+C**（第一次）     | 有 job → 取消；有 watch → 停止；有输入 → 提示已清空。进入 2 秒退出窗口 |
| **Ctrl+C**（2 秒内第二次） | 退出 TUI                                         |
| **Ctrl+D**          | 普通提示 → 退出；`/batch` 多行编辑中 → **立即运行**批量          |
| **Esc**             | `/batch` 取消；`/task` 向导/编辑菜单取消                  |


---



## 3. 会话模式 `/mode`

```text
/mode                         # 查看当前
/mode query|compare|expect|watch|continuous
```


| 值         | 别名                           | 含义                                                                        |
| --------- | ---------------------------- | ------------------------------------------------------------------------- |
| `query`   | `q`, `single`                | 查询（默认）。会话 1 DNS 或行内 `@x` → dig；会话 ≥2 DNS 且无行内 `@` → job 扇出                |
| `compare` | `vs`, `batch`†               | 多 DNS 对比；需 ≥2 个服务器（`/dns a,b`）。键入域名启动对比 job                               |
| `expect`  | `check`                      | 预期判定。敲域名须带 `expected=` 或清单同款第 4 列；list/batch 用第 4 列。判定：`符合预期` / `不符合预期`   |
| `watch`   | `continuous`, `cont`, `loop` | 持续循环：语义同当前草稿 query/compare/expect（dig watch 或 job 重跑），直到 `/stop` 或 Ctrl+C |


† `batch` 作为 `/mode` 别名时等于 `compare`，与 `/batch` 临时批量命令无关。

**持久化边界**

- 会话：`query` / `compare` / `expect` / `watch` 均可 `/mode` 切换。
- 永久任务（`Task.Mode`）：只存 `query`  `compare`  `expect`；`watch` **仅会话态**，不写 taskstore。
- `/mode` 切换 query/compare/expect 时会同步到当前草稿 `Mode`（便于随后 `/task save`）；切到 watch 不改草稿拨测 Mode。
- 加载/编辑已保存任务时，会话 mode 跟随任务 `Mode`。

兼容旧命令：`/compare on|off`（推荐改用 `/mode compare|query`）。

---



## 4. 斜杠命令一览

无参时多数命令打印当前值；有参则设置。

### 4.1 帮助与会话


| 命令       | 别名         | 语法       | 说明                                                                             |
| -------- | ---------- | -------- | ------------------------------------------------------------------------------ |
| `/help`  | `/h`, `/?` | `/help`  | 打印内置帮助摘要                                                                       |
| `/save`  | —          | `/save`  | 保存偏好 → `~/.dnsprobe/config.json`（DNS、type、Options、workdir、qps、format、interval） |
| `/clear` | —          | `/clear` | 清内存日志；终端 scrollback 保留                                                         |
| `/stop`  | —          | `/stop`  | 停止当前 job 与 watch                                                               |




### 4.2 DNS 与查询选项


| 命令         | 别名   | 语法                            | 默认 / 备注                                                             |
| ---------- | ---- | ----------------------------- | ------------------------------------------------------------------- |
| `/dns`     | —    | `/dns` 或 `/dns <ip[,ip…]>`    | 设置会话与草稿服务器；多 IP 逗号分隔。query 扇出/compare/expect 用全部；行内 `@x` 只 dig 该服务器 |
| `/type`    | `/t` | `/type` 或 `/type <T>`         | 默认 `A`。常用：A AAAA CNAME MX NS TXT PTR SOA SRV CAA                    |
| `/rd`      | —    | `/rd` 或 `/rd on|off`          | 无参切换。默认 on。别名：`on|1|true|yes` / `off|0|false|no`                    |
| `/tcp`     | —    | `/tcp` 或 `/tcp on|off`        | 无参切换。默认 off（UDP，截断仍 TCP fallback）                                   |
| `/timeout` | —    | `/timeout` 或 `/timeout <dur>` | 如 `2s`、`500ms`；须 `>0`。默认 `1s`                                       |
| `/retries` | —    | `/retries` 或 `/retries <n>`   | `n≥1`。超时最大尝试次数，默认 `2`                                               |
| `/workers` | `/w` | `/workers` 或 `/workers <n>`   | `n≥1`。批量并发，默认 `20`                                                  |




### 4.3 模式、输出与限速


| 命令          | 别名      | 语法                                    | 说明                                                                                     |
| ----------- | ------- | ------------------------------------- | -------------------------------------------------------------------------------------- |
| `/mode`     | —       | 见 §3                                  | 会话模式                                                                                   |
| `/format`   | —       | `/format` 或 `/format default|brief`   | 单条查询会话输出。别名：`full`/`dig`→default；`short`/`compact`→brief                               |
| `/interval` | —       | `/interval` 或 `/interval off|0|<dur>` | watch 轮次间隔，最大 24h                                                                      |
| `/qps`      | `/rate` | `/qps` 或 `/qps <n|off|0>`             | **每 DNS** 请求/秒；默认 `10`。`off`/`none`/`unlimited`/`0` 关闭。`/save` 时关闭存为负数以免 omitempty 丢状态 |
| `/detail`   | —       | `/detail` 或 `/detail on\|off`         | 敲域名 job 是否默认落 CSV；**默认 off**。`/run` `/batch` `/task` **始终写**。可 `/save`（`detail_auto`） |
| `/compare`  | `/vs`   | `/compare` 或 `/compare on|off`        | **已弃用**；请用 `/mode compare|query`                                                       |


会话级 `/format`、`/interval`、`/qps` 可 `/save`；行内 `+brief` / `+watch` / `+qps=` / `+interval=` **只覆盖本次**（§5）。

### 4.4 列表、输出目录、高级


| 命令        | 别名                       | 语法                                               | 说明                                                              |
| --------- | ------------------------ | ------------------------------------------------ | --------------------------------------------------------------- |
| `/list`   | `/file`                  | `/list`；`/list <path>`；`/list clear|none|-`      | 设活动列表文件（须为普通文件）。加载后清空草稿 Domain，活动目标改为 list。路径 Tab 补全；支持 `~`、去引号 |
| `/open`   | —                        | `/open <path>`                                   | 同 `/list <path>`                                                |
| `/outdir` | `/output`, `/output_dir` | `/outdir`；`/outdir <path>`；`/outdir clear|cwd|-` | 详情 CSV 目录。**空 = 进程 cwd**（不是 `~/.dnsprobe/runs`）                 |
| `/adv`    | `/advanced`              | `/adv`；`/adv key=value…`                         | 无参打印；可设：`retry-interval=<dur>`（≥0）、`edns=<512-65535>`           |




### 4.5 运行


| 命令          | 语法                                  | 说明                                                 |
| ----------- | ----------------------------------- | -------------------------------------------------- |
| `/run`      | `/run`                              | 跑当前活动目标：临时批量 items、或草稿 Domain、或 ListPath（无需先 save） |
| `/run`      | `/run <name|id>`                    | 跑已保存永久任务（解析规则见 §6.6）                               |
| `/task run` | `/task run` 或 `/task run <name|id>` | 同上                                                 |


活动目标互斥：单域名 / 列表文件 / 临时批量 三者只能有一个为当前 `/run` 来源；切换来源可保留 `/batch` 文本供再编辑，但不保留 items。

---



## 5. Dig 风格查询行（非斜杠）

不以 `/` 开头的行按 dig 风格解析。协议参数经 `probe.ParseDigQuery`；展示/循环参数由 TUI 先剥离。

### 5.1 基本形式

```text
example.com
example.com AAAA
@8.8.8.8 example.com MX +tcp +time=2
example.com IN A
example.com -t AAAA
```


| 语法                       | 说明                       |
| ------------------------ | ------------------------ |
| `name [TYPE]`            | 域名为必填；类型可省略（用会话 `/type`） |
| `@server`                | 仅本次查询服务器                 |
| `-t TYPE` / `-type TYPE` | 记录类型                     |
| `IN` / `CH` / `HS`       | 裸 class 词忽略（dig 兼容）      |




### 5.2 协议 `+` 参数（仅本次 Options）


| 参数                       | 含义                  |
| ------------------------ | ------------------- |
| `+tcp` / `+vc`           | 强制 TCP              |
| `+notcp`                 | 优先 UDP              |
| `+norec`                 | RD=0                |
| `+recurse` / `+rec`      | RD=1                |
| `+subnet=addr[/prefix]`  | EDNS Client Subnet  |
| `+time=N` / `+timeout=N` | 超时秒数                |
| `+tries=N` / `+retry=N`  | 超时最大尝试次数            |
| `+bufsize=N`             | EDNS UDP payload    |
| `+edns[=N]`              | 开启 EDNS（可选 payload） |
| `+noedns`                | 关闭 EDNS 并清空 Subnet  |


不支持：`+trace`、DoH/DoT、AXFR、TSIG、dig 的 `+short`/`+json` 等（会报错）。

### 5.3 一次性参数 vs 会话持久（硬规则）


| 来源                                                                  | 是否改会话 `dns`/`type`/`opts`/草稿 Type·Servers·Options | 生效范围                         |
| ------------------------------------------------------------------- | ------------------------------------------------- | ---------------------------- |
| `/dns` `/type` `/rd` `/tcp` `/timeout`… `/mode` `/task set` / 向导/菜单 | **是**                                             | 持续到再次修改                      |
| 查询行 `example.com AAAA @1.1.1.1 +tcp` 等 dig 风格                       | **否**                                             | **仅本行**                      |
| `+brief` `+watch` `+qps=` `+interval=` `+detail`                    | **否**                                             | 仅本行（`+detail` 还可覆盖本行启动的 watch） |
| `draft.Domain`                                                      | 可记录上次活动域名                                         | 供随后 `/run`（Type 等仍用会话/草稿持久值） |




### 5.4 TUI 专用覆盖


| 参数                               | 含义                                                        |
| -------------------------------- | --------------------------------------------------------- |
| `+watch`                         | 持续（单 DNS dig 用 `watchSpec`；多 DNS/compare/expect 用 job 重跑） |
| `+once`                          | 只跑一次（覆盖会话 watch）                                          |
| `+detail`                        | 本次敲域名 job 落 CSV；与 `+watch` 同用时同文件**按轮追加**（`轮次`/`时间`） |
| `+brief` / `+short` / `+compact` | 精简输出（**仅单条 dig**）                                         |
| `+full` / `+dig` / `+default`    | 完整 dig 输出（**仅单条 dig**）                                    |
| `+qps=<n|off|0>`                 | 本次每 DNS QPS（仅单条 dig）                                      |
| `+interval=<dur|off|0>`          | 本次轮次间隔（仅单条 dig）                                           |
| `expected=a,b`                   | expect 行内预期（多项 `,` 分隔）                                    |
| `domain type tag expected`       | 与清单同款四列（第 3 列标签忽略）                                        |


冲突对会报错（如同时 `+watch` 与 `+once`，或 `+brief` 与 `+full`）。

**重要**：`+brief`/`+full`/`+qps=`/`+interval=` **不得**用于 job 路径（多 DNS query / compare / expect）；会显式报错。`+watch` / `+detail` 可用于 job 路径。普通 dig 协议参数在 job 路径仍可用（仅本次 Options）。

### 5.5 场景矩阵：mode × 目标 × DNS


| 敲域名时                      | 行为                                  |
| ------------------------- | ----------------------------------- |
| query + 1 会话 DNS（无行内 `@`） | dig（可 full / `+brief` / `+watch`）   |
| query + ≥2 会话 DNS         | `ModeQuery` job 扇出（终端紧凑行；**默认不写 CSV**） |
| query + 行内 `@x`           | dig **仅** `@x`（一次性，不改会话 DNS）        |
| compare + ≥2              | compare job（单 DNS 拒绝；默认不写 CSV）       |
| expect + 可解析预期            | expect job；否则**明确报错**，禁止 silent dig |
| watch + 上述                | 同语义：**引擎 Continuous 单 job** 循环（非 Finished 重跑） |
| 同上且 `+detail` 或 `/detail on` | 落盘；**同文件按轮追加**（`轮次`/`时间` 列），禁止每轮新文件、禁止结束时截断 |


已加载的 `/list` **不会**因键入域名自动跑列表；列表须 `/run`。`/batch` 不提供一键存任务；需要永久任务时用 `/task new` + list。

**CSV 落盘规则**

| 入口 | 默认写文件？ |
|------|-------------|
| 敲域名（含 `+watch`） | 否；需 `+detail` 或 `/detail on` |
| `/run` / `/batch` / `/task run` | 是；watch 时 Continuous 同路径**按轮追加** |
| `/outdir` | 只定目录，不单独表示「一定要写」 |

---



## 6. 永久任务 `/task`

任务文件：`~/.dnsprobe/tasks/*.json`。名称唯一；同名 Save **upsert**。

```text
/task                              # 等同 /task list
/task list|ls|panel
/task new [name]
/task edit|load <name|id>
/task set key=value…
/task save [name]
/task run [name|id]
/task del|delete|rm <name|id>
```



### 6.1 `/task list`

列出已保存任务：短 id、名称、servers、**mode**（`query`/`compare`/`expect`）、target、outdir。

### 6.2 `/task new` 向导

```text
/task new
/task new my-task
```

逐步提示（Esc / Ctrl+C 取消；结束后直接 Save）：

1. **name** — 必填；若已存在提示将更新该 id
2. **dns (CSV)** — 默认当前会话 DNS
3. **mode** — `1=query` / `2=compare` / `3=expect`（默认跟会话；watch 按 query 起稿）
4. **type** — 默认会话 type
5. **target** — `1=domain` / `2=list`，再填域名或清单路径（list 路径 Tab 补全）
6. **expected** — 仅 `mode=expect` 且 target=domain 时询问（`,` 分隔）
7. **outdir** — 回车 = cwd；目录 Tab 补全
8. **workers** — 正整数

保存时校验：名称非空、≥1 服务器、compare 须 ≥2 服务器、domain 与 list **互斥且必有其一**；expect+domain 必须有 expected。

### 6.3 `/task edit` 菜单

```text
/task edit <name|id>
```

加载任务后进入编号菜单：

```text
  1) name
  2) dns
  3) mode     （1=query / 2=compare / 3=expect）
  4) type
  5) target   （先选 1=domain / 2=list，再填值）
  6) expected （domain 用；list 显示「list 第4列」）
  7) outdir
  8) workers
  s) 保存
  q) 取消     （Esc 同取消；恢复进入前草稿）
```

输入序号改字段 → 循环，直至 `s` 或 `q`。

别名：`/task load` = `/task edit`。

### 6.4 `/task set` 快捷补丁

须已有草稿名或 id（先 `/task new` / `/task edit`）：

```text
/task set name=foo dns=8.8.8.8,1.1.1.1 mode=expect type=A target=list:./list.txt outdir=. workers=20
```


| key         | 别名                        | 值                                                               |
| ----------- | ------------------------- | --------------------------------------------------------------- |
| `name=`     | —                         | 任务名                                                             |
| `dns=`      | `servers=`                | CSV IP                                                          |
| `mode=`     | —                         | `query`/`q`/`1`；`compare`/`vs`/`c`/`2`；`expect`/`check`/`e`/`3` |
| `type=`     | `qtype=`                  | 记录类型                                                            |
| `domain=`   | —                         | 单域名（清空 list）                                                    |
| `list=`     | `list_path=`, `listpath=` | 清单路径（清空 domain 与 domain 专用 expected；`expandPath`）               |
| `expected=` | `expect=`                 | domain 目标在 expect 模式下的预期答案（`,` 分隔）；list 用清单第 4 列                |
| `target=`   | —                         | `domain:<fqdn>` 或 `list:<path>`                                 |
| `outdir=`   | `output=`, `output_dir=`  | 详情目录；空语义见 `/outdir`                                             |
| `workers=`  | —                         | 正整数                                                             |


`set` 后会话 mode 跟随草稿（含 expect）；watch 仍只能由 `/mode watch` 设置。

### 6.5 `/task save` / `run` / `del`


| 命令                    | 说明                       |
| --------------------- | ------------------------ |
| `/task save [name]`   | 校验并写入 taskstore；可选改名     |
| `/task run`           | 跑当前草稿                    |
| `/task run <name|id>` | 跑已保存任务（以任务持久化 `Mode` 为准） |
| `/task del <name|id>` | 删除永久任务                   |




### 6.6 任务引用解析

`findTask` 顺序：精确 id → 精确名（EqualFold）→ 唯一前缀 id / 名称子串。多匹配报 `ambiguous`。

### 6.7 domain vs list vs expect


| 目标       | 用途                          |
| -------- | --------------------------- |
| `domain` | 单域名 × 多 DNS（常配 compare）     |
| `list`   | 批量清单文件（`job.ParseListFile`） |
| 二者       | **互斥**；保存时必须设其一             |


**expect**：任务可持久化 `mode=expect`。

- **list /batch**：清单行 `domain type [tag] [expected]`；第 4 列预期，多项 `,` 分隔；缺列/空 → 运行时判「不符合预期」（不报错）。
- **domain 目标**：必须设置 `expected=`（向导/`/task set`/编辑菜单）；保存与 `/run` 前校验，缺预期直接报错。
- **敲域名**：`example.com A expected=1.2.3.4` 或四列同款；无预期则报错，**不** silent dig。
- 判定：实际答案均落在预期集合内（actual ⊆ expected）→ `符合预期`，否则 → `不符合预期`。第 3 列标签忽略。

多 DNS 导出：query/expect CSV 每 DNS 一行（含 DNS 列）；compare≥3 每「基准 vs 对方」一行，并带「总对比结果」列。

---



## 7. 临时批量 `/batch`

```text
/batch            # 进入多行编辑
/batch clear      # 清除内存中的临时批量
```

- 文本与 items **只驻留 TUI 内存**，不写 taskstore / `~/.dnsprobe`。
- 解析：`job.ParseList`；每行至少 `domain type`。
- 执行模式跟随会话（草稿 sync）：query / compare / expect；watch 会话下跑完会按快照重开。



### 7.1 多行编辑键位


| 键                       | 动作                      |
| ----------------------- | ----------------------- |
| **Enter**               | 换行（继续编辑）                |
| **F2** 或 **Ctrl+D**     | 解析并**立即运行**             |
| **Ctrl+O** 或 **Ctrl+S** | 仅载入 items，提示用 `/run` 执行 |
| **Ctrl+L**              | 清空编辑缓冲                  |
| **Esc** / Ctrl+C        | 取消                      |


提示行格式：`domain type [tag] [expected]`。

详情 CSV 任务名固定为 `batch`，文件名形如 `query-batch-*` / `compare-batch-*` / `expect-batch-*`。

---



## 8. 高级与默认值速查


| 项             | 默认         | 设置方式                                               |
| ------------- | ---------- | -------------------------------------------------- |
| Timeout       | `1s`       | `/timeout`、`/adv` 打印、行内 `+time=`                   |
| MaxRetries    | `2`        | `/retries`、行内 `+tries=`                            |
| RetryInterval | `100ms`    | `/adv retry-interval=`                             |
| EDNS payload  | `4096`     | `/adv edns=`、行内 `+bufsize=` / `+edns=` / `+noedns` |
| RD            | on         | `/rd`、行内 `+norec`/`+recurse`                       |
| TCP           | off        | `/tcp`、行内 `+tcp`/`+notcp`                          |
| Workers       | `20`       | `/workers`                                         |
| QPS           | `10` / DNS | `/qps`、行内 `+qps=`                                  |
| Format        | `default`  | `/format`、行内 `+brief`/`+full`                      |
| Interval      | off        | `/interval`、行内 `+interval=`                        |


```text
/adv
/adv retry-interval=200ms edns=1232
```

---



## 9. 输出路径


| 规则           | 说明                                                                           |
| ------------ | ---------------------------------------------------------------------------- |
| 敲域名默认        | **不写 CSV**（与 dig 一致）；`+detail` 或 `/detail on` 才写                            |
| `/run` 等          | 自动写 CSV；**watch/continuous** 为**同一文件按轮追加**（含 `轮次`/`时间` 列），不每轮新建 |
| watch 模型         | 引擎内 `Continuous` 单 job 循环至 `/stop`；TUI **不再** Finished 后重入 Start           |
| 默认目录         | **进程 cwd**（`outdir` 为空）                                                      |
| 自定义          | `/outdir /path` 或任务 `outdir=`（只定目录）                                          |
| 文件名          | `{mode}-{name}-{YYYYMMDD-HHMMSS}.csv`（watch 会话启动时生成一次）                   |
| `detail:` 日志 | 首轮追加成功或任务结束写出成功后打印；失败或无完成行则提示未写出                         |
| 取消           | Continuous 取消**不**再 Create 截断已追加内容                                        |


禁止默认写到 `~/.dnsprobe/runs`。

---



## 10. TUI **没有**的功能

以下请用外部 CLI，不要在 TUI 里找菜单：

```bash
./dnsprobe config path              # 打印配置根目录
./dnsprobe config clean --yes       # 备份后清理 ~/.dnsprobe
./dnsprobe clean-config             # clean --yes 别名
```

也不包含：DoH/DoT、DNSSEC 校验、自绘全屏文件选择器、alt-screen viewport。

---



## 11. 快速示例

```text
/dns 8.8.8.8,1.1.1.1
# query + 双 DNS → job 扇出（不改会话 type）
example.com AAAA

# 行内 @ 只 dig 该服务器（一次性）
example.com @1.1.1.1 A

/mode compare
example.com A

/mode expect
example.com A expected=93.184.216.34
/list ./example-list.txt
/run

/batch
# （多行粘贴 domain type [tag] expected）
# F2 立即跑，或 Ctrl+S 后 /run；持久化请 /task new + list

/task new my-task
# 向导：mode=3 expect，target=2 list，填路径与 outdir
/task run my-task

/dns 8.8.8.8
example.com +brief +watch +interval=2s +qps=5
/stop
```

---



## 12. 命令名交叉核对（源码）

`handleSlash` 识别的命令名与别名：

`help`/`h`/`?` · `dns` · `type`/`t` · `rd` · `tcp` · `timeout` · `retries` · `workers`/`w` · `mode` · `format` · `interval` · `qps`/`rate` · `batch` · `list`/`file` · `open` · `outdir`/`output`/`output_dir` · `adv`/`advanced` · `save` · `compare`/`vs` · `task` · `run` · `stop` · `clear`

`/task` 子命令：`list`/`ls`/`panel` · `new` · `edit`/`load` · `set` · `save` · `run` · `del`/`delete`/`rm`