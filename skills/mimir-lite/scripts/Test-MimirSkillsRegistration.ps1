#requires -Version 7.4

<#
.SYNOPSIS
    Deterministic audit of the global registration of the XPZ skills across the
    installed agent tools.

.DESCRIPTION
    Mechanizes the inventory, install-detection, and classification steps of the
    install workflow. Does NOT create or remove links: it only audits and
    classifies. Resolution actions remain the agent's responsibility, after the
    user's explicit confirmation.

    Classification per skill x installed tool:
      OK                        valid link in the tool's native directory
      covered_by_compatibility  valid link found only in a compatibility-read directory
      missing                   no valid link found
      broken                    link present, but the target does not exist
      skipped_by_choice         no link, and the user declared that tool or skill
                                not linked by choice (-SkipTool / -SkipSkill)
      opaque_copy               a real folder (not a link) where a link should be
      stale_source              valid link, but the target != the current preferred source

    Special rules (mirror skills/mimir-lite/workflows/install.md):
      - Codex indexes TWO USER scopes (.codex/skills and .agents/skills); presence
        in either one counts as OK.
      - OpenCode requires a native link (.config/opencode/skills or .agents/skills);
        it does not count compatibility with .claude/skills.
      - Cursor: native is mandatory only at ~/.cursor/skills; .agents/.claude/.codex
        are compat, and covered_by_compatibility flags REGISTRATION_GAPS.

    Other tools: -AdditionalSkillsRoot audits any extra skills directory (one
    entry per directory, named "Custom:<path as given>"). Each one is treated as an
    installed tool declared by the user, with that directory as its only native
    location and no compatibility locations. A relative path is resolved against the
    user profile (a leading "~" also means the profile); an absolute path is used
    as is. The directory does not need to exist: a missing one reports every skill
    as missing. The directory also joins the orphan scan, deduplicated by canonical
    path with the built-in ones.

    Orphans: links under a skills directory whose target points INSIDE the XPZ
    skills repository, but whose name is no longer in the root inventory. Links to
    other repositories do not count as orphans of the XPZ repo.

.PARAMETER AdditionalSkillsRoot
    Extra skills directories to audit for tools without built-in support
    (for example ~/.agents/skills, or another tool's own skills directory).
    Relative paths resolve against the user profile; absolute paths are used as is.

.PARAMETER SkipTool
    Tools the user chose not to link, by their tools[].name (for example Cursor,
    or Custom:<dir> as given to -AdditionalSkillsRoot); case-insensitive. A skill
    that would be missing or covered_by_compatibility in such a tool is reported
    skipped_by_choice, which is not a gap; an OK or broken link keeps its status.
    An unknown name stops with BLOCK. Several names may be given as a
    comma-separated list (-SkipTool Codex,OpenCode), which also works under
    pwsh -File, where the list arrives as one string.

.PARAMETER OnlyTool
    The tools the user chose to link, by their tools[].name, as the opposite of
    -SkipTool: every built-in tool not listed is reported exactly as if it had been
    passed to -SkipTool. Same name rule and comma-separated lists; an unknown name
    stops with BLOCK, and so does combining it with -SkipTool. -SkipSkill still
    applies, and every -AdditionalSkillsRoot entry stays audited.

.PARAMETER SkipSkill
    Skills the user chose not to link in any tool (for example mimir-delegate);
    same rule as -SkipTool. A name outside the skills inventory stops with BLOCK.

.OUTPUTS
    Human-readable text by default; a JSON object with -AsJson. The "overall" and
    "label" fields are meant for agent interpretation.

.NOTES
    Exit codes when run with pwsh -File:
      0  the audit ran; "overall" is REGISTRATION_OK or REGISTRATION_GAPS (gaps
         are reported in the output, not through the exit code).
      1  the audit did not run. A BLOCK (unknown -SkipTool, -OnlyTool or
         -SkipSkill name, -OnlyTool combined with -SkipTool, repository root not
         inferable, no user profile directory) writes its
         message, starting with "BLOCK:", to stderr; any other terminating
         error (for example a -RepoRoot that does not exist) also exits 1.
         Stdout stays empty in both cases (no JSON, even with -AsJson).
#>

[CmdletBinding()]
param(
    [string]$RepoRoot,

    [ValidateSet('compact', 'expansive')]
    [string]$Strategy = 'compact',

    [string[]]$AdditionalSkillsRoot = @(),

    [string[]]$SkipTool = @(),

    [string[]]$OnlyTool = @(),

    [string[]]$SkipSkill = @(),

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -Name MimirNativeLong -Namespace Mimir -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern uint GetLongPathName(string lpszShortPath, System.Text.StringBuilder lpszLongPath, uint cchBuffer);
'@ -ErrorAction SilentlyContinue | Out-Null

function ConvertTo-LongPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    try {
        $sb = New-Object System.Text.StringBuilder 1024
        $n = [Mimir.MimirNativeLong]::GetLongPathName($Path, $sb, [uint32]1024)
        if ($n -gt 0 -and $n -lt 1024) { return $sb.ToString() }
    }
    catch { }
    return $Path
}

function Resolve-RepoRoot {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'BLOCK: could not infer the repository root from PSScriptRoot.'
    }
    # This engine lives at <skills-root>/mimir-lite/scripts/. The skills root
    # (parent of every skill folder, e.g. mimir-lite, mimir-delegate) is two
    # levels up, not one: <scripts> -> <mimir-lite> -> <skills-root>.
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).Path
}

