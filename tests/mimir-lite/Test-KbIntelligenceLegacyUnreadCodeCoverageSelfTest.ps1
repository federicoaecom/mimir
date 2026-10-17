#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: classic Procedure and Report objects with no <CodeBlock> are counted at build time
    and disclosed by reverse-relation coverage (unread_classic_code), so a code shape the
    extractor does not expect never reads as "unused".

.DESCRIPTION
    Builds a synthetic KB of classic objects (root dataSource="gx-legacy-export") plus one modern
    Procedure:

      - Procedure PROCOK keeps its code in Layout/Block/CodeBlock/Source (it calls PROCEMPTY):
        read, not counted.
      - Procedure PROCEMPTY has an empty <CodeBlock>: empty code, not counted.
      - Procedure PROCODD keeps a <Source> outside any <CodeBlock> (a shape no sample shows):
        counted.
      - Report RPTODD has no <Layout> at all: counted.
      - Procedure PROCTEXT keeps a <Source> outside any <CodeBlock> whose CDATA text and an XML
        comment mention "<CodeBlock>": text is not an element, so it is counted.
      - Procedure ModernProc is modern: never counted.

    Proves that:
      - the build records legacy_unread_code_counts {"Procedure": 2, "Report": 1} in the index
        metadata (index-metadata);
      - who-uses of Procedure PROCEMPTY (calls scope) lists the code of the two objects in
        coverage.unread_classic_code, coverage.complete is false, and the text note names them;
      - who-uses of Attribute CustNo (attribute_references scope) carries the same list and a
        note segment, and impact-basic of Procedure PROCEMPTY carries the list and the note too;
      - a copy of the index without the metadata key (built before the counter) lists none, and
        its calls coverage is complete again.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts')
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')
. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')
$enc = Get-Utf8NoBomEncoding
$pythonInterpreter = Get-GeneXusPythonExecutable
if ($null -eq $pythonInterpreter) {
    throw (Get-GeneXusPythonNotFoundMessage)
}
$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'

$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$procedureSourcePartGuid = '528d1c06-a9c2-420d-bd35-21dca83f12ff'
$expectedList = 'Procedure=2;Report=1'
$expectedNoteSegment = 'the code of classic Procedure (2) and Report (1) was not found in Layout/Block/CodeBlock, where classic exports are expected to keep it, so their calls and attribute uses are missing'

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

function Invoke-Query {
    param([string]$IndexPath, [hashtable]$Arguments)
    $output = & $queryScript -IndexPath $IndexPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Query failed (exit $LASTEXITCODE) for $($Arguments.Values -join ' '): $(@($output) -join "`n")"
    }
    return (@($output) -join "`n")
}

