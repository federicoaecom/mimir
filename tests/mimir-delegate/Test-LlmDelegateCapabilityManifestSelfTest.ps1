#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Self-test for Build-LlmDelegateCapabilityManifest.ps1 (mimir-delegate skill).
#
# Covers:
#  (A) Enumeration + locality: from an opencode.jsonc fixture with comments and
#      trailing commas, with one loopback (local) provider and one external provider, the
#      manifest lists both models with the correct locality.
#  (B) Sanitization by design: the manifest does NOT contain the decoy secret (apiKey,
#      external host, baseURL, config path) planted in the fixture.
#  (C) Schema: schemaVersion/generatedAt/backends present (canonical list in
#      skills/mimir-delegate/SKILL.md); v11 metadata per entry
#      (provider/family/sourceKind/sourceConfidence/availableInManifest/hardVeto);
#      Copilot/Gemini none-native with models=[]; lastHealthCheck null.
#  (D) Per-KB snapshot: snapshotAt present and sourceGeneratedAt == the manifest's generatedAt.
#  (E) Codex: does not invent openai/<slug> when the resolver cannot prove the provider.
#  (F) Claude Code: stats-cache counts as historical/weak, not current availability.

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
$scriptUnderTest = Join-Path $scriptsDir 'Build-LlmDelegateCapabilityManifest.ps1'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $scriptUnderTest -PathType Leaf) "Script under test missing: $scriptUnderTest"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-llm-cap-selftest-' + [System.Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

# Decoy secrets: must NEVER appear in the manifest.
$secretApiKey = 'sk-TOPSECRET-TOKEN-isca-123'
$externalHost = 'secret-host.internal.example'

