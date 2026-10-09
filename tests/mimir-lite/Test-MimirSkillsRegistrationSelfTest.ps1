#requires -Version 7.4

<#
.SYNOPSIS
    Deterministic self-test for Test-MimirSkillsRegistration.ps1.

.DESCRIPTION
    Builds a fake skills root and user profile in a temporary folder and
    checks the per-tool classification with no network. Simulates links with
    junctions on Windows (no administrator privilege required) and symbolic
    links elsewhere. The fake profile is injected via both $env:USERPROFILE and
    $env:HOME during the invocation, and both are restored at the end.

    Covers: OK, missing, broken, covered_by_compatibility and orphan.
    Additional isolated cases: Cursor-only compat marks REGISTRATION_GAPS;
    a native link at ~/.cursor/skills produces Cursor OK and REGISTRATION_OK;
    the profile resolves from HOME alone (no USERPROFILE), and a clear BLOCK is
    raised when neither variable is set. -SkipTool/-SkipSkill cases, and the
    exit contract as a child process (pwsh -File): REGISTRATION_GAPS exits 0
    with its JSON; an unknown skip name exits non-zero with BLOCK on stderr
    and nothing on stdout.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptUnderTest = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Test-MimirSkillsRegistration.ps1'
if (-not (Test-Path -LiteralPath $scriptUnderTest -PathType Leaf)) {
    throw "BLOCK: target script not found: $scriptUnderTest"
}

$failures = 0
$cases = 0

function New-TempDir {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-regselftest-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

# Points both profile variables at the fake profile ($null removes them).
function Set-FakeProfile {
    param([AllowNull()][string]$Path)
    $env:USERPROFILE = $Path
    $env:HOME = $Path
}

function Restore-RealProfile {
    $env:USERPROFILE = $script:originalProfile
    $env:HOME = $script:originalHome
}

# Removes a temporary tree. Links are deleted first, as links, so their targets
# (fake skills, or this repository's real skills) are never followed or touched.
function Remove-TempTree {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $links = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LinkType } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($link in $links) {
        try { $link.Delete() } catch { try { [System.IO.File]::Delete($link.FullName) } catch { } }
    }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.Attributes = 'Normal' } catch { } }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function New-FakeSkill {
    param([string]$SkillRepoRoot, [string]$Name, [switch]$WithoutSkillMd)
    $dir = Join-Path $SkillRepoRoot $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (-not $WithoutSkillMd) {
        Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value "# $Name" -Encoding utf8
    }
    return $dir
}

function New-Junction {
    # A junction on Windows (no privilege needed); a symbolic link elsewhere.
    param([string]$LinkDir, [string]$Name, [string]$Target)
    if (-not (Test-Path -LiteralPath $LinkDir -PathType Container)) {
        New-Item -ItemType Directory -Path $LinkDir -Force | Out-Null
    }
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path (Join-Path $LinkDir $Name) -Target $Target | Out-Null
}

function Get-SkillStatus {
    param($Report, [string]$Tool, [string]$Skill)
    $t = $Report.tools | Where-Object { $_.name -eq $Tool }
    if (-not $t) { return '<tool-missing>' }
    $s = $t.skills | Where-Object { $_.name -eq $Skill }
    if (-not $s) { return '<skill-missing>' }
    return $s.status
}

function Assert-Equal {
    param([string]$CaseName, [string]$Expected, [string]$Actual)
    $script:cases++
    if ($Actual -eq $Expected) {
        Write-Output ("PASS: {0} -> {1}" -f $CaseName, $Expected)
    }
    else {
        $script:failures++
        Write-Output ("FAIL: {0} -> expected '{1}', got '{2}'" -f $CaseName, $Expected, $Actual)
    }
}

$fakeRepo = New-TempDir
$fakeProfile = New-TempDir
$brokenTarget = Join-Path $fakeProfile 'broken-target'
$originalProfile = $env:USERPROFILE
$originalHome = $env:HOME
$originalPath = $env:PATH

