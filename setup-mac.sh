#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/setup-common.sh
source "$SCRIPT_DIR/scripts/setup-common.sh"

DEFAULT_BASE_DIR="$SCRIPT_DIR"
BASE_DIR="${TARGET_BASE_DIR:-$DEFAULT_BASE_DIR}"
START_SERVICES=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--start] [BASE_DIR]

  --start   setup完成后尝试启动3个服务
  BASE_DIR  仓库克隆目标目录（默认: $SCRIPT_DIR）
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start)
        START_SERVICES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        setup_err "unknown option: $1"
        usage
        exit 1
        ;;
      *)
        BASE_DIR="$1"
        shift
        ;;
    esac
  done
}

clone_repo() {
  local name="$1"
  local url="$2"
  local dir="$BASE_DIR/$name"

  if [[ -d "$dir/.git" ]]; then
    setup_log "repo exists, skip clone: $dir"
    return 0
  fi

  if [[ -e "$dir" ]]; then
    setup_err "path exists but not a git repo: $dir"
    return 1
  fi

  setup_log "cloning $url -> $dir"
  git clone "$url" "$dir"
}

check_repo_file() {
  local repo="$1"
  local relpath="$2"
  local full="$BASE_DIR/$repo/$relpath"
  if [[ ! -e "$full" ]]; then
    setup_err "missing required file: $full"
    return 1
  fi
  return 0
}

configure_password_hashes() {
  local term_env="$BASE_DIR/term-webclient/.env"
  local app_env="$BASE_DIR/zenmind-app-server/.env"
  local term_plain app_admin_plain app_master_plain
  local term_hash app_admin_hash app_master_hash

  setup_log "configuring bcrypt password hashes in .env files"

  setup_ensure_env_file "$term_env"
  setup_ensure_env_file "$app_env"

  term_plain="$(setup_prompt_password "term-webclient AUTH_PASSWORD_HASH_BCRYPT 对应明文密码" "password")"
  term_hash="$(setup_generate_bcrypt "$term_plain")" || return 1
  setup_upsert_env_var "$term_env" "AUTH_PASSWORD_HASH_BCRYPT" "$term_hash"
  setup_log "updated $term_env -> AUTH_PASSWORD_HASH_BCRYPT"

  app_admin_plain="$(setup_prompt_password "zenmind-app-server AUTH_ADMIN_PASSWORD_BCRYPT 对应明文密码" "password")"
  app_admin_hash="$(setup_generate_bcrypt "$app_admin_plain")" || return 1
  setup_upsert_env_var "$app_env" "AUTH_ADMIN_PASSWORD_BCRYPT" "$app_admin_hash"
  setup_log "updated $app_env -> AUTH_ADMIN_PASSWORD_BCRYPT"

  app_master_plain="$(setup_prompt_password "zenmind-app-server AUTH_APP_MASTER_PASSWORD_BCRYPT 对应明文密码" "password")"
  app_master_hash="$(setup_generate_bcrypt "$app_master_plain")" || return 1
  setup_upsert_env_var "$app_env" "AUTH_APP_MASTER_PASSWORD_BCRYPT" "$app_master_hash"
  setup_log "updated $app_env -> AUTH_APP_MASTER_PASSWORD_BCRYPT"

  setup_log "bcrypt 已写入 .env；若需手动生成请使用："
  setup_bcrypt_hint
  return 0
}

start_term_webclient() {
  local repo="$BASE_DIR/term-webclient"
  local backend_pid="$repo/release/run/backend.pid"
  local frontend_pid="$repo/release/run/frontend.pid"

  if setup_process_running_from_pid_file "$backend_pid" && setup_process_running_from_pid_file "$frontend_pid"; then
    setup_log "term-webclient already running, skip start"
    return 0
  fi

  setup_log "starting term-webclient via start.sh"
  (
    cd "$repo"
    ./start.sh
  )
}

start_zenmind_app_server() {
  local repo="$BASE_DIR/zenmind-app-server"

  if ! setup_docker_daemon_running; then
    setup_err "docker daemon is not running; cannot start zenmind-app-server"
    return 1
  fi

  setup_log "starting zenmind-app-server via docker compose up -d --build"
  (
    cd "$repo"
    docker compose up -d --build
  )
}

