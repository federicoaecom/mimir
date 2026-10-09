#requires -Version 7.4
<#
.SYNOPSIS
    Reads and writes text files preserving EOL and the trailing newline.

.DESCRIPTION
    Avoids the ReadAllLines + WriteAllLines / join-with-Environment.NewLine
    anti-pattern, which rewrites versioned files with CRLF on Windows even when
    the local or repository policy requires LF.
#>

Set-StrictMode -Version Latest

$utf8NoBomEncodingSupportPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

function Get-TextFileLineContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $raw = [System.IO.File]::ReadAllText($Path)
    $eolSequence = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $hadTrailingNewline = $raw.EndsWith("`n")
    $lines = [System.Collections.Generic.List[string]]@($raw -split "`r`n|`n")

    return [pscustomobject]@{
        Lines = $lines
        EolSequence = $eolSequence
        HadTrailingNewline = $hadTrailingNewline
    }
}

function Write-TextFilePreservingEol {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$FileContext
    )

    if ($null -eq $FileContext.Lines) {
        throw 'BLOCK: FileContext.Lines missing'
    }

    if ([string]::IsNullOrEmpty($FileContext.EolSequence)) {
        throw 'BLOCK: FileContext.EolSequence missing'
    }

    $text = ($FileContext.Lines.ToArray() -join $FileContext.EolSequence)
    if ($FileContext.HadTrailingNewline -and -not $text.EndsWith($FileContext.EolSequence)) {
        $text += $FileContext.EolSequence
    }

    $utf8NoBom = (Get-Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}