try {
    $env:PATH = ''
    # Inventory: skill-a, skill-b, skill-c (with SKILL.md). skill-removida without SKILL.md.
    New-FakeSkill -SkillRepoRoot $fakeRepo -Name 'skill-a' | Out-Null
    New-FakeSkill -SkillRepoRoot $fakeRepo -Name 'skill-b' | Out-Null
    New-FakeSkill -SkillRepoRoot $fakeRepo -Name 'skill-c' | Out-Null
    New-FakeSkill -SkillRepoRoot $fakeRepo -Name 'skill-removida' -WithoutSkillMd | Out-Null

    New-Item -ItemType Directory -Path $brokenTarget -Force | Out-Null

    $claudeSkills = Join-Path $fakeProfile '.claude/skills'
    $codexSkills = Join-Path $fakeProfile '.codex/skills'
    $geminiSkills = Join-Path $fakeProfile '.gemini/config/skills'

    # OK in Claude
    New-Junction -LinkDir $claudeSkills -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')
    # broken in Claude (target removed afterwards)
    New-Junction -LinkDir $claudeSkills -Name 'skill-c' -Target $brokenTarget
    # orphan in Claude (points to the repo, but is not in the inventory)
    New-Junction -LinkDir $claudeSkills -Name 'skill-removida' -Target (Join-Path $fakeRepo 'skill-removida')
    # OK in Codex
    New-Junction -LinkDir $codexSkills -Name 'skill-b' -Target (Join-Path $fakeRepo 'skill-b')
    # OK in Antigravity (.gemini\config\skills)
    New-Junction -LinkDir $geminiSkills -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')

    # Make skill-c broken: remove the junction's target
    Remove-Item -LiteralPath $brokenTarget -Recurse -Force

    # Mark tools as installed deterministically (independent of the real PATH):
    Set-Content -LiteralPath (Join-Path $fakeProfile '.claude/settings.json') -Value '{}' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $fakeProfile '.codex') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeProfile '.codex/config.toml') -Value '' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $fakeProfile '.cursor') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeProfile '.cursor/mcp.json') -Value '{}' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $fakeProfile '.config/opencode') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeProfile '.config/opencode/opencode.json') -Value '{}' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $fakeProfile '.gemini/config') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeProfile '.gemini/config/config.json') -Value '{}' -Encoding utf8

    Set-FakeProfile $fakeProfile
    $json = & $scriptUnderTest -RepoRoot $fakeRepo -AsJson | Out-String
    Restore-RealProfile
    $report = $json | ConvertFrom-Json

    Assert-Equal 'Claude/skill-a OK' 'OK' (Get-SkillStatus -Report $report -Tool 'ClaudeCode' -Skill 'skill-a')
    Assert-Equal 'Claude/skill-b missing' 'missing' (Get-SkillStatus -Report $report -Tool 'ClaudeCode' -Skill 'skill-b')
    Assert-Equal 'Claude/skill-c broken' 'broken' (Get-SkillStatus -Report $report -Tool 'ClaudeCode' -Skill 'skill-c')
    Assert-Equal 'Codex/skill-b OK' 'OK' (Get-SkillStatus -Report $report -Tool 'Codex' -Skill 'skill-b')
    Assert-Equal 'Cursor/skill-a compat' 'covered_by_compatibility' (Get-SkillStatus -Report $report -Tool 'Cursor' -Skill 'skill-a')
    Assert-Equal 'Cursor/skill-b compat' 'covered_by_compatibility' (Get-SkillStatus -Report $report -Tool 'Cursor' -Skill 'skill-b')
    Assert-Equal 'OpenCode/skill-a missing' 'missing' (Get-SkillStatus -Report $report -Tool 'OpenCode' -Skill 'skill-a')
    Assert-Equal 'Antigravity/skill-a OK' 'OK' (Get-SkillStatus -Report $report -Tool 'Antigravity' -Skill 'skill-a')
    Assert-Equal 'Antigravity/skill-b missing' 'missing' (Get-SkillStatus -Report $report -Tool 'Antigravity' -Skill 'skill-b')
    Assert-Equal 'default strategy is compact' 'compact' ([string]$report.strategy)

    $script:cases++
    $orphanNames = @($report.orphans | ForEach-Object { $_.name })
    if ($orphanNames -contains 'skill-removida') {
        Write-Output 'PASS: orphan skill-removida detected'
    }
    else {
        $script:failures++
        Write-Output ("FAIL: orphan skill-removida not detected (orphans: {0})" -f ($orphanNames -join ','))
    }

    $script:cases++
    if ($report.overall -eq 'REGISTRATION_GAPS') {
        Write-Output 'PASS: overall REGISTRATION_GAPS'
    }
    else {
        $script:failures++
        Write-Output ("FAIL: overall expected REGISTRATION_GAPS, got {0}" -f $report.overall)
    }
}
finally {
    $env:PATH = $originalPath
    Restore-RealProfile
    foreach ($p in @($fakeProfile, $fakeRepo)) { Remove-TempTree -Path $p }
}

