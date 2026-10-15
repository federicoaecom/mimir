#requires -Version 7.4
<#
.SYNOPSIS
    End-to-end self-test of the legacy branch of Sync-GeneXusXpzToXml.ps1 (GeneXus 9 export).

.DESCRIPTION
    Exercises the REAL INTEGRATION (child process pwsh -File) of the Sync over the
    iso-8859-1 fixture generated on-the-fly, covering:
    - legacy -FullSnapshot does NOT crash under StrictMode (guards against
      "property 'Guid' cannot be found"); LegacyFormatDetected=true, RenamedByGuid=0,
      MaterializationInterpretation='legacy-export-adapted';
    - reread from disk: equivalent -> <Object type="<real GUID>">, orphan Report ->
      type="gxlegacy/Report" under a Report folder, guid="" and GxLegacyPayload present;
    - sentinel vs. real date -> skipped-older-lastUpdate (conservative);
    - MIXED package -> throw and kb-source-metadata.md NOT created;
    - legacy tag outside the registry + KbMetadataPath -> throw and kb-source-metadata.md
      NEITHER created NOR altered (fail-closed before writing metadata).
    Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'GeneXusLegacyExportFileFixtureSupport.ps1')

$syncScript = Join-Path $scriptsRoot 'Sync-GeneXusXpzToXml.ps1'

function New-WorkRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('legacy-sync-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $root)
    return $root
}

function Write-Iso88591File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::GetEncoding('iso-8859-1'))
}

function Invoke-SyncJson {
    <# Runs the Sync and returns the stdout JSON object (last non-empty line). Throws if exit != 0. #>
    param([string[]]$SyncArgs)
    $stdout = & pwsh -NoProfile -File $syncScript @SyncArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Sync returned exit $LASTEXITCODE (expected 0). Args: $($SyncArgs -join ' ')"
    }
    $line = @($stdout | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1]
    return ($line | ConvertFrom-Json)
}

function Invoke-SyncExpectFailure {
    <# Runs the Sync and requires exit != 0 (fail-closed). #>
    param([string[]]$SyncArgs)
    & pwsh -NoProfile -File $syncScript @SyncArgs 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        throw "Sync should have failed (exit != 0), but returned 0. Args: $($SyncArgs -join ' ')"
    }
}

