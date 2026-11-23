#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/docker/Python38Smoke.py, the smoke run behind
    tools/Invoke-Python38SmokeInDocker.ps1.

.DESCRIPTION
    Runs the smoke script on the host's Python 3.8+ (no Docker needed) and checks that:
      - against the repository and its synthetic fixture, every step passes, it exits 0, and it
        reports the build, the queries, and the Python unit test files;
      - with a corpus folder that does not exist, the build fails, the queries are reported as
        skipped, and it exits 1;
      - a corpus with no Transaction reports the Transaction query as skipped, not failed;
      - a unit test file that hangs is stopped by the step timeout and reported as failed;
      - no run writes __pycache__ into the repository's scripts folder.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$smokePath = Join-Path $repoRoot 'tools/docker/Python38Smoke.py'
. (Join-Path $repoRoot 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-Smoke {
    param([string[]]$Arguments)
    $prefix = [string[]]$python.PrefixArguments
    $output = & $python.Source @prefix -B $smokePath @Arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($output | ForEach-Object { $_.ToString() }) -join "`n") }
}

$python = Get-GeneXusPythonExecutable
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-py38-smoke-selftest-' + [Guid]::NewGuid().ToString('N'))
$pycacheDir = Join-Path $repoRoot 'skills/mimir-lite/scripts/__pycache__'
$pycacheBefore = @(if (Test-Path -LiteralPath $pycacheDir) { Get-ChildItem -LiteralPath $pycacheDir -File | ForEach-Object { "$($_.Name)|$($_.LastWriteTimeUtc.Ticks)" } })

try {
    Assert-True ($null -ne $python) 'a usable Python 3.8+ must be available on this host'
    if ($null -ne $python) {
        # 1) The real repository passes every step.
        $run = Invoke-Smoke -Arguments @('--repo-root', $repoRoot)
        Assert-True ($run.ExitCode -eq 0) "the smoke run should pass on the repository (exit $($run.ExitCode)): $($run.Text)"
        Assert-True ($run.Text -match '(?m)^Python 3\.\d+') 'the smoke run should print the Python version first'
        Assert-True ($run.Text -match '(?m)^PASS build$') 'the build step should pass'
        foreach ($query in 'index-metadata', 'list-by-type', 'who-uses', 'impact-basic', 'functional-trace-basic', 'transaction-writable-attributes') {
            Assert-True ($run.Text -match "(?m)^PASS query $query$") "the $query query should pass"
        }
        Assert-True ($run.Text -match '(?m)^PASS unittest tests/mimir-lite/TestBuildKbIntelligenceIndexAtomicWrite\.py$') 'the Python unit test files should run'
        Assert-True ($run.Text -match '(?m)^STEPS FAILED=0$') 'the summary should report no failed step'

        # 2) A missing corpus fails the build and skips the queries.
        New-Item -ItemType Directory -Path $scratch -Force | Out-Null
        $run = Invoke-Smoke -Arguments @('--repo-root', $repoRoot, '--source-root', (Join-Path $scratch 'no-such-corpus'))
        Assert-True ($run.ExitCode -eq 1) "a missing corpus should exit 1 (got $($run.ExitCode))"
        Assert-True ($run.Text -match '(?m)^FAIL build') 'a missing corpus should fail the build step'
        Assert-True ($run.Text -match '(?m)^FAIL queries: skipped') 'a missing corpus should report the queries as skipped'

        # 3) A corpus without Transaction objects skips the Transaction query.
        $noTrnCorpus = Join-Path $scratch 'no-transaction-corpus'
        Copy-Item -LiteralPath (Join-Path $repoRoot 'tests/fixtures/sample-kb') -Destination $noTrnCorpus -Recurse
        Remove-Item -LiteralPath (Join-Path $noTrnCorpus 'Transaction') -Recurse -Force
        $emptyTests = Join-Path $scratch 'empty-tests'
        New-Item -ItemType Directory -Path $emptyTests -Force | Out-Null
        $run = Invoke-Smoke -Arguments @('--repo-root', $repoRoot, '--source-root', $noTrnCorpus, '--tests-root', $emptyTests)
        Assert-True ($run.Text -match '(?m)^SKIP query transaction-writable-attributes') 'without Transaction objects, the Transaction query should be reported as skipped'
        Assert-True ($run.Text -notmatch '(?m)^FAIL query transaction-writable-attributes') 'without Transaction objects, the Transaction query should not be reported as failed'

        # 4) A hanging unit test file is stopped by the step timeout.
        $hangTests = Join-Path $scratch 'hang-tests'
        New-Item -ItemType Directory -Path $hangTests -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $hangTests 'TestHang.py') -Encoding utf8NoBOM -Value "import time`ntime.sleep(60)`n"
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $run = Invoke-Smoke -Arguments @('--repo-root', $repoRoot, '--tests-root', $hangTests, '--step-timeout', '3')
        $watch.Stop()
        Assert-True ($run.ExitCode -eq 1) "a hanging test file should make the smoke run exit 1 (got $($run.ExitCode))"
        Assert-True ($run.Text -match '(?m)^FAIL unittest .*TestHang\.py \(timed out after 3 s\)') 'a hanging test file should be reported as timed out'
        Assert-True ($watch.Elapsed.TotalSeconds -lt 50) "the step timeout should stop the hanging file (took $([int]$watch.Elapsed.TotalSeconds) s)"
    }

    # 5) No bytecode written into the repository.
    $pycacheAfter = @(if (Test-Path -LiteralPath $pycacheDir) { Get-ChildItem -LiteralPath $pycacheDir -File | ForEach-Object { "$($_.Name)|$($_.LastWriteTimeUtc.Ticks)" } })
    Assert-True (($pycacheAfter -join ';') -eq ($pycacheBefore -join ';')) 'the smoke run should not write bytecode into skills/mimir-lite/scripts/__pycache__'
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS: Test-Python38SmokeSelfTest.ps1' -ForegroundColor Green
exit 0
