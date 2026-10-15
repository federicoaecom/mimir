#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: calls in classic GeneXus code (7.5 to 9 exports) produce call relations.

.DESCRIPTION
    Builds a synthetic KB of classic objects (root dataSource="gx-legacy-export") and proves that:
      - Call(, Udp(, and Link( in Events, Rules, and Source strip the object-type prefix
        (P Procedure, R Report, T Transaction, W Work Panel) and relate to the named object;
      - what-uses lists the callees and who-uses lists the caller, with the line of the call;
      - a call through a variable (Call(&PDebugProc, ...)) yields no relation, although stripping the P of the variable name would name an existing Procedure DebugProc;
      - classic code is not read with the modern regexes: call(PAGO) relates to Procedure AGO,
        never to a Procedure named PAGO;
      - a prefix outside P/R/T/W yields no relation;
      - a call inside a // line comment or a multi-line /* ... */ block comment yields no relation;
      - link( relates with the classic_link rule, and a quoted name (call('PQuoted')) resolves;
      - the HTML <Source> under a classic WebPanel HTMLForm is not read as code;
      - only a <Source> inside a <CodeBlock> is code: a Report's Documentation <Source> and the
        <Source> of a print control in its layout are not read;
      - a modern Procedure (real GUID, no dataSource) still relates call(ModernTarget) as before.
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

$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$transactionGuid = '1db606f2-af09-4cf9-a3b5-b481519d28f6'
$webPanelGuid = 'c9584656-94b6-4ccd-890f-332d11fc2c25'
$workPanelGuid = '198e8ea4-1d49-4c9c-8a9a-417024baa9d1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-ClassicXml {
    param([string]$Type, [string]$Name, [string]$RootElement, [string]$Body)
    return @"
<Object type="$Type" name="$Name" guid="" lastUpdate="2013-02-27T15:36:48.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<$RootElement>
  <Info><Name>$Name</Name></Info>
$Body
</$RootElement>
  </GxLegacyPayload>
</Object>
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-classic-calls-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
$folders = @{}
foreach ($folder in @('WebPanel', 'Report', 'Procedure', 'Transaction', 'WorkPanel')) {
    $folders[$folder] = Join-Path $kbObjectsPath $folder
}
[void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)

function Write-Fixture {
    param([string]$Folder, [string]$Name, [string]$Xml)
    [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
}

# Classic WebPanel: its code is in <Events>; the HTMLForm <Source> holds HTML.
$webPanelXml = New-ClassicXml -Type $webPanelGuid -Name 'WPORDERS' -RootElement 'WebPanel' -Body @'
  <HTMLForm><Source><![CDATA[<table><tr><td>Print call(PHtmlOnly)</td></tr></table>]]></Source></HTMLForm>
  <Events><![CDATA[Event 'Print'
  Call(RRPTORDERS, &OrdId)
  Udp(PLogMessage,&ErrorText,"E")
  Call(&PDebugProc, &DebugText)
  call(XFoo)
EndEvent]]></Events>
'@
Write-Fixture 'WebPanel' 'WPORDERS' $webPanelXml

# Classic WebPanel with commented-out calls, a link(, and a quoted name.
$linkerXml = New-ClassicXml -Type $webPanelGuid -Name 'WLINKER' -RootElement 'WebPanel' -Body @'
  <Events><![CDATA[Event Enter
  // call(PLineComment)
  /* call(PBlockOne)
     call(PBlockTwo) */
  link(WMemberRange)
  call('PQuoted')
EndEvent]]></Events>
'@
Write-Fixture 'WebPanel' 'WLINKER' $linkerXml

# Classic Report: code in Layout/Block/CodeBlock/Source and in Rules. Its Documentation <Source> (HTML)
# and the <Source> of a print control in its layout are not code.
$reportXml = New-ClassicXml -Type 'gxlegacy/Report' -Name 'RPTORDERS' -RootElement 'Report' -Body @'
  <Layout><Block><CodeBlock><Source><![CDATA[For Each OrdId
  call(WMemberRange)
EndFor]]></Source></CodeBlock><PrintBlock><Text><Source><![CDATA[call(PLayoutOnly)]]></Source></Text></PrintBlock></Block></Layout>
  <Documentation><Source><![CDATA[<P>Refreshes the list with call(PDocOnly)</P>]]></Source></Documentation>
  <Rules><![CDATA[Parm(&OrdId);
call(TMember);]]></Rules>
'@
Write-Fixture 'Report' 'RPTORDERS' $reportXml

# Classic WebPanel and classic Procedure calling call(PAGO): Procedure AGO, never PAGO.
$wpagoXml = New-ClassicXml -Type $webPanelGuid -Name 'WPAGO' -RootElement 'WebPanel' -Body @'
  <Events><![CDATA[Event Enter
  call(PAGO)
EndEvent]]></Events>
'@
Write-Fixture 'WebPanel' 'WPAGO' $wpagoXml
$legacyCallerXml = New-ClassicXml -Type $procedureGuid -Name 'LegacyCaller' -RootElement 'Procedure' -Body @'
  <Layout><Block><CodeBlock><Source><![CDATA[call(PAGO)]]></Source></CodeBlock></Block></Layout>
'@
Write-Fixture 'Procedure' 'LegacyCaller' $legacyCallerXml

foreach ($procedureName in @('LogMessage', 'DebugProc', 'Foo', 'PAGO', 'AGO', 'HtmlOnly', 'LineComment', 'BlockOne', 'BlockTwo', 'Quoted', 'DocOnly', 'LayoutOnly')) {
    Write-Fixture 'Procedure' $procedureName (New-ClassicXml -Type $procedureGuid -Name $procedureName -RootElement 'Procedure' -Body '')
}
Write-Fixture 'Transaction' 'Member' (New-ClassicXml -Type $transactionGuid -Name 'Member' -RootElement 'Transaction' -Body '')
Write-Fixture 'WorkPanel' 'MemberRange' (New-ClassicXml -Type $workPanelGuid -Name 'MemberRange' -RootElement 'WorkPanel' -Body '')

# Modern Procedures: the modern call path must still hold.
Write-Fixture 'Procedure' 'ModernCaller' @"
<Object type="$procedureGuid" name="ModernCaller" guid="77777777-7777-7777-7777-777777777701">
  <Source><![CDATA[call(ModernTarget)]]></Source>
</Object>
"@
Write-Fixture 'Procedure' 'ModernTarget' @"
<Object type="$procedureGuid" name="ModernTarget" guid="77777777-7777-7777-7777-777777777702">
  <Source><![CDATA[]]></Source>
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
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete with classic callers; exit $LASTEXITCODE"
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

function Find-Row {
    param($Rows, [string]$Type, [string]$Name, [string]$Kind, [string]$Side)
    # The leading comma keeps an empty match an empty array instead of $null.
    return , @($Rows | Where-Object {
        $_."$($Side)_type" -eq $Type -and $_."$($Side)_name" -eq $Name -and $_.relation_kind -eq $Kind
    })
}

# Rule: WebPanel Events, Call( with prefix R and Udp( with prefix P.
$wporders = Invoke-IndexQuery -Query 'what-uses' -Type 'WebPanel' -Name 'WPORDERS'
$wpordersRows = @($wporders.results)
$toReport = Find-Row $wpordersRows 'Report' 'RPTORDERS' 'calls_report' 'target'
Assert-True ($toReport.Count -eq 1) "what-uses WebPanel WPORDERS should list Report RPTORDERS (calls_report); got: $(($wpordersRows | ForEach-Object { "$($_.target_type) $($_.target_name) $($_.relation_kind)" }) -join '; ')"
Assert-True ($toReport[0].line -eq (Get-LineNumberOf $webPanelXml 'Call(RRPTORDERS')) "Report RPTORDERS evidence should carry the line of Call(RRPTORDERS, ...); got $($toReport[0].line)"
Assert-True ($toReport[0].extractor_rule -eq 'classic_call_command') "Call(RRPTORDERS, ...) should use classic_call_command; got $($toReport[0].extractor_rule)"
$toLogMessage = Find-Row $wpordersRows 'Procedure' 'LogMessage' 'calls_procedure' 'target'
Assert-True ($toLogMessage.Count -eq 1) 'what-uses WebPanel WPORDERS should list Procedure LogMessage (calls_procedure)'
Assert-True ($toLogMessage[0].extractor_rule -eq 'classic_udp_func') "Udp(PLogMessage, ...) should use classic_udp_func; got $($toLogMessage[0].extractor_rule)"

$rptordersCallers = Invoke-IndexQuery -Query 'who-uses' -Type 'Report' -Name 'RPTORDERS'
Assert-True ((Find-Row @($rptordersCallers.results) 'WebPanel' 'WPORDERS' 'calls_report' 'source').Count -eq 1) 'who-uses Report RPTORDERS should list WebPanel WPORDERS'

# Rule: a call through a variable is not a static call.
Assert-True (@($wpordersRows | Where-Object { $_.target_name -eq 'DebugProc' }).Count -eq 0) 'Call(&PDebugProc, ...) should yield no relation (a variable, not Procedure DebugProc)'

# Rule: a prefix outside P/R/T/W yields no relation.
Assert-True (@($wpordersRows | Where-Object { $_.target_name -eq 'Foo' }).Count -eq 0) 'call(XFoo) should yield no relation (X is not a mapped prefix)'

# Rule: the HTML <Source> under a classic WebPanel HTMLForm is not read as code.
Assert-True (@($wpordersRows | Where-Object { $_.target_name -eq 'HtmlOnly' }).Count -eq 0) 'call(PHtmlOnly) inside the HTMLForm <Source> should yield no relation'

# Rule: only a <Source> inside a <CodeBlock> is code (Documentation and print controls are not).
$reportCallRows = @((Invoke-IndexQuery -Query 'what-uses' -Type 'Report' -Name 'RPTORDERS').results)
foreach ($notCode in @('DocOnly', 'LayoutOnly')) {
    Assert-True (@($reportCallRows | Where-Object { $_.target_name -eq $notCode }).Count -eq 0) "call(P$notCode) outside a Report CodeBlock should yield no relation"
}

# Rule: calls inside // and multi-line /* */ comments yield no relation.
$linkerRows = @((Invoke-IndexQuery -Query 'what-uses' -Type 'WebPanel' -Name 'WLINKER').results)
foreach ($commented in @('LineComment', 'BlockOne', 'BlockTwo')) {
    Assert-True (@($linkerRows | Where-Object { $_.target_name -eq $commented }).Count -eq 0) "A commented-out call(P$commented) should yield no relation; got: $(($linkerRows | ForEach-Object { "$($_.target_type) $($_.target_name) $($_.relation_kind)" }) -join '; ')"
}

# Rule: link( relates with classic_link; a quoted name resolves.
$toLinked = Find-Row $linkerRows 'WorkPanel' 'MemberRange' 'calls_workpanel' 'target'
Assert-True ($toLinked.Count -eq 1) 'what-uses WebPanel WLINKER should list WorkPanel MemberRange for link(WMemberRange)'
Assert-True ($toLinked[0].extractor_rule -eq 'classic_link') "link(WMemberRange) should use classic_link; got $($toLinked[0].extractor_rule)"
$quotedCallers = Invoke-IndexQuery -Query 'who-uses' -Type 'Procedure' -Name 'Quoted'
Assert-True ((Find-Row @($quotedCallers.results) 'WebPanel' 'WLINKER' 'calls_procedure' 'source').Count -eq 1) "who-uses Procedure Quoted should list WebPanel WLINKER for call('PQuoted')"

# Rule: Report Rules (prefix T) and CodeBlock Source (prefix W).
$rptorders = Invoke-IndexQuery -Query 'what-uses' -Type 'Report' -Name 'RPTORDERS'
$rptordersRows = @($rptorders.results)
$toMember = Find-Row $rptordersRows 'Transaction' 'Member' 'calls_transaction' 'target'
Assert-True ($toMember.Count -eq 1) "what-uses Report RPTORDERS should list Transaction Member (calls_transaction); got: $(($rptordersRows | ForEach-Object { "$($_.target_type) $($_.target_name) $($_.relation_kind)" }) -join '; ')"
Assert-True ($toMember[0].line -eq (Get-LineNumberOf $reportXml 'call(TMember)')) "Transaction Member evidence should carry the line of call(TMember) in Rules; got $($toMember[0].line)"
$toWorkPanel = Find-Row $rptordersRows 'WorkPanel' 'MemberRange' 'calls_workpanel' 'target'
Assert-True ($toWorkPanel.Count -eq 1) 'what-uses Report RPTORDERS should list WorkPanel MemberRange (calls_workpanel)'
Assert-True ($toWorkPanel[0].line -eq (Get-LineNumberOf $reportXml 'call(WMemberRange)')) "WorkPanel MemberRange evidence should carry the line of call(WMemberRange); got $($toWorkPanel[0].line)"

# Rule: classic code is not read with the modern regexes (call(PAGO) is Procedure AGO).
foreach ($caller in @(@{ Type = 'WebPanel'; Name = 'WPAGO' }, @{ Type = 'Procedure'; Name = 'LegacyCaller' })) {
    $rows = @((Invoke-IndexQuery -Query 'what-uses' -Type $caller.Type -Name $caller.Name).results)
    Assert-True ((Find-Row $rows 'Procedure' 'AGO' 'calls_procedure' 'target').Count -eq 1) "what-uses $($caller.Type) $($caller.Name) should list Procedure AGO for call(PAGO)"
    Assert-True (@($rows | Where-Object { $_.target_name -eq 'PAGO' }).Count -eq 0) "what-uses $($caller.Type) $($caller.Name) should never list Procedure PAGO for call(PAGO)"
}
$pagoCallers = Invoke-IndexQuery -Query 'who-uses' -Type 'Procedure' -Name 'PAGO'
Assert-True (@($pagoCallers.results).Count -eq 0) 'who-uses Procedure PAGO should be empty'

# Existing behaviour: a modern Procedure keeps the modern call path.
$modern = Invoke-IndexQuery -Query 'what-uses' -Type 'Procedure' -Name 'ModernCaller'
$toModernTarget = Find-Row @($modern.results) 'Procedure' 'ModernTarget' 'calls_procedure' 'target'
Assert-True ($toModernTarget.Count -eq 1) 'what-uses Procedure ModernCaller should still list Procedure ModernTarget (calls_procedure)'
Assert-True ($toModernTarget[0].extractor_rule -eq 'procedure_call_command') "A modern call( should keep the procedure_call_command rule; got $($toModernTarget[0].extractor_rule)"

Write-Output 'OK: Test-KbIntelligenceLegacyClassicCallsSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
