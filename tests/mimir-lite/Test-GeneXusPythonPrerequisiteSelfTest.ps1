#requires -Version 7.4

<#
.SYNOPSIS
    Deterministic self-test for GeneXusPythonPrerequisite.ps1 and the wrappers that use it.

.DESCRIPTION
    Puts fake `python3`, `python`, and `py` commands on a temporary PATH (`.cmd` files on
    Windows, executable shell scripts elsewhere), followed only by the pwsh install folder, so
    no real interpreter is visible. Checks that discovery:
      - tries `python3`, then `python`, then `py -3`;
      - runs each candidate and skips one that fails (the Windows Store `python3` stub exits 9009);
      - requires Python 3.8 or later;
      - rejects an interpreter under a `WindowsApps` folder;
      - returns $null when nothing usable is found;
      - returns the `-3` prefix for `py`, and the KbIntelligence wrappers pass it on.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$helperPath = Join-Path $scriptsRoot 'GeneXusPythonPrerequisite.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "BLOCK: target script not found: $helperPath"
}
. $helperPath

$failures = 0
$cases = 0
$pwshPath = (Get-Process -Id $PID).Path

function Assert-Equal {
    param([string]$CaseName, [AllowNull()][string]$Expected, [AllowNull()][string]$Actual)
    $script:cases++
    if ($Actual -eq $Expected) {
        Write-Output ("PASS: {0} -> {1}" -f $CaseName, $Expected)
    }
    else {
        $script:failures++
        Write-Output ("FAIL: {0} -> expected '{1}', got '{2}'" -f $CaseName, $Expected, $Actual)
    }
}

function Assert-Match {
    param([string]$CaseName, [string]$Pattern, [AllowNull()][string]$Actual)
    $script:cases++
    if ($Actual -match $Pattern) {
        Write-Output ("PASS: {0}" -f $CaseName)
    }
    else {
        $script:failures++
        Write-Output ("FAIL: {0} -> '{1}' does not match '{2}'" -f $CaseName, $Actual, $Pattern)
    }
}

# Writes a fake interpreter. -VersionLine is what `--version` prints; -ExitCode is the exit
# code of every call (9009 mimics the Windows Store stub). -PyLauncher makes it answer like
# `py`: `-3 --version` prints -VersionLine, a bare `--version` prints Python 2, and any other
# call echoes its arguments as `FAKE-PY-ARGS: <args>` so a test can see what was passed.
function New-FakeInterpreter {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$VersionLine = 'Python 3.11.4',
        [int]$ExitCode = 0,
        [switch]$PyLauncher
    )
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    if ($IsWindows) {
        $path = Join-Path $Directory ($Name + '.cmd')
        if ($PyLauncher) {
            $lines = @(
                '@echo off'
                ('if "%~1"=="-3" if "%~2"=="--version" (echo {0}& exit /b {1})' -f $VersionLine, $ExitCode)
                ('if "%~1"=="--version" (echo Python 2.7.18& exit /b {0})' -f $ExitCode)
                'echo FAKE-PY-ARGS: %*'
                ('exit /b {0}' -f $ExitCode)
            )
        }
        else {
            $lines = @(
                '@echo off'
                ('echo {0}' -f $VersionLine)
                ('exit /b {0}' -f $ExitCode)
            )
        }
        [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))
    }
    else {
        $path = Join-Path $Directory $Name
        if ($PyLauncher) {
            $lines = @(
                '#!/bin/sh'
                ('if [ "$1" = "-3" ] && [ "$2" = "--version" ]; then echo "{0}"; exit {1}; fi' -f $VersionLine, $ExitCode)
                ('if [ "$1" = "--version" ]; then echo "Python 2.7.18"; exit {0}; fi' -f $ExitCode)
                'echo "FAKE-PY-ARGS: $*"'
                ('exit {0}' -f $ExitCode)
            )
        }
        else {
            $lines = @(
                '#!/bin/sh'
                ('echo "{0}"' -f $VersionLine)
                ('exit {0}' -f $ExitCode)
            )
        }
        [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
    }
    return $path
}

