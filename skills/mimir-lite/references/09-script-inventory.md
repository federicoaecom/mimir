# 09 - Script inventory

## Document role
Index and traceability

## Predominant confidence level
High

## Depends on
None

## Used by
`00-index.md`, `01-empirical-base-overview.md`

## Purpose

List every script and data file that actually exists today under this repository's three
script folders (`skills/mimir-lite/scripts/`, `skills/mimir-delegate/scripts/`, `tools/`), one
row per file: what it does, which workflow or reference owns it, and which self-test validates
it. It also records the small set of governance conventions that apply across those scripts.

## How to use this document

- **This is a pointer index, not a contract site.** Each row is one line: purpose, owner doc,
  tests. The full behavioral contract for a script lives in its owner doc (or, for a
  support-library with no dedicated doc section, in its own comment-based help header) — never
  duplicate that detail here. `tools/Test-PrePushTraceabilityCoverage.ps1` enforces this
  mechanically (`PUBLIC_TRACEABILITY_VERBOSE_LINE`): an entry that grows back into multi-sentence
  contract prose is a regression.
- **Completeness is checked mechanically, not by manual audit.** `tools/Test-ScriptInventory.ps1`
  (self-test: `tests/tools/Test-ScriptInventorySelfTest.ps1`) asserts that every file physically
  present under the three script folders is listed exactly once below, and that every file
  listed below still exists. If you add, remove, or rename a script, update its row in the same
  change — the gate fails otherwise.
- When a script changes in a way that affects its contract or public JSON/exit-code shape,
  update its owner doc, not this index; this index only needs its one-line purpose kept accurate.

## Conventions

- **Shared-engine non-deletion rule.** `Sync-GeneXusXpzToXml.ps1` is a shared engine that can be
  consumed by wrappers and local flows of external production projects that keep their own
  versioned XML corpora extracted from `XPZ`. It must not be silently deleted from this public
  repository. Any refactor, relocation, or replacement of the engine must be documented
  explicitly and propagated to external consumers before the previous file is removed.
- **Private traceability.** The maintainers keep editorial traceability between public aliases
  and real artifacts in private notes that are not published. They are maintenance support and
  never substitute for the documentation consolidated in this repository.
- **Public governance docs.** `CHANGELOG.md` records notable changes from changelog adoption
  onward, without reconstructing older versions retroactively. `CONTRIBUTING.md` covers human
  contribution and pre-push review. `SECURITY.md` defines the private channel for vulnerability
  and operational-risk reports. `CODE_OF_CONDUCT.md` defines the applicable code of conduct.
- **Wrapper/engine inventory-audit conventions.** `MimirWrapperEngineParamSupport.ps1`
  (dot-sourced by `Test-MimirWrapperInventory.ps1`) audits, by AST + `Get-Command` (never by executing an engine or
  touching a KB), that every parameter a local wrapper forwards to a shared "advanced" engine
  actually exists on that engine (`forwards_unknown_engine_param`, `shared_engine_unresolved`),
  and separately diffs a wrapper's parameter surface against its `.example.ps1` template
  (`surface_mismatch` for a lost mandatory parameter; `INVENTORY_SURFACE_ADVISORY` for an
  optional reduction). The audit's signal families:
  `INVENTORY_GAPS` (a required wrapper is missing under its canonical name),
  `INVENTORY_RECOMMENDED_MISSING` (a recommended thin wrapper is absent),
  `INVENTORY_CUSTOMIZED` (an objective methodological divergence — including the two forwarding
  signals above and `unsafe_last_exitcode_after_ps1_engine`),
  `INVENTORY_ENGINE_DIAGNOSTIC` (soft diagnostic, does not block), and
  `INVENTORY_SURFACE_ADVISORY` (soft, does not block).

## `skills/mimir-lite/scripts/` (43 files)

