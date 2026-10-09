#requires -Version 7.4
<#
.SYNOPSIS
    Machine-level state folder of mimir-delegate, shared by every script that keeps state.
.DESCRIPTION
    Dot-source this file and call Get-LlmDelegateStateRoot. It returns
    <local application data folder>/mimir-delegate:
      - Windows: %LOCALAPPDATA%\mimir-delegate. A process-level LOCALAPPDATA wins when it is a
        full path; otherwise the known-folder API, which does not read the environment.
      - Linux: $XDG_DATA_HOME/mimir-delegate, else ~/.local/share/mimir-delegate.
      - macOS: .NET's local application data folder (typically
        ~/Library/Application Support/mimir-delegate); when ~/Library/Application Support does
        not exist, the Linux base below (XDG_DATA_HOME, else HOME/.local/share). Not tested in CI.
    Off Windows, [Environment]::GetFolderPath('LocalApplicationData') returns an empty string while
    that folder does not exist yet. The helper then derives the Linux base itself (an absolute
    XDG_DATA_HOME, else HOME/.local/share) instead of falling back to a temporary folder, which
    would not persist. It never creates folders: callers that write create them.
    When no base can be determined, it throws an error that names what is missing.
    Callers keep their own overrides (-CircuitStateRoot, -PreferredRoot, -OutputPath,
    -CapabilitiesPath) and check them before calling this.
#>

function Get-LlmDelegateStateRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $base = $null
    if ($IsWindows) {
        $localAppData = $env:LOCALAPPDATA
        if (-not [string]::IsNullOrWhiteSpace($localAppData) -and [System.IO.Path]::IsPathFullyQualified($localAppData)) {
            $base = $localAppData
        }
        else {
            $base = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        }
    }
    else {
        $base = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($base)) {
            # Same rule as the XDG base directory spec and .NET: a relative XDG_DATA_HOME is ignored.
            $xdgData = $env:XDG_DATA_HOME
            $userHome = if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { $env:HOME } else { $HOME }
            if (-not [string]::IsNullOrWhiteSpace($xdgData) -and [System.IO.Path]::IsPathRooted($xdgData)) {
                $base = $xdgData
            }
            elseif (-not [string]::IsNullOrWhiteSpace($userHome)) {
                $base = Join-Path (Join-Path $userHome '.local') 'share'
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($base)) {
        $missing = if ($IsWindows) { 'LOCALAPPDATA' } else { 'XDG_DATA_HOME and HOME' }
        throw "mimir-delegate state folder: cannot determine the local application data folder ($missing not set)."
    }
    return (Join-Path $base 'mimir-delegate')
}
