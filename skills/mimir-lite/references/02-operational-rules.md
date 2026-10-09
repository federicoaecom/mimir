# 02 - Operational rules and runtime

## Document role
Operational

## Predominant confidence level
Medium

## Depends on
`01-empirical-base-overview.md`, `03-risk-and-decision-by-type.md`

## Used by
`04-webpanel-families-and-templates.md`, `05-transaction-families-and-templates.md`, `08-agent-guide.md`, `02a-runtime-notes-and-known-issues.md`

## Purpose
Consolidate the confidence-level taxonomy, general reading rules that connect observed XML structure to probable GeneXus runtime behavior, and the structural risk heuristics that support cautious reading. Mimir Lite is read-only: it never generates, clones, packages, imports, or builds GeneXus objects. Per-type runtime notes, known GeneXus error codes, and specific quirks live in `02a-runtime-notes-and-known-issues.md`.

## Operational premises

- Direct evidence: this reference set stays centered on XML extracted from `XPZ`, not on full specification, import, build, or execution logs.
- Documented rule: concepts such as `Base Table`, `Extended Table`, `For each` navigation, `Load`, `Refresh`, and `Refresh Grid` belong to GeneXus runtime/specification and cannot be inferred from the XML's shape alone.
- Strong inference: certain structural XML signals support talking about relative runtime risk, as long as the statement is qualified and never promises real behavior without a test.
- Hypothesis: the denser an object is in `events`, `grid`, `Level`, `AttributeProperties`, `parent`, `pattern`, and contextual links, the more likely it is to be sensitive to navigation, data load, and non-trivial execution behavior.

## Confidence levels

This reference set uses four confidence levels, in decreasing order of certainty:

| Level | Description | When to use |
|---|---|---|
| `Direct evidence` | Raw XML read directly from this corpus, or from the target KB's official XML in the current session | Statements about observed structure, fields, values, or behavior |
| `Strong inference — evidence from an inspected external KB` | Real XML read from another GeneXus KB (not this corpus), with a traceable source (KB, version, object) | A pattern observed in, or reported from, an external KB with traceability; valid for a conservative statement, but still needs validation against the target KB |
| `Strong inference` | A pattern derived from statistical recurrence or structural logic observed in this corpus, with no directly read XML for the specific case | Plausible deductions about expected behavior when direct evidence does not cover the case |
| `Hypothesis` | Speculation based on analogy, plausibility, or structural intuition, with no direct or reported empirical evidence | Untested paths, unvalidated alternatives; requires an explicit flag to the user |

Rules of use:
- Never promote `Hypothesis` to `Strong inference` without additional evidence.
- Never promote `Strong inference` to `Direct evidence` without real XML read in the current session.
- `Strong inference — evidence from an inspected external KB` is a valid level for practical use; state the source KB, version, and reference object when available.
- When recording a handoff, use exactly one of these four labels per critical statement.

## Evidence classification when citing XML lines

- Operational rule: when citing a line of GeneXus XML as evidence, explicitly classify the excerpt's role: effective `Source`, `Rules`/`parm`, XML metadata, `call in the caller`, or `signature in the callee`.
- Operational rule: in a `Procedure`, a line in the called object's own `Rules`/`parm` Part proves only that object's own signature or parameter rule — it does not prove that another object called that `Procedure`.
- Operational rule: to claim object A calls object B, the evidence must be in A's effective `Source`, on the line where B appears as a call, or in a call metadata explicitly materialized in A.
- Operational rule: when a cited line belongs to B's XML and shows `parm(...)`, describe it as "signature in the callee", never as a call site from A.
- Operational rule: in a call chain, always record the caller's file/line and the callee's signature file/line separately, without collapsing the two pieces of evidence into one link.

## Runtime rules

