# 08 - Agent guide

## Document role
Operational

## Predominant confidence level
Medium

## Depends on
`00-index.md`, `01-empirical-base-overview.md`, `02-operational-rules.md`, `03-risk-and-decision-by-type.md`, `04-webpanel-families-and-templates.md`, `05-transaction-families-and-templates.md`, `05b-procedure-and-report-families-and-templates.md`

## Used by
Any agent that needs to consume this reference set

## Purpose
Explain how an agent should consult this reference set, classify evidence, and read a GeneXus object with prudence. Mimir Lite is read-only: it never generates, clones, packages, imports, or builds GeneXus objects, and it does not run this repository's own development process (pre-push checks, peer review, delegation to another model) — those live in `AGENTS.md`, `docs/process/`, and the optional `mimir-delegate` skill.

## Reading order

1. Read `00-index.md`.
2. Read `02-operational-rules.md`.
3. Identify the target type and check `03-risk-and-decision-by-type.md`.
4. Use `01-empirical-base-overview.md` as the master index of the `01` series and open the most relevant empirical child (`01a` to `01h`; `01k` is a governance doc outside that map).
5. For `WebPanel`, read `04-webpanel-families-and-templates.md`.
6. For `Transaction`, read `05-transaction-families-and-templates.md`.
7. For a report `Procedure` (a name with a report prefix in the corpus), read `05b-procedure-and-report-families-and-templates.md`.
8. Use `09-script-inventory.md` to support traceability.

`06-object-patterns-and-naming.md`: supplementary reading — read it when the doubt is about object naming, type prefixes, or `Folder` vs `Module` behavior.

### Short read-side flow for a simple report `Procedure`

1. Classify first whether the observed case fits the simple family `F2` or `F3`.
2. If it fits, consult `05b-procedure-and-report-families-and-templates.md` as the primary structural reference for report `Procedure` families and their historical sanitized examples; this is a read-side comparison, not authorization to create or modify an object.
3. Explicitly separate `Source`, `Rules`, and layout when diagnosing, and check that `RPT_INTERNAL_NAME`, `PrintBlock` identifiers, and the references used in `print printBlock...` are coherent between `Source` and layout; an incoherence is a reading finding.
4. If the sanitized-template comparison does not settle the reading after one short structural re-check, stop reasoning by analogy and compare with comparable real XML.
5. Declare which evidence supports the answer: `sanitized template`, `real XML from the current KB`, `real XML from another KB`, or `hypothesis`.

## Unknown type in the catalog

This flow covers a **modern type** missing from the catalog (identified by GUID in `Object/@type`). A **legacy GeneXus 9 export** element (`<GXObject><Element>` by name, no type GUID) does not go through this flow — it is governed by the `gx-legacy-export-element-registry.json` registry (owner doc `01k-legacy-element-registry.md`); see `kb-index-reference.md` and `sync.md` for the legacy branch. In a legacy-export inventory, `unknownTypeCount=0`/`unknownTypesDiscovery=[]` is expected and is not evidence of "zero dependencies".

When sync or a pre-scan blocks on an `Object/@type` GUID missing from the effective catalog:

1. Stop the XPZ-to-XML sync/materialization; do not treat the unknown GUID as a defect in the KB's XPZ. Do not proceed with partial materialization.
2. Collect evidence (a JSON report: `-DiscoveryReportPath` in sync, or an inventory with `unknownTypesDiscovery`).
   - The block message names each unknown type as `<type GUID> type="<type name>" package="<package>" [<count>] names=<up to 3 object names>`, followed by `parent=`/`parentType=` samples when present. The type name and package come from the package's own `ExportFile/Dependencies/Reference` entry with `Type="Object"` and that GUID as `Id`; both are `unknown` when the package does not declare it. The sync engine throws this message, the inventory returns it in `unknownTypesMessage` (and each `unknownTypesDiscovery` entry carries `typeName` and `typePackageName`), and the sync wrapper prints it on one stderr line before failing. The declared name is a strong hint for the catalog entry, not a confirmed `folderName`.
