#requires -Version 7.4
<#
.SYNOPSIS
    Minimal test battery for Get-GeneXusXpzObjectInventory.ps1 (XML and synthetic .xpz).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
$inventoryScript = Join-Path $scriptDir 'Get-GeneXusXpzObjectInventory.ps1'
# Real GeneXus 18 export: SDK/platform modules come in as PackagedModule, not Module.
$packagedModuleGuid = 'c88fffcd-b6f8-0000-8fec-00b5497e2117'
$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$externalObjectGuid = 'c163e562-42c6-4158-ad83-5b21a14cf30e'
$workWithGuid = '15cf49b5-fc38-4899-91b5-395d02d79889'
$workWithForWebGuid = '78cecefe-be7d-4980-86ce-8d6e91fba04b'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-xpz-inventory-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

$exportXml = @"
<ExportFile>
  <Objects>
    <Object type="$packagedModuleGuid" name="GeneXus" guid="11111111-1111-1111-1111-111111111101" />
    <Object type="$procedureGuid" name="ProcPedida" guid="11111111-1111-1111-1111-111111111102" />
    <Object type="$procedureGuid" name="ProcExtra" guid="11111111-1111-1111-1111-111111111103" />
    <Object type="$externalObjectGuid" name="Camera" guid="11111111-1111-1111-1111-111111111104" />
  </Objects>
  <Attributes>
    <Attribute name="AttrA" guid="22222222-2222-2222-2222-222222222201" />
    <Attribute name="AttrB" guid="22222222-2222-2222-2222-222222222202" />
  </Attributes>
</ExportFile>
"@

$xmlPath = Join-Path $tempRoot 'package.import_file.xml'
[System.IO.File]::WriteAllText($xmlPath, $exportXml, (Get-Utf8NoBomEncoding))

# Read-side contract: the script inventories a package; it does not compare it against a
# declared delta (that belonged to package generation, which is out of scope).
$inventoryParameters = (Get-Command -Name $inventoryScript).Parameters
foreach ($removedParameter in @('DeclaredDeltaPath', 'DeclaredDeltaItems', 'FailOnDeltaMismatch')) {
    if ($inventoryParameters.ContainsKey($removedParameter)) {
        throw "parameter -$removedParameter should not exist on the read-side inventory"
    }
}

$result = (& $inventoryScript -InputPath $xmlPath | ConvertFrom-Json)
if ($result.status -ne 'INVENTORY_OK') { throw "status expected INVENTORY_OK; got $($result.status)" }
if ($result.objectCount -ne 4) { throw "objectCount expected 4; got $($result.objectCount)" }
if ($result.attributeCount -ne 2) { throw 'attributeCount expected 2' }
foreach ($removedField in @('deltaComparison', 'selectiveExport', 'declaredIncludesTransaction', 'attributesTopLevelUnreconciled')) {
    if ($null -ne $result.PSObject.Properties[$removedField]) {
        throw "output field '$removedField' should not exist on the read-side inventory"
    }
}
if (@($result.systemObjectsPresent).Count -ne 2) {
    throw "systemObjectsPresent expected 2 (GeneXus + Camera); got $(@($result.systemObjectsPresent).Count)"
}
$gxPresent = @($result.systemObjectsPresent | Where-Object { $_.name -eq 'GeneXus' -and $_.kind -eq 'packagedModule' })
if ($gxPresent.Count -ne 1) { throw 'packagedModule GeneXus expected in systemObjectsPresent' }
$camPresent = @($result.systemObjectsPresent | Where-Object { $_.name -eq 'Camera' -and $_.kind -eq 'externalObject' })
if ($camPresent.Count -ne 1) { throw 'externalObject Camera expected in systemObjectsPresent' }
$genexusItem = @($result.inventory | Where-Object { $_.name -eq 'GeneXus' } | Select-Object -First 1)
if ($genexusItem.typeName -ne 'PackagedModule') {
    throw "type expected PackagedModule for GeneXus; got $($genexusItem.typeName)"
}
$attrWarning = @($result.warnings | Where-Object { $_ -match 'attributes-top-level' })
if ($attrWarning.Count -gt 0) {
    throw 'no top-level attribute warning expected: it only made sense against a declared delta'
}
if ($result.inputKind -ne 'xml') { throw 'inputKind xml expected' }

