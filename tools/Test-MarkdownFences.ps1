#requires -Version 7.4
<#
.SYNOPSIS
    Checks that fenced code blocks in Markdown files are properly balanced.

.DESCRIPTION
    Scans every `*.md` file under -RootPath, except under -SkipPaths (default
    `docs/originals/`, large historical/preserved-as-is content). For each
    file, tracks fenced code blocks the way CommonMark does: a fence opened
    with a line of three or more backticks (`` ``` ``) or tildes (`~~~`) is
    only closed by a later line consisting solely of the same character,
    repeated at least as many times as the opener, with no other content
    besides surrounding whitespace. A fence opened with one character is never
    closed by the other (backticks and tildes do not match each other).

    Two kinds of findings are reported:
      - `malformed-closer`: while a fence is open, a line consisting solely of
        one or two of the *same* fence character appears where a real closing
        fence was evidently intended (e.g. a lone backtick, or two backticks,
        immediately after the fenced payload) but is too short to actually
        close it per CommonMark. The fence stays open.
      - `unclosed`: a fence opened in the file is still open at end of file.
        Reported at the opener's own file:line, since that is the actionable
        location (the line where the fix belongs).

    A line that merely *contains* backticks/tildes as part of prose or inline
    code, or a fence-looking line encountered while already inside another
    open fence but not shaped as a valid closer for it (e.g. a nested
    ` ```xml ` info-string line), is ordinary content and is not flagged
    directly — CommonMark does not support nested fences, so such a line
    cannot open a second block; it is either swallowed as content of the
    still-open fence (surfacing as `unclosed` or a real close further down)
    or, if it is itself a malformed short closer, caught by the rule above.

.PARAMETER RootPath
    Root directory to scan. Defaults to the repository root (one level above
    this script's folder).

.PARAMETER SkipPaths
    Repo-relative path prefixes (file or folder) to exclude from scanning.
    Default: `docs/originals` (large historical/preserved-as-is content).

.PARAMETER AsJson
    Emit a single JSON report to stdout instead of the human-readable list.
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
    [string[]]$SkipPaths = @('docs/originals'),
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

function Test-IsSkippedSource {
    param([string]$FullPath)
    $rel = [System.IO.Path]::GetRelativePath($resolvedRoot, $FullPath) -replace '\\', '/'
    foreach ($skip in $SkipPaths) {
        $skipNorm = $skip.Trim('/')
        if ($rel -eq $skipNorm -or $rel.StartsWith("$skipNorm/")) { return $true }
    }
    return $false
}

function Get-RelativeDisplayPath {
    param([string]$FullPath)
    return [System.IO.Path]::GetRelativePath($resolvedRoot, $FullPath) -replace '\\', '/'
}

$mdFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter '*.md' |
    Where-Object { -not (Test-IsSkippedSource $_.FullName) } |
    Sort-Object FullName)

$openerPattern = [regex]'^(`{3,}|~{3,})(.*)$'

$findings = [System.Collections.Generic.List[object]]::new()

foreach ($file in $mdFiles) {
    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding utf8)
    $relFile = Get-RelativeDisplayPath $file.FullName

    $inFence = $false
    $fenceChar = $null
    $fenceLen = 0
    $openerLine = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        $raw = $lines[$i]
        $trimmedBoth = $raw.Trim()
        $trimmedStart = $raw.TrimStart()

        if (-not $inFence) {
            $m = $openerPattern.Match($trimmedStart)
            if ($m.Success) {
                $inFence = $true
                $fenceChar = $m.Groups[1].Value[0]
                $fenceLen = $m.Groups[1].Value.Length
                $openerLine = $lineNo
            }
            continue
        }

        # Already inside an open fence: check for a real close first.
        if ($trimmedBoth.Length -gt 0 -and (@($trimmedBoth.ToCharArray() | Where-Object { $_ -ne $fenceChar })).Count -eq 0 -and $trimmedBoth.Length -ge $fenceLen) {
            $inFence = $false
            $fenceChar = $null
            $fenceLen = 0
            $openerLine = 0
            continue
        }

        # Not a real close: check for a malformed short closer (1-2 of the
        # same fence character, nothing else) — the realistic typo case.
        if ($trimmedBoth.Length -ge 1 -and $trimmedBoth.Length -le 2 -and (@($trimmedBoth.ToCharArray() | Where-Object { $_ -ne $fenceChar })).Count -eq 0) {
            $findings.Add([pscustomobject]@{
                kind        = 'malformed-closer'
                file        = $relFile
                line        = $lineNo
                openerFile  = $relFile
                openerLine  = $openerLine
                fenceMarker = ([string]$fenceChar) * $fenceLen
                found       = $trimmedBoth
            }) | Out-Null
        }
        # Otherwise: ordinary content of the still-open fence (including a
        # fence-shaped line of the wrong character, or one with an info
        # string / extra content after it — neither closes per CommonMark).
    }

    if ($inFence) {
        $findings.Add([pscustomobject]@{
            kind        = 'unclosed'
            file        = $relFile
            line        = $openerLine
            openerFile  = $relFile
            openerLine  = $openerLine
            fenceMarker = ([string]$fenceChar) * $fenceLen
            found       = $null
        }) | Out-Null
    }
}

$result = [ordered]@{
    rootPath   = $resolvedRoot
    status     = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
    fileCount  = $mdFiles.Count
    errorCount = $findings.Count
    findings   = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    foreach ($finding in $findings) {
        if ($finding.kind -eq 'unclosed') {
            "UNCLOSED_FENCE: {0}:{1}: opener `{2}` never closed" -f $finding.file, $finding.line, $finding.fenceMarker
        } else {
            "MALFORMED_CLOSER: {0}:{1}: found `"{2}`" (opener `{3}` at {4}:{5})" -f $finding.file, $finding.line, $finding.found, $finding.fenceMarker, $finding.openerFile, $finding.openerLine
        }
    }
    "FILES={0}; ERRORS={1}" -f $mdFiles.Count, $findings.Count
}

if ($findings.Count -gt 0) {
    exit 1
}
exit 0
