#requires -Version 7.4
<#
.SYNOPSIS
    File base-name normalization for GeneXus object materialization (single source).

.DESCRIPTION
    Canonical source of Normalize-FileBaseName, dot-sourced by Sync-GeneXusXpzToXml.ps1 and (future
    workstream, dependent on the GX9 sample) by the legacy export converter
    GeneXusLegacyExportFileSupport.ps1. Centralizing it guarantees that name-collision detection
    (grouping by FolderType|NormalizedName) is identical on both paths — avoiding the normalization
    divergence between paths that the peer review pointed out.

    Rule: replaces each invalid filename character (the fixed set from
    Get-GeneXusInvalidFileNameChars) with '_' and removes trailing dot(s) with TrimEnd('.').
    Behavior preserved byte-for-byte from the historical Windows implementation internal to Sync.
#>

function Get-GeneXusInvalidFileNameChars {
    <#
        Fixed invalid file-name character set: the Windows set (control characters 0-31 plus
        " < > | : * ? \ /), in the order Windows returns it. [System.IO.Path]::GetInvalidFileNameChars()
        is only '/' and NUL on Linux and macOS, so using it would give the same GeneXus object a
        different file name per OS; this set keeps names identical on every OS.
    #>
    $chars = [System.Collections.Generic.List[char]]::new()
    foreach ($c in '"<>|'.ToCharArray()) { $chars.Add($c) }
    foreach ($code in 0..31) { $chars.Add([char]$code) }
    foreach ($c in ':*?\/'.ToCharArray()) { $chars.Add($c) }
    return ,($chars.ToArray())
}

function Normalize-FileBaseName {
    param([string]$LogicalName)

    $invalidChars = Get-GeneXusInvalidFileNameChars
    $builder = New-Object System.Text.StringBuilder

    foreach ($char in $LogicalName.ToCharArray()) {
        if ($invalidChars -contains $char) {
            [void]$builder.Append('_')
        } else {
            [void]$builder.Append($char)
        }
    }

    return $builder.ToString().TrimEnd('.')
}
