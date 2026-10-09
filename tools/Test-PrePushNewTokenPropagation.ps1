#requires -Version 7.4
<#
.SYNOPSIS
    Advisory gate: detects a contract term introduced in the diff and
    equivalent mentions in the repository that may have kept the old set.

.DESCRIPTION
    Mechanical support for the symmetric rule of step 2 of
    13-pre-push-review.md: when a change ADDS a parameter/alias/flag to a
    contract, the new term must appear in every equivalent mention of the
    same operation.

    Deterministic heuristic based on a TRANSITION in the diff (not on the
    token's global novelty in the repo — an alias may already exist in
    another flow and still be new for this contract):

      1. Splits the BaseRef..HEAD diff into hunks.
      2. In each hunk, compares contract tokens (-Xxx, --xxx, .PARAMETER Xxx)
         from the removed and added lines. A token T is INTRODUCED in the
         hunk if it appears in an added line and in no removed line of the
         same hunk.
      3. When an added line co-locates T (introduced) with a token P that
         existed in the hunk (present in a removed line), it records the
         pair (T, P): this is the signature of "an alias added to an
         existing enumeration" (e.g.: '- ...-ObjectNames or -ObjectGuids' ->
         '+ ...-ObjectList, -ObjectNames or -ObjectGuids').
      4. Scans the repository's current state (VERSIONED .md, .ps1, .py,
         outside .git/) for lines that mention P without T (ignoring
         P's own declaration: .PARAMETER P and a param block): each one is a
         CANDIDATE for a stale mention. The scan uses `git ls-files` because
         ignored or untracked material (a review-round draft in Temp/,
         vendored node_modules/) is not a repository document and cannot go
         stale on a push — it would only inflate the required verdict
         ledger. No fallback to a filesystem walk: the contract already
         requires a Git repository (the BaseRef base ref is validated before
         the scan), so an `ls-files` failure is an environment defect and
         the gate fails closed.

    Advisory: does not prove complete propagation nor fail on its own.
    Findings have severity 'warn'; the orchestrator dumps them into
    agentWarnings and the semantic phase confronts and justifies or fixes
    each candidate. A false positive is cheap (justify/discard); the
    expensive cost is a false negative (a new term that stayed only with the
    old set, invisible in the diff). Known limitation: it only fires when
    there is a co-located transition in the diff; an alias added without a
    pre-existing enumeration in the same hunk does not generate a pair.

.PARAMETER RootPath
    Repository root. Default: the parent of tools/.

.PARAMETER BaseRef
    Base reference of the BaseRef..HEAD interval. Default: origin/main.

.PARAMETER ChangedFiles
    Files changed in the interval (informational; accepted for the
    orchestrator gates' common contract). Detection uses the diff and the
    repo's current state.

.PARAMETER MaxFindings
    Cap on reported `prose`-class candidates. Default: 30. Non-prose
    candidates (`param-list-item`, `param-table-cell`, `command-example`) are
    NOT truncated — they are the most actionable and could be in files
    scanned after the prose cap filled up. `truncatedProseCount` reports how
    many prose candidates were discarded by the cap.

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

# Contract tokens: PowerShell parameter (-Xxx, uppercase initial so as not to
# match -eq/-not/-join operators), CLI/Python flag (--xxx), and .PARAMETER Xxx block.
$psParamRegex  = [regex]::new('(?<![A-Za-z0-9_])-(?<name>[A-Z][A-Za-z0-9]+)')
$cliFlagRegex  = [regex]::new('(?<![A-Za-z0-9_])--(?<name>[a-z][a-z0-9-]+)')
$paramDocRegex = [regex]::new('\.PARAMETER\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)')

function Get-LineTokens {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line)

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($rx in @($psParamRegex, $cliFlagRegex, $paramDocRegex)) {
        foreach ($m in $rx.Matches($Line)) {
            [void]$names.Add($m.Groups['name'].Value)
        }
    }
    return @($names | Sort-Object -Unique)
}

function Test-TokensRelated {
    # Reduces noise from coincidental co-location (e.g.: invocation lines like
    # 'pwsh -NoProfile -File ... -FrontPrefix'): only treats it as a pair when
    # the two tokens share a morpheme (common prefix OR suffix >= 4 chars,
    # case-insensitive). A contract alias/enumeration almost always shares a
    # root (ObjectList/ObjectNames -> 'Object'; InputPath/Path -> 'Path').
    param(
        [Parameter(Mandatory = $true)][string]$A,
        [Parameter(Mandatory = $true)][string]$B
    )

    $a = $A.ToLowerInvariant()
    $b = $B.ToLowerInvariant()
    $min = [Math]::Min($a.Length, $b.Length)

    $prefix = 0
    while ($prefix -lt $min -and $a[$prefix] -eq $b[$prefix]) { $prefix++ }

    $suffix = 0
    while ($suffix -lt $min -and $a[$a.Length - 1 - $suffix] -eq $b[$b.Length - 1 - $suffix]) { $suffix++ }

    return ($prefix -ge 4 -or $suffix -ge 4)
}

$wordRegexCache = @{}
function Get-WordRegex {
    # Matches the token as a word in any form (includes code's $Token).
    param([Parameter(Mandatory = $true)][string]$Token)

    if (-not $wordRegexCache.ContainsKey($Token)) {
        $pattern = '(?<![A-Za-z0-9_])' + [regex]::Escape($Token) + '(?![A-Za-z0-9_])'
        $wordRegexCache[$Token] = [regex]::new($pattern)
    }
    return $wordRegexCache[$Token]
}

$mentionRegexCache = @{}
function Get-MentionRegex {
    # Matches the token only as a contract mention (prose, doc, -Param), NOT as
    # internal code's $Token variable (the lookbehind excludes '$').
    param([Parameter(Mandatory = $true)][string]$Token)

    if (-not $mentionRegexCache.ContainsKey($Token)) {
        $pattern = '(?<![A-Za-z0-9_$])' + [regex]::Escape($Token) + '(?![A-Za-z0-9_])'
        $mentionRegexCache[$Token] = [regex]::new($pattern)
    }
    return $mentionRegexCache[$Token]
}

$declRegexCache = @{}
function Test-IsOwnDeclarationLine {
    # A line that only declares/documents the token P itself (not an
    # enumeration of the operation): .PARAMETER P, [type]$P, $P = ...
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line
    )

    if (-not $declRegexCache.ContainsKey($Token)) {
        $escaped = [regex]::Escape($Token)
        # .PARAMETER P  |  parameter declaration ending in $P[,)]  |  assignment $P =
        $pattern = '(^\s*\.PARAMETER\s+' + $escaped + '\b)|(\$' + $escaped + '\s*[,)]?\s*$)|(\$' + $escaped + '\s*=)'
        $declRegexCache[$Token] = [regex]::new($pattern)
    }
    return $declRegexCache[$Token].IsMatch($Line)
}

