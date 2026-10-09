#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the Resolve-AntigravityModelLocality.ps1 resolver.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-AntigravityModelLocality.ps1'

$passed = 0
$failed = 0

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -eq $Expected) {
        $script:passed++
        Write-Host "[PASS] $Message" -ForegroundColor Green
    } else {
        $script:failed++
        Write-Host "[FAIL] $Message (expected '$Expected', got '$Actual')" -ForegroundColor Red
    }
}

# 1. Default (gemini-3.6-flash-high)
$res1 = & $script | ConvertFrom-Json
Assert-Equal $res1.provider 'antigravity' "Provider is antigravity"
Assert-Equal $res1.canonicalModel 'antigravity/gemini-3.6-flash-high' "CanonicalModel is antigravity/gemini-3.6-flash-high"
Assert-Equal $res1.family 'google' "Family is google"
Assert-Equal $res1.locality 'external' "Locality is external"

# 2. Claude
$res2 = & $script -Model 'antigravity/claude-sonnet-4-6' | ConvertFrom-Json
Assert-Equal $res2.canonicalModel 'antigravity/claude-sonnet-4-6' "CanonicalModel is antigravity/claude-sonnet-4-6"
Assert-Equal $res2.family 'anthropic' "Family is anthropic"

# 3. GPT
$res3 = & $script -Model 'gpt-oss-120b-medium' | ConvertFrom-Json
Assert-Equal $res3.canonicalModel 'antigravity/gpt-oss-120b-medium' "CanonicalModel is antigravity/gpt-oss-120b-medium"
Assert-Equal $res3.family 'openai' "Family is openai"

Write-Host "Self-test result: $passed passed, $failed failed."
if ($failed -gt 0) { exit 1 }
Write-Host "OK: Test-AntigravityModelLocalitySelfTest.ps1"
