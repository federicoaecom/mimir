#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for extracting Pattern-generated objects (IsGeneratedObject / PatternObjectId /
    InstanceKey) in KbIntelligence and the --generated/--authored filter.

.DESCRIPTION
    Builds a synthetic KB covering the converged design matrix:
      - generated WebPanel (flag + companion fields, with a Part before the root Properties);
      - authored WebPanel (no marker -> 0);
      - MALFORMED WebPanel (invalid XML -> regex FALLBACK path; flag + PatternObjectId in the root block);
      - divergent Procedure (flag WITHOUT companion fields, the ListPrograms case);
      - CONTAINER PackagedModule (flag on a NESTED <Object> under <Part><ExportFile>; authored root -> 0,
        guards against the whole-file extraction gap).
    Builds the index and checks object-info (JSON and text), the --generated/--authored filter in the .py
    engine and in the .ps1 wrapper (child process), and the generated_objects_count / schema_version counter in the metadata.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Python 3.8+ resolved once, the same way the KbIntelligence wrappers do it
# (python3, then python, then py -3).
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')
$pythonInterpreter = Get-GeneXusPythonExecutable
if ($null -eq $pythonInterpreter) {
    throw (Get-GeneXusPythonNotFoundMessage)
}

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath
$enc = Get-Utf8NoBomEncoding

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-genobj-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$webPanelDir = Join-Path $kbObjectsPath 'WebPanel'
$procedureDir = Join-Path $kbObjectsPath 'Procedure'
$packagedModuleDir = Join-Path $kbObjectsPath 'PackagedModule'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $webPanelDir, $procedureDir, $packagedModuleDir, $kbIntelDir -Force)

# --- Generated WebPanel: Part (with its own Properties) BEFORE the object-level Properties ---
$wpGeneratedXml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpGenerated" guid="11110000-0000-0000-0000-000000000001">
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Properties><Property><Name>Name</Name><Value>wpGenerated</Value></Property><Property><Name>IsGeneratedObject</Name><Value>True</Value></Property><Property><Name>InstanceKey</Name><Value>78cecefe-be7d-4980-86ce-8d6e91fba04b-WorkWithWebFoo</Value></Property><Property><Name>PatternObjectId</Name><Value>TabGrid</Value></Property></Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $webPanelDir 'wpGenerated.xml'), $wpGeneratedXml, $enc)

# --- Authored WebPanel: root Properties without the marker ---
$wpAuthoredXml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpAuthored" guid="11110000-0000-0000-0000-000000000002">
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Properties><Property><Name>Name</Name><Value>wpAuthored</Value></Property></Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $webPanelDir 'wpAuthored.xml'), $wpAuthoredXml, $enc)

# --- MALFORMED WebPanel: <Table> opened and closed by </Layout> -> ElementTree.ParseError -> FALLBACK ---
$wpMalformedXml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpMalformed" guid="11110000-0000-0000-0000-000000000003">
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Layout><Table class="X"></Layout>
  </Part>
  <Properties><Property><Name>Name</Name><Value>wpMalformed</Value></Property><Property><Name>IsGeneratedObject</Name><Value>True</Value></Property><Property><Name>PatternObjectId</Name><Value>Selection</Value></Property></Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $webPanelDir 'wpMalformed.xml'), $wpMalformedXml, $enc)

# --- Divergent Procedure: flag WITHOUT companion fields (the ListPrograms case) ---
$procDivergentXml = @'
<Object type="84a12160-f59b-4ad7-a683-ea4481ac23e9" name="procDivergent" guid="11110000-0000-0000-0000-000000000004">
  <Properties><Property><Name>Name</Name><Value>procDivergent</Value></Property><Property><Name>IsGeneratedObject</Name><Value>True</Value></Property></Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $procedureDir 'procDivergent.xml'), $procDivergentXml, $enc)

