#!/usr/bin/env bash

readonly ZENMIND_PRODUCTS=(
  "gateway"
  "zenmind-app-server"
  "zenmind-voice-server"
  "pan-webclient"
  "term-webclient"
  "mcp-server-imagine"
  "mcp-server-mock"
  "agent-platform-runner"
  "agent-container-hub"
)

readonly ZENMIND_IMAGE_PRODUCTS=(
  "gateway"
  "zenmind-app-server"
  "zenmind-voice-server"
  "pan-webclient"
  "term-webclient"
  "mcp-server-imagine"
  "mcp-server-mock"
  "agent-platform-runner"
)

readonly ZENMIND_HOST_PRODUCTS=(
  "agent-container-hub"
)

readonly ZENMIND_COMPOSE_SERVICES=(
  "gateway"
  "zenmind-app-server-backend"
  "zenmind-app-server-frontend"
  "zenmind-voice-server"
  "pan-webclient-api"
  "pan-webclient-frontend"
  "term-webclient-backend"
  "term-webclient-frontend"
  "mcp-server-imagine"
  "mcp-server-mock"
  "agent-platform-runner"
)

readonly ZENMIND_MAC_DOWNLOAD_REPOS=(
  "zenmind-app-server|https://github.com/linlay/zenmind-app-server-go.git"
  "zenmind-voice-server|https://github.com/linlay/zenmind-voice-server.git"
  "zenmind-gateway|https://github.com/linlay/zenmind-gateway.git"
  "agent-platform-runner|https://github.com/linlay/agent-platform-runner.git"
  "agent-container-hub|https://github.com/linlay/agent-container-hub.git"
  "pan-webclient|https://github.com/linlay/pan-webclient.git"
  "term-webclient|https://github.com/linlay/term-webclient.git"
  "mcp-server-mock|https://github.com/linlay/mcp-server-mock.git"
  "mcp-server-imagine|https://github.com/linlay/mcp-server-imagine.git"
)

zenmind_usage() {
  local usage_download_menu=""
  local usage_action_suffix=""

  if [[ "${ZENMIND_OS:-}" == "mac" ]]; then
    usage_download_menu=$'  6) 下载所有\n'
    usage_action_suffix=" | download-all"
  fi

  cat <<USAGE
Usage: ./setup-<os>.sh [--action ACTION] [options]

Interactive menu (default):
  1) 环境检测
  2) 配置
  3) 启动
  4) 停止
  5) 查看
${usage_download_menu}  0) 退出

Options:
  --action  check | configure | start | stop | view${usage_action_suffix}
  --web          configure mode: open the local HTML config editor
  --cli          configure mode: run the interactive CLI wizard
  --sync-only    configure mode: regenerate derived files only
  --logs <name>  view mode: show logs for one product/service or all
  --tail <N>     view mode: number of log lines to show (default 100)
  --follow       view mode: follow logs
  --yes          non-interactive mode
  -h, --help

Deprecated aliases (still accepted for now):
  precheck -> check
  edit-config -> configure --web
  apply-config -> configure --sync-only
  status -> view
USAGE
}

zenmind_summary_reset() {
  SUMMARY_OK=()
  SUMMARY_WARN=()
  SUMMARY_FAIL=()
}

zenmind_summary_add_ok() {
  SUMMARY_OK+=("$1")
  setup_log "$1"
}

zenmind_summary_add_warn() {
  SUMMARY_WARN+=("$1")
  setup_warn "$1"
}

zenmind_summary_add_fail() {
  SUMMARY_FAIL+=("$1")
  setup_err "$1"
}

