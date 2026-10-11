#requires -Version 7.4
<#
.SYNOPSIS
    Mobile WorkWith (WorkWith for Smart Devices) pattern instances emit
    workwith_references_attribute relations to the attributes their layouts, orders, search,
    break by and advanced filters name.

.DESCRIPTION
    Builds an index from a temporary copy of the synthetic sample-kb fixture
    (tests/fixtures/sample-kb/, no real KB data) plus two synthetic Attribute objects and four
    objects written by this test:

    - WorkWith WorkWithDevicesInvoice, in the X Evolution 2 layout (pattern version 0.10.2):
      orders, a self-closing <breakBy /> and <filter><search>/<advanced> sit directly under
      <list>. Its list grid names InvoiceId with <data attribute="...">, its orders InvoiceDate
      and CustomerName, its search CustomerName and customerid (lowercase), its advanced filter
      InvoiceTotal, and its detail layout InvoiceId again and InvoiceTotal. CustomerName and
      InvoiceTotal yield one row per role (order and search; filter and layout); InvoiceId
      yields one layout row at its first line. A <data attribute="&amp;InvoiceNote"> is a
      variable, GhostAttribute and GhostFilter are not in the Attribute inventory, and DomId is a
      Domain only: none of them is extracted. The self-closing <breakBy /> must not swallow the
      search that follows it.
    - WorkWith WorkWithDevicesProduct, in the gridData layout (X Evolution 3, GeneXus 15 and 16):
      orders, breakBy, search and advanced sit under <gridData name="Grid1">. It names
      ProductName (layout and search), Quantity (order), LineNumber (break by), InvoiceStatus
      (filter) and ProductId (detail layout).
    - WorkWith WorkWithDevicesCustomer, whose list layout binds CustomerName with an explicit
      lowercase closing tag (<data attribute="CustomerName"></data>). The instance body ends only
      at the Data element's own </Data> (case-sensitive), so the references after that tag are
      still read: CustomerId (layout), InvoiceDate (order), ProductId (search) and Quantity
      (filter).
    - WorkWithForWeb WorkWithDevicesInvoice, with the same name as the mobile one: its web
      pattern instance names CustomerName and InvoiceDate. Both sources keep their own rows; the
      mobile rows never mask the web rows or the reverse.

    who-uses lists the mobile WorkWith rows even though the catalog marks WorkWith as not
    queryable (that flag only refuses WorkWith as the queried object). Assertions go through
    Query-KbIntelligenceIndex.py who-uses in JSON: for every attribute checked, the exact set of
    Work With rows (source type, source name, evidence role), and for each mobile row its
    relation kind, extractor rule, inventory casing and the first line naming it in that role.
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
$relationKind = 'workwith_references_attribute'
$mobileRule = 'workwith_sd_attribute_reference'

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

# X Evolution 2: orders, breakBy and filter directly under <list>.
$invoiceXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithDevicesInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000001" name="WorkWithDevicesInvoice" type="15cf49b5-fc38-4899-91b5-395d02d79889" description="Synthetic mobile Work With, X Evolution 2 layout">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1">
    <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="0.10.2"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0d000000-0000-4000-8000-000000000010" name="Invoice" description="Invoice">
    <list caption="'Invoices'" events="Event 'Insert'&#xD;&#xA;&#x9;WorkWithDevicesInvoice.Invoice.Detail.Insert()&#xD;&#xA;EndEvent&#xD;&#xA;">
      <layout id="0d000000-0000-4000-8000-000000000011" Type="View">
        <table id="0d000000-0000-4000-8000-000000000012" controlName="MainTable">
          <row id="0d000000-0000-4000-8000-000000000013">
            <cell id="0d000000-0000-4000-8000-000000000014">
              <grid id="0d000000-0000-4000-8000-000000000015" controlName="Grid1">
                <table id="0d000000-0000-4000-8000-000000000016" controlName="Table1">
                  <row id="0d000000-0000-4000-8000-000000000017">
                    <cell id="0d000000-0000-4000-8000-000000000018">
                      <data attribute="InvoiceId" labelPosition="None" class="Attribute.Title" />
                    </cell>
                    <cell id="0d000000-0000-4000-8000-000000000019">
                      <data attribute="&amp;InvoiceNote" labelPosition="None" />
                    </cell>
                    <cell id="0d000000-0000-4000-8000-000000000020">
                      <data attribute="GhostAttribute" labelPosition="None" />
                    </cell>
                    <cell id="0d000000-0000-4000-8000-000000000021">
                      <data attribute="DomId" labelPosition="None" />
                    </cell>
                  </row>
                </table>
              </grid>
            </cell>
          </row>
        </table>
      </layout>
      <orders>
        <order name="ByDate">
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceDate" description="Date" ascending="True" />
        </order>
        <order name="ByCustomer">
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-CustomerName" description="Customer" ascending="True" />
        </order>
      </orders>
      <breakBy />
      <filter>
        <search>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-CustomerName" description="Customer" />
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-customerid" description="Customer id" />
        </search>
        <advanced>
          <filterAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceTotal" description="Total" />
          <filterAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GhostFilter" description="Ghost" />
        </advanced>
      </filter>
    </list>
    <detail caption="InvoiceId.ToString()" rules="parm(InvoiceId);&#xD;&#xA;">
      <layout id="0d000000-0000-4000-8000-000000000022" Type="View">
        <table id="0d000000-0000-4000-8000-000000000023" controlName="MainTable">
          <row id="0d000000-0000-4000-8000-000000000024">
            <cell id="0d000000-0000-4000-8000-000000000025">
              <data attribute="InvoiceId" labelCaption="Id" />
            </cell>
          </row>
          <row id="0d000000-0000-4000-8000-000000000026">
            <cell id="0d000000-0000-4000-8000-000000000027">
              <data attribute="InvoiceTotal" labelCaption="Total" />
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

