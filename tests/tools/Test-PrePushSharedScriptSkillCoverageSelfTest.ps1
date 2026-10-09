#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for Test-PrePushSharedScriptSkillCoverage.ps1.

.DESCRIPTION
    Builds a temporary git repository with a changed shared script and
    four skill documents. Confirms:
      - a skill that cites the script and is NOT in the diff -> candidate (cross-cutting);
      - a quality-checklist.md that cites the script and is NOT in the diff -> candidate;
      - a skill that cites the script but IS in the diff (owner touched) -> not a candidate;
      - a skill that does NOT cite the script -> not a candidate;
      - skills/mimir-lite/workflows/*.md that cites the script and is NOT in the diff -> candidate.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools') 'Test-PrePushSharedScriptSkillCoverage.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-shared-script-skill-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Utf8NoBomEncodingSupport.ps1')
$utf8NoBom = Get-Utf8NoBomEncoding
function Write-TempFile {
    param([string]$RelativePath, [string]$Content)
    $full = Join-Path $tempRoot $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
}

function Invoke-TempGit {
    param([string[]]$Arguments)
    $output = & git -C $tempRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("git {0} failed: {1}" -f ($Arguments -join ' '), (($output | Out-String).Trim()))
    }
    return $output
}

try {
    [void](Invoke-TempGit @('init', '-q'))
    [void](Invoke-TempGit @('config', 'user.email', 'selftest@example.com'))
    [void](Invoke-TempGit @('config', 'user.name', 'Self Test'))
    [void](Invoke-TempGit @('config', 'commit.gpgsign', 'false'))

    $scriptName = 'Invoke-DemoSharedEngine'
    Write-TempFile -RelativePath ("skills/mimir-lite/scripts/{0}.ps1" -f $scriptName) -Content "param([string]`$X)`n# v1`n"

    # Owner skill (will be touched in this workstream).
    Write-TempFile -RelativePath 'skill-dona/SKILL.md' -Content "# Owner`nContract for ``$scriptName`` documented here.`n"
    # Cross-cutting skill that consumes the script (will NOT be touched) -> candidate.
    Write-TempFile -RelativePath 'skill-transversal/SKILL.md' -Content "# Cross-cutting`nThis skill calls ``$scriptName`` in the import flow.`n"
    # Cross-cutting quality-checklist that cites the script (will NOT be touched) -> candidate.
    Write-TempFile -RelativePath 'skill-transversal/quality-checklist.md' -Content "# Checklist`n- [ ] check the output of ``$scriptName```n"
    # Skill that does NOT cite the script -> never a candidate.
    Write-TempFile -RelativePath 'skill-outra/SKILL.md' -Content "# Other`nNothing to do with the engine.`n"
    # Workflow doc (skills/mimir-lite/workflows/*.md) that cites the script and is
    # NOT touched -> candidate, since workflow docs replaced per-skill SKILL.md as
    # the usual place a script's usage gets documented.
    Write-TempFile -RelativePath 'skills/mimir-lite/workflows/demo.md' -Content "# Demo workflow`nCalls ``$scriptName`` during setup.`n"

    [void](Invoke-TempGit @('add', '-A'))
    [void](Invoke-TempGit @('commit', '-q', '-m', 'base'))
    $baseSha = (Invoke-TempGit @('rev-parse', 'HEAD') | Out-String).Trim()

    # HEAD: changes the script AND the owner skill (this enters the diff).
    Write-TempFile -RelativePath ("skills/mimir-lite/scripts/{0}.ps1" -f $scriptName) -Content "param([string]`$X, [string]`$Y)`n# v2 new parameter`n"
    Write-TempFile -RelativePath 'skill-dona/SKILL.md' -Content "# Owner`nContract for ``$scriptName`` documented here (now with -Y).`n"

    [void](Invoke-TempGit @('add', '-A'))
    [void](Invoke-TempGit @('commit', '-q', '-m', 'change engine and owner skill'))

    $output = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -BaseRef $baseSha -AsJson 2>&1
    $exitCode = $LASTEXITCODE
    $jsonText = ($output | Out-String).Trim()
    $result = $jsonText | ConvertFrom-Json

    if ($exitCode -ne 0) {
        throw "gate should exit with 0 (advisory); got $exitCode. Output: $jsonText"
    }
    if ($result.status -ne 'warn') {
        throw "status should be 'warn'; got '$($result.status)'. Output: $jsonText"
    }

    $candidatePaths = @($result.findings | ForEach-Object { $_.path })

    if (@($candidatePaths | Where-Object { $_ -like 'skill-transversal/SKILL.md:*' }).Count -eq 0) {
        throw "skill-transversal/SKILL.md (cites the script, outside the diff) should become a candidate; candidates: $($candidatePaths -join ', ')"
    }
    if (@($candidatePaths | Where-Object { $_ -like 'skill-transversal/quality-checklist.md:*' }).Count -eq 0) {
        throw "skill-transversal/quality-checklist.md should become a candidate; candidates: $($candidatePaths -join ', ')"
    }
    if (@($candidatePaths | Where-Object { $_ -like 'skills/mimir-lite/workflows/demo.md:*' }).Count -eq 0) {
        throw "skills/mimir-lite/workflows/demo.md (cites the script, outside the diff) should become a candidate; candidates: $($candidatePaths -join ', ')"
    }
    if (@($candidatePaths | Where-Object { $_ -like 'skill-dona/SKILL.md:*' }).Count -ne 0) {
        throw "skill-dona/SKILL.md is in the diff and should NOT become a candidate; candidates: $($candidatePaths -join ', ')"
    }
    if (@($candidatePaths | Where-Object { $_ -like 'skill-outra/SKILL.md:*' }).Count -ne 0) {
        throw "skill-outra/SKILL.md does not cite the script and should NOT become a candidate; candidates: $($candidatePaths -join ', ')"
    }

    Write-Output 'OK: Test-PrePushSharedScriptSkillCoverageSelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
