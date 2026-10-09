#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for the setup audit and index gate messages on a fresh KB workspace.
.DESCRIPTION
    Scaffolds synthetic workspaces with New-MimirKbWorkspace.ps1 under the system
    temp folder (no XPZ synced, no index built) and checks:
    (a) the setup audit reports the unbuilt index as pending with a reason:
        index/gate PENDING, evidence naming kb-intelligence.sqlite and the first
        sync, no "missing component(s)" text, and no line ending in a bare colon;
    (b) the index gate still blocks, with a non-empty reason that names the
        first index build, in -AsJson and in text mode;
    (c) a workspace that also lacks a wrapper keeps index/gate BLOCK, and the
        gate reason names the missing wrapper instead of ending at the colon;
    (d) a structure wrapper copied before this fix (warning only, no stdout)
        still gets a pending reason for the unbuilt index, and a structure
        wrapper that prints nothing gets a non-empty reason.
    No real KB, no external tool; child scripts run in their own pwsh process.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Plain output in child processes, so assertions see no ANSI sequences.
$env:NO_COLOR = '1'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scaffolder = Join-Path $repoRoot 'skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-fresh-audit-{0}' -f [guid]::NewGuid().ToString('N'))
$utf8 = [System.Text.UTF8Encoding]::new($false)
$kbName = 'FreshKb'

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-ChildScript {
    param([string]$Path, [string[]]$Arguments = @())
    $output = & pwsh -NoProfile -NonInteractive -File $Path @Arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @($output | ForEach-Object { "$_" })
        Text     = (@($output | ForEach-Object { "$_" }) -join "`n")
    }
}

function New-FreshWorkspace {
    param([string]$Label)
    $ws = Join-Path $tempRoot $Label
    $run = Invoke-ChildScript -Path $scaffolder -Arguments @('-WorkspaceRoot', $ws, '-KbName', $kbName)
    if ($run.ExitCode -ne 0) {
        throw "scaffolder failed for $Label (exit $($run.ExitCode)): $($run.Text)"
    }
    return $ws
}

function Get-AuditValue {
    param([string[]]$Lines, [string]$Key)
    $prefix = "${Key}: "
    $line = @($Lines | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::Ordinal) }) | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return $line.Substring($prefix.Length)
}

function Get-GateJson {
    param([string]$Workspace)
    $gate = Join-Path $Workspace "scripts/Test-${kbName}KbIndexGate.ps1"
    $stdout = & pwsh -NoProfile -NonInteractive -File $gate -AsJson 2>$null | Out-String
    $exit = $LASTEXITCODE
    $json = $null
    $start = $stdout.IndexOf('{')
    if ($start -ge 0) {
        try { $json = $stdout.Substring($start) | ConvertFrom-Json } catch { $json = $null }
    }
    return [pscustomobject]@{ ExitCode = $exit; Json = $json; Raw = $stdout }
}