$xpzPath = Join-Path $tempRoot 'package.xpz'
Compress-Archive -LiteralPath $xmlPath -DestinationPath $xpzPath -Force
$resultXpz = (& $inventoryScript -InputPath $xpzPath | ConvertFrom-Json)
if ($resultXpz.inputKind -ne 'xpz') { throw 'inputKind xpz expected' }
if ($resultXpz.objectCount -ne 4) { throw 'objectCount xpz expected 4' }
if (@($resultXpz.systemObjectsPresent).Count -ne 2) { throw 'systemObjectsPresent xpz expected 2' }

# sourceKb reports the export's <Source> block, so setup can propose the KB name before the first
# sync: the KB folder is the last segment of UNCPath (a trailing separator is ignored). An export
# with no <Source> block reports null.
if ($null -ne $result.PSObject.Properties['sourceKb'] -and $null -ne $result.sourceKb) {
    throw "sourceKb expected null for an export with no <Source> block; got $($result.sourceKb | ConvertTo-Json -Compress)"
}
if ($null -eq $result.PSObject.Properties['sourceKb']) { throw 'output field sourceKb expected' }
$sourceXml = @"
<ExportFile>
  <Source kb="33333333-3333-3333-3333-333333333301" username="SampleUser" UNCPath="\\SAMPLEHOST\KBs\SampleKbFolder\">
    <Version guid="33333333-3333-3333-3333-333333333302" name="SampleKbVersion" />
  </Source>
  <Objects>
    <Object type="$procedureGuid" name="ProcPedida" guid="11111111-1111-1111-1111-111111111102" />
  </Objects>
</ExportFile>
"@
$sourcePath = Join-Path $tempRoot 'package-source.import_file.xml'
[System.IO.File]::WriteAllText($sourcePath, $sourceXml, (Get-Utf8NoBomEncoding))
$resultSource = (& $inventoryScript -InputPath $sourcePath | ConvertFrom-Json)
$expectedSourceKb = [ordered]@{
    kbGuid       = '33333333-3333-3333-3333-333333333301'
    uncPath      = '\\SAMPLEHOST\KBs\SampleKbFolder\'
    kbFolderName = 'SampleKbFolder'
    versionName  = 'SampleKbVersion'
}
if ($null -eq $resultSource.sourceKb) { throw 'sourceKb expected for an export with a <Source> block; got null' }
foreach ($field in $expectedSourceKb.Keys) {
    if ($resultSource.sourceKb.$field -cne $expectedSourceKb[$field]) {
        throw "sourceKb.$field expected '$($expectedSourceKb[$field])'; got '$($resultSource.sourceKb.$field)'"
    }
}
if ($resultSource.status -ne 'INVENTORY_OK' -or $resultSource.objectCount -ne 1) {
    throw "a <Source> block must not change the inventory: status $($resultSource.status), objectCount $($resultSource.objectCount)"
}

$workWithXml = @"
<ExportFile>
  <Objects>
    <Object type="$workWithForWebGuid" name="MainWW" guid="55555555-5555-5555-5555-555555555501" />
    <Object type="$workWithGuid" name="MobileWW" guid="55555555-5555-5555-5555-555555555503" />
  </Objects>
</ExportFile>
"@
$workWithPath = Join-Path $tempRoot 'package-work-with.import_file.xml'
[System.IO.File]::WriteAllText($workWithPath, $workWithXml, (Get-Utf8NoBomEncoding))
$resultWorkWith = (& $inventoryScript -InputPath $workWithPath | ConvertFrom-Json)
$webItem = @($resultWorkWith.inventory | Where-Object { $_.name -eq 'MainWW' })[0]
if ($webItem.typeName -ne 'WorkWithForWeb') { throw "MainWW type expected WorkWithForWeb; got $($webItem.typeName)" }
$mobileItem = @($resultWorkWith.inventory | Where-Object { $_.name -eq 'MobileWW' })[0]
if ($mobileItem.typeName -ne 'WorkWith') { throw "MobileWW type expected WorkWith; got $($mobileItem.typeName)" }

# A BLOCK failure is reported as JSON with the English status 'blocked' and exit 20.
$resultBlocked = (& $inventoryScript -InputPath (Join-Path $tempRoot 'missing.import_file.xml') | ConvertFrom-Json)
$blockedExitCode = $LASTEXITCODE
if ($blockedExitCode -ne 20) { throw "missing input: exit code expected 20; got $blockedExitCode" }
if ($resultBlocked.status -ne 'blocked') { throw "missing input: status expected blocked; got $($resultBlocked.status)" }

Remove-Item -LiteralPath $tempRoot -Recurse -Force
Write-Output 'GENEXUS_XPZ_OBJECT_INVENTORY_SELFTEST_OK'
