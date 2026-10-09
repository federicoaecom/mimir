#requires -Version 7.4
<#
.SYNOPSIS
    Compares the KB workspace's local wrappers against the skills repository's canonical examples.

.DESCRIPTION
    Infers the KB prefix from the scripts present under scripts/, enumerates the examples
    in SkillsExamplesPath (*.example.ps1), and checks whether each expected wrapper exists
    locally under its canonical name (<Verb>-<KbPrefix>Kb<Name>.ps1). When no script carries
    the KB prefix yet, takes the KB name from kb-source-metadata.md. Returns:
      INVENTORY_OK                        - every required wrapper present under its canonical name
      INVENTORY_GAPS: <missing names>    - required wrappers missing under their canonical name
      INVENTORY_CUSTOMIZED: <list>        - wrappers present with an objective methodological divergence
                                            (e.g. requires_version_mismatch; on the setup-audit and index-gate wrappers
                                            Test-KbSetupAudit/Test-KbIndexGate, missing_AsJson_passthrough
                                            when the template forwards -AsJson and the local wrapper does not;
                                            forwards_unknown_engine_param when the wrapper forwards an
                                            undeclared parameter to a shared advanced engine;
                                            shared_engine_unresolved when the inferred engine path
                                            does not exist in the canonical base; surface_mismatch when the
                                            local wrapper LOSES a mandatory contract from the template
                                            (mandatory missing/downgraded, no_param_block with the template
                                            mandatory) — param()/ValidateSet surface diff;
                                            unsafe_last_exitcode_after_ps1_engine when the audited wrapper
                                            calls a PowerShell engine by variable and still exits via $LASTEXITCODE)
      INVENTORY_ENGINE_DIAGNOSTIC: <list> - soft diagnostic (canonical engine missing/parse-broken,
                                            engine_unresolved_or_unparseable); does NOT block the
                                            setup state (label outside the aggregator's pendency tokens)
      INVENTORY_SURFACE_ADVISORY: <list>  - surface warning: local wrapper falling behind the template due to an
                                            optional REDUCTION (optional_param_missing,
                                            validateset_reduced, optional_promoted_to_mandatory,
                                            extra_mandatory_added, no_param_block with a template that is optional-only);
                                            does NOT block (label outside the aggregator's pendency
                                            tokens); loss of a mandatory one comes out as INVENTORY_CUSTOMIZED
      INVENTORY_RECOMMENDED_MISSING: <list> - recommended wrappers missing due to objective signals
      INVENTORY_UNKNOWN: <reason>         - the state could not be determined

.PARAMETER KbWorkspaceRoot
    Root of the KB workspace.

.PARAMETER SkillsExamplesPath
    Path to the mimir-lite repository's setup examples folder
    (skills/mimir-lite/workflows/setup/examples).

.OUTPUTS
    String: "INVENTORY_OK", "INVENTORY_GAPS: <missing names>",
    "INVENTORY_CUSTOMIZED: <names and reasons>",
    "INVENTORY_ENGINE_DIAGNOSTIC: <names and reasons>",
    "INVENTORY_SURFACE_ADVISORY: <names and reasons>",
    "INVENTORY_RECOMMENDED_MISSING: <recommended names>", or
    "INVENTORY_UNKNOWN: <reason>"

.EXAMPLE
    .\Test-MimirWrapperInventory.ps1 `
        -KbWorkspaceRoot "C:\KBs\SampleKb" `
        -SkillsExamplesPath "C:\path\to\mimir-lite\skills\mimir-lite\workflows\setup\examples"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$KbWorkspaceRoot,

    [Parameter(Mandatory = $true)]
    [string]$SkillsExamplesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Helper for the generic forwards_unknown_engine_param check (resolves the shared engine by
# value + AST; without executing the engine or requiring a KB). EnginesRoot = the auditor's scripts/ ($PSScriptRoot).
. (Join-Path $PSScriptRoot 'MimirWrapperEngineParamSupport.ps1')

$scriptsPath = Join-Path $KbWorkspaceRoot 'scripts'

function Get-RequiresVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $pattern = '^\s*#requires\s+-version\s+(?<version>\d+(\.\d+)*)\b'
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $match = [regex]::Match($line, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups['version'].Value
        }

        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0) {
            continue
        }
        if ($trimmed.StartsWith('#')) {
            continue
        }
        if ($trimmed -eq '<#') {
            continue
        }

        break
    }

    return $null
}

