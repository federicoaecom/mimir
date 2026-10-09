#requires -Version 7.4
<#
.SYNOPSIS
    Contract self-test of CodexCliSupport.ps1's pure functions (mimir-delegate skill).
.DESCRIPTION
    Validates Get-CodexExecErrorMessage (error extraction from stdout/stderr), Resolve-CodexExe
    in -Override mode, and deterministic automatic discovery with a synthetic root:
    the canonical executable takes precedence, backup-* directories are excluded, and the
    fallback is used only when the canonical one is not available. Off Windows, it also checks
    PATH discovery: a fake codex failing --version is skipped and the BLOCK names no Windows path.
    Success sentinel: OK: Test-CodexCliSupportSelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'CodexCliSupport.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

$fail = 0
function Assert-Equal {
    param([string]$Label, $Got, $Expected)
    if ([string]$Got -eq [string]$Expected) {
        Write-Host ("PASS  {0}" -f $Label) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0} -> '{1}' (expected '{2}')" -f $Label, $Got, $Expected) -ForegroundColor Red
    }
}

# Get-CodexExecErrorMessage
$e1 = Get-CodexExecErrorMessage -StdoutText 'ERROR: {"type":"error","error":{"message":"boom"}}' -StderrText ''
Assert-Equal 'error: extracts message' $e1 'boom'

$e2 = Get-CodexExecErrorMessage -StdoutText 'all good, no error' -StderrText ''
Assert-Equal 'no error -> empty' $e2 ''

$e3 = Get-CodexExecErrorMessage -StdoutText '' -StderrText 'ERROR: {"error":{"message":"The gpt-5.5 model requires a newer version of Codex."}}'
Assert-Equal 'error in stderr (newer model)' $e3 'The gpt-5.5 model requires a newer version of Codex.'

$e4 = Get-CodexExecErrorMessage -StdoutText 'ERROR: {invalid json' -StderrText ''
Assert-Equal 'error with invalid json -> raw text' $e4 '{invalid json'

$e5 = Get-CodexExecErrorMessage -StdoutText '' -StderrText '{"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota"}}'
Assert-Equal 'error: native API json without ERROR prefix' $e5 'You exceeded your current quota, please check your plan and billing details.'

$e6 = Get-CodexExecErrorMessage -StdoutText '' -StderrText '{"error":"rate_limit_exceeded"}'
Assert-Equal 'error: native json with string error' $e6 'rate_limit_exceeded'

$e7 = Get-CodexExecErrorMessage -StdoutText '' -StderrText 'HTTP 429: rate_limit_exceeded - Requests per minute quota exceeded'
Assert-Equal 'error: 429 / rate limit sentinel in stderr' $e7 'HTTP 429: rate_limit_exceeded - Requests per minute quota exceeded'

$e8 = Get-CodexExecErrorMessage -StdoutText '' -StderrText 'Your credit balance is too low to access the OpenAI API.'
Assert-Equal 'error: credit balance sentinel in stderr' $e8 'Your credit balance is too low to access the OpenAI API.'

$e9 = Get-CodexExecErrorMessage -StdoutText '' -StderrText '401 Unauthorized: Invalid API key provided.'
Assert-Equal 'error: auth / unauthorized sentinel' $e9 '401 Unauthorized: Invalid API key provided.'

$e10 = Get-CodexExecErrorMessage -StdoutText '' -StderrText 'Authentication failed: token expired.'
Assert-Equal 'error: token expired sentinel' $e10 'Authentication failed: token expired.'

$e11 = Get-CodexExecErrorMessage -StdoutText '' -StderrText 'The model gpt-5 does not exist or you do not have access to it.'
Assert-Equal 'error: model does not exist sentinel' $e11 'The model gpt-5 does not exist or you do not have access to it.'

$e12 = Get-CodexExecErrorMessage -StdoutText '' -StderrText 'Server is overloaded. Please try again later.'
Assert-Equal 'error: overloaded sentinel' $e12 'Server is overloaded. Please try again later.'

$e13 = Get-CodexExecErrorMessage -StdoutText '' -StderrText 'ERROR: General communication failure'
Assert-Equal 'error: ERROR: plain-text fallback' $e13 'General communication failure'

# Resolve-CodexExe -Override
$self = (Get-Command pwsh).Source
$rOk = Resolve-CodexExe -Override $self
Assert-Equal 'existing override returns the path' $rOk $self

$threw = $false
try { Resolve-CodexExe -Override 'C:\__nao_existe__\codex.exe' | Out-Null } catch { $threw = $true }
Assert-Equal 'nonexistent override throws BLOCK' $threw $true