# Isolated case: only Cursor + skill only in .claude -> compat marks REGISTRATION_GAPS
$compatRepo = New-TempDir
$compatProfile = New-TempDir
$compatLocal = New-TempDir
$originalLocalAppData = $env:LOCALAPPDATA
try {
    $env:PATH = ''
    $env:LOCALAPPDATA = $compatLocal
    New-FakeSkill -SkillRepoRoot $compatRepo -Name 'skill-only' | Out-Null
    New-Junction -LinkDir (Join-Path $compatProfile '.claude/skills') -Name 'skill-only' -Target (Join-Path $compatRepo 'skill-only')
    New-Item -ItemType Directory -Path (Join-Path $compatProfile '.cursor') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $compatProfile '.cursor/mcp.json') -Value '{}' -Encoding utf8

    Set-FakeProfile $compatProfile
    $compatJson = & $scriptUnderTest -RepoRoot $compatRepo -AsJson | Out-String
    Restore-RealProfile
    $compatReport = $compatJson | ConvertFrom-Json

    Assert-Equal 'isolated: Cursor compat' 'covered_by_compatibility' (Get-SkillStatus -Report $compatReport -Tool 'Cursor' -Skill 'skill-only')
    Assert-Equal 'isolated: overall GAPS via compat' 'REGISTRATION_GAPS' ([string]$compatReport.overall)
    Assert-Equal 'isolated: missing 0' '0' ([string]$compatReport.summary.missing)
    Assert-Equal 'isolated: broken 0' '0' ([string]$compatReport.summary.broken)
    Assert-Equal 'isolated: orphans 0' '0' ([string]$compatReport.summary.orphans)
    $script:cases++
    if ([int]$compatReport.summary.coveredByCompat -ge 1) {
        Write-Output 'PASS: isolated: coveredByCompat >= 1'
    }
    else {
        $script:failures++
        Write-Output ("FAIL: isolated: coveredByCompat expected >= 1, got {0}" -f $compatReport.summary.coveredByCompat)
    }
}
finally {
    $env:PATH = $originalPath
    Restore-RealProfile
    $env:LOCALAPPDATA = $originalLocalAppData
    foreach ($p in @($compatProfile, $compatRepo, $compatLocal)) { Remove-TempTree -Path $p }
}

# Isolated case: native link in .cursor/skills -> Cursor OK and REGISTRATION_OK
$nativeRepo = New-TempDir
$nativeProfile = New-TempDir
$nativeLocal = New-TempDir
try {
    $env:PATH = ''
    $env:LOCALAPPDATA = $nativeLocal
    New-FakeSkill -SkillRepoRoot $nativeRepo -Name 'skill-only' | Out-Null
    New-Junction -LinkDir (Join-Path $nativeProfile '.cursor/skills') -Name 'skill-only' -Target (Join-Path $nativeRepo 'skill-only')
    New-Item -ItemType Directory -Path (Join-Path $nativeProfile '.cursor') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nativeProfile '.cursor/mcp.json') -Value '{}' -Encoding utf8

    Set-FakeProfile $nativeProfile
    $nativeJson = & $scriptUnderTest -RepoRoot $nativeRepo -AsJson | Out-String
    Restore-RealProfile
    $nativeReport = $nativeJson | ConvertFrom-Json

    Assert-Equal 'native: Cursor OK' 'OK' (Get-SkillStatus -Report $nativeReport -Tool 'Cursor' -Skill 'skill-only')
    Assert-Equal 'native: overall OK' 'REGISTRATION_OK' ([string]$nativeReport.overall)
    Assert-Equal 'native: coveredByCompat 0' '0' ([string]$nativeReport.summary.coveredByCompat)
}
finally {
    $env:PATH = $originalPath
    Restore-RealProfile
    $env:LOCALAPPDATA = $originalLocalAppData
    foreach ($p in @($nativeProfile, $nativeRepo, $nativeLocal)) { Remove-TempTree -Path $p }
}

