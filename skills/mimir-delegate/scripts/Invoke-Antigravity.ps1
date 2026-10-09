#requires -Version 7.4
<#
.SYNOPSIS
    Calls the Antigravity CLI (agy) in the fixed public-review profile and returns the final response.
.DESCRIPTION
    antigravity backend of the mimir-delegate skill. The public-review profile creates a
    disposable scratch cwd, redirects the environment only in the child process, and uses
    exclusively `agy -p`, `--mode plan`, `--output-format json`, `--print-timeout`, and `--model`.

    The profile is operational hygiene, not a security sandbox: keyring credentials remain
    global. CONFIDENTIALITY remains the dispatcher/gate's responsibility; this adapter does not
    receive or classify the payload's sensitivity.
.PARAMETER Message
    Prompt to send to the Antigravity CLI. Exclusive with -MessagePath.
.PARAMETER MessagePath
    Path to a UTF-8 file. Exclusive with -Message. The adapter remains argument-based;
    above 30000 characters it blocks without truncating.
.PARAMETER Model
    Model accepted by the Antigravity CLI. Default: gemini-3.6-flash-high.
.PARAMETER Profile
    Fixed profile. Only public-review is accepted.
.PARAMETER Mode
    Fixed mode. Only plan is accepted.
.PARAMETER ReceiptPath
    Optional path for the profile's technical JSON receipt. The dispatcher sets this path;
    reviewers' invokeArgs cannot control it.
.PARAMETER ScratchPath
    TEST ONLY: scratch prepared by the self-test. Normal calls should omit it.
.PARAMETER SimulateCleanupFailure
    TEST ONLY: injects a degraded/failed result to prove cleanup semantics.
.PARAMETER AntigravityExe
    Forces the path of the agy.exe executable.
.PARAMETER TimeoutSec
    Maximum wait time in seconds. Default: 1200.
#>
[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Inline')] [string] $Message,
    [Parameter(Mandatory, ParameterSetName = 'FromFile')] [string] $MessagePath,
    [string] $Model = 'gemini-3.6-flash-high',
    [ValidateSet('public-review')] [string] $Profile = 'public-review',
    [ValidateSet('plan')] [string] $Mode = 'plan',
    [string] $ReceiptPath,
    # --- TEST ONLY ---
    [string] $ScratchPath,
    [ValidateSet('none', 'degraded', 'failed')] [string] $SimulateCleanupFailure = 'none',
    [string] $AntigravityExe,
    [ValidateRange(1, 3600)] [int] $TimeoutSec = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

. (Join-Path $PSScriptRoot 'AntigravityCliSupport.ps1')

$ExpectedCliVersion = '1.1.19'
$MaxArgvPromptChars = 30000
$executionReason = $null
$executionError = $null
$responseText = $null
$proc = $null
$scratch = $null
$scratchOwned = $false
$scratchRemoved = $false
$scratchWasEmpty = $false
$workspaceDiagnostics = [ordered]@{
    hasGit = $false
    hasReparsePoint = $false
    insideRepository = $false
    insideKbWorkspace = $false
}
$descendantEnumerationFailed = $false
$observedDescendantIds = [System.Collections.Generic.HashSet[int]]::new()
$aliveDescendantsAfterCleanup = @()
$cleanupIssues = [System.Collections.Generic.List[string]]::new()
$cliVersion = $null
$startedAt = (Get-Date).ToUniversalTime()
$endedAt = $null

function New-PublicReviewException {
    param([string] $Reason, [string] $Detail)
    return [System.InvalidOperationException]::new("BLOCK: Antigravity public-review reason=$Reason; $Detail")
}

function Test-PathIsOrContainsReparsePoint {
    param([string] $Path)
    try {
        $rootItem = Get-Item -LiteralPath $Path -Force
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
        $nested = Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop | Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        } | Select-Object -First 1
        return ($null -ne $nested)
    } catch {
        throw (New-PublicReviewException -Reason 'unsafeWorkspace' -Detail "could not inspect reparse points at '$Path': $($_.Exception.Message)")
    }
}

