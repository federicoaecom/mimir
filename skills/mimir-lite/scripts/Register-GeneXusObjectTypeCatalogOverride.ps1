#requires -Version 7.4
<#
.SYNOPSIS
    Registers a palliative entry in gx-object-type-catalog.override.json (with upstream pending).

.DESCRIPTION
    Writes or updates the local override in the KB workspace. Requires explicit consent
    recorded via -UserApproved. Does not change the shared mimir-lite catalog.
    Flags: a type the base catalog already knows (same name, or else the same GUID) keeps
    the base inventoryEligible, queryableByKbIntelligence, and containerType values; a type
    missing from the base gets inventoryEligible=true, queryableByKbIntelligence=true, and
    containerType=false. There is no parameter to set these flags.

.PARAMETER KbWorkspaceRoot
    Root of the KB workspace.

.PARAMETER TypeName
    Canonical type name (JSON key, e.g. DataView).

.PARAMETER ObjectTypeGuid
    GUID of Object/@type in the XPZ/XML.

.PARAMETER FolderName
    Subfolder name in KbObjectsXml (default: TypeName).

.PARAMETER UserApproved
    Required. Confirms the user's explicit consent for local registration.

.PARAMETER EvidenceSummary
    Short summary of the evidence (XML, nexa, wiki).

.PARAMETER WikiLinks
    Official GeneXus links consulted.

.PARAMETER NexaFindings
    Findings from the nexa skill when applicable.

.PARAMETER CatalogOverridePath
    Alternative path to the override file.

.PARAMETER AsJson
    Emits JSON with the result.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KbWorkspaceRoot,

    [Parameter(Mandatory = $true)]
    [string]$TypeName,

    [Parameter(Mandatory = $true)]
    [string]$ObjectTypeGuid,

    [string]$FolderName,

    [switch]$UserApproved,

    [string]$EvidenceSummary,

    [string[]]$WikiLinks = @(),

    [string]$NexaFindings,

    [string]$CatalogOverridePath,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

if (-not $UserApproved) {
    throw 'BLOCK: local registration requires -UserApproved after the user''s explicit consent.'
}

$supportScript = Join-Path $PSScriptRoot 'GeneXusObjectTypeCatalogSupport.ps1'
. $supportScript

$resolvedKbRoot = (Resolve-Path -LiteralPath $KbWorkspaceRoot).Path
if (-not $CatalogOverridePath) {
    $CatalogOverridePath = Get-GeneXusObjectTypeCatalogDefaultOverridePath -KbWorkspaceRoot $resolvedKbRoot
}

if ([string]::IsNullOrWhiteSpace($CatalogOverridePath)) {
    throw 'BLOCK: CatalogOverridePath not resolved.'
}

if ([string]::IsNullOrWhiteSpace($FolderName)) {
    $FolderName = $TypeName.Trim()
}

$typeNameKey = $TypeName.Trim()
$guidValue = $ObjectTypeGuid.Trim().ToLowerInvariant()

$overrideObject = $null
if (Test-Path -LiteralPath $CatalogOverridePath -PathType Leaf) {
    $existingClassification = Get-GeneXusCatalogOverrideClassification `
        -CatalogOverridePath $CatalogOverridePath `
        -KbWorkspaceRoot $resolvedKbRoot
    if ($existingClassification.status -in @('INVALID_OVERRIDE_SHAPE', 'OVERRIDE_RESOLUTION_BLOCKED')) {
        $result = [pscustomobject]@{
            status           = $existingClassification.status
            blocked          = $true
            reason           = $existingClassification.reason
            diagnosticReason = $existingClassification.diagnosticReason
            fieldPath        = $existingClassification.fieldPath
            overridePath     = $CatalogOverridePath
            typeName         = $typeNameKey
            objectTypeGuid   = $guidValue
            message          = 'Existing local override is invalid or blocking; registration not written in order to preserve structured diagnostics.'
            classification   = $existingClassification
        }
        if ($AsJson) { $result | ConvertTo-Json -Depth 10 } else { $result | Format-List }
        exit 2
    }
    $overrideObject = Read-GeneXusObjectTypeCatalogFile -Path $CatalogOverridePath
} else {
    $overrideObject = [pscustomobject]@{
        schemaVersion       = 1
        upstreamPending     = $true
        lastLocalRegistrationAt = (Get-Date).ToString('o')
        types               = [pscustomobject]@{}
    }
}

