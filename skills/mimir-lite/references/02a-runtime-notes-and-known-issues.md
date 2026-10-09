# 02a - Per-type runtime notes and known issues

## Document role
Reference — historical error observations and read-side structural interpretation. This document records observed GeneXus behavior; it does not prescribe object edits, package imports, builds, or generated-code inspection as actions. XPZ corpus synchronization remains a separate, read-only workflow using the official exported XPZ.

## Predominant confidence level
Medium

## Depends on
`02-operational-rules.md`, `03-risk-and-decision-by-type.md`

## Used by
`08-agent-guide.md`

## Purpose
Per-type contextual runtime notes (`Transaction`, `Attribute`, `Table`/`Index`), known GeneXus error codes with their cause and meaning, and specific WebPanel/pattern-generation quirks — split out of `02-operational-rules.md` to keep each file focused. Mimir Lite is read-only; nothing here is a generation or packaging instruction.

## Transaction

- Direct evidence: an isolated test with a `Transaction`, its real top-level `Attribute`s, `SDT 'Context'`, and `SDT 'TransactionContext'` imported successfully, including generating the pattern for the associated `WorkWithForWeb`.
- Historical import observation: a package containing only a `Transaction` failed with `Attribute 'X' in 'Transaction Y' does not exist` when the attributes referenced in `<Level>` did not exist in the target KB; the historical test package containing the corresponding top-level `Attribute`s did not show that error. This records the observed dependency, not a package-construction instruction.
- Strong inference: when a Transaction's template uses `Context`, `TrnContext`, or `TrnContextAtt`, the corresponding context SDTs stop being an auxiliary detail and become first-class dependencies — read them as part of the Transaction's real shape, not optional context.
- Historical diagnostic interpretation: an error naming `sdt:Context`, `sdt:TransactionContext`, or `sdt:TransactionContext.Attribute` indicated a missing contextual dependency rather than an XML-envelope failure.
- Historical read-side interpretation: observed Transaction changes to displayed attributes, filters, tabs, or navigation can have a corresponding `WorkWithForWeb` representation; that object is relevant structural context when interpreting the exported corpus, not an edit or validation step prescribed here.

### Transaction anti-patterns (GeneXus error catalog)

Historical GeneXus error observations for `Transaction` `Rules`/`Events`, retained as a read-side diagnostic catalog. The `src0056` observation is distinct from the report-`Procedure` error notes in `05b-procedure-and-report-families-and-templates.md` (where symptoms included a `parm(...)` closure or report-rule terminator).

| Anti-pattern | Symptom | Error (Specifier) | Root cause |
| --- | --- | --- | --- |
| `transaction-rule-on-event-with-attribute-parameter` | Import fails on a rule with a punctuation-shaped message; easy to misread as a missing `;` | `src0056: Missed ';' at the end of the rule` | A declarative rule written as `on <event>(<attribute>)` (e.g. `on AfterValidate(<Attribute>)`) is not accepted — the `(` after the event name is an unexpected token. Only parameter-less `on <event>` clauses are valid there. |
| `transaction-event-attribute-assignment-rejected` | Import may pass; `BuildAll`/`SpecifyGenerate` fails when a Transaction attribute is assigned inside `Events` | `spc0150: Cannot update database. Changes to database are only allowed in procedures.` | Assigning a value to the Transaction's own attribute inside `Events` is treated as a database update, which the Specifier rejects — attribute persistence belongs to declarative `Rules` (and writability gates), not `Events`. |
| `transaction-default-rule-with-conditional` | Import fails on a `Default(...)` rule followed by a conditional clause | `src0239: 'Default' rule does not support a conditional expression.` | `Default(<Attribute>, <expression>)` sets the initial value when the attribute is empty and does not accept an `if <condition>` clause; a conditional initial value needs a separate assignment rule (`<Attribute> = <expression> if <condition>;`) instead — the two forms are not semantically equivalent: `Default` only supplies the initial value while the attribute is empty, while an assignment rule evaluates under its own trigger. Distinct from `transaction-attribute-rule-shadowed-by-default-in-cascade` below: `src0239` is an import-time rejection, while the cascade entry is a runtime shadowing with a clean import/build — do not confuse the two. |
| `transaction-attribute-rule-shadowed-by-default-in-cascade` | Historical observation: a rule present in XML passed specification/import/build, but at runtime the attribute received the `Default(...)` value (often `0`) or stayed empty; via web editing, the typical symptom is a derived FK field staying empty after tabbing out of the trigger attribute, even though the XML rule would indicate it should populate | No Specifier error was reported; the historical investigation compared generated web `.cs` | Read-side interpretation: `Default(...)` and an assignment rule over the same attribute can map to mutually exclusive `if`/`else if` branches; textual XML order determines branch order, and when the default sits before the rule it may shadow the assignment. Generated-code inspection is not a Mimir Lite workflow. |

