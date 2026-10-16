#requires -Version 7.4
<#
.SYNOPSIS
    Translates GeneXus `.xpw` text exports (GeneXus 7.0 and earlier) into the classic
    `<ExportFile><GXObject>` XML that GeneXusLegacyExportFileSupport.ps1 already consumes.

.DESCRIPTION
    Pure, in-memory translation: the result is an [xml] document with the classic shape
    (`/ExportFile/Model/Name`, `/ExportFile/KMW/*`, one `/ExportFile/GXObject/<Tag>` per object
    block, and `/ExportFile/Attributes/GXAtt/{Attribute,AttInfo,AttDoc}`). Nothing is written to
    disk; the sync and the inventory decide what to do with the document. Read-GeneXusXpwZipExport
    reads every `.xpw` entry of a `.zip` in memory (ordered by entry path, ordinal and
    case-insensitive) and merges them; it returns $null for a zip with no `.xpw` entry and fails
    closed for a zip that mixes `.xpw` and `.xml` entries.

    Grammar (Latin-1, CRLF; LF is accepted too):
    - Header lines before the first block: an optional first line `Model=  N: <name> (<kind>)`
      (becomes `Model/Name`) and at most two free-text lines (ignored). A file may have no header.
    - A block opens with `:Tag` and closes with `:eTag` at the same indent; nesting adds exactly
      2 spaces per level. A qualified tag `:Att:Font` closes with `:eFont` and becomes `<Att_Font>`.
    - Property lines sit at the block indent + 2: `Key=Value` becomes `<Key>Value</Key>` (the
      value is everything after the first `=`, may be empty, and keys may repeat); a bare `Key`
      becomes `<Key>Y</Key>`.
    - `Source`, `Rules`, `Events`, `Conditions`, and `Subroutines` are raw text blocks: their lines
      are kept verbatim (joined with LF, as an XML parser normalizes the classic CDATA) and only a
      line equal to `:e<Tag>` at the opening indent ends them. The text is emitted as CDATA.
    - Top-level `:Attribute`, `:AttInfo`, `:Doc` siblings form one attribute:
      `<GXAtt><Attribute/><AttInfo/><AttDoc/></GXAtt>` under `<Attributes>`. A top-level
      `:Formula` between them (where GeneXus writes an attribute's formula) becomes its own
      `<GXObject><Formula/></GXObject>` and does not break the attribute.
    - A top-level `:KMW` block is the export header (`/ExportFile/KMW`); every other top-level
      block is an object (`<GXObject><Tag/></GXObject>`).

    Fail-closed, naming the line: an unclosed block, a close that does not match the open tag,
    wrong indentation, a line that is neither a block line, a property line, nor raw content, a
    malformed `Model=` header, too many header lines, an `AttInfo`/`Doc` without its `Attribute`,
    a character XML cannot hold, input with no block, and (when merging) two different models or
    KMW headers. Content is never silently dropped.

    Doc owner: 01k-legacy-element-registry.md (the classic shape the result must match).
#>

Set-StrictMode -Version Latest

$script:XpwLatin1CodePage = 28591
$script:XpwRawBlockTags = @('Source', 'Rules', 'Events', 'Conditions', 'Subroutines')
$script:XpwAttributeBlockTags = @('Attribute', 'AttInfo', 'Doc')
$script:XpwFormulaBlockTag = 'Formula'
$script:XpwOpenPattern = '^:([A-Za-z][A-Za-z0-9_]*)(?::([A-Za-z][A-Za-z0-9_]*))?$'
$script:XpwClosePattern = '^:e([A-Z][A-Za-z0-9_]*)$'
$script:XpwPropertyPattern = '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
$script:XpwBareKeyPattern = '^([A-Za-z_][A-Za-z0-9_]*)$'
$script:XpwModelPattern = '^Model=\s*(\d+):\s*(.+?)\s*\(([^()]*)\)\s*$'
$script:XpwMaxFreeHeaderLines = 2

function Get-GeneXusXpwLatin1Encoding {
    return [System.Text.Encoding]::GetEncoding($script:XpwLatin1CodePage)
}

function New-GeneXusXpwError {
    param([string]$SourceName, [int]$LineNumber, [string]$Reason)
    return [System.IO.InvalidDataException]::new(("XPW '{0}' line {1}: {2}" -f $SourceName, $LineNumber, $Reason))
}

function Split-GeneXusXpwLines {
    <# Splits on CRLF or LF; a final terminator does not add an empty line. A lone CR stays in the line. #>
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return , ([string[]]@()) }
    $lines = [System.Text.RegularExpressions.Regex]::Split($Text, '\r?\n')
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '' -and ($Text.EndsWith("`n"))) {
        $lines = $lines[0..($lines.Count - 2)]
    }
    return , ([string[]]$lines)
}