# Isolated case: Cursor installed against the real skills inventory, both with inferred
# RepoRoot and with an explicit skills-root RepoRoot. The audit covers skill registration
# only: an unrelated MCP server folder under ~/.cursor is ignored, and the report carries
# no MCP section.
$mcpRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$mcpSkillsRoot = (Resolve-Path -LiteralPath (Join-Path $mcpRepoRoot 'skills')).Path

$realSkillDirs = @(
    Get-ChildItem -LiteralPath $mcpSkillsRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        Sort-Object Name
)
$realSkillNames = @($realSkillDirs | ForEach-Object { $_.Name })
$mcpProfile = New-TempDir
try {
    $env:PATH = ''
    $cursorRoot = Join-Path $mcpProfile '.cursor'
    New-Item -ItemType Directory -Path (Join-Path $cursorRoot 'rules') -Force | Out-Null
    # An unrelated MCP server folder with no config or registration.
    $strayMcpDir = Join-Path $cursorRoot 'sample-mcp-server'
    New-Item -ItemType Directory -Path $strayMcpDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $strayMcpDir 'server.py') -Value '# stale' -Encoding utf8

    foreach ($skillDir in $realSkillDirs) {
        New-Junction -LinkDir (Join-Path $cursorRoot 'skills') -Name $skillDir.Name -Target $skillDir.FullName
    }

    Set-FakeProfile $mcpProfile
    $defaultJson = & $scriptUnderTest -AsJson | Out-String
    $defaultReport = $defaultJson | ConvertFrom-Json
    $explicitJson = & $scriptUnderTest -RepoRoot $mcpSkillsRoot -AsJson | Out-String
    $explicitReport = $explicitJson | ConvertFrom-Json
    $humanText = & $scriptUnderTest -RepoRoot $mcpSkillsRoot | Out-String

    $reports = @(
        [pscustomobject]@{ Name = 'real inventory default'; Report = $defaultReport }
        [pscustomobject]@{ Name = 'real inventory explicit RepoRoot'; Report = $explicitReport }
    )
    foreach ($run in $reports) {
        $prefix = $run.Name
        $report = $run.Report
        Assert-Equal ("{0}: repoRoot is skills root" -f $prefix) $mcpSkillsRoot ([string]$report.repoRoot)
        Assert-Equal ("{0}: real skills inventory" -f $prefix) ($realSkillNames -join ',') (@($report.skillsInventory) -join ',')
        Assert-Equal ("{0}: Cursor native skill registrations" -f $prefix) (@($realSkillNames | ForEach-Object { '{0}=OK' -f $_ }) -join ',') (@($report.tools | Where-Object { $_.name -eq 'Cursor' } | ForEach-Object { $_.skills } | ForEach-Object { '{0}={1}' -f $_.name, $_.status }) -join ',')
        Assert-Equal ("{0}: no registration gaps" -f $prefix) '0/0/0/0' ('{0}/{1}/{2}/{3}' -f $report.summary.missing, $report.summary.broken, $report.summary.coveredByCompat, $report.summary.orphans)
        Assert-Equal ("{0}: no MCP section in the report" -f $prefix) 'False' ([string]($null -ne $report.PSObject.Properties['cursorMcp']))
        Assert-Equal ("{0}: no MCP field in the summary" -f $prefix) 'False' ([string]($null -ne $report.summary.PSObject.Properties['cursorMcp']))
        Assert-Equal ("{0}: overall ignores the stray MCP folder" -f $prefix) 'REGISTRATION_OK' ([string]$report.overall)
    }
    Assert-Equal 'real inventory human output: no MCP line' 'False' ([string]($humanText -match 'Cursor MCP'))
}
finally {
    $env:PATH = $originalPath
    Restore-RealProfile
    Remove-TempTree -Path $mcpProfile
}

