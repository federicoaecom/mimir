#requires -Version 7.4
<#
.SYNOPSIS
Reads and atomically writes the persistent synchronization state of an XML corpus.

.DESCRIPTION
The state lives in <corpus>/.mimir-sync-state.json (UTF-8 without BOM, LF) with these fields:
schemaVersion (1); state ('incomplete' or 'complete'); generation (32 lowercase hex characters
while complete, null while incomplete); updatedAt (UTC ISO 8601); packageSha256 (SHA-256 of the
package of the run that wrote the state); recoveryPackageSha256 (while incomplete, the SHA-256 of
the package whose re-run may publish the corpus again, or null when only a verified -FullSnapshot
sync can; always null while complete).

Reading a missing file returns state 'unknown'. A file that cannot be read or does not match the
schema (including a schemaVersion that is not the JSON integer 1) returns state 'invalid', never
'complete'. Writes go to an exclusively created sibling in
the same folder, which then replaces the state file. Callers hold the corpus lock
(GeneXusCorpusLockSupport.ps1) around every read that decides and every write.
#>

$script:GeneXusCorpusStateFileName = '.mimir-sync-state.json'

# Test-only stop point (see GeneXusCorpusState.stop_point_for_tests for the Python engines): when
# MIMIR_TEST_STOP_AT equals $Point, MIMIR_TEST_STOP_MODE 'kill' ends this process at once (no
# finally block runs; the OS releases the corpus lock), and 'pause' writes
# 'MIMIR_TEST_PAUSED <point>' to stderr and waits for a line on stdin. Unset, it does nothing.
function Invoke-GeneXusTestStopPoint {
    param([Parameter(Mandatory)][string]$Point)
    if ($env:MIMIR_TEST_STOP_AT -cne $Point) { return }
    switch -CaseSensitive ($env:MIMIR_TEST_STOP_MODE) {
        'kill' { [Diagnostics.Process]::GetCurrentProcess().Kill() }
        'pause' {
            [Console]::Error.WriteLine("MIMIR_TEST_PAUSED $Point")
            [Console]::Error.Flush()
            [void][Console]::In.ReadLine()
        }
    }
}

