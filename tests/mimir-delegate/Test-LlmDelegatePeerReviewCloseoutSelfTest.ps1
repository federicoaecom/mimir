#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Self-test for Resolve-LlmDelegatePeerReviewCloseout.ps1 (mimir-delegate skill).
# Covers the real bug: no preferred-reviewers.json + manual selection + offer omitted
# should block the peer review closeout.

$target = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-LlmDelegatePeerReviewCloseout.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $target -PathType Leaf) "Script missing: $target"
# The expected state root comes from the same helper the script uses: GetFolderPath('LocalApplicationData')
# is empty on a Linux host without ~/.local/share, and the helper still resolves a base there.
. (Join-Path (Split-Path -Parent $target) 'LlmDelegateStatePath.ps1')

function Invoke-Closeout {
    param(
        [bool] $HadPreferredReviewers,
        [bool] $ManualReviewerSelection,
        [string] $OfferState,
        [string] $SelectedReviewersJson = '[]',
        [string] $PreferredReviewerStatesJson = '[]',
        [string] $VNextState = 'notProduced',
        [string] $ResubmissionDeclinedBy = '',
        [string] $ResubmissionDeclineReason = '',
        [string] $RoundId = '',
        [string] $PreferredReviewersSnapshotJson = '',
        [string] $EffectivePreferredPath = '',
        [string] $PreferenceSource = '',
        [string] $ProposedPreferredPath = '',
        [string] $PreferredRoot = '',
        [string] $Orchestrator = ''
    )
    $hadStr = if ($HadPreferredReviewers) { 'true' } else { 'false' }
    $manualStr = if ($ManualReviewerSelection) { 'true' } else { 'false' }
    $args = @{
        HadPreferredReviewers          = $hadStr
        ManualReviewerSelection        = $manualStr
        PreferredReviewersOfferState   = $OfferState
        SelectedReviewersJson          = $SelectedReviewersJson
        PreferredReviewerStatesJson    = $PreferredReviewerStatesJson
        VNextState                     = $VNextState
        ResubmissionDeclinedBy         = $ResubmissionDeclinedBy
        ResubmissionDeclineReason      = $ResubmissionDeclineReason
        RoundId                        = $RoundId
    }
    if (-not [string]::IsNullOrWhiteSpace($PreferredReviewersSnapshotJson)) {
        $args['PreferredReviewersSnapshotJson'] = $PreferredReviewersSnapshotJson
    }
    if (-not [string]::IsNullOrWhiteSpace($EffectivePreferredPath)) {
        $args['EffectivePreferredPath'] = $EffectivePreferredPath
    }
    if (-not [string]::IsNullOrWhiteSpace($PreferenceSource)) {
        $args['PreferenceSource'] = $PreferenceSource
    }
    if (-not [string]::IsNullOrWhiteSpace($ProposedPreferredPath)) {
        $args['ProposedPreferredPath'] = $ProposedPreferredPath
    }
    if (-not [string]::IsNullOrWhiteSpace($PreferredRoot)) {
        $args['PreferredRoot'] = $PreferredRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($Orchestrator)) {
        $args['Orchestrator'] = $Orchestrator
    }
    return (& $target @args | ConvertFrom-Json)
}

function New-TestSnapshot {
    param([string]$SelectedReviewersJson, [string]$Path = 'C:\tmp\preferred-reviewers.json')
    $revs = $SelectedReviewersJson | ConvertFrom-Json
    $snap = [pscustomobject]@{
        hasPreferences         = $true
        schemaVersion          = 3
        preferenceSource       = 'machine'
        effectivePreferredPath = $Path
        reviewers              = @($revs)
    }
    return ($snap | ConvertTo-Json -Depth 8 -Compress)
}

# (1) Bug case: no prior preferences, manual choice, offer omitted -> blocks.
$r1 = Invoke-Closeout $false $true 'not_made' '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]'
Assert-True ($r1.closeoutReady -eq $false) 'Case 1: closeout should block.'
Assert-True (@($r1.blockingReasons) -contains 'preferred-reviewers-offer-missing') 'Case 1: blocking reason missing.'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$r1.requiredUserPrompt)) 'Case 1: required prompt missing.'
Assert-True ([string]$r1.effectivePreferredPath -match 'mimir-delegate[\\/]preferred-reviewers\.json$') 'Case 1: the default offer path should live under the mimir-delegate state folder.'

# (2) Offer presented, even without a final answer, releases the round.
$r2 = Invoke-Closeout $false $true 'offered'
Assert-True ($r2.closeoutReady -eq $true) 'Case 2: offer presented should release closeout.'

# (3) User declined to save curation -> releases and records it in the receipt.
$r3 = Invoke-Closeout $false $true 'declined'
Assert-True ($r3.closeoutReady -eq $true) 'Case 3: decline should release closeout.'
Assert-True ([string]$r3.receiptAddendum -match 'offer=declined') 'Case 3: receipt should record declined.'

# (4) User deferred saving curation -> releases and records it in the receipt.
$r4 = Invoke-Closeout $false $true 'deferred'
Assert-True ($r4.closeoutReady -eq $true) 'Case 4: deferral should release closeout.'
Assert-True ([string]$r4.receiptAddendum -match 'offer=deferred') 'Case 4: receipt should record deferred.'

