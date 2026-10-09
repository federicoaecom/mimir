#requires -Version 7.4
<#
.SYNOPSIS
    Deterministically checks whether a peer-review round can be closed out
    without omitting the offer to save preferred reviewers.
.DESCRIPTION
    Part of the mimir-delegate skill mechanism; methodology in 15-peer-review.md.

    Why it exists: in a real test, the consumer agent read the persistence rule for
    preferred-reviewers.json, asked for the reviewers, ran the panel, and closed the round
    without offering to save the curation. This resolver makes that closeout point mechanical:
    when the round starts with no resolved preferred list (hasPreferences=false in the
    Resolve-LlmDelegatePreferredReviewers.ps1 envelope) and the user selects reviewers
    manually, the closeout is only ready if the offer was made or an equivalent explicit
    decision was recorded.

    This script does NOT write preferred-reviewers.json, does NOT decide per-KB authorization,
    and does NOT recompute diversity. It only emits machine JSON for the orchestrator:
    ready/blocked, reasons, a required prompt, and a receipt addendum. Writing remains
    the job of Set-LlmDelegatePreferredReviewers.ps1.

    Snapshot/provenance axis (schema 3): when HadPreferredReviewers=true, the closeout
    requires -PreferredReviewersSnapshotJson with the complete Resolve- envelope from the
    start of the round (schemaVersion=3, preferenceSource, effectivePreferredPath, reviewers[]).
    The receipt echoes preferenceSource / effectivePreferredPath (via the snapshot and/or
    -PreferenceSource / -EffectivePreferredPath). With no preferred reviewers, the offer can use
    -ProposedPreferredPath, -PreferredRoot and -Orchestrator to materialize the proposed path in
    the receipt (preferenceSource=none). The envelope from Resolve- is the only source of truth
    for the effective path — do not search the repository for preferred-reviewers*.json.

    Offer states:
      not_made       -> the required offer has not been made yet
      offered        -> offer presented to the user; the round can proceed without a response
      accepted       -> user accepted saving the curation
      declined       -> user declined saving the curation
      deferred       -> user deferred saving the curation
      not_applicable -> there was no obligation to offer in this round

    Fail-closed rule: if there was no resolved preferred list, manual selection occurred, and
    the state comes back not_applicable or absent, the closeout blocks. not_applicable is only
    valid when there already were preferences, or when the round did not use manual reviewer
    selection.

    When a preferred list had been resolved, it is not authorization and does not require a
    useful opinion from everyone, but it also cannot silently turn into an optional pool. The
    closeout requires an auditable state for every preferred reviewer of the round. Incomplete
    states (`gateAllow`, `dispatched`, `enqueued`) block the final receipt; final states such as
    `responded`, `noResponse`, `timeout`, `error`, `quota`, `gateAsk`, `gateDeny`, `unavailable`,
    `skippedByHumanDecision`, `stoppedOnGap`, `skippedAfterSuccess`, `skippedByPolicy` and
    `notAttempted` clear as auditable final states, provided the diversity floor has already
    been handled by its own engine. Not-attempted states must come with
    `countsForDiversity=false`.

    vN+1 state axis (Finding A): after the panel, the agent AUTHORS a consolidated version
    (vN+1) that has NOT yet been reviewed. -VNextState declares where the vN+1 stands:
      notProduced                 -> no consolidated synthesis happened -> neutral
      pendingResubmission         -> vN+1 authored and NOT resubmitted -> BLOCKS (offer a 2nd round)
      resubmitted                 -> vN+1 resubmitted to the panel -> neutral
      resubmissionDeclinedByHuman -> human knowingly does NOT resubmit -> requires an auditable
                                     record (-ResubmissionDeclinedBy + -ResubmissionDeclineReason
                                     + -RoundId, which scopes the decline to the round);
                                     without who/reason/RoundId -> BLOCKS (vnext-resubmission-decline-unaudited)
    This script is STATELESS: the state arrives as a parameter and is re-evaluated from scratch
    on every call. The auditable trail (append-only per RoundId) and monotonicity across calls
    belong to the ORCHESTRATOR + receipt/ledger, NOT to this script. The only way to move from
    pendingResubmission to a terminal state is a new invocation with the terminal VNextState.
    Honest limit: this axis is proof of SILENCE (it turns a "I skipped the resubmission" into an
    auditable, falsifiable statement), not proof of FABRICATION.
.PARAMETER HadPreferredReviewers
    Indicates whether Resolve-LlmDelegatePreferredReviewers.ps1 returned hasPreferences=true at
    the start of assembling the panel (preferred list resolved via schema 3 cascade or bypass).
.PARAMETER ManualReviewerSelection
    Indicates whether the user picked reviewers manually for this round.
.PARAMETER PreferredReviewersOfferState
    State of the offer to save the selection into the machine-level / per-orchestrator curation
    (preferred-reviewers*.json outside the repository).
.PARAMETER RoundId
    Round identifier, used for the receipt and auditing. Optional in general, but
    REQUIRED when -VNextState is resubmissionDeclinedByHuman (scopes the decline to the round;
    absent in that case blocks the closeout).
