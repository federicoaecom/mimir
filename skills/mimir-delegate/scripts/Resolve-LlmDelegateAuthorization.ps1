#requires -Version 7.4
<#
.SYNOPSIS
    Confidentiality gate for the mimir-delegate skill: decides whether a payload can be
    sent to a model (allow / ask / deny), combining declared sensitivity,
    model locality and per-KB policy.
.DESCRIPTION
    Backend-agnostic core of the skill. Locality is resolved by the resolver for the backend
    selected via -Backend: opencode -> Resolve-OpenCodeModelLocality.ps1; codex ->
    Resolve-CodexModelLocality.ps1; claude-code -> Resolve-ClaudeCodeModelLocality.ps1;
    copilot -> Resolve-CopilotModelLocality.ps1; gemini -> Resolve-GeminiModelLocality.ps1;
    antigravity -> Resolve-AntigravityModelLocality.ps1
    (same folder). The key that matches the policy is the
    DESTINATION provider/model (the resolver's canonicalModel), not the backend/adapter: two
    backends sending to the same provider match the same rule (e.g. 'openai/*').

    Deterministic logic:

        payload = public                  -> allow  (any model; public data)
        payload = kb-sensitive:
            local locality                -> allow  (data does not leave the machine)
            external/unknown locality      -> consults the per-KB policy:
                allow-external (for model) -> allow  (announce destination anyway)
                deny-external              -> deny
                ask / not defined          -> ask    (requires explicit user authorization)

    'ask' means: the agent must get explicit user authorization before sending,
    and may offer to persist the choice in the policy file (durable clearance).

    Policy file (optional, per KB workspace), JSON:
        {
          "schemaVersion": 1,
          "defaultExternal": "ask",
          "models": {
            "openai/gpt-5.4": "allow-external",
            "ollama-cloud/*": "deny-external"
          }
        }
    Model resolution in the policy: exact key -> 'provider/*' wildcard -> '*' wildcard
    -> defaultExternal -> 'ask' (when there is no file).

    Output: machine JSON object on stdout.
.PARAMETER Model
    Model. In the opencode backend, provider/model format (e.g. openai/gpt-5.4). In the
    codex backend, the bare name (e.g. gpt-5.5); when omitted, the codex resolver tries to
    derive the default from the Codex config. In the claude-code backend, the Claude
    model name (e.g. claude-opus-4-8; alias 'opus' normalized); when omitted, locality is
    'unknown' and the gate treats it as external (fail-safe -> ask for sensitive payload). In the
    copilot, gemini and antigravity backends, the model name; when omitted, the resolver applies its
    default (auto in copilot - the CLI itself picks the model -, gemini-3-flash-preview
    in gemini, gemini-3.6-flash-high in antigravity).
.PARAMETER Backend
    Delegation backend: 'opencode' (default), 'codex', 'claude-code', 'copilot', 'gemini' or 'antigravity'.
    Selects the locality resolver.
.PARAMETER Oss
    (codex) Local OSS invocation (--oss); implies a local model. Passed through to the codex resolver.
.PARAMETER LocalProvider
    (codex) Local OSS provider when -Oss: 'ollama' or 'lmstudio'. Passed through to the codex resolver.
.PARAMETER Profile
    (codex) Codex config profile (-p); resolves the destination provider. Passed through to the codex resolver.
.PARAMETER PayloadSensitivity
    Payload class declared by the caller: 'kb-sensitive' (content from a
    KB workspace) or 'public' (public repo diff, sanitized template, README).
.PARAMETER PolicyPath
    Explicit path to the KB workspace's policy file. Takes precedence over
    -KbWorkspaceRoot. Optional; absent (and without -KbWorkspaceRoot) => 'ask'.
.PARAMETER KbWorkspaceRoot
    Root of the KB workspace. When provided and -PolicyPath is omitted, the gate uses
    '<KbWorkspaceRoot>\llm-delegation-policy.json' when that file exists. The output JSON carries
    policyFileName (the file name, or null when no policy file was found).
.PARAMETER ConfigPath
    Path to the backend config, passed through to the locality resolver: opencode.json for the
    opencode backend; the Codex config.toml when -Backend codex. Optional.
.EXAMPLE
    .\Resolve-LlmDelegateAuthorization.ps1 -Model ollama/qwen2.5-coder:7b_8192ctx -PayloadSensitivity kb-sensitive
.EXAMPLE
    .\Resolve-LlmDelegateAuthorization.ps1 -Model openai/gpt-5.4 -PayloadSensitivity public
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Model,
    [Parameter(Mandatory)] [ValidateSet('kb-sensitive', 'public')] [string] $PayloadSensitivity,
    [ValidateSet('opencode', 'codex', 'claude-code', 'copilot', 'gemini', 'antigravity', 'orchestrator-native')] [string] $Backend = 'opencode',
    [switch] $Oss,
    [ValidateSet('ollama', 'lmstudio')] [string] $LocalProvider,
    [string] $Profile,
    [string] $PolicyPath,
    [string] $KbWorkspaceRoot,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Prop {
    param($Obj, [string]$Name)
    # Guard against an empty $Name: PSObject.Properties[''] throws "value of argument 'name'
    # is not valid". An empty name never matches a property -> return $null.
    if ($null -ne $Obj -and -not [string]::IsNullOrEmpty($Name) -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function New-AuthResult {
    param(
        [string]$Locality, [string]$BaseUrl, [string]$Verdict,
        [string]$PolicyDecision, [string]$PolicySource, [string]$Reason
    )
    [pscustomobject]@{
        model              = $Model
        backend            = $Backend
        targetModelKey     = $matchKey
        payloadSensitivity = $PayloadSensitivity
        locality           = $Locality
        baseUrl            = $BaseUrl
        verdict            = $Verdict
        policyDecision     = $PolicyDecision
        policySource       = $PolicySource
        policyFileName     = $policyFileName
        reason             = $Reason
    } | ConvertTo-Json -Compress
}

# 0) Resolve the effective policy file path.
#    An explicit -PolicyPath takes precedence; -KbWorkspaceRoot looks for the policy file at its root.
$policyFileName = $null
if (-not $PolicyPath -and $KbWorkspaceRoot) {
    if (-not (Test-Path -LiteralPath $KbWorkspaceRoot -PathType Container)) {
        throw "BLOCK: KbWorkspaceRoot is not an existing directory: $KbWorkspaceRoot"
    }
    $policyName = 'llm-delegation-policy.json'
    $candidate  = Join-Path (Resolve-Path -LiteralPath $KbWorkspaceRoot).Path $policyName
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $PolicyPath     = $candidate
        $policyFileName = $policyName
    }
}

# 1) Resolve the model's locality (per-backend resolver)
$resolverName = switch ($Backend) {
    'codex'                { 'Resolve-CodexModelLocality.ps1' }
    'claude-code'          { 'Resolve-ClaudeCodeModelLocality.ps1' }
    'copilot'              { 'Resolve-CopilotModelLocality.ps1' }
    'gemini'               { 'Resolve-GeminiModelLocality.ps1' }
    'antigravity'          { 'Resolve-AntigravityModelLocality.ps1' }
    'orchestrator-native'  { 'Resolve-OrchestratorNativeModelLocality.ps1' }
    default                { 'Resolve-OpenCodeModelLocality.ps1' }
}
$localityScript = Join-Path $PSScriptRoot $resolverName
if (-not (Test-Path -LiteralPath $localityScript -PathType Leaf)) {
    throw "BLOCK: locality resolver not found: $localityScript"
}
$localityArgs = @{ Model = $Model }
if ($Backend -in @('opencode', 'codex') -and $PSBoundParameters.ContainsKey('ConfigPath')) {
    $localityArgs['ConfigPath'] = $ConfigPath
}
if ($Backend -eq 'codex') {
    if ($Oss) { $localityArgs['Oss'] = $true }
    if ($PSBoundParameters.ContainsKey('LocalProvider')) { $localityArgs['LocalProvider'] = $LocalProvider }
    if ($PSBoundParameters.ContainsKey('Profile')) { $localityArgs['Profile'] = $Profile }
}
$localityJson = & $localityScript @localityArgs
$loc = $localityJson | ConvertFrom-Json
$locality = [string]$loc.locality
$baseUrl  = [string]$loc.baseUrl
# DESTINATION key to match the policy: the canonicalModel when the resolver supplies it
# (codex normalizes it to the destination provider); otherwise Model itself (opencode is already canonical).
$matchKey = [string](Get-Prop $loc 'canonicalModel')
if ([string]::IsNullOrWhiteSpace($matchKey)) { $matchKey = $Model }

# 2) Public payload: always allowed
if ($PayloadSensitivity -eq 'public') {
    New-AuthResult -Locality $locality -BaseUrl $baseUrl -Verdict 'allow' `
        -PolicyDecision 'n/a' -PolicySource 'n/a' `
        -Reason 'public payload; send allowed to any model'
    return
}

# 3) Sensitive payload + local model: the data does not leave the machine
if ($locality -eq 'local') {
    New-AuthResult -Locality $locality -BaseUrl $baseUrl -Verdict 'allow' `
        -PolicyDecision 'n/a' -PolicySource 'n/a' `
        -Reason 'sensitive payload, but local model (loopback); the data does not leave the machine'
    return
}

# 3b) Unresolvable destination (model omitted and canonicalModel null, e.g. claude-code without
#     -Model): a policy cannot be matched by an empty key (lookup with '' throws). Fail-closed
#     per the doc (.PARAMETER Model): kb-sensitive payload -> ask. (public already returned above.)
if ([string]::IsNullOrWhiteSpace($matchKey)) {
    New-AuthResult -Locality $locality -BaseUrl $baseUrl -Verdict 'ask' `
        -PolicyDecision $null -PolicySource 'destination-not-resolvable' `
        -Reason 'model omitted and destination unresolvable (locality unknown); fail-closed: requires explicit authorization'
    return
}

# 4) Sensitive payload + external/unknown model: consult the per-KB policy
$policyDecision = $null
$policySource   = $null

if ($PolicyPath -and (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    try {
        $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
    } catch {
        New-AuthResult -Locality $locality -BaseUrl $baseUrl -Verdict 'ask' `
            -PolicyDecision $null -PolicySource $PolicyPath `
            -Reason "unreadable/invalid policy ($($_.Exception.Message)); requires explicit authorization"
        return
    }

    $models = Get-Prop $policy 'models'
    $providerWildcard = (@($matchKey -split '/', 2)[0]) + '/*'
    foreach ($key in @($matchKey, $providerWildcard, '*')) {
        $decision = Get-Prop $models $key
        if ($null -ne $decision) {
            $policyDecision = [string]$decision
            $policySource   = "models['$key']"
            break
        }
    }

    if ($null -eq $policyDecision) {
        $def = Get-Prop $policy 'defaultExternal'
        if ($null -ne $def) {
            $policyDecision = [string]$def
            $policySource   = 'defaultExternal'
        }
    }
} else {
    $policySource = 'no-policy-file'
}

# 5) Verdict from the policy decision
switch ($policyDecision) {
    'allow-external' {
        New-AuthResult -Locality $locality -BaseUrl $baseUrl -Verdict 'allow' `
            -PolicyDecision $policyDecision -PolicySource $policySource `
            -Reason 'policy authorizes this external model for this KB content; announce the destination to the user'
    }
    'deny-external' {
        New-AuthResult -Locality $locality -BaseUrl $baseUrl -Verdict 'deny' `
            -PolicyDecision $policyDecision -PolicySource $policySource `
            -Reason 'policy forbids sending this KB content to this external model'
    }
    default {
        New-AuthResult -Locality $locality -BaseUrl $baseUrl -Verdict 'ask' `
            -PolicyDecision $policyDecision -PolicySource $policySource `
            -Reason 'no durable authorization; requires explicit user authorization (and an offer to persist it in the policy file)'
    }
}