# (5) preferred-reviewers.json already existed -> requires preferred states to close.
$r5 = Invoke-Closeout $true $false 'not_applicable'
Assert-True ($r5.closeoutReady -eq $false) 'Case 5: existing preferences without states should block.'
Assert-True (
    (@($r5.blockingReasons) -contains 'preferred-reviewer-states-missing') -or
    (@($r5.blockingReasons) -contains 'preferred-snapshot-missing')
) 'Case 5: should block on states-missing and/or snapshot-missing.'

# (6) Resolved preferred list + final states + snapshot already existed -> not_applicable is valid.
$statesOk = @'
[
  {"backend":"claude-code","targetModelKey":"anthropic/claude-opus-4-8","family":"anthropic","state":"responded"},
  {"backend":"codex","targetModelKey":"openai/gpt-5.5","family":"openai","state":"responded"},
  {"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro","family":"ollama-cloud","state":"noResponse"},
  {"backend":"opencode","targetModelKey":"ollama-cloud/glm-5.2","family":"ollama-cloud","state":"stoppedOnGap"}
]
'@
$selectedOk = @'
[
  {"backend":"claude-code","targetModelKey":"anthropic/claude-opus-4-8"},
  {"backend":"codex","targetModelKey":"openai/gpt-5.5"},
  {"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"},
  {"backend":"opencode","targetModelKey":"ollama-cloud/glm-5.2"}
]
'@
$snap6 = New-TestSnapshot -SelectedReviewersJson $selectedOk
$r6 = Invoke-Closeout $true $false 'not_applicable' $selectedOk $statesOk -PreferredReviewersSnapshotJson $snap6
Assert-True ($r6.closeoutReady -eq $true) ("Case 6: existing preferences with final states should release. reasons=$($r6.blockingReasons -join ',')")
Assert-True ($r6.requiresPreferredOffer -eq $false) 'Case 6: requiresPreferredOffer should be false.'
Assert-True (@($r6.preferredReviewerStates).Count -eq 4) 'Case 6: should echo 4 preferred-reviewer states.'
Assert-True ([string]$r6.receiptAddendum -match 'recorded=4') 'Case 6: receipt should record the number of states.'
Assert-True ([string]$r6.receiptAddendum -match 'preferred list already resolved at the start of the round') 'Case 6: curation reason must not cite only preferred-reviewers.json.'
Assert-True ([string]$r6.receiptAddendum -notmatch 'preferred-reviewers\.json already existed') 'Case 6: legacy phrasing of the curation reason must not come back.'

# (7) Incomplete state on a preferred reviewer -> blocks.
$statesIncomplete = '[{"backend":"opencode","targetModelKey":"ollama-cloud/kimi-k2.7-code","family":"ollama-cloud","state":"gateAllow"}]'
$sel7 = '[{"backend":"opencode","targetModelKey":"ollama-cloud/kimi-k2.7-code"}]'
$snap7 = New-TestSnapshot -SelectedReviewersJson $sel7
$r7 = Invoke-Closeout $true $false 'not_applicable' $sel7 $statesIncomplete -PreferredReviewersSnapshotJson $snap7
Assert-True ($r7.closeoutReady -eq $false) 'Case 7: incomplete gateAllow state should block.'
Assert-True (@($r7.blockingReasons) -contains 'preferred-reviewer-state-incomplete:ollama-cloud/kimi-k2.7-code:gateAllow') 'Case 7: incomplete-state reason missing.'

# (8) Improper not_applicable with manual selection and no prior preferences -> fail-closed.
$r8 = Invoke-Closeout $false $true 'not_applicable'
Assert-True ($r8.closeoutReady -eq $false) 'Case 8: improper not_applicable should block.'
Assert-True (@($r8.blockingReasons) -contains 'preferred-reviewers-offer-state-invalid-for-manual-selection') 'Case 8: fail-closed reason missing.'

# (9) Invalid JSON must fail explicitly.
$failed = $false
try {
    [void](Invoke-Closeout $false $true 'not_made' '{')
} catch {
    $failed = ($_.Exception.Message -match 'SelectedReviewersJson')
}
Assert-True $failed 'Case 9: invalid JSON should fail citing SelectedReviewersJson.'

# (10) Invalid states JSON must fail explicitly.
$failedStates = $false
try {
    [void](Invoke-Closeout $true $false 'not_applicable' '[]' '{')
} catch {
    $failedStates = ($_.Exception.Message -match 'PreferredReviewerStatesJson')
}
Assert-True $failedStates 'Case 10: invalid JSON should fail citing PreferredReviewerStatesJson.'

# (11) Contract C: an invalid value for -HadPreferredReviewers is barred by ValidateSet
#      (string 'true'/'false'; never [bool] nor a bare $true/$false token via Bash).
$failedSet = $false
try {
    [void](& $target -HadPreferredReviewers 'sim' -ManualReviewerSelection 'true' -PreferredReviewersOfferState not_made | ConvertFrom-Json)
} catch {
    $failedSet = $true
}
Assert-True $failedSet 'Case 11: an invalid value for -HadPreferredReviewers should be barred by ValidateSet.'

