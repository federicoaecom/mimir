#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: classic GeneXus Tables and Transactions (7.5 to 9 exports) produce the structural
    relations has_key_attribute, has_index_member_attribute, has_level_attribute, and has_level_table.

.DESCRIPTION
    Builds a synthetic KB of classic objects (root dataSource="gx-legacy-export") and proves that:
      - a classic Table relates to every indexed attribute of its <Key> entries (has_key_attribute,
        rule classic_table_key_attribute, role 'Key Item'), with the line of each <Key>;
      - a classic Table relates to every indexed attribute of its <TblIndex><IdxAttri><Name> entries
        (has_index_member_attribute, rule classic_table_index_member_attribute, role 'Index Member'),
        one relation per attribute even when several indexes name it;
      - a classic Transaction relates to every indexed attribute of its <Structure><Source> text
        (has_level_attribute, rule classic_transaction_level_attribute, role 'Level Attribute'),
        sub-levels included, with the line of the attribute in the XML file;
      - each Transaction level relates to the one Table whose key set equals the level's combined
        key set (parent level keys plus its own; has_level_table, rule
        classic_transaction_level_table, role 'Level Keys'), whatever the names;
      - a level whose key set matches no Table, or more than one, gives no has_level_table, and its
        attributes still relate;
      - a name that is not an indexed Attribute gives nothing;
      - a modern Table and Transaction keep the modern rules.
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

$tableGuid = '857ca50e-7905-0000-0007-c5d9ff2975ec'
$transactionGuid = '1db606f2-af09-4cf9-a3b5-b481519d28f6'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-ClassicXml {
    param([string]$Type, [string]$Name, [string]$Payload)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Object type="$Type" name="$Name" guid="" lastUpdate="0001-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
$Payload
  </GxLegacyPayload>
</Object>
"@
}

