#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for OpenCodeStreamSupport.ps1 (mimir-delegate skill).
.DESCRIPTION
    Exercises the opencode stream parsing functions with synthetic JSONL fixtures
    (no opencode, no network). Covers: single message, multi-message (preambles + final),
    final message fragmented across several parts, error event, absence of text and
    invalid lines. Deterministic.
    Success sentinel: OK: Test-OpenCodeStreamSupportSelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'OpenCodeStreamSupport.ps1')

$fail = 0
function Assert-Eq {
    param([string]$Name, $Got, $Expected)
    if ([string]$Got -eq [string]$Expected) {
        Write-Host ("PASS  {0}" -f $Name) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0}: got=[{1}] expected=[{2}]" -f $Name, $Got, $Expected) -ForegroundColor Red
    }
}

# 1) Single message
$linesSingle = @(
    '{"type":"step_start","part":{}}',
    '{"type":"text","part":{"messageID":"m1","text":"Resposta unica."}}',
    '{"type":"step_finish","part":{}}'
)
$ev = ConvertFrom-OpenCodeStreamLines -Lines $linesSingle
$parts = @(Get-OpenCodeTextParts -Events $ev)
Assert-Eq 'single: part count'  (@($parts).Count) 1
Assert-Eq 'single: finalText'     (Get-OpenCodeFinalText -TextParts $parts) 'Resposta unica.'
Assert-Eq 'single: null error'     ($null -eq (Get-OpenCodeStreamErrorMessage -Events $ev)) $true

# 2) Multi-message: preambles + final response in the last message
$linesMulti = @(
    '{"type":"text","part":{"messageID":"m1","text":"preambulo 1"}}',
    '{"type":"tool_use","part":{"tool":"bash"}}',
    '{"type":"text","part":{"messageID":"m2","text":"preambulo 2"}}',
    '{"type":"text","part":{"messageID":"m3","text":"RESPOSTA FINAL"}}'
)
$ev = ConvertFrom-OpenCodeStreamLines -Lines $linesMulti
$parts = @(Get-OpenCodeTextParts -Events $ev)
Assert-Eq 'multi: part count'   (@($parts).Count) 3
Assert-Eq 'multi: finalText (last msg only)' (Get-OpenCodeFinalText -TextParts $parts) 'RESPOSTA FINAL'
Assert-Eq 'multi: allText joins everything' (Get-OpenCodeAllText -TextParts $parts) "preambulo 1`n`npreambulo 2`n`nRESPOSTA FINAL"

# 3) Final message fragmented into two parts (same messageID)
$linesFrag = @(
    '{"type":"text","part":{"messageID":"m1","text":"pre"}}',
    '{"type":"text","part":{"messageID":"m2","text":"parte A "}}',
    '{"type":"text","part":{"messageID":"m2","text":"parte B"}}'
)
$ev = ConvertFrom-OpenCodeStreamLines -Lines $linesFrag
$parts = @(Get-OpenCodeTextParts -Events $ev)
Assert-Eq 'frag: finalText concatenates the last msg' (Get-OpenCodeFinalText -TextParts $parts) 'parte A parte B'

# 4) Error event
$linesErr = @(
    '{"type":"text","part":{"messageID":"m1","text":"oi"}}',
    '{"type":"error","error":{"data":{"message":"model does not support tools"}}}'
)
$ev = ConvertFrom-OpenCodeStreamLines -Lines $linesErr
Assert-Eq 'error: message extracted' (Get-OpenCodeStreamErrorMessage -Events $ev) 'model does not support tools'

# 5) No text event
$linesNoText = @('{"type":"step_start","part":{}}', '{"type":"step_finish","part":{}}')
$ev = ConvertFrom-OpenCodeStreamLines -Lines $linesNoText
$parts = @(Get-OpenCodeTextParts -Events $ev)
Assert-Eq 'no-text: count 0'    (@($parts).Count) 0
Assert-Eq 'no-text: empty finalText' (Get-OpenCodeFinalText -TextParts $parts) ''

