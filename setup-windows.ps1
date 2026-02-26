[CmdletBinding()]
param(
  [string]$Action,
  [string]$BaseDir,
  [switch]$Yes,
  [Alias('h')][switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($BaseDir)) {
  $BaseDir = $ScriptDir
}

. (Join-Path $ScriptDir 'scripts/windows/setup-common.ps1')

$SourceSubdir = 'source'
$ReleaseSubdir = 'release'
$RepoNames = @('term-webclient', 'zenmind-app-server', 'agent-platform-runner')
$RepoUrls = @{
  'term-webclient' = 'https://github.com/linlay/term-webclient.git'
  'zenmind-app-server' = 'https://github.com/linlay/zenmind-app-server.git'
  'agent-platform-runner' = 'https://github.com/linlay/agent-platform-runner.git'
}
$ConfigMappings = @(
  @{ Source = 'source/term-webclient/.env.example'; Target = 'release/term-webclient/.env'; Required = $true },
  @{ Source = 'source/term-webclient/application.example.yml'; Target = 'release/term-webclient/application.yml'; Required = $true },
  @{ Source = 'source/zenmind-app-server/.env.example'; Target = 'release/zenmind-app-server/.env'; Required = $true },
  @{ Source = 'source/agent-platform-runner/application.example.yml'; Target = 'release/agent-platform-runner/application.yml'; Required = $true }
)

$SummaryOk = New-Object System.Collections.Generic.List[string]
$SummaryWarn = New-Object System.Collections.Generic.List[string]
$SummaryFail = New-Object System.Collections.Generic.List[string]
$script:UpdateConfigBackupDir = $null
$env:SETUP_NON_INTERACTIVE = if ($Yes.IsPresent) { '1' } else { '0' }

function Show-Usage {
  @"
Usage: $(Split-Path -Leaf $MyInvocation.MyCommand.Path) [-Action ACTION] [-BaseDir PATH] [-Yes] [-Help]

Interactive menu (default):
  1) 环境检测
  2) 首次安装
  3) 更新
  4) 启动
  5) 停止
  6) 重置密码哈希
  0) 退出

Options:
  -Action      precheck | first-install | update | start | stop | reset-password-hash
  -BaseDir     工作区根目录（默认: 脚本所在目录）
  -Yes         非交互模式（密码提示使用默认值）
  -Help/-h     显示帮助
"@ | Write-Host
}

if ($Help -or $Action -in @('help', '--help', '-h', '/?')) {
  Show-Usage
  exit 0
}

if (-not [string]::IsNullOrWhiteSpace($Action)) {
  $allowedActions = @('precheck', 'first-install', 'update', 'start', 'stop', 'reset-password-hash')
  if ($allowedActions -notcontains $Action) {
    throw "invalid action: $Action (allowed: $($allowedActions -join ', '))"
  }
}

function Join-WorkspacePath {
  param([string]$RelativePath)
  $parts = ($RelativePath -replace '\\', '/') -split '/'
  $path = $BaseDir
  foreach ($part in $parts) {
    if ([string]::IsNullOrWhiteSpace($part)) { continue }
    $path = Join-Path $path $part
  }
  return $path
}

function Get-WorkspaceSourceDir {
  return (Join-Path $BaseDir $SourceSubdir)
}

function Get-WorkspaceReleaseDir {
  return (Join-Path $BaseDir $ReleaseSubdir)
}

function Get-RepoSourceDir {
  param([string]$Repo)
  return (Join-Path (Get-WorkspaceSourceDir) $Repo)
}

function Get-RepoReleaseDir {
  param([string]$Repo)
  return (Join-Path (Get-WorkspaceReleaseDir) $Repo)
}

function Get-RepoPackagedOutputDir {
  param([string]$Repo)
  switch ($Repo) {
    'term-webclient' { return (Join-Path (Get-RepoSourceDir $Repo) 'release') }
    'zenmind-app-server' { return (Join-Path (Get-RepoSourceDir $Repo) 'release') }
    'agent-platform-runner' { return (Join-Path (Get-RepoSourceDir $Repo) 'release-local') }
    default { throw "unsupported repo: $Repo" }
  }
}

function Ensure-WorkspaceLayout {
  New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
  New-Item -ItemType Directory -Path (Get-WorkspaceSourceDir) -Force | Out-Null
  New-Item -ItemType Directory -Path (Get-WorkspaceReleaseDir) -Force | Out-Null
}

function Summary-Reset {
  $SummaryOk.Clear()
  $SummaryWarn.Clear()
  $SummaryFail.Clear()
}

function Summary-AddOk {
  param([string]$Message)
  $SummaryOk.Add($Message)
  Setup-Log $Message
}

function Summary-AddWarn {
  param([string]$Message)
  $SummaryWarn.Add($Message)
  Setup-Warn $Message
}

function Summary-AddFail {
  param([string]$Message)
  $SummaryFail.Add($Message)
  Setup-Err $Message
}

