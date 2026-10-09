#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for skills/mimir-lite/scripts/Test-MimirPowerShellRuntime.ps1.

.DESCRIPTION
    Runs the runtime gate in a child of the running pwsh whose PATH is exactly one test folder,
    so the `pwsh` the gate finds and runs is a fake. The fake ignores its arguments and prints
    a configured line: `<version>|<isWindows>` as the gate asks a real pwsh to report, or only
    a version, as an older gate's child call would print. Checks that:
      - off Windows, 7.4.2 blocks and 7.4.6 passes (7.4.6 floor on Linux and macOS);
      - on Windows, 7.4.0 passes;
      - an explicit -MinimumVersion 7.4, as existing workspace wrappers pass, is still raised
        to 7.4.6 off Windows;
      - a version-only answer is judged against the host OS;
      - no pwsh on PATH and an unparsable version both block;
      - a prerelease (`-preview.5`, `-rc.1`) of a version above the minimum passes, a prerelease
        of exactly the minimum blocks as too old, and build metadata (`+...`) is ignored.
    The fake is a `.cmd` file on Windows and an executable `#!/bin/sh` script elsewhere; it
    uses only shell built-ins, because its PATH holds nothing else.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$enginePath = Join-Path $repoRoot 'skills/mimir-lite/scripts/Test-MimirPowerShellRuntime.ps1'

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

# Invoke-PwshScriptWithExactPath.
. (Join-Path $repoRoot 'tests/fixtures/FakePythonSupport.ps1')

# Writes a fake `pwsh` into a new folder under the fixture root that prints -Line and exits 0;
# returns the folder, to use as the gate's whole PATH. -Line holds only letters, digits, dots,
# dashes, `+` and `|`.
function New-FakePwshDirectory {
    param([string]$Name, [string]$Line)

    $directory = Join-Path $fixtureRoot $Name
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if ($IsWindows) {
        $lines = @(
            '@echo off'
            ('echo {0}' -f $Line.Replace('|', '^|'))
            'exit /b 0'
        )
        [System.IO.File]::WriteAllText((Join-Path $directory 'pwsh.cmd'), (($lines -join "`r`n") + "`r`n"), $utf8NoBom)
    } else {
        $path = Join-Path $directory 'pwsh'
        $lines = @(
            '#!/bin/sh'
            ("printf '%s\n' '{0}'" -f $Line)
            'exit 0'
        )
        [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $utf8NoBom)
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
    }
    return (Resolve-Path -LiteralPath $directory).Path
}

# Runs the gate with PATH set to -PathValue; returns its exit code and output text.
function Invoke-RuntimeGate {
    param([string]$PathValue, [hashtable]$Parameters = @{})
    $raw = Invoke-PwshScriptWithExactPath -PathValue $PathValue -ScriptPath $enginePath -Parameters $Parameters
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ((@($raw) | ForEach-Object { "$_" }) -join "`n").Trim() }
}

function Assert-Blocks {
    param($Run, [string]$Case, [string]$Pattern)
    Assert-True ($Run.ExitCode -eq 1) "${Case}: should exit 1 (got $($Run.ExitCode); output '$($Run.Output)')"
    Assert-True ($Run.Output -match '^BLOCK: ') "${Case}: should print a BLOCK line (got '$($Run.Output)')"
    if ($Pattern) {
        Assert-True ($Run.Output -match $Pattern) "${Case}: output should match '$Pattern' (got '$($Run.Output)')"
    }
}

