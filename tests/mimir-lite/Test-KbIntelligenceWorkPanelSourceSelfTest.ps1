#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: a Work Panel's code is read for calls and attribute uses, and WorkPanel is queryable.

.DESCRIPTION
    Builds a synthetic KB with a classic Work Panel (root dataSource="gx-legacy-export", code in
    <Events> and <Rules>) and a modern Work Panel (real GUID, Events and Rules Parts) and proves that:
      - the classic Work Panel's Udp(, Call(, and Link( relate to the named Procedure, Report, and
        Work Panel, with the object-type prefix stripped;
      - the classic Work Panel's attribute uses relate with the roles 'Rules read', 'Events read', and
        'Events write' (an assignment inside a for each block);
      - the modern Work Panel's Events relate Proc.Call( to the Procedure and its Rules and Events
        attribute uses relate with the same roles, 'Events write' included;
      - a modern <WorkPanel>.Call( and call(<WorkPanel>, ...) relate to the Work Panel (calls_workpanel,
        rules workpanel_dot_call and workpanel_call_command), and a Procedure of the same name wins;
      - who-uses, what-uses, and impact-basic answer for a WorkPanel (no QUERY_NOT_SEMANTIC_FOR_TYPE);
      - a who-uses on a Procedure reports complete calls coverage with Work Panels in the index;
      - a who-uses on an Attribute lists WorkPanel as partly extracted (rule reads, event reads, block
        writes, condition reads), and an index whose extractor_signature_version is rewritten to 19, or removed, lists
        WorkPanel as not extracted, for calls and for attribute uses.
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
$workPanelGuid = '198e8ea4-1d49-4c9c-8a9a-417024baa9d1'
$rulesPartGuid = '9b0a32a3-de6d-4be1-a4dd-1b85d3741534'
$eventsPartGuid = 'c44bd5ff-f918-415b-98e6-aca44fed84fa'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-ClassicXml {
    param([string]$Type, [string]$Name, [string]$RootElement, [string]$Body)
    return @"
<Object type="$Type" name="$Name" guid="" lastUpdate="1997-07-22T04:36:13.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<$RootElement>
  <Info><Name>$Name</Name></Info>
$Body
</$RootElement>
  </GxLegacyPayload>
</Object>
"@
}

# The envelope the sync writes for each attribute of a classic export.
function New-ClassicAttributeXml {
    param([string]$Name)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$Name" guid="" lastUpdate="1997-07-22T04:36:13.0000000Z" dataSource="gx-legacy-export">
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-workpanel-source-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
$folders = @{}
foreach ($folder in @('WorkPanel', 'Procedure', 'Report', 'Attribute')) {
    $folders[$folder] = Join-Path $kbObjectsPath $folder
}
[void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)

function Write-Fixture {
    param([string]$Folder, [string]$Name, [string]$Xml)
    [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
}

foreach ($attributeName in @('PartId', 'PartName', 'PartStock', 'PartCode')) {
    Write-Fixture 'Attribute' $attributeName (New-ClassicAttributeXml -Name $attributeName)
}

# Classic Work Panel: code in <Events> and <Rules>, the shape the sync writes for a .xpw or a 7.5-9 export.
$classicXml = New-ClassicXml -Type $workPanelGuid -Name 'WkParts' -RootElement 'WorkPanel' -Body @'
  <Events><![CDATA[Event Load
  &Stock = udp(PPartStock, PartId)
EndEvent
Event Enter
  call(RRptParts, PartId)
  link(WWkPartDetail)
  for each
    PartName = &NewName
  endfor
EndEvent]]></Events>
  <Rules><![CDATA[noaccept(PartName);]]></Rules>
'@
Write-Fixture 'WorkPanel' 'WkParts' $classicXml
Write-Fixture 'WorkPanel' 'WkPartDetail' (New-ClassicXml -Type $workPanelGuid -Name 'WkPartDetail' -RootElement 'WorkPanel' -Body '')
# A classic Procedure or Report keeps its (here empty) code in Layout/Block/CodeBlock, so the
# unread classic code counter leaves them out.
Write-Fixture 'Procedure' 'PartStock' (New-ClassicXml -Type $procedureGuid -Name 'PartStock' -RootElement 'Procedure' -Body '<Layout><Block><CodeBlock></CodeBlock></Block></Layout>')
Write-Fixture 'Report' 'RptParts' (New-ClassicXml -Type 'gxlegacy/Report' -Name 'RptParts' -RootElement 'Report' -Body '<Layout><Block><CodeBlock></CodeBlock></Block></Layout>')

# Modern Work Panel: Events and Rules Parts, as GeneXus X to 18 export a Windows Work Panel.
$modernXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="ModernWk" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0e000000-0000-4000-8000-000000000001" name="ModernWk" type="$workPanelGuid" description="Synthetic modern work panel">
  <Part type="$rulesPartGuid">
    <Source><![CDATA[parm(in:PartCode);
]]></Source>
  </Part>
  <Part type="$eventsPartGuid">
    <Source><![CDATA[Event Enter
    ModernProc.Call(PartStock)
    for each
        PartCode = 1
    endfor
EndEvent
]]></Source>
  </Part>
</Object>
"@
Write-Fixture 'WorkPanel' 'ModernWk' $modernXml
Write-Fixture 'Procedure' 'ModernProc' @"
<Object type="$procedureGuid" name="ModernProc" guid="0e000000-0000-4000-8000-000000000002" lastUpdate="2026-01-01T00:00:00">
  <Source><![CDATA[]]></Source>
</Object>
"@

# Modern Procedures calling the modern Work Panel with .Call( and with call(.
foreach ($caller in @(@{ Name = 'WkDotCaller'; Code = 'ModernWk.Call(&Code)' }, @{ Name = 'WkCommandCaller'; Code = 'call(ModernWk, &Code)' })) {
    Write-Fixture 'Procedure' $caller.Name @"
<Object type="$procedureGuid" name="$($caller.Name)" guid="0e000000-0000-4000-8000-0000000000$(if ($caller.Name -eq 'WkDotCaller') { '03' } else { '04' })" lastUpdate="2026-01-01T00:00:00">
  <Source><![CDATA[$($caller.Code)]]></Source>
</Object>
"@
}

# A Procedure and a modern Work Panel with the same name: the call relates to the Procedure.
Write-Fixture 'Procedure' 'SharedWk' @"
<Object type="$procedureGuid" name="SharedWk" guid="0e000000-0000-4000-8000-000000000005" lastUpdate="2026-01-01T00:00:00">
  <Source><![CDATA[]]></Source>
</Object>
"@
Write-Fixture 'WorkPanel' 'SharedWk' @"
<Object type="$workPanelGuid" name="SharedWk" guid="0e000000-0000-4000-8000-000000000006" lastUpdate="2026-01-01T00:00:00">
  <Part type="$eventsPartGuid">
    <Source><![CDATA[]]></Source>
  </Part>
</Object>
"@
Write-Fixture 'Procedure' 'SharedCaller' @"
<Object type="$procedureGuid" name="SharedCaller" guid="0e000000-0000-4000-8000-000000000007" lastUpdate="2026-01-01T00:00:00">
  <Source><![CDATA[SharedWk.Call(&Code)]]></Source>
</Object>
"@

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'

& $buildScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete with Work Panels; exit $LASTEXITCODE"

function Invoke-IndexQuery {
    param([string]$Query, [string]$Type, [string]$Name, [string]$IndexPath = $sqlitePath)
    # stderr stays out of the JSON parse; it is only reported when the output does not parse.
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
    return (@($Rows) | ForEach-Object { "$($_.source_type) $($_.source_name) -> $($_.target_type) $($_.target_name) $($_.relation_kind) [$($_.evidence_role)]" }) -join '; '
}

function Find-Row {
    param($Rows, [string]$Type, [string]$Name, [string]$Kind, [string]$Side)
    # The leading comma keeps an empty match an empty array instead of $null.
    return , @($Rows | Where-Object {
        $_."$($Side)_type" -eq $Type -and $_."$($Side)_name" -eq $Name -and $_.relation_kind -eq $Kind
    })
}

function Find-AttributeUse {
    param($Rows, [string]$SourceName, [string]$Role)
    return , @($Rows | Where-Object {
        $_.source_type -eq 'WorkPanel' -and $_.source_name -eq $SourceName -and
        $_.relation_kind -eq 'code_references_attribute' -and $_.evidence_role -eq $Role
    })
}

# Rule: a classic Work Panel's calls relate, with the prefix stripped and the line of the call.
$classicRows = @((Invoke-IndexQuery -Query 'what-uses' -Type 'WorkPanel' -Name 'WkParts').results)
$toProcedure = Find-Row $classicRows 'Procedure' 'PartStock' 'calls_procedure' 'target'
Assert-True ($toProcedure.Count -eq 1) "what-uses WorkPanel WkParts should list Procedure PartStock (calls_procedure); got: $(Format-Rows $classicRows)"
Assert-True ($toProcedure[0].line -eq (Get-LineNumberOf $classicXml 'udp(PPartStock')) "Procedure PartStock evidence should carry the line of udp(PPartStock, ...); got $($toProcedure[0].line)"
Assert-True ($toProcedure[0].extractor_rule -eq 'classic_udp_func') "udp(PPartStock, ...) should use classic_udp_func; got $($toProcedure[0].extractor_rule)"
Assert-True ((Find-Row $classicRows 'Report' 'RptParts' 'calls_report' 'target').Count -eq 1) "what-uses WorkPanel WkParts should list Report RptParts (calls_report); got: $(Format-Rows $classicRows)"
Assert-True ((Find-Row $classicRows 'WorkPanel' 'WkPartDetail' 'calls_workpanel' 'target').Count -eq 1) "what-uses WorkPanel WkParts should list WorkPanel WkPartDetail (calls_workpanel); got: $(Format-Rows $classicRows)"

# Rule: who-uses answers for a WorkPanel target and for the callee of a Work Panel.
$detailCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'WorkPanel' -Name 'WkPartDetail').results)
Assert-True ((Find-Row $detailCallers 'WorkPanel' 'WkParts' 'calls_workpanel' 'source').Count -eq 1) "who-uses WorkPanel WkPartDetail should list WorkPanel WkParts; got: $(Format-Rows $detailCallers)"
$reportCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Report' -Name 'RptParts').results)
Assert-True ((Find-Row $reportCallers 'WorkPanel' 'WkParts' 'calls_report' 'source').Count -eq 1) "who-uses Report RptParts should list WorkPanel WkParts; got: $(Format-Rows $reportCallers)"
$impact = Invoke-IndexQuery -Query 'impact-basic' -Type 'WorkPanel' -Name 'WkPartDetail'
Assert-True ($impact.query -eq 'impact-basic') "impact-basic WorkPanel WkPartDetail should answer; got $($impact | ConvertTo-Json -Compress -Depth 3)"

# Rule: a classic Work Panel's attribute uses relate with Rules and Events roles.
$partIdRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'PartId').results)
Assert-True ((Find-AttributeUse $partIdRows 'WkParts' 'Events read').Count -eq 1) "who-uses Attribute PartId should list WorkPanel WkParts [Events read]; got: $(Format-Rows $partIdRows)"
$partNameRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'PartName').results)
Assert-True ((Find-AttributeUse $partNameRows 'WkParts' 'Rules read').Count -eq 1) "who-uses Attribute PartName should list WorkPanel WkParts [Rules read]; got: $(Format-Rows $partNameRows)"
$partNameWrite = Find-AttributeUse $partNameRows 'WkParts' 'Events write'
Assert-True ($partNameWrite.Count -eq 1) "who-uses Attribute PartName should list WorkPanel WkParts [Events write] for the assignment inside for each; got: $(Format-Rows $partNameRows)"
Assert-True ($partNameWrite[0].line -eq (Get-LineNumberOf $classicXml 'PartName = &NewName')) "PartName Events write evidence should carry the line of the assignment; got $($partNameWrite[0].line)"