| File | Kind | Purpose | Owner doc | Tests |
|---|---|---|---|---|
| `Build-KbIntelligenceIndex.ps1` | engine | PowerShell wrapper invoking `Build-KbIntelligenceIndex.py` to build the KB Intelligence SQLite index from materialized XML, with an optional validation-case run. | `references/kb-index-reference.md`, `workflows/sync.md`, `workflows/setup.md` | 10 self-tests invoke it: the nine `tests/mimir-lite/Test-KbIntelligence*SelfTest.ps1` files and `Test-GeneXusUnknownTypeDiscoverySelfTest.ps1` |
| `Build-KbIntelligenceIndex.py` | engine | Python extractor that parses materialized GeneXus XML and populates the KbIntelligence SQLite schema (objects, relations, formulas, `idBasedOn`, generated-object markers, CSS classes). | `references/kb-index-reference.md` | `tests/mimir-lite/Test-KbIntelligenceProcedureCallFormsSelfTest.ps1`, `Test-KbIntelligenceAttributeFormulaExtractionSelfTest.ps1`, `Test-KbIntelligenceWorkWithForWebAttributeSelfTest.ps1`, `Test-KbIntelligenceIdBasedOnDomainSelfTest.ps1`, `Test-KbIntelligenceExternalObjectMethodExtractionSelfTest.ps1`, `Test-KbIntelligenceCssClassExtractionSelfTest.ps1`, `Test-KbIntelligenceLegacyOrphanSkipSelfTest.ps1`, `Test-KbIntelligenceGeneratedObjectExtractionSelfTest.ps1`, `Test-KbIntelligenceSampleKbSelfTest.ps1` |
| `GeneXusFileBaseNameNormalizationSupport.ps1` | support-library | Defines `Normalize-FileBaseName`, the single canonical filename-sanitization routine shared by Sync and the legacy export converter. | `workflows/sync.md` | `tests/mimir-lite/Test-GeneXusFileBaseNameNormalizationSelfTest.ps1` |
| `GeneXusKbIntelligenceExtractorContract.ps1` | support-library | Computes the expected extractor signature (version + SHA-256 of `Build-KbIntelligenceIndex.py`) used to detect a stale KbIntelligence index. | `references/kb-index-reference.md`, `workflows/find.md`, `workflows/setup.md` | `tests/mimir-lite/Test-GeneXusKbIntelligenceExtractorSignatureSelfTest.ps1`, `Test-MimirSetupAuditContractSelfTest.ps1` |
| `GeneXusLegacyExportFileSupport.ps1` | support-library | Parses/materializes legacy GeneXus 9 `ExportFile` (`/ExportFile/GXObject/<Elemento>`) packages using the legacy element registry, fail-closed on mixed/unknown elements. | `references/01k-legacy-element-registry.md`, `workflows/sync.md` | `tests/mimir-lite/Test-GeneXusLegacyExportFileSupportSelfTest.ps1` |
| `GeneXusObjectTypeCatalogCore.py` | support-library | Python module: loads/merges the base + KB workspace override object-type catalog and classifies override entries; imported by `Build-KbIntelligenceIndex.py` and `Query-KbIntelligenceIndex.py`. | `references/kb-index-reference.md` | `tests/mimir-lite/Test-MimirCatalogOverrideClassificationSelfTest.ps1` |
| `GeneXusObjectTypeCatalogSupport.ps1` | support-library | PowerShell-side shared functions to read/merge `gx-object-type-catalog.json` with a KB workspace local override. | `references/01a-catalog-and-empirical-patterns.md` | `tests/mimir-lite/Test-GeneXusObjectTypeCatalogPuritySelfTest.ps1`, `Test-GeneXusUnknownTypeDiscoverySelfTest.ps1`, `Test-MimirCatalogOverrideClassificationSelfTest.ps1`, `Test-GeneXusLegacyExportFileSupportSelfTest.ps1`, `Test-GeneXusLegacyRegistryDisjointSelfTest.ps1` |
| `GeneXusPlatformObjectsCatalogSupport.ps1` | support-library | Loads `gx-platform-objects.json` and detects packaged-module/external-object platform entries in a package inventory. | none found | `tests/mimir-lite/Test-GeneXusPlatformObjectsCatalogSelfTest.ps1` |
| `GeneXusPythonPrerequisite.ps1` | support-library | Resolves a usable Python 3.8+ (`python3`, then `python`, then `py -3`, each one run), rejecting an empty/`WindowsApps` stub interpreter. | `references/kb-index-reference.md`, `workflows/setup.md`, `workflows/sync.md` | `tests/mimir-lite/Test-GeneXusPythonPrerequisiteSelfTest.ps1` |
| `GeneXusTransactionWritabilityCore.py` | support-library | Python canonical classifier of Transaction attribute writability (key/redundant/formula/subtype rules); imported by `Build-KbIntelligenceIndex.py` to materialize the classification in the index. | `references/kb-index-reference.md` | `tests/mimir-lite/Test-KbIntelligenceSampleKbSelfTest.ps1` (through the `transaction-writable-attributes` query) |
| `Get-GeneXusXpzObjectInventory.ps1` | engine | Inventories objects/attributes actually present in `import_file.xml` or a `.xpz` package and reports unknown types for the sync pre-scan. | `references/01k-legacy-element-registry.md`, `workflows/sync.md` | `tests/mimir-lite/Test-GeneXusXpzObjectInventorySelfTest.ps1`, `Test-GeneXusUnknownTypeDiscoverySelfTest.ps1`, `Test-GeneXusXpzObjectInventoryLegacyExportSelfTest.ps1` |
| `Get-MimirSetupContractSignature.ps1` | engine | Computes a deterministic hash signature over the setup methodology surface (LF-normalized) for setup-freshness comparison. | `workflows/setup.md` | `tests/mimir-lite/Test-MimirSetupContractSignatureSelfTest.ps1` |
| `KbIntelligenceQueryCases.py` | engine | Python case runner behind `Test-KbIntelligenceQueries.ps1`: loads `Query-KbIntelligenceIndex.py` from its own folder and checks each JSON validation case against the index. | `references/kb-index-reference.md` | via `tests/mimir-lite/Test-KbIntelligenceSampleKbSelfTest.ps1` |
| `New-GeneXusUnknownTypeMaintainerPrompt.ps1` | engine | Generates a copy-pasteable maintainer prompt describing an unknown GeneXus object type discovered during sync/inventory. | `references/08-agent-guide.md`, `workflows/sync.md` | none dedicated |
| `New-MimirKbWorkspace.ps1` | engine | Scaffolds a KB workspace from the setup examples (folders, `.gitignore`, prefixed wrappers with placeholders and sibling names resolved, `README.md`, `AGENTS.md`, `kb-source-metadata.md`); validates the KB name and never overwrites an existing file. | `workflows/setup.md` (CREATION BLOCK: the default way to create a workspace); `workflows/setup/setup-contract.manifest.json` | `tests/mimir-lite/Test-NewMimirKbWorkspaceSelfTest.ps1` |
| `Query-KbIntelligenceIndex.ps1` | engine | PowerShell wrapper CLI exposing KbIntelligence SQLite queries (`object-info`, `who-uses`, `impact-basic`, etc.) by invoking `Query-KbIntelligenceIndex.py`. | `references/kb-index-methodology.md`, `references/kb-index-reference.md`, `workflows/find.md` | `tests/mimir-lite/Test-KbIntelligenceGeneratedObjectExtractionSelfTest.ps1`, `Test-KbIntelligenceQueryableGuardSelfTest.ps1` (wrapper path) |
| `Query-KbIntelligenceIndex.py` | engine | Python query engine over the KbIntelligence SQLite index (`impact`/`who-uses`/`what-uses`/`functional-trace`/etc.), consuming `GeneXusObjectTypeCatalogCore` for type/queryability rules. | `references/kb-index-reference.md` | `tests/mimir-lite/Test-KbIntelligenceQueryableGuardSelfTest.ps1`, plus the extraction self-tests listed under `Build-KbIntelligenceIndex.py` |
| `Register-GeneXusObjectTypeCatalogOverride.ps1` | engine | Writes/updates a palliative entry in the local object-type-catalog override, requiring explicit user approval; blocks unsafe shadowing/duplicate-GUID collisions. | `references/01a-catalog-and-empirical-patterns.md` | `tests/mimir-lite/Test-GeneXusUnknownTypeDiscoverySelfTest.ps1`, `Test-MimirCatalogOverrideClassificationSelfTest.ps1` |
| `Resolve-GeneXusKbIdentity.ps1` | engine | Resolves native GeneXus KB identity (reads `model.ini`/internal database) for reconciling KB-workspace metadata, read-only. | `workflows/setup.md` | none dedicated |
| `Search-GeneXusXmlSourceBlock.ps1` | engine | Searches text within `<Source>` blocks of GeneXus XML, classifying blocks (code/events/layout/serialized) to avoid noisy CDATA dumps. | `references/08-agent-guide.md`, `workflows/find.md`, `workflows/read.md` | `tests/mimir-lite/Test-SearchGeneXusXmlSourceBlockSelfTest.ps1` |
| `Set-MimirSetupAuditTimestamp.ps1` | engine | Writes `last_setup_audit_run_at` and the setup-contract signature into `kb-source-metadata.md` after a successful setup audit. | `workflows/setup.md`, `workflows/sync.md` | `tests/mimir-lite/Test-MimirSetupAuditTimestampEolSelfTest.ps1`, `Test-MimirSetupContractSignatureSelfTest.ps1` |
| `Sync-GeneXusXpzToXml.ps1` | engine | Core materialization/verification engine: extracts objects from a `.xpz`/`.xml` export package into a per-type XML tree and can verify reflection, including GUID-rename reconciliation (every incoming item under `-FullSnapshot`; items with no target file yet in a delta). | `workflows/sync.md` | `tests/mimir-lite/Test-GeneXusXpzSyncCrossFlowCollisionSelfTest.ps1`, `Test-GeneXusXpzSyncGuidRenameSelfTest.ps1`, `Test-GeneXusXpzSyncLegacyExportFullSnapshotSelfTest.ps1`, `Test-GeneXusXpzSyncVerifyOnlyMetadataIsolationSelfTest.ps1` |
| `Test-KbIntelligenceQueries.ps1` | engine | CLI wrapper validating KbIntelligence query behavior against JSON validation-case files, invoking the Python query engine. | `references/kb-index-reference.md` | `tests/mimir-lite/Test-KbIntelligenceSampleKbSelfTest.ps1` |
| `Test-MimirCatalogOverrideSessionReminder.ps1` | engine | Read-only reminder/audit of an active local object-type-catalog override (redundant/metadata-only vs. reminder-required states). | `references/01a-catalog-and-empirical-patterns.md` | `tests/mimir-lite/Test-GeneXusUnknownTypeDiscoverySelfTest.ps1`, `Test-MimirCatalogOverrideClassificationSelfTest.ps1` |
| `Test-MimirKbIndexGate.ps1` | engine | Mandatory index gate validating the KbIntelligence index's structure, freshness against materialization, inventory-validation status, and extractor signature before any semantic query. | `workflows/find.md` | `tests/mimir-lite/Test-MimirKbIndexGateContractSelfTest.ps1`, `Test-MimirSetupAuditContractSelfTest.ps1` |
| `Test-MimirKbMetadataWrapper.ps1` | engine | Validates that a local `Get-KbMetadata` wrapper exposes the same `last_xpz_materialization_run_at`, `kb_name`, and `source_guid` values as `kb-source-metadata.md` itself; any other field (including legacy `deployment_*` / `kb_environment_*`) is ignored. | `workflows/setup.md` | `tests/mimir-lite/Test-MimirSetupAuditContractSelfTest.ps1` |
| `Test-MimirKbObjectsXmlNaming.ps1` | engine | Read-only audit comparing each `KbObjectsXml` immediate folder's name against the canonical type inferred from its first classifiable XML; legacy-registry-aware. | `references/01k-legacy-element-registry.md`, `workflows/setup.md` | `tests/mimir-lite/Test-GeneXusUnknownTypeDiscoverySelfTest.ps1`, `Test-MimirKbObjectsXmlNamingLegacyOrphanSelfTest.ps1` |
| `Test-MimirPowerShellRuntime.ps1` | engine | Gate verifying the installed `pwsh` meets the minimum required PowerShell version: 7.4 on Windows, 7.4.6 on Linux and macOS (the `pwsh` found reports its own OS; a lower minimum is raised off Windows). | `workflows/setup.md` | `tests/mimir-lite/Test-MimirPowerShellRuntimeSelfTest.ps1` |
| `Test-MimirSetupAudit.ps1` | engine | Setup-audit aggregator that runs the other setup-audit checks (PowerShell runtime, index gate, naming, metadata wrapper, declarative timestamps, wrapper inventory) and aggregates their text/JSON results. | `workflows/setup.md` | `tests/mimir-lite/Test-MimirSetupAuditContractSelfTest.ps1`, `Test-MimirWrapperInventorySelfTest.ps1` |
| `Test-MimirSetupFreshness.ps1` | engine | Compares the last successful setup-audit contract signature stored in metadata against the current computed signature; returns `GATE_ONLY`/`AUDIT_REQUIRED`. | `workflows/setup.md` | `tests/mimir-lite/Test-MimirSetupContractSignatureSelfTest.ps1` |
| `Test-MimirSkillsRegistration.ps1` | engine | Read-only audit of this repository's skills (`mimir-lite`, `mimir-delegate`) registered across installed agent tools (Codex/Claude Code/OpenCode/Cursor/Antigravity). | `workflows/install.md` | `tests/mimir-lite/Test-MimirSkillsRegistrationSelfTest.ps1` |
| `Test-MimirWrapperInventory.ps1` | engine | Compares a KB workspace's local wrappers against the canonical skill examples, flagging gaps/customization/recommended wrappers — see "Conventions" above. | `workflows/setup.md` | `tests/mimir-lite/Test-MimirWrapperInventorySelfTest.ps1` |
| `Update-MimirDocSection.ps1` | engine | Rewrites/inserts a named Markdown section with XML example code fences into a target documentation file. | `workflows/docs.md` | `tests/mimir-lite/Test-MimirDocSectionFormattingSelfTest.ps1` |
| `Update-MimirKbSourceMetadataIdentity.ps1` | engine | Writes/reconciles native KB identity fields (from `model.ini`/internal database) into `kb-source-metadata.md`, guarding against a silent identity overwrite. | `workflows/setup.md` | none dedicated |
| `Utf8NoBomEncodingSupport.ps1` | support-library | Defines `Get-Utf8NoBomEncoding`, the single BOM-less UTF-8 encoding helper every writer/self-test in this repository should reuse instead of constructing its own encoding. | none (cross-cutting helper; no single workflow owns it) | none dedicated — exercised indirectly by dozens of self-tests across all three script folders |
| `MimirKbSourceMetadataEditSupport.ps1` | support-library | Surgical mutation of `kb-source-metadata.md` under sync authority (frontmatter + `KMW`/`Source` table fields only; preserves the rest of the file); legacy-export `-IsLegacyExport` branch. | `workflows/sync.md` | `tests/mimir-lite/Test-MimirKbSourceMetadataLegacySelfTest.ps1`, `Test-MimirKbSourceMetadataSyncSelfTest.ps1` |
| `MimirTextFileEolSupport.ps1` | support-library | Read/write helpers preserving the original EOL style and trailing-newline presence, avoiding a CRLF rewrite of an LF-policy file. | `workflows/sync.md` | `tests/mimir-lite/Test-MimirSetupContractSignatureSelfTest.ps1`; also exercised via `Test-MimirSetupAuditTimestampEolSelfTest.ps1` and metadata-editing consumers |
| `MimirWrapperEngineParamSupport.ps1` | support-library | Dot-sourced AST/`Get-Command`-based checks used by `Test-MimirWrapperInventory.ps1` — see "Conventions" above. | `workflows/setup.md` | `tests/mimir-lite/Test-MimirWrapperEngineParamSupportSelfTest.ps1`, `Test-MimirWrapperEngineParamTemplatesSelfTest.ps1`, `Test-MimirWrapperInventorySelfTest.ps1` |
| `generate-kb-advanced-docs.ps1` | engine | Generates advanced Markdown documentation tables from a materialized KB XML tree. | `workflows/docs.md` | `tests/mimir-lite/Test-GenerateKbAdvancedDocsReadOnlySelfTest.ps1` |
| `generate-kb-inventory.ps1` | engine | Generates a Markdown inventory table of KB objects from a materialized KB XML tree. | `workflows/docs.md` | `tests/mimir-lite/Test-GenerateKbInventorySelfTest.ps1` |
| `gx-legacy-export-element-registry.json` | catalog | Registry (`schemaVersion` 1) classifying legacy GeneXus 9 `ExportFile` element names as `equivalent` (maps to a modern catalog type) or `orphan` (no modern equivalent). | `references/01k-legacy-element-registry.md` | `tests/mimir-lite/Test-GeneXusLegacyRegistryDisjointSelfTest.ps1`, `Test-GeneXusLegacyRegistrySchemaSelfTest.ps1`, `Test-KbIntelligenceLegacyOrphanSkipSelfTest.ps1`, `Test-MimirKbObjectsXmlNamingLegacyOrphanSelfTest.ps1` |
| `gx-object-type-catalog.json` | catalog | Base catalog mapping each GeneXus object type to its `objectTypeGuid`, `rootKind`, `folderName`, inventory/queryability flags, and container-type marker. | `references/01a-catalog-and-empirical-patterns.md` | `tests/mimir-lite/Test-GeneXusObjectTypeCatalogPuritySelfTest.ps1`, `Test-GeneXusUnknownTypeDiscoverySelfTest.ps1`, `Test-GeneXusLegacyExportFileSupportSelfTest.ps1` |
| `gx-platform-objects.json` | catalog | Catalog of GeneXus platform/SDK objects (`packagedModule` vs `externalObject` kind) used to classify package-inventory entries. | none found | `tests/mimir-lite/Test-GeneXusPlatformObjectsCatalogSelfTest.ps1` |

