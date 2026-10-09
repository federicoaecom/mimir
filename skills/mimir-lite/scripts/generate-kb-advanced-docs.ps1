#requires -Version 7.4

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot
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
    return $text.Trim()
}

function Add-Table {
    param(
        [System.Text.StringBuilder]$Builder,
        [string[]]$Headers,
        [object[]]$Rows
    )

    [void]$Builder.AppendLine(('| ' + (($Headers | ForEach-Object { Format-MdCell $_ }) -join ' | ') + ' |'))
    [void]$Builder.AppendLine(('| ' + (($Headers | ForEach-Object { '---' }) -join ' | ') + ' |'))
    foreach ($row in $Rows) {
        $cells = foreach ($header in $Headers) { Format-MdCell $row.$header }
        [void]$Builder.AppendLine(('| ' + ($cells -join ' | ') + ' |'))
    }
    [void]$Builder.AppendLine()
}

function Get-ObjectNodePropertyValue {
    param(
        [System.Xml.XmlElement]$ObjectNode,
        [string]$PropertyName
    )
    $property = $ObjectNode.SelectSingleNode("./Properties/Property[Name='$PropertyName']/Value")
    if ($null -ne $property) { return $property.InnerText }
    return $null
}

function Get-PartTextLength {
    param([System.Xml.XmlElement]$PartNode)
    if ($null -eq $PartNode) { return 0 }
    return ($PartNode.InnerXml | Out-String).Trim().Length
}

function Test-PartApparentlyEmpty {
    param([System.Xml.XmlElement]$PartNode)

    if ($null -eq $PartNode) { return $true }

    $sourceNode = $PartNode.SelectSingleNode("./Source")
    $propertiesNode = $PartNode.SelectSingleNode("./Properties")
    $childElements = @($PartNode.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element })

    if ($childElements.Count -eq 0) { return $true }

    if ($childElements.Count -eq 1 -and $null -ne $sourceNode) {
        return [string]::IsNullOrWhiteSpace($sourceNode.InnerText)
    }

    if ($childElements.Count -eq 1 -and $null -ne $propertiesNode) {
        return ($propertiesNode.ChildNodes.Count -eq 0)
    }

    if ($childElements.Count -eq 2 -and $null -ne $sourceNode -and $null -ne $propertiesNode) {
        return [string]::IsNullOrWhiteSpace($sourceNode.InnerText) -and ($propertiesNode.ChildNodes.Count -eq 0)
    }

    return $false
}

function Get-ReferenceSummary {
    param(
        [xml]$XmlDocument,
        [System.Xml.XmlElement]$ObjectNode
    )

    $refs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($attr in @("parent", "parentGuid", "parentType", "moduleGuid")) {
        $value = $ObjectNode.GetAttribute($attr)
        if ($value) { [void]$refs.Add("${attr}:$value") }
    }

    $propValues = $XmlDocument.SelectNodes("//Property[Name='idBasedOn' or Name='BasedOn' or Name='DataSelector' or Name='MasterPage']/Value")
    foreach ($prop in $propValues) {
        if ($prop.InnerText) { [void]$refs.Add("property:$($prop.InnerText.Trim())") }
    }

    $attributeNodes = $XmlDocument.SelectNodes("//link/@webpanel | //attribute/@attribute | //descriptionAttribute/@attribute | //variable/@domain | //transaction/@transaction")
    foreach ($node in $attributeNodes) {
        if ($node.Value) { [void]$refs.Add("$($node.Name):$($node.Value.Trim())") }
    }

    return ($refs | Sort-Object) -join "; "
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "SourceRoot not found: $SourceRoot"
}

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot | Out-Null
}

