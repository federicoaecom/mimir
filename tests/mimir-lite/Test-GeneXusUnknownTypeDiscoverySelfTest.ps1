#requires -Version 7.4
<#
.SYNOPSIS
    Minimal battery for unknown-type discovery and catalog override.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
. (Join-Path $scriptDir 'GeneXusObjectTypeCatalogSupport.ps1')

$unknownGuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
$knownProcedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'

$exportXml = @"
<ExportFile>
  <Objects>
    <Object type="$unknownGuid" name="ObjNovo" parent="FolderX" parentType="00000000-0000-0000-0000-000000000004" guid="11111111-1111-1111-1111-111111111101">
      <Source />
    </Object>
    <Object type="$knownProcedureGuid" name="ProcOk" guid="11111111-1111-1111-1111-111111111102">
      <Source />
    </Object>
  </Objects>
  <Dependencies>
    <Reference Package="99999999-9999-9999-9999-999999999999" Type="Part" Id="$unknownGuid">
      <Properties Name="Not An Object Type" PackageName="WrongBL" />
    </Reference>
    <Reference Package="99999999-9999-9999-9999-999999999999" Type="Object" Id="$unknownGuid">
      <Properties Name="Sample Type" PackageName="SampleBL" />
    </Reference>
  </Dependencies>
</ExportFile>
"@

$doc = New-Object System.Xml.XmlDocument
$doc.PreserveWhitespace = $true
$doc.LoadXml($exportXml)

$resolution = Resolve-GeneXusObjectTypeCatalogPaths -BaseCatalogPath (Join-Path $scriptDir 'gx-object-type-catalog.json')
$folderMap = Get-GeneXusCatalogGuidToFolderMap -MergedCatalog $resolution.MergedCatalog
$unknown = @(Get-GeneXusUnknownObjectTypesFromExportFile -XmlDocument $doc -GuidToFolderMap $folderMap)

if ($unknown.Count -ne 1) {
    throw "expected 1 unknown type; got $($unknown.Count)"
}
if ($unknown[0].unknownObjectTypeGuid -ne $unknownGuid) {
    throw 'unknown GUID diverges'
}
if ($unknown[0].count -ne 1) {
    throw 'expected count 1'
}
if ($unknown[0].sampleNames[0] -ne 'ObjNovo') {
    throw 'expected sampleNames ObjNovo'
}
if ($unknown[0].sampleParents[0] -ne 'FolderX') {
    throw 'expected sampleParents FolderX'
}
if ($unknown[0].sampleXmlSnippets.Count -lt 1) {
    throw 'expected sampleXmlSnippets'
}

$message = Format-GeneXusUnknownObjectTypesErrorMessage -UnknownTypes $unknown -OverrideActive $false
if ($message -notmatch 'ObjNovo') {
    throw 'error message must include the sample name'
}

