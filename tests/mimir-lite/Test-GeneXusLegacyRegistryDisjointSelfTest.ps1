#requires -Version 7.4
<#
.SYNOPSIS
    Registry x catalog disjointness: orphan name, typeToken and materializedFolderName
    do not collide with the modern catalog's type/folderName; each equivalent's catalogType
    exists in the catalog; a non-null modernSuccessor exists in the catalog.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
. (Join-Path $scriptDir 'GeneXusObjectTypeCatalogSupport.ps1')

$catalogPath = Get-GeneXusObjectTypeCatalogDefaultBasePath
$catalog = Read-GeneXusObjectTypeCatalogFile -Path $catalogPath

$registryPath = Join-Path $scriptDir 'gx-legacy-export-element-registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Registry not found: $registryPath"
}
$registry = (Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json)

$catalogTypeNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$catalogFolderNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($property in $catalog.types.PSObject.Properties) {
    [void]$catalogTypeNames.Add([string]$property.Name)
    $entry = $property.Value
    if ($null -ne $entry.PSObject.Properties['folderName'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.folderName)) {
        [void]$catalogFolderNames.Add([string]$entry.folderName)
    }
}

foreach ($property in $registry.elements.PSObject.Properties) {
    $name = $property.Name
    $value = $property.Value
    $class = [string]$value.class

    if ($class -eq 'equivalent') {
        $catalogType = [string]$value.catalogType
        if (-not $catalogTypeNames.Contains($catalogType)) {
            throw "Equivalent element '$name' points to catalogType '$catalogType' which does not exist in the catalog."
        }
    }
    elseif ($class -eq 'orphan') {
        if ($catalogTypeNames.Contains($name)) {
            throw "Orphan element '$name' collides with a modern catalog type (should not have an equivalent)."
        }
        $materialized = [string]$value.materializedFolderName
        if ($catalogFolderNames.Contains($materialized) -or $catalogTypeNames.Contains($materialized)) {
            throw "Orphan element '$name' has materializedFolderName '$materialized' which collides with the catalog."
        }
        $typeToken = [string]$value.typeToken
        if ($catalogTypeNames.Contains($typeToken) -or $catalogFolderNames.Contains($typeToken)) {
            throw "Orphan element '$name' has typeToken '$typeToken' which collides with the catalog."
        }
        $successorVal = $value.modernSuccessor
        $isNullSuccessor = ($null -eq $successorVal) -or [string]::IsNullOrWhiteSpace([string]$successorVal)
        if (-not $isNullSuccessor -and -not $catalogTypeNames.Contains([string]$successorVal)) {
            throw "Orphan element '$name' points to modernSuccessor '$successorVal' which does not exist in the catalog."
        }
    }
    else {
        throw "Element '$name' with class '$class' outside {equivalent, orphan}."
    }
}

Write-Output 'GENEXUS_LEGACY_REGISTRY_DISJOINT_SELFTEST_OK'