zenmind_print_summary() {
  local title="$1"
  local item

  echo
  setup_log "===== ${title} summary ====="
  if [[ ${#SUMMARY_OK[@]} -gt 0 ]]; then
    for item in "${SUMMARY_OK[@]}"; do
      setup_log "  - $item"
    done
  fi
  if [[ ${#SUMMARY_WARN[@]} -gt 0 ]]; then
    for item in "${SUMMARY_WARN[@]}"; do
      setup_warn "  - $item"
    done
  fi
  if [[ ${#SUMMARY_FAIL[@]} -gt 0 ]]; then
    for item in "${SUMMARY_FAIL[@]}"; do
      setup_err "  - $item"
    done
  fi
}

zenmind_profile_path() {
  printf '%s/config/zenmind.profile.local.json\n' "$SCRIPT_DIR"
}

zenmind_compose_env_path() {
  printf '%s/generated/docker-compose.env\n' "$SCRIPT_DIR"
}

zenmind_compose_override_path() {
  printf '%s/generated/docker-compose.override.yml\n' "$SCRIPT_DIR"
}

zenmind_startup_config_path() {
  printf '%s/config/startup-services.conf\n' "$SCRIPT_DIR"
}

zenmind_repo_root_path() {
  printf '%s\n' "$(cd "${SCRIPT_DIR}/.." && pwd)"
}

zenmind_generated_run_dir() {
  printf '%s/generated/run\n' "$SCRIPT_DIR"
}

zenmind_generated_logs_dir() {
  printf '%s/generated/logs\n' "$SCRIPT_DIR"
}

zenmind_trim_line() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  printf '%s\n' "$line"
}

zenmind_strip_startup_comment() {
  local line="$1"
  line="${line%%#*}"
  zenmind_trim_line "$line"
}

zenmind_read_startup_products() {
  local startup_file line
  startup_file="$(zenmind_startup_config_path)"
  [[ -f "$startup_file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(zenmind_strip_startup_comment "$line")"
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line"
  done <"$startup_file"
}

zenmind_product_runtime_type() {
  case "$1" in
    agent-container-hub) printf 'host' ;;
    *) printf 'image' ;;
  esac
}

zenmind_product_repo_name() {
  case "$1" in
    gateway) printf 'zenmind-gateway' ;;
    *) printf '%s' "$1" ;;
  esac
}

zenmind_product_enabled_in_startup() {
  local target="$1"
  local product
  while IFS= read -r product || [[ -n "$product" ]]; do
    [[ "$product" == "$target" ]] && return 0
  done < <(zenmind_read_startup_products)
  return 1
}

zenmind_host_service_pid_file() {
  printf '%s/%s.pid\n' "$(zenmind_generated_run_dir)" "$1"
}

zenmind_host_service_log_file() {
  printf '%s/%s.log\n' "$(zenmind_generated_logs_dir)" "$1"
}

zenmind_host_service_repo_dir() {
  printf '%s/%s\n' "$(zenmind_repo_root_path)" "$1"
}

zenmind_read_env_value() {
  local env_file="$1"
  local key="$2"
  local value
  [[ -f "$env_file" ]] || return 1
  value="$(awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/, "", $0); print $0; exit }' "$env_file")"
  value="${value#\'}"
  value="${value%\'}"
  value="${value#\"}"
  value="${value%\"}"
  printf '%s\n' "$value"
}

zenmind_host_service_bind_addr() {
  local product="$1"
  local env_file value
  env_file="$(zenmind_host_service_repo_dir "$product")/.env"
  value="$(zenmind_read_env_value "$env_file" "BIND_ADDR" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  printf '127.0.0.1:11960\n'
}

zenmind_host_service_port() {
  local bind_addr
  bind_addr="$(zenmind_host_service_bind_addr "$1")"
  printf '%s\n' "${bind_addr##*:}"
}

zenmind_ensure_profile() {
  if [[ ! -f "$(zenmind_profile_path)" ]]; then
    cp "${SCRIPT_DIR}/config/zenmind.profile.example.json" "$(zenmind_profile_path)"
    zenmind_summary_add_warn "created local profile from example: $(zenmind_profile_path)"
  fi
}

zenmind_apply_config() {
  zenmind_ensure_profile
  if node "${SCRIPT_DIR}/scripts/apply-config.mjs" --workspace-root "$SCRIPT_DIR" --profile "$(zenmind_profile_path)"; then
    zenmind_summary_add_ok "synced aggregate JSON into sibling repos and generated files"
  else
    zenmind_summary_add_fail "failed to sync aggregate JSON into derived files"
    return 1
  fi
}

zenmind_source_compose_env() {
  local env_path
  env_path="$(zenmind_compose_env_path)"
  [[ -f "$env_path" ]] || return 1
  set -a
  # shellcheck disable=SC1090
  source "$env_path"
  set +a
}

zenmind_product_enabled() {
  zenmind_product_enabled_in_startup "$1"
}

zenmind_expand_products() {
  local line
  local services=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      gateway) services+=("gateway") ;;
      zenmind-app-server) services+=("zenmind-app-server-backend" "zenmind-app-server-frontend") ;;
      zenmind-voice-server) services+=("zenmind-voice-server") ;;
      pan-webclient) services+=("pan-webclient-api" "pan-webclient-frontend") ;;
      term-webclient) services+=("term-webclient-backend" "term-webclient-frontend") ;;
      mcp-server-imagine) services+=("mcp-server-imagine") ;;
      mcp-server-mock) services+=("mcp-server-mock") ;;
      agent-platform-runner) services+=("agent-platform-runner") ;;
      agent-container-hub) ;;
      *)
        zenmind_summary_add_fail "unknown product in startup list: $line"
        return 1
        ;;
    esac
  done < <(zenmind_read_startup_products)
  printf '%s\n' "${services[@]}"
}

