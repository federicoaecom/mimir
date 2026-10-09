#requires -Version 7.4
<#
.SYNOPSIS
    Checks that relative markdown links and bare `NN-*.md` file mentions in every
    tracked-style markdown file resolve to a real file.

.DESCRIPTION
    Scans every `*.md` file under -RootPath, except under `docs/originals/` and
    `CHANGELOG.md` (large historical/preserved-as-is content). For each file:
      - every `[text](target)` link is resolved relative to the file's own folder
        (or repo-root when the target starts with `/`); external URLs (any
        `scheme://`), `mailto:` links and pure `#anchor` links (no path part) are
        skipped;
      - every bare `NN-*.md`/`NNx-*.md` filename mention (backtick or plain text,
        not necessarily a link) must match the basename of some real `.md` file
        anywhere under -RootPath;
      - when a link target resolves to a real `.md` file AND carries a `#anchor`
        fragment (e.g. `other.md#some-heading`), the anchor is validated against
        that file's own headings, converted to a GitHub-style slug (lowercase,
        spaces to `-`, punctuation other than `-`/`_` dropped, duplicate slugs
        suffixed `-1`, `-2`, ...); headings inside fenced code blocks are not
        counted. A pure `#anchor` link with no path part is not checked against
        anything (self-anchor validation is out of scope for this gate).

.PARAMETER IncludePaths
    Optional allowlist of repo-relative path prefixes (file or folder). When
    given, only source files under one of these prefixes are scanned for
    broken links/mentions (everything else is skipped as a source, e.g. a
    pending translation still in flight). A link *target* can still resolve
    anywhere in -RootPath regardless of this filter — only which files are
    read as sources is restricted. Default: empty, meaning every file under
    -RootPath (subject to -SkipPaths) is scanned, matching prior behavior.
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
    [string[]]$SkipPaths = @('docs/originals', 'CHANGELOG.md'),
    [string[]]$IncludePaths = @(),
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

function Test-IsIncludedSource {
    param([string]$FullPath)
    if ($IncludePaths.Count -eq 0) { return $true }
    $rel = [System.IO.Path]::GetRelativePath($resolvedRoot, $FullPath) -replace '\\', '/'
    foreach ($include in $IncludePaths) {
        $includeNorm = $include.Trim('/')
        if ($rel -eq $includeNorm -or $rel.StartsWith("$includeNorm/")) { return $true }
    }
    return $false
}

$allMdFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter '*.md')
$basenameMap = @{}
foreach ($f in $allMdFiles) {
    if (-not $basenameMap.ContainsKey($f.Name)) {
        $basenameMap[$f.Name] = [System.Collections.Generic.List[string]]::new()
    }
    $basenameMap[$f.Name].Add($f.FullName)
}

$sourceFiles = @($allMdFiles | Where-Object { -not (Test-IsSkippedSource $_.FullName) -and (Test-IsIncludedSource $_.FullName) } | Sort-Object FullName)

$linkPattern = [regex]'\[[^\]]*\]\(([^)]+)\)'
$barePattern = [regex]'(?<![\d-])(\d{2,3}[a-z]?-[A-Za-z0-9_-]+\.md)\b'

$findings = [System.Collections.Generic.List[object]]::new()

function Get-RelativeDisplayPath {
    param([string]$FullPath)
    return [System.IO.Path]::GetRelativePath($resolvedRoot, $FullPath) -replace '\\', '/'
}

function ConvertTo-GitHubSlug {
    param([string]$Text)
    $s = $Text.Trim().ToLowerInvariant()
    # Drop anything that is not a letter, digit, space, hyphen or underscore
    # (GitHub's slugger strips punctuation such as backticks, colons, slashes,
    # parentheses, etc. but keeps letters/digits/spaces/hyphens/underscores).
    $s = [regex]::Replace($s, "[^\p{L}\p{N} _-]", '')
    $s = [regex]::Replace($s, '\s+', '-')
    return $s
}

$headingSlugCache = @{}

