#requires -Version 7.4
<#
.SYNOPSIS
    Runs minimal validation cases for the XPZ wrapper inventory.

.DESCRIPTION
    Creates a temporary KB workspace and a temporary examples folder to validate
    that a #requires -Version mismatch classifies a wrapper as CUSTOMIZED, without
    treating Test-*KbPowerShellRuntime.ps1 as a false positive. Also validates the
    advisory signals for missing recommended wrappers, that old or unprefixed wrapper
    names are not mapped (no legacy-orphan or short-naming status), and the INVENTORY_CUSTOMIZED reasons: missing_AsJson_passthrough
    (setup-audit and index-gate wrappers), consumes_legacy_text_stdout (Update-*KbFromXpz),
    unsafe_last_exitcode_after_ps1_engine (audited wrappers that call a PowerShell engine via a variable), and forwards_unknown_engine_param
    (forwarding an undeclared parameter to an advanced shared engine; end-to-end case).
    It also validates the wrapper-vs-template surface diff (surface_mismatch -> INVENTORY_CUSTOMIZED;
    optional/ValidateSet reductions -> INVENTORY_SURFACE_ADVISORY) in unit + end-to-end cases,
    plus the anti-regression guard that locates by content the aggregator's pendency regex
    (Test-MimirSetupAudit.ps1) and fails if it matches the advisory labels.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')
$inventoryScriptPath = Join-Path $scriptDir 'Test-MimirWrapperInventory.ps1'
# Dot-source the helper for the surface diff's UNIT cases (Get-MimirWrapperSurfaceFinding).
. (Join-Path $scriptDir 'MimirWrapperEngineParamSupport.ps1')
# Single source for UTF-8-without-BOM encoding (reuse convention; see 09-script-inventory, Utf8NoBomEncodingSupport.ps1).
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw "ASSERT_FAILED: $Message | output=$Text"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Text -match $Pattern) {
        throw "ASSERT_FAILED: $Message | output=$Text"
    }
}

# --- Helpers for the surface diff's UNIT cases ---
$script:surfaceFixtureCounter = 0
$script:surfaceUtf8 = Get-Utf8NoBomEncoding

function New-SurfaceFixture {
    param([string]$Dir, [string]$Content)
    $script:surfaceFixtureCounter++
    $p = Join-Path $Dir ('sfx-{0}.ps1' -f $script:surfaceFixtureCounter)
    [System.IO.File]::WriteAllText($p, $Content, $script:surfaceUtf8)
    return $p
}

function Get-SurfaceReasonList {
    param([object[]]$Items)
    if (-not $Items) { return '' }
    return ((@($Items | ForEach-Object { [string]$_.Reason }) | Sort-Object) -join '|')
}

