#requires -Version 7.4
<#
.SYNOPSIS
    MECHANICAL dispatch+collection harness for a reviewer panel of the mimir-delegate skill:
    fires each reviewer at the LLM backend via the Invoke-*.ps1 adapters, collects the verdicts into
    a per-state ledger, and emits a machine panel-summary.json on stdout (one line).
.DESCRIPTION
    Implements the "panel dispatch harness" foreseen as future work in 15-peer-review.md.
    It is strictly MECHANICAL: it does NOT inject a native subagent, does NOT compute the diversity
    floor, and does NOT do closeout, triage, convergence, 'ask' authorization, human receipt, semantic
    reclassification responded->noResponse (off-task), single-flight, or opencode confinement. All of
    that belongs to the ORCHESTRATOR (outside this script). See 15-peer-review.md and
    skills/mimir-delegate/SKILL.md.

    Accepts exactly one manuscript source: -ManuscriptPath (an existing file) OR -ManuscriptText.
    In -ManuscriptText mode, it prepares transactional artifacts with New-LlmDelegatePeerReviewArtifacts.ps1
    before any gate/dispatch; a preparation failure emits its own summary with the round/dispatch
    not started and zero reviewers dispatched.

    Per reviewer (sequential, pre-dispatch):
      - opencode in kb-sensitive -> state=unavailable (no gate, no dispatch; confinement deferred);
      - effective model + fail-closeds (see -ReviewersJson);
      - Resolve-LlmDelegateAuthorization.ps1 gate (does NOT authorize): allow->dispatch queue,
        ask/deny->gateAsk/gateDeny, throw->error;
      - Antigravity public-review with a gate allow in kb-sensitive -> unavailable/refusedSensitivity
        before the adapter; ask/deny remain gate states;
      - classifies invokeArgs by a PER-BACKEND allowlist; containment (permissionMode/tools,
        agent, approvalMode!=plan) and internal adapter keys are REFUSED (securityBlockedArgs)
        and NOT passed through to the adapter:
        the dispatch proceeds with the adapter's safe defaults (a security decision, Position B);
      - resolves -Cd (precedence + fail-closed; opencode never receives -Cd; Antigravity
        public-review creates its own scratch space and refuses an inherited cwd).

    CONCURRENT dispatch: ForEach-Object -Parallel -ThrottleLimit 8 + SemaphoreSlim($OllamaConcurrency)
    via $using: ONLY for family 'ollama-cloud' (empirically validated on PS 7.6.2). Captured before Dispose.

    Result classification (STRUCTURAL, without parsing opinion prose): the other adapters follow
    non-empty text -> responded; quota/balance/limit sentinel -> quota; timeout (BLOCK exceeded ...
    terminated) -> timeout; empty/other -> error. Claude Code in the panel uses an atomic technical
    sidecar: stdout only counts when the accepted sidecar carries resultAccepted=true. No single-flight
    (deferred).

    STDOUT DISCIPLINE: this harness is a child process. panel-summary.json is the ONLY line of stdout.
    All human text goes out via [Console]::Error (Write-Host/Write-Warning/Write-Information LEAK into
    the captured stdout of a child process; only [Console]::Error stays out). The caller MUST capture
    stdout and stderr SEPARATELY; redirecting stderr->stdout would corrupt the JSON.
.PARAMETER ManuscriptPath
    Path to the manuscript sent to each reviewer (UTF-8). Mutually exclusive with -ManuscriptText.
.PARAMETER ManuscriptText
    Manuscript text. Mutually exclusive with -ManuscriptPath; generates manuscript.md/reviewers.json/manifest
    under <TempDir>\<RoundId> before dispatch starts. Use only for a short payload; for
    a large payload, use -ManuscriptPath to avoid Windows' command-line length limit.
.PARAMETER ReviewersJson
    JSON array [{backend, targetModelKey, invokeArgs, family?, rank?, fallbackChain?}] inline OR a file path. The
    orchestrator has already decided the set (native subagent injected OUTSIDE). fallbackChain[] is an ordered list
    of complete reviewers; the harness records attemptRole/fallbackOf/countsForDiversity in the result.
    family by order: explicit
    -> family resolved via Get-LlmDelegateTargetFamily -> $null (dispatchable, but does not count toward the floor).
    Effective model: opencode = invokeArgs.model or the INPUT targetModelKey (the opencode resolver
    requires -Model; the gate receives the same value); codex = invokeArgs.model or, if absent, gate WITHOUT -Model
    -> the returned targetModelKey's last segment; claude-code/copilot/gemini/antigravity = invokeArgs.model
    REQUIRED (absent -> state=error fail-closed). Null targetModelKey on opencode/codex where required
    -> state=error fail-closed.
.PARAMETER PayloadSensitivity
    Payload class: 'public' or 'kb-sensitive'. Passed through to the gate per reviewer.
.PARAMETER RoundId
    Round identifier (ledger subfolder). Default: [guid]::NewGuid().ToString('N').
.PARAMETER Cd
    Explicit working directory for the adapters that accept -Cd (codex/claude-code/gemini/copilot).
    Precedence: explicit -> $KbWorkspaceRoot in kb-sensitive -> cwd in public. opencode NEVER receives
    -Cd; Antigravity public-review creates its own scratch space and does not receive the repository root.
.PARAMETER KbWorkspaceRoot
    Root of the KB workspace; passed through to the gate (policy discovery) and used as -Cd in kb-sensitive.
.PARAMETER PolicyPath
    Explicit path to the policy file; passed through to the gate (takes precedence over -KbWorkspaceRoot).
.PARAMETER TempDir
    Ledger root. Default: <system temp>\mimir-panel-dispatch. The ledger lives at <TempDir>\<RoundId>\.
.PARAMETER OllamaConcurrency
    Cap on simultaneous calls to family 'ollama-cloud' (semaphore). [ValidateRange(1,16)];
    16 = mechanical cap, default 3 = SKILL.md's recommendation.
.PARAMETER OpenCodeConfigPath
    (TEST ONLY) -ConfigPath passed through to the gate on the opencode backend (synthetic opencode.json).
.PARAMETER CodexConfigPath
    (TEST ONLY) -ConfigPath passed through to the gate on the codex backend (synthetic config.toml).
.PARAMETER BackendExeMap
    (TEST ONLY) JSON {backend: exe-path} (inline OR a file path) to inject a fake-exe
    into the real adapter via -<Backend>Exe.
.PARAMETER ClaudeCircuitStateRoot
    (TEST ONLY) root of Claude Code's async adapter quota circuit.
.EXAMPLE
    .\Invoke-LlmDelegatePanelDispatch.ps1 -ManuscriptPath .\manuscript.md -ReviewersJson .\reviewers.json -PayloadSensitivity public
#>
[CmdletBinding()]
param(
    [string] $ManuscriptPath,
    [AllowEmptyString()] [string] $ManuscriptText,
    [Parameter(Mandatory)] [string] $ReviewersJson,
    [Parameter(Mandatory)] [ValidateSet('public', 'kb-sensitive')] [string] $PayloadSensitivity,
    [string] $RoundId,
    [string] $Cd,
    [string] $KbWorkspaceRoot,
    [string] $PolicyPath,
    [string] $TempDir,
    [ValidateRange(1, 16)] [int] $OllamaConcurrency = 3,
    # --- TEST ONLY ---
    [string] $OpenCodeConfigPath,
    [string] $CodexConfigPath,
    [string] $BackendExeMap,
    [string] $ClaudeCircuitStateRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# stdout discipline: UTF-8 without BOM; the JSON summary is the ONLY line of stdout.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
. (Join-Path $PSScriptRoot 'LlmDelegateTargetFamilySupport.ps1')

$MaxInlineManuscriptChars = 30000

# Adapter per backend; exe-override parameter (test only) per backend.
$AdapterScript = @{
    'opencode'    = 'Invoke-OpenCode.ps1'
    'codex'       = 'Invoke-Codex.ps1'
    'claude-code' = 'Invoke-ClaudeCodeAsync.ps1'
    'copilot'     = 'Invoke-Copilot.ps1'
    'gemini'      = 'Invoke-Gemini.ps1'
    'antigravity' = 'Invoke-Antigravity.ps1'
}
$ExeParam = @{
    'opencode'    = 'OpenCodeExe'
    'codex'       = 'CodexExe'
    'claude-code' = 'ClaudeExe'
    'copilot'     = 'CopilotExe'
    'gemini'      = 'GeminiExe'
    'antigravity' = 'AntigravityExe'
}
# Containment/internal keys refused (securityBlockedArgs) per backend. gemini.approvalMode is conditional.
$ContentionKeys = @{
    'claude-code' = @(
        'permissionmode', 'tools',
        'sidecarpath', 'retentionmode', 'tempdir', 'circuitstateroot', 'claudeexe',
        'message', 'messagepath'
    )
    'opencode'    = @('agent')
    'gemini'      = @('approvalmode')
    'antigravity' = @(
        'mode', 'agent', 'approvalmode', 'profile', 'cd', 'scratchpath', 'simulatecleanupfailure', 'receiptpath',
        'antigravityexe', 'message', 'messagepath'
    )
    'codex'       = @()
    'copilot'     = @()
}
$AdapterDefaultTimeoutSec = @{
    # An agentic review (reading the repo) can be long; the uniform synchronous default is 1200s.
    'opencode'    = 1200
    'codex'       = 1200
    'claude-code' = 1200
    'copilot'     = 1200
    'gemini'      = 1200
    'antigravity' = 1200
}
$AdapterCdCapable = @{
    'opencode'    = $false # contract: opencode never receives -Cd
    'codex'       = $true
    'claude-code' = $true
    'copilot'     = $true
    'gemini'      = $true
    'antigravity' = $false # public-review creates its own scratch; never inherits the dispatcher cwd
}

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and -not [string]::IsNullOrEmpty($Name) -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function Get-Slug {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'na' }
    return ([regex]::Replace($Value, '[^A-Za-z0-9._-]', '-'))
}

# `exhausted` does NOT enter bare: a generic network/context error ("retries exhausted", "connection pool
# exhausted", "context window exhausted") would turn into quota on EVERY backend and would send the
# operator to wait for a cycle reset over a failure that is not quota. Anchor on the exhausted subject
# (resource_exhausted, credits/balance/saldo exhausted); "quota exhausted" already matches via the term `quota`.
$quotaFailurePattern = '(?i)(^|[^0-9])(402|429)([^0-9]|$)|Payment Required|insufficient coding plan balance|quota|rate limit|resource_exhausted|(?:credits?|balance|saldo)\s+exhausted|too many requests|weekly usage limit|limite de uso|sem quota|saldo insuficiente'
$unavailableFailurePattern = '(?i)workspace-not-trusted'

