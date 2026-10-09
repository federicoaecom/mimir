# KB Intelligence - agent methodology guide

## Document role
Operational guide

## Predominant confidence level
Medium

## Depends on
`kb-index-reference.md`, `02-operational-rules.md`, `08-agent-guide.md`

## Used by
Agents who need to answer short functional or technical-impact questions using the KB Intelligence index as a triage trail, without replacing a read of the official XML.

---

## Methodological principle

The index guides reading order. The official XML closes the conclusion whenever the question depends on GeneXus semantics.

KB Intelligence can reduce search cost, guide the reading trail, and organize evidence, but the final answer still depends on:

- direct evidence from the index, when it exists
- additional reading of the official XML, when the question needs GeneXus semantics
- an explicit label for what is strong inference, weak inference, or hypothesis

---

## Checklist before answering

- Confirm which KB workspace is in use.
- Read the local `README.md` and `AGENTS.md` when entering a KB workspace other than this methodological root.
- Always identify the object by `type + name`.
- Locate `KbIntelligence\kb-intelligence.sqlite`.
- Treat `KbIntelligence\kb-intelligence.sqlite` as a canonical artifact derived from the KB workspace.
- Treat the SQLite index as a derived index, never as the normative source.
- If triage suggests the canonical index is stale relative to expected behavior, do not regenerate it mid-investigation.
- Treat index regeneration as a separate, explicit, validated operational action.
- Use `KbObjectsXml` as the normative source whenever the question depends on GeneXus semantics.
- Do not use `ArquivoMorto` unless explicitly asked for historical analysis.
- Do not touch local `logs/` unless explicitly asked.

---

## Minimum triage order

