#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for Test-PrePushNewTokenPropagation.ps1.

.DESCRIPTION
    Builds a temporary git repository that reproduces the structure of the real gap
    (the XPZ JSON standardization workstream): an engine gains the -ObjectList
    alias co-located with -ObjectNames/-ObjectGuids (transition in the diff), while an
    example keeps mentioning the old set without the new alias. Confirms:
      - positive case: the stale mention becomes a candidate (status=warn);
      - negative control: an already-propagated mention does not become a candidate;
      - the parameter's own declaration (.PARAMETER) does not become a candidate;
      - shape classification (mentionClass): running prose -> 'prose',
        a parameter list item -> 'param-list-item', a line inside a fenced
        code block -> 'command-example';
      - class-aware truncation: with a low cap and abundant prose, the
        prose is limited (truncatedProseCount > 0) but the non-prose candidate
        survives the truncation;
      - the scan's TRACKED universe: a stale mention in a file ignored by
        .gitignore (Temp/, node_modules/) or merely untracked does NOT become a
        candidate, while the equivalent tracked mention keeps becoming one —
        this guards against a regression back to the filesystem walk, which
        inflated the verdict ledger with material that is not a repo document.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools') 'Test-PrePushNewTokenPropagation.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-newtoken-propagation-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Utf8NoBomEncodingSupport.ps1')
$utf8NoBom = Get-Utf8NoBomEncoding
function Write-TempFile {
    param([string]$RelativePath, [string]$Content)
    $full = Join-Path $tempRoot $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
}

function Invoke-TempGit {
    param([string[]]$Arguments)
    $output = & git -C $tempRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("git {0} failed: {1}" -f ($Arguments -join ' '), (($output | Out-String).Trim()))
    }
    return $output
}

