#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for New-MimirKbWorkspace.ps1, the KB workspace scaffolder.
.DESCRIPTION
    Scaffolds synthetic workspaces under the system temp folder and checks:
    (a) a fresh scaffold creates every folder and file, with no sanitized
        shared-root placeholder, no unprefixed sibling wrapper name, no
        template-only help text, a canonical pwsh -NoProfile -File example in
        every wrapper, and UTF-8 without BOM plus LF everywhere;
    (b) the generated structure gate and the wrapper inventory accept the result;
    (c) a re-run is a no-op that reports every file SKIPPED_EXISTING;
    (d) a pre-existing README.md is preserved byte for byte;
    (e) an invalid -KbName exits 2 and creates nothing;
    (f) the setup contract manifest lists the scaffolder;
    (g) an XPZ-only workspace (-XpzOnly, no native KB folder) gets neutral
        README.md and AGENTS.md text with no native-folder claim or
        placeholder, a stable-identity pending line pointing at the first
        sync, and an identity wrapper that reports NATIVE_KB_NOT_RECORDED
        (exit 3), with -AsJson also as one JSON object on stdout, without
        touching kb-source-metadata.md; -XpzOnly together with -KbNativePath
        exits 2;
    (h) the .gitignore ignores the project skill links (.claude/skills/, .agents/skills/), and the
        scaffolder run through a project skill link (<project>/.claude/skills/mimir-lite, a
        junction or symbolic link to this repository's skills/mimir-lite) bakes the real checkout
        root into the wrappers, never the link's parent folder; a checkout reached through a
        linked ancestor folder keeps that path, since only a skill link is followed.
    No real KB, no external tool; child scripts run in their own pwsh process.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scaffolder = Join-Path $repoRoot 'skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1'
$inventoryScript = Join-Path $repoRoot 'skills/mimir-lite/scripts/Test-MimirWrapperInventory.ps1'
$examplesDir = Join-Path $repoRoot 'skills/mimir-lite/workflows/setup/examples'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-new-workspace-{0}' -f [guid]::NewGuid().ToString('N'))
$utf8 = [System.Text.UTF8Encoding]::new($false)

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-ChildScript {
    param([string]$Path, [string[]]$Arguments)
    $output = & pwsh -NoProfile -NonInteractive -File $Path @Arguments 2>&1
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @($output | ForEach-Object { "$_" })
    }
}

function Invoke-ChildScriptSplit {
    param([string]$Path, [string[]]$Arguments)
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-stderr-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    try {
        $stdout = & pwsh -NoProfile -NonInteractive -File $Path @Arguments 2> $stderrPath
        $exitCode = $LASTEXITCODE
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [System.IO.File]::ReadAllText($stderrPath) } else { '' }
    } finally {
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout   = (@($stdout | ForEach-Object { "$_" }) -join "`n")
        Stderr   = $stderr
    }
}

function Invoke-Scaffolder {
    param([string[]]$Arguments)
    $result = Invoke-ChildScript -Path $scaffolder -Arguments (@($Arguments) + '-AsJson')
    $report = $null
    if ($result.ExitCode -eq 0) {
        $report = ($result.Output -join "`n") | ConvertFrom-Json
    }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Output; Report = $report }
}

function Get-WorkspaceFileHashes {
    param([string]$Root)
    $map = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName) -replace '\\', '/'
        $map[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $map
}

$siblingBaseNames = @(
    Get-ChildItem -LiteralPath $examplesDir -Filter '*.example.ps1' -Name |
        ForEach-Object { $_ -replace '\.example\.ps1$', '' }
)
$expectedWrappers = @(
    $siblingBaseNames | ForEach-Object {
        if ($_ -match '^([A-Za-z]+-)(Kb.+)$') { "scripts/$($Matches[1])SampleKb$($Matches[2]).ps1" }
    }
)
$expectedFolders = @('scripts', 'Temp', 'IdeXpzExports', 'KbObjectsXml', 'KbIntelligence')
$expectedFiles = @(
    '.gitignore', 'Temp/.gitkeep', 'IdeXpzExports/.gitkeep',
    'README.md', 'AGENTS.md', 'kb-source-metadata.md'
) + $expectedWrappers

