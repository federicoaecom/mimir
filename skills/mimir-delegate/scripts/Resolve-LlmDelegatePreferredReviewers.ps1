#requires -Version 7.4
<#
.SYNOPSIS
    Reads the curated preferred-reviewers list (schema 3) via orchestrator->machine cascade
    and cross-references it with the capability manifest.
.DESCRIPTION
    Part of the mimir-delegate skill mechanism; methodology in 15-peer-review.md.
    INVARIANT: preference != authorization. The Resolve-LlmDelegateAuthorization.ps1 gate
    re-evaluates per reviewer on send.

    Cascade (without -PreferredPath): preferred-reviewers.<orch>.json schema 3, otherwise machine
    preferred-reviewers.json schema 3. An effective file that is unreadable/schema!=3 -> exit 2
    (does not fall through to the next level). -PreferredPath bypass: only that file.

    From -Orchestrator validation onward, the envelope includes cascadeOrchestratorPath/
    cascadeMachinePath and cascadeOrchestratorExists/cascadeMachineExists (under PreferredRoot
    or default), so the agent edits the file this harness actually resolves — not just
    the machine one. A refusal before that validation (orchestrator missing or outside the
    allowed set) is emitted without these fields: with no valid orchestrator there is no cascade
    path to compute.

    When no state folder can be determined (LlmDelegateStatePath.ps1 throws), the resolver does
    not fail: the defaults that need it degrade. The capability manifest is treated as missing,
    the cascade reports no preferences (reason=no-preferred-file, preferenceSource=none, null
    cascade paths), and diagnostics carries one 'state-root-unavailable: <reason>' entry.
    Explicit -PreferredPath, -PreferredRoot and -CapabilitiesPath keep working.

    -Orchestrator required in the body: a slug (^[a-z0-9][a-z0-9-]{0,39}$, lowercased). Known
    harnesses: cursor|claude-code|codex|opencode; any other well-formed slug is accepted.
    A native primary reviewer under an unknown harness is diagnosed as unverifiable and must not count
    toward the diversity floor until the orchestrator confirms it.
    stdout=JSON; stderr=diagnostics.
.PARAMETER Orchestrator
    Orchestrator slug (trimmed, lowercased). Known harnesses: cursor|claude-code|codex|opencode;
    the list is open.
.PARAMETER PreferredRoot
    Default: the state root (%LOCALAPPDATA%\mimir-delegate on Windows; see LlmDelegateStatePath.ps1)
    (cascade).
.PARAMETER PreferredPath
    Explicit bypass with no default.
.PARAMETER CapabilitiesPath
    Default <state root>\capabilities.json, where the state root is the local application data
    folder plus mimir-delegate (%LOCALAPPDATA%\mimir-delegate on Windows, ~/.local/share/mimir-delegate
    on Linux; see LlmDelegateStatePath.ps1 for macOS and the fallbacks); not derived from PreferredRoot.
#>
[CmdletBinding()]
param(
    [string] $Orchestrator,
    [string] $PreferredRoot,
    [string] $PreferredPath,
    [string] $CapabilitiesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LlmDelegateTargetFamilySupport.ps1')
. (Join-Path $PSScriptRoot 'LlmDelegateStatePath.ps1')

# Default state root, resolved once. When it cannot be determined, the defaults that need it
# degrade (no default cascade root, capability manifest treated as missing) and one
# diagnostic records why, instead of failing the resolver.
$script:DefaultStateRoot = $null
$script:StateRootDiagnostic = $null
try {
    $script:DefaultStateRoot = Get-LlmDelegateStateRoot
}
catch {
    $script:StateRootDiagnostic = "state-root-unavailable: $($_.Exception.Message) Pass -PreferredRoot or -PreferredPath and -CapabilitiesPath, or set XDG_DATA_HOME or HOME."
}
$script:StateRootNeeded = $false

if (-not $PSBoundParameters.ContainsKey('CapabilitiesPath')) {
    if ($null -ne $script:DefaultStateRoot) {
        $CapabilitiesPath = Join-Path $script:DefaultStateRoot 'capabilities.json'
    }
    else {
        $CapabilitiesPath = $null
        $script:StateRootNeeded = $true
    }
}

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and -not [string]::IsNullOrEmpty($Name) -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function Write-ErrDiag {
    param([string]$Message)
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        [Console]::Error.WriteLine($Message)
    }
}

