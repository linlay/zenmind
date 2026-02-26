param(
  [string]$Domain = $(if ($env:DOMAIN) { $env:DOMAIN } else { '_' }),
  [string]$ListenIp = $(if ($env:LISTEN_IP) { $env:LISTEN_IP } else { '127.0.0.1' }),
  [string]$ListenPort = $(if ($env:LISTEN_PORT) { $env:LISTEN_PORT } else { '11945' }),
  [string]$UpAuth = $(if ($env:UP_AUTH) { $env:UP_AUTH } else { '127.0.0.1:11952' }),
  [string]$UpAdmin = $(if ($env:UP_ADMIN) { $env:UP_ADMIN } else { '127.0.0.1:11950' }),
  [string]$UpAgent = $(if ($env:UP_AGENT) { $env:UP_AGENT } else { '127.0.0.1:11949' }),
  [string]$UpTerm = $(if ($env:UP_TERM) { $env:UP_TERM } else { '127.0.0.1:11947' }),
  [switch]$AutoInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'nginx-common.ps1')

function Backup-FileIfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    $bak = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Backing up: $Path -> $bak"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
  }
}

function Ensure-NginxExists {
  if (Get-Command -Name nginx -ErrorAction SilentlyContinue) {
    return
  }

  if (-not $AutoInstall.IsPresent) {
    throw 'nginx command not found in PATH. Install nginx first (or pass -AutoInstall).'
  }

  if (-not $IsWindows) {
    throw 'AutoInstall currently supports Windows only in this script.'
  }

  if (-not (Get-Command -Name winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install nginx manually and rerun.'
  }

  Write-Host 'nginx not found. Installing with winget...'
  & winget install --id Nginx.Nginx -e
  if ($LASTEXITCODE -ne 0) {
    throw 'winget install Nginx.Nginx failed.'
  }
}

function Ensure-SymlinkOrCopy {
  param(
    [string]$Source,
    [string]$LinkPath
  )

  if (Test-Path -LiteralPath $LinkPath) {
    Remove-Item -LiteralPath $LinkPath -Force -Recurse -ErrorAction SilentlyContinue
  }

  try {
    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $Source -Force | Out-Null
    Write-Host "Created symlink: $LinkPath -> $Source"
  } catch {
    Copy-Item -LiteralPath $Source -Destination $LinkPath -Force
    Write-Host "Symlink unavailable, copied file instead: $LinkPath"
  }
}

Ensure-NginxExists
Resolve-NginxPaths
Require-NginxBinary

$nginxDir = $script:NGINX_DIR
$nginxConf = $script:NGINX_CONF
$runDir = $script:RUN_DIR

$sitesAvailable = if ($env:SITES_AVAILABLE) { $env:SITES_AVAILABLE } else { Join-Path $nginxDir 'sites-available' }
$sitesEnabled = if ($env:SITES_ENABLED) { $env:SITES_ENABLED } else { Join-Path $nginxDir 'sites-enabled' }
$siteName = if ($env:SITE_NAME) { $env:SITE_NAME } else { "$ListenPort.conf" }
$siteConfPath = if ($env:SITE_CONF_PATH) { $env:SITE_CONF_PATH } else { Join-Path $sitesAvailable $siteName }
$siteLinkPath = if ($env:SITE_LINK_PATH) { $env:SITE_LINK_PATH } else { Join-Path $sitesEnabled $siteName }
$logDir = if ($env:LOG_DIR) { $env:LOG_DIR } else { Join-Path (Split-Path -Parent $runDir) 'log/nginx' }

New-Item -ItemType Directory -Path $nginxDir, $sitesAvailable, $sitesEnabled, $logDir, $runDir -Force | Out-Null

Backup-FileIfExists -Path $nginxConf

$mainConf = @"
worker_processes  auto;

error_log  $logDir/error.log warn;
pid        $runDir/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '`$remote_addr - `$remote_user [`$time_local] "`$request" '
                      '`$status `$body_bytes_sent "`$http_referer" '
                      '"`$http_user_agent" "`$http_x_forwarded_for"';
    access_log  $logDir/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;

    map `$http_upgrade `$connection_upgrade {
        default upgrade;
        ''      close;
    }

    map `$http_x_forwarded_proto `$proxy_x_forwarded_proto {
        default `$http_x_forwarded_proto;
        ''      `$scheme;
    }

    include sites-enabled/*;
}
"@
Set-Content -LiteralPath $nginxConf -Value $mainConf -Encoding UTF8

Backup-FileIfExists -Path $siteConfPath

$siteConf = @"
upstream auth_11952  { server $UpAuth; }
upstream admin_11950 { server $UpAdmin; }
upstream agent_11949 { server $UpAgent; }
upstream term_11947  { server $UpTerm; }

server {
    listen $ListenIp`:$ListenPort;
    server_name $Domain;

    proxy_set_header Host              `$host;
    proxy_set_header X-Real-IP         `$remote_addr;
    proxy_set_header X-Forwarded-For   `$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto `$proxy_x_forwarded_proto;

    proxy_http_version 1.1;
    proxy_set_header Upgrade    `$http_upgrade;
    proxy_set_header Connection `$connection_upgrade;

    location = /healthz {
        add_header Content-Type text/plain;
        return 200 "ok";
    }

    location ^~ /admin/api { proxy_pass http://auth_11952; }
    location ^~ /api/auth  { proxy_pass http://auth_11952; }
    location ^~ /api/app   { proxy_pass http://auth_11952; }
    location ^~ /oauth2    { proxy_pass http://auth_11952; }
    location ^~ /openid    { proxy_pass http://auth_11952; }

    location ^~ /admin {
        proxy_set_header X-Forwarded-Host  `$host;
        proxy_set_header X-Forwarded-Proto `$proxy_x_forwarded_proto;
        proxy_pass http://admin_11950;
    }

    location ^~ /api/ap/ {
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        add_header X-Accel-Buffering no;
        proxy_pass http://agent_11949;
    }

    location ^~ /appterm {
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        proxy_pass http://term_11947;
    }
    location ^~ /term {
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        proxy_pass http://term_11947;
    }

    location / { return 404; }
}
"@
Set-Content -LiteralPath $siteConfPath -Value $siteConf -Encoding UTF8

Ensure-SymlinkOrCopy -Source $siteConfPath -LinkPath $siteLinkPath

Write-Host "Testing Nginx with: nginx -t -c $nginxConf"
& nginx -t -c $nginxConf
if ($LASTEXITCODE -ne 0) {
  throw 'nginx -t failed'
}

Write-Host 'Reloading Nginx with this config...'
& nginx -s reload -c $nginxConf 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host 'Reload failed (maybe nginx not running). Starting nginx with this config...'
  & nginx -c $nginxConf
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to start nginx.'
  }
}

try {
  $url = "http://$ListenIp`:$ListenPort/healthz"
  Write-Host "Local check: $url"
  $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
  Write-Host "Health check status: $($resp.StatusCode)"
} catch {
  Write-Warning "Local check failed: $($_.Exception.Message)"
}

@"
Done.

Notes:
- This nginx listens ONLY on $ListenIp`:$ListenPort.
- server_name is set to: $Domain
- Start nginx:   .\scripts\windows\start-nginx.ps1
- Stop nginx:    .\scripts\windows\stop-nginx.ps1
- Restart nginx: .\scripts\windows\restart-nginx.ps1
"@ | Write-Host
