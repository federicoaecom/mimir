#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: a classic `for each` (GeneXus 9 and earlier exports) relates to its inferred base
    table (navigates_inferred_table, rule classic_for_each_base_table, confidence inferred).

.DESCRIPTION
    Builds a synthetic KB of classic objects (root dataSource="gx-legacy-export"):

      - Tables TCUST (CustNo), TORD (OrdNo), TLIN (OrdNo, LineNo), TPROD (ProdNo), TUNIT (UnitNo),
        TREGA (RegANo) and TREGB (RegBNo), named unlike their Transactions (a level is matched to a
        Table by its key set).
      - Transactions: TrnCustomer (CustNo*, CustName), TrnOrder (OrdNo*, OrdDate, OrdTotal, CustNo,
        SellerNo, then the sub-level LineNo*, ProdNo, LineQty), TrnProduct (ProdNo*, ProdName,
        UnitNo), TrnUnit (UnitNo*, UnitName), TrnRegA (RegANo*, RegLabel), TrnRegB (RegBNo*,
        RegLabel). The order header reaches TCUST through CustNo, a line reaches TPROD through
        ProdNo, and a product reaches TUNIT through UnitNo.
      - SubTypeGroup GrpSeller: SellerNo is a subtype of CustNo and SellerName of CustName, so
        TORD reaches the seller's name through SellerNo.

    The base table of a block is the one Table, among those whose extended table (the Table and
    every Table or subtype group whose full key it reaches) holds every attribute of the block,
    that no other candidate is part of. Blocks and expected answers:

      - Procedure PROCA (code in Layout/Block/CodeBlock/Source):
        c1 `For Each` with where CustName and body OrdDate -> TORD (TLIN also qualifies, but TORD
          is part of its extended table);
        c2 old syntax `for each CustNo` with body CustName -> TCUST;
        c3 outer block on OrdDate -> TORD, c4 nested block on LineQty -> TLIN (the nested block's
          attributes never count for the outer one);
        c5 `defined by LineQty` plus OrdDate -> TLIN;
        c6 where CustNo, with a `when none` section naming ProdName (not counted) -> TCUST;
        c7 RegLabel only, stored in TREGA and TREGB -> ambiguous, no relation;
        c8 ProdName and RegLabel, which no extended table holds together -> none, no relation
          (ProdName with CustName would be TLIN, which reaches TPROD and, through TORD, TCUST);
        c9 a `for each` inside `new` ... `endnew` -> skipped;
        c10 SellerName (a subtype) with OrdDate -> TORD through the subtype group;
        c11 OrdTotal (an attribute of the order level) -> TORD;
        c16 a blank line and a comment line before `order LineQty (OrdDate)`: the clause is still a
          clause, so LineQty (followed by '(' in an old order clause) counts -> TLIN, not TORD;
        c17 `using DSLines(LineQty)` with OrdDate: the data selector name is no attribute, LineQty
          counts -> TLIN.
      - Report RPTORD, whose layout alternates code and print blocks (each element on its own line,
        as GeneXus 7.5 to 9 exports write them): c12 `for each order OrdNo` prints a block holding
        ProdName (positive <Id>, an attribute) and RegLabel (negative <Id>, a variable): the base
        table is TLIN, not TORD, and the variable does not make it ambiguous.
      - WorkPanel WPNAV: c13 in its Events, ProdName -> TPROD; c14 `For each line` and c15
        `for each selected line` are grid loops, skipped.
      - Transaction TrnUnit: c18 in its Events, ProdName -> TPROD.
      - WebPanel WPCUST: c19 in its Events, CustName -> TCUST.
      - A modern Procedure with a `for each` gets no inferred relation.

    Assertions go through Query-KbIntelligenceIndex.ps1 what-uses (JSON): the exact set of
    navigates_inferred_table rows of each source (target and evidence line), each with rule
    classic_for_each_base_table, role 'For Each base table' and confidence 'inferred'; and who-uses
    of Table TLIN lists exactly PROCA and RPTORD as inferred sources.
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
$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$procedureSourcePartGuid = '528d1c06-a9c2-420d-bd35-21dca83f12ff'
$workPanelGuid = '198e8ea4-1d49-4c9c-8a9a-417024baa9d1'
$webPanelGuid = 'c9584656-94b6-4ccd-890f-332d11fc2c25'
$subTypeGroupGuid = '87313f43-5eb2-41d7-9b8c-e8d9f5bf9588'
$relationKind = 'navigates_inferred_table'
$rule = 'classic_for_each_base_table'
$role = 'For Each base table'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { $failures.Add($Message) }

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