## API

- Direct evidence: this corpus observes only one real `API` object, corresponding to a manual/local construction of this KB.
- Strong inference: the validation hierarchy for `API` in this trail is: `ATTCUSTOMTYPE`/SDTs first, then `Procedure`, then business attributes/domains/context used in code and events.
- Strong inference: for `API`, the most useful reading unit is a functional family — at least `Procedure`, `SDT`, `Domain`, and possibly `Transaction`, `Table`, and `DataProvider` — not the isolated object.

## Reading GeneXus source: declarative vs procedural facts

- Historical import observation: a non-empty `Procedure` `Conditions` part (`763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9`) was associated with `src0055`; read-side interpretation is structural drift because this object family has no `Conditions`-based filter and its predicates are represented in `For Each ... Where`.
- Documented rule: `Transaction` `Rules` are declarative clauses, not procedural code — a multiline `if ...` condition or a `[web] { ... }` block is normal declarative syntax there, not an `If`/`For`/`Do`/`Sub` block; do not read it as an unclosed or mismatched procedural block.
- Documented rule: `.Sort()` on a GeneXus collection supports both ascending and descending order: `"()"` alone sorts a scalar collection descending; `"MemberA, (MemberB)"` mixes ascending (bare member) with descending (parenthesized member) across SDT members.
- Documented rule: `Exit` leaves the innermost `For`/`Do While` loop — it is not a way to leave the enclosing `Sub`.

## Attribute

- Direct evidence: this corpus's materialized XML includes at least one case of an invalid logical filesystem name (a `ThemeClass` named `ImageHandCenter:hover`), materialized on disk as `ImageHandCenter_hover.xml`.
- XPZ corpus-sync interpretation: when an exported object's logical name contains a character invalid for the target filesystem, materialization may apply deterministic filename normalization while leaving the XML's internal `name` unchanged. Corpus completeness comparisons therefore account for `type + logical name` separately from the normalized disk filename; this describes the official XPZ-to-XML sync layer, not object editing.

## Table and Index

- Direct evidence: in this corpus, `Table` is its own top-level family and `Index` appears embedded inside `Table`; an isolated `Index` export came back empty, while `Table + Index` repeated the same top-level serialization as `Table` alone.
- Direct evidence: a private comparison against real pairs from the source KB confirmed the nominal correspondence between `Transaction` and `Table` in both simple and denser cases, and that the first `Level`'s key matches the `Table`'s `<Key>` block, including composite keys. In the same sample, every observed `Automatic` index member already existed as an attribute of the corresponding `Transaction`'s first `Level`.
- Direct evidence: in this KB, prefix `I` identifies an index automatically created by GeneXus from a modeler-defined PK/FK, and prefix `U` identifies an index created manually by a human operator. Renaming an automatic `I...` index to a friendlier name changes only the name — fields, order, and nature stay the same. GeneXus's default naming for automatic indexes is not very descriptive, typically derived from the `Table` name with incremental numbering from the second index onward.
- Direct evidence: a full parse of the local `<Indexes>` block across the corpus found 143/228 Tables with at least one `User` index and 85/228 with none; among the 85 without a `User` index, 69 had only 1-2 `Automatic Duplicate` indexes; among the 143 with a `User` index, 124 had 1-3 `User` indexes. Only 3 Tables (`OperacaoFiscal`, `Pais`, `TipoDocumento`) had no `Automatic Duplicate` index at all, and even those had at least one `User` index.
- Direct evidence: across 429 `User` indexes in the corpus, 239 had at least one `Descending` member, 229 ended with their last member `Descending`, and 190 were entirely `Ascending` — a manual index in this KB is not always about descending order; some cover a specific business search or navigation.
- Strong inference: for reverse-engineering the physical layer, the useful unit is a comparable `Table`, preferably alongside its corresponding `Transaction`, not an isolated `Index`.
- Strong inference: read an automatic-index name as a GeneXus-generated FK/PK index (possibly renamed for readability later); read a `User` index as empirical manual tuning, created when the automatic indexes did not serve a real grid/report/procedure ordering and the expected volume justified a dedicated index — a recurring case reuses an automatic index's composition but adds `Descending` on the last field to speed up "most recent record" lookups.
- Strong inference: `OperacaoFiscal`, `Pais`, and `TipoDocumento` are local exceptions in this KB, not preferred templates for inferring the absence of an `Automatic Duplicate` index elsewhere.
- Operational rule: do not classify `Index` as an independent top-level object in this trail without new external structural evidence; do not infer an `Automatic` index merely because an attribute ends in `Id` or `Codigo` — the safer signal is repetition across a comparable `Table` in the same structural group.