function Emit-ResolveResult {
    param([hashtable]$Fields, [int]$ExitCode = 0)
    $cascadeVar = Get-Variable -Scope Script -Name CascadeMeta -ErrorAction SilentlyContinue
    if ($null -ne $cascadeVar -and $null -ne $cascadeVar.Value) {
        foreach ($k in @($cascadeVar.Value.Keys)) {
            if (-not $Fields.ContainsKey($k)) {
                $Fields[$k] = $cascadeVar.Value[$k]
            }
        }
    }
    ([pscustomobject]$Fields) | ConvertTo-Json -Depth 12
    exit $ExitCode
}

function Stop-WithReason {
    param(
        [string]$Reason,
        [int]$ExitCode,
        [string]$Detail = '',
        [hashtable]$Extra = @{}
    )
    Write-ErrDiag $Detail
    $fields = @{
        hasPreferences         = $false
        reason                 = $Reason
        schemaVersion          = $null
        preferenceSource       = $null
        effectivePreferredPath = $null
        orchestrator           = $null
        calibratedBy           = $null
        fallbackPolicy         = $null
        diagnostics            = @()
        reviewers              = @()
        note                   = $script:Note
        updatedAt              = $null
    }
    foreach ($k in $Extra.Keys) { $fields[$k] = $Extra[$k] }
    Emit-ResolveResult -Fields $fields -ExitCode $ExitCode
}

$script:Note = 'Composition suggestion; NOT authorization. The Resolve-LlmDelegateAuthorization.ps1 gate re-evaluates destination+sensitivity PER REVIEWER on send. availableInManifest is best-effort: the manifest may not enumerate opencode (minimal config).'
$allowedDispatchBackends = @('opencode', 'codex', 'claude-code', 'copilot', 'gemini', 'antigravity')
$allowedNativeBackends = @('orchestrator-native')
$supportedFallbackActivateOn = @('quota', 'timeout', 'error', 'unavailable')

function Get-Family {
    param([string]$TargetModelKey)
    return Get-LlmDelegateTargetFamily -TargetModelKey $TargetModelKey
}

function Get-ManifestModelMap {
    param([string]$Path)
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $map }
    try {
        $cap = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($b in @(Get-Prop $cap 'backends')) {
            foreach ($m in @(Get-Prop $b 'models')) {
                $cm = [string](Get-Prop $m 'canonicalModel')
                if (-not [string]::IsNullOrWhiteSpace($cm)) { $map[$cm] = $m }
            }
        }
    } catch { }
    return $map
}

function Test-HardVetoTarget {
    param([string]$TargetModelKey)
    if ([string]::IsNullOrWhiteSpace($TargetModelKey)) { return $false }
    $modelPart = @($TargetModelKey -split '/')[-1].ToLowerInvariant()
    foreach ($v in @('mistral-large-3', 'nemotron-3-ultra')) {
        if ($modelPart.Contains($v)) { return $true }
    }
    return $false
}

function Assert-ValidRankSet {
    param([object[]]$Reviewers)
    $seenRanks = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($reviewer in @($Reviewers)) {
        $rank = [int](Get-Prop $reviewer 'rank')
        if ($rank -lt 1) {
            Stop-WithReason -Reason 'rank-invalid' -ExitCode 3 -Detail "invalid rank ($rank)"
        }
        if (-not $seenRanks.Add($rank)) {
            Stop-WithReason -Reason 'rank-duplicate' -ExitCode 3 -Detail "duplicate rank ($rank)"
        }
    }
}

