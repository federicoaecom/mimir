#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Self-test for Set-/Resolve-LlmDelegatePreferredReviewers.ps1 (mimir-delegate skill).
# Schema 3 contract (preferred-reviewers v20): Orchestrator/Scope required, invokeArgs
# required on the primary entry, hard-veto = exit 3, schema 1/2 = preferred-schema-unsupported.

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
$setScript = Join-Path $scriptsDir 'Set-LlmDelegatePreferredReviewers.ps1'
$resolveScript = Join-Path $scriptsDir 'Resolve-LlmDelegatePreferredReviewers.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Set {
    param([hashtable]$CallArgs)
    $out = & $setScript @CallArgs 2>$null
    $code = $LASTEXITCODE
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$out)) {
        $json = $out | ConvertFrom-Json
    }
    return [pscustomobject]@{ code = $code; json = $json; raw = $out }
}

function Invoke-Resolve {
    param([hashtable]$CallArgs)
    $out = & $resolveScript @CallArgs 2>$null
    $code = $LASTEXITCODE
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$out)) {
        $json = $out | ConvertFrom-Json
    }
    return [pscustomobject]@{ code = $code; json = $json; raw = $out }
}

function Assert-ReasonExit {
    param($Result, [string]$Reason, [int]$ExitCode, [string]$Label)
    Assert-True ($Result.code -eq $ExitCode) ("{0}: expected exit {1}; got {2}." -f $Label, $ExitCode, $Result.code)
    Assert-True ($null -ne $Result.json) ("{0}: stdout should be JSON." -f $Label)
    Assert-True ([string]$Result.json.reason -eq $Reason) ("{0}: reason should be '{1}'; got '{2}'." -f $Label, $Reason, $Result.json.reason)
}

Assert-True (Test-Path -LiteralPath $setScript -PathType Leaf) "Missing script: $setScript"
Assert-True (Test-Path -LiteralPath $resolveScript -PathType Leaf) "Missing script: $resolveScript"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-llm-pref-selftest-' + [System.Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

$secretToken = 'sk-SECRET-isca-pref-789'
$secretHost = 'pref-secret-host.internal.example'