zenmind_compose_cmd() {
  docker compose --env-file "$(zenmind_compose_env_path)" -f "${SCRIPT_DIR}/docker-compose.yml" -f "$(zenmind_compose_override_path)" "$@"
}

zenmind_actual_service_exists() {
  local target="$1"
  local service
  for service in "${ZENMIND_COMPOSE_SERVICES[@]}"; do
    if [[ "$service" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

zenmind_warn_deprecated_alias() {
  local message="$1"
  zenmind_summary_add_warn "deprecated action alias used: ${message}"
}

zenmind_configure_mode_label() {
  case "${CONFIGURE_MODE:-}" in
    web) printf 'web editor' ;;
    cli) printf 'CLI wizard' ;;
    sync-only) printf 'sync-only' ;;
    *) printf 'unspecified' ;;
  esac
}

zenmind_prompt_configure_mode() {
  if [[ -n "${CONFIGURE_MODE:-}" ]]; then
    return 0
  fi

  if [[ "${NON_INTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    CONFIGURE_MODE="sync-only"
    zenmind_summary_add_warn "configure mode not specified in non-interactive context; defaulting to sync-only"
    return 0
  fi

  local choice
  echo
  echo "Choose configure mode:"
  echo "  1) Web editor"
  echo "  2) CLI wizard"
  echo "  3) Sync-only"
  read -r -p "Select [1]: " choice
  case "${choice:-1}" in
    1) CONFIGURE_MODE="web" ;;
    2) CONFIGURE_MODE="cli" ;;
    3) CONFIGURE_MODE="sync-only" ;;
    *)
      CONFIGURE_MODE="web"
      zenmind_summary_add_warn "unknown configure choice '${choice}', defaulting to web editor"
      ;;
  esac
}

zenmind_run_check() {
  local check_script
  check_script="${SCRIPT_DIR}/scripts/${ZENMIND_OS}/check-environment.sh"
  if [[ ! -x "$check_script" ]]; then
    zenmind_summary_add_fail "missing check script: $check_script"
    return 1
  fi

  if "$check_script" --mode all; then
    zenmind_summary_add_ok "environment check passed"
  else
    zenmind_summary_add_fail "environment check reported blockers"
    return 1
  fi
}