try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)
    $nativeKb = Join-Path $tempRoot 'native-kb'
    [void](New-Item -ItemType Directory -Path $nativeKb -Force)

    # (a) Fresh scaffold into an empty folder.
    $wsA = Join-Path $tempRoot 'ws-a'
    [void](New-Item -ItemType Directory -Path $wsA -Force)
    $runA = Invoke-Scaffolder -Arguments @('-WorkspaceRoot', $wsA, '-KbName', 'SampleKb', '-KbNativePath', $nativeKb)
    Assert-True ($runA.ExitCode -eq 0) "(a) scaffold must exit 0; exit=$($runA.ExitCode), output=$($runA.Output -join ' | ')"
    Assert-True ($expectedWrappers.Count -eq 14) "(a) expected 14 example wrappers, found $($expectedWrappers.Count)"

    if ($runA.ExitCode -eq 0) {
        Assert-True ($runA.Report.status -eq 'OK') "(a) report status must be OK; got '$($runA.Report.status)'"
        Assert-True (@($runA.Report.skippedExisting).Count -eq 0) "(a) nothing may be skipped in an empty folder"
        Assert-True (@($runA.Report.nextSteps).Count -gt 0) "(a) report must list next steps"
        foreach ($folder in $expectedFolders) {
            Assert-True (Test-Path -LiteralPath (Join-Path $wsA $folder) -PathType Container) "(a) folder missing: $folder"
        }
        foreach ($file in $expectedFiles) {
            Assert-True (Test-Path -LiteralPath (Join-Path $wsA $file) -PathType Leaf) "(a) file missing: $file"
            Assert-True (@($runA.Report.created) -contains $file) "(a) report must list created file: $file"
        }
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $wsA 'scripts/gx-object-type-catalog.override.json'))) "(a) the optional catalog override must not be copied"

        $gitignore = [System.IO.File]::ReadAllText((Join-Path $wsA '.gitignore'))
        foreach ($rule in @('Temp/*', '!Temp/.gitkeep', 'IdeXpzExports/*', '!IdeXpzExports/.gitkeep',
                'KbIntelligence/kb-intelligence.sqlite', 'KbIntelligence/kb-intelligence-validation.json',
                '.claude/skills/', '.agents/skills/')) {
            Assert-True ($gitignore -match "(?m)^$([regex]::Escape($rule))$") "(a) .gitignore must carry '$rule'"
        }
        Assert-True ($gitignore -notmatch '(?m)^KbObjectsXml') "(a) .gitignore must never ignore KbObjectsXml"

        $siblingPatterns = $siblingBaseNames | ForEach-Object { '(?<![A-Za-z0-9_-])' + [regex]::Escape($_) + '\.ps1' }
        foreach ($file in Get-ChildItem -LiteralPath $wsA -Recurse -File -Force) {
            $relative = [System.IO.Path]::GetRelativePath($wsA, $file.FullName) -replace '\\', '/'
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            Assert-True (-not $hasBom) "(a) file has a UTF-8 BOM: $relative"
            $text = $utf8.GetString($bytes)
            Assert-True (-not $text.Contains("`r")) "(a) file has CR line endings: $relative"
            Assert-True (-not $text.Contains('C:\path\to\mimir-lite')) "(a) shared-root placeholder left in: $relative"
            Assert-True (-not $text.Contains('C:\path\to\native-kb')) "(a) native-KB placeholder left in: $relative"
            foreach ($pattern in $siblingPatterns) {
                Assert-True ($text -notmatch $pattern) "(a) unprefixed sibling name ($pattern) left in: $relative"
            }
        }
        # Generated wrappers carry no template-only help text and show their own canonical command.
        $workspaceText = [string]$runA.Report.workspaceRoot
        foreach ($wrapper in $expectedWrappers) {
            $text = [System.IO.File]::ReadAllText((Join-Path $wsA $wrapper))
            $name = Split-Path -Leaf $wrapper
            Assert-True (-not $text.Contains('<WorkspaceRoot>')) "(a) $wrapper still carries <WorkspaceRoot>"
            Assert-True ($text -notmatch '(?i)sanitized|this is a template') "(a) $wrapper carries template-only help text"
            Assert-True ($text -notmatch '(?m)^\s*(pwsh\b.*\s)?\.\\') "(a) $wrapper has an example with a relative .\ path"
            Assert-True ($text.Contains("pwsh -NoProfile -File `"$workspaceText/scripts/$name`"")) "(a) $wrapper must show its canonical pwsh -NoProfile -File example"
        }
        foreach ($doc in @('README.md', 'AGENTS.md')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $wsA $doc))
            foreach ($placeholder in @('<KbName>', '<WorkspaceRoot>', '<MimirLiteRoot>', '<NativeKbPath>', '<YYYY-MM-DD>', '<NativeKbCheck>', '<!-- WHEN', '<!-- END WHEN')) {
                Assert-True (-not $text.Contains($placeholder)) "(a) $doc still carries $placeholder"
            }
            Assert-True ($text -notmatch '(?i)none recorded') "(a) $doc must not carry the XPZ-only block when a native KB folder is given"
            if ($doc -eq 'AGENTS.md') {
                Assert-True ($text -match 'found and accessible') '(a) AGENTS.md must record the native KB folder check result'
            }
            Assert-True ($text.Contains('Test-SampleKbKbIndexGate.ps1')) "(a) $doc must name the prefixed index gate"
            Assert-True ($text.Contains(($nativeKb -replace '\\', '/'))) "(a) $doc must record the native KB path"
        }
        $metadata = [System.IO.File]::ReadAllText((Join-Path $wsA 'kb-source-metadata.md'))
        Assert-True ($metadata -match '(?m)^last_xpz_materialization_run_at:') "(a) kb-source-metadata.md must carry last_xpz_materialization_run_at"

        # (b) The generated structure gate and the wrapper inventory accept the workspace.
        $structureGate = Join-Path $wsA 'scripts/Test-SampleKbKbStructure.ps1'
        $structureBefore = Invoke-ChildScript -Path $structureGate -Arguments @()
        $missingLines = @($structureBefore.Output | Where-Object { $_ -cmatch '\bMISSING\b' })
        $parseLines = @($structureBefore.Output | Where-Object { $_ -cmatch '\bPARSE_ERROR\b' })
        Assert-True ($parseLines.Count -eq 0) "(b) generated wrappers must parse; output=$($structureBefore.Output -join ' | ')"
        Assert-True ($missingLines.Count -eq 1 -and $missingLines[0] -match 'kb-intelligence\.sqlite') "(b) before the first index build only kb-intelligence.sqlite may be missing; output=$($structureBefore.Output -join ' | ')"

        $sqlitePath = Join-Path $wsA 'KbIntelligence/kb-intelligence.sqlite'
        [System.IO.File]::WriteAllText($sqlitePath, 'synthetic fixture', $utf8)
        $structureAfter = Invoke-ChildScript -Path $structureGate -Arguments @()
        Assert-True ($structureAfter.ExitCode -eq 0 -and @($structureAfter.Output | Where-Object { $_ -eq 'STRUCTURE_OK' }).Count -eq 1) "(b) with an index file present the structure gate must return STRUCTURE_OK; exit=$($structureAfter.ExitCode), output=$($structureAfter.Output -join ' | ')"
        Remove-Item -LiteralPath $sqlitePath -Force

        $inventory = Invoke-ChildScript -Path $inventoryScript -Arguments @('-KbWorkspaceRoot', $wsA, '-SkillsExamplesPath', $examplesDir)
        $inventoryText = $inventory.Output -join ' | '
        Assert-True ($inventory.ExitCode -eq 0 -and $inventoryText -eq 'INVENTORY_OK') "(b) wrapper inventory must report INVENTORY_OK; got '$inventoryText'"

        # (c) Re-run is a safe no-op.
        $hashesBefore = Get-WorkspaceFileHashes -Root $wsA
        $runC = Invoke-Scaffolder -Arguments @('-WorkspaceRoot', $wsA, '-KbName', 'SampleKb', '-KbNativePath', $nativeKb)
        Assert-True ($runC.ExitCode -eq 0) "(c) re-run must exit 0; exit=$($runC.ExitCode), output=$($runC.Output -join ' | ')"
        if ($runC.ExitCode -eq 0) {
            Assert-True (@($runC.Report.created).Count -eq 0) "(c) re-run must create nothing; created=$(@($runC.Report.created) -join ', ')"
            foreach ($file in $expectedFiles) {
                Assert-True (@($runC.Report.skippedExisting) -contains $file) "(c) re-run must report SKIPPED_EXISTING for $file"
            }
        }
        $hashesAfter = Get-WorkspaceFileHashes -Root $wsA
        Assert-True (($hashesBefore | ConvertTo-Json) -eq ($hashesAfter | ConvertTo-Json)) '(c) re-run must leave every file byte-identical'
    }

    # (d) A pre-existing, modified README.md is preserved byte for byte.
    $wsD = Join-Path $tempRoot 'ws-d'
    [void](New-Item -ItemType Directory -Path $wsD -Force)
    $readmeD = Join-Path $wsD 'README.md'
    [System.IO.File]::WriteAllText($readmeD, "# Hand-written README`r`n`r`nKeep me exactly as I am.`r`n", $utf8)
    $readmeHash = (Get-FileHash -LiteralPath $readmeD -Algorithm SHA256).Hash
    $runD = Invoke-Scaffolder -Arguments @('-WorkspaceRoot', $wsD, '-KbName', 'SampleKb')
    Assert-True ($runD.ExitCode -eq 0) "(d) scaffold must exit 0; exit=$($runD.ExitCode), output=$($runD.Output -join ' | ')"
    Assert-True ((Get-FileHash -LiteralPath $readmeD -Algorithm SHA256).Hash -eq $readmeHash) '(d) pre-existing README.md must stay byte-identical'
    if ($runD.ExitCode -eq 0) {
        Assert-True (@($runD.Report.skippedExisting) -contains 'README.md') '(d) README.md must be reported SKIPPED_EXISTING'
        Assert-True (@($runD.Report.created) -contains 'AGENTS.md') '(d) the missing AGENTS.md must still be created'
        Assert-True ((@($runD.Report.pending) -join ' ') -match 'NativeKbPath') '(d) without -KbNativePath the native KB path must be reported pending'
        # The identity wrapper with its native-KB placeholder still unfilled says so instead of resolving a placeholder path.
        $resolveD = Invoke-ChildScript -Path (Join-Path $wsD 'scripts/Resolve-SampleKbKbIdentity.ps1') -Arguments @()
        Assert-True ($resolveD.ExitCode -eq 3 -and ($resolveD.Output -join ' ') -match 'NATIVE_KB_NOT_RECORDED') "(d) identity wrapper with an unfilled native KB path must report NATIVE_KB_NOT_RECORDED and exit 3; exit=$($resolveD.ExitCode), output=$($resolveD.Output -join ' | ')"
    }

    # (h) The scaffolder run through a project skill link derives the real checkout root.
    $projectH = Join-Path $tempRoot 'project-h'
    $linkDirH = Join-Path $projectH '.claude/skills'
    [void](New-Item -ItemType Directory -Path $linkDirH -Force)
    $linkTypeH = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    $linkH = Join-Path $linkDirH 'mimir-lite'
    [void](New-Item -ItemType $linkTypeH -Path $linkH -Target (Join-Path $repoRoot 'skills/mimir-lite'))
    try {
        $wsH = Join-Path $tempRoot 'ws-h'
        $runH = Invoke-ChildScript -Path (Join-Path $linkH 'scripts/New-MimirKbWorkspace.ps1') -Arguments @('-WorkspaceRoot', $wsH, '-KbName', 'SampleKb', '-XpzOnly', '-AsJson')
        Assert-True ($runH.ExitCode -eq 0) "(h) scaffold through a skill link must exit 0; exit=$($runH.ExitCode), output=$($runH.Output -join ' | ')"
        if ($runH.ExitCode -eq 0) {
            $realRoot = ([System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')) -replace '\\', '/'
            $wrapperText = [System.IO.File]::ReadAllText((Join-Path $wsH 'scripts/Test-SampleKbKbIndexGate.ps1'))
            Assert-True ($wrapperText.Contains($realRoot)) "(h) the wrappers must point at the real checkout root $realRoot"
            Assert-True ($wrapperText -notmatch [regex]::Escape(($projectH -replace '\\', '/'))) "(h) the wrappers must not point at the project's link folder $projectH"
        }
    } finally {
        $linkItem = Get-Item -LiteralPath $linkH -Force -ErrorAction SilentlyContinue
        if ($null -ne $linkItem) { $linkItem.Delete() }
    }

    # (h) A checkout reached through a linked ancestor folder keeps that path in the wrappers:
    # only a skill link is followed.
    $cloneLinkH = Join-Path $tempRoot 'clone-link-h'
    [void](New-Item -ItemType $linkTypeH -Path $cloneLinkH -Target $repoRoot)
    try {
        $wsH2 = Join-Path $tempRoot 'ws-h2'
        $runH2 = Invoke-ChildScript -Path (Join-Path $cloneLinkH 'skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1') -Arguments @('-WorkspaceRoot', $wsH2, '-KbName', 'SampleKb', '-XpzOnly', '-AsJson')
        Assert-True ($runH2.ExitCode -eq 0) "(h) scaffold through a linked checkout folder must exit 0; exit=$($runH2.ExitCode), output=$($runH2.Output -join ' | ')"
        if ($runH2.ExitCode -eq 0) {
            $linkedRoot = ([System.IO.Path]::GetFullPath($cloneLinkH).TrimEnd('\', '/')) -replace '\\', '/'
            $wrapperText2 = [System.IO.File]::ReadAllText((Join-Path $wsH2 'scripts/Test-SampleKbKbIndexGate.ps1'))
            Assert-True ($wrapperText2.Contains($linkedRoot)) "(h) the wrappers must keep the linked checkout path $linkedRoot"
        }
    } finally {
        $linkItem = Get-Item -LiteralPath $cloneLinkH -Force -ErrorAction SilentlyContinue
        if ($null -ne $linkItem) { $linkItem.Delete() }
    }

    # (g) XPZ-only workspace: no native KB folder at all.
    $wsG = Join-Path $tempRoot 'ws-g'
    $runG = Invoke-Scaffolder -Arguments @('-WorkspaceRoot', $wsG, '-KbName', 'SampleKb', '-XpzOnly')
    Assert-True ($runG.ExitCode -eq 0) "(g) XPZ-only scaffold must exit 0; exit=$($runG.ExitCode), output=$($runG.Output -join ' | ')"
    if ($runG.ExitCode -eq 0) {
        Assert-True ([bool]$runG.Report.xpzOnly) '(g) report must carry xpzOnly=true'
        $pendingG = @($runG.Report.pending) -join ' '
        Assert-True ($pendingG -notmatch 'NativeKbPath') "(g) an XPZ-only workspace must not report the native KB path pending; pending=$pendingG"
        Assert-True ($pendingG -match 'Stable identity' -and $pendingG -match 'first sync' -and $pendingG -match 'Source') "(g) the stable identity must be pending on the first sync's Source block; pending=$pendingG"
        foreach ($file in Get-ChildItem -LiteralPath $wsG -Recurse -File -Force) {
            $relative = [System.IO.Path]::GetRelativePath($wsG, $file.FullName) -replace '\\', '/'
            $text = [System.IO.File]::ReadAllText($file.FullName)
            Assert-True (-not $text.Contains('C:\path\to\native-kb')) "(g) native-KB placeholder left in: $relative"
            Assert-True ($text -notmatch '(?i)existed and was accessible') "(g) native-folder existence claim left in: $relative"
        }
        foreach ($doc in @('README.md', 'AGENTS.md')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $wsG $doc))
            foreach ($placeholder in @('<KbName>', '<WorkspaceRoot>', '<MimirLiteRoot>', '<NativeKbPath>', '<YYYY-MM-DD>', '<NativeKbCheck>', '<!-- WHEN', '<!-- END WHEN')) {
                Assert-True (-not $text.Contains($placeholder)) "(g) $doc still carries $placeholder"
            }
            Assert-True ($text -match 'XPZ-only') "(g) $doc must say the workspace is XPZ-only"
            Assert-True ($text -match '`Source`') "(g) $doc must say the identity comes from the XPZ Source block"
        }
        $inventoryG = Invoke-ChildScript -Path $inventoryScript -Arguments @('-KbWorkspaceRoot', $wsG, '-SkillsExamplesPath', $examplesDir)
        Assert-True ($inventoryG.ExitCode -eq 0 -and ($inventoryG.Output -join ' | ') -eq 'INVENTORY_OK') "(g) wrapper inventory must report INVENTORY_OK; got '$($inventoryG.Output -join ' | ')'"

        $resolveG = Join-Path $wsG 'scripts/Resolve-SampleKbKbIdentity.ps1'
        $metadataG = Join-Path $wsG 'kb-source-metadata.md'
        $metadataHash = (Get-FileHash -LiteralPath $metadataG -Algorithm SHA256).Hash
        foreach ($resolveArgs in @(@(), @('-UpdateMetadata'))) {
            $runResolve = Invoke-ChildScript -Path $resolveG -Arguments $resolveArgs
            $label = if ($resolveArgs.Count) { $resolveArgs -join ' ' } else { '(no arguments)' }
            Assert-True ($runResolve.ExitCode -eq 3) "(g) identity wrapper $label must exit 3; exit=$($runResolve.ExitCode), output=$($runResolve.Output -join ' | ')"
            Assert-True (($runResolve.Output -join ' ') -match 'NATIVE_KB_NOT_RECORDED' -and ($runResolve.Output -join ' ') -match 'Source') "(g) identity wrapper $label must report NATIVE_KB_NOT_RECORDED and point at the XPZ Source block; output=$($runResolve.Output -join ' | ')"
        }
        # With -AsJson the not-recorded path also prints exactly one JSON object on stdout; stderr keeps the line.
        foreach ($resolveArgs in @(@('-AsJson'), @('-UpdateMetadata', '-AsJson'))) {
            $runJson = Invoke-ChildScriptSplit -Path $resolveG -Arguments $resolveArgs
            $label = $resolveArgs -join ' '
            Assert-True ($runJson.ExitCode -eq 3) "(g) identity wrapper $label must exit 3; exit=$($runJson.ExitCode), stdout=$($runJson.Stdout), stderr=$($runJson.Stderr)"
            Assert-True ($runJson.Stderr -match 'NATIVE_KB_NOT_RECORDED') "(g) identity wrapper $label must keep NATIVE_KB_NOT_RECORDED on stderr; stderr=$($runJson.Stderr)"
            $parsed = $null
            try { $parsed = $runJson.Stdout | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }
            Assert-True ($null -ne $parsed -and @($parsed).Count -eq 1 -and $parsed -is [pscustomobject]) "(g) identity wrapper $label must print exactly one JSON object on stdout; stdout=$($runJson.Stdout)"
            if ($null -ne $parsed -and $parsed -is [pscustomobject]) {
                Assert-True ($parsed.PSObject.Properties.Name -contains 'status' -and $parsed.status -eq 'NATIVE_KB_NOT_RECORDED') "(g) identity wrapper $label JSON must carry status NATIVE_KB_NOT_RECORDED; stdout=$($runJson.Stdout)"
                Assert-True ($parsed.PSObject.Properties.Name -contains 'message' -and "$($parsed.message)" -match 'Source') "(g) identity wrapper $label JSON must carry the message; stdout=$($runJson.Stdout)"
            }
        }
        Assert-True ((Get-FileHash -LiteralPath $metadataG -Algorithm SHA256).Hash -eq $metadataHash) '(g) the identity wrapper must leave kb-source-metadata.md byte-identical'
    }
    $wsG2 = Join-Path $tempRoot 'ws-g2'
    $runG2 = Invoke-ChildScript -Path $scaffolder -Arguments @('-WorkspaceRoot', $wsG2, '-KbName', 'SampleKb', '-XpzOnly', '-KbNativePath', $nativeKb)
    Assert-True ($runG2.ExitCode -eq 2) "(g) -XpzOnly with -KbNativePath must exit 2; exit=$($runG2.ExitCode), output=$($runG2.Output -join ' | ')"
    Assert-True (-not (Test-Path -LiteralPath $wsG2)) '(g) -XpzOnly with -KbNativePath must not create the workspace folder'

    # (e) An invalid -KbName exits 2 and creates nothing.
    foreach ($badName in @('Sample-Kb', 'Sample Kb')) {
        $wsE = Join-Path $tempRoot ('ws-e-{0}' -f [guid]::NewGuid().ToString('N'))
        $runE = Invoke-ChildScript -Path $scaffolder -Arguments @('-WorkspaceRoot', $wsE, '-KbName', $badName)
        Assert-True ($runE.ExitCode -eq 2) "(e) -KbName '$badName' must exit 2; exit=$($runE.ExitCode), output=$($runE.Output -join ' | ')"
        Assert-True (-not (Test-Path -LiteralPath $wsE)) "(e) -KbName '$badName' must not create the workspace folder"
    }

    # (f) The scaffolder belongs to the signed setup contract surface.
    $manifest = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'skills/mimir-lite/workflows/setup/setup-contract.manifest.json')) | ConvertFrom-Json
    Assert-True (@($manifest.include) -contains 'skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1') '(f) setup-contract.manifest.json must include New-MimirKbWorkspace.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw ("New-MimirKbWorkspace self-test failed:`n - " + ($failures -join "`n - "))
}
Write-Output 'NEW_MIMIR_KB_WORKSPACE_SELFTEST_OK'
