#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to check the structure of the KB workspace.

.DESCRIPTION
Checks the presence of required folders, expected scripts,
KbIntelligence\kb-intelligence.sqlite and kb-source-metadata.md. Returns a
report of the presence/absence of each component. Used at initial setup and in
diagnostics before any operation.

The script names checked follow the wrapper naming rule <Verb>-<KbName>Kb<Name>.ps1
(e.g. Test-SampleKbKbIndexGate.ps1). The setup examples list them without the KB
prefix; New-MimirKbWorkspace.ps1 adds it when it generates the wrapper.
The detailed naming audit of the KbObjectsXml directories lives in the
dedicated wrapper `Test-KbObjectsXmlNaming.ps1`.

.PARAMETER KbRoot
Optional path to the root of the KB workspace.
When omitted, uses the parent of the scripts folder of this wrapper.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbStructure.ps1"

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbStructure.ps1" -KbRoot "<WorkspaceRoot>"
#>

param(
    [string]$KbRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $KbRoot) {
    $KbRoot = Split-Path -Parent $PSScriptRoot
}

$results = [System.Collections.Generic.List[pscustomobject]]::new()

function Test-Component {
    param(
        [string]$Label,
        [string]$Path,
        [string]$Type  # 'Container' or 'Leaf'
    )
    $exists = Test-Path -LiteralPath $Path -PathType $Type
    $results.Add([pscustomobject]@{
        Component = $Label
        Status    = if ($exists) { 'OK' } else { 'MISSING' }
        Path      = $Path
    })
}

foreach ($folder in @(
    'scripts',
    'Temp',
    'IdeXpzExports',
    'KbObjectsXml',
    'KbIntelligence'
)) {
    Test-Component -Label "folder\$folder" -Path (Join-Path $KbRoot $folder) -Type Container
}

foreach ($file in @('AGENTS.md', 'README.md', 'kb-source-metadata.md')) {
    Test-Component -Label $file -Path (Join-Path $KbRoot $file) -Type Leaf
}

$scriptsDir = Join-Path $KbRoot 'scripts'
foreach ($script in @(
    'Update-KbFromXpz.ps1',
    'Test-KbFullSnapshot.ps1',
    'Test-KbSetupFreshness.ps1',
    'Test-KbPowerShellRuntime.ps1',
    'Test-KbObjectsXmlNaming.ps1',
    'Query-KbIntelligence.ps1',
    'Rebuild-KbIntelligenceIndex.ps1',
    'Test-KbIndexGate.ps1',
    'Get-KbMetadata.ps1',
    'Test-KbMetadataWrapper.ps1',
    'Test-KbStructure.ps1',
    'Test-KbSetupAudit.ps1'
)) {
    Test-Component -Label "scripts\$script" -Path (Join-Path $scriptsDir $script) -Type Leaf
}

foreach ($script in @('Set-KbSetupAuditTimestamp.ps1')) {
    $optionalPath = Join-Path $scriptsDir $script
    if (Test-Path -LiteralPath $optionalPath -PathType Leaf) {
        Test-Component -Label "scripts\$script" -Path $optionalPath -Type Leaf
    }
}

Test-Component -Label 'KbIntelligence\kb-intelligence.sqlite' `
    -Path (Join-Path $KbRoot 'KbIntelligence\kb-intelligence.sqlite') -Type Leaf

# Parse audit of the expected scripts
$scriptsToParse = @(
    'Update-KbFromXpz.ps1',
    'Test-KbFullSnapshot.ps1',
    'Test-KbSetupFreshness.ps1',
    'Test-KbPowerShellRuntime.ps1',
    'Test-KbObjectsXmlNaming.ps1',
    'Query-KbIntelligence.ps1',
    'Rebuild-KbIntelligenceIndex.ps1',
    'Test-KbIndexGate.ps1',
    'Get-KbMetadata.ps1',
    'Test-KbMetadataWrapper.ps1',
    'Test-KbStructure.ps1',
    'Test-KbSetupAudit.ps1'
)

foreach ($optionalScriptName in @('Set-KbSetupAuditTimestamp.ps1')) {
    if (Test-Path -LiteralPath (Join-Path $scriptsDir $optionalScriptName) -PathType Leaf) {
        $scriptsToParse += $optionalScriptName
    }
}

foreach ($scriptName in $scriptsToParse) {
    $scriptPath = Join-Path $scriptsDir $scriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { continue }
    $parseTokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$parseTokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        $errorSummary = ($parseErrors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        $results.Add([pscustomobject]@{
            Component = "scripts\$scriptName"
            Status    = 'PARSE_ERROR'
            Path      = $errorSummary
        })
    }
}

$results | Format-Table -AutoSize

# Every verdict line goes to stdout (Write-Output), never to the warning stream:
# the index gate reads these lines as the reason of its block.
$missing     = @($results | Where-Object { $_.Status -eq 'MISSING' })
$parseFailed = @($results | Where-Object { $_.Status -eq 'PARSE_ERROR' })
if ($missing.Count -gt 0 -or $parseFailed.Count -gt 0) {
    # A fresh workspace lacks only the index, which the first sync builds: that
    # is a pending step, not a missing component.
    if ($parseFailed.Count -eq 0 -and $missing.Count -eq 1 -and $missing[0].Component -eq 'KbIntelligence\kb-intelligence.sqlite') {
        Write-Output 'PENDING: first index build pending: KbIntelligence/kb-intelligence.sqlite does not exist yet; the first sync builds it, and this check returns STRUCTURE_OK after that.'
        exit 1
    }
    foreach ($item in $missing) {
        Write-Output ("MISSING: {0}" -f $item.Component)
    }
    foreach ($item in $parseFailed) {
        Write-Output ("PARSE_ERROR: {0}: {1}" -f $item.Component, $item.Path)
    }
    Write-Output ("{0} missing component(s), {1} script(s) with a parse error. Run the setup workflow to fix." -f $missing.Count, $parseFailed.Count)
    exit 1
}

Write-Output 'STRUCTURE_OK'
