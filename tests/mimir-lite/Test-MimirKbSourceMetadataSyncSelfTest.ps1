#requires -Version 7.4
<#
.SYNOPSIS
    Validates that Update-MimirKbSourceMetadataFromSync preserves last_setup_audit_run_at, setup_contract_signature_* and LF EOL.

.DESCRIPTION
    LF fixture with a setup stamp/signature and minimal tables; simulates a materialization
    refresh and verifies that setup fields stay intact, CR=0, and materialization fields are updated.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$scriptDir = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')
$editSupportPath = Join-Path $scriptDir 'MimirKbSourceMetadataEditSupport.ps1'
$auditTimestamp = '2026-01-15T08:00:00.0000000+00:00'
$setupSignatureVersion = '2026-06-04T00:00:00Z'
$setupSignatureHash = 'sha256:selftest-setup-contract'
$oldMaterializationTimestamp = '2026-01-01T00:00:00.0000000+00:00'

function Get-CarriageReturnCount {
    param([string]$Path)

    $raw = [System.IO.File]::ReadAllText($Path)
    return ([regex]::Matches($raw, "`r")).Count
}

function New-LfMetadataFixture {
    param([string]$RootPath)

    $lines = @(
        '---'
        'name: KB Source Metadata'
        'description: self-test fixture'
        'last_xpz_materialization_run_at: 2026-01-01T00:00:00.0000000+00:00'
        'last_setup_audit_run_at: ' + $auditTimestamp
        'setup_contract_signature_version: ' + $setupSignatureVersion
        'setup_contract_signature_hash: ' + $setupSignatureHash
        'custom_future_field: keep-me'
        'source_xpz: C:\Old\Package.xpz'
        'source_refresh_status: partial-preserved'
        '---'
        ''
        '## KMW'
        ''
        '| Field | Value |'
        '|---|---|'
        '| MajorVersion | 17 |'
        '| MinorVersion | 0 |'
        '| Build | 100 |'
        ''
        '## Source'
        ''
        '| Field | Value |'
        '|---|---|'
        '| kb (GUID) | {11111111-1111-1111-1111-111111111111} |'
        '| username | olduser |'
        '| UNCPath | \\old\share |'
        ''
        '## Source/Version'
        ''
        '| Field | Value |'
        '|---|---|'
        '| guid | {22222222-2222-2222-2222-222222222222} |'
        '| name | OldVersion |'
        ''
        '## Notes'
        ''
        'Auxiliary text preserved by the self-test.'
    )

    $content = ($lines -join "`n") + "`n"
    $metadataPath = Join-Path $RootPath 'kb-source-metadata.md'
    $utf8NoBom = (Get-Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($metadataPath, $content, $utf8NoBom)
    return $metadataPath
}

function New-MinimalExportFileXml {
    param([string]$Path)

    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <KMW>
    <MajorVersion>18</MajorVersion>
    <MinorVersion>1</MinorVersion>
    <Build>200</Build>
  </KMW>
  <Source kb="{33333333-3333-3333-3333-333333333333}" username="newuser" UNCPath="\\new\share">
    <Version guid="{44444444-4444-4444-4444-444444444444}" name="NewVersion" />
  </Source>
  <Objects />
</ExportFile>
'@

    $utf8NoBom = (Get-Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($Path, $xml, $utf8NoBom)
}

function Assert-ZeroCr {
    param(
        [string]$Path,
        [string]$Message
    )

    $crCount = Get-CarriageReturnCount -Path $Path
    if ($crCount -ne 0) {
        throw "ASSERT_FAILED: $Message | crCount=$crCount path=$Path"
    }
}

function Assert-ContainsPattern {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    $raw = [System.IO.File]::ReadAllText($Path)
    if ($raw -notmatch $Pattern) {
        throw "ASSERT_FAILED: $Message | path=$Path"
    }
}

function Assert-NotContainsPattern {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    $raw = [System.IO.File]::ReadAllText($Path)
    if ($raw -match $Pattern) {
        throw "ASSERT_FAILED: $Message | path=$Path"
    }
}

. $editSupportPath

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-sync-kb-metadata-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$packageXmlPath = Join-Path $tempRoot 'minimal-export.xml'
$sourceXpzPath = 'C:\Dev\Test\Packages\SelfTestPackage.xpz'

try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)
    $metadataPath = New-LfMetadataFixture -RootPath $tempRoot
    New-MinimalExportFileXml -Path $packageXmlPath

    Assert-ZeroCr -Path $metadataPath -Message 'fixture should start without CR'
    Assert-ContainsPattern -Path $metadataPath -Pattern ('last_setup_audit_run_at:\s*' + [regex]::Escape($auditTimestamp)) -Message 'fixture should contain the setup stamp'
    Assert-ContainsPattern -Path $metadataPath -Pattern ('setup_contract_signature_version:\s*' + [regex]::Escape($setupSignatureVersion)) -Message 'fixture should contain the setup signature version'
    Assert-ContainsPattern -Path $metadataPath -Pattern ('setup_contract_signature_hash:\s*' + [regex]::Escape($setupSignatureHash)) -Message 'fixture should contain the setup signature hash'

    [xml]$packageXml = Get-Content -LiteralPath $packageXmlPath -Raw
    $result = Update-MimirKbSourceMetadataFromSync -XmlDocument $packageXml -SourceXpzPath $sourceXpzPath -MetadataPath $metadataPath

    if ($result.WriteMode -ne 'surgical-update') {
        throw "ASSERT_FAILED: expected WriteMode surgical-update | actual=$($result.WriteMode)"
    }

    Assert-ZeroCr -Path $metadataPath -Message 'materialization refresh should preserve LF EOL'
    Assert-ContainsPattern -Path $metadataPath -Pattern ('last_setup_audit_run_at:\s*' + [regex]::Escape($auditTimestamp)) -Message 'setup stamp should remain intact'
    Assert-ContainsPattern -Path $metadataPath -Pattern ('setup_contract_signature_version:\s*' + [regex]::Escape($setupSignatureVersion)) -Message 'setup signature version should remain intact'
    Assert-ContainsPattern -Path $metadataPath -Pattern ('setup_contract_signature_hash:\s*' + [regex]::Escape($setupSignatureHash)) -Message 'setup signature hash should remain intact'
    Assert-NotContainsPattern -Path $metadataPath -Pattern ('last_xpz_materialization_run_at:\s*' + [regex]::Escape($oldMaterializationTimestamp)) -Message 'old materialization timestamp should be replaced'

    $rawAfter = [System.IO.File]::ReadAllText($metadataPath)
    if ($rawAfter -notmatch '(?m)^updated:\s*(.+)$') {
        throw 'ASSERT_FAILED: updated field missing after refresh'
    }
    $updatedValue = $Matches[1].Trim()
    if ($rawAfter -notmatch '(?m)^last_xpz_materialization_run_at:\s*(.+)$') {
        throw 'ASSERT_FAILED: last_xpz_materialization_run_at field missing after refresh'
    }
    $materializedValue = $Matches[1].Trim()
    if ($updatedValue -ne $materializedValue) {
        throw "ASSERT_FAILED: updated and last_xpz_materialization_run_at should match | updated=$updatedValue materialized=$materializedValue"
    }
    if ($materializedValue -eq $oldMaterializationTimestamp) {
        throw 'ASSERT_FAILED: materialization timestamp was not updated'
    }
    Assert-ContainsPattern -Path $metadataPath -Pattern ('source_xpz:\s*' + [regex]::Escape($sourceXpzPath)) -Message 'source_xpz should be updated'
    Assert-ContainsPattern -Path $metadataPath -Pattern 'source_refresh_status:\s*complete' -Message 'source_refresh_status should reflect a complete package Source'
    Assert-ContainsPattern -Path $metadataPath -Pattern '\| MajorVersion \| 18 \|' -Message 'the KMW MajorVersion table should be updated'
    Assert-ContainsPattern -Path $metadataPath -Pattern '\| username \| newuser \|' -Message 'the Source username table should be updated'
    Assert-ContainsPattern -Path $metadataPath -Pattern 'custom_future_field:\s*keep-me' -Message 'frontmatter outside the sync scope should be preserved'
    Assert-ContainsPattern -Path $metadataPath -Pattern 'Auxiliary text preserved by the self-test' -Message 'an extra section outside the sync scope should be preserved'
    Assert-NotContainsPattern -Path $metadataPath -Pattern '\| username \| olduser \|' -Message 'the old username value should not remain'

    # Creating a missing file writes the read-side English template: it describes what the
    # metadata identifies and carries no import or packaging instructions.
    $newMetadataPath = Join-Path $tempRoot 'new-kb\kb-source-metadata.md'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $newMetadataPath) -Force)
    $createResult = Update-MimirKbSourceMetadataFromSync -XmlDocument $packageXml -SourceXpzPath $sourceXpzPath -MetadataPath $newMetadataPath
    if ($createResult.WriteMode -ne 'template-create') {
        throw "ASSERT_FAILED: expected WriteMode template-create | actual=$($createResult.WriteMode)"
    }
    Assert-ContainsPattern -Path $newMetadataPath -Pattern '\| username\s*\| newuser\s*\|' -Message 'the created template should carry the Source values'
    Assert-ContainsPattern -Path $newMetadataPath -Pattern '(?m)^## Usage\s*$' -Message 'the created template should have an English usage section'
    Assert-NotContainsPattern -Path $newMetadataPath -Pattern '(?m)^## Uso\b' -Message 'the created template must not carry the Portuguese usage heading'
    Assert-NotContainsPattern -Path $newMetadataPath -Pattern '(?i)import_file|\.xpz`* for import|ExportFile' -Message 'the created template must not carry import or packaging instructions'

    Write-Output 'MIMIR_SYNC_KB_METADATA_SELFTEST_OK'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
