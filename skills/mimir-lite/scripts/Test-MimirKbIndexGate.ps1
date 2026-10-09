#requires -Version 7.4
<#
.SYNOPSIS
  Shared engine for the KbIntelligence index gate (the gate a KB workspace's local
  Test-*KbIndexGate.ps1 wrapper calls): validates structure, freshness, semantic
  inventory and the extractor signature of the index derived from a KB workspace.

.DESCRIPTION
  A shared engine, symmetric to Test-MimirSetupAudit.ps1: it receives the KB paths as
  parameters; the thin local wrapper only injects the paths and forwards -AsJson.

  Checks sequentially:
    1. KB workspace structure (STRUCTURE_OK via the local structure wrapper);
    2. index folder + kb-intelligence.sqlite present;
    3. local query wrapper present;
    4. index-metadata with last_index_build_run_at and inventory_validation_status;
    5. kb-source-metadata.md with last_xpz_materialization_run_at;
    6. freshness: last_index_build_run_at >= last_xpz_materialization_run_at;
    7. inventory_validation_status literally OK;
    8. extractor signature (version/hash in the SQLite metadata) against the
       current engine via GeneXusKbIntelligenceExtractorContract.ps1.

  A block reason is never empty. On a fresh workspace (no materialization
  recorded) whose only structure gap is the not-yet-built index, the reason
  starts with `first index build pending:`; Test-MimirSetupAudit reports that
  case as index/gate PENDING instead of BLOCK.

  OUTPUT CONTRACT:
    - Default (text): backward-compatible -- emits the signature lines,
      inventory_validation_status: OK and GATE_OK on success; throws an
      exception `BLOCK: <reason>` on block (consumed via GATE_OK grep by
      Test-MimirSetupAudit and by agents).
    - -AsJson: structured contract -- object { status: OK|BLOCK, reason,
      extractor_signature_version, extractor_signature_hash,
      inventory_validation_status, last_index_build_run_at,
      last_xpz_materialization_run_at }. NEVER throws under -AsJson: a block
      becomes { status: BLOCK, reason } + exit 1, for callers that need a
      structured verdict.

.PARAMETER RepoRoot
  Root of the KB workspace (default: current working directory).

.PARAMETER QueryWrapperPath
  Local index query wrapper (default: <RepoRoot>/scripts/Query-KbIntelligence.ps1).

.PARAMETER StructureWrapperPath
  Local structure-check wrapper (default: <RepoRoot>/scripts/Test-KbStructure.ps1).

.PARAMETER IndexDirName
  Name of the derived index folder (default: KbIntelligence).

.PARAMETER MetadataFileName
  Name of the materialization metadata file (default: kb-source-metadata.md).

.PARAMETER ExtractorContractPath
  Path of the extractor signature contract (default: sibling of this engine in scripts/).

.PARAMETER AsJson
  Emits the structured JSON contract instead of the backward-compatible text.

.EXAMPLE
  Test-MimirKbIndexGate.ps1 -RepoRoot C:\KBs\SampleKb -AsJson
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = (Get-Location).Path,
  [string]$QueryWrapperPath,
  [string]$StructureWrapperPath,
  [string]$IndexDirName = 'KbIntelligence',
  [string]$MetadataFileName = 'kb-source-metadata.md',
  [string]$ExtractorContractPath,
  [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $QueryWrapperPath) { $QueryWrapperPath = Join-Path $RepoRoot (Join-Path 'scripts' 'Query-KbIntelligence.ps1') }
if (-not $StructureWrapperPath) { $StructureWrapperPath = Join-Path $RepoRoot (Join-Path 'scripts' 'Test-KbStructure.ps1') }
if (-not $ExtractorContractPath) { $ExtractorContractPath = Join-Path $PSScriptRoot 'GeneXusKbIntelligenceExtractorContract.ps1' }

$indexDir = Join-Path $RepoRoot (($IndexDirName -replace '\\', '/').TrimEnd('/'))
$indexPath = Join-Path $indexDir 'kb-intelligence.sqlite'
$sourceMetadata = Join-Path $RepoRoot (($MetadataFileName -replace '\\', '/').Trim())

# Accumulator for the structured contract.
$out = [ordered]@{ status = 'OK'; reason = $null }

function Fail-Gate {
  param([string]$Reason)
  if ($AsJson) {
    $out['status'] = 'BLOCK'
    $out['reason'] = $Reason
    [pscustomobject]$out | ConvertTo-Json -Depth 4
    exit 1
  }
  throw "BLOCK: $Reason"
}