function Print-Summary {
  param([string]$Title)

  Write-Host ''
  Setup-Log "===== $Title summary ====="

  if ($SummaryOk.Count -gt 0) {
    Setup-Log "success ($($SummaryOk.Count)):"
    foreach ($item in $SummaryOk) {
      Setup-Log "  - $item"
    }
  }

  if ($SummaryWarn.Count -gt 0) {
    Setup-Warn "warnings ($($SummaryWarn.Count)):"
    foreach ($item in $SummaryWarn) {
      Setup-Warn "  - $item"
    }
  }

  if ($SummaryFail.Count -gt 0) {
    Setup-Err "failures ($($SummaryFail.Count)):"
    foreach ($item in $SummaryFail) {
      Setup-Err "  - $item"
    }

    if ($Title -eq 'precheck') {
      return
    }

    @'
[setup-win] common fix hints:
  - Run precheck first: .\setup-windows.ps1 -Action precheck
  - Install dependencies: git, JDK 21+, Maven 3.9+, Node.js 20+, Docker Desktop
  - Optional nginx install: winget install --id Nginx.Nginx -e
  - Optional bcrypt helper: install python+bcrypt or htpasswd
'@ | Write-Host
  }
}

function Ensure-CheckScriptReady {
  $checkScript = Join-Path $ScriptDir 'scripts/windows/check-environment.ps1'
  if (-not (Test-Path -LiteralPath $checkScript)) {
    Summary-AddFail "environment check script missing: $checkScript"
    return $null
  }
  return $checkScript
}

function Invoke-CheckScriptProcess {
  param(
    [Parameter(Mandatory = $true)][string]$CheckScriptPath,
    [Parameter(Mandatory = $true)][ValidateSet('install', 'runtime', 'all')][string]$Mode
  )

  $psExe = $null
  $powershellCmd = Get-Command -Name powershell -ErrorAction SilentlyContinue
  if ($null -ne $powershellCmd) {
    $psExe = $powershellCmd.Source
  } else {
    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwshCmd) {
      $psExe = $pwshCmd.Source
    }
  }

  if ([string]::IsNullOrWhiteSpace($psExe)) {
    Summary-AddFail 'no powershell executable found to run check-environment.ps1'
    return $false
  }

  & $psExe -NoProfile -ExecutionPolicy Bypass -File $CheckScriptPath -Mode $Mode
  return ($LASTEXITCODE -eq 0)
}

function Invoke-RepoScript {
  param(
    [Parameter(Mandatory = $true)][string]$RepoDir,
    [Parameter(Mandatory = $true)][string[]]$Candidates,
    [string[]]$Arguments = @()
  )

  foreach ($candidate in $Candidates) {
    $path = Join-Path $RepoDir $candidate
    if (-not (Test-Path -LiteralPath $path)) {
      continue
    }

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    try {
      switch ($ext) {
        '.ps1' {
          $global:LASTEXITCODE = 0
          & $path @Arguments
          $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
          return @{ Ok = ($exitCode -eq 0); Path = $path }
        }
        '.bat' {
          $argLine = ($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
          }) -join ' '
          $commandText = if ([string]::IsNullOrWhiteSpace($argLine)) { '"' + $path + '"' } else { '"' + $path + '" ' + $argLine }
          & cmd.exe /c $commandText
          return @{ Ok = ($LASTEXITCODE -eq 0); Path = $path }
        }
        '.cmd' {
          $argLine = ($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
          }) -join ' '
          $commandText = if ([string]::IsNullOrWhiteSpace($argLine)) { '"' + $path + '"' } else { '"' + $path + '" ' + $argLine }
          & cmd.exe /c $commandText
          return @{ Ok = ($LASTEXITCODE -eq 0); Path = $path }
        }
        '.sh' {
          if (-not (Test-SetupCommand -Command 'bash')) {
            continue
          }
          & bash $path @Arguments
          return @{ Ok = ($LASTEXITCODE -eq 0); Path = $path }
        }
      }
    } catch {
      return @{ Ok = $false; Path = $path; Error = $_.Exception.Message }
    }
  }

  return @{ Ok = $false; Path = $null }
}

function Refresh-RepoByClone {
  param([string]$Repo)

  $url = $RepoUrls[$Repo]
  $dir = Get-RepoSourceDir $Repo

  if (Test-Path -LiteralPath $dir) {
    Setup-Log "removing existing source repo: $dir"
    Remove-Item -LiteralPath $dir -Recurse -Force
  }

  Setup-Log "cloning $url -> $dir"
  & git clone $url $dir
  if ($LASTEXITCODE -eq 0) {
    Summary-AddOk "cloned $Repo"
    return $true
  }

  Summary-AddFail "failed to clone $Repo"
  return $false
}

function Test-RepoFile {
  param([string]$Repo, [string]$RelativePath)
  $full = Join-Path (Get-RepoSourceDir $Repo) $RelativePath
  if (-not (Test-Path -LiteralPath $full)) {
    Summary-AddFail "missing required file: $full"
    return $false
  }
  Summary-AddOk "required file exists: source/$Repo/$RelativePath"
  return $true
}

function Test-AnyRepoFile {
  param([string]$Repo, [string[]]$Candidates)
  foreach ($candidate in $Candidates) {
    if (Test-Path -LiteralPath (Join-Path (Get-RepoSourceDir $Repo) $candidate)) {
      Summary-AddOk "required script exists: source/$Repo/$candidate"
      return $true
    }
  }
  Summary-AddFail "missing required script in source/$Repo: $($Candidates -join ', ')"
  return $false
}

