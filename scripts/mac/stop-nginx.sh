#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mac/nginx-common.sh
source "${SCRIPT_DIR}/nginx-common.sh"

resolve_nginx_paths
require_nginx_binary

echo "OS: ${OS_NAME}"
echo "NGINX_CONF: ${NGINX_CONF}"
echo "PID_FILE: ${PID_FILE}"

PID=""
if [[ -f "${PID_FILE}" ]]; then
  PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
fi

if [[ -n "${PID:-}" ]] && ! kill -0 "${PID}" 2>/dev/null; then
  echo "stale PID file detected, cleaning: ${PID_FILE}"
  rm -f "${PID_FILE}"
  PID=""
fi

if nginx -s quit -c "${NGINX_CONF}" 2>/dev/null; then
  echo "sent graceful quit signal."
else
  if [[ -z "${PID:-}" ]]; then
    echo "nginx is not running."
    exit 0
  fi
  echo "graceful quit failed, sending TERM to PID ${PID}."
  kill "${PID}" 2>/dev/null || true
fi

for _ in {1..10}; do
  if [[ -n "${PID:-}" ]] && kill -0 "${PID}" 2>/dev/null; then
    sleep 1
    continue
  fi
  break
done

if [[ -n "${PID:-}" ]] && kill -0 "${PID}" 2>/dev/null; then
  echo "process still alive, sending KILL to PID ${PID}."
  kill -9 "${PID}"
fi

rm -f "${PID_FILE}"
echo "nginx stopped."