start_agent_platform_runner() {
  local repo="$BASE_DIR/agent-platform-runner"
  local pid_file="$repo/release-local/app.pid"

  if setup_process_running_from_pid_file "$pid_file"; then
    setup_log "agent-platform-runner already running, skip start"
    return 0
  fi

  setup_log "starting agent-platform-runner via start-local.sh -d"
  (
    cd "$repo"
    ./start-local.sh -d
  )
}

start_all_services() {
  local failed=0
  start_term_webclient || failed=1
  start_zenmind_app_server || failed=1
  start_agent_platform_runner || failed=1

  if (( failed == 0 )); then
    setup_log "all services start commands completed."
  else
    setup_err "one or more services failed to start."
  fi
  return "$failed"
}

main() {
  local failed=0
  parse_args "$@"

  setup_log "base dir: $BASE_DIR"
  mkdir -p "$BASE_DIR"

  setup_require_cmd git || failed=1
  if (( failed != 0 )); then
    setup_err "git is required before running setup"
    exit 1
  fi

  clone_repo "term-webclient" "https://github.com/linlay/term-webclient.git" || failed=1
  clone_repo "zenmind-app-server" "https://github.com/linlay/zenmind-app-server.git" || failed=1
  clone_repo "agent-platform-runner" "https://github.com/linlay/agent-platform-runner.git" || failed=1

  check_repo_file "term-webclient" "README.md" || failed=1
  check_repo_file "term-webclient" "backend/pom.xml" || failed=1
  check_repo_file "term-webclient" "frontend/package.json" || failed=1
  check_repo_file "term-webclient" "start.sh" || failed=1

  check_repo_file "zenmind-app-server" "README.md" || failed=1
  check_repo_file "zenmind-app-server" "backend/pom.xml" || failed=1
  check_repo_file "zenmind-app-server" "frontend/package.json" || failed=1
  check_repo_file "zenmind-app-server" "docker-compose.yml" || failed=1
  check_repo_file "zenmind-app-server" "package.sh" || failed=1

  check_repo_file "agent-platform-runner" "README.md" || failed=1
  check_repo_file "agent-platform-runner" "pom.xml" || failed=1
  check_repo_file "agent-platform-runner" "libs/agw-springai-sdk-0.0.1-SNAPSHOT.jar" || failed=1
  check_repo_file "agent-platform-runner" "start-local.sh" || failed=1

  if (( failed == 0 )); then
    configure_password_hashes || failed=1
  fi

  setup_log "checking local-install dependencies for term-webclient (non-container)"
  setup_check_java21 || failed=1
  setup_check_maven39 || failed=1
  setup_check_node20 || failed=1
  setup_check_npm || failed=1

  setup_log "checking local-install dependencies for agent-platform-runner (non-container)"
  setup_check_java21 || failed=1
  setup_check_maven39 || failed=1

  setup_log "checking container dependencies for zenmind-app-server"
  setup_check_docker_compose_for_app_server || failed=1

  setup_check_optional_tools

  echo
  if (( failed == 0 )); then
    setup_log "setup completed successfully."

    if (( START_SERVICES == 1 )); then
      setup_log "start flag detected, launching 3 services..."
      start_all_services || return 1
    else
      setup_log "next suggested steps:"
      setup_log "  1) run this script with --start to auto start all services"
      setup_log "  2) or manually start:"
      setup_log "     - term-webclient: cd $BASE_DIR/term-webclient && ./start.sh"
      setup_log "     - zenmind-app-server: cd $BASE_DIR/zenmind-app-server && docker compose up -d --build"
      setup_log "     - agent-platform-runner: cd $BASE_DIR/agent-platform-runner && ./start-local.sh -d"
    fi
    return 0
  fi

  setup_err "setup finished with errors."
  cat <<'HINT' >&2
[setup-mac] install hints (macOS + Homebrew):
  brew install git
  brew install openjdk@21
  brew install maven
  brew install node@20
  brew install --cask docker
  brew install httpd        # provides htpasswd (optional)
HINT
  return 1
}

main "$@"
