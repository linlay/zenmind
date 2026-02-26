Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Setup-Log {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host "[setup-win] $Message"
}

function Setup-Warn {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Warning "[setup-win] $Message"
}

function Setup-Err {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host "[setup-win] ERROR: $Message"
}

function Test-SetupCommand {
  param([Parameter(Mandatory = $true)][string]$Command)
  return [bool](Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

function Setup-RequireCommand {
  param([Parameter(Mandatory = $true)][string]$Command)
  if (-not (Test-SetupCommand -Command $Command)) {
    Setup-Err "missing required command: $Command"
    return $false
  }
  return $true
}

function ConvertTo-SetupVersion {
  param([Parameter(Mandatory = $true)][string]$Version)
  $clean = $Version.Trim()
  if ([string]::IsNullOrWhiteSpace($clean)) {
    return $null
  }
  if ($clean.StartsWith('v')) {
    $clean = $clean.Substring(1)
  }
  $parts = $clean.Split('.')
  if ($parts.Length -eq 1) {
    $clean = "$clean.0.0"
  } elseif ($parts.Length -eq 2) {
    $clean = "$clean.0"
  }
  try {
    return [Version]$clean
  } catch {
    return $null
  }
}

function Setup-SemverGe {
  param(
    [Parameter(Mandatory = $true)][string]$Actual,
    [Parameter(Mandatory = $true)][string]$Required
  )
  $actualVersion = ConvertTo-SetupVersion -Version $Actual
  $requiredVersion = ConvertTo-SetupVersion -Version $Required
  if ($null -eq $actualVersion -or $null -eq $requiredVersion) {
    return $false
  }
  return ($actualVersion -ge $requiredVersion)
}

function Setup-CheckNode20 {
  if (-not (Test-SetupCommand -Command 'node')) {
    Setup-Err 'Node.js not found (required: 20+)'
    return $false
  }

  $version = (& node -v).TrimStart('v')
  if (-not (Setup-SemverGe -Actual $version -Required '20.0.0')) {
    Setup-Err "Node.js version too low: $version (required: 20+)"
    return $false
  }

  Setup-Log "Node.js OK: v$version"
  return $true
}

function Setup-CheckNpm {
  if (-not (Test-SetupCommand -Command 'npm')) {
    Setup-Err 'npm not found'
    return $false
  }

  $version = (& npm -v)
  Setup-Log "npm OK: $version"
  return $true
}

function Setup-CheckMaven39 {
  if (-not (Test-SetupCommand -Command 'mvn')) {
    Setup-Err 'Maven not found (required: 3.9+)'
    return $false
  }

  $mvnInfo = & mvn -v
  $versionLine = $mvnInfo | Where-Object { $_ -match 'Apache Maven' } | Select-Object -First 1
  if ([string]::IsNullOrWhiteSpace($versionLine)) {
    Setup-Err 'unable to parse Maven version'
    return $false
  }

  $match = [regex]::Match($versionLine, 'Apache Maven\s+([0-9]+(?:\.[0-9]+){1,2})')
  if (-not $match.Success) {
    Setup-Err "unable to parse Maven version from: $versionLine"
    return $false
  }

  $version = $match.Groups[1].Value
  if (-not (Setup-SemverGe -Actual $version -Required '3.9.0')) {
    Setup-Err "Maven version too low: $version (required: 3.9+)"
    return $false
  }

  Setup-Log "Maven OK: $version"
  return $true
}

function Setup-CheckJava21 {
  if (-not (Test-SetupCommand -Command 'java')) {
    Setup-Err 'Java not found (required: JDK 21+)'
    return $false
  }

  $javaVersionOutput = (& java -version) 2>&1
  $raw = ($javaVersionOutput | Select-Object -First 1)
  $match = [regex]::Match($raw, '"([0-9]+(?:\.[0-9]+){0,2})"')
  if (-not $match.Success) {
    Setup-Err "unable to parse Java version from: $raw"
    return $false
  }

  $version = $match.Groups[1].Value
  $major = [int](($version -split '\.')[0])
  if ($major -lt 21) {
    Setup-Err "Java version too low: $version (required: 21+)"
    return $false
  }

  Setup-Log "Java OK: $version"
  return $true
}

function Setup-DockerDaemonRunning {
  if (-not (Test-SetupCommand -Command 'docker')) {
    return $false
  }
  & docker info *> $null
  return ($LASTEXITCODE -eq 0)
}

function Setup-CheckOptionalTools {
  if (Test-SetupCommand -Command 'htpasswd') {
    Setup-Log 'Optional tool OK: htpasswd'
  } else {
    Setup-Warn 'optional tool missing: htpasswd'
  }

  if (Test-SetupCommand -Command 'openssl') {
    Setup-Log 'Optional tool OK: openssl'
  } else {
    Setup-Warn 'optional tool missing: openssl'
  }

  if ((Test-SetupCommand -Command 'python') -or (Test-SetupCommand -Command 'python3')) {
    Setup-Log 'Optional tool OK: python'
  } else {
    Setup-Warn 'optional tool missing: python'
  }
}

function Setup-BcryptHint {
  Setup-Log "bcrypt command (Git Bash): htpasswd -nbBC 10 '' 'your-password' | cut -d: -f2"
  Setup-Log "bcrypt command (PowerShell): (htpasswd -nbBC 10 '' 'your-password' | Select-String ':').ToString().Split(':',2)[1].Trim()"
  Setup-Log "fallback: use python bcrypt module on Windows"
}

function Setup-GenerateBcrypt {
  param([Parameter(Mandatory = $true)][string]$PlainPassword)

  if (Test-SetupCommand -Command 'htpasswd') {
    Setup-Log "[bcrypt] method: htpasswd"
    Setup-Log "[bcrypt] command: htpasswd -nbBC 10 '' '<password>'"
    $hashLines = & htpasswd -nbBC 10 '' $PlainPassword
    Setup-Log "[bcrypt] raw output: $($hashLines -join '|')"
    if ($LASTEXITCODE -eq 0 -and $null -ne $hashLines) {
      foreach ($line in @($hashLines)) {
        if ($line -is [string] -and $line.StartsWith(':')) {
          $candidate = $line.Substring(1).Trim()
          Setup-Log "[bcrypt] after extract (StartsWith ':'): $candidate"
          if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            Setup-Log "[bcrypt] final hash: $candidate"
            return $candidate
          }
        }
      }

      foreach ($line in @($hashLines)) {
        if ($line -is [string]) {
          $idx = $line.IndexOf(':')
          if ($idx -ge 0 -and $idx + 1 -lt $line.Length) {
            $candidate = $line.Substring($idx + 1).Trim()
            Setup-Log "[bcrypt] after extract (IndexOf ':'): $candidate"
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
              Setup-Log "[bcrypt] final hash: $candidate"
              return $candidate
            }
          }
        }
      }
    }
  }

  $pythonCmd = $null
  if (Test-SetupCommand -Command 'python') {
    $pythonCmd = 'python'
  } elseif (Test-SetupCommand -Command 'python3') {
    $pythonCmd = 'python3'
  }

  if ($null -ne $pythonCmd) {
    & $pythonCmd -c 'import bcrypt' *> $null
    if ($LASTEXITCODE -eq 0) {
      Setup-Log "[bcrypt] method: $pythonCmd bcrypt"
      $result = & $pythonCmd -c 'import bcrypt,sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(10)).decode())' $PlainPassword
      Setup-Log "[bcrypt] python raw: $result"
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($result)) {
        $trimmed = $result.Trim()
        Setup-Log "[bcrypt] final hash: $trimmed"
        return $trimmed
      }
    }
  }

  throw 'unable to generate bcrypt hash (need htpasswd, or python with bcrypt module)'
}

