#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for classifying gx-object-type-catalog.override.json.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
. (Join-Path $scriptDir 'GeneXusObjectTypeCatalogSupport.ps1')
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){ throw $Message } }
function Write-JsonFile { param([string]$Path,[object]$Value) [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), (Get-Utf8NoBomEncoding)) }
function New-CaseRoot { param([string]$Name) $root=Join-Path ([IO.Path]::GetTempPath()) ("gx-catalog-override-$Name-" + [guid]::NewGuid().ToString('N')); [void](New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force); return $root }
function New-BareRoot { param([string]$Name) $root=Join-Path ([IO.Path]::GetTempPath()) ("gx-catalog-override-$Name-" + [guid]::NewGuid().ToString('N')); [void](New-Item -ItemType Directory -Path $root -Force); return $root }
function Invoke-Reminder { param([string]$Root) return Get-GeneXusCatalogOverrideSessionReminder -KbWorkspaceRoot $Root }

# Python discovery is shared with the product (python3, python, py -3; 3.8 or later).
. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')
$python = Get-GeneXusPythonExecutable
if ($null -eq $python) {
    throw (Get-GeneXusPythonNotFoundMessage)
}
$pythonExe = $python.Source
$pythonArgs = [string[]]$python.PrefixArguments

$basePath = Get-GeneXusObjectTypeCatalogDefaultBasePath
$base = Read-GeneXusObjectTypeCatalogFile -Path $basePath
$workWith = $base.types.WorkWith
$workWithForWeb = $base.types.WorkWithForWeb
$procedure = $base.types.Procedure

# Without an override.
$emptyRoot = New-CaseRoot 'empty'
$r = Invoke-Reminder -Root $emptyRoot
Assert-True ($r.status -eq 'OK' -and -not $r.noticeRequired) 'without an override, should be OK'

# Identical redundant, but without a local exportTaskLabel: cleanup, no effective pending, base exportTaskLabel preserved.
$redundantRoot = New-CaseRoot 'redundant'
$overridePath = Join-Path $redundantRoot 'scripts/gx-object-type-catalog.override.json'
Write-JsonFile -Path $overridePath -Value ([ordered]@{
    schemaVersion = 1
    upstreamPending = $true
    types = [ordered]@{
        WorkWith = [ordered]@{
            objectTypeGuid = $workWith.objectTypeGuid
            rootKind = $workWith.rootKind
            folderName = $workWith.folderName
            inventoryEligible = $workWith.inventoryEligible
            queryableByKbIntelligence = $workWith.queryableByKbIntelligence
            containerType = $workWith.containerType
            notes = 'metadata only for local evidence'
            evidenceSummary = 'local evidence must not affect runtime catalog'
        }
    }
})
$r = Invoke-Reminder -Root $redundantRoot
Assert-True ($r.status -eq 'CLEANUP_RECOMMENDED') 'redundant should recommend cleanup'
Assert-True (-not $r.effectiveUpstreamPending -and $r.declaredUpstreamPending) 'a declared pending must not become an effective pending when redundant'
Assert-True ($r.redundantTypeNames -contains 'WorkWith' -and $r.pendingTypeNames.Count -eq 0) 'WorkWith should be redundant, not pending'
$res = Resolve-GeneXusObjectTypeCatalogPaths -KbWorkspaceRoot $redundantRoot
Assert-True ($res.UpstreamPending -eq $false -and $res.DeclaredUpstreamPending -eq $true -and $res.EffectiveUpstreamPending -eq $false) 'pending aliases should reflect effective/declared'
Assert-True ($res.MergedCatalog.types.WorkWith.exportTaskLabel -eq $workWith.exportTaskLabel) 'merge should preserve the base exportTaskLabel'
Assert-True ($res.MergedCatalog.types.WorkWith.canonicalType -eq 'WorkWith') 'canonicalType should be derived'
Assert-True ($res.MergedCatalog.types.WorkWith.notes -eq $workWith.notes) 'local metadata must not overwrite base metadata in the effective catalog'
Assert-True ($null -eq $res.MergedCatalog.types.WorkWith.PSObject.Properties['evidenceSummary']) 'local metadata must not enter the effective catalog'