function Invoke-QueryJson {
    param([string]$IndexPath, [hashtable]$Arguments)
    $output = & $queryScript -IndexPath $IndexPath @Arguments -Format json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Query failed (exit $LASTEXITCODE) for $($Arguments.Values -join ' '): $(@($output) -join "`n")"
    }
    return ((@($output) -join "`n") | ConvertFrom-Json)
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-foreach-base-table-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $kbObjectsPath = Join-Path $tempRoot 'KbWorkspace/KbObjectsXml'
    $folders = @{}
    foreach ($folder in @('Attribute', 'Table', 'Transaction', 'SubTypeGroup', 'Procedure', 'Report', 'WorkPanel', 'WebPanel')) {
        $folders[$folder] = Join-Path $kbObjectsPath $folder
    }
    [void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
    $written = @{}
    function Write-Fixture {
        param([string]$Folder, [string]$Name, [string]$Xml)
        [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
        $written["$Folder/$Name"] = $Xml
    }

    foreach ($attributeName in @(
            'CustNo', 'CustName', 'OrdNo', 'OrdDate', 'OrdTotal', 'SellerNo', 'SellerName', 'LineNo', 'LineQty',
            'ProdNo', 'ProdName', 'UnitNo', 'UnitName', 'RegANo', 'RegBNo', 'RegLabel')) {
        Write-Fixture 'Attribute' $attributeName (New-ClassicAttributeXml -Name $attributeName)
    }

    $tables = [ordered]@{ TCUST = @('CustNo'); TORD = @('OrdNo'); TLIN = @('OrdNo', 'LineNo'); TPROD = @('ProdNo'); TUNIT = @('UnitNo'); TREGA = @('RegANo'); TREGB = @('RegBNo') }
    $tableId = 0
    foreach ($tableName in $tables.Keys) {
        $tableId++
        $keys = ($tables[$tableName] | ForEach-Object { "<Key>$_</Key>" }) -join ''
        Write-Fixture 'Table' $tableName (New-ClassicXml -Type $tableGuid -Name $tableName -Payload "<Table>$keys<Info><Name>$tableName</Name></Info><Id>$tableId</Id></Table>")
    }

    $structures = [ordered]@{
        TrnCustomer = "CustNo*`nCustName"
        TrnOrder    = "OrdNo*`nOrdDate`nOrdTotal`nCustNo`nSellerNo`n(LineNo*`nProdNo`nLineQty)"
        TrnProduct  = "ProdNo*`nProdName`nUnitNo"
        TrnUnit     = "UnitNo*`nUnitName"
        TrnRegA     = "RegANo*`nRegLabel"
        TrnRegB     = "RegBNo*`nRegLabel"
    }
    $trnEvents = @{ TrnUnit = "<Events><![CDATA[Event 'Refresh'`nfor each // c18`n    &Prod = ProdName`nendfor`nEndEvent]]></Events>" }
    foreach ($trnName in $structures.Keys) {
        Write-Fixture 'Transaction' $trnName (New-ClassicXml -Type $transactionGuid -Name $trnName -Payload "<Transaction><Info><Name>$trnName</Name></Info><Structure><Source><![CDATA[$($structures[$trnName])]]></Source></Structure>$($trnEvents[$trnName])</Transaction>")
    }

    Write-Fixture 'SubTypeGroup' 'GrpSeller' (New-ClassicXml -Type $subTypeGroupGuid -Name 'GrpSeller' -Payload '<Group><Info><Name>GrpSeller</Name></Info><Subtype><Name>SellerNo</Name><Supertype>CustNo</Supertype></Subtype><Subtype><Name>SellerName</Name><Supertype>CustName</Supertype></Subtype></Group>')

    # Procedure PROCA: each `for each` line carries a unique // marker for its expected line.
    $procaCode = @'
For Each // c1
    Where CustName = &Name
    &Date = OrdDate
EndFor
for each CustNo // c2
    &Name = CustName
endfor
for each // c3
    &Date = OrdDate
    for each // c4
        &Qty = LineQty
    endfor
endfor
for each // c5
    defined by LineQty
    &Date = OrdDate
endfor
for each // c6
    where CustNo = &Cust
    &Name = CustName
when none
    &Prod = ProdName
endfor
for each // c7
    &Label = RegLabel
endfor
for each // c8
    &Prod = ProdName
    &Label = RegLabel
endfor
new
    OrdNo = &Ord
    for each // c9
        &Date = OrdDate
    endfor
endnew
for each // c10
    where SellerName = &Name
    &Date = OrdDate
endfor
for each // c11
    &Total = OrdTotal
endfor
for each // c16

    // the order clause follows
    order LineQty (OrdDate)
    &Total = OrdTotal
endfor
for each // c17
    using DSLines(LineQty)
    &Date = OrdDate
endfor
'@
    $procaXml = New-ClassicXml -Type $procedureGuid -Name 'PROCA' -Payload "<Procedure><Info><Name>PROCA</Name></Info><Layout><Block><CodeBlock><Source><![CDATA[$procaCode]]></Source></CodeBlock></Block></Layout><Rules><![CDATA[parm(&Cust);]]></Rules></Procedure>"
    Write-Fixture 'Procedure' 'PROCA' $procaXml

    # Report RPTORD: code block, print block, code block, one element per line (GeneXus 8 shape).
    $rptPayload = @'
<Report>
  <Info>
    <Name>RPTORD</Name>
  </Info>
  <Layout>
    <Block>
      <CodeBlock>
        <Source><![CDATA[for each order OrdNo // c12]]></Source>
      </CodeBlock>
    </Block>
    <Block>
      <PrintBlock>
        <CtrlName>Detail</CtrlName>
      </PrintBlock>
      <Edit>
        <Font>
          <Name>Courier New</Name>
        </Font>
        <Id>7</Id>
        <Name>ProdName</Name>
      </Edit>
      <Edit>
        <Font>
          <Name>Courier New</Name>
        </Font>
        <Id>-3</Id>
        <Name>RegLabel</Name>
      </Edit>
    </Block>
    <Block>
      <CodeBlock>
        <Source><![CDATA[endfor]]></Source>
      </CodeBlock>
    </Block>
  </Layout>
</Report>
'@
    $rptXml = New-ClassicXml -Type 'gxlegacy/Report' -Name 'RPTORD' -Payload $rptPayload
    Write-Fixture 'Report' 'RPTORD' $rptXml

    $wpCode = @'
Event 'Load'
    for each // c13
        &Prod = ProdName
    endfor
EndEvent
Event 'Enter'
    For each line // c14
        &Qty = LineQty
    EndFor
    for each selected line // c15
        &Date = OrdDate
    endfor
EndEvent
'@
    $wpXml = New-ClassicXml -Type $workPanelGuid -Name 'WPNAV' -Payload "<WorkPanel><Info><Name>WPNAV</Name></Info><Events><![CDATA[$wpCode]]></Events></WorkPanel>"
    Write-Fixture 'WorkPanel' 'WPNAV' $wpXml

    $webPanelCode = "Event 'Start'`nfor each // c19`n    &Name = CustName`nendfor`nEndEvent"
    Write-Fixture 'WebPanel' 'WPCUST' (New-ClassicXml -Type $webPanelGuid -Name 'WPCUST' -Payload "<WebPanel><Info><Name>WPCUST</Name></Info><Events><![CDATA[$webPanelCode]]></Events></WebPanel>")

    $modernXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="ModernNav" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0f000000-0000-4000-8000-000000000001" name="ModernNav" type="$procedureGuid" description="Modern Procedure">
  <Part type="$procedureSourcePartGuid">
    <Source><![CDATA[for each
    &Date = OrdDate
endfor]]></Source>
  </Part>
</Object>
"@
    Write-Fixture 'Procedure' 'ModernNav' $modernXml

    $indexPath = Join-Path $tempRoot 'KbWorkspace/KbIntelligence/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force)
    & $buildScript -SourceRoot $kbObjectsPath -OutputPath $indexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex failed; exit $LASTEXITCODE"
    }

    # Expected inferred rows per source: "Table@marker".
    $expected = [ordered]@{
        'Procedure:PROCA'   = @('TORD@// c1', 'TCUST@// c2', 'TORD@// c3', 'TLIN@// c4', 'TLIN@// c5', 'TCUST@// c6', 'TORD@// c10', 'TORD@// c11', 'TLIN@// c16', 'TLIN@// c17')
        'Report:RPTORD'     = @('TLIN@// c12')
        'WorkPanel:WPNAV'   = @('TPROD@// c13')
        'Transaction:TrnUnit' = @('TPROD@// c18')
        'WebPanel:WPCUST'   = @('TCUST@// c19')
        'Procedure:ModernNav' = @()
    }
    foreach ($sourceKey in $expected.Keys) {
        $sourceType, $sourceName = $sourceKey -split ':', 2
        $xml = $written["$sourceType/$sourceName"]
        $expectedKeys = @($expected[$sourceKey] | ForEach-Object {
                $table, $marker = $_ -split '@', 2
                '{0}@{1}' -f $table, (Get-LineNumberOf -Text $xml -Needle $marker)
            } | Sort-Object)
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @{ Query = 'what-uses'; ObjectType = $sourceType; ObjectName = $sourceName }
        $rows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
        $actualKeys = @($rows | ForEach-Object { '{0}@{1}' -f $_.target_name, $_.line } | Sort-Object)
        if (($actualKeys -join ';') -cne ($expectedKeys -join ';')) {
            Add-Failure "[what-uses/$sourceKey] '$relationKind' rows should be '$($expectedKeys -join ';')'; got '$($actualKeys -join ';')'"
            continue
        }
        foreach ($row in $rows) {
            $rowLabel = "what-uses/$sourceKey/$($row.target_name)@$($row.line)"
            if ($row.target_type -cne 'Table') { Add-Failure "[$rowLabel] target_type should be 'Table'; got '$($row.target_type)'" }
            if ($row.extractor_rule -cne $rule) { Add-Failure "[$rowLabel] extractor_rule should be '$rule'; got '$($row.extractor_rule)'" }
            if ($row.evidence_role -cne $role) { Add-Failure "[$rowLabel] evidence_role should be '$role'; got '$($row.evidence_role)'" }
            if ($row.confidence -cne 'inferred') { Add-Failure "[$rowLabel] confidence should be 'inferred'; got '$($row.confidence)'" }
        }
    }

    # who-uses of a Table lists the inferred navigations of every source.
    $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @{ Query = 'who-uses'; ObjectType = 'Table'; ObjectName = 'TLIN' }
    $actual = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind } | ForEach-Object { '{0}:{1}' -f $_.source_type, $_.source_name } | Sort-Object -Unique)
    if (($actual -join ';') -cne 'Procedure:PROCA;Report:RPTORD') {
        Add-Failure "[who-uses/Table:TLIN] inferred sources should be 'Procedure:PROCA;Report:RPTORD'; got '$($actual -join ';')'"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceLegacyForEachBaseTableSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligenceLegacyForEachBaseTableSelfTest.ps1'
exit 0
