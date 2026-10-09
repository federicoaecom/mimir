#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/Test-MarkdownFences.ps1: a fence opened with ``` or
    ~~~ must be closed by a matching fence of at least the same length and
    the same character; a lone or double backtick/tilde line where a real
    closer was evidently intended is reported, and so is a fence still open
    at end of file. docs/originals/ is skipped.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path $repoRoot 'tools\Test-MarkdownFences.ps1'
if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
    throw "BLOCK: tool not found: $toolPath"
}

$failures = [System.Collections.Generic.List[string]]::new()
$sourceLines = [System.IO.File]::ReadAllLines($PSCommandPath)
$trailingWhitespaceLines = @(
    for ($i = 0; $i -lt $sourceLines.Length; $i++) {
        if ($sourceLines[$i] -match '[ \t]$') { $i + 1 }
    }
)
if ($trailingWhitespaceLines.Count -gt 0) {
    throw "Self-test source has trailing whitespace on line(s): $($trailingWhitespaceLines -join ', ')"
}
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-mdfences-selftest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Fixture {
    param([string]$RelativePath, [string]$Content)
    $full = Join-Path $fixtureRoot $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
}

try {
    # --- RED case 1: lone-backtick close (the real-world corruption this
    # tool exists to catch: a fence "closed" by a single stray backtick,
    # which does not actually close it per CommonMark, so the following
    # heading/prose gets swallowed as literal code content until a real
    # closer eventually appears further down). ---
    $loneBacktickContent = @'
# Doc

```xml
<Object/>
__MALFORMED_CLOSER__

### Next section
Prose here.

```
'@
    $loneBacktickContent = $loneBacktickContent.Replace('__MALFORMED_CLOSER__', [string][char]96 + [char]32)
    Write-Fixture -RelativePath 'lone-backtick.md' -Content $loneBacktickContent

    # --- RED case 2: unclosed at EOF (no closing fence at all). ---
    Write-Fixture -RelativePath 'unclosed-eof.md' -Content @'
# Doc

```xml
<Object/>
'@

    # --- RED case 3: ~~~ vs ``` (a fence opened with ``` is never closed by
    # ~~~, even though ~~~ is a valid 3+-length fence marker for its OWN
    # kind; the ``` opener is left open through EOF). ---
    Write-Fixture -RelativePath 'tilde-vs-backtick.md' -Content @'
# Doc

```xml
<Object/>
~~~
'@

    # --- GREEN case 1: well-formed backtick fence. ---
    Write-Fixture -RelativePath 'good-backtick.md' -Content @'
# Doc

```xml
<Object/>
```

Prose after, properly closed.
'@

    # --- GREEN case 2: well-formed tilde fence. ---
    Write-Fixture -RelativePath 'good-tilde.md' -Content @'
# Doc

~~~xml
<Object/>
~~~

Prose after, properly closed.
'@

    # --- GREEN case 3: a longer closer than the opener (valid per
    # CommonMark: closer must be >= opener length, same character), and a
    # closer with a longer marker still matching by character. ---
    Write-Fixture -RelativePath 'good-longer-closer.md' -Content @'
# Doc

```xml
<Object/>
````

Prose after, properly closed (4-backtick close for a 3-backtick open is valid).
'@

    $jsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RootPath $fixtureRoot -AsJson
    $exitCode = $LASTEXITCODE
    $report = ($jsonRaw -join "`n") | ConvertFrom-Json

    Assert-True ($exitCode -ne 0) "tool should exit non-zero when malformed/unclosed fences exist (got $exitCode)"

    $loneBacktickHits = @($report.findings | Where-Object { $_.file -like '*lone-backtick.md' })
    Assert-True ($loneBacktickHits.Count -eq 1) "lone-backtick.md should produce exactly 1 finding, got $($loneBacktickHits.Count): $($loneBacktickHits | ConvertTo-Json -Compress)"
    if ($loneBacktickHits.Count -eq 1) {
        Assert-True ($loneBacktickHits[0].kind -eq 'malformed-closer') "lone-backtick.md finding should be kind=malformed-closer, got $($loneBacktickHits[0].kind)"
        Assert-True ($loneBacktickHits[0].found -eq '`') "lone-backtick.md finding should report the lone backtick as the found token, got '$($loneBacktickHits[0].found)'"
        Assert-True ($loneBacktickHits[0].line -eq 5) "lone-backtick.md finding should point at line 5 (the stray backtick), got $($loneBacktickHits[0].line)"
    }

    $unclosedHits = @($report.findings | Where-Object { $_.file -like '*unclosed-eof.md' })
    Assert-True ($unclosedHits.Count -eq 1) "unclosed-eof.md should produce exactly 1 finding, got $($unclosedHits.Count)"
    if ($unclosedHits.Count -eq 1) {
        Assert-True ($unclosedHits[0].kind -eq 'unclosed') "unclosed-eof.md finding should be kind=unclosed, got $($unclosedHits[0].kind)"
        Assert-True ($unclosedHits[0].line -eq 3) "unclosed-eof.md finding should point at the opener line (3), got $($unclosedHits[0].line)"
    }

    $tildeVsBacktickHits = @($report.findings | Where-Object { $_.file -like '*tilde-vs-backtick.md' })
    Assert-True ($tildeVsBacktickHits.Count -eq 1) "tilde-vs-backtick.md should produce exactly 1 finding (the ``` opener stays unclosed), got $($tildeVsBacktickHits.Count)"
    if ($tildeVsBacktickHits.Count -eq 1) {
        Assert-True ($tildeVsBacktickHits[0].kind -eq 'unclosed') "tilde-vs-backtick.md finding should be kind=unclosed (a ~~~ line never closes a ``` opener), got $($tildeVsBacktickHits[0].kind)"
        Assert-True ($tildeVsBacktickHits[0].line -eq 3) "tilde-vs-backtick.md finding should point at the opener line (3), got $($tildeVsBacktickHits[0].line)"
    }

    $goodHits = @($report.findings | Where-Object {
        $_.file -like '*good-backtick.md' -or $_.file -like '*good-tilde.md' -or $_.file -like '*good-longer-closer.md'
    })
    Assert-True ($goodHits.Count -eq 0) "well-formed fence files must produce zero findings, got $($goodHits.Count): $($goodHits | ConvertTo-Json -Compress)"

    Assert-True ($report.findings.Count -eq 3) "expected exactly 3 total findings (one per RED fixture), got $($report.findings.Count)"

    # --- docs/originals/ must be skipped, same convention as the other tools. ---
    Write-Fixture -RelativePath 'docs/originals/skip.md' -Content @'
```xml
<Object/>
`
'@

    $jsonRaw2 = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RootPath $fixtureRoot -AsJson
    $report2 = ($jsonRaw2 -join "`n") | ConvertFrom-Json
    $skipHits = @($report2.findings | Where-Object { $_.file -like '*docs*originals*' })
    Assert-True ($skipHits.Count -eq 0) "docs/originals/ must be skipped as a source"
    Assert-True ($report2.findings.Count -eq 3) "docs/originals/ addition must not change the total finding count, got $($report2.findings.Count)"

    # --- A clean-only run must exit 0 and report 0 findings. ---
    $cleanRoot = Join-Path $fixtureRoot 'clean-only'
    New-Item -ItemType Directory -Path $cleanRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'good-backtick.md') -Destination (Join-Path $cleanRoot 'good-backtick.md')
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'good-tilde.md') -Destination (Join-Path $cleanRoot 'good-tilde.md')

    $cleanJsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RootPath $cleanRoot -AsJson
    $cleanExitCode = $LASTEXITCODE
    $cleanReport = ($cleanJsonRaw -join "`n") | ConvertFrom-Json
    Assert-True ($cleanExitCode -eq 0) "tool should exit 0 when every fence is well-formed (got $cleanExitCode)"
    Assert-True ($cleanReport.status -eq 'pass') "status should be 'pass' for an all-clean tree, got '$($cleanReport.status)'"
    Assert-True ($cleanReport.findings.Count -eq 0) "an all-clean tree must report 0 findings, got $($cleanReport.findings.Count)"
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: Test-MarkdownFencesSelfTest.ps1" -ForegroundColor Green
exit 0