$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).ProviderPath
$files = Get-ChildItem -LiteralPath $resolvedSourceRoot -Recurse -File -Filter *.xml | Sort-Object FullName
$records = New-Object System.Collections.Generic.List[object]
$problemFiles = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    # Relative to the resolved root (SourceRoot may be relative); the type folder is the
    # first segment, whichever separator the platform uses.
    $relativePath = [System.IO.Path]::GetRelativePath($resolvedSourceRoot, $file.FullName)
    $folderType = Split-Path -Path $relativePath -Parent
    if ($folderType -match '[\\/]') { $folderType = ($folderType -split '[\\/]')[0] }

    try {
        [xml]$xmlDoc = Get-Content -LiteralPath $file.FullName -Raw
        $objectNode = $xmlDoc.SelectSingleNode("/Object")
        if ($null -eq $objectNode) {
            $problemFiles.Add([pscustomobject]@{
                RelativePath = $relativePath
                Issue = "No /Object node"
            }) | Out-Null
            continue
        }

        $partNodes = @($objectNode.SelectNodes("./Part"))
        $partInfos = @(foreach ($part in $partNodes) {
            [pscustomobject]@{
                PartType = $part.GetAttribute("type")
                ApparentlyEmpty = Test-PartApparentlyEmpty -PartNode $part
                TextLength = Get-PartTextLength -PartNode $part
            }
        })

        $record = [pscustomobject]@{
            RelativePath = $relativePath
            FileName = $file.Name
            FolderType = $folderType
            ObjectName = $objectNode.GetAttribute("name")
            ObjectGuid = $objectNode.GetAttribute("guid")
            ObjectTypeGuid = $objectNode.GetAttribute("type")
            Parent = $objectNode.GetAttribute("parent")
            ParentGuid = $objectNode.GetAttribute("parentGuid")
            ParentType = $objectNode.GetAttribute("parentType")
            ModuleGuid = $objectNode.GetAttribute("moduleGuid")
            FullyQualifiedName = $objectNode.GetAttribute("fullyQualifiedName")
            Description = $objectNode.GetAttribute("description")
            AttrNames = @($objectNode.Attributes | ForEach-Object { $_.Name })
            PartInfos = $partInfos
            PartCount = $partInfos.Count
            NonEmptyPartCount = @($partInfos | Where-Object { -not $_.ApparentlyEmpty }).Count
            PartTypes = @($partInfos | ForEach-Object { $_.PartType } | Where-Object { $_ } | Sort-Object -Unique)
            ReferenceSummary = Get-ReferenceSummary -XmlDocument $xmlDoc -ObjectNode $objectNode
            HasParent = -not [string]::IsNullOrWhiteSpace($objectNode.GetAttribute("parent"))
            HasModuleGuid = -not [string]::IsNullOrWhiteSpace($objectNode.GetAttribute("moduleGuid"))
            HasPatternData = ($xmlDoc.SelectNodes("//Data[@Pattern]").Count -gt 0)
            HasSource = ($xmlDoc.SelectNodes("//Source").Count -gt 0)
            FileSize = $file.Length
        }

        $records.Add($record) | Out-Null
    } catch {
        $problemFiles.Add([pscustomobject]@{
            RelativePath = $relativePath
            Issue = $_.Exception.Message
        }) | Out-Null
    }
}

$groups = $records | Group-Object FolderType | Sort-Object Name
$priorityMax = @("Transaction", "Procedure", "WebPanel", "Panel", "WorkWithForWeb", "DataProvider", "SDT")
$priorityMed = @("Theme", "ThemeClass", "DesignSystem", "API", "Module", "PackagedModule")
$priorityTypes = $priorityMax + $priorityMed

