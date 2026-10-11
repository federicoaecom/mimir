# Setup audit

Part of the [setup workflow](../setup.md). This file holds the fast-path precondition, with its own steps 0 to 3 (not WORKFLOW step 0, the catalog reminder in `setup.md`), the full audit, and the POST-AUDIT CORRECTION PLAN. Read the precondition only for the audit triggered by the global trigger, and the correction plan after any minimum audit. WORKFLOW steps and the other sections named in capitals are in [`setup.md`](../setup.md), except steps 8.a to 8.h in [`update.md`](update.md), steps 9 to 34 in [`common-steps.md`](common-steps.md), EXPECTED LOCAL WRAPPERS in [`wrappers.md`](wrappers.md), and CONSTRAINTS in [`constraints.md`](constraints.md). Relative paths resolve from the `setup/` folder (see PATH RESOLUTION in `setup.md`).

### Fast-path precondition (global trigger only)

Skip straight to WORKFLOW step 1 when the user explicitly asks for setup, an update, or an audit. The precondition below is the lightweight safety path for the user's normal KB tasks; it runs only runtime, freshness, and the index gate while freshness returns `GATE_ONLY` and the gate returns `GATE_OK` — it does **not** load or apply the full WORKFLOW body on this short path. `AUDIT_REQUIRED` for a missing, invalid, or stale setup contract signature is deliberate: after a `git pull` of the shared methodology base, the workspace needs re-checking whenever this workflow's contract surface changed, to see whether it must absorb new wrappers, gates, metadata, or local rules. Commits on unrelated workstreams that don't touch that surface should not, by themselves, trigger a full audit.

0. Check whether `Test-*KbPowerShellRuntime.ps1` exists in the workspace's `scripts/` and run it before any other wrapper, with the canonical command form (see [Running scripts](../../SKILL.md#running-scripts) in `SKILL.md`):
   ```text
   pwsh -NoProfile -File "<absolute-path-to-Test-*KbPowerShellRuntime.ps1>"
   ```
   - Missing → proceed with a full audit (WORKFLOW step 1), but classify the precondition as `setup_blocked` until the wrapper is created via `update-local-bootstrap`.
   - `POWERSHELL_RUNTIME_OK` → proceed to step 1 below.
   - `BLOCK:` or failure → record the error and block operational use of the workspace until `pwsh` 7.4 or later on Windows (7.4.6 or later on Linux and macOS) is available.
1. Check whether `Test-*KbSetupFreshness.ps1` exists in the workspace's `scripts/`. Missing → proceed with a full audit (WORKFLOW step 1).
2. If present, run it:
   ```text
   pwsh -NoProfile -File "<absolute-path-to-Test-*KbSetupFreshness.ps1>"
   ```
   Declare the result in the conversation before proceeding:
   - `GATE_ONLY` → state "`Test-*KbSetupFreshness.ps1` returned `GATE_ONLY`".
   - `AUDIT_REQUIRED: <reason>` → state "`Test-*KbSetupFreshness.ps1` returned `AUDIT_REQUIRED` — `<reason>`".
   - Script absent (per step 1) → state "`Test-*KbSetupFreshness.ps1` missing — full audit required".
   - Unexpected error → record the error before deciding the next step.
3. Follow the output:
   - `AUDIT_REQUIRED: <reason>` → proceed with a full audit (WORKFLOW step 1).
   - `GATE_ONLY` → run `Test-*KbIndexGate.ps1`; `GATE_OK` releases the normal flow; `BLOCK` → proceed with a full audit.

Never reason about timestamps manually or substitute the script's execution with manual date/file inspection.

