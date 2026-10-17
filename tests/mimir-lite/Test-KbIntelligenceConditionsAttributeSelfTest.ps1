#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: attribute uses in Conditions are indexed with the role 'Conditions read'.

.DESCRIPTION
    Builds a synthetic KB with classic objects (root dataSource="gx-legacy-export", conditions in a
    <Conditions> section) and modern objects (a Conditions Part, type
    763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9) and proves that:
      - a classic Work Panel, Report, and Procedure relate each attribute of their <Conditions> with
        the role 'Conditions read': a comparison, a .LIKE. filter, an .OR. with nullvalue(), a
        function argument (year(Attribute)), and an attribute right after .AND. or .LIKE.; a classic
        WebPanel <Conditions> too, with the line of the condition as the evidence line;
      - a modern WebPanel, Procedure, and WorkPanel relate the attributes of their Conditions Part the same way,
        including a condition with a when clause;
      - a condition is never a write ('Conditions write' never appears), and an &variable named like
        an attribute is not a use;
      - a call in a classic <Conditions> (udp(P...)) relates to the Procedure;
      - for an Attribute target, the coverage of Procedure, WebPanel, WorkPanel, and Report lists
        'condition reads' as extracted and no longer lists 'conditions' as missing; an index whose
        extractor_signature_version is rewritten to 20 lists 'condition reads' first in missing.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')
. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')
$enc = Get-Utf8NoBomEncoding

$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'

$procedureGuid = '84a12160-f59b-4ad7-a683-ea4481ac23e9'
$webPanelGuid = 'c9584656-94b6-4ccd-890f-332d11fc2c25'
$workPanelGuid = '198e8ea4-1d49-4c9c-8a9a-417024baa9d1'
$conditionsPartGuid = '763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-ClassicXml {
    param([string]$Type, [string]$Name, [string]$RootElement, [string]$Body)
    return @"
<Object type="$Type" name="$Name" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<$RootElement>
  <Info><Name>$Name</Name></Info>
$Body
</$RootElement>
  </GxLegacyPayload>
</Object>
"@
}

function New-ClassicAttributeXml {
    param([string]$Name)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute name="$Name" guid="" lastUpdate="1998-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<GXAtt><Attribute><Id>1</Id><Name>$Name</Name><Description>$Name</Description></Attribute></GXAtt>
  </GxLegacyPayload>
</Attribute>
"@
}

