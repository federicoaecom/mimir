#requires -Version 7.4
<#
.SYNOPSIS
    Surgical mutation of kb-source-metadata.md under sync workflow authority.

.DESCRIPTION
    Updates only the materialization fields in the frontmatter and the values of the
    KMW, Source, and Source/Version tables, preserving the remaining lines (including
    last_setup_audit_run_at and any other frontmatter, section, or text outside the
    sync's scope).

    Sync authority (frontmatter): updated, last_xpz_materialization_run_at,
    source_xpz, source_refresh_status. Other frontmatter keys, extra sections
    (e.g. ## Usage), and the existing file's formatting/EOL remain intact during the
    surgical update; creating a missing file still uses the full template.
#>

Set-StrictMode -Version Latest

$utf8NoBomEncodingSupportPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$script:SyncOwnedFrontmatterFieldNames = @(
    'updated'
    'last_xpz_materialization_run_at'
    'source_xpz'
    'source_refresh_status'
)

# Exact hint emitted on the legacy GeneXus 9 export branch (replaces the generic
# missing-KMW/Source warning). Stable literal: the legacy metadata self-test matches this string
# and validates the absence of the generic one. A legacy export has no <Source> block and uses
# KMW/MaxGxBuildSaved as Build.
$script:LegacyExportMetadataHintMessage = 'KbMetadataPath: legacy GeneXus 9 export detected (no <Source> block); Build filled from KMW/MaxGxBuildSaved and Source identity preserved from the previous baseline when present; kb-source-metadata.md received a partial refresh.'

function Get-KbSourceMetadataSnapshot {
    param([string]$MetadataPath)

    $snapshot = [ordered]@{
        MajorVersion = ''
        MinorVersion = ''
        Build        = ''
        Kb           = ''
        Username     = ''
        UNCPath      = ''
        VersionGuid  = ''
        VersionName  = ''
    }

    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
        return [pscustomobject]$snapshot
    }

    $section = ''
    foreach ($line in Get-Content -LiteralPath $MetadataPath) {
        if ($line -match '^##\s+KMW\b') {
            $section = 'KMW'
            continue
        }

        if ($line -match '^##\s+Source/Version\b') {
            $section = 'SourceVersion'
            continue
        }

        if ($line -match '^##\s+Source\b') {
            $section = 'Source'
            continue
        }

        if ($line -match '^##\s+') {
            $section = ''
            continue
        }

        switch ($section) {
            'KMW' {
                if ($line -match '^\|\s*MajorVersion\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.MajorVersion = $Matches[1].Trim()
                    continue
                }
                if ($line -match '^\|\s*MinorVersion\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.MinorVersion = $Matches[1].Trim()
                    continue
                }
                if ($line -match '^\|\s*Build\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.Build = $Matches[1].Trim()
                    continue
                }
            }
            'Source' {
                if ($line -match '^\|\s*kb \(GUID\)\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.Kb = $Matches[1].Trim()
                    continue
                }
                if ($line -match '^\|\s*username\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.Username = $Matches[1].Trim()
                    continue
                }
                if ($line -match '^\|\s*UNCPath\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.UNCPath = $Matches[1].Trim()
                    continue
                }
            }
            'SourceVersion' {
                if ($line -match '^\|\s*guid\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.VersionGuid = $Matches[1].Trim()
                    continue
                }
                if ($line -match '^\|\s*name\s*\|\s*(.*?)\s*\|\s*$') {
                    $snapshot.VersionName = $Matches[1].Trim()
                    continue
                }
            }
        }
    }

    return [pscustomobject]$snapshot
}

function Set-KbMetadataMarkdownTableValue {
    param(
        [string[]]$TableLines,
        [string]$SectionName,
        [string]$TableFieldName,
        [string]$Value
    )

    $result = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    $updated = $false
    $sectionPattern = '^\s*##\s+{0}\s*$' -f [regex]::Escape($SectionName)

    foreach ($line in $TableLines) {
        if ([regex]::IsMatch($line, '^\s*##\s+')) {
            $inSection = [regex]::IsMatch($line, $sectionPattern)
            $result.Add($line) | Out-Null
            continue
        }

        if ($inSection) {
            $cells = @($line -split '\|')
            if ($cells.Count -ge 4) {
                $name = $cells[1].Trim()
                if ($name -ieq $TableFieldName -and $name -notmatch '^-+$') {
                    $result.Add("| $name | $Value |") | Out-Null
                    $updated = $true
                    continue
                }
            }
        }

        $result.Add($line) | Out-Null
    }

    if (-not $updated) {
        throw "BLOCK: field '$TableFieldName' not found in section '## $SectionName'."
    }

    return $result.ToArray()
}

function Set-KbMetadataFrontmatterField {
    param(
        [Parameter(Mandatory = $true)]
        $RowBuffer,

        [Parameter(Mandatory = $true)]
        [string]$FrontmatterKey,

        [Parameter(Mandatory = $true)]
        [string]$FrontmatterValue
    )

    if ($RowBuffer -isnot [System.Collections.Generic.List[string]]) {
        throw "BLOCK: RowBuffer must be List[string]; received=$($RowBuffer.GetType().FullName)"
    }

    $newFieldLine = "${FrontmatterKey}: $FrontmatterValue"
    $fieldPattern = '^\s*{0}\s*[:=]\s*.+$' -f [regex]::Escape($FrontmatterKey)

    for ($i = 0; $i -lt $RowBuffer.Count; $i++) {
        if ($RowBuffer[$i] -match $fieldPattern) {
            $RowBuffer[$i] = $newFieldLine
            return $true
        }
    }

    $insertAt = -1
    $frontmatterClose = -1
    $hasFrontmatter = ($RowBuffer.Count -gt 0 -and $RowBuffer[0].Trim() -eq '---')

    if ($hasFrontmatter) {
        for ($i = 1; $i -lt $RowBuffer.Count; $i++) {
            if ($RowBuffer[$i].Trim() -eq '---') {
                $frontmatterClose = $i
                break
            }
        }

        if ($frontmatterClose -gt 0) {
            $insertAt = $frontmatterClose
            for ($j = 1; $j -lt $frontmatterClose; $j++) {
                if ($RowBuffer[$j] -match '^\s*last_xpz_materialization_run_at\s*[:=]') {
                    $insertAt = $j + 1
                }
            }
        }
    } else {
        for ($i = 0; $i -lt $RowBuffer.Count; $i++) {
            if ($RowBuffer[$i] -match '^\s*##\s+') {
                $insertAt = $i
                break
            }
        }

        if ($insertAt -lt 0) {
            $insertAt = $RowBuffer.Count
        }

        for ($j = 0; $j -lt $insertAt; $j++) {
            if ($RowBuffer[$j] -match '^\s*last_xpz_materialization_run_at\s*[:=]') {
                $insertAt = $j + 1
            }
        }
    }

    if ($insertAt -lt 0) {
        if ($frontmatterClose -gt 0) {
            $insertAt = $frontmatterClose
        } else {
            $insertAt = 0
        }
    }

    $RowBuffer.Insert($insertAt, $newFieldLine)
    return $true
}

function Write-NewKbSourceMetadataTemplate {
    param(
        [string]$MetadataPath,
        [string]$SourceXpzPath,
        [string]$Timestamp,
        [string]$MetadataStatus,
        [string]$MajorVersion,
        [string]$MinorVersion,
        [string]$Build,
        [string]$KbGuid,
        [string]$Username,
        [string]$UncPath,
        [string]$VersionGuid,
        [string]$VersionName
    )

    $content = @"
---
name: KB Source Metadata
description: GeneXus version, KB identity, and KB version read from the IDE's most recent XPZ export
updated: $Timestamp
last_xpz_materialization_run_at: $Timestamp
source_xpz: $SourceXpzPath
source_refresh_status: $MetadataStatus
---

## KMW

| Field        | Value          |
|---|---|
| MajorVersion | $MajorVersion  |
| MinorVersion | $MinorVersion  |
| Build        | $Build         |

## Source

| Field    | Value       |
|---|---|
| kb (GUID) | $KbGuid    |
| username  | $Username  |
| UNCPath   | $UncPath   |

## Source/Version

| Field | Value        |
|---|---|
| guid  | $VersionGuid |
| name  | $VersionName |

## Usage

These values identify the GeneXus version (KMW), the KB (Source), and the KB version
(Source/Version) that produced the official snapshot in ``KbObjectsXml``. The sync
refreshes them from each XPZ exported by the GeneXus IDE; read them to confirm which KB
and version the snapshot belongs to.
"@

    $utf8NoBom = (Get-Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($MetadataPath, $content, $utf8NoBom)
}

function Update-MimirKbSourceMetadataFromSync {
    param(
        [xml]$XmlDocument,
        [string]$SourceXpzPath,
        [string]$MetadataPath,
        [bool]$IsLegacyExport = $false
    )

    $kmwNode = $XmlDocument.SelectSingleNode('/ExportFile/KMW')
    $sourceNode = $XmlDocument.SelectSingleNode('/ExportFile/Source')
    $versionNode = $XmlDocument.SelectSingleNode('/ExportFile/Source/Version')

    $existingMetadata = Get-KbSourceMetadataSnapshot -MetadataPath $MetadataPath

    $packageMajorVersion = if ($null -ne $kmwNode -and $null -ne $kmwNode.SelectSingleNode('MajorVersion')) { $kmwNode.SelectSingleNode('MajorVersion').InnerText } else { '' }
    $packageMinorVersion = if ($null -ne $kmwNode -and $null -ne $kmwNode.SelectSingleNode('MinorVersion')) { $kmwNode.SelectSingleNode('MinorVersion').InnerText } else { '' }
    $packageBuild = if ($null -ne $kmwNode -and $null -ne $kmwNode.SelectSingleNode('Build')) { $kmwNode.SelectSingleNode('Build').InnerText } else { '' }

    $packageKbGuid = if ($null -ne $sourceNode) { $sourceNode.GetAttribute('kb') } else { '' }
    $packageUsername = if ($null -ne $sourceNode) { $sourceNode.GetAttribute('username') } else { '' }
    $packageUncPath = if ($null -ne $sourceNode) { $sourceNode.GetAttribute('UNCPath') } else { '' }
    $packageVersionGuid = if ($null -ne $versionNode) { $versionNode.GetAttribute('guid') } else { '' }
    $packageVersionName = if ($null -ne $versionNode) { $versionNode.GetAttribute('name') } else { '' }

    $majorVersion = if ([string]::IsNullOrWhiteSpace($packageMajorVersion)) { $existingMetadata.MajorVersion } else { $packageMajorVersion }
    $minorVersion = if ([string]::IsNullOrWhiteSpace($packageMinorVersion)) { $existingMetadata.MinorVersion } else { $packageMinorVersion }
    $build = if ([string]::IsNullOrWhiteSpace($packageBuild)) { $existingMetadata.Build } else { $packageBuild }

    $kbGuid = if ([string]::IsNullOrWhiteSpace($packageKbGuid)) { $existingMetadata.Kb } else { $packageKbGuid }
    $username = if ([string]::IsNullOrWhiteSpace($packageUsername)) { $existingMetadata.Username } else { $packageUsername }
    $uncPath = if ([string]::IsNullOrWhiteSpace($packageUncPath)) { $existingMetadata.UNCPath } else { $packageUncPath }
    $versionGuid = if ([string]::IsNullOrWhiteSpace($packageVersionGuid)) { $existingMetadata.VersionGuid } else { $packageVersionGuid }
    $versionName = if ([string]::IsNullOrWhiteSpace($packageVersionName)) { $existingMetadata.VersionName } else { $packageVersionName }

    $hasCompleteSourceFromPackage = @(
        $packageKbGuid,
        $packageUsername,
        $packageUncPath,
        $packageVersionGuid,
        $packageVersionName
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $hasCompleteSourceFromPackage = @($hasCompleteSourceFromPackage)
    $hasCompleteSourceFromPackage = ($hasCompleteSourceFromPackage.Count -eq 5)
    $hasStableMetadataBaseline = @(
        $existingMetadata.Kb,
        $existingMetadata.Username,
        $existingMetadata.UNCPath,
        $existingMetadata.VersionGuid,
        $existingMetadata.VersionName
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $hasStableMetadataBaseline = @($hasStableMetadataBaseline)
    $hasStableMetadataBaseline = ($hasStableMetadataBaseline.Count -gt 0)

    $metadataStatus = if ($hasCompleteSourceFromPackage) {
        'complete'
    } elseif ($hasStableMetadataBaseline) {
        'partial-preserved'
    } else {
        'partial-new'
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($IsLegacyExport -and [string]::IsNullOrWhiteSpace($packageBuild)) {
        # Legacy GeneXus 9 branch (gated by -IsLegacyExport): no KMW/Build; the Build comes from
        # KMW/MaxGxBuildSaved. The legacy hint REPLACES the generic missing-KMW/Source warning
        # — the generic one does NOT fire here (a legacy export has no <Source> block).
        $maxGxBuildNode = if ($null -ne $kmwNode) { $kmwNode.SelectSingleNode('MaxGxBuildSaved') } else { $null }
        if ($null -ne $maxGxBuildNode -and -not [string]::IsNullOrWhiteSpace($maxGxBuildNode.InnerText)) {
            $packageBuild = $maxGxBuildNode.InnerText.Trim()
            $build = $packageBuild
        }
        $warnings.Add($script:LegacyExportMetadataHintMessage) | Out-Null
    } elseif ($null -eq $kmwNode -or $null -eq $sourceNode) {
        $warnings.Add('KbMetadataPath: package accepted for object sync, but KMW or Source came back missing/incomplete; previous stable values were preserved and kb-source-metadata.md received a partial refresh.') | Out-Null
    } elseif (-not $hasCompleteSourceFromPackage) {
        if ($hasStableMetadataBaseline) {
            $warnings.Add('KbMetadataPath: package accepted for object sync, but Source is incomplete; previous stable values were preserved and kb-source-metadata.md received a partial refresh.') | Out-Null
        } else {
            $warnings.Add('KbMetadataPath: package accepted for object sync, but Source is incomplete and has no prior stable baseline; kb-source-metadata.md received a partial refresh.') | Out-Null
        }
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.0000000Z')

    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
        Write-NewKbSourceMetadataTemplate -MetadataPath $MetadataPath `
            -SourceXpzPath $SourceXpzPath `
            -Timestamp $timestamp `
            -MetadataStatus $metadataStatus `
            -MajorVersion $majorVersion `
            -MinorVersion $minorVersion `
            -Build $build `
            -KbGuid $kbGuid `
            -Username $username `
            -UncPath $uncPath `
            -VersionGuid $versionGuid `
            -VersionName $versionName

        return [pscustomobject]@{
            MetadataStatus   = $metadataStatus
            SourceComplete   = $hasCompleteSourceFromPackage
            Warnings         = @($warnings)
            WriteMode        = 'template-create'
        }
    }

    . (Join-Path $PSScriptRoot 'MimirTextFileEolSupport.ps1')

    $fileContext = Get-TextFileLineContext -Path $MetadataPath
    $kbMetadataLineList = $fileContext.Lines
    if ($kbMetadataLineList -isnot [System.Collections.Generic.List[string]]) {
        $kbMetadataLineList = [System.Collections.Generic.List[string]]::new()
        foreach ($contextLine in $fileContext.Lines) {
            [void]$kbMetadataLineList.Add([string]$contextLine)
        }
    }

    if ($kbMetadataLineList.Count -eq 0) {
        throw "BLOCK: kb-source-metadata.md has no readable lines: $MetadataPath"
    }

    foreach ($syncFieldName in $script:SyncOwnedFrontmatterFieldNames) {
        $fieldValue = switch ($syncFieldName) {
            'updated' { $timestamp }
            'last_xpz_materialization_run_at' { $timestamp }
            'source_xpz' { $SourceXpzPath }
            'source_refresh_status' { $metadataStatus }
            default { throw "BLOCK: unmapped frontmatter field: $syncFieldName" }
        }

        Set-KbMetadataFrontmatterField -RowBuffer $kbMetadataLineList -FrontmatterKey $syncFieldName -FrontmatterValue $fieldValue | Out-Null
    }

    $lineArray = @($kbMetadataLineList.ToArray())
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'KMW' 'MajorVersion' $majorVersion
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'KMW' 'MinorVersion' $minorVersion
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'KMW' 'Build' $build
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'Source' 'kb (GUID)' $kbGuid
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'Source' 'username' $username
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'Source' 'UNCPath' $uncPath
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'Source/Version' 'guid' $versionGuid
    $lineArray = Set-KbMetadataMarkdownTableValue $lineArray 'Source/Version' 'name' $versionName

    $fileContext.Lines.Clear()
    foreach ($line in $lineArray) {
        $fileContext.Lines.Add($line) | Out-Null
    }

    Write-TextFilePreservingEol -Path $MetadataPath -FileContext $fileContext

    return [pscustomobject]@{
        MetadataStatus = $metadataStatus
        SourceComplete = $hasCompleteSourceFromPackage
        Warnings       = @($warnings)
        WriteMode      = 'surgical-update'
    }
}
