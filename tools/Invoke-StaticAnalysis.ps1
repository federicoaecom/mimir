#requires -Version 7.4
<#
.SYNOPSIS
    Advisory static analysis of the repository's PowerShell and Python files.

.DESCRIPTION
    Runs two optional development tools over the tracked .ps1 and .py files under skills/,
    tools/ and tests/, and prints one sorted report line per finding:
      <path>:<line>:<column> <rule> <message>
    - Python: ruff with the pyflakes rules only (--select F), the Python 3.8 target, no
      configuration file (--isolated) and no cache.
    - PowerShell: PSScriptAnalyzer with a small rule set (unused variables and parameters,
      assignments to automatic variables, comparisons with $null on the wrong side, and an
      assignment where a comparison was likely meant).
    A tool that is not installed is reported as SKIPPED. The product needs neither tool.
    Findings never fail the step (exit 0); a tool that fails to run makes it exit 1.
    The last line is the summary: STATIC_ANALYSIS python=<n|skipped> powershell=<n|skipped>
#>

[CmdletBinding()]
param(
    [string] $RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,

    [string] $RuffCommand = 'ruff',

    [string] $PSScriptAnalyzerModule = 'PSScriptAnalyzer'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$powerShellRules = @(
    'PSUseDeclaredVarsMoreThanAssignments'
    'PSReviewUnusedParameter'
    'PSAvoidAssignmentToAutomaticVariable'
    'PSPossibleIncorrectComparisonWithNull'
    'PSPossibleIncorrectUsageOfAssignmentOperator'
)

$root = (Resolve-Path -LiteralPath $RootPath).Path

function Get-TrackedFile {
    param([string] $Extension)
    $listed = @(git -C $root ls-files -- "skills/*$Extension" "tools/*$Extension" "tests/*$Extension")
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $root" }
    return @($listed | Where-Object { $_ } | Sort-Object -CaseSensitive)
}

function Get-RootRelativePath {
    param([string] $Path)
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $root $Path }
    return [System.IO.Path]::GetRelativePath($root, [System.IO.Path]::GetFullPath($full)).Replace('\', '/')
}

function Format-Finding {
    param([string] $Path, [int] $Line, [int] $Column, [string] $Rule, [string] $Message)
    $oneLine = ($Message -replace '\s+', ' ').Trim()
    [pscustomobject]@{ Path = $Path; Line = $Line; Column = $Column; Rule = $Rule; Text = "${Path}:${Line}:${Column} $Rule $oneLine" }
}

$findings = [System.Collections.Generic.List[object]]::new()
$notes = [System.Collections.Generic.List[string]]::new()
$summary = [ordered]@{ python = 'skipped'; powershell = 'skipped' }
$toolFailed = $false

$pythonFiles = @(Get-TrackedFile '.py')
if (-not (Get-Command -Name $RuffCommand -CommandType Application -ErrorAction SilentlyContinue)) {
    $notes.Add("SKIPPED python: ruff command '$RuffCommand' was not found")
}
elseif ($pythonFiles.Count -eq 0) {
    $summary.python = '0'
}
else {
    Push-Location -LiteralPath $root
    try {
        $raw = & $RuffCommand check --isolated --no-cache --select F --target-version py38 --output-format json --exit-zero @pythonFiles 2>&1
        $ruffExit = $LASTEXITCODE
    }
    finally { Pop-Location }
    if ($ruffExit -ne 0) {
        $toolFailed = $true
        $notes.Add("ERROR python: ruff exited $ruffExit")
        $notes.Add(($raw | ForEach-Object { [string] $_ }) -join "`n")
    }
    else {
        $items = @(([string]::Join("`n", @($raw | ForEach-Object { [string] $_ }))) | ConvertFrom-Json)
        foreach ($item in $items) {
            $findings.Add((Format-Finding (Get-RootRelativePath $item.filename) $item.location.row $item.location.column $item.code $item.message))
        }
        $summary.python = [string] $items.Count
    }
}

$powerShellFiles = @(Get-TrackedFile '.ps1')
if (-not (Get-Module -ListAvailable -Name $PSScriptAnalyzerModule)) {
    $notes.Add("SKIPPED powershell: module $PSScriptAnalyzerModule is not installed")
}
else {
    Import-Module -Name $PSScriptAnalyzerModule
    $count = 0
    foreach ($file in $powerShellFiles) {
        try {
            $records = @(Invoke-ScriptAnalyzer -Path (Join-Path $root $file) -IncludeRule $powerShellRules)
        }
        catch {
            $toolFailed = $true
            $notes.Add("ERROR powershell: $file : $($_.Exception.Message)")
            continue
        }
        foreach ($record in $records) {
            $findings.Add((Format-Finding $file $record.Line $record.Column $record.RuleName $record.Message))
            $count++
        }
    }
    $summary.powershell = [string] $count
}

$findings |
    Sort-Object -CaseSensitive -Property Path, Line, Column, Rule, Text |
    ForEach-Object { Write-Output $_.Text }
foreach ($note in $notes) { Write-Output $note }
Write-Output ("STATIC_ANALYSIS python={0} powershell={1}" -f $summary.python, $summary.powershell)

if ($toolFailed) { exit 1 }
exit 0
