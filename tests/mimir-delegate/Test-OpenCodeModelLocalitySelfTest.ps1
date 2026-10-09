#requires -Version 7.4
<#
.SYNOPSIS
    Contract self-test for Resolve-OpenCodeModelLocality.ps1 (mimir-delegate skill).
.DESCRIPTION
    Creates a synthetic opencode config and validates the local/external/unknown classification
    for several models, without depending on opencode being installed or on network. Deterministic.
    Success sentinel: OK: Test-OpenCodeModelLocalitySelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-OpenCodeModelLocality.ps1'
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "BLOCK: target not found: $target" }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ocloc-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$cfg = Join-Path $tmp 'opencode.json'
@'
{
  "provider": {
    "ollama":   { "options": { "baseURL": "http://127.0.0.1:11434/v1" } },
    "lmstudio": { "options": { "baseURL": "http://localhost:1234/v1" } },
    "remote-x": { "options": { "baseURL": "https://api.example.com/v1" } },
    "no-url":   { "options": {} }
  }
}
'@ | Set-Content -LiteralPath $cfg -Encoding utf8

$fail = 0
function Assert-Locality {
    param([string]$Model, [string]$Expected, [string]$ConfigPath)
    $callArgs = @{ Model = $Model }
    if ($PSBoundParameters.ContainsKey('ConfigPath')) { $callArgs['ConfigPath'] = $ConfigPath }
    $out = & $target @callArgs | ConvertFrom-Json
    $got = [string]$out.locality
    if ($got -eq $Expected) {
        Write-Host ("PASS  {0,-32} -> {1}" -f $Model, $got) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0,-32} -> {1} (expected {2})" -f $Model, $got, $Expected) -ForegroundColor Red
    }
}

try {
    Assert-Locality -Model 'ollama/qwen2.5-coder:7b'    -Expected 'local'    -ConfigPath $cfg
    Assert-Locality -Model 'lmstudio/whatever'          -Expected 'local'    -ConfigPath $cfg
    Assert-Locality -Model 'remote-x/foo'               -Expected 'external' -ConfigPath $cfg
    Assert-Locality -Model 'no-url/foo'                 -Expected 'external' -ConfigPath $cfg
    Assert-Locality -Model 'openai/gpt-5.4'             -Expected 'external' -ConfigPath $cfg   # provider missing from config
    Assert-Locality -Model 'semBarra'                   -Expected 'unknown'  -ConfigPath $cfg
    Assert-Locality -Model 'ollama/foo' -Expected 'unknown' -ConfigPath (Join-Path $tmp 'inexistente.json')
    Assert-Locality -Model 'ollama-cloud/deepseek-v4-pro' -Expected 'external' -ConfigPath (Join-Path $tmp 'inexistente.json')
    Assert-Locality -Model 'opencode-go/deepseek-v4-pro'  -Expected 'external' -ConfigPath (Join-Path $tmp 'inexistente.json')
} finally {
    Get-ChildItem -LiteralPath $tmp -File -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $tmp -Force -Recurse -ErrorAction SilentlyContinue
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-OpenCodeModelLocalitySelfTest.ps1" }
Write-Host 'OK: Test-OpenCodeModelLocalitySelfTest.ps1' -ForegroundColor Cyan