# Genuinely pending.
$pendingRoot = New-CaseRoot 'pending'
Write-JsonFile -Path (Join-Path $pendingRoot 'scripts/gx-object-type-catalog.override.json') -Value ([ordered]@{
    schemaVersion = 1
    upstreamPending = $true
    types = [ordered]@{
        LocalOnlyType = [ordered]@{
            objectTypeGuid = '11111111-2222-3333-4444-555555555555'
            rootKind = 'Object'
            folderName = 'LocalOnlyType'
            inventoryEligible = $true
            queryableByKbIntelligence = $true
            containerType = $false
        }
    }
})
$r = Invoke-Reminder -Root $pendingRoot
Assert-True ($r.status -eq 'REMINDER_REQUIRED' -and $r.pendingTypeNames -contains 'LocalOnlyType') 'missing type should be pending'

# Ordinary divergent.
$divRoot = New-CaseRoot 'divergent'
Write-JsonFile -Path (Join-Path $divRoot 'scripts/gx-object-type-catalog.override.json') -Value ([ordered]@{
    schemaVersion = 1
    upstreamPending = $true
    types = [ordered]@{
        Procedure = [ordered]@{
            objectTypeGuid = $procedure.objectTypeGuid
            rootKind = $procedure.rootKind
            folderName = $procedure.folderName
            inventoryEligible = $procedure.inventoryEligible
            queryableByKbIntelligence = (-not [bool]$procedure.queryableByKbIntelligence)
            containerType = $procedure.containerType
        }
    }
})
$r = Invoke-Reminder -Root $divRoot
Assert-True ($r.status -eq 'REMINDER_REQUIRED' -and $r.divergentTypeNames -contains 'Procedure') 'divergent field should be divergent'
Assert-True (@($r.classificationEntries[0].divergentFields) -contains 'queryableByKbIntelligence') 'divergent field should be named'

# Identity divergent.
$identityRoot = New-CaseRoot 'identity-divergent'
Write-JsonFile -Path (Join-Path $identityRoot 'scripts/gx-object-type-catalog.override.json') -Value ([ordered]@{
    schemaVersion = 1
    upstreamPending = $true
    types = [ordered]@{
        Procedure = [ordered]@{
            objectTypeGuid = $procedure.objectTypeGuid
            rootKind = $procedure.rootKind
            folderName = 'ProcedureX'
            inventoryEligible = $procedure.inventoryEligible
            queryableByKbIntelligence = $procedure.queryableByKbIntelligence
            containerType = $procedure.containerType
        }
    }
})
$r = Invoke-Reminder -Root $identityRoot
Assert-True ($r.status -eq 'OVERRIDE_RESOLUTION_BLOCKED' -and $r.reason -eq 'unsafe-identity-divergence') 'divergent identity field should block resolution'
Assert-True ($r.diagnosticReason -eq 'identity-field-divergence' -and $r.fieldPath -eq 'types.Procedure.folderName') 'identity block should point at the divergent field'
Assert-True ($r.blockedTypeNames -contains 'Procedure') 'type with a divergent identity should appear in blockedTypeNames'

# Metadata-only / empty types.
$metaRoot = New-CaseRoot 'metadata'
Write-JsonFile -Path (Join-Path $metaRoot 'scripts/gx-object-type-catalog.override.json') -Value ([ordered]@{ schemaVersion = 1; upstreamPending = $true; notes = 'legacy root metadata' })
$r = Invoke-Reminder -Root $metaRoot
Assert-True ($r.status -eq 'CLEANUP_RECOMMENDED' -and -not $r.effectiveUpstreamPending) 'metadata-only should be cleanup with no effective pending'

# Invalid shape.
$invalidRoot = New-CaseRoot 'invalid'
$invalidOverridePath = Join-Path $invalidRoot 'scripts/gx-object-type-catalog.override.json'
[IO.File]::WriteAllText($invalidOverridePath, '{"upstreamPending":"yes","types":{}}', (Get-Utf8NoBomEncoding))
$r = Invoke-Reminder -Root $invalidRoot
Assert-True ($r.status -eq 'INVALID_OVERRIDE_SHAPE' -and $r.diagnosticReason -eq 'upstream-pending-not-boolean') 'invalid upstreamPending should be an invalid shape'

$registerOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'Register-GeneXusObjectTypeCatalogOverride.ps1') -KbWorkspaceRoot $invalidRoot -TypeName 'LocalInvalid' -ObjectTypeGuid '22222222-3333-4444-5555-666666666666' -UserApproved -AsJson
$registerExit = $LASTEXITCODE
Assert-True ($registerExit -eq 2) 'registering over an invalid override should exit with code 2'
$registerResult = $registerOut | ConvertFrom-Json
Assert-True ($registerResult.status -eq 'INVALID_OVERRIDE_SHAPE' -and $registerResult.blocked) 'registration should return a structured diagnostic for an existing invalid override'

# Registering a base type copies its flags (queryableByKbIntelligence, inventoryEligible,
# containerType) from the base, so the candidate is redundant and blocked whatever the base
# flags are: WorkWith and Folder are queryableByKbIntelligence=false, Folder is a container.
foreach ($redundantTypeName in @('WorkWith', 'WorkWithForWeb', 'Folder')) {
    $redundantBase = $base.types.$redundantTypeName
    $redundantRegisterRoot = New-BareRoot "register-redundant-$redundantTypeName"
    $redundantRegisterOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'Register-GeneXusObjectTypeCatalogOverride.ps1') -KbWorkspaceRoot $redundantRegisterRoot -TypeName $redundantTypeName -ObjectTypeGuid $redundantBase.objectTypeGuid -FolderName $redundantBase.folderName -UserApproved -AsJson
    $redundantRegisterExit = $LASTEXITCODE
    Assert-True ($redundantRegisterExit -eq 2) "redundant registration of $redundantTypeName should exit with code 2; got $redundantRegisterExit"
    $redundantRegisterResult = $redundantRegisterOut | ConvertFrom-Json
    Assert-True ($redundantRegisterResult.status -eq 'LOCAL_OVERRIDE_REDUNDANT_BLOCKED' -and $redundantRegisterResult.blocked) "redundant registration of $redundantTypeName should block with a specific status; got $($redundantRegisterResult.status)"
    Assert-True ($redundantRegisterResult.baseTypeName -eq $redundantTypeName -and $redundantRegisterResult.diagnosticReason -eq 'equivalent') "redundant registration of $redundantTypeName should point at equivalence with the base"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $redundantRegisterRoot 'scripts') -PathType Container)) "redundant registration of $redundantTypeName should not create scripts before blocking"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $redundantRegisterRoot 'scripts/gx-object-type-catalog.override.json') -PathType Leaf)) "redundant registration of $redundantTypeName should not write the override nor re-stamp the pending flag"
}

# A type missing from the base keeps the documented default flags (queryable, inventory, not a container).
$newTypeRegisterRoot = New-BareRoot 'register-new-type'
$newTypeRegisterOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'Register-GeneXusObjectTypeCatalogOverride.ps1') -KbWorkspaceRoot $newTypeRegisterRoot -TypeName 'LocalNewType' -ObjectTypeGuid '33333333-4444-5555-6666-777777777777' -UserApproved -AsJson
Assert-True ($LASTEXITCODE -eq 0) "registering a type missing from the base should exit 0; got $LASTEXITCODE"
$newTypeOverride = Get-Content -LiteralPath (Join-Path $newTypeRegisterRoot 'scripts/gx-object-type-catalog.override.json') -Raw | ConvertFrom-Json
$newTypeEntry = $newTypeOverride.types.LocalNewType
Assert-True ($newTypeEntry.queryableByKbIntelligence -eq $true -and $newTypeEntry.inventoryEligible -eq $true -and $newTypeEntry.containerType -eq $false) 'a type missing from the base should keep the default flags'

$shadowRegisterRoot = New-BareRoot 'register-shadow'
$shadowRegisterOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'Register-GeneXusObjectTypeCatalogOverride.ps1') -KbWorkspaceRoot $shadowRegisterRoot -TypeName 'Attribute' -ObjectTypeGuid 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -FolderName 'Attribute' -UserApproved -AsJson
$shadowRegisterExit = $LASTEXITCODE
Assert-True ($shadowRegisterExit -eq 2) 'registration with unsafe shadowing should exit with code 2'
$shadowRegisterResult = $shadowRegisterOut | ConvertFrom-Json
Assert-True ($shadowRegisterResult.status -eq 'LOCAL_OVERRIDE_UNSAFE_SHADOWING_BLOCKED' -and $shadowRegisterResult.reason -eq 'unsafe-shadowing') 'registration with unsafe shadowing should block with a specific status'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $shadowRegisterRoot 'scripts') -PathType Container)) 'registration with unsafe shadowing should not create scripts before blocking'

