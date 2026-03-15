#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OS_NAME="$(uname -s)"

case "${OS_NAME}" in
Darwin)
  # shellcheck source=scripts/mac/setup-common.sh
  source "${ROOT_DIR}/scripts/mac/setup-common.sh"
  ;;
Linux)
  # shellcheck source=scripts/linux/setup-common.sh
  source "${ROOT_DIR}/scripts/linux/setup-common.sh"
  ;;
*)
  echo "unsupported OS: ${OS_NAME}" >&2
  exit 1
  ;;
esac

if [[ $# -ne 1 ]]; then
  echo "usage: $(basename "$0") <plain-password>" >&2
  exit 1
fi

setup_generate_bcrypt "$1"