1. Run `object-info` to confirm the object exists and its path.
2. If the name or type is still uncertain, run `search-objects`.
3. Before `who-uses`, `what-uses`, `impact-basic`, or `functional-trace-basic`, check the effective catalog (`scripts/gx-object-type-catalog.json` + the KB workspace's local override) for whether the type has `queryableByKbIntelligence=true`. When it is `false`, `Query-KbIntelligenceIndex` returns exit `11` and `blocked=true` — **never** read this as zero dependencies; use `object-info`, `search-objects`, `list-by-type`, or a targeted XML read instead.
4. Run `impact-basic` (or `who-uses`/`what-uses`) **only** when the type is `queryableByKbIntelligence=true`, to get direct dependents and dependencies. For an expected asymmetric graph (`API`, `DataSelector`, `WorkWithForWeb`, `ExternalObject`), see `kb-index-reference.md`; the mobile `WorkWith` is `queryableByKbIntelligence=false`, and between the two Work With types, use the GUID as identity, never the historical name.
5. Pick only the relations that actually change the reading trail.
6. Run `show-evidence` on those relations.
7. Open the official XML only at the points that need it.
8. Answer by separating direct evidence, additional reading, strong inference, and hypothesis.

For short functional questions, `functional-trace-basic` can replace steps 1-6, still respecting the `queryableByKbIntelligence` gate in step 3; the final answer still needs an explicit separation of evidence and its limits.

### Branch: Transaction attribute or writability (index-based triage)

Use this branch only for a **technical triage** question about attributes or writability — not when the goal is to **generate or package** XML/XPZ (out of scope for this skill).

1. Pick the minimal query per `find.md`'s **QUERY PARAMETER REFERENCE**:
   - `attribute-info` — one attribute; **light** signals (`Formula`, `idBasedOn`, etc.)
   - `who-uses`/`what-uses` on a `Domain` — direct technical impact via `based_on_domain` (extractor 12: origins in scope, not just Attribute; does not cover attribute consumption in the body, `references_attribute`, still pending)
   - `transaction-attributes` or `transaction-writable-attributes` — one Transaction; **materialized** classification in the index (current `schema_version`, `"5"`), computed by `GeneXusTransactionWritabilityCore.py` at build time
2. Record the command, the object, and the returned signals as **direct evidence**.
3. Explicitly state the **query type**:
   - `attribute-info`: light; does **not** replace a full writability classification
   - `transaction-writable-attributes`: full materialized classification
4. If the question evolves into generating an assignment (`Rules`, `Events`, `New` blocks) or packaging, **stop the triage** — that is out of scope for this skill.

### Branch: Pattern-generated objects vs. authored objects (index-based triage)

Use this branch only for a **triage** question about telling Pattern-generated objects (WorkWith For Web) apart from authored ones — typically a security-style **audit** — not when the goal is to **generate or package** XML/XPZ (out of scope for this skill).

1. Pick the minimal query per `find.md`'s **QUERY PARAMETER REFERENCE**:
   - `object-info` — one object; returns `is_generated_object` (0/1), `pattern_object_id`, and `instance_key`
   - `search-objects` or `list-by-type` with `--generated`/`--authored` (mutually exclusive) — a deterministically filtered set per type
2. Record the command, the object, and the `is_generated_object`/`pattern_object_id`/`instance_key` value as **direct evidence**.
3. State explicitly that this is a **deterministic signal** materialized in the index (the object-level `IsGeneratedObject` property), **not** a name heuristic (`ww*`/`*WC`/`*General`/`*Selection`); the marker is proof only after a fresh index rebuild.
4. If the question evolves into packaging or fixing a generated derivative, **stop the triage** — that is out of scope for this skill.

For query syntax, parameters, and operational validation, prefer `kb-index-reference.md`; this guide does not duplicate that catalog.

---

## When to stop at the index

Stop at the index when the question only asks for:

- where to review first
- which objects technically surround a given object
- which technical relation justifies opening a given XML
- what the minimum reading trail should be
- which attributes of a Transaction deserve reading first, which light signals (`attribute-info`), or which materialized writability classifications (`transaction-writable-attributes`) the index exposes (without yet closing a business rule)

In these cases, state explicitly that this is direct technical triage, not full functional proof.

## When to open the official XML

Open the official XML whenever the question depends on:

- the effective `Source`
- `Rules`
- `parm(...)`
- events
- formulas
- properties with semantic effect
- the immediate call chain
- a variable's type, `ATTCUSTOMTYPE`, BC, `SDT`, `Domain`, or `ExternalObject`
- interpreting functional effect, validation, persistence, navigation, or a business rule

---

## Required shape of a functional answer

### Direct evidence

Record only what came from the index or from stored evidence:

- the command used
- source and target object as `type + name`
- the relative file
- the recorded line
- the extraction rule
- a short technical excerpt

### Additional XML reading

Record what the official XML confirmed:

- the official file read
- the excerpt or block consulted
- the excerpt's role in the investigation
- the limit of what the reading confirmed

### Strong inference

Use only when signals converge:

- a direct technical relation in the index
- evidence anchored to a line
- the official XML confirming the excerpt's context
- a type or variable resolved with confidence

Even then, do not turn the inference into a runtime guarantee.

### Hypothesis

Use for anything that still depends on additional reading, an external test, a build, execution, or functional knowledge outside what was actually read.

---

## Phrases to avoid

- "the system certainly does this"
- "this proves the business rule"
- "this is the complete functional impact"
- "just look at the index"
- "no need to open the XML"
- "the procedure always saves"
- "the SDT is the complete payload"
- "the screen always depends on this procedure"

## Preferred phrases

- "the index shows direct technical evidence"
- "the official XML confirms this excerpt"
- "the strong inference is"
- "this remains a hypothesis"
- "closing the full functional rule needs reading to continue into"
- "this is technical triage, not full runtime proof"

---

## Sanitized examples

The examples below use generic GeneXus object names, with no reference to real KBs. Correspondences with real KB names are kept in the maintainers' private notes (not published). The commands use the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`); `<mimir-lite-root>` and `<KbWorkspace>` stand for absolute paths.

### Example 1 - Technical-impact triage before changing a Procedure

**Scenario:** the agent needs to assess the impact of changing `Procedure:procExemploCalculaSaldo` before modifying its internal logic.

**Minimal trail:**

```text
# Step 1: confirm existence
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query object-info -ObjectType Procedure -ObjectName procExemploCalculaSaldo -Format text

# Step 2: map direct technical impact
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query impact-basic -ObjectType Procedure -ObjectName procExemploCalculaSaldo -Limit 20 -Format text
```

**Expected `impact-basic` result:**

- direct dependents: `WebPanel:wpExemploConsulta`, `DataProvider:dpExemploResumo`
- direct dependencies: `Procedure:procExemploRegistraLog`, `Transaction:TrnMovimento`

**Step 3 (optional): audit a specific relation**

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query show-evidence -SourceType WebPanel -SourceName wpExemploConsulta -TargetType Procedure -TargetName procExemploCalculaSaldo -Format text
```

**Expected structured answer:**

- Direct evidence: call `procExemploCalculaSaldo.Call(...)` in `WebPanel/wpExemploConsulta.xml`, line N, rule `procedure_dot_call`, confidence `direct`
- Additional XML reading: open `Procedure/procExemploCalculaSaldo.xml` to review parameters and the effective `Source` before drawing conclusions
- Strong inference: the change can affect `wpExemploConsulta` and `dpExemploResumo`
- Hypothesis: the runtime effect depends on the procedure's internal logic; not confirmable from the index alone

---

### Example 2 - Basic functional triage with `functional-trace-basic`

**Scenario:** the agent gets a short functional question about `API:apiExemploIntegracao` and needs to build an initial trail before opening XML.

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query functional-trace-basic -ObjectType API -ObjectName apiExemploIntegracao -Limit 20 -Format text
```

**Expected result:**

- located object: `API/apiExemploIntegracao.xml`
- resolved direct dependencies: `Procedure:procExemploProcessaEntrada`, `SDT:sdtExemploItemBasico`
- redundant `CustomType` literals suppressed when an equivalent resolved relation exists
- XML files flagged for reading: `API/apiExemploIntegracao.xml`, `Procedure/procExemploProcessaEntrada.xml`

**Expected structured answer:**

- Direct evidence: direct technical relations returned by the index for `apiExemploIntegracao`
- Additional XML reading: open `API/apiExemploIntegracao.xml` to review the API's contract and parameters; open `Procedure/procExemploProcessaEntrada.xml` to check what the procedure does with the received data
- Strong inference: the API receives input and delegates processing to `procExemploProcessaEntrada`; the SDT `sdtExemploItemBasico` is the data type carried
- Hypothesis: persistence, validation, and business rules depend on reading the procedures' effective `Source`; not confirmable from the index alone

---

### Example 3 - Object not found

**Scenario:** the agent queries an object that does not exist in the index.

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query object-info -ObjectType Procedure -ObjectName procNaoExisteNaKb -Format text
```

**Expected result:** a clear failure indicating the object was not found. Do not try to locate it by heuristics outside the index, do not search by a similar-looking name, do not scan `KbObjectsXml`.

**Expected structured answer:**

- Direct evidence: object not found in the index
- Next steps: confirm name and type with the user; if the index may be stale, offer regeneration

---

### Example 4 - Terminology: web editing vs. BC

This example records the correct terminology for the two ways of interacting with a GeneXus `Transaction`.

**Via web editing:** the flow through the transaction's own form, in the IDE or in the web runtime. `Rules` and `Events` tagged `[web]` apply. The user (or an entry WebPanel) saves, cancels, or edits the record through the transaction's own interface.

**Via BC (Business Component):** the `Transaction` is instantiated as a Business Component by a procedure or another GeneXus object. `.Load(...)`, `.Save()`, `.Delete()`, `.Check()`, `.Insert()`, and `.Update()` calls are made programmatically. `Rules` tagged `[bc]` apply.

**When to use each term in an answer:**

- When describing user actions (saving a form, canceling a record, editing a field): use "via web editing".
- When describing calls made by procedures or automations: use "via BC".
- Do not mix the two contexts in the same statement without explicitly stating which part refers to which context.

---

## Answer quality gate

Before answering, confirm:

- the object was identified by `type + name`
- direct evidence was not mixed with inference
- XML reading was cited separately when it happened
- every functional conclusion states its limit
- hypotheses were not written as facts
- the index was not described as the normative source
- the official XML prevails when there is an interpretive tension