# The envelope the sync writes for each Attributes/GXAtt entry of a classic export.
function New-ClassicAttributeXml {
    param([string]$Name)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$Name" guid="" lastUpdate="0001-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-classic-structure-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
$folders = @{}
foreach ($folder in @('Table', 'Transaction', 'Attribute')) {
    $folders[$folder] = Join-Path $kbObjectsPath $folder
}
[void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)

function Write-Fixture {
    param([string]$Folder, [string]$Name, [string]$Xml)
    [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
}

foreach ($attributeName in @(
        'CustNo', 'CustLabel', 'OrdNo', 'OrdDay', 'LineNo', 'LineQty', 'RegNo', 'RegLabel', 'ZoneNo',
        'ModNo', 'ModLabel')) {
    Write-Fixture 'Attribute' $attributeName (New-ClassicAttributeXml -Name $attributeName)
}

# Classic Tables. Their names differ from the Transactions' on purpose: a level is matched by keys.
$custTableXml = New-ClassicXml -Type $tableGuid -Name 'TCUST' -Payload @'
<Table><Key>CustNo</Key><Info><Name>TCUST</Name></Info><Id>1</Id><TblIndex><Id>1</Id><Name>ITCUST</Name><Type>System</Type><IdxAttri><Name>CustNo</Name></IdxAttri></TblIndex></Table>
'@
Write-Fixture 'Table' 'TCUST' $custTableXml

$headerTableXml = New-ClassicXml -Type $tableGuid -Name 'TORDHDR' -Payload @'
<Table><Key>OrdNo</Key><Info><Name>TORDHDR</Name></Info><Id>2</Id>
<TblIndex><Id>1</Id><Name>ITORDHDR</Name><Type>System</Type><IdxAttri><Name>OrdNo</Name></IdxAttri></TblIndex>
<TblIndex><Id>2</Id><Name>ITORDHDR1</Name><Type>System</Type><IdxAttri><Name>CustNo</Name></IdxAttri></TblIndex></Table>
'@
Write-Fixture 'Table' 'TORDHDR' $headerTableXml

# Each <Key> on its own line, to pin the evidence line of each key attribute.
$lineTableXml = New-ClassicXml -Type $tableGuid -Name 'TORDLIN' -Payload @'
<Table><Key>OrdNo</Key>
<Key>LineNo</Key><Info><Name>TORDLIN</Name></Info><Id>3</Id>
<TblIndex><Id>1</Id><Name>ITORDLIN</Name><Type>System</Type><IdxAttri><Name>OrdNo</Name></IdxAttri><IdxAttri><Name>LineNo</Name></IdxAttri></TblIndex>
<TblIndex><Id>2</Id><Name>ITORDLIN1</Name><Type>System</Type><IdxAttri><Name>LineNo</Name></IdxAttri></TblIndex></Table>
'@
Write-Fixture 'Table' 'TORDLIN' $lineTableXml

# A classic Table whose only key is not an indexed Attribute.
Write-Fixture 'Table' 'TNOATTR' (New-ClassicXml -Type $tableGuid -Name 'TNOATTR' -Payload '<Table><Key>NotAnAttr</Key><Info><Name>TNOATTR</Name></Info><Id>5</Id></Table>')

# Two Tables with the same key set: a level with that key set is ambiguous.
foreach ($regTable in @('TREGA', 'TREGB')) {
    Write-Fixture 'Table' $regTable (New-ClassicXml -Type $tableGuid -Name $regTable -Payload "<Table><Key>RegNo</Key><Info><Name>$regTable</Name></Info><Id>4</Id></Table>")
}

# Classic single-level Transaction.
$customerTrnXml = New-ClassicXml -Type $transactionGuid -Name 'TrnCustomer' -Payload @'
<Transaction><Info><Name>TrnCustomer</Name><Description>Customers</Description></Info><Structure><Source><![CDATA[CustNo*
CustLabel]]></Source></Structure><Rules><![CDATA[parm(&CustNo);]]></Rules></Transaction>
'@
Write-Fixture 'Transaction' 'TrnCustomer' $customerTrnXml

# Classic two-level Transaction: the sub-level's combined key set is OrdNo plus LineNo.
$orderTrnXml = New-ClassicXml -Type $transactionGuid -Name 'TrnOrder' -Payload @'
<Transaction><Info><Name>TrnOrder</Name><Description>Orders</Description></Info><Structure><Source><![CDATA[OrdNo*
OrdDay
CustNo
CustLabel
    (LineNo*
     LineQty
     NotAnAttr)]]></Source></Structure></Transaction>
'@
Write-Fixture 'Transaction' 'TrnOrder' $orderTrnXml

# Classic Transaction whose sub-level declares no key of its own: only the root level (CustNo)
# relates to a Table; the sub-level's inherited key set does not make it TCUST again.
$noteTrnXml = New-ClassicXml -Type $transactionGuid -Name 'TrnCustNote' -Payload @'
<Transaction><Info><Name>TrnCustNote</Name></Info><Structure><Source><![CDATA[CustNo*
CustLabel
    (CustLabel)]]></Source></Structure></Transaction>
'@
Write-Fixture 'Transaction' 'TrnCustNote' $noteTrnXml

# Classic Transactions whose only level matches two Tables (RegNo) or none (ZoneNo).
$regTrnXml = New-ClassicXml -Type $transactionGuid -Name 'TrnReg' -Payload @'
<Transaction><Info><Name>TrnReg</Name></Info><Structure><Source><![CDATA[RegNo*
RegLabel]]></Source></Structure></Transaction>
'@
Write-Fixture 'Transaction' 'TrnReg' $regTrnXml
$zoneTrnXml = New-ClassicXml -Type $transactionGuid -Name 'TrnZone' -Payload @'
<Transaction><Info><Name>TrnZone</Name></Info><Structure><Source><![CDATA[ZoneNo*]]></Source></Structure></Transaction>
'@
Write-Fixture 'Transaction' 'TrnZone' $zoneTrnXml

# Modern Table and Transaction: the modern rules must still hold.
$modernTableXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Object guid="55555555-5555-5555-5555-555555555501" name="ModTable" type="$tableGuid">
  <Key>
    <Item>ModNo</Item>
  </Key>
  <Index><Part><Members><Member>ModLabel</Member></Members></Part></Index>
</Object>
"@
Write-Fixture 'Table' 'ModTable' $modernTableXml
$modernTrnXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Object guid="55555555-5555-5555-5555-555555555502" name="ModTrn" type="$transactionGuid">
  <Level name="ModTrn" Type="ModTable">
    <Attribute key="True">ModNo</Attribute>
    <Attribute key="False">ModLabel</Attribute>
  </Level>
</Object>
"@
Write-Fixture 'Transaction' 'ModTrn' $modernTrnXml

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'

& $buildScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete with classic Tables and Transactions; exit $LASTEXITCODE"
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

function Get-Targets {
    param([string]$Type, [string]$Name, [string]$RelationKind)
    $rows = @((Invoke-IndexQuery -Query 'what-uses' -Type $Type -Name $Name).results)
    # The leading comma keeps an empty match an empty array instead of $null.
    return , @($rows | Where-Object { $_.relation_kind -eq $RelationKind })
}

function Format-Rows {
    param($Rows)
    return (@($Rows) | ForEach-Object { "$($_.target_type) $($_.target_name) $($_.relation_kind) [$($_.evidence_role)] $($_.extractor_rule) line $($_.line)" }) -join '; '
}

function Get-Names {
    param($Rows)
    return (@($Rows) | ForEach-Object { $_.target_name } | Sort-Object -Unique) -join ','
}

# Rule: a classic Table relates to the indexed attributes of its <Key> entries.
$lineKeys = Get-Targets 'Table' 'TORDLIN' 'has_key_attribute'
Assert-True ((Get-Names $lineKeys) -eq 'LineNo,OrdNo') "Table TORDLIN has_key_attribute should be LineNo,OrdNo; got: $(Format-Rows $lineKeys)"
foreach ($row in $lineKeys) {
    Assert-True ($row.extractor_rule -eq 'classic_table_key_attribute') "TORDLIN key $($row.target_name) should use classic_table_key_attribute; got $($row.extractor_rule)"
    Assert-True ($row.evidence_role -eq 'Key Item') "TORDLIN key $($row.target_name) should have role 'Key Item'; got $($row.evidence_role)"
    Assert-True ($row.line -eq (Get-LineNumberOf $lineTableXml "<Key>$($row.target_name)</Key>")) "TORDLIN key $($row.target_name) should carry the line of its <Key>; got $($row.line)"
}
$noAttrKeys = Get-Targets 'Table' 'TNOATTR' 'has_key_attribute'
Assert-True ($noAttrKeys.Count -eq 0) "Table TNOATTR has_key_attribute should be empty (NotAnAttr is not indexed); got: $(Format-Rows $noAttrKeys)"
$custKeys = Get-Targets 'Table' 'TCUST' 'has_key_attribute'
Assert-True ((Get-Names $custKeys) -eq 'CustNo') "Table TCUST has_key_attribute should be CustNo; got: $(Format-Rows $custKeys)"

# Rule: a classic Table relates to the indexed attributes of its index members, once each.
$lineMembers = Get-Targets 'Table' 'TORDLIN' 'has_index_member_attribute'
Assert-True ($lineMembers.Count -eq 2) "Table TORDLIN should have 2 has_index_member_attribute rows (LineNo once although two indexes name it); got: $(Format-Rows $lineMembers)"
Assert-True ((Get-Names $lineMembers) -eq 'LineNo,OrdNo') "Table TORDLIN index members should be LineNo,OrdNo; got: $(Format-Rows $lineMembers)"
foreach ($row in $lineMembers) {
    Assert-True ($row.extractor_rule -eq 'classic_table_index_member_attribute') "TORDLIN index member $($row.target_name) should use classic_table_index_member_attribute; got $($row.extractor_rule)"
    Assert-True ($row.evidence_role -eq 'Index Member') "TORDLIN index member $($row.target_name) should have role 'Index Member'; got $($row.evidence_role)"
}
$headerMembers = Get-Targets 'Table' 'TORDHDR' 'has_index_member_attribute'
Assert-True ((Get-Names $headerMembers) -eq 'CustNo,OrdNo') "Table TORDHDR index members should be CustNo,OrdNo; got: $(Format-Rows $headerMembers)"
$custMember = @($headerMembers | Where-Object { $_.target_name -eq 'CustNo' })
Assert-True ($custMember[0].line -eq (Get-LineNumberOf $headerTableXml 'ITORDHDR1')) "TORDHDR index member CustNo should carry the line of its <IdxAttri>; got $($custMember[0].line)"

# Rule: a classic Transaction relates to every indexed attribute of its structure, sub-levels included.
$orderAttributes = Get-Targets 'Transaction' 'TrnOrder' 'has_level_attribute'
Assert-True ((Get-Names $orderAttributes) -eq 'CustLabel,CustNo,LineNo,LineQty,OrdDay,OrdNo') "Transaction TrnOrder has_level_attribute should list its 6 indexed attributes; got: $(Format-Rows $orderAttributes)"
foreach ($row in $orderAttributes) {
    Assert-True ($row.extractor_rule -eq 'classic_transaction_level_attribute') "TrnOrder level attribute $($row.target_name) should use classic_transaction_level_attribute; got $($row.extractor_rule)"
    Assert-True ($row.evidence_role -eq 'Level Attribute') "TrnOrder level attribute $($row.target_name) should have role 'Level Attribute'; got $($row.evidence_role)"
}
$lineQty = @($orderAttributes | Where-Object { $_.target_name -eq 'LineQty' })
Assert-True ($lineQty[0].line -eq (Get-LineNumberOf $orderTrnXml 'LineQty')) "TrnOrder level attribute LineQty should carry its line in the XML file; got $($lineQty[0].line)"
$lineNo = @($orderAttributes | Where-Object { $_.target_name -eq 'LineNo' })
Assert-True ($lineNo[0].line -eq (Get-LineNumberOf $orderTrnXml '(LineNo*')) "TrnOrder level attribute LineNo should carry its line in the XML file; got $($lineNo[0].line)"
$ordNo = @($orderAttributes | Where-Object { $_.target_name -eq 'OrdNo' })
Assert-True ($ordNo[0].line -eq (Get-LineNumberOf $orderTrnXml 'OrdNo*')) "TrnOrder level attribute OrdNo should carry its line in the XML file; got $($ordNo[0].line)"

# Rule: each level relates to the one Table whose key set equals its combined key set.
$orderTables = Get-Targets 'Transaction' 'TrnOrder' 'has_level_table'
Assert-True ((Get-Names $orderTables) -eq 'TORDHDR,TORDLIN') "Transaction TrnOrder has_level_table should be TORDHDR (OrdNo) and TORDLIN (OrdNo+LineNo); got: $(Format-Rows $orderTables)"
foreach ($row in $orderTables) {
    Assert-True ($row.extractor_rule -eq 'classic_transaction_level_table') "TrnOrder level table $($row.target_name) should use classic_transaction_level_table; got $($row.extractor_rule)"
    Assert-True ($row.evidence_role -eq 'Level Keys') "TrnOrder level table $($row.target_name) should have role 'Level Keys'; got $($row.evidence_role)"
}
$subLevelTable = @($orderTables | Where-Object { $_.target_name -eq 'TORDLIN' })
Assert-True ($subLevelTable[0].line -eq (Get-LineNumberOf $orderTrnXml '(LineNo*')) "The sub-level's has_level_table should carry the line that opens the level; got $($subLevelTable[0].line)"
$rootLevelTable = @($orderTables | Where-Object { $_.target_name -eq 'TORDHDR' })
Assert-True ($rootLevelTable[0].line -eq (Get-LineNumberOf $orderTrnXml 'OrdNo*')) "The root level's has_level_table should carry the line of its first attribute; got $($rootLevelTable[0].line)"
$customerTables = Get-Targets 'Transaction' 'TrnCustomer' 'has_level_table'
Assert-True ((Get-Names $customerTables) -eq 'TCUST') "Transaction TrnCustomer has_level_table should be TCUST; got: $(Format-Rows $customerTables)"

# Rule: a sub-level with no key of its own gives no has_level_table, even though its inherited key set
# equals a Table's keys.
$noteTables = Get-Targets 'Transaction' 'TrnCustNote' 'has_level_table'
Assert-True ($noteTables.Count -eq 1 -and $noteTables[0].target_name -eq 'TCUST') "Transaction TrnCustNote should relate only its root level to TCUST; got: $(Format-Rows $noteTables)"

# Rule: a level that matches two Tables or none gives no has_level_table; its attributes still relate.
$regTables = Get-Targets 'Transaction' 'TrnReg' 'has_level_table'
Assert-True ($regTables.Count -eq 0) "Transaction TrnReg (key RegNo, two Tables) should have no has_level_table; got: $(Format-Rows $regTables)"
$regAttributes = Get-Targets 'Transaction' 'TrnReg' 'has_level_attribute'
Assert-True ((Get-Names $regAttributes) -eq 'RegLabel,RegNo') "Transaction TrnReg should still relate RegLabel,RegNo; got: $(Format-Rows $regAttributes)"
$zoneTables = Get-Targets 'Transaction' 'TrnZone' 'has_level_table'
Assert-True ($zoneTables.Count -eq 0) "Transaction TrnZone (key ZoneNo, no Table) should have no has_level_table; got: $(Format-Rows $zoneTables)"
$zoneAttributes = Get-Targets 'Transaction' 'TrnZone' 'has_level_attribute'
Assert-True ((Get-Names $zoneAttributes) -eq 'ZoneNo') "Transaction TrnZone should still relate ZoneNo; got: $(Format-Rows $zoneAttributes)"

# Existing behaviour: a modern Table and Transaction keep the modern rules.
$modernKeys = Get-Targets 'Table' 'ModTable' 'has_key_attribute'
Assert-True ((Get-Names $modernKeys) -eq 'ModNo' -and $modernKeys[0].extractor_rule -eq 'table_key_attribute') "Modern Table ModTable should keep has_key_attribute ModNo via table_key_attribute; got: $(Format-Rows $modernKeys)"
$modernMembers = Get-Targets 'Table' 'ModTable' 'has_index_member_attribute'
Assert-True ((Get-Names $modernMembers) -eq 'ModLabel' -and $modernMembers[0].extractor_rule -eq 'table_index_member_attribute') "Modern Table ModTable should keep has_index_member_attribute ModLabel via table_index_member_attribute; got: $(Format-Rows $modernMembers)"
$modernAttributes = Get-Targets 'Transaction' 'ModTrn' 'has_level_attribute'
Assert-True ((Get-Names $modernAttributes) -eq 'ModLabel,ModNo' -and @($modernAttributes | Where-Object { $_.extractor_rule -ne 'transaction_level_attribute' }).Count -eq 0) "Modern Transaction ModTrn should keep has_level_attribute via transaction_level_attribute; got: $(Format-Rows $modernAttributes)"
$modernTables = Get-Targets 'Transaction' 'ModTrn' 'has_level_table'
Assert-True ((Get-Names $modernTables) -eq 'ModTable' -and $modernTables[0].extractor_rule -eq 'transaction_level_table') "Modern Transaction ModTrn should keep has_level_table ModTable via transaction_level_table; got: $(Format-Rows $modernTables)"

Write-Output 'OK: Test-KbIntelligenceLegacyClassicStructureSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