function Assert-Surface {
    # Compares Get-MimirWrapperSurfaceFinding's (sorted) Blocking/Advisory reasons against the expected ones.
    param(
        [string]$Template,
        [string]$Local,
        [string]$Dir,
        [string[]]$Block = @(),
        [string[]]$Adv = @(),
        [string]$Message
    )
    $templatePath = New-SurfaceFixture -Dir $Dir -Content $Template
    $localPath = New-SurfaceFixture -Dir $Dir -Content $Local
    $finding = Get-MimirWrapperSurfaceFinding -TemplatePath $templatePath -LocalPath $localPath
    $gotB = Get-SurfaceReasonList $finding.Blocking
    $gotA = Get-SurfaceReasonList $finding.Advisory
    $wantB = ((@($Block) | Sort-Object) -join '|')
    $wantA = ((@($Adv) | Sort-Object) -join '|')
    if ($gotB -ne $wantB) { throw "ASSERT_FAILED: $Message (blocking) expected=[$wantB] got=[$gotB]" }
    if ($gotA -ne $wantA) { throw "ASSERT_FAILED: $Message (advisory) expected=[$wantA] got=[$gotA]" }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-wrapper-inventory-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$kbRoot = Join-Path $tempRoot 'Kb'
$scriptsPath = Join-Path $kbRoot 'scripts'
$examplesPath = Join-Path $tempRoot 'examples'

try {
    [void](New-Item -ItemType Directory -Path $scriptsPath -Force)
    [void](New-Item -ItemType Directory -Path $examplesPath -Force)

    @'
## Source/Version

| field | value |
|---|---|
| name | Demo |
'@ | Set-Content -LiteralPath (Join-Path $kbRoot 'kb-source-metadata.md') -Encoding utf8NoBOM

    @'
#requires -Version 7.4
Write-Output "metadata"
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Get-KbMetadata.example.ps1') -Encoding utf8NoBOM

    @'
#requires -version 5.1
Write-Output "metadata"
'@ | Set-Content -LiteralPath (Join-Path $scriptsPath 'Get-DemoKbMetadata.ps1') -Encoding utf8NoBOM

    @'
Write-Output "runtime"
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Test-KbPowerShellRuntime.example.ps1') -Encoding utf8NoBOM

    @'
Write-Output "runtime"
'@ | Set-Content -LiteralPath (Join-Path $scriptsPath 'Test-DemoKbPowerShellRuntime.ps1') -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern '\bINVENTORY_CUSTOMIZED\b' -Message 'a requires mismatch should classify as CUSTOMIZED'
    Assert-Contains -Text $output -Pattern 'Get-DemoKbMetadata\.ps1\(reason=requires_version_mismatch: local=5\.1 canonical=7\.4\)' -Message 'diagnostic should identify the wrapper and versions'
    Assert-NotContains -Text $output -Pattern '\bINVENTORY_OK\b' -Message 'an inventory with CUSTOMIZED cannot return OK'
    Assert-NotContains -Text $output -Pattern 'Test-DemoKbPowerShellRuntime\.ps1\(reason=requires_version_mismatch' -Message 'the runtime wrapper is an intentional exception'

    foreach ($optionalExample in @('New-KbFront', 'New-KbImportPackage', 'Resolve-KbIdentity')) {
        @'
#requires -Version 7.4
Write-Output "optional"
'@ | Set-Content -LiteralPath (Join-Path $examplesPath "$optionalExample.example.ps1") -Encoding utf8NoBOM
    }

    # The two folder names below are generated-objects and import-package folders that
    # write-side GeneXus tooling may leave in a KB workspace; they stay verbatim so the guard
    # keeps meaning "an existing generated-objects or import-package folder recommends nothing".
    $frontPath = Join-Path $kbRoot 'ObjetosGeradosParaImportacaoNaKbNoGenexus\MyWorkstream_11111111-1111-1111-1111-111111111111_20260524'
    $packagesPath = Join-Path $kbRoot 'PacotesGeradosParaImportacaoNaKbNoGenexus'
    [void](New-Item -ItemType Directory -Path $frontPath -Force)
    [void](New-Item -ItemType Directory -Path $packagesPath -Force)
    '<Object lastUpdate="2026-05-24T00:00:00.0000000Z" />' |
        Set-Content -LiteralPath (Join-Path $frontPath 'Object.xml') -Encoding utf8NoBOM
    '<ExportFile />' |
        Set-Content -LiteralPath (Join-Path $packagesPath 'MyWorkstream_11111111-1111-1111-1111-111111111111_20260524_01.import_file.xml') -Encoding utf8NoBOM
    '| kb (GUID) | 11111111-1111-1111-1111-111111111111 |' |
        Add-Content -LiteralPath (Join-Path $kbRoot 'kb-source-metadata.md') -Encoding utf8NoBOM

    foreach ($scriptName in @(
        'Test-DemoKbFullSnapshot.ps1',
        'Test-DemoFullSnapshot.ps1',
        'Update-DemoKbFromXpz.ps1',
        'Update-DemoFromXpz.ps1',
        'Test-DemoKbIndexGate.ps1',
        'Test-DemoKbGate.ps1'
    )) {
        '#requires -Version 7.4' |
            Set-Content -LiteralPath (Join-Path $scriptsPath $scriptName) -Encoding utf8NoBOM
    }

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    # Non-canonical wrapper names (Test-DemoFullSnapshot, Test-DemoKbGate, ...) are not mapped: extra scripts
    # with those names are neither orphans nor renames, just local scripts the inventory ignores.
    Assert-NotContains -Text $output -Pattern 'INVENTORY_LEGACY_ORPHANS' -Message 'non-canonical wrapper names must not produce a legacy-orphan status'
    Assert-NotContains -Text $output -Pattern '\(legacy=' -Message 'non-canonical wrapper names must not be paired with a canonical wrapper'

    # A wrapper named without the KB prefix is not a canonical wrapper: it is a gap, not a rename.
    '#requires -Version 7.4' |
        Set-Content -LiteralPath (Join-Path $examplesPath 'Test-KbStructure.example.ps1') -Encoding utf8NoBOM
    '#requires -Version 7.4' |
        Set-Content -LiteralPath (Join-Path $scriptsPath 'Test-KbStructure.ps1') -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-NotContains -Text $output -Pattern 'INVENTORY_SHORT_NAMING' -Message 'an unprefixed wrapper must not produce a short-naming status'
    Assert-Contains -Text $output -Pattern 'INVENTORY_GAPS:[^|]*Test-DemoKbStructure\.ps1' -Message 'an unprefixed wrapper leaves the canonical wrapper missing'
    Assert-Contains -Text $output -Pattern '\bINVENTORY_RECOMMENDED_MISSING\b' -Message 'missing recommended wrappers should be reported'
    $recommendedSegment = (@($output -split '\|' | Where-Object { $_ -match 'INVENTORY_RECOMMENDED_MISSING' }) -join ' ')
    Assert-Contains -Text $recommendedSegment -Pattern 'Resolve-DemoKbIdentity\.ps1' -Message 'identity metadata should recommend the identity wrapper'
    # Generated-object and import-package folders are write-side history outside Mimir Lite:
    # they are not evidence for any recommendation, and those wrappers are not optional names.
    Assert-NotContains -Text $recommendedSegment -Pattern 'New-DemoKbFront\.ps1' -Message 'a generated-objects folder must not recommend a write-side wrapper'
    Assert-NotContains -Text $recommendedSegment -Pattern 'New-DemoKbImportPackage\.ps1' -Message 'an import-package folder must not recommend a write-side wrapper'

    # Setup-audit and index-gate wrappers: the template forwards -AsJson; a local wrapper without -AsJson should become CUSTOMIZED
    @'
#requires -Version 7.4
param([switch]$AsJson)
& $enginePath -AsJson:$AsJson
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Test-KbSetupAudit.example.ps1') -Encoding utf8NoBOM
    @'
#requires -Version 7.4
param([switch]$AsJson)
$forward = @{}
if ($AsJson) { $forward['AsJson'] = $true }
& $engine @forward
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Test-KbIndexGate.example.ps1') -Encoding utf8NoBOM

    $setupAuditStandardPath = Join-Path $scriptsPath 'Test-DemoKbSetupAudit.ps1'
    $indexGateStandardPath = Join-Path $scriptsPath 'Test-DemoKbIndexGate.ps1'

    @'
#requires -Version 7.4
param()
& $enginePath
'@ | Set-Content -LiteralPath $setupAuditStandardPath -Encoding utf8NoBOM

    @'
#requires -Version 7.4
param()
& $engine
'@ | Set-Content -LiteralPath $indexGateStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'Test-DemoKbSetupAudit\.ps1\(reason=missing_AsJson_passthrough\)' -Message 'setup-audit wrapper without -AsJson forwarding should be flagged'
    Assert-Contains -Text $output -Pattern 'Test-DemoKbIndexGate\.ps1\(reason=missing_AsJson_passthrough\)' -Message 'index-gate wrapper without -AsJson forwarding should be flagged'

    # Same wrappers, now forwarding -AsJson, must not be flagged for this reason
    @'
#requires -Version 7.4
param([switch]$AsJson)
& $enginePath -AsJson:$AsJson
'@ | Set-Content -LiteralPath $setupAuditStandardPath -Encoding utf8NoBOM

    @'
#requires -Version 7.4
param([switch]$AsJson)
$forward = @{}
if ($AsJson) { $forward['AsJson'] = $true }
& $engine @forward
'@ | Set-Content -LiteralPath $indexGateStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-NotContains -Text $output -Pattern 'Test-DemoKbSetupAudit\.ps1\(reason=missing_AsJson_passthrough\)' -Message 'setup-audit wrapper with -AsJson forwarding must not be flagged for this reason'
    Assert-NotContains -Text $output -Pattern 'Test-DemoKbIndexGate\.ps1\(reason=missing_AsJson_passthrough\)' -Message 'index-gate wrapper with -AsJson forwarding must not be flagged for this reason'

    # Partial migration: declares [switch]$AsJson but does NOT forward it to the engine -> should
    # be flagged (the check detects the forwarding, not merely the term being mentioned).
    @'
#requires -Version 7.4
param([switch]$AsJson)
& $enginePath
'@ | Set-Content -LiteralPath $setupAuditStandardPath -Encoding utf8NoBOM

    @'
#requires -Version 7.4
param([switch]$AsJson)
$forward = @{}
& $engine @forward
'@ | Set-Content -LiteralPath $indexGateStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'Test-DemoKbSetupAudit\.ps1\(reason=missing_AsJson_passthrough\)' -Message 'setup-audit wrapper that declares AsJson but does not forward it should be flagged'
    Assert-Contains -Text $output -Pattern 'Test-DemoKbIndexGate\.ps1\(reason=missing_AsJson_passthrough\)' -Message 'index-gate wrapper that declares AsJson but does not forward it should be flagged'

    # Update-KbFromXpz x Sync-GeneXusXpzToXml: CONSUMPTION contract drift. The template consumes the
    # engine's stdout as JSON v1 (ConvertFrom-Json); a local wrapper that still treats it as TEXT
    # (no ConvertFrom-Json) should be flagged consumes_legacy_text_stdout.
    @'
#requires -Version 7.4
param([string]$InputPath)
$raw = & $enginePath -InputPath $InputPath
$result = $raw | ConvertFrom-Json
[Console]::Error.WriteLine("Created: $($result.Created)")
$raw
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Update-KbFromXpz.example.ps1') -Encoding utf8NoBOM

    $updateStandardPath = Join-Path $scriptsPath 'Update-DemoKbFromXpz.ps1'

    # FAILS: old textual wrapper (Format-List, no ConvertFrom-Json)
    @'
#requires -Version 7.4
param([string]$InputPath)
$result = & $enginePath -InputPath $InputPath
$result | Format-List
'@ | Set-Content -LiteralPath $updateStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'Update-DemoKbFromXpz\.ps1\(reason=consumes_legacy_text_stdout\)' -Message 'a textual Update-*KbFromXpz wrapper (no ConvertFrom-Json) should be flagged'

    # PASSES: a wrapper migrated to the JSON v1 contract (consumes via ConvertFrom-Json) must not be
    # flagged for this reason
    @'
#requires -Version 7.4
param([string]$InputPath)
$raw = & $enginePath -InputPath $InputPath
$result = $raw | ConvertFrom-Json
[Console]::Error.WriteLine("Created: $($result.Created)")
$raw
'@ | Set-Content -LiteralPath $updateStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-NotContains -Text $output -Pattern 'Update-DemoKbFromXpz\.ps1\(reason=consumes_legacy_text_stdout\)' -Message 'an Update-*KbFromXpz wrapper migrated to JSON v1 must not be flagged for this reason'

    # A successful shared .ps1 engine does not necessarily set $LASTEXITCODE.
    # The legacy `exit $LASTEXITCODE` pattern breaks under StrictMode or reuses a
    # stale value. The rule is generic for wrappers that call PowerShell engines.
    @'
#requires -Version 7.4
param([string]$BuildResultJsonPath)
$global:LASTEXITCODE = $null
& $engineScript -BuildResultJsonPath $BuildResultJsonPath
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Register-KbPostBuildEvents.example.ps1') -Encoding utf8NoBOM

    $registerStandardPath = Join-Path $scriptsPath 'Register-DemoKbPostBuildEvents.ps1'
    @'
#requires -Version 7.4
param([string]$BuildResultJsonPath)
& $engineScript -BuildResultJsonPath $BuildResultJsonPath
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $registerStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'Register-DemoKbPostBuildEvents\.ps1\(reason=unsafe_last_exitcode_after_ps1_engine\)' -Message 'a wrapper calling a PowerShell engine with exit LASTEXITCODE should be flagged'

    @'
#requires -Version 7.4
param([string]$BuildResultJsonPath)
& $ScriptPath -BuildResultJsonPath $BuildResultJsonPath
exit $LASTEXITCODE
'@ | Set-Content -LiteralPath $registerStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'Register-DemoKbPostBuildEvents\.ps1\(reason=unsafe_last_exitcode_after_ps1_engine\)' -Message 'a wrapper calling a PowerShell engine via a generic variable with exit LASTEXITCODE should be flagged'

    @'
#requires -Version 7.4
param([string]$BuildResultJsonPath)
$global:LASTEXITCODE = $null
& $engineScript -BuildResultJsonPath $BuildResultJsonPath
$lastCommandSucceeded = $?
$lastExitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
if ($null -ne $lastExitCodeVariable -and $lastExitCodeVariable.Value -is [int]) {
    exit $lastExitCodeVariable.Value
}
if (-not $lastCommandSucceeded) {
    exit 1
}
exit 0
'@ | Set-Content -LiteralPath $registerStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-NotContains -Text $output -Pattern 'Register-DemoKbPostBuildEvents\.ps1\(reason=unsafe_last_exitcode_after_ps1_engine\)' -Message 'a wrapper calling a PowerShell engine with a safe exit must not be flagged for this reason'

    # forwards_unknown_engine_param end-to-end: a local wrapper that forwards a nonexistent parameter
    # to a REAL advanced shared engine (Search-GeneXusXmlSourceBlock.ps1) should show up in the
    # INVENTORY_CUSTOMIZED line (captured by the aggregator).
    @'
#requires -Version 7.4
Write-Output "search"
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Search-KbXmlSourceBlock.example.ps1') -Encoding utf8NoBOM

    @'
#requires -Version 7.4
param([string]$Path)
$enginePath = Join-Path $SharedSkillsRoot 'scripts\Search-GeneXusXmlSourceBlock.ps1'
& $enginePath -Path $Path -BogusXyz $z
'@ | Set-Content -LiteralPath (Join-Path $scriptsPath 'Search-DemoKbXmlSourceBlock.ps1') -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'Search-DemoKbXmlSourceBlock\.ps1\(reason=forwards_unknown_engine_param: -BogusXyz -> Search-GeneXusXmlSourceBlock\.ps1\)' -Message 'a nonexistent parameter forwarded to an advanced engine should be flagged by the inventory inside INVENTORY_CUSTOMIZED'

    # ============================================================================
    # Wrapper surface diff (surface_mismatch / INVENTORY_SURFACE_ADVISORY)
    # UNIT: Get-MimirWrapperSurfaceFinding with surface-faithful fixtures (only the surface matters).
    # ============================================================================
    $surfaceDir = Join-Path $tempRoot 'surface'
    [void](New-Item -ItemType Directory -Path $surfaceDir -Force)
    $D = $surfaceDir

    # BLOCKS: loss of a mandatory contract
    Assert-Surface -Dir $D -Template 'param([Parameter(Mandatory)][string]$Query, [string]$Opt)' -Local 'param([string]$Opt)' -Block @('mandatory_param_missing') -Message 'U01 missing mandatory -> surface_mismatch'
    Assert-Surface -Dir $D -Template 'param([Parameter(Mandatory)][string]$Q)' -Local 'param([string]$Q)' -Block @('mandatory_downgraded') -Message 'U10 mandatory downgraded -> surface_mismatch'
    Assert-Surface -Dir $D -Template 'param([Parameter(Mandatory)][string]$Q)' -Local 'param([string]$Other)' -Block @('mandatory_param_missing') -Message 'U14 [Parameter(Mandatory)] without =$true is still mandatory'
    Assert-Surface -Dir $D -Template 'param([System.Management.Automation.ParameterAttribute(Mandatory=$true)][string]$Q)' -Local 'param([string]$Other)' -Block @('mandatory_param_missing') -Message 'U16 [Parameter] by FQN is read'
    Assert-Surface -Dir $D -Template 'param([Parameter(ParameterSetName="A")][Parameter(ParameterSetName="B",Mandatory=$true)][string]$Q)' -Local 'param([string]$Q)' -Block @('mandatory_downgraded') -Message 'U12 multiple [Parameter] with Mandatory on one set -> mandatory'

    # BLOCKS / WARNS / QUIET depending on the TEMPLATE's surface when the LOCAL has no top-level param() (v14)
    $localFn = "function Foo { param([Parameter(Mandatory)][string]`$X) }`nWrite-Output 'x'"
    Assert-Surface -Dir $D -Template 'param([Parameter(Mandatory)][string]$Q)' -Local $localFn -Block @('no_param_block') -Message 'U13a no top-level param() + mandatory template -> surface_mismatch no_param_block (does not inherit from the inner function)'
    Assert-Surface -Dir $D -Template 'param([string]$Q)' -Local $localFn -Adv @('no_param_block') -Message 'U13b no top-level param() + optional-only template -> advisory no_param_block'
    Assert-Surface -Dir $D -Template "[CmdletBinding()]`nparam()" -Local $localFn -Message 'U13c no top-level param() + zero-surface template -> quiet'

    # WARNS: optional reduction / ValidateSet / promotion / extra mandatory
    Assert-Surface -Dir $D -Template 'param([string]$A, [string]$B)' -Local 'param([string]$A)' -Adv @('optional_param_missing') -Message 'U03 missing optional -> advisory'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a','b','c')][string]`$Q)" -Local "param([ValidateSet('a','b')][string]`$Q)" -Adv @('validateset_reduced') -Message 'U04a reduced ValidateSet (subset) -> advisory'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a','b')][string]`$Q)" -Local "param([ValidateSet('a','c')][string]`$Q)" -Adv @('validateset_reduced') -Message 'U04b ValidateSet value swapped (set difference) -> advisory'
    Assert-Surface -Dir $D -Template "param([System.Management.Automation.ValidateSetAttribute('a','b')][string]`$Q)" -Local "param([ValidateSet('a')][string]`$Q)" -Adv @('validateset_reduced') -Message 'U15 ValidateSet by FQN is read'
    Assert-Surface -Dir $D -Template 'param([string]$Q)' -Local 'param([Parameter(Mandatory)][string]$Q)' -Adv @('optional_promoted_to_mandatory') -Message 'U11 optional -> mandatory -> advisory'
    Assert-Surface -Dir $D -Template 'param([string]$A)' -Local 'param([string]$A, [Parameter(Mandatory)][string]$Extra)' -Adv @('extra_mandatory_added') -Message 'U08 extra mandatory param -> advisory'
    Assert-Surface -Dir $D -Template "[CmdletBinding()]`nparam()" -Local 'param([Parameter(Mandatory)][string]$Z)' -Adv @('extra_mandatory_added') -Message 'U09 zero-surface template + mandatory local -> advisory extra_mandatory_added'

    # QUIET: surplus / workstream-ahead / legitimate delegation / not comparable
    Assert-Surface -Dir $D -Template 'param([string]$Root = "X")' -Local 'param([string]$Root = "Y")' -Message 'U02 faithful (only default differs) -> quiet'
    Assert-Surface -Dir $D -Template 'param([string]$A)' -Local 'param([string]$A, [string]$Extra)' -Message 'U07 extra optional param -> quiet'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a','b')][string]`$Q)" -Local 'param([string]$Q)' -Message 'U05a ValidateSet removed locally -> quiet (delegation)'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a','b')][string]`$Q)" -Local "param([ValidateSet('a','b','c')][string]`$Q)" -Message 'U05b local ValidateSet superset -> quiet'
    Assert-Surface -Dir $D -Template "param([ValidateSet()][string]`$Q)" -Local "param([ValidateSet('a')][string]`$Q)" -Message 'U05c empty ValidateSet in the template -> not comparable -> quiet'
    Assert-Surface -Dir $D -Template 'param([ValidateSet(1,2,3)][int]$Q)' -Local 'param([ValidateSet(1,2)][int]$Q)' -Message 'U05d non-string ValidateSet -> not comparable -> quiet'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a',`$z)][string]`$Q)" -Local "param([ValidateSet('a')][string]`$Q)" -Message 'U05e mixed ValidateSet (literal+var) -> not comparable -> quiet'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a','b')][ValidateSet('b','c')][string]`$Q)" -Local "param([ValidateSet('a')][string]`$Q)" -Message 'U06 param with 2 [ValidateSet] (AND/intersection) -> not comparable -> quiet'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a','b',IgnoreCase=`$true)][string]`$Q)" -Local "param([ValidateSet('a','b')][string]`$Q)" -Message 'U17 named ValidateSet arg ignored -> compares positional only -> quiet'

    # Coexistence: BLOCKING + WARNING in the same wrapper (per-wrapper finding, not global)
    Assert-Surface -Dir $D -Template "param([Parameter(Mandatory)][string]`$Query, [string]`$Opt, [ValidateSet('a','b','c')][string]`$Kind)" -Local "param([ValidateSet('a')][string]`$Kind)" -Block @('mandatory_param_missing') -Adv @('optional_param_missing', 'validateset_reduced') -Message 'U18 blocking + advisory coexistence in the same wrapper'

    # OUT-OF-SCOPE corners (kimi): lock the KNOWN behavior to catch regressions
    Assert-Surface -Dir $D -Template "param([Parameter(Mandatory)][string]`$Path)" -Local "param([Parameter(Mandatory)][Alias('Path')][string]`$Local)" -Block @('mandatory_param_missing') -Adv @('extra_mandatory_added') -Message 'OOS-a renamed [Alias] -> spurious block+advisory (known limitation, no alias support)'
    Assert-Surface -Dir $D -Template "param([ValidateSet('a','b')][string]`$Q)" -Local "param([ValidateSet('A','B',IgnoreCase=`$false)][string]`$Q)" -Message 'OOS-b differing IgnoreCase=$false compared as OrdinalIgnoreCase (known limitation) -> quiet'
    Assert-Surface -Dir $D -Template 'param([string]$Q)' -Local "filter Bar { `$_ }" -Adv @('no_param_block') -Message 'OOS-c wrapper in filter form -> no_param_block (advisory since the template is optional-only)'

    # ============================================================================
    # END-TO-END via the inventory: emitted labels, coexistence, and advisory-only does not become INVENTORY_OK
    # ============================================================================
    # E2E-1: block (downgraded) + advisory (missing optional) in the same Query wrapper
    @'
