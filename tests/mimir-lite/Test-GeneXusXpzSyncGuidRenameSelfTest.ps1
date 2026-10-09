#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for GUID-aware rename reconciliation in Sync-GeneXusXpzToXml.ps1.

.DESCRIPTION
    Covers Resolve-GuidAwareRenames's paths under -FullSnapshot:
      A. Real rename (Apply): same GUID, different name -> Move-Item old->new;
         a single file, no Extra residue, no throw, RenamedByGuid = 1.
      B. Check (-VerifyOnly): does not touch disk; classifies the residue
         (RenameResidualsDetected = 1, Action 'detected'). The check still
         flags the corpus as stale (non-zero exit), but the report, written
         before the throw, already explains that it is a rename.
      C. Zero renames (Apply): corpus already in sync -> exit 0, no error
         (StrictMode regression when the rename list came back empty).
      D. Orphan from a previous materialization: old name and new name both exist
         with the same GUID -> removes the old name and preserves the target.
      E. GUID collision (Apply): the new name already belongs to ANOTHER object
         (different GUID) -> fail-closed (throw) BEFORE writing; the existing object and
         the old-name one are both preserved (no data loss).
      F. Case-only rename (Apply): same GUID, name differs only in case ->
         the file on disk ends up with the new-case name.
      H. Delta rename (Apply, no -FullSnapshot): same GUID, different name in an
         incremental package -> the old file is renamed, a single file remains,
         and the JSON reports RenamedByGuid = 1 (not Created = 1). Files of other
         objects that the delta does not carry are preserved.
      I. Delta with an ambiguous GUID (two corpus files already share the incoming
         item's GUID): exit 0, no rename, the item is created under its new name,
         both old files are untouched, a warning names the GUID and both files, and
         kb-source-metadata.md is refreshed together with the write.
      J. Delta rename under -VerifyOnly: the rename is only classified
         (RenameResidualsDetected = 1), nothing is moved or created, and
         kb-source-metadata.md keeps its exact bytes.
      K. Delta with an unreadable XML in the scanned type folder: the rename check
         does not abort the sync after the metadata write; the rename in that folder
         is skipped, the item is created under its new name, the unreadable file and
         the old file are untouched, and a warning names the GUID and the file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Sync-GeneXusXpzToXml.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-sync-guid-rename-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function New-AttrFile {
    param([string]$Path, [string]$Guid, [string]$Name, [string]$LastUpdate, [string]$Description = '')
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<Attribute lastUpdate="$LastUpdate" guid="$Guid" name="$Name" description="$Description"><Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c" /></Attribute>
"@
    Write-Utf8 -Path $Path -Content $xml
}

function New-Package {
    param([string]$Path, [string]$Guid, [string]$Name, [string]$LastUpdate, [string]$Description = '')
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <Objects />
  <Attributes>
    <Attribute lastUpdate="$LastUpdate" guid="$Guid" name="$Name" description="$Description"><Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c" /></Attribute>
  </Attributes>
</ExportFile>
"@
    Write-Utf8 -Path $Path -Content $xml
}

function New-ExistingMetadata {
    param([string]$Path)
    $content = @'
---
name: KB Source Metadata
description: GUID rename self-test
updated: 2020-01-01T00:00:00.0000000Z
last_xpz_materialization_run_at: 2020-01-01T00:00:00.0000000Z
source_xpz: C:\Old\Package.xpz
source_refresh_status: partial-preserved
---

## KMW

| Field | Value |
|---|---|
| MajorVersion | 17 |
| MinorVersion | 0 |
| Build | 100 |

## Source

| Field | Value |
|---|---|
| kb (GUID) | {11111111-1111-1111-1111-111111111111} |
| username | old-user |
| UNCPath | \\old\share |

## Source/Version

| Field | Value |
|---|---|
| guid | {22222222-2222-2222-2222-222222222222} |
| name | OldVersion |
'@
    Write-Utf8 -Path $Path -Content $content
}

function New-CaseDir {
    param([string]$Name)
    $corpus = Join-Path (Join-Path $tempRoot $Name) 'KbObjectsXml'
    $attrDir = Join-Path $corpus 'Attribute'
    [void](New-Item -ItemType Directory -Path $attrDir -Force)
    return [pscustomobject]@{ Root = (Join-Path $tempRoot $Name); Corpus = $corpus; AttrDir = $attrDir }
}

function Invoke-Sync {
    param([string]$Pkg, [string]$Corpus, [switch]$VerifyOnly, [string]$ReportPath, [string[]]$ExpectedItems, [switch]$Delta, [string]$KbMetadataPath)
    $psArgs = @('-NoProfile', '-File', $scriptPath, '-InputPath', $Pkg, '-DestinationRoot', $Corpus)
    if ($KbMetadataPath) { $psArgs += @('-KbMetadataPath', $KbMetadataPath) }
    if (-not $Delta) { $psArgs += '-FullSnapshot' }
    if ($VerifyOnly) { $psArgs += '-VerifyOnly' }
    if ($ReportPath) { $psArgs += @('-ReportPath', $ReportPath, '-KeepReport') }
    if ($ExpectedItems) { $psArgs += @('-ExpectedItems', ($ExpectedItems -join ',')) }
    # stdout and stderr captured SEPARATELY: the contract requires stdout = pure single-line
    # JSON, with all human-readable text on stderr. 2>$errFile isolates the child's two streams.
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $stdout = & pwsh @psArgs 2>$errFile
        $exit = $LASTEXITCODE
        $stderr = Get-Content -LiteralPath $errFile -Raw
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
    $stdoutText = ($stdout | Out-String)
    return [pscustomobject]@{
        ExitCode = $exit
        StdOut = $stdoutText
        StdErr = $stderr
        Output = ($stdoutText + [Environment]::NewLine + $stderr)
    }
}

function Assert-StdoutIsPureJson {
    param([string]$Case, [object]$Result)
    $raw = $Result.StdOut.Trim()
    # Stdout must be EXCLUSIVELY the summary JSON: a single line, parseable, with no
    # leaked human text. (Write-Host would leak; that is why the engine uses [Console]::Error.)
    if ($raw -match "`n") { throw "${Case}: stdout should be a single JSON line (-Compress); it contains line breaks. StdOut: $raw" }
    try {
        $obj = $raw | ConvertFrom-Json
    } catch {
        throw "${Case}: stdout should be parseable JSON; failed: $($_.Exception.Message). StdOut: $raw"
    }
    if ($obj.Kind -ne 'mimir-sync-result') { throw "${Case}: stdout JSON.Kind should be 'mimir-sync-result'; got '$($obj.Kind)'" }
    if ($obj.SchemaVersion -ne 1) { throw "${Case}: stdout JSON.SchemaVersion should be 1; got '$($obj.SchemaVersion)'" }
    return $obj
}

try {
    $guid1 = '11111111-1111-1111-1111-111111111111'
    $guid2 = '22222222-2222-2222-2222-222222222222'

    # --- A: rename real (Apply) ---
    $a = New-CaseDir -Name 'apply'
    New-AttrFile -Path (Join-Path $a.AttrDir 'ExemploNome.xml') -Guid $guid1 -Name 'ExemploNome' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $pkgA = Join-Path $a.Root 'pacote.xml'
    New-Package -Path $pkgA -Guid $guid1 -Name 'ExemploNomeTeste' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $repA = Join-Path $a.Root 'report.json'
    $rA = Invoke-Sync -Pkg $pkgA -Corpus $a.Corpus -ReportPath $repA
    if ($rA.ExitCode -ne 0) { throw "A: expected exit 0; got $($rA.ExitCode). Output: $($rA.Output)" }
    if (-not (Test-Path -LiteralPath (Join-Path $a.AttrDir 'ExemploNomeTeste.xml'))) { throw "A: the new file should exist" }
    if (Test-Path -LiteralPath (Join-Path $a.AttrDir 'ExemploNome.xml')) { throw "A: the old file should have been renamed" }
    $repAObj = Get-Content -LiteralPath $repA -Raw | ConvertFrom-Json
    if ($repAObj.Summary.RenamedByGuid -ne 1) { throw "A: RenamedByGuid should be 1; got $($repAObj.Summary.RenamedByGuid)" }
    if ($repAObj.Summary.FullSnapshotExtra -ne 0) { throw "A: FullSnapshotExtra should be 0; got $($repAObj.Summary.FullSnapshotExtra)" }
    # Stdout contract: pure single-line JSON, no leaked human text.
    $aObj = Assert-StdoutIsPureJson -Case 'A' -Result $rA
    if (@($aObj.RenamedByGuidItems).Count -ne 1) { throw "A: RenamedByGuidItems should have 1 item; got $(@($aObj.RenamedByGuidItems).Count)" }
    if ($aObj.RenamedByGuidItems[0].Action -ne 'renamed') { throw "A: Action should be 'renamed'; got '$($aObj.RenamedByGuidItems[0].Action)'" }
    if ($aObj.RenamedByGuidItems[0].OldName -ne 'ExemploNome' -or $aObj.RenamedByGuidItems[0].NewName -ne 'ExemploNomeTeste') { throw "A: RenamedByGuidItems should expose Old->New; got '$($aObj.RenamedByGuidItems[0].OldName)'->'$($aObj.RenamedByGuidItems[0].NewName)'" }
    # Invariant len(*Names) == counter (UpdatedNames, since a rename rewrites the content).
    if (@($aObj.UpdatedNames).Count -ne $aObj.Updated) { throw "A: len(UpdatedNames) ($(@($aObj.UpdatedNames).Count)) != Updated ($($aObj.Updated))" }
    # ExpectedItems was not passed: the expected-items lists should be null (not [] nor absent).
    if ($null -ne $aObj.ExpectedReturnedNames) { throw "A: without -ExpectedItems, ExpectedReturnedNames should be null" }

    # --- B: check (-VerifyOnly) classifies without moving ---
    $b = New-CaseDir -Name 'verify'
    New-AttrFile -Path (Join-Path $b.AttrDir 'ExemploNome.xml') -Guid $guid1 -Name 'ExemploNome' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $pkgB = Join-Path $b.Root 'pacote.xml'
    New-Package -Path $pkgB -Guid $guid1 -Name 'ExemploNomeTeste' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $repB = Join-Path $b.Root 'report.json'
    $rB = Invoke-Sync -Pkg $pkgB -Corpus $b.Corpus -VerifyOnly -ReportPath $repB
    if (-not (Test-Path -LiteralPath (Join-Path $b.AttrDir 'ExemploNome.xml'))) { throw "B: VerifyOnly should not touch disk (old file)" }
    if (Test-Path -LiteralPath (Join-Path $b.AttrDir 'ExemploNomeTeste.xml')) { throw "B: VerifyOnly should not create the new file" }
    if (-not (Test-Path -LiteralPath $repB)) { throw "B: the report should have been written before the throw (exit=$($rB.ExitCode))" }
    $repBObj = Get-Content -LiteralPath $repB -Raw | ConvertFrom-Json
    if ($repBObj.Summary.RenameResidualsDetected -ne 1) { throw "B: RenameResidualsDetected should be 1; got $($repBObj.Summary.RenameResidualsDetected)" }
    if ($repBObj.Summary.RenamedByGuid -ne 0) { throw "B: RenamedByGuid should be 0 in VerifyOnly; got $($repBObj.Summary.RenamedByGuid)" }
    # Contract: the JSON is emitted BEFORE the verification throw, so stdout has parseable
    # JSON even with a non-zero exit. In VerifyOnly the write lists are empty by
    # construction -> serialize as [] (empty array), never null nor a scalar.
    $bObj = Assert-StdoutIsPureJson -Case 'B' -Result $rB
    if (@($bObj.CreatedNames).Count -ne 0) { throw "B: VerifyOnly -> CreatedNames should be an empty []; got $(@($bObj.CreatedNames).Count)" }
    if (@($bObj.UnchangedNames).Count -ne 0) { throw "B: VerifyOnly -> UnchangedNames should be an empty []" }
    if (@($bObj.RenamedByGuidItems).Count -ne 0) { throw "B: VerifyOnly -> RenamedByGuidItems should be an empty [] (detected does not count)" }
    # The human-readable summary (Format-List, multi-line) must be on STDERR, never on stdout.
    if ($rB.StdErr -notmatch 'MaterializationInterpretation') { throw "B: the human-readable summary should be on stderr; not found" }

    # --- C: zero renames (corpus already in sync) ---
    $c = New-CaseDir -Name 'zero'
    New-AttrFile -Path (Join-Path $c.AttrDir 'Alpha.xml') -Guid $guid1 -Name 'Alpha' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $pkgC = Join-Path $c.Root 'pacote.xml'
    New-Package -Path $pkgC -Guid $guid1 -Name 'Alpha' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $repC = Join-Path $c.Root 'report.json'
    $rC = Invoke-Sync -Pkg $pkgC -Corpus $c.Corpus -ReportPath $repC
    if ($rC.ExitCode -ne 0) { throw "C: FullSnapshot with no renames should exit 0; got $($rC.ExitCode). Output: $($rC.Output)" }
    $repCObj = Get-Content -LiteralPath $repC -Raw | ConvertFrom-Json
    if ($repCObj.Summary.RenamedByGuid -ne 0) { throw "C: RenamedByGuid should be 0; got $($repCObj.Summary.RenamedByGuid)" }
    if ($repCObj.Summary.RenameResidualsDetected -ne 0) { throw "C: RenameResidualsDetected should be 0; got $($repCObj.Summary.RenameResidualsDetected)" }

    # --- D: orphan from a previous materialization (new name already exists with the same GUID) ---
    $d = New-CaseDir -Name 'orphan'
    New-AttrFile -Path (Join-Path $d.AttrDir 'Old.xml') -Guid $guid1 -Name 'Old' -LastUpdate '2020-01-01T00:00:00.0000000Z' -Description 'G1 renamed to New'
    New-AttrFile -Path (Join-Path $d.AttrDir 'New.xml') -Guid $guid1 -Name 'New' -LastUpdate '2026-01-01T00:00:00.0000000Z' -Description 'G1 already materialized under the new name'
    $pkgD = Join-Path $d.Root 'pacote.xml'
    New-Package -Path $pkgD -Guid $guid1 -Name 'New' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $repD = Join-Path $d.Root 'report.json'
    $rD = Invoke-Sync -Pkg $pkgD -Corpus $d.Corpus -ReportPath $repD
    if ($rD.ExitCode -ne 0) { throw "D: orphan with the same GUID should exit 0; got $($rD.ExitCode). Output: $($rD.Output)" }
    if (Test-Path -LiteralPath (Join-Path $d.AttrDir 'Old.xml')) { throw "D: the old file should have been removed as an orphan" }
    if (-not (Test-Path -LiteralPath (Join-Path $d.AttrDir 'New.xml'))) { throw "D: the new file should be preserved" }
    $repDObj = Get-Content -LiteralPath $repD -Raw | ConvertFrom-Json
    if ($repDObj.Summary.RenamedByGuid -ne 1) { throw "D: RenamedByGuid should count the removed orphan; got $($repDObj.Summary.RenamedByGuid)" }
    # Coverage of the 'orphan-removed' Action in the structured item (not just the counter).
    $dObj = Assert-StdoutIsPureJson -Case 'D' -Result $rD
    if (@($dObj.RenamedByGuidItems).Count -ne 1) { throw "D: RenamedByGuidItems should have 1 item; got $(@($dObj.RenamedByGuidItems).Count)" }
    if ($dObj.RenamedByGuidItems[0].Action -ne 'orphan-removed') { throw "D: Action should be 'orphan-removed'; got '$($dObj.RenamedByGuidItems[0].Action)'" }

    # --- E: GUID collision (new name already belongs to another object) ---
    $e = New-CaseDir -Name 'collision'
    New-AttrFile -Path (Join-Path $e.AttrDir 'Old.xml') -Guid $guid1 -Name 'Old' -LastUpdate '2020-01-01T00:00:00.0000000Z' -Description 'G1 renamed to New'
    New-AttrFile -Path (Join-Path $e.AttrDir 'New.xml') -Guid $guid2 -Name 'New' -LastUpdate '2020-01-01T00:00:00.0000000Z' -Description 'unrelated legitimate G2'
    $pkgE = Join-Path $e.Root 'pacote.xml'
    New-Package -Path $pkgE -Guid $guid1 -Name 'New' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $rE = Invoke-Sync -Pkg $pkgE -Corpus $e.Corpus
    if ($rE.ExitCode -eq 0) { throw "E: GUID collision should fail (fail-closed), not exit 0" }
    if ($rE.Output -notmatch 'Name collision in the corpus') { throw "E: should report a name collision; output: $($rE.Output)" }
    if (-not (Test-Path -LiteralPath (Join-Path $e.AttrDir 'Old.xml'))) { throw "E: the old file should have been preserved" }
    $newGuidE = (Select-String -LiteralPath (Join-Path $e.AttrDir 'New.xml') -Pattern 'guid="([0-9a-f-]+)"').Matches[0].Groups[1].Value
    if ($newGuidE -ne $guid2) { throw "E: New.xml should preserve G2's GUID ($guid2); got $newGuidE (object destroyed!)" }

    # --- F: case-only rename ---
    $f = New-CaseDir -Name 'caseonly'
    New-AttrFile -Path (Join-Path $f.AttrDir 'Alpha.xml') -Guid $guid1 -Name 'Alpha' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $pkgF = Join-Path $f.Root 'pacote.xml'
    New-Package -Path $pkgF -Guid $guid1 -Name 'alpha' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $repF = Join-Path $f.Root 'report.json'
    $rF = Invoke-Sync -Pkg $pkgF -Corpus $f.Corpus -ReportPath $repF
    if ($rF.ExitCode -ne 0) { throw "F: case-only rename should exit 0; got $($rF.ExitCode). Output: $($rF.Output)" }
    $namesF = @(Get-ChildItem -LiteralPath $f.AttrDir -Filter *.xml -File | ForEach-Object { $_.Name })
    if ($namesF.Count -ne 1) { throw "F: exactly one file should remain; found $($namesF.Count): $($namesF -join ', ')" }
    if ($namesF[0] -cne 'alpha.xml') { throw "F: the filename should have the new case 'alpha.xml'; got '$($namesF[0])'" }
    $repFObj = Get-Content -LiteralPath $repF -Raw | ConvertFrom-Json
    if ($repFObj.Summary.RenamedByGuid -ne 1) { throw "F: RenamedByGuid should be 1; got $($repFObj.Summary.RenamedByGuid)" }

    # --- G: creation + -ExpectedItems (nominal lists and flattened Expected*Names) ---
    $g = New-CaseDir -Name 'expected'
    $pkgG = Join-Path $g.Root 'pacote.xml'
    New-Package -Path $pkgG -Guid $guid1 -Name 'Gamma' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $repG = Join-Path $g.Root 'report.json'
    $rG = Invoke-Sync -Pkg $pkgG -Corpus $g.Corpus -ReportPath $repG -ExpectedItems @('Attribute:Gamma', 'Attribute:Delta')
    if ($rG.ExitCode -ne 0) { throw "G: creation should exit 0; got $($rG.ExitCode). Output: $($rG.Output)" }
    $gObj = Assert-StdoutIsPureJson -Case 'G' -Result $rG
    # Invariant len(*Names) == counter.
    if (@($gObj.CreatedNames).Count -ne $gObj.Created) { throw "G: len(CreatedNames) ($(@($gObj.CreatedNames).Count)) != Created ($($gObj.Created))" }
    if ($gObj.CreatedNames -notcontains 'Attribute:Gamma') { throw "G: CreatedNames should contain 'Attribute:Gamma'; got [$($gObj.CreatedNames -join ', ')]" }
    # Empty lists serialize as [] (array), not null nor a scalar.
    if ($null -eq $gObj.UpdatedNames -or @($gObj.UpdatedNames).Count -ne 0) { throw "G: UpdatedNames should be an empty [] (not null)" }
    # Flattened Expected*Names: the source of the handoff's three parts.
    if ($gObj.ExpectedReturnedNames -notcontains 'Attribute:Gamma') { throw "G: ExpectedReturnedNames should contain 'Attribute:Gamma'; got [$($gObj.ExpectedReturnedNames -join ', ')]" }
    if ($gObj.ExpectedMissingNames -notcontains 'Attribute:Delta') { throw "G: ExpectedMissingNames should contain 'Attribute:Delta'; got [$($gObj.ExpectedMissingNames -join ', ')]" }
    # Cross-check against the $report on disk: the same lists exist under Summary.
    $repGObj = Get-Content -LiteralPath $repG -Raw | ConvertFrom-Json
    if ($repGObj.Summary.CreatedNames -notcontains 'Attribute:Gamma') { throw "G: report.Summary.CreatedNames should contain 'Attribute:Gamma'" }

    # --- H: delta rename (no -FullSnapshot) ---
    $h = New-CaseDir -Name 'delta'
    New-AttrFile -Path (Join-Path $h.AttrDir 'OldDeltaName.xml') -Guid $guid1 -Name 'OldDeltaName' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    New-AttrFile -Path (Join-Path $h.AttrDir 'Untouched.xml') -Guid $guid2 -Name 'Untouched' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $pkgH = Join-Path $h.Root 'pacote.xml'
    New-Package -Path $pkgH -Guid $guid1 -Name 'NewDeltaName' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $rH = Invoke-Sync -Pkg $pkgH -Corpus $h.Corpus -Delta
    if ($rH.ExitCode -ne 0) { throw "H: delta rename should exit 0; got $($rH.ExitCode). Output: $($rH.Output)" }
    $hObj = Assert-StdoutIsPureJson -Case 'H' -Result $rH
    if ($hObj.FullSnapshot -ne $false) { throw "H: the run must be a delta (FullSnapshot false)" }
    if (-not (Test-Path -LiteralPath (Join-Path $h.AttrDir 'NewDeltaName.xml'))) { throw "H: the new file should exist" }
    if (Test-Path -LiteralPath (Join-Path $h.AttrDir 'OldDeltaName.xml')) { throw "H: the old file should have been renamed" }
    if (-not (Test-Path -LiteralPath (Join-Path $h.AttrDir 'Untouched.xml'))) { throw "H: a delta must preserve files of objects it does not carry" }
    if ($hObj.RenamedByGuid -ne 1) { throw "H: RenamedByGuid should be 1; got $($hObj.RenamedByGuid) (Created $($hObj.Created))" }
    if ($hObj.Created -ne 0) { throw "H: Created should be 0 for a rename; got $($hObj.Created)" }
    if (@($hObj.RenamedByGuidItems).Count -ne 1 -or $hObj.RenamedByGuidItems[0].OldName -ne 'OldDeltaName' -or $hObj.RenamedByGuidItems[0].NewName -ne 'NewDeltaName') { throw "H: RenamedByGuidItems should expose OldDeltaName->NewDeltaName" }

    # --- I: delta with an ambiguous GUID (two corpus files share the item's GUID) ---
    $i = New-CaseDir -Name 'delta-ambiguous'
    $oldAPath = Join-Path $i.AttrDir 'AmbiguousOldA.xml'
    $oldBPath = Join-Path $i.AttrDir 'AmbiguousOldB.xml'
    New-AttrFile -Path $oldAPath -Guid $guid1 -Name 'AmbiguousOldA' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    New-AttrFile -Path $oldBPath -Guid $guid1 -Name 'AmbiguousOldB' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $oldABytes = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldAPath))
    $oldBBytes = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldBPath))
    $metaI = Join-Path $i.Root 'kb-source-metadata.md'
    New-ExistingMetadata -Path $metaI
    $metaIBefore = Get-Content -LiteralPath $metaI -Raw
    $pkgI = Join-Path $i.Root 'pacote.xml'
    New-Package -Path $pkgI -Guid $guid1 -Name 'AmbiguousNew' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $rI = Invoke-Sync -Pkg $pkgI -Corpus $i.Corpus -Delta -KbMetadataPath $metaI
    if ($rI.ExitCode -ne 0) { throw "I: an ambiguous delta rename must not abort; expected exit 0, got $($rI.ExitCode). Output: $($rI.Output)" }
    $iObj = Assert-StdoutIsPureJson -Case 'I' -Result $rI
    if (-not (Test-Path -LiteralPath (Join-Path $i.AttrDir 'AmbiguousNew.xml'))) { throw "I: the item should be created under its new name" }
    if ($iObj.Created -ne 1 -or $iObj.RenamedByGuid -ne 0) { throw "I: expected Created 1 and RenamedByGuid 0; got Created $($iObj.Created), RenamedByGuid $($iObj.RenamedByGuid)" }
    if (-not (Test-Path -LiteralPath $oldAPath) -or -not (Test-Path -LiteralPath $oldBPath)) { throw "I: both same-GUID files must stay" }
    if ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldAPath)) -ne $oldABytes) { throw "I: AmbiguousOldA.xml must be untouched" }
    if ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldBPath)) -ne $oldBBytes) { throw "I: AmbiguousOldB.xml must be untouched" }
    $iWarning = @($iObj.Warnings | Where-Object { $_ -match [regex]::Escape($guid1) })
    if ($iWarning.Count -eq 0) { throw "I: a warning should name the GUID $guid1; warnings: $(@($iObj.Warnings) -join ' | ')" }
    if ($iWarning[0] -notmatch 'AmbiguousOldA\.xml' -or $iWarning[0] -notmatch 'AmbiguousOldB\.xml') { throw "I: the warning should name both conflicting files; got: $($iWarning[0])" }
    $metaIAfter = Get-Content -LiteralPath $metaI -Raw
    if ($metaIAfter -eq $metaIBefore -or $metaIAfter -notmatch 'pacote\.xml') { throw "I: kb-source-metadata.md should be refreshed with the applied package" }

    # --- J: delta rename under -VerifyOnly (classify only, write nothing) ---
    $j = New-CaseDir -Name 'delta-verify'
    $oldJPath = Join-Path $j.AttrDir 'OldVerifyName.xml'
    New-AttrFile -Path $oldJPath -Guid $guid1 -Name 'OldVerifyName' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $oldJBytes = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldJPath))
    $metaJ = Join-Path $j.Root 'kb-source-metadata.md'
    New-ExistingMetadata -Path $metaJ
    $metaJBytes = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($metaJ))
    $pkgJ = Join-Path $j.Root 'pacote.xml'
    New-Package -Path $pkgJ -Guid $guid1 -Name 'NewVerifyName' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $rJ = Invoke-Sync -Pkg $pkgJ -Corpus $j.Corpus -Delta -VerifyOnly -KbMetadataPath $metaJ
    $jObj = Assert-StdoutIsPureJson -Case 'J' -Result $rJ
    if ($jObj.FullSnapshot -ne $false -or $jObj.VerifyOnly -ne $true) { throw "J: the run must be a delta under -VerifyOnly" }
    if ($jObj.RenameResidualsDetected -ne 1) { throw "J: RenameResidualsDetected should be 1; got $($jObj.RenameResidualsDetected)" }
    if ($jObj.RenamedByGuid -ne 0 -or $jObj.Created -ne 0) { throw "J: nothing should be renamed or created; got RenamedByGuid $($jObj.RenamedByGuid), Created $($jObj.Created)" }
    if (Test-Path -LiteralPath (Join-Path $j.AttrDir 'NewVerifyName.xml')) { throw "J: -VerifyOnly must not create the new file" }
    if (-not (Test-Path -LiteralPath $oldJPath)) { throw "J: -VerifyOnly must not move the old file" }
    if ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($oldJPath)) -ne $oldJBytes) { throw "J: the old file must be untouched" }
    if ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($metaJ)) -ne $metaJBytes) { throw "J: -VerifyOnly must keep kb-source-metadata.md bytes" }

    # --- K: delta with an unreadable XML in the scanned type folder ---
    $k = New-CaseDir -Name 'delta-unreadable'
    $brokenPath = Join-Path $k.AttrDir 'Broken.xml'
    Write-Utf8 -Path $brokenPath -Content 'this is not xml <'
    $oldKPath = Join-Path $k.AttrDir 'OldUnreadableName.xml'
    New-AttrFile -Path $oldKPath -Guid $guid1 -Name 'OldUnreadableName' -LastUpdate '2020-01-01T00:00:00.0000000Z'
    $metaK = Join-Path $k.Root 'kb-source-metadata.md'
    New-ExistingMetadata -Path $metaK
    $metaKBefore = Get-Content -LiteralPath $metaK -Raw
    $pkgK = Join-Path $k.Root 'pacote.xml'
    New-Package -Path $pkgK -Guid $guid1 -Name 'NewUnreadableName' -LastUpdate '2026-01-01T00:00:00.0000000Z'
    $rK = Invoke-Sync -Pkg $pkgK -Corpus $k.Corpus -Delta -KbMetadataPath $metaK
    if ($rK.ExitCode -ne 0) { throw "K: an unreadable corpus file must not abort a delta; expected exit 0, got $($rK.ExitCode). Output: $($rK.Output)" }
    $kObj = Assert-StdoutIsPureJson -Case 'K' -Result $rK
    if (-not (Test-Path -LiteralPath (Join-Path $k.AttrDir 'NewUnreadableName.xml'))) { throw "K: the item should be created under its new name" }
    if (-not (Test-Path -LiteralPath $oldKPath) -or -not (Test-Path -LiteralPath $brokenPath)) { throw "K: the old file and the unreadable file must stay" }
    if ((Get-Content -LiteralPath $brokenPath -Raw) -ne 'this is not xml <') { throw "K: the unreadable file must be untouched" }
    if ($kObj.Created -ne 1 -or $kObj.RenamedByGuid -ne 0) { throw "K: expected Created 1 and RenamedByGuid 0; got Created $($kObj.Created), RenamedByGuid $($kObj.RenamedByGuid)" }
    $kWarning = @($kObj.Warnings | Where-Object { $_ -match [regex]::Escape($guid1) -and $_ -match 'Broken\.xml' })
    if ($kWarning.Count -eq 0) { throw "K: a warning should name the GUID and Broken.xml; warnings: $(@($kObj.Warnings) -join ' | ')" }
    $metaKAfter = Get-Content -LiteralPath $metaK -Raw
    if ($metaKAfter -eq $metaKBefore -or $metaKAfter -notmatch 'pacote\.xml') { throw "K: kb-source-metadata.md should be refreshed with the applied package" }

    Write-Output 'OK: Test-GeneXusXpzSyncGuidRenameSelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
