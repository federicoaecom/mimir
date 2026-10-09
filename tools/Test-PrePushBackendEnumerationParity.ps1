#requires -Version 7.4
<#
.SYNOPSIS
    Advisory gate: an enumeration of delegation backends/adapters in the
    documentation that ended up as a proper subset of the dispatcher's
    canonical set.

.DESCRIPTION
    Root-cause fix for a methodological gap (Level 3): when new backends were
    added to the dispatcher (scripts/Invoke-LlmDelegatePanelDispatch.ps1),
    closed prose enumerations in the Markdown documents could keep the
    old/incomplete set without citing the new term.

    This gate extracts TRUTH from the code: it derives the canonical backend
    set from $AdapterScript in the real dispatcher's AST. It then scans the
    *.md files at the root + skills/mimir-delegate/**/*.md +
    skills/mimir-lite/**/*.md (excluding CHANGELOG.md and temp folders) and
    flags any logical unit/sentence that cites >= 2 backends forming a proper
    subset of the canonical set (2 <= n < total).

    Domain boundary: sentences/blocks containing the token \bCursor\b (case-
    insensitive) are ignored because they belong to Domain B (managed agent
    tools), not to LLM delegation backends (Domain A).

    Exception marker: supports <!-- backend-parity: ignore --> or
    # backend-parity: ignore in comments for intentional per-axis carve-outs.

.PARAMETER RootPath
    Repository root. Default: parent of tools/.

.PARAMETER BaseRef
    Accepted for the gates' common contract; this gate is invariant (does not use the diff).

.PARAMETER ChangedFiles
    Accepted for the gates' common contract; unused (the check is repo-wide).

.PARAMETER MaxFindings
    Cap on reported candidates. Default: 50.

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
    [int]$MaxFindings = 50,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

$dispatcherRel = 'skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1'
$dispatcherPath = Join-Path $resolvedRoot $dispatcherRel

$findings = [System.Collections.Generic.List[object]]::new()
$truncated = $false
$canonicalBackends = @()
$ignoredCount = 0

function Get-BackendRegex {
    param([string]$Backend)
    switch ($Backend.ToLowerInvariant()) {
        'opencode'    { return [regex]::new('(?i)\b(?:opencode(?:\/(?:ollama[\s\-_]*cloud|mimo))?)\b') }
        'codex'       { return [regex]::new('(?i)\b(?:codex(?:[\s\-_]*delegate|[\s\-_]*cli)?)\b') }
        'claude-code' { return [regex]::new('(?i)\b(?:claude[\s\-_]*code|claudecode|claude)\b') }
        'copilot'     { return [regex]::new('(?i)\b(?:github[\s\-_]+)?copilot(?:[\s\-_]+cli)?\b') }
        'gemini'      { return [regex]::new('(?i)\bgemini(?:[\s\-_]+cli)?\b') }
        'antigravity' { return [regex]::new('(?i)\b(?:antigravity(?:[\s\-_]+(?:cli|2\.0))?|agy)\b') }
        default       { return [regex]::new("(?i)\b$([regex]::Escape($Backend))\b") }
    }
}

function Parse-MarkdownLogicalUnits {
    param([string]$FilePath)

    $lines = @([System.IO.File]::ReadAllLines($FilePath))
    $units = [System.Collections.Generic.List[object]]::new()

    $inCodeBlock = $false
    $currentBlockLines = [System.Collections.Generic.List[string]]::new()
    $startLineNum = 1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNum = $i + 1
        $line = $lines[$i]

        if ($line -match '^\s*```') {
            if ($inCodeBlock) {
                $inCodeBlock = $false
                continue
            } else {
                if ($currentBlockLines.Count -gt 0) {
                    $units.Add([pscustomobject]@{
                        StartLine = $startLineNum
                        EndLine   = $lineNum - 1
                        RawLines  = @($currentBlockLines)
                    })
                    $currentBlockLines.Clear()
                }
                $inCodeBlock = $true
                continue
            }
        }

        if ($inCodeBlock) { continue }

        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($currentBlockLines.Count -gt 0) {
                $units.Add([pscustomobject]@{
                    StartLine = $startLineNum
                    EndLine   = $lineNum - 1
                    RawLines  = @($currentBlockLines)
                })
                $currentBlockLines.Clear()
            }
            continue
        }

        if ($line -match '^\s*#{1,6}\s+' -or $line -match '^\s*\|.*\|\s*$') {
            if ($currentBlockLines.Count -gt 0) {
                $units.Add([pscustomobject]@{
                    StartLine = $startLineNum
                    EndLine   = $lineNum - 1
                    RawLines  = @($currentBlockLines)
                })
                $currentBlockLines.Clear()
            }
            $units.Add([pscustomobject]@{
                StartLine = $lineNum
                EndLine   = $lineNum
                RawLines  = @($line)
            })
            continue
        }

        if ($line -match '^\s*[-*+]\s+' -or $line -match '^\s*\d+\.\s+') {
            if ($currentBlockLines.Count -gt 0) {
                $units.Add([pscustomobject]@{
                    StartLine = $startLineNum
                    EndLine   = $lineNum - 1
                    RawLines  = @($currentBlockLines)
                })
                $currentBlockLines.Clear()
            }
            $startLineNum = $lineNum
            $currentBlockLines.Add($line)
            continue
        }

        if ($currentBlockLines.Count -eq 0) {
            $startLineNum = $lineNum
        }
        $currentBlockLines.Add($line)
    }

    if ($currentBlockLines.Count -gt 0) {
        $units.Add([pscustomobject]@{
            StartLine = $startLineNum
            EndLine   = $lines.Count
            RawLines  = @($currentBlockLines)
        })
    }

    return @($units)
}