# (12) Contract C: strings 'false'/'true' produce the same result as the bug case (1).
$r12 = (& $target -HadPreferredReviewers 'false' -ManualReviewerSelection 'true' -PreferredReviewersOfferState not_made -SelectedReviewersJson '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]' | ConvertFrom-Json)
Assert-True ($r12.closeoutReady -eq $false) 'Case 12: string false/true should block like case 1.'
Assert-True ($r12.hadPreferredReviewers -eq $false) 'Case 12: hadPreferredReviewers should echo boolean $false.'
Assert-True ($r12.manualReviewerSelection -eq $true) 'Case 12: manualReviewerSelection should echo boolean $true.'

# --- vN+1 state axis (Finding A2) ---

# (13) vN+1 authored and not resubmitted -> blocks + prompt offers a 2nd round + echoes the state.
$r13 = Invoke-Closeout $false $false 'not_applicable' '[]' '[]' 'pendingResubmission' '' '' 'v3'
Assert-True ($r13.closeoutReady -eq $false) 'Case 13: pendingResubmission should block.'
Assert-True (@($r13.blockingReasons) -contains 'vnext-pending-resubmission') 'Case 13: vnext-pending-resubmission reason missing.'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$r13.requiredUserPrompt)) 'Case 13: 2nd-round prompt missing.'
Assert-True ([string]$r13.receiptAddendum -match 'vNextState=pendingResubmission') 'Case 13: receipt should echo vNextState.'

# (14) Decline without who/reason -> blocks (decline-unaudited).
$r14 = Invoke-Closeout $false $false 'not_applicable' '[]' '[]' 'resubmissionDeclinedByHuman' '' '' 'v3'
Assert-True ($r14.closeoutReady -eq $false) 'Case 14: decline without who/reason should block.'
Assert-True (@($r14.blockingReasons) -contains 'vnext-resubmission-decline-unaudited') 'Case 14: vnext-resubmission-decline-unaudited reason missing.'

# (15) Audited decline (who+reason+RoundId) -> releases and echoes who/reason/RoundId in the receipt.
$r15 = Invoke-Closeout $false $false 'not_applicable' '[]' '[]' 'resubmissionDeclinedByHuman' 'Reviewer' 'diff trivial; risco baixo' 'v9'
Assert-True ($r15.closeoutReady -eq $true) 'Case 15: audited decline should release.'
Assert-True ([string]$r15.receiptAddendum -match 'declinedBy=Reviewer') 'Case 15: receipt should echo who declined.'
Assert-True ([string]$r15.receiptAddendum -match 'RoundId=v9') 'Case 15: receipt should echo the decline RoundId.'
Assert-True ($r15.vNextState -eq 'resubmissionDeclinedByHuman') 'Case 15: vNextState should be echoed on the object.'
Assert-True ($r15.resubmissionDeclinedBy -eq 'Reviewer') 'Case 15: object should echo resubmissionDeclinedBy.'
Assert-True ([string]$r15.resubmissionDeclineReason -match 'trivial') 'Case 15: object should echo resubmissionDeclineReason.'

# (16) vN+1 resubmitted -> neutral, releases.
$r16 = Invoke-Closeout $false $false 'not_applicable' '[]' '[]' 'resubmitted'
Assert-True ($r16.closeoutReady -eq $true) 'Case 16: resubmitted should release.'
Assert-True (@($r16.blockingReasons).Count -eq 0) 'Case 16: resubmitted should not generate a block.'

# (17) notProduced (default) -> neutral and ALWAYS echoed in the receipt (fixes the silent risk).
$r17 = Invoke-Closeout $false $false 'not_applicable'
Assert-True ($r17.closeoutReady -eq $true) 'Case 17: notProduced should release.'
Assert-True ($r17.vNextState -eq 'notProduced') 'Case 17: default vNextState should be notProduced.'
Assert-True ([string]$r17.receiptAddendum -match 'vNextState=notProduced') 'Case 17: receipt should echo vNextState even on the default.'

# (18) Precedence: pending vN+1 AND curation offer omitted -> both block, but the
#      requiredUserPrompt is the vN+1 one (precedence), not the curation one.
$r18 = Invoke-Closeout $false $true 'not_made' '[{"backend":"opencode","targetModelKey":"ollama-cloud/minimax-m3"}]' '[]' 'pendingResubmission' '' '' 'v3'
Assert-True ($r18.closeoutReady -eq $false) 'Case 18: combined block should keep closeoutReady=false.'
Assert-True (@($r18.blockingReasons) -contains 'vnext-pending-resubmission') 'Case 18: vnext-pending-resubmission reason missing.'
Assert-True (@($r18.blockingReasons) -contains 'preferred-reviewers-offer-missing') 'Case 18: curation reason missing.'
Assert-True ([string]$r18.requiredUserPrompt -match 'not yet resubmitted') 'Case 18: prompt should prioritize vN+1, not curation.'

# (19) Decline with who+reason but WITHOUT RoundId -> blocks (RoundId scopes the decline).
$r19 = Invoke-Closeout $false $false 'not_applicable' '[]' '[]' 'resubmissionDeclinedByHuman' 'Reviewer' 'motivo qualquer' ''
Assert-True ($r19.closeoutReady -eq $false) 'Case 19: decline without RoundId should block.'
Assert-True (@($r19.blockingReasons) -contains 'vnext-resubmission-decline-unaudited') 'Case 19: decline-unaudited reason missing (RoundId).'

