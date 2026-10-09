#requires -Version 7.4
<#
.SYNOPSIS
    Probes the LLM backends of the mimir-delegate skill installed on the machine and writes a
    sanitized CAPABILITY manifest (which backends/models are available and whether they
    are local or external), to feed the peer-review panel OFFER without
    re-probing on every use.
.DESCRIPTION
    Part of the mimir-delegate skill mechanism; peer-review methodology in
    15-peer-review.md. The manifest is a MACHINE-level fact, written outside
    git (default capabilities.json in the mimir-delegate state folder; see -OutputPath).

    HINT, NEVER GATE TRUTH: this manifest serves the offer/UI. The confidentiality
    gate (Resolve-LlmDelegateAuthorization.ps1) does NOT consume this file;
    it re-evaluates destination and sensitivity deterministically on every use. Do not couple them.

    SANITIZATION BY DESIGN: the manifest writes ONLY non-sensitive metadata, such as
    backend, targetModelKey, canonicalModel, provider, family, sourceKind, sourceConfidence,
    availableInManifest, locality, reasonCode (short code, no host/baseURL), hardVeto and
    diagnostics. It NEVER writes a token, API key, baseURL/host, header, config path,
    prompt, or per-KB policy. The self-test proves this absence.

    ENUMERATION: opencode reads provider/model from opencode.json/jsonc; Codex uses config.toml
    and its resolver; Claude Code combines configured settings and weak/historical cache
    (enumeration=settings-or-historical); the Antigravity CLI probes models via agy models
    (enumeration=cli). Copilot and Gemini remain registered as installed without strong native
    enumeration (models=[] and enumeration=none-native); their default model lives in the skill doc/no. 14, not here.

    STABLE vs VOLATILE: what the manifest records (installed? local/external?) is stable and
    cacheable. Backend HEALTH ("does it respond now?") is volatile and lives in lastHealthCheck
    (null by default) - lightly re-checked at review time, not in this probe.

    Reuse: calls Resolve-OpenCodeModelLocality.ps1, Resolve-CodexModelLocality.ps1,
    Resolve-ClaudeCodeModelLocality.ps1, Resolve-CopilotModelLocality.ps1, Resolve-GeminiModelLocality.ps1
    and Resolve-AntigravityModelLocality.ps1 in-process for each model's locality (the canonical
    destination key). Enumeration itself (listing the models) is this script's own logic,
    since the resolvers classify ONE given model.
.PARAMETER OutputPath
    Path to the machine-level manifest. Default: capabilities.json in the state root
    (%LOCALAPPDATA%\mimir-delegate on Windows; $XDG_DATA_HOME/mimir-delegate, else
    ~/.local/share/mimir-delegate, on Linux; on macOS, see LlmDelegateStatePath.ps1).
.PARAMETER SnapshotPath
    When provided, also writes a per-KB snapshot (re-derivable cache) with snapshotAt and
    sourceGeneratedAt. The KB workspace setup uses Temp\llm-delegate-capabilities.snapshot.json.
.PARAMETER OpenCodeConfigPath
    Path to opencode.json/jsonc. Default: ~/.config/opencode/opencode.json; if absent,
    tries ~/.config/opencode/opencode.jsonc.
.PARAMETER CodexConfigPath
    Path to the Codex config.toml. Default: ~/.codex/config.toml.
.PARAMETER ClaudeSettingsPath
    Path to Claude Code's settings.json/jsonc. Default: ~/.claude/settings.json.
.PARAMETER ClaudeStatsCachePath
    Optional path to Claude Code's stats-cache.json. Weak/historical source.
.PARAMETER AntigravityExe
    Path to the Antigravity CLI executable (agy.exe). When omitted, it is resolved via AntigravityCliSupport.ps1.
.PARAMETER AntigravityProbeTimeoutSec
    TEST-ONLY. Time cap for the `agy models` probe. Default 20s. Exists so the self-test can prove
    the cutoff without waiting for the real cap; do not use in normal calls.
.EXAMPLE
    .\Build-LlmDelegateCapabilityManifest.ps1
.EXAMPLE
    .\Build-LlmDelegateCapabilityManifest.ps1 -SnapshotPath 'C:\KB\Workspace\Temp\llm-delegate-capabilities.snapshot.json'
