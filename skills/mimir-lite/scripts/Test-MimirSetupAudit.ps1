#requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KbRoot,

    [Parameter(Mandatory = $true)]
    [string]$GateWrapperPath,

    [Parameter(Mandatory = $true)]
    [string]$MetadataWrapperTestPath,

    [string]$PowerShellRuntimeTestPath,

    [string]$NamingWrapperPath,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Accumulator for the optional structured contract (-AsJson). The textual default
# (Emit-Line) remains byte-identical; -AsJson emits the SAME pairs as JSON,
# consumed by agents and callers that read the setup audit as a structured verdict.
$script:emitted = [ordered]@{}

function Invoke-WrapperText {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "BLOCK: wrapper missing: $Path"
    }

    $output = & $Path 2>&1
    if (-not $?) {
        $text = (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "BLOCK: wrapper failed with no output: $Path"
        }

        throw $text
    }

    return (($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
}

function Get-MetadataField {
    param(
        [string[]]$Lines,
        [string]$FieldName
    )

    $pattern = '^\s*{0}\s*[:=]\s*(?<value>.+?)\s*$' -f [regex]::Escape($FieldName)
    foreach ($line in $Lines) {
        $match = [regex]::Match($line, $pattern)
        if ($match.Success) {
            return $match.Groups['value'].Value.Trim()
        }
    }

    return $null
}

function Normalize-Value {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return $null
    }

    $trimmed = $Value.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed -eq '(missing)') {
        return $null
    }

    return $trimmed
}

function Emit-Line {
    param(
        [string]$Key,
        [string]$Value
    )

    # A repeated key (e.g. multi-part 'wrappers/inventory') accumulates as a list,
    # preserving every part in the structured contract's JSON (-AsJson). A unique
    # key remains a string.
    if ($script:emitted.Contains($Key)) {
        $existing = $script:emitted[$Key]
        if ($existing -is [System.Collections.Generic.List[string]]) {
            [void]$existing.Add([string]$Value)
        } else {
            $list = [System.Collections.Generic.List[string]]::new()
            [void]$list.Add([string]$existing)
            [void]$list.Add([string]$Value)
            $script:emitted[$Key] = $list
        }
    } else {
        $script:emitted[$Key] = $Value
    }
    if (-not $AsJson) {
        '{0}: {1}' -f $Key, $Value
    }
}

function Get-SuggestedPowerShellRuntimeWrapperPath {
    param([string]$RootPath)

    $fullRootPath = [System.IO.Path]::GetFullPath($RootPath)
    $kbName = Split-Path -Leaf $fullRootPath
    $safeName = $kbName -replace '[^A-Za-z0-9]', ''
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'Kb'
    }

    return (Join-Path (Join-Path $fullRootPath 'scripts') ('Test-{0}KbPowerShellRuntime.ps1' -f $safeName))
}

function Resolve-PowerShellRuntimeTestPath {
    param(
        [string]$RootPath,
        [string]$ExplicitPath
    )

    $suggestedPath = Get-SuggestedPowerShellRuntimeWrapperPath -RootPath $RootPath
    $examplePath = Join-Path $scriptDir '..\workflows\setup\examples\Test-KbPowerShellRuntime.example.ps1'

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return [ordered]@{
            path = $ExplicitPath
            source = 'explicit'
            suggestedPath = $suggestedPath
            examplePath = $examplePath
        }
    }

    $scriptsPath = Join-Path $RootPath 'scripts'
    $detected = @()
    if (Test-Path -LiteralPath $scriptsPath -PathType Container) {
        $detected = @(Get-ChildItem -LiteralPath $scriptsPath -File -Filter 'Test-*KbPowerShellRuntime.ps1' | Sort-Object Name)
    }

    if ($detected.Count -gt 0) {
        return [ordered]@{
            path = $detected[0].FullName
            source = if ($detected.Count -eq 1) { 'autodetected' } else { 'autodetected-first-of-many' }
            candidates = @($detected | ForEach-Object { $_.FullName })
            suggestedPath = $suggestedPath
            examplePath = $examplePath
        }
    }

    return [ordered]@{
        path = $null
        source = 'missing'
        candidates = @()
        suggestedPath = $suggestedPath
        examplePath = $examplePath
    }
}

$scriptDir = Split-Path -Parent $PSCommandPath

