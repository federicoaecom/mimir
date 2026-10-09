#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/Test-PyScriptsParse.ps1.

.DESCRIPTION
    Runs the parse gate against a temporary root with controlled PATH values and checks that:
      - with a `python3` older than 3.8 first on PATH, the gate skips it and parses with a
        Python 3.8+ interpreter, the same one the product's discovery helper picks;
      - a syntax error is reported with its file and line;
      - with no Python on PATH, every file is reported as a finding and the gate exits 1.
    The old `python3` is a fake (`.cmd` on Windows, shell script elsewhere) that reports 3.6
    on `--version` and writes a marker file on any other call. The gate's PATH is set exactly,
    and the pwsh install folder is never on it, since it may be a shared `bin` that also holds a
    Python; a new folder holding only a pwsh launcher takes its place.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolPath = Join-Path $repoRoot 'tools/Test-PyScriptsParse.ps1'
. (Join-Path $repoRoot 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

# New-OldPythonFake, New-PwshOnlyPathDirectory and Invoke-PwshScriptWithExactPath.
. (Join-Path $repoRoot 'tests/fixtures/FakePythonSupport.ps1')

# Runs the gate as a child process whose PATH is exactly -PathValue; returns the exit code and parsed JSON.
function Invoke-ParseGate {
    param([string]$RootPath, [string]$PathValue)
    $raw = Invoke-PwshScriptWithExactPath -PathValue $PathValue -ScriptPath $toolPath -Parameters @{ RootPath = $RootPath; AsJson = $true }
    $exitCode = $LASTEXITCODE
    $report = $null
    try {
        $report = ($raw -join "`n") | ConvertFrom-Json
    } catch {
        $failures.Add("gate output did not parse as JSON: $($_.Exception.Message)")
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Report = $report }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-pyparse-selftest-' + [Guid]::NewGuid().ToString('N'))

try {
    $realPython = Get-GeneXusPythonExecutable
    $pwshOnlyBin = New-PwshOnlyPathDirectory -Directory (Join-Path $fixtureRoot 'pwsh-only-bin')
    Assert-True ($null -ne $realPython) 'a usable Python 3.8+ must be available on this host'

    $okRoot = Join-Path $fixtureRoot 'ok-root'
    New-Item -ItemType Directory -Path (Join-Path $okRoot 'tools') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $okRoot 'tools/ok.py') -Encoding utf8NoBOM -Value 'x = 1'

    $badRoot = Join-Path $fixtureRoot 'bad-root'
    New-Item -ItemType Directory -Path (Join-Path $badRoot 'tests') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $badRoot 'tests/bad.py') -Encoding utf8NoBOM -Value "x = 1`ndef broken(:`n"

    if ($null -ne $realPython) {
        $oldPyBin = Join-Path $fixtureRoot 'old-python-bin'
        $marker = Join-Path $fixtureRoot 'old-python-ran.txt'
        New-OldPythonFake -Directory $oldPyBin -MarkerPath $marker | Out-Null
        $pathWithOldFirst = @($oldPyBin, (Split-Path -Parent $realPython.Source), $pwshOnlyBin) -join [System.IO.Path]::PathSeparator

        # 1) An old python3 first on PATH is skipped; a valid file passes.
        $run = Invoke-ParseGate -RootPath $okRoot -PathValue $pathWithOldFirst
        Assert-True ($run.ExitCode -eq 0) "with an old python3 first on PATH, a valid file should pass (exit $($run.ExitCode))"
        if ($run.Report) {
            Assert-True ($run.Report.status -eq 'pass' -and $run.Report.fileCount -eq 1) "expected status pass over 1 file (got '$($run.Report.status)', $($run.Report.fileCount) file(s))"
        }
        Assert-True (-not (Test-Path -LiteralPath $marker)) 'the gate should not run a python3 older than 3.8 beyond its --version probe'

        # 2) A syntax error is reported with file and line.
        $run = Invoke-ParseGate -RootPath $badRoot -PathValue $pathWithOldFirst
        Assert-True ($run.ExitCode -eq 1) "a syntax error should exit 1 (got $($run.ExitCode))"
        if ($run.Report) {
            $finding = @($run.Report.findings)
            Assert-True ($finding.Count -eq 1 -and $finding[0].file -match 'bad\.py$' -and $finding[0].line -eq 2) 'the syntax error should be reported once, on bad.py line 2'
        }
    }

    # 3) No Python on PATH: every file becomes a finding and the gate exits 1.
    $run = Invoke-ParseGate -RootPath $okRoot -PathValue $pwshOnlyBin
    Assert-True ($run.ExitCode -eq 1) "without Python, the gate should exit 1 (got $($run.ExitCode))"
    if ($run.Report) {
        $finding = @($run.Report.findings)
        Assert-True ($run.Report.status -eq 'fail' -and $finding.Count -eq 1) 'without Python, the one file should be reported as a finding'
        Assert-True ($finding.Count -ge 1 -and $finding[0].message -match 'Python executable not found') 'without Python, the finding should say the interpreter was not found'
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

Write-Host 'PASS: Test-PyScriptsParseSelfTest.ps1' -ForegroundColor Green
exit 0
