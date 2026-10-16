#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the `.xpw` source marker in kb-source-metadata.md.

.DESCRIPTION
    Proves that a sync of a GeneXus `.xpw` text export (GeneXus 7.0 and earlier) records where the
    export came from, so a KMW 1.x export is not mistaken for a modern version:
    (a) a real sync of a `.xpw` (child process, -KbMetadataPath) creates the metadata with
        `source_export_format: xpw`, KMW MajorVersion 1 / MinorVersion 5, an empty Build, and the
        dedicated `.xpw` hint instead of the GeneXus 9 one;
    (b) a `.xpw` sync over metadata left by a modern export replaces the KMW values with the
        export's own (no stale modern Build) and keeps the Source identity;
    (c) NON-REGRESSION: a modern complete export never adds `source_export_format` and keeps its
        values and status;
    (d) a later classic XML sync (real sync) over metadata that carries the marker rewrites it to
        `xml`.
    Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
. (Join-Path $repoRoot 'tests/fixtures/GeneXusXpwFixtureSupport.ps1')
. (Join-Path $repoRoot 'tests/fixtures/GeneXusLegacyExportFileFixtureSupport.ps1')
. (Join-Path $scriptsRoot 'MimirKbSourceMetadataEditSupport.ps1')
. (Join-Path $scriptsRoot 'GeneXusXpwExportFileSupport.ps1')

$syncScript = Join-Path $scriptsRoot 'Sync-GeneXusXpzToXml.ps1'
$xpwHintNeedle = 'GeneXus .xpw text export'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-WorkRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('xpw-meta-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $root)
    return $root
}