$powerShellRuntimeRaw = $null
$powerShellRuntimeStatus = $null
$powerShellRuntimeDetection = Resolve-PowerShellRuntimeTestPath -RootPath $KbRoot -ExplicitPath $PowerShellRuntimeTestPath
try {
    if (-not $powerShellRuntimeDetection['path']) {
        throw ("BLOCK: PowerShell runtime wrapper not provided nor detected in scripts/Test-*KbPowerShellRuntime.ps1; create the suggested local wrapper at {0} from {1}" -f $powerShellRuntimeDetection['suggestedPath'], $powerShellRuntimeDetection['examplePath'])
    }
    $powerShellRuntimeRaw = Invoke-WrapperText -Path $powerShellRuntimeDetection['path']
    if ($powerShellRuntimeRaw -match '\bPOWERSHELL_RUNTIME_OK\b') {
        $powerShellRuntimeStatus = 'OK'
    } else {
        $powerShellRuntimeStatus = 'BLOCK'
    }
} catch {
    $powerShellRuntimeRaw = $_.Exception.Message.Trim()
    $powerShellRuntimeStatus = 'BLOCK'
}

if ($powerShellRuntimeStatus -ne 'OK') {
    Emit-Line -Key 'powershell/runtime' -Value $powerShellRuntimeStatus
    Emit-Line -Key 'powershell/runtime.evidence' -Value $(if ($powerShellRuntimeRaw) { $powerShellRuntimeRaw.Replace([Environment]::NewLine, ' | ') } else { '(no output)' })
    Emit-Line -Key 'powershell/runtime.detection' -Value $powerShellRuntimeDetection['source']
    Emit-Line -Key 'powershell/runtime.suggested_wrapper' -Value $powerShellRuntimeDetection['suggestedPath']
    Emit-Line -Key 'powershell/runtime.template' -Value $powerShellRuntimeDetection['examplePath']
    Emit-Line -Key 'suggested_operational_state' -Value 'powershell_runtime_blocked'
    if ($AsJson) { $script:emitted | ConvertTo-Json -Depth 5 }
    exit 1
}

# Safety net for the "-AsJson never throws" contract (symmetric to Test-MimirKbIndexGate):
# any throw from here on (missing metadata, a read failure, etc.) becomes, under
# -AsJson, JSON with a blocking state + error -- never a throw that a caller
# would wrongly interpret as "stale wrapper".
try {

$metadataPath = Join-Path $KbRoot 'kb-source-metadata.md'
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "BLOCK: kb-source-metadata.md not found: $metadataPath"
}

$metadataLines = [System.IO.File]::ReadAllLines($metadataPath)
$lastMaterialization = Normalize-Value (Get-MetadataField -Lines $metadataLines -FieldName 'last_xpz_materialization_run_at')

$gateRaw = $null
$gateStatus = $null
$inventorySemanticStatus = $null
try {
    $gateRaw = Invoke-WrapperText -Path $GateWrapperPath
    $gateStatus = if ($gateRaw -match '\bGATE_OK\b') { 'OK' } else { 'PENDING' }
} catch {
    $gateRaw = $_.Exception.Message.Trim()
    $gateStatus = 'BLOCK'
}
# Before the first sync, the index does not exist yet by design: the gate's
# "first index build pending" block is a pending step, not a failure.
if ($gateStatus -eq 'BLOCK' -and -not $lastMaterialization -and $gateRaw -match '^(BLOCK:\s*)?first index build pending:') {
    $gateStatus = 'PENDING'
    $gateRaw = $gateRaw -replace '^BLOCK:\s*', ''
}

$inventorySemanticMatch = if ($gateRaw) {
    [regex]::Match($gateRaw, 'inventory_validation_status\s*[:=]\s*(?<value>\S+)')
} else {
    [regex]::Match('', 'a^')
}
if ($inventorySemanticMatch.Success) {
    $inventorySemanticStatus = $inventorySemanticMatch.Groups['value'].Value.Trim()
} elseif ($gateStatus -eq 'BLOCK' -and $gateRaw -match 'semantic inventory|inventory_validation_status') {
    $inventorySemanticStatus = 'BLOCK'
} else {
    $inventorySemanticStatus = 'PENDING'
}

$metadataWrapperRaw = $null
$metadataWrapperStatus = $null
try {
    $metadataWrapperRaw = Invoke-WrapperText -Path $MetadataWrapperTestPath
    if ($metadataWrapperRaw -match '\bMETADATA_WRAPPER_OK\b') {
        $metadataWrapperStatus = 'OK'
    } elseif ($metadataWrapperRaw -match '\bPENDING_DATA\b') {
        $metadataWrapperStatus = 'PENDING_DATA'
    } else {
        $metadataWrapperStatus = 'PENDING'
    }
} catch {
    $metadataWrapperRaw = $_.Exception.Message.Trim()
    if ($metadataWrapperRaw -match '\bPENDING_DATA\b') {
        $metadataWrapperStatus = 'PENDING_DATA'
    } else {
        $metadataWrapperStatus = 'BLOCK'
    }
}

$syncStatus = if ($lastMaterialization) { 'OK' } else { 'PENDING' }
$syncEvidence = if ($lastMaterialization) {
    "last_xpz_materialization_run_at=$lastMaterialization"
} else {
    'last_xpz_materialization_run_at missing'
}

