#requires -Version 7.4
<#
.SYNOPSIS
    Checks that tracked text files are UTF-8 without BOM and use LF line endings.

.DESCRIPTION
    Uses `git ls-files` under -RootPath to enumerate tracked files (so untracked
    scratch/build output is never flagged), keeps only known text extensions
    (.md, .ps1, .py, .json, .psd1, .yaml, .yml, .txt, .gitattributes,
    .gitignore, .editorconfig), skips `docs/originals/`, and reports any file
    that has a UTF-8 BOM and/or at least one CRLF line ending. Binary files and
    files outside the known text extension set are never inspected.
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

$textExtensions = @('.md', '.ps1', '.py', '.json', '.psd1', '.yaml', '.yml', '.txt', '.gitattributes', '.gitignore', '.editorconfig')

function Test-IsSkippedSource {
    param([string]$RelPath)
    foreach ($skip in $SkipPaths) {
        $skipNorm = $skip.Trim('/')
        if ($RelPath -eq $skipNorm -or $RelPath.StartsWith("$skipNorm/")) { return $true }
    }
    return $false
}

function Get-TrackedTextFiles {
    param([string]$Root)

    $isGitRepo = $false
    Push-Location -LiteralPath $Root
    try {
        & git rev-parse --is-inside-work-tree *> $null
        $isGitRepo = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }

    $relPaths = @()
    if ($isGitRepo) {
        Push-Location -LiteralPath $Root
        try {
            $relPaths = @(& git ls-files) | ForEach-Object { $_ -replace '\\', '/' }
        } finally {
            Pop-Location
        }
    } else {
        $relPaths = @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
            [System.IO.Path]::GetRelativePath($Root, $_.FullName) -replace '\\', '/'
        })
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($rel in $relPaths) {
        if (Test-IsSkippedSource $rel) { continue }
        $ext = [System.IO.Path]::GetExtension($rel)
        $name = [System.IO.Path]::GetFileName($rel)
        $isKnownText = ($textExtensions -contains $ext) -or ($textExtensions -contains $name)
        if (-not $isKnownText) { continue }
        $full = Join-Path $Root $rel
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $result.Add($rel)
        }
    }
    return $result
}

$files = Get-TrackedTextFiles -Root $resolvedRoot
$findings = [System.Collections.Generic.List[object]]::new()

foreach ($rel in $files) {
    $full = Join-Path $resolvedRoot $rel
    $bytes = [System.IO.File]::ReadAllBytes($full)

    $issues = [System.Collections.Generic.List[string]]::new()

    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if ($hasBom) { $issues.Add('bom') }

    $hasCrlf = $false
    for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
        if ($bytes[$i] -eq 0x0D -and $bytes[$i + 1] -eq 0x0A) { $hasCrlf = $true; break }
    }
    if ($hasCrlf) { $issues.Add('crlf') }

    if ($issues.Count -gt 0) {
        $findings.Add([pscustomobject]@{
            file   = $rel
            issues = @($issues)
        }) | Out-Null
    }
}

$result = [ordered]@{
    rootPath   = $resolvedRoot
    status     = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
    fileCount  = $files.Count
    errorCount = $findings.Count
    findings   = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    foreach ($finding in $findings) {
        "BAD_ENCODING: {0}: {1}" -f $finding.file, ($finding.issues -join ',')
    }
    "FILES={0}; ERRORS={1}" -f $files.Count, $findings.Count
}

if ($findings.Count -gt 0) {
    exit 1
}
exit 0
