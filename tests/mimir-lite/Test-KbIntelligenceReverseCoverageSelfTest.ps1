#requires -Version 7.4
<#
.SYNOPSIS
    Reverse-relation answers (who-uses, impact-basic, functional-trace-basic, object-info)
    state their coverage when the index holds objects whose calls are not extracted.

.DESCRIPTION
    Builds two indexes from copies of the synthetic sample-kb fixture (tests/fixtures/sample-kb/,
    no real KB data):

    - corpus A: the fixture as checked in (it holds the mobile Panel InvoiceSummaryMobile, whose
      events call CalculateInvoiceTotal) plus one synthetic object each of mobile WorkWith,
      SmartDevicesApplication, OfflineDatabase, and BusinessProcessDiagram written by this test.
      Reverse answers must report coverage.complete=false and list those five types with their
      counts; the text output must carry exactly one coverage note line. Exit codes stay 0.
    - corpus B: the fixture without its Panel folder. Reverse answers must report
      coverage.complete=true with an empty list, and the text output carries no note line.

    Coverage is target-aware. For an Attribute target the scope is attribute_references: besides
    the structural Attribute relations (Transaction levels, Table keys and indexes) the index
    holds the WorkWithForWeb grid, filter, order, view and filter condition references and the
    code reads of Procedure, WebPanel, Transaction and DataProvider, so coverage is incomplete
    whenever the index holds any type whose attribute uses are not extracted, or a partly
    extracted type. Corpus A also holds one synthetic WorkWithForWeb whose grid and filter name two
    fixture attributes: it is listed under partially_extracted_source_types (extracted: grids,
    filters, orders, views, filter conditions; missing: captions, parameters, tab conditions,
    code), not under unextracted_source_types, and its relations appear in the answer; the
    fixture's Procedure, Transaction and WebPanel objects are listed there too, each with its
    extracted code reads and writes and missing parts, and so is one synthetic Transaction-output
    DataProvider whose item assigns InvoiceTotal (its write row appears in the answer and the
    text note describes it first). The synthetic mobile WorkWith is listed there as well
    (extracted: layouts, orders, search, break by, filters; missing: grid conditions, rules,
    events, captions), while it stays an unextracted call source, and so is the fixture's Panel
    (the same parts since extractor 23), also still an unextracted call source. Copies of the
    corpus A index whose extractor_signature_version is rewritten to 22, 17, 14, 13, 12 or removed
    stand for older indexes: each reports the Panel as not extracted, all but 22 also report the
    mobile WorkWith as not extracted, 14 and 13 also report
    DataProvider, Procedure, Transaction and WebPanel as not extracted, 13 also reports filter
    conditions as missing, 12 and a missing version report WorkWithForWeb as not extracted too.
    Corpus C holds only that WorkWithForWeb: an Attribute
    target reports complete=false with no unextracted type, and the note keeps only the partly
    extracted and structural parts. The note is built from the coverage entry's own extracted
    list. Corpus B (no call-source types) must still report
    the attribute gap, with its Procedure, Transaction and WebPanel as partly extracted and no
    WorkWithForWeb, while a Procedure target on corpus B
    stays complete with scope calls and an empty partly extracted list. The scope is chosen
    ignoring the case of --object-type, so a lowercase 'attribute' target still discloses the gap.

    Forward answers (what-uses) carry no coverage object. The engine's list of unextracted
    caller types must stay disjoint from the extractor's INDEXED_SOURCE_TYPES; every unextracted
    caller type must be on the unextracted or the partly extracted attribute-use list; the partly
    extracted attribute-use types must include WorkWith, WorkWithForWeb, Procedure, WebPanel,
    Transaction and DataProvider and stay disjoint from the unextracted attribute-use list.
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
$builderPy = Join-Path $scriptDir 'Build-KbIntelligenceIndex.py'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { $failures.Add($Message) }

# partially_extracted_source_types as "Type=count:extracted,.../missing,...;..." in list order.
function Format-PartialEntries($Coverage) {
    return (@($Coverage.partially_extracted_source_types | ForEach-Object {
                '{0}={1}:{2}/{3}' -f $_.type, $_.count, (@($_.extracted) -join ','), (@($_.missing) -join ',')
            }) -join ';')
}

function Invoke-Query {
    param([string]$IndexPath, [string[]]$Arguments)
    $output = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $IndexPath @Arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (@($output) -join "`n") }
}

function New-Index {
    param([string]$CorpusRoot, [string]$IndexPath)
    & $buildScript -SourceRoot $CorpusRoot -OutputPath $IndexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex failed for $CorpusRoot; exit $LASTEXITCODE"
    }
}

# Copies an index and rewrites its extractor_signature_version ("absent" deletes the row),
# standing for an index built by an older extractor.
function Copy-IndexWithExtractorVersion {
    param([string]$SourceIndexPath, [string]$IndexPath, [string]$Version)
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $IndexPath) -Force)
    Copy-Item -LiteralPath $SourceIndexPath -Destination $IndexPath
    $patchScript = @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
