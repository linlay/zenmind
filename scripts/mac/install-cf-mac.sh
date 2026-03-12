#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew 未安装。先安装 brew: https://brew.sh/"
  exit 1
fi

echo "==> Installing/Upgrading cloudflared via Homebrew..."
brew update >/dev/null
brew install cloudflare/cloudflare/cloudflared 2>/dev/null || brew upgrade cloudflared

echo "==> cloudflared version:"
cloudflared --version

echo
echo "==> Creating config directories..."
mkdir -p "$HOME/.cloudflared"

echo
echo "Done."
echo "Next:"
echo "  1) 如 tunnel 尚未创建，先运行: ./scripts/mac/create-cf-tunnel-config-sysadmin.sh"
echo "  2) 再运行: ./scripts/mac/setup-cf-tunnel.sh"
echo "     会执行 route dns，并生成 ~/.cloudflared/config.yml"