# Isolated cases: -AdditionalSkillsRoot (generic tool support). No built-in tool is
# installed in the fake profile, so only the user-declared roots are audited.
$addRepo = New-TempDir
$addProfile = New-TempDir
try {
    $env:PATH = ''
    New-FakeSkill -SkillRepoRoot $addRepo -Name 'skill-a' | Out-Null
    New-FakeSkill -SkillRepoRoot $addRepo -Name 'skill-b' | Out-Null
    New-FakeSkill -SkillRepoRoot $addRepo -Name 'skill-gone' -WithoutSkillMd | Out-Null

    # Custom root (home-relative) with both skills linked
    New-Junction -LinkDir (Join-Path $addProfile 'custom/skills') -Name 'skill-a' -Target (Join-Path $addRepo 'skill-a')
    New-Junction -LinkDir (Join-Path $addProfile 'custom/skills') -Name 'skill-b' -Target (Join-Path $addRepo 'skill-b')
    # Absolute custom root with only skill-a linked
    $partialRoot = Join-Path $addProfile 'partial-abs'
    New-Junction -LinkDir $partialRoot -Name 'skill-a' -Target (Join-Path $addRepo 'skill-a')
    Set-FakeProfile $addProfile

    # Default: no parameter -> no custom entries, nothing installed
    $defReport = (& $scriptUnderTest -RepoRoot $addRepo -AsJson | Out-String) | ConvertFrom-Json
    Assert-Equal 'additional: default has no Custom tools' '0' ([string]@($defReport.tools | Where-Object { $_.name -like 'Custom:*' }).Count)
    Assert-Equal 'additional: default tool count unchanged' '5' ([string]@($defReport.tools).Count)
    Assert-Equal 'additional: default overall OK (no tools installed)' 'REGISTRATION_OK' ([string]$defReport.overall)

    # Custom root with every skill linked -> OK
    $okReport = (& $scriptUnderTest -RepoRoot $addRepo -AdditionalSkillsRoot 'custom/skills' -AsJson | Out-String) | ConvertFrom-Json
    $okTool = @($okReport.tools | Where-Object { $_.name -like 'Custom:*' })
    Assert-Equal 'additional: one Custom tool' '1' ([string]$okTool.Count)
    Assert-Equal 'additional: Custom tool installed' 'True' ([string]$okTool[0].installed)
    Assert-Equal 'additional: native is resolved under profile' ([System.IO.Path]::Combine($addProfile, 'custom', 'skills')) ([string]@($okTool[0].native)[0])
    Assert-Equal 'additional: skill-a OK' 'OK' (Get-SkillStatus -Report $okReport -Tool $okTool[0].name -Skill 'skill-a')
    Assert-Equal 'additional: skill-b OK' 'OK' (Get-SkillStatus -Report $okReport -Tool $okTool[0].name -Skill 'skill-b')
    Assert-Equal 'additional: overall OK' 'REGISTRATION_OK' ([string]$okReport.overall)

    # Absolute root missing one skill -> missing and GAPS
    $gapReport = (& $scriptUnderTest -RepoRoot $addRepo -AdditionalSkillsRoot $partialRoot -AsJson | Out-String) | ConvertFrom-Json
    $gapTool = @($gapReport.tools | Where-Object { $_.name -like 'Custom:*' })
    Assert-Equal 'additional: absolute root skill-a OK' 'OK' (Get-SkillStatus -Report $gapReport -Tool $gapTool[0].name -Skill 'skill-a')
    Assert-Equal 'additional: absolute root skill-b missing' 'missing' (Get-SkillStatus -Report $gapReport -Tool $gapTool[0].name -Skill 'skill-b')
    Assert-Equal 'additional: missing skill -> GAPS' 'REGISTRATION_GAPS' ([string]$gapReport.overall)

    # Nonexistent root -> all missing, GAPS, no crash
    $noneReport = (& $scriptUnderTest -RepoRoot $addRepo -AdditionalSkillsRoot 'does\not\exist' -AsJson | Out-String) | ConvertFrom-Json
    $noneTool = @($noneReport.tools | Where-Object { $_.name -like 'Custom:*' })
    Assert-Equal 'additional: nonexistent root skill-a missing' 'missing' (Get-SkillStatus -Report $noneReport -Tool $noneTool[0].name -Skill 'skill-a')
    Assert-Equal 'additional: nonexistent root -> GAPS' 'REGISTRATION_GAPS' ([string]$noneReport.overall)

    # .agents\skills passed as custom: orphan (points to the repo, not in inventory)
    # is counted once, not twice
    New-Junction -LinkDir (Join-Path $addProfile '.agents/skills') -Name 'skill-gone' -Target (Join-Path $addRepo 'skill-gone')
    $dupReport = (& $scriptUnderTest -RepoRoot $addRepo -AdditionalSkillsRoot '.agents\skills' -AsJson | Out-String) | ConvertFrom-Json
    Assert-Equal 'additional: .agents\skills orphan not double counted' '1' ([string]$dupReport.summary.orphans)
}
finally {
    $env:PATH = $originalPath
    Restore-RealProfile
    foreach ($p in @($addProfile, $addRepo)) { Remove-TempTree -Path $p }
}

