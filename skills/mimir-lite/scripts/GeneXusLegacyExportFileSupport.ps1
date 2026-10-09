#requires -Version 7.4
<#
.SYNOPSIS
    Support for parsing and materializing legacy GeneXus 9 ExportFile packages
    (/ExportFile/GXObject/<Elemento>, identified by NAME, no type GUID).

.DESCRIPTION
    Its OWN converter (does not reuse Convert-PackageToItems) that adapts pre-modern
    (GeneXus 9) exports into Object/Attribute envelopes recognizable by the KbObjectsXml
    XML corpus, CONSUMING the scripts/gx-legacy-export-element-registry.json registry (classes
    'equivalent'/'orphan') WITHOUT polluting the modern gx-object-type-catalog.json catalog.

    Doc owner of the representation: 01k-legacy-element-registry.md.

    Receives the [xml] ALREADY loaded encoding-aware (the iso-8859-1 read fix is local
    to Sync/Inventory) and the MergedCatalog ALREADY resolved; does not open, re-read, or
    unzip any file.

    Key rules:
    - Shared profile detection (Test-GeneXusLegacyExportFilePackage / ...Mixed...).
    - A MIXED package (GXObject + modern Objects/Object|Attributes/Attribute) = fail-closed.
    - Tag not in the registry / >1 child element per GXObject / name collision = fail-closed.
    - Missing/invalid lastUpdate => deterministic sentinel 0001-01-01 (NEVER Get-Date).
    - Legacy items expose Guid='' (do not participate in GUID-based rename).
#>

Set-StrictMode -Version Latest

$script:LegacyExportSupportRoot = Split-Path -Parent $PSCommandPath

$utf8NoBomEncodingSupportPath = Join-Path $script:LegacyExportSupportRoot 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "Required support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$fileBaseNameNormalizationSupportPath = Join-Path $script:LegacyExportSupportRoot 'GeneXusFileBaseNameNormalizationSupport.ps1'
if (-not (Test-Path -LiteralPath $fileBaseNameNormalizationSupportPath -PathType Leaf)) {
    throw "Required support script not found: $fileBaseNameNormalizationSupportPath"
}
. $fileBaseNameNormalizationSupportPath

# Deterministic sentinel for missing/invalid lastUpdate (NEVER Get-Date).
$script:LegacyExportSentinelLastUpdate = '0001-01-01T00:00:00.0000000Z'
$script:LegacyExportDataSourceAttribute = 'gx-legacy-export'
$script:LegacyExportPayloadElementName = 'GxLegacyPayload'
$script:LegacyExportRegistryCache = $null

function Get-GeneXusLegacyExportElementRegistryPath {
    return (Join-Path $script:LegacyExportSupportRoot 'gx-legacy-export-element-registry.json')
}

function Get-GeneXusLegacyExportElementRegistry {
    <# Loads (with caching) the legacy element registry. #>
    if ($null -ne $script:LegacyExportRegistryCache) {
        return $script:LegacyExportRegistryCache
    }
    $registryPath = Get-GeneXusLegacyExportElementRegistryPath
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
        throw "Legacy export element registry not found: $registryPath"
    }
    $raw = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8
    $script:LegacyExportRegistryCache = ($raw | ConvertFrom-Json)
    return $script:LegacyExportRegistryCache
}

function Get-GeneXusLegacyRegistryElementMap {
    <# Returns a hashtable: legacy tag (case-sensitive) -> registry element object. #>
    param([object]$Registry)

    if ($null -eq $Registry) {
        $Registry = Get-GeneXusLegacyExportElementRegistry
    }
    if ($null -eq $Registry.PSObject.Properties['elements'] -or $null -eq $Registry.elements) {
        throw "Legacy export registry has no 'elements' property."
    }
    $map = @{}
    foreach ($property in $Registry.elements.PSObject.Properties) {
        $map[$property.Name] = $property.Value
    }
    return $map
}