function Test-QuotaFailureMessage {
    param([AllowNull()] [string] $Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    return ($Message -match $script:quotaFailurePattern)
}

function Test-UnavailableFailureMessage {
    param([AllowNull()] [string] $Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    return ($Message -match $script:unavailableFailurePattern)
}

function Get-FallbackDispatcherTimeoutMs {
    param([string]$Backend, $InvokeArgs)
    $defaultTimeoutMs = 180000
    # Slack after the adapter: classification, ledger, summary.
    $overheadMs = 120000
    $adapterDefaultTimeoutSec = 180
    if (-not [string]::IsNullOrWhiteSpace($Backend) -and $script:AdapterDefaultTimeoutSec.ContainsKey($Backend)) {
        $adapterDefaultTimeoutSec = [int]$script:AdapterDefaultTimeoutSec[$Backend]
    }
    $timeoutSecValue = Get-Prop $InvokeArgs 'timeoutSec'
    $timeoutSec = 0
    if ($null -eq $timeoutSecValue -or -not [int]::TryParse([string]$timeoutSecValue, [ref]$timeoutSec) -or $timeoutSec -lt 1) {
        $timeoutSec = $adapterDefaultTimeoutSec
    }

    # OpenCode in the panel: MaxAttempts=2 and TimeoutSec per attempt (wall ~2x).
    $attemptFactor = 1
    if ($Backend -eq 'opencode') {
        $attemptFactor = 2
    }

    $derivedTimeoutMs = ([int64]$timeoutSec * 1000 * [int64]$attemptFactor) + $overheadMs
    if ($derivedTimeoutMs -lt $defaultTimeoutMs) { return $defaultTimeoutMs }
    if ($derivedTimeoutMs -gt [int]::MaxValue) { return [int]::MaxValue }
    return [int]$derivedTimeoutMs
}

function Get-CurrentPowerShellExecutable {
    $currentExe = ''
    try { $currentExe = [string]([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch { }
    if (-not [string]::IsNullOrWhiteSpace($currentExe) -and (Test-Path -LiteralPath $currentExe -PathType Leaf)) {
        return $currentExe
    }

    $psHomeExeName = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }
    $psHomeExe = Join-Path $PSHOME $psHomeExeName
    if (Test-Path -LiteralPath $psHomeExe -PathType Leaf) {
        return $psHomeExe
    }

    throw "BLOCK: current PowerShell executable not resolved for the recursive fallback"
}

function Test-InvokeArgsBackendDivergence {
    param($Reviewer, [string]$Label)
    $backend = [string](Get-Prop $Reviewer 'backend')
    $invokeArgs = Get-Prop $Reviewer 'invokeArgs'
    $invBackend = [string](Get-Prop $invokeArgs 'backend')
    if (-not [string]::IsNullOrWhiteSpace($invBackend) -and $invBackend -ne $backend) {
        return "invokeArgs.backend ('$invBackend') diverge de backend ('$backend') em $Label"
    }
    return $null
}

function Get-FallbackItems {
    param($Reviewer)
    $fallbackItems = Get-Prop $Reviewer 'fallbackChain'
    if ($null -eq $fallbackItems) { return @() }
    return @($fallbackItems)
}

function Add-SkippedFallbackRecords {
    param(
        [System.Collections.Generic.List[object]]$Records,
        [object[]]$FallbackItems,
        [string]$FallbackOf,
        [string]$State,
        [string]$Reason,
        [int]$BaseRank,
        [string]$FallbackSuppressedReason,
        [int]$EntryIndex
    )
    for ($skipIdx = 0; $skipIdx -lt @($FallbackItems).Count; $skipIdx++) {
        $fb = @($FallbackItems)[$skipIdx]
        $idx = $Records.Count
        $fbTarget = [string](Get-Prop $fb 'targetModelKey')
        $fbBackend = [string](Get-Prop $fb 'backend')
        $Records.Add([ordered]@{
                index              = $idx
                ledgerIndex        = $script:LedgerSeq++
                entryIndex         = $EntryIndex
                suppressedFallbackChain = @()
                dispatchChannel    = 'cli'
                backend            = $fbBackend
                family             = if ($fbTarget) { Get-LlmDelegateTargetFamily -TargetModelKey $fbTarget } else { $null }
                targetModelKey     = $fbTarget
                effectiveModel     = [string](Get-Prop (Get-Prop $fb 'invokeArgs') 'model')
                gateVerdict        = $null
                state              = $State
                verdictPath        = $null
                errorPath          = $null
                statePath          = $null
                startedAt          = $null
                endedAt            = $null
                durationMs         = $null
                attempts           = 0
                reason             = $Reason
                droppedArgs        = @()
                securityBlockedArgs = @()
                attemptRole        = 'fallback'
                fallbackOf         = $FallbackOf
                fallbackIndex      = $skipIdx
                activationReason   = $null
                countsForDiversity = $false
                rank               = $BaseRank
                fallbackChain      = @()
                dispatchAttempted  = $false
                preDispatchBlocked = $false
                processCreated     = $null
                sidecarPath        = $null
                sidecarAccepted    = $null
                sidecarValidationReason = $null
                technicalStatus    = $null
                resultAccepted     = $null
                acceptanceRejectionReason = $null
                acceptedFinalTextSha256 = $null
                acceptedFinalTextBytes = $null
                promptTransmission = $null
                quotaCircuitDecision = $null
                quotaCircuitVariantDecisions = @()
                fallbackSuppressedReason = $FallbackSuppressedReason
            })
    }
}

function Get-TextSha256 {
    param([AllowNull()] [string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function Read-PanelJsonFileWithDeadline {
    param([string]$Path, [int]$DeadlineMs = 250)

    $deadline = [datetime]::UtcNow.AddMilliseconds($DeadlineMs)
    do {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                Start-Sleep -Milliseconds 25
                continue
            }
            $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
            return [pscustomobject]@{ status = 'ok'; value = ($raw | ConvertFrom-Json); error = $null }
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 25
        } catch {
            return [pscustomobject]@{ status = 'json-invalid'; value = $null; error = $_.Exception.Message }
        }
    } while ([datetime]::UtcNow -lt $deadline)

    return [pscustomobject]@{ status = 'read-inconclusive'; value = $null; error = 'deadline' }
}

function Test-ClaudeCodeSidecarShape {
    param([AllowNull()] $Sidecar, [AllowNull()] [string]$StdoutText)

    if ($null -eq $Sidecar) { return [pscustomobject]@{ accepted = $false; reason = 'sidecar-missing' } }
    $forbidden = @(
        'sidecarAccepted', 'sidecarValidationReason', 'state', 'countsForDiversity',
        'preDispatchBlocked', 'dispatchAttempted', 'fallbackSuppressedReason',
        'reviewersDispatched', 'reviewersProcessCreated', 'processCreatedUnknownCount', 'vNextState'
    )
    foreach ($name in $forbidden) {
        if ($Sidecar.PSObject.Properties[$name]) {
            return [pscustomobject]@{ accepted = $false; reason = "sidecar-forbidden-field:$name" }
        }
    }
    $required = @(
        'Kind', 'SchemaVersion', 'adapterName', 'backend', 'model', 'jobId', 'startedAtUtc',
        'endedAtUtc', 'durationMs', 'technicalStatus', 'resultAccepted',
        'acceptanceRejectionReason', 'exitCode', 'terminalReason', 'apiErrorStatus',
        'failureAfterText', 'stderrSha256', 'streamSha256', 'acceptedFinalTextSha256',
        'acceptedFinalTextBytes', 'finalTextDisposition', 'promptTransmission',
        'spawnAttempted', 'processCreated', 'processIdentity', 'processIdentityVerified',
        'cancelRequested', 'cancelIssued', 'cancelIdentityUnverifiable', 'quotaEvidence',
        'quotaCircuitDecision', 'retentionMode', 'retentionCleanupFailed'
    )
    foreach ($name in $required) {
        if (-not $Sidecar.PSObject.Properties[$name]) {
            return [pscustomobject]@{ accepted = $false; reason = "sidecar-missing-field:$name" }
        }
    }
    if ([string](Get-Prop $Sidecar 'Kind') -ne 'claude-code-async-sidecar') {
        return [pscustomobject]@{ accepted = $false; reason = 'sidecar-kind-invalid' }
    }
    $schemaVersion = Get-Prop $Sidecar 'SchemaVersion'
    if (($schemaVersion -isnot [int] -and $schemaVersion -isnot [long]) -or [int]$schemaVersion -ne 1) {
        return [pscustomobject]@{ accepted = $false; reason = 'sidecar-schema-invalid' }
    }
    if ([string](Get-Prop $Sidecar 'backend') -ne 'claude-code') {
        return [pscustomobject]@{ accepted = $false; reason = 'sidecar-backend-invalid' }
    }
    $acceptedValue = Get-Prop $Sidecar 'resultAccepted'
    if ($acceptedValue -isnot [bool]) {
        return [pscustomobject]@{ accepted = $false; reason = 'sidecar-resultAccepted-not-boolean' }
    }
    $accepted = [bool]$acceptedValue
    $technicalStatus = [string](Get-Prop $Sidecar 'technicalStatus')
    $finalTextDisposition = [string](Get-Prop $Sidecar 'finalTextDisposition')
    $retentionCleanupFailedValue = Get-Prop $Sidecar 'retentionCleanupFailed'
    if ($retentionCleanupFailedValue -isnot [bool]) {
        return [pscustomobject]@{ accepted = $false; reason = 'sidecar-retentionCleanupFailed-not-boolean' }
    }
    $retentionCleanupFailed = [bool]$retentionCleanupFailedValue
    if ($accepted) {
        if ($technicalStatus -ne 'completed') {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-accepted-with-noncompleted-status' }
        }
        if ($finalTextDisposition -ne 'stdout') {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-accepted-without-stdout-disposition' }
        }
        if ($retentionCleanupFailed) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-accepted-with-retention-cleanup-failed' }
        }
        if ([string]::IsNullOrWhiteSpace([string]$StdoutText)) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-accepted-with-empty-stdout' }
        }
        $hash = [string](Get-Prop $Sidecar 'acceptedFinalTextSha256')
        if ([string]::IsNullOrWhiteSpace($hash) -or $hash -ne (Get-TextSha256 -Text ([string]$StdoutText))) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-accepted-hash-mismatch' }
        }
        $bytes = Get-Prop $Sidecar 'acceptedFinalTextBytes'
        if ($bytes -isnot [int] -and $bytes -isnot [long]) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-accepted-bytes-invalid' }
        }
        if ([long]$bytes -ne [System.Text.Encoding]::UTF8.GetByteCount([string]$StdoutText)) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-accepted-bytes-mismatch' }
        }
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace([string]$StdoutText)) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-rejected-with-stdout' }
        }
        if ($finalTextDisposition -eq 'stdout') {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-rejected-with-stdout-disposition' }
        }
        if ($null -ne (Get-Prop $Sidecar 'acceptedFinalTextSha256')) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-rejected-with-accepted-hash' }
        }
        if ($null -ne (Get-Prop $Sidecar 'acceptedFinalTextBytes')) {
            return [pscustomobject]@{ accepted = $false; reason = 'sidecar-rejected-with-accepted-bytes' }
        }
    }
    return [pscustomobject]@{ accepted = $true; reason = 'ok' }
}

function Convert-ClaudeCodeSidecarToPanelState {
    param([object]$Sidecar)
    $technicalStatus = [string](Get-Prop $Sidecar 'technicalStatus')
    $resultAccepted = [bool](Get-Prop $Sidecar 'resultAccepted')
    if ($technicalStatus -eq 'completed' -and $resultAccepted) { return [pscustomobject]@{ state = 'responded'; reason = $null } }
    if ($technicalStatus -eq 'completed') { return [pscustomobject]@{ state = 'error'; reason = 'completed-without-accepted-result' } }
    switch ($technicalStatus) {
        'timeout' { return [pscustomobject]@{ state = 'timeout'; reason = [string](Get-Prop $Sidecar 'acceptanceRejectionReason') } }
        'quota' { return [pscustomobject]@{ state = 'quota'; reason = [string](Get-Prop $Sidecar 'acceptanceRejectionReason') } }
        'unavailable' { return [pscustomobject]@{ state = 'unavailable'; reason = [string](Get-Prop $Sidecar 'acceptanceRejectionReason') } }
        'internalError' { return [pscustomobject]@{ state = 'error'; reason = [string](Get-Prop $Sidecar 'acceptanceRejectionReason') } }
        'cancelled' { return [pscustomobject]@{ state = 'error'; reason = 'unexpected-cancelled-status' } }
        default { return [pscustomobject]@{ state = 'error'; reason = "unexpected-technical-status:$technicalStatus" } }
    }
}

