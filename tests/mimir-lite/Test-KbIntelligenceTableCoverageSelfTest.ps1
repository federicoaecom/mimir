#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: reverse answers for a Table target disclose the navigation the index cannot see
    (coverage scope table_navigation, field implicit_navigation_source_types).

.DESCRIPTION
    A table is navigated without an extracted relation by a grid or form (Web Panel, Work Panel,
    Transaction, a Work With or Smart Devices Panel pattern) and by a for each or Data Provider
    group that names no table. Builds two indexes from copies of the synthetic sample-kb fixture
    (tests/fixtures/sample-kb/, no real KB data):

      - corpus A: the fixture as checked in (one Panel, one Procedure, three Transactions, one
        Web Panel, three Tables);
      - corpus B: only its Attribute and Table folders.

    Proves that:
      - who-uses and impact-basic of Table Invoice on corpus A report scope table_navigation,
        complete false, implicit_navigation_source_types
        Panel=1;Procedure=1;Transaction=3;WebPanel=1, no type twice (Panel is not also listed as an
        unextracted call source), and a text note naming those types;
      - a lowercase 'table' object type gets the same scope;
      - who-uses of Procedure CalculateInvoiceTotal keeps scope calls with an empty
        implicit_navigation_source_types;
      - who-uses of Table Invoice on corpus B (no type that can navigate a table) is complete,
        with no note line.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$sampleKbRoot = Join-Path $repoRoot 'tests/fixtures/sample-kb'
$buildScript = Join-Path $scriptDir 'Build-KbIntelligenceIndex.ps1'
$queryScript = Join-Path $scriptDir 'Query-KbIntelligenceIndex.ps1'
$expectedImplicit = 'Panel=1;Procedure=1;Transaction=3;WebPanel=1'
$expectedNoteSegment = 'navigation that names no table is not extracted from Panel (1), Procedure (1), Transaction (3), WebPanel (1)'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { $failures.Add($Message) }

function Invoke-Query {
    param([string]$IndexPath, [hashtable]$Arguments)
    $output = & $queryScript -IndexPath $IndexPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Query failed (exit $LASTEXITCODE) for $($Arguments.Values -join ' '): $(@($output) -join "`n")"
    }
    return (@($output) -join "`n")
}

function Format-Entries($Entries) {
    return (@($Entries | ForEach-Object { '{0}={1}' -f $_.type, $_.count }) -join ';')
}

function New-Index([string]$Name, [string[]]$Folders) {
    $corpus = Join-Path $tempRoot "$Name/KbObjectsXml"
    [void](New-Item -ItemType Directory -Path $corpus -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Directory | Where-Object { -not $Folders -or $Folders -contains $_.Name } |
        Copy-Item -Destination $corpus -Recurse
    $indexPath = Join-Path $tempRoot "$Name/index.sqlite"
    & $buildScript -SourceRoot $corpus -OutputPath $indexPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Build-KbIntelligenceIndex failed for $Name; exit $LASTEXITCODE" }
    return $indexPath
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-table-coverage-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $indexA = New-Index -Name 'a' -Folders @()
    $indexB = New-Index -Name 'b' -Folders @('Attribute', 'Table')

    foreach ($case in @(
            [pscustomobject]@{ Query = 'who-uses'; Type = 'Table' },
            [pscustomobject]@{ Query = 'impact-basic'; Type = 'Table' },
            [pscustomobject]@{ Query = 'who-uses'; Type = 'table' }
        )) {
        $label = "$($case.Query)/$($case.Type):Invoice/A"
        $payload = (Invoke-Query -IndexPath $indexA -Arguments @{ Query = $case.Query; ObjectType = $case.Type; ObjectName = 'Invoice'; Format = 'json' }) | ConvertFrom-Json
        $coverage = $payload.coverage
        if ($coverage.scope -cne 'table_navigation') { Add-Failure "[$label] scope should be table_navigation; got '$($coverage.scope)'" }
        if ($coverage.complete -ne $false) { Add-Failure "[$label] complete should be false; got $($coverage.complete)" }
        $implicit = if ($null -ne $coverage.PSObject.Properties['implicit_navigation_source_types']) { Format-Entries $coverage.implicit_navigation_source_types } else { '<missing>' }
        if ($implicit -cne $expectedImplicit) { Add-Failure "[$label] implicit_navigation_source_types should be '$expectedImplicit'; got '$implicit'" }
        $unextracted = @($coverage.unextracted_source_types | ForEach-Object { $_.type })
        if ($unextracted -contains 'Panel') { Add-Failure "[$label] Panel should not be listed twice (unextracted and implicit); got unextracted '$($unextracted -join ',')'" }
        if ($case.Type -ceq 'Table') {
            $text = Invoke-Query -IndexPath $indexA -Arguments @{ Query = $case.Query; ObjectType = $case.Type; ObjectName = 'Invoice'; Format = 'text' }
            $note = @($text -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -match '^coverage:' })
            if ($note.Count -ne 1 -or -not $note[0].Contains($expectedNoteSegment)) {
                Add-Failure "[$label/text] the note should contain '$expectedNoteSegment'; got '$($note -join ' | ')'"
            }
        }
    }

    $payload = (Invoke-Query -IndexPath $indexA -Arguments @{ Query = 'who-uses'; ObjectType = 'Procedure'; ObjectName = 'CalculateInvoiceTotal'; Format = 'json' }) | ConvertFrom-Json
    if ($payload.coverage.scope -cne 'calls') { Add-Failure "[who-uses/Procedure/A] scope should stay calls; got '$($payload.coverage.scope)'" }
    if ($null -eq $payload.coverage.PSObject.Properties['implicit_navigation_source_types'] -or @($payload.coverage.implicit_navigation_source_types).Count -ne 0) {
        Add-Failure "[who-uses/Procedure/A] implicit_navigation_source_types should be present and empty; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)"
    }

    $payload = (Invoke-Query -IndexPath $indexB -Arguments @{ Query = 'who-uses'; ObjectType = 'Table'; ObjectName = 'Invoice'; Format = 'json' }) | ConvertFrom-Json
    if ($payload.coverage.complete -ne $true) { Add-Failure "[who-uses/Table:Invoice/B] coverage should be complete with no navigating type; got $($payload.coverage | ConvertTo-Json -Compress -Depth 4)" }
    $text = Invoke-Query -IndexPath $indexB -Arguments @{ Query = 'who-uses'; ObjectType = 'Table'; ObjectName = 'Invoice'; Format = 'text' }
    if (@($text -split "`n" | Where-Object { $_ -match '^coverage:' }).Count -ne 0) { Add-Failure "[who-uses/Table:Invoice/B/text] no coverage note expected; got: $text" }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($failures.Count -gt 0) {
    throw ("Test-KbIntelligenceTableCoverageSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-KbIntelligenceTableCoverageSelfTest.ps1'
exit 0
