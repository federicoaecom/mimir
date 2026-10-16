#requires -Version 7.4
<#
.SYNOPSIS
    Intra-registry shape of gx-legacy-export-element-registry.json: schemaVersion,
    class equivalent|orphan, exact fields per class (orphans may add the optional boolean
    indexedByKbIntelligence), typeToken and coherence between successorRelation and modernSuccessor.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
$registryPath = Join-Path $scriptDir 'gx-legacy-export-element-registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Registry not found: $registryPath"
}

$registry = (Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json)

if ($null -eq $registry.PSObject.Properties['schemaVersion'] -or [int]$registry.schemaVersion -ne 1) {
    throw "schemaVersion expected 1."
}
if ($null -eq $registry.PSObject.Properties['elements'] -or $null -eq $registry.elements) {
    throw "Registry missing 'elements' property."
}

$typeTokenRegex = [regex]::new('^gxlegacy/[A-Za-z][A-Za-z0-9]*$')
$equivalentFields = @('class', 'catalogType')
$orphanFields = @('class', 'materializedFolderName', 'typeToken', 'modernSuccessor', 'successorRelation')
$orphanOptionalFields = @('indexedByKbIntelligence')
$knownRelations = @('absorbed', 'none')
$elementCount = 0

foreach ($property in $registry.elements.PSObject.Properties) {
    $name = $property.Name
    $value = $property.Value
    $elementCount++

    if ($null -eq $value.PSObject.Properties['class']) {
        throw "Element '$name' missing 'class'."
    }
    $class = [string]$value.class
    $actualFields = @($value.PSObject.Properties.Name | Sort-Object)

    if ($class -eq 'equivalent') {
        $expected = @($equivalentFields | Sort-Object)
        if (($actualFields -join ',') -ne ($expected -join ',')) {
            throw "Equivalent element '$name' has fields [$($actualFields -join ', ')]; expected [$($expected -join ', ')]."
        }
        if ([string]::IsNullOrWhiteSpace([string]$value.catalogType)) {
            throw "Equivalent element '$name' has an empty catalogType."
        }
    }
    elseif ($class -eq 'orphan') {
        $requiredActual = @($actualFields | Where-Object { $orphanOptionalFields -notcontains $_ })
        $expected = @($orphanFields | Sort-Object)
        if (($requiredActual -join ',') -ne ($expected -join ',')) {
            throw "Orphan element '$name' has fields [$($actualFields -join ', ')]; expected [$($expected -join ', ')] plus optional [$($orphanOptionalFields -join ', ')]."
        }
        if ($null -ne $value.PSObject.Properties['indexedByKbIntelligence'] -and $value.indexedByKbIntelligence -isnot [bool]) {
            throw "Orphan element '$name' has a non-boolean indexedByKbIntelligence."
        }
        if ([string]::IsNullOrWhiteSpace([string]$value.materializedFolderName)) {
            throw "Orphan element '$name' has an empty materializedFolderName."
        }
        $typeToken = [string]$value.typeToken
        if (-not $typeTokenRegex.IsMatch($typeToken)) {
            throw "Orphan element '$name' has typeToken '$typeToken' outside the format ^gxlegacy/[A-Za-z][A-Za-z0-9]*$."
        }
        $relation = [string]$value.successorRelation
        if ($knownRelations -notcontains $relation) {
            throw "Orphan element '$name' has successorRelation '$relation' outside the known set [$($knownRelations -join ', ')]."
        }
        $successorVal = $value.modernSuccessor
        $isNullSuccessor = ($null -eq $successorVal) -or [string]::IsNullOrWhiteSpace([string]$successorVal)
        if ($relation -eq 'none' -and -not $isNullSuccessor) {
            throw "Orphan element '$name' with successorRelation 'none' must have a null modernSuccessor."
        }
        if ($relation -eq 'absorbed' -and $isNullSuccessor) {
            throw "Orphan element '$name' with successorRelation 'absorbed' must have a non-null modernSuccessor."
        }
    }
    else {
        throw "Element '$name' has class '$class' outside {equivalent, orphan}."
    }
}

if ($elementCount -lt 1) {
    throw "Registry has no elements."
}

# The GeneXus 7.0 and earlier (.xpw) elements Menu, Prompt, and Formula sync as orphans that KB Intelligence does not index.
foreach ($xpwOrphan in @('Menu', 'Prompt', 'Formula')) {
    $entry = $registry.elements.PSObject.Properties[$xpwOrphan]
    if ($null -eq $entry -or [string]$entry.Value.class -ne 'orphan') {
        throw "Element '$xpwOrphan' should be registered as an orphan."
    }
    if ([string]$entry.Value.materializedFolderName -ne $xpwOrphan -or [string]$entry.Value.typeToken -ne "gxlegacy/$xpwOrphan") {
        throw "Orphan '$xpwOrphan' should materialize under '$xpwOrphan' with typeToken 'gxlegacy/$xpwOrphan'."
    }
    if ($null -ne $entry.Value.PSObject.Properties['indexedByKbIntelligence']) {
        throw "Orphan '$xpwOrphan' should not carry indexedByKbIntelligence (it is not indexed)."
    }
}

Write-Output 'GENEXUS_LEGACY_REGISTRY_SCHEMA_SELFTEST_OK'
