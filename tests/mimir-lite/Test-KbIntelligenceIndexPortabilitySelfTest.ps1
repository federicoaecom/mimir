#requires -Version 7.4
<#
.SYNOPSIS
    Self-contained test: a KB intelligence index keeps working after it is moved
    together with its corpus (same relative layout), on any OS.

.DESCRIPTION
    Builds the index from a copy of the synthetic sample-kb fixture (tests/fixtures/sample-kb/,
    no real KB data) into a temporary workspace (KbObjectsXml/ plus KbIntelligence/), then checks:
    - the stored metadata.source_root is relative to the index folder, with '/' separators;
    - after moving the whole workspace to another folder (the original is gone), the queries that
      read indexed XML from disk through source_root (attribute-info, transaction-attributes,
      transaction-writable-attributes) still work, and index-metadata reports the resolved root,
      in JSON and in the text output line (resolved_source_root: <path>);
    - when only the .sqlite file is copied (no corpus beside it), the file-backed queries fail with
      a message that names the resolved_source_root they looked under;
    - an index without a recorded source_root prints "resolved_source_root: (not recorded)" in
      the text output;
    - an index built with a relative -SourceRoot and -OutputPath stores the same relative
      source_root and works;
    - an index whose source_root holds an absolute path (older indexes, or no relative path,
      such as another drive on Windows) is still read as is;
    - when no relative path exists (os.path.relpath raises ValueError), the builder stores the
      absolute path instead of failing;
    - an index whose schema_version is rewritten to "4" (the stored source_root stays relative)
      is refused by the query engine with the schema-version mismatch message;
    - when the index folder is a directory link (Windows: junction) to a folder that does not
      share the corpus parent, the index works whether it is built or opened through the link or
      through the real path (skipped with a message when the link cannot be created).
    Failures are collected and reported together.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Python 3.8+ resolved the same way the KbIntelligence wrappers do it
# (python3, then python, then py -3). The helper enables strict mode.
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')
$pythonInterpreter = Get-GeneXusPythonExecutable
if ($null -eq $pythonInterpreter) {
    throw (Get-GeneXusPythonNotFoundMessage)
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$sampleKbRoot = Join-Path $repoRoot 'tests/fixtures/sample-kb'
$buildWrapper = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$buildEngine = Join-Path $scriptDir 'Build-KbIntelligenceIndex.py'
$queryWrapper = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'
foreach ($required in @($sampleKbRoot, $buildWrapper, $buildEngine, $queryWrapper)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path not found: $required"
    }
}

$pwshPath = (Get-Process -Id $PID).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-IndexQuery {
    param(
        [Parameter(Mandatory = $true)][string]$IndexPath,
        [Parameter(Mandatory = $true)][string[]]$QueryArguments,
        [ValidateSet('json', 'text')][string]$Format = 'json'
    )
    # The wrapper ends with `exit`, so it runs in a child pwsh process.
    $output = & $pwshPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $queryWrapper `
        -IndexPath $IndexPath @QueryArguments -Format $Format 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Text     = ($output | ForEach-Object { "$_" }) -join "`n"
    }
}

function Invoke-PythonSnippet {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [string[]]$Arguments = @()
    )
    $output = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) -c $Code @Arguments 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Text     = ($output | ForEach-Object { "$_" }) -join "`n"
    }
}

# The real path of a folder (links and, on Windows, 8.3 short names resolved), computed by
# Python the same way the query engine resolves the index folder.
function Get-RealPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $real = Invoke-PythonSnippet -Code 'import os, sys; print(os.path.realpath(sys.argv[1]))' -Arguments @($Path)
    if ($real.ExitCode -ne 0) {
        throw "Could not resolve the real path of '$Path': $($real.Text)"
    }
    return $real.Text.Trim()
}

# Path equality after normalizing separators; case-insensitive on Windows only.
function Test-SamePath {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    if (-not $Actual) {
        return $false
    }
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $normalizedActual = [System.IO.Path]::GetFullPath($Actual).TrimEnd($separators)
    $normalizedExpected = [System.IO.Path]::GetFullPath($Expected).TrimEnd($separators)
    return [string]::Equals($normalizedActual, $normalizedExpected, $comparison)
}

