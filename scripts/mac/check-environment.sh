#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mac/setup-common.sh
source "$SCRIPT_DIR/setup-common.sh"

MODE="all"

REQUIRED_ROWS=()
OPTIONAL_ROWS=()
RUNTIME_ROWS=()
NEXT_STEPS=()

required_failed=0
runtime_failed=0

usage() {
  cat <<'USAGE'
Usage: check-environment.sh [--mode install|runtime|all]

  --mode install   check required/optional tools only
  --mode runtime   check runtime readiness only
  --mode all       check install + runtime (default)
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
      -h|--help)
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
    install|runtime|all) ;;
    *)
      setup_err "invalid mode: $MODE"
      usage
      exit 2
      ;;
  esac
}

add_row() {
  local section="$1"
  local name="$2"
  local status="$3"
  local detail="$4"
  local fix="${5:-}"
  case "$section" in
    required) REQUIRED_ROWS+=("$name|$status|$detail|$fix") ;;
    optional) OPTIONAL_ROWS+=("$name|$status|$detail|$fix") ;;
    runtime) RUNTIME_ROWS+=("$name|$status|$detail|$fix") ;;
  esac
}

add_next_step() {
  NEXT_STEPS+=("$1")
}

record_required_failure() {
  required_failed=1
}

record_runtime_failure() {
  runtime_failed=1
}

command_version() {
  local cmd="$1"
  local version_cmd="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    return 1
  fi
  eval "$version_cmd" 2>/dev/null | head -n 1
}

check_brew() {
  if command -v brew >/dev/null 2>&1; then
    add_row required "brew" "OK" "installed ($(brew --version | head -n 1))"
  else
    add_row required "brew" "FAIL" "Homebrew is missing; macOS install commands below depend on it." '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    add_next_step "Install Homebrew first, then rerun: ./setup-mac.sh --action check"
    record_required_failure
  fi
}

check_git() {
  if command -v git >/dev/null 2>&1; then
    add_row required "git" "OK" "installed ($(git --version))"
  else
    add_row required "git" "FAIL" "git is required for workspace and sibling repo operations." "brew install git"
    add_next_step "Install git: brew install git"
    record_required_failure
  fi
}

check_go() {
  local raw version
  if command -v go >/dev/null 2>&1; then
    raw="$(go version 2>/dev/null || true)"
    version="$(printf '%s' "$raw" | awk '{print $3}' | sed 's/^go//')"
    if [[ -n "$version" ]] && setup_semver_ge "$version" "1.26.0"; then
      add_row required "go" "OK" "installed (version $version)"
    else
      add_row required "go" "FAIL" "Go 1.26.0+ is required; current value is ${raw:-unknown}." "brew install go"
      add_next_step "Upgrade Go to 1.26.0+: brew install go"
      record_required_failure
    fi
  else
    add_row required "go" "FAIL" "Go 1.26.0+ is required." "brew install go"
    add_next_step "Install Go: brew install go"
    record_required_failure
  fi
}

check_java() {
  local raw version major
  if command -v java >/dev/null 2>&1; then
    raw="$(java -version 2>&1 | head -n 1)"
    version="$(printf '%s' "$raw" | sed -E 's/.*"([0-9]+(\.[0-9]+){0,2}).*/\1/')"
    major="${version%%.*}"
    if [[ -n "$major" && "$major" =~ ^[0-9]+$ ]] && (( major >= 21 )); then
      add_row required "java" "OK" "installed (version $version)"
    else
      add_row required "java" "FAIL" "JDK 21+ is required; current value is ${raw:-unknown}." "brew install openjdk@21"
      add_next_step "Install JDK 21+: brew install openjdk@21"
      record_required_failure
    fi
  else
    add_row required "java" "FAIL" "JDK 21+ is required." "brew install openjdk@21"
    add_next_step "Install JDK 21+: brew install openjdk@21"
    record_required_failure
  fi
}