if (-not (Test-Path -LiteralPath $scriptsPath -PathType Container)) {
    Write-Output "INVENTORY_UNKNOWN: scripts folder not found in $KbWorkspaceRoot"
    exit 0
}

if (-not (Test-Path -LiteralPath $SkillsExamplesPath -PathType Container)) {
    Write-Output "INVENTORY_UNKNOWN: examples folder not found in $SkillsExamplesPath"
    exit 0
}

# Infer the KB prefix from existing scripts (e.g. Test-MyCinemaKbIndexGate.ps1 -> MyCinema)
$kbPrefix = $null
foreach ($f in Get-ChildItem -LiteralPath $scriptsPath -Filter '*.ps1' -Name | Sort-Object) {
    if ($f -match '^[A-Za-z]+-([A-Za-z0-9]+)Kb[A-Za-z]') {
        $kbPrefix = $Matches[1]
        break
    }
}

# When inference fails, try to get the KB name from kb-source-metadata.md
if ([string]::IsNullOrWhiteSpace($kbPrefix)) {
    $metadataPath = Join-Path $KbWorkspaceRoot 'kb-source-metadata.md'
    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        $inSourceVersion = $false
        foreach ($line in [System.IO.File]::ReadAllLines($metadataPath)) {
            if ($line -match '^\s*kb_name\s*[:=]\s*(?<value>\S+)') {
                $candidate = $Matches['value'].Trim()
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    $kbPrefix = $candidate; break
                }
            }
            if ($line -match '^\s*##\s+Source/Version') { $inSourceVersion = $true; continue }
            if ($inSourceVersion -and $line -match '^\s*##\s') { $inSourceVersion = $false }
            if ($inSourceVersion -and $line -match '^\s*\|\s*name\s*\|\s*(?<value>[^|]+)\|') {
                $candidate = $Matches['value'].Trim()
                if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate -notmatch '^[-\s]+$') {
                    $kbPrefix = $candidate; break
                }
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($kbPrefix)) {
    Write-Output 'INVENTORY_UNKNOWN: could not infer the KB prefix from the scripts nor from kb-source-metadata.md'
    exit 0
}

function Test-KbIdentityMetadata {
    param([string]$RootPath)

    $metadataPath = Join-Path $RootPath 'kb-source-metadata.md'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return $false
    }

    $metadataText = [System.IO.File]::ReadAllText($metadataPath)
    return $metadataText -match '(?i)(\bkb\s*\(GUID\)|\bsource_guid\b|\bUNCPath\b|\busername\b|\bversionGuid\b|\bVersion/guid\b)'
}

$recommendedEvidenceByBaseName = @{
    'Resolve-KbIdentity' = (Test-KbIdentityMetadata -RootPath $KbWorkspaceRoot)
}

# Map each example to the expected local name and check its presence
$absent      = [System.Collections.Generic.List[string]]::new()
$customized  = [System.Collections.Generic.List[string]]::new()
$recommendedMissing = [System.Collections.Generic.List[string]]::new()
$engineDiagnostics = [System.Collections.Generic.List[string]]::new()
$surfaceAdvisory = [System.Collections.Generic.List[string]]::new()
$optionalBaseNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
[void]$optionalBaseNames.Add('Resolve-KbIdentity')
$requiresVersionExemptBaseNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
[void]$requiresVersionExemptBaseNames.Add('Test-KbPowerShellRuntime')