# Isolated cases: profile resolution. HOME alone is enough (Linux and macOS have no
# USERPROFILE), and with neither variable set the audit stops with a clear BLOCK.
$homeRepo = New-TempDir
$homeProfile = New-TempDir
try {
    $env:PATH = ''
    New-FakeSkill -SkillRepoRoot $homeRepo -Name 'skill-only' | Out-Null
    New-Junction -LinkDir (Join-Path $homeProfile '.claude/skills') -Name 'skill-only' -Target (Join-Path $homeRepo 'skill-only')
    Set-Content -LiteralPath (Join-Path $homeProfile '.claude/settings.json') -Value '{}' -Encoding utf8

    $env:USERPROFILE = $null
    $env:HOME = $homeProfile
    $homeReport = $null
    $homeError = ''
    try {
        $homeReport = (& $scriptUnderTest -RepoRoot $homeRepo -AsJson | Out-String) | ConvertFrom-Json
    }
    catch {
        $homeError = $_.Exception.Message
    }
    Restore-RealProfile
    Assert-Equal 'HOME only: no error' '' $homeError
    Assert-Equal 'HOME only: Claude skill OK' 'OK' $(if ($homeReport) { Get-SkillStatus -Report $homeReport -Tool 'ClaudeCode' -Skill 'skill-only' } else { '<no-report>' })
    Assert-Equal 'HOME only: Claude native dir under HOME' ([System.IO.Path]::Combine($homeProfile, '.claude', 'skills')) $(if ($homeReport) { [string]@(@($homeReport.tools | Where-Object { $_.name -eq 'ClaudeCode' })[0].native)[0] } else { '<no-report>' })

    Set-FakeProfile $null
    $blockError = ''
    try {
        $null = & $scriptUnderTest -RepoRoot $homeRepo -AsJson
    }
    catch {
        $blockError = $_.Exception.Message
    }
    Restore-RealProfile
    Assert-Equal 'no profile variable: BLOCK raised' 'True' ([string]($blockError -match '^BLOCK: .*HOME.*USERPROFILE'))
}
finally {
    $env:PATH = $originalPath
    Restore-RealProfile
    foreach ($p in @($homeProfile, $homeRepo)) { Remove-TempTree -Path $p }
}