check_maven() {
  local version
  if command -v mvn >/dev/null 2>&1; then
    version="$(mvn -v | awk '/Apache Maven/ {print $3; exit}')"
    if [[ -n "$version" ]] && setup_semver_ge "$version" "3.9.0"; then
      add_row required "maven" "OK" "installed (version $version)"
    else
      add_row required "maven" "FAIL" "Maven 3.9+ is required; current value is ${version:-unknown}." "brew install maven"
      add_next_step "Install Maven 3.9+: brew install maven"
      record_required_failure
    fi
  else
    add_row required "maven" "FAIL" "Maven 3.9+ is required." "brew install maven"
    add_next_step "Install Maven: brew install maven"
    record_required_failure
  fi
}

check_node() {
  local version npm_version
  if command -v node >/dev/null 2>&1; then
    version="$(node -v | sed 's/^v//')"
    if setup_semver_ge "$version" "20.0.0"; then
      add_row required "node" "OK" "installed (version v$version)"
    else
      add_row required "node" "FAIL" "Node.js 20+ is required; current version is v$version." "brew install node@20"
      add_next_step "Install Node.js 20+: brew install node@20"
      record_required_failure
    fi
  else
    add_row required "node" "FAIL" "Node.js 20+ is required." "brew install node@20"
    add_next_step "Install Node.js 20+: brew install node@20"
    record_required_failure
  fi

  if command -v npm >/dev/null 2>&1; then
    npm_version="$(npm -v)"
    add_row required "npm" "OK" "installed (version $npm_version)"
  else
    add_row required "npm" "FAIL" "npm is required to work with the frontend/tooling packages." "brew install node@20"
    add_next_step "Install npm via Node.js: brew install node@20"
    record_required_failure
  fi
}

check_docker() {
  if ! setup_prepare_docker_alias; then
    add_row required "docker" "FAIL" "Docker CLI is missing; remote images and compose startup require it." "brew install --cask docker"
    add_next_step "Install Docker Desktop: brew install --cask docker"
    record_required_failure
    return
  fi

  add_row required "docker" "OK" "installed ($(docker --version 2>/dev/null | head -n 1 || echo "version unavailable"))"

  if docker compose version >/dev/null 2>&1; then
    add_row runtime "docker compose" "OK" "available ($(docker compose version | head -n 1))"
  else
    add_row runtime "docker compose" "FAIL" "Docker Compose plugin is unavailable." "Install/repair Docker Desktop, then verify: docker compose version"
    add_next_step "Fix Docker Compose and rerun: docker compose version"
    record_runtime_failure
  fi
}

check_optional_tools() {
  if command -v cloudflared >/dev/null 2>&1; then
    add_row optional "cloudflared" "OK" "installed ($(cloudflared --version | head -n 1))"
  else
    add_row optional "cloudflared" "WARN" "Cloudflare Tunnel tooling is not installed; public tunnel checks will stay local-only." "brew install cloudflare/cloudflare/cloudflared"
    add_next_step "Optional: install cloudflared for public tunnel support: brew install cloudflare/cloudflare/cloudflared"
  fi

  if command -v htpasswd >/dev/null 2>&1; then
    add_row optional "htpasswd" "OK" "installed"
  else
    add_row optional "htpasswd" "WARN" "bcrypt generation can fall back to Python, but htpasswd is a useful local helper." "brew install httpd"
  fi

  if command -v python3 >/dev/null 2>&1; then
    add_row optional "python3" "OK" "installed ($(python3 --version 2>/dev/null))"
  else
    add_row optional "python3" "WARN" "Used as a bcrypt fallback helper when htpasswd is unavailable." "brew install python"
  fi
}

