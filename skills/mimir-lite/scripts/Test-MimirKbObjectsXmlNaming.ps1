#requires -Version 7.4
<#
.SYNOPSIS
Audits the naming of KbObjectsXml's immediate directories.

.DESCRIPTION
For each immediate directory in KbObjectsXml, reads the first classifiable XML,
extracts the canonical type from the Attribute root element or from Object/@type, compares
it against the directory name, and emits a structured result. Uses the effective catalog
(shared base + local override in the KB workspace's scripts/ when it exists).
The script is read-only.

.PARAMETER KbWorkspaceRoot
Root of the KB workspace.

.PARAMETER CatalogPath
Optional path to gx-object-type-catalog.json (shared base).

.PARAMETER CatalogOverridePath
Optional path to gx-object-type-catalog.override.json in the KB workspace.

.PARAMETER AsJson
Emits structured JSON instead of the text table.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KbWorkspaceRoot,

    [string]$CatalogPath,

    [string]$CatalogOverridePath,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$supportScript = Join-Path $PSScriptRoot 'GeneXusObjectTypeCatalogSupport.ps1'
if (-not (Test-Path -LiteralPath $supportScript -PathType Leaf)) {
    throw "Support script not found: $supportScript"
}
. $supportScript

function Get-GeneXusLegacyOrphanTokenMap {
    # Map typeToken (lower) -> { TypeToken, FolderName } of the orphan legacy elements from the
    # gx-legacy-export-element-registry.json registry (GX9 legacy-export governance layer). Loaded
    # dynamically; missing -> empty map (unchanged behavior).
    $registryPath = Join-Path $PSScriptRoot 'gx-legacy-export-element-registry.json'
    $map = @{}
    if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
        return $map
    }
    $registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $registry.PSObject.Properties['elements']) {
        return $map
    }
    foreach ($prop in $registry.elements.PSObject.Properties) {
        $element = $prop.Value
        if ($null -ne $element.PSObject.Properties['class'] -and $element.class -eq 'orphan') {
            $token = [string]$element.typeToken
            $folder = [string]$element.materializedFolderName
            if (-not [string]::IsNullOrWhiteSpace($token) -and -not [string]::IsNullOrWhiteSpace($folder)) {
                $map[$token.ToLowerInvariant()] = [pscustomobject]@{ TypeToken = $token; FolderName = $folder }
            }
        }
    }
    return $map
}

function Write-StructuredError {
    param([string]$Message)

    if ($AsJson) {
        [pscustomobject]@{
            status    = 'STRUCTURAL_ERROR'
            divergent = @()
            all       = @()
            error     = $Message
        } | ConvertTo-Json -Depth 8
    } else {
        Write-Output "STRUCTURAL_ERROR: $Message"
    }
}

