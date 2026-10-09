#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper for the aggregated audit of the KB workspace.

.DESCRIPTION
Runs the shared script `Test-MimirSetupAudit.ps1` to consolidate, in
deterministic output, the main operational audit evidence of the KB
workspace: `powershell/runtime`, `sync/materialization`,
`naming/kb-objects`, `index/gate`, `index/semantics`, `metadata wrapper`,
`declarative/timestamps`, `wrappers/inventory` and
`suggested_operational_state`. The `naming/kb-objects` dimension delegates
to the local wrapper `Test-KbObjectsXmlNaming.ps1` when available.

This wrapper does not replace the specific gates. It only centralizes their
execution for handoff and a short diagnosis in update mode.

.PARAMETER KbRoot
Optional path to the root of the KB workspace.
When omitted, uses the parent folder of `scripts`.

.PARAMETER GateWrapperPath
Optional path to `Test-KbIndexGate.ps1`.

.PARAMETER MetadataWrapperTestPath
Optional path to `Test-KbMetadataWrapper.ps1`.

.PARAMETER PowerShellRuntimeWrapperPath
Optional path to `Test-KbPowerShellRuntime.ps1`.

.PARAMETER NamingWrapperPath
Optional path to `Test-KbObjectsXmlNaming.ps1`.

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout.

.PARAMETER AsJson
Forwards the structured contract to the engine (`Test-MimirSetupAudit.ps1 -AsJson`)
for callers that need it. Without the switch, the text output (default) is
preserved for existing consumers.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbSetupAudit.ps1"

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbSetupAudit.ps1" -KbRoot "<WorkspaceRoot>"
#>

param(
    [string]$KbRoot,

    [string]$GateWrapperPath,

    [string]$MetadataWrapperTestPath,

    [string]$PowerShellRuntimeWrapperPath,

    [string]$NamingWrapperPath,

    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite",

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $KbRoot) {
    $KbRoot = Split-Path -Parent $PSScriptRoot
}

if (-not $GateWrapperPath) {
    $GateWrapperPath = Join-Path $PSScriptRoot 'Test-KbIndexGate.ps1'
}

if (-not $MetadataWrapperTestPath) {
    $MetadataWrapperTestPath = Join-Path $PSScriptRoot 'Test-KbMetadataWrapper.ps1'
}

if (-not $PowerShellRuntimeWrapperPath) {
    $PowerShellRuntimeWrapperPath = Join-Path $PSScriptRoot 'Test-KbPowerShellRuntime.ps1'
}

if (-not $NamingWrapperPath) {
    $candidate = Join-Path $PSScriptRoot 'Test-KbObjectsXmlNaming.ps1'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $NamingWrapperPath = $candidate
    }
}

$enginePath = Join-Path $SharedSkillsRoot 'skills\mimir-lite\scripts\Test-MimirSetupAudit.ps1'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Shared setup audit script not found: $enginePath"
}

$global:LASTEXITCODE = $null
& $enginePath `
    -KbRoot $KbRoot `
    -GateWrapperPath $GateWrapperPath `
    -MetadataWrapperTestPath $MetadataWrapperTestPath `
    -PowerShellRuntimeTestPath $PowerShellRuntimeWrapperPath `
    -NamingWrapperPath $NamingWrapperPath `
    -AsJson:$AsJson
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
