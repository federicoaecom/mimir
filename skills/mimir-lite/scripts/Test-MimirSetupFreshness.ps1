#requires -Version 7.4
<#
.SYNOPSIS
    Checks whether the KB workspace's setup is fresh with respect to the XPZ setup contract.

.DESCRIPTION
    Reads last_setup_audit_run_at and setup_contract_signature_* from kb-source-metadata.md,
    computes the current signature of the setup workflow contract surface, and
    compares it with the signature recorded after the last successful audit.
    Returns GATE_ONLY when the audited signature matches the current one; returns
    AUDIT_REQUIRED with a reason in every other case.

    Designed to be called by the local wrapper Test-*KbSetupFreshness.ps1 as the first action
    of the mandatory PRE-CONDITION in the setup workflow.

.PARAMETER KbWorkspaceRoot
    Root of the KB workspace (must contain kb-source-metadata.md).

.PARAMETER SkillsRoot
    Root of the mimir-lite repository.

.OUTPUTS
    String: "GATE_ONLY" or "AUDIT_REQUIRED: <reason>"

.EXAMPLE
    .\Test-MimirSetupFreshness.ps1 -KbWorkspaceRoot "C:\KBs\SampleKb" -SkillsRoot "C:\path\to\mimir-lite"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$KbWorkspaceRoot,

    [Parameter(Mandatory = $true)]
    [string]$SkillsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$metadataPath = Join-Path $KbWorkspaceRoot 'kb-source-metadata.md'

if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    Write-Output "AUDIT_REQUIRED: kb-source-metadata.md missing in $KbWorkspaceRoot"
    exit 0
}

$content = Get-Content -LiteralPath $metadataPath -Raw

if ($content -notmatch '(?m)^last_setup_audit_run_at:\s*(.+)$') {
    Write-Output 'AUDIT_REQUIRED: last_setup_audit_run_at field missing in kb-source-metadata.md'
    exit 0
}

$rawTimestamp = $Matches[1].Trim()

if ([string]::IsNullOrWhiteSpace($rawTimestamp)) {
    Write-Output 'AUDIT_REQUIRED: last_setup_audit_run_at field empty in kb-source-metadata.md'
    exit 0
}

$lastAudit = $null
try {
    $lastAudit = [DateTimeOffset]::Parse($rawTimestamp)
} catch {
    Write-Output "AUDIT_REQUIRED: last_setup_audit_run_at is not a valid timestamp: '$rawTimestamp'"
    exit 0
}

$storedSignatureVersion = $null
if ($content -match '(?m)^setup_contract_signature_version:\s*(.+)$') {
    $storedSignatureVersion = $Matches[1].Trim()
}

if ([string]::IsNullOrWhiteSpace($storedSignatureVersion)) {
    Write-Output 'AUDIT_REQUIRED: setup_contract_signature_version field missing in kb-source-metadata.md'
    exit 0
}

$storedSignatureHash = $null
if ($content -match '(?m)^setup_contract_signature_hash:\s*(.+)$') {
    $storedSignatureHash = $Matches[1].Trim()
}

if ([string]::IsNullOrWhiteSpace($storedSignatureHash)) {
    Write-Output 'AUDIT_REQUIRED: setup_contract_signature_hash field missing in kb-source-metadata.md'
    exit 0
}

if ($storedSignatureHash -notmatch '^[0-9a-fA-F]{64}$') {
    Write-Output "AUDIT_REQUIRED: setup_contract_signature_hash invalid in kb-source-metadata.md: '$storedSignatureHash'"
    exit 0
}

$signatureScriptPath = Join-Path $SkillsRoot 'skills\mimir-lite\scripts\Get-MimirSetupContractSignature.ps1'
if (-not (Test-Path -LiteralPath $signatureScriptPath -PathType Leaf)) {
    Write-Output "AUDIT_REQUIRED: setup contract signature engine missing at $signatureScriptPath"
    exit 0
}

$signatureJson = & $signatureScriptPath -SkillsRoot $SkillsRoot -AsJson
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($signatureJson)) {
    Write-Output "AUDIT_REQUIRED: could not compute the current setup contract signature in $SkillsRoot"
    exit 0
}

$currentSignature = $signatureJson | ConvertFrom-Json

if ($storedSignatureVersion -ne $currentSignature.signatureVersion) {
    Write-Output "AUDIT_REQUIRED: setup contract signature version changed from $storedSignatureVersion to $($currentSignature.signatureVersion); last audit at $($lastAudit.ToString('o'))"
    exit 0
}

if ($storedSignatureHash -ne $currentSignature.signatureHash) {
    Write-Output "AUDIT_REQUIRED: setup contract updated; current signature $($currentSignature.signatureHash); audited signature $storedSignatureHash; last audit at $($lastAudit.ToString('o'))"
    exit 0
}

Write-Output 'GATE_ONLY'
exit 0
