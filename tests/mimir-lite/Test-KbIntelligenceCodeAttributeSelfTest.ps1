#requires -Version 7.4
<#
.SYNOPSIS
    GeneXus code Parts emit code_references_attribute relations (read and write roles) to the
    attributes their Procedure Source, Rules, Events and DataProvider Source name.

.DESCRIPTION
    Builds an index from a temporary copy of the synthetic sample-kb fixture
    (tests/fixtures/sample-kb/, no real KB data) plus synthetic Attribute, Domain and SDT objects
    and five code objects written by this test, all with their code inside <Part type="...">
    elements as a real export writes them:

    - Procedure CodeUsesProc: Source and Rules Parts, plus a Conditions and a Layout Part that
      this extractor does not read. The Source holds every tokenizer collision: block and line
      comments, string literals ('', "" and !""), &variables and &sdt.members, called objects
      (Name(...), Name.udp(...), the first argument of udp(...) and call(...)), for each heads
      (Movie.Actor, PurchasesInfo), Domain enumeration members (OrderStatus.Approved) and
      keywords named like attributes. The arguments of a call, a method receiver
      (MethodAttr.ToString()), the attributes after where, order and defined by, both sides of
      an assignment inside new ... endnew and a Domain-named attribute assigned an enumeration
      member (CompanyType = CompanyType.Startup) are uses. A name ending a line is not called by
      a '(' opening the next line. Write role: a statement-start 'Attr = expr' inside new ...
      endnew or for each ... endfor (nested, mixed-case keywords, inside if and do case) is a
      write; the when none / when duplicate branches, a plain 'for &i' loop and a top-level
      assignment are not write contexts (reads only); conditions and a compound assignment
      'Attr += 1' inside for each stay reads. A comment is whitespace: after a member and a
      comment, a statement-start assignment inside for each is still a write (CommentWriteAttr),
      and after a udp( opener and a comment the first argument is still the called object.
    - WebPanel CodeUsesPanel: Rules and Events Parts (Event 'Load', Event Grid1.Load,
      Event Enter, Sub/Do with quoted names, the Refresh and Load commands alone on their line,
      a top-level assignment that stays a read, a for each write, an assignment inside a value
      loop 'for &x in &coll' that stays a read), plus a Conditions and a WebForm Part (not read).
    - Transaction CodeUsesTrn: Rules and Events Parts naming one attribute in both (two rows,
      one per role), assignment rules 'Attr = expr [if ...];' (the target is a Rules write, also
      over two lines and as the rule opening the Part), a top-level Event assignment (a read),
      and an IsDefault=True Part without <Source>.
    - DataProvider CodeUsesTrnDp, output a Transaction (OutputSDT with the Transaction type
      GUID): group headers are not uses, item left sides are writes and right sides reads.
    - DataProvider CodeUsesSdtDp, output an SDT: group headers and item left sides (SDT item
      names) are not uses, right sides and order attributes are; its Rules Part is read.

    The fixture's own objects keep their code in a bare <Source> without <Part>: they produce no
    code_references_attribute row, and their other relations are the same with and without the
    objects this test adds.

    Assertions go through Query-KbIntelligenceIndex.py who-uses in JSON (relation kind, role,
    rule and evidence line), plus a direct SQLite comparison of the fixture objects' relations.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')
$pythonInterpreter = Get-GeneXusPythonExecutable
if ($null -eq $pythonInterpreter) {
    throw (Get-GeneXusPythonNotFoundMessage)
}

$sampleKbRoot = Join-Path $repoRoot 'tests/fixtures/sample-kb'
$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.py'
$relationKind = 'code_references_attribute'
$extractorRule = 'code_attribute_reference'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { $failures.Add($Message) }

function Invoke-QueryJson {
    param([string]$IndexPath, [string[]]$Arguments)
    $output = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $IndexPath @Arguments --format json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Query failed (exit $LASTEXITCODE) for $($Arguments -join ' '): $(@($output) -join "`n")"
    }
    return ((@($output) -join "`n") | ConvertFrom-Json)
}

