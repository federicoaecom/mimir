#requires -Version 7.4
<#
.SYNOPSIS
Test helper: marks a synthetic corpus as completely synchronized, so the KB Intelligence builder
and query accept it.

.DESCRIPTION
Dot-source this file, then call Set-TestCorpusStateComplete -CorpusRoot <folder> before building
an index from a corpus the test wrote itself (copies of tests/fixtures/sample-kb already carry a
complete state). It writes <corpus>/.mimir-sync-state.json through Write-GeneXusCorpusSyncState
(skills/mimir-lite/scripts/GeneXusCorpusStateSupport.ps1), the writer the XPZ sync uses, with a
fixed generation unless -Generation is given; a missing folder is left as is. Python tests use tests/mimir-lite/_corpus_state_support.py.
#>

. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts/GeneXusCorpusStateSupport.ps1')

function Set-TestCorpusStateComplete {
    param(
        [Parameter(Mandatory)][string]$CorpusRoot,
        [ValidatePattern('^[0-9a-f]{32}$')][string]$Generation = '0123456789abcdef0123456789abcdef'
    )
    # A missing corpus is left missing, so a test of that case still sees the builder's own error.
    if (-not (Test-Path -LiteralPath $CorpusRoot -PathType Container)) { return }
    $root = (Resolve-Path -LiteralPath $CorpusRoot).ProviderPath
    [void](Write-GeneXusCorpusSyncState -CorpusRoot $root -State complete -PackageSha256 ('0' * 64) -Generation $Generation)
}
