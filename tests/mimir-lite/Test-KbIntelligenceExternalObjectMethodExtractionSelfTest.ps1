#requires -Version 7.4
<#
.SYNOPSIS
    Minimal self-test for extracting ExternalObject method calls in KbIntelligence.
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

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$externalObjectGuid = 'c163e562-42c6-4158-ad83-5b21a14cf30e'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-external-object-method-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$procedureDir = Join-Path $kbObjectsPath 'Procedure'
$externalObjectDir = Join-Path $kbObjectsPath 'ExternalObject'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $procedureDir, $externalObjectDir, $kbIntelDir -Force)

$externalObjectXml = @"
<Object type="$externalObjectGuid" name="ProgressIndicator" guid="11111111-1111-1111-1111-111111111101">
</Object>
"@
[System.IO.File]::WriteAllText((Join-Path $externalObjectDir 'ProgressIndicator.xml'), $externalObjectXml, (Get-Utf8NoBomEncoding))

$shortProcXml = @"
<Object type="$procedureGuid" name="procExemploAtualiza" guid="22222222-2222-2222-2222-222222222201">
  <Source><![CDATA[]]></Source>
</Object>
"@
$longProcXml = @"
<Object type="$procedureGuid" name="procExemploAtualizaLista" guid="22222222-2222-2222-2222-222222222202">
  <Source><![CDATA[]]></Source>
</Object>
"@
$callerXml = @"
<Object type="$procedureGuid" name="procExemploUsaIndicador" guid="22222222-2222-2222-2222-222222222203">
  <Variables>
    <Variable Name="Progress">
      <Properties>
        <Property><Name>ATTCUSTOMTYPE</Name><Value>exo:ProgressIndicator</Value></Property>
      </Properties>
    </Variable>
  </Variables>
  <Source><![CDATA[
&Progress.Show()
procExemploAtualizaLista()
  ]]></Source>
</Object>
"@
[System.IO.File]::WriteAllText((Join-Path $procedureDir 'procExemploAtualiza.xml'), $shortProcXml, (Get-Utf8NoBomEncoding))
[System.IO.File]::WriteAllText((Join-Path $procedureDir 'procExemploAtualizaLista.xml'), $longProcXml, (Get-Utf8NoBomEncoding))
[System.IO.File]::WriteAllText((Join-Path $procedureDir 'procExemploUsaIndicador.xml'), $callerXml, (Get-Utf8NoBomEncoding))

$validationCasesPath = Join-Path $kbIntelDir 'external-object-method-validation.json'
$validationCasesJson = @'
{
  "cases": [
    {
      "id": "external-object-method-call-resolves-variable-custom-type",
      "source": "Procedure:procExemploUsaIndicador",
      "target": "ExternalObject:ProgressIndicator",
      "expected_rule": "source_external_object_method",
      "should_exist": true
    },
    {
      "id": "procedure-direct-call-keeps-exact-callee",
      "source": "Procedure:procExemploUsaIndicador",
      "target": "Procedure:procExemploAtualizaLista",
      "expected_rule": "procedure_direct_call",
      "should_exist": true
    },
    {
      "id": "procedure-direct-call-does-not-match-substring-callee",
      "source": "Procedure:procExemploUsaIndicador",
      "target": "Procedure:procExemploAtualiza",
      "expected_rule": "procedure_direct_call",
      "should_exist": false
    }
  ]
}
'@
[System.IO.File]::WriteAllText($validationCasesPath, $validationCasesJson, (Get-Utf8NoBomEncoding))

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
    throw "Build-KbIntelligenceIndex failed in the ExternalObject method self-test; exit $LASTEXITCODE"
}

$report = Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failed = @($report.cases | Where-Object { $_.status -ne 'passed' })
if ($failed.Count -gt 0) {
    throw "Validation cases failed: $($failed.id -join ', ')"
}

$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.py'
$whoUsesJson = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query who-uses --object-type ExternalObject --object-name ProgressIndicator --format json
if ($LASTEXITCODE -ne 0) {
    throw "who-uses failed; exit $LASTEXITCODE"
}
$whoUses = $whoUsesJson | ConvertFrom-Json
$methodCallSources = @(
    $whoUses.results |
        Where-Object { $_.source_type -eq 'Procedure' -and $_.source_name -eq 'procExemploUsaIndicador' -and $_.extractor_rule -eq 'source_external_object_method' }
)
if ($methodCallSources.Count -lt 1) {
    throw 'who-uses of ExternalObject:ProgressIndicator should list a source_external_object_method call from Procedure:procExemploUsaIndicador'
}

Write-Output 'OK: Test-KbIntelligenceExternalObjectMethodExtractionSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
