#requires -Version 7.4
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
$invoke = Join-Path $scriptsDir 'Invoke-OpenCode.ps1'
. (Join-Path $scriptsDir 'OpenCodeStreamSupport.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

function Assert-True { param([bool]$c, [string]$m) if (-not $c) { throw $m } }

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-oc-invoke-limit-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$origXdg = $env:XDG_DATA_HOME
try {
    $fakeCmd = New-FakeCli -Directory $tempRoot -Name 'fake-opencode' -PwshBody @'
$a = @($args)
if ($a.Count -ge 1 -and $a[0] -eq '--version') {
    '1.0.0-fake'
    exit 0
}
if ($a.Count -ge 2 -and $a[0] -eq 'agent' -and $a[1] -eq 'list') {
    'reviewer-fake (all)'
    '['; '{"permission":"*","action":"deny","pattern":"*"},'
    '{"permission":"read","action":"allow","pattern":"*"},'
    '{"permission":"grep","action":"allow","pattern":"*"},'
    '{"permission":"glob","action":"allow","pattern":"*"},'
    '{"permission":"list","action":"allow","pattern":"*"},'
    '{"permission":"external_directory","action":"deny","pattern":"*"}'; ']'
    exit 0
}
[void][Console]::In.ReadToEnd()
# Like the real CLI, write the provider-limit log during the run: the adapter only reads logs
# from its run window, and a log written before the call can fall outside it on a slow runner.
Set-Content -LiteralPath (Join-Path $env:XDG_DATA_HOME 'opencode/log/hit.log') -Value '{"statusCode":429,"msg":"weekly usage limit"}' -Encoding utf8
switch ($env:FAKE_PLAN) {
    'hang' { Start-Sleep -Seconds 30; exit 0 }
    'exit' { exit 3 }
    'streamerror' { '{"type":"error","error":{"data":{"message":"boom"}}}'; exit 0 }
    'nocomp' { '{"type":"text","part":{"messageID":"m1","text":"x"}}'; exit 0 }
    'ok' { '{"type":"text","part":{"messageID":"m1","text":"OK-LIMIT"}}'; '{"type":"step_finish","part":{"reason":"stop"}}'; exit 0 }
    default { throw "FAKE_PLAN $($env:FAKE_PLAN)" }
}
'@
    $promptFile = Join-Path $tempRoot 'prompt.txt'
    Set-Content -LiteralPath $promptFile -Value 'oi' -Encoding utf8 -NoNewline
    $xdg = Join-Path $tempRoot 'xdg'
    $logDir = Join-Path $xdg 'opencode/log'
    [System.IO.Directory]::CreateDirectory($logDir) | Out-Null
    $env:XDG_DATA_HOME = $xdg

    $fixedUsage = Format-OpenCodeLimitBlock -Kind 'usage-limit' -Message ''

    foreach ($plan in @('hang','exit','streamerror','nocomp')) {
        $env:FAKE_PLAN = $plan
        $threw = $false; $msg = ''
        $timeout = if ($plan -eq 'hang') { 2 } else { 60 }
        try {
            & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec $timeout -MaxAttempts 1
        } catch { $threw = $true; $msg = $_.Exception.Message }
        Assert-True $threw "$plan should throw"
        Assert-True ($msg.StartsWith($fixedUsage)) "$plan should use Format usage; got: $msg"
    }

    $env:FAKE_PLAN = 'ok'
    $ans = & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec 60 -MaxAttempts 1
    Assert-True (([string]$ans) -match 'OK-LIMIT') "ok with a 429 log must not throw; got: $ans"

    Write-Output 'OK: Test-OpenCodeInvokeLimitSelfTest.ps1'
} finally {
    Remove-Item Env:FAKE_PLAN -ErrorAction SilentlyContinue
    if ($null -eq $origXdg) { Remove-Item Env:XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $origXdg }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
