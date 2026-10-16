#requires -Version 7.4

<#
.SYNOPSIS
Extracts and verifies objects exported from a GeneXus XPZ/XML package.

.DESCRIPTION
Reads a GeneXus package exported from an .xpz file, an .xml file,
or a folder containing that XML, or a GeneXus 7.0 and earlier text export (a .xpw file, or a
.zip of .xpw files, translated in memory into the classic legacy XML), materializes the exported objects into a
directory tree by type, and can verify whether the package was correctly
reflected at the destination.

.PARAMETER InputPath
Path to an .xpz, to the exported package's XML, to the folder that contains
that XML, to a .xpw text export, or to a .zip of .xpw files (for example the 1997 layout,
an objects file and an attributes file, merged into one export). A zip that mixes .xpw and
.xml entries fails closed; a .zip with no .xpw entry is unsupported, as before.

.PARAMETER DestinationRoot
Root of the tree of XMLs individualized by type.

.PARAMETER VerifyOnly
Runs only a check, without rewriting files at the destination.

.PARAMETER FullSnapshot
In addition to checking the current package, compares the destination's entire
snapshot against the package's content. Use this mode for full KB exports.

.PARAMETER ReportPath
Optional path to save a JSON report with the result.

.PARAMETER KeepReport
Keeps the JSON report even when the run finishes without error.

.PARAMETER ExpectedItems
Optional list of expected items to compare against the XPZ's official return,
in `Type:Name` format.

.PARAMETER KbMetadataPath
Optional path to the KB workspace's kb-source-metadata.md.

.PARAMETER CatalogPath
Optional path to gx-object-type-catalog.json (default: the shared base's scripts/).

.PARAMETER CatalogOverridePath
Optional path to gx-object-type-catalog.override.json (local stopgap; not silent).

.PARAMETER KbWorkspaceRoot
Root of the KB workspace; when provided, resolves the override at scripts/gx-object-type-catalog.override.json.

.PARAMETER DiscoveryReportPath
When the package has an unknown type GUID, writes a JSON triage report before failing.

.PARAMETER BlockCrossFlowDataSource
Opt-in block: when an incoming item collides in the XML corpus with a divergent
source (`dataSource`) file — the central modern<->legacy case (GeneXus 9 export) —, aborts the sync
BEFORE writing metadata or XML, instead of the default fail-soft behavior (which only signals the
collision in `Summary.CrossFlowCollisions` and on stderr and continues). Separate from the
mixed-package fail-closed. Regarding an existing **unparseable** XML: detection neither produces a
collision nor blocks (not even under this switch), only a warning — but that **does not guarantee
the overwrite**: the sync may still fail further ahead while processing an existing corrupted file
(in the existing parse stages, which this detection does not cover).

.EXAMPLE
.\Sync-GeneXusXpzToXml.ps1 -InputPath C:\Exports\MyPackage.xpz -DestinationRoot C:\Corpus\KbObjectsXml

.EXAMPLE
.\Sync-GeneXusXpzToXml.ps1 -InputPath C:\Exports\MyFull.xml -DestinationRoot C:\Corpus\KbObjectsXml -VerifyOnly -FullSnapshot
#>

param(
    [Parameter(Mandatory = $true)]
    [Alias('Path')]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot,

    [switch]$VerifyOnly,

    [switch]$FullSnapshot,

    [string]$ReportPath,

    [switch]$KeepReport,

    [string[]]$ExpectedItems = @(),

    [string]$KbMetadataPath = "",

    [string]$CatalogPath = "",

    [string]$CatalogOverridePath = "",

    [string]$KbWorkspaceRoot = "",

    [string]$DiscoveryReportPath = "",

    [switch]$BlockCrossFlowDataSource
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$utf8NoBomEncodingSupportPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$kbMetadataEditSupportScript = Join-Path $PSScriptRoot 'MimirKbSourceMetadataEditSupport.ps1'
if (-not (Test-Path -LiteralPath $kbMetadataEditSupportScript -PathType Leaf)) {
    throw "BLOCK: kb-source-metadata edit support not found: $kbMetadataEditSupportScript"
}

. $kbMetadataEditSupportScript

$supportScript = Join-Path $PSScriptRoot 'GeneXusObjectTypeCatalogSupport.ps1'
if (-not (Test-Path -LiteralPath $supportScript -PathType Leaf)) {
    throw "Required support script not found: $supportScript"
}
. $supportScript

$fileBaseNameNormalizationSupportScript = Join-Path $PSScriptRoot 'GeneXusFileBaseNameNormalizationSupport.ps1'
if (-not (Test-Path -LiteralPath $fileBaseNameNormalizationSupportScript -PathType Leaf)) {
    throw "Required support script not found: $fileBaseNameNormalizationSupportScript"
}
. $fileBaseNameNormalizationSupportScript

$legacyExportSupportScript = Join-Path $PSScriptRoot 'GeneXusLegacyExportFileSupport.ps1'
if (-not (Test-Path -LiteralPath $legacyExportSupportScript -PathType Leaf)) {
    throw "Required support script not found: $legacyExportSupportScript"
}
. $legacyExportSupportScript

$xpwExportSupportScript = Join-Path $PSScriptRoot 'GeneXusXpwExportFileSupport.ps1'
if (-not (Test-Path -LiteralPath $xpwExportSupportScript -PathType Leaf)) {
    throw "Required support script not found: $xpwExportSupportScript"
}
. $xpwExportSupportScript

function New-TempDirectory {
    $tempBase = [System.IO.Path]::GetTempPath()
    $tempName = "gx-xpz-" + [System.Guid]::NewGuid().ToString("N")
    $tempPath = Join-Path $tempBase $tempName
    [System.IO.Directory]::CreateDirectory($tempPath) | Out-Null
    return $tempPath
}

function Resolve-PackageXmlPath {
    param([string]$RawInputPath)

    $resolved = (Resolve-Path -LiteralPath $RawInputPath).Path

    if (Test-Path -LiteralPath $resolved -PathType Container) {
        $xmlFiles = @(Get-ChildItem -LiteralPath $resolved -Filter *.xml -File)
        if ($xmlFiles.Count -ne 1) {
            throw "Expected exactly one XML file inside folder '$resolved', found $($xmlFiles.Count)."
        }
        return @{
            XmlPath = $xmlFiles[0].FullName
            TempPath = $null
            XpwDocument = $null
        }
    }

    if ($resolved.ToLowerInvariant().EndsWith(".xml")) {
        return @{
            XmlPath = $resolved
            TempPath = $null
            XpwDocument = $null
        }
    }

    # GeneXus 7.0 and earlier: a .xpw text export, or a .zip holding .xpw files (the 1997 layout
    # splits objects and attributes). Translated in memory into the classic ExportFile XML;
    # XmlPath then names the input itself (there is no package XML on disk).
    if (Test-GeneXusXpwInputPath -Path $resolved) {
        return @{
            XmlPath = $resolved
            TempPath = $null
            XpwDocument = (Read-GeneXusXpwExportFile -Path $resolved)
        }
    }

    if ($resolved.ToLowerInvariant().EndsWith(".zip")) {
        $xpwZip = Read-GeneXusXpwZipExport -Path $resolved
        if ($null -ne $xpwZip) {
            return @{
                XmlPath = $resolved
                TempPath = $null
                XpwDocument = $xpwZip.Document
            }
        }
    }

    if ($resolved.ToLowerInvariant().EndsWith(".xpz")) {
        $tempPath = New-TempDirectory
        $zipPath = Join-Path $tempPath "package.zip"
        Copy-Item -LiteralPath $resolved -Destination $zipPath
        Expand-Archive -LiteralPath $zipPath -DestinationPath $tempPath -Force
        $xmlFiles = @(Get-ChildItem -LiteralPath $tempPath -Filter *.xml -File)
        if ($xmlFiles.Count -ne 1) {
            throw "Expected exactly one XML file inside XPZ '$resolved', found $($xmlFiles.Count)."
        }
        return @{
            XmlPath = $xmlFiles[0].FullName
            TempPath = $tempPath
            XpwDocument = $null
        }
    }

    throw "Unsupported InputPath '$resolved'. Use a folder, .xml, .xpz, .xpw, or a .zip of .xpw files."
}

function Convert-ExpectedItemsToComparison {
    param(
        [string[]]$ExpectedItems,
        [object[]]$ActualItems
    )

    $rawExpectedItems = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($ExpectedItems)) {
        if ($null -eq $entry) {
            continue
        }

        foreach ($part in ($entry -split '[,\r\n;]+')) {
            $normalizedPart = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($normalizedPart)) {
                $rawExpectedItems.Add($normalizedPart) | Out-Null
            }
        }
    }

    if ($rawExpectedItems.Count -eq 0) {
        return $null
    }

    $expectedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $expectedEntries = New-Object System.Collections.Generic.List[object]
    foreach ($rawItem in $rawExpectedItems) {
        $separatorIndex = $rawItem.IndexOf(':')
        if ($separatorIndex -lt 1 -or $separatorIndex -ge ($rawItem.Length - 1)) {
            throw "Invalid ExpectedItems entry '$rawItem'. Use the format 'Type:Name'."
        }

        $folderType = $rawItem.Substring(0, $separatorIndex).Trim()
        $logicalName = $rawItem.Substring($separatorIndex + 1).Trim()
        if ([string]::IsNullOrWhiteSpace($folderType) -or [string]::IsNullOrWhiteSpace($logicalName)) {
            throw "Invalid ExpectedItems entry '$rawItem'. Use the format 'Type:Name'."
        }

        $key = "$folderType|$logicalName"
        if ($expectedKeys.Add($key)) {
            $expectedEntries.Add([pscustomobject]@{
                FolderType = $folderType
                LogicalName = $logicalName
                Key = $key
            }) | Out-Null
        }
    }

    $actualKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $actualMap = @{}
    foreach ($item in $ActualItems) {
        $key = "$($item.FolderType)|$($item.LogicalName)"
        [void]$actualKeys.Add($key)
        if (-not $actualMap.ContainsKey($key)) {
            $actualMap[$key] = [pscustomobject]@{
                FolderType = $item.FolderType
                LogicalName = $item.LogicalName
                PackageSection = $item.PackageSection
            }
        }
    }

    $expectedReturned = New-Object System.Collections.Generic.List[object]
    $expectedMissing = New-Object System.Collections.Generic.List[object]
    foreach ($expectedEntry in $expectedEntries) {
        if ($actualKeys.Contains($expectedEntry.Key)) {
            $expectedReturned.Add([pscustomobject]@{
                FolderType = $expectedEntry.FolderType
                LogicalName = $expectedEntry.LogicalName
            }) | Out-Null
        } else {
            $expectedMissing.Add([pscustomobject]@{
                FolderType = $expectedEntry.FolderType
                LogicalName = $expectedEntry.LogicalName
            }) | Out-Null
        }
    }

    $additionalOfficial = New-Object System.Collections.Generic.List[object]
    foreach ($actualKey in $actualMap.Keys | Sort-Object) {
        if (-not $expectedKeys.Contains($actualKey)) {
            $additionalOfficial.Add($actualMap[$actualKey]) | Out-Null
        }
    }

    $expectedItemsForReport = New-Object System.Collections.Generic.List[object]
    foreach ($expectedEntry in $expectedEntries) {
        $expectedItemsForReport.Add([pscustomobject]@{
            FolderType = $expectedEntry.FolderType
            LogicalName = $expectedEntry.LogicalName
        }) | Out-Null
    }

    return [pscustomobject]@{
        ExpectedItemsProvided = $true
        ExpectedItems = @($expectedItemsForReport.ToArray())
        ExpectedReturned = @($expectedReturned.ToArray())
        ExpectedMissing = @($expectedMissing.ToArray())
        AdditionalOfficial = @($additionalOfficial.ToArray())
    }
}

