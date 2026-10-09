#requires -Version 7.4
<#
.SYNOPSIS
    Loads gx-platform-objects.json and detects platform/SDK objects in the package inventory.
#>

Set-StrictMode -Version Latest

function Import-GeneXusPlatformObjectsCatalog {
    param([string]$CatalogPath)

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "BLOCK: PlatformObjectsCatalogPath not found: $CatalogPath"
    }

    $raw = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8
    $doc = $raw | ConvertFrom-Json
    if ($null -eq $doc.objects) {
        throw "BLOCK: gx-platform-objects.json missing 'objects' array"
    }

    return $doc
}

function Get-PlatformObjectKindSets {
    param($Catalog)

    $moduleNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $externalNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in @($Catalog.objects)) {
        $name = [string]$entry.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        switch ([string]$entry.kind) {
            'packagedModule' { [void]$moduleNames.Add($name.Trim()) }
            'externalObject' { [void]$externalNames.Add($name.Trim()) }
            default {
                throw ("BLOCK: invalid kind '{0}' for entry '{1}' in the platform catalog" -f $entry.kind, $name)
            }
        }
    }

    return [pscustomobject]@{
        ModuleNames           = $moduleNames
        ExternalObjectNames   = $externalNames
    }
}

function Test-IsPlatformModuleInventoryItem {
    param($Item)

    if ($Item.sourceBlock -ne 'Objects' -or [string]::IsNullOrWhiteSpace($Item.name)) {
        return $false
    }

    # A real GeneXus 18 export brings SDK/platform as PackagedModule (GUID c88fffcd-...).
    # Module (GUID 00000000-...-000006) is a user KB container.
    return $Item.typeName -eq 'Module' -or $Item.typeName -eq 'PackagedModule'
}

function Get-SystemObjectsPresent {
    param(
        $InventoryItems,
        $PlatformKindSets
    )

    $found = [System.Collections.Generic.List[pscustomobject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in @($InventoryItems | Where-Object { Test-IsPlatformModuleInventoryItem -Item $_ })) {
        if ($PlatformKindSets.ModuleNames.Contains($item.name)) {
            $dedupeKey = ('packagedModule|{0}' -f $item.name)
            if (-not $seen.Contains($dedupeKey)) {
                $found.Add([pscustomobject]@{
                        name     = $item.name
                        kind     = 'packagedModule'
                        typeName = $item.typeName
                    }) | Out-Null
                [void]$seen.Add($dedupeKey)
            }
        }
    }

    foreach ($item in @($InventoryItems | Where-Object {
            $_.sourceBlock -eq 'Objects' -and
            $_.typeName -eq 'ExternalObject' -and
            -not [string]::IsNullOrWhiteSpace($_.name)
        })) {
        if ($PlatformKindSets.ExternalObjectNames.Contains($item.name)) {
            $dedupeKey = ('externalObject|{0}' -f $item.name)
            if (-not $seen.Contains($dedupeKey)) {
                $found.Add([pscustomobject]@{
                        name     = $item.name
                        kind     = 'externalObject'
                        typeName = $item.typeName
                    }) | Out-Null
                [void]$seen.Add($dedupeKey)
            }
        }
    }

    return @($found | Sort-Object { $_.kind }, { $_.name })
}