# 6) Empty/invalid lines are ignored
$linesJunk = @('', '   ', 'this is not json', '{"type":"text","part":{"messageID":"m1","text":"ok"}}')
$ev = ConvertFrom-OpenCodeStreamLines -Lines $linesJunk
$parts = @(Get-OpenCodeTextParts -Events $ev)
Assert-Eq 'junk: ignores invalid, 1 part' (@($parts).Count) 1
Assert-Eq 'junk: finalText'       (Get-OpenCodeFinalText -TextParts $parts) 'ok'

# ── Finding D: completion signal (step_finish/reason) + precedence verdict ────────────

function Get-Verdict {
    # Helper: derives the signal from the fixtures and applies the verdict over the real finalText.
    param([string[]]$Lines)
    $ev = ConvertFrom-OpenCodeStreamLines -Lines $Lines
    $sig = Get-OpenCodeCompletionSignal -Events $ev
    $final = Get-OpenCodeFinalText -TextParts (Get-OpenCodeTextParts -Events $ev)
    return (Get-OpenCodeCompletionVerdict -HasStepFinish $sig.hasStepFinish -Reason $sig.reason -FinalText $final)
}

# 7) reason=stop + text -> ok
$linesStop = @(
    '{"type":"text","part":{"messageID":"m1","text":"resposta final"}}',
    '{"type":"step_finish","part":{"reason":"stop"}}'
)
$sig = Get-OpenCodeCompletionSignal -Events (ConvertFrom-OpenCodeStreamLines -Lines $linesStop)
Assert-Eq 'stop: hasStepFinish' $sig.hasStepFinish $true
Assert-Eq 'stop: reason'        $sig.reason 'stop'
Assert-Eq 'stop: verdict ok'    (Get-Verdict $linesStop).status 'ok'

# 8) reason=length -> truncated (classic truncation case)
$linesLen = @(
    '{"type":"text","part":{"messageID":"m1","text":"truncated preamble"}}',
    '{"type":"step_finish","part":{"reason":"length"}}'
)
$vLen = Get-Verdict $linesLen
Assert-Eq 'length: verdict truncated' $vLen.status 'truncated'
Assert-Eq 'length: message cites reason' ($vLen.message -match 'reason=length') $true

# 9) no step_finish at all -> no-completion (signal absent)
$linesNoFin = @('{"type":"text","part":{"messageID":"m1","text":"so preambulo, stream cortou"}}')
$sig = Get-OpenCodeCompletionSignal -Events (ConvertFrom-OpenCodeStreamLines -Lines $linesNoFin)
Assert-Eq 'noFin: hasStepFinish'  $sig.hasStepFinish $false
Assert-Eq 'noFin: verdict no-completion' (Get-Verdict $linesNoFin).status 'no-completion'

# 10) step_finish present but WITHOUT a reason field -> no-completion (null reason = absent, no exception)
$linesNoReason = @(
    '{"type":"text","part":{"messageID":"m1","text":"texto"}}',
    '{"type":"step_finish","part":{}}'
)
$sig = Get-OpenCodeCompletionSignal -Events (ConvertFrom-OpenCodeStreamLines -Lines $linesNoReason)
Assert-Eq 'noReason: hasStepFinish' $sig.hasStepFinish $true
Assert-Eq 'noReason: empty reason'  $sig.reason ''
Assert-Eq 'noReason: verdict no-completion' (Get-Verdict $linesNoReason).status 'no-completion'

# 11) reason=stop but empty final text -> empty
$linesEmpty = @('{"type":"step_finish","part":{"reason":"stop"}}')
Assert-Eq 'empty: verdict empty' (Get-Verdict $linesEmpty).status 'empty'

# 12) Regression of Finding D: preamble present (finalText NOT empty) + reason=tool-calls
#     -> truncated; the adapter must NOT return the preamble as the response.
$linesPreamble = @(
    '{"type":"text","part":{"messageID":"m1","text":"deixa eu ler os arquivos primeiro..."}}',
    '{"type":"step_finish","part":{"reason":"tool-calls"}}'
)
$evPre = ConvertFrom-OpenCodeStreamLines -Lines $linesPreamble
$finalPre = Get-OpenCodeFinalText -TextParts (Get-OpenCodeTextParts -Events $evPre)
Assert-Eq 'preamble: finalText non-empty' ([string]::IsNullOrWhiteSpace($finalPre)) $false
Assert-Eq 'preamble: verdict truncated (does not return the preamble)' (Get-Verdict $linesPreamble).status 'truncated'

