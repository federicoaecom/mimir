#requires -Version 7.4
<#
.SYNOPSIS
    Writes last_setup_audit_run_at and the setup contract signature into kb-source-metadata.md.

.DESCRIPTION
    Updates or inserts only the fields last_setup_audit_run_at,
    setup_contract_signature_version, and setup_contract_signature_hash, preserving
    the rest of the file (content, dominant EOL, and trailing newline).
    Authority for this operation: the setup workflow (successful setup audit).

    Designed to be called by the local wrapper Set-*KbSetupAuditTimestamp.ps1 after a
    complete audit with a successful canonical state or in the setup_ready_metadata_pending
    sub-state.

.PARAMETER KbWorkspaceRoot
    Root of the KB workspace (must contain kb-source-metadata.md).

.PARAMETER AuditTimestamp
    ISO 8601 timestamp with time zone. When omitted, uses the current system instant.

.PARAMETER SkillsRoot
    Root of the XPZ skills repository. When omitted, uses the scripts folder's parent root.

.PARAMETER AsJson
    Emits a JSON object instead of plain text.

.OUTPUTS
    String "SETUP_AUDIT_TIMESTAMP_OK: <timestamp>" or JSON with status.

.EXAMPLE
    .\Set-MimirSetupAuditTimestamp.ps1 -KbWorkspaceRoot "C:\KBs\SampleKb"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KbWorkspaceRoot,

    [string]$AuditTimestamp,

    [string]$SkillsRoot,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$metadataPath = Join-Path $KbWorkspaceRoot 'kb-source-metadata.md'

if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
  throw "BLOCK: kb-source-metadata.md missing in $KbWorkspaceRoot"
}

$isoValue = $null
if ([string]::IsNullOrWhiteSpace($AuditTimestamp)) {
  $isoValue = (Get-Date).ToString('o')
} else {
  try {
    $parsed = [DateTimeOffset]::Parse($AuditTimestamp.Trim())
    $isoValue = $parsed.ToString('o')
  } catch {
    throw "BLOCK: AuditTimestamp is not a valid timestamp: '$AuditTimestamp'"
  }
}

. (Join-Path $PSScriptRoot 'MimirTextFileEolSupport.ps1')

if ([string]::IsNullOrWhiteSpace($SkillsRoot)) {
  # $PSScriptRoot now lives in skills/mimir-lite/scripts/ (3 levels under the repo
  # root); 3 "-Parent" hops from here reach the real root.
  $SkillsRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

$signatureScriptPath = Join-Path $PSScriptRoot 'Get-MimirSetupContractSignature.ps1'
if (-not (Test-Path -LiteralPath $signatureScriptPath -PathType Leaf)) {
  throw "BLOCK: setup contract signature engine missing: $signatureScriptPath"
}

$signatureJson = & $signatureScriptPath -SkillsRoot $SkillsRoot -AsJson
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($signatureJson)) {
  throw "BLOCK: could not compute the current setup contract signature in $SkillsRoot"
}

$currentSignature = $signatureJson | ConvertFrom-Json

$fileContext = Get-TextFileLineContext -Path $metadataPath
$fileLines = $fileContext.Lines

function Get-MetadataFieldLineIndex {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$FieldName
  )

  $fieldPattern = '^\s*{0}\s*[:=]\s*.+$' -f [regex]::Escape($FieldName)
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match $fieldPattern) {
      return $i
    }
  }

  return -1
}

function Get-DefaultMetadataInsertIndex {
  param(
    [System.Collections.Generic.List[string]]$Lines
  )

  $insertAt = -1
  $frontmatterClose = -1
  $hasFrontmatter = ($Lines.Count -gt 0 -and $Lines[0].Trim() -eq '---')

  if ($hasFrontmatter) {
    for ($i = 1; $i -lt $Lines.Count; $i++) {
      if ($Lines[$i].Trim() -eq '---') {
        $frontmatterClose = $i
        break
      }
    }

    if ($frontmatterClose -gt 0) {
      $insertAt = $frontmatterClose
      for ($j = 1; $j -lt $frontmatterClose; $j++) {
        if ($Lines[$j] -match '^\s*last_xpz_materialization_run_at\s*[:=]') {
          $insertAt = $j + 1
        }
      }
    }
  } else {
    for ($i = 0; $i -lt $Lines.Count; $i++) {
      if ($Lines[$i] -match '^\s*##\s+') {
        $insertAt = $i
        break
      }
    }

    if ($insertAt -lt 0) {
      $insertAt = $Lines.Count
    }

    for ($j = 0; $j -lt $insertAt; $j++) {
      if ($Lines[$j] -match '^\s*last_xpz_materialization_run_at\s*[:=]') {
        $insertAt = $j + 1
      }
    }
  }

  if ($insertAt -lt 0) {
    if ($frontmatterClose -gt 0) {
      $insertAt = $frontmatterClose
    } else {
      $insertAt = 0
    }
  }

  return $insertAt
}

function Set-MetadataFieldLine {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$FieldName,
    [string]$Value,
    [string]$AfterFieldName
  )

  $newFieldLine = "${FieldName}: $Value"
  $existingIndex = Get-MetadataFieldLineIndex -Lines $Lines -FieldName $FieldName
  if ($existingIndex -ge 0) {
    $Lines[$existingIndex] = $newFieldLine
    return
  }

  $insertAt = -1
  if (-not [string]::IsNullOrWhiteSpace($AfterFieldName)) {
    $afterIndex = Get-MetadataFieldLineIndex -Lines $Lines -FieldName $AfterFieldName
    if ($afterIndex -ge 0) {
      $insertAt = $afterIndex + 1
    }
  }

  if ($insertAt -lt 0) {
    $insertAt = Get-DefaultMetadataInsertIndex -Lines $Lines
  }

  $Lines.Insert($insertAt, $newFieldLine)
}

Set-MetadataFieldLine -Lines $fileLines -FieldName 'last_setup_audit_run_at' -Value $isoValue -AfterFieldName ''
Set-MetadataFieldLine -Lines $fileLines -FieldName 'setup_contract_signature_version' -Value $currentSignature.signatureVersion -AfterFieldName 'last_setup_audit_run_at'
Set-MetadataFieldLine -Lines $fileLines -FieldName 'setup_contract_signature_hash' -Value $currentSignature.signatureHash -AfterFieldName 'setup_contract_signature_version'

Write-TextFilePreservingEol -Path $metadataPath -FileContext $fileContext

if ($AsJson) {
  [pscustomobject]@{
    status = 'SETUP_AUDIT_TIMESTAMP_OK'
    last_setup_audit_run_at = $isoValue
    setup_contract_signature_version = $currentSignature.signatureVersion
    setup_contract_signature_hash = $currentSignature.signatureHash
    metadataPath = $metadataPath
  } | ConvertTo-Json -Compress
  exit 0
}

Write-Output "SETUP_AUDIT_TIMESTAMP_OK: $isoValue setup_contract_signature_hash=$($currentSignature.signatureHash)"
exit 0