function Check-RequiredRepoFiles {
  $failed = $false

  if (-not (Test-RepoFile -Repo 'term-webclient' -RelativePath 'README.md')) { $failed = $true }
  if (-not (Test-RepoFile -Repo 'term-webclient' -RelativePath 'backend/pom.xml')) { $failed = $true }
  if (-not (Test-RepoFile -Repo 'term-webclient' -RelativePath 'frontend/package.json')) { $failed = $true }
  if (-not (Test-AnyRepoFile -Repo 'term-webclient' -Candidates @('release-scripts/windows/package.ps1', 'release-scripts/windows/package.bat', 'release-scripts/windows/package.cmd'))) { $failed = $true }

  if (-not (Test-RepoFile -Repo 'zenmind-app-server' -RelativePath 'README.md')) { $failed = $true }
  if (-not (Test-RepoFile -Repo 'zenmind-app-server' -RelativePath 'backend/pom.xml')) { $failed = $true }
  if (-not (Test-RepoFile -Repo 'zenmind-app-server' -RelativePath 'frontend/package.json')) { $failed = $true }
  if (-not (Test-RepoFile -Repo 'zenmind-app-server' -RelativePath 'docker-compose.yml')) { $failed = $true }
  if (-not (Test-AnyRepoFile -Repo 'zenmind-app-server' -Candidates @('release-scripts/windows/package.ps1', 'release-scripts/windows/package.bat', 'release-scripts/windows/package.cmd'))) { $failed = $true }

  if (-not (Test-RepoFile -Repo 'agent-platform-runner' -RelativePath 'README.md')) { $failed = $true }
  if (-not (Test-RepoFile -Repo 'agent-platform-runner' -RelativePath 'pom.xml')) { $failed = $true }
  if (-not (Test-AnyRepoFile -Repo 'agent-platform-runner' -Candidates @('release-scripts/windows/package-local.ps1', 'release-scripts/windows/package-local.bat', 'release-scripts/windows/package-local.cmd'))) { $failed = $true }

  return (-not $failed)
}

function Resolve-ExampleSource {
  param([string]$ExpectedSource)

  if (Test-Path -LiteralPath $ExpectedSource) {
    return $ExpectedSource
  }

  if ($ExpectedSource.EndsWith('.env.example')) {
    $sourceDir = Split-Path -Parent $ExpectedSource

    $envExampleSource = Join-Path $sourceDir 'env.example'
    if (Test-Path -LiteralPath $envExampleSource) {
      Summary-AddWarn "detected env.example and will use it: $envExampleSource"
      return $envExampleSource
    }

    $typoSource = $ExpectedSource.Substring(0, $ExpectedSource.Length - '.env.example'.Length) + '.evn.example'
    if (Test-Path -LiteralPath $typoSource) {
      Summary-AddWarn "detected typo file and will use it: $typoSource"
      return $typoSource
    }

    $hiddenTypoSource = Join-Path $sourceDir '.evn.example'
    if (Test-Path -LiteralPath $hiddenTypoSource) {
      Summary-AddWarn "detected typo file and will use it: $hiddenTypoSource"
      return $hiddenTypoSource
    }
  }

  return $null
}

function Copy-ExampleConfigs {
  param([ValidateSet('overwrite', 'if-missing')][string]$Mode = 'overwrite')

  $failed = $false
  Setup-Log "syncing example configs into release directories (mode=$Mode)"

  foreach ($mapping in $ConfigMappings) {
    $sourcePath = Join-WorkspacePath $mapping.Source
    $targetPath = Join-WorkspacePath $mapping.Target
    $actualSource = Resolve-ExampleSource -ExpectedSource $sourcePath

    if ($null -eq $actualSource) {
      if ($mapping.Required) {
        Summary-AddFail "required source config missing: $sourcePath"
        $failed = $true
      } else {
        Summary-AddWarn "optional source config missing, skip: $sourcePath"
      }
      continue
    }

    $targetDir = Split-Path -Parent $targetPath
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    if (Test-Path -LiteralPath $targetPath) {
      if ($Mode -eq 'if-missing') {
        Summary-AddOk "config exists, keep: $($mapping.Target)"
        continue
      }

      try {
        $backupPath = Setup-BackupFile -FilePath $targetPath
        Summary-AddOk "backup created: $backupPath"
      } catch {
        Summary-AddFail "failed to backup existing config: $targetPath"
        $failed = $true
        continue
      }
    }

    try {
      Copy-Item -LiteralPath $actualSource -Destination $targetPath -Force
      $displaySource = $actualSource
      if ($displaySource.StartsWith("$BaseDir" + [System.IO.Path]::DirectorySeparatorChar)) {
        $displaySource = $displaySource.Substring($BaseDir.Length + 1)
      }
      Summary-AddOk "copied config: $displaySource -> $($mapping.Target)"
    } catch {
      Summary-AddFail "failed to copy config: $($mapping.Source) -> $($mapping.Target)"
      $failed = $true
    }
  }

  return (-not $failed)
}

