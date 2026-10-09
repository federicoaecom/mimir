#requires -Version 7.4
<#
.SYNOPSIS
    Searches text in Source blocks of GeneXus XML without dumping extensive CDATA.

.DESCRIPTION
    Reads object XMLs or exported packages and splits each <Source> by
    textual role before applying the search. The main goal is to prevent a
    search in a WebPanel from confusing the <GxMultiForm> layout on one giant
    line with events code-behind.

.PARAMETER Path
    XML file or directory containing XMLs. Directories are read at the first
    level by default; use -Recurse to descend into subfolders.

.PARAMETER Pattern
    Regular expression to search for within the Source's effective text.

.PARAMETER Block
    all: all Source blocks.
    code: Source blocks that are neither layout nor serialized XML.
    events: code blocks that contain Event or Sub lines.
    layout: Source blocks whose content starts with <GxMultiForm.
    serialized: Source blocks whose content starts with XML, but not GxMultiForm.

.PARAMETER CaseSensitive
    Uses case-sensitive comparison.

.PARAMETER Recurse
    When Path is a directory, searches XMLs recursively.

.PARAMETER AsJson
    Emits structured JSON.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Pattern,

    [ValidateSet('all', 'code', 'events', 'layout', 'serialized')]
    [string]$Block = 'all',

    [switch]$CaseSensitive,

    [switch]$Recurse,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-TextFileFlexible {
    param([string]$FilePath)

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    foreach ($encoding in @(
        [System.Text.UTF8Encoding]::new($false, $true),
        [System.Text.UTF8Encoding]::new($true, $true),
        [System.Text.UnicodeEncoding]::new($false, $true, $true),
        [System.Text.UnicodeEncoding]::new($true, $true, $true)
    )) {
        try {
            return $encoding.GetString($bytes)
        } catch {
            continue
        }
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Get-XmlFiles {
    param([string]$InputPath)

    $resolved = [System.IO.Path]::GetFullPath($InputPath)
    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        return @(Get-Item -LiteralPath $resolved)
    }
    if (Test-Path -LiteralPath $resolved -PathType Container) {
        return @(Get-ChildItem -LiteralPath $resolved -Filter '*.xml' -File -Recurse:$Recurse)
    }
    throw "Path not found: $InputPath"
}

function Get-LineNumberAt {
    param(
        [string]$Text,
        [int]$Index
    )

    if ($Index -le 0) {
        return 1
    }
    return ([regex]::Matches($Text.Substring(0, $Index), "`n")).Count + 1
}

function Get-ObjectNameAtIndex {
    param(
        [string]$XmlText,
        [int]$Index
    )

    $regex = [regex]::new('<Object\b[^>]*\bname="(?<name>[^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::RightToLeft)
    $match = $regex.Match($XmlText, $Index)
    if ($match.Success) {
        return [System.Net.WebUtility]::HtmlDecode($match.Groups['name'].Value)
    }
    return $null
}

function Unwrap-SourceBody {
    param([string]$RawBody)

    $cdata = [regex]::Match($RawBody, '^\s*<!\[CDATA\[(?<body>.*)\]\]>\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($cdata.Success) {
        return $cdata.Groups['body'].Value
    }
    return [System.Net.WebUtility]::HtmlDecode($RawBody)
}

function Get-SourceBodyStartOffset {
    param([string]$RawBody)

    $cdataPrefix = [regex]::Match($RawBody, '^\s*<!\[CDATA\[', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($cdataPrefix.Success) {
        return $cdataPrefix.Length
    }
    return 0
}

function Get-SourceBlockKind {
    param([string]$SourceText)

    $trimmed = $SourceText.TrimStart()
    if ($trimmed.StartsWith('<GxMultiForm', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'layout'
    }
    if ($trimmed.StartsWith('<', [System.StringComparison]::Ordinal)) {
        return 'serialized'
    }
    if ($SourceText -match '(?im)^\s*(Event|Sub)\b') {
        return 'events'
    }
    return 'code'
}

function Test-BlockSelected {
    param(
        [string]$Actual,
        [string]$Selected
    )

    if ($Selected -eq 'all') { return $true }
    if ($Selected -eq 'code') { return ($Actual -eq 'code' -or $Actual -eq 'events') }
    return ($Actual -eq $Selected)
}

function Get-LinePreview {
    param([string]$Line)

    if ($null -eq $Line) { return '' }
    $trimmed = $Line.Trim()
    if ($trimmed.Length -le 180) {
        return $trimmed
    }
    return $trimmed.Substring(0, 180) + '...'
}

function Search-SourceBlocksInFile {
    param(
        [System.IO.FileInfo]$File,
        [regex]$Regex,
        [string]$SelectedBlock
    )

    $xmlText = Read-TextFileFlexible -FilePath $File.FullName
    $sourceRegex = [regex]::new('<Source(?:\s[^>]*)?>(?<body>.*?)</Source>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $sourceIndex = 0
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($sourceMatch in $sourceRegex.Matches($xmlText)) {
        $sourceIndex++
        $rawBody = $sourceMatch.Groups['body'].Value
        $body = Unwrap-SourceBody -RawBody $rawBody
        if ([string]::IsNullOrWhiteSpace($body)) {
            continue
        }

        $objectName = Get-ObjectNameAtIndex -XmlText $xmlText -Index $sourceMatch.Index
        $kind = Get-SourceBlockKind -SourceText $body
        if (-not (Test-BlockSelected -Actual $kind -Selected $SelectedBlock)) {
            continue
        }

        $bodyStart = $sourceMatch.Groups['body'].Index + (Get-SourceBodyStartOffset -RawBody $rawBody)
        $sourceStartLine = Get-LineNumberAt -Text $xmlText -Index $bodyStart
        $lines = @([regex]::Split($body, "`r?`n"))

        for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
            $line = $lines[$lineIndex]
            foreach ($match in $Regex.Matches($line)) {
                $results.Add([pscustomobject]@{
                    path          = $File.FullName
                    objectName    = $objectName
                    block         = $kind
                    sourceIndex   = $sourceIndex
                    xmlLine       = $sourceStartLine + $lineIndex
                    blockLine     = $lineIndex + 1
                    column        = $match.Index + 1
                    match         = $match.Value
                    preview       = Get-LinePreview -Line $line
                }) | Out-Null
            }
        }
    }

    return @($results)
}

$regexOptions = [System.Text.RegularExpressions.RegexOptions]::None
if (-not $CaseSensitive) {
    $regexOptions = $regexOptions -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
}
$searchRegex = [regex]::new($Pattern, $regexOptions)

$allResults = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-XmlFiles -InputPath $Path) {
    foreach ($result in Search-SourceBlocksInFile -File $file -Regex $searchRegex -SelectedBlock $Block) {
        $allResults.Add($result) | Out-Null
    }
}

if ($AsJson) {
    @($allResults) | ConvertTo-Json -Depth 5
    return
}

foreach ($result in $allResults) {
    $objectPart = if ([string]::IsNullOrWhiteSpace($result.objectName)) { '' } else { " object=$($result.objectName)" }
    "{0}:{1}: block={2} source={3} blockLine={4}{5}: {6}" -f $result.path, $result.xmlLine, $result.block, $result.sourceIndex, $result.blockLine, $objectPart, $result.preview
}
