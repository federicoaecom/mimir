#requires -Version 7.4

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$utf8NoBomEncodingSupportPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

function Format-MdCell {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return "" }

    $text = [string]$Value
    $text = $text -replace '\r?\n', '<br/>'
    $text = $text -replace '\|', '\|'
    $text = $text -replace '\t', ' '
    return $text.Trim()
}

function Add-MarkdownTable {
    param(
        [System.Text.StringBuilder]$Builder,
        [string[]]$Headers,
        [object[]]$Rows
    )

    [void]$Builder.AppendLine(('| ' + (($Headers | ForEach-Object { Format-MdCell $_ }) -join ' | ') + ' |'))
    [void]$Builder.AppendLine(('| ' + (($Headers | ForEach-Object { '---' }) -join ' | ') + ' |'))

    foreach ($row in $Rows) {
        $cells = foreach ($header in $Headers) {
            if ($row -is [System.Collections.IDictionary]) {
                Format-MdCell $row[$header]
            } else {
                Format-MdCell $row.$header
            }
        }
        [void]$Builder.AppendLine(('| ' + ($cells -join ' | ') + ' |'))
    }

    [void]$Builder.AppendLine()
}

function Get-ObjectPropertyValue {
    param(
        [System.Xml.XmlElement]$ObjectNode,
        [string]$PropertyName
    )

    $property = $ObjectNode.SelectSingleNode("./Properties/Property[Name='$PropertyName']/Value")
    if ($null -ne $property) {
        return $property.InnerText
    }
    return $null
}

function Get-StructuredReferences {
    param(
        [xml]$XmlDocument,
        [System.Xml.XmlElement]$ObjectNode
    )

    $refs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $parent = $ObjectNode.GetAttribute("parent")
    if ($parent) { [void]$refs.Add("parent:$parent") }

    $parentGuid = $ObjectNode.GetAttribute("parentGuid")
    if ($parentGuid) { [void]$refs.Add("parentGuid:$parentGuid") }

    $moduleGuid = $ObjectNode.GetAttribute("moduleGuid")
    if ($moduleGuid) { [void]$refs.Add("moduleGuid:$moduleGuid") }

    $propNodes = $XmlDocument.SelectNodes("//Property[Name='idBasedOn' or Name='BasedOn' or Name='DataSelector' or Name='MasterPage']/Value")
    foreach ($prop in $propNodes) {
        if ($prop.InnerText) {
            [void]$refs.Add("property:$($prop.InnerText.Trim())")
        }
    }

    $attrSelectors = @(
        "//transaction/@transaction",
        "//link/@webpanel",
        "//attribute/@attribute",
        "//descriptionAttribute/@attribute",
        "//variable/@domain",
        "//level/@name",
        "//item/@name"
    )

    foreach ($selector in $attrSelectors) {
        $nodes = $XmlDocument.SelectNodes($selector)
        foreach ($node in $nodes) {
            if ($node.Value) {
                [void]$refs.Add("$($node.Name):$($node.Value.Trim())")
            }
        }
    }

    return ($refs | Sort-Object) -join "; "
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "SourceRoot not found: $SourceRoot"
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).ProviderPath
$allFiles = Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File | Sort-Object FullName
$moduleFolderName = "Module"
$moduleTypeGuid = "00000000-0000-0000-0000-000000000008"

$records = New-Object System.Collections.Generic.List[object]
$problemFiles = New-Object System.Collections.Generic.List[object]
$moduleDefinitions = @{}