function Backup-UpdateConfigs {
  $failed = $false

  $backupDir = Join-Path ([System.IO.Path]::GetTempPath()) ("zenmind-config-backup." + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  $script:UpdateConfigBackupDir = $backupDir
  Summary-AddOk "created config backup dir: $backupDir"

  foreach ($mapping in $ConfigMappings) {
    $targetPath = Join-WorkspacePath $mapping.Target
    $backupTarget = Join-Path $backupDir $mapping.Target

    if (-not (Test-Path -LiteralPath $targetPath)) {
      Summary-AddWarn "no existing config to backup: $($mapping.Target)"
      continue
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $backupTarget) -Force | Out-Null
    try {
      Copy-Item -LiteralPath $targetPath -Destination $backupTarget -Force
      Summary-AddOk "backed up config: $($mapping.Target)"
    } catch {
      Summary-AddFail "failed to backup config: $($mapping.Target)"
      $failed = $true
    }
  }

  return (-not $failed)
}

function Restore-UpdateConfigs {
  $failed = $false

  if ([string]::IsNullOrWhiteSpace($script:UpdateConfigBackupDir) -or -not (Test-Path -LiteralPath $script:UpdateConfigBackupDir)) {
    Summary-AddWarn 'config backup dir unavailable, skip restore'
    return $true
  }

  foreach ($mapping in $ConfigMappings) {
    $targetPath = Join-WorkspacePath $mapping.Target
    $backupSource = Join-Path $script:UpdateConfigBackupDir $mapping.Target

    if (-not (Test-Path -LiteralPath $backupSource)) {
      Summary-AddWarn "no backup config to restore: $($mapping.Target)"
      continue
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
    try {
      Copy-Item -LiteralPath $backupSource -Destination $targetPath -Force
      Summary-AddOk "restored config: $($mapping.Target)"
    } catch {
      Summary-AddFail "failed to restore config: $($mapping.Target)"
      $failed = $true
    }
  }

  return (-not $failed)
}

function Cleanup-UpdateConfigBackup {
  if (-not [string]::IsNullOrWhiteSpace($script:UpdateConfigBackupDir) -and (Test-Path -LiteralPath $script:UpdateConfigBackupDir)) {
    Remove-Item -LiteralPath $script:UpdateConfigBackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Summary-AddOk 'removed temp config backup dir'
  }
  $script:UpdateConfigBackupDir = $null
}

function Configure-PasswordHashes {
  $termEnv = Join-Path (Get-RepoReleaseDir 'term-webclient') '.env'
  $appEnv = Join-Path (Get-RepoReleaseDir 'zenmind-app-server') '.env'

  Setup-Log 'configuring bcrypt password hashes in release env files'
  Setup-EnsureEnvFile -EnvFile $termEnv
  Setup-EnsureEnvFile -EnvFile $appEnv

  try {
    $termPlain = Setup-PromptPassword -Prompt 'term-webclient AUTH_PASSWORD_HASH_BCRYPT 对应明文密码' -DefaultPassword 'password'
    $termHash = Setup-GenerateBcrypt -PlainPassword $termPlain
    Setup-UpsertEnvVar -EnvFile $termEnv -Key 'AUTH_PASSWORD_HASH_BCRYPT' -Value (Setup-SingleQuoteEnvValue -Value $termHash)
    Setup-Log "[bcrypt] written to .env: AUTH_PASSWORD_HASH_BCRYPT=$(Setup-SingleQuoteEnvValue -Value $termHash)"
    Summary-AddOk 'updated AUTH_PASSWORD_HASH_BCRYPT in release/term-webclient/.env'

    $adminPlain = Setup-PromptPassword -Prompt 'zenmind-app-server AUTH_ADMIN_PASSWORD_BCRYPT 对应明文密码' -DefaultPassword 'password'
    $adminHash = Setup-GenerateBcrypt -PlainPassword $adminPlain
    Setup-UpsertEnvVar -EnvFile $appEnv -Key 'AUTH_ADMIN_PASSWORD_BCRYPT' -Value (Setup-SingleQuoteEnvValue -Value $adminHash)
    Setup-Log "[bcrypt] written to .env: AUTH_ADMIN_PASSWORD_BCRYPT=$(Setup-SingleQuoteEnvValue -Value $adminHash)"
    Summary-AddOk 'updated AUTH_ADMIN_PASSWORD_BCRYPT in release/zenmind-app-server/.env'

    $masterPlain = Setup-PromptPassword -Prompt 'zenmind-app-server AUTH_APP_MASTER_PASSWORD_BCRYPT 对应明文密码' -DefaultPassword 'password'
    $masterHash = Setup-GenerateBcrypt -PlainPassword $masterPlain
    Setup-UpsertEnvVar -EnvFile $appEnv -Key 'AUTH_APP_MASTER_PASSWORD_BCRYPT' -Value (Setup-SingleQuoteEnvValue -Value $masterHash)
    Setup-Log "[bcrypt] written to .env: AUTH_APP_MASTER_PASSWORD_BCRYPT=$(Setup-SingleQuoteEnvValue -Value $masterHash)"
    Summary-AddOk 'updated AUTH_APP_MASTER_PASSWORD_BCRYPT in release/zenmind-app-server/.env'

    Setup-BcryptHint
    return $true
  } catch {
    Summary-AddFail "failed to configure password hashes: $($_.Exception.Message)"
    return $false
  }
}

function Run-Precheck {
  $checkScript = Ensure-CheckScriptReady
  if ($null -eq $checkScript) { return $false }

  Setup-Log 'running environment check script (mode=all)'
  if (Invoke-CheckScriptProcess -CheckScriptPath $checkScript -Mode 'all') {
    Summary-AddOk 'environment precheck passed (mode=all)'
    return $true
  }

  Summary-AddFail 'environment precheck failed (mode=all)'
  return $false
}

function Check-RuntimeEnvironmentBeforeStart {
  $checkScript = Ensure-CheckScriptReady
  if ($null -eq $checkScript) { return $false }

  Setup-Log 'running environment check script (mode=runtime)'
  if (Invoke-CheckScriptProcess -CheckScriptPath $checkScript -Mode 'runtime') {
    Summary-AddOk 'environment runtime check passed'
    return $true
  }

  Summary-AddFail 'environment runtime check failed'
  return $false
}

function Invoke-PackageForRepo {
  param([string]$Repo)

  $repoDir = Get-RepoSourceDir $Repo
  $candidates = switch ($Repo) {
    'term-webclient' { @('release-scripts/windows/package.ps1', 'release-scripts/windows/package.bat', 'release-scripts/windows/package.cmd') }
    'zenmind-app-server' { @('release-scripts/windows/package.ps1', 'release-scripts/windows/package.bat', 'release-scripts/windows/package.cmd') }
    'agent-platform-runner' { @('release-scripts/windows/package-local.ps1', 'release-scripts/windows/package-local.bat', 'release-scripts/windows/package-local.cmd') }
    default { throw "unsupported repo: $Repo" }
  }

  $result = Invoke-RepoScript -RepoDir $repoDir -Candidates $candidates
  if ($result.Ok) {
    Summary-AddOk "packaged $Repo"
    return $true
  }

  if ($Repo -eq 'agent-platform-runner') {
    if ($null -eq $result.Path) {
      Summary-AddWarn "failed to package $Repo (no package script found), skip optional service"
    } elseif ($result.ContainsKey('Error')) {
      Summary-AddWarn "failed to package $Repo ($($result.Path)): $($result.Error), skip optional service"
    } else {
      Summary-AddWarn "failed to package $Repo ($($result.Path)), skip optional service"
    }
    return $true
  }

  if ($null -eq $result.Path) {
    Summary-AddFail "failed to package $Repo (no package script found)"
  } elseif ($result.ContainsKey('Error')) {
    Summary-AddFail "failed to package $Repo ($($result.Path)): $($result.Error)"
  } else {
    Summary-AddFail "failed to package $Repo ($($result.Path))"
  }
  return $false
}

function Run-PackageAllRepos {
  $failed = $false
  foreach ($repo in $RepoNames) {
    if (-not (Invoke-PackageForRepo -Repo $repo)) { $failed = $true }
  }
  return (-not $failed)
}

function Move-PackagedArtifactsForRepo {
  param([string]$Repo)

  try {
    $packagedDir = Get-RepoPackagedOutputDir $Repo
  } catch {
    Summary-AddFail "unsupported repo for move: $Repo"
    return $false
  }

  $releaseDir = Get-RepoReleaseDir $Repo

  if (-not (Test-Path -LiteralPath $packagedDir)) {
    Summary-AddFail "packaged output missing: $packagedDir"
    return $false
  }

  if (Test-Path -LiteralPath $releaseDir) {
    Remove-Item -LiteralPath $releaseDir -Recurse -Force
  }

  New-Item -ItemType Directory -Path (Split-Path -Parent $releaseDir) -Force | Out-Null

  try {
    Move-Item -LiteralPath $packagedDir -Destination $releaseDir
    Summary-AddOk "moved package output to release: $Repo"
    return $true
  } catch {
    Summary-AddFail "failed to move package output for $Repo"
    return $false
  }
}

function Move-PackagedArtifactsAll {
  $failed = $false
  foreach ($repo in @('term-webclient', 'zenmind-app-server')) {
    if (-not (Move-PackagedArtifactsForRepo -Repo $repo)) { $failed = $true }
  }

  $runnerPackagedDir = Get-RepoPackagedOutputDir 'agent-platform-runner'
  $runnerReleaseDir = Get-RepoReleaseDir 'agent-platform-runner'
  if (Test-Path -LiteralPath $runnerPackagedDir) {
    if (Test-Path -LiteralPath $runnerReleaseDir) {
      Remove-Item -LiteralPath $runnerReleaseDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $runnerReleaseDir) -Force | Out-Null
    try {
      Move-Item -LiteralPath $runnerPackagedDir -Destination $runnerReleaseDir
      Summary-AddOk 'moved package output to release: agent-platform-runner'
    } catch {
      Summary-AddWarn 'failed to move package output for optional service: agent-platform-runner'
    }
  } else {
    Summary-AddWarn "packaged output missing for optional service, skip move: $runnerPackagedDir"
  }

  return (-not $failed)
}

function Validate-ReleaseArtifacts {
  param([string]$Repo)

  $releaseRepo = Get-RepoReleaseDir $Repo
  $required = switch ($Repo) {
    'term-webclient' {
      @(
        (Join-Path $releaseRepo 'backend/app.jar'),
        (Join-Path $releaseRepo 'frontend/server.js'),
        (Join-Path $releaseRepo 'frontend/dist/index.html')
      )
    }
    'zenmind-app-server' {
      @(
        (Join-Path $releaseRepo 'docker-compose.yml'),
        (Join-Path $releaseRepo 'backend/app.jar'),
        (Join-Path $releaseRepo 'frontend/dist/index.html')
      )
    }
    'agent-platform-runner' {
      @((Join-Path $releaseRepo 'app.jar'))
    }
    default { @() }
  }

  $missing = @()
  foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath $file)) {
      $missing += $file
    }
  }

  if ($Repo -eq 'agent-platform-runner') {
    $startCandidates = @('start.ps1', 'start.bat', 'start.cmd') | ForEach-Object { Join-Path $releaseRepo $_ }
    $hasStartScript = $false
    foreach ($startScript in $startCandidates) {
      if (Test-Path -LiteralPath $startScript) {
        $hasStartScript = $true
        break
      }
    }
    if (-not $hasStartScript) {
      $missing += "any of: $($startCandidates -join ', ')"
    }
  }

  if ($Repo -eq 'term-webclient') {
    $startCandidates = @('start.ps1', 'start.bat', 'start.cmd') | ForEach-Object { Join-Path $releaseRepo "release-scripts/windows/$_" }
    $hasStartScript = $false
    foreach ($startScript in $startCandidates) {
      if (Test-Path -LiteralPath $startScript) {
        $hasStartScript = $true
        break
      }
    }
    if (-not $hasStartScript) {
      $missing += "any of: $($startCandidates -join ', ')"
    }
  }

  if ($missing.Count -gt 0) {
    if ($Repo -eq 'agent-platform-runner') {
      Summary-AddWarn "$Repo release incomplete, skip optional service: $($missing -join ', ')"
      return $true
    }
    Summary-AddFail "$Repo release incomplete, missing: $($missing -join ', ')"
    return $false
  }
  return $true
}

