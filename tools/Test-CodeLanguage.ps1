#requires -Version 7.4
<#
.SYNOPSIS
    Flags pt-BR words in comments and string literals of .ps1/.py files, so new
    code stays English going forward.

.DESCRIPTION
    Scans every `.ps1`/`.py` file under `skills/*/scripts`, `skills/*/workflows`, `tools`, and `tests`
    (relative to -RootPath), except under `tests/fixtures/` (synthetic test-input
    data is exempt by design) and except any path prefix in -SkipPaths. Only
    `.ps1`/`.py` files are scanned: Markdown and other shipped text files
    (for example `*.example` templates) are outside this gate.

    A line is flagged when it matches:
      - an accented character (a/e/i/o/u/c with an acute, circumflex, tilde, or
        cedilla), or
      - a common pt-BR function word (lang-allow: docstring, see the word list
        below), with or without its accent, as a whole word (case-insensitive):
        nao/não (lang-allow), arquivo (lang-allow), obrigatorio/obrigatório
        (lang-allow), parametro/parâmetro (lang-allow), encontrado (lang-allow),
        invalido/inválido (lang-allow), entao/então (lang-allow), tambem/também
        (lang-allow).

    A line carrying the literal marker `lang-allow` anywhere on it (e.g.
    `# lang-allow <reason>`) is never flagged — use it for a literal pt-BR
    fixture string that is intentionally test input, with a reason after the
    marker. A marker on the comment line right before a multi-line
    backtick-continued statement also covers every physical line of that
    statement (appending the marker inline on one of those lines would land
    after a trailing line-continuation backtick and break it).

.PARAMETER RootPath
    Root directory to scan. Defaults to the repository root (one level above
    this script's folder).

.PARAMETER IncludeRoots
    Repo-relative root globs to scan. Default: `skills/*/scripts`, `skills/*/workflows`, `tools`,
    `tests`.

.PARAMETER SkipPaths
    Repo-relative path prefixes (file or folder) to exclude, in addition to the
    always-excluded `tests/fixtures`. Default: none.

.PARAMETER AsJson
    Emit a single JSON report to stdout instead of the human-readable list.
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
    [string[]]$IncludeRoots = @('skills/*/scripts', 'skills/*/workflows', 'tools', 'tests'),
    [string[]]$SkipPaths = @(),
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

# tests/tools/Test-CodeLanguageSelfTest.ps1 is exempt for the same reason as
# tests/fixtures/: several of its here-string literals are pt-BR fixture
# PAYLOADS written out to a separate temp file to exercise this very
# detector's RED/GREEN cases. Appending a lang-allow marker to one of those
# lines would land inside the payload and silently suppress the finding the
# self-test depends on -- so the file is excluded wholesale instead.
$alwaysSkip = @('tests/fixtures', 'tests/tools/Test-CodeLanguageSelfTest.ps1')
$effectiveSkip = @($alwaysSkip + $SkipPaths)

function Get-RelativeDisplayPath {
    param([string]$FullPath)
    return [System.IO.Path]::GetRelativePath($resolvedRoot, $FullPath) -replace '\\', '/'
}

function Test-IsSkippedSource {
    param([string]$RelativePath)
    foreach ($skip in $effectiveSkip) {
        $skipNorm = $skip.Trim('/')
        if ($RelativePath -eq $skipNorm -or $RelativePath.StartsWith("$skipNorm/")) { return $true }
    }
    return $false
}

# --- Detection: accented characters, or a common pt-BR function word (accented
# or not) as a whole word, case-insensitive. ---
# lang-allow: detector data, not prose to translate -- see the module docstring.
$accentedCharClass = '[àáâãéêíóôõúüçÀÁÂÃÉÊÍÓÔÕÚÜÇ]'
$wordList = @(
    'nao', 'não',  # lang-allow: detector data
    'arquivo',  # lang-allow: detector data
    'obrigatorio', 'obrigatório',  # lang-allow: detector data
    'parametro', 'parâmetro',  # lang-allow: detector data
    'encontrado',  # lang-allow: detector data
    'invalido', 'inválido',  # lang-allow: detector data
    'entao', 'então',  # lang-allow: detector data
    'tambem', 'também'  # lang-allow: detector data
)
$wordListPattern = ($wordList | ForEach-Object { [regex]::Escape($_) }) -join '|'
$detectionRegex = [regex]::new(
    "$accentedCharClass|\b(?:$wordListPattern)\b",
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

$allowMarker = 'lang-allow'

# --- Discover files: IncludeRoots resolved as repo-relative globs, .ps1/.py only. ---
$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($includeRoot in $IncludeRoots) {
    $candidateDirs = @(Get-Item -Path (Join-Path $resolvedRoot $includeRoot) -ErrorAction SilentlyContinue)
    foreach ($dir in $candidateDirs) {
        if (-not $dir.PSIsContainer) { continue }
        Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.ps1', '.py') } |
            ForEach-Object {
                if ($seenPaths.Add($_.FullName)) { $files.Add($_) }
            }
    }
}
$files = @($files | Sort-Object FullName)

$findings = [System.Collections.Generic.List[object]]::new()
$scannedCount = 0

foreach ($file in $files) {
    $relFile = Get-RelativeDisplayPath $file.FullName
    if (Test-IsSkippedSource $relFile) { continue }
    $scannedCount++

    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding utf8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNo = $i + 1
        $raw = $lines[$i]

        if ($raw.Contains($allowMarker)) { continue }
        # Walk back through backtick line-continuations (the physical lines of one
        # multi-line statement) to the comment line right before the statement started.
        $checkIdx = $i - 1
        while ($checkIdx -ge 0 -and $lines[$checkIdx].TrimEnd().EndsWith('`') -and -not $lines[$checkIdx].TrimStart().StartsWith('#')) {
            $checkIdx--
        }
        if ($checkIdx -ge 0 -and $lines[$checkIdx].Contains($allowMarker) -and $lines[$checkIdx].TrimStart().StartsWith('#')) { continue }

        $m = $detectionRegex.Match($raw)
        if ($m.Success) {
            $findings.Add([pscustomobject]@{
                file  = $relFile
                line  = $lineNo
                match = $m.Value
                text  = $raw.Trim()
            }) | Out-Null
        }
    }
}

$result = [ordered]@{
    rootPath     = $resolvedRoot
    status       = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
    scannedCount = $scannedCount
    errorCount   = $findings.Count
    findings     = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    foreach ($finding in $findings) {
        "PT_BR_FOUND: {0}:{1}: '{2}' in: {3}" -f $finding.file, $finding.line, $finding.match, $finding.text
    }
    "FILES={0}; ERRORS={1}" -f $scannedCount, $findings.Count
}

if ($findings.Count -gt 0) {
    exit 1
}
exit 0
