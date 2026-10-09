#requires -Version 7.4
<#
.SYNOPSIS
Local wrapper to resolve the identity of the native KB.

.DESCRIPTION
Runs the shared script `Resolve-GeneXusKbIdentity.ps1`, which reads
`model.ini` and `knowledgebase.connection` and queries the KB's internal
database in read-only mode to obtain the stable identity fields used by
`kb-source-metadata.md`.

This wrapper is recommended when the KB workspace needs to reconcile identity
metadata because the exported XPZ came with an empty or incomplete `Source`.

With no native KB folder recorded in `$kbNativePath` (an XPZ-only workspace,
or a folder not recorded yet), it prints `NATIVE_KB_NOT_RECORDED` on stderr,
exits `3`, and changes nothing: in an XPZ-only workspace the stable identity
comes from the `Source` block of the XPZ, written by the sync workflow. With
`-AsJson` it also prints one JSON object on stdout, with `status`
(`NATIVE_KB_NOT_RECORDED`) and `message`; without `-AsJson` stdout stays empty.

.PARAMETER AsJson
Returns structured JSON output.

.PARAMETER SqlCredential
SQL Server credential. Needed only when the resolved connection requires SQL
authentication.

.PARAMETER UpdateMetadata
Updates the stable identity fields in `kb-source-metadata.md` from the local
native KB. By default, fills missing fields and blocks divergences.

.PARAMETER AllowIdentityOverwrite
Allows overwriting non-empty identity fields when they diverge from the
resolved local native KB. Use only in an approved reconciliation workstream.

.PARAMETER SharedSkillsRoot
Local root of the shared Mimir Lite checkout.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Resolve-KbIdentity.ps1" -AsJson

.EXAMPLE
& "<WorkspaceRoot>/scripts/Resolve-KbIdentity.ps1" -SqlCredential (Get-Credential)

Run from a PowerShell session: a PSCredential cannot be passed through pwsh -File.

.EXAMPLE
pwsh -NoProfile -File "<WorkspaceRoot>/scripts/Resolve-KbIdentity.ps1" -UpdateMetadata -AsJson
#>

param(
    [switch]$AsJson,

    [PSCredential]$SqlCredential,

    [switch]$UpdateMetadata,

    [switch]$AllowIdentityOverwrite,

    [string]$SharedSkillsRoot = "C:\path\to\mimir-lite"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$kbNativePath = "C:\path\to\native-kb"
$enginePath = Join-Path $SharedSkillsRoot "skills\mimir-lite\scripts\Resolve-GeneXusKbIdentity.ps1"
$updateEnginePath = Join-Path $SharedSkillsRoot "skills\mimir-lite\scripts\Update-MimirKbSourceMetadataIdentity.ps1"
$metadataPath = Join-Path (Split-Path -Parent $PSScriptRoot) "kb-source-metadata.md"

if ([string]::IsNullOrWhiteSpace($kbNativePath) -or $kbNativePath.EndsWith('\path\to\native-kb')) {
    $notRecordedMessage = 'no native KB folder is recorded in this wrapper ($kbNativePath). In an XPZ-only workspace the stable identity comes from the Source block of the XPZ, written into kb-source-metadata.md by the sync workflow. To resolve it from a native KB folder instead, record that folder here and in AGENTS.md and README.md.'
    [Console]::Error.WriteLine("NATIVE_KB_NOT_RECORDED: $notRecordedMessage")
    if ($AsJson) {
        [pscustomobject][ordered]@{
            status = 'NATIVE_KB_NOT_RECORDED'
            message = $notRecordedMessage
        } | ConvertTo-Json -Depth 5
    }
    exit 3
}

if ($UpdateMetadata) {
    if (-not (Test-Path -LiteralPath $updateEnginePath -PathType Leaf)) {
        throw "Shared KB metadata identity updater not found: $updateEnginePath"
    }

    $argsForUpdate = @{
        MetadataPath = $metadataPath
        KbNativePath = $kbNativePath
        PassThru = $AsJson
    }

    if ($AllowIdentityOverwrite) {
        $argsForUpdate.AllowIdentityOverwrite = $true
    }

    if ($null -ne $SqlCredential) {
        $argsForUpdate.SqlCredential = $SqlCredential
    }

    $updateResult = & $updateEnginePath @argsForUpdate
    if ($AsJson) {
        $updateResult | ConvertTo-Json -Depth 8
    } else {
        $updateResult
    }
    return
}

if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Shared KB identity resolver not found: $enginePath"
}

$argsForEngine = @{
    KbNativePath = $kbNativePath
}

if ($AsJson) {
    $argsForEngine.AsJson = $true
}

if ($null -ne $SqlCredential) {
    $argsForEngine.SqlCredential = $SqlCredential
}

& $enginePath @argsForEngine
