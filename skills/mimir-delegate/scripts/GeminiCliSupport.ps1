#requires -Version 7.4
<#
.SYNOPSIS
    Shared functions for the gemini backend of the mimir-delegate skill.
.DESCRIPTION
    Resolves the gemini command, validates the minimum flag contract used by the adapter, and
    extracts error messages from the Gemini CLI output.
#>

Set-StrictMode -Version Latest

function ConvertFrom-GeminiVersionText {
    param([string]$Text)
    $m = [regex]::Match([string]$Text, '(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) { return $null }
    return [version]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
}

function Test-GeminiHelpSupportsContract {
    param([string]$HelpText)
    $required = @(
        '--prompt',
        '--approval-mode',
        '--output-format',
        '--model'
    )
    foreach ($flag in $required) {
        if ($HelpText -notmatch [regex]::Escape($flag)) { return $false }
    }
    return $true
}

function Resolve-GeminiExe {
    param(
        [string]$Override,
        [version]$MinimumVersion = ([version]'0.35.3'),
        [switch]$SkipContractCheck
    )

    if ($Override) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) {
            throw "BLOCK: gemini given in -GeminiExe does not exist: $Override"
        }
        $exe = (Resolve-Path -LiteralPath $Override).Path
    } else {
        $cmd = Get-Command gemini -ErrorAction SilentlyContinue
        if (-not $cmd -or -not $cmd.Source) {
            throw 'BLOCK: gemini CLI not found on PATH. Install/authenticate the Gemini CLI or pass -GeminiExe.'
        }
        $exe = $cmd.Source
    }

    $versionText = ''
    try { $versionText = (& $exe --version 2>&1 | Out-String).Trim() } catch { $versionText = '' }
    $version = ConvertFrom-GeminiVersionText $versionText
    if ($null -eq $version) {
        throw "BLOCK: could not read the Gemini CLI version at $exe. Output: $versionText"
    }
    if ($version -lt $MinimumVersion) {
        throw "BLOCK: Gemini CLI $version is older than the minimum validated version $MinimumVersion for this adapter."
    }

    if (-not $SkipContractCheck) {
        $helpText = ''
        try { $helpText = (& $exe --help 2>&1 | Out-String) } catch { $helpText = '' }
        if (-not (Test-GeminiHelpSupportsContract -HelpText $helpText)) {
            throw 'BLOCK: Gemini CLI found, but does not expose the flags required by the adapter.'
        }
    }

    return $exe
}

function Get-GeminiErrorMessage {
    param([string]$StdoutText, [string]$StderrText)
    $combined = @($StderrText, $StdoutText) -join "`n"
    if ([string]::IsNullOrWhiteSpace($combined)) { return $null }
    $lines = @($combined -split "`r?`n")
    # `auth` also matches the inflected forms "authentication"/"authenticating", the words of two
    # real failure shapes: the interactive prompt "Opening authentication page in your browser..."
    # (stdout, exit 0) and "Error authenticating: IneligibleTierError..." (stderr, exit 1). Matching
    # only the isolated form (\bauth\b) would make the extractor return $null and lose the reason. `credential`
    # is deliberately left OUT: the CLI emits "Loaded cached credentials" as an informational line
    # during normal execution, and including it would bring noise into the error message.
    $interesting = @($lines | Where-Object {
        $_ -match '(?i)\b(error|failed|unauthorized|forbidden|not\s+available|requires|login|sign\s*in|auth|authenticat\w*|authoriz\w*|invalid)\b'
    })
    if ($interesting.Count -gt 0) {
        return (($interesting | Select-Object -First 8) -join "`n").Trim()
    }
    return $null
}
