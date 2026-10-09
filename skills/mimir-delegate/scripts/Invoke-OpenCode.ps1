#requires -Version 7.4
<#
.SYNOPSIS
    Calls opencode (one-shot, synchronous) and returns the response as text.
.DESCRIPTION
    opencode backend of the mimir-delegate skill. Resolves opencode.exe via -OpenCodeExe, PATH
    (WinGet/Scoop/direct binary) or legacy npm, and runs it with the prompt delivered via STDIN
    (a file), OUTSIDE the argv. Delivering the prompt via
    stdin (rather than as a positional argument to 'run') works around the Windows command-line
    ~32KB limit for large prompts and uses EXPLICIT stdout/stderr redirection to a file
    (Start-Process -RedirectStandard*), avoiding the non-deterministic "StandardOutputEncoding
    is only supported when standard output is redirected" error of the older pattern (& exe 1> file inside
    a temporary runner). Blocks until the response (or until -TimeoutSec).

    opencode reads the prompt from stdin when the positional argument to 'run' is omitted (verified
    empirically against the opencode build in use on this machine, 2026-06). Mirrors the stdin-based
    pattern of Invoke-Codex.ps1.

    This is the canonical synchronous invocation; give long tasks a higher -TimeoutSec.

    CONFIDENTIALITY: this script does NOT decide where the data may go. Before sending
    sensitive payload (content from a KB workspace) to a model, the caller must pass
    through the Resolve-LlmDelegateAuthorization.ps1 gate, per the mimir-delegate skill.
.PARAMETER Message
    Prompt to send to the agent (positional). Mutually exclusive with -MessagePath.
.PARAMETER MessagePath
    Path to a file to read the prompt from (UTF-8). Mutually exclusive with -Message. Useful for
    large prompts (above the ~32KB command-line limit) and to avoid command
    substitution ("$(cat ...)") on the caller's command line.
.PARAMETER Model
    Model in provider/model format (e.g. openai/gpt-5.4). Optional: omitted uses opencode's
    config default (~/.config/opencode/opencode.json).
.PARAMETER Agent
    Name of the opencode agent to use. Optional.
.PARAMETER OpenCodeExe
    Forces an opencode.exe path (bypasses automatic discovery). Also used by the
    self-tests to inject a fake exe.
.PARAMETER Raw
    Returns the raw JSON stream (one event per line) instead of the final text. No retry. On timeout,
    the adapter still classifies usage/rate limits (there is no useful stream to return). On other
    terminal outcomes (exit!=0, etc.), -Raw does not classify limits.
.PARAMETER AllText
    Returns the whole narration (step preambles + final response) concatenated, instead of just the final response.
.PARAMETER TimeoutSec
    Maximum time to wait for the response (default 1200s). It is PER ATTEMPT: with -MaxAttempts > 1,
    total wall-clock time can be a multiple of this value.
.PARAMETER MaxAttempts
    Maximum number of attempts (1-3, default 1 = historical behavior, no retry).
    With 2+, re-dispatches ONCE per additional attempt ONLY when the completion verdict is
    'truncated' or 'no-completion' (intermittent tail truncation from opencode). NEVER retries on
    timeout, non-zero exit code, an explicit stream error, a usage/rate limit detected in the
    attempt's window, or 'empty' (clean completion with no text). Has no effect with -Raw (which returns the 1st run).
    Each retry emits, on stderr, a line 'OPENCODE_RETRY: attempt=N status=... reason=...'.
.EXAMPLE
    .\Invoke-OpenCode.ps1 "hi"
.EXAMPLE
    .\Invoke-OpenCode.ps1 "summarize this log" -Model openai/gpt-5.4
.EXAMPLE
    .\Invoke-OpenCode.ps1 -MessagePath .\large-prompt.txt -Model ollama-cloud/deepseek-v4-pro
.EXAMPLE
    .\Invoke-OpenCode.ps1 "hi" -Raw      # raw JSON stream (tool-calls, cost, tokens)
#>
[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Inline')] [string] $Message,
    [Parameter(Mandatory, ParameterSetName = 'FromFile')] [string] $MessagePath,
    [string] $Model,
    [string] $Agent,
    [string] $OpenCodeExe,
    [switch] $Raw,
    [switch] $AllText,
    [ValidateRange(1, 3600)] [int] $TimeoutSec = 1200,
    [ValidateRange(1, 3)] [int] $MaxAttempts = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensures UTF-8 output (accents) when returning the text via stdout
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

# Shared functions to parse the opencode stream (dot-source)
. (Join-Path $PSScriptRoot 'OpenCodeStreamSupport.ps1')
# opencode CLI discovery (npm, WinGet/PATH, explicit override) + explicit -Agent resolution
. (Join-Path $PSScriptRoot 'OpenCodeCliSupport.ps1')

# Prompt: inline (-Message) or from a file (-MessagePath). Read as UTF-8.
if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
    if (-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)) {
        throw "BLOCK: -MessagePath not found: $MessagePath"
    }
    $Message = Get-Content -LiteralPath $MessagePath -Raw -Encoding utf8
}

