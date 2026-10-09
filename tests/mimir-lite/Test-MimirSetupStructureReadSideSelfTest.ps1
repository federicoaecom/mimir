#requires -Version 7.4
<#
.SYNOPSIS
    Ensures the sanitized structure gate accepts a complete read-side KB workspace.
.DESCRIPTION
    Uses a temporary synthetic workspace; no real GeneXus KB or external engine.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$template = Join-Path $repoRoot 'skills/mimir-lite/workflows/setup/examples/Test-KbStructure.example.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-structure-read-{0}' -f [guid]::NewGuid().ToString('N'))
$utf8 = [System.Text.UTF8Encoding]::new($false)
try {
    foreach ($folder in @('scripts', 'Temp', 'IdeXpzExports', 'KbObjectsXml', 'KbIntelligence')) {
        [void](New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force)
    }
    foreach ($file in @('AGENTS.md', 'README.md', 'kb-source-metadata.md', 'KbIntelligence/kb-intelligence.sqlite')) {
        [System.IO.File]::WriteAllText((Join-Path $root $file), 'synthetic fixture', $utf8)
    }
    foreach ($name in @(
        'Update-KbFromXpz.ps1', 'Test-KbFullSnapshot.ps1', 'Test-KbSetupFreshness.ps1',
        'Test-KbPowerShellRuntime.ps1', 'Test-KbObjectsXmlNaming.ps1',
        'Query-KbIntelligence.ps1', 'Rebuild-KbIntelligenceIndex.ps1',
        'Test-KbIndexGate.ps1', 'Get-KbMetadata.ps1', 'Test-KbMetadataWrapper.ps1',
        'Test-KbSetupAudit.ps1'
    )) {
        [System.IO.File]::WriteAllText((Join-Path $root "scripts/$name"), "#requires -Version 7.4`n", $utf8)
    }
    # A leftover out-of-scope packaging wrapper must not block the read-side gate.
    [System.IO.File]::WriteAllText((Join-Path $root 'scripts/New-KbImportPackage.ps1'), 'function Broken {', $utf8)
    Copy-Item -LiteralPath $template -Destination (Join-Path $root 'scripts/Test-KbStructure.ps1')
    $gate = Join-Path $root 'scripts/Test-KbStructure.ps1'
    $output = & pwsh -NoProfile -NonInteractive -File $gate -KbRoot $root 2>&1
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -or @($output | Where-Object { "$_" -eq 'STRUCTURE_OK' }).Count -ne 1) {
        throw "Read-side synthetic workspace must pass the structure gate without generated/import folders or a valid packaging wrapper; exit=$exit, output=$($output -join '; ')"
    }
    Write-Output 'MIMIR_SETUP_STRUCTURE_READ_SIDE_SELFTEST_OK'
} finally {
    if (Test-Path -LiteralPath $root -PathType Container) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
