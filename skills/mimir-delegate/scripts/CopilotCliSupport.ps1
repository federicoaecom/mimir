#requires -Version 7.4
<#
.SYNOPSIS
    Shared functions for the copilot backend of the mimir-delegate skill.
.DESCRIPTION
    Resolves the copilot command, validates the minimum flag contract used by the adapter, and
    extracts the final response from the GitHub Copilot CLI's JSONL stream.
#>

Set-StrictMode -Version Latest

function ConvertFrom-CopilotVersionText {
    param([string]$Text)
    $m = [regex]::Match([string]$Text, '(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) { return $null }
    return [version]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
}

function Test-CopilotHelpSupportsContract {
    param([string]$HelpText)
    $required = @(
        '--prompt',
        '--output-format',
        '--stream',
        '--no-custom-instructions',
        '--disable-builtin-mcps',
        '--available-tools',
        '--allow-all-tools',
        '--model'
    )
    foreach ($flag in $required) {
        if ($HelpText -notmatch [regex]::Escape($flag)) { return $false }
    }
    return $true
}

function Resolve-CopilotExe {
    param(
        [string]$Override,
        [version]$MinimumVersion = ([version]'1.0.12'),
        [switch]$SkipContractCheck
    )

    if ($Override) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) {
            throw "BLOCK: copilot given in -CopilotExe does not exist: $Override"
        }
        $exe = (Resolve-Path -LiteralPath $Override).Path
    } else {
        $cmd = Get-Command copilot -ErrorAction SilentlyContinue
        if (-not $cmd -or -not $cmd.Source) {
            throw 'BLOCK: copilot CLI not found on PATH. Install/authenticate the GitHub Copilot CLI or pass -CopilotExe.'
        }
        $exe = $cmd.Source
    }

    $versionText = ''
    try { $versionText = (& $exe --version 2>&1 | Out-String).Trim() } catch { $versionText = '' }
    $version = ConvertFrom-CopilotVersionText $versionText
    if ($null -eq $version) {
        throw "BLOCK: could not read the GitHub Copilot CLI version at $exe. Output: $versionText"
    }
    if ($version -lt $MinimumVersion) {
        throw "BLOCK: GitHub Copilot CLI $version is older than the minimum validated version $MinimumVersion for this adapter."
    }

    if (-not $SkipContractCheck) {
        $helpText = ''
        try { $helpText = (& $exe --help 2>&1 | Out-String) } catch { $helpText = '' }
        if (-not (Test-CopilotHelpSupportsContract -HelpText $helpText)) {
            throw 'BLOCK: GitHub Copilot CLI found, but does not expose the flags required by the adapter.'
        }
    }

    return $exe
}

function Get-CopilotJsonlFinalText {
    param([string[]]$Lines)

    $finalText = ''
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $ev = $null
        try { $ev = $line | ConvertFrom-Json } catch { continue }
        $type = [string]$ev.type
        if ($type -eq 'assistant.message' -and $ev.PSObject.Properties['data']) {
            $data = $ev.data
            if ($data.PSObject.Properties['content']) {
                $content = [string]$data.content
                if (-not [string]::IsNullOrWhiteSpace($content)) { $finalText = $content }
            }
        }
    }
    return $finalText
}

function Get-CopilotJsonlExitCode {
    param([string[]]$Lines)

    $exitCode = $null
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $ev = $null
        try { $ev = $line | ConvertFrom-Json } catch { continue }
        if ([string]$ev.type -eq 'result' -and $ev.PSObject.Properties['exitCode']) {
            $exitCode = [int]$ev.exitCode
        }
    }
    return $exitCode
}

function Get-CopilotErrorMessage {
    param([string]$StdoutText, [string]$StderrText)
    $combined = @($StderrText, $StdoutText) -join "`n"
    if ([string]::IsNullOrWhiteSpace($combined)) { return $null }
    $lines = @($combined -split "`r?`n")
    $interesting = @($lines | Where-Object {
        $_ -match '(?i)\b(error|failed|unauthorized|forbidden|not\s+available|requires|login|auth)\b'
    })
    if ($interesting.Count -gt 0) {
        return (($interesting | Select-Object -First 8) -join "`n").Trim()
    }
    return $null
}
