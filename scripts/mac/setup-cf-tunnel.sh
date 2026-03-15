#!/usr/bin/env bash
set -euo pipefail

CLOUDFLARED_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"
CERT_FILE="$CLOUDFLARED_DIR/cert.pem"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "未检测到命令: $1"
}

prompt() {
  local varname="$1"
  local text="$2"
  local default="${3:-}"
  local input=""
  if [[ -n "$default" ]]; then
    read -r -p "$text (默认: $default): " input
    input="${input:-$default}"
  else
    read -r -p "$text: " input
  fi
  printf -v "$varname" "%s" "$input"
}

echo "== Cloudflare Tunnel setup =="
echo "这会自动执行：远程 route dns、本地生成 config.yml"
echo

need_cmd cloudflared
need_cmd mkdir

prompt TUNNEL_UUID "请输入 Tunnel UUID" "${TUNNEL_UUID:-${CLOUDFLARED_TUNNEL_UUID:-}}"
prompt HOSTNAME "请输入域名（hostname），例如 app.zenmind.cc" "${HOSTNAME:-${CLOUDFLARED_HOSTNAME:-}}"
prompt LOCAL_PORT "请输入本地转发端口" "${LOCAL_PORT:-${GATEWAY_PORT:-11945}}"

[[ -n "$TUNNEL_UUID" ]] || die "Tunnel UUID 不能为空"
[[ -n "$HOSTNAME" ]] || die "hostname 不能为空"

mkdir -p "$CLOUDFLARED_DIR"

if [[ ! -f "$CERT_FILE" ]]; then
  echo
  echo "==> 未检测到 Cloudflare 登录凭据，开始登录..."
  echo "==> 浏览器会打开，请选择对应 zone 完成授权。"
  cloudflared tunnel login
  [[ -f "$CERT_FILE" ]] || die "登录后仍未生成证书: $CERT_FILE"
fi

CRED_FILE="$CLOUDFLARED_DIR/${TUNNEL_UUID}.json"
[[ -f "$CRED_FILE" ]] || die "未找到 tunnel 凭据文件: $CRED_FILE。请先创建 tunnel，或运行 ./scripts/mac/create-cf-tunnel-config-sysadmin.sh"

echo
echo "==> 绑定 DNS: $HOSTNAME -> $TUNNEL_UUID"
cloudflared tunnel route dns --overwrite-dns "$TUNNEL_UUID" "$HOSTNAME"

cat > "$CONFIG_FILE" <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: ${CRED_FILE}

ingress:
  - hostname: ${HOSTNAME}
    service: http://127.0.0.1:${LOCAL_PORT}
  - service: http_status:404
EOF

echo
echo "已完成 Cloudflare Tunnel 配置。"
echo "Tunnel UUID: $TUNNEL_UUID"
echo "DNS hostname: $HOSTNAME"
echo "本地端口: $LOCAL_PORT"
echo "配置文件: $CONFIG_FILE"
echo "凭据文件: $CRED_FILE"
echo

read -r -p "是否现在启动？(y/N): " START_NOW
START_NOW="${START_NOW:-N}"

if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
  echo "启动：./scripts/mac/start-cf-tunnel.sh --foreground"
  exec "$(cd "$(dirname "$0")" && pwd)/start-cf-tunnel.sh" --foreground
else
  echo "手动启动（后台）：./scripts/mac/start-cf-tunnel.sh"
  echo "停止命令：./scripts/mac/stop-cf-tunnel.sh"
fi