# Resolve-CodexExe - deterministic automatic discovery
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$probeRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot ('CodexCliSupportSelfTest_' + [guid]::NewGuid().ToString('N'))))
if (-not $probeRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "BLOCK: unexpected temp root in self-test: $probeRoot"
}
$canonicalPath = Join-Path $probeRoot 'codex.exe'
$stagedDir = Join-Path $probeRoot 'staged-alpha'
$stagedPath = Join-Path $stagedDir 'codex.exe'
$backupDir = Join-Path $probeRoot 'backup-before-0.142.5'
$backupPath = Join-Path $backupDir 'codex.exe'
$originalVersionProbe = ${function:Get-CodexExeVersion}
try {
    New-Item -ItemType Directory -Path $stagedDir, $backupDir -Force | Out-Null
    New-Item -ItemType File -Path $canonicalPath, $stagedPath, $backupPath -Force | Out-Null

    function Get-CodexExeVersion {
        param([string]$ExePath)
        if ([string]::Equals($ExePath, $canonicalPath, [StringComparison]::OrdinalIgnoreCase)) {
            return [version]'0.142.5'
        }
        if ([string]::Equals($ExePath, $stagedPath, [StringComparison]::OrdinalIgnoreCase)) {
            return [version]'0.146.0'
        }
        if ([string]::Equals($ExePath, $backupPath, [StringComparison]::OrdinalIgnoreCase)) {
            return [version]'9.9.9'
        }
        return $null
    }

    $candidates = @(Get-CodexExeCandidatePaths -BasePath $probeRoot)
    Assert-Equal 'discovery: excludes backup-*' ($candidates -contains $backupPath) $false
    Assert-Equal 'discovery: canonical comes first' $candidates[0] $canonicalPath
    Assert-Equal 'resolve: canonical takes precedence over a higher alpha version' (Resolve-CodexExe -BasePath $probeRoot) $canonicalPath

    Remove-Item -LiteralPath $canonicalPath -Force
    Assert-Equal 'resolve: fallback without canonical' (Resolve-CodexExe -BasePath $probeRoot) $stagedPath

    Remove-Item -LiteralPath $stagedPath -Force
    $onlyBackupThrew = $false
    try { Resolve-CodexExe -BasePath $probeRoot | Out-Null } catch { $onlyBackupThrew = $true }
    Assert-Equal 'resolve: backup only blocks' $onlyBackupThrew $true
}
finally {
    Set-Item -Path Function:Get-CodexExeVersion -Value $originalVersionProbe
    if (Test-Path -LiteralPath $probeRoot -PathType Container) {
        Remove-Item -LiteralPath $probeRoot -Recurse -Force
    }
}

# Resolve-CodexExe off Windows: with no override, `codex` comes from PATH and must
# answer `codex --version`; APPDATA, LOCALAPPDATA and USERPROFILE are not needed (Linux and macOS
# do not set them).
if ($IsWindows) {
    Write-Host 'SKIP: off-Windows codex PATH discovery cases (Windows host)' -ForegroundColor Yellow
}
else {
    $unixRoot = Join-Path ([IO.Path]::GetTempPath()) ('CodexCliSupportUnixSelfTest_' + [guid]::NewGuid().ToString('N'))
    $badDir = Join-Path $unixRoot 'bad'
    $goodDir = Join-Path $unixRoot 'good'
    $savedEnv = @{}
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'USERPROFILE')) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
    $oldPath = $env:PATH
    try {
        $badCodex = New-FakeCli -Directory $badDir -Name 'codex' -PwshBody 'exit 1'
        $goodCodex = New-FakeCli -Directory $goodDir -Name 'codex' -PwshBody @'
if ($args.Count -ge 1 -and $args[0] -eq '--version') { Write-Output 'codex-cli 0.150.0'; exit 0 }
exit 0
'@
        foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $null) }
        # The launchers need pwsh ($PSHOME) and `dirname`; a private tools folder links only
        # `dirname`, so a real codex in /usr/bin or anywhere else on the host cannot leak in.
        $toolsDir = Join-Path $unixRoot 'tools'
        New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
        $dirnamePath = (Get-Command dirname -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        New-Item -ItemType SymbolicLink -Path (Join-Path $toolsDir 'dirname') -Target $dirnamePath | Out-Null
        $sep = [IO.Path]::PathSeparator
        $basePath = @($PSHOME, $toolsDir) -join $sep

        $env:PATH = (@($badDir, $goodDir) -join $sep) + $sep + $basePath
        $resolved = $null
        $unixErr = ''
        try { $resolved = Resolve-CodexExe } catch { $unixErr = $_.Exception.Message }
        Assert-Equal "off Windows: PATH discovery skips a codex failing --version and finds the next ($unixErr)" $resolved $goodCodex

        $env:PATH = $badDir + $sep + $basePath
        $threw = $false
        $msg = ''
        try { Resolve-CodexExe | Out-Null } catch { $threw = $true; $msg = $_.Exception.Message }
        Assert-Equal "off Windows: only a failing codex on PATH blocks with no Windows-only location ($msg)" ($threw -and $msg -match '^BLOCK:' -and $msg -notmatch 'LOCALAPPDATA|\.exe') $true

        $env:PATH = $oldPath
        Assert-Equal 'off Windows: -Override still wins over PATH' (Resolve-CodexExe -Override $badCodex) $badCodex
    }
    finally {
        $env:PATH = $oldPath
        foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnv[$name]) }
        if (Test-Path -LiteralPath $unixRoot -PathType Container) {
            Remove-Item -LiteralPath $unixRoot -Recurse -Force
        }
    }
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-CodexCliSupportSelfTest.ps1" }
Write-Host 'OK: Test-CodexCliSupportSelfTest.ps1' -ForegroundColor Cyan
