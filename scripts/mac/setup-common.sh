#!/usr/bin/env bash

setup_log() {
  printf '[setup-mac] %s\n' "$*"
}

setup_warn() {
  printf '[setup-mac] WARN: %s\n' "$*" >&2
}

setup_err() {
  printf '[setup-mac] ERROR: %s\n' "$*" >&2
}

setup_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    setup_err "missing required command: $cmd"
    return 1
  fi
  return 0
}

setup_semver_ge() {
  local actual="$1"
  local required="$2"
  [[ "$(printf '%s\n%s\n' "$required" "$actual" | sort -V | tail -n 1)" == "$actual" ]]
}

setup_check_node20() {
  if ! command -v node >/dev/null 2>&1; then
    setup_err "Node.js not found (required: 20+)"
    return 1
  fi

  local version
  version="$(node -v | sed 's/^v//')"
  if ! setup_semver_ge "$version" "20.0.0"; then
    setup_err "Node.js version too low: $version (required: 20+)"
    return 1
  fi

  setup_log "Node.js OK: v$version"
  return 0
}

setup_check_npm() {
  if ! command -v npm >/dev/null 2>&1; then
    setup_err "npm not found"
    return 1
  fi
  setup_log "npm OK: $(npm -v)"
  return 0
}

setup_check_maven39() {
  if ! command -v mvn >/dev/null 2>&1; then
    setup_err "Maven not found (required: 3.9+)"
    return 1
  fi

  local version
  version="$(mvn -v | awk '/Apache Maven/ {print $3; exit}')"
  if [[ -z "$version" ]]; then
    setup_err "unable to parse Maven version"
    return 1
  fi

  if ! setup_semver_ge "$version" "3.9.0"; then
    setup_err "Maven version too low: $version (required: 3.9+)"
    return 1
  fi

  setup_log "Maven OK: $version"
  return 0
}

setup_check_java21() {
  if ! command -v java >/dev/null 2>&1; then
    setup_err "Java not found (required: JDK 21+)"
    return 1
  fi

  local raw version major
  raw="$(java -version 2>&1 | head -n 1)"
  version="$(printf '%s' "$raw" | sed -E 's/.*"([0-9]+(\.[0-9]+){0,2}).*/\1/')"
  major="${version%%.*}"
  if [[ -z "$major" ]] || ! [[ "$major" =~ ^[0-9]+$ ]]; then
    setup_err "unable to parse Java version from: $raw"
    return 1
  fi

  if (( major < 21 )); then
    setup_err "Java version too low: $version (required: 21+)"
    return 1
  fi

  setup_log "Java OK: $version"
  return 0
}

setup_check_docker_compose_for_app_server() {
  if ! command -v docker >/dev/null 2>&1; then
    setup_err "Docker not found (required by zenmind-app-server container setup)"
    return 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    setup_err "docker compose plugin not available (required by zenmind-app-server)"
    return 1
  fi

  setup_log "Docker Compose OK: $(docker compose version | head -n 1)"

  if ! setup_docker_daemon_running; then
    setup_warn "docker command exists but daemon is not running (start Docker Desktop before running app-server)"
  fi

  return 0
}

setup_docker_daemon_running() {
  docker info >/dev/null 2>&1
}

setup_check_optional_tools() {
  if command -v htpasswd >/dev/null 2>&1; then
    setup_log "Optional tool OK: htpasswd"
  else
    setup_warn "optional tool missing: htpasswd (macOS install hint: brew install httpd)"
  fi

  if command -v openssl >/dev/null 2>&1; then
    setup_log "Optional tool OK: openssl"
  else
    setup_warn "optional tool missing: openssl"
  fi

  if command -v python3 >/dev/null 2>&1; then
    setup_log "Optional tool OK: python3"
  else
    setup_warn "optional tool missing: python3 (used in term-webclient README password hash example)"
  fi
}

setup_normalize_bcrypt_hash() {
  local hash="$1"
  hash="${hash//$'\r'/}"
  hash="${hash//$'\n'/}"
  if [[ "$hash" == \$2b\$* ]]; then
    printf '%s\n' "\$2y\$${hash#\$2b\$}"
    return 0
  fi
  printf '%s\n' "$hash"
}