$duplicateRegisterRoot = New-BareRoot 'register-duplicate-guid'
$duplicateRegisterOut = & pwsh -NoProfile -File (Join-Path $scriptDir 'Register-GeneXusObjectTypeCatalogOverride.ps1') -KbWorkspaceRoot $duplicateRegisterRoot -TypeName 'WorkWith' -ObjectTypeGuid $procedure.objectTypeGuid -FolderName $workWith.folderName -UserApproved -AsJson
$duplicateRegisterExit = $LASTEXITCODE
Assert-True ($duplicateRegisterExit -eq 2) 'registration with an unsafe duplicate GUID should exit with code 2'
$duplicateRegisterResult = $duplicateRegisterOut | ConvertFrom-Json
Assert-True ($duplicateRegisterResult.status -eq 'LOCAL_OVERRIDE_UNSAFE_DUPLICATE_GUID_BLOCKED' -and $duplicateRegisterResult.reason -eq 'unsafe-duplicate-guid') 'registration with an unsafe duplicate GUID should block with a specific status'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $duplicateRegisterRoot 'scripts') -PathType Container)) 'registration with an unsafe duplicate GUID should not create scripts before blocking'

$invalidSourceRoot = Join-Path $invalidRoot 'KbObjectsXml'
[void](New-Item -ItemType Directory -Path $invalidSourceRoot -Force)
$buildOut = & $pythonExe @pythonArgs (Join-Path $scriptDir 'Build-KbIntelligenceIndex.py') --source-root $invalidSourceRoot --output-path (Join-Path $invalidRoot 'index.sqlite') --catalog-override-path $invalidOverridePath
$buildExit = $LASTEXITCODE
Assert-True ($buildExit -eq 2) 'index build should block an invalid override with code 2'
Assert-True (-not (($buildOut -join "`n") -match 'Traceback')) 'index build must not emit a traceback for an invalid override'
$buildResult = $buildOut | ConvertFrom-Json
Assert-True ($buildResult.status -eq 'INVALID_OVERRIDE_SHAPE' -and $buildResult.blocked) 'index build should return structured JSON for an invalid override'

$queryIndexPath = Join-Path $invalidRoot 'empty.sqlite'
[IO.File]::WriteAllBytes($queryIndexPath, [byte[]]@())
$queryOut = & $pythonExe @pythonArgs (Join-Path $scriptDir 'Query-KbIntelligenceIndex.py') --index-path $queryIndexPath --query who-uses --object-type Procedure --object-name Foo --catalog-override-path $invalidOverridePath
$queryExit = $LASTEXITCODE
Assert-True ($queryExit -eq 2) 'semantic query should block an invalid override with code 2'
Assert-True (-not (($queryOut -join "`n") -match 'Traceback')) 'semantic query must not emit a traceback for an invalid override'
$queryResult = $queryOut | ConvertFrom-Json
Assert-True ($queryResult.status -eq 'INVALID_OVERRIDE_SHAPE' -and $queryResult.blocked) 'semantic query should return structured JSON for an invalid override'

# Unsafe shadowing and duplicate GUID.
$shadowRoot = New-CaseRoot 'shadow'
Write-JsonFile -Path (Join-Path $shadowRoot 'scripts/gx-object-type-catalog.override.json') -Value ([ordered]@{ types = [ordered]@{ Attribute = [ordered]@{ objectTypeGuid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; rootKind='Attribute'; folderName='Attribute'; inventoryEligible=$true; queryableByKbIntelligence=$true; containerType=$false } } })
$r = Invoke-Reminder -Root $shadowRoot
Assert-True ($r.status -eq 'OVERRIDE_RESOLUTION_BLOCKED' -and $r.reason -eq 'unsafe-shadowing') 'Attribute with a GUID should block on shadowing'