function ConvertTo-SupportedFallbackPolicy {
    param($Policy)
    if ($null -eq $Policy) { return $null }
    $mode = [string](Get-Prop $Policy 'mode')
    if ($mode -ne 'ordered-chain') {
        Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail "fallbackPolicy.mode='$mode'"
    }
    $activateOn = @(Get-Prop $Policy 'defaultActivateOn' | ForEach-Object { [string]$_ })
    if ($activateOn.Count -ne $supportedFallbackActivateOn.Count) {
        Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail 'defaultActivateOn outside the contract'
    }
    for ($i = 0; $i -lt $supportedFallbackActivateOn.Count; $i++) {
        if ($activateOn[$i] -ne $supportedFallbackActivateOn[$i]) {
            Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail 'defaultActivateOn invalid order'
        }
    }
    $gateAsk = [string](Get-Prop $Policy 'gateAskBehavior')
    if ($gateAsk -ne 'ask-human') {
        Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail "gateAskBehavior='$gateAsk'"
    }
    $gateDeny = [string](Get-Prop $Policy 'gateDenyBehavior')
    if ($gateDeny -ne 'stop-or-suggest-manual-alternative') {
        Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail "gateDenyBehavior='$gateDeny'"
    }
    return [pscustomobject]@{
        mode              = 'ordered-chain'
        defaultActivateOn = @($supportedFallbackActivateOn)
        gateAskBehavior   = 'ask-human'
        gateDenyBehavior  = 'stop-or-suggest-manual-alternative'
    }
}

function Assert-ReviewerValid {
    param($Reviewer, [string]$OwnerLabel)
    $backend = [string](Get-Prop $Reviewer 'backend')
    $target = [string](Get-Prop $Reviewer 'targetModelKey')
    $invokeArgs = Get-Prop $Reviewer 'invokeArgs'
    if ([string]::IsNullOrWhiteSpace($backend) -or [string]::IsNullOrWhiteSpace($target) -or $null -eq $invokeArgs) {
        Stop-WithReason -Reason 'reviewer-incomplete' -ExitCode 3 -Detail "$OwnerLabel incomplete"
    }
    $invBackend = [string](Get-Prop $invokeArgs 'backend')
    if (-not [string]::IsNullOrWhiteSpace($invBackend) -and $invBackend -ne $backend) {
        Stop-WithReason -Reason 'invoke-args-backend-divergent' -ExitCode 3 -Detail "$OwnerLabel invokeArgs.backend diverge"
    }
    if (Test-HardVetoTarget -TargetModelKey $target) {
        Stop-WithReason -Reason 'hard-veto' -ExitCode 3 -Detail "$OwnerLabel hard veto: $target"
    }
}