#requires -Version 7.4
param(
    [Parameter(Mandatory = $true)]
    [string]$Query,
    [string]$Opt
)
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Query-KbIntelligence.example.ps1') -Encoding utf8NoBOM
    $queryStandardPath = Join-Path $scriptsPath 'Query-DemoKbIntelligence.ps1'
    @'
#requires -Version 7.4
param(
    [string]$Query
)
'@ | Set-Content -LiteralPath $queryStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'INVENTORY_CUSTOMIZED\b' -Message 'E2E-1 loss of mandatory should land in INVENTORY_CUSTOMIZED'
    Assert-Contains -Text $output -Pattern 'Query-DemoKbIntelligence\.ps1\(reason=surface_mismatch: mandatory_downgraded -Query\)' -Message 'E2E-1 downgraded mandatory emitted as surface_mismatch'
    Assert-Contains -Text $output -Pattern 'INVENTORY_SURFACE_ADVISORY:.*Query-DemoKbIntelligence\.ps1\(reason=optional_param_missing: -Opt\)' -Message 'E2E-1 missing optional emitted as INVENTORY_SURFACE_ADVISORY'
    Assert-NotContains -Text $output -Pattern '\bINVENTORY_OK\b' -Message 'E2E-1 a wrapper with surface_mismatch cannot return OK'

    # E2E-2: advisory-only (reduced ValidateSet) -> INVENTORY_SURFACE_ADVISORY with no surface_mismatch, and no INVENTORY_OK
    @'