function Try-ClassifyXml {
    param(
        [string]$Path,
        [hashtable]$GuidMap,
        [hashtable]$LegacyOrphanMap
    )

    $document = [xml](Get-Content -LiteralPath $Path -Raw)
    $root = $document.DocumentElement
    if ($null -eq $root) {
        throw "XML has no root element"
    }

    $rootName = $root.LocalName
    if ($rootName -eq 'Attribute' -or $rootName -eq 'Attributes') {
        return [pscustomobject]@{
            Root                 = $rootName
            TypeGuid             = $null
            ActualType             = 'Attribute'
            ExpectedCanonicalName = 'Attribute'
            NamingStatus         = $null
            SourceFile           = $Path
        }
    }

    if ($rootName -ne 'Object') {
        return [pscustomobject]@{
            Root                 = $rootName
            TypeGuid             = $null
            ActualType             = 'UNKNOWN'
            ExpectedCanonicalName = $null
            NamingStatus         = 'UNKNOWN_TYPE'
            SourceFile           = $Path
        }
    }

    $typeGuid = $root.GetAttribute('type')
    if ([string]::IsNullOrWhiteSpace($typeGuid)) {
        return [pscustomobject]@{
            Root                 = $rootName
            TypeGuid             = $null
            ActualType             = 'UNKNOWN'
            ExpectedCanonicalName = $null
            NamingStatus         = 'UNKNOWN_TYPE'
            SourceFile           = $Path
        }
    }

    if ($typeGuid -match '^gxlegacy/') {
        # Orphan legacy element materialized by typeToken (gxlegacy/<Elemento>): the @type never
        # matches a modern catalog GUID; classify from the registry, not as UNKNOWN_TYPE.
        $tokenKey = $typeGuid.ToLowerInvariant()
        if ($null -ne $LegacyOrphanMap -and $LegacyOrphanMap.ContainsKey($tokenKey)) {
            $orphan = $LegacyOrphanMap[$tokenKey]
            return [pscustomobject]@{
                Root                 = $rootName
                TypeGuid             = $typeGuid
                ActualType             = $orphan.TypeToken
                ExpectedCanonicalName = $orphan.FolderName
                NamingStatus         = $null
                SourceFile           = $Path
            }
        }
        # Unregistered gxlegacy typeToken -> unknown (defensive).
        return [pscustomobject]@{
            Root                 = $rootName
            TypeGuid             = $typeGuid
            ActualType             = 'UNKNOWN_TYPE'
            ExpectedCanonicalName = $null
            NamingStatus         = 'UNKNOWN_TYPE'
            SourceFile           = $Path
        }
    }

    $guidKey = $typeGuid.ToLowerInvariant()
    if (-not $GuidMap.ContainsKey($guidKey)) {
        return [pscustomobject]@{
            Root                 = $rootName
            TypeGuid             = $typeGuid
            ActualType             = 'UNKNOWN_TYPE'
            ExpectedCanonicalName = $null
            NamingStatus         = 'UNKNOWN_TYPE'
            SourceFile           = $Path
        }
    }

    $mapped = $GuidMap[$guidKey]
    return [pscustomobject]@{
        Root                 = $rootName
        TypeGuid             = $typeGuid
        ActualType             = $mapped.TypeName
        ExpectedCanonicalName = $mapped.FolderName
        NamingStatus         = $null
        SourceFile           = $Path
    }
}

