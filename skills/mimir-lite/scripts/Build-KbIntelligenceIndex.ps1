#requires -Version 7.4
<#
.SYNOPSIS
    Builds the KB Intelligence SQLite index.

.DESCRIPTION
    Wrapper for Build-KbIntelligenceIndex.py. Keeps paths explicit and avoids
    hardcoded KB-specific locations.

.PARAMETER SourceRoot
    Root folder of the materialized XML catalog, usually KbObjectsXml.

.PARAMETER OutputPath
    Destination SQLite database path.

.PARAMETER ValidationReportPath
    Optional JSON validation report path.

.PARAMETER ValidationCasesPath
    Optional JSON file with validation cases for the current KB.

.PARAMETER FailOnValidationFailure
    Return a non-zero exit code when any validation case fails.

.PARAMETER KbWorkspaceRoot
    Root of the KB workspace; resolves scripts/gx-object-type-catalog.override.json when it exists.

.PARAMETER CatalogOverridePath
    Explicit path of the local override; takes precedence over automatic detection via the KB workspace.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ValidationReportPath,

    [string]$ValidationCasesPath,

    [switch]$FailOnValidationFailure,

    [string]$KbWorkspaceRoot,

    [string]$CatalogOverridePath
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')

$enginePath = Join-Path $scriptDir "Build-KbIntelligenceIndex.py"

if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "Engine script not found: $enginePath"
}

$python = Get-GeneXusPythonExecutable
if ($null -eq $python) {
    Write-Host (Get-GeneXusPythonPrerequisiteErrorMessage) -ForegroundColor Red
    exit 8
}

$arguments = @(
    $enginePath,
    "--source-root", $SourceRoot,
    "--output-path", $OutputPath
)

if ($ValidationReportPath) {
    $arguments += @("--validation-report-path", $ValidationReportPath)
}
if ($ValidationCasesPath) {
    $arguments += @("--validation-cases-path", $ValidationCasesPath)
}
if ($FailOnValidationFailure) {
    $arguments += "--fail-on-validation-failure"
}
if ($KbWorkspaceRoot) {
    $arguments += @("--kb-workspace-root", $KbWorkspaceRoot)
}
if ($CatalogOverridePath) {
    $arguments += @("--catalog-override-path", $CatalogOverridePath)
}

$output = @(& $python.Source @($python.PrefixArguments) @arguments 2>&1)
$engineExitCode = $LASTEXITCODE

if ($output.Count -gt 0) {
    $output | ForEach-Object { Write-Output $_ }
}

if ($engineExitCode -ne 0) {
    exit $engineExitCode
}

exit 0
