#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for Test-PrePushBackendEnumerationParity.ps1 (Level 3).

.DESCRIPTION
    Validates the 10 methodological scenarios of the advisory backend-parity gate:
      1. Faithful extraction from the dispatcher's source of truth ($AdapterScript via AST).
      2. Complete enumeration on a single line (pass, no finding).
      3. Complete enumeration broken across multiple lines by paragraph wrap (pass).
      4. Proper subset on a single line and across multiple lines (warn / finding).
      5. Matching tolerant of Markdown formatting (bold, backticks, links, punctuation).
      6. Domain-boundary respect (sentences with \bCursor\b ignored).
      7. Respect for the inline marker (<!-- backend-parity: ignore --> / # backend-parity: ignore).
      8. Structured JSON output and conformance with the common gate contract.
      9. Simulation of a new backend added to the dispatcher without a doc update (detection).
      10. skills/mimir-lite/**/*.md is scanned too, not just skills/mimir-delegate/**/*.md.

    Success sentinel: OK: Test-PrePushBackendEnumerationParitySelfTest.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools') 'Test-PrePushBackendEnumerationParity.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Target script not found: $scriptPath"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-backend-parity-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
[void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'skills/mimir-delegate/scripts') -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'skills/mimir-lite/references') -Force)

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'Utf8NoBomEncodingSupport.ps1')
$utf8NoBom = Get-Utf8NoBomEncoding

function Write-TempFile {
    param([string]$RelativePath, [string]$Content)
    $full = Join-Path $tempRoot $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
}

