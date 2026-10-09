#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the ClaudeCodeCliSupport.ps1 functions and of the adapters' argument assembly.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'ClaudeCodeCliSupport.ps1')
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

Assert-Equal 'parse version' (ConvertFrom-ClaudeCodeVersionText '2.1.118 (Claude Code)') ([version]'2.1.118')
Assert-Equal 'invalid parse -> null' (ConvertFrom-ClaudeCodeVersionText 'no version') $null

$helpOk = @'
--model
--print
--output-format
--no-session-persistence
--permission-mode
--tools
'@
Assert-Equal 'help with required flags' (Test-ClaudeCodeHelpSupportsContract $helpOk) $true
Assert-Equal 'incomplete help' (Test-ClaudeCodeHelpSupportsContract '--model') $false

$err = Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText 'Error: model not available'
Assert-Equal 'extracts simple error' $err 'Error: model not available'
$trustErr = 'Claude Code refused to run because this workspace is not trusted. Mark this workspace as trusted to continue.'
Assert-Equal 'detects untrusted workspace' (Test-ClaudeCodeWorkspaceNotTrusted -Text $trustErr) $true
Assert-Equal 'workspace not trusted error becomes canonical message' ((Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText $trustErr) -match 'workspace-not-trusted') $true
Assert-Equal 'workspace error preserves raw stderr' ((Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText $trustErr) -match [regex]::Escape($trustErr)) $true
Assert-Equal 'workspace error asks for evidence package' ((Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText $trustErr) -match 'claude --version') $true
Assert-Equal 'informational workspace line does not become a generic error' (Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText 'Workspace cache atualizado.') $null
Assert-Equal 'cannot does not match as not' (Test-ClaudeCodeWorkspaceNotTrusted -Text 'Workspace initialization cannot continue: trusted certificate missing.') $false
Assert-Equal 'stdout text does not classify as workspace not trusted' (Get-ClaudeCodeErrorMessage -StdoutText $trustErr -StderrText '') $null

