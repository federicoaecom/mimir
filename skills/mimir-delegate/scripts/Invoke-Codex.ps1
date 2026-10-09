#requires -Version 7.4
<#
.SYNOPSIS
    Calls the Codex CLI (codex exec, synchronous) and returns the final response as text.
.DESCRIPTION
    codex backend of the mimir-delegate skill. Resolves the compatible codex.exe (desktop app,
    not the npm shim), sends the prompt via stdin, and captures the final response through the
    output-last-message file (-o) in the durable group under TempDir, with `--json` stream in
    <GUID>.stream.jsonl. Blocks until the response (or until
    -TimeoutSec). If the timeout kills the process but lastmsg already has bytes, the verdict is
    recovered (captureOutcome=success + MIMIR_CODEX_RECOVERED_AFTER_TIMEOUT sentinel); with no
    bytes in lastmsg, it throws a timeout as before.

    This is the canonical synchronous invocation (the panel calls this adapter with a high
    TimeoutSec).

    Sandbox: fixed read-only (delegation is reading/second-opinion, never writing). Codex
    exec is agentic and CAN read the workspace filesystem; this does NOT bypass the
    confidentiality gate.

    CONFIDENTIALITY: this script does NOT decide where the data may go. Before sending
    sensitive payload (KB workspace content) to a model, the caller must go through
    the Resolve-LlmDelegateAuthorization.ps1 gate (use -Backend codex), per the skill.

    request.json (source invoke-sync) does NOT persist the prompt; the prompt lives in
    invoke-in.txt until cleanup. MIMIR_CODEX_* sentinels go out via [Console]::Error (never
    Write-Error). Stdout on success: only the verdict.
.PARAMETER Message
    Prompt to send to the agent (positional). Sent via stdin. Exclusive with -MessagePath.
.PARAMETER MessagePath
    Path to a file to read the prompt from (UTF-8). Exclusive with -Message. Useful for
    large prompts and to avoid command substitution ("(Get-Content ...)") on the caller's
    command line (no compound command = no unnecessary authorization prompt in the harness).
    Codex already delivers the prompt via stdin, so -MessagePath does not change the transport;
    it only changes the text's origin.
.PARAMETER Model
    Codex model (bare). Optional; when omitted, the adapter does not pass -m and lets
    Codex's own/config default apply.
.PARAMETER Oss
    Uses a local open-source provider (codex exec --oss). Implies a local model.
.PARAMETER LocalProvider
    Local OSS provider when -Oss: 'ollama' or 'lmstudio'.
.PARAMETER Profile
    Codex config profile (codex exec -p <id>).
.PARAMETER Cd
    Working directory of the agent (codex exec -C <dir>).
.PARAMETER CodexExe
    Forces a codex.exe path (bypasses automatic discovery).
.PARAMETER TimeoutSec
    Maximum wait time for the response (default 1200s). External models can be slow.
.PARAMETER TempDir
    Job files folder. No default in param(); the effective default lives in
    Resolve-CodexJobTempDir (non-blank Bound -> env MIMIR_CODEX_JOBS_DIR -> %TEMP%\codex-jobs),
    always absolute.
.PARAMETER KeepDays
    Maximum age (days) of job files before per-class auto-cleanup. Default 3
    (ValidateRange 1..3650). Best-effort cleanup; failure does not block the invocation.
.PARAMETER RetentionMode
    public (default): lastmsg/request stay on disk; only invoke-* is deleted after the
    captureOutcome rewrite. kb-sensitive: deletes lastmsg/invoke-* and the request after the
    rewrite; on execution failure, copies the lastmsg into the Exception.Message.
.EXAMPLE
    .\Invoke-Codex.ps1 "summarize this log"
.EXAMPLE
    .\Invoke-Codex.ps1 "hi" -Model gpt-5.5 -TimeoutSec 300
.EXAMPLE
    .\Invoke-Codex.ps1 -MessagePath .\large-prompt.txt -Model gpt-5.5
#>
[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Inline')] [string] $Message,
    [Parameter(Mandatory, ParameterSetName = 'FromFile')] [string] $MessagePath,
    [string] $Model,
    [switch] $Oss,
    [ValidateSet('ollama', 'lmstudio')] [string] $LocalProvider,
    [string] $Profile,
    [string] $Cd,
    [string] $CodexExe,
    [ValidateRange(1, 3600)] [int] $TimeoutSec = 1200,
    [string] $TempDir,
    [ValidateRange(1, 3650)] [int] $KeepDays = 3,
    [ValidateSet('public', 'kb-sensitive')] [string] $RetentionMode = 'public'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

. (Join-Path $PSScriptRoot 'CodexCliSupport.ps1')

# Zero job files until the exe resolves.
if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
    if (-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)) {
        throw "BLOCK: -MessagePath not found: $MessagePath"
    }
    $Message = Get-Content -LiteralPath $MessagePath -Raw -Encoding utf8
}