try {
    $prefPath = Join-Path $tempRoot 'preferred-reviewers.json'
    $capPath = Join-Path $tempRoot 'capabilities.json'

    # --------------------------------------------------------------------------------------
    # (A) Schema 3 CLI write with Orchestrator+Scope+OutputPath; invokeArgs; models;
    #     sanitization; hard-veto = exit 3 (not discardedVeto).
    # --------------------------------------------------------------------------------------
    $reviewersJson = @"
{
  "schemaVersion": 3,
  "reviewers": [
    {
      "backend": "opencode",
      "targetModelKey": "ollama-cloud/deepseek-v4-pro",
      "rank": 1,
      "invokeArgs": {},
      "fallbackChain": [
        {
          "backend": "opencode",
          "targetModelKey": "nvidia/deepseek-ai/deepseek-v4-pro",
          "invokeArgs": { "backend": "opencode" },
          "reason": "fallback contratado"
        }
      ]
    },
    {
      "backend": "codex",
      "targetModelKey": "openai/gpt-5.5",
      "invokeArgs": {
        "backend": "codex",
        "baseURL": "https://$secretHost/v1",
        "token": "$secretToken"
      }
    }
  ]
}
"@

    $setA = Invoke-Set @{
        ReviewersJson = $reviewersJson
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = $prefPath
    }
    Assert-True ($setA.code -eq 0) "(A) Set should exit 0; got $($setA.code)."
    Assert-True (Test-Path -LiteralPath $prefPath -PathType Leaf) '(A) preferred-reviewers.json was not written.'
    Assert-True ($setA.json.written -eq 2) "(A) Should write 2 reviewers; wrote $($setA.json.written)."
    Assert-True ($setA.json.schemaVersion -eq 3) '(A) report schemaVersion should be 3.'

    $prefText = [System.IO.File]::ReadAllText($prefPath)
    $pref = $prefText | ConvertFrom-Json
    Assert-True ($pref.schemaVersion -eq 3) '(A) document schemaVersion should be 3.'
    Assert-True ($null -eq $pref.PSObject.Properties['migratedFrom']) '(A) the document must not carry migratedFrom.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$pref.updatedAt)) '(A) updatedAt missing.'
    Assert-True ($pref.calibratedBy -eq 'cursor') ("(A) Scope machine should write calibratedBy; got '{0}'." -f $pref.calibratedBy)
    $orchA = $pref.PSObject.Properties['orchestrator']
    Assert-True ($null -eq $orchA -or [string]::IsNullOrWhiteSpace([string]$orchA.Value)) '(A) Scope machine must not write orchestrator.'
    Assert-True ($pref.fallbackPolicy.mode -eq 'ordered-chain') '(A) fallbackPolicy.mode should be ordered-chain.'

    $oc = @($pref.reviewers | Where-Object { $_.targetModelKey -eq 'ollama-cloud/deepseek-v4-pro' })[0]
    Assert-True ($null -ne $oc) '(A) opencode reviewer missing.'
    Assert-True ($oc.type -eq 'delegation-cli') '(A) CLI type should be delegation-cli.'
    Assert-True ($oc.rank -eq 1) '(A) rank=1 should be preserved.'
    Assert-True ($oc.invokeArgs.backend -eq 'opencode') '(A) invokeArgs.backend opencode missing.'
    Assert-True ($oc.invokeArgs.model -eq 'ollama-cloud/deepseek-v4-pro') "(A) opencode model should be the full key; got '$($oc.invokeArgs.model)'."
    Assert-True (@($oc.fallbackChain).Count -eq 1) '(A) fallbackChain should preserve 1 item.'

    $cx = @($pref.reviewers | Where-Object { $_.targetModelKey -eq 'openai/gpt-5.5' })[0]
    Assert-True ($null -ne $cx) '(A) codex reviewer missing.'
    Assert-True ($cx.invokeArgs.backend -eq 'codex') '(A) invokeArgs.backend codex missing.'
    Assert-True ($cx.invokeArgs.model -eq 'gpt-5.5') "(A) codex model should be the bare name; got '$($cx.invokeArgs.model)'."

    foreach ($forbidden in @($secretToken, $secretHost, 'baseURL', 'token')) {
        Assert-True (-not ($prefText -like "*$forbidden*")) "(A) preferred-reviewers.json leaked sensitive content: '$forbidden'."
    }

    $vetoJson = '{"reviewers":[{"backend":"opencode","targetModelKey":"ollama-cloud/nemotron-3-ultra","invokeArgs":{}}]}'
    $veto = Invoke-Set @{
        ReviewersJson = $vetoJson
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'veto.json')
    }
    Assert-ReasonExit -Result $veto -Reason 'hard-veto' -ExitCode 3 -Label '(A) hard-veto'

    # --------------------------------------------------------------------------------------
    # (B) Resolve with -Orchestrator -PreferredPath -CapabilitiesPath
    # --------------------------------------------------------------------------------------
    @'
{
  "schemaVersion": 1,
  "generatedAt": "2026-06-17T00:00:00Z",
  "backends": [
    { "backend": "opencode", "installed": true, "enumeration": "config", "models": [
      { "canonicalModel": "nvidia/deepseek-ai/deepseek-v4-pro", "locality": "external", "sourceKind": "configured", "sourceConfidence": "strong" }
    ] },
    { "backend": "codex", "installed": true, "enumeration": "config", "models": [
      { "canonicalModel": "openai/gpt-5.5", "locality": "external", "reasonCode": "external", "sourceKind": "configured", "sourceConfidence": "strong" }
    ] }
  ],
  "lastHealthCheck": null
}
'@ | Set-Content -LiteralPath $capPath -Encoding utf8

    $resB = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $prefPath
        CapabilitiesPath = $capPath
    }
    Assert-True ($resB.code -eq 0) "(B) Resolve should exit 0; got $($resB.code)."
    Assert-True ($resB.json.hasPreferences -eq $true) '(B) hasPreferences should be true.'
    Assert-True ($resB.json.schemaVersion -eq 3) '(B) schemaVersion should be 3.'
    Assert-True ($resB.json.preferenceSource -eq 'explicit-path') "(B) preferenceSource should be explicit-path; got '$($resB.json.preferenceSource)'."
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$resB.json.note)) '(B) note (preference != authorization) missing.'
    Assert-True ($null -eq $resB.json.PSObject.Properties['migratedFrom']) '(B) Resolve output must not carry migratedFrom.'

    # A persisted fallbackPolicy that activates on noResponse is outside the contract.
    $noResponsePolicy = '"fallbackPolicy":{"mode":"ordered-chain","defaultActivateOn":["quota","timeout","error","unavailable","noResponse"],"gateAskBehavior":"ask-human","gateDenyBehavior":"stop-or-suggest-manual-alternative"}'
    $noResponsePath = Join-Path $tempRoot 'preferred-noresponse.json'
    ('{"schemaVersion":3,' + $noResponsePolicy + ',"reviewers":[{"type":"delegation-cli","backend":"codex","targetModelKey":"openai/gpt-5.5","rank":1,"invokeArgs":{"backend":"codex","model":"gpt-5.5"}}]}') |
        Set-Content -LiteralPath $noResponsePath -Encoding utf8
    $resNoResponse = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $noResponsePath
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $resNoResponse -Reason 'fallback-policy-invalid' -ExitCode 3 -Label '(B) Resolve noResponse activation'
    $setNoResponse = Invoke-Set @{
        ReviewersJson = ('{' + $noResponsePolicy + ',"reviewers":[{"backend":"codex","targetModelKey":"openai/gpt-5.5","invokeArgs":{}}]}')
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        Preview       = $true
    }
    Assert-ReasonExit -Result $setNoResponse -Reason 'fallback-policy-invalid' -ExitCode 3 -Label '(B) Set noResponse activation'

    $rcx = @($resB.json.reviewers | Where-Object { $_.targetModelKey -eq 'openai/gpt-5.5' })[0]
    Assert-True ($rcx.availableInManifest -eq $true) '(B) codex should be availableInManifest=true.'
    Assert-True ($rcx.type -eq 'delegation-cli') '(B) type should echo delegation-cli.'
    Assert-True ($rcx.reasoningEffort -eq 'unset') '(B) default reasoningEffort should be unset.'
    Assert-True ($null -eq $rcx.harnessModelId -or [string]::IsNullOrWhiteSpace([string]$rcx.harnessModelId)) '(B) CLI must not have harnessModelId.'

    $roc = @($resB.json.reviewers | Where-Object { $_.targetModelKey -eq 'ollama-cloud/deepseek-v4-pro' })[0]
    Assert-True ($roc.availableInManifest -eq $false) '(B) primary opencode missing from manifest.'
    Assert-True (@($roc.fallbackChain).Count -eq 1) '(B) resolved fallbackChain missing.'
    Assert-True ($roc.fallbackChain[0].availableInManifest -eq $true) '(B) nvidia fallback should be in the manifest.'
    Assert-True ($roc.fallbackChain[0].fallbackIndex -eq 0) '(B) fallbackIndex should be 0.'

    # --------------------------------------------------------------------------------------
    # (E) PreferredPath pointing at a missing file
    # --------------------------------------------------------------------------------------
    $resE = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = (Join-Path $tempRoot 'does-not-exist.json')
        CapabilitiesPath = $capPath
    }
    Assert-True ($resE.code -eq 0) '(E) missing file should exit 0.'
    Assert-True ($resE.json.hasPreferences -eq $false) '(E) hasPreferences=false expected.'
    Assert-True ($resE.json.reason -eq 'no-preferred-file') "(E) reason=no-preferred-file; got '$($resE.json.reason)'."
    Assert-True ($resE.json.preferenceSource -eq 'explicit-path') '(E) preferenceSource=explicit-path expected.'

    # --------------------------------------------------------------------------------------
    # (F) schema v1 -> exit 2 preferred-schema-unsupported (does NOT resolve as v1)
    # --------------------------------------------------------------------------------------
    $legacyPath = Join-Path $tempRoot 'preferred-v1.json'
    @'
{
  "updatedAt": "2026-06-17T00:00:00Z",
  "reviewers": [
    { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": { "model": "gpt-5.5" } }
  ]
}
'@ | Set-Content -LiteralPath $legacyPath -Encoding utf8
    $resF = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $legacyPath
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $resF -Reason 'preferred-schema-unsupported' -ExitCode 2 -Label '(F) schema v1'

    $legacyV2Path = Join-Path $tempRoot 'preferred-v2.json'
    @'
{
  "schemaVersion": 2,
  "reviewers": [
    { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": { "backend": "codex", "model": "gpt-5.5" } }
  ]
}
'@ | Set-Content -LiteralPath $legacyV2Path -Encoding utf8
    $resF2 = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $legacyV2Path
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $resF2 -Reason 'preferred-schema-unsupported' -ExitCode 2 -Label '(F) schema v2'

    # --------------------------------------------------------------------------------------
    # (G) invokeArgs.backend diverges
    # --------------------------------------------------------------------------------------
    $badPrimary = '{"reviewers":[{ "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": { "backend": "opencode", "model": "gpt-5.5" } }]}'
    $g = Invoke-Set @{
        ReviewersJson = $badPrimary
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'bad-primary.json')
    }
    Assert-ReasonExit -Result $g -Reason 'invoke-args-backend-divergent' -ExitCode 3 -Label '(G) primary'

    $badFallback = @'
{
  "reviewers": [
    {
      "backend": "opencode",
      "targetModelKey": "ollama-cloud/deepseek-v4-pro",
      "invokeArgs": { "backend": "opencode" },
      "fallbackChain": [
        { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": { "backend": "opencode", "model": "gpt-5.5" } }
      ]
    }
  ]
}
'@
    $g2 = Invoke-Set @{
        ReviewersJson = $badFallback
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'bad-fallback.json')
    }
    Assert-ReasonExit -Result $g2 -Reason 'invoke-args-backend-divergent' -ExitCode 3 -Label '(G) fallback'

    # --------------------------------------------------------------------------------------
    # (H) cycle in fallbackChain
    # --------------------------------------------------------------------------------------
    $cycleFallback = @'
{
  "reviewers": [
    {
      "backend": "opencode",
      "targetModelKey": "ollama-cloud/deepseek-v4-pro",
      "invokeArgs": {},
      "fallbackChain": [
        { "backend": "opencode", "targetModelKey": "ollama-cloud/deepseek-v4-pro", "invokeArgs": {} }
      ]
    }
  ]
}
'@
    $h = Invoke-Set @{
        ReviewersJson = $cycleFallback
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'cycle.json')
    }
    Assert-ReasonExit -Result $h -Reason 'fallback-cycle' -ExitCode 3 -Label '(H) cycle'

    # --------------------------------------------------------------------------------------
    # (I) ranks, implicit rank, overwrite-required, -Overwrite
    # --------------------------------------------------------------------------------------
    $outOfOrder = @'
[
  { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "rank": 20, "invokeArgs": {} },
  { "backend": "opencode", "targetModelKey": "ollama-cloud/deepseek-v4-pro", "rank": 10, "invokeArgs": {} }
]
'@
    $rankPath = Join-Path $tempRoot 'ranked.json'
    $rankSet = Invoke-Set @{
        ReviewersJson = $outOfOrder
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = $rankPath
    }
    Assert-True ($rankSet.code -eq 0) "(I) Set ranked should exit 0; got $($rankSet.code)."
    $ranked = Get-Content -LiteralPath $rankPath -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($ranked.reviewers[0].rank -eq 10) "(I) rank 10 entry should come first; got $($ranked.reviewers[0].rank)."
    $rankedResolved = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $rankPath
        CapabilitiesPath = $capPath
    }
    Assert-True ($rankedResolved.code -eq 0) '(I) Resolve ranked should exit 0.'
    Assert-True ($rankedResolved.json.reviewers[0].rank -eq 10) '(I) Resolve should preserve rank ordering.'

    $mixedImplicitRank = @'
