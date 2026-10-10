#requires -Version 7.4
<#
.SYNOPSIS
    WorkWithForWeb pattern instances emit workwith_references_attribute relations to the
    attributes their grids, orders, views, description, filters and conditions name.

.DESCRIPTION
    Builds an index from a temporary copy of the synthetic sample-kb fixture
    (tests/fixtures/sample-kb/, no real KB data) plus twenty-four synthetic Attribute objects and two
    objects written by this test:

    - WorkWithForWeb WorkWithWebInvoice: its pattern instance CDATA names fixture attributes in
      a selection grid (InvoiceTotal), a selection order (CustomerName), a fixed data block
      (invoiceid, lowercase), a Tabular view tab (ProductName), a Grid view tab (Quantity, with
      its own order repeating InvoiceTotal), a descriptionAttribute (CustomerId) and a bare
      filterAttribute (InvoiceDate). InvoiceTotal appears in three places and must yield one
      relation. ProductId appears only inside a three-line <variable> element (its name and its
      code, including a <condition value="..."> written there; the evidence lines after it
      prove the masking keeps line breaks): it is not extracted. GhostAttribute and
      GhostCondition are not in the Attribute inventory: no relation.
    - The selection filter and the Grid tab filter hold <condition value="..."> expressions.
      Attributes they name (LineNumber, InvoiceStatus, the arguments InvoiceDiscount and
      InvoiceAmount of InvoiceCheck(...) and InvoiceRule.udp(...), InvoiceDueDate after the
      legacy '.and.' operator and before a member call, InvoiceRegion in the Grid tab)
      are extracted with the condition role at the line of their <condition> tag. A // comment
      ends at its line only: InvoiceBalance, on the line after a comment inside a multi-line
      condition value (an encoded &#xA;), is extracted. A <condition> outside any <filter> (the
      Grid tab's own <conditions>) is not a filter condition: InvoiceCredit, named only there, is
      not extracted. A comment is whitespace, so the names after it are read with the tokens
      before it: InvoiceAfterMember (after a member and a comment) and InvoiceAfterOpener (the
      second argument of a udp( opener followed by a comment) are extracted, while InvoiceCheck,
      the object udp( names on the line after the comment, is not. A third Grid tab holds a
      filter whose quoted caption holds '/>' (its condition, InvoiceQuoted, is extracted), a
      self-closing filter whose quoted caption holds '>' followed by a <conditions> outside any
      filter (InvoiceStray, not extracted), and a nested filter, which the pattern instance does
      not produce: only the conditions up to the first </filter> are read (InvoiceNestedInner
      is extracted, InvoiceNestedOuter is not; a pinned limit). Quantity is
      named by a condition before the Grid tab names it, so its single row is the condition;
      InvoiceTotal and CustomerName keep their earlier grid and order rows. Names used only as
      a &variable (InvoiceSearch, also with .IsEmpty()), in a string literal or a // comment
      (InvoiceNote), as a called object (InvoiceCheck(...), InvoiceRule.udp(...)), as a member
      (InvoiceMonth) or as a keyword (like, when, not, and, or, null) are not extracted even
      though attributes with those names exist.
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
&Html += '<attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-ProductId" />'
&Html += '<condition value="ProductId &gt; 0" />']]]]><![CDATA[></variable>
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
          <condition value="InvoiceStatus = &amp;InvoiceSearch when not &amp;InvoiceSearch.IsEmpty()" />
          <condition value="CustomerName like 'InvoiceNote%' + &quot;InvoiceNote&quot; when not InvoiceCheck(InvoiceDiscount) // InvoiceNote" />
          <condition value="Quantity &gt; 0 .and. InvoiceDueDate.InvoiceMonth() = 1 or InvoiceRule.udp(InvoiceAmount) &lt;&gt; null" />
          <condition value="GhostCondition like &amp;GhostCondition when not InvoiceTotal = null and true or false" />
          <condition value="InvoiceTotal &gt; 0 // InvoiceNote&#xA;and InvoiceBalance &gt; 0" />
          <condition value="InvoiceDueDate.InvoiceMonth // InvoiceNote&#xA;and InvoiceAfterMember = 1" />
          <condition value="udp( // InvoiceNote&#xA;InvoiceCheck, InvoiceAfterOpener) = 1" />
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
          <conditions>
            <condition value="InvoiceCredit &gt; 0" />
          </conditions>
          <orders>
            <order name="ByTotal">
              <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-InvoiceTotal" />
            </order>
          </orders>
          <filter>
            <conditions>
              <condition value="InvoiceRegion = &amp;InvoiceRegion when not &amp;InvoiceRegion.IsEmpty()" />
            </conditions>
          </filter>
        </tab>
        <tab name="Notes" code="InvoiceNotes" type="Grid" wcname="InvoiceNotesWC">
          <filter caption="Total /> Limit">
            <conditions>
              <condition value="InvoiceQuoted &gt; 0" />
            </conditions>
          </filter>
          <filter caption="Total > Limit" />
          <conditions>
            <condition value="InvoiceStray &gt; 0" />
          </conditions>
          <filter>
            <filter>
              <conditions>
                <condition value="InvoiceNestedInner &gt; 0" />
              </conditions>
            </filter>
            <conditions>
              <condition value="InvoiceNestedOuter &gt; 0" />
            </conditions>
          </filter>
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
    # Extra attributes the conditions name: some must be extracted, the others share their name
    # with a variable, a string literal, a call, a member or a keyword and must not be.
    $extraAttributes = @(
        'InvoiceAmount', 'InvoiceStatus', 'InvoiceDiscount', 'InvoiceDueDate', 'InvoiceRegion',
        'InvoiceBalance', 'InvoiceCredit', 'InvoiceSearch', 'InvoiceNote', 'InvoiceCheck', 'InvoiceRule', 'InvoiceMonth',
        'InvoiceAfterMember', 'InvoiceAfterOpener', 'InvoiceQuoted', 'InvoiceStray', 'InvoiceNestedInner', 'InvoiceNestedOuter',
        'Like', 'When', 'Not', 'And', 'Or', 'Null'
    )
    for ($index = 0; $index -lt $extraAttributes.Count; $index++) {
        $attributeXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$($extraAttributes[$index])" guid="0c000000-0000-4000-8000-0000000001$('{0:d2}' -f $index)" lastUpdate="2026-01-01T00:00:00" description="Synthetic condition attribute">
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

    # Positive cases: one relation from the web Work With per named attribute, in the
    # inventory's casing, whichever part of the instance names it. The evidence points at the
    # first naming line of the written file (1-based, counted in the whole XML, so the CDATA
    # offset and the line-preserving <variable> masking must both hold) with the tag's role.
    # A condition names the attribute at the line of its <condition> tag; Quantity is named by a
    # selection condition before the Grid tab names it, so its first occurrence is the condition.
    $expectedTargets = @(
        'CustomerId', 'CustomerName', 'InvoiceAfterMember', 'InvoiceAfterOpener', 'InvoiceAmount', 'InvoiceBalance', 'InvoiceDate',
        'InvoiceDiscount', 'InvoiceDueDate', 'InvoiceId', 'InvoiceNestedInner', 'InvoiceQuoted', 'InvoiceRegion', 'InvoiceStatus',
        'InvoiceTotal', 'LineNumber', 'ProductName', 'Quantity'
    )
    $evidenceMarkers = @{
        InvoiceAfterMember = @('<condition value="InvoiceDueDate.InvoiceMonth // InvoiceNote', 'WorkWithForWeb condition')
        InvoiceAfterOpener = @('<condition value="udp( // InvoiceNote', 'WorkWithForWeb condition')
        InvoiceAmount   = @('<condition value="Quantity &gt; 0 .and.', 'WorkWithForWeb condition')
        InvoiceBalance  = @('<condition value="InvoiceTotal &gt; 0 // InvoiceNote', 'WorkWithForWeb condition')
        CustomerId      = @('<descriptionAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-CustomerId"', 'WorkWithForWeb description attribute')
        CustomerName    = @('-CustomerName" />', 'WorkWithForWeb attribute')
        InvoiceDate     = @('<filterAttribute name="InvoiceDate"', 'WorkWithForWeb filter attribute')
        InvoiceDiscount = @('<condition value="CustomerName like', 'WorkWithForWeb condition')
        InvoiceDueDate  = @('<condition value="Quantity &gt; 0 .and.', 'WorkWithForWeb condition')
        InvoiceId       = @('-invoiceid" />', 'WorkWithForWeb attribute')
        InvoiceNestedInner = @('<condition value="InvoiceNestedInner', 'WorkWithForWeb condition')
        InvoiceQuoted   = @('<condition value="InvoiceQuoted', 'WorkWithForWeb condition')
        InvoiceRegion   = @('<condition value="InvoiceRegion =', 'WorkWithForWeb condition')
        InvoiceStatus   = @('<condition value="InvoiceStatus =', 'WorkWithForWeb condition')
        InvoiceTotal    = @('-InvoiceTotal" />', 'WorkWithForWeb attribute')
        LineNumber      = @('<condition value="LineNumber', 'WorkWithForWeb condition')
        ProductName     = @('-ProductName" />', 'WorkWithForWeb attribute')
        Quantity        = @('<condition value="Quantity &gt; 0 .and.', 'WorkWithForWeb condition')
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

    # Negative cases: a name only inside a <variable> element (even in a condition written there),
    # only in a condition outside any <filter> (InvoiceStray follows a self-closing filter whose
    # quoted caption holds a '>'), only after a nested filter's first </filter> (InvoiceNestedOuter:
    # nesting does not occur in the pattern instance, see WORKWITH_FOR_WEB_FILTER_RE), or in a filter condition only as a &variable, a
    # string literal, a comment, a called object, a member after '.', or a keyword.
    $negativeTargets = @(
        'ProductId', 'InvoiceCredit', 'InvoiceStray', 'InvoiceNestedOuter', 'InvoiceSearch', 'InvoiceNote', 'InvoiceCheck', 'InvoiceRule', 'InvoiceMonth',
        'Like', 'When', 'Not', 'And', 'Or', 'Null'
    )
    foreach ($attributeName in $negativeTargets) {
        $label = "who-uses/Attribute:$attributeName"
        $payload = Invoke-QueryJson -IndexPath $indexPath -Arguments @('--query', 'who-uses', '--object-type', 'Attribute', '--object-name', $attributeName)
        $rows = @($payload.results | Where-Object { $_.relation_kind -eq $relationKind })
        if ($rows.Count -ne 0) {
            Add-Failure "[$label] a variable, literal, comment, call, member or keyword mention must not produce '$relationKind'; got $($rows.Count) row(s) from $(@($rows | ForEach-Object { '{0}:{1}' -f $_.source_type, $_.source_name }) -join ', ')"
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
