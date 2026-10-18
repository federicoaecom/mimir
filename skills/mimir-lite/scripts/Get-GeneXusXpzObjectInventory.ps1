#requires -Version 7.4
<#
.SYNOPSIS
Inventories objects actually present in import_file.xml or a GeneXus .xpz package.

.DESCRIPTION
Reads a GeneXus envelope with an <ExportFile> root (direct XML or inner XML inside a .xpz),
or a GeneXus 7.0 and earlier .xpw text export (a .xpw file, or a .zip of .xpw files) translated
in memory into the classic ExportFile XML, lists the objects under <Objects> and top-level attributes under <Attributes>, maps type
GUIDs via the shared catalog when possible, and reports unknown types for the sync pre-scan.

.PARAMETER InputPath
Path of import_file.xml, an equivalent XML with an <ExportFile> root, a .xpz package, a .xpw
text export, or a .zip of .xpw files (a zip mixing .xpw and .xml entries is blocked).

.PARAMETER CatalogPath
Optional path to gx-object-type-catalog.json.

.PARAMETER CatalogOverridePath
Optional path to gx-object-type-catalog.override.json in the KB workspace.

.PARAMETER KbWorkspaceRoot
Root of the KB workspace; resolves the override in scripts/ when CatalogOverridePath is omitted.

.PARAMETER FailOnUnknownTypes
Returns exit code 3 when there is a type not mapped in the effective catalog (sync pre-scan).

.PARAMETER PlatformObjectsCatalogPath
Optional path to gx-platform-objects.json (unified platform/SDK catalog).

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias('Path')]
    [string]$InputPath,

    [string]$CatalogPath,

    [string]$CatalogOverridePath,

    [string]$KbWorkspaceRoot,

    [switch]$FailOnUnknownTypes,

    [string]$PlatformObjectsCatalogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

trap {
    $message = $_.Exception.Message
    $exitCode = if ($message.StartsWith('BLOCK:')) { 20 } else { 90 }
    $status = if ($exitCode -eq 20) { 'blocked' } else { 'error' }
    [ordered]@{
        status = $status
        exitCode = $exitCode
        inputPath = $InputPath
        blockingReasons = @($message)
        warnings = @()
    } | ConvertTo-Json -Depth 6
    exit $exitCode
}

$supportScript = Join-Path $PSScriptRoot 'GeneXusObjectTypeCatalogSupport.ps1'
if (-not (Test-Path -LiteralPath $supportScript -PathType Leaf)) {
    throw "BLOCK: support script not found: $supportScript"
}
. $supportScript

$platformCatalogSupport = Join-Path $PSScriptRoot 'GeneXusPlatformObjectsCatalogSupport.ps1'
if (-not (Test-Path -LiteralPath $platformCatalogSupport -PathType Leaf)) {
    throw "BLOCK: support script not found: $platformCatalogSupport"
}
. $platformCatalogSupport

$legacyExportSupport = Join-Path $PSScriptRoot 'GeneXusLegacyExportFileSupport.ps1'
if (-not (Test-Path -LiteralPath $legacyExportSupport -PathType Leaf)) {
    throw "BLOCK: support script not found: $legacyExportSupport"
}
. $legacyExportSupport

$xpwExportSupport = Join-Path $PSScriptRoot 'GeneXusXpwExportFileSupport.ps1'
if (-not (Test-Path -LiteralPath $xpwExportSupport -PathType Leaf)) {
    throw "BLOCK: support script not found: $xpwExportSupport"
}
. $xpwExportSupport