# Rule: a modern Work Panel's Events call and its Rules and Events attribute uses relate.
$modernRows = @((Invoke-IndexQuery -Query 'what-uses' -Type 'WorkPanel' -Name 'ModernWk').results)
$toModernProc = Find-Row $modernRows 'Procedure' 'ModernProc' 'calls_procedure' 'target'
Assert-True ($toModernProc.Count -eq 1) "what-uses WorkPanel ModernWk should list Procedure ModernProc (calls_procedure); got: $(Format-Rows $modernRows)"
Assert-True ($toModernProc[0].extractor_rule -eq 'procedure_dot_call') "ModernProc.Call( should use procedure_dot_call; got $($toModernProc[0].extractor_rule)"
$partCodeRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'PartCode').results)
Assert-True ((Find-AttributeUse $partCodeRows 'ModernWk' 'Rules read').Count -eq 1) "who-uses Attribute PartCode should list WorkPanel ModernWk [Rules read]; got: $(Format-Rows $partCodeRows)"
Assert-True ((Find-AttributeUse $partCodeRows 'ModernWk' 'Events write').Count -eq 1) "who-uses Attribute PartCode should list WorkPanel ModernWk [Events write] for the assignment inside for each; got: $(Format-Rows $partCodeRows)"
$partStockRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'PartStock').results)
Assert-True ((Find-AttributeUse $partStockRows 'ModernWk' 'Events read').Count -eq 1) "who-uses Attribute PartStock should list WorkPanel ModernWk [Events read]; got: $(Format-Rows $partStockRows)"

