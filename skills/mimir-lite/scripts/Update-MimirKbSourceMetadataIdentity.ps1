#requires -Version 7.4
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath,

    [Parameter(Mandatory = $true)]
    [string]$KbNativePath,

    [PSCredential]$SqlCredential,

    [switch]$AllowIdentityOverwrite,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-Value {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $trimmed = $Value.Trim()
    if ($trimmed -eq '(missing)') {
        return ''
    }

    return $trimmed
}

function Get-MarkdownTableValue {
    param(
        [string[]]$Lines,
        [string]$SectionName,
        [string]$FieldName
    )

    $inSection = $false
    $sectionPattern = '^\s*##\s+{0}\s*$' -f [regex]::Escape($SectionName)

    foreach ($line in $Lines) {
        if ([regex]::IsMatch($line, '^\s*##\s+')) {
            $inSection = [regex]::IsMatch($line, $sectionPattern)
            continue
        }

        if (-not $inSection) {
            continue
        }

        $cells = @($line -split '\|')
        if ($cells.Count -lt 4) {
            continue
        }

        $name = $cells[1].Trim()
        $value = $cells[2].Trim()
        if ($name -ieq $FieldName -and $name -notmatch '^-+$') {
            return $value
        }
    }

    return $null
}

function Set-MarkdownTableValue {
    param(
        [string[]]$Lines,
        [string]$SectionName,
        [string]$FieldName,
        [string]$Value
    )

    $result = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $updated = $false
    $sectionPattern = '^\s*##\s+{0}\s*$' -f [regex]::Escape($SectionName)

    foreach ($line in $Lines) {
        if ([regex]::IsMatch($line, '^\s*##\s+')) {
            $inSection = [regex]::IsMatch($line, $sectionPattern)
            $result.Add($line) | Out-Null
            continue
        }

        if ($inSection) {
            $cells = @($line -split '\|')
            if ($cells.Count -ge 4) {
                $name = $cells[1].Trim()
                if ($name -ieq $FieldName -and $name -notmatch '^-+$') {
                    $result.Add("| $name | $Value |") | Out-Null
                    $updated = $true
                    continue
                }
            }
        }

        $result.Add($line) | Out-Null
    }

    if (-not $updated) {
        throw "BLOCK: field '$FieldName' not found in section '## $SectionName' of $MetadataPath"
    }

    return $result.ToArray()
}

function Test-IdentityChange {
    param(
        [string]$Field,
        [AllowNull()][string]$Existing,
        [string]$Resolved,
        [bool]$AllowOverwrite
    )

    $existingValue = Normalize-Value $Existing
    $resolvedValue = Normalize-Value $Resolved

    if ([string]::IsNullOrWhiteSpace($resolvedValue)) {
        throw "BLOCK: resolver returned an empty value for $Field"
    }

    if ([string]::IsNullOrWhiteSpace($existingValue)) {
        return [pscustomobject]@{
            Field = $Field
            Existing = $existingValue
            Resolved = $resolvedValue
            Action = 'fill'
        }
    }

    if ($existingValue -eq $resolvedValue) {
        return [pscustomobject]@{
            Field = $Field
            Existing = $existingValue
            Resolved = $resolvedValue
            Action = 'same'
        }
    }

    if (-not $AllowOverwrite) {
        throw "BLOCK: $Field diverges in kb-source-metadata.md; existing='$existingValue'; resolved='$resolvedValue'. Automatic reconciliation refused without -AllowIdentityOverwrite."
    }

    return [pscustomobject]@{
        Field = $Field
        Existing = $existingValue
        Resolved = $resolvedValue
        Action = 'overwrite'
    }
}

$resolvedMetadataPath = [System.IO.Path]::GetFullPath($MetadataPath)
if (-not (Test-Path -LiteralPath $resolvedMetadataPath -PathType Leaf)) {
    throw "BLOCK: kb-source-metadata.md not found: $resolvedMetadataPath"
}

$resolverPath = Join-Path $PSScriptRoot 'Resolve-GeneXusKbIdentity.ps1'
if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
    throw "BLOCK: identity resolver not found: $resolverPath"
}