try {
    [void](Invoke-TempGit @('init', '-q'))
    [void](Invoke-TempGit @('config', 'user.email', 'selftest@example.com'))
    [void](Invoke-TempGit @('config', 'user.name', 'Self Test'))
    [void](Invoke-TempGit @('config', 'commit.gpgsign', 'false'))

    # --- Base state: without -ObjectList ---
    $engineBase = @'
[CmdletBinding()]
param(
    [string[]]$ObjectNames,
    [string[]]$ObjectGuids
)
<#
.PARAMETER ObjectNames
Object names to copy.
#>
# When -ObjectNames or -ObjectGuids is provided, only the listed ones are copied.
if ($null -ne $ObjectGuids -and $ObjectGuids.Count -gt 0) { $usaGuids = $true }
'@
    Write-TempFile -RelativePath 'engine.ps1' -Content $engineBase

    # Equivalent mention that will become stale (without ObjectList).
    Write-TempFile -RelativePath 'exemplo.md' -Content "When ObjectNames or ObjectGuids is provided, it seeds the object.`n"

    # Negative control: an already-propagated mention.
    Write-TempFile -RelativePath 'ok-doc.md' -Content "Use ObjectList, ObjectNames or ObjectGuids to select objects.`n"

    # Stale mention in a parameter list item (param-list-item class).
    $paramListDoc = @'
Parameters:

- `-ObjectNames` object names to copy
'@
    Write-TempFile -RelativePath 'param-list.md' -Content ($paramListDoc + "`n")

    # Stale mention inside a fenced code block (command-example class).
    $cmdDoc = @'
Command example:

```text
& ./engine.ps1 -ObjectNames Proc:Foo
```
'@
    Write-TempFile -RelativePath 'cmd.md' -Content ($cmdDoc + "`n")

    [void](Invoke-TempGit @('add', '-A'))
    [void](Invoke-TempGit @('commit', '-q', '-m', 'base'))
    $baseSha = (Invoke-TempGit @('rev-parse', 'HEAD') | Out-String).Trim()

    # --- HEAD: introduces co-located -ObjectList (transition) ---
    $engineHead = @'
[CmdletBinding()]
param(
    [string[]]$ObjectList,
    [string[]]$ObjectNames,
    [string[]]$ObjectGuids
)
<#
.PARAMETER ObjectList
Operational alias.
.PARAMETER ObjectNames
Object names to copy.
#>
# When -ObjectList, -ObjectNames or -ObjectGuids is provided, only the listed ones are copied.
if ($null -ne $ObjectGuids -and $ObjectGuids.Count -gt 0) { $usaGuids = $true }
'@
    Write-TempFile -RelativePath 'engine.ps1' -Content $engineHead
    # exemplo.md and ok-doc.md remain unchanged.

    [void](Invoke-TempGit @('add', '-A'))
    [void](Invoke-TempGit @('commit', '-q', '-m', 'introduce ObjectList'))

    $output = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -BaseRef $baseSha -AsJson 2>&1
    $exitCode = $LASTEXITCODE
    $jsonText = ($output | Out-String).Trim()
    $result = $jsonText | ConvertFrom-Json

    if ($exitCode -ne 0) {
        throw "gate should exit with 0 (advisory); got $exitCode. Output: $jsonText"
    }
    if ($result.status -ne 'warn') {
        throw "status should be 'warn' (there is a stale mention); got '$($result.status)'. Output: $jsonText"
    }
    if (@($result.introducedTokens) -notcontains 'ObjectList') {
        throw "introducedTokens should contain 'ObjectList'; got: $(@($result.introducedTokens) -join ', ')"
    }

    $candidatePaths = @($result.findings | ForEach-Object { $_.path })
    $exemploHit = @($candidatePaths | Where-Object { $_ -like 'exemplo.md:*' })
    if ($exemploHit.Count -eq 0) {
        throw "exemplo.md (stale mention) should become a candidate; candidates: $($candidatePaths -join ', ')"
    }

    $okHit = @($candidatePaths | Where-Object { $_ -like 'ok-doc.md:*' })
    if ($okHit.Count -ne 0) {
        throw "ok-doc.md (negative control, already propagated) should NOT become a candidate; candidates: $($candidatePaths -join ', ')"
    }

    $engineHit = @($candidatePaths | Where-Object { $_ -like 'engine.ps1:*' })
    if ($engineHit.Count -ne 0) {
        throw "engine.ps1 should not produce a candidate (description already propagated; .PARAMETER and declaration filtered out); candidates: $($candidatePaths -join ', ')"
    }

    # --- Shape classification (mentionClass) ---
    $exemploFinding = @($result.findings | Where-Object { $_.path -like 'exemplo.md:*' })[0]
    if ($exemploFinding.mentionClass -ne 'prose') {
        throw "exemplo.md should have mentionClass='prose'; got '$($exemploFinding.mentionClass)'"
    }

    $paramListFinding = @($result.findings | Where-Object { $_.path -like 'param-list.md:*' })
    if ($paramListFinding.Count -eq 0) {
        throw "param-list.md (stale list item) should become a candidate; candidates: $($candidatePaths -join ', ')"
    }
    if ($paramListFinding[0].mentionClass -ne 'param-list-item') {
        throw "param-list.md should have mentionClass='param-list-item'; got '$($paramListFinding[0].mentionClass)'"
    }

    $cmdFinding = @($result.findings | Where-Object { $_.path -like 'cmd.md:*' })
    if ($cmdFinding.Count -eq 0) {
        throw "cmd.md (line inside a fenced block) should become a candidate; candidates: $($candidatePaths -join ', ')"
    }
    if ($cmdFinding[0].mentionClass -ne 'command-example') {
        throw "cmd.md should have mentionClass='command-example'; got '$($cmdFinding[0].mentionClass)'"
    }

    # --- Class-aware truncation: prose is limited, non-prose never ---
    # Adds abundant prose and runs with a low cap (-MaxFindings 2); confirms
    # that the param-list-item candidate (param-list.md) survives the truncation and
    # that prose respects the cap.
    Write-TempFile -RelativePath 'prose-a.md' -Content "See ObjectNames for flow details.`n"
    Write-TempFile -RelativePath 'prose-b.md' -Content "The flow uses ObjectNames at this point.`n"
    Write-TempFile -RelativePath 'prose-c.md' -Content "Check ObjectNames before the seed.`n"
    [void](Invoke-TempGit @('add', '-A'))
    [void](Invoke-TempGit @('commit', '-q', '-m', 'abundant prose'))

    $truncOutput = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -BaseRef $baseSha -AsJson -MaxFindings 2 2>&1
    $truncResult = (($truncOutput | Out-String).Trim()) | ConvertFrom-Json

    if (-not $truncResult.truncated) {
        throw "with -MaxFindings 2 and abundant prose, truncated should be true"
    }
    if ($truncResult.truncatedProseCount -lt 1) {
        throw "truncatedProseCount should be >= 1; got $($truncResult.truncatedProseCount)"
    }
    $proseKept = @($truncResult.findings | Where-Object { $_.mentionClass -eq 'prose' })
    if ($proseKept.Count -gt 2) {
        throw "retained prose should respect the cap (<=2); got $($proseKept.Count)"
    }
    $truncPaths = @($truncResult.findings | ForEach-Object { $_.path })
    $paramListKept = @($truncPaths | Where-Object { $_ -like 'param-list.md:*' })
    if ($paramListKept.Count -eq 0) {
        throw "the param-list-item candidate should NOT be truncated by the cap; missing from: $($truncPaths -join ', ')"
    }

    # --- TRACKED universe: ignored/untracked stays out of the scan ---
    # The scan uses `git ls-files`; ignored material (a scratch draft under
    # Temp/, a vendored dependency under node_modules/) or merely untracked
    # material is not a repository document: it cannot become stale on a push and
    # would only inflate the verdict ledger required by the orchestrator.
    Write-TempFile -RelativePath '.gitignore' -Content "Temp/`nnode_modules/`n"
    Write-TempFile -RelativePath 'Temp/draft.md' -Content "Draft: use ObjectNames for now.`n"
    Write-TempFile -RelativePath 'node_modules/vendor.md' -Content "Vendor doc mentions ObjectNames only.`n"
    # Not ignored, but never added to the index (merely untracked).
    Write-TempFile -RelativePath 'untracked.md' -Content "Loose note citing ObjectNames.`n"
    [void](Invoke-TempGit @('add', '.gitignore'))
    [void](Invoke-TempGit @('commit', '-q', '-m', 'ignore Temp and node_modules'))

    $trackedOutput = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -BaseRef $baseSha -AsJson 2>&1
    $trackedResult = (($trackedOutput | Out-String).Trim()) | ConvertFrom-Json
    $trackedPaths = @($trackedResult.findings | ForEach-Object { $_.path })

    foreach ($outsidePath in @('draft.md', 'vendor.md', 'untracked.md')) {
        $hit = @($trackedPaths | Where-Object { $_ -like "*$outsidePath*" })
        if ($hit.Count -ne 0) {
            throw "$outsidePath is not tracked and should NOT become a candidate (regression to the filesystem walk); candidates: $($trackedPaths -join ', ')"
        }
    }

    # Positive control in the same run: the equivalent TRACKED mention keeps
    # becoming a candidate — proves the scan did not end up empty by accident.
    $versionadoHit = @($trackedPaths | Where-Object { $_ -like 'exemplo.md:*' })
    if ($versionadoHit.Count -eq 0) {
        throw "exemplo.md (stale TRACKED mention) should remain a candidate; candidates: $($trackedPaths -join ', ')"
    }

    # --- Scanned extensions: same set as git's '*.md' '*.ps1' '*.py' pathspec ---
    # Tracked files are selected by extension at any depth, case-sensitively
    # (git pathspec matching ignores core.ignorecase), and the selection must
    # not depend on the shell: pwsh on Unix expands a wildcard argument passed
    # to a native command against the current directory.
    Write-TempFile -RelativePath 'docs/deep/nested.md' -Content "Nested note: see ObjectNames.`n"
    Write-TempFile -RelativePath 'docs/deep/nested-tool.py' -Content "# Reads ObjectNames from the caller.`n"
    Write-TempFile -RelativePath 'notes.txt' -Content "Plain text citing ObjectNames.`n"
    Write-TempFile -RelativePath 'UPPER.MD' -Content "Upper-case extension citing ObjectNames.`n"
    [void](Invoke-TempGit @('add', '-A'))
    [void](Invoke-TempGit @('commit', '-q', '-m', 'add extension-set fixtures'))

    $extOutput = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -BaseRef $baseSha -AsJson 2>&1
    $extResult = (($extOutput | Out-String).Trim()) | ConvertFrom-Json
    $extPaths = @($extResult.findings | ForEach-Object { $_.path })
    foreach ($expectedPath in @('docs/deep/nested.md', 'docs/deep/nested-tool.py')) {
        if (@($extPaths | Where-Object { $_ -like "${expectedPath}:*" }).Count -eq 0) {
            throw "$expectedPath (tracked, scanned extension, nested) should be a candidate; candidates: $($extPaths -join ', ')"
        }
    }
    foreach ($excludedPath in @('notes.txt', 'UPPER.MD')) {
        if (@($extPaths | Where-Object { $_ -like "${excludedPath}:*" }).Count -ne 0) {
            throw "$excludedPath (extension outside the case-sensitive .md/.ps1/.py set) should NOT be a candidate; candidates: $($extPaths -join ', ')"
        }
    }

    Write-Output 'OK: Test-PrePushNewTokenPropagationSelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
