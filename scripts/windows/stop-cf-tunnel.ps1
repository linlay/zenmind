Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cloudflaredDir = Join-Path $HOME '.cloudflared'
$pidFile = Join-Path $cloudflaredDir 'cloudflared.pid'

if (-not (Test-Path -LiteralPath $pidFile)) {
  Write-Host "未找到 PID 文件: $pidFile"
  Write-Host '如果是前台运行，请直接在对应终端按 Ctrl+C 停止。'
  exit 1
}

$pidRaw = (Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
$pidValue = 0
if (-not [int]::TryParse($pidRaw, [ref]$pidValue)) {
  Write-Host 'PID 文件为空或格式非法，无法停止。'
  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  exit 1
}

$proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
if ($null -eq $proc) {
  Write-Host "进程不存在 (PID: $pidValue)，已清理 PID 文件。"
  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  exit 0
}

Stop-Process -Id $pidValue -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 10; $i++) {
  Start-Sleep -Seconds 1
  if (-not (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) {
    break
  }
}

if (Get-Process -Id $pidValue -ErrorAction SilentlyContinue) {
  Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Write-Host "已停止 cloudflared (PID: $pidValue)"