# (20) Decline with who+RoundId but WITHOUT reason -> blocks (one field alone is not enough).
$r20 = Invoke-Closeout $false $false 'not_applicable' '[]' '[]' 'resubmissionDeclinedByHuman' 'Reviewer' '' 'v9'
Assert-True ($r20.closeoutReady -eq $false) 'Case 20: decline without a reason should block.'
Assert-True (@($r20.blockingReasons) -contains 'vnext-resubmission-decline-unaudited') 'Case 20: decline-unaudited reason missing (reason).'

# (21) Decline with fields filled but with surrounding whitespace -> releases (Trim) and echoes
#      the value without the edges; pure whitespace would count as empty (IsNullOrWhiteSpace).
$r21 = Invoke-Closeout $false $false 'not_applicable' '[]' '[]' 'resubmissionDeclinedByHuman' '  Reviewer  ' '  motivo ok  ' 'v9'
Assert-True ($r21.closeoutReady -eq $true) 'Case 21: decline with whitespace edges should release after Trim.'
Assert-True ($r21.resubmissionDeclinedBy -eq 'Reviewer') 'Case 21: object should echo the trimmed value.'
Assert-True ([string]$r21.receiptAddendum -match 'declinedBy=Reviewer;') 'Case 21: receipt should echo the trimmed value.'

# (22) Final fallback states are accepted when skips do not count toward diversity.
$statesFallbackOk = @'
[
  {"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro","family":"ollama-cloud","state":"responded","attemptRole":"primary","countsForDiversity":true},
  {"backend":"opencode","targetModelKey":"nvidia/deepseek-ai/deepseek-v4-pro","family":"nvidia","state":"skippedAfterSuccess","attemptRole":"fallback","fallbackOf":"ollama-cloud/deepseek-v4-pro","countsForDiversity":false},
  {"backend":"opencode","targetModelKey":"ollama-cloud/glm-5.2","family":"ollama-cloud","state":"timeout","attemptRole":"primary","countsForDiversity":false},
  {"backend":"opencode","targetModelKey":"nvidia/z-ai/glm-5.1","family":"nvidia","state":"notAttempted","attemptRole":"fallback","fallbackOf":"ollama-cloud/glm-5.2","countsForDiversity":false},
  {"backend":"opencode","targetModelKey":"ollama-cloud/minimax-m3","family":"ollama-cloud","state":"gateDeny","attemptRole":"primary","countsForDiversity":false},
  {"backend":"opencode","targetModelKey":"nvidia/minimaxai/minimax-m3","family":"nvidia","state":"skippedByPolicy","attemptRole":"fallback","fallbackOf":"ollama-cloud/minimax-m3","countsForDiversity":false}
]
'@
$selectedFallbackOk = @'
[
  {"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro","fallbackChain":[{"backend":"opencode","targetModelKey":"nvidia/deepseek-ai/deepseek-v4-pro"}]},
  {"backend":"opencode","targetModelKey":"ollama-cloud/glm-5.2","fallbackChain":[{"backend":"opencode","targetModelKey":"nvidia/z-ai/glm-5.1"}]},
  {"backend":"opencode","targetModelKey":"ollama-cloud/minimax-m3","fallbackChain":[{"backend":"opencode","targetModelKey":"nvidia/minimaxai/minimax-m3"}]}
]
'@
$r22 = Invoke-Closeout $true $false 'not_applicable' $selectedFallbackOk $statesFallbackOk -PreferredReviewersSnapshotJson (New-TestSnapshot $selectedFallbackOk)
Assert-True ($r22.closeoutReady -eq $true) ("Case 22: final fallback states should release. reasons=$($r22.blockingReasons -join ',')")
Assert-True (@($r22.preferredReviewerStates).Count -eq 6) 'Case 22: should echo primaries + fallbacks.'
Assert-True ([string]($r22.preferredReviewerStates | Where-Object { $_.attemptRole -eq 'fallback' } | Select-Object -First 1).effortApplied -eq 'unset') 'Case 22: fallback effortApplied should be unset.'

# (23) A skip that counts toward diversity blocks.
$sel23 = '[{"backend":"opencode","targetModelKey":"ollama-cloud/x","fallbackChain":[{"backend":"opencode","targetModelKey":"nvidia/x"}]}]'
$statesSkipBad = '[{"backend":"opencode","targetModelKey":"nvidia/x","family":"nvidia","state":"skippedAfterSuccess","attemptRole":"fallback","fallbackOf":"ollama-cloud/x","countsForDiversity":true}]'
$r23 = Invoke-Closeout $true $false 'not_applicable' $sel23 $statesSkipBad -PreferredReviewersSnapshotJson (New-TestSnapshot $sel23)
Assert-True ($r23.closeoutReady -eq $false) 'Case 23: skip with countsForDiversity=true should block.'
Assert-True (@($r23.blockingReasons) -contains 'preferred-reviewer-state-skip-counts-diversity:nvidia/x:skippedAfterSuccess') 'Case 23: inflated-diversity reason missing.'