setup_generate_bcrypt() {
  local plain_password="$1"
  local hash_line
  local normalized_hash
  local show_plain_password="${SETUP_SHOW_PLAIN_PASSWORD:-0}"

  if command -v htpasswd >/dev/null 2>&1; then
    if [[ "$show_plain_password" == "1" ]]; then
      setup_log "[bcrypt] method: htpasswd" >&2
      setup_log "[bcrypt] command: htpasswd -nbBC 10 '' $(setup_single_quote_env_value "$plain_password")" >&2
    fi
    local raw_output
    raw_output="$(htpasswd -nbBC 10 '' "$plain_password" 2>/dev/null)"
    if [[ "$show_plain_password" == "1" ]]; then
      setup_log "[bcrypt] raw output: $raw_output" >&2
    fi
    hash_line="$(printf '%s\n' "$raw_output" | awk -F: '$1=="" && $2!="" {print $2; exit}')"
    if [[ "$show_plain_password" == "1" ]]; then
      setup_log "[bcrypt] after awk:  $hash_line" >&2
    fi
    if [[ -n "$hash_line" ]]; then
      normalized_hash="$(setup_normalize_bcrypt_hash "$hash_line")"
      if [[ "$show_plain_password" == "1" ]]; then
        setup_log "[bcrypt] normalized: $normalized_hash" >&2
      fi
      if [[ -n "$normalized_hash" ]]; then
        if [[ "$normalized_hash" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]]; then
          printf '%s\n' "$normalized_hash"
          return 0
        fi
        setup_err "generated bcrypt hash has invalid format"
        return 1
      fi
    fi
  fi

  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import bcrypt" >/dev/null 2>&1; then
      if [[ "$show_plain_password" == "1" ]]; then
        setup_log "[bcrypt] method: python3 bcrypt" >&2
      fi
      normalized_hash="$(python3 -c 'import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(10)).decode())' "$plain_password" | tr -d '\r\n')"
      if [[ "$show_plain_password" == "1" ]]; then
        setup_log "[bcrypt] python raw: $normalized_hash" >&2
      fi
      if [[ -n "$normalized_hash" ]]; then
        normalized_hash="$(setup_normalize_bcrypt_hash "$normalized_hash")"
        if [[ "$show_plain_password" == "1" ]]; then
          setup_log "[bcrypt] normalized: $normalized_hash" >&2
        fi
        if [[ -n "$normalized_hash" ]]; then
          if [[ "$normalized_hash" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]]; then
            printf '%s\n' "$normalized_hash"
            return 0
          fi
          setup_err "generated bcrypt hash has invalid format"
          return 1
        fi
      fi
    fi
  fi

  setup_err "unable to generate bcrypt hash (need htpasswd, or python3 with bcrypt module)"
  return 1
}

setup_prompt_password() {
  local prompt="$1"
  local default_password="$2"
  local input=""
  local input_source="manual"
  local show_plain_password="${SETUP_SHOW_PLAIN_PASSWORD:-0}"

  if [[ "${SETUP_NON_INTERACTIVE:-0}" == "1" ]]; then
    setup_warn "non-interactive mode, use default password for '$prompt'"
    input_source="default(non-interactive)"
  elif [[ -t 0 ]]; then
    if [[ "$show_plain_password" == "1" ]]; then
      read -r -p "[setup-mac] $prompt [default: $default_password]: " input
    else
      read -r -s -p "[setup-mac] $prompt [default: $default_password]: " input
    fi
    # CRITICAL: this function is called via command substitution, e.g.
    #   term_plain="$(setup_prompt_password ...)"
    # so stdout must contain ONLY the final password value.
    # Any extra stdout (even this visual newline after read) gets captured
    # into the password string and changes the hashed value (historical bug:
    # hash was generated from "\npwd" instead of "pwd", making login fail).
    # Keep prompt formatting on stderr to avoid contaminating stdout.
    echo >&2
  else
    setup_warn "stdin is not interactive, use default password for '$prompt'"
    input_source="default(non-interactive-stdin)"
  fi

  if [[ -z "$input" ]]; then
    input="$default_password"
    if [[ "$input_source" == "manual" ]]; then
      input_source="default"
    fi
  fi
  # CRITICAL: strip CR/LF defensively before returning via stdout.
  # This prevents accidental newline persistence from TTY/paste behavior.
  input="${input//$'\r'/}"
  input="${input//$'\n'/}"

  if [[ "$show_plain_password" == "1" ]]; then
    setup_log "[bcrypt] input source: $input_source, plaintext: $(setup_single_quote_env_value "$input")" >&2
  fi

  printf '%s' "$input"
}

