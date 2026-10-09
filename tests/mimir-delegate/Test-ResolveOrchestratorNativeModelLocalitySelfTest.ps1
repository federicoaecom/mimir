#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for Resolve-OrchestratorNativeModelLocality.ps1 and the gate with Backend orchestrator-native.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$locality = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-OrchestratorNativeModelLocality.ps1'
$auth = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Resolve-LlmDelegateAuthorization.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $locality -PathType Leaf) "Missing script: $locality"
Assert-True (Test-Path -LiteralPath $auth -PathType Leaf) "Missing script: $auth"

# (1) Full gate: orchestrator-native + kb-sensitive with no policy -> ask (no PropertyNotFound)
$authOut = $null
$authErrMsg = $null
try {
    $authOut = & $auth -Backend orchestrator-native -Model 'moonshot/kimi-k3-max' -PayloadSensitivity 'kb-sensitive' | ConvertFrom-Json
} catch {
    $authErrMsg = [string]$_.Exception.Message
}
Assert-True ([string]::IsNullOrEmpty($authErrMsg)) ("(1) Gate should not throw; got: {0}" -f $authErrMsg)
Assert-True ($null -ne $authOut) '(1) Gate should emit JSON.'
Assert-True ([string]$authOut.verdict -eq 'ask') ("(1) with no policy, kb-sensitive + external/unknown -> ask; got '{0}'." -f $authOut.verdict)
$authBlob = ($authOut | ConvertTo-Json -Depth 6 -Compress)
Assert-True ($authBlob -notlike '*PropertyNotFound*') '(1) there must be no PropertyNotFound in the result.'
Assert-True ($authErrMsg -notlike '*PropertyNotFound*') '(1) there must be no PropertyNotFound in the exception.'

# (2) key without a slash -> unknown / native-key-no-slash
$r2 = & $locality -Model 'kimi-k3-max' | ConvertFrom-Json
Assert-True ([string]$r2.locality -eq 'unknown') "(2) locality should be unknown; got '$($r2.locality)'."
Assert-True ([string]$r2.reason -eq 'native-key-no-slash') "(2) reason should be native-key-no-slash; got '$($r2.reason)'."

# (3) cursor prefix without a Creator mapping -> unknown / native-cursor-prefix
$r3 = & $locality -Model 'cursor/unmapped-model' | ConvertFrom-Json
Assert-True ([string]$r3.locality -eq 'unknown') "(3) locality should be unknown; got '$($r3.locality)'."
Assert-True ([string]$r3.reason -eq 'native-cursor-prefix') "(3) reason should be native-cursor-prefix; got '$($r3.reason)'."

# (4) known cloud creator -> external / native-cloud-creator (direct resolver)
$r4 = & $locality -Model 'moonshot/kimi-k3-max' | ConvertFrom-Json
Assert-True ([string]$r4.locality -eq 'external') "(4) locality should be external; got '$($r4.locality)'."
Assert-True ([string]$r4.reason -eq 'native-cloud-creator') "(4) reason should be native-cloud-creator; got '$($r4.reason)'."
Assert-True ([string]$r4.family -eq 'moonshot') "(4) family should be moonshot; got '$($r4.family)'."

# (5) G16: creator outside the allowlist -> unknown / native-unknown-family (never local)
$r5 = & $locality -Model 'invented-vendor/model-x' | ConvertFrom-Json
Assert-True ([string]$r5.locality -eq 'unknown') "(5) unknown creator should be unknown; got '$($r5.locality)'."
Assert-True ([string]$r5.reason -eq 'native-unknown-family') "(5) reason should be native-unknown-family; got '$($r5.reason)'."
Assert-True ([string]$r5.locality -ne 'local') '(5) native should never classify as local.'

# (6) cursor-grok-* (slug without a slash) -> xai / external / native-cloud-creator
$r6 = & $locality -Model 'cursor-grok-4.6-medium' | ConvertFrom-Json
Assert-True ([string]$r6.family -eq 'xai') "(6) family should be xai; got '$($r6.family)'."
Assert-True ([string]$r6.locality -eq 'external') "(6) locality should be external; got '$($r6.locality)'."
Assert-True ([string]$r6.reason -eq 'native-cloud-creator') "(6) reason should be native-cloud-creator; got '$($r6.reason)'."

# (7) cursor/grok-* (form with a slash) -> xai / external
$r7 = & $locality -Model 'cursor/grok-4' | ConvertFrom-Json
Assert-True ([string]$r7.family -eq 'xai') "(7) family should be xai; got '$($r7.family)'."
Assert-True ([string]$r7.locality -eq 'external') "(7) locality should be external; got '$($r7.locality)'."
Assert-True ([string]$r7.reason -eq 'native-cloud-creator') "(7) reason should be native-cloud-creator; got '$($r7.reason)'."

# (8) cursor/composer-* -> anysphere / external (the weights' Creator, not the corporate owner)
$r8 = & $locality -Model 'cursor/composer-2' | ConvertFrom-Json
Assert-True ([string]$r8.family -eq 'anysphere') "(8) family should be anysphere; got '$($r8.family)'."
Assert-True ([string]$r8.locality -eq 'external') "(8) locality should be external; got '$($r8.locality)'."
Assert-True ([string]$r8.reason -eq 'native-cloud-creator') "(8) reason should be native-cloud-creator; got '$($r8.reason)'."

# (9) cursor-composer-* (slug without a slash) -> anysphere / external
$r9 = & $locality -Model 'cursor-composer-2-medium' | ConvertFrom-Json
Assert-True ([string]$r9.family -eq 'anysphere') "(9) family should be anysphere; got '$($r9.family)'."
Assert-True ([string]$r9.locality -eq 'external') "(9) locality should be external; got '$($r9.locality)'."
Assert-True ([string]$r9.reason -eq 'native-cloud-creator') "(9) reason should be native-cloud-creator; got '$($r9.reason)'."

Write-Host 'OK: Test-ResolveOrchestratorNativeModelLocalitySelfTest.ps1'
