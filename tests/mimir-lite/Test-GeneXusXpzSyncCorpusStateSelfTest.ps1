#requires -Version 7.4
<#
.SYNOPSIS
Self-test for the sync engine's corpus lock, persistent state and generation.

.DESCRIPTION
Runs Sync-GeneXusXpzToXml.ps1 as a child process against a temporary corpus outside the
repository and checks the rules of .mimir-sync-state.json: a first sync into a missing or empty
corpus (no XML, .mimir-* files ignored) publishes a generation; a sync over a non-empty corpus with
no recorded state stays incomplete; a schemaVersion that is not the integer 1 is invalid; a
verified -FullSnapshot publishes a generation; a delta
over a complete corpus publishes a new one; a run blocked before mutating writes no state;
a failure after the first mutation (including the kb-source-metadata.md update) leaves the
corpus incomplete; re-running the same package recovers it and another package does not; the
recovery text offers a package re-run only when the state records a recovery package, and
otherwise only a verified -FullSnapshot sync;
-VerifyOnly reports the state without writing it; a held corpus lock fails the run fast with
a clear message; and the inventory generator ignores .mimir-* files in the corpus.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$engine = Join-Path $repoRoot 'skills/mimir-lite/scripts/Sync-GeneXusXpzToXml.ps1'
$lockSupport = Join-Path $repoRoot 'skills/mimir-lite/scripts/GeneXusCorpusLockSupport.ps1'
$inventory = Join-Path $repoRoot 'skills/mimir-lite/scripts/generate-kb-inventory.ps1'
$base = if ($env:MIMIR_CORPUS_STATE_TEST_ROOT) { $env:MIMIR_CORPUS_STATE_TEST_ROOT } else { [IO.Path]::GetTempPath() }
$root = Join-Path $base ('mimir-corpus-state-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$encoding = [Text.UTF8Encoding]::new($false)
$corpus = Join-Path $root 'corpus'
$statePath = Join-Path $corpus '.mimir-sync-state.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}
function New-Package([string]$Name, [object[]]$Attributes) {
    $path = Join-Path $root "$Name.xml"
    $nodes = foreach ($a in $Attributes) {
        $source = if ($a.Count -gt 3) { " dataSource=`"$($a[3])`"" } else { '' }
        "<Attribute name=`"$($a[0])`" guid=`"`" lastUpdate=`"$($a[1])`" description=`"$($a[2])`"$source />"
    }
    [IO.File]::WriteAllText($path, "<ExportFile><Attributes>$($nodes -join '')</Attributes></ExportFile>", $encoding)
    return $path
}
function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Invoke-Sync([string]$Package, [string[]]$Extra = @(), [string]$Destination = $corpus) {
    $argsList = @('-NoProfile', '-NonInteractive', '-File', $engine, '-InputPath', $Package, '-DestinationRoot', $Destination) + $Extra
    $err = Join-Path $root 'stderr.txt'
    $stdout = & pwsh @argsList 2>$err
    $code = $LASTEXITCODE
    $text = ($stdout -join "`n")
    $json = $null
    if ($code -eq 0 -and $text) { $json = $text | ConvertFrom-Json }
    return [pscustomobject]@{ Code = $code; Stdout = $text; Stderr = [IO.File]::ReadAllText($err); Json = $json }
}
function Read-State {
    if (-not [IO.File]::Exists($statePath)) { return @{} }
    return [IO.File]::ReadAllText($statePath) | ConvertFrom-Json -AsHashtable
}
function Get-StateBytes { if ([IO.File]::Exists($statePath)) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath)) } else { '' } }
function Get-Property($Object, [string]$Name) {
    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) { return '<missing>' }
    return $Object.$Name
}