- Direct evidence: in this corpus, `Transaction` appears in 183 objects, all with `parent`, all with `Level`, and 177/183 with `AttributeProperties`.
- Documented rule: `Base Table` determination and its associated navigation depend on the attributes used, `For each`, the `Base Transaction` clause, the object's structure, and the events involved — this cannot be inferred from XML shape alone.
- Operational rule: a `WorkWithForWeb`'s outer package envelope is not the whole picture — the inner XML reconstructed from the `Data` `CDATA` block matters too; a closing error in `variable`, `attributes`, `filter`, `tab`, or `view` there may only surface on `Load`/`Import` in the IDE, not from the outer envelope alone.

### Base Table and Extended Table

- Documented rule: the `Base Transaction` clause declares navigation intent and can be used in `For each` and in `Data Provider` groups to define the base table more clearly and reduce specification ambiguity.
- Documented rule: when a `For each` declares a `Base Transaction`, the associated table becomes the `Base Table`, and attributes used in the body, filters, and orders need to belong to the corresponding `Extended Table`.
- Documented rule: GeneXus can also determine the `Base Table` implicitly from the attributes present, including in grids and `Load` events.
- Strong inference: objects with many attributes from different contexts, parallel FKs, or multiple levels tend to be more sensitive to `Extended Table` effects, conditional filters, and navigation cost.
- Operational rule: when reviewing a `For each`, check the real base table first (explicit in the header or implicit from the attribute set used), then validate whether each attribute belongs to that base or to a coherent `Extended Table`/subtype context.

### Navigation, filters, and loops

- Documented rule: `For each` and `Data Provider` groups are central navigation points; filters, orders, and attributes outside the base table can change joins, subselects, and the access path.
- Documented rule: when a `Load` over a grid or panel has an implicit base, a `For each` written inside the event can end up nested in an already-implicit navigation.
- Strong inference: this raises the relative risk of `N+1`-style patterns, repeated per-row loads, and a cost that is hard to notice from the final XML alone.
- Operational rule: when reading a filter for identity, uniqueness, count, existence, candidate selection, or ambiguity inside a `for each`, look nearby in the same `Source` for other blocks over the same table/base — pairs like `count/then-copy`, `exists/then-load`, `validate/then-apply`, and `select-candidate/then-materialize` are a logical unit; check that the record identity criteria stay coherent across them.

### WebPanel, Refresh, and Grid

- Documented rule: the `Refresh` event and the `Refresh Grid` event run before the displayed data loads/reloads; the `Load` event can run once per row when there is a grid with a navigation base.
- Documented rule: in Web, refresh events use the Ajax cycle — this improves the client-side exchange but does not eliminate server-side navigation and data-load cost.
- Direct evidence: in a `WebPanel`, declaring `Event &Variable.ControlValueChanged()`, even empty, registers an implicit Ajax roundtrip for that variable — it does not behave as a harmless marker.
- Operational rule: `SetFocus()` inside `Event Refresh` is a known source of unexpected focus jumps — because `Refresh` has Ajax-wide scope, it tends to reapply focus at unrelated moments; when the desired focus really depends on a specific action, prefer `Event Start`, `Event Enter`, `Event Click`, or a `Sub` called from an explicitly controlled event instead.
- Strong inference: a `WebPanel` with `events` + `grid` + actions + a contextual `parent` tends to deserve more runtime caution than a minimal shell with no events.

### Procedure, DataProvider, Transaction, and API

- Documented rule: `Procedure` and `Data Provider` can trigger navigation from `For each`, groups, and the attributes used; the relevant runtime behavior depends more on the code and the implicit base than on a simple Part inventory.
- Documented rule: `Transaction` describes transactional structure and levels; its runtime sensitivity grows with sub-levels, parent-child relations, and a higher density of relational attributes.
- Strong inference: a `Transaction` with multiple `Level`s suggests a higher probability of implicit joins, parent-child context, and higher maintenance/performance cost than a single-level `Transaction`.
- Strong inference: an `API` with a `Service` block, `RestMethod`, `.Before`/`.After` events, and calls to a `Procedure` suggests a server-side orchestration layer; the XML does not prove cost, but it does indicate a dependency on internal code and security/session context.
- Hypothesis: a small, direct `DataProvider` with few filters and simple output tends to be less runtime-risky than a `Procedure` or `WebPanel` with cross-cutting events and screen composition.

