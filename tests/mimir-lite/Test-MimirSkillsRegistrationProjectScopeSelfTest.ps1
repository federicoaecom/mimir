#requires -Version 7.4

<#
.SYNOPSIS
    Self-test for the project scope of Test-MimirSkillsRegistration.ps1.

.DESCRIPTION
    Builds a fake skills root, a fake user profile, and a fake project folder in a temporary
    folder (junctions on Windows, symbolic links elsewhere; no network, PATH emptied so no real
    CLI is detected). Claude Code and Codex are marked installed in the fake profile. Proves that:
      - -Scope Project -ProjectRoot <dir> audits the project's skills folders: Claude Code at
        <project>/.claude/skills and Codex at <project>/.agents/skills, both OK gives
        REGISTRATION_OK, and the result carries scope "project" and the projectRoot;
      - a missing project link is a gap (missing, REGISTRATION_GAPS);
      - a link to the same skill at user level is reported in userScopeAlsoRegistered (tool,
        skill, path), since Claude Code prefers a personal skill over a project one; it is a
        warning, not a gap;
      - a project link to a repository folder outside the inventory is an orphan in the
        project folder;
      - -Scope Project without -ProjectRoot, -ProjectRoot without -Scope Project, and a
        -ProjectRoot that does not exist stop with BLOCK;
      - in project scope, an -AdditionalSkillsRoot starting with ~/ still resolves against the
        profile, and a relative one against the project;
      - a Codex link at the profile's .agents/skills is reported in userScopeAlsoRegistered, and a
        tool skipped by choice is not;
      - the project-scope text output names the scope and lists the user-level duplicates;
      - the default (user) scope still audits the profile, reports scope "user", and its text
        output has no scope line, as before the project scope existed.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptUnderTest = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Test-MimirSkillsRegistration.ps1'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { $failures.Add($Message) }

