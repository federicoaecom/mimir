#requires -Version 7.4
<#
.SYNOPSIS
    End-to-end self-test of Get-GeneXusXpzObjectInventory.ps1 on GeneXus `.xpw` text exports.

.DESCRIPTION
    Runs the real inventory and sync as child processes over synthetic `.xpw` fixtures
    (tests/fixtures/GeneXusXpwFixtureSupport.ps1; every name is invented) and proves that:
    - a `.xpw` and a `.zip` of `.xpw` files (the 1997 split layout) are accepted
      (inputKind `xpw` / `xpw-zip`), legacyFormatDetected=true, every item is known-legacy, and
      the inventory lists the same items the sync writes for the same input;
    - a zip mixing `.xpw` and `.xml` entries is blocked with a clear message;
    - a `.zip` holding only an ExportFile XML keeps today's behaviour (inputKind `xpz`);
    - objects repeated inside one export (a `.zip` with two copies of the objects file): the
      inventory keeps objectCount and objectsByType as entries and adds distinctObjectCount,
      distinctObjectsByType and duplicatesInExport, with a warning; the sync writes each object
      once and reports the identical copies as RepeatedInExport (with RepeatedInExportNames), not
      as Unchanged; a copy that differs is still written last (Updated) and named in a warning.
    Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'GeneXusXpwFixtureSupport.ps1')

$inventoryScript = Join-Path $scriptsRoot 'Get-GeneXusXpzObjectInventory.ps1'
$syncScript = Join-Path $scriptsRoot 'Sync-GeneXusXpzToXml.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-WorkRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('xpw-inv-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $root)
    return $root
}

function Invoke-Inventory {
    param([string[]]$InvArgs)
    $stdout = & pwsh -NoProfile -File $inventoryScript @InvArgs 2>$null
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Json = (($stdout -join "`n") | ConvertFrom-Json) }
}

function Get-BlockingReasons {
    <# The blockingReasons of an inventory result, or '' when it has none (StrictMode-safe). #>
    param([object]$Json)
    if ($null -eq $Json -or $null -eq $Json.PSObject.Properties['blockingReasons']) { return '' }
    return (@($Json.blockingReasons) -join ' ')
}

