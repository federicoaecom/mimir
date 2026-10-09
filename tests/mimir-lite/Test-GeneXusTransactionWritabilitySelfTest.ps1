#requires -Version 7.4

<#
.SYNOPSIS
    Self-test for the corpus lookups of GeneXusTransactionWritabilityCore.py.

.DESCRIPTION
    GeneXus names are case-insensitive, and a Transaction can reference an Attribute (or its
    Table) with a casing that differs from the object's own file name, for example after a
    case-only rename synced on its own. Windows file systems resolve that lookup anyway; Linux
    file systems do not. This test copies tests/fixtures/sample-kb to a temporary corpus, changes
    the casing of an Attribute file and a Table file, and asserts that:

    - the Attribute and Table lookups still find those files, and an exact-case lookup returns
      the exact file;
    - a missing name is still not found;
    - the writability classification of every Transaction is identical to the one computed over
      the unchanged corpus;
    - on a case-sensitive file system only, a name matching two files that differ only in case
      is reported as not found (ambiguous) instead of picking one, while an exact-case lookup
      still resolves.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$sampleKbRoot = Join-Path $repoRoot 'tests/fixtures/sample-kb'

# Python 3.8+ resolved the same way the KbIntelligence wrappers do it.
. (Join-Path $scriptDir 'GeneXusPythonPrerequisite.ps1')
$python = Get-GeneXusPythonExecutable
if ($null -eq $python) {
    throw (Get-GeneXusPythonNotFoundMessage)
}

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Output "[PASS] $Message"
    } else {
        Write-Output "[FAIL] $Message"
        $failures.Add($Message) | Out-Null
    }
}

function Rename-ItemCase {
    # Case-only rename through an intermediate name, which also works on case-insensitive file systems.
    param([string]$Path, [string]$NewName)
    $parent = Split-Path -Parent $Path
    $tempPath = Join-Path $parent ($NewName + '.casetmp')
    Move-Item -LiteralPath $Path -Destination $tempPath
    Move-Item -LiteralPath $tempPath -Destination (Join-Path $parent $NewName)
}

$probeSource = @'
import json
import sys
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import GeneXusTransactionWritabilityCore as core

TRANSACTION_TYPE_GUID = "1db606f2-af09-4cf9-a3b5-b481519d28f6"


def name_of(path):
    return None if path is None else path.name


def classify(corpus):
    rows = core.build_corpus_writability(corpus, TRANSACTION_TYPE_GUID)
    return sorted(
        [row["transaction_name"], row["level_name"], row["attribute_name"], row["classification"], row["reason"]]
        for row in (asdict(r) for r in rows)
    )


baseline = Path(sys.argv[2])
drifted = Path(sys.argv[3])
result = {
    "attributeDrifted": name_of(core.find_attribute_xml_path("CustomerName", drifted)),
    "attributeExact": name_of(core.find_attribute_xml_path("CustomerId", drifted)),
    "attributeMissing": name_of(core.find_attribute_xml_path("NoSuchAttribute", drifted)),
    "tableDrifted": name_of(core.find_table_xml_path("Invoice", drifted)),
    "baselineRows": classify(baseline),
    "driftedRows": classify(drifted),
}
if len(sys.argv) > 4:
    ambiguous = Path(sys.argv[4])
    result["ambiguousUpper"] = name_of(core.find_attribute_xml_path("QUANTITY", ambiguous))
    result["ambiguousExact"] = name_of(core.find_attribute_xml_path("Quantity", ambiguous))
