#requires -Version 7.4
<#
.SYNOPSIS
  Self-test for the -AsJson CONTRACT of the Test-MimirSetupAudit.ps1 engine (the shared
  setup audit behind the local Test-*KbSetupAudit.ps1 wrapper). Sentinel:
  MIMIR_SETUP_AUDIT_CONTRACT_SELFTEST_OK.

.DESCRIPTION
  Focuses on the structured contract callers consume (suggested_operational_state
  in JSON, -AsJson never throws), using temporary synthetic workspaces rather than a real KB.
    A. No PowerShell runtime wrapper -> powershell_runtime_blocked state in
       JSON, exit 1, no throw.
    B. Runtime OK (stub) but kb-source-metadata.md missing -> safety net: state
       audit_incomplete in JSON, no throw.
    C. A complete read-side workspace audits clean (materialized_and_index_validated);
       a kb-source-metadata.md field outside the metadata wrapper contract is ignored.
    D. An XPZ-only workspace synced from a GeneXus 7.0 or earlier `.xpw` export
       (source_export_format: xpw, KMW 1.x), whose KB GUID and names are missing because a
       `.xpw` carries no <Source> block: the metadata wrapper reports NOT_APPLICABLE and the
       workspace audits clean.
    E. The same for a GeneXus 7.5 to 9 classic XML export (KMW 2.x, no export-format marker).
    F. A modern export (KMW 4.x) with the same identity fields missing keeps PENDING_DATA and
       methodology_update_pending: only an export that cannot carry the identity is exempt.
    G. A legacy export whose KB GUID is present but invalid keeps PENDING_DATA: the exemption
       covers missing identity fields only.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'MimirSetupSelfTestSupport.ps1')

$engine = Join-Path $scriptsRoot 'Test-MimirSetupAudit.ps1'
$roots = [System.Collections.Generic.List[string]]::new()
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-True {
  param([bool]$Cond, [string]$Message)
  if (-not $Cond) { throw "FAILURE: $Message" }
}

function Assert-JsonDimension {
  param(
    [object]$Json,
    [string]$Key,
    [string]$Expected,
    [string]$Message
  )

  $property = $Json.PSObject.Properties[$Key]
  if ($null -eq $property) { throw "FAILURE: $Message | JSON key '$Key' is missing" }
  $actual = [string]$property.Value
  if ($actual -cne $Expected) { throw "FAILURE: $Message | expected '$Expected'; got '$actual'" }
}

function Assert-JsonValueContains {
  param(
    [object]$Json,
    [string]$Key,
    [string]$ExpectedText,
    [string]$Message
  )

  $property = $Json.PSObject.Properties[$Key]
  if ($null -eq $property) { throw "FAILURE: $Message | JSON key '$Key' is missing" }
  if ([string]$property.Value -notmatch [regex]::Escape($ExpectedText)) {
    throw "FAILURE: $Message | expected '$Key' to contain '$ExpectedText'; got '$($property.Value)'"
  }
}

