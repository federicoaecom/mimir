#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '../../skills/mimir-lite/scripts'
. (Join-Path $root 'MimirMarkdownTableSupport.ps1')

function Assert-Equal($Actual, $Expected, $Label) {
    if ($null -eq $Expected) {
        if ($null -ne $Actual) { throw "$Label expected null, got '$Actual'" }
    } elseif ($null -eq $Actual -or $Actual -cne $Expected) {
        throw "$Label expected '$Expected', got '$Actual'"
    }
}

$lines = @(
    '| name | outside |', '## Other', '| name | wrong |',
    '## Source/Version', '| name | First |', '| NAME | Second |',
    '| empty |   |', '| short |', '| special (x) | value | extra |',
    '### Nested', '| nested | yes |', '## Source', '| name | other |'
)
Assert-Equal (Get-MarkdownTableValue $lines 'Source/Version' 'NAME') 'First' 'first case-insensitive match'
Assert-Equal (Get-MarkdownTableValue $lines 'Source/Version' 'empty') '' 'blank value'
Assert-Equal (Get-MarkdownTableValue $lines 'Source/Version' 'absent') $null 'missing field'
Assert-Equal (Get-MarkdownTableValue $lines 'Missing' 'name') $null 'missing section'
Assert-Equal (Get-MarkdownTableValue $lines 'Source/Version' 'special (x)') 'value' 'literal field and extra cells'
Assert-Equal (Get-MarkdownTableValue $lines 'Source/Version' 'nested') 'yes' 'third-level heading'
Assert-Equal (Get-MarkdownTableValue $lines 'Source' 'name') 'other' 'section boundary'
Assert-Equal (Get-MarkdownTableValue $lines 'Source/Version' 'short') $null 'short row'

$temp = Join-Path ([IO.Path]::GetTempPath()) ('mimir-table-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    foreach ($name in @('Test-MimirKbMetadataWrapper.ps1', 'Update-MimirKbSourceMetadataIdentity.ps1', 'MimirMarkdownTableSupport.ps1', 'MimirTextFileEolSupport.ps1', 'Utf8NoBomEncodingSupport.ps1')) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination $temp
    }
    $metadata = Join-Path $temp 'metadata.md'
    $wrapper = Join-Path $temp 'wrapper.ps1'
    $resolver = Join-Path $temp 'Resolve-GeneXusKbIdentity.ps1'
    $kbGuid = '11111111-1111-1111-1111-111111111111'
    $versionGuid = '22222222-2222-2222-2222-222222222222'
    $text = @"
last_xpz_materialization_run_at: 2026-01-01
## Source
| kb (GUID) | $kbGuid |
| username | user |
| UNCPath | path |
## Source/Version
| guid | $versionGuid |
| name | Demo |
"@ + "`n"
    [IO.File]::WriteAllText($metadata, $text, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($wrapper, @'
param($MetadataPath)
'last_xpz_materialization_run_at: 2026-01-01'
'kb_name: Demo'
'source_guid: 11111111-1111-1111-1111-111111111111'
'@, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($resolver, @'
param($KbNativePath, [switch]$AsJson)
'{"kbGuid":"11111111-1111-1111-1111-111111111111","username":"user","uncPath":"path","versionGuid":"22222222-2222-2222-2222-222222222222","versionName":"Demo","kbNativePath":"synthetic"}'
'@, [Text.UTF8Encoding]::new($false))
    $validator = Join-Path $temp 'Test-MimirKbMetadataWrapper.ps1'
    $updater = Join-Path $temp 'Update-MimirKbSourceMetadataIdentity.ps1'
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata))
    $output = @(& $validator -MetadataPath $metadata -WrapperPath $wrapper)
    Assert-Equal ($output -join "`n") "FIELD_OK: last_xpz_materialization_run_at`nFIELD_OK: kb_name`nFIELD_OK: source_guid`nMETADATA_WRAPPER_OK" 'wrapper success'
    Assert-Equal (& $updater -MetadataPath $metadata -KbNativePath 'synthetic') 'IDENTITY_METADATA_OK' 'identity unchanged'
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata))) $before 'unchanged bytes'
    [IO.File]::WriteAllText($metadata, $text.Replace('| username | user |', '| username | old |'), [Text.UTF8Encoding]::new($false))
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata))
    $failure = $null
    try { & $updater -MetadataPath $metadata -KbNativePath 'synthetic' } catch { $failure = $_.Exception.Message }
    Assert-Equal $failure "BLOCK: Source/username diverges in kb-source-metadata.md; existing='old'; resolved='user'. Automatic reconciliation refused without -AllowIdentityOverwrite." 'identity refusal'
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata))) $before 'refusal bytes'
    $output = @(& $updater -MetadataPath $metadata -KbNativePath 'synthetic' -AllowIdentityOverwrite)
    Assert-Equal ($output -join "`n") "IDENTITY_FIELD_SAME: Source/kb (GUID)`nIDENTITY_FIELD_OVERWRITE: Source/username`nIDENTITY_FIELD_SAME: Source/UNCPath`nIDENTITY_FIELD_SAME: Source/Version/guid`nIDENTITY_FIELD_SAME: Source/Version/name`nIDENTITY_METADATA_UPDATED" 'identity overwrite'
    Assert-Equal ([IO.File]::ReadAllText($metadata)) $text 'updated metadata'
    [IO.File]::WriteAllText($metadata, $text.Replace("| guid | $versionGuid |", '| guid |   |'), [Text.UTF8Encoding]::new($false))
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata))
    Assert-Equal ((@(& $validator -MetadataPath $metadata -WrapperPath $wrapper)) -join "`n") "PENDING_DATA: versionGuid missing`nMETADATA_WRAPPER_INCOMPLETE" 'wrapper incomplete'
    Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($metadata))) $before 'validator bytes'
    'PASS: 8 lookup cases and 5 public-interface scenarios'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
