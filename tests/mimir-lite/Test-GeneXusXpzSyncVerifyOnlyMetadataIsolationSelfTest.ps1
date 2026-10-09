#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for metadata isolation during modern and legacy VerifyOnly full snapshots.

.DESCRIPTION
    Builds synthetic packages and matching XML corpora in temporary directories, then verifies
    that -VerifyOnly -FullSnapshot leaves both the corpus and pre-existing kb-source-metadata.md
    byte-for-byte unchanged while retaining the expected machine-readable report.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$syncScript = Join-Path $scriptsRoot 'Sync-GeneXusXpzToXml.ps1'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'GeneXusLegacyExportFileFixtureSupport.ps1')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-verify-only-metadata-isolation-{0}' -f ([guid]::NewGuid().ToString('N')))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $script:utf8NoBom)
}

function New-ExistingMetadata {
    param([string]$Path)

    $content = @'
---
name: KB Source Metadata
description: VerifyOnly metadata isolation self-test
updated: 2020-01-01T00:00:00.0000000Z
last_xpz_materialization_run_at: 2020-01-01T00:00:00.0000000Z
source_xpz: C:\Old\Package.xpz
source_refresh_status: partial-preserved
---

## KMW

| Field | Value |
|---|---|
| MajorVersion | 17 |
| MinorVersion | 0 |
| Build | 100 |

## Source

| Field | Value |
|---|---|
| kb (GUID) | {11111111-1111-1111-1111-111111111111} |
| username | old-user |
| UNCPath | \\old\share |

## Source/Version

| Field | Value |
|---|---|
| guid | {22222222-2222-2222-2222-222222222222} |
| name | OldVersion |
'@
    Write-Utf8NoBom -Path $Path -Content $content
}