3. Ask the user, politely, whether they **recommend** authorizing a lookup in official GeneXus documentation — never consult it without consent.
4. If the exportable type can be safely identified, offer, as separate, user-authorized catalog-governance steps: a local stopgap record (`Register-GeneXusObjectTypeCatalogOverride.ps1` with `-UserApproved`) and a copyable prompt for the maintainer (`New-GeneXusUnknownTypeMaintainerPrompt.ps1`). These steps concern catalog governance, not permission to edit GeneXus objects or continue a partial XPZ-to-XML sync.
5. In every new session in a KB workspace with an active override, run `Test-MimirCatalogOverrideSessionReminder.ps1 -KbWorkspaceRoot <root> -AsJson` and read its status fields before treating the override as resolved.
6. Never register a shared-catalog entry from a KB workspace without switching context first; catalog maintenance requires separate authorization. Never materialize the XPZ-to-XML sync partially.

## Reading rule for runtime questions

- When the question involves `Base Table`, `Extended Table`, navigation, `For each`, `Load`, `Refresh`, `Refresh Grid`, or a performance risk, consult `02-operational-rules.md` first.
- When the question is only about observed XML structure, prioritize `01-empirical-base-overview.md` as the index and descend into the most relevant `01` empirical file.
- When the question mixes structure and probable behavior, answer by explicitly separating `Direct evidence`, `Documented rule`, `Strong inference`, and `Hypothesis`.

## Reading rule for a known official baseline

- When the question involves review, sanity, regression, an inherited defect, or delta quality on a legacy object, explicitly separate `absolute sanity of the current artifact` from `comparison against the official baseline`.
- Answer the absolute sanity check first, and only then, if a reliable official baseline exists, answer the comparison.
- Use only an official, traceable source as the baseline — the official snapshot in `KbObjectsXml` or a comparable official IDE export; never a provisional copy, a local delta, or contaminated XML.
- Label the comparison with exactly one of: `same as official baseline`, `worse than official baseline`, `better than official baseline`, or `no official baseline compared`.
- Never treat `same as official baseline` as a synonym for "good" — it only proves the absence of a relevant regression on the compared dimension.
- If the current artifact fails the absolute sanity check, keep that failing verdict even when the comparison reads `same as` or `better than official baseline`.
- When a problem already existed in the official baseline and the delta did not make it worse, describe it as an inherited risk or defect, not as a newly introduced regression.
- Before concluding `worse than official baseline`, filter out known, non-functional noise already documented in this trail.
- If there is no reliable official baseline, or it was not actually opened, use `no official baseline compared` instead of inferring a comparison from memory, plausibility, or recency.

## Reading rule for derived fields

- A calculated or derived attribute's name does not prove its functional semantics.
- When a filter, business rule, or interpretation depends on a derived field, the formula and its immediate call chain prevail over the name, caption, or intuition.
- A business filter over a derived field requires validating the formula before proposing anything.
- If the formula calls a `Procedure`, follow at least the immediate call chain needed to justify the field's functional meaning.

## KB Intelligence usage

Full usage rules, the query reference, and worked examples live in [`find.md`](../workflows/find.md) and [`kb-index-methodology.md`](kb-index-methodology.md) — this guide does not duplicate them. In short: run the freshness/compatibility gate before any substantive query, prefer `impact-basic`/`who-uses`/`what-uses` over a raw text search when the type is `queryableByKbIntelligence=true`, and always separate direct index evidence from a conclusion that still needs an XML read.

## Block-based review protocol

For every type below, review by functional block rather than opening the whole XML as one mass:

- Before a fine-grained analysis, declare the **primary block** for the current symptom.
- Open an **adjacent block** only when there is an explicit functional dependency on the primary block.
- Name every block transition in your reasoning and in the handoff (e.g. `Rules/parm -> Execution context`).
- Stop expanding once the hypothesis is already supported; do not reopen the whole object by reflex.
- Declare the conclusion's scope at the smallest functional level the evidence actually supports; when more than one execution context is relevant, make that context explicit as well.

For a report `Procedure`: `Output_file`, `Header`, `Footer`, `For each`, and `print printBlock...` belong to `Source`; `parm(...)` belongs to `Rules`; `Bands`, `PrintBlock`, `ReportLabel`, and `ReportAttribute` belong to the layout Part `c414ed00-8cc4-4f44-8820-4baf93547173`. A `;` mentioned in an error points to `Rules`; an invalid control, `printBlock`, or report-shape complaint points to layout.

