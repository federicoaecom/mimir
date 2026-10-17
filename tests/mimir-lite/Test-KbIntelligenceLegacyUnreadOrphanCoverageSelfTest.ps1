#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: reverse coverage counts the legacy orphans that stay skipped and unread (Prompt).

.DESCRIPTION
    Builds two synthetic classic KBs. KB A holds a classic Procedure, a Prompt (a skipped legacy
    orphan whose events and rules are not read), and a classic Formula (skipped as an object but
    read through the attribute it computes). KB B holds the Procedure only. Proves that:
      - KB A records the unread orphans in the index metadata (legacy_unread_orphan_counts) and its
        reverse answers list Prompt (count 1) under unextracted_source_types, for calls (a Procedure
        target) and for attribute uses (an Attribute target), with complete=false; the text note
        names Prompt (1);
      - Formula is never listed, since its content is read;
      - KB B lists no Prompt and its Procedure target is complete;
      - an index without the metadata key (built before it existed) lists no Prompt.
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

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-LegacyXml {
    param([string]$Type, [string]$Name, [string]$Inner)
    return "<Object type=`"$Type`" name=`"$Name`" guid=`"`" lastUpdate=`"1998-01-01T00:00:00.0000000Z`" dataSource=`"gx-legacy-export`"><GxLegacyPayload>$Inner</GxLegacyPayload></Object>"
}

