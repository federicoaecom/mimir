#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to write last_setup_audit_run_at and setup_contract_signature_* after a successful setup audit.

.DESCRIPTION
Delegates to the shared engine Set-MimirSetupAuditTimestamp.ps1 with the fixed root of this KB workspace.
Updates last_setup_audit_run_at and setup_contract_signature_* in kb-source-metadata.md;
does not change the fields owned by the sync workflow.

Use after a full audit with a successful canonical state (setup WORKFLOW step 34) or in the
setup_ready_metadata_pending sub-state of the PRECONDITION, with explicit approval when local rules require it.

After writing, rerun Test-*KbSetupFreshness.ps1 (expect GATE_ONLY) and Test-*KbIndexGate.ps1 (GATE_OK).

.PARAMETER AuditTimestamp
Optional ISO 8601 timestamp. When omitted, the engine uses the current instant.

.PARAMETER AsJson
Forwards the JSON output of the shared engine.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Set-KbSetupAuditTimestamp.ps1"

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Set-KbSetupAuditTimestamp.ps1" -AuditTimestamp "2026-05-27T22:45:00-03:00" -AsJson
#>

param(
    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite",

    [string]$AuditTimestamp,

    [switch]$AsJson,

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

$enginePath = Join-Path $SharedSkillsRoot 'skills\mimir-lite\scripts\Set-MimirSetupAuditTimestamp.ps1'

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Engine script not found: $enginePath"
}

$params = @{
    KbWorkspaceRoot = $KbWorkspaceRoot
    SkillsRoot = $SharedSkillsRoot
}

if ($AuditTimestamp) {
    $params['AuditTimestamp'] = $AuditTimestamp
}

if ($AsJson) {
    $params['AsJson'] = $true
}

$global:LASTEXITCODE = $null
& $enginePath @params
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
