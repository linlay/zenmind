#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/nginx-common.sh
source "${SCRIPT_DIR}/nginx-common.sh"

resolve_nginx_paths
require_nginx_binary

echo "OS: ${OS_NAME}"
echo "NGINX_CONF: ${NGINX_CONF}"
echo "PID_FILE: ${PID_FILE}"

nginx -t -c "${NGINX_CONF}"

if [[ -f "${PID_FILE}" ]]; then
  PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [[ -n "${PID:-}" ]] && kill -0 "${PID}" 2>/dev/null; then
    echo "nginx already running (PID: ${PID})."
    if [[ "${1:-}" == "--reload" ]]; then
      nginx -s reload -c "${NGINX_CONF}"
      echo "nginx reloaded."
    fi
    exit 0
  fi
fi

nginx -c "${NGINX_CONF}"
echo "nginx started."
