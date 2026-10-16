#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: the KbIntelligence indexer is registry-aware for orphaned legacy elements.

.DESCRIPTION
    Builds a synthetic KB with (a) a folder for a modern catalog type (WebPanel, 1 XML) and
    (b) a folder for the orphaned legacy element Report (1 XML with <Object type="gxlegacy/Report">),
    which the registry flags indexedByKbIntelligence. Builds the index with -FailOnValidationFailure and
    proves that:
      - the build COMPLETES (exit 0): the gxlegacy/Report token resolves to the type Report instead of
        falling into unknown_guids, and the Report folder is not an unknown_type_folder;
      - inventory_semantics.status == OK and mismatch_count == 0;
      - the Report folder enters snapshot_objects_by_directory and is NOT listed in
        legacy_orphan_directories_skipped (the skip applies only to orphans not indexed by KB Intelligence);
      - the modern-type folder is still indexed normally.
    Scenarios B and C keep the folder guards: a Report folder with modern content, or with a gxlegacy
    token other than the registered one, is flagged instead of being accepted.
    Scenario D runs the indexer from a copy of the scripts folder whose registry adds two synthetic orphans:
    one without indexedByKbIntelligence and one with the non-boolean value "true". Both folders are skipped
    and audited in legacy_orphan_directories_skipped (only the boolean true indexes an orphan).
    Scenario E uses the real registry: the non-indexed orphans Menu, Prompt, and Formula (GeneXus 7.0 and
    earlier, read from .xpw) are skipped and audited while Report stays indexed.
    The orphan folders and tokens come from the gx-legacy-export-element-registry.json registry, not inline.
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
$tempRootD = $null
$tempRootE = $null
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

# --- Orphaned legacy element indexed as its own type: Report, materialized with @type = typeToken gxlegacy/Report. ---
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
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete (exit 0) with a legacy Report folder present; exit $LASTEXITCODE"

$report = Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$inv = $report.inventory_semantics

Assert-True ($inv.status -eq 'OK') "inventory_semantics.status should be OK, was $($inv.status)"
Assert-True ($inv.mismatch_count -eq 0) "mismatch_count should be 0, was $($inv.mismatch_count)"

# Report is indexed as its own type, so it is not skipped and enters the snapshot.
$reportSkip = @(@($inv.legacy_orphan_directories_skipped) | Where-Object { $_.directory -eq 'Report' })
Assert-True ($reportSkip.Count -eq 0) "Report should not appear in legacy_orphan_directories_skipped, appeared $($reportSkip.Count)"
$snapNames = @($inv.snapshot_objects_by_directory.PSObject.Properties.Name)
Assert-True ($snapNames -contains 'Report') 'The Report folder should be in snapshot_objects_by_directory'
Assert-True ($snapNames -contains 'WebPanel') 'The modern-type WebPanel folder should be in snapshot_objects_by_directory'

$indexedNames = @($inv.indexed_objects_by_type.PSObject.Properties.Name)
Assert-True ($indexedNames -contains 'Report') 'Report should be indexed in indexed_objects_by_type'
Assert-True ($indexedNames -contains 'WebPanel') 'WebPanel should be indexed in indexed_objects_by_type'

# --- Scenario B: mis-named folder NOT masked ---
# A folder named 'Report' BUT with MODERN content (WebPanel, real GUID) must NOT be accepted silently:
# it follows the normal path and gets flagged (folder_type_mismatch, status BLOCK).
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
Assert-True ($reportSkipB.Count -eq 0) "Folder 'Report' with MODERN content should NOT be skipped as an orphan"
Assert-True ($invB.status -eq 'BLOCK') "Mis-named 'Report' folder (modern content) should produce status BLOCK, was $($invB.status)"

# --- Scenario C: wrong/unregistered gxlegacy token (governed by the registry) ---
# Folder 'Report' with type="gxlegacy/Foo" (a gxlegacy token that is NOT the one registered for Report).
# gxlegacy/Foo resolves to no type -> unknown token -> the build FAILS (does not silently accept it).
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