try {
    $resolvedKbRoot = (Resolve-Path -LiteralPath $KbWorkspaceRoot).Path
    $kbObjectsPath = Join-Path $resolvedKbRoot 'KbObjectsXml'
    if (-not (Test-Path -LiteralPath $kbObjectsPath -PathType Container)) {
        throw "KbObjectsXml not found: $kbObjectsPath"
    }

    $catalogResolution = Resolve-GeneXusObjectTypeCatalogPaths -BaseCatalogPath $CatalogPath -CatalogOverridePath $CatalogOverridePath -KbWorkspaceRoot $resolvedKbRoot
    $typeMap = Get-GeneXusCatalogGuidToTypeMap -MergedCatalog $catalogResolution.MergedCatalog
    $guidMap = @{}
    foreach ($entry in $typeMap.GetEnumerator()) {
        $guidMap[$entry.Key] = $entry.Value
    }
    $legacyOrphanMap = Get-GeneXusLegacyOrphanTokenMap
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($dir in Get-ChildItem -LiteralPath $kbObjectsPath -Directory | Sort-Object Name) {
        $xmlFiles = @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.xml' -File | Sort-Object Name)
        if ($xmlFiles.Count -eq 0) {
            $rows.Add([pscustomobject]@{
                Directory             = $dir.Name
                Root                  = $null
                TypeGuid              = $null
                ActualType              = 'INDETERMINATE'
                NamingStatus          = 'INDETERMINATE'
                ExpectedCanonicalName  = $null
                SourceFile            = $null
                Note            = 'directory has no readable XML'
            })
            continue
        }

        $classified = $null
        $lastError = $null
        foreach ($xmlFile in $xmlFiles) {
            try {
                $classified = Try-ClassifyXml -Path $xmlFile.FullName -GuidMap $guidMap -LegacyOrphanMap $legacyOrphanMap
                break
            } catch {
                $lastError = $_.Exception.Message
            }
        }

        if ($null -eq $classified) {
            $rows.Add([pscustomobject]@{
                Directory             = $dir.Name
                Root                  = $null
                TypeGuid              = $null
                ActualType              = 'INDETERMINATE'
                NamingStatus          = 'INDETERMINATE'
                ExpectedCanonicalName  = $null
                SourceFile            = $null
                Note            = "no classifiable XML: $lastError"
            })
            continue
        }

        $status = $classified.NamingStatus
        if ($null -eq $status) {
            $status = if ($dir.Name -eq $classified.ExpectedCanonicalName) { 'OK' } else { 'DIVERGENT' }
        }

        $rows.Add([pscustomobject]@{
            Directory             = $dir.Name
            Root                  = $classified.Root
            TypeGuid              = $classified.TypeGuid
            ActualType              = $classified.ActualType
            NamingStatus          = $status
            ExpectedCanonicalName  = if ($status -eq 'DIVERGENT') { $classified.ExpectedCanonicalName } else { $null }
            SourceFile            = $classified.SourceFile
            Note            = if ($status -eq 'UNKNOWN_TYPE') {
                if ($catalogResolution.OverrideActive) {
                    'GUID not mapped in the effective catalog (base + override); update gx-object-type-catalog.override.json or the mimir-lite repository (gx-object-type-catalog.json + 01a)'
                } else {
                    'GUID not mapped in the effective catalog; update the mimir-lite repository (gx-object-type-catalog.json + 01a) or register an approved local override'
                }
            } else { $null }
        })
    }

    $divergentRows = @($rows | Where-Object { $_.NamingStatus -eq 'DIVERGENT' })
    $indeterminedRows = @($rows | Where-Object { $_.NamingStatus -in @('INDETERMINATE', 'UNKNOWN_TYPE') })
    $statusText = if ($divergentRows.Count -gt 0) {
        'NAMING_DIVERGENT'
    } elseif ($indeterminedRows.Count -gt 0) {
        'NAMING_INDETERMINATE'
    } else {
        'NAMING_OK'
    }

    if ($AsJson) {
        [pscustomobject]@{
            status                 = $statusText
            divergent              = @($divergentRows | ForEach-Object { $_.Directory })
            all                    = @($rows)
            catalogBasePath        = $catalogResolution.BaseCatalogPath
            catalogOverridePath    = $catalogResolution.OverridePath
            catalogOverrideActive  = $catalogResolution.OverrideActive
            catalogUpstreamPending = $catalogResolution.UpstreamPending
            catalogDeclaredUpstreamPending = $catalogResolution.DeclaredUpstreamPending
            catalogEffectiveUpstreamPending = $catalogResolution.EffectiveUpstreamPending
            catalogOverrideClassification = $catalogResolution.OverrideClassification
        } | ConvertTo-Json -Depth 10
    } else {
        $rows |
            Select-Object Directory, Root, TypeGuid, ActualType, NamingStatus, ExpectedCanonicalName |
            Format-Table -AutoSize

        if ($divergentRows.Count -gt 0) {
            Write-Output ("NAMING_DIVERGENT: {0}" -f (($divergentRows | ForEach-Object { $_.Directory }) -join ','))
        } elseif ($indeterminedRows.Count -gt 0) {
            Write-Output ("NAMING_INDETERMINATE: {0}" -f (($indeterminedRows | ForEach-Object { $_.Directory }) -join ','))
        } else {
            Write-Output 'NAMING_OK'
        }
    }

    if ($divergentRows.Count -gt 0) {
        exit 1
    }

    exit 0
} catch {
    Write-StructuredError -Message $_.Exception.Message
    exit 2
}