function Get-TableValue {
    param([string]$Text, [string]$Field)
    $match = [regex]::Match($Text, ('(?m)^\|\s*{0}\s*\|\s*(.*?)\s*\|\s*$' -f [regex]::Escape($Field)))
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

function New-ModernCompleteXmlDoc {
    [xml]$doc = @'
<ExportFile>
  <KMW>
    <MajorVersion>18</MajorVersion>
    <MinorVersion>0</MinorVersion>
    <Build>250000</Build>
  </KMW>
  <Source kb="11111111-1111-1111-1111-111111111111" username="dev" UNCPath="\\srv\kb">
    <Version guid="22222222-2222-2222-2222-222222222222" name="Trunk"/>
  </Source>
</ExportFile>
'@
    return $doc
}

$work = New-WorkRoot
try {
    # (a) real sync of a .xpw with -KbMetadataPath.
    $xpw = New-GeneXusXpwFixtureFile -Path (Join-Path $work 'shop.xpw') -Lines (Get-GeneXusXpwSyncFixtureLines)
    $dest = Join-Path $work 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)
    $metaA = Join-Path $work 'kb-source-metadata.md'
    $stdout = & pwsh -NoProfile -File $syncScript -InputPath $xpw -DestinationRoot $dest -KbMetadataPath $metaA 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "(a): the .xpw sync with -KbMetadataPath should exit 0; got $LASTEXITCODE"
    Assert-True (Test-Path -LiteralPath $metaA) '(a): kb-source-metadata.md should be created.'
    $textA = Get-Content -LiteralPath $metaA -Raw
    Assert-True ($textA -match '(?m)^source_export_format: xpw\r?$') "(a): the metadata should record 'source_export_format: xpw'. Got:`n$textA"
    Assert-True ((Get-TableValue $textA 'MajorVersion') -eq '1' -and (Get-TableValue $textA 'MinorVersion') -eq '5') '(a): KMW MajorVersion 1 / MinorVersion 5 should be recorded.'
    Assert-True ((Get-TableValue $textA 'Build') -eq '') "(a): Build should be empty (KMW 1.x has no build); got '$(Get-TableValue $textA 'Build')'."
    $summaryA = @($stdout | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1] | ConvertFrom-Json
    $warningsA = @($summaryA.Warnings)
    Assert-True (@($warningsA | Where-Object { $_ -like "*$xpwHintNeedle*" }).Count -eq 1) "(a): the .xpw hint should be reported; got: $($warningsA -join ' || ')"
    Assert-True (@($warningsA | Where-Object { $_ -like '*legacy GeneXus 9 export*' }).Count -eq 0) '(a): the GeneXus 9 hint should not be reported for a .xpw.'

    # (b) .xpw over metadata left by a modern export: KMW from the export only, Source kept.
    $metaB = Join-Path $work 'meta-b.md'
    [void](Update-MimirKbSourceMetadataFromSync -XmlDocument (New-ModernCompleteXmlDoc) -SourceXpzPath 'C:\fake\modern.xpz' -MetadataPath $metaB)
    [xml]$xpwDoc = Read-GeneXusXpwExportFile -Path $xpw
    $resultB = Update-MimirKbSourceMetadataFromSync -XmlDocument $xpwDoc -SourceXpzPath $xpw -MetadataPath $metaB -IsLegacyExport $true -SourceExportFormat 'xpw'
    $textB = Get-Content -LiteralPath $metaB -Raw
    Assert-True ($textB -match '(?m)^source_export_format: xpw\r?$') '(b): the surgical update should add source_export_format: xpw.'
    Assert-True ((Get-TableValue $textB 'MajorVersion') -eq '1' -and (Get-TableValue $textB 'MinorVersion') -eq '5') '(b): KMW should come from the .xpw (1.5), not from the previous modern export.'
    Assert-True ((Get-TableValue $textB 'Build') -eq '') "(b): the stale modern Build should not survive a .xpw sync; got '$(Get-TableValue $textB 'Build')'."
    Assert-True ((Get-TableValue $textB 'kb (GUID)') -eq '11111111-1111-1111-1111-111111111111') '(b): the Source identity should be preserved.'
    Assert-True ($resultB.MetadataStatus -eq 'partial-preserved') "(b): status should be partial-preserved; got $($resultB.MetadataStatus)."

    # (c) modern complete export: no marker, values and status unchanged.
    $metaC = Join-Path $work 'meta-c.md'
    $resultC = Update-MimirKbSourceMetadataFromSync -XmlDocument (New-ModernCompleteXmlDoc) -SourceXpzPath 'C:\fake\modern.xpz' -MetadataPath $metaC -SourceExportFormat 'xml'
    $resultC2 = Update-MimirKbSourceMetadataFromSync -XmlDocument (New-ModernCompleteXmlDoc) -SourceXpzPath 'C:\fake\modern.xpz' -MetadataPath $metaC -SourceExportFormat 'xml'
    $textC = Get-Content -LiteralPath $metaC -Raw
    Assert-True ($textC -notmatch 'source_export_format') '(c): a modern export should not add source_export_format (template or surgical update).'
    Assert-True ($resultC.MetadataStatus -eq 'complete' -and $resultC2.MetadataStatus -eq 'complete' -and @($resultC2.Warnings).Count -eq 0) '(c): a complete modern export should stay complete with no warnings.'
    Assert-True ((Get-TableValue $textC 'Build') -eq '250000') '(c): the modern Build should be recorded.'

    # (d) a later XML sync (real sync of a classic GeneXus 9 XML) over metadata carrying the marker
    # rewrites it to xml.
    $classicXml = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $work 'legacy.xml')
    $destD = Join-Path $work 'corpus-d'
    [void](New-Item -ItemType Directory -Path $destD)
    & pwsh -NoProfile -File $syncScript -InputPath $classicXml -DestinationRoot $destD -KbMetadataPath $metaB 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "(d): the classic XML sync should exit 0; got $LASTEXITCODE"
    $textD = Get-Content -LiteralPath $metaB -Raw
    Assert-True ($textD -match '(?m)^source_export_format: xml\r?$') "(d): a later XML sync should rewrite the marker to 'xml'. Got:`n$textD"
    Assert-True (@([regex]::Matches($textD, '(?m)^source_export_format:')).Count -eq 1) '(d): the marker should appear once.'
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Write-Output 'MIMIR_KB_SOURCE_METADATA_XPW_SELFTEST_OK'
exit 0