# Flags: a type missing from the base gets the defaults (inventory-eligible, queryable, not a
# container). A type the base already knows (same name, or else the same GUID) keeps the base
# flags, so a registration never silently re-enables semantic queries on a type the base marks
# queryableByKbIntelligence=false (or changes inventoryEligible/containerType).
$inventoryEligibleValue = $true
$queryableValue = $true
$containerTypeValue = $false
$baseCatalogForFlags = Read-GeneXusObjectTypeCatalogFile -Path (Get-GeneXusObjectTypeCatalogDefaultBasePath)
$baseEntryForFlags = $null
foreach ($baseProperty in $baseCatalogForFlags.types.PSObject.Properties) {
    if ($baseProperty.Name.Equals($typeNameKey, [StringComparison]::OrdinalIgnoreCase)) {
        $baseEntryForFlags = $baseProperty.Value
        break
    }
}
if ($null -eq $baseEntryForFlags) {
    foreach ($baseProperty in $baseCatalogForFlags.types.PSObject.Properties) {
        $baseGuid = Get-GeneXusCatalogEntryValue $baseProperty.Value 'objectTypeGuid'
        if ($null -ne $baseGuid -and ([string]$baseGuid).Trim().ToLowerInvariant() -eq $guidValue) {
            $baseEntryForFlags = $baseProperty.Value
            break
        }
    }
}
if ($null -ne $baseEntryForFlags) {
    $baseInventoryEligible = Get-GeneXusCatalogEntryValue $baseEntryForFlags 'inventoryEligible'
    $baseQueryable = Get-GeneXusCatalogEntryValue $baseEntryForFlags 'queryableByKbIntelligence'
    $baseContainerType = Get-GeneXusCatalogEntryValue $baseEntryForFlags 'containerType'
    if ($baseInventoryEligible -is [bool]) { $inventoryEligibleValue = $baseInventoryEligible }
    if ($baseQueryable -is [bool]) { $queryableValue = $baseQueryable }
    if ($baseContainerType -is [bool]) { $containerTypeValue = $baseContainerType }
}

$typeEntry = [ordered]@{
    objectTypeGuid  = $guidValue
    rootKind        = 'Object'
    folderName      = $FolderName
    inventoryEligible = $inventoryEligibleValue
    queryableByKbIntelligence = $queryableValue
    containerType   = $containerTypeValue
    evidenceSummary = $EvidenceSummary
    wikiLinks       = @($WikiLinks)
    nexaFindings    = $NexaFindings
    notes           = 'Local palliative entry; upstreamPending in the mimir-lite base.'
}


$candidateTypesTable = [ordered]@{}
if ($null -ne $overrideObject -and $null -ne $overrideObject.PSObject.Properties['types'] -and $null -ne $overrideObject.types) {
    foreach ($property in $overrideObject.types.PSObject.Properties) {
        $candidateTypesTable[$property.Name] = $property.Value
    }
}
$candidateTypesTable[$typeNameKey] = [pscustomobject]$typeEntry

$candidateRoot = [ordered]@{}
if ($null -ne $overrideObject) {
    foreach ($property in $overrideObject.PSObject.Properties) {
        if ($property.Name -ne 'types') {
            $candidateRoot[$property.Name] = $property.Value
        }
    }
}
if (-not $candidateRoot.Contains('schemaVersion')) { $candidateRoot['schemaVersion'] = 1 }
if (-not $candidateRoot.Contains('upstreamPending')) { $candidateRoot['upstreamPending'] = $true }
$candidateRoot['types'] = [pscustomobject]$candidateTypesTable
$candidateOverride = [pscustomobject]$candidateRoot

