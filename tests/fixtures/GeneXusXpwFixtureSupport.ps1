#requires -Version 7.4
<#
.SYNOPSIS
    Builder for synthetic GeneXus `.xpw` text exports (GeneXus 7.0 and earlier) used by self-tests.

.DESCRIPTION
    This file is versioned as UTF-8/LF. The fixtures are built as line arrays, so every tab,
    trailing space, and blank line is explicit, and written on the fly as Latin-1 (code page
    28591) bytes with CRLF (or LF) line terminators, like a real `.xpw`.

    Every object, attribute, model, and path name here is invented: no content comes from public
    samples or from a real export.

    Coverage of the objects fixture:
    - `Model=` header with a free-text line and a `:KMW` header block;
    - Transaction with nested blocks, a value containing `=`, an empty value, a repeated key, bare
      keys, a qualified tag (`:Att:Font` closed by `:eFont`), and raw `Rules` and `Events` blocks
      with a blank line, a tab, trailing spaces, and lines starting with `:` that are not the
      terminator;
    - Procedure with code at `Layout/Block/CodeBlock/Source`;
    - Work Panel with raw `Conditions` and `Subroutines` blocks;
    - Report, Web Panel, Table, Folder, and Group (with a Subtype).
    Coverage of the attributes fixture (the 1997 layout keeps attributes in their own file, with no
    header): two `:Attribute`/`:AttInfo`/`:Doc` triplets, one of them a domain.
    Coverage of the sync fixture (Get-GeneXusXpwSyncFixtureLines, for the sync and index tests):
    KMW 1.5, a Procedure whose CodeBlock Source reads an attribute and calls another Procedure with
    the classic prefix, a Work Panel, a Prompt, a Menu, and a top-level Formula. New-GeneXusXpwFixtureZip
    writes named line arrays into a zip (the 1997 split layout, or a mixed zip).
#>

Set-StrictMode -Version Latest

function Get-GeneXusXpwFixtureAccentedDescription {
    <# The Latin-1 accented Transaction description carried by the objects fixture. #>
    return 'Gestión de clientes y facturación'
}

function Get-GeneXusXpwFixtureRulesLines {
    <# Raw content of the Transaction Rules block, line by line (verbatim, byte for byte). #>
    return @(
        'noaccept(CustId);',
        '',
        "`tdefault(CustName, 'none');",
        "error('Missing customer') if null(CustId);   ",
        ':eRule',
        ':eRules',
        '    :eRules'
    )
}

function Get-GeneXusXpwFixtureEventsLines {
    return @(
        "Event 'Recalc'",
        "`tcall(PrcTotals, CustId)",
        'EndEvent'
    )
}

function Get-GeneXusXpwFixtureProcedureSourceLines {
    return @(
        'for each',
        "`twhere CustId = &CustId",
        '    &Total = &Total + InvAmount',
        'endfor'
    )
}

function Get-GeneXusXpwFixtureConditionsLines {
    return @('CustName >= &Name;')
}

function Get-GeneXusXpwFixtureSubroutinesLines {
    return @(
        "Sub 'SumUp'",
        "`tcall(PrcTotals, &CustId)",
        'EndSub'
    )
}

function Get-GeneXusXpwObjectsFixtureLines {
    <# The objects file: header, KMW, and one block per object type. #>
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange([string[]]@(
        'Model=  3: Demo Store: North (Design)',
        'Demo Store sample model',
        ':KMW',
        '  MajorVersion=1',
        '  MinorVersion=4',
        '  Path=C:\Models\DemoStore',
        ':eKMW',
        ':Transaction',
        '  :Info',
        '    Name=TrnCustomer',
        ('    Description=' + (Get-GeneXusXpwFixtureAccentedDescription)),
        '    Folder=Sales',
        '  :eInfo',
        '  LastUpdate=2001-02-03 04:05:06',
        '  Formula=CustTotal=sum(InvAmount) if CustId>0;',
        '  Comment=',
        '  Tag=first',
        '  Tag=second',
        '  :Form',
        '    IsMain',
        '    :Att:Font',
        '      Name=Arial',
        '      Bold',
        '    :eFont',
        '  :eForm',
        '  :Rules'
    ))
    $lines.AddRange([string[]](Get-GeneXusXpwFixtureRulesLines))
    $lines.AddRange([string[]]@('  :eRules', '  :Events'))
    $lines.AddRange([string[]](Get-GeneXusXpwFixtureEventsLines))
    $lines.AddRange([string[]]@(
        '  :eEvents',
        ':eTransaction',
        ':Procedure',
        '  :Info',
        '    Name=PrcTotals',
        '  :eInfo',
        '  LastUpdate=2001-02-04 08:00:00',
        '  :Layout',
        '    :Block',
        '      :CodeBlock',
        '        :Source'
    ))
    $lines.AddRange([string[]](Get-GeneXusXpwFixtureProcedureSourceLines))
    $lines.AddRange([string[]]@(
        '        :eSource',
        '      :eCodeBlock',
        '    :eBlock',
        '  :eLayout',
        ':eProcedure',
        ':WorkPanel',
        '  :Info',
        '    Name=WkCustomers',
        '  :eInfo',
        '  :Conditions'
    ))
    $lines.AddRange([string[]](Get-GeneXusXpwFixtureConditionsLines))
    $lines.AddRange([string[]]@('  :eConditions', '  :Subroutines'))
    $lines.AddRange([string[]](Get-GeneXusXpwFixtureSubroutinesLines))
    $lines.AddRange([string[]]@(
        '  :eSubroutines',
        ':eWorkPanel',
        ':Report',
        '  :Info',
        '    Name=RptInvoices',
        '  :eInfo',
        ':eReport',
        ':WebPanel',
        '  :Info',
        '    Name=WbCustomer',
        '  :eInfo',
        ':eWebPanel',
        ':Table',
        '  :Info',
        '    Name=TblCustomer',
        '  :eInfo',
        ':eTable',
        ':Folder',
        '  :Info',
        '    Name=Sales',
        '  :eInfo',
        ':eFolder',
        ':Group',
        '  :Info',
        '    Name=GrpBilling',
        '  :eInfo',
        '  :Subtype',
        '    Name=BillCustId',
        '    Supertype=CustId',
        '  :eSubtype',
        ':eGroup'
    ))
    return @($lines.ToArray())
}