function Get-WorkspaceAncestorDiagnostics {
    param([string] $Path)
    $repo = $false
    $kb = $false
    $cursor = [System.IO.DirectoryInfo]::new($Path)
    while ($null -ne $cursor) {
        if (Test-Path -LiteralPath (Join-Path $cursor.FullName '.git')) { $repo = $true }
        if ((Test-Path -LiteralPath (Join-Path $cursor.FullName 'KbObjectsXml') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path $cursor.FullName 'KbIntelligence') -PathType Container)) {
            $kb = $true
        }
        $cursor = $cursor.Parent
    }
    return [pscustomobject]@{ insideRepository = $repo; insideKbWorkspace = $kb }
}

function Get-DescendantProcessIds {
    param([int] $RootProcessId)
    if ($IsWindows) {
        $all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId)
    } else {
        # Win32_Process exists only on Windows; elsewhere Get-Process exposes each process's parent.
        # A process that exits during the scan is skipped instead of failing the whole enumeration.
        $all = @(Get-Process -ErrorAction Stop | ForEach-Object {
            try {
                $parent = $_.Parent
                if ($null -ne $parent) { [pscustomobject]@{ ProcessId = $_.Id; ParentProcessId = $parent.Id } }
            } catch { }
        })
    }
    $knownParents = [System.Collections.Generic.HashSet[int]]::new()
    [void]$knownParents.Add($RootProcessId)
    $found = [System.Collections.Generic.HashSet[int]]::new()
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($p in $all) {
            $pidValue = [int]$p.ProcessId
            if ($knownParents.Contains([int]$p.ParentProcessId) -and -not $knownParents.Contains($pidValue)) {
                [void]$knownParents.Add($pidValue)
                [void]$found.Add($pidValue)
                $changed = $true
            }
        }
    }
    return @($found)
}

function Write-PublicReviewReceipt {
    param([System.Collections.IDictionary] $Receipt)
    if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { return }
    $receiptFull = [System.IO.Path]::GetFullPath($ReceiptPath)
    $parent = Split-Path -Parent $receiptFull
    if ($parent) { [void][System.IO.Directory]::CreateDirectory($parent) }
    $tmpReceipt = "$receiptFull.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        $Receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmpReceipt -Encoding utf8NoBOM
        Move-Item -LiteralPath $tmpReceipt -Destination $receiptFull -Force
    } finally {
        Remove-Item -LiteralPath $tmpReceipt -Force -ErrorAction SilentlyContinue
    }
}

$out = New-TemporaryFile
$err = New-TemporaryFile
$req = New-TemporaryFile
$runner = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, '.ps1')