### Structural bridge by type and family

- Direct evidence: 162/183 observed `Transaction`s have exactly 1 `Level`; 12/183 have 2 `Level`s; 9/183 have 3 or more.
- Strong inference: simple single-level families tend to carry lower relative runtime risk for navigation than master-detail/multi-level families; high `AttributeProperties` density and many referential attributes at the same level suggest higher sensitivity to `Extended Table`, filters, and implicit relations.
- Direct evidence: of 1196 observed `WebPanel` objects, 437 show a structural event signal and 25 a textual `grid` signal.
- Strong inference: `WebPanel` families with `grid` and `events` are more sensitive to load, refresh, and implicit navigation than menu/home or minimal-shell families; families generated with `Defaults`/`IsGeneratedObject` marks, a contextual `parent`, and pattern elements tend to depend more on the runtime/originating KB.
- Hypothesis: the more controls, links, actions, and event code a `WebPanel` has, the higher the chance of non-trivial authorization, refresh, conditional-load, or master-page-dependency behavior.
- Direct evidence: `WorkWithForWeb` carries a `pattern` and a transactional `parent` in 183/183 observed cases.
- Strong inference: objects with a `pattern`, a strong `parentType`, and generated-code blocks deserve more cautious runtime reading, because part of the navigation and functional expectation comes from the generation context; `WorkWithForWeb` and pattern derivatives should be read as high operational/runtime risk even when the structure looks recurring.
- Hypothesis: a small `API` can have simple runtime, but multiple methods and pre-/post-processing events suggest a cost invisible when looking only at the external contract.

## Runtime-impact decision rules

- Speak with more confidence when the conclusion comes directly from an official GeneXus concept (`Base Table`, `Extended Table`, `Load`, `Refresh`, `Refresh Grid`) or when the XML clearly shows repeated signals (`Level`, `Pattern`, `events`, `grid`, `parent`, dense `AttributeProperties`).
- Answer with caution when the XML suggests non-trivial navigation but there is no navigation report or enough code to confirm cost and cardinality (strong inference), or when the conclusion would require assuming joins, roundtrips, or database cost with no direct proof (hypothesis).
- When "looks structurally simple" conflicts with "runtime-sensitive," the more conservative reading prevails.

## Limits of what this corpus still does not prove

- Direct evidence: this trail does not contain complete IDE-generated navigation reports or real performance measurements.
- Documented rule: official concepts help interpret risk but do not replace specification or a real test of the concrete object in the KB.
- Strong inference: this reference set can now answer better about relative runtime sensitivity.
- Hypothesis: it still cannot claim, without a test, that a comparable object will import, build, navigate well, or perform acceptably.

## Complementary official references

- `Base Transaction clause` - <https://docs.genexus.com/en/wiki?25418,Base+Transaction+clause>
- `Base Transaction in For each command` - <https://docs.genexus.com/en/wiki?23945,Base+Transaction+in+For+each+command>
- `Load event` - <https://wiki.genexus.com/commwiki/wiki?8188,Load+event>
- `Refresh Grid event` - <https://wiki.genexus.com/commwiki/wiki?8187,Refresh+Grid+event>
- `Web Form Refresh` - <https://wiki.genexus.com/commwiki/wiki?6566,Web+Form+Refresh>

## Structural risk heuristics

Each heuristic below states the observable signals, the technical reading it supports, and how to answer with the right amount of caution. These heuristics guide reading and explanation, not generation.

