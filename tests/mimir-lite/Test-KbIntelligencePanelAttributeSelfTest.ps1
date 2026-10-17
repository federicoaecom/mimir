#requires -Version 7.4
<#
.SYNOPSIS
    Smart Devices Panel objects emit panel_references_attribute relations to the attributes
    their pattern instance layouts, orders, search, break by and advanced filters name.

.DESCRIPTION
    Builds an index from a temporary copy of the synthetic sample-kb fixture
    (tests/fixtures/sample-kb/, no real KB data, which already holds the Panel
    InvoiceSummaryMobile with no pattern instance) plus three objects written by this test:

    - Panel PanelDevicesInvoice, in the GeneXus 16 layout: its pattern instance
      (<Data Pattern="15cf49b5-...">, the same instance a mobile WorkWith carries) has a
      <level><detail> with a layout and a <gridData>. The layout names CustomerName and
      InvoiceTotal with <data attribute="...">, a variable (&amp;InvoiceNote) and GhostAttribute
      (not in the Attribute inventory); the gridData has an order with only a name (no
      attribute), an order on Quantity, a break by on LineNumber, a search on ProductName and
      customername (lowercase), and an advanced filter on InvoiceTotal. InvoiceTotal yields one
      row per role (layout and filter).
    - Panel PanelDevicesNotes, in the X Evolution 2 layout: its layout binds only variables, so
      it yields no row.
    - WorkWith PanelDevicesInvoice, a mobile Work With with the same name as the Panel, naming
      CustomerName in its layout: it keeps its own workwith_references_attribute row with the
      WorkWith role, and the Panel rows never mask it or the reverse.

    Assertions go through Query-KbIntelligenceIndex.py who-uses in JSON: for every attribute
    checked, the exact set of Panel rows (source name, evidence role), and for each its relation
    kind, extractor rule, inventory casing and the first line naming it in that role; the
    WorkWith row; and the coverage, which lists Panel as partly extracted (layouts, orders,
    search, break by and filters; grid conditions, rules, events and captions are not read) and
    no longer as a type whose attribute uses are not extracted.
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
$panelKind = 'panel_references_attribute'
$panelRule = 'sd_panel_attribute_reference'

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

# GeneXus 16: <level><detail> with a layout and a <gridData> (orders, breakBy, search, filter).
$invoicePanelXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="PanelDevicesInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0e000000-0000-4000-8000-000000000001" name="PanelDevicesInvoice" type="d82625fd-5892-40b0-99c9-5c8559c197fc" description="Synthetic Smart Devices panel, GeneXus 16 layout">
  <Part type="b4378a97-f9b2-4e05-b2f8-c610de258402">
    <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="16.0.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0e000000-0000-4000-8000-000000000010" name="Level">
    <detail rules="parm(&amp;InvoiceNote);&#xD;&#xA;">
      <layout id="0e000000-0000-4000-8000-000000000011" Type="Any Mode">
        <table id="0e000000-0000-4000-8000-000000000012" controlName="MainTable">
          <row id="0e000000-0000-4000-8000-000000000013">
            <cell id="0e000000-0000-4000-8000-000000000014">
              <data attribute="CustomerName" />
            </cell>
            <cell id="0e000000-0000-4000-8000-000000000015">
              <grid id="0e000000-0000-4000-8000-000000000016" controlName="Grid1">
                <table id="0e000000-0000-4000-8000-000000000017" controlName="Table1">
                  <row id="0e000000-0000-4000-8000-000000000018">
                    <cell id="0e000000-0000-4000-8000-000000000019">
                      <data attribute="InvoiceTotal" labelPosition="None" class="AttributeTitle" />
                    </cell>
                    <cell id="0e000000-0000-4000-8000-000000000020">
                      <data attribute="&amp;InvoiceNote" labelPosition="None" />
                    </cell>
                    <cell id="0e000000-0000-4000-8000-000000000021">
                      <data attribute="GhostAttribute" labelPosition="None" />
                    </cell>
                  </row>
                </table>
              </grid>
            </cell>
          </row>
        </table>
      </layout>
      <gridData name="Grid1" basetrn="Invoice&#xA;">
        <orders>
          <order name="ByName" />
          <order name="ByQuantity">
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-Quantity" description="Quantity" ascending="True" />
          </order>
        </orders>
        <breakBy>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-LineNumber" />
        </breakBy>
        <search>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-ProductName" />
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-customername" />
        </search>
        <filter>
          <advanced>
            <filterAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceTotal" description="Total" />
          </advanced>
        </filter>
      </gridData>
    </detail>
  </level>