function Get-GeneXusXpwAttributesFixtureLines {
    <# The attributes file of the 1997 layout: no header, attribute triplets only. #>
    return @(
        ':Attribute',
        '  Id=1',
        '  Name=CustId',
        '  Title=Customer',
        '  Length=5',
        ':eAttribute',
        ':AttInfo',
        '  Domain=CustCode',
        '  :Font',
        '  :eFont',
        ':eAttInfo',
        ':Doc',
        ':eDoc',
        ':Attribute',
        '  Id=2',
        '  Name=_CustCode',
        '  Title=Customer code',
        ':eAttribute',
        ':AttInfo',
        ':eAttInfo',
        ':Doc',
        '  :Source',
        'Customer code domain.',
        '  :eSource',
        ':eDoc'
    )
}

function Get-GeneXusXpwSyncFixtureLines {
    <#
        A single-file export for the sync and index tests: KMW 1.5 (no Build), a Transaction, a
        Procedure whose CodeBlock Source reads attribute OrdAmount and calls PrcTarget with the
        classic prefix, the called Procedure, a Work Panel, a Prompt, a Menu, and two attributes,
        one of them computed by a top-level Formula (between its AttInfo and Doc).
    #>
    return @(
        'Model=  1: Invented Shop (Design)',
        ':KMW',
        '  MajorVersion=1',
        '  MinorVersion=5',
        '  Path=C:\Models\InventedShop',
        ':eKMW',
        ':Transaction',
        '  :Info',
        '    Name=TrnOrder',
        '  :eInfo',
        '  LastUpdate=2002-03-04 05:06:07',
        ':eTransaction',
        ':Procedure',
        '  :Info',
        '    Name=PrcCaller',
        '  :eInfo',
        '  LastUpdate=2002-03-05 09:10:11',
        '  :Layout',
        '    :Block',
        '      :CodeBlock',
        '        :Source',
        'for each',
        "`t&Total = &Total + OrdAmount",
        'endfor',
        'call(PPrcTarget, &Total)',
        '        :eSource',
        '      :eCodeBlock',
        '    :eBlock',
        '  :eLayout',
        ':eProcedure',
        ':Procedure',
        '  :Info',
        '    Name=PrcTarget',
        '  :eInfo',
        ':eProcedure',
        ':WorkPanel',
        '  :Info',
        '    Name=WkOrders',
        '  :eInfo',
        ':eWorkPanel',
        ':Prompt',
        '  :Info',
        '    Name=PmtOrder',
        '  :eInfo',
        ':ePrompt',
        ':Menu',
        '  :Info',
        '    Name=MnuMain',
        '  :eInfo',
        ':eMenu',
        ':Attribute',
        '  Id=1',
        '  Name=OrdId',
        ':eAttribute',
        ':AttInfo',
        ':eAttInfo',
        ':Doc',
        ':eDoc',
        ':Attribute',
        '  Id=2',
        '  Name=OrdAmount',
        ':eAttribute',
        ':AttInfo',
        ':eAttInfo',
        ':Formula',
        '  Name=OrdAmount',
        '  :Source',
        'sum(LineAmount)',
        '  :eSource',
        ':eFormula',
        ':Doc',
        ':eDoc'
    )
}

function New-GeneXusXpwFixtureZip {
    <# Writes a zip holding -Entries (an ordered map of entry name -> line array, written as Latin-1 CRLF). #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.Specialized.OrderedDictionary]$Entries
    )
    Add-Type -AssemblyName System.IO.Compression
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    try {
        $zip = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries.Keys) {
                $bytes = $latin1.GetBytes((Join-GeneXusXpwFixtureLines -Lines ([string[]]$Entries[$name])))
                $entryStream = $zip.CreateEntry($name).Open()
                try { $entryStream.Write($bytes, 0, $bytes.Length) } finally { $entryStream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
    return $Path
}

function Join-GeneXusXpwFixtureLines {
    <# Joins fixture lines into `.xpw` text with a terminator after every line. #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [ValidateSet('CRLF', 'LF')][string]$Eol = 'CRLF'
    )
    $newLine = if ($Eol -eq 'CRLF') { "`r`n" } else { "`n" }
    return (($Lines -join $newLine) + $newLine)
}

function New-GeneXusXpwFixtureFile {
    <# Writes the lines to -Path as Latin-1 bytes and returns the path. #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [ValidateSet('CRLF', 'LF')][string]$Eol = 'CRLF'
    )
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir)
    }
    $text = Join-GeneXusXpwFixtureLines -Lines $Lines -Eol $Eol
    [System.IO.File]::WriteAllBytes($Path, [System.Text.Encoding]::GetEncoding(28591).GetBytes($text))
    return $Path
}
