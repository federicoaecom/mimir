#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the `.xpw` translator (GeneXusXpwExportFileSupport.ps1), in isolation.

.DESCRIPTION
    Builds synthetic `.xpw` exports (tests/fixtures/GeneXusXpwFixtureSupport.ps1, Latin-1 bytes,
    CRLF, invented names) and checks one rule per assertion: the `Model=` header and `:KMW` block,
    nesting and child order, property values (with `=`, empty, repeated keys, bare keys), qualified
    tags, raw text blocks kept byte for byte, Procedure code at `Layout/Block/CodeBlock/Source`,
    attribute triplets as `GXAtt`, the 1997 merge of an objects file and an attributes file,
    Latin-1 reading, every fail-closed case with its line number, and that the translated document
    is accepted by the legacy export engine. Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $scriptsRoot 'GeneXusObjectTypeCatalogSupport.ps1')
. (Join-Path $scriptsRoot 'GeneXusLegacyExportFileSupport.ps1')
. (Join-Path $scriptsRoot 'GeneXusXpwExportFileSupport.ps1')
. (Join-Path $fixturesRoot 'GeneXusXpwFixtureSupport.ps1')

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -cne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-XpwFailure {
    <# The translation must throw, and the message must name the expected line number. #>
    param([string[]]$Lines, [int]$ExpectedLine, [string]$ExpectedFragment, [string]$Case)
    $text = Join-GeneXusXpwFixtureLines -Lines $Lines
    $message = $null
    try { [void](ConvertFrom-GeneXusXpwText -Text $text) } catch { $message = $_.Exception.Message }
    if ($null -eq $message) { throw "Fail-closed case '$Case' did not throw." }
    if ($message -notmatch ("\bline {0}\b" -f $ExpectedLine)) { throw "Fail-closed case '$Case' should name line $ExpectedLine; got: $message" }
    if (-not $message.Contains($ExpectedFragment)) { throw "Fail-closed case '$Case' should say '$ExpectedFragment'; got: $message" }
}

$objectsLines = Get-GeneXusXpwObjectsFixtureLines
$attributesLines = Get-GeneXusXpwAttributesFixtureLines
[xml]$doc = ConvertFrom-GeneXusXpwText -Text (Join-GeneXusXpwFixtureLines -Lines $objectsLines)

# --- Header: Model name (a colon inside the name is kept) and the KMW block ---
Assert-Equal $doc.DocumentElement.LocalName 'ExportFile' 'Root element.'
Assert-Equal $doc.SelectSingleNode('/ExportFile/Model/Name').InnerText 'Demo Store: North' 'Model name from the header.'
Assert-Equal $doc.SelectSingleNode('/ExportFile/KMW/MajorVersion').InnerText '1' 'KMW MajorVersion.'
Assert-Equal $doc.SelectSingleNode('/ExportFile/KMW/MinorVersion').InnerText '4' 'KMW MinorVersion.'
Assert-Equal $doc.SelectSingleNode('/ExportFile/KMW/Path').InnerText 'C:\Models\DemoStore' 'KMW Path.'
Assert-Equal @($doc.SelectNodes('/ExportFile/GXObject/KMW')).Count 0 'KMW must not become an object.'
Assert-Equal (Get-GeneXusLegacyModelNameFromPackage -XmlDocument $doc) 'Demo Store: North' 'Model name through the legacy reader.'

# --- One GXObject per top-level block, in file order, one child each ---
$objectTags = @($doc.SelectNodes('/ExportFile/GXObject') | ForEach-Object { @($_.ChildNodes)[0].LocalName }) -join ','
Assert-Equal $objectTags 'Transaction,Procedure,WorkPanel,Report,WebPanel,Table,Folder,Group' 'Object order.'
$trn = $doc.SelectSingleNode('/ExportFile/GXObject/Transaction')

# --- Nesting and child order ---
$trnChildren = @($trn.ChildNodes | ForEach-Object { $_.LocalName }) -join ','
Assert-Equal $trnChildren 'Info,LastUpdate,Formula,Comment,Tag,Tag,Form,Rules,Events' 'Transaction child order.'
Assert-Equal $trn.SelectSingleNode('./Info/Name').InnerText 'TrnCustomer' 'Nested Info/Name.'