zenmind_run_configure() {
  zenmind_prompt_configure_mode
  zenmind_ensure_profile

  case "${CONFIGURE_MODE:-}" in
    web)
      local editor_path
      editor_path="${SCRIPT_DIR}/config/editor/index.html"
      zenmind_summary_add_ok "config editor ready: ${editor_path}"
      zenmind_summary_add_ok "aggregate JSON path: $(zenmind_profile_path)"
      case "$ZENMIND_OS" in
        mac)
          if command -v open >/dev/null 2>&1; then
            open "$editor_path" || zenmind_summary_add_warn "failed to auto-open config editor"
          fi
          ;;
        linux)
          if command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$editor_path" >/dev/null 2>&1 || zenmind_summary_add_warn "failed to auto-open config editor"
          fi
          ;;
      esac
      ;;
    cli)
      if node "${SCRIPT_DIR}/scripts/configure-profile.mjs" --workspace-root "$SCRIPT_DIR" --profile "$(zenmind_profile_path)"; then
        zenmind_summary_add_ok "updated aggregate JSON via CLI wizard"
      else
        zenmind_summary_add_fail "CLI wizard failed"
        return 1
      fi
      ;;
    sync-only)
      zenmind_apply_config || return 1
      ;;
    *)
      zenmind_summary_add_fail "unsupported configure mode: ${CONFIGURE_MODE:-}"
      return 1
      ;;
  esac
}

zenmind_validate_remote_image_config() {
  zenmind_source_compose_env || {
    zenmind_summary_add_fail "generated compose env is missing"
    return 1
  }

  if [[ -z "${IMAGE_REGISTRY:-}" || -z "${IMAGE_TAG:-}" ]]; then
    zenmind_summary_add_fail "image registry/tag are missing from the aggregate JSON"
    zenmind_summary_add_warn "configure them via: ./setup-${ZENMIND_OS}.sh --action configure --cli"
    return 1
  fi

  if [[ "${IMAGE_REGISTRY}" == "registry.example.com/zenmind" ]]; then
    zenmind_summary_add_fail "images.registry is still using the placeholder value: ${IMAGE_REGISTRY}"
    zenmind_summary_add_warn "set a real registry in the aggregate JSON before start"
    return 1
  fi

  zenmind_summary_add_ok "remote image source configured: ${IMAGE_REGISTRY} (tag ${IMAGE_TAG})"
}

