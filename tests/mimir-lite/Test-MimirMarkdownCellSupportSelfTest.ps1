#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Join-Path $PSScriptRoot '../..'
$scripts = Join-Path $repo 'skills/mimir-lite/scripts'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('mimir-cell-' + [guid]::NewGuid().ToString('N'))

function Invoke-Generator([string[]]$CommandArguments) {
    $start = [Diagnostics.ProcessStartInfo]::new('pwsh')
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File') + $CommandArguments) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0 -or $stderr.Result -cne '') {
            throw "Generator failed: $($CommandArguments[0]); exit=$($process.ExitCode); stdout=$($stdout.Result); stderr=$($stderr.Result)"
        }
    } finally {
        $process.Dispose()
    }
}

try {
    $corpus = Join-Path $temp 'corpus'
    $sample = Join-Path $repo 'tests/fixtures/sample-kb'
    [void][IO.Directory]::CreateDirectory($corpus)
    Get-ChildItem -LiteralPath $sample -Force | Copy-Item -Destination $corpus -Recurse
    $transaction = Join-Path $corpus 'Transaction'
    $xml = [xml][IO.File]::ReadAllText((Join-Path $transaction 'Invoice.xml'))
    $nameWithTab = "Before`tAfter"
    # A literal tab in an XML attribute is normalized to a space when parsed.
    $xml.DocumentElement.SetAttribute('name', '__MIMIR_TAB_TEST_NAME__')
    $xml.DocumentElement.SetAttribute('guid', '11111111-1111-1111-1111-111111111111')
    $part = $xml.CreateElement('Part')
    $part.SetAttribute('type', 'FormattingFixture')
    $part.InnerXml = '<Source>synthetic formatting example</Source>'
    [void]$xml.DocumentElement.AppendChild($part)
    $fixture = Join-Path $transaction '00-TabExample.xml'
    $fixtureXml = $xml.OuterXml.Replace('name="__MIMIR_TAB_TEST_NAME__"', 'name="Before&#x9;After"')
    [IO.File]::WriteAllText($fixture, $fixtureXml, [Text.UTF8Encoding]::new($false))
    $roundTrip = [xml][IO.File]::ReadAllText($fixture)
    if ($roundTrip.DocumentElement.GetAttribute('name') -cne $nameWithTab) {
        throw 'Fixture lost its internal tab before generation.'
    }

    $inventory = Join-Path $temp 'inventory.md'
    $advanced = Join-Path $temp 'advanced'
    Invoke-Generator @((Join-Path $scripts 'generate-kb-inventory.ps1'), '-SourceRoot', $corpus, '-OutputPath', $inventory)
    Invoke-Generator @((Join-Path $scripts 'generate-kb-advanced-docs.ps1'), '-SourceRoot', $corpus, '-OutputRoot', $advanced)
    $inventoryText = [IO.File]::ReadAllText($inventory)
    if (-not $inventoryText.Contains('| Before After |') -or $inventoryText.Contains($nameWithTab)) {
        throw 'The inventory object-name cell must replace the internal tab with one space.'
    }
    $matrix = [IO.File]::ReadAllText((Join-Path $advanced '10-part-type-matrix-by-type.md'))
    if (-not $matrix.Contains($nameWithTab) -or $matrix.Contains('Before After')) {
        throw 'Advanced documentation examples must preserve the internal tab.'
    }

    . (Join-Path $scripts 'MimirMarkdownCellSupport.ps1')
    $cases = @(
        @{ Value = $null; Inventory = ''; Advanced = '' }
        @{ Value = ' trimmed '; Inventory = 'trimmed'; Advanced = 'trimmed' }
        @{ Value = "a`tb"; Inventory = 'a b'; Advanced = "a`tb" }
        @{ Value = "a`r`nb`nc"; Inventory = 'a<br/>b<br/>c'; Advanced = 'a<br/>b<br/>c' }
        @{ Value = 'left|right'; Inventory = 'left\|right'; Advanced = 'left\|right' }
        @{ Value = 42; Inventory = '42'; Advanced = '42' }
    )
    foreach ($case in $cases) {
        $inventoryValue = Format-MdCell $case.Value -ReplaceTabs
        $advancedValue = Format-MdCell $case.Value
        if ($inventoryValue -isnot [string] -or $advancedValue -isnot [string] -or
            $inventoryValue -cne $case.Inventory -or $advancedValue -cne $case.Advanced) {
            throw 'Shared formatter changed one of the two cell policies.'
        }
    }
    Write-Output 'PASS: 12 cell assertions and 2 public rendering cases'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