[
  { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "rank": 2, "invokeArgs": {} },
  { "backend": "opencode", "targetModelKey": "ollama-cloud/deepseek-v4-pro", "invokeArgs": {} }
]
'@
    $mixedRankPath = Join-Path $tempRoot 'mixed-implicit-rank.json'
    $mixedSet = Invoke-Set @{
        ReviewersJson = $mixedImplicitRank
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = $mixedRankPath
    }
    Assert-True ($mixedSet.code -eq 0) '(I) Set mixed-rank should exit 0.'
    $mixedRanked = Get-Content -LiteralPath $mixedRankPath -Raw -Encoding utf8 | ConvertFrom-Json
    $implicitReviewer = @($mixedRanked.reviewers | Where-Object { $_.targetModelKey -eq 'ollama-cloud/deepseek-v4-pro' })[0]
    Assert-True ($implicitReviewer.rank -eq 3) "(I) implicit rank should avoid colliding with 2; got $($implicitReviewer.rank)."

    $ow = Invoke-Set @{
        ReviewersJson = $outOfOrder
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = $rankPath
    }
    Assert-ReasonExit -Result $ow -Reason 'overwrite-required' -ExitCode 1 -Label '(I) without Overwrite'

    $owOk = Invoke-Set @{
        ReviewersJson = $outOfOrder
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = $rankPath
        Overwrite     = $true
    }
    Assert-True ($owOk.code -eq 0) "(I) with -Overwrite should exit 0; got $($owOk.code)."

    $badRank = '{"reviewers":[{ "backend": "codex", "targetModelKey": "openai/gpt-5.5", "rank": 0, "invokeArgs": {} }]}'
    $br = Invoke-Set @{
        ReviewersJson = $badRank
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'bad-rank.json')
    }
    Assert-ReasonExit -Result $br -Reason 'rank-invalid' -ExitCode 3 -Label '(I) rank 0'

    $dupRank = @'
