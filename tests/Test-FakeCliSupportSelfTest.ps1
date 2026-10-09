#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tests/fixtures/FakeCliSupport.ps1 on the current operating system.
.DESCRIPTION
    Builds a fake CLI with New-FakeCli and runs its launcher as a native command, checking that
    the exit code, arguments containing spaces, stdin, stdout and stderr all pass through.
    Success sentinel: FAKE_CLI_SUPPORT_SELFTEST_OK
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'fixtures/FakeCliSupport.ps1')

$fail = 0
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if ($Condition) { Write-Host "PASS  $Message" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL  $Message" -ForegroundColor Red }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fake-cli-support-selftest-' + [guid]::NewGuid().ToString('N'))

try {
    $launcher = New-FakeCli -Directory $tempRoot -Name 'fake-tool' -PwshBody @'
$stdin = [Console]::In.ReadToEnd()
[Console]::Error.WriteLine('FAKE-STDERR')
'ARGC=' + $args.Count
foreach ($a in $args) { 'ARG=[' + $a + ']' }
'STDIN=[' + $stdin.Trim() + ']'
exit 7
'@

    Assert-True (Test-Path -LiteralPath $launcher -PathType Leaf) 'launcher exists'
    Assert-True ([System.IO.Path]::GetExtension($launcher) -ne '.ps1') 'launcher is not a .ps1 (runs as a child process)'
    if ($IsWindows) {
        Assert-True ($launcher.EndsWith('.cmd')) 'Windows launcher is a .cmd'
    }
    else {
        Assert-True ([System.IO.Path]::GetExtension($launcher) -eq '') 'Unix launcher has no extension'
        $mode = [System.IO.File]::GetUnixFileMode($launcher)
        Assert-True (($mode -band [System.IO.UnixFileMode]::UserExecute) -ne 0) 'Unix launcher has the exec bit'
    }

    $stderrPath = Join-Path $tempRoot 'stderr.txt'
    $stdout = @('piped input' | & $launcher 'one two' 'three' 2>$stderrPath)
    $exitCode = $LASTEXITCODE

    Assert-True ($exitCode -eq 7) "exit code passes through (got $exitCode)"
    Assert-True ($stdout -contains 'ARGC=2') "argument count is 2 (got: $($stdout -join ' | '))"
    Assert-True ($stdout -contains 'ARG=[one two]') 'an argument with a space arrives as one element'
    Assert-True ($stdout -contains 'ARG=[three]') 'a plain argument arrives unchanged'
    Assert-True ($stdout -contains 'STDIN=[piped input]') 'stdin passes through'
    $stderrText = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    Assert-True ($stderrText -match 'FAKE-STDERR') 'stderr passes through'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-FakeCliSupportSelfTest.ps1" }
Write-Host 'FAKE_CLI_SUPPORT_SELFTEST_OK' -ForegroundColor Cyan