# (24) A silent notAttempted primary state blocks.
$sel24 = '[{"backend":"opencode","targetModelKey":"ollama-cloud/x"}]'
$statesPrimaryNotAttempted = '[{"backend":"opencode","targetModelKey":"ollama-cloud/x","family":"ollama-cloud","state":"notAttempted","attemptRole":"primary","countsForDiversity":false}]'
$r24 = Invoke-Closeout $true $false 'not_applicable' $sel24 $statesPrimaryNotAttempted -PreferredReviewersSnapshotJson (New-TestSnapshot $sel24)
Assert-True ($r24.closeoutReady -eq $false) 'Case 24: a silent notAttempted primary should block.'
Assert-True (@($r24.blockingReasons) -contains 'preferred-reviewer-primary-notattempted-silent:ollama-cloud/x') 'Case 24: notAttempted-primary reason missing.'

# (25) Insufficient diversity after fallback blocks the peer review receipt.
$r25 = (& $target -HadPreferredReviewers 'false' -ManualReviewerSelection 'false' -PreferredReviewersOfferState not_applicable -DiversityState insufficientDiversityAfterFallback | ConvertFrom-Json)
Assert-True ($r25.closeoutReady -eq $false) 'Case 25: insufficientDiversityAfterFallback should block closeout.'
Assert-True (@($r25.blockingReasons) -contains 'insufficient-diversity-after-fallback') 'Case 25: insufficient-diversity-after-fallback reason missing.'
Assert-True ([string]$r25.requiredUserPrompt -match 'insufficient diversity') 'Case 25: prompt should mention insufficient diversity.'

# (26) With an existing preferred-reviewers, SelectedReviewersJson cannot come in empty: without
#      the expected list there is no way to prove completeness of the states.
$snap26 = New-TestSnapshot '[{"backend":"codex","targetModelKey":"openai/gpt-5.5"}]'
$r26 = Invoke-Closeout $true $false 'not_applicable' '[]' '[{"backend":"codex","targetModelKey":"openai/gpt-5.5","state":"responded","countsForDiversity":true}]' -PreferredReviewersSnapshotJson $snap26
Assert-True ($r26.closeoutReady -eq $false) 'Case 26: HadPreferred=true with an empty SelectedReviewersJson should block.'
Assert-True (
    (@($r26.blockingReasons) -contains 'preferred-reviewer-expected-states-missing') -or
    (@($r26.blockingReasons) -contains 'preferred-snapshot-invalid')
) 'Case 26: should block on expected-states-missing or snapshot-invalid (reviewers vs empty selected).'

# (27) A partial state cannot release: every expected primary reviewer must appear.
$selectedTwo = '[{"backend":"codex","targetModelKey":"openai/gpt-5.5"},{"backend":"opencode","targetModelKey":"nvidia/z-ai/glm-5.2"}]'
$stateOne = '[{"backend":"codex","targetModelKey":"openai/gpt-5.5","state":"responded","countsForDiversity":true}]'
$r27 = Invoke-Closeout $true $false 'not_applicable' $selectedTwo $stateOne -PreferredReviewersSnapshotJson (New-TestSnapshot $selectedTwo)
Assert-True ($r27.closeoutReady -eq $false) 'Case 27: a partial state should block.'
Assert-True (@($r27.blockingReasons) -contains 'preferred-reviewer-state-missing:nvidia/z-ai/glm-5.2') 'Case 27: an omitted expected primary reviewer should be pointed out.'

# (28) An expected fallback also needs an auditable state when it is part of the preferred list.
$selectedWithFallback = '[{"backend":"codex","targetModelKey":"openai/gpt-5.5","fallbackChain":[{"backend":"opencode","targetModelKey":"nvidia/z-ai/glm-5.2"}]}]'
$r28 = Invoke-Closeout $true $false 'not_applicable' $selectedWithFallback $stateOne -PreferredReviewersSnapshotJson (New-TestSnapshot $selectedWithFallback)
Assert-True ($r28.closeoutReady -eq $false) 'Case 28: an omitted expected fallback should block.'
Assert-True (@($r28.blockingReasons) -contains 'preferred-reviewer-state-missing:nvidia/z-ai/glm-5.2') 'Case 28: an omitted expected fallback should be pointed out.'

# (29) A duplicate state cannot mask the absence of another expected preferred reviewer.
$stateDuplicate = @'
[
  {"backend":"codex","targetModelKey":"openai/gpt-5.5","state":"responded","countsForDiversity":true},
  {"backend":"codex","targetModelKey":"openai/gpt-5.5","state":"responded","countsForDiversity":true}
]
'@
$r29 = Invoke-Closeout $true $false 'not_applicable' $selectedTwo $stateDuplicate -PreferredReviewersSnapshotJson (New-TestSnapshot $selectedTwo)
Assert-True ($r29.closeoutReady -eq $false) 'Case 29: a duplicate state should block.'
Assert-True (@($r29.blockingReasons) -contains 'preferred-reviewer-state-duplicate:openai/gpt-5.5') 'Case 29: the duplicate should be pointed out.'
Assert-True (@($r29.blockingReasons) -contains 'preferred-reviewer-state-missing:nvidia/z-ai/glm-5.2') 'Case 29: a duplicate must not mask the absence of the other expected one.'

