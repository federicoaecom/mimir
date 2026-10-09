#requires -Version 7.4
<#
.SYNOPSIS
    Classifies the destination of a call to the Gemini CLI.
.DESCRIPTION
    Gemini backend of the mimir-delegate skill. The Gemini CLI uses Google's external
    service; therefore locality is always external. The canonical key used by the gate is
    google/<model>, since the operational destination is the Google provider.

    Output: machine JSON object on stdout.
.PARAMETER Model
    Model requested from the Gemini CLI. Default: gemini-3-flash-preview, observed on the CLI
    validated on this machine when the user did not provide -m/--model.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Model = 'gemini-3-flash-preview'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modelParts = @($Model -split '/')
$modelId = $modelParts[$modelParts.Count - 1].Trim()
if ([string]::IsNullOrWhiteSpace($modelId)) { $modelId = 'gemini-3-flash-preview' }

[pscustomobject]@{
    model          = $Model
    modelId        = $modelId
    provider       = 'google'
    baseUrl        = $null
    locality       = 'external'
    canonicalModel = "google/$modelId"
    reason         = 'Gemini CLI uses Google''s external service; keyed by destination google/<model>'
} | ConvertTo-Json -Compress