$typeSummaries = foreach ($group in $groups) {
    $items = @($group.Group)
    $count = $items.Count
    $sampleTypeGuid = ($items | Select-Object -First 1).ObjectTypeGuid
    $avgParts = [math]::Round((($items | Measure-Object -Property PartCount -Average).Average), 2)
    $withParent = @($items | Where-Object { $_.HasParent }).Count
    $withPattern = @($items | Where-Object { $_.HasPatternData }).Count
    $withModule = @($items | Where-Object { $_.HasModuleGuid }).Count
    $partCatalog = foreach ($partGroup in ($items | ForEach-Object { $_.PartInfos } | Group-Object PartType | Sort-Object Name)) {
        $presentCount = @($items | Where-Object { $_.PartTypes -contains $partGroup.Name }).Count
        $partOccurrenceCount = @($partGroup.Group).Count
        $emptyCount = @($partGroup.Group | Where-Object { $_.ApparentlyEmpty }).Count
        $presencePct = if ($count -gt 0) { [math]::Round(($presentCount / $count) * 100, 1) } else { 0 }
        $emptyPct = if ($partOccurrenceCount -gt 0) { [math]::Round(($emptyCount / $partOccurrenceCount) * 100, 1) } else { 0 }
        $classification = if ($presencePct -ge 99) {
            "apparently mandatory"
        } elseif ($presencePct -lt 20) {
            "apparently rare"
        } elseif ($emptyPct -ge 80) {
            "apparently empty/structural"
        } else {
            "apparently optional"
        }
        if ($count -lt 3) {
            $classification = "$classification (sample too small)"
        }
        $examples = ($items | Where-Object { $_.PartTypes -contains $partGroup.Name } | Select-Object -First 3 | ForEach-Object { "$($_.ObjectName) [$($_.RelativePath)]" }) -join "; "
        [pscustomobject]@{
            FolderType = $group.Name
            ObjectTypeGuid = $sampleTypeGuid
            PartType = $partGroup.Name
            ObjectsWithPart = $presentCount
            PresencePct = $presencePct
            EmptyPct = $emptyPct
            PreliminaryClass = $classification
            Examples = $examples
        }
    }

    $attrCatalog = foreach ($attrGroup in ($items | ForEach-Object { $_.AttrNames } | Group-Object | Sort-Object Name)) {
        $attrCount = $attrGroup.Count
        $presencePct = if ($count -gt 0) { [math]::Round(($attrCount / $count) * 100, 1) } else { 0 }
        $bucket = if ($presencePct -ge 95) { "almost always" } elseif ($presencePct -ge 20) { "sometimes" } else { "rare" }
        $criticality = if ($attrGroup.Name -in @("guid", "name", "type")) {
            "strong indication of structural criticality"
        } elseif ($attrGroup.Name -in @("parent", "parentGuid", "parentType", "moduleGuid")) {
            "tied to parent/module"
        } else {
            "role not yet settled"
        }
        [pscustomobject]@{
            FolderType = $group.Name
            Attribute = $attrGroup.Name
            ObjectsWithAttribute = $attrCount
            PresencePct = $presencePct
            PresenceBucket = $bucket
            Reading = $criticality
        }
    }

    $simpleSample = $items | Sort-Object PartCount, FileSize | Select-Object -First 2
    $complexSample = $items | Sort-Object @{Expression="PartCount";Descending=$true}, @{Expression="FileSize";Descending=$true} | Select-Object -First 2

    [pscustomobject]@{
        FolderType = $group.Name
        ObjectTypeGuid = $sampleTypeGuid
        Count = $count
        AveragePartCount = $avgParts
        WithParent = $withParent
        WithPattern = $withPattern
        WithModuleGuid = $withModule
        PartCatalog = $partCatalog
        AttrCatalog = $attrCatalog
        SimpleSample = $simpleSample
        ComplexSample = $complexSample
    }
}

$prioritySummaries = $typeSummaries | Where-Object { $_.FolderType -in $priorityTypes }

$matrixBuilder = New-Object System.Text.StringBuilder
[void]$matrixBuilder.AppendLine("# 10 - Part Type Matrix by Type")
[void]$matrixBuilder.AppendLine()
[void]$matrixBuilder.AppendLine("- Direct evidence: frequencies calculated from the XML corpus given to the script.")
[void]$matrixBuilder.AppendLine("- Strong inference: classifications below describe recurrence in this extracted corpus only; they do not establish downstream import requirements.")
[void]$matrixBuilder.AppendLine()
foreach ($summary in $typeSummaries) {
    [void]$matrixBuilder.AppendLine("## $($summary.FolderType)")
    [void]$matrixBuilder.AppendLine()
    [void]$matrixBuilder.AppendLine("- Direct evidence: Object/@type = $($summary.ObjectTypeGuid) in $($summary.Count) objects.")
    [void]$matrixBuilder.AppendLine("- Direct evidence: average Part per object: $($summary.AveragePartCount).")
    [void]$matrixBuilder.AppendLine("- Strong inference: apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.")
    if ($summary.Count -lt 3) {
        [void]$matrixBuilder.AppendLine("- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.")
    }
    [void]$matrixBuilder.AppendLine()
    Add-Table -Builder $matrixBuilder -Headers @("PartType", "ObjectsWithPart", "PresencePct", "EmptyPct", "PreliminaryClass", "Examples") -Rows @($summary.PartCatalog)
}
[System.IO.File]::WriteAllText((Join-Path $OutputRoot "10-part-type-matrix-by-type.md"), $matrixBuilder.ToString(), (Get-Utf8NoBomEncoding))

