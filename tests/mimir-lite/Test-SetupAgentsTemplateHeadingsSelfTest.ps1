#requires -Version 7.4
<#
.SYNOPSIS
    Guards the English headings of the workspace AGENTS.md template and their
    parity with the setup and find workflows that route by them.
.DESCRIPTION
    Reads only repository files; no KB, no external engine.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$setupDir = Join-Path $repoRoot 'skills/mimir-lite/workflows'
$template = [System.IO.File]::ReadAllText((Join-Path $setupDir 'setup/examples/AGENTS.md.example'))
# The setup workflow spans setup.md plus the files under setup/ (not setup/examples/).
$setupFiles = @(Join-Path $setupDir 'setup.md') + @(Get-ChildItem -LiteralPath (Join-Path $setupDir 'setup') -File -Filter '*.md' | Sort-Object Name | ForEach-Object { $_.FullName })
$setupWorkflowText = ($setupFiles | ForEach-Object { [System.IO.File]::ReadAllText($_) }) -join "`n"
$findMd = [System.IO.File]::ReadAllText((Join-Path $setupDir 'find.md'))

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

$englishHeadings = @('## Index triage', '## Local wrappers', '## Operational state')

foreach ($heading in $englishHeadings) {
    $quoted = [string]([char]96) + $heading + [char]96
    Assert-True ($template -match "(?m)^$([regex]::Escape($heading))\s*$") "template must carry the heading '$heading'"
    Assert-True ($setupWorkflowText.Contains($quoted)) "the setup workflow (setup.md and setup/*.md) must match the heading '$heading'"
}
Assert-True ($findMd.Contains('`## Index triage`')) "find.md must match the heading '## Index triage'"

if ($failures.Count -gt 0) {
    throw ("Setup AGENTS template heading contract failed:`n - " + ($failures -join "`n - "))
}
Write-Output 'SETUP_AGENTS_TEMPLATE_HEADINGS_SELFTEST_OK'
