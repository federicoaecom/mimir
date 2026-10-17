# KB Intelligence scripts

## Document role
Operational guide

## Current scope

These scripts implement the KB Intelligence technical index, with support for inventory, semantic relations, and agent-assisted functional triage.

The `impact-basic` command summarizes an object's direct dependents and dependencies. The `functional-trace-basic` command builds an initial functional trail for short questions, but does not produce an automatic functional conclusion.

Canonical technical type catalog:

- `scripts/gx-object-type-catalog.json`
- Operational rule: the **effective** catalog = the shared base + `scripts/gx-object-type-catalog.override.json` in the KB workspace when present, with entry classification (`pending`/`redundant`/`divergent`) and a field-by-field merge. An equivalent override preserves operational fields missing from the override but present in the base, such as `exportTaskLabel`; unsafe reasons block resolution. `Build-KbIntelligenceIndex.py` and `Query-KbIntelligenceIndex.py` merge via `scripts/GeneXusObjectTypeCatalogCore.py`, with `--kb-workspace-root`/`--catalog-override-path` (build: auto-detected when `--source-root` ends in `KbObjectsXml`; query: auto-detected when the SQLite file sits under `KbIntelligence/`).
- Operational rule: this JSON is the canonical technical source for `Object/@type`, `rootKind`, expected folder, and inventory eligibility; the `.md` docs remain editorial/historical explanation.
- Operational rule: this catalog only covers modern GUID-based types. **Legacy GeneXus 9** export elements (`<GXObject><Element>` by name, no type GUID) live in their own registry, `scripts/gx-legacy-export-element-registry.json` (owner doc `01k-legacy-element-registry.md`), not in this catalog. The **legacy export engine/parser already exists** (`scripts/GeneXusLegacyExportFileSupport.ps1`) and is integrated with sync/inventory (`Sync-GeneXusXpzToXml.ps1` materializes the legacy branch; `Get-GeneXusXpzObjectInventory.ps1` inventories `known-legacy` items; a mixed package fails closed). `Build-KbIntelligenceIndex.py` is, in turn, **registry-aware** for the materialized corpus: it loads the registry and indexes a **registered** orphan flagged `indexedByKbIntelligence` (`Report` and `Menu` today) as its own queryable type, named after its `materializedFolderName`. Classic identity is type + name, so a `Report` and a `Procedure` may share a name and stay distinct. A registered orphan without that flag is skipped during the build when its content matches the expected `typeToken`, **without** `raise SystemExit` or `status=BLOCK`, and the skip is audited in the `legacy_orphan_directories_skipped` field of `inventory_semantics` (today `Prompt` and `Formula`, which come from `.xpw` exports; a skipped orphan is not queryable, although the content of a `Formula` is read through the attribute it computes, see "classic formula" below). A `gxlegacy/*` token **outside** the registry (e.g. an old corpus with `type="gxlegacy/Menubar"` after `Menubar` became `equivalent`) is **not** skipped — the rebuild fails until re-sync/cleanup; see `01k` and `sync.md`.
- Operational rule: `Attribute` should only be classified as a file's canonical type when the real root is `<Attribute ...>`; inline `<Attribute>` occurrences inside `Transaction`, `Table`, or other XML do not redefine the object's type.

### `inventoryEligible` and `queryableByKbIntelligence` flags

- `inventoryEligible=true`: the type enters the index inventory (an object listable via `object-info`, `search-objects`, `list-by-type`) when XML exists in a subfolder of `KbObjectsXml`.
- `queryableByKbIntelligence=true`: the index's semantic queries (`who-uses`, `what-uses`, `impact-basic`, `functional-trace-basic`) are **fit** for this type with the current extractor — the graph tends to reflect real technical dependencies in the corpus.
- `queryableByKbIntelligence=false`: the object may be in the inventory, but the semantic queries above must **not** be used as proof of impact or dependency; the current engine does not extract relations for this type (empty responses look like "no impact"). Prefer `object-info`, `search-objects`, or a targeted XML read. Canonical list: each entry in `scripts/gx-object-type-catalog.json` (zero-graph check: query `kb-intelligence.sqlite`).
- `Query-KbIntelligenceIndex.py` refuses `who-uses`, `what-uses`, `impact-basic`, and `functional-trace-basic` when the type has `queryableByKbIntelligence=false` in the **effective catalog** (base + override): JSON with `blocked=true`, `reason=QUERY_NOT_SEMANTIC_FOR_TYPE`, exit `11`; if the override blocks resolving the effective catalog, JSON with `status=INVALID_OVERRIDE_SHAPE`/`OVERRIDE_RESOLUTION_BLOCKED` and exit `2`. Wrappers must forward `-KbWorkspaceRoot`/`-CatalogOverridePath` as in the build.

### Types with an asymmetric graph (`queryableByKbIntelligence=true`)

These types **remain** fit for semantic queries; the graph may be outgoing-only, incoming-only, or sparse — **do not** reclassify as `false` just because `incoming_relations=0` or `outgoing_relations=0` on one side.

| Type | Typical current index behavior | Use of `impact-basic` |
| --- | --- | --- |
| `API` | Almost always a **source** (calls in `Source`); rarely a target | Reports what the API triggers |
| `DataSelector` | Same as `API`, smaller volume | Same |
| `WorkWithForWeb` | Strongly a **source** (actions, links, transaction, attributes); almost never a target | Reports dependencies the web WW references |
| `ExternalObject` | Can receive input via a resolved `ATTCUSTOMTYPE` and via a method call on an `exo:<ExternalObject>` variable in the effective `Source`; sparse per KB | `who-uses` may find declarative references and effective uses; an empty graph in a small KB does not prove global absence |