# 1) Resolves opencode.exe: explicit override, PATH (WinGet/Scoop/direct binary) or legacy npm.
$exe = Resolve-OpenCodeExe -Override $OpenCodeExe

# 1b) Without an explicit -Agent, no default agent is applied: opencode runs with whichever
#     agent its own config resolves to. With an EXPLICIT -Agent <x>, confirm that <x> RESOLVES, to avoid
#     silently falling back to 'build' (`--agent <missing>` does not fail).
$agentExplicit = $PSBoundParameters.ContainsKey('Agent') -and -not [string]::IsNullOrWhiteSpace($Agent)
# INHERITED cwd (opencode has no -Cd). WARNING: on Windows, `opencode run` FAILS (empty stdout /
# uv_spawn ENAMETOOLONG) when this cwd is a git WORKTREE (.git gitlink). Run from a flat dir
# without .git (e.g. git archive HEAD -> dir). See SKILL.md, section "KNOWN LIMITATION - opencode run
# FAILS IN A GIT WORKTREE CWD (WINDOWS)".
$cwd = (Get-Location).Path
if ($agentExplicit) {
    $res = Test-OpenCodeAgentResolves -Exe $exe -Name $Agent
    if (-not $res.ok) {
        throw "BLOCK: -Agent '$Agent' does not resolve (avoids silent fallback to full-access 'build'): $($res.detail)"
    }
}

# 2) Prompt via STDIN (a file), outside the argv. opencode reads stdin when the
#    positional argument to 'run' is omitted; -RedirectStandardInput delivers the file and gives EOF at the end
#    (headless anti-hang preserved: the CLI does not get stuck reading an inherited stdin with no end).
$ocArgs = @('run', '--format', 'json')
if (-not [string]::IsNullOrWhiteSpace($Model)) { $ocArgs += @('--model', $Model) }
if (-not [string]::IsNullOrWhiteSpace($Agent)) { $ocArgs += @('--agent', $Agent) }

$in  = (New-TemporaryFile).FullName
Set-Content -LiteralPath $in -Value $Message -Encoding utf8 -NoNewline
$out = $null
$err = $null
$attempt = 0