## `skills/mimir-delegate/scripts/` (30 files)

| File | Kind | Purpose | Owner doc | Tests |
|---|---|---|---|---|
| `AntigravityCliSupport.ps1` | support-library | Shared helpers for the Antigravity (`agy`) backend: resolve the `agy` CLI, validate the `--print`/`--mode` contract, classify quota/auth failures from raw `stderr`+`stdout`. | `SKILL.md` | `tests/mimir-delegate/Test-AntigravityCliSupportSelfTest.ps1` |
| `Build-LlmDelegateCapabilityManifest.ps1` | engine | Probes installed LLM CLI backends (opencode, Codex, Claude Code, Copilot, Gemini, Antigravity) and writes a sanitized machine-level capability manifest (backend/model/locality, no secrets); single owner, also used by the optional capability-snapshot step in `mimir-lite`'s `workflows/setup.md`. | `SKILL.md`, `skills/mimir-lite/workflows/setup.md` | `tests/mimir-delegate/Test-LlmDelegateCapabilityManifestSelfTest.ps1` |
| `ClaudeCodeCliSupport.ps1` | support-library | Shared helpers for the `claude-code` backend: resolve the `claude` executable, strip Claude Code environment noise from `stderr`, extract/classify error messages. | `SKILL.md` | `tests/mimir-delegate/Test-ClaudeCodeCliSupportSelfTest.ps1` |
| `CodexCliSupport.ps1` | support-library | Shared helpers for the `codex` backend: fail-closed discovery of the Codex CLI (app binaries on Windows, `codex` on `PATH` elsewhere), `TempDir`/`KeepDays` resolution, PID/start-time identity. | `SKILL.md` | `tests/mimir-delegate/Test-CodexCliSupportSelfTest.ps1`, `Test-CodexDurableCaptureSelfTest.ps1` |
| `CopilotCliSupport.ps1` | support-library | Shared helpers for the `copilot` backend: resolve the `copilot` command, validate the required CLI flag contract, parse version text. | `SKILL.md` | `tests/mimir-delegate/Test-CopilotCliSupportSelfTest.ps1` |
| `GeminiCliSupport.ps1` | support-library | Shared helpers for the `gemini` backend: resolve the `gemini` command, validate the `--prompt`/`--approval-mode`/`--output-format`/`--model` contract. | `SKILL.md` | `tests/mimir-delegate/Test-GeminiCliSupportSelfTest.ps1` |
| `Invoke-Antigravity.ps1` | engine | Synchronous adapter calling the Antigravity CLI in the fixed `public-review` profile (disposable scratch cwd, plan mode, JSON output). | `SKILL.md` | `tests/mimir-delegate/Test-AntigravityCliSupportSelfTest.ps1`, `Test-AntigravityPublicReviewSelfTest.ps1`, `Test-LlmDelegateStdinHandlingSelfTest.ps1` |
| `Invoke-ClaudeCode.ps1` | engine | Synchronous adapter calling Claude Code (`claude -p`) via stdin, read-only tools + plan permission mode by default. | `SKILL.md` | `tests/mimir-delegate/Test-ClaudeCodeCliSupportSelfTest.ps1`, `Test-LlmDelegateStdinHandlingSelfTest.ps1` |
| `Invoke-ClaudeCodeAsync.ps1` | engine | Typed async Claude Code adapter used by the panel dispatcher: `stream-json` output, atomic technical JSON sidecar, only emits accepted final text to stdout. | `SKILL.md` | `tests/mimir-delegate/Test-ClaudeCodeAsyncSelfTest.ps1` |
| `Invoke-Codex.ps1` | engine | Synchronous Codex adapter (`codex exec`) via stdin/output-last-message file with JSONL stream capture and timeout-recovery of the last message. | `SKILL.md` | `tests/mimir-delegate/Test-CodexDurableCaptureSelfTest.ps1`, `Test-LlmDelegateStdinHandlingSelfTest.ps1` |
| `Invoke-Copilot.ps1` | engine | Synchronous adapter calling GitHub Copilot CLI (`copilot -p`) in JSONL mode with custom instructions/MCP/tools disabled. | `SKILL.md` | `tests/mimir-delegate/Test-LlmDelegateStdinHandlingSelfTest.ps1` |
| `Invoke-Gemini.ps1` | engine | Synchronous adapter calling the Gemini CLI (`gemini -p --approval-mode plan --output-format json`). | `SKILL.md` | `tests/mimir-delegate/Test-GeminiCliSupportSelfTest.ps1`, `Test-LlmDelegateStdinHandlingSelfTest.ps1` |
| `Invoke-LlmDelegatePanelDispatch.ps1` | engine | Mechanical dispatch/collection harness: fires each reviewer through the `Invoke-*.ps1` adapters concurrently, applies per-backend arg allowlist + the confidentiality gate, emits one `panel-summary.json` line. | `SKILL.md`, `docs/process/15-peer-review.md` | `tests/mimir-delegate/Test-InvokeLlmDelegatePanelDispatchSelfTest.ps1` |
| `Invoke-OpenCode.ps1` | engine | Synchronous adapter calling `opencode` with the prompt via stdin (avoids the Windows ~32 KB argv cap); classifies usage-limit timeouts. | `SKILL.md` | `tests/mimir-delegate/Test-OpenCodeInvokeLimitSelfTest.ps1`, `Test-OpenCodeRetrySelfTest.ps1`, `Test-LlmDelegateStdinHandlingSelfTest.ps1` |
| `LlmDelegateStatePath.ps1` | support-library | Resolves the `mimir-delegate` state folder on every OS (local application data folder plus `mimir-delegate`; `XDG_DATA_HOME` or `HOME/.local/share` when that folder does not exist yet outside Windows). | `SKILL.md` | `tests/mimir-delegate/Test-LlmDelegateStatePathSelfTest.ps1` |
| `LlmDelegateTargetFamilySupport.ps1` | support-library | Resolves the Model Creator / structural family from a `targetModelKey` (collapses aggregator paths, e.g. `nvidia/<creator>/<model>`) for the diversity floor. | `SKILL.md`, `docs/process/15-peer-review.md` | exercised via `tests/mimir-delegate/Test-LlmDelegatePanelDiversitySelfTest.ps1` |
| `New-LlmDelegatePeerReviewArtifacts.ps1` | engine | Transactionally prepares peer-review round artifacts (manuscript + reviewers JSON) in a staging dir, then atomically publishes; never calls the dispatcher itself. | `SKILL.md`, `docs/process/15-peer-review.md` | `tests/mimir-delegate/Test-NewLlmDelegatePeerReviewArtifactsSelfTest.ps1` |
| `OpenCodeCliSupport.ps1` | support-library | Shared helpers to discover/validate the `opencode` CLI (override, PATH via WinGet/Scoop, legacy npm install) and read its version. | `SKILL.md` | `tests/mimir-delegate/Test-OpenCodeCliSupportSelfTest.ps1` |
| `OpenCodeStreamSupport.ps1` | support-library | Shared JSONL stream parsing for `opencode` events (text/tool_use/error) plus provider usage-limit/rate-limit detection from the log. | `SKILL.md` | `tests/mimir-delegate/Test-OpenCodeStreamSupportSelfTest.ps1`, `Test-OpenCodeUsageLimitDetectionSelfTest.ps1`, `Test-OpenCodeInvokeLimitSelfTest.ps1`, `Test-OpenCodeRetrySelfTest.ps1` |
| `Resolve-AntigravityModelLocality.ps1` | engine | Classifies an Antigravity invocation as always-external; emits the canonical `antigravity/<model>` destination key. | `SKILL.md` | `tests/mimir-delegate/Test-AntigravityModelLocalitySelfTest.ps1` |
| `Resolve-ClaudeCodeModelLocality.ps1` | engine | Classifies a Claude Code invocation as external (Anthropic), normalizes the `opus` alias, emits the canonical `anthropic/<model>` destination key. | `SKILL.md` | `tests/mimir-delegate/Test-ClaudeCodeModelLocalitySelfTest.ps1` |
| `Resolve-CodexModelLocality.ps1` | engine | Deterministically classifies a Codex invocation as local/external/unknown from the resolved provider `base_url`. | `SKILL.md` | `tests/mimir-delegate/Test-CodexModelLocalitySelfTest.ps1` |
| `Resolve-CopilotModelLocality.ps1` | engine | Classifies a Copilot CLI invocation as always-external; emits the canonical `github-copilot/<model>` destination key. | `SKILL.md` | `tests/mimir-delegate/Test-CopilotModelLocalitySelfTest.ps1` |
| `Resolve-GeminiModelLocality.ps1` | engine | Classifies a Gemini CLI invocation as always-external; emits the canonical `google/<model>` destination key. | `SKILL.md` | `tests/mimir-delegate/Test-GeminiModelLocalitySelfTest.ps1` |
| `Resolve-LlmDelegateAuthorization.ps1` | engine | Backend-agnostic confidentiality gate: combines declared payload sensitivity, resolved model locality, and per-KB policy into an allow/ask/deny verdict. | `SKILL.md`, `docs/process/15-peer-review.md`, `skills/mimir-lite/workflows/setup.md` | `tests/mimir-delegate/Test-LlmDelegateAuthorizationSelfTest.ps1` |
| `Resolve-LlmDelegatePanelDiversity.ps1` | engine | Consultatively evaluates whether a reviewer candidate set meets the diversity floor (≥2 distinct model-creator families), including fallback-evidence handling. | `SKILL.md`, `docs/process/15-peer-review.md` | `tests/mimir-delegate/Test-LlmDelegatePanelDiversitySelfTest.ps1` |
| `Resolve-LlmDelegatePeerReviewCloseout.ps1` | engine | Deterministic gate verifying a peer-review round can close only after the mandatory preferred-reviewers-save offer was made/resolved (skipped with a warning when no state folder resolves and no `-ProposedPreferredPath` is given); never writes preferences itself. | `SKILL.md`, `docs/process/15-peer-review.md` | `tests/mimir-delegate/Test-LlmDelegatePeerReviewCloseoutSelfTest.ps1` |
| `Resolve-LlmDelegatePreferredReviewers.ps1` | engine | Reads the curated preferred-reviewers list (schema 3) via orchestrator→machine cascade and cross-references it against the capability manifest. | `SKILL.md`, `docs/process/15-peer-review.md`, `skills/mimir-lite/workflows/install.md` | `tests/mimir-delegate/Test-LlmDelegatePreferredReviewersSelfTest.ps1` |
| `Resolve-OpenCodeModelLocality.ps1` | engine | Deterministically classifies an `opencode` model as local/external/unknown by checking the provider `baseURL` for loopback. | `SKILL.md` | `tests/mimir-delegate/Test-OpenCodeModelLocalitySelfTest.ps1` |
| `Resolve-OrchestratorNativeModelLocality.ps1` | engine | Classifies locality of an orchestrator-native (native subagent) destination by `targetModelKey` creator; by design never returns `local`. | `SKILL.md` | `tests/mimir-delegate/Test-ResolveOrchestratorNativeModelLocalitySelfTest.ps1` |
| `Set-LlmDelegatePreferredReviewers.ps1` | engine | Writes the curated preferred-reviewers list (schema 3) at machine or orchestrator scope, with overwrite/shadowing diagnostics. | `SKILL.md`, `docs/process/15-peer-review.md`, `skills/mimir-lite/workflows/install.md` | `tests/mimir-delegate/Test-LlmDelegatePreferredReviewersSelfTest.ps1` |