function Get-GeneXusCorpusSyncState {
    param([Parameter(Mandatory)][string]$CorpusRoot)
    $path = [IO.Path]::Combine($CorpusRoot, $script:GeneXusCorpusStateFileName)
    $result = [pscustomobject]@{ State = 'unknown'; Generation = $null; PackageSha256 = $null; RecoveryPackageSha256 = $null }
    if (-not [IO.File]::Exists($path)) { return $result }
    $result.State = 'invalid'
    try { $data = [IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable } catch { return $result }
    # Strict like GeneXusCorpusState.py: the JSON integer 1 only (not "1", 1.0, or true).
    $schemaVersion = if ($data -is [hashtable]) { $data['schemaVersion'] } else { $null }
    if (-not (($schemaVersion -is [int] -or $schemaVersion -is [long]) -and $schemaVersion -eq 1)) { return $result }
    $hash = $data['packageSha256']
    if ($hash -is [string] -and $hash -cmatch '^[0-9a-f]{64}$') { $result.PackageSha256 = $hash }
    if ($data['state'] -ceq 'complete') {
        $generation = $data['generation']
        if ($generation -is [string] -and $generation -cmatch '^[0-9a-f]{32}$') {
            $result.State = 'complete'
            $result.Generation = $generation
        }
    } elseif ($data['state'] -ceq 'incomplete') {
        $result.State = 'incomplete'
        $recovery = $data['recoveryPackageSha256']
        # A malformed recovery hash fails closed: only a verified full snapshot can publish.
        if ($recovery -is [string] -and $recovery -cmatch '^[0-9a-f]{64}$') { $result.RecoveryPackageSha256 = $recovery }
    }
    return $result
}

function Write-GeneXusCorpusSyncState {
    param(
        [Parameter(Mandatory)][string]$CorpusRoot,
        [Parameter(Mandatory)][ValidateSet('incomplete', 'complete')][string]$State,
        [Parameter(Mandatory)][string]$PackageSha256,
        [AllowNull()][string]$Generation,
        [AllowNull()][string]$RecoveryPackageSha256
    )
    if ($State -eq 'complete' -and $Generation -cnotmatch '^[0-9a-f]{32}$') { throw 'A complete corpus state requires a generation.' }
    $payload = [ordered]@{
        schemaVersion = 1
        state = $State
        generation = if ($State -eq 'complete') { $Generation } else { $null }
        updatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
        packageSha256 = $PackageSha256
        recoveryPackageSha256 = if ($State -eq 'incomplete' -and $RecoveryPackageSha256) { $RecoveryPackageSha256 } else { $null }
    }
    $text = (($payload | ConvertTo-Json -Depth 3) -replace "`r`n", "`n") + "`n"
    $path = [IO.Path]::Combine($CorpusRoot, $script:GeneXusCorpusStateFileName)
    $tempPath = [IO.Path]::Combine($CorpusRoot, '.mimir-sync-state-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $owned = $false
    try {
        $stream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $owned = $true
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
            $stream.Write($bytes, 0, $bytes.Length)
        } finally { $stream.Dispose() }
        [IO.File]::Move($tempPath, $path, $true)
        $owned = $false
    } finally {
        if ($owned) { [IO.File]::Delete($tempPath) }
    }
    return [pscustomobject]@{ State = $State; Generation = $payload.generation; PackageSha256 = $PackageSha256; RecoveryPackageSha256 = $payload.recoveryPackageSha256 }
}

function New-GeneXusCorpusGeneration {
    $bytes = [byte[]]::new(16)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToHexString($bytes).ToLowerInvariant()
}

function Get-GeneXusCorpusPackageSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-GeneXusCorpusEmpty {
    # True when the corpus holds no XML file at any depth (names starting with '.mimir-' are the
    # sync's own lock, state, and temporary files and are ignored); a missing folder is empty. An
    # enumeration error returns false, so an unreadable corpus is never taken as empty.
    param([Parameter(Mandatory)][string]$CorpusRoot)
    if (-not [IO.Directory]::Exists($CorpusRoot)) { return $true }
    $options = [IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $true
    $options.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
    $options.IgnoreInaccessible = $false
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($CorpusRoot, '*', $options)) {
            $name = [IO.Path]::GetFileName($file)
            if ($name.StartsWith('.mimir-', [StringComparison]::Ordinal)) { continue }
            if ($name.EndsWith('.xml', [StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
    } catch { return $false }
    return $true
}

function Get-GeneXusCorpusRecoveryPackageSha256 {
    # The package whose re-run may publish the corpus once this run marks it incomplete: this run's
    # package when the corpus was complete or was left incomplete by this same package; otherwise
    # none (an unknown, invalid, or other-package base can only be published by a full snapshot).
    param([Parameter(Mandatory)]$PreviousState, [Parameter(Mandatory)][string]$PackageSha256)
    if ($PreviousState.State -eq 'complete') { return $PackageSha256 }
    if ($PreviousState.State -eq 'incomplete' -and $PreviousState.RecoveryPackageSha256 -ceq $PackageSha256) { return $PackageSha256 }
    return $null
}

function Get-GeneXusCorpusRecoveryText {
    # The recovery sentence for an incomplete corpus. A package re-run is offered only when the state
    # records a recovery package; otherwise only a verified full snapshot can publish the corpus.
    param([AllowNull()][AllowEmptyString()][string]$RecoveryPackageSha256)
    if ([string]::IsNullOrEmpty($RecoveryPackageSha256)) {
        return 'Only a verified -FullSnapshot sync of a full KB export can complete it.'
    }
    return 'Re-run the package that left it incomplete, or run a verified -FullSnapshot sync of a full KB export.'
}

function Test-GeneXusCorpusPublication {
    # Decides whether a verified run may publish a new generation, from the state read under the
    # lock before the run mutated anything. Returns Allowed and, when not, the reason to report.
    # EmptyBase: the corpus had no state file and no XML (Test-GeneXusCorpusEmpty) when the run
    # took the lock, so a verified first sync starts from a known, empty base.
    # MarkedIncomplete: this run already recorded its own incomplete state, replacing the previous
    # recovery package with the one Get-GeneXusCorpusRecoveryPackageSha256 returns.
    param(
        [Parameter(Mandatory)]$PreviousState,
        [Parameter(Mandatory)][string]$PackageSha256,
        [bool]$VerifiedFullSnapshot,
        [bool]$EmptyBase,
        [bool]$MarkedIncomplete
    )
    if ($VerifiedFullSnapshot) { return [pscustomobject]@{ Allowed = $true; Note = $null } }
    switch ($PreviousState.State) {
        'complete' { return [pscustomobject]@{ Allowed = $true; Note = $null } }
        'unknown' {
            if ($EmptyBase) { return [pscustomobject]@{ Allowed = $true; Note = $null } }
            return [pscustomobject]@{ Allowed = $false; Note = "No corpus state was recorded before this run and the corpus already held XML; the corpus stays incomplete until a verified -FullSnapshot sync of a full KB export." }
        }
        'incomplete' {
            if ($PreviousState.RecoveryPackageSha256 -ceq $PackageSha256) { return [pscustomobject]@{ Allowed = $true; Note = $null } }
            $recorded = if ($MarkedIncomplete) { Get-GeneXusCorpusRecoveryPackageSha256 -PreviousState $PreviousState -PackageSha256 $PackageSha256 } else { $PreviousState.RecoveryPackageSha256 }
            $recover = Get-GeneXusCorpusRecoveryText -RecoveryPackageSha256 $recorded
            return [pscustomobject]@{ Allowed = $false; Note = "The corpus was already incomplete and this package cannot complete it; it stays incomplete. $recover" }
        }
        'invalid' { return [pscustomobject]@{ Allowed = $false; Note = "The corpus state file could not be read; the corpus stays incomplete until a verified -FullSnapshot sync of a full KB export." } }
        default { return [pscustomobject]@{ Allowed = $false; Note = "No corpus state was recorded before this run; the corpus stays incomplete until a verified -FullSnapshot sync of a full KB export." } }
    }
}
