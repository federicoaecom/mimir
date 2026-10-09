#requires -Version 7.4
<#
.SYNOPSIS
    Deterministic self-test of the Copilot resolver in mimir-delegate.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$target = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-CopilotModelLocality.ps1'
$out = & $target -Model 'gpt-5-mini' | ConvertFrom-Json
if ([string]$out.locality -ne 'external') { throw "BLOCK: expected locality external; got $($out.locality)" }
if ([string]$out.canonicalModel -ne 'github-copilot/gpt-5-mini') { throw "BLOCK: unexpected canonicalModel: $($out.canonicalModel)" }

# The resolver's default mirrors the adapter's default (auto). The Copilot catalog changes
# between CLI versions: on 2026-08-06 the old default 'gpt-5-mini' was already rejected by
# CLI 1.0.78. A concrete model passed by the caller still holds (assert above); what cannot
# come back is a concrete id as the DEFAULT.
$def = & $target | ConvertFrom-Json
if ([string]$def.locality -ne 'external') { throw "BLOCK: default: expected locality external; got $($def.locality)" }
if ([string]$def.canonicalModel -ne 'github-copilot/auto') { throw "BLOCK: default should be github-copilot/auto; got $($def.canonicalModel)" }

$emptyModel = & $target -Model '' | ConvertFrom-Json
if ([string]$emptyModel.canonicalModel -ne 'github-copilot/auto') { throw "BLOCK: empty model should fall back to github-copilot/auto; got $($emptyModel.canonicalModel)" }

Write-Host 'OK: Test-CopilotModelLocalitySelfTest.ps1' -ForegroundColor Cyan
