#requires -Version 7.4
<#
.SYNOPSIS
    Deterministically classifies whether an opencode model runs LOCAL (on the machine)
    or EXTERNAL (leaves the machine), reading the opencode config.
.DESCRIPTION
    opencode backend of the mimir-delegate skill. Reads ~/.config/opencode/opencode.json (or
    -ConfigPath), resolves the given model's provider, and classifies by baseURL:

        - loopback (127.x / localhost / ::1)     -> local
        - explicit external baseURL              -> external
        - provider with no baseURL in the config -> external (custom, no local endpoint)
        - provider absent from the config        -> external (embedded/remote gateway by definition)
        - known cloud provider                   -> external (even without readable config)
        - unparseable model or missing config     -> unknown

    The only way for a model to be LOCAL is for its provider to point to a loopback baseURL.
    Absent that, traffic leaves the machine. The confidentiality gate
    (Resolve-LlmDelegateAuthorization.ps1) treats 'external' and 'unknown' as requiring
    authorization for a sensitive payload.

    Output: machine JSON object on stdout.
.PARAMETER Model
    Model in provider/model format (e.g. ollama/qwen2.5-coder).
.PARAMETER ConfigPath
    Path to opencode.json. Default: ~/.config/opencode/opencode.json.
.EXAMPLE
    .\Resolve-OpenCodeModelLocality.ps1 -Model ollama/qwen2.5-coder:7b_8192ctx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [string] $Model,
    [string] $ConfigPath = (Join-Path $HOME '.config' | Join-Path -ChildPath 'opencode' | Join-Path -ChildPath 'opencode.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function Test-LoopbackHost {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $h = $HostName.Trim().Trim('[', ']')
    return ($h -ieq 'localhost' -or $h -eq '::1' -or $h -match '^127\.')
}

function Test-KnownExternalProvider {
    param([string]$Provider)
    return @('ollama-cloud', 'opencode-go') -contains $Provider
}

function New-LocalityResult {
    param([string]$Provider, [string]$BaseUrl, [string]$Locality, [string]$Reason)
    [pscustomobject]@{
        model    = $Model
        provider = $Provider
        baseUrl  = $BaseUrl
        locality = $Locality
        reason   = $Reason
    } | ConvertTo-Json -Compress
}

# 1) Parse provider/model
$parts = @($Model -split '/', 2)
if ($parts.Count -lt 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
    New-LocalityResult -Provider $null -BaseUrl $null -Locality 'unknown' `
        -Reason "model is not in provider/model format: '$Model'"
    return
}
$provider = $parts[0].Trim()

# 2) Is the config readable?
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    if (Test-KnownExternalProvider $provider) {
        New-LocalityResult -Provider $provider -BaseUrl $null -Locality 'external' `
            -Reason "known cloud provider ('$provider'); treated as external even without readable config"
        return
    }
    New-LocalityResult -Provider $provider -BaseUrl $null -Locality 'unknown' `
        -Reason "opencode config not found: $ConfigPath"
    return
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
    if (Test-KnownExternalProvider $provider) {
        New-LocalityResult -Provider $provider -BaseUrl $null -Locality 'external' `
            -Reason "known cloud provider ('$provider'); treated as external despite failing to read/parse the config: $($_.Exception.Message)"
        return
    }
    New-LocalityResult -Provider $provider -BaseUrl $null -Locality 'unknown' `
        -Reason "failed to read/parse the opencode config: $($_.Exception.Message)"
    return
}

# 3) Is the provider declared in the config?
$providers = Get-Prop $config 'provider'
$providerNode = Get-Prop $providers $provider
if ($null -eq $providerNode) {
    New-LocalityResult -Provider $provider -BaseUrl $null -Locality 'external' `
        -Reason 'provider absent from the config (embedded/remote gateway by definition, or invalid name); treated as external'
    return
}

# 4) The provider's baseURL
$options = Get-Prop $providerNode 'options'
$baseUrl = Get-Prop $options 'baseURL'
if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    New-LocalityResult -Provider $provider -BaseUrl $null -Locality 'external' `
        -Reason 'declared provider with no local baseURL; treated as external'
    return
}

# 5) Classify by baseURL
$uriHost = $null
try { $uriHost = ([System.Uri]$baseUrl).Host } catch { $uriHost = $null }

if (Test-LoopbackHost $uriHost) {
    New-LocalityResult -Provider $provider -BaseUrl $baseUrl -Locality 'local' `
        -Reason "loopback baseURL ($uriHost); the data does not leave the machine"
} else {
    New-LocalityResult -Provider $provider -BaseUrl $baseUrl -Locality 'external' `
        -Reason "external baseURL (host '$uriHost'); the data leaves the machine"
}
