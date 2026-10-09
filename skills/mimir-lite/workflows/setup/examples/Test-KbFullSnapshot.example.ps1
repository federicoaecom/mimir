#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper for a full check of a full KB export.

.DESCRIPTION
Reuses the daily wrapper in verify-only mode, comparing against the full
snapshot kept in `KbObjectsXml`.

.PARAMETER ExpectedItems
Optional list of expected items in `Type:Name` format, forwarded to the daily
wrapper to compare the expected focus against the official KB return.

.PARAMETER NoGitSummary
Suppresses the local Git change summary produced by the daily wrapper.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbFullSnapshot.ps1" -InputPath "<WorkspaceRoot>/IdeXpzExports/FullKb.xpz" -ExpectedItems 'Transaction:Cliente'

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Test-KbFullSnapshot.ps1" -InputPath "<WorkspaceRoot>/IdeXpzExports/FullKb.xpz" -ExpectedItems 'Transaction:Cliente,Procedure:GeraBoleto'
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$ReportPath,

    [string[]]$ExpectedItems = @(),

    [switch]$KeepReport,

    [switch]$NoGitSummary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$wrapperPath = Join-Path $scriptRoot "Update-KbFromXpz.ps1"

if (-not (Test-Path -LiteralPath $wrapperPath)) {
    throw "Wrapper script not found: $wrapperPath"
}

$params = @{
    InputPath = $InputPath
    VerifyOnly = $true
    FullSnapshot = $true
}

if ($ReportPath) {
    $params.ReportPath = $ReportPath
}

if ($KeepReport) {
    $params.KeepReport = $true
}

if ($ExpectedItems.Count -gt 0) {
    $params.ExpectedItems = @($ExpectedItems)
}

if ($NoGitSummary) {
    $params.NoGitSummary = $true
}

& $wrapperPath @params