# (30) Manual selection also becomes a completeness contract when SelectedReviewersJson is
#      supplied: it cannot close with a partial state after the curation offer.
$r30 = Invoke-Closeout $false $true 'offered' $selectedTwo $stateOne
Assert-True ($r30.closeoutReady -eq $false) 'Case 30: manual selection with a partial state should block.'
Assert-True (@($r30.blockingReasons) -contains 'preferred-reviewer-state-missing:nvidia/z-ai/glm-5.2') 'Case 30: an omitted expected manual reviewer should be pointed out.'

# (31) Offer with -ProposedPreferredPath / -PreferredRoot / -Orchestrator: the prompt and receipt
#      must echo the resolved path (preferred-reviewers.<orch>.json), not the fixed machine literal.
$orchRoot = Get-LlmDelegateStateRoot
$orchProposed = Join-Path $orchRoot 'preferred-reviewers.cursor.json'
$r31 = Invoke-Closeout $false $true 'not_made' '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]' `
    -ProposedPreferredPath $orchProposed -PreferredRoot $orchRoot -Orchestrator 'cursor'
Assert-True ($r31.closeoutReady -eq $false) 'Case 31: an omitted offer should block.'
Assert-True (@($r31.blockingReasons) -contains 'preferred-reviewers-offer-missing') 'Case 31: offer reason missing.'
Assert-True ([string]$r31.requiredUserPrompt -match 'preferred-reviewers\.cursor\.json') 'Case 31: prompt should cite preferred-reviewers.cursor.json.'
Assert-True ([string]$r31.requiredUserPrompt -match "the 'cursor' orchestrator") "Case 31: prompt should label the cursor orchestrator, not just this machine."
Assert-True ([string]$r31.requiredUserPrompt -notmatch 'preferred reviewers for this machine in %LOCALAPPDATA%\\mimir-delegate\\preferred-reviewers\.json') 'Case 31: prompt must not cite only the fixed machine literal.'
Assert-True ([string]$r31.receiptAddendum -match 'destination=.*preferred-reviewers\.cursor\.json') 'Case 31: receipt destination= should echo the orchestrator path.'
Assert-True ([string]$r31.effectivePreferredPath -match 'preferred-reviewers\.cursor\.json$') 'Case 31: effectivePreferredPath should be the proposed path.'

# (32) Open orchestrator allow-list: an unknown but well-formed slug is accepted and
#      normalized to lowercase in the allowed preferred-reviewers.<orch>.json name.
$unkProposed = Join-Path $orchRoot 'preferred-reviewers.gemini.json'
$r32 = Invoke-Closeout $false $true 'not_made' '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]' `
    -ProposedPreferredPath $unkProposed -PreferredRoot $orchRoot -Orchestrator ' Gemini '
Assert-True (@($r32.blockingReasons) -notcontains 'preferred-path-mismatch') 'Case 32: unknown valid slug must not trip preferred-path-mismatch.'
Assert-True ([string]$r32.requiredUserPrompt -match 'preferred-reviewers\.gemini\.json') 'Case 32: prompt should cite preferred-reviewers.gemini.json.'