$scriptsDir = $PSScriptRoot
$gateScript = Join-Path $scriptsDir 'Resolve-LlmDelegateAuthorization.ps1'
if (-not (Test-Path -LiteralPath $gateScript -PathType Leaf)) {
    throw "BLOCK: gate not found: $gateScript"
}

if ([string]::IsNullOrWhiteSpace($RoundId)) { $RoundId = [guid]::NewGuid().ToString('N') }
# Same hygiene as New-LlmDelegatePeerReviewArtifacts (which blocks with different wording,
# 'roundId-path-traversal'): RoundId enters the ledger and
# %TEMP%\mimir-panel-codex\<RoundId>\<NN> — fail-closed against unsafe chars / traversal.
if ($RoundId -match '[^A-Za-z0-9._-]' -or $RoundId -match '\.\.' -or $RoundId -match '[/\\]') {
    throw "BLOCK: unsafe RoundId: '$RoundId'. Use only letters, digits, dot, hyphen, and underscore."
}

$tempRoot = $TempDir
if ([string]::IsNullOrWhiteSpace($tempRoot)) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'mimir-panel-dispatch'
}

# 0) Caller preconditions: exactly one of -ManuscriptPath and -ManuscriptText
$useManuscriptText = ($PSBoundParameters.ContainsKey('ManuscriptText'))
$useManuscriptPath = ($PSBoundParameters.ContainsKey('ManuscriptPath'))
if ($useManuscriptText -eq $useManuscriptPath) {
    $failureCode = if ($useManuscriptText) { 'manuscript-source-ambiguous' } else { 'manuscript-source-missing' }
    $message = if ($useManuscriptText) {
        'Provide only one of -ManuscriptText and -ManuscriptPath.'
    } else {
        'Provide exactly one of -ManuscriptText and -ManuscriptPath.'
    }
    $blockResult = [ordered]@{
        Kind                         = 'mimir-panel-dispatch-result'
        SchemaVersion                = 3
        success                      = $false
        roundStarted                 = $false
        dispatchStarted              = $false
        reviewersDispatched          = 0
        reviewersDispatchAttempted   = 0
        reviewersProcessCreated      = 0
        processCreatedUnknownCount   = 0
        preDispatchBlockedCount      = 0
        sidecarAcceptedCount         = 0
        sidecarRejectedCount         = 0
        fallbackSuppressedCount      = 0
        roundId                      = $RoundId
        payloadSensitivity           = $PayloadSensitivity
        kbWorkspaceRoot              = $null
        policyPath                   = $null
        manuscriptPath               = $null
        ollamaConcurrency            = $OllamaConcurrency
        reviewers                    = @()
        dispatched                   = 0
        respondedCount               = 0
        errorCount                   = 0
        timeoutCount                 = 0
        quotaCount                   = 0
        unavailableCount             = 0
        gateAsk                      = 0
        gateDeny                     = 0
        ollamaQuotaWarning           = $null
        concurrencySaturationWarning = $null
        preparationError             = [ordered]@{
            failureStage = 'parameter-validation'
            failureCode  = $failureCode
            message      = $message
        }
    }
    [Console]::Error.WriteLine("BLOCK: ${failureCode}: $message")
    [Console]::Out.WriteLine(($blockResult | ConvertTo-Json -Compress -Depth 8))
    exit 1
}
if ($useManuscriptText -and $ManuscriptText.Length -gt $MaxInlineManuscriptChars) {
    $blockResult = [ordered]@{
        Kind                         = 'mimir-panel-dispatch-result'
        SchemaVersion                = 3
        success                      = $false
        roundStarted                 = $false
        dispatchStarted              = $false
        reviewersDispatched          = 0
        reviewersDispatchAttempted   = 0
        reviewersProcessCreated      = 0
        processCreatedUnknownCount   = 0
        preDispatchBlockedCount      = 0
        sidecarAcceptedCount         = 0
        sidecarRejectedCount         = 0
        fallbackSuppressedCount      = 0
        roundId                      = $RoundId
        payloadSensitivity           = $PayloadSensitivity
        kbWorkspaceRoot              = $null
        policyPath                   = $null
        manuscriptPath               = $null
        ollamaConcurrency            = $OllamaConcurrency
        reviewers                    = @()
        dispatched                   = 0
        respondedCount               = 0
        errorCount                   = 0
        timeoutCount                 = 0
        quotaCount                   = 0
        unavailableCount             = 0
        gateAsk                      = 0
        gateDeny                     = 0
        ollamaQuotaWarning           = $null
        concurrencySaturationWarning = $null
        preparationError             = [ordered]@{
            failureStage = 'parameter-validation'
            failureCode  = 'manuscript-text-too-large'
            message      = "-ManuscriptText exceeds $MaxInlineManuscriptChars characters; use -ManuscriptPath for a large payload."
        }
    }
    [Console]::Error.WriteLine("BLOCK: manuscript-text-too-large: -ManuscriptText excede $MaxInlineManuscriptChars caracteres; use -ManuscriptPath.")
    [Console]::Out.WriteLine(($blockResult | ConvertTo-Json -Compress -Depth 8))
    exit 1
}
if ($useManuscriptPath) {
    if (-not (Test-Path -LiteralPath $ManuscriptPath -PathType Leaf)) {
        $blockResult = [ordered]@{
            Kind                         = 'mimir-panel-dispatch-result'
            SchemaVersion                = 3
            success                      = $false
            roundStarted                 = $false
            dispatchStarted              = $false
            reviewersDispatched          = 0
            reviewersDispatchAttempted   = 0
            reviewersProcessCreated      = 0
            processCreatedUnknownCount   = 0
            preDispatchBlockedCount      = 0
            sidecarAcceptedCount         = 0
            sidecarRejectedCount         = 0
            fallbackSuppressedCount      = 0
            roundId                      = $RoundId
            payloadSensitivity           = $PayloadSensitivity
            kbWorkspaceRoot              = $null
            policyPath                   = $null
            manuscriptPath               = $null
            ollamaConcurrency            = $OllamaConcurrency
            reviewers                    = @()
            dispatched                   = 0
            respondedCount               = 0
            errorCount                   = 0
            timeoutCount                 = 0
            quotaCount                   = 0
            unavailableCount             = 0
            gateAsk                      = 0
            gateDeny                     = 0
            ollamaQuotaWarning           = $null
            concurrencySaturationWarning = $null
            preparationError             = [ordered]@{
                failureStage = 'parameter-validation'
                failureCode  = 'manuscript-path-not-found'
                message      = "-ManuscriptPath not found: $ManuscriptPath"
            }
        }
        [Console]::Error.WriteLine("BLOCK: manuscript-path-not-found: -ManuscriptPath not found.")
        [Console]::Out.WriteLine(($blockResult | ConvertTo-Json -Compress -Depth 8))
        exit 1
    }
    $manuscriptFull = (Resolve-Path -LiteralPath $ManuscriptPath).Path
    $ledgerDir = Join-Path $tempRoot $RoundId
    New-Item -ItemType Directory -Path $ledgerDir -Force | Out-Null
} else {
    # -ManuscriptText: prepare artifacts transactionally
    $preparerScript = Join-Path $scriptsDir 'New-LlmDelegatePeerReviewArtifacts.ps1'
    if (-not (Test-Path -LiteralPath $preparerScript -PathType Leaf)) {
        throw "BLOCK: artifact preparer not found: $preparerScript"
    }
    $prepReviewers = if (Test-Path -LiteralPath $ReviewersJson -PathType Leaf) {
        Get-Content -LiteralPath $ReviewersJson -Raw -Encoding utf8
    } else {
        $ReviewersJson
    }
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    $prepGuid = [guid]::NewGuid().ToString('N')
    $prepInputPath = Join-Path $tempRoot ".dispatch-prep-$prepGuid.manuscript.md"
    $prepReviewersPath = Join-Path $tempRoot ".dispatch-prep-$prepGuid.reviewers.json"
    $prepStdoutPath = Join-Path $tempRoot ".dispatch-prep-$prepGuid.stdout"
    $prepStderrPath = Join-Path $tempRoot ".dispatch-prep-$prepGuid.stderr"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($prepInputPath, $ManuscriptText, $utf8NoBom)
    [System.IO.File]::WriteAllText($prepReviewersPath, $prepReviewers, $utf8NoBom)

    $prepExitCode = $null
    $prepJson = $null
    $prepFailureMessage = $null
    try {
        $prepArgList = @(
            '-NoProfile',
            '-File', $preparerScript,
            '-ManuscriptPath', $prepInputPath,
            '-ReviewersJson', $prepReviewersPath,
            '-RoundId', $RoundId,
            '-TempDir', $tempRoot
        )
        $prepProcess = Start-Process -FilePath (Get-CurrentPowerShellExecutable) -ArgumentList $prepArgList -NoNewWindow -PassThru -RedirectStandardOutput $prepStdoutPath -RedirectStandardError $prepStderrPath
        if (-not $prepProcess.WaitForExit(120000)) {
            try { $prepProcess.Kill() } catch { }
            $prepExitCode = 124
            $prepFailureMessage = 'Artifact preparer exceeded 120s and was terminated.'
        } else {
            $prepExitCode = [int]$prepProcess.ExitCode
        }

        $prepStdout = Get-Content -LiteralPath $prepStdoutPath -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        if ($null -eq $prepStdout) { $prepStdout = '' }
        if (-not [string]::IsNullOrWhiteSpace($prepStdout)) {
            $prepJsonLine = @($prepStdout.Trim() -split "`r?`n") | Select-Object -Last 1
            try { $prepJson = $prepJsonLine | ConvertFrom-Json } catch { $prepFailureMessage = "Preparer returned invalid JSON: $($_.Exception.Message)" }
        } elseif ($null -eq $prepFailureMessage) {
            $prepFailureMessage = 'Preparer did not emit JSON on stdout.'
        }
    } finally {
        foreach ($p in @($prepInputPath, $prepReviewersPath, $prepStdoutPath, $prepStderrPath)) {
            try { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

    $prepSuccess = $false
    if ($null -ne $prepJson -and $prepJson.PSObject.Properties['success']) {
        $prepSuccess = [bool]$prepJson.success
    }
    if ($prepExitCode -ne 0 -or -not $prepSuccess) {
        $failureStage = 'artifactPreparation'
        $failureCode = 'artifact-preparation-failed'
        $message = $prepFailureMessage
        if ($null -ne $prepJson) {
            if ($prepJson.PSObject.Properties['failureStage']) { $failureStage = [string]$prepJson.failureStage }
            if ($prepJson.PSObject.Properties['failureCode']) { $failureCode = [string]$prepJson.failureCode }
            if ($prepJson.PSObject.Properties['message']) { $message = [string]$prepJson.message }
        }
        if ([string]::IsNullOrWhiteSpace($message)) { $message = 'Artifact preparation failed.' }
        $blockResult = [ordered]@{
            Kind                         = 'mimir-panel-dispatch-result'
            SchemaVersion                = 3
            success                      = $false
            roundStarted                 = $false
            dispatchStarted              = $false
            reviewersDispatched          = 0
            reviewersDispatchAttempted   = 0
            reviewersProcessCreated      = 0
            processCreatedUnknownCount   = 0
            preDispatchBlockedCount      = 0
            sidecarAcceptedCount         = 0
            sidecarRejectedCount         = 0
            fallbackSuppressedCount      = 0
            roundId                      = $RoundId
            payloadSensitivity           = $PayloadSensitivity
            kbWorkspaceRoot              = $null
            policyPath                   = $null
            manuscriptPath               = $null
            ollamaConcurrency            = $OllamaConcurrency
            reviewers                    = @()
            dispatched                   = 0
            respondedCount               = 0
            errorCount                   = 0
            timeoutCount                 = 0
            quotaCount                   = 0
            unavailableCount             = 0
            gateAsk                      = 0
            gateDeny                     = 0
            ollamaQuotaWarning           = $null
            concurrencySaturationWarning = $null
            preparationError             = [ordered]@{
                failureStage = $failureStage
                failureCode  = $failureCode
                message      = $message
            }
        }
        $blockJson = $blockResult | ConvertTo-Json -Compress -Depth 8
        [Console]::Error.WriteLine("BLOCK: artifact preparation failed: $failureCode - $message")
        [Console]::Out.WriteLine($blockJson)
        exit 1
    }
    $manuscriptFull = [string]$prepJson.artifactPaths.manuscript
    $ReviewersJson = [string]$prepJson.artifactPaths.reviewers
    $ledgerDir = Join-Path $tempRoot $RoundId
}

# Fake-exe map (test only): inline OR file
$exeMap = $null
if (-not [string]::IsNullOrWhiteSpace($BackendExeMap)) {
    $exeMapRaw = $BackendExeMap
    if (Test-Path -LiteralPath $BackendExeMap -PathType Leaf) {
        $exeMapRaw = Get-Content -LiteralPath $BackendExeMap -Raw -Encoding utf8
    }
    try { $exeMap = $exeMapRaw | ConvertFrom-Json } catch { throw "BLOCK: -BackendExeMap is not valid JSON: $($_.Exception.Message)" }
}

# Reviewers input: inline or file
$reviewersRaw = $null
if (Test-Path -LiteralPath $ReviewersJson -PathType Leaf) {
    $reviewersRaw = Get-Content -LiteralPath $ReviewersJson -Raw -Encoding utf8
} else {
    $reviewersRaw = $ReviewersJson
}
$reviewers = $null
try { $reviewers = @($reviewersRaw | ConvertFrom-Json) } catch { throw "BLOCK: -ReviewersJson is not valid JSON: $($_.Exception.Message)" }

# --------------------------------------------------------------------------------------------
# PRE-DISPATCH PHASE (sequential): produces one record per reviewer; the 'allow' ones become
# dispatch plans. Each record is a mutable [ordered]@{}; key order matches the contract.
# --------------------------------------------------------------------------------------------
$records = [System.Collections.Generic.List[object]]::new()
$dispatchList = [System.Collections.Generic.List[object]]::new()
$script:LedgerSeq = 0

for ($i = 0; $i -lt $reviewers.Count; $i++) {
    $r = $reviewers[$i]
    $backend = [string](Get-Prop $r 'backend')
    $invokeArgs = Get-Prop $r 'invokeArgs'
    $fallbackItems = @(Get-FallbackItems -Reviewer $r)

    $inputKey = [string](Get-Prop $r 'targetModelKey')
    if ([string]::IsNullOrWhiteSpace($inputKey)) { $inputKey = $null }
    $familyExplicit = [string](Get-Prop $r 'family')
    if ([string]::IsNullOrWhiteSpace($familyExplicit)) { $familyExplicit = $null }

    # Base record (every contract key; mutated further below)
    $rec = [ordered]@{
        index              = $i
        ledgerIndex        = $script:LedgerSeq++
        entryIndex         = $i
        suppressedFallbackChain = @()
        dispatchChannel    = 'cli'
        backend            = $backend
        family             = $familyExplicit
        targetModelKey     = $inputKey
        effectiveModel     = $null
        gateVerdict        = $null
        state              = $null
        verdictPath        = $null
        errorPath          = $null
        statePath          = $null
        startedAt          = $null
        endedAt            = $null
        durationMs         = $null
        attempts           = 0
        reason             = $null
        droppedArgs        = @()
        securityBlockedArgs = @()
        attemptRole        = 'primary'
        fallbackOf         = $null
        fallbackIndex      = $null
        activationReason   = $null
        countsForDiversity = $false
        rank               = if ($null -ne (Get-Prop $r 'rank')) { [int](Get-Prop $r 'rank') } else { $i + 1 }
        fallbackChain      = @($fallbackItems)
        dispatchAttempted  = $false
        preDispatchBlocked = $false
        processCreated     = $null
        sidecarPath        = $null
        sidecarAccepted    = $null
        sidecarValidationReason = $null
        technicalStatus    = $null
        resultAccepted     = $null
        acceptanceRejectionReason = $null
        acceptedFinalTextSha256 = $null
        acceptedFinalTextBytes = $null
        promptTransmission = $null
        quotaCircuitDecision = $null
        quotaCircuitVariantDecisions = @()
        fallbackSuppressedReason = $null
        adapterReceiptPath = $null
        publicReviewProfile = $null
        cliVersion = $null
        cliVersionMatchesBaseline = $null
        cleanupStatus = $null
        cleanupIssues = @()
        keyringIsolation = $null
        recoveredAfterTimeout = $null
    }

    # Defense in depth: native does not dispatch in this harness
    if ($rec.backend -eq 'orchestrator-native') {
        $rec.state = 'error'
        $rec.reason = 'orchestrator-native-leaked-to-dispatch'
        $rec.dispatchAttempted = $false
        $rec.attempts = 0
        $rec.countsForDiversity = $false
        $rec.suppressedFallbackChain = @($rec.fallbackChain)
        $rec.fallbackChain = @()
        $rec.entryIndex = $i
        $records.Add($rec)
        continue
    }

    $backendDivergence = Test-InvokeArgsBackendDivergence -Reviewer $r -Label "reviewer[$i]"
    if ($backendDivergence) {
        $rec.state = 'error'
        $rec.reason = "BLOCK: $backendDivergence"
        $records.Add($rec); continue
    }
    $fallbackDivergence = $null
    for ($fbIdx = 0; $fbIdx -lt $fallbackItems.Count; $fbIdx++) {
        $fallbackDivergence = Test-InvokeArgsBackendDivergence -Reviewer $fallbackItems[$fbIdx] -Label "fallbackChain[$fbIdx] of $inputKey"
        if ($fallbackDivergence) { break }
    }
    if ($fallbackDivergence) {
        $rec.state = 'error'
        $rec.reason = "BLOCK: $fallbackDivergence"
        $records.Add($rec); continue
    }

    # Invalid backend -> defensive error
    if (-not $AdapterScript.ContainsKey($backend)) {
        $rec.state = 'error'
        $rec.reason = "unknown backend: '$backend'"
        $records.Add($rec); continue
    }

    # --- invokeArgs classification (independent of the gate): securityBlockedArgs / droppedArgs / extraSplat ---
    $dropped = [System.Collections.Generic.List[string]]::new()
    $secBlocked = [System.Collections.Generic.List[string]]::new()
    $extraSplat = @{}
    $timeoutSecParseError = $null
    if ($null -ne $invokeArgs) {
        foreach ($prop in $invokeArgs.PSObject.Properties) {
            $k = $prop.Name
            $kl = $k.ToLowerInvariant()
            $v = $prop.Value
            if ($kl -eq 'model') { continue }   # handled as the effective model
            # per-backend containment
            if ($ContentionKeys[$backend] -contains $kl) {
                if ($backend -eq 'gemini' -and $kl -eq 'approvalmode') {
                    if ([string]$v -eq 'plan') { $dropped.Add($k) }   # default; silent drop (does not relax)
                    else { $secBlocked.Add($k) }                       # !=plan -> refused (early fail-closed)
                } else {
                    $secBlocked.Add($k)
                }
                continue
            }
            # dispatch allowlist
            if ($kl -eq 'timeoutsec') {
                # GAP-2: do not use [int]$v (global throw). Local reviewer goes to error; panel continues.
                $parsedTs = 0
                if (-not [int]::TryParse([string]$v, [ref]$parsedTs) -or $parsedTs -lt 1 -or $parsedTs -gt 3600) {
                    $timeoutSecParseError = "invokeArgs.timeoutSec invalid: '$v' (requires an integer 1..3600)"
                } else {
                    $extraSplat['TimeoutSec'] = $parsedTs
                }
                continue
            }
            if ($backend -eq 'codex') {
                if ($kl -eq 'profile') { $extraSplat['Profile'] = [string]$v; continue }
                if ($kl -eq 'oss') { if ($v) { $extraSplat['Oss'] = $true }; continue }   # -Oss only when true
                if ($kl -eq 'localprovider') { $extraSplat['LocalProvider'] = [string]$v; continue }
            }
            $dropped.Add($k)
        }
    }
    $rec.droppedArgs = @($dropped)
    $rec.securityBlockedArgs = @($secBlocked)

    if ($null -ne $timeoutSecParseError) {
        $rec.state = 'error'
        $rec.reason = $timeoutSecParseError
        if (-not $rec.family -and $inputKey) { $rec.family = Get-LlmDelegateTargetFamily -TargetModelKey $inputKey }
        $records.Add($rec); continue
    }

    # --- opencode in kb-sensitive: terminal unavailable (no gate/dispatch) ---
    if ($backend -eq 'opencode' -and $PayloadSensitivity -eq 'kb-sensitive') {
        $rec.state = 'unavailable'
        $rec.reason = 'opencode in kb-sensitive: confinement via a custom agent is deferred; no gate and no dispatch'
        if (-not $rec.family -and $inputKey) { $rec.family = Get-LlmDelegateTargetFamily -TargetModelKey $inputKey }
        $records.Add($rec); continue
    }

    # --- Effective model + pre-gate fail-closeds ---
    $invModel = [string](Get-Prop $invokeArgs 'model')
    if ([string]::IsNullOrWhiteSpace($invModel)) { $invModel = $null }
    $effectiveModel = $null
    $gateModel = $null   # what goes to the gate as -Model (may be omitted for codex)

    if ($backend -eq 'opencode') {
        if ($invModel) { $effectiveModel = $invModel } elseif ($inputKey) { $effectiveModel = $inputKey }
        if (-not $effectiveModel) {
            $rec.state = 'error'
            $rec.reason = 'opencode requires a model (invokeArgs.model or targetModelKey provider/model); both missing'
            $records.Add($rec); continue
        }
        $gateModel = $effectiveModel
    }
    elseif ($backend -eq 'codex') {
        # the effective model only resolves after the gate (gate without -Model derives from config -> targetModelKey)
        if ($invModel) { $gateModel = $invModel }   # senao omite -Model
    }
    else {
        # claude-code / copilot / gemini / antigravity -> invokeArgs.model REQUIRED
        if (-not $invModel) {
            $rec.state = 'error'
            $rec.reason = "invokeArgs.model is required for backend ${backend}: the adapter default is implicit and may diverge from the key resolved by the gate; requiring model makes the target declared and auditable"
            if (-not $rec.family -and $inputKey) { $rec.family = Get-LlmDelegateTargetFamily -TargetModelKey $inputKey }
            $records.Add($rec); continue
        }
        $effectiveModel = $invModel
        $gateModel = $invModel
    }

    # --- Gate (does not authorize) ---
    $gateArgs = @{ Backend = $backend; PayloadSensitivity = $PayloadSensitivity }
    if ($gateModel) { $gateArgs['Model'] = $gateModel }
    if ($PolicyPath) { $gateArgs['PolicyPath'] = $PolicyPath }
    elseif ($KbWorkspaceRoot) { $gateArgs['KbWorkspaceRoot'] = $KbWorkspaceRoot }
    if ($backend -eq 'codex') {
        if ($extraSplat.ContainsKey('Oss')) { $gateArgs['Oss'] = $true }
        if ($extraSplat.ContainsKey('LocalProvider')) { $gateArgs['LocalProvider'] = $extraSplat['LocalProvider'] }
        if ($extraSplat.ContainsKey('Profile')) { $gateArgs['Profile'] = $extraSplat['Profile'] }
        if (-not [string]::IsNullOrWhiteSpace($CodexConfigPath)) { $gateArgs['ConfigPath'] = $CodexConfigPath }
    }
    if ($backend -eq 'opencode' -and -not [string]::IsNullOrWhiteSpace($OpenCodeConfigPath)) {
        $gateArgs['ConfigPath'] = $OpenCodeConfigPath
    }

    $gateOut = $null
    try {
        $gateOut = & $gateScript @gateArgs | ConvertFrom-Json
    } catch {
        $rec.state = 'error'
        $rec.gateVerdict = $null
        $rec.reason = "gate lancou: $($_.Exception.Message)"
        if (-not $rec.family -and $inputKey) { $rec.family = Get-LlmDelegateTargetFamily -TargetModelKey $inputKey }
        $records.Add($rec); continue
    }

    $gateVerdict = [string]$gateOut.verdict
    $returnedKey = [string](Get-Prop $gateOut 'targetModelKey')
    if ([string]::IsNullOrWhiteSpace($returnedKey)) { $returnedKey = $null }

    $rec.gateVerdict = $gateVerdict
    if ($returnedKey) { $rec.targetModelKey = $returnedKey }

    # codex: derives the bare model from the returned targetModelKey; null -> fail-closed
    if ($backend -eq 'codex') {
        if (-not $returnedKey) {
            $rec.state = 'error'
            $rec.reason = 'codex without a resolvable model: gate without -Model did not derive targetModelKey from the config (fail-closed)'
            if (-not $rec.family -and $inputKey) { $rec.family = Get-LlmDelegateTargetFamily -TargetModelKey $inputKey }
            $records.Add($rec); continue
        }
        $effectiveModel = @($returnedKey -split '/')[-1]
    }
    $rec.effectiveModel = $effectiveModel

    # final family
    if (-not $rec.family) {
        if ($returnedKey) { $rec.family = Get-LlmDelegateTargetFamily -TargetModelKey $returnedKey }
        elseif ($inputKey) { $rec.family = Get-LlmDelegateTargetFamily -TargetModelKey $inputKey }
    }

    # Verdict
    if ($gateVerdict -eq 'ask') {
        $rec.state = 'gateAsk'
        $rec.reason = [string](Get-Prop $gateOut 'reason')
        $records.Add($rec); continue
    }
    if ($gateVerdict -eq 'deny') {
        $rec.state = 'gateDeny'
        $rec.reason = [string](Get-Prop $gateOut 'reason')
        $records.Add($rec); continue
    }
    if ($gateVerdict -ne 'allow') {
        $rec.state = 'error'
        $rec.reason = "gate devolveu verdict inesperado: '$gateVerdict'"
        $records.Add($rec); continue
    }

    # Antigravity public-review is exclusively public. The gate remains the confidentiality owner
    # and always runs first: ask/deny preserve their normative states. If a durable policy
    # were to allow kb-sensitive, the fixed posture refuses the dispatch before the adapter and records
    # the divergence as unavailable + refusedSensitivity; the adapter does not classify the payload.
    if ($backend -eq 'antigravity' -and $PayloadSensitivity -eq 'kb-sensitive') {
        $rec.state = 'unavailable'
        $rec.reason = 'refusedSensitivity'
        $rec.preDispatchBlocked = $true
        $rec.publicReviewProfile = 'public-review'
        $records.Add($rec); continue
    }

    # --- allow: assembles the dispatch ---
    $splat = @{ MessagePath = $manuscriptFull; Model = $effectiveModel }

    # -Cd: precedence + fail-closed (opencode never receives -Cd)
    $cdCapable = [bool]$AdapterCdCapable[$backend]
    if ($cdCapable) {
        if ($PayloadSensitivity -eq 'kb-sensitive' -and -not $Cd -and -not $KbWorkspaceRoot) {
            $rec.state = 'error'
            $rec.reason = "kb-sensitive without -Cd/-KbWorkspaceRoot for an adapter with -Cd ($backend): fail-closed (cannot confine the cwd to sensitive content)"
            $records.Add($rec); continue
        }
        $cdVal = $null
        if ($Cd) { $cdVal = $Cd }
        elseif ($PayloadSensitivity -eq 'kb-sensitive') { $cdVal = $KbWorkspaceRoot }
        else { $cdVal = (Get-Location).Path }
        $splat['Cd'] = $cdVal
    }

    # fake-exe (test only)
    if ($null -ne $exeMap) {
        $exeOverride = [string](Get-Prop $exeMap $backend)
        if (-not [string]::IsNullOrWhiteSpace($exeOverride)) { $splat[$ExeParam[$backend]] = $exeOverride }
    }

    # retry-once, opencode only
    if ($backend -eq 'opencode') { $splat['MaxAttempts'] = 2 }

    # Claude Code in the panel uses a typed asynchronous adapter: the dispatcher validates the technical
    # sidecar and only accepts stdout as an opinion when resultAccepted=true.
    if ($backend -eq 'claude-code') {
        $sidecarPath = Join-Path $ledgerDir ('{0:D2}-claude-code.sidecar.json' -f $i)
        $splat['SidecarPath'] = $sidecarPath
        $splat['RetentionMode'] = $PayloadSensitivity
        $splat['TempDir'] = $ledgerDir
        if (-not [string]::IsNullOrWhiteSpace($ClaudeCircuitStateRoot)) {
            $splat['CircuitStateRoot'] = $ClaudeCircuitStateRoot
        }
        $rec.sidecarPath = $sidecarPath
    }
    elseif ($backend -eq 'codex') {
        # TempDir OUTSIDE the -Cd/workspace under review: job files (request/stream/lastmsg) in %TEMP%
        # keep the agent from exploring the dispatch's own artifacts. The panel ledger stays in
        # $ledgerDir (verdict/error). Bound wins; invokeArgs.tempdir falls into droppedArgs.
        # PER-REVIEWER subdirectory (<RoundId>\<NN>): recoveredAfterTimeout pairing matches
        # the returned text against the directory's *.lastmsg.txt. With a directory shared by the
        # round, two codex primary reviewers returning the SAME text would make the pairing
        # ambiguous, and the recovery could be attributed to the wrong reviewer. A per-reviewer
        # directory eliminates the collision at the source, instead of tie-breaking by heuristic.
        $codexCaptureRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'mimir-panel-codex'
        $codexCaptureDir = Join-Path (Join-Path $codexCaptureRoot $RoundId) ('{0:D2}' -f $i)
        [void][System.IO.Directory]::CreateDirectory($codexCaptureDir)
        $splat['RetentionMode'] = $PayloadSensitivity
        $splat['TempDir'] = $codexCaptureDir
    }
    elseif ($backend -eq 'antigravity') {
        $receiptPath = Join-Path $ledgerDir ('{0:D2}-antigravity-public-review.receipt.json' -f $i)
        $splat['Profile'] = 'public-review'
        $splat['ReceiptPath'] = $receiptPath
        $rec.adapterReceiptPath = $receiptPath
        $rec.publicReviewProfile = 'public-review'
    }

    # TimeoutSec: uniform default of the panel and the synchronous adapters (1200s), unless a valid override.
    if (-not $extraSplat.ContainsKey('TimeoutSec') -and
        $AdapterDefaultTimeoutSec.ContainsKey($backend)) {
        $extraSplat['TimeoutSec'] = [int]$AdapterDefaultTimeoutSec[$backend]
    }

    # allowlisted args (TimeoutSec / codex Profile/Oss/LocalProvider)
    foreach ($ek in $extraSplat.Keys) { $splat[$ek] = $extraSplat[$ek] }

    $adapterPath = Join-Path $scriptsDir $AdapterScript[$backend]
    $dispatchList.Add([pscustomobject]@{
        index       = $i
        backend     = $backend
        family      = $rec.family
        adapterPath = $adapterPath
        splat       = $splat
        sidecarPath = if ($backend -eq 'claude-code') { $rec.sidecarPath } else { $null }
        adapterReceiptPath = if ($backend -eq 'antigravity') { $rec.adapterReceiptPath } else { $null }
    })

    $rec.state = 'PENDING'
    $records.Add($rec)
}

# --------------------------------------------------------------------------------------------
# CONCURRENT DISPATCH: ForEach-Object -Parallel + SemaphoreSlim via $using: (only 'ollama-cloud').
# --------------------------------------------------------------------------------------------
$ollamaDispatched = @($dispatchList | Where-Object { $_.family -eq 'ollama-cloud' }).Count
$ollamaQuotaWarning = $null
if ($ollamaDispatched -ge 2) {
    $ollamaQuotaWarning = "ollamaQuotaWarning: $ollamaDispatched ollama-cloud/* reviewers dispatched in the same batch; the quota (e.g. weekly usage limit) may be shared - see KNOWN LIMIT HTTP 429."
}

$collected = @()
$sem = [System.Threading.SemaphoreSlim]::new($OllamaConcurrency, $OllamaConcurrency)
try {
    if ($dispatchList.Count -gt 0) {
        $collected = $dispatchList | ForEach-Object -Parallel {
            $item = $_
            $sem = $using:sem
            Set-StrictMode -Version Latest

            $useSem = ($item.family -eq 'ollama-cloud')
            $acquired = $false
            $result = $null
            $quotaPattern = $using:quotaFailurePattern
            $unavailablePattern = $using:unavailableFailurePattern
            # OUTER try wraps the ENTIRE body: nothing (not Wait, not Get-Date, not the object build)
            # escapes the runspace (per v11 "the block never throws outward").
            try {
                if ($useSem) { $sem.Wait(); $acquired = $true }
                $startedAt = (Get-Date).ToUniversalTime()
                $outVal = $null
                $errRec = $null
                try {
                    $p = $item.splat
                    $outVal = & $item.adapterPath @p
                } catch {
                    $errRec = $_
                }
                $endedAt = (Get-Date).ToUniversalTime()

                $joined = $null
                if ($null -ne $outVal) {
                    if ($outVal -is [array]) { $joined = ($outVal -join "`n") } else { $joined = [string]$outVal }
                }

                $state = $null; $textOut = $null; $errText = $null
                if ($item.backend -eq 'claude-code') {
                    $state = 'PENDING-SIDECAR'
                    $textOut = $joined
                    if ($null -ne $errRec) { $errText = [string]$errRec.Exception.Message }
                }
                elseif ($null -ne $errRec) {
                    # $errText = complete message (MIMIR_CODEX_* sentinels + kb-sensitive capture).
                    # $classifiedMsg = prefix BEFORE the first MIMIR_CODEX_ line (after normalizing
                    # \r\n -> \n). Do NOT call a function from the parent runspace — inline / $using: only.
                    $errText = [string]$errRec.Exception.Message
                    $errNorm = $errText -replace "`r`n", "`n"
                    $classifiedMsg = $errNorm
                    $cut = -1
                    if ($errNorm.StartsWith('MIMIR_CODEX_')) {
                        $cut = 0
                    } else {
                        $marker = "`nMIMIR_CODEX_"
                        $cut = $errNorm.IndexOf($marker)
                    }
                    if ($cut -eq 0) {
                        $classifiedMsg = ''
                    } elseif ($cut -gt 0) {
                        $classifiedMsg = $errNorm.Substring(0, $cut)
                    }
                    $msg = $classifiedMsg
                    if ($msg -match 'BLOCK:' -and $msg -match $quotaPattern) {
                        $state = 'quota'
                    # `refusedSensitivity` does NOT enter here: the adapter never emits it (it does not
                    # receive sensitivity) and the pre-dispatch block records the state and does `continue`
                    # before any call, so this classifier would never see it.
                    } elseif ($item.backend -eq 'antigravity' -and $msg -match 'reason=(cliMissing|inputTooLarge|unsafeWorkspace)') {
                        $state = 'unavailable'
                    } elseif ($item.backend -eq 'antigravity' -and $msg -match 'reason=timeout') {
                        $state = 'timeout'
                    } elseif ($msg -match 'BLOCK:' -and $msg -match $unavailablePattern) {
                        $state = 'unavailable'
                    } elseif ($msg -match 'exceeded' -and $msg -match 'was terminated') {
                        $state = 'timeout'
                    } else {
                        $state = 'error'
                    }
                    # errorPath / __errorText use the complete $errText (sentinels + capture).
                } else {
                    if ([string]::IsNullOrWhiteSpace($joined)) {
                        $state = 'error'
                        $errText = 'BLOCK: adapter returned empty text (defensive).'
                    } else {
                        $state = 'responded'
                        $textOut = $joined
                    }
                }

                # GAP-3: project recoveredAfterTimeout from the Codex request.json (pairing via lastmsg).
                $recoveredAfterTimeout = $null
                # In kb-sensitive the adapter itself deletes lastmsg + request.json on the SUCCESS
                # path — and post-timeout recovery is a success. Without those files there is no
                # possible pairing, so the field stays $null (unknown) instead of $false:
                # false would assert "there was no recovery", which the dispatcher cannot know here.
                # The MIMIR_CODEX_RECOVERED_AFTER_TIMEOUT sentinel goes to the PROCESS's stderr via
                # [Console]::Error and does not go through PowerShell's error flow, so it is not
                # available on this branch (only when the adapter throws). Retaining a receipt in kb-sensitive
                # would contradict the mode's promise — the mode erases everything.
                $codexRetention = $null
                if ($null -ne $item.splat -and $item.splat.ContainsKey('RetentionMode')) {
                    $codexRetention = [string]$item.splat['RetentionMode']
                }
                if ($state -eq 'responded' -and $item.backend -eq 'codex' -and $codexRetention -ne 'kb-sensitive' -and -not [string]::IsNullOrWhiteSpace($textOut)) {
                    $recoveredAfterTimeout = $false
                    try {
                        $codexTd = $null
                        if ($null -ne $item.splat -and $item.splat.ContainsKey('TempDir')) {
                            $codexTd = [string]$item.splat['TempDir']
                        }
                        if (-not [string]::IsNullOrWhiteSpace($codexTd) -and (Test-Path -LiteralPath $codexTd -PathType Container)) {
                            $want = $textOut.TrimEnd("`r", "`n")
                            foreach ($lm in @(Get-ChildItem -LiteralPath $codexTd -Filter '*.lastmsg.txt' -File -ErrorAction SilentlyContinue)) {
                                $body = Get-Content -LiteralPath $lm.FullName -Raw -Encoding utf8 -ErrorAction SilentlyContinue
                                if ($null -eq $body) { continue }
                                if ($body.TrimEnd("`r", "`n") -ne $want) { continue }
                                $reqSibling = $lm.FullName -replace '\.lastmsg\.txt$', '.request.json'
                                if (-not (Test-Path -LiteralPath $reqSibling -PathType Leaf)) { break }
                                $ro = Get-Content -LiteralPath $reqSibling -Raw -Encoding utf8 | ConvertFrom-Json
                                if ($null -ne $ro -and $ro.PSObject.Properties['recoveredAfterTimeout'] -and [bool]$ro.recoveredAfterTimeout) {
                                    $recoveredAfterTimeout = $true
                                }
                                break
                            }
                        }
                    } catch {
                        $recoveredAfterTimeout = $false
                    }
                }

                $result = [pscustomobject]@{
                    index      = $item.index
                    backend    = $item.backend
                    state      = $state
                    text       = $textOut
                    errorText  = $errText
                    startedAt  = $startedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    endedAt    = $endedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    durationMs = [long]($endedAt - $startedAt).TotalMilliseconds
                    attempts   = 1
                    sidecarPath = $item.sidecarPath
                    adapterReceiptPath = $item.adapterReceiptPath
                    recoveredAfterTimeout = $recoveredAfterTimeout
                }
            } catch {
                # Defense in depth: any unexpected exception in the runspace (e.g. Wait,
                # Get-Date) turns into an 'error' result — never escapes the block (per v11).
                $result = [pscustomobject]@{
                    index      = $item.index
                    backend    = $item.backend
                    state      = 'error'
                    text       = $null
                    errorText  = "BLOCK: unexpected failure in the runspace: $($_.Exception.Message)"
                    startedAt  = $null
                    endedAt    = $null
                    durationMs = $null
                    attempts   = 1
                    sidecarPath = $item.sidecarPath
                    adapterReceiptPath = $item.adapterReceiptPath
                    recoveredAfterTimeout = $null
                }
            } finally {
                # [void]: SemaphoreSlim.Release() returns the previous count (int); without the [void]
                # that int would leak into the runspace's output and pollute $collected.
                if ($acquired) { [void]$sem.Release() }
            }
            $result
        } -ThrottleLimit 8
    }
} finally {
    $sem.Dispose()
}
$collected = @($collected)

# Merge the results (by index) into the PENDING records
$byIndex = @{}
foreach ($rec in $records) { $byIndex[[int]$rec.index] = $rec }
foreach ($res in $collected) {
    $rec = $byIndex[[int]$res.index]
    if ($null -eq $rec) { continue }
    $rec.startedAt = $res.startedAt
    $rec.endedAt = $res.endedAt
    $rec.durationMs = $res.durationMs
    $rec.attempts = $res.attempts
    $rec.dispatchAttempted = ([int]$res.attempts -ge 1)

    if ([string]$rec.backend -eq 'claude-code') {
        $rec.sidecarPath = [string]$res.sidecarPath
        $sidecar = $null
        $sidecarReadReason = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$rec.sidecarPath) -and (Test-Path -LiteralPath ([string]$rec.sidecarPath) -PathType Leaf)) {
            $sidecarRead = Read-PanelJsonFileWithDeadline -Path ([string]$rec.sidecarPath) -DeadlineMs 250
            if ($sidecarRead.status -eq 'ok') { $sidecar = $sidecarRead.value }
            else { $sidecarReadReason = "sidecar-$($sidecarRead.status):$($sidecarRead.error)" }
        }
        else {
            $sidecarReadReason = 'sidecar-file-missing'
        }

        $validation = if ($null -eq $sidecar) {
            [pscustomobject]@{ accepted = $false; reason = $sidecarReadReason }
        }
        else {
            Test-ClaudeCodeSidecarShape -Sidecar $sidecar -StdoutText ([string]$res.text)
        }
        $rec.sidecarAccepted = [bool]$validation.accepted
        $rec.sidecarValidationReason = [string]$validation.reason

        if (-not [bool]$validation.accepted) {
            $rec.state = 'error'
            $rec.reason = "claude-code-sidecar-rejected:$($validation.reason)"
            if (-not [string]::IsNullOrWhiteSpace([string]$res.errorText)) {
                $rec.reason = "$($rec.reason); adapterError=$($res.errorText)"
            }
            $rec['__text'] = $null
            $rec['__errorText'] = $rec.reason
            continue
        }

        $projection = Convert-ClaudeCodeSidecarToPanelState -Sidecar $sidecar
        $rec.state = [string]$projection.state
        $rec.technicalStatus = [string](Get-Prop $sidecar 'technicalStatus')
        $rec.resultAccepted = [bool](Get-Prop $sidecar 'resultAccepted')
        $rec.acceptanceRejectionReason = [string](Get-Prop $sidecar 'acceptanceRejectionReason')
        $rec.acceptedFinalTextSha256 = Get-Prop $sidecar 'acceptedFinalTextSha256'
        $rec.acceptedFinalTextBytes = Get-Prop $sidecar 'acceptedFinalTextBytes'
        $rec.promptTransmission = [string](Get-Prop $sidecar 'promptTransmission')
        $rec.processCreated = [bool](Get-Prop $sidecar 'processCreated')
        $rec.quotaCircuitDecision = [string](Get-Prop $sidecar 'quotaCircuitDecision')
        $quotaEvidence = Get-Prop $sidecar 'quotaEvidence'
        $rec.quotaCircuitVariantDecisions = @(Get-Prop $quotaEvidence 'variantDecisions')
        $spawnAttempted = [bool](Get-Prop $sidecar 'spawnAttempted')
        $rec.preDispatchBlocked = (-not $spawnAttempted -and [string]$rec.promptTransmission -eq 'none')
        $reason = [string]$projection.reason
        if ([string]::IsNullOrWhiteSpace($reason)) { $reason = [string]$rec.acceptanceRejectionReason }
        if (-not [string]::IsNullOrWhiteSpace($reason)) { $rec.reason = $reason }
        $rec['__text'] = if ($rec.state -eq 'responded') { $res.text } else { $null }
        $rec['__errorText'] = if ($rec.state -eq 'responded') { $null } else { $rec.reason }
        continue
    }

    if ([string]$rec.backend -eq 'antigravity') {
        $rec.adapterReceiptPath = [string]$res.adapterReceiptPath
        $receipt = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$rec.adapterReceiptPath) -and
            (Test-Path -LiteralPath ([string]$rec.adapterReceiptPath) -PathType Leaf)) {
            try { $receipt = Get-Content -LiteralPath ([string]$rec.adapterReceiptPath) -Raw -Encoding utf8 | ConvertFrom-Json } catch { $receipt = $null }
        }
        if ($null -eq $receipt -or [string](Get-Prop $receipt 'Kind') -ne 'antigravity-public-review-receipt' -or
            [int](Get-Prop $receipt 'SchemaVersion') -ne 1 -or [string](Get-Prop $receipt 'Profile') -ne 'public-review') {
            $rec.state = 'error'
            $rec.reason = 'invalidOutput'
            $rec['__text'] = $null
            $rec['__errorText'] = 'invalidOutput: public-review receipt missing or invalid'
            continue
        }
        $rec.cliVersion = [string](Get-Prop $receipt 'CliVersion')
        $rec.cliVersionMatchesBaseline = [bool](Get-Prop $receipt 'CliVersionMatchesBaseline')
        $rec.cleanupStatus = [string](Get-Prop $receipt 'CleanupStatus')
        $rec.cleanupIssues = @(Get-Prop $receipt 'CleanupIssues')
        $rec.keyringIsolation = [string](Get-Prop $receipt 'KeyringIsolation')
        $receiptReason = [string](Get-Prop $receipt 'Reason')
        if (-not [string]::IsNullOrWhiteSpace($receiptReason)) {
            # PRECEDENCE: state classification by specific sentinel (quota/timeout)
            # wins over the receipt's generic reason when they diverge. With the Antigravity
            # public-review adapter classifying typed quota (Reason=quota), state and reason align and
            # the field stays clean (`quota`). When it still diverges (e.g. leftover timeout from the
            # adapter vs. state=quota from the dispatcher via the BLOCK text — dispatcher more
            # permissive, `quota` without \b), the `quota; adapterReason=...` composition preserves
            # both readings instead of the dispatcher choosing which truth to discard.
            if ($res.state -in @('quota', 'timeout') -and $receiptReason -ne [string]$res.state) {
                $rec.reason = ('{0}; adapterReason={1}' -f $res.state, $receiptReason)
            } else {
                $rec.reason = $receiptReason
            }
        }
    }

    $rec.state = $res.state
    $rec['__text'] = $res.text
    $rec['__errorText'] = $res.errorText
    if ($null -ne (Get-Prop $res 'recoveredAfterTimeout')) {
        $rec.recoveredAfterTimeout = [bool](Get-Prop $res 'recoveredAfterTimeout')
    }
    if ([string]::IsNullOrWhiteSpace([string]$rec.reason) -and -not [string]::IsNullOrWhiteSpace([string]$res.errorText)) {
        $rec.reason = [string]$res.errorText
    }
}

