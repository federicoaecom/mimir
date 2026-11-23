#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to update `KbObjectsXml` from a KB XPZ/XML.

.DESCRIPTION
Uses the paths of the KB workspace and delegates extraction/verification to the
shared engine of this methodology base.

.PARAMETER InputPath
Path to an .xpz file, to the XML of the exported package, to the folder that
contains that XML, to a GeneXus 7.0-and-earlier .xpw text export, or to a .zip
holding .xpw files.

.PARAMETER VerifyOnly
Runs the check only, without rewriting files in the destination.

.PARAMETER FullSnapshot
In addition to checking the current package, compares the entire destination
snapshot with the package content. Use this mode for full KB exports.

.PARAMETER ReportPath
Optional path to save a JSON report with the result.

.PARAMETER KeepReport
Keeps the JSON report even when the run ends without error.

.PARAMETER KbMetadataPath
Optional path to save KB metadata in Markdown.
When omitted, the wrapper uses `kb-source-metadata.md` at the root of the KB
workspace. With `-KbMetadataPath` active, the shared engine performs a
**surgical** update of the materialization fields, preserving
`last_setup_audit_run_at`, `setup_contract_signature_*` and the frontmatter outside its scope.

.PARAMETER IndexUpdateScriptPath
Optional path of the local wrapper that regenerates the derived index after a
successful materialization. When omitted, uses
`Rebuild-KbIntelligenceIndex.ps1` in the same folder as this wrapper.

.PARAMETER IndexValidationCasesPath
Optional path to validation cases used in the mandatory index refresh.

.PARAMETER NoGitSummary
Suppresses the local Git change summary for `KbObjectsXml`.

.PARAMETER ExpectedItems
Optional list of expected items in `Type:Name` format, forwarded to the shared
engine to compare the expected focus against the official KB return. When
invoking through `pwsh -File` from Bash/CMD, prefer a single comma-separated
string to avoid parser ambiguity between shells.

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout. Use this parameter when the
shared checkout lives at a different local path.

.NOTES
Completion contract (KbIntelligence rigor; see the sync workflow and the README):
- Success: XPZ/XML materialization into KbObjectsXml and index refresh completed (exit 0).
- Failure with message PREREQUISITE MISSING: no usable Python 3.8 or later, found as
  python3, python, or py -3, for the rebuild (engine Build-KbIntelligenceIndex.ps1
  returns exit 8). The materialization may have completed; the official flow still
  failed because the index was not regenerated.
  Do not treat it as a failure of the exported package. Install Python 3.8 or later and rerun
  Rebuild-KbIntelligenceIndex.ps1 before broad triage or declaring the sync OK.
- Failure with exit 12 from the rebuild: the corpus is not complete (a sync failed or was
  interrupted, the corpus records no synchronization state, or its state file cannot be read).
  XML files may have been written, but the corpus is not certified, so the index was not
  rebuilt and queries stay blocked. Follow the builder's recovery: for an incomplete corpus,
  re-run the sync of the package that left it incomplete (when the sync reported one) or run a
  verified -FullSnapshot sync of a full KB export; for a corpus with no state or an unreadable
  one, only a verified -FullSnapshot sync of a full KB export. Then rebuild.
- Failure with exit 13 from the rebuild: the corpus lock stayed busy (another sync, index build,
  or query). Wait for it to finish, then run Rebuild-KbIntelligenceIndex.ps1.
- Other failures: materialization error or index engine error (do not confuse with missing Python).

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Update-KbFromXpz.ps1" -InputPath "<WorkspaceRoot>/IdeXpzExports/MyPackage.xpz" -ExpectedItems 'Transaction:Customer'

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Update-KbFromXpz.ps1" -InputPath "<WorkspaceRoot>/IdeXpzExports/MyPackage.xpz" -ExpectedItems 'Transaction:Customer,Procedure:GenerateInvoice'
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [switch]$VerifyOnly,

    [switch]$FullSnapshot,

    [string]$ReportPath,

    [switch]$KeepReport,

    [string]$KbMetadataPath,

    [string]$IndexUpdateScriptPath,

    [string]$IndexValidationCasesPath,

    [string[]]$ExpectedItems = @(),

    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite",

    [switch]$NoGitSummary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Human diagnostics go to STDERR, never to stdout. When this wrapper runs as a