#requires -Version 7.4
param(
    [ValidateSet('a', 'b', 'c')]
    [string]$Query
)
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Query-KbIntelligence.example.ps1') -Encoding utf8NoBOM
    @'
#requires -Version 7.4
param(
    [ValidateSet('a')]
    [string]$Query
)
'@ | Set-Content -LiteralPath $queryStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'INVENTORY_SURFACE_ADVISORY:.*Query-DemoKbIntelligence\.ps1\(reason=validateset_reduced: -Query \[b, c\]\)' -Message 'E2E-2 reduced ValidateSet emitted as advisory with the missing values'
    Assert-NotContains -Text $output -Pattern 'Query-DemoKbIntelligence\.ps1\(reason=surface_mismatch' -Message 'E2E-2 a ValidateSet reduction must not block (it is not surface_mismatch)'
    Assert-NotContains -Text $output -Pattern '\bINVENTORY_OK\b' -Message 'E2E-2 advisory-only is still not INVENTORY_OK (emits a status part)'

    # E2E-3: overlap of a per-token check (requires_version_mismatch) + surface_mismatch in the same wrapper
    @'
#requires -Version 7.4
param(
    [Parameter(Mandatory = $true)]
    [string]$Query
)
'@ | Set-Content -LiteralPath (Join-Path $examplesPath 'Query-KbIntelligence.example.ps1') -Encoding utf8NoBOM
    @'