zenmind_collect_service_images() {
  local compose_output
  compose_output="$(zenmind_compose_cmd config 2>/dev/null)" || return 1
  printf '%s\n' "$compose_output" | awk '
    /^services:/ { in_services = 1; next }
    in_services && /^[^[:space:]]/ { in_services = 0 }
    in_services && /^  [A-Za-z0-9_.-]+:$/ {
      service = $1
      sub(/:$/, "", service)
      next
    }
    in_services && /^    image: / {
      image = $2
      gsub(/"/, "", image)
      print service "|" image
    }
  '
}

zenmind_prepare_remote_images() {
  local requested_services=("$@")
  local mappings service image
  local -a unique_images=()
  local known_images=$'\n'

  if ! mappings="$(zenmind_collect_service_images)"; then
    zenmind_summary_add_fail "unable to resolve compose images from the final config"
    return 1
  fi

  while IFS='|' read -r service image; do
    [[ -n "$service" && -n "$image" ]] || continue
    local selected=0 requested
    for requested in "${requested_services[@]}"; do
      if [[ "$requested" == "$service" ]]; then
        selected=1
        break
      fi
    done
    [[ "$selected" == "1" ]] || continue

    if [[ "$known_images" == *$'\n'"$image"$'\n'* ]]; then
      continue
    fi
    known_images+="${image}"$'\n'
    unique_images+=("$image")
  done <<<"$mappings"

  if [[ ${#unique_images[@]} -eq 0 ]]; then
    zenmind_summary_add_fail "no image references found for the selected services"
    return 1
  fi

  for image in "${unique_images[@]}"; do
    if docker image inspect "$image" >/dev/null 2>&1; then
      zenmind_summary_add_ok "image already present locally: $image"
      continue
    fi

    setup_log "pulling image: $image"
    if docker pull "$image"; then
      zenmind_summary_add_ok "pulled image: $image"
    else
      zenmind_summary_add_fail "failed to pull image: $image"
      zenmind_summary_add_warn "check docker login / registry access and retry start"
      return 1
    fi
  done
}

zenmind_check_cloudflare_status() {
  local cf_dir config_file pid_file pid
  cf_dir="${HOME}/.cloudflared"
  config_file="${cf_dir}/config.yml"
  pid_file="${cf_dir}/cloudflared.pid"

  if ! command -v cloudflared >/dev/null 2>&1; then
    zenmind_summary_add_warn "cloudflared not installed; install with: brew install cloudflare/cloudflare/cloudflared"
    return 0
  fi

  zenmind_summary_add_ok "cloudflared installed"

  if [[ -f "$config_file" ]]; then
    zenmind_summary_add_ok "cloudflared config found: $config_file"
  else
    zenmind_summary_add_warn "cloudflared config missing; configure with: ./scripts/${ZENMIND_OS}/setup-cf-tunnel.sh"
  fi

  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      zenmind_summary_add_ok "cloudflared running (PID: $pid)"
      return 0
    fi
  fi

  zenmind_summary_add_warn "cloudflared not running; start with: ./scripts/${ZENMIND_OS}/start-cf-tunnel.sh"
  return 0
}

zenmind_check_gateway_health() {
  if zenmind_source_compose_env && curl -fsS "http://${GATEWAY_LISTEN_IP}:${GATEWAY_PORT}/healthz" >/dev/null 2>&1; then
    zenmind_summary_add_ok "gateway healthz reachable: http://${GATEWAY_LISTEN_IP}:${GATEWAY_PORT}/healthz"
    return 0
  fi

  zenmind_summary_add_warn "gateway healthz unavailable"
  return 0
}

zenmind_start_host_service() {
  local product="$1"
  local repo_dir pid_file log_file env_file bind_addr port pid

  repo_dir="$(zenmind_host_service_repo_dir "$product")"
  pid_file="$(zenmind_host_service_pid_file "$product")"
  log_file="$(zenmind_host_service_log_file "$product")"
  env_file="${repo_dir}/.env"

  if [[ ! -d "$repo_dir" ]]; then
    zenmind_summary_add_fail "host service repo missing: ${repo_dir}"
    return 1
  fi
  if ! setup_require_cmd go; then
    zenmind_summary_add_fail "go is required for host service: ${product}"
    return 1
  fi

  mkdir -p "$(zenmind_generated_run_dir)" "$(zenmind_generated_logs_dir)"
  if setup_process_running_from_pid_file "$pid_file"; then
    zenmind_summary_add_ok "host service already running: ${product}"
    return 0
  fi

  (
    cd "$repo_dir"
    set -a
    [[ -f "$env_file" ]] && source "$env_file"
    set +a
    nohup go run ./cmd/agent-container-hub >"$log_file" 2>&1 &
    echo "$!" >"$pid_file"
  )

  sleep 2
  if ! setup_process_running_from_pid_file "$pid_file"; then
    zenmind_summary_add_fail "host service exited early: ${product}"
    zenmind_summary_add_warn "check log file: ${log_file}"
    return 1
  fi

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  bind_addr="$(zenmind_host_service_bind_addr "$product")"
  port="$(zenmind_host_service_port "$product")"
  zenmind_summary_add_ok "started host service: ${product} (PID ${pid:-unknown}, bind ${bind_addr})"
  if curl -sS -o /dev/null -m 2 "http://127.0.0.1:${port}/api/sessions" 2>/dev/null; then
    zenmind_summary_add_ok "host service reachable: ${product}"
  else
    zenmind_summary_add_warn "host service port not yet reachable: ${product}"
  fi
}

zenmind_stop_host_service() {
  local product="$1"
  local pid_file
  pid_file="$(zenmind_host_service_pid_file "$product")"
  if setup_stop_process_by_pid_file "$pid_file"; then
    zenmind_summary_add_ok "stopped host service: ${product}"
    return 0
  fi
  zenmind_summary_add_warn "host service not running: ${product}"
  return 0
}

zenmind_view_host_service() {
  local product="$1"
  local pid_file log_file bind_addr port pid
  pid_file="$(zenmind_host_service_pid_file "$product")"
  log_file="$(zenmind_host_service_log_file "$product")"
  bind_addr="$(zenmind_host_service_bind_addr "$product")"
  port="$(zenmind_host_service_port "$product")"

  if setup_process_running_from_pid_file "$pid_file"; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    zenmind_summary_add_ok "host service running: ${product} (PID ${pid:-unknown}, bind ${bind_addr})"
  else
    zenmind_summary_add_warn "host service not running: ${product}"
    return 0
  fi

  if curl -sS -o /dev/null -m 2 "http://127.0.0.1:${port}/api/sessions" 2>/dev/null; then
    zenmind_summary_add_ok "host service reachable: ${product}"
  else
    zenmind_summary_add_warn "host service port not reachable: ${product}"
  fi

  if [[ -f "$log_file" ]]; then
    zenmind_summary_add_ok "host service log file: ${log_file}"
  fi
}

zenmind_run_start() {
  local services
  local product

  if ! setup_prepare_docker_alias; then
    zenmind_summary_add_fail "docker is required for start"
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    zenmind_summary_add_fail "docker compose is required for start"
    return 1
  fi
  if ! setup_docker_daemon_running; then
    zenmind_summary_add_fail "docker daemon is not running; start Docker Desktop first"
    return 1
  fi

  zenmind_apply_config || return 1
  zenmind_validate_remote_image_config || return 1
  for product in "${ZENMIND_HOST_PRODUCTS[@]}"; do
    if zenmind_product_enabled "$product"; then
      zenmind_start_host_service "$product" || return 1
    fi
  done
  mapfile -t services < <(zenmind_expand_products) || return 1
  zenmind_prepare_remote_images "${services[@]}" || return 1

  if zenmind_compose_cmd up -d "${services[@]}"; then
    zenmind_summary_add_ok "started selected services"
  else
    zenmind_summary_add_fail "docker compose up failed"
    return 1
  fi

  zenmind_check_gateway_health
  zenmind_check_cloudflare_status
}

zenmind_run_stop() {
  local services
  local product

  if ! setup_prepare_docker_alias; then
    zenmind_summary_add_fail "docker is required for stop"
    return 1
  fi

  mapfile -t services < <(zenmind_expand_products) || return 1
  if zenmind_compose_cmd stop "${services[@]}"; then
    zenmind_summary_add_ok "stopped selected containers"
  else
    zenmind_summary_add_fail "docker compose stop failed"
    return 1
  fi

  for product in "${ZENMIND_HOST_PRODUCTS[@]}"; do
    if zenmind_product_enabled "$product"; then
      zenmind_stop_host_service "$product" || return 1
    fi
  done
}

zenmind_expand_log_targets() {
  local target="$1"
  case "$target" in
    all)
      printf '%s\n' "${ZENMIND_COMPOSE_SERVICES[@]}"
      return 0
      ;;
    gateway)
      printf '%s\n' "gateway"
      return 0
      ;;
    zenmind-app-server)
      printf '%s\n' "zenmind-app-server-backend" "zenmind-app-server-frontend"
      return 0
      ;;
    zenmind-voice-server)
      printf '%s\n' "zenmind-voice-server"
      return 0
      ;;
    pan-webclient)
      printf '%s\n' "pan-webclient-api" "pan-webclient-frontend"
      return 0
      ;;
    term-webclient)
      printf '%s\n' "term-webclient-backend" "term-webclient-frontend"
      return 0
      ;;
    mcp-server-imagine|mcp-server-mock|agent-platform-runner)
      printf '%s\n' "$target"
      return 0
      ;;
  esac

  if zenmind_actual_service_exists "$target"; then
    printf '%s\n' "$target"
    return 0
  fi

  return 1
}