function Get-LegacyElementPropertyValue {
    <# StrictMode-safe read of an optional property of a registry element. #>
    param(
        [object]$Element,
        [string]$Name
    )
    $prop = $Element.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Test-GeneXusLegacyExportFilePackage {
    <# Pure legacy: /ExportFile/GXObject exists and none of the modern ones (Objects/Object, Attributes/Attribute). #>
    param([xml]$XmlDocument)

    if ($null -eq $XmlDocument -or $null -eq $XmlDocument.DocumentElement -or $XmlDocument.DocumentElement.LocalName -ne 'ExportFile') {
        return $false
    }
    $hasGxObject = $null -ne $XmlDocument.SelectSingleNode('/ExportFile/GXObject')
    if (-not $hasGxObject) { return $false }
    $modernObjectCount = @($XmlDocument.SelectNodes('/ExportFile/Objects/Object')).Count
    $modernAttributeCount = @($XmlDocument.SelectNodes('/ExportFile/Attributes/Attribute')).Count
    return ($modernObjectCount -eq 0) -and ($modernAttributeCount -eq 0)
}

function Test-GeneXusMixedExportFilePackage {
    <# Mixed: GXObject present AND some modern one (Objects/Object or Attributes/Attribute). Out of scope => fail-closed in the caller. #>
    param([xml]$XmlDocument)

    if ($null -eq $XmlDocument -or $null -eq $XmlDocument.DocumentElement -or $XmlDocument.DocumentElement.LocalName -ne 'ExportFile') {
        return $false
    }
    $hasGxObject = $null -ne $XmlDocument.SelectSingleNode('/ExportFile/GXObject')
    if (-not $hasGxObject) { return $false }
    $modernObjectCount = @($XmlDocument.SelectNodes('/ExportFile/Objects/Object')).Count
    $modernAttributeCount = @($XmlDocument.SelectNodes('/ExportFile/Attributes/Attribute')).Count
    return ($modernObjectCount -gt 0) -or ($modernAttributeCount -gt 0)
}

function Convert-GeneXusLegacyLastUpdateToIso8601 {
    <# "YYYY-MM-DD HH:MM:SSGMT" -> "YYYY-MM-DDTHH:MM:SS.0000000Z". Missing/invalid -> sentinel. #>
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return $script:LegacyExportSentinelLastUpdate
    }
    $match = [regex]::Match($Raw, '(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})')
    if ($match.Success) {
        return '{0}T{1}.0000000Z' -f $match.Groups[1].Value, $match.Groups[2].Value
    }
    return $script:LegacyExportSentinelLastUpdate
}

function Get-GeneXusLegacyCatalogMaps {
    <# From the modern MergedCatalog: catalogType -> folderName and catalogType -> objectTypeGuid. #>
    param([object]$MergedCatalog)

    if ($null -eq $MergedCatalog -or $null -eq $MergedCatalog.PSObject.Properties['types'] -or $null -eq $MergedCatalog.types) {
        throw "Invalid MergedCatalog (no 'types')."
    }
    $canonicalToFolder = @{}
    $canonicalToGuid = @{}
    foreach ($property in $MergedCatalog.types.PSObject.Properties) {
        $entry = $property.Value
        $canonicalName = [string]$property.Name
        $folderProp = $entry.PSObject.Properties['folderName']
        $folderName = if ($null -ne $folderProp -and -not [string]::IsNullOrWhiteSpace([string]$folderProp.Value)) { [string]$folderProp.Value } else { $canonicalName }
        $canonicalToFolder[$canonicalName] = $folderName
        $guidProp = $entry.PSObject.Properties['objectTypeGuid']
        if ($null -ne $guidProp -and -not [string]::IsNullOrWhiteSpace([string]$guidProp.Value)) {
            $canonicalToGuid[$canonicalName] = [string]$guidProp.Value
        }
    }
    return @{ CanonicalToFolder = $canonicalToFolder; CanonicalToGuid = $canonicalToGuid }
}

function Get-GeneXusLegacyExportObjectName {
    param([System.Xml.XmlElement]$TypeElement)

    $infoName = $TypeElement.SelectSingleNode('./Info/Name')
    if ($null -ne $infoName -and -not [string]::IsNullOrWhiteSpace($infoName.InnerText)) {
        return $infoName.InnerText.Trim()
    }
    throw "Legacy export: name not found in Info/Name for element '$($TypeElement.LocalName)'."
}

