#requires -Version 7.4
<#
.SYNOPSIS
    WorkWithForWeb pattern instances emit workwith_references_attribute relations to the
    attributes their grids, orders, views, description and filters name.

.DESCRIPTION
    Builds an index from a temporary copy of the synthetic sample-kb fixture
    (tests/fixtures/sample-kb/, no real KB data) plus two objects written by this test:

    - WorkWithForWeb WorkWithWebInvoice: its pattern instance CDATA names fixture attributes in
      a selection grid (InvoiceTotal), a selection order (CustomerName), a fixed data block
      (invoiceid, lowercase), a Tabular view tab (ProductName), a Grid view tab (Quantity, with
      its own order repeating InvoiceTotal), a descriptionAttribute (CustomerId) and a bare
      filterAttribute (InvoiceDate). InvoiceTotal appears in three places and must yield one
      relation. ProductId appears only inside a two-line <variable> element (its name and its
      code; the evidence lines after it prove the masking keeps line breaks) and
      LineNumber only inside a <condition value="..."> expression: neither is extracted.
      GhostAttribute is not in the Attribute inventory: no relation.
    - mobile WorkWith WorkWithDevicesInvoice with the same instance XML: no attribute relation,
      because the extractor reads WorkWithForWeb only (checked through who-uses, since
      what-uses refuses the WorkWith type).

    Assertions go through Query-KbIntelligenceIndex.py who-uses and what-uses in JSON.
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

# The same pattern instance is written for the web and the mobile Work With.
$instanceTemplate = @'
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1"><Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b" Version="1.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <transaction transaction="1db606f2-af09-4cf9-a3b5-b481519d28f6-Invoice" />
  <level id="0c000000-0000-4000-8000-000000000010:1" name="Invoice">
    <descriptionAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-CustomerId" description="Customer" />
    <selection>
      <attributes>
        <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceTotal" />
        <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GhostAttribute" />
        <variable name="ProductId" domain="adbb33c9-0906-4971-833c-998de27e0676-ProductId"><![CDATA[&Html = '<attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-ProductId" />'
&Html += '<attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-ProductId" />']]]]><![CDATA[></variable>
      </attributes>
      <orders>
        <order name="ByCustomer">
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-CustomerName" />
        </order>
      </orders>
      <filter>
        <attributes>
          <filterAttribute name="InvoiceDate" description="Date" />
        </attributes>
        <conditions>
          <condition value="LineNumber &gt; 0 and InvoiceTotal &gt; 0" />
        </conditions>
      </filter>
    </selection>
    <view caption="Invoice">
      <fixedData>
        <attributes>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-invoiceid" />
        </attributes>
      </fixedData>
      <tabs>
        <tab name="General" code="General" type="Tabular" wcname="InvoiceGeneral">
          <attributes>
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-ProductName" />
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceTotal" />
          </attributes>
        </tab>
        <tab name="Lines" code="InvoiceLines" type="Grid" wcname="InvoiceLinesWC">
          <attributes>
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-Quantity" />
          </attributes>
          <orders>
            <order name="ByTotal">
              <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceTotal" />
            </order>
          </orders>
        </tab>
      </tabs>
    </view>
  </level>
</instance>]]></Data></Part>
'@

$workWithForWebXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithWebInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0c000000-0000-4000-8000-000000000001" name="WorkWithWebInvoice" type="78cecefe-be7d-4980-86ce-8d6e91fba04b" description="Synthetic web Work With">
$instanceTemplate</Object>
"@
$workWithXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="WorkWithDevicesInvoice" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0c000000-0000-4000-8000-000000000002" name="WorkWithDevicesInvoice" type="15cf49b5-fc38-4899-91b5-395d02d79889" description="Synthetic mobile Work With">
$instanceTemplate</Object>
"@

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-wwfw-attribute-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $corpus = Join-Path $tempRoot 'corpus'
    [void](New-Item -ItemType Directory -Path $corpus -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $corpus -Recurse
    $workWithForWebDir = Join-Path $corpus 'WorkWithForWeb'
    $workWithDir = Join-Path $corpus 'WorkWith'
    [void](New-Item -ItemType Directory -Path $workWithForWebDir -Force)
    [void](New-Item -ItemType Directory -Path $workWithDir -Force)
    [System.IO.File]::WriteAllText((Join-Path $workWithForWebDir 'WorkWithWebInvoice.xml'), $workWithForWebXml, (Get-Utf8NoBomEncoding))
    [System.IO.File]::WriteAllText((Join-Path $workWithDir 'WorkWithDevicesInvoice.xml'), $workWithXml, (Get-Utf8NoBomEncoding))

    $indexPath = Join-Path $tempRoot 'index/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force)
    & $buildScript -SourceRoot $corpus -OutputPath $indexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex failed; exit $LASTEXITCODE"
    }

    # Positive cases: one relation from the web Work With per named attribute, in the
    # inventory's casing, whichever part of the instance names it. The evidence points at the
    # first naming line of the written file (1-based, counted in the whole XML, so the CDATA
    # offset and the line-preserving <variable> masking must both hold) with the tag's role.
    $expectedTargets = @('CustomerId', 'CustomerName', 'InvoiceDate', 'InvoiceId', 'InvoiceTotal', 'ProductName', 'Quantity')
    $evidenceMarkers = @{
        CustomerId   = @('<descriptionAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-CustomerId"', 'WorkWithForWeb description attribute')
        CustomerName = @('-CustomerName" />', 'WorkWithForWeb attribute')
        InvoiceDate  = @('<filterAttribute name="InvoiceDate"', 'WorkWithForWeb filter attribute')
        InvoiceId    = @('-invoiceid" />', 'WorkWithForWeb attribute')
        InvoiceTotal = @('-InvoiceTotal" />', 'WorkWithForWeb attribute')
        ProductName  = @('-ProductName" />', 'WorkWithForWeb attribute')
        Quantity     = @('-Quantity" />', 'WorkWithForWeb attribute')
    }
    $writtenLines = ([System.IO.File]::ReadAllText((Join-Path $workWithForWebDir 'WorkWithWebInvoice.xml'))) -split "`n"
    foreach ($attributeName in $expectedTargets) {
        $label = "who-uses/Attribute:$attributeName"
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $attributeName)
        $rows = @($payload.results | Where-Object { $_.source_type -eq 'WorkWithForWeb' -and $_.source_name -eq 'WorkWithWebInvoice' })
        if ($rows.Count -ne 1) {
            Add-Failure "[$label] expected exactly one WorkWithForWeb:WorkWithWebInvoice row; got $($rows.Count)"
            continue
        }
        if ($rows[0].relation_kind -ne $relationKind) {
            Add-Failure "[$label] relation_kind should be '$relationKind'; got '$($rows[0].relation_kind)'"
        }
        if ($rows[0].target_name -cne $attributeName) {
            Add-Failure "[$label] target_name should use the inventory casing '$attributeName'; got '$($rows[0].target_name)'"
        }
        $marker, $expectedRole = $evidenceMarkers[$attributeName]
        $expectedLine = 0
        for ($index = 0; $index -lt $writtenLines.Count; $index++) {
            if ($writtenLines[$index].Contains($marker)) { $expectedLine = $index + 1; break }
        }
        if ($expectedLine -eq 0) {
            throw "[$label] test marker '$marker' not found in the written WorkWithForWeb XML"
        }
        if ($rows[0].line -ne $expectedLine) {
            Add-Failure "[$label] evidence line should be $expectedLine (first line naming the attribute); got $($rows[0].line)"
        }
        if ($rows[0].evidence_role -cne $expectedRole) {
            Add-Failure "[$label] evidence_role should be '$expectedRole'; got '$($rows[0].evidence_role)'"
        }
        if ($rows[0].extractor_rule -cne 'workwith_for_web_attribute_reference') {
            Add-Failure "[$label] extractor_rule should be 'workwith_for_web_attribute_reference'; got '$($rows[0].extractor_rule)'"
        }
        $mobileRows = @($payload.results | Where-Object { $_.source_type -eq 'WorkWith' })
        if ($mobileRows.Count -ne 0) {
            Add-Failure "[$label] the mobile WorkWith must not emit attribute relations; got $($mobileRows.Count)"
        }
    }

    # Negative cases: a name only inside a <variable> element or a condition expression.
    foreach ($attributeName in @('ProductId', 'LineNumber')) {
        $label = "who-uses/Attribute:$attributeName"
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $attributeName)
        $rows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
        if ($rows.Count -ne 0) {
            Add-Failure "[$label] a variable or condition mention must not produce '$relationKind'; got $($rows.Count) row(s) from $(@($rows | ForEach-Object { '{0}:{1}' -f $_.source_type, $_.source_name }) -join ', ')"
        }
    }

    # Forward view: exactly the expected targets, nothing for GhostAttribute (not in inventory).
    $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'what-uses', '--object-type', 'WorkWithForWeb', '--object-name', 'WorkWithWebInvoice')
    $actualTargets = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind } | ForEach-Object { $_.target_name } | Sort-Object)
    if (($actualTargets -join ',') -cne (($expectedTargets | Sort-Object) -join ',')) {
        Add-Failure "[what-uses/WorkWithForWeb:WorkWithWebInvoice] '$relationKind' targets should be '$(($expectedTargets | Sort-Object) -join ',')'; got '$($actualTargets -join ',')'"
    }
    $nonAttributeTargets = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind -and $_.target_type -ne 'Attribute' })
    if ($nonAttributeTargets.Count -ne 0) {
        Add-Failure "[what-uses/WorkWithForWeb:WorkWithWebInvoice] '$relationKind' must target Attribute only"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceWorkWithForWebAttributeSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligenceWorkWithForWebAttributeSelfTest.ps1'
exit 0