[
  { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "rank": 1, "invokeArgs": {} },
  { "backend": "opencode", "targetModelKey": "ollama-cloud/deepseek-v4-pro", "rank": 1, "invokeArgs": {} }
]
'@
    $dr = Invoke-Set @{
        ReviewersJson = $dupRank
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'dup-rank.json')
    }
    Assert-ReasonExit -Result $dr -Reason 'rank-duplicate' -ExitCode 3 -Label '(I) duplicate rank'

    # --------------------------------------------------------------------------------------
    # (J) required parameters exit 1 + JSON
    # --------------------------------------------------------------------------------------
    $j1 = Invoke-Set @{ ReviewersJson = '[]'; Scope = 'machine'; OutputPath = (Join-Path $tempRoot 'j1.json') }
    Assert-ReasonExit -Result $j1 -Reason 'orchestrator-required' -ExitCode 1 -Label '(J) orchestrator-required'

    foreach ($badSlug in @('Bad Slug!', '../x', ('a' * 41), '-lead', 'with_underscore')) {
        $j2 = Invoke-Set @{
            ReviewersJson = '[]'
            Orchestrator  = $badSlug
            Scope         = 'machine'
            OutputPath    = (Join-Path $tempRoot 'j2.json')
        }
        Assert-ReasonExit -Result $j2 -Reason 'orchestrator-invalid' -ExitCode 1 -Label "(J) Set orchestrator-invalid '$badSlug'"
        $j2r = Invoke-Resolve @{ Orchestrator = $badSlug; PreferredRoot = $tempRoot; CapabilitiesPath = $capPath }
        Assert-ReasonExit -Result $j2r -Reason 'orchestrator-invalid' -ExitCode 1 -Label "(J) Resolve orchestrator-invalid '$badSlug'"
    }

    # (J2) open allow-list: any valid slug is accepted, normalized to lowercase, and
    # round-trips through Set and Resolve without touching other harnesses' files.
    $openRoot = Join-Path $tempRoot 'open-orch'
    [System.IO.Directory]::CreateDirectory($openRoot) | Out-Null
    $openNative = @'
{
  "reviewers": [
    {
      "backend": "orchestrator-native",
      "targetModelKey": "moonshot/kimi-k3-max",
      "harnessModelId": "kimi-k3-max",
      "invokeArgs": {}
    },
    {
      "backend": "codex",
      "targetModelKey": "openai/gpt-5.5",
      "invokeArgs": {}
    }
  ]
}
'@
    $jOpenSet = Invoke-Set @{
        ReviewersJson = $openNative
        Orchestrator  = 'Gemini'
        Scope         = 'orchestrator'
        PreferredRoot = $openRoot
    }
    Assert-True ($jOpenSet.code -eq 0) "(J2) Set with unknown valid slug should exit 0; got $($jOpenSet.code)."
    Assert-True ([string]$jOpenSet.json.orchestrator -eq 'gemini') "(J2) Set should normalize the slug to lowercase; got '$($jOpenSet.json.orchestrator)'."
    $openFiles = @(Get-ChildItem -LiteralPath $openRoot -File | ForEach-Object { $_.Name })
    Assert-True ($openFiles -ccontains 'preferred-reviewers.gemini.json') "(J2) expected lowercase file name; got '$($openFiles -join ',')'."

    $jOpenRes = Invoke-Resolve @{ Orchestrator = 'GEMINI'; PreferredRoot = $openRoot; CapabilitiesPath = $capPath }
    Assert-True ($jOpenRes.code -eq 0) "(J2) Resolve with unknown valid slug should exit 0; got $($jOpenRes.code)."
    Assert-True ([string]$jOpenRes.json.preferenceSource -eq 'orchestrator') "(J2) preferenceSource should be orchestrator; got '$($jOpenRes.json.preferenceSource)'."
    $openNativeRes = @($jOpenRes.json.reviewers | Where-Object { $_.backend -eq 'orchestrator-native' })[0]
    $openCliRes = @($jOpenRes.json.reviewers | Where-Object { $_.backend -eq 'codex' })[0]
    Assert-True (@(@($openNativeRes.diagnostics) | Where-Object { $_ -like '*not a known harness*' -and $_ -like '*do not count*' }).Count -eq 1) "(J2) native under unknown slug should carry the unverifiable diagnostic; got '$(@($openNativeRes.diagnostics) -join ' | ')'."
    Assert-True (@(@($openCliRes.diagnostics) | Where-Object { $_ -like '*not a known harness*' }).Count -eq 0) '(J2) CLI reviewer must not carry the native-unverifiable diagnostic.'

    # Known harness keeps no such diagnostic.
    $knownRoot = Join-Path $tempRoot 'known-orch'
    [System.IO.Directory]::CreateDirectory($knownRoot) | Out-Null
    $jKnownSet = Invoke-Set @{ ReviewersJson = $openNative; Orchestrator = 'codex'; Scope = 'orchestrator'; PreferredRoot = $knownRoot }
    Assert-True ($jKnownSet.code -eq 0) "(J2) Set under known harness should exit 0; got $($jKnownSet.code)."
    $jKnownRes = Invoke-Resolve @{ Orchestrator = 'codex'; PreferredRoot = $knownRoot; CapabilitiesPath = $capPath }
    $knownNativeRes = @($jKnownRes.json.reviewers | Where-Object { $_.backend -eq 'orchestrator-native' })[0]
    Assert-True (@(@($knownNativeRes.diagnostics) | Where-Object { $_ -like '*not a known harness*' }).Count -eq 0) '(J2) known harness must not carry the unknown-harness diagnostic.'

    # A cursor/* native under a non-cursor slug stays refused, known or not.
    $jGrok = '{"reviewers":[{ "backend": "orchestrator-native", "targetModelKey": "cursor/grok-4", "harnessModelId": "grok-4", "invokeArgs": {} }]}'
    $jCursorUnknown = Invoke-Set @{
        ReviewersJson = $jGrok
        Orchestrator  = 'gemini'
        Scope         = 'orchestrator'
        OutputPath    = (Join-Path $tempRoot 'cursor-under-gemini.json')
    }
    Assert-ReasonExit -Result $jCursorUnknown -Reason 'native-harness-orchestrator-mismatch' -ExitCode 3 -Label '(J2) cursor native under unknown slug'


    $j3 = Invoke-Set @{ ReviewersJson = '[]'; Orchestrator = 'cursor'; OutputPath = (Join-Path $tempRoot 'j3.json') }
    Assert-ReasonExit -Result $j3 -Reason 'scope-required' -ExitCode 1 -Label '(J) scope-required'

    $j4 = Invoke-Set @{ Orchestrator = 'cursor'; Scope = 'machine'; OutputPath = (Join-Path $tempRoot 'j4.json') }
    Assert-ReasonExit -Result $j4 -Reason 'reviewers-json-required' -ExitCode 1 -Label '(J) reviewers-json-required'

    $jR = Invoke-Resolve @{ PreferredPath = $prefPath; CapabilitiesPath = $capPath }
    Assert-ReasonExit -Result $jR -Reason 'orchestrator-required' -ExitCode 1 -Label '(J) Resolve orchestrator-required'

    # --------------------------------------------------------------------------------------
    # (K) native: harnessModelId + invokeArgs {}; fallbackChain forbidden; cursor/* forbidden
    # --------------------------------------------------------------------------------------
    $nativeOk = @'
{
  "reviewers": [
    {
      "backend": "orchestrator-native",
      "targetModelKey": "moonshot/kimi-k3-max",
      "harnessModelId": "kimi-k3-max",
      "invokeArgs": {}
    }
  ]
}
'@
    $nativePath = Join-Path $tempRoot 'native.json'
    $kOk = Invoke-Set @{
        ReviewersJson = $nativeOk
        Orchestrator  = 'cursor'
        Scope         = 'orchestrator'
        OutputPath    = $nativePath
    }
    Assert-True ($kOk.code -eq 0) "(K) valid native should exit 0; got $($kOk.code)."
    $nativeDoc = Get-Content -LiteralPath $nativePath -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($nativeDoc.reviewers[0].type -eq 'orchestrator-native-subagent') '(K) native type expected.'
    Assert-True ($nativeDoc.reviewers[0].harnessModelId -eq 'kimi-k3-max') '(K) harnessModelId should be preserved.'

    $nativeFb = @'
{
  "reviewers": [
    {
      "backend": "orchestrator-native",
      "targetModelKey": "moonshot/kimi-k3-max",
      "harnessModelId": "kimi-k3-max",
      "invokeArgs": {},
      "fallbackChain": [
        { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": {} }
      ]
    }
  ]
}
'@
    $kFb = Invoke-Set @{
        ReviewersJson = $nativeFb
        Orchestrator  = 'cursor'
        Scope         = 'orchestrator'
        OutputPath    = (Join-Path $tempRoot 'native-fb.json')
    }
    Assert-ReasonExit -Result $kFb -Reason 'native-fallback-chain-forbidden' -ExitCode 3 -Label '(K) native fallback'

    $cursorPref = '{"reviewers":[{ "backend": "opencode", "targetModelKey": "cursor/composer", "invokeArgs": {} }]}'
    $kCur = Invoke-Set @{
        ReviewersJson = $cursorPref
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'cursor-pref.json')
    }
    Assert-ReasonExit -Result $kCur -Reason 'native-cursor-prefix' -ExitCode 3 -Label '(K) cursor prefix'

    # (K2) Cursor harness key: legitimate as a NATIVE primary entry with a known Creator,
    # forbidden as a CLI target (undispatchable) in both spellings and as a fallbackChain link.
    $nativeGrok = @'
{
  "reviewers": [
    {
      "backend": "orchestrator-native",
      "targetModelKey": "cursor/grok-4",
      "harnessModelId": "grok-4",
      "invokeArgs": {}
    }
  ]
}
'@
    $grokPath = Join-Path $tempRoot 'native-grok.json'
    $kGrok = Invoke-Set @{
        ReviewersJson = $nativeGrok
        Orchestrator  = 'cursor'
        Scope         = 'orchestrator'
        OutputPath    = $grokPath
    }
    Assert-True ($kGrok.code -eq 0) "(K2) native cursor/grok-* should exit 0; got $($kGrok.code)."
    $grokDoc = Get-Content -LiteralPath $grokPath -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($grokDoc.reviewers[0].targetModelKey -eq 'cursor/grok-4') '(K2) native targetModelKey should be preserved.'

    $nativeComposer = @'
{
  "reviewers": [
    {
      "backend": "orchestrator-native",
      "targetModelKey": "cursor-composer-2-medium",
      "harnessModelId": "composer-2-medium",
      "invokeArgs": {}
    }
  ]
}
'@
    $kComposer = Invoke-Set @{
        ReviewersJson = $nativeComposer
        Orchestrator  = 'cursor'
        Scope         = 'orchestrator'
        OutputPath    = (Join-Path $tempRoot 'native-composer.json')
    }
    Assert-True ($kComposer.code -eq 0) "(K2) native cursor-composer-* should exit 0; got $($kComposer.code)."

    $nativeUnmapped = @'
{
  "reviewers": [
    {
      "backend": "orchestrator-native",
      "targetModelKey": "cursor/unmapped-model",
      "harnessModelId": "unmapped-model",
      "invokeArgs": {}
    }
  ]
}
'@
    $kUnmapped = Invoke-Set @{
        ReviewersJson = $nativeUnmapped
        Orchestrator  = 'cursor'
        Scope         = 'orchestrator'
        OutputPath    = (Join-Path $tempRoot 'native-unmapped.json')
    }
    Assert-ReasonExit -Result $kUnmapped -Reason 'native-cursor-prefix' -ExitCode 3 -Label '(K2) native without a known Creator'

    $cliGrokSlug = '{"reviewers":[{ "backend": "opencode", "targetModelKey": "cursor-grok-4.6-medium", "invokeArgs": {} }]}'
    $kCliSlug = Invoke-Set @{
        ReviewersJson = $cliGrokSlug
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'cli-grok-slug.json')
    }
    Assert-ReasonExit -Result $kCliSlug -Reason 'native-cursor-prefix' -ExitCode 3 -Label '(K2) CLI slug without a slash'

    $cliGrokSlash = '{"reviewers":[{ "backend": "codex", "targetModelKey": "cursor/grok-4", "invokeArgs": {} }]}'
    $kCliSlash = Invoke-Set @{
        ReviewersJson = $cliGrokSlash
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'cli-grok-slash.json')
    }
    Assert-ReasonExit -Result $kCliSlash -Reason 'native-cursor-prefix' -ExitCode 3 -Label '(K2) CLI spelling with a slash'

    $fbCursor = @'
{
  "reviewers": [
    {
      "backend": "codex",
      "targetModelKey": "openai/gpt-5.5",
      "invokeArgs": {},
      "fallbackChain": [
        { "backend": "opencode", "targetModelKey": "cursor/grok-4", "invokeArgs": {} }
      ]
    }
  ]
}
'@
    $kFbCursor = Invoke-Set @{
        ReviewersJson = $fbCursor
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'fb-cursor.json')
    }
    Assert-ReasonExit -Result $kFbCursor -Reason 'native-cursor-prefix' -ExitCode 3 -Label '(K2) fallback cursor'

    # (K3) reader with the SAME contract as the writer: a hand-edited schema 3 file with a
    # Cursor harness key under a CLI backend (or as a chain link) is rejected on read; native passes.
    $readerCliPath = Join-Path $tempRoot 'reader-cursor-cli.json'
    @'
{
  "schemaVersion": 3,
  "reviewers": [
    {
      "type": "delegation-cli",
      "backend": "opencode",
      "targetModelKey": "cursor/grok-4",
      "rank": 1,
      "invokeArgs": { "backend": "opencode", "model": "cursor/grok-4" }
    }
  ]
}
'@ | Set-Content -LiteralPath $readerCliPath -Encoding utf8
    $kRead1 = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $readerCliPath
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $kRead1 -Reason 'native-cursor-prefix' -ExitCode 3 -Label '(K3) CLI cursor reader'

    $readerFbPath = Join-Path $tempRoot 'reader-cursor-fallback.json'
    @'
{
  "schemaVersion": 3,
  "reviewers": [
    {
      "type": "delegation-cli",
      "backend": "codex",
      "targetModelKey": "openai/gpt-5.5",
      "rank": 1,
      "invokeArgs": { "backend": "codex", "model": "gpt-5.5" },
      "fallbackChain": [
        {
          "backend": "opencode",
          "targetModelKey": "cursor-grok-4.6-medium",
          "invokeArgs": { "backend": "opencode", "model": "cursor-grok-4.6-medium" }
        }
      ]
    }
  ]
}
'@ | Set-Content -LiteralPath $readerFbPath -Encoding utf8
    $kRead2 = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $readerFbPath
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $kRead2 -Reason 'native-cursor-prefix' -ExitCode 3 -Label '(K3) fallback cursor reader'

    $readerNativePath = Join-Path $tempRoot 'reader-cursor-native.json'
    @'
{
  "schemaVersion": 3,
  "reviewers": [
    {
      "type": "orchestrator-native-subagent",
      "backend": "orchestrator-native",
      "targetModelKey": "cursor/grok-4",
      "harnessModelId": "grok-4",
      "rank": 1,
      "invokeArgs": {}
    }
  ]
}
'@ | Set-Content -LiteralPath $readerNativePath -Encoding utf8
    $kRead3 = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredPath    = $readerNativePath
        CapabilitiesPath = $capPath
    }
    Assert-True ($kRead3.code -eq 0) "(K3) native cursor/grok-* reader should exit 0; got $($kRead3.code)."
    Assert-True ([string]$kRead3.json.reviewers[0].family -eq 'xai') "(K3) native family should be xai; got '$($kRead3.json.reviewers[0].family)'."

    # (K4) a native entry belongs to its harness: writing it in -Scope machine is forbidden,
    # because another orchestrator would resolve the entry as if it were its own native one
    # (a phantom voice on the shared floor).
    $kNativeMachine = Invoke-Set @{
        ReviewersJson = $nativeGrok
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'native-machine.json')
    }
    Assert-ReasonExit -Result $kNativeMachine -Reason 'native-machine-scope-forbidden' -ExitCode 3 -Label '(K4) native in machine scope'

    # A hand-edited machine file with a native entry is refused on read too (same contract as the writer).
    $machineNativeRoot = Join-Path $tempRoot 'machine-native'
    [System.IO.Directory]::CreateDirectory($machineNativeRoot) | Out-Null
    @'
{
  "schemaVersion": 3,
  "reviewers": [
    {
      "type": "orchestrator-native-subagent",
      "backend": "orchestrator-native",
      "targetModelKey": "cursor/grok-4",
      "harnessModelId": "grok-4",
      "rank": 1,
      "invokeArgs": {}
    }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $machineNativeRoot 'preferred-reviewers.json') -Encoding utf8
    $kRead4 = Invoke-Resolve @{
        Orchestrator     = 'claude-code'
        PreferredRoot    = $machineNativeRoot
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $kRead4 -Reason 'native-machine-scope-forbidden' -ExitCode 3 -Label '(K4) Resolve native in machine file'

    # The same primary entry in orchestrator scope is accepted.
    $orchRoot = Join-Path $tempRoot 'orch-native'
    [System.IO.Directory]::CreateDirectory($orchRoot) | Out-Null
    @'
{
  "schemaVersion": 3,
  "orchestrator": "cursor",
  "reviewers": [
    {
      "type": "orchestrator-native-subagent",
      "backend": "orchestrator-native",
      "targetModelKey": "cursor/grok-4",
      "harnessModelId": "grok-4",
      "rank": 1,
      "invokeArgs": {}
    }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $orchRoot 'preferred-reviewers.cursor.json') -Encoding utf8
    $kRead5 = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredRoot    = $orchRoot
        CapabilitiesPath = $capPath
    }
    Assert-True ($kRead5.code -eq 0) "(K4) reading in orchestrator scope should exit 0; got $($kRead5.code)."

    # (K5) orchestrator scope is not enough: a key identifying ANOTHER harness is rejected.
    # Partial enforcement — only applies to a key that carries the harness (cursor/*, cursor-*).
    $kMismatch = Invoke-Set @{
        ReviewersJson = $nativeGrok
        Orchestrator  = 'claude-code'
        Scope         = 'orchestrator'
        OutputPath    = (Join-Path $tempRoot 'native-mismatch.json')
    }
    Assert-ReasonExit -Result $kMismatch -Reason 'native-harness-orchestrator-mismatch' -ExitCode 3 -Label '(K5) native cursor under claude-code'

    # A neutral key (no harness in the key) is still accepted under any orchestrator: the
    # engine has no way to know which harness it came from, and this is a declared
    # limitation, not a bug.
    $kNeutral = Invoke-Set @{
        ReviewersJson = $nativeOk
        Orchestrator  = 'claude-code'
        Scope         = 'orchestrator'
        OutputPath    = (Join-Path $tempRoot 'native-neutral.json')
    }
    Assert-True ($kNeutral.code -eq 0) "(K5) neutral key should exit 0 under another orchestrator; got $($kNeutral.code)."

    # A hand-edited file with a native key from another harness is refused on read too.
    $mismatchRoot = Join-Path $tempRoot 'native-mismatch-file'
    [System.IO.Directory]::CreateDirectory($mismatchRoot) | Out-Null
    @'
{
  "schemaVersion": 3,
  "orchestrator": "claude-code",
  "reviewers": [
    {
      "type": "orchestrator-native-subagent",
      "backend": "orchestrator-native",
      "targetModelKey": "cursor/grok-4",
      "harnessModelId": "grok-4",
      "rank": 1,
      "invokeArgs": {}
    }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $mismatchRoot 'preferred-reviewers.claude-code.json') -Encoding utf8
    $kRead6 = Invoke-Resolve @{
        Orchestrator     = 'claude-code'
        PreferredRoot    = $mismatchRoot
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $kRead6 -Reason 'native-harness-orchestrator-mismatch' -ExitCode 3 -Label '(K5) Resolve native key from another harness'

    # --------------------------------------------------------------------------------------
    # (L) empty PreferredRoot cascade -> no-preferred-file preferenceSource=none
    # --------------------------------------------------------------------------------------
    $cascadeRoot = Join-Path $tempRoot 'cascade-empty'
    [System.IO.Directory]::CreateDirectory($cascadeRoot) | Out-Null
    $resL = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredRoot    = $cascadeRoot
        CapabilitiesPath = $capPath
    }
    Assert-True ($resL.code -eq 0) '(L) empty cascade should exit 0.'
    Assert-True ($resL.json.hasPreferences -eq $false) '(L) hasPreferences=false.'
    Assert-True ($resL.json.reason -eq 'no-preferred-file') '(L) reason=no-preferred-file.'
    Assert-True ($resL.json.preferenceSource -eq 'none') "(L) preferenceSource=none; got '$($resL.json.preferenceSource)'."

    # --------------------------------------------------------------------------------------
    # (M) Resolve envelope passed as ReviewersJson -> unknown-property
    # --------------------------------------------------------------------------------------
    $wrapperEnvelope = @{
        hasPreferences = $true
        reason         = $null
        reviewers      = @(
            @{ backend = 'codex'; targetModelKey = 'openai/gpt-5.5'; invokeArgs = @{} }
        )
        note           = 'echo of Resolve'
    } | ConvertTo-Json -Depth 6 -Compress
    $m = Invoke-Set @{
        ReviewersJson = $wrapperEnvelope
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'wrapper-envelope.json')
    }
    Assert-ReasonExit -Result $m -Reason 'unknown-property' -ExitCode 3 -Label '(M) Resolve wrapper'

    # --------------------------------------------------------------------------------------
    # (N) a primary reviewer "model" property is not an alias of targetModelKey
    # --------------------------------------------------------------------------------------
    $nJson = '{"reviewers":[{ "backend": "codex", "model": "openai/gpt-5.5", "invokeArgs": {} }]}'
    $n = Invoke-Set @{
        ReviewersJson = $nJson
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'model-divergent.json')
    }
    Assert-ReasonExit -Result $n -Reason 'unknown-property' -ExitCode 3 -Label '(N) primary reviewer model property'

    # --------------------------------------------------------------------------------------
    # (O) type inconsistent with backend
    # --------------------------------------------------------------------------------------
    $oJson = '{"reviewers":[{ "type": "orchestrator-native-subagent", "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": {} }]}'
    $o = Invoke-Set @{
        ReviewersJson = $oJson
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'type-divergent.json')
    }
    Assert-ReasonExit -Result $o -Reason 'type-backend-divergent' -ExitCode 3 -Label '(O) type'

    # --------------------------------------------------------------------------------------
    # (P) incomplete, missing invokeArgs
    # --------------------------------------------------------------------------------------
    $pJson = '{"reviewers":[{ "backend": "codex", "targetModelKey": "openai/gpt-5.5" }]}'
    $p = Invoke-Set @{
        ReviewersJson = $pJson
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'incomplete.json')
    }
    Assert-ReasonExit -Result $p -Reason 'reviewer-incomplete' -ExitCode 3 -Label '(P) missing invokeArgs'

    # --------------------------------------------------------------------------------------
    # (Q) claude-code / antigravity without model in invokeArgs -> last segment
    # --------------------------------------------------------------------------------------
    $qJson = @'
