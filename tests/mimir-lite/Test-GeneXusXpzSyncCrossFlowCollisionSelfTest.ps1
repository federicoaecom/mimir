#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for SOURCE DIVERGENCE (dataSource) detection cross-flow modern<->legacy
    in Sync-GeneXusXpzToXml.ps1 (section "Cross-flow modern↔legacy detection", owning doc 01k).

.DESCRIPTION
    Exercises the engine via a CHILD PROCESS (pwsh -File), capturing stdout/stderr/exit
    separately. The LEGACY fixture (GeneXusLegacyExportFileSupport) is the incoming; the
    «other flow» is simulated by pre-planting, in the already-materialized corpus, a
    MODERN envelope file (without dataSource), LEGACY (with dataSource), with
    <GxLegacyPayload> (Decision E.2), or unparseable. Detection is symmetric, so the
    legacy-incoming direction exercises the same code as modern-incoming.

    Cases covered (stable, non-contiguous case IDs, reused in the comments below):
      1/2 detection by divergence (existing modern «» vs. incoming legacy «gx-legacy-export»);
      3   same flow (existing legacy) -> NO collision;
      6   -Block + -KbMetadataPath -> throw, metadata NOT created, STDOUT without Summary, STDERR with
          CROSSFLOW_COLLISION: and CROSSFLOW_BLOCKED_ERRORID:;
      7   -VerifyOnly without -Block + collision -> Summary.CrossFlowCollisions present, nothing written;
      9   existing NOT PARSEABLE (fail-soft) -> warning, no crash, no collision;
      13  -Block + not parseable -> does NOT block (fail-safe);
      15  -VerifyOnly + -Block + collision -> throw, nothing written;
      17  Decision E.2: existing without dataSource but with <GxLegacyPayload> + legacy incoming ->
          classified as legacy -> NO collision (same flow);
      Writes[].CrossFlowCollision per item; stderr JSONL mitigation.

    Success token on stdout + exit 0: GENEXUS_MIMIR_SYNC_CROSSFLOW_SELFTEST_OK
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'GeneXusLegacyExportFileFixtureSupport.ps1')
$syncScript = Join-Path $scriptsRoot 'Sync-GeneXusXpzToXml.ps1'

function New-WorkRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('crossflow-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $root)
    return $root
}