# --- Property values ---
Assert-Equal $trn.SelectSingleNode('./Formula').InnerText 'CustTotal=sum(InvAmount) if CustId>0;' 'A value keeps everything after the first =.'
Assert-Equal $trn.SelectSingleNode('./Comment').InnerText '' 'An empty value.'
Assert-Equal (@($trn.SelectNodes('./Tag') | ForEach-Object { $_.InnerText }) -join ',') 'first,second' 'A repeated key keeps both values in order.'
Assert-Equal $trn.SelectSingleNode('./Form/IsMain').InnerText 'Y' 'A bare key means Y.'
Assert-Equal $trn.SelectSingleNode('./LastUpdate').InnerText '2001-02-03 04:05:06' 'LastUpdate property.'

# --- Qualified tag :Att:Font closed by :eFont ---
Assert-Equal $trn.SelectSingleNode('./Form/Att_Font/Name').InnerText 'Arial' 'Qualified tag becomes Att_Font.'
Assert-Equal $trn.SelectSingleNode('./Form/Att_Font/Bold').InnerText 'Y' 'Bare key inside a qualified block.'

# --- Raw text blocks: byte for byte, only the exact terminator ends them ---
Assert-Equal $trn.SelectSingleNode('./Rules').InnerText ((Get-GeneXusXpwFixtureRulesLines) -join "`n") 'Rules raw text (blank line, tab, trailing spaces, : lines).'
Assert-Equal $trn.SelectSingleNode('./Rules').FirstChild.NodeType ([System.Xml.XmlNodeType]::CDATA) 'Raw text is emitted as CDATA, like the classic XML.'
Assert-Equal $trn.SelectSingleNode('./Events').InnerText ((Get-GeneXusXpwFixtureEventsLines) -join "`n") 'Events raw text.'
$wkp = $doc.SelectSingleNode('/ExportFile/GXObject/WorkPanel')
Assert-Equal $wkp.SelectSingleNode('./Conditions').InnerText ((Get-GeneXusXpwFixtureConditionsLines) -join "`n") 'Conditions raw text.'
Assert-Equal $wkp.SelectSingleNode('./Subroutines').InnerText ((Get-GeneXusXpwFixtureSubroutinesLines) -join "`n") 'Subroutines raw text.'

# --- Procedure code at Layout/Block/CodeBlock/Source ---
$procSource = $doc.SelectSingleNode('/ExportFile/GXObject/Procedure/Layout/Block/CodeBlock/Source')
if ($null -eq $procSource) { throw 'Procedure code should sit at Layout/Block/CodeBlock/Source.' }
Assert-Equal $procSource.InnerText ((Get-GeneXusXpwFixtureProcedureSourceLines) -join "`n") 'Procedure Source raw text.'