function Get-GeneXusLegacyObjectTypeElement {
    <# First (and only) child element of <GXObject>. >1 child element => defensive fail-closed. #>
    param([System.Xml.XmlElement]$GxObject)

    $elementChildren = @($GxObject.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })
    if ($elementChildren.Count -eq 0) {
        return $null
    }
    if ($elementChildren.Count -gt 1) {
        $tags = ($elementChildren | ForEach-Object { $_.LocalName }) -join ', '
        throw "Legacy export: <GXObject> with more than one child element ($tags); unexpected structure (assumption: 1 type-element per GXObject). Defensive fail-closed."
    }
    return [System.Xml.XmlElement]$elementChildren[0]
}

function New-GeneXusLegacyWrappedXml {
    <# Modern envelope: lastUpdate injected as a root ATTRIBUTE (ensures Get-LastUpdateInfoFromNode works). #>
    param(
        [ValidateSet('Object', 'Attribute')][string]$RootTag,
        [string]$TypeAttribute,
        [string]$Name,
        [string]$LastUpdate,
        [System.Xml.XmlElement]$LegacyInnerElement
    )

    $escapedName = [System.Security.SecurityElement]::Escape($Name)
    $legacyXml = $LegacyInnerElement.OuterXml
    $payloadTag = $script:LegacyExportPayloadElementName
    $dataSource = $script:LegacyExportDataSourceAttribute
    $typeAttr = if ($RootTag -eq 'Object') { ' type="' + [System.Security.SecurityElement]::Escape($TypeAttribute) + '"' } else { '' }
    return @"
<?xml version="1.0" encoding="utf-8"?>
<$RootTag$typeAttr name="$escapedName" guid="" lastUpdate="$LastUpdate" dataSource="$dataSource">
  <$payloadTag>
$legacyXml
  </$payloadTag>
</$RootTag>
"@
}

function Import-GeneXusLegacyWrappedXmlNode {
    param([string]$XmlText)

    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $true
    $document.LoadXml($XmlText)
    return $document.DocumentElement
}

function Test-GeneXusLegacyItemNameCollision {
    <# Same detection as the modern one (Convert-PackageToItems): FolderType|NormalizedName with distinct logical names => throw. #>
    param([object[]]$Items)

    $collisions = @(
        $Items |
        Group-Object { "$($_.FolderType)|$($_.NormalizedName)" } |
        Where-Object {
            $_.Count -gt 1 -and
            @($_.Group | Select-Object -ExpandProperty LogicalName | Sort-Object -Unique).Count -gt 1
        }
    )
    if ($collisions.Count -gt 0) {
        $details = foreach ($collision in $collisions) {
            $names = $collision.Group | Select-Object -ExpandProperty LogicalName | Sort-Object -Unique
            "$($collision.Name) <= $($names -join ', ')"
        }
        throw "Legacy export: normalized name collision detected: $($details -join '; ')"
    }
}

