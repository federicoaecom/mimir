#requires -Version 7.4
<#
.SYNOPSIS
    Deterministic self-test for Build-PrePushReviewDossier.ps1.

.DESCRIPTION
    Builds local temporary git repositories (no network) and checks the
    pre-push dossier contract (cases a-f, n):

      (a) repo with pending commits: sections A/B present, literal section B
          header, HEAD:/END_DOSSIER sentinels; RECOMPUTES the body's sha256 and checks it.
      (b) dossierReady=false ONLY without git (b1) or without origin/main (b2).
      (c) broken parse in the repo's skills/mimir-lite/scripts/ => mechanicalStatus=failed, dossierReady=true.
      (d) commitsBehind>0 => pushReadiness=blocked + intervalDiffDiagnosticOnly.
      (e) -FetchStatus not-fetched/fetch-failed => remoteFreshness=stale; fetched => fresh.
      (f) reported sizeChars equals the dossierText's length.
      (n) non-empty status --porcelain => workingTreeDirty=true + a stamped path list.

    Requires the git executable (the resource itself depends on it).
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The dossier carries accents; decoding the child builder's output as UTF-8 without BOM
# (the builder also forces UTF-8 on its own stdout) avoids code-page corruption.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$builder = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools') 'Build-PrePushReviewDossier.ps1'
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "BLOCK: target script not found: $builder"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'BLOCK: git missing; this self-test requires the git executable.'
}

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Utf8NoBomEncodingSupport.ps1')

$failures = 0
$cases = 0

