# Sync workflow

Invokes the active repository's local scripts to sync individual XMLs from an XPZ exported by the IDE, or to check a full KB export.

---

## PURPOSE

Identify the repository root from context, locate the sync scripts in the `scripts\` folder, assemble the right command, and run it in the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`). Report the result clearly. Never edit files manually — delegate everything to the script. Treat `KbObjectsXml` as the official, read-only-for-agents snapshot; only the official sync flow from an XPZ exported by the GeneXus IDE may update it. Always distinguish the native KB folder from the KB workspace. A local delta or preview is never the official snapshot and must never be manually promoted into that corpus. If an edit is detected or intended in `KbObjectsXml` for a delta not yet officially re-exported by the KB, treat this as an explicit process error.

When the same XPZ is reprocessed after the exported file was updated, treat the new result as a new snapshot of that input, not as an irrelevant repeat of the previous processing. The `updated` vs. `unchanged` classification belongs to that specific processing run's result.

When the shared engine gains a relevant operational parameter, that only means the capability exists in the shared engine. Exposing it in local wrappers is still a local decision and can lag behind. In these cases, treat the gap as an opportunity for local adaptation, propose the change to the user, and wait for explicit approval; never change local wrappers unilaterally.

The local wrapper's surface can also be temporarily ahead of, behind, or slightly misaligned with the KB workspace's effective shared engine. When a failure is limited to one optional comparison/verification parameter and the main sync is still viable, treat it as a wrapper/engine divergence: rerun without the optional parameter, record the incident in the report, and do not automatically classify this as a block on the main operation.

The methodological base's `.example.ps1` files can serve as reference to fix or rebuild final local wrappers, but they do not replace the real local wrapper and must not be used as an automatic execution fallback in the KB workspace's normal flow.

If the KB workspace is not yet mounted, validated or mapped, stop and use the **setup** workflow before `sync`.

## PATH RESOLUTION

- Resolve every `../references/<file>.md` reference relative to the directory of this file (`skills/mimir-lite/workflows/`), not relative to the current working directory.

---

## TRIGGERS

Use this workflow for:
- The user wants to process a `.xpz` exported from the IDE
- The user wants to update the XML corpus from an XPZ
- The user wants to check whether a full KB export is complete
- The user wants to run the sync or snapshot script

Do NOT use this workflow for:
- Generating or building XPZ packages for manual import in the IDE — out of scope for this skill
- Analyzing the internal structure of a single XML (use **read**)
- Installing or managing automatic monitoring of XPZ folders — out of scope for this skill
- Locating objects in the KB corpus by name or type (use **find** when a `KbIntelligence` index is available)
- Preparing, explaining, or validating the KB workspace's initial structure (use **setup**)

---

## EXPECTED SCRIPTS