# --- Scenario D: an orphan not indexed by KB Intelligence is skipped and audited ---
# Report is the only real orphan and it is indexed, so the skip path is exercised with a registry copy that adds
# synthetic orphans. 'true' as a string is not the boolean true: the indexer fails closed and skips it.
$tempRootD = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-orphan-skip-{0}' -f ([guid]::NewGuid().ToString('N')))
$scriptsCopy = Join-Path $tempRootD 'scripts'
[void](New-Item -ItemType Directory -Path $tempRootD -Force)
Copy-Item -LiteralPath $scriptDir -Destination $scriptsCopy -Recurse
$registryCopyPath = Join-Path $scriptsCopy 'gx-legacy-export-element-registry.json'
$registryCopy = Get-Content -LiteralPath $registryCopyPath -Raw -Encoding UTF8 | ConvertFrom-Json
$registryCopy.elements | Add-Member -NotePropertyName 'SkipProbe' -NotePropertyValue ([pscustomobject]@{
    class = 'orphan'; materializedFolderName = 'SkipProbe'; typeToken = 'gxlegacy/SkipProbe'
    modernSuccessor = $null; successorRelation = 'none'
})
$registryCopy.elements | Add-Member -NotePropertyName 'StringFlagProbe' -NotePropertyValue ([pscustomobject]@{
    class = 'orphan'; materializedFolderName = 'StringFlagProbe'; typeToken = 'gxlegacy/StringFlagProbe'
    indexedByKbIntelligence = 'true'; modernSuccessor = $null; successorRelation = 'none'
})
[System.IO.File]::WriteAllText($registryCopyPath, ($registryCopy | ConvertTo-Json -Depth 10), $enc)

$kbWorkspaceRootD = Join-Path $tempRootD 'KbWorkspace'
$kbObjectsPathD = Join-Path $kbWorkspaceRootD 'KbObjectsXml'
$kbIntelDirD = Join-Path $kbWorkspaceRootD 'KbIntelligence'
foreach ($probe in @('SkipProbe', 'StringFlagProbe')) {
    $probeDir = Join-Path $kbObjectsPathD $probe
    [void](New-Item -ItemType Directory -Path $probeDir -Force)
    $probeXml = "<Object type=`"gxlegacy/$probe`" name=`"probe1`" lastUpdate=`"0001-01-01T00:00:00.0000000Z`" dataSource=`"gx-legacy-export`"><GxLegacyPayload><$probe><Info><Name>probe1</Name></Info></$probe></GxLegacyPayload></Object>"
    [System.IO.File]::WriteAllText((Join-Path $probeDir 'probe1.xml'), $probeXml, $enc)
}
[void](New-Item -ItemType Directory -Path (Join-Path $kbObjectsPathD 'WebPanel'), $kbIntelDirD -Force)
[System.IO.File]::WriteAllText((Join-Path $kbObjectsPathD 'WebPanel/wpProof.xml'), $webPanelXml, $enc)

$validationPathD = Join-Path $kbIntelDirD 'kb-intelligence-validation.json'
& (Join-Path $scriptsCopy 'Build-KbIntelligenceIndex.ps1') `
    -SourceRoot $kbObjectsPathD `
    -OutputPath (Join-Path $kbIntelDirD 'kb-intelligence.sqlite') `
    -ValidationReportPath $validationPathD `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRootD | Out-Null
Assert-True ($LASTEXITCODE -eq 0) "Scenario D: the build should complete with skipped orphan folders; exit $LASTEXITCODE"
$invD = (Get-Content -LiteralPath $validationPathD -Raw -Encoding UTF8 | ConvertFrom-Json).inventory_semantics
Assert-True ($invD.status -eq 'OK') "Scenario D: inventory_semantics.status should be OK, was $($invD.status)"
$snapNamesD = @($invD.snapshot_objects_by_directory.PSObject.Properties.Name)
foreach ($probe in @('SkipProbe', 'StringFlagProbe')) {
    $probeSkip = @(@($invD.legacy_orphan_directories_skipped) | Where-Object { $_.directory -eq $probe })
    Assert-True ($probeSkip.Count -eq 1) "Scenario D: $probe should appear once in legacy_orphan_directories_skipped, appeared $($probeSkip.Count)"
    Assert-True ($probeSkip[0].xml_count -eq 1) "Scenario D: $probe should record xml_count=1, recorded $($probeSkip[0].xml_count)"
    Assert-True (-not ($snapNamesD -contains $probe)) "Scenario D: the skipped $probe folder should NOT enter snapshot_objects_by_directory"
}
Assert-True (@($invD.indexed_objects_by_type.PSObject.Properties.Name) -contains 'WebPanel') 'Scenario D: WebPanel should still be indexed'

# --- Scenario E: the registered non-indexed orphans Menu, Prompt, and Formula (GeneXus 7.0 and earlier, .xpw) ---
# Uses the real registry: their folders are skipped and audited, while Report stays indexed as its own type.
$tempRootE = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-orphan-classic-{0}' -f ([guid]::NewGuid().ToString('N')))
$kbWorkspaceRootE = Join-Path $tempRootE 'KbWorkspace'
$kbObjectsPathE = Join-Path $kbWorkspaceRootE 'KbObjectsXml'
$kbIntelDirE = Join-Path $kbWorkspaceRootE 'KbIntelligence'
[void](New-Item -ItemType Directory -Path (Join-Path $kbObjectsPathE 'Report'), $kbIntelDirE -Force)
[System.IO.File]::WriteAllText((Join-Path $kbObjectsPathE 'Report/rptProof.xml'), $reportOrphanXml, $enc)
$classicOrphans = @(@('Menu', 'MnuMain', '<Info><Name>MnuMain</Name></Info>'), @('Prompt', 'PrmCustomer', '<Info><Name>PrmCustomer</Name></Info>'), @('Formula', 'CustTotal', '<Name>CustTotal</Name>'))
foreach ($orphan in $classicOrphans) {
    $orphanDir = Join-Path $kbObjectsPathE $orphan[0]
    [void](New-Item -ItemType Directory -Path $orphanDir -Force)
    $orphanXml = "<Object type=`"gxlegacy/$($orphan[0])`" name=`"$($orphan[1])`" lastUpdate=`"0001-01-01T00:00:00.0000000Z`" dataSource=`"gx-legacy-export`"><GxLegacyPayload><$($orphan[0])>$($orphan[2])</$($orphan[0])></GxLegacyPayload></Object>"
    [System.IO.File]::WriteAllText((Join-Path $orphanDir "$($orphan[1]).xml"), $orphanXml, $enc)
}

