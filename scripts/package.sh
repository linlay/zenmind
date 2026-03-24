#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/deploy/package-zenmind-data.sh"

if [[ ! -f "$TARGET_SCRIPT" ]]; then
  printf '[package] ERROR: target script not found: %s\n' "$TARGET_SCRIPT" >&2
  exit 1
fi

exec env ZENMIND_PACKAGE_SCRIPT_NAME="$(basename "$0")" "$TARGET_SCRIPT" "$@"