$fieldsBuilder = New-Object System.Text.StringBuilder
[void]$fieldsBuilder.AppendLine("# 11 - Stable vs Variable Fields of the Object Node")
[void]$fieldsBuilder.AppendLine()
[void]$fieldsBuilder.AppendLine("- Direct evidence: presence per attribute calculated per extracted type.")
[void]$fieldsBuilder.AppendLine("- Strong inference: readings such as structural criticality remain corpus heuristics, not evidence about downstream behavior.")
[void]$fieldsBuilder.AppendLine()
foreach ($summary in $typeSummaries) {
    [void]$fieldsBuilder.AppendLine("## $($summary.FolderType)")
    [void]$fieldsBuilder.AppendLine()
    [void]$fieldsBuilder.AppendLine("- Direct evidence: $($summary.Count) objects analyzed.")
    [void]$fieldsBuilder.AppendLine("- Direct evidence: objects with parent: $($summary.WithParent); with moduleGuid: $($summary.WithModuleGuid).")
    [void]$fieldsBuilder.AppendLine("- Strong inference: attributes tied to parent/module are associated with structural context in the extracted XML; no behavior beyond this corpus is implied.")
    [void]$fieldsBuilder.AppendLine()
    Add-Table -Builder $fieldsBuilder -Headers @("Attribute", "ObjectsWithAttribute", "PresencePct", "PresenceBucket", "Reading") -Rows @($summary.AttrCatalog)
    $examples = @($summary.SimpleSample) + @($summary.ComplexSample) | Select-Object -Unique RelativePath,ObjectName
    foreach ($example in $examples) {
        [void]$fieldsBuilder.AppendLine("- Direct evidence: cited example: $($example.ObjectName) in $($example.RelativePath).")
    }
    [void]$fieldsBuilder.AppendLine()
}
[System.IO.File]::WriteAllText((Join-Path $OutputRoot "11-stable-vs-variable-fields.md"), $fieldsBuilder.ToString(), (Get-Utf8NoBomEncoding))

$diffBuilder = New-Object System.Text.StringBuilder
[void]$diffBuilder.AppendLine("# 12 - Structural Diffs by Type")
[void]$diffBuilder.AppendLine()
[void]$diffBuilder.AppendLine("- Direct evidence: simple/complex samples were chosen by the smallest/largest combination of PartCount and file size.")
[void]$diffBuilder.AppendLine("- Strong inference: simple and complex here mean structural complexity in the extracted XML, not guaranteed functional complexity.")
[void]$diffBuilder.AppendLine()
foreach ($summary in $prioritySummaries) {
    [void]$diffBuilder.AppendLine("## $($summary.FolderType)")
    [void]$diffBuilder.AppendLine()
    $simple = @($summary.SimpleSample)
    $complex = @($summary.ComplexSample)
    foreach ($item in $simple) {
        [void]$diffBuilder.AppendLine("- Direct evidence: simple sample: $($item.ObjectName) in $($item.RelativePath) with $($item.PartCount) Part and $($item.NonEmptyPartCount) non-empty Part.")
    }
    foreach ($item in $complex) {
        [void]$diffBuilder.AppendLine("- Direct evidence: complex sample: $($item.ObjectName) in $($item.RelativePath) with $($item.PartCount) Part and a size of $($item.FileSize) bytes.")
    }
    $simpleParts = @($simple | ForEach-Object { $_.PartTypes } | Sort-Object -Unique)
    $complexParts = @($complex | ForEach-Object { $_.PartTypes } | Sort-Object -Unique)
    $onlyComplex = @($complexParts | Where-Object { $_ -notin $simpleParts })
    $onlySimple = @($simpleParts | Where-Object { $_ -notin $complexParts })
    $onlyComplexText = if($onlyComplex.Count -gt 0){ [string]::Join('; ', $onlyComplex) } else { 'none' }
    $onlySimpleText = if($onlySimple.Count -gt 0){ [string]::Join('; ', $onlySimple) } else { 'none' }
    [void]$diffBuilder.AppendLine("- Direct evidence: Part type in the simple samples: $(($simpleParts -join '; ')).")
    [void]$diffBuilder.AppendLine("- Direct evidence: Part type in the complex samples: $(($complexParts -join '; ')).")
    [void]$diffBuilder.AppendLine("- Direct evidence: Part type only in the complex samples: $onlyComplexText.")
    [void]$diffBuilder.AppendLine("- Direct evidence: Part type only in the simple samples: $onlySimpleText.")
    [void]$diffBuilder.AppendLine("- Strong inference: blocks recurring across simple and complex samples form a more consistent XML-reading baseline than blocks exclusive to complex cases.")
    [void]$diffBuilder.AppendLine("- Hypothesis: recurring blocks may be easier to compare across sampled XML; rarity alone does not establish edit risk or downstream behavior.")
    [void]$diffBuilder.AppendLine()
}
[System.IO.File]::WriteAllText((Join-Path $OutputRoot "12-structural-diffs-by-type.md"), $diffBuilder.ToString(), (Get-Utf8NoBomEncoding))

