#requires -Version 7.4
<#
.SYNOPSIS
  Self-test for the corpus generation verdict of the Test-MimirKbIndexGate.ps1 engine.
  Sentinel: MIMIR_KB_INDEX_GATE_CORPUS_GENERATION_SELFTEST_OK.

.DESCRIPTION
  Builds a temporary KB workspace from a copy of tests/fixtures/sample-kb (which carries a
  complete .mimir-sync-state.json), builds its index with the real builder, and runs the gate
  with stub structure and query wrappers (the query wrapper calls the real query engine):
    - a complete corpus whose generation matches the index reaches GATE_OK, even when
      last_xpz_materialization_run_at is later than last_index_build_run_at (dates are
      informational);
    - the gate blocks, naming the reason and its recovery, for an incomplete, unknown, or
      invalid corpus state, a generation mismatch, an index without a generation, and a busy
      corpus lock (only an incomplete corpus may offer a package re-run; an unknown or invalid
      one offers a verified -FullSnapshot sync only);
    - when the index-metadata query fails, the block reason carries the query's own exit code
      and stderr instead of a generic message.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptsRoot = Join-Path $repoRoot 'skills/mimir-lite/scripts'
. (Join-Path $repoRoot 'tests/fixtures/MimirSetupSelfTestSupport.ps1')
. (Join-Path $PSScriptRoot 'CorpusStateTestSupport.ps1')
. (Join-Path $scriptsRoot 'GeneXusPythonPrerequisite.ps1')

$engine = Join-Path $scriptsRoot 'Test-MimirKbIndexGate.ps1'
$builder = Join-Path $scriptsRoot 'Build-KbIntelligenceIndex.ps1'
$queryEngine = Join-Path $scriptsRoot 'Query-KbIntelligenceIndex.ps1'
$lockSupport = Join-Path $scriptsRoot 'GeneXusCorpusLockSupport.ps1'
$encoding = [Text.UTF8Encoding]::new($false)
$failures = [System.Collections.Generic.List[string]]::new()
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { $failures.Add($Message) } }

$python = Get-GeneXusPythonExecutable
if ($null -eq $python) { throw (Get-GeneXusPythonNotFoundMessage) }
function Invoke-Sql([string]$Database, [string]$Sql) {
  $code = "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute(sys.argv[2])`nc.commit()`nc.close()"
  & $python.Source @($python.PrefixArguments) -c $code $Database $Sql
  if ($LASTEXITCODE -ne 0) { throw "sqlite update failed: $Sql" }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('mimir-indexgate-generation-' + [guid]::NewGuid().ToString('N'))
try {
  $workspace = Join-Path $root 'ws'
  $corpus = Join-Path $workspace 'KbObjectsXml'
  $indexDir = Join-Path $workspace 'KbIntelligence'
  $index = Join-Path $indexDir 'kb-intelligence.sqlite'
  $scripts = Join-Path $workspace 'scripts'
  [void][IO.Directory]::CreateDirectory($scripts)
  [void][IO.Directory]::CreateDirectory($indexDir)
  Copy-Item -LiteralPath (Join-Path $repoRoot 'tests/fixtures/sample-kb') -Destination $corpus -Recurse
  $statePath = Join-Path $corpus '.mimir-sync-state.json'
  $completeState = [IO.File]::ReadAllText($statePath)

  $null = & $builder -SourceRoot $corpus -OutputPath $index -ValidationReportPath (Join-Path $indexDir 'kb-intelligence-validation.json') 2>&1
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $index)) { throw "index build failed: exit $LASTEXITCODE" }

  # Materialization recorded after the build: the old timestamp check would block as stale.
  [IO.File]::WriteAllText((Join-Path $workspace 'kb-source-metadata.md'), "# KB source metadata`n`n- last_xpz_materialization_run_at: 2999-01-01T00:00:00Z`n", $encoding)
  $structure = Join-Path $scripts 'Test-KbStructure.ps1'
  [IO.File]::WriteAllText($structure, "'STRUCTURE_OK'`n", $encoding)
  $query = Join-Path $scripts 'Query-KbIntelligence.ps1'
  $queryText = @"
