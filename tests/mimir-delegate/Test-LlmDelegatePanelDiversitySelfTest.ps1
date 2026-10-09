#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Self-test for Resolve-LlmDelegatePanelDiversity.ps1 (mimir-delegate skill).
# Covers the diversity floor (>=2 distinct families) and the states:
#  panelReady / needsBatchAuthorization / insufficientDiversity /
#  insufficientDiversityAfterFallback, plus droppedUnknownFamilies.

$target = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-LlmDelegatePanelDiversity.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $target -PathType Leaf) "Script missing: $target"

function Invoke-Diversity {
    param([string]$Json, [string]$AuthorFamily)
    if ([string]::IsNullOrWhiteSpace($AuthorFamily)) {
        return (& $target -CandidatesJson $Json | ConvertFrom-Json)
    }
    return (& $target -CandidatesJson $Json -AuthorFamily $AuthorFamily | ConvertFrom-Json)
}

# (1) 2 allow from distinct families -> panelReady
$r1 = Invoke-Diversity '[{"targetModelKey":"openai/gpt-5.5","verdict":"allow"},{"targetModelKey":"anthropic/claude-opus-4-8","verdict":"allow"}]'
Assert-True ($r1.state -eq 'panelReady') "Case 1: expected panelReady; got '$($r1.state)'."
Assert-True ($r1.panelReady -eq $true) 'Case 1: panelReady should be true.'

# (2) 1 allow + 1 ask from a NEW family -> needsBatchAuthorization, ask listed
$r2 = Invoke-Diversity '[{"targetModelKey":"openai/gpt-5.5","verdict":"allow"},{"targetModelKey":"ollama-cloud/deepseek-v4-pro","verdict":"ask"}]'
Assert-True ($r2.state -eq 'needsBatchAuthorization') "Case 2: expected needsBatchAuthorization; got '$($r2.state)'."
Assert-True (@($r2.askToAuthorize).Count -eq 1) 'Case 2: should list 1 candidate to authorize.'
Assert-True (@($r2.askToAuthorize)[0].family -eq 'ollama-cloud') 'Case 2: the ask to authorize should be ollama-cloud.'

# (3) 1 allow only -> insufficientDiversity, fallback "second opinion (1)"
$r3 = Invoke-Diversity '[{"targetModelKey":"openai/gpt-5.5","verdict":"allow"}]'
Assert-True ($r3.state -eq 'insufficientDiversity') "Case 3: expected insufficientDiversity; got '$($r3.state)'."
Assert-True ($r3.fallbackLabel -eq 'second opinion (1)') "Case 3: fallbackLabel should be 'second opinion (1)'; got '$($r3.fallbackLabel)'."

# (4) 1 allow + 1 ask from the SAME family -> insufficientDiversity (ask does not add a family)
$r4 = Invoke-Diversity '[{"targetModelKey":"openai/gpt-5.5","verdict":"allow"},{"targetModelKey":"openai/gpt-5-mini","verdict":"ask"}]'
Assert-True ($r4.state -eq 'insufficientDiversity') "Case 4: ask from the same family should not enable the panel; got '$($r4.state)'."
Assert-True (@($r4.askToAuthorize).Count -eq 0) 'Case 4: ask from an already-covered family does not enter askToAuthorize.'

# (5) author's family in the panel -> panelReady, but authorFamilyInPanel flagged
$r5 = Invoke-Diversity '[{"targetModelKey":"anthropic/claude-opus-4-8","verdict":"allow"},{"targetModelKey":"openai/gpt-5.5","verdict":"allow"}]' -AuthorFamily 'anthropic'
Assert-True ($r5.state -eq 'panelReady') "Case 5: expected panelReady; got '$($r5.state)'."
Assert-True ($r5.authorFamilyInPanel -eq $true) 'Case 5: authorFamilyInPanel should be true (anthropic in the panel).'

# (6) `deny` is ignored: 1 allow + 1 deny -> insufficientDiversity (deny does not count)
$r6 = Invoke-Diversity '[{"targetModelKey":"openai/gpt-5.5","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"deny"}]'
Assert-True ($r6.state -eq 'insufficientDiversity') "Case 6: deny should not count toward diversity; got '$($r6.state)'."

# (7) advisory invariant: the output does not carry an authorization verdict
Assert-True ($null -eq ($r1.PSObject.Properties['verdict'])) 'Case 7: the output must NOT have a verdict field (it is advisory, not authorization).'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$r1.note)) 'Case 7: note (advisory invariant) missing.'

