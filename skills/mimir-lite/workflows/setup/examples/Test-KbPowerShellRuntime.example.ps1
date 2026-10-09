<#
.SYNOPSIS
Local wrapper to validate the minimum PowerShell runtime of the KB workspace.

.DESCRIPTION
Delegates to the shared engine `Test-MimirPowerShellRuntime.ps1`.
This gate must run before any operational use of the KB workspace.
This wrapper deliberately does not use `#requires -Version 7.4`, so that it can
emit `BLOCK:` even when called from an old PowerShell host.

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbPowerShellRuntime.ps1"
#>

param(
    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$enginePath = Join-Path $SharedSkillsRoot 'skills\mimir-lite\scripts\Test-MimirPowerShellRuntime.ps1'

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Engine script not found: $enginePath"
}

$global:LASTEXITCODE = $null
& $enginePath -MinimumVersion ([version]'7.4')
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
