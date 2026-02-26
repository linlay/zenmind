param([switch]$Reload)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'nginx-common.ps1')

Resolve-NginxPaths
Require-NginxBinary

Write-Host "OS: $script:OS_NAME"
Write-Host "NGINX_CONF: $script:NGINX_CONF"
Write-Host "PID_FILE: $script:PID_FILE"

& nginx -t -c $script:NGINX_CONF
if ($LASTEXITCODE -ne 0) {
  throw 'nginx config test failed'
}

$isRunning = $false
if (Test-Path -LiteralPath $script:PID_FILE) {
  $pidRaw = (Get-Content -LiteralPath $script:PID_FILE -ErrorAction SilentlyContinue | Select-Object -First 1)
  $pidValue = 0
  if ([int]::TryParse($pidRaw, [ref]$pidValue)) {
    $isRunning = [bool](Get-Process -Id $pidValue -ErrorAction SilentlyContinue)
    if ($isRunning) {
      Write-Host "nginx already running (PID: $pidValue)."
      if ($Reload.IsPresent) {
        & nginx -s reload -c $script:NGINX_CONF
        if ($LASTEXITCODE -eq 0) {
          Write-Host 'nginx reloaded.'
        } else {
          throw 'nginx reload failed'
        }
      }
      exit 0
    }
  }
}

& nginx -c $script:NGINX_CONF
if ($LASTEXITCODE -ne 0) {
  throw 'nginx start failed'
}
Write-Host 'nginx started.'