| Type | Canonical blocks (in order) | Reading notes |
| --- | --- | --- |
| `Procedure` | Source, Rules/parm, Variables, Calls and dependencies, Identity and container, Report layout (report Procedures only) | `Source` → filters, procedural flow, navigation, assignments, conditions, calls in the body. `Rules/parm` → signature, parameters, contract direction. `Variables` → existence, type, new helper, collection vs. simple. `Calls and dependencies` → call chain, called object, external dependency, call-site proof. `Identity and container` → `parent`, `module`, `fullyQualifiedName`, clone risk. `Report layout` only when the symptom is about `PrintBlock`/`ReportLabel`/`ReportAttribute`/`Bands`/layout shape. |
| `DataProvider` | Output structure, Source, Navigation context, Calls and dependencies, Identity and container | `Output structure` → collection vs. simple, nested group, node name, cardinality, coherence of the promised shape. `Source` → condition, assignment, computation, internal flow. `Navigation context` → implicit base, `For each`, filter, base table, navigation ambiguity. |
| `DataSelector` | Selection contract, Selection logic and conditions, Attribute and function dependencies, Navigation context, Identity and container | Do not treat a small XML as automatically simple when the question is about filter/parameter/selection/function. `Selection contract` → parameters, input signature, control variable. `Attribute and function dependencies` → cited attribute, function used in the filter, broken/unresolved reference. |
| `DataView` | DataView structure and platform, Associated table (DVAssocTable), Indexes by platform, Identity and container | The observed structural set comprises `Attribute`(s) with an exclusive prefix (dates via `idBasedOn = Domain:<DateTimeDomain>`), a purely structural `Transaction` (no screen, no rules), the `DataView` with `<DataViewStructurePlatform Dbms="NN">` + `NAME`/`SCHEMA`, and `DVDataStore`+`DVAssocTable`. In the recorded case without `DVAssocTable`, specification failed with `spc0031`. In the historical missing-platform case, absence of `<DataViewStructurePlatform>` for a deployed DBMS left the Transaction represented as a plain table and impact analysis reported a `CREATE TABLE`, including for a production install. PostgreSQL's observed primary-key index name was stable across installs (`_pkey`); SQL Server's generated PK suffix differed per install. Interpret any existing `<DataViewIndexesPlatform>` against that observed per-install variation; these observations do not recommend omitting or editing the element. A `For Each` over a DataView in a WebPanel event was rejected (`src0065`) in the recorded case; the `01e` examples document the corresponding separation from Procedure logic as historical structure. See `03-risk-and-decision-by-type.md` and the `01e` sanitized templates (`dvExemploMultiDbms`/`dvExemploSingleDbmsMissingPlatform`). |
| `API` | Service contract, Events and orchestration, Calls and dependencies, Data contract, Identity and container | `Service contract` → exposed method, endpoint, external signature, published operation. `Events and orchestration` → `.Before`/`.After`, execution order, internal validation. `Data contract` → input/output shape, type coherence, response structure. |
| `SDT` | Structure definition, Item typing and dependencies, External serialization contract, Top-level type properties, Identity and container | `Structure definition` → `Level`, `LevelInfo`, `Item` sequence, hierarchy, collection vs. simple. `Item typing and dependencies` → `idBasedOn`, `ATTCUSTOMTYPE`, base domain, reference to another `SDT`. `External serialization contract` → `ExternalName`, `ExternalNamespace`, `idXmlName`/`idXmlNamespace`, `soaptype`, `idCollectionItemName`. |
| `Theme` | Theme core definition, Class graph and references, Predefined types and style bindings, Visual simplification and override surface, Identity and container | Do not prune classes just because they look unused — `TableDetail`, `TableSection`, `TextBlockGroupCaption`, and similar can be required by other references inside the same theme. |
| `ThemeClass` | Direct class surface, Inheritance and parent linkage, Theme applicability and internal classification, Visual references and external dependencies, Identity and container | `Inheritance and parent linkage` → `parent`, `parentGuid`, `parentType`, base class, derived variants, states like `hover`. |
| `ThemeColor` | Color identity and naming, Direct color value surface, Theme applicability and palette coupling, Visual references and usage dependencies, Identity and container | |
| `ColorPalette` | Palette identity and naming, Palette composition and declared members, Theme and design-system coupling, Color references and usage surface, Identity and container | |
| `DesignSystem` | System identity and naming, Design tokens and declared resources, Theme and palette coupling, Visual rules and consumption surface, Identity and container | |
| `PackagedModule` | Module identity and naming, Packaging boundary and declared members, Parent and installation context, Dependency and consumption surface, Identity and container | |
| `Image` | Image identity and naming, Image item set and declared variants, Binary payload and extraction fidelity, Theme and language references, Identity and container | `Binary payload and extraction fidelity` → `base64Binary` integrity, content preservation, extraction fidelity. |
| `Attribute` | Attribute core definition, Typing and base linkage, Semantic property references, Presentation and control semantics, Identity and container | Distinguish a real top-level `Attribute` (root `<Attribute ... name="...">` with `Part`+`Properties`) from an inline reference inside a `Transaction` (`<Attribute key="...">Name</Attribute>`) — never treat the latter as a complete object. `Semantic property references` → `ControlItemDescription`, a broken nominal reference, a concrete dependency on another real attribute. |
| `PatternSettings` | Pattern registration and environment fit, Internal pattern configuration, Context and callable dependencies, Security and auxiliary references, Identity and container | Treat the object as pattern configuration, not a self-contained object. `Context and callable dependencies` → `ContextVariable`, `LoadProcedure`, missing procedures. |
| `Folder` | Minimal structural shape, Parent and module context, IDE semantic reading, Identity and naming semantics, Identity and container | `Folder` (`...0008`) is a structurally valid XML type. `Category` is not a label of `Folder`: `...0006` is the container the IDE shows as **Category** (Main Programs, GAM, ToBeDefined, user categories), catalogued under the key and folder `Module`. |
| `Domain` | Base type definition, Limits and scalar constraints, Enumerated values contract, Usage-facing semantic contract, Identity and container | `Enumerated values contract` → `IDEnumDefinedValues`, the value list, descriptions. |
| `Table` | Primary key structure, Secondary indexes and embedded index members, Transaction coupling and physical context, Identity and container | Treat `Index` as a structure embedded in `Table` in this export trail, not a separate top-level block. `Transaction coupling and physical context` → the relation to the `Transaction` of the same name, physical re-association, contextual dependency. For index-prefix conventions and empirical statistics, see `02a-runtime-notes-and-known-issues.md`. |
| `ExternalObject` | External contract surface, Method signatures and parameter typing, Platform and native binding metadata, Identity and container | |
| `UserControl` | Control contract surface, Properties and event bindings, Runtime resources and external dependencies, Identity and container | |
| `SubTypeGroup` | Group definition and member structure, Subtype mappings and role assignments, Contextual usage contract, Identity and container | |
| `File` | File identity and declared surface, Binary or textual payload fidelity, References and consumption context, Identity and container | |
| `Dashboard` | Dashboard composition and layout, Widgets and data bindings, Navigation and interaction context, Identity and container | |
| `Stencil` | Stencil definition and structural surface, Parameters and configurable slots, Pattern or generation consumption context, Identity and container | |
| `DataStore` | Store definition and declared connection surface, Configuration parameters and runtime options, Model and consumption context, Identity and container | |
| `Generator` | Generator definition and declared surface, Generation options and technical parameters, Model and target-platform usage context, Identity and container | |
| `Language` | Language definition and declared surface, Localization parameters and technical options, Model and runtime usage context, Identity and container | |
| `Document` | Document identity and declared surface, Materialized content and payload fidelity, References and functional consumption context, Identity and container | |
| `DeploymentUnit` | Deployment unit definition and declared surface, Packaging parameters and technical options, Runtime or delivery context, Identity and container | |
| `Panel` | Panel structure and layout, Serialized behavior and configuration, Pattern and parent coupling, External dependencies, Identity and container | Treat `level id` and `layout id` as a coupled pair — a `Layout com identificador incorreto` warning can mean only one of the pair changed. For a read-side comparison, inspect the pair in a real IDE-exported Panel SD from the same KB rather than infer either GUID independently; this is not a cloning recommendation. For Panel SD with actions, read `detail/@events` before concluding which events exist; cross-check `onClickEvent="'Name'"` against `Event 'Name'` in the serialized behavior; do not assume an `Event Controle.Tap` without equivalent evidence from a real template in the same KB. |
| `Transaction` | Transaction structure, Attributes and attribute properties, Rules, Events, Execution context, Identity and container | `Execution context` → whether the effect happens via web editing or via BC (see `kb-index-methodology.md`, Example 4, for the terminology). `Rules` → declarative rule, obligation, normative effect. `Events` → behavior via the interface, user action. For known Rules/Events error patterns and a runtime cascade quirk, see `02a-runtime-notes-and-known-issues.md`. |
| `WebPanel` | layout, events, variables, serialized functional metadata, identity and container, dependencies | Treat serialized functional metadata (`Conditions`, `ControlWhere`, `ControlBaseTable`, `ControlOrder`, `ControlUnique`, `PATTERN_ELEMENT_CUSTOM_PROPERTIES`, `WebUserControlProperties`, pattern marks) as its own layer — it can sit near the layout but is not visual decoration. If a serialized layout read in `CDATA` comes back truncated, do not manually reassemble it from fragments — read the complete block through a structured extraction method. Do not use a raw match on `<Source><![CDATA[<GxMultiForm...` as evidence of `events` behavior — `GxMultiForm` proves the layout/serialized-metadata layer, not code-behind. For a targeted text search in a `WebPanel`'s `Source`, prefer `Search-GeneXusXmlSourceBlock.ps1 -Block events` for event/call/validation/flow questions, and `-Block layout` only for a visual or visible-binding symptom. If a raw grep is unavoidable, classify matches separately into `GxMultiForm`, `labelCaption`, `PATTERN_ELEMENT_CUSTOM_PROPERTIES`, and `events` lines, instead of dumping the whole `CDATA` into the response. |
| `WorkWithForWeb` | Transaction binding, Pattern structure and navigation, Actions/links/prompts, Attribute references and data contract, Identity and container | `Attribute references and data contract` → displayed attribute, filter by attribute, column, the structural convention `adbb33c9-0906-4971-833c-998de27e0676-AttributeName`. Treat the generated surrounding `WebPanel` and `WorkWithPlus` only as explicit external dependencies, not an internal canonical block of `WorkWithForWeb`. |

