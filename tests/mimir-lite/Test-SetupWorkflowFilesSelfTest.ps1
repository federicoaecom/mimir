#requires -Version 7.4
<#
.SYNOPSIS
    Guards the setup workflow files: their size budgets and their coverage by the
    setup contract manifest.
.DESCRIPTION
    Reads only repository files; no KB, no external engine.

    Size budgets: an agent reads a workflow file in one file-read call, capped at
    25,000 tokens, and this workflow text measures about 2.74 bytes per token
    (61,256 bytes read as about 22,400 tokens). setup.md is read on every setup run,
    so it keeps the larger budget, 65,000 bytes (about 23,700 tokens); each file
    under workflows/setup/ keeps 50,000 bytes (about 18,200 tokens).

    Contract coverage: every workflows/setup/*.md is part of the setup contract, so
    each must match an `include` entry of setup-contract.manifest.json (exact path or
    glob); otherwise a change to it would not change the setup contract signature.
.PARAMETER SetupMaxBytes
    Byte budget for workflows/setup.md. Override only to prove the check can fail.
.PARAMETER FileMaxBytes
    Byte budget for each workflows/setup/*.md. Override only to prove the check can fail.
.PARAMETER ManifestPath
    Manifest to check against. Default: the repository's setup-contract.manifest.json.
#>
param(
    [int]$SetupMaxBytes = 65000,
    [int]$FileMaxBytes = 50000,
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workflowsDir = Join-Path $repoRoot 'skills/mimir-lite/workflows'
$setupSubDir = Join-Path $workflowsDir 'setup'
if (-not $ManifestPath) {
    $ManifestPath = Join-Path $setupSubDir 'setup-contract.manifest.json'
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$setupMdPath = Join-Path $workflowsDir 'setup.md'
$setupMdBytes = (Get-Item -LiteralPath $setupMdPath).Length
Assert-True ($setupMdBytes -le $SetupMaxBytes) "workflows/setup.md is $setupMdBytes bytes, over its $SetupMaxBytes-byte budget"

$setupFiles = @(Get-ChildItem -LiteralPath $setupSubDir -File -Filter '*.md' | Sort-Object Name)
Assert-True ($setupFiles.Count -gt 0) 'workflows/setup/ must hold at least one .md file'
foreach ($file in $setupFiles) {
    Assert-True ($file.Length -le $FileMaxBytes) "workflows/setup/$($file.Name) is $($file.Length) bytes, over its $FileMaxBytes-byte budget"
}

$manifest = [System.IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
$includes = @($manifest.include)
foreach ($file in $setupFiles) {
    $relative = "skills/mimir-lite/workflows/setup/$($file.Name)"
    $covered = @($includes | Where-Object { $relative -like $_ }).Count -gt 0
    Assert-True $covered "$relative is not covered by any include entry of the setup contract manifest"
}

if ($failures.Count -gt 0) {
    throw ("Setup workflow files contract failed:`n - " + ($failures -join "`n - "))
}
Write-Output 'SETUP_WORKFLOW_FILES_SELFTEST_OK'