# --- Regression anchored in empirical evidence (2026-07-25, claude 2.1.215) ---------------------
# REAL stderr from running in an untrusted workspace. Measured across four trials: it appears identical
# (same size, same text) both on exit 1 and on exit 0 with a valid response. Therefore it is not
# failure evidence and must not trigger the untrusted-workspace detector.
$noiseStderr = @'
Ignoring 3 permissions.allow entries from .claude/settings.json: this workspace has not been trusted. Run Claude Code interactively here once and accept the trust dialog, or set projects["C:/tmp/probe"].hasTrustDialogAccepted: true in C:\Users\Fulano\.claude.json.
Permission allow rule (C:\Users\Fulano\.claude\settings.json): Glob(C:/Dev/**) is not matched by file permission checks - only Read(path) rules are. Use Read(C:/Dev/**) instead (Read rules cover all file-reading tools).
Permission allow rule (C:\Users\Fulano\.claude\settings.json): Write(C:/Dev/**) is not matched by file permission checks - only Edit(path) rules are. Use Edit(C:/Dev/**) instead (Edit rules cover all file-editing tools).
'@

Assert-Equal 'environment warning is not a workspace refusal' (Test-ClaudeCodeWorkspaceNotTrusted -Text $noiseStderr) $false
Assert-Equal 'environment noise is removed entirely' (Remove-ClaudeCodeEnvironmentNoise -Text $noiseStderr) ''
# Trial R4: exit 0, valid response, warning present -> no error should be reported.
Assert-Equal 'successful run with warning does not become an error' (Get-ClaudeCodeErrorMessage -StdoutText 'OK' -StderrText $noiseStderr) $null
# Trial R1: exit 1 from turn exhaustion, with the same warning in stderr.
$maxTurnsMsg = Get-ClaudeCodeErrorMessage -StdoutText 'Error: Reached max turns (1)' -StderrText $noiseStderr
Assert-Equal 'real failure becomes canonical code max-turns-exhausted' ($maxTurnsMsg -match 'max-turns-exhausted') $true
Assert-Equal 'real failure is NOT labeled as workspace-not-trusted' ($maxTurnsMsg -match 'workspace-not-trusted') $false
Assert-Equal 'max turns message preserves the evidence' ($maxTurnsMsg -match [regex]::Escape('Error: Reached max turns (1)')) $true
Assert-Equal 'max turns message does not repeat environment noise' ($maxTurnsMsg -match 'permissions\.allow entries') $false
Assert-Equal 'isolated max turns detector' (Test-ClaudeCodeMaxTurnsExhausted -Text 'Error: Reached max turns (1)') $true
Assert-Equal 'max turns detector does not match arbitrary text' (Test-ClaudeCodeMaxTurnsExhausted -Text 'Error: model not available') $false
# Protection against a genuine refusal stays active, even alongside the noise.
$trustPlusNoise = $noiseStderr + "`n" + $trustErr
Assert-Equal 'genuine refusal still detected under noise' (Test-ClaudeCodeWorkspaceNotTrusted -Text $trustPlusNoise) $true

# --- Deny noise filtering (2026-08-31: Write vs Edit warning appears as a deny rule) -----------
$denyNoise = @'
Ignoring 2 permissions.deny entries from .claude/settings.json: this workspace has not been trusted.
Permission deny rule (C:\Users\Fulano\.claude\settings.json): Write(C:/Dev/**) is not matched by file permission checks - only Edit(path) rules are. Use Edit(C:/Dev/**) instead (Edit rules cover all file-editing tools).
'@
Assert-Equal 'deny noise is removed entirely' (Remove-ClaudeCodeEnvironmentNoise -Text $denyNoise) ''
Assert-Equal 'deny noise does not become an error' (Get-ClaudeCodeErrorMessage -StdoutText 'OK' -StderrText $denyNoise) $null

# Mixed stderr: deny noise + real error -> real error preserved, noise removed
$mixedDenyErr = $denyNoise + "`nError: model not available"
$mixedMsg = Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText $mixedDenyErr
Assert-Equal 'mixed deny+error stderr preserves the real error' ($mixedMsg -match 'model not available') $true
Assert-Equal 'mixed deny+error stderr removes the noise' ($mixedMsg -match '(?i)permission deny rule') $false

# --- Symmetric spend limit extraction (2026-08-31: stdout and stderr) ----------------------------
$spendLimitStdout = "You've hit your monthly spend limit -- raise it at claude.ai/settings/usage."
$spendFromStdout = Get-ClaudeCodeErrorMessage -StdoutText $spendLimitStdout -StderrText $denyNoise
Assert-Equal 'spend limit in stdout with noise in stderr is extracted' ($spendFromStdout -match '(?i)spend limit') $true
Assert-Equal 'spend limit URL preserved' ($spendFromStdout -match 'claude\.ai/settings/usage') $true

$spendFromStderr = Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText $spendLimitStdout
Assert-Equal 'spend limit in stderr with empty stdout is extracted' ($spendFromStderr -match '(?i)spend limit') $true

$sessionLimitStdout = "You've hit your session limit · resets 9:40pm (America/Sao_Paulo)"
$sessionFromStdout = Get-ClaudeCodeErrorMessage -StdoutText $sessionLimitStdout -StderrText $denyNoise
Assert-Equal 'session limit in stdout measured on 2026-09-01 is extracted' ($sessionFromStdout -match '(?i)session limit') $true

# --- Pure noise: no classifiable error --------------------------------------------------
$pureNoiseResult = Get-ClaudeCodeErrorMessage -StdoutText '' -StderrText $noiseStderr
Assert-Equal 'pure noise returns null' $pureNoiseResult $null

# --- Exit 0 + noise + valid response: success intact -------------------------------------
Assert-Equal 'exit 0 with noise and a response does not become an error' (Get-ClaudeCodeErrorMessage -StdoutText 'resposta valida' -StderrText ($denyNoise + "`n" + $noiseStderr)) $null

# --- Stream events: error and text extraction ------------------------------------------------
# Measured on 2026-07-25 (claude 2.1.220): the outcome of `--output-format stream-json` does NOT come
# in a `type=error` event; the last line is `type=result` with `subtype` and `is_error`.
Assert-Equal 'isolated subtype error_max_turns matches the detector' (Test-ClaudeCodeMaxTurnsExhausted -Text 'subtype=error_max_turns') $true

$evSuccess = '{"type":"result","subtype":"success","is_error":false,"result":"OK"}' | ConvertFrom-Json
Assert-Equal 'success result event does not become an error' (Get-ClaudeCodeStreamEventErrorText -StreamEvent $evSuccess) ''
$evAssistant = '{"type":"assistant","message":{"content":[{"text":"parcial"}]}}' | ConvertFrom-Json
Assert-Equal 'assistant event does not become an error' (Get-ClaudeCodeStreamEventErrorText -StreamEvent $evAssistant) ''
$evMaxTurns = '{"type":"result","subtype":"error_max_turns","is_error":true,"result":"Error: Reached max turns (1)"}' | ConvertFrom-Json
Assert-Equal 'result event with is_error carries subtype and text' (Get-ClaudeCodeStreamEventErrorText -StreamEvent $evMaxTurns) 'subtype=error_max_turns: Error: Reached max turns (1)'
# REAL turn-exhaustion event, measured on 2026-07-25 (claude 2.1.220, `--max-turns 1`):
# there is no `result` field — the readable message lives in `errors[]`, with `terminal_reason` alongside it.
# Without reading those fields, the preserved evidence would be only `subtype=error_max_turns`.
$evMaxTurnsReal = '{"is_error":true,"terminal_reason":"max_turns","subtype":"error_max_turns","errors":["Reached maximum number of turns (1)"],"type":"result"}' | ConvertFrom-Json
$realText = Get-ClaudeCodeStreamEventErrorText -StreamEvent $evMaxTurnsReal
Assert-Equal 'real max turns event preserves the errors[] message' ($realText -match 'Reached maximum number of turns \(1\)') $true
Assert-Equal 'real max turns event preserves terminal_reason' ($realText -match 'terminal_reason=max_turns') $true
Assert-Equal 'real max turns event still matches the detector' (Test-ClaudeCodeMaxTurnsExhausted -Text $realText) $true
# The real errors[] text does NOT match `reached max turns`; without the alternation, detection would
# depend solely on the subtype being prefixed in the assembled evidence.
Assert-Equal 'real errors[] text matches the detector on its own' (Test-ClaudeCodeMaxTurnsExhausted -Text 'Reached maximum number of turns (1)') $true
# The canonical message is reused on the failureAfterText path, where text DID exist before the cutoff:
# it cannot claim that the call ended without producing a response.
$maxTurnsCanonical = New-ClaudeCodeMaxTurnsExhaustedEvidenceMessage -EvidenceText 'subtype=error_max_turns'
Assert-Equal 'canonical message does not claim absence of a response' ($maxTurnsCanonical -match 'without producing a response') $false
Assert-Equal 'canonical message admits partial text' ($maxTurnsCanonical -match 'partial text') $true
$evTypeError = '{"type":"error","message":"boom"}' | ConvertFrom-Json
Assert-Equal 'type=error event is still captured' ((Get-ClaudeCodeStreamEventErrorText -StreamEvent $evTypeError) -match 'boom') $true
Assert-Equal 'null event does not become an error' (Get-ClaudeCodeStreamEventErrorText -StreamEvent $null) ''

$evDeltaA = '{"type":"content_block_delta","delta":{"type":"text_delta","text":"A"}}' | ConvertFrom-Json
$evDeltaB = '{"type":"content_block_delta","delta":{"type":"text_delta","text":"B"}}' | ConvertFrom-Json
$evResultWithText = '{"type":"result","subtype":"success","is_error":false,"result":"NAO_E_VEREDITO"}' | ConvertFrom-Json
Assert-Equal 'content_block_delta extracts incremental text' (Get-ClaudeCodeStreamEventText -StreamEvent $evDeltaA) 'A'
Assert-Equal 'assistant content is the textual fallback' (Get-ClaudeCodeStreamAcceptedTextFromEvents -StreamEvents @($evAssistant)) 'parcial'
Assert-Equal 'deltas take precedence over assistant to avoid duplication' (Get-ClaudeCodeStreamAcceptedTextFromEvents -StreamEvents @($evAssistant, $evDeltaA, $evDeltaB)) 'AB'
Assert-Equal 'result.result does not become accepted text' (Get-ClaudeCodeStreamAcceptedTextFromEvents -StreamEvents @($evResultWithText)) ''

$rateLimitRejected = '{"type":"rate_limit_event","status":"rejected","rateLimitType":"weekly","reportedLimitScope":"subscription","resetsAt":1893456000}' | ConvertFrom-Json
$quotaEvidence = Get-ClaudeCodeStreamQuotaEvidence -StreamEvents @($rateLimitRejected)
Assert-Equal 'quota: rate_limit_event rejected detected' $quotaEvidence.isQuota $true
Assert-Equal 'quota: rateLimitType preserved' $quotaEvidence.rateLimitType 'weekly'
Assert-Equal 'quota: resetsAt unix converted to UTC' $quotaEvidence.resetsAtUtc '2030-01-01T00:00:00Z'
$result429 = '{"type":"result","is_error":true,"terminal_reason":"api_error","api_error_status":429,"result":"rate limit"}' | ConvertFrom-Json
$quota429 = Get-ClaudeCodeStreamQuotaEvidence -StreamEvents @($result429)
Assert-Equal 'quota: result api_error_status 429 detected' $quota429.isQuota $true
Assert-Equal 'quota: api_error_status preserved' $quota429.apiErrorStatus '429'

function New-FakeClaudeCodeExe {
    param([string]$TempRoot)

    $argsFile = Join-Path $TempRoot 'args.txt'
    # The default branch appends the arguments as one line, rendering an empty argument as ""
    # and quoting an argument that contains whitespace, the way the command line spelled them.
    $body = @'
if ($args.Count -ge 1 -and $args[0] -eq '--version') { '2.1.118'; exit 0 }
if ($args.Count -ge 1 -and $args[0] -eq '--help') { '--model --print --output-format --no-session-persistence --permission-mode --tools'; exit 0 }
if ($env:FAKE_CLAUDE_UNTRUSTED -eq '1') {
    [Console]::Error.WriteLine('Claude Code refused to run because this workspace is not trusted. Mark this workspace as trusted to continue.')
    exit 1
}
if ($env:FAKE_CLAUDE_SPEND_LIMIT -eq '1') {
    [Console]::Error.WriteLine('Permission allow rule: Write vs Edit noise')
    'You have hit your monthly spend limit -- raise it at claude.ai/settings/usage.'
    exit 1
}
if ($env:FAKE_CLAUDE_NOISE_ONLY -eq '1') {
    [Console]::Error.WriteLine('Permission deny rule (settings.json): Write vs Edit noise')
    [Console]::Error.WriteLine('Ignoring 1 permissions.deny entries from .claude/settings.json')
    exit 1
}
if ($env:FAKE_CLAUDE_UNCLASSIFIED -eq '1') {
    'unclassified output line 1'
    'unclassified output line 2'
    [Console]::Error.WriteLine('some warning')
    exit 1
}
$argsLine = @($args | ForEach-Object { if ($_ -eq '') { '""' } elseif ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
Add-Content -LiteralPath '__ARGS_FILE__' -Value $argsLine -Encoding utf8
'OK fake claude'
exit 0
'@
    $fakeExe = New-FakeCli -Directory $TempRoot -Name 'claude' -PwshBody $body.Replace('__ARGS_FILE__', $argsFile.Replace("'", "''"))
    return [pscustomobject]@{ Exe = $fakeExe; ArgsFile = $argsFile }
}

function Read-LastFakeClaudeArgs {
    param([string]$Path)
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    if ($lines.Count -eq 0) { return '' }
    return [string]$lines[-1]
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-code-cli-support-selftest-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $fake = New-FakeClaudeCodeExe -TempRoot $tmp

    & (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-ClaudeCode.ps1') 'adapter default tools' -ClaudeExe $fake.Exe -TimeoutSec 30 | Out-Null
    $invokeDefaultArgs = Read-LastFakeClaudeArgs -Path $fake.ArgsFile
    Assert-Equal 'invoke default passes --tools' ($invokeDefaultArgs -match '--tools Read,Glob,Grep') $true
    # CLI 2.1.215 no longer advertises --max-turns and the adapters stopped trying to negotiate it.
    Assert-Equal 'invoke does not pass --max-turns' ($invokeDefaultArgs -notmatch '--max-turns') $true

    & (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-ClaudeCode.ps1') 'adapter tools empty' -ClaudeExe $fake.Exe -Tools '' -TimeoutSec 30 | Out-Null
    $invokeEmptyArgs = Read-LastFakeClaudeArgs -Path $fake.ArgsFile
    # The CLI disables every tool with --tools "". Omitting the flag does the opposite: it opens up the
    # full default set. The empty value must arrive quoted, because Start-Process discards an empty
    # string from ArgumentList and --tools is variadic.
    Assert-Equal 'invoke with empty tools passes --tools ""' ($invokeEmptyArgs -match '--tools ""') $true

    # `--tools default` is the value the CLI documents to open up the full default set
    # (`claude --help`, 2.1.215). The adapter forwards it literally, with no special handling.
    & (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-ClaudeCode.ps1') 'adapter tools default' -ClaudeExe $fake.Exe -Tools 'default' -TimeoutSec 30 | Out-Null
    $invokeAllToolsArgs = Read-LastFakeClaudeArgs -Path $fake.ArgsFile
    Assert-Equal 'invoke with tools default passes --tools default' ($invokeAllToolsArgs -match '--tools default') $true

    $env:FAKE_CLAUDE_UNTRUSTED = '1'
    $threwTrust = $false
    $trustMsg = ''
    try { & (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-ClaudeCode.ps1') 'workspace not trusted' -ClaudeExe $fake.Exe -TimeoutSec 30 | Out-Null } catch { $threwTrust = $true; $trustMsg = [string]$_.Exception.Message }
    $env:FAKE_CLAUDE_UNTRUSTED = $null
    Assert-Equal 'invoke workspace not trusted blocks with canonical code' ($threwTrust -and $trustMsg -match 'workspace-not-trusted') $true

    # --- E2E: spend limit (2026-08-31) --------------------------------------------------------
    $env:FAKE_CLAUDE_SPEND_LIMIT = '1'
    $threwSpend = $false
    $spendMsg = ''
    try { & (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-ClaudeCode.ps1') 'spend limit' -ClaudeExe $fake.Exe -TimeoutSec 30 | Out-Null } catch { $threwSpend = $true; $spendMsg = [string]$_.Exception.Message }
    $env:FAKE_CLAUDE_SPEND_LIMIT = $null
    Assert-Equal 'invoke spend limit blocks' $threwSpend $true
    Assert-Equal 'invoke spend limit extracts message' ($spendMsg -match '(?i)spend limit') $true
    Assert-Equal 'invoke spend limit preserves URL' ($spendMsg -match 'claude\.ai/settings/usage') $true

    # --- E2E: noise only (2026-08-31) ---------------------------------------------------------
    $env:FAKE_CLAUDE_NOISE_ONLY = '1'
    $threwNoise = $false
    $noiseMsg = ''
    try { & (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-ClaudeCode.ps1') 'noise only' -ClaudeExe $fake.Exe -TimeoutSec 30 | Out-Null } catch { $threwNoise = $true; $noiseMsg = [string]$_.Exception.Message }
    $env:FAKE_CLAUDE_NOISE_ONLY = $null
    Assert-Equal 'invoke noise only blocks' $threwNoise $true
    Assert-Equal 'invoke noise only reports no response' ($noiseMsg -match 'no response') $true
    Assert-Equal 'invoke noise only does not dump the deny rule' ($noiseMsg -notmatch '(?i)permission (allow|deny) rule') $true
    Assert-Equal 'invoke noise only does not dump ignoring' ($noiseMsg -notmatch '(?i)ignoring \d+ permissions') $true

    # --- E2E: unclassified output (2026-08-31) ------------------------------------------------
    $env:FAKE_CLAUDE_UNCLASSIFIED = '1'
    $threwUnclass = $false
    $unclassMsg = ''
    try { & (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-ClaudeCode.ps1') 'unclassified' -ClaudeExe $fake.Exe -TimeoutSec 30 | Out-Null } catch { $threwUnclass = $true; $unclassMsg = [string]$_.Exception.Message }
    $env:FAKE_CLAUDE_UNCLASSIFIED = $null
    Assert-Equal 'invoke unclassified blocks' $threwUnclass $true
    Assert-Equal 'invoke unclassified has an stdout block' ($unclassMsg -match 'stdout:') $true
    Assert-Equal 'invoke unclassified preserves the content' ($unclassMsg -match 'unclassified output line') $true
    Assert-Equal 'invoke unclassified does not report no response' ($unclassMsg -notmatch 'no response') $true
} finally {
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-ClaudeCodeCliSupportSelfTest.ps1" }
Write-Host 'OK: Test-ClaudeCodeCliSupportSelfTest.ps1' -ForegroundColor Cyan