function Get-ProfileRoot {
    # The user's home directory: USERPROFILE first on Windows, HOME first elsewhere
    # (Linux and macOS have no USERPROFILE); the other variable is the fallback.
    $candidates = if ($IsWindows) { @($env:USERPROFILE, $env:HOME) } else { @($env:HOME, $env:USERPROFILE) }
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate }
    }
    throw 'BLOCK: user profile directory not found (neither HOME nor USERPROFILE is set).'
}

function Join-ProfilePath {
    # Joins a home-relative path written with either separator ("\" or "/") using
    # the platform's separator, so the same literal works on every OS.
    param([string]$ProfileRoot, [string]$RelativePath)
    $parts = @($RelativePath -split '[\\/]' | Where-Object { $_ -ne '' })
    return [System.IO.Path]::Combine([string[]](@($ProfileRoot) + $parts))
}

function Resolve-SkillsDir {
    # Home-relative (optionally "~"-prefixed) or absolute skills directory -> absolute path.
    param([string]$ProfileRoot, [string]$Path)
    if ($Path -eq '~') { return $ProfileRoot }
    if ($Path -match '^~[\\/]') { $Path = $Path.Substring(2) }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-ProfilePath -ProfileRoot $ProfileRoot -RelativePath $Path
}

function Test-UsableCliOnPath {
    param([string]$Name)
    $cmds = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmds) { return $false }
    foreach ($cmd in @($cmds)) {
        if ([string]::IsNullOrWhiteSpace($cmd.Source)) { continue }
        if ($cmd.Source -match '\\WindowsApps\\') { continue }
        if (Test-Path -LiteralPath $cmd.Source -PathType Leaf) {
            try {
                if ((Get-Item -LiteralPath $cmd.Source).Length -gt 0) {
                    return $true
                }
            } catch {}
        }
    }
    return $false
}