check_runtime_status() {
  if setup_docker_daemon_running; then
    add_row runtime "docker daemon" "OK" "Docker engine is reachable."
  else
    add_row runtime "docker daemon" "FAIL" "Docker engine is not running, so images cannot be pulled and containers cannot be started." "open -a Docker"
    add_next_step "Start Docker Desktop, wait until it is ready, then rerun: ./setup-mac.sh --action check"
    record_runtime_failure
  fi

  if command -v cloudflared >/dev/null 2>&1; then
    local config_file pid_file pid
    config_file="${HOME}/.cloudflared/config.yml"
    pid_file="${HOME}/.cloudflared/cloudflared.pid"
    if [[ -f "$config_file" ]]; then
      add_row runtime "cloudflared config" "OK" "found at $config_file"
    else
      add_row runtime "cloudflared config" "WARN" "Cloudflare config.yml is missing." "./scripts/mac/setup-cf-tunnel.sh"
      add_next_step "Optional: configure Cloudflare Tunnel: ./scripts/mac/setup-cf-tunnel.sh"
    fi

    if [[ -f "$pid_file" ]]; then
      pid="$(cat "$pid_file" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
        add_row runtime "cloudflared process" "OK" "running with PID $pid"
      else
        add_row runtime "cloudflared process" "WARN" "PID file exists but no running process was found." "./scripts/mac/start-cf-tunnel.sh"
        add_next_step "Optional: start Cloudflare Tunnel: ./scripts/mac/start-cf-tunnel.sh"
      fi
    else
      add_row runtime "cloudflared process" "WARN" "Cloudflare Tunnel is not running." "./scripts/mac/start-cf-tunnel.sh"
      add_next_step "Optional: start Cloudflare Tunnel: ./scripts/mac/start-cf-tunnel.sh"
    fi
  else
    add_row runtime "cloudflared" "WARN" "Skipped runtime tunnel check because cloudflared is not installed." "brew install cloudflare/cloudflare/cloudflared"
  fi
}

print_section() {
  local title="$1"
  shift
  local rows=("$@")
  local row name status detail fix

  printf '\n%s\n' "$title"
  printf '%s\n' "------------------------------------------------------------"

  if ((${#rows[@]} == 0)); then
    printf '  %-18s %-7s %s\n' "-" "INFO" "No items in this section."
    return
  fi

  for row in "${rows[@]}"; do
    IFS='|' read -r name status detail fix <<<"$row"
    printf '  %-18s %-7s %s\n' "$name" "$status" "$detail"
    if [[ -n "$fix" ]]; then
      printf '  %-18s %-7s %s\n' "" "fix" "$fix"
    fi
  done
}

print_next_steps() {
  local step
  printf '\n%s\n' "Next Steps"
  printf '%s\n' "------------------------------------------------------------"
  if ((${#NEXT_STEPS[@]} == 0)); then
    printf '  %s\n' "Everything needed for the selected check mode looks ready."
    return
  fi

  local seen=""
  for step in "${NEXT_STEPS[@]}"; do
    if [[ "$seen" == *$'\n'"$step"$'\n'* ]]; then
      continue
    fi
    printf '  - %s\n' "$step"
    seen+=$'\n'"$step"$'\n'
  done
}

main() {
  parse_args "$@"

  case "$MODE" in
    install)
      check_brew
      check_git
      check_go
      check_java
      check_maven
      check_node
      check_docker
      check_optional_tools
      ;;
    runtime)
      check_docker
      check_runtime_status
      ;;
    all)
      check_brew
      check_git
      check_go
      check_java
      check_maven
      check_node
      check_docker
      check_optional_tools
      check_runtime_status
      ;;
  esac

  printf '\n%s\n' "ZenMind macOS Environment Check"
  printf '%s\n' "mode: $MODE"

  if [[ "$MODE" == "install" || "$MODE" == "all" ]]; then
    print_section "Required" "${REQUIRED_ROWS[@]}"
    print_section "Optional" "${OPTIONAL_ROWS[@]}"
  fi

  if [[ "$MODE" == "runtime" || "$MODE" == "all" ]]; then
    print_section "Runtime" "${RUNTIME_ROWS[@]}"
  fi

  print_next_steps
  printf '\n'

  if (( required_failed != 0 || runtime_failed != 0 )); then
    exit 1
  fi
}

main "$@"
