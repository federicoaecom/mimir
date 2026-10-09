#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/Test-TextEncoding.ps1: tracked text files must be UTF-8
    without BOM and use LF line endings; docs/originals/ is skipped.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$toolPath = Join-Path $repoRoot 'tools\Test-TextEncoding.ps1'
if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
    throw "BLOCK: tool not found: $toolPath"
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-textencoding-selftest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

function Write-BytesFile {
    param([string]$RelativePath, [byte[]]$Bytes)
    $full = Join-Path $fixtureRoot $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    [System.IO.File]::WriteAllBytes($full, $Bytes)
}

try {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $bomPreamble = [byte[]]@(0xEF, 0xBB, 0xBF)

    # 1) Good: UTF-8 no BOM, LF only.
    Write-BytesFile -RelativePath 'good.md' -Bytes ($utf8NoBom.GetBytes("linha um`nlinha dois`n"))

    # 2) Bad: has a UTF-8 BOM.
    Write-BytesFile -RelativePath 'bom.md' -Bytes ($bomPreamble + $utf8NoBom.GetBytes("linha com bom`n"))

    # 3) Bad: has CRLF line endings.
    Write-BytesFile -RelativePath 'crlf.ps1' -Bytes ($utf8NoBom.GetBytes("linha um`r`nlinha dois`r`n"))

    # 4) Skipped despite being bad on both counts.
    Write-BytesFile -RelativePath 'docs/originals/skip.md' -Bytes ($bomPreamble + $utf8NoBom.GetBytes("linha com bom`r`n"))

    $jsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $toolPath -RootPath $fixtureRoot -AsJson
    $exitCode = $LASTEXITCODE
    $report = ($jsonRaw -join "`n") | ConvertFrom-Json

    Assert-True ($exitCode -ne 0) "tool should exit non-zero when BOM/CRLF files exist (got $exitCode)"
    Assert-True ($report.findings.Count -eq 2) "expected exactly 2 findings (bom.md + crlf.ps1), got $($report.findings.Count): $($report.findings | ConvertTo-Json -Compress)"

    $bomFinding = @($report.findings | Where-Object { $_.file -like '*bom.md' -and $_.file -notlike '*originals*' })
    Assert-True ($bomFinding.Count -eq 1) "bom.md should be flagged for a BOM"
    if ($bomFinding.Count -eq 1) {
        Assert-True ($bomFinding[0].issues -contains 'bom') "bom.md's finding should list 'bom' as an issue"
    }

    $crlfFinding = @($report.findings | Where-Object { $_.file -like '*crlf.ps1' })
    Assert-True ($crlfFinding.Count -eq 1) "crlf.ps1 should be flagged for CRLF"
    if ($crlfFinding.Count -eq 1) {
        Assert-True ($crlfFinding[0].issues -contains 'crlf') "crlf.ps1's finding should list 'crlf' as an issue"
    }

    $skipHit = @($report.findings | Where-Object { $_.file -like '*docs*originals*' })
    Assert-True ($skipHit.Count -eq 0) "docs/originals/ must be skipped"

    $goodHit = @($report.findings | Where-Object { $_.file -like '*good.md' })
    Assert-True ($goodHit.Count -eq 0) "good.md must produce zero findings"
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: Test-TextEncodingSelfTest.ps1" -ForegroundColor Green
exit 0
