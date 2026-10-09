#requires -Version 7.4

<#
.SYNOPSIS
    Self-test for generate-kb-inventory.ps1 over the synthetic sample-kb fixture.

.DESCRIPTION
    Copies tests/fixtures/sample-kb to a temporary corpus and runs the inventory generator
    with an absolute and with a relative -SourceRoot. In both runs the object types (the
    first folder of each relative path) must be the fixture's type folders that hold /Object
    or /Attribute XML, with no path separator in them, and relative paths must not start with
    a separator. Attribute XML (an <Attribute> root) is a record, not a problem file; an XML
    with any other root is still reported as a problem file.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$generatorScript = Join-Path $repoRoot 'skills/mimir-lite/scripts/generate-kb-inventory.ps1'
$sampleKbRoot = Join-Path $repoRoot 'tests/fixtures/sample-kb'
$failures = [System.Collections.Generic.List[string]]::new()

function Get-MarkdownSectionRows {
    # Returns the data rows (cells arrays) of the first table after the given heading line.
    param([string]$Content, [string]$Heading)
    $lines = $Content -split "`r?`n"
    $start = [Array]::IndexOf($lines, $Heading)
    if ($start -lt 0) { return @() }
    $rows = [System.Collections.Generic.List[object]]::new()
    $inTable = $false
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*\|') {
            $inTable = $true
            if ($line -match '^\s*\|\s*:?-{3,}') { continue }
            $rows.Add(@($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })) | Out-Null
            continue
        }
        if ($inTable) { break }
    }
    # Drop the header row.
    if ($rows.Count -gt 0) { $rows.RemoveAt(0) }
    return $rows.ToArray()
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-inventory-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    if (-not (Test-Path -LiteralPath $generatorScript -PathType Leaf)) {
        throw "Inventory generator not found: $generatorScript"
    }
    $sourceRoot = Join-Path $tempRoot 'corpus'
    [void](New-Item -ItemType Directory -Path $sourceRoot -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $sourceRoot -Recurse
    # One XML with an unexpected root: the only expected problem file.
    $junkDir = Join-Path $sourceRoot 'Junk'
    [void](New-Item -ItemType Directory -Path $junkDir -Force)
    [System.IO.File]::WriteAllText((Join-Path $junkDir 'NotAnObject.xml'), '<Foo name="NotAnObject" />', [System.Text.UTF8Encoding]::new($false))
    $expectedProblemPath = Join-Path 'Junk' 'NotAnObject.xml'

    # Object types are the folders holding at least one /Object or /Attribute XML.
    $expectedTypes = @(Get-ChildItem -LiteralPath $sourceRoot -Directory | Where-Object {
            @(Get-ChildItem -LiteralPath $_.FullName -File -Filter '*.xml' | Where-Object {
                    $xml = [System.Xml.XmlDocument]::new(); $xml.Load($_.FullName); $null -ne $xml.SelectSingleNode('/Object | /Attribute')
                }).Count -gt 0
        } | ForEach-Object { $_.Name } | Sort-Object)
    if ($expectedTypes -notcontains 'Attribute') {
        throw "Synthetic corpus must hold Attribute XML for this test: $sourceRoot"
    }
    if ($expectedTypes.Count -eq 0) {
        throw "Synthetic corpus has no type folders: $sourceRoot"
    }
    $expectedInvoicePath = Join-Path 'Transaction' 'Invoice.xml'

    $runs = @(
        @{ Name = 'absolute SourceRoot'; SourceRoot = $sourceRoot; OutputPath = (Join-Path $tempRoot 'absolute/inventory.md') }
        @{ Name = 'relative SourceRoot'; SourceRoot = 'corpus'; OutputPath = (Join-Path $tempRoot 'relative/inventory.md') }
    )
    foreach ($run in $runs) {
        Push-Location -LiteralPath $tempRoot
        try {
            $output = @(& pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $generatorScript -SourceRoot $run.SourceRoot -OutputPath $run.OutputPath 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($exitCode -ne 0) {
            $failures.Add("$($run.Name): generator exited $exitCode. Output: $($output -join "`n")") | Out-Null
            continue
        }
        $content = Get-Content -LiteralPath $run.OutputPath -Raw -Encoding UTF8

        $typeRows = @(Get-MarkdownSectionRows -Content $content -Heading '## Object Types')
        $actualTypes = @($typeRows | ForEach-Object { $_[0] } | Sort-Object -Unique)
        if (($actualTypes -join ',') -ne ($expectedTypes -join ',')) {
            $failures.Add(("{0}: object types [{1}]; expected [{2}]." -f $run.Name, ($actualTypes -join ', '), ($expectedTypes -join ', '))) | Out-Null
        }

        $fileRows = @(Get-MarkdownSectionRows -Content $content -Heading '### File list')
        if ($fileRows.Count -eq 0) {
            $failures.Add("$($run.Name): file list is empty.") | Out-Null
        }
        foreach ($row in $fileRows) {
            if ($row[0] -match '^[\\/]') {
                $failures.Add("$($run.Name): relative path starts with a separator: '$($row[0])'") | Out-Null
            }
            if ($row[2] -match '[\\/]') {
                $failures.Add("$($run.Name): folder type carries a separator: '$($row[2])'") | Out-Null
            }
        }
        $problemRows = @(Get-MarkdownSectionRows -Content $content -Heading '## Problem Files')
        $problemPaths = @($problemRows | ForEach-Object { $_[0] })
        if ($problemPaths.Count -ne 1 -or $problemPaths[0] -ne $expectedProblemPath) {
            $failures.Add(("{0}: problem files [{1}]; expected only [{2}] (Attribute XML is not a problem)." -f $run.Name, ($problemPaths -join ', '), $expectedProblemPath)) | Out-Null
        }

        $invoiceRows = @($fileRows | Where-Object { $_[3] -eq 'Invoice' -and $_[2] -eq 'Transaction' })
        if ($invoiceRows.Count -ne 1 -or $invoiceRows[0][0] -ne $expectedInvoicePath) {
            $failures.Add(("{0}: Transaction Invoice row not found with relative path '{1}'." -f $run.Name, $expectedInvoicePath)) | Out-Null
        }
    }

    if ($failures.Count -gt 0) {
        throw "Inventory generator contract failed:`n - $($failures -join "`n - ")"
    }
    Write-Output 'OK: Test-GenerateKbInventorySelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
