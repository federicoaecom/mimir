#requires -Version 7.4
<#
.SYNOPSIS
    Advisory gate: a gate enumeration in the routine's documentation that
    ended up as a proper subset of the gate set the orchestrator runs.

.DESCRIPTION
    Root-cause fix for a real gap: when new gates were added to the
    orchestrator, the "Orchestrator scripts" table was updated, but ANOTHER
    prose enumeration (a closed statement "the advisory gates are X and Y")
    kept the old set. The "is the new term present?" check is blind to this
    case, because the stale sentence does not cite the new term — it cites
    the old ones. Three reviews missed this.

    This gate derives TRUTH from the code: it extracts from the orchestrator
    (tools/Invoke-PrePushMechanicalChecks.ps1) the set of gate scripts it
    actually invokes (Join-Path $PSScriptRoot 'Test-*.ps1'). It then scans
    the root's .md files and flags any LINE that enumerates >= 2 of those
    gates as a proper subset of the real set — a candidate for a stale
    enumeration. The canonical table (one gate per line) and contextual
    mentions of a single gate do not match the ">= 2 on the same line"
    criterion.

    Advisory (severity warn): the agent confronts each candidate — complete
    the enumeration, or justify that the subset is intentional (e.g.: it
    only lists the gates for one theme). Invariant: the doc must not assert
    a gate set that contradicts what the orchestrator runs.

.PARAMETER RootPath
    Repository root. Default: parent of tools/.

.PARAMETER BaseRef
    Accepted for the gates' common contract; this gate is invariant (does not use the diff).

.PARAMETER ChangedFiles
    Accepted for the gates' common contract; unused (the check is repo-wide).

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

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

$orchestratorRel = 'tools/Invoke-PrePushMechanicalChecks.ps1'
$orchestratorPath = Join-Path $resolvedRoot $orchestratorRel

$findings = [System.Collections.Generic.List[object]]::new()
$truncated = $false
$orchestratorGates = @()

if (Test-Path -LiteralPath $orchestratorPath -PathType Leaf) {
    $orchestratorText = [System.IO.File]::ReadAllText($orchestratorPath)

    # Ground truth set: gate scripts the orchestrator invokes, EXCEPT the parse
    # gates (Test-*ScriptsParse.ps1). These are mechanical repo-health gates,
    # always referenced as a fixed, complete pair (PS parse + Python parse),
    # and are not part of the advisory enumeration the doc describes in lists;
    # including them generates a false positive on those legitimate co-mentions.
    $invokeRegex = [regex]::new("Join-Path\s+\`$PSScriptRoot\s+'(?<name>Test-[A-Za-z0-9.\-]+\.ps1)'")
    $gateSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in $invokeRegex.Matches($orchestratorText)) {
        $name = $m.Groups['name'].Value
        if ($name -match 'ScriptsParse\.ps1$') { continue }
        [void]$gateSet.Add($name)
    }
    $orchestratorGates = @($gateSet | Sort-Object)

    if ($orchestratorGates.Count -ge 2) {
        # Gate-script name token in text (inside backticks, after scripts/, etc.).
        $nameTokenRegex = [regex]::new('Test-[A-Za-z0-9.\-]+\.ps1')

        $docFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -File -Filter '*.md' -ErrorAction SilentlyContinue)
        foreach ($docFile in $docFiles) {
            if ($truncated) { break }

            $lines = @()
            try {
                $lines = @([System.IO.File]::ReadAllLines($docFile.FullName))
            } catch {
                continue
            }
            $relPath = ($docFile.Name)

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($truncated) { break }
                $text = $lines[$i]

                $onLine = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($m in $nameTokenRegex.Matches($text)) {
                    if ($gateSet.Contains($m.Value)) {
                        [void]$onLine.Add($m.Value)
                    }
                }

                # Enumeration: >= 2 gates from the set, but a proper subset.
                if ($onLine.Count -lt 2) { continue }
                if ($onLine.Count -ge $orchestratorGates.Count) { continue }

                if ($findings.Count -ge $MaxFindings) {
                    $truncated = $true
                    break
                }

                $listed = @($onLine | Sort-Object)
                $missing = @($orchestratorGates | Where-Object { -not $onLine.Contains($_) })

                $findings.Add([pscustomobject][ordered]@{
                    code     = 'GATE_ENUMERATION_SUBSET'
                    severity = 'warn'
                    path     = ('{0}:{1}' -f $relPath, ($i + 1))
                    message  = ("enumerates {0} of {1} orchestrator gates ({2}); if the sentence describes the gate set, confirm it is complete — missing: {3}" -f $onLine.Count, $orchestratorGates.Count, ($listed -join ', '), ($missing -join ', '))
                })
            }
        }
    }
}

$status = if ($findings.Count -gt 0) { 'warn' } else { 'pass' }

$result = [ordered]@{
    status            = $status
    orchestrator      = $orchestratorRel
    orchestratorGates = @($orchestratorGates)
    candidateCount    = $findings.Count
    truncated         = $truncated
    findings          = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    Write-Output ("STATUS={0}" -f $status)
    Write-Output ("ORCHESTRATOR_GATES={0}" -f ($orchestratorGates -join ', '))
    Write-Output ("CANDIDATE_COUNT={0}" -f $findings.Count)
    foreach ($finding in @($findings)) {
        Write-Output ("GATE_ENUMERATION_SUBSET: {0}: {1}" -f $finding.path, $finding.message)
    }
    if ($truncated) {
        Write-Output 'CANDIDATES_TRUNCATED=true'
    }
}

exit 0