| Heuristic | Observable signals | Technical reading | Reading caution |
| --- | --- | --- | --- |
| H01 - Single-level Transaction | Simple 1-level family (`05-transaction-families-and-templates.md`); 1 `Level`; no sub-level; low/moderate `AttributeProperties` density | Direct evidence: 162/183 observed Transactions have exactly 1 `Level`. Documented rule: transactional navigation tends to be less sensitive with a simpler, more local structural context. Hypothesis: the chance of a relative runtime error is lower than in families with detail or many relational attributes. | Answer with measured caution, not optimism; never promise import, build, or final navigation behavior; escalate caution if an extra FK, a context change, or a `DescriptionAttribute` change appears. |
| H02 - Transaction with 2+ levels | 2 or more `Level`s; explicit parent-child relation; master-detail/multi-level structure | Direct evidence: 21/183 observed Transactions have 2+ `Level`s. Strong inference: relative structural/runtime risk rises when attributes are distributed across levels. Hypothesis: changes between levels can affect navigation, implicit joins, and non-trivial behavior in the KB. | Treat as higher risk; do not promise ease of maintenance or good performance. |
| H03 - Transaction with dense AttributeProperties | Many `AttributeProperties` blocks; several referential/control attributes at the same `Level`; markedly denser XML than the lean family | Direct evidence: 177/183 observed Transactions have `AttributeProperties`, with variable density. Strong inference: high density suggests more points of structural/functional dependency. | Answer with caution; do not treat attribute removal as a trivial edit; the chance of an internal-coherence error grows with density. |
| H04 - Minimal-shell WebPanel | Minimal-shell family (`04-webpanel-families-and-templates.md`); small layout; no `grid`; no relevant events | Documented rule: the absence of `grid` and events reduces the observable server-side behavior surface. | The least risky case within `WebPanel`, but still conservative — dependency on `parent`, `MasterPage`, or integrated security can still exist. |
| H05 - Pattern/defaults-generated WebPanel | `Defaults`, `IsGeneratedObject`, `WEB_COMP=Yes` marks; contextual `parent`; recurring generated-object signature | Documented rule: generated objects tend to depend more on the KB's generation/navigation context. Strong inference: this raises relative operational/runtime risk. | Avoid optimistic "simple shell" language; part of the expected behavior may live outside the isolated XML, in the pattern, master page, or parent object. A generated derivative is an output artifact — read it only when a concrete diagnosis genuinely needs to confirm an error, a generated caller, or a runtime artifact; the declarative source (parent pattern, declarative instance, parent/called object) is where the explanation belongs. |
| H06 - WebPanel with events | `Events` block with real code; actions, object calls, or conditional rules; variables tied to screen flow | Direct evidence: 437/1196 observed WebPanels show a structural event signal. Documented rule: Web events can trigger refresh, Ajax load, and additional server-side logic. Strong inference: the presence of events increases the chance of non-trivial contextual behavior. | Answer with caution; the real cost depends on code and navigation not fully visible from the surface signature alone. |
| H07 - WebPanel with grid + events | `grid` family; `Events` block; possible `Load`, `Refresh`, or associated filters/actions | Documented rule: a grid with a navigation base can run `Load` per row; events and refresh raise runtime sensitivity. | One of the most sensitive combinations for cost, repeated load, and context dependency; without a navigation report, the risk of an incomplete runtime reading stays high. |
| H08 - Procedure/DataProvider with navigation sensitivity | `Source` code with queries, filters, orders, or mappings; `Parm`/`Variables` tied to attributes; structured output (`DataProvider`) or procedural logic (`Procedure`) | Documented rule: navigation in these objects depends on `For each`, groups, attributes used, and the implicit/explicit base. Hypothesis: cost and specification quality can vary widely depending on the filters, orders, and attributes used. | These objects can look simple in the outer XML while carrying high navigation sensitivity in the code; do not discuss `For each` or performance without considering `Base Table` and navigation. |
| H09 - Strong parent/pattern dependency | `parent`/`parentGuid`/`parentType` present; `Pattern=` or generated-object marks; structural context tied to a parent object | Direct evidence: `WorkWithForWeb` shows `parent` and `pattern` in 183/183 cases; several other types depend heavily on `parent`. | A strong operational/runtime caution signal; removing or swapping that context can break expected behavior even if the XML stays well-formed. |
| H10 - When the signals accumulate | Mixed families; rare/opaque blocks; events + grid + parent context together; multi-level transactional structure; a pattern with no clear equivalent | Documented rule: runtime and navigation cannot be guaranteed by surface XML similarity alone. | When high-sensitivity signals accumulate, the right stance shifts from "this looks fine" to explicit, well-justified caution — never promise import, build, correct navigation, or performance. |