zenmind_run_host_logs() {
  local target="$1"
  local tail_count="${VIEW_TAIL:-100}"
  local log_file
  log_file="$(zenmind_host_service_log_file "$target")"

  if [[ ! -f "$log_file" ]]; then
    zenmind_summary_add_fail "host log file missing: $log_file"
    return 1
  fi

  if [[ "${VIEW_FOLLOW:-0}" == "1" ]]; then
    tail -n "$tail_count" -f "$log_file"
  else
    tail -n "$tail_count" "$log_file"
  fi
  zenmind_summary_add_ok "showed host logs for: $target"
}

zenmind_run_logs() {
  local targets
  local tail_count="${VIEW_TAIL:-100}"
  local -a cmd_args=("logs" "--tail" "$tail_count")

  if [[ "$VIEW_LOG_TARGET" == "agent-container-hub" ]]; then
    zenmind_run_host_logs "$VIEW_LOG_TARGET"
    return $?
  fi

  if [[ "${VIEW_FOLLOW:-0}" == "1" ]]; then
    cmd_args+=("-f")
  fi

  if ! targets="$(zenmind_expand_log_targets "$VIEW_LOG_TARGET")"; then
    zenmind_summary_add_fail "unknown log target: $VIEW_LOG_TARGET"
    zenmind_summary_add_warn "use --logs all, a product name, a compose service name, or agent-container-hub"
    return 1
  fi

  mapfile -t target_list <<<"$targets"
  zenmind_compose_cmd "${cmd_args[@]}" "${target_list[@]}"
  if [[ "$VIEW_LOG_TARGET" == "all" && "${VIEW_FOLLOW:-0}" != "1" ]] && zenmind_product_enabled "agent-container-hub"; then
    zenmind_run_host_logs "agent-container-hub" || return 1
  fi
  zenmind_summary_add_ok "showed logs for: $VIEW_LOG_TARGET"
}

