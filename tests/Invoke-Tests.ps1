#Requires -Version 7.0
<#
.SYNOPSIS
Single aggregate test runner for Mimir Lite.

.DESCRIPTION
Discovers every `*SelfTest.ps1` and Python test script (`Test*.py`) under the
given roots (default: `tests/`), and runs each one as its own child process:
  - PowerShell tests: `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <path>`
  - Python tests: `<python> <path>`, where `<python>` is the Python 3.8+
    interpreter chosen by the product's discovery helper
    (`skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1`: `python3`,
    `python`, then `py -3`). If none is found, every Python test is reported
    as `Fail` with a message saying so, and the other tests still run.
Every child has its stdin closed immediately (no test may block reading
stdin), runs with the repository root as its working directory, and is
subject to a per-test timeout (killing the whole process tree on expiry).
Any `__pycache__` directory created by a run is removed afterwards.

Exits non-zero if any test failed or timed out.

.PARAMETER Root
One or more root directories to scan (absolute, or relative to the repo
root). Defaults to `tests`.

.PARAMETER ExcludeName
Leaf file names to skip. Defaults to none.

.PARAMETER TimeoutSeconds
Per-test timeout in seconds. Default 300.

.PARAMETER AsJson
Emit a single JSON report to stdout instead of the human-readable table.
Entries that did not pass (Fail or Timeout) also carry `StdOut` and `StdErr`,
each bounded to its last 4000 characters; passing entries stay compact and
carry neither.

.PARAMETER ThrottleLimit
How many test files run at the same time. Default 1: one after another,
exactly as before. Above 1, files run with `ForEach-Object -Parallel`; each
child gets its own `TEMP`, `TMP` and `TMPDIR` under one scratch folder for
the run (in the system temporary folder, removed at the end), the files named
in `$RunAloneNames` run one at a time after the parallel batch, and results
are sorted by path, so the report has the same order and shape as with 1.
Each child of the parallel batch also gets `MIMIR_TEST_THROTTLE=<n>` (the
throttle), so a test that runs its own cases concurrently can divide its
in-file concurrency by it; it is not set with 1, nor for a run-alone child.
2 is the tested value; higher values can cause timeouts on machines short of
memory.
#>
[CmdletBinding()]
param(
    [string[]]$Root = @('tests'),
    [string[]]$ExcludeName = @(),
    [int]$TimeoutSeconds = 300,
    [switch]$AsJson,
    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 1
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path

function Resolve-RootPath {
    param([string]$Candidate)
    if ([System.IO.Path]::IsPathRooted($Candidate)) {
        return $Candidate
    }
    return (Join-Path $RepoRoot $Candidate)
}

$resolvedRoots = @()
foreach ($r in $Root) {
    $p = Resolve-RootPath $r
    if (Test-Path -LiteralPath $p) {
        $resolvedRoots += (Resolve-Path -LiteralPath $p).Path
    }
}
$resolvedRoots = $resolvedRoots | Select-Object -Unique

# Discover test files across all roots, de-duplicated by full path.
$discovered = [ordered]@{}
foreach ($rootPath in $resolvedRoots) {
    Get-ChildItem -LiteralPath $rootPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*SelfTest.ps1' -or $_.Name -like 'Test*.py' } |
        ForEach-Object { $discovered[$_.FullName] = $_ }
}

$excludedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($n in $ExcludeName) { [void]$excludedSet.Add($n) }

$toRun = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$excludedCount = 0
foreach ($file in ($discovered.Values | Sort-Object FullName)) {
    if ($excludedSet.Contains($file.Name)) {
        $excludedCount++
        continue
    }
    $toRun.Add($file)
}

# Snapshot existing __pycache__ directories under the scanned roots, so we
# only remove the ones this run creates.
$pycacheBefore = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($rootPath in $resolvedRoots) {
    Get-ChildItem -LiteralPath $rootPath -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$pycacheBefore.Add($_.FullName) }
}

# Finds a usable Python 3.8+ interpreter with the product's discovery helper
# (python3, then python, then py -3; every PATH match is probed, WindowsApps and
# empty files are rejected). Returns $null when none works. The helper is
# dot-sourced inside this function so its StrictMode stays local to it.
function Resolve-PythonInterpreter {
    . (Join-Path $PSScriptRoot '../skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')
    return Get-GeneXusPythonExecutable
}

$PythonNotFoundMessage = 'Python 3 interpreter not found: no usable Python 3.8 or later (tried python3, python, py -3); cannot run this Python test.'

