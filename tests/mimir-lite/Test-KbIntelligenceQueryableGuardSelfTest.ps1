#requires -Version 7.4
<#
.SYNOPSIS
    Validates blocking of semantic queries when queryableByKbIntelligence=false.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-queryable-guard-selftest-{0}" -f ([guid]::NewGuid().ToString('N')))
try {
$kbObjectsPath = Join-Path $tempRoot 'KbObjectsXml'
$scriptsPath = Join-Path $tempRoot 'scripts'
$sdpDir = Join-Path $kbObjectsPath 'SmartDevicesPlus'
$sqlitePath = Join-Path $tempRoot 'KbIntelligence\kb-intelligence.sqlite'

[void](New-Item -ItemType Directory -Path $sdpDir -Force)
[void](New-Item -ItemType Directory -Path $scriptsPath -Force)
[void](New-Item -ItemType Directory -Path (Split-Path -Parent $sqlitePath) -Force)

$sdpXml = @'
<Object type="c84ec0ea-d159-46e2-a118-2108860379bb" name="SmartDevicesPlus" description="Smart Devices Plus" parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361"><Properties><Property><Name>SDPlus_Settings_Theme</Name><Value>DarkBlue</Value></Property></Properties></Object>
'@
[System.IO.File]::WriteAllText((Join-Path $sdpDir 'SmartDevicesPlus.xml'), $sdpXml, (Get-Utf8NoBomEncoding))

& $buildScript -SourceRoot $kbObjectsPath -OutputPath $sqlitePath -KbWorkspaceRoot $tempRoot
if ($LASTEXITCODE -ne 0) {
    throw "Build-KbIntelligenceIndex failed; exit $LASTEXITCODE"
}

$blockedJson = & $queryScript `
    -IndexPath $sqlitePath `
    -KbWorkspaceRoot $tempRoot `
    -Query impact-basic `
    -ObjectType SmartDevicesPlus `
    -ObjectName SmartDevicesPlus `
    -Format json 2>&1 | Out-String
$blockedExit = $LASTEXITCODE

if ($blockedExit -ne 11) {
    throw "impact-basic on SmartDevicesPlus (base) should exit 11; got $blockedExit"
}

$blocked = $blockedJson | ConvertFrom-Json
if (-not $blocked.blocked) {
    throw 'impact-basic should return blocked=true'
}
if ($blocked.reason -ne 'QUERY_NOT_SEMANTIC_FOR_TYPE') {
    throw "expected reason QUERY_NOT_SEMANTIC_FOR_TYPE; got $($blocked.reason)"
}

$infoJson = & $queryScript `
    -IndexPath $sqlitePath `
    -KbWorkspaceRoot $tempRoot `
    -Query object-info `
    -ObjectType SmartDevicesPlus `
    -ObjectName SmartDevicesPlus `
    -Format json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "object-info should exit 0; got $LASTEXITCODE"
}
if ($infoJson.found -ne $true) {
    throw 'object-info should find SmartDevicesPlus in the index'
}

# Event-bearing types whose calls the index does not extract (the mobile types and the legacy
# WorkPanel) are blocked as a source or target in the base catalog, like Panel, instead of
# returning an empty graph.
foreach ($mobileType in @('Panel', 'WorkWith', 'SmartDevicesApplication', 'WorkPanel')) {
    foreach ($semanticQuery in @('who-uses', 'what-uses')) {
        $mobileJson = & $queryScript `
            -IndexPath $sqlitePath `
            -KbWorkspaceRoot $tempRoot `
            -Query $semanticQuery `
            -ObjectType $mobileType `
            -ObjectName 'AnyMobileObject' `
            -Format json 2>&1 | Out-String
        if ($LASTEXITCODE -ne 11) {
            throw "$semanticQuery on $mobileType (base) should exit 11; got $LASTEXITCODE"
        }
        $mobileBlocked = $mobileJson | ConvertFrom-Json
        if ($mobileBlocked.reason -ne 'QUERY_NOT_SEMANTIC_FOR_TYPE') {
            throw "$semanticQuery on ${mobileType}: expected reason QUERY_NOT_SEMANTIC_FOR_TYPE; got $($mobileBlocked.reason)"
        }
    }
}
$webWwJson = & $queryScript `
    -IndexPath $sqlitePath `
    -KbWorkspaceRoot $tempRoot `
    -Query what-uses `
    -ObjectType WorkWithForWeb `
    -ObjectName 'AnyWebWorkWith' `
    -Format json 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "what-uses on WorkWithForWeb (base) must stay allowed; got exit $LASTEXITCODE"
}

