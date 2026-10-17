#requires -Version 7.4
<#
.SYNOPSIS
    End-to-end self-test of Sync-GeneXusXpzToXml.ps1 on GeneXus `.xpw` text exports (GeneXus 7.0
    and earlier), from the sync to KB Intelligence queries.

.DESCRIPTION
    Runs the real scripts as child processes over synthetic `.xpw` fixtures written on the fly
    (tests/fixtures/GeneXusXpwFixtureSupport.ps1; every name is invented):
    - a single `.xpw` syncs every object into its folder (Prompt, Menu, and Formula as
      `gxlegacy/*`) and every attribute, with LegacyFormatDetected=true and exit 0; -VerifyOnly on
      the same file then passes;
    - the synced corpus builds a KB index with -FailOnValidationFailure: inventory_semantics OK,
      Prompt/Formula in legacy_orphan_directories_skipped and Menu indexed as its own type, `who-uses Procedure PrcTarget`
      lists the calling Procedure (calls_procedure), and `who-uses Attribute OrdAmount` lists the
      Procedure source reference;
    - a `.zip` with the 1997 split layout (objects file + attributes-only file) syncs both;
    - a lone attributes-only `.xpw` syncs its attributes;
    - a zip mixing `.xpw` and `.xml` entries fails closed with a clear message and writes nothing;
    - an unsupported extension, and a `.zip` with no `.xpw` entry, keep the "Unsupported" error;
    - a classic `.xml` export and the same XML inside an `.xpz` still sync as before.
    Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'GeneXusXpwFixtureSupport.ps1')
. (Join-Path $fixturesRoot 'GeneXusLegacyExportFileFixtureSupport.ps1')

$syncScript = Join-Path $scriptsRoot 'Sync-GeneXusXpzToXml.ps1'
$buildScript = Join-Path $scriptsRoot 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptsRoot 'Query-KbIntelligenceIndex.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function New-WorkRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('xpw-sync-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $root)
    return $root
}

function Invoke-Sync {
    <# Runs the sync; returns exit code, the stdout JSON (when any), and stderr text. #>
    param([string[]]$SyncArgs)
    $output = & pwsh -NoProfile -File $syncScript @SyncArgs 2>&1
    $exitCode = $LASTEXITCODE
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] -and -not [string]::IsNullOrWhiteSpace($_) })
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n"
    $json = $null
    if ($stdout.Count -gt 0) {
        try { $json = $stdout[-1] | ConvertFrom-Json } catch { $json = $null }
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Json = $json; StdErr = $stderr }
}

function Invoke-SyncOk {
    param([string[]]$SyncArgs, [string]$Case)
    $result = Invoke-Sync -SyncArgs $SyncArgs
    Assert-True ($result.ExitCode -eq 0) "${Case}: sync should exit 0; got $($result.ExitCode). stderr: $($result.StdErr)"
    Assert-True ($null -ne $result.Json) "${Case}: sync should print its JSON summary."
    return $result.Json
}

function Get-ObjectRoot {
    param([string]$Path, [string]$Case)
    Assert-True (Test-Path -LiteralPath $Path) "${Case}: expected file not materialized: $Path"
    [xml]$doc = Get-Content -LiteralPath $Path -Raw
    return $doc.DocumentElement
}