function Invoke-OneTest {
    param(
        [System.IO.FileInfo]$File,
        [string]$RepoRoot,
        [int]$TimeoutSeconds,
        [object]$Python,
        # Environment variables set for this child only (the parallel mode's own TEMP folders).
        [hashtable]$Environment = $null
    )

    $isPython = $File.Extension -ieq '.py'
    if ($isPython -and $null -eq $Python) {
        return [pscustomobject]@{
            Name       = $File.Name
            Path       = $File.FullName
            Kind       = 'python'
            Result     = 'Fail'
            ExitCode   = $null
            DurationMs = 0
            StdOut     = ''
            StdErr     = $PythonNotFoundMessage
        }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.WorkingDirectory = $RepoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($null -ne $Environment) {
        foreach ($name in $Environment.Keys) { $psi.Environment[$name] = [string]$Environment[$name] }
    }

    if ($isPython) {
        $psi.FileName = $Python.Source
        foreach ($prefixArg in $Python.PrefixArguments) { $psi.ArgumentList.Add($prefixArg) }
        $psi.ArgumentList.Add($File.FullName)
    } else {
        $psi.FileName = 'pwsh'
        $psi.ArgumentList.Add('-NoProfile')
        $psi.ArgumentList.Add('-NonInteractive')
        $psi.ArgumentList.Add('-ExecutionPolicy')
        $psi.ArgumentList.Add('Bypass')
        $psi.ArgumentList.Add('-File')
        $psi.ArgumentList.Add($File.FullName)
    }

    $stdout = [System.Text.StringBuilder]::new()
    $stderr = [System.Text.StringBuilder]::new()

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $false

    $outHandler = { if ($null -ne $EventArgs.Data) { [void]$Event.MessageData.Append($EventArgs.Data).Append("`n") } }
    Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outHandler -MessageData $stdout | Out-Null
    Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $outHandler -MessageData $stderr | Out-Null

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [void]$proc.Start()
    try { $proc.StandardInput.Close() } catch { }
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
    $sw.Stop()

    $result = $null
    $exitCode = $null
    if (-not $exited) {
        try { $proc.Kill($true) } catch { }
        try { [void]$proc.WaitForExit(5000) } catch { }
        $result = 'Timeout'
        $exitCode = $null
    } else {
        $exitCode = $proc.ExitCode
        $result = if ($exitCode -eq 0) { 'Pass' } else { 'Fail' }
    }

    Get-EventSubscriber | Where-Object { $_.SourceObject -eq $proc } | Unregister-Event -Force -ErrorAction SilentlyContinue

    [pscustomobject]@{
        Name       = $File.Name
        Path       = $File.FullName
        Kind       = if ($isPython) { 'python' } else { 'pwsh' }
        Result     = $result
        ExitCode   = $exitCode
        DurationMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 0)
        StdOut     = $stdout.ToString()
        StdErr     = $stderr.ToString()
    }
}

# Bounded tail of captured output, for diagnosing non-passing entries in -AsJson.
$OutputTailChars = 4000
function Get-OutputTail {
    param([string]$Text)
    if ($Text.Length -le $OutputTailChars) { return $Text }
    return $Text.Substring($Text.Length - $OutputTailChars)
}

$python = $null
if (@($toRun | Where-Object { $_.Extension -ieq '.py' }).Count -gt 0) {
    $python = Resolve-PythonInterpreter
}

# Files that must not run beside other tests in parallel mode, by leaf name, each with its reason.
# They run one at a time after the parallel batch (with their own TEMP folders too).
$RunAloneNames = @(
    # Its fixtures assume a fresh pwsh starts well within a 10 s per-test timeout, and it starts
    # nested runner runs of its own (throttle 2 included); sibling CPU load can turn a pass into a Timeout.
    'Test-InvokeTestsSelfTest.ps1'
)