function Assert-GeneXusXpwXmlChars {
    param([string]$Value, [string]$SourceName, [int]$LineNumber)
    try { [void][System.Xml.XmlConvert]::VerifyXmlChars($Value) }
    catch { throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $LineNumber -Reason 'a character XML cannot hold (a control character); the line cannot be translated without losing it.') }
}

function ConvertFrom-GeneXusXpwTextToParts {
    <#
        Parses one `.xpw` text into its parts on -Document (elements not yet attached):
        { ModelName, ModelLine, Kmw, Objects[], Attributes[] }.
    #>
    param(
        [System.Xml.XmlDocument]$Document,
        [AllowEmptyString()][string]$Text,
        [string]$SourceName
    )

    $lines = Split-GeneXusXpwLines -Text $Text
    $modelName = $null
    $modelLine = 0
    $kmw = $null
    $objects = New-Object System.Collections.Generic.List[System.Xml.XmlElement]
    $attributes = New-Object System.Collections.Generic.List[System.Xml.XmlElement]

    # Header: lines before the first top-level block line.
    $index = 0
    $freeHeaderLines = 0
    while ($index -lt $lines.Count -and $lines[$index] -notmatch $script:XpwOpenPattern) {
        $lineNumber = $index + 1
        $line = $lines[$index]
        if ($index -eq 0 -and $line.StartsWith('Model=')) {
            $match = [regex]::Match($line, $script:XpwModelPattern)
            if (-not $match.Success) {
                throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "malformed Model header (expected 'Model=  N: <name> (<kind>)').")
            }
            $modelName = $match.Groups[2].Value
            Assert-GeneXusXpwXmlChars -Value $modelName -SourceName $SourceName -LineNumber $lineNumber
            $modelLine = $lineNumber
        }
        else {
            $freeHeaderLines++
            if ($freeHeaderLines -gt $script:XpwMaxFreeHeaderLines) {
                throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "more than $($script:XpwMaxFreeHeaderLines) free-text header lines before the first block; the line is neither a header line nor a block line.")
            }
        }
        $index++
    }
    if ($index -ge $lines.Count) {
        throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber ([Math]::Max(1, $lines.Count)) -Reason 'no block found in the input.')
    }

    # Blocks.
    $stack = New-Object System.Collections.Generic.List[object]
    $rawLines = $null
    $currentAttribute = $null
    $currentAttributeStage = 0

    for (; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = $lines[$index]
        $frame = if ($stack.Count -gt 0) { $stack[$stack.Count - 1] } else { $null }

        if ($null -ne $frame -and $frame.IsRaw) {
            if ($line -ceq $frame.Terminator) {
                $rawText = $rawLines -join "`n"
                if ($rawText.Length -gt 0) {
                    Assert-GeneXusXpwXmlChars -Value $rawText -SourceName $SourceName -LineNumber $frame.LineNumber
                    if ($rawText.Contains(']]>')) {
                        [void]$frame.Element.AppendChild($Document.CreateTextNode($rawText))
                    }
                    else {
                        [void]$frame.Element.AppendChild($Document.CreateCDataSection($rawText))
                    }
                }
                $rawLines = $null
            }
            else {
                $rawLines.Add($line) | Out-Null
                continue
            }
        }
        else {
            $depthIndent = if ($null -eq $frame) { 0 } else { $frame.Indent + 2 }
            $spaces = $line.Length - $line.TrimStart(' ').Length
            $rest = $line.Substring($spaces)

            $closeMatch = [regex]::Match($rest, $script:XpwClosePattern)
            if ($closeMatch.Success) {
                if ($null -eq $frame) {
                    throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "close ':e$($closeMatch.Groups[1].Value)' does not match any open block.")
                }
                if ($spaces -ne $frame.Indent) {
                    throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "wrong indentation: expected $($frame.Indent) spaces to close ':$($frame.Tag)' (opened at line $($frame.LineNumber)), found $spaces.")
                }
                if ($closeMatch.Groups[1].Value -cne $frame.CloseName) {
                    throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "close ':e$($closeMatch.Groups[1].Value)' does not match the open block ':$($frame.Tag)' (opened at line $($frame.LineNumber)).")
                }
            }
            else {
                $openMatch = [regex]::Match($rest, $script:XpwOpenPattern)
                if ($openMatch.Success) {
                    if ($spaces -ne $depthIndent) {
                        throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "wrong indentation: expected $depthIndent spaces for block ':$($openMatch.Groups[1].Value)', found $spaces.")
                    }
                    $qualifier = $openMatch.Groups[1].Value
                    $closeName = if ($openMatch.Groups[2].Success) { $openMatch.Groups[2].Value } else { $qualifier }
                    $tag = $rest.Substring(1)
                    $elementName = if ($openMatch.Groups[2].Success) { '{0}_{1}' -f $qualifier, $closeName } else { $qualifier }
                    $isRaw = (-not $openMatch.Groups[2].Success) -and ($script:XpwRawBlockTags -ccontains $closeName)
                    $stack.Add([pscustomobject]@{
                        Tag        = $tag
                        CloseName  = $closeName
                        Indent     = $spaces
                        LineNumber = $lineNumber
                        Element    = $Document.CreateElement($elementName)
                        IsRaw      = $isRaw
                        Terminator = (' ' * $spaces) + ':e' + $closeName
                    }) | Out-Null
                    if ($isRaw) { $rawLines = New-Object System.Collections.Generic.List[string] }
                    continue
                }

                $propertyMatch = [regex]::Match($rest, $script:XpwPropertyPattern)
                $bareMatch = [regex]::Match($rest, $script:XpwBareKeyPattern)
                if ($null -ne $frame -and ($propertyMatch.Success -or $bareMatch.Success)) {
                    if ($spaces -ne $depthIndent) {
                        throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "wrong indentation: expected $depthIndent spaces for a property of ':$($frame.Tag)' (opened at line $($frame.LineNumber)), found $spaces.")
                    }
                    if ($propertyMatch.Success) {
                        $key = $propertyMatch.Groups[1].Value
                        $value = $propertyMatch.Groups[2].Value
                    }
                    else {
                        $key = $bareMatch.Groups[1].Value
                        $value = 'Y'
                    }
                    Assert-GeneXusXpwXmlChars -Value $value -SourceName $SourceName -LineNumber $lineNumber
                    $property = $Document.CreateElement($key)
                    if ($value.Length -gt 0) { [void]$property.AppendChild($Document.CreateTextNode($value)) }
                    [void]$frame.Element.AppendChild($property)
                    continue
                }

                $where = if ($null -eq $frame) { 'outside any block' } else { "inside ':$($frame.Tag)' (opened at line $($frame.LineNumber))" }
                throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $lineNumber -Reason "the line is neither a block line, a property line, nor raw content ($where).")
            }
        }

        # Close the current frame (a matching close line or a raw terminator).
        $stack.RemoveAt($stack.Count - 1)
        if ($stack.Count -gt 0) {
            [void]$stack[$stack.Count - 1].Element.AppendChild($frame.Element)
            continue
        }

        # A top-level block just closed: dispatch it.
        $topTag = $frame.Element.LocalName
        if ($topTag -ceq 'KMW') {
            if ($null -ne $kmw) {
                throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $frame.LineNumber -Reason 'a second :KMW header block.')
            }
            $kmw = $frame.Element
            $currentAttribute = $null
        }
        elseif ($script:XpwAttributeBlockTags -ccontains $topTag) {
            if ($topTag -ceq 'Attribute') {
                $currentAttribute = $Document.CreateElement('GXAtt')
                [void]$currentAttribute.AppendChild($frame.Element)
                $currentAttributeStage = 1
                $attributes.Add($currentAttribute) | Out-Null
            }
            elseif ($topTag -ceq 'AttInfo') {
                if ($null -eq $currentAttribute -or $currentAttributeStage -ne 1) {
                    throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $frame.LineNumber -Reason ':AttInfo must follow its :Attribute block directly.')
                }
                [void]$currentAttribute.AppendChild($frame.Element)
                $currentAttributeStage = 2
            }
            else {
                if ($null -eq $currentAttribute -or $currentAttributeStage -eq 3) {
                    throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $frame.LineNumber -Reason ':Doc must follow its :Attribute (and :AttInfo) block directly.')
                }
                $attDoc = $Document.CreateElement('AttDoc')
                while ($frame.Element.HasChildNodes) { [void]$attDoc.AppendChild($frame.Element.FirstChild) }
                [void]$currentAttribute.AppendChild($attDoc)
                $currentAttributeStage = 3
            }
        }
        else {
            $gxObject = $Document.CreateElement('GXObject')
            [void]$gxObject.AppendChild($frame.Element)
            $objects.Add($gxObject) | Out-Null
            # A top-level :Formula sits between :AttInfo and :Doc of the attribute it computes (every
            # sample): it becomes an object of its own, and the attribute's :Doc still joins its GXAtt.
            $keepsAttributeOpen = ($topTag -ceq $script:XpwFormulaBlockTag) -and ($null -ne $currentAttribute) -and ($currentAttributeStage -lt 3)
            if (-not $keepsAttributeOpen) { $currentAttribute = $null }
        }
    }

    if ($stack.Count -gt 0) {
        $open = $stack[$stack.Count - 1]
        throw (New-GeneXusXpwError -SourceName $SourceName -LineNumber $open.LineNumber -Reason "unclosed block ':$($open.Tag)' (no ':e$($open.CloseName)' at indent $($open.Indent) before the end of input).")
    }

    return [pscustomobject]@{
        ModelName  = $modelName
        ModelLine  = $modelLine
        Kmw        = $kmw
        Objects    = @($objects.ToArray())
        Attributes = @($attributes.ToArray())
    }
}

