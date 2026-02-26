Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OsName {
  if ($IsWindows) { return 'windows' }
  if ($IsMacOS) { return 'darwin' }
  if ($IsLinux) { return 'linux' }
  return 'unknown'
}

function Get-DefaultNginxDir {
  param(
    [Parameter(Mandatory = $true)][string]$OsName,
    [string]$BrewPrefix
  )

  switch ($OsName) {
    'windows' {
      $candidates = @(
        (Join-Path $env:ProgramFiles 'nginx\conf'),
        (Join-Path ${env:ProgramFiles(x86)} 'nginx\conf'),
        'C:\nginx\conf'
      ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

      foreach ($item in $candidates) {
        if (Test-Path -LiteralPath $item) { return $item }
      }

      $nginxCmd = Get-Command -Name nginx -ErrorAction SilentlyContinue
      if ($null -ne $nginxCmd) {
        $binDir = Split-Path -Parent $nginxCmd.Source
        $confDir = Join-Path $binDir 'conf'
        if (Test-Path -LiteralPath $confDir) { return $confDir }
      }

      return 'C:\nginx\conf'
    }
    'darwin' {
      if (-not [string]::IsNullOrWhiteSpace($BrewPrefix)) { return (Join-Path $BrewPrefix 'etc/nginx') }
      return '/usr/local/etc/nginx'
    }
    'linux' {
      if (Test-Path -LiteralPath '/etc/nginx') { return '/etc/nginx' }
      return '/usr/local/etc/nginx'
    }
    default {
      return ''
    }
  }
}

function Get-DefaultRunDir {
  param(
    [Parameter(Mandatory = $true)][string]$OsName,
    [string]$BrewPrefix
  )

  switch ($OsName) {
    'windows' { return (Join-Path $env:TEMP 'nginx') }
    'darwin' {
      if (-not [string]::IsNullOrWhiteSpace($BrewPrefix)) { return (Join-Path $BrewPrefix 'var/run') }
      return '/usr/local/var/run'
    }
    'linux' { return '/var/run' }
    default { return '' }
  }
}

function Get-PidFileFromConf {
  param([string]$ConfFile)
  if (-not (Test-Path -LiteralPath $ConfFile)) {
    return $null
  }

  foreach ($line in Get-Content -LiteralPath $ConfFile) {
    $trimmed = $line.Trim()
    if ($trimmed -match '^pid\s+(.+?);$') {
      return $matches[1]
    }
  }
  return $null
}

function Resolve-NginxPaths {
  $script:OS_NAME = if ($env:OS_NAME) { $env:OS_NAME } else { Get-OsName }
  $script:BREW_PREFIX = if ($env:BREW_PREFIX) { $env:BREW_PREFIX } else { '' }

  $defaultNginxDir = Get-DefaultNginxDir -OsName $script:OS_NAME -BrewPrefix $script:BREW_PREFIX
  $script:NGINX_DIR = if ($env:NGINX_DIR) { $env:NGINX_DIR } else { $defaultNginxDir }
  if ([string]::IsNullOrWhiteSpace($script:NGINX_DIR)) {
    throw 'Unable to determine NGINX_DIR. Set env NGINX_DIR manually.'
  }

  $script:NGINX_CONF = if ($env:NGINX_CONF) { $env:NGINX_CONF } else { Join-Path $script:NGINX_DIR 'nginx.conf' }

  $defaultRunDir = Get-DefaultRunDir -OsName $script:OS_NAME -BrewPrefix $script:BREW_PREFIX
  $script:RUN_DIR = if ($env:RUN_DIR) { $env:RUN_DIR } else { $defaultRunDir }
  if ([string]::IsNullOrWhiteSpace($script:RUN_DIR)) {
    throw 'Unable to determine RUN_DIR. Set env RUN_DIR manually.'
  }

  New-Item -ItemType Directory -Path $script:RUN_DIR -Force | Out-Null

  $confPid = Get-PidFileFromConf -ConfFile $script:NGINX_CONF
  if ($env:PID_FILE) {
    $script:PID_FILE = $env:PID_FILE
  } elseif (-not [string]::IsNullOrWhiteSpace($confPid)) {
    $script:PID_FILE = $confPid
  } else {
    $script:PID_FILE = Join-Path $script:RUN_DIR 'nginx.pid'
  }
}

function Require-NginxBinary {
  if (-not (Get-Command -Name nginx -ErrorAction SilentlyContinue)) {
    throw 'nginx command not found in PATH.'
  }
}