function Format-ExpectedItemsSummary {
    param([object]$ExpectedComparison)

    if ($null -eq $ExpectedComparison) {
        return $null
    }

    $expectedCount = @($ExpectedComparison.ExpectedItems).Count
    $expectedReturnedCount = @($ExpectedComparison.ExpectedReturned).Count
    $expectedMissingCount = @($ExpectedComparison.ExpectedMissing).Count
    $additionalOfficialCount = @($ExpectedComparison.AdditionalOfficial).Count

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(
        "Workstream comparison: $expectedCount expected; $expectedReturnedCount returned; $expectedMissingCount did not return; $additionalOfficialCount additional official KB items."
    ) | Out-Null
    $lines.Add("Official materialization proceeded normally. The comparison is supplementary.") | Out-Null

    if ($additionalOfficialCount -gt 0) {
        $lines.Add("Additional items may represent an additional official KB return or a legitimate parallel change.") | Out-Null
    }

    if ($expectedMissingCount -gt 0) {
        $lines.Add("Expected items that are missing should be investigated in the workstream's context, without blocking the sync.") | Out-Null
    }

    return ($lines -join [Environment]::NewLine)
}

function Convert-PackageToItems {
    param(
        [xml]$XmlDocument,
        [hashtable]$CatalogGuidToFolderMap
    )

    $items = New-Object System.Collections.Generic.List[object]

    $objectsNode = $XmlDocument.SelectSingleNode("/ExportFile/Objects")
    if ($null -ne $objectsNode) {
        foreach ($node in $objectsNode.SelectNodes("./Object")) {
            $typeGuid = $node.GetAttribute("type").ToLowerInvariant()
            if (-not $CatalogGuidToFolderMap.ContainsKey($typeGuid)) {
                continue
            }

            $logicalName = $node.GetAttribute("name")
            $folderType = $CatalogGuidToFolderMap[$typeGuid]
            $normalizedName = Normalize-FileBaseName -LogicalName $logicalName
            $items.Add([pscustomobject]@{
                PackageSection = "Objects"
                RootTag = "Object"
                FolderType = $folderType
                LogicalName = $logicalName
                NormalizedName = $normalizedName
                TypeGuid = $typeGuid
                Guid = $node.GetAttribute("guid")
                Node = $node
            }) | Out-Null
        }
    }

    $attributesNode = $XmlDocument.SelectSingleNode("/ExportFile/Attributes")
    if ($null -ne $attributesNode) {
        foreach ($node in $attributesNode.SelectNodes("./Attribute")) {
            $logicalName = $node.GetAttribute("name")
            $normalizedName = Normalize-FileBaseName -LogicalName $logicalName
            $items.Add([pscustomobject]@{
                PackageSection = "Attributes"
                RootTag = "Attribute"
                FolderType = "Attribute"
                LogicalName = $logicalName
                NormalizedName = $normalizedName
                TypeGuid = "attribute-top-level"
                Guid = $node.GetAttribute("guid")
                Node = $node
            }) | Out-Null
        }
    }

    $collisions = @(
        $items |
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
        throw "Filename normalization collision detected: $($details -join '; ')"
    }

    return ,($items.ToArray())
}

