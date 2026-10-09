#requires -Version 7.4
<#
.SYNOPSIS
    Calls the GitHub Copilot CLI (synchronous) and returns the final response as text.
.DESCRIPTION
    copilot backend of the mimir-delegate skill. Uses `copilot -p` in JSONL mode, with
    custom instructions disabled, built-in MCP disabled, and an empty tool set.
    `--allow-all-tools` remains because the Copilot CLI requires automatic permission in
    non-interactive mode, but with no tools available there is nothing to approve.

    CONFIDENTIALITY: this script does NOT decide whether the payload may go to GitHub Copilot.
    Before sending sensitive payload, go through Resolve-LlmDelegateAuthorization.ps1
    -Backend copilot.
.PARAMETER Message
    Prompt to send to Copilot. Exclusive with -MessagePath.
.PARAMETER MessagePath
    Path to a file to read the prompt from (UTF-8). Exclusive with -Message. Avoids command
    substitution ("(Get-Content ...)") on the caller's command line. WARNING: this adapter is
    argument-based (the prompt goes in the argv via the runner), so -MessagePath does NOT raise
    the ~32KB ceiling of the Windows command line; a fail-closed guard (~30000 chars) rejects
    large prompts. Only the stdin-based adapters (Codex/Claude Code/opencode) are immune to the
    ceiling.
.PARAMETER Model
    Model accepted by the Copilot CLI. Default: auto (Copilot itself chooses). Do not pin a
    concrete name: the Copilot catalog changes between CLI versions and a retired id makes the
    CLI refuse the call. Measured on 2026-08-06 (Copilot CLI 1.0.78): the old default
    'gpt-5-mini' started responding «Model "gpt-5-mini" from --model flag is not available»,
    while 'auto' responded normally. 'auto' is documented in the CLI's own --help.
.PARAMETER Cd
    Working directory of the Copilot process. Default: caller's current directory.
.PARAMETER CopilotExe
    Forces the path of the copilot command.
.PARAMETER TimeoutSec
    Maximum wait time.
#>
[CmdletBinding(DefaultParameterSetName = 'Inline')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Inline')] [string] $Message,
    [Parameter(Mandatory, ParameterSetName = 'FromFile')] [string] $MessagePath,
    [string] $Model = 'auto',
    [string] $Cd,
    [string] $CopilotExe,
    [ValidateRange(1, 3600)] [int] $TimeoutSec = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

. (Join-Path $PSScriptRoot 'CopilotCliSupport.ps1')

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
    throw "BLOCK: prompt with $($Message.Length) characters exceeds the $MaxArgvPromptChars ceiling for the argument-based Copilot adapter (the prompt goes in the argv; ~32767 ceiling of the Windows command line). Use a smaller prompt or a stdin-based backend (Codex/Claude Code/opencode). Migrating Copilot to stdin is a known follow-up."
}

$exe = Resolve-CopilotExe -Override $CopilotExe
$workDir = if ($Cd) { (Resolve-Path -LiteralPath $Cd).Path } else { (Get-Location).Path }

$out = New-TemporaryFile
$err = New-TemporaryFile
$req = New-TemporaryFile
$runner = [System.IO.Path]::ChangeExtension((New-TemporaryFile).FullName, '.ps1')
$request = [ordered]@{
    exe = $exe
    prompt = $Message
    model = $Model
    stdoutPath = $out.FullName
    stderrPath = $err.FullName
}
$request | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $req.FullName -Encoding utf8
@'
param([Parameter(Mandatory)][string]$RequestPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$req = Get-Content -LiteralPath $RequestPath -Raw -Encoding utf8 | ConvertFrom-Json
$cpArgs = @(
    '-p', [string]$req.prompt,
    '--model', [string]$req.model,
    '--no-custom-instructions',
    '--disable-builtin-mcps',
    '--stream', 'off',
    '--output-format', 'json',
    '--available-tools=',
    '--allow-all-tools'
)
# stdin closed ($null = pure EOF, no bytes) so copilot does not hang reading the stdin
# inherited from a headless shell without a TTY. Depends on this runner being 'pwsh -File' (not -Command).
$null | & ([string]$req.exe) @cpArgs 1> ([string]$req.stdoutPath) 2> ([string]$req.stderrPath)
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $runner -Encoding utf8

try {
    $p = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', $runner, '-RequestPath', $req.FullName) `
        -WorkingDirectory $workDir -NoNewWindow -PassThru
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        throw "BLOCK: Copilot CLI exceeded ${TimeoutSec}s and was terminated."
    }

    $stdoutText = Get-Content -LiteralPath $out.FullName -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    $stderrText = Get-Content -LiteralPath $err.FullName -Raw -Encoding utf8 -ErrorAction SilentlyContinue
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($stdoutText)) { $lines = @($stdoutText -split "`r?`n") }
    $final = Get-CopilotJsonlFinalText -Lines $lines
    $reportedExitCode = Get-CopilotJsonlExitCode -Lines $lines

    if ($p.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($final)) {
        return $final.TrimEnd("`r", "`n")
    }

    $errMsg = Get-CopilotErrorMessage -StdoutText $stdoutText -StderrText $stderrText
    if ($errMsg) { throw "BLOCK: Copilot CLI returned an error: $errMsg" }
    if ($null -ne $reportedExitCode -and $reportedExitCode -ne 0) {
        throw "BLOCK: Copilot CLI reported exitCode $reportedExitCode without a final response."
    }
    if ($p.ExitCode -ne 0) {
        throw "BLOCK: Copilot CLI exited with code $($p.ExitCode) without a response.`nstderr:`n$stderrText"
    }
    throw 'BLOCK: Copilot CLI did not produce a final response.'
}
finally {
    Remove-Item -LiteralPath $out.FullName, $err.FullName, $req.FullName, $runner -Force -ErrorAction SilentlyContinue
}