# Isolated cases: links the user chose not to create. -SkipTool and -SkipSkill turn
# what would be missing or covered_by_compatibility into skipped_by_choice, which is
# not a gap; a broken link stays broken; an unknown name stops with a BLOCK.
$skipRepo = New-TempDir
$skipProfile = New-TempDir
try {
    $env:PATH = ''
    New-FakeSkill -SkillRepoRoot $skipRepo -Name 'skill-a' | Out-Null
    New-FakeSkill -SkillRepoRoot $skipRepo -Name 'skill-b' | Out-Null
    # Claude Code and Codex installed with skill-a only; Cursor installed with no native link.
    New-Junction -LinkDir (Join-Path $skipProfile '.claude/skills') -Name 'skill-a' -Target (Join-Path $skipRepo 'skill-a')
    Set-Content -LiteralPath (Join-Path $skipProfile '.claude/settings.json') -Value '{}' -Encoding utf8
    New-Junction -LinkDir (Join-Path $skipProfile '.codex/skills') -Name 'skill-a' -Target (Join-Path $skipRepo 'skill-a')
    Set-Content -LiteralPath (Join-Path $skipProfile '.codex/config.toml') -Value '' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $skipProfile '.cursor') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skipProfile '.cursor/mcp.json') -Value '{}' -Encoding utf8
    Set-FakeProfile $skipProfile

    $noSkip = (& $scriptUnderTest -RepoRoot $skipRepo -AsJson | Out-String) | ConvertFrom-Json
    Assert-Equal 'skip: without declared skips the audit reports gaps' 'REGISTRATION_GAPS' ([string]$noSkip.overall)

    $skipError = ''
    $skipReport = $null
    try {
        $skipReport = (& $scriptUnderTest -RepoRoot $skipRepo -SkipTool 'cursor' -SkipSkill 'skill-b' -AsJson | Out-String) | ConvertFrom-Json
    }
    catch { $skipError = $_.Exception.Message }
    Assert-Equal 'skip: declared skips run without error' '' $skipError
    if ($skipReport) {
        Assert-Equal 'skip: Cursor/skill-a skipped by choice' 'skipped_by_choice' (Get-SkillStatus -Report $skipReport -Tool 'Cursor' -Skill 'skill-a')
        Assert-Equal 'skip: Cursor/skill-b skipped by choice' 'skipped_by_choice' (Get-SkillStatus -Report $skipReport -Tool 'Cursor' -Skill 'skill-b')
        Assert-Equal 'skip: Claude/skill-a still OK' 'OK' (Get-SkillStatus -Report $skipReport -Tool 'ClaudeCode' -Skill 'skill-a')
        Assert-Equal 'skip: Claude/skill-b skipped by choice' 'skipped_by_choice' (Get-SkillStatus -Report $skipReport -Tool 'ClaudeCode' -Skill 'skill-b')
        Assert-Equal 'skip: Codex/skill-b skipped by choice' 'skipped_by_choice' (Get-SkillStatus -Report $skipReport -Tool 'Codex' -Skill 'skill-b')
        Assert-Equal 'skip: declared skips alone are not a gap' 'REGISTRATION_OK' ([string]$skipReport.overall)
        Assert-Equal 'skip: summary counts skipped by choice' '4' ([string]$skipReport.summary.skippedByChoice)
        Assert-Equal 'skip: summary missing 0' '0' ([string]$skipReport.summary.missing)
        Assert-Equal 'skip: summary coveredByCompat 0' '0' ([string]$skipReport.summary.coveredByCompat)
        Assert-Equal 'skip: Cursor flagged skippedByChoice' 'True' ([string](@($skipReport.tools | Where-Object { $_.name -eq 'Cursor' })[0].skippedByChoice))
        Assert-Equal 'skip: report lists the declared tools' 'Cursor' (@($skipReport.skippedByChoice.tools) -join ',')
        Assert-Equal 'skip: report lists the declared skills' 'skill-b' (@($skipReport.skippedByChoice.skills) -join ',')
    }
    $skipText = & $scriptUnderTest -RepoRoot $skipRepo -SkipTool 'Cursor' -SkipSkill 'skill-b' | Out-String
    Assert-Equal 'skip: text output names skipped by choice' 'True' ([string]($skipText -match 'skipped by choice'))
    Assert-Equal 'skip: text output overall OK' 'True' ([string]($skipText -match 'OVERALL: REGISTRATION_OK'))

    # A broken link stays a gap even in a skipped tool.
    $brokenSkipTarget = Join-Path $skipProfile 'gone'
    New-Item -ItemType Directory -Path $brokenSkipTarget -Force | Out-Null
    New-Junction -LinkDir (Join-Path $skipProfile '.cursor/skills') -Name 'skill-a' -Target $brokenSkipTarget
    Remove-Item -LiteralPath $brokenSkipTarget -Recurse -Force
    $brokenSkip = (& $scriptUnderTest -RepoRoot $skipRepo -SkipTool 'Cursor' -SkipSkill 'skill-b' -AsJson | Out-String) | ConvertFrom-Json
    Assert-Equal 'skip: broken link in a skipped tool stays broken' 'broken' (Get-SkillStatus -Report $brokenSkip -Tool 'Cursor' -Skill 'skill-a')
    Assert-Equal 'skip: broken link in a skipped tool is a gap' 'REGISTRATION_GAPS' ([string]$brokenSkip.overall)

    foreach ($badArgs in @(@{ SkipTool = 'NoSuchTool' }, @{ SkipSkill = 'no-such-skill' })) {
        $badError = ''
        try { $null = & $scriptUnderTest -RepoRoot $skipRepo @badArgs -AsJson }
        catch { $badError = $_.Exception.Message }
        Assert-Equal ("skip: unknown name {0} raises BLOCK" -f (@($badArgs.Values) -join '')) 'True' ([string]($badError -match '^BLOCK: '))
    }

    # Exit contract as a child process (pwsh -File): REGISTRATION_GAPS exits 0 with
    # its JSON; an unknown skip name exits non-zero with BLOCK on stderr and no stdout.
    # PATH is empty in this block, so the child runs through this process's own pwsh.
    $pwshExe = [System.Environment]::ProcessPath
    $childErrPath = Join-Path $skipRepo 'child-stderr.txt'
    $gapOut = & $pwshExe -NoProfile -NonInteractive -File $scriptUnderTest -RepoRoot $skipRepo -AsJson 2> $childErrPath
    $gapExit = $LASTEXITCODE
    Assert-Equal 'exit: REGISTRATION_GAPS exits 0 as a child process' '0' ([string]$gapExit)
    Assert-Equal 'exit: REGISTRATION_GAPS child prints its JSON' 'REGISTRATION_GAPS' ([string](($gapOut | Out-String) | ConvertFrom-Json).overall)
    foreach ($badArgs in @(@('-SkipTool', 'NoSuchTool'), @('-SkipSkill', 'no-such-skill'))) {
        $label = $badArgs -join ' '
        $badOut = & $pwshExe -NoProfile -NonInteractive -File $scriptUnderTest -RepoRoot $skipRepo @badArgs -AsJson 2> $childErrPath
        $badExit = $LASTEXITCODE
        $badErr = ([System.IO.File]::ReadAllText($childErrPath)) -replace "`e\[[0-9;?]*[A-Za-z]", ''
        Assert-Equal ("exit: {0} exits non-zero as a child process" -f $label) 'True' ([string]($badExit -ne 0))
        Assert-Equal ("exit: {0} writes BLOCK on stderr" -f $label) 'True' ([string]($badErr -match ('BLOCK: unknown {0} name' -f $badArgs[0])))
        Assert-Equal ("exit: {0} writes nothing on stdout" -f $label) '' ((@($badOut) | Out-String).Trim())
    }
}
finally {
    $env:PATH = $originalPath
    Restore-RealProfile
    foreach ($p in @($skipProfile, $skipRepo)) { Remove-TempTree -Path $p }
}

Write-Output '---'
if ($failures -eq 0) {
    Write-Output ("SELFTEST_OK: {0}/{0} cases passed" -f $cases)
    exit 0
}
else {
    Write-Output ("SELFTEST_FAIL: {0} of {1} cases failed" -f $failures, $cases)
    exit 1
}
