#!/usr/bin/env bash
set -euo pipefail

detect_os_name() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux) echo "linux" ;;
    *) echo "unknown" ;;
  esac
}

detect_brew_prefix() {
  if command -v brew >/dev/null 2>&1; then
    brew --prefix
    return 0
  fi
  if [[ -d /opt/homebrew ]]; then echo "/opt/homebrew"; return 0; fi
  if [[ -d /usr/local ]]; then echo "/usr/local"; return 0; fi
  echo ""
}

default_nginx_dir() {
  local os_name="$1"
  local brew_prefix="$2"
  case "${os_name}" in
    darwin)
      if [[ -n "${brew_prefix}" ]]; then
        echo "${brew_prefix}/etc/nginx"
        return 0
      fi
      if [[ -d /opt/homebrew/etc/nginx ]]; then echo "/opt/homebrew/etc/nginx"; return 0; fi
      if [[ -d /usr/local/etc/nginx ]]; then echo "/usr/local/etc/nginx"; return 0; fi
      echo "/usr/local/etc/nginx"
      ;;
    linux)
      if [[ -d /etc/nginx ]]; then echo "/etc/nginx"; return 0; fi
      if [[ -d /usr/local/etc/nginx ]]; then echo "/usr/local/etc/nginx"; return 0; fi
      echo "/etc/nginx"
      ;;
    *)
      echo ""
      ;;
  esac
}

default_run_dir() {
  local os_name="$1"
  local brew_prefix="$2"
  case "${os_name}" in
    darwin)
      if [[ -n "${brew_prefix}" ]]; then
        echo "${brew_prefix}/var/run"
      else
        echo "/usr/local/var/run"
      fi
      ;;
    linux)
      echo "/var/run"
      ;;
    *)
      echo ""
      ;;
  esac
}

extract_pid_file_from_conf() {
  local conf_file="$1"
  if [[ ! -f "${conf_file}" ]]; then
    return 0
  fi
  awk 'tolower($1)=="pid"{gsub(/;/, "", $2); print $2; exit}' "${conf_file}"
}

resolve_nginx_paths() {
  OS_NAME="${OS_NAME:-$(detect_os_name)}"
  BREW_PREFIX="${BREW_PREFIX:-$(detect_brew_prefix)}"
  NGINX_DIR="${NGINX_DIR:-$(default_nginx_dir "${OS_NAME}" "${BREW_PREFIX}")}"
  if [[ -z "${NGINX_DIR}" ]]; then
    echo "ERROR: Unsupported OS. Please set NGINX_DIR/NGINX_CONF manually." >&2
    exit 1
  fi
  NGINX_CONF="${NGINX_CONF:-${NGINX_DIR}/nginx.conf}"
  RUN_DIR="${RUN_DIR:-$(default_run_dir "${OS_NAME}" "${BREW_PREFIX}")}"
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