# --- Latin-1 text read from a file, CRLF and LF ---
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('xpw-support-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path $tempRoot)
try {
    foreach ($eol in @('CRLF', 'LF')) {
        $path = New-GeneXusXpwFixtureFile -Path (Join-Path $tempRoot "objects-$eol.xpw") -Lines $objectsLines -Eol $eol
        [xml]$fromFile = Read-GeneXusXpwExportFile -Path $path
        Assert-Equal $fromFile.SelectSingleNode('/ExportFile/GXObject/Transaction/Info/Description').InnerText (Get-GeneXusXpwFixtureAccentedDescription) "Latin-1 accents preserved ($eol)."
        Assert-Equal $fromFile.SelectSingleNode('/ExportFile/GXObject/Transaction/Rules').InnerText ((Get-GeneXusXpwFixtureRulesLines) -join "`n") "Raw text from a file ($eol)."
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

# --- Attribute-only file (no header): triplets become GXAtt with AttDoc ---
[xml]$attDoc = ConvertFrom-GeneXusXpwText -Text (Join-GeneXusXpwFixtureLines -Lines $attributesLines)
Assert-Equal $attDoc.SelectSingleNode('/ExportFile/Model') $null 'No Model without a header.'
$gxAtts = @($attDoc.SelectNodes('/ExportFile/Attributes/GXAtt'))
Assert-Equal $gxAtts.Count 2 'One GXAtt per attribute triplet.'
Assert-Equal (@($gxAtts[0].ChildNodes | ForEach-Object { $_.LocalName }) -join ',') 'Attribute,AttInfo,AttDoc' 'GXAtt children (Doc renamed AttDoc).'
Assert-Equal $gxAtts[0].SelectSingleNode('./Attribute/Name').InnerText 'CustId' 'Attribute name.'
Assert-Equal $gxAtts[0].SelectSingleNode('./AttInfo/Domain').InnerText 'CustCode' 'AttInfo property.'
Assert-Equal $gxAtts[1].SelectSingleNode('./Attribute/Name').InnerText '_CustCode' 'A domain keeps its classic name.'
Assert-Equal $gxAtts[1].SelectSingleNode('./AttDoc/Source').InnerText 'Customer code domain.' 'AttDoc raw Source.'
Assert-Equal @($attDoc.SelectNodes('/ExportFile/GXObject')).Count 0 'Attributes never become objects.'

# --- A top-level :Formula between :AttInfo and :Doc is an object; the Doc still joins its attribute ---
$formulaLines = @(':Attribute', '  Name=CustTotal', ':eAttribute', ':AttInfo', ':eAttInfo', ':Formula', '  Name=CustTotal', '  :Source', 'sum(InvAmount)', '  :eSource', ':eFormula', ':Doc', ':eDoc')
[xml]$formulaDoc = ConvertFrom-GeneXusXpwText -Text (Join-GeneXusXpwFixtureLines -Lines $formulaLines)
Assert-Equal $formulaDoc.SelectSingleNode('/ExportFile/GXObject/Formula/Source').InnerText 'sum(InvAmount)' 'Formula object with its raw Source.'
Assert-Equal (@($formulaDoc.SelectSingleNode('/ExportFile/Attributes/GXAtt').ChildNodes | ForEach-Object { $_.LocalName }) -join ',') 'Attribute,AttInfo,AttDoc' 'The Doc after a Formula joins the attribute.'

# --- 1997 layout: objects file + attributes file merge into one export ---
[xml]$merged = Merge-GeneXusXpwExportText -Text @((Join-GeneXusXpwFixtureLines -Lines $objectsLines), (Join-GeneXusXpwFixtureLines -Lines $attributesLines))
Assert-Equal $merged.SelectSingleNode('/ExportFile/Model/Name').InnerText 'Demo Store: North' 'Merge keeps the Model.'
Assert-Equal @($merged.SelectNodes('/ExportFile/GXObject')).Count 8 'Merge keeps every object.'
Assert-Equal @($merged.SelectNodes('/ExportFile/Attributes/GXAtt')).Count 2 'Merge keeps every attribute.'
Assert-Equal (@($merged.DocumentElement.ChildNodes | ForEach-Object { $_.LocalName } | Select-Object -Unique) -join ',') 'Model,KMW,GXObject,Attributes' 'Merged document layout.'
$otherModel = @('Model=  4: Other Model (Design)') + @($attributesLines)
$threw = $false
try { [void](Merge-GeneXusXpwExportText -Text @((Join-GeneXusXpwFixtureLines -Lines $objectsLines), (Join-GeneXusXpwFixtureLines -Lines $otherModel))) } catch { $threw = $true }
if (-not $threw) { throw 'Merging files from two different models should fail closed.' }
$otherKmw = @(':KMW', '  MajorVersion=1', '  MinorVersion=5', ':eKMW') + @($attributesLines)
$kmwError = $null
try { [void](Merge-GeneXusXpwExportText -Text @((Join-GeneXusXpwFixtureLines -Lines $objectsLines), (Join-GeneXusXpwFixtureLines -Lines $otherKmw))) } catch { $kmwError = $_.Exception.Message }
if ($null -eq $kmwError) { throw 'Merging files with different :KMW headers should fail closed.' }
if ($kmwError -notmatch ':KMW header differs') { throw "The :KMW conflict should be named; got: $kmwError" }

# --- Accepted by the legacy export engine (registered tags only) ---
if (-not (Test-GeneXusLegacyExportFilePackage -XmlDocument $merged)) { throw 'The translated document should be a pure legacy package.' }
$catalog = (Resolve-GeneXusObjectTypeCatalogPaths -BaseCatalogPath (Join-Path $scriptsRoot 'gx-object-type-catalog.json')).MergedCatalog
$items = @((Get-GeneXusLegacyExportFileSyncItems -XmlDocument $merged -MergedCatalog $catalog -Registry (Get-GeneXusLegacyExportElementRegistry)).Items)
Assert-Equal $items.Count 10 'Legacy sync items (8 objects + 2 attributes).'
Assert-Equal (@($items | ForEach-Object { $_.LegacyElement }) -join ',') 'Transaction,Procedure,WorkPanel,Report,WebPanel,Table,Folder,Group,GXAtt,GXAtt' 'Legacy elements.'
$trnItem = @($items | Where-Object { $_.LegacyElement -eq 'Transaction' })[0]
Assert-Equal $trnItem.LogicalName 'TrnCustomer' 'Legacy item name.'
Assert-Equal $trnItem.Node.GetAttribute('lastUpdate') '2001-02-03T04:05:06.0000000Z' 'xpw LastUpdate parses as a classic date.'

# --- Fail closed, naming the line ---
Assert-XpwFailure -Case 'unclosed block' -ExpectedLine 1 -ExpectedFragment 'unclosed block' -Lines @(':Transaction', '  :Info', '    Name=TrnA', '  :eInfo')
Assert-XpwFailure -Case 'unclosed raw block' -ExpectedLine 2 -ExpectedFragment 'unclosed block' -Lines @(':Procedure', '  :Source', 'for each', ':eProcedure')
Assert-XpwFailure -Case 'mismatched close' -ExpectedLine 3 -ExpectedFragment 'does not match' -Lines @(':Transaction', '  :Info', '  :eForm', ':eTransaction')
Assert-XpwFailure -Case 'close at a wrong indent' -ExpectedLine 3 -ExpectedFragment 'indentation' -Lines @(':Transaction', '  :Info', '    :eInfo', ':eTransaction')
Assert-XpwFailure -Case 'block at a wrong indent' -ExpectedLine 2 -ExpectedFragment 'indentation' -Lines @(':Transaction', '   :Info', '   :eInfo', ':eTransaction')
Assert-XpwFailure -Case 'property at a wrong indent' -ExpectedLine 3 -ExpectedFragment 'indentation' -Lines @(':Transaction', '  :Info', '      Name=TrnA', '  :eInfo', ':eTransaction')
Assert-XpwFailure -Case 'unknown line shape' -ExpectedLine 3 -ExpectedFragment 'neither' -Lines @(':Transaction', '  :Info', '    ?? not a property', '  :eInfo', ':eTransaction')
Assert-XpwFailure -Case 'property outside any block' -ExpectedLine 3 -ExpectedFragment 'neither' -Lines @(':Folder', ':eFolder', 'Name=Loose')
Assert-XpwFailure -Case 'malformed Model header' -ExpectedLine 1 -ExpectedFragment 'Model' -Lines @('Model=no number here', ':Folder', ':eFolder')
Assert-XpwFailure -Case 'too many header lines' -ExpectedLine 4 -ExpectedFragment 'header' -Lines @('Model=  1: Demo (Design)', 'first note', 'second note', 'third note', ':Folder', ':eFolder')
Assert-XpwFailure -Case 'AttInfo without Attribute' -ExpectedLine 1 -ExpectedFragment 'AttInfo' -Lines @(':AttInfo', ':eAttInfo')
Assert-XpwFailure -Case 'no block at all' -ExpectedLine 1 -ExpectedFragment 'no block' -Lines @('Model=  1: Demo (Design)')

Write-Output 'GENEXUS_XPW_EXPORT_FILE_SUPPORT_SELFTEST_OK'
exit 0
