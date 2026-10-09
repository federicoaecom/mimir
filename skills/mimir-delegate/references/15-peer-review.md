# 15 — Peer review (plan/design validation by multi-model panel)

> **Maintainer workflow.** This document describes the maintainers' review workflow for this repository. It is optional for contributors: the only checks a contribution must pass are the mechanical checks that CI runs, listed in [`CONTRIBUTING.md`](../../../CONTRIBUTING.md).

## Role of this document

This is the generic peer-review methodology for this repository. An author submits a reading of a problem and a proposed solution to a panel of independent reviewers from distinct model creators. Each reviewer thinks independently, checks the cited sources for itself, and returns a verdict. The author then revises and resubmits until the panel reaches the closeout state defined here.

Three documents, three layers:

- [`13-pre-push-review.md`](../../../docs/process/13-pre-push-review.md) — the pre-push routine each reviewer runs before a push.
- [`14-reinforced-pre-push-review.md`](../../../docs/process/14-reinforced-pre-push-review.md) — the reinforced pre-push application of this methodology; the panel reviews the routine from `13` and inherits this convergence rule.
- this `15` — the general methodology for validating a plan or design before or during implementation, not only before push.

The delegation mechanism — reviewer backends, prompt transport, panel dispatch, ledgers, and closeout scripts — belongs to [`mimir-delegate`](../SKILL.md). This document owns the methodology and convergence rule.

Peer review is always human-triggered. The agent may suggest a panel, but it must not assemble or dispatch one without the user's request or explicit agreement. This task of translating the document is not itself a peer review.

## What peer review is

The author, usually the primary agent, prepares a short manuscript containing:

1. the problem reading;
2. the proposed solution;
3. the sources that support or contradict the proposal;
4. open decisions.

The manuscript is submitted to a peer panel. Each peer reviewer:

- thinks independently and returns its own verdict (`agree`, `revise`, or `reject`) with justification and prioritized recommendations;
- checks the cited sources directly — the repository, and when authorized a KB workspace or experiment under the narrowest supported `-Cd`/cwd — to confirm, refine, or refute the author's claims; the manuscript is review input, not truth;
- lets the author carry the improved version forward: v1 → v2 → ... until final closeout.

## Generic rule