try {
    $openCfg = Join-Path $tempRoot 'opencode.jsonc'
    @"
{
  // JSONC comment: must be accepted
  "provider": {
    "ollama": {
      "options": { "baseURL": "http://localhost:11434/v1" },
      "models": { "qwen2.5-coder:7b": {}, }
    },
    "myexternal": {
      "options": { "baseURL": "https://$externalHost/v1", "apiKey": "$secretApiKey" },
      "models": { "big-model": {}, "mistral-large-3": {} }
    },
  },
}
"@ | Set-Content -LiteralPath $openCfg -Encoding utf8

    # Real Codex config.toml: top-level model (openai builtin -> external) + a local
    # OSS profile (loopback -> local). Exercises Codex enumeration (scope-bug regression).
    $codexCfg = Join-Path $tempRoot 'config.toml'
    @"
model = "gpt-5.5"

[profiles.local-oss]
model = "qwen2.5-coder:7b"
model_provider = "ollama"

[profiles.providerless]
model = "mystery-model"

[model_providers.ollama]
base_url = "http://localhost:11434/v1"
"@ | Set-Content -LiteralPath $codexCfg -Encoding utf8
    $claudeSettings = Join-Path $tempRoot 'claude-settings.json'
    @'
{
  "model": "claude-opus-4-8"
}
'@ | Set-Content -LiteralPath $claudeSettings -Encoding utf8
    $claudeStats = Join-Path $tempRoot 'stats-cache.json'
    @'
{
  "lastModel": "claude-opus-4-7"
}
'@ | Set-Content -LiteralPath $claudeStats -Encoding utf8

    $fakeAgy = New-FakeCli -Directory $tempRoot -Name 'fake-agy' -PwshBody @'
if ($args.Count -ge 1 -and $args[0] -eq 'models') {
    'gemini-3.6-flash-high'
    'claude-sonnet-4-6'
    exit 0
}
exit 1
'@

    $outPath = Join-Path $tempRoot 'capabilities.json'
    $snapPath = Join-Path $tempRoot 'snap.json'

    & $scriptUnderTest -OutputPath $outPath -SnapshotPath $snapPath `
        -OpenCodeConfigPath $openCfg -CodexConfigPath $codexCfg `
        -ClaudeSettingsPath $claudeSettings -ClaudeStatsCachePath $claudeStats `
        -AntigravityExe $fakeAgy 1> $null

    Assert-True (Test-Path -LiteralPath $outPath -PathType Leaf) 'Manifest was not written.'
    $manifestText = [System.IO.File]::ReadAllText($outPath)
    $manifest = $manifestText | ConvertFrom-Json

    # (C) Schema
    Assert-True ($manifest.schemaVersion -eq 1) 'schemaVersion should be 1.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$manifest.generatedAt)) 'generatedAt missing.'
    Assert-True ($null -eq $manifest.lastHealthCheck) 'lastHealthCheck should be null (health is volatile).'
    $backendNames = @($manifest.backends | ForEach-Object { $_.backend })
    foreach ($expected in @('opencode', 'codex', 'claude-code', 'copilot', 'gemini', 'antigravity')) {
        Assert-True ($backendNames -contains $expected) "Backend missing from manifest: $expected"
    }
    foreach ($b in $manifest.backends) {
        Assert-True ($b.installed -is [bool]) "Field 'installed' of backend '$($b.backend)' should be boolean."
    }
    foreach ($noneNative in @('copilot', 'gemini')) {
        $b = $manifest.backends | Where-Object { $_.backend -eq $noneNative }
        Assert-True ($b.enumeration -eq 'none-native') "Backend '$noneNative' should have enumeration=none-native."
        Assert-True (@($b.models).Count -eq 0) "Backend '$noneNative' should have models=[] (no native enumeration)."
    }

    # (A) opencode enumeration + locality
    $oc = $manifest.backends | Where-Object { $_.backend -eq 'opencode' }
    Assert-True ($oc.enumeration -eq 'config') 'opencode should have enumeration=config.'
    $local = $oc.models | Where-Object { $_.canonicalModel -eq 'ollama/qwen2.5-coder:7b' }
    Assert-True ($null -ne $local) 'Loopback model not enumerated.'
    Assert-True ($local.locality -eq 'local') "Loopback model should be local; got '$($local.locality)'."
    Assert-True ($local.reasonCode -eq 'loopback-local') "Loopback reasonCode should be loopback-local; got '$($local.reasonCode)'."
    Assert-True ($local.backend -eq 'opencode') 'Entry should declare backend=opencode.'
    Assert-True ($local.targetModelKey -eq 'ollama/qwen2.5-coder:7b') 'Entry should declare targetModelKey.'
    Assert-True ($local.provider -eq 'ollama') 'Entry should declare provider=ollama.'
    Assert-True ($local.family -eq 'ollama') 'Entry should declare family=ollama.'
    Assert-True ($local.sourceKind -eq 'configured') 'sourceKind should be configured.'
    Assert-True ($local.sourceConfidence -eq 'strong') 'sourceConfidence should be strong.'
    Assert-True ($local.availableInManifest -eq $true) 'availableInManifest should be true.'
    Assert-True ($local.hardVeto -eq $false) 'Local model should not have hardVeto.'
    $ext = $oc.models | Where-Object { $_.canonicalModel -eq 'myexternal/big-model' }
    Assert-True ($null -ne $ext) 'External model not enumerated.'
    Assert-True ($ext.locality -eq 'external') "External model should be external; got '$($ext.locality)'."
    $veto = $oc.models | Where-Object { $_.canonicalModel -eq 'myexternal/mistral-large-3' }
    Assert-True ($null -ne $veto) 'Vetoed model should appear marked for diagnostics.'
    Assert-True ($veto.hardVeto -eq $true) 'Mistral Large 3 should be marked as hardVeto.'

    # (A2) Codex enumeration + locality (regression of the scope bug in Add-FromResolver:
    # `$entries += ...` inside a nested function did not update the parent array -> codex always empty).
    $cx = $manifest.backends | Where-Object { $_.backend -eq 'codex' }
    Assert-True ($cx.enumeration -eq 'config') 'codex should have enumeration=config.'
    Assert-True (@($cx.models).Count -ge 1) 'codex should enumerate at least 1 model from config.toml (scope-bug regression).'
    $cxTop = $cx.models | Where-Object { $_.canonicalModel -eq 'openai/gpt-5.5' }
    Assert-True ($null -ne $cxTop) 'codex should enumerate the top-level openai/gpt-5.5 model.'
    Assert-True ($cxTop.locality -eq 'external') "codex top-level model should be external; got '$($cxTop.locality)'."
    $providerless = $cx.models | Where-Object { $_.canonicalModel -eq 'mystery-model' }
    Assert-True ($null -ne $providerless) 'codex should preserve the providerless model as weak diagnostics.'
    Assert-True ($providerless.provider -eq 'unknown') 'codex providerless should end up as provider=unknown.'
    Assert-True ($providerless.sourceConfidence -eq 'weak') 'codex providerless should be a weak source.'
    Assert-True (-not (@($cx.models | Where-Object { $_.canonicalModel -eq 'openai/mystery-model' }).Count -gt 0)) 'codex must not invent openai/mystery-model when the provider was not proven.'

    # (F) Claude Code: settings are strong, stats are historical/weak.
    $cc = $manifest.backends | Where-Object { $_.backend -eq 'claude-code' }
    Assert-True ($cc.enumeration -eq 'settings-or-historical') 'claude-code should declare enumeration=settings-or-historical.'
    $ccConfigured = $cc.models | Where-Object { $_.canonicalModel -eq 'anthropic/claude-opus-4-8' }
    Assert-True ($null -ne $ccConfigured) 'Claude settings should enumerate claude-opus-4-8.'
    Assert-True ($ccConfigured.sourceKind -eq 'configured') 'Claude settings should be sourceKind=configured.'
    Assert-True ($ccConfigured.availableInManifest -eq $true) 'Claude settings should be availableInManifest=true.'
    $ccHistorical = $cc.models | Where-Object { $_.canonicalModel -eq 'anthropic/claude-opus-4-7' }
    Assert-True ($null -ne $ccHistorical) 'Claude stats-cache should enumerate claude-opus-4-7 as historical.'
    Assert-True ($ccHistorical.sourceKind -eq 'historical') 'Claude stats-cache should be sourceKind=historical.'
    Assert-True ($ccHistorical.sourceConfidence -eq 'weak') 'Claude stats-cache should be a weak source.'
    Assert-True ($ccHistorical.availableInManifest -eq $false) 'Claude stats-cache must not prove current availability.'

    # (G) Antigravity: enumeration via CLI agy models (fake-exe).
    $agy = $manifest.backends | Where-Object { $_.backend -eq 'antigravity' }
    Assert-True ($agy.enumeration -eq 'cli') 'antigravity should have enumeration=cli.'
    $agyModel = $agy.models | Where-Object { $_.canonicalModel -eq 'antigravity/gemini-3.6-flash-high' }
    Assert-True ($null -ne $agyModel) 'antigravity should enumerate gemini-3.6-flash-high.'
    Assert-True ($agyModel.sourceKind -eq 'cli') 'antigravity should be sourceKind=cli.'
    Assert-True ($agyModel.sourceConfidence -eq 'strong') 'antigravity should be sourceConfidence=strong.'

    # (H) Antigravity fallback without -AntigravityExe: must not throw under StrictMode
    # Hermetic: PATH is blanked so no real agy/copilot/gemini is discovered, and every config path is
    # injected. The script's last-resort fallback (%LOCALAPPDATA%\agy\bin\agy.exe, resolved through the
    # OS known-folder API and not overridable from the environment) could still find a real agy and run
    # `agy models`. When that binary exists on this machine, pass a non-existent -AntigravityExe instead:
    # the model probe then never runs (the file is missing) while the StrictMode no-throw path is exercised.
    # That fallback is Windows-only; off Windows, GetFolderPath('LocalApplicationData') can be empty (a
    # host without ~/.local/share), so the path is not built there.
    $outPathNoArg = Join-Path $tempRoot 'cap-no-arg.json'
    $realAgyDefault = if ($IsWindows) { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'agy\bin\agy.exe' } else { $null }
    $hExtra = @{}
    if ($null -ne $realAgyDefault -and (Test-Path -LiteralPath $realAgyDefault -PathType Leaf)) {
        Write-Host '[NOTE] (H) real agy at the default install path; using a missing -AntigravityExe so it is never run.' -ForegroundColor Yellow
        # Hashtable splat: an array splat would pass '-AntigravityExe' positionally as a value.
        $hExtra = @{ AntigravityExe = (Join-Path $tempRoot 'missing-agy.exe') }
    }
    $strayH = Join-Path (Get-Location).Path '-AntigravityExe'
    if (Test-Path -LiteralPath $strayH) { Remove-Item -LiteralPath $strayH -Force }
    $savedPathH = $env:PATH
    try {
        $env:PATH = ''
        & $scriptUnderTest -OutputPath $outPathNoArg `
            -OpenCodeConfigPath $openCfg -CodexConfigPath $codexCfg `
            -ClaudeSettingsPath $claudeSettings -ClaudeStatsCachePath $claudeStats @hExtra 1> $null
    }
    finally { $env:PATH = $savedPathH }
    Assert-True (Test-Path -LiteralPath $outPathNoArg -PathType Leaf) 'Manifest without -AntigravityExe should be written without error.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Get-Location).Path '-AntigravityExe'))) 'Case (H) must bind -AntigravityExe by name, not write a stray "-AntigravityExe" file into the current folder.'

    # (J) Default -OutputPath off Windows: the manifest lands in
    # $XDG_DATA_HOME/mimir-delegate/capabilities.json. XDG_DATA_HOME points to a folder that does not
    # exist yet, where GetFolderPath('LocalApplicationData') returns an empty string; the script
    # creates the folder on write. Hermetic like (H): blank PATH, injected configs, missing agy.
    if ($IsWindows) {
        Write-Host 'SKIP: off-Windows default manifest path case (Windows host; the real %LOCALAPPDATA% is not redirected)' -ForegroundColor Yellow
    }
    else {
        $savedXdgJ = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
        $savedPathJ = $env:PATH
        $xdgDefault = Join-Path $tempRoot 'xdg-default'
        $expectedDefaultManifest = Join-Path (Join-Path $xdgDefault 'mimir-delegate') 'capabilities.json'
        try {
            $env:XDG_DATA_HOME = $xdgDefault
            $env:PATH = ''
            try {
                & $scriptUnderTest -OpenCodeConfigPath $openCfg -CodexConfigPath $codexCfg `
                    -ClaudeSettingsPath $claudeSettings -ClaudeStatsCachePath $claudeStats `
                    -AntigravityExe (Join-Path $tempRoot 'missing-agy') 1> $null
            }
            catch { throw "(J) manifest without -OutputPath threw: $($_.Exception.Message)" }
        }
        finally {
            $env:PATH = $savedPathJ
            if ($null -eq $savedXdgJ) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdgJ }
        }
        Assert-True (Test-Path -LiteralPath $expectedDefaultManifest -PathType Leaf) "(J) manifest without -OutputPath should be written to XDG_DATA_HOME/mimir-delegate/capabilities.json ($expectedDefaultManifest)."
    }

    # (I) Antigravity: a HUNG probe is cut off by the time ceiling.
    # `agy models` is the only probe in this manifest that runs a CLI and waits on a network
    # response; without a ceiling, a stuck agy (expired token falling into an interactive prompt,
    # service down) would hang the ENTIRE manifest. Here the fake sleeps far longer than the
    # injected ceiling: the manifest must still come back, degrading ONLY antigravity to none-native.
    $fakeAgyHang = New-FakeCli -Directory $tempRoot -Name 'fake-agy-hang' -PwshBody @'
Start-Sleep -Seconds 60
exit 0
'@

    $outPathHang = Join-Path $tempRoot 'cap-hang.json'
    $swHang = [System.Diagnostics.Stopwatch]::StartNew()
    & $scriptUnderTest -OutputPath $outPathHang `
        -OpenCodeConfigPath $openCfg -CodexConfigPath $codexCfg `
        -ClaudeSettingsPath $claudeSettings -ClaudeStatsCachePath $claudeStats `
        -AntigravityExe $fakeAgyHang -AntigravityProbeTimeoutSec 2 1> $null
    $swHang.Stop()

    Assert-True ($swHang.Elapsed.TotalSeconds -lt 30) "Hung probe should be cut off by the ceiling; took $([math]::Round($swHang.Elapsed.TotalSeconds,1))s."
    Assert-True (Test-Path -LiteralPath $outPathHang -PathType Leaf) 'Manifest should be written even with the agy probe hung.'
    $manifestHang = [System.IO.File]::ReadAllText($outPathHang) | ConvertFrom-Json
    $agyHang = $manifestHang.backends | Where-Object { $_.backend -eq 'antigravity' }
    Assert-True ($agyHang.enumeration -eq 'none-native') "Hung agy should degrade to none-native; got $($agyHang.enumeration)."
    Assert-True (@($agyHang.models).Count -eq 0) 'Hung agy should not enumerate any model.'
    $ocHang = $manifestHang.backends | Where-Object { $_.backend -eq 'opencode' }
    Assert-True (@($ocHang.models).Count -gt 0) 'The other backends should remain enumerated despite the hung agy.'

    # (B) Sanitization by design
    foreach ($forbidden in @($secretApiKey, $externalHost, 'apiKey', 'baseURL', 'Authorization', '11434', $openCfg, $codexCfg, $claudeSettings, $claudeStats)) {
        Assert-True (-not ($manifestText -like "*$forbidden*")) "Manifest leaked forbidden sensitive content: '$forbidden'."
    }

    # (D) Per-KB snapshot
    Assert-True (Test-Path -LiteralPath $snapPath -PathType Leaf) 'Per-KB snapshot was not written.'
    $snap = [System.IO.File]::ReadAllText($snapPath) | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$snap.snapshotAt)) 'snapshotAt missing from snapshot.'
    Assert-True ($snap.sourceGeneratedAt -eq $manifest.generatedAt) 'Snapshot sourceGeneratedAt should match manifest generatedAt.'

    Write-Output 'OK: Test-LlmDelegateCapabilityManifestSelfTest.ps1'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