try {
    if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
        if (-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)) {
            throw (New-PublicReviewException -Reason 'invalidOutput' -Detail "-MessagePath not found: $MessagePath")
        }
        $Message = Get-Content -LiteralPath $MessagePath -Raw -Encoding utf8
    }
    if ($Message.Length -gt $MaxArgvPromptChars) {
        throw (New-PublicReviewException -Reason 'inputTooLarge' -Detail "prompt with $($Message.Length) characters exceeds the $MaxArgvPromptChars ceiling; the profile omits it without truncating")
    }

    try {
        $exe = Resolve-AntigravityExe -Override $AntigravityExe
    } catch {
        throw (New-PublicReviewException -Reason 'cliMissing' -Detail $_.Exception.Message)
    }
    try {
        $cliVersion = Get-AntigravityCliVersion -AntigravityExe $exe
    } catch {
        throw (New-PublicReviewException -Reason 'cliMissing' -Detail "could not obtain agy --version: $($_.Exception.Message)")
    }

    if ($ScratchPath) {
        if (-not (Test-Path -LiteralPath $ScratchPath -PathType Container)) {
            throw (New-PublicReviewException -Reason 'unsafeWorkspace' -Detail "test scratch does not exist: $ScratchPath")
        }
        $scratch = (Resolve-Path -LiteralPath $ScratchPath).Path
    } else {
        $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'mimir-agy-public-review'
        [void][System.IO.Directory]::CreateDirectory($scratchRoot)
        $scratch = Join-Path $scratchRoot ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($scratch)
        $scratchOwned = $true
    }

    $itemsBefore = @(Get-ChildItem -LiteralPath $scratch -Force -ErrorAction Stop)
    $scratchWasEmpty = ($itemsBefore.Count -eq 0)
    $workspaceDiagnostics.hasGit = [bool](@(Get-ChildItem -LiteralPath $scratch -Force -Recurse -ErrorAction Stop | Where-Object { $_.Name -eq '.git' }).Count -gt 0)
    $workspaceDiagnostics.hasReparsePoint = Test-PathIsOrContainsReparsePoint -Path $scratch
    $ancestor = Get-WorkspaceAncestorDiagnostics -Path $scratch
    $workspaceDiagnostics.insideRepository = [bool]$ancestor.insideRepository
    $workspaceDiagnostics.insideKbWorkspace = [bool]$ancestor.insideKbWorkspace
    if (-not $scratchWasEmpty -or $workspaceDiagnostics.hasGit -or $workspaceDiagnostics.hasReparsePoint -or
        $workspaceDiagnostics.insideRepository -or $workspaceDiagnostics.insideKbWorkspace) {
        throw (New-PublicReviewException -Reason 'unsafeWorkspace' -Detail "scratch rejected (empty=$scratchWasEmpty git=$($workspaceDiagnostics.hasGit) reparse=$($workspaceDiagnostics.hasReparsePoint) repo=$($workspaceDiagnostics.insideRepository) kb=$($workspaceDiagnostics.insideKbWorkspace))")
    }

    $profileHome = Join-Path $scratch 'profile'
    # One segment per Join-Path: no separator is written into a child folder name.
    $appData = Join-Path (Join-Path $profileHome 'AppData') 'Roaming'
    $localAppData = Join-Path (Join-Path $profileHome 'AppData') 'Local'
    $childTemp = Join-Path $scratch 'temp'
    $xdgConfig = Join-Path $profileHome '.config'
    $xdgData = Join-Path (Join-Path $profileHome '.local') 'share'
    $xdgCache = Join-Path $profileHome '.cache'
    foreach ($dir in @($profileHome, $appData, $localAppData, $childTemp, $xdgConfig, $xdgData, $xdgCache)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }

    $rawModel = $Model.Trim()
    if ($rawModel -like 'antigravity/*') { $rawModel = ($rawModel -split '/', 2)[1].Trim() }
    if ([string]::IsNullOrWhiteSpace($rawModel)) { $rawModel = 'gemini-3.6-flash-high' }

    $request = [ordered]@{
        exe = $exe; prompt = $Message; model = $rawModel; mode = $Mode; timeoutSec = $TimeoutSec
        stdoutPath = $out.FullName; stderrPath = $err.FullName
    }
    $request | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $req.FullName -Encoding utf8NoBOM

    @'
