#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: a classic Menu is indexed as its own type and each option calls its program.

.DESCRIPTION
    Builds a synthetic KB of classic objects (root dataSource="gx-legacy-export") with two Menu
    objects (type token gxlegacy/Menu, options in <MenuOptions> with PgmType and PgmName) and
    proves that:
      - the Menu folder is indexed, not skipped as a legacy orphan, and object-info finds a Menu;
      - each option whose PgmType is Menu, WorkPanel, Transaction, or Report and whose PgmName names
        an indexed object of that type relates the Menu to it (calls_menu, calls_workpanel,
        calls_transaction, calls_report; rule classic_menu_option; the line of the option's PgmName);
      - who-uses on the called object lists the Menu, including a Menu called from another Menu;
      - a PgmType with a space (Work Panel) and a PgmName in another case resolve, and two options
        that call the same program give one relation each, with its own line (one per call site, as
        for the other call extractors);
      - an option whose PgmName names no indexed object, and an option with an unmapped PgmType
        (Procedure, not seen in a sample), give no relation.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')
$enc = Get-Utf8NoBomEncoding

$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'

$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$transactionGuid = '1db606f2-af09-4cf9-a3b5-b481519d28f6'
$workPanelGuid = '198e8ea4-1d49-4c9c-8a9a-417024baa9d1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-ClassicXml {
    param([string]$Type, [string]$Name, [string]$RootElement, [string]$Body)
    return @"
<Object type="$Type" name="$Name" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<$RootElement>
  <Info><Name>$Name</Name></Info>
$Body
</$RootElement>
  </GxLegacyPayload>
</Object>
"@
}

function New-MenuOptions {
    param([object[]]$Options)
    $lines = for ($i = 0; $i -lt $Options.Count; $i++) {
        "  <MenuOptions><OptionCode>$($i + 1)</OptionCode><PgmType>$($Options[$i][0])</PgmType><PgmName>$($Options[$i][1])</PgmName><Description>Option $($i + 1)</Description></MenuOptions>"
    }
    return ($lines -join "`n")
}

function Get-LineNumberOf {
    param([string]$Text, [string]$Needle)
    $lines = $Text -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Contains($Needle)) { return $i + 1 }
    }
    throw "Fixture text has no line with '$Needle'"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-menu-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
$folders = @{}
foreach ($folder in @('Menu', 'WorkPanel', 'Transaction', 'Report', 'Procedure')) {
    $folders[$folder] = Join-Path $kbObjectsPath $folder
}
[void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)

function Write-Fixture {
    param([string]$Folder, [string]$Name, [string]$Xml)
    [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
}

$mainMenuXml = New-ClassicXml -Type 'gxlegacy/Menu' -Name 'MnuMain' -RootElement 'Menu' -Body (New-MenuOptions @(
    @('WorkPanel', 'WkOrders'),
    @('Transaction', 'Customer'),
    @('Menu', 'MnuSub'),
    @('Report', 'RptSales'),
    @('WorkPanel', 'WkMissing'),
    @('Procedure', 'PrcBatch')
))
Write-Fixture 'Menu' 'MnuMain' $mainMenuXml
$subMenuXml = New-ClassicXml -Type 'gxlegacy/Menu' -Name 'MnuSub' -RootElement 'Menu' -Body (New-MenuOptions @(
    @('Work Panel', 'wkorders'),
    @('WorkPanel', 'WkOrders')
))
Write-Fixture 'Menu' 'MnuSub' $subMenuXml
Write-Fixture 'WorkPanel' 'WkOrders' (New-ClassicXml -Type $workPanelGuid -Name 'WkOrders' -RootElement 'WorkPanel' -Body '')
Write-Fixture 'Transaction' 'Customer' (New-ClassicXml -Type $transactionGuid -Name 'Customer' -RootElement 'Transaction' -Body '')
Write-Fixture 'Report' 'RptSales' (New-ClassicXml -Type 'gxlegacy/Report' -Name 'RptSales' -RootElement 'Report' -Body '')
Write-Fixture 'Procedure' 'PrcBatch' (New-ClassicXml -Type $procedureGuid -Name 'PrcBatch' -RootElement 'Procedure' -Body '')

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
& $buildScript -SourceRoot $kbObjectsPath -OutputPath $sqlitePath -ValidationReportPath $validationPath `
    -FailOnValidationFailure -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete with classic Menus; exit $LASTEXITCODE"

# Rule: the Menu folder is indexed, not skipped.
$inventory = (Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json).inventory_semantics
Assert-True (@(@($inventory.legacy_orphan_directories_skipped) | Where-Object { $_.directory -eq 'Menu' }).Count -eq 0) 'The Menu folder should not be skipped as a legacy orphan'
Assert-True (@($inventory.indexed_objects_by_type.PSObject.Properties.Name) -contains 'Menu') 'Menu should be indexed as its own type'

function Invoke-IndexQuery {
    param([string]$Query, [string]$Type, [string]$Name)
    $output = & $queryScript -IndexPath $sqlitePath -KbWorkspaceRoot $kbWorkspaceRoot -Query $Query `
        -ObjectType $Type -ObjectName $Name -Format json 2>&1
    $exitCode = $LASTEXITCODE
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($stdout)) {
        throw "ASSERT FAILED: $Query $Type $Name returned no output (exit $exitCode). stderr: $stderr"
    }
    try { $json = $stdout | ConvertFrom-Json }
    catch { throw "ASSERT FAILED: $Query $Type $Name did not return JSON (exit $exitCode). stderr: $stderr" }
    Assert-True ($exitCode -eq 0) "$Query $Type $Name should exit 0; got $exitCode. output: $stdout $stderr"
    return $json
}