function Get-FoundValue {
    # Reads one property of a discovery result as a string; 'null' when nothing was found and
    # '<missing>' when the property does not exist (so a missing field fails, not throws).
    param([AllowNull()]$Found, [string]$Name)
    if ($null -eq $Found) { return 'null' }
    $property = $Found.PSObject.Properties[$Name]
    if ($null -eq $property) { return '<missing>' }
    return (@($property.Value) -join ' ')
}

function New-CaseDir {
    $path = Join-Path $script:tempRoot ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Use-OnlyPath {
    param([string[]]$Directories)
    $env:PATH = (@($Directories) + @($PSHOME)) -join [System.IO.Path]::PathSeparator
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-pyprereq-selftest-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$originalPath = $env:PATH

try {
    # 1. A failing python3 (Store stub, exit 9009) is skipped; python is used.
    $dir = New-CaseDir
    New-FakeInterpreter -Directory $dir -Name 'python3' -VersionLine 'Python was not found; run without arguments to install from the Microsoft Store' -ExitCode 9009 | Out-Null
    $expectedPython = New-FakeInterpreter -Directory $dir -Name 'python' -VersionLine 'Python 3.11.4'
    Use-OnlyPath -Directories @($dir)
    $found = Get-GeneXusPythonExecutable
    Assert-Equal 'stub python3 skipped: python used' $expectedPython (Get-FoundValue -Found $found -Name 'Source')
    Assert-Equal 'stub python3 skipped: no prefix arguments' '' (Get-FoundValue -Found $found -Name 'PrefixArguments')
    Assert-Match 'stub python3 skipped: version line reported' '3\.11\.4' (Get-FoundValue -Found $found -Name 'VersionLine')

    # 2. python3 comes before python.
    $dir = New-CaseDir
    $expectedPython3 = New-FakeInterpreter -Directory $dir -Name 'python3' -VersionLine 'Python 3.12.1'
    New-FakeInterpreter -Directory $dir -Name 'python' -VersionLine 'Python 3.11.4' | Out-Null
    Use-OnlyPath -Directories @($dir)
    $found = Get-GeneXusPythonExecutable
    Assert-Equal 'order: python3 preferred over python' $expectedPython3 (Get-FoundValue -Found $found -Name 'Source')
    Assert-Equal 'order: launcher name is python3' 'python3' (Get-FoundValue -Found $found -Name 'Launcher')

    # 3. Too-old interpreters are skipped; py -3 is the last resort and carries its prefix.
    $dir = New-CaseDir
    New-FakeInterpreter -Directory $dir -Name 'python3' -VersionLine 'Python 3.7.9' | Out-Null
    New-FakeInterpreter -Directory $dir -Name 'python' -VersionLine 'Python 2.7.18' | Out-Null
    $expectedPy = New-FakeInterpreter -Directory $dir -Name 'py' -VersionLine 'Python 3.9.13' -PyLauncher
    Use-OnlyPath -Directories @($dir)
    $found = Get-GeneXusPythonExecutable
    Assert-Equal 'py -3: chosen after too-old python3 and python 2' $expectedPy (Get-FoundValue -Found $found -Name 'Source')
    Assert-Equal 'py -3: prefix arguments' '-3' (Get-FoundValue -Found $found -Name 'PrefixArguments')
    Assert-Equal 'py -3: launcher name' 'py' (Get-FoundValue -Found $found -Name 'Launcher')

    # 4. Python 3.8.0 is the minimum accepted version.
    $dir = New-CaseDir
    $expectedMin = New-FakeInterpreter -Directory $dir -Name 'python3' -VersionLine 'Python 3.8.0'
    Use-OnlyPath -Directories @($dir)
    $found = Get-GeneXusPythonExecutable
    Assert-Equal 'minimum: Python 3.8.0 accepted' $expectedMin (Get-FoundValue -Found $found -Name 'Source')

    # 5. An interpreter under a WindowsApps folder is rejected even when it answers.
    $dir = Join-Path (New-CaseDir) 'WindowsApps'
    New-FakeInterpreter -Directory $dir -Name 'python3' -VersionLine 'Python 3.11.4' | Out-Null
    Use-OnlyPath -Directories @($dir)
    $found = Get-GeneXusPythonExecutable
    Assert-Equal 'WindowsApps interpreter rejected' 'null' (Get-FoundValue -Found $found -Name 'Source')

    # 6. Nothing usable on PATH -> $null, and the prerequisite message keeps its contract token.
    $dir = New-CaseDir
    New-FakeInterpreter -Directory $dir -Name 'python3' -VersionLine 'Python was not found' -ExitCode 9009 | Out-Null
    New-FakeInterpreter -Directory $dir -Name 'python' -VersionLine 'Python 2.7.18' | Out-Null
    Use-OnlyPath -Directories @($dir)
    $found = Get-GeneXusPythonExecutable
    Assert-Equal 'no usable Python -> null' 'null' (Get-FoundValue -Found $found -Name 'Source')
    Use-OnlyPath -Directories @()
    $found = Get-GeneXusPythonExecutable
    Assert-Equal 'empty PATH (pwsh only) -> null' 'null' (Get-FoundValue -Found $found -Name 'Source')
    Assert-Match 'prerequisite message keeps the contract token' '^PREREQUISITE MISSING:' (Get-GeneXusPythonPrerequisiteErrorMessage)

    # 7. The KbIntelligence wrappers resolve Python through the helper and pass `-3` to py.
    $dir = New-CaseDir
    New-FakeInterpreter -Directory $dir -Name 'py' -VersionLine 'Python 3.9.13' -PyLauncher | Out-Null
    $wrapperWork = New-CaseDir
    $sqlitePath = Join-Path $wrapperWork 'index.sqlite'
    $casesPath = Join-Path $wrapperWork 'cases.json'
    Use-OnlyPath -Directories @($dir)
    $wrapperRuns = @(
        @{ Name = 'Build-KbIntelligenceIndex.ps1'; Engine = 'Build-KbIntelligenceIndex.py'; Arguments = @('-SourceRoot', $wrapperWork, '-OutputPath', $sqlitePath) }
        @{ Name = 'Query-KbIntelligenceIndex.ps1'; Engine = 'Query-KbIntelligenceIndex.py'; Arguments = @('-IndexPath', $sqlitePath, '-Query', 'index-metadata') }
        @{ Name = 'Test-KbIntelligenceQueries.ps1'; Engine = 'KbIntelligenceQueryCases.py'; Arguments = @('-IndexPath', $sqlitePath, '-ValidationCasesPath', $casesPath) }
    )
    foreach ($run in $wrapperRuns) {
        $wrapperPath = Join-Path $scriptsRoot $run.Name
        $output = @(& $pwshPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapperPath @($run.Arguments) 2>&1) -join "`n"
        $exitCode = $LASTEXITCODE
        Assert-Equal ("{0}: exit code with fake py" -f $run.Name) '0' ([string]$exitCode)
        Assert-Match ("{0}: calls py with -3 before the engine" -f $run.Name) ('FAKE-PY-ARGS: -3 "?[^\s"]*' + [regex]::Escape($run.Engine)) $output
    }

    # 8. With no usable Python, the query wrappers fail with a clear prerequisite message.
    Use-OnlyPath -Directories @()
    foreach ($run in $wrapperRuns) {
        $wrapperPath = Join-Path $scriptsRoot $run.Name
        $output = @(& $pwshPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapperPath @($run.Arguments) 2>&1) -join "`n"
        $exitCode = $LASTEXITCODE
        Assert-Equal ("{0}: fails without Python" -f $run.Name) 'True' ([string]($exitCode -ne 0))
        Assert-Match ("{0}: prerequisite message without Python" -f $run.Name) 'PREREQUISITE MISSING: no usable Python 3' $output
    }
}
finally {
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output '---'
if ($failures -eq 0) {
    Write-Output ("SELFTEST_OK: {0}/{0} cases passed" -f $cases)
    exit 0
}
else {
    Write-Output ("SELFTEST_FAIL: {0} of {1} cases failed" -f $failures, $cases)
    exit 1
}