$mandatoryBuilder = New-Object System.Text.StringBuilder
[void]$mandatoryBuilder.AppendLine("# 14 - Indications of Mandatoriness")
[void]$mandatoryBuilder.AppendLine()
[void]$mandatoryBuilder.AppendLine("- Direct evidence: the percentages below come from the frequency of Part type per extracted type.")
[void]$mandatoryBuilder.AppendLine("- Strong inference: apparently mandatory means presence in ~100% of this type's samples in this KB.")
[void]$mandatoryBuilder.AppendLine("- Hypothesis: corpus frequencies alone cannot establish what downstream processing requires.")
[void]$mandatoryBuilder.AppendLine()
foreach ($summary in $prioritySummaries) {
    $mandatory = @($summary.PartCatalog | Where-Object { $_.PresencePct -ge 99 })
    $optional = @($summary.PartCatalog | Where-Object { $_.PresencePct -ge 20 -and $_.PresencePct -lt 99 -and $_.EmptyPct -lt 80 })
    $structural = @($summary.PartCatalog | Where-Object { $_.EmptyPct -ge 80 })
    $mandatoryText = if($mandatory.Count -gt 0){ [string]::Join('; ', ($mandatory | ForEach-Object { $_.PartType })) } else { 'none' }
    $optionalText = if($optional.Count -gt 0){ [string]::Join('; ', ($optional | ForEach-Object { $_.PartType })) } else { 'none' }
    $structuralText = if($structural.Count -gt 0){ [string]::Join('; ', ($structural | ForEach-Object { $_.PartType })) } else { 'none' }
    [void]$mandatoryBuilder.AppendLine("## $($summary.FolderType)")
    [void]$mandatoryBuilder.AppendLine()
    [void]$mandatoryBuilder.AppendLine("- Direct evidence: total objects analyzed: $($summary.Count).")
    [void]$mandatoryBuilder.AppendLine("- Direct evidence: Part type with strong indication of mandatoriness: $mandatoryText.")
    [void]$mandatoryBuilder.AppendLine("- Direct evidence: Part type with indication of optionality: $optionalText.")
    [void]$mandatoryBuilder.AppendLine("- Direct evidence: Part type with indication of empty/structural: $structuralText.")
    [void]$mandatoryBuilder.AppendLine("- Strong inference: blocks present in every sampled object are consistent structural observations, but their operational significance is not established.")
    [void]$mandatoryBuilder.AppendLine("- Hypothesis: almost-always-empty blocks may still be structurally meaningful despite little visible content; sample frequency cannot establish downstream requirements.")
    [void]$mandatoryBuilder.AppendLine()
}
[System.IO.File]::WriteAllText((Join-Path $OutputRoot "14-mandatoriness-indications.md"), $mandatoryBuilder.ToString(), (Get-Utf8NoBomEncoding))

$riskBuilder = New-Object System.Text.StringBuilder
[void]$riskBuilder.AppendLine("# 16 - Risk Map by Type")
[void]$riskBuilder.AppendLine()
[void]$riskBuilder.AppendLine("- Strong inference: structural-risk labels summarize observed XML structure only; they are not operational readiness guidance.")
[void]$riskBuilder.AppendLine()
$riskRows = foreach ($summary in $prioritySummaries) {
    $risk = if ($summary.WithPattern -gt 0 -or $summary.AveragePartCount -ge 5) { "high" } elseif ($summary.AveragePartCount -ge 3) { "medium" } else { "low" }
    $parentDep = if ($summary.WithParent -gt 0) { "$($summary.WithParent)/$($summary.Count)" } else { "0/$($summary.Count)" }
    $patternDep = if ($summary.WithPattern -gt 0) { "$($summary.WithPattern)/$($summary.Count)" } else { "0/$($summary.Count)" }
    $confidence = if ($risk -eq "low") { "medium" } elseif ($risk -eq "medium") { "medium-low" } else { "low" }
    $caution = if ($risk -eq "low") { "Lower sample Part count; downstream behavior remains unknown" } elseif ($risk -eq "medium") { "Intermediate sample Part count; interpretation is corpus-limited" } else { "Pattern or high Part-count signal; downstream behavior remains unknown" }
    [pscustomobject]@{
        FolderType = $summary.FolderType
        StructuralRisk = $risk
        ObjectCount = $summary.Count
        AveragePartCount = $summary.AveragePartCount
        ParentModuleDependency = $parentDep
        PatternDependency = $patternDep
        CurrentConfidence = $confidence
        AnalyticalCaution = $caution
    }
}
Add-Table -Builder $riskBuilder -Headers @("FolderType", "StructuralRisk", "ObjectCount", "AveragePartCount", "ParentModuleDependency", "PatternDependency", "CurrentConfidence", "AnalyticalCaution") -Rows $riskRows
[System.IO.File]::WriteAllText((Join-Path $OutputRoot "16-risk-map-by-type.md"), $riskBuilder.ToString(), (Get-Utf8NoBomEncoding))

Write-Output "Advanced KB docs generated under: $OutputRoot"