# =====================================================================================
# Case 1 — legacy -FullSnapshot does not crash; reread from disk (equivalent + orphan)
# =====================================================================================
$work1 = New-WorkRoot
try {
    $fixture = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $work1 'legacy.xml')
    $dest = Join-Path $work1 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)
    $meta = Join-Path $work1 'kb-source-metadata.md'

    $summary = Invoke-SyncJson -SyncArgs @('-InputPath', $fixture, '-DestinationRoot', $dest, '-FullSnapshot', '-KbMetadataPath', $meta)

    if (-not $summary.LegacyFormatDetected) { throw 'Case1: LegacyFormatDetected should be true.' }
    if ($summary.MaterializationInterpretation -ne 'legacy-export-adapted') { throw "Case1: MaterializationInterpretation='$($summary.MaterializationInterpretation)' (expected legacy-export-adapted)." }
    if ($summary.RenamedByGuid -ne 0) { throw "Case1: RenamedByGuid=$($summary.RenamedByGuid) (expected 0; guid='' does not participate in rename)." }
    if ($summary.Created -ne 7) { throw "Case1: Created=$($summary.Created) (expected 7)." }
    if ($summary.MissingAfterVerification -ne 0 -or $summary.MismatchesAfterVerification -ne 0) { throw 'Case1: post-materialization verification failed.' }
    if ($summary.FullSnapshotMissing -ne 0 -or $summary.FullSnapshotExtra -ne 0) { throw 'Case1: full snapshot reported missing/extra.' }

    # Reread from disk: orphan Report -> Report folder, type gxlegacy/Report
    $reportFile = Join-Path (Join-Path $dest 'Report') 'RelMov.xml'
    if (-not (Test-Path -LiteralPath $reportFile)) { throw "Case1: orphan Report not materialized at $reportFile." }
    [xml]$reportXml = Get-Content -LiteralPath $reportFile -Raw
    if ($reportXml.DocumentElement.LocalName -ne 'Object') { throw 'Case1: the orphan root should be <Object>.' }
    if ($reportXml.DocumentElement.GetAttribute('type') -ne 'gxlegacy/Report') { throw "Case1: orphan type='$($reportXml.DocumentElement.GetAttribute('type'))' (expected gxlegacy/Report)." }
    if ($reportXml.DocumentElement.GetAttribute('guid') -ne '') { throw 'Case1: the orphan guid should be empty.' }
    if ($null -eq $reportXml.DocumentElement.SelectSingleNode('./GxLegacyPayload')) { throw 'Case1: GxLegacyPayload missing on the orphan.' }

    # Reread from disk: equivalent Transaction -> real GUID (not gxlegacy/*)
    $txFile = Join-Path (Join-Path $dest 'Transaction') 'Cliente.xml'
    if (-not (Test-Path -LiteralPath $txFile)) { throw "Case1: equivalent Transaction not materialized at $txFile." }
    [xml]$txXml = Get-Content -LiteralPath $txFile -Raw
    $txType = $txXml.DocumentElement.GetAttribute('type')
    if ([string]::IsNullOrWhiteSpace($txType) -or $txType -like 'gxlegacy/*') { throw "Case1: equivalent type='$txType' (expected a real catalog GUID)." }

    # Metadata written with Build coming from MaxGxBuildSaved (2601) and no real <Source> block
    if (-not (Test-Path -LiteralPath $meta)) { throw 'Case1: kb-source-metadata.md should have been created.' }
    $metaText = Get-Content -LiteralPath $meta -Raw
    if ($metaText -notmatch '(?m)^\|\s*Build\s*\|\s*2601\s*\|') { throw 'Case1: Build=2601 (MaxGxBuildSaved) not written to the metadata.' }
} finally {
    if (Test-Path -LiteralPath $work1) { Remove-Item -LiteralPath $work1 -Recurse -Force }
}

# =====================================================================================
# Case 2 — sentinel vs. real date -> skipped-older-lastUpdate
# =====================================================================================
$work2 = New-WorkRoot
try {
    $fixture = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $work2 'legacy.xml')
    $dest = Join-Path $work2 'corpus'
    $procFolder = Join-Path $dest 'Procedure'
    [void](New-Item -ItemType Directory -Path $procFolder)

    # Pre-seeds Procedure/RelConfig.xml with a REAL lastUpdate (the fixture ships RelConfig WITHOUT
    # LastUpdate -> sentinel 0001-01-01, which is older -> should be skipped).
    $seed = @'
<?xml version="1.0" encoding="utf-8"?>
<Object type="gxlegacy/seed-irrelevante" name="RelConfig" guid="" lastUpdate="2020-06-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
    <Procedure><Info><Name>RelConfig</Name></Info></Procedure>
  </GxLegacyPayload>
</Object>
'@
    [System.IO.File]::WriteAllText((Join-Path $procFolder 'RelConfig.xml'), $seed, (New-Object System.Text.UTF8Encoding($false)))

    $summary = Invoke-SyncJson -SyncArgs @('-InputPath', $fixture, '-DestinationRoot', $dest)
    if ($summary.SkippedOlderLastUpdate -lt 1) { throw "Case2: SkippedOlderLastUpdate=$($summary.SkippedOlderLastUpdate) (expected >=1; sentinel < real date)." }
    if (@($summary.SkippedOlderLastUpdateNames) -notcontains 'Procedure:RelConfig') { throw "Case2: Procedure:RelConfig should be among the skipped ones; got: $($summary.SkippedOlderLastUpdateNames -join ', ')." }
} finally {
    if (Test-Path -LiteralPath $work2) { Remove-Item -LiteralPath $work2 -Recurse -Force }
}

