# Setup workflow

Defines and validates the initial structure of the **KB workspace** used alongside a GeneXus Knowledge Base. This structure does not replace the native KB folder; it organizes the user's IDE-exported `XPZ` inputs, the XML materialized by the official flow, the derived index used for triage, and stable KB identity metadata.

---

## COMPLETION CHECKLIST

Read this whole file before acting on it. It is long: when the tool shows only part of it, keep reading in parts until **CONSTRAINTS**, the last section.

Before declaring any completion state (see **SETUP COMPLETION STATES**), confirm that each applicable item below was done, or that the user explicitly refused it. These are steps of this workflow, not optional extras: never present them as optional items in a list of offers.

1. The runtime gate `Test-*KbPowerShellRuntime.ps1`, then the setup audit `Test-*KbSetupAudit.ps1`, ran (8.s.5, 8.g3).
2. When the agent tool has a command allowlist: the workspace allow rule (step 20), the shared-scripts allow rule (step 20a), and, when the tool has file-read rules, the read rules for the clone's `skills` folder and for each skill link in the tool's skills folder (step 20a) were each shown verbatim, with the settings file path, on screen with the question, as COMMUNICATION, **Show before asking** describes, and asked about before writing; the shared-scripts rule before the first direct call to a shared script after the scaffolder, which runs once before it by design (step 20a). One question may cover all of them when it shows each verbatim.
3. The global instruction files were checked (7b); any write to one was asked as its own question, showing the file path and the exact block on screen with the question, as COMMUNICATION, **Show before asking** describes.
4. The local `AGENTS.md` has its `## Index triage` section (7a).
5. Nothing was saved to an external memory tool during this run (workspace details or anything else) without an explicit yes to a question naming what would be saved and where (step 14).
6. On a successful canonical state, `Set-*KbSetupAuditTimestamp.ps1` wrote the setup-audit timestamp and the contract signature (step 34) as the last write of the setup run, after every edit to `AGENTS.md`, `README.md`, and other workspace files.
7. The closing message gives the canonical state, says that `KbObjectsXml` is not materialized yet and that the next step is a full XPZ export and the **sync** workflow (steps 29 and 31), tells the user to start the agent tool in the KB workspace folder for KB work so the allow rules written there apply (step 20), says that permission prompts continue in this session when it was not opened in that folder (step 31), and recommends the **install** workflow by name in a sentence of its own (step 32).

---

## PURPOSE

This workflow **must** run before any query, triage, or XML read in a folder containing `KbObjectsXml/` or `KbIntelligence/`. No other KB workflow of this skill (the **find** workflow, the **read** workflow, the **sync** workflow) may start in that folder until this workflow has run in the current session.

### Fast-path precondition (global trigger only)

Skip straight to WORKFLOW step 1 when the user explicitly asks for setup, an update, or an audit. The precondition below is the lightweight safety path for the user's normal KB tasks; it runs only runtime, freshness, and the index gate while freshness returns `GATE_ONLY` and the gate returns `GATE_OK` — it does **not** load or apply the full WORKFLOW body on this short path. `AUDIT_REQUIRED` for a missing, invalid, or stale setup contract signature is deliberate: after a `git pull` of the shared methodology base, the workspace needs re-checking whenever this workflow's contract surface changed, to see whether it must absorb new wrappers, gates, metadata, or local rules. Commits on unrelated workstreams that don't touch that surface should not, by themselves, trigger a full audit.

0. Check whether `Test-*KbPowerShellRuntime.ps1` exists in the workspace's `scripts/` and run it before any other wrapper, with the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`):
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

