#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/mac/setup-common.sh
source "$SCRIPT_DIR/scripts/mac/setup-common.sh"

DEFAULT_BASE_DIR="$SCRIPT_DIR"
BASE_DIR="${TARGET_BASE_DIR:-$DEFAULT_BASE_DIR}"
ACTION=""
NON_INTERACTIVE=0
SHOW_PLAIN_PASSWORD=0
UPDATE_CONFIG_BACKUP_DIR=""

readonly SOURCE_SUBDIR="source"
readonly RELEASE_SUBDIR="release"

readonly REPO_NAMES=(
  "term-webclient"
  "zenmind-app-server"
  "agent-platform-runner"
)
readonly REPO_URLS=(
  "https://github.com/linlay/term-webclient.git"
  "https://github.com/linlay/zenmind-app-server.git"
  "https://github.com/linlay/agent-platform-runner.git"
)

# format: source|target|required
readonly CONFIG_MAPPINGS=(
  "source/term-webclient/.env.example|release/term-webclient/.env|true"
  "source/term-webclient/application.example.yml|release/term-webclient/application.yml|true"
  "source/zenmind-app-server/.env.example|release/zenmind-app-server/.env|true"
  "source/agent-platform-runner/application.example.yml|release/agent-platform-runner/application.yml|true"
)

SUMMARY_OK=()
SUMMARY_WARN=()
SUMMARY_FAIL=()

workspace_source_dir() {
  printf '%s/%s\n' "$BASE_DIR" "$SOURCE_SUBDIR"
}

workspace_release_dir() {
  printf '%s/%s\n' "$BASE_DIR" "$RELEASE_SUBDIR"
}

repo_source_dir() {
  local repo="$1"
  printf '%s/%s\n' "$(workspace_source_dir)" "$repo"
}

repo_release_dir() {
  local repo="$1"
  printf '%s/%s\n' "$(workspace_release_dir)" "$repo"
}

repo_packaged_output_dir() {
  local repo="$1"
  case "$repo" in
  term-webclient | zenmind-app-server)
    printf '%s/release\n' "$(repo_source_dir "$repo")"
    ;;
  agent-platform-runner)
    printf '%s/release-local\n' "$(repo_source_dir "$repo")"
    ;;
  *)
    return 1
    ;;
  esac
}

ensure_workspace_layout() {
  mkdir -p "$BASE_DIR" "$(workspace_source_dir)" "$(workspace_release_dir)"
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--action ACTION] [--base-dir PATH] [--yes] [--show-plain-password] [BASE_DIR]

Interactive menu (default):
  1) 环境检测
  2) 首次安装
  3) 更新
  4) 启动
  5) 停止
  6) 重置密码哈希
  0) 退出

Options:
  --action      precheck | first-install | update | start | stop | reset-password-hash
  --base-dir    工作区根目录（默认: ${SCRIPT_DIR}）
  --yes         非交互模式（密码提示使用默认值）
  --show-plain-password  调试模式：输出输入明文密码（请勿用于共享终端）
  -h, --help    显示帮助
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --action)
      [[ $# -ge 2 ]] || {
        setup_err "--action requires a value"
        exit 1
      }
      ACTION="$2"
      shift 2
      ;;
    --base-dir)
      [[ $# -ge 2 ]] || {
        setup_err "--base-dir requires a value"
        exit 1
      }
      BASE_DIR="$2"
      shift 2
      ;;
    --yes)
      NON_INTERACTIVE=1
      shift
      ;;
    --show-plain-password)
      SHOW_PLAIN_PASSWORD=1
      shift
      ;;
    -h | --help)
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

  case "$ACTION" in
  "" | precheck | first-install | update | start | stop | reset-password-hash) ;;
  *)
    setup_err "invalid action: $ACTION"
    usage
    exit 1
    ;;
  esac

  if [[ -z "$ACTION" && "$NON_INTERACTIVE" == "1" ]]; then
    setup_err "--yes requires --action in non-interactive mode"
    exit 1
  fi

  export SETUP_NON_INTERACTIVE="$NON_INTERACTIVE"
  export SETUP_SHOW_PLAIN_PASSWORD="$SHOW_PLAIN_PASSWORD"
}

summary_reset() {
  SUMMARY_OK=()
  SUMMARY_WARN=()
  SUMMARY_FAIL=()
}

summary_add_ok() {
  SUMMARY_OK+=("$1")
  setup_log "$1"
}

summary_add_warn() {
  SUMMARY_WARN+=("$1")
  setup_warn "$1"
}

summary_add_fail() {
  SUMMARY_FAIL+=("$1")
  setup_err "$1"
}