function Get-SyncedNames {
    <# Syncs -InputPath into a fresh folder and returns the sorted "Folder:Name" list it created. #>
    param([string]$InputPath, [string]$WorkRoot)
    $dest = Join-Path $WorkRoot ('corpus-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $dest)
    $stdout = & pwsh -NoProfile -File $syncScript -InputPath $InputPath -DestinationRoot $dest 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "the sync of $InputPath should exit 0; got $LASTEXITCODE"
    $summary = @($stdout | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1] | ConvertFrom-Json
    return @($summary.CreatedNames | Sort-Object)
}

function Assert-InventoryMatchesSync {
    param([object]$Inventory, [string[]]$SyncedNames, [string]$Case)
    $items = @($Inventory.inventory)
    Assert-True ($items.Count -eq $SyncedNames.Count) "${Case}: inventory lists $($items.Count) items, the sync wrote $($SyncedNames.Count)."
    Assert-True (@($items | Where-Object { $_.typeStatus -ne 'known-legacy' }).Count -eq 0) "${Case}: every item should be known-legacy."
    $inventoryNames = @($items | ForEach-Object { $_.name } | Sort-Object)
    $syncNames = @($SyncedNames | ForEach-Object { $_.Substring($_.IndexOf(':') + 1) } | Sort-Object)
    Assert-True (($inventoryNames -join '|') -ceq ($syncNames -join '|')) "${Case}: inventory names [$($inventoryNames -join ', ')] differ from the synced names [$($syncNames -join ', ')]."
}

$work = New-WorkRoot
try {
    # Case 1 — a single .xpw.
    $xpw = New-GeneXusXpwFixtureFile -Path (Join-Path $work 'shop.xpw') -Lines (Get-GeneXusXpwSyncFixtureLines)
    $result = Invoke-Inventory -InvArgs @('-InputPath', $xpw)
    Assert-True ($result.ExitCode -eq 0) "Case1: inventory of a .xpw should exit 0; got $($result.ExitCode): $(Get-BlockingReasons $result.Json)"
    Assert-True ([bool]$result.Json.legacyFormatDetected) 'Case1: legacyFormatDetected should be true.'
    Assert-True ($result.Json.inputKind -eq 'xpw') "Case1: inputKind='$($result.Json.inputKind)' (expected xpw)."
    Assert-True ($result.Json.objectCount -eq 7 -and $result.Json.attributeCount -eq 2) "Case1: objects=$($result.Json.objectCount), attributes=$($result.Json.attributeCount) (expected 7 and 2)."
    Assert-InventoryMatchesSync -Inventory $result.Json -SyncedNames (Get-SyncedNames -InputPath $xpw -WorkRoot $work) -Case 'Case1'

    # Case 2 — a .zip with the 1997 split layout.
    $zip = New-GeneXusXpwFixtureZip -Path (Join-Path $work 'export.zip') -Entries ([ordered]@{ 'gxw.xpw' = (Get-GeneXusXpwObjectsFixtureLines); 'att.xpw' = (Get-GeneXusXpwAttributesFixtureLines) })
    $result = Invoke-Inventory -InvArgs @('-InputPath', $zip)
    Assert-True ($result.ExitCode -eq 0) "Case2: inventory of a .zip of .xpw should exit 0; got $($result.ExitCode): $(Get-BlockingReasons $result.Json)"
    Assert-True ($result.Json.inputKind -eq 'xpw-zip') "Case2: inputKind='$($result.Json.inputKind)' (expected xpw-zip)."
    Assert-True ($result.Json.objectCount -eq 8 -and $result.Json.attributeCount -eq 2) "Case2: objects=$($result.Json.objectCount), attributes=$($result.Json.attributeCount) (expected 8 and 2)."
    Assert-InventoryMatchesSync -Inventory $result.Json -SyncedNames (Get-SyncedNames -InputPath $zip -WorkRoot $work) -Case 'Case2'

    # Case 3 — a zip mixing .xpw and .xml is blocked.
    $mixed = New-GeneXusXpwFixtureZip -Path (Join-Path $work 'mixed.zip') -Entries ([ordered]@{ 'gxw.xpw' = (Get-GeneXusXpwObjectsFixtureLines); 'export.xml' = @('<ExportFile/>') })
    $result = Invoke-Inventory -InvArgs @('-InputPath', $mixed)
    Assert-True ($result.ExitCode -eq 20 -and $result.Json.status -eq 'blocked') "Case3: a mixed zip should be blocked (exit 20); got $($result.ExitCode) $($result.Json.status)."
    Assert-True ((Get-BlockingReasons $result.Json) -match 'mixes \.xpw and \.xml entries') "Case3: the block should say the zip mixes .xpw and .xml entries; got: $(Get-BlockingReasons $result.Json)"

    # Case 5 — every object but the Group repeated by an identical second objects file (a repeated
    # Group or ungrouped Subtype stays blocked by the legacy rule).
    $objects = Get-GeneXusXpwObjectsFixtureLines
    $inGroup = $false
    $copy = @($objects | Where-Object {
            if ($_ -eq ':Group') { $inGroup = $true }
            $keep = -not $inGroup
            if ($_ -eq ':eGroup') { $inGroup = $false }
            $keep
        })
    $dupZip = New-GeneXusXpwFixtureZip -Path (Join-Path $work 'dup.zip') -Entries ([ordered]@{ 'gxw.xpw' = $objects; 'gxw-copy.xpw' = $copy; 'att.xpw' = (Get-GeneXusXpwAttributesFixtureLines) })
    $result = Invoke-Inventory -InvArgs @('-InputPath', $dupZip)
    Assert-True ($result.ExitCode -eq 0) "Case5: inventory should exit 0; got $($result.ExitCode): $(Get-BlockingReasons $result.Json)"
    $json = $result.Json
    Assert-True ($json.objectCount -eq 15) "Case5: objectCount counts entries (expected 15); got $($json.objectCount)."
    Assert-True ($null -ne $json.PSObject.Properties['distinctObjectCount'] -and $json.distinctObjectCount -eq 8) "Case5: distinctObjectCount should be 8; got $($json | Select-Object -ExpandProperty distinctObjectCount -ErrorAction SilentlyContinue)."
    Assert-True ($null -ne $json.PSObject.Properties['duplicatesInExport'] -and $json.duplicatesInExport.count -eq 7 -and @($json.duplicatesInExport.items).Count -eq 7) "Case5: duplicatesInExport should report 7 extra copies of 7 objects."
    Assert-True (@($json.duplicatesInExport.items | Where-Object { $_.copies -ne 2 }).Count -eq 0) 'Case5: each repeated object has 2 copies.'
    $distinctTransactions = $json.distinctObjectsByType.PSObject.Properties['Transaction'].Value
    $entryTransactions = $json.objectsByType.PSObject.Properties['Transaction'].Value
    Assert-True ($distinctTransactions * 2 -eq $entryTransactions) "Case5: distinctObjectsByType.Transaction ($distinctTransactions) should be half of objectsByType.Transaction ($entryTransactions)."
    Assert-True (@($json.warnings | Where-Object { "$_" -match 'repeated inside the export' }).Count -eq 1) "Case5: one warning should name the in-export repeats; got: $(@($json.warnings) -join ' | ')"
    $dest = Join-Path $work 'corpus-dup'
    [void](New-Item -ItemType Directory -Path $dest)
    $stdout = & pwsh -NoProfile -File $syncScript -InputPath $dupZip -DestinationRoot $dest 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "Case5: sync should exit 0; got $LASTEXITCODE"
    $summary = @($stdout | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1] | ConvertFrom-Json
    Assert-True ($summary.Created -eq 10 -and $summary.Unchanged -eq 0) "Case5: sync should create the 8 objects and 2 attributes once with nothing Unchanged; got Created=$($summary.Created) Unchanged=$($summary.Unchanged)."
    Assert-True ($null -ne $summary.PSObject.Properties['RepeatedInExport'] -and $summary.RepeatedInExport -eq 7 -and @($summary.RepeatedInExportNames).Count -eq 7) "Case5: RepeatedInExport should be 7 with 7 names; got $($summary | Select-Object -ExpandProperty RepeatedInExport -ErrorAction SilentlyContinue)."
    Assert-True (@($summary.CreatedNames).Count -eq (@($summary.CreatedNames | Sort-Object -Unique)).Count) 'Case5: CreatedNames should hold each object once.'

    # Case 6 — the same, with one copy of TrnCustomer that differs.
    $changed = @($copy | ForEach-Object { if ($_ -eq '  Tag=second') { '  Tag=changed' } else { $_ } })
    $diffZip = New-GeneXusXpwFixtureZip -Path (Join-Path $work 'diff.zip') -Entries ([ordered]@{ 'gxw.xpw' = $objects; 'gxw-copy.xpw' = $changed; 'att.xpw' = (Get-GeneXusXpwAttributesFixtureLines) })
    $dest = Join-Path $work 'corpus-diff'
    [void](New-Item -ItemType Directory -Path $dest)
    $stdout = & pwsh -NoProfile -File $syncScript -InputPath $diffZip -DestinationRoot $dest 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "Case6: sync should exit 0; got $LASTEXITCODE"
    $summary = @($stdout | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1] | ConvertFrom-Json
    Assert-True ($summary.RepeatedInExport -eq 6 -and $summary.Updated -eq 1 -and @($summary.UpdatedNames) -contains 'Transaction:TrnCustomer') "Case6: 6 identical repeats and TrnCustomer updated by its differing copy; got RepeatedInExport=$($summary.RepeatedInExport) Updated=$($summary.Updated) [$(@($summary.UpdatedNames) -join ', ')]."
    Assert-True (@($summary.Warnings | Where-Object { "$_" -match 'differing copies' -and "$_" -match 'Transaction:TrnCustomer' }).Count -eq 1) "Case6: a warning should name the differing copies of Transaction:TrnCustomer; got: $(@($summary.Warnings) -join ' | ')"

    # Case 7 — copies in the order original, changed, original: each copy is compared with the one
    # written last, so the final original is written again and wins, as it did before (zip entries
    # are read in name order, hence the numbered names).
    $abaZip = New-GeneXusXpwFixtureZip -Path (Join-Path $work 'aba.zip') -Entries ([ordered]@{ '1-objects.xpw' = $objects; '2-changed.xpw' = $changed; '3-original.xpw' = $copy; 'att.xpw' = (Get-GeneXusXpwAttributesFixtureLines) })
    $dest = Join-Path $work 'corpus-aba'
    [void](New-Item -ItemType Directory -Path $dest)
    $stdout = & pwsh -NoProfile -File $syncScript -InputPath $abaZip -DestinationRoot $dest 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "Case7: sync should exit 0; got $LASTEXITCODE"
    $summary = @($stdout | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1] | ConvertFrom-Json
    Assert-True ($summary.RepeatedInExport -eq 12 -and $summary.Updated -eq 2) "Case7: 12 identical repeats and TrnCustomer written twice more (changed, then original); got RepeatedInExport=$($summary.RepeatedInExport) Updated=$($summary.Updated)."
    $customerXml = [System.IO.File]::ReadAllText((Get-ChildItem -LiteralPath $dest -Recurse -File -Filter 'TrnCustomer.xml' | Select-Object -First 1).FullName)
    Assert-True ($customerXml -notmatch 'changed') 'Case7: the last copy (the original) should win; the corpus file still holds the changed copy.'

    # Case 4 — a .zip holding only an ExportFile XML keeps today's behaviour.
    $xmlOnly = New-GeneXusXpwFixtureZip -Path (Join-Path $work 'xml-only.zip') -Entries ([ordered]@{ 'export.xml' = @('<ExportFile><Objects/></ExportFile>') })
    $result = Invoke-Inventory -InvArgs @('-InputPath', $xmlOnly)
    Assert-True ($result.ExitCode -eq 0 -and $result.Json.inputKind -eq 'xpz' -and $result.Json.innerXmlEntry -eq 'export.xml') "Case4: a .zip with only XML should keep inputKind xpz; got exit $($result.ExitCode), inputKind '$($result.Json.inputKind)'."
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Write-Output 'MIMIR_INVENTORY_XPW_SELFTEST_OK'
exit 0
