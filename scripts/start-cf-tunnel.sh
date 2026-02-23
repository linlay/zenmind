#!/usr/bin/env bash
set -euo pipefail

CLOUDFLARED_DIR="${HOME}/.cloudflared"
CONFIG_FILE="${CLOUDFLARED_DIR}/config.yml"
PID_FILE="${CLOUDFLARED_DIR}/cloudflared.pid"
LOG_FILE="/tmp/cloudflared-tunnel.log"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "未检测到 cloudflared。可用 Homebrew 安装："
  echo "  brew install cloudflare/cloudflare/cloudflared"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "未找到配置文件: $CONFIG_FILE"
  echo "请先运行 setup-cf-tunnel.sh 生成配置。"
  exit 1
fi

if [[ "${1:-}" == "--foreground" || "${1:-}" == "-f" ]]; then
  echo "前台启动：cloudflared tunnel --config \"$CONFIG_FILE\" run"
  exec cloudflared tunnel --config "$CONFIG_FILE" run
fi

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${OLD_PID:-}" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "cloudflared 已在运行 (PID: $OLD_PID)"
    exit 0
  fi
fi

mkdir -p "$CLOUDFLARED_DIR"
nohup cloudflared tunnel --config "$CONFIG_FILE" run >"$LOG_FILE" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"

echo "已后台启动 cloudflared (PID: $NEW_PID)"
echo "日志文件: $LOG_FILE"
echo "停止命令: ./scripts/stop-cf-tunnel.sh"
