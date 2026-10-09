#requires -Version 7.4
<#
.SYNOPSIS
  Self-test of the MimirWrapperEngineParamSupport.ps1 helper — check forwards_unknown_engine_param.
  (The helper's second hosted check, the wrapper->template surface diff
  `surface_mismatch`/`INVENTORY_SURFACE_ADVISORY`, is covered by Test-MimirWrapperInventorySelfTest.ps1.)

.DESCRIPTION
  Creates fixture wrappers (only PARSED, never executed) and confronts them with:
    - REAL engines from the repo (Sync-GeneXusXpzToXml.ps1) via EnginesRoot = the auditor's scripts/;
    - SYNTHETIC engines (simple/advanced/parse-broken/adversarial) in a temp folder.
  Final sentinel: MIMIR_WRAPPER_ENGINE_PARAM_SELFTEST_OK.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')
. (Join-Path $scriptDir 'MimirWrapperEngineParamSupport.ps1')
# Single source of UTF-8-no-BOM encoding (reuse convention; see 09-script-inventory, Utf8NoBomEncodingSupport.ps1).
. (Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1')

$utf8 = Get-Utf8NoBomEncoding
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-engineparam-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$wrapDir = Join-Path $tempRoot 'wrappers'
$synthEngines = Join-Path $tempRoot 'synthscripts'
[void](New-Item -ItemType Directory -Path $wrapDir -Force)
[void](New-Item -ItemType Directory -Path $synthEngines -Force)

function New-Fixture {
    param([string]$Dir, [string]$Name, [string]$Content)
    $p = Join-Path $Dir $Name
    [System.IO.File]::WriteAllText($p, $Content, $utf8)
    return $p
}

function Assert-Signal {
    param([object]$Finding, [string]$Reason, [string]$DetailLike, [string]$Message)
    $hit = @($Finding.Signals | Where-Object { $_.Reason -eq $Reason -and $_.Detail -like $DetailLike })
    if ($hit.Count -eq 0) {
        throw "ASSERT_FAILED: $Message | expected signal $Reason '$DetailLike'; got=$(($Finding.Signals | ForEach-Object { $_.Reason + ':' + $_.Detail }) -join ', ')"
    }
}

function Assert-NoSignalReason {
    param([object]$Finding, [string]$Reason, [string]$Message)
    $hit = @($Finding.Signals | Where-Object { $_.Reason -eq $Reason })
    if ($hit.Count -gt 0) {
        throw "ASSERT_FAILED: $Message | did not expect $Reason; got=$(($hit | ForEach-Object { $_.Reason + ':' + $_.Detail }) -join ', ')"
    }
}

function Assert-Eq {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ([string]$Actual -ne [string]$Expected) { throw "ASSERT_FAILED: $Message | expected=$Expected got=$Actual" }
}

try {
    # Real EnginesRoot = the auditor's scripts/ (where Sync-GeneXusXpzToXml.ps1 etc. live)
    $realEngines = $scriptDir

    # 1. FAIL: forwards a nonexistent parameter to a real advanced engine (Sync).
    $f = New-Fixture $wrapDir 'fail-unknown.ps1' @'
param([string]$InputPath)
$e = Join-Path $SharedSkillsRoot 'scripts\Sync-GeneXusXpzToXml.ps1'
& $e -InputPath $InputPath -BogusParam $x
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-Signal $r 'forwards_unknown_engine_param' '*-BogusParam -> Sync-GeneXusXpzToXml.ps1*' 'a nonexistent parameter on an advanced engine should signal'
    Assert-Eq $r.AuditedSiteCount 1 'an audited advanced site should count as 1'

    # 2. PASS: only declared parameters.
    $f = New-Fixture $wrapDir 'pass-valid.ps1' @'
param([string]$InputPath)
$e = Join-Path $SharedSkillsRoot 'scripts\Sync-GeneXusXpzToXml.ps1'
& $e -InputPath $InputPath -DestinationRoot $d
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-NoSignalReason $r 'forwards_unknown_engine_param' 'only valid parameters must not signal'
    Assert-Eq $r.AuditedSiteCount 1 'a valid site still counts as audited'

    # 3. Nested Join-Path.
    $f = New-Fixture $wrapDir 'nested.ps1' @'
$e = Join-Path $S (Join-Path 'scripts' 'Sync-GeneXusXpzToXml.ps1')
& $e -BogusNested $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-Signal $r 'forwards_unknown_engine_param' '*-BogusNested -> Sync-GeneXusXpzToXml.ps1*' 'the nested form should resolve and signal'

    # 4. Local sibling (no 'scripts' segment) -> out of scope.
    $f = New-Fixture $wrapDir 'local-sibling.ps1' @'
$e = Join-Path $PSScriptRoot 'Rebuild-KbIntelligenceIndex.ps1'
& $e -Anything $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-NoSignalReason $r 'forwards_unknown_engine_param' 'a local sibling must not signal'
    Assert-Eq $r.AuditedSiteCount 0 'a local sibling is not audited'

    # 5. Renamed root ($MyBase) with a valid leaf -> audited normally (GAP-2 fix).
    $f = New-Fixture $wrapDir 'renamed-root.ps1' @'
$MyBase = 'C:\any\mimir-lite'
$e = Join-Path $MyBase 'scripts\Sync-GeneXusXpzToXml.ps1'
& $e -BogusRenamed $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-Signal $r 'forwards_unknown_engine_param' '*-BogusRenamed -> Sync-GeneXusXpzToXml.ps1*' 'a renamed root with a valid leaf should be audited'

    # 6. shared_engine_unresolved: nonexistent leaf under an expression containing 'scripts'.
    $f = New-Fixture $wrapDir 'unresolved.ps1' @'
$e = Join-Path $S 'scripts\NonExistentEngine-xyz.ps1'
& $e -Foo $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-Signal $r 'shared_engine_unresolved' 'NonExistentEngine-xyz.ps1' 'a nonexistent leaf should become shared_engine_unresolved'

    # 7. Splat with a nonexistent key.
    $f = New-Fixture $wrapDir 'splat-bad.ps1' @'
$e = Join-Path $S 'scripts\Sync-GeneXusXpzToXml.ps1'
$p = @{ InputPath = $x; BogusKey = $z }
& $e @p
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-Signal $r 'forwards_unknown_engine_param' '*-BogusKey -> Sync-GeneXusXpzToXml.ps1*' 'a nonexistent splat key should signal'

    # 8. Splat with .Remove -> site skipped (non-trackable mutation).
    $f = New-Fixture $wrapDir 'splat-remove.ps1' @'
$e = Join-Path $S 'scripts\Sync-GeneXusXpzToXml.ps1'
$p = @{ InputPath = $x; BogusKey = $z }
$p.Remove('BogusKey')
& $e @p
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-NoSignalReason $r 'forwards_unknown_engine_param' 'a splat with .Remove should skip the site'
    Assert-Eq $r.AuditedSiteCount 0 'a site with a mutated splat is not audited'

    # 9. Colon form -Param:$v (name extracted).
    $f = New-Fixture $wrapDir 'colon.ps1' @'
param([switch]$AsJson)
$e = Join-Path $S 'scripts\Sync-GeneXusXpzToXml.ps1'
& $e -InputPath $x -BogusColon:$AsJson
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $realEngines
    Assert-Signal $r 'forwards_unknown_engine_param' '*-BogusColon -> Sync-GeneXusXpzToXml.ps1*' 'the -Param:$v form should extract the name'

    # --- SYNTHETIC engines (temp EnginesRoot) ---

    [void](New-Fixture $synthEngines 'SimpleEngine.ps1' "param([string]`$X)`n`"ok`"")
    [void](New-Fixture $synthEngines 'AdvancedEngine.ps1' "[CmdletBinding()]`nparam([string]`$X)`n`"ok`"")
    [void](New-Fixture $synthEngines 'AdversarialSimpleEngine.ps1' "param([switch]`$Verbose,[switch]`$Debug,[switch]`$ErrorAction,[switch]`$WarningAction,[switch]`$OutBuffer,[string]`$X)`n`"ok`"")
    [void](New-Fixture $synthEngines 'BrokenEngine.ps1' "[CmdletBinding()]`nparam([string]`$X`n`"oops")

    # 10. SIMPLE engine -> skipped even when forwarding -Foo.
    $f = New-Fixture $wrapDir 'use-simple.ps1' @'
$e = Join-Path $S 'scripts\SimpleEngine.ps1'
& $e -Foo $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $synthEngines
    Assert-NoSignalReason $r 'forwards_unknown_engine_param' 'a SIMPLE engine is permissive: do not audit'
    Assert-Eq $r.AuditedSiteCount 0 'a SIMPLE engine does not count as audited'

    # 11. Adversarial SIMPLE engine (declares literal Verbose/Debug/...) -> still skipped.
    $f = New-Fixture $wrapDir 'use-adversarial.ps1' @'
$e = Join-Path $S 'scripts\AdversarialSimpleEngine.ps1'
& $e -Foo $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $synthEngines
    Assert-NoSignalReason $r 'forwards_unknown_engine_param' 'SIMPLE with literal CommonParameter names is still SIMPLE'
    Assert-Eq $r.AuditedSiteCount 0 'an adversarial SIMPLE engine is not audited'

    # 12. Synthetic ADVANCED engine -> signals -Foo.
    $f = New-Fixture $wrapDir 'use-advanced.ps1' @'
$e = Join-Path $S 'scripts\AdvancedEngine.ps1'
& $e -Foo $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $synthEngines
    Assert-Signal $r 'forwards_unknown_engine_param' '*-Foo -> AdvancedEngine.ps1*' 'an advanced engine with a nonexistent -Foo should signal'

    # 13. Parse-broken engine -> engine_unresolved_or_unparseable (diagnostic), not a crash.
    $f = New-Fixture $wrapDir 'use-broken.ps1' @'
$e = Join-Path $S 'scripts\BrokenEngine.ps1'
& $e -Foo $y
'@
    $r = Get-MimirWrapperEngineParamFinding -WrapperPath $f -EnginesRoot $synthEngines
    $diag = @($r.EngineDiagnostics | Where-Object { $_.Reason -eq 'engine_unresolved_or_unparseable' -and $_.Detail -eq 'BrokenEngine.ps1' })
    if ($diag.Count -eq 0) { throw "ASSERT_FAILED: a parse-broken engine should produce engine_unresolved_or_unparseable" }
    Assert-NoSignalReason $r 'forwards_unknown_engine_param' 'a broken engine must not produce a parameter signal'

    Write-Output 'MIMIR_WRAPPER_ENGINE_PARAM_SELFTEST_OK'
} finally {
    if ($tempRoot.StartsWith([System.IO.Path]::GetTempPath(), [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $tempRoot -PathType Container)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
