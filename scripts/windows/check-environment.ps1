param(
  [ValidateSet('install', 'runtime', 'all')]
  [string]$Mode = 'install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$ScriptDir = Split-Path -Parent $ScriptPath
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

function Test-WslCommand {
  return (Test-SetupCommand -Command 'wsl.exe')
}

function Normalize-WslOutputLine {
  param([object]$Line)
  return ("$Line" -replace "`0", '').Trim()
}

function Invoke-WslCommand {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  if (-not (Test-WslCommand)) {
    return @{
      Ok = $false
      ExitCode = -1
      Output = @()
      ErrorSummary = 'wsl.exe not found'
    }
  }

  try {
    $output = & wsl.exe @Arguments 2>&1
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    $cleanOutput = @($output | ForEach-Object { Normalize-WslOutputLine -Line $_ })

    $errorCode = $null
    foreach ($line in $cleanOutput) {
      $match = [regex]::Match($line, '\bE_[A-Z_]+\b')
      if ($match.Success) {
        $errorCode = $match.Value
        break
      }
    }

    $errorSummary = $null
    if ($exitCode -ne 0) {
      if (-not [string]::IsNullOrWhiteSpace($errorCode)) {
        $errorSummary = $errorCode
      } elseif (@($cleanOutput).Count -gt 0) {
        $errorSummary = ($cleanOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
      } else {
        $errorSummary = "exit code $exitCode"
      }
    }

    return @{
      Ok = ($exitCode -eq 0)
      ExitCode = $exitCode
      Output = $cleanOutput
      ErrorSummary = $errorSummary
    }
  } catch {
    return @{
      Ok = $false
      ExitCode = -1
      Output = @()
      ErrorSummary = $_.Exception.Message
    }
  }
}

function Parse-WslDistroNames {
  param([string[]]$Lines)

  $distros = New-Object System.Collections.Generic.List[string]
  foreach ($raw in @($Lines)) {
    $clean = Normalize-WslOutputLine -Line $raw
    if ([string]::IsNullOrWhiteSpace($clean)) { continue }
    if ($clean.StartsWith('*')) { $clean = $clean.Substring(1).Trim() }
    if ($clean -match '^(NAME(\s+STATE\s+VERSION)?|[-]+)$') { continue }
    if ($clean -match 'Windows Subsystem for Linux') { continue }
    if ($clean -match 'Wsl/(EnumerateDistros|Service|Api)') { continue }
    if ($clean -match 'no installed distributions') { continue }
    if ($clean -match 'no.*distributions') { continue }

    $name = $clean
    $parts = $clean -split '\s{2,}'
    if ($parts.Count -ge 3 -and $parts[-1] -match '^\d+$') {
      $name = $parts[0].Trim()
    }

    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if (-not $distros.Contains($name)) {
      $distros.Add($name)
    }
  }

  return @($distros)
}

$script:WslDistroProbeCache = $null

function Get-WslDistroProbe {
  if ($null -ne $script:WslDistroProbeCache) {
    return $script:WslDistroProbeCache
  }

  if (-not (Test-WslCommand)) {
    $script:WslDistroProbeCache = @{
      QueryOk = $false
      Distros = @()
      ErrorSummary = 'wsl.exe not found'
    }
    return $script:WslDistroProbeCache
  }

  $attempts = @(
    @('-l', '-q'),
    @('--list', '--quiet'),
    @('-l')
  )
  $lastError = $null

  foreach ($args in $attempts) {
    $result = Invoke-WslCommand -Arguments $args
    if ($result.Ok) {
      # Ensure array semantics even when only one distro is returned.
      $distros = @(Parse-WslDistroNames -Lines @($result.Output))
      if ($distros.Count -eq 0 -and ($args -contains '-q' -or $args -contains '--quiet')) {
        continue
      }

      $script:WslDistroProbeCache = @{
        QueryOk = $true
        Distros = @($distros)
        ErrorSummary = $null
      }
      return $script:WslDistroProbeCache
    }

    if (-not [string]::IsNullOrWhiteSpace($result.ErrorSummary)) {
      $lastError = $result.ErrorSummary
    } else {
      $lastError = "exit code $($result.ExitCode)"
    }
  }

  $script:WslDistroProbeCache = @{
    QueryOk = $false
    Distros = @()
    ErrorSummary = $lastError
  }
  return $script:WslDistroProbeCache
}

function Get-WslDistroList {
  $probe = Get-WslDistroProbe
  return @($probe.Distros)
}

function Test-WslProbeAccessDenied {
  param([hashtable]$Probe)

  if ($null -eq $Probe) { return $false }
  if ($Probe.QueryOk) { return $false }
  if ([string]::IsNullOrWhiteSpace($Probe.ErrorSummary)) { return $false }
  return ($Probe.ErrorSummary -match '\bE_ACCESSDENIED\b')
}

function Get-WslVersionMap {
  $map = @{}
  if (-not (Test-WslCommand)) {
    return $map
  }

  $result = Invoke-WslCommand -Arguments @('-l', '-v')
  if (-not $result.Ok) {
    return $map
  }

  foreach ($raw in @($result.Output)) {
    $clean = Normalize-WslOutputLine -Line $raw
    if ([string]::IsNullOrWhiteSpace($clean)) { continue }
    if ($clean -match '^(NAME(\s+STATE\s+VERSION)?|[-]+)$') { continue }
    if ($clean.StartsWith('*')) { $clean = $clean.Substring(1).Trim() }

    $parts = $clean -split '\s{2,}'
    if ($parts.Count -ge 3 -and $parts[-1] -match '^\d+$') {
      $name = $parts[0].Trim()
      if (-not [string]::IsNullOrWhiteSpace($name)) {
        $map[$name] = [int]$parts[-1]
      }
      continue
    }

    if ($clean -match '^(?<name>.+?)\s+\S+\s+(?<ver>\d+)\s*$') {
      $map[$matches.name.Trim()] = [int]$matches.ver
    }
  }

  return $map
}

function Invoke-WslSh {
  param([Parameter(Mandatory = $true)][string]$Command)

  $result = Invoke-WslCommand -Arguments @('-e', 'sh', '-lc', $Command)
  return $result.Ok
}

function Get-ContainerProvider {
  if (Test-SetupCommand -Command 'docker') {
    return @{
      Name = 'docker'
      DisplayName = 'Docker (Windows)'
      Scope = 'windows'
    }
  }
  if (Test-SetupCommand -Command 'podman') {
    return @{
      Name = 'podman'
      DisplayName = 'Podman (Windows)'
      Scope = 'windows'
    }
  }

  $wslProbe = Get-WslDistroProbe
  if (-not $wslProbe.QueryOk) {
    return $null
  }
  if (@($wslProbe.Distros).Count -eq 0) {
    return $null
  }

  if (Invoke-WslSh -Command 'command -v docker >/dev/null 2>&1') {
    return @{
      Name = 'docker'
      DisplayName = 'Docker (WSL)'
      Scope = 'wsl'
    }
  }
  if (Invoke-WslSh -Command 'command -v podman >/dev/null 2>&1') {
    return @{
      Name = 'podman'
      DisplayName = 'Podman (WSL)'
      Scope = 'wsl'
    }
  }
  return $null
}

function Test-ComposeAvailable {
  param([Parameter(Mandatory = $true)][hashtable]$Provider)

  if ($Provider.Scope -eq 'windows') {
    if ($Provider.Name -eq 'docker') {
      & docker compose version *> $null
      return ($LASTEXITCODE -eq 0)
    }

    & podman compose version *> $null
    if ($LASTEXITCODE -eq 0) {
      return $true
    }
    if (Test-SetupCommand -Command 'podman-compose') {
      & podman-compose version *> $null
      return ($LASTEXITCODE -eq 0)
    }
    return $false
  }

  if ($Provider.Name -eq 'docker') {
    return (Invoke-WslSh -Command 'docker compose version >/dev/null 2>&1')
  }

  if (Invoke-WslSh -Command 'podman compose version >/dev/null 2>&1') {
    return $true
  }
  return (Invoke-WslSh -Command 'podman-compose version >/dev/null 2>&1')
}

function Get-ComposeVersionLine {
  param([Parameter(Mandatory = $true)][hashtable]$Provider)

  if ($Provider.Scope -eq 'windows') {
    if ($Provider.Name -eq 'docker') {
      return (& docker compose version | Select-Object -First 1)
    }

    & podman compose version *> $null
    if ($LASTEXITCODE -eq 0) {
      return (& podman compose version | Select-Object -First 1)
    }
    if (Test-SetupCommand -Command 'podman-compose') {
      return (& podman-compose version | Select-Object -First 1)
    }
    return 'compose version unavailable'
  }

  if ($Provider.Name -eq 'docker') {
    $lineResult = Invoke-WslCommand -Arguments @('-e', 'sh', '-lc', 'docker compose version 2>/dev/null | head -n 1')
    return ($lineResult.Output | Select-Object -First 1)
  }

  if (Invoke-WslSh -Command 'podman compose version >/dev/null 2>&1') {
    $lineResult = Invoke-WslCommand -Arguments @('-e', 'sh', '-lc', 'podman compose version 2>/dev/null | head -n 1')
    return ($lineResult.Output | Select-Object -First 1)
  }
  $lineResult = Invoke-WslCommand -Arguments @('-e', 'sh', '-lc', 'podman-compose version 2>/dev/null | head -n 1')
  return ($lineResult.Output | Select-Object -First 1)
}

function Test-ContainerRuntimeReady {
  param([Parameter(Mandatory = $true)][hashtable]$Provider)

  if ($Provider.Scope -eq 'windows') {
    if ($Provider.Name -eq 'docker') {
      return (Setup-DockerDaemonRunning)
    }
    & podman info *> $null
    return ($LASTEXITCODE -eq 0)
  }

  if ($Provider.Name -eq 'docker') {
    return (Invoke-WslSh -Command 'docker info >/dev/null 2>&1')
  }
  return (Invoke-WslSh -Command 'podman info >/dev/null 2>&1')
}

function Check-InstallDependencies {
  $failed = $false

  if (Test-SetupCommand -Command 'git') {
    Add-Ok 'git installed'
  } else {
    Add-Issue 'git missing' 'winget install --id Git.Git -e'
    $failed = $true
  }

  if (Test-WslCommand) {
    Add-Ok 'wsl installed'
    $wslProbe = Get-WslDistroProbe
    if (-not $wslProbe.QueryOk) {
      if ([string]::IsNullOrWhiteSpace($wslProbe.ErrorSummary)) {
        Add-WarnItem 'unable to query WSL distro list. run: wsl -l -v'
      } else {
        Add-WarnItem "unable to query WSL distro list ($($wslProbe.ErrorSummary)). run: wsl -l -v"
      }
      Add-WarnItem 'if your distro exists, run this script under the same Windows user that owns the distro (avoid elevated/system context)'
    } else {
      $wslDistros = @($wslProbe.Distros)
      if (@($wslDistros).Count -eq 0) {
        Add-WarnItem 'wsl is installed but no Linux distro detected. install one: wsl --install -d Ubuntu'
      } else {
        Add-Ok "wsl distro available ($($wslDistros[0]))"
      }
      $versionMap = Get-WslVersionMap
      if ($versionMap.Count -gt 0) {
        $wsl1 = @()
        foreach ($name in $versionMap.Keys) {
          if ($versionMap[$name] -lt 2) { $wsl1 += $name }
        }
        if ($wsl1.Count -gt 0) {
          Add-WarnItem "WSL1 distro detected ($($wsl1 -join ', ')). recommend WSL2: wsl --set-version <DistroName> 2"
        } else {
          Add-Ok 'wsl2 ready'
        }
      }
    }
  } else {
    Add-Issue 'wsl missing (recommended for Docker Engine/Podman workflow on Windows)' 'install WSL: wsl --install'
    $failed = $true
  }

  if (Test-SetupCommand -Command 'java') {
    $javaOutput = cmd /c "java -version 2>&1"
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

  $containerProvider = Get-ContainerProvider
  if ($null -ne $containerProvider) {
    Add-Ok "container command available ($($containerProvider.DisplayName))"
    if (Test-ComposeAvailable -Provider $containerProvider) {
      $composeVersion = Get-ComposeVersionLine -Provider $containerProvider
      Add-Ok "compose available ($composeVersion)"
    } else {
      Add-Issue 'compose unavailable' 'WSL Docker Engine: install docker compose plugin; Podman: install podman-compose'
      $failed = $true
    }
  } else {
    $wslProbe = Get-WslDistroProbe
    if (Test-WslProbeAccessDenied -Probe $wslProbe) {
      Add-WarnItem 'container check skipped because WSL access is denied (E_ACCESSDENIED)'
      Add-WarnItem 'rerun under the Windows user that owns the WSL distro, then rerun precheck'
    } elseif (-not $wslProbe.QueryOk -and -not [string]::IsNullOrWhiteSpace($wslProbe.ErrorSummary)) {
      Add-WarnItem "WSL probe issue detected: $($wslProbe.ErrorSummary)"
      Add-Issue 'docker/podman missing (Windows and WSL)' 'Option A: install Docker Engine + compose in WSL; Option B: install Podman (Windows or WSL)'
      $failed = $true
    } else {
      Add-Issue 'docker/podman missing (Windows and WSL)' 'Option A: install Docker Engine + compose in WSL; Option B: install Podman (Windows or WSL)'
      $failed = $true
    }
  }

  return (-not $failed)
}

function Check-RuntimeStatus {
  $failed = $false

  $containerProvider = Get-ContainerProvider
  if ($null -ne $containerProvider) {
    Add-Ok "container command available for runtime checks ($($containerProvider.DisplayName))"

    if (Test-ComposeAvailable -Provider $containerProvider) {
      $composeVersion = Get-ComposeVersionLine -Provider $containerProvider
      Add-Ok "compose available ($composeVersion)"
    } else {
      Add-RuntimeBlocker 'compose unavailable' 'install/repair compose for selected engine (docker compose plugin or podman-compose)'
      $failed = $true
    }

    if (Test-ContainerRuntimeReady -Provider $containerProvider) {
      Add-Ok "$($containerProvider.DisplayName) runtime ready"
    } else {
      if ($containerProvider.Name -eq 'docker' -and $containerProvider.Scope -eq 'windows') {
        Add-RuntimeBlocker 'docker runtime not ready' 'start docker daemon/service'
      } elseif ($containerProvider.Name -eq 'docker' -and $containerProvider.Scope -eq 'wsl') {
        Add-RuntimeBlocker 'docker runtime not ready (WSL)' 'start Docker daemon inside WSL distro'
      } elseif ($containerProvider.Scope -eq 'wsl') {
        Add-RuntimeBlocker 'podman runtime not ready (WSL)' 'start Podman service/machine inside WSL distro'
      } else {
        Add-RuntimeBlocker 'podman runtime not ready' 'start podman machine: podman machine start'
      }
      $failed = $true
    }
  } else {
    $wslProbe = Get-WslDistroProbe
    if (-not $wslProbe.QueryOk -and -not [string]::IsNullOrWhiteSpace($wslProbe.ErrorSummary)) {
      Add-WarnItem "WSL probe issue detected: $($wslProbe.ErrorSummary)"
    }
    if (Test-WslProbeAccessDenied -Probe $wslProbe) {
      if ($Mode -eq 'runtime') {
        Add-RuntimeBlocker 'unable to verify container runtime (WSL access denied)' 'run under distro owner user, then rerun runtime check'
        $failed = $true
      } else {
        Add-WarnItem 'runtime container check skipped because WSL access is denied (E_ACCESSDENIED)'
      }
    } else {
      if ($Mode -eq 'runtime') {
        Add-RuntimeBlocker 'docker/podman missing (Windows and WSL)' 'install Docker Engine in WSL, or install Podman'
        $failed = $true
      } else {
        Add-WarnItem 'runtime container check skipped because no container engine was found (Windows/WSL)'
      }
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
