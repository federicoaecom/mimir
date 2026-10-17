#requires -Version 7.4
<#
.SYNOPSIS
    Runs every check of the CI workflow, in order, from the repository root: the one place that
    lists them, called by .github/workflows/ci.yml and by tools/Invoke-LinuxTestsInDocker.ps1.

.DESCRIPTION
    Steps, each run even when an earlier one fails:
      1. PowerShell version (7.4.6 or later outside Windows: pwsh 7.4.2 loses a native command's
         stderr when stdout and stderr go to separate files).
      2. Test suite (tests/Invoke-Tests.ps1).
      3. Text encoding (UTF-8 without BOM, LF).
      4. PowerShell parse check.
      5. Python parse check.
      6. Markdown fence check (whole repository).
      7. Markdown link check over the governance docs, the skill payload, and the English
         references (the include list below).
      8. Script inventory completeness (09-script-inventory.md).
      9. Code language check (pt-BR in code comments and messages).

    Prints one PASS or FAIL line per step and a summary. Exit code 0 when every step passed,
    1 otherwise. -ListSteps prints the step names, one per line, and runs nothing.

.PARAMETER ListSteps
    Print the step names and exit 0 without running them.
#>
[CmdletBinding()]
param(
    [switch]$ListSteps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

# Scoped to the set that must stay clean: root governance docs, the docs/ index and translation
# process, the agent-facing skill payload (SKILL.md files + mimir-lite workflows/), every English
# knowledge reference under skills/mimir-lite/references/, the process docs, the ADRs, and the
# curated ideas indexes.
$markdownLinkIncludePaths = @(
    'README.md', 'README.es.md',
    'AGENTS.md', 'CLAUDE.md',
    'CONTRIBUTING.md', 'CONTRIBUTING.es.md',
    'SECURITY.md', 'SECURITY.es.md',
    'CODE_OF_CONDUCT.md', 'CODE_OF_CONDUCT.es.md',
    'docs/README.md', 'docs/README.es.md', 'docs/i18n', 'docs/adr', 'docs/ideas',
    'docs/process/13-pre-push-review.md',
    'docs/process/13-pre-push-review.es.md',
    'docs/process/14-reinforced-pre-push-review.md',
    'docs/process/14-reinforced-pre-push-review.es.md',
    'docs/process/15-peer-review.md',
    'docs/process/15-peer-review.es.md',
    'skills/mimir-lite/SKILL.md', 'skills/mimir-delegate/SKILL.md',
    'skills/mimir-lite/workflows',
    'skills/mimir-lite/references/00-index.md',
    'skills/mimir-lite/references/01-empirical-base-overview.md',
    'skills/mimir-lite/references/01a-catalog-and-empirical-patterns.md',
    'skills/mimir-lite/references/01b-part-type-matrix-by-type.md',
    'skills/mimir-lite/references/01c-stable-vs-variable-fields.md',
    'skills/mimir-lite/references/01d-structural-diffs-by-type.md',
    'skills/mimir-lite/references/01e-sanitized-templates-core.md',
    'skills/mimir-lite/references/01f-sanitized-templates-data-and-design.md',
    'skills/mimir-lite/references/01g-sanitized-templates-components-and-physical.md',
    'skills/mimir-lite/references/01h-sanitized-templates-metadata-and-artifacts.md',
    'skills/mimir-lite/references/01j-workwithweb-cdata-patterns.md',
    'skills/mimir-lite/references/01k-legacy-element-registry.md',
    'skills/mimir-lite/references/02-operational-rules.md',
    'skills/mimir-lite/references/02a-runtime-notes-and-known-issues.md',
    'skills/mimir-lite/references/03-risk-and-decision-by-type.md',
    'skills/mimir-lite/references/04-webpanel-families-and-templates.md',
    'skills/mimir-lite/references/04b-ucw-gxcontroltype-reference.md',
    'skills/mimir-lite/references/05-transaction-families-and-templates.md',
    'skills/mimir-lite/references/05b-procedure-and-report-families-and-templates.md',
    'skills/mimir-lite/references/06-object-patterns-and-naming.md',
    'skills/mimir-lite/references/08-agent-guide.md',
    'skills/mimir-lite/references/09-script-inventory.md',
    'skills/mimir-delegate/references/15-peer-review.md',
    'skills/mimir-lite/references/kb-index-methodology.md',
    'skills/mimir-lite/references/kb-index-reference.md'
)

# Each step writes its own output to the host as it runs, and returns only its exit code.
function Invoke-PwshFile([string]$RelativePath) {
    & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repoRoot $RelativePath) | Out-Host
    return $LASTEXITCODE
}

