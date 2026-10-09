#Requires -Version 7.0
<#
.SYNOPSIS
Self-test for tests/Invoke-Tests.ps1, the single aggregate test runner.

Builds a temp fixture directory with fake test scripts (pass, fail, a stdin
reader, and a slow test) and asserts the runner's contract: stdin is closed
for every child, a per-test timeout is enforced, cwd is the repo root, the
runner's own exit code reflects overall pass/fail, -AsJson emits a parseable
summary (with a bounded StdOut/StdErr tail for non-passing entries only),
and __pycache__ directories the runner's own run creates are
cleaned up afterwards. Python tests run on the interpreter the product's
discovery helper picks (a python3 older than 3.8 first on PATH is skipped),
and are reported as Fail when no Python is found.
#>

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptDir
$runner = Join-Path $scriptDir 'Invoke-Tests.ps1'

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
    }
}

# Returns the interpreter the product's discovery helper picks on the current PATH, or $null.
# Dot-sourced inside this function so the helper's StrictMode stays local to it.
function Get-UsablePythonForTest {
    . (Join-Path $repoRoot 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')
    return Get-GeneXusPythonExecutable
}

# New-OldPythonFake, New-PwshOnlyPathDirectory and Invoke-PwshScriptWithExactPath.
. (Join-Path $scriptDir 'fixtures/FakePythonSupport.ps1')

# The default -Root scans only tests/ (read from the runner's param block; running it with defaults would run the whole suite).
$runnerAst = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null)
$rootParam = @($runnerAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Root' })[0]
$rootDefault = if ($null -ne $rootParam -and $null -ne $rootParam.DefaultValue) { $rootParam.DefaultValue.SafeGetValue() } else { $null }
Assert-True ((@($rootDefault) -join ',') -eq 'tests') "default -Root should be 'tests' only (got '$(@($rootDefault) -join ',')')"

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mimir-invoke-tests-selftest-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

try {
    # 1) A passing self-test.
    $passPath = Join-Path $fixtureRoot 'Test-FakePassSelfTest.ps1'
    Set-Content -LiteralPath $passPath -Encoding utf8NoBOM -Value 'exit 0'

    # 2) A failing self-test.
    $failPath = Join-Path $fixtureRoot 'Test-FakeFailSelfTest.ps1'
    Set-Content -LiteralPath $failPath -Encoding utf8NoBOM -Value 'exit 1'

    # 3) A self-test that reads stdin to EOF, then exits 0. If the runner
    #    does not close the child's stdin, this hangs forever.
    $stdinPath = Join-Path $fixtureRoot 'Test-FakeStdinReaderSelfTest.ps1'
    Set-Content -LiteralPath $stdinPath -Encoding utf8NoBOM -Value @'
$null = [Console]::In.ReadToEnd()
exit 0
'@

    # 4) A self-test that reports the process cwd, so the runner's
    #    "cwd = repo root" contract is directly observable.
    $cwdMarkerPath = Join-Path $fixtureRoot 'cwd-marker.txt'
    $cwdPath = Join-Path $fixtureRoot 'Test-FakeCwdSelfTest.ps1'
    $cwdMarkerLiteral = $cwdMarkerPath.Replace("'", "''")
    Set-Content -LiteralPath $cwdPath -Encoding utf8NoBOM -Value "Set-Content -LiteralPath '$cwdMarkerLiteral' -Encoding utf8NoBOM -Value (Get-Location).Path`nexit 0"

    # 5) A self-test that sleeps far longer than the timeout under test.
    $slowSleepSeconds = 120
    $slowPath = Join-Path $fixtureRoot 'Test-FakeSlowSelfTest.ps1'
    Set-Content -LiteralPath $slowPath -Encoding utf8NoBOM -Value "Start-Sleep -Seconds $slowSleepSeconds; exit 0"

    # 6) A Python test that creates a __pycache__ byproduct, to prove cleanup.
    $pyPath = Join-Path $fixtureRoot 'Test-FakePython.py'
    Set-Content -LiteralPath $pyPath -Encoding utf8NoBOM -Value @'
import os
d = os.path.join(os.path.dirname(__file__), "__pycache__")
os.makedirs(d, exist_ok=True)
with open(os.path.join(d, "marker.txt"), "w") as f:
    f.write("x")
'@

    # 6b) A failing test with long stdout/stderr, and a passing test with output:
    #     -AsJson must keep a bounded tail for the failure only.
    $noisyFailPath = Join-Path $fixtureRoot 'Test-FakeNoisyFailSelfTest.ps1'
    Set-Content -LiteralPath $noisyFailPath -Encoding utf8NoBOM -Value @'
Write-Output ('HEADMARK' + ('x' * 9000) + 'TAILMARK-OUT')
[Console]::Error.WriteLine('ERRLINE-TAILMARK-ERR')
exit 1
'@
    $noisyPassPath = Join-Path $fixtureRoot 'Test-FakeNoisyPassSelfTest.ps1'
    Set-Content -LiteralPath $noisyPassPath -Encoding utf8NoBOM -Value @'
Write-Output 'PASSING-OUTPUT-SHOULD-NOT-BE-REPORTED'
exit 0
'@

    # 7) A passing Python test named like the old default exclusion; nothing is excluded by default, so it must run.
    $pyPath = Join-Path $fixtureRoot 'Test-KbIntelligenceQueries.py'
    Set-Content -LiteralPath $pyPath -Encoding utf8NoBOM -Value 'import sys; sys.exit(0)'

    # Every fixture starts a fresh pwsh, which takes 1 to 3 s on a hosted runner; the per-test
    # timeout leaves the normal fixtures room for that, and the slow fixture's sleep exceeds it
    # by far, so it still times out.
    $fixtureTimeoutSeconds = 10
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $jsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -Root $fixtureRoot -TimeoutSeconds $fixtureTimeoutSeconds -AsJson
    $exitCode = $LASTEXITCODE
    $sw.Stop()

    Assert-True ($exitCode -ne 0) "runner should exit non-zero when a test fails/times out (got $exitCode)"
    # A hang check, not a speed check: well under the slow fixture's sleep, with room for slow starts.
    Assert-True ($sw.Elapsed.TotalSeconds -lt 90) "runner should not wait out the ${slowSleepSeconds}s sleep; a ${fixtureTimeoutSeconds}s timeout must cut it short (took $($sw.Elapsed.TotalSeconds)s)"

    $report = $null
    try {
        $report = ($jsonRaw -join "`n") | ConvertFrom-Json
    } catch {
        $failures.Add("`-AsJson output did not parse as JSON: $($_.Exception.Message)")
    }

    if ($report) {
        $byName = @{}
        foreach ($r in $report.results) { $byName[$r.Name] = $r }

        Assert-True ($byName.ContainsKey('Test-FakePassSelfTest.ps1')) 'pass fixture should be present in results'
        if ($byName.ContainsKey('Test-FakePassSelfTest.ps1')) {
            Assert-True ($byName['Test-FakePassSelfTest.ps1'].Result -eq 'Pass') "pass fixture should report Pass (got '$($byName['Test-FakePassSelfTest.ps1'].Result)' after $($byName['Test-FakePassSelfTest.ps1'].DurationMs) ms)"
        }

        Assert-True ($byName.ContainsKey('Test-FakeFailSelfTest.ps1')) 'fail fixture should be present in results'
        if ($byName.ContainsKey('Test-FakeFailSelfTest.ps1')) {
            Assert-True ($byName['Test-FakeFailSelfTest.ps1'].Result -eq 'Fail') 'fail fixture should report Fail'
        }

        Assert-True ($byName.ContainsKey('Test-FakeStdinReaderSelfTest.ps1')) 'stdin fixture should be present in results'
        if ($byName.ContainsKey('Test-FakeStdinReaderSelfTest.ps1')) {
            Assert-True ($byName['Test-FakeStdinReaderSelfTest.ps1'].Result -eq 'Pass') "stdin-reading fixture should complete fast and Pass, proving stdin is closed for children (got '$($byName['Test-FakeStdinReaderSelfTest.ps1'].Result)' after $($byName['Test-FakeStdinReaderSelfTest.ps1'].DurationMs) ms)"
        }

        Assert-True ($byName.ContainsKey('Test-FakeSlowSelfTest.ps1')) 'slow fixture should be present in results'
        if ($byName.ContainsKey('Test-FakeSlowSelfTest.ps1')) {
            Assert-True ($byName['Test-FakeSlowSelfTest.ps1'].Result -eq 'Timeout') 'slow fixture should be marked Timeout'
            Assert-True ([long]$byName['Test-FakeSlowSelfTest.ps1'].DurationMs -lt ($slowSleepSeconds * 1000 / 2)) "slow fixture should be cut at the ${fixtureTimeoutSeconds}s timeout, far below its ${slowSleepSeconds}s sleep (took $($byName['Test-FakeSlowSelfTest.ps1'].DurationMs) ms)"
        }

        Assert-True ($byName.ContainsKey('Test-KbIntelligenceQueries.py')) 'with no -ExcludeName, the Python fixture should run (no default exclusion)'
        if ($byName.ContainsKey('Test-KbIntelligenceQueries.py')) {
            Assert-True ($byName['Test-KbIntelligenceQueries.py'].Result -eq 'Pass') 'the passing Python fixture should report Pass (the runner found a Python 3 interpreter: python3, python, or py -3)'
        }

        # -AsJson keeps a bounded output tail for non-passing entries only.
        Assert-True ($byName.ContainsKey('Test-FakeNoisyFailSelfTest.ps1')) 'noisy fail fixture should be present in results'
        if ($byName.ContainsKey('Test-FakeNoisyFailSelfTest.ps1')) {
            $noisy = $byName['Test-FakeNoisyFailSelfTest.ps1']
            Assert-True ($null -ne $noisy.StdOut -and $noisy.StdOut -match 'TAILMARK-OUT') 'failing entry should carry the tail of StdOut in -AsJson'
            Assert-True ($null -ne $noisy.StdOut -and $noisy.StdOut.Length -le 4100) "failing entry StdOut should be bounded (got $($noisy.StdOut.Length) chars)"
            Assert-True ($null -ne $noisy.StdOut -and $noisy.StdOut -notmatch 'HEADMARK') 'failing entry StdOut should keep the tail, not the head'
            Assert-True ($null -ne $noisy.StdErr -and $noisy.StdErr -match 'TAILMARK-ERR') 'failing entry should carry StdErr in -AsJson'
        }
        Assert-True ($byName.ContainsKey('Test-FakeNoisyPassSelfTest.ps1')) 'noisy pass fixture should be present in results'
        if ($byName.ContainsKey('Test-FakeNoisyPassSelfTest.ps1')) {
            $props = $byName['Test-FakeNoisyPassSelfTest.ps1'].PSObject.Properties.Name
            Assert-True ($props -notcontains 'StdOut' -and $props -notcontains 'StdErr') 'passing entry should not carry StdOut/StdErr in -AsJson'
        }
        if ($byName.ContainsKey('Test-FakeSlowSelfTest.ps1')) {
            Assert-True ($byName['Test-FakeSlowSelfTest.ps1'].PSObject.Properties.Name -contains 'StdOut') 'timed-out entry should carry StdOut in -AsJson'
        }

        Assert-True ($report.summary.excluded -eq 0) 'with no -ExcludeName, summary should count no excluded test'
        Assert-True ($report.summary.fail -ge 1) 'summary should count at least one failure'
        Assert-True ($report.summary.timeout -ge 1) 'summary should count at least one timeout'
    }

    if (Test-Path -LiteralPath $cwdMarkerPath) {
        $reportedCwd = (Get-Content -LiteralPath $cwdMarkerPath -Raw).Trim()
        $expectedCwd = (Resolve-Path -LiteralPath $repoRoot).Path.TrimEnd('\', '/')
        Assert-True ($reportedCwd.TrimEnd('\', '/') -eq $expectedCwd) "child cwd should be the repo root (expected '$expectedCwd', got '$reportedCwd')"
    } else {
        $failures.Add('cwd marker file was not written by the fixture test')
    }

    $pycachePath = Join-Path $fixtureRoot '__pycache__'
    Assert-True (-not (Test-Path -LiteralPath $pycachePath)) '__pycache__ created by the Python fixture should be cleaned up by the runner'

    # Re-run with an explicit -ExcludeName, to prove it is honored.
    $jsonRaw2 = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -Root $fixtureRoot -TimeoutSeconds $fixtureTimeoutSeconds -ExcludeName @('Test-FakeSlowSelfTest.ps1') -AsJson
    $report2 = ($jsonRaw2 -join "`n") | ConvertFrom-Json
    $byName2 = @{}
    foreach ($r in $report2.results) { $byName2[$r.Name] = $r }
    Assert-True ($byName2.ContainsKey('Test-KbIntelligenceQueries.py')) 'a name not passed in -ExcludeName should still run'
    Assert-True (-not $byName2.ContainsKey('Test-FakeSlowSelfTest.ps1')) 'a name passed in -ExcludeName should be excluded'
    Assert-True ($report2.summary.excluded -eq 1) 'summary should count the one excluded test'

    # With no Python interpreter on PATH, the runner must not crash: Python
    # tests are reported as Fail with a clear message and PowerShell tests
    # still run. The runner's PATH is exactly a new folder holding only a pwsh
    # launcher (the pwsh install folder may be a shared bin that also holds a
    # Python, and pwsh puts it in front of PATH at startup).
    $noPyRoot = Join-Path $fixtureRoot 'no-python'
    New-Item -ItemType Directory -Path $noPyRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $noPyRoot 'Test-FakePassSelfTest.ps1') -Encoding utf8NoBOM -Value 'exit 0'
    Set-Content -LiteralPath (Join-Path $noPyRoot 'Test-FakeNoPython.py') -Encoding utf8NoBOM -Value 'import sys; sys.exit(0)'
    $pwshOnlyBin = New-PwshOnlyPathDirectory -Directory (Join-Path $fixtureRoot 'pwsh-only-bin')
    $jsonRaw3 = Invoke-PwshScriptWithExactPath -PathValue $pwshOnlyBin -ScriptPath $runner -Parameters @{ Root = $noPyRoot; TimeoutSeconds = '30'; AsJson = $true }
    $exitCode3 = $LASTEXITCODE
    $report3 = $null
    try {
        $report3 = ($jsonRaw3 -join "`n") | ConvertFrom-Json
    } catch {
        $failures.Add("without Python, -AsJson output did not parse as JSON: $($_.Exception.Message)")
    }
    Assert-True ($exitCode3 -ne 0) "without Python, the runner should exit non-zero (got $exitCode3)"
    if ($report3) {
        $byName3 = @{}
        foreach ($r in $report3.results) { $byName3[$r.Name] = $r }
        Assert-True ($byName3.ContainsKey('Test-FakeNoPython.py')) 'without Python, the Python test should still be listed in results'
        if ($byName3.ContainsKey('Test-FakeNoPython.py')) {
            $noPy = $byName3['Test-FakeNoPython.py']
            Assert-True ($noPy.Result -eq 'Fail') "without Python, the Python test should report Fail (got '$($noPy.Result)')"
            Assert-True ($null -ne $noPy.StdErr -and $noPy.StdErr -match 'Python 3 interpreter not found') 'without Python, the Python test StdErr should say the interpreter was not found'
        }
        Assert-True ($byName3.ContainsKey('Test-FakePassSelfTest.ps1') -and $byName3['Test-FakePassSelfTest.ps1'].Result -eq 'Pass') 'without Python, PowerShell tests should still run and pass'
    }

    # A `python3` older than 3.8 placed ahead of a usable Python on PATH must be
    # skipped, exactly as the product's discovery helper does. The fake reports
    # 3.6 on `--version` and writes a marker file on any other call, so the
    # marker proves the runner probed or used it beyond the version check.
    $realPython = Get-UsablePythonForTest
    Assert-True ($null -ne $realPython) 'a usable Python 3.8+ must be available on this host to run the old-python3 case'
    if ($null -ne $realPython) {
        $oldPyRoot = Join-Path $fixtureRoot 'old-python'
        $oldPyBin = Join-Path $fixtureRoot 'old-python-bin'
        $oldPyMarker = Join-Path $fixtureRoot 'old-python-ran.txt'
        New-Item -ItemType Directory -Path $oldPyRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $oldPyRoot 'Test-FakeNeedsPython38.py') -Encoding utf8NoBOM -Value 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'
        New-OldPythonFake -Directory $oldPyBin -MarkerPath $oldPyMarker | Out-Null
        $pathWithOldFirst = @($oldPyBin, (Split-Path -Parent $realPython.Source), $pwshOnlyBin) -join [System.IO.Path]::PathSeparator
        $jsonRaw4 = Invoke-PwshScriptWithExactPath -PathValue $pathWithOldFirst -ScriptPath $runner -Parameters @{ Root = $oldPyRoot; TimeoutSeconds = '60'; AsJson = $true }
        $report4 = $null
        try {
            $report4 = ($jsonRaw4 -join "`n") | ConvertFrom-Json
        } catch {
            $failures.Add("with an old python3 first on PATH, -AsJson output did not parse as JSON: $($_.Exception.Message)")
        }
        if ($report4) {
            $oldPyEntry = @($report4.results | Where-Object { $_.Name -eq 'Test-FakeNeedsPython38.py' })
            Assert-True ($oldPyEntry.Count -eq 1 -and $oldPyEntry[0].Result -eq 'Pass') 'with an old python3 first on PATH, the Python test should run on a Python 3.8+ interpreter and Pass'
        }
        Assert-True (-not (Test-Path -LiteralPath $oldPyMarker)) 'the runner should not run a python3 older than 3.8 beyond its --version probe'
    }
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: Test-InvokeTestsSelfTest.ps1" -ForegroundColor Green
exit 0