## WebPanel and pattern-generation quirks

- Documented rule: in a `WebPanel`, a button is declared exactly once, in one of two serialized forms of the same Button control — `<action controlName= onClickEvent= caption=>` or `<ucw gxControlType="-2133704903" PATTERN_ELEMENT_CUSTOM_PROPERTIES=...>` (name and event live inside the escaped `Properties`) — and fires through a named user `Event` (`Event 'Name'`) or a default one (`Enter`/`Back`); the choice of form is a serialization detail, not a modeling one (observed pattern: `ucw` in menus, `<action>` elsewhere).
- Documented rule: do not confuse three distinct uses in `WebPanel` XML: a layout button (`<action controlName= onClickEvent=>` or a `<ucw>` Button) inside `<layout>`; a `WorkWithForWeb` pattern action (`<action name=>` inside `<actions>`); and a property reference in event code (`Button.Visible`/`.Icon`/`.Enabled`), which manipulates an already-declared control and is neither a declaration nor an event. N mentions of a button's name in `Source` do not mean N buttons.
- Direct evidence: in this trail, non-functional noise tied to `Load Code` has appeared in a `WorkWithWeb`'s `Selection` attribute and/or `View` tabs. Treat this as expected noise only at those confirmed points, without generalizing to every `WorkWithWeb`.
- **HISTORICAL evidence — nested Tab / SDT rebind** (see also `04-webpanel-families-and-templates.md`): with an outer Tab containing an inner Tab whose sub-tabs bind `&Sdt.<member>` through data attributes, the inner default sub-tab appeared empty on first outer-tab activation despite the SDT being populated server-side. Strong inference: the client-side re-bind of the inner sub-tabs' data attributes is triggered by an `ajax_rsp_assign_sdt_attri(..., AV<SdtName>, AV<SdtName>)` call in the generated `.cs`; without a server-side event marking the SDT as mutated, that call is not emitted. The historical fix touched one SDT member, not the whole SDT: whole-SDT `out` reassignment changed its identity and could break sibling WebComponents in other outer tabs. Historical alternatives were tested and did not work: self-assignments were stripped as no-ops; `FromJson`/`ToJson` were unavailable, and `FromJSonString`/`ToJSonString` were not exposed to events; `Refresh` alone kept the handler but did not include the SDT in `oparms`; `SelectTab(1)` alone was a client-side no-op when tab 1 was already active, unlike the `(2);(1)` pair. Scope of evidence: the pattern was observed in one real `WebPanel` of an inspected KB; applicability to `Panel SD` was not verified locally and should be checked case by case when the event structure is equivalent. These are historical observations, not instructions to edit objects or inspect generated code.
- Historical error observations and read-side interpretation: reports of event code not running fell into two structurally different cases; preserving the distinction helps interpret historical diagnostics, without prescribing import/build actions:
  - **Historical import rejection**: a call existed in the generated `.cs` API surface but was not exposed to the GeneXus event layer (e.g. `ToJSonString`/`FromJSonString` on an SDT). The recorded import diagnostic was `Unknown function '<name>'` (`src0294` or similar), a non-zero exit code, and a line/column pointing at the event source; the object was not updated in the KB.
  - **Historical silent strip by dead-code elimination**: an event body containing only operations the generator statically classified as no-ops (e.g. `&x = &x`, `&sdt.<m> = &sdt.<m>`, `&str = &str + ""`) was recorded with successful import/build and no error or warning; the handler was absent from generated `.cs` or had an empty body.
  - Historical diagnostic distinction: an error/non-zero import result was evidence of rejection; clean import/build records paired with absent behavior were historically correlated with dead-code elimination. Generated `.cs` comparison belongs to the historical investigation, not the current read-side workflow.