$dupRoot = New-CaseRoot 'dupguid'
Write-JsonFile -Path (Join-Path $dupRoot 'scripts/gx-object-type-catalog.override.json') -Value ([ordered]@{ types = [ordered]@{ ProcedureAlias = [ordered]@{ objectTypeGuid=$procedure.objectTypeGuid; rootKind=$procedure.rootKind; folderName=$procedure.folderName; inventoryEligible=$procedure.inventoryEligible; queryableByKbIntelligence=$procedure.queryableByKbIntelligence; containerType=$procedure.containerType } } })
$r = Invoke-Reminder -Root $dupRoot
Assert-True ($r.status -eq 'CLEANUP_RECOMMENDED' -and $r.redundantTypeNames -contains 'ProcedureAlias' -and $r.classificationEntries[0].baseTypeName -eq 'Procedure') 'alias by equivalent GUID should be redundant'
Assert-True (-not (Resolve-GeneXusObjectTypeCatalogPaths -KbWorkspaceRoot $dupRoot).MergedCatalog.types.PSObject.Properties['ProcedureAlias']) 'redundant alias must not create a new effective type'

# Textual CLI should distinguish cleanup from the absence of an override.
$textReminder = & pwsh -NoProfile -File (Join-Path $scriptDir 'Test-MimirCatalogOverrideSessionReminder.ps1') -KbWorkspaceRoot $redundantRoot
Assert-True (($textReminder -join "`n") -match 'CLEANUP_RECOMMENDED') 'redundant textual output should recommend cleanup'
Assert-True (-not (($textReminder -join "`n") -match 'no local catalog override')) 'redundant textual output must not say there is no active override'
$textNoOverride = & pwsh -NoProfile -File (Join-Path $scriptDir 'Test-MimirCatalogOverrideSessionReminder.ps1') -KbWorkspaceRoot $emptyRoot
Assert-True (($textNoOverride -join "`n") -match 'OK: no local catalog override active\.') 'textual output without an override should say so in English'

# Python parity: redundant, invalid operational fields, and divergence reason.
$py = @"
from pathlib import Path
from GeneXusObjectTypeCatalogCore import classify_gx_object_type_catalog_override, load_gx_object_type_catalog, resolve_effective_object_type_catalog
cat, override = resolve_effective_object_type_catalog(Path(r'$redundantRoot') / 'KbObjectsXml', kb_workspace_root=Path(r'$redundantRoot'))
base = load_gx_object_type_catalog()
assert cat['types']['WorkWith']['exportTaskLabel'] == '$($workWith.exportTaskLabel)'
assert 'canonicalType' in cat['types']['WorkWith']
assert cat['types']['WorkWith']['notes'] == base['types']['WorkWith']['notes']
assert 'evidenceSummary' not in cat['types']['WorkWith']
proc = dict(base['types']['Procedure'])
bool_string = {'schemaVersion': 1, 'upstreamPending': True, 'types': {'Procedure': dict(proc, queryableByKbIntelligence='false')}}
r = classify_gx_object_type_catalog_override(base, bool_string, Path('override.json'))
assert r['status'] == 'INVALID_OVERRIDE_SHAPE' and r['diagnosticReason'] == 'field-not-boolean', r
bad_guid = {'schemaVersion': 1, 'upstreamPending': True, 'types': {'Procedure': dict(proc, objectTypeGuid='not-a-guid')}}
r = classify_gx_object_type_catalog_override(base, bad_guid, Path('override.json'))
assert r['status'] == 'INVALID_OVERRIDE_SHAPE' and r['diagnosticReason'] == 'invalid-guid', r
divergent_only = {'schemaVersion': 1, 'upstreamPending': True, 'types': {'Procedure': dict(proc, folderName='ProcedureX')}}
r = classify_gx_object_type_catalog_override(base, divergent_only, Path('override.json'))
assert r['status'] == 'OVERRIDE_RESOLUTION_BLOCKED' and r['reason'] == 'unsafe-identity-divergence' and r['diagnosticReason'] == 'identity-field-divergence', r
"@
$env:PYTHONPATH = $scriptDir
$py | & $pythonExe @pythonArgs -
if($LASTEXITCODE -ne 0){ throw 'Python parity failed for override classification' }

Write-Output 'OK: Test-MimirCatalogOverrideClassificationSelfTest.ps1'
exit 0