param([Parameter(Mandatory)][string]$RequestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$req = Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8 | ConvertFrom-Json
$agyArgs = @(
    '-p', [string]$req.prompt,
    '--mode', [string]$req.mode,
    '--output-format', 'json',
    '--print-timeout', "$([string]$req.timeoutSec)s",
    '--model', [string]$req.model
)
$null | & ([string]$req.exe) @agyArgs 1> ([string]$req.stdoutPath) 2> ([string]$req.stderrPath)
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $runner -Encoding utf8NoBOM

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'pwsh'
    $psi.ArgumentList.Add('-NoProfile')
    $psi.ArgumentList.Add('-File')
    $psi.ArgumentList.Add($runner)
    $psi.ArgumentList.Add($req.FullName)
    $psi.WorkingDirectory = $scratch
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $redirectedEnvironment = [ordered]@{
        USERPROFILE = $profileHome; HOME = $profileHome; APPDATA = $appData; LOCALAPPDATA = $localAppData
        TEMP = $childTemp; TMP = $childTemp; XDG_CONFIG_HOME = $xdgConfig; XDG_DATA_HOME = $xdgData
        XDG_CACHE_HOME = $xdgCache; ANTIGRAVITY_HOME = (Join-Path $profileHome '.antigravity')
        AGY_HOME = (Join-Path $profileHome '.agy')
    }
    foreach ($entry in $redirectedEnvironment.GetEnumerator()) { $psi.Environment[$entry.Key] = [string]$entry.Value }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    $timedOut = $false
    while (-not $proc.HasExited) {
        try {
            foreach ($id in @(Get-DescendantProcessIds -RootProcessId $proc.Id)) { [void]$observedDescendantIds.Add([int]$id) }
        } catch {
            $descendantEnumerationFailed = $true
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            $timedOut = $true
            # Kill descendants (agy) first and let the runner flush 1>/2> to the
            # temporary files; only then Kill the runner if it is still alive.
            try {
                foreach ($id in @(Get-DescendantProcessIds -RootProcessId $proc.Id)) {
                    try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { }
                }
            } catch { }
            try { [void]$proc.WaitForExit(10000) } catch { }
            if (-not $proc.HasExited) {
                try { $proc.Kill($true) } catch { }
                try { [void]$proc.WaitForExit(10000) } catch { }
            }
            Start-Sleep -Milliseconds 200
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $timedOut) { $proc.WaitForExit() }

    $stdoutText = Get-Content -LiteralPath $out.FullName -Raw -ErrorAction SilentlyContinue
    $stderrText = Get-Content -LiteralPath $err.FullName -Raw -ErrorAction SilentlyContinue
    $raw = Get-AntigravityClassificationRaw -StdoutText $stdoutText -StderrText $stderrText

    if ($timedOut) {
        $resolved = Resolve-AntigravityPublicReviewFailureReason -Raw $raw
        if ($null -ne $resolved) {
            throw (New-PublicReviewException -Reason $resolved.Reason -Detail $resolved.Detail)
        }
        throw (New-PublicReviewException -Reason 'timeout' -Detail "limit of $($TimeoutSec)s reached; process tree was terminated")
    }

    if ($proc.ExitCode -ne 0) {
        $errorField = $null
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            try {
                $errJson = $stdoutText | ConvertFrom-Json
                if ($errJson.PSObject.Properties['error']) {
                    $errorField = Normalize-AntigravityErrorField -ErrorField $errJson.error
                }
            } catch { }
        }
        $resolved = if ($null -ne $errorField) {
            Resolve-AntigravityPublicReviewFailureReason -Raw $raw -ErrorField $errorField
        } else {
            Resolve-AntigravityPublicReviewFailureReason -Raw $raw
        }
        if ($null -ne $resolved) {
            throw (New-PublicReviewException -Reason $resolved.Reason -Detail $resolved.Detail)
        }
        $errMsg = Get-AntigravityErrorMessage -StdoutText $stdoutText -StderrText $stderrText
        if ([string]::IsNullOrWhiteSpace($errMsg)) { $errMsg = "process finished with code $($proc.ExitCode)" }
        throw (New-PublicReviewException -Reason 'processFailure' -Detail $errMsg)
    }
    if ([string]::IsNullOrWhiteSpace($stdoutText)) {
        $resolved = Resolve-AntigravityPublicReviewFailureReason -Raw $raw
        if ($null -ne $resolved) {
            throw (New-PublicReviewException -Reason $resolved.Reason -Detail $resolved.Detail)
        }
        throw (New-PublicReviewException -Reason 'invalidOutput' -Detail 'CLI returned empty stdout')
    }

    try { $jsonResp = $stdoutText | ConvertFrom-Json } catch {
        $resolved = Resolve-AntigravityPublicReviewFailureReason -Raw $raw
        if ($null -ne $resolved) {
            throw (New-PublicReviewException -Reason $resolved.Reason -Detail $resolved.Detail)
        }
        throw (New-PublicReviewException -Reason 'invalidOutput' -Detail 'CLI did not return the required JSON envelope')
    }
    $respStatus = [string]$jsonResp.status
    $responseText = [string]$jsonResp.response
    if ($respStatus -ne 'SUCCESS') {
        $reportedError = $null
        if ($jsonResp.PSObject.Properties['error']) {
            $reportedError = Normalize-AntigravityErrorField -ErrorField $jsonResp.error
        }
        $resolved = if ($null -ne $reportedError) {
            Resolve-AntigravityPublicReviewFailureReason -Raw $raw -ErrorField $reportedError
        } else {
            Resolve-AntigravityPublicReviewFailureReason -Raw $raw
        }
        if ($null -ne $resolved) {
            throw (New-PublicReviewException -Reason $resolved.Reason -Detail $resolved.Detail)
        }
        $detail = if (-not [string]::IsNullOrWhiteSpace($reportedError)) {
            "status '$respStatus': $reportedError"
        } else {
            "status '$respStatus'"
        }
        throw (New-PublicReviewException -Reason 'processFailure' -Detail $detail)
    }
    if ([string]::IsNullOrWhiteSpace($responseText)) {
        throw (New-PublicReviewException -Reason 'invalidOutput' -Detail 'SUCCESS envelope without a usable response')
    }
    $responseText = $responseText.Trim()
} catch {
    $executionError = $_.Exception
    if ($executionError.Message -match 'reason=([A-Za-z]+)') { $executionReason = $Matches[1] }
    elseif (-not $executionReason) { $executionReason = 'processFailure' }
} finally {
    if ($null -ne $proc) {
        try { if (-not $proc.HasExited) { $proc.Kill($true) } } catch { $cleanupIssues.Add("runner-kill:$($_.Exception.Message)") }
        try { $proc.Dispose() } catch { $cleanupIssues.Add("runner-dispose:$($_.Exception.Message)") }
    }

    foreach ($id in @($observedDescendantIds)) {
        $child = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($null -ne $child) {
            try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { $cleanupIssues.Add("descendant-kill-${id}:$($_.Exception.Message)") }
        }
    }
    Start-Sleep -Milliseconds 100
    $aliveDescendantsAfterCleanup = @($observedDescendantIds | Where-Object { $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue) })
    if ($descendantEnumerationFailed) { $cleanupIssues.Add('descendant-enumeration-failed') }
    if ($aliveDescendantsAfterCleanup.Count -gt 0) { $cleanupIssues.Add('descendants-still-alive') }
    if ($SimulateCleanupFailure -eq 'degraded') { $cleanupIssues.Add('simulated-cleanup-degraded') }
    if ($SimulateCleanupFailure -eq 'failed') { $cleanupIssues.Add('simulated-cleanup-failed') }

    if ($scratchOwned -and $scratch) {
        try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction Stop } catch { $cleanupIssues.Add("scratch-remove:$($_.Exception.Message)") }
        $scratchRemoved = -not (Test-Path -LiteralPath $scratch)
        if (-not $scratchRemoved) { $cleanupIssues.Add('scratch-still-present') }
    }
    elseif ($scratch) { $scratchRemoved = $false }

    Remove-Item -LiteralPath $out.FullName, $err.FullName, $req.FullName, $runner -Force -ErrorAction SilentlyContinue
    $endedAt = (Get-Date).ToUniversalTime()
    $cleanupStatus = if ($aliveDescendantsAfterCleanup.Count -gt 0 -or $SimulateCleanupFailure -eq 'failed') { 'failed' } elseif ($cleanupIssues.Count -gt 0) { 'degraded' } else { 'clean' }
    if ($cleanupStatus -ne 'clean' -and -not $executionReason) { $executionReason = 'cleanupIncomplete' }
    $receipt = [ordered]@{
        Kind = 'antigravity-public-review-receipt'; SchemaVersion = 1; Backend = 'antigravity'; Profile = $Profile
        Model = $Model; EffectiveMode = $Mode; CliVersion = $cliVersion; ExpectedCliVersion = $ExpectedCliVersion
        CliVersionMatchesBaseline = ($cliVersion -eq $ExpectedCliVersion); ScratchPath = $scratch
        ScratchOwned = $scratchOwned; ScratchWasEmpty = $scratchWasEmpty; Workspace = $workspaceDiagnostics
        EnvironmentRedirected = $true
        RedirectedEnvironmentKeys = @('USERPROFILE','HOME','APPDATA','LOCALAPPDATA','TEMP','TMP','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME','ANTIGRAVITY_HOME','AGY_HOME')
        KeyringIsolation = 'not-isolated-global-keyring'; CleanupStatus = $cleanupStatus
        CleanupIssues = @($cleanupIssues); AliveDescendantsAfterCleanup = @($aliveDescendantsAfterCleanup)
        ScratchRemoved = $scratchRemoved; ResponseAccepted = ($null -eq $executionError -and $cleanupStatus -ne 'failed')
        Reason = $executionReason; StartedAtUtc = $startedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
        EndedAtUtc = $endedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    try { Write-PublicReviewReceipt -Receipt $receipt } catch {
        if ($null -eq $executionError) { $executionError = New-PublicReviewException -Reason 'cleanupIncomplete' -Detail "failed to write receipt: $($_.Exception.Message)" }
    }
    if ($cleanupStatus -eq 'failed' -and $null -eq $executionError) {
        $executionError = New-PublicReviewException -Reason 'cleanupIncomplete' -Detail 'descendant processes remained alive after best-effort cleanup'
    }
}

if ($null -ne $executionError) { throw $executionError }
return $responseText
