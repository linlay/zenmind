#!/usr/bin/env bash

readonly ZENMIND_PRODUCTS=(
  "gateway"
  "zenmind-app-server"
  "zenmind-voice-server"
  "pan-webclient"
  "term-webclient"
  "mini-app-server"
  "mcp-server-imagine"
  "mcp-server-bash"
  "mcp-server-mock"
  "mcp-server-email"
)

zenmind_usage() {
  cat <<'USAGE'
Usage: ./setup-<os>.sh [--action ACTION] [--yes]

Interactive menu (default):
  1) 环境检测
  2) 打开配置页
  3) 应用配置
  4) 启动
  5) 停止
  6) 查看状态
  7) 配置启动列表
  8) 准备 gateway nginx
  9) 配置 Cloudflare Tunnel
  0) 退出

Options:
  --action  precheck | edit-config | apply-config | start | stop | status | configure-startup | setup-nginx | setup-cf-tunnel
  --yes     非交互模式
  -h, --help
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

zenmind_ensure_profile() {
  if [[ ! -f "$(zenmind_profile_path)" ]]; then
    cp "${SCRIPT_DIR}/config/zenmind.profile.example.json" "$(zenmind_profile_path)"
    zenmind_summary_add_warn "created local profile from example: $(zenmind_profile_path)"
  fi
}

zenmind_apply_config() {
  zenmind_ensure_profile
  if node "${SCRIPT_DIR}/scripts/apply-config.mjs" --workspace-root "$SCRIPT_DIR" --profile "$(zenmind_profile_path)"; then
    zenmind_summary_add_ok "applied profile into sibling repos and generated files"
  else
    zenmind_summary_add_fail "failed to apply profile"
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
  local target="$1"
  local startup_file line
  startup_file="$(zenmind_startup_config_path)"
  [[ -f "$startup_file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == "$target" ]]; then
      return 0
    fi
  done <"$startup_file"
  return 1
}

zenmind_expand_products() {
  local startup_file line
  local services=()
  startup_file="$(zenmind_startup_config_path)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    case "$line" in
      gateway) services+=("gateway") ;;
      zenmind-app-server) services+=("zenmind-app-server-backend" "zenmind-app-server-frontend") ;;
      zenmind-voice-server) services+=("zenmind-voice-server") ;;
      pan-webclient) services+=("pan-webclient-api" "pan-webclient-frontend") ;;
      term-webclient) services+=("term-webclient-backend" "term-webclient-frontend") ;;
      mini-app-server) services+=("mini-app-server") ;;
      mcp-server-imagine) services+=("mcp-server-imagine") ;;
      mcp-server-bash) services+=("mcp-server-bash") ;;
      mcp-server-mock) services+=("mcp-server-mock") ;;
      mcp-server-email) services+=("mcp-server-email") ;;
      *)
        zenmind_summary_add_fail "unknown product in startup list: $line"
        return 1
        ;;
    esac
  done <"$startup_file"
  printf '%s\n' "${services[@]}"
}

zenmind_compose_cmd() {
  docker compose --env-file "$(zenmind_compose_env_path)" -f "${SCRIPT_DIR}/docker-compose.yml" -f "$(zenmind_compose_override_path)" "$@"
}

zenmind_run_precheck() {
  local check_script
  check_script="${SCRIPT_DIR}/scripts/${ZENMIND_OS}/check-environment.sh"
  if [[ -x "$check_script" ]] && "$check_script" --mode runtime; then
    zenmind_summary_add_ok "runtime environment check passed"
  else
    zenmind_summary_add_warn "platform runtime check did not fully pass; continuing with direct command checks"
  fi

  if [[ "$ZENMIND_OS" == "linux" ]]; then
    if setup_check_node20; then
      zenmind_summary_add_ok "node available"
    else
      zenmind_summary_add_fail "Node.js 20+ is required for Linux/WSL; $(setup_node20_install_hint)"
    fi
  else
    command -v node >/dev/null 2>&1 && zenmind_summary_add_ok "node available" || zenmind_summary_add_fail "node missing"
  fi
  command -v docker >/dev/null 2>&1 && zenmind_summary_add_ok "docker available" || zenmind_summary_add_fail "docker missing"
  if docker compose version >/dev/null 2>&1; then
    zenmind_summary_add_ok "docker compose available"
  else
    zenmind_summary_add_fail "docker compose missing"
  fi
}

zenmind_run_edit_config() {
  local editor_path
  zenmind_ensure_profile
  editor_path="${SCRIPT_DIR}/config/editor/index.html"
  zenmind_summary_add_ok "config editor ready: ${editor_path}"
  zenmind_summary_add_ok "local profile path: $(zenmind_profile_path)"
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
}

zenmind_run_start() {
  local services
  mapfile -t services < <(zenmind_expand_products) || return 1
  if zenmind_compose_cmd up -d --build "${services[@]}"; then
    zenmind_summary_add_ok "started selected services"
  else
    zenmind_summary_add_fail "docker compose up failed"
    return 1
  fi
}