zenmind_run_view() {
  if ! setup_prepare_docker_alias; then
    zenmind_summary_add_fail "docker is required for view"
    return 1
  fi

  zenmind_apply_config || return 1

  zenmind_compose_cmd ps || zenmind_summary_add_warn "docker compose ps returned a non-zero exit code"
  local product
  for product in "${ZENMIND_HOST_PRODUCTS[@]}"; do
    if zenmind_product_enabled "$product"; then
      zenmind_view_host_service "$product"
    fi
  done
  zenmind_check_gateway_health
  zenmind_check_cloudflare_status

  if [[ -n "${VIEW_LOG_TARGET:-}" ]]; then
    zenmind_run_logs || return 1
  fi
}

zenmind_download_repo() {
  local repo_name="$1"
  local repo_url="$2"
  local repo_root repo_dir status_output

  repo_root="$(zenmind_repo_root_path)"
  repo_dir="${repo_root}/${repo_name}"

  if [[ ! -e "$repo_dir" ]]; then
    setup_log "cloning ${repo_url} -> ${repo_dir}"
    if git clone "$repo_url" "$repo_dir"; then
      zenmind_summary_add_ok "cloned repo: ${repo_name}"
      return 0
    fi
    zenmind_summary_add_fail "failed to clone repo: ${repo_name}"
    return 1
  fi

  if ! git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    zenmind_summary_add_warn "skip existing non-git directory: ${repo_dir}"
    return 0
  fi

  status_output="$(git -C "$repo_dir" status --porcelain 2>/dev/null || true)"
  if [[ -n "$status_output" ]]; then
    zenmind_summary_add_warn "skip dirty repo: ${repo_name}"
    return 0
  fi

  setup_log "pulling repo: ${repo_name}"
  if git -C "$repo_dir" pull --ff-only; then
    zenmind_summary_add_ok "updated repo: ${repo_name}"
    return 0
  fi

  zenmind_summary_add_fail "failed to update repo: ${repo_name}"
  return 1
}

zenmind_run_download_all() {
  local entry repo_name repo_url
  local failed=0

  if [[ "${ZENMIND_OS}" != "mac" ]]; then
    zenmind_summary_add_fail "download-all is only supported on macOS"
    return 1
  fi

  if ! setup_require_cmd git; then
    zenmind_summary_add_fail "git is required for download-all"
    return 1
  fi
  zenmind_summary_add_ok "git available"
  zenmind_summary_add_ok "repo root: $(zenmind_repo_root_path)"

  for entry in "${ZENMIND_MAC_DOWNLOAD_REPOS[@]}"; do
    repo_name="${entry%%|*}"
    repo_url="${entry#*|}"
    if ! zenmind_download_repo "$repo_name" "$repo_url"; then
      failed=1
    fi
  done

  if [[ "$failed" == "0" ]]; then
    zenmind_summary_add_ok "download-all completed"
    return 0
  fi
  return 1
}