.PARAMETER SelectedReviewersJson
    JSON with the round's expected reviewers. When HadPreferredReviewers=true, it is required
    to prove completeness; when ManualReviewerSelection=true and the list is provided, it also
    becomes a completeness contract. Primary reviewers and fallbackChain[] are expanded and compared
    against PreferredReviewerStatesJson.
.PARAMETER PreferredReviewerStatesJson
    Optional JSON with the final state of each expected/audited reviewer of the round:
    [{ "targetModelKey": "...", "backend": "...", "state": "responded|noResponse|timeout|error|quota|gateAsk|gateDeny|unavailable|skippedByHumanDecision|stoppedOnGap|skippedAfterSuccess|skippedByPolicy|notAttempted|gateAllow|dispatched|enqueued", "family": "...", "attemptRole": "primary|fallback", "fallbackOf": "...", "countsForDiversity": true|false }].
    When HadPreferredReviewers=true, or when ManualReviewerSelection=true with SelectedReviewersJson
    provided, it must contain every expected reviewer. In that comparison, backend, targetModelKey,
    attemptRole and fallbackOf compose the expected reviewer's identity; omitting them can produce a
    missing or unexpected state in the closeout.
    Not-attempted states (`skippedAfterSuccess`, `skippedByPolicy`, `notAttempted`) must carry
    `countsForDiversity=false`; `notAttempted` as a silent primary state blocks the closeout.
.PARAMETER DiversityState
    Optional state already computed by Resolve-LlmDelegatePanelDiversity.ps1. This script does
    not recompute diversity; it only echoes the value in the receipt.
.PARAMETER VNextState
    State of the consolidated version (vN+1) authored after the panel:
    notProduced | pendingResubmission | resubmitted | resubmissionDeclinedByHuman.
    Default notProduced. Always echoed in the receiptAddendum (Finding A).
.PARAMETER ResubmissionDeclinedBy
    Who (the human) decided not to resubmit the vN+1. Required only when
    -VNextState is resubmissionDeclinedByHuman; absent/empty in that case blocks the closeout.
    Ignored in the other states.
.PARAMETER ResubmissionDeclineReason
    Why the resubmission was declined. Required only when
    -VNextState is resubmissionDeclinedByHuman; absent/empty in that case blocks the closeout.
    Ignored in the other states.
.PARAMETER PreferredReviewersSnapshotJson
    Complete JSON envelope from Resolve-LlmDelegatePreferredReviewers.ps1 at the start of the
    round (schema 3). Required when HadPreferredReviewers=true; must carry schemaVersion=3,
    preferenceSource (orchestrator|machine|explicit-path), effectivePreferredPath, hasPreferences
    and reviewers[]. SelectedReviewersJson must be a subset of the snapshot's reviewers.
    With no preferred reviewers, omit it or pass {}.
.PARAMETER EffectivePreferredPath
    Effective curation path (echo of the Resolve-). Optional if the snapshot already carries
    effectivePreferredPath; if both are provided, they must match (otherwise preferred-path-mismatch).
.PARAMETER PreferenceSource
    Provenance: orchestrator | machine | explicit-path | none. Optional if the snapshot already
    carries preferenceSource; if both are provided, they must match.
.PARAMETER PreferredRoot
    Machine-level root of the curation (default: the state root, %LOCALAPPDATA%\mimir-delegate on
    Windows; see LlmDelegateStatePath.ps1). Used
    when there are no preferred reviewers and the offer needs to materialize the proposed path
    in the receipt.
.PARAMETER Orchestrator
    Orchestrator slug (^[a-z0-9][a-z0-9-]{0,39}$, lowercased; known harnesses:
    cursor|claude-code|codex|opencode, the list is open; a malformed slug is rejected). Used in the offer with no preferred reviewers to validate
    the allowed name preferred-reviewers.<orch>.json alongside preferred-reviewers.json.
.PARAMETER ProposedPreferredPath
    Proposed path to write the curation to when the round starts with no preferred reviewers
    and there is manual selection. Default: preferred-reviewers.json in the state root. When the
    state root cannot be determined and this is omitted, the optional offer is skipped: no blocking
    reason, requiresPreferredOffer=false, and a warning in receiptAddendum.
.EXAMPLE
    .\Resolve-LlmDelegatePeerReviewCloseout.ps1 -HadPreferredReviewers false -ManualReviewerSelection true -PreferredReviewersOfferState not_made

    Note: -HadPreferredReviewers/-ManualReviewerSelection take the string 'true'/'false'
    (NOT the literal $true/$false). Via `pwsh -File` called from Bash, bare $true/$false shell
    tokens expand to empty before pwsh; that is why the contract is a string validated by ValidateSet.
.EXAMPLE
    .\Resolve-LlmDelegatePeerReviewCloseout.ps1 -HadPreferredReviewers true -ManualReviewerSelection false -RoundId v3 -VNextState pendingResubmission

    vN+1 authored and not yet resubmitted: closeoutReady=false, blockingReason
    vnext-pending-resubmission, and requiredUserPrompt offers the 2nd round.
