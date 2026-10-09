#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the legacy branch of MimirKbSourceMetadataEditSupport.ps1 (-IsLegacyExport).

.DESCRIPTION
    Exercises Update-MimirKbSourceMetadataFromSync with its 3 legacy-export safeguards:
    (a) legacy export (-IsLegacyExport $true, KMW/MaxGxBuildSaved, no <Source>): Build
        filled from MaxGxBuildSaved; literal legacy hint present; generic warning absent;
    (b) modern NON-REGRESSION: the SAME package without -IsLegacyExport keeps the current
        behavior (generic warning when Source is absent; no legacy hint; no Build fallback);
    (c) complete modern NON-REGRESSION: modern package with KMW/Build and complete Source ->
        status 'complete', no warnings, Build coming from KMW/Build.
    Success token on stdout + exit 0.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-lite/scripts')
. (Join-Path $scriptsRoot 'MimirKbSourceMetadataEditSupport.ps1')

function New-MetaPath {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('legacy-meta-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $root)
    return @{ Root = $root; Meta = (Join-Path $root 'kb-source-metadata.md') }
}

function New-LegacyXmlDoc {
    [xml]$doc = @'
<ExportFile>
  <KMW>
    <MajorVersion>2</MajorVersion>
    <MinorVersion>2</MinorVersion>
    <MaxGxBuildSaved>2601</MaxGxBuildSaved>
  </KMW>
</ExportFile>
'@
    return $doc
}

function New-ModernCompleteXmlDoc {
    [xml]$doc = @'
<ExportFile>
  <KMW>
    <MajorVersion>18</MajorVersion>
    <MinorVersion>0</MinorVersion>
    <Build>250000</Build>
  </KMW>
  <Source kb="11111111-1111-1111-1111-111111111111" username="dev" UNCPath="\\srv\kb">
    <Version guid="22222222-2222-2222-2222-222222222222" name="Trunk"/>
  </Source>
</ExportFile>
'@
    return $doc
}

$genericNeedles = @(
    'KMW or Source came back missing',
    'Source is incomplete'
)

# =====================================================================================
# (a) legacy export: -IsLegacyExport $true
# =====================================================================================
$ctxA = New-MetaPath
try {
    $docA = New-LegacyXmlDoc
    $resultA = Update-MimirKbSourceMetadataFromSync -XmlDocument $docA -SourceXpzPath 'C:\fake\fin.xpz' -MetadataPath $ctxA.Meta -IsLegacyExport $true
    $warningsA = @($resultA.Warnings)

    if ($warningsA -notcontains $script:LegacyExportMetadataHintMessage) {
        throw "(a): literal legacy hint missing from warnings. Got: $($warningsA -join ' || ')"
    }
    foreach ($needle in $genericNeedles) {
        if (@($warningsA | Where-Object { $_ -like "*$needle*" }).Count -gt 0) {
            throw "(a): generic warning '$needle' should NOT appear in the legacy branch."
        }
    }
    $metaTextA = Get-Content -LiteralPath $ctxA.Meta -Raw
    if ($metaTextA -notmatch '(?m)^\|\s*Build\s*\|\s*2601\s*\|') {
        throw '(a): Build=2601 (MaxGxBuildSaved) not written to the legacy metadata.'
    }
} finally {
    if (Test-Path -LiteralPath $ctxA.Root) { Remove-Item -LiteralPath $ctxA.Root -Recurse -Force }
}

# =====================================================================================
# (b) modern NON-REGRESSION: SAME package without -IsLegacyExport
# =====================================================================================
$ctxB = New-MetaPath
try {
    $docB = New-LegacyXmlDoc
    $resultB = Update-MimirKbSourceMetadataFromSync -XmlDocument $docB -SourceXpzPath 'C:\fake\fin.xpz' -MetadataPath $ctxB.Meta
    $warningsB = @($resultB.Warnings)

    if ($warningsB -contains $script:LegacyExportMetadataHintMessage) {
        throw '(b): the legacy hint should NOT appear without -IsLegacyExport.'
    }
    # Source absent -> generic warning expected (current behavior preserved)
    if (@($warningsB | Where-Object { $_ -like '*KMW or Source came back missing*' }).Count -eq 0) {
        throw "(b): expected the generic KMW/Source-absent warning in the modern branch. Got: $($warningsB -join ' || ')"
    }
    # No Build fallback in the modern branch: Build remains empty
    $metaTextB = Get-Content -LiteralPath $ctxB.Meta -Raw
    if ($metaTextB -match '(?m)^\|\s*Build\s*\|\s*2601\s*\|') {
        throw '(b): Build should NOT receive the MaxGxBuildSaved fallback without -IsLegacyExport.'
    }
} finally {
    if (Test-Path -LiteralPath $ctxB.Root) { Remove-Item -LiteralPath $ctxB.Root -Recurse -Force }
}

# =====================================================================================
# (c) complete modern NON-REGRESSION: status complete, no warnings, Build from KMW/Build
# =====================================================================================
$ctxC = New-MetaPath
try {
    $docC = New-ModernCompleteXmlDoc
    $resultC = Update-MimirKbSourceMetadataFromSync -XmlDocument $docC -SourceXpzPath 'C:\fake\modern.xpz' -MetadataPath $ctxC.Meta
    if ($resultC.MetadataStatus -ne 'complete') { throw "(c): MetadataStatus='$($resultC.MetadataStatus)' (expected complete)." }
    if (@($resultC.Warnings).Count -ne 0) { throw "(c): a complete modern package should not emit warnings. Got: $(@($resultC.Warnings) -join ' || ')" }
    $metaTextC = Get-Content -LiteralPath $ctxC.Meta -Raw
    if ($metaTextC -notmatch '(?m)^\|\s*Build\s*\|\s*250000\s*\|') { throw '(c): Build=250000 (KMW/Build) not written to the modern metadata.' }
} finally {
    if (Test-Path -LiteralPath $ctxC.Root) { Remove-Item -LiteralPath $ctxC.Root -Recurse -Force }
}

Write-Output 'MIMIR_KB_SOURCE_METADATA_LEGACY_SELFTEST_OK'
exit 0
