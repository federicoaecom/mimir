#requires -Version 7.4
<#
.SYNOPSIS
    Deterministically classifies whether a Codex invocation runs LOCAL (on the machine)
    or EXTERNAL (leaves the machine), and returns the canonical DESTINATION provider/model.
.DESCRIPTION
    codex backend of the mimir-delegate skill. Mirrors the opencode resolver's criterion
    (Resolve-OpenCodeModelLocality.ps1): locality comes from the destination provider's
    baseURL, not from the model's name.

    AXIS (see the skill's ANATOMY section): this script translates the Codex invocation into
    the DESTINATION key that the gate and the policy use. The backend/adapter (Codex vs
    opencode) does NOT enter the key: if the traffic goes to OpenAI, the key is openai/<model>,
    the same as opencode. That is why a single 'openai/*' policy rule covers both backends.

    Codex does not use the provider/model format on the command line (when -Model is provided,
    it uses a bare '-m <model>'; when omitted, Codex's/config's own default applies). This
    resolver determines the effective provider:

        -Oss / -LocalProvider <ollama|lmstudio>  -> local OSS provider (loopback) -> local
        -Profile <id>                            -> [profiles.<id>].model_provider ->
                                                    [model_providers.<prov>].base_url -> loopback?
        neither oss nor profile                  -> the config's top-level model_provider, or
                                                    'openai' (built-in, no base_url) -> external

    Classification by base_url (same as opencode):
        - loopback (127.x / localhost / ::1)          -> local
        - explicit external base_url                  -> external
        - built-in provider with no base_url in config -> external (remote endpoint by definition)
        - unresolvable profile/provider                -> unknown

    The confidentiality gate (Resolve-LlmDelegateAuthorization.ps1) treats 'external' and
    'unknown' as requiring authorization for a sensitive payload.

    Output: machine JSON object on stdout, with the same fields as the opencode resolver
    plus 'canonicalModel' (the destination key the gate matches against the policy).
.PARAMETER Model
    Model name as Codex accepts it (e.g. gpt-5.5). Optional; when omitted, the
    resolver tries to derive it from [profiles.<id>].model or the config's top-level model.
    Also accepts the prefixed form (openai/gpt-5.5); in that case only the model part is
    used, and the provider is determined by the invocation/config, not by the prefix.
.PARAMETER Oss
    Indicates invocation with a local open-source provider (codex exec --oss). Implies local.
.PARAMETER LocalProvider
    Local OSS provider when -Oss: 'ollama' (default) or 'lmstudio'.
.PARAMETER Profile
    Codex config profile name (codex exec -p <id>). Resolves the model_provider and the
    base_url from [profiles.<id>] / [model_providers.<prov>].
.PARAMETER ConfigPath
    Path to the Codex config.toml. Default: ~/.codex/config.toml.
.EXAMPLE
    .\Resolve-CodexModelLocality.ps1 -Model gpt-5.5
.EXAMPLE
    .\Resolve-CodexModelLocality.ps1 -Model qwen2.5-coder:7b -Oss -LocalProvider ollama
.EXAMPLE
    .\Resolve-CodexModelLocality.ps1 -Model qwen2.5-coder:7b -Profile ollama-launch
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Model,
    [switch] $Oss,
    [ValidateSet('ollama', 'lmstudio')] [string] $LocalProvider,
    [string] $Profile,
    [string] $ConfigPath = (Join-Path $HOME '.codex' | Join-Path -ChildPath 'config.toml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:modelId = $null
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $initialModelParts = @($Model -split '/')
    $script:modelId = $initialModelParts[$initialModelParts.Count - 1].Trim()
    if ([string]::IsNullOrWhiteSpace($script:modelId)) { $script:modelId = $null }
}

function Test-LoopbackHost {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $h = $HostName.Trim().Trim('[', ']')
    return ($h -ieq 'localhost' -or $h -eq '::1' -or $h -match '^127\.')
}

function Get-BaseUrlLocality {
    param([string]$BaseUrl)
    $uriHost = $null
    try { $uriHost = ([System.Uri]$BaseUrl).Host } catch { $uriHost = $null }
    if (Test-LoopbackHost $uriHost) { return 'local' }
    return 'external'
}

function New-LocalityResult {
    param([string]$Provider, [string]$BaseUrl, [string]$Locality, [string]$Reason)
    $canonical = if ($Provider -and $script:modelId) { "$Provider/$script:modelId" } elseif ($script:modelId) { $script:modelId } else { $null }
    [pscustomobject]@{
        model          = $Model
        modelId        = $script:modelId
        provider       = $Provider
        baseUrl        = $BaseUrl
        locality       = $Locality
        canonicalModel = $canonical
        reason         = $Reason
    } | ConvertTo-Json -Compress
}

# Focused mini TOML parser: collects only what the resolver needs.
#   - $topLevelModel    : 'model' before the first [..] section
#   - $topLevelProvider : 'model_provider' before the first [..] section
#   - $providerBaseUrl  : base_url per [model_providers.<id>]
#   - $profileModel     : model per [profiles.<id>]
#   - $profileProvider  : model_provider per [profiles.<id>]
function Read-CodexConfigSubset {
    param([string]$Path)
    $providerBaseUrl = @{}
    $profileModel = @{}
    $profileProvider = @{}
    $topLevelModel = $null
    $topLevelProvider = $null
    $section = ''   # '' = top level

    foreach ($rawLine in (Get-Content -LiteralPath $Path -Encoding utf8)) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }

        $secMatch = [regex]::Match($line, '^\[([^\]]+)\]')
        if ($secMatch.Success) { $section = $secMatch.Groups[1].Value.Trim(); continue }

        $kvMatch = [regex]::Match($line, '^([A-Za-z0-9_\-\.]+)\s*=\s*"([^"]*)"')
        if (-not $kvMatch.Success) { continue }
        $key = $kvMatch.Groups[1].Value
        $val = $kvMatch.Groups[2].Value

        if ($section -eq '') {
            if ($key -eq 'model') { $topLevelModel = $val }
            if ($key -eq 'model_provider') { $topLevelProvider = $val }
        }
        elseif ($section -like 'model_providers.*') {
            if ($key -eq 'base_url') {
                $id = $section.Substring('model_providers.'.Length)
                $providerBaseUrl[$id] = $val
            }
        }
        elseif ($section -like 'profiles.*') {
            if ($key -eq 'model') {
                $id = $section.Substring('profiles.'.Length)
                $profileModel[$id] = $val
            }
            if ($key -eq 'model_provider') {
                $id = $section.Substring('profiles.'.Length)
                $profileProvider[$id] = $val
            }
        }
    }

    [pscustomobject]@{
        topLevelModel    = $topLevelModel
        topLevelProvider = $topLevelProvider
        providerBaseUrl  = $providerBaseUrl
        profileModel     = $profileModel
        profileProvider  = $profileProvider
    }
}

