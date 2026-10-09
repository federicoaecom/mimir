#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for the PUBLIC_TRACEABILITY_VERBOSE_LINE signal of Test-PrePushTraceabilityCoverage.ps1.

.DESCRIPTION
    Builds a temporary root with a synthetic 09 and invokes the gate with a non-empty
    -ChangedFiles (skips the git diff; the verbosity signal is invariant over the 09 text).
    Confirms:
      - a script line in the old verbose format (`Direct evidence` label glued to a
        path `skills/mimir-lite/scripts/` or `tools/`) -> triggers PUBLIC_TRACEABILITY_VERBOSE_LINE
        (covers both real script-root families the regex alternation must match);
      - a lean pointer (`- `skills/mimir-lite/scripts/X` (category) -- ...`, no label) -> does NOT trigger;
      - a governance bullet that cites a script with intervening text (": the script `skills/.../X`")
        -> does NOT trigger;
      - a fully lean 09 -> status pass, zero verbosity findings;
      - an agent guide (08) changed with the pre-push doc is checked for the English markers it
        actually carries (`09-script-inventory.md`, `docs/process/`), and the current 08 raises
        no AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE.
    Does not need git.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools') 'Test-PrePushTraceabilityCoverage.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-traceability-verbose-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$publicTraceabilityRelative = 'skills/mimir-lite/references/09-script-inventory.md'
[void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'skills/mimir-lite/references') -Force)

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Utf8NoBomEncodingSupport.ps1')
$utf8NoBom = Get-Utf8NoBomEncoding

function Write-Synthetic09 {
    param([string]$Content)
    [System.IO.File]::WriteAllText((Join-Path $tempRoot $publicTraceabilityRelative), $Content, $utf8NoBom)
}

function Invoke-Gate {
    $output = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -ChangedFiles $publicTraceabilityRelative -AsJson 2>&1
    $script:lastExit = $LASTEXITCODE
    return (($output | Out-String).Trim() | ConvertFrom-Json)
}

try {
    # Scenario 1: two verbose entries (skills/mimir-lite/scripts/ and tools/) + three negatives.
    Write-Synthetic09 @'
# 09 synthetic

## Note on the shared operational engine

- `Direct evidence`: `skills/mimir-lite/scripts/FooVerbose.ps1` describes its contract with parameters, exit codes and consumers at length, duplicating the logical owner.
- `skills/mimir-lite/scripts/BarLean.ps1` (engine) — role in one sentence. Owner: 02. Validation: none.
- `Direct evidence`: the script `skills/mimir-lite/scripts/BazGovernance.ps1` is part of this base's operational infrastructure; it is not a script pointer.
- `Direct evidence`: `tools/CampaignVerbose.ps1` implements a maintenance campaign with long contract prose.
- `tools/CampaignLean.ps1` (maintenance) — campaign. Owner: 10a.
'@
    $r1 = Invoke-Gate
    if ($script:lastExit -ne 0) { throw "gate should exit with 0 (advisory); got $($script:lastExit)" }
    if ($r1.status -ne 'warn') { throw "scenario 1: status should be 'warn'; got '$($r1.status)'" }
    $verbose1 = @($r1.findings | Where-Object { $_.code -eq 'PUBLIC_TRACEABILITY_VERBOSE_LINE' })
    if ($verbose1.Count -ne 2) {
        throw ("scenario 1: there should be 2 PUBLIC_TRACEABILITY_VERBOSE_LINE (skills/mimir-lite/scripts/ + tools/); got {0}. Findings: {1}" -f $verbose1.Count, (@($r1.findings | ForEach-Object { $_.code }) -join ', '))
    }

    # Scenario 2: a fully lean 09 (no verbose format) -> pass, zero verbosity.
    Write-Synthetic09 @'
# 09 synthetic lean

## Note on the shared operational engine

- `skills/mimir-lite/scripts/BarLean.ps1` (engine) — role in one sentence. Owner: 02. Validation: none.
- `Direct evidence`: the script `skills/mimir-lite/scripts/BazGovernance.ps1` is part of the operational infrastructure; it is not a pointer.
- `Strong inference`: editorial reasoning note, not a script pointer.
'@
    $r2 = Invoke-Gate
    if ($script:lastExit -ne 0) { throw "gate should exit with 0 (advisory); got $($script:lastExit)" }
    $verbose2 = @($r2.findings | Where-Object { $_.code -eq 'PUBLIC_TRACEABILITY_VERBOSE_LINE' })
    if ($verbose2.Count -ne 0) {
        throw ("scenario 2: a lean 09 should not trigger verbosity; got {0}" -f $verbose2.Count)
    }
    if ($r2.status -ne 'pass') {
        throw ("scenario 2: status should be 'pass'; got '$($r2.status)'. Findings: {0}" -f (@($r2.findings | ForEach-Object { $_.code }) -join ', '))
    }

    # Scenario 3: the pre-push process doc changed together with an 08 that lacks the
    # expected markers -> one AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE per English marker.
    $agentGuideRelative = 'skills/mimir-lite/references/08-agent-guide.md'
    [System.IO.File]::WriteAllText((Join-Path $tempRoot $agentGuideRelative), "# 08 synthetic`n", $utf8NoBom)
    $output3 = & pwsh -NoProfile -Command "& '$scriptPath' -RootPath '$tempRoot' -ChangedFiles 'docs/process/13-pre-push-review.md','$agentGuideRelative' -AsJson" 2>&1
    $r3 = (($output3 | Out-String).Trim() | ConvertFrom-Json)
    $incomplete3 = @($r3.findings | Where-Object { $_.code -eq 'AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE' })
    $markers3 = @($incomplete3 | ForEach-Object { ($_.message -split 'expected marker: ')[-1] } | Sort-Object)
    if (($markers3 -join ',') -ne '09-script-inventory.md,docs/process/') {
        throw ("scenario 3: expected markers 'docs/process/' and '09-script-inventory.md'; got: {0}" -f ($markers3 -join ' | '))
    }

    # Scenario 4: the retired pt-BR path no longer triggers the pre-push doc rule.
    $output4 = & pwsh -NoProfile -Command "& '$scriptPath' -RootPath '$tempRoot' -ChangedFiles 'docs/process/13-revisao-pre-push.md','$agentGuideRelative' -AsJson" 2>&1
    $r4 = (($output4 | Out-String).Trim() | ConvertFrom-Json)
    if (@($r4.findings | Where-Object { $_.code -eq 'AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE' }).Count -ne 0) {
        throw 'scenario 4: the retired pt-BR doc path must not trigger AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE'
    }

    # Scenario 5: the current agent guide carries every expected marker -> no finding.
    $realAgentGuide = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) $agentGuideRelative
    Copy-Item -LiteralPath $realAgentGuide -Destination (Join-Path $tempRoot $agentGuideRelative) -Force
    $output5 = & pwsh -NoProfile -Command "& '$scriptPath' -RootPath '$tempRoot' -ChangedFiles 'docs/process/13-pre-push-review.md','$agentGuideRelative' -AsJson" 2>&1
    $r5 = (($output5 | Out-String).Trim() | ConvertFrom-Json)
    $incomplete5 = @($r5.findings | Where-Object { $_.code -eq 'AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE' })
    if ($incomplete5.Count -ne 0) {
        throw ("scenario 5: the current agent guide must not raise AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE; got: {0}" -f (@($incomplete5 | ForEach-Object { $_.message }) -join ' | '))
    }

    Write-Output 'OK: Test-PrePushTraceabilityCoverageSelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
