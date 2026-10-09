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

    Coverage is target-aware. For an Attribute target the scope is attribute_references: the
    index holds only structural Attribute relations (Transaction levels, Table keys and indexes),
    so coverage is incomplete whenever the index holds any type whose attribute uses are not
    extracted. Corpus A also holds one synthetic WorkWithForWeb whose grid and filter name two
    fixture attributes; corpus B (no call-source types) must still report the attribute gap,
    while a Procedure target on corpus B stays complete with scope calls. The scope is chosen
    ignoring the case of --object-type, so a lowercase 'attribute' target still discloses the gap.

    Forward answers (what-uses) carry no coverage object. The engine's list of unextracted
    caller types must stay disjoint from the extractor's INDEXED_SOURCE_TYPES; the attribute-use
    list must include every unextracted caller type.
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

    # Attribute targets: only structural relations are indexed, so coverage discloses every
    # indexed type whose attribute uses are not extracted, even without call-source types.
    $attributeCases = @(
        [pscustomobject]@{ Corpus = 'A'; Index = $indexA; Name = 'InvoiceTotal'; MustList = @('WorkWithForWeb', 'Procedure', 'WebPanel', 'Panel') },
        [pscustomobject]@{ Corpus = 'A'; Index = $indexA; Name = 'InvoiceDate'; MustList = @('WorkWithForWeb', 'Procedure', 'WebPanel', 'Panel') },
        [pscustomobject]@{ Corpus = 'B'; Index = $indexB; Name = 'InvoiceTotal'; MustList = @('Procedure', 'WebPanel') }
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
        if ($case.Corpus -eq 'A') {
            $wwfw = @($payload.coverage.unextracted_source_types | Where-Object { $_.type -eq 'WorkWithForWeb' })
            if ($wwfw.Count -ne 1 -or $wwfw[0].count -ne 1) {
                Add-Failure "[$label/json] WorkWithForWeb should be listed once with count 1"
            }
        }
        if ($case.Corpus -eq 'B' -and $listedTypes -contains 'WorkWithForWeb') {
            Add-Failure "[$label/json] corpus B holds no WorkWithForWeb; it must not be listed"
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
        elseif ($case.Corpus -eq 'A' -and $noteLines[0] -notmatch '\bWorkWithForWeb \(1\)') {
            Add-Failure "[$label/text] the note should name 'WorkWithForWeb (1)': $($noteLines[0])"
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
missing = sorted(unextracted - attribute_uses)
print("attribute_list_missing=" + ",".join(missing))
sys.exit(1 if overlap or not unextracted or missing or "WorkWithForWeb" not in attribute_uses else 0)
'@
    $parityPath = Join-Path $tempRoot 'parity.py'
    [System.IO.File]::WriteAllText($parityPath, $parityScript, (Get-Utf8NoBomEncoding))
    $parityOutput = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $parityPath $queryScript $builderPy 2>&1
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "UNEXTRACTED_CALL_SOURCE_TYPES must exist, be non-empty and stay disjoint from INDEXED_SOURCE_TYPES; UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES must include it and WorkWithForWeb: $(@($parityOutput) -join ' ')"
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