function New-Kb {
    param([string]$Root, [switch]$WithOrphans)
    $objects = Join-Path $Root 'KbObjectsXml'
    foreach ($folder in @('Procedure', 'Attribute')) { [void](New-Item -ItemType Directory -Path (Join-Path $objects $folder) -Force) }
    [System.IO.File]::WriteAllText((Join-Path $objects 'Procedure/PrcTarget.xml'), (New-LegacyXml -Type $procedureGuid -Name 'PrcTarget' -Inner '<Procedure><Info><Name>PrcTarget</Name></Info><Layout><Block><CodeBlock></CodeBlock></Block></Layout></Procedure>'), $enc)
    [System.IO.File]::WriteAllText((Join-Path $objects 'Attribute/OrdAmount.xml'), (New-LegacyXml -Type 'gxlegacy/Attribute' -Name 'OrdAmount' -Inner '<GXAtt><Attribute><Id>1</Id><Name>OrdAmount</Name></Attribute></GXAtt>').Replace('<Object type="gxlegacy/Attribute"', '<Attribute').Replace('</Object>', '</Attribute>'), $enc)
    if ($WithOrphans) {
        foreach ($folder in @('Prompt', 'Formula')) { [void](New-Item -ItemType Directory -Path (Join-Path $objects $folder) -Force) }
        [System.IO.File]::WriteAllText((Join-Path $objects 'Prompt/PmtOrders.xml'), (New-LegacyXml -Type 'gxlegacy/Prompt' -Name 'PmtOrders' -Inner '<Prompt><Info><Name>PmtOrders</Name></Info><Events><![CDATA[Event Enter
  call(PPrcTarget)
EndEvent]]></Events></Prompt>'), $enc)
        [System.IO.File]::WriteAllText((Join-Path $objects 'Formula/OrdAmount.xml'), (New-LegacyXml -Type 'gxlegacy/Formula' -Name 'OrdAmount' -Inner '<Formula><Name>OrdAmount</Name><Type>SUM</Type><Source><![CDATA[OrdAmount]]></Source></Formula>'), $enc)
    }
    $intel = Join-Path $Root 'KbIntelligence'
    [void](New-Item -ItemType Directory -Path $intel -Force)
    $sqlite = Join-Path $intel 'kb-intelligence.sqlite'
    & $buildScript -SourceRoot $objects -OutputPath $sqlite -ValidationReportPath (Join-Path $intel 'validation.json') `
        -FailOnValidationFailure -KbWorkspaceRoot $Root | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Build-KbIntelligenceIndex should complete for $Root; exit $LASTEXITCODE"
    return $sqlite
}

function Invoke-Coverage {
    param([string]$IndexPath, [string]$WorkspaceRoot, [string]$Type, [string]$Name, [string]$Format = 'json')
    $output = & $queryScript -IndexPath $IndexPath -KbWorkspaceRoot $WorkspaceRoot -Query 'who-uses' `
        -ObjectType $Type -ObjectName $Name -Format $Format 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "who-uses $Type $Name should exit 0; got $LASTEXITCODE"
    if ($Format -eq 'text') { return @($output) }
    return (($output -join "`n") | ConvertFrom-Json).coverage
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-unread-orphan-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
$rootA = Join-Path $tempRoot 'A'
$rootB = Join-Path $tempRoot 'B'
$indexA = New-Kb -Root $rootA -WithOrphans
$indexB = New-Kb -Root $rootB

# Rule: KB A lists Prompt (count 1) for calls and for attribute uses; Formula is never listed.
foreach ($target in @(@{ Type = 'Procedure'; Name = 'PrcTarget' }, @{ Type = 'Attribute'; Name = 'OrdAmount' })) {
    $coverage = Invoke-Coverage -IndexPath $indexA -WorkspaceRoot $rootA -Type $target.Type -Name $target.Name
    $prompt = @($coverage.unextracted_source_types | Where-Object { $_.type -eq 'Prompt' })
    Assert-True ($coverage.complete -eq $false -and $prompt.Count -eq 1 -and $prompt[0].count -eq 1) "who-uses $($target.Type) $($target.Name) on KB A should list Prompt (count 1) as not extracted; got $($coverage | ConvertTo-Json -Compress -Depth 4)"
    Assert-True (@($coverage.unextracted_source_types | Where-Object { $_.type -eq 'Formula' }).Count -eq 0) "Formula should never be listed (its content is read); got $($coverage | ConvertTo-Json -Compress -Depth 4)"
}
$noteLines = @(Invoke-Coverage -IndexPath $indexA -WorkspaceRoot $rootA -Type 'Procedure' -Name 'PrcTarget' -Format 'text' | ForEach-Object { "$_".TrimEnd("`r") } | Where-Object { $_ -match '^coverage:' })
Assert-True ($noteLines.Count -eq 1 -and $noteLines[0].Contains('Prompt (1)')) "The text coverage note should name Prompt (1); got: $($noteLines -join ' | ')"

# Rule: KB B lists no Prompt and its Procedure target is complete.
$coverageB = Invoke-Coverage -IndexPath $indexB -WorkspaceRoot $rootB -Type 'Procedure' -Name 'PrcTarget'
Assert-True ($coverageB.complete -eq $true -and @($coverageB.unextracted_source_types).Count -eq 0) "who-uses Procedure PrcTarget on KB B should be complete; got $($coverageB | ConvertTo-Json -Compress -Depth 4)"

# Rule: an index without the metadata key lists no Prompt.
$oldIndex = Join-Path $tempRoot 'old.sqlite'
Copy-Item -LiteralPath $indexA -Destination $oldIndex
$patchPath = Join-Path $tempRoot 'drop-key.py'
[System.IO.File]::WriteAllText($patchPath, @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("DELETE FROM metadata WHERE key = 'legacy_unread_orphan_counts'")
conn.commit()
conn.close()
'@, $enc)
$python = Get-GeneXusPythonExecutable
Assert-True ($null -ne $python) 'Python 3 is required to drop the metadata key'
$patchOutput = & $python.Source @($python.PrefixArguments) $patchPath $oldIndex 2>&1
Assert-True ($LASTEXITCODE -eq 0) "Dropping the metadata key should succeed; $(@($patchOutput) -join ' ')"
$oldCoverage = Invoke-Coverage -IndexPath $oldIndex -WorkspaceRoot $rootA -Type 'Procedure' -Name 'PrcTarget'
Assert-True (@($oldCoverage.unextracted_source_types | Where-Object { $_.type -eq 'Prompt' }).Count -eq 0) "An index without legacy_unread_orphan_counts should list no Prompt; got $($oldCoverage | ConvertTo-Json -Compress -Depth 4)"

Write-Output 'OK: Test-KbIntelligenceLegacyUnreadOrphanCoverageSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
