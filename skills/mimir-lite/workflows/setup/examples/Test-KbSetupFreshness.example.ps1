#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to check the freshness of the KB workspace setup against the XPZ setup contract.

.DESCRIPTION
Delegates to the shared engine Test-MimirSetupFreshness.ps1 with the fixed paths of this KB workspace.
Returns GATE_ONLY when the audited contract signature in kb-source-metadata.md matches
the current signature of the setup workflow; returns AUDIT_REQUIRED with a reason otherwise.

Used as the mandatory first action of the setup workflow's PRECONDITION when invoked
by the global trigger (when the user does not explicitly ask for setup, an update or an audit).

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbSetupFreshness.ps1"
#>

param(
    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite",

    [string]$PowerShellRuntimeWrapperPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$KbWorkspaceRoot = Split-Path -Parent $PSScriptRoot
$PowerShellRuntimeWrapperPath = if ($PowerShellRuntimeWrapperPath) {
    $PowerShellRuntimeWrapperPath
} else {
    Join-Path $PSScriptRoot 'Test-KbPowerShellRuntime.ps1'
}

if (-not (Test-Path -LiteralPath $PowerShellRuntimeWrapperPath -PathType Leaf)) {
    throw "BLOCK: PowerShell runtime wrapper missing: $PowerShellRuntimeWrapperPath"
}

$global:LASTEXITCODE = $null
& $PowerShellRuntimeWrapperPath
$runtimeCommandSucceeded = $?
$runtimeExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $runtimeExitCodeVariable -and $runtimeExitCodeVariable.Value -is [int] -and $runtimeExitCodeVariable.Value -ne 0) {
    exit $runtimeExitCodeVariable.Value
}
if (-not $runtimeCommandSucceeded) {
    exit 1
}

$enginePath = Join-Path $SharedSkillsRoot 'skills\mimir-lite\scripts\Test-MimirSetupFreshness.ps1'

if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "Engine script not found: $enginePath"
}

$global:LASTEXITCODE = $null
& $enginePath -KbWorkspaceRoot $KbWorkspaceRoot -SkillsRoot $SharedSkillsRoot
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