function Merge-GeneXusXpwExportText {
    <#
        Translates one or more `.xpw` texts (for example the 1997 layout: an objects file and a
        separate attributes file) into ONE classic ExportFile [xml] document. Objects and attributes
        keep input order. Two different Model names or two different KMW blocks fail closed.
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Text,
        [string[]]$SourceName
    )

    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $true
    $root = $document.CreateElement('ExportFile')
    [void]$document.AppendChild($root)

    $modelName = $null
    $modelSource = $null
    $kmw = $null
    $kmwSource = $null
    $objects = New-Object System.Collections.Generic.List[System.Xml.XmlElement]
    $attributes = New-Object System.Collections.Generic.List[System.Xml.XmlElement]

    for ($i = 0; $i -lt $Text.Count; $i++) {
        $name = if ($null -ne $SourceName -and $i -lt $SourceName.Count -and -not [string]::IsNullOrWhiteSpace($SourceName[$i])) { $SourceName[$i] } else { "text $($i + 1)" }
        $parts = ConvertFrom-GeneXusXpwTextToParts -Document $document -Text $Text[$i] -SourceName $name
        if ($null -ne $parts.ModelName) {
            if ($null -ne $modelName -and $modelName -cne $parts.ModelName) {
                throw (New-GeneXusXpwError -SourceName $name -LineNumber $parts.ModelLine -Reason "Model '$($parts.ModelName)' differs from Model '$modelName' of '$modelSource'; the files belong to different models.")
            }
            $modelName = $parts.ModelName
            $modelSource = $name
        }
        if ($null -ne $parts.Kmw) {
            if ($null -ne $kmw -and $kmw.OuterXml -cne $parts.Kmw.OuterXml) {
                throw ("XPW '{0}': its :KMW header differs from the :KMW header of '{1}'." -f $name, $kmwSource)
            }
            if ($null -eq $kmw) {
                $kmw = $parts.Kmw
                $kmwSource = $name
            }
        }
        foreach ($object in $parts.Objects) { $objects.Add($object) | Out-Null }
        foreach ($attribute in $parts.Attributes) { $attributes.Add($attribute) | Out-Null }
    }

    if ($null -ne $modelName) {
        $model = $document.CreateElement('Model')
        $modelNameElement = $document.CreateElement('Name')
        [void]$modelNameElement.AppendChild($document.CreateTextNode($modelName))
        [void]$model.AppendChild($modelNameElement)
        [void]$root.AppendChild($model)
    }
    if ($null -ne $kmw) { [void]$root.AppendChild($kmw) }
    foreach ($object in $objects) { [void]$root.AppendChild($object) }
    if ($attributes.Count -gt 0) {
        $attributesElement = $document.CreateElement('Attributes')
        foreach ($attribute in $attributes) { [void]$attributesElement.AppendChild($attribute) }
        [void]$root.AppendChild($attributesElement)
    }
    return , $document
}