foreach ($exampleFile in Get-ChildItem -LiteralPath $SkillsExamplesPath -Filter '*.example.ps1' -Name | Sort-Object) {
    $baseName = $exampleFile -replace '\.example\.ps1$', ''

    if ($baseName -match '^([A-Za-z]+-)(Kb.+)$') {
        $standardLocalName = "$($Matches[1])${kbPrefix}$($Matches[2]).ps1"
    } else {
        $standardLocalName = "$baseName.ps1"
    }

    $standardPath   = Join-Path $scriptsPath $standardLocalName
    $examplePath    = Join-Path $SkillsExamplesPath $exampleFile
    $standardExists = Test-Path -LiteralPath $standardPath -PathType Leaf

    if ($standardExists) {
        if (-not $requiresVersionExemptBaseNames.Contains($baseName)) {
            $canonicalRequiresVersion = Get-RequiresVersion -Path $examplePath
            $localRequiresVersion = Get-RequiresVersion -Path $standardPath
            if ($canonicalRequiresVersion -and $localRequiresVersion -ne $canonicalRequiresVersion) {
                $localLabel = if ($localRequiresVersion) { $localRequiresVersion } else { 'missing' }
                $customized.Add(('{0}(reason=requires_version_mismatch: local={1} canonical={2})' -f $standardLocalName, $localLabel, $canonicalRequiresVersion))
            }
        }

        if ($baseName -ieq 'Test-KbSetupAudit' -or $baseName -ieq 'Test-KbIndexGate') {
            $exampleText = [System.IO.File]::ReadAllText($examplePath)
            $localText = [System.IO.File]::ReadAllText($standardPath)
            # Detects the FORWARDING of -AsJson to the engine, not just the mere mention of the
            # term: a wrapper with `[switch]$AsJson` declared but without forwarding (partial
            # migration) has 'AsJson' in the text but still cannot return the structured verdict. The two templates forward it in
            # distinct ways, both covered: setup-audit via `-AsJson:$AsJson` (token
            # `-AsJson`); index-gate via `$forward['AsJson']` (quoted key). The `$AsJson`
            # param alone matches neither.
            if ($exampleText -match 'AsJson' -and $localText -notmatch '(-AsJson|[''"]AsJson)') {
                $customized.Add(('{0}(reason=missing_AsJson_passthrough)' -f $standardLocalName))
            }
        }

        if ($baseName -ieq 'Update-KbFromXpz') {
            $exampleText = [System.IO.File]::ReadAllText($examplePath)
            $localText = [System.IO.File]::ReadAllText($standardPath)
            # Engine CONSUMPTION contract drift: the canonical template consumes
            # Sync-GeneXusXpzToXml.ps1's stdout as the JSON v1 contract (ConvertFrom-Json). A
            # local wrapper that still treats that stdout as TEXT (without ConvertFrom-Json) consumes
            # the stale output shape and, without this check, would pass as non-customized. Same
            # heuristic mechanic (local text vs. template) as the preceding missing_AsJson_passthrough:
            # flags when the template consumes JSON and the local one doesn't. KNOWN LIMIT (conservative
            # textual heuristic, not proof of conformance): does not detect partial migration
            # (ConvertFrom-Json present in one branch but stdout consumed as text in another) nor
            # alternative parsers (System.Text.Json, Invoke-RestMethod). These cases are matter
            # for the contract-version follow-up (Kind/SchemaVersion).
            if ($exampleText -match 'ConvertFrom-Json' -and $localText -notmatch 'ConvertFrom-Json') {
                $customized.Add(('{0}(reason=consumes_legacy_text_stdout)' -f $standardLocalName))
            }
        }

        $localTextForEngineExit = [System.IO.File]::ReadAllText($standardPath)
        # Shared engines and local helper wrappers are .ps1; a successful PowerShell call
        # does not guarantee $LASTEXITCODE is set, and a stale value can leak through. Under
        # StrictMode, `exit $LASTEXITCODE` can fail or return a stale code after
        # running the engine. Within the audited scope of local wrappers, any call by variable
        # followed by a raw LASTEXITCODE exit is unsafe, regardless of the variable's name.
        # The current template zeroes $global:LASTEXITCODE before the call and reads the variable via
        # Get-Variable, keeping `$?` as a fallback.
        if (
            $localTextForEngineExit -match '&\s+\$[A-Za-z_][A-Za-z0-9_]*\b' -and
            $localTextForEngineExit -match 'exit\s+\$LASTEXITCODE\b'
        ) {
            $customized.Add(('{0}(reason=unsafe_last_exitcode_after_ps1_engine)' -f $standardLocalName))
        }

        # Generic check: a parameter forwarded to a shared advanced engine that the engine does not
        # declare (forwards_unknown_engine_param), a nonexistent engine path
        # (shared_engine_unresolved) -> wrapper-drift signals, become INVENTORY_CUSTOMIZED (captured
        # by the aggregator). Unresolvable/parse-broken canonical engine -> INVENTORY_ENGINE_DIAGNOSTIC
        # (skills repo infra; does not block the KB workspace's state).
        $engineParamFinding = Get-MimirWrapperEngineParamFinding -WrapperPath $standardPath -EnginesRoot $PSScriptRoot
        foreach ($sig in $engineParamFinding.Signals) {
            $customized.Add(('{0}(reason={1}: {2})' -f $standardLocalName, $sig.Reason, $sig.Detail))
        }
        foreach ($diag in $engineParamFinding.EngineDiagnostics) {
            $engineDiagnostics.Add(('{0}(reason={1}: {2})' -f $standardLocalName, $diag.Reason, $diag.Detail))
        }

        # Local-wrapper vs. canonical-template surface diff (Get-MimirWrapperSurfaceFinding helper,
        # wrapper->template direction, complementary to forwards_unknown_engine_param above). LOSS of
        # a mandatory contract (mandatory missing/downgraded; no_param_block with the template mandatory)
        # -> INVENTORY_CUSTOMIZED reason=surface_mismatch (captured by the aggregator). Optional/
        # ValidateSet reductions -> INVENTORY_SURFACE_ADVISORY (its own label, OUTSIDE the aggregator's
        # pendency regex -> does not block). Legitimate surplus/delegation -> quiet. Coexists
        # with the per-token checks above (accepted redundancy, do not deduplicate).
        $surfaceFinding = Get-MimirWrapperSurfaceFinding -TemplatePath $examplePath -LocalPath $standardPath
        foreach ($b in $surfaceFinding.Blocking) {
            $blockDetail = if ($b.Detail) { '{0} {1}' -f $b.Reason, $b.Detail } else { [string]$b.Reason }
            $customized.Add(('{0}(reason=surface_mismatch: {1})' -f $standardLocalName, $blockDetail))
        }
        foreach ($a in $surfaceFinding.Advisory) {
            $advBody = if ($a.Detail) { '{0}: {1}' -f $a.Reason, $a.Detail } else { [string]$a.Reason }
            $surfaceAdvisory.Add(('{0}(reason={1})' -f $standardLocalName, $advBody))
        }
    } elseif ($optionalBaseNames.Contains($baseName)) {
        if ($recommendedEvidenceByBaseName.ContainsKey($baseName) -and $recommendedEvidenceByBaseName[$baseName]) {
            $recommendedMissing.Add($standardLocalName)
        }
    } else {
        $absent.Add($standardLocalName)
    }
}