function Format-UnreadList($Coverage) {
    if ($null -eq $Coverage.PSObject.Properties['unread_classic_code']) { return '<missing>' }
    return (@($Coverage.unread_classic_code | ForEach-Object { '{0}={1}' -f $_.type, $_.count }) -join ';')
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-unread-code-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $kbObjectsPath = Join-Path $tempRoot 'KbWorkspace/KbObjectsXml'
    foreach ($folder in @('Attribute', 'Procedure', 'Report')) {
        [void](New-Item -ItemType Directory -Path (Join-Path $kbObjectsPath $folder) -Force)
    }
    function Write-Fixture([string]$Folder, [string]$Name, [string]$Xml) {
        [System.IO.File]::WriteAllText((Join-Path $kbObjectsPath "$Folder/$Name.xml"), $Xml, $enc)
    }
    Write-Fixture 'Attribute' 'CustNo' @'
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="CustNo" guid="" lastUpdate="0001-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<GXAtt><Attribute><Id>1</Id><Name>CustNo</Name><Description>CustNo</Description></Attribute></GXAtt>
  </GxLegacyPayload>
</Attribute>
'@
    Write-Fixture 'Procedure' 'PROCOK' (New-ClassicXml -Type $procedureGuid -Name 'PROCOK' -Payload '<Procedure><Info><Name>PROCOK</Name></Info><Layout><Block><CodeBlock><Source><![CDATA[call(PPROCEMPTY, CustNo)]]></Source></CodeBlock></Block></Layout></Procedure>')
    Write-Fixture 'Procedure' 'PROCEMPTY' (New-ClassicXml -Type $procedureGuid -Name 'PROCEMPTY' -Payload '<Procedure><Info><Name>PROCEMPTY</Name></Info><Layout><Block><CodeBlock></CodeBlock></Block></Layout></Procedure>')
    Write-Fixture 'Procedure' 'PROCODD' (New-ClassicXml -Type $procedureGuid -Name 'PROCODD' -Payload '<Procedure><Info><Name>PROCODD</Name></Info><Source><![CDATA[call(PPROCEMPTY, CustNo)]]></Source></Procedure>')
    Write-Fixture 'Procedure' 'PROCTEXT' (New-ClassicXml -Type $procedureGuid -Name 'PROCTEXT' -Payload '<Procedure><Info><Name>PROCTEXT</Name></Info><!-- no <CodeBlock> here --><Source><![CDATA[// moved out of <CodeBlock>
&x = CustNo]]></Source></Procedure>')
    Write-Fixture 'Report' 'RPTODD' (New-ClassicXml -Type 'gxlegacy/Report' -Name 'RPTODD' -Payload '<Report><Info><Name>RPTODD</Name></Info><Rules><![CDATA[parm(&x);]]></Rules></Report>')
    Write-Fixture 'Procedure' 'ModernProc' @"
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="ModernProc" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0f000000-0000-4000-8000-000000000002" name="ModernProc" type="$procedureGuid" description="Modern Procedure">
  <Part type="$procedureSourcePartGuid">
    <Source><![CDATA[&x = 1]]></Source>
  </Part>