## `tools/` (17 files)

Repository-maintainer/CI tooling — not part of either skill's payload, but shared across both.

| File | Kind | Purpose | Owner doc | Tests |
|---|---|---|---|---|
| `Build-PrePushReviewDossier.ps1` | engine | Assembles the pre-push dossier for a semantic-only reviewer: raw git facts (Section A) + `Invoke-PrePushMechanicalChecks.ps1 -AsJson` output (Section B), plus sentinel/SHA-256 anti-truncation lines. | `docs/process/13-pre-push-review.md` | `tests/tools/Test-BuildPrePushReviewDossierSelfTest.ps1` |
| `Invoke-PrePushMechanicalChecks.ps1` | engine | Main pre-push orchestrator: resolves git context, delegates PS/Python parse, runs every consultative gate, classifies changed files, and consolidates `pushReadiness`. | `docs/process/13-pre-push-review.md` | `tests/tools/Test-InvokePrePushMechanicalChecksBaseRefFallbackSelfTest.ps1` (covers the `origin/main`→local `main` `BaseRef` fallback), `Test-PrePushGateEnumerationParitySelfTest.ps1` |
| `PrePushGitSupport.ps1` | support-library | Dot-sourced by `Invoke-PrePushMechanicalChecks.ps1`: runs git with strict UTF-8 decoding and parses its output with blank lines preserved, so paired `git diff --check` diagnostics stay intact; it suppresses nothing. | `docs/process/13-pre-push-review.md` | `tests/tools/Test-PrePushGitSupportSelfTest.ps1` |
| `Show-FileWhitespace.ps1` | engine | Read-only helper rendering tabs/spaces/EOL/BOM/encoding of a file window before a surgical edit. | `AGENTS.md` | none |
| `Test-CodeLanguage.ps1` | engine | Gate flagging pt-BR words (accented characters or a common function-word list) in `.ps1`/`.py` files under `skills/*/scripts`, `skills/*/workflows`, `tools`, `tests` (skipping `tests/fixtures/`), honoring an inline `lang-allow <reason>` marker. | `.github/workflows/ci.yml`, `CONTRIBUTING.md` | `tests/tools/Test-CodeLanguageSelfTest.ps1` |
| `Test-GeneXusUnexpectedCharacter.ps1` | engine | Consultative gate (always exit 0, `severity=warn`) flagging Unicode characters outside pt-BR/es/en in added `.md`/`.ps1` diff lines, skipping fenced code. | `docs/process/13-pre-push-review.md` | none dedicated (wired into `Invoke-PrePushMechanicalChecks.ps1`) |
| `Test-MarkdownFences.ps1` | engine | Gate verifying fenced code blocks in `.md` files are CommonMark-balanced; flags a malformed closer or an unclosed fence. | `.github/workflows/ci.yml`, `CONTRIBUTING.md` | `tests/tools/Test-MarkdownFencesSelfTest.ps1` |
| `Test-MarkdownLinks.ps1` | engine | Gate resolving relative markdown links, bare `NN-*.md` mentions, and `#anchor` fragments against real files/headings. | `.github/workflows/ci.yml`, `AGENTS.md`, `CONTRIBUTING.md` | `tests/tools/Test-MarkdownLinksSelfTest.ps1` |
| `Test-PrePushBackendEnumerationParity.ps1` | engine | Consultative gate: derives the canonical delegation-backend set from the dispatcher's own AST and flags doc prose enumerating an incomplete proper subset. | `docs/process/13-pre-push-review.md`, `docs/process/14-reinforced-pre-push-review.md` | `tests/tools/Test-PrePushBackendEnumerationParitySelfTest.ps1` |
| `Test-PrePushGateEnumerationParity.ps1` | engine | Consultative gate: derives the real gate set the orchestrator invokes and flags a doc line enumerating an outdated proper subset. | `docs/process/13-pre-push-review.md` | `tests/tools/Test-PrePushGateEnumerationParitySelfTest.ps1` |
| `Test-PrePushNewTokenPropagation.ps1` | engine | Consultative gate detecting a contract token newly introduced alongside an existing alias in a diff hunk that is missing from other repo mentions of that alias. | `docs/process/13-pre-push-review.md` | `tests/tools/Test-PrePushNewTokenPropagationSelfTest.ps1` |
| `Test-PrePushSharedScriptSkillCoverage.ps1` | engine | Consultative gate: for a shared script changed in the diff, flags `SKILL.md`/checklist docs citing it that were not touched in the same change. | `docs/process/13-pre-push-review.md` | `tests/tools/Test-PrePushSharedScriptSkillCoverageSelfTest.ps1` |
| `Test-PrePushTraceabilityCoverage.ps1` | engine | Consultative gate surfacing objective editorial-traceability risk zones against this document (missing script mention, missing token, aggregated-role risk, verbose-entry regression) for the agent to justify. | `docs/process/13-pre-push-review.md` | `tests/tools/Test-PrePushTraceabilityCoverageSelfTest.ps1` |
| `Test-PsScriptsParse.ps1` | engine | Syntax-only gate parsing every `.ps1` under `skills/`, `tools/`, `tests/` plus every `*.example.ps1`. | `docs/process/13-pre-push-review.md`, `.github/workflows/ci.yml` | none dedicated (wired into the orchestrator and CI) |
| `Test-ScriptInventory.ps1` | engine | Mechanical completeness gate: every file under the three script folders is listed exactly once in this document's tables, and every listed entry still exists on disk. | this document (see "How to use this document" above), `.github/workflows/ci.yml` | `tests/tools/Test-ScriptInventorySelfTest.ps1` |
| `Test-PyScriptsParse.ps1` | engine | Syntax-only gate parsing every `.py` under `skills/`, `tools/`, `tests/` via `ast.parse`, avoiding `py_compile`/`.pyc` generation. | `docs/process/13-pre-push-review.md`, `.github/workflows/ci.yml` | none dedicated (wired into the orchestrator and CI) |
| `Test-TextEncoding.ps1` | engine | Gate checking every tracked text file is UTF-8 without BOM and LF-only. | `.github/workflows/ci.yml`, `AGENTS.md` | `tests/tools/Test-TextEncodingSelfTest.ps1` |

## Public aliases and family templates

Public aliases for report `Procedure` templates (`PRCRelatorioExemploF1`-`F5`), their structural
family, and the criterion used to pick each representative, are documented in
`05b-procedure-and-report-families-and-templates.md`, which is the sole owner of that
content.
