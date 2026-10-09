#requires -Version 7.4
<#
.SYNOPSIS
    Mechanical completeness gate for skills/mimir-lite/references/09-script-inventory.md.

.DESCRIPTION
    Asserts that every file physically present under the three script folders
    (skills/mimir-lite/scripts/, skills/mimir-delegate/scripts/, tools/ — excluding
    __pycache__/) appears exactly once in the matching section of the inventory document, and
    that every entry listed in the inventory still corresponds to a real file. This replaces a
    manual/opus audit of the inventory: the source of truth is the file system.

.PARAMETER RepoRoot
    Repository root. Default: parent of tools/.

.PARAMETER InventoryPath
    Path to the inventory document, relative to -RepoRoot. Default:
    skills/mimir-lite/references/09-script-inventory.md.

.PARAMETER AsJson
    Emit the structured result as JSON instead of human-readable text.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,

    [string]$InventoryPath = 'skills/mimir-lite/references/09-script-inventory.md',

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function ConvertTo-RepoRelativePath {
    param([string]$Path)
    return (($Path -replace '\\', '/').Trim())
}

# The three script folders this gate covers, and the exact section-heading pattern each one
# uses in the inventory document (a level-2 heading naming the folder in backticks).
$sections = @(
    [pscustomobject]@{ Folder = 'skills/mimir-lite/scripts'; HeadingPattern = '^## `skills/mimir-lite/scripts/`' }
    [pscustomobject]@{ Folder = 'skills/mimir-delegate/scripts'; HeadingPattern = '^## `skills/mimir-delegate/scripts/`' }
    [pscustomobject]@{ Folder = 'tools'; HeadingPattern = '^## `tools/`' }
)

$inventoryFullPath = Join-Path $resolvedRoot $InventoryPath
if (-not (Test-Path -LiteralPath $inventoryFullPath -PathType Leaf)) {
    throw ("Inventory document not found: {0}" -f $inventoryFullPath)
}
$inventoryLines = Get-Content -LiteralPath $inventoryFullPath -Encoding utf8

$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Target,
        [string]$Code,
        [string]$Path,
        [string]$Message
    )
    $Target.Add([pscustomobject][ordered]@{
        code    = $Code
        path    = $Path
        message = $Message
    })
}

foreach ($section in $sections) {
    $folderFullPath = Join-Path $resolvedRoot $section.Folder

    # Actual files on disk, relative to the repo root, excluding __pycache__.
    $actualRelativePaths = @()
    if (Test-Path -LiteralPath $folderFullPath -PathType Container) {
        $actualRelativePaths = @(Get-ChildItem -LiteralPath $folderFullPath -Recurse -File -Force |
            Where-Object { $_.FullName -notmatch '[\\/]__pycache__[\\/]' } |
            ForEach-Object {
                ConvertTo-RepoRelativePath -Path ([System.IO.Path]::GetRelativePath($resolvedRoot, $_.FullName))
            } |
            Sort-Object)
    }

    # Slice the inventory document to the text between this section's heading and the next
    # level-2 heading (or end of file).
    $headingIndex = -1
    for ($i = 0; $i -lt $inventoryLines.Count; $i++) {
        if ($inventoryLines[$i] -match $section.HeadingPattern) {
            $headingIndex = $i
            break
        }
    }
    if ($headingIndex -eq -1) {
        Add-Finding -Target $findings -Code 'INVENTORY_SECTION_MISSING' -Path $section.Folder -Message ("No section heading found for {0} in {1}." -f $section.Folder, $InventoryPath)
        continue
    }
    $sectionEndIndex = $inventoryLines.Count
    for ($i = $headingIndex + 1; $i -lt $inventoryLines.Count; $i++) {
        if ($inventoryLines[$i] -match '^## ') {
            $sectionEndIndex = $i
            break
        }
    }
    $sectionLines = $inventoryLines[($headingIndex + 1)..($sectionEndIndex - 1)]

    # Table rows: a line starting with "| `<relative-path>` |" — the first backtick span is
    # the listed file's path, relative to this section's folder.
    $listedRelativeToFolder = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $sectionLines) {
        $rowMatch = [regex]::Match($line, '^\|\s*`([^`]+)`\s*\|')
        if ($rowMatch.Success) {
            $listedRelativeToFolder.Add($rowMatch.Groups[1].Value) | Out-Null
        }
    }

    $listedRelativeToRoot = @($listedRelativeToFolder | ForEach-Object { ConvertTo-RepoRelativePath -Path ("{0}/{1}" -f $section.Folder, $_) })

    # Duplicates: the same relative path listed more than once in this section.
    $listedGroups = $listedRelativeToRoot | Group-Object
    foreach ($group in $listedGroups) {
        if ($group.Count -gt 1) {
            Add-Finding -Target $findings -Code 'INVENTORY_DUPLICATE_ENTRY' -Path $group.Name -Message ("{0} appears {1} times in the {2} section of {3}; each file must be listed exactly once." -f $group.Name, $group.Count, $section.Folder, $InventoryPath)
        }
    }

    $listedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$listedRelativeToRoot)
    $actualSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$actualRelativePaths)

    foreach ($actualPath in $actualRelativePaths) {
        if (-not $listedSet.Contains($actualPath)) {
            Add-Finding -Target $findings -Code 'INVENTORY_MISSING_FILE' -Path $actualPath -Message ("{0} exists on disk but is not listed in the {1} section of {2}." -f $actualPath, $section.Folder, $InventoryPath)
        }
    }
    foreach ($listedPath in ($listedSet | Sort-Object)) {
        if (-not $actualSet.Contains($listedPath)) {
            Add-Finding -Target $findings -Code 'INVENTORY_STALE_ENTRY' -Path $listedPath -Message ("{0} is listed in the {1} section of {2} but no such file exists on disk." -f $listedPath, $section.Folder, $InventoryPath)
        }
    }
}

$status = if ($findings.Count -gt 0) { 'fail' } else { 'pass' }
$result = [ordered]@{
    status       = $status
    inventoryPath = $InventoryPath
    findings     = @($findings)
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 8
} else {
    Write-Output ("SCRIPT_INVENTORY={0}" -f $status)
    foreach ($finding in $findings) {
        Write-Output ("SCRIPT_INVENTORY_FINDING: {0}: {1}" -f $finding.code, $finding.message)
    }
}

if ($status -eq 'fail') {
    exit 1
}
exit 0