</Object>
"@

    $indexPath = Join-Path $tempRoot 'KbWorkspace/KbIntelligence/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force)
    & $buildScript -SourceRoot $kbObjectsPath -OutputPath $indexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex failed; exit $LASTEXITCODE"
    }

    # Metadata.
    $metadata = (Invoke-Query -IndexPath $indexPath -Arguments @{ Query = 'index-metadata'; Format = 'json' }) | ConvertFrom-Json
    $metadataJson = $metadata | ConvertTo-Json -Depth 6 -Compress
    $counts = $null
    foreach ($candidate in @($metadata, $metadata.PSObject.Properties['metadata'].Value)) {
        if ($null -ne $candidate -and $null -ne $candidate.PSObject.Properties['legacy_unread_code_counts']) {
            $counts = $candidate.legacy_unread_code_counts
        }
    }
    if ($null -eq $counts) {
        Add-Failure "[index-metadata] legacy_unread_code_counts should be recorded; got $metadataJson"
    }
    else {
        $parsed = if ($counts -is [string]) { $counts | ConvertFrom-Json } else { $counts }
        $actual = (@($parsed.PSObject.Properties | Sort-Object Name | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ';')
        if ($actual -cne $expectedList) {
            Add-Failure "[index-metadata] legacy_unread_code_counts should be '$expectedList'; got '$actual'"
        }
    }

    # Calls scope.
    $payload = (Invoke-Query -IndexPath $indexPath -Arguments @{ Query = 'who-uses'; ObjectType = 'Procedure'; ObjectName = 'PROCEMPTY'; Format = 'json' }) | ConvertFrom-Json
    if ((Format-UnreadList $payload.coverage) -cne $expectedList) {
        Add-Failure "[who-uses/Procedure:PROCEMPTY/json] coverage.unread_classic_code should be '$expectedList'; got '$(Format-UnreadList $payload.coverage)'"
    }
    if ($payload.coverage.complete -ne $false) {
        Add-Failure "[who-uses/Procedure:PROCEMPTY/json] coverage.complete should be false; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
    }
    if (@($payload.results | Where-Object { $_.source_name -eq 'PROCOK' }).Count -lt 1) {
        Add-Failure "[who-uses/Procedure:PROCEMPTY/json] PROCOK, whose CodeBlock code calls it, should still be listed"
    }
    $text = Invoke-Query -IndexPath $indexPath -Arguments @{ Query = 'who-uses'; ObjectType = 'Procedure'; ObjectName = 'PROCEMPTY'; Format = 'text' }
    $note = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match '^coverage:' })
    if ($note.Count -ne 1 -or -not $note[0].Contains($expectedNoteSegment)) {
        Add-Failure "[who-uses/Procedure:PROCEMPTY/text] the note should contain '$expectedNoteSegment'; got '$($note -join ' | ')'"
    }

    # impact-basic carries the same coverage.
    $payload = (Invoke-Query -IndexPath $indexPath -Arguments @{ Query = 'impact-basic'; ObjectType = 'Procedure'; ObjectName = 'PROCEMPTY'; Format = 'json' }) | ConvertFrom-Json
    if ((Format-UnreadList $payload.coverage) -cne $expectedList) {
        Add-Failure "[impact-basic/Procedure:PROCEMPTY/json] coverage.unread_classic_code should be '$expectedList'; got '$(Format-UnreadList $payload.coverage)'"
    }
    $text = Invoke-Query -IndexPath $indexPath -Arguments @{ Query = 'impact-basic'; ObjectType = 'Procedure'; ObjectName = 'PROCEMPTY'; Format = 'text' }
    $note = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match '^coverage:' })
    if ($note.Count -ne 1 -or -not $note[0].Contains($expectedNoteSegment)) {
        Add-Failure "[impact-basic/Procedure:PROCEMPTY/text] the note should contain '$expectedNoteSegment'; got '$($note -join ' | ')'"
    }

    # Attribute scope.
    $payload = (Invoke-Query -IndexPath $indexPath -Arguments @{ Query = 'who-uses'; ObjectType = 'Attribute'; ObjectName = 'CustNo'; Format = 'json' }) | ConvertFrom-Json
    if ((Format-UnreadList $payload.coverage) -cne $expectedList) {
        Add-Failure "[who-uses/Attribute:CustNo/json] coverage.unread_classic_code should be '$expectedList'; got '$(Format-UnreadList $payload.coverage)'"
    }
    $text = Invoke-Query -IndexPath $indexPath -Arguments @{ Query = 'who-uses'; ObjectType = 'Attribute'; ObjectName = 'CustNo'; Format = 'text' }
    $note = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match '^coverage:' })
    if ($note.Count -ne 1 -or -not $note[0].Contains($expectedNoteSegment)) {
        Add-Failure "[who-uses/Attribute:CustNo/text] the note should contain '$expectedNoteSegment'; got '$($note -join ' | ')'"
    }

    # An index built before the counter (no metadata key) lists none.
    $oldIndexPath = Join-Path $tempRoot 'old/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $oldIndexPath) -Force)
    Copy-Item -LiteralPath $indexPath -Destination $oldIndexPath
    $dropScript = Join-Path $tempRoot 'drop.py'
    [System.IO.File]::WriteAllText($dropScript, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute(""DELETE FROM metadata WHERE key = 'legacy_unread_code_counts'"")`nc.commit()`n", $enc)
    & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $dropScript $oldIndexPath
    if ($LASTEXITCODE -ne 0) { throw "metadata removal failed; exit $LASTEXITCODE" }
    $payload = (Invoke-Query -IndexPath $oldIndexPath -Arguments @{ Query = 'who-uses'; ObjectType = 'Procedure'; ObjectName = 'PROCEMPTY'; Format = 'json' }) | ConvertFrom-Json
    if ((Format-UnreadList $payload.coverage) -cne '') {
        Add-Failure "[who-uses/old index] coverage.unread_classic_code should be empty; got '$(Format-UnreadList $payload.coverage)'"
    }
    if ($payload.coverage.complete -ne $true) {
        Add-Failure "[who-uses/old index] calls coverage should be complete without the counter; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceLegacyUnreadCodeCoverageSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligenceLegacyUnreadCodeCoverageSelfTest.ps1'
exit 0