# --------------------------------------------------------------------------------------------
# ORDERED FALLBACK (second pass): the primary failed with an activatable state, so each
# fallback goes through the same gate/adapter via a recursive call without inheriting authorization.
# Not-attempted states never count toward diversity.
# --------------------------------------------------------------------------------------------
$activateFallbackOn = @('quota', 'timeout', 'error', 'unavailable')
$skipPolicyStates = @('gateAsk', 'gateDeny')
$originalRecords = @($records)
foreach ($rec in $originalRecords) {
    # Native leak: the effective source is suppressedFallbackChain (fallbackChain already empty)
    if ([string]$rec.reason -eq 'orchestrator-native-leaked-to-dispatch') {
        $suppressed = @($rec.suppressedFallbackChain)
        if ($suppressed.Count -gt 0) {
            Add-SkippedFallbackRecords -Records $records -FallbackItems $suppressed -FallbackOf ([string]$rec.targetModelKey) `
                -State 'skippedByPolicy' -Reason 'fallback not attempted because the native primary leaked into the dispatcher' `
                -BaseRank ([int]$rec.rank) -FallbackSuppressedReason 'primary-native-leaked' -EntryIndex ([int]$rec.entryIndex)
        }
        continue
    }
    $fallbackItems = @($rec.fallbackChain)
    if ($fallbackItems.Count -eq 0) { continue }
    if ($rec.state -eq 'responded') {
        Add-SkippedFallbackRecords -Records $records -FallbackItems $fallbackItems -FallbackOf ([string]$rec.targetModelKey) `
            -State 'skippedAfterSuccess' -Reason 'fallback not attempted because the primary responded' -BaseRank ([int]$rec.rank) -EntryIndex ([int]$rec.entryIndex)
        continue
    }
    if ([string]$rec.state -eq 'error' -and [int]$rec.attempts -eq 0 -and [string]$rec.reason -like 'BLOCK:*') {
        Add-SkippedFallbackRecords -Records $records -FallbackItems $fallbackItems -FallbackOf ([string]$rec.targetModelKey) `
            -State 'skippedByPolicy' -Reason "fallback not attempted due to a pre-dispatch validation error: $($rec.reason)" -BaseRank ([int]$rec.rank) -EntryIndex ([int]$rec.entryIndex)
        continue
    }
    if ([bool]$rec.preDispatchBlocked) {
        $rec.fallbackSuppressedReason = 'pre-dispatch-block-not-fallback-safe'
        Add-SkippedFallbackRecords -Records $records -FallbackItems $fallbackItems -FallbackOf ([string]$rec.targetModelKey) `
            -State 'skippedByPolicy' -Reason "fallback not attempted because the primary was blocked before sending the prompt: $($rec.reason)" `
            -BaseRank ([int]$rec.rank) -FallbackSuppressedReason ([string]$rec.fallbackSuppressedReason) -EntryIndex ([int]$rec.entryIndex)
        continue
    }
    if ($skipPolicyStates -contains [string]$rec.state) {
        Add-SkippedFallbackRecords -Records $records -FallbackItems $fallbackItems -FallbackOf ([string]$rec.targetModelKey) `
            -State 'skippedByPolicy' -Reason "fallback not attempted because the primary ended in $($rec.state)" -BaseRank ([int]$rec.rank) -EntryIndex ([int]$rec.entryIndex)
        continue
    }
    if ($activateFallbackOn -notcontains [string]$rec.state) {
        Add-SkippedFallbackRecords -Records $records -FallbackItems $fallbackItems -FallbackOf ([string]$rec.targetModelKey) `
            -State 'notAttempted' -Reason "fallback not reached; primary state=$($rec.state)" -BaseRank ([int]$rec.rank) -EntryIndex ([int]$rec.entryIndex)
        continue
    }

    $fallbackSucceeded = $false
    for ($fbIdx = 0; $fbIdx -lt $fallbackItems.Count; $fbIdx++) {
        $fb = $fallbackItems[$fbIdx]
        if ($fallbackSucceeded) {
            Add-SkippedFallbackRecords -Records $records -FallbackItems @($fb) -FallbackOf ([string]$rec.targetModelKey) `
                -State 'skippedAfterSuccess' -Reason 'fallback not attempted because an earlier attempt in the chain responded' -BaseRank ([int]$rec.rank) -EntryIndex ([int]$rec.entryIndex)
            continue
        }

        $fbJsonPath = Join-Path $ledgerDir ("fallback-$($rec.index)-$fbIdx.reviewers.json")
        $fbClean = [pscustomobject]@{
            backend        = [string](Get-Prop $fb 'backend')
            targetModelKey = [string](Get-Prop $fb 'targetModelKey')
            invokeArgs     = (Get-Prop $fb 'invokeArgs')
            family         = (Get-Prop $fb 'family')
            rank           = [int]$rec.rank
        }
        @($fbClean) | ConvertTo-Json -Depth 10 -AsArray | Set-Content -LiteralPath $fbJsonPath -Encoding utf8
        $fbArgs = @{
            ManuscriptPath     = $manuscriptFull
            ReviewersJson      = $fbJsonPath
            PayloadSensitivity = $PayloadSensitivity
            RoundId            = "$RoundId-fb-$($rec.index)-$fbIdx"
            TempDir            = $tempRoot
            OllamaConcurrency  = $OllamaConcurrency
        }
        if ($Cd) { $fbArgs['Cd'] = $Cd }
        if ($KbWorkspaceRoot) { $fbArgs['KbWorkspaceRoot'] = $KbWorkspaceRoot }
        if ($PolicyPath) { $fbArgs['PolicyPath'] = $PolicyPath }
        if ($OpenCodeConfigPath) { $fbArgs['OpenCodeConfigPath'] = $OpenCodeConfigPath }
        if ($CodexConfigPath) { $fbArgs['CodexConfigPath'] = $CodexConfigPath }
        if ($BackendExeMap) { $fbArgs['BackendExeMap'] = $BackendExeMap }
        if ($ClaudeCircuitStateRoot) { $fbArgs['ClaudeCircuitStateRoot'] = $ClaudeCircuitStateRoot }

        $fbRecord = $null
        try {
            $fbOutPath = Join-Path $ledgerDir ("fallback-$($rec.index)-$fbIdx.stdout.json")
            $fbErrPath = Join-Path $ledgerDir ("fallback-$($rec.index)-$fbIdx.stderr.txt")
            $argList = @(
                '-NoProfile', '-File', $PSCommandPath,
                '-ManuscriptPath', $fbArgs.ManuscriptPath,
                '-ReviewersJson', $fbArgs.ReviewersJson,
                '-PayloadSensitivity', $fbArgs.PayloadSensitivity,
                '-RoundId', $fbArgs.RoundId,
                '-TempDir', $fbArgs.TempDir,
                '-OllamaConcurrency', ([string]$fbArgs.OllamaConcurrency)
            )
            foreach ($optionalKey in @('Cd', 'KbWorkspaceRoot', 'PolicyPath', 'OpenCodeConfigPath', 'CodexConfigPath', 'BackendExeMap', 'ClaudeCircuitStateRoot')) {
                if ($fbArgs.ContainsKey($optionalKey)) { $argList += @("-$optionalKey", [string]$fbArgs[$optionalKey]) }
            }
            $p = Start-Process -FilePath (Get-CurrentPowerShellExecutable) -ArgumentList $argList -NoNewWindow -PassThru `
                -RedirectStandardOutput $fbOutPath -RedirectStandardError $fbErrPath
            $fallbackDispatcherTimeoutMs = Get-FallbackDispatcherTimeoutMs -Backend ([string]$fbClean.backend) -InvokeArgs $fbClean.invokeArgs
            $exited = $p.WaitForExit($fallbackDispatcherTimeoutMs)
            if (-not $exited) {
                try {
                    $p.Kill($true)
                    $p.WaitForExit()
                } catch { }
                throw "fallback dispatcher timeout exceeded ${fallbackDispatcherTimeoutMs}ms; process terminated"
            }
            $fbStdout = ''
            if (Test-Path -LiteralPath $fbOutPath -PathType Leaf) {
                $fbStdout = Get-Content -LiteralPath $fbOutPath -Raw -Encoding utf8
            }
            if ($p.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($fbStdout)) {
                throw "fallback dispatcher exit=$($p.ExitCode)"
            }
            $fbSummary = ($fbStdout.Trim() -split "`r?`n" | Select-Object -Last 1) | ConvertFrom-Json
            $fbRecord = @($fbSummary.reviewers)[0]
        } catch {
            $fallbackState = 'error'
            if ([string]$_.Exception.Message -match 'timeout|exceeded') { $fallbackState = 'timeout' }
            elseif (Test-QuotaFailureMessage -Message ([string]$_.Exception.Message)) { $fallbackState = 'quota' }
            elseif (Test-UnavailableFailureMessage -Message ([string]$_.Exception.Message)) { $fallbackState = 'unavailable' }
            $fbRecord = [pscustomobject]@{
                backend        = [string](Get-Prop $fb 'backend')
                targetModelKey = [string](Get-Prop $fb 'targetModelKey')
                family         = (Get-Prop $fb 'family')
                state          = $fallbackState
                reason         = "fallback dispatcher failed: $($_.Exception.Message)"
                attempts       = 0
            }
        }
        $newIdx = $records.Count
        $fbState = [string](Get-Prop $fbRecord 'state')
        $counts = ($fbState -eq 'responded')
        $records.Add([ordered]@{
                index              = $newIdx
                ledgerIndex        = $script:LedgerSeq++
                entryIndex         = [int]$rec.entryIndex
                suppressedFallbackChain = @()
                dispatchChannel    = 'cli'
                backend            = [string](Get-Prop $fbRecord 'backend')
                family             = [string](Get-Prop $fbRecord 'family')
                targetModelKey     = [string](Get-Prop $fbRecord 'targetModelKey')
                effectiveModel     = [string](Get-Prop $fbRecord 'effectiveModel')
                gateVerdict        = [string](Get-Prop $fbRecord 'gateVerdict')
                state              = $fbState
                verdictPath        = [string](Get-Prop $fbRecord 'verdictPath')
                errorPath          = [string](Get-Prop $fbRecord 'errorPath')
                statePath          = [string](Get-Prop $fbRecord 'statePath')
                startedAt          = [string](Get-Prop $fbRecord 'startedAt')
                endedAt            = [string](Get-Prop $fbRecord 'endedAt')
                durationMs         = Get-Prop $fbRecord 'durationMs'
                attempts           = [int](Get-Prop $fbRecord 'attempts')
                reason             = [string](Get-Prop $fbRecord 'reason')
                droppedArgs        = @(Get-Prop $fbRecord 'droppedArgs')
                securityBlockedArgs = @(Get-Prop $fbRecord 'securityBlockedArgs')
                attemptRole        = 'fallback'
                fallbackOf         = [string]$rec.targetModelKey
                fallbackIndex      = $fbIdx
                activationReason   = [string]$rec.state
                countsForDiversity = $counts
                rank               = [int]$rec.rank
                fallbackChain      = @()
                dispatchAttempted  = [bool](Get-Prop $fbRecord 'dispatchAttempted')
                preDispatchBlocked = [bool](Get-Prop $fbRecord 'preDispatchBlocked')
                processCreated     = Get-Prop $fbRecord 'processCreated'
                sidecarPath        = [string](Get-Prop $fbRecord 'sidecarPath')
                sidecarAccepted    = Get-Prop $fbRecord 'sidecarAccepted'
                sidecarValidationReason = [string](Get-Prop $fbRecord 'sidecarValidationReason')
                technicalStatus    = [string](Get-Prop $fbRecord 'technicalStatus')
                resultAccepted     = Get-Prop $fbRecord 'resultAccepted'
                acceptanceRejectionReason = [string](Get-Prop $fbRecord 'acceptanceRejectionReason')
                acceptedFinalTextSha256 = Get-Prop $fbRecord 'acceptedFinalTextSha256'
                acceptedFinalTextBytes = Get-Prop $fbRecord 'acceptedFinalTextBytes'
                promptTransmission = [string](Get-Prop $fbRecord 'promptTransmission')
                quotaCircuitDecision = [string](Get-Prop $fbRecord 'quotaCircuitDecision')
                quotaCircuitVariantDecisions = @(Get-Prop $fbRecord 'quotaCircuitVariantDecisions')
                fallbackSuppressedReason = [string](Get-Prop $fbRecord 'fallbackSuppressedReason')
            })
        if ($fbState -eq 'responded') { $fallbackSucceeded = $true }
    }
}

