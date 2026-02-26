#!/usr/bin/env bash
set -euo pipefail

CLOUDFLARED_DIR="${HOME}/.cloudflared"
PID_FILE="${CLOUDFLARED_DIR}/cloudflared.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "未找到 PID 文件: $PID_FILE"
  echo "如果是前台运行，请直接在对应终端按 Ctrl+C 停止。"
  exit 1
fi

PID="$(cat "$PID_FILE" 2>/dev/null || true)"
if [[ -z "${PID:-}" ]]; then
  echo "PID 文件为空，无法停止。"
  rm -f "$PID_FILE"
  exit 1
fi

if ! kill -0 "$PID" 2>/dev/null; then
  echo "进程不存在 (PID: $PID)，已清理 PID 文件。"
  rm -f "$PID_FILE"
  exit 0
fi

kill "$PID"

for _ in {1..10}; do
  if ! kill -0 "$PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if kill -0 "$PID" 2>/dev/null; then
  kill -9 "$PID"
fi

rm -f "$PID_FILE"
echo "已停止 cloudflared (PID: $PID)"
