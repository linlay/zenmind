[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
$entryScript = Join-Path $rootDir 'setup-windows.ps1'

& $entryScript @args
exit $LASTEXITCODE