function Get-HeadingSlugSet {
    param([string]$FilePath)
    if ($headingSlugCache.ContainsKey($FilePath)) {
        return $headingSlugCache[$FilePath]
    }
    $slugSet = [System.Collections.Generic.HashSet[string]]::new()
    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        $slugCounts = @{}
        $inFence = $false
        $fenceMarker = $null
        foreach ($rawLine in (Get-Content -LiteralPath $FilePath -Encoding utf8)) {
            $trimmed = $rawLine.TrimStart()
            if ($trimmed -match '^(```|~~~)') {
                $marker = $Matches[1]
                if (-not $inFence) {
                    $inFence = $true
                    $fenceMarker = $marker
                } elseif ($fenceMarker -eq $marker) {
                    $inFence = $false
                    $fenceMarker = $null
                }
                continue
            }
            if ($inFence) { continue }
            if ($rawLine -match '^(#{1,6})\s+(.+?)\s*#*\s*$') {
                $headingText = $Matches[2]
                $baseSlug = ConvertTo-GitHubSlug $headingText
                if ($slugCounts.ContainsKey($baseSlug)) {
                    $slugCounts[$baseSlug] += 1
                    $finalSlug = "$baseSlug-$($slugCounts[$baseSlug])"
                } else {
                    $slugCounts[$baseSlug] = 0
                    $finalSlug = $baseSlug
                }
                [void]$slugSet.Add($finalSlug)
            }
        }
    }
    $headingSlugCache[$FilePath] = $slugSet
    return $slugSet
}

foreach ($file in $sourceFiles) {
    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding utf8)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        foreach ($m in $linkPattern.Matches($line)) {
            $rawTarget = $m.Groups[1].Value.Trim()
            # A link target may carry a trailing "title" in quotes: (path "title").
            $target = ($rawTarget -split '\s+', 2)[0]
            if ([string]::IsNullOrWhiteSpace($target)) { continue }
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.\-]*://') { continue }
            if ($target -like 'mailto:*') { continue }
            if ($target.StartsWith('#')) { continue }

            $pathPart = $target
            $hashIdx = $target.IndexOf('#')
            if ($hashIdx -ge 0) { $pathPart = $target.Substring(0, $hashIdx) }
            if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }

            if ($pathPart.StartsWith('/')) {
                $candidate = Join-Path $resolvedRoot $pathPart.TrimStart('/')
            } else {
                $candidate = Join-Path $file.DirectoryName $pathPart
            }
            $candidateFull = [System.IO.Path]::GetFullPath($candidate)
            if (-not (Test-Path -LiteralPath $candidateFull)) {
                $findings.Add([pscustomobject]@{
                    file    = Get-RelativeDisplayPath $file.FullName
                    line    = $i + 1
                    kind    = 'link'
                    target  = $target
                    resolved = $candidateFull
                }) | Out-Null
            } elseif ($hashIdx -ge 0 -and $candidateFull.ToLowerInvariant().EndsWith('.md') -and (Test-Path -LiteralPath $candidateFull -PathType Leaf)) {
                $anchor = $target.Substring($hashIdx + 1)
                if (-not [string]::IsNullOrWhiteSpace($anchor)) {
                    $slugSet = Get-HeadingSlugSet -FilePath $candidateFull
                    if (-not $slugSet.Contains($anchor)) {
                        $findings.Add([pscustomobject]@{
                            file    = Get-RelativeDisplayPath $file.FullName
                            line    = $i + 1
                            kind    = 'anchor'
                            target  = $target
                            resolved = $candidateFull
                        }) | Out-Null
                    }
                }
            }
        }

        foreach ($m in $barePattern.Matches($line)) {
            $name = $m.Groups[1].Value
            if (-not $basenameMap.ContainsKey($name)) {
                $findings.Add([pscustomobject]@{
                    file    = Get-RelativeDisplayPath $file.FullName
                    line    = $i + 1
                    kind    = 'bare-mention'
                    target  = $name
                    resolved = $null
                }) | Out-Null
            }
        }
    }
}

$result = [ordered]@{
    rootPath     = $resolvedRoot
    includePaths = @($IncludePaths)
    status       = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
    fileCount    = $sourceFiles.Count
    errorCount   = $findings.Count
    findings     = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    foreach ($finding in $findings) {
        "BROKEN_{0}: {1}:{2}: {3}" -f $finding.kind.ToUpperInvariant(), $finding.file, $finding.line, $finding.target
    }
    "FILES={0}; ERRORS={1}" -f $sourceFiles.Count, $findings.Count
}

if ($findings.Count -gt 0) {
    exit 1
}
exit 0
