#requires -Version 7.4
<#
.SYNOPSIS
    Runs the pre-push routine's initial mechanical checks.

.DESCRIPTION
    Coordinates git context (pending commits, diff --check, changed files),
    delegates PowerShell parse to tools/Test-PsScriptsParse.ps1 (covers skills/,
    tools/ and tests/), Python parse without bytecode to tools/Test-PyScriptsParse.ps1,
    and classifies diff files as input for the agent's semantic phase.

    Does not replace a cross-coherence search, the layered rule for long skills,
    nor the final report to the user — see 13-pre-push-review.md (AGENTS.md points to that file).
    Emits informational warnings if the branch is not main or if the working
    tree has uncommitted changes outside the BaseRef..HEAD interval. With
    commitsBehind > 0, sets pushReadiness=blocked and marks the interval diff
    as diagnostic only (without failing parse/whitespace).

.PARAMETER RootPath
    Repository root. Default: parent of tools/.

.PARAMETER BaseRef
    Single reference for the analyzed interval: pending commits, count,
    changed files, and diff --check always use BaseRef..HEAD. Default:
    origin/main (local copy from the last fetch; since the usual last push to main).
    When BaseRef is left at its default ('origin/main') and that ref cannot be
    resolved (for example, no 'origin' remote configured on this clone), the
    script falls back to the local 'main' branch when it exists, and records
    the fallback in agentWarnings and in the JSON git.baseRefFallbackApplied
    field. An explicitly passed -BaseRef that does not exist still fails with a
    clear message and no fallback. With an existing but stale ref relative to
    the remote, the interval may overestimate pending commits; the agent
    should run git fetch origin before the routine when it needs to compare
    against the current remote (see AGENTS.md). The branch's upstream only
    appears in the JSON as informational context.

.PARAMETER AsJson
    Emits structured diagnostic in JSON.

.PARAMETER SkipParse
    Skips invoking Test-PsScriptsParse.ps1 (exceptional use).
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,

    [string]$BaseRef = 'origin/main',

    [switch]$AsJson,

    [switch]$SkipParse
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PrePushGitSupport.ps1')

function Get-RelativeDisplayPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    return [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($BasePath),
        [System.IO.Path]::GetFullPath($TargetPath)
    )
}

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

function Test-GitRefExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$Ref
    )

    $result = Invoke-RepoGit -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', '--verify', $Ref)
    return ($result.ExitCode -eq 0)
}

function Resolve-GitRepositoryContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartPath
    )

    $topLevelResult = Invoke-RepoGit -RepositoryRoot $StartPath -Arguments @('rev-parse', '--show-toplevel')
    if ($topLevelResult.ExitCode -ne 0) {
        throw ("Could not resolve a git repository from '{0}'. Check the path or use git rev-parse --show-toplevel manually. Detail: {1}" -f $StartPath, $topLevelResult.Text)
    }

    $repositoryRoot = $topLevelResult.Lines[0].Trim()
    $gitDirResult = Invoke-RepoGit -RepositoryRoot $repositoryRoot -Arguments @('rev-parse', '--git-dir')
    $gitDir = $null
    if ($gitDirResult.ExitCode -eq 0 -and $gitDirResult.Lines.Count -gt 0) {
        $gitDir = $gitDirResult.Lines[0].Trim()
    }

    return [pscustomobject]@{
        RepositoryRoot = $repositoryRoot
        GitDir         = $gitDir
    }
}

function Get-PropOrDefault {
    # Safe access to a property of an object from ConvertFrom-Json: under
    # Set-StrictMode -Version Latest, reading a nonexistent property throws. Used to
    # project optional gate fields without coupling the orchestrator to a
    # specific version of the gate's JSON.
    param(
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Get-ChangedFileKind {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $normalized = ($RelativePath -replace '\\', '/').Trim()

    if ($normalized -match '^skills/(?:mimir-lite|mimir-delegate)/scripts/.+\.(ps1|py)$') {
        return 'scripts'
    }
    if ($normalized -match '^tools/.+\.(ps1|py)$') {
        return 'toolsScripts'
    }
    if ($normalized -match '\.example\.ps1$') {
        return 'examples'
    }
    if ($normalized -match '/SKILL\.md$') {
        return 'skills'
    }
    if ($normalized -match '^\.github/') {
        return 'workflows'
    }
    if ($normalized -match '^[^/]+\.md$') {
        return 'baseDocs'
    }

    return 'other'
}

function Add-ChangedFilesByKind {
    param(
        [AllowEmptyCollection()]
        [string[]]$RelativePaths = @()
    )

    $byKind = [ordered]@{
        scripts   = @()
        toolsScripts = @()
        skills    = @()
        baseDocs  = @()
        examples  = @()
        workflows = @()
        other     = @()
    }

    foreach ($relativePath in @($RelativePaths | Sort-Object)) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }

        $kind = Get-ChangedFileKind -RelativePath $relativePath
        $byKind[$kind] = @($byKind[$kind] + $relativePath)
    }

    return $byKind
}

