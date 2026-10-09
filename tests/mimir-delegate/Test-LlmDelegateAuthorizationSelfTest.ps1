#requires -Version 7.4
<#
.SYNOPSIS
    Contract self-test for Resolve-LlmDelegateAuthorization.ps1 (mimir-delegate skill).
.DESCRIPTION
    Validates the allow/ask/deny decision table combining payload sensitivity, model
    locality and per-KB policy, with synthetic config and policy (no opencode installed,
    no network). Deterministic.
    Success sentinel: OK: Test-LlmDelegateAuthorizationSelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-LlmDelegateAuthorization.ps1'
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "BLOCK: target not found: $target" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ocauth-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$cfg = Join-Path $tmp 'opencode.json'
@'
{
  "provider": {
    "ollama":   { "options": { "baseURL": "http://127.0.0.1:11434/v1" } },
    "remote-x": { "options": { "baseURL": "https://api.example.com/v1" } }
  }
}
'@ | Set-Content -LiteralPath $cfg -Encoding utf8
$pol = Join-Path $tmp 'llm-delegation-policy.json'
@'
{
  "schemaVersion": 1,
  "defaultExternal": "ask",
  "models": {
            "openai/gpt-5.4": "allow-external",
            "openai/*": "allow-external",
            "anthropic/claude-opus-4-8": "allow-external",
            "anthropic/claude-deny-test": "deny-external",
            "github-copilot/*": "allow-external",
            "google/gemini-deny-test": "deny-external",
            "google/*": "allow-external",
            "antigravity/gemini-deny-test": "deny-external",
            "antigravity/*": "allow-external",
            "remote-x/*": "deny-external"
  }
}
'@ | Set-Content -LiteralPath $pol -Encoding utf8

# Synthetic config.toml for the codex backend cases (default falls back to openai/external).
$cfgToml = Join-Path $tmp 'config.toml'
@'
model = "gpt-5.5"
'@ | Set-Content -LiteralPath $cfgToml -Encoding utf8

$fail = 0
function Assert-Verdict {
    param([string]$Model, [string]$Sensitivity, [string]$Expected, [switch]$WithPolicy, [string]$Note, [string]$Backend = 'opencode')
    $cfgForBackend = if ($Backend -eq 'codex') { $cfgToml } else { $cfg }
    $callArgs = @{ Model = $Model; PayloadSensitivity = $Sensitivity; ConfigPath = $cfgForBackend; Backend = $Backend }
    if ($WithPolicy) { $callArgs['PolicyPath'] = $pol }
    $out = & $target @callArgs | ConvertFrom-Json
    $got = [string]$out.verdict
    $tagPol = if ($WithPolicy) { ' +pol' } else { '' }
    $tagBk = if ($Backend -ne 'opencode') { " $Backend" } else { '' }
    $label = "{0} [{1}]{2}{3}" -f $Model, $Sensitivity, $tagPol, $tagBk
    if ($got -eq $Expected) {
        Write-Host ("PASS  {0,-40} -> {1}  ({2})" -f $label, $got, $Note) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0,-40} -> {1} (expected {2})  ({3})" -f $label, $got, $Expected, $Note) -ForegroundColor Red
    }
}

function Assert-Equal {
    param([string]$Label, $Got, $Expected)
    if ([string]$Got -eq [string]$Expected) {
        Write-Host ("PASS  {0}" -f $Label) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0} -> '{1}' (expected '{2}')" -f $Label, $Got, $Expected) -ForegroundColor Red
    }
}