# child process (pwsh -File) and the caller captures stdout for `ConvertFrom-Json`, the
# child's Host/Warning/Information streams LEAK into that stdout (measured empirically);
# only [Console]::Error (fd 2) stays out. Contract: stdout = exclusively the engine's JSON line
# (re-emitted at the end); everything else (summaries, warnings) goes out through here.
function Write-HumanLine {
    param([string]$Message = '')
    [Console]::Error.WriteLine($Message)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $SharedSkillsRoot "skills\mimir-lite\scripts\Sync-GeneXusXpzToXml.ps1"
$destinationRoot = Join-Path $repoRoot "KbObjectsXml"

if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "Engine script not found: $enginePath"
}

$pythonPrerequisiteScript = Join-Path $SharedSkillsRoot 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1'
if (-not (Test-Path -LiteralPath $pythonPrerequisiteScript -PathType Leaf)) {
    throw "Shared prerequisite script not found: $pythonPrerequisiteScript"
}

. $pythonPrerequisiteScript

$reminderScriptPath = Join-Path $SharedSkillsRoot 'skills\mimir-lite\scripts\Test-MimirCatalogOverrideSessionReminder.ps1'
if (Test-Path -LiteralPath $reminderScriptPath -PathType Leaf) {
    $reminderResult = & $reminderScriptPath -KbWorkspaceRoot $repoRoot -AsJson | ConvertFrom-Json
    if ($reminderResult.noticeRequired -and -not [string]::IsNullOrWhiteSpace($reminderResult.message)) {
        Write-HumanLine ("WARNING: " + $reminderResult.message)
    }
}