# Retry-once (opt-in via -MaxAttempts; default 1 = historical behavior, no retry).
# Retry ONLY on a truncated/no-completion completion verdict (opencode tail
# non-determinism); NEVER on timeout, exit!=0, an explicit stream error, a masked usage/rate limit, or
# 'empty' (clean completion). The retry decision reads $verdict.status DIRECTLY (it does not catch the
# throw), so terminals thrown before the verdict escape the loop. Precedence per attempt:
#   (1) timeout / exit!=0 / explicit stream error  -> terminal (exits the loop)
#   (2) completion verdict: 'ok' returns; 'empty' terminal; only {truncated, no-completion} are retryable
#   (3) when DECIDING to retry, checks the usage/rate limit in the window -> terminal (gates the retry).
#       With no retry pending (-MaxAttempts 1 / last attempt), the resolver still runs;
#       with no hit, it reports the completion verdict.
# -TimeoutSec is PER ATTEMPT (with -MaxAttempts 2 wall-clock time can double).
try {
    while ($true) {
        $attempt++
        $startedAt = (Get-Date).ToUniversalTime()
        $out = (New-TemporaryFile).FullName
        $err = (New-TemporaryFile).FullName

        $p = Start-Process -FilePath $exe -ArgumentList $ocArgs -NoNewWindow -PassThru `
            -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill($true) } catch { }
            $limitHit = Resolve-OpenCodeProviderLimitHit -StreamErrors @(Get-OpenCodeStreamErrorCandidates -Lines @(Get-Content -LiteralPath $out -Encoding utf8 -ErrorAction SilentlyContinue)) -StderrText ([string](Get-Content -LiteralPath $err -Raw -Encoding utf8 -ErrorAction SilentlyContinue)) -SinceTime $startedAt
            if ($null -ne $limitHit) {
                throw (Format-OpenCodeLimitBlock -Kind ([string](Get-OcProp $limitHit 'kind')) -Message ([string](Get-OcProp $limitHit 'message')))
            }
            throw "BLOCK: opencode exceeded ${TimeoutSec}s and was terminated."
        }
        if ($p.ExitCode -ne 0) {
            if (-not $Raw) {
                $limitHit = Resolve-OpenCodeProviderLimitHit -StreamErrors @(Get-OpenCodeStreamErrorCandidates -Lines @(Get-Content -LiteralPath $out -Encoding utf8 -ErrorAction SilentlyContinue)) -StderrText ([string](Get-Content -LiteralPath $err -Raw -Encoding utf8 -ErrorAction SilentlyContinue)) -SinceTime $startedAt
                if ($null -ne $limitHit) {
                    throw (Format-OpenCodeLimitBlock -Kind ([string](Get-OcProp $limitHit 'kind')) -Message ([string](Get-OcProp $limitHit 'message')))
                }
            }
            throw "BLOCK: opencode exited with code $($p.ExitCode).`nstderr:`n$(Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)"
        }

        # Post-check (DEFENSE-IN-DEPTH, not the barrier): with an explicit -Agent, reads the CONTENTS of
        # $err (discarded in the finally block) BEFORE Remove-Item and scans for the silent-fallback warning.
        # If it appears, --agent did not resolve at runtime despite the pre-check -> discard the output.
        if ($agentExplicit) {
            $errText = Get-Content -LiteralPath $err -Raw -Encoding utf8 -ErrorAction SilentlyContinue
            if (Test-OpenCodeAgentFallbackWarning -Text $errText) {
                throw "BLOCK: post-check -Agent '$Agent': fallback-to-'build' warning detected in stderr (--agent did not resolve at runtime despite the pre-check). Output discarded for safety."
            }
        }

        $lines = Get-Content -LiteralPath $out -Encoding utf8
        # -Raw: literal stream from the 1st run, WITHOUT retry (the caller wants the raw stream from one call).
        if ($Raw) { return $lines }

        $events = ConvertFrom-OpenCodeStreamLines -Lines $lines

        # An explicit agent error in the stream takes priority over the absence of text and is terminal.
        $errMsg = Get-OpenCodeStreamErrorMessage -Events $events
        if ($errMsg) {
            $limitHit = Resolve-OpenCodeProviderLimitHit -StreamErrors @(Get-OpenCodeStreamErrorCandidates -Lines @($lines)) -StderrText ([string](Get-Content -LiteralPath $err -Raw -Encoding utf8 -ErrorAction SilentlyContinue)) -SinceTime $startedAt
            if ($null -ne $limitHit) {
                throw (Format-OpenCodeLimitBlock -Kind ([string](Get-OcProp $limitHit 'kind')) -Message ([string](Get-OcProp $limitHit 'message')))
            }
            throw "BLOCK: opencode returned an error in the stream: $errMsg"
        }

        $parts = @(Get-OpenCodeTextParts -Events $events)
        $finalText = Get-OpenCodeFinalText -TextParts $parts

        # Finding D: do NOT return the preamble as the response. Completion precedence ALWAYS wins over the
        # final response (Get-OpenCodeFinalText), never over the -AllText narration: reason!=stop ->
        # truncated; step_finish/reason absent -> no-completion; empty final text -> empty.
        $signal = Get-OpenCodeCompletionSignal -Events $events
        $verdict = Get-OpenCodeCompletionVerdict -HasStepFinish $signal.hasStepFinish -Reason $signal.reason -FinalText $finalText

        if ($verdict.status -eq 'ok') {
            # -AllText: narration of the SUCCESSFUL attempt; default: concatenated final response.
            if ($AllText) { return (Get-OpenCodeAllText -TextParts $parts) }
            return $finalText
        }

        # Only 'truncated'/'no-completion' are retryable; 'empty' (clean completion) is terminal.
        $retryable = ($verdict.status -eq 'truncated' -or $verdict.status -eq 'no-completion')
        if ($retryable -and $attempt -lt $MaxAttempts) {
            $limitHit = Resolve-OpenCodeProviderLimitHit -StreamErrors @(Get-OpenCodeStreamErrorCandidates -Lines @($lines)) -StderrText ([string](Get-Content -LiteralPath $err -Raw -Encoding utf8 -ErrorAction SilentlyContinue)) -SinceTime $startedAt
            if ($null -ne $limitHit) {
                throw (Format-OpenCodeLimitBlock -Kind ([string](Get-OcProp $limitHit 'kind')) -Message ([string](Get-OcProp $limitHit 'message')))
            }
            [Console]::Error.WriteLine("OPENCODE_RETRY: attempt=$attempt status=$($verdict.status) reason=$($verdict.reason)")
            Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
            $out = $null
            $err = $null
            continue
        }

        # Exhausted or non-retryable (includes 'empty'): throws with the LAST attempt's status.
        $limitHit = Resolve-OpenCodeProviderLimitHit -StreamErrors @(Get-OpenCodeStreamErrorCandidates -Lines @($lines)) -StderrText ([string](Get-Content -LiteralPath $err -Raw -Encoding utf8 -ErrorAction SilentlyContinue)) -SinceTime $startedAt
        if ($null -ne $limitHit) {
            throw (Format-OpenCodeLimitBlock -Kind ([string](Get-OcProp $limitHit 'kind')) -Message ([string](Get-OcProp $limitHit 'message')))
        }
        if ($attempt -gt 1) {
            throw "$($verdict.message) (after $attempt attempts; last status=$($verdict.status) reason=$($verdict.reason))"
        }
        throw $verdict.message
    }
}
finally {
    Remove-Item -LiteralPath $in -Force -ErrorAction SilentlyContinue
    if ($out) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
    if ($err) { Remove-Item -LiteralPath $err -Force -ErrorAction SilentlyContinue }
}