function Start-TermWebclient {
  $sourceRepo = Get-RepoSourceDir 'term-webclient'
  $releaseRepo = Get-RepoReleaseDir 'term-webclient'
  $backendPid = Join-Path $releaseRepo 'run/backend.pid'
  $frontendPid = Join-Path $releaseRepo 'run/frontend.pid'

  if (-not (Test-Path -LiteralPath $sourceRepo)) {
    Summary-AddFail "term-webclient source repo missing: $sourceRepo"
    return $false
  }

  if (-not (Validate-ReleaseArtifacts -Repo 'term-webclient')) { return $false }

  if ((Setup-ProcessRunningFromPidFile -PidFile $backendPid) -and (Setup-ProcessRunningFromPidFile -PidFile $frontendPid)) {
    Summary-AddOk 'term-webclient already running'
    return $true
  }

  $result = Invoke-RepoScript -RepoDir $releaseRepo -Candidates @('release-scripts/windows/start.ps1', 'release-scripts/windows/start.bat', 'release-scripts/windows/start.cmd')
  if (-not $result.Ok) {
    $result = Invoke-RepoScript -RepoDir $sourceRepo -Candidates @('release-scripts/windows/start.ps1', 'release-scripts/windows/start.bat', 'release-scripts/windows/start.cmd')
  }

  if ($result.Ok) {
    Summary-AddOk 'start command completed: term-webclient'
    return $true
  }

  Summary-AddFail 'failed to start term-webclient'
  return $false
}