# --- Container PackagedModule: flag on a NESTED <Object>; authored root -> extraction should yield 0 ---
$pkgContainerXml = @'
<Object type="c88fffcd-b6f8-0000-8fec-00b5497e2117" name="pkgContainer" guid="11110000-0000-0000-0000-000000000005">
  <Part type="ed1b7b1c-2aaf-46eb-9ec5-db348f6fa3fc">
    <ExportFile><Objects>
      <Object type="c163e562-42c6-4158-ad83-5b21a14cf30e" name="NestedGen" guid="11110000-0000-0000-0000-000000000006">
        <Properties><Property><Name>Name</Name><Value>NestedGen</Value></Property><Property><Name>IsGeneratedObject</Name><Value>True</Value></Property><Property><Name>PatternObjectId</Name><Value>View</Value></Property><Property><Name>InstanceKey</Name><Value>xxxx-WorkWithWebNested</Value></Property></Properties>
      </Object>
    </Objects></ExportFile>
  </Part>
  <Properties><Property><Name>Name</Name><Value>pkgContainer</Value></Property><Property><Name>ModuleVersion</Name><Value>1.0</Value></Property></Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $packagedModuleDir 'pkgContainer.xml'), $pkgContainerXml, $enc)

# --- Generated WebPanel 2: SAME canonical instance as wpGenerated (grouping by instance) ---
$wpGenerated2Xml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpGenerated2" guid="11110000-0000-0000-0000-000000000007">
  <Properties><Property><Name>Name</Name><Value>wpGenerated2</Value></Property><Property><Name>IsGeneratedObject</Name><Value>True</Value></Property><Property><Name>InstanceKey</Name><Value>78cecefe-be7d-4980-86ce-8d6e91fba04b-WorkWithWebFoo</Value></Property><Property><Name>PatternObjectId</Name><Value>TabTabular</Value></Property></Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $webPanelDir 'wpGenerated2.xml'), $wpGenerated2Xml, $enc)

# --- Generated WebPanel with a NON-CANONICAL InstanceKey (root): instance_name should derive to null ---
$wpOrfaXml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpOrfa" guid="11110000-0000-0000-0000-000000000008">
  <Properties><Property><Name>Name</Name><Value>wpOrfa</Value></Property><Property><Name>IsGeneratedObject</Name><Value>True</Value></Property><Property><Name>InstanceKey</Name><Value>zzzz-WorkWithWebOrfa</Value></Property><Property><Name>PatternObjectId</Name><Value>Selection</Value></Property></Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $webPanelDir 'wpOrfa.xml'), $wpOrfaXml, $enc)

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$indexScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'

& $indexScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
if ($LASTEXITCODE -ne 0) {
    throw "Build-KbIntelligenceIndex failed in the generated-objects self-test; exit $LASTEXITCODE"
}

$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.py'
$queryWrapper = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'