function ConvertTo-PowerShellSingleQuotedLiteral {
  param([string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function New-SetupAuditFixture {
  param(
    [string]$Slug,
    [switch]$IncludeUnknownMetadataField,
    # complete | xpw-missing | classic-xml-missing | modern-missing | xpw-invalid-guid
    [string]$Identity = 'complete'
  )

  $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mimir-setupaudit-{0}-{1}" -f $Slug, ([guid]::NewGuid().ToString('N')))
  $kbRoot = Join-Path $fixtureRoot 'Demo'
  $scriptsPath = Join-Path $kbRoot 'scripts'
  $objectsPath = Join-Path $kbRoot 'KbObjectsXml\Attribute'
  $indexPath = Join-Path $kbRoot 'KbIntelligence'
  [void](New-Item -ItemType Directory -Path $scriptsPath -Force)
  [void](New-Item -ItemType Directory -Path $objectsPath -Force)
  [void](New-Item -ItemType Directory -Path $indexPath -Force)

  # Copy every canonical local wrapper so the real inventory audit sees a complete,
  # otherwise-clean synthetic workspace. The engines are not invoked by this copy.
  $examplesPath = Join-Path $repoRoot 'skills/mimir-lite/workflows/setup/examples'
  foreach ($example in Get-ChildItem -LiteralPath $examplesPath -File -Filter '*.example.ps1' | Sort-Object Name) {
    $baseName = $example.Name -replace '\.example\.ps1$', ''
    if ($baseName -match '^([A-Za-z]+-)Kb(.+)$') {
      $localName = '{0}DemoKb{1}.ps1' -f $Matches[1], $Matches[2]
    } else {
      $localName = "$baseName.ps1"
    }
    Copy-Item -LiteralPath $example.FullName -Destination (Join-Path $scriptsPath $localName)
  }

  $timestamp = '2026-01-01T00:00:00Z'
  $metadataLines = @(
    "last_xpz_materialization_run_at: $timestamp"
    'kb_name: Demo'
    'source_guid: 11111111-1111-1111-1111-111111111111'
    '## Source'
    '| field | value |'
    '| kb (GUID) | 11111111-1111-1111-1111-111111111111 |'
    '## Source/Version'
    '| field | value |'
    '| name | Demo |'
    '| guid | 22222222-2222-2222-2222-222222222222 |'
  )
  if ($Identity -ne 'complete') {
    # The KB GUID and names left empty, as a sync from an export without a <Source> block
    # leaves them, with the export's KMW block and format marker.
    $kbGuidCell = if ($Identity -eq 'xpw-invalid-guid') { 'not-a-guid' } else { '' }
    $major, $marker = switch ($Identity) {
      'xpw-missing' { '1', 'source_export_format: xpw' }
      'xpw-invalid-guid' { '1', 'source_export_format: xpw' }
      'classic-xml-missing' { '2', $null }
      'modern-missing' { '4', $null }
    }
    $metadataLines = @(
      "last_xpz_materialization_run_at: $timestamp"
      'source_refresh_status: partial-new'
    ) + @($marker | Where-Object { $_ }) + @(
      '## KMW'
      '| Field | Value |'
      '|---|---|'
      "| MajorVersion | $major |"
      '| MinorVersion | 4 |'
      '## Source'
      '| field | value |'
      "| kb (GUID) | $kbGuidCell |"
      '## Source/Version'
      '| field | value |'
      '| name |  |'
      '| guid |  |'
    )
  }
  if ($IncludeUnknownMetadataField) {
    $metadataLines += @('custom_local_field: keep-me')
  }
  [System.IO.File]::WriteAllText((Join-Path $kbRoot 'kb-source-metadata.md'), ($metadataLines -join "`n"), $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $objectsPath 'CustomerId.xml'), '<Attribute />', $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $indexPath 'kb-intelligence.sqlite'), '', $utf8NoBom)

  $runtimePath = Join-Path $fixtureRoot 'runtime-ok.ps1'
  [System.IO.File]::WriteAllText($runtimePath, "'POWERSHELL_RUNTIME_OK'`n", $utf8NoBom)

  # Use the actual metadata wrapper contract with a synthetic local reader exposing
  # the same metadata values; this keeps the fixture independent of a real KB.
  $metadataReaderPath = Join-Path $scriptsPath 'Get-DemoKbMetadata.ps1'
  $metadataReader = @'
#requires -Version 7.4
param([string]$MetadataPath)
$lines = [System.IO.File]::ReadAllLines($MetadataPath)
foreach ($field in @('last_xpz_materialization_run_at', 'kb_name', 'source_guid')) {
  $pattern = '^\s*{0}\s*[:=]\s*(?<value>.+?)\s*$' -f [regex]::Escape($field)
  foreach ($line in $lines) {
    $match = [regex]::Match($line, $pattern)
    if ($match.Success) {
      '{0}: {1}' -f $field, $match.Groups['value'].Value.Trim()
      break
    }
  }
}
'@
  [System.IO.File]::WriteAllText($metadataReaderPath, $metadataReader, $utf8NoBom)

  $metadataEngine = Join-Path $scriptsRoot 'Test-MimirKbMetadataWrapper.ps1'
  $metadataCheckPath = Join-Path $fixtureRoot 'metadata-wrapper-check.ps1'
  $metadataCheck = @"
& $(ConvertTo-PowerShellSingleQuotedLiteral $metadataEngine) -MetadataPath $(ConvertTo-PowerShellSingleQuotedLiteral (Join-Path $kbRoot 'kb-source-metadata.md')) -WrapperPath $(ConvertTo-PowerShellSingleQuotedLiteral $metadataReaderPath)
"@
  [System.IO.File]::WriteAllText($metadataCheckPath, $metadataCheck, $utf8NoBom)

  # Supply a structurally valid synthetic index to the real index-gate engine. The
  # query stub carries the current extractor signature, freshness, and semantic OK.
  $signatureContractPath = Join-Path $scriptsRoot 'GeneXusKbIntelligenceExtractorContract.ps1'
  . $signatureContractPath
  $signature = Get-GeneXusKbIntelligenceExpectedExtractorSignature
  $queryPath = Join-Path $fixtureRoot 'query-index-metadata.ps1'
  $queryContent = @"
param([string]`$Query, [string]`$Format)
if (`$Query -ne 'index-metadata' -or `$Format -ne 'text') { throw 'Unexpected query for the synthetic index gate.' }
'last_index_build_run_at: $timestamp'
'inventory_validation_status: OK'
'extractor_signature_version: $($signature.extractor_signature_version)'
'extractor_signature_hash: $($signature.extractor_signature_hash)'
"@
  [System.IO.File]::WriteAllText($queryPath, $queryContent, $utf8NoBom)

  $structurePath = Join-Path $fixtureRoot 'structure-ok.ps1'
  [System.IO.File]::WriteAllText($structurePath, "'STRUCTURE_OK'`n", $utf8NoBom)

  $gatePath = Join-Path $fixtureRoot 'index-gate.ps1'
  $gateEngine = Join-Path $scriptsRoot 'Test-MimirKbIndexGate.ps1'
  $gateContent = @"
& $(ConvertTo-PowerShellSingleQuotedLiteral $gateEngine) -RepoRoot $(ConvertTo-PowerShellSingleQuotedLiteral $kbRoot) -QueryWrapperPath $(ConvertTo-PowerShellSingleQuotedLiteral $queryPath) -StructureWrapperPath $(ConvertTo-PowerShellSingleQuotedLiteral $structurePath)
"@
  [System.IO.File]::WriteAllText($gatePath, $gateContent, $utf8NoBom)

  return [pscustomobject]@{
    Root = $fixtureRoot
    KbRoot = $kbRoot
    GateWrapper = $gatePath
    MetadataWrapper = $metadataCheckPath
    RuntimeWrapper = $runtimePath
  }
}

function Invoke-SetupAuditFixture {
  param([object]$Fixture)

  return Invoke-MimirSelfTestScript -ScriptPath $engine -ScriptArgs @(
    '-KbRoot', $Fixture.KbRoot,
    '-GateWrapperPath', $Fixture.GateWrapper,
    '-MetadataWrapperTestPath', $Fixture.MetadataWrapper,
    '-PowerShellRuntimeTestPath', $Fixture.RuntimeWrapper,
    '-AsJson'
  )
}

try {
  # --- A: runtime missing -> powershell_runtime_blocked ---
  $a = Join-Path ([System.IO.Path]::GetTempPath()) ("mimir-setupaudit-a-{0}" -f ([guid]::NewGuid().ToString('N')))
  [void](New-Item -ItemType Directory -Path $a -Force); $roots.Add($a)
  $ra = Invoke-MimirSelfTestScript -ScriptPath $engine -ScriptArgs @(
    '-KbRoot', $a, '-GateWrapperPath', 'dummy', '-MetadataWrapperTestPath', 'dummy', '-AsJson')
  Assert-True ($ra.exit -eq 1) "A: exit 1 expected; got $($ra.exit)"
  Assert-True ($null -ne $ra.json) "A: stdout should be parseable JSON (-AsJson never throws)"
  Assert-True ($ra.json.suggested_operational_state -eq 'powershell_runtime_blocked') "A: state powershell_runtime_blocked expected; got $($ra.json.suggested_operational_state)"

  # --- B: runtime OK (stub) but metadata missing -> audit_incomplete ---
  $b = Join-Path ([System.IO.Path]::GetTempPath()) ("mimir-setupaudit-b-{0}" -f ([guid]::NewGuid().ToString('N')))
  [void](New-Item -ItemType Directory -Path $b -Force); $roots.Add($b)
  $runtimeStub = Join-Path $b 'runtime-ok.ps1'
  [System.IO.File]::WriteAllText($runtimeStub, "'POWERSHELL_RUNTIME_OK'`n", $utf8NoBom)
  $rb = Invoke-MimirSelfTestScript -ScriptPath $engine -ScriptArgs @(
    '-KbRoot', $b, '-GateWrapperPath', 'dummy', '-MetadataWrapperTestPath', 'dummy',
    '-PowerShellRuntimeTestPath', $runtimeStub, '-AsJson')
  Assert-True ($null -ne $rb.json) "B: stdout should be parseable JSON (safety net -AsJson never throws)"
  Assert-True ($rb.json.suggested_operational_state -eq 'audit_incomplete') "B: state audit_incomplete expected; got $($rb.json.suggested_operational_state)"

  $cleanState = 'materialized_and_index_validated'

  # --- C: a complete read-side workspace audits clean; an unknown metadata field is ignored ---
  $c = New-SetupAuditFixture -Slug 'clean-workspace' -IncludeUnknownMetadataField
  $roots.Add($c.Root)
  $rc = Invoke-SetupAuditFixture -Fixture $c
  Assert-True ($rc.exit -eq 0) "C: expected a successful audit process; got $($rc.exit): $($rc.stdout)"
  Assert-True ($null -ne $rc.json) 'C: stdout should be parseable JSON'
  Assert-JsonDimension $rc.json 'powershell/runtime' 'OK' 'C runtime dimension'
  Assert-JsonDimension $rc.json 'sync/materialization' 'OK' 'C materialization dimension'
  Assert-JsonDimension $rc.json 'naming/kb-objects' 'OK' 'C naming dimension'
  Assert-JsonDimension $rc.json 'index/gate' 'OK' 'C index gate dimension'
  Assert-JsonDimension $rc.json 'index/semantics' 'OK' 'C index semantic dimension'
  Assert-JsonDimension $rc.json 'metadata wrapper' 'OK' 'C metadata wrapper ignores a field outside its contract'
  Assert-JsonDimension $rc.json 'declarative/timestamps' 'OK' 'C declarative timestamp dimension'
  Assert-JsonDimension $rc.json 'wrappers/inventory' 'INVENTORY_OK' 'C wrapper inventory is clean'
  Assert-JsonDimension $rc.json 'suggested_operational_state' $cleanState 'C operational state'

  # --- D to G: identity fields missing from the metadata ---
  $identityCases = @(
    [pscustomobject]@{ Label = 'D'; Identity = 'xpw-missing'; Wrapper = 'NOT_APPLICABLE'; State = $cleanState; Evidence = 'carries no KB identity' },
    [pscustomobject]@{ Label = 'E'; Identity = 'classic-xml-missing'; Wrapper = 'NOT_APPLICABLE'; State = $cleanState; Evidence = 'carries no KB identity' },
    [pscustomobject]@{ Label = 'F'; Identity = 'modern-missing'; Wrapper = 'PENDING_DATA'; State = 'methodology_update_pending'; Evidence = 'kbGuid missing' },
    [pscustomobject]@{ Label = 'G'; Identity = 'xpw-invalid-guid'; Wrapper = 'PENDING_DATA'; State = 'methodology_update_pending'; Evidence = 'kbGuid invalid' }
  )
  foreach ($case in $identityCases) {
    $fixture = New-SetupAuditFixture -Slug $case.Identity -Identity $case.Identity
    $roots.Add($fixture.Root)
    $result = Invoke-SetupAuditFixture -Fixture $fixture
    Assert-True ($null -ne $result.json) "$($case.Label): stdout should be parseable JSON; got $($result.stdout)"
    Assert-JsonDimension $result.json 'metadata wrapper' $case.Wrapper "$($case.Label) ($($case.Identity)) metadata wrapper"
    Assert-JsonDimension $result.json 'suggested_operational_state' $case.State "$($case.Label) ($($case.Identity)) operational state"
    Assert-JsonValueContains $result.json 'metadata wrapper.evidence' $case.Evidence "$($case.Label) ($($case.Identity)) evidence"
  }

  'MIMIR_SETUP_AUDIT_CONTRACT_SELFTEST_OK'
}
finally {
  foreach ($r in $roots) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
}

exit 0
