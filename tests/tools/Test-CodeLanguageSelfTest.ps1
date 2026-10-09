#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tools/Test-CodeLanguage.ps1.

.DESCRIPTION
    Builds a synthetic temp root with `.ps1`/`.py` files under the same script
    folders this repository scans (skills/*/scripts, skills/*/workflows, tools, tests) and proves:
      - an accented pt-BR word in a comment -> finding;
      - a common pt-BR function word without accent (e.g. "nao") -> finding;
      - a pt-BR literal listed in a leftover docs/i18n/contract-tokens.md ->
        still flagged (the tool reads no token list and masks nothing);
      - a line carrying an inline `# lang-allow <reason>` marker -> NOT flagged;
      - a pt-BR comment or message in a `.ps1` under `skills/<skill>/workflows/**`
        (the shipped wrapper examples) -> finding;
      - a file under tests/fixtures/ -> skipped entirely, even with pt-BR content;
      - a clean English file -> zero findings, exit 0.
    Also proves the tool exposes no -ContractTokensPath parameter and that an
    all-clean tree without any docs/i18n/contract-tokens.md passes.
    Does not touch the real repository tree; points -RootPath at the synthetic
    tree.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path (Join-Path $repoRoot 'tools') 'Test-CodeLanguage.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "BLOCK: tool not found: $scriptPath"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-code-language-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

function Write-Fixture {
    param([string]$RelativePath, [string]$Content)
    $full = Join-Path $tempRoot $RelativePath
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
}

try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)

    # A leftover contract-tokens.md listing a pt-BR literal. The tool must
    # ignore it: the literal below is still a finding.
    Write-Fixture -RelativePath 'docs/i18n/contract-tokens.md' -Content @'
# Contract tokens

| Token | Emitted by | Read by | Note |
|---|---|---|---|
| `bloqueado por parametro invalido` | fake.ps1 | fake test | synthetic |
'@

    # --- RED case 1: accented pt-BR word in a comment. ---
    Write-Fixture -RelativePath 'skills/mimir-lite/scripts/HasAccentWord.ps1' -Content @'
#requires -Version 7.4
# Verifica se a configuração está correta antes de prosseguir.
Write-Output "ok"
'@

    # --- RED case 2: unaccented common pt-BR function word ("nao"). ---
    Write-Fixture -RelativePath 'tools/HasPlainWord.ps1' -Content @'
#requires -Version 7.4
# Retorna nulo quando o arquivo nao existe no caminho informado.
Write-Output "ok"
'@

    # --- RED case 1b: a pt-BR literal listed in contract-tokens.md is flagged. ---
    Write-Fixture -RelativePath 'skills/mimir-lite/scripts/ContractToken.ps1' -Content @'
#requires -Version 7.4
# Kept as-is per contract: throw "BLOCK: bloqueado por parametro invalido"
Write-Output "ok"
'@

    # --- GREEN case 2: inline lang-allow marker suppresses the line. ---
    Write-Fixture -RelativePath 'tools/AllowMarker.ps1' -Content @'
#requires -Version 7.4
# fixture literal kept in pt-BR on purpose  # lang-allow test fixture needs real pt-BR text
Write-Output "ok"
'@

    # --- GREEN case 2b: a lang-allow marker on the comment line before a
    # multi-line backtick-continued statement covers every physical line of
    # that statement (needed since an inline marker would land after a
    # trailing backtick and break the continuation). ---
    Write-Fixture -RelativePath 'tools/AllowMarkerPrecedingLine.ps1' -Content @'
#requires -Version 7.4
# lang-allow: test fixture, statement continues across lines
Write-Output 'primeira parte' `
    'nao devolvido' `
    -Verbose
'@

    # --- RED case 3: pt-BR help text and message in a shipped workflow example
    # (skills/<skill>/workflows/**), which the gate did not scan before. ---
    Write-Fixture -RelativePath 'skills/mimir-lite/workflows/setup/examples/HasPtBrHelp.example.ps1' -Content @'
#requires -Version 7.4
<#
.SYNOPSIS
Wrapper local para validar o runtime; nao altera a configuração do espaço de trabalho.
#>
throw "BLOCK: motor compartilhado não encontrado"
'@

    # --- GREEN case: a clean English workflow example is not flagged. ---
    Write-Fixture -RelativePath 'skills/mimir-lite/workflows/setup/examples/CleanHelp.example.ps1' -Content @'
#requires -Version 7.4
<#
.SYNOPSIS
Sanitized local wrapper to validate the runtime of the KB workspace.
#>
throw "BLOCK: shared engine missing"
'@

    # --- GREEN case 3: tests/fixtures/ is skipped entirely. ---
    Write-Fixture -RelativePath 'tests/fixtures/SampleData.ps1' -Content @'
#requires -Version 7.4
# Este arquivo contem dados de amostra em portugues, nao deve ser escaneado.
Write-Output "ok"
'@

    # --- GREEN case 4: clean English file. ---
    Write-Fixture -RelativePath 'tests/mimir-lite/Clean.ps1' -Content @'
