#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: attribute references in classic GeneXus code (7.5 to 9 exports) produce
    code_references_attribute relations.

.DESCRIPTION
    Builds a synthetic KB of classic objects (root dataSource="gx-legacy-export") whose attributes
    come from the classic GXAtt envelope, and proves that:
      - who-uses Attribute OrdId lists the classic Report (its Layout/Block/CodeBlock/Source) and
        the classic WebPanel (its Events), with the roles 'Report Source read' and 'Events read';
      - an assignment at a statement start inside a For Each of a Report Source is a write
        ('Report Source write'), as in a modern Procedure Source;
      - a classic WebPanel's Rules are read ('Rules read');
      - an assignment at a statement start inside a New block of classic Events is a write
        ('Events write');
      - a classic Procedure's <Source> gives 'Procedure Source read' and, inside a For Each,
        'Procedure Source write';
      - an assignment rule in a classic Transaction's <Rules> is a write ('Rules write');
      - the coverage of who-uses on an Attribute lists Report as partly extracted, with its
        extracted and missing parts;
      - an &variable named like an attribute is not an attribute reference, and a name that is not
        an indexed Attribute yields nothing;
      - a modern Procedure (real GUID, no dataSource) still relates its Procedure Source Part
        attribute with the role 'Procedure Source read'.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath
$enc = Get-Utf8NoBomEncoding

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'

$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$transactionGuid = '1db606f2-af09-4cf9-a3b5-b481519d28f6'
$webPanelGuid = 'c9584656-94b6-4ccd-890f-332d11fc2c25'
$procedureSourcePartGuid = '528d1c06-a9c2-420d-bd35-21dca83f12ff'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-ClassicXml {
    param([string]$Type, [string]$Name, [string]$RootElement, [string]$Body)
    return @"
<Object type="$Type" name="$Name" guid="" lastUpdate="2013-02-27T15:36:48.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<$RootElement>
  <Info><Name>$Name</Name></Info>
$Body
</$RootElement>
  </GxLegacyPayload>
</Object>
"@
}

# The envelope the sync writes for each Attributes/GXAtt entry of a classic export.
function New-ClassicAttributeXml {
    param([string]$Name)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$Name" guid="" lastUpdate="2013-02-27T15:36:48.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<GXAtt><Attribute><Id>1</Id><Name>$Name</Name><Description>$Name</Description></Attribute></GXAtt>
  </GxLegacyPayload>
</Attribute>
"@
}

function Get-LineNumberOf {
    param([string]$Text, [string]$Needle)
    $lines = $Text -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Contains($Needle)) { return $i + 1 }
    }
    throw "Fixture text has no line with '$Needle'"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-classic-attributes-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
$folders = @{}
foreach ($folder in @('WebPanel', 'Report', 'Procedure', 'Transaction', 'Attribute')) {
    $folders[$folder] = Join-Path $kbObjectsPath $folder
}
[void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)