zenmind_menu() {
  local menu_download_line=""

  if [[ "${ZENMIND_OS:-}" == "mac" ]]; then
    menu_download_line=$'6) 下载所有\n'
  fi

  cat <<MENU
1) 环境检测
2) 配置
3) 启动
4) 停止
5) 查看
${menu_download_line}0) 退出
MENU
}

zenmind_parse_args() {
  ACTION=""
  NON_INTERACTIVE=0
  CONFIGURE_MODE=""
  VIEW_LOG_TARGET=""
  VIEW_TAIL=100
  VIEW_FOLLOW=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action)
        ACTION="$2"
        shift 2
        ;;
      --web)
        CONFIGURE_MODE="web"
        shift
        ;;
      --cli)
        CONFIGURE_MODE="cli"
        shift
        ;;
      --sync-only)
        CONFIGURE_MODE="sync-only"
        shift
        ;;
      --logs)
        VIEW_LOG_TARGET="$2"
        shift 2
        ;;
      --tail)
        VIEW_TAIL="$2"
        shift 2
        ;;
      --follow)
        VIEW_FOLLOW=1
        shift
        ;;
      --yes)
        NON_INTERACTIVE=1
        shift
        ;;
      -h|--help)
        zenmind_usage
        exit 0
        ;;
      *)
        setup_err "unknown option: $1"
        zenmind_usage
        exit 1
        ;;
    esac
  done

  case "$ACTION" in
    precheck)
      zenmind_warn_deprecated_alias "precheck -> check"
      ACTION="check"
      ;;
    edit-config)
      zenmind_warn_deprecated_alias "edit-config -> configure --web"
      ACTION="configure"
      CONFIGURE_MODE="${CONFIGURE_MODE:-web}"
      ;;
    apply-config)
      zenmind_warn_deprecated_alias "apply-config -> configure --sync-only"
      ACTION="configure"
      CONFIGURE_MODE="${CONFIGURE_MODE:-sync-only}"
      ;;
    status)
      zenmind_warn_deprecated_alias "status -> view"
      ACTION="view"
      ;;
  esac
}

zenmind_dispatch() {
  case "$ACTION" in
    check) zenmind_run_check ;;
    configure) zenmind_run_configure ;;
    start) zenmind_run_start ;;
    stop) zenmind_run_stop ;;
    view) zenmind_run_view ;;
    download-all) zenmind_run_download_all ;;
    *)
      zenmind_summary_add_fail "unsupported action: $ACTION"
      return 1
      ;;
  esac
}

zenmind_interactive_loop() {
  local choice
  while true; do
    echo
    zenmind_menu
    read -r -p "Select an action: " choice
    case "$choice" in
      1) ACTION="check" ;;
      2) ACTION="configure"; CONFIGURE_MODE="" ;;
      3) ACTION="start" ;;
      4) ACTION="stop" ;;
      5) ACTION="view" ;;
      6)
        if [[ "${ZENMIND_OS}" == "mac" ]]; then
          ACTION="download-all"
        else
          setup_warn "unknown choice: $choice"
          continue
        fi
        ;;
      0) exit 0 ;;
      *) setup_warn "unknown choice: $choice"; continue ;;
    esac
    zenmind_summary_reset
    zenmind_dispatch
    zenmind_print_summary "$ACTION"
  done
}

zenmind_main() {
  ZENMIND_OS="$1"
  shift
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  zenmind_summary_reset
  zenmind_parse_args "$@"
  if [[ -z "${ACTION:-}" ]]; then
    zenmind_interactive_loop
    return 0
  fi
  zenmind_dispatch
  zenmind_print_summary "$ACTION"
}