function Get-WorkingTreeDiagnostics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [int]$MaxSamplePaths = 15
    )

    $statusResult = Invoke-RepoGit -RepositoryRoot $RepositoryRoot -Arguments @('status', '--porcelain')
    if ($statusResult.ExitCode -ne 0) {
        throw ("Failed to read the working tree (git status --porcelain). Detail: {0}" -f $statusResult.Text)
    }

    $untrackedFiles = [System.Collections.Generic.List[string]]::new()
    $dirtyTrackedFiles = [System.Collections.Generic.List[string]]::new()

    foreach ($line in @($statusResult.Lines)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) {
            continue
        }

        $status = $line.Substring(0, 2)
        $path = $line.Substring(3).Trim()
        if ($path -match ' -> ') {
            $path = ($path -split ' -> ', 2)[1].Trim()
        }

        if ($status -eq '??') {
            [void]$untrackedFiles.Add($path)
        } else {
            [void]$dirtyTrackedFiles.Add($path)
        }
    }

    $untrackedAll = @($untrackedFiles)
    $dirtyTrackedAll = @($dirtyTrackedFiles)
    $isClean = ($untrackedAll.Count -eq 0 -and $dirtyTrackedAll.Count -eq 0)

    return [pscustomobject]@{
        Status              = $(if ($isClean) { 'clean' } else { 'dirty' })
        UntrackedCount      = $untrackedAll.Count
        DirtyTrackedCount   = $dirtyTrackedAll.Count
        UntrackedFiles      = @($untrackedAll | Select-Object -First $MaxSamplePaths)
        DirtyTrackedFiles   = @($dirtyTrackedAll | Select-Object -First $MaxSamplePaths)
        UntrackedTruncated  = ($untrackedAll.Count -gt $MaxSamplePaths)
        DirtyTrackedTruncated = ($dirtyTrackedAll.Count -gt $MaxSamplePaths)
    }
}

$startPath = (Resolve-Path -LiteralPath $RootPath).Path
$gitContext = Resolve-GitRepositoryContext -StartPath $startPath
$resolvedRoot = $gitContext.RepositoryRoot
$resolvedGitDir = $gitContext.GitDir

$branchResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
if ($branchResult.ExitCode -ne 0) {
    throw 'Could not resolve the current branch.'
}
$currentBranch = $branchResult.Lines[0].Trim()

$expectedBranch = 'main'
$onExpectedBranch = ($currentBranch -ceq $expectedBranch)
$workingTree = Get-WorkingTreeDiagnostics -RepositoryRoot $resolvedRoot

$upstreamResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('rev-parse', '--abbrev-ref', '@{upstream}')
$upstreamRef = $null
$upstreamConfigured = ($upstreamResult.ExitCode -eq 0)
if ($upstreamConfigured) {
    $upstreamRef = $upstreamResult.Lines[0].Trim()
}

$defaultBaseRef = 'origin/main'
$localMainFallbackRef = 'main'
$effectiveBaseRef = $BaseRef
$baseRefFallbackApplied = $false
if (-not (Test-GitRefExists -RepositoryRoot $resolvedRoot -Ref $effectiveBaseRef)) {
    # Tolerate a missing 'origin' remote: only the untouched default falls back,
    # so an explicit -BaseRef that does not exist still fails loudly below.
    if ($BaseRef -eq $defaultBaseRef -and (Test-GitRefExists -RepositoryRoot $resolvedRoot -Ref $localMainFallbackRef)) {
        $effectiveBaseRef = $localMainFallbackRef
        $baseRefFallbackApplied = $true
    } else {
        throw ("Base ref '{0}' not found. To measure local commits not yet pushed to the remote, confirm that origin/main exists (e.g.: git fetch origin) or pass -BaseRef with a valid ref. The automatic fallback to local 'main' only applies when -BaseRef was left at its default ('{1}') and 'main' exists locally." -f $BaseRef, $defaultBaseRef)
    }
}

$range = "$effectiveBaseRef..HEAD"
$commitLogResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('log', $range, '--oneline')
if ($commitLogResult.ExitCode -ne 0) {
    throw "Failed to list pending commits for the interval $range."
}

