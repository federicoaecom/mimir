#requires -Version 7.4
<#
.SYNOPSIS
    Classifies the destination of a call to the Antigravity CLI (agy).
.DESCRIPTION
    antigravity backend of the mimir-delegate skill. The Antigravity CLI uses the external Antigravity
    service; therefore, locality is always external. The canonical key used by the gate is
    antigravity/<model>, because the operational destination is the Antigravity provider.

    Output: machine JSON object on stdout.
.PARAMETER Model
    Model requested from the Antigravity CLI. Default: gemini-3.6-flash-high.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Model = 'gemini-3.6-flash-high'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LlmDelegateTargetFamilySupport.ps1')

$raw = $Model.Trim()
$modelId = $raw
if ($raw -like 'antigravity/*') {
    $modelId = ($raw -split '/', 2)[1].Trim()
}
if ([string]::IsNullOrWhiteSpace($modelId)) { $modelId = 'gemini-3.6-flash-high' }

$canonicalModel = "antigravity/$modelId"
$family = Get-LlmDelegateTargetFamily -TargetModelKey $canonicalModel

[pscustomobject]@{
    model          = $Model
    modelId        = $modelId
    provider       = 'antigravity'
    family         = $family
    baseUrl        = $null
    locality       = 'external'
    canonicalModel = $canonicalModel
    reason         = 'Antigravity CLI uses the external Antigravity service; key per destination antigravity/<model>'
} | ConvertTo-Json -Compress