if sys.argv[2] != "absent":
    conn.execute("UPDATE metadata SET value = ? WHERE key = 'extractor_signature_version'", (sys.argv[2],))
else:
    conn.execute("DELETE FROM metadata WHERE key = 'extractor_signature_version'")
conn.commit()
conn.close()
'@
    $patchPath = Join-Path (Split-Path -Parent $IndexPath) 'patch-version.py'
    [System.IO.File]::WriteAllText($patchPath, $patchScript, (Get-Utf8NoBomEncoding))
    $output = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $patchPath $IndexPath $Version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not rewrite extractor_signature_version in ${IndexPath}: $(@($output) -join ' ')"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-reverse-coverage-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)

    if (-not (Test-Path -LiteralPath (Join-Path $sampleKbRoot 'Panel') -PathType Container)) {
        throw "sample-kb fixture must hold a Panel folder for this test: $sampleKbRoot"
    }

    # --- corpus A: fixture + synthetic mobile WorkWith, SmartDevicesApplication, OfflineDatabase, BusinessProcessDiagram ---
    $corpusA = Join-Path $tempRoot 'corpus-a'
    [void](New-Item -ItemType Directory -Path $corpusA -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $corpusA -Recurse
    $workWithDir = Join-Path $corpusA 'WorkWith'
    $sdAppDir = Join-Path $corpusA 'SmartDevicesApplication'
    $offlineDbDir = Join-Path $corpusA 'OfflineDatabase'
    $bpdDir = Join-Path $corpusA 'BusinessProcessDiagram'
    $workWithForWebDir = Join-Path $corpusA 'WorkWithForWeb'
    [void](New-Item -ItemType Directory -Path $workWithForWebDir -Force)
    [void](New-Item -ItemType Directory -Path $workWithDir -Force)
    [void](New-Item -ItemType Directory -Path $sdAppDir -Force)
    [void](New-Item -ItemType Directory -Path $offlineDbDir -Force)
    [void](New-Item -ItemType Directory -Path $bpdDir -Force)
    $workWithXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithDevicesInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="ccf275d3-b7db-4eca-a94b-8139389f4643" name="WorkWithDevicesInvoice" type="15cf49b5-fc38-4899-91b5-395d02d79889" description="Synthetic mobile Work With">
  <Source><![CDATA[
Event 'Recalculate'
  CalculateInvoiceTotal(&InvoiceId)
EndEvent
]]></Source>
</Object>
'@
    $sdAppXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="InvoiceMobileApp" moduleGuid="00000000-0000-0000-0000-000000000000" guid="5ae68dd9-bdb8-4c6d-ba37-71210da6430f" name="InvoiceMobileApp" type="9bdcc055-174e-4af6-96cb-a2ceef6c5f09" description="Synthetic Smart Devices application">
  <Source><![CDATA[
Event 'Totals'
  CalculateInvoiceTotal(&InvoiceId)
EndEvent
]]></Source>
</Object>
'@
    $offlineDbXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="InvoiceOfflineDatabase" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0b000000-0000-4000-8000-000000000001" name="InvoiceOfflineDatabase" type="70b6075c-331c-0000-0038-ac3b65316dd0" description="Synthetic Offline Database">
  <Source><![CDATA[
Event Start
  CalculateInvoiceTotal(&InvoiceId)
EndEvent
]]></Source>
</Object>
'@
    $bpdXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="InvoiceApproval" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0b000000-0000-4000-8000-000000000002" name="InvoiceApproval" type="b5f00807-9da8-4cf9-b408-7554f2b6a8ee" description="Synthetic Business Process Diagram">
  <Part type="5a51075a-e991-44a6-9e1e-84937cd973f3"><DiagramDocument version="1"><Properties><Property><Name>PWFTaskObject</Name><Value>Procedure:CalculateInvoiceTotal</Value></Property></Properties></DiagramDocument></Part>
</Object>
'@
    # Synthetic web Work With: a grid attribute (GUID-Name form) and a bare filter attribute.
    $workWithForWebXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithWebInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0b000000-0000-4000-8000-000000000003" name="WorkWithWebInvoice" type="78cecefe-be7d-4980-86ce-8d6e91fba04b" description="Synthetic web Work With">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1"><Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b" Version="1.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0b000000-0000-4000-8000-000000000004:1" name="Invoice">
    <selection>
      <attributes>
        <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceTotal" />
      </attributes>
      <filter>
        <attributes>
          <filterAttribute name="InvoiceDate" />
        </attributes>
      </filter>
    </selection>
  </level>
</instance>]]></Data></Part>
</Object>
'@
    # Synthetic DataProvider whose output is the Invoice Transaction: its item assigns InvoiceTotal
    # (a DataProvider Source write).
    $dataProviderXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="InvoiceSeed" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0b000000-0000-4000-8000-000000000005" name="InvoiceSeed" type="2a9e9aba-d2de-4801-ae7f-5e3819222daf" description="Synthetic Transaction-output data provider">
  <Part type="1d8aeb5a-6e98-45a7-92d2-d8de7384e432">
    <Source><![CDATA[InvoiceCollection
{
    Invoice
    {
        InvoiceTotal = &Total
    }
}
]]></Source>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>InvoiceSeed</Value>
    </Property>
    <Property>
      <Name>OutputSDT</Name>
      <Value>1db606f2-af09-4cf9-a3b5-b481519d28f6-Invoice</Value>
    </Property>
  </Properties>