</instance>]]></Data>
  </Part>
</Object>
'@

# X Evolution 2: a layout that binds only variables.
$notesPanelXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="PanelDevicesNotes" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0e000000-0000-4000-8000-000000000002" name="PanelDevicesNotes" type="d82625fd-5892-40b0-99c9-5c8559c197fc" description="Synthetic Smart Devices panel, X Evolution 2 layout">
  <Part type="b4378a97-f9b2-4e05-b2f8-c610de258402">
    <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="0.10.2"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0e000000-0000-4000-8000-000000000030" name="Level">
    <detail>
      <layout id="0e000000-0000-4000-8000-000000000031" Type="View">
        <table id="0e000000-0000-4000-8000-000000000032" controlName="MainTable">
          <row id="0e000000-0000-4000-8000-000000000033">
            <cell id="0e000000-0000-4000-8000-000000000034">
              <data attribute="&amp;CustomerName" labelPosition="None" />
            </cell>
          </row>
        </table>
      </layout>
    </detail>
  </level>
</instance>]]></Data>
  </Part>
</Object>
'@

# A mobile Work With with the same name as the Panel.
$workWithXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="PanelDevicesInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0e000000-0000-4000-8000-000000000003" name="PanelDevicesInvoice" type="15cf49b5-fc38-4899-91b5-395d02d79889" description="Synthetic mobile Work With sharing the Panel name">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1">
    <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="16.0.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0e000000-0000-4000-8000-000000000050" name="Invoice">
    <list caption="'Invoices'">
      <layout id="0e000000-0000-4000-8000-000000000051" Type="Any Mode">
        <table id="0e000000-0000-4000-8000-000000000052" controlName="MainTable">
          <row id="0e000000-0000-4000-8000-000000000053">
            <cell id="0e000000-0000-4000-8000-000000000054">
              <data attribute="CustomerName" labelPosition="None" />
            </cell>
          </row>
        </table>
      </layout>
    </list>
  </level>
</instance>]]></Data>
  </Part>