function Start-ZenmindAppServer {
  $sourceRepo = Get-RepoSourceDir 'zenmind-app-server'
  $releaseRepo = Get-RepoReleaseDir 'zenmind-app-server'

  if (-not (Test-Path -LiteralPath $sourceRepo)) {
    Summary-AddFail "zenmind-app-server source repo missing: $sourceRepo"
    return $false
  }

  if (-not (Validate-ReleaseArtifacts -Repo 'zenmind-app-server')) { return $false }

  if (-not (Setup-DockerDaemonRunning)) {
    Summary-AddFail 'docker is installed but daemon is not running; start Docker Desktop before starting zenmind-app-server'
    return $false
  }

  Push-Location $releaseRepo
  try {
    & docker compose up -d --build
    if ($LASTEXITCODE -eq 0) {
      Summary-AddOk 'start command completed: zenmind-app-server'
      return $true
    }
    Summary-AddFail 'failed to start zenmind-app-server'
    return $false
  } finally {
    Pop-Location
  }
}

function Start-AgentPlatformRunner {
  $sourceRepo = Get-RepoSourceDir 'agent-platform-runner'
  $releaseRepo = Get-RepoReleaseDir 'agent-platform-runner'
  $pidFile = Join-Path $releaseRepo 'app.pid'

  if (-not (Test-Path -LiteralPath $sourceRepo)) {
    Summary-AddWarn "agent-platform-runner source repo missing, skip optional service: $sourceRepo"
    return $true
  }

  if (-not (Validate-ReleaseArtifacts -Repo 'agent-platform-runner')) { return $false }

  if (Setup-ProcessRunningFromPidFile -PidFile $pidFile) {
    Summary-AddOk 'agent-platform-runner already running'
    return $true
  }

  $result = Invoke-RepoScript -RepoDir $releaseRepo -Candidates @('start.ps1', 'start.bat', 'start.cmd') -Arguments @('-d')
  if (-not $result.Ok) {
    $result = Invoke-RepoScript -RepoDir $sourceRepo -Candidates @('release-scripts/windows/start-local.ps1', 'release-scripts/windows/start-local.bat', 'release-scripts/windows/start-local.cmd') -Arguments @('-d')
  }

  if ($result.Ok) {
    Summary-AddOk 'start command completed: agent-platform-runner'
    return $true
  }

  Summary-AddWarn 'failed to start agent-platform-runner, skip optional service'
  return $true
}

function Stop-AgentPlatformRunner {
  $sourceRepo = Get-RepoSourceDir 'agent-platform-runner'
  $releaseRepo = Get-RepoReleaseDir 'agent-platform-runner'
  $pidFile = Join-Path $releaseRepo 'app.pid'

  if (-not (Test-Path -LiteralPath $sourceRepo)) {
    Summary-AddWarn "agent-platform-runner source repo not found, skip stop"
    return $true
  }

  $result = Invoke-RepoScript -RepoDir $releaseRepo -Candidates @('stop.ps1', 'stop.bat', 'stop.cmd')
  if (-not $result.Ok) {
    $result = Invoke-RepoScript -RepoDir $sourceRepo -Candidates @('release-scripts/windows/stop-local.ps1', 'release-scripts/windows/stop-local.bat', 'release-scripts/windows/stop-local.cmd')
  }

  if ($result.Ok) {
    Summary-AddOk 'stop command completed: agent-platform-runner'
    return $true
  }

  if (Setup-StopProcessByPidFile -PidFile $pidFile) {
    Summary-AddOk 'stopped by pid: agent-platform-runner'
    return $true
  }

  Summary-AddWarn 'agent-platform-runner is not running'
  return $true
}

