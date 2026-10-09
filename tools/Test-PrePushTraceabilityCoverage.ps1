#requires -Version 7.4
<#
.SYNOPSIS
    Detects objective editorial traceability risks in the pre-push routine.

.DESCRIPTION
    Advisory check to point out risk zones that the semantic phase must
    justify. Does not try to prove complete documentation coverage.
#>

[CmdletBinding()]
param(
    # Default: parent of tools/.
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,

    [string]$BaseRef = 'origin/main',

    [AllowEmptyCollection()]
    [string[]]$ChangedFiles = @(),

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
    param([string]$Path)

    return (($Path -replace '\\', '/').Trim())
}

function Add-Finding {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Path = $null
    )

    $Target.Add([pscustomobject][ordered]@{
        code     = $Code
        severity = 'warn'
        path     = $Path
        message  = $Message
    })
}

function Get-GitFileTextAtRef {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$Ref,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $result = Invoke-RepoGit -RepositoryRoot $RepositoryRoot -Arguments @('show', ('{0}:{1}' -f $Ref, $Path))
    if ($result.ExitCode -ne 0) {
        return $null
    }
    return $result.Text
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path
$normalizedChangedFiles = @($ChangedFiles | ForEach-Object { Normalize-RepoPath -Path $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
if ($normalizedChangedFiles.Count -eq 0) {
    $changedResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', '--name-only', "$BaseRef..HEAD")
    if ($changedResult.ExitCode -ne 0) {
        throw ("Failed to list changed files in {0}..HEAD: {1}" -f $BaseRef, $changedResult.Text)
    }
    $normalizedChangedFiles = @($changedResult.Lines | ForEach-Object { Normalize-RepoPath -Path $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

$publicTraceabilityRelative = 'skills/mimir-lite/references/09-script-inventory.md'
$agentGuideRelative = 'skills/mimir-lite/references/08-agent-guide.md'
$publicTraceabilityPath = Join-Path $resolvedRoot $publicTraceabilityRelative
$agentGuidePath = Join-Path $resolvedRoot $agentGuideRelative
$publicTraceabilityText = if (Test-Path -LiteralPath $publicTraceabilityPath -PathType Leaf) {
    [System.IO.File]::ReadAllText($publicTraceabilityPath)
} else {
    ''
}
$agentGuideText = if (Test-Path -LiteralPath $agentGuidePath -PathType Leaf) {
    [System.IO.File]::ReadAllText($agentGuidePath)
} else {
    ''
}

$findings = [System.Collections.Generic.List[object]]::new()

$prePushDocRelative = 'docs/process/13-pre-push-review.md'
$agentsChanged = $normalizedChangedFiles -contains 'AGENTS.md'
$prePushDocChanged = $normalizedChangedFiles -contains $prePushDocRelative
if ($agentsChanged) {
    $agentsDiff = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', '--unified=0', "$BaseRef..HEAD", '--', 'AGENTS.md')
    if ($agentsDiff.ExitCode -eq 0 -and
        $agentsDiff.Text -match '(?i)(pre-push|09-script-inventory|traceability|13-pre-push-review)' -and
        -not ($normalizedChangedFiles -contains $agentGuideRelative)) {
        Add-Finding -Target $findings -Code 'AGENTS_PREPUSH_NOT_MIRRORED_IN_08' -Path $agentGuideRelative -Message ("AGENTS.md changed a pre-push/traceability rule, but {0} does not appear in the interval; assess whether the agent guide is stale." -f $agentGuideRelative)
    }
}
if ($prePushDocChanged -and -not ($normalizedChangedFiles -contains $agentGuideRelative)) {
    Add-Finding -Target $findings -Code 'PREPUSH_DOC_NOT_MIRRORED_IN_08' -Path $agentGuideRelative -Message ("{0} changed in the interval, but {1} did not; assess whether the summary for GPT agents is stale." -f $prePushDocRelative, $agentGuideRelative)
}

# Anti-regression trap for the lean 09 (pointer index): a script entry that reverted to
# the old verbose format (a "Direct evidence" label glued to a script path). After the
# lean-down, a script pointer carries no label (- `skills/mimir-lite/scripts/X`
# (category) -- ...); this format reappearing signals contract prose creeping back in to
# duplicate the logical owner. Invariant (not diff-scoped), warn, with a cap. Governance
# bullets that cite a script have text between the label and the path (": the script
# `skills/.../X`"), so they don't match the pattern. Covers all 3 real script roots
# (skills/mimir-lite/scripts/, skills/mimir-delegate/scripts/, tools/).
$verboseEntryRegex = [regex]'(?m)^- `Direct evidence`:[ \t]*`(?:skills/(?:mimir-lite|mimir-delegate)/scripts|tools)/'
$verboseLineCap = 25
$verboseReported = 0
foreach ($verboseMatch in $verboseEntryRegex.Matches($publicTraceabilityText)) {
    if ($verboseReported -ge $verboseLineCap) { break }
    $verboseLineNumber = (($publicTraceabilityText.Substring(0, $verboseMatch.Index)) -split "`n").Count
    Add-Finding -Target $findings -Code 'PUBLIC_TRACEABILITY_VERBOSE_LINE' -Path $publicTraceabilityRelative -Message ("Line ~{0} of 09 is in the verbose script-entry format (a 'Direct evidence' label glued to a script path); 09 is a pointer index - reduce it to 1 line (role + owner + validation), the contract detail lives with the owner." -f $verboseLineNumber)
    $verboseReported++
}

$scriptRiskPattern = '(INVENTORY_[A-Z_]+|DRIFT_[A-Z_]+|LITERAL_TIMESTAMP_DRIFT|executionEvidence|watcherContext|pathEnrichment|diagnosticDegraded|compactSignals|PUSH_READINESS|pushReadiness|suggested_operational_state|methodology_update_pending)'
$changedScriptPaths = @($normalizedChangedFiles | Where-Object { $_ -match '^(?:skills/(?:mimir-lite|mimir-delegate)/scripts|tools)/.+\.(ps1|py|json)$' })
foreach ($scriptPath in $changedScriptPaths) {
    $scriptDiff = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', '--unified=0', "$BaseRef..HEAD", '--', $scriptPath)
    if ($scriptDiff.ExitCode -ne 0) {
        continue
    }

    $scriptBaseName = Split-Path -Leaf $scriptPath
    $isTraceabilityDetector = $scriptBaseName -eq 'Test-PrePushTraceabilityCoverage.ps1'
    $addedDiffText = (@($scriptDiff.Lines | Where-Object { $_ -match '^\+' -and $_ -notmatch '^\+\+\+' }) -join [Environment]::NewLine)
    $removedDiffText = (@($scriptDiff.Lines | Where-Object { $_ -match '^-' -and $_ -notmatch '^---' }) -join [Environment]::NewLine)
    $scriptHasTraceabilityRisk = $addedDiffText -match $scriptRiskPattern
    if ($scriptHasTraceabilityRisk -and $publicTraceabilityText -notmatch [regex]::Escape($scriptBaseName)) {
        Add-Finding -Target $findings -Code 'PUBLIC_TRACEABILITY_MISSING_SCRIPT' -Path $scriptPath -Message ("{0} changed a traceable contract/signal, but {1} does not mention the script by name." -f $scriptPath, $publicTraceabilityRelative)
    }

    $tokens = if ($isTraceabilityDetector) {
        @()
    } else {
        $addedTokens = @([regex]::Matches($addedDiffText, $scriptRiskPattern) | ForEach-Object { $_.Value } | Sort-Object -Unique)
        $removedTokens = @([regex]::Matches($removedDiffText, $scriptRiskPattern) | ForEach-Object { $_.Value } | Sort-Object -Unique)
        @($addedTokens | Where-Object { $removedTokens -notcontains $_ })
    }
    foreach ($token in $tokens) {
        if ($publicTraceabilityText -notmatch [regex]::Escape($token)) {
            Add-Finding -Target $findings -Code 'PUBLIC_TRACEABILITY_MISSING_TOKEN' -Path $scriptPath -Message ("Traceable token '{0}' appears in {1}'s diff, but does not appear in 09." -f $token, $scriptPath)
        }
    }
}

$selfTestChangedPaths = @($changedScriptPaths | Where-Object { $_ -match 'SelfTest\.ps1$' })
foreach ($selfTestPath in $selfTestChangedPaths) {
    $selfTestBaseName = Split-Path -Leaf $selfTestPath
    $motorCandidates = [System.Collections.Generic.List[string]]::new()
    $suffixMotor = $selfTestBaseName -replace 'SelfTest\.ps1$', '.ps1'
    if ($suffixMotor -ne $selfTestBaseName) {
        $motorCandidates.Add($suffixMotor) | Out-Null
    }
    if ($selfTestBaseName -match '^Test-(.+)SelfTest\.ps1$') {
        $getMotor = ('Get-{0}.ps1' -f $Matches[1])
        if (-not $motorCandidates.Contains($getMotor)) {
            $motorCandidates.Add($getMotor) | Out-Null
        }
    }

    $existingMotorCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($motorCandidate in $motorCandidates) {
        $candidatePath = Join-Path (Join-Path $resolvedRoot 'scripts') $motorCandidate
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $existingMotorCandidates.Add($motorCandidate) | Out-Null
        }
    }

    $motorMentioned = $false
    foreach ($motorCandidate in $existingMotorCandidates) {
        if ($publicTraceabilityText -match [regex]::Escape($motorCandidate)) {
            $motorMentioned = $true
            break
        }
    }

    if ($existingMotorCandidates.Count -gt 0 -and
        $publicTraceabilityText -match [regex]::Escape($selfTestBaseName) -and
        -not $motorMentioned) {
        $motorList = ($existingMotorCandidates -join ', ')
        Add-Finding -Target $findings -Code 'PUBLIC_TRACEABILITY_AGGREGATED_ROLE_RISK' -Path $selfTestPath -Message ("09 mentions the {0} test battery, but does not mention the corresponding engine ({1}); assess whether traceability is too aggregated." -f $selfTestBaseName, $motorList)
    }
}

if ((($agentsChanged -or $prePushDocChanged) -and ($normalizedChangedFiles -contains $agentGuideRelative))) {
    # The agent guide does not restate the development process; it points to where it lives
    # (docs/process/) and to the traceability index (09-script-inventory.md).
    foreach ($requiredPhrase in @('09-script-inventory.md', 'docs/process/')) {
        if ($agentGuideText -notmatch [regex]::Escape($requiredPhrase)) {
            Add-Finding -Target $findings -Code 'AGENT_GUIDE_PREPUSH_RULE_INCOMPLETE' -Path $agentGuideRelative -Message ("{0} was changed together with the pre-push doc, but does not contain the expected marker: {1}" -f $agentGuideRelative, $requiredPhrase)
        }
    }
}

$queryPyPath = Join-Path $resolvedRoot 'skills/mimir-lite/scripts/Query-KbIntelligenceIndex.py'
$buildPs1Path = Join-Path $resolvedRoot 'skills/mimir-lite/scripts/Build-KbIntelligenceIndex.ps1'
$queryPs1Path = Join-Path $resolvedRoot 'skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1'
$buildPyRelativePath = 'skills/mimir-lite/scripts/Build-KbIntelligenceIndex.py'
if ($normalizedChangedFiles -contains $buildPyRelativePath) {
    $buildPyPath = Join-Path $resolvedRoot $buildPyRelativePath
    if (Test-Path -LiteralPath $buildPyPath -PathType Leaf) {
        $buildPyCurrentText = [System.IO.File]::ReadAllText($buildPyPath)
        $buildPyBaseText = Get-GitFileTextAtRef -RepositoryRoot $resolvedRoot -Ref $BaseRef -Path $buildPyRelativePath
        $currentVersionMatch = [regex]::Match($buildPyCurrentText, 'EXTRACTOR_SIGNATURE_VERSION\s*=\s*"(?<version>[^"]+)"')
        $baseVersionMatch = if ($null -ne $buildPyBaseText) {
            [regex]::Match($buildPyBaseText, 'EXTRACTOR_SIGNATURE_VERSION\s*=\s*"(?<version>[^"]+)"')
        } else {
            [System.Text.RegularExpressions.Match]::Empty
        }

        if ($currentVersionMatch.Success -and $baseVersionMatch.Success) {
            $currentExtractorVersion = $currentVersionMatch.Groups['version'].Value
            $baseExtractorVersion = $baseVersionMatch.Groups['version'].Value
            if ($currentExtractorVersion -ne $baseExtractorVersion) {
                $staleExtractorPattern = [regex]::new(
                    ('(?i)\b(?:extrator|extractor)(?:\s+\w+){{0,4}}\s+`?{0}`?\b' -f [regex]::Escape($baseExtractorVersion))
                )
                $docFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
                    Where-Object {
                        (Normalize-RepoPath -Path ([System.IO.Path]::GetRelativePath($resolvedRoot, $_.FullName))) -notmatch '^\.git/'
                    })
                foreach ($docFile in $docFiles) {
                    $relativeDocPath = Normalize-RepoPath -Path ([System.IO.Path]::GetRelativePath($resolvedRoot, $docFile.FullName))
                    $docText = [System.IO.File]::ReadAllText($docFile.FullName)
                    $staleMatches = @($staleExtractorPattern.Matches($docText))
                    if ($staleMatches.Count -gt 0) {
                        Add-Finding -Target $findings -Code 'EXTRACTOR_SIGNATURE_STALE_DOC_REF' -Path $relativeDocPath -Message ("Build-KbIntelligenceIndex.py changed EXTRACTOR_SIGNATURE_VERSION from {0} to {1}, but {2} still contains a textual reference to extrator/extractor {0}; review whether this is justified history or a documentation gap." -f $baseExtractorVersion, $currentExtractorVersion, $relativeDocPath)
                    }
                }
            }
        }
    }
}
if ((Test-Path -LiteralPath $queryPyPath -PathType Leaf) -and (Test-Path -LiteralPath $buildPs1Path -PathType Leaf)) {
    $queryPyText = [System.IO.File]::ReadAllText($queryPyPath)
    $buildPs1Text = [System.IO.File]::ReadAllText($buildPs1Path)
    $queryPs1Text = if (Test-Path -LiteralPath $queryPs1Path -PathType Leaf) {
        [System.IO.File]::ReadAllText($queryPs1Path)
    } else {
        ''
    }

    $docPaths = @(
        'skills/mimir-lite/references/02-operational-rules.md',
        $agentGuideRelative,
        'README.md',
        'AGENTS.md',
        $prePushDocRelative,
        'skills/mimir-lite/references/kb-index-reference.md'
    )
    $docCombined = ($docPaths | ForEach-Object {
        $docPath = Join-Path $resolvedRoot $_
        if (Test-Path -LiteralPath $docPath -PathType Leaf) {
            [System.IO.File]::ReadAllText($docPath)
        } else {
            ''
        }
    }) -join [Environment]::NewLine

    $docsPromiseEffectiveCatalog = ($docCombined -match '(?i)catalogo efetivo|effective catalog') -and
        ($docCombined -match 'Query-KbIntelligenceIndex')

    if ($docsPromiseEffectiveCatalog) {
        $queryHasEffectiveCatalog = $queryPyText -match '(?i)catalog-override-path|kb-workspace-root|resolve_effective|GeneXusObjectTypeCatalogCore'
        if (-not $queryHasEffectiveCatalog) {
            Add-Finding -Target $findings -Code 'MOTOR_DOC_CATALOG_EFFECTIVE_MISMATCH' -Path $queryPyPath -Message 'Documentation promises an effective catalog in Query-KbIntelligenceIndex, but the Python engine does not reference merge/override/kb-workspace-root.'
        }
    }

    if ($buildPs1Text -match '\$KbWorkspaceRoot' -and $queryPs1Text -and $queryPs1Text -notmatch '\$KbWorkspaceRoot') {
        Add-Finding -Target $findings -Code 'MOTOR_PAIR_PARAM_ASYMMETRY' -Path $queryPs1Path -Message 'Build-KbIntelligenceIndex.ps1 exposes -KbWorkspaceRoot, but Query-KbIntelligenceIndex.ps1 does not.'
    }
}

$orchestratorPath = 'tools/Invoke-PrePushMechanicalChecks.ps1'
if ($normalizedChangedFiles -contains $orchestratorPath) {
    $orchestratorDiff = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', '--unified=0', "$BaseRef..HEAD", '--', $orchestratorPath)
    if ($orchestratorDiff.ExitCode -eq 0) {
        $addedOrchestratorText = (@($orchestratorDiff.Lines | Where-Object { $_ -match '^\+' -and $_ -notmatch '^\+\+\+' }) -join [Environment]::NewLine)
        $referencedGateScripts = @([regex]::Matches($addedOrchestratorText, 'Test-[A-Za-z0-9-]+\.ps1') |
            ForEach-Object { $_.Value } |
            Where-Object { $_ -ne 'Test-PsScriptsParse.ps1' } |
            Sort-Object -Unique)
        foreach ($gateScript in $referencedGateScripts) {
            if ($agentGuideText -notmatch [regex]::Escape($gateScript)) {
                Add-Finding -Target $findings -Code 'AGENT_GUIDE_MISSING_ORCHESTRATOR_GATE' -Path $agentGuideRelative -Message ("Invoke-PrePushMechanicalChecks.ps1 now references {0}, but {1} does not cite that gate by name." -f $gateScript, $agentGuideRelative)
            }
        }
    }
}

$status = if ($findings.Count -gt 0) { 'warn' } else { 'pass' }
$result = [ordered]@{
    status       = $status
    baseRef      = $BaseRef
    changedFiles = @($normalizedChangedFiles)
    findings     = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 8
} else {
    Write-Output ("TRACEABILITY_COVERAGE={0}" -f $status)
    foreach ($finding in $findings) {
        Write-Output ("TRACEABILITY_FINDING: {0}: {1}" -f $finding.code, $finding.message)
    }
}

exit 0
