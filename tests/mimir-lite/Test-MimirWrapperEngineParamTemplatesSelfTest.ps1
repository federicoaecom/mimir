#requires -Version 7.4
<#
.SYNOPSIS
  SAFETY self-test: runs the forwards_unknown_engine_param check over ALL
  skills/mimir-lite/workflows/setup/examples/*.example.ps1 templates against the repo's REAL engines.

.DESCRIPTION
  The templates are, by definition, correct: a forwards_unknown_engine_param signal on them
  is a false positive from the extractor. Beyond "zero signals", it asserts EXACT COVERAGE
  (a named constant derived from the site inventory) so "zero signals" is not vacuous, and
  per-template coverage (proves the real shapes: intermediate variable, nested Join-Path,
  splat with conditional keys, 2>&1 redirection, -Param:$v form).
  Final sentinel: MIMIR_WRAPPER_ENGINE_PARAM_TEMPLATES_OK.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
. (Join-Path $scriptDir 'MimirWrapperEngineParamSupport.ps1')

$examplesDir = Join-Path $repoRoot 'skills\mimir-lite\workflows\setup\examples'
if (-not (Test-Path -LiteralPath $examplesDir -PathType Container)) {
    throw "ASSERT_FAILED: templates folder not found: $examplesDir"
}

# Canonical inventory of the 3 known shapes (a named constant, derived from the design
# table). Each template -> exact number of audited advanced-engine sites, proving each shape.
# Other templates also delegate to shared engines (larger aggregate coverage); here we
# pin only the proof shapes and use a derived FLOOR (their sum) for anti-vacuity,
# tolerant of new templates (avoids a fragile magic number).
$ExpectedAuditedByTemplate = [ordered]@{
    'Update-KbFromXpz.example.ps1'  = 3  # Sync (splat) + reminder (-AsJson) + inventory (-FailOnUnknownTypes 2>&1)
    'Test-KbIndexGate.example.ps1'  = 1  # nested Join-Path + splat via conditional index
    'Test-KbSetupAudit.example.ps1' = 1  # explicit with continuation + -AsJson:$AsJson
}
$MinExpectedAuditedSites = (@($ExpectedAuditedByTemplate.Values) | Measure-Object -Sum).Sum  # = 5

$totalAudited = 0
$totalSignals = [System.Collections.Generic.List[string]]::new()
$perTemplate = [ordered]@{}

foreach ($template in (Get-ChildItem -LiteralPath $examplesDir -Filter '*.example.ps1' -File | Sort-Object Name)) {
    $finding = Get-MimirWrapperEngineParamFinding -WrapperPath $template.FullName -EnginesRoot $scriptDir
    $totalAudited += [int]$finding.AuditedSiteCount
    $perTemplate[$template.Name] = [int]$finding.AuditedSiteCount
    foreach ($sig in $finding.Signals) {
        $totalSignals.Add(('{0}: {1}={2}' -f $template.Name, $sig.Reason, $sig.Detail))
    }
}

# 1. Zero signals over the templates (correct by definition).
if ($totalSignals.Count -gt 0) {
    throw "ASSERT_FAILED: templates must not produce signals; got=$($totalSignals -join ' | ')"
}

# 2. Anti-vacuity: aggregate coverage never below the proof-shapes floor.
if ($totalAudited -lt $MinExpectedAuditedSites) {
    throw "ASSERT_FAILED: aggregate auditedSiteCount=$totalAudited below the floor $MinExpectedAuditedSites (partial coverage?) (perTemplate=$(($perTemplate.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))"
}

# 3. Per-template coverage (proves the real shapes).
foreach ($name in $ExpectedAuditedByTemplate.Keys) {
    $got = if ($perTemplate.Contains($name)) { [int]$perTemplate[$name] } else { -1 }
    if ($got -ne [int]$ExpectedAuditedByTemplate[$name]) {
        throw "ASSERT_FAILED: template $name expected $($ExpectedAuditedByTemplate[$name]) audited site(s); got=$got"
    }
}

Write-Output 'MIMIR_WRAPPER_ENGINE_PARAM_TEMPLATES_OK'
