#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for the catalog (layer 1) and usage tracking (layer 2) of CSS classes in KbIntelligence.

.DESCRIPTION
    Builds a synthetic KB covering the matrix: legacy ThemeClass (with a :hover case and inheritance),
    authored DesignSystem (with a redeclaration inside @media and /* */ and // comments), PackagedModule
    (nested DesignSystem, imported class), and a WebPanel exercising the 7 usage forms
    (static layout, multiple classes, single/double-quote literals, StyleClass:/ThemeClass: prefixes,
    dynamic variable, dynamic Format(), commented-out line) plus a class that is used but not catalogued.
    Builds the index, validates relation cases, and checks the css-classes and css-class-usage queries.
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-css-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$themeClassDir = Join-Path $kbObjectsPath 'ThemeClass'
$designSystemDir = Join-Path $kbObjectsPath 'DesignSystem'
$packagedModuleDir = Join-Path $kbObjectsPath 'PackagedModule'
$webPanelDir = Join-Path $kbObjectsPath 'WebPanel'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $themeClassDir, $designSystemDir, $packagedModuleDir, $webPanelDir, $kbIntelDir -Force)

# --- Legacy ThemeClass ---
$legacyButtonXml = @'
<Object type="d4876646-98dd-419b-8c1c-896f83c48368" name="LegacyButton" guid="11111111-0000-0000-0000-000000000001">
  <Properties>
    <Property><Name>Name</Name><Value>LegacyButton</Value></Property>
  </Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $themeClassDir 'LegacyButton.xml'), $legacyButtonXml, $enc)

# :hover case — the filesystem corrupts ':' into '_' in the file name; the real Name has ':'.
$legacyHoverXml = @'
<Object type="d4876646-98dd-419b-8c1c-896f83c48368" name="LegacyHover:hover" guid="11111111-0000-0000-0000-000000000002">
  <Properties>
    <Property><Name>Name</Name><Value>LegacyHover:hover</Value></Property>
  </Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $themeClassDir 'LegacyHover_hover.xml'), $legacyHoverXml, $enc)

# Inheritance — parent points to another ThemeClass.
$legacyChildXml = @'
<Object type="d4876646-98dd-419b-8c1c-896f83c48368" name="LegacyChild" guid="11111111-0000-0000-0000-000000000003" parent="LegacyButton">
  <Properties>
    <Property><Name>Name</Name><Value>LegacyChild</Value></Property>
  </Properties>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $themeClassDir 'LegacyChild.xml'), $legacyChildXml, $enc)

# --- Authored DesignSystem: Styles part (GUID c6b14574); @media redeclares .Responsive; comments do not count. ---
$designSystemXml = @'
<Object type="78b3fa0e-174c-4b2b-8716-718167a428b5" name="dsTest" guid="22222222-0000-0000-0000-000000000001">
  <Part type="75e52d99-6edd-4bad-a1d7-dcc9b7f000ef">
    <Source><![CDATA[tokens Name {
  #colors { primary: #000; }
}]]></Source>
  </Part>
  <Part type="c6b14574-4f5f-4e35-aaa7-e322e88a9a10">
    <Source><![CDATA[Styles dsTest
{
  .PanelTitle { color: #000; }
  .card-basico { padding: 4px; }
  .Responsive { width: 100%; }
  @media (max-width: 1199px) {
    .Responsive { width: 50%; }
  }
  /* .CommentedBlock { color: red; } */
  // .CommentedLine { color: blue; }
}]]></Source>
  </Part>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $designSystemDir 'dsTest.xml'), $designSystemXml, $enc)

# --- PackagedModule: nested DesignSystem (same Styles part GUID); imported class. ---
$packagedModuleXml = @'
<Object type="c88fffcd-b6f8-0000-8fec-00b5497e2117" name="PkgMod" guid="33333333-0000-0000-0000-000000000001">
  <Module>
    <Object type="78b3fa0e-174c-4b2b-8716-718167a428b5" name="NestedDS" guid="33333333-0000-0000-0000-000000000002">
      <Part type="c6b14574-4f5f-4e35-aaa7-e322e88a9a10">
        <Source><![CDATA[Styles NestedDS
{
  .ImportedThing { color: green; }
}]]></Source>
      </Part>
    </Object>
  </Module>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $packagedModuleDir 'PkgMod.xml'), $packagedModuleXml, $enc)

# --- WebPanel: 7 usage forms + an uncatalogued class (UncatalProof). ---
$webPanelXml = @'
<Object type="c9584656-94b6-4ccd-890f-332d11fc2c25" name="wpTest" guid="44444444-0000-0000-0000-000000000001">
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Layout><Table class="PanelTitle"><Cell class="card-basico PanelTitle" cellClass="FormCell" /><Cell class="UncatalProof" GxObjClass="13" /></Table></Layout>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[
&v1.Class = "PanelTitle"
&v2.Class = 'card-basico'
&v3.Class = 'card-basico PanelTitle'
&v4.Class = StyleClass:PanelTitle
&v5.Class = ThemeClass:LegacyButton
&v6.Class = &someVar
&v7.Class = Format("x-%1", &t)
// &v8.Class = "ShouldBeIgnored"
]]></Source>
  </Part>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $webPanelDir 'wpTest.xml'), $webPanelXml, $enc)