$steps = @(
    @{
        Name = 'PowerShell version (7.4.6+ outside Windows)'
        Run  = {
            Write-Host $PSVersionTable.PSVersion.ToString()
            if (-not $IsWindows -and $PSVersionTable.PSVersion -lt [semver]'7.4.6') {
                Write-Host "PowerShell 7.4.6 or later is required outside Windows; found $($PSVersionTable.PSVersion)."
                return 1
            }
            return 0
        }
    },
    @{ Name = 'Test suite'; Run = { Invoke-PwshFile 'tests/Invoke-Tests.ps1' } },
    @{ Name = 'Text encoding (UTF-8 without BOM, LF)'; Run = { Invoke-PwshFile 'tools/Test-TextEncoding.ps1' } },
    @{ Name = 'PowerShell parse check'; Run = { Invoke-PwshFile 'tools/Test-PsScriptsParse.ps1' } },
    @{ Name = 'Python parse check'; Run = { Invoke-PwshFile 'tools/Test-PyScriptsParse.ps1' } },
    @{ Name = 'Markdown fence check (whole repository)'; Run = { Invoke-PwshFile 'tools/Test-MarkdownFences.ps1' } },
    @{
        Name = 'Markdown link check (governance + skill payload + English references)'
        Run  = {
            # In-process call (not a nested `pwsh -File` process): -IncludePaths is a string array,
            # and a nested process boundary would flatten it to argv, where PowerShell's
            # positional binder only takes the first value for an explicitly named array
            # parameter. The call operator keeps the array as one object.
            $global:LASTEXITCODE = 0
            & (Join-Path $repoRoot 'tools/Test-MarkdownLinks.ps1') -IncludePaths $markdownLinkIncludePaths | Out-Host
            return $LASTEXITCODE
        }
    },
    @{ Name = 'Script inventory completeness (09-script-inventory.md)'; Run = { Invoke-PwshFile 'tools/Test-ScriptInventory.ps1' } },
    @{ Name = 'Code language check (pt-BR in code comments/messages)'; Run = { Invoke-PwshFile 'tools/Test-CodeLanguage.ps1' } }
)

if ($ListSteps) {
    $steps | ForEach-Object { Write-Output $_.Name }
    exit 0
}

Push-Location $repoRoot
$results = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($step in $steps) {
        Write-Output "=== $($step.Name)"
        $exitCode = 1
        try {
            # A step that returns nothing reports no exit code, which never counts as a pass.
            $returned = & $step.Run | Select-Object -Last 1
            $exitCode = if ($null -eq $returned) { 1 } else { [int]$returned }
        }
        catch {
            Write-Output "ERROR: $($_.Exception.Message)"
        }
        $status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        Write-Output "$status ($exitCode): $($step.Name)"
        $results.Add([pscustomobject]@{ Name = $step.Name; Status = $status })
    }
}
finally {
    Pop-Location
}

$failed = @($results | Where-Object { $_.Status -eq 'FAIL' })
Write-Output ''
Write-Output ("CI checks: {0} passed, {1} failed" -f ($results.Count - $failed.Count), $failed.Count)
$failed | ForEach-Object { Write-Output "  FAIL: $($_.Name)" }
exit ([int]($failed.Count -gt 0))