</Object>
'@
    $dataProviderDir = Join-Path $corpusA 'DataProvider'
    [void](New-Item -ItemType Directory -Path $dataProviderDir -Force)
    [System.IO.File]::WriteAllText((Join-Path $dataProviderDir 'InvoiceSeed.xml'), $dataProviderXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $workWithForWebDir 'WorkWithWebInvoice.xml'), $workWithForWebXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $workWithDir 'WorkWithDevicesInvoice.xml'), $workWithXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $offlineDbDir 'InvoiceOfflineDatabase.xml'), $offlineDbXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $bpdDir 'InvoiceApproval.xml'), $bpdXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $sdAppDir 'InvoiceMobileApp.xml'), $sdAppXml, (Get-Utf8NoBomEncoding))
    $indexA = Join-Path $tempRoot 'index-a/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexA) -Force)
    New-Index -CorpusRoot $corpusA -IndexPath $indexA

    # --- corpus B: fixture without its Panel folder ---
    $corpusB = Join-Path $tempRoot 'corpus-b'
    [void](New-Item -ItemType Directory -Path $corpusB -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Where-Object { $_.Name -ne 'Panel' } | Copy-Item -Destination $corpusB -Recurse
    $indexB = Join-Path $tempRoot 'index-b/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexB) -Force)
    New-Index -CorpusRoot $corpusB -IndexPath $indexB

    # --- corpus C: only the synthetic WorkWithForWeb, no other object ---
    $corpusC = Join-Path $tempRoot 'corpus-c'
    [void](New-Item -ItemType Directory -Path (Join-Path $corpusC 'WorkWithForWeb') -Force)
    [System.IO.File]::WriteAllText((Join-Path $corpusC 'WorkWithForWeb/WorkWithWebInvoice.xml'), $workWithForWebXml, (Get-Utf8NoBomEncoding))
    $indexC = Join-Path $tempRoot 'index-c/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexC) -Force)
    New-Index -CorpusRoot $corpusC -IndexPath $indexC

    $expectedA = 'BusinessProcessDiagram=1;OfflineDatabase=1;Panel=1;SmartDevicesApplication=1;WorkWith=1'
    $expectedNoteTypes = @('BusinessProcessDiagram', 'OfflineDatabase', 'Panel', 'SmartDevicesApplication', 'WorkWith')
    $reverseQueries = @(
        @('--query', 'who-uses', '--object-type', 'Procedure', '--object-name', 'CalculateInvoiceTotal'),
        @('--query', 'impact-basic', '--object-type', 'Procedure', '--object-name', 'CalculateInvoiceTotal'),
        @('--query', 'functional-trace-basic', '--object-type', 'Procedure', '--object-name', 'CalculateInvoiceTotal'),
        @('--query', 'object-info', '--object-type', 'Procedure', '--object-name', 'CalculateInvoiceTotal')
    )

    foreach ($queryArgs in $reverseQueries) {
        $label = $queryArgs[1]

        # corpus A, JSON: incomplete coverage with the five unextracted types and their counts
        $run = Invoke-Query -IndexPath $indexA -Arguments (@($queryArgs) + @('--format', 'json'))
        if ($run.ExitCode -ne 0) {
            Add-Failure "[$label/A/json] exit should stay 0; got $($run.ExitCode): $($run.Text)"
            continue
        }
        $payload = $run.Text | ConvertFrom-Json
        if ($null -eq $payload.PSObject.Properties['coverage']) {
            Add-Failure "[$label/A/json] result has no coverage object"
        }
        else {
            if ($payload.coverage.complete -ne $false) {
                Add-Failure "[$label/A/json] coverage.complete should be false; got $($payload.coverage.complete)"
            }
            $actual = (@($payload.coverage.unextracted_source_types | ForEach-Object { '{0}={1}' -f $_.type, $_.count }) -join ';')
            if ($actual -ne $expectedA) {
                Add-Failure "[$label/A/json] unextracted_source_types should be '$expectedA'; got '$actual'"
            }
        }

        # corpus A, text: exactly one coverage note line naming the types
        $run = Invoke-Query -IndexPath $indexA -Arguments (@($queryArgs) + @('--format', 'text'))
        if ($run.ExitCode -ne 0) {
            Add-Failure "[$label/A/text] exit should stay 0; got $($run.ExitCode)"
        }
        $noteLines = @($run.Text -split "`n" | Where-Object { $_ -match '^coverage: incomplete' })
        if ($noteLines.Count -ne 1) {
            Add-Failure "[$label/A/text] expected exactly one 'coverage: incomplete' line; got $($noteLines.Count): $($run.Text)"
        }
        else {
            $missing = @($expectedNoteTypes | Where-Object { $noteLines[0] -notmatch ('\b{0}\b' -f [regex]::Escape($_)) })
            if ($missing.Count -gt 0) {
                Add-Failure "[$label/A/text] coverage note should name $($expectedNoteTypes -join ', '); missing $($missing -join ', '): $($noteLines[0])"
            }
        }

        # corpus B, JSON: complete coverage, empty list
        $run = Invoke-Query -IndexPath $indexB -Arguments (@($queryArgs) + @('--format', 'json'))
        if ($run.ExitCode -ne 0) {
            Add-Failure "[$label/B/json] exit should stay 0; got $($run.ExitCode)"
            continue
        }
        $payload = $run.Text | ConvertFrom-Json
        if ($null -eq $payload.PSObject.Properties['coverage']) {
            Add-Failure "[$label/B/json] result has no coverage object"
        }
        elseif ($payload.coverage.complete -ne $true -or @($payload.coverage.unextracted_source_types).Count -ne 0) {
            Add-Failure "[$label/B/json] coverage should be complete with an empty list; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
        }
        elseif ($null -eq $payload.coverage.PSObject.Properties['scope'] -or $payload.coverage.scope -ne 'calls') {
            Add-Failure "[$label/B/json] a non-Attribute target should report coverage.scope 'calls'; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
        }
        elseif ($null -eq $payload.coverage.PSObject.Properties['partially_extracted_source_types'] -or @($payload.coverage.partially_extracted_source_types).Count -ne 0) {
            Add-Failure "[$label/B/json] the calls scope should carry an empty partially_extracted_source_types list; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
        }

        # corpus B, text: no coverage note
        $run = Invoke-Query -IndexPath $indexB -Arguments (@($queryArgs) + @('--format', 'text'))
        if ($run.ExitCode -ne 0) {
            Add-Failure "[$label/B/text] exit should stay 0; got $($run.ExitCode)"
        }
        if (@($run.Text -split "`n" | Where-Object { $_ -match '^coverage:' }).Count -ne 0) {
            Add-Failure "[$label/B/text] complete coverage must print no coverage line: $($run.Text)"
        }
    }

    # The extracted WebPanel caller is still listed next to the coverage note.
    $run = Invoke-Query -IndexPath $indexA -Arguments @('--query', 'who-uses', '--object-type', 'Procedure', '--object-name', 'CalculateInvoiceTotal', '--format', 'json')
    if ($run.ExitCode -ne 0) {
        Add-Failure "[who-uses/A] exit should stay 0; got $($run.ExitCode)"
    }
    $payload = $run.Text | ConvertFrom-Json
    if (@($payload.results | Where-Object { $_.source_type -eq 'WebPanel' -and $_.source_name -eq 'CustomerView' }).Count -lt 1) {
        Add-Failure "[who-uses/A] WebPanel:CustomerView should still be listed as a caller"
    }

    # Attribute targets: structural relations, WorkWithForWeb references and code reads are
    # indexed, so coverage discloses every indexed type whose attribute uses are not extracted,
    # even without call-source types, and lists WorkWithForWeb, Procedure, WebPanel, Transaction
    # and DataProvider as partly extracted (an index built by the current extractor reads
    # WorkWithForWeb grids, filters, orders, views and filter conditions, the attribute reads of
    # Procedure Source, Rules and Events and DataProvider Source and Rules, and the unambiguous
    # writes: for each / new blocks, Transaction assignment rules, Transaction-output DataProvider
    # items; captions, parameters, tab conditions and pattern code, ambiguous writes, conditions,
    # layouts, WebForm bindings, SDT output items, Business Component members and code outside a
    # Part are not read).
    $wwfwExtracted = 'grids,filters,orders,views,filter conditions'
    $wwfwMissing = 'captions,parameters,tab conditions,code'
    $wwfwNotePart = 'grids, filters, orders, views and filter conditions are indexed, captions, parameters, tab conditions and code are not'
    $wwsdExtracted = 'layouts,orders,search,break by,filters'
    $wwsdMissing = 'grid conditions,rules,events,captions'
    $wwsdNotePart = 'layouts, orders, search, break by and filters are indexed, grid conditions, rules, events and captions are not'
    $procedurePart = 'Source reads,rule reads,block writes,condition reads/ambiguous writes,layout,Business Component members,code outside a Part'
    # An index older than 21 has not read the conditions yet: 'condition reads' leads missing.
    $procedurePartBefore21 = 'Source reads,rule reads,block writes/condition reads,ambiguous writes,layout,Business Component members,code outside a Part'
    $transactionPart = 'rule reads,rule writes,event reads,block writes/ambiguous writes,WebForm bindings,Business Component members,code outside a Part'
    $webPanelPart = 'rule reads,event reads,block writes,condition reads/ambiguous writes,WebForm bindings,Business Component members,code outside a Part'
    $webPanelPartBefore21 = 'rule reads,event reads,block writes/condition reads,ambiguous writes,WebForm bindings,Business Component members,code outside a Part'
    $dataProviderPart = 'Source reads,rule reads,Transaction item writes/SDT output items,Business Component members,code outside a Part'
    $procedureNotePart = 'Source reads, rule reads, block writes and condition reads are indexed, ambiguous writes, layout, Business Component members and code outside a Part are not'
    $dataProviderNotePart = 'Source reads, rule reads and Transaction item writes are indexed, SDT output items, Business Component members and code outside a Part are not'
    $codeTypes = @('DataProvider', 'Procedure', 'Transaction', 'WebPanel')
    # Counts are the checked-in fixture's objects (tests/fixtures/sample-kb/): one Procedure
    # (CalculateInvoiceTotal), three Transactions (Customer, Invoice, Product) and one WebPanel
    # (CustomerView); corpus A adds the one synthetic DataProvider (InvoiceSeed) and the one
    # WorkWithForWeb (WorkWithWebInvoice) written above.
    $expectedPartialB = "Procedure=1:$procedurePart;Transaction=3:$transactionPart;WebPanel=1:$webPanelPart"
    # Corpus A also holds the one synthetic mobile WorkWith (WorkWithDevicesInvoice); an index of
    # extractor 17 or older predates its attribute uses and lists it as not extracted.
    $expectedPartialB17 = "Procedure=1:$procedurePartBefore21;Transaction=3:$transactionPart;WebPanel=1:$webPanelPartBefore21"
    $expectedPartialA17 = "DataProvider=1:$dataProviderPart;$expectedPartialB17;WorkWithForWeb=1:$wwfwExtracted/$wwfwMissing"
    # Since extractor 23 the fixture's Panel (InvoiceSummaryMobile) is partly extracted too, with
    # the mobile WorkWith parts; an index of extractor 22 or older lists it as not extracted.
    $expectedPartialA22 = "DataProvider=1:$dataProviderPart;$expectedPartialB;WorkWith=1:$wwsdExtracted/$wwsdMissing;WorkWithForWeb=1:$wwfwExtracted/$wwfwMissing"
    $expectedPartialA = "DataProvider=1:$dataProviderPart;Panel=1:$wwsdExtracted/$wwsdMissing;$expectedPartialB;WorkWith=1:$wwsdExtracted/$wwsdMissing;WorkWithForWeb=1:$wwfwExtracted/$wwfwMissing"
    $attributeCases = @(
        [pscustomobject]@{ Corpus = 'A'; Index = $indexA; Name = 'InvoiceTotal'; MustList = @('BusinessProcessDiagram', 'OfflineDatabase', 'SmartDevicesApplication'); Partial = $expectedPartialA },
        [pscustomobject]@{ Corpus = 'A'; Index = $indexA; Name = 'InvoiceDate'; MustList = @('BusinessProcessDiagram', 'OfflineDatabase', 'SmartDevicesApplication'); Partial = $expectedPartialA },
        [pscustomobject]@{ Corpus = 'B'; Index = $indexB; Name = 'InvoiceTotal'; MustList = @(); Partial = $expectedPartialB }
    )
    foreach ($case in $attributeCases) {
        $label = "who-uses/Attribute:$($case.Name)/$($case.Corpus)"
        $run = Invoke-Query -IndexPath $case.Index -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $case.Name, '--format', 'json')
        if ($run.ExitCode -ne 0) {
            Add-Failure "[$label/json] exit should stay 0; got $($run.ExitCode): $($run.Text)"
            continue
        }
        $payload = $run.Text | ConvertFrom-Json
        if ($null -eq $payload.PSObject.Properties['coverage']) {
            Add-Failure "[$label/json] result has no coverage object"
            continue
        }
        if ($payload.coverage.complete -ne $false) {
            Add-Failure "[$label/json] coverage.complete should be false for an Attribute target; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
        }
        if ($null -eq $payload.coverage.PSObject.Properties['scope'] -or $payload.coverage.scope -ne 'attribute_references') {
            Add-Failure "[$label/json] coverage.scope should be 'attribute_references'; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
        }
        $listedTypes = @($payload.coverage.unextracted_source_types | ForEach-Object { $_.type })
        $missingTypes = @($case.MustList | Where-Object { $listedTypes -notcontains $_ })
        if ($missingTypes.Count -gt 0) {
            Add-Failure "[$label/json] unextracted_source_types should list $($case.MustList -join ', '); missing $($missingTypes -join ', ')"
        }
        $wronglyListed = @(@($codeTypes + 'Panel' + 'WorkWith' + 'WorkWithForWeb') | Where-Object { $listedTypes -contains $_ })
        if ($wronglyListed.Count -gt 0) {
            Add-Failure "[$label/json] partly extracted types must not be listed under unextracted_source_types: $($wronglyListed -join ', ')"
        }
        if ($null -eq $payload.coverage.PSObject.Properties['partially_extracted_source_types']) {
            Add-Failure "[$label/json] coverage has no partially_extracted_source_types list"
        }
        else {
            $actualPartial = Format-PartialEntries $payload.coverage
            if ($actualPartial -cne $case.Partial) {
                Add-Failure "[$label/json] partially_extracted_source_types should be '$($case.Partial)'; got '$actualPartial'"
            }
        }
        if ($case.Corpus -eq 'A') {
            $wwfwRows = @($payload.results | Where-Object { $_.source_type -eq 'WorkWithForWeb' -and $_.source_name -eq 'WorkWithWebInvoice' -and $_.relation_kind -eq 'workwith_references_attribute' })
            if ($wwfwRows.Count -ne 1) {
                Add-Failure "[$label/json] WorkWithForWeb:WorkWithWebInvoice should be listed once as workwith_references_attribute; got $($wwfwRows.Count)"
            }
        }
        if ($case.Corpus -eq 'A' -and $case.Name -eq 'InvoiceTotal') {
            # The synthetic Transaction-output DataProvider assigns InvoiceTotal: one write row.
            $dpRows = @($payload.results | Where-Object { $_.source_type -eq 'DataProvider' -and $_.source_name -eq 'InvoiceSeed' -and $_.relation_kind -eq 'code_references_attribute' })
            if ($dpRows.Count -ne 1 -or $dpRows[0].evidence_role -ne 'DataProvider Source write') {
                Add-Failure "[$label/json] DataProvider:InvoiceSeed should be listed once as code_references_attribute with role 'DataProvider Source write'; got $(@($dpRows | ForEach-Object { $_.evidence_role }) -join ', ')"
            }
        }

        $run = Invoke-Query -IndexPath $case.Index -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $case.Name, '--format', 'text')
        if ($run.ExitCode -ne 0) {
            Add-Failure "[$label/text] exit should stay 0; got $($run.ExitCode)"
        }
        $noteLines = @($run.Text -split "`n" | Where-Object { $_ -match '^coverage: incomplete' })
        if ($noteLines.Count -ne 1) {
            Add-Failure "[$label/text] expected exactly one 'coverage: incomplete' line; got $($noteLines.Count): $($run.Text)"
        }
        elseif ($noteLines[0] -notmatch 'attribute uses' -or $noteLines[0] -notmatch 'only structural relations' -or $noteLines[0] -match 'calls made from') {
            Add-Failure "[$label/text] the note should describe unextracted attribute uses and structural-only relations: $($noteLines[0])"
        }
        elseif (-not $noteLines[0].Contains("Procedure (1): $procedureNotePart")) {
            Add-Failure "[$label/text] the note should describe Procedure (1) as partly extracted: $($noteLines[0])"
        }
        elseif ($case.Corpus -eq 'A' -and -not $noteLines[0].Contains("partly extracted from DataProvider (1): $dataProviderNotePart; Panel (1): $wwsdNotePart; Procedure (1)")) {
            Add-Failure "[$label/text] the note should describe DataProvider (1) and then Panel (1) as partly extracted, before Procedure: $($noteLines[0])"
        }
        elseif ($case.Corpus -eq 'B' -and -not $noteLines[0].Contains("partly extracted from Procedure (1): $procedureNotePart")) {
            Add-Failure "[$label/text] corpus B holds no DataProvider; the partly extracted list should start with Procedure (1): $($noteLines[0])"
        }
        elseif ($case.Corpus -eq 'A' -and -not $noteLines[0].Contains("WorkWithForWeb (1): $wwfwNotePart")) {
            Add-Failure "[$label/text] the note should describe WorkWithForWeb (1) as partly extracted: $($noteLines[0])"
        }
        elseif ($case.Corpus -eq 'A' -and -not $noteLines[0].Contains("WorkWith (1): $wwsdNotePart")) {
            Add-Failure "[$label/text] the note should describe the mobile WorkWith (1) as partly extracted: $($noteLines[0])"
        }
        elseif ($case.Corpus -eq 'B' -and $noteLines[0] -match 'WorkWithForWeb') {
            Add-Failure "[$label/text] corpus B holds no WorkWithForWeb; the note must not mention it: $($noteLines[0])"
        }
    }

    # A differently cased Attribute type still gets the attribute_references disclosure.
    # Object types match case-sensitively in who-uses (only names ignore case), so 'attribute'
    # finds no relation rows; the empty list must still carry the attribute gap instead of
    # falling back to the calls scope, which on corpus B (no call-source types) reads complete.
    $label = 'who-uses/attribute(lowercase):InvoiceTotal/B'
    $run = Invoke-Query -IndexPath $indexB -Arguments @('--query', 'who-uses', '--object-type', 'attribute', '--object-name', 'InvoiceTotal', '--format', 'json')
    if ($run.ExitCode -ne 0) {
        Add-Failure "[$label/json] exit should stay 0; got $($run.ExitCode): $($run.Text)"
    }
    else {
        $payload = $run.Text | ConvertFrom-Json
        if ($payload.total -ne 0) {
            Add-Failure "[$label/json] object types match case-sensitively, so a lowercase type should return no rows; got total $($payload.total)"
        }
        if ($null -eq $payload.PSObject.Properties['coverage']) {
            Add-Failure "[$label/json] result has no coverage object"
        }
        elseif ($payload.coverage.scope -ne 'attribute_references' -or $payload.coverage.complete -ne $false) {
            Add-Failure "[$label/json] coverage should be scope 'attribute_references' with complete=false; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
        }
    }

    # Only partly extracted types indexed: the note keeps the partly extracted and the structural
    # parts and drops the "not extracted" part. Attribute and Transaction are on the unextracted
    # list, so any corpus holding the target attribute (or a Transaction) lists them; the shape is
    # reachable only for an Attribute absent from the index, as in corpus C (one WorkWithForWeb).
    $label = 'who-uses/Attribute:InvoiceTotal/C'
    $run = Invoke-Query -IndexPath $indexC -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', 'InvoiceTotal', '--format', 'json')
    if ($run.ExitCode -ne 0) {
        Add-Failure "[$label/json] exit should stay 0; got $($run.ExitCode): $($run.Text)"
    }
    else {
        $payload = $run.Text | ConvertFrom-Json
        if ($null -eq $payload.PSObject.Properties['coverage']) {
            Add-Failure "[$label/json] result has no coverage object"
        }
        else {
            $coverage = $payload.coverage
            $partial = @($coverage.partially_extracted_source_types)
            if ($coverage.complete -ne $false -or $coverage.scope -ne 'attribute_references' -or @($coverage.unextracted_source_types).Count -ne 0) {
                Add-Failure "[$label/json] coverage should be scope 'attribute_references', complete=false, with no unextracted type; got $($coverage | ConvertTo-Json -Compress -Depth 4)"
            }
            elseif ($partial.Count -ne 1 -or $partial[0].type -ne 'WorkWithForWeb' -or $partial[0].count -ne 1) {
                Add-Failure "[$label/json] partially_extracted_source_types should hold WorkWithForWeb once with count 1; got $($coverage | ConvertTo-Json -Compress -Depth 4)"
            }
        }
    }
    $run = Invoke-Query -IndexPath $indexC -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', 'InvoiceTotal', '--format', 'text')
    $expectedNoteC = "coverage: incomplete - attribute uses are partly extracted from WorkWithForWeb (1): $wwfwNotePart; otherwise only structural relations (Transaction levels, Table keys and indexes) are indexed, so an empty or short list does not prove the attribute is unused"
    $noteLines = @($run.Text -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match '^coverage:' })
    if ($run.ExitCode -ne 0) {
        Add-Failure "[$label/text] exit should stay 0; got $($run.ExitCode)"
    }
    elseif ($noteLines.Count -ne 1 -or $noteLines[0] -cne $expectedNoteC) {
        Add-Failure "[$label/text] expected exactly the note '$expectedNoteC'; got: $($noteLines -join ' | ')"
    }

    # The partly extracted claims follow the index's extractor_signature_version: version 13
    # indexed the WorkWithForWeb grids, filters, orders and views, version 14 added its filter
    # conditions, version 15 the code reads and writes of Procedure, WebPanel, Transaction and
    # DataProvider (corpus A holds one of each, so 14 lists all four as not extracted), version 18
    # the mobile WorkWith layouts, orders, search, break by and filters (17 and older list it as
    # not extracted), version 23 the same parts of the Panel (22 and older list it as not
    # extracted).
    # An older index (or one without the version) reports a type whose parts it predates as not
    # extracted, never as partly extracted.
    $versionCases = @(
        [pscustomobject]@{ Version = '22'; Partial = $expectedPartialA22; Unextracted = @('Panel') },
        [pscustomobject]@{ Version = '17'; Partial = $expectedPartialA17; Unextracted = @('Panel', 'WorkWith', 'Attribute') },
        [pscustomobject]@{ Version = '14'; Partial = "WorkWithForWeb=1:$wwfwExtracted/$wwfwMissing"; Unextracted = @($codeTypes + 'WorkWith' + 'Attribute') },
        [pscustomobject]@{ Version = '13'; Partial = "WorkWithForWeb=1:grids,filters,orders,views/filter conditions,$wwfwMissing"; Unextracted = @($codeTypes + 'WorkWith' + 'Attribute') },
        [pscustomobject]@{ Version = '12'; Partial = ''; Unextracted = @($codeTypes + 'WorkWith' + 'WorkWithForWeb' + 'Attribute') },
        [pscustomobject]@{ Version = 'absent'; Partial = ''; Unextracted = @($codeTypes + 'WorkWith' + 'WorkWithForWeb' + 'Attribute') }
    )
    foreach ($versionCase in $versionCases) {
        $label = "who-uses/Attribute:InvoiceTotal/A@extractor-$($versionCase.Version)"
        $versionIndex = Join-Path $tempRoot "index-a-$($versionCase.Version)/kb-intelligence.sqlite"
        Copy-IndexWithExtractorVersion -SourceIndexPath $indexA -IndexPath $versionIndex -Version $versionCase.Version
        $run = Invoke-Query -IndexPath $versionIndex -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', 'InvoiceTotal', '--format', 'json')
        if ($run.ExitCode -ne 0) {
            Add-Failure "[$label/json] exit should stay 0; got $($run.ExitCode): $($run.Text)"
            continue
        }
        $coverage = ($run.Text | ConvertFrom-Json).coverage
        $actualPartial = Format-PartialEntries $coverage
        if ($actualPartial -cne $versionCase.Partial) {
            Add-Failure "[$label/json] partially_extracted_source_types should be '$($versionCase.Partial)'; got '$actualPartial'"
        }
        $listedTypes = @($coverage.unextracted_source_types | ForEach-Object { $_.type })
        $notListed = @($versionCase.Unextracted | Where-Object { $listedTypes -notcontains $_ })
        if ($notListed.Count -gt 0) {
            Add-Failure "[$label/json] unextracted_source_types should list $($versionCase.Unextracted -join ', '); missing $($notListed -join ', ')"
        }
    }

    # The note describes the extracted parts from the coverage result, not from a constant.
    $noteScript = @'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("kb_query_engine", sys.argv[1])
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
note = engine.format_coverage_note({"coverage": {
    "complete": False,
    "scope": engine.COVERAGE_SCOPE_ATTRIBUTE_REFERENCES,
    "unextracted_source_types": [],
    "partially_extracted_source_types": [
        {"type": "WorkWithForWeb", "count": 2, "extracted": ["grids", "views"], "missing": ["conditions"]}
    ],
}})
print(note)
'@
    $notePath = Join-Path $tempRoot 'note.py'
    [System.IO.File]::WriteAllText($notePath, $noteScript, (Get-Utf8NoBomEncoding))
    $noteOutput = (@(& $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $notePath $queryScript 2>&1) -join "`n").Trim()
    if ($LASTEXITCODE -ne 0 -or $noteOutput -notmatch 'partly extracted from WorkWithForWeb \(2\): grids and views are indexed, conditions are not;') {
        Add-Failure "[format_coverage_note] the note should name the extracted parts carried by the coverage entry (grids and views); got: $noteOutput"
    }

    # Forward answers carry no coverage object.
    $run = Invoke-Query -IndexPath $indexA -Arguments @('--query', 'what-uses', '--object-type', 'WebPanel', '--object-name', 'CustomerView', '--format', 'json')
    $payload = $run.Text | ConvertFrom-Json
    if ($null -ne $payload.PSObject.Properties['coverage']) {
        Add-Failure "[what-uses/A] a forward answer must not carry a coverage object"
    }

    # The engine's unextracted caller types never overlap the extractor's Source scope.
    $parityScript = @'
