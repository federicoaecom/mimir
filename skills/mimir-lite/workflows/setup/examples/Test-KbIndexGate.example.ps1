#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper for the KbIntelligence index gate of a KB workspace.

.DESCRIPTION
Thin wrapper: delegates all logic to the shared engine
`skills/mimir-lite/scripts/Test-MimirKbIndexGate.ps1` of the Mimir Lite checkout,
injecting the local paths and forwarding -AsJson. Symmetric to the setup audit
wrapper (which delegates to Test-MimirSetupAudit.ps1).

Output contract inherited from the engine:
- Default (text): emits GATE_OK on success, throws `BLOCK: <reason>` on a block.
  Backward compatible with grep-based consumption (Test-MimirSetupAudit / agents).
- -AsJson: { status: OK|BLOCK, reason, extractor_signature_*, ... }. Under -AsJson
  it never throws; a block becomes { status: BLOCK, reason } + exit 1. Meant for
  callers that need the structured contract.

`SharedSkillsRoot` defaults to the shared checkout path recorded when this
wrapper was created; when the KB uses other local names for the Query/Structure
wrappers, pass them in the parameters.

It must be the single execution point of the index gate of the KB workspace.

.PARAMETER QueryWrapperPath
Path of the local index query wrapper (default: Query-KbIntelligence.ps1
in the same folder as this wrapper).

.PARAMETER StructureWrapperPath
Path of the local structure check wrapper (default: Test-KbStructure.ps1
in the same folder as this wrapper).

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout (engine under `skills/mimir-lite/scripts/`).

.PARAMETER AsJson
Forwards the structured contract mode to the shared engine.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbIndexGate.ps1" -AsJson
#>

param(
    [string]$QueryWrapperPath,
    [string]$StructureWrapperPath,
    [string]$SharedSkillsRoot = 'C:\path\to\mimir-lite',
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $QueryWrapperPath) { $QueryWrapperPath = Join-Path $PSScriptRoot 'Query-KbIntelligence.ps1' }
if (-not $StructureWrapperPath) { $StructureWrapperPath = Join-Path $PSScriptRoot 'Test-KbStructure.ps1' }

$engine = Join-Path $SharedSkillsRoot (Join-Path 'skills\mimir-lite\scripts' 'Test-MimirKbIndexGate.ps1')
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    throw "BLOCK: shared index gate engine missing: $engine"
}

$forward = @{
    RepoRoot             = $repoRoot
    QueryWrapperPath     = $QueryWrapperPath
    StructureWrapperPath = $StructureWrapperPath
}
if ($AsJson) { $forward['AsJson'] = $true }

$global:LASTEXITCODE = $null
& $engine @forward
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