- **Independence.** Every reviewer receives the same manuscript and a minimal prompt, without enrichment that leaks what the author already knows or did. Do not assign per-reviewer personas or lenses; persona research remains future work. A capability split is not a persona: if one reviewer cannot run shell commands, it may receive an equivalent fact dossier instead of raw commands. The reviewed content and task remain the same; only the delivery of facts changes. The pre-push application of that split is in [`14`](../../../docs/process/14-reinforced-pre-push-review.md) / [`13`](../../../docs/process/13-pre-push-review.md) under dossier-assisted mode.
- **Model diversity.** Prefer reviewers from model creators distinct from the author and from each other. Native subagents and secondary LLMs through [`mimir-delegate`](../SKILL.md) can both participate. The minimum floor for peer review is at least two distinct model creators among effectively consulted reviewers. Below that floor there is no peer-review panel; see [Panel composition](#panel-composition). The floor applies to the entire composition, regardless of whether reviewers are native subagents, delegated LLMs, or both.
- **Stop on the first reported gap.** Any reviewer-reported gap halts the round's decision immediately, pending human triage; it need not first be accepted as a real gap. Human triage decides whether the finding is a real gap, a local convention, or a false positive. If a real gap warrants correction, the author updates the manuscript and creates a new version. This governs convergence, not transport. Already-dispatched parallel calls may still return, but no convergence decision resumes before triage; see [Panel composition](#panel-composition).
- **A panel is stale after every new version.** Each new version invalidates previous verdicts because reviewers reviewed a different artifact. A “no gaps” result only applies to the exact reviewed version.
- **Self-inflicted regression.** “Stale after every version” requires re-review, but does not guarantee that external reviewers will notice that vN+1 subtly changed an already-approved decision. In long-context sessions, the author must diff vN+1 against vN for closed decisions and the specification, not for full prose, before resubmission. The “auditable relay” item in the maintainers' ideas backlog (not published) specifies, but does not yet mechanize, a `newClaim` / `reordered` / `resolvedConflict` checklist in the same direction.
- **Return to the dissenter.** After a correction, resubmit to the reviewer that objected and confirm the fix closes the objection in that reviewer's terms. Do not declare success just because more lenient reviewers passed.
- **The cycle does not stop halfway.** Once started, peer review is a loop: gap → human triage → new version → reassemble the panel on the new version → repeat until closeout.
- **Convergence is the ready state.** A plan is converged only when the full valid diverse panel reports zero gaps on the final version. Partial passes do not count, including a pass from only the dissenter or from reviewers who approved an older version. A one-family panel converges trivially and is not peer review. If the author creates vN+1 from the reviews, that version has not yet been reviewed. Delivering it as “done” without resubmission is false convergence; label it “vN+1 proposed, pending resubmission.” At minimum, return to every dissenter, but final convergence requires the whole panel on the final version.
- **“Agree with reservations” is not convergence.** A verdict such as “agree with reservations” or “approved with suggestions” declares gaps. The orchestrator reports the gap and does not close the round, auto-triage it, or declare convergence on its own.
- **vN+1 state is mechanical at authorship time.** When the agent authors vN+1, it records `-VNextState pendingResubmission` in [`Resolve-LlmDelegatePeerReviewCloseout.ps1`](../scripts/Resolve-LlmDelegatePeerReviewCloseout.ps1). Closeout blocks (`closeoutReady=false`) until vN+1 is `resubmitted` or the human records an audited decline of resubmission with `resubmissionDeclinedByHuman`, who decided, why, and the `RoundId`. The closeout script is stateless: the state arrives by parameter and is re-evaluated on each call. The append-only trail per `RoundId` and monotonicity across calls belong to the orchestrator plus receipt/ledger, not the script. The only valid transition from `pendingResubmission` to a terminal state is a new closeout invocation with the terminal `-VNextState`; changing the receipt any other way bypasses the gate. Honest limit: this axis prevents silent skipping, but it cannot prove fabrication because the script does not read the conversation.
- **Execution remains a human decision.** Convergence makes the plan releasable for execution, but the human decides whether to execute. In the pre-push case in `14`, the equivalent is “push-ready”; push still requires explicit authorization.

## When the design stabilizes: freeze paper and move proof to code

The rule above says when the panel agrees; it does not say when to stop iterating on paper. If rounds stop reopening architecture and the remaining objections concern implementation precision — specification, telemetry, self-tests — rather than design gaps, the agent may propose that the human freeze the design, end the paper cycle, and move proof to implementation. This is a human decision. The rule is a decision trigger, not permission for the agent to end the debate alone.

- **Freeze is not convergence.** Freezing is the audited human decision to stop the paper design cycle and transfer proof to implementation/self-test. It is not convergence and not weak convergence. Use “the design is stable” or “architecture is no longer being reopened,” never “converged.”
- **How the agent proposes it.** List each remaining objection and classify it as either “does not reopen architecture” or “still discusses design,” with justification. The human accepts, rejects, or asks for another round.
- **The rule stays active until the human freezes.** Until the human decides, stale-after-version, return-to-dissenter, and full-panel-on-final-version all remain mandatory.
- **Auditable record.** Record the decision in [`Resolve-LlmDelegatePeerReviewCloseout.ps1`](../scripts/Resolve-LlmDelegatePeerReviewCloseout.ps1) as `resubmissionDeclinedByHuman` with the decision maker, reason such as “proof transferred to implementation/self-test,” and `RoundId`; do not mark it `resubmitted`. “Decline paper resubmission” covers two subcases: proof transferred to implementation/self-test, and abandonment without substitute proof. The reason distinguishes them.
- **Caveat.** If the dissenter still identifies a real design defect, paper stays open. Only implementation precision migrates. The design-vs-precision boundary is human triage.
- **Orthogonal to panel composition.** Freezing controls how many versions to iterate over time. It does not authorize reducing the panel, stopping at the family floor, or skipping the preferred-reviewer list; composition is governed by [Panel composition](#panel-composition) and the scope items in the maintainers' ideas backlog (not published).

## Roles: assembly and opinion by the agent, decisions by the human

- **Panel assembly.** The agent may, as the human's hands and only after human trigger, dispatch diverse reviewers through [`mimir-delegate`](../SKILL.md) and native subagents, send each the manuscript plus the minimal prompt, and collect verdicts. Before using the peer-review label, the agent validates the diversity floor over the complete reviewer list. Native subagents enter with the model creator of their `targetModelKey`; they do not inherit the orchestrating tool as creator. The mechanical dispatch/collect path for delegated reviewers may use `Invoke-LlmDelegatePanelDispatch.ps1`, but the harness is strictly mechanical: native injection, diversity floor, closeout, triage, and convergence remain with the orchestrator/human.
- **Decision nodes.** The human decides whether a finding is a real gap, declares convergence, and authorizes execution. The agent is expected to give its opinion and recommendation on each point before the human decides. The agent must not decide and act alone: no auto-triage followed by edits, no unilateral convergence, no execution.
- **Reviewer role.** A reviewer, human or agent, evaluates the manuscript against the sources.

Guardrail: an agent must not (1) decide and act in the human's place, or (2) pretend a single opinion is peer review. Triage, convergence, and execution are human decision nodes.

### Mandatory receipt

Before using the `peer review` label, the orchestrator reports:

- methodology files read;
- manuscript/prompt sent;
- reviewers effectively consulted;
- model creator/family for each reviewer;
- diversity-floor result;
- verdict/state for each reviewer;
- `vNextState`;
- when `mimir-delegate` was used, the `receiptAddendum` from `Resolve-LlmDelegatePeerReviewCloseout.ps1`.

If a preferred-reviewer list existed, the receipt also lists every primary reviewer and applicable fallback with an auditable final state: responded with verdict, consulted without usable verdict (`noResponse`), timeout, quota, error, gate ask/deny, unavailable, skipped after primary-reviewer success, skipped by policy, not attempted, excluded by human decision, or stopped on first gap. Skipped states carry `countsForDiversity=false`.

If the receipt is absent, incomplete, incompatible with at least two effectively consulted creators, marked `insufficientDiversityAfterFallback`, or accompanied by `closeoutReady=false`, label the result honestly as `solo opinion`, `second opinion (N)`, or an unfinished round. An off-task response, or an on-task but substantively empty response that does not take a position on the manuscript, is `noResponse` and does not count toward the floor. The criterion is substance against the manuscript, not character count; a short auditable verdict can still be usable.

### Minimum time as negative evidence

A near-immediate answer is incompatible with this methodology. Reading the documentation, assembling a panel, consulting at least two creators, and collecting verdicts takes material time. Operationally, an answer produced in under 30 seconds from the request must not be labeled `peer review`, unless the agent is only reporting a previously completed and identifiable panel with receipt/ledger. The threshold does not prove that longer answers are valid; it only invalidates the label when the real flow would be physically impossible.

## Panel composition

Principle: use independent reviewers from model creators distinct from the author. Strong instruction-following models are preferred in the core. Weaker models can be additional voices, never the single decisive reviewer; every objection still goes through human triage. Mistral Large 3 and Nemotron 3 Ultra are hard-vetoed because of observed weak grounding.

Discover models and backends through [`mimir-delegate`](../SKILL.md), not by re-probing every use. If a preferred-reviewer list exists (`preferred-reviewers.<orchestrator>.json` → machine `preferred-reviewers.json`, schema 3), it supplies the preferred composition/candidates. It is not an optional pool from which the agent may silently choose the minimum, and it is not delivery authorization. Primary reviewers have positive unique `rank`; CLI primary reviewers may have ordered `fallbackChain[]`; native reviewers cannot have fallback chains. A fallback activates only when the primary reviewer fails or becomes unavailable, must have an auditable skipped or activated state, never replaces the destination gate, and never reduces the diversity floor. The only persisted fallback policy supported by the dispatcher is `ordered-chain`, activated on `quota`, `timeout`, `error`, or `unavailable`; unsupported variants block before dispatch. `noResponse` is the orchestrator's post-hoc reclassification for no usable verdict, not a primary mechanical trigger.

On first use without a list, the agent asks which tools/models the user has and prefers, in recognizable terms (`Claude Code`, `opencode/Ollama Cloud`, `Codex`, `Copilot`, `Gemini`, `Antigravity`, or the current tool's native subagent), and offers to calibrate/save the list only after the user chooses. Preferences are subordinate to this role policy and to the gate.

### Mechanical diversity floor

A peer review requires at least two distinct model creators. In the code, `family` from `Get-LlmDelegateTargetFamily` means model creator, not the model line/series. For most direct `provider/model` keys, the creator is the prefix before `/`: `google/gemini-*` → `google`, `anthropic/claude-*` → `anthropic`, `openai/gpt-*` → `openai`, `github-copilot/*` → `github-copilot`.

Aggregator rules from `LlmDelegateTargetFamilySupport.ps1`:

- `nvidia/<creator>/<model>` extracts the second segment and normalizes known creators: `deepseek-ai` → `deepseek`, `mistralai` → `mistral`, `qwen` → `alibaba`, `meta-llama`/`facebook` → `meta`, `thudm`/`glm` → `z-ai`, `minimax`/`minimaxai` → `minimaxai`, `moonshotai` → `moonshot`, `nvidia` → `nvidia`; unknown sub-orgs use the second segment as-is. Two-level `nvidia` keys resolve `nemotron-*` → `nvidia`, `llama-*` → `meta`, otherwise `nvidia`.
- `antigravity/*` resolves `antigravity/gemini-*` or unknown/default → `google`, `antigravity/claude-*` → `anthropic`, and `antigravity/gpt-*` → `openai`.
- Cursor native harness slugs resolve by model creator: `cursor-grok-*` / `cursor/grok-*` → `xai`; `cursor-composer-*` / `cursor/composer-*` → `anysphere`. Do not count them as `cursor`; the axis is who trained the weights.
- Two-level aggregators with no creator in the path, such as `ollama-cloud/*`, `opencode-go/*`, and `atlas-cloud/*`, are counted by destination-provider prefix as a documented undercount that preserves endpoint governance and dispatcher concurrency semantics.

| Term | Meaning | Governed by | Examples |
|---|---|---|---|
| Backend / Harness | Local tool or CLI that transports the prompt. | Adapters and dispatcher. | `opencode`, `codex`, `claude-code`, `copilot`, `gemini`, `antigravity` |
| Destination provider | Cloud service/server that receives the network request. | Confidentiality gate and per-KB policy. | `openai`, `anthropic`, `nvidia`, `ollama-cloud`, `antigravity` |
| Model creator | Organization that trained the architecture/weights; the diversity axis. | `Get-LlmDelegateTargetFamily`. | `openai`, `anthropic`, `google`, `deepseek`, `z-ai`, `moonshot`, `alibaba`, `meta`, `minimaxai`, `mistral`, `microsoft`, `nvidia`, `xai`, `anysphere` |
| Model family | Model line inside a creator portfolio. | Creator catalog identifier. | Gemini vs Gemma; GPT vs o1; Mistral vs Codestral; Qwen vs Qwen-Coder |

Build the full candidate array for `Resolve-LlmDelegatePanelDiversity.ps1 -CandidatesJson <json>`. Before dispatch, include every primary reviewer in the resolved preferred-reviewer list and every native subagent the orchestrator will inject; never cherry-pick a floor-sized subset. Include each candidate's `targetModelKey`, `backend` when available, and that destination's `Resolve-LlmDelegateAuthorization.ps1` result in `verdict` (`allow`, `ask`, or `deny`). For example, `Resolve-LlmDelegatePanelDiversity.ps1 -CandidatesJson '[{"targetModelKey":"openai/gpt-5.5","backend":"codex","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","backend":"orchestrator-native","verdict":"ask"}]'` shows the item shape only: pass the complete reviewer list, not just these two entries. The resolver derives family from `targetModelKey`; it is consultative and emits `panelReady`, `needsBatchAuthorization`, `insufficientDiversity`, or `insufficientDiversityAfterFallback`. `panelReady` means at least two known creators are allowed. `needsBatchAuthorization` means the listed `ask` destinations would close the floor if authorized; present those asks together to the human, with destination and sensitivity. `insufficientDiversity` means even authorization cannot create the floor; do not call it peer review. After dispatch, evaluate the full attempt/state set, including applicable fallbacks; entries with `countsForDiversity=false` (`skippedAfterSuccess`, `skippedByPolicy`, `notAttempted`) do not count. If fallback does not recover at least two creators, `insufficientDiversityAfterFallback` blocks the label. A zero-preauthorized case is only a request to try assembling a panel. The diversity resolver does not decide authorization; `Resolve-LlmDelegateAuthorization.ps1` is sovereign per destination.

This applies to every panel assembly path. Before using the label, materialize the full reviewer list and assign a creator to every reviewer, including native subagents, then validate the floor over that full list. Only creators known to `Test-LlmDelegateFamilyKnown` count; unknown creators go to `droppedUnknownFamilies` until the allowlist is extended. A native-only panel with one creator is `second opinion`, not peer review.

Native reviewer curation is per orchestrator, never machine-wide. A primary reviewer `orchestrator-native-subagent` exists only inside the harness that runs it; persisting it in machine `preferred-reviewers.json` would make another harness resolve it as its own native reviewer. `Set-LlmDelegatePreferredReviewers.ps1` refuses `native-machine-scope-forbidden` and refuses native primary reviewers whose key identifies another harness (`native-harness-orchestrator-mismatch`). Older files remain readable, but `Resolve-` marks diagnostics for confirmation.

Before editing preferences, resolve first and read `preferenceSource`, `effectivePreferredPath`, and `cascadeOrchestratorExists`. A generic request in this session edits orchestrator scope when the orchestrator file exists or is effective; machine scope is only for explicit machine/all-harness requests. Writing machine preferences while an orchestrator file shadows them does not affect the current harness.

Known limit: harness-vs-orchestrator matching is enforceable only when the key itself carries the harness, currently `cursor/*` and `cursor-*`. A neutral native key such as `moonshot/kimi-k3-max` does not identify its harness; calibration remains responsible for that curation.

Orchestrator identifiers are an open list: any slug matching `^[a-z0-9][a-z0-9-]{0,39}$` (lowercased) names an orchestrator, with `cursor`, `claude-code`, `codex`, and `opencode` as the harnesses this repository can identify. Under an orchestrator it cannot identify, `Resolve-LlmDelegatePreferredReviewers.ps1` marks each native primary reviewer as unverifiable in `diagnostics`; the orchestrator must not count it toward the diversity floor (`countsForDiversity=false`) until it confirms the harness offers that model. A malformed slug is rejected (`orchestrator-invalid`).

Native subagents should be used when the current tool offers them. They add independent review with the declared `targetModelKey` creator, but cannot satisfy the diversity floor alone if they are the only creator.

### Dispatch: serial for pre-push, parallel for plan review

“Stop on the first reported gap” governs convergence, not dispatch. For plan/design validation, pause the decision as soon as any reviewer reports a gap and leave it pending human triage, even if parallel calls are already in flight. Those calls may return, but their results do not resume the decision or count as convergence while triage is pending. If triage leads to a changed manuscript, review the new version; final convergence still requires the whole panel plus return to dissenters on the final version. In pre-push (`14`), dispatch is serial for cost/control: the git-capable reviewer runs the full `13` routine, while the semantic-only reviewer uses a dossier.

## Confidentiality

Before sending anything, classify the manuscript as `public` (repository text, sanitized template, public diff) or `kb-sensitive` (real KB workspace content). For each reviewer, run `Resolve-LlmDelegateAuthorization.ps1`; sensitive content only goes to an external model with authorization. The gate deterministically re-evaluates destination and sensitivity and does not depend on capability inventory.

Agentic reviewers run with the narrowest necessary directory when the adapter supports `-Cd` (Codex, Claude Code, Copilot, Gemini). The generic direct `Invoke-OpenCode` adapter remains available for ordinary delegation and plan/design review, subject to the usual per-destination authorization and the operator's assessment of local configuration and cwd. opencode has no `-Cd`; without `-Agent`, it uses its configured default (typically `build`), which may be agentic, and explicitly selecting an agent through the direct adapter does not guarantee read-only/no-shell confinement. The panel dispatcher is a separate route: it rejects `invokeArgs.agent`, so an in-panel opencode reviewer receives no explicit agent and uses whatever the opencode configuration resolves; this route cannot guarantee read-only/no-shell behavior. For the reinforced pre-push panel only, [`14`](../../../docs/process/14-reinforced-pre-push-review.md) therefore requires the orchestrator to omit opencode manually until enforceable read-only/no-shell confinement exists. The dispatcher still lists opencode and does not enforce this omission. This is a human panel-assembly policy, not a general opencode ban or a ban on its direct adapter. Antigravity is deliberately fixed to `public-review`, semantic-only, and `public` payloads: if policy allows `kb-sensitive`, the adapter still converts it to `unavailable` with `refusedSensitivity` before invocation. Its scratch directory and environment redirection are state hygiene, not a sandbox; global keyrings remain shared and this limitation belongs in the receipt.

Plan/design validation in the development repository is typically `public`, which is the ideal case for model diversity. Safe cwd selection remains the operator's responsibility. If the cwd contains unversioned secrets, logs, caches, or `.env` files, an agentic reviewer may read them; test decoys do not replace checking the real directory.

## Receipt and ledger

The minimum receipt is mandatory before using the `peer review` label. It includes the fields listed in [Mandatory receipt](#mandatory-receipt), and always includes `vNextState` (`notProduced`, `pendingResubmission`, `resubmitted`, or `resubmissionDeclinedByHuman`) so the field is never silently absent. When `mimir-delegate` is used, include the mechanical closeout `receiptAddendum`. When preferred reviewers were resolved (`hasPreferences=true`), include every primary reviewer and fallback state with `attemptRole`, `fallbackOf`, and `countsForDiversity`.

If `Resolve-LlmDelegatePeerReviewCloseout.ps1` returns `closeoutReady=false`, including for `insufficient-diversity-after-fallback`, `vnext-pending-resubmission`, or `vnext-resubmission-decline-unaudited`, present its `requiredUserPrompt` and do not close the round as complete. `vNextState` prevents silence, not fabrication.

For high-risk or reinforced cycles, store an auditable ledger with manuscript versions, prompts, reviewer verdicts per version, and convergence summary under `<system temp>\mimir-panel-dispatch\<round-id>\`, the default ledger root of `Invoke-LlmDelegatePanelDispatch.ps1` (`-TempDir` overrides the root; `-RoundId` defaults to a GUID). The file ledger is optional for lightweight use, ephemeral, and lives outside the repository.

## Minimal prompt

For plan/design validation, the minimal prompt tells the reviewer to read the manuscript and cited sources, not treat the manuscript as truth, confirm or refute each claim against sources, and report gaps plus prioritized recommendations. It must not enrich the reviewer with the author's conclusion.

Shield the role for agentic backends: the recipient is a reviewer and must issue its own verdict (`agree`, `revise`, or `reject`). It must not execute the plan, conduct its own peer review, or delegate. A response that takes over the task instead of opining is not a verdict and counts as no usable response.

## Relationship with other documents

| Document | Role |
|---|---|
| [`13-pre-push-review.md`](../../../docs/process/13-pre-push-review.md) | The routine each reviewer runs before a push. |
| [`14-reinforced-pre-push-review.md`](../../../docs/process/14-reinforced-pre-push-review.md) | The reinforced pre-push application of peer review; a panel over the `13` routine. |
| this `15` | General plan/design peer-review methodology and normative convergence rule. |
| [`mimir-delegate/SKILL.md`](../SKILL.md) | Secondary-LLM delegation mechanism; panel review is a human-directed use case of it. |

Paper vs code: this `15` reviews design/plan while decisions are still malleable. `13` validates the code state that is about to be pushed, and `14` applies this peer-review methodology to that pre-push routine. Code freezes what paper leaves malleable; self-tests prove what paper can only debate.

## Future work

- One-shot backends (`llm`, `mods`, or equivalent) that send only the prompt without an agentic layer.
- Review personas or lenses, which remain in tension with the independent minimal-prompt rule.
- Automatic single-flight recovery outside `fallbackChain` for adapters other than the supported ordered-chain path; this still requires explicit human decision.
