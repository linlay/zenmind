Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'nginx-common.ps1')

Resolve-NginxPaths
Require-NginxBinary

Write-Host "OS: $script:OS_NAME"
Write-Host "NGINX_CONF: $script:NGINX_CONF"
Write-Host "PID_FILE: $script:PID_FILE"

$pidValue = $null
if (Test-Path -LiteralPath $script:PID_FILE) {
  $pidRaw = (Get-Content -LiteralPath $script:PID_FILE -ErrorAction SilentlyContinue | Select-Object -First 1)
  $temp = 0
  if ([int]::TryParse($pidRaw, [ref]$temp)) {
    $pidValue = $temp
  }
}

if ($null -ne $pidValue -and -not (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) {
  Write-Host "stale PID file detected, cleaning: $script:PID_FILE"
  Remove-Item -LiteralPath $script:PID_FILE -Force -ErrorAction SilentlyContinue
  $pidValue = $null
}

& nginx -s quit -c $script:NGINX_CONF 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host 'sent graceful quit signal.'
} else {
  if ($null -eq $pidValue) {
    Write-Host 'nginx is not running.'
    exit 0
  }
  Write-Host "graceful quit failed, sending TERM to PID $pidValue."
  Stop-Process -Id $pidValue -ErrorAction SilentlyContinue
}

for ($i = 0; $i -lt 10; $i++) {
  if ($null -eq $pidValue) { break }
  if (-not (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Seconds 1
}

if ($null -ne $pidValue -and (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) {
  Write-Host "process still alive, sending KILL to PID $pidValue."
  Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $script:PID_FILE -Force -ErrorAction SilentlyContinue
Write-Host 'nginx stopped.'
