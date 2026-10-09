#requires -Version 7.4
<#
.SYNOPSIS
  Self-test for the -AsJson CONTRACT of the Test-MimirKbIndexGate.ps1 engine (the shared
  index gate behind the local Test-*KbIndexGate.ps1 wrapper). Sentinel:
  MIMIR_KB_INDEX_GATE_CONTRACT_SELFTEST_OK.

.DESCRIPTION
  Focuses on the structured contract callers consume, not the green path (which requires
  a real SQLite + extractor signature). Over a folder with no structure/index:
    A. -AsJson NEVER throws: the block becomes { status: BLOCK, reason } + exit 1
       (parseable JSON), not a throw.
    B. Default (text) throws BLOCK: nonzero exit and no structured JSON on stdout
       (the backward-compatible path via grep GATE_OK).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
$fixturesRoot = Join-Path $repoRoot 'tests/fixtures'
. (Join-Path $fixturesRoot 'MimirSetupSelfTestSupport.ps1')

$engine = Join-Path $scriptsRoot 'Test-MimirKbIndexGate.ps1'
$roots = [System.Collections.Generic.List[string]]::new()

function Assert-True {
  param([bool]$Cond, [string]$Message)
  if (-not $Cond) { throw "FAILURE: $Message" }
}

try {
  # Empty folder (no structure wrapper, no index): the gate should block.
  $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mimir-indexgate-{0}" -f ([guid]::NewGuid().ToString('N')))
  [void](New-Item -ItemType Directory -Path $root -Force); $roots.Add($root)

  # --- A: -AsJson never throws -> { status: BLOCK, reason } + exit 1 ---
  $a = Invoke-MimirSelfTestScript -ScriptPath $engine -ScriptArgs @('-RepoRoot', $root, '-AsJson')
  Assert-True ($a.exit -eq 1) "A: expected exit 1; got $($a.exit)"
  Assert-True ($null -ne $a.json) "A: stdout should be parseable JSON (the -AsJson contract never throws)"
  Assert-True ($a.json.status -eq 'BLOCK') "A: expected status BLOCK; got $($a.json.status)"
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$a.json.reason)) "A: reason should be populated"

  # --- B: default (text) throws -> nonzero exit, no structured JSON ---
  $b = Invoke-MimirSelfTestScript -ScriptPath $engine -ScriptArgs @('-RepoRoot', $root)
  Assert-True ($b.exit -ne 0) "B: expected a nonzero exit on the text path (throw BLOCK); got $($b.exit)"
  Assert-True ($null -eq $b.json -or $null -eq $b.json.status) "B: the text path should not emit structured JSON on stdout"

  'MIMIR_KB_INDEX_GATE_CONTRACT_SELFTEST_OK'
}
finally {
  foreach ($r in $roots) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
}

exit 0