param([string]`$Query, [string]`$Format = 'json')
`$global:LASTEXITCODE = `$null
& '$($queryEngine -replace "'", "''")' -IndexPath '$($index -replace "'", "''")' -Query `$Query -Format `$Format
exit `$LASTEXITCODE
"@
  [IO.File]::WriteAllText($query, $queryText, $encoding)
  $gateArgs = @('-RepoRoot', $workspace, '-QueryWrapperPath', $query, '-StructureWrapperPath', $structure)

  function Invoke-GateJson { Invoke-MimirSelfTestScript -ScriptPath $engine -ScriptArgs ($gateArgs + '-AsJson') }
  function Get-Field($Json, [string]$Name) {
    if ($null -eq $Json -or -not ($Json.PSObject.Properties.Name -contains $Name)) { return '<missing>' }
    return $Json.$Name
  }

  # --- GATE_OK on a complete corpus whose generation matches the index ---
  $text = & pwsh -NoProfile -File $engine @gateArgs 2>&1 | Out-String
  Check ($LASTEXITCODE -eq 0 -and $text -match '\bGATE_OK\b') "matching corpus must reach GATE_OK: exit $LASTEXITCODE $text"
  $ok = Invoke-GateJson
  Check ($ok.exit -eq 0 -and (Get-Field $ok.json 'status') -eq 'OK') "matching corpus -AsJson must be OK: $($ok.stdout)"
  Check ((Get-Field $ok.json 'corpus_generation_match') -eq $true -and (Get-Field $ok.json 'corpus_generation') -eq '5a3b0c0de5a3b0c0de5a3b0c0de5a3b0') "OK result must report the matching generation: $($ok.stdout)"
  # Read from the raw JSON text: ConvertFrom-Json turns ISO 8601 strings into DateTime values.
  Check ($ok.stdout -match '"last_xpz_materialization_run_at":\s*"2999-01-01T00:00:00Z"' -and $ok.stdout -match '"last_index_build_run_at":\s*"\d{4}-') "OK result must keep the dates as information: $($ok.stdout)"

  function Test-Block([string]$Case, [string]$ExpectedReason, [string]$RecoveryPattern) {
    $r = Invoke-GateJson
    $reason = [string](Get-Field $r.json 'reason')
    Check ($r.exit -eq 1 -and (Get-Field $r.json 'status') -eq 'BLOCK') "${Case}: gate must block: $($r.stdout)"
    Check ($reason -match [regex]::Escape($ExpectedReason) -and $reason -match $RecoveryPattern) "${Case}: reason must name '$ExpectedReason' and its recovery: $reason"
    Check ((Get-Field $r.json 'corpus_block_reason') -eq $ExpectedReason -and (Get-Field $r.json 'corpus_generation_match') -eq $false) "${Case}: JSON must carry the verdict: $($r.stdout)"
  }

  # --- Corpus state classes ---
  [IO.File]::WriteAllText($statePath, '{"schemaVersion":1,"state":"incomplete","generation":null,"packageSha256":null,"recoveryPackageSha256":null}', $encoding)
  # Only an incomplete corpus may name a package re-run; unknown and invalid offer -FullSnapshot only.
  Test-Block 'incomplete' 'corpus-incomplete' '(?is)re-run the sync of the package that left it incomplete.*FullSnapshot'
  [IO.File]::Delete($statePath)
  Test-Block 'unknown' 'corpus-unknown' '(?is)^(?!.*re-run).*FullSnapshot'
  [IO.File]::WriteAllText($statePath, '{"schemaVersion":"1","state":"complete","generation":"5a3b0c0de5a3b0c0de5a3b0c0de5a3b0"}', $encoding)
  Test-Block 'invalid' 'corpus-invalid' '(?is)^(?!.*re-run).*FullSnapshot'

  # --- Generation mismatch ---
  Set-TestCorpusStateComplete -CorpusRoot $corpus -Generation 'ffffffffffffffffffffffffffffffff'
  Test-Block 'mismatch' 'index-generation-mismatch' '(?i)rebuild'
  # Text mode keeps the BLOCK exception and names the reason too.
  $blockedText = & pwsh -NoProfile -File $engine @gateArgs 2>&1 | Out-String
  Check ($LASTEXITCODE -ne 0 -and $blockedText -match 'BLOCK:' -and $blockedText -match 'index-generation-mismatch' -and $blockedText -notmatch '\bGATE_OK\b') "text mode must throw BLOCK with the reason: $blockedText"

  # --- Busy corpus lock (index-metadata reports it after its bounded retry) ---
  [IO.File]::WriteAllText($statePath, $completeState, $encoding)
  $holderScript = ". '$($lockSupport -replace "'", "''")'; `$l = Enter-GeneXusCorpusLock -CorpusRoot '$($corpus -replace "'", "''")'; [Console]::Out.WriteLine('locked'); [Console]::Out.Flush(); [void][Console]::In.ReadLine(); Exit-GeneXusCorpusLock -Lock `$l"
  $psi = [Diagnostics.ProcessStartInfo]::new('pwsh')
  foreach ($a in @('-NoProfile', '-NonInteractive', '-Command', $holderScript)) { $psi.ArgumentList.Add($a) }
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.UseShellExecute = $false
  $holder = [Diagnostics.Process]::Start($psi)
  try {
    $line = $holder.StandardOutput.ReadLineAsync()
    if (-not $line.Wait(60000) -or $line.Result -ne 'locked') { throw 'lock holder did not start' }
    Test-Block 'lock busy' 'corpus-lock-busy' '(?i)wait'
  } finally {
    $holder.StandardInput.WriteLine('')
    $holder.StandardInput.Close()
    if (-not $holder.WaitForExit(60000)) { $holder.Kill($true) }
    $holder.Dispose()
  }

  # --- Index without a corpus generation (built before generations were recorded) ---
  Invoke-Sql $index "DELETE FROM metadata WHERE key = 'corpus_generation'"
  Test-Block 'missing generation' 'index-generation-missing' '(?i)rebuild'

  # --- A failing index-metadata query keeps its real cause ---
  Invoke-Sql $index "DELETE FROM metadata WHERE key = 'last_index_build_run_at'"
  $failed = Invoke-GateJson
  $reason = [string](Get-Field $failed.json 'reason')
  Check ($failed.exit -eq 1 -and (Get-Field $failed.json 'status') -eq 'BLOCK') "failed query must block: $($failed.stdout)"
  Check ($reason -match 'exit 1' -and $reason -match 'requires metadata\.last_index_build_run_at') "failed query must keep its exit code and stderr: $reason"

  if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("FAIL: $_") }
    exit 1
  }
  'MIMIR_KB_INDEX_GATE_CORPUS_GENERATION_SELFTEST_OK'
} finally {
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
exit 0