zenmind_run_stop() {
  local services
  mapfile -t services < <(zenmind_expand_products) || return 1
  if zenmind_compose_cmd stop "${services[@]}"; then
    zenmind_summary_add_ok "stopped selected services"
  else
    zenmind_summary_add_fail "docker compose stop failed"
    return 1
  fi
}

zenmind_run_status() {
  zenmind_compose_cmd ps || true
  if zenmind_source_compose_env; then
    curl -i -sS "http://${GATEWAY_LISTEN_IP}:${GATEWAY_PORT}/healthz" >/dev/null && zenmind_summary_add_ok "gateway healthz reachable" || zenmind_summary_add_warn "gateway healthz unavailable"
  fi
}

zenmind_write_startup_config() {
  local config_file tmp_file product
  config_file="$(zenmind_startup_config_path)"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/zenmind-startup.XXXXXX")"
  {
    printf '# Generated by zenmind docker-first setup\n'
    printf '# One product per line. Order defines startup sequence.\n'
    for product in "$@"; do
      printf '%s\n' "$product"
    done
  } >"$tmp_file"
  mv "$tmp_file" "$config_file"
  zenmind_summary_add_ok "updated startup list: $config_file"
}

zenmind_run_configure_startup() {
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    zenmind_write_startup_config "${ZENMIND_PRODUCTS[@]}"
    return 0
  fi

  local selected=()
  local answer product
  for product in "${ZENMIND_PRODUCTS[@]}"; do
    read -r -p "[setup-${ZENMIND_OS}] enable ${product}? [Y/n]: " answer
    answer="${answer:-Y}"
    case "$answer" in
      y|Y|yes|YES|Yes) selected+=("$product") ;;
      n|N|no|NO|No) ;;
      *) selected+=("$product") ;;
    esac
  done
  if [[ ${#selected[@]} -eq 0 ]]; then
    zenmind_summary_add_fail "at least one product must be enabled"
    return 1
  fi
  zenmind_write_startup_config "${selected[@]}"
}

zenmind_run_setup_nginx() {
  zenmind_apply_config || return 1
  zenmind_summary_add_ok "gateway nginx generated at ${SCRIPT_DIR}/generated/gateway/nginx.conf"
  zenmind_summary_add_ok "host nginx is no longer required; cloudflared should target the gateway container port directly"
}

zenmind_run_setup_cf_tunnel() {
  zenmind_apply_config || return 1
  zenmind_source_compose_env || return 1
  zenmind_summary_add_ok "use tunnel hostname: ${CLOUDFLARED_HOSTNAME}"
  zenmind_summary_add_ok "use tunnel uuid: ${CLOUDFLARED_TUNNEL_UUID}"
  zenmind_summary_add_ok "gateway origin: http://${GATEWAY_LISTEN_IP}:${GATEWAY_PORT}"
  export CLOUDFLARED_HOSTNAME CLOUDFLARED_TUNNEL_UUID GATEWAY_PORT
  "${SCRIPT_DIR}/scripts/${ZENMIND_OS}/setup-cf-tunnel.sh"
}

zenmind_menu() {
  cat <<'MENU'
1) 环境检测
2) 打开配置页
3) 应用配置
4) 启动
5) 停止
6) 查看状态
7) 配置启动列表
8) 准备 gateway nginx
9) 配置 Cloudflare Tunnel
0) 退出
MENU
}

zenmind_parse_args() {
  ACTION=""
  NON_INTERACTIVE=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action)
        ACTION="$2"
        shift 2
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
}

zenmind_dispatch() {
  case "$ACTION" in
    precheck) zenmind_run_precheck ;;
    edit-config) zenmind_run_edit_config ;;
    apply-config) zenmind_apply_config ;;
    start) zenmind_apply_config && zenmind_run_start ;;
    stop) zenmind_run_stop ;;
    status) zenmind_run_status ;;
    configure-startup) zenmind_run_configure_startup ;;
    setup-nginx) zenmind_run_setup_nginx ;;
    setup-cf-tunnel) zenmind_run_setup_cf_tunnel ;;
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
      1) ACTION="precheck" ;;
      2) ACTION="edit-config" ;;
      3) ACTION="apply-config" ;;
      4) ACTION="start" ;;
      5) ACTION="stop" ;;
      6) ACTION="status" ;;
      7) ACTION="configure-startup" ;;
      8) ACTION="setup-nginx" ;;
      9) ACTION="setup-cf-tunnel" ;;
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
  zenmind_parse_args "$@"
  zenmind_summary_reset
  if [[ -z "${ACTION:-}" ]]; then
    zenmind_interactive_loop
    return 0
  fi
  zenmind_dispatch
  zenmind_print_summary "$ACTION"
}
