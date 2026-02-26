Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

try {
  & (Join-Path $ScriptDir 'stop-nginx.ps1')
} catch {
  Write-Warning "stop-nginx.ps1 failed: $($_.Exception.Message)"
}

& (Join-Path $ScriptDir 'start-nginx.ps1')
