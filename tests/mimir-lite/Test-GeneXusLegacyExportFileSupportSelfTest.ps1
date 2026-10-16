#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the GeneXus 9 legacy export engine (GeneXusLegacyExportFileSupport.ps1), in isolation.

.DESCRIPTION
    Exercises the parser/converter over the iso-8859-1 fixture (generated on-the-fly in Temp by
    GeneXusLegacyExportFileFixtureSupport.ps1; not versioned — Option B) and inline
    cases: profile detection; encoding-aware reading via .xml and .xpz (Latin-1 accent
    preserved, not transliterated); equivalent->real GUID / orphan->gxlegacy/<Tag>; sentinel;
    guid=''/dataSource/GxLegacyPayload; attributes; XPath-does-not-leak (nodes nested in the
    payload do not contaminate detection or materialization); fail-closed for mixed / unknown tag /
    >1 child / collision; known-legacy inventory contract; no declared-delta helpers; the GeneXus 7.0
    and earlier (.xpw) orphans Menu, Prompt, and Formula (named by its direct Name child).
    Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $scriptsRoot 'GeneXusObjectTypeCatalogSupport.ps1')
. (Join-Path $scriptsRoot 'GeneXusLegacyExportFileSupport.ps1')
. (Join-Path $fixturesRoot 'GeneXusLegacyExportFileFixtureSupport.ps1')

# The iso-8859-1 fixture is generated in Temp on-the-fly (not versioned; avoids transcoding by editor/git).
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('legacy-fixture-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $fixtureRoot)
$fixturePath = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $fixtureRoot 'legacy-exportfile-minimal.xml')

function Get-EncodingAwareXmlFromFile {
    param([string]$Path)
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.Load($Path)   # honors the iso-8859-1 prolog
    return $doc
}

