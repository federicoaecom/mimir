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
    >1 child / collision; known-legacy inventory contract; no declared-delta helpers.
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

if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }

Write-Output 'GENEXUS_LEGACY_EXPORT_FILE_SUPPORT_SELFTEST_OK'
exit 0