function Setup-PromptPassword {
  param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$DefaultPassword
  )

  $nonInteractive = ($env:SETUP_NON_INTERACTIVE -eq '1')
  if ($nonInteractive) {
    Setup-Warn "non-interactive mode, use default password for '$Prompt'"
    return $DefaultPassword
  }

  try {
    $secure = Read-Host -Prompt "[setup-win] $Prompt [default: $DefaultPassword]" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
      $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
    if ([string]::IsNullOrWhiteSpace($plain)) {
      return $DefaultPassword
    }
    return $plain
  } catch {
    Setup-Warn "stdin is not interactive, use default password for '$Prompt'"
    return $DefaultPassword
  }
}

function Setup-ShowFirstInstallPasswordNotice {
  $nonInteractive = ($env:SETUP_NON_INTERACTIVE -eq '1')
  if ($nonInteractive) {
    Setup-Log 'non-interactive mode: skip enter-to-continue password notice'
    return
  }

  @'
[setup-win] 首次安装将要求输入 3 组密码（后续会自动加密写入配置）:
[setup-win] 1) term-webclient: AUTH_PASSWORD_HASH_BCRYPT 对应明文密码
[setup-win] 2) zenmind-app-server: AUTH_ADMIN_PASSWORD_BCRYPT 对应明文密码
[setup-win] 3) zenmind-app-server: AUTH_APP_MASTER_PASSWORD_BCRYPT 对应明文密码
[setup-win] First install will prompt for 3 passwords (hashed and written to config).
'@ | Write-Host
  [void](Read-Host '[setup-win] 按回车继续 / Press Enter to continue')
}

