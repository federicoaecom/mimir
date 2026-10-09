#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for Test-PrePushGateEnumerationParity.ps1.

.DESCRIPTION
    Builds a temporary root with a synthetic orchestrator that invokes three
    semantic gates (Alpha/Beta/Gamma) and two parse gates (excluded by
    default), and a root .md with four lines. Confirms:
      - a line that enumerates 2 of the 3 semantic gates -> candidate (proper subset);
      - a line that co-cites the parse pair -> does NOT become a candidate (excluded pair);
      - a line that enumerates all 3 semantic gates -> does NOT become a candidate (complete set);
      - a line with a single gate -> does NOT become a candidate.
    Does not need git: the gate is invariant (reads the orchestrator + .md, no diff).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools') 'Test-PrePushGateEnumerationParity.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-gate-enum-parity-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'tools') -Force)

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

try {
    # Synthetic orchestrator: 3 semantic gates + 2 parse gates (excluded).
    $orchestrator = @'
$a = Join-Path $PSScriptRoot 'Test-Alpha.ps1'
$b = Join-Path $PSScriptRoot 'Test-Beta.ps1'
$g = Join-Path $PSScriptRoot 'Test-Gamma.ps1'
$p1 = Join-Path $PSScriptRoot 'Test-PsScriptsParse.ps1'
$p2 = Join-Path $PSScriptRoot 'Test-PyScriptsParse.ps1'
'@
    Write-TempFile -RelativePath 'tools/Invoke-PrePushMechanicalChecks.ps1' -Content $orchestrator

    $doc = @'
# Routine doc

- The semantic gates are `Test-Alpha.ps1` and `Test-Beta.ps1`.
- The delegated parse (`Test-PsScriptsParse.ps1` and `Test-PyScriptsParse.ps1`) scans the repo.
- Complete set: `Test-Alpha.ps1`, `Test-Beta.ps1` and `Test-Gamma.ps1`.
- Only `Test-Gamma.ps1` covers the isolated case.
'@
    Write-TempFile -RelativePath 'doc-rotina.md' -Content $doc

    $output = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -AsJson 2>&1
    $exitCode = $LASTEXITCODE
    $jsonText = ($output | Out-String).Trim()
    $result = $jsonText | ConvertFrom-Json

    if ($exitCode -ne 0) {
        throw "gate should exit with 0 (advisory); got $exitCode. Output: $jsonText"
    }
    if ($result.status -ne 'warn') {
        throw "status should be 'warn'; got '$($result.status)'. Output: $jsonText"
    }
    if (@($result.orchestratorGates).Count -ne 3) {
        throw "the derived set should have 3 gates (parse excluded); got $(@($result.orchestratorGates) -join ', ')"
    }
    if ($result.candidateCount -ne 1) {
        throw "there should be exactly 1 candidate (2-of-3 line); got $($result.candidateCount). Findings: $(@($result.findings | ForEach-Object { $_.path }) -join ', ')"
    }

    $finding = $result.findings[0]
    if ($finding.message -notmatch 'Test-Alpha\.ps1' -or $finding.message -notmatch 'Test-Beta\.ps1') {
        throw "the candidate should enumerate Alpha and Beta; message: $($finding.message)"
    }
    if ($finding.message -notmatch 'Test-Gamma\.ps1') {
        throw "the candidate should point out Gamma as missing; message: $($finding.message)"
    }

    Write-Output 'OK: Test-PrePushGateEnumerationParitySelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
