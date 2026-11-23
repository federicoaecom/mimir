#requires -Version 7.4
<#
.SYNOPSIS
  Shared engine for the KbIntelligence index gate (the gate a KB workspace's local
  Test-*KbIndexGate.ps1 wrapper calls): validates structure, the corpus generation
  verdict, semantic inventory and the extractor signature of the index derived from a
  KB workspace.

.DESCRIPTION
  A shared engine, symmetric to Test-MimirSetupAudit.ps1: it receives the KB paths as
  parameters; the thin local wrapper only injects the paths and forwards -AsJson.

  Checks sequentially:
    1. KB workspace structure (STRUCTURE_OK via the local structure wrapper);
    2. index folder + kb-intelligence.sqlite present;
    3. local query wrapper present;
    4. index-metadata with last_index_build_run_at and inventory_validation_status; a
       failing query blocks with its own exit code and stderr;
    5. kb-source-metadata.md present;
    6. corpus generation verdict from index-metadata: blocks unless
       corpus_generation_match is true, naming corpus_block_reason (corpus-incomplete,
       corpus-unknown, corpus-invalid, corpus-lock-busy, index-generation-missing,
       index-generation-mismatch) and its recovery. The gate takes no lock itself: the
       query reads the corpus state under the corpus lock. last_index_build_run_at and
       last_xpz_materialization_run_at are reported as information only, never as proof
       of freshness;
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
      last_xpz_materialization_run_at, corpus_state, corpus_generation,
      index_corpus_generation, corpus_generation_match, corpus_block_reason }
      (fields appear once the step that reads them has run). NEVER throws under -AsJson: a block
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

# 4. index-metadata. The query's stderr is captured so a failure reports its real cause.
$global:LASTEXITCODE = $null
$indexMetadataRaw = @(& $QueryWrapperPath -Query index-metadata -Format text 2>&1)
$indexMetadataExit = if ($LASTEXITCODE -is [int]) { $LASTEXITCODE } else { 0 }
$indexMetadataText = (@($indexMetadataRaw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) | Out-String)
$indexMetadataError = (@($indexMetadataRaw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join ' | ')
if ($indexMetadataExit -ne 0 -or [string]::IsNullOrWhiteSpace($indexMetadataText)) {
  $cause = if ($indexMetadataError) {
    $indexMetadataError
  } elseif (-not [string]::IsNullOrWhiteSpace($indexMetadataText)) {
    $indexMetadataText.Trim() -replace '\r?\n', ' | '
  } else {
    'the query printed nothing'
  }
  Fail-Gate "index-metadata query failed (exit $indexMetadataExit): $cause"
}
if ($indexMetadataText -notmatch 'last_index_build_run_at') { Fail-Gate 'index-metadata missing or without last_index_build_run_at' }
if ($indexMetadataText -notmatch 'inventory_validation_status') { Fail-Gate 'index-metadata missing or without inventory_validation_status' }

# 5. kb-source-metadata (its materialization date is information, not a freshness proof)
if (-not (Test-Path -LiteralPath $sourceMetadata -PathType Leaf)) { Fail-Gate "$MetadataFileName missing" }
$indexMatch = [regex]::Match($indexMetadataText, '(?m)^last_index_build_run_at\s*[:=]\s*(?<value>\S+)')
$out['last_index_build_run_at'] = if ($indexMatch.Success) { $indexMatch.Groups['value'].Value } else { $null }
$sourceMaterialization = Select-String -LiteralPath $sourceMetadata -Pattern 'last_xpz_materialization_run_at' -SimpleMatch | Select-Object -First 1
$sourceMatch = if ($sourceMaterialization) { [regex]::Match($sourceMaterialization.Line, 'last_xpz_materialization_run_at\s*[:=]\s*(?<value>\S+)') } else { $null }
$out['last_xpz_materialization_run_at'] = if ($sourceMatch -and $sourceMatch.Success) { $sourceMatch.Groups['value'].Value } else { $null }

# 6. corpus generation verdict, read by index-metadata under the corpus lock (the gate
#    itself takes no lock).
function Get-IndexMetadataValue {
  param([string]$Key)
  $match = [regex]::Match($indexMetadataText, "(?m)^$([regex]::Escape($Key))[ \t]*:[ \t]*(?<value>\S*)[ \t]*\r?$")
  if (-not $match.Success) { return $null }
  return $match.Groups['value'].Value
}
$matchValue = Get-IndexMetadataValue 'corpus_generation_match'
if ($null -eq $matchValue) {
  Fail-Gate 'index-metadata does not report corpus_generation_match: the shared Mimir Lite checkout predates corpus generations; update it, then rebuild the index'
}
foreach ($key in @('corpus_state', 'corpus_generation', 'index_corpus_generation', 'corpus_block_reason')) {
  $value = Get-IndexMetadataValue $key
  $out[$key] = if ([string]::IsNullOrEmpty($value) -or $value -eq 'null') { $null } else { $value }
}
$out['corpus_generation_match'] = ($matchValue -eq 'true')
if (-not $out['corpus_generation_match']) {
  $blockReason = if ($out['corpus_block_reason']) { $out['corpus_block_reason'] } else { 'unknown' }
  # Only an incomplete corpus can name a package to re-run (when the sync reported one); an unknown
  # or invalid state is recovered by a verified -FullSnapshot sync alone.
  $notAFix = 'deleting or editing the state file is not a fix'
  $incompleteRecovery = "re-run the sync of the package that left it incomplete (when the sync reported one), or run a verified -FullSnapshot sync of a full KB export; then rebuild the index; $notAFix"
  $snapshotRecovery = "run a verified -FullSnapshot sync of a full KB export, then rebuild the index; $notAFix"
  $recovery = switch ($blockReason) {
    'corpus-incomplete' { "the corpus is incomplete (a sync failed or was interrupted): $incompleteRecovery" }
    'corpus-unknown' { "the corpus records no synchronization state, or its folder is missing beside the index: $snapshotRecovery (an existing workspace migrates once, see the setup update workflow)" }
    'corpus-invalid' { "the corpus state file cannot be read: $snapshotRecovery" }
    'corpus-lock-busy' { 'another process (an XPZ sync or an index build) holds the corpus lock: wait for it to finish and run the gate again' }
    'index-generation-missing' { 'the index records no corpus generation (built before generations were recorded): rebuild the index from the complete corpus' }
    'index-generation-mismatch' { 'the corpus changed since the index was built: rebuild the index from the complete corpus' }
    default { 'the index is not backed by a complete corpus: complete the sync, then rebuild the index' }
  }
  Fail-Gate "corpus generation check failed ($blockReason): $recovery"
}

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
  ('corpus_generation: {0}' -f $out['corpus_generation'])
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