# 13) "The last step_finish governs": multiple step_finish, the LAST one without a reason -> no-completion.
#     Contract: always overwrite lastFinishReason,
#     never inherit the reason from an earlier step_finish). Finding from the diff review (Codex).
$linesMultiFin = @(
    '{"type":"text","part":{"messageID":"m1","text":"parcial"}}',
    '{"type":"step_finish","part":{"reason":"stop"}}',
    '{"type":"text","part":{"messageID":"m2","text":"mais texto"}}',
    '{"type":"step_finish","part":{}}'
)
$sig = Get-OpenCodeCompletionSignal -Events (ConvertFrom-OpenCodeStreamLines -Lines $linesMultiFin)
Assert-Eq 'multiFin: last step_finish governs (empty reason)' $sig.reason ''
Assert-Eq 'multiFin: verdict no-completion (does not inherit the earlier stop)' (Get-Verdict $linesMultiFin).status 'no-completion'

# 14) Parametric: any reason != stop -> truncated (opencode's open vocabulary).
foreach ($r in @('length', 'tool-calls', 'content_filter', 'unknown', 'max_tokens')) {
    $linesR = @(
        '{"type":"text","part":{"messageID":"m1","text":"preambulo"}}',
        ('{"type":"step_finish","part":{"reason":"' + $r + '"}}')
    )
    Assert-Eq ("param: reason=$r -> truncated") (Get-Verdict $linesR).status 'truncated'
}

# 15) Precedence of the explicit error (G1, claude-opus): even with reason=stop + text (verdict ok),
#     Get-OpenCodeStreamErrorMessage detects the error -> the caller (Invoke-OpenCode) throws
#     it BEFORE consulting the verdict. The test fixes the detection and the non-interference.
$linesErrFirst = @(
    '{"type":"text","part":{"messageID":"m1","text":"ok"}}',
    '{"type":"step_finish","part":{"reason":"stop"}}',
    '{"type":"error","error":{"data":{"message":"boom no agente"}}}'
)
$evErrFirst = ConvertFrom-OpenCodeStreamLines -Lines $linesErrFirst
Assert-Eq 'errFirst: error detected' (Get-OpenCodeStreamErrorMessage -Events $evErrFirst) 'boom no agente'
Assert-Eq 'errFirst: isolated verdict would be ok (error handled separately by the caller)' (Get-Verdict $linesErrFirst).status 'ok'

# --- usage-limit/rate-limit block texts and limit resolution ---
$fixedUsage = Format-OpenCodeLimitBlock -Kind 'usage-limit' -Message ''
$fixedRate = Format-OpenCodeLimitBlock -Kind 'rate-limit' -Message ''
Assert-Eq 'format usage literal' $fixedUsage 'BLOCK: opencode reached the provider usage limit. This is NOT a technical timeout; wait for the usage cycle to reset (usage quota).'
Assert-Eq 'format rate literal' $fixedRate 'BLOCK: opencode reached the provider rate limit. Do not retry immediately (rate limit / too many requests).'
Assert-Eq 'format rate without 429 in the fixed part' ($fixedRate -notmatch '429') $true
$stream429 = @(Get-OpenCodeStreamErrorCandidates -Lines @('{"type":"error","error":{"data":{"message":"statusCode\":429"}}}'))
$logUsage = @([pscustomobject]@{ path = 'C:\z.log'; lineIndex = 0; raw = 'weekly usage limit'; lineTimestampUtc = $null; lastWriteTimeUtc = [datetime]::UtcNow; level = 'ERROR' })
$kindGlobal = Resolve-OpenCodeProviderLimitHit -StreamErrors $stream429 -StderrText '' -LogLines $logUsage
Assert-Eq 'global usage kind beats stream 429' $kindGlobal.kind 'usage-limit'