$pendingCommits = @($commitLogResult.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$aheadRange = "${effectiveBaseRef}..HEAD"
$behindRange = "HEAD..${effectiveBaseRef}"
$aheadResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('rev-list', '--count', $aheadRange)
$behindResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('rev-list', '--count', $behindRange)

$commitsAhead = 0
$commitsBehind = 0
if ($aheadResult.ExitCode -eq 0 -and $aheadResult.Lines.Count -gt 0) {
    $commitsAhead = [int]$aheadResult.Lines[0]
}
if ($behindResult.ExitCode -eq 0 -and $behindResult.Lines.Count -gt 0) {
    $commitsBehind = [int]$behindResult.Lines[0]
}

$changedFiles = @()
$whitespaceStatus = 'clean'
$whitespaceIssues = @()
$whitespaceRemainingIssues = @()
$whitespaceRawExitCode = 0

if ($commitsAhead -gt 0) {
    $nameOnlyResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', '--name-only', $range)
    if ($nameOnlyResult.ExitCode -ne 0) {
        throw "Failed to list changed files for the interval $range."
    }
    $changedFiles = @($nameOnlyResult.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $whitespaceResult = Invoke-PrePushGitUtf8 -RepositoryRoot $resolvedRoot -Arguments @('diff', '--check', $range)
    $whitespaceRawExitCode = $whitespaceResult.ExitCode
    $whitespaceIssues = @($whitespaceResult.Lines)
    if ($whitespaceRawExitCode -ne 0 -or $whitespaceIssues.Count -gt 0) {
        $whitespaceStatus = 'issues-found'
        $whitespaceRemainingIssues = @($whitespaceIssues)
        if ($whitespaceRemainingIssues.Count -eq 0) {
            $whitespaceRemainingIssues = @('Unclassified git diff --check failure; failed closed.')
        }
    }
}

$changedFilesByKind = Add-ChangedFilesByKind -RelativePaths $changedFiles

$parseGate = [ordered]@{
    script     = 'tools/Test-PsScriptsParse.ps1'
    status     = 'skipped'
    exitCode   = $null
    fileCount  = $null
    errorCount = $null
    findings   = @()
}

$pythonParseGate = [ordered]@{
    script     = 'tools/Test-PyScriptsParse.ps1'
    status     = 'skipped'
    exitCode   = $null
    fileCount  = $null
    errorCount = $null
    findings   = @()
}

$traceabilityCoverageGate = [ordered]@{
    script   = 'tools/Test-PrePushTraceabilityCoverage.ps1'
    status   = 'skipped'
    findings = @()
}

$unexpectedCharGate = [ordered]@{
    script   = 'tools/Test-GeneXusUnexpectedCharacter.ps1'
    status   = 'skipped'
    findings = @()
}

$newTokenPropagationGate = [ordered]@{
    script              = 'tools/Test-PrePushNewTokenPropagation.ps1'
    status              = 'skipped'
    candidateCount      = 0
    classCounts         = $null
    truncated           = $false
    truncatedProseCount = 0
    findings            = @()
}

$sharedScriptSkillGate = [ordered]@{
    script   = 'tools/Test-PrePushSharedScriptSkillCoverage.ps1'
    status   = 'skipped'
    findings = @()
}

$gateEnumParityGate = [ordered]@{
    script   = 'tools/Test-PrePushGateEnumerationParity.ps1'
    status   = 'skipped'
    findings = @()
}

$backendEnumParityGate = [ordered]@{
    script   = 'tools/Test-PrePushBackendEnumerationParity.ps1'
    status   = 'skipped'
    findings = @()
}

$mechanicalFailures = [System.Collections.Generic.List[string]]::new()

if (-not $SkipParse) {
    $parseScript = Join-Path $PSScriptRoot 'Test-PsScriptsParse.ps1'
    if (-not (Test-Path -LiteralPath $parseScript -PathType Leaf)) {
        throw "Parse script not found: $parseScript"
    }

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $parseOutput = & $parseScript -RootPath $resolvedRoot -AsJson 2>&1
    $parseExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction

    $parseJsonText = ($parseOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $parseObject = $null
    if (-not [string]::IsNullOrWhiteSpace($parseJsonText)) {
        $parseObject = $parseJsonText | ConvertFrom-Json
    }

    $parseGate.status = if ($parseExitCode -eq 0) { 'pass' } else { 'fail' }
    $parseGate.exitCode = $parseExitCode
    if ($null -ne $parseObject) {
        $parseGate.fileCount = $parseObject.fileCount
        $parseGate.errorCount = $parseObject.errorCount
        $parseGate.findings = @($parseObject.findings)
    }

    if ($parseExitCode -ne 0) {
        [void]$mechanicalFailures.Add('parse')
    }

    $pythonParseScript = Join-Path $PSScriptRoot 'Test-PyScriptsParse.ps1'
    if (Test-Path -LiteralPath $pythonParseScript -PathType Leaf) {
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $pythonParseOutput = & $pythonParseScript -RootPath $resolvedRoot -AsJson 2>&1
        $pythonParseExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorAction

        $pythonParseJsonText = ($pythonParseOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        $pythonParseObject = $null
        if (-not [string]::IsNullOrWhiteSpace($pythonParseJsonText)) {
            $pythonParseObject = $pythonParseJsonText | ConvertFrom-Json
        }

        $pythonParseGate.status = if ($pythonParseExitCode -eq 0) { 'pass' } else { 'fail' }
        $pythonParseGate.exitCode = $pythonParseExitCode
        if ($null -ne $pythonParseObject) {
            $pythonParseGate.fileCount = $pythonParseObject.fileCount
            $pythonParseGate.errorCount = $pythonParseObject.errorCount
            $pythonParseGate.findings = @($pythonParseObject.findings)
        }

        if ($pythonParseExitCode -ne 0) {
            [void]$mechanicalFailures.Add('pythonParse')
        }
    }
}

if ($whitespaceStatus -ne 'clean') {
    [void]$mechanicalFailures.Add('whitespace')
}

$traceabilityCoverageScript = Join-Path $PSScriptRoot 'Test-PrePushTraceabilityCoverage.ps1'
if (Test-Path -LiteralPath $traceabilityCoverageScript -PathType Leaf) {
    $traceabilityOutput = & $traceabilityCoverageScript -RootPath $resolvedRoot -BaseRef $effectiveBaseRef -ChangedFiles $changedFiles -AsJson 2>&1
    $traceabilityExitCode = $LASTEXITCODE
    $traceabilityJsonText = ($traceabilityOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $traceabilityObject = $null
    if (-not [string]::IsNullOrWhiteSpace($traceabilityJsonText)) {
        $traceabilityObject = $traceabilityJsonText | ConvertFrom-Json
    }

    if ($traceabilityExitCode -eq 0 -and $null -ne $traceabilityObject) {
        $traceabilityCoverageGate.status = $traceabilityObject.status
        $traceabilityCoverageGate.findings = @($traceabilityObject.findings)
    } else {
        $traceabilityCoverageGate.status = 'warn'
        $traceabilityCoverageGate.findings = @([pscustomobject][ordered]@{
            code     = 'TRACEABILITY_COVERAGE_SCRIPT_ERROR'
            severity = 'warn'
            path     = 'tools/Test-PrePushTraceabilityCoverage.ps1'
            message  = "Advisory failure while running Test-PrePushTraceabilityCoverage.ps1: $traceabilityJsonText"
        })
    }
}

$unexpectedCharScript = Join-Path $PSScriptRoot 'Test-GeneXusUnexpectedCharacter.ps1'
if (Test-Path -LiteralPath $unexpectedCharScript -PathType Leaf) {
    $unexpectedCharOutput = & $unexpectedCharScript -RootPath $resolvedRoot -BaseRef $effectiveBaseRef -ChangedFiles $changedFiles -AsJson 2>&1
    $unexpectedCharExitCode = $LASTEXITCODE
    $unexpectedCharJsonText = ($unexpectedCharOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $unexpectedCharObject = $null
    if (-not [string]::IsNullOrWhiteSpace($unexpectedCharJsonText)) {
        $unexpectedCharObject = $unexpectedCharJsonText | ConvertFrom-Json
    }

    if ($unexpectedCharExitCode -eq 0 -and $null -ne $unexpectedCharObject) {
        $unexpectedCharGate.status = $unexpectedCharObject.status
        $unexpectedCharGate.findings = @($unexpectedCharObject.findings)
    } else {
        $unexpectedCharGate.status = 'warn'
        $unexpectedCharGate.findings = @([pscustomobject][ordered]@{
            code     = 'UNEXPECTED_CHARACTER_SCRIPT_ERROR'
            severity = 'warn'
            path     = 'tools/Test-GeneXusUnexpectedCharacter.ps1'
            message  = "Advisory failure while running Test-GeneXusUnexpectedCharacter.ps1: $unexpectedCharJsonText"
        })
    }
}

$newTokenPropagationScript = Join-Path $PSScriptRoot 'Test-PrePushNewTokenPropagation.ps1'
if (Test-Path -LiteralPath $newTokenPropagationScript -PathType Leaf) {
    $newTokenOutput = & $newTokenPropagationScript -RootPath $resolvedRoot -BaseRef $effectiveBaseRef -ChangedFiles $changedFiles -AsJson 2>&1
    $newTokenExitCode = $LASTEXITCODE
    $newTokenJsonText = ($newTokenOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $newTokenObject = $null
    if (-not [string]::IsNullOrWhiteSpace($newTokenJsonText)) {
        $newTokenObject = $newTokenJsonText | ConvertFrom-Json
    }

    if ($newTokenExitCode -eq 0 -and $null -ne $newTokenObject) {
        $newTokenPropagationGate.status = $newTokenObject.status
        $newTokenPropagationGate.findings = @($newTokenObject.findings)
        # The -MaxFindings cap truncates only the 'prose' class. Without projecting these
        # fields, the reviewer (especially the semantic-only one, which only has the
        # dossier) sees the listed candidates and does not know how many were discarded —
        # and 13 (step 2) promises that truncatedProseCount reports exactly that.
        $newTokenPropagationGate.candidateCount = [int](Get-PropOrDefault $newTokenObject 'candidateCount' 0)
        $newTokenPropagationGate.classCounts = (Get-PropOrDefault $newTokenObject 'classCounts' $null)
        $newTokenPropagationGate.truncated = [bool](Get-PropOrDefault $newTokenObject 'truncated' $false)
        $newTokenPropagationGate.truncatedProseCount = [int](Get-PropOrDefault $newTokenObject 'truncatedProseCount' 0)
    } else {
        $newTokenPropagationGate.status = 'warn'
        $newTokenPropagationGate.findings = @([pscustomobject][ordered]@{
            code     = 'NEW_TOKEN_PROPAGATION_SCRIPT_ERROR'
            severity = 'warn'
            path     = 'tools/Test-PrePushNewTokenPropagation.ps1'
            message  = "Advisory failure while running Test-PrePushNewTokenPropagation.ps1: $newTokenJsonText"
        })
    }
}

$sharedScriptSkillScript = Join-Path $PSScriptRoot 'Test-PrePushSharedScriptSkillCoverage.ps1'
if (Test-Path -LiteralPath $sharedScriptSkillScript -PathType Leaf) {
    $sharedScriptOutput = & $sharedScriptSkillScript -RootPath $resolvedRoot -BaseRef $effectiveBaseRef -ChangedFiles $changedFiles -AsJson 2>&1
    $sharedScriptExitCode = $LASTEXITCODE
    $sharedScriptJsonText = ($sharedScriptOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $sharedScriptObject = $null
    if (-not [string]::IsNullOrWhiteSpace($sharedScriptJsonText)) {
        $sharedScriptObject = $sharedScriptJsonText | ConvertFrom-Json
    }

    if ($sharedScriptExitCode -eq 0 -and $null -ne $sharedScriptObject) {
        $sharedScriptSkillGate.status = $sharedScriptObject.status
        $sharedScriptSkillGate.findings = @($sharedScriptObject.findings)
    } else {
        $sharedScriptSkillGate.status = 'warn'
        $sharedScriptSkillGate.findings = @([pscustomobject][ordered]@{
            code     = 'SHARED_SCRIPT_SKILL_COVERAGE_SCRIPT_ERROR'
            severity = 'warn'
            path     = 'tools/Test-PrePushSharedScriptSkillCoverage.ps1'
            message  = "Advisory failure while running Test-PrePushSharedScriptSkillCoverage.ps1: $sharedScriptJsonText"
        })
    }
}

$gateEnumParityScript = Join-Path $PSScriptRoot 'Test-PrePushGateEnumerationParity.ps1'
if (Test-Path -LiteralPath $gateEnumParityScript -PathType Leaf) {
    $gateEnumOutput = & $gateEnumParityScript -RootPath $resolvedRoot -BaseRef $effectiveBaseRef -ChangedFiles $changedFiles -AsJson 2>&1
    $gateEnumExitCode = $LASTEXITCODE
    $gateEnumJsonText = ($gateEnumOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $gateEnumObject = $null
    if (-not [string]::IsNullOrWhiteSpace($gateEnumJsonText)) {
        $gateEnumObject = $gateEnumJsonText | ConvertFrom-Json
    }

    if ($gateEnumExitCode -eq 0 -and $null -ne $gateEnumObject) {
        $gateEnumParityGate.status = $gateEnumObject.status
        $gateEnumParityGate.findings = @($gateEnumObject.findings)
    } else {
        $gateEnumParityGate.status = 'warn'
        $gateEnumParityGate.findings = @([pscustomobject][ordered]@{
            code     = 'GATE_ENUMERATION_PARITY_SCRIPT_ERROR'
            severity = 'warn'
            path     = 'tools/Test-PrePushGateEnumerationParity.ps1'
            message  = "Advisory failure while running Test-PrePushGateEnumerationParity.ps1: $gateEnumJsonText"
        })
    }
}

$backendEnumParityScript = Join-Path $PSScriptRoot 'Test-PrePushBackendEnumerationParity.ps1'
if (Test-Path -LiteralPath $backendEnumParityScript -PathType Leaf) {
    $backendEnumOutput = & $backendEnumParityScript -RootPath $resolvedRoot -BaseRef $effectiveBaseRef -ChangedFiles $changedFiles -AsJson 2>&1
    $backendEnumExitCode = $LASTEXITCODE
    $backendEnumJsonText = ($backendEnumOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $backendEnumObject = $null
    if (-not [string]::IsNullOrWhiteSpace($backendEnumJsonText)) {
        $backendEnumObject = $backendEnumJsonText | ConvertFrom-Json
    }

    if ($backendEnumExitCode -eq 0 -and $null -ne $backendEnumObject) {
        $backendEnumParityGate.status = $backendEnumObject.status
        $backendEnumParityGate.findings = @($backendEnumObject.findings)
    } else {
        $backendEnumParityGate.status = 'warn'
        $backendEnumParityGate.findings = @([pscustomobject][ordered]@{
            code     = 'BACKEND_ENUMERATION_PARITY_SCRIPT_ERROR'
            severity = 'warn'
            path     = 'tools/Test-PrePushBackendEnumerationParity.ps1'
            message  = "Advisory failure while running Test-PrePushBackendEnumerationParity.ps1: $backendEnumJsonText"
        })
    }
}

$overallStatus = if ($mechanicalFailures.Count -eq 0) { 'pass' } else { 'fail' }

$pushReadiness = if ($commitsBehind -gt 0) { 'blocked' } else { 'ok' }
$intervalDiffDiagnosticOnly = ($commitsBehind -gt 0)

$agentOperationalReminders = @(
    'Before the routine, git fetch origin when origin/main must reflect the current remote; a missing ref and a stale ref are different cases; without fetch, commitsBehind can stay 0 while the real remote is already ahead.',
    'Parse (Test-PsScriptsParse.ps1) scans all of skills/, tools/, tests/ and every *.example.ps1, not just the interval diff.',
    'Python parse (Test-PyScriptsParse.ps1) uses AST and does not generate __pycache__/*.pyc.',
    'With commitsAhead=0 there is no diff in the interval; pre-push does not replace review of changes that only sit in the working tree (see worktree warnings).',
    'A mechanical exit 0 does not authorize a push: read PUSH_READINESS; with blocked, integrate the remote before pushing.',
    'With PUSH_READINESS=blocked, the interval diff/files are diagnostic only; the semantic phase over local commits is still mandatory.',
    'With SKILL.md in the diff, open the satellites referenced in the SKILL itself (quality-checklist, wwp-packaging, responsibilities-by-type) for the layered rule.'
)

$agentWarnings = [System.Collections.Generic.List[string]]::new()
$skillMdInDiff = @($changedFiles | Where-Object { $_ -match '/SKILL\.md$' })
if ($skillMdInDiff.Count -gt 0) {
    $skillSummary = if ($skillMdInDiff.Count -le 3) {
        ($skillMdInDiff -join ', ')
    } else {
        ('{0} (+{1} more)' -f $skillMdInDiff[0], ($skillMdInDiff.Count - 1))
    }
    [void]$agentWarnings.Add(
        ("SKILL.md changed in the interval ({0}): check the satellites referenced in the file itself (e.g. quality-checklist.md, wwp-packaging.md, responsibilities-by-type/) for the layered rule." -f $skillSummary)
    )
}
$publicTraceabilityTriggers = [System.Collections.Generic.List[string]]::new()
foreach ($changedPath in @($changedFiles)) {
    $normalizedChangedPath = ($changedPath -replace '\\', '/').Trim()
    if ($normalizedChangedPath -match '^skills/(?:mimir-lite|mimir-delegate)/scripts/.+\.(ps1|py|json)$' -or
        $normalizedChangedPath -match '^tools/.+\.(ps1|py|json)$' -or
        $normalizedChangedPath -match '^skills/(?:mimir-lite|mimir-delegate)/SKILL\.md$' -or
        $normalizedChangedPath -in @('README.md', 'skills/mimir-lite/references/02-operational-rules.md', 'skills/mimir-lite/references/08-agent-guide.md')) {
        $publicTraceabilityTriggers.Add($normalizedChangedPath)
    }
}
if ($publicTraceabilityTriggers.Count -gt 0) {
    $traceabilitySummary = if ($publicTraceabilityTriggers.Count -le 4) {
        ($publicTraceabilityTriggers -join ', ')
    } else {
        ('{0}, {1}, {2}, {3} (+{4} more)' -f $publicTraceabilityTriggers[0], $publicTraceabilityTriggers[1], $publicTraceabilityTriggers[2], $publicTraceabilityTriggers[3], ($publicTraceabilityTriggers.Count - 4))
    }
    [void]$agentWarnings.Add(
        ("Methodological or shared-engine change detected ({0}): explicitly assess whether 09-script-inventory.md needs to record the evolution; the term's presence in 09 is not enough, compare whether the description reflects the current scope." -f $traceabilitySummary)
    )
}
if ($baseRefFallbackApplied) {
    [void]$agentWarnings.Add(
        ("BaseRef default '{0}' not found (no 'origin' remote configured on this clone); falling back to local '{1}' as the base ref for this run." -f $defaultBaseRef, $localMainFallbackRef)
    )
}
if (-not $onExpectedBranch) {
    [void]$agentWarnings.Add(
        ("Current branch is '{0}'; this repository expects direct work on {1}." -f $currentBranch, $expectedBranch)
    )
}
if ($workingTree.Status -ne 'clean') {
    [void]$agentWarnings.Add(
        ("Working tree outside the commit interval: {0} tracked file(s) modified without a commit and {1} untracked; pre-push does not analyze these changes in BaseRef..HEAD." -f $workingTree.DirtyTrackedCount, $workingTree.UntrackedCount)
    )
}
if ($commitsBehind -gt 0) {
    [void]$agentWarnings.Add(
        ("Remote ({0}) is {1} commit(s) ahead of HEAD: the interval {2} and listed files are diagnostic only; push blocked until integrated. If there has been no fetch yet, git fetch origin; if commitsBehind persists, integrate (e.g.: git pull --rebase origin main) before pushing." -f $effectiveBaseRef, $commitsBehind, $range)
    )
}
foreach ($traceabilityFinding in @($traceabilityCoverageGate.findings)) {
    [void]$agentWarnings.Add(
        ("Advisory traceability coverage ({0}): {1}" -f $traceabilityFinding.code, $traceabilityFinding.message)
    )
}
foreach ($unexpectedCharFinding in @($unexpectedCharGate.findings)) {
    [void]$agentWarnings.Add(
        ("Unexpected character ({0}): {1}" -f $unexpectedCharFinding.code, $unexpectedCharFinding.message)
    )
}
if ($newTokenPropagationGate.truncated) {
    [void]$agentWarnings.Add(
        ("New term propagation: {0} candidate(s) of class 'prose' were DISCARDED by the -MaxFindings cap and do not appear in the listed candidates; non-prose ones never truncate. High prose noise can dilute a legitimate candidate — check the pairs in pairsConsidered before treating the list as exhaustive." -f $newTokenPropagationGate.truncatedProseCount)
    )
}
foreach ($newTokenFinding in @($newTokenPropagationGate.findings)) {
    [void]$agentWarnings.Add(
        ("New term propagation (advisory candidate) ({0}): {1} [{2}]" -f $newTokenFinding.code, $newTokenFinding.message, $newTokenFinding.path)
    )
}
foreach ($sharedScriptFinding in @($sharedScriptSkillGate.findings)) {
    [void]$agentWarnings.Add(
        ("Shared script in a cross-cutting skill (advisory candidate) ({0}): {1} [{2}]" -f $sharedScriptFinding.code, $sharedScriptFinding.message, $sharedScriptFinding.path)
    )
}
foreach ($gateEnumFinding in @($gateEnumParityGate.findings)) {
    [void]$agentWarnings.Add(
        ("Gate enumeration stale in the doc (advisory candidate) ({0}): {1} [{2}]" -f $gateEnumFinding.code, $gateEnumFinding.message, $gateEnumFinding.path)
    )
}
foreach ($backendEnumFinding in @($backendEnumParityGate.findings)) {
    [void]$agentWarnings.Add(
        ("Backend enumeration stale in the doc (advisory candidate) ({0}): {1} [{2}]" -f $backendEnumFinding.code, $backendEnumFinding.message, $backendEnumFinding.path)
    )
}

# Segregation of NON-PROSE candidates from the propagation gate: these are the
# ones that do not admit collective justification (13: per-class confrontation
# discipline) and require an item-by-item verdict. Prominent block so the
# reviewer does not dilute them among the other warnings.
$nonProseVerdictRequired = [System.Collections.Generic.List[object]]::new()
foreach ($ntFinding in @($newTokenPropagationGate.findings)) {
    $ntClass = if ($ntFinding.PSObject.Properties.Name -contains 'mentionClass') { [string]$ntFinding.mentionClass } else { '' }
    if ($ntClass -ne '' -and $ntClass -ne 'prose') {
        [void]$nonProseVerdictRequired.Add([pscustomobject][ordered]@{
            path         = $ntFinding.path
            mentionClass = $ntClass
            message      = $ntFinding.message
        })
    }
}
$nonProseModelDiversityThreshold = 5

$agentSemanticChecklist = [System.Collections.Generic.List[string]]::new()
[void]$agentSemanticChecklist.Add('Semantic phase: follow 13-pre-push-review.md at the root in full (authoritative source; AGENTS.md summarizes it).')
[void]$agentSemanticChecklist.Add('Do not treat this mechanical step exiting 0 as pre-push being complete.')
if ($nonProseVerdictRequired.Count -gt 0) {
    [void]$agentSemanticChecklist.Add(
        ("{0} NON-PROSE candidate(s) from the propagation gate require an INDIVIDUAL VERDICT (item-by-item ledger: each one with file:line, the twin list/table/example in the other document, and a gap|justified verdict). Collective justification is forbidden. Full list in nonProseVerdictRequired." -f $nonProseVerdictRequired.Count)
    )
    if ($nonProseVerdictRequired.Count -gt $nonProseModelDiversityThreshold) {
        [void]$agentSemanticChecklist.Add(
            ("More than {0} non-prose candidates: a second semantic-phase pass by a DIFFERENT MODEL is recommended before closing the verdict (13: model diversity safeguard) — a single model tends to satisfice and confront only the salient candidates." -f $nonProseModelDiversityThreshold)
        )
    }
}

$whitespaceRemainingDiagnosticHeaderCount = @($whitespaceRemainingIssues | Where-Object {
    $_ -match '^.+:\d+: (?:trailing whitespace\.|space before tab in indent\.|new blank line at EOF\.)$'
}).Count

$result = [ordered]@{
    status                      = $overallStatus
    pushReadiness               = $pushReadiness
    intervalDiffDiagnosticOnly  = $intervalDiffDiagnosticOnly
    rootPath                    = $resolvedRoot
    git                    = [ordered]@{
        repositoryRoot      = $resolvedRoot
        gitDir              = $resolvedGitDir
        branch              = $currentBranch
        expectedBranch      = $expectedBranch
        onExpectedBranch    = $onExpectedBranch
        workingTree         = [ordered]@{
            status                = $workingTree.Status
            untrackedCount        = $workingTree.UntrackedCount
            dirtyTrackedCount     = $workingTree.DirtyTrackedCount
            untrackedFiles        = @($workingTree.UntrackedFiles)
            dirtyTrackedFiles     = @($workingTree.DirtyTrackedFiles)
            untrackedTruncated    = $workingTree.UntrackedTruncated
            dirtyTrackedTruncated = $workingTree.DirtyTrackedTruncated
        }
        upstream            = $upstreamRef
        baseRef             = $effectiveBaseRef
        baseRefFallbackApplied = $baseRefFallbackApplied
        range               = $range
        commitsAhead        = $commitsAhead
        commitsBehind       = $commitsBehind
        pendingCommits      = @($pendingCommits)
        changedFiles        = @($changedFiles)
        changedFilesByKind  = $changedFilesByKind
        whitespaceCheck     = $whitespaceStatus
        whitespaceRawGitExitCode = $whitespaceRawExitCode
        whitespaceRawGitFailed = ($whitespaceRawExitCode -ne 0)
        whitespaceRemainingIssues = @($whitespaceRemainingIssues)
        whitespaceRemainingOutputLineCount = $whitespaceRemainingIssues.Count
        whitespaceRemainingDiagnosticHeaderCount = $whitespaceRemainingDiagnosticHeaderCount
        whitespaceIssues    = @($whitespaceIssues)
    }
    gates                  = [ordered]@{
        parse                = $parseGate
        pythonParse          = $pythonParseGate
        traceabilityCoverage = $traceabilityCoverageGate
        unexpectedChar       = $unexpectedCharGate
        newTokenPropagation  = $newTokenPropagationGate
        sharedScriptSkillCoverage = $sharedScriptSkillGate
        gateEnumerationParity = $gateEnumParityGate
        backendEnumerationParity = $backendEnumParityGate
    }
    mechanicalFailures       = @($mechanicalFailures)
    agentOperationalReminders = @($agentOperationalReminders)
    agentWarnings             = @($agentWarnings)
    agentSemanticChecklist   = @($agentSemanticChecklist)
    nonProseVerdictRequired  = @($nonProseVerdictRequired)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 8
} else {
    Write-Output ("STATUS={0}" -f $overallStatus)
    Write-Output ("BRANCH={0} BASE_INTERVAL={1} UPSTREAM_INFORMATIONAL={2}" -f $currentBranch, $effectiveBaseRef, $(if ($upstreamRef) { $upstreamRef } else { '(not configured)' }))
    Write-Output ("ON_EXPECTED_BRANCH={0} EXPECTED_BRANCH={1}" -f $(if ($onExpectedBranch) { 'true' } else { 'false' }), $expectedBranch)
    Write-Output ("WORKING_TREE={0} UNTRACKED={1} DIRTY_TRACKED={2}" -f $workingTree.Status, $workingTree.UntrackedCount, $workingTree.DirtyTrackedCount)
    foreach ($warning in @($agentWarnings)) {
        Write-Output ("WARNING: {0}" -f $warning)
    }
    if ($nonProseVerdictRequired.Count -gt 0) {
        Write-Output ("NON_PROSE_INDIVIDUAL_VERDICT ({0}):" -f $nonProseVerdictRequired.Count)
        foreach ($np in @($nonProseVerdictRequired)) {
            Write-Output ("  - [{0}] {1} [{2}]" -f $np.mentionClass, $np.message, $np.path)
        }
    }
    foreach ($path in @($workingTree.UntrackedFiles)) {
        Write-Output ("WORKING_TREE_UNTRACKED: {0}" -f $path)
    }
    foreach ($path in @($workingTree.DirtyTrackedFiles)) {
        Write-Output ("WORKING_TREE_DIRTY: {0}" -f $path)
    }
    if ($workingTree.UntrackedTruncated -or $workingTree.DirtyTrackedTruncated) {
        Write-Output 'WORKING_TREE_PATHS_TRUNCATED=true'
    }
    Write-Output ("COMMITS_AHEAD={0} COMMITS_BEHIND={1}" -f $commitsAhead, $commitsBehind)
    Write-Output ("PUSH_READINESS={0}" -f $pushReadiness)
    if ($intervalDiffDiagnosticOnly) {
        Write-Output 'INTERVAL_DIFF_DIAGNOSTIC_ONLY=true'
    }
    Write-Output 'NOTE=With origin/main existing but stale, the count may not reflect the current remote; git fetch origin before the routine when needed (see AGENTS.md).'

    if ($commitsAhead -eq 0) {
        Write-Output 'PENDING_COMMITS=none'
    } else {
        foreach ($commitLine in $pendingCommits) {
            Write-Output ("PENDING_COMMIT: {0}" -f $commitLine)
        }
    }

    Write-Output ("WHITESPACE_CHECK={0}" -f $whitespaceStatus)
    Write-Output ("WHITESPACE_RAW_GIT_EXIT_CODE={0} RAW_GIT_FAILED={1}" -f $whitespaceRawExitCode, ($whitespaceRawExitCode -ne 0))
    Write-Output ("WHITESPACE_REMAINING_OUTPUT_LINES={0}" -f $whitespaceRemainingIssues.Count)
    Write-Output ("WHITESPACE_REMAINING_DIAGNOSTIC_HEADERS={0}" -f $whitespaceRemainingDiagnosticHeaderCount)
    foreach ($issue in $whitespaceRemainingIssues) {
        Write-Output ("WHITESPACE_REMAINING_ISSUE: {0}" -f $issue)
    }
    foreach ($issue in $whitespaceIssues) {
        Write-Output ("WHITESPACE_ISSUE: {0}" -f $issue)
    }

    Write-Output ("PARSE_GATE={0}" -f $parseGate.status)
    if ($parseGate.status -ne 'skipped') {
        Write-Output ("PARSE_FILES={0} PARSE_ERRORS={1}" -f $parseGate.fileCount, $parseGate.errorCount)
        foreach ($finding in @($parseGate.findings)) {
            Write-Output ("PARSE_ERROR: {0}:{1}:{2}: {3}" -f $finding.file, $finding.line, $finding.column, $finding.message)
        }
    }

    Write-Output ("PYTHON_PARSE_GATE={0}" -f $pythonParseGate.status)
    if ($pythonParseGate.status -ne 'skipped') {
        Write-Output ("PYTHON_PARSE_FILES={0} PYTHON_PARSE_ERRORS={1}" -f $pythonParseGate.fileCount, $pythonParseGate.errorCount)
        foreach ($finding in @($pythonParseGate.findings)) {
            Write-Output ("PY_PARSE_ERROR: {0}:{1}:{2}: {3}" -f $finding.file, $finding.line, $finding.column, $finding.message)
        }
    }

    Write-Output ("TRACEABILITY_COVERAGE={0}" -f $traceabilityCoverageGate.status)
    foreach ($finding in @($traceabilityCoverageGate.findings)) {
        Write-Output ("TRACEABILITY_FINDING: {0}: {1}" -f $finding.code, $finding.message)
    }

    Write-Output ("UNEXPECTED_CHAR_GATE={0}" -f $unexpectedCharGate.status)
    foreach ($finding in @($unexpectedCharGate.findings)) {
        Write-Output ("UNEXPECTED_CHAR_FINDING: {0}: {1}" -f $finding.code, $finding.message)
    }

    Write-Output ("NEW_TOKEN_PROPAGATION_GATE={0}" -f $newTokenPropagationGate.status)
    if ($newTokenPropagationGate.truncated) {
        Write-Output ("NEW_TOKEN_PROPAGATION_PROSE_TRUNCATED={0}" -f $newTokenPropagationGate.truncatedProseCount)
    }
    foreach ($finding in @($newTokenPropagationGate.findings)) {
        Write-Output ("NEW_TOKEN_PROPAGATION_CANDIDATE: {0}: {1}" -f $finding.path, $finding.message)
    }

    Write-Output ("SHARED_SCRIPT_SKILL_COVERAGE_GATE={0}" -f $sharedScriptSkillGate.status)
    foreach ($finding in @($sharedScriptSkillGate.findings)) {
        Write-Output ("SHARED_SCRIPT_SKILL_DOC_NOT_IN_DIFF: {0}: {1}" -f $finding.path, $finding.message)
    }

    Write-Output ("GATE_ENUMERATION_PARITY_GATE={0}" -f $gateEnumParityGate.status)
    foreach ($finding in @($gateEnumParityGate.findings)) {
        Write-Output ("GATE_ENUMERATION_SUBSET: {0}: {1}" -f $finding.path, $finding.message)
    }

    Write-Output ("BACKEND_ENUMERATION_PARITY_GATE={0}" -f $backendEnumParityGate.status)
    foreach ($finding in @($backendEnumParityGate.findings)) {
        Write-Output ("BACKEND_ENUMERATION_SUBSET: {0}: {1}" -f $finding.path, $finding.message)
    }

    if ($changedFiles.Count -gt 0) {
        Write-Output 'CHANGED_FILES_BY_KIND:'
        foreach ($kind in @($changedFilesByKind.Keys)) {
            $paths = @($changedFilesByKind[$kind])
            if ($paths.Count -eq 0) {
                continue
            }
            Write-Output ("  {0}:" -f $kind)
            foreach ($path in $paths) {
                Write-Output ("    - {0}" -f $path)
            }
        }
    }

    Write-Output 'AGENT_SEMANTIC_CHECKLIST:'
    foreach ($item in $agentSemanticChecklist) {
        Write-Output ("  - {0}" -f $item)
    }
}

if ($mechanicalFailures.Count -gt 0) {
    exit 1
}

exit 0