if (-not $VerifyOnly) {
    $inventoryScriptPath = Join-Path $SharedSkillsRoot 'skills\mimir-lite\scripts\Get-GeneXusXpzObjectInventory.ps1'
    if (Test-Path -LiteralPath $inventoryScriptPath -PathType Leaf) {
        $global:LASTEXITCODE = $null
        $inventoryOutput = @(& $inventoryScriptPath -InputPath $InputPath -KbWorkspaceRoot $repoRoot -FailOnUnknownTypes 2>&1)
        $inventorySucceeded = $?
        $inventoryExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $inventoryExitCode = if ($null -ne $inventoryExitCodeVariable -and $inventoryExitCodeVariable.Value -is [int]) {
            $inventoryExitCodeVariable.Value
        } elseif ($inventorySucceeded) {
            0
        } else {
            1
        }
        if ($inventoryExitCode -eq 3) {
            # The pre-scan JSON (stdout lines) carries unknownTypesMessage: each unknown type
            # GUID with its type name and package from the XPZ Dependencies block, the count,
            # and sample object names. Surface it instead of a generic message.
            $unknownTypesDetail = $null
            try {
                $inventoryJson = (@($inventoryOutput | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json
                $messageProperty = $inventoryJson.PSObject.Properties['unknownTypesMessage']
                if ($null -ne $messageProperty -and -not [string]::IsNullOrWhiteSpace([string]$messageProperty.Value)) {
                    $unknownTypesDetail = [string]$messageProperty.Value
                }
            } catch {
                $unknownTypesDetail = $null
            }
            if ([string]::IsNullOrWhiteSpace($unknownTypesDetail)) {
                $unknownTypesDetail = 'Run Get-GeneXusXpzObjectInventory.ps1 with -FailOnUnknownTypes for the list.'
            }
            $preScanBlockedMessage = "Pre-scan blocked: types not mapped in the effective catalog (base + override). $unknownTypesDetail Resolve before materializing; see the sync workflow and 08-agent-guide.md."
            # One unwrapped stderr line (the thrown error is wrapped to the console width).
            Write-HumanLine $preScanBlockedMessage
            throw $preScanBlockedMessage
        }
    }
}

function Invoke-IndexRefresh {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$SharedSkillsRoot,

        [string]$ValidationCasesPath
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "Index refresh wrapper not found: $ScriptPath"
    }

    $rebuildParams = @{
        SharedSkillsRoot = $SharedSkillsRoot
    }

    if ($ValidationCasesPath) {
        $rebuildParams.ValidationCasesPath = $ValidationCasesPath
        $rebuildParams.FailOnValidationFailure = $true
    }

    Write-HumanLine ""
    Write-HumanLine "Refreshing KbIntelligence index after XPZ/XML materialization..."

    $prefix = 'Index refresh failed after XPZ/XML materialization. The XPZ/XML materialization completed; only the KbIntelligence index was not generated.'

    $rebuildErrorLines = [System.Collections.Generic.List[string]]::new()
    $rebuildExitCode = 0
    try {
        $global:LASTEXITCODE = $null
        # Captured, then sent to stderr: the rebuild prints its own report on stdout, and
        # this wrapper's stdout must carry only the sync result JSON line. Its stderr is kept
        # too, to explain a refusal (exit 12 or 13) with the builder's own recovery.
        $rebuildOutput = @(& $ScriptPath @rebuildParams 2>&1)
        $rebuildSucceeded = $?
        foreach ($rebuildLine in $rebuildOutput) {
            if ($rebuildLine -is [System.Management.Automation.ErrorRecord]) {
                $rebuildErrorLines.Add($rebuildLine.ToString().Trim())
            }
            Write-HumanLine ([string]$rebuildLine)
        }
        $rebuildExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $rebuildExitCode = if ($null -ne $rebuildExitCodeVariable -and $rebuildExitCodeVariable.Value -is [int]) {
            $rebuildExitCodeVariable.Value
        } elseif ($rebuildSucceeded) {
            0
        } else {
            1
        }
        if ($rebuildExitCode -ne 0 -and $rebuildExitCode -ne 12 -and $rebuildExitCode -ne 13) {
            if ($rebuildExitCode -eq 8) {
                throw "$(Get-GeneXusPythonPrerequisiteErrorMessage)"
            }

            throw "Index rebuild failed (exit $rebuildExitCode)."
        }
    } catch {
        throw "$prefix $($_.Exception.Message)"
    }

    # Refusals from the corpus check: the materialization did not leave a complete corpus (12),
    # or another process held the corpus lock (13). Neither means the index is up to date.
    $builderDetail = @($rebuildErrorLines | Where-Object { $_ -match '^BLOCK:' })
    if ($builderDetail.Count -eq 0) { $builderDetail = @($rebuildErrorLines | Where-Object { $_ }) }
    $detail = if ($builderDetail.Count -gt 0) { $builderDetail -join ' ' } else { 'The builder printed no detail.' }
    if ($rebuildExitCode -eq 12) {
        throw "Index rebuild refused (exit 12): the corpus is not complete, so the KbIntelligence index was not rebuilt and queries stay blocked. XML files may have been written, but the corpus is not certified. Builder: $detail"
    }
    if ($rebuildExitCode -eq 13) {
        throw "Index rebuild refused (exit 13): the corpus lock stayed busy (another sync, index build, or query is running), so the KbIntelligence index was not rebuilt. Wait for it to finish, then run Rebuild-KbIntelligenceIndex.ps1. Builder: $detail"
    }
}

function Show-LocalGitSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$PathFilter
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-HumanLine "WARNING: git not found; local change summary skipped."
        return
    }

    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot ".git"))) {
        Write-HumanLine "WARNING: Git repository not found at $RepositoryRoot; local summary skipped."
        return
    }

    $statusLines = @(git -C $RepositoryRoot status --short -- $PathFilter 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-HumanLine "WARNING: could not get git status for $PathFilter."
        return
    }

    if ($statusLines.Count -eq 0) {
        Write-HumanLine ""
        Write-HumanLine "Git summary (`"$PathFilter`"): no pending local changes."
        return
    }

    $modifiedCount  = @($statusLines | Where-Object { $_ -match '^( M|M |MM|AM|RM| T|MT|TM)' }).Count
    $addedCount     = @($statusLines | Where-Object { $_ -match '^(A | A|AA)' }).Count
    $deletedCount   = @($statusLines | Where-Object { $_ -match '^( D|D |DD|AD|DA)' }).Count
    $renamedCount   = @($statusLines | Where-Object { $_ -match '^(R | R|RR)' }).Count
    $untrackedCount = @($statusLines | Where-Object { $_ -match '^\?\?' }).Count

    Write-HumanLine ""
    Write-HumanLine ("Git summary (`"{0}`"):" -f $PathFilter)
    Write-HumanLine ("  Modified : {0}" -f $modifiedCount)
    Write-HumanLine ("  Added    : {0}" -f $addedCount)
    Write-HumanLine ("  Deleted  : {0}" -f $deletedCount)
    Write-HumanLine ("  Renamed  : {0}" -f $renamedCount)
    Write-HumanLine ("  Untracked: {0}" -f $untrackedCount)
    Write-HumanLine ""
    Write-HumanLine "Changed paths:"
    $statusLines | ForEach-Object { Write-HumanLine ("  {0}" -f $_) }
}