[
  { "backend": "claude-code", "targetModelKey": "anthropic/claude-opus-4-8", "invokeArgs": {} },
  { "backend": "antigravity", "targetModelKey": "google/gemini-3-flash-preview", "invokeArgs": { "backend": "antigravity" } }
]
'@
    $qPath = Join-Path $tempRoot 'last-segment.json'
    $q = Invoke-Set @{
        ReviewersJson = $qJson
        Orchestrator  = 'claude-code'
        Scope         = 'machine'
        OutputPath    = $qPath
    }
    Assert-True ($q.code -eq 0) "(Q) Set claude/antigravity should exit 0; got $($q.code)."
    $qDoc = Get-Content -LiteralPath $qPath -Raw -Encoding utf8 | ConvertFrom-Json
    $qClaude = @($qDoc.reviewers | Where-Object { $_.backend -eq 'claude-code' })[0]
    $qAgy = @($qDoc.reviewers | Where-Object { $_.backend -eq 'antigravity' })[0]
    Assert-True ($qClaude.invokeArgs.model -eq 'claude-opus-4-8') "(Q) claude-code model should be the last segment; got '$($qClaude.invokeArgs.model)'."
    Assert-True ($qAgy.invokeArgs.model -eq 'gemini-3-flash-preview') "(Q) antigravity model should be the last segment; got '$($qAgy.invokeArgs.model)'."

    # --------------------------------------------------------------------------------------
    # (R) Scope orchestrator writes orchestrator; Scope machine writes calibratedBy
    # --------------------------------------------------------------------------------------
    $rOrchPath = Join-Path $tempRoot 'scope-orch.json'
    $rOrch = Invoke-Set @{
        ReviewersJson = '{"reviewers":[{ "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": {} }]}'
        Orchestrator  = 'opencode'
        Scope         = 'orchestrator'
        OutputPath    = $rOrchPath
    }
    Assert-True ($rOrch.code -eq 0) '(R) Scope orchestrator should exit 0.'
    $rOrchDoc = Get-Content -LiteralPath $rOrchPath -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($rOrchDoc.orchestrator -eq 'opencode') ("(R) orchestrator field expected; got '{0}'." -f $rOrchDoc.orchestrator)
    $calR = $rOrchDoc.PSObject.Properties['calibratedBy']
    Assert-True ($null -eq $calR -or [string]::IsNullOrWhiteSpace([string]$calR.Value)) '(R) Scope orchestrator must not write calibratedBy.'

    $rMachPath = Join-Path $tempRoot 'scope-machine.json'
    $rMach = Invoke-Set @{
        ReviewersJson = '{"reviewers":[{ "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": {} }]}'
        Orchestrator  = 'codex'
        Scope         = 'machine'
        OutputPath    = $rMachPath
    }
    Assert-True ($rMach.code -eq 0) '(R) Scope machine should exit 0.'
    $rMachDoc = Get-Content -LiteralPath $rMachPath -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($rMachDoc.calibratedBy -eq 'codex') "(R) calibratedBy expected; got '$($rMachDoc.calibratedBy)'."

    # --------------------------------------------------------------------------------------
    # (S) PreferredPath+PreferredRoot / OutputPath+PreferredRoot conflict
    # --------------------------------------------------------------------------------------
    $s1 = Invoke-Set @{
        ReviewersJson = '[]'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 's1.json')
        PreferredRoot = $tempRoot
    }
    Assert-ReasonExit -Result $s1 -Reason 'preferred-path-mode-conflict' -ExitCode 1 -Label '(S) Set OutputPath+PreferredRoot'

    $s2 = Invoke-Resolve @{
        Orchestrator  = 'cursor'
        PreferredPath = $prefPath
        PreferredRoot = $tempRoot
        CapabilitiesPath = $capPath
    }
    Assert-ReasonExit -Result $s2 -Reason 'preferred-path-mode-conflict' -ExitCode 1 -Label '(S) Resolve PreferredPath+PreferredRoot'

    # --------------------------------------------------------------------------------------
    # (T) Preview: schema 3 and a bare array are accepted without migratedFrom; another schemaVersion is refused
    # --------------------------------------------------------------------------------------
    $t3 = Invoke-Set @{
        ReviewersJson = '{"schemaVersion":3,"reviewers":[{"backend":"codex","targetModelKey":"openai/gpt-5.5","invokeArgs":{}}]}'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        Preview       = $true
    }
    Assert-True ($t3.code -eq 0) '(T) Preview schema3 should exit 0.'
    Assert-True ($t3.json.preview -eq $true) '(T) preview=true expected.'
    Assert-True ($null -eq $t3.json.document.PSObject.Properties['migratedFrom']) '(T) schema3 Preview must not carry migratedFrom.'

    $tBare = Invoke-Set @{
        ReviewersJson = '[{"backend":"codex","targetModelKey":"openai/gpt-5.5","invokeArgs":{}},{"backend":"gemini","targetModelKey":"google/gemini-3-flash-preview","invokeArgs":{}}]'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        Preview       = $true
    }
    Assert-True ($tBare.code -eq 0) '(T) Preview bare array should exit 0.'
    Assert-True ($null -eq $tBare.json.document.PSObject.Properties['migratedFrom']) '(T) bare array Preview must not carry migratedFrom.'

    # A one-element bare array must stay an array: ConvertFrom-Json without -NoEnumerate unwraps
    # it into a single object, which then failed the wrapper check with unknown-property.
    $tBareOne = Invoke-Set @{
        ReviewersJson = '[{"backend":"codex","targetModelKey":"openai/gpt-5.5","invokeArgs":{}}]'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        Preview       = $true
    }
    Assert-True ($tBareOne.code -eq 0) ("(T) Preview one-element bare array should exit 0; got {0} ({1})." -f $tBareOne.code, $tBareOne.raw)
    Assert-True (@($tBareOne.json.document.reviewers).Count -eq 1) '(T) one-element bare array should keep its single reviewer.'
    Assert-True ([string]@($tBareOne.json.document.reviewers)[0].targetModelKey -eq 'openai/gpt-5.5') '(T) one-element bare array should keep the reviewer target.'

    # An empty bare array carries no reviewer, exactly like a wrapper with an empty list.
    $tBareEmpty = Invoke-Set @{
        ReviewersJson = '[]'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        Preview       = $true
    }
    Assert-ReasonExit -Result $tBareEmpty -Reason 'reviewer-incomplete' -ExitCode 3 -Label '(T) empty bare array'

    $t2 = Invoke-Set @{
        ReviewersJson = '{"schemaVersion":2,"reviewers":[{"backend":"codex","targetModelKey":"openai/gpt-5.5","invokeArgs":{}}]}'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        Preview       = $true
    }
    Assert-ReasonExit -Result $t2 -Reason 'reviewers-schema-unsupported' -ExitCode 3 -Label '(T) schema2 input'

    # --------------------------------------------------------------------------------------
    # (U) atomic write: temp-file cleanup remains in the Set- text
    # --------------------------------------------------------------------------------------
    $setScriptText = Get-Content -LiteralPath $setScript -Raw -Encoding utf8
    Assert-True ($setScriptText -match 'Remove-Item -LiteralPath \$tmpPath') '(U) atomic write should clean up the temp file if Move-Item fails.'

    # --------------------------------------------------------------------------------------
    # (V) Cascade: machine write when preferred-reviewers.<orch>.json is present and shadowed
    # --------------------------------------------------------------------------------------
    $vRoot = Join-Path $tempRoot 'cascade-shadow'
    New-Item -ItemType Directory -Path $vRoot -Force | Out-Null
    $vOrch = Invoke-Set @{
        ReviewersJson = '{"reviewers":[{ "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": {} }]}'
        Orchestrator  = 'cursor'
        Scope         = 'orchestrator'
        PreferredRoot = $vRoot
    }
    Assert-True ($vOrch.code -eq 0) '(V) orchestrator setup should exit 0.'
    Assert-True ($vOrch.json.harnessResolveReadsThisPath -eq $true) '(V) Scope orchestrator should affect the harness Resolve.'
    Assert-True ($vOrch.json.resolveWouldPreferAfterWrite -eq 'orchestrator') '(V) resolveWouldPreferAfterWrite=orchestrator expected.'

    $vMach = Invoke-Set @{
        ReviewersJson = '{"reviewers":[{ "backend": "claude-code", "targetModelKey": "anthropic/claude-opus-5", "invokeArgs": {} }]}'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        PreferredRoot = $vRoot
    }
    Assert-True ($vMach.code -eq 0) '(V) Scope machine should exit 0 even when shadowed.'
    Assert-True ($vMach.json.harnessResolveReadsThisPath -eq $false) '(V) shadowed machine: harnessResolveReadsThisPath=false.'
    Assert-True ($vMach.json.resolveWouldPreferAfterWrite -eq 'orchestrator') '(V) after the machine write, Resolve still prefers orchestrator.'
    Assert-True (@($vMach.json.diagnostics) -contains 'machine-write-shadowed-by-orchestrator-file') '(V) diagnostics should cite machine-write-shadowed-by-orchestrator-file.'

    $vRes = Invoke-Resolve @{
        Orchestrator     = 'cursor'
        PreferredRoot    = $vRoot
        CapabilitiesPath = $capPath
    }
    Assert-True ($vRes.code -eq 0) '(V) Resolve should exit 0.'
    Assert-True ($vRes.json.preferenceSource -eq 'orchestrator') "(V) preferenceSource=orchestrator; got '$($vRes.json.preferenceSource)'."
    Assert-True ($vRes.json.cascadeOrchestratorExists -eq $true) '(V) cascadeOrchestratorExists=true.'
    Assert-True ($vRes.json.cascadeMachineExists -eq $true) '(V) cascadeMachineExists=true after the machine write.'
    Assert-True ($vRes.json.reviewers[0].backend -eq 'codex') '(V) Resolve should read the orchestrator file (codex), not machine.'

    # (V.1) overwrite-required also carries the shadowing signal, before -Overwrite
    $vShadowAgain = Invoke-Set @{
        ReviewersJson = '{"reviewers":[{ "backend": "gemini", "targetModelKey": "google/gemini-3-pro", "invokeArgs": {} }]}'
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        PreferredRoot = $vRoot
    }
    Assert-True ($vShadowAgain.code -eq 1) '(V.1) a second machine write without -Overwrite should exit 1.'
    Assert-True ($vShadowAgain.json.reason -eq 'overwrite-required') "(V.1) reason=overwrite-required; got '$($vShadowAgain.json.reason)'."
    Assert-True ($vShadowAgain.json.harnessResolveReadsThisPath -eq $false) '(V.1) the refusal should carry harnessResolveReadsThisPath=false.'
    Assert-True ($vShadowAgain.json.resolveWouldPreferAfterWrite -eq 'orchestrator') '(V.1) the refusal should carry resolveWouldPreferAfterWrite=orchestrator.'
    Assert-True (@($vShadowAgain.json.diagnostics) -contains 'machine-write-shadowed-by-orchestrator-file') '(V.1) the refusal should cite machine-write-shadowed-by-orchestrator-file.'
    Assert-True ($vShadowAgain.json.siblingOrchestratorExists -eq $true) '(V.1) the refusal should carry siblingOrchestratorExists=true.'

    # an invalid policy still blocks
    $badPolicy = @'
{
  "fallbackPolicy": { "mode": "custom", "defaultActivateOn": ["error"], "gateAskBehavior": "skip", "gateDenyBehavior": "skip" },
  "reviewers": [
    { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "invokeArgs": {} }
  ]
}
'@
    $bp = Invoke-Set @{
        ReviewersJson = $badPolicy
        Orchestrator  = 'cursor'
        Scope         = 'machine'
        OutputPath    = (Join-Path $tempRoot 'bad-policy.json')
    }
    Assert-ReasonExit -Result $bp -Reason 'fallback-policy-invalid' -ExitCode 3 -Label 'invalid fallbackPolicy'

    # --------------------------------------------------------------------------------------
    # Default root off Windows: without -PreferredRoot/-CapabilitiesPath, Set and
    # Resolve use $XDG_DATA_HOME/mimir-delegate. XDG_DATA_HOME points to a folder that does not exist
    # yet, where GetFolderPath('LocalApplicationData') returns an empty string. Neither call writes.
    # --------------------------------------------------------------------------------------
    if ($IsWindows) {
        Write-Host 'SKIP: off-Windows default preferred root cases (Windows host; the real %LOCALAPPDATA% is not redirected)' -ForegroundColor Yellow
    }
    else {
        $savedXdg = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
        $xdgDefault = Join-Path $tempRoot 'xdg-default'
        $expectedDefaultRoot = Join-Path $xdgDefault 'mimir-delegate'
        try {
            $env:XDG_DATA_HOME = $xdgDefault
            $setDefault = $null
            # Unparseable ReviewersJson stops after the target path is resolved and before any write.
            try { $setDefault = Invoke-Set @{ ReviewersJson = 'not-json'; Orchestrator = 'cursor'; Scope = 'machine' } }
            catch { throw "(default root) Set without -PreferredRoot threw: $($_.Exception.Message)" }
            Assert-ReasonExit -Result $setDefault -Reason 'reviewers-json-required' -ExitCode 1 -Label '(default root) Set with unparseable ReviewersJson'
            Assert-True ([string]$setDefault.json.outputPath -eq (Join-Path $expectedDefaultRoot 'preferred-reviewers.json')) "(default root) Set outputPath should be under XDG_DATA_HOME/mimir-delegate; got '$($setDefault.json.outputPath)'."

            $resolveDefault = $null
            try { $resolveDefault = Invoke-Resolve @{ Orchestrator = 'cursor' } }
            catch { throw "(default root) Resolve without -PreferredRoot threw: $($_.Exception.Message)" }
            Assert-True ($resolveDefault.code -eq 0) "(default root) Resolve should exit 0; got $($resolveDefault.code)."
            Assert-True ($resolveDefault.json.preferenceSource -eq 'none') "(default root) Resolve preferenceSource=none; got '$($resolveDefault.json.preferenceSource)'."
            Assert-True ([string]$resolveDefault.json.cascadeMachinePath -eq (Join-Path $expectedDefaultRoot 'preferred-reviewers.json')) "(default root) Resolve cascadeMachinePath should be under XDG_DATA_HOME/mimir-delegate; got '$($resolveDefault.json.cascadeMachinePath)'."
            Assert-True (-not (Test-Path -LiteralPath $xdgDefault)) '(default root) Set/Resolve must not create the state folder when nothing is written.'
        }
        finally {
            if ($null -eq $savedXdg) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdg }
        }
    }

    # --------------------------------------------------------------------------------------
    # Unresolvable state root off Windows: no XDG_DATA_HOME, a blank HOME and an empty
    # GetFolderPath('LocalApplicationData'), as in the closeout self-test Case 35. Resolve degrades
    # instead of throwing: without explicit paths it reports no preferences with a
    # state-root-unavailable diagnostic and treats the capability manifest as missing; explicit
    # -PreferredRoot, -PreferredPath and -CapabilitiesPath keep working. PowerShell's own $HOME is
    # blanked too, and the case runs from a fresh empty folder (process folder and location),
    # because .NET resolves the blank home against the process working folder.
    # --------------------------------------------------------------------------------------
    if ($IsWindows) {
        Write-Host 'SKIP: off-Windows unresolvable state root cases (Windows host)' -ForegroundColor Yellow
    }
    else {
        $savedXdgNoRoot = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
        $savedHomeEnvNoRoot = [Environment]::GetEnvironmentVariable('HOME')
        $savedHomeVarNoRoot = $HOME
        $savedCwdNoRoot = [Environment]::CurrentDirectory
        $cwdNoRoot = Join-Path $tempRoot 'no-state-root-cwd'
        $explicitRootNoRoot = Join-Path $tempRoot 'no-state-root-explicit'
        [void][System.IO.Directory]::CreateDirectory($cwdNoRoot)
        [void][System.IO.Directory]::CreateDirectory($explicitRootNoRoot)
        $explicitPrefNoRoot = Join-Path $explicitRootNoRoot 'preferred-reviewers.json'
        '{ "schemaVersion": 3, "reviewers": [ { "backend": "codex", "targetModelKey": "openai/gpt-5.5", "rank": 1, "invokeArgs": {} } ] }' |
            Set-Content -LiteralPath $explicitPrefNoRoot -Encoding utf8
        $pushedNoRoot = $false
        try {
            [Environment]::CurrentDirectory = $cwdNoRoot
            Push-Location -LiteralPath $cwdNoRoot
            $pushedNoRoot = $true
            Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue
            $env:HOME = ' '
            Set-Variable -Name HOME -Value '' -Scope Global -Force
            Assert-True ([Environment]::GetFolderPath('LocalApplicationData') -eq '') '(no state root) precondition: GetFolderPath(LocalApplicationData) should be empty.'

            $noRoot = $null
            try { $noRoot = Invoke-Resolve @{ Orchestrator = 'cursor' } }
            catch { throw "(no state root) Resolve should return its JSON envelope, not throw: $($_.Exception.Message)" }
            Assert-True ($noRoot.code -eq 0) "(no state root) Resolve should exit 0; got $($noRoot.code)."
            Assert-True ($noRoot.json.hasPreferences -eq $false) '(no state root) hasPreferences should be false.'
            Assert-True ([string]$noRoot.json.reason -eq 'no-preferred-file') "(no state root) reason should be 'no-preferred-file'; got '$($noRoot.json.reason)'."
            Assert-True ([string]$noRoot.json.preferenceSource -eq 'none') "(no state root) preferenceSource should be 'none'; got '$($noRoot.json.preferenceSource)'."
            $noRootDiagnostics = @($noRoot.json.diagnostics | ForEach-Object { [string]$_ })
            Assert-True (@($noRootDiagnostics | Where-Object { $_ -match '^state-root-unavailable' -and $_ -match 'XDG_DATA_HOME and HOME' }).Count -eq 1) "(no state root) diagnostics should carry one state-root-unavailable entry with the helper's reason; got: $($noRootDiagnostics -join ' | ')."
            Assert-True ([string]::IsNullOrEmpty([string]$noRoot.json.cascadeMachinePath)) "(no state root) cascadeMachinePath should be empty; got '$($noRoot.json.cascadeMachinePath)'."
            Assert-True ($noRoot.json.cascadeMachineExists -eq $false) '(no state root) cascadeMachineExists should be false.'

            # An explicit -PreferredRoot still resolves; the manifest is treated as missing.
            $explicitRoot = Invoke-Resolve @{ Orchestrator = 'cursor'; PreferredRoot = $explicitRootNoRoot }
            Assert-True ($explicitRoot.code -eq 0 -and $explicitRoot.json.hasPreferences -eq $true) "(no state root) -PreferredRoot should resolve the machine file; got exit $($explicitRoot.code): $($explicitRoot.raw)"
            Assert-True ([string]$explicitRoot.json.preferenceSource -eq 'machine') "(no state root) -PreferredRoot preferenceSource should be 'machine'; got '$($explicitRoot.json.preferenceSource)'."
            Assert-True ($explicitRoot.json.reviewers[0].availableInManifest -eq $false) '(no state root) without -CapabilitiesPath the manifest should be treated as missing.'
            Assert-True (@($explicitRoot.json.diagnostics | Where-Object { [string]$_ -match '^state-root-unavailable' }).Count -eq 1) '(no state root) -PreferredRoot without -CapabilitiesPath should still report the state-root-unavailable diagnostic.'

            # Explicit -PreferredPath and -CapabilitiesPath need no state root at all.
            $explicitPath = Invoke-Resolve @{ Orchestrator = 'cursor'; PreferredPath = $explicitPrefNoRoot; CapabilitiesPath = $capPath }
            Assert-True ($explicitPath.code -eq 0 -and $explicitPath.json.hasPreferences -eq $true) "(no state root) -PreferredPath should resolve; got exit $($explicitPath.code): $($explicitPath.raw)"
            Assert-True ([string]$explicitPath.json.preferenceSource -eq 'explicit-path') "(no state root) -PreferredPath preferenceSource should be 'explicit-path'; got '$($explicitPath.json.preferenceSource)'."
            Assert-True ($explicitPath.json.reviewers[0].availableInManifest -eq $true) '(no state root) an explicit -CapabilitiesPath should be read.'
            Assert-True (@($explicitPath.json.diagnostics | Where-Object { [string]$_ -match '^state-root-unavailable' }).Count -eq 0) '(no state root) with every path explicit, no state-root-unavailable diagnostic is expected.'
        }
        finally {
            if ($pushedNoRoot) { Pop-Location }
            [Environment]::CurrentDirectory = $savedCwdNoRoot
            Set-Variable -Name HOME -Value $savedHomeVarNoRoot -Scope Global -Force
            if ($null -eq $savedHomeEnvNoRoot) { Remove-Item Env:\HOME -ErrorAction SilentlyContinue } else { $env:HOME = $savedHomeEnvNoRoot }
            if ($null -eq $savedXdgNoRoot) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdgNoRoot }
        }
    }

    Write-Output 'OK: Test-LlmDelegatePreferredReviewersSelfTest.ps1'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
