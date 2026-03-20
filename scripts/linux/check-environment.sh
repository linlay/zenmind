#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/setup-common.sh
source "$SCRIPT_DIR/setup-common.sh"

MODE="install"

OK_ITEMS=()
ISSUE_ITEMS=()
RUNTIME_BLOCKERS=()
WARN_ITEMS=()

usage() {
  cat <<'USAGE'
Usage: check-environment.sh [--mode install|runtime|all]

  --mode install   check required tools and versions only (default)
  --mode runtime   check runtime readiness only
  --mode all       check install + runtime
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --mode)
      [[ $# -ge 2 ]] || {
        setup_err "--mode requires a value"
        exit 2
      }
      MODE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      setup_err "unknown argument: $1"
      usage
      exit 2
      ;;
    esac
  done

  case "$MODE" in
  install | runtime | all) ;;
  *)
    setup_err "invalid mode: $MODE"
    usage
    exit 2
    ;;
  esac
}

add_ok() {
  OK_ITEMS+=("$1")
}

add_issue() {
  local item="$1"
  local hint="$2"
  ISSUE_ITEMS+=("$item|$hint")
}

add_runtime_blocker() {
  local item="$1"
  local hint="$2"
  RUNTIME_BLOCKERS+=("$item|$hint")
}

add_warn_item() {
  WARN_ITEMS+=("$1")
}

detect_wsl() {
  [[ -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]] && return 0
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null
}

print_section_header() {
  local title="$1"
  setup_log "$title"
}

print_report() {
  local entry item hint

  echo
  setup_log "===== environment report (mode=$MODE) ====="

  print_section_header "[OK]"
  if ((${#OK_ITEMS[@]} == 0)); then
    setup_log "  - none"
  else
    for entry in "${OK_ITEMS[@]}"; do
      setup_log "  - $entry"
    done
  fi

  print_section_header "[MISSING / VERSION_MISMATCH]"
  if ((${#ISSUE_ITEMS[@]} == 0)); then
    setup_log "  - none"
  else
    for entry in "${ISSUE_ITEMS[@]}"; do
      IFS='|' read -r item hint <<<"$entry"
      setup_log "  - $item"
      setup_log "    fix: $hint"
    done
  fi

  print_section_header "[NOT_RUNNING / RUNTIME_BLOCKER]"
  if ((${#RUNTIME_BLOCKERS[@]} == 0)); then
    setup_log "  - none"
  else
    for entry in "${RUNTIME_BLOCKERS[@]}"; do
      IFS='|' read -r item hint <<<"$entry"
      setup_log "  - $item"
      setup_log "    fix: $hint"
    done
  fi

  print_section_header "[WARNINGS]"
  if ((${#WARN_ITEMS[@]} == 0)); then
    setup_log "  - none"
  else
    for entry in "${WARN_ITEMS[@]}"; do
      setup_log "  - $entry"
    done
  fi
}

check_install_dependencies() {
  local failed=0
  local version raw major go_raw

  if [[ "$(uname -s)" != "Linux" ]]; then
    add_issue "non-linux host detected" "run this script on Linux or inside WSL"
    return 1
  fi

  if detect_wsl; then
    add_ok "wsl detected (${WSL_DISTRO_NAME:-linux})"
  else
    add_ok "linux host detected"
  fi

  if command -v git >/dev/null 2>&1; then
    add_ok "git installed"
  else
    add_issue "git missing" "sudo apt-get update && sudo apt-get install -y git"
    failed=1
  fi

  if command -v go >/dev/null 2>&1; then
    go_raw="$(go version 2>/dev/null || true)"
    version="$(printf '%s' "$go_raw" | awk '{print $3}' | sed 's/^go//')"
    if [[ -n "$version" ]] && setup_semver_ge "$version" "1.26.0"; then
      add_ok "go installed (version $version)"
    else
      add_issue "go version too low or unparsable (${go_raw:-unknown})" "install/upgrade Go to 1.26.0+"
      failed=1
    fi
  else
    add_issue "go missing (required: 1.26.0+)" "install Go 1.26.0+ from the official tarball or a version manager (Ubuntu apt packages may be older)"
    failed=1
  fi

  if command -v java >/dev/null 2>&1; then
    raw="$(java -version 2>&1 | head -n 1)"
    version="$(printf '%s' "$raw" | sed -E 's/.*"([0-9]+(\.[0-9]+){0,2}).*/\1/')"
    major="${version%%.*}"
    if [[ -n "$major" && "$major" =~ ^[0-9]+$ ]] && ((major >= 21)); then
      add_ok "java installed (version $version)"
    else
      add_issue "java version too low or unparsable ($raw)" "sudo apt-get update && sudo apt-get install -y openjdk-21-jdk"
      failed=1
    fi
  else
    add_issue "java missing (required: JDK 21+)" "sudo apt-get update && sudo apt-get install -y openjdk-21-jdk"
    failed=1
  fi

  if command -v mvn >/dev/null 2>&1; then
    version="$(mvn -v | awk '/Apache Maven/ {print $3; exit}')"
    if [[ -n "$version" ]] && setup_semver_ge "$version" "3.9.0"; then
      add_ok "maven installed (version $version)"
    else
      add_issue "maven version too low or unparsable (${version:-unknown})" "sudo apt-get update && sudo apt-get install -y maven"
      failed=1
    fi
  else
    add_issue "maven missing (required: 3.9+)" "sudo apt-get update && sudo apt-get install -y maven"
    failed=1
  fi

  local node_install_hint
  node_install_hint="$(setup_node20_install_hint)"

  if command -v node >/dev/null 2>&1; then
    version="$(node -v | sed 's/^v//')"
    if setup_semver_ge "$version" "20.0.0"; then
      add_ok "node installed (version v$version)"
    else
      add_issue "node version too low (v$version, required 20+)" "$node_install_hint"
      failed=1
    fi
  else
    add_issue "node missing (required: 20+)" "$node_install_hint"
    failed=1
  fi

  if command -v npm >/dev/null 2>&1; then
    add_ok "npm installed (version $(npm -v))"
  else
    add_issue "npm missing" "install Node.js 20+ first: $node_install_hint"
    failed=1
  fi

  return "$failed"
}

check_runtime_status() {
  add_ok "runtime mandatory checks: none (docker/compose not required in the linux topology)"

  if command -v nginx >/dev/null 2>&1; then
    add_ok "nginx installed"
    if pgrep -x nginx >/dev/null 2>&1; then
      add_ok "nginx running"
    else
      add_warn_item "nginx installed but not running (optional). start: sudo systemctl start nginx or sudo service nginx start"
    fi
  else
    add_warn_item "nginx not installed (optional). install: sudo apt-get update && sudo apt-get install -y nginx"
  fi

  return 0
}

main() {
  local failed=0

  parse_args "$@"

  case "$MODE" in
  install)
    check_install_dependencies || failed=1
    ;;
  runtime)
    check_runtime_status || failed=1
    ;;
  all)
    check_install_dependencies || failed=1
    check_runtime_status || failed=1
    ;;
  esac

  print_report
  exit "$failed"
}

main "$@"
