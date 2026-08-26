# Web API 概要（`/api/v1`）

嵌入式服务由 `dnsprobe serve` 提供。鉴权与绑定规则见 README「Web」。本文与 `internal/web` 实现对齐；字段可扩展，旧键保留兼容。

**主字段**：DNS 用 `servers`（数组或逗号串）；`dns1`/`dns2` 为旧 shim（有 `servers` 时优先 `servers`）。QPS 省略默认 **10**；显式 `0` 表示不限。

---

## serve 公网地址

`GET /api/v1/public-ip` 返回运行 serve 的服务器出口公网 IPv4/IPv6。配置 Token 时该接口与其他 `/api/*` 一样需要 Bearer 鉴权；无 Token 的 localhost 模式免认证。

```json
{
  "ipv4": {"address":"198.51.100.8","status":"ok","checked_at":"2026-08-26T10:00:00Z","stale":false},
  "ipv6": {"status":"unavailable","checked_at":"2026-08-26T10:00:05Z","stale":false,"error":"查询失败: ..."}
}
```

- 状态为 `pending`、`ok`、`unavailable` 或 `disabled`；IPv4/IPv6 独立处理。
- 成功地址缓存 30 分钟。首次失败后不再自动访问对应端点，`GET /api/v1/public-ip?refresh=1` 可手动重试。
- 曾成功的地址在后续查询失败时保留，并设置 `stale: true`。
- 默认端点为 Cloudflare 官方的 `https://ipv4.icanhazip.com` 与 `https://ipv6.icanhazip.com`；serve 参数 `--public-ipv4-url` / `--public-ipv6-url` 或环境变量 `DNSPROBE_PUBLIC_IPV4_URL` / `DNSPROBE_PUBLIC_IPV6_URL` 可覆盖，值为 `off` 时禁用。
- 外部查询失败只影响该接口，不影响 serve 启动、健康状态或拨测任务。

---

## Jobs

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/v1/jobs` | 列出任务：内存（运行中/近期）优先，持久库补充历史；`rows` 为记录行数 |
| `POST` | `/api/v1/jobs` | 创建；JSON 或 multipart；`201 {"id"}` |
| `GET` | `/api/v1/jobs/{id}` | 状态；`?include=results` 带结果数组（持久库任务返回全历史，每行含 `at` 时间） |
| `GET` | `/api/v1/jobs/{id}/events` | SSE 进度事件 |
| `GET` | `/api/v1/jobs/{id}/export.csv` | 下载 CSV（全历史，行尾「时间」列；无轮次概念） |
| `GET` | `/api/v1/jobs/{id}/export.json` | 下载 JSON（全历史，行含 `at`） |
| `POST` | `/api/v1/jobs/{id}/cancel` | 取消（含 Continuous） |
| `DELETE` | `/api/v1/jobs/{id}` | 手动清理：内存 + 持久库 + SSE 缓冲 |

> **持久库**（`dnsprobe serve --store`，默认 `~/.dnsprobe/runs.db`，bbolt 单文件）：批量/持续任务自动落库，可回查全历史并带每行拨测时间（`at`）；单条域名查询不落库。`--store off` 关闭（退回纯内存）。持久库默认 7 天自动清理（`--store-retention` 可调，`0` 不清理）。
>
> job 列表/详情附带 `name`（拨测对象：首条域名 + 条数）、`rows`（展开后记录行数，多 DNS 扇出每行）；由永久任务触发的 job 额外带 `task_name`/`task_id`（来源任务）。记录模型为「一行结果 + 时间戳」，不引入轮次。
>
> **内存保留策略**：job 记录默认最多保留 **200** 个，结束态超过 **24h** 自动淘汰（`--job-max / --job-max-age` 可调，设 `0` 不限制）；运行中的任务不受影响。

### `POST /jobs` 常用字段

| 字段 | 类型 | 语义 |
|------|------|------|
| `servers` | `string[]` 或逗号串 | 主 DNS 列表 |
| `dns1` / `dns2` | string | 旧 shim |
| `mode` | string | `query` / `compare` / `expect`（`vs`/`check` 别名） |
| `name` + `type` | string | 单域名目标（`type` 默认 `A`） |
| `expected` | string | domain + expect **必填** |
| `list` / 文件 | string / multipart `file` | 列表正文 |
| `qps` | number | 默认 10；**Web 上限 100**（1–100，`0`=不限仅 CLI/TUI） |
| `continuous` | bool | watch |
| `interval_ms` | number | 轮间间隔 |
| `workers` | number | 并发（服务端默认同 job）；**Web 上限 100** |

列表/详情响应新增字段：`name`（拨测对象，批量取首条+条数）、`rows`（展开后记录行数）、`task_name`/`task_id`（任务执行来源）。
| `timeout_ms` / `retries` / `retry_interval_ms` / `rd` / `tcp` / `edns` / `subnet` | | 协议选项 |
| `output_dir` | string | 可选：在**服务端**该目录写详情 CSV（本机场景；默认仅内存供 export） |

OpenAPI 风格片段：

```yaml
paths:
  /api/v1/jobs:
    get:
      summary: 列出内存中的 jobs
    post:
      summary: 创建拨测 job
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                mode: { type: string, enum: [query, compare, expect] }
                servers:
                  oneOf:
                    - { type: array, items: { type: string } }
                    - { type: string }
                name: { type: string }
                type: { type: string }
                expected: { type: string }
                list: { type: string }
                qps: { type: number }
                continuous: { type: boolean }
                interval_ms: { type: integer }
                workers: { type: integer }
                dns1: { type: string }
                dns2: { type: string }
      responses:
        "201":
          description: '{ "id": "<jobId>" }'
  /api/v1/jobs/{id}:
    get:
      parameters:
        - name: include
          in: query
          schema: { type: string, enum: [results] }
  /api/v1/jobs/{id}/events:
    get:
      summary: SSE
  /api/v1/jobs/{id}/export.csv:
    get: {}
  /api/v1/jobs/{id}/export.json:
    get: {}
  /api/v1/jobs/{id}/cancel:
    post: {}
