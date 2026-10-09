#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for opencode.exe discovery.
.DESCRIPTION
    Validates the OpenCodeCliSupport.ps1 helper without depending on network or a real model.
    Success sentinel: OPENCODE_CLI_SUPPORT_SELFTEST_OK
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'OpenCodeCliSupport.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

$fail = 0
function Assert-True {
    param([bool] $Condition, [string] $Message)
    if ($Condition) { Write-Host "PASS  $Message" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL  $Message" -ForegroundColor Red }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-oc-cli-selftest-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

try {
    $fakeCmd = New-FakeCli -Directory $tempRoot -Name 'opencode' -PwshBody @'
if ($args.Count -ge 1 -and $args[0] -eq '--version') {
    Write-Output '9.8.7-test'
    exit 0
}
exit 0
'@

    $resolvedOverride = Resolve-OpenCodeExe -Override $fakeCmd
    Assert-True ($resolvedOverride -eq $fakeCmd) 'explicit override resolves the fake opencode'
    Assert-True ((Get-OpenCodeExeVersion -ExePath $fakeCmd) -eq '9.8.7-test') 'Get-OpenCodeExeVersion reads --version'

    # Off Windows, discovery is PATH only (no npm/%APPDATA% probe) and must work without APPDATA,
    # LOCALAPPDATA or USERPROFILE, which Linux and macOS do not set.
    if ($IsWindows) {
        Write-Host 'SKIP: off-Windows opencode discovery cases (Windows host)' -ForegroundColor Yellow
    }
    else {
        $savedEnv = @{}
        foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'USERPROFILE')) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
        $oldPath = $env:PATH
        try {
            foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $null) }

            $env:PATH = $tempRoot + [System.IO.Path]::PathSeparator + $oldPath
            $resolvedUnix = $null
            $unixErr = ''
            try { $resolvedUnix = Resolve-OpenCodeExe } catch { $unixErr = $_.Exception.Message }
            Assert-True ($resolvedUnix -eq $fakeCmd) "off Windows: PATH discovery finds the fake without APPDATA/LOCALAPPDATA/USERPROFILE ($unixErr)"

            $emptyDir = Join-Path $tempRoot 'empty-path'
            [System.IO.Directory]::CreateDirectory($emptyDir) | Out-Null
            $env:PATH = $emptyDir
            $threw = $false
            $msg = ''
            try { Resolve-OpenCodeExe | Out-Null } catch { $threw = $true; $msg = $_.Exception.Message }
            Assert-True ($threw -and $msg -match '^BLOCK:' -and $msg -notmatch 'APPDATA' -and $msg -notmatch '\.exe') "off Windows: no opencode on PATH blocks without Windows-only locations ($msg)"
        }
        finally {
            $env:PATH = $oldPath
            foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnv[$name]) }
        }
    }

    $oldPath = $env:PATH
    try {
        $env:PATH = $tempRoot + [System.IO.Path]::PathSeparator + $oldPath
        $resolvedPath = Resolve-OpenCodeExe
        Assert-True ($resolvedPath -eq $fakeCmd) 'Resolve-OpenCodeExe finds opencode on PATH'
    }
    finally {
        $env:PATH = $oldPath
    }

    $missing = Join-Path $tempRoot 'missing-opencode.exe'
    $threw = $false
    $msg = ''
    try { Resolve-OpenCodeExe -Override $missing | Out-Null }
    catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-True ($threw -and $msg -match 'does not exist') 'a nonexistent override blocks with a clear message'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-OpenCodeCliSupportSelfTest.ps1" }
Write-Host 'OPENCODE_CLI_SUPPORT_SELFTEST_OK' -ForegroundColor Cyan