function Get-EncodingAwareXmlFromXpz {
    param([string]$XpzPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($XpzPath)
    try {
        $entry = @($zip.Entries | Where-Object { $_.FullName -match '\.xml$' })[0]
        $doc = New-Object System.Xml.XmlDocument
        $doc.PreserveWhitespace = $true
        $stream = $entry.Open()
        try { $doc.Load($stream) } finally { $stream.Dispose() }   # Load($entry.Open()) honors the prolog
        return $doc
    } finally {
        $zip.Dispose()
    }
}

$resolution = Resolve-GeneXusObjectTypeCatalogPaths -BaseCatalogPath (Join-Path $scriptsRoot 'gx-object-type-catalog.json')
$merged = $resolution.MergedCatalog
$registry = Get-GeneXusLegacyExportElementRegistry

# --- Encoding-aware reading via .xml: Latin-1 accent preserved ---
[xml]$fixtureXml = Get-EncodingAwareXmlFromFile -Path $fixturePath
$wpDesc = $fixtureXml.SelectSingleNode('/ExportFile/GXObject/WorkPanel/Info/Description').InnerText
if ($wpDesc -ne 'Cadastro de Parâmetros') { throw "Accent (.xml) not preserved; got '$wpDesc'." }  # lang-allow: pt-BR payload that verifies accent preservation

# --- Encoding-aware reading via .xpz: same accent preserved ---
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('legacy-support-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot)
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $xpzPath = Join-Path $tempRoot 'fixture.xpz'
    $zipW = [System.IO.Compression.ZipFile]::Open($xpzPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try { [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipW, $fixturePath, 'FinSample_1.xml') } finally { $zipW.Dispose() }
    [xml]$fromXpz = Get-EncodingAwareXmlFromXpz -XpzPath $xpzPath
    $wpDescXpz = $fromXpz.SelectSingleNode('/ExportFile/GXObject/WorkPanel/Info/Description').InnerText
    if ($wpDescXpz -ne 'Cadastro de Parâmetros') { throw "Accent (.xpz) not preserved; got '$wpDescXpz'." }  # lang-allow: pt-BR payload that verifies accent preservation
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

# --- Profile detection: pure-legacy despite <Objects>/<Attribute> nested in the payload ---
if (-not (Test-GeneXusLegacyExportFilePackage -XmlDocument $fixtureXml)) { throw 'Fixture should be pure-legacy (XPath-does-not-leak).' }
if (Test-GeneXusMixedExportFilePackage -XmlDocument $fixtureXml) { throw 'Fixture should not be mixed (nested nodes leaked).' }

# --- Conversion ---
$items = (Get-GeneXusLegacyExportFileSyncItems -XmlDocument $fixtureXml -MergedCatalog $merged -Registry $registry).Items
if (@($items).Count -ne 7) { throw "Expected 7 items (5 objects + 2 attributes), got $(@($items).Count)." }

# XPath-does-not-leak: no item materialized from the nested <Object name='NaoDeveVazar'>
if (@($items | Where-Object { $_.LogicalName -eq 'NaoDeveVazar' }).Count -ne 0) { throw 'An object nested in the payload leaked into the items.' }

$byElem = @{}
foreach ($it in $items) {
    if ($it.Guid -ne '') { throw "guid should be empty on '$($it.LogicalName)'." }
    if ($it.Node.GetAttribute('dataSource') -ne 'gx-legacy-export') { throw "dataSource missing on '$($it.LogicalName)'." }
    if ($null -eq $it.Node.SelectSingleNode('./GxLegacyPayload')) { throw "GxLegacyPayload missing on '$($it.LogicalName)'." }
    if (-not $byElem.ContainsKey($it.LegacyElement)) { $byElem[$it.LegacyElement] = New-Object System.Collections.Generic.List[object] }
    $byElem[$it.LegacyElement].Add($it)
}

# equivalent -> real catalog GUID (WorkPanel) and correct folder
$wp = $byElem['WorkPanel'][0]
if ($wp.FolderType -ne 'WorkPanel') { throw "Wrong WorkPanel folder: $($wp.FolderType)." }
if ($wp.TypeGuid -notmatch '^[0-9a-fA-F-]{36}$') { throw "WorkPanel should have a real GUID; got '$($wp.TypeGuid)'." }
$tx = $byElem['Transaction'][0]
if ($tx.FolderType -ne 'Transaction' -or $tx.TypeGuid -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Transaction equivalent failed.' }

# object without LastUpdate (Procedure RelConfig) -> sentinel
$proc = $byElem['Procedure'][0]
if ($proc.Node.GetAttribute('lastUpdate') -ne '0001-01-01T00:00:00.0000000Z') { throw "Expected sentinel on the Procedure without LastUpdate; got '$($proc.Node.GetAttribute('lastUpdate'))'." }

# orphan -> gxlegacy/<Tag> in its own folder
$rep = $byElem['Report'][0]
if ($rep.TypeGuid -ne 'gxlegacy/Report' -or $rep.FolderType -ne 'Report') { throw "Report orphan failed (type=$($rep.TypeGuid), folder=$($rep.FolderType))." }

# Menubar is equivalent (real GUID from the modern catalog), no longer orphan gxlegacy/Menubar
$menu = $byElem['Menubar'][0]
if ($menu.FolderType -ne 'Menubar') { throw "Wrong Menubar folder: $($menu.FolderType)." }
if ($menu.TypeGuid -notmatch '^[0-9a-fA-F-]{36}$') { throw "Menubar should have a real GUID; got '$($menu.TypeGuid)'." }
if ($menu.TypeGuid -ne '28eca899-04c7-4114-9556-5879b0a6414c') { throw "Unexpected Menubar GUID: $($menu.TypeGuid)." }

# Latin-1 accent preserved (not transliterated) in the materialized payload
if ($tx.Node.OuterXml -notmatch 'Configuração de clientes') { throw 'Accent not preserved in the Transaction payload.' }  # lang-allow: pt-BR payload that verifies accent preservation

# attributes: 2 GXAtt, with the accent in Title preserved
$atts = @($items | Where-Object { $_.RootTag -eq 'Attribute' })
if ($atts.Count -ne 2) { throw "Expected 2 GXAtt attributes, got $($atts.Count)." }
$end = @($atts | Where-Object { $_.LogicalName -eq 'Endereco' })[0]
if ($end.Node.OuterXml -notmatch 'Endereço de cobrança') { throw 'Accent not preserved in the attribute Title.' }  # lang-allow: pt-BR payload that verifies accent preservation

# --- Inventory: known-legacy contract ---
$inv = Get-GeneXusLegacyExportFileInventoryItems -XmlDocument $fixtureXml -MergedCatalog $merged -Registry $registry
if ($inv.TotalCount -ne 7) { throw "Expected inventory 7, got $($inv.TotalCount)." }
foreach ($iv in $inv.Items) {
    if ($iv.typeStatus -ne 'known-legacy') { throw 'typeStatus should be known-legacy.' }
    if ([string]::IsNullOrWhiteSpace($iv.typeName)) { throw 'a non-null typeName is required.' }
    if ($iv.rootKind -ne 'Object' -and $iv.rootKind -ne 'Attribute') { throw "invalid synthetic rootKind: $($iv.rootKind)." }
    if ($iv.sourceBlock -ne 'Objects' -and $iv.sourceBlock -ne 'Attributes') { throw "invalid sourceBlock: $($iv.sourceBlock)." }
}
$invRep = @($inv.Items | Where-Object { $_.legacyElement -eq 'Report' })[0]
if ($invRep.typeName -ne 'gxlegacy/Report' -or $invRep.rootKind -ne 'Object') { throw 'Report orphan inventory failed.' }

# --- No declared-delta helpers: the read-side inventory does not compare against a delta ---
foreach ($removedHelper in @('Convert-LegacyDeclaredDeltaKeyToCanonical', 'Get-GeneXusExportTaskLabelAliasRules')) {
    if (Get-Command -Name $removedHelper -CommandType Function -ErrorAction SilentlyContinue) { throw "helper $removedHelper should not exist." }
}

# --- Fail-closed: mixed ---
$mixed = [xml]'<ExportFile><GXObject><Transaction><Info><Name>X</Name></Info></Transaction></GXObject><Objects><Object type="x" name="Y"/></Objects></ExportFile>'
if (-not (Test-GeneXusMixedExportFilePackage -XmlDocument $mixed)) { throw 'Mixed (Objects/Object) should be detected.' }
$mixedAtt = [xml]'<ExportFile><GXObject><Transaction><Info><Name>X</Name></Info></Transaction></GXObject><Attributes><Attribute name="Z"/></Attributes></ExportFile>'
if (-not (Test-GeneXusMixedExportFilePackage -XmlDocument $mixedAtt)) { throw 'Mixed (Attributes/Attribute modern) should be detected.' }
if (Test-GeneXusLegacyExportFilePackage -XmlDocument $mixedAtt) { throw 'Mixed should not classify as pure-legacy.' }

# --- Fail-closed: unknown tag ---
$unknown = [xml]'<ExportFile><GXObject><FooBar><Info><Name>Z</Name></Info></FooBar></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $unknown -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'An unknown tag should fail-closed.' }

# --- Fail-closed: >1 child element per GXObject ---
$twoChild = [xml]'<ExportFile><GXObject><Transaction><Info><Name>A</Name></Info></Transaction><Report><Info><Name>B</Name></Info></Report></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $twoChild -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw '>1 child element per GXObject should fail-closed.' }

# --- Fail-closed: name collision (same FolderType|NormalizedName, distinct logical names) ---
# 'A:b' (invalid ':' -> '_') and 'A_b' both normalize to 'A_b' (distinct logical names) => collision.
$collision = [xml]'<ExportFile><GXObject><Transaction><Info><Name>A:b</Name></Info></Transaction></GXObject><GXObject><Transaction><Info><Name>A_b</Name></Info></Transaction></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $collision -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'A normalized name collision should fail-closed.' }

# --- GeneXus 8 shapes: WebPanel element and ungrouped subtypes (Group with a blank name) ---
$webPanelGuid = [string]$merged.types.WebPanel.objectTypeGuid
$gx8 = [xml]@'
<ExportFile>
  <GXObject><WebPanel><Info><Name>WpOrders</Name></Info><LastUpdate>2013-02-18 22:48:04GMT</LastUpdate></WebPanel></GXObject>
  <GXObject><Group><Info><Name> </Name></Info><Subtype><Name>SubC</Name><Supertype>SuperC</Supertype></Subtype><Subtype><Name>SubB</Name><Supertype>SuperB</Supertype></Subtype></Group></GXObject>
  <GXObject><Group><Info><Name>GrpClients</Name></Info><Subtype><Name>SubClient</Name><Supertype>SuperB</Supertype></Subtype></Group></GXObject>
</ExportFile>
'@
$gx8Items = @((Get-GeneXusLegacyExportFileSyncItems -XmlDocument $gx8 -MergedCatalog $merged -Registry $registry).Items)
if ($gx8Items.Count -ne 4) { throw "GX8: expected 4 items (WebPanel + 2 ungrouped subtypes + 1 named group), got $($gx8Items.Count)." }

$gx8Wp = @($gx8Items | Where-Object { $_.LegacyElement -eq 'WebPanel' })
if ($gx8Wp.Count -ne 1 -or $gx8Wp[0].FolderType -ne 'WebPanel' -or $gx8Wp[0].TypeGuid -ne $webPanelGuid) { throw "GX8: WebPanel should map to the catalog WebPanel type (folder WebPanel, GUID $webPanelGuid)." }
if ($gx8Wp[0].Node.GetAttribute('lastUpdate') -ne '2013-02-18T22:48:04.0000000Z') { throw "GX8: WebPanel lastUpdate='$($gx8Wp[0].Node.GetAttribute('lastUpdate'))'." }

$gx8Groups = @($gx8Items | Where-Object { $_.LegacyElement -eq 'Group' })
$gx8GroupNames = @($gx8Groups | ForEach-Object { $_.LogicalName } | Sort-Object)
if (($gx8GroupNames -join ',') -ne 'GrpClients,SubB,SubC') { throw "GX8: expected SubTypeGroup items GrpClients, SubB, SubC; got $($gx8GroupNames -join ', ')." }
foreach ($g in $gx8Groups) {
    if ($g.FolderType -ne 'SubTypeGroup') { throw "GX8: '$($g.LogicalName)' should materialize under SubTypeGroup; got $($g.FolderType)." }
}
foreach ($pair in @(@('SubC', 'SuperC'), @('SubB', 'SuperB'))) {
    $split = @($gx8Groups | Where-Object { $_.LogicalName -eq $pair[0] })[0]
    $subtypes = @($split.Node.SelectNodes('./GxLegacyPayload/Group/Subtype'))
    if ($subtypes.Count -ne 1) { throw "GX8: ungrouped subtype '$($pair[0])' should carry exactly 1 Subtype; got $($subtypes.Count)." }
    if ($subtypes[0].SelectSingleNode('./Name').InnerText -ne $pair[0] -or $subtypes[0].SelectSingleNode('./Supertype').InnerText -ne $pair[1]) { throw "GX8: ungrouped subtype '$($pair[0])' carries the wrong Subtype." }
    if ($null -eq $split.Node.SelectSingleNode('./GxLegacyPayload/Group/Info/Name') -or -not [string]::IsNullOrWhiteSpace($split.Node.SelectSingleNode('./GxLegacyPayload/Group/Info/Name').InnerText)) { throw "GX8: '$($pair[0])' should keep the blank Info/Name marking it ungrouped." }
    if ($split.Node.GetAttribute('lastUpdate') -ne '0001-01-01T00:00:00.0000000Z') { throw "GX8: ungrouped subtype without LastUpdate should get the sentinel." }
}
$named = @($gx8Groups | Where-Object { $_.LogicalName -eq 'GrpClients' })[0]
if (@($named.Node.SelectNodes('./GxLegacyPayload/Group/Subtype')).Count -ne 1) { throw 'GX8: the named group should keep its own Subtype list unchanged.' }

# A blank name on any other element still fails closed
$blankTx = [xml]'<ExportFile><GXObject><Transaction><Info><Name> </Name></Info></Transaction></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $blankTx -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'A blank Info/Name outside Group should still fail-closed.' }

# A blank-name Group with no Subtype has nothing to materialize: fail closed
$emptyGroup = [xml]'<ExportFile><GXObject><Group><Info><Name> </Name></Info></Group></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $emptyGroup -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'A blank-name Group without Subtype should fail-closed.' }

# An ungrouped Subtype without a name fails closed
$blankSubtype = [xml]'<ExportFile><GXObject><Group><Info><Name> </Name></Info><Subtype><Name> </Name><Supertype>SuperB</Supertype></Subtype></Group></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $blankSubtype -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'An ungrouped Subtype without a name should fail-closed.' }

# An ungrouped subtype named like a named group would overwrite its file: fail closed
$sameName = [xml]'<ExportFile><GXObject><Group><Info><Name> </Name></Info><Subtype><Name>SuperB</Name><Supertype>SuperD</Supertype></Subtype></Group></GXObject><GXObject><Group><Info><Name>SuperB</Name></Info><Subtype><Name>SubB</Name><Supertype>SuperB</Supertype></Subtype></Group></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $sameName -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'An ungrouped subtype with the same name as a named group should fail-closed.' }

# --- GeneXus 7.0 and earlier shapes (.xpw): Menu, Prompt, and Formula are non-indexed orphans ---
# Formula has no Info block: its identity is the attribute it computes, in a Name child of the element.
$classic = [xml]@'
<ExportFile>
  <GXObject><Menu><Info><Name>MnuMain</Name></Info><MenuOptions><OptionCode>1</OptionCode><PgmName>PrcAlpha</PgmName></MenuOptions></Menu></GXObject>
  <GXObject><Prompt><Info><Name>PrmCustomer</Name></Info><PromptInfo><Name>PrmCustomer</Name><Table>TblAlpha</Table></PromptInfo></Prompt></GXObject>
  <GXObject><Formula><Name>CustTotal</Name><Type>1</Type><Source>CustQty * CustPrice</Source></Formula></GXObject>
</ExportFile>
'@
$classicItems = @((Get-GeneXusLegacyExportFileSyncItems -XmlDocument $classic -MergedCatalog $merged -Registry $registry).Items)
if ($classicItems.Count -ne 3) { throw "Classic: expected 3 items (Menu, Prompt, Formula), got $($classicItems.Count)." }
foreach ($expected in @(@('Menu', 'MnuMain'), @('Prompt', 'PrmCustomer'), @('Formula', 'CustTotal'))) {
    $classicItem = @($classicItems | Where-Object { $_.LegacyElement -eq $expected[0] })
    if ($classicItem.Count -ne 1) { throw "Classic: expected 1 $($expected[0]) item, got $($classicItem.Count)." }
    if ($classicItem[0].TypeGuid -ne "gxlegacy/$($expected[0])" -or $classicItem[0].Node.GetAttribute('type') -ne "gxlegacy/$($expected[0])") { throw "Classic: $($expected[0]) should carry type gxlegacy/$($expected[0]); got '$($classicItem[0].TypeGuid)'." }
    if ($classicItem[0].FolderType -ne $expected[0]) { throw "Classic: $($expected[0]) should materialize under $($expected[0]); got $($classicItem[0].FolderType)." }
    if ($classicItem[0].LogicalName -ne $expected[1] -or $classicItem[0].Node.GetAttribute('name') -ne $expected[1]) { throw "Classic: $($expected[0]) should be named $($expected[1]); got '$($classicItem[0].LogicalName)'." }
    if ($classicItem[0].Node.GetAttribute('lastUpdate') -ne '0001-01-01T00:00:00.0000000Z') { throw "Classic: $($expected[0]) without LastUpdate should get the sentinel." }
}
$classicFormula = @($classicItems | Where-Object { $_.LegacyElement -eq 'Formula' })[0]
if ($classicFormula.Node.SelectSingleNode('./GxLegacyPayload/Formula/Source').InnerText -ne 'CustQty * CustPrice') { throw 'Classic: the Formula payload should keep its Source.' }

# A Formula with a blank Name fails closed
$blankFormula = [xml]'<ExportFile><GXObject><Formula><Name> </Name><Type>1</Type></Formula></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $blankFormula -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'A Formula with a blank Name should fail-closed.' }

# A direct Name child names only a Formula: any other element without Info/Name still fails closed
$directNameTx = [xml]'<ExportFile><GXObject><Transaction><Name>TrnAlpha</Name></Transaction></GXObject></ExportFile>'
$threw = $false
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $directNameTx -MergedCatalog $merged -Registry $registry) } catch { $threw = $true }
if (-not $threw) { throw 'A Transaction named only by a direct Name child should still fail-closed.' }

# An unknown element next to the new orphans still aborts the whole package
$classicUnknown = [xml]'<ExportFile><GXObject><Menu><Info><Name>MnuMain</Name></Info></Menu></GXObject><GXObject><FooBar><Info><Name>Z</Name></Info></FooBar></GXObject></ExportFile>'
$unknownMessage = ''
try { [void](Get-GeneXusLegacyExportFileSyncItems -XmlDocument $classicUnknown -MergedCatalog $merged -Registry $registry) } catch { $unknownMessage = $_.Exception.Message }
if ($unknownMessage -notmatch 'not in the registry: FooBar \(x1\)') { throw "Classic: an unknown element should still fail-closed naming only FooBar; got '$unknownMessage'." }

if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }

Write-Output 'GENEXUS_LEGACY_EXPORT_FILE_SUPPORT_SELFTEST_OK'
exit 0
