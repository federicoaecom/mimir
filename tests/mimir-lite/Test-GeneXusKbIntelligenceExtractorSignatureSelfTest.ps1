#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$contractPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'GeneXusKbIntelligenceExtractorContract.ps1'
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "GeneXusKbIntelligenceExtractorContract.ps1 not found: $contractPath"
}
. $contractPath

$expected = Get-GeneXusKbIntelligenceExpectedExtractorSignature
if ([string]::IsNullOrWhiteSpace($expected.extractor_signature_version)) {
    throw 'Expected extractor version is empty'
}
if ($expected.extractor_signature_hash.Length -ne 64) {
    throw "Expected hash should have 64 hex chars; got: $($expected.extractor_signature_hash.Length)"
}

$okResult = Test-GeneXusKbIntelligenceExtractorSignatureFromMetadata -Metadata @{
    extractor_signature_version = $expected.extractor_signature_version
    extractor_signature_hash    = $expected.extractor_signature_hash
}
if (-not $okResult.ok) {
    throw "Expected signature should pass: $($okResult.summary)"
}

$missingResult = Test-GeneXusKbIntelligenceExtractorSignatureFromMetadata -Metadata @{}
if ($missingResult.ok) {
    throw 'Empty metadata should fail'
}
if ($missingResult.reason -ne 'indice_sem_assinatura_extrator') {
    throw "incorrect reason: $($missingResult.reason)"
}

$versionResult = Test-GeneXusKbIntelligenceExtractorSignatureFromMetadata -Metadata @{
    extractor_signature_version = '0'
    extractor_signature_hash    = $expected.extractor_signature_hash
}
if ($versionResult.ok -or $versionResult.reason -ne 'extrator_version_defasada') {
    throw 'Stale version should fail with extrator_version_defasada'
}

Write-Output 'KB_INTELLIGENCE_EXTRACTOR_SIGNATURE_SELFTEST_OK'
