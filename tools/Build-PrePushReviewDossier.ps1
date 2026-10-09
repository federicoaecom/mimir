#requires -Version 7.4
<#
.SYNOPSIS
    Builds the pre-push dossier for the semantic-only reviewer (RAW git + mechanical diagnostic).

.DESCRIPTION
    ORCHESTRATOR artifact (whoever has git). Builds a single dossier and EMITS it on
    stdout; inline delivery in the prompt to the semantic-only reviewer is the
    ORCHESTRATOR's decision (stdin on stdin-dossier-capable ones like opencode/Claude
    Code; argv on argv-limited Copilot/Gemini/Antigravity, if it fits — see 13/14). The
    semantic-only reviewer does not run 13's mechanical step (denies bash/shell). The
    dossier has two labeled sections:

      - SECTION A - RAW git (fact): rev-parse HEAD, log origin/main..HEAD,
        diff origin/main..HEAD, status --porcelain.
      - SECTION B - mechanical diagnostic (NOT truth): the entire container from
        Invoke-PrePushMechanicalChecks.ps1 -AsJson, under a single literal header,
        labeled "candidates to verify, NOT truth".

    At the end, two isolated sentinel lines:
        HEAD: <hex40>
        END_DOSSIER sha256=<hex64>
    The sha256 is computed over the UTF-8 bytes (no BOM) of the BODY (Section A +
    Section B), EXCLUDING the two sentinels, after normalizing line endings to LF. It
    is anti-truncation (the reviewer echoes the sentinels), not anti-wrong-dossier
    (the git-capable invariant from 14/15 covers that). See docs/process/13, 14
    and 15.

    The builder does NOT run git fetch (fetch belongs to the caller, 13:37); it
    receives -FetchStatus and derives remoteFreshness. The mechanical check is the
    SOURCE OF TRUTH for commitsBehind/pushReadiness; the builder REFERENCES it (reads
    from -AsJson), it does not keep a second tracker.

.PARAMETER RootPath
    Repository root. Default: the parent of tools/.

.PARAMETER BaseRef
    Base ref of the range (same as the mechanical check). Default: origin/main.

.PARAMETER FetchStatus
    Fetch state done (or not) by the caller before building the dossier:
    fetched | not-fetched | fetch-failed. The builder does not run fetch. not-fetched /
    fetch-failed => remoteFreshness=stale (local diagnostic). Default: not-fetched.

.PARAMETER MechanicalScriptPath
    Test seam (internal use). Path to the mechanical script; default = the
    Invoke-PrePushMechanicalChecks.ps1 next to this one. The self-test injects a fake
    mechanical check (non-JSON output) to exercise the degraded mode. Do not use in
    production.

.PARAMETER AsJson
    Emits structured metadata (for the orchestrator to decide dispatch) + the full
    dossier text in the dossierText field. Without -AsJson, emits only the dossier
    text on stdout (the orchestrator delivers it inline in the prompt; transport via
    adapter — see 13/14).
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,

    [string]$BaseRef = 'origin/main',

    [ValidateSet('fetched', 'not-fetched', 'fetch-failed')]
    [string]$FetchStatus = 'not-fetched',

    # Test seam: path to the mechanical script. Default = Invoke-PrePushMechanicalChecks.ps1
    # next to this one. The self-test injects a fake mechanical check to exercise the degraded mode.
    [string]$MechanicalScriptPath,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The dossier carries accents (section headers) and is captured via stdout (the
# reviewer's stdin). Forcing UTF-8 without BOM on output avoids code-page-dependent corruption.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/mimir-lite/scripts') 'Utf8NoBomEncodingSupport.ps1')

$SectionBHeader = '=== SECTION B — ORCHESTRATOR MECHANICAL DIAGNOSTIC (candidates to verify, NOT truth) ==='

function Invoke-DossierGit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git -C $RepositoryRoot @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = @()
    if ($null -ne $output) {
        $lines = @($output | ForEach-Object { $_.ToString() })
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines    = $lines
        Text     = ($lines -join "`n")
    }
}

function ConvertTo-LfText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-BodySha256Hex {
    param([Parameter(Mandatory = $true)][string]$Body)

    $encoding = Get-Utf8NoBomEncoding
    $bytes = $encoding.GetBytes($Body)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return (([System.BitConverter]::ToString($hashBytes)) -replace '-', '').ToLowerInvariant()
}