try {
    $p1 = New-Package 'p1' @(, @('Alpha', '2026-01-01T00:00:00Z', 'a1'))
    $p2 = New-Package 'p2' @(, @('Beta', '2026-01-01T00:00:00Z', 'b1'))

    # A first sync into a missing folder starts from a known empty base and publishes a generation.
    $first = Invoke-Sync $p1
    Check ($first.Code -eq 0) "first sync failed: $($first.Stderr)"
    $state = Read-State
    Check ($null -ne $state -and $state['schemaVersion'] -eq 1 -and $state['state'] -eq 'complete' -and $state['generation'] -match '^[0-9a-f]{32}$') "first sync into a missing corpus must publish: $(Get-StateBytes) $($first.Stderr)"
    Check ($null -ne $state -and $state['packageSha256'] -eq (Get-Sha256 $p1)) 'state must record the package SHA-256'
    $raw = [byte[]]::new(0)
    if ([IO.File]::Exists($statePath)) { $raw = [IO.File]::ReadAllBytes($statePath) }
    Check ($raw.Length -gt 3 -and $raw[0] -ne 0xef -and -not ([Text.Encoding]::UTF8.GetString($raw).Contains("`r"))) 'state file must be UTF-8 without BOM, LF'
    Check ((Get-Property $first.Json 'CorpusState') -eq 'complete' -and (Get-Property $first.Json 'CorpusStatePublished') -eq $true -and (Get-Property $first.Json 'CorpusGeneration') -eq $state['generation']) "first sync must report the published generation: $($first.Stdout)"

    # A first sync into an existing empty folder (only .mimir-* files, no XML) also publishes.
    $emptyCorpus = Join-Path $root 'empty-corpus'
    [void][IO.Directory]::CreateDirectory((Join-Path $emptyCorpus 'Attribute'))
    [IO.File]::WriteAllText((Join-Path $emptyCorpus '.mimir-sync.lock'), '', $encoding)
    [IO.File]::WriteAllText((Join-Path $emptyCorpus 'Attribute/.mimir-xml-leftover.xml'), 'partial', $encoding)
    $emptyRun = Invoke-Sync $p1 @() $emptyCorpus
    Check ($emptyRun.Code -eq 0 -and (Get-Property $emptyRun.Json 'CorpusStatePublished') -eq $true -and (Get-Property $emptyRun.Json 'CorpusState') -eq 'complete') "first sync into an empty corpus must publish: $($emptyRun.Stdout) $($emptyRun.Stderr)"

    # A first sync into a non-empty corpus with no recorded state stays incomplete.
    [IO.File]::Delete($statePath)
    $unknown = Invoke-Sync $p1
    $state = Read-State
    Check ($unknown.Code -eq 0 -and $state['state'] -eq 'incomplete' -and $null -eq $state['generation']) "sync over a non-empty corpus with no state must stay incomplete: $(Get-StateBytes)"
    Check ((Get-Property $unknown.Json 'CorpusState') -eq 'incomplete' -and (Get-Property $unknown.Json 'CorpusStatePublished') -eq $false -and $null -eq (Get-Property $unknown.Json 'CorpusGeneration')) "must report an unpublished incomplete corpus: $($unknown.Stdout)"
    Check ([string](Get-Property $unknown.Json 'CorpusStateNote') -match 'FullSnapshot') 'unpublished state must say how to recover'

    # schemaVersion must be the integer 1: a string "1" is an invalid state, never complete.
    . (Join-Path $repoRoot 'skills/mimir-lite/scripts/GeneXusCorpusStateSupport.ps1')
    $stringSchema = Join-Path $root 'string-schema'
    [void][IO.Directory]::CreateDirectory($stringSchema)
    [IO.File]::WriteAllText((Join-Path $stringSchema '.mimir-sync-state.json'), '{"schemaVersion":"1","state":"complete","generation":"0123456789abcdef0123456789abcdef","packageSha256":null,"recoveryPackageSha256":null}', $encoding)
    Check ((Get-GeneXusCorpusSyncState -CorpusRoot $stringSchema).State -eq 'invalid') 'a string schemaVersion must read as invalid'
    [IO.File]::WriteAllText((Join-Path $stringSchema '.mimir-sync-state.json'), '{"schemaVersion":1.5,"state":"complete","generation":"0123456789abcdef0123456789abcdef","packageSha256":null,"recoveryPackageSha256":null}', $encoding)
    Check ((Get-GeneXusCorpusSyncState -CorpusRoot $stringSchema).State -eq 'invalid') 'a non-integer schemaVersion must read as invalid'
    [IO.File]::WriteAllText((Join-Path $stringSchema '.mimir-sync-state.json'), '{"schemaVersion":1,"state":"complete","generation":"0123456789abcdef0123456789abcdef","packageSha256":null,"recoveryPackageSha256":null}', $encoding)
    Check ((Get-GeneXusCorpusSyncState -CorpusRoot $stringSchema).State -eq 'complete') 'an integer schemaVersion 1 must read as complete'

    # Re-running the same package does not bless a corpus whose prior state was unknown.
    $again = Invoke-Sync $p1
    Check ($again.Code -eq 0 -and (Read-State)['state'] -eq 'incomplete' -and (Get-Property $again.Json 'CorpusStatePublished') -eq $false) 're-run over an unknown base must stay incomplete'
    # With no recovery package recorded, only a -FullSnapshot sync is offered, never a package re-run.
    Check ($null -eq (Read-State)['recoveryPackageSha256']) 'an incomplete state left over an unknown base must record no recovery package'
    $againNote = [string](Get-Property $again.Json 'CorpusStateNote')
    Check ($againNote -match 'FullSnapshot' -and $againNote -notmatch 're-run') "no recovery package: the note must offer only -FullSnapshot: $againNote"
    Check ($again.Stderr -match 'FullSnapshot' -and $again.Stderr -notmatch 're-run') "no recovery package: stderr must offer only -FullSnapshot: $($again.Stderr)"

    # -VerifyOnly reports the state and never writes it.
    $before = Get-StateBytes
    $verify = Invoke-Sync $p1 @('-VerifyOnly')
    Check ($verify.Code -eq 0 -and (Get-Property $verify.Json 'CorpusState') -eq 'incomplete' -and (Get-Property $verify.Json 'CorpusStatePublished') -eq $false) "VerifyOnly must report the state: $($verify.Stdout)"
    Check ((Get-StateBytes) -eq $before) 'VerifyOnly changed the state file'

    # A failure after the first mutation over an incomplete state with no recovery package records
    # none and offers only -FullSnapshot.
    $pNull = New-Package 'p-null' @(@('Alpha', '2026-06-01T00:00:00Z', 'a0'), @('Gamma', '2026-06-01T00:00:00Z', 'g0'))
    $nullObstacle = Join-Path $corpus 'Attribute/Gamma.xml'
    [void][IO.Directory]::CreateDirectory($nullObstacle)
    $nullFailed = Invoke-Sync $pNull
    $state = Read-State
    Check ($nullFailed.Code -ne 0 -and $state['state'] -eq 'incomplete' -and $state['packageSha256'] -eq (Get-Sha256 $pNull) -and $null -eq $state['recoveryPackageSha256']) "failure over an incomplete state with no recovery package must record none: $(Get-StateBytes)"
    Check ([IO.File]::ReadAllText((Join-Path $corpus 'Attribute/Alpha.xml')).Contains('description="a0"')) 'the no-recovery failure must happen after a real mutation'
    Check ($nullFailed.Stderr -match 'CORPUS STATE: incomplete' -and $nullFailed.Stderr -match 'FullSnapshot' -and $nullFailed.Stderr -notmatch 're-run') "no recovery package: the failure must offer only -FullSnapshot: $($nullFailed.Stderr)"
    [IO.Directory]::Delete($nullObstacle)

    # A verified -FullSnapshot publishes a generation.
    $full = Invoke-Sync $p1 @('-FullSnapshot')
    $state = Read-State
    Check ($full.Code -eq 0 -and $state['state'] -eq 'complete' -and $state['generation'] -match '^[0-9a-f]{32}$') "verified full snapshot must publish: $(Get-StateBytes) $($full.Stderr)"
    Check ((Get-Property $full.Json 'CorpusGeneration') -eq $state['generation'] -and (Get-Property $full.Json 'CorpusStatePublished') -eq $true -and (Get-Property $full.Json 'CorpusState') -eq 'complete') 'output must carry the published generation'
    $generation1 = $state['generation']

    # A delta over a complete corpus publishes a new generation.
    $delta = Invoke-Sync $p2
    $state = Read-State
    Check ($delta.Code -eq 0 -and $state['state'] -eq 'complete' -and $state['generation'] -match '^[0-9a-f]{32}$' -and $state['generation'] -ne $generation1) 'delta over complete must publish a new generation'
    $generation2 = $state['generation']

    # A run blocked before mutating writes no state and no metadata.
    $blockedPackage = New-Package 'blocked' @(, @('Alpha', '2027-01-01T00:00:00Z', 'x', 'other-source'))
    $metadata = Join-Path $root 'kb-source-metadata.md'
    $before = Get-StateBytes
    $blocked = Invoke-Sync $blockedPackage @('-BlockCrossFlowDataSource', '-KbMetadataPath', $metadata)
    Check ($blocked.Code -ne 0 -and (Get-StateBytes) -eq $before -and -not (Test-Path -LiteralPath $metadata)) 'blocked run must not write state or metadata'

    # A failure after the first mutation leaves the corpus incomplete.
    $p3 = New-Package 'p3' @(@('Alpha', '2027-01-01T00:00:00Z', 'a3'), @('Gamma', '2027-01-01T00:00:00Z', 'g3'))
    $obstacle = Join-Path $corpus 'Attribute/Gamma.xml'
    [void][IO.Directory]::CreateDirectory($obstacle)
    $failed = Invoke-Sync $p3
    $state = Read-State
    Check ($failed.Code -ne 0 -and $state['state'] -eq 'incomplete') "failure after mutation must leave incomplete: $(Get-StateBytes)"
    Check ([IO.File]::ReadAllText((Join-Path $corpus 'Attribute/Alpha.xml')).Contains('description="a3"')) 'injected failure must happen after a real mutation'
    Check ($state['recoveryPackageSha256'] -eq (Get-Sha256 $p3) -and $failed.Stderr -match 're-run the same package' -and $failed.Stderr -match 'FullSnapshot') "a recovery package: the failure must offer the re-run: $($failed.Stderr)"

    # A delta from another package does not publish over an incomplete corpus.
    $other = Invoke-Sync $p2
    Check ($other.Code -eq 0 -and (Read-State)['state'] -eq 'incomplete' -and (Get-Property $other.Json 'CorpusStatePublished') -eq $false) 'other-package delta must not publish'
    $otherNote = [string](Get-Property $other.Json 'CorpusStateNote')
    Check ($otherNote -match 'Re-run the package that left it incomplete' -and $otherNote -match 'FullSnapshot' -and $other.Stderr -match 'Re-run the package that left it incomplete') "a recovery package: the note must still offer the re-run: $otherNote"

    # Re-running the package that left the corpus incomplete recovers it.
    [IO.Directory]::Delete($obstacle)
    $recovered = Invoke-Sync $p3
    $state = Read-State
    Check ($recovered.Code -eq 0 -and $state['state'] -eq 'complete' -and $state['generation'] -notin @($generation1, $generation2, $null)) "same-package re-run must publish: $(Get-StateBytes) $($recovered.Stderr)"

    # The incomplete state is written before the kb-source-metadata.md update.
    $p4 = New-Package 'p4' @(, @('Alpha', '2028-01-01T00:00:00Z', 'a4'))
    $badMetadata = Join-Path $root 'metadata-is-a-folder'
    [void][IO.Directory]::CreateDirectory($badMetadata)
    $metaFail = Invoke-Sync $p4 @('-KbMetadataPath', $badMetadata)
    Check ($metaFail.Code -ne 0 -and (Read-State)['state'] -eq 'incomplete') 'a failed metadata update must leave the corpus incomplete'
    Check ([IO.File]::ReadAllText((Join-Path $corpus 'Attribute/Alpha.xml')).Contains('description="a3"')) 'metadata failure must happen before XML writes'
    $metaRecovered = Invoke-Sync $p4
    Check ($metaRecovered.Code -eq 0 -and (Read-State)['state'] -eq 'complete') 'same package must recover after a metadata failure'

    # A held corpus lock fails sync and VerifyOnly fast with a clear message.
    $holderScript = ". '$($lockSupport -replace "'", "''")'; `$l = Enter-GeneXusCorpusLock -CorpusRoot '$($corpus -replace "'", "''")'; [Console]::Out.WriteLine('locked'); [Console]::Out.Flush(); [void][Console]::In.ReadLine(); Exit-GeneXusCorpusLock -Lock `$l"
    $psi = [Diagnostics.ProcessStartInfo]::new('pwsh')
    foreach ($a in @('-NoProfile', '-NonInteractive', '-Command', $holderScript)) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $holder = [Diagnostics.Process]::Start($psi)
    try {
        $line = $holder.StandardOutput.ReadLineAsync()
        if (-not $line.Wait(60000) -or $line.Result -ne 'locked') { throw 'lock holder did not start' }
        $before = Get-StateBytes
        $busy = Invoke-Sync $p2
        Check ($busy.Code -ne 0 -and $busy.Stdout -eq '' -and $busy.Stderr -match 'corpus is locked by another process') "held lock must fail sync with a clear message: $($busy.Stderr)"
        Check ($busy.Stderr -match 'an index query') "the lock message must name an index query as a possible holder: $($busy.Stderr)"
        $busyVerify = Invoke-Sync $p2 @('-VerifyOnly')
        Check ($busyVerify.Code -ne 0 -and $busyVerify.Stderr -match 'corpus is locked by another process') 'held lock must fail VerifyOnly'
        Check ((Get-StateBytes) -eq $before) 'contended runs changed the state'
    } finally {
        $holder.StandardInput.WriteLine('')
        $holder.StandardInput.Close()
        if (-not $holder.WaitForExit(60000)) { $holder.Kill($true) }
        $holder.Dispose()
    }

    # The inventory generator ignores .mimir-* files in the corpus.
    [IO.File]::WriteAllText((Join-Path $corpus 'Attribute/.mimir-xml-leftover.tmp'), 'partial', $encoding)
    $inventoryOut = Join-Path $root 'inventory/kb-inventory.md'
    $null = & pwsh -NoProfile -NonInteractive -File $inventory -SourceRoot $corpus -OutputPath $inventoryOut 2>&1
    Check ($LASTEXITCODE -eq 0 -and -not ([IO.File]::ReadAllText($inventoryOut).Contains('.mimir-'))) 'inventory must ignore .mimir-* files'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("FAIL: $_") }
    exit 1
}
Write-Output 'OK: corpus lock, state and generation'