function Get-GeneXusLegacyExportFileSyncItems {
    <#
        Its own converter. Returns { Items[] } in the SAME shape as the modern items
        (PackageSection/RootTag/FolderType/LogicalName/NormalizedName/TypeGuid/Guid/Node),
        for transparent reuse by Write-ItemToDestination / Resolve-GuidAwareRenames /
        Test-PackageMaterialization. Tag not in the registry => fail-closed (exception with tag,
        count, and registry extension path).
    #>
    param(
        [xml]$XmlDocument,
        [object]$MergedCatalog,
        [object]$Registry,
        [scriptblock]$NormalizeFileBaseName
    )

    if ($null -eq $NormalizeFileBaseName) {
        $NormalizeFileBaseName = { param($LogicalName) Normalize-FileBaseName -LogicalName $LogicalName }
    }
    $registryMap = Get-GeneXusLegacyRegistryElementMap -Registry $Registry
    $catalogMaps = Get-GeneXusLegacyCatalogMaps -MergedCatalog $MergedCatalog
    $items = New-Object System.Collections.Generic.List[object]
    $unmappedCounts = @{}

    foreach ($gxObject in $XmlDocument.SelectNodes('/ExportFile/GXObject')) {
        $typeElement = Get-GeneXusLegacyObjectTypeElement -GxObject ([System.Xml.XmlElement]$gxObject)
        if ($null -eq $typeElement) { continue }

        $legacyTag = $typeElement.LocalName
        if (-not $registryMap.ContainsKey($legacyTag)) {
            if ($unmappedCounts.ContainsKey($legacyTag)) { $unmappedCounts[$legacyTag] = [int]$unmappedCounts[$legacyTag] + 1 } else { $unmappedCounts[$legacyTag] = 1 }
            continue
        }

        $element = $registryMap[$legacyTag]
        $class = [string](Get-LegacyElementPropertyValue -Element $element -Name 'class')
        $logicalName = Get-GeneXusLegacyExportObjectName -TypeElement $typeElement
        $lastUpdateNode = $typeElement.SelectSingleNode('./LastUpdate')
        $rawLastUpdate = if ($null -ne $lastUpdateNode) { $lastUpdateNode.InnerText } else { '' }
        $lastUpdate = Convert-GeneXusLegacyLastUpdateToIso8601 -Raw $rawLastUpdate

        if ($class -eq 'equivalent') {
            $catalogType = [string](Get-LegacyElementPropertyValue -Element $element -Name 'catalogType')
            if (-not $catalogMaps.CanonicalToFolder.ContainsKey($catalogType) -or -not $catalogMaps.CanonicalToGuid.ContainsKey($catalogType)) {
                throw "Legacy export: element '$legacyTag' maps to '$catalogType' (equivalent), but the effective catalog has no folder/GUID for that type."
            }
            $typeAttribute = $catalogMaps.CanonicalToGuid[$catalogType]
            $folderType = $catalogMaps.CanonicalToFolder[$catalogType]
            $canonicalType = $catalogType
        }
        elseif ($class -eq 'orphan') {
            $typeAttribute = [string](Get-LegacyElementPropertyValue -Element $element -Name 'typeToken')
            $folderType = [string](Get-LegacyElementPropertyValue -Element $element -Name 'materializedFolderName')
            $canonicalType = $typeAttribute
        }
        else {
            throw "Legacy export: unknown class '$class' for element '$legacyTag' in the registry."
        }

        $xmlText = New-GeneXusLegacyWrappedXml -RootTag 'Object' -TypeAttribute $typeAttribute -Name $logicalName -LastUpdate $lastUpdate -LegacyInnerElement $typeElement
        $node = Import-GeneXusLegacyWrappedXmlNode -XmlText $xmlText

        $items.Add([pscustomobject]@{
            PackageSection = 'Objects'
            RootTag        = 'Object'
            FolderType     = $folderType
            LogicalName    = $logicalName
            NormalizedName = (& $NormalizeFileBaseName $logicalName)
            TypeGuid       = $typeAttribute
            Guid           = ''
            LegacyElement  = $legacyTag
            CanonicalType  = $canonicalType
            Node           = $node
        }) | Out-Null
    }

    if ($unmappedCounts.Count -gt 0) {
        $details = ($unmappedCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) (x$($_.Value))" }) -join ', '
        throw ("Legacy export: GXObject element(s) not in the registry: {0}. Extend 'scripts/gx-legacy-export-element-registry.json' (doc owner 01k-legacy-element-registry.md) before materializing." -f $details)
    }

    foreach ($gxAtt in $XmlDocument.SelectNodes('/ExportFile/Attributes/GXAtt')) {
        $attributeNode = $gxAtt.SelectSingleNode('./Attribute')
        if ($null -eq $attributeNode) { continue }
        $nameNode = $attributeNode.SelectSingleNode('./Name')
        if ($null -eq $nameNode -or [string]::IsNullOrWhiteSpace($nameNode.InnerText)) { continue }

        $logicalName = $nameNode.InnerText.Trim()
        $lastUpdateNode = $attributeNode.SelectSingleNode('./LastUpdate')
        $rawLastUpdate = if ($null -ne $lastUpdateNode) { $lastUpdateNode.InnerText } else { '' }
        $lastUpdate = Convert-GeneXusLegacyLastUpdateToIso8601 -Raw $rawLastUpdate

        $xmlText = New-GeneXusLegacyWrappedXml -RootTag 'Attribute' -TypeAttribute '' -Name $logicalName -LastUpdate $lastUpdate -LegacyInnerElement ([System.Xml.XmlElement]$gxAtt)
        $node = Import-GeneXusLegacyWrappedXmlNode -XmlText $xmlText

        $items.Add([pscustomobject]@{
            PackageSection = 'Attributes'
            RootTag        = 'Attribute'
            FolderType     = 'Attribute'
            LogicalName    = $logicalName
            NormalizedName = (& $NormalizeFileBaseName $logicalName)
            TypeGuid       = 'attribute-top-level'
            Guid           = ''
            LegacyElement  = 'GXAtt'
            CanonicalType  = 'Attribute'
            Node           = $node
        }) | Out-Null
    }

    $itemArray = @($items.ToArray())
    Test-GeneXusLegacyItemNameCollision -Items $itemArray
    return [pscustomobject]@{ Items = $itemArray }
}

