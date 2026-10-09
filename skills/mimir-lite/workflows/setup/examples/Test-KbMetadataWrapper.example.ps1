#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to validate the contract of Get-KbMetadata.ps1.

.DESCRIPTION
Runs the shared script `Test-MimirKbMetadataWrapper.ps1` to check that the local
wrapper `Get-KbMetadata.ps1` exposes the required fields that exist in
`kb-source-metadata.md`: `last_xpz_materialization_run_at`, `kb_name` and
`source_guid`. It also validates that the critical KB identity fields
(`kbGuid`, `kbName`, `versionGuid`, `versionName`) are complete in the local
metadata before declaring the wrapper OK.

This wrapper should be used in setup audits to prevent a `Get-KbMetadata.ps1`
that only works at parse level from being classified as EQUIVALENT when it
fails to expose fields that exist in the local metadata.

.PARAMETER MetadataPath
Optional path to kb-source-metadata.md. When omitted, uses the file at the
root of the KB workspace.

.PARAMETER MetadataWrapperPath
Optional path to Get-KbMetadata.ps1. When omitted, uses the local wrapper in
the same `scripts` folder.

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbMetadataWrapper.ps1"

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbMetadataWrapper.ps1" -MetadataPath "<WorkspaceRoot>/kb-source-metadata.md" -MetadataWrapperPath "<WorkspaceRoot>/scripts/Get-KbMetadata.ps1"
#>

param(
    [string]$MetadataPath,

    [string]$MetadataWrapperPath,

    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $MetadataPath) {
    $MetadataPath = Join-Path $repoRoot "kb-source-metadata.md"
}

if (-not $MetadataWrapperPath) {
    $MetadataWrapperPath = Join-Path $PSScriptRoot "Get-KbMetadata.ps1"
}

$enginePath = Join-Path $SharedSkillsRoot "skills\mimir-lite\scripts\Test-MimirKbMetadataWrapper.ps1"
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Shared metadata wrapper test not found: $enginePath"
}

& $enginePath -MetadataPath $MetadataPath -WrapperPath $MetadataWrapperPath