# (8) Post-fallback: requires dispatchAttempted=true OR attempts>=1 for AfterFallback
$r8 = Invoke-Diversity '[{"targetModelKey":"openai/gpt-5.5","state":"responded","attemptRole":"fallback","fallbackOf":"ollama-cloud/deepseek","dispatchAttempted":true,"countsForDiversity":true},{"targetModelKey":"ollama-cloud/deepseek","state":"skippedAfterSuccess","attemptRole":"fallback","fallbackOf":"ollama-cloud/primary","countsForDiversity":false}]'
Assert-True ($r8.state -eq 'insufficientDiversityAfterFallback') "Case 8: expected insufficientDiversityAfterFallback; got '$($r8.state)'."
Assert-True ($r8.panelReady -eq $false) 'Case 8: panelReady should be false.'
Assert-True (@($r8.distinctFamiliesAllow).Count -eq 1) 'Case 8: skips with countsForDiversity=false must not inflate families.'

# (9) antigravity/gemini-* collapses into google (no diversity against google directly)
$r9 = Invoke-Diversity '[{"targetModelKey":"antigravity/gemini-3.6-flash","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"allow"}]'
Assert-True ($r9.state -eq 'insufficientDiversity') "Case 9: antigravity/gemini and google share the google family; expected insufficientDiversity; got '$($r9.state)'."

# (10) antigravity/claude-* vs google/gemini-* are 2 distinct families (anthropic vs google)
$r10 = Invoke-Diversity '[{"targetModelKey":"antigravity/claude-sonnet-4-6","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"allow"}]'
Assert-True ($r10.state -eq 'panelReady') "Case 10: antigravity/claude-* (anthropic) + google (google) -> panelReady; got '$($r10.state)'."

# (11) the 'unknown' key (no slash) is dropped; only google counts -> insufficientDiversity
$r11 = Invoke-Diversity '[{"targetModelKey":"unknown","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"allow"}]'
Assert-True ($r11.state -eq 'insufficientDiversity') "Case 11: unknown dropped; expected insufficientDiversity; got '$($r11.state)'."
Assert-True ($r11.unknownFamiliesPresent -eq $true) 'Case 11: unknownFamiliesPresent should be true.'
Assert-True (@($r11.dispatchable).Count -eq 1) "Case 11: only google should be dispatchable; got '$(@($r11.dispatchable).Count)'."

# (12) nvidia/minimaxai/* vs nvidia/z-ai/* are 2 distinct creators (minimaxai vs z-ai) -> panelReady
$r12 = Invoke-Diversity '[{"targetModelKey":"nvidia/minimaxai/minimax-m3","verdict":"allow"},{"targetModelKey":"nvidia/z-ai/glm-5.2","verdict":"allow"}]'
Assert-True ($r12.state -eq 'panelReady') "Case 12: nvidia/minimaxai and nvidia/z-ai are distinct creators; expected panelReady; got '$($r12.state)'."
Assert-True (@($r12.distinctFamiliesAllow).Count -eq 2) "Case 12: expected 2 distinctFamiliesAllow; got '$(@($r12.distinctFamiliesAllow).Count)'."

# (13) nvidia/meta/* vs meta/* direct share the meta creator -> insufficientDiversity
$r13 = Invoke-Diversity '[{"targetModelKey":"nvidia/meta/llama-3.3-70b-instruct","verdict":"allow"},{"targetModelKey":"meta/llama-3.3-70b-instruct","verdict":"allow"}]'
Assert-True ($r13.state -eq 'insufficientDiversity') "Case 13: nvidia/meta and meta direct share the meta creator; expected insufficientDiversity; got '$($r13.state)'."

# (14) canonical sub-org normalization: nvidia/deepseek-ai/* collapses into deepseek
$r14 = Invoke-Diversity '[{"targetModelKey":"nvidia/deepseek-ai/deepseek-r1","verdict":"allow"},{"targetModelKey":"deepseek/deepseek-r1","verdict":"allow"}]'
Assert-True ($r14.state -eq 'insufficientDiversity') "Case 14: deepseek-ai and deepseek normalize to the same creator; expected insufficientDiversity; got '$($r14.state)'."

# (15) canonical sub-org normalization: nvidia/mistralai/* collapses into mistral
$r15 = Invoke-Diversity '[{"targetModelKey":"nvidia/mistralai/mistral-large","verdict":"allow"},{"targetModelKey":"mistral/mistral-large","verdict":"allow"}]'
Assert-True ($r15.state -eq 'insufficientDiversity') "Case 15: mistralai and mistral normalize to the same creator; expected insufficientDiversity; got '$($r15.state)'."