## Object identification by type

Always qualify a GeneXus object by type + name, never by name alone — see the operational rules in `06-object-patterns-and-naming.md` (type determines the physical folder; a name can repeat across types in the same KB).

## Precedence of heuristics

- If a heuristic in `02-operational-rules.md` flags runtime caution, do not answer with optimistic language.
- If a heuristic in `02-operational-rules.md` requires a comparable template, that prevails over structural enthusiasm, sample frequency, or surface similarity.
- If a heuristic in `02-operational-rules.md` says to abort, abort clearly, explaining the structural signal and the methodological limit.
- When "looks structurally simple" conflicts with "runtime-sensitive," the more conservative reading prevails.

## Answering with confidence

Answer with more confidence when the question is descriptive and directly backed by XML or empirical tables, when the answer can be labeled `Direct evidence`, and when the target type is already well mapped by frequency and comparable examples.

Answer with caution when the conclusion depends on a recurring frequency with no external test, when the type's sample is small, when the answer touches safe editing, a real requirement, import, or a build, when the type's correctness depends on `ATTCUSTOMTYPE`, a registered pattern, a parent visual class, an imported package, a real attribute, or an existing parent object, or when it depends on a calculated attribute's semantics, a formula, a derived status, or a shared procedure not yet reviewed.

## Answer formula