function Get-ResultValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [object]$DefaultValue
    )

    if ($null -eq $Result) {
        return $DefaultValue
    }

    $prop = $Result.PSObject.Properties[$PropertyName]
    if ($null -eq $prop) {
        return $DefaultValue
    }

    return $prop.Value
}

if (-not $KbMetadataPath) {
    $KbMetadataPath = Join-Path $repoRoot "kb-source-metadata.md"
}

if (-not $IndexUpdateScriptPath) {
    $IndexUpdateScriptPath = Join-Path $PSScriptRoot "Rebuild-KbIntelligenceIndex.ps1"
    if (-not (Test-Path -LiteralPath $IndexUpdateScriptPath)) {
        throw "Local index refresh wrapper not found: $IndexUpdateScriptPath. Generate or update the local final wrapper before normal XPZ/XML sync."
    }
}

$params = @{
    InputPath        = $InputPath
    DestinationRoot  = $destinationRoot
    KbMetadataPath   = $KbMetadataPath
    KbWorkspaceRoot  = $repoRoot
    GuidCleanupContractVersion = 1
}

if ($VerifyOnly) {
    $params.VerifyOnly = $true
}

if ($FullSnapshot) {
    $params.FullSnapshot = $true
}

if ($ReportPath) {
    $params.ReportPath = $ReportPath
}

if ($KeepReport) {
    $params.KeepReport = $true
}

if ($ExpectedItems.Count -gt 0) {
    $params.ExpectedItems = @($ExpectedItems)
}

# The engine emits a single JSON line on stdout (-Compress). Invoked in-process via &,
# $rawResult is that string; we parse it into an object for the logic below. If the engine fails
# before emitting the JSON, it throws (ErrorActionPreference=Stop aborts here) and the JSON-on-failure
# is only recoverable by an agent that captures stdout+exit code, not by this wrapper.
$rawResult = & $enginePath @params
$result = $null
if ($null -ne $rawResult) {
    try {
        $result = $rawResult | ConvertFrom-Json
    } catch {
        throw "Failed to parse the JSON output of the Sync-GeneXusXpzToXml.ps1 engine: $($_.Exception.Message). Raw output: $rawResult"
    }
}

if (-not $VerifyOnly) {
    Invoke-IndexRefresh `
        -ScriptPath $IndexUpdateScriptPath `
        -SharedSkillsRoot $SharedSkillsRoot `
        -ValidationCasesPath $IndexValidationCasesPath
}

$shouldShowGitSummary = -not $NoGitSummary
if ($shouldShowGitSummary -and $null -ne $result) {
    $created = [int](Get-ResultValue -Result $result -PropertyName "Created" -DefaultValue 0)
    $updated = [int](Get-ResultValue -Result $result -PropertyName "Updated" -DefaultValue 0)
    $normalizedFileNames = [int](Get-ResultValue -Result $result -PropertyName "NormalizedFileNames" -DefaultValue 0)
    # FullSnapshotMissing/Extra are COUNTERS (int) or null in the summary, not arrays: read as
    # [int] and compare > 0. Wrapping in @(...).Count would give @(0).Count == 1 -> always true.
    $fullSnapshotMissing = [int](Get-ResultValue -Result $result -PropertyName "FullSnapshotMissing" -DefaultValue 0)
    $fullSnapshotExtra = [int](Get-ResultValue -Result $result -PropertyName "FullSnapshotExtra" -DefaultValue 0)
    # A run with only renames is also a material change (RenamedByGuid applies; in VerifyOnly
    # RenameResidualsDetected signals a stale corpus).
    $renamedByGuid = [int](Get-ResultValue -Result $result -PropertyName "RenamedByGuid" -DefaultValue 0)
    $renameResidualsDetected = [int](Get-ResultValue -Result $result -PropertyName "RenameResidualsDetected" -DefaultValue 0)

    $hasMaterialChange = ($created -gt 0) -or ($updated -gt 0) -or
        ($normalizedFileNames -gt 0) -or ($fullSnapshotMissing -gt 0) -or
        ($fullSnapshotExtra -gt 0) -or ($renamedByGuid -gt 0) -or
        ($renameResidualsDetected -gt 0)
    if (-not $hasMaterialChange) {
        $shouldShowGitSummary = $false
    }
}

# stdout: exclusively the engine's JSON line, re-emitted byte-for-byte (without re-serializing,
# to avoid introducing formatting/ordering drift). All human diagnostics go to stderr.
$rawResult

if ($shouldShowGitSummary) {
    Show-LocalGitSummary -RepositoryRoot $repoRoot -PathFilter "KbObjectsXml"
}
