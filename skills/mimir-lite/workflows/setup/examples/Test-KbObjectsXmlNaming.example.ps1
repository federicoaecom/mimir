#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to audit the naming of KbObjectsXml.

.DESCRIPTION
Delegates to the shared engine `Test-MimirKbObjectsXmlNaming.ps1`.
This wrapper is read-only: it does not rename directories or change XMLs.

.PARAMETER KbRoot
Optional path to the root of the KB workspace.
When omitted, uses the parent folder of `scripts`.

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout.

.PARAMETER AsJson
Emits structured JSON.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbObjectsXmlNaming.ps1"
#>

param(
    [string]$KbRoot,

    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite",

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $KbRoot) {
    $KbRoot = Split-Path -Parent $PSScriptRoot
}

$enginePath = Join-Path $SharedSkillsRoot 'skills\mimir-lite\scripts\Test-MimirKbObjectsXmlNaming.ps1'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Shared naming audit script not found: $enginePath"
}

$global:LASTEXITCODE = $null
& $enginePath -KbWorkspaceRoot $KbRoot -AsJson:$AsJson
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