function Test-MovedIndexQueries {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$IndexPath
    )

    $attribute = Invoke-IndexQuery -IndexPath $IndexPath -QueryArguments @('-Query', 'attribute-info', '-ObjectName', 'InvoiceTotal')
    if ($attribute.ExitCode -ne 0) {
        $failures.Add("${Label}: attribute-info(InvoiceTotal) exit $($attribute.ExitCode): $($attribute.Text)")
    }
    else {
        $payload = $attribute.Text | ConvertFrom-Json
        if (-not $payload.found -or -not $payload.isFormula) {
            $failures.Add("${Label}: attribute-info(InvoiceTotal) should be found and be a formula; got: $($attribute.Text)")
        }
    }

    $transaction = Invoke-IndexQuery -IndexPath $IndexPath -QueryArguments @('-Query', 'transaction-attributes', '-ObjectName', 'Invoice')
    if ($transaction.ExitCode -ne 0) {
        $failures.Add("${Label}: transaction-attributes(Invoice) exit $($transaction.ExitCode): $($transaction.Text)")
    }
    else {
        $payload = $transaction.Text | ConvertFrom-Json
        if (-not $payload.found) {
            $failures.Add("${Label}: transaction-attributes(Invoice) should be found; got: $($transaction.Text)")
        }
    }

    $writable = Invoke-IndexQuery -IndexPath $IndexPath -QueryArguments @('-Query', 'transaction-writable-attributes', '-ObjectName', 'Invoice')
    if ($writable.ExitCode -ne 0) {
        $failures.Add("${Label}: transaction-writable-attributes(Invoice) exit $($writable.ExitCode): $($writable.Text)")
    }
    else {
        $payload = $writable.Text | ConvertFrom-Json
        $formulaRows = @($payload.results | Where-Object { $_.attribute -eq 'InvoiceTotal' -and $_.isFormula -eq $true })
        if (-not $payload.found -or $formulaRows.Count -ne 1) {
            $failures.Add("${Label}: transaction-writable-attributes(Invoice) should report InvoiceTotal as a formula read from its XML; got: $($writable.Text)")
        }
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-portability-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $originalWorkspace = Join-Path $tempRoot 'original/workspace'
    $originalCorpus = Join-Path $originalWorkspace 'KbObjectsXml'
    $originalIndex = Join-Path $originalWorkspace 'KbIntelligence/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path $originalWorkspace -Force)
    Copy-Item -LiteralPath $sampleKbRoot -Destination $originalCorpus -Recurse

    # --- Build the index into the original workspace ---
    $buildOutput = & $buildWrapper -SourceRoot $originalCorpus -OutputPath $originalIndex 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $originalIndex -PathType Leaf)) {
        throw "Build-KbIntelligenceIndex failed; exit $LASTEXITCODE. Output: $(($buildOutput | Select-Object -Last 5) -join ' | ')"
    }

    # --- The stored source_root is relative to the index folder, with '/' separators ---
    $metadata = Invoke-IndexQuery -IndexPath $originalIndex -QueryArguments @('-Query', 'index-metadata')
    if ($metadata.ExitCode -ne 0) {
        throw "index-metadata failed; exit $($metadata.ExitCode): $($metadata.Text)"
    }
    $storedSourceRoot = [string](($metadata.Text | ConvertFrom-Json).metadata.source_root)
    if ($storedSourceRoot -cne '../KbObjectsXml') {
        $failures.Add("metadata.source_root should be '../KbObjectsXml' (relative to the index folder, '/' separators); got '$storedSourceRoot'")
    }

    # --- Move the whole workspace (corpus + index, same layout) elsewhere; the original is gone ---
    $movedParent = Join-Path $tempRoot 'moved/elsewhere'
    $movedWorkspace = Join-Path $movedParent 'workspace-copy'
    $movedCorpus = Join-Path $movedWorkspace 'KbObjectsXml'
    $movedIndex = Join-Path $movedWorkspace 'KbIntelligence/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path $movedParent -Force)
    Move-Item -LiteralPath $originalWorkspace -Destination $movedWorkspace
    Remove-Item -LiteralPath (Join-Path $tempRoot 'original') -Recurse -Force
    if (Test-Path -LiteralPath $originalWorkspace) {
        throw "The original workspace should be gone after the move: $originalWorkspace"
    }

    Test-MovedIndexQueries -Label 'moved index (relative source_root)' -IndexPath $movedIndex

    # --- index-metadata reports the root resolved against the moved index folder ---
    $movedMetadata = Invoke-IndexQuery -IndexPath $movedIndex -QueryArguments @('-Query', 'index-metadata')
    if ($movedMetadata.ExitCode -ne 0) {
        $failures.Add("moved index-metadata exit $($movedMetadata.ExitCode): $($movedMetadata.Text)")
    }
    else {
        $resolvedProperty = ($movedMetadata.Text | ConvertFrom-Json).PSObject.Properties['resolved_source_root']
        $resolvedSourceRoot = if ($null -ne $resolvedProperty) { [string]$resolvedProperty.Value } else { '' }
        # The query engine resolves the index folder to its real path (temp folders can sit behind
        # a link, such as macOS /var -> /private/var, or use 8.3 short names on Windows).
        $expectedResolved = Get-RealPath -Path $movedCorpus
        if (-not (Test-SamePath -Actual $resolvedSourceRoot -Expected $expectedResolved)) {
            $failures.Add("index-metadata resolved_source_root should be the moved corpus '$expectedResolved'; got '$resolvedSourceRoot'")
        }
    }

    # --- The text output prints the same resolved_source_root line ---
    $movedMetadataText = Invoke-IndexQuery -IndexPath $movedIndex -QueryArguments @('-Query', 'index-metadata') -Format text
    $textLine = @($movedMetadataText.Text -split "`n" | Where-Object { $_ -match '^resolved_source_root: ' })
    $textResolved = if ($textLine.Count -eq 1) { $textLine[0].Substring('resolved_source_root: '.Length).Trim() } else { '' }
    if ($movedMetadataText.ExitCode -ne 0 -or -not (Test-SamePath -Actual $textResolved -Expected (Get-RealPath -Path $movedCorpus))) {
        $failures.Add("index-metadata text output should print 'resolved_source_root: <moved corpus>'; exit $($movedMetadataText.ExitCode): $($movedMetadataText.Text)")
    }

    # --- Only the .sqlite file is copied, without its corpus: the failure names the folder the
    #     queries looked under (resolved_source_root) ---
    $sqliteOnlyFolder = Join-Path $tempRoot 'sqlite-only/KbIntelligence'
    $sqliteOnlyIndex = Join-Path $sqliteOnlyFolder 'kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path $sqliteOnlyFolder -Force)
    Copy-Item -LiteralPath $movedIndex -Destination $sqliteOnlyIndex
    $sqliteOnly = Invoke-IndexQuery -IndexPath $sqliteOnlyIndex -QueryArguments @('-Query', 'attribute-info', '-ObjectName', 'InvoiceTotal')
    $expectedMissingRoot = Join-Path (Get-RealPath -Path (Join-Path $tempRoot 'sqlite-only')) 'KbObjectsXml'
    $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $namesMissingRoot = $sqliteOnly.Text.IndexOf("resolved_source_root: $expectedMissingRoot", $pathComparison) -ge 0
    if ($sqliteOnly.ExitCode -eq 0 -or $sqliteOnly.Text -notmatch 'Indexed XML file not found' -or -not $namesMissingRoot -or $sqliteOnly.Text -notmatch 'together with the index') {
        $failures.Add("a .sqlite copied without its corpus should fail naming 'resolved_source_root: $expectedMissingRoot' and saying the corpus moves together with the index; exit $($sqliteOnly.ExitCode): $($sqliteOnly.Text)")
    }

    # --- An index without a recorded source_root prints "(not recorded)" in the text output ---
    $noSourceRootIndex = Join-Path $tempRoot 'no-source-root/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $noSourceRootIndex) -Force)
    Copy-Item -LiteralPath $movedIndex -Destination $noSourceRootIndex
    $dropSourceRoot = Invoke-PythonSnippet -Code @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("DELETE FROM metadata WHERE key = 'source_root'")