foreach ($rec in $records) {
    if ($rec.state -eq 'responded') { $rec.countsForDiversity = $true }
    if ($rec.state -in @('skippedByPolicy', 'skippedAfterSuccess', 'notAttempted')) { $rec.countsForDiversity = $false }
}

# --------------------------------------------------------------------------------------------
# LEDGER + SUMMARY
# --------------------------------------------------------------------------------------------

$reviewerFiles = [System.Collections.Generic.List[object]]::new()
foreach ($rec in $records) {
    $nn = '{0:D2}' -f [int]$rec.index
    $famSlug = if ([string]::IsNullOrWhiteSpace([string]$rec.family)) { 'na' } else { Get-Slug ([string]$rec.family) }
    $keySlug = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$rec.targetModelKey)) { $keySlug = Get-Slug ([string]$rec.targetModelKey) }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$rec.effectiveModel)) { $keySlug = Get-Slug ([string]$rec.effectiveModel) }
    else { $keySlug = 'na' }
    $baseName = "$nn-$famSlug-$keySlug"

    $text = $null; $errText = $null
    if ($rec.Contains('__text')) { $text = [string]$rec['__text'] }
    if ($rec.Contains('__errorText')) { $errText = [string]$rec['__errorText'] }

    switch ($rec.state) {
        'responded' {
            if ([string]::IsNullOrWhiteSpace([string]$rec.verdictPath)) {
                $path = Join-Path $ledgerDir "$baseName.verdict.txt"
                Set-Content -LiteralPath $path -Value ([string]$text) -Encoding utf8
                $rec.verdictPath = $path
            }
        }
        { $_ -in @('error', 'timeout') } {
            if ([string]::IsNullOrWhiteSpace([string]$rec.errorPath)) {
                $path = Join-Path $ledgerDir "$baseName.error.txt"
                $content = if ($errText) { $errText } else { [string]$rec.reason }
                Set-Content -LiteralPath $path -Value ([string]$content) -Encoding utf8
                $rec.errorPath = $path
            }
        }
            { $_ -in @('gateAsk', 'gateDeny', 'quota', 'unavailable', 'skippedByPolicy', 'skippedAfterSuccess', 'notAttempted') } {
            if ([string]::IsNullOrWhiteSpace([string]$rec.statePath)) {
                $path = Join-Path $ledgerDir "$baseName.state.txt"
                $content = if ($errText) { $errText } else { [string]$rec.reason }
                Set-Content -LiteralPath $path -Value ([string]$content) -Encoding utf8
                $rec.statePath = $path
            }
        }
    }
    $reviewerFiles.Add([pscustomobject]@{
        index = [int]$rec.index
        path  = @($rec.verdictPath, $rec.errorPath, $rec.statePath | Where-Object { $_ }) | Select-Object -First 1
    })
    # internal fields outside the contract
    if ($rec.Contains('__text')) { $rec.Remove('__text') }
    if ($rec.Contains('__errorText')) { $rec.Remove('__errorText') }
}