.EXAMPLE
    .\Resolve-LlmDelegatePeerReviewCloseout.ps1 -HadPreferredReviewers true -ManualReviewerSelection false -RoundId v3 -VNextState resubmissionDeclinedByHuman -ResubmissionDeclinedBy "Reviewer" -ResubmissionDeclineReason "diff trivial; risco baixo"

    Audited decline: closeoutReady=true and the receipt echoes who/reason/RoundId.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('true', 'false')] [string] $HadPreferredReviewers,
    [Parameter(Mandatory)] [ValidateSet('true', 'false')] [string] $ManualReviewerSelection,
    [ValidateSet('not_made', 'offered', 'accepted', 'declined', 'deferred', 'not_applicable')]
    [string] $PreferredReviewersOfferState = 'not_applicable',
    [string] $RoundId,
    [string] $SelectedReviewersJson = '[]',
    [string] $PreferredReviewerStatesJson = '[]',
    [string] $DiversityState,
    [ValidateSet('notProduced', 'pendingResubmission', 'resubmitted', 'resubmissionDeclinedByHuman')]
    [string] $VNextState = 'notProduced',
    [string] $ResubmissionDeclinedBy,
    [string] $ResubmissionDeclineReason,
    [string] $PreferredReviewersSnapshotJson,
    [string] $EffectivePreferredPath,
    [string] $PreferenceSource,
    [string] $PreferredRoot,
    [string] $Orchestrator,
    [string] $ProposedPreferredPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# HadPreferredReviewers/ManualReviewerSelection arrive as strings ('true'/'false'): via
# `pwsh -File` called from Bash, bare $true/$false shell tokens expand to empty before
# pwsh (a real quirk; two agents tripped on it). ValidateSet bars invalid values and the
# conversion is textual — NEVER [bool]$x, which would make [bool]'false' = $true. See Finding C.
. (Join-Path $PSScriptRoot 'LlmDelegateTargetFamilySupport.ps1')
. (Join-Path $PSScriptRoot 'LlmDelegateStatePath.ps1')

# Default state root, resolved once. When it cannot be determined (off Windows with no XDG_DATA_HOME
# and no usable HOME), keep the helper's error: without -ProposedPreferredPath the optional save
# offer is then skipped with a warning in receiptAddendum instead of aborting the envelope or
# blocking the round.
$stateRoot = $null
$stateRootError = $null
try { $stateRoot = Get-LlmDelegateStateRoot } catch { $stateRootError = $_.Exception.Message }

# -Orchestrator is an open slug (known: cursor|claude-code|codex|opencode). A malformed value
# is rejected before any file name is built from it (path characters would escape the root).
$orchSlug = $null
if (-not [string]::IsNullOrWhiteSpace($Orchestrator)) {
    $orchSlug = ConvertTo-LlmDelegateOrchestratorSlug -Orchestrator $Orchestrator
    if ($null -eq $orchSlug) {
        throw "BLOCK: -Orchestrator is not a valid slug (expected ^[a-z0-9][a-z0-9-]{0,39}`$): '$($Orchestrator.Trim())'"
    }
}

$hadPreferred = ($HadPreferredReviewers -eq 'true')
$manualSelection = ($ManualReviewerSelection -eq 'true')

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name]) { return $Obj.PSObject.Properties[$Name].Value }
    return $null
}

function Get-ReviewerLabel {
    param($Reviewer)
    $backend = [string](Get-Prop $Reviewer 'backend')
    $target = [string](Get-Prop $Reviewer 'targetModelKey')
    if ([string]::IsNullOrWhiteSpace($target)) { $target = [string](Get-Prop $Reviewer 'model') }
    if ([string]::IsNullOrWhiteSpace($backend)) { return $target }
    if ([string]::IsNullOrWhiteSpace($target)) { return $backend }
    return "$backend -> $target"
}

function Get-ReviewerTarget {
    param($Reviewer)
    $target = [string](Get-Prop $Reviewer 'targetModelKey')
    if ([string]::IsNullOrWhiteSpace($target)) { $target = [string](Get-Prop $Reviewer 'model') }
    return $target
}

function Get-ReviewerStateKey {
    param([string]$Backend, [string]$TargetModelKey, [string]$AttemptRole, [string]$FallbackOf)
    $role = if ($AttemptRole -eq 'fallback' -or -not [string]::IsNullOrWhiteSpace($FallbackOf)) { 'fallback' } else { 'primary' }
    $fallbackOwner = if ($role -eq 'fallback') { $FallbackOf } else { '' }
    return "$Backend|$TargetModelKey|$role|$fallbackOwner"
}