1. Classify the statement as `Direct evidence`, `Strong inference`, or `Hypothesis`.
2. Cite the base file used.
3. State the limitation.
4. Recommend a conservative next step.

## Unconscious inference risk in investigations

Complements the confidence-level system in `02-operational-rules.md`.

The hardest risk to detect is not an agent that knows it is speculating and says so. It is an agent that believes it is reporting a direct observation while it is actually consolidating from context — and therefore does not notice it should qualify the statement.

Three concrete patterns identified empirically (2026-05-10):

- **Inference by structural proximity**: attributing a property of one row to a neighboring row in the same family, without a literal query on the specific row. Example: concluding that a type's `EntityTypeNamespace` is `K2BTools` because neighboring types in the same table have that namespace, without reading the target row's own field.
- **Ungranular COUNT reported as a narrative about elements**: turning a total aggregated by a textual criterion into a claim about individual elements without checking whether they all share the same name/type. Example: "37 `FormDesigner` records" when the COUNT actually mixes two distinct names (`FormDesigner`=1, `FormDesignerPart`=36).
- **Consolidating context evidence without preserving its origin**: grouping items from the same provider/context into a single block and, when writing it up, letting the proximity imply a link that was never proven. Example: listing a provider's GUIDs next to a passage about a specific type without stating explicitly which type each GUID belongs to.

Operational rule: when reviewing or recording investigation findings — your own or another agent's — explicitly check whether each statement has a directly traceable source (a line read, a query run, a named column) or is an inference from consolidated context. When in doubt, qualify it as `Strong inference` or `Hypothesis` before recording it as fact.