## Limits of XPZ/XML versus providers and GeneXus extensions

- Operational rule: the XPZ/XML corpus materialized in `KbObjectsXml` is the normative source for common exportable GeneXus objects; it does not cover internal provider, designer, or extension metadata that a KB persists directly in its internal database (e.g. `FormDesignerPart` and equivalent parts).
- Operational rule: name disambiguation — `WebPanelDesigner` and `SDPanelDesigner` exist in the shared catalog as **exportable** types (`inventoryEligible=true`); a positive XPZ/XML search is expected when the corresponding settings object was exported. That does not replace the classification below: the same label in an open/build warning can still refer to a missing extension (e.g. a third-party object designer) or an internal part — do not confuse a cataloged object with an internal-database-only part.
- Operational rule: when an open, build, or export warning names a missing provider, an unknown item, a designer, or extension metadata, classify the cited item **before** searching XPZ/XML: (a) a common exportable GeneXus object; (b) an internal part/metadata; (c) a designer/extension provider; (d) an unknown type.
- Operational rule: if the XPZ/XML search is negative and the item is not type (a), the conclusion must stay limited: "not found in XPZ/XML" — never "does not exist in the KB".
- Operational rule: never use a negative XPZ/XML search result alone to conclude that a provider warning is false or that the KB has no residual dependency on it.
- Operational rule: a positive-sounding textual reference to a third-party framework or design-system name in the exported XML is not, by itself, evidence of a missing provider — it can be legitimate consumption of that framework. Do not confuse a functional object with internal designer metadata.
- Operational rule: a read-only SQL diagnostic against the KB's internal database is the second-layer evidence path when XPZ/XML does not cover the item; suggest it only when there is concrete evidence of an unknown provider/item in an open or build warning, never as routine scanning.
- Operational rule: the six canonical conclusion phrasings for this case, in increasing order of certainty: `not found in XPZ/XML`, `not exported as a common object`, `possible internal provider metadata`, `confirmed in an internal KB table`, `provider absent or incompatible in the environment`, `removal requires the official tool or support`.
- Operational rule: terms that must trigger classification before concluding absence: `FormDesigner`, `WebPanelDesigner`, `SDPanelDesigner`, `Object Designer`, `FormDesignerPart`, `provider GUID`, `extension provider`, `unknown item`, and any unrecognized GUID cited in an open or build warning. For `WebPanelDesigner`/`SDPanelDesigner`, also classify against the effective catalog — they can be type (a) if the GUID matches the exportable type.
- Operational rule: an object or attribute property at its default value is not written in the export. Its absence from the XML (or from the `properties` of `attribute-info`) means "default; the value is not in the export". Say exactly that, and do not name a candidate value at all: not as the default, not as a hypothesis, not as what the property "typically" or "probably" is. When the user needs the value, point to the GeneXus documentation or the IDE.

## Reading anti-patterns

- Never infer good performance from the XML alone.
- Never answer "it will build" or "it will import" without external evidence.
- Never treat `grid` + `events` as a simple shell.
- Never answer about a `For each` without considering `Base Table`, navigation, and attribute context.
- **Editing the corpus expecting a package to catch it**: never edit `KbObjectsXml` expecting documentation, a package, or a later query to pick up that version. The corpus is read-only for agents; only the **sync** workflow's official flow writes it. Editing it directly does not influence any downstream artifact and leaves the corpus itself inconsistent with its own read-only contract.