# (33) A slug that is not well-formed is rejected before any file name is built from it.
foreach ($badSlug in @('../x', 'Bad Slug!', ('a' * 41), 'a\b')) {
    $threw = $false
    try {
        Invoke-Closeout $false $true 'not_made' '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]' `
            -ProposedPreferredPath (Join-Path $orchRoot 'preferred-reviewers.json') -PreferredRoot $orchRoot -Orchestrator $badSlug | Out-Null
    } catch {
        $threw = ([string]$_.Exception.Message -match 'orchestrator')
    }
    Assert-True $threw "Case 33: invalid orchestrator slug '$badSlug' must be rejected."
}

# (34) Default offer path: with no -ProposedPreferredPath, the offer path is a real
#      path under the shared state root (Windows: %LOCALAPPDATA%\mimir-delegate; elsewhere
#      $XDG_DATA_HOME/mimir-delegate), never a literal '%LOCALAPPDATA%' resolved against the cwd, and
#      passing that same root as -PreferredRoot does not report a path mismatch. Off Windows,
#      XDG_DATA_HOME points to a folder that does not exist yet (GetFolderPath returns '').
$savedXdg34 = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
$temp34 = Join-Path ([System.IO.Path]::GetTempPath()) ('closeout-selftest-' + [guid]::NewGuid().ToString('N'))
try {
    if ($IsWindows) {
        $stateRoot34 = Join-Path $env:LOCALAPPDATA 'mimir-delegate'
    }
    else {
        $env:XDG_DATA_HOME = Join-Path $temp34 'xdg-missing'
        $stateRoot34 = Join-Path $env:XDG_DATA_HOME 'mimir-delegate'
    }
    $expected34 = Join-Path $stateRoot34 'preferred-reviewers.json'
    $manual34 = '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]'
    $r34 = Invoke-Closeout $false $true 'not_made' $manual34
    Assert-True ([string]$r34.effectivePreferredPath -eq $expected34) "Case 34: default offer path should be '$expected34'; got '$($r34.effectivePreferredPath)'."
    if (-not $IsWindows) {
        Assert-True ([string]$r34.effectivePreferredPath -notmatch '%') 'Case 34: off Windows, the offer path must not contain a literal %LOCALAPPDATA%.'
        Assert-True ([string]$r34.requiredUserPrompt -notmatch '%LOCALAPPDATA%') 'Case 34: off Windows, the prompt must not cite %LOCALAPPDATA%.'
    }
    $r34b = Invoke-Closeout $false $true 'not_made' $manual34 -PreferredRoot $stateRoot34
    Assert-True (@($r34b.blockingReasons) -notcontains 'preferred-path-mismatch') "Case 34: the default offer path must pass the allowed-directory check for -PreferredRoot; got $(@($r34b.blockingReasons) -join ', ')."
    Assert-True ([string]$r34b.effectivePreferredPath -eq $expected34) "Case 34: with -PreferredRoot the offer path should stay '$expected34'; got '$($r34b.effectivePreferredPath)'."
    Assert-True (-not (Test-Path -LiteralPath $temp34)) 'Case 34: the closeout must not create the state folder.'
}
finally {
    if ($null -eq $savedXdg34) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdg34 }
    Remove-Item -LiteralPath $temp34 -Recurse -Force -ErrorAction SilentlyContinue
}

# (35) Unresolvable state root off Windows: no XDG_DATA_HOME, no usable HOME and an empty
#      GetFolderPath('LocalApplicationData'). Saving preferred reviewers is optional, so the
#      closeout must still return its JSON envelope, skip the save offer without a blocking
#      reason, and leave a warning in receiptAddendum; the rest of the round's outcome is what
#      it would be without the offer. HOME is set to a blank value: the helper treats it as
#      unset, and .NET does not fall back to the account's home folder from the passwd database,
#      so GetFolderPath is empty on any host. PowerShell's own $HOME (read-only, taken from HOME
#      at startup) is blanked too and restored afterwards. .NET resolves the blank home against
#      the process working folder, so the case runs from a fresh empty one, both as the process
#      folder and as the PowerShell location (a stray ' /.local/share' there would make
#      GetFolderPath non-empty).
if ($IsWindows) {
    Write-Host 'SKIP: off-Windows unresolvable state root case (Windows host)' -ForegroundColor Yellow
}
else {
    $savedXdg35 = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
    $savedHomeEnv35 = [Environment]::GetEnvironmentVariable('HOME')
    $savedHomeVar35 = $HOME
    $savedCwd35 = [Environment]::CurrentDirectory
    $cwd35 = Join-Path ([System.IO.Path]::GetTempPath()) ('closeout-selftest-cwd-' + [guid]::NewGuid().ToString('N'))
    $pushed35 = $false
    try {
        [void][System.IO.Directory]::CreateDirectory($cwd35)
        [Environment]::CurrentDirectory = $cwd35
        Push-Location -LiteralPath $cwd35
        $pushed35 = $true
        Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue
        $env:HOME = ' '
        Set-Variable -Name HOME -Value '' -Scope Global -Force
        Assert-True ([Environment]::GetFolderPath('LocalApplicationData') -eq '') 'Case 35 precondition: GetFolderPath(LocalApplicationData) should be empty.'
        $manual35 = '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]'
        $states35 = '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro","family":"deepseek","state":"responded","attemptRole":"primary","countsForDiversity":true}]'
        $r35 = $null
        try { $r35 = Invoke-Closeout $false $true 'not_made' $manual35 $states35 }
        catch { throw "Case 35: the closeout should return its JSON envelope, not throw: $($_.Exception.Message)" }
        Assert-True (@($r35.blockingReasons) -notcontains 'preferred-path-state-root-unavailable') "Case 35: an unresolvable state root must not block the round; got $(@($r35.blockingReasons) -join ', ')."
        Assert-True ($r35.closeoutReady -eq $true) "Case 35: with the offer skipped, a complete round should release; got $(@($r35.blockingReasons) -join ', ')."
        Assert-True ($r35.requiresPreferredOffer -eq $false) 'Case 35: the save offer should be skipped (requiresPreferredOffer=false).'
        Assert-True ([string]::IsNullOrWhiteSpace([string]$r35.requiredUserPrompt)) "Case 35: no save offer should be prompted; got '$($r35.requiredUserPrompt)'."
        Assert-True ([string]::IsNullOrWhiteSpace([string]$r35.effectivePreferredPath)) "Case 35: no offer path can be proposed; got '$($r35.effectivePreferredPath)'."
        Assert-True ([string]$r35.receiptAddendum -match 'Preferred-reviewer curation: skipped') "Case 35: the receipt should record the skipped offer; got '$($r35.receiptAddendum)'."
        Assert-True ([string]$r35.receiptAddendum -match 'XDG_DATA_HOME and HOME') "Case 35: the warning should carry the helper's reason; got '$($r35.receiptAddendum)'."
        Assert-True ([string]$r35.receiptAddendum -match 'ProposedPreferredPath') 'Case 35: the warning should point to -ProposedPreferredPath.'
        Assert-True ([string]$r35.receiptAddendum -notmatch '%LOCALAPPDATA%|\.local/share') "Case 35: the receipt must not invent a path; got '$($r35.receiptAddendum)'."

        # (35a) Skipping the offer leaves the other checks intact: missing reviewer states still
        #       block, and the state root adds no reason of its own.
        $r35a = Invoke-Closeout $false $true 'not_made' $manual35
        Assert-True ($r35a.closeoutReady -eq $false) 'Case 35a: missing reviewer states should still block.'
        Assert-True ((@($r35a.blockingReasons) -join ',') -eq 'preferred-reviewer-state-missing:ollama-cloud/deepseek-v4-pro') "Case 35a: only the missing state should block; got $(@($r35a.blockingReasons) -join ', ')."

        # (35b) An explicit -ProposedPreferredPath needs no state root: the offer works as usual.
        $proposed35 = Join-Path ([System.IO.Path]::GetTempPath()) 'closeout-35b/preferred-reviewers.json'
        $r35b = $null
        try { $r35b = Invoke-Closeout $false $true 'offered' -ProposedPreferredPath $proposed35 }
        catch { throw "Case 35b: the closeout should not throw with -ProposedPreferredPath: $($_.Exception.Message)" }
        Assert-True ($r35b.closeoutReady -eq $true) "Case 35b: with -ProposedPreferredPath the offered round should release; got $(@($r35b.blockingReasons) -join ', ')."
        Assert-True ($r35b.requiresPreferredOffer -eq $true) 'Case 35b: with -ProposedPreferredPath the save offer still applies.'
        Assert-True ([string]$r35b.effectivePreferredPath -eq $proposed35) "Case 35b: the offer path should be '$proposed35'; got '$($r35b.effectivePreferredPath)'."
        $r35c = Invoke-Closeout $false $true 'not_made' -ProposedPreferredPath $proposed35
        Assert-True (@($r35c.blockingReasons) -contains 'preferred-reviewers-offer-missing') "Case 35b: with -ProposedPreferredPath an omitted offer should still block; got $(@($r35c.blockingReasons) -join ', ')."
    }
    finally {
        if ($pushed35) { Pop-Location }
        [Environment]::CurrentDirectory = $savedCwd35
        Set-Variable -Name HOME -Value $savedHomeVar35 -Scope Global -Force
        if ($null -eq $savedHomeEnv35) { Remove-Item Env:\HOME -ErrorAction SilentlyContinue } else { $env:HOME = $savedHomeEnv35 }
        if ($null -eq $savedXdg35) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdg35 }
        Remove-Item -LiteralPath $cwd35 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# (36) Fallback display on Windows: when no offer path materialized (provenance given as
#      -PreferenceSource none without a path), the save prompt and the receipt show the path under
#      the resolved state root, not '%LOCALAPPDATA%' text. A fully qualified process-level
#      LOCALAPPDATA wins in the helper, so the case points it to a fresh folder that is never
#      created.
if (-not $IsWindows) {
    Write-Host 'SKIP: Windows fallback display case (non-Windows host)' -ForegroundColor Yellow
}
else {
    $savedLocalAppData36 = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    $temp36 = Join-Path ([System.IO.Path]::GetTempPath()) ('closeout-selftest-lad-' + [guid]::NewGuid().ToString('N'))
    try {
        $env:LOCALAPPDATA = $temp36
        $expected36 = Join-Path (Join-Path $temp36 'mimir-delegate') 'preferred-reviewers.json'
        $manual36 = '[{"backend":"opencode","targetModelKey":"ollama-cloud/deepseek-v4-pro"}]'
        $r36 = Invoke-Closeout $false $true 'not_made' $manual36 -PreferenceSource 'none'
        Assert-True ([string]::IsNullOrWhiteSpace([string]$r36.effectivePreferredPath)) "Case 36 precondition: no offer path should materialize; got '$($r36.effectivePreferredPath)'."
        Assert-True ($r36.requiresPreferredOffer -eq $true) 'Case 36 precondition: the save offer should apply.'
        Assert-True (([string]$r36.requiredUserPrompt).Contains(" in ${expected36}?")) "Case 36: the save prompt should name '$expected36'; got '$($r36.requiredUserPrompt)'."
        Assert-True (([string]$r36.receiptAddendum).Contains("destination=$expected36.")) "Case 36: the receipt should name '$expected36'; got '$($r36.receiptAddendum)'."
        Assert-True ([string]$r36.requiredUserPrompt -notmatch '%LOCALAPPDATA%') "Case 36: the prompt must not cite '%LOCALAPPDATA%'; got '$($r36.requiredUserPrompt)'."
        Assert-True ([string]$r36.receiptAddendum -notmatch '%LOCALAPPDATA%') "Case 36: the receipt must not cite '%LOCALAPPDATA%'; got '$($r36.receiptAddendum)'."
        Assert-True (-not (Test-Path -LiteralPath $temp36)) 'Case 36: the closeout must not create the state folder.'
    }
    finally {
        if ($null -eq $savedLocalAppData36) { Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA = $savedLocalAppData36 }
        Remove-Item -LiteralPath $temp36 -Recurse -Force -ErrorAction SilentlyContinue
    }
}

<#
Old cases kept for historical coverage:
  - no prior preferences + manual choice + offer omitted -> blocks;
  - offer presented/declined/deferred -> releases the ad-hoc round;
  - states of existing preferred reviewers are now mandatory at closeout.
vN+1 cases (Finding A2): pendingResubmission/decline-unaudited block;
audited decline and resubmitted/notProduced release; vNextState always echoed.
#>

Write-Output 'OK: Test-LlmDelegatePeerReviewCloseoutSelfTest.ps1'
