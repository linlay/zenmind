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
echo "  1) 运行: cloudflared tunnel login"
echo "     会打开浏览器让你选择 zone 并授权，证书会写入 ~/.cloudflared/"
echo "  2) 然后用 create 脚本创建 tunnel"