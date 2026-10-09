#requires -Version 7.4
<#
.SYNOPSIS
    Deterministic self-test of the Gemini resolver in mimir-delegate.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-GeminiModelLocality.ps1'
$out = & $target -Model 'gemini-3-flash-preview' | ConvertFrom-Json
if ([string]$out.locality -ne 'external') { throw "BLOCK: expected locality external; got $($out.locality)" }
if ([string]$out.canonicalModel -ne 'google/gemini-3-flash-preview') { throw "BLOCK: unexpected canonicalModel: $($out.canonicalModel)" }

Write-Host 'OK: Test-GeminiModelLocalitySelfTest.ps1' -ForegroundColor Cyan
