#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: Test-MimirKbObjectsXmlNaming classifies a legacy orphan element by typeToken,
    not as UNKNOWN_TYPE.

.DESCRIPTION
    Builds a synthetic KB workspace with KbObjectsXml/Report containing a materialized
    XML with <Object type="gxlegacy/Report">. Runs the naming audit -AsJson and proves that:
      - the Report directory classifies as NAMING_OK (ActualType = gxlegacy/Report,
        ExpectedCanonicalName = Report from the registry), instead of UNKNOWN_TYPE;
      - the overall status is NAMING_OK and the exit code is 0.
    The typeToken -> materializedFolderName correspondence comes from the
    gx-legacy-export-element-registry.json registry (dynamic), not inline.
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

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-naming-legacy-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$kbWorkspaceRoot = Join-Path $tempRoot 'KbWorkspace'
$kbObjectsPath = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
$reportDir = Join-Path $kbObjectsPath 'Report'
[void](New-Item -ItemType Directory -Path $reportDir -Force)

$reportOrphanXml = @'
<Object type="gxlegacy/Report" name="rptProof" lastUpdate="0001-01-01T00:00:00.0000000Z" dataSource="gx-legacy-export">
  <GxLegacyPayload>
    <Report><Info><Name>rptProof</Name></Info></Report>
  </GxLegacyPayload>
</Object>
'@
[System.IO.File]::WriteAllText((Join-Path $reportDir 'rptProof.xml'), $reportOrphanXml, $enc)

$namingScript = Join-Path $scriptDir 'Test-MimirKbObjectsXmlNaming.ps1'
$output = & $namingScript -KbWorkspaceRoot $kbWorkspaceRoot -AsJson
Assert-True ($LASTEXITCODE -eq 0) "Test-MimirKbObjectsXmlNaming should exit 0 with the legacy orphan classified; exit $LASTEXITCODE"

$result = $output | ConvertFrom-Json
Assert-True ($result.status -eq 'NAMING_OK') "status should be NAMING_OK, was $($result.status)"

$reportRow = @($result.all | Where-Object { $_.Directory -eq 'Report' })
Assert-True ($reportRow.Count -eq 1) "there should be 1 row for the Report directory, there were $($reportRow.Count)"
Assert-True ($reportRow[0].ActualType -eq 'gxlegacy/Report') "Report's ActualType should be gxlegacy/Report, was $($reportRow[0].ActualType)"
Assert-True ($reportRow[0].NamingStatus -eq 'OK') "Report's NamingStatus should be OK, was $($reportRow[0].NamingStatus)"

Write-Output 'OK: Test-MimirKbObjectsXmlNamingLegacyOrphanSelfTest.ps1'
exit 0