function New-ModernXml {
    param([string]$Type, [string]$Name, [string]$Guid, [string]$Conditions)
    return @"
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" lastUpdate="2026-01-01T00:00:00" fullyQualifiedName="$Name" moduleGuid="00000000-0000-0000-0000-000000000000" guid="$Guid" name="$Name" type="$Type" description="Synthetic object with conditions">
  <Part type="$conditionsPartGuid">
    <Source><![CDATA[$Conditions]]></Source>
  </Part>
</Object>
"@
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-conditions-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
$folders = @{}
foreach ($folder in @('WorkPanel', 'WebPanel', 'Procedure', 'Report', 'Attribute')) {
    $folders[$folder] = Join-Path $kbObjectsPath $folder
}
[void](New-Item -ItemType Directory -Path @($folders.Values) -Force)
[void](New-Item -ItemType Directory -Path $kbIntelDir -Force)

function Write-Fixture {
    param([string]$Folder, [string]$Name, [string]$Xml)
    [System.IO.File]::WriteAllText((Join-Path $folders[$Folder] "$Name.xml"), $Xml, $enc)
}

foreach ($attributeName in @('FltName', 'FltDate', 'FltYear', 'FltId', 'FltNro', 'FltCode', 'FltKind', 'FltVarOnly', 'FltA', 'FltB', 'FltC', 'FltWeb', 'FltWkModern')) {
    Write-Fixture 'Attribute' $attributeName (New-ClassicAttributeXml -Name $attributeName)
}

Write-Fixture 'WorkPanel' 'WkFilter' (New-ClassicXml -Type $workPanelGuid -Name 'WkFilter' -RootElement 'WorkPanel' -Body @'
  <Conditions><![CDATA[FltName .LIKE. &C1 ;
FltDate = &FltDate .OR. &FltDate = nullvalue(&FltDate ) ;
year(FltYear ) >= &Year ;
FltA = 1 .AND. FltB = 2 ;
&Pattern .LIKE. FltC ;
&FltVarOnly = 1 ;]]></Conditions>
'@)
$webPanelXml = New-ClassicXml -Type $webPanelGuid -Name 'WpFilter' -RootElement 'WebPanel' -Body @'
  <Conditions><![CDATA[FltWeb = &Web ;]]></Conditions>
'@
Write-Fixture 'WebPanel' 'WpFilter' $webPanelXml
Write-Fixture 'Report' 'RptFilter' (New-ClassicXml -Type 'gxlegacy/Report' -Name 'RptFilter' -RootElement 'Report' -Body @'
  <Conditions><![CDATA[FltId <= &CodFin ;
FltId >= udp(PFltDefault) ;]]></Conditions>
'@)
Write-Fixture 'Procedure' 'PrcFilter' (New-ClassicXml -Type $procedureGuid -Name 'PrcFilter' -RootElement 'Procedure' -Body @'
  <Conditions><![CDATA[FltNro = &FltNro ;]]></Conditions>
'@)
Write-Fixture 'Procedure' 'FltDefault' (New-ClassicXml -Type $procedureGuid -Name 'FltDefault' -RootElement 'Procedure' -Body '')
Write-Fixture 'WebPanel' 'ModernFilterPanel' (New-ModernXml -Type $webPanelGuid -Name 'ModernFilterPanel' -Guid '0f000000-0000-4000-8000-000000000001' -Conditions "FltCode = &Code when not &Code.IsEmpty();`n")
Write-Fixture 'Procedure' 'ModernFilterProc' (New-ModernXml -Type $procedureGuid -Name 'ModernFilterProc' -Guid '0f000000-0000-4000-8000-000000000002' -Conditions "FltKind = &Kind;`n")
Write-Fixture 'WorkPanel' 'ModernFilterWk' (New-ModernXml -Type $workPanelGuid -Name 'ModernFilterWk' -Guid '0f000000-0000-4000-8000-000000000003' -Conditions "FltWkModern = &Value;`n")

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
& $buildScript -SourceRoot $kbObjectsPath -OutputPath $sqlitePath -ValidationReportPath $validationPath `
    -FailOnValidationFailure -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete; exit $LASTEXITCODE"

function Invoke-IndexQuery {
    param([string]$Query, [string]$Type, [string]$Name, [string]$IndexPath = $sqlitePath)
    $output = & $queryScript -IndexPath $IndexPath -KbWorkspaceRoot $kbWorkspaceRoot -Query $Query `
        -ObjectType $Type -ObjectName $Name -Format json 2>&1
    $exitCode = $LASTEXITCODE
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($stdout)) {
        throw "ASSERT FAILED: $Query $Type $Name returned no output (exit $exitCode). stderr: $stderr"
    }
    try { $json = $stdout | ConvertFrom-Json }
    catch { throw "ASSERT FAILED: $Query $Type $Name did not return JSON (exit $exitCode). stderr: $stderr" }
    Assert-True ($exitCode -eq 0) "$Query $Type $Name should exit 0; got $exitCode. output: $stdout $stderr"
    return $json
}

function Format-Rows {
    param($Rows)
    return (@($Rows) | ForEach-Object { "$($_.source_type) $($_.source_name) $($_.relation_kind) [$($_.evidence_role)]" }) -join '; '
}

# Rule: each attribute of a condition relates with 'Conditions read', classic and modern.
$expectedUses = @(
    @{ Attribute = 'FltName'; Type = 'WorkPanel'; Name = 'WkFilter' },
    @{ Attribute = 'FltDate'; Type = 'WorkPanel'; Name = 'WkFilter' },
    @{ Attribute = 'FltYear'; Type = 'WorkPanel'; Name = 'WkFilter' },
    @{ Attribute = 'FltId'; Type = 'Report'; Name = 'RptFilter' },
    @{ Attribute = 'FltNro'; Type = 'Procedure'; Name = 'PrcFilter' },
    @{ Attribute = 'FltCode'; Type = 'WebPanel'; Name = 'ModernFilterPanel' },
    @{ Attribute = 'FltKind'; Type = 'Procedure'; Name = 'ModernFilterProc' },
    @{ Attribute = 'FltA'; Type = 'WorkPanel'; Name = 'WkFilter' },
    @{ Attribute = 'FltB'; Type = 'WorkPanel'; Name = 'WkFilter' },
    @{ Attribute = 'FltC'; Type = 'WorkPanel'; Name = 'WkFilter' },
    @{ Attribute = 'FltWeb'; Type = 'WebPanel'; Name = 'WpFilter' },
    @{ Attribute = 'FltWkModern'; Type = 'WorkPanel'; Name = 'ModernFilterWk' }
)
foreach ($expected in $expectedUses) {
    $rows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name $expected.Attribute).results)
    $match = @($rows | Where-Object {
        $_.source_type -eq $expected.Type -and $_.source_name -eq $expected.Name -and
        $_.relation_kind -eq 'code_references_attribute' -and $_.evidence_role -eq 'Conditions read'
    })
    Assert-True ($match.Count -eq 1) "who-uses Attribute $($expected.Attribute) should list $($expected.Type) $($expected.Name) [Conditions read]; got: $(Format-Rows $rows)"
    Assert-True (@($rows | Where-Object { $_.evidence_role -eq 'Conditions write' }).Count -eq 0) "A condition is never a write; got: $(Format-Rows $rows)"
}

