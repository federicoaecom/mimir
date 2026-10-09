#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the pure functions in GeminiCliSupport.ps1.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'GeminiCliSupport.ps1')
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

Assert-Equal 'parse version' (ConvertFrom-GeminiVersionText 'gemini 0.35.3') ([version]'0.35.3')
Assert-Equal 'parse invalid -> null' (ConvertFrom-GeminiVersionText 'no version') $null

$helpOk = @'
--prompt
--approval-mode
--output-format
--model
'@
Assert-Equal 'help with required flags' (Test-GeminiHelpSupportsContract $helpOk) $true
Assert-Equal 'help incomplete' (Test-GeminiHelpSupportsContract '--prompt --model') $false

$err = Get-GeminiErrorMessage -StdoutText '' -StderrText 'Error: invalid model'
Assert-Equal 'extracts simple error' $err 'Error: invalid model'
$semErr = Get-GeminiErrorMessage -StdoutText 'tudo certo' -StderrText ''
Assert-Equal 'no error -> null' $semErr $null

# Proof that the extractor recognizes the interactive login prompt. Measured on 2026-08-06: with
# no cached credential, gemini writes this to STDOUT and exits 0.
$authTxt = Get-GeminiErrorMessage -StdoutText 'Opening authentication page in your browser. Do you want to continue? [Y/n]:' -StderrText ''
Assert-Equal 'recognizes interactive auth prompt on stdout' ($null -ne $authTxt) $true

# ---------------------------------------------------------------------------------------------
# BEHAVIORAL proofs of the adapter via fake-exe: non-JSON stdout with exit 0.
# Locked-in regression: the adapter used to blow up on ConvertFrom-Json and die with
# "invalid JSON: Unexpected character... O" without ever consulting Get-GeminiErrorMessage.
# ---------------------------------------------------------------------------------------------
$invokeScript = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-Gemini.ps1'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gx-gemini-selftest-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
try {
    $helpBody = 'Usage: gemini --prompt --approval-mode --output-format --model'

    function New-FakeGemini {
        param([string]$Name, [string]$StdoutBody)
        return New-FakeCli -Directory $tempDir -Name $Name -PwshBody @"
param()
if (`$args -contains '--version') { '0.54.0'; exit 0 }
if (`$args -contains '--help') { '$helpBody'; exit 0 }
Write-Output @'
$StdoutBody
'@
exit 0
"@
    }

    # (a) stdout with the login prompt -> actionable message, NOT "invalid JSON"
    $fakeAuth = New-FakeGemini -Name 'fake-gemini-auth' -StdoutBody 'Opening authentication page in your browser. Do you want to continue? [Y/n]:'
    $msgAuth = ''
    try { $null = & $invokeScript -GeminiExe $fakeAuth -Message 'ping' -Model 'gemini-3-flash-preview' }
    catch { $msgAuth = [string]$_.Exception.Message }
    Assert-Equal 'auth stdout: reports the real reason' ($msgAuth -match 'authentication') $true
    Assert-Equal 'auth stdout: does NOT report invalid JSON' ($msgAuth -notmatch 'invalid JSON') $true

    # (b) unreadable stdout that the extractor does NOT recognize -> still "invalid JSON", now with a sample
    $fakeJunk = New-FakeGemini -Name 'fake-gemini-junk' -StdoutBody 'zzz garbled stdout sample zzz'
    $msgJunk = ''
    try { $null = & $invokeScript -GeminiExe $fakeJunk -Message 'ping' -Model 'gemini-3-flash-preview' }
    catch { $msgJunk = [string]$_.Exception.Message }
    Assert-Equal 'unreadable stdout: keeps the JSON-contract diagnostic' ($msgJunk -match 'invalid JSON') $true
    Assert-Equal 'unreadable stdout: includes a stdout sample' ($msgJunk -match 'zzz garbled stdout') $true
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-GeminiCliSupportSelfTest.ps1" }
Write-Host 'OK: Test-GeminiCliSupportSelfTest.ps1' -ForegroundColor Cyan
