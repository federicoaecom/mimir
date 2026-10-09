#requires -Version 7.4
<#
.SYNOPSIS
    Parses repository PowerShell scripts and reports syntax errors.

.DESCRIPTION
    Checks every *.ps1 under skills/, tools/ and tests/, plus every *.example.ps1
    (deduplicated, since a moved example may already live under one of those roots).
    This is a syntax-only gate for the repository runtime contract: pwsh 7.4+ (7.4.6+ on Linux and macOS).
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RelativeDisplayPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    return [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($BasePath),
        [System.IO.Path]::GetFullPath($TargetPath)
    )
}

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

$scanRootNames = @('skills', 'tools', 'tests')
$scanRoots = @($scanRootNames | ForEach-Object { Join-Path $resolvedRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container })

if ($scanRoots.Count -eq 0) {
    throw "no scan roots found under: $resolvedRoot (expected one of: $($scanRootNames -join ', '))"
}

$scriptFiles = @(foreach ($root in $scanRoots) { Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.ps1" })
$exampleFiles = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter "*.example.ps1")

$files = @(
    @($scriptFiles + $exampleFiles) |
        Group-Object -Property FullName |
        ForEach-Object { $_.Group[0] } |
        Sort-Object FullName
)

$findings = [System.Collections.Generic.List[object]]::new()

foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)

    foreach ($parseError in @($parseErrors)) {
        $findings.Add([pscustomobject]@{
            file    = Get-RelativeDisplayPath -BasePath $resolvedRoot -TargetPath $file.FullName
            line    = $parseError.Extent.StartLineNumber
            column  = $parseError.Extent.StartColumnNumber
            message = $parseError.Message
        }) | Out-Null
    }
}

$result = [ordered]@{
    rootPath   = $resolvedRoot
    status     = if ($findings.Count -eq 0) { "pass" } else { "fail" }
    fileCount  = $files.Count
    errorCount = $findings.Count
    findings   = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 6
} else {
    foreach ($finding in $findings) {
        "PARSE_ERROR: {0}:{1}:{2}: {3}" -f $finding.file, $finding.line, $finding.column, $finding.message
    }
    "FILES={0}; ERRORS={1}" -f $files.Count, $findings.Count
}

if ($findings.Count -gt 0) {
    exit 1
}

exit 0