function Get-MentionClass {
    # Classifies the FORM of the line where the candidate was found. 13's
    # semantic phase uses this to avoid discarding candidates in bulk: 'prose'
    # admits collective justification (it only cites the canonical name);
    # 'param-list-item', 'param-table-cell', and 'command-example' require an
    # item-by-item verdict, confronted against the twin list/table/example in
    # the other document.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line,
        [bool]$InFence = $false
    )

    if ($InFence) { return 'command-example' }
    if ($Line -match '^\s*\|') { return 'param-table-cell' }
    if ($Line -match '^\s*[-*]\s+`?-') { return 'param-list-item' }
    return 'prose'
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

# Confirms the base ref exists (no automatic fallback).
$refCheck = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('rev-parse', '--verify', $BaseRef)
if ($refCheck.ExitCode -ne 0) {
    throw ("Base ref '{0}' not found; run git fetch origin or pass a valid -BaseRef." -f $BaseRef)
}

$range = "$BaseRef..HEAD"
$diffResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('diff', $range)
if ($diffResult.ExitCode -ne 0) {
    throw ("Failed to get the diff for the interval {0}." -f $range)
}

# Splits the patch into hunks; collects added and removed lines from each hunk.
$hunks = [System.Collections.Generic.List[object]]::new()
$currentAdded = $null
$currentRemoved = $null