function Write-Fixture {
    param([string]$Folder, [string]$Name, [string]$Xml)
    [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
}

foreach ($attributeName in @('OrdId', 'OrdName', 'DocAttr')) {
    Write-Fixture 'Attribute' $attributeName (New-ClassicAttributeXml -Name $attributeName)
}

# Classic Report: code in Layout/Block/CodeBlock/Source. NotAnAttr is not an indexed Attribute.
$reportXml = New-ClassicXml -Type 'gxlegacy/Report' -Name 'RPTORDERS' -RootElement 'Report' -Body @'
  <Layout><Block><CodeBlock><Source><![CDATA[For Each OrdId
  Where OrdId = &OrdId
  Defined By OrdName
  OrdName = &Name
  NotAnAttr = &Name
EndFor]]></Source></CodeBlock><PrintBlock><Edit><Source><![CDATA[DocAttr]]></Source></Edit></PrintBlock></Block></Layout>
  <Rules><![CDATA[Parm(&OrdId);]]></Rules>
  <Documentation><Source><![CDATA[<P>Prints DocAttr for each order</P>]]></Source></Documentation>
'@
Write-Fixture 'Report' 'RPTORDERS' $reportXml

# Classic WebPanel: its code is in <Events> and <Rules>; the HTMLForm <Source> holds HTML.
$webPanelXml = New-ClassicXml -Type $webPanelGuid -Name 'WPORDERS' -RootElement 'WebPanel' -Body @'
  <HTMLForm><Source><![CDATA[<table><tr><td>Print</td></tr></table>]]></Source></HTMLForm>
  <Rules><![CDATA[parm(OrdName);]]></Rules>
  <Events><![CDATA[Event 'Print'
  &Msg = OrdId
EndEvent]]></Events>
'@
Write-Fixture 'WebPanel' 'WPORDERS' $webPanelXml

# Classic WebPanel that only names a variable like the attribute.
$variableOnlyXml = New-ClassicXml -Type $webPanelGuid -Name 'WVARONLY' -RootElement 'WebPanel' -Body @'
  <Events><![CDATA[Event Enter
  &OrdId = 1
EndEvent]]></Events>
'@
Write-Fixture 'WebPanel' 'WVARONLY' $variableOnlyXml

# Classic WebPanel whose Events assign an attribute inside a New block.
$eventsWriterXml = New-ClassicXml -Type $webPanelGuid -Name 'WNEWER' -RootElement 'WebPanel' -Body @'
  <Events><![CDATA[Event Enter
  New
    OrdId = &OrdId
  EndNew
EndEvent]]></Events>
'@
Write-Fixture 'WebPanel' 'WNEWER' $eventsWriterXml

# Classic Procedure: code in Layout/Block/CodeBlock/Source (assumed like the Report's; no real export seen).
$classicProcedureXml = New-ClassicXml -Type $procedureGuid -Name 'PrcOrders' -RootElement 'Procedure' -Body @'
  <Layout><Block><CodeBlock><Source><![CDATA[For Each
  Where OrdId = &OrdId
  OrdName = &Name
EndFor]]></Source></CodeBlock></Block></Layout>
'@
Write-Fixture 'Procedure' 'PrcOrders' $classicProcedureXml

# Classic Transaction: an assignment rule in <Rules>.
$classicTransactionXml = New-ClassicXml -Type $transactionGuid -Name 'TrnOrders' -RootElement 'Transaction' -Body @'
  <Rules><![CDATA[OrdName = 'Default' if insert;]]></Rules>
'@
Write-Fixture 'Transaction' 'TrnOrders' $classicTransactionXml

# Modern Procedure: the modern code-Part path must still hold.
$modernXml = @"
<Object type="$procedureGuid" name="ModernAttrProc" guid="77777777-7777-7777-7777-777777777711">
  <Part type="$procedureSourcePartGuid">
    <Source><![CDATA[for each
  where OrdId = 1
endfor]]></Source>
  </Part>
</Object>
"@
Write-Fixture 'Procedure' 'ModernAttrProc' $modernXml

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'

& $buildScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete with classic attribute users; exit $LASTEXITCODE"
$inv = (Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json).inventory_semantics
Assert-True ($inv.status -eq 'OK') "inventory_semantics.status should be OK, was $($inv.status)"

function Invoke-IndexQuery {
    param([string]$Query, [string]$Type, [string]$Name)
    # stderr stays out of the JSON parse; it is only reported when the output does not parse.
    $output = & $queryScript -IndexPath $sqlitePath -KbWorkspaceRoot $kbWorkspaceRoot -Query $Query `
        -ObjectType $Type -ObjectName $Name -Format json 2>&1
    $exitCode = $LASTEXITCODE
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($stdout)) {
        throw "ASSERT FAILED: $Query $Type $Name returned no output (exit $exitCode). stderr: $stderr"
    }
    try { $json = $stdout | ConvertFrom-Json }
    catch { throw "ASSERT FAILED: $Query $Type $Name did not return JSON (exit $exitCode). stderr: $stderr" }
    Assert-True ($exitCode -eq 0) "$Query $Type $Name should exit 0; got $exitCode. stderr: $stderr"
    return $json
}

function Find-AttributeUse {
    param($Rows, [string]$SourceType, [string]$SourceName, [string]$Role)
    # The leading comma keeps an empty match an empty array instead of $null.
    return , @($Rows | Where-Object {
        $_.source_type -eq $SourceType -and $_.source_name -eq $SourceName -and
        $_.relation_kind -eq 'code_references_attribute' -and $_.evidence_role -eq $Role
    })
}

function Format-Rows {
    param($Rows)
    return (@($Rows) | ForEach-Object { "$($_.source_type) $($_.source_name) $($_.relation_kind) [$($_.evidence_role)]" }) -join '; '
}

# Rule: who-uses Attribute OrdId lists the classic Report and the classic WebPanel.
$ordIdRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'OrdId').results)
$fromReport = Find-AttributeUse $ordIdRows 'Report' 'RPTORDERS' 'Report Source read'
Assert-True ($fromReport.Count -eq 1) "who-uses Attribute OrdId should list Report RPTORDERS (code_references_attribute, Report Source read); got: $(Format-Rows $ordIdRows)"
Assert-True ($fromReport[0].line -eq (Get-LineNumberOf $reportXml 'Where OrdId')) "Report RPTORDERS evidence should carry the line of 'Where OrdId' (the For Each table name is not a use); got $($fromReport[0].line)"
Assert-True ($fromReport[0].extractor_rule -eq 'code_attribute_reference') "Report RPTORDERS should use code_attribute_reference; got $($fromReport[0].extractor_rule)"
$fromWebPanel = Find-AttributeUse $ordIdRows 'WebPanel' 'WPORDERS' 'Events read'
Assert-True ($fromWebPanel.Count -eq 1) "who-uses Attribute OrdId should list WebPanel WPORDERS (code_references_attribute, Events read); got: $(Format-Rows $ordIdRows)"
Assert-True ($fromWebPanel[0].line -eq (Get-LineNumberOf $webPanelXml '&Msg = OrdId')) "WebPanel WPORDERS evidence should carry the line of '&Msg = OrdId'; got $($fromWebPanel[0].line)"

# Rule: a Report's attribute uses are extracted only in part, so the answer is never complete.
# Whether Report is listed as partly extracted or as not extracted follows the index's
# extractor_signature_version (partly extracted since 19).
$expectedReportExtracted = 'Source reads,rule reads,block writes'
$expectedReportMissing = 'ambiguous writes,layout,Business Component members'
$ordIdCoverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'OrdId').coverage
Assert-True ($ordIdCoverage.complete -eq $false) "who-uses Attribute OrdId coverage should not be complete with a Report in the index; got $($ordIdCoverage | ConvertTo-Json -Compress -Depth 4)"
$reportCoverage = @(@($ordIdCoverage.partially_extracted_source_types) | Where-Object { $_.type -eq 'Report' })
Assert-True ($reportCoverage.Count -eq 1 -and $reportCoverage[0].count -eq 1) "who-uses Attribute OrdId coverage should list Report (count 1) as partly extracted; got $($ordIdCoverage | ConvertTo-Json -Compress -Depth 4)"
Assert-True (@($ordIdCoverage.unextracted_source_types | Where-Object { $_.type -eq 'Report' }).Count -eq 0) "who-uses Attribute OrdId coverage should not list Report as not extracted; got $($ordIdCoverage | ConvertTo-Json -Compress -Depth 4)"
$reportExtracted = @($reportCoverage[0].extracted) -join ','
$reportMissing = @($reportCoverage[0].missing) -join ','
Assert-True ($reportExtracted -ceq $expectedReportExtracted) "Report coverage extracted should be '$expectedReportExtracted'; got '$reportExtracted'"
Assert-True ($reportMissing -ceq $expectedReportMissing) "Report coverage missing should be '$expectedReportMissing'; got '$reportMissing'"

# The text output carries the same Report entry in its coverage note.
$textOutput = & $queryScript -IndexPath $sqlitePath -KbWorkspaceRoot $kbWorkspaceRoot -Query 'who-uses' `
    -ObjectType 'Attribute' -ObjectName 'OrdId' -Format text 2>$null
Assert-True ($LASTEXITCODE -eq 0) "who-uses Attribute OrdId (text) should exit 0; got $LASTEXITCODE"
$coverageLines = @(@($textOutput) | ForEach-Object { "$_".TrimEnd("`r") } | Where-Object { $_ -match '^coverage:' })
$expectedReportNote = 'Report (1): Source reads, rule reads and block writes are indexed, ambiguous writes, layout and Business Component members are not'
Assert-True ($coverageLines.Count -eq 1 -and $coverageLines[0].Contains($expectedReportNote)) "The text coverage note should contain '$expectedReportNote'; got: $($coverageLines -join ' | ')"

# Rule: an assignment at a statement start inside a For Each of a Report Source is a write.
$ordNameRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'OrdName').results)
$write = Find-AttributeUse $ordNameRows 'Report' 'RPTORDERS' 'Report Source write'
Assert-True ($write.Count -eq 1) "who-uses Attribute OrdName should list Report RPTORDERS with Report Source write; got: $(Format-Rows $ordNameRows)"
Assert-True ($write[0].line -eq (Get-LineNumberOf $reportXml 'OrdName = &Name')) "The write evidence should carry the line of 'OrdName = &Name'; got $($write[0].line)"
Assert-True ((Find-AttributeUse $ordNameRows 'Report' 'RPTORDERS' 'Report Source read').Count -eq 1) "who-uses Attribute OrdName should list Report RPTORDERS with Report Source read (Defined By OrdName); got: $(Format-Rows $ordNameRows)"