# X Evolution 3, GeneXus 15 and 16: orders, breakBy, search and filters under <gridData>.
$productXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithDevicesProduct" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000002" name="WorkWithDevicesProduct" type="15cf49b5-fc38-4899-91b5-395d02d79889" description="Synthetic mobile Work With, gridData layout">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1">
    <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="16.0.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0d000000-0000-4000-8000-000000000030" name="Product" description="Product">
    <list caption="'Products'">
      <layout id="0d000000-0000-4000-8000-000000000031" Type="Any Mode">
        <table id="0d000000-0000-4000-8000-000000000032" controlName="MainTable">
          <row id="0d000000-0000-4000-8000-000000000033">
            <cell id="0d000000-0000-4000-8000-000000000034">
              <grid id="0d000000-0000-4000-8000-000000000035" controlName="Grid1">
                <table id="0d000000-0000-4000-8000-000000000036" controlName="Table1">
                  <row id="0d000000-0000-4000-8000-000000000037">
                    <cell id="0d000000-0000-4000-8000-000000000038" vAlign="Middle">
                      <data attribute="ProductName" labelPosition="None" class="AttributeTitle" />
                    </cell>
                  </row>
                </table>
              </grid>
            </cell>
          </row>
        </table>
      </layout>
      <gridData name="Grid1">
        <orders>
          <order name="ByQuantity">
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-Quantity" description="Quantity" ascending="True" />
          </order>
        </orders>
        <breakBy>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-LineNumber" />
        </breakBy>
        <search>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-ProductName" description="Name" />
        </search>
        <filter>
          <advanced>
            <filterAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceStatus" description="Status" />
          </advanced>
        </filter>
      </gridData>
    </list>
    <detail caption="ProductName">
      <layout id="0d000000-0000-4000-8000-000000000039" Type="Any Mode">
        <table id="0d000000-0000-4000-8000-000000000040" controlName="MainTable">
          <row id="0d000000-0000-4000-8000-000000000041">
            <cell id="0d000000-0000-4000-8000-000000000042">
              <data attribute="ProductId" labelCaption="Id" />
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

# A layout control with an explicit lowercase closing tag (</data>) before later references.
$customerXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithDevicesCustomer" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000004" name="WorkWithDevicesCustomer" type="15cf49b5-fc38-4899-91b5-395d02d79889" description="Synthetic mobile Work With, explicit closing tag">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1">
    <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="16.0.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0d000000-0000-4000-8000-000000000060" name="Customer" description="Customer">
    <list caption="'Customers'">
      <layout id="0d000000-0000-4000-8000-000000000061" Type="Any Mode">
        <table id="0d000000-0000-4000-8000-000000000062" controlName="MainTable">
          <row id="0d000000-0000-4000-8000-000000000063">
            <cell id="0d000000-0000-4000-8000-000000000064">
              <data attribute="CustomerName" labelPosition="None"></data>
            </cell>
            <cell id="0d000000-0000-4000-8000-000000000065">
              <data attribute="CustomerId" labelPosition="None" class="AfterClosingTag" />
            </cell>
          </row>
        </table>
      </layout>
      <gridData name="Grid1">
        <orders>
          <order name="ByDate">
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceDate" description="After closing tag" ascending="True" />
          </order>
        </orders>
        <search>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-ProductId" description="After closing tag" />
        </search>
        <filter>
          <advanced>
            <filterAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-Quantity" description="After closing tag" />
          </advanced>
        </filter>
      </gridData>
    </list>
  </level>