function Stop-ZenmindAppServer {
  $sourceRepo = Get-RepoSourceDir 'zenmind-app-server'
  $releaseRepo = Get-RepoReleaseDir 'zenmind-app-server'

  if (-not (Test-Path -LiteralPath $sourceRepo)) {
    Summary-AddWarn "zenmind-app-server source repo not found, skip stop"
    return $true
  }

  if (-not (Test-Path -LiteralPath $releaseRepo)) {
    Summary-AddWarn 'zenmind-app-server release dir not found, skip stop'
    return $true
  }

  if (-not (Test-SetupCommand -Command 'docker')) {
    Summary-AddWarn 'docker not installed, skip stop: zenmind-app-server'
    return $true
  }

  if (-not (Setup-DockerDaemonRunning)) {
    Summary-AddWarn 'docker daemon not running, skip stop: zenmind-app-server'
    return $true
  }

  Push-Location $releaseRepo
  try {
    & docker compose stop
    if ($LASTEXITCODE -eq 0) {
      Summary-AddOk 'stop command completed: zenmind-app-server'
      return $true
    }
    Summary-AddFail 'failed to stop zenmind-app-server'
    return $false
  } finally {
    Pop-Location
  }
}

function Stop-TermWebclient {
  $sourceRepo = Get-RepoSourceDir 'term-webclient'
  $releaseRepo = Get-RepoReleaseDir 'term-webclient'
  $backendPid = Join-Path $releaseRepo 'run/backend.pid'
  $frontendPid = Join-Path $releaseRepo 'run/frontend.pid'

  if (-not (Test-Path -LiteralPath $sourceRepo)) {
    Summary-AddWarn 'term-webclient source repo not found, skip stop'
    return $true
  }

  $result = Invoke-RepoScript -RepoDir $releaseRepo -Candidates @('release-scripts/windows/stop.ps1', 'release-scripts/windows/stop.bat', 'release-scripts/windows/stop.cmd')
  if (-not $result.Ok) {
    $result = Invoke-RepoScript -RepoDir $sourceRepo -Candidates @('release-scripts/windows/stop.ps1', 'release-scripts/windows/stop.bat', 'release-scripts/windows/stop.cmd')
  }

  if ($result.Ok) {
    Summary-AddOk 'stop command completed: term-webclient'
    return $true
  }

  $stoppedAny = $false
  if (Setup-StopProcessByPidFile -PidFile $backendPid) {
    Summary-AddOk 'stopped backend process by pid'
    $stoppedAny = $true
  }
  if (Setup-StopProcessByPidFile -PidFile $frontendPid) {
    Summary-AddOk 'stopped frontend process by pid'
    $stoppedAny = $true
  }

  if ($stoppedAny) { return $true }

  Summary-AddWarn 'term-webclient is not running'
  return $true
}

function Health-CheckAfterStart {
  $failed = $false

  $termRelease = Get-RepoReleaseDir 'term-webclient'
  $appRelease = Get-RepoReleaseDir 'zenmind-app-server'
  $agentRelease = Get-RepoReleaseDir 'agent-platform-runner'

  if ((Setup-ProcessRunningFromPidFile -PidFile (Join-Path $termRelease 'run/backend.pid')) -and
      (Setup-ProcessRunningFromPidFile -PidFile (Join-Path $termRelease 'run/frontend.pid'))) {
    Summary-AddOk 'health check passed: term-webclient backend/frontend pids alive'
  } else {
    Summary-AddFail 'health check failed: term-webclient process not fully running'
    $failed = $true
  }

  if ((Test-Path -LiteralPath $appRelease) -and (Setup-DockerDaemonRunning)) {
    Push-Location $appRelease
    try {
      $runningServices = (& docker compose ps --status running --services 2>$null)
    } finally {
      Pop-Location
    }

    if (-not [string]::IsNullOrWhiteSpace(($runningServices | Out-String).Trim())) {
      Summary-AddOk 'health check passed: zenmind-app-server has running compose services'
    } else {
      Summary-AddFail 'health check failed: zenmind-app-server has no running compose service'
      $failed = $true
    }
  } else {
    Summary-AddFail 'health check failed: zenmind-app-server compose status unavailable'
    $failed = $true
  }

  if (Setup-ProcessRunningFromPidFile -PidFile (Join-Path $agentRelease 'app.pid')) {
    Summary-AddOk 'health check passed: agent-platform-runner pid alive'
  } else {
    Summary-AddWarn 'health check skipped: agent-platform-runner not running (optional service)'
  }

  return (-not $failed)
}

