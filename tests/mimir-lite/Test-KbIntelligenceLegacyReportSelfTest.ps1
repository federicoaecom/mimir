#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: a classic Report (gxlegacy/Report) is indexed and queried as its own type Report.

.DESCRIPTION
    Builds a synthetic KB with a classic Report and a classic-equivalent Procedure that share the
    name RPTORDERS (classic identity is type + name), then proves that:
      - the build completes with inventory_semantics OK and the Report folder in the snapshot;
      - object-info finds Report RPTORDERS and Procedure RPTORDERS as two distinct objects;
      - who-uses, what-uses, and impact-basic answer for Report RPTORDERS (exit 0, not blocked);
      - a gxlegacy/Report object outside a Report folder is still flagged (status BLOCK).
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

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-report-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$tempRootB = $null
try {
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$reportDir = Join-Path $kbObjectsPath 'Report'
$procedureDir = Join-Path $kbObjectsPath 'Procedure'
$kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $reportDir, $procedureDir, $kbIntelDir -Force)

$reportXml = @'
<Object type="gxlegacy/Report" name="RPTORDERS" guid="" lastUpdate="2013-02-27T15:36:48.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<Report>
  <Info><Name>RPTORDERS</Name></Info>
  <Layout><Block><CodeBlock><Source><![CDATA[For Each OrdId
  Where OrdId = &OrdId
EndFor]]></Source></CodeBlock></Block></Layout>
  <Rules><![CDATA[Parm(&OrdId);]]></Rules>
</Report>
  </GxLegacyPayload>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $reportDir 'RPTORDERS.xml'), $reportXml, $enc)

# Same name, other type: classic identity is type + name, so both must stay distinct.
$procedureXml = @'
<Object type="84a12160-f59b-4ad7-a683-ea4481ac23e9" name="RPTORDERS" guid="" lastUpdate="2013-02-27T15:36:48.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
<Procedure>
  <Info><Name>RPTORDERS</Name></Info>
</Procedure>
  </GxLegacyPayload>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $procedureDir 'RPTORDERS.xml'), $procedureXml, $enc)

$sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
$validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'

& $buildScript `
    -SourceRoot $kbObjectsPath `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -FailOnValidationFailure `
    -KbWorkspaceRoot $kbWorkspaceRoot
Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete with a classic Report; exit $LASTEXITCODE"

$inv = (Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json).inventory_semantics
Assert-True ($inv.status -eq 'OK') "inventory_semantics.status should be OK, was $($inv.status)"
Assert-True (@($inv.snapshot_objects_by_directory.PSObject.Properties.Name) -contains 'Report') 'The Report folder should be in snapshot_objects_by_directory'
Assert-True (@($inv.indexed_objects_by_type.PSObject.Properties.Name) -contains 'Report') 'Report should be in indexed_objects_by_type'
Assert-True (@($inv.legacy_orphan_directories_skipped).Count -eq 0) 'No folder should be skipped as a legacy orphan'

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
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json }
}

$reportInfo = Invoke-IndexQuery -Query 'object-info' -Type 'Report' -Name 'RPTORDERS'
Assert-True ($reportInfo.ExitCode -eq 0) "object-info Report RPTORDERS should exit 0; got $($reportInfo.ExitCode)"
Assert-True ($reportInfo.Json.found -eq $true) 'object-info should find Report RPTORDERS'
Assert-True ($reportInfo.Json.object.type -eq 'Report') "object-info Report RPTORDERS should report type Report, was $($reportInfo.Json.object.type)"

$procedureInfo = Invoke-IndexQuery -Query 'object-info' -Type 'Procedure' -Name 'RPTORDERS'
Assert-True ($procedureInfo.Json.found -eq $true) 'object-info should still find Procedure RPTORDERS'
Assert-True ($procedureInfo.Json.object.type -eq 'Procedure') "object-info Procedure RPTORDERS should report type Procedure, was $($procedureInfo.Json.object.type)"
Assert-True ($procedureInfo.Json.object.file_path -ne $reportInfo.Json.object.file_path) 'Report RPTORDERS and Procedure RPTORDERS should be distinct objects'

foreach ($semanticQuery in @('who-uses', 'what-uses', 'impact-basic')) {
    $result = Invoke-IndexQuery -Query $semanticQuery -Type 'Report' -Name 'RPTORDERS'
    Assert-True ($result.ExitCode -eq 0) "$semanticQuery Report RPTORDERS should exit 0; got $($result.ExitCode)"
    $blockedProperty = $result.Json.PSObject.Properties['blocked']
    Assert-True (-not ($blockedProperty -and $blockedProperty.Value)) "$semanticQuery Report RPTORDERS should not be blocked"
    Assert-True ($result.Json.query -eq $semanticQuery) "$semanticQuery Report RPTORDERS should answer the $semanticQuery query, answered $($result.Json.query)"
    Assert-True ($result.Json.object.type -eq 'Report' -and $result.Json.object.name -eq 'RPTORDERS') "$semanticQuery should answer for Report RPTORDERS"
    if ($semanticQuery -eq 'impact-basic') {
        # impact-basic resolves the object in the index: found, and typed Report.
        Assert-True ($result.Json.found -eq $true) 'impact-basic should find Report RPTORDERS in the index'
    }
}

# --- A gxlegacy/Report object in a folder that is not Report is still flagged. ---
$tempRootB = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-legacy-report-misplaced-{0}' -f ([guid]::NewGuid().ToString('N')))
$kbWorkspaceRootB = Join-Path $tempRootB 'KbWorkspace'
$kbObjectsPathB = Join-Path $kbWorkspaceRootB 'KbObjectsXml'
$misplacedDir = Join-Path $kbObjectsPathB 'Procedure'
$kbIntelDirB = Join-Path $kbWorkspaceRootB 'KbIntelligence'
[void](New-Item -ItemType Directory -Path $misplacedDir, $kbIntelDirB -Force)
[System.IO.File]::WriteAllText((Join-Path $misplacedDir 'RPTORDERS.xml'), $reportXml, $enc)

$validationPathB = Join-Path $kbIntelDirB 'kb-intelligence-validation.json'
& $buildScript `
    -SourceRoot $kbObjectsPathB `
    -OutputPath (Join-Path $kbIntelDirB 'kb-intelligence.sqlite') `
    -ValidationReportPath $validationPathB `
    -KbWorkspaceRoot $kbWorkspaceRootB | Out-Null
$invB = (Get-Content -LiteralPath $validationPathB -Raw -Encoding UTF8 | ConvertFrom-Json).inventory_semantics
Assert-True ($invB.status -eq 'BLOCK') "A gxlegacy/Report object in a Procedure folder should produce status BLOCK, was $($invB.status)"

Write-Output 'OK: Test-KbIntelligenceLegacyReportSelfTest.ps1'
} finally {
    foreach ($root in @($tempRoot, $tempRootB)) {
        if ($root -and (Test-Path -LiteralPath $root)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
exit 0
