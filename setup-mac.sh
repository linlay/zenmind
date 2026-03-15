#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mac/setup-common.sh
source "${SCRIPT_DIR}/scripts/mac/setup-common.sh"
# shellcheck source=scripts/shared/zenmind-docker-first.sh
source "${SCRIPT_DIR}/scripts/shared/zenmind-docker-first.sh"

zenmind_main "mac" "$@"
