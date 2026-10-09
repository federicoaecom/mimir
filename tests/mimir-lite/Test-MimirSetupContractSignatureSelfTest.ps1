#requires -Version 7.4
<#
.SYNOPSIS
    Validates the signature contract used by setup freshness.

.DESCRIPTION
    Covers the conservative migration with no signature recorded, the GATE_ONLY
    path after recording a signature, a change outside the signed surface, and
    a change inside the signed surface.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts'
$repoRoot = Split-Path -Parent $scriptDir

$utf8NoBomEncodingSupportPath = Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

function Write-Utf8NoBomText {
    param(
        [string]$Path,
        [string]$Text
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }

    $utf8NoBom = Get-Utf8NoBomEncoding
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Copy-SelfTestScript {
    param(
        [string]$Name,
        [string]$DestinationScriptsDir
    )

    Copy-Item -LiteralPath (Join-Path $scriptDir $Name) -Destination (Join-Path $DestinationScriptsDir $Name) -Force
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw "ASSERT_FAILED: $Message | output=$Text"
    }
}

function Invoke-Freshness {
    param(
        [string]$KbRoot,
        [string]$SkillsRoot
    )

    $freshnessPath = Join-Path $SkillsRoot 'skills\mimir-lite\scripts\Test-MimirSetupFreshness.ps1'
    $output = & $freshnessPath -KbWorkspaceRoot $KbRoot -SkillsRoot $SkillsRoot 2>&1 | ForEach-Object { $_.ToString() }
    return ($output -join [Environment]::NewLine).Trim()
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-setup-contract-signature-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$skillsRoot = Join-Path $tempRoot 'skills'
$kbRoot = Join-Path $tempRoot 'kb'
$tempScriptsDir = Join-Path $skillsRoot 'skills\mimir-lite\scripts'
$tempWorkflowsDir = Join-Path $skillsRoot 'skills\mimir-lite\workflows'
$tempSetupDir = Join-Path $tempWorkflowsDir 'setup'
$tempExamplesDir = Join-Path $tempSetupDir 'examples'
$auditTimestamp = '2026-06-04T12:00:00.0000000+00:00'

try {
    [void](New-Item -ItemType Directory -Path $tempScriptsDir -Force)
    [void](New-Item -ItemType Directory -Path $tempExamplesDir -Force)
    [void](New-Item -ItemType Directory -Path $kbRoot -Force)

    Copy-SelfTestScript -Name 'Get-MimirSetupContractSignature.ps1' -DestinationScriptsDir $tempScriptsDir
    Copy-SelfTestScript -Name 'Test-MimirSetupFreshness.ps1' -DestinationScriptsDir $tempScriptsDir
    Copy-SelfTestScript -Name 'Set-MimirSetupAuditTimestamp.ps1' -DestinationScriptsDir $tempScriptsDir
    Copy-SelfTestScript -Name 'MimirTextFileEolSupport.ps1' -DestinationScriptsDir $tempScriptsDir
    Copy-SelfTestScript -Name 'Utf8NoBomEncodingSupport.ps1' -DestinationScriptsDir $tempScriptsDir

    $manifestText = @'
{
  "signatureVersion": "mimir-setup-contract-signature-v1",
  "description": "Fixture de self-test",
  "include": [
    "skills/mimir-lite/workflows/setup.md",
    "skills/mimir-lite/workflows/setup/examples/*",
    "skills/mimir-lite/scripts/Get-MimirSetupContractSignature.ps1",
    "skills/mimir-lite/scripts/Test-MimirSetupFreshness.ps1",
    "skills/mimir-lite/scripts/Set-MimirSetupAuditTimestamp.ps1"
  ]
}
'@

    Write-Utf8NoBomText -Path (Join-Path $tempSetupDir 'setup-contract.manifest.json') -Text $manifestText
    Write-Utf8NoBomText -Path (Join-Path $tempWorkflowsDir 'setup.md') -Text "# setup`n`nContrato fixture.`n"
    Write-Utf8NoBomText -Path (Join-Path $tempExamplesDir 'Test-KbSetupFreshness.example.ps1') -Text "#requires -Version 7.4`n# fixture`n"
    Write-Utf8NoBomText -Path (Join-Path $skillsRoot '08-agent-guide.md') -Text "fora da superficie assinada`n"

    $metadataPath = Join-Path $kbRoot 'kb-source-metadata.md'
    $metadataText = @"
---
name: KB Source Metadata
last_xpz_materialization_run_at: 2026-06-04T11:00:00.0000000+00:00
last_setup_audit_run_at: $auditTimestamp
---

## Source
"@
    Write-Utf8NoBomText -Path $metadataPath -Text ($metadataText + "`n")

    $migrationOutput = Invoke-Freshness -KbRoot $kbRoot -SkillsRoot $skillsRoot
    Assert-Contains -Text $migrationOutput -Pattern 'AUDIT_REQUIRED: setup_contract_signature_version field missing' -Message 'metadata with no signature should require a migration audit'

    $setTimestampPath = Join-Path $tempScriptsDir 'Set-MimirSetupAuditTimestamp.ps1'
    $setOutput = & $setTimestampPath -KbWorkspaceRoot $kbRoot -SkillsRoot $skillsRoot -AuditTimestamp $auditTimestamp 2>&1 | ForEach-Object { $_.ToString() }
    Assert-Contains -Text ($setOutput -join ' ') -Pattern 'SETUP_AUDIT_TIMESTAMP_OK' -Message 'recording the timestamp should succeed'

    $gateOnlyOutput = Invoke-Freshness -KbRoot $kbRoot -SkillsRoot $skillsRoot
    Assert-Contains -Text $gateOnlyOutput -Pattern '^GATE_ONLY$' -Message 'a recorded signature should unlock the light path'

    Write-Utf8NoBomText -Path (Join-Path $skillsRoot '08-agent-guide.md') -Text "mudanca irrelevante ao contrato de setup`n"
    $outsideOutput = Invoke-Freshness -KbRoot $kbRoot -SkillsRoot $skillsRoot
    Assert-Contains -Text $outsideOutput -Pattern '^GATE_ONLY$' -Message 'a change outside the signed surface should not require an audit'

    Write-Utf8NoBomText -Path (Join-Path $tempExamplesDir 'Test-KbSetupFreshness.example.ps1') -Text "#requires -Version 7.4`n# fixture alterado`n"
    $insideOutput = Invoke-Freshness -KbRoot $kbRoot -SkillsRoot $skillsRoot
    Assert-Contains -Text $insideOutput -Pattern 'AUDIT_REQUIRED: setup contract updated' -Message 'a change inside the signed surface should require an audit'

    Write-Output 'MIMIR_SETUP_CONTRACT_SIGNATURE_SELFTEST_OK'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
