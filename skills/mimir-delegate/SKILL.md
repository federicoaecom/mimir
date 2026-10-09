---
name: mimir-delegate
description: Lets the main agent delegate small tasks, ask for a second opinion, or run a multi-model panel peer review (painel multi-modelo) of a plan or design through opencode, Codex, Claude Code (Opus 4.8), GitHub Copilot CLI, Gemini CLI, or Antigravity CLI; on "peer review"/"revisão por pares", load this skill, ask for preferred reviewers if no resolved list exists (cascade preferred-reviewers.<orchestrator>.json → machine), never assume an external subscription, and never label a solo opinion as a peer review; always human-triggered
---

# Mimir Delegate

Operator-first contract for delegating small tasks, requesting second opinions,
and running real multi-model peer review. This skill does **not** manipulate
XPZ/XML; it belongs to the `mimir-lite` family and operates from the repository
root or, under the confidentiality rules below, from a KB workspace.

Active backends: **opencode** (#1), **Codex** (`codex exec`, #2), **Claude Code**
(`claude -p`, Opus 4.8 default, #3), **GitHub Copilot CLI** (`copilot -p`, #4),
**Gemini CLI** (`gemini -p`, #5), and **Antigravity CLI** (`agy -p`, #6).
Future backends plug in as an invocation adapter plus a locality resolver wired
into the same authorization gate.

<!-- backend-parity: ignore --> Platform: like `mimir-lite`, Windows and Linux
(tested in CI; on Linux the adapters run against fake CLIs), macOS best effort.
CLI discovery: an explicit `-<Tool>Exe` parameter always wins. Without it, on
Windows, Codex comes from the Codex desktop app's binaries
(`%LOCALAPPDATA%\OpenAI\Codex\bin`; the npm shim is rejected), and opencode and
the Antigravity CLI from `PATH`, then `%APPDATA%\npm` and `%LOCALAPPDATA%\agy`.
On Linux and macOS every CLI comes from `PATH`; for Codex, the first `codex` that
answers `codex --version`. On Linux and macOS, the stdin-based adapters deliver
the prompt with one extra trailing newline (harmless; see section 11). State
folder: see section 2, step 2.

> <!-- backend-parity: ignore --> **Conceptual separation note:** installing
> Antigravity as an agent tool managed by the `mimir-lite` install workflow is
> about skill registration and global instructions. It is not the same as the
> Gemini CLI backend (`google/*`) or Antigravity CLI backend (`antigravity/*`)
> defined here.

Peer-review methodology and convergence rules are owned by
[`15-peer-review.md`](references/15-peer-review.md). Reinforced
pre-push review is owned by
[`14-reinforced-pre-push-review.md`](../../docs/process/14-reinforced-pre-push-review.md).
This file owns the delegation mechanics, hard gates, adapter contracts, and
operator workflow.

---

## 1. Non-negotiable gates

- **Human trigger only.** Never invoke a subagent automatically. Suggesting is
  allowed; execution requires a user request or explicit agreement.
- **The strong agent keeps judgment.** Never delegate structural GeneXus
  decisions, object risk/family/type classification, import/build/security
  decisions, gate verdicts, or any decision that becomes a write action.
- **Output is evidence, not truth.** Validate delegated output before using it;
  do not trust timestamps, counts, or factual claims reported by the subagent.
- **Confidentiality is gate-driven.** Classify the payload as `public` or
  `kb-sensitive`, then run `Resolve-LlmDelegateAuthorization.ps1` before sending
  any payload to a model. When uncertain, use `kb-sensitive`.
- **Announce the destination every time.** Even with durable authorization, tell
  the user which `targetModelKey` receives the payload and whether it is local or
  external.
- **Authorization is not preference.** `allow` means delivery is permitted, not
  that a reviewer was selected or that the choice is prudent. Preference comes
  only from the human or `preferred-reviewers*.json`.
- **No solo peer-review label.** Use `peer review` only with a valid panel (at
  least two effectively consulted Model Creators) and a receipt. Otherwise label
  the result `solo opinion` or `second opinion (N)`, translated into the user's
  language when answering in another one.
- **A near-immediate response is not peer review.** Under 30 seconds is evidence
  that no real panel occurred, unless reporting an identifiable prior panel with
  receipt/ledger.

## 2. Peer-review entry contract

When the user asks for `peer review`, a multi-model panel, or a multi-model
plan validation, in any language (the description lists the trigger phrases):

1. Read this file and, when available, the methodology
   [`15-peer-review.md`](references/15-peer-review.md).
2. Resolve preferred reviewers:
   `Resolve-LlmDelegatePreferredReviewers.ps1 -Orchestrator <orchestrator-slug>`
   (the session harness: `cursor`, `claude-code`, `codex`, `opencode`, or any other
   lowercase slug such as `my-tool`; under a harness this repo cannot identify,
   native primary reviewers are diagnosed as unverifiable and must not count toward the
   diversity floor until the orchestrator confirms them).
   The source of truth is the resolver envelope only (`hasPreferences`,
   `preferenceSource`, `effectivePreferredPath`). Do **not** search the repo for
   `preferred-reviewers*.json` or `capabilities.json` in the machine-level state
   folder of this skill (`%LOCALAPPDATA%\mimir-delegate` on Windows;
   `~/.local/share/mimir-delegate` on Linux, or `$XDG_DATA_HOME/mimir-delegate`
   when that is set; on macOS, the .NET local application data folder, typically
   `~/Library/Application Support/mimir-delegate`, or the Linux location when
   `~/Library/Application Support` does not exist; not tested in CI).
   Cascade: `preferred-reviewers.<orchestrator>.json`
   (schema 3) → machine `preferred-reviewers.json` (schema 3). Unreadable files
   or `schemaVersion != 3` fail closed (exit 2) and do not fall through. When the
   state folder cannot be determined, the resolver does not fail: it returns
   `hasPreferences=false` with a `state-root-unavailable` entry in `diagnostics` and
   treats the capability manifest as missing (explicit `-PreferredRoot`,
   `-PreferredPath`, and `-CapabilitiesPath` still work).
3. If `hasPreferences=false`, ask which tools/models the user has and wants to
   use: `Claude Code`, `opencode/Ollama Cloud`, `Codex`, `Copilot`, `Gemini`,
   `Antigravity CLI`, or the current tool's native subagent. This calibrates
   subscription/login and preference; detected inventory is only diagnostic and
   must be phrased as "detected; confirm if you want to use it." Do not recommend
   Gemini, Copilot, Codex cloud, Antigravity, or any external service without a
   confirmed preference or existing conversation context. After the user picks
   reviewers, offer to save **that already-made selection** using
   `Set-LlmDelegatePreferredReviewers.ps1`; this is separate from per-KB
   authorization and does not block the round if declined.
4. Native subagent: represent as `type=orchestrator-native-subagent`,
   `backend=orchestrator-native`; it participates with the Creator of
   `targetModelKey`, never enters the CLI dispatcher's `ReviewersJson`, and does
   not by itself satisfy the floor if it is the only creator.
5. Run the per-destination authorization gate and diversity floor before
   consulting reviewers. Missing `ask`s required for the floor are batched to the
   human; never silently drop them.
6. Before the final receipt, run
   `Resolve-LlmDelegatePeerReviewCloseout.ps1`. If preferred reviewers were in
   play, pass `-PreferredReviewersSnapshotJson` from the initial `Resolve-` call
   and final states for every preferred reviewer. If no resolved list existed
   and reviewers were manually selected, closeout must block until the save-offer
   state is recorded. Exception: when the state folder cannot be determined and no
   `-ProposedPreferredPath` is given, the optional offer is skipped without
   blocking, and `receiptAddendum` carries the warning. A preferred reviewer is
   never an optional silent pool.
7. If the orchestrator authored a consolidated vN+1, closeout must receive
   `-VNextState pendingResubmission`; completion remains blocked until
   `resubmitted` or an audited human decline:
   `-VNextState resubmissionDeclinedByHuman -ResubmissionDeclinedBy <who>
   -ResubmissionDeclineReason <reason> -RoundId <round>`. Two decline subcases
   share the same state: design freeze moving proof to implementation/self-test,
   and abandonment of the cycle. Neither is `resubmitted`.
8. Minimum receipt: methodology files read, manuscript/prompt, reviewers and
   families, diversity-floor result, each verdict/state, closeout result, and
   `vNextState`.

### Mandatory no-preference user prompt

When `hasPreferences=false`, before any delivery:

1. State that no preferred-reviewers list is configured.
2. State payload class (`public` or `kb-sensitive`).
3. Ask: "Which tools/models do you have and want to use as reviewers?"
4. Cite recognizable examples, filtering out anything already dismissed.
5. State that inventory and authorization verdicts are diagnostics, not
   preference; the gate will run per destination after the choice.

Forbidden at this point: "one obvious option would be", "the simplest path
would be", "I suggest X + Y", or any default composition involving an external
reviewer without registered preference.

## 3. Axes and confidentiality

Do not conflate the four axes:

| Axis | Owns | Never substitutes for |
|---|---|---|
| Backend/Harness | How the prompt is sent (`Invoke-*` adapters) | destination or confidentiality |
| Destination Provider | Where traffic goes (`targetModelKey`, policy key) | Model Creator/diversity |
| Model Creator | Diversity floor (via `Get-LlmDelegateTargetFamily`) | destination/provider |
| Model Family | Descriptive category in the methodology | a mechanical gate |

Legacy code names `family` and `Get-LlmDelegateTargetFamily` represent Model
Creator (#3). The gate derives destination directly from the raw model-key
prefix, never from creator.

**Destination invariant:** policy/gate keys are destination `provider/model`,
never adapter names. Codex with `gpt-5.5` uses `openai/gpt-5.5`; Claude Code
Opus 4.8 uses `anthropic/claude-opus-4-8`; Copilot uses
`github-copilot/<model>`; Gemini uses `google/<model>`; Antigravity uses
`antigravity/<model>` (not `google/*`, even for Gemini underlying models).
There is no `codex/*`, `claude-code/*`, `copilot/*`, `gemini/*`, or `agy/*`
policy namespace.

**Locality is deterministic; sensitivity is contextual.** Resolver modules read
backend config/base URLs and normalize known cloud providers; the agent decides
whether payload origin makes it `public` or `kb-sensitive`.

Gate logic:

```text
payload public                     -> allow
payload kb-sensitive + local        -> allow
payload kb-sensitive + external/unknown:
  policy allow-external             -> allow
  policy deny-external              -> deny
  policy ask/unset/no file           -> ask
```

Per-KB policy: `llm-delegation-policy.json` at KB workspace root; the gate
finds it with `-KbWorkspaceRoot <root>`. Matching order: exact key → `provider/*` → `*` →
`defaultExternal` → `ask`. Valid entry values: `allow-external`,
`deny-external`, `ask`.

### KB-sensitive external delivery

For `kb-sensitive` to any external destination, before sending enumerate in the
same authorization message, without suggesting an answer:

1. what concretely leaves (category + scope + sample for large payloads);
2. count and named list of external destinations, each an independent
   disclosure;
3. irreversibility: no recall under the agent's control; retention/logging or
   training may apply depending on destination.

Then stop and wait. Consent is per destination and per invocation/session; no
carry-over. If any content already leaked, state what leaked and treat it as a
new notice. Receipt fields: `riskNotice{what,destinations[],irreversibility}`;
when overriding all-external/no-local caution, `overrideOfFindingB=consciousOverride`,
`humanAuthorizer`, `authorizationTextRef`, and resolved `localReviewerStatus`
(`noneAvailable|unavailable|declined|inadequate`). `consciousOverride` is
incompatible with a skipped local-reviewer check.

### All-external preferred composition in a KB workspace

Preferred lists are machine-level and context-agnostic. In a `kb-sensitive`
context, if the preferred composition is all external, warn and ask whether to
include a local reviewer before dispatch. If no local reviewer is available,
stop and report; external-only proceeding is a conscious override requiring
explicit textual authorization. Do not present "proceed external-only" as a
neutral co-equal option. Gate `deny` still vetoes delivery; gate `allow` does
not remove this prudence layer or the risk notice.

## 4. Reviewer curation and capability

Three artifacts are distinct:

| Artifact | Scope | Purpose | Gate truth? |
|---|---|---|---|
| `llm-delegation-policy.json` | KB workspace | durable delivery authorization | yes, through the gate |
| `capabilities.json` | machine | sanitized probe of installed/known backends | no, offer hint only |
| `preferred-reviewers*.json` | machine/orchestrator | human curation and ranks | no, preference only |

Capability discovery order: `capabilities.json` → chosen backend's
`Resolve-*ModelLocality` → `opencode models`. `Get-Command`, `--version`, and
`--help` are last-resort diagnostics, never proof of subscription/preference.
Freshness uses `capabilities.json.generatedAt` (not `updatedAt`, which belongs
to preferences). Fresh machines: ask the human; use round-only live probes for
chosen backends; offer to generate the manifest opt-in; never fabricate a
composition or silently create a stub.

Preferred-reviewer persistence after manual selection is independent from
per-KB authorization. Scope rule for `Set-LlmDelegatePreferredReviewers.ps1`:
resolve first, then edit `-Scope orchestrator` when the request is for this
harness and an orchestrator file exists or is the effective source; use
`-Scope machine` only for explicit machine-list requests or when machine is the
effective choice. Show effective path, `preferenceSource`, current ranks, and
shadowing diagnostics before/after writing. Native primary reviewers require
`-Scope orchestrator`; a native entry in the machine file, or a native key that
names another harness, is refused on write and on read. `Set-` accepts only
schema 3 input (`reviewers-schema-unsupported` otherwise), and a primary reviewer names
its destination with `targetModelKey` only.

## 5. Operator workflow

1. Confirm human trigger.
2. Confirm the task is delegable; if it is GeneXus judgment, stop.
3. Classify payload as `public` or `kb-sensitive`.
4. For peer review, resolve preferred reviewers; if absent, ask the calibration
   question; later offer to save the human's selected reviewers.
5. Run `Resolve-LlmDelegateAuthorization.ps1` with model, sensitivity and
   `-Backend <opencode|codex|claude-code|copilot|gemini|antigravity|orchestrator-native>`.
   In a KB workspace pass `-KbWorkspaceRoot <root>` unless using explicit
   `-PolicyPath`.
   `allow` → proceed and announce destination; `deny` → do not send and offer a
   local alternative; `ask` → request explicit authorization and offer durable
   persistence.
6. Invoke the adapter (raise `-TimeoutSec` for long tasks), or
   `Invoke-LlmDelegatePanelDispatch.ps1` for panel collection.
7. Validate output, reclassify off-task/threadbare `responded` as `noResponse`
   when applicable, run closeout, then produce the receipt.

## 6. Scripts and exact operator signatures

All scripts live in `skills/mimir-delegate/scripts/`.

### Invocation adapters

- `Invoke-OpenCode.ps1 [-Message <prompt> | -MessagePath <file>] [-Model <p/m>] [-Agent <n>] [-OpenCodeExe <path>] [-Raw] [-AllText] [-TimeoutSec <1-3600>] [-MaxAttempts <1-3>]`
- `Invoke-Codex.ps1 [-Message <prompt> | -MessagePath <file>] [-Model <m>] [-Oss] [-LocalProvider <ollama|lmstudio>] [-Profile <id>] [-Cd <dir>] [-CodexExe <path>] [-TimeoutSec <1-3600>] [-TempDir <path>] [-KeepDays <n>] [-RetentionMode public|kb-sensitive]`
- `Invoke-ClaudeCode.ps1 [-Message <prompt> | -MessagePath <file>] [-Model <m>] [-PermissionMode <mode>] [-Tools <list>] [-Cd <dir>] [-ClaudeExe <path>] [-TimeoutSec <1-3600>]`
- `Invoke-ClaudeCodeAsync.ps1 [-Message <prompt> | -MessagePath <file>] -SidecarPath <json> [-Model <m>] [-PermissionMode <mode>] [-Tools <list>] [-Cd <dir>] [-ClaudeExe <path>] [-TimeoutSec <1-3600>] [-RetentionMode public|kb-sensitive] [-CircuitStateRoot <dir>] [-TempDir <dir>]`
- `Invoke-Copilot.ps1 [-Message <prompt> | -MessagePath <file>] [-Model <m>] [-Cd <dir>] [-CopilotExe <path>] [-TimeoutSec <1-3600>]`
- `Invoke-Gemini.ps1 [-Message <prompt> | -MessagePath <file>] [-Model <m>] [-ApprovalMode plan] [-Cd <dir>] [-GeminiExe <path>] [-TimeoutSec <1-3600>]`
- `Invoke-Antigravity.ps1 [-Message <prompt> | -MessagePath <file>] [-Model <m>] [-Profile public-review] [-Mode plan] [-ReceiptPath <json>] [-ScratchPath <path>] [-SimulateCleanupFailure <none|degraded|failed>] [-AntigravityExe <path>] [-TimeoutSec <1-3600>]` (no `-Cd`: the profile always creates its own scratch cwd)

### Locality, authorization, curation, and panel scripts

- `Resolve-OpenCodeModelLocality.ps1 -Model <provider/model> [-ConfigPath <opencode.json|jsonc>]` → JSON `{ locality, baseUrl, reason }`.
- `Resolve-CodexModelLocality.ps1 [-Model <m>] [-Oss] [-LocalProvider <ollama|lmstudio>] [-Profile <id>] [-ConfigPath <config.toml>]` → `{ locality, baseUrl, canonicalModel, reason }`.
- `Resolve-ClaudeCodeModelLocality.ps1 [-Model <m>]` → `{ locality, canonicalModel, reason }`.
- `Resolve-CopilotModelLocality.ps1 [-Model <m>]` → `{ locality, canonicalModel, reason }`.
- `Resolve-GeminiModelLocality.ps1 [-Model <m>]` → `{ locality, canonicalModel, reason }`.
- `Resolve-AntigravityModelLocality.ps1 [-Model <m>]` → `{ locality, canonicalModel, reason }`.
- `Resolve-OrchestratorNativeModelLocality.ps1 [-Model <m>]` → `{ locality, canonicalModel, reason }`; never local.
- `Resolve-LlmDelegateAuthorization.ps1 [-Model <m>] -PayloadSensitivity <kb-sensitive|public> [-Backend <opencode|codex|claude-code|copilot|gemini|antigravity|orchestrator-native>] [-Oss] [-LocalProvider <p>] [-Profile <id>] [-ConfigPath <opencode.json|config.toml>] [-PolicyPath <json>] [-KbWorkspaceRoot <dir>]` → JSON `{ verdict: allow|ask|deny, targetModelKey, policyFileName, ... }`.
- `Build-LlmDelegateCapabilityManifest.ps1 [-OutputPath <json>] [-SnapshotPath <json>] [-OpenCodeConfigPath <opencode.json|jsonc>] [-CodexConfigPath <config.toml>] [-ClaudeSettingsPath <settings.json>] [-ClaudeStatsCachePath <stats.json>] [-AntigravityExe <path>] [-AntigravityProbeTimeoutSec <s>]` (`-AntigravityProbeTimeoutSec` is a test-only seam). Writes sanitized `capabilities.json`; no tokens, keys, base URLs, headers, config paths, prompts, or policy.
- `Set-LlmDelegatePreferredReviewers.ps1 -ReviewersJson <json> -Orchestrator <orchestrator-slug> -Scope <machine|orchestrator> [-PreferredRoot <dir>] [-OutputPath <json>] [-Preview] [-Overwrite]`.
- `Resolve-LlmDelegatePreferredReviewers.ps1 -Orchestrator <orchestrator-slug> [-PreferredRoot <dir>] [-PreferredPath <json>] [-CapabilitiesPath <json>]`.
- <!-- backend-parity: ignore --> `Resolve-LlmDelegatePanelDiversity.ps1 -CandidatesJson <json> [-Floor <n>] [-AuthorFamily <fam>]`.
- `Resolve-LlmDelegatePeerReviewCloseout.ps1 -HadPreferredReviewers <true|false> -ManualReviewerSelection <true|false> [-PreferredReviewersOfferState not_made|offered|accepted|declined|deferred|not_applicable] [-RoundId <id>] [-SelectedReviewersJson <json>] [-PreferredReviewerStatesJson <json>] [-DiversityState <state>] [-VNextState notProduced|pendingResubmission|resubmitted|resubmissionDeclinedByHuman] [-ResubmissionDeclinedBy <who>] [-ResubmissionDeclineReason <reason>] [-PreferredReviewersSnapshotJson <json>] [-EffectivePreferredPath <path>] [-PreferenceSource <source>] [-PreferredRoot <dir>] [-Orchestrator <orchestrator-slug>] [-ProposedPreferredPath <path>]`.
- `New-LlmDelegatePeerReviewArtifacts.ps1 [-ManuscriptText <text> | -ManuscriptPath <file>] -ReviewersJson <json> [-RoundId <safe id>] [-TempDir <dir>] [-FailAt <test seam>]` — accepts exactly one manuscript source; writes `manuscript.md`, `reviewers.json`, and `preparation-manifest.json` under `<TempDir>/<RoundId>` via staging; stdout is one JSON line `mimir-peer-review-artifacts-result`.
- `Invoke-LlmDelegatePanelDispatch.ps1 (-ManuscriptPath <file> | -ManuscriptText <text>) -ReviewersJson <file|inline> -PayloadSensitivity <public|kb-sensitive> [-RoundId <safe id>] [-Cd <dir>] [-KbWorkspaceRoot <dir>] [-PolicyPath <json>] [-TempDir <dir>] [-OllamaConcurrency <1-16>]` plus test-only `-OpenCodeConfigPath`, `-CodexConfigPath`, `-BackendExeMap`, `-ClaudeCircuitStateRoot`.

### Support modules and self-tests

Support modules: `OpenCodeCliSupport.ps1`, `OpenCodeStreamSupport.ps1`,
`CodexCliSupport.ps1`, `ClaudeCodeCliSupport.ps1`, `CopilotCliSupport.ps1`,
`GeminiCliSupport.ps1`, `AntigravityCliSupport.ps1`, and
`LlmDelegateTargetFamilySupport.ps1`. Their corresponding self-tests live under
`tests/mimir-delegate/` and are the canonical enumeration for detailed helper
edge cases.

## 7. Backend contracts and limits

### opencode

<!-- backend-parity: ignore -->
`Invoke-OpenCode` is stdin-based, blocks until a response, default
`-TimeoutSec 1200` per attempt, validated range `1..3600`; `-AllText` returns
full narration, otherwise final answer; `-Raw` bypasses normal classification
where documented. `-MessagePath` is mutually exclusive with `-Message` and keeps
the prompt out of argv. `-MaxAttempts` default 1, range 1..3; retry only happens
on `truncated`/`no-completion`, never on timeout, exit non-zero, stream error,
clean `empty`, or `-Raw`. Before actually retrying, it re-checks the usage/rate
limit in the attempt's window; a hit is terminal (no retry) to avoid re-burning
quota. Each retry writes
`OPENCODE_RETRY: attempt=N status=… reason=…` to stderr. `-TimeoutSec` is per
attempt, so wall-clock can multiply.

No default agent is applied. Without `-Agent`, opencode uses its own config
(typically `build`). With explicit `-Agent`, the adapter verifies it resolves in
`opencode agent list` and scans stderr for fallback warnings. Anyone needing
least privilege must provision and name a restricted agent.

Use provider/model ids accepted by opencode; for Ollama Cloud use
`ollama-cloud/deepseek-v4-pro`, not a short name. Catalog presence is not proof
of availability: HTTP 410 model-gone is permanent and should be recorded as
`unavailable`/`model-gone`, not timeout/quota. Log-based 429/quota detection is
time-window based and machine-shared; concurrent runs can misattribute orphan
log lines. `Format-OpenCodeLimitBlock` is evidence, not exclusive proof.

### Codex

<!-- backend-parity: ignore -->
`Invoke-Codex` is stdin-based, fixed read-only sandbox, default `-TimeoutSec
1200`, range `1..3600`. Omitting `-Model` lets Codex/config choose. Final answer
comes from `output-last-message`, persisted to `<TempDir>/<GUID>.lastmsg.txt`;
JSONL stream goes to `<GUID>.stream.jsonl`; `TempDir` cascade is bound value →
`MIMIR_CODEX_JOBS_DIR` → `%TEMP%\codex-jobs` (no param default). Request metadata
contains no prompt on sync. Timeout without lastmsg throws (`exceeded` +
`was terminated` literal fragments); timeout with lastmsg recovers success and
emits `MIMIR_CODEX_RECOVERED_AFTER_TIMEOUT=1` on stderr unless test hook
`MIMIR_TEST_CODEX_FORCE_TIMEOUT=1` forces the timeout throw. Non-zero exit
with nonblank lastmsg returns the verdict; otherwise errors are extracted from
JSON/`ERROR:` prefixes and rate/auth/service sentinels.

Sentinels `MIMIR_CODEX_LASTMSG=` and `MIMIR_CODEX_REQUEST=` are written on stderr in
`finally`; success stdout is only the verdict. In `kb-sensitive`, successful
lastmsg/stream artifacts are deleted; failure may include lastmsg evidence in
the throw.

<!-- backend-parity: ignore --> `Invoke-OpenCode.ps1` and `Invoke-Codex.ps1`
share the model-default contract: omitted `-Model` leaves the tool/config default
in place. `gpt-5.5` is an example/suggested Codex reviewer, not adapter-pinned.

<!-- backend-parity: ignore --> Durable Codex capture in the panel uses a
per-reviewer `%TEMP%\mimir-panel-codex\<RoundId>\<NN>` directory. Panel default
`TimeoutSec=1200` is injected for all sync adapters when omitted; invalid
`invokeArgs.timeoutSec` errors only that reviewer. `recoveredAfterTimeout` is
projected when lastmsg matches `request.json`; in `kb-sensitive`, success deletes
artifacts so the field stays `null` (unknown), never `false`. Fallback dispatcher
timeout has 120s overhead and opencode ×2 attempts; `ContentionKeys['codex']` is
empty.

### Claude Code

<!-- backend-parity: ignore -->
`Invoke-ClaudeCode` is stdin-based; defaults are restricted short-query posture:
`PermissionMode=plan`, `Tools=Read,Glob,Grep`, no session persistence. `-Tools ""`
disables all tools; `-Tools default` releases the CLI default set. Default
`-TimeoutSec 1200`, range `1..3600`. There is no `-MaxTurns`: the adapter does
not pass `--max-turns`.

`Invoke-ClaudeCodeAsync` is the panel path only: `stream-json`, atomic sidecar
`claude-code-async-sidecar` schema 1, stdout only after accepted final text.
Param default `-TimeoutSec 300`; dispatcher injects 1200 when omitted. The panel
validates sidecar states: `completed+true→responded`, `completed+false→error`,
`timeout→timeout`, `quota→quota`, `unavailable→unavailable`, `internalError→error`,
unexpected `cancelled→error`. In `kb-sensitive`, partial raw text is not
persisted; only accepted `.verdict.txt` raw text remains.

`Invoke-ClaudeCodeAsync` reads both `type=error` and final `type=result` with
`is_error=true` from the stream. The adapters report turn exhaustion as
`max-turns-exhausted` and an untrusted-workspace refusal as
`workspace-not-trusted`/`unavailable`. Partial text followed by a failure goes to
`failureAfterText`; orchestrator decides whether to use or
reclassify it. Noise warnings about ignored permission allow/deny entries are
discarded before classification. Usage-limit evidence remains raw in technical
fields; the human receipt must say only: `Claude Code returned a usage limit;
type/period not determined`. Do not infer monthly/weekly/5-hour windows or other
billing periods from CLI text.

Official Claude Code exit-code sources do not publish a general table. Treat
`0` as documented success where documented, `1` as generic failure without
classifiable evidence, `2` as hook-block only, and `137` as killed/terminated
possibly OOM. Do not infer quota/auth/workspace/model from a number alone.

`Invoke-ClaudeCode.ps1` and `Invoke-ClaudeCodeAsync.ps1`
refuse `PermissionMode=bypassPermissions` outright; that mode is not part of Mimir
delegation.

### Copilot CLI

<!-- backend-parity: ignore -->
`Invoke-Copilot` is sync only, argument-based, external
`github-copilot/<model>`. It uses `--no-custom-instructions`,
`--disable-builtin-mcps`, `--available-tools=`, JSONL, and `--allow-all-tools`
(required for non-interactive auto-approval even though no tools are exposed).
Default model is `auto`; concrete ids can retire (e.g. `gpt-5-mini` on CLI
1.0.78), so caller-supplied ids must be known-good. `-MessagePath` removes
caller-side command substitution but the prompt still goes through argv; the
30000-char fail-closed guard remains.

### Gemini CLI

<!-- backend-parity: ignore -->
`Invoke-Gemini` is sync only, argument-based, external `google/<model>`. It uses
`--approval-mode plan` and `--output-format json`; modes other than `plan` are
blocked. `-MessagePath` does not raise the argv cap; 30000-char guard applies.

### Antigravity CLI

<!-- backend-parity: ignore -->
`Invoke-Antigravity` is sync only, external `antigravity/<model>`, fixed to
`Profile=public-review`, `Mode=plan`, semantic-only/public-only. It creates a
short empty scratch cwd, refuses `.git`, reparse points, repo roots, KB-workspace
roots or ancestors, and does not accept operational `-Cd`. It redirects user/home
and XDG variables only in the child process; this is state hygiene, not a
sandbox, and does not isolate keyrings, absolute paths, MCP, browser, or network.
`ScratchPath` and `SimulateCleanupFailure` are self-test-only and blocked by the
dispatcher. It requires the JSON envelope's `.response`; non-JSON stdout with
exit 0 is `invalidOutput`, interactive auth is `unauthenticated`, typed quota is
`quota`, timeout kills descendants and may promote quota/auth residuals. Receipt
schema `antigravity-public-review-receipt` v1 records CLI version, posture,
scratch, and cleanup `clean|degraded|failed`. Baseline version changes require a
new probe/smoke test before promoted evidence.

Observed `agy.exe` success envelope, 2026-08-04:

```json
{"conversation_id":"…","status":"SUCCESS","response":"OK\n","duration_seconds":42.6,"num_turns":1,"usage":{"input_tokens":17125,"output_tokens":43,"thinking_tokens":39,"cache_read_tokens":0,"total_tokens":17168}}
```

`AntigravityCliSupport.ps1` has a support quota pattern deliberately different
from the dispatcher; there is no regex parity. `auth` wins over quota. Prompt
echoes containing quota/auth terms can cause false classifications; the panel
projects them as technical states, not reviewer verdicts.

<!-- backend-parity: ignore --> External OAuth backends can exceed 180 seconds;
adjust `-TimeoutSec`. Antigravity is slow and expensive even on a trivial prompt
(42.6s and 17,125 input tokens measured), so review timeout/cost before panels.

### Backend-agnostic concurrency and agentic limits

<!-- backend-parity: ignore -->
- Multiple `ollama-cloud/*` reviewers: cap at 3 simultaneous calls and queue the
  rest. A concurrent no-text failure gets a `concurrencySaturationWarning`; no
  automatic redispatch outside `fallbackChain` without explicit human decision.
- opencode, Codex, Claude Code, Copilot, Gemini, and Antigravity are agentic,
  not pure one-shot backends. They may load instructions/context and can read or
  act according to their tool model. The confidentiality gate still applies even
  when an adapter uses a read-only sandbox or semantic-only posture.
- Future one-shot backends (`llm`/`mods`/equivalent) remain reserved for cases
  that require sending only the prompt with no agentic layer.

## 8. Panel dispatch harness

`Invoke-LlmDelegatePanelDispatch.ps1` is a mechanical dispatch+collect harness;
the orchestrator remains responsible for native subagent injection, floor,
closeout, first-gap triage, convergence, authorizing `ask`s, human receipt,
ledger interpretation, and `responded→noResponse` reclassification.

Harness responsibilities:

- Validate `RoundId` fail-closed before dispatch: only letters, digits, dot,
  hyphen, underscore; reject `..`, `/`, and `\` because the value enters paths
  under the ledger and `%TEMP%\mimir-panel-codex\<RoundId>\<NN>`.
- If receiving `-ManuscriptText`, prepare artifacts first via
  `New-LlmDelegatePeerReviewArtifacts.ps1`. Preparation failure emits
  `mimir-panel-dispatch-result`, `SchemaVersion=3`, `success=false`,
  `roundStarted=false`, `dispatchStarted=false`, zero reviewers.
- Validate `invokeArgs.backend`. Exception: `opencode` with
  `PayloadSensitivity=kb-sensitive` is terminal `state=unavailable` before the
  authorization gate or dispatch, regardless of destination. For remaining
  primary reviewers, run the gate and dispatch only `allow`s in parallel
  (`ForEach-Object -Parallel -ThrottleLimit 8`, plus a SemaphoreSlim for
  `ollama-cloud/*`); record `attemptRole=primary`, `rank`, `fallbackChain`,
  `countsForDiversity=true`.
- Emit exactly one stdout line: `panel-summary.json` / `Kind=mimir-panel-dispatch-result`
  / `SchemaVersion=3`. Human-readable text goes to stderr; callers must keep
  stdout and stderr separate or JSON is corrupted.
- Emit `manifest.json` schema v1 and per-state ledger under `<TempDir>/<RoundId>`.

Effective model rules: opencode = `invokeArgs.model` or input `targetModelKey`;
Codex = `invokeArgs.model` or gate without `-Model` then last segment of returned
`targetModelKey`; Claude Code/Copilot/Gemini/Antigravity require
`invokeArgs.model` or fail closed. Null `targetModelKey` where required errors.
Antigravity is pinned to `public-review`; `kb-sensitive allow` becomes
`unavailable` + `refusedSensitivity` before adapter.

`responded` is mechanical non-empty text, not a valid verdict. The orchestrator
must reclassify off-task, empty, or threadbare returns as `noResponse` before
floor/closeout. The criterion is substance against the manuscript, not char
count.

Containment keys are refused and not passed through: Claude Code
`{permissionMode,tools}`, opencode `{agent}`, Gemini `{approvalMode != plan}`,
Antigravity
`{mode,agent,approvalMode,profile,cd,scratchPath,simulateCleanupFailure,receiptPath,antigravityExe,message,messagePath}`;
panel Claude Code internal async keys are also blocked. `approvalMode=plan` for
Gemini is silently dropped. Codex/Copilot have no containment parameter. The
panel blocks opencode `{agent}`, so opencode reviewers run with no explicit
`-Agent` and whatever opencode config resolves.

Native leak defense: every record carries `ledgerIndex`, `entryIndex`,
`suppressedFallbackChain`, and `dispatchChannel`. If `backend=orchestrator-native`
leaks into `ReviewersJson`, it becomes `state=error`,
`reason=orchestrator-native-leaked-to-dispatch`, and any chain is suppressed with
`fallbackSuppressedReason=primary-native-leaked`.

Fallback v2: activate `fallbackChain` in order for dispatcher technical states
`quota`, `timeout`, `error`, `unavailable`. Primary-reviewer success →
`skippedAfterSuccess`; `gateAsk`, `gateDeny`, and pre-dispatch validation blocks
→ `skippedByPolicy`. Claude Code durable quota pre-spawn/prompt blocks suppress
automatic fallback as `fallbackSuppressedReason=pre-dispatch-block-not-fallback-safe`.
Responded fallbacks can count after usable-verdict review; skips and
`notAttempted` must have `countsForDiversity=false`. `noResponse` is
orchestrator-only.

Quota pattern: `402`, `429`, `Payment Required`, `insufficient coding plan
balance`, `quota`, `rate limit`, `resource_exhausted`, `credits`/`balance`/`saldo`
+ `exhausted`, `too many requests`, `weekly usage limit`, `limite de uso`,
`sem quota`, `saldo insuficiente` become `quota`; `exhausted` alone does not.
Human receipt for `quota`: say "returned/hit a usage limit" and preserve raw
evidence; do not infer period/type unless proven.

States/reasons that must remain meaningful in receipts/ledgers include:
`responded`, `noResponse`, `timeout`, `quota`, `error`, `unavailable`, `gateAsk`,
`gateDeny`, `skippedAfterSuccess`, `skippedByPolicy`, `notAttempted`,
`skippedByHumanDecision`, `stoppedOnGap`, `securityBlockedArgs`,
`refusedSensitivity`, `cliMissing`, `inputTooLarge`, `unsafeWorkspace`,
`unauthenticated`, `invalidOutput`, `processFailure`, `cleanupIncomplete`,
`workspace-not-trusted`, `max-turns-exhausted`, `state-json-invalid`,
`pre-dispatch-block-not-fallback-safe`, `insufficientDiversity`, and
`insufficientDiversityAfterFallback`.

## 9. Canonical adapter invocation form

The harness allowlist matches atomic commands. Always pass the prompt through
`-MessagePath <file>`; never embed the prompt inline.

The command is always `pwsh -NoProfile -File <script> [parameters]`, which runs
the same from bash, PowerShell, and cmd (see the `mimir-lite` skill's
"Running scripts" section for why).

- Working directory is the repository root, relative path:
  `pwsh -NoProfile -File skills/mimir-delegate/scripts/<Adapter>.ps1 -MessagePath <file> [other adapter parameters]`
  — matches the Claude Code rule `Bash(pwsh -NoProfile -File skills/mimir-delegate/scripts/*)`.
- Any other working directory (for example a KB workspace), absolute path with
  forward slashes, in double quotes:
  `pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-delegate/scripts/<Adapter>.ps1" -MessagePath <file> [other adapter parameters]`
  — matches `Bash(pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-delegate/scripts/*)`,
  where `<mimir-lite-root>` is the absolute path of the repository clone.
- Claude Code's PowerShell tool, when enabled, runs the same command text; its
  rule uses the `PowerShell(...)` prefix with the same text.

Do not use PowerShell-only syntax (`& "<path>"`): it fails in bash and cmd, and
a rule written for one spelling does not match the other. Keep
`-MessagePath` under a temp path with no spaces when possible. `-Cd` exists only
for Codex, Claude Code, Copilot, and Gemini; opencode has no `-Cd`, and
Antigravity has no `-Cd` (its `public-review` profile creates its own scratch cwd).

An inline-prompt PowerShell call with embedded quotes and `-Cd "<path>"` can
prompt despite allowlist entries; the atomic `-MessagePath` form avoids that
class of mismatch. The allowlist examples are informative, not a versioned
setup contract.

## 10. Prompt construction for reviewers

A reviewer prompt must not package the conclusion as fact. Separate evidence
from hypotheses; avoid unproven wording such as "universal identifier" or "the
KB's standard." Use auditable phrasing like "the observed XML has
`AUTONUMBER=True`" or "the plan's hypothesis is...".

Shield the role: tell agentic recipients that they are reviewers who must issue
their own verdict (`agree`/`revise`/`reject`, with justification and prioritized
gaps). They must not execute the plan, assemble a panel, delegate, or assume the
orchestrator role. If a response takes over instead of opining, record
`noResponse`.

## 11. Known platform limits

### Headless stdin anti-hang

Agentic CLIs can hang in headless shells when inheriting an open stdin pipe. All
adapters give EOF in one of two regimes:

- <!-- backend-parity: ignore --> stdin-based (`Invoke-OpenCode`, `Invoke-Codex`,
  `Invoke-ClaudeCode`, `Invoke-ClaudeCodeAsync`): prompt via
  `Start-Process -RedirectStandardInput <file>`; EOF comes from file end; prompt
  stays outside argv. On Linux and macOS, PowerShell copies the file line by
  line, so the CLI receives one extra trailing newline; harmless for LLM CLIs.
  opencode's no-positional `run` reads stdin as verified on the 2026-06 version.
- <!-- backend-parity: ignore --> argument-based (`Invoke-Gemini`,
  `Invoke-Copilot`, `Invoke-Antigravity`): prompt is an argument; runner closes
  stdin with `$null | &`, not `'' |`; using `pwsh -Command` would reintroduce the
  hang.

If argument-based CLIs gain stdin mode, the closed-stdin design must be reviewed.
Flag-contract self-tests guard this. `--version`/`--help` probes do not hang.

### Command-line limit and `StandardOutputEncoding`

Argument-based adapters still pass prompt text through argv internally.
`-MessagePath` removes caller-side command substitution but does **not** raise the
Windows ~32767-character command-line limit; all three argument-based adapters
fail closed at 30000 UTF-16 code units. Stdin-based adapters avoid this limit.
An observed but unconfirmed `StandardOutputEncoding is only supported when
standard output is redirected` symptom is worked around by using the Bash tool or
a shell with piped stdout for argument-based adapters, keeping prompts lean.
opencode is host-agnostic to this symptom because it uses explicit redirection.

### Truncation and substance

<!-- backend-parity: ignore -->
opencode detects completion via the last `step_finish.reason`; only `stop` is
success. Other values (`length`, `tool-calls`, `content_filter`, `unknown`,
`max_tokens`) or missing finish become `truncated`/`no-completion`; stream errors
win. If future opencode renames `stop`, legitimate calls may all become
`truncated`; revisit `Get-OpenCodeCompletionVerdict`.

Non-opencode adapters deliver final text through terminal fields/mechanisms:
Codex `output-last-message`, Claude Code final stdout or async terminal result,
Gemini `$json.response`, Antigravity `$json.response` from a `SUCCESS` envelope,
Copilot last-wins `assistant.message` + `result.exitCode`. They do not expose an
opencode-like `reason=length`, so token-limit truncation outside opencode remains
undetected. Copilot last-wins and cross-adapter empirical truncation parity remain
future work.

`ok` / mechanical `responded` does not guarantee a useful verdict. Threadbare
answers must be reclassified by the orchestrator based on substance.

### Provider quota/usage limits

<!-- backend-parity: ignore -->
opencode 429/quota may look like timeout because stdout/stderr can stay empty
while evidence appears only in `~/.local/share/opencode/log` (honors
`XDG_DATA_HOME`). `Resolve-OpenCodeProviderLimitHit` classifies usage/rate limits
from stream, stderr, and log in the T0 UTC window on terminal paths; an `ok`
response is not overridden by leftover logs. Redispatching or raising timeout
does not fix usage/quota; rate limits
are short-lived but should not be retried immediately. Claude Code, Codex, and
Antigravity have their own typed or textual limit handling; Gemini and Copilot
remain future parity work.

### Worktree cwd and opencode on Windows

On Windows, `opencode run` can fail in a Git worktree cwd (`.git` is a gitlink)
with empty stdout or `uv_spawn ENAMETOOLONG`; measured on opencode 1.4.4.
`opencode models` still works. Because opencode lacks `-Cd`, reviewing from a
Claude Code worktree can fail silently. Workaround: materialize a flat directory
outside the worktree and run opencode from there; the dossier can still go via
stdin.

```text
git -C <worktree> archive --format=tar HEAD | tar -xf - -C "C:/Users/<user>/AppData/Local/Temp/xr"
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-delegate/scripts/Invoke-OpenCode.ps1" -MessagePath "<dossier>.txt" -Model opencode-go/glm-5.2 -TimeoutSec 600
```

Run the second command in the canonical form of section 9, with the flat
directory as its working directory (opencode has no `-Cd`, so the adapter runs
opencode from the current directory). Set that working directory through the
agent tool, never with a `cd ... &&` prefix, so the allow rule still matches.

## 12. Usage contexts and relation to other skills

| Context | Typical data | Delegation rule |
|---|---|---|
| Mimir Lite development root | public repo diffs, sanitized templates, docs | external diversity is allowed and often useful |
| KB workspace | real KB XML/content | external requires gate authorization; prefer local; agentic backends have no native read protection |

Pre-push review (`13-pre-push-review.md`) applies to the development root, not
KB workspaces.

The `mimir-lite` **setup** workflow offers to create/update the per-KB delegation
policy (`llm-delegation-policy.json`). The
`mimir-lite` **install** workflow registers this skill in agent tools.

PATH RESOLUTION: this file lives in `skills/mimir-delegate/`; scripts are in
`skills/mimir-delegate/scripts/`; resolve repository-anchored paths from the repo
root.
