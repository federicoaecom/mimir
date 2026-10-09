#requires -Version 7.4

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetMarkdown,

    [Parameter(Mandatory = $true)]
    [string]$SectionTitle,

    [string[]]$IntroLines = @(),

    [Parameter(Mandatory = $true)]
    [string[]]$XmlExamplePaths,

    [string[]]$ExampleTitles = @(),

    [string[]]$ExampleNotes = @(),

    [string]$CodeFenceLanguage = "xml"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$utf8NoBomEncodingSupportPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

function Resolve-ExistingPath {
    param(
        [string]$Path,
        [string]$ParameterName
    )

    try {
        return (Resolve-Path -LiteralPath $Path).Path
    } catch {
        throw ("{0} not found: {1}" -f $ParameterName, $Path)
    }
}


function Get-NextSectionMatch {
    param(
        [string]$Content,
        [int]$StartIndex,
        [string]$Title
    )

    $remaining = $Content.Substring($StartIndex)
    $openFenceCharacter = $null
    $openFenceLength = 0

    foreach ($lineMatch in [regex]::Matches($remaining, '(?m)^[^\r\n]*')) {
        $line = $lineMatch.Value

        if ($null -ne $openFenceCharacter) {
            $closingFenceMatch = [regex]::Match($line, '^ {0,3}(?<fence>`+|~+)[ \t]*$')
            if ($closingFenceMatch.Success) {
                $closingFence = $closingFenceMatch.Groups['fence'].Value
                if ($closingFence[0] -eq $openFenceCharacter -and $closingFence.Length -ge $openFenceLength) {
                    $openFenceCharacter = $null
                    $openFenceLength = 0
                }
            }
            continue
        }

        $openingFenceMatch = [regex]::Match($line, '^ {0,3}(?<fence>`{3,}|~{3,})(?<info>.*)$')
        if ($openingFenceMatch.Success) {
            $openingFence = $openingFenceMatch.Groups['fence'].Value
            $openFenceCharacter = $openingFence[0]
            $openFenceLength = $openingFence.Length
            continue
        }

        $isSectionHeading = if ($PSBoundParameters.ContainsKey('Title')) {
            [regex]::IsMatch($line, ("^" + [regex]::Escape($Title) + "\s*$"))
        } else {
            [regex]::IsMatch($line, '^##\s+.+$')
        }
        if ($isSectionHeading) {
            return [pscustomobject]@{
                Success = $true
                Index = $lineMatch.Index
                Length = $lineMatch.Length
            }
        }
    }

    return [pscustomobject]@{
        Success = $false
        Index = 0
        Length = 0
    }
}

function Get-LineEnding {
    param([string]$Content)

    $match = [regex]::Match($Content, '\r\n|\n|\r')
    if ($match.Success) {
        return $match.Value
    }

    return "`r`n"
}

function ConvertTo-LineEnding {
    param(
        [string]$Content,
        [string]$LineEnding
    )

    return [regex]::Replace($Content, '\r\n|\n|\r', $LineEnding)
}

function Replace-ExistingSection {
    param(
        [string]$Content,
        [string]$Title,
        [string]$LineEnding,
        [string]$ReplacementSection
    )

    $startMatch = Get-NextSectionMatch -Content $Content -StartIndex 0 -Title $Title
    if (-not $startMatch.Success) {
        return [pscustomobject]@{
            Found = $false
            Content = $Content.TrimEnd()
        }
    }

    $startIndex = $startMatch.Index
    $searchFrom = $startIndex + $startMatch.Length
    $nextSection = Get-NextSectionMatch -Content $Content -StartIndex $searchFrom

    if ($nextSection.Success) {
        $endIndex = $searchFrom + $nextSection.Index
        $prefix = $Content.Substring(0, $startIndex)
        $suffix = $Content.Substring($endIndex)
        return [pscustomobject]@{
            Found = $true
            Content = $prefix + $ReplacementSection + $LineEnding + $LineEnding + $suffix
        }
    }

    return [pscustomobject]@{
        Found = $true
        Content = $Content.Substring(0, $startIndex) + $ReplacementSection + $LineEnding
    }
}

function Format-FencedBlock {
    param(
        [string]$Path,
        [string]$Language,
        [string]$LineEnding
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $content = ConvertTo-LineEnding -Content $content -LineEnding $LineEnding

    $maxBacktickRun = 0
    foreach ($match in [regex]::Matches($content, '`+')) {
        if ($match.Length -gt $maxBacktickRun) {
            $maxBacktickRun = $match.Length
        }
    }

    $fenceLength = [Math]::Max(3, $maxBacktickRun + 1)
    $fence = [string]([char]96) * $fenceLength
    return ($fence + $Language + $LineEnding + $content + $LineEnding + $fence)
}

if ($XmlExamplePaths.Count -eq 0) {
    throw "At least one XmlExamplePaths entry is required."
}

$resolvedTarget = Resolve-ExistingPath -Path $TargetMarkdown -ParameterName "TargetMarkdown"
$resolvedExamples = @(
    foreach ($path in $XmlExamplePaths) {
        Resolve-ExistingPath -Path $path -ParameterName "XmlExamplePaths"
    }
)

if ($ExampleTitles.Count -gt 0 -and $ExampleTitles.Count -ne $resolvedExamples.Count) {
    throw "ExampleTitles count must match XmlExamplePaths count when provided."
}

if ($ExampleNotes.Count -gt 0 -and $ExampleNotes.Count -ne $resolvedExamples.Count) {
    throw "ExampleNotes count must match XmlExamplePaths count when provided."
}

$raw = Get-Content -LiteralPath $resolvedTarget -Raw
$lineEnding = Get-LineEnding -Content $raw
$raw = ConvertTo-LineEnding -Content $raw -LineEnding $lineEnding

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($SectionTitle)
$lines.Add("")

foreach ($intro in $IntroLines) {
    $lines.Add($intro)
}

if ($IntroLines.Count -gt 0) {
    $lines.Add("")
}

for ($i = 0; $i -lt $resolvedExamples.Count; $i++) {
    if ($ExampleTitles.Count -gt 0) {
        $lines.Add($ExampleTitles[$i])
        $lines.Add("")
    }

    if ($ExampleNotes.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($ExampleNotes[$i])) {
        $noteLines = $ExampleNotes[$i] -split "\r?\n"
        foreach ($noteLine in $noteLines) {
            $lines.Add($noteLine)
        }
        $lines.Add("")
    }

    $lines.Add((Format-FencedBlock -Path $resolvedExamples[$i] -Language $CodeFenceLanguage -LineEnding $lineEnding))
    $lines.Add("")
}

$newSection = (ConvertTo-LineEnding -Content ($lines -join $lineEnding) -LineEnding $lineEnding).TrimEnd()
$sectionResult = Replace-ExistingSection -Content $raw -Title $SectionTitle -LineEnding $lineEnding -ReplacementSection $newSection
$newContent = if ($sectionResult.Found) {
    $sectionResult.Content
} elseif ([string]::IsNullOrWhiteSpace($sectionResult.Content)) {
    $newSection + $lineEnding
} else {
    $sectionResult.Content + $lineEnding + $lineEnding + $newSection + $lineEnding
}

[System.IO.File]::WriteAllText($resolvedTarget, $newContent, (Get-Utf8NoBomEncoding))