try {
    Assert-Verdict -Model 'remote-x/foo'   -Sensitivity 'public'       -Expected 'allow' -WithPolicy -Note 'public payload'
    Assert-Verdict -Model 'ollama/foo'     -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'local: data does not leave'
    Assert-Verdict -Model 'openai/gpt-5.4' -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'exact allow-external policy'
    Assert-Verdict -Model 'remote-x/zzz'   -Sensitivity 'kb-sensitive' -Expected 'deny'  -WithPolicy -Note 'remote-x/* wildcard deny'
    Assert-Verdict -Model 'opencode-go/x'  -Sensitivity 'kb-sensitive' -Expected 'ask'   -WithPolicy -Note 'not listed -> defaultExternal ask'
    Assert-Verdict -Model 'remote-x/foo'   -Sensitivity 'kb-sensitive' -Expected 'ask'   -Note 'external without policy file -> ask'

    # Backend codex: the DESTINATION key (openai/...) matches the SAME policy rule that
    # opencode would use; the adapter is not part of the key. This proves the design 'openai/' != 'codex/'.
    Assert-Verdict -Model 'gpt-5.5' -Backend codex -Sensitivity 'public'       -Expected 'allow' -WithPolicy -Note 'codex public -> allow'
    Assert-Verdict -Model 'gpt-5.4' -Backend codex -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'codex matches exact openai/gpt-5.4 (same rule as opencode)'
    Assert-Verdict -Model 'gpt-5.5' -Backend codex -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'codex matches openai/* wildcard (unification by destination)'
    Assert-Verdict -Model 'gpt-5.5' -Backend codex -Sensitivity 'kb-sensitive' -Expected 'ask'   -Note 'codex external without policy -> ask'
    Assert-Verdict -Model ''        -Backend codex -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'codex without -Model derives the model from config and matches openai/*'

    # Backend claude-code: Anthropic DESTINATION key, never claude-code/*.
    Assert-Verdict -Model 'claude-opus-4-8' -Backend claude-code -Sensitivity 'public'       -Expected 'allow' -WithPolicy -Note 'Claude Code public -> allow'
    Assert-Verdict -Model 'claude-opus-4-8' -Backend claude-code -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'Claude Code matches exact anthropic/claude-opus-4-8'
    Assert-Verdict -Model 'opus'             -Backend claude-code -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'opus alias normalized to Opus 4.8'
    Assert-Verdict -Model 'claude-deny-test' -Backend claude-code -Sensitivity 'kb-sensitive' -Expected 'deny'  -WithPolicy -Note 'Claude Code honors exact deny-external'
    Assert-Verdict -Model 'claude-opus-4-8' -Backend claude-code -Sensitivity 'kb-sensitive' -Expected 'ask'   -Note 'Claude Code external without policy -> ask'
    Assert-Verdict -Model ''                 -Backend claude-code -Sensitivity 'kb-sensitive' -Expected 'ask'   -Note 'Claude Code without -Model: unknown -> ask (fail-safe, not a binding error)'
    Assert-Verdict -Model ''                 -Backend claude-code -Sensitivity 'public'       -Expected 'allow' -Note 'Claude Code without -Model: public payload -> allow'
    Assert-Verdict -Model ''                 -Backend claude-code -Sensitivity 'kb-sensitive' -Expected 'ask'   -WithPolicy -Note 'Claude Code without -Model + policy present: ask with no exception (regression of the empty-name crash in policy lookup)'

    # Backends copilot/gemini: also match by DESTINATION key, not by generic adapter.
    Assert-Verdict -Model 'gpt-5-mini' -Backend copilot -Sensitivity 'public'       -Expected 'allow' -WithPolicy -Note 'Copilot public -> allow'
    Assert-Verdict -Model 'gpt-5-mini' -Backend copilot -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'Copilot matches github-copilot/*'
    Assert-Verdict -Model 'gpt-5-mini' -Backend copilot -Sensitivity 'kb-sensitive' -Expected 'ask'   -Note 'Copilot external without policy -> ask'
    Assert-Verdict -Model 'gemini-3-flash-preview' -Backend gemini -Sensitivity 'public'       -Expected 'allow' -WithPolicy -Note 'Gemini public -> allow'
    Assert-Verdict -Model 'gemini-deny-test'        -Backend gemini -Sensitivity 'kb-sensitive' -Expected 'deny'  -WithPolicy -Note 'Gemini honors exact deny-external'
    Assert-Verdict -Model 'gemini-3-flash-preview' -Backend gemini -Sensitivity 'kb-sensitive' -Expected 'ask'   -Note 'Gemini external without policy -> ask'
    Assert-Verdict -Model 'gemini-3.6-flash-high' -Backend antigravity -Sensitivity 'public'       -Expected 'allow' -WithPolicy -Note 'Antigravity public -> allow'
    Assert-Verdict -Model 'gemini-deny-test'        -Backend antigravity -Sensitivity 'kb-sensitive' -Expected 'deny'  -WithPolicy -Note 'Antigravity honors exact deny-external'
    Assert-Verdict -Model 'gemini-3.6-flash-high' -Backend antigravity -Sensitivity 'kb-sensitive' -Expected 'allow' -WithPolicy -Note 'Antigravity matches antigravity/*'
    Assert-Verdict -Model 'gemini-3.6-flash-high' -Backend antigravity -Sensitivity 'kb-sensitive' -Expected 'ask'   -Note 'Antigravity external without policy -> ask'

    # B2: policy file discovery via -KbWorkspaceRoot (only llm-delegation-policy.json counts).
    # $tmp contains llm-delegation-policy.json.
    $oNew = & $target -Model 'openai/gpt-5.4' -PayloadSensitivity 'kb-sensitive' -ConfigPath $cfg -KbWorkspaceRoot $tmp | ConvertFrom-Json
    Assert-Equal 'KbWorkspaceRoot finds the policy -> allow' $oNew.verdict 'allow'
    Assert-Equal 'KbWorkspaceRoot reports the policy file name' $oNew.policyFileName 'llm-delegation-policy.json'
    Assert-Equal 'output carries no policyNameStatus' ([bool]$oNew.PSObject.Properties['policyNameStatus']) $false

    # Any other file name at the root is not a policy file.
    $kbOther = Join-Path $tmp 'kb-other'
    New-Item -ItemType Directory -Path $kbOther -Force | Out-Null
    Copy-Item -LiteralPath $pol -Destination (Join-Path $kbOther 'delegation-policy.json')
    $oOther = & $target -Model 'openai/gpt-5.4' -PayloadSensitivity 'kb-sensitive' -ConfigPath $cfg -KbWorkspaceRoot $kbOther | ConvertFrom-Json
    Assert-Equal 'KbWorkspaceRoot ignores other file names -> ask' $oOther.verdict 'ask'

    $kbNone = Join-Path $tmp 'kb-none'
    New-Item -ItemType Directory -Path $kbNone -Force | Out-Null
    $oNone = & $target -Model 'openai/gpt-5.4' -PayloadSensitivity 'kb-sensitive' -ConfigPath $cfg -KbWorkspaceRoot $kbNone | ConvertFrom-Json
    Assert-Equal 'KbWorkspaceRoot without policy -> ask' $oNone.verdict 'ask'
    Assert-Equal 'KbWorkspaceRoot without policy -> no file name' $oNone.policyFileName $null

    # A -KbWorkspaceRoot that is not an existing directory is refused.
    $refused = $false
    try {
        & $target -Model 'openai/gpt-5.4' -PayloadSensitivity 'kb-sensitive' -ConfigPath $cfg -KbWorkspaceRoot (Join-Path $tmp 'missing') | Out-Null
    } catch {
        $refused = ($_.Exception.Message -like 'BLOCK:*')
    }
    Assert-Equal 'missing KbWorkspaceRoot -> BLOCK' $refused $true

    # An explicit -PolicyPath takes precedence over -KbWorkspaceRoot.
    $oPrec = & $target -Model 'openai/gpt-5.4' -PayloadSensitivity 'kb-sensitive' -ConfigPath $cfg -PolicyPath $pol -KbWorkspaceRoot $kbNone | ConvertFrom-Json
    Assert-Equal 'explicit PolicyPath takes precedence over KbWorkspaceRoot' $oPrec.verdict 'allow'
} finally {
    Get-ChildItem -LiteralPath $tmp -File -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-LlmDelegateAuthorizationSelfTest.ps1" }
Write-Host 'OK: Test-LlmDelegateAuthorizationSelfTest.ps1' -ForegroundColor Cyan