print(json.dumps(result))
'@

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-writability-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $baselineCorpus = Join-Path $tempRoot 'baseline'
    $driftedCorpus = Join-Path $tempRoot 'drifted'
    [void](New-Item -ItemType Directory -Path $baselineCorpus, $driftedCorpus -Force)
    foreach ($folder in 'Attribute', 'Table', 'Transaction') {
        Copy-Item -LiteralPath (Join-Path $sampleKbRoot $folder) -Destination $baselineCorpus -Recurse
        Copy-Item -LiteralPath (Join-Path $sampleKbRoot $folder) -Destination $driftedCorpus -Recurse
    }
    Rename-ItemCase -Path (Join-Path $driftedCorpus 'Attribute/CustomerName.xml') -NewName 'customername.xml'
    Rename-ItemCase -Path (Join-Path $driftedCorpus 'Table/Invoice.xml') -NewName 'INVOICE.xml'

    $probeArguments = [System.Collections.Generic.List[string]]::new()
    $probePath = Join-Path $tempRoot 'probe.py'
    [System.IO.File]::WriteAllText($probePath, $probeSource, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($argument in @($python.PrefixArguments)) { $probeArguments.Add($argument) }
    foreach ($argument in @($probePath, $scriptDir, $baselineCorpus, $driftedCorpus)) { $probeArguments.Add($argument) }

    # Two files differing only in case can exist only on a case-sensitive file system.
    $caseProbe = Join-Path $tempRoot 'CaseProbe'
    [void](New-Item -ItemType File -Path $caseProbe)
    $isCaseSensitive = -not (Test-Path -LiteralPath (Join-Path $tempRoot 'caseprobe'))
    if ($isCaseSensitive) {
        $ambiguousCorpus = Join-Path $tempRoot 'ambiguous'
        [void](New-Item -ItemType Directory -Path (Join-Path $ambiguousCorpus 'Attribute') -Force)
        $quantitySource = Join-Path $sampleKbRoot 'Attribute/Quantity.xml'
        Copy-Item -LiteralPath $quantitySource -Destination (Join-Path $ambiguousCorpus 'Attribute/Quantity.xml')
        Copy-Item -LiteralPath $quantitySource -Destination (Join-Path $ambiguousCorpus 'Attribute/quantity.xml')
        $probeArguments.Add($ambiguousCorpus)
    }

    $output = & $python.Source @probeArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Python probe failed (exit $LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }
    $result = ($output -join "`n") | ConvertFrom-Json

    Assert-True -Condition ($null -ne $result.attributeDrifted -and ([string]$result.attributeDrifted).ToLowerInvariant() -eq 'customername.xml') -Message "Attribute lookup ignores file-name case (got '$($result.attributeDrifted)')"
    Assert-True -Condition ($result.attributeExact -ceq 'CustomerId.xml') -Message "Exact-case Attribute lookup returns the exact file (got '$($result.attributeExact)')"
    Assert-True -Condition ($null -eq $result.attributeMissing) -Message 'A missing Attribute is still not found'
    Assert-True -Condition ($null -ne $result.tableDrifted -and ([string]$result.tableDrifted).ToLowerInvariant() -eq 'invoice.xml') -Message "Table lookup ignores file-name case (got '$($result.tableDrifted)')"

    $baselineRows = @($result.baselineRows | ForEach-Object { $_ -join '|' })
    $driftedRows = @($result.driftedRows | ForEach-Object { $_ -join '|' })
    Assert-True -Condition ($baselineRows.Count -gt 0) -Message "The baseline corpus yields writability rows ($($baselineRows.Count))"
    $diff = @(Compare-Object -ReferenceObject $baselineRows -DifferenceObject $driftedRows -CaseSensitive)
    Assert-True -Condition ($diff.Count -eq 0) -Message ("Classification is identical over the case-drifted corpus (differences: {0})" -f (($diff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; '))

    if ($isCaseSensitive) {
        Assert-True -Condition ($null -eq $result.ambiguousUpper) -Message "Ambiguous case-insensitive match is not found (got '$($result.ambiguousUpper)')"
        Assert-True -Condition ($result.ambiguousExact -ceq 'Quantity.xml') -Message "Exact-case lookup resolves next to a case variant (got '$($result.ambiguousExact)')"
    } else {
        Write-Output '[SKIP] Ambiguous case variants need a case-sensitive file system'
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    Write-Output ("FAILED: {0} assertion(s)" -f $failures.Count)
    exit 1
}
Write-Output 'OK: Test-GeneXusTransactionWritabilitySelfTest.ps1'
exit 0