# --- Validation cases (relations) ---
$validationCasesPath = Join-Path $kbIntelDir 'css-validation.json'
$validationCasesJson = @'
{
  "cases": [
    { "id": "layout-static-resolves", "source": "WebPanel:wpTest", "target": "CssClass:PanelTitle", "expected_rule": "css_layout_class_attribute", "should_exist": true },
    { "id": "layout-uncatalogued-still-tracked", "source": "WebPanel:wpTest", "target": "CssClass:UncatalProof", "expected_rule": "css_layout_class_attribute", "should_exist": true },
    { "id": "layout-cellclass-tracked", "source": "WebPanel:wpTest", "target": "CssClass:FormCell", "expected_rule": "css_layout_class_attribute", "should_exist": true },
    { "id": "layout-gxobjclass-numeric-ignored", "source": "WebPanel:wpTest", "target": "CssClass:13", "expected_rule": "css_layout_class_attribute", "should_exist": false },
    { "id": "event-literal-single-quote", "source": "WebPanel:wpTest", "target": "CssClass:card-basico", "expected_rule": "css_event_class_assignment", "should_exist": true },
    { "id": "event-themeclass-prefix", "source": "WebPanel:wpTest", "target": "CssClass:LegacyButton", "expected_rule": "css_event_class_assignment", "should_exist": true },
    { "id": "event-styleclass-prefix", "source": "WebPanel:wpTest", "target": "CssClass:PanelTitle", "expected_rule": "css_event_class_assignment", "should_exist": true },
    { "id": "commented-line-ignored", "source": "WebPanel:wpTest", "target": "CssClass:ShouldBeIgnored", "expected_rule": "css_event_class_assignment", "should_exist": false }
  ]
}
'@
[System.IO.File]::WriteAllText($validationCasesPath, $validationCasesJson, $enc)

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
$indexScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'

& $indexScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -ValidationCasesPath $validationCasesPath `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
if ($LASTEXITCODE -ne 0) {
    throw "Build-KbIntelligenceIndex failed in the CSS classes self-test; exit $LASTEXITCODE"
}

$report = Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failed = @($report.cases | Where-Object { $_.status -ne 'passed' })
if ($failed.Count -gt 0) {
    throw "Relation validation cases failed: $($failed.id -join ', ')"
}

$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.py'

function Invoke-CssQuery {
    param([string[]]$QueryArgs)
    $out = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath @QueryArgs --format json
    if ($LASTEXITCODE -ne 0) {
        throw "Query failed (args: $($QueryArgs -join ' ')); exit $LASTEXITCODE"
    }
    return ($out | ConvertFrom-Json)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

# --- css-classes: default view (kb-authored only) ---
$catalog = Invoke-CssQuery -QueryArgs @('--query', 'css-classes')
$byName = @{}
foreach ($row in $catalog.results) { $byName[$row.class_name] = $row }

Assert-True ($byName.ContainsKey('PanelTitle')) 'PanelTitle should be in the catalog (design-system)'
Assert-True ($byName['PanelTitle'].model -eq 'design-system') 'PanelTitle should be model=design-system'
Assert-True ($byName.ContainsKey('card-basico')) 'card-basico (with a hyphen) should be in the catalog'
Assert-True ($byName.ContainsKey('Responsive')) 'Responsive should be in the catalog'
$respCount = @($catalog.results | Where-Object { $_.class_name -eq 'Responsive' }).Count
Assert-True ($respCount -eq 1) "Responsive should appear once (dedup of @media), appeared $respCount"
Assert-True (-not $byName.ContainsKey('CommentedBlock')) 'CommentedBlock (/* */) must NOT be catalogued'
Assert-True (-not $byName.ContainsKey('CommentedLine')) 'CommentedLine (//) must NOT be catalogued'

Assert-True ($byName.ContainsKey('LegacyButton')) 'LegacyButton should be in the catalog (legacy-theme)'
Assert-True ($byName['LegacyButton'].model -eq 'legacy-theme') 'LegacyButton should be model=legacy-theme'
Assert-True ([bool]$byName['LegacyButton'].deprecated) 'LegacyButton (legacy) should be deprecated=true'
Assert-True ($byName.ContainsKey('LegacyHover:hover')) 'Legacy class should use the Name (LegacyHover:hover), not the stem'
Assert-True (-not $byName.ContainsKey('LegacyHover_hover')) 'The corrupted stem (LegacyHover_hover) must NOT become a class name'
Assert-True ($byName.ContainsKey('LegacyChild')) 'LegacyChild should be in the catalog'
Assert-True ($byName['LegacyChild'].parent_class -eq 'LegacyButton') 'LegacyChild should record parent_class=LegacyButton'

Assert-True (-not $byName.ContainsKey('ImportedThing')) 'ImportedThing (packaged-module) must NOT appear in the default view'

# --- css-classes: including imported ones ---
$catalogImported = Invoke-CssQuery -QueryArgs @('--query', 'css-classes', '--include-imported')
$importedRow = @($catalogImported.results | Where-Object { $_.class_name -eq 'ImportedThing' })
Assert-True ($importedRow.Count -eq 1) 'ImportedThing should appear with --include-imported'
Assert-True ($importedRow[0].origin -eq 'packaged-module') 'ImportedThing should be origin=packaged-module'

# --- css-class-usage: by class ---
$usage = Invoke-CssQuery -QueryArgs @('--query', 'css-class-usage', '--object-name', 'PanelTitle')
Assert-True ([bool]$usage.found_in_catalog) 'PanelTitle should be found_in_catalog=true'
Assert-True ($usage.resolvable_uses_total -ge 2) "PanelTitle should have >=2 resolvable uses, had $($usage.resolvable_uses_total)"
Assert-True ($usage.dynamic_uses_total -ge 2) "There should be >=2 dynamic assignments (&someVar and Format), had $($usage.dynamic_uses_total)"

# --- css-class-usage: overview with a class that is used but not catalogued ---
$overview = Invoke-CssQuery -QueryArgs @('--query', 'css-class-usage')
Assert-True ($overview.used_but_uncatalogued -contains 'UncatalProof') 'UncatalProof should appear in used_but_uncatalogued'

Write-Output 'OK: Test-KbIntelligenceCssClassExtractionSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
