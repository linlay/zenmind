param(
  [ValidateSet('install', 'runtime', 'all')]
  [string]$Mode = 'install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'setup-common.ps1')

$OkItems = New-Object System.Collections.Generic.List[string]
$IssueItems = New-Object System.Collections.Generic.List[string]
$RuntimeBlockers = New-Object System.Collections.Generic.List[string]
$WarnItems = New-Object System.Collections.Generic.List[string]

function Add-Ok {
  param([string]$Item)
  $OkItems.Add($Item)
}

function Add-Issue {
  param([string]$Item, [string]$Hint)
  $IssueItems.Add("$Item|$Hint")
}

function Add-RuntimeBlocker {
  param([string]$Item, [string]$Hint)
  $RuntimeBlockers.Add("$Item|$Hint")
}

function Add-WarnItem {
  param([string]$Item)
  $WarnItems.Add($Item)
}

function Write-Section {
  param([string]$Title)
  Setup-Log $Title
}

function Write-Report {
  Write-Host ''
  Setup-Log "===== environment report (mode=$Mode) ====="

  Write-Section '[OK]'
  if ($OkItems.Count -eq 0) {
    Setup-Log '  - none'
  } else {
    foreach ($entry in $OkItems) {
      Setup-Log "  - $entry"
    }
  }

  Write-Section '[MISSING / VERSION_MISMATCH]'
  if ($IssueItems.Count -eq 0) {
    Setup-Log '  - none'
  } else {
    foreach ($entry in $IssueItems) {
      $parts = $entry -split '\|', 2
      Setup-Log "  - $($parts[0])"
      Setup-Log "    fix: $($parts[1])"
    }
  }

  Write-Section '[NOT_RUNNING / RUNTIME_BLOCKER]'
  if ($RuntimeBlockers.Count -eq 0) {
    Setup-Log '  - none'
  } else {
    foreach ($entry in $RuntimeBlockers) {
      $parts = $entry -split '\|', 2
      Setup-Log "  - $($parts[0])"
      Setup-Log "    fix: $($parts[1])"
    }
  }

  Write-Section '[WARNINGS]'
  if ($WarnItems.Count -eq 0) {
    Setup-Log '  - none'
  } else {
    foreach ($entry in $WarnItems) {
      Setup-Log "  - $entry"
    }
  }
}

function Check-InstallDependencies {
  $failed = $false

  if (Test-SetupCommand -Command 'git') {
    Add-Ok 'git installed'
  } else {
    Add-Issue 'git missing' 'winget install --id Git.Git -e'
    $failed = $true
  }

  if (Test-SetupCommand -Command 'java') {
    $javaOutput = (& java -version) 2>&1
    $raw = ($javaOutput | Select-Object -First 1)
    $match = [regex]::Match($raw, '"([0-9]+(?:\.[0-9]+){0,2})"')
    if ($match.Success) {
      $version = $match.Groups[1].Value
      $major = [int](($version -split '\.')[0])
      if ($major -ge 21) {
        Add-Ok "java installed (version $version)"
      } else {
        Add-Issue "java version too low ($version, required 21+)" 'winget install --id EclipseAdoptium.Temurin.21.JDK -e'
        $failed = $true
      }
    } else {
      Add-Issue "java version unparsable ($raw)" 'winget install --id EclipseAdoptium.Temurin.21.JDK -e'
      $failed = $true
    }
  } else {
    Add-Issue 'java missing (required: JDK 21+)' 'winget install --id EclipseAdoptium.Temurin.21.JDK -e'
    $failed = $true
  }

  if (Test-SetupCommand -Command 'mvn') {
    $mvnInfo = & mvn -v
    $line = $mvnInfo | Where-Object { $_ -match 'Apache Maven' } | Select-Object -First 1
    if ($null -eq $line) {
      Add-Issue 'maven version unparsable' 'winget install --id Apache.Maven -e'
      $failed = $true
    } else {
      $match = [regex]::Match($line, 'Apache Maven\s+([0-9]+(?:\.[0-9]+){1,2})')
      if ($match.Success -and (Setup-SemverGe -Actual $match.Groups[1].Value -Required '3.9.0')) {
        Add-Ok "maven installed (version $($match.Groups[1].Value))"
      } else {
        Add-Issue 'maven version too low (required: 3.9+)' 'winget install --id Apache.Maven -e'
        $failed = $true
      }
    }
  } else {
    Add-Issue 'maven missing (required: 3.9+)' 'winget install --id Apache.Maven -e'
    $failed = $true
  }

  if (Test-SetupCommand -Command 'node') {
    $version = (& node -v).TrimStart('v')
    if (Setup-SemverGe -Actual $version -Required '20.0.0') {
      Add-Ok "node installed (version v$version)"
    } else {
      Add-Issue "node version too low (v$version, required 20+)" 'winget install --id OpenJS.NodeJS.LTS -e'
      $failed = $true
    }
  } else {
    Add-Issue 'node missing (required: 20+)' 'winget install --id OpenJS.NodeJS.LTS -e'
    $failed = $true
  }

  if (Test-SetupCommand -Command 'npm') {
    Add-Ok "npm installed (version $(& npm -v))"
  } else {
    Add-Issue 'npm missing' 'reinstall Node.js LTS: winget install --id OpenJS.NodeJS.LTS -e'
    $failed = $true
  }

  if (Test-SetupCommand -Command 'docker') {
    Add-Ok 'docker installed'
    & docker compose version *> $null
    if ($LASTEXITCODE -eq 0) {
      $composeVersion = (& docker compose version | Select-Object -First 1)
      Add-Ok "docker compose plugin installed ($composeVersion)"
    } else {
      Add-Issue 'docker compose plugin missing' 'upgrade Docker Desktop: winget upgrade --id Docker.DockerDesktop -e'
      $failed = $true
    }
  } else {
    Add-Issue 'docker missing' 'winget install --id Docker.DockerDesktop -e; then launch Docker Desktop'
    $failed = $true
  }

  return (-not $failed)
}

function Check-RuntimeStatus {
  $failed = $false

  if (Test-SetupCommand -Command 'docker') {
    Add-Ok 'docker command available for runtime checks'
    if (Setup-DockerDaemonRunning) {
      Add-Ok 'docker daemon running'
    } else {
      Add-RuntimeBlocker 'docker daemon not running' 'start Docker Desktop'
      $failed = $true
    }
  } else {
    if ($Mode -eq 'runtime') {
      Add-RuntimeBlocker 'docker missing' 'winget install --id Docker.DockerDesktop -e; then launch Docker Desktop'
      $failed = $true
    } else {
      Add-WarnItem 'runtime docker check skipped because docker is missing'
    }
  }

  if (Test-SetupCommand -Command 'nginx') {
    Add-Ok 'nginx installed'
    if (Get-Process -Name nginx -ErrorAction SilentlyContinue) {
      Add-Ok 'nginx running'
    } else {
      Add-WarnItem 'nginx installed but not running (optional). start command: nginx'
    }
  } else {
    Add-WarnItem 'nginx not installed (optional). install: winget install --id Nginx.Nginx -e'
  }

  return (-not $failed)
}

$ok = $true
switch ($Mode) {
  'install' {
    if (-not (Check-InstallDependencies)) { $ok = $false }
  }
  'runtime' {
    if (-not (Check-RuntimeStatus)) { $ok = $false }
  }
  'all' {
    if (-not (Check-InstallDependencies)) { $ok = $false }
    if (-not (Check-RuntimeStatus)) { $ok = $false }
  }
}

Write-Report
if ($ok) { exit 0 }
exit 1