# Rule: a modern call to a Work Panel relates, with .Call( and with call(.
$modernWkCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'WorkPanel' -Name 'ModernWk').results)
foreach ($expected in @(@{ Name = 'WkDotCaller'; Rule = 'workpanel_dot_call' }, @{ Name = 'WkCommandCaller'; Rule = 'workpanel_call_command' })) {
    $row = Find-Row $modernWkCallers 'Procedure' $expected.Name 'calls_workpanel' 'source'
    Assert-True ($row.Count -eq 1) "who-uses WorkPanel ModernWk should list Procedure $($expected.Name) (calls_workpanel); got: $(Format-Rows $modernWkCallers)"
    Assert-True ($row[0].extractor_rule -eq $expected.Rule) "Procedure $($expected.Name) should relate with $($expected.Rule); got $($row[0].extractor_rule)"
}

# Rule: a Procedure of the same name wins over a Work Panel.
$sharedProcedureCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Procedure' -Name 'SharedWk').results)
Assert-True ((Find-Row $sharedProcedureCallers 'Procedure' 'SharedCaller' 'calls_procedure' 'source').Count -eq 1) "who-uses Procedure SharedWk should list Procedure SharedCaller (calls_procedure); got: $(Format-Rows $sharedProcedureCallers)"
$sharedWorkPanelCallers = @((Invoke-IndexQuery -Query 'who-uses' -Type 'WorkPanel' -Name 'SharedWk').results)
Assert-True ($sharedWorkPanelCallers.Count -eq 0) "who-uses WorkPanel SharedWk should be empty (the Procedure SharedWk wins); got: $(Format-Rows $sharedWorkPanelCallers)"