foreach ($file in $allFiles) {
    # Relative to the resolved root (SourceRoot may be relative); the type folder is the
    # first segment, whichever separator the platform uses.
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $file.FullName)
    $folderType = ($relativePath -split '[\\/]')[0]

    try {
        [xml]$xmlDoc = Get-Content -LiteralPath $file.FullName -Raw
        # Objects use an <Object> root; top-level attributes use an <Attribute> root (no type GUID).
        $objectNode = $xmlDoc.SelectSingleNode("/Object | /Attribute")

        if ($null -eq $objectNode) {
            $problemFiles.Add([pscustomobject]@{
                RelativePath = $relativePath
                Issue = "No /Object or /Attribute root node"
                Detail = ""
            }) | Out-Null
            continue
        }

        $objectName = $objectNode.GetAttribute("name")
        $objectGuid = $objectNode.GetAttribute("guid")
        $objectTypeGuid = $objectNode.GetAttribute("type")
        $moduleGuid = $objectNode.GetAttribute("moduleGuid")
        $parent = $objectNode.GetAttribute("parent")
        $parentGuid = $objectNode.GetAttribute("parentGuid")
        $parentTypeGuid = $objectNode.GetAttribute("parentType")
        $fullName = $objectNode.GetAttribute("fullyQualifiedName")
        $description = $objectNode.GetAttribute("description")

        if (-not $objectName) {
            $fallbackName = Get-ObjectPropertyValue -ObjectNode $objectNode -PropertyName "Name"
            if ($fallbackName) { $objectName = $fallbackName }
        }

        $partTypeList = @(
            $objectNode.SelectNodes("./Part") |
            ForEach-Object { $_.GetAttribute("type") } |
            Where-Object { $_ }
        )

        $record = [pscustomobject]@{
            RelativePath = $relativePath
            FileName = $file.Name
            FolderType = $folderType
            ObjectName = $objectName
            FullyQualifiedName = $fullName
            Description = $description
            ObjectGuid = $objectGuid
            ObjectTypeGuid = $objectTypeGuid
            ModuleGuid = $moduleGuid
            Parent = $parent
            ParentGuid = $parentGuid
            ParentTypeGuid = $parentTypeGuid
            PartTypes = ($partTypeList | Sort-Object -Unique) -join "; "
            PartTypeCount = ($partTypeList | Measure-Object).Count
            ApparentRelations = Get-StructuredReferences -XmlDocument $xmlDoc -ObjectNode $objectNode
            FileSize = $file.Length
            LastWriteTime = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }

        $records.Add($record) | Out-Null

        if ($folderType -eq $moduleFolderName -and $objectGuid -and $objectName) {
            $moduleDefinitions[$objectGuid] = $objectName
        }

        $isAttributeRoot = ($objectNode.LocalName -eq "Attribute")
        if (-not $objectName -or (-not $objectTypeGuid -and -not $isAttributeRoot)) {
            $problemFiles.Add([pscustomobject]@{
                RelativePath = $relativePath
                Issue = "Missing metadata"
                Detail = "Name='$objectName' Type='$objectTypeGuid'"
            }) | Out-Null
        }
    } catch {
        $problemFiles.Add([pscustomobject]@{
            RelativePath = $relativePath
            Issue = "Failed to read XML"
            Detail = $_.Exception.Message
        }) | Out-Null
    }
}

$recordsWithModule = foreach ($record in $records) {
    $moduleName = ""

    if ($record.FolderType -eq $moduleFolderName) {
        $moduleName = $record.ObjectName
    } elseif ($record.ParentTypeGuid -eq $moduleTypeGuid -and $record.Parent) {
        $moduleName = $record.Parent
    } elseif ($record.ModuleGuid -and $moduleDefinitions.ContainsKey($record.ModuleGuid)) {
        $moduleName = $moduleDefinitions[$record.ModuleGuid]
    }

    [pscustomobject]@{
        RelativePath = $record.RelativePath
        FileName = $record.FileName
        FolderType = $record.FolderType
        ObjectName = $record.ObjectName
        FullyQualifiedName = $record.FullyQualifiedName
        Description = $record.Description
        ObjectGuid = $record.ObjectGuid
        ObjectTypeGuid = $record.ObjectTypeGuid
        Module = $moduleName
        ModuleGuid = $record.ModuleGuid
        Parent = $record.Parent
        ParentGuid = $record.ParentGuid
        ParentTypeGuid = $record.ParentTypeGuid
        PartTypes = $record.PartTypes
        PartTypeCount = $record.PartTypeCount
        ApparentRelations = $record.ApparentRelations
        FileSize = $record.FileSize
        LastWriteTime = $record.LastWriteTime
    }
}

$fileCountsByFolder = $allFiles |
    Group-Object { $_.Directory.Name } |
    Sort-Object Name |
    ForEach-Object {
        [pscustomobject]@{
            FolderType = $_.Name
            FileCount = $_.Count
        }
    }

$objectNamesTable = $recordsWithModule |
    Sort-Object ObjectName, FolderType, RelativePath |
    ForEach-Object {
        [pscustomobject]@{
            ObjectName = $_.ObjectName
            FolderType = $_.FolderType
            Module = $_.Module
            RelativePath = $_.RelativePath
        }
    }

$objectTypesTable = $recordsWithModule |
    Group-Object FolderType, ObjectTypeGuid |
    Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false } |
    ForEach-Object {
        $sample = $_.Group | Select-Object -First 5 -ExpandProperty ObjectName
        [pscustomobject]@{
            FolderType = $_.Group[0].FolderType
            ObjectTypeGuid = $_.Group[0].ObjectTypeGuid
            ObjectCount = $_.Count
            SampleObjects = ($sample -join "; ")
        }
    }

$moduleUsageTable = $recordsWithModule |
    Group-Object Module, ModuleGuid |
    Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false } |
    ForEach-Object {
        [pscustomobject]@{
            Module = $_.Group[0].Module
            ModuleGuid = $_.Group[0].ModuleGuid
            ObjectCount = $_.Count
            SampleObjects = (($_.Group | Select-Object -First 5 -ExpandProperty ObjectName) -join "; ")
        }
    }

