#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to read key fields of kb-source-metadata.md.

.DESCRIPTION
Reads kb-source-metadata.md at the root of the KB workspace and returns key
fields as structured text. Removes the recurring Select-String + regex pattern
inline in callers.

Markdown tables are parsed with ReadAllLines + split on pipe + Trim, which
tolerates residual CRLF; avoid a multiline regex ending in \|$, which is
fragile when the file has CR terminators before the LF.

Returned fields and their origin in kb-source-metadata.md:
  last_xpz_materialization_run_at : top-level field or frontmatter of the file
  kb_name                         : "name" field in the table of the ## Source/Version section
  source_guid                     : "kb (GUID)" field in the table of the ## Source section
                                    (the KB GUID -- not the version GUID in ## Source/Version;
                                    implementations that read source_guid from ## Source/Version
                                    are semantically wrong even when the parse is valid)

Missing fields are reported as "(missing)" instead of failing silently.

.PARAMETER MetadataPath
Optional path to kb-source-metadata.md.
When omitted, uses kb-source-metadata.md at the root of the KB workspace.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Get-KbMetadata.ps1"

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Get-KbMetadata.ps1" -MetadataPath "<WorkspaceRoot>/kb-source-metadata.md"
#>

param(
    [string]$MetadataPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $MetadataPath) {
    $MetadataPath = Join-Path $repoRoot 'kb-source-metadata.md'
}

if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
    throw "kb-source-metadata.md not found: $MetadataPath"
}

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

$lines = [System.IO.File]::ReadAllLines($MetadataPath)

$lastMaterialization = Get-DirectFieldValue -Lines $lines -FieldName 'last_xpz_materialization_run_at'
$kbName = Get-DirectFieldValue -Lines $lines -FieldName 'kb_name'
$sourceGuid = Get-DirectFieldValue -Lines $lines -FieldName 'source_guid'

if (-not $kbName) {
    $kbName = Get-MarkdownTableValue -Lines $lines -SectionName 'Source/Version' -FieldName 'name'
}

if (-not $sourceGuid) {
    $sourceGuid = Get-MarkdownTableValue -Lines $lines -SectionName 'Source' -FieldName 'kb (GUID)'
}

$values = [ordered]@{
    last_xpz_materialization_run_at = $lastMaterialization
    kb_name = $kbName
    source_guid = $sourceGuid
}

foreach ($field in $values.Keys) {
    $value = $values[$field]
    if ($value) {
        "${field}: $value"
    } else {
        "${field}: (missing)"
    }
}
