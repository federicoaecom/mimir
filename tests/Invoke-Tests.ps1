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
#>
[CmdletBinding()]
param(
    [string[]]$Root = @('tests'),
    [string[]]$ExcludeName = @(),
    [int]$TimeoutSeconds = 300,
    [switch]$AsJson
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
        [object]$Python
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

$results = [System.Collections.Generic.List[object]]::new()
foreach ($file in $toRun) {
    $results.Add((Invoke-OneTest -File $file -RepoRoot $RepoRoot -TimeoutSeconds $TimeoutSeconds -Python $python))
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