$statusParts = [System.Collections.Generic.List[string]]::new()
if ($customized.Count -gt 0) {
    $statusParts.Add("INVENTORY_CUSTOMIZED: $($customized -join ', ')")
}
if ($absent.Count -gt 0) {
    $statusParts.Add("INVENTORY_GAPS: $($absent -join ', ')")
}
if ($recommendedMissing.Count -gt 0) {
    $statusParts.Add("INVENTORY_RECOMMENDED_MISSING: $($recommendedMissing -join ', ')")
}
if ($engineDiagnostics.Count -gt 0) {
    # Soft channel: label deliberately OUTSIDE the aggregator's pendency regex
    # (Test-MimirSetupAudit.ps1) -> does not block the KB workspace's state.
    $statusParts.Add("INVENTORY_ENGINE_DIAGNOSTIC: $($engineDiagnostics -join ', ')")
}
if ($surfaceAdvisory.Count -gt 0) {
    # Surface warning channel: label deliberately OUTSIDE the aggregator's pendency
    # regex (Test-MimirSetupAudit.ps1) -> does not block the KB workspace's state.
    # Only optional/ValidateSet/no_param_block-optional reduction; loss of a mandatory contract already
    # came out as INVENTORY_CUSTOMIZED (reason=surface_mismatch) above.
    $statusParts.Add("INVENTORY_SURFACE_ADVISORY: $($surfaceAdvisory -join ', ')")
}

if ($statusParts.Count -eq 0) {
    Write-Output 'INVENTORY_OK'
} else {
    Write-Output ($statusParts -join ' | ')
}
exit 0
