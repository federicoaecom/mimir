#requires -Version 7.4
<#
.SYNOPSIS
    Sync and index regression for five object types first seen in public samples:
    OfflineDatabase, ThemeTransformation, BusinessProcessDiagram, WorkflowRole, and
    WorkflowDocument.

.DESCRIPTION
    Writes a synthetic ExportFile package (no real KB data) with one minimal object per
    type, using each type's GUID from the XPZ Dependencies block of the public samples.
    The objects carry only <Properties>, the shape the GXflow Role and WorkflowDocument
    objects have in a real export.

    - Sync-GeneXusXpzToXml.ps1 must not block on an unknown type: exit 0, and each object
      materializes as KbObjectsXml/<folderName>/<name>.xml.
    - Build-KbIntelligenceIndex.ps1 must build an index over that corpus, and
      list-by-type must find each object under its catalog type.
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

$syncScript = Join-Path $scriptDir 'Sync-GeneXusXpzToXml.ps1'
$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.py'

$types = @(
    [pscustomobject]@{ Folder = 'OfflineDatabase'; TypeGuid = '70b6075c-331c-0000-0038-ac3b65316dd0'; Name = 'MenuOfflineDatabase'; Guid = '0a000000-0000-4000-8000-000000000001' },
    [pscustomobject]@{ Folder = 'ThemeTransformation'; TypeGuid = '2258230e-d565-4b79-8103-caff9f453a1f'; Name = 'MapCollapse'; Guid = '0a000000-0000-4000-8000-000000000002' },
    [pscustomobject]@{ Folder = 'BusinessProcessDiagram'; TypeGuid = 'b5f00807-9da8-4cf9-b408-7554f2b6a8ee'; Name = 'Purchases'; Guid = '0a000000-0000-4000-8000-000000000003' },
    [pscustomobject]@{ Folder = 'WorkflowRole'; TypeGuid = '3e62f22c-a0db-476e-915b-9f06dde83f4d'; Name = 'Administrative'; Guid = '0a000000-0000-4000-8000-000000000004' },
    [pscustomobject]@{ Folder = 'WorkflowDocument'; TypeGuid = '12b41a58-3890-4adf-9134-820aaa4c6404'; Name = 'RepairImage'; Guid = '0a000000-0000-4000-8000-000000000005' }
)

$objectXml = foreach ($type in $types) {
    @"
    <Object parentGuid="00000000-0000-0000-0000-000000000000" user="SampleKbUser" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-01-01T00:00:00.0000000Z" fullyQualifiedName="$($type.Name)" moduleGuid="00000000-0000-0000-0000-000000000000" guid="$($type.Guid)" name="$($type.Name)" type="$($type.TypeGuid)" description="Synthetic $($type.Folder)">
      <Properties><Property><Name>Name</Name><Value>$($type.Name)</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Object>
"@
}
$packageXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <Objects>
$($objectXml -join "`n")
  </Objects>
</ExportFile>
"@

$failures = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-sync-gxflow-offline-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)
    $packagePath = Join-Path $tempRoot 'package.xml'
    [System.IO.File]::WriteAllText($packagePath, $packageXml, (Get-Utf8NoBomEncoding))
    $corpus = Join-Path $tempRoot 'KbObjectsXml'
    [void](New-Item -ItemType Directory -Path $corpus -Force)
    $discoveryPath = Join-Path $tempRoot 'unknown-type-discovery.json'

    # --- sync: no unknown-type block, one file per object in its catalog folder ---
    $errFile = Join-Path $tempRoot 'sync-stderr.txt'
    $stdout = & pwsh -NoProfile -File $syncScript -InputPath $packagePath -DestinationRoot $corpus -DiscoveryReportPath $discoveryPath 2>$errFile
    $syncExit = $LASTEXITCODE
    $stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { '' }
    if ($syncExit -ne 0) {
        throw "sync should succeed for the five catalog types; exit $syncExit. stderr: $stderr stdout: $(@($stdout) -join ' ')"
    }
    if (Test-Path -LiteralPath $discoveryPath) {
        $failures.Add("sync wrote an unknown-type discovery report: $(Get-Content -LiteralPath $discoveryPath -Raw)")
    }
    foreach ($type in $types) {
        $expected = Join-Path (Join-Path $corpus $type.Folder) ($type.Name + '.xml')
        if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) {
            $failures.Add("[$($type.Folder)] expected materialized file $($type.Folder)/$($type.Name).xml")
        }
    }

    # --- index: builds over the corpus, and each object is listed under its type ---
    $indexPath = Join-Path $tempRoot 'KbIntelligence/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force)
    & $buildScript -SourceRoot $corpus -OutputPath $indexPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Build-KbIntelligenceIndex should pass over the synced corpus; exit $LASTEXITCODE"
    }
    foreach ($type in $types) {
        $output = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $indexPath --query list-by-type --object-type $type.Folder --format json 2>&1
        $queryExit = $LASTEXITCODE
        $text = @($output) -join "`n"
        if ($queryExit -ne 0) {
            $failures.Add("[$($type.Folder)] list-by-type should exit 0; got ${queryExit}: $text")
            continue
        }
        $payload = $text | ConvertFrom-Json
        $names = @($payload.results | ForEach-Object { [string]$_.name })
        if ($names -notcontains $type.Name) {
            $failures.Add("[$($type.Folder)] list-by-type should list $($type.Name); got: $($names -join ',')")
        }
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-GeneXusXpzSyncGxflowOfflineTypesSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-GeneXusXpzSyncGxflowOfflineTypesSelfTest.ps1'
exit 0