$results = [System.Collections.Generic.List[object]]::new()
if ($ThrottleLimit -le 1) {
    foreach ($file in $toRun) {
        $results.Add((Invoke-OneTest -File $file -RepoRoot $RepoRoot -TimeoutSeconds $TimeoutSeconds -Python $python))
    }
} else {
    $runAloneSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$RunAloneNames, [System.StringComparer]::OrdinalIgnoreCase)
    $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-invoke-tests-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
    try {
        # One work item per file, each with its own TEMP folder under the run's scratch folder.
        $work = for ($i = 0; $i -lt $toRun.Count; $i++) {
            $childTemp = Join-Path $scratchRoot ('{0:D4}' -f $i)
            New-Item -ItemType Directory -Path $childTemp -Force | Out-Null
            [pscustomobject]@{
                File        = $toRun[$i]
                Environment = @{ TEMP = $childTemp; TMP = $childTemp; TMPDIR = $childTemp }
            }
        }
        $parallelWork = @($work | Where-Object { -not $runAloneSet.Contains($_.File.Name) })
        $aloneWork = @($work | Where-Object { $runAloneSet.Contains($_.File.Name) })
        # The parallel batch's children learn the throttle, so a test that runs work concurrently
        # inside its own file can divide it; a run-alone child runs by itself and does not get it.
        foreach ($item in $parallelWork) { $item.Environment['MIMIR_TEST_THROTTLE'] = [string]$ThrottleLimit }

        # A parallel runspace does not see this script's functions or variables: pass the
        # function's text and the values it reads.
        $invokeOneTestText = ${function:Invoke-OneTest}.ToString()
        $collected = [System.Collections.Generic.List[object]]::new()
        if ($parallelWork.Count -gt 0) {
            $parallelResults = $parallelWork | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
                $PythonNotFoundMessage = $using:PythonNotFoundMessage
                ${function:Invoke-OneTest} = [scriptblock]::Create($using:invokeOneTestText)
                Invoke-OneTest -File $_.File -RepoRoot $using:RepoRoot -TimeoutSeconds $using:TimeoutSeconds -Python $using:python -Environment $_.Environment
            }
            foreach ($r in @($parallelResults)) { $collected.Add($r) }
        }
        foreach ($item in $aloneWork) {
            $collected.Add((Invoke-OneTest -File $item.File -RepoRoot $RepoRoot -TimeoutSeconds $TimeoutSeconds -Python $python -Environment $item.Environment))
        }
        # Same order as the sequential run, which follows the files sorted by full path.
        $orderByPath = @{}
        for ($i = 0; $i -lt $toRun.Count; $i++) { $orderByPath[$toRun[$i].FullName] = $i }
        foreach ($r in @($collected | Sort-Object { $orderByPath[$_.Path] })) { $results.Add($r) }
    } finally {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Clean up any __pycache__ directory created by this run.
foreach ($rootPath in $resolvedRoots) {
    Get-ChildItem -LiteralPath $rootPath -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue |
        Where-Object { -not $pycacheBefore.Contains($_.FullName) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

$passCount = ($results | Where-Object { $_.Result -eq 'Pass' }).Count
$failCount = ($results | Where-Object { $_.Result -eq 'Fail' }).Count
$timeoutCount = ($results | Where-Object { $_.Result -eq 'Timeout' }).Count

$summary = [pscustomobject]@{
    total    = $results.Count
    pass     = $passCount
    fail     = $failCount
    timeout  = $timeoutCount
    excluded = $excludedCount
}

if ($AsJson) {
    $report = [pscustomobject]@{
        repoRoot      = $RepoRoot
        roots         = $resolvedRoots
        timeoutSeconds = $TimeoutSeconds
        excludeName   = @($ExcludeName)
        results       = @($results | ForEach-Object {
            $entry = [ordered]@{
                Name       = $_.Name
                Path       = $_.Path
                Kind       = $_.Kind
                Result     = $_.Result
                ExitCode   = $_.ExitCode
                DurationMs = $_.DurationMs
            }
            if ($_.Result -ne 'Pass') {
                $entry.StdOut = Get-OutputTail $_.StdOut
                $entry.StdErr = Get-OutputTail $_.StdErr
            }
            [pscustomobject]$entry
        })
        summary       = $summary
    }
    $report | ConvertTo-Json -Depth 6
} else {
    Write-Host ""
    "{0,-55} {1,-8} {2,8} {3,10}" -f 'Test', 'Result', 'ExitCode', 'Duration' | Write-Host
    "-" * 85 | Write-Host
    foreach ($r in ($results | Sort-Object Name)) {
        $color = switch ($r.Result) {
            'Pass' { 'Green' }
            'Fail' { 'Red' }
            'Timeout' { 'Yellow' }
            default { 'White' }
        }
        "{0,-55} {1,-8} {2,8} {3,7} ms" -f $r.Name, $r.Result, $r.ExitCode, $r.DurationMs | Write-Host -ForegroundColor $color
        if ($r.Result -ne 'Pass' -and $r.StdErr) {
            Write-Host ("    " + ($r.StdErr.Trim() -replace "`n", "`n    ")) -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host ("Total: {0}  Pass: {1}  Fail: {2}  Timeout: {3}  Excluded: {4}" -f $summary.total, $summary.pass, $summary.fail, $summary.timeout, $summary.excluded)
}

if ($failCount -gt 0 -or $timeoutCount -gt 0) {
    exit 1
}
exit 0