function New-TempDir {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-dossier-selftest-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Remove-TempDir {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Set-RepoFile {
    param([string]$Root, [string]$RelativePath, [string]$Content)
    $full = Join-Path $Root $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    # -NoNewline: $Content itself already carries the desired trailing \n; without this, Set-Content
    # adds a second one => blank line at EOF => git diff --check flags whitespace.
    Set-Content -LiteralPath $full -Value $Content -Encoding utf8 -NoNewline
}

function Initialize-DossierRepo {
    # Repo with 1 base commit (=> origin/main) and 1 commit ahead (=> HEAD ahead).
    param([string]$Root, [switch]$BrokenScript)

    & git -C $Root init -b main *> $null
    & git -C $Root config user.email 'selftest@example.com' *> $null
    & git -C $Root config user.name 'Self Test' *> $null

    if ($BrokenScript) {
        Set-RepoFile -Root $Root -RelativePath 'skills/mimir-lite/scripts/broken.ps1' -Content "function Foo {`n"
    } else {
        Set-RepoFile -Root $Root -RelativePath 'skills/mimir-lite/scripts/valid.ps1' -Content "Write-Output 'ok'`n"
    }
    # A valid .py guarantees the mechanical routine's Python parse gate runs without
    # tripping on an empty-array access ($files.FullName) under StrictMode in a
    # skills/mimir-lite/scripts/ with no .py.
    Set-RepoFile -Root $Root -RelativePath 'skills/mimir-lite/scripts/valid.py' -Content "x = 1`n"
    Set-RepoFile -Root $Root -RelativePath 'README.md' -Content "# base`n"
    & git -C $Root add -A *> $null
    & git -C $Root commit -m 'base' *> $null
    $baseSha = (& git -C $Root rev-parse HEAD).Trim()
    & git -C $Root update-ref refs/remotes/origin/main $baseSha *> $null

    Set-RepoFile -Root $Root -RelativePath 'feature.md' -Content "# feature`n"
    & git -C $Root add -A *> $null
    & git -C $Root commit -m 'feature' *> $null

    return $baseSha
}

function Invoke-Builder {
    param([string[]]$BuilderArgs)
    $out = & pwsh -NoProfile -File $builder @BuilderArgs 2>&1 | Out-String
    return $out.Trim()
}

function Assert-True {
    param([string]$CaseName, [bool]$Condition, [string]$Detail = '')
    $script:cases++
    if ($Condition) {
        Write-Output ("PASS: {0}" -f $CaseName)
    } else {
        $script:failures++
        Write-Output ("FAIL: {0}" -f $CaseName)
        if ($Detail) { Write-Output ("      {0}" -f $Detail) }
    }
}

# ---------------------------------------------------------------------------
# Case (a): complete dossier + recompute the body's sha256
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    [void](Initialize-DossierRepo -Root $tmp)
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json

    Assert-True -CaseName 'a: dossierReady=true' -Condition ($json.dossierReady -eq $true)
    Assert-True -CaseName 'a: mechanicalStatus=passed' -Condition ($json.mechanicalStatus -eq 'passed') -Detail ("mechanicalStatus={0} exit={1}" -f $json.mechanicalStatus, $json.mechanicalExitCode)

    $text = [string]$json.dossierText
    Assert-True -CaseName 'a: Section A present' -Condition ($text -match '=== SECTION A — RAW GIT \(FACT\) ===')
    $expectedBHeader = '=== SECTION B — ORCHESTRATOR MECHANICAL DIAGNOSTIC (candidates to verify, NOT truth) ==='
    Assert-True -CaseName 'a: literal Section B header' -Condition ($text.Contains($expectedBHeader)) -Detail 'Section B header missing/divergent'

    $headMatch = [regex]::Match($text, '(?m)^HEAD:\s*([0-9a-f]{40})\s*$')
    $endMatch = [regex]::Match($text, '(?m)^END_DOSSIER sha256=([0-9a-f]{64})\s*$')
    Assert-True -CaseName 'a: HEAD: sentinel' -Condition $headMatch.Success
    Assert-True -CaseName 'a: END_DOSSIER sentinel' -Condition $endMatch.Success

    # Recompute: body = everything before "\nHEAD: "; hash UTF-8 without BOM, LF.
    $idx = $text.LastIndexOf("`nHEAD: ")
    Assert-True -CaseName 'a: body boundary located' -Condition ($idx -gt 0)
    if ($idx -gt 0 -and $endMatch.Success) {
        $body = $text.Substring(0, $idx)
        $bodyLf = ($body -replace "`r`n", "`n" -replace "`r", "`n")
        $enc = Get-Utf8NoBomEncoding
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $hashBytes = $sha.ComputeHash($enc.GetBytes($bodyLf)) } finally { $sha.Dispose() }
        $recomputed = (([System.BitConverter]::ToString($hashBytes)) -replace '-', '').ToLowerInvariant()
        $sentinelHash = $endMatch.Groups[1].Value.ToLowerInvariant()
        Assert-True -CaseName 'a: recomputed sha256 == sentinel' -Condition ($recomputed -eq $sentinelHash) -Detail ("recomputed={0} sentinel={1}" -f $recomputed, $sentinelHash)
        Assert-True -CaseName 'a: recomputed sha256 == bodySha256' -Condition ($recomputed -eq ([string]$json.bodySha256))
    }
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (b1): without git => dossierReady=false
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    Set-RepoFile -Root $tmp -RelativePath 'README.md' -Content '# not a repo'
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'b1: no git => dossierReady=false' -Condition ($json.dossierReady -eq $false) -Detail ("reason={0}" -f $json.notReadyReason)
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (b2): git repo without origin/main => dossierReady=false
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    & git -C $tmp init -b main *> $null
    & git -C $tmp config user.email 'selftest@example.com' *> $null
    & git -C $tmp config user.name 'Self Test' *> $null
    Set-RepoFile -Root $tmp -RelativePath 'README.md' -Content '# base'
    & git -C $tmp add -A *> $null
    & git -C $tmp commit -m 'base' *> $null
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'b2: no origin/main => dossierReady=false' -Condition ($json.dossierReady -eq $false) -Detail ("reason={0}" -f $json.notReadyReason)
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (c): VALID JSON + exit != 0 (mechanical parse gate failed) => mechanicalStatus
# =failed, dossierReady=true, and the fields come FROM the JSON (parseOk=true). Contrasts
# with case (o) (unparseable JSON => degraded mode => pushReadiness/intervalDiffDiagnosticOnly
# indeterminate). The broken .ps1 makes the parse gate fail: the mechanical routine exits 1
# but emits valid JSON; commitsBehind=0 (HEAD ahead by 1, behind by 0) => pushReadiness='ok'.
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    [void](Initialize-DossierRepo -Root $tmp -BrokenScript)
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'c: dossierReady=true (even with broken parse)' -Condition ($json.dossierReady -eq $true)
    Assert-True -CaseName 'c: mechanicalStatus=failed' -Condition ($json.mechanicalStatus -eq 'failed') -Detail ("mechanicalStatus={0} exit={1}" -f $json.mechanicalStatus, $json.mechanicalExitCode)
    Assert-True -CaseName 'c: mechanicalExitCode != 0 with valid JSON' -Condition ($json.mechanicalExitCode -ne 0) -Detail ("exit={0}" -f $json.mechanicalExitCode)
    Assert-True -CaseName 'c: pushReadiness comes from JSON (ok, NOT degraded unknown)' -Condition ($json.pushReadiness -eq 'ok') -Detail ("pushReadiness={0}" -f $json.pushReadiness)
    Assert-True -CaseName 'c: intervalDiffDiagnosticOnly from JSON (false bool, NOT null)' -Condition ($json.intervalDiffDiagnosticOnly -eq $false) -Detail ("intervalDiffDiagnosticOnly={0}" -f $json.intervalDiffDiagnosticOnly)
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (d): commitsBehind>0 => pushReadiness=blocked + intervalDiffDiagnosticOnly
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    $baseSha = Initialize-DossierRepo -Root $tmp
    # origin/main points at HEAD (feature); reset HEAD to base => HEAD behind by 1.
    $featureSha = (& git -C $tmp rev-parse HEAD).Trim()
    & git -C $tmp update-ref refs/remotes/origin/main $featureSha *> $null
    & git -C $tmp reset --hard $baseSha *> $null
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'd: commitsBehind>0' -Condition ($json.commitsBehind -gt 0) -Detail ("commitsBehind={0}" -f $json.commitsBehind)
    Assert-True -CaseName 'd: pushReadiness=blocked' -Condition ($json.pushReadiness -eq 'blocked') -Detail ("pushReadiness={0}" -f $json.pushReadiness)
    Assert-True -CaseName 'd: intervalDiffDiagnosticOnly=true' -Condition ($json.intervalDiffDiagnosticOnly -eq $true)
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (e): remoteFreshness derived from FetchStatus
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    [void](Initialize-DossierRepo -Root $tmp)
    $jsonNotFetched = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-FetchStatus', 'not-fetched', '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'e: not-fetched => remoteFreshness=stale' -Condition ($jsonNotFetched.remoteFreshness -eq 'stale')
    $jsonFailed = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-FetchStatus', 'fetch-failed', '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'e: fetch-failed => remoteFreshness=stale' -Condition ($jsonFailed.remoteFreshness -eq 'stale')
    $jsonFetched = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-FetchStatus', 'fetched', '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'e: fetched => remoteFreshness=fresh' -Condition ($jsonFetched.remoteFreshness -eq 'fresh')
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (f): reported sizeChars is consistent with the dossierText
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    [void](Initialize-DossierRepo -Root $tmp)
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'f: sizeChars>0' -Condition ($json.sizeChars -gt 0)
    Assert-True -CaseName 'f: sizeChars == len(dossierText)' -Condition ($json.sizeChars -eq ([string]$json.dossierText).Length) -Detail ("sizeChars={0} len={1}" -f $json.sizeChars, ([string]$json.dossierText).Length)
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (n): dirty working tree => workingTreeDirty + path list
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    [void](Initialize-DossierRepo -Root $tmp)
    Set-RepoFile -Root $tmp -RelativePath 'README.md' -Content "# base modified without a commit`n"
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'n: workingTreeDirty=true' -Condition ($json.workingTreeDirty -eq $true)
    $dirty = @($json.dirtyPaths)
    Assert-True -CaseName 'n: dirty path list stamped' -Condition ($dirty.Count -gt 0 -and ($dirty -contains 'README.md')) -Detail ("dirtyPaths={0}" -f ($dirty -join ', '))
}
finally { Remove-TempDir -Path $tmp }