```

---

## Tasks（永久任务，服务端 `~/.dnsprobe/tasks`）

远程操作即改服务端家目录任务库；无多用户隔离。

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/v1/tasks` | 列表 |
| `GET` | `/api/v1/tasks?name=` | 按名称取一条；Web 托管列表附带 `list` 正文 |
| `GET` | `/api/v1/tasks/{id}` | 详情；Web 托管列表附带 `list` 正文 |
| `POST` | `/api/v1/tasks` | 创建；`201` + Task |
| `PUT`/`PATCH` | `/api/v1/tasks/{id}` | 更新（未传字段保留） |
| `DELETE` | `/api/v1/tasks/{id}` | 删除 |
| `POST` | `/api/v1/tasks/{id}/run` | 生成 job；`201 {"id": jobId}` |

### 写入字段（对齐 `taskstore.Task`）

`name`, `servers`, `mode`, `domain` **XOR**（`list_path` | 内联 `list`）, `expected`, `type`, `options` 或扁平 `timeout_ms`…, `output_dir`, `workers`。

- 内联 `list`：服务端写入 `tasks/lists/<id>.txt` 并填 `list_path`。
- `list_path`：表示**服务端本地路径**。
- `list` 仅在单任务详情且 `list_path` 为该任务自己的 `tasks/lists/<id>.txt` 时返回；任务列表及外部 `list_path` 不返回文件正文。
- `continuous` **不**写入任务；仅在 `…/run` 的 body 覆盖。

### `POST …/run` body（可选覆盖）

```json
{ "qps": 5, "continuous": true, "interval_ms": 2000, "workers": 10 }
```

省略 `qps` 时默认 10；Web 上限 qps≤100、workers≤100。

```yaml
paths:
  /api/v1/tasks:
    get: { summary: 列表；?name= 按名查询 }
    post: { summary: 创建永久任务 }
  /api/v1/tasks/{id}:
    get: {}
    put: {}
    patch: {}
    delete: {}
  /api/v1/tasks/{id}/run:
    post:
      summary: 从任务启动 job
      responses:
        "201":
          description: '{ "id": "<jobId>" }'
```

---

---

