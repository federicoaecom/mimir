#requires -Version 7.4
<#
.SYNOPSIS
    Classifies the locality of an orchestrator-native destination (native subagent).
.DESCRIPTION
    orchestrator-native backend of the mimir-delegate skill. Shape identical to
    Resolve-AntigravityModelLocality (includes baseUrl=$null) so the gate does not branch.
    Locality = destination of the targetModelKey, never "in-process = local".
    This resolver never returns locality=local.
.PARAMETER Model
    targetModelKey (creator/model).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Model
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LlmDelegateTargetFamilySupport.ps1')

$raw = if ($null -eq $Model) { '' } else { $Model.Trim() }
$parts = @($raw -split '/')
$modelId = if ($parts.Count -ge 2) { $parts[-1] } else { $raw }
$provider = if ($parts.Count -ge 2) { $parts[0] } else { $raw }
$family = Get-LlmDelegateTargetFamily -TargetModelKey $raw

$locality = 'unknown'
$reason = 'native-unknown-family'

$first = if ($parts.Count -ge 1) { $parts[0] } else { '' }
if ($first.Equals('cursor', [System.StringComparison]::OrdinalIgnoreCase) -and $parts.Count -ge 2) {
    # cursor/<model>: if the resolved Creator is known (e.g. cursor/grok-* -> xai), counts as cloud.
    if ((Test-LlmDelegateFamilyKnown -Family $family)) {
        $locality = 'external'
        $reason = 'native-cloud-creator'
    } else {
        $locality = 'unknown'
        $reason = 'native-cursor-prefix'
    }
} elseif ($raw -notmatch '/') {
    # A slash-less harness slug (e.g. cursor-grok-*) may map to a known Creator.
    if ((Test-LlmDelegateFamilyKnown -Family $family)) {
        $locality = 'external'
        $reason = 'native-cloud-creator'
    } else {
        $locality = 'unknown'
        $reason = 'native-key-no-slash'
    }
} elseif (-not (Test-LlmDelegateFamilyKnown -Family $family)) {
    $locality = 'unknown'
    $reason = 'native-unknown-family'
} else {
    $locality = 'external'
    $reason = 'native-cloud-creator'
}

[pscustomobject]@{
    model          = $Model
    modelId        = $modelId
    provider       = $provider
    family         = $family
    baseUrl        = $null
    locality       = $locality
    canonicalModel = $raw
    reason         = $reason
} | ConvertTo-Json -Compress
