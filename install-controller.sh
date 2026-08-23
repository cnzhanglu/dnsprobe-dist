#!/usr/bin/env bash
# 从 dnsprobe-dist 安装或更新 Controller；需以 root 运行。
set -euo pipefail

REPO="${DNSPROBE_RELEASE_REPO:-cnzhanglu/dnsprobe-dist}"
VERSION="${DNSPROBE_VERSION:-latest}"
INSTALL_ROOT="${DNSPROBE_CONTROLLER_INSTALL_ROOT:-/opt/dnsprobe-controller}"
DATA_DIR="${DNSPROBE_CONTROLLER_DATA_DIR:-/var/lib/dnsprobe-controller}"
ENV_DIR="${DNSPROBE_CONTROLLER_ENV_DIR:-/etc/dnsprobe-controller}"
LISTEN_ADDR="${DNSPROBE_CONTROLLER_LISTEN_ADDR:-127.0.0.1:2082}"
SERVICE="dnsprobe-controller.service"

[[ "$(id -u)" -eq 0 ]] || { echo "请以 root 运行" >&2; exit 1; }
[[ "$(uname -s)" == "Linux" ]] || { echo "仅支持 Linux" >&2; exit 1; }
command -v curl >/dev/null || { echo "缺少 curl" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "缺少 sha256sum" >&2; exit 1; }
command -v systemctl >/dev/null || { echo "缺少 systemd" >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac

asset="dnsprobe-controller-linux-$arch"
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

getent group dnsprobe-controller >/dev/null || groupadd --system dnsprobe-controller
id dnsprobe-controller >/dev/null 2>&1 || useradd --system --gid dnsprobe-controller --home-dir "$DATA_DIR" --shell /usr/sbin/nologin dnsprobe-controller
install -d -o root -g root -m 0755 "$INSTALL_ROOT/bin"
install -d -o dnsprobe-controller -g dnsprobe-controller -m 0700 "$DATA_DIR"
install -d -o root -g dnsprobe-controller -m 0750 "$ENV_DIR"
install -o root -g root -m 0755 "$tmp_dir/$asset" "$INSTALL_ROOT/bin/dnsprobe-controller"

if [[ ! -f "$ENV_DIR/controller.env" ]]; then
  printf 'DNSPROBE_CONTROLLER_DATA=%s\n' "$DATA_DIR" > "$ENV_DIR/controller.env"
  chown root:dnsprobe-controller "$ENV_DIR/controller.env"
  chmod 0640 "$ENV_DIR/controller.env"
fi

cat > "/etc/systemd/system/$SERVICE" <<EOF
[Unit]
Description=dnsprobe multi-node controller
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=dnsprobe-controller
Group=dnsprobe-controller
EnvironmentFile=$ENV_DIR/controller.env
WorkingDirectory=$DATA_DIR
ExecStart=$INSTALL_ROOT/bin/dnsprobe-controller serve --addr $LISTEN_ADDR
Restart=on-failure
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
echo "Controller 已安装：$INSTALL_ROOT/bin/dnsprobe-controller（监听 $LISTEN_ADDR）"
echo "初始化管理员：DNSPROBE_CONTROLLER_DATA=$DATA_DIR $INSTALL_ROOT/bin/dnsprobe-controller admin create <名称>"
