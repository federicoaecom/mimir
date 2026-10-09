#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/Test-ScriptInventory.ps1.

.DESCRIPTION
    Builds a synthetic temp root with the same three script folders this repository has
    (skills/mimir-lite/scripts/, skills/mimir-delegate/scripts/, tools/) plus a synthetic
    09-script-inventory.md, and proves the gate:
      - clean case (every real file listed exactly once, every listed entry real) -> pass;
      - a real file missing from the inventory -> fail, INVENTORY_MISSING_FILE;
      - an inventory entry with no matching real file -> fail, INVENTORY_STALE_ENTRY;
      - a file listed twice in the same section -> fail, INVENTORY_DUPLICATE_ENTRY;
      - a subfolder entry (sample-subfolder/tool.py shape) is matched by its
        full relative path, not just its basename.
    Does not touch the real repository tree.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path (Join-Path $repoRoot 'tools') 'Test-ScriptInventory.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-script-inventory-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))

. (Join-Path (Join-Path $repoRoot 'skills/mimir-lite/scripts') 'Utf8NoBomEncodingSupport.ps1')
$utf8NoBom = Get-Utf8NoBomEncoding

function New-FixtureTree {
    param([string]$Root)

    [void](New-Item -ItemType Directory -Path (Join-Path $Root 'skills/mimir-lite/scripts/sample-subfolder') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $Root 'skills/mimir-lite/scripts/__pycache__') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $Root 'skills/mimir-delegate/scripts') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $Root 'tools') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $Root 'skills/mimir-lite/references') -Force)

    foreach ($relative in @(
        'skills/mimir-lite/scripts/Foo.ps1',
        'skills/mimir-lite/scripts/Bar.ps1',
        'skills/mimir-lite/scripts/sample-subfolder/tool.py',
        'skills/mimir-lite/scripts/__pycache__/Foo.cpython-312.pyc',
        'skills/mimir-delegate/scripts/Baz.ps1',
        'tools/Qux.ps1'
    )) {
        [System.IO.File]::WriteAllText((Join-Path $Root $relative), '# fixture', $utf8NoBom)
    }
}

function Write-FixtureInventory {
    param(
        [string]$Root,
        [string]$Content
    )
    [System.IO.File]::WriteAllText((Join-Path $Root 'skills/mimir-lite/references/09-script-inventory.md'), $Content, $utf8NoBom)
}

function Invoke-Gate {
    param([string]$Root)
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $Root -AsJson 2>&1
    $script:lastExit = $LASTEXITCODE
    return (($output | Out-String).Trim() | ConvertFrom-Json)
}

$cleanInventory = @'
# 09 - Script inventory

## `skills/mimir-lite/scripts/` (3 files)

| File | Kind | Purpose | Owner doc | Tests |
|---|---|---|---|---|
| `Foo.ps1` | engine | fixture. | none | none |
| `Bar.ps1` | engine | fixture. | none | none |
| `sample-subfolder/tool.py` | engine | fixture. | none | none |

## `skills/mimir-delegate/scripts/` (1 files)

| File | Kind | Purpose | Owner doc | Tests |
|---|---|---|---|---|
| `Baz.ps1` | engine | fixture. | none | none |

## `tools/` (1 files)

| File | Kind | Purpose | Owner doc | Tests |
|---|---|---|---|---|
| `Qux.ps1` | engine | fixture. | none | none |
'@

try {
    # Scenario 1: clean fixture -> pass, zero findings.
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-FixtureTree -Root $tempRoot
    Write-FixtureInventory -Root $tempRoot -Content $cleanInventory
    $r1 = Invoke-Gate -Root $tempRoot
    if ($script:lastExit -ne 0) { throw "scenario 1 (clean): exit should be 0; got $($script:lastExit)" }
    if ($r1.status -ne 'pass') { throw "scenario 1 (clean): status should be 'pass'; got '$($r1.status)'. Findings: $((@($r1.findings | ForEach-Object { $_.code }) -join ', '))" }

    # Scenario 2: a real file missing from the inventory -> fail, INVENTORY_MISSING_FILE.
    $missingInventory = (($cleanInventory -split "`r?`n") | Where-Object { $_ -notmatch '^\|\s*`Bar\.ps1`' }) -join "`n"
    Write-FixtureInventory -Root $tempRoot -Content $missingInventory
    $r2 = Invoke-Gate -Root $tempRoot
    if ($script:lastExit -eq 0) { throw "scenario 2 (missing file): exit should be != 0" }
    if ($r2.status -ne 'fail') { throw "scenario 2 (missing file): status should be 'fail'; got '$($r2.status)'" }
    $missing = @($r2.findings | Where-Object { $_.code -eq 'INVENTORY_MISSING_FILE' -and $_.path -eq 'skills/mimir-lite/scripts/Bar.ps1' })
    if ($missing.Count -ne 1) { throw "scenario 2: expected 1 INVENTORY_MISSING_FILE for Bar.ps1; got $($missing.Count). Findings: $((@($r2.findings | ForEach-Object { $_.code + ':' + $_.path }) -join ', '))" }

    # Scenario 3: an inventory entry with no matching real file -> fail, INVENTORY_STALE_ENTRY.
    Write-FixtureInventory -Root $tempRoot -Content $cleanInventory
    $staleInventory = $cleanInventory -replace '(\| `Bar\.ps1` \| engine \| fixture\. \| none \| none \|)', "`$1`n| ``Ghost.ps1`` | engine | fixture. | none | none |"
    Write-FixtureInventory -Root $tempRoot -Content $staleInventory
    $r3 = Invoke-Gate -Root $tempRoot
    if ($script:lastExit -eq 0) { throw "scenario 3 (stale entry): exit should be != 0" }
    if ($r3.status -ne 'fail') { throw "scenario 3 (stale entry): status should be 'fail'; got '$($r3.status)'" }
    $stale = @($r3.findings | Where-Object { $_.code -eq 'INVENTORY_STALE_ENTRY' -and $_.path -eq 'skills/mimir-lite/scripts/Ghost.ps1' })
    if ($stale.Count -ne 1) { throw "scenario 3: expected 1 INVENTORY_STALE_ENTRY for Ghost.ps1; got $($stale.Count)" }

    # Scenario 4: a file listed twice in the same section -> fail, INVENTORY_DUPLICATE_ENTRY.
    $duplicateInventory = $cleanInventory -replace '(\| `Bar\.ps1` \| engine \| fixture\. \| none \| none \|)', "`$1`n| ``Bar.ps1`` | engine | fixture again. | none | none |"
    Write-FixtureInventory -Root $tempRoot -Content $duplicateInventory
    $r4 = Invoke-Gate -Root $tempRoot
    if ($script:lastExit -eq 0) { throw "scenario 4 (duplicate entry): exit should be != 0" }
    if ($r4.status -ne 'fail') { throw "scenario 4 (duplicate entry): status should be 'fail'; got '$($r4.status)'" }
    $duplicate = @($r4.findings | Where-Object { $_.code -eq 'INVENTORY_DUPLICATE_ENTRY' -and $_.path -eq 'skills/mimir-lite/scripts/Bar.ps1' })
    if ($duplicate.Count -ne 1) { throw "scenario 4: expected 1 INVENTORY_DUPLICATE_ENTRY for Bar.ps1; got $($duplicate.Count)" }

    Write-Output 'OK: Test-ScriptInventorySelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