function New-TempDir {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-regproject-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function New-Link {
    param([string]$LinkDir, [string]$Name, [string]$Target)
    if (-not (Test-Path -LiteralPath $LinkDir -PathType Container)) { New-Item -ItemType Directory -Path $LinkDir -Force | Out-Null }
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path (Join-Path $LinkDir $Name) -Target $Target | Out-Null
}

function Remove-TempTree {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $links = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.LinkType } | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($link in $links) { try { $link.Delete() } catch { try { [System.IO.File]::Delete($link.FullName) } catch { } } }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-Audit {
    param([hashtable]$Arguments)
    return (& $scriptUnderTest -RepoRoot $fakeRepo @Arguments -AsJson | Out-String | ConvertFrom-Json)
}

function Get-SkillStatus($Report, [string]$Tool, [string]$Skill) {
    $t = @($Report.tools | Where-Object { $_.name -eq $Tool })
    if ($t.Count -eq 0) { return '<tool-missing>' }
    $s = @($t[0].skills | Where-Object { $_.name -eq $Skill })
    if ($s.Count -eq 0) { return '<skill-missing>' }
    return $s[0].status
}

$fakeRepo = New-TempDir
$fakeProfile = New-TempDir
$project = New-TempDir
$originalProfile = $env:USERPROFILE
$originalHome = $env:HOME
$originalPath = $env:PATH
try {
    $env:PATH = ''
    $env:USERPROFILE = $fakeProfile
    $env:HOME = $fakeProfile
    foreach ($name in @('skill-a', 'skill-b')) {
        New-Item -ItemType Directory -Path (Join-Path $fakeRepo $name) -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fakeRepo "$name/SKILL.md") -Value "# $name" -Encoding utf8
    }
    New-Item -ItemType Directory -Path (Join-Path $fakeRepo 'skill-old') -Force | Out-Null
    # Claude Code and Codex installed (profile markers).
    New-Item -ItemType Directory -Path (Join-Path $fakeProfile '.claude'), (Join-Path $fakeProfile '.codex') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fakeProfile '.claude/settings.json') -Value '{}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $fakeProfile '.codex/config.toml') -Value '' -Encoding utf8

    $projectClaude = Join-Path $project '.claude/skills'
    $projectAgents = Join-Path $project '.agents/skills'
    New-Link -LinkDir $projectClaude -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')
    New-Link -LinkDir $projectAgents -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')
    $base = @{ Scope = 'Project'; ProjectRoot = $project; OnlyTool = @('ClaudeCode', 'Codex') }

    # 1: both project links -> OK, scope and root reported.
    $r = Invoke-Audit -Arguments ($base + @{ SkipSkill = @('skill-b') })
    if ($r.overall -cne 'REGISTRATION_OK') { Add-Failure "[1] overall should be REGISTRATION_OK; got $($r.overall)" }
    if ($null -eq $r.PSObject.Properties['scope'] -or $r.scope -cne 'project') { Add-Failure "[1] scope should be 'project'; got '$($r | Select-Object -ExpandProperty scope -ErrorAction SilentlyContinue)'" }
    if ($null -eq $r.PSObject.Properties['projectRoot'] -or (Resolve-Path -LiteralPath $r.projectRoot).Path -ne (Resolve-Path -LiteralPath $project).Path) { Add-Failure "[1] projectRoot should be the project folder" }
    foreach ($pair in @(@('ClaudeCode', $projectClaude), @('Codex', $projectAgents))) {
        if ((Get-SkillStatus $r $pair[0] 'skill-a') -cne 'OK') { Add-Failure "[1] $($pair[0]) skill-a should be OK; got $(Get-SkillStatus $r $pair[0] 'skill-a')" }
        $native = @(@($r.tools | Where-Object { $_.name -eq $pair[0] })[0].native)
        if (-not (@($native | ForEach-Object { [System.IO.Path]::GetFullPath($_) }) -contains [System.IO.Path]::GetFullPath($pair[1]))) { Add-Failure "[1] $($pair[0]) native folders should include $($pair[1]); got $($native -join ', ')" }
    }
    if (@($r.userScopeAlsoRegistered).Count -ne 0) { Add-Failure "[1] userScopeAlsoRegistered should be empty; got $(@($r.userScopeAlsoRegistered).Count)" }

    # 2: skill-b has no project link -> missing, gaps.
    $r = Invoke-Audit -Arguments $base
    if ($r.overall -cne 'REGISTRATION_GAPS' -or (Get-SkillStatus $r 'ClaudeCode' 'skill-b') -cne 'missing') { Add-Failure "[2] skill-b should be missing with REGISTRATION_GAPS; got $($r.overall), $(Get-SkillStatus $r 'ClaudeCode' 'skill-b')" }

    # 3: skill-a also linked at user level -> reported, not a gap.
    New-Link -LinkDir (Join-Path $fakeProfile '.claude/skills') -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')
    $r = Invoke-Audit -Arguments ($base + @{ SkipSkill = @('skill-b') })
    $also = @($r.userScopeAlsoRegistered | ForEach-Object { '{0}:{1}' -f $_.tool, $_.skill })
    if (($also -join ';') -cne 'ClaudeCode:skill-a') { Add-Failure "[3] userScopeAlsoRegistered should be 'ClaudeCode:skill-a'; got '$($also -join ';')'" }
    if ($r.overall -cne 'REGISTRATION_OK') { Add-Failure "[3] a user-level duplicate is a warning, not a gap; got $($r.overall)" }

    # 4: a project link to a repository folder outside the inventory -> orphan in the project.
    New-Link -LinkDir $projectClaude -Name 'skill-old' -Target (Join-Path $fakeRepo 'skill-old')
    $r = Invoke-Audit -Arguments ($base + @{ SkipSkill = @('skill-b') })
    $orphans = @($r.orphans | Where-Object { $_.name -eq 'skill-old' })
    if ($orphans.Count -ne 1 -or [System.IO.Path]::GetFullPath($orphans[0].dir) -ne [System.IO.Path]::GetFullPath($projectClaude)) { Add-Failure "[4] skill-old should be one orphan in $projectClaude; got $(@($r.orphans | ForEach-Object { "$($_.dir)/$($_.name)" }) -join ', ')" }

    # 5: invalid parameter combinations stop with BLOCK.
    foreach ($bad in @(
            @{ Label = 'Project without root'; Args = @{ Scope = 'Project' } },
            @{ Label = 'root without Project'; Args = @{ ProjectRoot = $project } },
            @{ Label = 'missing root'; Args = @{ Scope = 'Project'; ProjectRoot = (Join-Path $project 'nope') } }
        )) {
        $threw = $false
        $badArgs = $bad.Args
        try { & $scriptUnderTest -RepoRoot $fakeRepo @badArgs -AsJson | Out-Null } catch { $threw = "$_" -match 'BLOCK' }
        if (-not $threw) { Add-Failure "[5] $($bad.Label) should stop with BLOCK" }
    }

    # 6: -AdditionalSkillsRoot: ~/ is the profile, a relative path is the project.
    New-Link -LinkDir (Join-Path $fakeProfile '.extra/skills') -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')
    New-Link -LinkDir (Join-Path $project '.local/skills') -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')
    $r = Invoke-Audit -Arguments ($base + @{ SkipSkill = @('skill-b'); AdditionalSkillsRoot = @('~/.extra/skills', '.local/skills') })
    if ((Get-SkillStatus $r 'Custom:~/.extra/skills' 'skill-a') -cne 'OK') { Add-Failure "[6] ~/.extra/skills should resolve against the profile (OK); got $(Get-SkillStatus $r 'Custom:~/.extra/skills' 'skill-a')" }
    if ((Get-SkillStatus $r 'Custom:.local/skills' 'skill-a') -cne 'OK') { Add-Failure "[6] .local/skills should resolve against the project (OK); got $(Get-SkillStatus $r 'Custom:.local/skills' 'skill-a')" }

    # 7: a Codex link at the profile's .agents/skills is reported; a skipped tool is not.
    New-Link -LinkDir (Join-Path $fakeProfile '.agents/skills') -Name 'skill-a' -Target (Join-Path $fakeRepo 'skill-a')
    $r = Invoke-Audit -Arguments ($base + @{ SkipSkill = @('skill-b') })
    $also = @($r.userScopeAlsoRegistered | ForEach-Object { '{0}:{1}' -f $_.tool, $_.skill }) | Sort-Object
    if (($also -join ';') -cne 'ClaudeCode:skill-a;Codex:skill-a') { Add-Failure "[7] userScopeAlsoRegistered should be 'ClaudeCode:skill-a;Codex:skill-a'; got '$($also -join ';')'" }
    $r = Invoke-Audit -Arguments @{ Scope = 'Project'; ProjectRoot = $project; OnlyTool = @('ClaudeCode'); SkipSkill = @('skill-b') }
    $also = @($r.userScopeAlsoRegistered | ForEach-Object { '{0}:{1}' -f $_.tool, $_.skill })
    if (($also -join ';') -cne 'ClaudeCode:skill-a') { Add-Failure "[7] a tool skipped by choice should not be in userScopeAlsoRegistered; got '$($also -join ';')'" }

    # 8: the project-scope text output names the scope and lists the user-level duplicates.
    $text = (& $scriptUnderTest -RepoRoot $fakeRepo @base -SkipSkill skill-b | Out-String)
    if ($text -notmatch '(?m)^Scope: project \(') { Add-Failure "[8] the text output should have a 'Scope: project (...)' line" }
    if ($text -notmatch '(?ms)^Also registered at user level.*^\s+\[Codex\] skill-a ') { Add-Failure "[8] the text output should list the user-level duplicates, Codex included" }

    # 9: the default scope audits the profile (skill-a is linked at user level since case 3) and
    # its text output has no scope line.
    $r = Invoke-Audit -Arguments @{ OnlyTool = @('ClaudeCode'); SkipSkill = @('skill-b') }
    if ($r.scope -cne 'user') { Add-Failure "[9] the default scope should be 'user'; got '$($r.scope)'" }
    if ((Get-SkillStatus $r 'ClaudeCode' 'skill-a') -cne 'OK') { Add-Failure "[9] user-level skill-a should be OK; got $(Get-SkillStatus $r 'ClaudeCode' 'skill-a')" }
    $text = (& $scriptUnderTest -RepoRoot $fakeRepo -OnlyTool ClaudeCode -SkipSkill skill-b | Out-String)
    if ($text -match '(?m)^Scope:') { Add-Failure "[9] the user-scope text output should have no scope line" }
}
finally {
    $env:USERPROFILE = $originalProfile
    $env:HOME = $originalHome
    $env:PATH = $originalPath
    foreach ($dir in @($fakeRepo, $fakeProfile, $project)) { Remove-TempTree -Path $dir }
}

if ($failures.Count -gt 0) {
    throw ("Test-MimirSkillsRegistrationProjectScopeSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-MimirSkillsRegistrationProjectScopeSelfTest.ps1'
exit 0