# =====================================================================================
# Case 1 — a single .xpw syncs every object and attribute; the index answers who-uses
# =====================================================================================
$work1 = New-WorkRoot
try {
    $xpw = New-GeneXusXpwFixtureFile -Path (Join-Path $work1 'shop.xpw') -Lines (Get-GeneXusXpwSyncFixtureLines)
    $kbWorkspaceRoot = Join-Path $work1 'KbWorkspace'
    $dest = Join-Path $kbWorkspaceRoot 'KbObjectsXml'
    $kbIntelDir = Join-Path $kbWorkspaceRoot 'KbIntelligence'
    [void](New-Item -ItemType Directory -Path $dest, $kbIntelDir -Force)

    $summary = Invoke-SyncOk -SyncArgs @('-InputPath', $xpw, '-DestinationRoot', $dest, '-FullSnapshot') -Case 'Case1'
    Assert-True ([bool]$summary.LegacyFormatDetected) 'Case1: LegacyFormatDetected should be true for a .xpw.'
    Assert-True ($summary.Created -eq 9) "Case1: Created=$($summary.Created) (expected 9: 6 objects, 1 Formula, 2 attributes). Created: $($summary.CreatedNames -join ', ')"

    foreach ($expected in @(
            @{ Folder = 'Transaction'; Name = 'TrnOrder' },
            @{ Folder = 'Procedure'; Name = 'PrcCaller' },
            @{ Folder = 'Procedure'; Name = 'PrcTarget' },
            @{ Folder = 'WorkPanel'; Name = 'WkOrders' },
            @{ Folder = 'Attribute'; Name = 'OrdId' },
            @{ Folder = 'Attribute'; Name = 'OrdAmount' })) {
        $root = Get-ObjectRoot -Path (Join-Path (Join-Path $dest $expected.Folder) "$($expected.Name).xml") -Case 'Case1'
        Assert-True ($root.GetAttribute('dataSource') -eq 'gx-legacy-export') "Case1: $($expected.Folder)/$($expected.Name) should carry dataSource gx-legacy-export."
    }
    foreach ($orphan in @(@{ Folder = 'Prompt'; Name = 'PmtOrder' }, @{ Folder = 'Menu'; Name = 'MnuMain' }, @{ Folder = 'Formula'; Name = 'OrdAmount' })) {
        $root = Get-ObjectRoot -Path (Join-Path (Join-Path $dest $orphan.Folder) "$($orphan.Name).xml") -Case 'Case1'
        Assert-True ($root.GetAttribute('type') -eq "gxlegacy/$($orphan.Folder)") "Case1: $($orphan.Folder)/$($orphan.Name) type='$($root.GetAttribute('type'))' (expected gxlegacy/$($orphan.Folder))."
    }
    $callerRoot = Get-ObjectRoot -Path (Join-Path (Join-Path $dest 'Procedure') 'PrcCaller.xml') -Case 'Case1'
    $callerSource = $callerRoot.SelectSingleNode('./GxLegacyPayload/Procedure/Layout/Block/CodeBlock/Source')
    Assert-True ($null -ne $callerSource -and $callerSource.InnerText.Contains('call(PPrcTarget, &Total)')) 'Case1: the Procedure CodeBlock Source should keep its code.'

    $verify = Invoke-SyncOk -SyncArgs @('-InputPath', $xpw, '-DestinationRoot', $dest, '-VerifyOnly', '-FullSnapshot') -Case 'Case1 VerifyOnly'
    Assert-True ($verify.MissingAfterVerification -eq 0 -and $verify.MismatchesAfterVerification -eq 0) 'Case1: -VerifyOnly on the same .xpw should find no missing or mismatched item.'

    # End to end: build the index on the synced corpus and query it.
    $sqlitePath = Join-Path $kbIntelDir 'kb-intelligence.sqlite'
    $validationPath = Join-Path $kbIntelDir 'kb-intelligence-validation.json'
    & $buildScript -SourceRoot $dest -OutputPath $sqlitePath -ValidationReportPath $validationPath -FailOnValidationFailure -KbWorkspaceRoot $kbWorkspaceRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Case1: Build-KbIntelligenceIndex should complete on the .xpw corpus; exit $LASTEXITCODE"
    $inv = (Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json).inventory_semantics
    Assert-True ($inv.status -eq 'OK') "Case1: inventory_semantics.status should be OK, was $($inv.status)"
    $skipped = @(@($inv.legacy_orphan_directories_skipped) | ForEach-Object { $_.directory })
    foreach ($folder in @('Prompt', 'Formula')) {
        Assert-True ($skipped -contains $folder) "Case1: $folder should be in legacy_orphan_directories_skipped; got: $($skipped -join ', ')"
    }
    Assert-True (-not ($skipped -contains 'Menu')) "Case1: Menu should not be skipped (it is indexed); got: $($skipped -join ', ')"
    Assert-True (@($inv.indexed_objects_by_type.PSObject.Properties.Name) -contains 'Menu') 'Case1: Menu should be indexed as its own type'

    $queryOutput = & $queryScript -IndexPath $sqlitePath -KbWorkspaceRoot $kbWorkspaceRoot -Query 'who-uses' -ObjectType 'Procedure' -ObjectName 'PrcTarget' -Format json 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "Case1: who-uses Procedure PrcTarget should exit 0; got $LASTEXITCODE"
    $callers = @((($queryOutput -join "`n") | ConvertFrom-Json).results)
    $fromCaller = @($callers | Where-Object { $_.source_type -eq 'Procedure' -and $_.source_name -eq 'PrcCaller' -and $_.relation_kind -eq 'calls_procedure' })
    Assert-True ($fromCaller.Count -eq 1) "Case1: who-uses Procedure PrcTarget should list Procedure PrcCaller (calls_procedure); got: $(($callers | ForEach-Object { "$($_.source_type) $($_.source_name) $($_.relation_kind)" }) -join '; ')"

    $attributeOutput = & $queryScript -IndexPath $sqlitePath -KbWorkspaceRoot $kbWorkspaceRoot -Query 'who-uses' -ObjectType 'Attribute' -ObjectName 'OrdAmount' -Format json 2>$null
    Assert-True ($LASTEXITCODE -eq 0) "Case1: who-uses Attribute OrdAmount should exit 0; got $LASTEXITCODE"
    $attributeUsers = @((($attributeOutput -join "`n") | ConvertFrom-Json).results)
    $fromSource = @($attributeUsers | Where-Object { $_.source_type -eq 'Procedure' -and $_.source_name -eq 'PrcCaller' -and $_.relation_kind -eq 'code_references_attribute' })
    Assert-True ($fromSource.Count -eq 1) "Case1: who-uses Attribute OrdAmount should list the Procedure PrcCaller source reference; got: $(($attributeUsers | ForEach-Object { "$($_.source_type) $($_.source_name) $($_.relation_kind)" }) -join '; ')"
} finally {
    if (Test-Path -LiteralPath $work1) { Remove-Item -LiteralPath $work1 -Recurse -Force }
}

