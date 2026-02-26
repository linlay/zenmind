Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command -Name winget -ErrorAction SilentlyContinue)) {
  Write-Error 'winget not found. Install App Installer from Microsoft Store first.'
  exit 1
}

Write-Host '==> Installing/Upgrading cloudflared via winget...'
& winget install --id Cloudflare.cloudflared -e --accept-source-agreements --accept-package-agreements
if ($LASTEXITCODE -ne 0) {
  Write-Host 'install may have failed or package already exists, trying upgrade...'
  & winget upgrade --id Cloudflare.cloudflared -e --accept-source-agreements --accept-package-agreements
}

if (-not (Get-Command -Name cloudflared -ErrorAction SilentlyContinue)) {
  Write-Error 'cloudflared command not found after install. Re-open terminal and retry.'
  exit 1
}

Write-Host '==> cloudflared version:'
& cloudflared --version

$configDir = Join-Path $HOME '.cloudflared'
Write-Host ''
Write-Host '==> Creating config directory...'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

Write-Host ''
Write-Host 'Done.'
Write-Host 'Next:'
Write-Host '  1) Run: cloudflared tunnel login'
Write-Host "     Browser auth will write cert file to $configDir"
Write-Host '  2) Then run create script to create/reuse tunnel'