function Assert-Passes {
    param($Run, [string]$Case, [string]$Version)
    Assert-True ($Run.ExitCode -eq 0) "${Case}: should exit 0 (got $($Run.ExitCode); output '$($Run.Output)')"
    Assert-True ($Run.Output -match ('^POWERSHELL_RUNTIME_OK: pwsh ' + [regex]::Escape($Version) + ' at ')) "${Case}: should print POWERSHELL_RUNTIME_OK for $Version (got '$($Run.Output)')"
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-pwshruntime-selftest-' + [Guid]::NewGuid().ToString('N'))

try {
    [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null

    # 1) Off Windows, 7.4.2 is below the 7.4.6 floor.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'off-windows-742' -Line '7.4.2|False')
    Assert-Blocks -Run $run -Case '7.4.2 off Windows' -Pattern '7\.4\.6 or later required; found 7\.4\.2 .*Linux and macOS need 7\.4\.6'

    # 2) Off Windows, 7.4.6 passes.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'off-windows-746' -Line '7.4.6|False')
    Assert-Passes -Run $run -Case '7.4.6 off Windows' -Version '7.4.6'

    # 3) On Windows, 7.4.0 passes (the minimum stays 7.4).
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'windows-740' -Line '7.4.0|True')
    Assert-Passes -Run $run -Case '7.4.0 on Windows' -Version '7.4.0'

    # 4) An explicit -MinimumVersion 7.4 (what existing wrappers pass) is still raised off Windows.
    $run = Invoke-RuntimeGate -PathValue (Join-Path $fixtureRoot 'off-windows-742') -Parameters @{ MinimumVersion = '7.4' }
    Assert-Blocks -Run $run -Case 'explicit -MinimumVersion 7.4 with 7.4.2 off Windows' -Pattern '7\.4\.6 or later required'

    # 5) A higher explicit minimum is kept as is off Windows.
    $run = Invoke-RuntimeGate -PathValue (Join-Path $fixtureRoot 'off-windows-746') -Parameters @{ MinimumVersion = '7.5' }
    Assert-Blocks -Run $run -Case 'explicit -MinimumVersion 7.5 with 7.4.6 off Windows' -Pattern '7\.5 or later required; found 7\.4\.6'

    # 6) A version-only answer is judged against the host OS.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'version-only-742' -Line '7.4.2')
    if ($IsWindows) {
        Assert-Passes -Run $run -Case 'version-only 7.4.2 on a Windows host' -Version '7.4.2'
    } else {
        Assert-Blocks -Run $run -Case 'version-only 7.4.2 on a non-Windows host' -Pattern '7\.4\.6 or later required'
    }

    # 7) No pwsh on PATH.
    $emptyBin = Join-Path $fixtureRoot 'empty-bin'
    [System.IO.Directory]::CreateDirectory($emptyBin) | Out-Null
    $run = Invoke-RuntimeGate -PathValue $emptyBin
    Assert-Blocks -Run $run -Case 'no pwsh on PATH' -Pattern 'pwsh not found on PATH'

    # 8) An unparsable version.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'unparsable' -Line 'not-a-version|False')
    Assert-Blocks -Run $run -Case 'unparsable version' -Pattern 'could not determine pwsh version'

    # 9) A prerelease of a version above the minimum passes; the report keeps the full version.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'windows-preview' -Line '7.6.0-preview.5|True')
    Assert-Passes -Run $run -Case '7.6.0-preview.5 on Windows' -Version '7.6.0-preview.5'

    # 10) A release candidate above the floor passes off Windows.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'off-windows-rc' -Line '7.5.0-rc.1|False')
    Assert-Passes -Run $run -Case '7.5.0-rc.1 off Windows' -Version '7.5.0-rc.1'

    # 11) A prerelease of exactly the minimum precedes the release (semver), so it is too old.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'windows-740-preview' -Line '7.4.0-preview.1|True')
    Assert-Blocks -Run $run -Case '7.4.0-preview.1 on Windows' -Pattern '7\.4 or later required; found 7\.4\.0-preview\.1 '

    # 12) Off Windows, a prerelease of exactly the 7.4.6 floor is too old as well.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'off-windows-746-rc' -Line '7.4.6-rc.1|False')
    Assert-Blocks -Run $run -Case '7.4.6-rc.1 off Windows' -Pattern '7\.4\.6 or later required; found 7\.4\.6-rc\.1 '

    # 13) Build metadata alone does not make a prerelease.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'windows-build' -Line '7.4.0+build.7|True')
    Assert-Passes -Run $run -Case '7.4.0+build.7 on Windows' -Version '7.4.0+build.7'

    # 14) A suffix on a non-numeric core still blocks as unparsable.
    $run = Invoke-RuntimeGate -PathValue (New-FakePwshDirectory -Name 'unparsable-suffix' -Line 'seven-preview.1|False')
    Assert-Blocks -Run $run -Case 'unparsable version with a suffix' -Pattern 'could not determine pwsh version'
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host 'PASS: Test-MimirPowerShellRuntimeSelfTest.ps1' -ForegroundColor Green
exit 0
