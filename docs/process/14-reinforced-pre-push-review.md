# 14 — Reinforced pre-push review (multi-model panel)

> **Maintainer workflow.** This document describes the maintainers' review workflow for this repository. It is optional for contributors: the only checks a contribution must pass are the mechanical checks that CI runs, listed in [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

## Role of this document

This is the optional reinforced tier of the pre-push review. [`13-pre-push-review.md`](13-pre-push-review.md) defines the routine each reviewer runs: mechanical step plus semantic phase. This document applies the peer-review methodology in [`15-peer-review.md`](15-peer-review.md) to pre-push: it orchestrates a diverse reviewer panel over the `13` routine and applies the convergence rule that decides when a state is push-ready.

The delegation mechanism — reviewer backends, adapters, preferred-reviewer files, ledgers, and closeout scripts — belongs to [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md). This document owns only the pre-push panel policy. The generic methodology and convergence rule are normative in [`15`](15-peer-review.md).

Reinforced review is always human-triggered, like every delegation. The normal `13` routine is enough for ordinary work; this panel is an escalation when model diversity is desired. It governs the Mimir Lite repository pre-push routine.

## The convergence rule as applied to pre-push

In [`15`](15-peer-review.md), a manuscript version becomes converged only after the whole valid diverse panel reports no gaps on the final version. In pre-push, the reviewed “version” is a commit/HEAD state, and “ready” means **push-ready**, not permission to push.

- **Prompt by capability, not persona.** A `git-capable` reviewer receives the minimal prompt `execute a rotina pre push, sem push` and runs the full `13` routine. A `semantic-only` reviewer receives the dossier from `13` and performs only the semantic phase read-only. Do not assign per-reviewer personas or lenses.
- **Stop on first gap.** The first reviewer that reports a gap stops the round. The agent reports the verdict and its own recommended triage; the human decides whether the finding is real, local convention, or false positive. Only after the human explicitly authorizes both the correction and its commit may the agent apply the correction and commit it promptly. That authorization also lets the agent restart the full panel on the new HEAD without another initial trigger. The human may stop the loop at any point; no edit or commit is automatic.
- **Every new commit makes the panel stale.** Prior approvals apply only to the exact HEAD reviewed. After an explicitly authorized correction commit, restart the full panel over the new HEAD without requiring another initial “execute the reinforced review” trigger, unless the human stops the loop.
- **The cycle does not stop halfway.** Gap → human triage → explicit authorization of correction and commit → prompt correction commit → full panel on the new HEAD → repeat until closeout or the human stops. “No push” only forbids the final push; it does not stop the review loop.
- **Push-ready state.** After the last repository change, the whole valid panel must report no gaps on that final state. A partial pass, a pass from only the dissenter, or a pass from reviewers that reviewed an older commit does not count. Push itself still requires explicit human authorization under `13`.
- **Freeze design vs code proof.** The generic paper-freeze rule is in `15`. In pre-push, proof is already the code and the `13` routine; no agent may unilaterally declare convergence or push.

## Roles: panel assembly and opinion by the agent; decisions by the human

- **Panel assembly.** After the initial human trigger, the agent dispatches eligible diverse reviewers through [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md) and/or native reviewer mechanisms, using the prompt determined by reviewer capability. The agent manually omits opencode from the in-panel reviewer set under the policy below; the dispatcher does not enforce this omission. After an explicitly authorized correction commit, the agent restarts the full panel on the new HEAD without another initial trigger, unless the human stops the loop.
- **Agent opinion.** The agent must recommend triage for each finding: what appears to be a real gap, convention, or false positive, and why.
- **Human decision.** The human decides triage and convergence, explicitly authorizes both any correction and its commit, and authorizes push. Without that explicit correction-and-commit authorization, the agent does not edit or commit. It must not declare convergence alone, stage or commit unrelated changes, push, or pretend a single review is the reinforced panel.
- **Reviewer role.** A reviewer, human or agent, runs the applicable `13` routine for its capability.

## Panel composition

Use reviewers from distinct model creators where possible. The diversity axis is the creator of `targetModelKey`, not the local tool name. Native reviewers count by their declared `targetModelKey` creator and do not inherit the orchestrator’s tool family.

Strong instruction-following models are preferred in the core. Weaker models may be additional voices, never the single decisive reviewer. Mistral Large 3 and Nemotron 3 Ultra remain hard-vetoed because of observed weak grounding. Nemotron 3 Super is not hard-vetoed, but past reinforced pre-push use produced fabricated repository claims; verify every file/line citation before accepting any finding or justification from that line.