function New-ModernPackage {
    param([string]$Path)

    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <KMW><MajorVersion>18</MajorVersion><MinorVersion>1</MinorVersion><Build>200</Build></KMW>
  <Source kb="{33333333-3333-3333-3333-333333333333}" username="verify-user" UNCPath="\\verify\share">
    <Version guid="{44444444-4444-4444-4444-444444444444}" name="VerifyVersion" />
  </Source>
  <Objects>
    <Object type="84a12160-f59b-4ad7-a683-ea4481ac23e9" name="VerifyOnlyModernProcedure" guid="55555555-5555-5555-5555-555555555555" lastUpdate="2026-01-01T00:00:00.0000000Z">
      <Source><![CDATA[// synthetic procedure]]></Source>
    </Object>
  </Objects>
  <Attributes />
</ExportFile>
'@
    Write-Utf8NoBom -Path $Path -Content $xml
}

function Invoke-Sync {
    param([string[]]$SyncArgs)

    $stdout = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:syncScript @SyncArgs 2>$null
    $exitCode = $LASTEXITCODE
    $stdoutText = ($stdout | Out-String).Trim()
    $summary = $null
    if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
        try { $summary = $stdoutText | ConvertFrom-Json } catch { $summary = $null }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = $stdoutText
        Summary = $summary
    }
}

function Get-CorpusFileHashes {
    param([string]$Root)

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)
    $snapshot = foreach ($file in $files) {
        [pscustomobject]@{
            RelativePath = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    return @($snapshot)
}

function Test-ByteArraysEqual {
    param([byte[]]$Left, [byte[]]$Right)

    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }
    return $true
}

function Test-NormalSyncMetadataControl {
    param(
        [string]$Name,
        [string]$PackagePath,
        [string]$Corpus,
        [string]$CaseRoot,
        [string]$ExpectedMetadataStatus
    )

    $controlMetadataPath = Join-Path $CaseRoot 'normal-sync-kb-source-metadata.md'
    $controlReportPath = Join-Path $CaseRoot 'normal-sync-report.json'
    New-ExistingMetadata -Path $controlMetadataPath
    $metadataBefore = [System.IO.File]::ReadAllBytes($controlMetadataPath)

    $control = Invoke-Sync -SyncArgs @(
        '-InputPath', $PackagePath,
        '-DestinationRoot', $Corpus,
        '-FullSnapshot',
        '-KbMetadataPath', $controlMetadataPath,
        '-ReportPath', $controlReportPath,
        '-KeepReport'
    )

    if ($control.ExitCode -ne 0) {
        Add-Failure "$Name normal-sync control failed (exit=$($control.ExitCode)); stdout=$($control.Stdout)"
    }
    if ($null -eq $control.Summary) {
        Add-Failure "$Name normal-sync control did not produce a parseable stdout summary."
    } else {
        if ($control.Summary.VerifyOnly -ne $false) {
            Add-Failure "$Name normal-sync control summary VerifyOnly should be false; got $($control.Summary.VerifyOnly)."
        }
        if ($control.Summary.FullSnapshot -ne $true) {
            Add-Failure "$Name normal-sync control summary FullSnapshot should be true; got $($control.Summary.FullSnapshot)."
        }
    }

    if (-not (Test-Path -LiteralPath $controlMetadataPath -PathType Leaf)) {
        Add-Failure "$Name normal-sync control removed pre-existing kb-source-metadata.md."
    } else {
        $metadataAfter = [System.IO.File]::ReadAllBytes($controlMetadataPath)
        if (Test-ByteArraysEqual -Left $metadataBefore -Right $metadataAfter) {
            Add-Failure "$Name normal-sync control left pre-existing kb-source-metadata.md bytes unchanged; expected a metadata refresh."
        }
    }

    if (-not (Test-Path -LiteralPath $controlReportPath -PathType Leaf)) {
        Add-Failure "$Name normal-sync control did not retain the requested report despite -KeepReport."
        return
    }

    try {
        $controlReport = Get-Content -LiteralPath $controlReportPath -Raw | ConvertFrom-Json
    } catch {
        Add-Failure "$Name normal-sync control report was not valid JSON: $($_.Exception.Message)"
        return
    }

    if ($controlReport.Summary.VerifyOnly -ne $false) {
        Add-Failure "$Name normal-sync control report Summary.VerifyOnly should be false; got $($controlReport.Summary.VerifyOnly)."
    }
    if ($controlReport.KbMetadataStatus -ne $ExpectedMetadataStatus) {
        Add-Failure "$Name normal-sync control report KbMetadataStatus should be '$ExpectedMetadataStatus'; got '$($controlReport.KbMetadataStatus)'."
    }
}

function Test-VerifyOnlyCase {
    param(
        [string]$Name,
        [string]$PackagePath,
        [string]$CaseRoot,
        [bool]$ExpectedLegacy,
        [string]$ExpectedInterpretation,
        [string]$ExpectedMetadataStatus,
        [string]$ExpectedNormalSyncMetadataStatus
    )

    $corpus = Join-Path $CaseRoot 'KbObjectsXml'
    [void](New-Item -ItemType Directory -Path $corpus -Force)
    $metadataPath = Join-Path $CaseRoot 'kb-source-metadata.md'
    $reportPath = Join-Path $CaseRoot 'verify-report.json'
    New-ExistingMetadata -Path $metadataPath

    # Materialize the fixture first so the VerifyOnly full-snapshot check starts from a matching corpus.
    $setup = Invoke-Sync -SyncArgs @('-InputPath', $PackagePath, '-DestinationRoot', $corpus)
    if ($setup.ExitCode -ne 0) {
        Add-Failure "$Name fixture setup failed before VerifyOnly (exit=$($setup.ExitCode)); stdout=$($setup.Stdout)"
        return
    }

    $metadataBefore = [System.IO.File]::ReadAllBytes($metadataPath)
    $corpusBefore = @(Get-CorpusFileHashes -Root $corpus)
    if ($corpusBefore.Count -eq 0) {
        Add-Failure "$Name fixture setup produced an empty corpus; VerifyOnly was not exercised."
        return
    }

    $result = Invoke-Sync -SyncArgs @(
        '-InputPath', $PackagePath,
        '-DestinationRoot', $corpus,
        '-VerifyOnly',
        '-FullSnapshot',
        '-KbMetadataPath', $metadataPath,
        '-ReportPath', $reportPath,
        '-KeepReport'
    )

    if ($result.ExitCode -ne 0) {
        Add-Failure "$Name VerifyOnly full-snapshot run failed (exit=$($result.ExitCode)); expected a matching-corpus success; stdout=$($result.Stdout)"
    }

    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        Add-Failure "$Name VerifyOnly removed pre-existing kb-source-metadata.md."
    } else {
        $metadataAfter = [System.IO.File]::ReadAllBytes($metadataPath)
        if (-not (Test-ByteArraysEqual -Left $metadataBefore -Right $metadataAfter)) {
            Add-Failure "$Name VerifyOnly changed pre-existing kb-source-metadata.md bytes; expected exact byte preservation."
        }
    }

    $corpusAfter = @(Get-CorpusFileHashes -Root $corpus)
    if ($corpusBefore.Count -ne $corpusAfter.Count) {
        Add-Failure "$Name VerifyOnly changed the corpus file count ($($corpusBefore.Count) before, $($corpusAfter.Count) after)."
    } else {
        for ($i = 0; $i -lt $corpusBefore.Count; $i++) {
            if ($corpusBefore[$i].RelativePath -cne $corpusAfter[$i].RelativePath -or $corpusBefore[$i].Sha256 -cne $corpusAfter[$i].Sha256) {
                Add-Failure "$Name VerifyOnly changed corpus file/hash at sorted entry $i ($($corpusBefore[$i].RelativePath) vs. $($corpusAfter[$i].RelativePath))."
            }
        }
    }

    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        Add-Failure "$Name VerifyOnly did not retain the requested report despite -KeepReport."
        Test-NormalSyncMetadataControl -Name $Name -PackagePath $PackagePath -Corpus $corpus -CaseRoot $CaseRoot `
            -ExpectedMetadataStatus $ExpectedNormalSyncMetadataStatus
        return
    }

    try {
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    } catch {
        Add-Failure "$Name retained report was not valid JSON: $($_.Exception.Message)"
        Test-NormalSyncMetadataControl -Name $Name -PackagePath $PackagePath -Corpus $corpus -CaseRoot $CaseRoot `
            -ExpectedMetadataStatus $ExpectedNormalSyncMetadataStatus
        return
    }

    if ($report.Summary.VerifyOnly -ne $true) { Add-Failure "$Name report Summary.VerifyOnly should be true." }
    if ($report.Summary.FullSnapshot -ne $true) { Add-Failure "$Name report Summary.FullSnapshot should be true." }
    if ([bool]$report.Summary.LegacyFormatDetected -ne $ExpectedLegacy) {
        Add-Failure "$Name report Summary.LegacyFormatDetected should be $ExpectedLegacy; got $($report.Summary.LegacyFormatDetected)."
    }
    if ($report.Summary.MaterializationInterpretation -ne $ExpectedInterpretation) {
        Add-Failure "$Name report MaterializationInterpretation should be '$ExpectedInterpretation'; got '$($report.Summary.MaterializationInterpretation)'."
    }
    if ($report.Summary.FullSnapshotMissing -ne 0 -or $report.Summary.FullSnapshotExtra -ne 0) {
        Add-Failure "$Name report should show a matching full snapshot (missing=$($report.Summary.FullSnapshotMissing), extra=$($report.Summary.FullSnapshotExtra))."
    }
    if ($report.Summary.MissingAfterVerification -ne 0 -or $report.Summary.MismatchesAfterVerification -ne 0) {
        Add-Failure "$Name report should show successful package verification (missing=$($report.Summary.MissingAfterVerification), mismatch=$($report.Summary.MismatchesAfterVerification))."
    }
    if ($report.KbMetadataStatus -ne $ExpectedMetadataStatus) {
        Add-Failure "$Name report KbMetadataStatus should be '$ExpectedMetadataStatus' when VerifyOnly suppresses metadata refresh; got '$($report.KbMetadataStatus)'."
    }

    Test-NormalSyncMetadataControl -Name $Name -PackagePath $PackagePath -Corpus $corpus -CaseRoot $CaseRoot `
        -ExpectedMetadataStatus $ExpectedNormalSyncMetadataStatus
}

try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)

    $modernRoot = Join-Path $tempRoot 'modern'
    [void](New-Item -ItemType Directory -Path $modernRoot -Force)
    $modernPackage = Join-Path $modernRoot 'modern-export.xml'
    New-ModernPackage -Path $modernPackage
    Test-VerifyOnlyCase -Name 'Modern' -PackagePath $modernPackage -CaseRoot $modernRoot `
        -ExpectedLegacy $false -ExpectedInterpretation 'verify-only' -ExpectedMetadataStatus 'not-requested' `
        -ExpectedNormalSyncMetadataStatus 'complete'

    $legacyRoot = Join-Path $tempRoot 'legacy'
    [void](New-Item -ItemType Directory -Path $legacyRoot -Force)
    $legacyPackage = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $legacyRoot 'legacy-export.xml')
    Test-VerifyOnlyCase -Name 'Legacy' -PackagePath $legacyPackage -CaseRoot $legacyRoot `
        -ExpectedLegacy $true -ExpectedInterpretation 'legacy-export-adapted' -ExpectedMetadataStatus 'not-requested' `
        -ExpectedNormalSyncMetadataStatus 'partial-preserved'

    if ($failures.Count -gt 0) {
        Write-Output "FAILURES ($($failures.Count)):"
        $failures | ForEach-Object { Write-Output " - $_" }
        exit 1
    }

    Write-Output 'OK: Test-GeneXusXpzSyncVerifyOnlyMetadataIsolationSelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