$candidateClassification = Get-GeneXusCatalogOverrideClassification `
    -CatalogOverridePath $CatalogOverridePath `
    -KbWorkspaceRoot $resolvedKbRoot `
    -OverrideCatalog $candidateOverride `
    -OverridePathForDiagnostics $CatalogOverridePath
$candidateEntry = @($candidateClassification.classificationEntries | Where-Object { $_.typeName -eq $typeNameKey } | Select-Object -First 1)

if ($candidateClassification.status -in @('INVALID_OVERRIDE_SHAPE', 'OVERRIDE_RESOLUTION_BLOCKED') -or ($null -ne $candidateEntry -and $candidateEntry.effectiveCatalogAction -eq 'block-resolution')) {
    $result = [pscustomobject]@{
        status           = if ($candidateEntry.reason -eq 'unsafe-shadowing') { 'LOCAL_OVERRIDE_UNSAFE_SHADOWING_BLOCKED' } elseif ($candidateEntry.reason -eq 'unsafe-duplicate-guid') { 'LOCAL_OVERRIDE_UNSAFE_DUPLICATE_GUID_BLOCKED' } else { $candidateClassification.status }
        blocked          = $true
        reason           = if ($null -ne $candidateEntry) { $candidateEntry.reason } else { $candidateClassification.reason }
        diagnosticReason = if ($null -ne $candidateEntry) { $candidateEntry.diagnosticReason } else { $candidateClassification.diagnosticReason }
        overridePath     = $CatalogOverridePath
        typeName         = $typeNameKey
        objectTypeGuid   = $guidValue
        message          = 'Local override not written because it would block safe resolution of the effective catalog.'
        classification   = $candidateClassification
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 10 } else { $result | Format-List }
    exit 2
}

if ($null -ne $candidateEntry -and $candidateEntry.classification -eq 'redundant') {
    $result = [pscustomobject]@{
        status           = 'LOCAL_OVERRIDE_REDUNDANT_BLOCKED'
        blocked          = $true
        reason           = $candidateEntry.reason
        diagnosticReason = $candidateEntry.diagnosticReason
        overridePath     = $CatalogOverridePath
        typeName         = $typeNameKey
        objectTypeGuid   = $guidValue
        baseTypeName     = $candidateEntry.baseTypeName
        message          = 'Not written because the type is already in the base catalog in an equivalent way; remove or avoid a redundant local override.'
        classification   = $candidateClassification
    }
    if ($AsJson) { $result | ConvertTo-Json -Depth 10 } else { $result | Format-List }
    exit 2
}

$scriptsDir = Split-Path -Parent $CatalogOverridePath
if (-not (Test-Path -LiteralPath $scriptsDir)) {
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
}

$typesTable = $candidateTypesTable

$payload = [ordered]@{}
foreach ($property in $candidateOverride.PSObject.Properties) {
    if ($property.Name -ne 'types') { $payload[$property.Name] = $property.Value }
}
$payload['upstreamPending'] = $true
$payload['lastLocalRegistrationAt'] = (Get-Date).ToString('o')
$payload['registrationRequiresUpstreamSync'] = $true
$payload['types'] = [pscustomobject]$typesTable

$json = ($payload | ConvertTo-Json -Depth 8)
[System.IO.File]::WriteAllText($CatalogOverridePath, $json, (Get-Utf8NoBomEncoding))

$reminder = Get-GeneXusCatalogOverrideSessionReminder -KbWorkspaceRoot $resolvedKbRoot -CatalogOverridePath $CatalogOverridePath

$result = [pscustomobject]@{
    status            = 'LOCAL_OVERRIDE_REGISTERED'
    overridePath      = (Resolve-Path -LiteralPath $CatalogOverridePath).Path
    typeName          = $typeNameKey
    objectTypeGuid    = $guidValue
    folderName        = $FolderName
    upstreamPending   = $true
    reminder          = $reminder
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
} else {
    $result | Format-List
}

exit 0