Discover available backends with the capability inventory in [`Build-LlmDelegateCapabilityManifest.ps1`](../../skills/mimir-delegate/scripts/Build-LlmDelegateCapabilityManifest.ps1) instead of re-probing every time. Update opencode discovery with `opencode models` when refreshing that inventory.

Current backend inventory from the dispatcher and gate:

- `opencode`
- `codex`
- `claude-code`
- `copilot`
- `gemini`
- `antigravity`

The backend set is owned by [`skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1`](../../skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1) and checked by [`tools/Test-PrePushBackendEnumerationParity.ps1`](../../tools/Test-PrePushBackendEnumerationParity.ps1). Do not treat this document as the adapter source of truth.

Recommended in-panel reviewer families are examples, not a fixed rule: Codex / OpenAI, Claude Code / Anthropic when the orchestrator is not Anthropic, and additional Copilot, Gemini, Antigravity `public-review`, or native reviewers when available. The principle and the diversity floor in `15` prevail over any example list. Although opencode remains an available backend and its direct adapter remains available, it is not an eligible or recommended in-panel route until an enforceable read-only, no-shell posture exists. Panel assembly must omit it manually; this is policy, not an automatic dispatcher restriction.

A valid reinforced pre-push panel must satisfy, in this order:

1. **At least one `git-capable` reviewer** that reproduces Section A of the dossier independently. Without one, Section A is not verified and the round cannot conclude.
2. **The diversity floor from `15`**: at least two effectively consulted model creators. Below this floor, label the result `solo opinion` or `second opinion (N)`, not peer review.
3. **Transport and omission rules**: omitted reviewers are recorded with auditable states and reasons, then the floor and `git-capable` invariant are re-evaluated.

The preferred `git-capable` anchor is an external Codex-delegate when available. Because quota can be limiting, the frequent fallback is a native subagent under the orchestrator harness. That is allowed but must be recorded as reduced assurance (`gitCapableAnchorFamily=orchestrator-native` in receipts). Accepting the asymmetry where `semantic-only` reviewers trust the orchestrator’s dossier is a human decision recorded as `asymmetryAcceptedBy`.

<!-- backend-parity: ignore -->
### Codex transport vs native anchor

Durable Codex adapter capture (`Invoke-Codex` / `codex-jobs` on disk) does not improve the reduced assurance of the native-anchor path. A native subagent does not pass through `Invoke-Codex` or Codex durable storage; it is an anchor by the orchestrator harness, not by the recoverable Codex adapter transport.

## Operational matrix — capability × transport

Capability and dossier transport are independent axes. A strong tool is not automatically `git-capable` inside this panel.

| Backend / route | Panel role | Outside the panel (adapter) | Dossier transport | Notes |
|---|---|---|---|---|
| Codex-delegate | `git-capable` | `git-capable` | N/A | Read-only sandbox in panel use. |
| Native subagent (`orchestrator-native`) | `git-capable` | N/A typical | N/A | Frequent anchor; not a dispatcher `$AdapterScript` key. |
| Claude Code (async / panel) | `semantic-only` | `git-capable` via synchronous `Invoke-ClaudeCode.ps1` with `-Tools default -PermissionMode dontAsk` | `stdin-dossier-capable` | Direct adapter use does not count as a `14` in-panel git-capable reviewer; in-panel git-capable profile remains future work. |
| opencode | Manually omitted from the in-panel reviewer set; do not dispatch or count it until an enforceable read-only, no-shell posture exists | Direct adapter remains available; without `-Agent` it uses opencode's configured default, which may be agentic. An explicitly named restricted agent is not automatically safe or an enforceable no-shell guarantee. | `stdin-dossier-capable` | The dispatcher still lists opencode and does not enforce the panel-assembly omission; it rejects `invokeArgs.agent`, so a selected in-panel opencode receives no explicit agent. See cwd/worktree and local-secret notes. |
| Copilot CLI | `semantic-only` | `semantic-only` | `argv-limited` (~30000 chars) | Omit if dossier exceeds the cap. |
| Gemini CLI | `semantic-only` | `semantic-only` (`ApprovalMode=plan`) | `argv-limited` (~30000 chars) | Omit if dossier exceeds the cap. |
| Antigravity `public-review` | `semantic-only` | always `semantic-only` | `argv-limited` (~30000 chars) | Never a `git-capable` anchor; creates its own scratch; refuses `-Cd`; accepts only `public` payloads. |

Maintenance rule: this table is a closed per-axis enumeration. The backend parity gate cannot infer a missing new row when every row cites only one backend. When a backend is added to the dispatcher, update this matrix in the same workstream.

