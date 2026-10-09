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
- `sample-kb/Panel/InvoiceSummaryMobile.xml` is a mobile `Panel` whose events
  call `CalculateInvoiceTotal`. The index does not extract `Panel` calls, so it
  makes every reverse-relation answer over `sample-kb` report incomplete
  coverage (`tests/mimir-lite/Test-KbIntelligenceReverseCoverageSelfTest.ps1`).

## Fake CLI backends

- `FakeCliSupport.ps1` provides `New-FakeCli -Directory -Name -PwshBody`, which
  writes a fake command-line tool whose logic is a PowerShell body
  (`<name>.body.ps1`) behind a launcher: `<name>.cmd` on Windows, an
  executable extensionless `#!/bin/sh` script elsewhere. Arguments, stdin,
  stdout, stderr and the exit code pass through on every OS. Self-test:
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
