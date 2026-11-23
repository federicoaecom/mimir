#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/benchmark/Compare-KbIntelligenceBuilds.py.

.DESCRIPTION
    Works in a temporary folder only (the corpus is a temporary copy of tests/fixtures/sample-kb,
    because the builds and queries take the corpus lock, which creates a lock file in the corpus)
    and checks that:
      - two copies of skills/mimir-lite/scripts give identical indexes and query answers on
        tests/fixtures/sample-kb: exit 0, "identical", with the table row counts and the query count;
      - a copy whose engine core lists one type fewer in UNEXTRACTED_CALL_SOURCE_TYPES (a coverage
        entry) is reported: exit 1, "DIFFERENT", naming a reverse query whose answer differs;
      - a scripts folder without the engine scripts is refused with exit 2.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolPath = Join-Path $repoRoot 'tools/benchmark/Compare-KbIntelligenceBuilds.py'
$scriptsPath = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixtureCorpusPath = Join-Path $repoRoot 'tests/fixtures/sample-kb'
. (Join-Path $repoRoot 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-Compare {
    param([object]$Python, [string]$Baseline, [string]$Candidate)
    $arguments = @($Python.PrefixArguments) + @('-B', $toolPath, '--baseline-scripts', $Baseline, '--candidate-scripts', $Candidate, '--corpus', $corpusPath)
    $output = & $Python.Source @arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (@($output | ForEach-Object { "$_" }) -join "`n") }
}

function Copy-Scripts {
    param([string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $scriptsPath -File | Copy-Item -Destination $Destination
    return $Destination
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-compare-builds-selftest-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    # The copy keeps the folder name, which the report prints, and the complete sync state.
    $corpusPath = Join-Path $fixtureRoot 'sample-kb'
    Copy-Item -LiteralPath $fixtureCorpusPath -Destination $corpusPath -Recurse
    $python = Get-GeneXusPythonExecutable
    Assert-True ($null -ne $python) 'a usable Python 3.8+ must be available on this host'
    if ($null -eq $python) { throw 'no Python' }

    $baseline = Copy-Scripts -Destination (Join-Path $fixtureRoot 'baseline')
    $same = Copy-Scripts -Destination (Join-Path $fixtureRoot 'same')

    # 1) Identical engines: exit 0 and a report of what was compared.
    $run = Invoke-Compare -Python $python -Baseline $baseline -Candidate $same
    Assert-True ($run.ExitCode -eq 0) "identical engines should exit 0 (got $($run.ExitCode)): $($run.Output)"
    Assert-True ($run.Output -match '(?m)^identical: .*sample-kb \((\d+) queries; rows .*objects=19, relations=29') "the report should name the corpus, the query count and the row counts: $($run.Output)"
    if ($Matches -and $Matches[1]) {
        Assert-True ([int]$Matches[1] -gt 50) "the tool should run more than 50 queries on sample-kb (got $($Matches[1]))"
    }

    # 2) One coverage entry changed: exit 1 and the differing answers named.
    $changed = Copy-Scripts -Destination (Join-Path $fixtureRoot 'changed')
    $modules = @(Get-ChildItem -LiteralPath $changed -File -Filter '*.py' | Where-Object {
        (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^UNEXTRACTED_CALL_SOURCE_TYPES = \('
    })
    Assert-True ($modules.Count -eq 1) "exactly one engine module should define UNEXTRACTED_CALL_SOURCE_TYPES (got $($modules.Count))"
    if ($modules.Count -eq 1) {
        $text = Get-Content -LiteralPath $modules[0].FullName -Raw
        # Line-ending neutral: the checkout may use LF or CRLF.
        $edited = $text -replace '(    "OfflineDatabase",\r?\n)    "Panel",\r?\n', '$1'

        Assert-True ($edited -ne $text) 'the Panel entry of UNEXTRACTED_CALL_SOURCE_TYPES should be found and removed'
        [System.IO.File]::WriteAllText($modules[0].FullName, $edited, [System.Text.UTF8Encoding]::new($false))
        $run = Invoke-Compare -Python $python -Baseline $baseline -Candidate $changed
        Assert-True ($run.ExitCode -eq 1) "a changed coverage entry should exit 1 (got $($run.ExitCode)): $($run.Output)"
        Assert-True ($run.Output -match '(?m)^DIFFERENT: .*sample-kb') "the report should mark sample-kb as DIFFERENT: $($run.Output)"
        Assert-True ($run.Output -match '(?m)^  query --query who-uses --object-type Procedure --object-name CalculateInvoiceTotal: stdout differ; line 3: baseline ''"complete": false,'', candidate ''"complete": true,''') "the report should name the who-uses answer whose coverage changed: $($run.Output)"
    }

    # 3) A folder without the engine scripts is refused.
    $empty = Join-Path $fixtureRoot 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $run = Invoke-Compare -Python $python -Baseline $baseline -Candidate $empty
    Assert-True ($run.ExitCode -eq 2) "a folder without the engine scripts should exit 2 (got $($run.ExitCode)): $($run.Output)"
    Assert-True ($run.Output -match 'candidate scripts folder has no Build-KbIntelligenceIndex.py') "the refusal should name the missing script: $($run.Output)"

    # The tool writes no bytecode into the scripts folders it runs.
    $caches = @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -Directory -Filter '__pycache__')
    Assert-True ($caches.Count -eq 0) "the tool should write no __pycache__ (found $($caches.Count))"
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS: Test-CompareKbIntelligenceBuildsSelfTest.ps1' -ForegroundColor Green
exit 0
