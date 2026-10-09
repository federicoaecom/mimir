#requires -Version 7.4
<#
.SYNOPSIS
    Locks down EOL and Markdown-fence formatting for Update-MimirDocSection.ps1.

.DESCRIPTION
    Runs the updater through pwsh -File against synthetic LF and CRLF Markdown
    targets and well-formed XML containing a standalone three-backtick CDATA line.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptDir = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$updaterScriptPath = Join-Path $scriptDir 'Update-MimirDocSection.ps1'
$utf8NoBomEncodingSupportPath = Join-Path $scriptDir 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $updaterScriptPath -PathType Leaf)) {
    throw "Update-MimirDocSection.ps1 not found: $updaterScriptPath"
}
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$failures = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-doc-section-formatting-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

function Add-FormattingAssertion {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Passed) {
        $script:failures.Add($Message) | Out-Null
    }
}

function Get-EolStatistics {
    param([Parameter(Mandatory = $true)][string]$Content)

    return [pscustomobject]@{
        CrLf = [regex]::Matches($Content, "`r`n").Count
        BareCr = [regex]::Matches($Content, "`r(?!`n)").Count
        BareLf = [regex]::Matches($Content, "(?<!`r)`n").Count
    }
}

function New-FormattingFixture {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Eol
    )

    $caseRoot = Join-Path $RootPath $Name
    [void](New-Item -ItemType Directory -Path $caseRoot -Force)
    $targetPath = Join-Path $caseRoot 'guide.md'
    $xmlPath = Join-Path $caseRoot 'example.xml'

    $targetLines = @(
        '# Synthetic guide'
        ''
        '## Generated examples'
        ''
        'Old generated content must be replaced.'
        ''
        '## Next'
        ''
        'This following section must remain intact.'
        ''
    )
    $targetContent = $targetLines -join $Eol

    $xmlLines = @(
        '<Example>'
        '  <Payload><![CDATA['
        'content before the Markdown marker'
        '```'
        'content after the Markdown marker'
        ']]></Payload>'
        '</Example>'
    )
    $xmlContent = $xmlLines -join $Eol
    try {
        $xmlDocument = [System.Xml.XmlDocument]::new()
        $xmlDocument.LoadXml($xmlContent)
    } catch {
        throw "Synthetic XML fixture is not well-formed ($Name): $($_.Exception.Message)"
    }
    $standaloneBacktickLine = $Eol + '```' + $Eol
    if (-not $xmlContent.Contains($standaloneBacktickLine)) {
        throw "Synthetic XML fixture is missing a standalone three-backtick line ($Name)."
    }

    $utf8NoBom = Get-Utf8NoBomEncoding
    [System.IO.File]::WriteAllText($targetPath, $targetContent, $utf8NoBom)
    [System.IO.File]::WriteAllText($xmlPath, $xmlContent, $utf8NoBom)

    $targetEolStatistics = Get-EolStatistics -Content ([System.IO.File]::ReadAllText($targetPath))
    if (($Eol -eq "`n" -and ($targetEolStatistics.CrLf -ne 0 -or $targetEolStatistics.BareCr -ne 0)) -or
        ($Eol -eq "`r`n" -and ($targetEolStatistics.BareLf -ne 0 -or $targetEolStatistics.BareCr -ne 0))) {
        throw "Synthetic Markdown fixture did not retain its requested $Name EOL."
    }

    return [pscustomobject]@{
        Name = $Name
        Eol = $Eol
        TargetPath = $targetPath
        XmlPath = $xmlPath
        XmlContent = $xmlContent
    }
}

