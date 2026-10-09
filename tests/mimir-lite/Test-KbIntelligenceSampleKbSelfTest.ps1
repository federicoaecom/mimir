#requires -Version 7.4
<#
.SYNOPSIS
    Self-contained regression test for the KbIntelligence query engine: builds the SQLite
    index from the synthetic sample-kb fixture (tests/fixtures/sample-kb/, no real KB data)
    and runs representative query cases against it.

.DESCRIPTION
    The query-case runner (Test-KbIntelligenceQueries.ps1) needs an index and a cases file.
    This test needs no external KB or
    machine-specific path: it builds the index from the checked-in fixture into a fresh temp
    directory (also exercising Build-KbIntelligenceIndex's own relation-extraction validation
    cases via kb-intelligence-sample-kb.validation-extraction.json), then exercises
    search-objects, object-info, who-uses, what-uses and transaction-writable-attributes
    directly, plus the query-case runner (skills/mimir-lite/scripts/Test-KbIntelligenceQueries.ps1)
    against a small dedicated validation-cases file (kb-intelligence-sample-kb.validation-queries.json).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Python 3.8+ resolved once, the same way the KbIntelligence wrappers do it
# (python3, then python, then py -3).
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts/GeneXusPythonPrerequisite.ps1')
$pythonInterpreter = Get-GeneXusPythonExecutable
if ($null -eq $pythonInterpreter) {
    throw (Get-GeneXusPythonNotFoundMessage)
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
$sampleKbRoot = Join-Path $fixturesRoot 'sample-kb'

if (-not (Test-Path -LiteralPath $sampleKbRoot -PathType Container)) {
    throw "sample-kb fixture not found: $sampleKbRoot"
}

$indexScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.py'
$queriesTestScript = Join-Path $scriptDir 'Test-KbIntelligenceQueries.ps1'

foreach ($required in @($indexScript, $queryScript, $queriesTestScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required script not found: $required"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-intel-sample-kb-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

$sqlitePath = Join-Path $tempRoot 'kb-intelligence.sqlite'
$validationPath = Join-Path $tempRoot 'kb-intelligence-validation.json'
$extractionValidationCases = Join-Path $fixturesRoot 'kb-intelligence-sample-kb.validation-extraction.json'
if (-not (Test-Path -LiteralPath $extractionValidationCases -PathType Leaf)) {
    throw "sample-kb validation-extraction fixture not found: $extractionValidationCases"
}

# --- Build the index from the checked-in synthetic fixture, also exercising the
#     build-time relation extraction validation cases (idBasedOn, Formula calls,
#     Source procedure calls, for-each table navigation, Table Key/Index). ---
& $indexScript `
    -SourceRoot $sampleKbRoot `
    -OutputPath $sqlitePath `
    -ValidationReportPath $validationPath `
    -ValidationCasesPath $extractionValidationCases `
    -FailOnValidationFailure
if ($LASTEXITCODE -ne 0) {
    $buildReport = Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $failedExtractionCases = @($buildReport.cases | Where-Object { $_.status -ne 'passed' })
    throw "Build-KbIntelligenceIndex failed for sample-kb; exit $LASTEXITCODE. Failed extraction cases: $($failedExtractionCases.id -join ', ')"
}

$buildReport = Get-Content -LiteralPath $validationPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($buildReport.inventory_semantics.status -ne 'OK') {
    throw ("sample-kb inventory validation should be OK, got '{0}' ({1} mismatch(es)): {2}" -f `
        $buildReport.inventory_semantics.status, `
        $buildReport.inventory_semantics.mismatch_count, `
        ($buildReport.inventory_semantics.mismatches | ConvertTo-Json -Depth 6))
}

# --- search-objects: finds the Invoice transaction by name ---
$searchJson = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query search-objects --object-name Invoice --format json
if ($LASTEXITCODE -ne 0) {
    throw "search-objects failed; exit $LASTEXITCODE"
}
$search = $searchJson | ConvertFrom-Json
$invoiceMatches = @($search.results | Where-Object { $_.type -eq 'Transaction' -and $_.name -eq 'Invoice' })
if ($invoiceMatches.Count -lt 1) {
    throw "search-objects('Invoice') should include Transaction:Invoice; got: $($searchJson -join ' ')"
}

# --- object-info: the Invoice transaction resolves with the expected type ---
$objectInfoJson = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query object-info --object-type Transaction --object-name Invoice --format json
if ($LASTEXITCODE -ne 0) {
    throw "object-info failed; exit $LASTEXITCODE"
}
$objectInfo = $objectInfoJson | ConvertFrom-Json
if (-not $objectInfo.found) {
    throw "object-info(Transaction, Invoice) should be found"
}
if ($objectInfo.object.type -ne 'Transaction') {
    throw "object-info(Transaction, Invoice) returned unexpected type: $($objectInfo.object.type)"
}

# --- who-uses: CalculateInvoiceTotal is called by the CustomerView web panel ---
$whoUsesJson = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query who-uses --object-type Procedure --object-name CalculateInvoiceTotal --format json
if ($LASTEXITCODE -ne 0) {
    throw "who-uses failed; exit $LASTEXITCODE"
}
$whoUses = $whoUsesJson | ConvertFrom-Json
$webPanelCallers = @($whoUses.results | Where-Object {
    $_.source_type -eq 'WebPanel' -and $_.source_name -eq 'CustomerView' -and $_.relation_kind -eq 'calls_procedure'
})
if ($webPanelCallers.Count -lt 1) {
    throw "who-uses(Procedure, CalculateInvoiceTotal) should list WebPanel:CustomerView as a caller; got: $($whoUsesJson -join ' ')"
}

# --- what-uses: CustomerView calls CalculateInvoiceTotal ---
$whatUsesJson = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query what-uses --object-type WebPanel --object-name CustomerView --format json
if ($LASTEXITCODE -ne 0) {
    throw "what-uses failed; exit $LASTEXITCODE"
}
$whatUses = $whatUsesJson | ConvertFrom-Json
$procedureTargets = @($whatUses.results | Where-Object {
    $_.target_type -eq 'Procedure' -and $_.target_name -eq 'CalculateInvoiceTotal' -and $_.relation_kind -eq 'calls_procedure'
})
if ($procedureTargets.Count -lt 1) {
    throw "what-uses(WebPanel, CustomerView) should list Procedure:CalculateInvoiceTotal as a dependency; got: $($whatUsesJson -join ' ')"
}

# --- transaction-writable-attributes: key, formula and FK classification on Invoice ---
$writableJson = & $pythonInterpreter.Source @($pythonInterpreter.PrefixArguments) $queryScript --index-path $sqlitePath --query transaction-writable-attributes --object-name Invoice --format json
if ($LASTEXITCODE -ne 0) {
    throw "transaction-writable-attributes failed; exit $LASTEXITCODE"
}
$writable = $writableJson | ConvertFrom-Json
if (-not $writable.found) {
    throw "transaction-writable-attributes(Invoice) should be found"
}
$byAttribute = @{}
foreach ($row in $writable.results) {
    $byAttribute[$row.attribute] = $row
}
$expectedClassifications = @{
    InvoiceId    = @{ classification = 'key-attribute'; writable = $true }
    LineNumber   = @{ classification = 'key-attribute'; writable = $true }
    InvoiceTotal = @{ classification = 'formula'; writable = $false }
    CustomerId   = @{ classification = 'extended-fk-key'; writable = $true }
    ProductId    = @{ classification = 'extended-fk-key'; writable = $true }
    CustomerName = @{ classification = 'extended-fk-descriptive'; writable = $false }
}
foreach ($attributeName in $expectedClassifications.Keys) {
    $expected = $expectedClassifications[$attributeName]
    $row = $byAttribute[$attributeName]
    if ($null -eq $row) {
        throw "transaction-writable-attributes(Invoice) is missing attribute '$attributeName'"
    }
    if ($row.classification -ne $expected.classification -or $row.writable -ne $expected.writable) {
        throw ("transaction-writable-attributes(Invoice).{0} = classification '{1}' writable {2}; expected classification '{3}' writable {4}" -f `
            $attributeName, $row.classification, $row.writable, $expected.classification, $expected.writable)
    }
}

# --- query-case runner (Test-KbIntelligenceQueries.ps1) against the same index ---
$sampleKbValidationCases = Join-Path $fixturesRoot 'kb-intelligence-sample-kb.validation-queries.json'
if (-not (Test-Path -LiteralPath $sampleKbValidationCases -PathType Leaf)) {
    throw "sample-kb validation-queries fixture not found: $sampleKbValidationCases"
}
$queriesReportPath = Join-Path $tempRoot 'kb-intelligence-sample-kb-queries-report.json'
# The wrapper ends with `exit`, so it runs in a child pwsh process.
$queriesOutput = & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $queriesTestScript `
    -IndexPath $sqlitePath `
    -ValidationCasesPath $sampleKbValidationCases `
    -ValidationReportPath $queriesReportPath `
    -FailOnValidationFailure 2>&1
$queriesExit = $LASTEXITCODE
if ($queriesExit -ne 0) {
    $failedCases = @()
    if (Test-Path -LiteralPath $queriesReportPath -PathType Leaf) {
        $queriesReport = Get-Content -LiteralPath $queriesReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $failedCases = @($queriesReport.cases | Where-Object { $_.status -ne 'passed' })
    }
    throw "Test-KbIntelligenceQueries.ps1 failed for sample-kb; exit $queriesExit. Failed cases: $(@($failedCases | ForEach-Object { $_.id }) -join ', '). Output: $(($queriesOutput | Select-Object -Last 5) -join ' | ')"
}

Write-Output 'OK: Test-KbIntelligenceSampleKbSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit 0
