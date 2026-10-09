#requires -Version 7.4
<#
.SYNOPSIS
    Advisory gate: a shared script changed in the diff whose contract is
    documented in a SKILL.md / quality-checklist.md that was NOT touched.

.DESCRIPTION
    Mechanical support for the "Documentation comparison" step of
    13-pre-push-review.md for the cross-cutting-skill case: a shared
    wrapper/engine/helper is usually documented in more than one skill (the
    owner plus skills that consume it). When a change alters the script but
    only touches the owning skill (or none at all), the other skills that
    describe that same script's contract/parameters/checklist can go stale
    without appearing in the diff.

    For each shared script (skills/mimir-lite/scripts/*.ps1|*.py or
    skills/mimir-delegate/scripts/*.ps1|*.py) in the BaseRef..HEAD interval,
    it looks for the script's base name (as a word) in every SKILL.md,
    quality-checklist.md, and skills/mimir-lite/workflows/*.md in the
    repository. Every document that cites the script and
    is NOT in the diff becomes a CANDIDATE for documentation comparison.

    Advisory: severity 'warn'; findings go into agentWarnings and the
    semantic phase confronts each candidate (update the contract/checklist or
    justify that the change does not affect that skill). Does not prove
    alignment nor fail on its own.

.PARAMETER RootPath
    Repository root. Default: parent of tools/.

.PARAMETER BaseRef
    Base reference of the BaseRef..HEAD interval. Default: origin/main.

.PARAMETER ChangedFiles
    Files changed in the interval. When empty, the gate computes it via git diff
    BaseRef..HEAD.

.PARAMETER MaxFindings
    Cap on reported candidates. Default: 30.

.PARAMETER AsJson
    Emits structured diagnostic in JSON.
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,

    [string]$BaseRef = 'origin/main',

    [AllowEmptyCollection()]
    [string[]]$ChangedFiles = @(),

    [ValidateRange(1, 500)]
    [int]$MaxFindings = 30,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-RepoGit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git -C $RepositoryRoot @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = @()
    if ($null -ne $output) {
        $lines = @($output | ForEach-Object { $_.ToString() })
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines    = $lines
        Text     = ($lines -join [Environment]::NewLine)
    }
}

function Normalize-RepoPath {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path)
    return (($Path -replace '\\', '/').Trim())
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

# Confirms the base ref exists (no automatic fallback).
$refCheck = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('rev-parse', '--verify', $BaseRef)
if ($refCheck.ExitCode -ne 0) {
    throw ("Base ref '{0}' not found; run git fetch origin or pass a valid -BaseRef." -f $BaseRef)
}

$normalizedChangedFiles = @($ChangedFiles |
    ForEach-Object { Normalize-RepoPath -Path $_ } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique)
if ($normalizedChangedFiles.Count -eq 0) {
    $changedResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', '--name-only', "$BaseRef..HEAD")
    if ($changedResult.ExitCode -ne 0) {
        throw ("Failed to list changed files in {0}..HEAD: {1}" -f $BaseRef, $changedResult.Text)
    }
    $normalizedChangedFiles = @($changedResult.Lines |
        ForEach-Object { Normalize-RepoPath -Path $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique)
}

$changedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($cf in $normalizedChangedFiles) { [void]$changedSet.Add($cf) }

# Shared scripts changed in the interval.
$changedScripts = @($normalizedChangedFiles | Where-Object { $_ -match '^skills/(?:mimir-lite|mimir-delegate)/scripts/[^/]+\.(ps1|py)$' })

$findings = [System.Collections.Generic.List[object]]::new()
$truncated = $false

if ($changedScripts.Count -gt 0) {
    # Target documents: SKILL.md and quality-checklist.md, outside .git/,
    # plus skills/mimir-lite/workflows/*.md — the workflow docs that replaced the
    # old per-skill SKILL.md files as the usual place a script's usage gets documented.
    $docFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'SKILL.md' -or $_.Name -eq 'quality-checklist.md') -and
            $_.FullName -notmatch '[\\/]\.git[\\/]'
        })
    $workflowsRoot = Join-Path $resolvedRoot 'skills/mimir-lite/workflows'
    if (Test-Path -LiteralPath $workflowsRoot -PathType Container) {
        $docFiles = @($docFiles) + @(Get-ChildItem -LiteralPath $workflowsRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)
    }

    # Pre-reads each doc once (full text + lines).
    $docCache = [System.Collections.Generic.List[object]]::new()
    foreach ($docFile in $docFiles) {
        $relDoc = Normalize-RepoPath -Path ([System.IO.Path]::GetRelativePath($resolvedRoot, $docFile.FullName))
        $lines = @()
        try {
            $lines = @([System.IO.File]::ReadAllLines($docFile.FullName))
        } catch {
            continue
        }
        $docCache.Add([pscustomobject]@{
            RelPath = $relDoc
            Lines   = $lines
            InDiff  = $changedSet.Contains($relDoc)
        })
    }

    foreach ($scriptPath in $changedScripts) {
        if ($truncated) { break }

        $baseName = Split-Path -Leaf $scriptPath
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
        # Script name as a word: '-' is not a word character, so the extension
        # suffix (.ps1/.py) or text boundary delimits it correctly.
        $stemRegex = [regex]::new('(?<![A-Za-z0-9_])' + [regex]::Escape($stem) + '(?![A-Za-z0-9_])')

        foreach ($doc in $docCache) {
            if ($truncated) { break }
            if ($doc.InDiff) { continue }

            $firstLine = 0
            for ($i = 0; $i -lt $doc.Lines.Count; $i++) {
                if ($stemRegex.IsMatch($doc.Lines[$i])) {
                    $firstLine = $i + 1
                    break
                }
            }
            if ($firstLine -eq 0) { continue }

            if ($findings.Count -ge $MaxFindings) {
                $truncated = $true
                break
            }

            $findings.Add([pscustomobject][ordered]@{
                code     = 'SHARED_SCRIPT_SKILL_DOC_NOT_IN_DIFF'
                severity = 'warn'
                path     = ('{0}:{1}' -f $doc.RelPath, $firstLine)
                message  = ("shared script '{0}' changed in the interval, but '{1}' (which documents it) is not in the diff — compare the contract/checklist or justify that the change does not affect this skill" -f $scriptPath, $doc.RelPath)
            })
        }
    }
}

$status = if ($findings.Count -gt 0) { 'warn' } else { 'pass' }

$result = [ordered]@{
    status         = $status
    baseRef        = $BaseRef
    changedScripts = @($changedScripts)
    candidateCount = $findings.Count
    truncated      = $truncated
    findings       = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    Write-Output ("STATUS={0}" -f $status)
    Write-Output ("CHANGED_SCRIPTS={0}" -f ($changedScripts -join ', '))
    Write-Output ("CANDIDATE_COUNT={0}" -f $findings.Count)
    foreach ($finding in @($findings)) {
        Write-Output ("SHARED_SCRIPT_SKILL_DOC_NOT_IN_DIFF: {0}: {1}" -f $finding.path, $finding.message)
    }
    if ($truncated) {
        Write-Output 'CANDIDATES_TRUNCATED=true'
    }
}

exit 0