## HTTP/HTTPS 探测（`POST /api/v1/httpprobe`）

同步执行一批地址并返回 `results`；单次最多 1000 个地址。`list` 为一行一个 URL（省略 scheme 默认 HTTPS），也可传 `targets` 数组。`protocol` 当前接受 `http` / `https`，作为后续协议实现的分发入口。

```json
{
  "protocol": "http",
  "list": "https://example.com/health\napi.example.com/status",
  "method": "GET",
  "host": "origin.example.com",
  "headers": {"X-Probe": "web"},
  "body": "",
  "timeout_ms": 10000,
  "workers": 20,
  "follow_redirects": false,
  "insecure_tls": false
}
```

结果字段包括 `url`、`final_url`、`protocol`、`status_code`、`status`、`latency_ms`、`body_bytes`、`body_preview`、`body_truncated`、`body_binary`、`content_type`、`server`、`error`、`at`。文本响应最多预览前 16 KiB；超长或二进制响应会明确标记，避免批量任务占用过多内存。

当 `host` 非空时，共享引擎会同时将其写入 HTTP Host 头和 TLS ClientHello SNI（自动去掉端口）。因此可用 IP 建立连接，并按指定域名完成虚拟主机路由与证书校验；Web、TUI、CLI 语义一致。

## Portprobe（端口探测，`/api/v1/portprobe`）

与 DNS job 完全独立的进程内会话注册表（纯内存，**不进 runs.db / SSE hub**）：`POST` 创建后在后台跑，前端/脚本轮询 `GET` 详情。内存最多保留最近 **100** 个会话，超出淘汰最旧结束态。

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/api/v1/portprobe` | 创建会话；`201 {"id"}` |
| `GET` | `/api/v1/portprobe` | 会话列表（新建在前，不含 results） |
| `GET` | `/api/v1/portprobe/sources` | 本机可探测源 IP（`{sources:[{ip,iface,is_v6}]}`，前端勾选用） |
| `GET` | `/api/v1/portprobe/{id}` | 会话详情（含 `results`） |
| `POST` | `/api/v1/portprobe/{id}/cancel` | 取消（已完成结果保留） |
| `GET` | `/api/v1/portprobe/{id}/export.csv` | 长表 CSV 下载 |

### `POST /portprobe` body

| 字段 | 类型 | 语义 | 上限/默认 |
|------|------|------|-----------|
| `targets` | `[{ip,port,meta?}]` | 目标数组（与 `list` 二选一） | ≤5000 |
| `list` | string | 目标文本（`ip,port[,备注]` 行；**支持逗号/Tab/空格分隔，自动探测**） | ≤5000 行 |
| `sources` | `string[]` | 源 IP（可选，与 `sources_raw` 二选一）；**缺省为空=默认路由模式**（不绑定源，`results[].source_ip` 记录内核实际出口） | ≤16 |
| `sources_raw` | string | 源 IP 字符串（空格/英文逗号/Tab；**拒中文分隔符**） | ≤16 |
| `workers` | int | 并发 | 1–200（默认 200） |
| `timeout_ms` | int | 单次超时 | 1–10000（默认 3000） |
| `retries` | int | 重试次数（不含首次） | 0–10（默认 3） |
| `retry_interval_ms` | int | 重试间隔 | 0–60000（默认 1000） |
| `node` | string | 节点名 | 缺省主机名 |
| `qps` | number | 每源 IP QPS | 0=不限速（默认） |

详情/列表响应含：`id, status(running/finished/cancelled/error), node, created_at, started_at, finished_at, error, total, done, stats{OK,FAIL,TIMEOUT,SKIP}, inconsistent, targets, sources, results`。`results[]` 字段：`status, latency_ms, error, local_port, source_ip, at`。`port=0` 走 ICMP ping（依赖系统 `ping`）。

---
## 明确不做

- 不暴露改 `config.json` / `config clean` 的通用 API。
- 不做完整 dig 行解析（那是 CLI `query`）。
- jobs 内存默认保留 200 个/24h；持久库（`~/.dnsprobe/runs.db`）保留 7 天且支持 DELETE 手动清理；永久定义用 tasks。
