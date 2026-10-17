#requires -Version 7.4
<#
.SYNOPSIS
    Scaffolds a KB workspace from the setup examples: folders, wrappers, README.md,
    AGENTS.md, kb-source-metadata.md, and .gitignore.

.DESCRIPTION
    Creates the creation-mode layout of the setup workflow in -WorkspaceRoot:

    - Folders scripts, Temp, IdeXpzExports, KbObjectsXml, KbIntelligence, with
      .gitkeep in Temp and IdeXpzExports (the folders the .gitignore covers with
      a folder/* pattern).
    - .gitignore with the rules the setup workflow prescribes.
    - One wrapper per workflows/setup/examples/<Verb>-Kb<Name>.example.ps1, written
      as scripts/<Verb>-<KbName>Kb<Name>.ps1. The shared-root placeholder
      C:\path\to\mimir-lite becomes -SharedSkillsRoot, the native-KB placeholder
      C:\path\to\native-kb becomes -KbNativePath when given (an empty value with
      -XpzOnly), the help-text
      placeholder <WorkspaceRoot> becomes the workspace folder, and every
      unprefixed sibling wrapper name (for example Query-KbIntelligence.ps1)
      becomes its prefixed name. The optional catalog override example is not
      copied.
    - README.md and AGENTS.md from README.md.example and AGENTS.md.example, with
      <KbName>, <WorkspaceRoot>, <MimirLiteRoot>, and (when given) <NativeKbPath>
      and the native KB folder check filled in. Of each pair of
      "<!-- WHEN native-kb -->" and "<!-- WHEN xpz-only -->" blocks, only the one
      matching the workspace is kept.
    - kb-source-metadata.md from the shared template in
      MimirKbSourceMetadataEditSupport.ps1, with empty values until the identity
      resolver and the sync workflow fill them.

    Never overwrites or deletes: an existing file is reported SKIPPED_EXISTING and
    left byte-identical, so a re-run is a safe no-op that only adds missing pieces.
    Every file is written as UTF-8 without BOM with LF line endings.

    Exit codes: 0 success; 2 invalid input (KB name, shared root, workspace path);
    1 unexpected failure.

.PARAMETER WorkspaceRoot
    KB workspace folder. Created when missing.

.PARAMETER KbName
    KB name used as the wrapper prefix. Letters and digits only ([A-Za-z0-9]+), the
    same prefix rule Test-MimirWrapperInventory.ps1 uses to infer it back.

.PARAMETER SharedSkillsRoot
    Root of the shared Mimir Lite checkout (the folder that contains
    skills/mimir-lite/scripts). Default: derived from this script's location.

.PARAMETER KbNativePath
    Native GeneXus KB folder. When given, it is recorded in AGENTS.md, README.md,
    and the identity-resolution wrapper; otherwise it is reported as pending.

.PARAMETER XpzOnly
    The user has no native KB folder: the workspace is built from XPZ files only.
    README.md and AGENTS.md say so, the identity-resolution wrapper gets an empty
    native path (it then reports NATIVE_KB_NOT_RECORDED), and the stable identity
    is reported as pending on the first sync, which writes it from the XPZ Source
    block. Cannot be combined with -KbNativePath.

.PARAMETER AsJson
    Emit the report as JSON instead of text lines.

.EXAMPLE
    pwsh -NoProfile -File "C:/Tools/mimir-lite/skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1" -WorkspaceRoot "C:/KBs/SampleKbWorkspace" -KbName SampleKb -KbNativePath "C:/Models/SampleKb"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,

    [Parameter(Mandatory = $true)]
    [string]$KbName,

    [string]$SharedSkillsRoot,

    [string]$KbNativePath,

    [switch]$XpzOnly,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'MimirTextFileEolSupport.ps1')
. (Join-Path $PSScriptRoot 'MimirKbSourceMetadataEditSupport.ps1')

function Exit-InvalidInput {
    param([string]$Message)
    [Console]::Error.WriteLine("BLOCK: $Message")
    exit 2
}

function ConvertTo-ForwardSlashPath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

function ConvertTo-DoubleQuotedContent {
    param([string]$Value)
    return ($Value -replace '`', '``' -replace '\$', '`$' -replace '"', '`"')
}

function ConvertTo-SingleQuotedContent {
    param([string]$Value)
    return ($Value -replace "'", "''")
}

# Same prefix rule as Test-MimirWrapperInventory.ps1: '^[A-Za-z]+-([A-Za-z0-9]+)Kb[A-Za-z]'.
if ($KbName -notmatch '^[A-Za-z0-9]+$') {
    Exit-InvalidInput "invalid -KbName '$KbName': use letters and digits only ([A-Za-z0-9]+), the prefix rule of Test-MimirWrapperInventory.ps1"
}

if ($XpzOnly -and -not [string]::IsNullOrWhiteSpace($KbNativePath)) {
    Exit-InvalidInput '-XpzOnly and -KbNativePath cannot be combined: an XPZ-only workspace has no native KB folder'
}

if ([string]::IsNullOrWhiteSpace($SharedSkillsRoot)) {
    $SharedSkillsRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$sharedScriptsDir = Join-Path $SharedSkillsRoot (Join-Path 'skills' (Join-Path 'mimir-lite' 'scripts'))
$examplesDir = Join-Path $SharedSkillsRoot (Join-Path 'skills' (Join-Path 'mimir-lite' (Join-Path 'workflows' (Join-Path 'setup' 'examples'))))
if (-not (Test-Path -LiteralPath $sharedScriptsDir -PathType Container) -or
    -not (Test-Path -LiteralPath $examplesDir -PathType Container)) {
    Exit-InvalidInput "invalid -SharedSkillsRoot '$SharedSkillsRoot': expected the Mimir Lite checkout root containing skills/mimir-lite/scripts and skills/mimir-lite/workflows/setup/examples"
}
$sharedRootFull = [System.IO.Path]::GetFullPath($SharedSkillsRoot).TrimEnd('\', '/')
$examplesDir = [System.IO.Path]::GetFullPath($examplesDir)

if (Test-Path -LiteralPath $WorkspaceRoot -PathType Leaf) {
    Exit-InvalidInput "invalid -WorkspaceRoot '$WorkspaceRoot': it is a file, not a folder"
}
$workspaceFull = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\', '/')

$nativeFull = $null
if (-not [string]::IsNullOrWhiteSpace($KbNativePath)) {
    $nativeFull = [System.IO.Path]::GetFullPath($KbNativePath).TrimEnd('\', '/')
}

$sharedRootText = ConvertTo-ForwardSlashPath $sharedRootFull
$workspaceText = ConvertTo-ForwardSlashPath $workspaceFull
$nativeText = if ($nativeFull) { ConvertTo-ForwardSlashPath $nativeFull } else { $null }

$created = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$pending = [System.Collections.Generic.List[string]]::new()

function Add-Folder {
    param([string]$RelativePath)
    $path = Join-Path $workspaceFull $RelativePath
    if (Test-Path -LiteralPath $path -PathType Container) { return }
    if (Test-Path -LiteralPath $path) {
        throw "BLOCK: '$path' exists and is not a folder"
    }
    [void](New-Item -ItemType Directory -Path $path)
    $created.Add("$RelativePath/")
}

function Add-TextFile {
    param([string]$RelativePath, [string]$Content)
    $path = Join-Path $workspaceFull $RelativePath
    if (Test-Path -LiteralPath $path) {
        $skipped.Add($RelativePath)
        return
    }
    $text = $Content -replace "`r`n", "`n"
    $lines = [System.Collections.Generic.List[string]]@($text.TrimEnd("`n") -split "`n")
    $context = [pscustomobject]@{ Lines = $lines; EolSequence = "`n"; HadTrailingNewline = ($text.Length -gt 0) }
    if ($text.Length -eq 0) {
        [System.IO.File]::WriteAllText($path, '', (Get-Utf8NoBomEncoding))
    } else {
        Write-TextFilePreservingEol -Path $path -FileContext $context
    }
    $created.Add($RelativePath)
}

function Read-Example {
    param([string]$FileName)
    $text = [System.IO.File]::ReadAllText((Join-Path $examplesDir $FileName))
    return ($text -replace "`r`n", "`n")
}

# Wrapper names: <Verb>-Kb<Name>.example.ps1 -> <Verb>-<KbName>Kb<Name>.ps1.
$wrapperMap = [ordered]@{}
foreach ($exampleFile in Get-ChildItem -LiteralPath $examplesDir -Filter '*.example.ps1' -Name | Sort-Object) {
    $baseName = $exampleFile -replace '\.example\.ps1$', ''
    if ($baseName -match '^([A-Za-z]+-)(Kb.+)$') {
        $wrapperMap[$exampleFile] = [pscustomobject]@{
            SiblingName = "$baseName.ps1"
            LocalName   = "$($Matches[1])${KbName}$($Matches[2]).ps1"
        }
    }
}

function Resolve-WrapperText {
    param([string]$Text)
    $Text = $Text.Replace('"C:\path\to\mimir-lite"', '"' + (ConvertTo-DoubleQuotedContent $sharedRootText) + '"')
    $Text = $Text.Replace("'C:\path\to\mimir-lite'", "'" + (ConvertTo-SingleQuotedContent $sharedRootText) + "'")
    if ($nativeText) {
        $Text = $Text.Replace('"C:\path\to\native-kb"', '"' + (ConvertTo-DoubleQuotedContent $nativeText) + '"')
        $Text = $Text.Replace("'C:\path\to\native-kb'", "'" + (ConvertTo-SingleQuotedContent $nativeText) + "'")
    } elseif ($XpzOnly) {
        $Text = $Text.Replace('"C:\path\to\native-kb"', '""').Replace("'C:\path\to\native-kb'", "''")
    }
    $Text = $Text.Replace('<WorkspaceRoot>', $workspaceText)
    foreach ($entry in $wrapperMap.Values) {
        $pattern = '(?<![A-Za-z0-9_-])' + [regex]::Escape($entry.SiblingName)
        $Text = [regex]::Replace($Text, $pattern, $entry.LocalName.Replace('$', '$$'))
    }
    if ($Text.Contains('C:\path\to\mimir-lite')) {
        throw 'BLOCK: shared-root placeholder left unresolved; the example uses an unexpected quoting form'
    }
    return $Text
}

function Resolve-DocText {
    param([string]$Text)
    $Text = $Text -replace '(?m)^<!-- FILL IN: replace <KbName> with the real KB name -->\n', ''
    # Keep the WHEN block that matches the workspace, drop the other one, and remove the markers.
    $keep = if ($XpzOnly) { 'xpz-only' } else { 'native-kb' }
    $Text = $Text -replace '(?m)^<!-- FILL IN: keep the WHEN block [^\n]*-->\n', ''
    $Text = [regex]::Replace($Text, '(?ms)^<!-- WHEN ([a-z-]+) -->\n(.*?)^<!-- END WHEN -->\n', {
            param($match)
            if ($match.Groups[1].Value -eq $keep) { return $match.Groups[2].Value }
            return ''
        })
    $Text = $Text.Replace('<KbName>', $KbName).Replace('<WorkspaceRoot>', $workspaceText).Replace('<MimirLiteRoot>', $sharedRootText)
    if ($nativeText) {
        $Text = $Text.Replace('<NativeKbPath>', $nativeText)
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $check = if (Test-Path -LiteralPath $nativeFull -PathType Container) { 'found and accessible' } else { 'not found or not accessible' }
        $Text = $Text.Replace('<NativeKbCheck>', $check)
        $Text = $Text.Replace('<YYYY-MM-DD>', $today)
        $Text = $Text -replace '(?m)^<!-- FILL IN: check date in YYYY-MM-DD format[^\n]*-->\n', ''
    }
    return $Text
}

foreach ($folder in @('scripts', 'Temp', 'IdeXpzExports', 'KbObjectsXml', 'KbIntelligence')) {
    Add-Folder -RelativePath $folder
}

$gitignore = @(
    '# Ephemeral artifacts and disposable reports'
    'Temp/*'
    '!Temp/.gitkeep'
    ''
    '# Inbox of XPZ files exported from the GeneXus IDE'
    'IdeXpzExports/*'
    '!IdeXpzExports/.gitkeep'
    ''
    '# Derived, regenerable index (KbObjectsXml is the official corpus and is never ignored)'
    'KbIntelligence/kb-intelligence.sqlite'
    'KbIntelligence/kb-intelligence-validation.json'
) -join "`n"
Add-TextFile -RelativePath '.gitignore' -Content ($gitignore + "`n")
Add-TextFile -RelativePath 'Temp/.gitkeep' -Content ''
Add-TextFile -RelativePath 'IdeXpzExports/.gitkeep' -Content ''

foreach ($exampleFile in $wrapperMap.Keys) {
    $entry = $wrapperMap[$exampleFile]
    Add-TextFile -RelativePath "scripts/$($entry.LocalName)" -Content (Resolve-WrapperText (Read-Example $exampleFile))
}

Add-TextFile -RelativePath 'README.md' -Content (Resolve-DocText (Read-Example 'README.md.example'))
Add-TextFile -RelativePath 'AGENTS.md' -Content (Resolve-DocText (Read-Example 'AGENTS.md.example'))

$metadataPath = Join-Path $workspaceFull 'kb-source-metadata.md'
if (Test-Path -LiteralPath $metadataPath) {
    $skipped.Add('kb-source-metadata.md')
} else {
    Write-NewKbSourceMetadataTemplate -MetadataPath $metadataPath -SourceXpzPath '' -Timestamp '' -MetadataStatus '' `
        -MajorVersion '' -MinorVersion '' -Build '' -KbGuid '' -Username '' -UncPath '' -VersionGuid '' -VersionName ''
    $created.Add('kb-source-metadata.md')
}

$resolveWrapper = "Resolve-${KbName}KbIdentity.ps1"
if ($nativeText) {
    if (-not (Test-Path -LiteralPath $nativeFull -PathType Container)) {
        $pending.Add("NativeKbPath: '$nativeText' was not found or is not accessible; check it before resolving the KB identity.")
    }
} elseif (-not $XpzOnly) {
    $pending.Add("NativeKbPath: native KB folder not given; record it in AGENTS.md, README.md, and scripts/$resolveWrapper (placeholders <NativeKbPath> and C:\path\to\native-kb).")
}
if ($XpzOnly) {
    $pending.Add("Stable identity: kb-source-metadata.md has empty Source fields; in this XPZ-only workspace the first sync writes them from the Source block of the XPZ (a GeneXus 9 or earlier export has none, and the audit then reports the metadata wrapper as NOT_APPLICABLE); rerun the setup audit after that sync.")
} else {
    $pending.Add("Stable identity: kb-source-metadata.md has empty Source fields; once the native KB folder is confirmed, run scripts/$resolveWrapper -UpdateMetadata.")
}

$scriptsText = "$workspaceText/scripts"
$nextSteps = @(
    "pwsh -NoProfile -File `"$scriptsText/Test-${KbName}KbPowerShellRuntime.ps1`""
    "pwsh -NoProfile -File `"$scriptsText/Test-${KbName}KbStructure.ps1`" (KbIntelligence/kb-intelligence.sqlite stays missing until the first sync builds the index)"
    "pwsh -NoProfile -File `"$scriptsText/Test-${KbName}KbSetupAudit.ps1`""
    'Export a full XPZ from the GeneXus IDE into IdeXpzExports, then run the Mimir Lite sync workflow.'
)

if ($AsJson) {
    [ordered]@{
        status           = 'OK'
        workspaceRoot    = $workspaceText
        kbName           = $KbName
        sharedSkillsRoot = $sharedRootText
        kbNativePath     = $nativeText
        xpzOnly          = [bool]$XpzOnly
        created          = @($created)
        skippedExisting  = @($skipped)
        pending          = @($pending)
        nextSteps        = @($nextSteps)
    } | ConvertTo-Json -Depth 4
} else {
    foreach ($item in $created) { Write-Output "CREATED: $item" }
    foreach ($item in $skipped) { Write-Output "SKIPPED_EXISTING: $item" }
    foreach ($item in $pending) { Write-Output "PENDING: $item" }
    foreach ($item in $nextSteps) { Write-Output "NEXT: $item" }
    Write-Output 'WORKSPACE_SCAFFOLD_OK'
}
exit 0