function Run-FirstInstall {
  $failed = $false

  Ensure-WorkspaceLayout
  Setup-Log "workspace base dir: $BaseDir"
  Setup-Log "workspace source dir: $(Get-WorkspaceSourceDir)"
  Setup-Log "workspace release dir: $(Get-WorkspaceReleaseDir)"

  if (Setup-RequireCommand -Command 'git') {
    Summary-AddOk 'git available'
  } else {
    Summary-AddFail 'git is required before first-install'
    return $false
  }

  Setup-ShowFirstInstallPasswordNotice

  foreach ($repo in $RepoNames) {
    if (-not (Refresh-RepoByClone -Repo $repo)) { $failed = $true }
  }

  if (-not (Check-RequiredRepoFiles)) { $failed = $true }
  if (-not (Run-PackageAllRepos)) { $failed = $true }
  if (-not (Move-PackagedArtifactsAll)) { $failed = $true }
  if (-not (Copy-ExampleConfigs -Mode 'overwrite')) { $failed = $true }
  if (-not (Configure-PasswordHashes)) { $failed = $true }

  Summary-AddWarn 'security reminder: replace default passwords and review sensitive release config values'

  if (-not $failed) {
    Summary-AddOk 'first-install completed'
    return $true
  }
  return $false
}

function Run-Update {
  $failed = $false

  Ensure-WorkspaceLayout
  Setup-Log 'update mode: refresh clone + package + move'

  if (Setup-RequireCommand -Command 'git') {
    Summary-AddOk 'git available'
  } else {
    Summary-AddFail 'git is required before update'
    return $false
  }

  if (-not (Backup-UpdateConfigs)) { $failed = $true }

  foreach ($repo in $RepoNames) {
    if (-not (Refresh-RepoByClone -Repo $repo)) { $failed = $true }
  }

  if (-not (Check-RequiredRepoFiles)) { $failed = $true }
  if (-not (Run-PackageAllRepos)) { $failed = $true }
  if (-not (Move-PackagedArtifactsAll)) { $failed = $true }
  if (-not (Restore-UpdateConfigs)) { $failed = $true }
  if (-not (Copy-ExampleConfigs -Mode 'if-missing')) { $failed = $true }

  Cleanup-UpdateConfigBackup

  if (-not $failed) {
    Summary-AddOk 'update completed'
    return $true
  }
  return $false
}

function Run-Start {
  if (-not (Check-RuntimeEnvironmentBeforeStart)) {
    return $false
  }

  $failed = $false
  if (-not (Start-TermWebclient)) { $failed = $true }
  if (-not (Start-ZenmindAppServer)) { $failed = $true }
  if (-not (Start-AgentPlatformRunner)) { $failed = $true }
  if (-not (Health-CheckAfterStart)) { $failed = $true }

  if (-not $failed) {
    Summary-AddOk 'start completed'
    return $true
  }
  return $false
}

function Run-Stop {
  $failed = $false
  if (-not (Stop-AgentPlatformRunner)) { $failed = $true }
  if (-not (Stop-ZenmindAppServer)) { $failed = $true }
  if (-not (Stop-TermWebclient)) { $failed = $true }

  if (-not $failed) {
    Summary-AddOk 'stop completed'
    return $true
  }
  return $false
}

function Run-ResetPasswordHash {
  $termRelease = Get-RepoReleaseDir 'term-webclient'
  $appRelease = Get-RepoReleaseDir 'zenmind-app-server'
  if (-not (Test-Path -LiteralPath $termRelease) -or -not (Test-Path -LiteralPath $appRelease)) {
    Summary-AddFail "release dirs missing, run first-install/update first: $termRelease, $appRelease"
    return $false
  }

  if (-not (Configure-PasswordHashes)) {
    return $false
  }

  Summary-AddOk 'reset-password-hash completed'
  return $true
}

function Dispatch-Action {
  param([string]$RequestedAction)

  Summary-Reset
  $status = $true

  switch ($RequestedAction) {
    'precheck' { if (-not (Run-Precheck)) { $status = $false }; Print-Summary 'precheck' }
    'first-install' { if (-not (Run-FirstInstall)) { $status = $false }; Print-Summary 'first-install' }
    'update' { if (-not (Run-Update)) { $status = $false }; Print-Summary 'update' }
    'start' { if (-not (Run-Start)) { $status = $false }; Print-Summary 'start' }
    'stop' { if (-not (Run-Stop)) { $status = $false }; Print-Summary 'stop' }
    'reset-password-hash' { if (-not (Run-ResetPasswordHash)) { $status = $false }; Print-Summary 'reset-password-hash' }
    default {
      Summary-AddFail "unsupported action: $RequestedAction"
      Print-Summary 'unknown'
      $status = $false
    }
  }

  return $status
}

function Show-Menu {
  while ($true) {
    Write-Host ''
    @'
================ Setup Menu ================
1) 环境检测
2) 首次安装
3) 更新
4) 启动
5) 停止
6) 重置密码哈希
0) 退出
===========================================
'@ | Write-Host

    $choice = Read-Host '请输入数字 [0-6]'
    switch ($choice) {
      '1' { [void](Dispatch-Action -RequestedAction 'precheck') }
      '2' { [void](Dispatch-Action -RequestedAction 'first-install') }
      '3' { [void](Dispatch-Action -RequestedAction 'update') }
      '4' { [void](Dispatch-Action -RequestedAction 'start') }
      '5' { [void](Dispatch-Action -RequestedAction 'stop') }
      '6' { [void](Dispatch-Action -RequestedAction 'reset-password-hash') }
      '0' {
        Setup-Log 'exit setup menu'
        return
      }
      default {
        Setup-Warn "invalid choice: $choice (allowed: 0-6)"
      }
    }
  }
}

if (-not [string]::IsNullOrWhiteSpace($Action)) {
  if (Dispatch-Action -RequestedAction $Action) {
    exit 0
  }
  exit 1
}

Show-Menu
