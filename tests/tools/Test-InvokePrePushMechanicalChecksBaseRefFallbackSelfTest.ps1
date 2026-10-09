#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: Invoke-PrePushMechanicalChecks.ps1 tolerates a missing 'origin'
    remote by falling back to the local 'main' branch.

.DESCRIPTION
    Builds a fresh temporary git repository with only a local 'main' branch and
    NO 'origin' remote or ref at all (this is the same real-world condition as
    this repository's own clone). Confirms:
      - with -BaseRef left at its default ('origin/main'), which cannot be
        resolved, the orchestrator falls back to the local 'main' branch
        instead of throwing: it emits valid JSON, git.baseRefFallbackApplied
        is true, git.baseRef is 'main', and the fallback is recorded in
        agentWarnings;
      - with an explicitly passed -BaseRef that does not exist, the
        orchestrator still fails loudly (no silent fallback for an explicit,
        wrong ref).
    Requires the git executable (the resource itself depends on it).
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools') 'Invoke-PrePushMechanicalChecks.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "BLOCK: target script not found: $scriptPath"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'BLOCK: git missing; this self-test requires the git executable.'
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-baseref-fallback-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

function Set-RepoFile {
    param([string]$Root, [string]$RelativePath, [string]$Content)
    $full = Join-Path $Root $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    Set-Content -LiteralPath $full -Value $Content -Encoding utf8 -NoNewline
}

try {
    & git -C $tempRoot init -b main *> $null
    & git -C $tempRoot config user.email 'selftest@example.com' *> $null
    & git -C $tempRoot config user.name 'Self Test' *> $null
    & git -C $tempRoot config commit.gpgsign false *> $null

    Set-RepoFile -Root $tempRoot -RelativePath 'README.md' -Content "# base`n"
    & git -C $tempRoot add -A *> $null
    & git -C $tempRoot commit -m 'base' *> $null

    & git -C $tempRoot checkout -q -b feature *> $null
    Set-RepoFile -Root $tempRoot -RelativePath 'feature.md' -Content "# feature`n"
    & git -C $tempRoot add -A *> $null
    & git -C $tempRoot commit -m 'feature work' *> $null

    # Test-PsScriptsParse.ps1 (a sibling gate the orchestrator delegates to) requires at
    # least one of skills/, tools/ or tests/ to exist under -RootPath; these need not be
    # tracked by git, just present on disk for its own filesystem scan.
    foreach ($scanRootName in @('skills', 'tools', 'tests')) {
        [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot $scanRootName) -Force)
    }

    # Sanity: this temp repo genuinely has no 'origin' remote or ref.
    & git -C $tempRoot rev-parse --verify origin/main *> $null
    if ($LASTEXITCODE -eq 0) {
        throw 'BLOCK: invalid fixture - origin/main should not exist in this synthetic repo.'
    }

    # --- Case 1: default -BaseRef ('origin/main') falls back to local 'main' ---
    $output = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -AsJson 2>&1
    $exitCode = $LASTEXITCODE
    $jsonText = ($output | Out-String).Trim()
    $result = $null
    try { $result = $jsonText | ConvertFrom-Json } catch { $result = $null }

    if ($null -eq $result) {
        throw "Case 1: expected valid JSON (fallback without crash); got exit=$exitCode output: $jsonText"
    }
    if ($result.git.baseRefFallbackApplied -ne $true) {
        throw "Case 1: git.baseRefFallbackApplied should be true; got '$($result.git.baseRefFallbackApplied)'"
    }
    if ($result.git.baseRef -ne 'main') {
        throw "Case 1: git.baseRef should be 'main' after fallback; got '$($result.git.baseRef)'"
    }
    if ([int]$result.git.commitsAhead -ne 1) {
        throw "Case 1: commitsAhead should be 1 (1 commit on the feature branch beyond main); got $($result.git.commitsAhead)"
    }
    $fallbackWarning = @($result.agentWarnings | Where-Object { $_ -match "(?i)origin.*main.*not found.*main|falling back to local 'main'" })
    if ($fallbackWarning.Count -eq 0) {
        throw "Case 1: agentWarnings should record the BaseRef fallback; got: $($result.agentWarnings -join ' | ')"
    }

    # The removed historico/ folder must not survive as a changed-file kind.
    if (@($result.git.changedFilesByKind.PSObject.Properties.Name) -contains 'historico') {
        throw "Case 1: changedFilesByKind should not list a 'historico' kind (the folder no longer exists)"
    }

    # --- Case 2: an explicit, nonexistent -BaseRef still fails loudly (no silent fallback) ---
    $output2 = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -BaseRef 'this-ref-does-not-exist' -AsJson 2>&1
    $exitCode2 = $LASTEXITCODE
    $jsonText2 = ($output2 | Out-String).Trim()
    $result2 = $null
    try { $result2 = $jsonText2 | ConvertFrom-Json } catch { $result2 = $null }

    if ($exitCode2 -eq 0 -and $null -ne $result2) {
        throw "Case 2: an explicit nonexistent -BaseRef should not produce valid JSON with exit 0 (fallback should be refused); got exit=$exitCode2"
    }
    if ($jsonText2 -notmatch '(?i)not found') {
        throw "Case 2: expected an error message about the base ref not being found; got: $jsonText2"
    }

    Write-Output 'OK: Test-InvokePrePushMechanicalChecksBaseRefFallbackSelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Get-ChildItem -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