function Get-GeneXusLegacyExportFileInventoryItems {
    <# Legacy inventory items (typeStatus='known-legacy', synthetic rootKind, non-null typeName). #>
    param(
        [xml]$XmlDocument,
        [object]$MergedCatalog,
        [object]$Registry
    )

    $sync = Get-GeneXusLegacyExportFileSyncItems -XmlDocument $XmlDocument -MergedCatalog $MergedCatalog -Registry $Registry
    $inventory = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($item in $sync.Items) {
        $index += 1
        $isAttribute = ($item.RootTag -eq 'Attribute')
        $inventory.Add([pscustomobject]@{
            index         = $index
            sourceBlock   = if ($isAttribute) { 'Attributes' } else { 'Objects' }
            rootKind      = if ($isAttribute) { 'Attribute' } else { 'Object' }
            type          = $item.CanonicalType
            typeName      = $item.CanonicalType
            typeGuid      = if ($isAttribute) { $null } else { $item.TypeGuid }
            typeStatus    = 'known-legacy'
            name          = $item.LogicalName
            guid          = $null
            legacyElement = $item.LegacyElement
            parent        = $null
            parentType    = $null
            identityKey   = "$($item.CanonicalType):$($item.LogicalName)"
        }) | Out-Null
    }
    return [pscustomobject]@{ Items = @($inventory.ToArray()); TotalCount = $inventory.Count }
}

function Get-GeneXusLegacyKmwBuildFromPackage {
    param([xml]$XmlDocument)
    $kmwNode = $XmlDocument.SelectSingleNode('/ExportFile/KMW')
    if ($null -eq $kmwNode) { return '' }
    $buildNode = $kmwNode.SelectSingleNode('Build')
    if ($null -ne $buildNode -and -not [string]::IsNullOrWhiteSpace($buildNode.InnerText)) { return $buildNode.InnerText.Trim() }
    $legacyBuildNode = $kmwNode.SelectSingleNode('MaxGxBuildSaved')
    if ($null -ne $legacyBuildNode -and -not [string]::IsNullOrWhiteSpace($legacyBuildNode.InnerText)) { return $legacyBuildNode.InnerText.Trim() }
    return ''
}

function Get-GeneXusLegacyModelNameFromPackage {
    param([xml]$XmlDocument)
    $node = $XmlDocument.SelectSingleNode('/ExportFile/Model/Name')
    if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) { return $node.InnerText.Trim() }
    return ''
}

function Get-GeneXusLegacyKmwPathFromPackage {
    param([xml]$XmlDocument)
    $node = $XmlDocument.SelectSingleNode('/ExportFile/KMW/Path')
    if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) { return $node.InnerText.Trim() }
    return ''
}
