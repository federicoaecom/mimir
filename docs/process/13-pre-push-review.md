# 13 — Pre-push review routine

> **Maintainer workflow.** This document describes the maintainers' review workflow for this repository. It is optional for contributors: the only checks a contribution must pass are the mechanical checks that CI runs, listed in [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

## Role of this document

This is the authoritative pre-push routine for this repository. `AGENTS.md` points here; agents and maintainers must follow this document before treating a push as ready.

For the optional reinforced tier — a diverse multi-model panel and the convergence rule where the final state is push-ready only after the whole valid panel reports no gaps — see [`14-reinforced-pre-push-review.md`](14-reinforced-pre-push-review.md).

## Scope

The pre-push routine is analysis, coherence search, and reporting to the user. It does not authorize edits, commits, staging, or push. If the routine finds gaps, the agent reports them and may propose a diff or change list, but writes only after explicit user approval after the report. A single explicit approval such as “apply the reported gaps” may cover the whole proposed set unless the user asks for item-by-item approval. This same single-approval exception applies to the reinforced review.

This routine applies to the **Mimir Lite repository**. It is not a GeneXus KB-workspace validation routine. Mimir Lite reads XPZ/XML exports and derived indexes; generating, building, packaging, or importing XPZ and MSBuild flows are out of scope (see [`README.md`](../../README.md#out-of-scope)), and the pre-push mechanics in this document never treat them as live paths.

## Initial mechanical step

Run the orchestrator from the repository root with PowerShell 7.4+ (7.4.6+ on Linux and macOS):

```powershell
pwsh -NoProfile -File tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson
```

The mechanical script defaults `-BaseRef` to `origin/main`; pending commits, commit count, changed files, and `git diff --check` use the same effective interval, `BaseRef..HEAD`. If its default `origin/main` is missing and local `main` exists, it falls back to `main` and records that fallback; an explicitly supplied missing `-BaseRef` fails. The dossier builder separately defaults `-BaseRef` to `origin/main` and does not perform that fallback: pass the same explicit, valid `-BaseRef` to both when the mechanical check selected a non-default base, or Section A and Section B would describe different ranges.

`git diff --check` runs over that same interval and every diagnostic fails the whitespace check; nothing is suppressed, and the JSON and text reports carry the raw Git exit code and the remaining diagnostics. A few reference files hold sanitized-template payload blocks inside fenced code with trailing whitespace on purpose. An interval that does not touch those lines is unaffected (with `commitsAhead=0` there is no interval diff at all). When a change must touch them, the whitespace failure is expected: confirm the payload bytes are intentional and say so in the review report instead of normalizing the payload.

The orchestrator delegates PowerShell parse to [`tools/Test-PsScriptsParse.ps1`](../../tools/Test-PsScriptsParse.ps1), which scans all `*.ps1` under `skills/`, `tools/`, and `tests/`, plus every `*.example.ps1`. It delegates Python syntax to [`tools/Test-PyScriptsParse.ps1`](../../tools/Test-PyScriptsParse.ps1), which scans `*.py` under `skills/`, `tools/`, and `tests/` with `ast.parse` and does not write bytecode. These checks do not replace the semantic phase below.

### Canonical invocation forms

Use one of these forms:

- From repository root: `pwsh -NoProfile -File tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson`
- From another directory: `pwsh -NoProfile -File "<absolute-repo-path>/tools/Invoke-PrePushMechanicalChecks.ps1" -AsJson`

### Limits of the mechanical step

- **PowerShell parse** is repository-wide over `skills/`, `tools/`, `tests/`, and `*.example.ps1`; it is not limited to the interval diff.
- **Python parse** uses `ast.parse`; syntax validation must not depend on writing `__pycache__`.
- **Working tree** changes are reported, but the interval only covers committed changes. With `commitsAhead=0`, there is no interval diff and no `git diff --check` payload.
- **`exit 0` is not push authorization.** Read `PUSH_READINESS` / `pushReadiness`. If it is `blocked`, push is forbidden until the remote is integrated.
- **`pushReadiness=blocked`** makes the interval diff diagnostic only, but the semantic phase over local pending commits is still required.
- **Advisory gates** point at risk candidates; they do not replace the semantic phase and do not authorize closing the review by themselves.

### Fresh remote reference

When the user wants comparison with the current remote, run `git fetch origin` before the mechanical step. A missing ref and a stale local `origin/main` are different cases: the script can diagnose the former, but a stale ref can overstate or understate what is pending.

### Remote ahead (`commitsBehind`)

When `commitsBehind > 0`, `BaseRef..HEAD` no longer cleanly means “only what is waiting to be pushed.” The orchestrator emits `pushReadiness=blocked` without treating parse or whitespace as failed. The review may continue for coherence reporting, but push remains forbidden until the remote is integrated by a human-approved action such as rebase or merge.

## Dossier-assisted mode for semantic-only reviewers

In the reinforced tier ([`14`](14-reinforced-pre-push-review.md)), some reviewers cannot run shell commands. The dossier builder ([`tools/Build-PrePushReviewDossier.ps1`](../../tools/Build-PrePushReviewDossier.ps1)) is git-capable and builds the packet; it is distinct from the `semantic-only` reviewer, who receives it and performs only the semantic phase read-only. A `git-capable` reviewer runs the full routine and independently reproduces Section A; a valid panel retains at least one such reviewer. `semantic-only` reviewers do not run the mechanical step.

The dossier contains:

- **Section A — RAW git (fact):** `rev-parse HEAD`, `log BaseRef..HEAD`, `diff BaseRef..HEAD`, and `status --porcelain`.
- **Section B — mechanical diagnostic, NOT truth:** the entire JSON container from `Invoke-PrePushMechanicalChecks.ps1 -AsJson`, under the script’s literal header `=== SECTION B — ORCHESTRATOR MECHANICAL DIAGNOSTIC (candidates to verify, NOT truth) ===`. The mechanical script owns `pushReadiness` policy; the builder references its diagnostic rather than reimplementing that policy.
- **Sentinels:** final `HEAD:` and `END_DOSSIER sha256=` lines. The SHA-256 covers the UTF-8-without-BOM LF-normalized body, excluding the sentinels. Missing echo with an otherwise on-task review is `responded` + `noEchoSentinel`, not `noResponse`.

If the mechanical JSON is unavailable or invalid, the dossier can still be ready with `mechanicalStatus=failed`; in that degraded mode, the builder only reasserts raw `commitsBehind` from git and leaves `pushReadiness` / `intervalDiffDiagnosticOnly` unknown.

`semantic-only` dispatch is blocked when the working tree is dirty: those reviewers read the live tree but cannot distinguish committed content from uncommitted changes. The orchestrator reports the dirty paths and asks for commit or stash before dispatching them. `git-capable` reviewers may proceed because they can inspect git state themselves.

Transport is separate from capability. `stdin-dossier-capable` adapters such as opencode and Claude Code can receive large dossiers on stdin. `argv-limited` adapters such as Copilot, Gemini, and Antigravity are guarded around 30000 characters; above the cap, the reviewer is omitted as `unavailable` + `dossier-too-large`, never silently truncated. For Antigravity `public-review`, the confidentiality gate runs first: `gateAsk` and `gateDeny` remain gate outcomes; only `allow` for `kb-sensitive` is then refused by the fixed public-review posture as `unavailable` + `refusedSensitivity`. The adapter does not reclassify payloads. The public-review receipt records CLI version, workspace, environment redirection, and cleanup; the system-wide keyring is not isolated, and that limitation must remain explicit.

A valid reinforced panel still needs at least one `git-capable` reviewer that reproduces Section A independently; see [`14`](14-reinforced-pre-push-review.md).

## Semantic phase — per changed workstream

### 1. Inventory the workstream

List terms, scripts, wrappers, parameters, states, paths, public tokens, and operational rules introduced or changed by the workstream.

### 2. Repository search

Search the whole repository for the same terms. Do not stop at the first file.

When a workstream changes a version, signature, evidence code, extraction rule, state name, parameter, alias, flag, option, backend, gate, exit code, or any enumerated set, search both the old terms and the new terms. Searching only the new term misses stale closed enumerations that list only the old members.

[`tools/Test-PrePushNewTokenPropagation.ps1`](../../tools/Test-PrePushNewTokenPropagation.ps1) supports this mechanically when a hunk co-locates an introduced token with an old token. It emits candidates grouped by `mentionClass`:

- `prose` candidates may receive a collective justification when the omission is intentionally non-contractual.
- `param-list-item`, `param-table-cell`, and `command-example` candidates require an item-by-item ledger: file:line, the twin list/table/example, and `gap` or `justified`. The complete non-prose ledger is mandatory in the report; do not stop after finding a gap or aggregate items under a prose rationale. Complete it before concluding whenever non-prose candidates exist.

The orchestrator projects `candidateCount`, `classCounts`, `truncated`, `truncatedProseCount`, and `nonProseVerdictRequired`. `-MaxFindings` caps only `prose`; non-prose candidates are never truncated. If prose was truncated, `truncatedProseCount` reports the discarded count, and the dossier's mechanical diagnostic warns that listed prose candidates are not exhaustive (text output uses `NEW_TOKEN_PROPAGATION_PROSE_TRUNCATED=`). `pairsConsidered` records token pairs, not omitted findings. When non-prose candidates exceed the threshold currently documented by the orchestrator (> 5), a second semantic pass by a different model is recommended before closing the verdict.

Closed enumerations are also checked by advisory gates:

- [`tools/Test-PrePushGateEnumerationParity.ps1`](../../tools/Test-PrePushGateEnumerationParity.ps1) derives the current advisory gate set from the orchestrator.
- [`tools/Test-PrePushBackendEnumerationParity.ps1`](../../tools/Test-PrePushBackendEnumerationParity.ps1) derives the delegation backend set from `$AdapterScript` in [`skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1`](../../skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1).

Use `<!-- backend-parity: ignore -->` only for intentional dated or per-axis subsets, such as a measurement note, incident record, or comparison of two named backends. Do not mark live contracts such as dispatcher branches, capability matrices, gate sets, or adapter enumerations. When unsure, triage the warning instead of silencing it.

### 3. Documentation comparison

Compare the affected documentation with related documents and code, including:

- related skills and workflows, including cross-cutting docs that describe a shared script even if they are outside the diff;
- [`README.md`](../../README.md);
- [`skills/mimir-lite/references/02-operational-rules.md`](../../skills/mimir-lite/references/02-operational-rules.md);
- [`skills/mimir-lite/references/08-agent-guide.md`](../../skills/mimir-lite/references/08-agent-guide.md);
- [`skills/mimir-lite/references/09-script-inventory.md`](../../skills/mimir-lite/references/09-script-inventory.md) when a shared script, method contract, skill, operational name, state, parameter, wrapper, or public traceability item changed. It is a pointer index (one line per script: role, normative owner, validation pointer); check pointer correctness and whether the role summary still fits, not whether it duplicates the owner's detailed contract;
- canonical `*.example.ps1` files under affected workflows, currently mainly [`skills/mimir-lite/workflows/setup/examples/`](../../skills/mimir-lite/workflows/setup/examples/);
- shared engines under `skills/mimir-lite/scripts/`, `skills/mimir-delegate/scripts/`, and repository tools under `tools/`.

[`tools/Test-PrePushSharedScriptSkillCoverage.ps1`](../../tools/Test-PrePushSharedScriptSkillCoverage.ps1) lists SKILL/workflow/checklist documents that cite a changed shared script but are not in the diff. It is advisory: compare the contract or justify why the change does not affect that document.

When a shared operational rule changes, `02-operational-rules.md` must either carry the rule or the report must justify its absence. Coverage only in `08`, `09`, a skill, or `README` is not enough.

For shared engines consumed by local wrappers or other consumers, a breaking output or consumption change must be matched by detection of stale consumers in the auditing workflow. A changelog note alone is not enough if a drift-detection check exists and remains blind.

Before reporting that a term, self-test, script, rule, or evidence is absent from a document, reconcile all searches and snippets already collected. If results conflict, reopen the target file at the cited place before confirming a gap.

### 4. `CHANGELOG.md`

For each changed workstream, decide whether there is user-visible behavior, an operational contract change, public script/skill/governance/security/contribution change, removal, rename, or relevant incompatibility. If yes, `CHANGELOG.md` needs an `Unreleased` entry before release. If it is not updated, the pre-push report must explicitly classify the changelog flag as discarded and justify why omission is acceptable.

### 5. Engine/document parity

When documentation names an engine, parameter, exit code, state, or rule, read the cited `.ps1` / `.py` code. If the doc cites two artifacts in one rule, both must exist in the engine or wrapper. If a paired engine makes the same decision, it should expose the same contract unless the report justifies asymmetry.

Objective red flags include:

- docs promising an effective catalog while `Query-KbIntelligenceIndex` does not resolve catalog overrides;
- `Build-KbIntelligenceIndex.ps1` exposing `-KbWorkspaceRoot` while `Query-KbIntelligenceIndex.ps1` lacks the equivalent where the same decision requires it;
- extractor signature version changes with stale operational docs;
- index-extraction rules changing without `02-operational-rules.md` explaining what the index materializes and what still requires XML reading.

When a workstream introduces a block, refusal, validation, `Stop-WithReason`, `BLOCK: ...`, `ValidateSet`, `ValidateRange`, or similar predicate, explicitly enumerate neighboring axes and give a verdict for each: closed, intentionally open with justification, or residual. Common axes are writer vs reader, alternate parameter reaching the same state, alternate spelling of the same key, titular vs fallback-chain link, and `public` vs `kb-sensitive` mode.

### 6. Long skill and satellite rule

When aligning a name or contract in a long skill or workflow, scan the satellites that the file tells agents to load before considering the workstream closed. The three cuts are final checklist/closing gates, operational flow and result capture, and script/contract inventory.

### 7. Gap checklist

Check for:

- old docs contradicting new behavior;
- stale canonical examples;
- scripts whose contract diverges from their description;
- checklists promising validation the script does not perform;
- stale satellite docs;
- a newly documented tool missing from correlated skills/workflows;
- stale or too-aggregated traceability in `09-script-inventory.md`;
- a documented new contract without self-test coverage, or a report that coverage is absent;
- a new block/validation without the neighboring-axis verdict required above;
- public-impact changes without `CHANGELOG.md` entry or explicit omission rationale.

Use candidate-gap reporting for adjacent pre-existing traceability holes: separate attribution (“not introduced by this workstream”) from merit (“may still be worth recording”). Do not bias the user toward discarding it automatically.

### 8. Report before editing

The semantic phase produces a report, including confirmed gaps (or their absence), discarded flags with justification, and search areas not covered, whether or not gaps are found. Between that report and any edit, commit, stage, or push there is a mandatory human validation point. If gaps are found:

1. Report the proposed corrections.
2. Stop. Do not edit files.
3. Wait for explicit approval for the proposed changes.
4. Only then apply corrections.

There is no “small enough to fix without asking” exception inside pre-push review.

### 9. Verdict

End with exactly one fixed line:

`VERDICT: no confirmed gaps`

or

`VERDICT: N confirmed gap(s)`

Warnings, discarded flags, and uncovered areas do not count as confirmed gaps. Missing verdict means pre-push review is incomplete.

## Conclusion

The pre-push routine is not complete until the semantic phase has been executed and reported, even when `git diff --check`, parse checks, and local tests are clean. Do not treat the mechanical step as push authorization, especially when `PUSH_READINESS=blocked`.

## Search patterns by workstream type

### Effective catalog / KbIntelligence

- Positive terms in the cited engines: `merge`, `override`, `KbWorkspaceRoot`, `catalog-override-path`, `GeneXusObjectTypeCatalogCore`, `resolve_effective`.
- Negative signal: a fixed `gx-object-type-catalog.json` path in the same flow that applies `queryableByKbIntelligence` or a semantic block, with no merge/override path.

## Orchestrator scripts

| Script | Role |
|---|---|
| [`tools/Invoke-PrePushMechanicalChecks.ps1`](../../tools/Invoke-PrePushMechanicalChecks.ps1) | Mechanical orchestrator: git context, parse gates, `git diff --check`, advisory warnings, and push readiness. |
| [`tools/Build-PrePushReviewDossier.ps1`](../../tools/Build-PrePushReviewDossier.ps1) | Builds the raw-git + mechanical-diagnostic dossier for reinforced `semantic-only` reviewers. |
| [`tools/Test-PsScriptsParse.ps1`](../../tools/Test-PsScriptsParse.ps1) | Parses PowerShell files under `skills/`, `tools/`, `tests/`, plus `*.example.ps1`. |
| [`tools/Test-PyScriptsParse.ps1`](../../tools/Test-PyScriptsParse.ps1) | Parses Python files under `skills/`, `tools/`, and `tests/` with `ast.parse`, without bytecode. |
| [`tools/Test-PrePushTraceabilityCoverage.ps1`](../../tools/Test-PrePushTraceabilityCoverage.ps1) | Advisory traceability and engine/doc parity candidates, including `09-script-inventory.md` pointer-index risks. |
| [`tools/Test-GeneXusUnexpectedCharacter.ps1`](../../tools/Test-GeneXusUnexpectedCharacter.ps1) | Advisory unexpected-Unicode detection over added `.md` / `.ps1` diff lines. |
| [`tools/Test-PrePushNewTokenPropagation.ps1`](../../tools/Test-PrePushNewTokenPropagation.ps1) | Advisory new-token propagation candidates from co-located diff transitions. |
| [`tools/Test-PrePushSharedScriptSkillCoverage.ps1`](../../tools/Test-PrePushSharedScriptSkillCoverage.ps1) | Advisory candidates for shared scripts whose documenting skills/workflows were not touched. |
| [`tools/Test-PrePushGateEnumerationParity.ps1`](../../tools/Test-PrePushGateEnumerationParity.ps1) | Advisory gate-enumeration parity against the orchestrator’s current advisory gates. |
| [`tools/Test-PrePushBackendEnumerationParity.ps1`](../../tools/Test-PrePushBackendEnumerationParity.ps1) | Advisory backend-enumeration parity against `$AdapterScript` in the panel dispatcher. |

## Mirrors in other documents

- [`skills/mimir-lite/references/08-agent-guide.md`](../../skills/mimir-lite/references/08-agent-guide.md): operational summary for agents. If it diverges, this file (`13`) prevails for the full pre-push routine.
- [`skills/mimir-lite/references/09-script-inventory.md`](../../skills/mimir-lite/references/09-script-inventory.md): script inventory and owner pointers for the scripts above.