The mobile `WorkWith` type is passed to the same action, link, prompt, condition, and transaction extractors as `WorkWithForWeb` (its attribute references have an extractor of their own, see "attribute reference (mobile)" below), but those extractors match only the web Work With XML shape: the calls of a mobile Work With live in the events of its `List`/`Detail` sections, which the extractor does not read, so in practice it produces no call relations (observed on public samples). For that reason `WorkWith`, like `Panel` and `SmartDevicesApplication`, is `queryableByKbIntelligence=false`, and all three are among the types counted in the coverage of reverse-relation answers (the full list is in "Coverage of reverse-relation answers"). Its declarative references (`ATTCUSTOMTYPE`, `idBasedOn`) and, since extractor 18, its attribute references are still indexed and appear in the `who-uses` of their target (the flag only refuses `WorkWith` as the queried object, not as a source listed in another object's `who-uses`). The two Work With types keep their own distinct canonical GUIDs and names, and deduplication includes `source_type`, so homonymous mobile and web objects do not collapse into a single relation.

The legacy `WorkPanel` (desktop/Windows generator) is `queryableByKbIntelligence=true` since extractor 20: its code is read like a `WebPanel`'s, from a classic export (its `<Rules>` and `<Events>`, see classic calls and classic code attribute use below) and from a modern one (calls from the effective `Source`, attribute uses from the Rules and Events Parts). Its `for each` tables and Business Component calls are not extracted. Before 20 it was `false`, like `Panel`. Calls to a `WorkPanel` come from classic code (prefix `W`) and from the modern `<WorkPanel>.Call(...)` and `call(<WorkPanel>, ...)` (see the targets via effective `Source` below). An index built before 20 still counts `WorkPanel` in the coverage of reverse-relation answers.

Do not confuse these with `false`-flagged types (e.g. `Image`, `Theme`, `SubTypeGroup`), where the extractor **never** creates edges for that `target_type`.

Current inventory scope:

- every type flagged `inventoryEligible=true` in the technical catalog and present with XML in an immediate subfolder of `KbObjectsXml`

Current relation-extraction scope:

- sources via effective `Source`: `Procedure`, `WebPanel`, `DataProvider`, `Transaction`, `API`, `DataSelector`, `WorkPanel` (since extractor 20), and a classic `Report` (classic calls, below)
- targets via effective `Source`: `Procedure`, `WebPanel`, `DataProvider`, and since extractor 20 `WorkPanel` (`calls_workpanel` from `<WorkPanel>.Call(...)`, rule `workpanel_dot_call`, and from `call(<WorkPanel>, ...)`, rule `workpanel_call_command`, when the name is not a `Procedure` of the local inventory)
- the `Source` scan also covers `Source` serialized as structured XML (e.g. `<Property><Name>ControlWhere</Name><Value>Object(...) or udp(Object, ...)</Value></Property>` in WebPanel layouts), not only `Source` in a CDATA block of free GeneXus code
- WebComponent creation in effective `Source`: `Procedure`, `WebPanel`, `DataProvider`, `Transaction`, `API`, `DataSelector`, `WorkPanel` for a `WebPanel` via `<WebPanel>.Create(...)`, when the target exists in the local `WebPanel` inventory
- classic calls (since extractor 19; GeneXus 7.5 to 9 exports, root `dataSource="gx-legacy-export"`): a classic `Report`, `WebPanel`, `Procedure`, `Transaction`, or (since extractor 20) `WorkPanel` is read by its own extractor, never by the modern call forms above (a classic call names its target with an object-type prefix, so the modern `call(PAGO)` would wrongly match a `Procedure` named `PAGO` instead of `AGO`). It reads every `<Rules>` and `<Events>` body and every `<Source>` inside a `<CodeBlock>` (the `Report` `Layout/Block/CodeBlock/Source`), CDATA-unwrapped, skipping `//` and `/* */` comments (a `/* */` comment may span lines), with the evidence line of the call in the XML file. `call(`, `udp(`, and `link(` (any case, not after `&`, `.`, or a name character; an optional quote before the name) relate to the object named after the first letter, the prefix: `P` → `Procedure` (`calls_procedure`), `R` → `Report` (`calls_report`), `T` → `Transaction` (`calls_transaction`), `W` → `WorkPanel` (`calls_workpanel`), when that object exists in the local inventory of the type (case-insensitive). Rules `classic_call_command`, `classic_udp_func`, `classic_link`. A call through a variable (`Call(&PDebugProc, ...)`) and any other prefix give no relation; the Web Panel prefix is not mapped because no sample shows it. Assumption: the code tags of a classic `Procedure` and `Transaction` were not observed in a real export; they are read the same way (a `<Source>` inside a `<CodeBlock>`, `<Rules>`, and `<Events>`), so code a classic `Procedure` keeps in a `<Source>` outside a `<CodeBlock>` gives no relation. Since extractor 20 a classic `WorkPanel` is also a call source: its `<Rules>` and `<Events>` are read like a classic `WebPanel`'s. A `<Source>` outside a `<CodeBlock>` is not code and is not read, by this extractor nor by the classic attribute extractor below: the `WebPanel` `HTMLForm` and the `Documentation` hold HTML, and a print control in a `Report` layout holds the value it prints
- source via action: `WorkWithForWeb`
- target via action: `Procedure` or `WebPanel`
- explicit binding: `WorkWithForWeb` to `Transaction`
- explicit link: `WorkWithForWeb` to `WebPanel`
- explicit prompt: `WorkWithForWeb` to `WebPanel`
- explicit condition: `WorkWithForWeb` to `Procedure`, including a static call resolved by the real name in the inventory, `Name.Call(...)`, `Call(Name, ...)`, `udp(Name, ...)`, `Name.Udp(...)`; a `//` comment ends at its own line (since extractor 16 the later lines of a multi-line condition are read, and a `//` inside a string literal is not a comment)
- condition attribute: `WorkWithForWeb` to `Procedure`, with the same forms resolvable via inventory as the explicit condition
- attribute reference: `WorkWithForWeb` to `Attribute` (`workwith_references_attribute`, rule `workwith_for_web_attribute_reference`) from the pattern instance in `<Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b">`: `<attribute attribute="<typeGuid>-<Name>">` in grids, orders, view tabs, and fixed data, `<descriptionAttribute attribute="<typeGuid>-<Name>">`, and bare `<filterAttribute name="<Name>">`, and (since extractor 14) the attribute names of `<condition value="...">` expressions in the selection and Grid tab filters (only a `<condition>` inside a `<filter>` element is read), when the attribute exists in the local inventory; one relation per object and attribute (the first occurrence in document order is the evidence, whichever part names it); `<variable>` elements are not read, and the mobile `WorkWith` has its own extractor (next item). `evidence_role` tells the part: `WorkWithForWeb attribute`, `WorkWithForWeb description attribute`, `WorkWithForWeb filter attribute`, or `WorkWithForWeb condition` (evidence line: the `<condition>` tag). A condition is read after XML unescaping with a small tokenizer that skips `//` comments (each to the end of its line; later lines of a multi-line value are read; a `//` inside a string literal is not a comment, and a comment counts as whitespace, so a name after it is read with the tokens before it), string literals, `&variables` (also `&Var.IsEmpty()`), members after `.` (the legacy `.and.`, `.or.`, `.not.` operators are not members), names followed by `(` or an object call method (`.udp(`, `.call(`, `.link(`, `.submit(`), the object named first in `udp(...)` and `call(...)`, and the keywords `and`, `or`, `not`, `like`, `when`, `null`, `true`, `false`, `in`; an attribute with a method (`Name.IsEmpty()`) and a call argument (`Proc(Name)`, `Proc.udp(Name)`) are uses. Captions, view and action parameters, tab `condition` attributes, and `<variable>` or event code are not read
- attribute reference (mobile, since extractor 18): `WorkWith` (WorkWith for Smart Devices) to `Attribute` (`workwith_references_attribute`, rule `workwith_sd_attribute_reference`) from the pattern instance in `<Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889">`: `<data attribute="<Name>">` in the list and detail layouts (a value starting with `&` after unescaping is a variable and is skipped), `<attribute attribute="<typeGuid>-<Name>">` inside `<orders>`, `<search>`, and `<breakBy>` (directly under `<list>` in X Evolution 2, pattern version `0.10.2`; under `<gridData>` in X Evolution 3, GeneXus 15, and GeneXus 16), and `<filterAttribute attribute="<typeGuid>-<Name>">` advanced filters, when the attribute exists in the local inventory (a Domain or unknown name gives no relation). One relation per object, attribute, and role (the first occurrence of each role in document order is the evidence), so an attribute in a layout and in the search has two rows; deduplication includes `source_type`, so a `WorkWithForWeb` with the same name never masks a `WorkWith` row. `evidence_role` tells the part: `WorkWith layout attribute`, `WorkWith order attribute`, `WorkWith search attribute`, `WorkWith break by attribute`, or `WorkWith filter attribute`. Grid conditions, rules, events, captions, the base transaction and level, and links to other WorkWith objects are not read
- attribute reference (Smart Devices panel, since extractor 23): `Panel` to `Attribute` (`panel_references_attribute`, rule `sd_panel_attribute_reference`) from the same pattern instance a mobile `WorkWith` carries (`<Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889">`, a `<level><detail>` with a layout and a `<gridData>`), read by the same extractor with the same rules: layout `<data attribute>` (variables skipped), `<orders>`, `<search>`, and `<breakBy>` attributes, and `<filterAttribute>` advanced filters, one relation per object, attribute, and role. `evidence_role` reads `Panel layout attribute`, `Panel order attribute`, `Panel search attribute`, `Panel break by attribute`, or `Panel filter attribute`. A `Panel` and a `WorkWith` with the same name keep their own rows. The shape was checked in an X Evolution 2 and a GeneXus 16 public sample; grid conditions, rules, events, and captions are not read, and `Panel` stays `queryableByKbIntelligence=false` (it is listed in `who-uses` of an `Attribute`, but not accepted as the queried object)
- code attribute use (since extractor 15): `Procedure`, `WebPanel`, `Transaction`, and `DataProvider` to `Attribute` (`code_references_attribute`, rule `code_attribute_reference`) from the `<Source>` of code Parts selected by Part type GUID: Procedure Source (`528d1c06-a9c2-420d-bd35-21dca83f12ff`), Rules (`9b0a32a3-de6d-4be1-a4dd-1b85d3741534`) and Events (`c44bd5ff-f918-415b-98e6-aca44fed84fa`) of `Procedure`, `WebPanel`, and `Transaction`, and since extractor 20 of `WorkPanel` (Rules and Events), DataProvider Source (`1d8aeb5a-6e98-45a7-92d2-d8de7384e432`), and the DataProvider Rules Part, and since extractor 21 the Conditions Part (`763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9`) of `Procedure`, `WebPanel`, and `WorkPanel`, read like plain rules (role `Conditions read`; a condition only reads), when the attribute exists in the local inventory. WebForm and Layout Parts, and a bare `<Source>` outside any `<Part>`, are not read by this extractor (the other `Source` extractors keep reading every `<Source>`). `evidence_role` names the Part and the role: `Procedure Source read`, `Rules read`, `Events read`, `Conditions read`, `DataProvider Source read`, or the same Parts with `write` (`Procedure Source write`, `Rules write`, `Events write`, `DataProvider Source write`). The `write` role marks only an unambiguous assignment target: `Attribute = expression` at a statement start (first on its line, not continuing an expression from the line before, outside parentheses) inside a `for each` ... `endfor` or `new` ... `endnew` block of a Procedure Source or an Events Part (keywords in any case, blocks nested, also inside `if` and `do case`; the innermost `for each` or `new` decides, and its `when none` or `when duplicate` branch is not a write context, nor is a plain `for &i = ...` or `for &x in ...` loop on its own; an `Event` or `Sub` boundary closes every open block); a Transaction assignment rule `Attribute = expression [if condition];` (a rule that starts the Rules Part or follows `;`, and since extractor 17 also one that follows the `{` or `}` of a platform section such as `[web] { noaccept(Attribute); }`); since extractor 17, the attribute a Transaction `Default(Attribute, expression)` or `Equal(Attribute, expression)` rule assigns (its first argument) and the two a `Serial(Attribute1, Attribute2, step)` rule assigns (its first and second arguments), when the argument is a bare attribute name (not an `&variable`, a member, or a call) and the rule starts the Rules Part or follows `;`, `{`, or `}` (rule name in any case, with an optional trailing `if`, `on`, or `level` clause; in Procedure, WebPanel, and DataProvider Rules these rules stay reads); and an item's left side in a DataProvider whose output is a Transaction. Anything else stays a read: a top-level assignment in an Event or Procedure outside those blocks, `=` inside `where`, `if`, `case`, and other conditions, `parm(in:Attribute)` (receiving an attribute assigns nothing), the value expression of a `Default` or `Equal` rule, and a compound assignment such as `Attribute += 1`; `&trn.Attribute = ...` is a member and is not a use. A write occurrence gives no read row of its own; one relation per object, attribute, and role (the first occurrence in the Part, in document order, is the evidence; the line is the code line in the XML file), so an attribute both assigned and read in one Part has a `write` and a `read` row. The code is read with a tokenizer that skips `//` and `/* */` comments (a comment counts as whitespace: the name after it is read with the tokens before it), single-line string literals (`'...'`, `"..."`, `!"..."`), `&variables` and their members (`&sdt.Name`), every member after `.` (the legacy `.and.`, `.or.`, `.not.`, and, since extractor 21, `.like.` operators are not members, so the name after one is read), names followed on their own line by `(` or an object call method (`.udp(`, `.call(`, `.link(`, `.submit(`; a `(` that opens the next line does not count), the object named first in `udp(...)` and `call(...)`, the table named after `for each` on its line (`for each Movie.Actor`), a Domain of the inventory followed by `.Member` that is not a method call (an enumeration value: in `CompanyType = CompanyType.Startup` only the left side is a use), every name on an `Event` header line (`Event Enter`, `Event Grid1.Load`), the `Load` and `Refresh` commands alone on their line at a statement start (an attribute with that name elsewhere is still a use), and GeneXus keywords (`for`, `each`, `where`, `order`, `defined`, `by`, `new`, `when`, `none`, `duplicate`, `if`, `do`, `case`, `otherwise`, `sub`, `event`, `parm`, `in`, `out`, `inout`, `and`, `or`, `not`, `like`, `null`, and others); `Sub '...'` and `Do '...'` names are literals. Call arguments (`Proc(Name)`, `Proc.udp(Name)`, `udp(Proc, Name)`), method receivers (`Name.ToString()`), and the attributes after `where`, `order`, and `defined by` are uses. In a DataProvider Source, group headers (a name that starts a statement and is not followed by `=`, `.`, or `(`, such as `Recipes {` or `Recipes order Name`) are not uses; an item's left side (`Item = expression`) is a use, with the `write` role, only when the `OutputSDT` property names a Transaction (by its type GUID), since with an SDT output it names an SDT item and is not read
- classic code attribute use (since extractor 19; GeneXus 7.5 to 9 exports, root `dataSource="gx-legacy-export"`): a classic `Report`, `Procedure`, `WebPanel`, `Transaction`, or (since extractor 20) `WorkPanel` to `Attribute` (`code_references_attribute`, rule `code_attribute_reference`), resolved against the indexed `Attribute` objects (the sync materializes each `Attributes/GXAtt` entry of a classic export as one). It reads the same CDATA-unwrapped code sections as the classic calls, each like the matching modern Part, with the same tokenizer, roles, and one-relation-per-role rule as the code attribute use above: `<Source>` only for a `Report` (its `Layout/Block/CodeBlock/Source`, role `Report Source read` or `Report Source write`) and a `Procedure` (`Procedure Source read` or `write`), read as block code; `<Events>` (`Events read` or `write`), read as block code; and `<Rules>` (`Rules read`; in a `Transaction`, also `Rules write` for its assignment rules). So a statement-start assignment inside a `For Each` or `New` block of a `Report` Source or of `Events` is a write, an `&variable` is never a use, and a name that is not an indexed `Attribute` gives nothing. A `<Source>` outside a `<CodeBlock>` (the `WebPanel` `HTMLForm`, the `Documentation`, a `Report`'s layout print controls) is not read
- classic menu option (since extractor 21; GeneXus 7.0 and earlier `.xpw` exports): a classic `Menu` (folder `Menu`, token `gxlegacy/Menu`) is indexed and queried as its own type `Menu` (registry flag `indexedByKbIntelligence`, like `Report`). Each `<MenuOptions>` entry whose `PgmType` is `Menu`, `WorkPanel` (also written `Work Panel`), `Transaction`, or `Report` and whose `PgmName` names an indexed object of that type (case-insensitive) relates the `Menu` to it: `calls_menu`, `calls_workpanel`, `calls_transaction`, or `calls_report`, rule `classic_menu_option`, with the line of the option's `<PgmName>` as the evidence line. One relation per option (call site), so two options that call the same program give two rows. Other `PgmType` values (for example `Procedure`) are not mapped until a sample shows one. In the public samples, 74 options, all resolved (`WorkPanel` 36, `Transaction` 21, `Menu` 16, `Report` 1)
- classic formula (since extractor 21; `.xpw` exports): a classic `Formula` (folder `Formula`, token `gxlegacy/Formula`; its `<Formula><Name>` is the attribute it computes, plus `<Type>` and `<Source>`) stays a skipped orphan folder, not an indexed type, but its content is read through the attribute it computes: the relation source is the indexed `Attribute` named by the formula's `Name`, and the evidence file is the `Formula/<name>.xml` file. Calls in its `Source` with the `P` prefix give `formula_calls_procedure` (rules `classic_formula_udp_func`, `classic_formula_call_command`, `classic_formula_link`; evidence role `Formula`), like the modern attribute-formula calls. Every attribute its `Source` names is a use: `code_references_attribute`, rule `code_attribute_reference`, role `Formula read` (always a read; the computed attribute is not a use of itself; one relation per attribute). A formula whose attribute is not indexed gives nothing
- literal target via property: `CustomType:<value>` from `ATTCUSTOMTYPE`
- resolved target via property: `SDT`, `Domain`, or `ExternalObject` from `ATTCUSTOMTYPE`, when the object exists in the inventory and the approved rule safely resolves the prefix
- current sources of indexed `ATTCUSTOMTYPE`: `Procedure`, `WebPanel`, `DataProvider`, `API`, `DataSelector`, `Domain`, `SDT`, `WorkWithForWeb`, `Transaction`
- effective method call on an ExternalObject: `Procedure`, `WebPanel`, `DataProvider`, `Transaction`, `API`, `DataSelector`, `WorkPanel` to `ExternalObject` from `&Variable.Method(...)` in the effective `Source`, when the variable has a resolved `ATTCUSTOMTYPE` `exo:<ExternalObject>` in the local inventory
- base domain via `idBasedOn`: objects in scope `IDBASEDON_DOMAIN_SOURCE_TYPES` (`relation_scope` + `Attribute`; excludes `Panel`, `Stencil`, `PackagedModule`) to `Domain` from `<Property><Name>idBasedOn</Name>…>`, when the domain exists in the local inventory; masks CDATA/comments in a **single pass** (exclusive state per delimiter); the module suffix `Domain:Name, Module` only resolves if the Domain's `fullyQualifiedName` is `Module.Name` (case-insensitive comparison); `who-uses(Domain)` counts `based_on_domain` relation rows (no longer "Attribute only"); an `Attribute:…` value does not generate `based_on_domain`
- calculated-attribute call: `Attribute` to `Procedure`, `WebPanel`, or `DataProvider` from a `Formula` property, when the target exists in the local inventory and the form is statically resolvable (`Name(...)`, `Name.Call(...)`, `Call(Name, ...)`, `udp(Name, ...)`, `Name.Udp(...)`, `Name.Link(...)`, `Name.Create(...)`, a direct `DataProvider` call)
- formula attribute use (since extractor 21): `Attribute` to `Attribute` (`code_references_attribute`, rule `code_attribute_reference`, role `Formula read`): every attribute named in the `Formula` property of a modern `Attribute` is a use of that attribute, with the line of the property value as the evidence line (for example, the fixture `InvoiceTotal` formula `CalculateInvoiceTotal(InvoiceId)` gives `InvoiceTotal` → `InvoiceId`); the classic `Formula` gives the same relation (see "classic formula" above). The formula calls (`formula_calls_*`) are unchanged
- transaction structural attribute: `Transaction` to `Attribute` from `<Level>/<Attribute>`, when the attribute exists in the local inventory
- transaction structural table: `Transaction` to `Table` from `Type` in `<Level>`, when the table exists in the local inventory
- table key attribute: `Table` to `Attribute` from `<Key>/<Item>`, when the attribute exists in the local inventory
- table index member attribute: `Table` to `Attribute` from `<Index>/<Part>/<Members>/<Member>`, when the attribute exists in the local inventory
- classic structure (since extractor 22; classic exports, root `dataSource="gx-legacy-export"`): the four structural relations above, from the classic shapes, each with its own rule. A classic `Table` relates to the attribute of each `<Key>` entry (`has_key_attribute`, rule `classic_table_key_attribute`, role `Key Item`, the line of the `<Key>`) and of each `<TblIndex>/<IdxAttri>/<Name>` (`has_index_member_attribute`, rule `classic_table_index_member_attribute`, role `Index Member`, one relation per attribute like the modern one). A classic `Transaction` keeps its structure as text in `<Structure>/<Source>`: one attribute per line, `*` after a key attribute, `(` opening a sub-level and `)` closing it. Every attribute of every level relates (`has_level_attribute`, rule `classic_transaction_level_attribute`, role `Level Attribute`, the line of the attribute). A classic level names no table, so each level relates to the one classic `Table` whose key set equals the level's combined key set, the keys of its parent levels plus its own (`has_level_table`, rule `classic_transaction_level_table`, role `Level Keys`, the line that opens the level), whatever the names of the two objects; a level with no key of its own, or whose key set matches no classic `Table` or more than one, gives no `has_level_table`, and its attributes still relate. In the public 1997 sample, 21 of 21 levels match one `Table`. Every relation needs the attribute or table in the local inventory, as above. A classic `has_level_attribute` row carries `writability: null` in `who-uses`, because transactional writability is materialized from modern `<Level>` structures only
- SDT item type: `SDT` to `SDT` from `ATTCUSTOMTYPE` in `<Item>`, when the value has the `sdt:` prefix and the SDT exists in the local inventory
- explicitly navigated table: `Procedure` and `WebPanel` to `Table` from `for each <Name>` in the effective `Source`, when the table exists in the local inventory
- table prefix in qualified navigation: `Procedure` and `WebPanel` to `Table` from `for each <Name>.<Member>` in the effective `Source`, when `<Name>` exists as a table in the local inventory
- inferred base table of a classic `for each` (since extractor 24; root `dataSource="gx-legacy-export"`): a classic `Procedure`, `Report`, `WorkPanel`, `WebPanel`, or `Transaction` to `Table` (`navigates_inferred_table`, rule `classic_for_each_base_table`, role `For Each base table`, confidence `inferred`, the line of the `for each`). A classic `for each` names no table, so its base table is inferred the way GeneXus chooses it: the attributes of the block are those of its `where`, `order` (an old `for each A B` lists order attributes), `defined by`, and `using` clauses, its body, and the attribute controls of the print blocks it prints (a layout is read as its blocks in order; a control with a negative `<Id>` is a variable), without variables, names followed by `(`, nested `for each` blocks, `new` ... `endnew`, and `when none` sections. A classic `Table` holds its keys and the attributes of every Transaction level matched to it by `has_level_table` (the level's own attributes, formulas included, and its parent levels' keys); a `SubTypeGroup` whose supertypes hold the full key of exactly one `Table` acts as a table keyed by its subtypes. The extended table of a `Table` adds, repeatedly, every table or group whose full key it holds. The base table is the one candidate (a `Table` whose extended table holds every attribute of the block) that no other candidate is part of; when no candidate or more than one remains, there is no relation. Grid loops (`for each line`, `for each selected line`) and blocks inside a `new` give none. Measured on 100 blocks of 12 public classic samples (GeneXus 5 to 6): 83 answers, all correct when checked by hand, 0 wrong, 0 ambiguous; the 17 without a relation are template Procedures whose attributes are not in their KB and one subtype case GeneXus itself cannot resolve to a single table. Larger KBs may have blocks the samples do not show, hence `inferred`; confirm with the code of the block
- Business Component load: `Procedure`, `WebPanel`, `DataProvider` to `Transaction` from `&Variable.Load(...)` in the effective `Source`, when the variable has a resolved `ATTCUSTOMTYPE` `bc:<Transaction>` in the local inventory
- Business Component save: `Procedure`, `WebPanel`, `DataProvider` to `Transaction` from `&Variable.Save()` in the effective `Source`, when the variable has a resolved `ATTCUSTOMTYPE` `bc:<Transaction>` in the local inventory
- Business Component delete: `Procedure`, `WebPanel`, `DataProvider` to `Transaction` from `&Variable.Delete()` in the effective `Source`, when the variable has a resolved `ATTCUSTOMTYPE` `bc:<Transaction>` in the local inventory
- Business Component validation: `Procedure`, `WebPanel`, `DataProvider` to `Transaction` from `&Variable.Check()` in the effective `Source`, when the variable has a resolved `ATTCUSTOMTYPE` `bc:<Transaction>` in the local inventory
- simple Business Component insert/update: `Procedure`, `WebPanel`, `DataProvider` to `Transaction` from `&Variable.Insert()` or `&Variable.Update()` in the effective `Source`, when the variable has a resolved `ATTCUSTOMTYPE` `bc:<Transaction>` in the local inventory and does not have `AttCollection=True`
- relations: direct calls in the effective `Source`, `Procedure.Link(...)` in the effective `Source`, WebComponent creation via `<WebPanel>.Create(...)`, resolved `gxobject` actions, `WorkWithForWeb` action parameters with `Procedure.Link(...)`, explicit `Transaction` bindings, explicit `WebPanel` links and prompts in `WorkWithForWeb`, tag and attribute conditions of `WorkWithForWeb` calling `Procedure`, `WorkWithForWeb` attribute references (grids, filters, orders, views), `ATTCUSTOMTYPE` properties, method calls on an `exo:<ExternalObject>` variable, `idBasedOn`→`Domain` (`based_on_domain`, rules `attribute_idbasedon_domain`/`object_idbasedon_domain`), `Attribute` `Formula` (calls and, since extractor 21, attribute uses), classic `Menu` options and classic `Formula` blocks (since extractor 21), `Transaction` structural attributes and tables, `Table` key attributes and index members, resolved `SDT` internal types, tables declared in an explicit `for each`, table prefixes in a qualified `for each`, and resolved BC `.Load(...)`/`.Save()`/`.Delete()`/`.Check()`/`.Insert()`/`.Update()` calls to `Transaction`
- main artifact: the derived SQLite file

Basic extraction covers `DataProvider` as a source and as the target of a direct call, `Procedure.Link(...)` and `<WebPanel>.Create(...)` in the effective `Source`, `WorkWithForWeb` actions with a resolved `gxobject` to `Procedure` or `WebPanel`, `WorkWithForWeb` action parameters with `Procedure.Link(...)`, explicit `WorkWithForWeb` binding to `Transaction`, explicit `WorkWithForWeb` links and prompts to `WebPanel`, tag and attribute conditions of `WorkWithForWeb` calling `Procedure`, `WorkWithForWeb` attribute references in grids, filters, orders, and views, and `ATTCUSTOMTYPE` as a literal `CustomType`. It does not cover the full semantics of `Transaction`, nor `WorkWithForWeb` semantics beyond the cuts already covered. Semantic extraction expanded `for each`, `.Load(...)`, `CustomType` resolution to `SDT`, `Domain`, and `ExternalObject`, and effective method calls on an `exo:<ExternalObject>` variable.

`Procedure` call forms are resolved against the real inventory, without relying on local naming prefixes. Dynamic calls such as `Call(&Name)`, `Call(ATT:Att)`, or a program name in quotes stay outside the nominal graph.

They do not replace the XML corpus in `KbObjectsXml` and do not prove runtime behavior.

### Classic exports (GeneXus 7.5 to 9)

Since extractor 19, `who-uses`, `what-uses`, and `impact-basic` answer for objects synced from a classic export (root `dataSource="gx-legacy-export"`). A `.xpw` text export (GeneXus 7.0 and earlier) is translated by the sync into the same classic XML, so its objects get the same relations. In summary (the details are in the "classic calls", "classic code attribute use", "classic menu option", "classic formula", and "classic structure" items above):

- covered: a classic `Report` is indexed and queried as its own type `Report` (not as a `Procedure`); calls with the object-type prefixes `P` (`Procedure`), `R` (`Report`), `T` (`Transaction`), and `W` (`WorkPanel`) in `call(`, `udp(`, and `link(`; attribute references (`code_references_attribute`) from `<Source>` inside a `<CodeBlock>`, `<Rules>`, and `<Events>`, with read and write roles; since extractor 20, a `WorkPanel` as a call source and as the queried object, with its `<Rules>` and `<Events>` read for calls and attribute uses; since extractor 21, the `<Conditions>` of a classic `Report`, `Procedure`, `WebPanel`, and `WorkPanel`, read for attribute uses (role `Conditions read`, always a read); the classic call extractor reads the `<Conditions>` of any classic object for calls; since extractor 21, a classic `Menu` (`.xpw`) indexed and queried as its own type `Menu`, its options relating to the programs they call (`calls_menu`, `calls_workpanel`, `calls_transaction`, `calls_report`), and a classic `Formula` (`.xpw`) read through the attribute it computes (its `P` calls as `formula_calls_procedure` and its attribute uses, role `Formula read`); since extractor 22, the structural relations of a classic `Table` (`has_key_attribute` from its `<Key>` entries, `has_index_member_attribute` from its `<TblIndex>/<IdxAttri>`) and of a classic `Transaction` (`has_level_attribute` for every attribute of its `<Structure>/<Source>` text, and `has_level_table` for each level whose combined key set equals the key set of exactly one classic `Table`); `who-uses` on an `Attribute` lists `Report` and `WorkPanel` as partly extracted in its coverage
- not covered: a Web Panel call prefix (no sample shows one, so it is not mapped); a `Menu` option whose `PgmType` is not one of the four mapped (for example `Procedure`); a classic `Prompt` (`.xpw`), skipped at build time and not read, which reverse coverage counts (see "Coverage of reverse-relation answers"); the `Subroutines` blocks (seen in `.xpw` exports), which are synced but not read (in the public samples they hold no call and no attribute use); the base table of a classic `for each` whose attributes fit no table or more than one (see "inferred base table of a classic `for each`"), and of a grid loop or a block inside a `new`; the `has_level_table` of a classic level whose combined key set matches no classic `Table` or more than one; the transactional writability of a classic level attribute (`writability: null`)
- assumption: a classic `Procedure` keeps its code in `Layout/Block/CodeBlock/Source` like a `Report`, and a classic `Procedure` and `Transaction` keep their rules and events in the same `<Rules>` and `<Events>` tags as a `Report` and a `WebPanel`. For GeneXus 7.0 and earlier the public `.xpw` samples confirm the `Procedure` code location (154 `CodeBlock` blocks in 87 `Procedure` objects, 78 of them in the public GeneXus 6 samples, every one with its code in `Layout/Block/CodeBlock/Source`); for GeneXus 7.5 to 9 XML no export with a `Procedure` has been found (local and public searches, 2026-10-17), but the GeneXus 9.0 help gives a `Procedure` the same Layout, Rules, Subroutines, and Conditions tabs as a `Report` and describes a layout as code blocks and print blocks, and the GeneXus 8 `Report` exports keep their code there. Code kept anywhere else is not read, and a classic `Procedure` or `Report` with no `<CodeBlock>` at all is counted and disclosed by reverse coverage (see "Unread classic code" in "Coverage of reverse-relation answers"), so a different shape never reads as an unused object

An index built by extractor 18 or older holds none of these relations: the index gate reports it as built by an older extractor until it is rebuilt once.

## Python prerequisite

- Rebuilding the index requires a **usable Python 3.8 or later** on `PATH`, resolved by `scripts/GeneXusPythonPrerequisite.ps1` (called from `Build-KbIntelligenceIndex.ps1`, `Query-KbIntelligenceIndex.ps1`, and `Test-KbIntelligenceQueries.ps1`): it tries `python3`, then `python`, then `py -3`, and runs each candidate, so one that does not actually run is skipped.
- The Microsoft Store `WindowsApps` stub does not count; its absence returns exit `8` with the message `PREREQUISITE MISSING`.
- A Python engine failure in `Build-KbIntelligenceIndex.ps1` forwards the captured output and preserves the `.py`'s exit code (including exit `2` for an invalid/blocked catalog override).
- **Rigor**: an official XPZ/XML sync does **not** finish without a regenerated index — materialization into `KbObjectsXml` may already have completed; state an **incomplete flow**, not sync-OK nor an export-package failure; do not authorize broad triage without an index; see `README.md`, `08-agent-guide.md`, and `sync.md`.

## Generate the index

Every command in this reference uses the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`); `<mimir-lite-root>` and `<KbWorkspace>` stand for absolute paths.

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Build-KbIntelligenceIndex.ps1" -SourceRoot "<KbWorkspace>/KbObjectsXml" -OutputPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -ValidationReportPath "<KbWorkspace>/KbIntelligence/kb-intelligence-validation.json" -ValidationCasesPath "<mimir-lite-root>/tests/fixtures/kb-intelligence-sample-kb.validation-extraction.json" -FailOnValidationFailure
```

Replace `<KbWorkspace>` with the real KB workspace folder (e.g. `C:\KBs\SampleKb`). Swap `-ValidationCasesPath` for the battery whose inventory matches that KB.

This repository ships no batteries for real KBs, for privacy: such a battery names a real third-party KB and its inventory. The reproducible equivalent, with no external-KB dependency, is the synthetic `tests/fixtures/sample-kb/` fixture, with `tests/fixtures/kb-intelligence-sample-kb.validation-extraction.json`/`...-queries.json`, exercised by `Test-KbIntelligenceSampleKbSelfTest.ps1`. To validate against your own real KB, generate your own case battery in the same format.

To validate extended extraction with the synthetic `sample-kb` fixture, use:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Build-KbIntelligenceIndex.ps1" -SourceRoot "<KbWorkspace>/KbObjectsXml" -OutputPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -ValidationReportPath "<KbWorkspace>/KbIntelligence/kb-intelligence-validation.json" -ValidationCasesPath "<mimir-lite-root>/tests/fixtures/kb-intelligence-sample-kb.validation-extraction.json" -FailOnValidationFailure
```

The standard operational location inside the KB workspace is `KbIntelligence\kb-intelligence.sqlite`. This database is derived and regenerable; the normative source remains `KbObjectsXml`.

## Operational freshness of the index

The index should only be used for broad triage when it is up to date with the corpus's latest XPZ/XML materialization.

- `last_xpz_materialization_run_at` lives in `kb-source-metadata.md` at the KB workspace root.
- `last_index_build_run_at` lives in the `metadata` table of `KbIntelligence\kb-intelligence.sqlite`.
- `last_index_build_run_at` is also mirrored into `KbIntelligence\kb-intelligence-validation.json` when the validation report is generated.
- `inventory_validation_status` lives in the SQLite `metadata` table and must be `OK`.
- `generated_at` is no longer part of the index's operational contract; if it appears in an old artifact, treat that index as legacy/incompatible and regenerate.
- Every successful processing of an IDE-exported `XPZ` that materializes or updates XML in `KbObjectsXml` must trigger index regeneration/validation right after.
- If `last_index_build_run_at >= last_xpz_materialization_run_at`, `inventory_validation_status=OK`, and `extractor_signature_version`/`extractor_signature_hash` in the metadata match the current engine in `scripts/Build-KbIntelligenceIndex.py` (via `scripts/GeneXusKbIntelligenceExtractorContract.ps1`), the index is fit for initial triage.
- A missing `extractor_signature_version` or `extractor_signature_hash` in the metadata, or a mismatch against the shared engine, means the index was built by an old extractor even when timestamps look fresh — `Test-*KbIndexGate.ps1` blocks with `BLOCK:` and the correct response is to rebuild the index.
- If the index is missing, has no metadata, is older than the latest materialization, or `kb-source-metadata.md` does not literally expose `last_xpz_materialization_run_at`, the agent must not perform substantive triage or read official object XML to answer a business question — neither via a broad scan nor via a deduced targeted path. This gate governs read-side access only; generating, cloning, packaging, building, or importing GeneXus objects is out of scope regardless of gate status.
- If `inventory_validation_status` is missing, `BLOCK`, or anything other than `OK`, treat the index as semantically incompatible with the official snapshot and offer a rebuild/refresh before any broad triage.
- In that stale state, treat it as an operational exception, offer index regeneration/validation to the user, and do not proceed to a broad scan, substantive triage, a deduced targeted path, or an official object XML read.
- A targeted read with a blocked gate should only happen for a minimal diagnosis of the incompatibility, in local documentation, structure, wrappers, and operational metadata; do not assemble, test the existence of, list, or open an official object XML path as a fallback to answer a business question.
- The gate must be sequential and atomic; do not test a child path before its parent layer, e.g. `KbIntelligence\kb-intelligence.sqlite` before `KbIntelligence`.
- If the documented local index-query wrapper is missing, do not list `scripts` or look for alternative wrappers, backups, or similar names; treat it as KB-workspace drift and offer a refresh via setup.
- Do not substitute `last_xpz_materialization_run_at` with a file date, `updated`, `generated_at`, `source_xpz`, a report date, or any other approximate metadata.

To read the index metadata via the wrapper:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query index-metadata -Format text
```

If `index-metadata` fails, returns empty, or does not expose `last_index_build_run_at` or `inventory_validation_status`, treat the index as legacy/incompatible or without valid metadata. Do not proceed to substantive triage, broad search, a deduced targeted path in `KbObjectsXml`, or an official object XML read; offer index regeneration/validation to the user. This read-side gate never authorizes GeneXus object edits or in-scope object generation.

When index validity is a relevant part of the answer or handoff, record the decision briefly. In a fit case, state `last_index_build_run_at >= last_xpz_materialization_run_at`, `inventory_validation_status=OK`, and a matching extractor signature; in a blocked case, state the missing field/capability, which timestamp is stale, a missing/stale extractor signature, or which inventory semantic incompatibility was detected.

## Extractor signature (`extractor_signature_*`)

The `Build-KbIntelligenceIndex.py` engine writes to the `metadata` table:

- `extractor_signature_version` — incremented whenever the indexer's coverage or rules change materially
- `extractor_signature_hash` — SHA-256 of the bytes of the `Build-KbIntelligenceIndex.py` used for the build

Shared contract: `scripts/GeneXusKbIntelligenceExtractorContract.ps1`. Verification: `Test-GeneXusKbIntelligenceExtractorSignatureSelfTest.ps1` (sentinel `KB_INTELLIGENCE_EXTRACTOR_SIGNATURE_SELFTEST_OK`).

The `Test-*KbIndexGate.ps1` gate (template in `workflows/setup/examples/Test-KbIndexGate.example.ps1`) compares the index's metadata against the active repository's engine. Old indexes without these fields pass the timestamp check but fail this step — expected behavior after an evolution such as an `INDEXED_SOURCE_TYPES` expansion.

## Schema and versioning

The index stores `schema_version` in the `metadata` table. The current value is `"5"` (it includes the `transaction_attribute_writability` table with `writability_rule_version`, the `css_class` table for the CSS class catalog, and the `is_generated_object`/`pattern_object_id`/`instance_key` columns in the `objects` table). Version `"5"` stores `metadata.source_root` relative to the index folder, with `/` separators, so the index keeps working when it moves together with its corpus; the absolute path is stored only when no relative path exists (for example, the corpus on another Windows drive).

This is deliberate: the index is a derived, always-regenerable artifact. There is therefore no schema migration path — any structural engine change requires a full rebuild.

Operational consequences:

- Every index built before `schema_version` was introduced is automatically treated as incompatible and blocks any query with an explicit rebuild message.
- With every schema evolution (`"1"` → `"2"` → `"3"` → `"4"` → `"5"`), every index at an earlier version blocks the same way — expected behavior, not a bug.
- The schema-version error is detected by `Query-KbIntelligenceIndex.py` itself before any query, including `index-metadata`; so `Test-*KbIndexGate.ps1` also fails with `BLOCK:` on incompatible indexes.
- The correct response to any schema-version block is a rebuild via `Build-KbIntelligenceIndex.ps1`, never a workaround via a direct SQLite or XML read.

## Pattern-generated objects (authored vs. generated)

The `objects` table carries three columns to separate objects GENERATED by a Pattern (WorkWith For Web) from AUTHORED ones **deterministically**, with no name heuristic (`ww*`/`*WC`/`*General`/`*Selection`):

- `is_generated_object` (`INTEGER NOT NULL DEFAULT 0`): `1` when the object has the object-level `IsGeneratedObject=True` property; `0` otherwise. The flag marks pattern-instance output only and says nothing about authorship: `0` never means "hand-written". Objects with `0` may still be generated by GeneXus, for example Tables derived from Transactions, objects in core modules, or SDTs that support a pattern. The `--authored` filter below means "not pattern-instance output", nothing more.
- `pattern_object_id` (`TEXT`, nullable): the Pattern role (e.g. `TabGrid`, `TabTabular`, `View`, `Selection` in WebPanel; `ExportSelection`, `ExportTabGrid` in Procedure).
- `instance_key` (`TEXT`, nullable): the owning instance — `<WorkWithForWeb type-GUID>-<WorkWith instance name>`. Can be null even with `is_generated_object=1` (e.g. some generated Procedures).
- `instance_name` (a **derived** field, not a column): the instance name extracted from `instance_key` by the query engine, in `object-info`/`search-objects`/`list-by-type` (not in `attribute-info`, nor in `transaction-attributes`/`transaction-writable-attributes`). Always present in the output, `null` when it cannot be derived (a null or non-canonical `instance_key`). Derivation is anchored on the canonical GUID (`8-4-4-4-12`) plus the first hyphen; never a blind `split` (internal hyphens in the name are preserved). The `pattern_object_id → name-shape` mapping (`Selection`=`WW<name>`, `TabTabular`=`<name>General`, etc.) is a **GeneXus convention, not a repository contract**.

Extraction is **scoped to the ROOT object's `<Properties>`** (byte-level XML parse; a regex fallback over the last `<Properties>` block only for malformed XML), never from an `<Object>` nested inside a container type (`PackagedModule`, which packages a library with internally flagged objects). All three fields appear in the `object-info`/`search-objects`/`list-by-type` JSON; in `--format text`, `object-info` shows all three plus `instance_name`; `search-objects`/`list-by-type` show `generated=0/1` and, when derivable, `instance_name=<name>` (compact list output). The index metadata carries `generated_objects_count`.

Deterministic filter (`--generated`/`--authored`, mutually exclusive, on `search-objects` and `list-by-type`; `-Generated`/`-Authored` switches on the `.ps1` wrapper):

- `Query-KbIntelligenceIndex.ps1 -IndexPath <sqlite> -Query list-by-type -ObjectType WebPanel -Generated` — generated only
- `Query-KbIntelligenceIndex.ps1 -IndexPath <sqlite> -Query list-by-type -ObjectType WebPanel -Authored` — authored only

### Reverse lookup by instance (`-InstanceKey`)

`search-objects` accepts `-InstanceKey` (`--instance-key`) to list the objects generated by a given WorkWithForWeb instance. The engine **auto-detects** the argument's shape (contract rule):

- a **plain instance name** (e.g. `WorkWithWebExemplo`) → **exact, case-insensitive** match (`casefold`) against the derived `instance_name`;
- a **full key** `<canonical GUID 8-4-4-4-12>-<name>` → **exact, case-insensitive** match (SQLite `LOWER`) against `instance_key`;
- `<GUID>-` with no name → an **error** (incomplete key); a plain GUID with no hyphen falls through to the name path (no object matches).

The match is always **exact, never partial** (`WorkWithWebFoo` does not match `WorkWithWebFooBar`). It combines with `-ObjectType`, `-Generated`/`-Authored`, and `-Limit`; with `-ObjectName`, the two filters combine with **AND**. `search-objects` now requires **at least one** of `-ObjectName`/`-InstanceKey`. `-InstanceKey` is **only** valid on `search-objects` (on another query → error `--instance-key is only valid with search-objects.`).

- `Query-KbIntelligenceIndex.ps1 -IndexPath <sqlite> -Query search-objects -InstanceKey WorkWithWebExemplo` — objects generated by that instance (by name)
- `Query-KbIntelligenceIndex.ps1 -IndexPath <sqlite> -Query search-objects -InstanceKey <GUID>-WorkWithWebExemplo` — same, by full key

**Case note (ASCII):** the case-insensitive comparison for the **full key** uses SQLite's `LOWER()` (ASCII); the one for the **name** uses Python's `casefold()` (Unicode). The difference only matters for a non-ASCII instance name — the GeneXus convention is ASCII.

**Performance note:** in name mode without `-ObjectName`/`-ObjectType`, the query scans the whole table and derives each row's name; `-Limit` trims **after** the filter (it does not reduce the scan).

## Exploratory triage in PowerShell

Use short, auditable queries when you need to measure a pattern's footprint before proposing a new increment. On Windows, prefer several small steps over one long one-liner.

The snippets below are PowerShell code, not script invocations: run them through the agent tool's PowerShell shell when it has one; otherwise save the snippet as a `.ps1` file under the workspace's `Temp/` folder and run that file with the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`).

Suggested triage order:

1. Count raw occurrences.
2. Group by the relevant value or prefix.
3. Open a short sample of real positive and negative cases.
4. Measure how many cases actually resolve against the local inventory.

If a grouping or regex unexpectedly returns zero, do not immediately conclude the signal is absent. First open a real occurrence in the KB's XML to check the property's actual shape, and only then adjust the extractor.

After splitting by prefix, do not treat a promising prefix as a resolved relation. Before proposing an increment, measure how many cases of that prefix actually point at an object that exists in the local inventory. Textually or semantically close prefixes, like `exo:` and `ext:`, can have different methodological behavior and should not be merged by intuition.

Count raw `ATTCUSTOMTYPE` occurrences in the corpus:

```powershell
Get-ChildItem -Path "<KbWorkspace>\KbObjectsXml" -Recurse -File |
  Select-String -Pattern 'ATTCUSTOMTYPE' |
  Measure-Object
```

Group `ATTCUSTOMTYPE` values by observable prefix:

```powershell
Get-ChildItem -Path "<KbWorkspace>\KbObjectsXml" -Recurse -File |
  Select-String -Pattern 'ATTCUSTOMTYPE="([^"]+)"' -AllMatches |
  ForEach-Object { $_.Matches } |
  ForEach-Object { ($_.Groups[1].Value -split ':', 2)[0].ToLower() } |
  Group-Object |
  Sort-Object Count -Descending
```

Open a short sample of real values before deciding on a contract:

```powershell
Get-ChildItem -Path "<KbWorkspace>\KbObjectsXml" -Recurse -File |
  Select-String -Pattern 'ATTCUSTOMTYPE="([^"]+)"' -AllMatches |
  ForEach-Object { $_.Matches } |
  ForEach-Object { $_.Groups[1].Value } |
  Select-Object -First 30
```

Avoid:

- a long one-liner with many interpolations, `:`, and sub-expressions on the same line
- deciding on a new increment from raw textual occurrences alone
- jumping from a raw count to a contract change with no real sample

## Search objects by name

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query search-objects -ObjectName "*ExemploPlanilha*" -Limit 10 -Format text
```

## Locate an object

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query object-info -ObjectType Procedure -ObjectName procSampleVolumeSpreadsheet -Format text
```

## Query an attribute and transactional writability

For a light attribute query, without scanning XML in bulk:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query attribute-info -ObjectName ClienteTotal -Format text
```

To list a Transaction's attributes with **materialized** writability classification (parity with the gate; requires an index with the current `schema_version`, `"5"`):

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query transaction-writable-attributes -ObjectName Cliente -Format text
```

The `transaction-attributes` and `transaction-writable-attributes` queries read the classification **materialized** at build time (`transaction_attribute_writability`). `Build-KbIntelligenceIndex.py` computes it with the canonical classifier `GeneXusTransactionWritabilityCore.py` (key, redundant, formula, and subtype rules), so the index is the single source of the classification; no separate per-Transaction gate exists. `unclassified-*` attributes (`writable=null`) need an additional XML read before drawing any conclusion about them.

The `attribute-info`, `transaction-attributes`, and `transaction-writable-attributes` queries depend on the `source_root` recorded in `index-metadata` and read the XML files the index points at from disk. The stored `source_root` is relative to the folder that contains the index file, with `/` separators (for example `../KbObjectsXml`), so the index keeps working when it is moved or copied together with its corpus, with the same relative layout, to another folder, machine, or OS. When no relative path exists (on Windows, a corpus on another drive), the absolute path is stored; an absolute value, including one written by an older build, is read as is. `index-metadata` also reports `resolved_source_root`, the folder the queries actually read (the text output prints `resolved_source_root: (not recorded)` when the index has no `source_root`). If the materialized snapshot was moved without the index, deleted, or regenerated outside that path, or only the `.sqlite` file was copied, the query can fail with `Indexed XML file not found`; the message names the `resolved_source_root` it looked under. Restore the snapshot at the expected path, or regenerate the index from the current `KbObjectsXml`, before repeating the query.

`attribute-info` reports `isFormula` and `formulaExpression` from the attribute's `Formula` property; for a classic attribute (GeneXus 9 and earlier exports), whose formula is its own object in the corpus folder `Formula` (`Formula/<Name>.xml`, `<Formula><Name>` and `<Source>`, the file the builder reads for formula relations), it reads that file instead, so a classic formula reports `isFormula: true` and its expression: a horizontal formula's `<Source>`, or for a vertical one its `<Type>` function applied to the `<Source>` (`<Type>SUM</Type>` with `FacTotLin` reads `sum(FacTotLin)`).

## Validate attribute and transactional writability queries

After generating or locating a valid SQLite index with a valid `source_root`, a materialized snapshot at the expected path, and the current `schema_version` (`"5"`), validate `attribute-info` (light), `transaction-attributes`, and `transaction-writable-attributes` (materialized) with:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Test-KbIntelligenceQueries.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -ValidationCasesPath "<mimir-lite-root>/tests/fixtures/kb-intelligence-sample-kb.validation-queries.json" -ValidationReportPath "<KbWorkspace>/KbIntelligence/kb-intelligence-validation-queries-writability.json" -FailOnValidationFailure
```

These cases check dispatch, non-existence, and a targeted file-backed read. `attribute-info` reports attribute facts only; the `transaction-writable-attributes` query is the source for writability classification, and reflects the classification `GeneXusTransactionWritabilityCore.py` materialized at build time (see above).

Since these cases validate queries and carry a `query` field, they belong to the `Test-KbIntelligenceQueries.ps1` runner, not to the `Build-KbIntelligenceIndex.ps1` regeneration flow.

## Query who uses an object

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query who-uses -ObjectType Procedure -ObjectName procSampleVolumeSpreadsheet -Limit 10 -Format text
```

In `who-uses`, `what-uses`, `impact-basic`, `functional-trace-basic`, `show-evidence`, and `css-class-usage`, each row's `source_file` comes from its evidence row (`evidence.source_file`), not from the source object: it is the source object's file for every relation except a classic formula's, whose evidence file is the `Formula/<name>.xml` file instead of the file of the `Attribute` it computes.

For an `Attribute` target, each `has_level_attribute` row whose source is a Transaction also carries `writability`: that Transaction's materialized classification of the attribute (see "Query an attribute and transactional writability"), the same object a `transaction-writable-attributes` row gives (`transaction`, `levelName`, `attribute`, `key`, `isRedundant`, `classification`, `writable`, `canAssignInNew`, `reason`, `evidence`, `writabilityRuleVersion`, `attributeFile`) without `isFormula` and `formulaExpression`, which that query reads from the attribute's XML file; `who-uses` keeps reading the index alone. `writability` is `null` when the Transaction has no materialized row for the attribute, and rows from other relations carry no `writability` field. The `dependents` of `impact-basic` carry the same field. In `text`, the row gets one more line:

```text
- #11 Transaction:Invoice -> Attribute:CustomerId [has_level_attribute, direct]
  Transaction/Invoice.xml:5 Level Attribute via transaction_level_attribute
  <Attribute key="False">CustomerId</Attribute>
  writability: [Invoice] classification=extended-fk-key writable=True reason=extended-fk-key
```

When `writability` is `null`, that line reads `writability: (no materialized row)`.

The classification is direct evidence from the index: an `extended-fk-key` row states that the attribute is a foreign key in that Transaction, so the answer does not need to infer it from the level structure.

### Coverage of reverse-relation answers

Answers that list or count an object's callers or users (`who-uses`, `impact-basic`, `functional-trace-basic`, and the `incoming_relations` count of `object-info`) carry a `coverage` object in JSON:

```json
"coverage": {
  "complete": false,
  "unextracted_source_types": [{"type": "Panel", "count": 12}, {"type": "WorkWith", "count": 3}],
  "partially_extracted_source_types": [],
  "unread_classic_code": [],
  "implicit_navigation_source_types": [],
  "scope": "calls"
}
```

- `scope` is `calls` for every target type except `Attribute` and `Table`, `attribute_references` for an `Attribute` target (see the last item of this list), and `table_navigation` for a `Table` target (the type is compared ignoring case).
- Scope `table_navigation` (a `Table` target): a table is navigated without an extracted relation by a grid or form (a `WebPanel`, `WorkPanel`, or `Transaction`, and the `WorkWith`, `WorkWithForWeb`, and Smart Devices `Panel` patterns), which navigates the table of its attributes, and by a `for each` or Data Provider group that names no table, which navigates the base table GeneXus infers: a modern one is never related, and a classic `for each` is related (`navigates_inferred_table`) only when one table fits. The index relates a table only to the `for each` blocks that name it or its prefix, to inferred classic base tables, and to Transaction levels. `implicit_navigation_source_types` therefore lists, with their counts, the indexed objects of `IMPLICIT_TABLE_NAVIGATION_SOURCE_TYPES` (`DataProvider`, `Panel`, `Procedure`, `Report`, `Transaction`, `WebPanel`, `WorkPanel`, `WorkWith`, `WorkWithForWeb`); any entry makes `complete=false`, and those types are not listed again under `unextracted_source_types`. The field is empty in the other scopes. The `text` line adds `navigation that names no table is not extracted from Procedure (n), ...: grids and forms, and a for each or Data Provider group without a table name (...); only for each blocks that name the table or its prefix, inferred classic base tables and Transaction levels are indexed; navigations from those types can be missing, so an empty or short list does not prove the table is unused`. Confirm a table's users with a literal search for its attributes in the XML of the listed types.
- Rule (scope `calls`): a type is listed when its objects carry code or bindings that reference other objects (events, a `Source` part, or declarative bindings such as the task bindings and conditions of a GXflow Business Process Diagram), but the extractor does not read those references. The current list is `BusinessProcessDiagram`, `OfflineDatabase`, `Panel`, `SmartDevicesApplication`, and `WorkWith` (`UNEXTRACTED_CALL_SOURCE_TYPES` in `Query-KbIntelligenceIndex.py`), plus `WorkPanel` on an index whose `extractor_signature_version` is below 20 or missing (`CALL_SOURCE_TYPES_EXTRACTED_SINCE`), since earlier extractors did not read its code; none of them is in the effective-`Source` scope above, and the action/link extractors that also receive `WorkWith` match only the web Work With XML shape. This section is the single place that lists them; other documents point here.
- `complete=false` when the index holds at least one object of those types, or counts a skipped legacy orphan (see the item on skipped legacy orphans below); each entry gives the type and its object count in the index (for a skipped legacy orphan, the XML count of its folder). `complete=true` with an empty list otherwise.
- `partially_extracted_source_types` lists types whose references are extracted only in part, each with `type`, `count`, `extracted` (what is read), and `missing` (what is not read); the `text` line is built from these two lists. It is always empty for scope `calls`; for scope `attribute_references` see the last item of this list. A non-empty list also makes `complete=false`.
- The `text` format prints one extra line starting with `coverage: incomplete` when coverage is incomplete, and nothing when it is complete.
- Exit codes do not change. Forward answers (`what-uses`) carry no `coverage` object.
- With incomplete coverage, an empty or short caller list is not proof that the object is unused: callers of the listed types can be missing. Confirm with a literal search in the XML of those types.
- Unread classic code (since extractor 25): the build counts the classic `Procedure` and `Report` objects (root `dataSource="gx-legacy-export"`) that hold no `<CodeBlock>` at all, whose code is therefore not read (an empty `<CodeBlock>` is empty code and is not counted, and `<CodeBlock>` written inside a CDATA section or an XML comment is text, not an element), and writes the index metadata `legacy_unread_code_counts`, a JSON object of type to count. Reverse answers in both scopes list them in `unread_classic_code` (`[{"type": "Procedure", "count": n}]`, empty when there are none), which makes `complete=false`, and the `text` line adds `the code of classic Procedure (n) ... was not found in Layout/Block/CodeBlock, where classic exports are expected to keep it, so their calls and attribute uses are missing`. No known export has such an object; the counter exists because no GeneXus 7.5 to 9 `Procedure` sample has confirmed the code location (see the classic assumption above). An index built before the key existed lists none. With it listed, read those objects' XML to find where their code is.
- Skipped legacy orphans: coverage also counts the legacy elements skipped at build time whose content is not read. The build writes the index metadata `legacy_unread_orphan_counts`, a JSON object of folder to XML count with every folder in `legacy_orphan_directories_skipped` (validation report) except `Formula`, whose content is read through the attribute it computes (see "classic formula" above). Reverse answers in both scopes (`calls` and `attribute_references`) append each folder as `{"type": <folder>, "count": n}` to `unextracted_source_types`, so a classic or `.xpw` KB with a `Prompt` (a `Prompt` has events and rules) reports `complete=false` and the `text` line names `Prompt (1)`. Today only `Prompt` qualifies. An index built before the key existed lists none. The `Subroutines` blocks of classic and `.xpw` objects are not counted and never make coverage incomplete. With `Prompt` listed, confirm callers and attribute uses with a literal search in the `Prompt/` folder of the corpus.
- Classic objects: coverage entries are per type, so a classic `WebPanel`, `Procedure`, `Transaction`, or `WorkPanel` shares the entry of its modern type and its `missing` list uses modern names: for a classic object, "WebForm bindings" stands for the `HTMLForm`, and "code outside a Part" for a `<Source>` outside a `<CodeBlock>` and the `Subroutines` blocks, none of which is read. A classic `Procedure`'s "Source reads" relies on the assumption that its code sits in `Layout/Block/CodeBlock/Source` (see "Classic exports"). An index built by an older extractor cannot misstate classic coverage in an agent flow: the index gate blocks a stale extractor signature before any reverse query, and each partly extracted part carries the extractor version that first read it.
- Scope `attribute_references` (an `Attribute` target): besides the structural relations to attributes (`has_level_attribute` from Transaction levels, `has_key_attribute` and `has_index_member_attribute` from Table keys and indexes), the attribute-use relations are `workwith_references_attribute` from `WorkWithForWeb` grids, filters, orders, views, and filter conditions and from mobile `WorkWith` layouts, orders, search, break by, and filters, `panel_references_attribute` (since extractor 23) from Smart Devices `Panel` layouts, orders, search, break by, and filters, and `code_references_attribute` from the code Parts of `Procedure`, `WebPanel`, `Transaction`, `DataProvider`, and `WorkPanel` and the code sections of classic objects, a classic `Report` included (the read role, and the write role for unambiguous assignment targets), and since extractor 21 from the formula of an `Attribute` (the modern `Formula` property and the classic `Formula` named after it, role `Formula read`); no other type emits attribute-use relations (grids, filters, code, rules, formulas, conditions of the types not listed here). `unextracted_source_types` uses `UNEXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES`: the calls list above plus `API`, `DataSelector`, `DataView`, `Query`, `SDT`, and `WorkWithPlusInstance`, minus the partly extracted types (`WorkWith` and `Panel` stay unextracted call sources), plus `Attribute` on an index whose `extractor_signature_version` is below 21 or missing (`ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE`), since earlier extractors did not read formulas, and the counted skipped legacy orphans (item above), so on almost any KB coverage is `complete=false`. `partially_extracted_source_types` uses `PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES`: `WorkWith` with `extracted: ["layouts", "orders", "search", "break by", "filters"]` and `missing: ["grid conditions", "rules", "events", "captions"]`; `Panel` with the same `extracted` and `missing` lists as `WorkWith`; `WorkWithForWeb` with `extracted: ["grids", "filters", "orders", "views", "filter conditions"]` and `missing: ["captions", "parameters", "tab conditions", "code"]` (view captions, view and action parameters, tab `condition` attributes, and `<variable>` or event code are not read); `Procedure` with `extracted: ["Source reads", "rule reads", "block writes", "condition reads"]` and `missing: ["ambiguous writes", "layout", "Business Component members", "code outside a Part"]`; `WebPanel` with `extracted: ["rule reads", "event reads", "block writes", "condition reads"]` and `missing: ["ambiguous writes", "WebForm bindings", "Business Component members", "code outside a Part"]`; `Transaction` with `extracted: ["rule reads", "rule writes", "event reads", "block writes"]` and `missing: ["ambiguous writes", "WebForm bindings", "Business Component members", "code outside a Part"]`; `Report` (classic) with `extracted: ["Source reads", "rule reads", "block writes", "condition reads"]` and `missing: ["ambiguous writes", "layout", "Business Component members"]`; `WorkPanel` (classic and modern) with `extracted: ["rule reads", "event reads", "block writes", "condition reads"]` and `missing: ["ambiguous writes", "Windows form bindings", "Business Component members", "code outside a Part"]`; and `DataProvider` with `extracted: ["Source reads", "rule reads", "Transaction item writes"]` and `missing: ["SDT output items", "Business Component members", "code outside a Part"]` (block writes: statement-start assignments inside `for each` and `new` blocks; rule writes: Transaction assignment rules; Transaction item writes: item left sides of a DataProvider whose output is a Transaction; ambiguous writes: any other assignment target, indexed as a read; condition reads: the attributes of a Conditions Part or a classic `<Conditions>`, always reads; layout and WebForm: Parts this extractor does not read; SDT output items: the items of a DataProvider whose output is an SDT, not read; Business Component members: `&bc.Attribute`, skipped as a member; code outside a Part: a `<Source>` not inside a `<Part>`, which this extractor does not read). Each extracted part carries the extractor version that first indexed it (`WorkWithForWeb` grids, filters, orders, and views: 13; filter conditions: 14; the code reads and writes: 15; the `WorkWith` parts: 18; the classic `Report` parts: 19; the `WorkPanel` parts: 20; condition reads: 21; the `Panel` parts: 23), compared with the index's `extractor_signature_version`: on an index built by extractor 13 the `WorkWithForWeb` entry reads `extracted: ["grids", "filters", "orders", "views"]` and `missing` starts with `"filter conditions"`, and a type none of whose parts the index's extractor read (`WorkWith` before 18; `Report` before 19; `Panel` before 23; `WorkPanel` before 20; `Procedure`, `WebPanel`, `Transaction`, and `DataProvider` before 15; every partly extracted type on an index older than 13 or without a numeric version) is listed under `unextracted_source_types` instead, so an old index never claims what its extractor did not read. The `text` line joins the parts that apply: `coverage: incomplete - attribute uses (grids, filters, code, rules, formulas) from ... are not extracted; attribute uses are partly extracted from Procedure (N): Source reads, rule reads, block writes and condition reads are indexed, ambiguous writes, layout, Business Component members and code outside a Part are not; ...; WorkWithForWeb (N): grids, filters, orders, views and filter conditions are indexed, captions, parameters, tab conditions and code are not; otherwise only structural relations (Transaction levels, Table keys and indexes) are indexed, so an empty or short list does not prove the attribute is unused`; the first part is left out when no unextracted type is indexed and no skipped legacy orphan is counted (since extractor 21 `Attribute` is not on the unextracted list, so a KB whose attribute consumers are all partly extracted types gets only the second part) and the second when no partly extracted type is. Confirm attribute uses with a literal search for the attribute name in the XML of the listed types, including the parts the `missing` lists name.

## Query what an object uses

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query what-uses -ObjectType WebPanel -ObjectName wpSampleVolumeMovementReports -Limit 10 -Format text
```

## Query evidence

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query show-evidence -SourceType WebPanel -SourceName wpSampleVolumeMovementReports -TargetType Procedure -TargetName procSampleVolumeSpreadsheet -Format text
```

## Basic impact triage

The `impact-basic` command summarizes an object's direct dependents and direct dependencies, without changing the extraction scope.

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query impact-basic -ObjectType Procedure -ObjectName procSampleVolumeSpreadsheet -Limit 10 -Format text
```

To audit a specific relation returned by `impact-basic`, use `show-evidence`.

This query represents direct technical impact based on the index. It does not prove complete runtime impact.

## Basic functional triage

The `functional-trace-basic` command builds an initial trail for short functional questions:

- locates the main object
- combines direct dependents and dependencies
- prioritizes resolved, local objects over `CustomType` literals
- hides a redundant `CustomType` literal when an equivalent resolved relation exists on the same line
- flags the official XML files the agent should open
- returns a structured trail for a short functional answer

It does not open XML automatically, does not interpret business rules, and does not replace reading the official XML.

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query functional-trace-basic -ObjectType Procedure -ObjectName procSampleAdjustOrderItemIds -Limit 20 -Format text
```

## CSS class catalog and usage (`css-classes`, `css-class-usage`)

The index catalogs the KB's CSS classes (`css_class` table) and tracks where they are used (`uses_css_class`/`uses_css_class_dynamic` relations in `relations`/`evidence`), covering the two false "does not exist" failure modes: an incomplete inventory (a `DesignSystem`'s classes never become an object) and invisible usage (assignment via code, `Control.Class = ...`, not just `class="..."` in the layout).

Layer 1 — catalog. `css_class` unifies the two theme models, with `model` (`legacy-theme` from `ThemeClass` objects | `design-system` from SCSS in `DesignSystem`) and `origin` (`kb-authored` | `packaged-module` from imported libraries). `legacy-theme` is flagged `deprecated=true` (a migration-to-DesignSystem candidate). The default view lists only `kb-authored`; a named lookup (`-ObjectName`) **never** filters by origin, so it does not produce a false "does not exist" for an imported class.

```text
# authored catalog (kb-authored); use -IncludeImported or -Origin packaged-module for libraries
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query css-classes -Model design-system -Format text

# lookup for one specific class (case-sensitive; also finds imported ones)
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query css-classes -ObjectName AttributeAvisos -Format text
```

Layer 2 — usage. `css-class-usage -ObjectName <class>` lists the resolvable uses (layout in `class`/`cellClass`/`rowClass`/`formClass`; code in `Control.Class = "..." | 'A B' | StyleClass:x | ThemeClass:y`) with a **locator = object + snippet** (in a layout everything is on one line, so `line` is not very useful there). Without `-ObjectName`, it returns an overview with totals and the list of classes **used but not cataloged** (a golden-rule cross-check). The output honestly states its coverage: `dynamic_uses_total` counts dynamic `.Class=` assignments (a `&v` variable / `Format()`) that **cannot** be attributed to a class by name. `found_in_catalog=false` means a class is used but not cataloged (e.g. an imported one that was not scanned), **not** that it does not exist.

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -Query css-class-usage -ObjectName AttributeAvisos -Format text
```

Safeguard: this table is a triage accelerator with gate-checked freshness, not exhaustive truth. For a destructive operation (renaming/removing a class), confirm with a literal XML search before acting.

## Validate basic impact queries

After generating or locating a SQLite index, validate `impact-basic`'s operational behavior with:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Test-KbIntelligenceQueries.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -ValidationCasesPath "<mimir-lite-root>/tests/fixtures/kb-intelligence-sample-kb.validation-queries.json" -ValidationReportPath "<KbWorkspace>/KbIntelligence/kb-intelligence-validation-queries-impact.json" -FailOnValidationFailure
```

These cases check query behavior. They do not regenerate the index and do not replace the extraction batteries.

Pick the runner by the case's shape. Cases with a `query` field belong to query validation; cases with `source`, `target`, and `expected_rule` belong to extraction/generation validation.

### Relation case fields (extraction / generation)

Besides `source`, `target`, `expected_rule`, and `expectation` (free text):

| Field | Role |
| --- | --- |
| `should_exist` | Default `true`. If `false`, the case only passes when the edge does **not** exist. |
| `require_source_exists` | If `true`, fails when `source` is not in the build's inventory. |
| `require_property_in_source` | An expected string, or an object `{ "value": "..." }`. Requires an `idBasedOn` property with that value in the source's XML, **outside** CDATA/comments (same masking as the extractor). Avoids a false pass on `should_exist:false` when the property does not really exist. |
| `require_target_exists` | If `true`, fails when the typed `target` is not in the inventory. |
| `require_target_fully_qualified_name` | Compares the target's `fullyQualifiedName` (requires `require_target_exists`). Case-insensitive comparison. |

Preconditions (`require_*`) run **before** the edge check; if any fails, the case fails without looking at `should_exist`.

## Care with SQLite validations on Windows

After generating a new temporary SQLite file, prefer running validations against it in sequence. Avoid running parallel validations against the same freshly generated database.

If parallelizing is really needed, use independent temporary copies of the SQLite file for each validation.

Transient access/lock failures, or a table not yet visible on Windows, should be retried in sequence first before being treated as a real contract failure or index regression.

## Validate extended type inventory

After regenerating the index, validate the presence of extended types with:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Test-KbIntelligenceQueries.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -ValidationCasesPath "<mimir-lite-root>/tests/fixtures/kb-intelligence-sample-kb.validation-extraction.json" -ValidationReportPath "<KbWorkspace>/KbIntelligence/kb-intelligence-validation-inventory-extended.json" -FailOnValidationFailure
```

These cases check object inventory and `impact-basic`'s conservative behavior for types with no extracted relations.

Recommended minimum extra coverage to avoid a false-positive inventory pass:

- at least one positive `Transaction` case in `object-info`
- one case for a type with its own envelope, such as `Attribute`
- one case for a type recently added to the catalog, when there is one

## Validate semantic relations

After regenerating the index, validate approved semantic resolution with:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Build-KbIntelligenceIndex.ps1" -SourceRoot "<KbWorkspace>/KbObjectsXml" -OutputPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -ValidationReportPath "<KbWorkspace>/KbIntelligence/kb-intelligence-validation.json" -ValidationCasesPath "<mimir-lite-root>/tests/fixtures/kb-intelligence-sample-kb.validation-extraction.json" -FailOnValidationFailure
```

These cases check semantic relations. They should run together with the extraction batteries whenever there is an official round.

To specifically validate WebComponent-creation extraction via `<WebPanel>.Create(...)`, generate a dedicated battery from your own real KB that has such a case (this repository ships no such real-KB example, for privacy; there is no generic substitute, since the case depends on a real observed `<WebPanel>.Create(...)`). The case format is the same as the `sample-kb` battery (`source`, `target`, `expected_rule`) — use it as a structural template.

This class of battery covers `webpanel_dot_create` and should be treated as extraction/generation validation, not query validation.

Local self-test (no real KB workspace needed) for the calls in `Property Formula` on `Attribute`:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceAttributeFormulaExtractionSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for the formula relations from the attribute they compute (extractor 21): the calls and attribute uses of a classic `Formula`, and the attribute uses (`Formula read`) of a modern `Formula` property:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceFormulaSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for the classic structural relations (extractor 22): classic `Table` keys and index members, classic `Transaction` level attributes, and the level-to-`Table` match by key set, including the unmatched and ambiguous levels:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceLegacyClassicStructureSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for the unread classic code counter (extractor 25): classic `Procedure` and `Report` objects with no `<CodeBlock>` counted, an empty `<CodeBlock>` and modern objects not counted, the metadata key, both coverage scopes, and an older index without the key:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceLegacyUnreadCodeCoverageSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for the inferred base table of a classic `for each` (extractor 24): clauses, body and print blocks, nested blocks, `when none`, `new`, grid loops, subtype groups, ambiguous and missing answers:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceLegacyForEachBaseTableSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for the attribute references of Smart Devices `Panel` objects (extractor 23): layouts, orders, search, break by, and filters of the pattern instance, variables skipped, a mobile `WorkWith` with the same name kept apart, and the `Panel` coverage entry:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligencePanelAttributeSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for `Procedure` call forms resolved via the real inventory, without depending on prefixes like `proc*`:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceProcedureCallFormsSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for a method call on an `exo:<ExternalObject>` variable, and protection against a substring false positive in a direct `Procedure` call:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceExternalObjectMethodExtractionSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for the deterministic generated-by-Pattern signal (`IsGeneratedObject`/`PatternObjectId`/`InstanceKey`) in the `objects` table, guarding against markers from an `<Object>` nested inside a `PackagedModule` and against the regex fallback path for malformed XML:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceGeneratedObjectExtractionSelfTest.ps1"
```

Local self-test (no real KB workspace needed) for `idBasedOn`→`Domain` (`based_on_domain`, extractor 12): scope beyond `Attribute`, module qualification via `fullyQualifiedName`, single-pass CDATA/comment masking, and deduplication:

```text
pwsh -NoProfile -File "<mimir-lite-root>/tests/mimir-lite/Test-KbIntelligenceIdBasedOnDomainSelfTest.ps1"
```

Positive `Property Formula` cases observed in real production KBs are cataloged in dedicated per-KB batteries, kept out of this repository for privacy (not distributed here). The synthetic fixture `tests/fixtures/kb-intelligence-sample-kb.validation-extraction.json` covers the same extraction mechanism with invented data. To validate against your own real KB, generate your own battery in the same format and validate it on that KB workspace's own rebuild — not on the generic examples' path.

Since these cases use `source`, `target`, and `expected_rule`, they must run through the generator/indexer. If sent by mistake to `Test-KbIntelligenceQueries.ps1`, treat the result first as an incompatible runner, not as a real rule regression.

## Validate basic functional triage

After locating or regenerating the canonical index, validate `functional-trace-basic` with:

```text
pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Test-KbIntelligenceQueries.ps1" -IndexPath "<KbWorkspace>/KbIntelligence/kb-intelligence.sqlite" -ValidationCasesPath "<mimir-lite-root>/tests/fixtures/kb-intelligence-sample-kb.validation-queries.json" -ValidationReportPath "<KbWorkspace>/KbIntelligence/kb-intelligence-validation-queries-functional-trace.json" -FailOnValidationFailure
```

These cases only check the basic functional trail assembly. They do not prove runtime behavior and do not replace reading the official XML.

Since these cases validate queries and carry a `query` field, they belong to the `Test-KbIntelligenceQueries.ps1` runner, not to the `Build-KbIntelligenceIndex.ps1` regeneration flow.

## Output formats

- `json`: standard format for consumption by agents and automation
- `text`: short format for quick reading in a conversation or terminal

## Rules of use for an agent

- Query by `type + name`, never by name alone.
- Look first for `KbIntelligence\kb-intelligence.sqlite` in the KB workspace.
- Ignore `ArquivoMorto` folders unless the user explicitly asks for historical analysis.
- Treat the SQLite file as derived and regenerable.
- Keep the official XML as the normative source.
- Before analyzing a GeneXus object covered by the index, run `impact-basic` only when the type has `queryableByKbIntelligence=true`; for `false`-flagged types, use `object-info` and an XML read (the semantic query returns exit `11`).
- Treat `impact-basic` as direct technical impact, not complete functional proof.
- When a reverse-relation answer has `coverage.complete=false`, say so to the user and never present it as "no callers" (see "Coverage of reverse-relation answers").
- For short functional questions, `functional-trace-basic` can reduce initial collection, but the final answer must still separate `Direct evidence`, `Additional XML reading`, `Strong inference`, and `Hypothesis`.
- Use the line and the `snippet` only as technical evidence, not as complete functional proof.
- When the question needs GeneXus semantics, open the XML and review the effective `Source`.