function Save-CurrentHunk {
    if ($null -ne $currentAdded -and ($currentAdded.Count -gt 0 -or $currentRemoved.Count -gt 0)) {
        $script:hunks.Add([pscustomobject]@{
            Added   = @($currentAdded)
            Removed = @($currentRemoved)
        })
    }
}

foreach ($line in @($diffResult.Lines)) {
    if ($line.StartsWith('@@')) {
        Save-CurrentHunk
        $currentAdded = [System.Collections.Generic.List[string]]::new()
        $currentRemoved = [System.Collections.Generic.List[string]]::new()
        continue
    }
    if ($line.StartsWith('diff --git') -or $line.StartsWith('+++') -or $line.StartsWith('---')) {
        # File boundary / header: closes the current hunk.
        Save-CurrentHunk
        $currentAdded = $null
        $currentRemoved = $null
        continue
    }
    if ($null -eq $currentAdded) {
        continue
    }
    if ($line.StartsWith('+')) {
        [void]$currentAdded.Add($line.Substring(1))
    } elseif ($line.StartsWith('-')) {
        [void]$currentRemoved.Add($line.Substring(1))
    }
}
Save-CurrentHunk

# Pairs (IntroducedToken, PreExistingToken) from a co-located transition.
$pairKeys = [System.Collections.Generic.HashSet[string]]::new()
$pairs = [System.Collections.Generic.List[object]]::new()
$introducedTokens = [System.Collections.Generic.HashSet[string]]::new()

foreach ($hunk in $hunks) {
    $removedTokens = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($removedLine in @($hunk.Removed)) {
        foreach ($token in @(Get-LineTokens -Line $removedLine)) {
            [void]$removedTokens.Add($token)
        }
    }

    foreach ($addedLine in @($hunk.Added)) {
        $tokens = @(Get-LineTokens -Line $addedLine)
        if ($tokens.Count -lt 2) {
            continue
        }

        $introducedInLine = @($tokens | Where-Object { -not $removedTokens.Contains($_) })
        $preExistingInLine = @($tokens | Where-Object { $removedTokens.Contains($_) })
        if ($introducedInLine.Count -eq 0 -or $preExistingInLine.Count -eq 0) {
            continue
        }

        foreach ($newToken in $introducedInLine) {
            [void]$introducedTokens.Add($newToken)
            foreach ($oldToken in $preExistingInLine) {
                if ($newToken -eq $oldToken) {
                    continue
                }
                if (-not (Test-TokensRelated -A $newToken -B $oldToken)) {
                    continue
                }
                $key = '{0}|{1}' -f $newToken, $oldToken
                if ($pairKeys.Add($key)) {
                    $pairs.Add([pscustomobject][ordered]@{
                        newToken = $newToken
                        oldToken = $oldToken
                    })
                }
            }
        }
    }
}

$findings = [System.Collections.Generic.List[object]]::new()
$findingKeys = [System.Collections.Generic.HashSet[string]]::new()
$truncated = $false
$proseCount = 0
$truncatedProseCount = 0