foreach ($rxCase in @(
    @{ t = 'insufficient balance'; k = 'usage-limit' },
    @{ t = 'insufficient coding plan balance'; k = 'usage-limit' },
    @{ t = 'credits exhausted'; k = 'usage-limit' },
    @{ t = 'saldo insuficiente'; k = 'usage-limit' },
    @{ t = 'sem quota'; k = 'usage-limit' }
)) {
    Assert-Eq ("regex $($rxCase.t)") (Get-OpenCodeProviderLimitKindFromText -Text $rxCase.t) $rxCase.k
}
Assert-Eq 'isolated quota miss' ($null -eq (Get-OpenCodeProviderLimitKindFromText -Text 'quota')) $true
Assert-Eq 'retries exhausted miss' ($null -eq (Get-OpenCodeProviderLimitKindFromText -Text 'retries exhausted')) $true
Assert-Eq 'insufficient permissions miss' ($null -eq (Get-OpenCodeProviderLimitKindFromText -Text 'insufficient permissions')) $true
Assert-Eq 'rate_limit' (Get-OpenCodeProviderLimitKindFromText -Text 'rate_limit') 'rate-limit'
Assert-Eq '1402 is not structural 402' ($null -eq (Get-OpenCodeProviderLimitKindFromText -Text '{"n":1402}')) $true
Assert-Eq 'USAGE LIMIT case' (Get-OpenCodeProviderLimitKindFromText -Text 'USAGE LIMIT') 'usage-limit'

# No default agent: the opencode adapters no longer load the reviewer-ro guard nor
# assign 'reviewer-ro' as -Agent when the caller does not supply an explicit one.
foreach ($adapterName in @('Invoke-OpenCode.ps1')) {
    $adapterSrc = Get-Content -LiteralPath (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') $adapterName) -Raw -Encoding utf8
    Assert-Eq "$adapterName without dot-sourcing the reviewer-ro guard" ($adapterSrc -match 'OpenCodeReviewerRoGuard') $false
    Assert-Eq "$adapterName without a default -Agent reviewer-ro" ($adapterSrc -match "Agent\s*=\s*'reviewer-ro'") $false
}

$dispatchPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-LlmDelegatePanelDispatch.ps1'
$patternRaw = Get-Content -LiteralPath $dispatchPath -Raw -Encoding utf8
$mPat = [regex]::Match($patternRaw, '\$quotaFailurePattern = ''([^'']+)''')
if (-not $mPat.Success) { throw 'FAIL: $quotaFailurePattern assignment not found' }
$patternText = $mPat.Groups[1].Value
Assert-Eq 'quota pattern matches fixed usage' ($fixedUsage -match $patternText) $true
Assert-Eq 'quota pattern matches fixed rate' ($fixedRate -match $patternText) $true

# Default provider log folder without XDG_DATA_HOME: Windows keeps %USERPROFILE%\.local/share;
# Linux and macOS have no USERPROFILE and use HOME.
$savedLogEnv = @{}
foreach ($name in @('XDG_DATA_HOME', 'USERPROFILE', 'HOME')) { $savedLogEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    [Environment]::SetEnvironmentVariable('XDG_DATA_HOME', $null)
    if ($IsWindows) {
        $expectedLogDir = Join-Path (Join-Path $env:USERPROFILE '.local/share') 'opencode/log'
        Assert-Eq 'log dir: Windows uses USERPROFILE without XDG_DATA_HOME' (Get-OpenCodeDefaultProviderLogDir) $expectedLogDir
        Write-Host 'SKIP: off-Windows provider log folder case (Windows host)' -ForegroundColor Yellow
    } else {
        [Environment]::SetEnvironmentVariable('USERPROFILE', $null)
        $fakeHome = Join-Path ([System.IO.Path]::GetTempPath()) ('oc-home-' + [guid]::NewGuid().ToString('N'))
        $env:HOME = $fakeHome
        $gotLogDir = $null
        $logDirErr = ''
        try { $gotLogDir = Get-OpenCodeDefaultProviderLogDir } catch { $logDirErr = $_.Exception.Message }
        $expectedLogDir = Join-Path (Join-Path $fakeHome '.local/share') 'opencode/log'
        Assert-Eq "log dir: off Windows uses HOME without XDG_DATA_HOME or USERPROFILE ($logDirErr)" $gotLogDir $expectedLogDir
    }
} finally {
    foreach ($name in $savedLogEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $savedLogEnv[$name]) }
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-OpenCodeStreamSupportSelfTest.ps1" }
Write-Host 'OK: Test-OpenCodeStreamSupportSelfTest.ps1' -ForegroundColor Cyan