if (Test-Path -LiteralPath $dispatcherPath -PathType Leaf) {
    $tokens = $null
    $parserErrors = $null
    $dispatcherAst = [System.Management.Automation.Language.Parser]::ParseFile($dispatcherPath, [ref]$tokens, [ref]$parserErrors)

    if (@($parserErrors).Count -eq 0) {
        $assign = @($dispatcherAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text.Trim() -eq '$AdapterScript'
        }, $true))[0]

        if ($null -ne $assign) {
            $ht = if ($assign.Right -is [System.Management.Automation.Language.HashtableAst]) {
                $assign.Right
            } else {
                @($assign.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true))[0]
            }

            if ($null -ne $ht) {
                $extracted = [System.Collections.Generic.List[string]]::new()
                foreach ($pair in $ht.KeyValuePairs) {
                    $extracted.Add($pair.Item1.Extent.Text.Trim("'", '"', ' '))
                }
                $canonicalBackends = @($extracted)
            }
        }
    }
}

if ($canonicalBackends.Count -ge 2) {
    $backendPatterns = [ordered]@{}
    foreach ($b in $canonicalBackends) {
        $backendPatterns[$b] = Get-BackendRegex $b
    }

    $excludedFileNames = @('CHANGELOG.md')

    $docFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($f in @(Get-ChildItem -LiteralPath $resolvedRoot -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
        $docFiles.Add($f)
    }
    foreach ($skillDirName in @('skills/mimir-delegate', 'skills/mimir-lite')) {
        $skillDir = Join-Path $resolvedRoot $skillDirName
        if (Test-Path -LiteralPath $skillDir -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $skillDir -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
                $docFiles.Add($f)
            }
        }
    }

    foreach ($docFile in $docFiles) {
        if ($truncated) { break }

        $relPath = ([System.IO.Path]::GetRelativePath($resolvedRoot, $docFile.FullName) -replace '\\', '/')
        if ($relPath -match '^(?:temp|tempo)/' -or $docFile.Name -in $excludedFileNames) {
            continue
        }

        $units = Parse-MarkdownLogicalUnits $docFile.FullName

        foreach ($u in $units) {
            if ($truncated) { break }

            $hasIgnore = $false
            foreach ($l in $u.RawLines) {
                if ($l -match '<!--\s*backend-parity:\s*ignore\s*-->' -or $l -match '#\s*backend-parity:\s*ignore') {
                    $hasIgnore = $true
                    break
                }
            }
            if ($hasIgnore) {
                $ignoredCount++
                continue
            }

            $flatText = ($u.RawLines -join ' ')
            if ($flatText -match '(?i)\bcursor\b') {
                continue
            }

            $onUnit = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($b in $canonicalBackends) {
                if ($backendPatterns[$b].IsMatch($flatText)) {
                    [void]$onUnit.Add($b)
                }
            }

            if ($onUnit.Count -lt 2) { continue }
            if ($onUnit.Count -ge $canonicalBackends.Count) { continue }

            if ($findings.Count -ge $MaxFindings) {
                $truncated = $true
                break
            }

            $listed = @($onUnit | Sort-Object)
            $missing = @($canonicalBackends | Where-Object { -not $onUnit.Contains($_) })

            $findings.Add([pscustomobject][ordered]@{
                code     = 'BACKEND_ENUMERATION_SUBSET'
                severity = 'warn'
                path     = ('{0}:{1}' -f $relPath, $u.StartLine)
                message  = ("enumerates {0} of {1} canonical backends ({2}); if the block describes the backend set, confirm it is complete — missing: {3}" -f $onUnit.Count, $canonicalBackends.Count, ($listed -join ', '), ($missing -join ', '))
            })
        }
    }
}

$status = if ($findings.Count -gt 0) { 'warn' } else { 'pass' }

$result = [ordered]@{
    status            = $status
    dispatcher        = $dispatcherRel
    canonicalBackends = @($canonicalBackends)
    candidateCount    = $findings.Count
    ignoredCount      = $ignoredCount
    truncated         = $truncated
    findings          = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    Write-Output ("STATUS={0}" -f $status)
    Write-Output ("CANONICAL_BACKENDS={0}" -f ($canonicalBackends -join ', '))
    Write-Output ("CANDIDATE_COUNT={0}" -f $findings.Count)
    Write-Output ("IGNORED_COUNT={0}" -f $ignoredCount)
    foreach ($finding in @($findings)) {
        Write-Output ("BACKEND_ENUMERATION_SUBSET: {0}: {1}" -f $finding.path, $finding.message)
    }
    if ($truncated) {
        Write-Output 'CANDIDATES_TRUNCATED=true'
    }
}

exit 0
