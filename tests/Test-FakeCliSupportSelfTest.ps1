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

    # -ProbeOutput: the launcher answers a lone probe argument itself; anything else reaches the body.
    $probeMarker = Join-Path $tempRoot 'probe-body-ran.txt'
    $probeLauncher = New-FakeCli -Directory $tempRoot -Name 'probe-tool' -ProbeOutput @{ '--version' = 'probe-tool 1.2.3' } -PwshBody (@'
Set-Content -LiteralPath '{0}' -Value ($args -join ' ')
Write-Output 'BODY'
'@ -f $probeMarker)
    $probeStdout = @(& $probeLauncher '--version')
    Assert-True ($LASTEXITCODE -eq 0) "a probe answered by the launcher exits 0 (got $LASTEXITCODE)"
    Assert-True (($probeStdout -join '|') -eq 'probe-tool 1.2.3') "a probe prints only its configured line (got: $($probeStdout -join ' | '))"
    Assert-True (-not (Test-Path -LiteralPath $probeMarker)) 'a probe answered by the launcher does not start the body'
    $probeStdout = @(& $probeLauncher '--version' 'extra')
    Assert-True ($probeStdout -contains 'BODY') 'a probe argument followed by another argument reaches the body'
    Assert-True ((Test-Path -LiteralPath $probeMarker) -and ((Get-Content -LiteralPath $probeMarker -Raw).Trim() -eq '--version extra')) 'the body receives both arguments'
    $rejected = $false
    try { New-FakeCli -Directory $tempRoot -Name 'bad-probe' -PwshBody 'exit 0' -ProbeOutput @{ '--version' = 'a & b' } | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'a probe line with a character the launcher cannot print safely is rejected'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-FakeCliSupportSelfTest.ps1" }
Write-Host 'FAKE_CLI_SUPPORT_SELFTEST_OK' -ForegroundColor Cyan