$exe = Resolve-CodexExe -Override $CodexExe

$tempOverride = $null
if ($PSBoundParameters.ContainsKey('TempDir') -and -not [string]::IsNullOrWhiteSpace($TempDir)) {
    $tempOverride = $TempDir.Trim()
}
$TempDir = Resolve-CodexJobTempDir -Override $tempOverride

try {
    Invoke-CodexJobsKeepDaysCleanup -TempDir $TempDir -KeepDays $KeepDays
} catch { }

$jobId       = [guid]::NewGuid().ToString('N')
$base        = Join-Path $TempDir $jobId
$reqPath     = "$base.request.json"
$lastMsgPath = "$base.lastmsg.txt"
$streamPath  = "$base.stream.jsonl"
$invokeIn    = "$base.invoke-in.txt"
$invokeErr   = "$base.invoke-err.txt"

$startedAt = Format-CodexUtcTimestamp -Value (Get-Date).ToUniversalTime()
$requestObj = [ordered]@{
    schemaVersion = 1
    source        = 'invoke-sync'
    jobId         = $jobId
    model         = if ($Model) { $Model } else { $null }
    startedAt     = $startedAt
    lastMsgPath   = $lastMsgPath
}
Write-CodexJsonAtomic -Object $requestObj -Path $reqPath

Set-Content -LiteralPath $invokeIn -Value $Message -Encoding utf8 -NoNewline
Set-Content -LiteralPath $invokeErr -Value '' -Encoding utf8 -NoNewline

$arguments = @(
    'exec', '--skip-git-repo-check', '-s', 'read-only', '--color', 'never',
    '--json', '-o', $lastMsgPath
)
if ($Model) { $arguments += @('-m', $Model) }
if ($Oss) { $arguments += '--oss' }
if ($LocalProvider) { $arguments += @('--local-provider', $LocalProvider) }
if ($Profile) { $arguments += @('-p', $Profile) }
if ($Cd) { $arguments += @('-C', $Cd) }
$arguments += '-'

$script:captureOutcome = 'success'
$script:pendingExceptionMessage = $null
$script:successText = $null
$script:recoveredAfterTimeout = $false

function Append-CodexPendingBlock {
    param([Parameter(Mandatory)] [string] $Block)
    if ($null -eq $script:pendingExceptionMessage) {
        $script:pendingExceptionMessage = $Block
    } else {
        $script:pendingExceptionMessage = $script:pendingExceptionMessage + "`n" + $Block
    }
}

function Ensure-CodexPendingSentinels {
    if ($null -eq $script:pendingExceptionMessage) { return }
    if ($script:pendingExceptionMessage -notmatch '(?m)^MIMIR_CODEX_LASTMSG=') {
        $script:pendingExceptionMessage = $script:pendingExceptionMessage + "`nMIMIR_CODEX_LASTMSG=$lastMsgPath"
    }
    if ($script:pendingExceptionMessage -notmatch '(?m)^MIMIR_CODEX_REQUEST=') {
        $script:pendingExceptionMessage = $script:pendingExceptionMessage + "`nMIMIR_CODEX_REQUEST=$reqPath"
    }
}

function Write-CodexInvokeRequestRewrite {
    param(
        [Parameter(Mandatory)] [string] $Outcome,
        [bool] $IncludeRetentionFlag = $false,
        [bool] $RetentionCleanupFailed = $false
    )
    if ($env:MIMIR_TEST_CODEX_INVOKE_FAIL_REWRITE -eq '1') {
        throw 'hook: request rewrite fail'
    }
    $requestObj['captureOutcome'] = $Outcome
    if ($script:recoveredAfterTimeout) {
        $requestObj['recoveredAfterTimeout'] = $true
    } elseif ($requestObj.Contains('recoveredAfterTimeout')) {
        $requestObj.Remove('recoveredAfterTimeout')
    }
    if ($IncludeRetentionFlag) {
        $requestObj['retentionCleanupFailed'] = [bool]$RetentionCleanupFailed
    } elseif ($requestObj.Contains('retentionCleanupFailed')) {
        $requestObj.Remove('retentionCleanupFailed')
    }
    Write-CodexJsonAtomic -Object $requestObj -Path $reqPath -Force
}