function New-Index {
    param([string]$CorpusRoot, [string]$IndexPath)
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $IndexPath) -Force)
    & $buildScript -SourceRoot $CorpusRoot -OutputPath $IndexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex failed for $CorpusRoot; exit $LASTEXITCODE"
    }
}

# Relations whose source is one of the given objects, as sorted "type|name|kind|target_type|target" lines.
function Get-RelationLines {
    param([string]$IndexPath, [string[]]$SourceKeys)
    $script = @'
import json, sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
keys = set(json.loads(sys.argv[2]))
rows = conn.execute(
    "SELECT o.type, o.name, r.relation_kind, r.target_type, r.target_name "
    "FROM relations r JOIN objects o ON o.object_id = r.source_object_id"
).fetchall()
for row in sorted(r for r in rows if f"{r[0]}|{r[1]}" in keys):
    print("|".join(row))
'@
    $scriptPath = Join-Path $tempRoot 'relations.py'
    [System.IO.File]::WriteAllText($scriptPath, $script, (Get-Utf8NoBomEncoding))
    $keysJson = ConvertTo-Json -InputObject @($SourceKeys) -Compress
    $output = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $scriptPath $IndexPath $keysJson 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Relation listing failed for ${IndexPath}: $(@($output) -join ' ')"
    }
    return @($output | ForEach-Object { "$_".TrimEnd("`r") } | Where-Object { $_ })
}

$procedureXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="CodeUsesProc" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000001" name="CodeUsesProc" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="Synthetic procedure with code Parts">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Source><![CDATA[/* Block comment naming BlockNoteAttr
   and BlockNoteAttr again on its second line */
// Line comment naming LineNoteAttr
&Message = 'LiteralAttr' + "LiteralAttr // not a comment" + !"LiteralAttr"
&VarAttr = &Sdt.MemberAttr
&Total = CalledAttr(1) + CalledAttr.udp(2) + udp(UdpObjAttr, LegacyArgAttr) + call(UdpObjAttr, LegacyArgAttr)
&Total = CalculateInvoiceTotal(ArgAttr) + CalculateInvoiceTotal.udp(UdpArgAttr)
&Text = MethodAttr.ToString()
for each Movie.Actor
    where WhereAttr = &Key // marker: first WhereAttr
    order OrderAttr
    defined by DefinedAttr
    &Key = WhereAttr
endfor
for each PurchasesInfo
    if Where = 1 and not Like
    endif
endfor
&Status = OrderStatus.Approved
&Label = PriorityLevel.EnumerationDescription()
new
    AssignAttr = &Key
    CompanyType = CompanyType.Startup
when duplicate
    &Key = 0
endnew
do case
    case Each = 1
    otherwise
endcase
&Total = LineEndAttr
(&Total)
For Each NestedTable
    Where NestedKeyAttr = &Key
    NestedWriteAttr = NestedReadAttr + 1
    BothWaysAttr = BothWaysAttr + 1
    if NestedIfAttr = 1
        NestedIfWriteAttr = 2
    endif
    do case
        case NestedCaseAttr = 1
            NestedCaseWriteAttr = 3
    endcase
    for each InnerTable
        InnerWriteAttr = 4
    when none
        WhenNoneAttr = 5
    endFor
    New
        NewWriteAttr = NestedReadAttr
    When Duplicate
        DuplicateBranchAttr = 6
    EndNew
    AfterNewWriteAttr = 7
    exit
EndFor
TopLevelAttr = 8
for each OtherTable
    &Count += 1
    CompoundAttr += 1
endfor
for &i = 1 to 3
    LoopOnlyAttr = &i
