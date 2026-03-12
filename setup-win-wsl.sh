#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[setup-win-wsl] %s\n' "$*"
}

err() {
  printf '[setup-win-wsl] ERROR: %s\n' "$*" >&2
}

is_wsl() {
  if [[ -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]]; then
    return 0
  fi

  if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    return 0
  fi

  if grep -qi microsoft /proc/version 2>/dev/null; then
    return 0
  fi

  return 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  err "this entry must be run inside a Linux shell provided by WSL"
  err "open your WSL distro first, then rerun: ./setup-win-wsl.sh --action precheck"
  exit 1
fi

if ! is_wsl; then
  err "detected Linux, but not WSL"
  err "for regular Linux hosts use: ./setup-linux.sh"
  exit 1
fi

export SETUP_RUNTIME_ENV="wsl"
log "WSL environment detected, forwarding to ./setup-linux.sh"
exec "$SCRIPT_DIR/setup-linux.sh" "$@"