$validationPathE = Join-Path $kbIntelDirE 'kb-intelligence-validation.json'
& $indexScript `
    -SourceRoot $kbObjectsPathE `
    -OutputPath (Join-Path $kbIntelDirE 'kb-intelligence.sqlite') `
    -ValidationReportPath $validationPathE `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRootE | Out-Null
Assert-True ($LASTEXITCODE -eq 0) "Scenario E: the build should complete with Menu, Prompt, and Formula folders; exit $LASTEXITCODE"
$invE = (Get-Content -LiteralPath $validationPathE -Raw -Encoding UTF8 | ConvertFrom-Json).inventory_semantics
Assert-True ($invE.status -eq 'OK') "Scenario E: inventory_semantics.status should be OK, was $($invE.status)"
$snapNamesE = @($invE.snapshot_objects_by_directory.PSObject.Properties.Name)
foreach ($orphan in $classicOrphans) {
    $orphanSkip = @(@($invE.legacy_orphan_directories_skipped) | Where-Object { $_.directory -eq $orphan[0] })
    Assert-True ($orphanSkip.Count -eq 1) "Scenario E: $($orphan[0]) should appear once in legacy_orphan_directories_skipped, appeared $($orphanSkip.Count)"
    Assert-True ($orphanSkip[0].xml_count -eq 1) "Scenario E: $($orphan[0]) should record xml_count=1, recorded $($orphanSkip[0].xml_count)"
    Assert-True (-not ($snapNamesE -contains $orphan[0])) "Scenario E: the skipped $($orphan[0]) folder should NOT enter snapshot_objects_by_directory"
}
Assert-True (@(@($invE.legacy_orphan_directories_skipped) | Where-Object { $_.directory -eq 'Report' }).Count -eq 0) 'Scenario E: Report should not be skipped'
Assert-True ($snapNamesE -contains 'Report') 'Scenario E: the Report folder should be in snapshot_objects_by_directory'
Assert-True (@($invE.indexed_objects_by_type.PSObject.Properties.Name) -contains 'Report') 'Scenario E: Report should still be indexed as its own type'

Write-Output 'OK: Test-KbIntelligenceLegacyOrphanSkipSelfTest.ps1'
} finally {
    foreach ($root in @($tempRoot, $tempRootB, $tempRootC, $tempRootD, $tempRootE)) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
exit 0
