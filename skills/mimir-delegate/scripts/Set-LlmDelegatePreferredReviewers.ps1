#requires -Version 7.4
<#
.SYNOPSIS
    Writes the CURATED preferred-reviewers list (schema 3), at machine or orchestrator scope.
.DESCRIPTION
    Part of the mimir-delegate skill mechanism; methodology in 15-peer-review.md.
    Preference != authorization. Schema 3: delegation-cli (6 CLI backends) and
    orchestrator-native-subagent (orchestrator-native backend). Path cascade via
    -PreferredRoot/-Orchestrator/-Scope, or -OutputPath bypass (mutually exclusive).
    -Orchestrator/-Scope/-ReviewersJson required in the body. stdout=JSON; stderr=diagnostics.
.PARAMETER ReviewersJson
    Array of primary reviewers OR { reviewers, schemaVersion?, fallbackPolicy? }. A schemaVersion other
    than 3 is refused (reviewers-schema-unsupported).
.PARAMETER Orchestrator
    Orchestrator slug (trimmed, lowercased, ^[a-z0-9][a-z0-9-]{0,39}$). Known harnesses:
    cursor|claude-code|codex|opencode; any other well-formed slug is accepted (open list).
.PARAMETER Scope
    machine|orchestrator. When editing "this harness's" list, prefer orchestrator
    when Resolve already uses preferred-reviewers.<orch>.json; machine only on an
    explicit "machine list" request. stdout includes sibling* and harnessResolveReadsThisPath
    to detect a machine write shadowed by the orchestrator's file; these fields
    are emitted both on success and on the overwrite-required refusal, so the shadowing
    signal already shows up on the first attempt, before -Overwrite.
.PARAMETER PreferredRoot
    Default: the state root (%LOCALAPPDATA%\mimir-delegate on Windows; see LlmDelegateStatePath.ps1)
    (cascade).
.PARAMETER OutputPath
    Explicit bypass with no default.
.PARAMETER Preview
    Validates and emits without writing.
.PARAMETER Overwrite
    Writes over a valid schema 3 target.
#>
[CmdletBinding()]
param(
    [string] $ReviewersJson,
    [string] $Orchestrator,
    [string] $Scope,
    [string] $PreferredRoot,
    [string] $OutputPath,
    [switch] $Preview,
    [switch] $Overwrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LlmDelegateTargetFamilySupport.ps1')
. (Join-Path $PSScriptRoot 'LlmDelegateStatePath.ps1')

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

function Emit-SetResult {
    param([hashtable]$Fields, [int]$ExitCode = 0)
    ([pscustomobject]$Fields) | ConvertTo-Json -Depth 12 -Compress
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
        written                = 0
        discardedVeto          = @()
        reason                 = $Reason
        effectivePreferredPath = $null
        outputPath             = $null
        preview                = [bool]$Preview
        document               = $null
    }
    foreach ($k in $Extra.Keys) { $fields[$k] = $Extra[$k] }
    Emit-SetResult -Fields $fields -ExitCode $ExitCode
}

$hardVetoPatterns = @('mistral-large-3', 'nemotron-3-ultra')
$allowedDispatchBackends = @('opencode', 'codex', 'claude-code', 'copilot', 'gemini', 'antigravity')
$allowedNativeBackends = @('orchestrator-native')
$allowedScopes = @('machine', 'orchestrator')
$allowedInvokeArgs = @('backend', 'model', 'profile', 'localProvider', 'oss', 'timeoutSec')
$allowedReasoningEffort = @('unset', 'low', 'medium', 'high', 'xhigh')
$allowedPrimaryReviewerProps = @('type', 'backend', 'targetModelKey', 'harnessModelId', 'reasoningEffort', 'rank', 'invokeArgs', 'fallbackChain')
$allowedFallbackProps = @('backend', 'targetModelKey', 'invokeArgs', 'reason')
$allowedWrapperProps = @('reviewers', 'schemaVersion', 'fallbackPolicy')
$supportedFallbackActivateOn = @('quota', 'timeout', 'error', 'unavailable')

function Test-HardVetoTarget {
    param([string]$TargetModelKey)
    if ([string]::IsNullOrWhiteSpace($TargetModelKey)) { return $false }
    $modelPart = @($TargetModelKey -split '/')[-1]
    foreach ($v in $hardVetoPatterns) {
        if ($modelPart.ToLowerInvariant().Contains($v)) { return $true }
    }
    return $false
}