# (16) canonical sub-org normalization: nvidia/qwen/* collapses into alibaba
$r16 = Invoke-Diversity '[{"targetModelKey":"nvidia/qwen/qwen2.5-coder-32b","verdict":"allow"},{"targetModelKey":"alibaba/qwen2.5-coder-32b","verdict":"allow"}]'
Assert-True ($r16.state -eq 'insufficientDiversity') "Case 16: qwen and alibaba normalize to the same creator; expected insufficientDiversity; got '$($r16.state)'."

# (17) nvidia/nvidia/* (Nemotron) vs nvidia/minimaxai/* are 2 distinct creators (nvidia vs minimaxai)
$r17 = Invoke-Diversity '[{"targetModelKey":"nvidia/nvidia/nemotron-3-super-120b-a12b","verdict":"allow"},{"targetModelKey":"nvidia/minimaxai/minimax-m3","verdict":"allow"}]'
Assert-True ($r17.state -eq 'panelReady') "Case 17: nvidia/nvidia and nvidia/minimaxai are distinct creators; expected panelReady; got '$($r17.state)'."

# (18) a 2-level nvidia key (e.g. nvidia/nemotron-*) resolves to the nvidia creator
$r18 = Invoke-Diversity '[{"targetModelKey":"nvidia/nemotron-3-super-120b-a12b","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"allow"}]'
Assert-True ($r18.state -eq 'panelReady') "Case 18: a 2-level nvidia key should resolve to the nvidia creator; got '$($r18.state)'."
Assert-True (@($r18.distinctFamiliesAllow) -contains 'nvidia') "Case 18: distinctFamiliesAllow should contain 'nvidia'."

# (19) an unknown sub-org under nvidia is dropped (custom-lab off the allowlist)
$r19 = Invoke-Diversity '[{"targetModelKey":"nvidia/custom-lab/model-x","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"allow"}]'
Assert-True ($r19.state -eq 'insufficientDiversity') "Case 19: custom-lab dropped; expected insufficientDiversity; got '$($r19.state)'."
Assert-True ($r19.unknownFamiliesPresent -eq $true) 'Case 19: unknownFamiliesPresent should be true.'
Assert-True (-not (@($r19.distinctFamiliesAllow) -contains 'custom-lab')) 'Case 19: custom-lab must not count toward the floor.'

# (20) antigravity/gpt-* collapses into openai
$r20 = Invoke-Diversity '[{"targetModelKey":"antigravity/gpt-5-preview","verdict":"allow"},{"targetModelKey":"openai/gpt-5.5","verdict":"allow"}]'
Assert-True ($r20.state -eq 'insufficientDiversity') "Case 20: antigravity/gpt-* and openai share the openai creator; expected insufficientDiversity; got '$($r20.state)'."

# (21) antigravity with an unknown model preserves the historical google default
$r21 = Invoke-Diversity '[{"targetModelKey":"antigravity/custom-model-y","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"allow"}]'
Assert-True ($r21.state -eq 'insufficientDiversity') "Case 21: antigravity with an unknown model should fall back to the google default; expected insufficientDiversity; got '$($r21.state)'."

# (22) two unknown 2-level nvidia keys both collapse into the conservative nvidia fallback (avoids overcounting)
$r22 = Invoke-Diversity '[{"targetModelKey":"nvidia/custom-model-a","verdict":"allow"},{"targetModelKey":"nvidia/custom-model-b","verdict":"allow"}]'
Assert-True ($r22.state -eq 'insufficientDiversity') "Case 22: unknown 2-level nvidia keys should collapse into nvidia (no overcounting); expected insufficientDiversity; got '$($r22.state)'."
Assert-True (@($r22.distinctFamiliesAllow).Count -eq 1) "Case 22: expected 1 distinctFamiliesAllow ('nvidia'); got '$(@($r22.distinctFamiliesAllow).Count)'."
Assert-True (@($r22.distinctFamiliesAllow) -contains 'nvidia') "Case 22: distinctFamiliesAllow should contain 'nvidia'."

# (23) two primaries, one responds, no chain -> insufficientDiversity (not AfterFallback)
$r23 = Invoke-Diversity '[{"targetModelKey":"openai/gpt-5.5","state":"responded","attemptRole":"primary"},{"targetModelKey":"anthropic/claude-opus-4-8","state":"error","attemptRole":"primary"}]'
Assert-True ($r23.state -eq 'insufficientDiversity') "Case 23: expected insufficientDiversity (no fallback evidence); got '$($r23.state)'."
Assert-True ($r23.state -ne 'insufficientDiversityAfterFallback') 'Case 23: must not be AfterFallback without a dispatched chain.'