# =====================================================================================
# Case 2 — a .zip with the 1997 split layout (objects file + attributes file) syncs both
# =====================================================================================
$work2 = New-WorkRoot
try {
    $entries = [ordered]@{ 'gxw.xpw' = (Get-GeneXusXpwObjectsFixtureLines); 'att.xpw' = (Get-GeneXusXpwAttributesFixtureLines) }
    $zip = New-GeneXusXpwFixtureZip -Path (Join-Path $work2 'export.zip') -Entries $entries
    $dest = Join-Path $work2 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)

    $summary = Invoke-SyncOk -SyncArgs @('-InputPath', $zip, '-DestinationRoot', $dest) -Case 'Case2'
    Assert-True ([bool]$summary.LegacyFormatDetected) 'Case2: LegacyFormatDetected should be true for a .zip of .xpw.'
    Assert-True ($summary.ObjectsBlockCount -eq 8 -and $summary.AttributesBlockCount -eq 2) "Case2: objects=$($summary.ObjectsBlockCount), attributes=$($summary.AttributesBlockCount) (expected 8 and 2)."
    [void](Get-ObjectRoot -Path (Join-Path (Join-Path $dest 'Transaction') 'TrnCustomer.xml') -Case 'Case2')
    [void](Get-ObjectRoot -Path (Join-Path (Join-Path $dest 'Attribute') 'CustId.xml') -Case 'Case2')
} finally {
    if (Test-Path -LiteralPath $work2) { Remove-Item -LiteralPath $work2 -Recurse -Force }
}

# =====================================================================================
# Case 3 — a lone attributes-only .xpw syncs its attributes
# =====================================================================================
$work3 = New-WorkRoot
try {
    $att = New-GeneXusXpwFixtureFile -Path (Join-Path $work3 'att.xpw') -Lines (Get-GeneXusXpwAttributesFixtureLines)
    $dest = Join-Path $work3 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)

    $summary = Invoke-SyncOk -SyncArgs @('-InputPath', $att, '-DestinationRoot', $dest) -Case 'Case3'
    Assert-True ([bool]$summary.LegacyFormatDetected) 'Case3: an attributes-only .xpw should take the legacy path.'
    Assert-True ($summary.ObjectsBlockCount -eq 0 -and $summary.AttributesBlockCount -eq 2) "Case3: objects=$($summary.ObjectsBlockCount), attributes=$($summary.AttributesBlockCount) (expected 0 and 2)."
    [void](Get-ObjectRoot -Path (Join-Path (Join-Path $dest 'Attribute') 'CustId.xml') -Case 'Case3')
} finally {
    if (Test-Path -LiteralPath $work3) { Remove-Item -LiteralPath $work3 -Recurse -Force }
}

