#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: tools/Invoke-CiChecks.ps1 lists the CI steps in order, and the CI workflow runs
    that script only on demand or for a release tag.

.DESCRIPTION
    Proves that:
      - `Invoke-CiChecks.ps1 -ListSteps` exits 0 and prints exactly the nine steps, in order,
        without running them;
      - run against a temporary stub repository (a copy of the script next to stub check scripts
        that exit 0 or 1), every step runs even after one fails, the failing step prints
        `FAIL (1)`, the others `PASS (0)`, the summary counts them, and the exit code is 1; with
        every stub passing, the exit code is 0;
      - .github/workflows/ci.yml runs `tools/Invoke-CiChecks.ps1` (the one list of checks shared
        with tools/Invoke-LinuxTestsInDocker.ps1), keeps the Windows and Linux matrix, and is
        triggered by `workflow_dispatch` and by `v*` tags only (no push to a branch, no pull
        request), so hosted-runner minutes are spent once per release.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $repoRoot 'tools/Invoke-CiChecks.ps1'
$workflow = Join-Path $repoRoot '.github/workflows/ci.yml'

$failures = [System.Collections.Generic.List[string]]::new()
function Add-Failure([string]$Message) { $failures.Add($Message) }

$expectedSteps = @(
    'PowerShell version (7.4.6+ outside Windows)',
    'Test suite',
    'Text encoding (UTF-8 without BOM, LF)',
    'PowerShell parse check',
    'Python parse check',
    'Markdown fence check (whole repository)',
    'Markdown link check (governance + skill payload + English references)',
    'Script inventory completeness (09-script-inventory.md)',
    'Code language check (pt-BR in code comments/messages)'
)

$output = @(& pwsh -NoProfile -NonInteractive -File $script -ListSteps 2>&1)
if ($LASTEXITCODE -ne 0) {
    Add-Failure "-ListSteps should exit 0; got $LASTEXITCODE`: $($output -join ' | ')"
}
$actualSteps = @($output | ForEach-Object { "$_".TrimEnd() } | Where-Object { $_ -ne '' })
if (($actualSteps -join "`n") -cne ($expectedSteps -join "`n")) {
    Add-Failure "-ListSteps should print the nine steps in order; got:`n$($actualSteps -join "`n")"
}

# Stub repository: the real script, with every check it calls replaced by a stub.
$stubRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ci-checks-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    $stubFiles = @('tests/Invoke-Tests.ps1', 'tools/Test-TextEncoding.ps1', 'tools/Test-PsScriptsParse.ps1',
        'tools/Test-PyScriptsParse.ps1', 'tools/Test-MarkdownFences.ps1', 'tools/Test-MarkdownLinks.ps1',
        'tools/Test-ScriptInventory.ps1', 'tools/Test-CodeLanguage.ps1')
    [void](New-Item -ItemType Directory -Path (Join-Path $stubRoot 'tools'), (Join-Path $stubRoot 'tests') -Force)
    Copy-Item -LiteralPath $script -Destination (Join-Path $stubRoot 'tools/Invoke-CiChecks.ps1')
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    foreach ($runCase in @(
            [pscustomobject]@{ Failing = 'tools/Test-PyScriptsParse.ps1'; FailingStep = 'Python parse check'; ExpectedExit = 1; Summary = 'CI checks: 8 passed, 1 failed' },
            [pscustomobject]@{ Failing = $null; FailingStep = $null; ExpectedExit = 0; Summary = 'CI checks: 9 passed, 0 failed' }
        )) {
        foreach ($stub in $stubFiles) {
            $code = if ($stub -eq $runCase.Failing) { 1 } else { 0 }
            [System.IO.File]::WriteAllText((Join-Path $stubRoot $stub), "param([string[]]`$IncludePaths)`nWrite-Output 'stub $stub'`nexit $code`n", $utf8)
        }
        $label = if ($runCase.Failing) { "stub run, $($runCase.Failing) failing" } else { 'stub run, all passing' }
        $runOutput = @(& pwsh -NoProfile -NonInteractive -File (Join-Path $stubRoot 'tools/Invoke-CiChecks.ps1') 2>&1 | ForEach-Object { "$_".TrimEnd() })
        $runExit = $LASTEXITCODE
        if ($runExit -ne $runCase.ExpectedExit) {
            Add-Failure "[$label] exit code should be $($runCase.ExpectedExit); got $runExit"
        }
        $statusLines = @($runOutput | Where-Object { $_ -match '^(PASS|FAIL) \(' })
        if ($statusLines.Count -ne $expectedSteps.Count) {
            Add-Failure "[$label] every step should run and print a status line; got $($statusLines.Count): $($statusLines -join ' | ')"
        }
        foreach ($line in $statusLines) {
            $isFailing = $runCase.FailingStep -and $line.EndsWith(": $($runCase.FailingStep)")
            $expectedPrefix = if ($isFailing) { 'FAIL (1): ' } else { 'PASS (0): ' }
            if (-not $line.StartsWith($expectedPrefix)) {
                Add-Failure "[$label] status line should start with '$expectedPrefix': $line"
            }
        }
        if ($runOutput -notcontains $runCase.Summary) {
            Add-Failure "[$label] the summary should read '$($runCase.Summary)'; got: $(($runOutput | Select-Object -Last 3) -join ' | ')"
        }
    }
}
finally {
    if (Test-Path -LiteralPath $stubRoot) { Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

$yaml = [System.IO.File]::ReadAllText($workflow)
if ($yaml -notmatch '(?m)^\s+pwsh\s.*-File\s+tools/Invoke-CiChecks\.ps1\s*$') {
    Add-Failure 'ci.yml should run tools/Invoke-CiChecks.ps1'
}
if ($yaml -notmatch 'windows-latest' -or $yaml -notmatch 'ubuntu-latest') {
    Add-Failure 'ci.yml should keep the windows-latest and ubuntu-latest matrix'
}
# The on: block is the indented (or blank) lines right after `on:`, up to the next top-level key.
$onBlock = [regex]::Match($yaml, '(?m)^on:[ \t]*\r?\n(?<body>(?:[ \t]+[^\n]*\n|[ \t]*\r?\n)*)').Groups['body'].Value
if ($onBlock -match '(?m)^\S') {
    Add-Failure "the on: block should hold only indented lines; got:`n$onBlock"
}
if ($onBlock -match 'jobs:|runs-on:') {
    Add-Failure "the on: block extraction ran past the triggers; got:`n$onBlock"
}
if ($onBlock -notmatch '(?m)^\s+workflow_dispatch:') {
    Add-Failure "ci.yml should be triggered by workflow_dispatch; on: block was:`n$onBlock"
}
if ($onBlock -notmatch "(?m)^\s+tags:\s*\[\s*['""]?v\*['""]?\s*\]") {
    Add-Failure "ci.yml should be triggered by v* tags; on: block was:`n$onBlock"
}
if ($onBlock -match '(?m)^\s+branches:' -or $onBlock -match '(?m)^\s+pull_request:') {
    Add-Failure "ci.yml must not run on branch pushes or pull requests; on: block was:`n$onBlock"
}

if ($failures.Count -gt 0) {
    throw ("Test-InvokeCiChecksSelfTest.ps1: {0} failure(s):`n- {1}" -f $failures.Count, ($failures -join "`n- "))
}
Write-Output 'OK: Test-InvokeCiChecksSelfTest.ps1'
exit 0