function Get-IdentityKey {
    param(
        [string]$TypeName,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($TypeName) -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    return ('{0}:{1}' -f $TypeName.Trim(), $Name.Trim()).ToLowerInvariant()
}

function Get-ExportFileXmlDocument {
    param([string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()

    # GeneXus 7.0 and earlier .xpw (a file, or a .zip of .xpw files): translated in memory. A zip
    # with no .xpw entry keeps the XML handling below; translation errors are blocks.
    if ($extension -eq '.xpw' -or $extension -eq '.zip') {
        try {
            if ($extension -eq '.xpw') {
                $xpwDocument = Read-GeneXusXpwExportFile -Path $resolvedPath
                $xpwKind = 'xpw'
                $xpwEntryNames = $null
            } else {
                # Statement form: an XmlDocument written to the pipeline would be enumerated.
                $xpwZip = Read-GeneXusXpwZipExport -Path $resolvedPath
                $xpwDocument = $null
                $xpwEntryNames = $null
                if ($null -ne $xpwZip) {
                    $xpwDocument = $xpwZip.Document
                    $xpwEntryNames = $xpwZip.EntryNames -join ', '
                }
                $xpwKind = 'xpw-zip'
            }
        } catch {
            throw "BLOCK: $($_.Exception.Message)"
        }
        if ($null -ne $xpwDocument) {
            return [pscustomobject]@{
                Document     = $xpwDocument
                ResolvedPath = $resolvedPath
                InputKind    = $xpwKind
                InnerXmlName = $xpwEntryNames
                IsXpw        = $true
            }
        }
    }

    if ($extension -eq '.xpz' -or $extension -eq '.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $candidates = [System.Collections.Generic.List[System.Xml.XmlDocument]]::new()
        $candidateNames = [System.Collections.Generic.List[string]]::new()
        $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedPath)
        try {
            foreach ($entry in @($zip.Entries | Where-Object { $_.FullName -match '\.xml$' } | Sort-Object FullName)) {
                # Encoding-aware read: Load(stream) honors the prolog's encoding attribute
                # (legacy GeneXus 9 export is iso-8859-1). The previous StreamReader(UTF-8)+ReadToEnd+
                # LoadXml pair assumed UTF-8 and corrupted Latin-1 accents. Multi-candidate loop
                # + try/catch continue + ExportFile selection + fail-closed >1 preserved.
                $candidateDoc = New-Object System.Xml.XmlDocument
                $entryStream = $entry.Open()
                try {
                    $candidateDoc.PreserveWhitespace = $true
                    $candidateDoc.Load($entryStream)
                } catch {
                    continue
                } finally {
                    $entryStream.Dispose()
                }

                if ($candidateDoc.DocumentElement.LocalName -eq 'ExportFile') {
                    $candidates.Add($candidateDoc) | Out-Null
                    $candidateNames.Add($entry.FullName) | Out-Null
                }
            }
        } finally {
            $zip.Dispose()
        }

        if ($candidates.Count -eq 0) {
            throw "BLOCK: .xpz package has no XML with an ExportFile root: $resolvedPath"
        }
        if ($candidates.Count -gt 1) {
            $names = ($candidateNames -join ', ')
            throw ("BLOCK: .xpz package contains {0} ambiguous ExportFile candidates ({1}); provide the extracted XML instead." -f $candidates.Count, $names)
        }

        return [pscustomobject]@{
            Document     = $candidates[0]
            ResolvedPath = $resolvedPath
            InputKind    = 'xpz'
            InnerXmlName = $candidateNames[0]
            IsXpw        = $false
        }
    }

    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $true
    $document.Load($resolvedPath)
    return [pscustomobject]@{
        Document     = $document
        ResolvedPath = $resolvedPath
        InputKind    = 'xml'
        InnerXmlName = $null
        IsXpw        = $false
    }
}

function New-InventoryItem {
    param(
        [System.Xml.XmlElement]$Node,
        [hashtable]$GuidMap,
        [string]$SourceBlock,
        [int]$Index
    )

    $rootKind = $Node.LocalName
    $rawTypeGuid = $Node.GetAttribute('type')
    $name = $Node.GetAttribute('name')
    $guid = $Node.GetAttribute('guid')
    $typeName = $null
    $typeStatus = 'unknown'

    if ($rootKind -eq 'Attribute') {
        $typeName = 'Attribute'
        $typeStatus = 'root-kind'
    } elseif (-not [string]::IsNullOrWhiteSpace($rawTypeGuid)) {
        $typeKey = $rawTypeGuid.ToLowerInvariant()
        if ($GuidMap.ContainsKey($typeKey)) {
            $typeName = $GuidMap[$typeKey].typeName
            $typeStatus = 'mapped'
        }
    }

    $identityKey = Get-IdentityKey -TypeName $typeName -Name $name

    $parent = $null
    $parentType = $null
    if ($rootKind -eq 'Object') {
        $parent = $Node.GetAttribute('parent')
        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = $null }
        $parentType = $Node.GetAttribute('parentType')
        if ([string]::IsNullOrWhiteSpace($parentType)) { $parentType = $null }
    }

    return [pscustomobject]@{
        index       = $Index
        sourceBlock = $SourceBlock
        rootKind    = $rootKind
        type        = $typeName
        typeName    = $typeName
        typeGuid    = if ([string]::IsNullOrWhiteSpace($rawTypeGuid)) { $null } else { $rawTypeGuid }
        typeStatus  = $typeStatus
        name        = if ([string]::IsNullOrWhiteSpace($name)) { $null } else { $name }
        guid        = if ([string]::IsNullOrWhiteSpace($guid)) { $null } else { $guid }
        parent      = $parent
        parentType  = $parentType
        identityKey = $identityKey
    }
}

function Get-ObjectsByTypeMap {
    param($InventoryItems)

    $map = [ordered]@{}
    foreach ($item in @($InventoryItems | Where-Object { $_.sourceBlock -eq 'Objects' -and -not [string]::IsNullOrWhiteSpace($_.typeName) })) {
        $key = [string]$item.typeName
        if ($map.Contains($key)) {
            $map[$key] = [int]$map[$key] + 1
        } else {
            $map[$key] = 1
        }
    }
    return $map
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "BLOCK: InputPath not found: $InputPath"
}

$catalogResolution = Resolve-GeneXusObjectTypeCatalogPaths -BaseCatalogPath $CatalogPath -CatalogOverridePath $CatalogOverridePath -KbWorkspaceRoot $KbWorkspaceRoot
$CatalogPath = $catalogResolution.BaseCatalogPath
$guidMap = Get-GeneXusCatalogGuidToTypeMap -MergedCatalog $catalogResolution.MergedCatalog
$catalogFolderMap = Get-GeneXusCatalogGuidToFolderMap -MergedCatalog $catalogResolution.MergedCatalog

if (-not $PlatformObjectsCatalogPath) {
    $PlatformObjectsCatalogPath = Join-Path $PSScriptRoot 'gx-platform-objects.json'
}
$platformCatalog = Import-GeneXusPlatformObjectsCatalog -CatalogPath $PlatformObjectsCatalogPath
$platformKindSets = Get-PlatformObjectKindSets -Catalog $platformCatalog

$package = Get-ExportFileXmlDocument -Path $InputPath
$root = $package.Document.DocumentElement
if ($null -eq $root -or $root.LocalName -ne 'ExportFile') {
    $found = if ($null -eq $root) { '<null>' } else { $root.LocalName }
    throw ("BLOCK: expected root 'ExportFile'; found '{0}'." -f $found)
}

$inventory = [System.Collections.Generic.List[pscustomObject]]::new()
$legacyFormatDetected = $false
$legacyRegistry = $null

# Profile classification BEFORE iterating and BEFORE unknown-type discovery.
# A MIXED export package (legacy <GXObject> + modern <Objects>/<Attributes> in the same
# ExportFile) is fail-closed.
if (Test-GeneXusMixedExportFilePackage -XmlDocument $package.Document) {
    throw "BLOCK: MIXED export package (legacy <GXObject> and modern <Objects>/<Attributes> elements in the same ExportFile); out of scope for the legacy export engine. Inventory the formats separately."
}

# A translated .xpw always takes the legacy branch, even with no GXObject (attributes only).
if ($package.IsXpw -or (Test-GeneXusLegacyExportFilePackage -XmlDocument $package.Document)) {
    # ===== LEGACY BRANCH (GeneXus 9 export; GeneXus 7.0 and earlier .xpw, translated): known-legacy items via the shared support =====
    # synthetic rootKind Object/Attribute, typeStatus='known-legacy', guid=null, typeName
    # non-null, legacyElement=<tag> (contract section 4.3). ./GXObject and ./Attributes/GXAtt.
    $legacyFormatDetected = $true
    $legacyRegistry = Get-GeneXusLegacyExportElementRegistry
    $legacyInventory = Get-GeneXusLegacyExportFileInventoryItems -XmlDocument $package.Document -MergedCatalog $catalogResolution.MergedCatalog -Registry $legacyRegistry
    foreach ($legacyItem in $legacyInventory.Items) {
        $inventory.Add($legacyItem) | Out-Null
    }
}
else {
    # ===== MODERN BRANCH (unchanged) =====
    $objectsNode = $root.SelectSingleNode('./Objects')
    if ($null -ne $objectsNode) {
        $index = 0
        foreach ($child in @($objectsNode.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] })) {
            $index += 1
            $inventory.Add((New-InventoryItem -Node $child -GuidMap $guidMap -SourceBlock 'Objects' -Index $index)) | Out-Null
        }
    }

    $attributesNode = $root.SelectSingleNode('./Attributes')
    if ($null -ne $attributesNode) {
        $index = 0
        foreach ($child in @($attributesNode.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] })) {
            $index += 1
            $inventory.Add((New-InventoryItem -Node $child -GuidMap $guidMap -SourceBlock 'Attributes' -Index $index)) | Out-Null
        }
    }
}