function Invoke-Query {
    param([string[]]$QueryArgs)
    $out = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath @QueryArgs --format json
    if ($LASTEXITCODE -ne 0) {
        throw "Query (.py) failed (args: $($QueryArgs -join ' ')); exit $LASTEXITCODE"
    }
    return ($out | ConvertFrom-Json)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Get-ObjectInfo {
    param([string]$Type, [string]$Name)
    return Invoke-Query -QueryArgs @('--query', 'object-info', '--object-type', $Type, '--object-name', $Name)
}

# --- object-info: correctly scoped extraction for each case ---
$gen = Get-ObjectInfo -Type 'WebPanel' -Name 'wpGenerated'
Assert-True ($gen.object.is_generated_object -eq 1) 'wpGenerated should have is_generated_object=1'
Assert-True ($gen.object.pattern_object_id -eq 'TabGrid') 'wpGenerated should have pattern_object_id=TabGrid'
Assert-True ($gen.object.instance_key -eq '78cecefe-be7d-4980-86ce-8d6e91fba04b-WorkWithWebFoo') 'wpGenerated instance_key is incorrect'

$auth = Get-ObjectInfo -Type 'WebPanel' -Name 'wpAuthored'
Assert-True ($auth.object.is_generated_object -eq 0) 'wpAuthored should have is_generated_object=0'
Assert-True ($null -eq $auth.object.pattern_object_id) 'wpAuthored should have a null pattern_object_id'
Assert-True ($null -eq $auth.object.instance_key) 'wpAuthored should have a null instance_key'

# FALLBACK: malformed XML -> ElementTree fails -> regex extracts from the last root <Properties>
$mal = Get-ObjectInfo -Type 'WebPanel' -Name 'wpMalformed'
Assert-True ($mal.object.is_generated_object -eq 1) 'wpMalformed (fallback) should have is_generated_object=1'
Assert-True ($mal.object.pattern_object_id -eq 'Selection') 'wpMalformed (fallback) should have pattern_object_id=Selection'
Assert-True ($null -eq $mal.object.instance_key) 'wpMalformed should have a null instance_key'

# DIVERGENT: flag without companion fields
$div = Get-ObjectInfo -Type 'Procedure' -Name 'procDivergent'
Assert-True ($div.object.is_generated_object -eq 1) 'procDivergent should have is_generated_object=1'
Assert-True ($null -eq $div.object.pattern_object_id) 'procDivergent should have a null pattern_object_id'
Assert-True ($null -eq $div.object.instance_key) 'procDivergent should have a null instance_key'

# CONTAINER (gap-guard): nested marker must NOT contaminate the root
$pkg = Get-ObjectInfo -Type 'PackagedModule' -Name 'pkgContainer'
Assert-True ($pkg.object.is_generated_object -eq 0) 'pkgContainer (root) should have is_generated_object=0, never inherit from the nested one'
Assert-True ($null -eq $pkg.object.pattern_object_id) 'pkgContainer should have a null pattern_object_id'

# --- --generated / --authored filter in the .py engine (list-by-type WebPanel) ---
$genList = Invoke-Query -QueryArgs @('--query', 'list-by-type', '--object-type', 'WebPanel', '--generated')
$genNames = @($genList.results | ForEach-Object { $_.name })
Assert-True ($genNames -contains 'wpGenerated') '--generated filter should include wpGenerated'
Assert-True ($genNames -contains 'wpMalformed') '--generated filter should include wpMalformed'
Assert-True (-not ($genNames -contains 'wpAuthored')) '--generated filter should NOT include wpAuthored'

$authList = Invoke-Query -QueryArgs @('--query', 'list-by-type', '--object-type', 'WebPanel', '--authored')
$authNames = @($authList.results | ForEach-Object { $_.name })
Assert-True ($authNames -contains 'wpAuthored') '--authored filter should include wpAuthored'
Assert-True (-not ($authNames -contains 'wpGenerated')) '--authored filter should NOT include wpGenerated'

# --- filter via .ps1 WRAPPER (child process) ---
$wrapperOut = & $queryWrapper -IndexPath $sqlitePath -Query 'list-by-type' -ObjectType 'WebPanel' -Generated -Format json
if ($LASTEXITCODE -ne 0) { throw "Wrapper .ps1 -Generated failed; exit $LASTEXITCODE" }
$wrapperGen = ($wrapperOut | ConvertFrom-Json)
$wrapperNames = @($wrapperGen.results | ForEach-Object { $_.name })
Assert-True ($wrapperNames -contains 'wpGenerated') 'wrapper -Generated should include wpGenerated'
Assert-True (-not ($wrapperNames -contains 'wpAuthored')) 'wrapper -Generated should NOT include wpAuthored'

# --- text mode: object-info shows the 3 fields ---
$textOut = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query object-info --object-type WebPanel --object-name wpGenerated --format text
if ($LASTEXITCODE -ne 0) { throw "object-info --format text failed; exit $LASTEXITCODE" }
$textJoined = ($textOut -join "`n")
Assert-True ($textJoined -match 'generated: 1') 'object-info text should show "generated: 1"'
Assert-True ($textJoined -match 'pattern_object_id: TabGrid') 'object-info text should show pattern_object_id: TabGrid'
Assert-True ($textJoined -match 'instance_key: 78cecefe') 'object-info text should show instance_key'

# --- metadata: counter and schema_version ---
$meta = Invoke-Query -QueryArgs @('--query', 'index-metadata')
Assert-True ($meta.metadata.schema_version -eq '5') "schema_version should be 5, was $($meta.metadata.schema_version)"
Assert-True ($meta.metadata.generated_objects_count -eq '5') "generated_objects_count should be 5 (wpGenerated, wpMalformed, procDivergent, wpGenerated2, wpOrfa), was $($meta.metadata.generated_objects_count)"

# ============================================================================
# Reverse lookup by instance: derived instance_name + -InstanceKey filter
# ============================================================================

$fooKey = '78cecefe-be7d-4980-86ce-8d6e91fba04b-WorkWithWebFoo'
$fooKeyUpper = '78CECEFE-BE7D-4980-86CE-8D6E91FBA04B-WorkWithWebFoo'
$fooKeyLower = '78cecefe-be7d-4980-86ce-8d6e91fba04b-workwithwebfoo'

# instance_name derived in object-info (canonical -> name; authored/non-canonical -> null)
$gen1 = Get-ObjectInfo -Type 'WebPanel' -Name 'wpGenerated'
Assert-True ($gen1.object.instance_name -eq 'WorkWithWebFoo') 'wpGenerated should have instance_name=WorkWithWebFoo'
$auth1 = Get-ObjectInfo -Type 'WebPanel' -Name 'wpAuthored'
Assert-True ($null -eq $auth1.object.instance_name) 'wpAuthored should have a null instance_name'
$orfa1 = Get-ObjectInfo -Type 'WebPanel' -Name 'wpOrfa'
Assert-True ($null -eq $orfa1.object.instance_name) 'wpOrfa (non-canonical) should have a null instance_name'

function Get-SearchNames {
    param([string[]]$ExtraArgs)
    $r = Invoke-Query -QueryArgs (@('--query', 'search-objects') + $ExtraArgs)
    # ',@(...)' preserves the array in the return value (avoids unwrapping to $null when empty, under StrictMode).
    return , @($r.results | ForEach-Object { $_.name })
}

# reverse lookup by instance NAME -> the 2 objects of the instance (not authored ones or others)
$byName = Get-SearchNames -ExtraArgs @('--instance-key', 'WorkWithWebFoo')
Assert-True ($byName.Count -eq 2) "reverse lookup by name should have 2 results, had $($byName.Count)"
Assert-True (($byName -contains 'wpGenerated') -and ($byName -contains 'wpGenerated2')) 'reverse lookup by name should contain wpGenerated and wpGenerated2'
Assert-True (-not ($byName -contains 'wpOrfa')) 'reverse lookup by name should NOT contain wpOrfa (different instance)'

# reverse lookup by canonical FULL KEY -> same 2
$byKey = Get-SearchNames -ExtraArgs @('--instance-key', $fooKey)
Assert-True ($byKey.Count -eq 2) 'reverse lookup by full key should have 2 results'

# full key with an UPPERCASE GUID -> same 2 (case-insensitive)
$byKeyUpper = Get-SearchNames -ExtraArgs @('--instance-key', $fooKeyUpper)
Assert-True ($byKeyUpper.Count -eq 2) 'full key with an uppercase GUID should have 2 results (case-insensitive)'

# LOWERCASE full key (lowercase GUID + name) -> same 2 (case-insensitive by key)
$byKeyLower = Get-SearchNames -ExtraArgs @('--instance-key', $fooKeyLower)
Assert-True ($byKeyLower.Count -eq 2) 'lowercase full key should have 2 results (case-insensitive by key)'

# LOWERCASE name -> same 2 (case-insensitive by name)
$byNameLower = Get-SearchNames -ExtraArgs @('--instance-key', 'workwithwebfoo')
Assert-True ($byNameLower.Count -eq 2) 'lowercase name should give the 2 (case-insensitive by name)'

# partial prefix of the name -> zero (exact match, never partial)
$byPartial = Get-SearchNames -ExtraArgs @('--instance-key', 'WorkWithWebFo')
Assert-True ($byPartial.Count -eq 0) 'partial prefix of the name should give zero (exact, not partial)'

# composition with --authored / --generated / --object-type
$byNameAuth = Get-SearchNames -ExtraArgs @('--instance-key', 'WorkWithWebFoo', '--authored')
Assert-True ($byNameAuth.Count -eq 0) 'instance + --authored should give zero'
$byNameGen = Get-SearchNames -ExtraArgs @('--instance-key', 'WorkWithWebFoo', '--generated')
Assert-True ($byNameGen.Count -eq 2) 'instance + --generated should give the 2'
$byNameType = Get-SearchNames -ExtraArgs @('--instance-key', 'WorkWithWebFoo', '--object-type', 'WebPanel')
Assert-True ($byNameType.Count -eq 2) 'instance + --object-type WebPanel should give the 2'

# JSON: instance_filter.mode and instance_name in the results
$byNameFull = Invoke-Query -QueryArgs @('--query', 'search-objects', '--instance-key', 'WorkWithWebFoo')
Assert-True ($byNameFull.instance_filter.mode -eq 'instance-name') 'instance_filter.mode should be instance-name'
Assert-True (@($byNameFull.results | Where-Object { $_.instance_name -eq 'WorkWithWebFoo' }).Count -eq 2) 'results by name should carry instance_name=WorkWithWebFoo'
$byKeyFull = Invoke-Query -QueryArgs @('--query', 'search-objects', '--instance-key', $fooKey)
Assert-True ($byKeyFull.instance_filter.mode -eq 'full-key') 'instance_filter.mode should be full-key'

# non-regression: search by object name (without -InstanceKey) carries instance_name (null for authored)
$byObjName = Invoke-Query -QueryArgs @('--query', 'search-objects', '--object-name', 'wpAuthored')
$authRow = @($byObjName.results | Where-Object { $_.name -eq 'wpAuthored' })[0]
Assert-True ($authRow.PSObject.Properties.Name -contains 'instance_name') 'authored result should have the instance_name field'
Assert-True ($null -eq $authRow.instance_name) 'wpAuthored should have a null instance_name in the search by object name'

# via .ps1 WRAPPER (child process): -InstanceKey forwarded
$wrapInst = & $queryWrapper -IndexPath $sqlitePath -Query 'search-objects' -InstanceKey 'WorkWithWebFoo' -Format json
if ($LASTEXITCODE -ne 0) { throw "wrapper .ps1 -InstanceKey failed; exit $LASTEXITCODE" }
$wrapInstNames = @(($wrapInst | ConvertFrom-Json).results | ForEach-Object { $_.name })
Assert-True ($wrapInstNames.Count -eq 2) 'wrapper -InstanceKey WorkWithWebFoo should give the 2'

# Expected errors: requiredness, scope, key without a name
function Assert-QueryFails {
    param([string[]]$QueryArgs, [string]$Message)
    $null = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath @QueryArgs --format json 2>&1
    if ($LASTEXITCODE -eq 0) { throw "ASSERT FAILED (should have failed): $Message" }
}

Assert-QueryFails -QueryArgs @('--query', 'search-objects') -Message 'search-objects without object-name and without instance-key should fail'
Assert-QueryFails -QueryArgs @('--query', 'list-by-type', '--object-type', 'WebPanel', '--instance-key', 'WorkWithWebFoo') -Message 'list-by-type with --instance-key should fail (out of scope)'
Assert-QueryFails -QueryArgs @('--query', 'search-objects', '--instance-key', '78cecefe-be7d-4980-86ce-8d6e91fba04b-') -Message 'key <GUID>- without a name should fail'
Assert-QueryFails -QueryArgs @('--query', 'who-uses', '--object-type', 'WebPanel', '--object-name', 'wpGenerated', '--instance-key', 'WorkWithWebFoo') -Message 'who-uses (semantic) with --instance-key should fail (out of scope)'

Write-Output 'OK: Test-KbIntelligenceGeneratedObjectExtractionSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
