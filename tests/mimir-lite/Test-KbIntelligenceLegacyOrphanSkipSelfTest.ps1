#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: the KbIntelligence indexer is registry-aware for orphaned legacy elements.

.DESCRIPTION
    Builds a synthetic KB with (a) a folder for a modern catalog type (WebPanel, 1 XML) and
    (b) a folder for an orphaned legacy element from the registry (Report, 1 XML with
    <Object type="gxlegacy/Report">). Builds the index with -FailOnValidationFailure and proves that:
      - the build COMPLETES (exit 0); before the fix, the type "gxlegacy/Report" fell into unknown_guids
        and triggered raise SystemExit in collect_all_objects, and the "Report" folder (outside
        GX_TYPE_CATALOG_BY_NAME) would become unknown_type_folder -> status BLOCK;
      - inventory_semantics.status == OK and mismatch_count == 0;
      - the orphan folder does NOT enter snapshot_objects_by_directory (avoids directory_inventory_mismatch);
      - the skip stays AUDITABLE in legacy_orphan_directories_skipped (name + count), so that OK does not
        hide physically present orphan XMLs;
      - the modern-type folder is still indexed normally.
    The list of orphan folders comes from the gx-legacy-export-element-registry.json registry (dynamic), not inline.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath
$enc = Get-Utf8NoBomEncoding

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-orphan-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
# Scenarios B and C assign their own temp roots below; declared here so the finally block can remove them.
$tempRootB = $null
$tempRootC = $null
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$webPanelDir = Join-Path $kbObjectsPath 'WebPanel'
$reportDir = Join-Path $kbObjectsPath 'Report'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $webPanelDir, $reportDir, $kbIntelDir -Force)

# --- Modern catalog type: WebPanel (real GUID), should be indexed normally. ---
$webPanelXml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpProof" guid="44444444-0000-0000-0000-000000000001">
  <Properties>
    <Property><Name>Name</Name><Value>wpProof</Value></Property>
  </Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $webPanelDir 'wpProof.xml'), $webPanelXml, $enc)

# --- Orphaned legacy element: Report, materialized with @type = typeToken gxlegacy/Report. ---
# Before the fix this broke the build (unknown_guids -> SystemExit; Report folder -> unknown_type_folder -> BLOCK).
$reportOrphanXml = @'
<Object type="gxlegacy/Report" name="rptProof" lastUpdate="0001-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
    <Report><Info><Name>rptProof</Name></Info></Report>
  </GxLegacyPayload>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $reportDir 'rptProof.xml'), $reportOrphanXml, $enc)

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
$indexScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'

& $indexScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete (exit 0) with an orphaned legacy folder present; exit $LASTEXITCODE"

$report = Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$inv = $report.inventory_semantics

Assert-True ($inv.status -eq 'OK') "inventory_semantics.status should be OK, was $($inv.status)"
Assert-True ($inv.mismatch_count -eq 0) "mismatch_count should be 0, was $($inv.mismatch_count)"

# Orphan folder audited in the diagnostic (name + count).
$skipped = @($inv.legacy_orphan_directories_skipped)
$reportSkip = @($skipped | Where-Object { $_.directory -eq 'Report' })
Assert-True ($reportSkip.Count -eq 1) "Report should appear once in legacy_orphan_directories_skipped, appeared $($reportSkip.Count)"
Assert-True ($reportSkip[0].xml_count -eq 1) "Report should record xml_count=1 in the skip, recorded $($reportSkip[0].xml_count)"

# Orphan folder does NOT enter the snapshot (avoids directory_inventory_mismatch); modern type stays in the snapshot.
$snapNames = @($inv.snapshot_objects_by_directory.PSObject.Properties.Name)
Assert-True (-not ($snapNames -contains 'Report')) 'The orphan Report folder should NOT enter snapshot_objects_by_directory'
Assert-True ($snapNames -contains 'WebPanel') 'The modern-type WebPanel folder should be in snapshot_objects_by_directory'

# Modern type indexed normally.
$indexedNames = @($inv.indexed_objects_by_type.PSObject.Properties.Name)
Assert-True ($indexedNames -contains 'WebPanel') 'WebPanel should be indexed in indexed_objects_by_type'