# concurrencySaturationWarning: 2+ ollama-cloud/* in error in this batch (no automatic redispatch - single-flight deferred)
$ollamaErrors = @($records | Where-Object { $_.family -eq 'ollama-cloud' -and $_.state -eq 'error' }).Count
$concurrencySaturationWarning = $null
if ($ollamaErrors -ge 2) {
    $concurrencySaturationWarning = "concurrencySaturationWarning: $ollamaErrors ollama-cloud/* reviewers ended in error in this batch; possible concurrency saturation. No automatic re-dispatch (single-flight deferred) - the orchestrator may only re-dispatch in isolation with an explicit human decision."
}

# Counts
$dispatched = @($records | Where-Object { [int]$_.attempts -ge 1 }).Count
$respondedCount = @($records | Where-Object { $_.state -eq 'responded' }).Count
$errorCount = @($records | Where-Object { $_.state -eq 'error' }).Count
$timeoutCount = @($records | Where-Object { $_.state -eq 'timeout' }).Count
$quotaCount = @($records | Where-Object { $_.state -eq 'quota' }).Count
$unavailableCount = @($records | Where-Object { $_.state -eq 'unavailable' }).Count
$gateAskCount = @($records | Where-Object { $_.state -eq 'gateAsk' }).Count
$gateDenyCount = @($records | Where-Object { $_.state -eq 'gateDeny' }).Count
$reviewersDispatchAttempted = @($records | Where-Object { $_.dispatchAttempted -eq $true }).Count
$reviewersProcessCreated = @($records | Where-Object { $_.processCreated -eq $true }).Count
$processCreatedUnknownCount = @($records | Where-Object { $_.dispatchAttempted -eq $true -and $null -eq $_.processCreated }).Count
$preDispatchBlockedCount = @($records | Where-Object { $_.preDispatchBlocked -eq $true }).Count
$sidecarAcceptedCount = @($records | Where-Object { $_.sidecarAccepted -eq $true }).Count
$sidecarRejectedCount = @($records | Where-Object { $_.sidecarAccepted -eq $false }).Count
$fallbackSuppressedCount = @($records | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.fallbackSuppressedReason) }).Count

