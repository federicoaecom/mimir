#requires -Version 7.4
<#
.SYNOPSIS
    Exercises the workspace GUID-cleanup migration contract with synthetic data.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$engine = Join-Path $repo 'skills/mimir-lite/scripts/Sync-GeneXusXpzToXml.ps1'
$template = Join-Path $repo 'skills/mimir-lite/workflows/setup/examples/Update-KbFromXpz.example.ps1'
$auditor = Join-Path $repo 'skills/mimir-lite/scripts/Test-MimirWrapperInventory.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('mimir-guid-contract-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)
$failures = [Collections.Generic.List[string]]::new()
function Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}
function Invoke-Child([string]$Path, [string[]]$Arguments) {
    $err = Join-Path $root ('stderr-' + [guid]::NewGuid().ToString('N'))
    $out = @(& pwsh -NoProfile -NonInteractive -File $Path @Arguments 2>$err)
    $code = $LASTEXITCODE
    $stderr = [IO.File]::ReadAllText($err)
    return [pscustomobject]@{ Exit = $code; Out = ($out -join "`n"); Err = $stderr }
}
function Write-Text([string]$Path, [string]$Value) {
    [IO.File]::WriteAllText($Path, $Value, $utf8)
}
try {
    [void][IO.Directory]::CreateDirectory($root)
    $ws = Join-Path $root 'workspace'
    $scripts = Join-Path $ws 'scripts'
    $corpus = Join-Path $ws 'KbObjectsXml'
    [void][IO.Directory]::CreateDirectory((Join-Path $corpus 'Procedure'))
    [void][IO.Directory]::CreateDirectory((Join-Path $corpus 'Transaction'))
    [void][IO.Directory]::CreateDirectory($scripts)
    $guid = '11111111-1111-1111-1111-111111111111'
    $type = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
    $otherType = '1db606f2-af09-4cf9-a3b5-b481519d28f6'
    $node = "<Object type=`"$type`" guid=`"$guid`" name=`"Alpha`" lastUpdate=`"2026-01-01T00:00:00Z`" />"
    $other = "<Object type=`"$otherType`" guid=`"$guid`" name=`"Beta`" lastUpdate=`"2025-01-01T00:00:00Z`" />"
    $one = Join-Path $corpus 'Procedure/Alpha.xml'
    $two = Join-Path $corpus 'Transaction/Beta.xml'
    Write-Text $one "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n$node"
    Write-Text $two "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n$other"
    $beforeOne = [IO.File]::ReadAllBytes($one)
    $beforeTwo = [IO.File]::ReadAllBytes($two)
    $package = Join-Path $root 'package.xml'
    Write-Text $package "<ExportFile><Objects>$node</Objects><Attributes /></ExportFile>"
    $metadata = Join-Path $ws 'kb-source-metadata.md'
    $report = Join-Path $root 'report.json'
    $base = @('-InputPath', $package, '-DestinationRoot', $corpus, '-KbWorkspaceRoot', $ws, '-KbMetadataPath', $metadata)
    $legacy = Invoke-Child $engine ($base + @('-ReportPath', $report, '-KeepReport'))
    Write-Output "LEGACY exit=$($legacy.Exit) stdout=[$($legacy.Out)] stderr=[$($legacy.Err.Trim())]"
    Check ($legacy.Exit -ne 0) 'legacy workspace write must fail'
    Check ($legacy.Out -eq '') 'rejected workspace write must have empty stdout'
    Check ($legacy.Err -match 'GuidCleanupContractVersion 1' -and $legacy.Err -match 'wrapper') 'rejection must explain migration'
    Check (-not (Test-Path $metadata) -and -not (Test-Path $report)) 'rejection must not create metadata or report'
    Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($one)) -eq [Convert]::ToBase64String($beforeOne)) 'rejection changed first corpus file'
    Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($two)) -eq [Convert]::ToBase64String($beforeTwo)) 'rejection changed second corpus file'
    $invalid = Invoke-Child $engine ($base + @('-GuidCleanupContractVersion', '2'))
    Check ($invalid.Exit -ne 0 -and $invalid.Out -eq '') 'unknown contract must fail without stdout'
    $verify = Invoke-Child $engine ($base + @('-VerifyOnly'))
    Check ($verify.Exit -eq 0 -and (($verify.Out | ConvertFrom-Json).Kind -eq 'mimir-sync-result')) 'legacy VerifyOnly must remain usable'
    $verifyJson = $verify.Out | ConvertFrom-Json
    Check (@($verifyJson.CrossTypeGuidCollisions).Count -eq 1) 'VerifyOnly must report the cross-type GUID group'
    Check (@($verifyJson.GuidRemovedFiles).Count -eq 0) 'VerifyOnly must not report removals'
    Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($one)) -eq [Convert]::ToBase64String($beforeOne)) 'VerifyOnly changed first file'
    Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($two)) -eq [Convert]::ToBase64String($beforeTwo)) 'VerifyOnly changed second file'
    Check (-not (Test-Path $metadata)) 'VerifyOnly created metadata'
    $standalone = Join-Path $root 'standalone'
    $stand = Invoke-Child $engine @('-InputPath', $package, '-DestinationRoot', $standalone)
    Check ($stand.Exit -eq 0 -and (Test-Path (Join-Path $standalone 'Procedure/Alpha.xml'))) 'standalone sync must remain usable'
    $positionalRoot = Join-Path $root 'standalone-positional'
    $discoveryPath = Join-Path $root 'positional-discovery.json'
    $legacyArgs = @($package, $positionalRoot, '', @(), '', '', '', '', $discoveryPath)
    try {
        $positional = (& $engine @legacyArgs 2>$null) | ConvertFrom-Json
        Check ($positional.Kind -eq 'mimir-sync-result' -and
            (Test-Path (Join-Path $positionalRoot 'Procedure/Alpha.xml'))) 'legacy positional standalone sync must remain usable'
    } catch {
        $failures.Add("legacy positional standalone sync failed: $($_.Exception.Message)")
    }
    $declared = Invoke-Child $engine ($base + @('-GuidCleanupContractVersion', '1', '-ReportPath', $report, '-KeepReport'))
    Check ($declared.Exit -eq 0 -and (($declared.Out | ConvertFrom-Json).Kind -eq 'mimir-sync-result')) 'declared workspace sync must succeed'
    $declaredJson = $declared.Out | ConvertFrom-Json
    $collision = @($declaredJson.CrossTypeGuidCollisions)
    Check ($collision.Count -eq 1 -and $collision[0].Guid -eq $guid) 'sync must report the GUID collision'
    Check (($collision[0].Files.FilePath -join '|') -eq (@($one, $two) -join '|')) 'collision files must be sorted and include both paths'
    $reportJson = [IO.File]::ReadAllText($report) | ConvertFrom-Json
    Check (($reportJson.Summary.CrossTypeGuidCollisions | ConvertTo-Json -Depth 8 -Compress) -eq ($declaredJson.CrossTypeGuidCollisions | ConvertTo-Json -Depth 8 -Compress)) 'report must contain the same collision observation'
    Check ((Test-Path $one) -and (Test-Path $two)) 'sync must retain cross-type files'
    $again = Invoke-Child $engine ($base + @('-GuidCleanupContractVersion', '1'))
    $againJson = $again.Out | ConvertFrom-Json
    Check ($again.Exit -eq 0 -and (($againJson.CrossTypeGuidCollisions | ConvertTo-Json -Depth 8 -Compress) -eq ($collision | ConvertTo-Json -Depth 8 -Compress))) 'collision observation must be deterministic on repeat'
    Check (@($againJson.GuidRemovedFiles).Count -eq 0) 'repeat must not report removals'
    $wrapper = Join-Path $scripts 'Update-SampleKbFromXpz.ps1'
    Copy-Item -LiteralPath $template -Destination $wrapper
    $index = Join-Path $scripts 'index.ps1'
    $marker = Join-Path $ws 'index-refreshed'
    Write-Text $index "param([string]`$SharedSkillsRoot)`n[IO.File]::WriteAllText('$($marker.Replace("'", "''"))', 'refreshed')`n"
    $newNode = "<Object type=`"$type`" guid=`"22222222-2222-2222-2222-222222222222`" name=`"Gamma`" lastUpdate=`"2026-01-01T00:00:00Z`" />"
    Write-Text $package "<ExportFile><Objects>$node$newNode</Objects><Attributes /></ExportFile>"
    $run = Invoke-Child $wrapper @('-InputPath', $package, '-SharedSkillsRoot', $repo, '-IndexUpdateScriptPath', $index)
    Write-Output "WRAPPER exit=$($run.Exit) stdout=[$($run.Out)] stderr=[$($run.Err.Trim())]"
    Check ($run.Exit -eq 0 -and (($run.Out | ConvertFrom-Json).Kind -eq 'mimir-sync-result')) 'current wrapper must produce sync JSON'
    Check ((Test-Path $one) -and (Test-Path $two)) 'wrapper must preserve cross-type same-GUID files'
    Check (Test-Path $marker) 'wrapper must refresh the index'
    Check ($run.Err -match 'Git repository not found.*local summary skipped') 'material change must trigger the Git summary'
    # A late engine failure must not reach the wrapper's index refresh.
    $attrs = Join-Path $corpus 'Attribute'
    [void][IO.Directory]::CreateDirectory($attrs)
    $g2 = '22222222-2222-2222-2222-222222222222'
    $g3 = '33333333-3333-3333-3333-333333333333'
    foreach ($entry in @(@('OldA', $guid), @('NewA', $guid), @('OldB', $g2), @('NewB', $g3))) {
        Write-Text (Join-Path $attrs ($entry[0] + '.xml')) "<Attribute name=`"$($entry[0])`" guid=`"$($entry[1])`" lastUpdate=`"2020-01-01T00:00:00Z`"/>"
    }
    Write-Text $package "<ExportFile><Objects/><Attributes><Attribute name=`"NewA`" guid=`"$guid`" lastUpdate=`"2026-01-01T00:00:00Z`"/><Attribute name=`"NewB`" guid=`"$g2`" lastUpdate=`"2026-01-01T00:00:00Z`"/></Attributes></ExportFile>"
    $lateMarker = Join-Path $ws 'late-index-refreshed'
    Write-Text $index "param([string]`$SharedSkillsRoot)`n[IO.File]::WriteAllText('$($lateMarker.Replace("'", "''"))', 'refreshed')`n"
    $lateReport = Join-Path $root 'late-report.json'
    $late = Invoke-Child $wrapper @('-InputPath', $package, '-SharedSkillsRoot', $repo, '-IndexUpdateScriptPath', $index, '-FullSnapshot', '-ReportPath', $lateReport, '-KeepReport')
    Check ($late.Exit -ne 0 -and $late.Err -match 'Name collision in the corpus') 'late wrapper sync must fail with the original diagnostic'
    Check (-not (Test-Path $lateMarker)) 'late failure must not refresh the index'
    Check (-not (Test-Path (Join-Path $attrs 'OldA.xml'))) 'late wrapper scenario must actually remove the eligible orphan'
    Check ((Test-Path $lateReport) -and ((Get-Content -LiteralPath $lateReport -Raw | ConvertFrom-Json).Summary.Status -eq 'failed')) 'late wrapper failure must retain the failure report'
    $examples = Join-Path $root 'examples'
    [void][IO.Directory]::CreateDirectory($examples)
    Copy-Item -LiteralPath $template -Destination (Join-Path $examples 'Update-KbFromXpz.example.ps1')
    $audit = Invoke-Child $auditor @('-KbWorkspaceRoot', $ws, '-SkillsExamplesPath', $examples)
    Check ($audit.Exit -eq 0 -and $audit.Out -notmatch 'guid_cleanup_contract') 'current wrapper must pass contract audit'
    $old = [IO.File]::ReadAllText($wrapper) -replace '(?m)^\s*GuidCleanupContractVersion\s*=\s*1\s*\r?\n', ''
    Write-Text $wrapper $old
    $auditOld = Invoke-Child $auditor @('-KbWorkspaceRoot', $ws, '-SkillsExamplesPath', $examples)
    Check ($auditOld.Out -match 'guid_cleanup_contract') 'old wrapper must be flagged by inventory audit'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($failures.Count) { throw ("GUID cleanup contract failures:`n - " + ($failures -join "`n - ")) }
Write-Output 'MIMIR_GUID_CLEANUP_CONTRACT_OK'
