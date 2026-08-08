# Web API 概要（`/api/v1`）

嵌入式服务由 `dnsprobe serve` 提供。鉴权与绑定规则见 README「Web」。本文与 `internal/web` 实现对齐；字段可扩展，旧键保留兼容。

**主字段**：DNS 用 `servers`（数组或逗号串）；`dns1`/`dns2` 为旧 shim（有 `servers` 时优先 `servers`）。QPS 省略默认 **10**；显式 `0` 表示不限。

---

## Jobs

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/v1/jobs` | 列出进程内近期 jobs（内存；重启丢失） |
| `POST` | `/api/v1/jobs` | 创建；JSON 或 multipart；`201 {"id"}` |
| `GET` | `/api/v1/jobs/{id}` | 状态；`?include=results` 带结果数组 |
| `GET` | `/api/v1/jobs/{id}/events` | SSE 进度事件 |
| `GET` | `/api/v1/jobs/{id}/export.csv` | 下载 CSV |
| `GET` | `/api/v1/jobs/{id}/export.json` | 下载 JSON |
| `POST` | `/api/v1/jobs/{id}/cancel` | 取消（含 Continuous） |

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
| `GET` | `/api/v1/tasks?name=` | 按名称取一条 |
| `GET` | `/api/v1/tasks/{id}` | 详情 |
| `POST` | `/api/v1/tasks` | 创建；`201` + Task |
| `PUT`/`PATCH` | `/api/v1/tasks/{id}` | 更新（未传字段保留） |
| `DELETE` | `/api/v1/tasks/{id}` | 删除 |
| `POST` | `/api/v1/tasks/{id}/run` | 生成 job；`201 {"id": jobId}` |

### 写入字段（对齐 `taskstore.Task`）

`name`, `servers`, `mode`, `domain` **XOR**（`list_path` | 内联 `list`）, `expected`, `type`, `options` 或扁平 `timeout_ms`…, `output_dir`, `workers`。

- 内联 `list`：服务端写入 `tasks/lists/<id>.txt` 并填 `list_path`。
- `list_path`：表示**服务端本地路径**。
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

## 明确不做

- 不暴露改 `config.json` / `config clean` 的通用 API。
- 不做完整 dig 行解析（那是 CLI `query`）。
- jobs 仅进程内存；永久定义用 tasks。