# 1) Explicit LOCAL path via OSS: does not depend on the config.
if ($Oss -or $LocalProvider) {
    $prov = if ($LocalProvider) { $LocalProvider } else { 'ollama' }
    $baseUrl = if ($prov -eq 'lmstudio') { 'http://localhost:1234/v1' } else { 'http://localhost:11434/v1' }
    New-LocalityResult -Provider $prov -BaseUrl $baseUrl -Locality 'local' `
        -Reason "local OSS invocation ($prov, loopback); the data does not leave the machine"
    return
}

# 2) Is the config readable? (needed for profile and top-level provider)
$configFound = Test-Path -LiteralPath $ConfigPath -PathType Leaf
$cfg = $null
if ($configFound) {
    try {
        $cfg = Read-CodexConfigSubset -Path $ConfigPath
    } catch {
        New-LocalityResult -Provider $null -BaseUrl $null -Locality 'unknown' `
            -Reason "failed to read/parse the Codex config.toml: $($_.Exception.Message)"
        return
    }
}

# Effective model: if -Model was omitted, use profile.model or the config's top-level model.
if ($script:modelId) {
    # An explicit -Model wins over the config.
}
elseif ($Profile -and $configFound -and $cfg.profileModel.ContainsKey($Profile)) {
    $script:modelId = [string]$cfg.profileModel[$Profile]
}
elseif ($configFound -and $cfg.topLevelModel) {
    $script:modelId = [string]$cfg.topLevelModel
}

if ([string]::IsNullOrWhiteSpace($script:modelId)) {
    $script:modelId = $null
}

# 3) PROFILE path: resolves provider -> base_url from the config.
if ($Profile) {
    if (-not $configFound) {
        New-LocalityResult -Provider $null -BaseUrl $null -Locality 'unknown' `
            -Reason "profile '$Profile' requested, but config.toml not found: $ConfigPath"
        return
    }
    if (-not $cfg.profileProvider.ContainsKey($Profile)) {
        New-LocalityResult -Provider $null -BaseUrl $null -Locality 'unknown' `
            -Reason "profile '$Profile' has no model_provider in the config; not resolvable"
        return
    }
    $prov = $cfg.profileProvider[$Profile]
    if (-not $script:modelId) {
        New-LocalityResult -Provider $prov -BaseUrl $null -Locality 'unknown' `
            -Reason "profile '$Profile' has no model in the config and -Model was omitted; destination model not resolvable"
        return
    }
    if (-not $cfg.providerBaseUrl.ContainsKey($prov)) {
        # Built-in provider (e.g. openai) with no base_url in the config -> external.
        New-LocalityResult -Provider $prov -BaseUrl $null -Locality 'external' `
            -Reason "profile '$Profile' uses the built-in provider '$prov' (no local base_url); treated as external"
        return
    }
    $baseUrl = $cfg.providerBaseUrl[$prov]
    $locality = Get-BaseUrlLocality $baseUrl
    New-LocalityResult -Provider $prov -BaseUrl $baseUrl -Locality $locality `
        -Reason "profile '$Profile' -> provider '$prov' (base_url '$baseUrl')"
    return
}

# 4) DEFAULT path: the config's top-level provider, or built-in openai.
$prov = if ($configFound -and $cfg.topLevelProvider) { $cfg.topLevelProvider } else { 'openai' }

if (-not $script:modelId) {
    New-LocalityResult -Provider $prov -BaseUrl $null -Locality 'unknown' `
        -Reason "model omitted and the config has no top-level model; exact destination not resolvable"
    return
}

if (-not $configFound -or -not $cfg.providerBaseUrl.ContainsKey($prov)) {
    # openai (or another built-in) with no local base_url -> external, by definition.
    New-LocalityResult -Provider $prov -BaseUrl $null -Locality 'external' `
        -Reason "destination provider '$prov' built-in/remote (no local base_url); the data leaves the machine"
    return
}

$baseUrl = $cfg.providerBaseUrl[$prov]
$locality = Get-BaseUrlLocality $baseUrl
New-LocalityResult -Provider $prov -BaseUrl $baseUrl -Locality $locality `
    -Reason "destination provider '$prov' (base_url '$baseUrl')"