</instance>]]></Data>
  </Part>
</Object>
'@

# A web Work With with the same name as the mobile one.
$webXml = @'
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithDevicesInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0d000000-0000-4000-8000-000000000003" name="WorkWithDevicesInvoice" type="78cecefe-be7d-4980-86ce-8d6e91fba04b" description="Synthetic web Work With sharing the mobile name">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1"><Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b" Version="1.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <level id="0d000000-0000-4000-8000-000000000050:1" name="Invoice">
    <selection>
      <attributes>
        <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-CustomerName" />
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-wwsd-attribute-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $corpus = Join-Path $tempRoot 'corpus'
    [void](New-Item -ItemType Directory -Path $corpus -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $corpus -Recurse
    $workWithDir = Join-Path $corpus 'WorkWith'
    $workWithForWebDir = Join-Path $corpus 'WorkWithForWeb'
    [void](New-Item -ItemType Directory -Path $workWithDir -Force)
    [void](New-Item -ItemType Directory -Path $workWithForWebDir -Force)
    $writtenFiles = @{
        WorkWithDevicesInvoice = Join-Path $workWithDir 'WorkWithDevicesInvoice.xml'
        WorkWithDevicesProduct = Join-Path $workWithDir 'WorkWithDevicesProduct.xml'
        WorkWithDevicesCustomer = Join-Path $workWithDir 'WorkWithDevicesCustomer.xml'
    }
    [System.IO.File]::WriteAllText($writtenFiles.WorkWithDevicesInvoice, $invoiceXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText($writtenFiles.WorkWithDevicesProduct, $productXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText($writtenFiles.WorkWithDevicesCustomer, $customerXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $workWithForWebDir 'WorkWithDevicesInvoice.xml'), $webXml, (Get-Utf8NoBomEncoding))
    $extraAttributes = @('InvoiceStatus', 'InvoiceNote')
    for ($index = 0; $index -lt $extraAttributes.Count; $index++) {
        $attributeXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$($extraAttributes[$index])" guid="0d000000-0000-4000-8000-0000000001$('{0:d2}' -f $index)" lastUpdate="2026-01-01T00:00:00" description="Synthetic attribute">
  <Properties />
</Attribute>
"@
        [System.IO.File]::WriteAllText((Join-Path $corpus "Attribute/$($extraAttributes[$index]).xml"), $attributeXml, (Get-Utf8NoBomEncoding))
    }

    $indexPath = Join-Path $tempRoot 'index/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force)
    & $buildScript -SourceRoot $corpus -OutputPath $indexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex failed; exit $LASTEXITCODE"
    }

    # Expected Work With rows per attribute as "SourceType:SourceName|role". Mobile rows carry a
    # marker: the first line of the written file holding it is the expected evidence line.
    $layout = 'WorkWith layout attribute'
    $order = 'WorkWith order attribute'
    $search = 'WorkWith search attribute'
    $breakBy = 'WorkWith break by attribute'
    $filter = 'WorkWith filter attribute'
    $expectedRows = @{
        CustomerId    = @(
            @('WorkWithDevicesInvoice', $search, '-customerid" description="Customer id"'),
            @('WorkWithDevicesCustomer', $layout, '<data attribute="CustomerId"')
        )
        CustomerName  = @(
            @('WorkWithDevicesCustomer', $layout, '<data attribute="CustomerName"'),
            @('WorkWithDevicesInvoice', $order, '-CustomerName" description="Customer" ascending'),
            @('WorkWithDevicesInvoice', $search, '-CustomerName" description="Customer" />'),
            'WorkWithForWeb:WorkWithDevicesInvoice|WorkWithForWeb attribute'
        )
        InvoiceDate   = @(
            @('WorkWithDevicesCustomer', $order, '-InvoiceDate" description="After closing tag"'),
            @('WorkWithDevicesInvoice', $order, '-InvoiceDate" description="Date"'),
            'WorkWithForWeb:WorkWithDevicesInvoice|WorkWithForWeb filter attribute'
        )
        InvoiceId     = @(,@('WorkWithDevicesInvoice', $layout, '<data attribute="InvoiceId"'))
        InvoiceTotal  = @(
            @('WorkWithDevicesInvoice', $filter, '-InvoiceTotal" description="Total"'),
            @('WorkWithDevicesInvoice', $layout, '<data attribute="InvoiceTotal"')
        )
        InvoiceStatus = @(,@('WorkWithDevicesProduct', $filter, '-InvoiceStatus" description="Status"'))
        LineNumber    = @(,@('WorkWithDevicesProduct', $breakBy, '-LineNumber" />'))
        ProductId     = @(
            @('WorkWithDevicesProduct', $layout, '<data attribute="ProductId"'),
            @('WorkWithDevicesCustomer', $search, '-ProductId" description="After closing tag"')
        )
        ProductName   = @(
            @('WorkWithDevicesProduct', $layout, '<data attribute="ProductName"'),
            @('WorkWithDevicesProduct', $search, '-ProductName" description="Name"')
        )
        Quantity      = @(
            @('WorkWithDevicesProduct', $order, '-Quantity" description="Quantity"'),
            @('WorkWithDevicesCustomer', $filter, '-Quantity" description="After closing tag"')
        )
        # Negatives: a &variable, a Domain-only name (DomId is no Attribute, so who-uses has no row).
        InvoiceNote   = @()
        DomId         = @()
    }
    $writtenLines = @{}
    foreach ($name in $writtenFiles.Keys) {
        $writtenLines[$name] = ([System.IO.File]::ReadAllText($writtenFiles[$name])) -split "`n"
    }

    foreach ($attributeName in ($expectedRows.Keys | Sort-Object)) {
        $label = "who-uses/Attribute:$attributeName"
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $attributeName)
        $rows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
        $expectedKeys = @($expectedRows[$attributeName] | ForEach-Object {
                if ($_ -is [string]) { $_ } else { 'WorkWith:{0}|{1}' -f $_[0], $_[1] }
            } | Sort-Object)
        $actualKeys = @($rows | ForEach-Object { '{0}:{1}|{2}' -f $_.source_type, $_.source_name, $_.evidence_role } | Sort-Object)
        if (($actualKeys -join ';') -cne ($expectedKeys -join ';')) {
            Add-Failure "[$label] '$relationKind' rows should be '$($expectedKeys -join ';')'; got '$($actualKeys -join ';')'"
            continue
        }
        foreach ($expected in @($expectedRows[$attributeName] | Where-Object { $_ -isnot [string] })) {
            $sourceName, $role, $marker = $expected
            $row = @($rows | Where-Object { $_.source_type -eq 'WorkWith' -and $_.source_name -eq $sourceName -and $_.evidence_role -eq $role })[0]
            $rowLabel = "$label/WorkWith:$sourceName/$role"
            if ($row.extractor_rule -cne $mobileRule) {
                Add-Failure "[$rowLabel] extractor_rule should be '$mobileRule'; got '$($row.extractor_rule)'"
            }
            if ($row.target_name -cne $attributeName) {
                Add-Failure "[$rowLabel] target_name should use the inventory casing '$attributeName'; got '$($row.target_name)'"
            }
            $expectedLine = 0
            $lines = $writtenLines[$sourceName]
            for ($index = 0; $index -lt $lines.Count; $index++) {
                if ($lines[$index].Contains($marker)) { $expectedLine = $index + 1; break }
            }
            if ($expectedLine -eq 0) {
                throw "[$rowLabel] test marker '$marker' not found in the written WorkWith XML"
            }
            if ($row.line -ne $expectedLine) {
                Add-Failure "[$rowLabel] evidence line should be $expectedLine (first line naming the attribute in that role); got $($row.line)"
            }
        }
    }

    # DomId, named by a layout <data attribute="DomId">, is a Domain only. Targets resolve against
    # the Attribute inventory alone, so the query for DomId as an Attribute finds no row at all
    # (any relation kind: a regression that resolved layout names against every inventory type
    # would emit an Attribute:DomId row), and the Domain DomId gets no Work With attribute row.
    $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', 'DomId')
    if ($payload.total -ne 0 -or @($payload.results).Count -ne 0) {
        Add-Failure "[who-uses/Attribute:DomId] a Domain-only name in a layout must not produce any Attribute row; got total $($payload.total): $(@($payload.results | ForEach-Object { '{0}:{1}|{2}' -f $_.source_type, $_.source_name, $_.relation_kind }) -join ', ')"
    }
    $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Domain', '--object-name', 'DomId')
    $domainRows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
    if ($domainRows.Count -ne 0) {
        Add-Failure "[who-uses/Domain:DomId] a Domain-only name in a layout must not produce '$relationKind' to the Domain; got $($domainRows.Count)"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceWorkWithDevicesAttributeSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligenceWorkWithDevicesAttributeSelfTest.ps1'
exit 0