$inventoryArray = @($inventory)
$objectItems = @($inventoryArray | Where-Object { $_.sourceBlock -eq 'Objects' })
$attributeItems = @($inventoryArray | Where-Object { $_.sourceBlock -eq 'Attributes' })

$warnings = [System.Collections.Generic.List[string]]::new()
$unknownTypeItems = @($inventoryArray | Where-Object { $_.typeStatus -eq 'unknown' })
foreach ($item in $unknownTypeItems) {
    $parentHint = if (-not [string]::IsNullOrWhiteSpace($item.parent)) { " parent='$($item.parent)'" } else { '' }
    $parentTypeHint = if (-not [string]::IsNullOrWhiteSpace($item.parentType)) { " parentType='$($item.parentType)'" } else { '' }
    $warnings.Add(("type not mapped in item {0}[{1}] name='{2}' typeGuid='{3}'{4}{5}" -f $item.sourceBlock, $item.index, $item.name, $item.typeGuid, $parentHint, $parentTypeHint)) | Out-Null
}

# On the legacy branch, the fail-closed for an unknown tag lives in the parser
# (Get-GeneXusLegacyExportFile*), not in modern GUID-based discovery: unknownTypeCount=0
# (typeStatus='known-legacy') and unknownTypesDiscovery=empty.
# Statement form (not an if-expression): under StrictMode, '$x = if (...) { @() }' would collapse
# @() to $null and break .Count downstream.
if ($legacyFormatDetected) {
    $unknownTypesDiscovery = @()
} else {
    $unknownTypesDiscovery = @(Get-GeneXusUnknownObjectTypesFromExportFile -XmlDocument $package.Document -GuidToFolderMap $catalogFolderMap)
}