function Assert-KnownProperties {
    param($Obj, [string[]]$Allowed, [string]$Context)
    if ($null -eq $Obj) { return }
    foreach ($p in @($Obj.PSObject.Properties)) {
        if ($Allowed -notcontains $p.Name) {
            Stop-WithReason -Reason 'unknown-property' -ExitCode 3 -Detail "$Context extra property: $($p.Name)"
        }
    }
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
    if ($null -eq $Policy) {
        return [pscustomobject]@{
            mode              = 'ordered-chain'
            defaultActivateOn = @($supportedFallbackActivateOn)
            gateAskBehavior   = 'ask-human'
            gateDenyBehavior  = 'stop-or-suggest-manual-alternative'
        }
    }
    $mode = [string](Get-Prop $Policy 'mode')
    if ($mode -ne 'ordered-chain') {
        Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail "fallbackPolicy.mode='$mode'"
    }
    $activateOn = @(Get-Prop $Policy 'defaultActivateOn' | ForEach-Object { [string]$_ })
    if ($activateOn.Count -ne $supportedFallbackActivateOn.Count) {
        Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail 'fallbackPolicy.defaultActivateOn outside the contract'
    }
    for ($i = 0; $i -lt $supportedFallbackActivateOn.Count; $i++) {
        if ($activateOn[$i] -ne $supportedFallbackActivateOn[$i]) {
            Stop-WithReason -Reason 'fallback-policy-invalid' -ExitCode 3 -Detail 'fallbackPolicy.defaultActivateOn invalid order'
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

function Copy-SanitizedInvokeArgs {
    param($InvokeArgs, [string]$Backend, [string]$TargetModelKey)
    $invClean = [ordered]@{}
    $invBackend = [string](Get-Prop $InvokeArgs 'backend')
    if (-not [string]::IsNullOrWhiteSpace($invBackend) -and $invBackend -ne $Backend) {
        Stop-WithReason -Reason 'invoke-args-backend-divergent' -ExitCode 3 -Detail "invokeArgs.backend='$invBackend' vs backend='$Backend'"
    }
    $invClean['backend'] = $Backend
    foreach ($f in $allowedInvokeArgs) {
        if ($f -eq 'backend') { continue }
        $val = Get-Prop $InvokeArgs $f
        if ($null -eq $val) { continue }
        if ($f -eq 'oss') {
            if ($val -is [bool] -and $val) { $invClean[$f] = $true }
            continue
        }
        if ($f -eq 'timeoutSec') {
            $invClean[$f] = [int]$val
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$val)) { $invClean[$f] = [string]$val }
    }
    if (-not $invClean.Contains('model')) {
        $modelPart = @($TargetModelKey -split '/')[-1]
        $invClean['model'] = if ($Backend -eq 'opencode') { $TargetModelKey } else { $modelPart }
    }
    return [pscustomobject]$invClean
}

function Resolve-PrimaryReviewerType {
    param([string]$Backend, $TypeRaw)
    $isNative = $allowedNativeBackends -contains $Backend
    $isCli = $allowedDispatchBackends -contains $Backend
    if (-not $isNative -and -not $isCli) {
        Stop-WithReason -Reason 'backend-not-allowed' -ExitCode 3 -Detail "backend='$Backend'"
    }
    $inferred = if ($isNative) { 'orchestrator-native-subagent' } else { 'delegation-cli' }
    if ($null -eq $TypeRaw -or [string]::IsNullOrWhiteSpace([string]$TypeRaw)) {
        return $inferred
    }
    $t = [string]$TypeRaw
    if ($t -ne 'delegation-cli' -and $t -ne 'orchestrator-native-subagent') {
        Stop-WithReason -Reason 'unknown-property' -ExitCode 3 -Detail "type='$t'"
    }
    if (($t -eq 'delegation-cli' -and -not $isCli) -or ($t -eq 'orchestrator-native-subagent' -and -not $isNative)) {
        Stop-WithReason -Reason 'type-backend-divergent' -ExitCode 3 -Detail "type='$t' backend='$Backend'"
    }
    return $t
}

function ConvertTo-ReviewerV3 {
    param($Item, [int]$DefaultRank)
    Assert-KnownProperties -Obj $Item -Allowed $allowedPrimaryReviewerProps -Context 'primary reviewer'

    $backend = [string](Get-Prop $Item 'backend')
    $target = [string](Get-Prop $Item 'targetModelKey')

    $invokeArgs = Get-Prop $Item 'invokeArgs'
    if ([string]::IsNullOrWhiteSpace($backend) -or [string]::IsNullOrWhiteSpace($target) -or $null -eq $invokeArgs) {
        Stop-WithReason -Reason 'reviewer-incomplete' -ExitCode 3 -Detail 'backend/targetModelKey/invokeArgs required'
    }

    $type = Resolve-PrimaryReviewerType -Backend $backend -TypeRaw (Get-Prop $Item 'type')
    $isNative = ($type -eq 'orchestrator-native-subagent')

    # A Cursor harness key is legitimate ONLY as a native primary reviewer and with a known Creator
    # (cursor/grok-* and cursor-grok-* -> xai; cursor/composer-* and cursor-composer-* -> anysphere).
    # As a CLI target it would be an undispatchable primary reviewer; with an unknown Creator it would not count toward the floor.
    if (Test-LlmDelegateCursorHarnessKey -TargetModelKey $target) {
        $cursorFamily = Get-LlmDelegateTargetFamily -TargetModelKey $target
        if (-not $isNative -or -not (Test-LlmDelegateFamilyKnown -Family $cursorFamily)) {
            Stop-WithReason -Reason 'native-cursor-prefix' -ExitCode 3 -Detail "targetModelKey='$target'"
        }
    }
    if (Test-HardVetoTarget -TargetModelKey $target) {
        Stop-WithReason -Reason 'hard-veto' -ExitCode 3 -Detail "hard veto: $target"
    }

    $effortRaw = Get-Prop $Item 'reasoningEffort'
    $effort = if ($null -eq $effortRaw -or [string]::IsNullOrWhiteSpace([string]$effortRaw)) { 'unset' } else { [string]$effortRaw }
    if ($allowedReasoningEffort -notcontains $effort) {
        Stop-WithReason -Reason 'unknown-property' -ExitCode 3 -Detail "reasoningEffort='$effort'"
    }

    $rankValue = Get-Prop $Item 'rank'
    $rank = if ($null -ne $rankValue) { [int]$rankValue } else { $DefaultRank }
    $harnessRaw = Get-Prop $Item 'harnessModelId'
    $chainOut = [System.Collections.Generic.List[object]]::new()

    if ($isNative) {
        # harnessModelId is an id INSIDE a harness: a native primary reviewer belongs to the orchestrator,
        # not to the machine. At machine scope it would be resolved by another orchestrator as if
        # it were its own native — a ghost voice that would still count toward the diversity floor.
        if ($scopeTrim -eq 'machine') {
            Stop-WithReason -Reason 'native-machine-scope-forbidden' -ExitCode 3 -Detail "native requires -Scope orchestrator; targetModelKey='$target'"
        }
        # Same axis, different gate: orchestrator scope is not enough if the key belongs to ANOTHER
        # harness. Enforcement is PARTIAL by nature — it only applies when the key identifies the harness
        # (cursor/*, cursor-*); a neutral key like moonshot/kimi-k3-max cannot be verified here.
        $keyHarness = Get-LlmDelegateKeyHarness -TargetModelKey $target
        if ($null -ne $keyHarness -and -not $keyHarness.Equals($orchTrim, [System.StringComparison]::OrdinalIgnoreCase)) {
            Stop-WithReason -Reason 'native-harness-orchestrator-mismatch' -ExitCode 3 -Detail "harness key '$keyHarness' under -Orchestrator '$orchTrim'; targetModelKey='$target'"
        }
        if ($null -eq $harnessRaw -or [string]::IsNullOrWhiteSpace([string]$harnessRaw)) {
            Stop-WithReason -Reason 'native-harness-model-id-missing' -ExitCode 3 -Detail 'harnessModelId required for native'
        }
        $harnessId = ([string]$harnessRaw).Trim()
        foreach ($p in @($invokeArgs.PSObject.Properties)) {
            Stop-WithReason -Reason 'unknown-property' -ExitCode 3 -Detail "native does not accept invokeArgs.$($p.Name)"
        }
        $invClean = [pscustomobject]@{}
        $fallbackItems = Get-Prop $Item 'fallbackChain'
        if ($null -ne $fallbackItems -and @($fallbackItems).Count -gt 0) {
            Stop-WithReason -Reason 'native-fallback-chain-forbidden' -ExitCode 3 -Detail 'native cannot have a fallbackChain'
        }
        return [pscustomobject]@{
            type            = $type
            backend         = $backend
            targetModelKey  = $target
            harnessModelId  = $harnessId
            reasoningEffort = $effort
            rank            = $rank
            invokeArgs      = $invClean
        }
    }

    if ($null -ne $harnessRaw) {
        Stop-WithReason -Reason 'unknown-property' -ExitCode 3 -Detail 'harnessModelId forbidden for CLI'
    }
    $invClean = Copy-SanitizedInvokeArgs -InvokeArgs $invokeArgs -Backend $backend -TargetModelKey $target
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$seen.Add("$backend|$target")
    $fallbackItems = Get-Prop $Item 'fallbackChain'
    if ($null -eq $fallbackItems) { $fallbackItems = @() }
    foreach ($fb in @($fallbackItems)) {
        Assert-KnownProperties -Obj $fb -Allowed $allowedFallbackProps -Context 'fallbackChain'
        $fbBackend = [string](Get-Prop $fb 'backend')
        $fbTarget = [string](Get-Prop $fb 'targetModelKey')
        $fbInv = Get-Prop $fb 'invokeArgs'
        if ([string]::IsNullOrWhiteSpace($fbBackend) -or [string]::IsNullOrWhiteSpace($fbTarget) -or $null -eq $fbInv) {
            Stop-WithReason -Reason 'reviewer-incomplete' -ExitCode 3 -Detail 'incomplete fallbackChain item'
        }
        if ($allowedNativeBackends -contains $fbBackend) {
            Stop-WithReason -Reason 'native-fallback-chain-forbidden' -ExitCode 3 -Detail "native as chain link: $fbTarget"
        }
        if ($allowedDispatchBackends -notcontains $fbBackend) {
            Stop-WithReason -Reason 'backend-not-allowed' -ExitCode 3 -Detail "fallback backend='$fbBackend'"
        }
        # A chain link is always CLI: no Cursor harness spelling is dispatchable here.
        if (Test-LlmDelegateCursorHarnessKey -TargetModelKey $fbTarget) {
            Stop-WithReason -Reason 'native-cursor-prefix' -ExitCode 3 -Detail "fallback targetModelKey='$fbTarget'"
        }
        if (Test-HardVetoTarget -TargetModelKey $fbTarget) {
            Stop-WithReason -Reason 'hard-veto' -ExitCode 3 -Detail "fallback veto: $fbTarget"
        }
        $key = "$fbBackend|$fbTarget"
        if (-not $seen.Add($key)) {
            Stop-WithReason -Reason 'fallback-cycle' -ExitCode 3 -Detail "cycle involving $fbTarget"
        }
        $fbInvClean = Copy-SanitizedInvokeArgs -InvokeArgs $fbInv -Backend $fbBackend -TargetModelKey $fbTarget
        $chainOut.Add([pscustomobject]@{
                backend        = $fbBackend
                targetModelKey = $fbTarget
                invokeArgs     = $fbInvClean
                reason         = [string](Get-Prop $fb 'reason')
            })
    }

    return [pscustomobject]@{
        type            = $type
        backend         = $backend
        targetModelKey  = $target
        reasoningEffort = $effort
        rank            = $rank
        invokeArgs      = $invClean
        fallbackChain   = @($chainOut)
    }
}

function Test-PersistedSchema3Valid {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $doc = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
        $sv = Get-Prop $doc 'schemaVersion'
        return ($null -ne $sv -and [int]$sv -eq 3)
    } catch {
        return $false
    }
}

function Get-DefaultPreferredRoot {
    return (Get-LlmDelegateStateRoot)
}

# --- params (exit 1) ---
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

$scopeTrim = if ($null -eq $Scope) { '' } else { $Scope.Trim() }
if ([string]::IsNullOrWhiteSpace($scopeTrim)) {
    Stop-WithReason -Reason 'scope-required' -ExitCode 1
}
if ($allowedScopes -notcontains $scopeTrim) {
    Stop-WithReason -Reason 'scope-invalid' -ExitCode 1 -Detail "scope='$scopeTrim'"
}

if ([string]::IsNullOrWhiteSpace($ReviewersJson)) {
    Stop-WithReason -Reason 'reviewers-json-required' -ExitCode 1
}

$hasOutputPath = $PSBoundParameters.ContainsKey('OutputPath') -and -not [string]::IsNullOrWhiteSpace($OutputPath)
$hasPreferredRoot = $PSBoundParameters.ContainsKey('PreferredRoot')
if ($hasOutputPath -and $hasPreferredRoot) {
    Stop-WithReason -Reason 'preferred-path-mode-conflict' -ExitCode 1
}

$root = if ($hasPreferredRoot -and -not [string]::IsNullOrWhiteSpace($PreferredRoot)) {
    [System.IO.Path]::GetFullPath($PreferredRoot)
} else {
    Get-DefaultPreferredRoot
}

if ($hasOutputPath) {
    $effectivePath = [System.IO.Path]::GetFullPath($OutputPath)
} else {
    $fileName = if ($scopeTrim -eq 'orchestrator') {
        "preferred-reviewers.$orchTrim.json"
    } else {
        'preferred-reviewers.json'
    }
    $effectivePath = [System.IO.Path]::GetFullPath((Join-Path $root $fileName))
}

$siblingOrchestratorPath = [System.IO.Path]::GetFullPath((Join-Path $root "preferred-reviewers.$orchTrim.json"))
$siblingMachinePath = [System.IO.Path]::GetFullPath((Join-Path $root 'preferred-reviewers.json'))
$siblingOrchestratorExists = [bool](Test-Path -LiteralPath $siblingOrchestratorPath -PathType Leaf)
$siblingMachineExists = [bool](Test-Path -LiteralPath $siblingMachinePath -PathType Leaf)
$setDiagnostics = [System.Collections.Generic.List[string]]::new()

$orchExistsAfterWrite = $siblingOrchestratorExists -or ($effectivePath -eq $siblingOrchestratorPath)
$machineExistsAfterWrite = $siblingMachineExists -or ($effectivePath -eq $siblingMachinePath)
$resolveWouldPreferAfterWrite = if ($orchExistsAfterWrite) {
    'orchestrator'
} elseif ($machineExistsAfterWrite) {
    'machine'
} else {
    'none'
}
$harnessResolveReadsThisPath = if ($resolveWouldPreferAfterWrite -eq 'orchestrator') {
    ($effectivePath -eq $siblingOrchestratorPath)
} elseif ($resolveWouldPreferAfterWrite -eq 'machine') {
    ($effectivePath -eq $siblingMachinePath)
} else {
    $false
}
if ($scopeTrim -eq 'machine' -and $siblingOrchestratorExists -and ($effectivePath -eq $siblingMachinePath)) {
    [void]$setDiagnostics.Add('machine-write-shadowed-by-orchestrator-file')
}

if (-not $Preview -and -not $Overwrite -and (Test-PersistedSchema3Valid -Path $effectivePath)) {
    Stop-WithReason -Reason 'overwrite-required' -ExitCode 1 -Detail "schema 3 target: $effectivePath" -Extra @{
        effectivePreferredPath       = $effectivePath
        schemaVersion                = 3
        outputPath                   = $effectivePath
        scope                        = $scopeTrim
        orchestrator                 = $orchTrim
        siblingOrchestratorPath      = $siblingOrchestratorPath
        siblingOrchestratorExists    = $siblingOrchestratorExists
        siblingMachinePath           = $siblingMachinePath
        siblingMachineExists         = $siblingMachineExists
        resolveWouldPreferAfterWrite = $resolveWouldPreferAfterWrite
        harnessResolveReadsThisPath  = [bool]$harnessResolveReadsThisPath
        diagnostics                  = @($setDiagnostics)
    }
}

$parsed = $null
# -NoEnumerate keeps a one-element bare array as an array instead of unwrapping it into
# a single object that would then be checked as the wrapper.
try { $parsed = $ReviewersJson | ConvertFrom-Json -NoEnumerate } catch {
    Write-ErrDiag $_.Exception.Message
    Stop-WithReason -Reason 'reviewers-json-required' -ExitCode 1 -Extra @{ outputPath = $effectivePath }
}

$items = @()
$inputSchema = $null
$fallbackPolicyIn = $null

if ($parsed -is [System.Array]) {
    $items = @($parsed)
    if ($items.Count -eq 0) {
        Stop-WithReason -Reason 'reviewer-incomplete' -ExitCode 3 -Detail 'bare array without reviewers'
    }
} else {
    Assert-KnownProperties -Obj $parsed -Allowed $allowedWrapperProps -Context 'wrapper'
    $itemsNode = Get-Prop $parsed 'reviewers'
    if ($null -eq $itemsNode) {
        Stop-WithReason -Reason 'reviewer-incomplete' -ExitCode 3 -Detail 'wrapper without reviewers'
    }
    $items = @($itemsNode)
    $inputSchema = Get-Prop $parsed 'schemaVersion'
    if ($null -ne $inputSchema -and [string]$inputSchema -ne '3') {
        Stop-WithReason -Reason 'reviewers-schema-unsupported' -ExitCode 3 -Detail "schemaVersion='$inputSchema'; only schema 3 is accepted"
    }
    $fallbackPolicyIn = Get-Prop $parsed 'fallbackPolicy'
}

$kept = [System.Collections.Generic.List[object]]::new()
$explicitRanks = [System.Collections.Generic.HashSet[int]]::new()
$implicitRanks = [System.Collections.Generic.HashSet[int]]::new()
$nextImplicitRank = 1

foreach ($it in $items) {
    $backendForRank = [string](Get-Prop $it 'backend')
    $targetForRank = [string](Get-Prop $it 'targetModelKey')
    $rankValueForReservation = Get-Prop $it 'rank'
    $backendOk = ($allowedDispatchBackends -contains $backendForRank) -or ($allowedNativeBackends -contains $backendForRank)
    if ($null -ne $rankValueForReservation -and
        -not [string]::IsNullOrWhiteSpace($backendForRank) -and
        -not [string]::IsNullOrWhiteSpace($targetForRank) -and
        $backendOk -and
        -not (Test-HardVetoTarget -TargetModelKey $targetForRank)) {
        [void]$explicitRanks.Add([int]$rankValueForReservation)
    }
}
foreach ($explicitRank in $explicitRanks) {
    if ($explicitRank -ge $nextImplicitRank) { $nextImplicitRank = $explicitRank + 1 }
}

foreach ($it in $items) {
    $defaultRank = 0
    if ($null -eq (Get-Prop $it 'rank')) {
        while ($explicitRanks.Contains($nextImplicitRank) -or $implicitRanks.Contains($nextImplicitRank)) {
            $nextImplicitRank++
        }
        $defaultRank = $nextImplicitRank
        [void]$implicitRanks.Add($defaultRank)
        $nextImplicitRank++
    }
    $converted = ConvertTo-ReviewerV3 -Item $it -DefaultRank $defaultRank
    $kept.Add($converted)
}

$keptSorted = @($kept | Sort-Object -Property @{ Expression = { [int](Get-Prop $_ 'rank') } }, @{ Expression = { [string](Get-Prop $_ 'targetModelKey') } })
Assert-ValidRankSet -Reviewers $keptSorted
$fallbackPolicy = ConvertTo-SupportedFallbackPolicy -Policy $fallbackPolicyIn


$docOrdered = [ordered]@{
    schemaVersion = 3
    updatedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
if ($scopeTrim -eq 'orchestrator') {
    $docOrdered['orchestrator'] = $orchTrim
} else {
    $docOrdered['calibratedBy'] = $orchTrim
}
$docOrdered['fallbackPolicy'] = $fallbackPolicy
$docOrdered['reviewers'] = @($keptSorted)
$doc = [pscustomobject]$docOrdered
$docJson = $doc | ConvertTo-Json -Depth 12

if (-not $Preview) {
    $outDir = Split-Path -Parent $effectivePath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $effectivePath -PathType Leaf) {
        $backupPath = "$effectivePath.bak-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"
        Copy-Item -LiteralPath $effectivePath -Destination $backupPath -Force
    }
    $tmpPath = "$effectivePath.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tmpPath, $docJson, $utf8NoBom)
        Move-Item -LiteralPath $tmpPath -Destination $effectivePath -Force
    } catch {
        if (Test-Path -LiteralPath $tmpPath -PathType Leaf) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

Emit-SetResult -ExitCode 0 -Fields @{
    written                       = $kept.Count
    discardedVeto                 = @()
    reason                        = $null
    effectivePreferredPath        = $effectivePath
    schemaVersion                 = 3
    outputPath                    = $effectivePath
    preview                       = [bool]$Preview
    document                      = if ($Preview) { $doc } else { $null }
    scope                         = $scopeTrim
    orchestrator                  = $orchTrim
    siblingOrchestratorPath       = $siblingOrchestratorPath
    siblingOrchestratorExists     = $siblingOrchestratorExists
    siblingMachinePath            = $siblingMachinePath
    siblingMachineExists          = $siblingMachineExists
    resolveWouldPreferAfterWrite  = $resolveWouldPreferAfterWrite
    harnessResolveReadsThisPath   = [bool]$harnessResolveReadsThisPath
    diagnostics                   = @($setDiagnostics)
}
