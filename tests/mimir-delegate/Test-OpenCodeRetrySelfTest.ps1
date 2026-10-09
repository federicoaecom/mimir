#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Self-test for Invoke-OpenCode.ps1's retry-once behavior (-MaxAttempts).
#
# Mechanism: a REAL fake-exe (New-FakeCli launcher -> pwsh body) injected via -OpenCodeExe. Since each attempt
# of the loop is a NEW PROCESS, the attempt number comes from an IN-FILE COUNTER ($env:FAKE_COUNTER);
# the stream each attempt emits is decided by $env:FAKE_PLAN (a comma-separated status list).
#
# Cases covered:
#  (i)   'truncated,ok' with -MaxAttempts 2 -> converts truncated into final text (counter == 2)
#  (ii)  'truncated' with -MaxAttempts 1 -> keeps the throw, WITHOUT the "(after N attempts)" annotation (counter == 1)
#  (iii) exit!=0 and an explicit stream error are TERMINAL (do not retry; counter == 1)
#  (iv)  'truncated,truncated' -MaxAttempts 2 -> throws with "(after 2 attempts; last status=truncated...)"
#  (v)   per-attempt anti-429 guard: with a 429 in the window (XDG_DATA_HOME seam), the retry is blocked
#        (terminal) and there is NO 2nd attempt (counter == 1). The fake writes the 429 log during
#        attempt 1 ($env:FAKE_LIMIT_LOG), so the log always falls inside that attempt's window.
#
# 429 detection (Get-OpenCodeUsageLimitError) reads the opencode log under XDG_DATA_HOME; the test
# uses a CLEAN temporary XDG_DATA_HOME in every case (isolating it from the machine's real log) and, in
# case (v), points it to a dir where the fake writes a 429 log during the run.

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
$invoke = Join-Path $scriptsDir 'Invoke-OpenCode.ps1'
. (Join-Path $scriptsDir 'OpenCodeStreamSupport.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Reset-Counter { param([string]$Path) Set-Content -LiteralPath $Path -Value '0' -Encoding ascii -NoNewline }
function Get-Counter  { param([string]$Path) [int](Get-Content -LiteralPath $Path -Raw) }

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-oc-retry-selftest-' + [System.Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

$origXdg = $env:XDG_DATA_HOME

try {
    # reader: increments the counter, consumes stdin (EOF), emits the attempt's status stream.
    $fakeCmd = New-FakeCli -Directory $tempRoot -Name 'fake-opencode' -PwshBody @'
$a = @($args)
# Guard D1/D2: the adapter calls `agent list` (opt-out -Agent reviewer-fake -> only confirms it
# resolves). Respond BEFORE the counter logic (doesn't consume an attempt) and without reading stdin.
if ($a.Count -ge 1 -and $a[0] -eq '--version') {
    '1.0.0-fake'
    exit 0
}
if ($a.Count -ge 2 -and $a[0] -eq 'agent' -and $a[1] -eq 'list') {
    'reviewer-fake (all)'
    '['
    '{"permission":"*","action":"deny","pattern":"*"},'
    '{"permission":"read","action":"allow","pattern":"*"},'
    '{"permission":"grep","action":"allow","pattern":"*"},'
    '{"permission":"glob","action":"allow","pattern":"*"},'
    '{"permission":"list","action":"allow","pattern":"*"},'
    '{"permission":"external_directory","action":"deny","pattern":"*"}'
    ']'
    exit 0
}
$counterFile = $env:FAKE_COUNTER
$n = 0
if ($counterFile -and (Test-Path -LiteralPath $counterFile)) { $n = [int](Get-Content -LiteralPath $counterFile -Raw) }
$n++
Set-Content -LiteralPath $counterFile -Value $n -Encoding ascii -NoNewline
[void][Console]::In.ReadToEnd()
# Like the real CLI, write the provider-limit log during the run: the adapter only reads logs
# from the attempt's window, and a log written before the call can fall outside it on a slow runner.
if ($env:FAKE_LIMIT_LOG) {
    Set-Content -LiteralPath $env:FAKE_LIMIT_LOG -Value '{"statusCode": 429, "msg": "You have reached your weekly usage limit"}' -Encoding utf8
}
$plan = @(($env:FAKE_PLAN -split ','))
$idx = [Math]::Min($n - 1, $plan.Count - 1)
$status = $plan[$idx]
switch ($status) {
    'ok'          { '{"type":"text","part":{"messageID":"m1","text":"OK-RETRY"}}'; '{"type":"step_finish","part":{"reason":"stop"}}'; exit 0 }
    'truncated'   { '{"type":"text","part":{"messageID":"m1","text":"preambulo"}}'; '{"type":"step_finish","part":{"reason":"tool-calls"}}'; exit 0 }
    'streamerror' { '{"type":"error","error":{"data":{"message":"fake stream error"}}}'; exit 0 }
    'exit'        { exit 3 }
    default       { throw "FAKE_PLAN unknown status: $status" }
}
'@

    $promptFile = Join-Path $tempRoot 'prompt.txt'
    Set-Content -LiteralPath $promptFile -Value 'oi' -Encoding utf8 -NoNewline

    # Clean XDG_DATA_HOME (no opencode/log) -> Get-OpenCodeUsageLimitError returns $null by default.
    $cleanXdg = Join-Path $tempRoot 'xdg-clean'
    [System.IO.Directory]::CreateDirectory($cleanXdg) | Out-Null
    $env:XDG_DATA_HOME = $cleanXdg

    # ---- (i) 'truncated,ok' with -MaxAttempts 2 ----
    $c = Join-Path $tempRoot 'c1.txt'; Reset-Counter $c
    $env:FAKE_COUNTER = $c; $env:FAKE_PLAN = 'truncated,ok'
    $ans = & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec 60 -MaxAttempts 2
    Assert-True (([string]$ans) -match 'OK-RETRY') "(i) -MaxAttempts 2 should convert truncated->ok; got: '$ans'."
    Assert-True ((Get-Counter $c) -eq 2) "(i) should have 2 attempts; counter=$(Get-Counter $c)."

    # ---- (ii) 'truncated' with -MaxAttempts 1 ----
    $c = Join-Path $tempRoot 'c2.txt'; Reset-Counter $c
    $env:FAKE_COUNTER = $c; $env:FAKE_PLAN = 'truncated'
    $threw = $false; $msg = ''
    try { & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec 60 -MaxAttempts 1 } catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-True $threw "(ii) -MaxAttempts 1 with truncated should throw."
    Assert-True ($msg -match 'truncat') "(ii) the message should indicate truncated; got: '$msg'."
    Assert-True (-not ($msg -match 'after .* attempts')) "(ii) -MaxAttempts 1 must not annotate '(after N attempts)'; got: '$msg'."
    Assert-True ((Get-Counter $c) -eq 1) "(ii) should have 1 attempt; counter=$(Get-Counter $c)."

    # ---- (iii-a) exit!=0 does NOT retry ----
    $c = Join-Path $tempRoot 'c3a.txt'; Reset-Counter $c
    $env:FAKE_COUNTER = $c; $env:FAKE_PLAN = 'exit,ok'
    $threw = $false; $msg = ''
    try { & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec 60 -MaxAttempts 2 } catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-True $threw "(iii-a) exit!=0 should throw."
    Assert-True ($msg -match 'code 3') "(iii-a) the message should cite the exit code; got: '$msg'."
    Assert-True ((Get-Counter $c) -eq 1) "(iii-a) exit!=0 must NOT retry; counter=$(Get-Counter $c)."

    # ---- (iii-b) a stream error does NOT retry ----
    $c = Join-Path $tempRoot 'c3b.txt'; Reset-Counter $c
    $env:FAKE_COUNTER = $c; $env:FAKE_PLAN = 'streamerror,ok'
    $threw = $false; $msg = ''
    try { & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec 60 -MaxAttempts 2 } catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-True $threw "(iii-b) a stream error should throw."
    Assert-True ($msg -match 'error in the stream') "(iii-b) the message should cite an error in the stream; got: '$msg'."
    Assert-True ((Get-Counter $c) -eq 1) "(iii-b) a stream error must NOT retry; counter=$(Get-Counter $c)."

    # ---- (iv) all truncate -> throw with the final status ----
    $c = Join-Path $tempRoot 'c4.txt'; Reset-Counter $c
    $env:FAKE_COUNTER = $c; $env:FAKE_PLAN = 'truncated,truncated'
    $threw = $false; $msg = ''
    try { & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec 60 -MaxAttempts 2 } catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-True $threw "(iv) all truncating should throw."
    Assert-True ($msg -match 'after 2 attempts') "(iv) should annotate '(after 2 attempts...)'; got: '$msg'."
    Assert-True ($msg -match 'last status=truncated') "(iv) should cite 'last status=truncated'; got: '$msg'."
    Assert-True ((Get-Counter $c) -eq 2) "(iv) should have 2 attempts; counter=$(Get-Counter $c)."

    # ---- (v) per-attempt anti-429 guard (XDG_DATA_HOME seam) ----
    $c = Join-Path $tempRoot 'c5.txt'; Reset-Counter $c
    $xdg429 = Join-Path $tempRoot 'xdg-429'
    $logDir = Join-Path $xdg429 'opencode/log'
    [System.IO.Directory]::CreateDirectory($logDir) | Out-Null
    $env:FAKE_COUNTER = $c; $env:FAKE_PLAN = 'truncated,ok'
    $env:FAKE_LIMIT_LOG = Join-Path $logDir 'fake.log'
    $env:XDG_DATA_HOME = $xdg429
    $threw = $false; $msg = ''
    try { & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $promptFile -Model 'fake/model' -TimeoutSec 60 -MaxAttempts 2 } catch { $threw = $true; $msg = $_.Exception.Message }
    $env:XDG_DATA_HOME = $cleanXdg
    Remove-Item Env:FAKE_LIMIT_LOG -ErrorAction SilentlyContinue
    Assert-True $threw "(v) a 429 in the window should block the retry (throw)."
    Assert-True ($msg -match 'usage quota') "(v) the message should be Format usage; got: '$msg'."
    Assert-True ($msg -notmatch 'System\.Collections|@{kind') "(v) the throw must not interpolate a hashtable; got: '$msg'."
    $fixedRate = Format-OpenCodeLimitBlock -Kind 'rate-limit' -Message ''
    Assert-True ($fixedRate -notmatch '429') "(v) the fixed rate part must not contain 429: $fixedRate"
    Assert-True ((Get-Counter $c) -eq 1) "(v) a 429 must NOT retry; counter=$(Get-Counter $c)."

    Write-Output 'OK: Test-OpenCodeRetrySelfTest.ps1'
}
finally {
    Remove-Item Env:FAKE_COUNTER -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_PLAN -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_LIMIT_LOG -ErrorAction SilentlyContinue
    if ($null -eq $origXdg) { Remove-Item Env:XDG_DATA_HOME -ErrorAction SilentlyContinue }
    else { $env:XDG_DATA_HOME = $origXdg }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