function Invoke-AndCheckFormattingFixture {
    param([Parameter(Mandatory = $true)][pscustomobject]$Fixture)

    $arguments = @(
        '-TargetMarkdown', $Fixture.TargetPath,
        '-SectionTitle', '## Generated examples',
        '-XmlExamplePaths', $Fixture.XmlPath,
        '-CodeFenceLanguage', 'xml'
    )
    $updaterOutput = @(
        & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $updaterScriptPath @arguments 2>&1
    )
    $updaterExitCode = $LASTEXITCODE
    if ($updaterExitCode -ne 0) {
        throw "BLOCKER: updater did not process valid $($Fixture.Name) fixture; exit=$updaterExitCode output=$($updaterOutput -join ' | ')"
    }

    $targetBytes = [System.IO.File]::ReadAllBytes($Fixture.TargetPath)
    $hasUtf8Bom = $targetBytes.Length -ge 3 -and
        $targetBytes[0] -eq 0xEF -and $targetBytes[1] -eq 0xBB -and $targetBytes[2] -eq 0xBF
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $updatedContent = $strictUtf8.GetString($targetBytes)
    } catch {
        Add-FormattingAssertion -Passed $false -Message "$($Fixture.Name): generated Markdown must be valid UTF-8 without a BOM (invalid UTF-8 bytes)."
        $updatedContent = [System.Text.Encoding]::UTF8.GetString($targetBytes)
    }

    if (-not $updatedContent.Contains('<Example>') -or
        $updatedContent.Contains('Old generated content must be replaced.')) {
        throw "BLOCKER: updater exited successfully but did not recompose the target section for $($Fixture.Name)."
    }
    Write-Output "FIXTURE_VALID_AND_PROCESSED: $($Fixture.Name) XML parsed; updater exited 0 and replaced the prior section."

    Add-FormattingAssertion -Passed (-not $hasUtf8Bom) -Message "$($Fixture.Name): generated Markdown must be UTF-8 without a BOM."

    $eolStatistics = Get-EolStatistics -Content $updatedContent
    $hasOnlyExpectedEol = if ($Fixture.Eol -eq "`n") {
        $eolStatistics.CrLf -eq 0 -and $eolStatistics.BareCr -eq 0 -and $eolStatistics.BareLf -gt 0
    } else {
        $eolStatistics.CrLf -gt 0 -and $eolStatistics.BareCr -eq 0 -and $eolStatistics.BareLf -eq 0
    }
    $expectedEolName = if ($Fixture.Eol -eq "`n") { 'LF' } else { 'CRLF' }
    Add-FormattingAssertion -Passed $hasOnlyExpectedEol -Message (
        "$($Fixture.Name): output must preserve $expectedEolName with no mixed EOLs " +
        "(observed CRLF=$($eolStatistics.CrLf), bareCR=$($eolStatistics.BareCr), bareLF=$($eolStatistics.BareLf))."
    )

    $expectedNextSection = "## Next$($Fixture.Eol)$($Fixture.Eol)This following section must remain intact."
    $nextSectionIndex = $updatedContent.IndexOf('## Next', [System.StringComparison]::Ordinal)
    $nextSectionIsIntact = $nextSectionIndex -ge 0 -and
        $updatedContent.Substring($nextSectionIndex).StartsWith($expectedNextSection, [System.StringComparison]::Ordinal)
    Add-FormattingAssertion -Passed $nextSectionIsIntact -Message "$($Fixture.Name): the following ## Next section must remain intact."
    $generatedSectionIndex = $updatedContent.IndexOf('## Generated examples', [System.StringComparison]::Ordinal)
    $xmlEndIndex = $updatedContent.IndexOf('</Example>', [System.StringComparison]::Ordinal)
    $replacementPrecedesNext = $generatedSectionIndex -ge 0 -and $xmlEndIndex -gt $generatedSectionIndex -and
        $nextSectionIndex -gt $xmlEndIndex
    Add-FormattingAssertion -Passed $replacementPrecedesNext -Message "$($Fixture.Name): the replacement must remain in its original position before ## Next, not be appended after it."

    $maxXmlBacktickRun = 0
    foreach ($run in [regex]::Matches($Fixture.XmlContent, '`+')) {
        if ($run.Length -gt $maxXmlBacktickRun) {
            $maxXmlBacktickRun = $run.Length
        }
    }

    $openingFenceMatch = [regex]::Match($updatedContent, '(?m)^(?<ticks>`{3,})xml\r?$')
    $openingFenceLength = if ($openingFenceMatch.Success) { $openingFenceMatch.Groups['ticks'].Value.Length } else { 0 }
    Add-FormattingAssertion -Passed ($openingFenceLength -gt $maxXmlBacktickRun) -Message (
        "$($Fixture.Name): opening XML fence must exceed the longest XML backtick run " +
        "(XML max=$maxXmlBacktickRun, opener=$openingFenceLength)."
    )

    $closingFenceMatch = $null
    if ($openingFenceMatch.Success) {
        $contentAfterOpeningFence = $updatedContent.Substring($openingFenceMatch.Index + $openingFenceMatch.Length)
        $closingFencePattern = '(?m)^(?<ticks>`{' + $openingFenceLength + ',})\r?$'
        $closingFenceMatch = [regex]::Match($contentAfterOpeningFence, $closingFencePattern)
    }
    $closingFenceLength = if ($null -ne $closingFenceMatch -and $closingFenceMatch.Success) {
        $closingFenceMatch.Groups['ticks'].Value.Length
    } else {
        0
    }
    Add-FormattingAssertion -Passed ($closingFenceLength -gt $maxXmlBacktickRun) -Message (
        "$($Fixture.Name): closing XML fence must exceed the longest XML backtick run " +
        "(XML max=$maxXmlBacktickRun, closer=$closingFenceLength)."
    )

    $xmlEndIndex = $updatedContent.IndexOf('</Example>', [System.StringComparison]::Ordinal)
    $firstClosingFenceIndex = if ($null -ne $closingFenceMatch -and $closingFenceMatch.Success) {
        $openingFenceMatch.Index + $openingFenceMatch.Length + $closingFenceMatch.Index
    } else {
        -1
    }
    Add-FormattingAssertion -Passed ($xmlEndIndex -ge 0 -and $firstClosingFenceIndex -gt $xmlEndIndex) -Message (
        "$($Fixture.Name): the first valid closing fence must follow the complete XML example; " +
        "this prevents the CDATA backtick line from prematurely closing Markdown."
    )
}

try {
    $fixtures = @(
        (New-FormattingFixture -RootPath $tempRoot -Name 'lf' -Eol "`n")
        (New-FormattingFixture -RootPath $tempRoot -Name 'crlf' -Eol "`r`n")
    )
    foreach ($fixture in $fixtures) {
        Invoke-AndCheckFormattingFixture -Fixture $fixture
    }

    if ($failures.Count -gt 0) {
        Write-Output "RED: $($failures.Count) formatting assertion(s) failed against successfully processed valid fixtures."
        foreach ($failure in $failures) {
            Write-Output "RED_ASSERTION_FAILED: $failure"
        }
        throw "Doc section formatting failed: $($failures.Count) assertion(s)."
    }

    Write-Output 'MIMIR_DOC_SECTION_FORMATTING_SELFTEST_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