if ($pairs.Count -gt 0) {
    # Scan universe = VERSIONED files. Ignored/untracked material (Temp/ from
    # review rounds, vendored node_modules/) is not a repository document: it
    # cannot go stale on a push and would only inflate the verdict ledger the
    # orchestrator requires. There is no filesystem-walk fallback: the contract
    # already requires a Git repository (the base ref is validated above), so a
    # failure here is an environment defect, not a Git-less root — fail-closed.
    # No wildcard pathspec: pwsh on Unix expands a wildcard argument passed to
    # a native command against the current directory. The extension filter
    # below reproduces git's '*.md' '*.ps1' '*.py' pathspec: any depth,
    # case-sensitive.
    $trackedResult = Invoke-RepoGit -RepositoryRoot $resolvedRoot -Arguments @('ls-files', '--cached')
    if ($trackedResult.ExitCode -ne 0) {
        throw ("Failed to list versioned files in '{0}': {1}" -f $resolvedRoot, $trackedResult.Text)
    }
    $files = @($trackedResult.Lines |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Where-Object { $_ -cmatch '\.(md|ps1|py)$' } |
        ForEach-Object { [System.IO.FileInfo]::new((Join-Path $resolvedRoot $_)) } |
        Where-Object {
            $_.Exists -and
            $_.FullName -notmatch '[\\/]\.git[\\/]'
        })

    foreach ($file in $files) {
        $fileLines = @()
        try {
            $fileLines = @([System.IO.File]::ReadAllLines($file.FullName))
        } catch {
            continue
        }

        $relPath = ([System.IO.Path]::GetRelativePath($resolvedRoot, $file.FullName) -replace '\\', '/')
        $inFence = $false

        for ($i = 0; $i -lt $fileLines.Count; $i++) {
            $text = $fileLines[$i]

            # Tracks fenced code blocks (```), to classify internal lines as
            # command-example. The delimiter itself is not a candidate.
            if ($text -match '^\s*```') {
                $inFence = -not $inFence
                continue
            }

            foreach ($pair in $pairs) {
                # Contract mention of the old token (prose/doc/-Param), not a $variable.
                $oldMentionRx = Get-MentionRegex -Token $pair.oldToken
                if (-not $oldMentionRx.IsMatch($text)) {
                    continue
                }
                # New token present in any form -> mention already propagated.
                $newRx = Get-WordRegex -Token $pair.newToken
                if ($newRx.IsMatch($text)) {
                    continue
                }
                # Declaration of the old parameter itself (.PARAMETER P / param block).
                if (Test-IsOwnDeclarationLine -Token $pair.oldToken -Line $text) {
                    continue
                }

                $lineNumber = $i + 1
                $findingKey = '{0}:{1}:{2}|{3}' -f $relPath, $lineNumber, $pair.newToken, $pair.oldToken
                if (-not $findingKeys.Add($findingKey)) {
                    continue
                }

                $mentionClass = Get-MentionClass -Line $text -InFence $inFence

                # Class-aware truncation: non-prose candidates
                # (param-list-item/param-table-cell/command-example) are NEVER
                # truncated — they are the most actionable and may be in files
                # scanned after the prose cap filled up. Only prose is
                # limited by -MaxFindings.
                if ($mentionClass -eq 'prose') {
                    if ($proseCount -ge $MaxFindings) {
                        $truncated = $true
                        $truncatedProseCount++
                        continue
                    }
                    $proseCount++
                }

                $findings.Add([pscustomobject][ordered]@{
                    code         = 'NEW_TOKEN_PROPAGATION_CANDIDATE'
                    severity     = 'warn'
                    path         = ('{0}:{1}' -f $relPath, $lineNumber)
                    mentionClass = $mentionClass
                    message      = ("term '{0}' was introduced in the diff alongside '{1}'; this mention has '{1}' without '{0}' — confirm propagation or justify the omission [class={2}]" -f $pair.newToken, $pair.oldToken, $mentionClass)
                })
            }
        }
    }
}

$status = if ($findings.Count -gt 0) { 'warn' } else { 'pass' }

$classCounts = [ordered]@{}
foreach ($f in $findings) {
    if ($classCounts.Contains($f.mentionClass)) {
        $classCounts[$f.mentionClass] = $classCounts[$f.mentionClass] + 1
    } else {
        $classCounts[$f.mentionClass] = 1
    }
}

$result = [ordered]@{
    status              = $status
    range               = $range
    introducedTokens    = @($introducedTokens | Sort-Object)
    pairsConsidered     = @($pairs)
    candidateCount      = $findings.Count
    classCounts         = $classCounts
    truncated           = $truncated
    truncatedProseCount = $truncatedProseCount
    findings            = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    Write-Output ("STATUS={0}" -f $status)
    Write-Output ("RANGE={0}" -f $range)
    Write-Output ("INTRODUCED_TOKENS={0}" -f (@($introducedTokens | Sort-Object) -join ', '))
    Write-Output ("CANDIDATE_COUNT={0}" -f $findings.Count)
    foreach ($finding in @($findings)) {
        Write-Output ("NEW_TOKEN_PROPAGATION_CANDIDATE: {0}: {1}" -f $finding.path, $finding.message)
    }
    if ($truncated) {
        Write-Output ("PROSE_CANDIDATES_TRUNCATED={0}" -f $truncatedProseCount)
        Write-Output 'NON_PROSE_CANDIDATES_COMPLETE=true'
    }
}

exit 0