function Convert-NodeToXmlString {
    param(
        [System.Xml.XmlNode]$Node
    )

    $doc = New-Object System.Xml.XmlDocument
    $declaration = $doc.CreateXmlDeclaration("1.0", "utf-8", $null)
    [void]$doc.AppendChild($declaration)
    $imported = $doc.ImportNode($Node, $true)
    [void]$doc.AppendChild($imported)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = (Get-Utf8NoBomEncoding)
    $settings.Indent = $true
    $settings.NewLineChars = "`r`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    $settings.OmitXmlDeclaration = $false

    $stream = New-Object System.IO.MemoryStream
    $writer = [System.Xml.XmlWriter]::Create($stream, $settings)
    $doc.Save($writer)
    $writer.Close()
    $bytes = $stream.ToArray()
    $stream.Dispose()
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Get-LastUpdateInfoFromXmlDocument {
    param(
        [xml]$XmlDocument,
        [string]$SourceLabel
    )

    $rootNode = $XmlDocument.DocumentElement
    if ($null -eq $rootNode) {
        throw "Missing root element while reading lastUpdate from $SourceLabel."
    }

    $rawValue = $rootNode.GetAttribute("lastUpdate")
    if ([string]::IsNullOrWhiteSpace($rawValue)) {
        throw "Missing lastUpdate on '$($rootNode.LocalName)' from $SourceLabel."
    }

    $parsedValue = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($rawValue, [ref]$parsedValue)) {
        throw "Invalid lastUpdate '$rawValue' on '$($rootNode.LocalName)' from $SourceLabel."
    }

    return [pscustomobject]@{
        RootTag = $rootNode.LocalName
        RawValue = $rawValue
        ParsedValue = $parsedValue.ToUniversalTime()
    }
}

function Get-LastUpdateInfoFromNode {
    param([System.Xml.XmlNode]$Node)

    $ownerDocument = New-Object System.Xml.XmlDocument
    $importedNode = $ownerDocument.ImportNode($Node, $true)
    [void]$ownerDocument.AppendChild($importedNode)
    return Get-LastUpdateInfoFromXmlDocument -XmlDocument $ownerDocument -SourceLabel "package item '$($Node.Attributes['name'].Value)'"
}

function Get-LastUpdateInfoFromFile {
    param([string]$FilePath)

    [xml]$xmlDocument = Get-Content -LiteralPath $FilePath -Raw
    return Get-LastUpdateInfoFromXmlDocument -XmlDocument $xmlDocument -SourceLabel $FilePath
}

function Resolve-ItemDestinationPath {
    # ONLY builds the item's destination path (FolderType/NormalizedName.xml); does NOT create a
    # directory or do I/O. Single source reused by Write-ItemToDestination and
    # Get-GeneXusCrossFlowDataSourceCollisions (avoids drift in the path rule).
    param(
        [string]$Root,
        [string]$FolderType,
        [string]$NormalizedName
    )
    return Join-Path (Join-Path $Root $FolderType) ($NormalizedName + ".xml")
}

function Write-ItemToDestination {
    param(
        [object]$Item,
        [string]$Root,
        [bool]$CrossFlowCollision = $false
    )

    $folderPath = Join-Path $Root $Item.FolderType
    if (-not (Test-Path -LiteralPath $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath | Out-Null
    }

    $filePath = Resolve-ItemDestinationPath -Root $Root -FolderType $Item.FolderType -NormalizedName $Item.NormalizedName
    $xmlText = Convert-NodeToXmlString -Node $Item.Node
    $incomingLastUpdate = Get-LastUpdateInfoFromNode -Node $Item.Node
    $status = "created"
    $existingLastUpdate = $null

    if (Test-Path -LiteralPath $filePath) {
        $existing = Get-Content -LiteralPath $filePath -Raw
        if ($existing -eq $xmlText) {
            $status = "unchanged"
        } else {
            $existingLastUpdate = Get-LastUpdateInfoFromFile -FilePath $filePath
            if ($incomingLastUpdate.ParsedValue -lt $existingLastUpdate.ParsedValue) {
                $status = "skipped-older-lastUpdate"
            } else {
                $status = "updated"
            }
        }
    }

    if ($status -eq "created" -or $status -eq "updated") {
        [System.IO.File]::WriteAllText($filePath, $xmlText, (Get-Utf8NoBomEncoding))
    }

    return [pscustomobject]@{
        FolderType = $Item.FolderType
        LogicalName = $Item.LogicalName
        FilePath = $filePath
        Status = $status
        WasNormalized = ($Item.LogicalName -ne $Item.NormalizedName)
        IncomingLastUpdate = $incomingLastUpdate.RawValue
        ExistingLastUpdate = if ($null -ne $existingLastUpdate) { $existingLastUpdate.RawValue } else { $null }
        CrossFlowCollision = [bool]$CrossFlowCollision
    }
}

function Get-GeneXusCrossFlowDataSourceCollisions {
    <#
        Detects a cross-flow SOURCE DIVERGENCE (dataSource) in the XML corpus (central
        modern<->legacy GeneXus 9 case). Compares the incoming node's dataSource against the one
        of the file ALREADY materialized at the destination. This FUNCTION NEVER throws; it returns
        { Collisions, Warnings } and the caller decides whether to block (Decision K) or continue
        (fail-soft). Runs pre-rename, before metadata. See doc owner 01k and skills/mimir-lite/workflows/sync.md.
    #>
    param(
        [object[]]$Items,
        [string]$Root
    )

    $collisions = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]

    foreach ($item in $Items) {
        $filePath = Resolve-ItemDestinationPath -Root $Root -FolderType $item.FolderType -NormalizedName $item.NormalizedName
        if (-not (Test-Path -LiteralPath $filePath)) { continue }  # nonexistent => no collision (no parse)

        # Incoming: the node is already in $item.Node (XmlElement on both branches); absence => "".
        $incomingDataSource = [string]$item.Node.GetAttribute('dataSource')

        # Existing: encoding-aware parse (XmlDocument.Load, like the package's pre-read), NOT the
        # [xml]Get-Content -Raw used by Get-LogicalNameFromExtractedFile. Parse failure => fail-safe warning.
        $existingDataSource = $null
        try {
            $existingDoc = New-Object System.Xml.XmlDocument
            $existingDoc.PreserveWhitespace = $true
            $existingDoc.Load($filePath)
            $existingRoot = $existingDoc.DocumentElement
            if ($null -eq $existingRoot) { throw "no root node" }
            $existingDataSource = [string]$existingRoot.GetAttribute('dataSource')
            # Decision E.2: a present attribute wins; only on ABSENCE does it consult the secondary
            # <GxLegacyPayload> signal (direct child, exclusive to legacy; LocalName namespace-tolerant).
            if ([string]::IsNullOrEmpty($existingDataSource)) {
                foreach ($child in $existingRoot.ChildNodes) {
                    if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element -and $child.LocalName -eq 'GxLegacyPayload') {
                        $existingDataSource = 'gx-legacy-export'
                        break
                    }
                }
            }
        } catch {
            # parse failure: does not produce a reliable ExistingDataSource => no collision, no block.
            $w = (@{ FilePath = $filePath; ExceptionType = $_.Exception.GetType().Name } | ConvertTo-Json -Compress)
            [Console]::Error.WriteLine("CROSSFLOW_WARNING: $w")
            $warnings.Add("undeterminable dataSource on '$filePath' (parse failed: $($_.Exception.GetType().Name)); item treated with no cross-flow collision.") | Out-Null
            continue
        }

        # COLLISION when the dataSource values DIVERGE (Decision E: ordinal comparison, no normalization).
        if (-not [string]::Equals($incomingDataSource, $existingDataSource, [System.StringComparison]::Ordinal)) {
            $collision = [pscustomobject]@{
                FolderType = $item.FolderType
                NormalizedName = $item.NormalizedName
                LogicalName = $item.LogicalName
                ExistingDataSource = $existingDataSource
                IncomingDataSource = $incomingDataSource
                FilePath = $filePath
            }
            $collisions.Add($collision) | Out-Null
            # UNIVERSAL stderr mitigation (JSONL): always emitted at the point of detection, so the
            # collision is never lost even on paths that abort before stdout's Summary.
            $line = ($collision | ConvertTo-Json -Compress)
            [Console]::Error.WriteLine("CROSSFLOW_COLLISION: $line")
        }
    }

    return [pscustomobject]@{
        Collisions = $collisions.ToArray()
        Warnings = $warnings.ToArray()
    }
}

