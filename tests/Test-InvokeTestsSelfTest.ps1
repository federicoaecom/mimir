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
and are reported as Fail when no Python is found. With -ThrottleLimit 2,
every result is present in the same order and JSON shape as with 1, a
timeout still kills the test's process tree, and each child gets its own
TEMP, TMP and TMPDIR under a per-run scratch folder removed at the end; every
child of the parallel batch sees MIMIR_TEST_THROTTLE=2 (no throttle-1 child
sees it), and a file named in the runner's run-alone list runs by itself after
the batch, with its own TEMP, and is reported in its sorted position.
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

    # -ThrottleLimit: the same synthetic root run with a throttle of 1 and of 2. With 2, every
    # result is present, the order matches the throttle-1 run (sorted by path), the JSON shape is
    # the same, a timeout still kills the child's whole process tree, and each child gets its own
    # TEMP, TMP and TMPDIR under a per-run scratch folder that is removed at the end. With 1, the
    # children inherit the runner's TEMP unchanged.
    $parRoot = Join-Path $fixtureRoot 'parallel'
    $parMarkers = Join-Path $fixtureRoot 'parallel-markers'
    New-Item -ItemType Directory -Path $parRoot, $parMarkers -Force | Out-Null
    # The nested runs below must not inherit a throttle from an outer run of this file.
    Remove-Item Env:\MIMIR_TEST_THROTTLE -ErrorAction SilentlyContinue
    $treePidMarker = Join-Path $parMarkers 'tree-grandchild.pid'
    $treePidLiteral = $treePidMarker.Replace("'", "''")
    # Each marker fixture writes '<name>.txt' (TEMP|TMP|TMPDIR) and '<name>.info.txt'
    # (start ticks|end ticks|MIMIR_TEST_THROTTLE|whether the process-tree fixture had started).
    function New-ParMarkerFixture {
        param([string]$Name)
        $markerLiteral = (Join-Path $parMarkers ($Name + '.txt')).Replace("'", "''")
        $infoLiteral = (Join-Path $parMarkers ($Name + '.info.txt')).Replace("'", "''")
        Set-Content -LiteralPath (Join-Path $parRoot $Name) -Encoding utf8NoBOM -Value @"
`$start = [DateTime]::UtcNow.Ticks
`$treeStarted = Test-Path -LiteralPath '$treePidLiteral'
Set-Content -LiteralPath '$markerLiteral' -Encoding utf8NoBOM -Value (@(`$env:TEMP, `$env:TMP, `$env:TMPDIR) -join '|')
Set-Content -LiteralPath '$infoLiteral' -Encoding utf8NoBOM -Value (@(`$start, [DateTime]::UtcNow.Ticks, [string]`$env:MIMIR_TEST_THROTTLE, `$treeStarted) -join '|')
exit 0
"@
    }
    $tempFixtureNames = @('Test-ParTempASelfTest.ps1', 'Test-ParTempBSelfTest.ps1', 'Test-ParTempCSelfTest.ps1')
    foreach ($name in $tempFixtureNames) { New-ParMarkerFixture -Name $name }
    # A fixture named in the runner's run-alone list ($RunAloneNames): at throttle 2 it must run
    # by itself after the parallel batch, with its own TEMP, and still be reported in path order
    # (its name sorts first in this root).
    $aloneFixtureName = 'Test-InvokeTestsSelfTest.ps1'
    $runAloneAssignment = $runnerAst.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$RunAloneNames' }, $true)
    Assert-True ($null -ne $runAloneAssignment -and $runAloneAssignment.Right.Extent.Text -match [regex]::Escape("'$aloneFixtureName'")) "the runner's `$RunAloneNames should list '$aloneFixtureName' (the run-alone fixture's name)"
    New-ParMarkerFixture -Name $aloneFixtureName
    $markerFixtureNames = @($tempFixtureNames + $aloneFixtureName)
    Set-Content -LiteralPath (Join-Path $parRoot 'Test-ParNoisyFailSelfTest.ps1') -Encoding utf8NoBOM -Value @'
