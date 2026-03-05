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
  "mcp-server-mock"
)
readonly REQUIRED_START_ORDER=(
  "zenmind-app-server"
  "mcp-server-mock"
  "agent-platform-runner"
  "term-webclient"
)
readonly REQUIRED_STOP_ORDER=(
  "term-webclient"
  "agent-platform-runner"
  "mcp-server-mock"
  "zenmind-app-server"
)

# format: source|target|required
readonly CONFIG_MAPPINGS=(
  "source/term-webclient/.env.example|release/term-webclient/.env|true"
  "source/term-webclient/application.example.yml|release/term-webclient/application.yml|true"
  "source/zenmind-app-server/.env.example|release/zenmind-app-server/.env|true"
  "source/agent-platform-runner/application.example.yml|release/agent-platform-runner/application.yml|true"
  "source/mcp-server-mock/.env.example|release/mcp-server-mock/.env|true"
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

repo_url() {
  local repo="$1"
  printf 'https://github.com/linlay/%s.git\n' "$repo"
}

repo_packaged_output_dir() {
  local repo="$1"
  case "$repo" in
  term-webclient | zenmind-app-server | mcp-server-mock)
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

repo_package_script_rel() {
  local repo="$1"
  case "$repo" in
  term-webclient | zenmind-app-server | mcp-server-mock)
    printf 'release-scripts/mac/package.sh\n'
    ;;
  agent-platform-runner)
    printf 'release-scripts/mac/package-local.sh\n'
    ;;
  *)
    return 1
    ;;
  esac
}

repo_pid_files() {
  local repo="$1"
  case "$repo" in
  term-webclient)
    printf '%s\n' "run/backend.pid" "run/frontend.pid"
    ;;
  *)
    printf '%s\n' "run/app.pid"
    ;;
  esac
}

repo_start_script_abs() {
  local repo="$1"
  printf '%s/release-scripts/mac/start.sh\n' "$(repo_release_dir "$repo")"
}