# =====================================================================================
# Case 4 — fail-closed and unsupported inputs
# =====================================================================================
$work4 = New-WorkRoot
try {
    $dest = Join-Path $work4 'corpus'
    [void](New-Item -ItemType Directory -Path $dest)
    $meta = Join-Path $work4 'kb-source-metadata.md'

    # 4a — a zip mixing .xpw and .xml entries fails closed and writes nothing.
    $mixedEntries = [ordered]@{ 'gxw.xpw' = (Get-GeneXusXpwObjectsFixtureLines); 'export.xml' = @('<ExportFile/>') }
    $mixed = New-GeneXusXpwFixtureZip -Path (Join-Path $work4 'mixed.zip') -Entries $mixedEntries
    $result = Invoke-Sync -SyncArgs @('-InputPath', $mixed, '-DestinationRoot', $dest, '-KbMetadataPath', $meta)
    Assert-True ($result.ExitCode -ne 0) 'Case4a: a zip mixing .xpw and .xml should fail.'
    Assert-True ($result.StdErr -match 'mixes \.xpw and \.xml entries') "Case4a: the failure should say the zip mixes .xpw and .xml entries; got: $($result.StdErr)"
    Assert-True (-not (Test-Path -LiteralPath $meta)) 'Case4a: a mixed zip should not write kb-source-metadata.md.'
    Assert-True (@(Get-ChildItem -LiteralPath $dest -Recurse -File).Count -eq 0) 'Case4a: a mixed zip should materialize nothing.'

    # 4b — an unsupported extension keeps the existing error.
    $text = Join-Path $work4 'notes.txt'
    [System.IO.File]::WriteAllText($text, 'not an export')
    $result = Invoke-Sync -SyncArgs @('-InputPath', $text, '-DestinationRoot', $dest)
    Assert-True ($result.ExitCode -ne 0 -and $result.StdErr -match 'Unsupported InputPath') "Case4b: a .txt input should fail with 'Unsupported InputPath'; got exit $($result.ExitCode): $($result.StdErr)"

    # 4c — a .zip with no .xpw entry keeps the existing error.
    $xmlOnly = New-GeneXusXpwFixtureZip -Path (Join-Path $work4 'xml-only.zip') -Entries ([ordered]@{ 'export.xml' = @('<ExportFile/>') })
    $result = Invoke-Sync -SyncArgs @('-InputPath', $xmlOnly, '-DestinationRoot', $dest)
    Assert-True ($result.ExitCode -ne 0 -and $result.StdErr -match 'Unsupported InputPath') "Case4c: a .zip without .xpw entries should fail with 'Unsupported InputPath'; got exit $($result.ExitCode): $($result.StdErr)"
} finally {
    if (Test-Path -LiteralPath $work4) { Remove-Item -LiteralPath $work4 -Recurse -Force }
}

# =====================================================================================
# Case 5 — existing inputs: a classic .xml and the same XML inside an .xpz sync as before
# =====================================================================================
$work5 = New-WorkRoot
try {
    $xml = New-GeneXusLegacyExportFixtureFile -Path (Join-Path $work5 'legacy.xml')
    $xpzStage = Join-Path $work5 'stage'
    [void](New-Item -ItemType Directory -Path $xpzStage)
    Copy-Item -LiteralPath $xml -Destination (Join-Path $xpzStage 'legacy.xml')
    $xpzZip = Join-Path $work5 'legacy.zip'
    Compress-Archive -Path (Join-Path $xpzStage 'legacy.xml') -DestinationPath $xpzZip
    $xpz = Join-Path $work5 'legacy.xpz'
    Move-Item -LiteralPath $xpzZip -Destination $xpz

    $destXml = Join-Path $work5 'corpus-xml'
    $destXpz = Join-Path $work5 'corpus-xpz'
    [void](New-Item -ItemType Directory -Path $destXml, $destXpz)
    $fromXml = Invoke-SyncOk -SyncArgs @('-InputPath', $xml, '-DestinationRoot', $destXml) -Case 'Case5 xml'
    $fromXpz = Invoke-SyncOk -SyncArgs @('-InputPath', $xpz, '-DestinationRoot', $destXpz) -Case 'Case5 xpz'
    Assert-True ($fromXml.Created -eq 7 -and $fromXpz.Created -eq 7) "Case5: Created xml=$($fromXml.Created), xpz=$($fromXpz.Created) (expected 7 each)."
    Assert-True ($fromXml.PackageXmlPath -eq (Resolve-Path -LiteralPath $xml).Path) 'Case5: PackageXmlPath of an .xml input should stay the input path.'
    Assert-True ($fromXpz.PackageXmlPath -like '*legacy.xml') 'Case5: PackageXmlPath of an .xpz input should stay the extracted inner XML.'
} finally {
    if (Test-Path -LiteralPath $work5) { Remove-Item -LiteralPath $work5 -Recurse -Force }
}

Write-Output 'MIMIR_SYNC_XPW_SELFTEST_OK'
exit 0
