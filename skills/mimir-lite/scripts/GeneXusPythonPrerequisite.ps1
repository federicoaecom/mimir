#requires -Version 7.4
<#
.SYNOPSIS
    Resolves a usable Python executable for mimir-lite engines (e.g., KbIntelligence).

.DESCRIPTION
    Candidates are tried in order: `python3`, `python`, then `py -3` (the Windows launcher).
    Each one is actually run with `--version`, so a non-working shim (for example the Windows
    Store `python3` alias, which exits 9009) is skipped. An interpreter must report Python 3.8
    or later. Interpreters under a `WindowsApps` folder and empty (zero-byte) executables are
    rejected. Callers invoke the result as `& $python.Source @($python.PrefixArguments) <script> ...`.
#>

Set-StrictMode -Version Latest

$script:GeneXusPythonMinimumVersion = [version]'3.8'

function Test-GeneXusPythonCandidateExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        return $false
    }

    try {
        $length = (Get-Item -LiteralPath $ExecutablePath).Length
        if ($length -eq 0) {
            return $false
        }
    } catch {
        return $false
    }

    if ($ExecutablePath -match '[\\/]WindowsApps[\\/]') {
        return $false
    }

    return $true
}

function Get-GeneXusPythonVersionFromOutput {
    # Parses "Python X.Y[.Z]" from `--version` output; returns $null when absent.
    param([AllowNull()][string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }
    $match = [regex]::Match($VersionText, '\bPython\s+(\d+)\.(\d+)')
    if (-not $match.Success) {
        return $null
    }
    return [version]::new([int]$match.Groups[1].Value, [int]$match.Groups[2].Value)
}

function Get-GeneXusPythonExecutable {
    <#
    .OUTPUTS
        PSCustomObject with Source (executable path), PrefixArguments (string[]; `-3` for the
        `py` launcher, empty otherwise), VersionLine and Launcher (candidate name), or $null
        when no usable Python 3.8+ was found.
    #>
    $candidates = @(
        @{ Name = 'python3'; PrefixArguments = [string[]]@() },
        @{ Name = 'python'; PrefixArguments = [string[]]@() },
        @{ Name = 'py'; PrefixArguments = [string[]]@('-3') }
    )

    foreach ($candidate in $candidates) {
        $commands = @(Get-Command -Name $candidate.Name -CommandType Application -ErrorAction SilentlyContinue)
        foreach ($command in $commands) {
            $executablePath = $command.Source
            if ([string]::IsNullOrWhiteSpace($executablePath)) {
                continue
            }
            if (-not (Test-GeneXusPythonCandidateExecutable -ExecutablePath $executablePath)) {
                continue
            }

            $prefixArguments = [string[]]$candidate.PrefixArguments
            try {
                $versionOutput = @(& $executablePath @prefixArguments --version 2>&1)
            } catch {
                continue
            }
            if ($LASTEXITCODE -ne 0) {
                continue
            }

            $versionLine = (($versionOutput | ForEach-Object { $_.ToString() }) -join ' ').Trim()
            $version = Get-GeneXusPythonVersionFromOutput -VersionText $versionLine
            if ($null -eq $version -or $version -lt $script:GeneXusPythonMinimumVersion) {
                continue
            }

            return [pscustomobject]@{
                Source          = $executablePath
                PrefixArguments = $prefixArguments
                VersionLine     = $versionLine
                Launcher        = $candidate.Name
            }
        }
    }

    return $null
}

function Get-GeneXusPythonNotFoundMessage {
    return @(
        'PREREQUISITE MISSING: no usable Python 3 (3.8 or later) found on PATH (tried python3, python, py -3).'
        'Install Python 3.8 or later (https://www.python.org/downloads/) and add it to PATH.'
        'On Windows, ignore the Microsoft Store stub (WindowsApps) if it does not actually run.'
    ) -join ' '
}

function Get-GeneXusPythonPrerequisiteErrorMessage {
    return @(
        Get-GeneXusPythonNotFoundMessage
        'XPZ/XML materialization may have completed; only the KbIntelligence index was not generated.'
    ) -join ' '
}
