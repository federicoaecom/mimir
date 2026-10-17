#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: formulas relate from the attribute they compute, classic and modern.

.DESCRIPTION
    Builds a synthetic KB with classic Formula objects (folder Formula, type token
    gxlegacy/Formula, <Formula><Name>, <Type>, <Source>) and classic attributes, plus a modern
    attribute whose Formula property names other attributes, and proves that:
      - each attribute named in a classic formula's Source is a use of the computed attribute
        (code_references_attribute, role 'Formula read'), with the line of the formula in its own
        Formula XML file;
      - a call in a classic formula (udp(P...)) relates the computed attribute to the Procedure
        (formula_calls_procedure, rule classic_formula_udp_func);
      - a classic formula whose attribute is not indexed gives no relation;
      - each attribute named in a modern Formula property is a use of that attribute
        ('Formula read'); a called object's name and an &variable are not;
      - for an Attribute target, Attribute is no longer an unextracted attribute-use source on an
        index of extractor 21, and an index rewritten to 20 still lists it as not extracted.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')
. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')
$enc = Get-Utf8NoBomEncoding

$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'
$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-ClassicAttributeXml {
    param([string]$Name)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$Name" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<GXAtt><Attribute><Id>1</Id><Name>$Name</Name><Description>$Name</Description></Attribute></GXAtt>
  </GxLegacyPayload>
</Attribute>
"@
}

function New-ClassicFormulaXml {
    param([string]$Name, [string]$Type, [string]$Source)
    return @"
<Object type="gxlegacy/Formula" name="$Name" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<Formula><Name>$Name</Name><Type>$Type</Type><Source><![CDATA[$Source]]></Source></Formula>
  </GxLegacyPayload>
</Object>
"@
}

function New-ModernAttributeXml {
    param([string]$Name, [string]$Guid, [string]$Formula = '')
    $formulaProperty = if ($Formula) { "<Property><Name>Formula</Name><Value>$Formula</Value></Property>" } else { '' }
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$Name" guid="$Guid" lastUpdate="2026-01-01T00:00:00" description="Synthetic modern attribute">
  <Properties>
    <Property><Name>Name</Name><Value>$Name</Value></Property>
    $formulaProperty
  </Properties>
</Attribute>
"@
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-formula-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
$folders = @{}
foreach ($folder in @('Attribute', 'Formula', 'Procedure')) {
    $folders[$folder] = Join-Path $kbObjectsPath $folder
}
[void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)

function Write-Fixture {
    param([string]$Folder, [string]$Name, [string]$Xml)
    [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
}

foreach ($attributeName in @('LineTotal', 'OrderSubtotal', 'ItemCode', 'OrderDate', 'UnitPrice', 'LineCount')) {
    Write-Fixture 'Attribute' $attributeName (New-ClassicAttributeXml -Name $attributeName)
}
$subtotalFormulaXml = New-ClassicFormulaXml -Name 'OrderSubtotal' -Type 'SUM' -Source 'LineTotal'
Write-Fixture 'Formula' 'OrderSubtotal' $subtotalFormulaXml
Write-Fixture 'Formula' 'UnitPrice' (New-ClassicFormulaXml -Name 'UnitPrice' -Type '' -Source 'udp(PPriceOf, ItemCode, OrderDate)')
Write-Fixture 'Formula' 'NotIndexed' (New-ClassicFormulaXml -Name 'NotIndexed' -Type 'SUM' -Source 'LineTotal')
# A Formula file for LineCount with no <Source>, sorted before the one that has it: the search
# skips it and goes on to CountOfLines.
Write-Fixture 'Formula' 'AaLineCountDraft' @"
<Object type="gxlegacy/Formula" name="AaLineCountDraft" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<Formula><Name>LineCount</Name><Type>COUNT</Type></Formula>
  </GxLegacyPayload>
</Object>
"@
# A vertical formula whose <Type> follows its <Source>, in a file not named after its attribute.
Write-Fixture 'Formula' 'CountOfLines' @"
<Object type="gxlegacy/Formula" name="CountOfLines" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<Formula><Name>LineCount</Name><Source><![CDATA[LineNumber]]></Source><Type>COUNT</Type></Formula>
  </GxLegacyPayload>
</Object>
"@
Write-Fixture 'Procedure' 'PriceOf' @"
<Object type="$procedureGuid" name="PriceOf" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<Procedure><Info><Name>PriceOf</Name></Info></Procedure>
  </GxLegacyPayload>
</Object>
"@

Write-Fixture 'Attribute' 'InvoiceLineAmount' (New-ModernAttributeXml -Name 'InvoiceLineAmount' -Guid '0a000000-0000-4000-8000-000000000001')
Write-Fixture 'Attribute' 'InvoiceDiscount' (New-ModernAttributeXml -Name 'InvoiceDiscount' -Guid '0a000000-0000-4000-8000-000000000002')
Write-Fixture 'Attribute' 'InvoiceTotal' (New-ModernAttributeXml -Name 'InvoiceTotal' -Guid '0a000000-0000-4000-8000-000000000003' -Formula 'sum(InvoiceLineAmount) - InvoiceDiscount if &amp;Apply = 1')
# Attributes named like the formula's called function and its variable: neither is a use.
Write-Fixture 'Attribute' 'Sum' (New-ModernAttributeXml -Name 'Sum' -Guid '0a000000-0000-4000-8000-000000000004')
Write-Fixture 'Attribute' 'Apply' (New-ModernAttributeXml -Name 'Apply' -Guid '0a000000-0000-4000-8000-000000000005')

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
& $buildScript -SourceRoot $kbObjectsPath -OutputPath $sqlitePath -ValidationReportPath $validationPath `
    -FailOnValidationFailure -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete with classic formulas; exit $LASTEXITCODE"

function Invoke-IndexQuery {
    param([string]$Query, [string]$Type, [string]$Name, [string]$IndexPath = $sqlitePath)
    $output = & $queryScript -IndexPath $IndexPath -KbWorkspaceRoot $kbWorkspaceRoot -Query $Query `
        -ObjectType $Type -ObjectName $Name -Format json 2>&1
    $exitCode = $LASTEXITCODE
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($stdout)) {
        throw "ASSERT FAILED: $Query $Type $Name returned no output (exit $exitCode). stderr: $stderr"
    }
    try { $json = $stdout | ConvertFrom-Json }
    catch { throw "ASSERT FAILED: $Query $Type $Name did not return JSON (exit $exitCode). stderr: $stderr" }
    Assert-True ($exitCode -eq 0) "$Query $Type $Name should exit 0; got $exitCode. output: $stdout $stderr"
    return $json
}

