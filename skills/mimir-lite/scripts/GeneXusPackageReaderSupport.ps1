#requires -Version 7.4
<#
.SYNOPSIS
Shared folder resolution and in-memory ExportFile XML selection for sync and inventory.
.DESCRIPTION
A folder must contain exactly one immediate XML file. An XPZ or XML ZIP must contain
exactly one parseable XML with an ExportFile root at any depth. Other XML entries are
ignored. Archive entries are read as streams, preserving the declared XML encoding;
no archive member is extracted. The caller handles XPW translation and error envelopes.
#>

function Resolve-GeneXusPackageInputPath {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (Test-Path -LiteralPath $resolved -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $resolved -Filter '*.xml' -File)
        if ($files.Count -ne 1) {
            throw "Expected exactly one XML file inside folder '$resolved', found $($files.Count)."
        }
        return $files[0].FullName
    }
    return $resolved
}

function Read-GeneXusPackageArchiveXml {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $candidates = [System.Collections.Generic.List[System.Xml.XmlDocument]]::new()
    $names = [System.Collections.Generic.List[string]]::new()
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in @($zip.Entries | Where-Object { $_.FullName -match '\.xml$' } | Sort-Object FullName)) {
            $document = [System.Xml.XmlDocument]::new()
            $document.PreserveWhitespace = $true
            $stream = $entry.Open()
            try { $document.Load($stream) }
            catch { continue }
            finally { $stream.Dispose() }
            if ($null -ne $document.DocumentElement -and $document.DocumentElement.LocalName -eq 'ExportFile') {
                $candidates.Add($document)
                $names.Add($entry.FullName)
            }
        }
    } finally { $zip.Dispose() }
    if ($candidates.Count -eq 0) {
        throw "BLOCK: .xpz package has no XML with an ExportFile root: $Path"
    }
    if ($candidates.Count -gt 1) {
        throw ("BLOCK: .xpz package contains {0} ambiguous ExportFile candidates ({1}); provide the extracted XML instead." -f $candidates.Count, ($names -join ', '))
    }
    return [pscustomobject]@{ Document = $candidates[0]; EntryName = $names[0] }
}
