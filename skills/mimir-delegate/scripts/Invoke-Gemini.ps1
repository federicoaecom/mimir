#requires -Version 7.4
<#
.SYNOPSIS
    Calls the Gemini CLI (synchronous) and returns the final response as text.
.DESCRIPTION
    gemini backend of the mimir-delegate skill. Uses `gemini -p` with `--approval-mode plan`
    and `--output-format json`, an advisory/read-only mode proven in local tests.

    CONFIDENTIALITY: this script does NOT decide whether the payload may go to Google. Before
    sending sensitive payload, go through Resolve-LlmDelegateAuthorization.ps1 -Backend
    gemini.
.PARAMETER Message
    Prompt to send to Gemini. Exclusive with -MessagePath.
.PARAMETER MessagePath
    Path to a file to read the prompt from (UTF-8). Exclusive with -Message. Avoids command
    substitution ("(Get-Content ...)") on the caller's command line. WARNING: this adapter is
    argument-based (the prompt goes in the argv via the runner), so -MessagePath does NOT raise
    the ~32KB ceiling of the Windows command line; a fail-closed guard (~30000 chars) rejects
    large prompts. Only the stdin-based adapters (Codex/Claude Code/opencode) are immune to the
    ceiling.
.PARAMETER Model
    Model accepted by the Gemini CLI. Default: gemini-3-flash-preview.
.PARAMETER ApprovalMode
    Gemini CLI approval mode. Default: plan.
.PARAMETER Cd
    Working directory of the Gemini process. Default: caller's current directory.
.PARAMETER GeminiExe
    Forces the path of the gemini command.
.PARAMETER TimeoutSec
    Maximum wait time.
#>
[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Inline')] [string] $Message,
    [Parameter(Mandatory, ParameterSetName = 'FromFile')] [string] $MessagePath,
    [string] $Model = 'gemini-3-flash-preview',
    [ValidateSet('default', 'auto_edit', 'yolo', 'plan')] [string] $ApprovalMode = 'plan',
    [string] $Cd,
    [string] $GeminiExe,
    [ValidateRange(1, 3600)] [int] $TimeoutSec = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

. (Join-Path $PSScriptRoot 'GeminiCliSupport.ps1')

if ($ApprovalMode -ne 'plan') {
    throw 'BLOCK: Invoke-Gemini.ps1 only allows ApprovalMode=plan for delegated calls.'
}

# Prompt: inline (-Message) or from file (-MessagePath, UTF-8). Read BEFORE the size guard.
if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
    if (-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)) {
        throw "BLOCK: -MessagePath not found: $MessagePath"
    }
    $Message = Get-Content -LiteralPath $MessagePath -Raw -Encoding utf8
}

# Fail-closed size guard (covers -Message AND -MessagePath). This adapter is argument-based:
# the prompt goes in the runner's argv, so above the margin the Windows command line overflows.
# The limit is HEURISTIC in chars (UTF-16 code units), not bytes: conservative margin under the
# ~32767 command-line ceiling, reserving room for the remaining flags. -MessagePath does NOT
# raise the ceiling.
$MaxArgvPromptChars = 30000
if ($Message.Length -gt $MaxArgvPromptChars) {
    throw "BLOCK: prompt with $($Message.Length) characters exceeds the $MaxArgvPromptChars ceiling for the argument-based Gemini adapter (the prompt goes in the argv; ~32767 ceiling of the Windows command line). Use a smaller prompt or a stdin-based backend (Codex/Claude Code/opencode). Migrating Gemini to stdin is a known follow-up."
}

$exe = Resolve-GeminiExe -Override $GeminiExe
$workDir = if ($Cd) { (Resolve-Path -LiteralPath $Cd).Path } else { (Get-Location).Path }

$out = New-TemporaryFile
$err = New-TemporaryFile
$req = New-TemporaryFile
$runner = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, '.ps1')
$request = [ordered]@{
    exe = $exe
    prompt = $Message
    model = $Model
    approvalMode = $ApprovalMode
    stdoutPath = $out.FullName
    stderrPath = $err.FullName
}
$request | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $req.FullName -Encoding utf8
@'
param([Parameter(Mandatory)][string]$RequestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$req = Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8 | ConvertFrom-Json
$gmArgs = @(
    '-p', [string]$req.prompt,
    '--approval-mode', [string]$req.approvalMode,
    '--output-format', 'json',
    '--model', [string]$req.model
)
# stdin closed ($null = pure EOF, no bytes) so gemini does not hang reading the stdin
# inherited from a headless shell without a TTY. Depends on this runner being 'pwsh -File' (not -Command).
$null | & ([string]$req.exe) @gmArgs 1> ([string]$req.stdoutPath) 2> ([string]$req.stderrPath)
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $runner -Encoding utf8

try {
    $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $runner, '-RequestPath', $req.FullName) `
        -WorkingDirectory $workDir -NoNewWindow -PassThru
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        throw "BLOCK: Gemini CLI exceeded ${TimeoutSec}s and was terminated."
    }

    $stdoutText = Get-Content -LiteralPath $out.FullName -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    $stderrText = Get-Content -LiteralPath $err.FullName -Raw -Encoding utf8 -ErrorAction SilentlyContinue

    if ($p.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stdoutText)) {
        $json = $null
        try { $json = $stdoutText | ConvertFrom-Json } catch {
            # The CLI can exit 0 and still write HUMAN TEXT to stdout instead of JSON -
            # measured on 2026-08-06 with gemini without a cached credential, which prints the
            # interactive login prompt ("Opening authentication page in your browser..."). Before
            # this ordering, the parse would blow up here and the adapter would die with "invalid
            # JSON: Unexpected character... O" - the 'O' from "Opening" -, without EVER consulting
            # Get-GeminiErrorMessage, which comes next and would have found the real reason.
            # Consult the extractor BEFORE giving up: an auth/service error becomes an actionable
            # message; only what it does not recognize keeps being reported as a broken JSON
            # contract, now with a stdout sample so the diagnostic is not blind.
            $parseErr = $_.Exception.Message
            $errMsgOnParse = Get-GeminiErrorMessage -StdoutText $stdoutText -StderrText $stderrText
            if ($errMsgOnParse) { throw "BLOCK: Gemini CLI returned an error: $errMsgOnParse" }
            $sample = ([string]$stdoutText).Trim()
            if ($sample.Length -gt 400) { $sample = $sample.Substring(0, 400) + '...' }
            throw "BLOCK: Gemini CLI returned invalid JSON: $parseErr`nstdout:`n$sample"
        }
        if ($json.PSObject.Properties['response'] -and -not [string]::IsNullOrWhiteSpace([string]$json.response)) {
            return ([string]$json.response).TrimEnd("`r", "`n")
        }
    }

    $errMsg = Get-GeminiErrorMessage -StdoutText $stdoutText -StderrText $stderrText
    if ($errMsg) { throw "BLOCK: Gemini CLI returned an error: $errMsg" }
    if ($p.ExitCode -ne 0) {
        throw "BLOCK: Gemini CLI exited with code $($p.ExitCode) without a response.`nstderr:`n$stderrText"
    }
    throw 'BLOCK: Gemini CLI did not produce a response in the JSON.'
}
finally {
    Remove-Item -LiteralPath $out.FullName, $err.FullName, $req.FullName, $runner -Force -ErrorAction SilentlyContinue
}
