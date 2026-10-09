#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to query the derived KB index.

.DESCRIPTION
Uses the default local index of the KB workspace and delegates the query to the
shared engine of this methodology base.

.PARAMETER Query
Query to run against the index.

.PARAMETER IndexPath
Optional path to an alternative SQLite file. The local default points to
`KbIntelligence\kb-intelligence.sqlite`.

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout. Use this parameter when the
shared checkout lives at a different local path.

.PARAMETER KbWorkspaceRoot
Root of the KB workspace. By default, the parent folder of this wrapper's
`scripts/`. Used to resolve `scripts/gx-object-type-catalog.override.json` in
the `queryableByKbIntelligence` gate of the semantic queries.

.PARAMETER CatalogOverridePath
Optional path to the catalog override (takes precedence over detection through KbWorkspaceRoot).

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Query-KbIntelligence.ps1" -Query impact-basic -ObjectType Procedure -ObjectName procExample -Limit 10 -Format text

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Query-KbIntelligence.ps1" -Query functional-trace-basic -ObjectType Procedure -ObjectName procExample -Limit 20 -Format text

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Query-KbIntelligence.ps1" -Query list-by-type -ObjectType Procedure -Format text

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Query-KbIntelligence.ps1" -Query index-metadata -Format text
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("object-info", "attribute-info", "search-objects", "list-by-type", "transaction-attributes", "transaction-writable-attributes", "who-uses", "what-uses", "show-evidence", "impact-basic", "functional-trace-basic", "index-metadata", "css-classes", "css-class-usage")]
    [string]$Query,

    [string]$IndexPath,

    [string]$ObjectType,
    [string]$ObjectName,
    [string]$InstanceKey,
    [int]$RelationId,
    [string]$SourceType,
    [string]$SourceName,
    [string]$TargetType,
    [string]$TargetName,
    [string]$Model,
    [string]$Origin,
    [switch]$IncludeImported,
    [switch]$Generated,
    [switch]$Authored,
    [int]$Limit,

    [ValidateSet("json", "text")]
    [string]$Format = "json",

    [string]$KbWorkspaceRoot,

    [string]$CatalogOverridePath,

    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $SharedSkillsRoot "skills\mimir-lite\scripts\Query-KbIntelligenceIndex.ps1"

if (-not $IndexPath) {
    $IndexPath = Join-Path $repoRoot "KbIntelligence\kb-intelligence.sqlite"
}

if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "Engine script not found: $enginePath"
}

if (-not (Test-Path -LiteralPath $IndexPath)) {
    throw "KB Intelligence index not found: $IndexPath"
}

if (-not $KbWorkspaceRoot) {
    $KbWorkspaceRoot = $repoRoot
}

$params = @{
    IndexPath       = $IndexPath
    Query           = $Query
    Format          = $Format
    KbWorkspaceRoot = $KbWorkspaceRoot
}

if ($CatalogOverridePath) {
    $params.CatalogOverridePath = $CatalogOverridePath
}

if ($ObjectType) { $params.ObjectType = $ObjectType }
if ($ObjectName) { $params.ObjectName = $ObjectName }
if ($InstanceKey) { $params.InstanceKey = $InstanceKey }
if ($RelationId) { $params.RelationId = $RelationId }
if ($SourceType) { $params.SourceType = $SourceType }
if ($SourceName) { $params.SourceName = $SourceName }
if ($TargetType) { $params.TargetType = $TargetType }
if ($TargetName) { $params.TargetName = $TargetName }
if ($Model) { $params.Model = $Model }
if ($Origin) { $params.Origin = $Origin }
if ($IncludeImported) { $params.IncludeImported = $true }
if ($Generated) { $params.Generated = $true }
if ($Authored) { $params.Authored = $true }
if ($Limit) { $params.Limit = $Limit }

$global:LASTEXITCODE = $null
& $enginePath @params
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
