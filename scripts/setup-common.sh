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

setup_bcrypt_hint() {
  setup_log "macOS bcrypt command: htpasswd -nbBC 10 '' 'your-password' | cut -d: -f2"
}

setup_generate_bcrypt() {
  local plain_password="$1"

  if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -nbBC 10 '' "$plain_password" | cut -d: -f2
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import bcrypt" >/dev/null 2>&1; then
      python3 -c 'import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(10)).decode())' "$plain_password"
      return 0
    fi
  fi

  setup_err "unable to generate bcrypt hash (need htpasswd, or python3 with bcrypt module)"
  return 1
}

setup_prompt_password() {
  local prompt="$1"
  local default_password="$2"
  local input=""

  if [[ -t 0 ]]; then
    read -r -s -p "[setup-mac] $prompt [default: $default_password]: " input
    echo
  else
    setup_warn "stdin is not interactive, use default password for '$prompt'"
  fi

  if [[ -z "$input" ]]; then
    input="$default_password"
  fi

  printf '%s' "$input"
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
  awk -v k="$key" -v v="$value" '
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
  ' "$env_file" >"$tmp"
  mv "$tmp" "$env_file"
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
