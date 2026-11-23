#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('package parity-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$scripts = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'skills/mimir-lite/scripts'
$inventory = Join-Path $scripts 'Get-GeneXusXpzObjectInventory.ps1'
$sync = Join-Path $scripts 'Sync-GeneXusXpzToXml.ps1'
$xml = '<ExportFile><Objects><Object type="84a12160-f59b-4ad7-a683-ea4481ac23e9" name="Example" guid="11111111-1111-1111-1111-111111111111" lastUpdate="2024-01-01T00:00:00Z" /></Objects></ExportFile>'
function New-Archive([string]$Name, [hashtable]$Entries) {
    $path = Join-Path $root $Name
    $archive = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries.Keys) {
            $entry = $archive.CreateEntry($name)
            $stream = $entry.Open()
            try {
                $bytes = if ($Entries[$name] -is [byte[]]) { $Entries[$name] } else { [Text.Encoding]::UTF8.GetBytes($Entries[$name]) }
                $stream.Write($bytes, 0, $bytes.Length)
            } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    return $path
}
function Invoke-Child([string]$Script, [string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($arg in (@('-NoProfile', '-NonInteractive', '-File', $Script) + $Arguments)) {
        $start.ArgumentList.Add($arg)
    }
    $p = [Diagnostics.Process]::Start($start)
    try {
        $out = $p.StandardOutput.ReadToEndAsync()
        $err = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        return [pscustomobject]@{ Exit = $p.ExitCode; Out = $out.GetAwaiter().GetResult(); Err = $err.GetAwaiter().GetResult() }
    } finally { $p.Dispose() }
}
try {
    $direct = Join-Path $root 'direct.xml'
    [IO.File]::WriteAllText($direct, $xml, [Text.UTF8Encoding]::new($false))
    $nested = New-Archive 'nested.xpz' @{ 'nested/export.xml' = $xml }
    $sidecar = New-Archive 'sidecar.xpz' @{ 'manifest.xml' = '<Manifest />'; 'dir/export.xml' = $xml }
    $zip = New-Archive 'export.zip' @{ 'export.xml' = $xml }
    $ambiguous = New-Archive 'ambiguous.xpz' @{ 'a.xml' = $xml; 'b.xml' = $xml }
    $empty = New-Archive 'empty.xpz' @{ 'manifest.xml' = '<Manifest />' }
    $latinName = 'Caf' + [char]0x00E9
    $latinXml = '<?xml version="1.0" encoding="iso-8859-1"?>' + $xml.Replace('Example', $latinName)
    $latin = New-Archive 'latin.xpz' @{ 'inner/export.xml' = [Text.Encoding]::GetEncoding(28591).GetBytes($latinXml) }
    $emptyFolder = Join-Path $root 'empty-folder'
    $multipleFolder = Join-Path $root 'multiple-folder'
    [void][IO.Directory]::CreateDirectory($emptyFolder)
    [void][IO.Directory]::CreateDirectory((Join-Path $emptyFolder 'nested'))
    [IO.File]::WriteAllText((Join-Path $emptyFolder 'nested/export.xml'), $xml)
    [void][IO.Directory]::CreateDirectory($multipleFolder)
    [IO.File]::WriteAllText((Join-Path $multipleFolder 'a.xml'), $xml)
    [IO.File]::WriteAllText((Join-Path $multipleFolder 'b.xml'), $xml)
    $folder = Join-Path $root 'folder'
    [void][IO.Directory]::CreateDirectory($folder)
    [IO.File]::WriteAllText((Join-Path $folder 'export.xml'), $xml, [Text.UTF8Encoding]::new($false))
    foreach ($case in @(
        @{ Path = $nested; Entry = 'nested/export.xml'; Kind = 'xpz'; XmlPath = $null },
        @{ Path = $sidecar; Entry = 'dir/export.xml'; Kind = 'xpz'; XmlPath = $null },
        @{ Path = $zip; Entry = 'export.xml'; Kind = 'xpz'; XmlPath = $null },
        @{ Path = $direct; Entry = $null; Kind = 'xml'; XmlPath = $direct },
        @{ Path = $folder; Entry = $null; Kind = 'xml'; XmlPath = (Join-Path $folder 'export.xml') }
    )) {
        $destination = Join-Path $root ('corpus-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($destination)
        $inv = Invoke-Child $inventory @('-InputPath', $case.Path)
        if ($inv.Exit -ne 0 -or $inv.Err -ne '') { throw "inventory failed for $($case.Path): $($inv.Exit) $($inv.Err) $($inv.Out)" }
        $i = $inv.Out | ConvertFrom-Json
        if ($i.inputKind -cne $case.Kind -or $i.innerXmlEntry -cne $case.Entry -or $i.objectCount -ne 1) { throw "inventory mismatch for $($case.Path)" }
        $result = Invoke-Child $sync @('-InputPath', $case.Path, '-DestinationRoot', $destination)
        if ($result.Exit -ne 0) { throw "sync failed for $($case.Path): $($result.Exit) $($result.Err) $($result.Out)" }
        $s = $result.Out | ConvertFrom-Json
        if ($s.PackageXmlPath -cne $case.XmlPath -or $s.PackageXmlEntry -cne $case.Entry -or $s.Created -ne 1) { throw "sync summary mismatch for $($case.Path)" }
        if (-not (Test-Path -LiteralPath (Join-Path $destination 'Procedure/Example.xml'))) { throw 'materialized object missing' }
    }
    $destination = Join-Path $root 'latin-corpus'
    [void][IO.Directory]::CreateDirectory($destination)
    $inv = Invoke-Child $inventory @('-InputPath', $latin)
    if ($inv.Exit -ne 0 -or $inv.Err -ne '') { throw 'Latin-1 inventory failed' }
    $i = $inv.Out | ConvertFrom-Json
    if ($i.innerXmlEntry -cne 'inner/export.xml' -or $i.inventory[0].name -cne $latinName) { throw 'Latin-1 inventory decoded incorrectly' }
    $result = Invoke-Child $sync @('-InputPath', $latin, '-DestinationRoot', $destination)
    if ($result.Exit -ne 0) { throw "Latin-1 sync failed: $($result.Err)" }
    $s = $result.Out | ConvertFrom-Json
    if ($null -ne $s.PackageXmlPath -or $s.PackageXmlEntry -cne 'inner/export.xml' -or $s.Created -ne 1 -or $s.CreatedNames[0] -cne "Procedure:$latinName") { throw 'Latin-1 sync decoded incorrectly' }
    $saved = [xml][IO.File]::ReadAllText((Join-Path $destination "Procedure/$latinName.xml"))
    if ($saved.DocumentElement.GetAttribute('name') -cne $latinName) { throw 'Latin-1 materialized XML decoded incorrectly' }

    foreach ($path in @($ambiguous, $empty, $emptyFolder, $multipleFolder)) {
        $destination = Join-Path $root ('rejected-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($destination)
        $marker = Join-Path $destination 'marker.txt'
        [IO.File]::WriteAllText($marker, 'unchanged')
        $inv = Invoke-Child $inventory @('-InputPath', $path)
        if ($inv.Exit -ne 20 -or $inv.Err -ne '' -or ($inv.Out | ConvertFrom-Json).status -ne 'blocked') { throw "inventory must block $path" }
        $result = Invoke-Child $sync @('-InputPath', $path, '-DestinationRoot', $destination)
        $expectedError = if ($path -eq $emptyFolder -or $path -eq $multipleFolder) { 'Expected exactly one XML file inside folder' } else { 'ExportFile' }
        if ($result.Exit -ne 1 -or $result.Out -ne '' -or $result.Err -notmatch $expectedError) { throw "sync must block $path" }
        if ([IO.File]::ReadAllText($marker) -cne 'unchanged' -or @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count -ne 1) { throw 'rejected input changed corpus' }
    }
    Write-Output 'GENEXUS_PACKAGE_READER_PARITY_SELFTEST_OK'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
