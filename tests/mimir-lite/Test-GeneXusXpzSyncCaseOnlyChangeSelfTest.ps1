#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for case-sensitive change detection in Sync-GeneXusXpzToXml.ps1.

.DESCRIPTION
    The sync decides an object is unchanged by comparing the existing file text with the
    incoming XML text. That comparison must be ordinal (case-sensitive):
      A. First sync creates the object.
      B. A package whose object differs only by letter case (same name, same GUID, same
         lastUpdate) is reported as updated, and the file bytes change.
      C. Syncing the identical package again reports the object as unchanged and keeps
         the file bytes.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Sync-GeneXusXpzToXml.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-sync-case-only-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function New-Package {
    param([string]$Path, [string]$Guid, [string]$Name, [string]$LastUpdate, [string]$Description)
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <Objects />
  <Attributes>
    <Attribute lastUpdate="$LastUpdate" guid="$Guid" name="$Name" description="$Description"><Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c" /></Attribute>
  </Attributes>
</ExportFile>
"@
    Write-Utf8 -Path $Path -Content $xml
}

function Invoke-Sync {
    param([string]$Pkg, [string]$Corpus)
    $psArgs = @('-NoProfile', '-File', $scriptPath, '-InputPath', $Pkg, '-DestinationRoot', $Corpus)
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $stdout = & pwsh @psArgs 2>$errFile
        $exit = $LASTEXITCODE
        $stderr = Get-Content -LiteralPath $errFile -Raw
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
    $stdoutText = ($stdout | Out-String).Trim()
    if ($exit -ne 0) { throw "sync of '$Pkg' should exit 0; got $exit. StdOut: $stdoutText StdErr: $stderr" }
    $obj = $stdoutText | ConvertFrom-Json
    if ($obj.Kind -ne 'mimir-sync-result') { throw "stdout JSON.Kind should be 'mimir-sync-result'; got '$($obj.Kind)'" }
    return $obj
}

function Get-FileBase64 {
    param([string]$Path)
    return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
}

try {
    $guid = '33333333-3333-3333-3333-333333333333'
    $lastUpdate = '2026-01-01T00:00:00.0000000Z'
    $corpus = Join-Path $tempRoot 'KbObjectsXml'
    $filePath = Join-Path (Join-Path $corpus 'Attribute') 'CaseAttr.xml'

    # --- A: first sync creates the object ---
    $pkgA = Join-Path $tempRoot 'package-a.xml'
    New-Package -Path $pkgA -Guid $guid -Name 'CaseAttr' -LastUpdate $lastUpdate -Description 'customer name'
    $a = Invoke-Sync -Pkg $pkgA -Corpus $corpus
    if ($a.Created -ne 1) { throw "A: Created should be 1; got $($a.Created)" }
    if (-not (Test-Path -LiteralPath $filePath)) { throw "A: the object file should exist at $filePath" }
    $bytesA = Get-FileBase64 -Path $filePath

    # --- B: case-only difference, same lastUpdate -> updated, bytes change ---
    $pkgB = Join-Path $tempRoot 'package-b.xml'
    New-Package -Path $pkgB -Guid $guid -Name 'CaseAttr' -LastUpdate $lastUpdate -Description 'Customer Name'
    $b = Invoke-Sync -Pkg $pkgB -Corpus $corpus
    if ($b.Updated -ne 1) { throw "B: a case-only change should be reported as updated (Updated 1); got Updated $($b.Updated), Unchanged $($b.Unchanged)" }
    if ($b.Unchanged -ne 0) { throw "B: Unchanged should be 0; got $($b.Unchanged)" }
    if ($b.UpdatedNames -notcontains 'Attribute:CaseAttr') { throw "B: UpdatedNames should contain 'Attribute:CaseAttr'; got [$(@($b.UpdatedNames) -join ', ')]" }
    $bytesB = Get-FileBase64 -Path $filePath
    if ($bytesB -eq $bytesA) { throw "B: the file bytes should change after a case-only update" }
    if (-not ((Get-Content -LiteralPath $filePath -Raw).Contains('description="Customer Name"'))) { throw "B: the file should carry the new-case description" }

    # --- C: identical package -> unchanged, bytes kept ---
    $c = Invoke-Sync -Pkg $pkgB -Corpus $corpus
    if ($c.Unchanged -ne 1) { throw "C: an identical object should be reported as unchanged (Unchanged 1); got Unchanged $($c.Unchanged), Updated $($c.Updated)" }
    if ($c.Updated -ne 0) { throw "C: Updated should be 0; got $($c.Updated)" }
    if ((Get-FileBase64 -Path $filePath) -ne $bytesB) { throw "C: the file bytes should not change for an identical object" }

    Write-Output 'OK: Test-GeneXusXpzSyncCaseOnlyChangeSelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