# (24) dropped unknown appears in droppedUnknownFamilies
$r24 = Invoke-Diversity '[{"targetModelKey":"unknown","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","verdict":"allow"}]'
Assert-True ($r24.unknownFamiliesPresent -eq $true) 'Case 24: unknownFamiliesPresent should be true.'
$droppedKeys = @($r24.droppedUnknownFamilies | ForEach-Object { [string]$_.targetModelKey })
Assert-True ($droppedKeys -contains 'unknown') "Case 24: droppedUnknownFamilies should contain 'unknown'; got '$($droppedKeys -join ',')'."

# (25) native Grok in Cursor without a slash resolves to xai and opens diversity against openai
$r25 = Invoke-Diversity '[{"targetModelKey":"cursor-grok-4.6-medium","verdict":"allow"},{"targetModelKey":"openai/gpt-5.6","verdict":"allow"}]'
Assert-True ($r25.state -eq 'panelReady') "Case 25: cursor-grok-* + openai should form panelReady; got '$($r25.state)'."
Assert-True (@($r25.distinctFamiliesAllow).Count -eq 2) "Case 25: expected xai + openai; got '$(@($r25.distinctFamiliesAllow) -join ',')'."
Assert-True (@($r25.distinctFamiliesAllow) -contains 'xai') "Case 25: distinctFamiliesAllow should contain 'xai'."
Assert-True (@($r25.distinctFamiliesAllow) -contains 'openai') "Case 25: distinctFamiliesAllow should contain 'openai'."

# (26) the two spellings of native Grok in Cursor represent the same xai creator
$r26 = Invoke-Diversity '[{"targetModelKey":"cursor-grok-4.6-medium","verdict":"allow"},{"targetModelKey":"cursor/grok-4","verdict":"allow"}]'
Assert-True ($r26.state -eq 'insufficientDiversity') "Case 26: the two Cursor/Grok spellings should not create diversity; got '$($r26.state)'."
Assert-True (@($r26.distinctFamiliesAllow).Count -eq 1) "Case 26: expected a single creator; got '$(@($r26.distinctFamiliesAllow) -join ',')'."
Assert-True (@($r26.distinctFamiliesAllow) -contains 'xai') "Case 26: distinctFamiliesAllow should contain 'xai'."

# (27) Cursor without an explicit mapping remains unknown for the diversity floor
$r27 = Invoke-Diversity '[{"targetModelKey":"cursor/unmapped-model","verdict":"allow"},{"targetModelKey":"openai/gpt-5.6","verdict":"allow"}]'
Assert-True ($r27.state -eq 'insufficientDiversity') "Case 27: unknown cursor/<model> should not open diversity; got '$($r27.state)'."
Assert-True ($r27.unknownFamiliesPresent -eq $true) 'Case 27: cursor/<model> without a mapping should flag an unknown family.'
Assert-True (@($r27.distinctFamiliesAllow).Count -eq 1) "Case 27: only openai should count; got '$(@($r27.distinctFamiliesAllow) -join ',')'."
Assert-True (-not (@($r27.distinctFamiliesAllow) -contains 'cursor')) "Case 27: cursor should not count as a known creator."

# (28) native Composer resolves to anysphere (weight creator) and opens diversity against openai
$r28 = Invoke-Diversity '[{"targetModelKey":"cursor/composer-2","verdict":"allow"},{"targetModelKey":"openai/gpt-5.6","verdict":"allow"}]'
Assert-True ($r28.state -eq 'panelReady') "Case 28: cursor/composer-* + openai should form panelReady; got '$($r28.state)'."
Assert-True (@($r28.distinctFamiliesAllow) -contains 'anysphere') "Case 28: distinctFamiliesAllow should contain 'anysphere'; got '$(@($r28.distinctFamiliesAllow) -join ',')'."

# (29) Composer and Grok are DISTINCT creators: a corporate acquisition does not merge weight lineage
$r29 = Invoke-Diversity '[{"targetModelKey":"cursor-composer-2-medium","verdict":"allow"},{"targetModelKey":"cursor/grok-4","verdict":"allow"}]'
Assert-True ($r29.state -eq 'panelReady') "Case 29: Composer + Grok should form panelReady; got '$($r29.state)'."
Assert-True (@($r29.distinctFamiliesAllow).Count -eq 2) "Case 29: expected anysphere + xai; got '$(@($r29.distinctFamiliesAllow) -join ',')'."
Assert-True (@($r29.distinctFamiliesAllow) -contains 'anysphere') "Case 29: distinctFamiliesAllow should contain 'anysphere'."
Assert-True (@($r29.distinctFamiliesAllow) -contains 'xai') "Case 29: distinctFamiliesAllow should contain 'xai'."

Write-Host "OK: Test-LlmDelegatePanelDiversitySelfTest.ps1"
