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
    - a `.zip` holding only an ExportFile XML keeps today's behaviour (inputKind `xpz`).
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

    # Case 4 — a .zip holding only an ExportFile XML keeps today's behaviour.
    $xmlOnly = New-GeneXusXpwFixtureZip -Path (Join-Path $work 'xml-only.zip') -Entries ([ordered]@{ 'export.xml' = @('<ExportFile><Objects/></ExportFile>') })
    $result = Invoke-Inventory -InvArgs @('-InputPath', $xmlOnly)
    Assert-True ($result.ExitCode -eq 0 -and $result.Json.inputKind -eq 'xpz' -and $result.Json.innerXmlEntry -eq 'export.xml') "Case4: a .zip with only XML should keep inputKind xpz; got exit $($result.ExitCode), inputKind '$($result.Json.inputKind)'."
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Write-Output 'MIMIR_INVENTORY_XPW_SELFTEST_OK'
exit 0