$resolverArgs = @{
    KbNativePath = $KbNativePath
    AsJson = $true
}

if ($null -ne $SqlCredential) {
    $resolverArgs.SqlCredential = $SqlCredential
}

. (Join-Path $PSScriptRoot 'MimirTextFileEolSupport.ps1')

$resolved = (& $resolverPath @resolverArgs | ConvertFrom-Json)
$fileContext = Get-TextFileLineContext -Path $resolvedMetadataPath
$lines = @($fileContext.Lines.ToArray())

$changes = @(
    Test-IdentityChange -Field 'Source/kb (GUID)' -Existing (Get-MarkdownTableValue -Lines $lines -SectionName 'Source' -FieldName 'kb (GUID)') -Resolved $resolved.kbGuid -AllowOverwrite:$AllowIdentityOverwrite
    Test-IdentityChange -Field 'Source/username' -Existing (Get-MarkdownTableValue -Lines $lines -SectionName 'Source' -FieldName 'username') -Resolved $resolved.username -AllowOverwrite:$AllowIdentityOverwrite
    Test-IdentityChange -Field 'Source/UNCPath' -Existing (Get-MarkdownTableValue -Lines $lines -SectionName 'Source' -FieldName 'UNCPath') -Resolved $resolved.uncPath -AllowOverwrite:$AllowIdentityOverwrite
    Test-IdentityChange -Field 'Source/Version/guid' -Existing (Get-MarkdownTableValue -Lines $lines -SectionName 'Source/Version' -FieldName 'guid') -Resolved $resolved.versionGuid -AllowOverwrite:$AllowIdentityOverwrite
    Test-IdentityChange -Field 'Source/Version/name' -Existing (Get-MarkdownTableValue -Lines $lines -SectionName 'Source/Version' -FieldName 'name') -Resolved $resolved.versionName -AllowOverwrite:$AllowIdentityOverwrite
)

$pendingChanges = @($changes | Where-Object { $_.Action -ne 'same' })
if ($pendingChanges.Count -eq 0) {
    if ($PassThru) {
        [pscustomobject]@{
            status = 'IDENTITY_METADATA_OK'
            metadataPath = $resolvedMetadataPath
            kbNativePath = $resolved.kbNativePath
            changes = @($changes)
        }
    } else {
        'IDENTITY_METADATA_OK'
    }
    return
}

if ($PSCmdlet.ShouldProcess($resolvedMetadataPath, 'reconcile stable KB identity')) {
    $updatedLines = $lines
    $updatedLines = Set-MarkdownTableValue -Lines $updatedLines -SectionName 'Source' -FieldName 'kb (GUID)' -Value $resolved.kbGuid
    $updatedLines = Set-MarkdownTableValue -Lines $updatedLines -SectionName 'Source' -FieldName 'username' -Value $resolved.username
    $updatedLines = Set-MarkdownTableValue -Lines $updatedLines -SectionName 'Source' -FieldName 'UNCPath' -Value $resolved.uncPath
    $updatedLines = Set-MarkdownTableValue -Lines $updatedLines -SectionName 'Source/Version' -FieldName 'guid' -Value $resolved.versionGuid
    $updatedLines = Set-MarkdownTableValue -Lines $updatedLines -SectionName 'Source/Version' -FieldName 'name' -Value $resolved.versionName

    $fileContext.Lines = [System.Collections.Generic.List[string]]@($updatedLines)
    Write-TextFilePreservingEol -Path $resolvedMetadataPath -FileContext $fileContext
}

if ($PassThru) {
    [pscustomobject]@{
        status = 'IDENTITY_METADATA_UPDATED'
        metadataPath = $resolvedMetadataPath
        kbNativePath = $resolved.kbNativePath
        changes = @($changes)
    }
} else {
    foreach ($change in $changes) {
        "IDENTITY_FIELD_$($change.Action.ToUpperInvariant()): $($change.Field)"
    }
    'IDENTITY_METADATA_UPDATED'
}
