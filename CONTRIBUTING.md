See also: [Español](CONTRIBUTING.es.md)

# Contributing to Mimir Lite

Thank you for considering a contribution. Contributions are accepted under the project's [MIT License](LICENSE.md). The same care applies throughout: technical rigor, traceability, and no real KB or customer data anywhere in the repository.

## Before you start

- Read [`README.md`](README.md) and [`AGENTS.md`](AGENTS.md) first, plus any documentation directly related to your change.
- Check [`docs/ideas/`](docs/ideas/) for backlog items and previously discarded approaches before re-researching a topic that may already be evaluated.
- Never include credentials, customer data, or content from a real GeneXus KB in an example, fixture, or test. Use the synthetic fixture at `tests/fixtures/sample-kb/` as the reference pattern for anything that needs a KB shape.
- Prefer small, local, easy-to-review changes.

## Setup

1. Clone the repository.
2. Install `pwsh` 7.4+ (7.4.6+ on Linux and macOS) and Python 3.8+ (stdlib only is enough), found as `python3`, `python`, or `py -3`. CI runs on Windows and Linux; macOS is best effort (see [Platform](README.md#platform) and [Known platform differences](README.md#known-platform-differences)).
3. Run the test suite once to confirm your environment is set up correctly:
   ```
   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1
   ```

## Running tests and checks

A change is expected to pass the checks below on Windows and Linux. They are the only checks a contributor must run. `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools/Invoke-CiChecks.ps1` runs them all in order, exactly as CI does, and `pwsh -NoProfile -File tools/Invoke-LinuxTestsInDocker.ps1` runs the same script on Linux in a local Docker container (Docker Desktop on Windows), on the committed HEAD. `pwsh -NoProfile -File tools/Invoke-Python38SmokeInDocker.ps1` runs the Python engines on a real Python 3.8, the minimum, in a `python:3.8-slim` container; run it when a change touches Python code, since the Python parse check only rejects newer syntax, not newer standard-library calls. To measure the index build on a large KB without real content, generate a synthetic corpus with `tools/benchmark/New-SyntheticKbCorpus.py` and measure it with `tools/benchmark/Measure-KbIntelligenceBuild.py`; both use only the standard library, write only under the system temp folder (or a folder you name outside the repository), and report wall-clock time, profile, peak memory, index size, and query times. For a refactor that must not change behavior, `tools/benchmark/Compare-KbIntelligenceBuilds.py` builds each corpus with a baseline and a candidate copy of `skills/mimir-lite/scripts/`, compares every index table and the answers of a fixed set of queries, and exits 1 on any difference. `pwsh -NoProfile -File tools/Invoke-StaticAnalysis.ps1` runs an advisory static analysis with the optional development tools ruff and PSScriptAnalyzer: findings never fail it, and a tool that is not installed is skipped.

CI (`.github/workflows/ci.yml`) runs that script on Windows and Linux on demand (Actions > CI > Run workflow) and for each `v*` release tag, not on every push: hosted-runner minutes are limited on the repository's plan, so day-to-day checks run locally. A tag-triggered run starts after the tag is published, so run CI on demand on the release commit before tagging it.

| Command | Purpose |
|---|---|
| `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1` | Full test suite (`-ThrottleLimit <n>` runs n files at a time, each with its own `TEMP`; default 1, and CI stays sequential; 2 is the tested value) |
| `pwsh -NoProfile -File tools/Test-TextEncoding.ps1` | UTF-8-without-BOM, LF check |
| `pwsh -NoProfile -File tools/Test-PsScriptsParse.ps1` | PowerShell parse check |
| `pwsh -NoProfile -File tools/Test-PyScriptsParse.ps1` | Python parse check |
| `pwsh -NoProfile -File tools/Test-MarkdownFences.ps1` | Markdown code-fence check |
| `pwsh -NoProfile -File tools/Test-MarkdownLinks.ps1` | Markdown link / bare-mention check |
| `pwsh -NoProfile -File tools/Test-ScriptInventory.ps1` | Script inventory completeness |
| `pwsh -NoProfile -File tools/Test-CodeLanguage.ps1` | Code language check (comments and messages in English) |

Maintainers additionally follow an optional review workflow before a push: the pre-push routine in [`docs/process/13-pre-push-review.md`](docs/process/13-pre-push-review.md), with its reinforced and peer-review tiers. It is maintainer practice, not a contributor requirement; `tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson` is available if you want to run its mechanical step.

## Branching and commits

- Work on a feature branch; do not commit directly to `main` for anything beyond a trivial fix.
- [Conventional Commits](https://www.conventionalcommits.org/), in English (e.g. `feat: add impact query for Business Component`, `fix: repoint stale wrapper path`).
- No AI attribution lines in commit messages.
- Keep a commit focused on one coherent unit of work; tests and documentation for a behavior change belong in the same commit as the behavior, not a follow-up.

## Test-driven development

Behavior changes follow strict TDD: write or extend the test first, observe it fail (RED) for the right reason, implement the change (GREEN), then refactor with the test still passing. Do not claim a RED/GREEN step that was not actually observed.

A new extractor rule gets one Python unit test for its parsing function (load the engine with `tests/mimir-lite/_engine_loader.py`, as `tests/mimir-lite/TestBuildKbIntelligenceIndexParsingFunctions.py` does) and one end-to-end self-test, instead of several process-starting cases. A new extractor is one record in `EXTRACTOR_RECORDS` of `skills/mimir-lite/scripts/GeneXusKbIntelligenceCore.py` plus its call in `EXTRACTOR_CALLS` of `Build-KbIntelligenceIndex.py` and its function; `main` runs the records in order.

PowerShell tests dot-source `tests/fixtures/AssertSupport.ps1` for their assertions and define no local `Assert*` function: `tests/Test-LocalAssertGuardSelfTest.ps1` fails on a new one in `tests/` or `tools/`, except for the files listed in `tests/fixtures/local-assert-baseline.txt`. When you touch a listed file for another reason, migrate it to the shared assertions and remove its entry in the same change.

To test an interruption or an overlap of the XPZ sync, the index build, or a query, use the test-only stop points instead of timing a kill: set `MIMIR_TEST_STOP_AT` to one point (`sync:after-mark-incomplete`, `sync:after-xml:<n>`, `sync:before-publish`, `build:before-publish`, or `query:after-lock`) and `MIMIR_TEST_STOP_MODE` to `kill` (the process ends at once, with no cleanup) or `pause` (it writes `MIMIR_TEST_PAUSED <point>` to stderr and waits for a line on stdin while it holds the corpus lock). `tests/mimir-lite/TestCorpusInterruptionAndOverlap.py` shows both modes. Unset, the stop points do nothing.

## Documentation taxonomy

| Folder | What goes there |
|---|---|
| `docs/adr/` | Decision records |
| `docs/ideas/` | Curated backlog of new capabilities and discarded ideas with rationale |
| `docs/process/` | Team working methods (pre-push review, reinforced review, peer review) |
| `docs/i18n/` | Translation policy and glossary |

When you move or rename a file, do it in a commit of its own, without content changes, so git history follows the file.

## Language policy and translations

English is canonical for code, skill payload (`SKILL.md`, `workflows/`, `references/`), and root/human documentation. Root and human docs also get a Spanish translation (`<name>.es.md`). See [`docs/i18n/README.md`](docs/i18n/README.md) for the translation policy and [`docs/i18n/glossary.md`](docs/i18n/glossary.md) for term mappings. Fix or add a glossary term before it appears translated anywhere else; GeneXus object types and API names are never translated.

## Reporting an issue

Describe the problem observed, the expected behavior, steps to reproduce (with sanitized data only), and the affected script, skill, or document. Open an issue in the repository's issue tracker using the bug report or feature request template. Anything sensitive (credentials, customer data, real KB content, exploitable steps) is reported privately instead, as described in [`SECURITY.md`](SECURITY.md).

## Pull requests

When you open a change for review, describe: what changed and why, what was intentionally left out of scope, which tests and checks you ran (and their result), whether `CHANGELOG.md` needs an entry (see [`docs/process/13-pre-push-review.md`](docs/process/13-pre-push-review.md) §4) or why it does not apply, and whether the documentation needs updating. Keep the description in English.