# Safety net for the "-AsJson never throws" contract: besides the known
# Fail-Gate cases, any unexpected exception (datetime parsing, a local wrapper
# that throws, the signature contract) also becomes { status: BLOCK, reason }
# under -AsJson, never a throw.
try {

# 1. structure
if (-not (Test-Path -LiteralPath $StructureWrapperPath -PathType Leaf)) { Fail-Gate 'local structure wrapper missing' }
$structureOutput = & $StructureWrapperPath *>&1
$structureOk = $?
$structureLines = @($structureOutput | Where-Object { $_ -is [string] } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$structureWarnings = @($structureOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message.Trim() } | Where-Object { $_ })
if ((-not $structureOk) -or (@($structureLines | Where-Object { $_ -match 'STRUCTURE_OK' }).Count -eq 0)) {
  # A fresh workspace (nothing materialized yet) lacks only the index, which the
  # first sync builds. Current structure wrappers say so with a PENDING line; a
  # wrapper copied before that change warns "1 missing component(s)" instead.
  $sourceMaterialized = (Test-Path -LiteralPath $sourceMetadata -PathType Leaf) -and
    ([System.IO.File]::ReadAllText($sourceMetadata) -match '(?m)^\s*last_xpz_materialization_run_at\s*[:=][ \t]*[^\s(]')
  $indexPending = (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) -and (-not $sourceMaterialized) -and (
    (@($structureLines | Where-Object { $_ -match '^PENDING:\s*first index build pending' }).Count -gt 0) -or
    ($structureLines.Count -eq 0 -and $structureWarnings.Count -eq 1 -and $structureWarnings[0] -match '^1 missing component\(s\)\.'))
  if ($indexPending) {
    Fail-Gate "first index build pending: $IndexDirName/kb-intelligence.sqlite does not exist yet; the first sync builds it, and the structure and index gates pass after that"
  }
  foreach ($w in $structureWarnings) { Write-Warning $w }
  $structureDetails = if ($structureLines.Count -gt 0) {
    $structureLines -join '; '
  } elseif ($structureWarnings.Count -gt 0) {
    $structureWarnings -join '; '
  } else {
    "the structure wrapper printed no details; run $StructureWrapperPath to see them"
  }
  Fail-Gate "KB workspace structure check failed: $structureDetails"
}

# 2. index
if (-not (Test-Path -LiteralPath $indexDir -PathType Container)) { Fail-Gate "$IndexDirName folder missing" }
if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { Fail-Gate "$IndexDirName/kb-intelligence.sqlite missing" }

# 3. query wrapper
if (-not (Test-Path -LiteralPath $QueryWrapperPath -PathType Leaf)) { Fail-Gate 'local query wrapper missing' }

# 4. index-metadata
$indexMetadata = & $QueryWrapperPath -Query index-metadata -Format text
$indexMetadataText = ($indexMetadata | Out-String)
if ([string]::IsNullOrWhiteSpace($indexMetadataText) -or ($indexMetadataText -notmatch 'last_index_build_run_at')) { Fail-Gate 'index-metadata missing or without last_index_build_run_at' }
if ($indexMetadataText -notmatch 'inventory_validation_status') { Fail-Gate 'index-metadata missing or without inventory_validation_status' }

# 5. kb-source-metadata
if (-not (Test-Path -LiteralPath $sourceMetadata -PathType Leaf)) { Fail-Gate "$MetadataFileName missing" }
$sourceMaterialization = Select-String -LiteralPath $sourceMetadata -Pattern 'last_xpz_materialization_run_at' -SimpleMatch
if (-not $sourceMaterialization) { Fail-Gate "$MetadataFileName without last_xpz_materialization_run_at" }

# 6. freshness
$indexMatch = [regex]::Match($indexMetadataText, 'last_index_build_run_at\s*[:=]\s*(?<value>\S+)')
$sourceMatch = [regex]::Match($sourceMaterialization.Line, 'last_xpz_materialization_run_at\s*[:=]\s*(?<value>\S+)')
if (-not $indexMatch.Success) { Fail-Gate 'index-metadata without a parseable value for last_index_build_run_at' }
if (-not $sourceMatch.Success) { Fail-Gate "$MetadataFileName without a parseable value for last_xpz_materialization_run_at" }
$lastIndexBuild = [datetimeoffset]::Parse($indexMatch.Groups['value'].Value)
$lastXpzMaterialization = [datetimeoffset]::Parse($sourceMatch.Groups['value'].Value)
$out['last_index_build_run_at'] = $indexMatch.Groups['value'].Value
$out['last_xpz_materialization_run_at'] = $sourceMatch.Groups['value'].Value
if ($lastIndexBuild -lt $lastXpzMaterialization) { Fail-Gate 'index is stale relative to last_xpz_materialization_run_at' }

# 7. semantic inventory
$inventoryStatusMatch = [regex]::Match($indexMetadataText, 'inventory_validation_status\s*[:=]\s*(?<value>\S+)')
if (-not $inventoryStatusMatch.Success) { Fail-Gate 'index-metadata without a parseable value for inventory_validation_status' }
if ($inventoryStatusMatch.Groups['value'].Value -ne 'OK') { Fail-Gate 'index has invalid or pending semantic inventory' }

# 8. extractor signature
if (-not (Test-Path -LiteralPath $ExtractorContractPath -PathType Leaf)) { Fail-Gate "extractor signature contract missing: $ExtractorContractPath" }
. $ExtractorContractPath
$indexMetadataMap = Get-GeneXusKbIntelligenceExtractorSignatureFromIndexMetadataText -IndexMetadataText $indexMetadataText
$extractorCheck = Test-GeneXusKbIntelligenceExtractorSignatureFromMetadata -Metadata $indexMetadataMap
if (-not $extractorCheck.ok) { Fail-Gate $extractorCheck.summary }

$out['extractor_signature_version'] = $extractorCheck.stored.extractor_signature_version
$out['extractor_signature_hash'] = $extractorCheck.stored.extractor_signature_hash
$out['inventory_validation_status'] = 'OK'

if ($AsJson) {
  [pscustomobject]$out | ConvertTo-Json -Depth 4
} else {
  ('extractor_signature_version: {0}' -f $extractorCheck.stored.extractor_signature_version)
  ('extractor_signature_hash: {0}' -f $extractorCheck.stored.extractor_signature_hash)
  'inventory_validation_status: OK'
  'GATE_OK'
}
exit 0

} catch {
  # Exception outside the known Fail-Gate cases. Under -AsJson honors the
  # contract (never throws): emits { status: BLOCK, reason } + exit 1. In text
  # mode, re-throws (backward-compatible default, preserves "BLOCK: <reason>").
  if ($AsJson) {
    $out['status'] = 'BLOCK'
    $out['reason'] = ($_.Exception.Message -replace '^BLOCK:\s*', '')
    [pscustomobject]$out | ConvertTo-Json -Depth 4
    exit 1
  }
  throw
}
