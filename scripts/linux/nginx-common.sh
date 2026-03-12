#!/usr/bin/env bash
set -euo pipefail

default_nginx_dir() {
  if [[ -d /etc/nginx ]]; then echo "/etc/nginx"; return 0; fi
  if [[ -d /usr/local/etc/nginx ]]; then echo "/usr/local/etc/nginx"; return 0; fi
  echo "/etc/nginx"
}

default_run_dir() {
  echo "/var/run"
}

extract_pid_file_from_conf() {
  local conf_file="$1"
  if [[ ! -f "${conf_file}" ]]; then
    return 0
  fi
  awk 'tolower($1)=="pid"{gsub(/;/, "", $2); print $2; exit}' "${conf_file}"
}

resolve_nginx_paths() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "ERROR: scripts/linux/nginx-common.sh only supports Linux or WSL." >&2
    exit 1
  fi
  NGINX_DIR="${NGINX_DIR:-$(default_nginx_dir)}"
  if [[ -z "${NGINX_DIR}" ]]; then
    echo "ERROR: Unsupported OS. Please set NGINX_DIR/NGINX_CONF manually." >&2
    exit 1
  fi
  NGINX_CONF="${NGINX_CONF:-${NGINX_DIR}/nginx.conf}"
  RUN_DIR="${RUN_DIR:-$(default_run_dir)}"
  if [[ -z "${RUN_DIR}" ]]; then
    echo "ERROR: Unable to determine RUN_DIR. Please set RUN_DIR manually." >&2
    exit 1
  fi
  local conf_pid
  conf_pid="$(extract_pid_file_from_conf "${NGINX_CONF}" || true)"
  PID_FILE="${PID_FILE:-${conf_pid:-${RUN_DIR}/nginx.pid}}"
}

require_nginx_binary() {
  if ! command -v nginx >/dev/null 2>&1; then
    echo "ERROR: nginx command not found in PATH." >&2
    exit 1
  fi
}
