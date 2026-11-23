#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/AssertSupport.ps1')

$scriptPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts/Sync-GeneXusXpzToXml.ps1'
$base = if ($env:MIMIR_ATOMIC_XML_TEST_ROOT) { $env:MIMIR_ATOMIC_XML_TEST_ROOT } else { [IO.Path]::GetTempPath() }
$root = Join-Path $base ('mimir-atomic-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$encoding = [Text.UTF8Encoding]::new($false)
$corpus = Join-Path $root 'corpus'
$target = Join-Path $corpus 'Attribute/Atomic.xml'
$package = Join-Path $root 'package.xml'

function Set-Package([string]$date, [string]$description) {
    $text = "<ExportFile><Attributes><Attribute name=`"Atomic`" guid=`"`" lastUpdate=`"$date`" description=`"$description`" /></Attributes></ExportFile>"
    [IO.File]::WriteAllText($package, $text, $encoding)
}
function Invoke-Sync([switch]$VerifyOnly) {
    $argsList = @('-NoProfile', '-NonInteractive', '-File', $scriptPath, '-InputPath', $package, '-DestinationRoot', $corpus)
    if ($VerifyOnly) { $argsList += '-VerifyOnly' }
    $err = Join-Path $root 'stderr.txt'
    $stdout = & pwsh @argsList 2>$err
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Code = $code; Stdout = ($stdout -join "`n"); Stderr = [IO.File]::ReadAllText($err) }
}
function Confirm-SyncField($result, [string]$field) {
    Assert-True ($result.Code -eq 0 -and $result.Stderr) "sync failed: exit $($result.Code), stderr $($result.Stderr)"
    $json = $result.Stdout | ConvertFrom-Json
    Assert-True ($json.Kind -eq 'mimir-sync-result' -and $json.$field -eq 1) "expected $field=1: $($result.Stdout)"
}
function Bytes { [Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) }
function Confirm-OnlyUnownedSibling {
    $files = @(Get-ChildItem -LiteralPath (Split-Path $target) -File -Force)
    Assert-True ($files.Count -eq 2 -and (Test-Path -LiteralPath (Join-Path (Split-Path $target) '.mimir-xml-unowned.tmp'))) "unexpected sibling files: $($files.Name -join ', ')"
    Assert-True ([IO.File]::ReadAllText((Join-Path (Split-Path $target) '.mimir-xml-unowned.tmp')) -eq 'unowned') 'unowned sibling changed'
}
try {
    Set-Package '2026-01-01T00:00:00Z' 'old'
    Confirm-SyncField (Invoke-Sync) 'Created'
    $old = Bytes
    [IO.File]::WriteAllText((Join-Path (Split-Path $target) '.mimir-xml-unowned.tmp'), 'unowned', $encoding)
    $bytes = [IO.File]::ReadAllBytes($target)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) { throw 'unexpected UTF-8 BOM' }
    Confirm-SyncField (Invoke-Sync) 'Unchanged'
    if ((Bytes) -ne $old) { throw 'unchanged modified bytes' }
    Set-Package '2025-01-01T00:00:00Z' 'older'
    Confirm-SyncField (Invoke-Sync) 'SkippedOlderLastUpdate'
    if ((Bytes) -ne $old) { throw 'older input modified bytes' }
    Set-Package '2027-01-01T00:00:00Z' 'new'
    $verify = Invoke-Sync -VerifyOnly
    if ($verify.Code -ne 0 -or ($verify.Stdout | ConvertFrom-Json).VerifyOnly -ne $true -or (Bytes) -ne $old) { throw 'VerifyOnly changed the corpus or failed' }

    if ($IsWindows) {
        # Permit the old in-place write while denying the delete sharing required by replacement.
        $handle = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $failed = Invoke-Sync } finally { $handle.Dispose() }
        if ($failed.Code -eq 0) { throw 'locked replacement must fail nonzero' }
        Write-Output "Locked replacement exit: $($failed.Code)"
        if ($failed.Stdout -ne '' -or -not $failed.Stderr) { throw 'failed sync must have empty stdout and diagnostic stderr' }
        if ((Bytes) -ne $old) { throw 'failed replacement changed destination bytes' }
        Confirm-OnlyUnownedSibling
    } else {
        Write-Output 'SKIP: Windows delete-sharing failure probe'
    }
    Confirm-SyncField (Invoke-Sync) 'Updated'
    if ((Bytes) -eq $old -or -not ([IO.File]::ReadAllText($target).Contains('description="new"'))) { throw 'replacement did not publish new bytes' }
    Confirm-OnlyUnownedSibling
    Write-Output 'OK: atomic XML creation, replacement and preservation'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
