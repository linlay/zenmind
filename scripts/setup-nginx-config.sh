#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Nginx config bootstrap for cloudflared tunnel origin
# - Writes nginx.conf that ONLY includes sites-enabled/*
# - Writes site that listens on 127.0.0.1:11945 (no need for domain)
# - Backs up existing nginx.conf and site conf if present
# - Tests and reloads/starts nginx using THIS nginx.conf explicitly
#
# Optional env:
#   AUTO_INSTALL=1            # auto-install nginx on macOS (Homebrew only)
#   DOMAIN=app.zenmind.cc      # if you want server_name; default "_"
#   LISTEN_IP=127.0.0.1
#   LISTEN_PORT=11945
#   OS_NAME=darwin|linux       # optional override
#   BREW_PREFIX=/opt/homebrew  # optional (macOS)
#   NGINX_DIR=/path/to/nginx   # optional override
# ============================================================

DOMAIN="${DOMAIN:-_}"               # "_" means catch-all, domain not required
LISTEN_IP="${LISTEN_IP:-127.0.0.1}"
LISTEN_PORT="${LISTEN_PORT:-11945}"

UP_AUTH="${UP_AUTH:-127.0.0.1:11952}"
UP_ADMIN="${UP_ADMIN:-127.0.0.1:11950}"
UP_AGENT="${UP_AGENT:-127.0.0.1:11949}"
UP_TERM="${UP_TERM:-127.0.0.1:11947}"

AUTO_INSTALL="${AUTO_INSTALL:-0}"
OS_NAME="${OS_NAME:-}"

detect_os_name() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux) echo "linux" ;;
    *) echo "unknown" ;;
  esac
}

detect_brew_prefix() {
  if command -v brew >/dev/null 2>&1; then
    brew --prefix
    return 0
  fi
  if [[ -d /opt/homebrew ]]; then echo "/opt/homebrew"; return 0; fi
  if [[ -d /usr/local ]]; then echo "/usr/local"; return 0; fi
  echo ""
}

default_nginx_dir() {
  case "${OS_NAME}" in
    darwin)
      if [[ -n "${BREW_PREFIX}" ]]; then
        echo "${BREW_PREFIX}/etc/nginx"
        return 0
      fi
      if [[ -d /opt/homebrew/etc/nginx ]]; then echo "/opt/homebrew/etc/nginx"; return 0; fi
      if [[ -d /usr/local/etc/nginx ]]; then echo "/usr/local/etc/nginx"; return 0; fi
      echo "/usr/local/etc/nginx"
      ;;
    linux)
      if [[ -d /etc/nginx ]]; then echo "/etc/nginx"; return 0; fi
      if [[ -d /usr/local/etc/nginx ]]; then echo "/usr/local/etc/nginx"; return 0; fi
      echo "/etc/nginx"
      ;;
    *)
      echo ""
      ;;
  esac
}

default_log_dir() {
  case "${OS_NAME}" in
    darwin)
      if [[ -n "${BREW_PREFIX}" ]]; then
        echo "${BREW_PREFIX}/var/log/nginx"
      else
        echo "/usr/local/var/log/nginx"
      fi
      ;;
    linux)
      echo "/var/log/nginx"
      ;;
    *)
      echo ""
      ;;
  esac
}

default_run_dir() {
  case "${OS_NAME}" in
    darwin)
      if [[ -n "${BREW_PREFIX}" ]]; then
        echo "${BREW_PREFIX}/var/run"
      else
        echo "/usr/local/var/run"
      fi
      ;;
    linux)
      echo "/var/run"
      ;;
    *)
      echo ""
      ;;
  esac
}

if [[ -z "${OS_NAME}" ]]; then
  OS_NAME="$(detect_os_name)"
fi

BREW_PREFIX="${BREW_PREFIX:-$(detect_brew_prefix)}"

NGINX_DIR="${NGINX_DIR:-$(default_nginx_dir)}"
if [[ -z "${NGINX_DIR}" ]]; then
  echo "ERROR: Unsupported OS. Please set NGINX_DIR/NGINX_CONF manually." >&2
  exit 1
fi
NGINX_CONF="${NGINX_CONF:-${NGINX_DIR}/nginx.conf}"

SITES_AVAILABLE="${SITES_AVAILABLE:-${NGINX_DIR}/sites-available}"
SITES_ENABLED="${SITES_ENABLED:-${NGINX_DIR}/sites-enabled}"
SITE_NAME="${SITE_NAME:-${LISTEN_PORT}.conf}"
SITE_CONF_PATH="${SITE_CONF_PATH:-${SITES_AVAILABLE}/${SITE_NAME}}"
SITE_LINK_PATH="${SITE_LINK_PATH:-${SITES_ENABLED}/${SITE_NAME}}"

LOG_DIR="${LOG_DIR:-$(default_log_dir)}"
RUN_DIR="${RUN_DIR:-$(default_run_dir)}"

backup_file_if_exists() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local ts bak
    ts="$(date +%Y%m%d-%H%M%S)"
    bak="${f}.bak-${ts}"
    echo "Backing up: $f -> $bak"
    cp -a "$f" "$bak"
  fi
}