# The type name and package come from the package's Dependencies block (Type="Object" only).
if ($unknown[0].typeName -ne 'Sample Type') {
    throw "expected typeName 'Sample Type' from Dependencies; got '$($unknown[0].typeName)'"
}
if ($unknown[0].typePackageName -ne 'SampleBL') {
    throw "expected typePackageName 'SampleBL' from Dependencies; got '$($unknown[0].typePackageName)'"
}
if ($message -notmatch [regex]::Escape("$unknownGuid type=`"Sample Type`" package=`"SampleBL`" [1]")) {
    throw "error message must name the GUID with its type name, package, and count; got: $message"
}

# Without a Dependencies entry, the type name and package are reported as 'unknown'.
$noDependenciesDoc = New-Object System.Xml.XmlDocument
$noDependenciesDoc.LoadXml(@"
<ExportFile>
  <Objects>
    <Object type="$unknownGuid" name="ObjNovo" guid="11111111-1111-1111-1111-111111111101"><Source /></Object>
  </Objects>
</ExportFile>
"@)
$unknownNoDeps = @(Get-GeneXusUnknownObjectTypesFromExportFile -XmlDocument $noDependenciesDoc -GuidToFolderMap $folderMap)
if ($unknownNoDeps[0].typeName -ne 'unknown' -or $unknownNoDeps[0].typePackageName -ne 'unknown') {
    throw "without Dependencies, typeName/typePackageName must be 'unknown'; got '$($unknownNoDeps[0].typeName)'/'$($unknownNoDeps[0].typePackageName)'"
}
$messageNoDeps = Format-GeneXusUnknownObjectTypesErrorMessage -UnknownTypes $unknownNoDeps -OverrideActive $false
if ($messageNoDeps -notmatch [regex]::Escape("$unknownGuid type=`"unknown`" package=`"unknown`" [1]")) {
    throw "error message must say 'unknown' when Dependencies does not name the type; got: $messageNoDeps"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-unknown-discovery-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$scriptsDir = Join-Path $kbWorkspaceRoot 'scripts'
[void](New-Item -ItemType Directory -Path $scriptsDir -Force)

& (Join-Path $scriptDir 'Register-GeneXusObjectTypeCatalogOverride.ps1') `
    -KbWorkspaceRoot $kbWorkspaceRoot `
    -TypeName 'TipoTeste' `
    -ObjectTypeGuid $unknownGuid `
    -FolderName 'TipoTeste' `
    -UserApproved `
    -EvidenceSummary 'self-test' | Out-Null

$reminderScript = Join-Path $scriptDir 'Test-MimirCatalogOverrideSessionReminder.ps1'
$reminderJson = & $reminderScript -KbWorkspaceRoot $kbWorkspaceRoot -AsJson | ConvertFrom-Json
if (-not $reminderJson.reminderRequired) {
    throw 'expected reminderRequired true after override'
}
if ($reminderJson.status -ne 'REMINDER_REQUIRED') {
    throw "expected status REMINDER_REQUIRED; got $($reminderJson.status)"
}

$mergedResolution = Resolve-GeneXusObjectTypeCatalogPaths -KbWorkspaceRoot $kbWorkspaceRoot
$mergedMap = Get-GeneXusCatalogGuidToFolderMap -MergedCatalog $mergedResolution.MergedCatalog
if (-not $mergedMap.ContainsKey($unknownGuid)) {
    throw 'override should map the unknown GUID'
}

$discoveryReportPath = Join-Path $tempRoot 'unknown-type-discovery.json'
Write-GeneXusUnknownTypeDiscoveryReport -Path $discoveryReportPath -UnknownTypes $unknown -CatalogResolution $resolution -InputPath 'package.xml'
$discoveryReport = Get-Content -LiteralPath $discoveryReportPath -Raw | ConvertFrom-Json
$overrideHint = [string]$discoveryReport.resolutionHints.localOverrideFile
if ($overrideHint -notmatch 'KB workspace root' -or $overrideHint -match '(?i)parallel') {
    throw "discovery report override hint must name the KB workspace root; got: $overrideHint"
}

$xmlPath = Join-Path $tempRoot 'package.xml'
[System.IO.File]::WriteAllText($xmlPath, $exportXml, (Get-Utf8NoBomEncoding))
$inventoryScript = Join-Path $scriptDir 'Get-GeneXusXpzObjectInventory.ps1'
# Pre-scan without the override: blocked, and the JSON carries the ready-made message.
$emptyWorkspaceRoot = Join-Path $tempRoot 'EmptyWorkspace'
[void](New-Item -ItemType Directory -Path (Join-Path $emptyWorkspaceRoot 'scripts') -Force)
$invUnknown = & $inventoryScript -InputPath $xmlPath -KbWorkspaceRoot $emptyWorkspaceRoot -FailOnUnknownTypes | ConvertFrom-Json
if ($LASTEXITCODE -ne 3 -or $invUnknown.status -ne 'UNKNOWN_TYPES_BLOCKED') {
    throw "pre-scan without override must block with exit 3; got exit $LASTEXITCODE status $($invUnknown.status)"
}
if ([string]$invUnknown.unknownTypesMessage -notmatch [regex]::Escape("$unknownGuid type=`"Sample Type`" package=`"SampleBL`" [1] names=ObjNovo")) {
    throw "pre-scan JSON must carry unknownTypesMessage naming the type; got: $($invUnknown.unknownTypesMessage)"
}
$invBlocked = & $inventoryScript -InputPath $xmlPath -KbWorkspaceRoot $kbWorkspaceRoot | ConvertFrom-Json
if ($invBlocked.unknownTypeCount -ne 0) {
    throw 'with override, unknownTypeCount should be 0'
}

$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$tipoDir = Join-Path $kbObjectsPath 'TipoTeste'
[void](New-Item -ItemType Directory -Path $tipoDir -Force)
$sampleObjectXml = @"
<Object type="$unknownGuid" name="ObjNovo" guid="11111111-1111-1111-1111-111111111199">
  <Source />
</Object>
"@
[System.IO.File]::WriteAllText((Join-Path $tipoDir 'ObjNovo.xml'), $sampleObjectXml, (Get-Utf8NoBomEncoding))

$namingScript = Join-Path $scriptDir 'Test-MimirKbObjectsXmlNaming.ps1'
$namingJson = & $namingScript -KbWorkspaceRoot $kbWorkspaceRoot -AsJson | ConvertFrom-Json
if ($namingJson.status -ne 'NAMING_OK') {
    throw "expected naming NAMING_OK with override; got $($namingJson.status)"
}

$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)
$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
$indexScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
& $indexScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -KbWorkspaceRoot $kbWorkspaceRoot
if ($LASTEXITCODE -ne 0) {
    throw "Build-KbIntelligenceIndex with override should pass; exit $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $sqlitePath -PathType Leaf)) {
    throw 'Index SQLite was not generated with override'
}

Write-Output 'OK: Test-GeneXusUnknownTypeDiscoverySelfTest.ps1'
exit 0
