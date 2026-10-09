#requires -Version 7.4

<#
.SYNOPSIS
    Detects unexpected Unicode characters in .md and .ps1 files in the pre-push diff.

.DESCRIPTION
    Scans added (or modified) lines in the BaseRef..HEAD range in .md and .ps1
    files, looking for characters that do not belong to
    the pt-BR, es, and en alphabets (CJK, Cyrillic, Arabic, etc.). For .md,
    lines inside fenced code blocks (``` ... ```) are ignored based on the full
    current file, preserving the real line number in the new file.

    The gate is advisory: it emits findings with severity='warn' and always
    exits 0. The agent reviews the findings and decides whether they are false
    positives.

.PARAMETER RootPath
    Repository root (mandatory).

.PARAMETER BaseRef
    Base reference of the range (default: origin/main).

.PARAMETER ChangedFiles
    Pre-computed list of changed files (paths relative to RootPath).
    If omitted, the script runs git diff --name-only to get the list.

.PARAMETER AsJson
    Emits structured JSON output.

.EXAMPLE
    .\Test-GeneXusUnexpectedCharacter.ps1 -RootPath C:\path\to\mimir-lite -AsJson
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,

    [string]$BaseRef = 'origin/main',

    [AllowEmptyCollection()]
    [string[]]$ChangedFiles = @(),

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BlockedRanges = @(
    @{ Min = 0x0400; Max = 0x04FF; Name = 'Cyrillic' }
    @{ Min = 0x0500; Max = 0x052F; Name = 'Cyrillic Supplement' }
    @{ Min = 0x0590; Max = 0x05FF; Name = 'Hebrew' }
    @{ Min = 0x0600; Max = 0x06FF; Name = 'Arabic' }
    @{ Min = 0x0900; Max = 0x097F; Name = 'Devanagari' }
    @{ Min = 0x3000; Max = 0x303F; Name = 'CJK Symbols and Punctuation' }
    @{ Min = 0x3040; Max = 0x309F; Name = 'Hiragana' }
    @{ Min = 0x30A0; Max = 0x30FF; Name = 'Katakana' }
    @{ Min = 0x3400; Max = 0x4DBF; Name = 'CJK Unified Ideographs Extension A' }
    @{ Min = 0x4E00; Max = 0x9FFF; Name = 'CJK Unified Ideographs' }
    @{ Min = 0xAC00; Max = 0xD7AF; Name = 'Hangul Syllables' }
    @{ Min = 0x0E00; Max = 0x0E7F; Name = 'Thai' }
    @{ Min = 0x0E80; Max = 0x0EFF; Name = 'Lao' }
    @{ Min = 0x1F600; Max = 0x1F64F; Name = 'Emoticons' }
    @{ Min = 0x1F300; Max = 0x1F5FF; Name = 'Misc Symbols and Pictographs' }
    @{ Min = 0x1F680; Max = 0x1F6FF; Name = 'Transport and Map Symbols' }
    @{ Min = 0x1F900; Max = 0x1F9FF; Name = 'Supplemental Symbols and Pictographs' }
    @{ Min = 0x1FA00; Max = 0x1FA6F; Name = 'Chess Symbols' }
    @{ Min = 0x1FA70; Max = 0x1FAFF; Name = 'Symbols and Pictographs Extended-A' }
)

$BlockedIndividualChars = @(
    @{ Code = 0xFEFF; Name = 'BOM / ZERO WIDTH NO-BREAK SPACE' }
    @{ Code = 0x200B; Name = 'ZERO WIDTH SPACE' }
)

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

function Get-BlockedRangeName {
    param([int]$CodePoint)
    foreach ($range in $BlockedRanges) {
        if ($CodePoint -ge $range.Min -and $CodePoint -le $range.Max) {
            return $range.Name
        }
    }
    foreach ($blocked in $BlockedIndividualChars) {
        if ($CodePoint -eq $blocked.Code) {
            return $blocked.Name
        }
    }
    return $null
}

function Invoke-RepoGit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git -C $RepositoryRoot @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = @()
    if ($null -ne $output) {
        $lines = @($output | ForEach-Object { $_.ToString() })
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines    = $lines
        Text     = ($lines -join [Environment]::NewLine)
    }
}

function Get-AddedLineRecordsFromDiff {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$BaseRef,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $diffResult = Invoke-RepoGit -RepositoryRoot $RepositoryRoot -Arguments @('diff', '--unified=0', "$BaseRef..HEAD", '--', $RelativePath)
    if ($diffResult.ExitCode -ne 0) {
        return ,[string[]]@()
    }

    $addedLines = [System.Collections.Generic.List[pscustomobject]]::new()
    $newLineNumber = 0
    foreach ($line in $diffResult.Lines) {
        if ($line.StartsWith('@@')) {
            $match = [regex]::Match($line, '\+(\d+)(?:,(\d+))?')
            if ($match.Success) {
                $newLineNumber = [int]$match.Groups[1].Value
            }
            continue
        }

        if ($line.StartsWith('+++')) {
            continue
        }

        if ($line.StartsWith('+')) {
            $addedLines.Add([pscustomobject]@{
                Text       = $line.Substring(1)
                LineNumber = $newLineNumber
            })
            $newLineNumber++
            continue
        }

        if ($line.StartsWith(' ')) {
            $newLineNumber++
        }
    }

    return ,[pscustomobject[]]@($addedLines)
}

function Test-MarkdownLineInsideCodeBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [int]$LineNumber
    )

    $fullPath = Join-Path $RepositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return $false
    }

    $lines = [System.IO.File]::ReadAllLines($fullPath)
    $maxIndex = [Math]::Min($LineNumber - 1, $lines.Length - 1)
    if ($maxIndex -lt 0) {
        return $false
    }

    $inCodeBlock = $false

    for ($idx = 0; $idx -le $maxIndex; $idx++) {
        $line = $lines[$idx]
        $trimmed = $line.TrimStart()
        if ($trimmed.StartsWith('```')) {
            $inCodeBlock = -not $inCodeBlock
        }
    }

    return $inCodeBlock
}

function Find-UnexpectedCharacters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line,

        [Parameter(Mandatory = $true)]
        [int]$LineNumber,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $findings = [System.Collections.Generic.List[pscustomobject]]::new()

    for ($i = 0; $i -lt $Line.Length; $i++) {
        $currentChar = $Line[$i]
        if ([char]::IsHighSurrogate($currentChar) -and ($i + 1) -lt $Line.Length -and [char]::IsLowSurrogate($Line[$i + 1])) {
            $cp = [char]::ConvertToUtf32($currentChar, $Line[$i + 1])
            $character = [string]::new(@($currentChar, $Line[$i + 1]))
            $advanceExtra = $true
        } else {
            $cp = [int][char]$currentChar
            $character = [string]$currentChar
            $advanceExtra = $false
        }

        if ($cp -le 0x007E) {
            if ($advanceExtra) {
                $i++
            }
            continue
        }

        $rangeName = Get-BlockedRangeName -CodePoint $cp
        if ($null -ne $rangeName) {
            $start = [Math]::Max(0, $i - 30)
            $end = [Math]::Min($Line.Length, $i + 31)
            $context = $Line.Substring($start, $end - $start)
            $msg = "Character U+{0:X4} ({1}) on line {2} of {3} belongs to the '{4}' block, unexpected in pt-BR/es/en content." -f $cp, $character, $LineNumber, $RelativePath, $rangeName
            $cpStr = 'U+{0:X4}' -f $cp

            $findings.Add([pscustomobject]@{
                severity  = 'warn'
                code      = 'UNEXPECTED_CHARACTER'
                message   = $msg
                file      = $RelativePath
                line      = $LineNumber
                codepoint = $cpStr
                character = $character
                blockName = $rangeName
                context   = $context
            })
        }

        if ($advanceExtra) {
            $i++
        }
    }

    return ,[pscustomobject[]]@($findings)
}

$relevantFiles = [System.Collections.Generic.List[string]]::new()

if ($ChangedFiles.Count -gt 0) {
    foreach ($f in @($ChangedFiles)) {
        $normalized = ($f -replace '\\', '/').Trim()
        if ($normalized -match '\.(md|ps1)$') {
            $relevantFiles.Add($normalized)
        }
    }
} else {
    $nameOnlyResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', '--name-only', "$BaseRef..HEAD")
    if ($nameOnlyResult.ExitCode -ne 0) {
        $result = [pscustomobject]@{
            status         = 'warn'
            totalFilesScanned = 0
            totalUnexpectedChars = 0
            findings       = @([pscustomobject]@{
                severity  = 'warn'
                code      = 'GIT_DIFF_FAILED'
                message   = "Failed to list changed files: $($nameOnlyResult.Text)"
                file      = ''
                line      = 0
                codepoint = ''
                character = ''
                blockName = ''
                context   = ''
            })
        }
        if ($AsJson) { $result | ConvertTo-Json -Depth 6 } else { Write-Output "status: warn"; Write-Output "findings: 1 (git diff failed)" }
        exit 0
    }

    foreach ($f in @($nameOnlyResult.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $normalized = ($f -replace '\\', '/').Trim()
        if ($normalized -match '\.(md|ps1)$') {
            $relevantFiles.Add($normalized)
        }
    }
}

$allFindings = [System.Collections.Generic.List[pscustomobject]]::new()
$filesScanned = 0

foreach ($relPath in @($relevantFiles)) {
    $addedLineRecords = Get-AddedLineRecordsFromDiff -RepositoryRoot $resolvedRoot -BaseRef $BaseRef -RelativePath $relPath
    if ($addedLineRecords.Count -eq 0) {
        continue
    }

    $filesScanned++

    foreach ($lineRecord in @($addedLineRecords)) {
        $lineContent = [string]$lineRecord.Text
        if ([string]::IsNullOrWhiteSpace($lineContent)) {
            continue
        }
        $lineNumber = [int]$lineRecord.LineNumber
        if ($relPath -match '\.md$' -and (Test-MarkdownLineInsideCodeBlock -RepositoryRoot $resolvedRoot -RelativePath $relPath -LineNumber $lineNumber)) {
            continue
        }

        $charFindings = Find-UnexpectedCharacters -Line $lineContent -LineNumber $lineNumber -RelativePath $relPath
        foreach ($f in $charFindings) {
            [void]$allFindings.Add($f)
        }
    }
}

$status = if ($allFindings.Count -eq 0) { 'pass' } else { 'warn' }
$uniqueChars = @($allFindings | Select-Object -Property codepoint, character, blockName -Unique)

$result = [pscustomobject]@{
    status                = $status
    totalFilesScanned     = $filesScanned
    totalUnexpectedChars   = $allFindings.Count
    uniqueUnexpectedChars  = $uniqueChars.Count
    findings               = @($allFindings)
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
} else {
    Write-Output "status: $status"
    Write-Output "totalFilesScanned: $filesScanned"
    Write-Output "totalUnexpectedChars: $($allFindings.Count)"
    if ($allFindings.Count -eq 0) {
        Write-Output "findings: (none)"
    } else {
        Write-Output "findings:"
        foreach ($f in $allFindings) {
            Write-Output "  - [$($f.severity)] $($f.code): $($f.message)"
            Write-Output "    context: $($f.context)"
        }
    }
}

exit 0