# ---------------------------------------------------------------------------
# Case (o): unparseable mechanical routine (degraded mode, a') => the builder only
# reaffirms the raw commitsBehind fact; pushReadiness/intervalDiffDiagnosticOnly stay
# indeterminate (the engine's push-ready policy is NOT re-enacted by the builder on failure).
# ---------------------------------------------------------------------------
$tmp = New-TempDir
$fakeMech = Join-Path ([System.IO.Path]::GetTempPath()) ('fake-mech-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $baseSha = Initialize-DossierRepo -Root $tmp
    # HEAD behind origin/main by 1 (commitsBehind>0), as in case (d)
    $featureSha = (& git -C $tmp rev-parse HEAD).Trim()
    & git -C $tmp update-ref refs/remotes/origin/main $featureSha *> $null
    & git -C $tmp reset --hard $baseSha *> $null
    # Fake mechanical routine: NON-JSON output + exit 1 => builder parseOk=false (degraded mode)
    Set-Content -LiteralPath $fakeMech -Value "param([string]`$RootPath,[string]`$BaseRef,[switch]`$AsJson)`nWrite-Output 'BOOM: non-JSON output from the mechanical routine'`nexit 1" -Encoding utf8 -NoNewline
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-MechanicalScriptPath', $fakeMech, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'o: dossierReady=true (unparseable mechanical routine)' -Condition ($json.dossierReady -eq $true)
    Assert-True -CaseName 'o: mechanicalStatus=failed' -Condition ($json.mechanicalStatus -eq 'failed') -Detail ("status={0}" -f $json.mechanicalStatus)
    Assert-True -CaseName 'o: raw commitsBehind preserved (>0)' -Condition ($json.commitsBehind -gt 0) -Detail ("commitsBehind={0}" -f $json.commitsBehind)
    Assert-True -CaseName 'o: pushReadiness=unknown (policy NOT re-enacted)' -Condition ($json.pushReadiness -eq 'unknown') -Detail ("pushReadiness={0}" -f $json.pushReadiness)
    Assert-True -CaseName 'o: intervalDiffDiagnosticOnly indeterminate (null)' -Condition ($null -eq $json.intervalDiffDiagnosticOnly) -Detail ("intervalDiffDiagnosticOnly={0}" -f $json.intervalDiffDiagnosticOnly)
}
finally {
    Remove-TempDir -Path $tmp
    if (Test-Path -LiteralPath $fakeMech) { Remove-Item -LiteralPath $fakeMech -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------------------
# Case (p): origin/main exists but HEAD is UNBORN (pending symref) => the builder
# does not throw under StrictMode; it returns dossierReady=false, notReadyReason='head-unresolved'.
# Setup: commit (creates refs/heads/main + origin/main) and then delete refs/heads/main,
# leaving HEAD pointing at a nonexistent ref (rev-parse HEAD fails).
# ---------------------------------------------------------------------------
$tmp = New-TempDir
try {
    & git -C $tmp init -b main *> $null
    & git -C $tmp config user.email 'selftest@example.com' *> $null
    & git -C $tmp config user.name 'Self Test' *> $null
    Set-RepoFile -Root $tmp -RelativePath 'README.md' -Content '# base'
    & git -C $tmp add -A *> $null
    & git -C $tmp commit -m 'base' *> $null
    $baseSha = (& git -C $tmp rev-parse HEAD).Trim()
    & git -C $tmp update-ref refs/remotes/origin/main $baseSha *> $null
    & git -C $tmp update-ref -d refs/heads/main *> $null   # HEAD -> nonexistent refs/heads/main
    $json = Invoke-Builder -BuilderArgs @('-RootPath', $tmp, '-AsJson') | ConvertFrom-Json
    Assert-True -CaseName 'p: unborn HEAD => dossierReady=false (does not throw)' -Condition ($json.dossierReady -eq $false) -Detail ("reason={0}" -f $json.notReadyReason)
    Assert-True -CaseName 'p: notReadyReason=head-unresolved' -Condition ($json.notReadyReason -eq 'head-unresolved') -Detail ("reason={0}" -f $json.notReadyReason)
}
finally { Remove-TempDir -Path $tmp }

Write-Output '---'
if ($failures -eq 0) {
    Write-Output ("SELFTEST_OK: {0}/{0} asserts passed" -f $cases)
    Write-Output 'BUILD_PREPUSH_REVIEW_DOSSIER_SELFTEST_OK'
    exit 0
} else {
    Write-Output ("SELFTEST_FAIL: {0} of {1} asserts failed" -f $failures, $cases)
    exit 1
}
