#requires -Version 7.4
<#
.SYNOPSIS
    Exercises the UTF-8-safe git helpers of the pre-push mechanical checks and
    proves that whitespace diagnostics inside fenced blocks are never suppressed.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/PrePushGitSupport.ps1')

# The raw Git parser must keep blank lines between a diagnostic header and its context.
$blankText = "a.md:3: trailing whitespace.`n`n+payload  `n"
$blankLines = @(ConvertFrom-PrePushGitOutputText -Text $blankText)
if ($blankLines.Count -ne 3 -or $blankLines[1] -cne '') {
    throw 'The raw Git parser must preserve blank lines between diagnostic headers and context.'
}
if (@(ConvertFrom-PrePushGitOutputText -Text '').Count -ne 0) {
    throw 'Empty Git output must parse to zero lines.'
}
$oneBlank = @(ConvertFrom-PrePushGitOutputText -Text "`n")
if ($oneBlank.Count -ne 1 -or $oneBlank[0] -cne '') {
    throw 'A lone newline is one blank line, not zero lines.'
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('prepush-gitsupport-selftest-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot)
try {
    & git -C $tempRoot init -b main *> $null
    & git -C $tempRoot config user.email selftest@example.test *> $null
    & git -C $tempRoot config user.name 'Self Test' *> $null
    & git -C $tempRoot config core.autocrlf false *> $null
    $fence = ([string][char]96) * 3
    [IO.File]::WriteAllText((Join-Path $tempRoot 'base.md'), "base`n")
    $crlfPath = 'crlf.md'
    $baseCrlfText = (@('# CRLF', ($fence + 'gx'), 'payload', $fence) -join "`r`n") + "`r`n"
    [IO.File]::WriteAllBytes((Join-Path $tempRoot $crlfPath), [Text.Encoding]::UTF8.GetBytes($baseCrlfText))
    $payloadPath = 'payload.md'
    $payloadFile = Join-Path $tempRoot $payloadPath
    [IO.File]::WriteAllText($payloadFile, ((@('# sample', "${fence}gx", 'first', $fence, 'between', "${fence}gx", 'second', $fence) -join "`n") + "`n"))
    & git -C $tempRoot add base.md $payloadPath $crlfPath *> $null
    & git -C $tempRoot commit -m base *> $null
    & git -C $tempRoot checkout -q -b feature *> $null
    [IO.File]::WriteAllText((Join-Path $tempRoot 'changed.md'), "clean`n")
    [IO.File]::WriteAllText($payloadFile, ((@('# sample', "${fence}gx", 'first  ', $fence, 'between', "${fence}gx", 'second  ', $fence) -join "`n") + "`n"))
    $changedCrlfText = (@('# CRLF', ($fence + 'gx'), 'payload  ', $fence) -join "`r`n") + "`r`n"
    [IO.File]::WriteAllBytes((Join-Path $tempRoot $crlfPath), [Text.Encoding]::UTF8.GetBytes($changedCrlfText))
    & git -C $tempRoot add changed.md $payloadPath $crlfPath *> $null
    & git -C $tempRoot commit -m whitespace *> $null

    $raw = Invoke-PrePushGitUtf8 -RepositoryRoot $tempRoot -Arguments @('diff', '--check', 'main..HEAD')
    if ($raw.ExitCode -ne 2 -or $raw.Lines.Count -ne 6) {
        throw "Expected three paired raw diagnostics, got exit=$($raw.ExitCode) lines=$($raw.Lines.Count)."
    }

    $orchestrator = Join-Path $repoRoot 'tools/Invoke-PrePushMechanicalChecks.ps1'
    $output = & pwsh -NoProfile -NonInteractive -File $orchestrator -RootPath $tempRoot -BaseRef main -SkipParse -AsJson 2>&1
    $exitCode = $LASTEXITCODE
    $json = ($output | Out-String).Trim()
    $report = $null
    try { $report = $json | ConvertFrom-Json } catch { }
    if ($null -eq $report) { throw "The orchestrator must return JSON for a temporary repository: $json" }
    if ($exitCode -eq 0 -or $report.status -ne 'fail' -or $report.mechanicalFailures -notcontains 'whitespace') {
        throw 'Whitespace inside fenced blocks must fail the mechanical check.'
    }
    if ($report.git.whitespaceCheck -ne 'issues-found') {
        throw "Expected whitespaceCheck 'issues-found', got '$($report.git.whitespaceCheck)'."
    }
    if ($report.git.whitespaceRemainingIssues.Count -ne $raw.Lines.Count) {
        throw 'Every raw diagnostic must stay visible; nothing is suppressed.'
    }
    if ($null -ne $report.git.PSObject.Properties['whitespacePayloadExceptions']) {
        throw 'The report must not carry a payload-exception section.'
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-Output 'OK: Test-PrePushGitSupportSelfTest.ps1'
