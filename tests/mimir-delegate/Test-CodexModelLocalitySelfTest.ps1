#requires -Version 7.4
<#
.SYNOPSIS
    Contract self-test of Resolve-CodexModelLocality.ps1 (mimir-delegate skill).
.DESCRIPTION
    Creates a synthetic Codex config.toml and validates the local/external/unknown
    classification and the target key (canonicalModel) for several invocations, without
    depending on an installed Codex or on the network. Deterministic.
    Sentinela de sucesso: OK: Test-CodexModelLocalitySelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-CodexModelLocality.ps1'
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "BLOCK: target not found: $target" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cxloc-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$cfg = Join-Path $tmp 'config.toml'
@'
model = "gpt-5.5"

[model_providers.localx]
name = "Local X"
base_url = "http://127.0.0.1:11434/v1"

[model_providers.remotex]
name = "Remote X"
base_url = "https://api.example.com/v1"

[profiles.plocal]
model = "qwen2.5-coder:7b"
model_provider = "localx"

[profiles.premote]
model = "some-model"
model_provider = "remotex"
'@ | Set-Content -LiteralPath $cfg -Encoding utf8

$fail = 0
function Assert-Codex {
    param(
        [string]$Label, [string]$Expected, [string]$ExpectedKey,
        [hashtable]$CallArgs
    )
    $CallArgs['ConfigPath'] = $cfg
    $out = & $target @CallArgs | ConvertFrom-Json
    $got = [string]$out.locality
    $gotKey = [string]$out.canonicalModel
    $okLoc = ($got -eq $Expected)
    $okKey = ([string]::IsNullOrEmpty($ExpectedKey)) -or ($gotKey -eq $ExpectedKey)
    if ($okLoc -and $okKey) {
        Write-Host ("PASS  {0,-40} -> {1,-8} key={2}" -f $Label, $got, $gotKey) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0,-40} -> {1} key={2} (expected {3} / {4})" -f $Label, $got, $gotKey, $Expected, $ExpectedKey) -ForegroundColor Red
    }
}

try {
    Assert-Codex -Label 'config default'            -Expected 'external' -ExpectedKey 'openai/gpt-5.5'            -CallArgs @{}
    Assert-Codex -Label 'explicit gpt-5.5'         -Expected 'external' -ExpectedKey 'openai/gpt-5.5'            -CallArgs @{ Model = 'gpt-5.5' }
    Assert-Codex -Label 'prefixed openai/gpt-5.5'  -Expected 'external' -ExpectedKey 'openai/gpt-5.5'            -CallArgs @{ Model = 'openai/gpt-5.5' }
    Assert-Codex -Label 'oss ollama'               -Expected 'local'    -ExpectedKey 'ollama/qwen2.5-coder:7b'   -CallArgs @{ Model = 'qwen2.5-coder:7b'; Oss = $true; LocalProvider = 'ollama' }
    Assert-Codex -Label 'oss lmstudio'             -Expected 'local'    -ExpectedKey 'lmstudio/foo'              -CallArgs @{ Model = 'foo'; Oss = $true; LocalProvider = 'lmstudio' }
    Assert-Codex -Label 'local profile (loopback)' -Expected 'local'    -ExpectedKey 'localx/qwen2.5-coder:7b'   -CallArgs @{ Profile = 'plocal' }
    Assert-Codex -Label 'remote profile'           -Expected 'external' -ExpectedKey 'remotex/some-model'        -CallArgs @{ Profile = 'premote' }
    Assert-Codex -Label 'nonexistent profile'      -Expected 'unknown'  -ExpectedKey ''                          -CallArgs @{ Model = 'x'; Profile = 'naoexiste' }
} finally {
    Get-ChildItem -LiteralPath $tmp -File -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
}

# Missing config with an explicit model: falls back to openai/external (built-in), not unknown.
$missing = Join-Path $tmp 'inexistente.toml'
$out = & $target -Model 'gpt-5.5' -ConfigPath $missing | ConvertFrom-Json
if ([string]$out.locality -eq 'external') {
    Write-Host ("PASS  {0,-40} -> {1}" -f 'missing config -> openai external', $out.locality) -ForegroundColor Green
} else {
    $fail++
    Write-Host ("FAIL  missing config -> {0} (expected external)" -f $out.locality) -ForegroundColor Red
}

# Missing config and omitted model: does not invent a model; stays unknown.
$outMissingDefault = & $target -ConfigPath $missing | ConvertFrom-Json
if ([string]$outMissingDefault.locality -eq 'unknown') {
    Write-Host ("PASS  {0,-40} -> {1}" -f 'missing config + omitted model', $outMissingDefault.locality) -ForegroundColor Green
} else {
    $fail++
    Write-Host ("FAIL  missing config + omitted model -> {0} (expected unknown)" -f $outMissingDefault.locality) -ForegroundColor Red
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-CodexModelLocalitySelfTest.ps1" }
Write-Host 'OK: Test-CodexModelLocalitySelfTest.ps1' -ForegroundColor Cyan
