Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$configDir = Join-Path $HOME '.cloudflared'
$defaultTunnelName = 'my-tunnel'

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
    throw "Missing command: $Name"
  }
}

function Prompt-Value {
  param([string]$Message, [string]$Default = '')
  if ([string]::IsNullOrWhiteSpace($Default)) {
    return (Read-Host -Prompt $Message)
  }
  $value = Read-Host -Prompt "$Message [$Default]"
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value
}

Write-Host '== Cloudflare Tunnel config generator (Windows) =='
Write-Host 'This will CREATE/REUSE a tunnel and generate tunnel credentials JSON.'
Write-Host 'It will NOT create/modify DNS records, and will NOT change ~/.cloudflared/config.yml.'
Write-Host ''

Require-Command -Name cloudflared
New-Item -ItemType Directory -Path $configDir -Force | Out-Null

$certPath = Join-Path $configDir 'cert.pem'
if (-not (Test-Path -LiteralPath $certPath)) {
  Write-Host "==> Cloudflare login required (no cert found at $certPath)"
  Write-Host '==> A browser window may open. Pick the zone when prompted.'
  & cloudflared tunnel login
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $certPath)) {
    throw "Login did not create $certPath"
  }
}

Write-Host ''
$tunnelName = Prompt-Value -Message 'Tunnel name' -Default $defaultTunnelName
if ([string]::IsNullOrWhiteSpace($tunnelName)) {
  throw 'Tunnel name cannot be empty.'
}

Write-Host "==> Ensuring tunnel exists: $tunnelName"
$listOutput = & cloudflared tunnel list 2>$null
$tunnelId = $null
foreach ($line in $listOutput) {
  $trimmed = $line.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
  if ($trimmed.StartsWith('ID')) { continue }
  $parts = $trimmed -split '\s+'
  if ($parts.Length -ge 2 -and $parts[1] -eq $tunnelName) {
    $tunnelId = $parts[0]
    break
  }
}

if ([string]::IsNullOrWhiteSpace($tunnelId)) {
  Write-Host '==> Tunnel not found. Creating...'
  & cloudflared tunnel create $tunnelName *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'cloudflared tunnel create failed'
  }

  $listOutput = & cloudflared tunnel list 2>$null
  foreach ($line in $listOutput) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith('ID')) { continue }
    $parts = $trimmed -split '\s+'
    if ($parts.Length -ge 2 -and $parts[1] -eq $tunnelName) {
      $tunnelId = $parts[0]
      break
    }
  }
}

if ([string]::IsNullOrWhiteSpace($tunnelId)) {
  throw 'Could not determine tunnel ID. Try: cloudflared tunnel list'
}

$credJson = Join-Path $configDir "$tunnelId.json"
if (-not (Test-Path -LiteralPath $credJson)) {
  throw "Credentials file missing: $credJson"
}

Write-Host ''
Write-Host '==> Done.'
Write-Host "Tunnel name: $tunnelName"
Write-Host "Tunnel ID:   $tunnelId"
Write-Host "Credentials: $credJson"
Write-Host 'config.yml was not modified.'
