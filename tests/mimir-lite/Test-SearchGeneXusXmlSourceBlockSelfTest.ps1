#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBomEncodingSupportPath = Join-Path ((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')) 'Utf8NoBomEncodingSupport.ps1'
if (-not (Test-Path -LiteralPath $utf8NoBomEncodingSupportPath -PathType Leaf)) {
    throw "UTF-8 no-BOM encoding support script not found: $utf8NoBomEncodingSupportPath"
}
. $utf8NoBomEncodingSupportPath

$scriptUnderTest = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Search-GeneXusXmlSourceBlock.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-source-search-selftest-' + [guid]::NewGuid().ToString('N'))
$samplePath = Join-Path $tempRoot 'wpSample.xml'
$packagePath = Join-Path $tempRoot 'package.xml'

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Read-JsonArray {
    param([string[]]$Text)

    $joined = ($Text -join [Environment]::NewLine)
    if ([string]::IsNullOrWhiteSpace($joined)) {
        return @()
    }
    return @($joined | ConvertFrom-Json)
}

try {
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    $sampleXml = @(
        '<Object type="d82625fd-5892-40b0-99c9-5c8559c197fc" name="wpSample">',
        '  <Part type="layout">',
        '    <Source><![CDATA[<GxMultiForm><Form><detail><layout><data attribute="&praConsultaSerie" labelCaption="Serie" /></layout></detail></Form></GxMultiForm>]]></Source>',
        '  </Part>',
        '  <Part type="events">',
        '    <Source><![CDATA[Event Start',
        '  &praConsultaSerie = ''001''',
        'EndEvent',
        ']]></Source>',
        '  </Part>',
        '</Object>'
    ) -join "`n"
    [System.IO.File]::WriteAllText($samplePath, $sampleXml, (Get-Utf8NoBomEncoding))

    $packageXml = @(
        '<ExportFile>',
        '  <Objects>',
        '    <Object type="x" name="wpFirst">',
        '      <Source><![CDATA[Event Start',
        '  &outra = 1',
        'EndEvent',
        ']]></Source>',
        '    </Object>',
        '    <Object type="x" name="wpSecond">',
        '      <Source><![CDATA[Event Start',
        '  &praConsultaSerie = ''002''',
        'EndEvent',
        ']]></Source>',
        '    </Object>',
        '  </Objects>',
        '</ExportFile>'
    ) -join "`n"
    [System.IO.File]::WriteAllText($packagePath, $packageXml, (Get-Utf8NoBomEncoding))

    $events = Read-JsonArray -Text (& $scriptUnderTest -Path $samplePath -Pattern 'praConsultaSerie' -Block events -AsJson)
    Assert-Equal -Actual $events.Count -Expected 1 -Message 'events should find only the match in the code-behind.'
    Assert-Equal -Actual $events[0].block -Expected 'events' -Message 'events should classify the block correctly.'
    Assert-Equal -Actual $events[0].xmlLine -Expected 7 -Message 'events should report the correct internal line.'

    $layout = Read-JsonArray -Text (& $scriptUnderTest -Path $samplePath -Pattern 'praConsultaSerie' -Block layout -AsJson)
    Assert-Equal -Actual $layout.Count -Expected 1 -Message 'layout should find only the match in the GxMultiForm.'
    Assert-Equal -Actual $layout[0].block -Expected 'layout' -Message 'layout should classify the GxMultiForm correctly.'
    if ($layout[0].preview.Length -gt 183) {
        throw 'the layout preview should stay compact.'
    }

    $code = Read-JsonArray -Text (& $scriptUnderTest -Path $samplePath -Pattern 'praConsultaSerie' -Block code -AsJson)
    Assert-Equal -Actual $code.Count -Expected 1 -Message 'code should include events and exclude layout.'
    Assert-Equal -Actual $code[0].block -Expected 'events' -Message 'code should preserve the block''s real classification.'

    $package = Read-JsonArray -Text (& $scriptUnderTest -Path $packagePath -Pattern 'praConsultaSerie' -Block events -AsJson)
    Assert-Equal -Actual $package.Count -Expected 1 -Message 'package should find the match in the correct object.'
    Assert-Equal -Actual $package[0].objectName -Expected 'wpSecond' -Message 'package should report the Object/@name closest to the Source.'

    Write-Output 'SEARCH_GENEXUS_XML_SOURCE_BLOCK_SELFTEST_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
        $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolvedTempRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Temp root outside the expected temporary directory: $resolvedTempRoot"
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