#>
[CmdletBinding()]
param(
    [string] $OutputPath,
    [string] $SnapshotPath,
    [string] $OpenCodeConfigPath = (Join-Path $HOME '.config' | Join-Path -ChildPath 'opencode' | Join-Path -ChildPath 'opencode.json'),
    [string] $CodexConfigPath = (Join-Path $HOME '.codex' | Join-Path -ChildPath 'config.toml'),
    [string] $ClaudeSettingsPath = (Join-Path $HOME '.claude' | Join-Path -ChildPath 'settings.json'),
    [string] $ClaudeStatsCachePath = (Join-Path $HOME '.claude' | Join-Path -ChildPath 'stats-cache.json'),
    [string] $AntigravityExe,
    [ValidateRange(1, 600)] [int] $AntigravityProbeTimeoutSec = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsDir = $PSScriptRoot
. (Join-Path $scriptsDir 'LlmDelegateTargetFamilySupport.ps1')
. (Join-Path $scriptsDir 'LlmDelegateStatePath.ps1')

if (-not $PSBoundParameters.ContainsKey('OutputPath')) {
    $OutputPath = Join-Path (Get-LlmDelegateStateRoot) 'capabilities.json'
}
$openResolver = Join-Path $scriptsDir 'Resolve-OpenCodeModelLocality.ps1'
$codexResolver = Join-Path $scriptsDir 'Resolve-CodexModelLocality.ps1'
$claudeResolver = Join-Path $scriptsDir 'Resolve-ClaudeCodeModelLocality.ps1'

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function Test-CommandPresent {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function ConvertFrom-JsoncText {
    param([Parameter(Mandatory)] [string]$Text)
    $withoutBlock = [regex]::Replace($Text, '(?s)/\*.*?\*/', '')
    $withoutLine = [regex]::Replace($withoutBlock, '(?m)^\s*//.*$', '')
    $withoutTrailingCommas = [regex]::Replace($withoutLine, ',(\s*[\}\]])', '$1')
    return $withoutTrailingCommas | ConvertFrom-Json
}

function Read-JsonOrJsoncFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return ConvertFrom-JsoncText -Text (Get-Content -LiteralPath $Path -Raw -Encoding utf8)
}

function Resolve-OpenCodeConfigPath {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return $Path }
    if ($Path.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) {
        $jsonc = $Path.Substring(0, $Path.Length - 5) + '.jsonc'
        if (Test-Path -LiteralPath $jsonc -PathType Leaf) { return $jsonc }
    }
    return $Path
}

# Maps the resolver's output to a SHORT, sanitized reasonCode (no host/baseURL).
function ConvertTo-ReasonCode {
    param([string]$Locality)
    switch ($Locality) {
        'local' { 'loopback-local' }
        'external' { 'external' }
        default { 'unknown' }
    }
}

function Get-ProviderFromModelKey {
    param([string]$TargetModelKey)
    if ([string]::IsNullOrWhiteSpace($TargetModelKey) -or $TargetModelKey -notmatch '/') { return 'unknown' }
    return @($TargetModelKey -split '/', 2)[0]
}

function Test-HardVetoModel {
    param([string]$TargetModelKey)
    if ([string]::IsNullOrWhiteSpace($TargetModelKey)) { return $false }
    $modelPart = @($TargetModelKey -split '/')[-1].ToLowerInvariant()
    foreach ($v in @('mistral-large-3', 'nemotron-3-ultra')) {
        if ($modelPart.Contains($v)) { return $true }
    }
    return $false
}

