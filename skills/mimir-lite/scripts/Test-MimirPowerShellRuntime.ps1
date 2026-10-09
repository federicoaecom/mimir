<#
.SYNOPSIS
    Checks whether the XPZ base's minimum PowerShell runtime is available.

.DESCRIPTION
    Consultative gate for KB workspaces. It must be called before the other
    local wrappers to ensure `pwsh` exists and meets the base's minimum
    contract: PowerShell 7.4 or later on Windows, 7.4.6 or later on Linux
    and macOS. On Linux and macOS, 7.4.6 is the first version tested:
    pwsh 7.4.2 loses a native command's stderr when stdout and stderr are
    redirected to separate files.

    The gate runs the `pwsh` found on PATH and asks it for its version and
    whether it runs on Windows. When it does not, a -MinimumVersion below
    7.4.6 is raised to 7.4.6, so wrappers that pass 7.4 get the floor too.
    The script declares no `#requires` on purpose: it must also run on an
    older host, such as Windows PowerShell 5.1, to report the problem.

    A prerelease version such as `7.6.0-preview.5` or `7.5.0-rc.1` is
    accepted: the numeric part before `-` is compared, and build metadata
    after `+` is ignored. As in semantic versioning, a prerelease comes
    before its release, so a prerelease of exactly the minimum (for example
    `7.4.0-preview.1` against 7.4) does not meet it; a prerelease of a
    higher version does. Missing version components count as 0.

.PARAMETER MinimumVersion
    Minimum pwsh version. Defaults to 7.4; raised to 7.4.6 off Windows.
#>

[CmdletBinding()]
param(
    [version]$MinimumVersion = [version]'7.4'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$nonWindowsFloor = [version]'7.4.6'

$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $pwsh) {
    $installHint = "PowerShell $MinimumVersion or later"
    if ($MinimumVersion -lt $nonWindowsFloor) {
        $installHint += " ($nonWindowsFloor or later on Linux and macOS)"
    }
    Write-Output "BLOCK: pwsh not found on PATH; install $installHint before using this KB workspace"
    exit 1
}

# The child reports `<version>|<isWindows>`; `$IsWindows` exists in every pwsh, but not in
# Windows PowerShell 5.1, which may be the host running this gate. The command text holds no
# double quote (Windows PowerShell 5.1 drops embedded quotes from native arguments) and no
# literal `|` (cmd.exe would read it as a pipe when `pwsh` on PATH is a `.cmd` shim).
$outputLines = @()
try {
    $outputLines = @(& $pwsh.Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString() + [char]124 + $IsWindows' 2>&1 |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ -ne '' })
} catch {
    Write-Output "BLOCK: failed to run pwsh: $($_.Exception.Message)"
    exit 1
}
$rawText = $outputLines -join ' '

$versionText = $rawText
$childIsWindows = $null
foreach ($line in $outputLines) {
    if ($line -match '^(?<version>[^|\s]+)\|(?<windows>True|False)$') {
        $versionText = $Matches['version']
        $childIsWindows = ($Matches['windows'] -eq 'True')
    }
}
if ($null -eq $childIsWindows) {
    # A version-only answer: the child runs on the same machine, so use the host OS.
    $childIsWindows = ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

# Split `<numeric>[-<prerelease>][+<build>]`; only the numeric part goes to [version].
$actualVersion = $null
$isPrerelease = $false
$numericText = $versionText
if ($versionText -match '^(?<numeric>[^-+]+)(?:-(?<prerelease>[^+]*))?(?:\+.*)?$') {
    $numericText = $Matches['numeric']
    $isPrerelease = ($Matches.ContainsKey('prerelease') -and $Matches['prerelease'] -ne '')
}
if (-not [version]::TryParse($numericText, [ref]$actualVersion)) {
    Write-Output "BLOCK: could not determine pwsh version: '$rawText'"
    exit 1
}

# [version] ranks 7.4 below 7.4.0; treat a missing component as 0 so both compare equal.
function ConvertTo-ComparableVersion {
    param([version]$Version)
    return (New-Object System.Version $Version.Major, $Version.Minor, ([Math]::Max($Version.Build, 0)), ([Math]::Max($Version.Revision, 0)))
}

$effectiveMinimum = $MinimumVersion
$floorApplied = $false
if (-not $childIsWindows -and $effectiveMinimum -lt $nonWindowsFloor) {
    $effectiveMinimum = $nonWindowsFloor
    $floorApplied = $true
}

$comparableActual = ConvertTo-ComparableVersion -Version $actualVersion
$comparableMinimum = ConvertTo-ComparableVersion -Version $effectiveMinimum
# A prerelease precedes its release, so it meets the minimum only when its numeric part is higher.
if ($isPrerelease) {
    $meetsMinimum = ($comparableActual -gt $comparableMinimum)
} else {
    $meetsMinimum = ($comparableActual -ge $comparableMinimum)
}

if (-not $meetsMinimum) {
    $message = "BLOCK: PowerShell $effectiveMinimum or later required; found $versionText at $($pwsh.Source)"
    if ($floorApplied) {
        $message += " (Linux and macOS need $nonWindowsFloor or later: pwsh 7.4.2 loses a native command's stderr when stdout and stderr are redirected to separate files)"
    }
    Write-Output $message
    exit 1
}

Write-Output "POWERSHELL_RUNTIME_OK: pwsh $versionText at $($pwsh.Source)"
exit 0