$objectsByType = Get-ObjectsByTypeMap -InventoryItems $inventoryArray

# Objects repeated inside the export: the same type and name more than once (a GeneXus 6 export
# re-emits a style object each time it is referenced). objectCount and objectsByType count
# entries; distinctObjectCount and distinctObjectsByType count each object once, and
# duplicatesInExport names the repeats. This key is the object's identity (type, or type GUID when
# the type is unknown, and name); the sync recognizes a repeat by its target file instead
# (folder and normalized file name), which is the same object for every catalogued type. An entry
# with no name is its own object.
function Get-ObjectTypeLabel($Item) { if ($Item.typeName) { [string]$Item.typeName } else { [string]$Item.typeGuid } }
$objectGroups = @($objectItems | Group-Object -Property {
        if ([string]::IsNullOrWhiteSpace($_.name)) { "#entry:$($_.sourceBlock):$($_.index)" }
        else { ('{0}:{1}' -f (Get-ObjectTypeLabel $_), $_.name).ToLowerInvariant() }
    })
$repeatedGroups = @($objectGroups | Where-Object { $_.Count -gt 1 })
$distinctObjectItems = @($objectGroups | ForEach-Object { $_.Group[0] })
$distinctObjectsByType = Get-ObjectsByTypeMap -InventoryItems $distinctObjectItems
$duplicatesInExport = [ordered]@{
    count = [int](($repeatedGroups | ForEach-Object { $_.Count - 1 } | Measure-Object -Sum).Sum)
    items = @($repeatedGroups | ForEach-Object {
            [ordered]@{ type = (Get-ObjectTypeLabel $_.Group[0]); name = [string]$_.Group[0].name; copies = $_.Count }
        })
}
if ($repeatedGroups.Count -gt 0) {
    $repeatedList = @($repeatedGroups | ForEach-Object { '{0}:{1} x{2}' -f (Get-ObjectTypeLabel $_.Group[0]), $_.Group[0].name, $_.Count }) -join ', '
    $warnings.Add(("objects repeated inside the export ({0} extra copies): {1}; distinctObjectCount and distinctObjectsByType count each object once" -f $duplicatesInExport.count, $repeatedList)) | Out-Null
}
$systemObjectsPresent = @(Get-SystemObjectsPresent -InventoryItems $inventoryArray -PlatformKindSets $platformKindSets)