function Add-ExpectedReviewerState {
    param(
        [System.Collections.Generic.List[object]]$Rows,
        [System.Collections.Generic.HashSet[string]]$Keys,
        [System.Collections.Generic.List[string]]$BlockingReasons,
        $Reviewer,
        [string]$AttemptRole,
        [string]$FallbackOf
    )
    $backend = [string](Get-Prop $Reviewer 'backend')
    $target = Get-ReviewerTarget $Reviewer
    if ([string]::IsNullOrWhiteSpace($target)) {
        $BlockingReasons.Add('preferred-reviewer-expected-missing-target')
        return
    }
    $key = Get-ReviewerStateKey -Backend $backend -TargetModelKey $target -AttemptRole $AttemptRole -FallbackOf $FallbackOf
    if (-not $Keys.Add($key)) {
        $BlockingReasons.Add("preferred-reviewer-expected-duplicate:$target")
        return
    }
    $Rows.Add([pscustomobject]@{
            targetModelKey = $target
            backend        = $backend
            attemptRole    = $AttemptRole
            fallbackOf     = $FallbackOf
            key            = $key
        })
}

function Get-NormalizedFullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    try {
        return [System.IO.Path]::GetFullPath($expanded)
    } catch {
        return $expanded
    }
}

function Resolve-EffortApplied {
    param($StateRow, $SnapshotReviewers)
    $attemptRole = [string](Get-Prop $StateRow 'attemptRole')
    $fallbackOf = [string](Get-Prop $StateRow 'fallbackOf')
    if ($attemptRole -eq 'fallback' -or -not [string]::IsNullOrWhiteSpace($fallbackOf)) {
        return 'unset'
    }
    if ($null -eq $SnapshotReviewers) { return 'unset' }
    $backend = [string](Get-Prop $StateRow 'backend')
    $target = [string](Get-Prop $StateRow 'targetModelKey')
    $hit = $null
    foreach ($r in @($SnapshotReviewers)) {
        $rb = [string](Get-Prop $r 'backend')
        $rt = [string](Get-Prop $r 'targetModelKey')
        if ($rb.Equals($backend, [System.StringComparison]::OrdinalIgnoreCase) -and
            $rt.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) {
            $hit = $r
            break
        }
    }
    if ($null -eq $hit) { return 'unset' }
    $effort = [string](Get-Prop $hit 'reasoningEffort')
    if ([string]::IsNullOrWhiteSpace($effort) -or $effort -eq 'unset') { return 'unset' }
    return 'unsupported'
}

$selectedReviewers = @()
try {
    $parsed = $SelectedReviewersJson | ConvertFrom-Json
    $selectedReviewers = @($parsed)
} catch {
    throw "BLOCK: -SelectedReviewersJson is not valid JSON: $($_.Exception.Message)"
}

$preferredReviewerStates = @()
try {
    $parsedStates = $PreferredReviewerStatesJson | ConvertFrom-Json
    $preferredReviewerStates = @($parsedStates)
} catch {
    throw "BLOCK: -PreferredReviewerStatesJson is not valid JSON: $($_.Exception.Message)"
}

$requiresOffer = (-not $hadPreferred) -and $manualSelection
$blockingReasons = [System.Collections.Generic.List[string]]::new()
$offerSkippedWarning = $null

# Snapshot / provenance
$snapshotObj = $null
$snapshotReviewers = @()
$resolvedPreferenceSource = $PreferenceSource
$resolvedEffectivePath = $EffectivePreferredPath