function ConvertTo-ResolvedReviewer {
    param($Reviewer, $ManifestMap, [int]$DefaultRank, [string]$PreferenceSource)
    Assert-ReviewerValid -Reviewer $Reviewer -OwnerLabel 'preferred reviewer'
    $backend = [string](Get-Prop $Reviewer 'backend')
    $target = [string](Get-Prop $Reviewer 'targetModelKey')
    $isNative = ($allowedNativeBackends -contains $backend)
    $typeRaw = Get-Prop $Reviewer 'type'
    $type = if ($null -ne $typeRaw -and -not [string]::IsNullOrWhiteSpace([string]$typeRaw)) {
        [string]$typeRaw
    } elseif ($isNative) {
        'orchestrator-native-subagent'
    } else {
        'delegation-cli'
    }
    $rankValue = Get-Prop $Reviewer 'rank'
    $rank = if ($null -ne $rankValue) { [int]$rankValue } else { $DefaultRank }
    $effortRaw = Get-Prop $Reviewer 'reasoningEffort'
    $effort = if ($null -eq $effortRaw -or [string]::IsNullOrWhiteSpace([string]$effortRaw)) { 'unset' } else { [string]$effortRaw }
    $harnessRaw = Get-Prop $Reviewer 'harnessModelId'
    $harnessId = if ($isNative) {
        if ($null -eq $harnessRaw -or [string]::IsNullOrWhiteSpace([string]$harnessRaw)) {
            Stop-WithReason -Reason 'native-harness-model-id-missing' -ExitCode 3 -Detail 'harnessModelId missing for native'
        }
        ([string]$harnessRaw).Trim()
    } else {
        $null
    }

    # Same contract as the writer (Set-): a Cursor harness key is only valid as a native primary reviewer
    # with a known Creator. A file hand-edited with it under a CLI backend would hand the panel
    # an undispatchable primary reviewer, so the read also refuses fail-closed.
    if (Test-LlmDelegateCursorHarnessKey -TargetModelKey $target) {
        $cursorFamily = Get-Family $target
        if (-not $isNative -or -not (Test-LlmDelegateFamilyKnown -Family $cursorFamily)) {
            Stop-WithReason -Reason 'native-cursor-prefix' -ExitCode 3 -Detail "targetModelKey='$target'"
        }
    }

    # Same contract as the writer (Set-): a native primary reviewer belongs to the harness that runs it,
    # so a hand-edited machine file with a native entry, or a native key that names another
    # harness, is refused fail-closed instead of reaching the panel as a phantom voice.
    if ($isNative -and $PreferenceSource -eq 'machine') {
        Stop-WithReason -Reason 'native-machine-scope-forbidden' -ExitCode 3 -Detail "native primary reviewer in the machine file; targetModelKey='$target'"
    }
    if ($isNative) {
        $keyHarness = Get-LlmDelegateKeyHarness -TargetModelKey $target
        if ($null -ne $keyHarness -and -not $keyHarness.Equals($orchTrim, [System.StringComparison]::OrdinalIgnoreCase)) {
            Stop-WithReason -Reason 'native-harness-orchestrator-mismatch' -ExitCode 3 -Detail "harness key '$keyHarness' under orchestrator '$orchTrim'; targetModelKey='$target'"
        }
    }

    $manifestEntry = $ManifestMap[$target]
    $available = ($null -ne $manifestEntry)
    $diagnostics = [System.Collections.Generic.List[string]]::new()
    # Open orchestrator list: for a harness this repository cannot identify, the native primary reviewer
    # cannot be verified here. Diagnostic only (same mechanism as the mismatch one above): the
    # orchestrator must confirm it before passing the candidate with countsForDiversity=true.
    if ($isNative -and -not (Test-LlmDelegateOrchestratorKnown -Orchestrator $orchTrim)) {
        $diagnostics.Add("orchestrator '$orchTrim' is not a known harness; this native primary reviewer is unverifiable for it — do not count it toward the floor (countsForDiversity=false) until the orchestrator confirms it offers this model")
    }

    if (-not $available) { $diagnostics.Add('availableInManifest=false; diagnostic, not a gate block') }
    elseif ((Get-Prop $manifestEntry 'sourceConfidence') -eq 'weak') { $diagnostics.Add('capability sourceConfidence=weak') }

    $chainOut = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$seen.Add("$backend|$target")
    $fallbackIndex = 0
    $fallbackItems = Get-Prop $Reviewer 'fallbackChain'
    if ($null -eq $fallbackItems) { $fallbackItems = @() }
    if ($isNative -and @($fallbackItems).Count -gt 0) {
        Stop-WithReason -Reason 'native-fallback-chain-forbidden' -ExitCode 3 -Detail 'native with fallbackChain'
    }
    foreach ($fb in @($fallbackItems)) {
        Assert-ReviewerValid -Reviewer $fb -OwnerLabel "fallbackChain[$fallbackIndex] of $target"
        $fbBackend = [string](Get-Prop $fb 'backend')
        $fbTarget = [string](Get-Prop $fb 'targetModelKey')
        if ($allowedNativeBackends -contains $fbBackend) {
            Stop-WithReason -Reason 'native-fallback-chain-forbidden' -ExitCode 3 -Detail "native as chain link: $fbTarget"
        }
        # A chain link is always CLI: no Cursor harness spelling is dispatchable here.
        if (Test-LlmDelegateCursorHarnessKey -TargetModelKey $fbTarget) {
            Stop-WithReason -Reason 'native-cursor-prefix' -ExitCode 3 -Detail "fallback targetModelKey='$fbTarget'"
        }
        $key = "$fbBackend|$fbTarget"
        if (-not $seen.Add($key)) {
            Stop-WithReason -Reason 'fallback-cycle' -ExitCode 3 -Detail "cycle involving $fbTarget"
        }
        $fbManifest = $ManifestMap[$fbTarget]
        $fbAvailable = ($null -ne $fbManifest)
        $fbDiagnostics = [System.Collections.Generic.List[string]]::new()
        if (-not $fbAvailable) { $fbDiagnostics.Add('availableInManifest=false; diagnostic, not a gate block') }
        elseif ((Get-Prop $fbManifest 'sourceConfidence') -eq 'weak') { $fbDiagnostics.Add('capability sourceConfidence=weak') }
        $chainOut.Add([pscustomobject]@{
                backend             = $fbBackend
                targetModelKey      = $fbTarget
                invokeArgs          = (Get-Prop $fb 'invokeArgs')
                family              = Get-Family $fbTarget
                rank                = $rank
                fallbackIndex       = $fallbackIndex
                fallbackOf          = $target
                reason              = [string](Get-Prop $fb 'reason')
                availableInManifest = $fbAvailable
                capability          = $fbManifest
                diagnostics         = @($fbDiagnostics)
                type                = 'delegation-cli'
                harnessModelId      = $null
                reasoningEffort     = 'unset'
            })
        $fallbackIndex++
    }

    [pscustomobject]@{
        backend             = $backend
        targetModelKey      = $target
        invokeArgs          = (Get-Prop $Reviewer 'invokeArgs')
        family              = Get-Family $target
        rank                = $rank
        fallbackChain       = @($chainOut)
        availableInManifest = $available
        capability          = $manifestEntry
        diagnostics         = @($diagnostics)
        type                = $type
        harnessModelId      = $harnessId
        reasoningEffort     = $effort
    }
}

