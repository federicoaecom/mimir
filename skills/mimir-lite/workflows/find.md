# Find workflow

Uses a derived index of the GeneXus KB as the initial discovery/triage step. Helps the caller quickly find where to start, cutting down broad XML corpus scans while preserving `KbObjectsXml` as the final normative source.

## FIRST-QUESTION CHECKLIST

Decide both items at the first question this workflow answers in a session. The literal command form applies to every script call from the first one, the gate included; the session-folder notice is said once, in the first answer, after the gate has run:

- [ ] **Session-folder notice.** When this session was not started in the KB workspace folder and the workspace has allow rules from the **setup** workflow (step 20; for Claude Code, `<KbWorkspace>/.claude/settings.json`), say once, in the first answer, that those rules apply only to a session started in the workspace folder, so permission prompts for the workspace wrappers will continue in this session; offer to reopen the agent tool in the KB workspace folder. Do not repeat it on later questions.
- [ ] **Literal command form.** Every script call, the gate included, uses the form in [Running scripts](../SKILL.md#running-scripts): one line, the literal absolute path in double quotes, no variables, no pipes, no `cd ... &&` prefix or other compound command, one script call per command. Read the output in your own reasoning, never through `| python`, `| tail`, or a similar filter.

---

## PURPOSE

Use the derived index as the initial triage trail before expanding into the official XML corpus. This workflow runs the initial index query and steers the caller toward opening the smallest necessary set of XML files.

The index is a derived artifact. It never replaces the official XML and never authorizes an automatic functional conclusion on its own.

In flows triggered by a button, link, action or event, a plausible-sounding WebPanel or popup name is not sufficient evidence that it is the real target executed by the flow. The caller object must be resolved before any official-corpus read or analysis of the target object (see **Navigation target resolution** below). This resolution and a successful `GATE_OK` authorize read-side triage only; they never authorize editing GeneXus objects. Generating, cloning, packaging, building, or importing GeneXus objects remains out of scope regardless of gate status.

Before using the index for triage, the check via `Test-*KbIndexGate.ps1` is mandatory. The check verifies, in order: workspace structure via `Test-*KbStructure.ps1`; existence of the `KbIntelligence` folder and its SQLite file; inventory semantics and freshness via `index-metadata`; existence of `kb-source-metadata.md` and its `last_xpz_materialization_run_at` field; a timestamp comparison; and `extractor_signature_version`/`extractor_signature_hash` in the SQLite metadata against the shared engine (`scripts/GeneXusKbIntelligenceExtractorContract.ps1` + `scripts/Build-KbIntelligenceIndex.py`). Do not perform manual freshness, semantic, extractor-signature or structure verification — every check is encapsulated in the gate script, the only authorized execution point. If `Test-*KbIndexGate.ps1` does not exist in `scripts/`, treat this as a structural block equivalent to a `BLOCK:` from the script itself — close the business question and offer an update via the **setup** workflow; never compensate with manual verification, a direct index query, or any other alternative.

- if the check returns `GATE_OK`, the index is fit for initial triage
- if it returns `BLOCK: <reason>`, treat the index as stale/incompatible

The check is mandatory even for simple existence questions — a stale index can return a false negative or false positive even for `search-objects`; the simplicity of the question does not remove the risk of a wrong answer.

A stale index, a missing `last_xpz_materialization_run_at`, or a local wrapper without `index-metadata` support is a blocking gate for broad search, substantive triage, substantive queries against the official object corpus, and official object XML reads. Treat this state as an operational exception, usually signaling a KB workspace whose XPZ wrappers are not yet updated, or a transient failure. Offer the user an update via the **setup** workflow before proceeding. In this state, run only minimal diagnosis to explain the incompatibility, restricted to local documentation, structure, wrappers, and operational metadata; never compensate by manually reading validation JSON, the raw SQLite file, an isolated `kb-source-metadata.md`, file dates, `updated`, `generated_at`, `source_xpz`, official object XML, a guessed path under `KbObjectsXml`, or a scan of `KbObjectsXml`.

If the KB workspace is not yet mounted, validated or mapped, stop and use the **setup** workflow before depending on local paths.

Run the check as atomic, sequential steps. The first atomic step is the structure check via `Test-*KbStructure.ps1`. Each step may only consult its own artifact after the previous step has passed. In particular, do not test, list or open child paths such as `KbIntelligence\kb-intelligence.sqlite` before confirming the structure is `STRUCTURE_OK`. If the structure check fails, report only that first block and close the business question. If the documented local wrapper is missing, do not search for variants, backups or similarly named files; report only the expected missing wrapper and offer an update via the **setup** workflow.

After `index-metadata` passes, validate `kb-source-metadata.md` in two atomic steps: first confirm the file exists; only then look for the literal field `last_xpz_materialization_run_at`. If the file is missing, block on the missing file without looking for the field. If the field is missing, block on the missing field without inferring freshness from other metadata. Do not interleave `Get-Date` between the check's internal steps; get the local time only when a reply or an operational record states a time.

## PATH RESOLUTION

- Resolve every `../references/<file>.md` reference relative to the directory of this file (`skills/mimir-lite/workflows/`), not relative to the current working directory.

---

## TRIGGERS

Use this workflow for:
- A question about the direct technical impact of an object
- A question about who uses an object, or what an object uses
- A question about evidence of a relationship between GeneXus objects
- A short functional question that needs initial triage before reading the official XML
- Deciding which official XMLs should be opened first
- Reducing a broad scan of the `KbObjectsXml` corpus
- Identifying which object is actually opened or executed by an action, button, link or event on a GeneXus screen ("what popup does this button open?", "what object does event X call?", "what opens when I click Y?")

Do NOT use this workflow for:
- Structural reading of a raw, isolated XML without depending on the index (use **read**)
- Generating, cloning or packaging XML/XPZ — out of scope for this skill
- Syncing XPZ (use **sync**)
- Documentation as the primary goal (use **docs**)
- Maintaining, regenerating or evolving the index as the primary focus
- A complete functional conclusion with no read of the official XML, when the question requires GeneXus semantics

---

## RESPONSIBILITIES

- Detect whether the active KB exposes `KbIntelligence\kb-intelligence.sqlite`
- Read the target repository's local `README.md` and `AGENTS.md` before depending on the index
- Locate, from the target repository's local documentation, the index-query wrapper for the active environment
- Check `last_index_build_run_at` against `last_xpz_materialization_run_at` before the first substantive query
- Prefer `index-metadata` on the local wrapper when available, to read the SQLite metadata
- If `index-metadata` exists but fails, returns empty, or does not expose `last_index_build_run_at` or `inventory_validation_status`, treat the index as having no valid metadata; do not proceed with substantive triage before offering a regeneration/validation
- If `kb-source-metadata.md` does not literally expose `last_xpz_materialization_run_at`, treat this as incompatible materialization metadata; do not infer freshness from file date, `updated`, `generated_at`, `source_xpz` or other fields
- If the local wrapper does not accept `index-metadata`, declare this precisely as a gap in the local wrapper's exposure, not a gap in the shared engine; abort the business question and offer an update via the **setup** workflow
- Translate the user's question into the most useful index query
- Choose among queries such as: `object-info`, `attribute-info`, `search-objects`, `list-by-type`, `transaction-attributes`, `transaction-writable-attributes`, `who-uses`, `what-uses`, `show-evidence`, `impact-basic`, `functional-trace-basic`, `css-classes`, `css-class-usage`
- When the question or request is anchored in a navigation flow ("on this screen I click X", "the popup opened by Y", "the object called by event Z"), run the mandatory **navigation target resolution** sub-flow before any official-corpus read or analysis:
  1. Identify the caller object named by the user
  2. Locate the real event or action in the caller's XML (`Event`, `Action`, `Link`, `Window.Object`, `Create(...)`, `formatLink`, `context.NewWindow`, generated URL)
  3. Resolve the object actually opened or executed
  4. When more than one target is plausible, state the ambiguity explicitly and confirm the target with the user before proceeding
  5. Produce the auditable target-resolution handoff block (see COMMUNICATION) before allowing any official-corpus read or analysis

### Locating with the index and disambiguating candidates

- To locate an object, dependency, or starting read point, prefer index queries (`search-objects`, `object-info`, `who-uses`, `what-uses`, etc.) after `GATE_OK`; the index exists to reduce broad XML scans and path errors.
- For impact analysis, callers, callees and cross-object references, do not use raw `rg`/`grep` as the basis for a conclusion when the index is usable. The required path is `impact-basic`/`who-uses`/`what-uses`, and for one specific relationship, `show-evidence` or reading the official XML at the right block.
- Before `who-uses`, `what-uses`, `impact-basic` or `functional-trace-basic`, check the effective catalog (`scripts/gx-object-type-catalog.json` + local override) for whether the type has `queryableByKbIntelligence=true`; when the effective catalog resolves this flag to `false`, the semantic query returns a blocked result (`blocked=true`, reason `QUERY_NOT_SEMANTIC_FOR_TYPE`) with exit `11` — **never** read this as "zero dependencies"; use `object-info`, `search-objects`, `list-by-type` or a targeted XML read (listed in the result) instead. An invalid or unresolvable catalog override is a separate block: it returns an override diagnostic such as `INVALID_OVERRIDE_SHAPE` or `OVERRIDE_RESOLUTION_BLOCKED` with exit `2`, not a zero-dependencies result.
- `who-uses`, `impact-basic`, `functional-trace-basic` and `object-info` return a `coverage` object (JSON) and, in `text`, one `coverage: incomplete` line when the index holds objects of a type whose code or bindings reference other objects but are not extracted (the answer names those types; the list is in `kb-index-reference.md`). With `coverage.complete=false`, callers of those types can be missing from the answer: treat an empty or short caller list as partial, and when the question depends on it, confirm with a targeted literal search in the XML of the listed types. For an `Attribute` target, `coverage.scope` is `attribute_references`: besides structural relations (Transaction levels, Table keys and indexes), the index holds `WorkWithForWeb` attribute references in grids, filters, orders, views and filter conditions and mobile `WorkWith` attribute references in layouts, orders, search, break by and filters (`workwith_references_attribute`) and attribute uses in the code of `Procedure` (Source, rules), `WebPanel`, `Transaction` and, since extractor 20, `WorkPanel` (rules, events) and `DataProvider` (Source, rules), and, in classic exports (GeneXus 7.5 to 9 and `.xpw`), the code of a `Report`, `Procedure`, `WebPanel`, `Transaction`, or `WorkPanel` (a `<Source>` inside a `<CodeBlock>`, rules, events; see "Classic exports (GeneXus 7.5 to 9)" in `kb-index-reference.md`) (`code_references_attribute`, with an `evidence_role` ending in `read` or `write`: `write` only for an unambiguous assignment target, inside `for each` and `new` blocks, in a Transaction assignment rule, or as an item of a DataProvider whose output is a Transaction; any other assignment is reported as a read); attribute uses in conditions, layouts, WebForms, Business Component members, SDT-output DataProvider items, code outside a Part (other than that classic code), and in the formulas, grids and filters of other types are never in the answer. Those partly extracted types are then listed in `coverage.partially_extracted_source_types` (with `extracted` and `missing`), not in `coverage.unextracted_source_types`. Coverage counts only indexed objects: in a classic or `.xpw` KB, the skipped `Menu`, `Prompt`, and `Formula` objects and the `Subroutines` and `Conditions` blocks are not counted, so search the `Menu/`, `Prompt/`, and `Formula/` folders literally when the question depends on them. See `kb-index-reference.md`, section "Coverage of reverse-relation answers".
- Types with `queryableByKbIntelligence=true` and an asymmetric graph (`API`, `DataSelector`, `WorkWithForWeb`, `ExternalObject`): see `kb-index-reference.md` — `impact-basic` with only sparse outputs or inputs can be a valid answer. The mobile `WorkWith` is `false` (its calls are not extracted); its attribute references still appear in the `who-uses` of the `Attribute`. For both Work With types, always classify by GUID; historical names can be ambiguous.
- For `ExternalObject`, distinguish a declarative reference via `ATTCUSTOMTYPE` from actual use via a method call on an `exo:<ExternalObject>` variable; when the question is "who touches/uses this external object", prefer `who-uses` and check `extractor_rule`/`show-evidence` before concluding the kind of use.
- For a question about attributes (their type, length, formula, domain, or other properties), try the query first: `attribute-info` for each attribute, `transaction-attributes` for a Transaction's attributes. Search or open the attribute XML only for what the query does not return, never before trying it.
- The index never replaces an XML read when the question depends on content not represented in the index (a literal `Source`/`Rules` fragment, an exact error message, GeneXus semantics in the XML). In these cases, after the minimal index query when it still helps, a targeted textual search over the official corpus is acceptable — only with `GATE_OK` and without an unnecessary broad scan.
- For a targeted textual search in `WebPanel` XML, avoid raw `rg`/`grep` when the question is about an event, call, validation, filter or flow; use `scripts\Search-GeneXusXmlSourceBlock.ps1 -Block events` or an equivalent structured extraction first, to avoid confusing a match inside `GxMultiForm` layout with actual code-behind.
- When the agent already knows the official XML's name and path and the task is only to read or analyze that file, repeating `search-objects` is not required; still, if a literal-fragment text search returns more than one file, apply disambiguation before opening a single XML.
- When the index or a targeted text search returns **more than one** plausible candidate, list **all of them**, cross-check against the user's clues (action, button, event, named Procedure/WebPanel, tokens in the file name, declared flow), state an **explicit recommendation with a reason**, and **confirm with the user** before opening an XML or answering as if the target were settled.
- Run the appropriate initial triage.
- Do not run a substantive index query before `GATE_OK`; `search-objects`, `list-by-type`, `object-info`, `attribute-info`, `transaction-attributes`, `transaction-writable-attributes`, `who-uses`, `what-uses`, `show-evidence`, `impact-basic`, `functional-trace-basic`, `css-classes` and `css-class-usage` may only run after the gate is cleared.
- After `GATE_OK`, go straight to the minimal substantive query needed; do not open `kb-index-reference.md`, list `scripts`, or re-inspect the local wrapper when the question is already answerable with a simple query like `search-objects`, `object-info`, `attribute-info`, `transaction-attributes` or `transaction-writable-attributes`.
- For a simple existence/nominal-location question, a type listing, or a single attribute query (`attribute-info`) or materialized writability query (`transaction-attributes`, `transaction-writable-attributes`), this workflow is sufficient to pick the minimal query; use the parameters documented in **QUERY PARAMETER REFERENCE**; do not open the wrapper just to "confirm the signature" before calling one of those queries.
- Return a short, auditable technical reading, scoped to the index's coverage.
- Steer the caller toward opening the minimal necessary set of XML files.
- Indicate which official XMLs should be read next, when triage alone is not enough.
- Preserve the distinction between the derived index and the normative source in `KbObjectsXml`.
- For a short functional question, keep the classification separated into: `Direct evidence`, `Additional XML reading`, `Strong inference`, `Hypothesis`.
- State the methodological limit explicitly when triage does not cover the semantics the question needs.
- Recognize when the local KB does not yet expose a wrapper compatible with the desired capability, and treat this as a pending local adaptation, not a methodological failure of the index.
- When an index search is motivated by a GeneXus warning about a missing provider, unknown item, designer, or extension metadata: classify the cited item before interpreting the result — (a) a common exportable GeneXus object; (b) internal part or metadata; (c) designer/extension provider; (d) unknown type. A negative index result for kind (b), (c) or (d) must be reported as a limited conclusion: "not found in the derived index or in the XPZ/XML" — never "does not exist in the KB". See the conceptual boundary rule in [02-operational-rules.md](../references/02-operational-rules.md#limits-of-xpzxml-versus-providers-and-genexus-extensions), section "Limits of XPZ/XML versus providers and GeneXus extensions".

---

## COMMUNICATION

- Respond in the same language the user writes in.
- Get the local time only when a reply or an operational record states a time, immediately before stating it; never reuse a previous timestamp or infer the time from the conversation's sequence.
- Lead with the triage result, not the index's history.
- When the freshness/compatibility gate was relevant to the flow, briefly state the gate's decision in the reply or handoff:
  - if cleared, report that `last_index_build_run_at >= last_xpz_materialization_run_at` and `inventory_validation_status=OK`
  - if blocked, report which field/capability was missing or which timestamp was stale
- When the gate blocks after `index-metadata`, do not say "I cannot query the index"; say that the gate's metadata query ran, but substantive index triage is blocked.
- Say explicitly when the answer still depends on reading the official XML.
- When the gate is blocked, say explicitly that no official object XML will be opened and no scan of `KbObjectsXml` will be run to answer the business question.
- When the gate command is denied, cancelled or interrupted by the user, say explicitly that (a) no alternative search will be run until the gate clears and (b) the operational path is to review the agent tool's permission configuration (for example, the allow rule in Claude Code's `settings.json`) and/or run the **setup** workflow; do not promise to "try another way".
- Open an official object XML only after the gate has cleared; with a blocked gate, do not use a targeted XML read to answer the business question.
- When the index returns the official XML's nominal path, keep that full path consistent in the reply; do not shorten it afterward to just the file name.
- Separate what came from the index from what is the agent's own inference.
- A `WorkPanel` listed under `coverage.unextracted_source_types` of a calls-scope answer also means the index is older than extractor 20: relay it and offer a rebuild. Calls to a `WorkPanel` are indexed from classic `call(W...)` and modern `<WorkPanel>.Call(...)` and `call(<WorkPanel>, ...)`; a `<WorkPanel>.Link(...)`, a call through a variable, or a dynamic program name is not, so confirm a surprising empty caller list with a literal search for the Work Panel name in the XML.
- Whenever a reverse-relation answer has `coverage.complete=false`, tell the user in plain words that the list of callers may be partial, and why: calls made from the listed object types (for example mobile panels) are not indexed. Name each type in `coverage.unextracted_source_types` with its `count` (for example "the KB has 12 `Panel` and 3 `WorkWith` objects whose calls are not indexed"); a relay without the per-type counts is incomplete. For an `Attribute` target (`coverage.scope` = `attribute_references`), say instead which attribute uses are indexed: for each type in `coverage.partially_extracted_source_types`, its `extracted` parts (for example `WorkWithForWeb` grids, filters, orders, views and filter conditions, or `Procedure` Source reads, rule reads and block writes) and its `missing` parts (for example captions, parameters, tab conditions and code, or ambiguous writes, conditions, layout, Business Component members and code outside a Part); attribute uses in the code, rules, formulas, grids and filters of the types in `coverage.unextracted_source_types` are not indexed (when `WorkWith`, `WorkWithForWeb`, `Procedure`, `WebPanel`, `Transaction`, `DataProvider`, `Report` or `WorkPanel` is listed under `coverage.unextracted_source_types` instead, the index is older than that extraction: relay it like any other unextracted type and offer a rebuild); a code use has the `write` role only where the assignment target is unambiguous (block writes in `for each` and `new`, Transaction rule writes, Transaction item writes of a DataProvider) and the `read` role otherwise, other assignments included; besides those, only structural relations (Transaction levels, Table keys and indexes) are indexed. Name each type in `coverage.unextracted_source_types` with its `count` (for example "the KB has 120 `Attribute` and 8 `SDT` objects whose attribute uses are not indexed") and each type in `coverage.partially_extracted_source_types` with its `count` and what is `missing` (for example "40 `WorkWithForWeb` objects whose captions, parameters, tab conditions and code are not indexed", or "310 `Procedure` objects whose ambiguous writes, conditions, layout, Business Component members and code outside a Part are not indexed"). When suggesting which objects likely hold the unlisted uses, label it `Hypothesis` and point at pattern instances (`WorkWithForWeb`, `WorkWith`) and authored code objects (for example `Procedure`), never at objects generated from those instances (`is_generated_object=1`, such as the Web Panels a `WorkWithForWeb` instance generates).
- Give the session-folder notice of the **FIRST-QUESTION CHECKLIST** once per session, in the first answer (after the gate, not as a step before it).
- For a functional question, keep the classification: `Direct evidence`, `Additional XML reading`, `Strong inference`, `Hypothesis`.
- When the target-resolution sub-flow ran, produce an auditable handoff block before any official-corpus read or analysis:
  ```
  Confirmed caller: <caller object name>
  Event/Action: <event or action name in the caller>
  Resolved target: <object actually opened/executed>
  Evidence: <caller XML fragment pointing to the target>
  ```
- Do not promise a complete runtime impact analysis.
- Do not promise a closed functional conclusion when the index only points to a reading trail.

---

## REFERENCES

Reference files and when to load them:

| Reference | Load when |
|-----------|-----------|
| [02-operational-rules.md](../references/02-operational-rules.md) | After the initial structural gate, to interpret freshness, metadata, an operational limit, or the relationship between a derived artifact and the normative source |
| [08-agent-guide.md](../references/08-agent-guide.md) | After the initial structural gate, to guide index use, escalation to official XML, or an operational decision |
| [kb-index-methodology.md](../references/kb-index-methodology.md) | When the answer needs a functional-investigation script, a response model (evidence / additional reading / inference / hypothesis), `functional-trace-basic` as a narrative trail, or the "via web editing" / "via BC" terminology — not for choosing an index query (`search-objects`, `attribute-info`, etc.), which is covered by this workflow and **QUERY PARAMETER REFERENCE** |
| [kb-index-reference.md](../references/kb-index-reference.md) | After the initial structural gate, when this workflow's **QUERY PARAMETER REFERENCE** is not enough: ambiguous index coverage, a command not listed here, or the distinction between validators (`Test-KbIntelligenceQueries` vs. index-generation gates) |

To save context, do not load the long references above before the initial structural gate (`KbIntelligence`, SQLite, local wrapper). If the gate blocks at any of those three checks, answer with the first failure and offer the **setup** workflow, without opening additional references.

Even with the gate cleared, stay economical: for a simple existence/nominal-location question, use `search-objects` or `object-info` first; for light signals about an attribute use `attribute-info`; for materialized transactional writability use `transaction-attributes` or `transaction-writable-attributes`; only open `kb-index-reference.md` or re-read the local wrapper when the query's coverage is genuinely ambiguous.

---

## QUERY PARAMETER REFERENCE (minimal queries)

For the most frequent queries, the `Query-*KbIntelligence.ps1` wrapper accepts the following parameters (in addition to `-IndexPath` and `-Format`, common to all queries):

- **search-objects**: `-ObjectName` (required **unless** `-InstanceKey` is passed; accepts a partial substring with a `*` wildcard, e.g. `"*spreadsheet*"`), `-InstanceKey` (optional; the flat instance name of a WorkWithForWeb, or the full `<GUID>-<name>` key; lists the objects generated by that instance — the route for "which objects did `WorkWithWeb<X>` generate"; case-insensitive exact match; combines with the other filters using AND), `-ObjectType` (optional, filters by type), `-Generated`/`-Authored` (optional, mutually exclusive: Pattern-generated only vs. authored only), `-Limit` (optional); each object's output includes `is_generated_object`/`pattern_object_id`/`instance_key`/`instance_name` (derived instance name, `null` when it cannot be derived)
- **list-by-type**: `-ObjectType` (required, exact type, e.g. `Procedure`), `-Generated`/`-Authored` (optional, mutually exclusive), `-Limit` (optional); lists every object of a type without needing a name — use when the user asks "what are the X objects in the KB"; same `is_generated_object`/`pattern_object_id`/`instance_key`/`instance_name` output fields as above
- **object-info**: `-ObjectType` (required, exact type, e.g. `Procedure`), `-ObjectName` (required, exact object name); output includes `is_generated_object` (0/1), `pattern_object_id`, `instance_key` and `instance_name` — a deterministic generated-by-Pattern vs. authored signal, preferable to name heuristics (`ww*`/`*WC`/`*General`/`*Selection`) for authored-vs-generated audits
- **attribute-info**: `-ObjectName` (required, exact attribute name); returns light signals such as `Formula` and `idBasedOn`, plus every property the export carries for the attribute (`properties`, for example its type and length), without scanning the whole corpus. A property missing from `properties` is at its GeneXus default and its value is not in the export; say so and name no candidate value, not even as a hypothesis (see [02-operational-rules.md](../references/02-operational-rules.md#limits-of-xpzxml-versus-providers-and-genexus-extensions)). For a `Domain`'s impact, prefer `who-uses`/`what-uses` (since extractor 12, `based_on_domain` is no longer Attribute-only)
- **who-uses** / **what-uses** on `Procedure` (and targets resolved in an `Attribute`'s `Formula`): the index includes dependencies via `Property Formula` when the call pattern matches the effective `Source`; for expression semantics or non-indexed functions, open the attribute's XML
- **who-uses** on an `Attribute`: each Transaction level row carries `writability`, that Transaction's materialized writability classification of the attribute (for example `extended-fk-key` for a foreign key); treat it as direct evidence, not an inference (fields in `kb-index-reference.md`, section "Query who uses an object")
- **transaction-writable-attributes**: full classification materialized in the index by the canonical classifier `GeneXusTransactionWritabilityCore.py`; use it for triage and for the impact of `New` on attributes; `unclassified-*` requires the XML
- **transaction-attributes** / **transaction-writable-attributes**: `-ObjectName` (required, exact Transaction name); lists attributes by Level with materialized classification

Although the classification is materialized, these queries may still read indexed `Attribute` XML through the index's recorded `source_root` to populate formula details. The recorded `source_root` is relative to the index folder, so the index and its corpus can move together with the same relative layout. Even after `GATE_OK`, a snapshot moved without the index, or missing, can make a query fail with `Indexed XML file not found on disk` (the message names the `resolved_source_root` it looked under); restore the snapshot at the path `index-metadata` reports as `resolved_source_root` or rebuild the index from the current XML corpus before retrying.
- **css-classes**: CSS class catalog (`css_class` table, style-inventory; does not require `queryableByKbIntelligence`). `-Model` (optional: `legacy-theme` | `design-system`), `-Origin` (optional: `kb-authored` | `packaged-module`), `-IncludeImported` (optional, includes imported libraries in the view without a lookup), `-ObjectName` (optional, **case-sensitive** nominal lookup of a class; without explicit `-Origin`, bypasses the default `kb-authored`-only restriction and can find imported classes; an explicit `-Origin` still filters), `-Limit`. `legacy-theme` is marked `deprecated=true` (a migration candidate to DesignSystem)
- **css-class-usage**: where a class is used (`uses_css_class`/`uses_css_class_dynamic` relations). `-ObjectName` (optional: a specific class; without it, returns an overview with totals and the list of classes **used but not cataloged**), `-Limit`. Declares honest coverage: `dynamic_uses_total` = dynamic `.Class=` assignments (variable/`Format()`) that cannot be attributed to one class; `found_in_catalog=false` = a class that is used but not cataloged, **not** nonexistent. For a destructive operation (renaming/removing a class), verify with a literal XML search before acting

The full documentation of every query and its parameters is in [kb-index-reference.md](../references/kb-index-reference.md).

---

## MINIMUM RECOMMENDED GATE

Call `Test-*KbIndexGate.ps1` by the name provisioned in the KB workspace's `scripts` folder. The script encapsulates the whole gate logic: it sequentially checks the `KbIntelligence` folder, `kb-intelligence.sqlite`, the local query wrapper, the build metadata via `-Query index-metadata`, `kb-source-metadata.md`, and a timestamp comparison. It returns `GATE_OK` on stdout when the index is fit for use, or raises an exception with `BLOCK: <reason>` when it is not.

Replace `<absolute-script-path>` with the literal absolute path of the script, read from the KB workspace's local documentation (e.g. `C:/KBs/SampleKbWorkspace/scripts/Test-SampleKbKbIndexGate.ps1`). Do not use a variable or `Join-Path`: the literal path is required so an agent tool's permission system can statically validate the command and skip manual prompts. Do not add extra lines, side output, parsing, or extra commands to the block; all the gate logic is encapsulated in the script.

Run the gate as one atomic command in the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`), with the literal absolute script path and nothing else on the command line (no `cd ... &&` prefix). It runs the same from bash, PowerShell, or cmd, so use whatever shell or command-execution tool the agent tool provides. If the tool asks for permission to run it, the user approves it, or allow-lists it through that tool's own permission mechanism; a stable, path-scoped allow rule is what lets later gate runs skip the manual prompt.

```text
pwsh -NoProfile -File "<absolute-script-path>"
```

If the script returns `GATE_OK`, end the gate command; any next action must be decided and run in a separate command, per the substantive query needed.

If any `BLOCK:` occurs, close the business question and offer the **setup** workflow. Do not run later gate steps in separate commands "to complete the diagnosis".

### Tool notes: Claude Code (optional)

These notes apply only when the agent tool is Claude Code; other tools use their own permission mechanism.

- Any shell tool works for the canonical form: the `Bash` tool (the default on Windows) or the `PowerShell` tool when the user enabled it. The allow rule's prefix must name the tool that runs the command: `Bash(...)` does not match a command run through the `PowerShell` tool, and vice versa.
- The allow rule the **setup** workflow registers (WORKFLOW step 20) is scoped to the workspace's `scripts` folder: `Bash(pwsh -NoProfile -File "<KbWorkspace>/scripts/*)`. It covers the gate and every other local wrapper, with or without parameters, as long as the command is spelled in the canonical form.
- Earlier versions of this workflow appended a `#gate` comment to a PowerShell-only gate command, so a path-plus-wildcard rule always had text to match after the path (an exact-match rule had been observed not to skip the prompt on Claude Desktop for Windows). The canonical form does not need it: the folder rule's `*` covers the rest of the command. Do not append `#gate`; in cmd it would reach the script as an extra argument.

### COMMON CALL MISTAKES

- Running the gate with PowerShell-only syntax (`& "..."`, `.\script.ps1`) instead of the canonical `pwsh -NoProfile -File "..."` form; it fails in bash or cmd.
- Swapping the literal absolute script path for a variable, `Join-Path`, or indirect assembly.
- Adding parsing, `Write-Host`, `Get-Date`, side output, or extra commands to the same gate block.
- Treating a permission refusal, cancellation, or interruption of the gate as license for a manual fallback.
- After `GATE_OK`, re-inspecting the local wrapper or opening `kb-index-reference.md` without need, when the question already fits `search-objects`, `list-by-type` or `object-info`.
- For a simple existence/nominal-location question, opening the wrapper only to confirm its signature before using the parameters already documented in **QUERY PARAMETER REFERENCE**.

---

## WORKFLOW

1. Identify the active repository and re-read its local `README.md` and `AGENTS.md`; when re-reading `AGENTS.md`, check whether it contains a `## Index triage` section — if absent in a folder that adopts `KbIntelligence`, treat this as an outdated structure and route to the **setup** workflow before any triage. Decide the **FIRST-QUESTION CHECKLIST** items now: use the literal command form for every script call from the gate onward, and keep the session-folder notice for the first answer.
2. If the KB workspace is not yet mounted, validated or mapped for this repository → **ABORT** and use the **setup** workflow.
3. The FIRST substantive action of this workflow in any session must be running the gate. No substantive index query, official object XML read, `KbObjectsXml` scan, or `Query-*KbIntelligence.ps1` query may run before `Test-*KbIndexGate.ps1` returns `GATE_OK`. The gate is a prerequisite for read-side triage only and never grants permission to edit GeneXus objects. This applies even to simple existence/nominal-location questions, type listings, or single attribute/writability queries — `search-objects`, `list-by-type`, `object-info`, `attribute-info`, `transaction-attributes` and `transaction-writable-attributes` are all forbidden before the gate.
4. Run the gate in sequential order and stop at the first block; do not investigate inner layers before the outer layer is valid.
5. Check whether `Test-*KbIndexGate.ps1` exists in `scripts\`; if absent, block as a KB-workspace gap and offer an update via the **setup** workflow.
6. Run `Test-*KbIndexGate.ps1`; the script sequentially checks: workspace structure via `Test-*KbStructure.ps1`, the `KbIntelligence` folder, `kb-intelligence.sqlite`, the local query wrapper with `-Query index-metadata`, `inventory_validation_status`, `kb-source-metadata.md`, and a timestamp comparison; any `BLOCK:` closes the business question.
   - If the gate command's execution is denied, cancelled or interrupted by the user, treat this as a gate not cleared: close the business question, report the situation to the user, offer to review the agent tool's permission configuration (for example, Claude Code's `settings.json`) and/or the **setup** workflow; NEVER work around the gate with a scan, a targeted read, or an indirect query.
7. If any gate step fails, block broad search, substantive triage, substantive queries against the official object corpus, and official object XML reads; report the first operational exception found and offer an update via the **setup** workflow before proceeding.
8. With the gate blocked, close the business question before resolving the requested object to an XML path; do not build, test for existence, list, or open guessed paths like `KbObjectsXml\<Type>\<Name>.xml`.
9. Classify the user's question into one of these kinds: object location; technical impact; dependents and dependencies; specific-relationship evidence; short functional triage; navigation target resolution (a question anchored in an action, button, link or event: "what popup does this button open?", "the object called by event X", "on this screen I click Y").
   - If the kind is navigation target resolution, run the mandatory sub-flow (see RESPONSIBILITIES) to resolve the target before any official-corpus read or analysis: identify the caller, locate the event/action in the caller's XML, resolve the object actually opened, confirm the target with the user if ambiguous, and produce the auditable handoff block; target resolution does not authorize an object edit.
10. Choose the most suitable index query.
    - For a claim "X calls/uses/references Y", use `show-evidence` when the specific relationship needs to be audited; textual `rg`/`grep` can only serve as a targeted probe after `GATE_OK`, never as final evidence of a call between objects.
    - If there is more than one candidate (from the index or a targeted text search with `GATE_OK`), run disambiguation: list the candidates, recommend one with a reason, confirm with the user; do not open a single XML or close the answer while ambiguity persists.
11. Only after `GATE_OK`, run the minimal substantive query needed, without a side read of `scripts`, `kb-index-reference.md`, or re-inspecting the wrapper when the question already fits `search-objects`, `object-info`, `attribute-info`, `transaction-attributes` or `transaction-writable-attributes`.
12. Summarize the triage result briefly and auditably.
13. Decide whether the triage already answers the question at the requested technical level.
14. If not enough, tell the caller only the minimal set of official XMLs to open.
15. If the question is functional: use the index only to guide reading order, and keep `Direct evidence`, `Additional XML reading`, `Strong inference` and `Hypothesis` explicitly separated.
16. If the required GeneXus semantics falls outside the index's current coverage, escalate to the official XML and state the index's limit.
17. If the local wrapper does not expose a capability already available in the shared engine: report the gap, treat the case as a workspace compatibility block for that triage, offer an update via the **setup** workflow, and wait for explicit approval before changing local wrappers.

---

## CONSTRAINTS

- NEVER treat the index as the final normative source.
- NEVER treat the index as a replacement for `KbObjectsXml`.
- NEVER conclude functionality from the index alone.
- NEVER open XML in bulk by default; index triage exists to reduce reading — opening in bulk defeats the workflow's purpose.
- NEVER query the official object corpus to answer a business question, whether by broad scan or a guessed path, when the compatibility/freshness gate is blocked; a blocked gate means the index is not trustworthy, and any answer based on direct XML reads may be stale or inconsistent.
- NEVER treat a permission refusal, cancellation, or interruption of the `Test-*KbIndexGate.ps1` command as authorization for a fallback; it is a gate not cleared and requires the same blocking posture as a `BLOCK:` from the script's own output.
- NEVER use `Grep`, `Select-String`, `Get-ChildItem`, `find`, a folder scan, or a targeted read of `KbObjectsXml` to answer a business question when the gate did not return `GATE_OK` for any reason, including a permission refusal, a cancelled command, an interruption, or a timeout.
- NEVER run a broad corpus search or substantive triage, or open official object XML, when the index is stale relative to the last XPZ/XML materialization.
- NEVER spend diagnosis effort on inner gate layers when an outer layer already failed; stop at the first block and offer an update.
- NEVER test, list, or open a child path of a gate layer before confirming the parent layer; for example, do not test `KbIntelligence\kb-intelligence.sqlite` before `KbIntelligence`.
- NEVER list `scripts` or look for alternative wrappers when the documented local wrapper is missing; this is a KB-workspace gap, not a fallback discovery.
- NEVER continue substantive triage when `index-metadata` fails, returns empty, or does not carry the index's build timestamp.
- NEVER run `search-objects`, `list-by-type`, `object-info`, `attribute-info`, `transaction-attributes`, `transaction-writable-attributes`, `who-uses`, `what-uses`, `show-evidence`, `impact-basic`, `functional-trace-basic`, `css-classes` or `css-class-usage` before `GATE_OK`.
- NEVER look for `last_xpz_materialization_run_at` before confirming `kb-source-metadata.md` exists as a file.
- NEVER interleave `Get-Date` between the gate's internal steps; get the local time only when a reply or an operational record states a time.
- NEVER describe a post-`index-metadata` block as a total ban on querying the index; `index-metadata` is a gate query, the block prevents substantive triage.
- NEVER add parsing, side output, timestamp printing, or extra commands to the gate call block; all logic is encapsulated in `Test-*KbIndexGate.ps1`.
- NEVER, after `GATE_OK`, open `kb-index-reference.md`, list `scripts`, or re-inspect the local wrapper when the question can be resolved directly by `search-objects`, `list-by-type`, `object-info`, `attribute-info`, `transaction-attributes` or `transaction-writable-attributes`.
- NEVER, for a simple existence/nominal-location question, a type listing, or a single attribute/writability query, open the local wrapper only to confirm its signature before calling one of those queries; the parameters are documented in **QUERY PARAMETER REFERENCE**.
- NEVER shorten or inconsistently rewrite the official XML's nominal path returned by the index.
- NEVER present a reverse-relation answer with `coverage.complete=false` as "no callers", "unused" or "safe to remove"; it is a partial answer.
- NEVER reuse a previous timestamp when an update, reply, or operational record states a time; get the local time immediately before stating it.
- NEVER access `kb-intelligence.sqlite` directly through any language or tool — Python, the sqlite3 CLI, inline PowerShell, Bash, or any other means — without going through the gate and the local wrapper; direct SQLite access is equivalent to bypassing the gate regardless of the result obtained.
- NEVER compensate for an `index-metadata` failure or a missing `last_xpz_materialization_run_at` by manually reading validation JSON, the raw SQLite file, an isolated `kb-source-metadata.md`, file dates, `updated`, `generated_at`, `source_xpz`, or official XML to answer the business question.
- NEVER open an official object XML to answer a business question when the compatibility/freshness gate is blocked.
- NEVER normalize working without an index as an economical alternative when the repository adopts `KbIntelligence`; a missing or stale index requires offering an update.
- NEVER edit or allow editing any GeneXus object; target resolution and `GATE_OK` authorize read-side triage only. Generating, cloning, packaging, building, and importing GeneXus objects are out of scope regardless of gate status.
- NEVER, with multiple candidates from the index or from a targeted text search over the official corpus, silently open the first result or answer with certainty without listing the rest, recommending one with a reason, and confirming with the user when the choice is not unambiguous from the context already given.
- NEVER call `Query-*KbIntelligence.ps1` or any index query without first verifying that `Test-*KbIndexGate.ps1` exists in `scripts/` and running the gate with a `GATE_OK` result; the gate script's absence is a structural block, not license to query the index directly.
- NEVER treat a state declaration in the local `AGENTS.md` (e.g. `materialized_and_index_validated`) as authorization to skip the gate's structural check when `Test-*KbIndexGate.ps1` is missing or when this workflow detects an objective absence of scripts. `AGENTS.md` can be stale; the workspace's objective inspection prevails over a state declaration.
- NEVER assume that every new capability in the shared engine is already exposed in the KB's local wrapper.
- NEVER treat the absence of a compatible local wrapper as a defect of the methodological base.
- NEVER pick the KB Intelligence validation executor by phase number alone; the case's format still decides the executor.
- If the local index does not exist, report this explicitly, block the business question, and offer an update via the **setup** workflow.
- If the question falls outside the index's coverage and the gate already cleared, state this before proceeding to the official XML.