$reviewerObjs = @($records | ForEach-Object { [pscustomobject]$_ })

$kbWorkspaceRootOut = $null; if (-not [string]::IsNullOrWhiteSpace($KbWorkspaceRoot)) { $kbWorkspaceRootOut = $KbWorkspaceRoot }
$policyPathOut = $null; if (-not [string]::IsNullOrWhiteSpace($PolicyPath)) { $policyPathOut = $PolicyPath }

$summary = [ordered]@{
    Kind                         = 'mimir-panel-dispatch-result'
    SchemaVersion                = 3
    success                      = $true
    roundStarted                 = $true
    dispatchStarted              = $true
    reviewersDispatched          = $dispatched
    reviewersDispatchAttempted   = $reviewersDispatchAttempted
    reviewersProcessCreated      = $reviewersProcessCreated
    processCreatedUnknownCount   = $processCreatedUnknownCount
    preDispatchBlockedCount      = $preDispatchBlockedCount
    sidecarAcceptedCount         = $sidecarAcceptedCount
    sidecarRejectedCount         = $sidecarRejectedCount
    fallbackSuppressedCount      = $fallbackSuppressedCount
    roundId                      = $RoundId
    payloadSensitivity           = $PayloadSensitivity
    kbWorkspaceRoot              = $kbWorkspaceRootOut
    policyPath                   = $policyPathOut
    manuscriptPath               = $manuscriptFull
    ollamaConcurrency            = $OllamaConcurrency
    reviewers                    = @($reviewerObjs)
    dispatched                   = $dispatched
    respondedCount               = $respondedCount
    errorCount                   = $errorCount
    timeoutCount                 = $timeoutCount
    quotaCount                   = $quotaCount
    unavailableCount             = $unavailableCount
    gateAsk                      = $gateAskCount
    gateDeny                     = $gateDenyCount
    ollamaQuotaWarning           = $ollamaQuotaWarning
    concurrencySaturationWarning = $concurrencySaturationWarning
    preparationError             = $null
}

$summaryPath = Join-Path $ledgerDir 'panel-summary.json'
$summaryJson = $summary | ConvertTo-Json -Compress -Depth 8
Set-Content -LiteralPath $summaryPath -Value $summaryJson -Encoding utf8

$manifest = [ordered]@{
    Kind          = 'mimir-panel-dispatch-manifest'
    SchemaVersion = 1
    roundId       = $RoundId
    tempDir       = $tempRoot
    summaryPath   = $summaryPath
    reviewerFiles = @($reviewerFiles)
}
$manifestPath = Join-Path $ledgerDir 'manifest.json'
($manifest | ConvertTo-Json -Compress -Depth 6) | Set-Content -LiteralPath $manifestPath -Encoding utf8

# Warnings -> stderr (never stdout)
if ($ollamaQuotaWarning) { [Console]::Error.WriteLine($ollamaQuotaWarning) }
if ($concurrencySaturationWarning) { [Console]::Error.WriteLine($concurrencySaturationWarning) }

# stdout = ONLY line (the panel-summary.json)
[Console]::Out.WriteLine($summaryJson)