#requires -Version 7.4
# Checks whether the configuration is valid before continuing.
Write-Output "ok"
'@

    # --- The tool no longer takes a contract-token list. ---
    $toolParameters = @((Get-Command -Name $scriptPath).Parameters.Keys)
    Assert-True (-not ($toolParameters -contains 'ContractTokensPath')) "the tool must not expose a -ContractTokensPath parameter"

    $jsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -RootPath $tempRoot -AsJson
    $exitCode = $LASTEXITCODE
    $report = ($jsonRaw -join "`n") | ConvertFrom-Json

    Assert-True ($exitCode -ne 0) "tool should exit non-zero when real findings exist (got $exitCode)"
    Assert-True ($report.status -eq 'fail') "status should be 'fail', got '$($report.status)'"

    $accentedHits = @($report.findings | Where-Object { $_.file -eq 'skills/mimir-lite/scripts/HasAccentWord.ps1' })
    Assert-True ($accentedHits.Count -eq 1) "HasAccentWord.ps1 should produce exactly 1 finding, got $($accentedHits.Count)"

    $unaccentedHits = @($report.findings | Where-Object { $_.file -eq 'tools/HasPlainWord.ps1' })
    Assert-True ($unaccentedHits.Count -eq 1) "HasPlainWord.ps1 should produce exactly 1 finding (nao), got $($unaccentedHits.Count)"

    $contractHits = @($report.findings | Where-Object { $_.file -eq 'skills/mimir-lite/scripts/ContractToken.ps1' })
    Assert-True ($contractHits.Count -eq 1) "ContractToken.ps1's pt-BR literal must be flagged even when contract-tokens.md lists it, got $($contractHits.Count) findings"

    $allowHits = @($report.findings | Where-Object { $_.file -eq 'tools/AllowMarker.ps1' })
    Assert-True ($allowHits.Count -eq 0) "AllowMarker.ps1's lang-allow line must not be flagged, got $($allowHits.Count) findings"

    $allowPrecedingHits = @($report.findings | Where-Object { $_.file -eq 'tools/AllowMarkerPrecedingLine.ps1' })
    Assert-True ($allowPrecedingHits.Count -eq 0) "AllowMarkerPrecedingLine.ps1's line should be suppressed by the lang-allow marker on the line before it, got $($allowPrecedingHits.Count) findings"

    $workflowHits = @($report.findings | Where-Object { $_.file -eq 'skills/mimir-lite/workflows/setup/examples/HasPtBrHelp.example.ps1' })
    Assert-True ($workflowHits.Count -ge 1) "a pt-BR comment under skills/*/workflows/** must be flagged, got $($workflowHits.Count) findings"

    $workflowCleanHits = @($report.findings | Where-Object { $_.file -eq 'skills/mimir-lite/workflows/setup/examples/CleanHelp.example.ps1' })
    Assert-True ($workflowCleanHits.Count -eq 0) "a clean English workflow example must not be flagged, got $($workflowCleanHits.Count) findings"

    $fixtureHits = @($report.findings | Where-Object { $_.file -like 'tests/fixtures/*' })
    Assert-True ($fixtureHits.Count -eq 0) "tests/fixtures/ must be skipped entirely, got $($fixtureHits.Count) findings"

    $cleanHits = @($report.findings | Where-Object { $_.file -eq 'tests/mimir-lite/Clean.ps1' })
    Assert-True ($cleanHits.Count -eq 0) "Clean.ps1 must produce zero findings, got $($cleanHits.Count)"

    # --- A clean-only run without any contract-tokens.md must exit 0 and report status=pass. ---
    $cleanRoot = Join-Path $tempRoot 'clean-only'
    New-Item -ItemType Directory -Path (Join-Path $cleanRoot 'tests/mimir-lite') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $tempRoot 'tests/mimir-lite/Clean.ps1') -Destination (Join-Path $cleanRoot 'tests/mimir-lite/Clean.ps1')
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $cleanRoot 'docs/i18n/contract-tokens.md'))) "the clean-only tree must not carry a contract-tokens.md"

    $cleanJsonRaw = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -RootPath $cleanRoot -AsJson
    $cleanExitCode = $LASTEXITCODE
    $cleanReport = ($cleanJsonRaw -join "`n") | ConvertFrom-Json
    Assert-True ($cleanExitCode -eq 0) "tool should exit 0 when everything is clean (got $cleanExitCode)"
    Assert-True ($cleanReport.status -eq 'pass') "status should be 'pass' for an all-clean tree, got '$($cleanReport.status)'"
    Assert-True ($cleanReport.findings.Count -eq 0) "an all-clean tree must report 0 findings, got $($cleanReport.findings.Count)"
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) assertion(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: Test-CodeLanguageSelfTest.ps1" -ForegroundColor Green
exit 0
