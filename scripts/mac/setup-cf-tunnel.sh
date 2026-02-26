#!/usr/bin/env bash
set -euo pipefail

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

echo "== Cloudflare Tunnel config generator (UUID-only) =="

prompt TUNNEL_UUID "请输入 Tunnel UUID"
prompt HOSTNAME "请输入域名（hostname），例如 app.zenmind.cc"
prompt LOCAL_PORT "请输入本地转发端口" "11945"

CLOUDFLARED_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"
CRED_FILE="$CLOUDFLARED_DIR/${TUNNEL_UUID}.json"

mkdir -p "$CLOUDFLARED_DIR"

cat > "$CONFIG_FILE" <<EOF
tunnel: ${TUNNEL_UUID}
credentials-file: ${CRED_FILE}

ingress:
  - hostname: ${HOSTNAME}
    service: http://127.0.0.1:${LOCAL_PORT}
  - service: http_status:404
EOF

echo
echo "已写入配置: $CONFIG_FILE"
echo "凭据文件应存在: $CRED_FILE"
echo

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "未检测到 cloudflared。可用 Homebrew 安装："
  echo "  brew install cloudflare/cloudflare/cloudflared"
  exit 1
fi

if [[ ! -f "$CRED_FILE" ]]; then
  echo "警告：未找到 $CRED_FILE"
  echo "需要先在本机通过 Cloudflare 登录/创建 tunnel 生成该凭据文件。"
  echo
fi

read -r -p "是否现在启动？(y/N): " START_NOW
START_NOW="${START_NOW:-N}"

if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
  echo "启动：./scripts/mac/start-cf-tunnel.sh --foreground"
  exec "$(cd "$(dirname "$0")" && pwd)/start-cf-tunnel.sh" --foreground
else
  echo "手动启动（后台）：./scripts/mac/start-cf-tunnel.sh"
  echo "停止命令：./scripts/mac/stop-cf-tunnel.sh"
fi