function Invoke-Sync {
    <# Runs the Sync as a child process; returns { Stdout, Stderr, ExitCode, Summary }. Never throws. #>
    param([string[]]$SyncArgs)
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath 'pwsh' -ArgumentList (@('-NoProfile', '-File', $syncScript) + $SyncArgs) `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $stdout = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        $summary = $null
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            $line = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1]
            if ($line) { try { $summary = $line | ConvertFrom-Json } catch { $summary = $null } }
        }
        return [pscustomobject]@{ Stdout = [string]$stdout; Stderr = [string]$stderr; ExitCode = $p.ExitCode; Summary = $summary }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

function New-LegacyCorpus {
    <# Materializes the legacy fixture into a fresh corpus and returns { Dest, ProcFile }
       (the materialized RelConfig Procedure path, used to plant the «other flow»). #>
    param([string]$Work)
    $fixture = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $Work 'legacy.xml')
    $dest = Join-Path $Work 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)
    $report = Join-Path $Work 'report.json'
    $r = Invoke-Sync -SyncArgs @('-InputPath', $fixture, '-DestinationRoot', $dest, '-ReportPath', $report, '-KeepReport')
    if ($r.ExitCode -ne 0) { throw "Setup: the initial legacy sync failed (exit $($r.ExitCode)). Stderr: $($r.Stderr)" }
    $rep = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    $proc = @($rep.Writes | Where-Object { $_.LogicalName -eq 'RelConfig' })[0]
    if (-not $proc) { throw 'Setup: could not find the RelConfig item in the materialized corpus.' }
    return [pscustomobject]@{ Fixture = $fixture; Dest = $dest; ProcFile = $proc.FilePath }
}

$failures = New-Object System.Collections.Generic.List[string]
function Assert($cond, $msg) { if (-not $cond) { $script:failures.Add($msg) | Out-Null } }

$modernEnvelope = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<Object type=`"x`" name=`"RelConfig`" guid=`"abc`" lastUpdate=`"2000-01-01T00:00:00.0000000Z`"><Body/></Object>"
$legacyEnvelope = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<Object type=`"x`" name=`"RelConfig`" guid=`"`" lastUpdate=`"2000-01-01T00:00:00.0000000Z`" dataSource=`"gx-legacy-export`"><GxLegacyPayload><Procedure/></GxLegacyPayload></Object>"
$payloadOnlyEnvelope = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<Object name=`"RelConfig`" guid=`"`" lastUpdate=`"2000-01-01T00:00:00.0000000Z`"><GxLegacyPayload><Procedure/></GxLegacyPayload></Object>"

# =====================================================================================
# Case 1/2 — existing MODERN (without dataSource) + legacy incoming -> COLLISION (fail-soft)
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, $modernEnvelope)
    $meta = Join-Path $w 'kb-source-metadata.md'
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest, '-KbMetadataPath', $meta)
    Assert ($r.ExitCode -eq 0) "Case1: exit=$($r.ExitCode) (expected 0, fail-soft). Stderr: $($r.Stderr)"
    Assert ($null -ne $r.Summary) 'Case1: Summary missing from stdout.'
    $cf = @($r.Summary.CrossFlowCollisions)
    Assert ($cf.Count -eq 1) "Case1: CrossFlowCollisions=$($cf.Count) (expected 1)."
    Assert ($cf.Count -eq 1 -and $cf[0].NormalizedName -eq 'RelConfig') 'Case1: the collision is not RelConfig.'
    Assert ($cf.Count -eq 1 -and $cf[0].IncomingDataSource -eq 'gx-legacy-export' -and $cf[0].ExistingDataSource -eq '') 'Case1: incorrect dataSource pair.'
    Assert ($r.Stderr -match 'CROSSFLOW_COLLISION:') 'Case1: stderr missing CROSSFLOW_COLLISION:.'
    Assert (Test-Path -LiteralPath $meta) 'Case1: metadata should have been written (fail-soft).'
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================
# Case 3 — existing LEGACY + legacy incoming -> SAME FLOW, NO collision
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, $legacyEnvelope)
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest)
    Assert ($r.ExitCode -eq 0) "Case3: exit=$($r.ExitCode)."
    Assert ($null -ne $r.Summary -and @($r.Summary.CrossFlowCollisions).Count -eq 0) 'Case3: should be NO collision (same flow).'
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================
# Case 17 — Decision E.2: existing without dataSource but with <GxLegacyPayload> -> legacy -> NO collision
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, $payloadOnlyEnvelope)
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest)
    Assert ($r.ExitCode -eq 0) "Case17: exit=$($r.ExitCode)."
    Assert ($null -ne $r.Summary -and @($r.Summary.CrossFlowCollisions).Count -eq 0) 'Case17: E.2 should classify the existing item as legacy (NO collision).'
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================
# Case 6 — -Block + -KbMetadataPath + collision -> throw, metadata NOT created, stderr with ErrorId
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, $modernEnvelope)
    $metaB = Join-Path $w 'kb-block.md'   # does not exist yet
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest, '-KbMetadataPath', $metaB, '-BlockCrossFlowDataSource')
    Assert ($r.ExitCode -ne 0) "Case6: exit=$($r.ExitCode) (expected !=0 under -Block)."
    Assert (-not (Test-Path -LiteralPath $metaB)) 'Case6: metadata should NOT have been created (pre-metadata atomicity).'
    Assert ($r.Stderr -match 'CROSSFLOW_BLOCKED_ERRORID: CrossFlowDataSourceCollisionBlocked') 'Case6: stderr missing CROSSFLOW_BLOCKED_ERRORID.'
    Assert ($r.Stderr -match 'CROSSFLOW_COLLISION:') 'Case6: stderr missing CROSSFLOW_COLLISION:.'
    Assert ($null -eq $r.Summary) 'Case6: STDOUT should not contain a Summary (throw before it is emitted).'
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================
# Case 7 — -VerifyOnly without -Block + collision -> Summary.CrossFlowCollisions present, nothing written
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, $modernEnvelope)
    $before = (Get-Content -LiteralPath $a.ProcFile -Raw)
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest, '-VerifyOnly')
    Assert ($r.ExitCode -eq 0) "Case7: exit=$($r.ExitCode)."
    Assert ($null -ne $r.Summary -and @($r.Summary.CrossFlowCollisions).Count -eq 1) 'Case7: CrossFlowCollisions should be present under -VerifyOnly.'
    Assert ((Get-Content -LiteralPath $a.ProcFile -Raw) -eq $before) 'Case7: -VerifyOnly should not have overwritten the file.'
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================
# Case 15 — -VerifyOnly + -Block + collision -> throw, nothing written
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, $modernEnvelope)
    $before = (Get-Content -LiteralPath $a.ProcFile -Raw)
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest, '-VerifyOnly', '-BlockCrossFlowDataSource')
    Assert ($r.ExitCode -ne 0) "Case15: exit=$($r.ExitCode) (expected !=0)."
    Assert ($r.Stderr -match 'CROSSFLOW_BLOCKED_ERRORID') 'Case15: stderr missing ErrorId.'
    Assert ((Get-Content -LiteralPath $a.ProcFile -Raw) -eq $before) 'Case15: nothing should have been written.'
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================
# Case 9/13 — existing NOT PARSEABLE: contract of the DETECTION (Decision G). Asserted through the detection's stderr MARKERS (warning emitted, no
# collision, no block), NOT through the exit code: a garbage file in the corpus crashes
# DOWNSTREAM stages (Get-LastUpdateInfoFromFile / Test-PackageMaterialization),
# independently of the detection. Detection runs and emits its markers BEFORE that
# downstream crash.
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, "this is not XML <<< {{{ ")
    # fail-soft: detection treats the unparseable file as a warning, no collision
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest)
    Assert ($r.Stderr -match 'CROSSFLOW_WARNING:') 'Case9: detection should emit CROSSFLOW_WARNING for an unparseable file.'
    Assert (-not ($r.Stderr -match 'CROSSFLOW_COLLISION:')) 'Case9: unparseable should NOT generate a collision.'
    # -Block: detection does NOT block on unparseable (fail-safe): no block ErrorId
    $a2obj = New-LegacyCorpus -Work (New-WorkRoot)
    [System.IO.File]::WriteAllText($a2obj.ProcFile, "also not XML }}}")
    $r2 = Invoke-Sync -SyncArgs @('-InputPath', $a2obj.Fixture, '-DestinationRoot', $a2obj.Dest, '-BlockCrossFlowDataSource')
    Assert (-not ($r2.Stderr -match 'CROSSFLOW_BLOCKED_ERRORID')) 'Case13: -Block should NOT trigger a block on an unparseable file (fail-safe).'
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

# =====================================================================================
# Writes[].CrossFlowCollision per item (via -ReportPath) — exactly the colliding item marked
# =====================================================================================
$w = New-WorkRoot
try {
    $a = New-LegacyCorpus -Work $w
    [System.IO.File]::WriteAllText($a.ProcFile, $modernEnvelope)
    $rep2 = Join-Path $w 'rep2.json'
    $r = Invoke-Sync -SyncArgs @('-InputPath', $a.Fixture, '-DestinationRoot', $a.Dest, '-ReportPath', $rep2, '-KeepReport')
    Assert ($r.ExitCode -eq 0) "WritesFlag: exit=$($r.ExitCode)."
    $rep = Get-Content -LiteralPath $rep2 -Raw | ConvertFrom-Json
    $flagged = @($rep.Writes | Where-Object { $_.CrossFlowCollision })
    Assert ($flagged.Count -eq 1 -and $flagged[0].LogicalName -eq 'RelConfig') "WritesFlag: expected 1 flagged item (RelConfig), got $($flagged.Count)."
} finally { Remove-Item -LiteralPath $w -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count -gt 0) {
    Write-Host "FAILURES ($($failures.Count)):"
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Output 'GENEXUS_MIMIR_SYNC_CROSSFLOW_SELFTEST_OK'
exit 0
