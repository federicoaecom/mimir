#requires -Version 7.4
<#
.SYNOPSIS
    Resolves the Model Creator (structural foundation family) for diversity-floor evaluation.
.DESCRIPTION
    Extracts the Model Creator (structural family) from the targetModelKey.

    Models under aggregator providers collapse into the Model Creator:
      - nvidia/<creator>/<model> (3 levels) -> resolves the 2nd segment (<creator>) with canonical normalization
        (e.g.: deepseek-ai -> deepseek, mistralai -> mistral, qwen -> alibaba, meta-llama/facebook -> meta,
        thudm/glm -> z-ai, minimax/minimaxai -> minimaxai, moonshotai -> moonshot; unknown -> 2nd segment as-is).
      - nvidia/<model> (2 levels) -> nemotron-* -> nvidia, llama-* -> meta, fallback -> nvidia.
      - antigravity/* (2 levels) -> antigravity/claude-* -> anthropic, antigravity/gpt-* -> openai,
        antigravity/gemini-* or default model -> google.

    For 2-level aggregators with no creator in the path (e.g. ollama-cloud/*, opencode-go/*), returns the
    provider prefix (a known, documented limit to preserve the dispatcher's concurrency semaphores).

    Slash-less keys (e.g. 'unknown', 'gpt-5') keep the key itself as the family,
    except for Cursor harness slugs that map to the Model Creator (e.g. cursor-grok-* -> xai,
    cursor-composer-* -> anysphere). Creator = who trained the weights, not the corporate owner:
    Composer (Anysphere) and Grok (xAI) are distinct creators and both count toward the floor.

    Test-LlmDelegateFamilyKnown: versioned allowlist of creators that count toward the diversity floor.
    A family derived outside the list is unknown for the floor (it does not collapse in the Get-* helper).
#>

# Initial normative list (case-insensitive). Extend only with a human decision + docs.
$script:LlmDelegateKnownFamilies = @(
    'openai', 'anthropic', 'google', 'moonshot', 'z-ai', 'deepseek', 'mistral', 'alibaba',
    'meta', 'minimaxai', 'nvidia', 'ollama-cloud', 'opencode-go', 'atlas-cloud',
    'github-copilot', 'microsoft', 'xai', 'anysphere'
)

function Test-LlmDelegateFamilyKnown {
    [CmdletBinding()]
    param(
        [string]$Family
    )
    Set-StrictMode -Version Latest
    if ([string]::IsNullOrWhiteSpace($Family)) { return $false }
    $trim = $Family.Trim()
    foreach ($f in $script:LlmDelegateKnownFamilies) {
        if ($f.Equals($trim, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Cursor harness key in both spellings: 'cursor/<model>' (with slash) and 'cursor-<model>'
# (slash-less slug, e.g. cursor-grok-*, cursor-composer-*). These models only exist inside
# Cursor: legitimate as a native primary reviewer with a known Creator, never as a CLI backend target
# nor as a fallbackChain link. Predicate shared by the curation's writer (Set-) and reader
# (Resolve-), so the two sides never diverge.
function Test-LlmDelegateCursorHarnessKey {
    [CmdletBinding()]
    param(
        [string]$TargetModelKey
    )
    Set-StrictMode -Version Latest
    if ([string]::IsNullOrWhiteSpace($TargetModelKey)) { return $false }
    $t = $TargetModelKey.Trim()
    if ($t -notmatch '/') { return $t.StartsWith('cursor-', [System.StringComparison]::OrdinalIgnoreCase) }
    $first = @($t -split '/')[0]
    return $first.Equals('cursor', [System.StringComparison]::OrdinalIgnoreCase)
}

# Harness the key belongs to, when the key itself identifies it ('cursor/grok-4' and
# 'cursor-grok-*' -> 'cursor'). Returns $null when the key carries no such information
# (e.g. 'moonshot/kimi-k3-max', which could be the native of any harness) — this is why
# harness-vs-orchestrator enforcement is PARTIAL by nature, as declared in doc 15.
function Get-LlmDelegateKeyHarness {
    [CmdletBinding()]
    param(
        [string]$TargetModelKey
    )
    Set-StrictMode -Version Latest
    if (Test-LlmDelegateCursorHarnessKey -TargetModelKey $TargetModelKey) { return 'cursor' }
    return $null
}

function Get-LlmDelegateTargetFamily {
    [CmdletBinding()]
    param(
        [string]$TargetModelKey
    )
    Set-StrictMode -Version Latest
    if ([string]::IsNullOrWhiteSpace($TargetModelKey)) { return $null }

    $trimmed = $TargetModelKey.Trim()

    # Slash-less native Cursor (harness) slugs: map to the Creator of the weights.
    if ($trimmed -ilike 'cursor-grok-*')     { return 'xai' }
    if ($trimmed -ilike 'cursor-composer-*') { return 'anysphere' }

    if ($trimmed -notmatch '/') { return $trimmed }

    $parts = @($trimmed -split '/')
    $fam = $parts[0].Trim()

    # cursor/grok-* and cursor/composer-* (slash form) -> Creator of the weights
    if ($fam -ieq 'cursor') {
        $modelId = if ($parts.Count -gt 1) { ($parts[1..($parts.Count - 1)] -join '/').Trim() } else { '' }
        if ($modelId -ilike 'grok-*')     { return 'xai' }
        if ($modelId -ilike 'composer-*') { return 'anysphere' }
    }

    if ($fam -ieq 'antigravity') {
        $modelId = if ($parts.Count -gt 1) { ($parts[1..($parts.Count - 1)] -join '/').Trim() } else { '' }
        if ($modelId -ilike 'claude-*') { return 'anthropic' }
        if ($modelId -ilike 'gpt-*')    { return 'openai' }
        return 'google'
    }

    if ($fam -ieq 'nvidia') {
        if ($parts.Count -ge 3) {
            $creatorRaw = $parts[1].Trim().ToLowerInvariant()
            # The adopted canonical slugs reflect the model catalog's official convention
            switch ($creatorRaw) {
                'deepseek-ai' { return 'deepseek' }
                'mistralai'   { return 'mistral' }
                'qwen'        { return 'alibaba' }
                'meta-llama'  { return 'meta' }
                'facebook'    { return 'meta' }
                'thudm'       { return 'z-ai' }
                'glm'         { return 'z-ai' }
                'minimax'     { return 'minimaxai' }
                'moonshotai'  { return 'moonshot' }
                default {
                    if (-not [string]::IsNullOrWhiteSpace($creatorRaw)) { return $creatorRaw }
                    return 'nvidia'
                }
            }
        }
        elseif ($parts.Count -eq 2) {
            $modelId = $parts[1].Trim()
            if ($modelId -ilike 'nemotron-*') { return 'nvidia' }
            if ($modelId -ilike 'llama-*')    { return 'meta' }
            return 'nvidia'
        }
        return 'nvidia'
    }

    return $fam
}

# Orchestrator (harness) identifiers. The set is OPEN: any well-formed slug names an
# orchestrator, because preferred-reviewers.<orchestrator>.json is keyed by it and new agent
# tools appear over time. The four below are the harnesses this repository can identify
# (they are used for docs and diagnostics only, never for rejection).
$script:LlmDelegateKnownOrchestrators = @('cursor', 'claude-code', 'codex', 'opencode')

function Test-LlmDelegateOrchestratorKnown {
    [CmdletBinding()]
    param(
        [string]$Orchestrator
    )
    Set-StrictMode -Version Latest
    if ([string]::IsNullOrWhiteSpace($Orchestrator)) { return $false }
    return ($script:LlmDelegateKnownOrchestrators -contains $Orchestrator.Trim().ToLowerInvariant())
}

# Trim + lowercase + validate the slug (^[a-z0-9][a-z0-9-]{0,39}$). Returns the normalized
# slug, or $null when it is blank or malformed (path separators, dots, spaces, over-length).
# It also keeps the slug safe to concatenate into a file name.
function ConvertTo-LlmDelegateOrchestratorSlug {
    [CmdletBinding()]
    param(
        [string]$Orchestrator
    )
    Set-StrictMode -Version Latest
    if ([string]::IsNullOrWhiteSpace($Orchestrator)) { return $null }
    $slug = $Orchestrator.Trim().ToLowerInvariant()
    if ($slug -cnotmatch '^[a-z0-9][a-z0-9-]{0,39}$') { return $null }
    return $slug
}