function Test-ToolInstalled {
    param([string]$Tool)
    $profileRoot = Get-ProfileRoot
    switch ($Tool) {
        'ClaudeCode' {
            if (Get-Command claude -ErrorAction SilentlyContinue) { return $true }
            if (Test-Path -LiteralPath (Join-ProfilePath -ProfileRoot $profileRoot -RelativePath '.claude\settings.json') -PathType Leaf) { return $true }
            if (Test-Path -LiteralPath (Join-ProfilePath -ProfileRoot $profileRoot -RelativePath '.claude\CLAUDE.md') -PathType Leaf) { return $true }
            return $false
        }
        'Codex' {
            if (Get-Command codex -ErrorAction SilentlyContinue) { return $true }
            if (Test-Path -LiteralPath (Join-ProfilePath -ProfileRoot $profileRoot -RelativePath '.codex\config.toml') -PathType Leaf) { return $true }
            return $false
        }
        'Cursor' {
            if (Get-Command cursor -ErrorAction SilentlyContinue) { return $true }
            $cursorRoot = Join-ProfilePath -ProfileRoot $profileRoot -RelativePath '.cursor'
            if (-not (Test-Path -LiteralPath $cursorRoot -PathType Container)) { return $false }
            foreach ($name in @('mcp.json', 'skills-cursor', 'rules')) {
                if (Test-Path -LiteralPath (Join-Path $cursorRoot $name)) { return $true }
            }
            return $false
        }
        'OpenCode' {
            if (Get-Command opencode -ErrorAction SilentlyContinue) { return $true }
            $configDir = Join-ProfilePath -ProfileRoot $profileRoot -RelativePath '.config\opencode'
            if (Test-Path -LiteralPath (Join-Path $configDir 'opencode.json') -PathType Leaf) { return $true }
            if (Test-Path -LiteralPath (Join-Path $configDir 'opencode.jsonc') -PathType Leaf) { return $true }
            return $false
        }
        'Antigravity' {
            if (Test-UsableCliOnPath -Name 'agy') { return $true }
            if (Test-UsableCliOnPath -Name 'antigravity') { return $true }
            $geminiConfigDir = Join-ProfilePath -ProfileRoot $profileRoot -RelativePath '.gemini\config'
            if (Test-Path -LiteralPath (Join-Path $geminiConfigDir 'config.json') -PathType Leaf) { return $true }
            if (Test-Path -LiteralPath (Join-Path $geminiConfigDir 'AGENTS.md') -PathType Leaf) { return $true }
            if (Test-Path -LiteralPath (Join-Path $geminiConfigDir 'GEMINI.md') -PathType Leaf) { return $true }
            $geminiDir = Join-ProfilePath -ProfileRoot $profileRoot -RelativePath '.gemini'
            if (Test-Path -LiteralPath (Join-Path $geminiDir 'AGENTS.md') -PathType Leaf) { return $true }
            if (Test-Path -LiteralPath (Join-Path $geminiDir 'GEMINI.md') -PathType Leaf) { return $true }
            return $false
        }
    }
    return $false
}

function Get-LinkTarget {
    param([System.IO.FileSystemInfo]$Item)
    $target = $Item.Target
    if ($null -eq $target) { return '' }
    $arr = @($target)
    if ($arr.Count -eq 0) { return '' }
    return [string]$arr[0]
}

function Get-EntryInfo {
    param([string]$DirPath, [string]$Name)

    $full = Join-Path $DirPath $Name
    $info = [ordered]@{
        present     = $false
        linkType    = ''
        target      = ''
        targetValid = $false
    }
    if (-not (Test-Path -LiteralPath $full)) {
        # On Linux and macOS, Test-Path follows a symbolic link, so a dangling link
        # looks absent; read the link itself to report it as present and broken.
        $danglingTarget = [System.IO.DirectoryInfo]::new($full).LinkTarget
        if ([string]::IsNullOrWhiteSpace($danglingTarget)) { return $info }
        $info.present = $true
        $info.linkType = 'SymbolicLink'
        $info.target = $danglingTarget
        return $info
    }

    $info.present = $true
    $item = Get-Item -LiteralPath $full -Force
    if ($item.LinkType) {
        $info.linkType = [string]$item.LinkType
        $info.target = Get-LinkTarget -Item $item
        $info.targetValid = (-not [string]::IsNullOrWhiteSpace($info.target)) -and (Test-Path -LiteralPath $info.target)
    }
    else {
        # Real folder/file (not a link). Counts as present and valid.
        $info.linkType = 'Directory'
        $info.target = $full
        $info.targetValid = $true
    }
    return $info
}