The repository must contain two wrappers under `<repo_root>\scripts\`:

| Purpose | When to use |
|---|---|
| **Daily update** — extracts and materializes XMLs into the corpus from a partial XPZ | Day-to-day XPZ exported by the IDE |
| **Full check** — verifies the corpus against a full KB export without changing the corpus or `kb-source-metadata.md` | A new full KB export |

The exact wrapper names are defined per repository. Check the local `README.md` to identify them.

## NAMING RULES

- When materializing a corpus from XPZ, organize files into subfolders by the object's friendly GeneXus type.
- When materializing a corpus from XPZ, use the object's friendly name as the XML's primary file name.
- Never use a GUID as the primary folder or file name during materialization.
- GUID, `parentGuid`, `parentType` and `moduleGuid` are supporting metadata, not the primary organizing axis.

---

## LOCATING THE REPOSITORY

1. Use the current working directory as the starting point.
2. If needed, walk up to the Git root (`git rev-parse --show-toplevel`).
3. List `scripts\` and identify the two wrappers from the local `README.md`.
4. If not found, ask the user where the repository root is before proceeding.

---

## COMMON PARAMETERS

The wrappers follow this parameter convention:

### Daily-update wrapper
- `-InputPath` *(required)* — path to the `.xpz`, an XML, or a folder containing the XML; for GeneXus 7.0 and earlier, a `.xpw` text export or a `.zip` of `.xpw` files (see [`.xpw` text exports](#xpw-text-exports-genexus-70-and-earlier))
- `-VerifyOnly` *(switch)* — check without modifying the official corpus or KB metadata; XPZ extraction may use a temporary directory, and explicitly requested report or diagnostic output may still be written
- `-FullSnapshot` *(switch)* — compare against the corpus' full snapshot
- Under `-FullSnapshot`, the engine reconciles the corpus by the root node's stable identity (`guid`), not just by logical name: when the same `guid` appears in the corpus under a different file name, it treats this as a **rename** and renames the existing file (`Move-Item` old → new) instead of create-new + abandon-old; the result is a single file (new name) and Git detects a similarity-based rename. Covers `Attribute` and `Object`. Under `-VerifyOnly`, the engine only **classifies** the rename residue in the report (`RenameResidualsDetected`), without touching disk.
- Without `-FullSnapshot` (a delta), the engine applies the same `guid` rename to each incoming item whose target file does not exist yet, scanning only that item's type folder: a same-`guid` file under the old name is renamed instead of creating a second file. When the rename cannot be done safely, the delta skips it with a warning and creates the item under its new name (see **Ordering and atomicity** below). Files of objects the delta does not carry are never touched.
- A full XPZ only defines the input; by itself it does not define the verification mode.
- For normal materialization — including an initial load from a full XPZ exported by the IDE — never assume `-FullSnapshot` as an implicit default or an ergonomic shortcut.
- Use `-FullSnapshot` only in one of these cases: an explicit user request for a full check, using the dedicated full-check wrapper, or an explicit requirement from local documentation.
- `-ReportPath` *(optional)* — saves a JSON report
- `-KeepReport` *(switch)* — keeps the report even with no error
- When there is a first materialization followed by a confirmatory reprocessing or a full check, do not silently overwrite the first materialization's main report with the second pass' report; use separate paths for each report, or make explicit in the handoff which file corresponds to `materialization` and which to `confirmation`/`check`.
- `-ExpectedItems` *(optional)* — a list of the current workstream's expected items, formatted `Type:Name`, used only to classify the expected focus against the KB's official return
- The shared engine accepts `-ExpectedItems` as a normal PowerShell list or as a single string separated by commas, semicolons, or line breaks; with the canonical `pwsh -NoProfile -File` form, prefer the single comma-separated string, so the value parses the same in bash, PowerShell, and cmd.
- This parameter's availability in the shared engine does not authorize assuming a KB workspace's local wrappers already expose it; if the local wrapper does not accept it yet, treat this as a local-update opportunity, mention it to the user, and wait for explicit approval before any change.
- If the local wrapper accepts `-ExpectedItems` but execution fails in the effective shared engine due to an incompatibility limited to that comparison optional, treat this as a wrapper/engine divergence, not an automatic block on the main sync.
- When the failure is limited to that optional parameter, rerun without `-ExpectedItems`, complete the materialization if the rest of the flow is sound, and record in the handoff that the expected-vs-official-return comparison was unavailable that round due to an engine incompatibility.
- If the failure attributed to `-ExpectedItems` reveals a break in materialization, the wrapper's core contract, the index's mandatory refresh, or another central impact on the official flow, keep treating the case as a real block.
- `-KbMetadataPath` *(optional)* — saves KB metadata in Markdown
- `-KbWorkspaceRoot` *(optional)* — the KB workspace root; resolves `scripts/gx-object-type-catalog.override.json`
- `-CatalogOverridePath` / `-DiscoveryReportPath` *(optional)* — a local override and a JSON report when the package has an unmapped GUID
- During normal materialization, when the local wrapper enables `-KbMetadataPath`, `kb-source-metadata.md` is refreshed surgically in materialization-owned fields only (`updated`, `last_xpz_materialization_run_at`, `source_xpz`, `source_refresh_status`, `source_export_format`, and the `KMW`/`Source`/`Source/Version` tables; `source_export_format: xpw` is written only for a `.xpw` source, and a later XML/XPZ sync rewrites an existing field to `xml` without adding it to files that lack it), preserving `last_setup_audit_run_at`, `setup_contract_signature_*`, other out-of-scope frontmatter, and extra sections. `-VerifyOnly` skips this metadata write.
- When `kb-source-metadata.md` is updated by the sync, it must record `last_xpz_materialization_run_at` as the time of the requested XPZ/XML processing, even when no XML had a material change.
- If the XPZ comes with an empty, incomplete, or missing `Source`, the wrapper must preserve known stable values and emit a partial-refresh warning; this does not invalidate the object sync.
- After a successful XPZ/XML materialization into `KbObjectsXml`, the local wrapper must compulsorily trigger regeneration/validation of the derived index through the local `KbIntelligence` wrapper.
- Rebuilding the index via `scripts/Build-KbIntelligenceIndex.ps1` requires **usable Python 3.8 or later** on `PATH`, found as `python3`, `python`, or `py -3` (`scripts/GeneXusPythonPrerequisite.ps1`; a Microsoft Store `WindowsApps` stub does not count). Its absence blocks the refresh with exit `8` and message `PREREQUISITE MISSING` — **strictly speaking, the normal sync did not finish**; XPZ/XML materialization may already have completed, but that is **not** equivalent to the official flow succeeding, nor does it authorize broad triage without an index. Do not treat this as a failure of the exported package; install Python 3.8 or later and rerun the rebuild (`Rebuild-*KbIntelligenceIndex.ps1`). See `README.md`, `02-operational-rules.md`, and the `Update-KbFromXpz.example.ps1` template.
- Clear evidence of this chaining means an explicit local declaration in `README.md`/`AGENTS.md`, or an observable call in the local wrapper's own code; do not assume this capability just because the shared engine requires it.
- If the local index-regeneration wrapper is missing or stale, or if the materialization wrapper does not chain this refresh, treat this as an operational block on the normal sync and offer the user an update via the **setup** workflow before proceeding.
- Do not present `sync` followed by a separate manual index regeneration as the normal flow in a KB workspace that adopts `KbIntelligence`.
- `-BlockCrossFlowDataSource` *(switch, opt-in)* — aborts the sync (`ErrorId=CrossFlowDataSourceCollisionBlocked`, preceded by `CROSSFLOW_BLOCKED_ERRORID:` on stderr) **before** writing metadata or XML, when there is a cross-flow origin (`dataSource`) collision: modern (no `dataSource`) ↔ legacy (`gx-legacy-export`).
- Without the switch, the **fail-soft path adds no extra gate to materialization**: detection runs before the write and only **records** the collision (`CrossFlowCollisions` field; stderr/report), and the flow proceeds normally under the `lastUpdate` rule (overwrites if the incoming item is not older), possibly materializing modern↔legacy without blocking; see the result-interpretation section for detail.
- As with every shared-engine parameter, the KB workspace's local wrapper may not yet forward it; treat its absence as a local-update opportunity (same posture as `-ExpectedItems`), not a block.
- `-NoGitSummary` *(switch)* — suppresses the final Git summary

### Full-check wrapper
- `-InputPath` *(required)* — path to the `.xpz`, an XML, or a folder; or a `.xpw` text export or a `.zip` of `.xpw` files
- `-ReportPath` *(optional)* — saves a JSON report
- `-KeepReport` *(switch)* — keeps the report even with no error
- `-ExpectedItems` *(optional)* — passes known workstream focus items to the comparison
- `-NoGitSummary` *(switch, optional)* — suppresses the Git summary

The setup example `Test-KbFullSnapshot.example.ps1` accepts `-ExpectedItems` and `-NoGitSummary`. A KB-local wrapper may expose a different parameter surface; check that wrapper rather than assuming the example's parameters are available.

---

## FIRST SYNC OF A NEW WORKSPACE

Applies to the first materialization into a workspace that setup closed on `ready_for_first_materialization`, typically right after the agent bootstrap in the repository `README.md` ("Use it with an AI agent").

- **An XPZ attached in the chat may not exist on disk.** The wrapper needs a real file path for `-InputPath`. If the user only attached the XPZ, ask for its path on disk; or, with the user's explicit consent, save the attachment into the workspace's `IdeXpzExports` folder under its original name and use that path. Saving a file the user hands over in the chat, with consent, is the user placing their input; it is not the agent moving the user's files, which **CONSTRAINTS** still forbids: never move, copy, or rename an XPZ that already exists on the user's disk (apart from the `processado_` rename of an XPZ inside `IdeXpzExports` after success, step 15).
- **The first load must come from a full KB export.** A partial (delta) export materializes only the objects it carries, and the index built from that partial corpus still passes its freshness gate, so later answers would be silently incomplete (missing callers, missing impact). Before the first sync, ask the user whether the XPZ is a full export of the KB, unless the user already said so in this conversation; never infer the answer from the file name, its size, or the object counts. Run the **7b** pre-scan first and put its counts in the question itself, as numbers from the inventory JSON: `distinctObjectCount`, `attributeCount`, and the largest entries of `distinctObjectsByType`, which count each object once (for example "The XPZ holds 392 objects and 18 attributes: 120 Procedure, 80 WebPanel, 40 Transaction, ... Is it a full export of the KB?"). A question without the counts is incomplete. `objectCount` and `objectsByType` count export entries instead: when `duplicatesInExport.count` is above zero, the export repeats some objects, so say so in one line and name them from `duplicatesInExport.items`. The counts support the question, but never replace the user's answer. If the user has only deltas, ask for a full export first. When several deltas follow the full load, process them oldest first, in the order they were exported: each run then reports the real sequence of changes, instead of the `lastUpdate` rule reporting the objects of an older delta as `skipped-older-lastUpdate`.
- **The run can take a long time.** On a large KB, the sync plus its chained index build can run far longer than an agent tool's default command timeout. Run it as a background command, or with the longest timeout the tool allows, and wait for the result JSON; do not kill it or report it as stuck while it is still running. A run stopped halfway can leave the corpus materialized and the index pending (an incomplete flow, see step 14).

---

## WORKFLOW

1. Identify whether this is a daily update or a full-snapshot check.
2. If the KB workspace is not yet mounted, validated, or mapped for this repository → **ABORT** and use the **setup** workflow. A new workspace that setup closed on `ready_for_first_materialization` is ready for its first sync even though `Test-*KbStructure.ps1` and `Test-*KbIndexGate.ps1` still report `KbIntelligence/kb-intelligence.sqlite` as not built yet (`first index build pending`): that file is created by this sync's index build, and both gates pass only after it (see "Structure gate before the first index build" in the **setup** workflow).
3. Resolve the repository root from context.
4. Read the local `README.md` to identify the wrapper names.
5. Distinguish the KB's official corpus (`KbObjectsXml`), the IDE-export input (`IdeXpzExports`), and the local sync wrappers; these folder names are defaults when the user has not named alternatives. Report any real-name → function mapping when local names differ. If the XPZ-input folder is missing, ask the user where exports should be saved; if the official corpus folder is missing, stop and treat the KB as not yet materialized (use **setup**). Do not create KB workspace folders in this workflow; use the corpus only as updated by the official sync flow.
6. If local changes to the official corpus are detected outside that flow, report a process incident and stop the normal sync. Preserve the affected work separately without promoting it into the corpus, and present a structured manifest of preserved items before resuming. Restore the official snapshot only through an approved recovery process; keep sync blocked until that is complete.
7. Apply the applicable catalog and package checks:
7a. **Catalog-override reminder/audit (each session, when the workspace has a local override):** if the KB workspace has `scripts/gx-object-type-catalog.override.json`, run `Test-MimirCatalogOverrideSessionReminder.ps1 -KbWorkspaceRoot <root> -AsJson` and read `status`, `noticeRequired`, `reminderRequired`, `cleanupRecommended`, `declaredUpstreamPending`, `effectiveUpstreamPending`, and the `pendingTypeNames`/`redundantTypeNames`/`divergentTypeNames` lists. Repeat the message to the user when `reminderRequired=true`; when `cleanupRecommended=true`, offer approved local cleanup of redundant entries in the round's plan, without automatically removing anything. With no override file, skip it: the script would only report `status=OK` with `noticeRequired=false`. This is the same rule as **setup** step 0.
7b. **Pre-scan before a long materialization:** for a full XPZ or an initial load, run the shared inventory script with this complete command, in the canonical command form (machine output is JSON on stdout by default, no `-AsJson` needed):
   ```text
   pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Get-GeneXusXpzObjectInventory.ps1" -InputPath "<path-to-xpz>" -FailOnUnknownTypes -KbWorkspaceRoot "<KbWorkspace>"
   ```
   It is a direct call to a shared script, so the shared-scripts allow rule of the **setup** workflow (step 20a) is offered before it when the agent tool has a command allowlist. If it blocks (`exit 3` / `UNKNOWN_TYPES_BLOCKED`), do not call sync until the type is resolved. Read `unknownTypesMessage`: it names each unknown type GUID with the type name and package the package declares in its Dependencies block (format in `08-agent-guide.md`, unknown-type section). The sync wrapper runs the same pre-scan and prints that message on stderr when it blocks.
7c. **Unknown type detected:** follow `02`/`08` (unknown-type section): stop; ask whether the user authorizes a **recommended** external documentation lookup (e.g. the official wiki); offer a local record with `-UserApproved` (`Register-GeneXusObjectTypeCatalogOverride.ps1`) and a maintainer prompt (`New-GeneXusUnknownTypeMaintainerPrompt.ps1`). Use `-DiscoveryReportPath` in the sync for a triage JSON under `Temp`.
8. Confirm `InputPath` with the user if not provided (for a chat-attached XPZ or a first load, see **FIRST SYNC OF A NEW WORKSPACE**). On the first sync, ask whether the XPZ is a full KB export unless the user already said so, with the 7b pre-scan counts in the question. If an active workstream is clear but its focus objects have not been declared in the conversation, ask or confirm those objects before running the sync.
9. When the flow involves materializing a full XPZ:
   - break `full.xml` into individual per-object XMLs
   - write the output into the materialized-corpus folder
   - organize by the object's friendly GeneXus type
   - use the object's friendly name as the XML's primary file name
10. When the flow involves a partial XPZ, update the same materialized-corpus folder. If the same XPZ file is re-exported/updated and reprocessed, treat the new processing by its content and resulting `lastUpdate`, not by memory of the previous run. `-ExpectedItems` compares expected focus with the official return; it does not limit which returned items the sync materializes.
11. If the workspace adopts `KbIntelligence`, verify the local materialization wrapper chains a compulsory index refresh after a successful non-`VerifyOnly` sync:
    - only count clear evidence explicitly documented in the local repository or observable in the local wrapper's own code
    - if the wrapper lacks this capability, block the normal sync before running it and offer an update via the **setup** workflow
    - do not run the normal sync expecting to fix the index manually afterward
    - do not use the old wrapper to update `kb-source-metadata.md` and then regenerate the index manually as a substitute for the compatibility fix
    - do not use the shared base's `.example.ps1` as a temporary substitute for a missing real local wrapper
12. Assemble the command with the correct parameters:
    - for normal XPZ materialization into `KbObjectsXml`, do not add `-FullSnapshot` on your own
    - do not reinterpret a full XPZ as implicit authorization for `-FullSnapshot`; a full export and a full check are different things
    - use `-FullSnapshot` only when the user asks for a full check, when the dedicated check wrapper is the one chosen, or when local documentation makes it an explicit requirement
    - treat a `processado_`-prefixed name as a strong heuristic for an already-consumed artifact, not absolute truth about the file's content
    - if the user's explicit `InputPath` points at a `processado_`-prefixed file, issue a short alert, ask for confirmation, and proceed only if the user confirms that file as the correct input for the current round
    - if there is a comparison optional like `-ExpectedItems`, remember that its exposure in the local wrapper does not prove full compatibility with the effective shared engine; if the first run fails only at that point, prepare a rerun without the optional before concluding the sync is blocked
13. Run it as one command in the canonical form, `pwsh -NoProfile -File "<absolute-path-to-the-wrapper>" [parameters]`:
    - if execution fails with clear evidence of a wrapper/engine divergence limited to a comparison optional, rerun once without that optional parameter before classifying the case as a block
    - if the rerun without the optional completes materialization and the mandatory gates, record the main sync as successful with an incident on the optional capability
    - if the rerun without the optional repeats a central failure or exposes an issue outside the comparison's scope, treat it as a real block
14. If XPZ/XML materialization into `KbObjectsXml` completed successfully and was not `VerifyOnly`, confirm from the wrapper's output or clear local evidence that the derived index's compulsory refresh also ran:
    - if the rebuild fails with `PREREQUISITE MISSING` / exit `8` from the Python engine, declare an **incomplete flow** (XMLs possibly updated, index pending); do not close this as a successful sync nor as a defect in the XPZ
    - in a workspace that adopts `KbIntelligence`, missing evidence of the refresh must be treated as a failure or operational gap in the local wrapper
    - do not compensate for this gap with a separate manual index rebuild as if it were the normal flow
    - if the wrapper does not produce enough evidence of the refresh, end with a compatibility block and offer an update via the **setup** workflow
15. If processing completed successfully and the consumed `.xpz` is inside the workspace's `IdeXpzExports` folder, it is fine to rename it to `processado_<original-name>.xpz`. The rename applies only to files inside `IdeXpzExports`: an XPZ anywhere else (the user's own folder, a download folder, a project folder) is never renamed, and the report says that it kept its name because it is outside `IdeXpzExports`.
16. Report: objects created, updated, skipped, removed residue, index refresh, the Git summary, and every warning.
    - **warnings come from two places:** relay to the user both the result JSON's `Warnings` and every warning line the run printed on stderr (for example `WARNING: Git repository not found ...`); keep stderr when running the command so none is lost. Never report "no warnings" from the JSON alone
    - if the wrapper's summary exposes `MaterializationInterpretation`, use that field as the primary reading of the result instead of inferring from a loose combination of `Created`, `Updated` and `Unchanged`
    - `PackageInterpretation = no-exportable-items` means a valid, well-formed package with zero exportable items (`TotalExportedItems = 0`); on a normal materialization `MaterializationInterpretation` may also be `no-exportable-items`, but under `-VerifyOnly` it reports `verify-only` (or `legacy-export-adapted` for legacy input). Never mistake an empty package for a read failure or malformed input; confirm with the user which export scope the IDE accepted.
    - when a sync (with or without `-FullSnapshot`) reconciles a rename by `guid`, report `RenamedByGuid` (files renamed in the corpus, or same-`guid` orphans removed); under `-VerifyOnly`, report `RenameResidualsDetected` (renames detected without moving anything); these numbers explain why an old name stopped existing in the corpus and must be read as a recognized rename, not a blind deletion
    - **incremental-sync preservation:** without `-FullSnapshot`, the sync only materializes/updates the items present in the input (including a same-`guid` rename of an incoming item, reported in `RenamedByGuid`) and **preserves** corpus files not present in the XPZ — leftovers are neither removed nor flagged in this mode; do not declare leftover detection on an incremental round
    - **leftovers/missing are exclusive to `-FullSnapshot`:** `FullSnapshotMissing` (reference-snapshot keys absent from the corpus) and `FullSnapshotExtra` (keys found in the corpus and absent from the snapshot — the leftovers) are only counted under `-FullSnapshot`; without the switch both come back `null` in the JSON — do not read `null` as "zero leftovers" or as "an intact snapshot"
    - the wrapper/engine's result is a **single machine JSON line on stdout** (`Kind = "mimir-sync-result"`, `SchemaVersion = 1`, serialized with `-Compress`); all human-readable text (counter summaries, Git summary, warnings) goes to **stderr**, never stdout. Consume the result as an object (`ConvertFrom-Json`), not by parsing the human text. Note: in a child process (`pwsh -File`), `Write-Host`/`Write-Warning`/`Write-Information` leak into captured stdout — this is why the contract requires stderr for diagnostics
    - **read the last JSON line of stdout:** parse the last non-empty stdout line that starts with `{` as the sync result, not the whole stdout. The current wrapper template sends the chained index rebuild report to stderr, but a wrapper copied into a workspace before that fix prints the rebuild report on stdout first; reading the last JSON line works with both
    - the engine exposes **ready-made nominal lists**, removing the need for `git diff` to name the objects: `CreatedNames`, `UpdatedNames`, `UnchangedNames`, `SkippedOlderLastUpdateNames` (format `"Type:Name"`) and `RenamedByGuidItems` (`{Guid, FolderType, OldName, NewName, Action}`). Each list is consistent with its matching counter (`len(UpdatedNames) == Updated`, etc.). These status lists describe materialization outcomes, not workstream focus. Under `-VerifyOnly` the write lists come back empty by construction (not by missing data); `NormalizedFileNames` stays a counter only (it counts file names, not logical names)
    - when `-ExpectedItems` was supplied, use `ExpectedReturnedNames` for `focus objects that came back`, `ExpectedMissingNames` for `focus objects that did not come back`, and `AdditionalOfficialNames` for `additional official KB return`. These nominal lists classify package membership; `CreatedNames`/`UpdatedNames`/`UnchangedNames`/`SkippedOlderLastUpdateNames` remain an orthogonal materialization-status axis.
    - if `-ExpectedItems` was supplied, give a short, non-alarmist comparison summary (for example, expected / returned / not returned / additional counts). The comparison is supplementary: additional official objects may be legitimate parallel KB changes, and missing focus items are not an automatic sync failure.
    - if an active workstream is known but `-ExpectedItems` was not supplied or the local wrapper does not expose it, compare the returned-item names/evidence with the known focus: matching focus items came back, unmatched focus items did not, and identified official items outside the focus are additional returns. Do not treat empty `-VerifyOnly` write lists as evidence that no objects came back; if the report does not expose enough returned-item names to classify the buckets, state that evidence limitation instead of guessing.
    - when presenting the nominal lists to the user, apply a **per-category** size rule: up to 10 items, list the names; above 10, show the counter + a short sample (first 3 + "… and N more") and **offer** to print the full list in chat (the JSON result is already in hand — no file or `git diff` needed)
    - explain that `updated` means the wrapper materialized newer/relevant content into the corpus in that processing run
    - explain that `unchanged` means the incoming XML matches the existing corpus XML; if it differs but carries an older `lastUpdate`, the result is `skipped-older-lastUpdate`, not `unchanged`
    - explain that `RepeatedInExport` (with `RepeatedInExportNames`) counts the extra identical copies of an object inside the same export (a GeneXus 6 export repeats a style object each time it is referenced): each object is written once, and its copies are neither `created` nor `unchanged`; a copy that differs is written in order (the last one wins) and named in a `differing copies inside the export` warning
    - explain that `updated`/`unchanged` belong to processing the XPZ against the current materialized file, not to the repository's Git state
    - never claim "first load" or equivalent when `Created = 0` and `Unchanged > 0`; that combination alone does not prove a first materialization, and usually indicates a snapshot that already existed, confirmed against the current input
    - explain that an item can appear as `unchanged` in the sync because the local file already matches the content coming from the XPZ, even if that same file still has a pending diff in Git against the last commit
    - **cross-flow origin (`dataSource`) detection:** the engine detects, before writing metadata/XML, when an incoming item collides in the corpus (`FolderType|NormalizedName`) with a file of a **different origin** — the central case is modern (no `dataSource`) ↔ legacy (`dataSource="gx-legacy-export"`). Default posture is **fail-soft**: an additive `CrossFlowCollisions` field (array; `[]` when empty) in the stdout result + a `Writes[].CrossFlowCollision` boolean in the `$report` (`-ReportPath`); each collision also goes to **stderr** as JSONL prefixed `CROSSFLOW_COLLISION:` (and parse warnings as `CROSSFLOW_WARNING:`), so it is not lost on paths that abort before stdout. `SchemaVersion` stays `1` (additive fields). **Decision E.2:** when the existing file has no `dataSource`, a direct `<GxLegacyPayload>` child is the legacy signal; `guid=""` only corroborates it.
    - **`-BlockCrossFlowDataSource` (opt-in block):** aborts the sync (a terminating error, `ErrorId=CrossFlowDataSourceCollisionBlocked`, preceded by the stable `CROSSFLOW_BLOCKED_ERRORID:` line on stderr) **before** writing any metadata or XML, instead of fail-soft. Separate from the fail-closed for a mixed package. For an existing **unparseable** XML (Decision G): detection neither collides nor blocks (even under the switch), only a warning — but this **does not guarantee the overwrite**; the sync can still fail later processing a corrupted existing file (in the existing parse stages, which this detection does not cover).
    - **Ordering and atomicity:** detection runs **pre-rename**, after `$items` and **before** metadata, on both branches. On the **modern** branch the flow is `catalog → unknown-type → Convert → detection → metadata`: the **unknown-type** and **intra-package-collision** fail-closed paths abort **before** `kb-source-metadata.md` is written. **Asymmetry:** the **rename** fail-closed under `-FullSnapshot` (`Resolve-GuidAwareRenames`) aborts **after** metadata — under `-FullSnapshot`, this path can leave the metadata written with no writes. A delta never aborts on the rename step: it only reconciles items whose target file does not exist, and any condition that fails closed under `-FullSnapshot` (an unreadable XML in the scanned type folder, a duplicate `guid`, a name collision, a failed move) skips the rename for the affected item instead, with a warning in `Warnings` naming the `guid` and the files involved; the item is then created under its new name and the existing files are kept, as before delta renames existed. Under `-VerifyOnly`, a delta rename is only classified (`RenameResidualsDetected`): nothing is moved, created, or written to `kb-source-metadata.md`.
    - when there is a Git summary, present that layer separately as a worktree-vs-current-commit comparison, without reclassifying the sync's result
    - if the same XPZ was reprocessed after the file was updated, make explicit that the relevant comparison is against the reprocessed input's content and the corpus' current state, not the old report
    - if `kb-source-metadata.md` was surgically updated by the wrapper (materialization fields), treat this as a normal flow artifact, not automatic evidence of a functional change in the workstream
    - if the workspace still carries a provisional local setup memory saying `KbObjectsXml` was not materialized, `waiting for the first XPZ`, or equivalent, update or neutralize that state once the first official materialization has succeeded
    - only state specific `kb-source-metadata.md` content — GeneXus version, build, KB GUID, user, or `Source` path — when that metadata explicitly appeared in the wrapper's real output, or when `kb-source-metadata.md` itself was opened and read by name in the current round
    - when neither acceptable source showed the metadata, limit the summary to what the wrapper actually returned
    - if the package has a partial `Source`, clearly separate "object sync accepted" from "partial metadata refresh", and preserve the already-known stable values
    - if there is a first-materialization report and another confirmatory-reprocessing or full-check report, do not mix their roles in the handoff; explicitly identify which file represents corpus creation/update and which represents only a later verification
    - if the KB's official XPZ brings additional objects outside the workstream's immediate focus, report this as unexpected for the current workstream, but treat it as a possibly legitimate parallel change coming from the IDE/KB until evidence says otherwise
    - when the Git summary or `git diff --check` flags whitespace in `KbObjectsXml`, treat it as evidence to review without automatically reformatting the official snapshot
17. When an object comes back from the KB via XPZ, treat its official corpus XML as the most trustworthy source; a local delta is never itself an official return.
18. When preparing a commit or handoff after `sync`, explicitly separate:
    - current-workstream artifact = a result the current processing confirmed as belonging to the ongoing workstream
    - legitimate parallel change from the KB/IDE = an item officially returned by the KB in the XPZ, even if outside the workstream's immediate focus
    - improper side change = an edit made by the agent outside the phase's scope or outside the expected official flow
    - do not group parallel changes into the current workstream's commit without an explicit decision, but do not automatically treat the KB's additional official return as an error
19. The minimal technical handoff must state:
    - the command/wrapper run and the `InputPath` used
    - whether the round was a normal materialization, a confirmatory reprocessing, or a full check
    - the main report used for the conclusion and, when present, a separate later-verification report
    - `MaterializationInterpretation` when the wrapper exposes that field; otherwise limit the reading to the real counters and warnings
    - the warnings, from both the result JSON's `Warnings` and stderr, or an explicit statement that neither had any
    - the evidence used to claim the index refresh, or the block that prevented that conclusion
    - whether `kb-source-metadata.md` was read by name in the current round, or only surgically updated by the wrapper (materialization fields)
    - if there was an optional-comparison failure due to a wrapper/engine divergence, state the affected parameter, the rerun without it, and that this did not block the main sync
    - when the context identifies an active workstream, state explicitly: `focus objects that came back`, `focus objects that did not come back`, and `additional official KB return` — even when `-ExpectedItems` was not passed or is unavailable in the wrapper
20. The Git summary from the previous item is informative only; it does not authorize `git add`, `commit` or `push`.
21. If the user does not explicitly ask for Git closure, the flow should end at the technical handoff and, at most, suggest next steps without publishing anything.

---

## EXPECTED MATERIALIZED STRUCTURE — SHORT EXAMPLE

```text
KbWorkspace/
  IdeXpzExports/
    FullKb_20260413.xpz
    processado_PacoteExemplo_20260413.xpz
  KbObjectsXml/
    Transaction/
      Customer.xml
      Order.xml
    Procedure/
      GenerateInvoice.xml
    WebPanel/
      WPCustomerLookup.xml
  scripts/
    Update-KbFromXpz.ps1
    Test-KbFullSnapshot.ps1
  kb-source-metadata.md
```

`kb-source-metadata.md`, when refreshed by a local wrapper during normal materialization, gets a surgical update rather than full regeneration. The engine preserves `last_setup_audit_run_at` (the **setup** workflow's authority), other out-of-scope frontmatter, and extra sections; it updates stable `Source`/`KMW` values when the current XPZ comes with empty or partial metadata. A full `-VerifyOnly` check leaves this file unchanged; an explicitly requested report or diagnostic output may still be written, and XPZ extraction may use a temporary directory that is cleaned up when processing ends.

This file is also the expected location of `last_xpz_materialization_run_at` (this workflow's authority). That timestamp represents the last XPZ/XML materialization request/processing, not just the last material change detected in the XMLs.

---

## LEGACY EXPORTS (GeneXus 8 and 9)

`Sync-GeneXusXpzToXml.ps1` recognizes and materializes **legacy GeneXus 8 and 9 exports** with no extra configuration. A legacy export is an `ExportFile` whose objects appear as `<GXObject><Element>` by **name** (e.g. `<Procedure>`, `<Report>`), **without** `Object/@type` (a type GUID) — unlike a modern GeneXus 18 export. Automatic detection by profile:

- **pure-legacy** = `/ExportFile/GXObject` exists **and** `Objects/Object`=0 **and** `Attributes/Attribute`=0
- **mixed** (legacy and modern elements in the same `ExportFile`) = **fail-closed**: the sync throws a `BLOCK` error **without** writing `kb-source-metadata.md` and without materializing anything. Export the formats separately.

On the legacy branch the engine (`scripts/GeneXusLegacyExportFileSupport.ps1`) consumes the `scripts/gx-legacy-export-element-registry.json` registry (owner doc `01k-legacy-element-registry.md`):

- `equivalent` → materializes under the modern type's `folderName`, with `type=<real catalog GUID>`
- `orphan` (`Report`, `Menu`, `Prompt`, `Formula`) → materializes under its own `materializedFolderName`, with `type="gxlegacy/<Element>"`; KB Intelligence indexes `Report` and (since extractor 21) `Menu` as their own types and skips `Prompt/` and `Formula/`, auditing them in `legacy_orphan_directories_skipped`; a `Formula` is still read through the attribute it computes, and a `Prompt`, not read, is counted in reverse coverage (see the KB index reference). `Menu`, `Prompt`, and `Formula` come from GeneXus 7.0 and earlier (`.xpw`); a `Formula` has no `Info` block and is named after the attribute it computes (its own `Name`)
- **legacy `<Menubar>`** is `equivalent`→`Menubar` (a modern GUID), no longer an orphan. If the corpus still has XML with `type="gxlegacy/Menubar"` under `Menubar/` (materialized before the reclassification), the `KbIntelligence` rebuild **fails** — the folder is no longer skippable as an orphan. Re-sync the legacy package or clean up before the index; details in `01k`.
- **ungrouped subtypes:** a `<Group>` with a blank `Info/Name` holds the subtypes that belong to no group (GeneXus 8 exports one in each package). It materializes as **one `SubTypeGroup/<subtype>.xml` per `<Subtype>`**, each keeping only its own `<Subtype>` and the blank `Info/Name`, so a later export that carries fewer subtypes never overwrites the others. A blank group with no `<Subtype>`, a subtype without a name, or two groups/ungrouped subtypes with the same name in one package → `throw`
- each item becomes an `Object`/`Attribute` envelope with `dataSource="gx-legacy-export"`, the original payload preserved in `<GxLegacyPayload>`, and `guid=""` (does not take part in GUID-based rename)
- **cross-flow collision:** if the same `FolderType|NormalizedName` already exists in the corpus as **modern** (no `dataSource`), cross-flow detection triggers when materializing the legacy item — fail-soft by default (`CrossFlowCollisions`), or block with `-BlockCrossFlowDataSource` (see "Daily-update wrapper" and the result-interpretation section)
- a missing/invalid `lastUpdate` → a deterministic sentinel `0001-01-01T00:00:00.0000000Z` (conservative: in incremental materialization, sentinel × a real date → `skipped-older-lastUpdate`)
- **a tag outside the registry** → `throw` with instructions to extend the registry (never materialize partially)

Signals in the result JSON: `LegacyFormatDetected=true` and `MaterializationInterpretation`/`PackageInterpretation`=`legacy-export-adapted`. During normal materialization, when `-KbMetadataPath` is given, the metadata gets `-IsLegacyExport`: `Build` comes from `KMW/MaxGxBuildSaved` (a legacy export carries no `KMW/Build` or `<Source>` block), with a dedicated hint in place of the generic missing-`Source` warning. `-VerifyOnly` skips this metadata write. Reading is encoding-aware (GX8 and GX9 exports are iso-8859-1, read via `XmlDocument.Load`). Since extractor 19, KB Intelligence extracts calls and attribute uses from classic objects (see "Classic exports" in `kb-index-reference.md`). See `01k`, `02`, and the **read** workflow.

### `.xpw` text exports (GeneXus 7.0 and earlier)

GeneXus 6 and 7.0 export a KB as `.xpw` text, not XML. The engine (`scripts/GeneXusXpwExportFileSupport.ps1`) translates it in memory into the same classic `<ExportFile><GXObject>` XML, which then goes through the legacy branch above unchanged (registry, envelopes, `dataSource="gx-legacy-export"`, signals). Accepted inputs, for both the sync and `Get-GeneXusXpzObjectInventory.ps1` (`inputKind` `xpw` or `xpw-zip`):

- a `.xpw` file;
- a `.zip` holding `.xpw` files: every `.xpw` entry is merged into one export, in entry-path order; this covers the 1997 layout that splits objects and attributes into two files (an attributes-only `.xpw` syncs its attributes alone);
- a `.zip` that mixes `.xpw` and `.xml` entries fails closed; a `.zip` with no `.xpw` entry is handled as before;
- a folder of `.xpw` files is **not** accepted (the folder form still expects exactly one XML file): zip the files or sync them one by one.

Malformed `.xpw` text (an unclosed block, wrong indentation, an unknown line shape) fails closed naming the file and line; files from two different models or with different `KMW` headers in one zip fail closed naming the files; nothing is written. `Menu`, `Prompt`, and `Formula` blocks sync as legacy orphans (see above). KB Intelligence indexes Transaction, Procedure, Report, Web Panel, and (since extractor 20) Work Panel objects with the classic relations, `Conditions` included since extractor 21; since extractor 21 it also indexes `Menu` objects (each option calls its program) and reads each `Formula` through the attribute it computes; `Prompt` objects and `Subroutines` are not indexed.

With `-KbMetadataPath`, a `.xpw` source writes `source_export_format: xpw`, takes the `KMW` values from the export only (`KMW` 1.x has `MajorVersion`/`MinorVersion` and no `Build`; some files have no `KMW` block at all), never inherits them from a previous modern export, and emits its own hint (`KbMetadataPath: GeneXus .xpw text export detected ...`) in place of the GeneXus 9 one.

---

## CONSTRAINTS

- NEVER edit XMLs manually — all the work is delegated to the script.
- NEVER assume private absolute paths — always derive from the repository root.
- NEVER assume the wrapper names without checking the local `README.md`.
- NEVER run a normal `sync` while the KB workspace is still undefined, unmounted, or unvalidated.
- NEVER move files between working folders and the corpus — that is the official flow's responsibility.
- NEVER automatically create or move a `.xpz` into `IdeXpzExports` as if that folder were agent output; it is the input folder written by the user/IDE. The one exception is saving an XPZ the user attached in the chat, with the user's explicit consent (see **FIRST SYNC OF A NEW WORKSPACE**).
- NEVER rename the `.xpz` to `processado_<original-name>.xpz` before a clear processing success, and NEVER rename an XPZ outside `IdeXpzExports`.
- NEVER default to selecting a file already marked with the `processado_` prefix.
- NEVER use a GUID as the primary structure of materialization output.
- NEVER organize the materialized corpus with `guid`, `parentGuid`, `parentType` or `moduleGuid` as the primary navigation axis.
- NEVER create, alter, move, rename, or overwrite files in `KbObjectsXml` outside the official `.ps1` script flow.
- NEVER end a successful XPZ/XML sync without a compulsory derived-index refresh when the KB adopts `KbIntelligence`.
- NEVER run a normal sync in a workspace that adopts `KbIntelligence` if the local materialization wrapper does not yet chain a compulsory index refresh; offer an update via the **setup** workflow.
- NEVER describe `sync` followed by a separate manual index rebuild as the normal flow in a workspace that adopts `KbIntelligence`.
- NEVER use an old wrapper's sync to repair materialization metadata when the wrapper itself is stale; update/validate wrappers through the setup trail first.
- NEVER automatically default to a `processado_`-prefixed file when other plausible candidates exist for the current round.
- NEVER treat the `processado_` prefix as an absolute block when the user explicitly pointed at that `InputPath`; first issue an operational alert and require explicit confirmation.
- NEVER anticipate a manual update of `KbObjectsXml`.
- NEVER proceed with a normal sync when `KbObjectsXml` is dirty outside the official flow; first preserve, restore, and treat it as a process incident.
- NEVER treat a detected or intended edit in `KbObjectsXml`, for a delta not yet officially re-exported by the KB, as an operational detail; it is an explicit process error.
- NEVER create a new script if the repository already has an official flow provided by the skills or in `scripts/`.
- If the script is not found at the resolved root, report the error and ask the user before trying any alternative.
- NEVER treat reprocessing of the same updated XPZ as if the previous result were still authoritative.
- NEVER treat a surgical wrapper update of `kb-source-metadata.md` (materialization fields) as an automatic functional change in the current workstream.
- NEVER let `kb-source-metadata.md` lose known stable values because the XPZ came with an empty or incomplete `Source`.
- NEVER erase or overwrite `last_setup_audit_run_at` or other frontmatter fields outside the sync's authority; writing that field belongs to the **setup** workflow (`Set-*KbSetupAuditTimestamp.ps1` / `scripts/Set-MimirSetupAuditTimestamp.ps1`).
- NEVER reformat or normalize `KbObjectsXml` during sync to remove whitespace inherited from an official export.
- NEVER automatically classify as a process error, undue contamination, or a trail violation the simple fact that an official XPZ coming from the KB brings additional objects beyond the workstream's focus.
- NEVER materialize an XPZ with a type unknown to the effective catalog (shared + approved override).
- NEVER materialize a **mixed** `ExportFile` (legacy `<GXObject>` and modern `<Objects>`/`<Attributes>` elements in the same package); it is fail-closed (`throw` without writing `kb-source-metadata.md`) — export the formats separately.
- NEVER materialize a legacy element whose tag is **outside** `gx-legacy-export-element-registry.json`; the engine throws asking to extend the registry (owner doc `01k`) — never improvise a folder/type.
- NEVER register a local override or consult external documentation without the user's explicit consent.
- NEVER omit an override warning when `Test-MimirCatalogOverrideSessionReminder.ps1` returns `noticeRequired=true`: `reminderRequired=true` requires a pending/divergence alert; `cleanupRecommended=true` requires an explicit offer of approved local cleanup, with no automatic removal.
- NEVER mix parallel changes into the current workstream's commit without an explicit decision, just because they appear in the same workspace.
- NEVER omit the three-part structure (`focus objects that came back`, `focus objects that did not come back`, `additional official KB return`) in the handoff when the conversation identifies an active workstream with known focus objects — this is mandatory regardless of whether `-ExpectedItems` is available in the wrapper.