function New-NotReadyResult {
    param(
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$ResolvedRoot = ''
    )

    return [ordered]@{
        dossierReady               = $false
        notReadyReason             = $Reason
        mechanicalStatus           = 'not-run'
        pushReadiness              = 'unknown'
        intervalDiffDiagnosticOnly = $false
        commitsBehind              = $null
        fetchStatus                = $FetchStatus
        remoteFreshness            = 'unknown'
        workingTreeDirty           = $false
        dirtyPaths                 = @()
        head                       = $null
        baseRef                    = $BaseRef
        rootPath                   = $ResolvedRoot
        sizeChars                  = 0
        bodySha256                 = $null
        dossierText                = ''
    }
}

# --- Resolving git / origin (dossierReady=false ONLY without raw facts, 4c) ---
$resolvedRoot = ''
try {
    $resolvedStart = (Resolve-Path -LiteralPath $RootPath).Path
    $topLevel = Invoke-DossierGit -RepositoryRoot $resolvedStart -Arguments @('rev-parse', '--show-toplevel')
    if ($topLevel.ExitCode -ne 0 -or $topLevel.Lines.Count -eq 0) {
        $result = New-NotReadyResult -Reason 'git-repo-unresolved'
        if ($AsJson) { [pscustomobject]$result | ConvertTo-Json -Depth 6 } else { Write-Output '' }
        exit 0
    }
    $resolvedRoot = $topLevel.Lines[0].Trim()
} catch {
    $result = New-NotReadyResult -Reason 'git-repo-unresolved'
    if ($AsJson) { [pscustomobject]$result | ConvertTo-Json -Depth 6 } else { Write-Output '' }
    exit 0
}

$baseRefCheck = Invoke-DossierGit -RepositoryRoot $resolvedRoot -Arguments @('rev-parse', '--verify', $BaseRef)
if ($baseRefCheck.ExitCode -ne 0) {
    $result = New-NotReadyResult -Reason 'baseRef-missing' -ResolvedRoot $resolvedRoot
    if ($AsJson) { [pscustomobject]$result | ConvertTo-Json -Depth 6 } else { Write-Output '' }
    exit 0
}

# --- SECTION A - RAW git (fact) ---
# Unborn HEAD (repo with no commits) or unresolvable: rev-parse HEAD fails (or does not
# return a 40-hex hash). Without HEAD there are no raw facts => dossierReady=false, instead
# of letting $headResult.Lines[0] throw under StrictMode. (4c: without Section A, dossier not ready.)
$headResult = Invoke-DossierGit -RepositoryRoot $resolvedRoot -Arguments @('rev-parse', 'HEAD')
if ($headResult.ExitCode -ne 0 -or $headResult.Lines.Count -eq 0 -or $headResult.Lines[0].Trim() -notmatch '^[0-9a-f]{40}$') {
    $result = New-NotReadyResult -Reason 'head-unresolved' -ResolvedRoot $resolvedRoot
    if ($AsJson) { [pscustomobject]$result | ConvertTo-Json -Depth 6 } else { Write-Output '' }
    exit 0
}
$head = $headResult.Lines[0].Trim()

$range = "$BaseRef..HEAD"
$logResult = Invoke-DossierGit -RepositoryRoot $resolvedRoot -Arguments @('log', $range, '--oneline')
$diffResult = Invoke-DossierGit -RepositoryRoot $resolvedRoot -Arguments @('diff', $range)
$statusResult = Invoke-DossierGit -RepositoryRoot $resolvedRoot -Arguments @('status', '--porcelain')

# Dirty working-tree paths (4h): non-empty status --porcelain => workingTreeDirty.
$dirtyPaths = [System.Collections.Generic.List[string]]::new()
foreach ($line in @($statusResult.Lines)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -match ' -> ') {
        $path = @($path -split ' -> ', 2)[1].Trim()
    }
    [void]$dirtyPaths.Add($path)
}
$dirtyPathsAll = @($dirtyPaths)
$workingTreeDirty = ($dirtyPathsAll.Count -gt 0)

$sectionA = @(
    '=== SECTION A — RAW GIT (FACT) ==='
    ''
    '--- git rev-parse HEAD ---'
    $head
    ''
    ("--- git log {0} --oneline ---" -f $range)
    $logResult.Text
    ''
    ("--- git diff {0} ---" -f $range)
    $diffResult.Text
    ''
    '--- git status --porcelain ---'
    $statusResult.Text
) -join "`n"

# --- SECTION B - mechanical diagnostic (NOT truth): entire -AsJson container ---
$mechanicalScript = if ([string]::IsNullOrWhiteSpace($MechanicalScriptPath)) {
    Join-Path $PSScriptRoot 'Invoke-PrePushMechanicalChecks.ps1'
} else {
    $MechanicalScriptPath
}
if (-not (Test-Path -LiteralPath $mechanicalScript -PathType Leaf)) {
    throw "Mechanical script not found: $mechanicalScript"
}

