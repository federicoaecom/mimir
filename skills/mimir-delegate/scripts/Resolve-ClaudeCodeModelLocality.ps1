#requires -Version 7.4
<#
.SYNOPSIS
    Classifies a Claude Code invocation as an external Anthropic destination and returns the
    canonical provider/model key used by the confidentiality gate.
.DESCRIPTION
    claude-code backend of the mimir-delegate skill. Claude Code, in the usage covered by this
    adapter, sends traffic to Anthropic; therefore known Claude models are external.

    The policy key is always the destination: anthropic/<model>. The adapter never enters the
    key. Volatile aliases are treated conservatively: only `opus` is normalized here
    to `claude-opus-4-8`, because this is the workstream's explicit target; other bare aliases
    remain unknown to avoid an ambiguous policy.

    Output: compact JSON with locality, provider, canonicalModel and reason.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Model = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$raw = $Model.Trim()
$modelId = $raw
if ($raw -like 'anthropic/*') {
    $modelId = ($raw -split '/', 2)[1]
}

$canonicalModel = $null
$locality = 'unknown'
$provider = $null
$reason = ''

if ([string]::IsNullOrWhiteSpace($modelId)) {
    $reason = "model not provided; unknown destination (fail-closed in the gate: kb-sensitive payload -> ask, public -> allow)"
}
elseif ($modelId -ieq 'opus') {
    $provider = 'anthropic'
    $modelId = 'claude-opus-4-8'
    $canonicalModel = 'anthropic/claude-opus-4-8'
    $locality = 'external'
    $reason = "alias 'opus' normalized to Claude Opus 4.8; external Anthropic destination"
}
elseif ($modelId -match '^claude-[a-z0-9][a-z0-9\-]*$') {
    $provider = 'anthropic'
    $canonicalModel = "anthropic/$modelId"
    $locality = 'external'
    $reason = "explicit Claude model; external Anthropic destination"
}
else {
    $reason = "model '$Model' not recognized as an explicit Claude model; unknown locality (fail-closed in the gate for a sensitive payload)"
}

[pscustomobject]@{
    model          = $Model
    modelId        = $modelId
    provider       = $provider
    baseUrl        = $null
    locality       = $locality
    canonicalModel = $canonicalModel
    reason         = $reason
} | ConvertTo-Json -Compress