$namingRaw = $null
$namingStatus = 'INDETERMINATE'
if ($lastMaterialization) {
    try {
        if (-not $NamingWrapperPath) {
            $defaultNamingScriptPath = Join-Path $scriptDir 'Test-MimirKbObjectsXmlNaming.ps1'
            if (Test-Path -LiteralPath $defaultNamingScriptPath -PathType Leaf) {
                $namingOutput = & $defaultNamingScriptPath -KbWorkspaceRoot $KbRoot -AsJson 2>&1
            } else {
                throw "BLOCK: naming wrapper not provided"
            }
        } else {
            $namingOutput = & $NamingWrapperPath -AsJson 2>&1
        }

        $namingExitCode = $LASTEXITCODE
        $namingRaw = (($namingOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine).Trim()
        $namingData = $namingRaw | ConvertFrom-Json
        $indetermined = @($namingData.all | Where-Object { $_.NamingStatus -in @('INDETERMINATE', 'UNKNOWN_TYPE') })
        if ($namingData.status -eq 'NAMING_DIVERGENT' -or $namingExitCode -eq 1) {
            $namingStatus = 'DIVERGENT'
        } elseif ($namingData.status -eq 'NAMING_INDETERMINATE' -or $indetermined.Count -gt 0) {
            $namingStatus = 'INDETERMINATE'
        } elseif ($namingData.status -eq 'NAMING_OK' -and $namingExitCode -eq 0) {
            $namingStatus = 'OK'
        } else {
            $namingStatus = 'INDETERMINATE'
        }
        $divergentList = @($namingData.divergent) -join ','
        $namingRaw = "status=$($namingData.status); divergent=$divergentList; total=$(@($namingData.all).Count)"
    } catch {
        $namingRaw = $_.Exception.Message.Trim()
        $namingStatus = 'INDETERMINATE'
    }
} else {
    $namingRaw = 'last_xpz_materialization_run_at missing; naming not audited'
}

$declarativeFiles = @('AGENTS.md', 'README.md') | ForEach-Object { Join-Path $KbRoot $_ }
$declarativeDriftEntries = @()
$declarativeIgnoreCase = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$declarativeDriftPattern = [regex]::new('\blast_(xpz_materialization|index_build)_run_at\b[^\r\n]*?[:=][^\r\n]*?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', $declarativeIgnoreCase)
foreach ($declarativePath in $declarativeFiles) {
    if (-not (Test-Path -LiteralPath $declarativePath -PathType Leaf)) { continue }
    $declarativeText = [System.IO.File]::ReadAllText($declarativePath)
    $driftMatches = $declarativeDriftPattern.Matches($declarativeText)
    if ($driftMatches.Count -gt 0) {
        $driftFields = @($driftMatches | ForEach-Object { (@($_.Value -split '[:=]', 2))[0].Trim().Trim('`').Trim() } | Sort-Object -Unique)
        $declarativeDriftEntries += ('{0}:{1}' -f (Split-Path -Leaf $declarativePath), ($driftFields -join ','))
    }
}
if ($declarativeDriftEntries.Count -gt 0) {
    $declarativeStatus = 'LITERAL_TIMESTAMP_DRIFT'
    $declarativeEvidence = $declarativeDriftEntries -join '; '
    $declarativeRecommendedAction = 'remove literal timestamps from AGENTS.md/README.md and replace them with pointers to the authoritative sources; do not update the literal values'
} else {
    $declarativeStatus = 'OK'
    $declarativeEvidence = 'no literal last_xpz_materialization_run_at or last_index_build_run_at timestamps in local AGENTS.md/README.md'
    $declarativeRecommendedAction = $null
}
$hasDeclarativeDrift = $declarativeStatus -ne 'OK'

$inventoryScriptPath = Join-Path $scriptDir 'Test-MimirWrapperInventory.ps1'
$examplesPath = Join-Path $scriptDir '..\workflows\setup\examples'
$inventoryStatus = 'INVENTORY_UNKNOWN'
if (Test-Path -LiteralPath $inventoryScriptPath -PathType Leaf) {
    try {
        $inventoryOutput = (& $inventoryScriptPath -KbWorkspaceRoot $KbRoot -SkillsExamplesPath $examplesPath 2>&1 |
            ForEach-Object { $_.ToString() }) -join ' '
        $inventoryStatus = $inventoryOutput.Trim()
    } catch {
        $inventoryStatus = "INVENTORY_UNKNOWN: $($_.Exception.Message.Trim())"
    }
} else {
    $inventoryStatus = 'INVENTORY_UNKNOWN: Test-MimirWrapperInventory.ps1 engine missing'
}

# Inventory methodology-pendency regex: ONLY these 2 tokens block the setup state.
# Deliberately OUT of this list (by design, not by accident): INVENTORY_ENGINE_DIAGNOSTIC (skills
# repo infra) and INVENTORY_SURFACE_ADVISORY (optional/ValidateSet reduction of the surface diff) —
# both are consultative warnings that do NOT block. Loss of the surface diff's mandatory contract
# already reaches here via INVENTORY_CUSTOMIZED (reason=surface_mismatch). Do NOT add the warning
# labels to this regex (regression guard: Test-MimirWrapperInventorySelfTest.ps1).
$hasInventoryMethodologyPendencies = $inventoryStatus -match '\b(INVENTORY_GAPS|INVENTORY_CUSTOMIZED)\b'
$hasMetadataWrapperPendencies = $metadataWrapperStatus -ne 'OK'

$suggestedState = switch ($true) {
    ($powerShellRuntimeStatus -ne 'OK') { 'powershell_runtime_blocked'; break }
    ($syncStatus -eq 'PENDING') { 'ready_for_first_materialization'; break }
    ($namingStatus -eq 'DIVERGENT') { 'kb_objects_naming_pending'; break }
    ($hasMetadataWrapperPendencies) { 'methodology_update_pending'; break }
    ($hasInventoryMethodologyPendencies) { 'methodology_update_pending'; break }
    ($hasDeclarativeDrift) { 'methodology_update_pending'; break }
    ($syncStatus -eq 'OK' -and $gateStatus -eq 'OK' -and $inventorySemanticStatus -eq 'OK') { 'materialized_and_index_validated'; break }
    default { 'wrappers_updated' }
}

Emit-Line -Key 'powershell/runtime' -Value $powerShellRuntimeStatus
Emit-Line -Key 'powershell/runtime.evidence' -Value $(if ($powerShellRuntimeRaw) { $powerShellRuntimeRaw.Replace([Environment]::NewLine, ' | ') } else { '(no output)' })
Emit-Line -Key 'powershell/runtime.detection' -Value $powerShellRuntimeDetection['source']
Emit-Line -Key 'sync/materialization' -Value $syncStatus
Emit-Line -Key 'sync/materialization.evidence' -Value $syncEvidence
Emit-Line -Key 'naming/kb-objects' -Value $namingStatus
Emit-Line -Key 'naming/kb-objects.evidence' -Value $(if ($namingRaw) { $namingRaw.Replace([Environment]::NewLine, ' | ') } else { '(no output)' })
Emit-Line -Key 'index/gate' -Value $gateStatus
Emit-Line -Key 'index/gate.evidence' -Value $(if ($gateRaw) { $gateRaw.Replace([Environment]::NewLine, ' | ') } else { '(no output)' })
Emit-Line -Key 'index/semantics' -Value $inventorySemanticStatus
Emit-Line -Key 'index/semantics.evidence' -Value $(if ($gateRaw) { $gateRaw.Replace([Environment]::NewLine, ' | ') } else { '(no output)' })
Emit-Line -Key 'metadata wrapper' -Value $metadataWrapperStatus
Emit-Line -Key 'metadata wrapper.evidence' -Value $(if ($metadataWrapperRaw) { $metadataWrapperRaw.Replace([Environment]::NewLine, ' | ') } else { '(no output)' })
Emit-Line -Key 'declarative/timestamps' -Value $declarativeStatus
Emit-Line -Key 'declarative/timestamps.evidence' -Value $declarativeEvidence
if (-not [string]::IsNullOrWhiteSpace($declarativeRecommendedAction)) {
    Emit-Line -Key 'declarative/timestamps.recommended_action' -Value $declarativeRecommendedAction
}
if ($inventoryStatus -match '\|') {
    foreach ($inventoryPart in @($inventoryStatus -split '\|')) {
        $trimmedInventoryPart = $inventoryPart.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedInventoryPart)) {
            Emit-Line -Key 'wrappers/inventory' -Value $trimmedInventoryPart
        }
    }
} else {
    Emit-Line -Key 'wrappers/inventory' -Value $inventoryStatus
}
Emit-Line -Key 'suggested_operational_state' -Value $suggestedState

if ($AsJson) { $script:emitted | ConvertTo-Json -Depth 5 }

} catch {
    # Exception outside the inner try/catch blocks (e.g. kb-source-metadata.md missing).
    # Under -AsJson, honor the contract: blocking state (audit_incomplete) +
    # error, never a throw. In text mode, re-throw (backward-compatible default).
    if ($AsJson) {
        if (-not $script:emitted.Contains('suggested_operational_state')) {
            $script:emitted['suggested_operational_state'] = 'audit_incomplete'
        }
        $script:emitted['error'] = ($_.Exception.Message -replace '^BLOCK:\s*', '')
        $script:emitted | ConvertTo-Json -Depth 5
        exit 1
    }
    throw
}
