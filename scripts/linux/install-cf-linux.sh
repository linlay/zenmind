#!/usr/bin/env bash
set -euo pipefail

run_privileged() {
  if [[ "${EUID}" == "0" ]]; then
    "$@"
    return
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: this script requires root privileges or sudo." >&2
    exit 1
  fi

  sudo "$@"
}

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: apt-get not found. This script currently supports Ubuntu/Debian-based Linux and WSL." >&2
  echo "Please install cloudflared manually for your distro, then rerun the tunnel setup scripts."
  exit 1
fi

echo "==> Installing/Updating cloudflared via apt..."
run_privileged apt-get update
run_privileged apt-get install -y curl gpg ca-certificates
run_privileged install -m 0755 -d /usr/share/keyrings

TMP_GPG="$(mktemp)"
trap 'rm -f "$TMP_GPG"' EXIT
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o "$TMP_GPG"
run_privileged gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-main.gpg "$TMP_GPG"
printf '%s\n' 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | run_privileged tee /etc/apt/sources.list.d/cloudflared.list >/dev/null
run_privileged apt-get update
run_privileged apt-get install -y cloudflared

echo "==> cloudflared version:"
cloudflared --version

echo
echo "==> Creating config directories..."
mkdir -p "$HOME/.cloudflared"

echo
echo "Done."
echo "Next:"
echo "  1) 如 tunnel 尚未创建，先运行: ./scripts/linux/create-cf-tunnel-config-sysadmin.sh"
echo "  2) 再运行: ./scripts/linux/setup-cf-tunnel.sh"
echo "     会执行 route dns，并生成 ~/.cloudflared/config.yml"