$partTypeTable = $recordsWithModule |
    Where-Object { $_.PartTypes } |
    ForEach-Object {
        $parts = $_.PartTypes -split '; '
        foreach ($part in $parts) {
            [pscustomobject]@{
                PartTypeGuid = $part
                ObjectName = $_.ObjectName
                FolderType = $_.FolderType
                RelativePath = $_.RelativePath
            }
        }
    } |
    Group-Object PartTypeGuid |
    Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false } |
    ForEach-Object {
        [pscustomobject]@{
            PartTypeGuid = $_.Name
            Occurrences = $_.Count
            SampleObjects = (($_.Group | Select-Object -First 5 -ExpandProperty ObjectName) -join "; ")
            SampleFiles = (($_.Group | Select-Object -First 3 -ExpandProperty RelativePath) -join "; ")
        }
    }

$guidCatalog = $recordsWithModule |
    Group-Object ObjectTypeGuid |
    Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Descending = $false } |
    ForEach-Object {
        [pscustomobject]@{
            GuidKind = "ObjectTypeGuid"
            GuidValue = $_.Name
            Occurrences = $_.Count
            FolderTypes = (($_.Group | Select-Object -ExpandProperty FolderType -Unique | Sort-Object) -join "; ")
        }
    }

$relationsTable = $recordsWithModule |
    Where-Object { $_.Parent -or $_.ApparentRelations } |
    Sort-Object ObjectName, RelativePath |
    ForEach-Object {
        [pscustomobject]@{
            ObjectName = $_.ObjectName
            FolderType = $_.FolderType
            Module = $_.Module
            Parent = $_.Parent
            ParentTypeGuid = $_.ParentTypeGuid
            ApparentRelations = $_.ApparentRelations
            RelativePath = $_.RelativePath
        }
    }

$allFilesTable = $recordsWithModule |
    Sort-Object RelativePath |
    ForEach-Object {
        [pscustomobject]@{
            RelativePath = $_.RelativePath
            FileName = $_.FileName
            FolderType = $_.FolderType
            ObjectName = $_.ObjectName
            ObjectTypeGuid = $_.ObjectTypeGuid
            Module = $_.Module
            FileSize = $_.FileSize
            LastWriteTime = $_.LastWriteTime
        }
    }

$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine("# Raw XML Corpus Inventory")
[void]$sb.AppendLine()
[void]$sb.AppendLine("- Source: XML corpus given to the script")
[void]$sb.AppendLine("- Generation date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("- Total files scanned: $($allFiles.Count)")
[void]$sb.AppendLine("- Total object records read: $($recordsWithModule.Count)")
[void]$sb.AppendLine("- Total problem files: $($problemFiles.Count)")
[void]$sb.AppendLine("- Note: descriptive, raw inventory; no strong conclusions at this stage.")
[void]$sb.AppendLine()

[void]$sb.AppendLine("## Files Found")
[void]$sb.AppendLine()
[void]$sb.AppendLine("### Count by folder")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("FolderType", "FileCount") -Rows $fileCountsByFolder

[void]$sb.AppendLine("### File list")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("RelativePath", "FileName", "FolderType", "ObjectName", "ObjectTypeGuid", "Module", "FileSize", "LastWriteTime") -Rows $allFilesTable

[void]$sb.AppendLine("## Object Names")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("ObjectName", "FolderType", "Module", "RelativePath") -Rows $objectNamesTable

[void]$sb.AppendLine("## Object Types")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("FolderType", "ObjectTypeGuid", "ObjectCount", "SampleObjects") -Rows $objectTypesTable

[void]$sb.AppendLine("## Modules")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("Module", "ModuleGuid", "ObjectCount", "SampleObjects") -Rows $moduleUsageTable

[void]$sb.AppendLine("## Part Types and GUIDs Detected")
[void]$sb.AppendLine()
[void]$sb.AppendLine("### ObjectType GUID Catalog")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("GuidKind", "GuidValue", "Occurrences", "FolderTypes") -Rows $guidCatalog

[void]$sb.AppendLine("### PartType GUID Catalog")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("PartTypeGuid", "Occurrences", "SampleObjects", "SampleFiles") -Rows $partTypeTable

[void]$sb.AppendLine("## Apparent Relations")
[void]$sb.AppendLine()
Add-MarkdownTable -Builder $sb -Headers @("ObjectName", "FolderType", "Module", "Parent", "ParentTypeGuid", "ApparentRelations", "RelativePath") -Rows $relationsTable

[void]$sb.AppendLine("## Problem Files")
[void]$sb.AppendLine()
if ($problemFiles.Count -gt 0) {
    Add-MarkdownTable -Builder $sb -Headers @("RelativePath", "Issue", "Detail") -Rows ($problemFiles | Sort-Object RelativePath)
} else {
    [void]$sb.AppendLine("No problem files detected while reading XML.")
    [void]$sb.AppendLine()
}

[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), (Get-Utf8NoBomEncoding))
Write-Output "Inventory generated at: $OutputPath"