# Rule: a classic WebPanel's Rules are read.
Assert-True ((Find-AttributeUse $ordNameRows 'WebPanel' 'WPORDERS' 'Rules read').Count -eq 1) "who-uses Attribute OrdName should list WebPanel WPORDERS with Rules read (parm(OrdName)); got: $(Format-Rows $ordNameRows)"

# Rule: an assignment at a statement start inside a New block of classic Events is a write.
$eventsWrite = Find-AttributeUse $ordIdRows 'WebPanel' 'WNEWER' 'Events write'
Assert-True ($eventsWrite.Count -eq 1) "who-uses Attribute OrdId should list WebPanel WNEWER with Events write; got: $(Format-Rows $ordIdRows)"
Assert-True ($eventsWrite[0].line -eq (Get-LineNumberOf $eventsWriterXml 'OrdId = &OrdId')) "The Events write evidence should carry the line of 'OrdId = &OrdId'; got $($eventsWrite[0].line)"

# Rule: only a <Source> inside a <CodeBlock> is code: the Report's Documentation <Source> (HTML) and the
# <Source> of a print control in its layout yield no attribute reference.
$docAttrRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'DocAttr').results)
Assert-True ($docAttrRows.Count -eq 0) "who-uses Attribute DocAttr should be empty (named only in Documentation and a print control); got: $(Format-Rows $docAttrRows)"

