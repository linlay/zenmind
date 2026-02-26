param([switch]$Foreground)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cloudflaredDir = Join-Path $HOME '.cloudflared'
$configFile = Join-Path $cloudflaredDir 'config.yml'
$pidFile = Join-Path $cloudflaredDir 'cloudflared.pid'
$logFile = Join-Path $env:TEMP 'cloudflared-tunnel.log'
$errLogFile = Join-Path $env:TEMP 'cloudflared-tunnel.err.log'

if (-not (Get-Command -Name cloudflared -ErrorAction SilentlyContinue)) {
  Write-Host '未检测到 cloudflared。可用 winget 安装：'
  Write-Host '  winget install --id Cloudflare.cloudflared -e'
  exit 1
}

if (-not (Test-Path -LiteralPath $configFile)) {
  Write-Host "未找到配置文件: $configFile"
  Write-Host '请先运行 setup-cf-tunnel.ps1 生成配置。'
  exit 1
}

if ($Foreground.IsPresent) {
  Write-Host "前台启动：cloudflared tunnel --config \"$configFile\" run"
  & cloudflared tunnel --config $configFile run
  exit $LASTEXITCODE
}

if (Test-Path -LiteralPath $pidFile) {
  $oldPidRaw = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  $oldPid = 0
  if ([int]::TryParse($oldPidRaw, [ref]$oldPid)) {
    if (Get-Process -Id $oldPid -ErrorAction SilentlyContinue) {
      Write-Host "cloudflared 已在运行 (PID: $oldPid)"
      exit 0
    }
  }
}

New-Item -ItemType Directory -Path $cloudflaredDir -Force | Out-Null
$proc = Start-Process -FilePath 'cloudflared' -ArgumentList @('tunnel', '--config', $configFile, 'run') -RedirectStandardOutput $logFile -RedirectStandardError $errLogFile -PassThru
$proc.Id | Set-Content -LiteralPath $pidFile -Encoding ASCII

Write-Host "已后台启动 cloudflared (PID: $($proc.Id))"
Write-Host "日志文件: $logFile"
Write-Host "错误日志: $errLogFile"
Write-Host '停止命令: .\scripts\windows\stop-cf-tunnel.ps1'