# Ready-made message (GUID, type name and package from the package's Dependencies block,
# count, sample names): the sync wrapper surfaces it when the pre-scan blocks.
$unknownTypesMessage = $null
if ($unknownTypesDiscovery.Count -gt 0) {
    $unknownTypesMessage = Format-GeneXusUnknownObjectTypesErrorMessage -UnknownTypes $unknownTypesDiscovery -OverrideActive ([bool]$catalogResolution.OverrideActive)
}

$status = 'INVENTORY_OK'
$exitCode = 0

if ($unknownTypesDiscovery.Count -gt 0 -and $FailOnUnknownTypes) {
    $status = 'UNKNOWN_TYPES_BLOCKED'
    $exitCode = 3
    $warnings.Add('pre-scan blocked: types not mapped in the effective catalog; resolve before Sync-GeneXusXpzToXml.ps1') | Out-Null
}

$overrideReminder = $null
if (-not [string]::IsNullOrWhiteSpace($KbWorkspaceRoot)) {
    $overrideReminder = Get-GeneXusCatalogOverrideSessionReminder -KbWorkspaceRoot $KbWorkspaceRoot -CatalogOverridePath $CatalogOverridePath
    if ($overrideReminder.noticeRequired -and -not [string]::IsNullOrWhiteSpace($overrideReminder.message)) {
        $warnings.Add($overrideReminder.message) | Out-Null
    }
}

$result = [ordered]@{
    status               = $status
    exitCode             = $exitCode
    inputPath            = $package.ResolvedPath
    inputKind            = $package.InputKind
    innerXmlEntry        = $package.InnerXmlName
    rootElement          = $root.LocalName
    legacyFormatDetected = $legacyFormatDetected
    totalItemCount       = $inventoryArray.Count
    objectCount          = $objectItems.Count
    attributeCount       = $attributeItems.Count
    objectsByType                 = $objectsByType
    distinctObjectCount           = $distinctObjectItems.Count
    distinctObjectsByType         = $distinctObjectsByType
    duplicatesInExport            = $duplicatesInExport
    systemObjectsPresent          = @($systemObjectsPresent)
    unknownTypeCount              = $unknownTypeItems.Count
    unknownTypesDiscovery         = $unknownTypesDiscovery
    unknownTypesMessage           = $unknownTypesMessage
    catalogOverrideActive         = $catalogResolution.OverrideActive
    catalogOverridePath           = $catalogResolution.OverridePath
    catalogUpstreamPending        = $catalogResolution.UpstreamPending
    catalogOverrideReminder       = $overrideReminder
    inventory            = $inventoryArray
    warnings             = @($warnings)
}

[pscustomobject]$result | ConvertTo-Json -Depth 10

exit $exitCode