function Format-Rows {
    param($Rows)
    return (@($Rows) | ForEach-Object { "$($_.source_type) $($_.source_name) $($_.relation_kind) [$($_.evidence_role)] line $($_.line) $($_.source_file)" }) -join '; '
}

function Find-FormulaUse {
    param($Rows, [string]$SourceName)
    return , @($Rows | Where-Object {
        $_.source_type -eq 'Attribute' -and $_.source_name -eq $SourceName -and
        $_.relation_kind -eq 'code_references_attribute' -and $_.evidence_role -eq 'Formula read'
    })
}

# Rule: an attribute in a classic formula is a use of the computed attribute, evidenced in the Formula file.
$lineTotalRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'LineTotal').results)
$subtotalUse = Find-FormulaUse $lineTotalRows 'OrderSubtotal'
Assert-True ($subtotalUse.Count -eq 1) "who-uses Attribute LineTotal should list Attribute OrderSubtotal [Formula read]; got: $(Format-Rows $lineTotalRows)"
$expectedLine = [array]::IndexOf(($subtotalFormulaXml -split "`n"), (($subtotalFormulaXml -split "`n") | Where-Object { $_.Contains('<Formula>') } | Select-Object -First 1)) + 1
Assert-True ($subtotalUse[0].line -eq $expectedLine) "OrderSubtotal evidence should carry line $expectedLine of its Formula file; got $($subtotalUse[0].line)"
Assert-True ($null -ne $subtotalUse[0].PSObject.Properties['source_file']) 'who-uses rows should carry source_file'
Assert-True ("$($subtotalUse[0].source_file)".Replace('\', '/').EndsWith('Formula/OrderSubtotal.xml')) "OrderSubtotal evidence should point to Formula/OrderSubtotal.xml; got $($subtotalUse[0].source_file)"

# Rule: a classic formula whose attribute is not indexed gives no relation.
Assert-True (@($lineTotalRows | Where-Object { $_.source_name -eq 'NotIndexed' }).Count -eq 0) "The formula NotIndexed (no indexed attribute) should give no relation; got: $(Format-Rows $lineTotalRows)"

# Rule: a call in a classic formula relates the computed attribute; its arguments are uses.
$priceCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Procedure' -Name 'PriceOf').results)
$call = @($priceCallers | Where-Object { $_.source_type -eq 'Attribute' -and $_.source_name -eq 'UnitPrice' -and $_.relation_kind -eq 'formula_calls_procedure' })
Assert-True ($call.Count -eq 1) "who-uses Procedure PriceOf should list Attribute UnitPrice (formula_calls_procedure); got: $(Format-Rows $priceCallers)"
Assert-True ($call[0].extractor_rule -eq 'classic_formula_udp_func') "The classic formula call should use classic_formula_udp_func; got $($call[0].extractor_rule)"
foreach ($argument in @('ItemCode', 'OrderDate')) {
    $rows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name $argument).results)
    Assert-True ((Find-FormulaUse $rows 'UnitPrice').Count -eq 1) "who-uses Attribute $argument should list Attribute UnitPrice [Formula read]; got: $(Format-Rows $rows)"
}