print_summary() {
  local title="$1"
  local item

  echo
  setup_log "===== ${title} summary ====="

  if ((${#SUMMARY_OK[@]} > 0)); then
    setup_log "success (${#SUMMARY_OK[@]}):"
    for item in "${SUMMARY_OK[@]}"; do
      setup_log "  - $item"
    done
  fi

  if ((${#SUMMARY_WARN[@]} > 0)); then
    setup_warn "warnings (${#SUMMARY_WARN[@]}):"
    for item in "${SUMMARY_WARN[@]}"; do
      setup_warn "  - $item"
    done
  fi

  if ((${#SUMMARY_FAIL[@]} > 0)); then
    setup_err "failures (${#SUMMARY_FAIL[@]}):"
    for item in "${SUMMARY_FAIL[@]}"; do
      setup_err "  - $item"
    done
    if [[ "$title" == "precheck" ]]; then
      return 0
    fi
    cat <<'HINT' >&2
[setup-mac] common fix hints:
  - Run precheck first: ./setup-mac.sh --action precheck
  - Install dependencies: brew install git openjdk@21 maven node@20
  - Install Podman + alias (recommended): brew install podman podman-compose && podman machine init && podman machine start
  - Optional: alias docker='podman'
  - Install Docker Desktop (alternative): brew install --cask docker && open -a Docker
  - Install nginx (optional): brew install nginx
  - Start nginx (optional): ./scripts/mac/start-nginx.sh
  - Optional bcrypt tool: brew install httpd
HINT
  fi
}

ensure_check_script_ready() {
  local check_script="$SCRIPT_DIR/scripts/mac/check-environment.sh"

  if [[ ! -x "$check_script" ]]; then
    chmod +x "$check_script" 2>/dev/null || true
  fi

  if [[ ! -x "$check_script" ]]; then
    summary_add_fail "environment check script missing or not executable: $check_script"
    return 1
  fi

  printf '%s\n' "$check_script"
}

refresh_repo_by_clone() {
  local name="$1"
  local url="$2"
  local dir

  dir="$(repo_source_dir "$name")"

  if [[ -e "$dir" ]]; then
    setup_log "removing existing source repo: $dir"
    rm -rf "$dir"
  fi

  setup_log "cloning $url -> $dir"
  if git clone "$url" "$dir"; then
    summary_add_ok "cloned $name"
    return 0
  fi

  summary_add_fail "failed to clone $name"
  return 1
}

check_repo_file() {
  local repo="$1"
  local relpath="$2"
  local full

  full="$(repo_source_dir "$repo")/$relpath"

  if [[ ! -e "$full" ]]; then
    summary_add_fail "missing required file: $full"
    return 1
  fi

  summary_add_ok "required file exists: source/$repo/$relpath"
  return 0
}

check_required_repo_files() {
  local failed=0

  check_repo_file "term-webclient" "README.md" || failed=1
  check_repo_file "term-webclient" "backend/pom.xml" || failed=1
  check_repo_file "term-webclient" "frontend/package.json" || failed=1
  check_repo_file "term-webclient" "release-scripts/mac/package.sh" || failed=1

  check_repo_file "zenmind-app-server" "README.md" || failed=1
  check_repo_file "zenmind-app-server" "backend/pom.xml" || failed=1
  check_repo_file "zenmind-app-server" "frontend/package.json" || failed=1
  check_repo_file "zenmind-app-server" "docker-compose.yml" || failed=1
  check_repo_file "zenmind-app-server" "release-scripts/mac/package.sh" || failed=1

  check_repo_file "agent-platform-runner" "README.md" || failed=1
  check_repo_file "agent-platform-runner" "pom.xml" || failed=1
  check_repo_file "agent-platform-runner" "release-scripts/mac/package-local.sh" || failed=1

  return "$failed"
}

resolve_example_source() {
  local expected_source="$1"
  local source_dir=""
  local fallback_source=""

  if [[ -f "$expected_source" ]]; then
    printf '%s\n' "$expected_source"
    return 0
  fi

  if [[ "$expected_source" == *.env.example ]]; then
    source_dir="$(dirname "$expected_source")"

    fallback_source="$source_dir/env.example"
    if [[ -f "$fallback_source" ]]; then
      summary_add_warn "detected env.example and will use it: $fallback_source"
      printf '%s\n' "$fallback_source"
      return 0
    fi

    fallback_source="${expected_source%.env.example}.evn.example"
    if [[ -f "$fallback_source" ]]; then
      summary_add_warn "detected typo file and will use it: $fallback_source"
      printf '%s\n' "$fallback_source"
      return 0
    fi

    fallback_source="$source_dir/.evn.example"
    if [[ -f "$fallback_source" ]]; then
      summary_add_warn "detected typo file and will use it: $fallback_source"
      printf '%s\n' "$fallback_source"
      return 0
    fi
  fi

  return 1
}

copy_example_configs() {
  local mode="${1:-overwrite}"
  local failed=0
  local mapping source_rel target_rel required source_path actual_source target_path backup_path display_source

  case "$mode" in
  overwrite | if-missing) ;;
  *)
    summary_add_fail "invalid copy config mode: $mode"
    return 1
    ;;
  esac

  setup_log "syncing example configs into release directories (mode=$mode)"

  for mapping in "${CONFIG_MAPPINGS[@]}"; do
    IFS='|' read -r source_rel target_rel required <<<"$mapping"
    source_path="$BASE_DIR/$source_rel"
    target_path="$BASE_DIR/$target_rel"

    if actual_source="$(resolve_example_source "$source_path")"; then
      :
    else
      if [[ "$required" == "true" ]]; then
        summary_add_fail "required source config missing: $source_path"
        failed=1
      else
        summary_add_warn "optional source config missing, skip: $source_path"
      fi
      continue
    fi

    mkdir -p "$(dirname "$target_path")"

    if [[ -f "$target_path" ]]; then
      if [[ "$mode" == "if-missing" ]]; then
        summary_add_ok "config exists, keep: $target_rel"
        continue
      fi

      if backup_path="$(setup_backup_file "$target_path")"; then
        summary_add_ok "backup created: $backup_path"
      else
        summary_add_fail "failed to backup existing config: $target_path"
        failed=1
        continue
      fi
    fi

    if cp "$actual_source" "$target_path"; then
      display_source="${actual_source#$BASE_DIR/}"
      if [[ "$display_source" == "$actual_source" ]]; then
        display_source="$actual_source"
      fi
      summary_add_ok "copied config: ${display_source} -> ${target_rel}"
    else
      summary_add_fail "failed to copy config: ${source_rel} -> ${target_rel}"
      failed=1
    fi
  done

  return "$failed"
}

backup_update_configs() {
  local failed=0
  local backup_dir mapping target_rel target_path backup_target

  backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/zenmind-config-backup.XXXXXX")" || {
    summary_add_fail "failed to create temp backup dir for update configs"
    return 1
  }

  UPDATE_CONFIG_BACKUP_DIR="$backup_dir"
  summary_add_ok "created config backup dir: $backup_dir"

  for mapping in "${CONFIG_MAPPINGS[@]}"; do
    IFS='|' read -r _ target_rel _ <<<"$mapping"
    target_path="$BASE_DIR/$target_rel"
    backup_target="$backup_dir/$target_rel"

    if [[ ! -f "$target_path" ]]; then
      summary_add_warn "no existing config to backup: $target_rel"
      continue
    fi

    mkdir -p "$(dirname "$backup_target")"
    if cp "$target_path" "$backup_target"; then
      summary_add_ok "backed up config: $target_rel"
    else
      summary_add_fail "failed to backup config: $target_rel"
      failed=1
    fi
  done

  return "$failed"
}

restore_update_configs() {
  local failed=0
  local mapping target_rel target_path backup_source

  if [[ -z "$UPDATE_CONFIG_BACKUP_DIR" || ! -d "$UPDATE_CONFIG_BACKUP_DIR" ]]; then
    summary_add_warn "config backup dir unavailable, skip restore"
    return 0
  fi

  for mapping in "${CONFIG_MAPPINGS[@]}"; do
    IFS='|' read -r _ target_rel _ <<<"$mapping"
    target_path="$BASE_DIR/$target_rel"
    backup_source="$UPDATE_CONFIG_BACKUP_DIR/$target_rel"

    if [[ ! -f "$backup_source" ]]; then
      summary_add_warn "no backup config to restore: $target_rel"
      continue
    fi

    mkdir -p "$(dirname "$target_path")"
    if cp "$backup_source" "$target_path"; then
      summary_add_ok "restored config: $target_rel"
    else
      summary_add_fail "failed to restore config: $target_rel"
      failed=1
    fi
  done

  return "$failed"
}

cleanup_update_config_backup() {
  if [[ -n "$UPDATE_CONFIG_BACKUP_DIR" && -d "$UPDATE_CONFIG_BACKUP_DIR" ]]; then
    rm -rf "$UPDATE_CONFIG_BACKUP_DIR"
    summary_add_ok "removed temp config backup dir"
  fi
  UPDATE_CONFIG_BACKUP_DIR=""
}

configure_password_hashes() {
  local term_env app_env
  local term_plain app_admin_plain app_master_plain
  local term_hash app_admin_hash app_master_hash

  term_env="$(repo_release_dir "term-webclient")/.env"
  app_env="$(repo_release_dir "zenmind-app-server")/.env"

  setup_log "configuring bcrypt password hashes in release env files"

  setup_ensure_env_file "$term_env"
  setup_ensure_env_file "$app_env"

  term_plain="$(setup_prompt_password "term-webclient AUTH_PASSWORD_HASH_BCRYPT 对应明文密码" "password")"
  term_hash="$(setup_generate_bcrypt "$term_plain")" || return 1
  setup_upsert_env_var "$term_env" "AUTH_PASSWORD_HASH_BCRYPT" "$(setup_single_quote_env_value "$term_hash")" || return 1
  summary_add_ok "updated AUTH_PASSWORD_HASH_BCRYPT in release/term-webclient/.env"

  app_admin_plain="$(setup_prompt_password "zenmind-app-server AUTH_ADMIN_PASSWORD_BCRYPT 对应明文密码" "password")"
  app_admin_hash="$(setup_generate_bcrypt "$app_admin_plain")" || return 1
  setup_upsert_env_var "$app_env" "AUTH_ADMIN_PASSWORD_BCRYPT" "$(setup_single_quote_env_value "$app_admin_hash")" || return 1
  summary_add_ok "updated AUTH_ADMIN_PASSWORD_BCRYPT in release/zenmind-app-server/.env"

  app_master_plain="$(setup_prompt_password "zenmind-app-server AUTH_APP_MASTER_PASSWORD_BCRYPT 对应明文密码" "password")"
  app_master_hash="$(setup_generate_bcrypt "$app_master_plain")" || return 1
  setup_upsert_env_var "$app_env" "AUTH_APP_MASTER_PASSWORD_BCRYPT" "$(setup_single_quote_env_value "$app_master_hash")" || return 1
  summary_add_ok "updated AUTH_APP_MASTER_PASSWORD_BCRYPT in release/zenmind-app-server/.env"
  return 0
}

run_reset_password_hash() {
  local term_release app_release

  term_release="$(repo_release_dir "term-webclient")"
  app_release="$(repo_release_dir "zenmind-app-server")"
  if [[ ! -d "$term_release" || ! -d "$app_release" ]]; then
    summary_add_fail "release dirs missing, run first-install/update first: $term_release, $app_release"
    return 1
  fi

  configure_password_hashes || return 1
  summary_add_ok "reset-password-hash completed"
  return 0
}

run_precheck() {
  local check_script

  check_script="$(ensure_check_script_ready)" || return 1

  setup_log "running environment check script (mode=all)"
  if "$check_script" --mode all; then
    summary_add_ok "environment precheck passed (mode=all)"
    return 0
  fi

  summary_add_fail "environment precheck failed (mode=all)"
  return 1
}

check_runtime_environment_before_start() {
  local check_script

  check_script="$(ensure_check_script_ready)" || return 1

  setup_log "running environment check script (mode=runtime)"
  if "$check_script" --mode runtime; then
    summary_add_ok "environment runtime check passed"
    return 0
  fi

  summary_add_fail "environment runtime check failed"
  return 1
}

run_package_term_webclient() {
  local repo
  repo="$(repo_source_dir "term-webclient")"

  setup_log "packaging term-webclient via ./release-scripts/mac/package.sh"
  if (cd "$repo" && ./release-scripts/mac/package.sh); then
    summary_add_ok "packaged term-webclient"
    return 0
  fi

  summary_add_fail "failed to package term-webclient (run: cd $repo && ./release-scripts/mac/package.sh)"
  return 1
}

run_package_zenmind_app_server() {
  local repo
  repo="$(repo_source_dir "zenmind-app-server")"

  setup_log "packaging zenmind-app-server via ./release-scripts/mac/package.sh"
  if (cd "$repo" && ./release-scripts/mac/package.sh); then
    summary_add_ok "packaged zenmind-app-server"
    return 0
  fi

  summary_add_fail "failed to package zenmind-app-server (run: cd $repo && ./release-scripts/mac/package.sh)"
  return 1
}

run_package_agent_platform_runner() {
  local repo
  repo="$(repo_source_dir "agent-platform-runner")"

  setup_log "packaging agent-platform-runner via ./release-scripts/mac/package-local.sh"
  if (cd "$repo" && ./release-scripts/mac/package-local.sh); then
    summary_add_ok "packaged agent-platform-runner"
    return 0
  fi

  summary_add_warn "failed to package agent-platform-runner, skip this optional service (run: cd $repo && ./release-scripts/mac/package-local.sh)"
  return 0
}

run_package_all_repos() {
  local failed=0

  run_package_term_webclient || failed=1
  run_package_zenmind_app_server || failed=1
  run_package_agent_platform_runner || failed=1

  return "$failed"
}

move_packaged_artifacts_for_repo() {
  local repo="$1"
  local packaged_dir release_dir

  packaged_dir="$(repo_packaged_output_dir "$repo")" || {
    summary_add_fail "unsupported repo for move: $repo"
    return 1
  }
  release_dir="$(repo_release_dir "$repo")"

  if [[ ! -d "$packaged_dir" ]]; then
    summary_add_fail "packaged output missing: $packaged_dir"
    return 1
  fi

  if [[ -e "$release_dir" ]]; then
    rm -rf "$release_dir"
  fi
  mkdir -p "$(dirname "$release_dir")"

  if mv "$packaged_dir" "$release_dir"; then
    summary_add_ok "moved package output to release: $repo"
    return 0
  fi

  summary_add_fail "failed to move package output for $repo"
  return 1
}

move_packaged_artifacts_all() {
  local failed=0
  local runner_packaged_dir
  local runner_release_dir

  move_packaged_artifacts_for_repo "term-webclient" || failed=1
  move_packaged_artifacts_for_repo "zenmind-app-server" || failed=1

  runner_packaged_dir="$(repo_packaged_output_dir "agent-platform-runner")"
  runner_release_dir="$(repo_release_dir "agent-platform-runner")"
  if [[ -d "$runner_packaged_dir" ]]; then
    if [[ -e "$runner_release_dir" ]]; then
      rm -rf "$runner_release_dir"
    fi
    mkdir -p "$(dirname "$runner_release_dir")"
    if mv "$runner_packaged_dir" "$runner_release_dir"; then
      summary_add_ok "moved package output to release: agent-platform-runner"
    else
      summary_add_warn "failed to move package output for optional service: agent-platform-runner"
    fi
  else
    summary_add_warn "packaged output missing for optional service, skip move: $runner_packaged_dir"
  fi

  return "$failed"
}

validate_release_artifacts_term_webclient() {
  local release_repo
  local missing=()
  local required file
  local start_script

  release_repo="$(repo_release_dir "term-webclient")"
  start_script="$release_repo/release-scripts/mac/start.sh"
  required=(
    "$release_repo/backend/app.jar"
    "$release_repo/frontend/server.js"
    "$release_repo/frontend/dist/index.html"
    "$start_script"
  )

  for file in "${required[@]}"; do
    [[ -f "$file" ]] || missing+=("$file")
  done

  if ((${#missing[@]} > 0)); then
    summary_add_fail "term-webclient release incomplete, missing: $(
      IFS=', '
      echo "${missing[*]}"
    )"
    return 1
  fi

  if [[ ! -x "$start_script" ]]; then
    summary_add_fail "term-webclient release start script is not executable: $start_script"
    return 1
  fi

  return 0
}

validate_release_artifacts_zenmind_app_server() {
  local release_repo
  local missing=()
  local required file

  release_repo="$(repo_release_dir "zenmind-app-server")"
  required=(
    "$release_repo/docker-compose.yml"
    "$release_repo/backend/app.jar"
    "$release_repo/frontend/dist/index.html"
  )

  for file in "${required[@]}"; do
    [[ -f "$file" ]] || missing+=("$file")
  done

  if ((${#missing[@]} > 0)); then
    summary_add_fail "zenmind-app-server release incomplete, missing: $(
      IFS=', '
      echo "${missing[*]}"
    )"
    return 1
  fi

  return 0
}

validate_release_artifacts_agent_platform_runner() {
  local release_repo
  local missing=()
  local required file

  release_repo="$(repo_release_dir "agent-platform-runner")"
  required=(
    "$release_repo/app.jar"
    "$release_repo/start.sh"
  )

  for file in "${required[@]}"; do
    [[ -f "$file" ]] || missing+=("$file")
  done

  if ((${#missing[@]} > 0)); then
    summary_add_warn "agent-platform-runner release incomplete, skip optional service: $(
      IFS=', '
      echo "${missing[*]}"
    )"
    return 0
  fi

  return 0
}

read_env_value_from_file() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  awk -v key="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      eq=index(line, "=")
      if (eq <= 0) {
        next
      }
      k=substr(line, 1, eq - 1)
      sub(/[[:space:]]+$/, "", k)
      if (k != key) {
        next
      }
      v=substr(line, eq + 1)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      print v
      exit
    }
  ' "$file"
}

listening_processes_for_port() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {printf "%s(pid=%s) ", $1, $2}'
}

diagnose_term_webclient_start_failure() {
  local release_repo="$1"
  local env_file backend_log frontend_log
  local backend_port frontend_port
  local backend_listeners frontend_listeners
  local port_conflict=0

  env_file="$release_repo/.env"
  backend_log="$release_repo/logs/backend.out"
  frontend_log="$release_repo/logs/frontend.out"

  backend_port="$(read_env_value_from_file "$env_file" "BACKEND_PORT" || true)"
  frontend_port="$(read_env_value_from_file "$env_file" "FRONTEND_PORT" || true)"
  if [[ -z "$frontend_port" ]]; then
    frontend_port="$(read_env_value_from_file "$env_file" "PORT" || true)"
  fi

  backend_port="${backend_port:-11946}"
  frontend_port="${frontend_port:-11947}"

  if [[ -f "$backend_log" ]] && grep -Eiq 'Port[[:space:]]+[0-9]+[[:space:]]+was already in use|Address already in use' "$backend_log"; then
    port_conflict=1
  fi
  if [[ -f "$frontend_log" ]] && grep -Eiq 'EADDRINUSE|address already in use' "$frontend_log"; then
    port_conflict=1
  fi

  if [[ "$port_conflict" == "1" ]]; then
    backend_listeners="$(listening_processes_for_port "$backend_port")"
    frontend_listeners="$(listening_processes_for_port "$frontend_port")"
    if [[ -n "$backend_listeners" ]]; then
      summary_add_fail "term-webclient backend port ${backend_port} is in use by: ${backend_listeners}"
    fi
    if [[ -n "$frontend_listeners" ]]; then
      summary_add_fail "term-webclient frontend port ${frontend_port} is in use by: ${frontend_listeners}"
    fi
    summary_add_fail "term-webclient port conflict detected; run stop, then release ports or change ports in release/term-webclient/.env"
    return 0
  fi

  summary_add_warn "term-webclient start failed; check logs: $backend_log , $frontend_log"
  return 0
}

start_term_webclient() {
  local source_repo release_repo
  local backend_pid frontend_pid
  local backend_running=0 frontend_running=0

  source_repo="$(repo_source_dir "term-webclient")"
  release_repo="$(repo_release_dir "term-webclient")"
  backend_pid="$release_repo/run/backend.pid"
  frontend_pid="$release_repo/run/frontend.pid"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_fail "term-webclient source repo missing: $source_repo"
    return 1
  fi

  validate_release_artifacts_term_webclient || return 1

  if setup_process_running_from_pid_file "$backend_pid"; then
    backend_running=1
  fi
  if setup_process_running_from_pid_file "$frontend_pid"; then
    frontend_running=1
  fi

  if [[ "$backend_running" == "1" && "$frontend_running" == "1" ]]; then
    summary_add_ok "term-webclient already running"
    return 0
  fi

  if [[ "$backend_running" == "1" || "$frontend_running" == "1" ]]; then
    summary_add_warn "term-webclient partial running state detected, restart it (backend=$backend_running frontend=$frontend_running)"
    if [[ -x "$release_repo/release-scripts/mac/stop.sh" ]]; then
      if (cd "$release_repo" && ./release-scripts/mac/stop.sh); then
        :
      else
        summary_add_warn "release-scripts/mac/stop.sh failed during restart recovery, fallback to pid stop"
      fi
    elif [[ -x "$source_repo/release-scripts/mac/stop.sh" ]]; then
      if (cd "$source_repo" && ./release-scripts/mac/stop.sh); then
        :
      else
        summary_add_warn "source release-scripts/mac/stop.sh failed during restart recovery, fallback to pid stop"
      fi
    fi
    setup_stop_process_by_pid_file "$backend_pid" >/dev/null 2>&1 || true
    setup_stop_process_by_pid_file "$frontend_pid" >/dev/null 2>&1 || true
  fi

  if [[ -x "$release_repo/release-scripts/mac/start.sh" ]]; then
    setup_log "starting term-webclient via release/release-scripts/mac/start.sh"
    if (cd "$release_repo" && ./release-scripts/mac/start.sh); then
      summary_add_ok "start command completed: term-webclient"
      return 0
    fi
  elif [[ -x "$source_repo/release-scripts/mac/start.sh" ]]; then
    setup_log "starting term-webclient via source/release-scripts/mac/start.sh (fallback)"
    if (cd "$source_repo" && ./release-scripts/mac/start.sh); then
      summary_add_ok "start command completed: term-webclient"
      return 0
    fi
  else
    summary_add_fail "term-webclient start script missing (expected release/release-scripts/mac/start.sh)"
    return 1
  fi

  diagnose_term_webclient_start_failure "$release_repo"
  summary_add_fail "failed to start term-webclient"
  return 1
}

start_zenmind_app_server() {
  local source_repo release_repo

  source_repo="$(repo_source_dir "zenmind-app-server")"
  release_repo="$(repo_release_dir "zenmind-app-server")"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_fail "zenmind-app-server source repo missing: $source_repo"
    return 1
  fi

  validate_release_artifacts_zenmind_app_server || return 1

  if ! setup_prepare_docker_alias; then
    summary_add_fail "docker command unavailable (install Docker, or install podman and map docker to podman)"
    return 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    summary_add_fail "docker compose unavailable; if using podman, install podman-compose"
    return 1
  fi

  if ! setup_docker_daemon_running; then
    summary_add_fail "docker runtime not ready; if using podman alias run: podman machine start"
    return 1
  fi

  setup_log "starting zenmind-app-server via release/docker compose up -d --build"
  if (cd "$release_repo" && docker compose up -d --build); then
    summary_add_ok "start command completed: zenmind-app-server"
    return 0
  fi

  summary_add_fail "failed to start zenmind-app-server"
  return 1
}

start_agent_platform_runner() {
  local source_repo release_repo
  local pid_file

  source_repo="$(repo_source_dir "agent-platform-runner")"
  release_repo="$(repo_release_dir "agent-platform-runner")"
  pid_file="$release_repo/app.pid"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_warn "agent-platform-runner source repo missing, skip optional service: $source_repo"
    return 0
  fi

  validate_release_artifacts_agent_platform_runner || return 1

  if setup_process_running_from_pid_file "$pid_file"; then
    summary_add_ok "agent-platform-runner already running"
    return 0
  fi

  if [[ -x "$release_repo/start.sh" ]]; then
    setup_log "starting agent-platform-runner via release/start.sh -d"
    if (cd "$release_repo" && ./start.sh -d); then
      summary_add_ok "start command completed: agent-platform-runner"
      return 0
    fi
  elif [[ -x "$source_repo/release-scripts/mac/start-local.sh" ]]; then
    setup_log "starting agent-platform-runner via source/release-scripts/mac/start-local.sh -d (fallback)"
    if (cd "$source_repo" && ./release-scripts/mac/start-local.sh -d); then
      summary_add_ok "start command completed: agent-platform-runner"
      return 0
    fi
  else
    summary_add_warn "agent-platform-runner start script missing, skip optional service (expected release/start.sh)"
    return 0
  fi

  summary_add_warn "failed to start agent-platform-runner, skip optional service"
  return 0
}

stop_agent_platform_runner() {
  local source_repo release_repo
  local pid_file

  source_repo="$(repo_source_dir "agent-platform-runner")"
  release_repo="$(repo_release_dir "agent-platform-runner")"
  pid_file="$release_repo/app.pid"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_warn "agent-platform-runner source repo not found, skip stop"
    return 0
  fi

  if [[ -x "$release_repo/stop.sh" ]]; then
    if (cd "$release_repo" && ./stop.sh); then
      summary_add_ok "stop command completed: agent-platform-runner"
      return 0
    fi
    summary_add_warn "release stop.sh failed, fallback to pid stop"
  elif [[ -x "$source_repo/release-scripts/mac/stop-local.sh" ]]; then
    if (cd "$source_repo" && ./release-scripts/mac/stop-local.sh); then
      summary_add_ok "stop command completed: agent-platform-runner"
      return 0
    fi
    summary_add_warn "source release-scripts/mac/stop-local.sh failed, fallback to pid stop"
  fi

  if setup_stop_process_by_pid_file "$pid_file"; then
    summary_add_ok "stopped by pid: agent-platform-runner"
    return 0
  fi

  summary_add_warn "agent-platform-runner is not running"
  return 0
}

stop_zenmind_app_server() {
  local source_repo release_repo

  source_repo="$(repo_source_dir "zenmind-app-server")"
  release_repo="$(repo_release_dir "zenmind-app-server")"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_warn "zenmind-app-server source repo not found, skip stop"
    return 0
  fi

  if [[ ! -d "$release_repo" ]]; then
    summary_add_warn "zenmind-app-server release dir not found, skip stop"
    return 0
  fi

  if ! setup_prepare_docker_alias; then
    summary_add_warn "docker command unavailable (and podman alias not ready), skip stop: zenmind-app-server"
    return 0
  fi

  if ! docker compose version >/dev/null 2>&1; then
    summary_add_warn "docker compose unavailable, skip stop: zenmind-app-server"
    return 0
  fi

  if ! setup_docker_daemon_running; then
    summary_add_warn "docker runtime not ready, skip stop: zenmind-app-server"
    return 0
  fi

  if (cd "$release_repo" && docker compose stop); then
    summary_add_ok "stop command completed: zenmind-app-server"
    return 0
  fi

  summary_add_fail "failed to stop zenmind-app-server"
  return 1
}

stop_term_webclient() {
  local source_repo release_repo
  local backend_pid frontend_pid
  local stopped_any=0

  source_repo="$(repo_source_dir "term-webclient")"
  release_repo="$(repo_release_dir "term-webclient")"
  backend_pid="$release_repo/run/backend.pid"
  frontend_pid="$release_repo/run/frontend.pid"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_warn "term-webclient source repo not found, skip stop"
    return 0
  fi

  if [[ -x "$release_repo/release-scripts/mac/stop.sh" ]]; then
    if (cd "$release_repo" && ./release-scripts/mac/stop.sh); then
      summary_add_ok "stop command completed: term-webclient"
      return 0
    fi
    summary_add_warn "release-scripts/mac/stop.sh failed, fallback to pid stop"
  elif [[ -x "$source_repo/release-scripts/mac/stop.sh" ]]; then
    if (cd "$source_repo" && ./release-scripts/mac/stop.sh); then
      summary_add_ok "stop command completed: term-webclient"
      return 0
    fi
    summary_add_warn "source release-scripts/mac/stop.sh failed, fallback to pid stop"
  fi

  if setup_stop_process_by_pid_file "$backend_pid"; then
    summary_add_ok "stopped backend process by pid"
    stopped_any=1
  fi

  if setup_stop_process_by_pid_file "$frontend_pid"; then
    summary_add_ok "stopped frontend process by pid"
    stopped_any=1
  fi

  if [[ "$stopped_any" == "1" ]]; then
    return 0
  fi

  summary_add_warn "term-webclient is not running"
  return 0
}

collect_running_compose_services() {
  local release_repo="$1"
  local services ps_output

  services="$(cd "$release_repo" && docker compose ps --status running --services 2>/dev/null || true)"
  if [[ -n "$services" ]]; then
    printf '%s\n' "$services"
    return 0
  fi

  services="$(cd "$release_repo" && docker compose ps --services 2>/dev/null || true)"
  if [[ -n "$services" ]]; then
    printf '%s\n' "$services"
    return 0
  fi

  ps_output="$(cd "$release_repo" && docker compose ps 2>/dev/null || true)"
  if [[ -n "$ps_output" ]] && printf '%s\n' "$ps_output" | grep -Eiq '\b(up|running|healthy)\b'; then
    printf '%s\n' "$ps_output"
    return 0
  fi

  return 1
}

health_check_after_start() {
  local failed=0
  local term_release app_release agent_release
  local running_services

  term_release="$(repo_release_dir "term-webclient")"
  app_release="$(repo_release_dir "zenmind-app-server")"
  agent_release="$(repo_release_dir "agent-platform-runner")"

  if setup_process_running_from_pid_file "$term_release/run/backend.pid" &&
    setup_process_running_from_pid_file "$term_release/run/frontend.pid"; then
    summary_add_ok "health check passed: term-webclient backend/frontend pids alive"
  else
    summary_add_fail "health check failed: term-webclient process not fully running"
    failed=1
  fi

  if [[ -d "$app_release" ]] &&
    setup_prepare_docker_alias &&
    docker compose version >/dev/null 2>&1 &&
    setup_docker_daemon_running; then
    if running_services="$(collect_running_compose_services "$app_release")"; then
      summary_add_ok "health check passed: zenmind-app-server has running compose services"
    else
      summary_add_fail "health check failed: zenmind-app-server has no running compose service"
      failed=1
    fi
  else
    summary_add_fail "health check failed: zenmind-app-server compose status unavailable"
    failed=1
  fi

  if setup_process_running_from_pid_file "$agent_release/app.pid"; then
    summary_add_ok "health check passed: agent-platform-runner pid alive"
  else
    summary_add_warn "health check skipped: agent-platform-runner not running (optional service)"
  fi

  return "$failed"
}

run_first_install() {
  local failed=0

  ensure_workspace_layout
  setup_log "workspace base dir: $BASE_DIR"
  setup_log "workspace source dir: $(workspace_source_dir)"
  setup_log "workspace release dir: $(workspace_release_dir)"

  if setup_require_cmd git; then
    summary_add_ok "git available"
  else
    summary_add_fail "git is required before first-install"
    return 1
  fi

  setup_show_first_install_password_notice

  refresh_repo_by_clone "${REPO_NAMES[0]}" "${REPO_URLS[0]}" || failed=1
  refresh_repo_by_clone "${REPO_NAMES[1]}" "${REPO_URLS[1]}" || failed=1
  refresh_repo_by_clone "${REPO_NAMES[2]}" "${REPO_URLS[2]}" || failed=1

  check_required_repo_files || failed=1
  run_package_all_repos || failed=1
  move_packaged_artifacts_all || failed=1
  copy_example_configs "overwrite" || failed=1
  configure_password_hashes || {
    summary_add_fail "failed to configure password hashes"
    failed=1
  }

  summary_add_warn "security reminder: replace default passwords and review sensitive release config values"

  if [[ "$failed" == "0" ]]; then
    summary_add_ok "first-install completed"
    return 0
  fi

  return 1
}

run_update() {
  local failed=0

  ensure_workspace_layout
  setup_log "update mode: refresh clone + package + move"

  if setup_require_cmd git; then
    summary_add_ok "git available"
  else
    summary_add_fail "git is required before update"
    return 1
  fi

  backup_update_configs || failed=1

  refresh_repo_by_clone "${REPO_NAMES[0]}" "${REPO_URLS[0]}" || failed=1
  refresh_repo_by_clone "${REPO_NAMES[1]}" "${REPO_URLS[1]}" || failed=1
  refresh_repo_by_clone "${REPO_NAMES[2]}" "${REPO_URLS[2]}" || failed=1

  check_required_repo_files || failed=1
  run_package_all_repos || failed=1
  move_packaged_artifacts_all || failed=1
  restore_update_configs || failed=1
  copy_example_configs "if-missing" || failed=1

  cleanup_update_config_backup

  if [[ "$failed" == "0" ]]; then
    summary_add_ok "update completed"
    return 0
  fi

  return 1
}

run_start() {
  local failed=0

  if ! check_runtime_environment_before_start; then
    return 1
  fi

  start_term_webclient || failed=1
  start_zenmind_app_server || failed=1
  start_agent_platform_runner || failed=1
  health_check_after_start || failed=1

  if [[ "$failed" == "0" ]]; then
    summary_add_ok "start completed"
    return 0
  fi

  return 1
}

run_stop() {
  local failed=0

  stop_agent_platform_runner || failed=1
  stop_zenmind_app_server || failed=1
  stop_term_webclient || failed=1

  if [[ "$failed" == "0" ]]; then
    summary_add_ok "stop completed"
    return 0
  fi

  return 1
}

dispatch_action() {
  local action="$1"
  local status=0

  summary_reset

  case "$action" in
  precheck)
    run_precheck || status=1
    print_summary "precheck"
    ;;
  first-install)
    run_first_install || status=1
    print_summary "first-install"
    ;;
  update)
    run_update || status=1
    print_summary "update"
    ;;
  start)
    run_start || status=1
    print_summary "start"
    ;;
  stop)
    run_stop || status=1
    print_summary "stop"
    ;;
  reset-password-hash)
    run_reset_password_hash || status=1
    print_summary "reset-password-hash"
    ;;
  *)
    summary_add_fail "unsupported action: $action"
    print_summary "unknown"
    status=1
    ;;
  esac

  return "$status"
}

menu_loop() {
  local choice

  while true; do
    echo
    cat <<'MENU'
================ Setup Menu ================
1) 环境检测
2) 首次安装
3) 更新
4) 启动
5) 停止
6) 重置密码哈希
0) 退出
===========================================
MENU

    read -r -p "请输入数字 [0-6]: " choice
    case "$choice" in
    1) dispatch_action "precheck" ;;
    2) dispatch_action "first-install" ;;
    3) dispatch_action "update" ;;
    4) dispatch_action "start" ;;
    5) dispatch_action "stop" ;;
    6) dispatch_action "reset-password-hash" ;;
    0)
      setup_log "exit setup menu"
      return 0
      ;;
    *)
      setup_warn "invalid choice: $choice (allowed: 0-6)"
      ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [[ -n "$ACTION" ]]; then
    dispatch_action "$ACTION"
    return $?
  fi

  menu_loop
}

main "$@"