function New-CapabilityEntry {
    param(
        [Parameter(Mandatory)] [string]$Backend,
        [Parameter(Mandatory)] [string]$TargetModelKey,
        [string]$CanonicalModel,
        [string]$Provider,
        [string]$Family,
        [string]$Locality = 'unknown',
        [ValidateSet('configured', 'catalog', 'cache', 'historical', 'probe', 'cli')] [string]$SourceKind = 'configured',
        [ValidateSet('strong', 'medium', 'weak')] [string]$SourceConfidence = 'strong',
        [bool]$AvailableInManifest = $true,
        [string[]]$Diagnostics = @()
    )
    if ([string]::IsNullOrWhiteSpace($CanonicalModel)) { $CanonicalModel = $TargetModelKey }
    if ([string]::IsNullOrWhiteSpace($Provider)) { $Provider = Get-ProviderFromModelKey $CanonicalModel }
    if ([string]::IsNullOrWhiteSpace($Family)) { $Family = Get-LlmDelegateTargetFamily -TargetModelKey $CanonicalModel }
    if ([string]::IsNullOrWhiteSpace($Family)) { $Family = $Provider }
    [pscustomobject]@{
        backend             = $Backend
        targetModelKey      = $TargetModelKey
        canonicalModel      = $CanonicalModel
        provider            = $Provider
        family              = $Family
        sourceKind          = $SourceKind
        sourceConfidence    = $SourceConfidence
        availableInManifest = $AvailableInManifest
        locality            = $Locality
        reasonCode          = ConvertTo-ReasonCode $Locality
        hardVeto            = (Test-HardVetoModel $CanonicalModel)
        diagnostics         = @($Diagnostics | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
}

function Get-OpenCodeModelEntries {
    param([string]$ConfigPath)
    $entries = @()
    $ConfigPath = Resolve-OpenCodeConfigPath -Path $ConfigPath
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $entries }
    $cfg = $null
    try { $cfg = Read-JsonOrJsoncFile -Path $ConfigPath } catch { return $entries }
    $providers = Get-Prop $cfg 'provider'
    if ($null -eq $providers) { return $entries }
    foreach ($prop in $providers.PSObject.Properties) {
        $provName = $prop.Name
        $modelsNode = Get-Prop $prop.Value 'models'
        if ($null -eq $modelsNode) { continue }
        foreach ($modelProp in $modelsNode.PSObject.Properties) {
            $canonical = "$provName/$($modelProp.Name)"
            $locality = 'unknown'
            try {
                $resJson = & $openResolver -Model $canonical -ConfigPath $ConfigPath
                if ($resJson) {
                    $res = $resJson | ConvertFrom-Json
                    $locality = [string](Get-Prop $res 'locality')
                }
            } catch { $locality = 'unknown' }
            $entries += New-CapabilityEntry -Backend 'opencode' -TargetModelKey $canonical `
                -CanonicalModel $canonical -Provider $provName -Locality $locality `
                -SourceKind 'configured' -SourceConfidence 'strong' -AvailableInManifest $true
        }
    }
    return $entries
}

function Get-CodexProfileIds {
    param([string]$ConfigPath)
    $ids = @()
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $ids }
    foreach ($rawLine in (Get-Content -LiteralPath $ConfigPath -Encoding utf8)) {
        $m = [regex]::Match($rawLine.Trim(), '^\[profiles\.([^\]]+)\]')
        if ($m.Success) { $ids += $m.Groups[1].Value.Trim() }
    }
    return $ids
}

