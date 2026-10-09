#requires -Version 7.4
<#
.SYNOPSIS
    Minimal self-test for extracting calls in an Attribute's Property Formula in KbIntelligence.
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

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
$utf8NoBomEncodingSupportPath = Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath
$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-attr-formula-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$procedureDir = Join-Path $kbObjectsPath 'Procedure'
$attributeDir = Join-Path $kbObjectsPath 'Attribute'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $procedureDir, $attributeDir, $kbIntelDir -Force)

$procCalleeXml = @"
<Object type="$procedureGuid" name="procFormulaCallee" guid="11111111-1111-1111-1111-111111111101">
  <Source><![CDATA[]]></Source>
</Object>
"@
[System.IO.File]::WriteAllText((Join-Path $procedureDir 'procFormulaCallee.xml'), $procCalleeXml, (Get-Utf8NoBomEncoding))

$attrDirectXml = @"
<Attribute name="AttrCalcFormula" guid="22222222-2222-2222-2222-222222222201">
  <Properties>
    <Property><Name>Formula</Name><Value>procFormulaCallee(0)</Value></Property>
  </Properties>
</Attribute>
"@
$attrDotCallXml = @"
<Attribute name="AttrCalcFormulaDotCall" guid="22222222-2222-2222-2222-222222222202">
  <Properties>
    <Property><Name>Formula</Name><Value>procFormulaCallee.Call(0)</Value></Property>
  </Properties>
</Attribute>
"@
$attrPlainXml = @"
<Attribute name="AttrPlain" guid="22222222-2222-2222-2222-222222222203">
  <Properties>
    <Property><Name>idBasedOn</Name><Value>Domain:Character</Value></Property>
  </Properties>
</Attribute>
"@
[System.IO.File]::WriteAllText((Join-Path $attributeDir 'AttrCalcFormula.xml'), $attrDirectXml, (Get-Utf8NoBomEncoding))
[System.IO.File]::WriteAllText((Join-Path $attributeDir 'AttrCalcFormulaDotCall.xml'), $attrDotCallXml, (Get-Utf8NoBomEncoding))
[System.IO.File]::WriteAllText((Join-Path $attributeDir 'AttrPlain.xml'), $attrPlainXml, (Get-Utf8NoBomEncoding))

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
$validationCases = Join-Path $fixturesRoot 'kb-intelligence-attribute-formula.validation-extraction.json'
$indexScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'

& $indexScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -ValidationCasesPath $validationCases `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
if ($LASTEXITCODE -ne 0) {
    throw "Build-KbIntelligenceIndex failed in the Formula self-test; exit $LASTEXITCODE"
}

$report = Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failed = @($report.cases | Where-Object { $_.status -ne 'passed' })
if ($failed.Count -gt 0) {
    throw "Validation cases failed: $($failed.id -join ', ')"
}

$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.py'
$whoUsesJson = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query who-uses --object-type Procedure --object-name procFormulaCallee --format json
if ($LASTEXITCODE -ne 0) {
    throw "who-uses failed; exit $LASTEXITCODE"
}
$whoUses = $whoUsesJson | ConvertFrom-Json
$attributeSources = @(
    $whoUses.results |
        Where-Object { $_.source_type -eq 'Attribute' } |
        ForEach-Object { "$($_.source_type):$($_.source_name)" }
)
if ($attributeSources.Count -lt 2) {
    throw "who-uses of procFormulaCallee should list at least 2 Attributes; got: $($attributeSources -join ', ')"
}

Write-Output 'OK: Test-KbIntelligenceAttributeFormulaExtractionSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
