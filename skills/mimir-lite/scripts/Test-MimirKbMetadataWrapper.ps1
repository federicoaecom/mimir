#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath,

    [Parameter(Mandatory = $true)]
    [string]$WrapperPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DirectFieldValue {
    param(
        [string[]]$Lines,
        [string]$FieldName
    )

    $pattern = '^\s*{0}\s*[:=]\s*(?<value>.+?)\s*$' -f [regex]::Escape($FieldName)
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, $pattern)
        if ($match.Success) {
            return $match.Groups['value'].Value.Trim()
        }
    }

    return $null
}

function Get-MarkdownTableValue {
    param(
        [string[]]$Lines,
        [string]$SectionName,
        [string]$FieldName
    )

    $inSection = $false
    $sectionPattern = '^\s*##\s+{0}\s*$' -f [regex]::Escape($SectionName)

    foreach ($line in $Lines) {
        if ([regex]::IsMatch($line, '^\s*##\s+')) {
            $inSection = [regex]::IsMatch($line, $sectionPattern)
            continue
        }

        if (-not $inSection) {
            continue
        }

        $cells = $line -split '\|'
        if ($cells.Count -lt 4) {
            continue
        }

        $name = $cells[1].Trim()
        $value = $cells[2].Trim()
        if ($name -ieq $FieldName -and $name -notmatch '^-+$') {
            return $value
        }
    }

    return $null
}

function Normalize-MetadataValue {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $trimmed = $Value.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed -eq '(missing)') {
        return $null
    }

    return $trimmed
}

function Test-GuidValue {
    param([AllowNull()][string]$Value)

    if (-not $Value) {
        return $false
    }

    $parsed = [guid]::Empty
    return [guid]::TryParse($Value, [ref]$parsed)
}

function Get-WrapperFields {
    param([string[]]$OutputLines)

    $result = @{}
    foreach ($line in $OutputLines) {
        $match = [regex]::Match($line, '^\s*(?<key>last_xpz_materialization_run_at|kb_name|source_guid)\s*[:=]\s*(?<value>.*)\s*$')
        if ($match.Success) {
            $result[$match.Groups['key'].Value] = $match.Groups['value'].Value.Trim()
        }
    }

    return $result
}

if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
    throw "BLOCK: kb-source-metadata.md not found: $MetadataPath"
}

if (-not (Test-Path -LiteralPath $WrapperPath -PathType Leaf)) {
    throw "BLOCK: metadata wrapper not found: $WrapperPath"
}

$metadataLines = [System.IO.File]::ReadAllLines($MetadataPath)

$expected = [ordered]@{
    last_xpz_materialization_run_at = Normalize-MetadataValue (Get-DirectFieldValue -Lines $metadataLines -FieldName 'last_xpz_materialization_run_at')
    kb_name = Normalize-MetadataValue (Get-DirectFieldValue -Lines $metadataLines -FieldName 'kb_name')
    source_guid = Normalize-MetadataValue (Get-DirectFieldValue -Lines $metadataLines -FieldName 'source_guid')
}

if (-not $expected.kb_name) {
    $expected.kb_name = Normalize-MetadataValue (Get-MarkdownTableValue -Lines $metadataLines -SectionName 'Source/Version' -FieldName 'name')
}

if (-not $expected.source_guid) {
    $expected.source_guid = Normalize-MetadataValue (Get-MarkdownTableValue -Lines $metadataLines -SectionName 'Source' -FieldName 'kb (GUID)')
}

$critical = [ordered]@{
    kbGuid = Normalize-MetadataValue (Get-MarkdownTableValue -Lines $metadataLines -SectionName 'Source' -FieldName 'kb (GUID)')
    kbName = Normalize-MetadataValue (Get-MarkdownTableValue -Lines $metadataLines -SectionName 'Source/Version' -FieldName 'name')
    versionGuid = Normalize-MetadataValue (Get-MarkdownTableValue -Lines $metadataLines -SectionName 'Source/Version' -FieldName 'guid')
    versionName = Normalize-MetadataValue (Get-MarkdownTableValue -Lines $metadataLines -SectionName 'Source/Version' -FieldName 'name')
}

$incomplete = New-Object System.Collections.Generic.List[string]
foreach ($field in @('kbGuid', 'kbName', 'versionGuid', 'versionName')) {
    if (-not $critical[$field]) {
        $incomplete.Add("$field missing") | Out-Null
    }
}

foreach ($field in @('kbGuid', 'versionGuid')) {
    if ($critical[$field] -and -not (Test-GuidValue $critical[$field])) {
        $incomplete.Add("$field invalid: '$($critical[$field])'") | Out-Null
    }
}

if ($incomplete.Count -gt 0) {
    foreach ($item in $incomplete) {
        "PENDING_DATA: $item"
    }

    'METADATA_WRAPPER_INCOMPLETE'
    return
}

$wrapperOutput = & $WrapperPath -MetadataPath $MetadataPath 2>&1
if (-not $?) {
    throw "BLOCK: Get-KbMetadata wrapper failed"
}

$outputLines = @($wrapperOutput | ForEach-Object { $_.ToString() })
$actual = Get-WrapperFields -OutputLines $outputLines
$failures = New-Object System.Collections.Generic.List[string]

# Only these three fields are part of the wrapper contract. Any other field in
# kb-source-metadata.md is ignored, never an error.
$requiredWrapperFields = @('last_xpz_materialization_run_at', 'kb_name', 'source_guid')

foreach ($field in $requiredWrapperFields) {
    $expectedValue = $expected[$field]

    if (-not $expectedValue) {
        "PENDING_DATA: $field missing from metadata"
        continue
    }

    if (-not $actual.ContainsKey($field)) {
        $failures.Add("$field present in metadata was not exposed by the wrapper") | Out-Null
        continue
    }

    $actualValue = Normalize-MetadataValue $actual[$field]
    if (-not $actualValue) {
        $failures.Add("$field present in metadata came out missing in the wrapper") | Out-Null
        continue
    }

    if ($actualValue -ne $expectedValue) {
        $failures.Add("$field diverges; metadata='$expectedValue'; wrapper='$actualValue'") | Out-Null
        continue
    }

    "FIELD_OK: $field"
}

if ($failures.Count -gt 0) {
    throw ('BLOCK: Get-KbMetadata.ps1 does not fulfill the contract: ' + ($failures -join '; '))
}

'METADATA_WRAPPER_OK'
