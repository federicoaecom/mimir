#requires -Version 7.4
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptUnderTest = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts/Test-MimirSkillsRegistration.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function New-TempDir { $p = Join-Path ([IO.Path]::GetTempPath()) ('mimir-pi-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $p | Out-Null; $p }
function Link-Skill([string]$dir,[string]$name,[string]$target) { New-Item -ItemType Directory -Path $dir -Force | Out-Null; $kind = if ($IsWindows) {'Junction'} else {'SymbolicLink'}; New-Item -ItemType $kind -Path (Join-Path $dir $name) -Target $target | Out-Null }
$variables = 'HOME','USERPROFILE','PATH','GENTLE_SHELL_USER_PI_HOME','PI_CODING_AGENT_DIR','GENTLE_PI_AGENT_HOME','GENTLE_SHELL_HOME'
$saved = @{}; foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$repo = New-TempDir; $profile = New-TempDir; $pi = New-TempDir; $gentle = New-TempDir; $project = $null
try {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    $env:HOME = $profile; $env:USERPROFILE = $profile; $env:PATH = ''
    New-Item -ItemType Directory -Path (Join-Path $repo 'sample-skill') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'sample-skill/SKILL.md') -Value '# sample' -Encoding utf8
    Link-Skill (Join-Path $pi 'skills') 'sample-skill' (Join-Path $repo 'sample-skill')
    Link-Skill (Join-Path $gentle 'skills') 'sample-skill' (Join-Path $repo 'sample-skill')
    $json = & $scriptUnderTest -RepoRoot $repo -PiAgentHome $pi -GentleShellAgentHome $gentle -AsJson | Out-String
    $r = $json | ConvertFrom-Json
    $names = @($r.tools | ForEach-Object name)
    Assert ($names -contains 'Pi') 'explicit Pi home should declare Pi'
    Assert ($names -contains 'GentleShell') 'explicit GentleShell home should declare GentleShell'
    foreach ($tool in 'Pi','GentleShell') {
        $t = @($r.tools | Where-Object name -eq $tool)[0]
        Assert ($t.installed) "$tool explicit target should be installed"
        Assert (@($t.native | Where-Object { $_ -match 'skills' }).Count -gt 0) "$tool should report native skills root"
        Assert ((@($t.skills | Where-Object name -eq 'sample-skill')[0].status) -eq 'OK') "$tool should recognize native skill link"
    }
    Assert (@($r.tools).Count -eq 7) 'built-in inventory should contain seven tools'
    Assert ((@($r.orphans).Count) -eq 0) 'same-target/native scan should not manufacture orphan entries'
    $env:PI_CODING_AGENT_DIR = Join-Path $profile 'lower-priority'
    $priority = (& $scriptUnderTest -RepoRoot $repo -PiAgentHome $pi -GentleShellAgentHome $gentle -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($priority.tools | Where-Object name -eq 'Pi')[0].native | Select-Object -First 1) -eq (Join-Path $pi 'skills')) 'explicit Pi home has precedence over environment selection'
    $tildeTarget = Join-Path $profile '.tilde-pi'
    $tilde = (& $scriptUnderTest -RepoRoot $repo -PiAgentHome '~/.tilde-pi' -GentleShellAgentHome $gentle -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($tilde.tools | Where-Object name -eq 'Pi')[0].native | Select-Object -First 1) -eq (Join-Path $tildeTarget 'skills')) ("leading tilde resolves against selected profile; got {0}" -f (@($tilde.tools | Where-Object name -eq 'Pi')[0].native | Select-Object -First 1))
    $relative = (& $scriptUnderTest -RepoRoot $repo -PiAgentHome 'relative-pi' -GentleShellAgentHome $gentle -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($relative.tools | Where-Object name -eq 'Pi')[0].native | Select-Object -First 1) -eq (Join-Path (Get-Location).Path 'relative-pi/skills')) 'relative Pi home resolves against current directory'

    # A shared folder alone is not product detection; named consumers remain present but uninstalled.
    $sharedOnly = Join-Path $profile '.agents/skills'
    Link-Skill $sharedOnly 'sample-skill' (Join-Path $repo 'sample-skill')
    $shared = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert (-not (@($shared.tools | Where-Object name -eq 'Pi')[0].installed)) 'shared folder alone must not detect Pi'
    Assert (-not (@($shared.tools | Where-Object name -eq 'GentleShell')[0].installed)) 'shared folder alone must not detect Gentle Shell'

    # Pi settings detection follows the selected env home; Pi's active marker outranks its default.
    $env:GENTLE_SHELL_USER_PI_HOME = $pi
    New-Item -ItemType Directory -Path $pi -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $pi 'settings.json') -Value '{}' -Encoding utf8
    $piDetected = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert (@($piDetected.tools | Where-Object name -eq 'Pi')[0].installed) 'Pi settings under resolved environment home detect Pi'
    Assert ((@($piDetected.tools | Where-Object name -eq 'Pi')[0].skills | Where-Object name -eq 'sample-skill')[0].status -eq 'OK') 'GENTLE_SHELL_USER_PI_HOME takes precedence and finds its native link'
    $env:GENTLE_SHELL_USER_PI_HOME = $null
    $env:PI_CODING_AGENT_DIR = $pi
    $piDetected = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert (@($piDetected.tools | Where-Object name -eq 'Pi')[0].installed) 'PI_CODING_AGENT_DIR settings detect Pi'

    # Launcher home selectors: link uses Pi home, isolated remains independent, custom paths resolve from cwd.
    $configDir = Join-Path $profile '.gentle-shell'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $configDir 'config.json') -Value '{"home":"link"}' -Encoding utf8
    $env:PI_CODING_AGENT_DIR = $pi
    $linked = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($linked.tools | Where-Object name -eq 'GentleShell')[0].native | Select-Object -First 1) -eq (Join-Path $pi 'skills')) 'saved link selector resolves to Pi home'
    Set-Content -LiteralPath (Join-Path $configDir 'config.json') -Value '{"home":"isolated"}' -Encoding utf8
    $isolated = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($isolated.tools | Where-Object name -eq 'GentleShell')[0].native | Select-Object -First 1) -eq (Join-Path $profile '.gentle-shell/agent/skills')) 'isolated selector does not reuse Pi home'
    Set-Content -LiteralPath (Join-Path $configDir 'config.json') -Value '{"home":"custom-home"}' -Encoding utf8
    $custom = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($custom.tools | Where-Object name -eq 'GentleShell')[0].native | Select-Object -First 1) -eq (Join-Path (Get-Location).Path 'custom-home/skills')) 'relative custom launcher home resolves against cwd'
    Set-Content -LiteralPath (Join-Path $configDir 'config.json') -Value '{bad json' -Encoding utf8
    $malformed = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($malformed.tools | Where-Object name -eq 'GentleShell')[0].native | Select-Object -First 1) -eq (Join-Path $profile '.gentle-shell/agent/skills')) 'malformed config uses isolated default'
    Set-Content -LiteralPath (Join-Path $configDir 'config.json') -Value '{"home":42}' -Encoding utf8
    $foreign = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($foreign.tools | Where-Object name -eq 'GentleShell')[0].native | Select-Object -First 1) -eq (Join-Path $profile '.gentle-shell/agent/skills')) 'non-string config selector uses isolated default'

    # JSON selectors follow the launcher's case-sensitive object contract, not PowerShell member lookup.
    foreach ($case in @(
        @{ Json = '{"Home":"link"}'; Home = (Join-Path $profile '.gentle-shell/agent'); Name = 'uppercase key is not home' },
        @{ Json = '[{"home":"link"}]'; Home = (Join-Path $profile '.gentle-shell/agent'); Name = 'array is not a config object' },
        @{ Json = '{"home":"LINK"}'; Home = (Join-Path (Get-Location).Path 'LINK'); Name = 'uppercase LINK is a custom path' },
        @{ Json = '{"home":"ISOLATED"}'; Home = (Join-Path (Get-Location).Path 'ISOLATED'); Name = 'uppercase ISOLATED is a custom path' },
        @{ Json = '{"home":" "}'; Home = (Join-Path (Get-Location).Path ' '); Name = 'nonempty whitespace selector is a custom path' }
    )) {
        Set-Content -LiteralPath (Join-Path $configDir 'config.json') -Value $case.Json -Encoding utf8
        $edge = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
        $actualRoot = @($edge.tools | Where-Object name -eq 'GentleShell')[0].native[0]
        Assert ($actualRoot -ceq (Join-Path $case.Home 'skills')) $case.Name
    }

    # Active marker and explicit selection take precedence; explicit project selection declares the consumer.
    $env:GENTLE_PI_AGENT_HOME = $gentle
    $active = (& $scriptUnderTest -RepoRoot $repo -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($active.tools | Where-Object name -eq 'GentleShell')[0].native | Select-Object -First 1) -eq (Join-Path $gentle 'skills')) 'active Gentle marker overrides saved config'
    $project = New-TempDir
    Link-Skill (Join-Path $project '.pi/skills') 'sample-skill' (Join-Path $repo 'sample-skill')
    $projectReport = (& $scriptUnderTest -RepoRoot $repo -Scope Project -ProjectRoot $project -PiAgentHome $pi -OnlyTool Pi -AsJson | Out-String) | ConvertFrom-Json
    Assert (@($projectReport.tools | Where-Object name -eq 'Pi')[0].installed) 'explicit target declares Pi in project scope'
    Assert ((@($projectReport.tools | Where-Object name -eq 'Pi')[0].skills | Where-Object name -eq 'sample-skill')[0].status -eq 'OK') 'project Pi native path is audited'
    Assert (@($projectReport.userScopeAlsoRegistered | Where-Object tool -eq 'Pi').Count -gt 0) 'user-level Pi registration appears in project duplicate warnings'
    Link-Skill (Join-Path $project '.agents/skills') 'sample-skill' (Join-Path $repo 'sample-skill')
    $projectBoth = (& $scriptUnderTest -RepoRoot $repo -Scope Project -ProjectRoot $project -PiAgentHome $pi -GentleShellAgentHome $gentle -OnlyTool Pi,GentleShell -AsJson | Out-String) | ConvertFrom-Json
    foreach ($tool in 'Pi','GentleShell') { Assert ((@($projectBoth.tools | Where-Object name -eq $tool)[0].skills | Where-Object name -eq 'sample-skill')[0].status -eq 'OK') "$tool accepts project shared-folder registration" }
    Assert (@($projectBoth.userScopeAlsoRegistered | Where-Object { $_.tool -in @('Pi','GentleShell') }).Count -ge 2) 'project report warns for both user-level registrations'
    Assert (@($projectBoth.orphans).Count -eq 0) 'shared project directory is scanned without duplicate orphan records'
    $orphanTarget = Join-Path $repo 'removed-skill'
    New-Item -ItemType Directory -Path $orphanTarget | Out-Null
    $bothHomes = Join-Path $profile 'both-homes'
    Link-Skill (Join-Path $bothHomes 'skills') 'removed-skill' $orphanTarget
    $dedup = (& $scriptUnderTest -RepoRoot $repo -PiAgentHome $bothHomes -GentleShellAgentHome $bothHomes -AsJson | Out-String) | ConvertFrom-Json
    Assert (@($dedup.orphans | Where-Object name -eq 'removed-skill').Count -eq 1) 'identical Pi and Gentle home orphan scans are deduplicated'
    $emptyHome = Join-Path $profile 'empty-home'
    Remove-Item -LiteralPath (Join-Path $profile '.agents/skills/sample-skill') -Force
    $missing = (& $scriptUnderTest -RepoRoot $repo -PiAgentHome $emptyHome -OnlyTool Pi -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($missing.tools | Where-Object name -eq 'Pi')[0].skills | Where-Object name -eq 'sample-skill')[0].status -eq 'missing') 'unregistered skill keeps the existing missing status'
    Link-Skill (Join-Path $profile '.agents/skills') 'sample-skill' (Join-Path $repo 'sample-skill')
    New-Item -ItemType Directory -Path (Join-Path $repo 'broken-skill') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'broken-skill/SKILL.md') -Value '# broken target' -Encoding utf8
    $brokenTarget = Join-Path $profile 'broken-target'
    New-Item -ItemType Directory -Path $brokenTarget | Out-Null
    Link-Skill (Join-Path $emptyHome 'skills') 'broken-skill' $brokenTarget
    Remove-Item -LiteralPath $brokenTarget -Recurse -Force
    $broken = (& $scriptUnderTest -RepoRoot $repo -PiAgentHome $emptyHome -OnlyTool Pi -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($broken.tools | Where-Object name -eq 'Pi')[0].skills | Where-Object name -eq 'broken-skill')[0].status -eq 'broken') 'broken native link keeps the existing broken status'
    $skipPi = (& $scriptUnderTest -RepoRoot $repo -PiAgentHome $pi -OnlyTool Pi -AsJson | Out-String) | ConvertFrom-Json
    Assert ((@($skipPi.tools | Where-Object name -eq 'Pi')[0].installed)) 'OnlyTool Pi selects Pi'
    Assert (@($skipPi.skippedByChoice.tools) -contains 'GentleShell') 'OnlyTool Pi skips GentleShell'
    $skipGentle = (& $scriptUnderTest -RepoRoot $repo -GentleShellAgentHome $gentle -SkipTool GentleShell -AsJson | Out-String) | ConvertFrom-Json
    Assert (@($skipGentle.skippedByChoice.tools) -contains 'GentleShell') 'SkipTool GentleShell is accepted'
    Remove-Item -LiteralPath $project -Recurse -Force
}
catch { $failures.Add($_.Exception.Message) }
finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    foreach ($path in @($repo,$profile,$pi,$gentle,$project)) { if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) { Get-ChildItem -LiteralPath $path -Recurse -Force | Where-Object LinkType | ForEach-Object { $_.Delete() }; Remove-Item -LiteralPath $path -Recurse -Force } }
}
if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ }; exit 1 }
'OK: Test-MimirSkillsRegistrationPiSelfTest.ps1'
exit 0
