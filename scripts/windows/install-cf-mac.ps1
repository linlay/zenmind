Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'install-cf-windows.ps1'
Write-Warning 'install-cf-mac.ps1 on Windows forwards to install-cf-windows.ps1.'
& $scriptPath @args