# Rule: Work Panels no longer make calls coverage incomplete.
$callsCoverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Procedure' -Name 'PartStock').coverage
Assert-True ($callsCoverage.complete -eq $true) "who-uses Procedure PartStock coverage should be complete with Work Panels in the index; got $($callsCoverage | ConvertTo-Json -Compress -Depth 4)"

# Rule: for an Attribute target WorkPanel is partly extracted, with its extracted and missing parts.
$attributeCoverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'PartId').coverage
$workPanelPartial = @($attributeCoverage.partially_extracted_source_types | Where-Object { $_.type -eq 'WorkPanel' })
Assert-True ($workPanelPartial.Count -eq 1 -and $workPanelPartial[0].count -eq 4) "who-uses Attribute PartId coverage should list WorkPanel (count 4) as partly extracted; got $($attributeCoverage | ConvertTo-Json -Compress -Depth 4)"
Assert-True (($workPanelPartial[0].extracted -join ',') -ceq 'rule reads,event reads,block writes,condition reads') "WorkPanel coverage extracted should be 'rule reads,event reads,block writes,condition reads'; got '$($workPanelPartial[0].extracted -join ',')'"
Assert-True (($workPanelPartial[0].missing -join ',') -ceq 'ambiguous writes,Windows form bindings,Business Component members,code outside a Part') "WorkPanel coverage missing is wrong; got '$($workPanelPartial[0].missing -join ',')'"
Assert-True (@($attributeCoverage.unextracted_source_types | Where-Object { $_.type -eq 'WorkPanel' }).Count -eq 0) "who-uses Attribute PartId coverage should not list WorkPanel as not extracted; got $($attributeCoverage | ConvertTo-Json -Compress -Depth 4)"

