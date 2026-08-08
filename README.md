# dnsprobe 发布仓库（二进制 + 使用文档）

> 源码为**私有仓库**，不在此开放；本仓库只提供编译好的可执行文件与使用文档。

## 下载

到 [Releases](https://github.com/cnzhanglu/dnsprobe-dist/releases) 选择对应平台：

| 平台 | 文件 |
|------|------|
| macOS (Apple Silicon) | `dnsprobe-darwin-arm64` |
| macOS (Intel) | `dnsprobe-darwin-amd64` |
| Linux x86_64 | `dnsprobe-linux-amd64` |
| Linux ARM64 | `dnsprobe-linux-arm64` |
| Linux 386 | `dnsprobe-linux-386` |
| Windows x64 | `dnsprobe-windows-amd64.exe` |
| Windows ARM64 | `dnsprobe-windows-arm64.exe` |
| FreeBSD x86_64 | `dnsprobe-freebsd-amd64` |

每个 Release 附 `SHA256SUMS`，下载后用以下命令校验：

```bash
# macOS
shasum -a 256 -c SHA256SUMS
# Linux / Windows(可配合 git-bash 或 PowerShell Get-FileHash)
sha256sum -c SHA256SUMS
```

## 使用文档

- [使用说明（拨测列表格式 / CLI / TUI / Web）](USAGE.md)
- [CLI 命令参考](CLI_COMMANDS.md)
- [TUI 命令参考](TUI_COMMANDS.md)
- [TUI 输出控制](TUI_OUTPUT_CONTROL.md)
- [Web API](docs/api.md)

> 文档随每次 Release 自动同步更新；使用中如有问题，请联系维护者（源码仓库为私有）。