- Historical error observation: repeated C# build errors `CS1010` (newline in a constant) and `CS1513` (expected `}`) in a referenced generated `.cs` were associated with truncation from interrupted GeneXus generation, not necessarily a defect in object XML. Typical cause: the GeneXus generator was interrupted mid-write of the `.cs` file — a cancelled process, an internal exception, insufficient disk space, or a frozen IDE — so the build compiled an incomplete file and the C# errors point at the truncated region. The historical investigation noted abrupt final lines, unclosed calls or strings, a missing final newline, unexpectedly few lines, and differences against completed environments as diagnostic clues; this records the prior investigation, not a current generated-file inspection task.
- Historical observation: for the same KB and object version, GeneXus generation produced materially different `.cs` code between environments (e.g. .NET Framework vs. a .NET Core target), including layout and available runtime APIs. Read-side implication: generated-code findings are environment-specific and do not establish cross-environment behavior or validate object XML universally.

## Known GeneXus error codes

Historical code → phase → context → cause observations, retained to interpret exported structure and historical diagnostic records. These entries preserve observed codes and causes; they are not instructions to edit objects or run import, specification, or build workflows.

| Code | Phase | Context | Cause |
| --- | --- | --- | --- |
| `spc0031` | Specification | A `DataView` with no associated table | A `DataView` alone does not form a base table for `For Each` — it needs a structural `Transaction` plus a `DVAssocTable` property. |
| `src0013` | Import | `For each` in a WebPanel `Start` event | Historical interpretation: the recorded error associated direct data reading in a screen event with the parser's procedural-placement restriction. |
| `src0055` | Import | A non-empty `Conditions` part in a `Procedure` | A `Procedure` has no `Conditions`-based filter (predicates live in `For Each ... Where`, part `528d1c06-...`); code left in the `Conditions` part (`763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9`) causes this on import. |
| `src0051` | Import | A method called on a procedure's return value | Historical observation: e.g. `proc(x).ToUpper()` was rejected as a method call on a procedure return value. |
| `src0054` | Import | A method called on a parenthesized expression | Historical observation: e.g. `(&a-&b).ToString()` was rejected as a method call on a parenthesized expression. |
| `src0065` | Import | `For Each` in a WebPanel event | Historical interpretation: the recorded error associated direct iteration in the event with the WebPanel event parser restriction. |
| `src0216` | Import | An orphan `condition` in a WorkWith | Historical interpretation: a condition such as `Attribute.Visible` referred to an attribute not listed under `<attributes>`. |
| `src0294` / `src0246` | Import | A structural Transaction (`GenerateObject=False`) with screen code | Historical interpretation: `Call("LoadWWPContext")`/`Call("<Trn>WW")`-style WorkWithPlus screen code was rejected on a Transaction without a generated screen. |
| `src0294` | Import | `.IsNull()` on a scalar variable | Historical observation: `.IsNull()` was rejected for a scalar variable; the observed distinction was between attribute/BC null semantics and scalar emptiness. |
| `src0229` | Import | `.SetNull()` on a scalar variable | Historical observation: `.SetNull()` was rejected for a scalar variable; the observed distinction was between attribute/BC null semantics and scalar emptiness. |
| `CS2001` | Build (C#) | `right()`/`left()` calls | Historical observation: these calls surfaced as an orphan `udp("right")`; specification passed but generated C# failed because the functions were not recognized in that context. |

Note: `src0294` has two distinct contexts above (a structural-Transaction screen-code rejection, and a scalar `.IsNull()` call) — the same error code repeating does not by itself mean the same root cause.

### Historical false alarm: Impact Analysis display

- Historical observation: the IDE's **Impact Analysis** panel displayed `CREATE TABLE <schema>.<TransactionName> (...)` even when no table change was pending; the displayed statement represented the Transaction structure. This caused legitimate alarm in two independent KBs. In the validated case, the panel header read `Database tables will not be changed.` This is not a current workflow check.
- Evidence limit: a definitive reorganization verdict was historically associated with build evidence (`reorgDetected`, DDL counts in logs, and target-database state). Mimir Lite does not run or automate that analysis. Structural XML reading alone cannot establish a pending database change; the cited IDE header was the strongest evidence in the documented case.
