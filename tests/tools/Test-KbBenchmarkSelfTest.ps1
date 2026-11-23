#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/benchmark/New-SyntheticKbCorpus.py and tools/benchmark/Measure-KbIntelligenceBuild.py.

.DESCRIPTION
    Works in a temporary folder only and checks that:
      - the generator writes a tiny corpus and reports the relation families it generated;
      - the same seed gives byte-identical corpora;
      - the generator refuses a non-empty output folder and an output folder inside the repository;
      - the measuring tool builds the index from that corpus and reports wall-clock time, cProfile
        top functions, peak memory, index size, object/relation/evidence counts and the time of
        each fixed query;
      - the built index holds at least one relation of every family the generator reported.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$generatorPath = Join-Path $repoRoot 'tools/benchmark/New-SyntheticKbCorpus.py'
$measurePath = Join-Path $repoRoot 'tools/benchmark/Measure-KbIntelligenceBuild.py'
. (Join-Path $repoRoot 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-Python {
    param([object]$Python, [string[]]$Arguments)
    $allArguments = @($Python.PrefixArguments) + $Arguments
    $output = & $Python.Source @allArguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (@($output | ForEach-Object { "$_" }) -join "`n") }
}

function Get-TreeHash {
    param([string]$Root)
    $lines = Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
        "$relative $((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    }
    return ($lines -join "`n")
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-kb-benchmark-selftest-' + [Guid]::NewGuid().ToString('N'))
$insideRepo = Join-Path $repoRoot ('mimir-kb-benchmark-selftest-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $python = Get-GeneXusPythonExecutable
    Assert-True ($null -ne $python) 'a usable Python 3.8+ must be available on this host'
    if ($null -eq $python) { throw 'no Python' }

    $corpusA = Join-Path $fixtureRoot 'corpus-a'
    $corpusB = Join-Path $fixtureRoot 'corpus-b'
    $generatorArguments = @('--objects', '80', '--procedure-share', '0.5', '--lines-per-source', '40', '--call-density', '0.1', '--seed', '7')

    # 1) The generator writes a corpus and a JSON summary.
    $run = Invoke-Python -Python $python -Arguments (@($generatorPath, '--output-dir', $corpusA) + $generatorArguments)
    Assert-True ($run.ExitCode -eq 0) "the generator should exit 0 (got $($run.ExitCode)): $($run.Output)"
    $summary = $null
    try { $summary = $run.Output | ConvertFrom-Json } catch { $failures.Add("generator output did not parse as JSON: $($_.Exception.Message)") }
    $families = @()
    if ($summary) {
        Assert-True ($summary.objects -eq 80) "the generator should report 80 objects (got $($summary.objects))"
        Assert-True ($summary.objects_by_type.Procedure -eq 40) "half the objects should be Procedure objects (got $($summary.objects_by_type.Procedure))"
        $families = @($summary.relation_families)
        Assert-True ($families.Count -ge 8) "the generator should report at least 8 relation families (got $($families.Count))"
        $xmlCount = @(Get-ChildItem -LiteralPath $corpusA -Recurse -File -Filter '*.xml').Count
        Assert-True ($xmlCount -eq 80) "the corpus should hold 80 XML files (got $xmlCount)"
    }

    # 2) The same seed gives byte-identical corpora.
    $run = Invoke-Python -Python $python -Arguments (@($generatorPath, '--output-dir', $corpusB) + $generatorArguments)
    Assert-True ($run.ExitCode -eq 0) "the second generation should exit 0 (got $($run.ExitCode))"
    if ((Test-Path -LiteralPath $corpusA) -and (Test-Path -LiteralPath $corpusB)) {
        Assert-True ((Get-TreeHash -Root $corpusA) -eq (Get-TreeHash -Root $corpusB)) 'the same seed should give identical corpora'
    }

    # 3) A non-empty output folder and a folder inside the repository are refused.
    $run = Invoke-Python -Python $python -Arguments (@($generatorPath, '--output-dir', $corpusA) + $generatorArguments)
    Assert-True ($run.ExitCode -eq 2 -and $run.Output -match 'refused output folder that is not empty') "a non-empty output folder should be refused with exit 2 (got $($run.ExitCode)): $($run.Output)"
    $run = Invoke-Python -Python $python -Arguments (@($generatorPath, '--output-dir', $insideRepo) + $generatorArguments)
    Assert-True ($run.ExitCode -eq 2 -and $run.Output -match 'refused output folder inside the repository') "an output folder inside the repository should be refused with exit 2 (got $($run.ExitCode)): $($run.Output)"
    Assert-True (-not (Test-Path -LiteralPath $insideRepo)) 'nothing should be written inside the repository'

    # 4) The measuring tool builds the index and reports every expected field.
    $measureDir = Join-Path $fixtureRoot 'measure'
    $run = Invoke-Python -Python $python -Arguments @($measurePath, '--corpus-root', $corpusA, '--output-dir', $measureDir, '--query-repeats', '1', '--json')
    Assert-True ($run.ExitCode -eq 0) "the measuring tool should exit 0 (got $($run.ExitCode)): $($run.Output)"
    $report = $null
    try { $report = $run.Output | ConvertFrom-Json } catch { $failures.Add("measure output did not parse as JSON: $($_.Exception.Message)") }
    if ($report) {
        Assert-True ($report.build.wall_clock_seconds -gt 0) 'the report should carry the build wall-clock time'
        Assert-True (@($report.profile.top_cumulative).Count -ge 5) 'the report should list the top cumulative functions'
        Assert-True (@($report.profile.top_tottime).Count -ge 5) 'the report should list the top functions by own time'
        Assert-True ($null -ne $report.profile.top_cumulative[0].function) 'a profile row should name its function'
        Assert-True ($report.memory.tracemalloc_peak_mb -gt 0) 'the report should carry the tracemalloc peak'
        Assert-True ($report.memory.PSObject.Properties.Name -contains 'peak_rss_mb') 'the report should carry the peak RSS field'
        Assert-True ($report.memory.PSObject.Properties.Name -contains 'peak_rss_source') 'the report should say where the peak RSS came from'
        Assert-True ($report.index.size_bytes -gt 0) 'the report should carry the index size'
        # Compare by file, not by path text: Python's resolve() and Resolve-Path normalize short names and links differently.
        Assert-True (Test-Path -LiteralPath (Join-Path $measureDir (Split-Path -Leaf $report.index.path)) -PathType Leaf) 'the index should be written in the output folder'
        Assert-True ($report.counts.objects -eq 80) "the index should hold 80 objects (got $($report.counts.objects))"
        Assert-True ($report.counts.relations -gt 0) 'the index should hold relations'
        Assert-True ($report.counts.evidence -gt 0) 'the index should hold evidence rows'
        Assert-True ($report.corpus.size_bytes -gt 0) 'the report should carry the corpus size'
        $queryNames = @($report.queries | ForEach-Object { $_.query })
        foreach ($expected in @('who-uses', 'impact-basic', 'functional-trace-basic', 'list-by-type', 'search-objects')) {
            Assert-True ($queryNames -contains $expected) "the report should time the $expected query"
        }
        foreach ($query in @($report.queries)) {
            Assert-True ($query.median_ms -ge 0 -and $query.ok -eq $true) "query $($query.query) should run and report its time"
        }
        foreach ($family in $families) {
            $count = 0
            $property = $report.counts.relations_by_kind.PSObject.Properties[$family]
            if ($property) { $count = [int]$property.Value }
            Assert-True ($count -gt 0) "the build should extract at least one $family relation from the corpus (got $count)"
        }
    }
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $insideRepo -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS: Test-KbBenchmarkSelfTest.ps1' -ForegroundColor Green
exit 0