endfor
for each CommentTable
    &Text = MethodAttr.ToString // a comment after a member
    CommentWriteAttr = 9
    &Total = udp( // a comment after the opener
        UdpObjAttr, CommentArgAttr)
endfor
]]></Source>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[parm(in:ProcParmAttr, out:&Result);
]]></Source>
  </Part>
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Source><![CDATA[ConditionOnlyAttr > 0;
]]></Source>
  </Part>
  <Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
    <Source><![CDATA[LayoutOnlyAttr
]]></Source>
  </Part>
</Object>
'@

$webPanelXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="CodeUsesPanel" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000002" name="CodeUsesPanel" type="c9584656-94b6-4ccd-890f-332d11fc2c25" description="Synthetic web panel with code Parts">
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[parm(in:PanelParmAttr);
]]></Source>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[Event 'Load'
    &Value = PanelEventAttr
EndEvent

Event Grid1.Load
    &Value = 1
EndEvent

Event Enter
    Do 'SubAttr'
EndEvent

Sub 'SubAttr'
    &Value = SubBodyAttr
EndSub

Event Refresh
    Refresh
    &Value = Refresh + 1
    EventTopAttr = 1
    if EventIfAttr = 1
    endif
    for each EventTable
        EventWriteAttr = &Value
    endfor
    for &Item in &Items
        ValueLoopAttr = &Item
    endfor
EndEvent

Event Load
    Load
EndEvent
]]></Source>
  </Part>
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Source><![CDATA[ConditionOnlyAttr > 0;
]]></Source>
  </Part>
  <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
    <Source><![CDATA[<table><tr><td>FormOnlyAttr</td></tr></table>]]></Source>
  </Part>
</Object>
'@

$transactionXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="CodeUsesTrn" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000003" name="CodeUsesTrn" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" description="Synthetic transaction with code Parts">
  <Level name="CodeUsesTrn" Type="CodeUsesTrn">
    <Attribute key="True">TrnKeyAttr</Attribute>
  </Level>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[TrnFirstAttr = &x if &Mode = 'INS';
noaccept(TrnBothAttr);
default(TrnRuleAttr, 1);
error('TrnErrorAttr') if TrnErrorAttr = 0;
TrnAssignAttr = &x if &Mode = 'INS';
TrnMultiAttr = TrnSourceAttr
    if TrnCondAttr = 1; parm(in:TrnParmAttr);
]]></Source>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[Event Start
    &Value = TrnBothAttr
    TrnEventAssignAttr = &Value
EndEvent
]]></Source>
  </Part>
  <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
    </Properties>
  </Part>
</Object>
'@

$transactionDataProviderXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="CodeUsesTrnDp" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000004" name="CodeUsesTrnDp" type="2a9e9aba-d2de-4801-ae7f-5e3819222daf" description="Synthetic Transaction-output data provider">
  <Part type="1d8aeb5a-6e98-45a7-92d2-d8de7384e432">
    <Source><![CDATA[CodeUsesTrnCollection
{
    TrnHeaderAttr
    {
        DpTrnLeftAttr = DpRightAttr
    }
}
]]></Source>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>CodeUsesTrnDp</Value>
    </Property>
    <Property>
      <Name>OutputSDT</Name>
      <Value>1db606f2-af09-4cf9-a3b5-b481519d28f6-CodeUsesTrn</Value>
    </Property>
    <Property>
      <Name>OutputCollection</Name>
      <Value>True</Value>
    </Property>
  </Properties>
</Object>
'@

$sdtDataProviderXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="CodeUsesSdtDp" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000005" name="CodeUsesSdtDp" type="2a9e9aba-d2de-4801-ae7f-5e3819222daf" description="Synthetic SDT-output data provider">
  <Part type="1d8aeb5a-6e98-45a7-92d2-d8de7384e432">
    <Source><![CDATA[RecipeList
{
    Recipes order DpOrderAttr {
        SdtItemAttr = DpSdtRightAttr
        RecipeTitle = Format("%1", Count(DpCountAttr,
            DpContinuationAttr = 1))
    }
}
]]></Source>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[parm(in:DpParmAttr);
]]></Source>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>CodeUsesSdtDp</Value>
    </Property>
    <Property>
      <Name>OutputSDT</Name>
      <Value>447527b5-9210-4523-898b-5dccb17be60a-RecipeList</Value>
    </Property>
  </Properties>