setup_show_first_install_password_notice() {
  if [[ "${SETUP_NON_INTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    setup_log "non-interactive mode: skip enter-to-continue password notice"
    return 0
  fi

  cat <<'NOTICE'
[setup-mac] 首次安装将要求输入 3 组密码（后续会自动加密写入配置）:
[setup-mac] 1) term-webclient: AUTH_PASSWORD_HASH_BCRYPT 对应明文密码
[setup-mac] 2) zenmind-app-server: AUTH_ADMIN_PASSWORD_BCRYPT 对应明文密码
[setup-mac] 3) zenmind-app-server: AUTH_APP_MASTER_PASSWORD_BCRYPT 对应明文密码
[setup-mac] First install will prompt for 3 passwords (hashed and written to config):
[setup-mac] 1) term-webclient: plaintext password for AUTH_PASSWORD_HASH_BCRYPT
[setup-mac] 2) zenmind-app-server: plaintext password for AUTH_ADMIN_PASSWORD_BCRYPT
[setup-mac] 3) zenmind-app-server: plaintext password for AUTH_APP_MASTER_PASSWORD_BCRYPT
[setup-mac] 按回车继续 / Press Enter to continue...
NOTICE
  read -r _
}

setup_ensure_env_file() {
  local env_file="$1"
  local env_dir
  env_dir="$(dirname "$env_file")"
  mkdir -p "$env_dir"
  if [[ ! -f "$env_file" ]]; then
    : >"$env_file"
  fi
}

setup_upsert_env_var() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local tmp

  tmp="$(mktemp "${TMPDIR:-/tmp}/setup-env.XXXXXX")"
  if ! awk -v k="$key" -v v="$value" '
    BEGIN { replaced = 0 }
    $0 ~ ("^" k "=") {
      if (!replaced) {
        print k "=" v
        replaced = 1
      }
      next
    }
    { print }
    END {
      if (!replaced) {
        print k "=" v
      }
    }
  ' "$env_file" >"$tmp"; then
    rm -f "$tmp"
    setup_err "failed to update env var '$key' in $env_file"
    return 1
  fi

  if ! mv "$tmp" "$env_file"; then
    rm -f "$tmp"
    setup_err "failed to write env file: $env_file"
    return 1
  fi
}

setup_single_quote_env_value() {
  local value="$1"
  # Keep literal content safe for shell-style .env loading.
  value="${value//\'/\'\"\'\"\'}"
  printf "'%s'" "$value"
}

setup_process_running_from_pid_file() {
  local pid_file="$1"
  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    return 1
  fi

  kill -0 "$pid" >/dev/null 2>&1
}

setup_timestamp() {
  date '+%Y%m%d%H%M%S'
}

setup_backup_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    setup_err "cannot backup missing file: $file_path"
    return 1
  fi

  local backup_path="${file_path}.bak.$(setup_timestamp)"
  cp "$file_path" "$backup_path"
  printf '%s\n' "$backup_path"
}

setup_stop_process_by_pid_file() {
  local pid_file="$1"

  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    return 1
  fi

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    rm -f "$pid_file"
    return 1
  fi

  kill "$pid" >/dev/null 2>&1 || true
  for _ in {1..10}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      rm -f "$pid_file"
      return 0
    fi
    sleep 1
  done

  kill -9 "$pid" >/dev/null 2>&1 || true
  rm -f "$pid_file"
  return 0
}