function ConvertFrom-GeneXusXpwText {
    <# Translates one already-decoded `.xpw` text into a classic ExportFile [xml] document. #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$SourceName = 'text'
    )
    return , (Merge-GeneXusXpwExportText -Text @($Text) -SourceName @($SourceName))
}

function Read-GeneXusXpwExportFile {
    <# Reads one `.xpw` file as Latin-1 (code page 28591) and translates it. #>
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "XPW file not found: $Path"
    }
    $text = [System.IO.File]::ReadAllText($Path, (Get-GeneXusXpwLatin1Encoding))
    return , (ConvertFrom-GeneXusXpwText -Text $text -SourceName ([System.IO.Path]::GetFileName($Path)))
}

function Test-GeneXusXpwInputPath {
    <# True when -Path is a `.xpw` file (by extension, case-insensitive). #>
    param([Parameter(Mandatory = $true)][string]$Path)
    return ([System.IO.Path]::GetExtension($Path) -ieq '.xpw')
}

function Read-GeneXusXpwZipExport {
    <#
        Reads every `.xpw` entry of a `.zip` (for example the 1997 layout: an objects file such as
        `gxw.xpw` and an attributes-only file such as `att.xpw`) and merges them into ONE classic
        ExportFile document with Merge-GeneXusXpwExportText. Entries are read in memory (never
        extracted), as Latin-1, in a deterministic order: by entry path, ordinal and
        case-insensitive. The merge places objects before attributes whatever the order, so the
        order only fixes the sequence of objects and of attributes.

        Returns $null when the zip holds no `.xpw` entry, so the caller keeps its existing behaviour
        for that zip. A zip holding both `.xpw` and `.xml` entries fails closed: it is neither a
        `.xpw` export nor an XML export.

        Result: { Document, EntryNames }.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $files = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
        $xpwEntries = @($files | Where-Object { [System.IO.Path]::GetExtension($_.FullName) -ieq '.xpw' })
        if ($xpwEntries.Count -eq 0) { return $null }
        $xmlEntries = @($files | Where-Object { [System.IO.Path]::GetExtension($_.FullName) -ieq '.xml' })
        if ($xmlEntries.Count -gt 0) {
            throw ("XPW zip '{0}' mixes .xpw and .xml entries ({1}; {2}); it is neither a .xpw export nor an XML export. Provide the .xpw files and the XML export separately." -f $Path, (($xpwEntries | ForEach-Object { $_.FullName }) -join ', '), (($xmlEntries | ForEach-Object { $_.FullName }) -join ', '))
        }

        $ordered = [System.Collections.Generic.List[System.IO.Compression.ZipArchiveEntry]]::new()
        foreach ($entry in $xpwEntries) { $ordered.Add($entry) }
        $ordered.Sort([System.Comparison[System.IO.Compression.ZipArchiveEntry]] { param($a, $b) [System.StringComparer]::OrdinalIgnoreCase.Compare($a.FullName, $b.FullName) })

        $encoding = Get-GeneXusXpwLatin1Encoding
        $texts = [System.Collections.Generic.List[string]]::new()
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $ordered) {
            $stream = $entry.Open()
            try {
                $reader = [System.IO.StreamReader]::new($stream, $encoding, $false)
                try { $texts.Add($reader.ReadToEnd()) } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
            $names.Add($entry.FullName)
        }
    } finally {
        $zip.Dispose()
    }

    $document = Merge-GeneXusXpwExportText -Text $texts.ToArray() -SourceName $names.ToArray()
    return [pscustomobject]@{
        Document   = $document
        EntryNames = @($names.ToArray())
    }
}
