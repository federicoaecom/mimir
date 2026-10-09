#requires -Version 7.4
<#
.SYNOPSIS
    Emits a session reminder when gx-object-type-catalog.override.json is active.

.PARAMETER KbWorkspaceRoot
    Root of the KB workspace.

.PARAMETER CatalogOverridePath
    Optional path of the override.

.PARAMETER AsJson
    JSON output (recommended for agents).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KbWorkspaceRoot,

    [string]$CatalogOverridePath,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GeneXusObjectTypeCatalogSupport.ps1')

$resolvedKbRoot = (Resolve-Path -LiteralPath $KbWorkspaceRoot).Path
$reminder = Get-GeneXusCatalogOverrideSessionReminder -KbWorkspaceRoot $resolvedKbRoot -CatalogOverridePath $CatalogOverridePath

$result = [pscustomobject]@{
    status                   = $reminder.status
    kbWorkspaceRoot          = $resolvedKbRoot
    reminderRequired         = $reminder.reminderRequired
    noticeRequired           = $reminder.noticeRequired
    cleanupRecommended       = $reminder.cleanupRecommended
    blocked                  = $reminder.blocked
    overrideActive           = $reminder.overrideActive
    upstreamPending          = $reminder.upstreamPending
    declaredUpstreamPending  = $reminder.declaredUpstreamPending
    effectiveUpstreamPending = $reminder.effectiveUpstreamPending
    reason                   = $reminder.reason
    diagnosticReason         = $reminder.diagnosticReason
    fieldPath                = $reminder.fieldPath
    overridePath             = $reminder.overridePath
    pendingTypeNames         = $reminder.pendingTypeNames
    pendingTypeGuids         = $reminder.pendingTypeGuids
    redundantTypeNames       = $reminder.redundantTypeNames
    redundantTypeGuids       = $reminder.redundantTypeGuids
    divergentTypeNames       = $reminder.divergentTypeNames
    divergentTypeGuids       = $reminder.divergentTypeGuids
    blockedTypeNames         = $reminder.blockedTypeNames
    blockedTypeGuids         = $reminder.blockedTypeGuids
    classificationEntries    = $reminder.classificationEntries
    message                  = $reminder.message
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
} else {
    if ($reminder.reminderRequired) {
        Write-Output $reminder.message
    } elseif ($reminder.cleanupRecommended) {
        $names = @($reminder.redundantTypeNames) -join ', '
        if ([string]::IsNullOrWhiteSpace($names)) {
            Write-Output 'CLEANUP_RECOMMENDED: local override active with no effective pending item; approved local removal is recommended if there are no type entries.'
        } else {
            Write-Output ("CLEANUP_RECOMMENDED: redundant local override for: {0}. Approved local removal is recommended; there is no effective global pending item." -f $names)
        }
    } elseif ($reminder.overrideActive) {
        Write-Output ("{0}: local override active with no pending reminder." -f $reminder.status)
    } else {
        Write-Output 'OK: no local catalog override active.'
    }
}

exit $(if ($reminder.status -in @('REMINDER_REQUIRED', 'INVALID_OVERRIDE_SHAPE', 'OVERRIDE_RESOLUTION_BLOCKED')) { 2 } else { 0 })