try {
    # -----------------------------------------------------------------------------------
    # Fixture: synthetic dispatcher with 6 canonical backends
    # -----------------------------------------------------------------------------------
    $dispatcher = @'
$AdapterScript = @{
    'opencode'    = 'Invoke-OpenCode.ps1'
    'codex'       = 'Invoke-Codex.ps1'
    'claude-code' = 'Invoke-ClaudeCodeAsync.ps1'
    'copilot'     = 'Invoke-Copilot.ps1'
    'gemini'      = 'Invoke-Gemini.ps1'
    'antigravity' = 'Invoke-Antigravity.ps1'
}
'@
    Write-TempFile -RelativePath 'skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1' -Content $dispatcher

    # -----------------------------------------------------------------------------------
    # Test documents covering scenarios 2 through 7
    # -----------------------------------------------------------------------------------
    $doc1 = @'
# Backend Parity Test

## Scenario 2: complete enumeration on a single line
Supports opencode, codex, claude-code, copilot, gemini and antigravity.

## Scenario 3: complete enumeration broken by wrap
This methodology supports the backends **opencode**, **Codex**, `Claude Code`,
`GitHub Copilot CLI`, `Gemini CLI` and **Antigravity CLI** in an integrated way.

## Scenario 4: proper subset (should produce a warning)
The backends initially evaluated were `opencode`, `codex` and `claude-code`.

## Scenario 5: complex formatting in a proper subset
Comparing **[OpenCode](https://example.com)** against _Copilot_ and `Gemini`.

## Scenario 6: domain B (Cursor present -> should be ignored)
Installed agent tools: Cursor, Claude Code, Codex, Copilot, Gemini and Antigravity.

## Scenario 7: inline exception marker (should be ignored)
<!-- backend-parity: ignore -->
Slice by stdin-based axis: only opencode, codex and claude-code.
'@
    Write-TempFile -RelativePath 'doc-test.md' -Content $doc1

    # Run the gate via pwsh
    $output = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -AsJson 2>&1
    $exitCode = $LASTEXITCODE
    $jsonText = ($output | Out-String).Trim()
    $result = $jsonText | ConvertFrom-Json

    # -----------------------------------------------------------------------------------
    # Assertions for scenarios 1 through 8
    # -----------------------------------------------------------------------------------
    if ($exitCode -ne 0) {
        throw "Scenario 8: gate should exit with 0 (advisory); got $exitCode. Output: $jsonText"
    }
    if ($result.status -ne 'warn') {
        throw "Scenario 8: status should be 'warn'; got '$($result.status)'. Output: $jsonText"
    }

    # Scenario 1: faithful extraction
    $extractedBackends = @($result.canonicalBackends | Sort-Object)
    $expectedBackends = @('antigravity', 'claude-code', 'codex', 'copilot', 'gemini', 'opencode')
    if (($extractedBackends -join ',') -ne ($expectedBackends -join ',')) {
        throw "Scenario 1: extraction of backends from the dispatcher failed; got $(($extractedBackends) -join ',')"
    }

    # Scenario 7: count of ignored entries
    if ([int]$result.ignoredCount -ne 1) {
        throw "Scenario 7: ignoredCount should be 1; got $($result.ignoredCount)"
    }

    # Scenarios 2, 3, 4, 5, 6: finding count (only scenarios 4 and 5 should produce a finding)
    if ([int]$result.candidateCount -ne 2) {
        throw "Scenarios 2-6: expected exactly 2 findings (scenarios 4 and 5); got $($result.candidateCount). Findings: $(@($result.findings | ForEach-Object { $_.message }) -join ' | ')"
    }

    # Finding-message validation
    $f1 = $result.findings[0]
    if ($f1.message -notmatch 'opencode' -or $f1.message -notmatch 'codex' -or $f1.message -notmatch 'claude-code') {
        throw "Scenario 4: finding 1 should list opencode, codex and claude-code; got $($f1.message)"
    }
    if ($f1.message -notmatch 'antigravity' -or $f1.message -notmatch 'copilot' -or $f1.message -notmatch 'gemini') {
        throw "Scenario 4: finding 1 should point out antigravity, copilot and gemini as missing; got $($f1.message)"
    }

    $f2 = $result.findings[1]
    if ($f2.message -notmatch 'opencode' -or $f2.message -notmatch 'copilot' -or $f2.message -notmatch 'gemini') {
        throw "Scenario 5: finding 2 should list opencode, copilot and gemini; got $($f2.message)"
    }

    # -----------------------------------------------------------------------------------
    # Scenario 9: simulation of a new backend in the dispatcher without a doc update
    # -----------------------------------------------------------------------------------
    $dispatcherWithNew = @'
$AdapterScript = @{
    'opencode'    = 'Invoke-OpenCode.ps1'
    'codex'       = 'Invoke-Codex.ps1'
    'claude-code' = 'Invoke-ClaudeCodeAsync.ps1'
    'copilot'     = 'Invoke-Copilot.ps1'
    'gemini'      = 'Invoke-Gemini.ps1'
    'antigravity' = 'Invoke-Antigravity.ps1'
    'future-llm'  = 'Invoke-FutureLlm.ps1'
}
'@
    Write-TempFile -RelativePath 'skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1' -Content $dispatcherWithNew

    # A doc that previously had all 6 (complete) now has 6 of 7 -> should become a finding!
    $docWith6 = @'
# Previously Complete Doc
The supported backends are opencode, codex, claude-code, copilot, gemini and antigravity.
'@
    Write-TempFile -RelativePath 'doc-test.md' -Content $docWith6

    $output9 = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -AsJson 2>&1
    $jsonText9 = ($output9 | Out-String).Trim()
    $result9 = $jsonText9 | ConvertFrom-Json

    if (@($result9.canonicalBackends).Count -ne 7) {
        throw "Scenario 9: canonicalBackends should contain 7 items; got $(@($result9.canonicalBackends).Count)"
    }
    if ([int]$result9.candidateCount -ne 1) {
        throw "Scenario 9: a doc with 6 backends should be detected as a proper subset after the 7th backend is added; candidateCount=$($result9.candidateCount)"
    }
    if ($result9.findings[0].message -notmatch 'future-llm') {
        throw "Scenario 9: finding should indicate future-llm as missing; got $($result9.findings[0].message)"
    }

    # -----------------------------------------------------------------------------------
    # Scenario 10: skills/mimir-lite/**/*.md is scanned too (not just skills/mimir-delegate/)
    # -----------------------------------------------------------------------------------
    Write-TempFile -RelativePath 'doc-test.md' -Content '# Empty root doc, no backend mentions here.'
    $mimirLiteDoc = @'
# Mimir Lite reference mentioning backends

Delegation panel supports opencode, codex and claude-code as an initial subset.
'@
    Write-TempFile -RelativePath 'skills/mimir-lite/references/delegate-note.md' -Content $mimirLiteDoc

    $output10 = & pwsh -NoProfile -File $scriptPath -RootPath $tempRoot -AsJson 2>&1
    $jsonText10 = ($output10 | Out-String).Trim()
    $result10 = $jsonText10 | ConvertFrom-Json

    if ([int]$result10.candidateCount -ne 1) {
        throw "Scenario 10: skills/mimir-lite/**/*.md doc with a proper-subset mention should be scanned and flagged; candidateCount=$($result10.candidateCount)"
    }
    if ($result10.findings[0].path -notlike 'skills/mimir-lite/references/delegate-note.md:*') {
        throw "Scenario 10: finding should point at the skills/mimir-lite doc; got $($result10.findings[0].path)"
    }

    Write-Output 'OK: Test-PrePushBackendEnumerationParitySelfTest.ps1'
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