function Format-Rows {
    param($Rows)
    return (@($Rows) | ForEach-Object { "$($_.source_type) $($_.source_name) -> $($_.target_type) $($_.target_name) $($_.relation_kind)" }) -join '; '
}

# Rule: object-info finds a Menu.
$info = Invoke-IndexQuery -Query 'object-info' -Type 'Menu' -Name 'MnuMain'
Assert-True ($info.found -eq $true) 'object-info Menu MnuMain should find the Menu'

# Rule: each mapped option relates the Menu to its program, with the line of its PgmName.
$mainRows = @((Invoke-IndexQuery -Query 'what-uses' -Type 'Menu' -Name 'MnuMain').results)
$expected = @(
    @{ Type = 'WorkPanel'; Name = 'WkOrders'; Kind = 'calls_workpanel' },
    @{ Type = 'Transaction'; Name = 'Customer'; Kind = 'calls_transaction' },
    @{ Type = 'Menu'; Name = 'MnuSub'; Kind = 'calls_menu' },
    @{ Type = 'Report'; Name = 'RptSales'; Kind = 'calls_report' }
)
foreach ($target in $expected) {
    $row = @($mainRows | Where-Object { $_.target_type -eq $target.Type -and $_.target_name -eq $target.Name -and $_.relation_kind -eq $target.Kind })
    Assert-True ($row.Count -eq 1) "what-uses Menu MnuMain should list $($target.Type) $($target.Name) ($($target.Kind)); got: $(Format-Rows $mainRows)"
    Assert-True ($row[0].extractor_rule -eq 'classic_menu_option') "$($target.Type) $($target.Name) should relate with classic_menu_option; got $($row[0].extractor_rule)"
    $expectedLine = Get-LineNumberOf $mainMenuXml "<PgmName>$($target.Name)</PgmName>"
    Assert-True ($row[0].line -eq $expectedLine) "$($target.Type) $($target.Name) evidence should carry line $expectedLine; got $($row[0].line)"
}

# Rule: an unresolved PgmName and an unmapped PgmType give no relation.
Assert-True (@($mainRows | Where-Object { $_.target_name -in @('WkMissing', 'PrcBatch') }).Count -eq 0) "WkMissing and the Procedure option should give no relation; got: $(Format-Rows $mainRows)"
Assert-True ($mainRows.Count -eq 4) "what-uses Menu MnuMain should list exactly the 4 mapped options; got: $(Format-Rows $mainRows)"

# Rule: who-uses lists the Menus that call an object, a Menu called from a Menu included.
$orderCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'WorkPanel' -Name 'WkOrders').results)
foreach ($menu in @(@{ Name = 'MnuMain'; Count = 1 }, @{ Name = 'MnuSub'; Count = 2 })) {
    Assert-True (@($orderCallers | Where-Object { $_.source_type -eq 'Menu' -and $_.source_name -eq $menu.Name -and $_.relation_kind -eq 'calls_workpanel' }).Count -eq $menu.Count) "who-uses WorkPanel WkOrders should list Menu $($menu.Name) $($menu.Count) time(s); got: $(Format-Rows $orderCallers)"
}
$subCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Menu' -Name 'MnuSub').results)
Assert-True (@($subCallers | Where-Object { $_.source_type -eq 'Menu' -and $_.source_name -eq 'MnuMain' -and $_.relation_kind -eq 'calls_menu' }).Count -eq 1) "who-uses Menu MnuSub should list Menu MnuMain (calls_menu); got: $(Format-Rows $subCallers)"

# Rule: 'Work Panel' and a PgmName in another case resolve; each option is its own call site.
$subRows = @((Invoke-IndexQuery -Query 'what-uses' -Type 'Menu' -Name 'MnuSub').results)
Assert-True ($subRows.Count -eq 2 -and @($subRows | Where-Object { $_.target_name -eq 'WkOrders' -and $_.relation_kind -eq 'calls_workpanel' }).Count -eq 2) "what-uses Menu MnuSub should list WorkPanel WkOrders twice; got: $(Format-Rows $subRows)"
$subLines = @($subRows | ForEach-Object { [int]$_.line } | Sort-Object)
$expectedSubLines = @((Get-LineNumberOf $subMenuXml '<PgmName>wkorders</PgmName>'), (Get-LineNumberOf $subMenuXml '<PgmName>WkOrders</PgmName>')) | Sort-Object
Assert-True (($subLines -join ',') -eq ($expectedSubLines -join ',')) "MnuSub evidences should carry the lines of both options ($($expectedSubLines -join ',')); got $($subLines -join ',')"

Write-Output 'OK: Test-KbIntelligenceLegacyMenuSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
