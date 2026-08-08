# readline TUI 输出控制

## 目标

dnsprobe 使用 `github.com/reeflective/readline` 构建普通 REPL，不进入 alt-screen，也不维护固定高度 viewport。终端主缓冲是日志事实来源，因此结果可直接滚动、选中和复制，窗口缩放时由终端与 readline 共同处理重排。

## 输出模型

```text
query/job/watch goroutine
        │
        ▼
buffered eventCh ── 私有唤醒键
        │
        ▼
readline 主协程 ── appendLog ── readline.PrintTransientf
                                      │
                                      ├─ 日志进入主缓冲 scrollback
                                      └─ readline 重绘提示与当前输入
```

- 执行协程不得直接写终端；事件先进入 `eventCh`，保持行顺序并避免多写者交叉。
- readline 正在读输入时使用 `PrintTransientf`，把异步日志写在输入行上方并重绘。
- 异步唤醒：Unix 用 readline `RequestRefresh`（wake pipe）；Windows 上该 API 为空实现，改由 `WriteConsoleInputW` 注入私有键 `\x1e`（`\C-^` → `dnsprobe-drain-events`）打断 `ReadConsoleInputW`。非控制台静默失败，退回下次按键再刷。
- 两次 `Readline` 之间的同步命令输出直接打印；下一轮由 readline 正常绘制提示。
- 不自行实现终端宽度探测、硬折行、resize 防抖、reflow 或 diff render。
- 日志和提示先复位 SGR，只设置前景语义色，不覆盖用户终端背景。

## Scrollback 与 `/clear`

- 日志始终写入主缓冲，不启用 mouse capture。
- 任务完成、取消、切换模式均不清日志；dig、任务和 watch 轮次后追加分隔行。
- `Model.logText` 只保留有限内存副本，供测试和 `/clear` 使用。
- `/clear` 清内存副本并输出提示，但不会尝试清终端已有 scrollback。

## readline 负责的终端行为

- raw mode 建立与恢复。
- bracketed paste。
- 窗口 resize 与多行输入重绘。
- 补全菜单和描述。
- ↑/↓ 历史、Ctrl+R 增量搜索。
- 普通 Ctrl+D EOF；批量编辑态临时改绑为“校验并运行”。

## Ctrl+C

1. 运行中优先取消 query/watch/job。
2. 有输入时由 readline 返回并清空当前行。
3. 第一次按下只进入 2 秒退出待确认态。
4. 2 秒内第二次按下退出并由 readline 恢复终端。

## 验收

- 长任务期间继续输入时，事件输出不破坏当前编辑内容。
- 缩放终端后提示与多行输入无残影，历史 scrollback 不丢失。
- 任务结束后结果仍可通过终端原生方式复制。
- `/clear` 后旧 scrollback 仍可回看。
- 退出、Ctrl+C、Ctrl+D 后终端模式恢复。
- `go test ./...`、`go build ./cmd/dnsprobe` 通过。