try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)

    # (a) Fresh workspace: the audit reports the unbuilt index as pending, with a reason.
    $wsA = New-FreshWorkspace -Label 'ws-a'
    $audit = Invoke-ChildScript -Path (Join-Path $wsA "scripts/Test-${kbName}KbSetupAudit.ps1")
    Assert-True ($audit.ExitCode -eq 0) "(a) audit must exit 0; exit=$($audit.ExitCode), output=$($audit.Text)"
    Assert-True ($audit.Text -notmatch 'missing component\(s\)') "(a) audit must not print 'missing component(s)' for the unbuilt index; output=$($audit.Text)"
    $bareColon = @($audit.Output | Where-Object { $_.TrimEnd() -match ':$' })
    Assert-True ($bareColon.Count -eq 0) "(a) no audit line may end in a bare colon; lines=$($bareColon -join ' | ')"
    $gateValue = Get-AuditValue -Lines $audit.Output -Key 'index/gate'
    $gateEvidence = Get-AuditValue -Lines $audit.Output -Key 'index/gate.evidence'
    Assert-True ($gateValue -eq 'PENDING') "(a) index/gate must be PENDING on a fresh workspace; got '$gateValue'"
    Assert-True ($null -ne $gateEvidence -and $gateEvidence -match 'first index build pending' -and $gateEvidence -match 'kb-intelligence\.sqlite' -and $gateEvidence -match 'first sync') "(a) index/gate.evidence must name the pending first index build; got '$gateEvidence'"
    Assert-True ($null -ne $gateEvidence -and $gateEvidence -notmatch 'BLOCK:') "(a) index/gate.evidence must not carry a BLOCK prefix when the index is only pending; got '$gateEvidence'"
    $semanticsValue = Get-AuditValue -Lines $audit.Output -Key 'index/semantics'
    Assert-True ($semanticsValue -eq 'PENDING') "(a) index/semantics must stay PENDING; got '$semanticsValue'"
    $state = Get-AuditValue -Lines $audit.Output -Key 'suggested_operational_state'
    Assert-True ($state -eq 'ready_for_first_materialization') "(a) suggested state must be ready_for_first_materialization; got '$state'"

    $auditJsonRun = Invoke-ChildScript -Path (Join-Path $wsA "scripts/Test-${kbName}KbSetupAudit.ps1") -Arguments @('-AsJson')
    $auditJson = $null
    $auditJsonStart = $auditJsonRun.Text.IndexOf('{')
    if ($auditJsonStart -ge 0) {
        try { $auditJson = $auditJsonRun.Text.Substring($auditJsonStart) | ConvertFrom-Json } catch { $auditJson = $null }
    }
    Assert-True ($null -ne $auditJson -and $auditJson.'index/gate' -eq 'PENDING') "(a) audit -AsJson must report index/gate PENDING; output=$($auditJsonRun.Text)"

    # (b) The index gate still blocks, with a reason naming the first index build.
    $gateA = Get-GateJson -Workspace $wsA
    Assert-True ($gateA.ExitCode -eq 1 -and $null -ne $gateA.Json -and $gateA.Json.status -eq 'BLOCK') "(b) gate -AsJson must block with exit 1; exit=$($gateA.ExitCode), raw=$($gateA.Raw)"
    Assert-True ($null -ne $gateA.Json -and "$($gateA.Json.reason)" -match 'first index build pending' -and "$($gateA.Json.reason)" -match 'kb-intelligence\.sqlite') "(b) gate reason must name the pending first index build; raw=$($gateA.Raw)"
    $gateText = Invoke-ChildScript -Path (Join-Path $wsA "scripts/Test-${kbName}KbIndexGate.ps1")
    Assert-True ($gateText.ExitCode -ne 0) "(b) gate text mode must exit non-zero; output=$($gateText.Text)"
    Assert-True ($gateText.Text -match 'BLOCK: first index build pending') "(b) gate text mode must throw 'BLOCK: first index build pending'; output=$($gateText.Text)"
    Assert-True ($gateText.Text -notmatch 'missing component\(s\)') "(b) gate text mode must not print 'missing component(s)'; output=$($gateText.Text)"

    # (c) A missing wrapper is still a block, and the reason names it.
    $wsC = New-FreshWorkspace -Label 'ws-c'
    Remove-Item -LiteralPath (Join-Path $wsC "scripts/Test-${kbName}KbFullSnapshot.ps1") -Force
    $gateC = Get-GateJson -Workspace $wsC
    $reasonC = if ($null -ne $gateC.Json) { "$($gateC.Json.reason)" } else { '' }
    Assert-True ($gateC.ExitCode -eq 1 -and $reasonC -match "Test-${kbName}KbFullSnapshot\.ps1") "(c) gate reason must name the missing wrapper; raw=$($gateC.Raw)"
    Assert-True ($reasonC -notmatch 'first index build pending') "(c) a missing wrapper must not be reported as a pending first index build; reason=$reasonC"
    Assert-True ($reasonC.TrimEnd() -notmatch ':$') "(c) gate reason must not end in a bare colon; reason=$reasonC"
    $auditC = Invoke-ChildScript -Path (Join-Path $wsC "scripts/Test-${kbName}KbSetupAudit.ps1")
    Assert-True ((Get-AuditValue -Lines $auditC.Output -Key 'index/gate') -eq 'BLOCK') "(c) audit index/gate must stay BLOCK when a wrapper is missing; output=$($auditC.Text)"

    # (d) Structure wrappers copied before this fix.
    $wsD = New-FreshWorkspace -Label 'ws-d'
    $structureD = Join-Path $wsD "scripts/Test-${kbName}KbStructure.ps1"
    [System.IO.File]::WriteAllText($structureD, "Write-Warning '1 missing component(s). Run the setup workflow to fix.'`nexit 1`n", $utf8)
    $gateD = Get-GateJson -Workspace $wsD
    $reasonD = if ($null -ne $gateD.Json) { "$($gateD.Json.reason)" } else { '' }
    Assert-True ($reasonD -match 'first index build pending') "(d) an older structure wrapper must still yield a pending first index build; raw=$($gateD.Raw)"

    [System.IO.File]::WriteAllText($structureD, "exit 1`n", $utf8)
    $gateD2 = Get-GateJson -Workspace $wsD
    $reasonD2 = if ($null -ne $gateD2.Json) { "$($gateD2.Json.reason)" } else { '' }
    Assert-True ($reasonD2 -match 'structure check failed: \S') "(d) a silent structure wrapper must still yield a non-empty reason; raw=$($gateD2.Raw)"
    Assert-True ($reasonD2.TrimEnd() -notmatch ':$') "(d) gate reason must not end in a bare colon; reason=$reasonD2"
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw ("Fresh workspace audit self-test failed:`n - " + ($failures -join "`n - "))
}
Write-Output 'MIMIR_FRESH_WORKSPACE_AUDIT_SELFTEST_OK'
