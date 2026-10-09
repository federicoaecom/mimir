#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/Test-MarkdownLinks.ps1: relative markdown links and bare
    `NN-*.md` file mentions must resolve to a real file; external URLs,
    docs/originals/ and CHANGELOG.md are skipped.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path $repoRoot 'tools\Test-MarkdownLinks.ps1'
if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
    throw "BLOCK: tool not found: $toolPath"
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-mdlinks-selftest-' + [guid]::NewGuid().ToString('N'))
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
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'sub') -Force | Out-Null
    Write-Fixture -RelativePath 'sub/target.md' -Content "# Target`n"
    Write-Fixture -RelativePath '01-something.md' -Content "# Something`n"

    Write-Fixture -RelativePath 'good.md' -Content @'
See [good link](sub/target.md) and bare mention 01-something.md here.
'@

    Write-Fixture -RelativePath 'bad.md' -Content @'
See [bad link](sub/missing.md) and bare mention 99-nonexistent.md here.
'@

    # Date-stamped filenames (YYYY-MM-DD-slug.md) must not be misread as a bare
    # `NN-*.md` mention starting mid-string (e.g. "09-25-..." or "25-....md").
    Write-Fixture -RelativePath 'dated.md' -Content @'
See docs/evidence/2026-09-25-some-report.md for details.
'@

    Write-Fixture -RelativePath 'external.md' -Content @'
See [external](https://example.com/foo.md) and [mail](mailto:a@b.com) and [anchor only](#section).
'@

    Write-Fixture -RelativePath 'docs/originals/skip.md' -Content @'
See [broken but skipped](nope.md).
'@

    Write-Fixture -RelativePath 'CHANGELOG.md' -Content @'
See [broken but skipped](also-nope.md).
'@

    $jsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RootPath $fixtureRoot -AsJson
    $exitCode = $LASTEXITCODE
    $report = ($jsonRaw -join "`n") | ConvertFrom-Json

    Assert-True ($exitCode -ne 0) "tool should exit non-zero when broken links/mentions exist (got $exitCode)"
    Assert-True ($report.findings.Count -eq 2) "expected exactly 2 findings (bad.md link + bad.md bare mention), got $($report.findings.Count): $($report.findings | ConvertTo-Json -Compress)"

    $badFindings = @($report.findings | Where-Object { $_.file -like '*bad.md' })
    Assert-True ($badFindings.Count -eq 2) "both findings should be attributed to bad.md, got $($badFindings.Count)"

    $skipHit = @($report.findings | Where-Object { $_.file -like '*docs*originals*' -or $_.file -like '*CHANGELOG.md' })
    Assert-True ($skipHit.Count -eq 0) "docs/originals/ and CHANGELOG.md must be skipped as sources"

    # Re-run over just good.md + external.md's directory tree indirectly by checking they contributed 0 findings
    $goodOrExternalHit = @($report.findings | Where-Object { $_.file -like '*good.md' -or $_.file -like '*external.md' })
    Assert-True ($goodOrExternalHit.Count -eq 0) "good.md and external.md must produce zero findings"

    $datedHit = @($report.findings | Where-Object { $_.file -like '*dated.md' })
    Assert-True ($datedHit.Count -eq 0) "a YYYY-MM-DD-slug.md mention must not be misread as a bare NN-*.md mention (got: $($datedHit | ConvertTo-Json -Compress))"

    # -IncludePaths restricts which files are scanned as *sources* (their own
    # broken links/mentions are only reported when they fall under an include
    # prefix), while a link *target* can still resolve anywhere in the tree
    # (basenameMap / candidate resolution stay repo-wide).
    Write-Fixture -RelativePath 'included/inside.md' -Content @'
See [broken](missing-inside.md).
'@
    Write-Fixture -RelativePath 'excluded/outside.md' -Content @'
See [broken](missing-outside.md).
'@

    $jsonIncludeRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RootPath $fixtureRoot -IncludePaths 'included' -AsJson
    $includeExitCode = $LASTEXITCODE
    $includeReport = ($jsonIncludeRaw -join "`n") | ConvertFrom-Json

    Assert-True ($includeExitCode -ne 0) "tool should still exit non-zero when the included set has a finding (got $includeExitCode)"
    $insideHit = @($includeReport.findings | Where-Object { $_.file -like '*included*inside.md' })
    Assert-True ($insideHit.Count -eq 1) "included/inside.md's own broken link must be reported under -IncludePaths 'included' (got $($insideHit.Count))"
    $outsideHit = @($includeReport.findings | Where-Object { $_.file -like '*excluded*outside.md' })
    Assert-True ($outsideHit.Count -eq 0) "excluded/outside.md must not be scanned as a source under -IncludePaths 'included' (got $($outsideHit.Count))"
    $badHitUnderInclude = @($includeReport.findings | Where-Object { $_.file -like '*bad.md' })
    Assert-True ($badHitUnderInclude.Count -eq 0) "root-level bad.md must not be scanned as a source under -IncludePaths 'included' (got $($badHitUnderInclude.Count))"

    # --- Anchor validation (isolated sub-tree, own -RootPath, to keep counts above untouched) ---
    $anchorRoot = Join-Path $fixtureRoot 'anchor-cases'
    New-Item -ItemType Directory -Path $anchorRoot -Force | Out-Null

    Write-Fixture -RelativePath 'anchor-cases/target.md' -Content @'
# Target With Headings

## First Section

## First Section

Some text.

```text
# Not A Heading Inside Fence
```
'@

    Write-Fixture -RelativePath 'anchor-cases/linker.md' -Content @'
See [good](target.md#first-section) and [good-dup](target.md#first-section-1) and [good-top](target.md#target-with-headings) and [bad](target.md#missing-section) and [bad-fenced](target.md#not-a-heading-inside-fence) and [anchor-only](#not-checked) and [no-anchor](target.md).
'@

    $anchorJsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RootPath $anchorRoot -AsJson
    $anchorExitCode = $LASTEXITCODE
    $anchorReport = ($anchorJsonRaw -join "`n") | ConvertFrom-Json

    Assert-True ($anchorExitCode -ne 0) "tool should exit non-zero when a broken anchor exists (got $anchorExitCode)"

    $anchorKindFindings = @($anchorReport.findings | Where-Object { $_.kind -eq 'anchor' })
    Assert-True ($anchorKindFindings.Count -eq 2) "expected exactly 2 anchor findings (missing-section + fenced pseudo-heading), got $($anchorKindFindings.Count): $($anchorReport.findings | ConvertTo-Json -Compress)"

    $anchorTargets = @($anchorKindFindings | ForEach-Object { $_.target })
    Assert-True ($anchorTargets -contains 'target.md#missing-section') "a non-existent anchor on an existing target file must be flagged as kind=anchor"
    Assert-True ($anchorTargets -contains 'target.md#not-a-heading-inside-fence') "a heading-shaped line inside a fenced code block must not count as a real anchor"

    $linkKindFindingsInAnchorCases = @($anchorReport.findings | Where-Object { $_.kind -eq 'link' })
    Assert-True ($linkKindFindingsInAnchorCases.Count -eq 0) "no target-file-missing findings expected in the anchor-cases sub-tree, got $($linkKindFindingsInAnchorCases.Count)"

    Assert-True ($anchorReport.findings.Count -eq 2) "total findings in anchor-cases must be exactly the 2 anchor findings (valid anchors, a duplicate-heading anchor, a pure #anchor-only link, and a plain file link with no anchor must all produce zero findings), got $($anchorReport.findings.Count)"
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: Test-MarkdownLinksSelfTest.ps1" -ForegroundColor Green
exit 0
