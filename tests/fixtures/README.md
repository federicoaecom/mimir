# tests/fixtures/

Shared fixtures for the `tests/` suite.

## KbIntelligence validation cases

- No validation-case files for real KBs are kept here, for privacy: such files
  name a real, externally-provided GeneXus KB in their filename and content, and
  they are not self-contained, because running them requires that KB's export
  on disk (`--index-path`/`--validation-cases-path` point at that KB's own
  materialized XML and index). The synthetic `sample-kb` fixture below is the
  self-contained regression case; to validate against a real KB of your own,
  generate a validation-case file in the same format from that KB.
- `sample-kb/` is a synthetic, hand-authored GeneXus KB export (folder-per-type,
  invented Invoice/Customer/Product data only — no real KB content, names or
  GUIDs). Together with `kb-intelligence-sample-kb.validation-extraction.json`,
  `kb-intelligence-sample-kb.validation-queries.json` and
  `tests/mimir-lite/Test-KbIntelligenceSampleKbSelfTest.ps1`, it is fully
  self-contained: the test builds its own index from `sample-kb/` into a temp
  directory and needs no external KB or machine-specific path.
- `sample-kb/.mimir-sync-state.json` marks the fixture as a completely
  synchronized corpus (`schemaVersion` 1, state `complete`, the fixed
  generation `5a3b0c0de5a3b0c0de5a3b0c0de5a3b0`, a zero package hash), the
  shape the XPZ sync writes, so the index builder and query accept it and
  record or compare that generation. The builder and the query take the corpus
  lock, which creates `.mimir-sync.lock` in the corpus: tests build from and
  query a scratch copy of `sample-kb/`, never the checked-in folder (the root
  `.gitignore` ignores a stray lock file). Tests that write their own corpus
  mark it complete with `Set-TestCorpusStateComplete`
  (`tests/mimir-lite/CorpusStateTestSupport.ps1`) or `write_corpus_state`
  (`tests/mimir-lite/_corpus_state_support.py`).
- `sample-kb/Panel/InvoiceSummaryMobile.xml` is a mobile `Panel` whose events
  call `CalculateInvoiceTotal`. The index does not extract `Panel` calls, so it
  makes every reverse-relation answer over `sample-kb` report incomplete
  coverage (`tests/mimir-lite/Test-KbIntelligenceReverseCoverageSelfTest.ps1`).

## Fake CLI backends

- `FakeCliSupport.ps1` provides `New-FakeCli -Directory -Name -PwshBody`, which
  writes a fake command-line tool whose logic is a PowerShell body
  (`<name>.body.ps1`) behind a launcher: `<name>.cmd` on Windows, an
  executable extensionless `#!/bin/sh` script elsewhere. Arguments, stdin,
  stdout, stderr and the exit code pass through on every OS. The optional
  `-ProbeOutput @{ '--version' = '<line>' }` makes the launcher answer a lone
  probe argument itself, without starting pwsh, for tests that do not test the
  probe. Self-test:
  `tests/Test-FakeCliSupportSelfTest.ps1`.

## Python on PATH

- `FakePythonSupport.ps1` serves the self-tests that control which Python a
  child process finds on PATH (`tests/Test-InvokeTestsSelfTest.ps1` and
  `tests/tools/Test-PyScriptsParseSelfTest.ps1`):
  - `New-OldPythonFake -Directory -MarkerPath` writes a fake `python3` that
    reports Python 3.6 on `--version` and writes the marker file on any other
    call (`python3.cmd` on Windows, an executable `#!/bin/sh` script elsewhere),
    to prove that Python discovery skips an interpreter older than 3.8.
  - `New-PwshOnlyPathDirectory -Directory` creates a folder holding only a
    `pwsh` launcher for the running pwsh (`pwsh.cmd` on Windows, a symbolic
    link elsewhere) and returns its path, to use as the whole PATH of a child
    that must find no Python. The pwsh install folder is not used instead,
    because it can be a shared `bin` that also holds a Python.
  - `Invoke-PwshScriptWithExactPath -PathValue -ScriptPath -Parameters` runs a
    script in a child pwsh whose PATH is exactly `-PathValue` and returns its
    output, with the child's exit code in `$LASTEXITCODE`. Setting PATH before
    starting pwsh is not enough: pwsh puts its own install folder (`$PSHOME`)
    in front of PATH at startup, so the child sets PATH itself before running
    the script.

## Shared assertions

- `AssertSupport.ps1` provides `Assert-True`, `Assert-Equal`, `Assert-Match`,
  `Assert-NotMatch` and `Assert-Contains`. Each throws on failure with a
  message that starts with `ASSERT FAILED: `; comparisons are case-sensitive
  and `Assert-Contains` is ordinal. A test that reports every case wraps each
  one in `Invoke-AssertCase -Name -Body` and ends with `Complete-AssertRun`,
  which throws `BLOCK: <n> of <m> case(s) failed` when any case failed.
  Self-test: `tests/Test-AssertSupportSelfTest.ps1`.
- `local-assert-baseline.txt` lists the files that still define their own
  `Assert*` functions. `tests/Test-LocalAssertGuardSelfTest.ps1` fails when
  any other file under `tests/` or `tools/` defines one, and when an entry no
  longer does.
