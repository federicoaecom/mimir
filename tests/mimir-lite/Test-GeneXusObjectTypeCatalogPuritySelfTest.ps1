#requires -Version 7.4
<#
.SYNOPSIS
    Purity of the modern gx-object-type-catalog.json catalog: objectTypeGuid null
    is only accepted for rootKind Attribute; every other rootKind requires a valid UUID;
    fail-safe for a new rootKind (outside Object/Virtual/Attribute).
.DESCRIPTION
    Does not use a "looks synthetic" heuristic: GUIDs with a repeated pattern
    (dcdcdcdc-... DataStore, ecececec-... Generator) are real and confirmed in a
    real export. The criterion is structural (rootKind), not the shape of the GUID.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
. (Join-Path $scriptDir 'GeneXusObjectTypeCatalogSupport.ps1')

$catalogPath = Get-GeneXusObjectTypeCatalogDefaultBasePath
$catalog = Read-GeneXusObjectTypeCatalogFile -Path $catalogPath

if ($null -eq $catalog.PSObject.Properties['types'] -or $null -eq $catalog.types) {
    throw "Catalog without a 'types' property: $catalogPath"
}

$knownRootKinds = @('Object', 'Virtual', 'Attribute')

foreach ($property in $catalog.types.PSObject.Properties) {
    $typeName = $property.Name
    $entry = $property.Value

    if ($null -eq $entry.PSObject.Properties['rootKind']) {
        throw "Type '$typeName' without a 'rootKind'."
    }
    $rootKind = [string]$entry.rootKind

    if ($knownRootKinds -notcontains $rootKind) {
        throw "Type '$typeName' uses unknown rootKind '$rootKind'. Review the purity rule (fail-safe): only Attribute may have a null objectTypeGuid; a new rootKind needs an explicit decision."
    }

    if ($null -eq $entry.PSObject.Properties['objectTypeGuid']) {
        throw "Type '$typeName' without an 'objectTypeGuid'."
    }
    $guidVal = $entry.objectTypeGuid
    $isNullGuid = ($null -eq $guidVal) -or [string]::IsNullOrWhiteSpace([string]$guidVal)

    if ($isNullGuid) {
        if ($rootKind -ne 'Attribute') {
            throw "Type '$typeName' has a null objectTypeGuid but rootKind '$rootKind' (null is only allowed for rootKind Attribute)."
        }
        continue
    }

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse([string]$guidVal, [ref]$parsed)) {
        throw "Type '$typeName' has objectTypeGuid '$guidVal' which is not a valid UUID."
    }
}

Write-Output 'GENEXUS_CATALOG_PURITY_SELFTEST_OK'