# Rule: an index built before extractor 20, or with no extractor version, still reports WorkPanel
# as not extracted.
$patchPath = Join-Path $tempRoot 'patch-version.py'
[System.IO.File]::WriteAllText($patchPath, @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
if sys.argv[2] == "absent":
    conn.execute("DELETE FROM metadata WHERE key = 'extractor_signature_version'")
else:
    conn.execute("UPDATE metadata SET value = ? WHERE key = 'extractor_signature_version'", (sys.argv[2],))
conn.commit()
conn.close()
'@, $enc)
$python = Get-GeneXusPythonExecutable
Assert-True ($null -ne $python) 'Python 3 is required to rewrite the index version'
foreach ($oldVersion in @('19', 'absent')) {
    $oldIndexPath = Join-Path $kbIntelDir "kb-intelligence-$oldVersion.sqlite"
    Copy-Item -LiteralPath $sqlitePath -Destination $oldIndexPath
    $patchOutput = & $python.Source @($python.PrefixArguments) $patchPath $oldIndexPath $oldVersion 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Rewriting the index version to $oldVersion should succeed; exit $LASTEXITCODE. $(@($patchOutput) -join ' ')"
    $oldCallsCoverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Procedure' -Name 'PartStock' -IndexPath $oldIndexPath).coverage
    $oldCallsWorkPanel = @($oldCallsCoverage.unextracted_source_types | Where-Object { $_.type -eq 'WorkPanel' })
    Assert-True ($oldCallsCoverage.complete -eq $false -and $oldCallsWorkPanel.Count -eq 1 -and $oldCallsWorkPanel[0].count -eq 4) "An index with version $oldVersion should list WorkPanel (count 4) as an unextracted call source; got $($oldCallsCoverage | ConvertTo-Json -Compress -Depth 4)"
    $oldAttributeCoverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'PartId' -IndexPath $oldIndexPath).coverage
    Assert-True (@($oldAttributeCoverage.unextracted_source_types | Where-Object { $_.type -eq 'WorkPanel' }).Count -eq 1) "An index with version $oldVersion should list WorkPanel as not extracted for attribute uses; got $($oldAttributeCoverage | ConvertTo-Json -Compress -Depth 4)"
    Assert-True (@($oldAttributeCoverage.partially_extracted_source_types | Where-Object { $_.type -eq 'WorkPanel' }).Count -eq 0) "An index with version $oldVersion should not list WorkPanel as partly extracted; got $($oldAttributeCoverage | ConvertTo-Json -Compress -Depth 4)"
}

Write-Output 'OK: Test-KbIntelligenceWorkPanelSourceSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
