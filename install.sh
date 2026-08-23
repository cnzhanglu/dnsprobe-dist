#!/usr/bin/env bash
# 从 dnsprobe-dist 最新 Release 安装或更新 dnsprobe。
set -euo pipefail

REPO="${DNSPROBE_RELEASE_REPO:-cnzhanglu/dnsprobe-dist}"
INSTALL_BIN="${DNSPROBE_INSTALL_BIN:-/usr/local/bin/dnsprobe}"
SERVICE="${DNSPROBE_SERVICE:-}"

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  FreeBSD) os=freebsd ;;
  *) echo "暂不支持的系统：$(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  i386|i486|i586|i686) arch=386 ;;
  *) echo "暂不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac

asset="dnsprobe-$os-$arch"
base="https://github.com/$REPO/releases/latest/download"
install_dir="$(dirname "$INSTALL_BIN")"
mkdir -p "$install_dir"
tmp_dir="$(mktemp -d "$install_dir/.dnsprobe-install.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

checksum() {
  case "$os" in
    darwin) shasum -a 256 "$1" | awk '{print $1}' ;;
    freebsd) sha256 -q "$1" ;;
    *) sha256sum "$1" | awk '{print $1}' ;;
  esac
}

echo "==> 检查 $REPO latest/$asset"
curl -fL --retry 3 --retry-all-errors -o "$tmp_dir/SHA256SUMS" "$base/SHA256SUMS"
expected="$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print $1; exit }' "$tmp_dir/SHA256SUMS")"
[[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "SHA256SUMS 中缺少 $asset" >&2; exit 1; }

if [[ -f "$INSTALL_BIN" ]] && [[ "$(checksum "$INSTALL_BIN")" == "$expected" ]]; then
  echo "==> 已是最新版本（sha256=${expected}）"
  exit 0
fi

curl -fL --retry 3 --retry-all-errors -o "$tmp_dir/$asset" "$base/$asset"
[[ "$(checksum "$tmp_dir/$asset")" == "$expected" ]] || { echo "SHA-256 校验失败" >&2; exit 1; }
chmod 0755 "$tmp_dir/$asset"
"$tmp_dir/$asset" help >/dev/null

if [[ -z "$SERVICE" ]]; then
  mv "$tmp_dir/$asset" "$INSTALL_BIN"
  echo "==> 安装成功：${INSTALL_BIN}（sha256=${expected}）"
  exit 0
fi

command -v systemctl >/dev/null || { echo "配置 DNSPROBE_SERVICE 需要 systemd" >&2; exit 1; }
backup="$INSTALL_BIN.backup"
had_old=0
if [[ -f "$INSTALL_BIN" ]]; then cp -p "$INSTALL_BIN" "$backup"; had_old=1; fi
systemctl stop "$SERVICE"
mv "$tmp_dir/$asset" "$INSTALL_BIN"
if systemctl start "$SERVICE" && systemctl is-active --quiet "$SERVICE"; then
  [[ "$had_old" -eq 0 ]] || rm -f "$backup"
  echo "==> 更新成功并已启动 ${SERVICE}（sha256=${expected}）"
else
  echo "启动失败，恢复旧版本" >&2
  if [[ "$had_old" -eq 1 ]]; then mv "$backup" "$INSTALL_BIN"; else rm -f "$INSTALL_BIN"; fi
  systemctl start "$SERVICE" || true
  exit 1
fi