conn.commit()
conn.close()
'@ -Arguments @($noSourceRootIndex)
    if ($dropSourceRoot.ExitCode -ne 0) {
        throw "Could not remove source_root from the index copy: $($dropSourceRoot.Text)"
    }
    $noSourceRootText = Invoke-IndexQuery -IndexPath $noSourceRootIndex -QueryArguments @('-Query', 'index-metadata') -Format text
    if ($noSourceRootText.ExitCode -ne 0 -or $noSourceRootText.Text -notmatch '(?m)^resolved_source_root: \(not recorded\)\s*$') {
        $failures.Add("an index without source_root should print 'resolved_source_root: (not recorded)'; exit $($noSourceRootText.ExitCode): $($noSourceRootText.Text)")
    }

    # --- Built with a relative -SourceRoot and -OutputPath (resolved against the working
    #     directory): the same relative source_root is stored and the index works ---
    $relativeWorkspace = Join-Path $tempRoot 'relative/workspace'
    $relativeIndex = Join-Path $relativeWorkspace 'KbIntelligence/kb-intelligence.sqlite'
    [void](New-Item -ItemType Directory -Path $relativeWorkspace -Force)
    Copy-Item -LiteralPath $sampleKbRoot -Destination (Join-Path $relativeWorkspace 'KbObjectsXml') -Recurse
    # A child pwsh started in the workspace, so the engine runs with the workspace as its working directory.
    $relativeBuild = & $pwshPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -WorkingDirectory $relativeWorkspace `
        -File $buildWrapper -SourceRoot 'KbObjectsXml' -OutputPath 'KbIntelligence/kb-intelligence.sqlite' 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $relativeIndex -PathType Leaf)) {
        $failures.Add("build with a relative -SourceRoot and -OutputPath failed; exit $LASTEXITCODE. Output: $(($relativeBuild | Select-Object -Last 5) -join ' | ')")
    }
    else {
        $relativeMetadata = Invoke-IndexQuery -IndexPath $relativeIndex -QueryArguments @('-Query', 'index-metadata')
        $relativeStored = if ($relativeMetadata.ExitCode -eq 0) { [string](($relativeMetadata.Text | ConvertFrom-Json).metadata.source_root) } else { '' }
        if ($relativeStored -cne '../KbObjectsXml') {
            $failures.Add("relative build: metadata.source_root should be '../KbObjectsXml'; got '$relativeStored' (exit $($relativeMetadata.ExitCode))")
        }
        Test-MovedIndexQueries -Label 'relative -SourceRoot/-OutputPath build' -IndexPath $relativeIndex
    }

    # --- An absolute stored source_root (older index, or no relative path) is read as is ---
    $setAbsolute = Invoke-PythonSnippet -Code @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE metadata SET value = ? WHERE key = 'source_root'", (sys.argv[2],))
conn.commit()
conn.close()
'@ -Arguments @($movedIndex, ([System.IO.Path]::GetFullPath($movedCorpus)))
    if ($setAbsolute.ExitCode -ne 0) {
        throw "Could not store an absolute source_root: $($setAbsolute.Text)"
    }
    Test-MovedIndexQueries -Label 'absolute source_root' -IndexPath $movedIndex

    # --- No relative path (os.path.relpath raises ValueError, as across Windows drives):
    #     the builder keeps the absolute path ---
    $fallback = Invoke-PythonSnippet -Code @'
import importlib.util, os, sys
from pathlib import Path
engine = Path(sys.argv[1])
sys.path.insert(0, str(engine.parent))
spec = importlib.util.spec_from_file_location("kb_index_builder_under_test", engine)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
source_root = Path(sys.argv[2]).resolve()
def no_relative_path(*_args, **_kwargs):
    raise ValueError("path is on mount 'X:', start on mount 'Y:'")
os.path.relpath = no_relative_path
stored = module.portable_source_root(source_root, source_root.parent / "KbIntelligence")
if stored != str(source_root):
    raise SystemExit(f"expected the absolute path {source_root}, got {stored!r}")
print(stored)
'@ -Arguments @($buildEngine, $movedCorpus)
    if ($fallback.ExitCode -ne 0) {
        $failures.Add("portable_source_root should store the absolute path when no relative path exists: $($fallback.Text)")
    }

    # --- schema_version rewritten to 4 (the stored source_root stays relative): the query engine
    #     refuses the index with the schema-version mismatch message ---
    $setOldSchema = Invoke-PythonSnippet -Code @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
conn.execute("UPDATE metadata SET value = '4' WHERE key = 'schema_version'")
conn.commit()
conn.close()
'@ -Arguments @($movedIndex)
    if ($setOldSchema.ExitCode -ne 0) {
        throw "Could not store schema_version 4: $($setOldSchema.Text)"
    }
    $oldSchema = Invoke-IndexQuery -IndexPath $movedIndex -QueryArguments @('-Query', 'attribute-info', '-ObjectName', 'InvoiceTotal')
    if ($oldSchema.ExitCode -eq 0 -or $oldSchema.Text -notmatch 'Index schema version mismatch') {
        $failures.Add("a schema_version 4 index should be refused with 'Index schema version mismatch'; exit $($oldSchema.ExitCode): $($oldSchema.Text)")
    }

    # --- The index folder is a directory link (Windows: junction) to a folder that does not share
    #     the corpus parent. Builder and query must both use the real path, so the index works
    #     whether it is built or opened through the link or through the real path. This relies on
    #     the .resolve() calls in Build-KbIntelligenceIndex.py main() (args.source_root.resolve()
    #     and args.output_path.resolve()) and in Query-KbIntelligenceIndex.py
    #     index_file_folder(), which resolves the open index file ---
    $linkCaseRoot = Join-Path $tempRoot 'link-case'
    $linkCorpus = Join-Path $linkCaseRoot 'corpus-home/KbObjectsXml'
    $realIndexDir = Join-Path $linkCaseRoot 'elsewhere/deeper/real-index'
    $linkIndexDir = Join-Path $linkCaseRoot 'corpus-home/KbIntelligence'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $linkCorpus) -Force)
    [void](New-Item -ItemType Directory -Path $realIndexDir -Force)
    Copy-Item -LiteralPath $sampleKbRoot -Destination $linkCorpus -Recurse

    $linkItemType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    $linkCreated = $false
    try {
        [void](New-Item -ItemType $linkItemType -Path $linkIndexDir -Target $realIndexDir -ErrorAction Stop)
        $linkCreated = $true
    }
    catch {
        Write-Output "SKIP: directory link cases ($linkItemType could not be created: $($_.Exception.Message))"
    }

    if ($linkCreated) {
        # Built through the link, opened through the link and through the real path.
        $builtViaLink = Join-Path $linkIndexDir 'built-via-link.sqlite'
        $linkBuild = & $buildWrapper -SourceRoot $linkCorpus -OutputPath $builtViaLink 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("build through the directory link failed; exit $LASTEXITCODE. Output: $(($linkBuild | Select-Object -Last 5) -join ' | ')")
        }
        else {
            Test-MovedIndexQueries -Label 'built via link, opened via link' -IndexPath $builtViaLink
            Test-MovedIndexQueries -Label 'built via link, opened via real path' -IndexPath (Join-Path $realIndexDir 'built-via-link.sqlite')
        }

        # Built through the real path, opened through the link.
        $builtViaReal = Join-Path $realIndexDir 'built-via-real.sqlite'
        $realBuild = & $buildWrapper -SourceRoot $linkCorpus -OutputPath $builtViaReal 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failures.Add("build through the real index path failed; exit $LASTEXITCODE. Output: $(($realBuild | Select-Object -Last 5) -join ' | ')")
        }
        else {
            Test-MovedIndexQueries -Label 'built via real path, opened via link' -IndexPath (Join-Path $linkIndexDir 'built-via-real.sqlite')
        }

        # Remove the link itself (not its target's contents through it) before the cleanup below.
        (Get-Item -LiteralPath $linkIndexDir -Force).Delete()
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceIndexPortabilitySelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}

Write-Output 'OK: Test-KbIntelligenceIndexPortabilitySelfTest.ps1'
exit 0
