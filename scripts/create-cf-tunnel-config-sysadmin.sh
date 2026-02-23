#!/usr/bin/env bash
# create-cf-tunnel-config-sysadmin.sh
# Interactive script for macOS to:
# 1) Ensure cloudflared is available
# 2) Ensure you're logged in (cert.pem)
# 3) Create (or reuse) a Cloudflare Tunnel by name
# 4) Ensure tunnel credentials JSON exists (NO config.yml changes, NO DNS changes)

set -euo pipefail

CONFIG_DIR="$HOME/.cloudflared"
DEFAULT_TUNNEL_NAME="my-tunnel"

die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

prompt() {
  local msg="$1"
  local def="${2:-}"
  local ans=""
  if [[ -n "$def" ]]; then
    read -r -p "$msg [$def]: " ans
    echo "${ans:-$def}"
  else
    read -r -p "$msg: " ans
    echo "$ans"
  fi
}

echo "== Cloudflare Tunnel config generator (macOS) =="
echo "This will CREATE/REUSE a tunnel and generate tunnel credentials JSON."
echo "It will NOT create/modify DNS records, and will NOT change ~/.cloudflared/config.yml."
echo

need_cmd cloudflared
need_cmd awk
need_cmd mkdir

mkdir -p "$CONFIG_DIR"

CERT_PATH="$CONFIG_DIR/cert.pem"
if [[ ! -f "$CERT_PATH" ]]; then
  echo "==> Cloudflare login required (no cert found at $CERT_PATH)"
  echo "==> A browser window will open. Pick the zone when prompted."
  cloudflared tunnel login
  [[ -f "$CERT_PATH" ]] || die "Login did not create $CERT_PATH"
fi

echo
TUNNEL_NAME="$(prompt "Tunnel name" "$DEFAULT_TUNNEL_NAME")"
[[ -n "$TUNNEL_NAME" ]] || die "Tunnel name cannot be empty."
echo "==> Ensuring tunnel exists: $TUNNEL_NAME"

# Try to find existing tunnel by exact name (2nd column in `cloudflared tunnel list`)
TUNNEL_ID="$(cloudflared tunnel list 2>/dev/null | awk -v name="$TUNNEL_NAME" '$2==name {print $1; exit}')"

if [[ -z "${TUNNEL_ID:-}" ]]; then
  echo "==> Tunnel not found. Creating..."
  cloudflared tunnel create "$TUNNEL_NAME" >/dev/null
  TUNNEL_ID="$(cloudflared tunnel list 2>/dev/null | awk -v name="$TUNNEL_NAME" '$2==name {print $1; exit}')"
fi

[[ -n "${TUNNEL_ID:-}" ]] || die "Could not determine tunnel ID. Try: cloudflared tunnel list"

CRED_JSON="$CONFIG_DIR/$TUNNEL_ID.json"
[[ -f "$CRED_JSON" ]] || die "Credentials file missing: $CRED_JSON"

echo
echo "==> Done."
echo "Tunnel name: $TUNNEL_NAME"
echo "Tunnel ID:   $TUNNEL_ID"
echo "Credentials: $CRED_JSON"
echo "config.yml was not modified."