# 4c: the mechanical check is a diagnostic (NOT truth). If it fails/throws, the dossier
# stays READY (mechanicalStatus=failed); Section B carries the raw error text.
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$mechanicalExitCode = 0
try {
    $mechanicalOutput = & $mechanicalScript -RootPath $resolvedRoot -BaseRef $BaseRef -AsJson 2>&1
    $mechanicalExitCode = $LASTEXITCODE
} catch {
    $mechanicalOutput = @("Invoke-PrePushMechanicalChecks.ps1 threw an exception (caught by the builder): $($_.Exception.Message)")
    $mechanicalExitCode = 1
}
$ErrorActionPreference = $previousErrorAction

$mechanicalJsonText = (@($mechanicalOutput | ForEach-Object { if ($null -ne $_) { $_.ToString() } }) -join "`n")

$mechanicalObject = $null
$mechanicalParseOk = $false
if (-not [string]::IsNullOrWhiteSpace($mechanicalJsonText)) {
    try {
        $mechanicalObject = $mechanicalJsonText | ConvertFrom-Json
        $mechanicalParseOk = $true
    } catch {
        $mechanicalParseOk = $false
    }
}

# 4c: broken parse OR mechanical exit != 0 => mechanicalStatus=failed (dossier stays ready).
$mechanicalStatus = if ($mechanicalExitCode -eq 0 -and $mechanicalParseOk) { 'passed' } else { 'failed' }

# 4b: the mechanical check is the source of truth for commitsBehind/pushReadiness; the builder REFERENCES it.
# Degraded mode (a'): if the mechanical JSON does not parse (mechanical check threw), the builder
# reasserts ONLY the RAW FACT commitsBehind via git; pushReadiness/intervalDiffDiagnosticOnly are
# engine POLICY and stay UNDETERMINED ('unknown'/$null), consistent with mechanicalStatus=failed --
# they are not derived through a parallel path (avoids a fabricated push verdict under failure).
$commitsBehind = $null
$pushReadiness = 'unknown'
$intervalDiffDiagnosticOnly = $null
$mechanicalFailures = @()
if ($mechanicalParseOk) {
    try { $commitsBehind = [int]$mechanicalObject.git.commitsBehind } catch { $commitsBehind = $null }
    try { $pushReadiness = [string]$mechanicalObject.pushReadiness } catch { $pushReadiness = 'unknown' }
    try { $intervalDiffDiagnosticOnly = [bool]$mechanicalObject.intervalDiffDiagnosticOnly } catch { $intervalDiffDiagnosticOnly = $null }
    try { $mechanicalFailures = @($mechanicalObject.mechanicalFailures) } catch { $mechanicalFailures = @() }
}
if ($null -eq $commitsBehind) {
    $behindResult = Invoke-DossierGit -RepositoryRoot $resolvedRoot -Arguments @('rev-list', '--count', "HEAD..$BaseRef")
    if ($behindResult.ExitCode -eq 0 -and $behindResult.Lines.Count -gt 0) {
        $commitsBehind = [int]$behindResult.Lines[0]
    }
}

$sectionB = @(
    $SectionBHeader
    ''
    $mechanicalJsonText
) -join "`n"

# --- Body (Section A + Section B), LF-normalized, no trailing newline; basis for the hash (4e) ---
$body = ConvertTo-LfText -Text (($sectionA, '', $sectionB) -join "`n")
$body = $body.TrimEnd("`n")
$bodySha256 = Get-BodySha256Hex -Body $body

# --- Isolated sentinels ---
$dossierText = @(
    $body
    ("HEAD: {0}" -f $head)
    ("END_DOSSIER sha256={0}" -f $bodySha256)
) -join "`n"

# 4b: remoteFreshness derived from the fetch reported by the caller (builder does not run fetch).
$remoteFreshness = if ($FetchStatus -eq 'fetched') { 'fresh' } else { 'stale' }

$result = [ordered]@{
    dossierReady               = $true
    notReadyReason             = $null
    mechanicalStatus           = $mechanicalStatus
    mechanicalExitCode         = $mechanicalExitCode
    pushReadiness              = $pushReadiness
    intervalDiffDiagnosticOnly = $intervalDiffDiagnosticOnly
    commitsBehind              = $commitsBehind
    mechanicalFailures         = @($mechanicalFailures)
    fetchStatus                = $FetchStatus
    remoteFreshness            = $remoteFreshness
    workingTreeDirty           = $workingTreeDirty
    dirtyPaths                 = @($dirtyPathsAll)
    head                       = $head
    baseRef                    = $BaseRef
    range                      = $range
    rootPath                   = $resolvedRoot
    sizeChars                  = $dossierText.Length
    bodySha256                 = $bodySha256
    dossierText                = $dossierText
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    Write-Output $dossierText
}

exit 0