# --- Setup --------------------------------------------------------------------
$root = Resolve-RepoRoot -Requested $RepoRoot
$profileRoot = Get-ProfileRoot

# Inventory: root subfolders that contain SKILL.md
$inventory = @(
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
        ForEach-Object { $_.Name } | Sort-Object
)
$inventorySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($s in $inventory) { [void]$inventorySet.Add($s) }

# Directory map per tool (native + compatibility)
# Cursor: native is required only at ~/.cursor/skills (compact and expansive). .agents/.claude/.codex
# count as compat — covered_by_compatibility counts as REGISTRATION_GAPS.
$toolDefs = @(
    [ordered]@{ Name = 'ClaudeCode'; Native = @('.claude\skills'); Compat = @() },
    [ordered]@{ Name = 'Codex'; Native = @('.codex\skills', '.agents\skills'); Compat = @() },
    [ordered]@{ Name = 'Cursor'; Native = @('.cursor\skills'); Compat = @('.agents\skills', '.claude\skills', '.codex\skills') },
    [ordered]@{ Name = 'OpenCode'; Native = @('.config\opencode\skills', '.agents\skills'); Compat = @() },
    [ordered]@{ Name = 'Antigravity'; Native = @('.gemini\config\skills', '.agents\skills'); Compat = @() }
)
# User-declared directories (tools without built-in support): always treated as installed.
foreach ($extra in @($AdditionalSkillsRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $toolDefs += [ordered]@{ Name = "Custom:$extra"; Native = @($extra); Compat = @(); Declared = $true }
}

function Split-NameList {
    # Under pwsh -File, "-SkipTool A,B" arrives as the single string "A,B"; in process
    # it arrives as an array. Split every value on commas so both forms (and repeated
    # values) yield the same trimmed, non-empty names.
    param([string[]]$Values)
    return @(@($Values) | ForEach-Object { "$_" -split ',' } |
            ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# Tools and skills the user chose not to link: validated against the known names,
# kept in their canonical spelling. Split-NameList is the single normalization point (trim, drop empties).
$skippedTools = [System.Collections.Generic.List[string]]::new()
foreach ($name in (Split-NameList -Values $SkipTool)) {
    $match = @($toolDefs | Where-Object { $_.Name -ieq $name })
    if ($match.Count -eq 0) {
        throw ("BLOCK: unknown -SkipTool name '{0}'; use one of: {1}" -f $name, (@($toolDefs | ForEach-Object { $_.Name }) -join ', '))
    }
    if (-not $skippedTools.Contains($match[0].Name)) { $skippedTools.Add($match[0].Name) }
}
# -OnlyTool is the complement of -SkipTool: every built-in tool not listed is skipped.
# User-declared roots (-AdditionalSkillsRoot) are never skipped by it.
$onlyNames = @(Split-NameList -Values $OnlyTool)
if ($onlyNames.Count -gt 0) {
    if ($skippedTools.Count -gt 0) {
        throw 'BLOCK: -OnlyTool and -SkipTool cannot be combined; use one of them.'
    }
    $onlyTools = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $onlyNames) {
        $match = @($toolDefs | Where-Object { $_.Name -ieq $name })
        if ($match.Count -eq 0) {
            throw ("BLOCK: unknown -OnlyTool name '{0}'; use one of: {1}" -f $name, (@($toolDefs | ForEach-Object { $_.Name }) -join ', '))
        }
        [void]$onlyTools.Add($match[0].Name)
    }
    foreach ($def in $toolDefs) {
        if ($def.Contains('Declared') -or $onlyTools.Contains($def.Name)) { continue }
        $skippedTools.Add($def.Name)
    }
}
$skippedSkills = [System.Collections.Generic.List[string]]::new()
foreach ($name in (Split-NameList -Values $SkipSkill)) {
    $match = @($inventory | Where-Object { $_ -ieq $name })
    if ($match.Count -eq 0) {
        throw ("BLOCK: unknown -SkipSkill name '{0}'; the skills inventory is: {1}" -f $name, (@($inventory) -join ', '))
    }
    if (-not $skippedSkills.Contains($match[0])) { $skippedSkills.Add($match[0]) }
}

$toolsReport = @()
$sumOk = 0; $sumMissing = 0; $sumBroken = 0; $sumCompat = 0; $sumSkipped = 0

foreach ($def in $toolDefs) {
    if ($def.Contains('Declared')) { $installed = $true }
    else { $installed = Test-ToolInstalled -Tool $def.Name }
    $toolSkipped = $skippedTools.Contains($def.Name)
    $skillsStatus = @()

    if ($installed) {
        foreach ($skill in $inventory) {
            $status = 'missing'; $linkType = ''; $target = ''

            foreach ($rel in $def.Native) {
                $dir = Resolve-SkillsDir -ProfileRoot $profileRoot -Path $rel
                $entry = Get-EntryInfo -DirPath $dir -Name $skill
                if ($entry.present) {
                    if ($entry.targetValid) { $status = 'OK'; $linkType = $entry.linkType; $target = $entry.target; break }
                    else { $status = 'broken'; $linkType = $entry.linkType; $target = $entry.target }
                }
            }

            if ($status -eq 'missing') {
                foreach ($rel in $def.Compat) {
                    $dir = Resolve-SkillsDir -ProfileRoot $profileRoot -Path $rel
                    $entry = Get-EntryInfo -DirPath $dir -Name $skill
                    if ($entry.present -and $entry.targetValid) {
                        $status = 'covered_by_compatibility'; $linkType = $entry.linkType; $target = $entry.target; break
                    }
                }
            }

            # A link the user chose not to create is not a gap; an existing link keeps its status.
            if (($status -eq 'missing' -or $status -eq 'covered_by_compatibility') -and
                ($toolSkipped -or $skippedSkills.Contains($skill))) {
                $status = 'skipped_by_choice'; $linkType = ''; $target = ''
            }

            switch ($status) {
                'OK' { $sumOk++ }
                'covered_by_compatibility' { $sumCompat++ }
                'broken' { $sumBroken++ }
                'missing' { $sumMissing++ }
                'skipped_by_choice' { $sumSkipped++ }
            }

            $skillsStatus += [ordered]@{ name = $skill; status = $status; linkType = $linkType; target = $target }
        }
    }

    $toolsReport += [ordered]@{
        name            = $def.Name
        installed       = $installed
        skippedByChoice = $toolSkipped
        native          = @($def.Native | ForEach-Object { Resolve-SkillsDir -ProfileRoot $profileRoot -Path $_ })
        compat          = @($def.Compat | ForEach-Object { Resolve-SkillsDir -ProfileRoot $profileRoot -Path $_ })
        skills          = $skillsStatus
    }
}

# Orphans: scan each known skills directory exactly once (deduplicated by canonical path)
$rootNorm = (ConvertTo-LongPath -Path $root).TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
$allDirs = [System.Collections.Generic.List[string]]::new()
$seenCanonical = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$scanDirs = @('.claude\skills', '.codex\skills', '.agents\skills', '.cursor\skills', '.config\opencode\skills', '.gemini\config\skills') +
    @($AdditionalSkillsRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
foreach ($rel in $scanDirs) {
    $fullDir = Resolve-SkillsDir -ProfileRoot $profileRoot -Path $rel
    if (Test-Path -LiteralPath $fullDir -PathType Container) {
        $canonical = (Resolve-Path -LiteralPath $fullDir).Path
        $canonLong = (ConvertTo-LongPath -Path $canonical).TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
        if (-not $seenCanonical.Contains($canonLong)) {
            [void]$seenCanonical.Add($canonLong)
            [void]$allDirs.Add($fullDir)
        }
    }
}
$orphans = @()
foreach ($dir in $allDirs) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    foreach ($child in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
        if ($inventorySet.Contains($child.Name)) { continue }
        $childItem = Get-Item -LiteralPath $child.FullName -Force -ErrorAction SilentlyContinue
        if ($null -eq $childItem) { continue }
        $tgt = Get-LinkTarget -Item $childItem
        if ([string]::IsNullOrWhiteSpace($tgt)) { continue }
        # Normalize the target to a long path (expand 8.3 short names) before comparing.
        $tgtResolved = (ConvertTo-LongPath -Path $tgt).TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
        if ($tgtResolved.StartsWith($rootNorm)) {
            $orphans += [ordered]@{ dir = $dir; name = $child.Name; target = $tgt }
        }
    }
}

# --- Verdict -------------------------------------------------------------------
# covered_by_compatibility on Cursor (missing ~/.cursor/skills) counts as a gap —
# native registration at ~/.cursor/skills is mandatory when Cursor is installed.
# skipped_by_choice never counts as a gap.
$hasGaps = ($sumMissing -gt 0) -or ($sumBroken -gt 0) -or ($sumCompat -gt 0) -or (@($orphans).Count -gt 0)
if ($hasGaps) { $overall = 'REGISTRATION_GAPS' } else { $overall = 'REGISTRATION_OK' }

$result = [ordered]@{
    overall         = $overall
    repoRoot        = $root
    strategy        = $Strategy
    skillsInventory = @($inventory)
    skippedByChoice = [ordered]@{
        tools  = @($skippedTools)
        skills = @($skippedSkills)
    }
    tools           = $toolsReport
    orphans         = @($orphans)
    summary         = [ordered]@{
        ok              = $sumOk
        coveredByCompat = $sumCompat
        missing         = $sumMissing
        broken          = $sumBroken
        skippedByChoice = $sumSkipped
        orphans         = @($orphans).Count
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8 | Write-Output
    return
}

# Human-readable output
Write-Output ("OVERALL: {0}" -f $overall)
Write-Output ("Repo: {0}" -f $root)
Write-Output ("Inventory: {0} skills | Strategy: {1}" -f @($inventory).Count, $Strategy)
if ($skippedTools.Count -gt 0 -or $skippedSkills.Count -gt 0) {
    Write-Output ("Not linked by the user's choice: tools [{0}] | skills [{1}]" -f ($skippedTools -join ', '), ($skippedSkills -join ', '))
}
Write-Output ''
foreach ($t in $toolsReport) {
    if (-not $t.installed) {
        Write-Output ("[{0}] not installed" -f $t.name)
        continue
    }
    Write-Output ("[{0}] installed{1}" -f $t.name, $(if ($t.skippedByChoice) { ', skipped by choice' } else { '' }))
    foreach ($s in $t.skills) {
        if ($s.status -eq 'skipped_by_choice') {
            Write-Output ("    {0,-28} skipped by choice" -f $s.name)
        }
        elseif ($s.status -ne 'OK') {
            Write-Output ("    {0,-28} {1}" -f $s.name, $s.status)
        }
    }
    $okCount = @($t.skills | Where-Object { $_.status -eq 'OK' }).Count
    Write-Output ("    ({0} OK; the rest are listed above, if any)" -f $okCount)
}
Write-Output ''
if (@($orphans).Count -gt 0) {
    Write-Output 'Orphans (link to the repo with no matching skill):'
    foreach ($o in $orphans) { Write-Output ("    {0}  ->  {1}" -f $o.name, $o.target) }
}
else {
    Write-Output 'Orphans: none'
}
Write-Output ''
Write-Output ("Summary: OK={0} compat={1} missing={2} broken={3} skippedByChoice={4} orphans={5}" -f `
        $sumOk, $sumCompat, $sumMissing, $sumBroken, $sumSkipped, @($orphans).Count)