function Invoke-GeneXusCrossFlowDetection {
    # Orchestrates detection in the sync flow: runs Get-GeneXusCrossFlowDataSourceCollisions, aggregates
    # the warnings into $Warnings, and, under -Block + a collision, EMITS the terminating error (Decision K) after
    # signaling the ErrorId over stderr (so the self-test's child process can confirm it without dot-sourcing).
    # Returns the array of collisions (empty when there are none) for Summary/Writes[]. Pre-metadata.
    param(
        [object[]]$Items,
        [string]$Root,
        [object]$Warnings,
        [switch]$Block
    )
    $result = Get-GeneXusCrossFlowDataSourceCollisions -Items $Items -Root $Root
    foreach ($w in $result.Warnings) {
        if (-not [string]::IsNullOrWhiteSpace($w)) { $Warnings.Add($w) | Out-Null }
    }
    $collisions = @($result.Collisions)
    if ($Block -and $collisions.Count -gt 0) {
        [Console]::Error.WriteLine("CROSSFLOW_BLOCKED_ERRORID: CrossFlowDataSourceCollisionBlocked")
        Write-Error -Message ("BLOCK: cross-flow dataSource collision detected ({0} item(s)); -BlockCrossFlowDataSource is active. No metadata or XML was written." -f $collisions.Count) -ErrorId 'CrossFlowDataSourceCollisionBlocked' -Category InvalidOperation -ErrorAction Stop
    }
    return ,$collisions
}

function Get-LogicalNameFromExtractedFile {
    param([string]$FilePath)

    [xml]$xmlDoc = Get-Content -LiteralPath $FilePath -Raw
    $rootNode = $xmlDoc.DocumentElement
    return [pscustomobject]@{
        RootTag = $rootNode.LocalName
        LogicalName = $rootNode.GetAttribute("name")
        Guid = $rootNode.GetAttribute("guid")
    }
}

function Test-PackageMaterialization {
    param(
        [object[]]$Items,
        [string]$Root
    )

    $missing = New-Object System.Collections.Generic.List[object]
    $mismatch = New-Object System.Collections.Generic.List[object]

    foreach ($item in $Items) {
        $filePath = Join-Path (Join-Path $Root $item.FolderType) ($item.NormalizedName + ".xml")
        if (-not (Test-Path -LiteralPath $filePath)) {
            $missing.Add([pscustomobject]@{
                FolderType = $item.FolderType
                LogicalName = $item.LogicalName
                ExpectedPath = $filePath
            }) | Out-Null
            continue
        }

        $details = Get-LogicalNameFromExtractedFile -FilePath $filePath
        if ($details.RootTag -ne $item.RootTag -or $details.LogicalName -ne $item.LogicalName) {
            $mismatch.Add([pscustomobject]@{
                FolderType = $item.FolderType
                ExpectedName = $item.LogicalName
                ActualName = $details.LogicalName
                ExpectedRootTag = $item.RootTag
                ActualRootTag = $details.RootTag
                FilePath = $filePath
            }) | Out-Null
        }
    }

    return [pscustomobject]@{
        Missing = $missing
        Mismatch = $mismatch
    }
}

function Get-OfficialXmlCount {
    param(
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return 0
    }

    return @(Get-ChildItem -Path $Root -Recurse -File -Filter *.xml).Count
}

function Get-FullSnapshotComparison {
    param(
        [object[]]$Items,
        [string]$Root
    )

    $packageKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Items) {
        [void]$packageKeys.Add("$($item.FolderType)|$($item.LogicalName)")
    }

    $localKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $xmlFiles = Get-ChildItem -LiteralPath $Root -Recurse -Filter *.xml -File
    foreach ($file in $xmlFiles) {
        $folderType = $file.Directory.Name
        $details = Get-LogicalNameFromExtractedFile -FilePath $file.FullName
        [void]$localKeys.Add("$folderType|$($details.LogicalName)")
    }

    $missing = foreach ($key in $packageKeys) {
        if (-not $localKeys.Contains($key)) { $key }
    }

    $extra = foreach ($key in $localKeys) {
        if (-not $packageKeys.Contains($key)) { $key }
    }

    return [pscustomobject]@{
        MissingKeys = @($missing | Sort-Object)
        ExtraKeys = @($extra | Sort-Object)
    }
}

function Test-IsMeaningfulGuid {
    param([string]$Guid)

    if ([string]::IsNullOrWhiteSpace($Guid)) { return $false }
    if ($Guid.Trim().ToLowerInvariant() -eq "00000000-0000-0000-0000-000000000000") { return $false }
    return $true
}