repo_stop_script_abs() {
  local repo="$1"
  printf '%s/release-scripts/mac/stop.sh\n' "$(repo_release_dir "$repo")"
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
  - Install dependencies: brew install git go openjdk@21 maven node@20
  - Ensure Go version is 1.26.0 or newer
  - Verify each service repo has release-scripts/mac/package*.sh and release-scripts/mac/start.sh/stop.sh
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
  local repo package_script

  for repo in "${REPO_NAMES[@]}"; do
    check_repo_file "$repo" "README.md" || failed=1
    package_script="$(repo_package_script_rel "$repo")" || {
      summary_add_fail "unsupported repo for package script: $repo"
      failed=1
      continue
    }
    check_repo_file "$repo" "$package_script" || failed=1
  done

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

run_package_repo() {
  local repo="$1"
  local repo_dir package_script

  repo_dir="$(repo_source_dir "$repo")"
  package_script="$(repo_package_script_rel "$repo")" || {
    summary_add_fail "unsupported repo for package: $repo"
    return 1
  }

  setup_log "packaging $repo via ./$package_script"
  if (cd "$repo_dir" && "./$package_script"); then
    summary_add_ok "packaged $repo"
    return 0
  fi

  summary_add_fail "failed to package $repo (run: cd $repo_dir && ./$package_script)"
  return 1
}

run_package_all_repos() {
  local failed=0
  local repo

  for repo in "${REPO_NAMES[@]}"; do
    run_package_repo "$repo" || failed=1
  done

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
  local repo

  for repo in "${REPO_NAMES[@]}"; do
    move_packaged_artifacts_for_repo "$repo" || failed=1
  done

  return "$failed"
}

validate_release_artifacts() {
  local repo="$1"
  local release_repo start_script stop_script
  local missing=()

  release_repo="$(repo_release_dir "$repo")"
  start_script="$(repo_start_script_abs "$repo")"
  stop_script="$(repo_stop_script_abs "$repo")"

  [[ -d "$release_repo" ]] || missing+=("$release_repo")
  [[ -f "$start_script" ]] || missing+=("$start_script")
  [[ -f "$stop_script" ]] || missing+=("$stop_script")

  if ((${#missing[@]} > 0)); then
    summary_add_fail "$repo release incomplete, missing: $(IFS=', '; echo "${missing[*]}")"
    return 1
  fi

  if [[ ! -x "$start_script" ]]; then
    summary_add_fail "$repo release start script is not executable: $start_script"
    return 1
  fi

  if [[ ! -x "$stop_script" ]]; then
    summary_add_fail "$repo release stop script is not executable: $stop_script"
    return 1
  fi

  return 0
}

repo_running_state() {
  local repo="$1"
  local release_repo
  local running_count=0
  local total_count=0
  local pid_rel pid_file
  local -a pid_rels=()

  release_repo="$(repo_release_dir "$repo")"
  if [[ ! -d "$release_repo" ]]; then
    printf '0 0\n'
    return 0
  fi

  mapfile -t pid_rels < <(repo_pid_files "$repo")
  total_count="${#pid_rels[@]}"

  for pid_rel in "${pid_rels[@]}"; do
    pid_file="$release_repo/$pid_rel"
    if setup_process_running_from_pid_file "$pid_file"; then
      running_count=$((running_count + 1))
    fi
  done

  printf '%s %s\n' "$running_count" "$total_count"
}

kill_repo_pids_fallback() {
  local repo="$1"
  local release_repo pid_rel pid_file
  local stopped_any=0
  local -a pid_rels=()

  release_repo="$(repo_release_dir "$repo")"
  mapfile -t pid_rels < <(repo_pid_files "$repo")

  for pid_rel in "${pid_rels[@]}"; do
    pid_file="$release_repo/$pid_rel"
    if setup_stop_process_by_pid_file "$pid_file"; then
      stopped_any=1
    fi
  done

  if [[ "$stopped_any" == "1" ]]; then
    summary_add_warn "$repo stop fallback used: stopped by pid files"
  fi
}

start_repo() {
  local repo="$1"
  local source_repo release_repo
  local state running_count total_count

  source_repo="$(repo_source_dir "$repo")"
  release_repo="$(repo_release_dir "$repo")"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_fail "$repo source repo missing: $source_repo"
    return 1
  fi

  validate_release_artifacts "$repo" || return 1

  state="$(repo_running_state "$repo")"
  running_count="${state%% *}"
  total_count="${state##* }"

  if [[ "$running_count" == "$total_count" && "$total_count" != "0" ]]; then
    summary_add_ok "$repo already running"
    return 0
  fi

  if [[ "$running_count" != "0" ]]; then
    summary_add_warn "$repo partial running state detected, restart it ($running_count/$total_count)"
    if (cd "$release_repo" && ./release-scripts/mac/stop.sh); then
      :
    else
      summary_add_warn "$repo stop script failed during restart recovery, fallback to pid stop"
    fi
    kill_repo_pids_fallback "$repo"
  fi

  setup_log "starting $repo via release-scripts/mac/start.sh"
  if (cd "$release_repo" && ./release-scripts/mac/start.sh); then
    summary_add_ok "start command completed: $repo"
    return 0
  fi

  summary_add_fail "failed to start $repo"
  return 1
}

stop_repo() {
  local repo="$1"
  local source_repo release_repo state running_count total_count

  source_repo="$(repo_source_dir "$repo")"
  release_repo="$(repo_release_dir "$repo")"

  if [[ ! -d "$source_repo" ]]; then
    summary_add_fail "$repo source repo not found, cannot stop"
    return 1
  fi

  validate_release_artifacts "$repo" || return 1

  state="$(repo_running_state "$repo")"
  running_count="${state%% *}"
  total_count="${state##* }"

  if [[ "$running_count" == "0" ]]; then
    summary_add_warn "$repo is not running"
    return 0
  fi

  if (cd "$release_repo" && ./release-scripts/mac/stop.sh); then
    state="$(repo_running_state "$repo")"
    running_count="${state%% *}"
    if [[ "$running_count" == "0" ]]; then
      summary_add_ok "stop command completed: $repo"
      return 0
    fi

    summary_add_warn "$repo stop script returned success but processes are still alive, fallback to pid stop"
    kill_repo_pids_fallback "$repo"
  else
    summary_add_warn "$repo stop script failed, fallback to pid stop"
    kill_repo_pids_fallback "$repo"
  fi

  state="$(repo_running_state "$repo")"
  running_count="${state%% *}"
  total_count="${state##* }"

  if [[ "$running_count" == "0" ]]; then
    summary_add_ok "stop completed after fallback: $repo"
    return 0
  fi

  summary_add_fail "failed to stop $repo (still running: $running_count/$total_count)"
  return 1
}

health_check_after_start() {
  local failed=0
  local repo state running_count total_count

  for repo in "${REQUIRED_START_ORDER[@]}"; do
    state="$(repo_running_state "$repo")"
    running_count="${state%% *}"
    total_count="${state##* }"

    if [[ "$running_count" == "$total_count" && "$total_count" != "0" ]]; then
      if [[ "$repo" == "term-webclient" ]]; then
        summary_add_ok "health check passed: term-webclient backend/frontend pids alive"
      else
        summary_add_ok "health check passed: $repo app pid alive"
      fi
    else
      summary_add_fail "health check failed: $repo process not fully running ($running_count/$total_count)"
      failed=1
    fi
  done

  return "$failed"
}

run_first_install() {
  local failed=0
  local repo

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

  for repo in "${REPO_NAMES[@]}"; do
    refresh_repo_by_clone "$repo" "$(repo_url "$repo")" || failed=1
  done

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
  local repo

  ensure_workspace_layout
  setup_log "update mode: refresh clone + package + move"

  if setup_require_cmd git; then
    summary_add_ok "git available"
  else
    summary_add_fail "git is required before update"
    return 1
  fi

  backup_update_configs || failed=1

  for repo in "${REPO_NAMES[@]}"; do
    refresh_repo_by_clone "$repo" "$(repo_url "$repo")" || failed=1
  done

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
  local repo

  if ! check_runtime_environment_before_start; then
    return 1
  fi

  for repo in "${REQUIRED_START_ORDER[@]}"; do
    start_repo "$repo" || failed=1
  done
  health_check_after_start || failed=1

  if [[ "$failed" == "0" ]]; then
    summary_add_ok "start completed"
    return 0
  fi

  return 1
}

run_stop() {
  local failed=0
  local repo

  for repo in "${REQUIRED_STOP_ORDER[@]}"; do
    stop_repo "$repo" || failed=1
  done

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