Write-Output 'PARALLEL-TAILMARK-OUT'
[Console]::Error.WriteLine('PARALLEL-TAILMARK-ERR')
exit 1
'@
    Set-Content -LiteralPath (Join-Path $parRoot 'Test-ParPython.py') -Encoding utf8NoBOM -Value 'import sys; sys.exit(0)'
    # A timed-out test whose own child (a grandchild of the runner) must die with it.
    Set-Content -LiteralPath (Join-Path $parRoot 'Test-ParTreeSelfTest.ps1') -Encoding utf8NoBOM -Value @"
`$grandchild = Start-Process -FilePath (Get-Process -Id `$PID).Path -ArgumentList '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds $slowSleepSeconds' -NoNewWindow -PassThru
Set-Content -LiteralPath '$treePidLiteral' -Encoding utf8NoBOM -Value `$grandchild.Id
Start-Sleep -Seconds $slowSleepSeconds
exit 0
"@

    function Get-ParallelRun {
        param([int]$Throttle)
        Get-ChildItem -LiteralPath $parMarkers -File | Remove-Item -Force
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $raw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -Root $parRoot -TimeoutSeconds $fixtureTimeoutSeconds -ThrottleLimit $Throttle -AsJson
        $code = $LASTEXITCODE
        $watch.Stop()
        $parsed = $null
        try { $parsed = ($raw -join "`n") | ConvertFrom-Json } catch { $failures.Add("throttle ${Throttle}: -AsJson output did not parse as JSON: $($_.Exception.Message)") }
        $temps = @{}
        $infos = @{}
        foreach ($name in $markerFixtureNames) {
            $marker = Join-Path $parMarkers ($name + '.txt')
            if (Test-Path -LiteralPath $marker) { $temps[$name] = (Get-Content -LiteralPath $marker -Raw).Trim() }
            $info = Join-Path $parMarkers ($name + '.info.txt')
            if (Test-Path -LiteralPath $info) {
                $fields = @((Get-Content -LiteralPath $info -Raw).Trim() -split '\|')
                $infos[$name] = [pscustomobject]@{ Start = [long]$fields[0]; End = [long]$fields[1]; Throttle = [string]$fields[2]; TreeStarted = ($fields[3] -eq 'True') }
            }
        }
        $grandchildPid = if (Test-Path -LiteralPath $treePidMarker) { [int](Get-Content -LiteralPath $treePidMarker -Raw).Trim() } else { $null }
        return [pscustomobject]@{ ExitCode = $code; Seconds = $watch.Elapsed.TotalSeconds; Report = $parsed; Temps = $temps; Infos = $infos; GrandchildPid = $grandchildPid }
    }

    # True when the process is gone within a few seconds (a kill may take a moment to land).
    function Test-ProcessGone {
        param([int]$ProcessId)
        for ($i = 0; $i -lt 20; $i++) {
            if ($null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $true }
            Start-Sleep -Milliseconds 250
        }
        return $false
    }

    $seq = Get-ParallelRun -Throttle 1
    $par = Get-ParallelRun -Throttle 2

    $expectedNames = @($markerFixtureNames + 'Test-ParNoisyFailSelfTest.ps1', 'Test-ParPython.py', 'Test-ParTreeSelfTest.ps1')
    foreach ($run in @(@{ Label = 'throttle 1'; Run = $seq }, @{ Label = 'throttle 2'; Run = $par })) {
        $label = $run.Label
        $r = $run.Run
        Assert-True ($r.ExitCode -eq 1) "${label}: the runner should exit 1 when a test fails or times out (got $($r.ExitCode))"
        Assert-True ($r.Seconds -lt 90) "${label}: the runner should not wait out the ${slowSleepSeconds}s sleep (took $($r.Seconds)s)"
        if ($null -ne $r.GrandchildPid) {
            Assert-True (Test-ProcessGone -ProcessId $r.GrandchildPid) "${label}: a timeout should kill the timed-out test's whole process tree (grandchild $($r.GrandchildPid) is still running)"
        } else {
            $failures.Add("${label}: the process-tree fixture did not record its grandchild PID")
        }
        if ($null -eq $r.Report) { $failures.Add("${label}: the runner produced no -AsJson report"); continue }
        $names = @($r.Report.results | ForEach-Object { $_.Name })
        foreach ($n in $expectedNames) {
            Assert-True ($names -contains $n) "${label}: '$n' should be present in results"
        }
        Assert-True ($names.Count -eq $expectedNames.Count) "${label}: results should hold exactly $($expectedNames.Count) entries (got $($names.Count))"
        $byNameP = @{}
        foreach ($e in $r.Report.results) { $byNameP[$e.Name] = $e }
        if ($byNameP.ContainsKey('Test-ParTreeSelfTest.ps1')) { Assert-True ($byNameP['Test-ParTreeSelfTest.ps1'].Result -eq 'Timeout') "${label}: the process-tree fixture should be marked Timeout" }
        if ($byNameP.ContainsKey('Test-ParNoisyFailSelfTest.ps1')) {
            $nf = $byNameP['Test-ParNoisyFailSelfTest.ps1']
            Assert-True ($nf.Result -eq 'Fail') "${label}: the noisy fail fixture should report Fail"
            Assert-True ([string]$nf.StdOut -match 'PARALLEL-TAILMARK-OUT' -and [string]$nf.StdErr -match 'PARALLEL-TAILMARK-ERR') "${label}: a failing entry should carry its captured StdOut and StdErr"
        }
        foreach ($n in @($markerFixtureNames + 'Test-ParPython.py')) {
            if ($byNameP.ContainsKey($n)) { Assert-True ($byNameP[$n].Result -eq 'Pass') "${label}: '$n' should Pass (got '$($byNameP[$n].Result)')" }
        }
        Assert-True ($r.Report.summary.total -eq 7 -and $r.Report.summary.pass -eq 5 -and $r.Report.summary.fail -eq 1 -and $r.Report.summary.timeout -eq 1) "${label}: summary should be total 7, pass 5, fail 1, timeout 1"
        Assert-True (@($r.Report.results)[0].Name -eq $aloneFixtureName) "${label}: the run-alone fixture should be reported in its sorted position, first (got '$(@($r.Report.results)[0].Name)')"
    }

    # MIMIR_TEST_THROTTLE: every child of the throttle-2 parallel batch sees 2; no throttle-1
    # child sees it, and neither does the run-alone child (it runs by itself).
    foreach ($name in $markerFixtureNames) {
        Assert-True ($seq.Infos.ContainsKey($name) -and $seq.Infos[$name].Throttle -eq '') "throttle 1: '$name' should not see MIMIR_TEST_THROTTLE (got '$(if ($seq.Infos.ContainsKey($name)) { $seq.Infos[$name].Throttle } else { '<no marker>' })')"
    }
    foreach ($name in $tempFixtureNames) {
        Assert-True ($par.Infos.ContainsKey($name) -and $par.Infos[$name].Throttle -eq '2') "throttle 2: '$name' should see MIMIR_TEST_THROTTLE=2 (got '$(if ($par.Infos.ContainsKey($name)) { $par.Infos[$name].Throttle } else { '<no marker>' })')"
    }
    # The run-alone child does not overlap the parallel batch: it starts after every batch
    # fixture ended and after the process-tree fixture started.
    if ($par.Infos.ContainsKey($aloneFixtureName)) {
        $alone = $par.Infos[$aloneFixtureName]
        Assert-True ($alone.Throttle -eq '') "throttle 2: the run-alone child should not see MIMIR_TEST_THROTTLE (got '$($alone.Throttle)')"
        Assert-True $alone.TreeStarted 'throttle 2: the run-alone child should start after the process-tree fixture of the parallel batch started'
        foreach ($name in $tempFixtureNames) {
            if ($par.Infos.ContainsKey($name)) {
                Assert-True ($alone.Start -ge $par.Infos[$name].End) "throttle 2: the run-alone child should start after '$name' ended (alone start $($alone.Start), '$name' end $($par.Infos[$name].End))"
            }
        }
    } else {
        $failures.Add("throttle 2: the run-alone fixture did not record its start and end")
    }

    if ($seq.Report -and $par.Report) {
        $seqPaths = @($seq.Report.results | ForEach-Object { $_.Path })
        $parPaths = @($par.Report.results | ForEach-Object { $_.Path })
        Assert-True (($parPaths -join '|') -eq ($seqPaths -join '|')) "throttle 2: result order should match the throttle-1 order (sorted by path); got '$($parPaths -join ', ')'"
        Assert-True ((@($par.Report.PSObject.Properties.Name) -join ',') -eq (@($seq.Report.PSObject.Properties.Name) -join ',')) "throttle 2: the report's top-level fields should match throttle 1 (got '$(@($par.Report.PSObject.Properties.Name) -join ',')')"
        Assert-True ((@($par.Report.summary.PSObject.Properties.Name) -join ',') -eq (@($seq.Report.summary.PSObject.Properties.Name) -join ',')) 'throttle 2: the summary fields should match throttle 1'
        for ($i = 0; $i -lt [math]::Min($seqPaths.Count, $parPaths.Count); $i++) {
            $seqFields = @($seq.Report.results[$i].PSObject.Properties.Name) -join ','
            $parFields = @($par.Report.results[$i].PSObject.Properties.Name) -join ','
            Assert-True ($parFields -eq $seqFields) "throttle 2: entry '$($par.Report.results[$i].Name)' fields should match throttle 1 ('$seqFields', got '$parFields')"
        }
    }

    # Throttle 1 leaves the children's TEMP as the runner's own.
    foreach ($name in $markerFixtureNames) {
        $expectedInherited = @($env:TEMP, $env:TMP, $env:TMPDIR) -join '|'
        Assert-True ($seq.Temps[$name] -eq $expectedInherited) "throttle 1: '$name' should inherit the runner's TEMP/TMP/TMPDIR unchanged (expected '$expectedInherited', got '$($seq.Temps[$name])')"
    }
    # Throttle 2 gives every child its own TEMP, TMP and TMPDIR, outside the repository, removed afterwards.
    $childTemps = @()
    $repoRootFull = (Resolve-Path -LiteralPath $repoRoot).Path.TrimEnd('\', '/')
    foreach ($name in $markerFixtureNames) {
        $value = [string]$par.Temps[$name]
        $parts = @($value -split '\|')
        Assert-True ($parts.Count -eq 3 -and $parts[0] -ne '' -and $parts[0] -eq $parts[1] -and $parts[1] -eq $parts[2]) "throttle 2: '$name' should see TEMP, TMP and TMPDIR set to one folder (got '$value')"
        if ($parts.Count -ge 1 -and $parts[0] -ne '') {
            $childTemps += $parts[0]
            Assert-True ($parts[0] -ne $env:TEMP) "throttle 2: '$name' should not inherit the runner's TEMP"
            Assert-True (-not $parts[0].StartsWith($repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)) "throttle 2: '$name' TEMP should be outside the repository (got '$($parts[0])')"
            Assert-True (-not (Test-Path -LiteralPath $parts[0])) "throttle 2: '$name' TEMP folder should be removed at the end of the run ($($parts[0]))"
        }
    }
    Assert-True (@($childTemps | Select-Object -Unique).Count -eq $markerFixtureNames.Count) "throttle 2: each child should get its own TEMP (got '$($childTemps -join ', ')')"
    if ($childTemps.Count -ge 2) {
        $scratchParents = @($childTemps | ForEach-Object { Split-Path -Parent $_ } | Select-Object -Unique)
        Assert-True ($scratchParents.Count -eq 1) "throttle 2: the children's TEMP folders should share one per-run scratch folder (got '$($scratchParents -join ', ')')"
        if ($scratchParents.Count -eq 1) { Assert-True (-not (Test-Path -LiteralPath $scratchParents[0])) "throttle 2: the per-run scratch folder should be removed at the end ($($scratchParents[0]))" }
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