function Resolve-GuidAwareRenames {
    <#
        Reconciles the XML corpus with the package by stable identity (root node GUID),
        not by logical name. When the same GUID appears in the corpus under a file
        name different from the package's target, treats it as a rename: renames the
        existing file on disk (Move-Item old -> new) instead of create-new +
        abandon-old. That way the result is a single file and git detects the rename.

        -Apply $true  : performs the rename/cleanup on disk (materialization mode).
        -Apply $false : only detects and classifies (-VerifyOnly mode), without touching disk.

        Scope: matches GUID within the SAME FolderType. A GUID that matches under a
        different FolderType (type change) is out of scope and follows the current path.

        -FolderTypes: when given, only those corpus folders are scanned (a delta passes the
        folders of its rename candidates, so a delta does not parse the whole corpus).

        -FailSoft $true (a delta): a condition that fails closed otherwise (an unreadable XML
        in a scanned folder, a name collision, a failed move) never throws: the rename of the
        affected item is skipped with a warning naming the GUID and the files, and the write
        loop creates the item under its new name (the behavior before delta renames).
        kb-source-metadata.md is already written at this point, so a delta must not abort here.
    #>
    param(
        [object[]]$Items,
        [string]$Root,
        [System.Collections.Generic.List[string]]$Warnings,
        [bool]$Apply,
        [string[]]$FolderTypes,
        [bool]$FailSoft = $false
    )

    $renames = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return ,($renames.ToArray())
    }

    $corpusByGuid = @{}
    if ($PSBoundParameters.ContainsKey('FolderTypes')) {
        $xmlFiles = @(foreach ($folderType in @($FolderTypes | Sort-Object -Unique)) {
            $folderPath = Join-Path $Root $folderType
            if (Test-Path -LiteralPath $folderPath -PathType Container) {
                Get-ChildItem -LiteralPath $folderPath -Recurse -Filter *.xml -File
            }
        })
    } else {
        $xmlFiles = Get-ChildItem -LiteralPath $Root -Recurse -Filter *.xml -File
    }
    # FolderType -> file names that could not be read (fail-soft only): the GUID of such a file
    # is unknown, so no rename is attempted in that folder.
    $unreadableByFolder = @{}
    foreach ($file in $xmlFiles) {
        try {
            $details = Get-LogicalNameFromExtractedFile -FilePath $file.FullName
        } catch {
            if (-not $FailSoft) { throw }
            $unreadableFolder = $file.Directory.Name
            if (-not $unreadableByFolder.ContainsKey($unreadableFolder)) {
                $unreadableByFolder[$unreadableFolder] = New-Object System.Collections.Generic.List[string]
            }
            $unreadableByFolder[$unreadableFolder].Add("$unreadableFolder/$($file.Name)")
            continue
        }
        if (-not (Test-IsMeaningfulGuid -Guid $details.Guid)) { continue }
        $guidKey = $details.Guid.Trim().ToLowerInvariant()
        $info = [pscustomobject]@{
            FilePath = $file.FullName
            FolderType = $file.Directory.Name
            LogicalName = $details.LogicalName
            FileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        }
        if (-not $corpusByGuid.ContainsKey($guidKey)) {
            $corpusByGuid[$guidKey] = New-Object System.Collections.Generic.List[object]
        }
        $corpusByGuid[$guidKey].Add($info)
    }

    foreach ($item in $Items) {
        if (-not (Test-IsMeaningfulGuid -Guid $item.Guid)) { continue }
        $guidKey = $item.Guid.Trim().ToLowerInvariant()
        $fallbackNote = if ($FailSoft) { " The item is created under its new name and the existing files are kept." } else { "" }
        if ($FailSoft -and $unreadableByFolder.ContainsKey($item.FolderType)) {
            $Warnings.Add("GUID-based rename skipped for '$($item.LogicalName)' (GUID $guidKey) in $($item.FolderType): the corpus file(s) $(($unreadableByFolder[$item.FolderType] | ForEach-Object { "'$_'" }) -join ', ') could not be read as XML, so a same-GUID file cannot be ruled out.$fallbackNote") | Out-Null
            continue
        }
        if (-not $corpusByGuid.ContainsKey($guidKey)) { continue }

        $sameFolderMatches = @($corpusByGuid[$guidKey] | Where-Object { $_.FolderType -eq $item.FolderType })
        if ($sameFolderMatches.Count -eq 0) { continue }
        $folderPath = Join-Path $Root $item.FolderType
        $newPath = Join-Path $folderPath ($item.NormalizedName + ".xml")
        if ($sameFolderMatches.Count -gt 1) {
            $targetMatches = @($sameFolderMatches | Where-Object { $_.FileBaseName -ceq $item.NormalizedName })
            $oldMatches = @($sameFolderMatches | Where-Object { $_.FileBaseName -cne $item.NormalizedName })
            if ($targetMatches.Count -eq 1 -and $oldMatches.Count -eq 1) {
                $existing = $oldMatches[0]
            } else {
                $duplicateFiles = ($sameFolderMatches | ForEach-Object { "'$($item.FolderType)/$($_.FileBaseName).xml'" } | Sort-Object) -join ', '
                $Warnings.Add("Duplicate GUID in the XML corpus ($guidKey) in $($item.FolderType): $duplicateFiles; GUID-based rename skipped for '$($item.LogicalName)'.$fallbackNote") | Out-Null
                continue
            }
        } else {
            $existing = $sameFolderMatches[0]
        }

        if ($existing.FileBaseName -ceq $item.NormalizedName) { continue }

        $oldPath = $existing.FilePath
        $isCaseOnlyRename = ($existing.FileBaseName -ieq $item.NormalizedName)
        $action = "detected"

        if ($Apply) {
            $tempPath = $null
            try {
                if ($isCaseOnlyRename) {
                    # On NTFS, names that differ only in case point to the same
                    # file; renaming via an intermediate step effects the case change.
                    $tempPath = Join-Path $folderPath ($item.NormalizedName + ".gxcasetmp")
                    Move-Item -LiteralPath $oldPath -Destination $tempPath
                    Move-Item -LiteralPath $tempPath -Destination $newPath
                    $action = "renamed"
                } elseif (Test-Path -LiteralPath $newPath) {
                    $newPathGuidRaw = (Get-LogicalNameFromExtractedFile -FilePath $newPath).Guid
                    if (Test-IsMeaningfulGuid -Guid $newPathGuidRaw) {
                        $newPathGuid = $newPathGuidRaw.Trim().ToLowerInvariant()
                    } else {
                        $newPathGuid = ""
                    }
                    if ($newPathGuid -eq $guidKey) {
                        # True orphan: the target is already the SAME object (same GUID), a leftover
                        # from a previous materialization; remove the old-named file.
                        Remove-Item -LiteralPath $oldPath -Force
                        $action = "orphan-removed"
                    } else {
                        # Collision: the target belongs to a different object (different GUID).
                        # Fail-closed before the write loop overwrites the existing file.
                        throw "Name collision in the corpus: '$($item.NormalizedName).xml' in '$($item.FolderType)' already exists with a different GUID ('$newPathGuid') than the renamed item (GUID '$guidKey', '$($existing.FileBaseName)' -> '$($item.NormalizedName)'). GUID rename aborted to preserve the existing file."
                    }
                } else {
                    Move-Item -LiteralPath $oldPath -Destination $newPath
                    $action = "renamed"
                }
            } catch {
                if (-not $FailSoft) { throw }
                # Delta: never abort here. Put a case-only rename's intermediate file back under
                # the old name, then let the write loop create the item under its new name.
                $failure = $_.Exception.Message
                if ($null -ne $tempPath -and (Test-Path -LiteralPath $tempPath) -and -not (Test-Path -LiteralPath $oldPath)) {
                    try {
                        Move-Item -LiteralPath $tempPath -Destination $oldPath
                    } catch {
                        $failure += " The intermediate file '$tempPath' could not be moved back: $($_.Exception.Message)"
                    }
                }
                $Warnings.Add("GUID-based rename skipped for '$($item.LogicalName)' (GUID $guidKey) in $($item.FolderType): '$($item.FolderType)/$($existing.FileBaseName).xml' -> '$($item.FolderType)/$($item.NormalizedName).xml' failed: $failure$fallbackNote") | Out-Null
                continue
            }
        }

        $renames.Add([pscustomobject]@{
            Guid = $guidKey
            FolderType = $item.FolderType
            OldName = $existing.LogicalName
            OldFileBaseName = $existing.FileBaseName
            NewName = $item.LogicalName
            NewFileBaseName = $item.NormalizedName
            Action = $action
        }) | Out-Null
    }

    return ,($renames.ToArray())
}