# =====================================================================================
# Case 3 — MIXED package -> throw and kb-source-metadata.md NOT created
# =====================================================================================
$work3 = New-WorkRoot
try {
    $mixed = Join-Path $work3 'misto.xml'
    Write-Iso88591File -Path $mixed -Content @'
<?xml version='1.0' encoding='iso-8859-1'?>
<ExportFile>
  <GXObject><Transaction><Info><Name>Cliente</Name></Info></Transaction></GXObject>
  <Objects><Object type="00000000-0000-0000-0000-000000000001" name="Moderno"/></Objects>
</ExportFile>
'@
    $dest = Join-Path $work3 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)
    $meta = Join-Path $work3 'kb-source-metadata.md'

    Invoke-SyncExpectFailure -SyncArgs @('-InputPath', $mixed, '-DestinationRoot', $dest, '-KbMetadataPath', $meta)
    if (Test-Path -LiteralPath $meta) { throw 'Case3: a mixed package should NOT create kb-source-metadata.md.' }
} finally {
    if (Test-Path -LiteralPath $work3) { Remove-Item -LiteralPath $work3 -Recurse -Force }
}

# =====================================================================================
# Case 4 — legacy tag outside the registry + KbMetadataPath -> throw and metadata NOT altered
# =====================================================================================
$work4 = New-WorkRoot
try {
    $unknown = Join-Path $work4 'unknown.xml'
    Write-Iso88591File -Path $unknown -Content @'
<?xml version='1.0' encoding='iso-8859-1'?>
<ExportFile>
  <KMW><MaxGxBuildSaved>2601</MaxGxBuildSaved></KMW>
  <GXObject><TagInexistente><Info><Name>NaoRegistrado</Name></Info></TagInexistente></GXObject>
</ExportFile>
'@
    $dest = Join-Path $work4 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)

    # 4a — metadata absent: should not be created
    $metaAbsent = Join-Path $work4 'kb-source-metadata.md'
    Invoke-SyncExpectFailure -SyncArgs @('-InputPath', $unknown, '-DestinationRoot', $dest, '-KbMetadataPath', $metaAbsent)
    if (Test-Path -LiteralPath $metaAbsent) { throw 'Case4a: an unknown tag should NOT create kb-source-metadata.md.' }

    # 4b — pre-existing metadata: its content should not be altered (fail-closed before metadata)
    $metaPre = Join-Path $work4 'kb-source-metadata-pre.md'
    $sentinelContent = "SENTINELA-INTACTA-{0}" -f ([guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($metaPre, $sentinelContent, (New-Object System.Text.UTF8Encoding($false)))
    Invoke-SyncExpectFailure -SyncArgs @('-InputPath', $unknown, '-DestinationRoot', $dest, '-KbMetadataPath', $metaPre)
    if ((Get-Content -LiteralPath $metaPre -Raw) -ne $sentinelContent) { throw 'Case4b: the pre-existing kb-source-metadata.md was altered despite the fail-closed behavior.' }
} finally {
    if (Test-Path -LiteralPath $work4) { Remove-Item -LiteralPath $work4 -Recurse -Force }
}

# =====================================================================================
# Case 5 — GeneXus 8 shapes: WebPanel and ungrouped subtypes; a later export keeps earlier subtypes
# =====================================================================================
$work5 = New-WorkRoot
try {
    $catalog = Get-Content -LiteralPath (Join-Path $scriptsRoot 'gx-object-type-catalog.json') -Raw | ConvertFrom-Json
    $webPanelGuid = [string]$catalog.types.WebPanel.objectTypeGuid
    $first = Join-Path $work5 'RptOrders_1.xml'
    Write-Iso88591File -Path $first -Content @'
<?xml version='1.0' encoding='iso-8859-1'?>
<ExportFile>
  <KMW><MajorVersion>2</MajorVersion><MinorVersion>1</MinorVersion><MaxGxBuildSaved>1595</MaxGxBuildSaved></KMW>
  <GXObject><WebPanel><Info><Name>WpOrders</Name></Info><LastUpdate>2013-02-18 22:48:04GMT</LastUpdate></WebPanel></GXObject>
  <GXObject>
    <Group>
      <Info>
        <Name> </Name>
      </Info>
      <Subtype>
        <Name>SubC</Name>
        <Supertype>SuperC</Supertype>
      </Subtype>
      <Subtype>
        <Name>SubB</Name>
        <Supertype>SuperB</Supertype>
      </Subtype>
    </Group>
  </GXObject>
</ExportFile>
'@
    # Indented like a real export: the payload of SubC must not depend on how many siblings it had.
    $second = Join-Path $work5 'WpOrders_1.xml'
    Write-Iso88591File -Path $second -Content @'
<?xml version='1.0' encoding='iso-8859-1'?>
<ExportFile>
  <KMW><MajorVersion>2</MajorVersion><MinorVersion>1</MinorVersion><MaxGxBuildSaved>1595</MaxGxBuildSaved></KMW>
  <GXObject>
    <Group>
      <Info>
        <Name> </Name>
      </Info>
      <Subtype>
        <Name>SubC</Name>
        <Supertype>SuperC</Supertype>
      </Subtype>
    </Group>
  </GXObject>
</ExportFile>
'@
    $dest = Join-Path $work5 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)

    $summary = Invoke-SyncJson -SyncArgs @('-InputPath', $first, '-DestinationRoot', $dest)
    if ($summary.Created -ne 3) { throw "Case5: Created=$($summary.Created) (expected 3: WebPanel + 2 ungrouped subtypes)." }

    $wpFile = Join-Path (Join-Path $dest 'WebPanel') 'WpOrders.xml'
    if (-not (Test-Path -LiteralPath $wpFile)) { throw "Case5: WebPanel not materialized at $wpFile." }
    [xml]$wpXml = Get-Content -LiteralPath $wpFile -Raw
    if ($wpXml.DocumentElement.GetAttribute('type') -ne $webPanelGuid) { throw "Case5: WebPanel type='$($wpXml.DocumentElement.GetAttribute('type'))' (expected $webPanelGuid)." }

    $subBFile = Join-Path (Join-Path $dest 'SubTypeGroup') 'SubB.xml'
    foreach ($name in @('SubC', 'SubB')) {
        $file = Join-Path (Join-Path $dest 'SubTypeGroup') "$name.xml"
        if (-not (Test-Path -LiteralPath $file)) { throw "Case5: ungrouped subtype not materialized at $file." }
        [xml]$subXml = Get-Content -LiteralPath $file -Raw
        $subtypeNames = @($subXml.DocumentElement.SelectNodes('./GxLegacyPayload/Group/Subtype/Name') | ForEach-Object { $_.InnerText })
        if (($subtypeNames -join ',') -ne $name) { throw "Case5: $name.xml should carry only Subtype '$name'; got '$($subtypeNames -join ',')'." }
    }
    $subBBefore = Get-Content -LiteralPath $subBFile -Raw

    $summary2 = Invoke-SyncJson -SyncArgs @('-InputPath', $second, '-DestinationRoot', $dest)
    if ($summary2.Unchanged -ne 1 -or $summary2.Created -ne 0 -or $summary2.Updated -ne 0) { throw "Case5: second export should leave SubC unchanged (Unchanged=$($summary2.Unchanged), Created=$($summary2.Created), Updated=$($summary2.Updated))." }
    if (-not (Test-Path -LiteralPath $subBFile) -or (Get-Content -LiteralPath $subBFile -Raw) -ne $subBBefore) { throw 'Case5: a later export without SubB must not remove or change SubTypeGroup/SubB.xml.' }
} finally {
    if (Test-Path -LiteralPath $work5) { Remove-Item -LiteralPath $work5 -Recurse -Force }
}

Write-Output 'MIMIR_SYNC_LEGACY_EXPORT_FULLSNAPSHOT_SELFTEST_OK'
exit 0
