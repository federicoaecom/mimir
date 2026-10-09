#requires -Version 7.4
<#
.SYNOPSIS
    End-to-end self-test of the legacy branch of Get-GeneXusXpzObjectInventory.ps1.

.DESCRIPTION
    Exercises the real INTEGRATION (child process pwsh -File) of the Inventory over the
    iso-8859-1 fixture generated on-the-fly, locking down the legacy-profile contract
    end to end (the support script's own self-test covers it in isolation):
    - pure-legacy profile detected: legacyFormatDetected=true; known-legacy items with
      synthetic rootKind Object/Attribute; equivalent -> real typeName (Transaction, Menubar),
      orphan -> typeName gxlegacy/Report; guid=null;
    - unknownTypeCount=0 and unknownTypesDiscovery=[] (statement form: the tag fail-closed
      lives in the parser, not in modern GUID-based discovery; guards against a regression
      of the StrictMode if-expression @()->null gotcha);
    - MIXED package -> BLOCK (exit != 0), neither materializes nor inventories.
    Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'GeneXusLegacyExportFileFixtureSupport.ps1')

$inventoryScript = Join-Path $scriptsRoot 'Get-GeneXusXpzObjectInventory.ps1'

function New-WorkRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('legacy-inv-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $root)
    return $root
}

function Write-Iso88591File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::GetEncoding('iso-8859-1'))
}

function Invoke-InventoryJson {
    <# Runs the Inventory and returns the JSON object from stdout. Throws if exit != 0. #>
    param([string[]]$InvArgs)
    $stdout = & pwsh -NoProfile -File $inventoryScript @InvArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Inventory returned exit $LASTEXITCODE (expected 0). Args: $($InvArgs -join ' ')"
    }
    return (($stdout -join "`n") | ConvertFrom-Json)
}

function Invoke-InventoryExpectBlock {
    <# Runs the Inventory and requires exit != 0 (fail-closed). #>
    param([string[]]$InvArgs)
    & pwsh -NoProfile -File $inventoryScript @InvArgs 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        throw "Inventory should have failed (exit != 0), but returned 0. Args: $($InvArgs -join ' ')"
    }
}

# =====================================================================================
# Case 1 — pure-legacy profile: known-legacy, unknownTypeCount=0, empty discovery
# =====================================================================================
$work1 = New-WorkRoot
try {
    $fixture = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $work1 'legacy.xml')
    $inv = Invoke-InventoryJson -InvArgs @('-InputPath', $fixture)

    if (-not $inv.legacyFormatDetected) { throw 'Case1: legacyFormatDetected should be true.' }
    if ($inv.objectCount -ne 5) { throw "Case1: objectCount=$($inv.objectCount) (expected 5)." }
    if ($inv.attributeCount -ne 2) { throw "Case1: attributeCount=$($inv.attributeCount) (expected 2)." }
    if ($inv.unknownTypeCount -ne 0) { throw "Case1: unknownTypeCount=$($inv.unknownTypeCount) (expected 0)." }
    if (@($inv.unknownTypesDiscovery).Count -ne 0) { throw "Case1: unknownTypesDiscovery should be empty (got $(@($inv.unknownTypesDiscovery).Count))." }

    foreach ($item in $inv.inventory) {
        if ($item.typeStatus -ne 'known-legacy') { throw "Case1: item '$($item.name)' typeStatus='$($item.typeStatus)' (expected known-legacy)." }
        if ($null -ne $item.guid) { throw "Case1: item '$($item.name)' guid should be null." }
        if ([string]::IsNullOrWhiteSpace([string]$item.legacyElement)) { throw "Case1: item '$($item.name)' has no legacyElement." }
    }

    $cliente = @($inv.inventory | Where-Object { $_.name -eq 'Cliente' })
    if ($cliente.Count -ne 1 -or $cliente[0].type -ne 'Transaction' -or $cliente[0].rootKind -ne 'Object') { throw 'Case1: equivalent Transaction Cliente misclassified.' }
    $relmov = @($inv.inventory | Where-Object { $_.name -eq 'RelMov' })
    if ($relmov.Count -ne 1 -or $relmov[0].type -ne 'gxlegacy/Report') { throw "Case1: orphan Report RelMov type='$($relmov[0].type)' (expected gxlegacy/Report)." }
    $menu = @($inv.inventory | Where-Object { $_.name -eq 'MenuPrincipal' })
    if ($menu.Count -ne 1 -or $menu[0].type -ne 'Menubar') { throw "Case1: equivalent Menubar type='$($menu[0].type)' (expected Menubar)." }
    $attr = @($inv.inventory | Where-Object { $_.rootKind -eq 'Attribute' })
    if ($attr.Count -ne 2) { throw "Case1: expected 2 known-legacy attributes, got $($attr.Count)." }
} finally {
    if (Test-Path -LiteralPath $work1) { Remove-Item -LiteralPath $work1 -Recurse -Force }
}

# =====================================================================================
# Case 2 — MIXED package -> BLOCK (exit != 0)
# =====================================================================================
$work2 = New-WorkRoot
try {
    $mixed = Join-Path $work2 'misto.xml'
    Write-Iso88591File -Path $mixed -Content @'
<?xml version='1.0' encoding='iso-8859-1'?>
<ExportFile>
  <GXObject><Transaction><Info><Name>Cliente</Name></Info></Transaction></GXObject>
  <Objects><Object type="00000000-0000-0000-0000-000000000001" name="Moderno"/></Objects>
</ExportFile>
'@
    Invoke-InventoryExpectBlock -InvArgs @('-InputPath', $mixed)
} finally {
    if (Test-Path -LiteralPath $work2) { Remove-Item -LiteralPath $work2 -Recurse -Force }
}

Write-Output 'MIMIR_INVENTORY_LEGACY_EXPORT_SELFTEST_OK'
exit 0