</Object>
'@

$sdtXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="RecipeList" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000006" name="RecipeList" type="447527b5-9210-4523-898b-5dccb17be60a" description="Synthetic SDT whose item is named like an attribute">
  <Level Name="RecipeList">
    <Item Name="Recipes" />
    <Item Name="SdtItemAttr" />
    <Item Name="RecipeTitle" />
  </Level>
</Object>
'@

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-code-attribute-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    # --- base corpus: the fixture alone ---
    $baseCorpus = Join-Path $tempRoot 'corpus-base'
    [void](New-Item -ItemType Directory -Path $baseCorpus -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $baseCorpus -Recurse
    $baseIndex = Join-Path $tempRoot 'index-base/kb-intelligence.sqlite'
    New-Index -CorpusRoot $baseCorpus -IndexPath $baseIndex

    # --- code corpus: the fixture plus the synthetic code objects ---
    $corpus = Join-Path $tempRoot 'corpus'
    [void](New-Item -ItemType Directory -Path $corpus -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $corpus -Recurse
    $writtenFiles = @{
        'Procedure/CodeUsesProc.xml'       = $procedureXml
        'WebPanel/CodeUsesPanel.xml'       = $webPanelXml
        'Transaction/CodeUsesTrn.xml'      = $transactionXml
        'DataProvider/CodeUsesTrnDp.xml'   = $transactionDataProviderXml
        'DataProvider/CodeUsesSdtDp.xml'   = $sdtDataProviderXml
        'SDT/RecipeList.xml'               = $sdtXml
    }
    foreach ($relativePath in $writtenFiles.Keys) {
        $path = Join-Path $corpus $relativePath
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
        [System.IO.File]::WriteAllText($path, $writtenFiles[$relativePath], (Get-Utf8NoBomEncoding))
    }
    # Domains used as enumerations; CompanyType, OrderStatus and PriorityLevel are also attributes.
    $domainNames = @('CompanyType', 'OrderStatus', 'PriorityLevel')
    for ($index = 0; $index -lt $domainNames.Count; $index++) {
        $domainXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="$($domainNames[$index])" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-0000000002$('{0:d2}' -f $index)" name="$($domainNames[$index])" type="00972a17-9975-449e-aab1-d26165d51393" description="Synthetic enumerated domain">
  <Properties>
    <Property><Name>DataType</Name><Value>Numeric</Value></Property>
  </Properties>
</Object>
"@
        [System.IO.File]::WriteAllText((Join-Path $corpus "Domain/$($domainNames[$index]).xml"), $domainXml, (Get-Utf8NoBomEncoding))
    }

    # Expected rows: source, attribute, role and the marker of the first line naming it.
    $expectedRows = @(
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'LegacyArgAttr'; Role = 'Procedure Source read'; Marker = 'udp(UdpObjAttr, LegacyArgAttr)' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'ArgAttr'; Role = 'Procedure Source read'; Marker = 'CalculateInvoiceTotal(ArgAttr)' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'UdpArgAttr'; Role = 'Procedure Source read'; Marker = 'CalculateInvoiceTotal(ArgAttr)' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'MethodAttr'; Role = 'Procedure Source read'; Marker = 'MethodAttr.ToString()' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'WhereAttr'; Role = 'Procedure Source read'; Marker = 'marker: first WhereAttr' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'OrderAttr'; Role = 'Procedure Source read'; Marker = 'order OrderAttr' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'DefinedAttr'; Role = 'Procedure Source read'; Marker = 'defined by DefinedAttr' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'PriorityLevel'; Role = 'Procedure Source read'; Marker = 'PriorityLevel.EnumerationDescription()' },
        # Assignment targets inside new ... endnew: writes; the Domain member on the right is not a use.
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'AssignAttr'; Role = 'Procedure Source write'; Marker = 'AssignAttr = &Key' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'CompanyType'; Role = 'Procedure Source write'; Marker = 'CompanyType = CompanyType.Startup' },
        # A name ending its line is not called by a '(' that opens the next line.
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'LineEndAttr'; Role = 'Procedure Source read'; Marker = '&Total = LineEndAttr' },
        # Nested for each / new blocks with mixed-case keywords: statement-start assignments are
        # writes (also inside if and do case), conditions and right sides are reads, the when none
        # and when duplicate branches and a plain for loop are not write contexts.
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NestedKeyAttr'; Role = 'Procedure Source read'; Marker = 'Where NestedKeyAttr = &Key' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NestedWriteAttr'; Role = 'Procedure Source write'; Marker = 'NestedWriteAttr = NestedReadAttr + 1' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NestedReadAttr'; Role = 'Procedure Source read'; Marker = 'NestedWriteAttr = NestedReadAttr + 1' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'BothWaysAttr'; Role = 'Procedure Source write'; Marker = 'BothWaysAttr = BothWaysAttr + 1' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'BothWaysAttr'; Role = 'Procedure Source read'; Marker = 'BothWaysAttr = BothWaysAttr + 1' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NestedIfAttr'; Role = 'Procedure Source read'; Marker = 'if NestedIfAttr = 1' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NestedIfWriteAttr'; Role = 'Procedure Source write'; Marker = 'NestedIfWriteAttr = 2' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NestedCaseAttr'; Role = 'Procedure Source read'; Marker = 'case NestedCaseAttr = 1' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NestedCaseWriteAttr'; Role = 'Procedure Source write'; Marker = 'NestedCaseWriteAttr = 3' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'InnerWriteAttr'; Role = 'Procedure Source write'; Marker = 'InnerWriteAttr = 4' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'WhenNoneAttr'; Role = 'Procedure Source read'; Marker = 'WhenNoneAttr = 5' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'NewWriteAttr'; Role = 'Procedure Source write'; Marker = 'NewWriteAttr = NestedReadAttr' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'DuplicateBranchAttr'; Role = 'Procedure Source read'; Marker = 'DuplicateBranchAttr = 6' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'AfterNewWriteAttr'; Role = 'Procedure Source write'; Marker = 'AfterNewWriteAttr = 7' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'TopLevelAttr'; Role = 'Procedure Source read'; Marker = 'TopLevelAttr = 8' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'LoopOnlyAttr'; Role = 'Procedure Source read'; Marker = 'LoopOnlyAttr = &i' },
        # A compound assignment 'Attr += 1' inside for each is not an unambiguous write: read only.
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'CompoundAttr'; Role = 'Procedure Source read'; Marker = 'CompoundAttr += 1' },
        # A comment is whitespace: the line after it is read with the tokens before it, so a
        # statement-start assignment after a member and a comment is a write, and the object named
        # first in a udp( opener followed by a comment stays a called object (UdpObjAttr, negative).
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'CommentWriteAttr'; Role = 'Procedure Source write'; Marker = 'CommentWriteAttr = 9' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'CommentArgAttr'; Role = 'Procedure Source read'; Marker = 'UdpObjAttr, CommentArgAttr)' },
        [pscustomobject]@{ Source = 'Procedure:CodeUsesProc'; File = 'Procedure/CodeUsesProc.xml'; Attribute = 'ProcParmAttr'; Role = 'Rules read'; Marker = 'parm(in:ProcParmAttr' },
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'PanelParmAttr'; Role = 'Rules read'; Marker = 'parm(in:PanelParmAttr)' },
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'PanelEventAttr'; Role = 'Events read'; Marker = '&Value = PanelEventAttr' },
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'SubBodyAttr'; Role = 'Events read'; Marker = '&Value = SubBodyAttr' },
        # The Refresh command alone on its line is not a use; Refresh inside an expression is.
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'Refresh'; Role = 'Events read'; Marker = '&Value = Refresh + 1' },
        # A top-level assignment in an Event is a read only; inside for each it is a write.
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'EventTopAttr'; Role = 'Events read'; Marker = 'EventTopAttr = 1' },
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'EventIfAttr'; Role = 'Events read'; Marker = 'if EventIfAttr = 1' },
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'EventWriteAttr'; Role = 'Events write'; Marker = 'EventWriteAttr = &Value' },
        # A value loop 'for &x in &coll' (not a for each) is not a write context: read only.
        [pscustomobject]@{ Source = 'WebPanel:CodeUsesPanel'; File = 'WebPanel/CodeUsesPanel.xml'; Attribute = 'ValueLoopAttr'; Role = 'Events read'; Marker = 'ValueLoopAttr = &Item' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnBothAttr'; Role = 'Rules read'; Marker = 'noaccept(TrnBothAttr)' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnBothAttr'; Role = 'Events read'; Marker = '&Value = TrnBothAttr' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnRuleAttr'; Role = 'Rules read'; Marker = 'default(TrnRuleAttr, 1)' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnErrorAttr'; Role = 'Rules read'; Marker = "if TrnErrorAttr = 0" },
        # Transaction assignment rules: the rule's target is a write, its value and condition reads;
        # the rule opening the Rules Part (its first token) counts as a rule start.
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnFirstAttr'; Role = 'Rules write'; Marker = "TrnFirstAttr = &x if &Mode = 'INS';" },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnAssignAttr'; Role = 'Rules write'; Marker = "TrnAssignAttr = &x if &Mode = 'INS';" },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnMultiAttr'; Role = 'Rules write'; Marker = 'TrnMultiAttr = TrnSourceAttr' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnSourceAttr'; Role = 'Rules read'; Marker = 'TrnMultiAttr = TrnSourceAttr' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnCondAttr'; Role = 'Rules read'; Marker = 'if TrnCondAttr = 1;' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnParmAttr'; Role = 'Rules read'; Marker = 'parm(in:TrnParmAttr)' },
        [pscustomobject]@{ Source = 'Transaction:CodeUsesTrn'; File = 'Transaction/CodeUsesTrn.xml'; Attribute = 'TrnEventAssignAttr'; Role = 'Events read'; Marker = 'TrnEventAssignAttr = &Value' },
        # Transaction output: an item's left side is a write, its right side a read.
        [pscustomobject]@{ Source = 'DataProvider:CodeUsesTrnDp'; File = 'DataProvider/CodeUsesTrnDp.xml'; Attribute = 'DpTrnLeftAttr'; Role = 'DataProvider Source write'; Marker = 'DpTrnLeftAttr = DpRightAttr' },
        [pscustomobject]@{ Source = 'DataProvider:CodeUsesTrnDp'; File = 'DataProvider/CodeUsesTrnDp.xml'; Attribute = 'DpRightAttr'; Role = 'DataProvider Source read'; Marker = 'DpTrnLeftAttr = DpRightAttr' },
        [pscustomobject]@{ Source = 'DataProvider:CodeUsesSdtDp'; File = 'DataProvider/CodeUsesSdtDp.xml'; Attribute = 'DpOrderAttr'; Role = 'DataProvider Source read'; Marker = 'Recipes order DpOrderAttr' },
        [pscustomobject]@{ Source = 'DataProvider:CodeUsesSdtDp'; File = 'DataProvider/CodeUsesSdtDp.xml'; Attribute = 'DpSdtRightAttr'; Role = 'DataProvider Source read'; Marker = 'SdtItemAttr = DpSdtRightAttr' },
        [pscustomobject]@{ Source = 'DataProvider:CodeUsesSdtDp'; File = 'DataProvider/CodeUsesSdtDp.xml'; Attribute = 'DpCountAttr'; Role = 'DataProvider Source read'; Marker = 'Count(DpCountAttr,' },
        [pscustomobject]@{ Source = 'DataProvider:CodeUsesSdtDp'; File = 'DataProvider/CodeUsesSdtDp.xml'; Attribute = 'DpContinuationAttr'; Role = 'DataProvider Source read'; Marker = 'DpContinuationAttr = 1))' },
        # DataProvider Rules are read.
        [pscustomobject]@{ Source = 'DataProvider:CodeUsesSdtDp'; File = 'DataProvider/CodeUsesSdtDp.xml'; Attribute = 'DpParmAttr'; Role = 'Rules read'; Marker = 'parm(in:DpParmAttr)' }
    )
    # Attributes named only in places that are not uses (comments, literals, variables, members,
    # called objects, for each heads, Domain members, keywords, Event and Sub headers, the Load
    # command alone on its line, parts this extractor does not read, DataProvider group headers,
    # SDT-output item names) or only in the fixture's bare <Source>.
    $negativeAttributes = @(
        'BlockNoteAttr', 'LineNoteAttr', 'LiteralAttr', 'VarAttr', 'MemberAttr', 'CalledAttr', 'UdpObjAttr',
        'Movie', 'Actor', 'PurchasesInfo', 'OrderStatus', 'Startup', 'Approved',
        'NestedTable', 'InnerTable', 'OtherTable', 'EventTable', 'CommentTable',
        'Where', 'Like', 'Each', 'Not', 'Duplicate', 'Case', 'Otherwise', 'In', 'Out', 'None', 'Exit',
        'Grid1', 'Load', 'Enter', 'Start', 'SubAttr',
        'ConditionOnlyAttr', 'LayoutOnlyAttr', 'FormOnlyAttr',
        'CodeUsesTrnCollection', 'TrnHeaderAttr', 'RecipeList', 'Recipes', 'SdtItemAttr', 'RecipeTitle'
    )
    $positiveAttributes = @($expectedRows | ForEach-Object { $_.Attribute } | Where-Object { -not (Test-Path -LiteralPath (Join-Path $corpus "Attribute/$_.xml")) } | Sort-Object -Unique)
    $attributeNames = @($positiveAttributes + $negativeAttributes)
    for ($index = 0; $index -lt $attributeNames.Count; $index++) {
        $attributeXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$($attributeNames[$index])" guid="0d000000-0000-4000-8000-000000001$('{0:d3}' -f $index)" lastUpdate="2026-01-01T00:00:00" description="Synthetic code attribute">
  <Properties />
</Attribute>
"@
        [System.IO.File]::WriteAllText((Join-Path $corpus "Attribute/$($attributeNames[$index]).xml"), $attributeXml, (Get-Utf8NoBomEncoding))
    }
    $indexPath = Join-Path $tempRoot 'index/kb-intelligence.sqlite'
    New-Index -CorpusRoot $corpus -IndexPath $indexPath

    # Positive cases: exactly the expected (source, role) rows per attribute, at the first line
    # naming it in that Part (1-based, counted in the whole written XML file).
    $expectedByAttribute = $expectedRows | Group-Object -Property Attribute
    foreach ($group in $expectedByAttribute) {
        $attributeName = $group.Name
        $label = "who-uses/Attribute:$attributeName"
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $attributeName)
        $rows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
        $actualKeys = @($rows | ForEach-Object { '{0}:{1}|{2}' -f $_.source_type, $_.source_name, $_.evidence_role } | Sort-Object)
        $expectedKeys = @($group.Group | ForEach-Object { '{0}|{1}' -f $_.Source, $_.Role } | Sort-Object)
        if (($actualKeys -join ',') -cne ($expectedKeys -join ',')) {
            Add-Failure "[$label] '$relationKind' rows should be '$($expectedKeys -join ',')'; got '$($actualKeys -join ',')'"
            continue
        }
        foreach ($expected in $group.Group) {
            $row = @($rows | Where-Object { ('{0}:{1}' -f $_.source_type, $_.source_name) -eq $expected.Source -and $_.evidence_role -eq $expected.Role })[0]
            if ($row.target_name -cne $attributeName) {
                Add-Failure "[$label] target_name should use the inventory casing '$attributeName'; got '$($row.target_name)'"
            }
            if ($row.extractor_rule -cne $extractorRule) {
                Add-Failure "[$label] extractor_rule should be '$extractorRule'; got '$($row.extractor_rule)'"
            }
            $writtenLines = $writtenFiles[$expected.File] -split "`n"
            $expectedLine = 0
            for ($lineIndex = 0; $lineIndex -lt $writtenLines.Count; $lineIndex++) {
                if ($writtenLines[$lineIndex].Contains($expected.Marker)) { $expectedLine = $lineIndex + 1; break }
            }
            if ($expectedLine -eq 0) {
                throw "[$label] test marker '$($expected.Marker)' not found in $($expected.File)"
            }
            if ($row.line -ne $expectedLine) {
                Add-Failure "[$label/$($expected.Role)] evidence line should be $expectedLine; got $($row.line)"
            }
        }
    }

    # Negative cases: no code row at all, from any source.
    foreach ($attributeName in $negativeAttributes) {
        $label = "who-uses/Attribute:$attributeName"
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $attributeName)
        $rows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
        if ($rows.Count -ne 0) {
            Add-Failure "[$label] a mention that is not a use must not produce '$relationKind'; got $($rows.Count) row(s): $(@($rows | ForEach-Object { '{0}:{1} {2} line {3}' -f $_.source_type, $_.source_name, $_.evidence_role, $_.line }) -join ', ')"
        }
    }

    # The fixture keeps its code in a bare <Source> (no <Part>): no code row, e.g. for
    # InvoiceTotal, which the fixture procedure reads.
    $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', 'InvoiceTotal')
    $bareRows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
    if ($bareRows.Count -ne 0) {
        Add-Failure "[who-uses/Attribute:InvoiceTotal] a bare <Source> without <Part> must not be read by the code extractor; got $($bareRows.Count) row(s)"
    }

    # The fixture objects' relations are unchanged by the added objects, and the base index
    # holds no code row at all.
    $fixtureKeys = @(Get-ChildItem -LiteralPath $sampleKbRoot -Directory | ForEach-Object {
            $typeName = $_.Name
            Get-ChildItem -LiteralPath $_.FullName -Filter '*.xml' | ForEach-Object { '{0}|{1}' -f $typeName, $_.BaseName }
        })
    $baseLines = @(Get-RelationLines -IndexPath $baseIndex -SourceKeys $fixtureKeys)
    $codeLines = @(Get-RelationLines -IndexPath $indexPath -SourceKeys $fixtureKeys)
    if ($baseLines.Count -eq 0) {
        throw 'The fixture objects should have relations in the base index'
    }
    if (($baseLines -join "`n") -cne ($codeLines -join "`n")) {
        $added = @($codeLines | Where-Object { $baseLines -notcontains $_ })
        $removed = @($baseLines | Where-Object { $codeLines -notcontains $_ })
        Add-Failure "[fixture relations] should be unchanged; added: $($added -join '; '); removed: $($removed -join '; ')"
    }
    if (@($baseLines | Where-Object { $_ -match "\|$relationKind\|" }).Count -ne 0) {
        Add-Failure "[fixture relations] the base fixture must hold no '$relationKind' row"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceCodeAttributeSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligenceCodeAttributeSelfTest.ps1'
exit 0
