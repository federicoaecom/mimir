#requires -Version 7.4
<#
.SYNOPSIS
    Validates KB Intelligence query behavior against small JSON case files.
.DESCRIPTION
    Runs KbIntelligenceQueryCases.py (same folder) with Python 3. Exit code 2 means at
    least one case failed and -FailOnValidationFailure was set.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$IndexPath,

    [Parameter(Mandatory = $true)]
    [string]$ValidationCasesPath,

    [string]$ValidationReportPath,

    [switch]$FailOnValidationFailure
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$enginePath = Join-Path $scriptDir "KbIntelligenceQueryCases.py"

if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "Engine script not found: $enginePath"
}

. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')
$python = Get-GeneXusPythonExecutable
if ($null -eq $python) {
    throw "$(Get-GeneXusPythonNotFoundMessage) Python 3 with sqlite3 is required."
}

$arguments = @(
    $enginePath,
    "--index-path", $IndexPath,
    "--validation-cases-path", $ValidationCasesPath
)

if ($ValidationReportPath) { $arguments += @("--validation-report-path", $ValidationReportPath) }
if ($FailOnValidationFailure) { $arguments += @("--fail-on-validation-failure") }

& $python.Source @($python.PrefixArguments) @arguments
exit $LASTEXITCODE
