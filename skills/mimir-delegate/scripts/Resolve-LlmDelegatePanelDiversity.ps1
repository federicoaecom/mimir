#requires -Version 7.4
<#
.SYNOPSIS
    Evaluates, in a CONSULTATIVE way, whether a set of reviewer candidates (with their gate
    verdicts) reaches the DIVERSITY FLOOR of a peer review (>=2 distinct families).
.DESCRIPTION
    Part of the mimir-delegate skill mechanism; methodology in 15-peer-review.md.

    Family for the floor = Model Creator via Get-LlmDelegateTargetFamily(targetModelKey).
    An explicit family on the item is an echo (it does not govern allow/potential/dropped).
    Only creators in Test-LlmDelegateFamilyKnown count; unknown ones go to droppedUnknownFamilies.

    hasFallbackEvidence requires (attemptRole=fallback OR fallbackOf not empty) AND
    (dispatchAttempted=true OR attempts>=1).

    States: panelReady | needsBatchAuthorization | insufficientDiversityAfterFallback |
    insufficientDiversity.

    Output: machine JSON object on stdout (adds droppedUnknownFamilies,
    unknownFamiliesPresent).
.PARAMETER CandidatesJson
    JSON (array) of the candidates.
.PARAMETER Floor
    Floor of distinct families. Default 2.
.PARAMETER AuthorFamily
    Model Creator of the manuscript's author (not the tool's name).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [string] $CandidatesJson,
    [int] $Floor = 2,
    [string] $AuthorFamily
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'LlmDelegateTargetFamilySupport.ps1')

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and -not [string]::IsNullOrEmpty($Name) -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function Get-Family {
    param([string]$TargetModelKey)
    return Get-LlmDelegateTargetFamily -TargetModelKey $TargetModelKey
}

$parsed = $null
try { $parsed = $CandidatesJson | ConvertFrom-Json } catch {
    throw "BLOCK: -CandidatesJson is not valid JSON: $($_.Exception.Message)"
}
$items = @($parsed)

$allowFamilies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$askByNewFamily = [System.Collections.Generic.List[object]]::new()
$potentialFamilies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$dispatchable = [System.Collections.Generic.List[object]]::new()
$droppedUnknown = [System.Collections.Generic.List[object]]::new()
$droppedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Pass 0: all items (including countsForDiversity=false) — unknown families
foreach ($it in $items) {
    $target = [string](Get-Prop $it 'targetModelKey')
    $fam = Get-Family $target
    $known = (Test-LlmDelegateFamilyKnown -Family $fam)
    if (-not $known -or [string]::IsNullOrWhiteSpace($fam)) {
        if (-not [string]::IsNullOrWhiteSpace($target) -and $droppedKeys.Add($target)) {
            $droppedUnknown.Add([pscustomobject]@{
                    targetModelKey = $target
                    resolvedFamily = $fam
                    backend        = [string](Get-Prop $it 'backend')
                })
        }
    }
}

# 1) Already-dispatchable families (allow) — known only
foreach ($it in $items) {
    $countsRaw = Get-Prop $it 'countsForDiversity'
    if ($countsRaw -eq $false) { continue }
    $verdict = [string](Get-Prop $it 'verdict')
    $stateValue = [string](Get-Prop $it 'state')
    if ([string]::IsNullOrWhiteSpace($verdict) -and $stateValue -eq 'responded') { $verdict = 'allow' }
    $target = [string](Get-Prop $it 'targetModelKey')
    $fam = Get-Family $target
    if ([string]::IsNullOrWhiteSpace($fam)) { continue }
    if (-not (Test-LlmDelegateFamilyKnown -Family $fam)) { continue }
    if ($verdict -eq 'allow') {
        [void]$allowFamilies.Add($fam)
        [void]$potentialFamilies.Add($fam)
        $dispatchable.Add([pscustomobject]@{ targetModelKey = $target; family = $fam; backend = [string](Get-Prop $it 'backend') })
    }
}

# 2) `ask` items that add a family not yet covered by `allow`
foreach ($it in $items) {
    $countsRaw = Get-Prop $it 'countsForDiversity'
    if ($countsRaw -eq $false) { continue }
    $verdict = [string](Get-Prop $it 'verdict')
    $stateValue = [string](Get-Prop $it 'state')
    if ([string]::IsNullOrWhiteSpace($verdict) -and $stateValue -eq 'responded') { $verdict = 'allow' }
    if ($verdict -ne 'ask') { continue }
    $target = [string](Get-Prop $it 'targetModelKey')
    $fam = Get-Family $target
    if ([string]::IsNullOrWhiteSpace($fam)) { continue }
    if (-not (Test-LlmDelegateFamilyKnown -Family $fam)) { continue }
    [void]$potentialFamilies.Add($fam)
    if (-not $allowFamilies.Contains($fam)) {
        $askByNewFamily.Add([pscustomobject]@{ targetModelKey = $target; family = $fam; backend = [string](Get-Prop $it 'backend') })
    }
}

$allowCount = $allowFamilies.Count
$potentialCount = $potentialFamilies.Count

$hasFallbackEvidence = @($items | Where-Object {
        $isFb = (-not [string]::IsNullOrWhiteSpace([string](Get-Prop $_ 'fallbackOf'))) -or ([string](Get-Prop $_ 'attemptRole') -eq 'fallback')
        if (-not $isFb) { return $false }
        $dispatched = ([bool](Get-Prop $_ 'dispatchAttempted') -eq $true)
        $attempts = 0
        try { $attempts = [int](Get-Prop $_ 'attempts') } catch { $attempts = 0 }
        return ($dispatched -or $attempts -ge 1)
    }).Count -gt 0

$state = if ($allowCount -ge $Floor) { 'panelReady' }
elseif ($potentialCount -ge $Floor) { 'needsBatchAuthorization' }
elseif ($hasFallbackEvidence) { 'insufficientDiversityAfterFallback' }
else { 'insufficientDiversity' }

$authorInPanel = $false
if (-not [string]::IsNullOrWhiteSpace($AuthorFamily)) {
    $authorInPanel = $allowFamilies.Contains($AuthorFamily.Trim())
}

$fallbackLabel = if ($state -ne 'panelReady') { "second opinion ($($dispatchable.Count))" } else { $null }
$unknownPresent = $droppedUnknown.Count -gt 0

[pscustomobject]@{
    floor                     = $Floor
    panelReady                = ($state -eq 'panelReady')
    state                     = $state
    distinctFamiliesAllow     = @($allowFamilies)
    distinctFamiliesPotential = @($potentialFamilies)
    dispatchable              = @($dispatchable)
    askToAuthorize            = @($askByNewFamily)
    authorFamily              = $AuthorFamily
    authorFamilyInPanel       = $authorInPanel
    fallbackLabel             = $fallbackLabel
    droppedUnknownFamilies    = @($droppedUnknown)
    unknownFamiliesPresent    = $unknownPresent
    note                      = 'Consultative; NOT authorization. Family = Model Creator via Get-LlmDelegateTargetFamily(targetModelKey); only creators in Test-LlmDelegateFamilyKnown count toward the floor. Input family is an echo. hasFallbackEvidence requires actual dispatch on the chain link.'
} | ConvertTo-Json -Depth 8
