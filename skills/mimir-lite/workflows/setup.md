# Setup workflow

Defines and validates the initial structure of the **KB workspace** used alongside a GeneXus Knowledge Base. This structure does not replace the native KB folder; it organizes the user's IDE-exported `XPZ` inputs, the XML materialized by the official flow, the derived index used for triage, and stable KB identity metadata.

---

## COMPLETION CHECKLIST

Read this whole file before acting on it. When the tool shows only part of it, keep reading in parts until **CONSTRAINTS**, the last section, which points to [`setup/constraints.md`](setup/constraints.md): read that file before any write, in every mode.

Five files under `setup/` hold the rest of this workflow; read each one when its pointer in this file says it applies: [`setup/audit.md`](setup/audit.md) (the fast-path precondition with its own steps 0 to 3, for the audit triggered by the global trigger, and the correction plan after any minimum audit), [`setup/update.md`](setup/update.md) (update mode only, steps 8.a to 8.h), [`setup/common-steps.md`](setup/common-steps.md) (every mode, steps 9 to 34), [`setup/wrappers.md`](setup/wrappers.md) (EXPECTED LOCAL WRAPPERS, when checking or fixing local wrappers or creating one by hand), and [`setup/constraints.md`](setup/constraints.md) (CONSTRAINTS, before any write, in every mode). Every other WORKFLOW step, from step 0 (the catalog reminder), and every other section named in capitals, is in this file.

Before declaring any completion state (see **SETUP COMPLETION STATES**), confirm that each applicable item below was done, or that the user explicitly refused it. These are steps of this workflow, not optional extras: never present them as optional items in a list of offers.

1. The runtime gate `Test-*KbPowerShellRuntime.ps1`, then the setup audit `Test-*KbSetupAudit.ps1`, ran (8.s.5; in update mode, 8.g3 in [`setup/update.md`](setup/update.md)).
2. When the agent tool has a command allowlist: the workspace allow rule (step 20 in [`setup/common-steps.md`](setup/common-steps.md)), the shared-scripts allow rule (step 20a), and, when the tool has file-read rules, the read rules for the clone's `skills` folder and for each skill link in the tool's skills folder (step 20a) were each shown verbatim, with the settings file path, on screen with the question, as COMMUNICATION, **Show before asking** describes, and asked about before writing; the shared-scripts rule before the first direct call to a shared script after the scaffolder, which runs once before it by design (step 20a). One question may cover all of them when it shows each verbatim.
3. The global instruction files were checked (7b); any write to one was asked as its own question, showing the file path and the exact block on screen with the question, as COMMUNICATION, **Show before asking** describes.
4. The local `AGENTS.md` has its `## Index triage` section (7a).
5. Nothing was saved to an external memory tool during this run (workspace details or anything else) without an explicit yes to a question naming what would be saved and where (step 14 in [`setup/common-steps.md`](setup/common-steps.md)).
6. On a successful canonical state, `Set-*KbSetupAuditTimestamp.ps1` wrote the setup-audit timestamp and the contract signature (step 34 in [`setup/common-steps.md`](setup/common-steps.md)) as the last write of the setup run, after every edit to `AGENTS.md`, `README.md`, and other workspace files.
7. The closing message gives the canonical state, says that `KbObjectsXml` is not materialized yet and that the next step is a full XPZ export and the **sync** workflow (steps 29 and 31), tells the user to start the agent tool in the KB workspace folder for KB work so the allow rules written there apply (step 20), says that permission prompts continue in this session when it was not opened in that folder (step 31), and recommends the **install** workflow by name in a sentence of its own (step 32). Steps 20, 29, 31, and 32 are in [`setup/common-steps.md`](setup/common-steps.md).

---

## PURPOSE

This workflow **must** run before any query, triage, or XML read in a folder containing `KbObjectsXml/` or `KbIntelligence/`. No other KB workflow of this skill (the **find** workflow, the **read** workflow, the **sync** workflow) may start in that folder until this workflow has run in the current session.

