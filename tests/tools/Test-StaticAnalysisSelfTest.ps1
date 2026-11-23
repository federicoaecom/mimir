#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/Invoke-StaticAnalysis.ps1.
.DESCRIPTION
    Builds a synthetic git repository in a temp folder and runs the advisory step against it:
      - a fake ruff reports one pyflakes finding, which the report prints with its relative path;
      - ruff is called with the pyflakes rules, the Python 3.8 target, no config file and no cache;
      - a missing ruff or PSScriptAnalyzer is reported as skipped, and the step still exits 0;
      - a ruff that fails to run makes the step exit 1;
      - when PSScriptAnalyzer is installed, an unused variable is reported (otherwise that case
        is skipped, since the test must not depend on machine-specific tools).
    Success sentinel: STATIC_ANALYSIS_SELFTEST_OK
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $testsRoot 'fixtures/AssertSupport.ps1')
. (Join-Path $testsRoot 'fixtures/FakeCliSupport.ps1')

$scriptPath = Join-Path (Split-Path -Parent $testsRoot) 'tools/Invoke-StaticAnalysis.ps1'
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('static-analysis-selftest-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $scratch 'repo'
$fakes = Join-Path $scratch 'fakes'
$argsLog = Join-Path $scratch 'ruff-args.txt'

function Invoke-Step {
    param([string[]] $Arguments)
    $output = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -RootPath $repo @Arguments 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (@($output | ForEach-Object { [string] $_ }) -join "`n") }
}

try {
    foreach ($folder in 'tools', 'tests', 'docs') { New-Item -ItemType Directory -Path (Join-Path $repo $folder) -Force | Out-Null }
    Set-Content -LiteralPath (Join-Path $repo 'tools/sample.py') -Value "import os`n"
    Set-Content -LiteralPath (Join-Path $repo 'docs/outside.py') -Value "import sys`n"
    Set-Content -LiteralPath (Join-Path $repo 'tests/Sample.ps1') -Value "function Get-Thing {`n    `$unused = 1`n    'thing'`n}`n"
    git -C $repo init --quiet
    git -C $repo add --all

    $fakeRuff = New-FakeCli -Directory $fakes -Name 'ruff' -PwshBody @"
Set-Content -LiteralPath '$argsLog' -Value (`$args -join "`n")
`$files = @(`$args | Where-Object { `$_ -like '*.py' })
`$findings = foreach (`$file in `$files) {
    @{ filename = `$file; location = @{ row = 1; column = 8 }; code = 'F401'; message = '``os`` imported but unused' }
}
ConvertTo-Json -InputObject @(`$findings) -Depth 4
exit 0
"@
    $brokenRuff = New-FakeCli -Directory $fakes -Name 'broken-ruff' -PwshBody "[Console]::Error.WriteLine('ruff crashed'); exit 2"
    $noAnalyzer = @('-PSScriptAnalyzerModule', 'NoSuchAnalyzerModule')

    Invoke-AssertCase 'a ruff finding is reported with its relative path' {
        $run = Invoke-Step (@('-RuffCommand', $fakeRuff) + $noAnalyzer)
        Assert-Equal $run.ExitCode 0 'exit code with findings'
        Assert-Contains $run.Text 'tools/sample.py:1:8 F401 `os` imported but unused' 'report line'
        Assert-Contains $run.Text 'STATIC_ANALYSIS python=1 powershell=skipped' 'summary line'
        Assert-Contains $run.Text 'SKIPPED powershell: module NoSuchAnalyzerModule is not installed' 'analyzer skip line'
    }

    Invoke-AssertCase 'ruff gets the pyflakes rules, the 3.8 target, no config, no cache, and only skills, tools and tests files' {
        $sent = @(Get-Content -LiteralPath $argsLog)
        Assert-Equal ($sent[0..8] -join ' ') 'check --isolated --no-cache --select F --target-version py38 --output-format json' 'ruff arguments'
        Assert-Equal (@($sent | Where-Object { $_ -like '*.py' }) -join '|') 'tools/sample.py' 'files passed to ruff'
    }

    Invoke-AssertCase 'a missing ruff is skipped and the step still exits 0' {
        $run = Invoke-Step (@('-RuffCommand', (Join-Path $fakes 'no-such-ruff')) + $noAnalyzer)
        Assert-Equal $run.ExitCode 0 'exit code without tools'
        Assert-Match $run.Text 'SKIPPED python: ruff command .+no-such-ruff. was not found' 'ruff skip line'
        Assert-Contains $run.Text 'STATIC_ANALYSIS python=skipped powershell=skipped' 'summary line'
    }

    Invoke-AssertCase 'a ruff that fails to run makes the step exit 1' {
        $run = Invoke-Step (@('-RuffCommand', $brokenRuff) + $noAnalyzer)
        Assert-Equal $run.ExitCode 1 'exit code when ruff fails'
        Assert-Contains $run.Text 'ERROR python: ruff exited 2' 'error line'
    }

    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        Invoke-AssertCase 'PSScriptAnalyzer reports an unused variable' {
            $run = Invoke-Step @('-RuffCommand', (Join-Path $fakes 'no-such-ruff'))
            Assert-Equal $run.ExitCode 0 'exit code with analyzer findings'
            Assert-Match $run.Text 'tests/Sample\.ps1:2:5 PSUseDeclaredVarsMoreThanAssignments ' 'analyzer finding'
            Assert-Contains $run.Text 'STATIC_ANALYSIS python=skipped powershell=1' 'summary line'
        }
    }
    else {
        Write-Host 'SKIP  PSScriptAnalyzer is not installed; its finding case did not run' -ForegroundColor Yellow
    }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-AssertRun
Write-Host 'STATIC_ANALYSIS_SELFTEST_OK' -ForegroundColor Cyan