# Rule: an attribute in a modern Formula property is a use; the called name and an &variable are not.
foreach ($used in @('InvoiceLineAmount', 'InvoiceDiscount')) {
    $rows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name $used).results)
    Assert-True ((Find-FormulaUse $rows 'InvoiceTotal').Count -eq 1) "who-uses Attribute $used should list Attribute InvoiceTotal [Formula read]; got: $(Format-Rows $rows)"
}

foreach ($notUsed in @('Sum', 'Apply')) {
    $rows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name $notUsed).results)
    Assert-True ((Find-FormulaUse $rows 'InvoiceTotal').Count -eq 0) "who-uses Attribute $notUsed should not list InvoiceTotal (a called function and an &variable are not uses); got: $(Format-Rows $rows)"
}

# Rule: attribute-info reports a classic formula (its Formula/<Name>.xml file) like a modern one:
# isFormula true and the formula as formulaExpression (a vertical formula, <Type>SUM</Type>, as
# sum(<Source>)); an attribute with no formula is
# not one, and a modern Formula property is unchanged.
foreach ($case in @(
        [pscustomobject]@{ Name = 'OrderSubtotal'; IsFormula = $true; Expression = 'sum(LineTotal)' },
        [pscustomobject]@{ Name = 'UnitPrice'; IsFormula = $true; Expression = 'udp(PPriceOf, ItemCode, OrderDate)' },
        [pscustomobject]@{ Name = 'LineCount'; IsFormula = $true; Expression = 'count(LineNumber)' },
        [pscustomobject]@{ Name = 'LineTotal'; IsFormula = $false; Expression = $null },
        [pscustomobject]@{ Name = 'InvoiceTotal'; IsFormula = $true; Expression = 'sum(InvoiceLineAmount) - InvoiceDiscount if &Apply = 1' }
    )) {
    $info = Invoke-IndexQuery -Query 'attribute-info' -Type 'Attribute' -Name $case.Name
    Assert-True ($info.isFormula -eq $case.IsFormula) "attribute-info $($case.Name) isFormula should be $($case.IsFormula); got $($info.isFormula)"
    Assert-True ("$($info.formulaExpression)" -ceq "$($case.Expression)") "attribute-info $($case.Name) formulaExpression should be '$($case.Expression)'; got '$($info.formulaExpression)'"
}

# Rule: Attribute is no longer an unextracted attribute-use source on an index of extractor 21.
$coverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'LineTotal').coverage
Assert-True (@($coverage.unextracted_source_types | Where-Object { $_.type -eq 'Attribute' }).Count -eq 0) "Coverage should not list Attribute as not extracted; got $($coverage | ConvertTo-Json -Compress -Depth 4)"

# Rule: an index rewritten to 20 still lists Attribute as not extracted.
$oldIndexPath = Join-Path $kbIntelDir 'kb-intelligence-20.sqlite'
Copy-Item -LiteralPath $sqlitePath -Destination $oldIndexPath
$patchPath = Join-Path $tempRoot 'patch-version.py'
[System.IO.File]::WriteAllText($patchPath, @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE metadata SET value = '20' WHERE key = 'extractor_signature_version'")
conn.commit()
conn.close()
'@, $enc)
$python = Get-GeneXusPythonExecutable
Assert-True ($null -ne $python) 'Python 3 is required to rewrite the index version'
$patchOutput = & $python.Source @($python.PrefixArguments) $patchPath $oldIndexPath 2>&1
Assert-True ($LASTEXITCODE -eq 0) "Rewriting the index version to 20 should succeed; $(@($patchOutput) -join ' ')"
$oldCoverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'LineTotal' -IndexPath $oldIndexPath).coverage
Assert-True (@($oldCoverage.unextracted_source_types | Where-Object { $_.type -eq 'Attribute' }).Count -eq 1) "A version 20 index should list Attribute as not extracted; got $($oldCoverage | ConvertTo-Json -Compress -Depth 4)"

Write-Output 'OK: Test-KbIntelligenceFormulaSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