function Get-CodexModelEntries {
    param([string]$ConfigPath)
    $entries = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Each resolver invocation: $null = default (derives the top-level model from config);
    # otherwise, a declared profile. DIRECT call (no array splat, which does not
    # bind a named parameter reliably) and no nested function (which would break
    # `+=` by scope); the List mutates by reference via .Add().
    $profilesToProbe = @($null) + @(Get-CodexProfileIds -ConfigPath $ConfigPath)

    foreach ($profileId in $profilesToProbe) {
        try {
            if ([string]::IsNullOrWhiteSpace([string]$profileId)) {
                $resJson = & $codexResolver -ConfigPath $ConfigPath
            }
            else {
                $resJson = & $codexResolver -Profile $profileId -ConfigPath $ConfigPath
            }
            if (-not $resJson) { continue }
            $res = $resJson | ConvertFrom-Json
            $canonical = [string](Get-Prop $res 'canonicalModel')
            if ([string]::IsNullOrWhiteSpace($canonical)) { continue }
            $provider = [string](Get-Prop $res 'provider')
            if ([string]::IsNullOrWhiteSpace($provider) -or $canonical -notmatch '/') {
                if (-not $seen.Add("weak:$canonical")) { continue }
                $entries.Add((New-CapabilityEntry -Backend 'codex' -TargetModelKey $canonical `
                            -CanonicalModel $canonical -Provider 'unknown' -Locality 'unknown' `
                            -SourceKind 'configured' -SourceConfidence 'weak' -AvailableInManifest $true `
                            -Diagnostics @('destination provider not proven by the resolver; do not invent an openai prefix')))
                continue
            }
            if (-not $seen.Add($canonical)) { continue }
            $locality = [string](Get-Prop $res 'locality')
            $entries.Add((New-CapabilityEntry -Backend 'codex' -TargetModelKey $canonical `
                        -CanonicalModel $canonical -Provider $provider -Locality $locality `
                        -SourceKind 'configured' -SourceConfidence 'strong' -AvailableInManifest $true))
        } catch { }
    }
    return $entries
}

function Get-ClaudeCodeModelEntries {
    param([string]$SettingsPath, [string]$StatsCachePath)
    $entries = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($source in @(
            @{ path = $SettingsPath; kind = 'configured'; confidence = 'strong' }
            @{ path = $StatsCachePath; kind = 'historical'; confidence = 'weak' }
        )) {
        if (-not (Test-Path -LiteralPath $source.path -PathType Leaf)) { continue }
        $raw = Get-Content -LiteralPath $source.path -Raw -Encoding utf8
        $matches = [regex]::Matches($raw, '(?i)\b(claude-[a-z0-9][a-z0-9\-]*|opus)\b')
        foreach ($m in $matches) {
            $model = $m.Groups[1].Value
            try {
                $res = (& $claudeResolver -Model $model) | ConvertFrom-Json
                $canonical = [string](Get-Prop $res 'canonicalModel')
                if ([string]::IsNullOrWhiteSpace($canonical)) { continue }
                $seenKey = "$($source.kind):$canonical"
                if (-not $seen.Add($seenKey)) { continue }
                $diagnostics = @()
                if ($source.kind -eq 'historical') { $diagnostics += 'historical/weak source; does not prove current availability' }
                $entries.Add((New-CapabilityEntry -Backend 'claude-code' -TargetModelKey $canonical `
                            -CanonicalModel $canonical -Provider ([string](Get-Prop $res 'provider')) `
                            -Locality ([string](Get-Prop $res 'locality')) -SourceKind $source.kind `
                            -SourceConfidence $source.confidence -AvailableInManifest ($source.kind -ne 'historical') `
                            -Diagnostics $diagnostics))
            } catch { }
        }
    }
    return $entries
}

# --- Assembles the backends -------------------------------------------------

$backends = @()

$backends += [pscustomobject]@{
    backend     = 'opencode'
    installed   = (Test-CommandPresent 'opencode')
    enumeration = 'config'
    models      = @(Get-OpenCodeModelEntries -ConfigPath $OpenCodeConfigPath)
}

$backends += [pscustomobject]@{
    backend     = 'codex'
    installed   = (Test-CommandPresent 'codex')
    enumeration = 'config'
    models      = @(Get-CodexModelEntries -ConfigPath $CodexConfigPath)
}

$backends += [pscustomobject]@{
    backend     = 'claude-code'
    installed   = (Test-CommandPresent 'claude')
    enumeration = 'settings-or-historical'
    models      = @(Get-ClaudeCodeModelEntries -SettingsPath $ClaudeSettingsPath -StatsCachePath $ClaudeStatsCachePath)
}

function Get-AntigravityModelEntries {
    param([string]$AntigravityExe, [int]$ProbeTimeoutSec = 20)
    $entries = [System.Collections.Generic.List[object]]::new()
    $antigravityResolver = Join-Path $PSScriptRoot 'Resolve-AntigravityModelLocality.ps1'
    if (-not (Test-Path -LiteralPath $antigravityResolver -PathType Leaf)) { return $entries }

    $exe = $AntigravityExe
    if (-not $exe) {
        $supportScript = Join-Path $PSScriptRoot 'AntigravityCliSupport.ps1'
        if (Test-Path -LiteralPath $supportScript -PathType Leaf) {
            . $supportScript
            try { $exe = Resolve-AntigravityExe -SkipContractCheck } catch { }
        }
    }

    if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $entries }

    # `agy models` is the ONLY probe in this manifest that RUNS a CLI and waits for a network response
    # (opencode/codex/claude-code read a config file; copilot/gemini only check presence on PATH).
    # Without a time cap, a CLI that hangs - an expired token falling into an interactive login prompt,
    # slow network, service down - would hang the ENTIRE manifest, and with it the panel offer and
    # the setup workflow snapshot. Measured on 2026-08-06: 2.2s on the happy path (~80% of the
    # manifest's total time). A 20s cap = wide margin over that without becoming a lock. Timeout/error degrades
    # to an empty list -> enumeration=none-native, the same path already used when there are no models.
    # The cap is injectable (TEST-ONLY) only so the self-test can prove the cutoff without waiting 20s.
    $rawModels = @()
    $proc = $null
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $exe
        $psi.ArgumentList.Add('models')
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true    # closed right below: pure EOF, no hanging on a TTY
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.StandardInput.Close()
        # Drain BOTH pipes asynchronously before WaitForExit. stderr is not consumed,
        # but it must be read: a full pipe blocks the child process and the timeout would become
        # the rule instead of the exception.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $null = $proc.StandardError.ReadToEndAsync()

        if ($proc.WaitForExit($ProbeTimeoutSec * 1000)) {
            $rawOutput = $stdoutTask.GetAwaiter().GetResult()
            if ($proc.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($rawOutput)) {
                $rawModels = @($rawOutput -split "`r?`n" | Where-Object { $_ -match '^[a-z0-9][a-z0-9\-\.]+$' })
            }
        }
        else {
            try { $proc.Kill($true) } catch { }
        }
    } catch { }
    finally {
        if ($null -ne $proc) { try { $proc.Dispose() } catch { } }
    }

    if ($rawModels.Count -eq 0) {
        return $entries
    }

    foreach ($m in $rawModels) {
        try {
            $res = (& $antigravityResolver -Model $m) | ConvertFrom-Json
            $canonical = [string](Get-Prop $res 'canonicalModel')
            if ([string]::IsNullOrWhiteSpace($canonical)) { continue }
            $entries.Add((New-CapabilityEntry -Backend 'antigravity' -TargetModelKey $canonical `
                        -CanonicalModel $canonical -Provider ([string](Get-Prop $res 'provider')) `
                        -Family ([string](Get-Prop $res 'family')) `
                        -Locality ([string](Get-Prop $res 'locality')) -SourceKind 'cli' `
                        -SourceConfidence 'strong' -AvailableInManifest $true))
        } catch { }
    }
    return $entries
}

function Test-AntigravityPresent {
    param([string]$AntigravityExe)
    if ($AntigravityExe -and (Test-Path -LiteralPath $AntigravityExe -PathType Leaf)) { return $true }
    $supportScript = Join-Path $PSScriptRoot 'AntigravityCliSupport.ps1'
    if (Test-Path -LiteralPath $supportScript -PathType Leaf) {
        . $supportScript
        try { return [bool](Resolve-AntigravityExe -SkipContractCheck) } catch { return $false }
    }
    return (Test-CommandPresent 'agy')
}

foreach ($b in @(
        @{ name = 'copilot'; cmd = 'copilot' }
        @{ name = 'gemini'; cmd = 'gemini' }
    )) {
    $backends += [pscustomobject]@{
        backend     = $b.name
        installed   = (Test-CommandPresent $b.cmd)
        enumeration = 'none-native'
        models      = @()
    }
}

$isAgyInstalled = Test-AntigravityPresent -AntigravityExe $AntigravityExe
$agyModelEntries = @(Get-AntigravityModelEntries -AntigravityExe $AntigravityExe -ProbeTimeoutSec $AntigravityProbeTimeoutSec)
$hasAgyModels = ($agyModelEntries.Count -gt 0)

$backends += [pscustomobject]@{
    backend     = 'antigravity'
    installed   = $isAgyInstalled
    enumeration = if ($hasAgyModels) { 'cli' } else { 'none-native' }
    models      = [object[]]$agyModelEntries
}

$generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

$manifest = [pscustomobject]@{
    schemaVersion   = 1
    generatedAt     = $generatedAt
    backends        = $backends
    lastHealthCheck = $null
}

# --- Writes the machine-level manifest --------------------------------------

$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$manifestJson = $manifest | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $OutputPath -Value $manifestJson -Encoding utf8

# --- Optional per-KB snapshot (re-derivable cache) --------------------------

if (-not [string]::IsNullOrWhiteSpace($SnapshotPath)) {
    $snapDir = Split-Path -Parent $SnapshotPath
    if ($snapDir -and -not (Test-Path -LiteralPath $snapDir)) {
        New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    }
    $snapshot = [pscustomobject]@{
        schemaVersion     = 1
        snapshotAt        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        sourceGeneratedAt = $generatedAt
        backends          = $backends
        lastHealthCheck   = $null
    }
    Set-Content -LiteralPath $SnapshotPath -Value ($snapshot | ConvertTo-Json -Depth 8) -Encoding utf8
}

# Machine output: the manifest.
$manifestJson