try {
    if ($env:MIMIR_TEST_CODEX_INVOKE_UNEXPECTED -eq '1') {
        throw 'BLOCK: unexpected test failure.'
    }

    $p = Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -PassThru `
        -RedirectStandardOutput $streamPath -RedirectStandardError $invokeErr -RedirectStandardInput $invokeIn

    $timedOut = $false
    if ($env:MIMIR_TEST_CODEX_FORCE_TIMEOUT -eq '1') {
        # Test hook: wait for the fake to write -o and exit; classify as timeout with unlocked files.
        try { [void]$p.WaitForExit(60000) } catch { }
        $timedOut = $true
    }
    elseif (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill($true) } catch {
            try { $p.Kill() } catch { }
        }
        try { [void]$p.WaitForExit(5000) } catch { }
        Start-Sleep -Milliseconds 300
        $timedOut = $true
    }

    # Stdout (the --json JSONL stream) is redirected to stream.jsonl.
    $stdoutText = (Get-Content -LiteralPath $streamPath -Raw -ErrorAction SilentlyContinue)
    $stderrText = (Get-Content -LiteralPath $invokeErr -Raw -ErrorAction SilentlyContinue)

    $final = ''
    if (Test-Path -LiteralPath $lastMsgPath -PathType Leaf) {
        $final = (Get-Content -LiteralPath $lastMsgPath -Raw -Encoding utf8 -ErrorAction SilentlyContinue)
    }
    if ($null -eq $final) { $final = '' }

    if ($timedOut) {
        # FORCE_TIMEOUT preserves the self-tests' historical contract (always timeout).
        # On a real timeout, if lastmsg already has bytes, recovers the verdict (premature Kill).
        if ($env:MIMIR_TEST_CODEX_FORCE_TIMEOUT -eq '1') {
            $script:captureOutcome = 'timeout'
            $script:pendingExceptionMessage = "BLOCK: codex exceeded ${TimeoutSec}s and was terminated."
        }
        elseif (-not [string]::IsNullOrWhiteSpace($final)) {
            $script:captureOutcome = 'success'
            $script:successText = $final.TrimEnd("`r", "`n")
            $script:recoveredAfterTimeout = $true
        }
        else {
            $script:captureOutcome = 'timeout'
            $script:pendingExceptionMessage = "BLOCK: codex exceeded ${TimeoutSec}s and was terminated."
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($final)) {
        $script:successText = $final.TrimEnd("`r", "`n")
    }
    elseif ($p.ExitCode -eq 0) {
        $script:captureOutcome = 'empty'
        $script:pendingExceptionMessage = 'BLOCK: codex did not produce a response (output-last-message empty).'
    }
    else {
        $script:captureOutcome = 'error'
        $errMsg = Get-CodexExecErrorMessage -StdoutText $stdoutText -StderrText $stderrText
        if ($errMsg) {
            $script:pendingExceptionMessage = "BLOCK: codex returned an error: $errMsg"
        } else {
            $stdoutClean = if ($stdoutText) { $stdoutText.Trim() } else { '' }
            $stderrClean = if ($stderrText) { $stderrText.Trim() } else { '' }
            if ($stdoutClean -or $stderrClean) {
                $parts = @()
                if ($stdoutClean) {
                    $stdoutLines = @($stdoutClean -split "`r?`n" | Select-Object -First 8) -join "`n"
                    $parts += "stdout:`n$stdoutLines"
                }
                if ($stderrClean) {
                    $stderrLines = @($stderrClean -split "`r?`n" | Select-Object -First 8) -join "`n"
                    $parts += "stderr:`n$stderrLines"
                }
                $detailsText = $parts -join "`n---`n"
                $script:pendingExceptionMessage = "BLOCK: codex exited with code $($p.ExitCode).`n$detailsText"
            } else {
                $script:pendingExceptionMessage = "BLOCK: codex exited with code $($p.ExitCode) without a response."
            }
        }
    }
}
catch {
    $script:captureOutcome = 'error'
    $msg = [string]$_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = 'unexpected error' }
    if ($msg -notlike 'BLOCK:*') {
        $msg = "BLOCK: $msg"
    }
    $script:pendingExceptionMessage = $msg
}
finally {
    # NEVER throw from the finally block.

    # 2b. Sentinels on stderr (success and failure).
    try {
        [Console]::Error.WriteLine("MIMIR_CODEX_LASTMSG=$lastMsgPath")
        [Console]::Error.WriteLine("MIMIR_CODEX_REQUEST=$reqPath")
        if ($script:recoveredAfterTimeout) {
            [Console]::Error.WriteLine('MIMIR_CODEX_RECOVERED_AFTER_TIMEOUT=1')
        }
    } catch { }

    if ($RetentionMode -eq 'public') {
        $rewriteOk = $false
        try {
            Write-CodexInvokeRequestRewrite -Outcome $script:captureOutcome -IncludeRetentionFlag:$false
            $rewriteOk = $true
        } catch {
            $rewriteOk = $false
        }

        if (-not $rewriteOk) {
            if ($null -ne $script:pendingExceptionMessage) {
                Append-CodexPendingBlock -Block 'BLOCK: failed to write request.json.'
            }
            # Success: does not block successText; does not delete the group.
        } else {
            foreach ($f in @($invokeIn, $invokeErr)) {
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            }
            # stream.jsonl stays in public (diagnostics).
        }
    }
    else {
        # kb-sensitive
        $isExecFailure = ($null -ne $script:pendingExceptionMessage) -or (
            $script:captureOutcome -eq 'timeout' -or
            $script:captureOutcome -eq 'error' -or
            $script:captureOutcome -eq 'empty'
        )

        if ($isExecFailure) {
            if ((Test-Path -LiteralPath $lastMsgPath -PathType Leaf)) {
                $captured = $null
                try {
                    $captured = Get-Content -LiteralPath $lastMsgPath -Raw -Encoding utf8 -ErrorAction SilentlyContinue
                } catch { $captured = $null }
                if (-not [string]::IsNullOrWhiteSpace($captured)) {
                    Ensure-CodexPendingSentinels
                    Append-CodexPendingBlock -Block 'MIMIR_CODEX_CAPTURED_TEXT_BEGIN'
                    $script:pendingExceptionMessage = $script:pendingExceptionMessage + "`n" + $captured
                }
            }
        }

        $rewriteOk = $false
        try {
            Write-CodexInvokeRequestRewrite -Outcome $script:captureOutcome -IncludeRetentionFlag:$true -RetentionCleanupFailed:$false
            $rewriteOk = $true
        } catch {
            $rewriteOk = $false
        }

        if (-not $rewriteOk) {
            try {
                if (Test-Path -LiteralPath $reqPath -PathType Leaf) {
                    [Console]::Error.WriteLine("MIMIR_CODEX_REQUEST=$reqPath")
                }
                if (Test-Path -LiteralPath $lastMsgPath -PathType Leaf) {
                    [Console]::Error.WriteLine("MIMIR_CODEX_LASTMSG=$lastMsgPath")
                }
            } catch { }
            Append-CodexPendingBlock -Block 'BLOCK: failed to write request.json before kb-sensitive cleanup.'
        }
        else {
            $deleteFailed = $false
            foreach ($pass in 1..5) {
                $deleteFailed = $false
                foreach ($f in @($invokeIn, $invokeErr, $lastMsgPath, $streamPath)) {
                    try {
                        if (Test-Path -LiteralPath $f -PathType Leaf) {
                            Remove-Item -LiteralPath $f -Force -ErrorAction Stop
                        }
                    } catch {
                        $deleteFailed = $true
                    }
                }
                if (-not $deleteFailed) { break }
                Start-Sleep -Milliseconds 200
            }
            if (-not $deleteFailed) {
                try {
                    if (Test-Path -LiteralPath $reqPath -PathType Leaf) {
                        Remove-Item -LiteralPath $reqPath -Force -ErrorAction Stop
                    }
                } catch {
                    $deleteFailed = $true
                }
            }

            if ($deleteFailed) {
                try {
                    Write-CodexInvokeRequestRewrite -Outcome $script:captureOutcome -IncludeRetentionFlag:$true -RetentionCleanupFailed:$true
                } catch { }
                Append-CodexPendingBlock -Block 'BLOCK: failed to clean up kb-sensitive artifacts.'
                try {
                    if (Test-Path -LiteralPath $reqPath -PathType Leaf) {
                        [Console]::Error.WriteLine("MIMIR_CODEX_REQUEST=$reqPath")
                    }
                    if (Test-Path -LiteralPath $lastMsgPath -PathType Leaf) {
                        [Console]::Error.WriteLine("MIMIR_CODEX_LASTMSG=$lastMsgPath")
                    }
                } catch { }
            }
        }
    }

    if ($null -ne $script:pendingExceptionMessage) {
        Ensure-CodexPendingSentinels
    }
}

if ($null -ne $script:pendingExceptionMessage) {
    throw $script:pendingExceptionMessage
}
elseif ($null -ne $script:successText) {
    return $script:successText
}
else {
    throw 'BLOCK: Invoke-Codex has neither a verdict nor a pending error.'
}