$overridePath = Join-Path $scriptsPath 'gx-object-type-catalog.override.json'
$overrideJson = @{
    schemaVersion                   = 1
    upstreamPending                 = $true
    registrationRequiresUpstreamSync = $true
    types                           = @{
        SmartDevicesPlus = @{
            objectTypeGuid              = 'c84ec0ea-d159-46e2-a118-2108860379bb'
            rootKind                    = 'Object'
            folderName                  = 'SmartDevicesPlus'
            inventoryEligible           = $true
            queryableByKbIntelligence   = $true
            containerType               = $false
            notes                       = 'override selftest: allow semantic query'
        }
        Procedure        = @{
            objectTypeGuid              = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
            rootKind                    = 'Object'
            folderName                  = 'Procedure'
            inventoryEligible           = $true
            queryableByKbIntelligence   = $false
            containerType               = $false
            notes                       = 'override selftest: block semantic query'
        }
    }
}
$overrideJson | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $overridePath -Encoding utf8

$allowedJson = & $queryScript `
    -IndexPath $sqlitePath `
    -KbWorkspaceRoot $tempRoot `
    -CatalogOverridePath $overridePath `
    -Query impact-basic `
    -ObjectType SmartDevicesPlus `
    -ObjectName SmartDevicesPlus `
    -Format json 2>&1 | Out-String
if ($LASTEXITCODE -eq 11) {
    throw 'impact-basic on SmartDevicesPlus with override queryable=true should not exit 11'
}

$procDir = Join-Path $kbObjectsPath 'Procedure'
[void](New-Item -ItemType Directory -Path $procDir -Force)
$procXml = @'
<Object type="84a12160-f59b-4ad7-a683-ea4481ac23e9" name="procSelfTestQueryable" description="proc selftest" parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361"><Properties><Property><Name>Name</Name><Value>procSelfTestQueryable</Value></Property></Properties><Source><![CDATA[]]></Source></Object>
'@
[System.IO.File]::WriteAllText((Join-Path $procDir 'procSelfTestQueryable.xml'), $procXml, (Get-Utf8NoBomEncoding))

& $buildScript -SourceRoot $kbObjectsPath -OutputPath $sqlitePath -KbWorkspaceRoot $tempRoot -CatalogOverridePath $overridePath
if ($LASTEXITCODE -ne 0) {
    throw "Rebuild with Procedure failed; exit $LASTEXITCODE"
}

$procBlocked = & $queryScript `
    -IndexPath $sqlitePath `
    -KbWorkspaceRoot $tempRoot `
    -CatalogOverridePath $overridePath `
    -Query impact-basic `
    -ObjectType Procedure `
    -ObjectName procSelfTestQueryable `
    -Format json 2>&1 | Out-String
if ($LASTEXITCODE -ne 11) {
    throw "impact-basic on Procedure with override queryable=false should exit 11; got $LASTEXITCODE"
}

$procBlockedObj = $procBlocked | ConvertFrom-Json
if ($procBlockedObj.reason -ne 'QUERY_NOT_SEMANTIC_FOR_TYPE') {
    throw "Procedure override: expected reason QUERY_NOT_SEMANTIC_FOR_TYPE"
}

Write-Output 'OK: Test-KbIntelligenceQueryableGuardSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