function Get-DefaultPreferredRoot {
    return $script:DefaultStateRoot
}

function New-CascadeMeta {
    param(
        [AllowNull()][string]$Root,
        [string]$Orchestrator
    )
    if ([string]::IsNullOrWhiteSpace($Root)) {
        # No state root and no -PreferredRoot: there is no cascade path to report.
        return [ordered]@{
            cascadeOrchestratorPath   = $null
            cascadeMachinePath        = $null
            cascadeOrchestratorExists = $false
            cascadeMachineExists      = $false
        }
    }
    $orchPath = [System.IO.Path]::GetFullPath((Join-Path $Root "preferred-reviewers.$Orchestrator.json"))
    $machinePath = [System.IO.Path]::GetFullPath((Join-Path $Root 'preferred-reviewers.json'))
    return [ordered]@{
        cascadeOrchestratorPath   = $orchPath
        cascadeMachinePath        = $machinePath
        cascadeOrchestratorExists = [bool](Test-Path -LiteralPath $orchPath -PathType Leaf)
        cascadeMachineExists      = [bool](Test-Path -LiteralPath $machinePath -PathType Leaf)
    }
}

function Read-PreferredDocument {
    param(
        [string]$Path,
        [string]$PreferenceSource,
        [string]$OrchestratorExpected,
        [bool]$RequireOrchestratorMatch,
        [System.Collections.Generic.List[string]]$Diagnostics
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    $pref = $null
    try {
        $pref = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        Stop-WithReason -Reason 'preferred-file-unreadable' -ExitCode 2 -Detail $_.Exception.Message -Extra @{
            preferenceSource       = $PreferenceSource
            effectivePreferredPath = [System.IO.Path]::GetFullPath($Path)
            diagnostics            = @($Diagnostics)
        }
    }
    $sv = Get-Prop $pref 'schemaVersion'
    if ($null -eq $sv -or [int]$sv -ne 3) {
        Stop-WithReason -Reason 'preferred-schema-unsupported' -ExitCode 2 -Detail "schemaVersion='$sv' in $Path; rewrite with Set- schema 3" -Extra @{
            preferenceSource       = $PreferenceSource
            effectivePreferredPath = [System.IO.Path]::GetFullPath($Path)
            schemaVersion          = $sv
            diagnostics            = @($Diagnostics)
        }
    }
    $fileOrch = [string](Get-Prop $pref 'orchestrator')
    if ($RequireOrchestratorMatch) {
        if ([string]::IsNullOrWhiteSpace($fileOrch) -or -not $fileOrch.Equals($OrchestratorExpected, [System.StringComparison]::OrdinalIgnoreCase)) {
            Stop-WithReason -Reason 'orchestrator-mismatch' -ExitCode 2 -Detail "file orchestrator='$fileOrch' vs '$OrchestratorExpected'" -Extra @{
                preferenceSource       = $PreferenceSource
                effectivePreferredPath = [System.IO.Path]::GetFullPath($Path)
                schemaVersion          = 3
                orchestrator           = $fileOrch
                diagnostics            = @($Diagnostics)
            }
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($fileOrch)) {
        if (-not $fileOrch.Equals($OrchestratorExpected, [System.StringComparison]::OrdinalIgnoreCase)) {
            Stop-WithReason -Reason 'orchestrator-mismatch' -ExitCode 2 -Detail "field orchestrator='$fileOrch' vs '$OrchestratorExpected'" -Extra @{
                preferenceSource       = $PreferenceSource
                effectivePreferredPath = [System.IO.Path]::GetFullPath($Path)
                schemaVersion          = 3
                orchestrator           = $fileOrch
                diagnostics            = @($Diagnostics)
            }
        }
    }
    return $pref
}

function Emit-ResolvedDocument {
    param(
        $Pref,
        [string]$PreferenceSource,
        [string]$EffectivePath,
        [string]$CapabilitiesPath,
        [System.Collections.Generic.List[string]]$Diagnostics
    )
    $fallbackPolicy = ConvertTo-SupportedFallbackPolicy -Policy (Get-Prop $Pref 'fallbackPolicy')
    $manifestMap = Get-ManifestModelMap -Path $CapabilitiesPath
    $reviewers = @(Get-Prop $Pref 'reviewers')
    $out = [System.Collections.Generic.List[object]]::new()
    $rankCounter = 0
    foreach ($r in $reviewers) {
        $rankCounter++
        $out.Add((ConvertTo-ResolvedReviewer -Reviewer $r -ManifestMap $manifestMap -DefaultRank $rankCounter -PreferenceSource $PreferenceSource))
    }
    $outSorted = @($out | Sort-Object -Property @{ Expression = { [int](Get-Prop $_ 'rank') } }, @{ Expression = { [string](Get-Prop $_ 'targetModelKey') } })
    Assert-ValidRankSet -Reviewers $outSorted

    $updatedAtRaw = Get-Prop $Pref 'updatedAt'
    $updatedAtOut = if ($updatedAtRaw -is [datetime]) {
        $updatedAtRaw.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    } else {
        [string]$updatedAtRaw
    }

    Emit-ResolveResult -ExitCode 0 -Fields @{
        hasPreferences         = $true
        reason                 = $null
        schemaVersion          = 3
        preferenceSource       = $PreferenceSource
        effectivePreferredPath = [System.IO.Path]::GetFullPath($EffectivePath)
        orchestrator           = Get-Prop $Pref 'orchestrator'
        calibratedBy           = Get-Prop $Pref 'calibratedBy'
        fallbackPolicy         = $fallbackPolicy
        diagnostics            = @($Diagnostics)
        reviewers              = @($outSorted)
        note                   = $script:Note
        updatedAt              = $updatedAtOut
    }
}

# --- params ---
$orchTrim = if ($null -eq $Orchestrator) { '' } else { $Orchestrator.Trim() }
if ([string]::IsNullOrWhiteSpace($orchTrim)) {
    Stop-WithReason -Reason 'orchestrator-required' -ExitCode 1
}
# Open allow-list: any well-formed slug (normalized to lowercase) names an orchestrator.
$orchSlug = ConvertTo-LlmDelegateOrchestratorSlug -Orchestrator $orchTrim
if ($null -eq $orchSlug) {
    Stop-WithReason -Reason 'orchestrator-invalid' -ExitCode 1 -Detail "orchestrator='$orchTrim' (expected ^[a-z0-9][a-z0-9-]{0,39}$)"
}
$orchTrim = $orchSlug

$script:CascadeMeta = New-CascadeMeta -Root (Get-DefaultPreferredRoot) -Orchestrator $orchTrim

$hasPreferredPath = $PSBoundParameters.ContainsKey('PreferredPath') -and -not [string]::IsNullOrWhiteSpace($PreferredPath)
$hasPreferredRoot = $PSBoundParameters.ContainsKey('PreferredRoot')
if ($hasPreferredPath -and $hasPreferredRoot) {
    Stop-WithReason -Reason 'preferred-path-mode-conflict' -ExitCode 1
}

$diagnostics = [System.Collections.Generic.List[string]]::new()

$root = if ($hasPreferredRoot -and -not [string]::IsNullOrWhiteSpace($PreferredRoot)) {
    [System.IO.Path]::GetFullPath($PreferredRoot)
} else {
    Get-DefaultPreferredRoot
}
if (-not $hasPreferredPath -and $null -eq $root) {
    $script:StateRootNeeded = $true
}
if ($script:StateRootNeeded -and $null -ne $script:StateRootDiagnostic) {
    $diagnostics.Add($script:StateRootDiagnostic)
}

if ($hasPreferredPath) {
    $fullPath = [System.IO.Path]::GetFullPath($PreferredPath)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Emit-ResolveResult -ExitCode 0 -Fields @{
            hasPreferences         = $false
            reason                 = 'no-preferred-file'
            schemaVersion          = $null
            preferenceSource       = 'explicit-path'
            effectivePreferredPath = $fullPath
            orchestrator           = $null
            calibratedBy           = $null
            fallbackPolicy         = $null
            diagnostics            = @($diagnostics)
            reviewers              = @()
            note                   = $script:Note
            updatedAt              = $null
        }
    }
    $pref = Read-PreferredDocument -Path $fullPath -PreferenceSource 'explicit-path' `
        -OrchestratorExpected $orchTrim -RequireOrchestratorMatch:$false -Diagnostics $diagnostics
    Emit-ResolvedDocument -Pref $pref -PreferenceSource 'explicit-path' -EffectivePath $fullPath `
        -CapabilitiesPath $CapabilitiesPath -Diagnostics $diagnostics
}

$script:CascadeMeta = New-CascadeMeta -Root $root -Orchestrator $orchTrim
$orchPath = $script:CascadeMeta.cascadeOrchestratorPath
$machinePath = $script:CascadeMeta.cascadeMachinePath

if ($null -eq $root) {
    # No state root and no -PreferredRoot: no cascade file can be read (diagnostic added above).
    Emit-ResolveResult -ExitCode 0 -Fields @{
        hasPreferences         = $false
        reason                 = 'no-preferred-file'
        schemaVersion          = $null
        preferenceSource       = 'none'
        effectivePreferredPath = $null
        orchestrator           = $null
        calibratedBy           = $null
        fallbackPolicy         = $null
        diagnostics            = @($diagnostics)
        reviewers              = @()
        note                   = $script:Note
        updatedAt              = $null
    }
}

if (Test-Path -LiteralPath $orchPath -PathType Leaf) {
    $pref = Read-PreferredDocument -Path $orchPath -PreferenceSource 'orchestrator' `
        -OrchestratorExpected $orchTrim -RequireOrchestratorMatch:$true -Diagnostics $diagnostics
    Emit-ResolvedDocument -Pref $pref -PreferenceSource 'orchestrator' -EffectivePath $orchPath `
        -CapabilitiesPath $CapabilitiesPath -Diagnostics $diagnostics
}

$diagnostics.Add('orchestrator-file-absent')

if (Test-Path -LiteralPath $machinePath -PathType Leaf) {
    $pref = Read-PreferredDocument -Path $machinePath -PreferenceSource 'machine' `
        -OrchestratorExpected $orchTrim -RequireOrchestratorMatch:$false -Diagnostics $diagnostics
    Emit-ResolvedDocument -Pref $pref -PreferenceSource 'machine' -EffectivePath $machinePath `
        -CapabilitiesPath $CapabilitiesPath -Diagnostics $diagnostics
}

Emit-ResolveResult -ExitCode 0 -Fields @{
    hasPreferences         = $false
    reason                 = 'no-preferred-file'
    schemaVersion          = $null
    preferenceSource       = 'none'
    effectivePreferredPath = $null
    orchestrator           = $null
    calibratedBy           = $null
    fallbackPolicy         = $null
    diagnostics            = @($diagnostics)
    reviewers              = @()
    note                   = $script:Note
    updatedAt              = $null
}