function Write-Report {
    param(
        [string]$Path,
        [object]$Payload
    )

    $json = $Payload | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Path, $json, (Get-Utf8NoBomEncoding))
}

$package = $null
$metadataResult = $null
$warnings = New-Object System.Collections.Generic.List[string]
try {
    $package = Resolve-PackageXmlPath -RawInputPath $InputPath
    # Encoding-aware read: XmlDocument.Load honors the prolog's encoding attribute. Legacy
    # GeneXus 9 export is iso-8859-1; Get-Content -Raw would assume UTF-8 and corrupt
    # Latin-1 accents. Applies equally to modern (UTF-8) and legacy (iso-8859-1).
    # A .xpw source (GeneXus 7.0 and earlier) arrives already translated (Latin-1 read by the
    # translator); it always takes the legacy branch below, even with no GXObject (an
    # attributes-only file), since the translation never produces modern elements.
    $isXpwSource = ($null -ne $package.XpwDocument)
    if ($isXpwSource) {
        $packageXml = $package.XpwDocument
    } else {
        $packageXml = New-Object System.Xml.XmlDocument
        $packageXml.PreserveWhitespace = $true
        $packageXml.Load($package.XmlPath)
    }

    if ($null -eq $packageXml.DocumentElement -or $packageXml.DocumentElement.LocalName -ne "ExportFile") {
        $foundRoot = if ($null -eq $packageXml.DocumentElement) { '<null>' } else { $packageXml.DocumentElement.LocalName }
        throw "Expected root element 'ExportFile', found '$foundRoot'."
    }

    # Profile classification BEFORE any metadata write. A MIXED package (legacy
    # <GXObject> elements and modern <Objects>/<Attributes> in the same ExportFile) is fail-closed
    # WITHOUT touching kb-source-metadata.md.
    $LegacyFormatDetected = $false
    $crossFlowCollisions = @()
    if (Test-GeneXusMixedExportFilePackage -XmlDocument $packageXml) {
        throw "BLOCK: MIXED export package (legacy <GXObject> and modern <Objects>/<Attributes> elements in the same ExportFile); out of scope for the legacy export engine. Export the formats separately. No metadata was written."
    }

    if ($isXpwSource -or (Test-GeneXusLegacyExportFilePackage -XmlDocument $packageXml)) {
        # ===== LEGACY BRANCH (GeneXus 9 export; GeneXus 7.0 and earlier .xpw, translated) =====
        # Order: resolve catalog -> build/validate items (fail-closed
        # for tag not in registry / >1 child element / collision HERE, before metadata) ->
        # metadata (-IsLegacyExport) -> shared materialization/rename/verification.
        $LegacyFormatDetected = $true
        $catalogResolution = Resolve-GeneXusObjectTypeCatalogPaths -BaseCatalogPath $CatalogPath -CatalogOverridePath $CatalogOverridePath -KbWorkspaceRoot $KbWorkspaceRoot
        $legacyRegistry = Get-GeneXusLegacyExportElementRegistry
        $legacySyncResult = Get-GeneXusLegacyExportFileSyncItems -XmlDocument $packageXml -MergedCatalog $catalogResolution.MergedCatalog -Registry $legacyRegistry
        $items = @($legacySyncResult.Items)

        # Cross-flow detection: post-$items, BEFORE metadata and rename (pre-rename snapshot).
        $crossFlowCollisions = Invoke-GeneXusCrossFlowDetection -Items $items -Root $DestinationRoot -Warnings $warnings -Block:$BlockCrossFlowDataSource

        if ($KbMetadataPath -and -not $VerifyOnly) {
            # METADATA WRITE (legacy): post-catalog/items. Mutually exclusive with the
            # modern branch's write below (after profile classification) — never both
            # in the same run, since the legacy/modern branches are disjoint by profile.
            $sourceExportFormat = if ($isXpwSource) { 'xpw' } else { 'xml' }
            $metadataResult = Update-MimirKbSourceMetadataFromSync -XmlDocument $packageXml -SourceXpzPath $InputPath -MetadataPath $KbMetadataPath -IsLegacyExport $true -SourceExportFormat $sourceExportFormat
            [Console]::Error.WriteLine("KbMetadataPath updated: $KbMetadataPath ($($metadataResult.WriteMode))")
            if ($metadataResult.Warnings.Count -gt 0) {
                [Console]::Error.WriteLine("WARNING: " + $metadataResult.Warnings[0])
            }
            foreach ($warning in $metadataResult.Warnings) {
                if (-not [string]::IsNullOrWhiteSpace($warning)) {
                    $warnings.Add($warning) | Out-Null
                }
            }
        }
    }
    else {
        # ===== MODERN BRANCH =====
        # Order: catalog -> unknown-throw -> Convert($items) -> cross-flow DETECTION -> metadata.
        # The unknown-type and intra-package-collision fail-closeds (Convert-PackageToItems)
        # fire BEFORE writing kb-source-metadata.md (see the sync workflow).
        # Update-MimirKbSourceMetadataFromSync does not receive $items, so building $items
        # before it is safe.
        $catalogResolution = Resolve-GeneXusObjectTypeCatalogPaths -BaseCatalogPath $CatalogPath -CatalogOverridePath $CatalogOverridePath -KbWorkspaceRoot $KbWorkspaceRoot
        $catalogGuidMap = Get-GeneXusCatalogGuidToFolderMap -MergedCatalog $catalogResolution.MergedCatalog
        $unknownTypes = @(Get-GeneXusUnknownObjectTypesFromExportFile -XmlDocument $packageXml -GuidToFolderMap $catalogGuidMap)
        if ($unknownTypes.Count -gt 0) {
            if ($DiscoveryReportPath) {
                Write-GeneXusUnknownTypeDiscoveryReport -Path $DiscoveryReportPath -UnknownTypes $unknownTypes -CatalogResolution $catalogResolution -InputPath $InputPath
            }
            $errorMessage = Format-GeneXusUnknownObjectTypesErrorMessage -UnknownTypes $unknownTypes -OverrideActive $catalogResolution.OverrideActive
            throw $errorMessage
        }

        $items = Convert-PackageToItems -XmlDocument $packageXml -CatalogGuidToFolderMap $catalogGuidMap

        # Cross-flow detection: post-$items, BEFORE metadata and rename (pre-rename snapshot).
        $crossFlowCollisions = Invoke-GeneXusCrossFlowDetection -Items $items -Root $DestinationRoot -Warnings $warnings -Block:$BlockCrossFlowDataSource

        if ($KbMetadataPath -and -not $VerifyOnly) {
            # METADATA WRITE (modern): post-catalog/unknown/Convert/detection.
            # Mutually exclusive with the legacy branch's write above.
            $metadataResult = Update-MimirKbSourceMetadataFromSync -XmlDocument $packageXml -SourceXpzPath $InputPath -MetadataPath $KbMetadataPath -SourceExportFormat 'xml'
            [Console]::Error.WriteLine("KbMetadataPath updated: $KbMetadataPath ($($metadataResult.WriteMode))")
            if ($metadataResult.Warnings.Count -gt 0) {
                # stderr (not Write-Warning): the warning stream also leaks into the stdout
                # captured from a child process, contaminating the JSON contract.
                [Console]::Error.WriteLine("WARNING: " + $metadataResult.Warnings[0])
            }
            foreach ($warning in $metadataResult.Warnings) {
                if (-not [string]::IsNullOrWhiteSpace($warning)) {
                    $warnings.Add($warning) | Out-Null
                }
            }
        }
    }

    $expectedComparison = Convert-ExpectedItemsToComparison -ExpectedItems $ExpectedItems -ActualItems $items

    $objectsBlockCount = @($items | Where-Object { $_.PackageSection -eq "Objects" }).Count
    $attributesBlockCount = @($items | Where-Object { $_.PackageSection -eq "Attributes" }).Count
    $preExistingOfficialXmlCount = Get-OfficialXmlCount -Root $DestinationRoot

    $renameResults = @()
    if ($FullSnapshot) {
        $renameResults = Resolve-GuidAwareRenames -Items $items -Root $DestinationRoot -Warnings $warnings -Apply (-not [bool]$VerifyOnly)
    } else {
        # Delta (incremental) package: an item whose target file does not exist yet may be a
        # same-GUID rename of a file already in the corpus. Reconcile only those candidates,
        # scanning only their folders, so the rename is reported in RenamedByGuid instead of
        # Created + an orphan old-name file. Files of objects the delta does not carry stay.
        # -FailSoft: kb-source-metadata.md is already written, so a rename that cannot be done
        # safely is skipped with a warning (the item is created under its new name) instead of
        # aborting the daily delta. -FullSnapshot keeps its fail-closed behavior.
        $renameCandidates = @($items | Where-Object {
            (Test-IsMeaningfulGuid -Guid $_.Guid) -and
            -not (Test-Path -LiteralPath (Resolve-ItemDestinationPath -Root $DestinationRoot -FolderType $_.FolderType -NormalizedName $_.NormalizedName))
        })
        if ($renameCandidates.Count -gt 0) {
            $renameResults = Resolve-GuidAwareRenames -Items $renameCandidates -Root $DestinationRoot -Warnings $warnings -Apply (-not [bool]$VerifyOnly) -FolderTypes @($renameCandidates | ForEach-Object { $_.FolderType }) -FailSoft $true
        }
    }

    # FolderType|NormalizedName keys of the cross-flow collisions (pre-rename); they match the
    # cross-flow pair's final destination (Decision I), so they index the per-item boolean in Writes[].
    $crossFlowKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($c in $crossFlowCollisions) {
        [void]$crossFlowKeys.Add("$($c.FolderType)|$($c.NormalizedName)")
    }

    $writeResults = @()
    if (-not $VerifyOnly) {
        foreach ($item in $items) {
            $itemCrossFlow = $crossFlowKeys.Contains("$($item.FolderType)|$($item.NormalizedName)")
            $writeResults += Write-ItemToDestination -Item $item -Root $DestinationRoot -CrossFlowCollision $itemCrossFlow
        }
    }

    $verification = Test-PackageMaterialization -Items $items -Root $DestinationRoot
    $fullSnapshotResult = $null
    if ($FullSnapshot) {
        $fullSnapshotResult = Get-FullSnapshotComparison -Items $items -Root $DestinationRoot
    }

    $createdCount = @($writeResults | Where-Object { $_.Status -eq "created" }).Count
    $updatedCount = @($writeResults | Where-Object { $_.Status -eq "updated" }).Count
    $unchangedCount = @($writeResults | Where-Object { $_.Status -eq "unchanged" }).Count
    $skippedOlderLastUpdateCount = @($writeResults | Where-Object { $_.Status -eq "skipped-older-lastUpdate" }).Count
    $normalizedFileNamesCount = @($writeResults | Where-Object { $_.WasNormalized }).Count

    # Nominal lists (machine data): "Type:Name" per status, sorted and stable.
    # Built as an array and exposed as a pscustomobject property: ConvertTo-Json
    # serializes an empty array as [] and a single-item array as ["x"] (never collapses to null).
    $createdNames = @($writeResults | Where-Object { $_.Status -eq "created" } | ForEach-Object { "$($_.FolderType):$($_.LogicalName)" } | Sort-Object)
    $updatedNames = @($writeResults | Where-Object { $_.Status -eq "updated" } | ForEach-Object { "$($_.FolderType):$($_.LogicalName)" } | Sort-Object)
    $unchangedNames = @($writeResults | Where-Object { $_.Status -eq "unchanged" } | ForEach-Object { "$($_.FolderType):$($_.LogicalName)" } | Sort-Object)
    $skippedOlderLastUpdateNames = @($writeResults | Where-Object { $_.Status -eq "skipped-older-lastUpdate" } | ForEach-Object { "$($_.FolderType):$($_.LogicalName)" } | Sort-Object)
    $renamedByGuidItems = @($renameResults |
        Where-Object { $_.Action -eq "renamed" -or $_.Action -eq "orphan-removed" } |
        Sort-Object FolderType, NewName |
        ForEach-Object { [pscustomobject]@{ Guid = $_.Guid; FolderType = $_.FolderType; OldName = $_.OldName; NewName = $_.NewName; Action = $_.Action } })

    # ExpectedComparison flattened into nominal lists (the source for the three parts of the
    # sync workflow's handoff). null when -ExpectedItems was not provided, to distinguish
    # "not requested" from "requested, but empty".
    if ($null -ne $expectedComparison) {
        $expectedReturnedNames = @($expectedComparison.ExpectedReturned | ForEach-Object { "$($_.FolderType):$($_.LogicalName)" } | Sort-Object)
        $expectedMissingNames = @($expectedComparison.ExpectedMissing | ForEach-Object { "$($_.FolderType):$($_.LogicalName)" } | Sort-Object)
        $additionalOfficialNames = @($expectedComparison.AdditionalOfficial | ForEach-Object { "$($_.FolderType):$($_.LogicalName)" } | Sort-Object)
    } else {
        $expectedReturnedNames = $null
        $expectedMissingNames = $null
        $additionalOfficialNames = $null
    }

    $materializationInterpretation = if ($LegacyFormatDetected) {
        "legacy-export-adapted"
    } elseif ($VerifyOnly) {
        "verify-only"
    } elseif ($items.Count -eq 0) {
        "no-exportable-items"
    } elseif ($preExistingOfficialXmlCount -eq 0 -and $createdCount -gt 0) {
        "first-materialization"
    } elseif ($preExistingOfficialXmlCount -gt 0 -and ($createdCount -gt 0 -or $updatedCount -gt 0)) {
        "existing-snapshot-updated"
    } elseif ($preExistingOfficialXmlCount -gt 0 -and $createdCount -eq 0 -and $updatedCount -eq 0 -and $unchangedCount -gt 0) {
        "existing-snapshot-confirmed-unchanged"
    } else {
        "materialization-result-requires-context"
    }

    $summary = [pscustomobject]@{
        SchemaVersion = 1
        Kind = "mimir-sync-result"
        InputPath = (Resolve-Path -LiteralPath $InputPath).Path
        PackageXmlPath = $package.XmlPath
        VerifyOnly = [bool]$VerifyOnly
        FullSnapshot = [bool]$FullSnapshot
        LegacyFormatDetected = [bool]$LegacyFormatDetected
        ObjectsBlockCount = $objectsBlockCount
        AttributesBlockCount = $attributesBlockCount
        TotalExportedItems = $items.Count
        PackageHasExportedItems = ($items.Count -gt 0)
        PackageInterpretation = if ($LegacyFormatDetected) { "legacy-export-adapted" } elseif ($items.Count -gt 0) { "exported-items-found" } else { "no-exportable-items" }
        PreExistingOfficialXmlCount = $preExistingOfficialXmlCount
        MaterializationInterpretation = $materializationInterpretation
        Created = $createdCount
        Updated = $updatedCount
        Unchanged = $unchangedCount
        SkippedOlderLastUpdate = $skippedOlderLastUpdateCount
        NormalizedFileNames = $normalizedFileNamesCount
        RenamedByGuid = @($renameResults | Where-Object { $_.Action -eq "renamed" -or $_.Action -eq "orphan-removed" }).Count
        RenameResidualsDetected = @($renameResults | Where-Object { $_.Action -eq "detected" }).Count
        MissingAfterVerification = $verification.Missing.Count
        MismatchesAfterVerification = $verification.Mismatch.Count
        FullSnapshotMissing = if ($null -ne $fullSnapshotResult) { $fullSnapshotResult.MissingKeys.Count } else { $null }
        FullSnapshotExtra = if ($null -ne $fullSnapshotResult) { $fullSnapshotResult.ExtraKeys.Count } else { $null }
        ExpectedItemsProvided = ($null -ne $expectedComparison)
        ExpectedItemsCount = if ($null -ne $expectedComparison) { $expectedComparison.ExpectedItems.Count } else { 0 }
        ExpectedReturnedCount = if ($null -ne $expectedComparison) { $expectedComparison.ExpectedReturned.Count } else { $null }
        ExpectedMissingCount = if ($null -ne $expectedComparison) { $expectedComparison.ExpectedMissing.Count } else { $null }
        AdditionalOfficialCount = if ($null -ne $expectedComparison) { $expectedComparison.AdditionalOfficial.Count } else { $null }
        CreatedNames = $createdNames
        UpdatedNames = $updatedNames
        UnchangedNames = $unchangedNames
        SkippedOlderLastUpdateNames = $skippedOlderLastUpdateNames
        RenamedByGuidItems = $renamedByGuidItems
        ExpectedReturnedNames = $expectedReturnedNames
        ExpectedMissingNames = $expectedMissingNames
        AdditionalOfficialNames = $additionalOfficialNames
        CrossFlowCollisions = @($crossFlowCollisions)
    }

    $overrideReminder = $null
    if (-not [string]::IsNullOrWhiteSpace($KbWorkspaceRoot)) {
        $overrideReminder = Get-GeneXusCatalogOverrideSessionReminder -KbWorkspaceRoot $KbWorkspaceRoot -CatalogOverridePath $CatalogOverridePath
        if ($overrideReminder.noticeRequired -and -not [string]::IsNullOrWhiteSpace($overrideReminder.message)) {
            $warnings.Add($overrideReminder.message) | Out-Null
        }
    }

    $report = [pscustomobject]@{
        Summary = $summary
        Missing = $verification.Missing
        Mismatch = $verification.Mismatch
        FullSnapshot = $fullSnapshotResult
        ExpectedComparison = $expectedComparison
        Renames = $renameResults
        Writes = $writeResults
        Warnings = @($warnings)
        KbMetadataStatus = if ($null -ne $metadataResult) { $metadataResult.MetadataStatus } else { "not-requested" }
        KbMetadataSourceComplete = if ($null -ne $metadataResult) { [bool]$metadataResult.SourceComplete } else { $null }
        CatalogOverrideActive = $catalogResolution.OverrideActive
        CatalogOverridePath = $catalogResolution.OverridePath
        CatalogUpstreamPending = $catalogResolution.UpstreamPending
        CatalogOverrideReminder = $overrideReminder
    }

    if ($ReportPath) {
        Write-Report -Path $ReportPath -Payload $report
    }

    # Warnings also on the stdout object (in addition to $report.Warnings), for the agent that
    # only reads stdout. Add-Member after the override-reminder block to capture all of them.
    $summary | Add-Member -NotePropertyName Warnings -NotePropertyValue @($warnings) -Force

    # STDOUT CONTRACT: exclusively the summary's machine JSON (-Compress = one line,
    # robust at the process boundary). All human text goes to STDERR, never to
    # stdout: Write-Host leaks into the stdout captured from a child process (pwsh -File),
    # contaminating the JSON. See skills/mimir-lite/workflows/sync.md (output contract).
    $summary | ConvertTo-Json -Depth 8 -Compress | Write-Output

    $humanSummary = $summary |
        Select-Object -Property * -ExcludeProperty CreatedNames, UpdatedNames, UnchangedNames, SkippedOlderLastUpdateNames, RenamedByGuidItems, ExpectedReturnedNames, ExpectedMissingNames, AdditionalOfficialNames, Warnings |
        Format-List | Out-String
    [Console]::Error.WriteLine($humanSummary)

    $expectedSummary = Format-ExpectedItemsSummary -ExpectedComparison $expectedComparison
    if (-not [string]::IsNullOrWhiteSpace($expectedSummary)) {
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine($expectedSummary)
    }

    if ($verification.Missing.Count -gt 0 -or $verification.Mismatch.Count -gt 0) {
        throw "Verification failed after materialization. Missing=$($verification.Missing.Count), Mismatch=$($verification.Mismatch.Count)."
    }

    if ($null -ne $fullSnapshotResult -and ($fullSnapshotResult.MissingKeys.Count -gt 0 -or $fullSnapshotResult.ExtraKeys.Count -gt 0)) {
        throw "Full snapshot verification failed. Missing=$($fullSnapshotResult.MissingKeys.Count), Extra=$($fullSnapshotResult.ExtraKeys.Count)."
    }

    if ($ReportPath -and -not $KeepReport -and (Test-Path -LiteralPath $ReportPath)) {
        Remove-Item -LiteralPath $ReportPath -Force
    }
} finally {
    if ($null -ne $package -and $null -ne $package.TempPath -and (Test-Path -LiteralPath $package.TempPath)) {
        Remove-Item -LiteralPath $package.TempPath -Recurse -Force
    }
}