#requires -version 5.1
param(
    [string]$Other
)
'@ | Set-Content -LiteralPath $queryStandardPath -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $kbRoot -SkillsExamplesPath $examplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '

    Assert-Contains -Text $output -Pattern 'Query-DemoKbIntelligence\.ps1\(reason=requires_version_mismatch' -Message 'E2E-3 the per-token check (requires) is still reported'
    Assert-Contains -Text $output -Pattern 'Query-DemoKbIntelligence\.ps1\(reason=surface_mismatch: mandatory_param_missing -Query\)' -Message 'E2E-3 surface_mismatch coexists with the per-token check (redundancy accepted)'

    # ============================================================================
    # REQUIRED-WRAPPER SET: a workspace that carries local wrappers only for the read-side
    # examples must audit INVENTORY_OK against the REAL canonical examples: every example
    # that ships is a wrapper setup bootstraps, and none of the retired deployment,
    # package-collision, source-sanity, generated-.cs or lastUpdate wrappers is required.
    # Conversely, dropping a genuinely required wrapper must still report a gap.
    # ============================================================================
    $realExamplesPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptDir))) 'skills/mimir-lite/workflows/setup/examples'
    $readSideKbRoot = Join-Path $tempRoot 'read-side-kb'
    $readSideScripts = Join-Path $readSideKbRoot 'scripts'
    [void](New-Item -ItemType Directory -Path $readSideScripts -Force)
    foreach ($realExample in Get-ChildItem -LiteralPath $realExamplesPath -File -Filter '*.example.ps1' | Sort-Object Name) {
        $realBaseName = $realExample.Name -replace '\.example\.ps1$', ''
        $localRealName = if ($realBaseName -match '^([A-Za-z]+-)Kb(.+)$') { '{0}DemoKb{1}.ps1' -f $Matches[1], $Matches[2] } else { "$realBaseName.ps1" }
        Copy-Item -LiteralPath $realExample.FullName -Destination (Join-Path $readSideScripts $localRealName)
    }
    "kb_name: Demo" | Set-Content -LiteralPath (Join-Path $readSideKbRoot 'kb-source-metadata.md') -Encoding utf8NoBOM

    $output = (& $inventoryScriptPath -KbWorkspaceRoot $readSideKbRoot -SkillsExamplesPath $realExamplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '
    Assert-Contains -Text $output -Pattern '^\s*INVENTORY_OK\s*$' -Message 'a read-side-only workspace must audit INVENTORY_OK against the real examples (only the wrappers that ship as examples are required)'

    Remove-Item -LiteralPath (Join-Path $readSideScripts 'Test-DemoKbIndexGate.ps1') -Force
    $output = (& $inventoryScriptPath -KbWorkspaceRoot $readSideKbRoot -SkillsExamplesPath $realExamplesPath 2>&1 |
        ForEach-Object { $_.ToString() }) -join ' '
    Assert-Contains -Text $output -Pattern 'INVENTORY_GAPS:.*Test-DemoKbIndexGate\.ps1' -Message 'a genuinely required wrapper that is missing must still be reported as a gap'

    # ============================================================================
    # ANTI-REGRESSION GUARD: the aggregator's pendency regex (Test-MimirSetupAudit.ps1) matches
    # INVENTORY_CUSTOMIZED but NOT the advisory/diagnostic labels. Located BY CONTENT
    # (not by line number) to survive drift.
    # ============================================================================
    $auditPath = Join-Path $scriptDir 'Test-MimirSetupAudit.ps1'
    $auditLines = [System.IO.File]::ReadAllLines($auditPath)
    $regexLine = @($auditLines | Where-Object { $_ -match 'hasInventoryMethodologyPendencies\s*=' }) | Select-Object -First 1
    if (-not $regexLine) { throw 'ASSERT_FAILED: could not find the $hasInventoryMethodologyPendencies line in Test-MimirSetupAudit.ps1' }
    $regexMatch = [regex]::Match($regexLine, "-match\s+'(?<pat>[^']*)'")
    if (-not $regexMatch.Success) { throw "ASSERT_FAILED: could not extract the literal regex from the pendency line | line=$regexLine" }
    $blockRegex = $regexMatch.Groups['pat'].Value

    Assert-Contains -Text 'INVENTORY_CUSTOMIZED: X(reason=surface_mismatch: mandatory_param_missing -Query)' -Pattern $blockRegex -Message 'the pendency regex MUST match INVENTORY_CUSTOMIZED (surface_mismatch blocks via CUSTOMIZED)'
    Assert-NotContains -Text 'INVENTORY_SURFACE_ADVISORY: X(reason=validateset_reduced: -Query [a, b])' -Pattern $blockRegex -Message 'REGRESSION: the pendency regex must NOT match INVENTORY_SURFACE_ADVISORY'
    Assert-NotContains -Text 'INVENTORY_ENGINE_DIAGNOSTIC: X(reason=engine_unresolved_or_unparseable: Y)' -Pattern $blockRegex -Message 'REGRESSION: the pendency regex must NOT match INVENTORY_ENGINE_DIAGNOSTIC'

    Write-Output 'WRAPPER_INVENTORY_SELFTEST_OK'
} finally {
    if ($tempRoot.StartsWith([System.IO.Path]::GetTempPath(), [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $tempRoot -PathType Container)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