**Full audit**, when triggered by the global trigger, means: run `Test-*KbPowerShellRuntime.ps1` before the other wrappers; if it is missing or returns `BLOCK:`, classify as `setup_blocked` and do not allow operational use of the workspace. With the runtime approved, run `Test-*KbSetupAudit.ps1` (if it exists), then `Test-*KbIndexGate.ps1` (if it exists), verify that `suggested_operational_state` is compatible with the task at hand, and release the flow only after `GATE_OK`. The one exception is a workspace before its first index build (see [Structure gate before the first index build](../setup.md#structure-gate-before-the-first-index-build)): when the audit suggests `ready_for_first_materialization` and reports `index/gate: PENDING` with `first index build pending` (the gate's only block is the not-yet-built `KbIntelligence/kb-intelligence.sqlite`), release the flow for the **sync** workflow, which builds the index, and keep every other task blocked. After a full audit, explicitly classify the precondition's transient sub-state before returning to the original task; these `setup_*` labels are **not** canonical completion states and must never be used as the setup's final state:

- `setup_ready`: audit passed, gate passed (or, for the first sync only, blocked solely by the missing index file), and no persistent pending item remains from the original `AUDIT_REQUIRED` reason.
- `setup_ready_metadata_pending`: audit and gate passed, but the original `AUDIT_REQUIRED` reason was a missing, stale, or inconsistent persistent field in `kb-source-metadata.md` (e.g. `last_setup_audit_run_at` or `setup_contract_signature_*`).
- `setup_blocked`: minimum PowerShell runtime failed/missing, audit or gate failed, or `suggested_operational_state` is not compatible with the task at hand.

When the original `AUDIT_REQUIRED` reason was a missing or stale setup contract signature and the full audit plus gate pass without a fixable pendency, treat writing `last_setup_audit_run_at` and `setup_contract_signature_*` as closing the precondition successfully: include `Set-*KbSetupAuditTimestamp.ps1` in the consolidated plan, or record the user's explicit refusal/deferral. Without that closure, the next session repeats the full audit for the same reason even though the folder was already checked.

If the sub-state is `setup_ready_metadata_pending`, do not silently continue just because the gate returned `GATE_OK`. Before resuming the original task, build the **consolidated correction plan** (see POST-AUDIT CORRECTION PLAN), mandatorily including the `last_setup_audit_run_at`/`setup_contract_signature_*` line with `Set-*KbSetupAuditTimestamp.ps1` when the successful audit allows writing it. State that the current task is released by the gate, but the folder will repeat the full audit in future sessions until the plan is executed or explicitly deferred.

Whenever `Test-*KbSetupAudit.ps1` runs, read every `wrappers/inventory:` line, even if an earlier runtime, missing-materialization, or naming condition selected a different `suggested_operational_state`. Fold each pendency (`INVENTORY_GAPS`, `INVENTORY_CUSTOMIZED`, `INVENTORY_RECOMMENDED_MISSING`) into the **consolidated correction plan**, explained in plain language. If the consultative `INVENTORY_SURFACE_ADVISORY` line is also present (which, on its own, does **not** cause `methodology_update_pending`), fold it into the same plan as a surface-realignment recommendation, not a blocker. Do not trigger the creation/documentation WORKFLOW (steps 1–7b) here — that is reserved for an explicit user request for setup, an update, or an audit.

When `Test-*KbSetupAudit.ps1`'s output carries `metadata wrapper:` different from `OK` (`PENDING_DATA`, `PENDING`, or `BLOCK`), treat it as a correction item and never declare a clean state on that evidence. The engine may suggest `ready_for_first_materialization` first when sync has not yet materialized a snapshot, or a naming-pendency token first when naming diverges; its state switch does not always select `methodology_update_pending` for this case. `GATE_OK`, `NAMING_OK`, and a gap-free inventory do not neutralize missing identity metadata or a broken metadata wrapper. Surface the `metadata wrapper.evidence` line, distinguish a missing field from a functional wrapper failure, and — when the pendency is a missing stable identity — offer reconciliation via the identity resolver/updater before declaring a clean state.

The setup audit does not report deployment, hosting, or packaging dimensions. This workflow does not collect deployment metadata, invoke MSBuild, build, import, or package.

After setup succeeds, route any XML existence/location/triage query to the **find** workflow before opening individual files, whenever the folder adopts `KbIntelligence`.

## POST-AUDIT CORRECTION PLAN

Applies whenever this workflow has completed the **minimum audit** — in `audit-setup`, in the update block of update mode, or in the global trigger precondition's **full audit** (after `Test-*KbSetupAudit.ps1` and `Test-*KbIndexGate.ps1` with `GATE_OK`, when applicable). It does not replace the explicit-approval-before-writing rules; it consolidates **what to offer to fix** and **in what order**, so the user does not have to discover pendencies one at a time.

### Objective

When the audit finishes, deliver to the user:

1. **Diagnosis** (canonical operational state, `Test-*KbSetupAudit.ps1` dimensions when it exists, the 8.h table in update mode).
2. **Consolidated correction plan** — a single list of items this workflow can fix in this folder, each with a proposed action, whether approval is required (yes/no), and the intent used (`update-local-bootstrap`, `fix-local-wrapper`, WORKFLOW step 34, etc.).
3. **Batch offer**: ask whether to execute the plan (or a subset) **now, in this session**; never close with "left pending" or default to recommending a future round.

`GATE_OK` can release the user's original task **in parallel** with the plan, but it never excuses presenting the plan when a correctable item exists.

### Items to include (when detected)

Fold in **every** item below the audit found; omitting one when evidence exists is not allowed.

| Typical source | Plan item | Preferred action | Approval before writing |
|---|---|---|---|
| `setup_ready`, `setup_ready_metadata_pending`, or WORKFLOW step 34 after `AUDIT_REQUIRED` | `last_setup_audit_run_at` or `setup_contract_signature_*` missing, empty, or stale after a successful audit; includes an updated setup contract | `Set-*KbSetupAuditTimestamp.ps1`; rerun freshness and the index gate | Yes, when local rules require it |
| `INVENTORY_GAPS` / scripts `MISSING` in 8.h | Missing wrappers/gates | `update-local-bootstrap`: rerun the scaffolder (fallback: the `.example.ps1` files) | Yes |
| `INVENTORY_CUSTOMIZED` | Wrapper diverging from the example | Menu 8.c, or deterministic case → `fix-local-wrapper` | Yes, per script or batch |
| `INVENTORY_SURFACE_ADVISORY` (consultative, non-blocking) | Local wrapper behind the template by an optional/`ValidateSet` reduction (`param()` surface diff) | Realign the surface to the template, preserving local defaults; never recopy the template wholesale | Yes, if the user opts to realign |
| Deterministic case (8.a.iii, 8.z) | Stale wrapper with an unambiguous fix | `fix-local-wrapper` without an A/B/C/D menu | Yes, when local rules require it |
| `metadata wrapper` ≠ OK | Identity or metadata contract | Reconciliation via `Resolve-*KbIdentity`/`Update-*KbMetadataIdentity`, or fix the wrapper | Yes |
| `declarative/timestamps=LITERAL_TIMESTAMP_DRIFT` | Literal timestamps in `AGENTS.md`/`README.md` | Replace with pointers (`examples/AGENTS.md.example`) | Yes |
| `## Index triage` section missing (8.g) | Routing to the **find** workflow | Insert the standard block into the local `AGENTS.md` | Yes |
| `INVENTORY_RECOMMENDED_MISSING` | Recommended thin wrappers | Rerun the scaffolder (fallback: the `.example.ps1` files) | Yes |
| Stale verb prefix (8.f) | Local name ≠ canonical example (`Update-` vs `Rebuild-`, etc.) | Rename + update references | Yes |
| `Test-*KbPowerShellRuntime.ps1` missing | Missing runtime gate | Add the runtime wrapper | Yes |

### Items that do **not** enter this workflow's plan

Never promise in the consolidated plan what belongs to another workstream; mention it only as **out of scope**, with the responsible workflow:

- XPZ materialization, XML corpus sync, `last_xpz_materialization_run_at` → the **sync** workflow.
- Index rebuild/regeneration when it is stale due to materialization → index wrappers + a chained **sync** run.
- Divergent directory naming in the official corpus → diagnose the type mismatch, then route a proposed fix to the **sync** workflow or a separately approved shared-engine correction; never manually rename directories in this read-only snapshot.
- Generating or packaging business XML objects → out of scope for this workflow.
- CUSTOMIZED scripts with editorial logic divergence and no deterministic fix → enter the plan as a **user decision** (8.c), not as an "automatic fix".

### Suggested execution order

Once the user approves the correction plan, execute in this order unless a concrete blocker prevents it:

1. `Test-*KbPowerShellRuntime.ps1` present and OK (if it was missing).
2. Deterministic wrapper fixes (`fix-local-wrapper`) that unblock gates.
3. `update-local-bootstrap` for `MISSING` scripts.
4. Verb-prefix alignment (8.f).
5. Declarative drift (`AGENTS.md`/`README.md`) and the index-triage section.
6. Setup metadata (`Set-*KbSetupAuditTimestamp.ps1`) once a successful audit allows it.
7. Stable-identity reconciliation when `metadata wrapper` requires it.
8. `INVENTORY_RECOMMENDED_MISSING` wrappers, once approved by the user. Corpus naming divergences are reported separately and routed to sync/mapping correction, not executed as a setup-plan write.
9. Rerun `Test-*KbSetupAudit.ps1`, `Test-*KbSetupFreshness.ps1` (if it exists), and `Test-*KbIndexGate.ps1`; update the handoff.

### Global-trigger precondition

After classifying the transient sub-state (`setup_ready`, `setup_ready_metadata_pending`, `setup_blocked`):

- `setup_blocked`: do not return to the original task; the plan only covers what is fixable to unblock it.
- `setup_ready` or `setup_ready_metadata_pending` with correctable items: **build the consolidated plan** before resuming the original task; pending-metadata items enter as plan lines, not a lone loose warning. When the only item is refreshing `last_setup_audit_run_at`/`setup_contract_signature_*` after a successful audit required by a missing or stale signature, it must still appear in the plan, to restore the `GATE_ONLY` path for future sessions.
- Record the user's decision on the plan: executed (fully/partially), refused, or deferred — only then resume the original task released by the gate.

### Closing `audit-setup`

`audit-setup` never closes with just a diagnosis. It closes with diagnosis **+** the consolidated plan offered **+** a record of the user's decision (execute now, refuse, defer, or execute a subset). If the user approves execution, the workflow may move into `update-local-bootstrap` and/or `fix-local-wrapper` in the same session without requiring a new request.

### LLM delegation policy (optional, deferrable, non-blocking)

The delegation scripts named below (`Resolve-LlmDelegateAuthorization.ps1`, `Build-LlmDelegateCapabilityManifest.ps1`) are owned by the `mimir-delegate` skill, not by this skill. When `mimir-delegate` is installed, run them from its `scripts` folder, the sibling of this skill's folder (`../../../mimir-delegate/scripts/` from this file). When it is not installed, skip the script-backed steps below with a short notice; everything here stays optional and never blocks a completion state.

The `mimir-delegate` skill uses a per-KB policy file at the root of the workspace to durably authorize sending this KB's content to external models (see `mimir-delegate`'s `SKILL.md`). The file name is `llm-delegation-policy.json`.

- This item is **never** a setup gate, is not part of the required-wrapper matrix, and **never** blocks any completion state. Setup closes normally without it.
- When setup concludes, **offer** (without pressure) to define the policy, in prose, with an explicit option to **defer** — users typically have a lot to absorb during setup.
- Absence of the file ⇒ `ask` behavior at the gate (`Resolve-LlmDelegateAuthorization.ps1`, from `mimir-delegate`); deferring never opens a loophole.
- If the user accepts, write `llm-delegation-policy.json` with `schemaVersion`, `defaultExternal`, and fine-grained `provider/model` entries per the user's choice; never assume `allow-external` on your own.
- At the same time (also optional and non-blocking), offer to save a **capability snapshot** of the LLMs available on the machine with `Build-LlmDelegateCapabilityManifest.ps1 -SnapshotPath <workspace-root>\Temp\llm-delegate-capabilities.snapshot.json` (from `mimir-delegate`), to feed a future **peer review** offer (see the peer-review methodology in the `mimir-delegate` skill, `references/15-peer-review.md`) without re-probing every time. **Capability ≠ authorization:** it is a separate file from the policy, lives in `Temp/` (already git-ignored), is a re-derivable cache, and is only an **offer hint, never gate truth** — `Resolve-LlmDelegateAuthorization.ps1` always re-evaluates destination and sensitivity. When reviewing it, compare `snapshotAt`/`sourceGeneratedAt` and ask the user whether to refresh the probe or keep the recorded one; never re-probe automatically.