function Setup-EnsureEnvFile {
  param([Parameter(Mandatory = $true)][string]$EnvFile)
  $dir = Split-Path -Parent $EnvFile
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  if (-not (Test-Path -LiteralPath $EnvFile)) {
    New-Item -ItemType File -Path $EnvFile -Force | Out-Null
  }
}

function Setup-UpsertEnvVar {
  param(
    [Parameter(Mandatory = $true)][string]$EnvFile,
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Value
  )

  Setup-EnsureEnvFile -EnvFile $EnvFile
  $lines = Get-Content -LiteralPath $EnvFile -ErrorAction SilentlyContinue
  $output = New-Object System.Collections.Generic.List[string]
  $replaced = $false

  foreach ($line in $lines) {
    if ($line -match "^$([regex]::Escape($Key))=") {
      if (-not $replaced) {
        $output.Add("$Key=$Value")
        $replaced = $true
      }
      continue
    }
    $output.Add($line)
  }

  if (-not $replaced) {
    $output.Add("$Key=$Value")
  }

  Set-Content -LiteralPath $EnvFile -Value $output -Encoding UTF8
}

function Setup-SingleQuoteEnvValue {
  param([Parameter(Mandatory = $true)][string]$Value)
  # Keep literal content safe for shell-style .env loading.
  $escaped = $Value -replace "'", "'\\''"
  return "'$escaped'"
}

function Setup-ProcessRunningFromPidFile {
  param([Parameter(Mandatory = $true)][string]$PidFile)

  if (-not (Test-Path -LiteralPath $PidFile)) {
    return $false
  }

  $pidRaw = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($pidRaw)) {
    return $false
  }

  $pidValue = 0
  if (-not [int]::TryParse($pidRaw, [ref]$pidValue)) {
    return $false
  }

  return [bool](Get-Process -Id $pidValue -ErrorAction SilentlyContinue)
}

function Setup-Timestamp {
  return (Get-Date -Format 'yyyyMMddHHmmss')
}

function Setup-BackupFile {
  param([Parameter(Mandatory = $true)][string]$FilePath)

  if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "cannot backup missing file: $FilePath"
  }

  $backupPath = "$FilePath.bak.$(Setup-Timestamp)"
  Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force
  return $backupPath
}

function Setup-StopProcessByPidFile {
  param([Parameter(Mandatory = $true)][string]$PidFile)

  if (-not (Test-Path -LiteralPath $PidFile)) {
    return $false
  }

  $pidRaw = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
  $pidValue = 0
  if (-not [int]::TryParse($pidRaw, [ref]$pidValue)) {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    return $false
  }

  $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
  if ($null -eq $process) {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    return $false
  }

  Stop-Process -Id $pidValue -ErrorAction SilentlyContinue
  for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Id $pidValue -ErrorAction SilentlyContinue)) {
      Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
      return $true
    }
  }

  Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
  return $true
}
