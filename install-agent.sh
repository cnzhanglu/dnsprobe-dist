#!/usr/bin/env bash
# 从 dnsprobe-dist 安装或更新 Agent；需以 root 运行。
set -euo pipefail

REPO="${DNSPROBE_RELEASE_REPO:-cnzhanglu/dnsprobe-dist}"
VERSION="${DNSPROBE_VERSION:-latest}"
INSTALL_ROOT="${DNSPROBE_AGENT_INSTALL_ROOT:-/opt/dnsprobe-agent}"
DATA_DIR="${DNSPROBE_AGENT_DATA_DIR:-/var/lib/dnsprobe-agent}"
ENV_DIR="${DNSPROBE_AGENT_ENV_DIR:-/etc/dnsprobe-agent}"
CONTROLLER_URL="${DNSPROBE_CONTROLLER:-}"
NODE_TOKEN="${DNSPROBE_CONTROLLER_TOKEN:-}"
NODE_NAME="${DNSPROBE_NODE_NAME:-}"
SERVICE="dnsprobe-agent.service"

[[ "$(id -u)" -eq 0 ]] || { echo "请以 root 运行" >&2; exit 1; }
[[ "$(uname -s)" == "Linux" ]] || { echo "仅支持 Linux" >&2; exit 1; }
command -v curl >/dev/null || { echo "缺少 curl" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "缺少 sha256sum" >&2; exit 1; }
command -v systemctl >/dev/null || { echo "缺少 systemd" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  i386|i486|i586|i686) arch=386 ;;
  *) echo "不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac

asset="dnsprobe-agent-linux-$arch"
if [[ "$VERSION" == "latest" ]]; then
  base="https://github.com/$REPO/releases/latest/download"
else
  base="https://github.com/$REPO/releases/download/$VERSION"
fi
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fL --retry 3 --retry-all-errors -o "$tmp_dir/SHA256SUMS" "$base/SHA256SUMS"
expected="$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print $1; exit }' "$tmp_dir/SHA256SUMS")"
[[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "SHA256SUMS 中缺少 $asset" >&2; exit 1; }
curl -fL --retry 3 --retry-all-errors -o "$tmp_dir/$asset" "$base/$asset"
actual="$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')"
[[ "$actual" == "$expected" ]] || { echo "SHA-256 校验失败" >&2; exit 1; }

getent group dnsprobe-agent >/dev/null || groupadd --system dnsprobe-agent
id dnsprobe-agent >/dev/null 2>&1 || useradd --system --gid dnsprobe-agent --home-dir "$DATA_DIR" --shell /usr/sbin/nologin dnsprobe-agent
install -d -o root -g root -m 0755 "$INSTALL_ROOT/bin"
install -d -o dnsprobe-agent -g dnsprobe-agent -m 0700 "$DATA_DIR"
install -d -o root -g dnsprobe-agent -m 0750 "$ENV_DIR"
# 同目录原子替换，避免直接截断正在运行的 ELF 在部分文件系统上留下损坏文件。
install -o root -g root -m 0755 "$tmp_dir/$asset" "$INSTALL_ROOT/bin/dnsprobe-agent.new"
mv -f "$INSTALL_ROOT/bin/dnsprobe-agent.new" "$INSTALL_ROOT/bin/dnsprobe-agent"

if [[ ! -f "$ENV_DIR/agent.env" ]]; then
  [[ -n "$CONTROLLER_URL" && -n "$NODE_TOKEN" && -n "$NODE_NAME" ]] || {
    echo "首次安装必须设置 DNSPROBE_CONTROLLER、DNSPROBE_CONTROLLER_TOKEN、DNSPROBE_NODE_NAME" >&2
    exit 1
  }
  {
    printf 'DNSPROBE_CONTROLLER=%s\n' "$CONTROLLER_URL"
    printf 'DNSPROBE_CONTROLLER_TOKEN=%s\n' "$NODE_TOKEN"
    printf 'DNSPROBE_NODE_NAME=%s\n' "$NODE_NAME"
  } > "$ENV_DIR/agent.env"
  chown root:dnsprobe-agent "$ENV_DIR/agent.env"
  chmod 0640 "$ENV_DIR/agent.env"
fi

cat > "/etc/systemd/system/$SERVICE" <<EOF
[Unit]
Description=dnsprobe remote probe agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=dnsprobe-agent
Group=dnsprobe-agent
EnvironmentFile=$ENV_DIR/agent.env
WorkingDirectory=$DATA_DIR
ExecStart=$INSTALL_ROOT/bin/dnsprobe-agent
Restart=always
RestartSec=5s
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=$DATA_DIR
CapabilityBoundingSet=
LockPersonality=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE"
systemctl restart "$SERVICE"
echo "Agent 已安装：$INSTALL_ROOT/bin/dnsprobe-agent"
echo "配置文件：$ENV_DIR/agent.env"