# Rule: a classic Procedure's <Source> is read as a Procedure Source, with writes inside a For Each.
$procedureRead = Find-AttributeUse $ordIdRows 'Procedure' 'PrcOrders' 'Procedure Source read'
Assert-True ($procedureRead.Count -eq 1) "who-uses Attribute OrdId should list classic Procedure PrcOrders with Procedure Source read; got: $(Format-Rows $ordIdRows)"
Assert-True ($procedureRead[0].line -eq (Get-LineNumberOf $classicProcedureXml 'Where OrdId')) "The Procedure Source read evidence should carry the line of 'Where OrdId'; got $($procedureRead[0].line)"
$procedureWrite = Find-AttributeUse $ordNameRows 'Procedure' 'PrcOrders' 'Procedure Source write'
Assert-True ($procedureWrite.Count -eq 1) "who-uses Attribute OrdName should list classic Procedure PrcOrders with Procedure Source write; got: $(Format-Rows $ordNameRows)"
Assert-True ($procedureWrite[0].line -eq (Get-LineNumberOf $classicProcedureXml 'OrdName = &Name')) "The Procedure Source write evidence should carry the line of 'OrdName = &Name'; got $($procedureWrite[0].line)"

# Rule: an assignment rule in a classic Transaction's <Rules> is a write.
$rulesWrite = Find-AttributeUse $ordNameRows 'Transaction' 'TrnOrders' 'Rules write'
Assert-True ($rulesWrite.Count -eq 1) "who-uses Attribute OrdName should list classic Transaction TrnOrders with Rules write; got: $(Format-Rows $ordNameRows)"
Assert-True ((Find-AttributeUse $ordNameRows 'Transaction' 'TrnOrders' 'Rules read').Count -eq 0) "The Transaction assignment rule should give no Rules read of its own; got: $(Format-Rows $ordNameRows)"

# Rule: an &variable is not an attribute reference.
Assert-True (@($ordIdRows | Where-Object { $_.source_name -eq 'WVARONLY' }).Count -eq 0) "&OrdId should not be an attribute reference; who-uses Attribute OrdId got: $(Format-Rows $ordIdRows)"

# Rule: a name that is not an indexed Attribute yields nothing.
$reportUses = @((Invoke-IndexQuery -Query 'what-uses' -Type 'Report' -Name 'RPTORDERS').results)
$reportAttributeTargets = @($reportUses | Where-Object { $_.target_type -eq 'Attribute' } | ForEach-Object { $_.target_name } | Sort-Object -Unique)
Assert-True (($reportAttributeTargets -join ',') -eq 'OrdId,OrdName') "what-uses Report RPTORDERS should list only the indexed attributes OrdId and OrdName; got: $($reportAttributeTargets -join ',')"

# Existing behaviour: a modern Procedure keeps the modern code-Part path.
$modernUse = Find-AttributeUse $ordIdRows 'Procedure' 'ModernAttrProc' 'Procedure Source read'
Assert-True ($modernUse.Count -eq 1) "who-uses Attribute OrdId should still list Procedure ModernAttrProc with Procedure Source read; got: $(Format-Rows $ordIdRows)"
Assert-True ($modernUse[0].line -eq (Get-LineNumberOf $modernXml 'where OrdId')) "Procedure ModernAttrProc evidence should carry the line of 'where OrdId'; got $($modernUse[0].line)"

Write-Output 'OK: Test-KbIntelligenceLegacyClassicAttributesSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
