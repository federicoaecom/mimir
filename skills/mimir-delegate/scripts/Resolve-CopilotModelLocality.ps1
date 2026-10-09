#requires -Version 7.4
<#
.SYNOPSIS
    Classifies the destination of a call to the GitHub Copilot CLI.
.DESCRIPTION
    Copilot backend of the mimir-delegate skill. The Copilot CLI sends the prompt to the
    GitHub Copilot service; therefore locality is always external. The canonical key used
    by the gate is github-copilot/<model>, never openai/<model>, because the operational
    destination is the Copilot service, not a direct call to the model's provider.

    Output: machine JSON object on stdout.
.PARAMETER Model
    Model requested from the Copilot CLI. Default: auto, mirroring the default of the
    Invoke-Copilot.ps1 adapter (Copilot itself picks the model). The key becomes
    github-copilot/auto: the operational destination remains the Copilot service, so it
    matches github-copilot/* in the policy just like any concrete id. Do not pin a model
    name here - see the volatile-catalog note in Invoke-Copilot.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Model = 'auto'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modelParts = @($Model -split '/')
$modelId = $modelParts[$modelParts.Count - 1].Trim()
if ([string]::IsNullOrWhiteSpace($modelId)) { $modelId = 'auto' }

[pscustomobject]@{
    model          = $Model
    modelId        = $modelId
    provider       = 'github-copilot'
    baseUrl        = $null
    locality       = 'external'
    canonicalModel = "github-copilot/$modelId"
    reason         = 'GitHub Copilot CLI uses the external GitHub Copilot service; keyed by destination github-copilot/<model>'
} | ConvertTo-Json -Compress
