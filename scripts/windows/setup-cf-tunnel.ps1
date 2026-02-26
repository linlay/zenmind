Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Prompt-Value {
  param([string]$Message, [string]$Default = '')
  if ([string]::IsNullOrWhiteSpace($Default)) {
    return (Read-Host -Prompt $Message)
  }
  $value = Read-Host -Prompt "$Message (默认: $Default)"
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value
}

Write-Host '== Cloudflare Tunnel config generator (UUID-only) =='

$tunnelUuid = Prompt-Value -Message '请输入 Tunnel UUID'
$hostname = Prompt-Value -Message '请输入域名（hostname），例如 app.zenmind.cc'
$localPort = Prompt-Value -Message '请输入本地转发端口' -Default '11945'

if ([string]::IsNullOrWhiteSpace($tunnelUuid)) { throw 'Tunnel UUID is required' }
if ([string]::IsNullOrWhiteSpace($hostname)) { throw 'Hostname is required' }

$cloudflaredDir = Join-Path $HOME '.cloudflared'
$configFile = Join-Path $cloudflaredDir 'config.yml'
$credFile = Join-Path $cloudflaredDir "$tunnelUuid.json"

New-Item -ItemType Directory -Path $cloudflaredDir -Force | Out-Null

$configContent = @"
tunnel: $tunnelUuid
credentials-file: $credFile

ingress:
  - hostname: $hostname
    service: http://127.0.0.1:$localPort
  - service: http_status:404
"@
Set-Content -LiteralPath $configFile -Value $configContent -Encoding UTF8

Write-Host ''
Write-Host "已写入配置: $configFile"
Write-Host "凭据文件应存在: $credFile"
Write-Host ''

if (-not (Get-Command -Name cloudflared -ErrorAction SilentlyContinue)) {
  Write-Host '未检测到 cloudflared。可使用 winget 安装：'
  Write-Host '  winget install --id Cloudflare.cloudflared -e'
  exit 1
}

if (-not (Test-Path -LiteralPath $credFile)) {
  Write-Host "警告：未找到 $credFile"
  Write-Host '需要先在本机通过 Cloudflare 登录/创建 tunnel 生成该凭据文件。'
  Write-Host ''
}

$startNow = Read-Host -Prompt '是否现在启动？(y/N)'
if ($startNow -match '^[Yy]$') {
  Write-Host '启动：.\scripts\windows\start-cf-tunnel.ps1 -Foreground'
  & (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'start-cf-tunnel.ps1') -Foreground
} else {
  Write-Host '手动启动（后台）：.\scripts\windows\start-cf-tunnel.ps1'
  Write-Host '停止命令：.\scripts\windows\stop-cf-tunnel.ps1'
}
