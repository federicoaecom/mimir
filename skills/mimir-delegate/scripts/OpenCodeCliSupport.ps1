#requires -Version 7.4
<#
.SYNOPSIS
    Shared functions to discover and validate the opencode CLI.
.DESCRIPTION
    Used by the opencode adapters of the mimir-delegate skill. Discovery does not assume
    npm-based installation: it accepts an explicit override, PATH (WinGet/Scoop/direct binary), and,
    on Windows only and for backward compatibility, the npm install under %APPDATA%\npm. Off
    Windows, discovery is the override or PATH only (Get-Command opencode -CommandType Application).
#>

Set-StrictMode -Version Latest

function Get-OpenCodeExeVersion {
    param([Parameter(Mandatory)] [string] $ExePath)
    try {
        $raw = & $ExePath --version 2>$null
        $line = ([string](@($raw) | Select-Object -First 1)).Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return $null }
        return $line
    } catch {
        return $null
    }
}

function Resolve-OpenCodeExe {
    param([string] $Override)

    if ($Override) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) {
            throw "BLOCK: -OpenCodeExe given does not exist: $Override"
        }
        $version = Get-OpenCodeExeVersion -ExePath $Override
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "BLOCK: -OpenCodeExe did not respond to 'opencode --version': $Override"
        }
        return $Override
    }

    $candidates = [System.Collections.Generic.List[string]]::new()

    try {
        # Off Windows, only native executables count (no alias, function or script named opencode).
        $cmds = if ($IsWindows) {
            @(Get-Command opencode -All -ErrorAction SilentlyContinue)
        } else {
            @(Get-Command opencode -CommandType Application -All -ErrorAction SilentlyContinue)
        }
        foreach ($cmd in $cmds) {
            if ($cmd.Source -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) {
                if (-not $candidates.Contains($cmd.Source)) { $candidates.Add($cmd.Source) }
            }
        }
    } catch { }

    # The npm install under %APPDATA% is a Windows-only location; off Windows, PATH is the only source.
    $searchedLocations = [System.Collections.Generic.List[string]]::new()
    $searchedLocations.Add('PATH via Get-Command opencode')
    if ($IsWindows) {
        $npmRoot = Join-Path $env:APPDATA 'npm\node_modules\opencode-ai'
        $searchedLocations.Add($npmRoot)
        if (Test-Path -LiteralPath $npmRoot -PathType Container) {
            $npmCandidates = @(Get-ChildItem -LiteralPath $npmRoot -Recurse -Filter 'opencode.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like '*windows-x64\bin\opencode.exe' } |
                Select-Object -ExpandProperty FullName)
            foreach ($c in $npmCandidates) {
                if (-not $candidates.Contains($c)) { $candidates.Add($c) }
            }
        }
    }

    foreach ($c in $candidates) {
        $version = Get-OpenCodeExeVersion -ExePath $c
        if (-not [string]::IsNullOrWhiteSpace($version)) { return $c }
    }

    $searched = $searchedLocations -join '; '
    $exeName = if ($IsWindows) { 'opencode.exe' } else { 'opencode' }
    throw "BLOCK: $exeName not found or not functional. Locations checked: $searched. Install the opencode CLI or provide -OpenCodeExe <path>."
}

function Get-OpenCodeAgentListLines {
    <#
        Runs `opencode agent list` with a SHORT RETRY to tolerate a transient SQLite failure
        (`PRAGMA wal_checkpoint`) observed in the field. Retries ONLY on a TRANSIENT failure (exit!=0 or
        an exception), with a brief sleep between attempts; exit 0 (even if the sought block does not
        appear) is NOT transient and is not retried. Returns @{ ok; lines; error }. -Retries =
        EXTRA attempts (default 2 => up to 3 runs); -RetryDelayMs = pause between attempts
        (0 in the self-tests).
    #>
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [int] $Retries = 2,
        [int] $RetryDelayMs = 250
    )
    $attempts = [Math]::Max(1, $Retries + 1)
    $lastErr = $null
    for ($i = 1; $i -le $attempts; $i++) {
        $failed = $false
        $stdout = $null
        try {
            $prev = if (Test-Path Variable:LASTEXITCODE) { $LASTEXITCODE } else { 0 }
            $stdout = & $Exe agent list 2>$null
            $exit = $LASTEXITCODE
            $global:LASTEXITCODE = $prev
            if ($exit -ne 0) {
                $failed = $true
                $lastErr = "'opencode agent list' exited with code $exit (attempt $i/$attempts)."
            }
        } catch {
            $failed = $true
            $lastErr = "exception while running 'opencode agent list' (attempt $i/$attempts): $($_.Exception.Message)"
        }
        if (-not $failed) { return @{ ok = $true; lines = @($stdout); error = $null } }
        if ($i -lt $attempts -and $RetryDelayMs -gt 0) { Start-Sleep -Milliseconds $RetryDelayMs }
    }
    return @{ ok = $false; lines = @(); error = $lastErr }
}

function Get-OpenCodeAgentBlockFromAgentList {
    <#
        Extracts the JSON rule array for agent <Name> from the text output of `opencode agent list`.
        The output interleaves several agents (header `name (mode)` + pretty JSON array). Locates the
        header and accumulates lines until the bracket depth returns to zero. Returns the array of
        objects (@{permission;action;pattern}) or $null if the agent does not appear.
    #>
    param(
        [Parameter(Mandatory)] [string[]] $Lines,
        [Parameter(Mandatory)] [string] $Name
    )

    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match ("^" + [regex]::Escape($Name) + "\s*\(")) { $start = $i; break }
    }
    if ($start -lt 0) { return $null }

    $buf = [System.Collections.Generic.List[string]]::new()
    $depth = 0
    $started = $false
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        $s = $Lines[$i]
        # a new agent header before the array opens => empty/unexpected block
        if (-not $started -and $s -match '^\S.*\(.*\)\s*$') { break }
        $buf.Add($s)
        $open = ([regex]::Matches($s, '\[')).Count
        $close = ([regex]::Matches($s, '\]')).Count
        $depth += ($open - $close)
        if ($open -gt 0) { $started = $true }
        if ($started -and $depth -le 0) { break }
    }
    if (-not $started) { return $null }
    try {
        return ($buf -join "`n" | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Test-OpenCodeAgentResolves {
    <#
        When the caller passes an EXPLICIT -Agent <x>, confirms that <x> RESOLVES (appears in
        `opencode agent list`) - otherwise opencode would SILENTLY fall back to the full-access `build`
        (`--agent <missing>` does not fail). Returns @{ ok = $bool; detail }.
    #>
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [Parameter(Mandatory)] [string] $Name,
        [int] $Retries = 2,
        [int] $RetryDelayMs = 250
    )
    $al = Get-OpenCodeAgentListLines -Exe $Exe -Retries $Retries -RetryDelayMs $RetryDelayMs
    if (-not $al.ok) {
        return @{ ok = $false; detail = $al.error }
    }
    $rules = Get-OpenCodeAgentBlockFromAgentList -Lines $al.lines -Name $Name
    if ($null -eq $rules) {
        return @{ ok = $false; detail = "agent '$Name' does not resolve in 'opencode agent list' — would fall back silently to the full-access 'build'." }
    }
    return @{ ok = $true; detail = "agent '$Name' resolves." }
}