</Object>
'@

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-panel-attribute-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $corpus = Join-Path $tempRoot 'corpus'
    [void](New-Item -ItemType Directory -Path $corpus -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $corpus -Recurse
    $panelDir = Join-Path $corpus 'Panel'
    $workWithDir = Join-Path $corpus 'WorkWith'
    [void](New-Item -ItemType Directory -Path $workWithDir -Force)
    $invoicePanelPath = Join-Path $panelDir 'PanelDevicesInvoice.xml'
    [System.IO.File]::WriteAllText($invoicePanelPath, $invoicePanelXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $panelDir 'PanelDevicesNotes.xml'), $notesPanelXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $workWithDir 'PanelDevicesInvoice.xml'), $workWithXml, (Get-Utf8NoBomEncoding))

    $indexPath = Join-Path $tempRoot 'index/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force)
    & $buildScript -SourceRoot $corpus -OutputPath $indexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex failed; exit $LASTEXITCODE"
    }

    # Expected Panel rows per attribute: source name, role, and a marker whose first line in the
    # written Panel XML is the expected evidence line.
    $layout = 'Panel layout attribute'
    $order = 'Panel order attribute'
    $search = 'Panel search attribute'
    $breakBy = 'Panel break by attribute'
    $filter = 'Panel filter attribute'
    $expectedRows = @{
        CustomerName = @(
            @('PanelDevicesInvoice', $layout, '<data attribute="CustomerName" />'),
            @('PanelDevicesInvoice', $search, '-customername" />')
        )
        InvoiceTotal = @(
            @('PanelDevicesInvoice', $layout, '<data attribute="InvoiceTotal"'),
            @('PanelDevicesInvoice', $filter, '-InvoiceTotal" description="Total"')
        )
        LineNumber   = @(,@('PanelDevicesInvoice', $breakBy, '-LineNumber" />'))
        ProductName  = @(,@('PanelDevicesInvoice', $search, '-ProductName" />'))
        Quantity     = @(,@('PanelDevicesInvoice', $order, '-Quantity" description="Quantity"'))
        # Negatives: fixture attributes no Panel names. The variables &InvoiceNote and
        # &CustomerName (PanelDevicesNotes) give no row; the exact CustomerName set above pins the
        # second one.
        CustomerId   = @()
        InvoiceDate  = @()
    }
    $panelLines = ([System.IO.File]::ReadAllText($invoicePanelPath)) -split "`n"

    foreach ($attributeName in ($expectedRows.Keys | Sort-Object)) {
        $label = "who-uses/Attribute:$attributeName"
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $attributeName)
        $rows = @($payload.results | Where-Object { $_.source_type -eq 'Panel' })
        $expectedKeys = @($expectedRows[$attributeName] | ForEach-Object { 'Panel:{0}|{1}' -f $_[0], $_[1] } | Sort-Object)
        $actualKeys = @($rows | ForEach-Object { '{0}:{1}|{2}' -f $_.source_type, $_.source_name, $_.evidence_role } | Sort-Object)
        if (($actualKeys -join ';') -cne ($expectedKeys -join ';')) {
            Add-Failure "[$label] Panel rows should be '$($expectedKeys -join ';')'; got '$($actualKeys -join ';')'"
            continue
        }
        foreach ($expected in @($expectedRows[$attributeName])) {
            $sourceName, $role, $marker = $expected
            $row = @($rows | Where-Object { $_.source_name -eq $sourceName -and $_.evidence_role -eq $role })[0]
            $rowLabel = "$label/Panel:$sourceName/$role"
            if ($row.relation_kind -cne $panelKind) {
                Add-Failure "[$rowLabel] relation_kind should be '$panelKind'; got '$($row.relation_kind)'"
            }
            if ($row.extractor_rule -cne $panelRule) {
                Add-Failure "[$rowLabel] extractor_rule should be '$panelRule'; got '$($row.extractor_rule)'"
            }
            if ($row.target_name -cne $attributeName) {
                Add-Failure "[$rowLabel] target_name should use the inventory casing '$attributeName'; got '$($row.target_name)'"
            }
            $expectedLine = 0
            for ($index = 0; $index -lt $panelLines.Count; $index++) {
                if ($panelLines[$index].Contains($marker)) { $expectedLine = $index + 1; break }
            }
            if ($expectedLine -eq 0) {
                throw "[$rowLabel] test marker '$marker' not found in the written Panel XML"
            }
            if ($row.line -ne $expectedLine) {
                Add-Failure "[$rowLabel] evidence line should be $expectedLine (first line naming the attribute in that role); got $($row.line)"
            }
        }
    }

    # The mobile Work With with the same name keeps its own row, kind and role.
    $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', 'CustomerName')
    $workWithRows = @($payload.results | Where-Object { $_.source_type -eq 'WorkWith' -and $_.source_name -eq 'PanelDevicesInvoice' } |
            ForEach-Object { '{0}|{1}|{2}' -f $_.relation_kind, $_.extractor_rule, $_.evidence_role })
    $expectedWorkWith = 'workwith_references_attribute|workwith_sd_attribute_reference|WorkWith layout attribute'
    if (($workWithRows -join ';') -cne $expectedWorkWith) {
        Add-Failure "[who-uses/Attribute:CustomerName/WorkWith:PanelDevicesInvoice] rows should be '$expectedWorkWith'; got '$($workWithRows -join ';')'"
    }

    # Coverage: Panel (three objects: the fixture's InvoiceSummaryMobile and the two written here)
    # is partly extracted for attribute uses, and no longer listed as not extracted.
    $coverage = $payload.coverage
    $unextracted = @($coverage.unextracted_source_types | ForEach-Object { $_.type })
    if ($unextracted -contains 'Panel') {
        Add-Failure "[coverage] Panel must not be listed under unextracted_source_types; got $($unextracted -join ', ')"
    }
    $panelEntry = @($coverage.partially_extracted_source_types | Where-Object { $_.type -eq 'Panel' })
    $expectedEntry = 'Panel=3:layouts,orders,search,break by,filters/grid conditions,rules,events,captions'
    $actualEntry = @($panelEntry | ForEach-Object { '{0}={1}:{2}/{3}' -f $_.type, $_.count, (@($_.extracted) -join ','), (@($_.missing) -join ',') }) -join ';'
    if ($actualEntry -cne $expectedEntry) {
        Add-Failure "[coverage] partially_extracted_source_types should hold '$expectedEntry'; got '$actualEntry'"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligencePanelAttributeSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligencePanelAttributeSelfTest.ps1'
exit 0