ensure_nginx_exists() {
  if command -v nginx >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${AUTO_INSTALL}" == "1" ]]; then
    if [[ "${OS_NAME}" != "darwin" ]]; then
      echo "ERROR: AUTO_INSTALL=1 currently supports macOS Homebrew only." >&2
      echo "Install nginx using your distro package manager, then rerun this script."
      exit 1
    fi
    if ! command -v brew >/dev/null 2>&1; then
      echo "ERROR: nginx missing and brew not found. Install Homebrew or install nginx manually." >&2
      exit 1
    fi
    echo "nginx not found in PATH. Installing via Homebrew because AUTO_INSTALL=1..."
    brew install nginx
  else
    echo "ERROR: nginx command not found in PATH."
    echo "Fix PATH or install nginx. (Set AUTO_INSTALL=1 to auto-install via brew.)"
    exit 1
  fi
}

write_main_nginx_conf() {
  echo "Writing main nginx.conf: ${NGINX_CONF}"
  backup_file_if_exists "${NGINX_CONF}"

  mkdir -p "${NGINX_DIR}" "${LOG_DIR}" "${RUN_DIR}" "${SITES_AVAILABLE}" "${SITES_ENABLED}"

  cat > "${NGINX_CONF}" <<EOF
worker_processes  auto;

error_log  ${LOG_DIR}/error.log warn;
pid        ${RUN_DIR}/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  ${LOG_DIR}/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;

    # WebSocket: Connection header mapping
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }

    # Preserve X-Forwarded-Proto if provided by cloudflared/Cloudflare
    map \$http_x_forwarded_proto \$proxy_x_forwarded_proto {
        default \$http_x_forwarded_proto;
        ''      \$scheme;
    }

    # IMPORTANT: only include our sites-enabled
    include sites-enabled/*;
}
EOF
}

write_site_conf() {
  echo "Writing site conf: ${SITE_CONF_PATH}"
  backup_file_if_exists "${SITE_CONF_PATH}"
  mkdir -p "${SITES_AVAILABLE}" "${SITES_ENABLED}"

  cat > "${SITE_CONF_PATH}" <<EOF
upstream auth_11952  { server ${UP_AUTH}; }
upstream admin_11950 { server ${UP_ADMIN}; }
upstream agent_11949 { server ${UP_AGENT}; }
upstream term_11947  { server ${UP_TERM}; }

server {
    listen ${LISTEN_IP}:${LISTEN_PORT};
    server_name ${DOMAIN};

    proxy_set_header Host              \$host;
    proxy_set_header X-Real-IP         \$remote_addr;
    proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$proxy_x_forwarded_proto;

    proxy_http_version 1.1;
    proxy_set_header Upgrade    \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    location = /healthz {
        add_header Content-Type text/plain;
        return 200 "ok";
    }

    # Auth (11952)
    location ^~ /admin/api { proxy_pass http://auth_11952; }
    location ^~ /api/auth  { proxy_pass http://auth_11952; }
    location ^~ /api/app   { proxy_pass http://auth_11952; }
    location ^~ /oauth2    { proxy_pass http://auth_11952; }
    location ^~ /openid    { proxy_pass http://auth_11952; }

    # Admin (11950) must keep /admin prefix
    location ^~ /admin {
        proxy_set_header X-Forwarded-Host  \$host;
        proxy_set_header X-Forwarded-Proto \$proxy_x_forwarded_proto;
        proxy_pass http://admin_11950;
    }

    # Agent (11949) - unified API prefix, includes /api/ap/data
    location ^~ /api/ap/ {
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        add_header X-Accel-Buffering no;
        proxy_pass http://agent_11949;
    }

    # Term (11947) - long connections / websocket
    location ^~ /appterm {
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        proxy_pass http://term_11947;
    }
    location ^~ /term {
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        proxy_pass http://term_11947;
    }

    location / { return 404; }
}
EOF
}

ensure_symlink() {
  echo "Ensuring symlink: ${SITE_LINK_PATH} -> ../sites-available/${SITE_NAME}"
  mkdir -p "${SITES_ENABLED}"
  rm -f "${SITE_LINK_PATH}"
  ln -s "../sites-available/${SITE_NAME}" "${SITE_LINK_PATH}"
}

test_and_reload_or_start() {
  echo "Testing Nginx with: nginx -t -c ${NGINX_CONF}"
  nginx -t -c "${NGINX_CONF}"

  echo "Reloading Nginx with this config..."
  if nginx -s reload -c "${NGINX_CONF}" 2>/dev/null; then
    echo "Reload OK."
    return 0
  fi

  echo "Reload failed (maybe nginx not running). Starting nginx with this config..."
  if nginx -c "${NGINX_CONF}"; then
    echo "Start OK."
    return 0
  fi

  echo "ERROR: Failed to start nginx."
  echo "If you see 80 port bind errors, something else is listening on :80, or another nginx instance is running."
  echo "Check who uses 80:"
  echo "  sudo lsof -nP -iTCP:80 -sTCP:LISTEN"
  exit 1
}

verify_local() {
  echo "Local check:"
  curl -i "http://${LISTEN_IP}:${LISTEN_PORT}/healthz" || true
}

main() {
  ensure_nginx_exists
  write_main_nginx_conf
  write_site_conf
  ensure_symlink
  test_and_reload_or_start
  verify_local

  cat <<EOF

Done.

Notes:
- This nginx listens ONLY on ${LISTEN_IP}:${LISTEN_PORT}. No 80/443 listeners are created by this script.
- server_name is set to: ${DOMAIN}
  (Use DOMAIN=app.zenmind.cc if you want strict host matching; "_" is fine for tunnel origin.)
- Start nginx:   ./scripts/start-nginx.sh
- Stop nginx:    ./scripts/stop-nginx.sh
- Restart nginx: ./scripts/restart-nginx.sh
EOF
}

main "$@"