import ast, importlib.util, sys
engine_path, builder_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("kb_query_engine", engine_path)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
indexed = None
for node in ast.parse(open(builder_path, encoding="utf-8").read()).body:
    if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == "INDEXED_SOURCE_TYPES" for t in node.targets):
        indexed = set(ast.literal_eval(node.value))
if indexed is None:
    print("INDEXED_SOURCE_TYPES not found"); sys.exit(1)
unextracted = set(engine.UNEXTRACTED_CALL_SOURCE_TYPES)
overlap = sorted(unextracted & indexed)
print("overlap=" + ",".join(overlap))
attribute_uses = set(getattr(engine, "UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES", ()))
partial = set(getattr(engine, "PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES", {}))
missing = sorted(unextracted - attribute_uses - partial)
print("attribute_list_missing=" + ",".join(missing))
partial_overlap = sorted(partial & attribute_uses)
print("partial_overlap=" + ",".join(partial_overlap))
code_types = {"WorkWith", "WorkWithForWeb", "Procedure", "WebPanel", "Transaction", "DataProvider"}
print("partial_missing=" + ",".join(sorted(code_types - partial)))
sys.exit(1 if overlap or not unextracted or missing or partial_overlap or not code_types <= partial else 0)
'@
    $parityPath = Join-Path $tempRoot 'parity.py'
    [System.IO.File]::WriteAllText($parityPath, $parityScript, (Get-Utf8NoBomEncoding))
    $parityOutput = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $parityPath $queryScript $builderPy 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "UNEXTRACTED_CALL_SOURCE_TYPES must exist, be non-empty and stay disjoint from INDEXED_SOURCE_TYPES; every type in it must be in UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES or PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES; PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES must include WorkWith, WorkWithForWeb, Procedure, WebPanel, Transaction and DataProvider and stay disjoint from the unextracted list: $(@($parityOutput) -join ' ')"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceReverseCoverageSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligenceReverseCoverageSelfTest.ps1'
exit 0