if ($hadPreferred) {
    if ([string]::IsNullOrWhiteSpace($PreferredReviewersSnapshotJson) -or $PreferredReviewersSnapshotJson.Trim() -eq '[]') {
        $blockingReasons.Add('preferred-snapshot-missing')
    } else {
        try {
            $snapshotObj = $PreferredReviewersSnapshotJson | ConvertFrom-Json
        } catch {
            $blockingReasons.Add('preferred-snapshot-unreadable')
        }
        if ($null -ne $snapshotObj) {
            $isObj = $snapshotObj -isnot [System.Array]
            $svOk = $false
            try { $svOk = ([int](Get-Prop $snapshotObj 'schemaVersion') -eq 3) } catch { $svOk = $false }
            $src = [string](Get-Prop $snapshotObj 'preferenceSource')
            $srcOk = $src -in @('orchestrator', 'machine', 'explicit-path')
            $pathSnap = [string](Get-Prop $snapshotObj 'effectivePreferredPath')
            $pathOk = -not [string]::IsNullOrWhiteSpace($pathSnap)
            $hasPref = [bool](Get-Prop $snapshotObj 'hasPreferences')
            $revNode = Get-Prop $snapshotObj 'reviewers'
            $revOk = $null -ne $revNode
            if (-not ($isObj -and $hasPref -and $svOk -and $srcOk -and $pathOk -and $revOk)) {
                $blockingReasons.Add('preferred-snapshot-invalid')
            } else {
                $snapshotReviewers = @($revNode)
                foreach ($sr in $snapshotReviewers) {
                    if ([string]::IsNullOrWhiteSpace([string](Get-Prop $sr 'backend')) -or
                        [string]::IsNullOrWhiteSpace([string](Get-Prop $sr 'targetModelKey'))) {
                        $blockingReasons.Add('preferred-snapshot-invalid')
                        break
                    }
                }
                if ([string]::IsNullOrWhiteSpace($resolvedPreferenceSource)) {
                    $resolvedPreferenceSource = $src
                }
                if ([string]::IsNullOrWhiteSpace($resolvedEffectivePath)) {
                    $resolvedEffectivePath = $pathSnap
                } else {
                    $a = Get-NormalizedFullPath $resolvedEffectivePath
                    $b = Get-NormalizedFullPath $pathSnap
                    if ($null -ne $a -and $null -ne $b -and -not $a.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $blockingReasons.Add('preferred-path-mismatch')
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($PreferenceSource) -and
                    -not $PreferenceSource.Equals($src, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $blockingReasons.Add('preferred-path-mismatch')
                }
                # Selected ⊆ snapshot.reviewers match
                foreach ($sel in $selectedReviewers) {
                    $sb = [string](Get-Prop $sel 'backend')
                    $st = Get-ReviewerTarget $sel
                    $found = $false
                    foreach ($sr in $snapshotReviewers) {
                        if ([string](Get-Prop $sr 'backend').Equals($sb, [System.StringComparison]::OrdinalIgnoreCase) -and
                            [string](Get-Prop $sr 'targetModelKey').Equals($st, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $found = $true
                            break
                        }
                    }
                    if (-not $found) {
                        $blockingReasons.Add('preferred-snapshot-selection-mismatch')
                        break
                    }
                }
            }
        }
    }
} else {
    # No preferred reviewers: snapshot omitted or {}; effortApplied=unset
    if (-not [string]::IsNullOrWhiteSpace($PreferredReviewersSnapshotJson) -and
        $PreferredReviewersSnapshotJson.Trim() -notin @('{}', '')) {
        try {
            $tmpSnap = $PreferredReviewersSnapshotJson | ConvertFrom-Json
            if ($tmpSnap -is [System.Array] -or [bool](Get-Prop $tmpSnap 'hasPreferences')) {
                # do not invalidate if it is a plain {}
            }
        } catch { }
    }
}

if ($requiresOffer -or $hadPreferred) {
    if ([string]::IsNullOrWhiteSpace($resolvedEffectivePath) -and [string]::IsNullOrWhiteSpace($resolvedPreferenceSource)) {
        if ($requiresOffer) {
            # offer: ProposedPreferredPath or the machine default
            $proposed = $ProposedPreferredPath
            if ([string]::IsNullOrWhiteSpace($proposed) -and $null -ne $stateRoot) {
                $proposed = Join-Path $stateRoot 'preferred-reviewers.json'
            }
            if ([string]::IsNullOrWhiteSpace($resolvedPreferenceSource)) {
                $resolvedPreferenceSource = 'none'
            }
            if ([string]::IsNullOrWhiteSpace($proposed)) {
                # No -ProposedPreferredPath and no state root: there is no destination to offer.
                # Saving preferred reviewers is optional, so the offer is skipped with a warning and
                # the rest of the round is judged as if no offer were required.
                $requiresOffer = $false
                $offerSkippedWarning = "the mimir-delegate state folder cannot be determined ($stateRootError), so the optional offer to save the preferred reviewers was skipped; pass -ProposedPreferredPath (the destination to offer), or set XDG_DATA_HOME or HOME, to enable it."
            } else {
                $resolvedEffectivePath = Get-NormalizedFullPath $proposed
                $rootResolved = if (-not [string]::IsNullOrWhiteSpace($PreferredRoot)) {
                    Get-NormalizedFullPath $PreferredRoot
                } else {
                    Get-NormalizedFullPath $stateRoot
                }
                $dirName = [System.IO.Path]::GetDirectoryName($resolvedEffectivePath)
                $fileName = [System.IO.Path]::GetFileName($resolvedEffectivePath)
                $allowedNames = @('preferred-reviewers.json')
                if ($null -ne $orchSlug) {
                    $allowedNames += "preferred-reviewers.$orchSlug.json"
                }
                if ($null -eq $dirName -or $null -eq $rootResolved -or
                    -not $dirName.Equals($rootResolved, [System.StringComparison]::OrdinalIgnoreCase) -or
                    ($allowedNames -notcontains $fileName)) {
                    # do not block if root was not provided and the path is the expanded machine default
                    if (-not [string]::IsNullOrWhiteSpace($PreferredRoot)) {
                        $blockingReasons.Add('preferred-path-mismatch')
                    }
                }
            }
        } else {
            $blockingReasons.Add('preferred-path-provenance-missing')
        }
    } elseif ([string]::IsNullOrWhiteSpace($resolvedEffectivePath) -or [string]::IsNullOrWhiteSpace($resolvedPreferenceSource)) {
        $blockingReasons.Add('preferred-path-provenance-missing')
    }
}

if ($requiresOffer -and $PreferredReviewersOfferState -eq 'not_made') {
    $blockingReasons.Add('preferred-reviewers-offer-missing')
}

if ($requiresOffer -and $PreferredReviewersOfferState -eq 'not_applicable') {
    $blockingReasons.Add('preferred-reviewers-offer-state-invalid-for-manual-selection')
}

if (-not $requiresOffer -and $PreferredReviewersOfferState -ne 'not_applicable' -and -not $manualSelection) {
    $blockingReasons.Add('preferred-reviewers-offer-state-unexpected-without-manual-selection')
}

$validFinalStates = @(
    'responded',
    'noResponse',
    'timeout',
    'error',
    'quota',
    'gateAsk',
    'gateDeny',
    'unavailable',
    'skippedByHumanDecision',
    'stoppedOnGap',
    'skippedAfterSuccess',
    'skippedByPolicy',
    'notAttempted'
)
$incompleteStates = @('gateAllow', 'dispatched', 'enqueued')
$allKnownStates = @($validFinalStates + $incompleteStates)
$expectedStateRows = [System.Collections.Generic.List[object]]::new()
$expectedStateKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$requiresStateCompleteness = ($hadPreferred -or ($manualSelection -and @($selectedReviewers).Count -gt 0))
if ($requiresStateCompleteness) {
    foreach ($selected in $selectedReviewers) {
        $selectedTarget = Get-ReviewerTarget $selected
        Add-ExpectedReviewerState -Rows $expectedStateRows -Keys $expectedStateKeys -BlockingReasons $blockingReasons -Reviewer $selected -AttemptRole 'primary' -FallbackOf ''
        $fallbackItems = Get-Prop $selected 'fallbackChain'
        if ($null -eq $fallbackItems) { $fallbackItems = @() }
        foreach ($fb in @($fallbackItems)) {
            Add-ExpectedReviewerState -Rows $expectedStateRows -Keys $expectedStateKeys -BlockingReasons $blockingReasons -Reviewer $fb -AttemptRole 'fallback' -FallbackOf $selectedTarget
        }
    }
    if ($expectedStateRows.Count -eq 0) {
        $blockingReasons.Add('preferred-reviewer-expected-states-missing')
    }
}
$preferredStateRows = [System.Collections.Generic.List[object]]::new()
$receivedStateKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($st in $preferredReviewerStates) {
    $target = [string](Get-Prop $st 'targetModelKey')
    $state = [string](Get-Prop $st 'state')
    $backend = [string](Get-Prop $st 'backend')
    $family = [string](Get-Prop $st 'family')
    $attemptRole = [string](Get-Prop $st 'attemptRole')
    $fallbackOf = [string](Get-Prop $st 'fallbackOf')
    $countsForDiversityRaw = Get-Prop $st 'countsForDiversity'

    if ([string]::IsNullOrWhiteSpace($target)) {
        $blockingReasons.Add('preferred-reviewer-state-missing-target')
        continue
    }
    if ([string]::IsNullOrWhiteSpace($state)) {
        $blockingReasons.Add("preferred-reviewer-state-missing-state:$target")
        continue
    }
    if ($allKnownStates -notcontains $state) {
        $blockingReasons.Add("preferred-reviewer-state-invalid:${target}:${state}")
        continue
    }
    if ($incompleteStates -contains $state) {
        $blockingReasons.Add("preferred-reviewer-state-incomplete:${target}:${state}")
    }
    if ($state -in @('skippedByPolicy', 'skippedAfterSuccess', 'notAttempted')) {
        if ($countsForDiversityRaw -ne $false) {
            $blockingReasons.Add("preferred-reviewer-state-skip-counts-diversity:${target}:${state}")
        }
    }
    if ($state -eq 'notAttempted' -and ([string]::IsNullOrWhiteSpace($attemptRole) -or $attemptRole -eq 'primary')) {
        $blockingReasons.Add("preferred-reviewer-primary-notattempted-silent:${target}")
    }
    if ($requiresStateCompleteness) {
        $stateKey = Get-ReviewerStateKey -Backend $backend -TargetModelKey $target -AttemptRole $attemptRole -FallbackOf $fallbackOf
        if (-not $receivedStateKeys.Add($stateKey)) {
            $blockingReasons.Add("preferred-reviewer-state-duplicate:$target")
        } elseif (-not $expectedStateKeys.Contains($stateKey)) {
            $blockingReasons.Add("preferred-reviewer-state-unexpected:$target")
        }
    }

    $preferredStateRows.Add([pscustomobject]@{
            targetModelKey      = $target
            backend             = $backend
            family              = $family
            state               = $state
            attemptRole         = $attemptRole
            fallbackOf          = $fallbackOf
            countsForDiversity  = $countsForDiversityRaw
            effortApplied       = (Resolve-EffortApplied -StateRow $st -SnapshotReviewers $snapshotReviewers)
        })
}

if ($hadPreferred -and $preferredStateRows.Count -eq 0) {
    $blockingReasons.Add('preferred-reviewer-states-missing')
}
if ($requiresStateCompleteness) {
    foreach ($expected in $expectedStateRows) {
        if (-not $receivedStateKeys.Contains([string]$expected.key)) {
            $blockingReasons.Add("preferred-reviewer-state-missing:$($expected.targetModelKey)")
        }
    }
}

# vN+1 state axis (Finding A2). This closeout is STATELESS: VNextState arrives as an input
# parameter and is re-evaluated from scratch on every call; there is no mutable record between
# invocations. The auditable trail (append-only per RoundId) is the responsibility of the
# ORCHESTRATOR + receipt/ledger, NOT of this script (monotonicity across calls would require
# persistent state and would contradict the design). The only way to move from
# pendingResubmission to a terminal state is a new invocation of this closeout with the terminal
# VNextState; any other way of altering the state asserted in the receipt is a gate bypass.
# Honest limit: this axis is proof of silence (it turns a "I skipped the resubmission" into an
# auditable, falsifiable statement), not proof of fabrication (the script does not read the
# conversation to prove the lie).
$vNextDeclinedBy = ''
if ($null -ne $ResubmissionDeclinedBy) { $vNextDeclinedBy = $ResubmissionDeclinedBy.Trim() }
$vNextDeclineReason = ''
if ($null -ne $ResubmissionDeclineReason) { $vNextDeclineReason = $ResubmissionDeclineReason.Trim() }

if ($VNextState -eq 'pendingResubmission') {
    $blockingReasons.Add('vnext-pending-resubmission')
}
if ($VNextState -eq 'resubmissionDeclinedByHuman') {
    # RoundId is also required: the ruler is stale-per-version, so a decline needs to be
    # scoped to the round (without RoundId the decline would "leak" into future versions). Aligns with doc 15.
    if ([string]::IsNullOrWhiteSpace($vNextDeclinedBy) -or [string]::IsNullOrWhiteSpace($vNextDeclineReason) -or [string]::IsNullOrWhiteSpace($RoundId)) {
        $blockingReasons.Add('vnext-resubmission-decline-unaudited')
    }
}

if ($DiversityState -eq 'insufficientDiversityAfterFallback') {
    $blockingReasons.Add('insufficient-diversity-after-fallback')
}

$labels = @($selectedReviewers | ForEach-Object { Get-ReviewerLabel $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$selectedText = if ($labels.Count -gt 0) { ($labels -join ', ') } else { 'the reviewers chosen in this round' }

# Path in the prompt/receipt = the resolved one (ProposedPreferredPath / PreferredRoot / Orchestrator / snapshot),
# not the fixed machine literal. Fallback only if resolution did not materialize a path.
$preferredPathDisplay = if (-not [string]::IsNullOrWhiteSpace($resolvedEffectivePath)) {
    [string]$resolvedEffectivePath
} elseif ($null -ne $stateRoot) {
    Join-Path $stateRoot 'preferred-reviewers.json'
} else {
    "(no destination: $stateRootError)"
}
$offerLeaf = [System.IO.Path]::GetFileName($preferredPathDisplay)
$offerScopeLabel = if ($offerLeaf -match '^preferred-reviewers\.(.+)\.json$') {
    "as preferred reviewers of the '$($Matches[1])' orchestrator"
} else {
    'as preferred reviewers for this machine'
}

$roundLabel = 'this round'
if (-not [string]::IsNullOrWhiteSpace($RoundId)) { $roundLabel = "round '$RoundId'" }
$requiredPrompt = $null
if ($blockingReasons -contains 'vnext-pending-resubmission') {
    $requiredPrompt = "Before closing the peer review: a vN+1 was authored and not yet resubmitted ($roundLabel). Under option 1 (D2), offer the 2nd round to the panel and, after resubmitting, re-run this closeout with -VNextState resubmitted; if the human knowingly declines the resubmission, re-run with -VNextState resubmissionDeclinedByHuman + -ResubmissionDeclinedBy, -ResubmissionDeclineReason, and -RoundId."
} elseif ($blockingReasons -contains 'vnext-resubmission-decline-unaudited') {
    $requiredPrompt = "Before closing the peer review: declining the vN+1 resubmission ($roundLabel) requires an auditable record; provide -ResubmissionDeclinedBy (who decided), -ResubmissionDeclineReason (why), and -RoundId (which round)."
} elseif ($blockingReasons -contains 'insufficient-diversity-after-fallback') {
    $requiredPrompt = 'Before closing the peer review: the final composition after fallback has insufficient diversity. Do not use the peer review label; record it as a solo opinion, a second opinion, or an unfinished round.'
} elseif ($requiresOffer -and ($blockingReasons -contains 'preferred-reviewers-offer-missing' -or $blockingReasons -contains 'preferred-reviewers-offer-state-invalid-for-manual-selection')) {
    $requiredPrompt = "Before closing the peer review: do you want to save $selectedText $offerScopeLabel in ${preferredPathDisplay}? If you answer yes, I will use Set-LlmDelegatePreferredReviewers.ps1 -Orchestrator/-Scope according to the destination; if you prefer not to save or to defer, I continue without blocking this round."
} elseif ($blockingReasons -contains 'preferred-path-provenance-missing') {
    $requiredPrompt = 'Before closing the peer review: provide the provenance of the preferred path (-EffectivePreferredPath / -PreferenceSource or snapshot).'
} elseif ($blockingReasons -contains 'preferred-path-mismatch') {
    $requiredPrompt = 'Before closing the peer review: the provided path/preferenceSource differs from the Resolve- snapshot.'
} elseif ($blockingReasons -contains 'preferred-snapshot-missing') {
    $requiredPrompt = 'Before closing the peer review: pass -PreferredReviewersSnapshotJson with the complete Resolve- envelope from the start of the round.'
} elseif ($blockingReasons -contains 'preferred-snapshot-invalid' -or $blockingReasons -contains 'preferred-snapshot-unreadable') {
    $requiredPrompt = 'Before closing the peer review: the preferred snapshot is invalid (schema 3, hasPreferences, preferenceSource, path, and reviewers).'
} elseif ($blockingReasons -contains 'preferred-snapshot-selection-mismatch') {
    $requiredPrompt = 'Before closing the peer review: some -SelectedReviewersJson item does not exist in snapshot.reviewers.'
} elseif ($blockingReasons -contains 'preferred-reviewer-expected-states-missing') {
    $requiredPrompt = 'Before closing the peer review: provide -SelectedReviewersJson with the expected list of the round (primary reviewers and fallbackChain[]) and re-run this closeout together with -PreferredReviewerStatesJson. Without the expected list, the script cannot prove that the auditable states are complete.'
} elseif ($blockingReasons.Count -gt 0) {
    $requiredPrompt = 'Before closing the peer review: record in the receipt the final state of every preferred reviewer of the round, without omitting preferred reviewers that were not consulted. If any was left out, give the auditable reason.'
}

$closeoutReady = ($blockingReasons.Count -eq 0)
$curationReceipt = if ($null -ne $offerSkippedWarning) {
    "Preferred-reviewer curation: skipped; warning=$offerSkippedWarning"
} elseif ($requiresOffer) {
    "Preferred-reviewer curation: offer=$PreferredReviewersOfferState; destination=$preferredPathDisplay."
} else {
    "Preferred-reviewer curation: not_applicable; reason=" + ($(if ($hadPreferred) { 'preferred list already resolved at the start of the round' } else { 'no manual reviewer selection' }))
}
$stateReceipt = if ($hadPreferred) {
    "Preferred-reviewer states: recorded=$($preferredStateRows.Count)."
} else {
    'Preferred-reviewer states: not_applicable.'
}
# vNextState is ALWAYS echoed (including notProduced): the field cannot be silently
# absent from the receipt (Finding A; fixes the default's risk). On decline, echoes who/why/RoundId.
$vNextReceipt = "vN+1 state: vNextState=$VNextState."
if ($VNextState -eq 'resubmissionDeclinedByHuman') {
    $declineWho = if ([string]::IsNullOrWhiteSpace($vNextDeclinedBy)) { '(not provided)' } else { $vNextDeclinedBy }
    $declineWhy = if ([string]::IsNullOrWhiteSpace($vNextDeclineReason)) { '(not provided)' } else { $vNextDeclineReason }
    $declineRound = if ([string]::IsNullOrWhiteSpace($RoundId)) { '(no RoundId)' } else { $RoundId }
    $vNextReceipt = "vN+1 state: vNextState=$VNextState; declinedBy=$declineWho; reason=$declineWhy; RoundId=$declineRound."
}
$pathReceipt = "preferenceSource=$resolvedPreferenceSource; effectivePreferredPath=$resolvedEffectivePath."
$receiptAddendum = "$curationReceipt $stateReceipt $vNextReceipt $pathReceipt"

[pscustomobject]@{
    closeoutReady                = $closeoutReady
    blockingReasons             = @($blockingReasons)
    requiresPreferredOffer       = $requiresOffer
    hadPreferredReviewers        = $hadPreferred
    manualReviewerSelection      = $manualSelection
    preferredReviewersOfferState = $PreferredReviewersOfferState
    roundId                      = $RoundId
    diversityState               = $DiversityState
    vNextState                   = $VNextState
    resubmissionDeclinedBy       = $vNextDeclinedBy
    resubmissionDeclineReason    = $vNextDeclineReason
    selectedReviewers            = @($labels)
    expectedPreferredReviewerStates = @($expectedStateRows)
    preferredReviewerStates      = @($preferredStateRows)
    effectivePreferredPath       = $resolvedEffectivePath
    preferenceSource             = $resolvedPreferenceSource
    requiredUserPrompt           = $requiredPrompt
    receiptAddendum              = $receiptAddendum
    note                         = 'Advisory, deterministic peer-review closeout; it does not save preferences, does not decide authorization, and does not recompute diversity. If closeoutReady=false, do not close the round or issue a final receipt before presenting requiredUserPrompt.'
} | ConvertTo-Json -Depth 8