# Rule: the evidence line of a classic condition is the line of that condition in the XML file.
$webRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'FltWeb').results)
$expectedLine = [array]::IndexOf(($webPanelXml -split "`n"), (($webPanelXml -split "`n") | Where-Object { $_.Contains('FltWeb = &Web') } | Select-Object -First 1)) + 1
Assert-True ($webRows.Count -eq 1 -and $webRows[0].line -eq $expectedLine) "FltWeb evidence should carry line $expectedLine; got: $(($webRows | ForEach-Object { $_.line }) -join ',')"

# Rule: an &variable named like an attribute is not a use.
$varOnlyRows = @((Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'FltVarOnly').results)
Assert-True ($varOnlyRows.Count -eq 0) "who-uses Attribute FltVarOnly should be empty (&FltVarOnly is a variable); got: $(Format-Rows $varOnlyRows)"

# Rule: a call in a classic <Conditions> relates.
$reportRows = @((Invoke-IndexQuery -Query 'what-uses' -Type 'Report' -Name 'RptFilter').results)
Assert-True (@($reportRows | Where-Object { $_.target_type -eq 'Procedure' -and $_.target_name -eq 'FltDefault' -and $_.relation_kind -eq 'calls_procedure' }).Count -eq 1) "what-uses Report RptFilter should list Procedure FltDefault for udp(PFltDefault) in Conditions; got: $(($reportRows | ForEach-Object { "$($_.target_type) $($_.target_name) $($_.relation_kind)" }) -join '; ')"

# Rule: coverage lists 'condition reads' as extracted and drops 'conditions' from missing.
$coverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'FltName').coverage
foreach ($type in @('Procedure', 'WebPanel', 'WorkPanel', 'Report')) {
    $entry = @($coverage.partially_extracted_source_types | Where-Object { $_.type -eq $type })
    Assert-True ($entry.Count -eq 1) "Coverage should list $type as partly extracted; got $($coverage | ConvertTo-Json -Compress -Depth 4)"
    Assert-True (@($entry[0].extracted) -contains 'condition reads') "$type coverage should list 'condition reads' as extracted; got '$(@($entry[0].extracted) -join ',')'"
    Assert-True (-not (@($entry[0].missing) -contains 'conditions')) "$type coverage should no longer list 'conditions' as missing; got '$(@($entry[0].missing) -join ',')'"
}

# Rule: an index built by extractor 20 lists 'condition reads' first in missing.
$oldIndexPath = Join-Path $kbIntelDir 'kb-intelligence-20.sqlite'
Copy-Item -LiteralPath $sqlitePath -Destination $oldIndexPath
$patchPath = Join-Path $tempRoot 'patch-version.py'
[System.IO.File]::WriteAllText($patchPath, @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE metadata SET value = '20' WHERE key = 'extractor_signature_version'")
conn.commit()
conn.close()
'@, $enc)
$python = Get-GeneXusPythonExecutable
Assert-True ($null -ne $python) 'Python 3 is required to rewrite the index version'
$patchOutput = & $python.Source @($python.PrefixArguments) $patchPath $oldIndexPath 2>&1
Assert-True ($LASTEXITCODE -eq 0) "Rewriting the index version to 20 should succeed; $(@($patchOutput) -join ' ')"
$oldCoverage = (Invoke-IndexQuery -Query 'who-uses' -Type 'Attribute' -Name 'FltName' -IndexPath $oldIndexPath).coverage
foreach ($type in @('Procedure', 'WebPanel', 'WorkPanel', 'Report')) {
    $entry = @($oldCoverage.partially_extracted_source_types | Where-Object { $_.type -eq $type })
    Assert-True ($entry.Count -eq 1 -and @($entry[0].missing)[0] -eq 'condition reads') "On a version 20 index, $type coverage should list 'condition reads' first in missing; got $($oldCoverage | ConvertTo-Json -Compress -Depth 4)"
}

Write-Output 'OK: Test-KbIntelligenceConditionsAttributeSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