## Omission and degraded labels

A `semantic-only` reviewer is omitted when `dossierReady=false`, the dossier exceeds an `argv-limited` transport cap, the working tree is dirty, or the Antigravity public profile refuses sensitivity. Record `unavailable` plus the applicable declared reason (`dossier-unavailable`, `dossier-too-large`, `working-tree-dirty`, `refusedSensitivity`, or the current dispatcher reason). The closeout does not use an `excluded` state.

For opencode, panel assembly must manually omit it from dispatcher `ReviewersJson`. If it was selected for the panel, closeout can represent that omission through `SelectedReviewersJson` and a matching `PreferredReviewerStatesJson` entry with `state=unavailable` and `countsForDiversity=false`. Record the human-readable omission explanation separately in the mandatory human-facing panel receipt; there is no existing per-reviewer `reason` field for a reviewer absent from the dispatcher input or in closeout. Do not invent a machine reason token or claim that closeout records the explanation. The dispatcher still contains and can dispatch opencode for `public` payloads; this documented policy is not automatically enforced there. Its existing `kb-sensitive` block does not enforce the broader in-panel omission.

After omissions, re-evaluate the `git-capable` invariant and diversity floor. With a dirty tree, all `semantic-only` reviewers are blocked; if Codex is unavailable and only the native anchor remains, the result is at most one family and must degrade to `solo opinion` or `second opinion (N)`.

For Antigravity, the confidentiality gate runs first. `ask` and `deny` retain their gate states. Only a gate `allow` for `kb-sensitive` is blocked by the fixed public-review posture as `unavailable` + `refusedSensitivity`. The adapter does not reclassify the payload.

## HEAD stability

Regenerate the dossier at every new HEAD. Immediately before each dispatch, compare live `git rev-parse HEAD` with the dossier HEAD and re-check the clean-tree precondition. A mismatch regenerates the dossier. The review assumes HEAD stays stable during each serial dispatch; the next dispatch detects any change.

## Dispatch order

When the user says “execute the reinforced pre-push review,” dispatch reviewers serially and pause on the first gap. This is a cost/control choice for pre-push: a `git-capable` reviewer runs the full `13` routine. `semantic-only` reviewers are cheaper because they read the dossier, but serial dispatch keeps the stop-on-first-gap workflow auditable. Future optimization may batch semantic-only reviewers; the convergence rule remains the one in `15`.

Keep the report concise: verdict, recommended triage, and the evidence needed for the human decision. Do not re-summarize the entire repository state after every reviewer.

## Operator notes

### opencode in a git worktree on Windows

`opencode run` can fail from a Git worktree cwd because of the gitlink `.git`. For direct adapter use, materialize the HEAD into a flat directory, for example with `git archive HEAD`, and run the adapter there. This workaround does not make opencode eligible for the reinforced in-panel route, which remains manually omitted. The dossier is delivered through stdin and does not depend on that cwd. Codex, Claude Code, Copilot, and Gemini support `-Cd`; Antigravity `public-review` refuses `-Cd` and uses its own scratch.

### opencode in a cwd with local secrets

opencode has no `-Cd`; it inherits cwd. `external_directory[*]=deny` does not protect `.env`, logs, caches, or other unversioned secrets inside that cwd, and a custom agent rule can accidentally allow broad reads. For direct adapter use, an operator may provision and explicitly pass an agent with `-Agent`, but neither that setting nor a safe cwd automatically guarantees an enforceable read-only, no-shell posture. The direct adapter remains available; assess its actual configuration and cwd, and do not dispatch from a directory containing secrets. For the reinforced panel, omit opencode regardless of cwd until the required posture is enforceable, and record the omission in the orchestrator receipt.

## Prohibition

An agent must not:

1. decide and act in the human’s place — no auto-triage into edits, no editing or committing without explicit human authorization for both the correction and its commit, no unilateral convergence or push, and no staging or committing unrelated changes; or
2. pretend a single reviewer is the reinforced panel.

The agent should assemble the panel and give its opinion. Decisions remain human nodes.

## Relationship with other documents

| Document | Role |
|---|---|
| [`15-peer-review.md`](15-peer-review.md) | Generic peer-review methodology and normative convergence rule. |
| [`13-pre-push-review.md`](13-pre-push-review.md) | The routine each reviewer runs. |
| [`mimir-delegate/SKILL.md`](../../skills/mimir-delegate/SKILL.md) | Secondary-LLM delegation mechanism and adapter contracts. |
| Maintainers' ideas backlog (not published) | Future-work items such as compact dossiers and in-panel git-capable profiles. |
