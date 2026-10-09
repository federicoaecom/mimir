#requires -Version 7.4
<#
.SYNOPSIS
    Calls the Claude Code CLI (synchronous) and returns the final response as text.
.DESCRIPTION
    claude-code backend of the mimir-delegate skill. Sends the prompt via stdin to avoid
    payload in a process argument, uses `claude -p`, and captures stdout. Runs by default in
    a restricted short-query mode: no session persistence, permission-mode plan, and
    read-only tools. Does not limit agentic turns: CLI 2.1.215 removed `--max-turns` from
    `--help` and the adapter has no way to negotiate that limit (see CHANGELOG).

    CONFIDENTIALITY: this script does NOT decide whether the payload may go to Anthropic. Before
    sending sensitive payload, go through Resolve-LlmDelegateAuthorization.ps1 -Backend
    claude-code.
.PARAMETER Message
    Prompt to send to Claude Code. Sent via stdin. Exclusive with -MessagePath.
.PARAMETER MessagePath
    Path to a file to read the prompt from (UTF-8). Exclusive with -Message. Avoids command
    substitution ("(Get-Content ...)") on the caller's command line (no compound command = no
    unnecessary authorization prompt in the harness). The prompt already goes via stdin;
    -MessagePath only changes the text's origin.
.PARAMETER Model
    Model accepted by Claude Code. Default: claude-opus-4-8.
.PARAMETER PermissionMode
    Claude Code permission mode. Default: plan.
.PARAMETER Tools
    List of available tools. Default: Read,Glob,Grep. Use "" to disable all
    (becomes --tools "" in the CLI) or "default" to release the CLI's full default set.
.PARAMETER Cd
    Working directory of the Claude Code process. Default: caller's current directory.
.PARAMETER ClaudeExe
    Forces the path of the claude executable.
.PARAMETER TimeoutSec
    Maximum wait time. External models can be slow.
#>
[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Inline')] [string] $Message,
    [Parameter(Mandatory, ParameterSetName = 'FromFile')] [string] $MessagePath,
    [string] $Model = 'claude-opus-4-8',
    [ValidateSet('default', 'acceptEdits', 'plan', 'auto', 'dontAsk', 'bypassPermissions')] [string] $PermissionMode = 'plan',
    [string] $Tools = 'Read,Glob,Grep',
    [string] $Cd,
    [string] $ClaudeExe,
    [ValidateRange(1, 3600)] [int] $TimeoutSec = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

. (Join-Path $PSScriptRoot 'ClaudeCodeCliSupport.ps1')

# Prompt: inline (-Message) or from file (-MessagePath). Read as UTF-8 before any use.
if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
    if (-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)) {
        throw "BLOCK: -MessagePath not found: $MessagePath"
    }
    $Message = Get-Content -LiteralPath $MessagePath -Raw -Encoding utf8
}

if ($PSBoundParameters.ContainsKey('PermissionMode') -and $PermissionMode -eq 'bypassPermissions') {
    throw 'BLOCK: Invoke-ClaudeCode.ps1 does not allow PermissionMode=bypassPermissions.'
}

$exe = Resolve-ClaudeCodeExe -Override $ClaudeExe
$workDir = if ($Cd) { (Resolve-Path -LiteralPath $Cd).Path } else { (Get-Location).Path }

$arguments = @(
    '-p',
    '--model', $Model,
    '--output-format', 'text',
    '--no-session-persistence',
    '--permission-mode', $PermissionMode
)
# No turn limit: the adapter does not pass `--max-turns`.
# The CLI accepts --tools "" to disable all tools. The empty value needs to go
# quoted: Start-Process discards an empty string from ArgumentList and, since --tools is variadic,
# it would end up consuming the following argument.
if ([string]::IsNullOrWhiteSpace($Tools)) {
    $arguments += @('--tools', '""')
} else {
    $arguments += @('--tools', $Tools)
}

$in = (New-TemporaryFile).FullName
$out = (New-TemporaryFile).FullName
$err = (New-TemporaryFile).FullName
Set-Content -LiteralPath $in -Value $Message -Encoding utf8 -NoNewline

try {
    $p = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $workDir `
        -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err `
        -RedirectStandardInput $in
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        throw "BLOCK: Claude Code exceeded ${TimeoutSec}s and was terminated."
    }

    $stdoutText = Get-Content -LiteralPath $out -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    $stderrText = Get-Content -LiteralPath $err -Raw -Encoding utf8 -ErrorAction SilentlyContinue

    if ($p.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stdoutText)) {
        return $stdoutText.TrimEnd("`r", "`n")
    }

    # Exit 0 without output -- preserve current behavior
    if ($p.ExitCode -eq 0) {
        throw 'BLOCK: Claude Code did not produce a response.'
    }

    # ExitCode != 0 -- preserve evidence from both channels
    $errMsg = Get-ClaudeCodeErrorMessage -StdoutText $stdoutText -StderrText $stderrText
    if ($errMsg) {
        throw "BLOCK: Claude Code returned an error: $errMsg"
    }

    $stdoutClean = if ($stdoutText) { $stdoutText.Trim() } else { '' }
    $cleanStderr = Remove-ClaudeCodeEnvironmentNoise -Text $stderrText

    if ($stdoutClean -or $cleanStderr) {
        $parts = @()
        if ($stdoutClean) {
            $stdoutLines = @($stdoutClean -split "`r?`n" | Select-Object -First 8) -join "`n"
            $parts += "stdout:`n$stdoutLines"
        }
        if ($cleanStderr) {
            $stderrLines = @($cleanStderr -split "`r?`n" | Select-Object -First 8) -join "`n"
            $parts += "stderr:`n$stderrLines"
        }
        $detailsText = $parts -join "`n---`n"
        throw "BLOCK: Claude Code exited with code $($p.ExitCode).`n$detailsText"
    }

    throw "BLOCK: Claude Code exited with code $($p.ExitCode) no response."
}
finally {
    Remove-Item -LiteralPath $in, $out, $err -Force -ErrorAction SilentlyContinue
}