### Fast-path precondition (global trigger only)

Read [`setup/audit.md`](setup/audit.md#fast-path-precondition-global-trigger-only) only for the audit triggered by the global trigger: it holds the fast-path precondition (its steps 0–3), the **full audit**, and the transient `setup_*` sub-states. When the user explicitly asks for setup, an update, or an audit, skip it and go straight to WORKFLOW step 1.

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

Read [`setup/audit.md`](setup/audit.md#post-audit-correction-plan) after any minimum audit (`audit-setup`, the UPDATE BLOCK, or the precondition's full audit): it holds the **consolidated correction plan** (objective, items to include and to leave out, execution order, the global-trigger precondition, closing `audit-setup`). Read its last section, the optional LLM delegation policy, when setup concludes in any mode.

---

## PATH RESOLUTION

- Every `../file.md` reference in this workflow resolves from this file's own folder, not from the current working directory; `../` points at the shared methodology base one level up.
- The files under `setup/` (`audit.md`, `update.md`, `common-steps.md`, `wrappers.md`, `constraints.md`) sit one folder deeper: their `../../file.md` and `../../scripts/` references reach the same shared methodology base, `../setup.md` is this file, and their `examples/` is the same `setup/examples/` folder.
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

Read [`setup/wrappers.md`](setup/wrappers.md) when checking or fixing local wrappers, or when creating one by hand (update mode, or reconstructing a wrapper from the examples). In creation mode the scaffolder creates the wrappers and the setup audit checks them (its `wrappers/inventory` result), so read the file then only when that audit reports a wrapper problem. It holds the requirement matrix (which wrappers each scenario needs and what a missing one blocks), what each wrapper must do, and the fallback for reconstructing wrappers from the examples.

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
- When `AUDIT_REQUIRED` originated from missing/stale/inconsistent persistent metadata and the full audit plus gate then pass, differentiate in the handoff: `GATE_OK` releases the current task, but the folder still has a metadata pendency that should be fixed in the same session (via `Set-*KbSetupAuditTimestamp.ps1` or WORKFLOW step 34 in [`setup/common-steps.md`](setup/common-steps.md)) to restore the fast path for future sessions; defer to another session only when the user explicitly refuses or defers.
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

   This section is a prerequisite for declaring setup complete; without it, agents may route triage questions elsewhere instead of the **find** workflow, defeating the gate. In creation mode, the scaffolder writes it as part of `AGENTS.md` (from `examples/AGENTS.md.example`); in update mode, check and add it if missing (see step 8.g in [`setup/update.md`](setup/update.md)).

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
   - **Creation mode**: folder missing, empty, with no materialized `KbObjectsXml` and no `kb-source-metadata.md` with real timestamps → run the CREATION BLOCK below (the scaffolder), deepen exploration only on a concrete blocker, then proceed to step 9 ([`setup/common-steps.md`](setup/common-steps.md)).
   - **Update mode**: a folder with real history — any combination of materialized `KbObjectsXml`, `kb-source-metadata.md` with real timestamps, or a populated `kb-intelligence.sqlite` → run the UPDATE BLOCK ([`setup/update.md`](setup/update.md)) before step 9.
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
   It creates the default folders (`scripts`, `Temp`, `IdeXpzExports`, `KbObjectsXml`, `KbIntelligence`); the `.gitignore` and `.gitkeep` files of step 10; one wrapper per example, with the shared-checkout path, the native KB folder (when given), and the prefixed sibling names already resolved; `README.md` and `AGENTS.md` from [`examples/README.md.example`](setup/examples/README.md.example) and `examples/AGENTS.md.example`, including the native-KB-folder rule (steps 6–7) and `## Index triage` (7a); and `kb-source-metadata.md` with empty values. Exit `2` with `BLOCK:` on stderr means invalid input (KB name, shared root, or workspace path): fix it and rerun. Alternative folder names are not supported; use the hand-adaptation fallback in [Reconstructing wrappers from the examples (fallback)](setup/wrappers.md#reconstructing-wrappers-from-the-examples-fallback).

   This run is a direct shared-script call that comes before the allow rules by design (step 20a in [`setup/common-steps.md`](setup/common-steps.md)). Before it, tell the user that the agent tool may ask permission for this one call and that the allow rules are offered right after it (8.s.5).

8.s.3 **It never overwrites.** An existing file is reported `SKIPPED_EXISTING` and left byte-identical, so a rerun only adds what is missing. In a folder with real history, pass the KB name the existing wrappers already use as prefix, present what it will add and get approval first (8.b), list every wrapper it added in the existing `AGENTS.md`'s `## Local wrappers` section (8.z), and still classify every skipped wrapper in the UPDATE BLOCK — the scaffolder never fixes a stale wrapper.

8.s.4 **Relay the report:** the `CREATED` and `SKIPPED_EXISTING` lists and every `PENDING` line (native KB folder not given or not reachable; stable identity still empty). The `NEXT` lines list the follow-up commands.

8.s.5 **Continue with the steps that still apply**, in this order:
   - Allow rules (steps 20 and 20a in [`setup/common-steps.md`](setup/common-steps.md)), first: every later command runs a workspace wrapper or a shared script, so offer the workspace and shared-scripts rules before them, plus, when the tool has file-read rules, the read rules for the clone's `skills` folder and for each skill link in the tool's skills folder (step 20a), each shown verbatim on screen with the question, as COMMUNICATION, **Show before asking** describes (one question may cover all of them).
   - Stable identity (step 13): once the native KB folder is confirmed, run `Resolve-<KbName>KbIdentity.ps1 -UpdateMetadata`. If the folder was not given at creation, first record it in `AGENTS.md`, `README.md`, and that wrapper (placeholders `<NativeKbPath>` and `C:\path\to\native-kb`). In an XPZ-only workspace, skip this step: the first sync writes the identity.
   - Global trigger offer (7b), as its own question.
   - Git initialization offer (steps 11–12).
   - Every other edit to `AGENTS.md`, `README.md`, or other workspace files that this run makes.
   - `Test-<KbName>KbPowerShellRuntime.ps1`, then the setup audit `Test-<KbName>KbSetupAudit.ps1`; setup closes on that audit, not on the structure gate (see below).
   - Setup-audit timestamp (step 34 in [`setup/common-steps.md`](setup/common-steps.md)) when closing on `ready_for_first_materialization`, as the last write of the run. An edit to a workspace file after it means rerunning the setup audit and the timestamp.
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

Read [`setup/update.md`](setup/update.md) only in update mode: steps 8.a to 8.h continue there. Then continue with step 9 in [`setup/common-steps.md`](setup/common-steps.md).

--- NAMING-CHECK BLOCK (standalone, outside update mode) ---

When triggered standalone, follow the same 8.g2.i–8.g2.vii steps (in [`setup/update.md`](setup/update.md)). The only difference is there is no update-mode completion state to declare — the output is just the naming result per directory (conforming/divergent) and, if divergent, the supported sync/mapping follow-up from 8.g2.v.

--- END OF NAMING-CHECK BLOCK ---

### Steps 9–34 (every mode, after step 8)

Read [`setup/common-steps.md`](setup/common-steps.md) in every mode after step 8 (after the CREATION BLOCK in creation mode, after the UPDATE BLOCK in update mode): steps 9 to 34 continue there, including the allow rules (steps 20 and 20a), the closing message (steps 29, 31, and 32), and the setup-audit metadata write (step 34).

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

Read [`setup/constraints.md`](setup/constraints.md) before any write, in every mode: it holds this workflow's NEVER rules, among them never writing to the native KB folder, never renaming directories under `KbObjectsXml` by hand, and never proposing a write in update mode before the 8.h classification table.