**Full audit**, when triggered by the global trigger, means: run `Test-*KbPowerShellRuntime.ps1` before the other wrappers; if it is missing or returns `BLOCK:`, classify as `setup_blocked` and do not allow operational use of the workspace. With the runtime approved, run `Test-*KbSetupAudit.ps1` (if it exists), then `Test-*KbIndexGate.ps1` (if it exists), verify that `suggested_operational_state` is compatible with the task at hand, and release the flow only after `GATE_OK`. The one exception is a workspace before its first index build (see [Structure gate before the first index build](#structure-gate-before-the-first-index-build)): when the audit suggests `ready_for_first_materialization` and reports `index/gate: PENDING` with `first index build pending` (the gate's only block is the not-yet-built `KbIntelligence/kb-intelligence.sqlite`), release the flow for the **sync** workflow, which builds the index, and keep every other task blocked. After a full audit, explicitly classify the precondition's transient sub-state before returning to the original task; these `setup_*` labels are **not** canonical completion states and must never be used as the setup's final state:

- `setup_ready`: audit passed, gate passed (or, for the first sync only, blocked solely by the missing index file), and no persistent pending item remains from the original `AUDIT_REQUIRED` reason.
- `setup_ready_metadata_pending`: audit and gate passed, but the original `AUDIT_REQUIRED` reason was a missing, stale, or inconsistent persistent field in `kb-source-metadata.md` (e.g. `last_setup_audit_run_at` or `setup_contract_signature_*`).
- `setup_blocked`: minimum PowerShell runtime failed/missing, audit or gate failed, or `suggested_operational_state` is not compatible with the task at hand.

When the original `AUDIT_REQUIRED` reason was a missing or stale setup contract signature and the full audit plus gate pass without a fixable pendency, treat writing `last_setup_audit_run_at` and `setup_contract_signature_*` as closing the precondition successfully: include `Set-*KbSetupAuditTimestamp.ps1` in the consolidated plan, or record the user's explicit refusal/deferral. Without that closure, the next session repeats the full audit for the same reason even though the folder was already checked.

If the sub-state is `setup_ready_metadata_pending`, do not silently continue just because the gate returned `GATE_OK`. Before resuming the original task, build the **consolidated correction plan** (see POST-AUDIT CORRECTION PLAN), mandatorily including the `last_setup_audit_run_at`/`setup_contract_signature_*` line with `Set-*KbSetupAuditTimestamp.ps1` when the successful audit allows writing it. State that the current task is released by the gate, but the folder will repeat the full audit in future sessions until the plan is executed or explicitly deferred.

Whenever `Test-*KbSetupAudit.ps1` runs, read every `wrappers/inventory:` line, even if an earlier runtime, missing-materialization, or naming condition selected a different `suggested_operational_state`. Fold each pendency (`INVENTORY_GAPS`, `INVENTORY_CUSTOMIZED`, `INVENTORY_RECOMMENDED_MISSING`) into the **consolidated correction plan**, explained in plain language. If the consultative `INVENTORY_SURFACE_ADVISORY` line is also present (which, on its own, does **not** cause `methodology_update_pending`), fold it into the same plan as a surface-realignment recommendation, not a blocker. Do not trigger the creation/documentation WORKFLOW (steps 1–7b) here — that is reserved for an explicit user request for setup, an update, or an audit.

When `Test-*KbSetupAudit.ps1`'s output carries `metadata wrapper:` different from `OK` (`PENDING_DATA`, `PENDING`, or `BLOCK`), treat it as a correction item and never declare a clean state on that evidence. The engine may suggest `ready_for_first_materialization` first when sync has not yet materialized a snapshot, or a naming-pendency token first when naming diverges; its state switch does not always select `methodology_update_pending` for this case. `GATE_OK`, `NAMING_OK`, and a gap-free inventory do not neutralize missing identity metadata or a broken metadata wrapper. Surface the `metadata wrapper.evidence` line, distinguish a missing field from a functional wrapper failure, and — when the pendency is a missing stable identity — offer reconciliation via the identity resolver/updater before declaring a clean state.

The setup audit does not report deployment, hosting, or packaging dimensions. This workflow does not collect deployment metadata, invoke MSBuild, build, import, or package.

After setup succeeds, route any XML existence/location/triage query to the **find** workflow before opening individual files, whenever the folder adopts `KbIntelligence`.

### When to use

Use this workflow when work requires preparing, explaining, validating, updating, or fixing the KB workspace structure. Always keep the native KB folder distinct from the KB workspace, and apply the default names when the user has not specified alternatives.

### Detecting setup intent in an existing workspace

When the user uses language suggesting setup — "redo", "restart", "recreate", "update", "I need the new scripts", "my gate is failing", or equivalent — in a folder that already has real history, assume **update mode** and briefly confirm with the user what will be done before writing anything. For a generic request such as "redo the setup" or "review the setup", default to the **audit-setup** intent until the user explicitly asks for `fix-local-wrapper` or `update-local-bootstrap`. In a folder with real history, **creation mode** is never offered or accepted; if the user insists on wiping everything or recreating from scratch, refuse, explain that existing data will not be destroyed, and redirect to update mode.

That brief pre-write confirmation must be textual, to the point, and grounded in the diagnosis under way — never a menu, survey, or questionnaire opened right at the start of update mode before the mandatory minimum audit has completed.

In update mode, the naming check of `KbObjectsXml` is never optional and can never be skipped, even when every script classifies as EQUIVALENT: for each directory present, read at least one XML, extract the canonical type from the GUID (or from a root `<Attribute>` element), compare it against the directory name, and report the result — conforming or divergent — before declaring any completion state.

### Operational intents inside update mode

Separate the operational intent before proceeding:

- **`audit-setup`**: the user wants to check whether the workspace is compliant, current, and coherent; the main output is a diagnosis with operational state, script classification, pendencies, and the **consolidated correction plan** offered for execution in the same session.
- **`fix-local-wrapper`**: the user wants to fix a stale, broken, or gate-rejected local wrapper; the main output is editing the wrapper, rerunning the relevant gate, and an updated handoff.
- **`update-local-bootstrap`**: the user wants to add wrappers or documentation sections the shared methodology base expects but that are missing; the main output is completing the missing local bootstrap without recreating the folder.

Update mode describes the folder's context; the three intents describe the nature of the work — never conflate them just because they happen in the same folder.

In `audit-setup`, finish the mandatory minimum audit first, then build and offer the **consolidated correction plan** before any other next operational step. Before that, do not default-offer "re-sync the XPZ", "rebuild the index", or equivalent as the standard response to "redo the setup".

---

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

The delegation scripts named below (`Resolve-LlmDelegateAuthorization.ps1`, `Build-LlmDelegateCapabilityManifest.ps1`) are owned by the `mimir-delegate` skill, not by this skill. When `mimir-delegate` is installed, run them from its `scripts` folder, the sibling of this skill's folder (`../../mimir-delegate/scripts/` from this file). When it is not installed, skip the script-backed steps below with a short notice; everything here stays optional and never blocks a completion state.

The `mimir-delegate` skill uses a per-KB policy file at the root of the workspace to durably authorize sending this KB's content to external models (see `mimir-delegate`'s `SKILL.md`). The file name is `llm-delegation-policy.json`.

- This item is **never** a setup gate, is not part of the required-wrapper matrix, and **never** blocks any completion state. Setup closes normally without it.
- When setup concludes, **offer** (without pressure) to define the policy, in prose, with an explicit option to **defer** — users typically have a lot to absorb during setup.
- Absence of the file ⇒ `ask` behavior at the gate (`Resolve-LlmDelegateAuthorization.ps1`, from `mimir-delegate`); deferring never opens a loophole.
- If the user accepts, write `llm-delegation-policy.json` with `schemaVersion`, `defaultExternal`, and fine-grained `provider/model` entries per the user's choice; never assume `allow-external` on your own.
- At the same time (also optional and non-blocking), offer to save a **capability snapshot** of the LLMs available on the machine with `Build-LlmDelegateCapabilityManifest.ps1 -SnapshotPath <workspace-root>\Temp\llm-delegate-capabilities.snapshot.json` (from `mimir-delegate`), to feed a future **peer review** offer (see the peer-review methodology in the `mimir-delegate` skill, `references/15-peer-review.md`) without re-probing every time. **Capability ≠ authorization:** it is a separate file from the policy, lives in `Temp/` (already git-ignored), is a re-derivable cache, and is only an **offer hint, never gate truth** — `Resolve-LlmDelegateAuthorization.ps1` always re-evaluates destination and sensitivity. When reviewing it, compare `snapshotAt`/`sourceGeneratedAt` and ask the user whether to refresh the probe or keep the recorded one; never re-probe automatically.

---

## PATH RESOLUTION

- Every `../file.md` reference in this workflow resolves from this file's own folder, not from the current working directory; `../` points at the shared methodology base one level up.
- When the session already publishes a path for this skill or its examples, use that published path as the authoritative source; do not infer an alternative by heuristic.
- For `examples/`, resolve the sibling folder of the published workflow file first. If that file comes from outside the current repository, do not assume a similarly-named local folder is the right one just because it exists in the current workspace.
- A published path outside the current workspace does not license reinterpreting the skill's origin or silently switching to an "equivalent" in-repo path; the published path keeps prevailing until there is objective evidence otherwise.
- If the published `examples/` has not been read yet, the audit may proceed provisionally on locally available evidence (`GATE_OK`, `STRUCTURE_OK`, wrapper parsing, presence of required sections, and the naming check), leaving the final classification against the examples as an explicit pending step rather than opening broad path exploration too early.

---

## TRIGGERS

Use this workflow for:

- The initial load of a KB via a KB workspace.
- Preparing the initial folder structure for `XPZ`-based flows.
- Validating whether the KB workspace is ready for read, sync, index, and identity workflows.
- Preparing the KB workspace for the derived index used by `KbIntelligence`.
- Auditing an existing KB workspace's setup and, at the end, offering in the same session the consolidated correction plan for everything this workflow classifies as fixable in that folder (execution after approval where required).
- Fixing a stale or gate-rejected local wrapper, especially when the evidence comes from `Test-*KbMetadataWrapper.ps1`, `Test-*KbIndexGate.ps1`, or `Test-*KbStructure.ps1`.
- Updating a workspace with usage history to add scripts the shared methodology base now expects.
- Blocking operational use of the workspace when `pwsh` with PowerShell 7.4 or later on Windows (7.4.6 or later on Linux and macOS) is unavailable.
- Detecting that the workspace's `AGENTS.md` is behind the current canonical pattern — e.g. a missing `## Index triage` section, an incomplete wrapper list, or other sections missing compared to `examples/AGENTS.md.example`.
- Checking whether container-directory naming in `KbObjectsXml` matches each object's real GUID — especially `Folder/`, `Module/`, and `PackagedModule/` — and reporting divergences for correction through the supported sync/mapping workstream.
- Explaining the difference between the native KB folder and the KB workspace.
- Confirming default subfolder names when the user did not specify alternatives.

Do NOT use this workflow for:

- Syncing a specific `XPZ` into the official corpus (use the **sync** workflow).
- Generating, importing, or packaging business XML objects; these are outside Mimir Lite's supported scope.
- Analyzing an individual XML object's structure (use the **read** workflow).
- Querying the derived index as the main analytical step (use the **find** workflow).
- Regenerating the index as the task's main objective; this workflow prepares the structure and the local wrappers, not the index content itself.

---

## RESPONSIBILITIES

### Folder identity

- Explain that the native KB folder differs from the KB workspace; use "KB workspace" as the primary term.
- If the native KB folder's path is not given, ask for it before finishing the initial setup; if it is given, reuse it without asking again. When the user has no native KB folder, only XPZ exports, follow [XPZ-only workspace](#xpz-only-workspace) instead.
- If the agent checks the native KB folder's existence, state the result in the handoff; if it does not exist or is inaccessible, record the given path, keep the no-write rule, and close setup with an explicit operational caveat.
- Record the confirmed native-KB-folder path in the workspace's `AGENTS.md`, and record there that the native KB folder is off-limits for agent writes (read allowed only when an explicit operational flow truly requires it). Mirror both facts in the local `README.md`, in plain language for humans. The scaffolder writes both files with these facts when the native KB folder is given (see [CREATION BLOCK](#creation-block-scaffolder)); `README.md` comes from [`examples/README.md.example`](setup/examples/README.md.example).

### Default subfolders

When the user does not specify alternative names, assume: `scripts`, `Temp`, `IdeXpzExports`, `KbObjectsXml`, and `KbIntelligence`. These names are only suggested defaults; a folder's function prevails over its literal name. If the user gives different names, record the mapping in `AGENTS.md` and, when it helps humans, also in `README.md`.

In a well-scoped standard initial setup — no alternative names, no structural conflict, native KB folder already given — run the scaffolder (see [CREATION BLOCK](#creation-block-scaffolder)) without broad exploration of the shared engine and the examples first; explore further only if a concrete blocker appears. When local inspection of the folder contradicts indirect context from the environment, the session, or hooks, trust the local inspection first and follow up with a short, objective check — no long speculative narrative.

### Folder roles

- `KbObjectsXml` is the official snapshot and read-only for agents. Agents never edit it manually; it changes only when the **sync** workflow materializes an official XPZ returned by the native KB.
- `IdeXpzExports` is the inbox for user-provided `.xpz` files exported from the IDE. If it is missing when sync requires an XPZ, ask for the intended path or create the default folder only when approved. After a successful sync, an XPZ may be renamed to `processado_<original-name>.xpz`; never apply that prefix before success.
- `Temp` is the preferred destination for ephemeral artifacts, execution temporaries, disposable reports, and temporary SQLite copies.
- `KbIntelligence` holds the derived, regenerable SQLite index — normally `KbIntelligence\kb-intelligence.sqlite` — plus validation reports when the local repository adopts that flow.
- `kb-source-metadata.md` is the materialization's operational metadata; it must expose `last_xpz_materialization_run_at` once the official flow has processed an IDE input. Treat any local memory saying "not yet materialized" or "waiting for the first XPZ" as provisional — once the first official materialization succeeds, stop presenting that state as current.
- `KbIntelligence\kb-intelligence.sqlite`'s `metadata` table owns `last_index_build_run_at`; it must be equal to or later than `last_xpz_materialization_run_at` to allow broad search and triage. `last_index_build_run_at` is the authoritative source for index freshness — query it via `index-metadata`, never mirror or derive it into `kb-source-metadata.md`.
- Besides timestamp freshness, `Test-*KbIndexGate.ps1` must validate `extractor_signature_version` and `extractor_signature_hash` in the SQLite metadata against the shared engine (`../scripts/GeneXusKbIntelligenceExtractorContract.ps1` + `../scripts/Build-KbIntelligenceIndex.py` in the active repository). An index with no signature, or a divergent one, blocks with `BLOCK:` even when `last_index_build_run_at >= last_xpz_materialization_run_at` — regenerate the index.
- Rebuilding the index via `Rebuild-*KbIntelligenceIndex.ps1` (engine `../scripts/Build-KbIntelligenceIndex.ps1`) requires **usable Python 3.8 or later** on `PATH`, found as `python3`, `python`, or `py -3` (`../scripts/GeneXusPythonPrerequisite.ps1`; a Microsoft Store `WindowsApps` stub does not count). Its absence blocks the refresh with exit `8` and message `PREREQUISITE MISSING` — **be strict**: normal sync did **not** finish; the XPZ/XML materialization in `KbObjectsXml` may already have completed, but that is **not** equivalent to the official flow succeeding and does not authorize broad triage without an index. Do not treat this as a failure of the IDE-exported XPZ; install Python 3.8 or later and rerun the rebuild. `Update-KbFromXpz.example.ps1` propagates this message when the rebuild chain fails in the same `pwsh` process. See `README.md`, `../references/02-operational-rules.md`, and the **sync** workflow.
- Treat `kb-source-metadata.md` and the local query wrapper's `-Query index-metadata` output as the authoritative sources for materialization/index operational timestamps; local `AGENTS.md`/`README.md` are human-facing auxiliary memory and must never record literal `last_xpz_materialization_run_at`/`last_index_build_run_at` values — only pointers to the authoritative sources and to the `declarative/timestamps` line of `Test-*KbSetupAudit.ps1`.
- New complete `XPZ` files can be used at any time to re-update `KbObjectsXml`.
- When asked to review `KbObjectsXml` naming in an existing workspace, read at least one XML from each container directory (`Folder/`, `Module/`, `PackagedModule/`) and check the real `Object/@type` before concluding anything about inversion or conformance.
- Distinguish initial load from incremental sync.
- Materializing a complete IDE `XPZ` includes breaking `full.xml` into individual per-object XML files, organized into friendly-object-type subfolders, using friendly object names as filenames — `guid`, `parentGuid`, `parentType`, and `moduleGuid` are supporting metadata, never the primary organization axis.
- The `KbIntelligence` index can only be built once `KbObjectsXml` exists and holds the official materialized snapshot; it is a derived triage layer, never a substitute for the corpus. If `last_index_build_run_at` is missing or predates `last_xpz_materialization_run_at`, do not search the corpus broadly or perform substantive triage — treat it as an operational exception and offer to regenerate/validate the index first.

### Local wrappers, Git, and metadata bootstrap

- Expect local `.ps1` wrappers under `scripts` whenever the workspace needs to rebuild its local operational flow on top of the shared engine; a script with static KB parameters (fixed paths, KB name, GUIDs) deserves a local wrapper, while a script with fully dynamic per-run parameters (e.g. a log monitor whose PID and path vary each run) is called directly from the shared engine by absolute path, with no wrapper.
- `Test-*KbPowerShellRuntime.ps1` is the mandatory first gate of any operational use of the workspace: it must delegate to the shared engine `../scripts/Test-MimirPowerShellRuntime.ps1`, require `pwsh` 7.4 or later on Windows and 7.4.6 or later on Linux and macOS (the engine raises the minimum off Windows: pwsh 7.4.2 loses a native command's stderr when stdout and stderr are redirected to separate files), and block on `BLOCK:` or when missing.
- When the workspace is initialized from scratch for the official XPZ/XML materialization flow, treat the minimum local-wrapper layer under `scripts` as part of the expected technical bootstrap, not as a pendency for a later step; the scaffolder generates it. Never declare "initial setup done", "structure ready", or equivalent while that minimum layer — and, when adopted, `KbIntelligence` compatibility — is still missing.
- If the workspace is already Git-versioned, treat a root `.gitignore` and `.gitkeep` files in empty structural subfolders as an expected part of standard initial setup. If it is not yet versioned, the agent may offer to initialize local Git versioning as an optional supporting step — the decision belongs to the user; never run `git init` unilaterally.
- The `.gitignore` must always cover: `Temp`, `KbIntelligence` (only `kb-intelligence.sqlite` and `kb-intelligence-validation.json`), and `IdeXpzExports`; `KbObjectsXml` must never be ignored, since it is the official, version-worthy corpus. Every folder covered by a `folder/*` + `!folder/.gitkeep` pattern must get its `.gitkeep` file created in the same step the `.gitignore` is written — never reference a `.gitkeep` that does not physically exist. If the user accepts local Git versioning and the environment lacks a working Git, the agent may offer to install or guide the install before bootstrapping Git.
- Changing `.gitignore`, versioning policy, or tracked-file scope to enable `git add`/`commit` is a repository policy decision; the agent may diagnose and propose options but must not change that policy automatically just to close out the task.
- Reuse the official flow already defined in the skill and the shared engine before considering any new script.
- The scaffolder generates the initial `kb-source-metadata.md` in the shared engine's format, with the `last_xpz_materialization_run_at` field present from the start and empty values. Once the native KB folder's path is confirmed, resolve the stable identity via the local `Resolve-*KbIdentity.ps1 -UpdateMetadata` (engine `../scripts/Resolve-GeneXusKbIdentity.ps1`) before declaring the metadata fit, writing `kb-source-metadata.md` with `Source/kb (GUID)`, `Source/username`, `Source/UNCPath`, `Source/Version/guid`, and `Source/Version/name` filled in when resolution succeeds. If resolution fails, do not declare a clean metadata state — record the pendency and guide the fix instead of relying on a future XPZ carrying `Source`. The one exception is an XPZ-only workspace, where the XPZ `Source` block is the only identity source (see [XPZ-only workspace](#xpz-only-workspace)).
- Never save operational memory outside the KB workspace without explicit user authorization; `AGENTS.md`, `README.md`, and local operational files are the preferred memory layer for setup.
- When initial setup concludes, explicitly state that the workspace is ready but `KbObjectsXml` has not been materialized yet; once the first official materialization succeeds, refresh that provisional local memory so the handoff never shows a stale state.

### `kb-source-metadata.md` field authority

Treat `kb-source-metadata.md` by field authority, not single file ownership:

| Field group | Authority |
|---|---|
| Stable identity (`Source/kb (GUID)`, `Source/username`, `Source/UNCPath`, `Source/Version/guid`, `Source/Version/name`) | Primary: this workflow's setup/resolver against the local native KB. Secondary: the IDE-exported XPZ only when it is complete and coherent with the local KB. In an XPZ-only workspace: the XPZ `Source` block alone, written by the **sync** workflow. |
| Materialization (`last_xpz_materialization_run_at`, `source_xpz`, `source_refresh_status`) | The **sync** workflow. |
| Setup audit (`last_setup_audit_run_at`, `setup_contract_signature_version`, `setup_contract_signature_hash`) | This workflow, in the allowed canonical states. |

- Treat a `Source/kb (GUID)` mismatch between the XPZ and the locally resolved native KB as an identity conflict. Do not overwrite either identity automatically; surface the mismatch and reconcile only through an explicitly approved identity update.

### Wrapper bootstrap when `scripts` has none

If `scripts` exists with no minimum local wrappers, rerun the scaffolder (it only adds missing files; see [CREATION BLOCK](#creation-block-scaffolder)) to restore the daily sync and full-snapshot verification wrappers; the index query, rebuild/validation, and gate wrappers when `KbIntelligence` is adopted; and the runtime, metadata-reading, setup-audit, and identity-resolution wrappers required for the workspace. Do not bootstrap local object-generation, import/package, deployment, or build wrappers.

### Initial handoff

The workspace receives XPZ files exported by the user from the GeneXus IDE; the **sync** workflow materializes that input and refreshes the derived index. Setup does not create XPZ files or perform local object generation, deployment, build, import, or package creation.

On closing initial setup, recommend the **install** workflow to audit the full skill ecosystem installed on the machine, beyond what this workflow itself checks.

---

## INTENT → FOLDER MAPPING

| Intent | Use this folder |
|---|---|
| Query the materialized corpus | `KbObjectsXml` — receives individual XMLs extracted from the IDE-exported `XPZ`; may use subfolders per friendly GeneXus object type. |
| Query relationships, technical impact, or a short functional trail via the derived index | `KbIntelligence` for the derived SQLite and validation reports; local wrappers in `scripts` to query or regenerate it; `KbObjectsXml` stays the normative source and regeneration origin. |
| Store an IDE-exported `XPZ` | The XPZ inbox — input to the **sync** workflow, not the materialized corpus. |

---

## NAMING RULES

- For the materialized corpus, prefer subfolders per friendly GeneXus object type (e.g. `Transaction`, `Procedure`, `WebPanel`).
- For GeneXus containers, use the canonical convention derived from a real KB (e.g. SampleKb): `Folder/` for objects with `Object/@type="00000000-0000-0000-0000-000000000008"` (user-created containers — "Folders") and `Module/` for objects with `Object/@type="00000000-0000-0000-0000-000000000006"` (system containers: Main Programs, ToBeDefined).
- A subdirectory's name under `KbObjectsXml` is **not** a reliable indicator of the GeneXus type across KBs; the authoritative source is always `Object/@type` in the object's XML.
- Prefer the object's friendly name as the XML filename (e.g. `Cliente.xml`, `GeraBoleto.xml`); never use a GUID as the primary folder/file name. On a rare name collision, a GUID may appear only as a disambiguation aid, never as the main organization axis. `guid`, `parentGuid`, `parentType`, and `moduleGuid` are supporting metadata, not the main output structure.

---

## EXPECTED LOCAL WRAPPERS

### Requirement matrix

Quick reference for how serious a missing wrapper is. Detailed classification rules (`MISSING`/`EQUIVALENT`/`CUSTOMIZED`) and evidence criteria stay in 8.a and 8.g2–8.g4; this table is a quick read, not a substitute.

| Wrapper | Required when | Missing blocks |
|---|---|---|
| `Test-*KbPowerShellRuntime.ps1` | Always (first gate of operational use) | Any operational use of the workspace |
| `Test-*KbObjectsXmlNaming.ps1` | `KbObjectsXml` materialized | Clean `wrappers_updated` / `materialized_and_index_validated` |
| `Test-*KbSetupFreshness.ps1` | Always (global trigger invocation) | The precondition's fast path — missing forces a full audit on every trigger |
| `Set-*KbSetupAuditTimestamp.ps1` | Recommended whenever `last_setup_audit_run_at`/`setup_contract_signature_*` is missing, invalid, or stale after a successful audit | No state, as long as the shared engine can be called directly or manual editing follows WORKFLOW step 34 |
| `Update-*KbFromXpz.ps1` | Always (official materialization flow) | `ready_for_first_materialization` |
| `Test-*KbFullSnapshot.ps1` | Always (official materialization flow) | `ready_for_first_materialization` |
| `Query-*KbIntelligence.ps1` | `KbIntelligence` adopted | `wrappers_updated` |
| `Rebuild-*KbIntelligenceIndex.ps1` | `KbIntelligence` adopted | `wrappers_updated` |
| `Test-*KbIndexGate.ps1` | `KbIntelligence` adopted | `wrappers_updated` |
| `Get-*KbMetadata.ps1` | `KbIntelligence` adopted | `wrappers_updated` |
| `Resolve-*KbIdentity.ps1` | Expected at initial setup/audit when a native KB is confirmed and identity needs filling/checking; recommended for later reconciliations when an XPZ arrived with empty/incomplete `Source` | Stable identity metadata remains incomplete or divergent |
| `Test-*KbMetadataWrapper.ps1` | `KbIntelligence` adopted | `wrappers_updated` |
| `Test-*KbStructure.ps1` | `KbIntelligence` adopted | `wrappers_updated` |
| `Test-*KbSetupAudit.ps1` | `KbIntelligence` adopted | `wrappers_updated` |

- Beyond the mandatory `Test-*KbPowerShellRuntime.ps1` gate, `scripts` must have at least two local wrappers when the workspace runs the official XML materialization flow over the shared engine: a daily-update wrapper from an IDE-exported `.xpz` or XML export, and a full-check wrapper that reuses the daily one in `VerifyOnly + FullSnapshot` mode.
- When the workspace needs to reconcile a native KB's stable identity because the exported XPZ had empty/incomplete `Source`, recommend the thin local wrapper `Resolve-*KbIdentity.ps1`:
  - Delegates to `../scripts/Resolve-GeneXusKbIdentity.ps1`.
  - Read-only over `model.ini`, `knowledgebase.connection`, and the KB's internal database.
  - Returns `kbGuid`, `kbName`, `versionGuid`, `versionName`, `UNCPath`, and `username` to support an approved write to `kb-source-metadata.md`.
  - With an `-UpdateMetadata`-equivalent option, delegates to `../scripts/Update-MimirKbSourceMetadataIdentity.ps1`, fills missing stable-identity fields, and blocks non-empty divergences unless explicitly approved to overwrite.
  - Does not replace `Get-*KbMetadata.ps1`: this wrapper resolves identity from the native KB; `Get-*KbMetadata.ps1` reads metadata already written.
- When the workspace adopts `KbIntelligence`, `scripts` must also have thin local wrappers for:
  - Querying the derived index in `KbIntelligence\kb-intelligence.sqlite`.
  - Regenerating/validating the index from `KbObjectsXml`.
  - The freshness gate (`Test-*KbIndexGate.ps1`): calls the local query wrapper with `-Query index-metadata`, reads `kb-source-metadata.md`, compares timestamps, and returns `GATE_OK` or raises `BLOCK: <reason>`; depends on `Query-*KbIntelligence.ps1` in the same folder and must be the single entry point for the freshness gate.
  - Reading key `kb-source-metadata.md` fields (`Get-*KbMetadata.ps1`): removes the recurring `Select-String + regex` pattern from callers; exposes at least `last_xpz_materialization_run_at`, `kb_name`, and `source_guid`. Canonical semantic contract: `last_xpz_materialization_run_at` is a top-level/frontmatter field; `kb_name` is the `name` field in the `## Source/Version` table (the KB's IDE name); `source_guid` is the `kb (GUID)` field in `## Source` — the KB's GUID, never the version GUID under `## Source/Version` (an implementation reading `source_guid` from there is semantically wrong even if parsing succeeds).
  - Validating the metadata wrapper's functional contract (`Test-*KbMetadataWrapper.ps1`): calls the shared engine `Test-MimirKbMetadataWrapper.ps1`, compares what `Get-*KbMetadata.ps1` exposes against `kb-source-metadata.md`, and returns `METADATA_WRAPPER_OK`, `METADATA_WRAPPER_INCOMPLETE`, `PENDING_DATA`, or `BLOCK: ...`.
  - Auditing `KbObjectsXml` naming (`Test-*KbObjectsXmlNaming.ps1`): calls the shared engine `../scripts/Test-MimirKbObjectsXmlNaming.ps1`, covers every immediate directory of the snapshot, extracts the real type from a root `Attribute` element or `Object/@type`, compares against the **effective catalog** (`../scripts/gx-object-type-catalog.json` merged with the workspace's own `scripts/gx-object-type-catalog.override.json` when present), and returns `NAMING_OK`, `NAMING_DIVERGENT`, or `NAMING_INDETERMINATE`; it never renames directories.
  - A structure check (`Test-*KbStructure.ps1`): reports presence/absence of expected folders, scripts, and artifacts; returns `STRUCTURE_OK`, or one `MISSING:`/`PARSE_ERROR:` line per problem on stdout; used at setup and before any diagnostic operation. It requires `KbIntelligence/kb-intelligence.sqlite`: when that file is the only gap, it prints `PENDING: first index build pending: ...` until the first sync builds the index, and returns `STRUCTURE_OK` only after that first index build (see [Structure gate before the first index build](#structure-gate-before-the-first-index-build)).
  - The PowerShell runtime gate (`Test-*KbPowerShellRuntime.ps1`): calls the shared engine `../scripts/Test-MimirPowerShellRuntime.ps1`, checks for `pwsh` 7.4 or later on Windows and 7.4.6 or later on Linux and macOS, and blocks any operational use on `BLOCK:`; must be the first wrapper run in setup, audit, freshness, sync, or indexing.
  - The aggregated setup audit (`Test-*KbSetupAudit.ps1`): calls the shared engine `../scripts/Test-MimirSetupAudit.ps1`, consolidating deterministic evidence for `powershell/runtime`, `sync/materialization`, `naming/kb-objects`, `index/gate`, `index/semantics`, `metadata wrapper`, `declarative/timestamps`, `wrappers/inventory`, and `suggested_operational_state`. It orchestrates the specific gates but never replaces them as primary evidence. When `-PowerShellRuntimeTestPath` is not given, it scans `scripts/Test-*KbPowerShellRuntime.ps1` in the workspace, uses the single wrapper it finds, and — if none exists — emits `powershell/runtime.detection=missing` plus a suggested wrapper name and template, without auto-creating a file. When it exists and the operational intent is `audit-setup`, run it and use its consolidated output as the handoff vehicle; its dimensions replace manual synthesis of those same dimensions, but never the specific gates' underlying evidence.






- In `audit-setup`, already-registered identity metadata can support recommending `Resolve-*KbIdentity.ps1` for future reconciliations. This is advisory and does not block a clean state; preserve explicit approval before any identity update.
- A local wrapper must be thin: resolve the workspace's paths, point at the shared engine, forward parameters, and optionally produce a Git summary, report, and KB metadata.
- The materialization wrapper must pass `kb-source-metadata.md`'s path so `last_xpz_materialization_run_at` is written even when no XML materially changed, and must call the index regeneration/validation wrapper after a successful sync that is not `VerifyOnly`. The index regeneration wrapper must preserve the shared engine's produced metadata, including `last_index_build_run_at`.
- A new shared-engine parameter does not automatically mean local wrappers already expose it. A stale local wrapper is an update opportunity to mention to the user and wait for explicit approval — never fix it automatically. A local wrapper must never reimplement the shared engine when the official flow already exists.

### Reconstructing wrappers from the examples (fallback)

The scaffolder (see [CREATION BLOCK](#creation-block-scaffolder)) generates every wrapper from these examples, so hand adaptation is a fallback: use it only for a customized workspace the scaffolder cannot express (alternative folder names, local customizations to carry over) or when the scaffolder cannot run. Even then, prefer adapting this workflow's sanitized examples over improvising a new or partial flow. Name each wrapper `<Verb>-<KbName>Kb<Name>.ps1` (the KB name is letters and digits only) and rename the unprefixed sibling names it references (e.g. `Query-KbIntelligence.ps1` → `Query-SampleKbKbIntelligence.ps1`):

[Update-KbFromXpz.example.ps1](setup/examples/Update-KbFromXpz.example.ps1) · [Test-KbFullSnapshot.example.ps1](setup/examples/Test-KbFullSnapshot.example.ps1) · [Query-KbIntelligence.example.ps1](setup/examples/Query-KbIntelligence.example.ps1) · [Rebuild-KbIntelligenceIndex.example.ps1](setup/examples/Rebuild-KbIntelligenceIndex.example.ps1) · [Test-KbPowerShellRuntime.example.ps1](setup/examples/Test-KbPowerShellRuntime.example.ps1) · [Test-KbObjectsXmlNaming.example.ps1](setup/examples/Test-KbObjectsXmlNaming.example.ps1) · [gx-object-type-catalog.override.json.example](setup/examples/gx-object-type-catalog.override.json.example) · [Test-KbIndexGate.example.ps1](setup/examples/Test-KbIndexGate.example.ps1) · [Get-KbMetadata.example.ps1](setup/examples/Get-KbMetadata.example.ps1) · [Resolve-KbIdentity.example.ps1](setup/examples/Resolve-KbIdentity.example.ps1) · [Test-KbMetadataWrapper.example.ps1](setup/examples/Test-KbMetadataWrapper.example.ps1) · [Test-KbSetupAudit.example.ps1](setup/examples/Test-KbSetupAudit.example.ps1) · [Test-KbStructure.example.ps1](setup/examples/Test-KbStructure.example.ps1) · [Test-KbSetupFreshness.example.ps1](setup/examples/Test-KbSetupFreshness.example.ps1) · [Set-KbSetupAuditTimestamp.example.ps1](setup/examples/Set-KbSetupAuditTimestamp.example.ps1)



These `.example.ps1` files are important methodological references for technical bootstrap and assisted wrapper reconstruction; they never substitute for the workspace's real local wrapper and must never become an automatic execution fallback in the normal flow. A wrapper derived from a `.example.ps1` only counts as a valid bootstrap wrapper once the agent has validated the `.ps1` parses and has no sanitized placeholders left in executable values, effective configuration, default paths, default parameters, or real calls. The sanitized placeholders in the examples are `C:\path\to\mimir-lite` (default `-SharedSkillsRoot`, the root of the shared Mimir Lite checkout) and `C:\path\to\native-kb` (native KB folder in `Resolve-KbIdentity.example.ps1`, set to an empty string in an XPZ-only workspace); the help blocks also use `<WorkspaceRoot>` in their `.EXAMPLE` commands, which the scaffolder fills with the workspace folder. Illustrative paths kept only inside comment/help blocks (e.g. `.EXAMPLE`) do not block bootstrap by themselves, but must never be cited as evidence of a validated local configuration.

The sanitized examples embody a real KB-workspace trail with: KB metadata recorded in `kb-source-metadata.md`; `last_xpz_materialization_run_at` updated on every requested XPZ/XML run; mandatory derived-index refresh after a successful materialization; a Git summary scoped to the official corpus when there is a material change; localized cleanup of leftovers from a renamed object (preserving the XML under its current name with the more trustworthy `lastUpdate`); optional forwarding of `ExpectedItems` to distinguish the expected focus from additional official returns; the derived index at `KbIntelligence\kb-intelligence.sqlite`; `last_index_build_run_at` recorded in the SQLite `metadata` table and mirrored in the validation report; and index query/regeneration delegated to local wrappers, never reimplementing the shared engine.

---

## OPERATIONAL COMPATIBILITY GATE

Before any substantive work in a KB workspace that declares `KbIntelligence` use, validate four layers in the exact order `Test-*KbIndexGate.ps1` runs them:

1. **Structure** (via `Test-*KbStructure.ps1`): expected functional folders, `README.md`, `AGENTS.md`, `kb-source-metadata.md`, `KbObjectsXml`, `KbIntelligence` with its `kb-intelligence.sqlite`, and the minimum scripts under the right names. Anything other than `STRUCTURE_OK` blocks immediately — do not move to inner layers. Because the index file exists only after the first sync builds it, this layer — and therefore the whole gate — passes only after the first index build.
2. **Wrappers**: functional local scripts in `scripts`, including index query with `index-metadata` support, index regeneration/validation with `-FailOnValidationFailure`, and XPZ/XML materialization with mandatory index refresh.
3. **Inventory semantics**: `index-metadata` must expose `inventory_validation_status=OK`, confirming the SQLite inventory stays coherent with the official snapshot and the shared technical type catalog.
4. **Freshness**: `last_index_build_run_at` (from the local query wrapper) must be equal to or later than `last_xpz_materialization_run_at` (read nominally from `kb-source-metadata.md`).

Run the gate sequentially and stop at the first block; do not investigate inner layers while an outer one is still invalid — at most mention that further checks may follow the first fix.

Detect wrapper staleness before running the actual business task:

- The query wrapper must accept `index-metadata` itself; an unknown-parameter failure, a stale `ValidateSet`, or missing `last_index_build_run_at` in the output all block.
- `index-metadata` must also expose `inventory_validation_status`; missing or non-`OK` blocks.
- The regeneration wrapper must exist, accept `-FailOnValidationFailure`, and write `last_index_build_run_at` into the generated index.
- The materialization wrapper must call the index regeneration/validation wrapper after a successful sync that is not `VerifyOnly` when the folder adopts `KbIntelligence`; without clear evidence of that chaining, block the next normal sync and offer an update. Clear evidence means an explicit statement in local `README.md`/`AGENTS.md` or an observable call inside the wrapper itself — never assume compatibility just because the shared base already requires that behavior.
- `kb-source-metadata.md` must expose the nominal `last_xpz_materialization_run_at` field; if it does not exist, block. Do not accept a file date, `updated`, `generated_at`, `source_xpz`, a report date, or any other approximate metadata as a substitute.

When the gate fails because of a stale materialization wrapper, fix the wrapper before any new normal sync. Never use the old wrapper to "patch" `kb-source-metadata.md` and then rebuild the index manually as a normal path — that hides exactly the incompatibility the gate exists to surface.

If any layer fails, treat the workspace as stale or incompatible with the current operational version of the skill: block broad search and substantive triage; allow only a minimal diagnosis explaining what is missing; never compensate with manual reads of `kb-intelligence-validation.json`, direct SQLite access, an isolated `kb-source-metadata.md`, official XML, or a scan of `KbObjectsXml`; never run a normal sync via a stale wrapper as a "compatibility repair" step; never run the `.example.ps1` files as a substitute for the missing real local wrapper; never suggest `sync` followed by a separate manual index rebuild as the normal flow when `KbIntelligence` is adopted. Offer the user an update of the structure/wrappers/index using this workflow. The point of blocking is to make visible that a workspace still needs an operational update — especially in community settings with folders at different adoption stages.

---

## SETUP COMPLETION STATES

When closing a setup or handoff, use one explicit operational state — never infer status:

- `structure_created`: base folders/documents exist, but local wrappers, materialization, or the index have not been validated yet.
- `bootstrap_incomplete`: the structure exists, but the minimum local-wrapper layer for the adopted official flow is missing, or mandatory `KbIntelligence` compatibility is missing.
- `ready_for_first_materialization`: structure, documents, and minimum local wrappers were created/validated, with no sanitized placeholders left in effective wrapper configuration, but `KbObjectsXml` has not received an official materialization yet.
- `materialized_and_index_validated`: a successful official materialization happened and, when `KbIntelligence` is adopted, the derived index was regenerated/validated with `last_index_build_run_at >= last_xpz_materialization_run_at` and `inventory_validation_status=OK`; local declarative memory is clean (`declarative/timestamps=OK` in `Test-*KbSetupAudit.ps1`'s output).
- `wrappers_updated`: a folder already in production received the missing scripts the shared base expects; customized scripts were preserved or replaced with explicit approval; `KbObjectsXml`, `kb-source-metadata.md`, and `kb-intelligence.sqlite` are intact; local declarative memory is clean (`declarative/timestamps=OK`). No mandatory wrapper for the adopted scenario may remain `MISSING` without an explicit user decision — an unresolved `MISSING` wrapper means `bootstrap_incomplete`, never `wrappers_updated`.
- `methodology_update_pending`: a production folder with a working operational flow, but one or more scripts the current shared base expects have not been added yet, or local declarative memory (`AGENTS.md`/`README.md`) still carries literal materialization/index timestamps instead of pointers to the authoritative source (`declarative/timestamps=LITERAL_TIMESTAMP_DRIFT`). The existing scripts still work normally. Fix by adding the missing scripts via `update-local-bootstrap` and/or replacing literal timestamps with pointers (per `examples/AGENTS.md.example`) to reach `wrappers_updated`. Distinct from `bootstrap_incomplete`: here the folder already operates — only the canonical set or the declarative memory needs updating.

The audit can suggest `kb_objects_naming_pending` when it finds divergent corpus naming. Preserve that emitted token as diagnostic evidence; it is not a canonical closing state. Report the divergence, choose `methodology_update_pending` only when the workspace otherwise has a working flow, and otherwise choose the applicable blocked/incomplete state. The engine can also suggest `ready_for_first_materialization` as soon as the materialization timestamp is absent, before checking metadata-wrapper, inventory, or index-gate pendencies. Never declare that state from the suggestion alone: verify the stated structure and wrapper preconditions independently and report every remaining correction item.

Never use "setup done", "structure ready", or an equivalent phrase without saying which of these milestones was actually reached. Creating empty folders or writing initial local memory is not enough to declare the folder ready for normal sync or broad search. In the final handoff, use literally one of the canonical states above — never invent hybrid labels, free qualifiers, or variants such as "`wrappers_updated` complete", "almost `wrappers_updated`", "index ok with a pendency", "structure ready with a caveat", or equivalent.

---

## COMMUNICATION

- Reply in the user's language. Lead with the difference between the native KB folder and the KB workspace; whenever ambiguity is possible, always use the full phrase "KB workspace".
- **Show before asking.** When a question asks approval to write exact text (an allow rule, a read rule, a global instruction block), the target file's full path and that text, verbatim, must be on screen with the question, before the user answers. When the agent tool has a structured question tool with options (for example Claude Code's question prompt), keep using it for this question and for every other question, and never turn a question with options into a free-text question. If that tool can show a text block with an option (Claude Code: the option's `preview` field, single-select questions only), put the path and the exact text in a fenced block in the `preview` of every option that approves a write; do not rely on text printed before the call, which end-to-end runs showed can be skipped. Otherwise print them in a visible fenced block in the same message as the question, before it (with a question tool, as visible text in the same turn, right before the call). Text that appears only in another tool input, a permission prompt, or the agent's reasoning has not been shown, so a yes to a question that relies on it is not approval of that text.
- If the structure does not exist, say explicitly what is missing. In a well-scoped standard initial setup, prefer a short, objective close over narrating unnecessary exploration.
- If the compatibility gate fails, explain the failure as the workspace's operational staleness and offer an update before answering the underlying business question.
- When `AUDIT_REQUIRED` originated from missing/stale/inconsistent persistent metadata and the full audit plus gate then pass, differentiate in the handoff: `GATE_OK` releases the current task, but the folder still has a metadata pendency that should be fixed in the same session (via `Set-*KbSetupAuditTimestamp.ps1` or WORKFLOW step 34) to restore the fast path for future sessions; defer to another session only when the user explicitly refuses or defers.
- Never treat the native KB folder's structure as if it were the same thing as the KB workspace. When closing a successful initial setup, explicitly distinguish "structure ready" from "official snapshot not yet materialized", and recommend the supported next step: export an XPZ from the GeneXus IDE and use the **sync** workflow. If the native KB folder's existence was checked, state in the closing whether it exists/was reachable, or note it as an operational caveat.
- When closing update mode, the reply must include: each script's classification (EQUIVALENT/MISSING/CUSTOMIZED); the `KbObjectsXml` naming check per present directory, as a table or structured list with at least the columns `Directory`, `Real type found`, `Status` (conforming/divergent) — even when nothing diverges — plus `Expected canonical name` when something does diverge; the declared operational state; and the gate result when run.
- When closing update mode, report `sync/materialization`, `index/gate`, `index/semantics`, and `declarative/timestamps` as operational dimensions. When `Test-*KbSetupAudit.ps1` exists, prefer its consolidated operational lines over manual synthesis; never collapse those dimensions into "all good". Use the literal label `index/gate` for the structure/freshness gate dimension — never a variant like `index/freshness`, `freshness` alone, or `index` alone.
- Capture the real timestamp immediately before replying and use it in the response itself — never a placeholder, an invented time, a value reused from an earlier message, or one inferred from context.
- The final "operational state" must be exactly one of this workflow's canonical states — never append free qualifiers or phrase it as a new state.
- When `Test-*KbMetadataWrapper.ps1` exists, the final handoff must not cite `kb_name`/`source_guid` or classify `Get-*KbMetadata.ps1` without referencing that gate's evidence — isolated text inspection is not enough.
- If `Test-*KbObjectsXmlNaming.ps1` or `Test-*KbSetupAudit.ps1` reports `NAMING_DIVERGENT`/`naming/kb-objects: DIVERGENT`, include the explicit warning — regardless of the original question — naming which directories diverge and offering a separate sync/mapping correction workstream; never suppress that warning just because the business question was already answered.
- If local `AGENTS.md`/`README.md` record literal materialization/index timestamps, treat that as documentary drift even if the value still looks consistent with `kb-source-metadata.md` or the live gate; point out the divergence and offer to replace it with pointers before declaring the folder "all good".
- In `audit-setup`, when `Test-*KbSetupAudit.ps1` exists, the handoff must cite its consolidated blocks by name (`powershell/runtime`, `sync/materialization`, `naming/kb-objects`, `index/gate`, `index/semantics`, `metadata wrapper`, `declarative/timestamps`, `wrappers/inventory`, `suggested_operational_state`) instead of a manual synthesis, which is acceptable only when the wrapper is absent.
- After any minimum audit (`audit-setup`, the update block, or the precondition's full audit), the handoff must include the **consolidated correction plan** whenever at least one correctable item exists; if none exists, state explicitly "correction plan: no correctable item in this folder this round".
- The consolidated plan is mandatory **before** asking for approval on any write. If there is a mandatory/minimum item (e.g. re-stamping `setup_contract_signature_*` due to `AUDIT_REQUIRED`) alongside an already-detected consultative item (e.g. a cleanup reminder), both must appear in the same plan — never ask for approval on only the mandatory one while leaving the consultative one as a loose remark.
- The consolidated plan must be a structured list (table or numbered bullets) with at least: `Item`, `Evidence`, `Proposed action`, `Approval required` (yes/no), `Intent` (`update-local-bootstrap`/`fix-local-wrapper`/WORKFLOW step 34/out of scope).
- Compare the wrapper-reported `suggested_operational_state` against the canonical state the skill's own evidence supports; if they diverge, declare the correct canonical state and call out the divergence — never silently adopt the wrapper's suggestion without checking.
- On closing initial setup, recommend the **install** workflow for a full ecosystem audit beyond what this workflow itself checks.

---

## WORKFLOW

0. **XPZ catalog reminder (each session, when the workspace has a local override)**: when `scripts/gx-object-type-catalog.override.json` exists in the workspace, run `Test-MimirCatalogOverrideSessionReminder.ps1 -KbWorkspaceRoot <root> -AsJson` before assembling the final consolidated plan. With no override file there is nothing to remind: the script would only report `status=OK` with `noticeRequired=false`, so skip it. This is the same rule as **sync** step 7a. Read `status`, `noticeRequired`, `reminderRequired`, `cleanupRecommended`, `declaredUpstreamPending`, `effectiveUpstreamPending`, and the `pendingTypeNames`/`redundantTypeNames`/`divergentTypeNames` lists. If `reminderRequired=true`, show the message to the user before sync or materialization. If `cleanupRecommended=true`, include an explicit approved local cleanup offer in the consolidated plan (e.g. remove only the redundant entry in `redundantTypeNames`, or remove the file only when no entries remain), with `Approval required=yes` — never leave it as a loose remark or change it automatically.
1. Confirm whether the user means the native KB folder or the KB workspace.
2. If the native KB folder's path is not given, ask for it before finishing initial setup. When the user has none, only XPZ exports, follow [XPZ-only workspace](#xpz-only-workspace): steps 3, 6, and 7 then record that the workspace is XPZ-only instead of a native path.
3. If it is given, check existence/access when that is safe and cheap; if it does not exist or is inaccessible, do not write to or try to fix the native KB folder — just record the caveat in the handoff.
4. If the user gives no alternative names, assume the default subfolders.
5. If the user gives alternative names, record the mapping between real name and folder function in the workspace's `AGENTS.md` and, when it helps humans, also in `README.md`.
6. Record the confirmed native-KB-folder path and its read-only-for-agents rule in the workspace's `AGENTS.md`.
7. Mirror the native-KB-folder identification and read-only rule in the local `README.md`, in plain language. The workspace always has one: the scaffolder creates it from [`examples/README.md.example`](setup/examples/README.md.example); when it is missing in an existing workspace, create it from that example (rerunning the scaffolder does this without touching other files).

7a. If the workspace adopts `KbIntelligence`, the local `AGENTS.md` **must** include a `## Index triage` section with:
   - Routing: existence/location/technical-impact/relationship/short functional-investigation questions → the **find** workflow.
   - Gate: `Test-*KbIndexGate.ps1` as the sole entry point; a blocked gate blocks broad search, substantive triage, and XML scanning.
   - Explicit rule: never compensate a blocked gate with a manual SQLite/validation-JSON/`kb-source-metadata.md`/official-XML read.
   - Normative source: `KbObjectsXml` for confirmation only after the gate is released.

   This section is a prerequisite for declaring setup complete; without it, agents may route triage questions elsewhere instead of the **find** workflow, defeating the gate. In creation mode, the scaffolder writes it as part of `AGENTS.md` (from `examples/AGENTS.md.example`); in update mode, check and add it if missing (see step 8.g).

7b. Check whether the global structural trigger is present in the installed agent tools' global configuration. <!-- backend-parity: ignore --> This check covers the instruction files of Claude Code, Codex, and OpenCode only; other tools are not checked:
   - Identify the tool in use this session and check its global configuration file first, then the other installed tools' files.
   - Files to check (only if they exist): Claude Code's `.claude\CLAUDE.md`; Codex's `.codex\AGENTS.md`; OpenCode's `.config\opencode\AGENTS.md`, plus each file listed in `instructions[]` of `.config\opencode\opencode.json`/`.jsonc` when it exists — all under the user's profile directory. Check exactly these paths, one existence check per path; never search or list the whole user profile to find instruction files.
   - For each file found, check two levels: (1) does the file itself already contain a "KB workspace" section? If so, it is covered. (2) Does it reference another instructions file (e.g. an `@~/.codex/AGENTS.md` line or an `instructions` field)? If so, follow the reference and check that file too.
   - Only propose adding the section when neither the direct file nor a referenced one has it; add it to the already-referenced centralized file when one exists, otherwise to the tool's own configuration file.
   - Ask about this write as its own question, never bundled with other actions or approvals: show the file's full path and the exact block below, verbatim, on screen with the question, as COMMUNICATION, **Show before asking** describes, and write only after an explicit yes to that question. Approving a plan, a list of actions, or any other question is not approval of this write.
     ```
     ## KB workspace (GeneXus)

     When the working folder or any folder referenced in the conversation contains `KbObjectsXml/` or `KbIntelligence/`, invoke the `mimir-lite` skill's setup workflow once per session before any triage, query, or XML read — even if the local AGENTS.md does not say so explicitly.
     ```
   - When appending the block to an existing file, separate it from the preceding content with one blank line, and end the file with a newline.
   - This check is non-blocking: the user refusing or skipping it does not prevent closing setup.

7c. When recurring risk of off-convention text editing appears (e.g. mixed line endings in a file covered by `.gitattributes`), the agent may propose an optional reinforcement in the tool's global instructions file:
   - Treat this as a general editorial-hygiene recommendation, not a KB setup gate.
   - Check first whether the centralized global file already has an equivalent EOL-preservation instruction; propose adding it only if absent.
   - Ask about this write as its own question, as in 7b: show the global file's full path and the exact block below, explain the rule applies beyond GeneXus work, and write only after an explicit yes to that question:
     ```
     ## Text file line endings

     - In text files covered by `.gitattributes`, preserve the repository's expected `eol` when writing.
     - If there is a line-ending warning, a suspected mixed file, or an explicit repository `eol` policy, verify the saved file matches the expected format before concluding.
     ```
   - Also non-blocking.

8. Detect the workspace's operational context before any write:
   - **Creation mode**: folder missing, empty, with no materialized `KbObjectsXml` and no `kb-source-metadata.md` with real timestamps → run the CREATION BLOCK below (the scaffolder), deepen exploration only on a concrete blocker, then proceed to step 9.
   - **Update mode**: a folder with real history — any combination of materialized `KbObjectsXml`, `kb-source-metadata.md` with real timestamps, or a populated `kb-intelligence.sqlite` → run the UPDATE BLOCK below before step 9.
   - If the user's language suggests setup and the folder shows real-history signs, assume update mode, briefly tell the user the folder has history and that only what's missing will be added while preserving everything else, and confirm before writing.
   - If the user explicitly asks to wipe everything or recreate from scratch on a folder with real history, refuse, explain existing data will not be destroyed, and offer update mode as the only available path.

8.z Classify the operational intent within the detected context before choosing execution depth:
   - `audit-setup`: for a request to check, review, validate, diagnose, or ask "is everything OK"; prioritize evidence, classification, the **consolidated correction plan**, and a handoff recording the user's decision on that plan.
   - `fix-local-wrapper`: when the gate's or the update block's own evidence points at one stale wrapper, or the user explicitly asks to fix a local wrapper/script; prioritize editing the wrapper, rerunning the affected gate, then consolidating the final state.
   - `update-local-bootstrap`: for a folder with real history missing expected wrappers, required documentation sections, or part of the methodological bootstrap; prioritize adding those missing pieces. When whole wrappers, `README.md`, or `AGENTS.md` are missing, add them by rerunning the scaffolder after approval (8.s.3); missing sections inside an existing `AGENTS.md` are still added by hand.
   - For a generic audit request, start with `audit-setup`; if the audit finds a deterministic wrapper-fix case this skill mandates, explicitly switch to `fix-local-wrapper` and tell the user before writing: "the audit found a deterministic fix case; switching explicitly to `fix-local-wrapper` before writing."
   - Counts as a deterministic fix case for that switch: `Get-*KbMetadata.ps1` stale against the real `kb-source-metadata.md` format already covered by the current example, with `Test-*KbMetadataWrapper.ps1` blocking for that specific reason (mandatory flow defined in 8.a.iii); or any other wrapper blocked by `Test-*KbMetadataWrapper.ps1`/`Test-*KbIndexGate.ps1` for a known, unambiguous functional reason, whose current example already covers the real local data format — the fix must be local, observable in the wrapper itself, and not dependent on the user's editorial judgment.
   - Does **not** count, and the switch must not happen, when: the minimum audit has not finished (gate not yet run, 8.a scripts not all classified, or the `KbObjectsXml` naming check from 8.g2 not yet closed); the wrapper is CUSTOMIZED with a logic/parameter difference requiring an explicit user decision on what to preserve; or the gate's block has no unambiguous cause or depends on data outside the workspace to diagnose.
   - Interaction differs by intent: `audit-setup` closes with a diagnosis **and** the consolidated correction plan offered (executed in the same session after approval when correctable items exist); `fix-local-wrapper` closes with the gate rerun; `update-local-bootstrap` closes with a list of what was added.
   - When `audit-setup` finds correctable items, offer to execute the consolidated plan in the same session, transitioning into `fix-local-wrapper`/`update-local-bootstrap` per item and telling the user, without requiring a new generic "fix setup" request.
   - In `update-local-bootstrap`, when writing each new wrapper created from a canonical example, also update the local `AGENTS.md`'s `## Local wrappers` section to list it — never close out without that sync.

### CREATION BLOCK (scaffolder)

Run in creation mode, and in `update-local-bootstrap` when whole wrappers, `README.md`, or `AGENTS.md` are missing. The scaffolder `New-MimirKbWorkspace.ps1` builds the workspace in one run; it replaces hand-adapting the examples one by one.

8.s.1 **Ask only for what the scaffolder needs:**
   - the KB workspace folder (absolute path; created when missing);
   - the KB name: letters and digits only (`[A-Za-z0-9]+`). It becomes the wrapper prefix: each `<Verb>-Kb<Name>.example.ps1` is written as `scripts/<Verb>-<KbName>Kb<Name>.ps1` — KB name `SampleKb` gives `Test-SampleKbKbIndexGate.ps1`, and the doubled `Kb` is expected. Propose a name from the native KB folder or the KB's IDE name with other characters removed, and confirm it with the user;
   - the native KB folder (optional here; step 2 still requires it before setup closes), or that the user has none, which selects `-XpzOnly` (see [XPZ-only workspace](#xpz-only-workspace)).

8.s.2 **Run it** with the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`):
   ```text
   pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1" -WorkspaceRoot "<KbWorkspace>" -KbName <KbName> [-KbNativePath "<native-kb-folder>" | -XpzOnly]
   ```
   It creates the default folders (`scripts`, `Temp`, `IdeXpzExports`, `KbObjectsXml`, `KbIntelligence`); the `.gitignore` and `.gitkeep` files of step 10; one wrapper per example, with the shared-checkout path, the native KB folder (when given), and the prefixed sibling names already resolved; `README.md` and `AGENTS.md` from [`examples/README.md.example`](setup/examples/README.md.example) and `examples/AGENTS.md.example`, including the native-KB-folder rule (steps 6–7) and `## Index triage` (7a); and `kb-source-metadata.md` with empty values. Exit `2` with `BLOCK:` on stderr means invalid input (KB name, shared root, or workspace path): fix it and rerun. Alternative folder names are not supported; use the hand-adaptation fallback in [Reconstructing wrappers from the examples (fallback)](#reconstructing-wrappers-from-the-examples-fallback).

   This run is a direct shared-script call that comes before the allow rules by design (step 20a). Before it, tell the user that the agent tool may ask permission for this one call and that the allow rules are offered right after it (8.s.5).

8.s.3 **It never overwrites.** An existing file is reported `SKIPPED_EXISTING` and left byte-identical, so a rerun only adds what is missing. In a folder with real history, pass the KB name the existing wrappers already use as prefix, present what it will add and get approval first (8.b), list every wrapper it added in the existing `AGENTS.md`'s `## Local wrappers` section (8.z), and still classify every skipped wrapper in the UPDATE BLOCK — the scaffolder never fixes a stale wrapper.

8.s.4 **Relay the report:** the `CREATED` and `SKIPPED_EXISTING` lists and every `PENDING` line (native KB folder not given or not reachable; stable identity still empty). The `NEXT` lines list the follow-up commands.

8.s.5 **Continue with the steps that still apply**, in this order:
   - Allow rules (steps 20 and 20a), first: every later command runs a workspace wrapper or a shared script, so offer the workspace and shared-scripts rules before them, plus, when the tool has file-read rules, the read rules for the clone's `skills` folder and for each skill link in the tool's skills folder (step 20a), each shown verbatim on screen with the question, as COMMUNICATION, **Show before asking** describes (one question may cover all of them).
   - Stable identity (step 13): once the native KB folder is confirmed, run `Resolve-<KbName>KbIdentity.ps1 -UpdateMetadata`. If the folder was not given at creation, first record it in `AGENTS.md`, `README.md`, and that wrapper (placeholders `<NativeKbPath>` and `C:\path\to\native-kb`). In an XPZ-only workspace, skip this step: the first sync writes the identity.
   - Global trigger offer (7b), as its own question.
   - Git initialization offer (steps 11–12).
   - Every other edit to `AGENTS.md`, `README.md`, or other workspace files that this run makes.
   - `Test-<KbName>KbPowerShellRuntime.ps1`, then the setup audit `Test-<KbName>KbSetupAudit.ps1`; setup closes on that audit, not on the structure gate (see below).
   - Setup-audit timestamp (step 34) when closing on `ready_for_first_materialization`, as the last write of the run. An edit to a workspace file after it means rerunning the setup audit and the timestamp.
   - The closing message (item 7 of the **COMPLETION CHECKLIST**).

   Do not build the index during setup (step 22), and close with the canonical state `ready_for_first_materialization` only when its preconditions hold.

#### Structure gate before the first index build

`Test-<KbName>KbStructure.ps1` requires `KbIntelligence/kb-intelligence.sqlite`, which exists only after the first sync builds the index, and `Test-<KbName>KbIndexGate.ps1` runs the structure gate first. On a new workspace the structure check prints `PENDING: first index build pending: ...`, the index gate blocks with the reason `first index build pending: ...`, and the setup audit reports `index/gate: PENDING` with that reason; this is expected and is not a setup failure. Never create the file, or a placeholder for it, to make the gate pass. Setup closes on the setup audit (`Test-<KbName>KbSetupAudit.ps1`); the structure gate and the index gate pass only after the first sync and index build.

#### XPZ-only workspace

Some users have no native KB folder, only XPZ files exported from the GeneXus IDE (for example, the KB lives on another machine, or the XPZ is a public sample). Never invent a native path for them, and never leave the native-folder placeholders waiting for one:

- Ask once whether a native KB folder exists on this machine. An answer that there is none, or that the user only has the XPZ, selects this branch.
- Run the scaffolder with `-XpzOnly` instead of `-KbNativePath`. It writes `README.md` and `AGENTS.md` with the XPZ-only wording (no native path, no existence check), gives `Resolve-<KbName>KbIdentity.ps1` an empty native path, and reports the stable identity as pending on the first sync. Do not hand-edit `AGENTS.md` or `README.md` to say the same.
- Skip the identity resolver (step 13): with no native path it prints `NATIVE_KB_NOT_RECORDED`, exits `3`, and changes nothing. The first sync writes the stable-identity fields from the XPZ `Source` block, through the **sync** workflow's surgical metadata refresh.
- Before that sync, the setup audit's `metadata wrapper` line reports the identity fields as pending. In an XPZ-only workspace this is expected: state it in the handoff with its route (the first sync), not as a correction item of this workflow, and close on `ready_for_first_materialization` when its other preconditions hold.
- After the first sync, rerun the setup audit. When the XPZ `Source` block was empty or partial, report the identity fields still missing as a pendency: there is no native folder to resolve them from.
- The closing message says that the workspace is XPZ-only and that the KB identity comes from the first sync.
- When the user later records a native KB folder, update the identification sections of `AGENTS.md` and `README.md` and the wrapper's `$kbNativePath`, after approval, then run step 13.

### UPDATE BLOCK (run only in update mode)

Mandatory precondition: confirm step 7b ran this session before starting 8.a; if not, run it now first.

**8.a — Classify every expected script.** Inspect `scripts/` and classify each script the shared base expects into one of three classes. When the folder adopts `KbIntelligence`, the minimum canonical required scripts to classify are: `Test-*KbPowerShellRuntime.ps1`, `Update-*KbFromXpz.ps1`, `Test-*KbFullSnapshot.ps1`, `Test-*KbObjectsXmlNaming.ps1`, `Query-*KbIntelligence.ps1`, `Rebuild-*KbIntelligenceIndex.ps1`, `Test-*KbIndexGate.ps1`, `Get-*KbMetadata.ps1`, `Test-*KbMetadataWrapper.ps1`, `Test-*KbStructure.ps1`, and `Test-*KbSetupAudit.ps1`. This list is normative for 8.a.ii regardless of what the local `Test-*KbStructure.ps1` version happens to check — its checklist scope can be behind the current standard, but the obligation to classify all of these does not depend on the gate.

8.a.i **Parse validation is automatic.** `Test-*KbStructure.ps1` runs `[System.Management.Automation.Language.Parser]::ParseFile()` over each wrapper and adds `PARSE_ERROR` entries on failure. `GATE_OK` (which depends on `STRUCTURE_OK`) means every script parsed without errors — no extra manual run is needed for that. Caution: `GATE_OK`/`STRUCTURE_OK` prove absence of parse **errors**, not absence of parse **warnings** — the parser's second output parameter is never inspected by the gate. A confirmed parse warning (e.g. ambiguous interpolation like `"$field: $value"` instead of `"${field}: $value"`) is a real functional divergence and classifies the script as CUSTOMIZED in 8.a.ii even when the gate passed. `GATE_OK` proves parse cleanliness only — nothing more; it never anticipates or substitutes the EQUIVALENT/MISSING/CUSTOMIZED classification.

8.a.ii **Classify each script that passed 8.a.i:**
   - **MISSING**: expected script that does not exist locally yet.
   - **EQUIVALENT**: passed 8.a.i and its logic matches the corresponding example, including the `#requires -Version` directive when the canonical example declares one (a capitalization-only difference, e.g. `-version` vs `-Version`, is not a divergence; a version difference, e.g. `5.1` vs `7.4`, is). A local name carrying the KB prefix that the example lacks (e.g. `Test-SampleKbKbIndexGate.ps1` vs `Test-KbIndexGate.example.ps1`) is tolerated — but never the reverse: a name **missing** the KB prefix it should carry (e.g. `Test-KbIndexGate.ps1` instead of `Test-SampleKb2KbIndexGate.ps1`) is not the canonical wrapper: the canonical one is MISSING (`INVENTORY_GAPS`) even with identical content, and the fix is creating it under the canonical name. To be EQUIVALENT, no parameter may have a hardcoded default pointing at a file that does not exist on disk, and the inferred shared-engine path in the script body (typically `Join-Path $SharedSkillsRoot 'scripts\<name>.ps1'`) must point at a file that really exists in the shared engine — an engine path pointing nowhere classifies the script CUSTOMIZED. Specifically for `Test-*KbStructure.ps1`, it must emit `STRUCTURE_OK` via `Write-Output`, not `Write-Host` — the gate filters `$_ -is [string]` on output redirected through `*>&1`, and `Write-Host` emits an `InformationRecord` that silently breaks the gate. For any script, an absent parse warning is also required for EQUIVALENT; a confirmed parse warning makes it CUSTOMIZED. Exception: `Test-*KbPowerShellRuntime.ps1` may diverge from or omit `#requires -Version 7.4` when the canonical example does the same, so it can still emit `BLOCK:` on an older host.
   - **CUSTOMIZED**: exists with different logic, extra parameters, altered flow, or one of these mechanically-detected objective divergences: `requires_version_mismatch`; `missing_AsJson_passthrough` (the setup-audit and index-gate wrappers `Test-*KbSetupAudit.ps1`/`Test-*KbIndexGate.ps1` not forwarding `-AsJson`); `consumes_legacy_text_stdout` (e.g. `Update-*KbFromXpz.ps1` still treating `Sync-GeneXusXpzToXml.ps1`'s stdout as text instead of the JSON v1 contract via `ConvertFrom-Json`); `forwards_unknown_engine_param` (forwarding a parameter an advanced shared engine does not declare — a runtime binding error invisible to parsing/`STRUCTURE_OK`/`GATE_OK`); `unsafe_last_exitcode_after_ps1_engine` (`exit $LASTEXITCODE` after calling a PowerShell engine by variable); `shared_engine_unresolved` (an inferred engine path pointing at a nonexistent file); or `surface_mismatch` (the local wrapper **lost** a mandatory contract from the template — a missing/downgraded mandatory parameter, or a missing top-level `param()` when the template requires one). Reading the canonical example and identifying the concrete divergence is mandatory before classifying CUSTOMIZED — a complete local implementation is not, by itself, evidence of divergence, since the canonical example may also be a complete implementation. Without comparing the local script against the matching canonical example, do not classify it as either EQUIVALENT or CUSTOMIZED; record the comparison as pending.

8.a.iii **`Get-*KbMetadata.ps1`'s specific contract.** When `Test-*KbMetadataWrapper.ps1` exists, run it before classifying `Get-*KbMetadata.ps1` or mentioning `kb_name`/`source_guid` in the handoff. It returns `METADATA_WRAPPER_OK` when `Get-*KbMetadata.ps1` exposes `last_xpz_materialization_run_at`, `kb_name`, and `source_guid` that exist in `kb-source-metadata.md`; before OK, it must also confirm `kbGuid`/`versionGuid` are present and valid GUIDs and `kbName`/`versionName` are present — otherwise `METADATA_WRAPPER_INCOMPLETE`. `BLOCK: ...` classifies the wrapper CUSTOMIZED with the gate's evidence. `Get-KbMetadata.example.ps1` already covers the real documented `kb-source-metadata.md` format (including `name` under `## Source/Version` and `kb (GUID)` under `## Source`) — do not assume it only reads top-level `kb_name:`/`source_guid:` lines. If the gate blocks only because `kb_name`/`source_guid` exist in a documented Markdown table but the local wrapper returns them as absent, that is a stale wrapper against the current example — align it to the example without touching `kb-source-metadata.md`. Prefer the current example's EOL-robust reading pattern (`ReadAllLines` + `split('|')` + `.Trim()`) over a multiline regex ending in `\|$`, which is fragile against CRLF. Do not open an "adapt/keep/skip" question for this deterministic case: (1) align `Get-*KbMetadata.ps1` to the current example, preserving only genuinely-needed local customizations; (2) rerun `Test-*KbMetadataWrapper.ps1`; (3) only then move to handoff or final classification. `PENDING_DATA` for a genuinely-missing field is not, by itself, CUSTOMIZED; but it also does not prove methodological equivalence against the example (which still depends on 8.a.ii, including `#requires -Version`). Never conclude `Get-*KbMetadata.ps1 = EQUIVALENT` while also recording that `kb_name`/`source_guid` exist in metadata but come back `(absent)` — that is a contradiction. If `Test-*KbMetadataWrapper.ps1` is missing in a folder adopting `KbIntelligence`, classify it MISSING and offer to create it by rerunning the scaffolder (fallback: `Test-KbMetadataWrapper.example.ps1`).

8.b **For each MISSING script**: prepare creation — preferably by rerunning the scaffolder, which adds only missing files (8.s.3), otherwise from the matching example — present it to the user, and wait for explicit approval before writing. After writing, if the repository's `.gitattributes` sets an explicit EOL policy for `*.ps1`, verify the saved file matches it before declaring the script created and valid.

8.c **For each CUSTOMIZED script**: show the divergence objectively (which sections differ, which parameters were added, which logic changed) and present four options, waiting for an explicit decision before any write:
   - **A)** Keep the local version intact — no write.
   - **B)** Replace with the current example — the local customization is discarded.
   - **C)** Review and selectively incorporate — the user decides what from the example to bring in; the agent applies only what is explicitly confirmed.
   - **D)** Skip this script for now — no write; continue with the rest.

   Exception: this four-option rule does not apply to the deterministic `Get-*KbMetadata.ps1` case from 8.a.iii — align to the current example instead.
   Note on `surface_mismatch`: the A/B/C/D menu still applies, but option B (full replacement) is discouraged as the fix — the template uses placeholders (e.g. `SharedSkillsRoot`) and may deliberately drop `[ValidateSet]` to delegate validation to the engine, so recopying it whole would discard legitimate local defaults/customizations. The preferred fix realigns only the **surface** (re-adding the missing mandatory parameter, restoring a downgraded `Mandatory`, or reintroducing the top-level `param()`), preserving local defaults, never recopying the template wholesale.

   When two or more consecutive scripts get the same decision, the agent may ask whether to apply it to all remaining unreviewed CUSTOMIZED scripts, avoiding repetitive rounds; wait for the answer before proceeding.

8.d **Metadata write authority.** Never touch `kb-source-metadata.md` fields outside the current operation's authority. In update mode, this workflow may only write `last_setup_audit_run_at`/`setup_contract_signature_*` in its allowed cases (prefer `Set-*KbSetupAuditTimestamp.ps1`), or update stable-identity fields when the approved workstream is explicitly a reconciliation against the native KB; `last_xpz_materialization_run_at`, `source_xpz`, and `source_refresh_status` belong to the **sync** workflow. This covers both WORKFLOW step 34 and the precondition's `setup_ready_metadata_pending` sub-state, always preserving out-of-scope fields and local write-approval rules.

8.e **For an existing tool allowlist** (e.g. Claude Code's `.claude\settings.json`, where the agent tool in use has one): read current entries and insert only the patterns not already present; never remove or overwrite existing entries.

8.f **Verb-prefix drift.** For each local script whose role matches a canonical example, check whether the local verb prefix still matches the current example's. If the canonical example changed prefix since an earlier base version (e.g. `Update-KbIntelligenceIndex` → `Rebuild-KbIntelligenceIndex`), the local name should follow — even when the script's content is already fixed and functional. Evidence the divergence objectively (e.g. local `Update-SampleKbKbIntelligenceIndex.ps1` vs. canonical `Rebuild-KbIntelligenceIndex.example.ps1`); offer the rename; after an approved rename, update references to the old name in the daily-update wrapper's `IndexUpdateScriptPath` default, in `Test-KbStructure.ps1`'s expected-script list, in `Test-KbIndexGate.ps1` if it cites the old name, and in the agent tool's allowlist entries (e.g. `.claude\settings.json`). Wait for explicit approval before renaming or altering any script for this reason.

8.f.1 **`INVENTORY_RECOMMENDED_MISSING`.** Treat as an ergonomics recommendation, not a structural failure. Offer to create the listed wrappers by rerunning the scaffolder (fallback: the `.example.ps1` files) when the user wants fewer composite commands and ad hoc allowlist entries; if deferred, record the recommendation in the handoff without downgrading the operational state.

8.g **Index-triage section.** For a folder adopting `KbIntelligence`, check whether local `AGENTS.md` has `## Index triage` routing explicitly to the **find** workflow. If missing, evidence it to the user ("`AGENTS.md` has no index-triage section — existence/location/impact tasks may bypass the gate"), offer the standard block (same as creation mode, see 7a), and wait for explicit approval.

8.g2 **Mandatory before 8.h — `KbObjectsXml` naming check** (skip only if the folder does not exist or is completely empty):

   8.g2.0 Preferred mechanism: run the local wrapper `Test-*KbObjectsXmlNaming.ps1`, if it exists — it delegates to the shared, read-only, deterministic engine `../scripts/Test-MimirKbObjectsXmlNaming.ps1`. If missing or unavailable, follow 8.g2.i–8.g2.vii manually as a documented fallback and record the wrapper as MISSING in 8.a.

   8.g2.i Identify every directory present in `KbObjectsXml`; representative sampling is not an accepted substitute — every present directory must be covered.

   8.g2.ii For each directory, read at least one XML and extract the canonical type: for a focused or short audit limited to specific directories, sample directly inside each target directory rather than adding a separate exploratory step. For `Folder`, `Module`, `PackagedModule`, and `Attribute`, a single XML is sufficient evidence unless the first file read is corrupted, unreadable, or lacks the minimum classification data. If the root element is `<Attribute>`, the canonical type is `Attribute`; otherwise extract the GUID from `Object/@type` and map it via the effective catalog (`../scripts/gx-object-type-catalog.json` merged with the workspace's own local `scripts/gx-object-type-catalog.override.json` when present) — `../references/01a-catalog-and-empirical-patterns.md` remains the upstream editorial reference when a new type appears in the shared base. The GUID found in the XML is always the authoritative source; the directory name is a local convention and may diverge. A registered legacy orphan element (`Object/@type` matching `gxlegacy/<Element>`, no GUID, and the token in the `orphan` class of `../scripts/gx-legacy-export-element-registry.json` — today only `Report` → `materializedFolderName`) maps through that registry rather than being treated as unknown; a legacy `<Menubar>` materializes as the modern `Menubar` type (`equivalent`), not as an orphan. Note: `Build-KbIntelligenceIndex.py` already maps by GUID for modern objects, so the index's `object_type` is correct regardless of folder name — this check exists for human readability/consistency of the corpus. A registered legacy orphan is skipped by the indexer (not indexed, no `object_type`) and reported in `legacy_orphan_directories_skipped`; a mis-named folder with modern content is still flagged.

   8.g2.iii If a directory's name diverges from the canonical name expected for the GUID found, state the divergence explicitly: which directory, which real type, what the canonical name would be, and the likely cause when known. An unresolved naming divergence blocks declaring `wrappers_updated`/`materialized_and_index_validated` as a clean final state until the official snapshot is corrected through the supported workflow and rechecked. If the user defers correction, report the pendency without claiming a clean state.

   8.g2.iv Before proposing a sync/mapping investigation, check whether local `AGENTS.md` references the directory names at risk, and whether a `KbIntelligence` index exists (its `object_type` will already be correct since the engine reads the GUID, but its `path` field will reflect the old folder name until the next rebuild).

   8.g2.v Do not manually rename directories in the official corpus, even with approval: it is read-only for agents and is maintained by the **sync** workflow. Report the type mismatch and ask the user whether to investigate the sync input/mapping or open a separate shared-engine correction workstream. Neither diagnostic path authorizes changing the snapshot in place.

   8.g2.vi Once a corrected official snapshot has been materialized through **sync**, recheck the naming and rebuild/validate the derived index through that workflow; its `path` field must reflect the new official paths. Update old-name references in local `AGENTS.md` only after observing the corrected official paths and obtaining the required approval.

   8.g2.vii **Stopping rule.** If `Test-*KbStructure.ps1` returned `STRUCTURE_OK`, `Test-*KbIndexGate.ps1` returned `GATE_OK`, and the naming check concluded every present directory as conforming or divergent based on its own local XML, consider the naming check closed — do not keep searching external catalogs, paths outside the workspace, or extra samples just to reconfirm already-identified types. This closes 8.g2 only, not the full `audit-setup` diagnosis — that still requires every canonical mandatory wrapper for the adopted scenario classified in 8.a, with none left `MISSING` without an explicit user decision. A failed intermediate glob/listing attempt does not license widening scope — just switch to a simpler, direct XML read of the directory under test. Exception: when the XML's own structure already settles the type (e.g. a root `<Attribute>`), that is enough — no `Object/@type` lookup or external check is required to close this out. If a real divergence exists, report it and route correction through the supported sync/mapping workstream; if not, move on to 8.g3 and continue the audit/handoff without extra exploration.

8.g3 **Consolidating the handoff via `Test-*KbSetupAudit.ps1`** (before 8.h when the intent is `audit-setup`): check whether it exists in the workspace's `scripts`. If it does, run it and reproduce **every** `wrappers/inventory:` line exactly as emitted (if there are two such lines, reproduce both — never summarize, omit, or paraphrase them); cite its consolidated blocks by name (`powershell/runtime`, `sync/materialization`, `naming/kb-objects`, `index/gate`, `index/semantics`, `metadata wrapper`, `declarative/timestamps`, `wrappers/inventory`, `suggested_operational_state`); compare `suggested_operational_state` against the canonical state the objective evidence supports and declare the correct one if they diverge — never adopt the wrapper's suggestion unchecked. Its output consolidates dimensions but never replaces individual script classification — 8.a.ii and the 8.h table remain mandatory even when it exists and passes. Limit: `metadata wrapper: OK` and `wrappers/inventory: INVENTORY_OK` show the metadata reader is complete and the current inventory reports no gaps/customizations — they do **not** prove `Source/kb (GUID)`, `Source/Version/guid`, `username`, or `UNCPath` still match the current native KB; that requires a dedicated resolver/updater workstream. If it does not exist, synthesize the applicable operational dimensions manually per 8.h and record the wrapper as MISSING there.

   Handling per `wrappers/inventory` token, all mandatory:
   - `INVENTORY_GAPS: <list>` → classify each listed wrapper MISSING in 8.h and offer `update-local-bootstrap` immediately — never treat as informative or deferrable. A state suggestion of `methodology_update_pending` is expected only after earlier runtime, missing-materialization, and naming checks do not take precedence; a different suggestion never cancels the inventory gap.
   - `INVENTORY_CUSTOMIZED: <list>` → classify CUSTOMIZED; per reason: `requires_version_mismatch` → align `#requires -Version` to the example (except the documented runtime-wrapper exception); `missing_AsJson_passthrough` (setup-audit and index-gate wrappers) → realign the wrapper to forward `-AsJson`, since callers that read the audit or the gate as a structured verdict need that contract; `forwards_unknown_engine_param` → realign the forwarded parameter to the engine's real surface; `shared_engine_unresolved` → fix the engine path or update the shared base; `surface_mismatch` → realign only the surface to the template (re-add the missing mandatory, restore a downgraded `Mandatory`, or reintroduce the top-level `param()`), preserving local defaults, never recopying the template whole. `GATE_OK`/`STRUCTURE_OK`/functional execution never neutralize this classification. The informative-only `INVENTORY_ENGINE_DIAGNOSTIC` (canonical shared engine missing/parse-broken — infrastructure of the shared skill base, not a local deviation) and the consultative `INVENTORY_SURFACE_ADVISORY` (optional reduction/`ValidateSet` narrowing) never block the state.
   - `INVENTORY_RECOMMENDED_MISSING: <list>` → offer to create the recommended wrappers by rerunning the scaffolder (fallback: the `.example.ps1` files); consultative, does not block `materialized_and_index_validated` when other dimensions are OK, but must still appear in the handoff.
   - `INVENTORY_SURFACE_ADVISORY: <list>` → consultative surface drift by optional reduction only (`optional_param_missing`, `validateset_reduced`, `optional_promoted_to_mandatory`, `extra_mandatory_added`, `no_param_block` with an optional-only template) — deliberately outside the four blocking tokens, never blocks `materialized_and_index_validated`; a parallel loss of a mandatory contract on the same wrapper surfaces separately as `INVENTORY_CUSTOMIZED (reason=surface_mismatch)` — both may legitimately appear together. Reproduce the line and offer the surface realignment (preserving local defaults) when the user wants to reduce drift; if deferred, record the recommendation without downgrading the state.
   - Multiple tokens can appear together as separate `wrappers/inventory:` lines — handle each independently; ignoring any line invalidates the 8.h table.
   - `declarative/timestamps: LITERAL_TIMESTAMP_DRIFT` → local `AGENTS.md`/`README.md` carry literal materialization/index timestamps; this drift remains a correction item even if the state suggestion is selected earlier by runtime, missing materialization, or naming. The fix is **not** updating the literal values — it is removing them and pointing at the authoritative sources instead, per `examples/AGENTS.md.example`: (1) reproduce `declarative/timestamps.evidence`; (2) propose the pointer-based rewrite to the user; (3) wait for explicit approval; (4) execute via `update-local-bootstrap`. Blocks `wrappers_updated`/`materialized_and_index_validated` while the drift persists. Runbook: locate the literals, replace with pointers to `kb-source-metadata.md` (via `Get-*KbMetadata.ps1`), `Query-*KbIntelligence.ps1 -Query index-metadata`, and `Test-*KbIndexGate.ps1`'s `GATE_OK`; rerun `Test-*KbSetupAudit.ps1`; if `suggested_operational_state` returns to a clean canonical state, run `Set-*KbSetupAuditTimestamp.ps1` with the real audit timestamp; rerun `Test-*KbSetupFreshness.ps1` (expect `GATE_ONLY`) and `Test-*KbIndexGate.ps1` (expect `GATE_OK`).

8.g4 **Unrestricted external-tool routing rule in `AGENTS.md`.** If local `AGENTS.md` instructs invoking an external GeneXus-modeling tool "for any GeneXus task" without restricting the scope, evidence the unnecessary-load risk to the user and offer to replace it with a scoped rule (that tool for modeling/analysis/structure queries only; anything covered by a more specific workflow of this skill follows that workflow instead). Wait for explicit approval. If the rule is already scoped correctly, state so without proposing a change. Applies to any workspace referencing such a tool in local `AGENTS.md`, regardless of `KbIntelligence` adoption.

8.h **Close the update block.** Declare the operational state matching the evidence actually closed, and present the script table with columns `Script | Class (EQUIVALENT/MISSING/CUSTOMIZED) | Action`. The table must include **every** expected script, not only the ones needing action — EQUIVALENT scripts get a row too. A list of "scripts to update"/"scripts to create"/"points of attention" never substitutes for this table; both can coexist, but the table is mandatory regardless. `RECOMMENDED_MISSING` wrappers appear in a separate consultative block or as MISSING/recommended, making clear the isolated absence does not block a clean state. Parse is already covered by the gate — no need to repeat it in the table, but classification remains mandatory regardless. List explicitly: scripts added, scripts kept (EQUIVALENT), scripts replaced with approval, and scripts skipped.

   Align local `AGENTS.md`'s `## Operational state` section to the pointer format of `examples/AGENTS.md.example` (no fixed canonical state, no literal materialization/index timestamps) — the workspace's real canonical state comes from `Test-*KbSetupAudit.ps1`'s `suggested_operational_state` and the specific gates this session, never from static markdown text. If `AGENTS.md` still mirrors `materialized_and_index_validated` or another fixed state/literal timestamp while objective evidence diverges, treat it as documentary drift and fix it via pointers before closing clean — never replace one fixed state with another. Also check whether `## Local wrappers` lists every script currently in `scripts/` with correct names/roles, proposing an update if stale. Finally, compare the overall `AGENTS.md` structure against `examples/AGENTS.md.example`; if canonical sections are missing beyond the ones already checked (`## Index triage`, `## Local wrappers`), propose adding them before declaring setup complete.

   Additional rules: when local `README.md`/`AGENTS.md` record a fixed canonical operational state or literal timestamps as a mirror, treat as documentary drift — fix via pointers, never by harmonizing literal values between markdown files or swapping one fixed state for another. `GATE_OK`/`STRUCTURE_OK` alone never prove the declarative memory is drift-free. An unresolved (or undiscarded) `KbObjectsXml` naming divergence blocks declaring `wrappers_updated`/`materialized_and_index_validated` clean. `AGENTS.md` is normative agent memory — active wrapper list, gate rules, routing; the canonical state and operational freshness live in the consolidated audit and the authoritative sources, never in static `## Operational state` text. `README.md` is the human usage guide — how to operate the folder, which automations the human runs directly. This distinction decides whether one or both files need updating. Mandatory trigger for `AGENTS.md`: whenever any wrapper changes class this round (an MISSING resolved, a CUSTOMIZED fixed, a new wrapper added), update `## Local wrappers` and the pointer-format `## Operational state` section — this is not an optional proposal, it is mandatory before declaring any completion state. Mandatory trigger for `README.md`: whenever the change alters the automations exposed directly to the human. The final handoff must list `Test-*KbMetadataWrapper.ps1`'s result explicitly when it exists (e.g. `Test-<Kb>KbMetadataWrapper.ps1: METADATA_WRAPPER_OK` or `metadata wrapper: OK`) rather than inferring it from `suggested_operational_state: materialized_and_index_validated`. `declarative/timestamps` is the primary deterministic evidence for declarative-memory drift; a `LITERAL_TIMESTAMP_DRIFT` result blocks `wrappers_updated`/`materialized_and_index_validated` while it persists — `GATE_OK`/`STRUCTURE_OK` never neutralize it.

--- END OF UPDATE BLOCK ---

--- NAMING-CHECK BLOCK (standalone, outside update mode) ---

When triggered standalone, follow the same 8.g2.i–8.g2.vii steps. The only difference is there is no update-mode completion state to declare — the output is just the naming result per directory (conforming/divergent) and, if divergent, the supported sync/mapping follow-up from 8.g2.v.

--- END OF NAMING-CHECK BLOCK ---

9. Validate the setup structure: `scripts`, `Temp`, `IdeXpzExports`, `KbObjectsXml`, and `KbIntelligence` when adopted (the scaffolder creates all five).
10. The scaffolder writes the root `.gitignore` and the `.gitkeep` files. When building by hand, create the `.gitignore` when the workspace is Git-versioned or the user accepts preparing for future versioning: cover `Temp/*`, `KbIntelligence/kb-intelligence.sqlite`, `KbIntelligence/kb-intelligence-validation.json`, and `IdeXpzExports/*`; create the matching `.gitkeep` in each `folder/*`-covered folder in the same step; never reference a `.gitkeep` you did not create; never ignore `KbObjectsXml`.
11. If not yet Git-versioned, the agent may offer to initialize local Git versioning; never run `git init` without explicit approval.
12. If the user accepts and Git is not functional locally, offer to install or guide the install first.
13. If `kb-source-metadata.md` does not exist, create it with the nominal `last_xpz_materialization_run_at` field, matching the shared engine's format (the scaffolder does this). Once the native KB folder is confirmed, run `Resolve-*KbIdentity.ps1 -UpdateMetadata` (engine `Resolve-GeneXusKbIdentity.ps1`) to fill the stable-identity fields; if resolution blocks, create at most partial metadata and declare the stable-identity fields pending. In an XPZ-only workspace, the first sync fills them instead (see [XPZ-only workspace](#xpz-only-workspace)). If `kb-source-metadata.md` already exists, do not touch fields outside the current authority — use the approved identity-reconciliation workstream via `Update-MimirKbSourceMetadataIdentity.ps1` for missing/divergent fields, preserving real operational timestamps the freshness gate depends on.
14. External memory: follow the core rule in [`SKILL.md`](../SKILL.md#core-rules-apply-to-every-workflow) on saving anything to a memory tool outside the workspace (ask first, naming what and where). The workspace's own `AGENTS.md` and `README.md` are the memory layer for setup.
15. Explain each folder's role (per RESPONSIBILITIES above).
16. If `KbObjectsXml` does not exist yet, treat the corpus as not yet materialized.
17. Setup does not create generated-object workstreams or import-package folders; those activities are outside Mimir Lite's supported workflow.
18. If `IdeXpzExports` is missing and the flow depends on `XPZ`, ask for the intended path or create the default folder when repository policy allows.
19. If `scripts` exists with no minimum local wrappers, rerun the scaffolder per the "Wrapper bootstrap when `scripts` has none" list in RESPONSIBILITIES.
20. If the agent tool in use has a command allowlist or equivalent permission configuration, then whenever a local `.ps1` wrapper expected by the shared base is created or confirmed — any mandatory or adopted recommended wrapper — offer to register the matching allow rule in that configuration. Ask before writing, as in 20a: show the settings file's full path and the exact rule or rules, verbatim, on screen with the question, as COMMUNICATION, **Show before asking** describes, and write only after an explicit yes. One question may cover this rule and the 20a rules when it shows each verbatim; approving a plan or another question is not approval of this write. This covers the core gates/readers (`Test-*KbIndexGate.ps1`, `Get-*KbMetadata.ps1`, `Test-*KbMetadataWrapper.ps1`, `Test-*KbStructure.ps1`), materialization wrappers, and the identity resolver. Register each script by its real local name (not the sanitized example name), or with one rule scoped to the workspace's `scripts` folder when the tool's rules support a path prefix, always with an absolute, literal path matching the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`). Treat this as part of bootstrap/update, not a manual follow-up — ask it before declaring the completion state. For a tool with no allowlist, this step is not applicable: it must not block any completion state, and the user handles any prompt through that tool's own permission flow.

    Tool note: Claude Code. One rule scoped to the workspace's `scripts` folder covers every wrapper run with the canonical command form: add `Bash(pwsh -NoProfile -File "<KbWorkspace>/scripts/*)` to `permissions.allow` in the workspace's `.claude/settings.json` (e.g. `Bash(pwsh -NoProfile -File "C:/KBs/SampleKbWorkspace/scripts/*)`). Claude Code matches the text before the `*` literally, so the rule only covers commands spelled exactly in the canonical form (literal absolute path, forward slashes, double quotes); never write `..` in a command path, since the rule would still match it. When the user has enabled Claude Code's PowerShell tool, add the same rule with the `PowerShell(...)` prefix: `PowerShell(pwsh -NoProfile -File "<KbWorkspace>/scripts/*)`. Create the file with a minimal structure if it does not exist; if it does, read current entries and insert only the missing ones. These project settings apply only to a session started in the KB workspace folder, so the closing message tells the user to start the agent tool there for KB work. Rule syntax: <https://code.claude.com/docs/en/permissions>.

20a. Some steps call a shared script directly, with no local wrapper: the catalog reminder (step 0, when it runs), the sync pre-scan `Get-GeneXusXpzObjectInventory.ps1` (**sync** workflow step 7b), and any direct engine call that passes `-RepoRoot` to resolve the workspace's own folders. When the agent tool in use has a command allowlist, check that it has an entry covering the shared base's `scripts` folder, using an absolute, literal path — never a placeholder. If missing, offer to add it right after the scaffolder (8.s.5), before the first of these calls, and wait for explicit approval. The scaffolder (`<mimir-lite-root>/skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1`, 8.s.2) is also a direct shared-script call, and this rule would match it, but it runs once before this question by design: it creates the workspace whose settings file holds the allow rules, and those rules apply only to a session started in the workspace folder, so writing the rule first would not spare the scaffolder's permission prompt. Treat this as bootstrap when a direct engine call is needed for an approved read, sync, index, or identity workflow, or as an update when the direct engine call is new to this folder. When the agent tool also has file-read permission rules, check in the same way for a read rule covering the clone's `skills` folder (`<mimir-lite-root>/skills`, both skills): the agent reads the skill's own workflow and reference files there, outside the KB workspace folder, so a session with default permissions asks approval for each read. Also check for one read rule for each skill link that exists in the tool's own skills folder (`mimir-lite`, and `mimir-delegate` when it is linked there): the agent reads the skill through its link path, and the tool matches the path as requested without resolving the link, so the clone-path rule alone does not cover those reads (seen in an end-to-end run). Keep the clone-path rule for reads through `<mimir-lite-root>`. Offer the read rules in the same question as the shared-scripts rule, shown verbatim (COMMUNICATION, **Show before asking**), write them only after an explicit yes, and insert each one only when missing (8.e). Write all of these rules only to the KB workspace's settings, never to user-level settings. For a tool with no allowlist, this step is not applicable.

    Tool note: Claude Code. The entry is `Bash(pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/*)` in `.claude/settings.json` (e.g. `Bash(pwsh -NoProfile -File "C:/Tools/mimir-lite/skills/mimir-lite/scripts/*)`), plus the same rule with the `PowerShell(...)` prefix when the PowerShell tool is enabled; create the file with that entry if it does not exist. The read rules go in the same `permissions.allow` list. The clone-path rule is `Read(//<root>/skills/**)`, where `//` starts an absolute path from the filesystem root and `<root>` is `<mimir-lite-root>` in POSIX form without its leading slash. On Windows, Claude Code normalizes `C:\Tools\mimir-lite` to `/c/Tools/mimir-lite` (lowercase drive letter, forward slashes), so a clone there gives `Read(//c/Tools/mimir-lite/skills/**)`; on Linux or macOS, a clone at `/home/user/mimir-lite` gives `Read(//home/user/mimir-lite/skills/**)`. A single leading `/` is relative to the settings file's project, not absolute. For the skill links under `~/.claude/skills`, add `Read(~/.claude/skills/mimir-lite/**)`, and `Read(~/.claude/skills/mimir-delegate/**)` when that link exists; `~/` is Claude Code's documented home-relative form, so these two rules need no literal path. Claude Code also applies `Read` rules, best effort, to Grep and Glob. Do not offer `permissions.additionalDirectories` instead: it opens the whole clone, and in `acceptEdits` mode it auto-approves edits there.

21. If `KbIntelligence` is missing, guide creating it as the derived-artifact folder before installing index wrappers.
22. If `KbObjectsXml` has no materialized snapshot yet, do not attempt to generate `kb-intelligence.sqlite` — only prepare the folder and local wrappers.
23. If the folder adopts `KbIntelligence`, validate the operational compatibility gate before allowing broad search or substantive triage.
24. If the gate fails, offer to update the workspace/wrappers/index — never answer the underlying business question via a manual fallback.
25. Before declaring setup complete, validate that the minimum local-wrapper layer in `scripts` exists for the workspace's adopted official flow.
26. When local wrappers are derived from `.example.ps1` files, validate they keep no sanitized placeholders in effective configuration before classifying them as existing minimum wrappers. The scaffolder resolves the shared-root placeholder always and the native-KB placeholder when `-KbNativePath` is given (to an empty value with `-XpzOnly`); its `PENDING` lines name what is left.
27. Mimir Lite setup prepares the read, sync, index, and identity workspace only; it does not generate, import, build, or deploy GeneXus objects.

28. If the folder/document structure is ready but the minimum local-wrapper layer is missing or still holds sanitized placeholders in effective configuration, report this as "partial structure"/"incomplete bootstrap" — never as setup complete.
29. On concluding initial setup, state explicitly that the structure is ready but `KbObjectsXml` has not been materialized yet, and that the structure gate and the index gate pass only after the first sync builds the index.
30. If the first official materialization happens after setup, update or clear the provisional local memory from setup that still says "not materialized"/"waiting for the first XPZ" or equivalent.
31. On concluding initial setup, explain that the supported next action is exporting an XPZ from the GeneXus IDE and using the **sync** workflow, with the agent tool started in the KB workspace folder so the allow rules written there apply (step 20). When this session was not opened in the KB workspace folder, say that permission prompts continue in this session and that the allow rules apply once the agent tool is reopened in `<KbWorkspace>`; only when the session was opened in that folder, say that the scripts now run without prompts.
32. On closing initial setup, recommend the **install** workflow by name, in a sentence of its own, for a full ecosystem audit beyond what this workflow itself checks. When the install audit already ran in this session, say so, give its result, and recommend running the **install** workflow again after every `git pull` of the shared checkout.
33. Do not propose MSBuild-based export or local object-generation alternatives; the supported input is a user-exported XPZ from the GeneXus IDE, consumed by the **sync** workflow.
34. **Setup-audit metadata write.** On declaring any successful canonical completion state (`ready_for_first_materialization`, `materialized_and_index_validated`, or `wrappers_updated`), write `last_setup_audit_run_at` with the successful audit's timestamp and `setup_contract_signature_version`/`setup_contract_signature_hash` with the current setup contract signature, in `kb-source-metadata.md`'s frontmatter; never write them for `bootstrap_incomplete` or `methodology_update_pending`. The timestamp must be ISO 8601 with a timezone offset, matching `last_xpz_materialization_run_at`'s format. Prefer `Set-*KbSetupAuditTimestamp.ps1` (engine `../scripts/Set-MimirSetupAuditTimestamp.ps1`), which updates only these fields and preserves the rest of the file; manual editing only when the wrapper is missing and the approved workstream allows local writes. These fields record a successful setup audit; they never substitute for or mirror `last_xpz_materialization_run_at`/`last_index_build_run_at`. The precondition's `setup_ready_metadata_pending` sub-state uses this same write once the full audit just passed with a compatible successful canonical state — never default-deferred to another session. This write is the last write of the setup run: make every edit to `AGENTS.md`, `README.md`, and other workspace files first, then run the setup audit, then write the timestamp; when a workspace file changes after the timestamp, rerun the audit and this write.

---

## SHORT EXAMPLE OF MATERIALIZED STRUCTURE

```text
SampleKbWorkspace/
  AGENTS.md
  README.md
  kb-source-metadata.md
  scripts/
    Update-SampleKbKbFromXpz.ps1
    Test-SampleKbKbFullSnapshot.ps1
    Test-SampleKbKbObjectsXmlNaming.ps1
    Query-SampleKbKbIntelligence.ps1
    Rebuild-SampleKbKbIntelligenceIndex.ps1
    Test-SampleKbKbIndexGate.ps1
    Get-SampleKbKbMetadata.ps1
    Test-SampleKbKbMetadataWrapper.ps1
    Test-SampleKbKbStructure.ps1
    ...                                  (the other wrappers the scaffolder writes)
  Temp/
  IdeXpzExports/
    KBCompleta_20260413.xpz
    processado_PacoteExemplo_20260413.xpz
  KbObjectsXml/
    Transaction/
      Cliente.xml
      Pedido.xml
    Procedure/
      GeraBoleto.xml
    WebPanel/
      WPClienteConsulta.xml
  KbIntelligence/
    kb-intelligence.sqlite
    kb-intelligence-validation.json
```

---

## CONSTRAINTS

- NEVER assume a directory name under `KbObjectsXml` matches the correct GeneXus type without checking the GUID in at least one XML from it; the directory name is a local convention and may diverge from the real type.
- NEVER manually rename directories under `KbObjectsXml`, even with approval; report a naming divergence and route its correction through the **sync** workflow or an explicitly scoped shared-engine fix, then verify the new official snapshot and derived index.
- NEVER declare a completion state in update mode (step 8.h) without having run the naming check (8.g2.i–8.g2.vii) when `KbObjectsXml` has XML-holding directories — mandatory even when every script is EQUIVALENT and no other fix is needed.
- NEVER confuse the native KB folder with the KB workspace. NEVER write to the native KB folder — it is read-only for agents, save for controlled operational reads when genuinely required. NEVER write manually into `KbObjectsXml`.
- NEVER treat `IdeXpzExports` as an output area for packages or generated XMLs. NEVER apply the `processado_` prefix before clear success processing the `.xpz`.
- NEVER use a GUID as the primary folder/file name of the materialized corpus, nor `guid`/`parentGuid`/`parentType`/`moduleGuid` as the KB workspace's primary navigation axis.
- NEVER treat `KbIntelligence` as a normative source — the index is derived from `KbObjectsXml`. NEVER generate `kb-intelligence.sqlite` before an official materialized snapshot exists in `KbObjectsXml`.
- NEVER create a new script when the official flow already exists in the skill or in `scripts/` of this repository. NEVER assume a missing `KbObjectsXml` means an empty snapshot — it means the structure has not been materialized yet. NEVER hide from the user that a default structure was assumed for lack of alternative names.
- NEVER overwrite an existing `scripts/` script without first comparing it to the matching example, objectively evidencing the divergence to the user, and getting explicit approval to replace it.
- NEVER write `kb-source-metadata.md` fields outside the current operation's authority; after the first official materialization, `last_xpz_materialization_run_at`/`source_xpz`/`source_refresh_status` still belong only to the **sync** workflow, while this workflow may only write `last_setup_audit_run_at`/`setup_contract_signature_*` in the allowed cases, or reconcile stable identity when that is the explicitly approved workstream.
- NEVER propose a new `kb-source-metadata.md` field to track index state/freshness — `last_index_build_run_at` in the SQLite `metadata` table is already the authoritative source; a markdown mirror would be redundant and break the single source of truth.
- NEVER write literal `last_xpz_materialization_run_at`/`last_index_build_run_at` timestamps into `AGENTS.md`/`README.md` — those fields live only in their authoritative sources; local files must use pointers instead. The detector for this drift is the `declarative/timestamps` line of `Test-*KbSetupAudit.ps1`.
- NEVER classify a folder `bootstrap_incomplete` just because a newly-added script is missing when the existing scripts already work and the folder has real usage history — that is an update-mode case, not incomplete bootstrap. NEVER confuse `bootstrap_incomplete` (no functional minimum-wrapper layer for the adopted flow) with `methodology_update_pending` (working folder whose wrappers function, but the current shared base added scripts not yet incorporated) — they are distinct and need distinct handling.
- NEVER create `KbIntelligence/kb-intelligence.sqlite`, or a placeholder for it, to make the structure gate pass before the first index build; setup closes on the setup audit, and the structure and index gates pass only after the first sync.
- NEVER hand-adapt the examples one by one in creation mode when the scaffolder can produce the workspace; hand adaptation is the fallback for a customized workspace or a scaffolder that cannot run.
- NEVER assume creation mode in a folder with real history, whatever the user asks. NEVER offer recreating from scratch as an option there — update mode is the only available path.
- NEVER treat an index-regeneration wrapper's "file not found" failure on a default validation-cases path as an absence of validation cases, nor propose workarounds like an empty path or another KB's cases — treat it as a broken hardcoded default (classify CUSTOMIZED), evidence it, and offer the fix (make the parameter optional with no fixed default).
- NEVER ignore a verb-prefix divergence between a local script and its canonical example when the example's prefix changed since an earlier base version. Fixing the content without aligning the name hides the divergence from `Test-KbStructure` and leaves the folder invisibly stale to the gate.
- NEVER treat a state declared in local `AGENTS.md` (e.g. `materialized_and_index_validated`) as absolute truth when objective inspection shows missing scripts, stale wrappers, or a broken gate — `AGENTS.md` is auxiliary memory and can be outdated; structural evidence (script presence/absence, gate result, `declarative/timestamps`) prevails. On any successful update, align `## Operational state` to the pointer format of `examples/AGENTS.md.example` — the real canonical state comes from the consolidated audit and specific gates, never from fixed markdown text.
- NEVER leave a `KbIntelligence`-adopting workspace without the `## Index triage` section in local `AGENTS.md` — its absence lets a generic external-tool-routing rule capture existence/location/impact questions instead of the **find** workflow, defeating the gate. Verify and ensure this section in both creation mode and update mode.
- NEVER use a placeholder, fixed, reused, or clock-independent timestamp in the final handoff — it invalidates the diagnosis's formal compliance.
- NEVER classify `Get-*KbMetadata.ps1` as EQUIVALENT when `kb-source-metadata.md` has `kb_name`/`source_guid` in the documented format but the wrapper returns them as absent — that is a functional wrapper failure, not an informative caveat. NEVER open an A/B/C/D question, an equivalent poll, or a preference request for that specific deterministic case before aligning the wrapper to the current example and rerunning the gate.
- NEVER declare a freshly created or rewritten `.ps1` wrapper valid when the repository's `.gitattributes` sets an explicit EOL policy for `*.ps1` and the saved file does not match it — EOL normalization is part of closing out the creation/fix, not later rework.
- NEVER ignore `INVENTORY_CUSTOMIZED` in a `wrappers/inventory:` line — every listed script must appear in the 8.h table with its mandated classification and action (see 8.g3 for the per-reason fix, including `requires_version_mismatch`, `missing_AsJson_passthrough`, `consumes_legacy_text_stdout`, `unsafe_last_exitcode_after_ps1_engine`, `forwards_unknown_engine_param`, `shared_engine_unresolved`, and `surface_mismatch` — the last always realigned by restoring the missing mandatory surface element while preserving local defaults, never by recopying the template whole). Process both lines when two separate `wrappers/inventory:` lines appear.
- `INVENTORY_ENGINE_DIAGNOSTIC` is **informative**, not a workspace pendency: it flags a canonical engine missing/broken in the shared skill base itself (infrastructure of this repository, not a local deviation), so it stays outside the blocking tokens (`INVENTORY_GAPS`/`INVENTORY_CUSTOMIZED`) and never blocks setup state. Include it in the handoff as a diagnostic note, never classify it CUSTOMIZED.
- `INVENTORY_SURFACE_ADVISORY` is **consultative**, not a blocking pendency: it flags a local wrapper behind the template by an **optional** reduction only (`optional_param_missing`, `validateset_reduced`, `optional_promoted_to_mandatory`, `extra_mandatory_added`, `no_param_block` with an optional-only template) — never a lost mandatory contract, which surfaces in parallel as `INVENTORY_CUSTOMIZED (reason=surface_mismatch)`. It stays outside the four blocking tokens by design, same as `INVENTORY_ENGINE_DIAGNOSTIC` and `INVENTORY_RECOMMENDED_MISSING`; never add it to the aggregator's blocking regex.
- NEVER audit, report, or ask for deployment, hosting, or packaging metadata.
- NEVER omit `INVENTORY_RECOMMENDED_MISSING` from the handoff — even though consultative, it exists to stop agents from repeatedly calling the shared engine directly when the skill already recommends a thin local wrapper for the observed scenario.
- NEVER propose changing existing `kb-source-metadata.md` fields in update mode just to satisfy a stale wrapper — fix the wrapper to read the real file format instead. Metadata changes are only in scope when they belong to the current operation's authority (`last_setup_audit_run_at`/`setup_contract_signature_*` for this workflow, materialization fields for the **sync** workflow, or stable identity in an explicitly approved reconciliation workstream).
- NEVER propose creating a wrapper, renaming a script, updating `AGENTS.md`, writing `kb-source-metadata.md`, or any other write in update mode before presenting the full 8.h classification table — the table is a prerequisite of the action proposal, never its consequence.
- NEVER omit or summarize `Test-*KbSetupAudit.ps1`'s `wrappers/inventory:` lines when reporting to the user — every line must appear exactly as emitted.
- NEVER ignore an unrestricted external-tool routing rule in local `AGENTS.md` without evidencing the unnecessary-load risk to the user and offering the scoped fix from 8.g4.
- NEVER close a minimum audit, a full-audit precondition, or `audit-setup` with only a diagnosis when objective evidence shows at least one correctable item from the POST-AUDIT CORRECTION PLAN — presenting the consolidated plan and offering same-session execution is mandatory.
- NEVER recommend "a separate round" or "fix it later" as the default response to a correctable setup pendency — defer only when the user explicitly refuses or defers the plan or one of its items.
- NEVER silently resume the user's original task after `GATE_OK` without having presented the consolidated plan when a correctable setup pendency exists, even though the task is already released by the gate.
