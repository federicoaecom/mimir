#requires -Version 7.4
<#
.SYNOPSIS
    Loads and validates the ordered panel CLI backend registry; registry data never grants authorization.
#>
function Get-LlmDelegateBackendRegistry {
    param([string]$Path = (Join-Path $PSScriptRoot 'LlmDelegateBackendRegistry.psd1'))
    $registry = Import-PowerShellDataFile -LiteralPath $Path
    $seen = @{}
    if ($registry.Backends -isnot [array]) { throw 'BLOCK: invalid backend registry' }
    foreach ($backendData in $registry.Backends) {
        if ($backendData -isnot [hashtable]) { throw 'BLOCK: invalid backend registry' }
        $name = $backendData.Name
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name) -or $seen.ContainsKey($name) -or $name -eq 'orchestrator-native' -or
            $backendData.Adapter -isnot [string] -or [string]::IsNullOrWhiteSpace($backendData.Adapter) -or
            $backendData.ExeParam -isnot [string] -or [string]::IsNullOrWhiteSpace($backendData.ExeParam) -or
            $backendData.ContentionKeys -isnot [array] -or $backendData.TimeoutSec -isnot [int] -or $backendData.TimeoutSec -lt 1 -or
            $backendData.CdCapable -isnot [bool]) { throw 'BLOCK: invalid backend registry' }
        foreach ($key in $backendData.ContentionKeys) {
            if ($key -isnot [string]) { throw 'BLOCK: invalid backend registry' }
        }
        $seen[$name] = $true
    }
    if ($seen.Count -lt 2) { throw 'BLOCK: invalid backend registry' }
    return $registry.Backends
}