# --- Scenario B: content-aware skip (mis-named folder NOT masked) ---
# A folder named 'Report' (an orphan name from the registry) BUT with MODERN content (WebPanel, real GUID)
# must NOT be silently skipped: the skip is content-aware (folder_is_all_legacy_orphan), so it follows
# the normal path and gets flagged (status BLOCK), instead of becoming legacy_orphan_directories_skipped.
$tempRootB = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-orphan-misnamed-{0}' -f ([guid]::NewGuid().ToString('N')))
$kbWorkspaceRootB = Join-Path $tempRootB 'KbWorkspace'
$kbObjectsPathB = Join-Path $kbWorkspaceRootB 'KbObjectsXml'
$misnamedReportDir = Join-Path $kbObjectsPathB 'Report'
$kbIntelDirB = Join-Path $kbWorkspaceRootB 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $misnamedReportDir, $kbIntelDirB -Force)

$misnamedXml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpMisnamed" guid="55555555-0000-0000-0000-000000000001">
  <Properties>
    <Property><Name>Name</Name><Value>wpMisnamed</Value></Property>
  </Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $misnamedReportDir 'wpMisnamed.xml'), $misnamedXml, $enc)

$sqlitePathB = Join-Path $kbIntelDirB 'kb-intelligence.sqlite'
$validationPathB = Join-Path $kbIntelDirB 'kb-intelligence-validation.json'

# Without -FailOnValidationFailure: we want to read the report even with BLOCK.
& $indexScript `
    -SourceRoot $kbObjectsPathB `
    -OutputPath $sqlitePathB `
    -ValidationReportPath $validationPathB `
    -KbWorkspaceRoot $kbWorkspaceRootB | Out-Null

$reportB = Get-Content -LiteralPath $validationPathB -Raw -Encoding UTF8 | ConvertFrom-Json
$invB = $reportB.inventory_semantics

$skippedB = @($invB.legacy_orphan_directories_skipped)
$reportSkipB = @($skippedB | Where-Object { $_.directory -eq 'Report' })
Assert-True ($reportSkipB.Count -eq 0) "Folder 'Report' with MODERN content should NOT be skipped as an orphan (skip would mask a mis-named directory)"
Assert-True ($invB.status -eq 'BLOCK') "Mis-named 'Report' folder (modern content) should produce status BLOCK, was $($invB.status)"

# --- Scenario C: wrong/unregistered gxlegacy token (governed by the registry) ---
# Folder 'Report' with type="gxlegacy/Foo" (a gxlegacy token that is NOT the one registered for Report). The skip is
# governed by the registry: gxlegacy/Foo != gxlegacy/Report -> does NOT skip -> follows the normal path ->
# unknown token -> the build FAILS (does not silently mask it as an orphan).
$tempRootC = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-orphan-wrongtoken-{0}' -f ([guid]::NewGuid().ToString('N')))
$kbWorkspaceRootC = Join-Path $tempRootC 'KbWorkspace'
$kbObjectsPathC = Join-Path $kbWorkspaceRootC 'KbObjectsXml'
$wrongTokenReportDir = Join-Path $kbObjectsPathC 'Report'
$kbIntelDirC = Join-Path $kbWorkspaceRootC 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $wrongTokenReportDir, $kbIntelDirC -Force)

$wrongTokenXml = @'
<Object type="gxlegacy/Foo" name="rptWrong" lastUpdate="0001-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload><Foo><Info><Name>rptWrong</Name></Info></Foo></GxLegacyPayload>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $wrongTokenReportDir 'rptWrong.xml'), $wrongTokenXml, $enc)

$sqlitePathC = Join-Path $kbIntelDirC 'kb-intelligence.sqlite'
$validationPathC = Join-Path $kbIntelDirC 'kb-intelligence-validation.json'

$cFailed = $false
try {
    & $indexScript -SourceRoot $kbObjectsPathC -OutputPath $sqlitePathC -ValidationReportPath $validationPathC -KbWorkspaceRoot $kbWorkspaceRootC 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $cFailed = $true }
} catch {
    $cFailed = $true
}
Assert-True $cFailed "Folder 'Report' with a wrong gxlegacy token (gxlegacy/Foo) should FAIL the build (not mask it as an orphan), but the build succeeded"

Write-Output 'OK: Test-KbIntelligenceLegacyOrphanSkipSelfTest.ps1'
} finally {
    foreach ($root in @($tempRoot, $tempRootB, $tempRootC)) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
exit 0
