# 01a - Catalog and Empirical Patterns

## Document role
Empirical

## Purpose
Concentrate the corpus overview, the observed type catalog, recurring patterns, and general limits of structural reading.

## Incorporated origin - 01-base-empirica-geral

## Document role
Conceptual

## Predominant confidence level
High

## Depends on
`09-script-inventory.md`

## Used by
`01b-part-type-matrix-by-type.md`, `01c-stable-vs-variable-fields.md`, `01d-structural-diffs-by-type.md`, `02-operational-rules.md`

## Purpose
Consolidate the structural reading of the XML corpus extracted from the KB.
Serve as the conceptual base for the empirical and operational documents.

## Source used

- Direct evidence: the consolidation below uses a raw KB inventory the maintainer exported locally, before this repository existed.
- Direct evidence: XMLs from the corpus `C:\SANITIZED\KbObjectsXml` were read.

## Corpus overview

- Direct evidence: the corpus holds `7219` XMLs distributed across `32` extracted-type directories.
- Direct evidence: the largest sets by directory are `Procedure` (`2281`), `WebPanel` (`1196`), `SubTypeGroup` (`709`), `SDT` (`594`), `Domain` (`592`), `ThemeClass` (`501`), `Module` (`279`), `Image` (`250`), `Index` (`228`), `Transaction` (`183`) and `WorkWithForWeb` (`183`).
- Direct evidence: the raw inventory recorded `0` files with XML-read problems.

## Recurring XML structure

- Direct evidence: extracted objects follow the general `<Object ...>` format with attributes such as `guid`, `name`, `type`, `parent`, `parentGuid`, `moduleGuid`, and `fullyQualifiedName`.
- Direct evidence: most types store internal content in `<Part type="...">...</Part>` blocks inside `<Object>`.
- Direct evidence: one class of types stores properties directly under `<Properties>` inside `<Object>`, with no `<Part>` wrapper at all. Types confirmed with this structure in the SampleKb corpus: `ThemeClass` (501 objects), `Module/Folder` (279 objects, `000...0008`), `ThemeColor` (24 objects), `Generator` (5 objects), `DataStore` (2 objects).
- Direct evidence: on 2026-05-30, a sample across four KB workspaces (`Gx_SampleKb`, `Gx_SampleKb2` in Prod and Test, `Gx_SampleKb3` in Test) confirmed `only_properties_in_sample` for `Generator`, `DataStore`, `ThemeClass`, `ThemeColor` (when present), and `Folder` in every KB that had the type; `PatternSettings` has a `<Part>` with `<Data>` in CDATA, but the index's extractor does not parse that block.
- Editorial rule: `queryableByKbIntelligence=false` in the technical catalog (`scripts/gx-object-type-catalog.json`) marks types for which **the current index engine should not** be used in `who-uses`, `what-uses`, `impact-basic`, or `functional-trace-basic` — the criterion is extractor coverage, not "irrelevant object in the KB". Canonical list: the `queryableByKbIntelligence` field on each JSON entry (updated 2026-05-30 with a multi-KB sample plus a zero-edge graph in SampleKb's `kb-intelligence.sqlite`).
- Direct evidence: a second 2026-05-30 pass — types with `<Part>` in the export but **zero** inbound/outbound edges in the SampleKb index (e.g. `SubTypeGroup` 710 objects, `Image` 251, `Theme`, `File`, `Module`, `PackagedModule`, `Stencil`, `UserControl`, `Panel`, ...) were set to `queryableByKbIntelligence=false`; `Query`, `DataView`, `WorkPanel`, and similar **remain** `true` in the catalog absent an explicit reclassification.
- Editorial rule: types that **remain** `queryableByKbIntelligence=true` despite an asymmetric graph (`API`, `DataSelector`, `WorkWithForWeb`, `ExternalObject`) are documented in `kb-index-reference.md` — semantic queries can still surface **outbound** dependencies or sparse inbound ones; do not confuse this with "no impact".
- Direct evidence: `Attribute` has its own envelope, different from every other type — root `<Attributes><Attribute>` instead of `<Object type="...">`. It has an internal `<Part type="...">`, but does not follow the standard envelope.
- Strong inference: the absence of `<Part>` in an XML does not indicate an empty or corrupted object — it can be the type's normal structure.
- Strong inference: for this corpus, the GUID in `Object/@type` is a stable identifier of the object's extracted type.
- Editorial rule: in the XPZ base, every `objectTypeGuid` registered in `scripts/gx-object-type-catalog.json` is treated as **stable** for its corresponding GeneXus type — no GUID change is assumed across minor GeneXus upgrades or new addon versions (K2BTools, SmartDevicesPlus, etc.) absent documented evidence to the contrary.
- Hypothesis: the same `Object/@type` and `Part/@type` catalog may repeat across other GeneXus 18 exports, but this has not been proven here for every type.

## GeneXus Object Type Reference

Types that generate their own XML file in the corpus. Organizational containers are in the next section.

- Editorial rule: the canonical, executable technical source for this list is `scripts/gx-object-type-catalog.json`.
- Operational rule: a KB workspace may keep `scripts/gx-object-type-catalog.override.json` as a local stopgap for a type still missing from the base catalog. The override is merged **field by field** with the base catalog by the shared core; an omitted field inherits from the base when the entry shares the same name, but a divergent value on a sensitive-identity field (`objectTypeGuid`, `rootKind`, `folderName`) is an unsafe block.
- Operational rule: the local override's classification is triadic per entry: `pending` when the entry still needs to be upstreamed to the base catalog; `redundant` when the base already covers the same information; `divergent` when the override contradicts the base and needs a human decision. `pending` is an effective reminder; `redundant`/metadata-only recommends cleanup with `CLEANUP_RECOMMENDED`; `divergent` on a non-identity operational field (`field-divergence`) keeps the merge with a warning and `REMINDER_REQUIRED`; `divergent` on a sensitive-identity field (`unsafe-identity-divergence` on `objectTypeGuid`, `rootKind`, or `folderName`), an invalid shape, or an unsafe collision blocks resolution of the effective catalog.
- Operational rule: `Register-GeneXusObjectTypeCatalogOverride.ps1` does not write a redundant stopgap or an unsafe collision; before writing, it classifies the candidate against the effective catalog and requires `-UserApproved` only for a genuine stopgap registration. A type the base already knows keeps the base `inventoryEligible`, `queryableByKbIntelligence`, and `containerType` flags, so a registration never re-enables semantic queries on a type marked `false`; a type missing from the base gets `inventoryEligible=true`, `queryableByKbIntelligence=true`, `containerType=false` (edit the override afterwards when the type holds code the index does not read).
- Operational rule: `Test-MimirCatalogOverrideSessionReminder.ps1` is a read-only audit of the local override. `REMINDER_REQUIRED`, `INVALID_OVERRIDE_SHAPE`, and `OVERRIDE_RESOLUTION_BLOCKED` exit `2`; `CLEANUP_RECOMMENDED` exits `0` and should be offered as an approved cleanup, not as a block on the current task.
- Operational rule: the structured override diagnostics use fields such as `status`, `reason`, `diagnosticReason`, `fieldPath`, `overridePath`, and `catalogOverrideDiagnostic`; these fields describe the override's own resolution problem, not another engine's input paths.
- Editorial rule: this catalog covers **only** modern types identified by a GUID in `Object/@type`. **Legacy GeneXus 9** export elements (`ExportFile` with `<GXObject><Element>` by **name**, no type GUID) are **outside** this catalog, in their own registry `scripts/gx-legacy-export-element-registry.json` (owner doc `01k-legacy-element-registry.md`) — never invent a GUID or reuse the modern successor type's GUID to represent a legacy element.
- Editorial rule: this document remains an explanatory and historical reference, not a single point of reading for scripts.
- Editorial rule: in the Description column, `queryableByKbIntelligence=false` means the current index engine must **not** be used for `who-uses`, `what-uses`, `impact-basic`, or `functional-trace-basic` (canonical list in the JSON). Types with no such mark in the table remain `true` in the catalog — including with an asymmetric graph (`API`, `DataSelector`, `WorkWithForWeb`, `ExternalObject`; see `kb-index-reference.md`). The mobile `WorkWith` and `SmartDevicesApplication`, and the legacy `WorkPanel`, are `false`: the index does not extract their calls.

| Type | GUID in `Object/@type` | Description | Suggested dir. |
| --- | --- | --- | --- |
| `API` | `36e32e2d-023e-4188-95df-d13573bac2e0` | REST or SOAP service interface | `API/` |
| `Attribute` | *(own envelope: `<Attributes><Attribute>`; no `Object/@type`)* | KB domain attribute | `Attribute/` |
| `BusinessProcessDiagram` | `b5f00807-9da8-4cf9-b408-7554f2b6a8ee` | GXflow Business Process Diagram (declarative task bindings and condition expressions in its diagram `Part`); `queryableByKbIntelligence=false` | `BusinessProcessDiagram/` |
| `CategoryDiagram` | `280c149c-48b2-4284-a532-0c999df9e006` | Organizational category/diagram exported by the KB | `CategoryDiagram/` |
| `ColorPalette` | `3affc0b3-494b-4d84-9ec1-3a6ab8349cda` | Color palette for themes; `queryableByKbIntelligence=false` | `ColorPalette/` |
| `Dashboard` | `526aba9f-a725-4bc7-b1db-0b9f92ac9550` | Composite visual panel; `queryableByKbIntelligence=false` | `Dashboard/` |
| `DataProvider` | `2a9e9aba-d2de-4801-ae7f-5e3819222daf` | Parameterized data source | `DataProvider/` |
| `DataSelector` | `ffd44be7-3bb4-4d01-9e7e-d1c1a3c095af` | Reusable data selector | `DataSelector/` |
| `DataView` | `19abc6ff-2cd2-0000-0006-6d172bc2333b` | Data View (external table mapping; `DataViewAttribute`, platforms) | `DataView/` |
| `DataStore` | `dcdcdcdc-dfe0-4a57-ae8f-c6e31b0dcbc0` | Data store configuration; `queryableByKbIntelligence=false` | `DataStore/` |
| `DeploymentUnit` | `bf08dfb1-361c-4e7e-ad54-391e56e60b49` | Deployment packaging unit; `queryableByKbIntelligence=false` | `DeploymentUnit/` |
| `DesignSystem` | `78b3fa0e-174c-4b2b-8716-718167a428b5` | Design System; `queryableByKbIntelligence=false` | `DesignSystem/` |
| `Document` | `faeb588c-dcce-4dad-9af3-cdd11b961a32` | Knowledge document (internal wiki); `queryableByKbIntelligence=false` | `Document/` |
| `Domain` | `00972a17-9975-449e-aab1-d26165d51393` | Domain (reusable data type) | `Domain/` |
| `ExternalObject` | `c163e562-42c6-4158-ad83-5b21a14cf30e` | API or native library wrapper | `ExternalObject/` |
| `File` | `1132ac08-290f-4fd1-bd18-64777b7329d1` | Embedded static file; `queryableByKbIntelligence=false` | `File/` |
| `Generator` | `ecececec-dfe0-4a57-ae8f-c6e31b0dcbc0` | Code generator; `queryableByKbIntelligence=false` | `Generator/` |
| `Image` | `9fb193d9-64a4-4d30-b129-ff7c76830f7e` | Image resource; `queryableByKbIntelligence=false` | `Image/` |
| `K2BEntityServices` | `589d4b49-e3f9-4d49-aaf4-fad023028eb1` | K2BTools addon Entity Services pattern instance; `queryableByKbIntelligence=false` | `K2BEntityServices/` |
| `K2BGeneralSettings` | `75a2b955-749a-3f29-99e0-aec666f802a2` | K2BTools addon global configuration; `queryableByKbIntelligence=false` | `K2BGeneralSettings/` |
| `K2BMenu` | `ce7b18b7-b5b0-4b27-8c21-b77743938ddf` | K2BTools application menu; `queryableByKbIntelligence=false` | `K2BMenu/` |
| `K2BPrompt` | `589d4b49-e3f9-4d49-aaf4-fad023028eb6` | K2BTools prompt/selection; `queryableByKbIntelligence=false` | `K2BPrompt/` |
| `K2BTrnForm` | `bcc946b1-3fe3-4980-8948-42574dc14209` | K2BTools pattern Transaction Web Form; `queryableByKbIntelligence=false` | `K2BTrnForm/` |
| `Language` | `88313f43-5eb2-0000-0028-e8d9f5bf9588` | Language configuration; `queryableByKbIntelligence=false` | `Language/` |
| `Menubar` | `28eca899-04c7-4114-9556-5879b0a6414c` | Menu Bar Win (deprecated since GeneXus 15); `queryableByKbIntelligence=false` | `Menubar/` |
| `OfflineDatabase` | `70b6075c-331c-0000-0038-ac3b65316dd0` | Offline Database of an offline Smart Devices application (events such as `Start` in its `Part`s); `queryableByKbIntelligence=false` | `OfflineDatabase/` |
| `Panel` | `d82625fd-5892-40b0-99c9-5c8559c197fc` | Panel for mobile devices (SmartDevices); `queryableByKbIntelligence=false` | `Panel/` |
| `PatternSettings` | `83476c1e-fa72-4229-9930-f51b954fca2d` | Applied pattern configuration; `queryableByKbIntelligence=false` | `PatternSettings/` |
| `Procedure` | `84a12160-f59b-4ad7-a683-ea4481ac23e9` | Procedure (GeneXus code) | `Procedure/` |
| `Query` | `926a06b9-3417-4ab4-9f8c-09c2f626bb1c` | GeneXus Query object (`QueryElement`, filters, parameters, chart/card settings) | `Query/` |
| `SDPanelDesigner` | `a84e76c6-ccf5-4b03-a9d2-7c31c3d717e6` | K2BTools addon SD designer settings (`SDPanelDesignerSettings`); `queryableByKbIntelligence=false` | `SDPanelDesigner/` |
| `SDT` | `447527b5-9210-4523-898b-5dccb17be60a` | Structured Data Type | `SDT/` |
| `SmartDevicesApplication` | `9bdcc055-174e-4af6-96cb-a2ceef6c5f09` | SmartDevicesPlus/WWPM addon Smart Devices Application (dashboard + events in `Source`; **not** the catalog's `Dashboard` type); `queryableByKbIntelligence=false` | `SmartDevicesApplication/` |
| `SmartDevicesPlus` | `c84ec0ea-d159-46e2-a118-2108860379bb` | Smart Devices Plus addon global configuration object (`SDPlus_Settings_*` in `Properties`; typical parent `RootModule`); `queryableByKbIntelligence=false` in the technical catalog — inventory yes, `who-uses`/`impact-basic` no | `SmartDevicesPlus/` |
| `Stencil` | `624a8b31-36f0-4292-adba-2d270d1e3537` | Pattern stencil; `queryableByKbIntelligence=false` | `Stencil/` |
| `SubTypeGroup` | `87313f43-5eb2-41d7-9b8c-e8d9f5bf9588` | Domain subtype group; `queryableByKbIntelligence=false` | `SubTypeGroup/` |
| `Table` | `857ca50e-7905-0000-0007-c5d9ff2975ec` | Database index or table | `Table/` |
| `Theme` | `c804fdbd-7c0b-440d-8527-4316c92649a6` | Full visual theme; `queryableByKbIntelligence=false` | `Theme/` |
| `ThemeClass` | `d4876646-98dd-419b-8c1c-896f83c48368` | Class inside a theme; `queryableByKbIntelligence=false` | `ThemeClass/` |
| `ThemeColor` | `5592de59-d30a-499d-9100-a7006d3674f2` | Named color inside a theme; `queryableByKbIntelligence=false` | `ThemeColor/` |
| `ThemeTransformation` | `2258230e-d565-4b79-8103-caff9f453a1f` | Theme Transformation (`Properties` only); `queryableByKbIntelligence=false` | `ThemeTransformation/` |
| `Transaction` | `1db606f2-af09-4cf9-a3b5-b481519d28f6` | Transaction (form + data model) | `Transaction/` |
| `UserControl` | `562f4793-aabe-449f-8821-fc77e550698e` | Custom User Control; `queryableByKbIntelligence=false` | `UserControl/` |
| `WebPanel` | `c9584656-94b6-4ccd-890f-332d11fc2c25` | Web screen (events and layout) | `WebPanel/` |
| `WebPanelDesigner` | `562b39a3-dde2-4349-9252-e9e69090c53e` | K2BTools addon Web designer settings (`WebPanelDesignerSettings`); distinct from the internal SQL `FormDesignerPart`; `queryableByKbIntelligence=false` | `WebPanelDesigner/` |
| `WorkPanel` | `198e8ea4-1d49-4c9c-8a9a-417024baa9d1` | Legacy GeneXus Work Panel (deprecated since GeneXus 15); `Form Type=Windows`; `queryableByKbIntelligence=false` | `WorkPanel/` |
| `WorkWith` | `15cf49b5-fc38-4899-91b5-395d02d79889` | WW for SD/mobile; current name "Work With"; historical name "Work With for Smart Devices". Identity is the GUID, not the pattern's historical name; `queryableByKbIntelligence=false` | `WorkWith/` |
| `WorkWithForWeb` | `78cecefe-be7d-4980-86ce-8d6e91fba04b` | Work With For Web (pattern-generated) | `WorkWithForWeb/` |
| `WorkWithPlusInstance` | `07135890-56fc-489b-b408-063722fa9f7d` | Instance of the (third-party) WorkWithPlus Pattern applied to a GeneXus object, typically `WebPanel`; the XML carries `Pattern="07135890-..."` | `WorkWithPlusInstance/` |
| `WorkWithPlusTemplate` | `083f1b21-5715-45e1-8a8d-ceadef141e02` | WorkWithPlus template (`WWPTemplate_Type`, `WWPTemplate_TemplateXml`) | `WorkWithPlusTemplate/` |
| `WorkflowDocument` | `12b41a58-3890-4adf-9134-820aaa4c6404` | GXflow workflow document (`Properties` only, e.g. `PWFDocType`); not the knowledge-base `Document` type; `queryableByKbIntelligence=false` | `WorkflowDocument/` |
| `WorkflowRole` | `3e62f22c-a0db-476e-915b-9f06dde83f4d` | GXflow role (`Properties` only); named `WorkflowRole` so it is not confused with GAM roles; `queryableByKbIntelligence=false` | `WorkflowRole/` |

- Direct evidence (KB `SampleKb4`, XPZ `SampleKb416052026FULL.xpz`, 2026-05-16): the `Query`, `WorkPanel`, `WorkWithPlusInstance`, and `WorkWithPlusTemplate` rows above were registered from a `Sync-GeneXusXpzToXml.ps1` block on unknown GUIDs. Counts observed in that XPZ: `WorkWithPlusInstance` = 420 (e.g. `WorkWithPlusHome`, `WorkWithPlusGAMApplicationEntry`); `WorkWithPlusTemplate` = 67 (e.g. `ListNoBaseTable`, `Dashboard1`, `CardWithMainImage`); `Query` = 31 (e.g. `QExemploPeriodoA`, `QExemploPeriodoB`); `WorkPanel` = 1 (`WPExemploImpressao`). The overview counts at the start of this document refer to the SampleKb corpus and were not redone.
- Direct evidence (KB `SampleKb5`, GeneXus `18.0.13.186738` U13, XPZ/XML 2026-05): `DataView` = 8 (e.g. `Tgol421`, `CEP001`); `SmartDevicesApplication` = 2 (`Evo`, `MDFSampleApp`); `SmartDevicesPlus` = 1 (`SmartDevicesPlus`, `SDPlus_Settings_*` properties). XML with `DataViewAttribute` / `DataViewStructurePlatform`, `Dashboard` embedded in a `Part`, and `parentGuid`/`moduleGuid` pointing at `RootModule` (`afa47377-41d5-4ae8-9755-6f53150aa361`). C4 research: GeneXus wiki (Data View), WorkWithPlus docs (SDP addon), a 2015 forum post with the same `SmartDevicesApplication` GUID in an import error.
- Direct evidence (KB `SampleKb6`, GeneXus 18 Upgrade 15, XPZ/XML 2026-07 via a local `upstreamPending` override promoted 2026-08-12): seven K2BTools addon types registered from a sync block on an unknown GUID — `K2BEntityServices` = 172; `K2BTrnForm` = 149; `K2BMenu` = 38; `K2BPrompt` = 23; `K2BGeneralSettings` = 1; `WebPanelDesigner` = 1 (`WebPanelDesignerSettings`); `SDPanelDesigner` = 1 (`SDPanelDesignerSettings`). The `WebPanelDesigner` (`562b39a3-...`) and `SDPanelDesigner` (`a84e76c6-...`) GUIDs cross-reference a SQL investigation recorded in the maintainers' pending-ideas archive (not published; `EntityTypeNamespace` `K2BTools`). In the technical catalog all of them stay `queryableByKbIntelligence=false` until the extractor guarantees edges. **Post-pull:** `CLEANUP_RECOMMENDED` only with full operational equivalence to the base. The stopgap registrar writes `queryableByKbIntelligence=$true` by default; with the base at `false`, the typical outcome is `REMINDER_REQUIRED` / `field-divergence` until aligned or removed — do not assume automatic cleanup just because the GUID is already in the shared base.
- Direct evidence (same KB `SampleKb6`, 2026-08-12): the GUID `28eca899-04c7-4114-9556-5879b0a6414c`, initially labeled in the local override as `MicroInfo` from its description, is actually the **`Menubar`** type (IDE: objects `BbInfo` / `Bbinfo2`, Type=`Menubar`, descriptions `MICRO Info` / `MICRO Info Java`). Wiki [Menu Bar](https://docs.genexus.com/en/wiki?7610%2CMenu+Bar=) (deprecated since GeneXus 15; Win generators). Promoted to the modern catalog; the legacy GX9 registry reclassifies the `<Menubar>` element from `orphan` to `equivalent`→`Menubar` (the same pattern as `WorkPanel`). **Post-pull:** while that GUID's override entry diverges from the base on an identity field — typically `folderName=MicroInfo` against `folderName=Menubar` — resolution of the effective catalog **blocks** (`OVERRIDE_RESOLUTION_BLOCKED`, `unsafe-identity-divergence` / `identity-field-divergence`, `fieldPath=types.MicroInfo.folderName`) until the entry is removed or aligned to `Menubar`'s identity fields. Aligned identity guarantees **no block**, not `CLEANUP_RECOMMENDED`: the engine compares every operational field; consultative cleanup only when they are also equivalent — a divergent `queryableByKbIntelligence`, for example, becomes `REMINDER_REQUIRED` / `field-divergence`. The same full-equivalence criterion applies to the seven K2B override entries.
- Direct evidence (public GeneXus samples, 2026-10-08): five types registered from a `Sync-GeneXusXpzToXml.ps1` block on unknown GUIDs. Each GUID is named in the XPZ `ExportFile/Dependencies/Reference` block, which lists every object type the export uses with its type name and package: `OfflineDatabase` = "Offline Database" (`GenexusBL`), 1 object in GeneXus X Evolution 3 `MyFirstOfflineApplication` (`MenuOfflineDatabase`), wiki [Offline Database](https://docs.genexus.com/en/wiki?22509); `ThemeTransformation` = "Theme Transformation" (`GenexusBL`), 2 objects (`MapCollapse`, `MapShow`) in GeneXus 16 `EventDay_BeforeGAM17`, exported again in its `2-ThemeGX28` delta, wiki [Theme Transformation](https://docs.genexus.com/en/wiki?23694); `BusinessProcessDiagram` = "Business Process Diagram" (`GxpmBL`), 11 objects in GeneXus 17 `GXBPMSuiteGX17_KBSolucion` (e.g. `Purchases`), wiki [Business Process Diagram](https://docs.genexus.com/en/wiki?7273); `WorkflowRole` = "Role" (`GxpmBL`), 2 objects in the same sample (e.g. `Administrativo`), wiki [Role](https://docs.genexus.com/en/wiki?10194); `WorkflowDocument` = "WorkflowDocument" (`GxpmBL`), 1 object in the same sample (`ReparationImage`), GeneXus training material "Working with documents". All five are `queryableByKbIntelligence=false`. `OfflineDatabase` (events) and `BusinessProcessDiagram` (task bindings such as `PWFTask*` and condition expressions) can reference other objects, but the index does not extract those references, so both are counted in the coverage of reverse-relation answers (`kb-index-reference.md`); `ThemeTransformation`, `WorkflowRole`, and `WorkflowDocument` carry only `Properties`.

## KB organizational containers

These are not programmable object types. They are the KB's own organizational infrastructure. The local corpus directory name **is not a reliable type indicator across KBs** — always use the GUID in `Object/@type`.

| Container | GUID in `Object/@type` | Description | Suggested dir. |
| --- | --- | --- | --- |
| System folder | `00000000-0000-0000-0000-000000000006` | Internal GeneXus folders (Main Programs, ToBeDefined); **never** a valid `parentType` for exportable objects; `queryableByKbIntelligence=false` | `Module/` |
| User folder/module | `00000000-0000-0000-0000-000000000008` | User-created container; the IDE shows it as "Module/Folder" in the Properties panel; `queryableByKbIntelligence=false` | `Folder/` |
| Installed module | `c88fffcd-b6f8-0000-8fec-00b5497e2117` | Installed GeneXus modules (GAM, package modules); cube icon in the IDE; `queryableByKbIntelligence=false` | `PackagedModule/` |
| RootModule | `afa47377-41d5-4ae8-9755-6f53150aa361` | Virtual root of the KB; **generates no XML file** in the corpus; appears only as `parentGuid`/`moduleGuid`; `queryableByKbIntelligence=false` | *(no folder)* |

## Internal patterns observed by group

### `Procedure`

- Direct evidence: `C:\SANITIZED\KbObjectsXml\Procedure\PRCExemplo0001.xml` shows `Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff"`, `9b0a32a3-de6d-4be1-a4dd-1b85d3741534`, `e4c4ade7-53f0-4a56-bdfd-843735b66f47`, `ad3ca970-19d0-44e1-a7b7-db05556e820c`, and `babf62c5-0111-49e9-a1c3-cc004d90900a`.
- Direct evidence: that same XML has a `parm(...)` fragment inside a `Part` block, showing parameters can be stored separately from the main code.
- Strong inference: `Procedure` objects use a recurring set of `Part type`s for code, parameters, variables, and properties, but this documentation does not semantically name each `Part type` beyond what was observed.

### `WebPanel`

- Direct evidence: `C:\SANITIZED\KbObjectsXml\WebPanel\WPExemplo0001.xml` has a `Source` with `GxMultiForm`.
- Direct evidence: the same file has another `Source` with `Event` blocks.
- Strong inference: in `WebPanel`, declarative layout and event code tend to appear in distinct parts of the XML.

### Real property persistence in `WebPanel`

- Direct evidence: in a later operational re-read of `1197` `WebPanel` objects, the type's `7` recurring `Part type`s remained present in `100%` of cases.
- Direct evidence: `Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778"` concentrated the declarative layout and nearly all of the observed structural control properties.
- Direct evidence: `PATTERN_ELEMENT_CUSTOM_PROPERTIES` appeared in `411/1197` `WebPanel`s, always in the layout `Part`'s `Source`.
- Direct evidence: `WebUserControlProperties` appeared in `172/1197` `WebPanel`s, always in the layout `Part`'s `Source`.
- Direct evidence: `ControlWhere` appeared in `101/1197` cases; `100` came from the layout `Part`, serialized inside control properties, and `1` case appeared in the variables `Part`.
- Direct evidence: `ControlBaseTable` appeared in `23/1197`, `ControlOrder` in `86/1197`, and `ControlUnique` in `13/1197`; in those cases, the observed persistence was concentrated in the layout `Part`'s `Source`, inside serialized control metadata.
- Direct evidence: `Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9"` appeared in `1197/1197` `WebPanel`s, but only `141` cases had a non-empty `Source` for that `Part`.
- Direct evidence: `Conditions` as a materialized filter appeared in those `141` cases via that `Part`'s `Source`, not as a layout attribute.
- Direct evidence: a plain text search for `Conditions` over-counted template cases, because `183` objects used `ViewConditions.dkt` and `179` used `TabGridConditions.dkt` only in `Defaults` metadata.
- Direct evidence: for `Prompt`/`Selection List`, filter materialization in the `Conditions` `Part` was strong: `92/100` `prompt*` objects had a non-empty `Source` in that `Part`, and the `30` `Selection List` cases belonged to that family.
- Direct evidence: for `FreeStyleGrid`, there were `10` cases; all had `ControlWhere` in the layout, `8/10` had `ControlOrder`, and `9/10` had `WebUserControlProperties`.
- Direct evidence: for traditional grids with a `<grid` tag, there were `26` cases; `16` with `ControlWhere`, `9` with `ControlBaseTable`, `14` with `ControlOrder`, and `5` with `ControlUnique`.
- Direct evidence: for `Dynamic Combo Box` controls, there were `58` cases; `56` coexisted with `ControlWhere` in the layout and `50` with `WebUserControlProperties`.
- Sanitized example: `WPExemploSelectionPromptA` shows a `Selection List` with the filter materialized in the `Conditions` `Part`, while `ControlOrder` and `WebUserControlProperties` stay in the layout.
- Sanitized example: `WPExemploGridEstruturalA` shows a traditional grid with `ControlBaseTable`, `ControlOrder`, `ControlWhere`, and `ControlUnique` serialized in the layout.
- Sanitized example: `WPExemploComboDinamicoA` shows a `Dynamic Combo Box` with `ControlWhere` persisted in the layout and extra configuration in `WebUserControlProperties`.
- Sanitized example: `WPExemploGridLivreA` shows a `FreeStyleGrid` with its filter persisted in the layout via `ControlWhere`, plus extra control metadata in the same `Part`.
- Sanitized example: `WPExemploConditionsTemplateA` shows a case where the term `Conditions` appears only from template `Defaults`, with no filter materialized in the conditions `Part`'s `Source`.
- Strong inference: for `WebPanel`, "the property exists in the XML" and "the property persists in the same place across every family" are different claims; the persistence point varies by family and by control type.
- Strong inference: for the `xpz-*` trail, empirical reading distinguishes at least a `Conditions` value present in its own `Part`, serialized layout metadata, and template defaults. These observations document persistence and direct evidence only; they do not authorize cloning, object creation, import, or packaging.

### `Transaction`

- Direct evidence: `C:\SANITIZED\KbObjectsXml\Transaction\TRNExemplo0001.xml` and `TRNExemplo0002.xml` show `<Level ...>` nodes and several `<AttributeProperties Attribute="...">`.
- Strong inference: `Transaction` objects carry hierarchical structure and attribute configuration inside their own `Part type`s.

### `SDT`

- Direct evidence: `C:\SANITIZED\KbObjectsXml\SDT\SDTExemplo0001.xml` shows `<Level>`, `<LevelInfo>`, and `<Item>`.
- Strong inference: in this corpus, `SDT` represents declared hierarchical structure, distinct from the `Transaction` pattern.

### `SubTypeGroup`

- Direct evidence: `C:\SANITIZED\KbObjectsXml\SubTypeGroup\STGExemplo0001.xml` shows several `<Subtype guid="...">` nodes.
- Strong inference: `SubTypeGroup` records subtype/supertype links by GUID and name, not procedural rules.

### `ThemeClass`

- Direct evidence: files such as `ActionAttribute.xml` and `ActionButtons.xml` contain `ThemeElementThemeTypes` and `ThemeElementInternalType` properties.
- Strong inference: these properties are stable markers for recognizing objects in this corpus's `ThemeClass` directory.

### `WorkWith`

- Direct evidence (test KB `GxTest3`, GeneXus 18, 2026-07-26): the GUID `15cf49b5-fc38-4899-91b5-395d02d79889` materializes five objects in `WorkWith/`.
- Direct evidence: the XMLs contain a `List`/`Detail` structure, `GeneXus.SD` actions, and a link to the parent `Transaction`, confirming WW for SD/mobile.
- Direct evidence: the same KB also has five `WorkWithForWeb` objects with the distinct GUID `78cecefe-be7d-4980-86ce-8d6e91fba04b`; the two families coexist.
- Editorial rule: "Work With" is the current name for "Work With for Smart Devices". Historical pattern names can be ambiguous; classification must always use the GUID.

### `WorkWithForWeb`

- Direct evidence: files such as `WorkWithWebTRNExemplo0001.xml` show `Object/@name` starting with `WorkWithWeb`.
- Direct evidence: those same files show `<Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b">`.
- Strong inference: `WorkWithForWeb` XMLs hold web-pattern-generated artifact configuration associated with the parent object.
- Editorial rule: this is the WW for Web, identified by GUID `78cecefe-be7d-4980-86ce-8d6e91fba04b`. A historical name may appear as `WorkWith`, but that does not redefine the type; the GUID prevails.

## Apparent relations observed

- Direct evidence: many objects carry `parent`, `parentGuid`, and `parentType` directly on the `<Object>` node.
- Direct evidence: `WorkWithForWeb` objects use `parentType="1db606f2-af09-4cf9-a3b5-b481519d28f6"` when linked to a `Transaction`, as in `WorkWithWebTRNExemplo0001.xml`.
- Direct evidence: `WebPanel\WPExemplo0001.xml` references other objects in its event code, such as `WPExemploA`, `WWExemploA`, `WWExemploB`, and `WPExemploB`.
- Strong inference: dependencies between objects can be detected by combining `parent*` fields, property references, and named calls in code blocks.
- Hypothesis: a future step could turn these apparent relations into a more reliable dependency graph, given additional validation per object type.

## Cautious reading of `Part type` GUIDs

- Direct evidence: the raw inventory cataloged `Part type` GUIDs by occurrence.
- Strong inference: some `Part type`s recur within the same object family and can be used as a structural signature.
- Hypothesis: the exact functional meaning of each `Part type` still needs finer, object-by-object labeling.

## Limits of this consolidation

- Direct evidence: the corpus was analyzed already decomposed into per-object XMLs, not as the complete original/binary `XPZ`.
- Strong inference: the current documentation describes the organization of this KB's extracted XMLs well.
- Hypothesis: it is not yet safe to generalize every pattern above to any GeneXus 18 KB without new sampling.

## Historical import-test evidence and real-corpus lookup

The following import-test outcomes are retained as historical evidence of observed behavior in the named test trail. They are not instructions to create, clone, import, or package objects. Read references to a successful or failed import only as evidence about shape, direct references, and semantic dependencies; Mimir Lite remains read-only toward the KB except for the permitted corpus sync workflow. Counts, qualifiers, and the recorded outcomes below describe that historical test and are not operational procedures.

## Complementary evidence - real-corpus lookup after the import test battery

## Complement role
Complementary empirical

## Purpose
Record what direct reading of the real corpus at `C:\SANITIZED\KbObjectsXml` added to the results of the controlled import test battery.
Separate more precisely what is a shape gap, what is a KB semantic dependency, and what is only a naming difference the IDE already recognizes.

- Direct evidence: the real-corpus lookup targeted the types that had been problematic or ambiguous in the test battery: `Folder`, `PatternSettings`, `Theme`, `API`, `Transaction`, and later `Attribute` too.
- Direct evidence: on a first pass over `C:\SANITIZED\KbObjectsXml`, `Attribute` did not appear as its own directory, and the observed attributes showed up mainly embedded inside `Transaction`.
- Direct evidence: an XML extracted from a full KB export in a sanitized private path was then checked, where top-level `Attribute` objects appeared with root `<Attribute ... name="...">`.
- Direct evidence: those top-level `Attribute`s were extracted to `C:\SANITIZED\KbObjectsXml\Attribute`, and the folder was cleaned to keep only real attributes, removing inline references.
- Strong inference: `Attribute` is no longer without top-level evidence; the current risk shifts to distinguishing a real attribute definition from a contextual occurrence inside another object.

### `Folder`

- Direct evidence: real examples in `KbObjectsXml\Folder\` (e.g. `ACESSO.xml`, `APIs.xml`) use `Object/@type="00000000-0000-0000-0000-000000000008"`.
- Direct evidence: `Folder`'s XML shape is minimal — no `<Part>` element, only `<Properties>` with `Name` and `IsDefault`.
- Direct evidence: the `moduleGuid` field points at the Root Module (`afa47377-41d5-4ae8-9755-6f53150aa361`) or at another `...0008` container; `parentType` is `00000000-0000-0000-0000-000000000008` when the parent folder is also a user folder.
- Strong inference: `Folder` (`...0008`) is the container the user creates in the IDE ("New Folder" / "New Module"); the IDE shows its name under the "Module/Folder" property in the Properties panel, but the type's canonical GUID is `...0008` and the corpus directory is `Folder/`.

### `Module`

- Direct evidence: real examples in `KbObjectsXml\Module\` (e.g. `Main Programs.xml`, `ToBeDefined.xml`, `GAM.xml`) use `Object/@type="00000000-0000-0000-0000-000000000006"`.
- Direct evidence: `Module`'s XML shape includes `<Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">` with an empty `<Properties />`, plus extra properties under `<Properties>`: `Name`, `ShowInModelTree`, `Query`, `Properties` (e.g. `main_program=true`), `IsDefault`.
- Direct evidence: the `moduleGuid` field is `00000000-0000-0000-0000-000000000000` (no parent module — KB root level); `Main Programs` and `ToBeDefined` have both `parentGuid` and `moduleGuid` zeroed.
- Strong inference: `Module` (`...0006`) groups both internal GeneXus system containers (`Main Programs`, `ToBeDefined`) and installed package modules (`GAM`, `GAM_Frontend-web`) — all living in the corpus's `Module/` directory.
- Strong inference: `...0006` objects never appear as the `parentType` of a user-exportable object; they are the GeneXus engine's organizational containers, not application logic.

### `PatternSettings`

- Direct evidence: the real examples `WorkWith.xml` and `WorkWithDevices.xml` keep their configuration inside `<Data Pattern="..."> <![CDATA[ ... ]]> </Data>`.
- Direct evidence: the internal XML references `Pattern`, `ContextVariable`, `LoadProcedure`, `Security`, and other artifact IDs associated with the registered pattern.
- Strong inference: `PatternSettings` is not self-contained in the observed XML; its references point to the corresponding registered pattern and related artifacts.
- Direct evidence (historical test outcome): in a later isolated test with the real `WorkWith` object, `Pattern Settings 'WorkWith'` imported successfully in the test environment.
- Strong inference: `PatternSettings` is no longer an open structural gap on this trail; the observed dependency is a pattern recognized by that test environment.

### `Theme`

- Direct evidence: the real example `ThemeExemploMobileA.xml` contains `PredefinedTypes` and concrete visual classes such as `TableDetail`, `TableSection`, and `TextBlockGroupCaption`.
- Direct evidence: these classes are referenced by other classes within the same theme, e.g. `Group` references `TextBlockGroupCaption` and `TableSection` references `HorizontalLine`.
- Strong inference: the observed theme references form a graph of internally referenced classes; this is direct dependency evidence, not an instruction to materialize those objects.
- Direct evidence (historical test outcome): in a later revised consolidation, the real `ThemeExemploMobileA` itself failed in the test environment with `Theme class 'TableDetail' does not exist`, `Theme class 'TableSection' does not exist`, and `Theme class 'TextBlockGroupCaption' does not exist`.
- Direct evidence: the real folder `C:\SANITIZED\KbObjectsXml\ThemeClass` contains separate top-level `ThemeClass` objects for `TableDetail`, `TableSection`, and `TextBlockGroupCaption`.
- Direct evidence (historical test outcome): in a later isolated test, those three real `ThemeClass` objects imported successfully, and right after, `Theme 'ThemeExemploMobileA'` also imported successfully.
- Strong inference: on this trail, `Theme` is not explained by serialization alone; the observed dependency evidence is the auxiliary `ThemeClass` objects referenced by the theme.

### `API`

- Direct evidence: on this trail, the observed KB has only `1` real `API` object.
- Direct evidence: that single real case corresponds to a manual/local KB construction, not a broad family observed with multiple comparable examples.
- Direct evidence: on this documentary trail, there is no evidence of a complementary automation tool acting on this case.
- Direct evidence: the real example `APIExemploIntegracaoA.xml` uses several valid `ATTCUSTOMTYPE`s, including `exo:GAMSession, GeneXusSecurity`, `exo:GAMError, GeneXusSecurity`, `exo:GAMUser, GeneXusSecurity`, `sdt:Messages, GeneXus.Common`, `sdt:SDTExemploProdutoBasicoA`, and `sdt:SDTExemploTribSelecaoA`.
- Direct evidence: the same example also depends on real `Procedure`s and events in its source code.
- Strong inference: since there is only one real case in the KB, `API` should be read here as an operational case study of the analyzed KB, not yet as a generalizable GeneXus family in this base.
- Strong inference: in `API`, the XML envelope is relatively well defined; the observed references are to custom types and procedures present in the analyzed KB.
- Strong inference: the observed `ATTCUSTOMTYPE` values refer to types evidenced in the analyzed corpus; this is evidence about references, not an instruction to copy values or create/import/package those types.
- Direct evidence (historical test outcome): in a later isolated test, the real SDTs `SDTExemploProdutoBasicoA`, `SDTExemploProdutoBasicoB`, `SDTExemploProdutoBasicoC`, `SDTExemploProdutoBasicoD`, `SDTExemploTribA`, and `SDTExemploTribSelecaoA` imported successfully before the `API` attempt.
- Direct evidence: in that same test, `API 'APIExemploIntegracaoA'` stopped failing on `ATTCUSTOMTYPE` and started failing on `Object Reference PRCExemploListaA not found`, `Invalid attribute 'DomainExemploTipoA'`, and `'TRNExemploProdutoA' invalid property`.
- Strong inference: in this historical test trail, the remaining observed `API` dependencies after the `SDT` checks were `Procedure` and business context.
- Direct evidence: in a later round, `Domain 'DomainExemploTipoA'` imported successfully and `Procedure 'PRCExemploListaA'` was located in the real corpus.
- Direct evidence: when trying to include that `Procedure`, it failed because it depends on a large chain of transactions and attributes from the main entity and related satellites, plus auxiliary domains such as `DomainExemploSimNao`, `DomainExemploGrupoA`, and `DomainExemploLocalA`.
- Direct evidence: in the same attempt, the `API` advanced one more step and failed on another missing `Procedure`: `PRCExemploTribSelecaoA`.
- Direct evidence: that second `Procedure` also exists in the real corpus and, once inspected, showed an additional dependency on a `Data Provider` (`DPExemploTribSelecaoA`), `Domain 'DomainExemploEnvioA'`, and additional tax-related attributes from the functional chain.
- Strong inference: in this observed API case, the dependency evidence from this KB and IDE export expands beyond a few auxiliary references to a relevant functional subtree of the KB; this does not establish a general profile for APIs.

### `Transaction`

- Direct evidence: real examples such as `TRNExemploComplexaA.xml` carry `<Level ...>` with many `<Attribute ... guid="...">AttributeName</Attribute>` and several `<AttributeProperties Attribute="...">` blocks.
- Direct evidence: the same type has variables named `Context`, `TrnContext`, and `TrnContextAtt`, with `ATTCUSTOMTYPE`s such as `sdt:Context`, `sdt:TransactionContext`, and `sdt:TransactionContext.Attribute`.
- Strong inference: in `Transaction`, the structural shape can be inferred by family, but the final object still depends on the actual existence of its context attributes and SDTs in the KB.
- Strong inference: the failure observed in the test battery was consistent with the real corpus; it was not just a missing envelope — real attributes and valid context types were missing.
- Direct evidence (historical test outcome): in a later isolated test, the real `Attribute`s of `TRNExemploMinBancoA`, the `SDT 'Context'`, and the `SDT 'TransactionContext'` imported successfully before the `Transaction` attempt.
- Direct evidence (historical test outcome): in that same test, `Transaction 'TRNExemploMinBancoA'` imported successfully and triggered pattern generation for `WWExemploMinBancoA`.
- Direct evidence (historical test outcome): in another controlled practical test, a minimal `Transaction` imported successfully when the corresponding top-level `Attribute`s were included in the same package.
- Direct evidence: in that case, the `<Attribute>` nodes inside `<Level>` were not enough by themselves to define the attributes; they only worked as the `Level`'s contextual reference.
- Direct evidence (historical test outcome): in a later real import-test battery, a minimal `Transaction` with `DescriptionAttribute` and `AttributeProperties` succeeded when the corresponding top-level `Attribute`s were present and the main `Part` had the family's expected shape.
- Direct evidence: in that same battery, `AttributeProperties` worked both alone and combined with `DescriptionAttribute`.
- Direct evidence: `DescriptionAttribute` was accepted in the expanded minimal case when it pointed at an attribute existing in the same `Level`.
- Strong inference: the distinction between top-level `Attribute` and inline `Attribute` in a `Level` is essential to interpreting the validated historical test cases.
- Strong inference: the successful historical cases showed references to top-level attributes and context SDTs; this is read-side dependency evidence, not an instruction to assemble a package.

### `Attribute`

- Direct evidence: the XML extracted from the full KB export, kept in a sanitized private path, contains top-level `Attribute` objects with root `<Attribute ...>`, not `<Object ...>`.
- Direct evidence: a real, complete attribute such as `AtributoExemploComplexoA` carries XML attributes such as `guid`, `name`, `fullyQualifiedName`, `description`, `moduleGuid`, `parentGuid`, plus `Part` and `Properties`.
- Direct evidence: the same export also shows short `<Attribute key="True|False" guid="...">AttributeName</Attribute>` nodes inside a `Transaction`'s `<Level>`.
- Direct evidence: those short nodes share the same `guid` as their corresponding real top-level attribute; they work as the attribute's contextual reference at the `Transaction` level, not as a top-level definition.
- Direct evidence: cleaning the `C:\SANITIZED\KbObjectsXml\Attribute` folder kept `7646` real top-level attributes and removed `8539` inline `Attribute_*.xml` references.
- Direct evidence: widening the search to a sanitized private directory of the GeneXus model, suggestive names such as `GAMExampleUserCustomAttributes.xml` turned out not to be an `Attribute` object; that file turned out to be a `Web Panel`.
- Direct evidence: files such as `<KbName>selectAttributes.Filters` turned out to be just auxiliary filter/interface configuration, not an `Attribute` object export.
- Strong inference: top-level `Attribute` is now empirically proven on this trail, but needs extra care because the same XML element name also appears as an inline reference inside `Transaction`.
- Strong inference: when reading an `Attribute` corpus, the evidenced distinction is not "every node called Attribute" but the complete root node with `name` and a `Part`/`Properties` structure.
- Direct evidence: in a later combined test, `Attribute 'AtributoExemploTesteA'` no longer failed on shape; it failed on a semantic property, with `ControlItemDescription='AtributoExemploDescricaoRelacionada'` pointing at an unknown attribute on the target.
- Strong inference: `Attribute` moved out of the "insufficient shape" zone and into the same methodological class of KB context dependency in properties like `ControlItemDescription`, `idBasedOn`, and other named references to real attributes.
- Direct evidence (historical test outcome): in a later revised consolidation, `Attribute 'AtributoExemploFechadoA'`, read from the real corpus with no `ControlItemDescription`, imported successfully.
- Strong inference: on this trail, the historical successful `Attribute` case was a real top-level attribute without the observed unresolved semantic reference; this describes the evidence boundary, not a target-environment readiness rule.

### `Table`

- Direct evidence: direct reading of `228` `Table` objects in `C:\SANITIZED\KbObjectsXml\Table` confirms exactly `2` `Part type`s in `100%` of cases — no variation across the examples.
- Direct evidence: `Part type="00000000-0000-0000-0002-000000000004"` contains `<Key>` with a list of `<Item guid="...">AttributeName</Item>`, representing the table's primary key.
- Direct evidence: `Part type="a5c0e770-560d-0001-0001-7fe71c260de3"` contains `<Indexes>` with one or more `<TableIndex><Index ... type="9e750647-3679-0000-0100-2529de263960">`, representing the table's indexes.
- Direct evidence: no third `Part type` was found at the `Object` level across the 228 examples.
- Direct evidence: `Table`'s `<Object>` node does NOT have a named `parent` attribute; it has only `parentGuid` and `moduleGuid`. This differs from `Transaction`, `Procedure`, and other types that carry a named `parent` — `Table` is the only family of relevant size observed without a named `parent`.
- Direct evidence: primary-key cardinality across the 228 objects: 1 field (34 tables, 15%), 2 fields (106, 46%), 3 fields (59, 26%), 4 fields (15, 7%), 5 fields (9, 4%), 6 fields (5, 2%). Composite keys make up 85% of the corpus.
- Direct evidence: index count per `Table`: minimum 2, maximum 59, average 6.5 — observed across the 228 examples.
- Direct evidence: all `1480` embedded `Index` objects use `type="9e750647-3679-0000-0100-2529de263960"` and contain exactly `1` internal `Part type`: `62cfa789-c127-0001-0100-77676175e433` (a `<Members>` list).
- Direct evidence: of the 1480 indexes, `1036` have `Source="Automatic"` (GeneXus-generated) and `444` have `Source="User"` (manually defined). Every `Table` has at least `1` `Type="Unique" Source="Automatic"` index corresponding to the primary key.
- Strong inference: `Table` carries no explicit reference to its corresponding `Transaction` in the XML; the association is by naming convention — the same object name.
- Strong inference: `Table`'s residual risk is in correctly re-associating it with the `Transaction` on the target, not in the envelope or Part types — both are structurally simple, fixed, and show no variation across families.

## Later complement - the IDE exporting `Table`, `Index`, and `WorkWithForWeb`

- Direct evidence: the isolated export `XPZExemploTabelaA.xpz` contains `228` top-level objects of type `857ca50e-7905-0000-0007-c5d9ff2975ec`.
- Direct evidence: these top-level `Table` objects use the same names as their corresponding `Transaction`s, not a separate convention exclusive to the physical layer.
- Direct evidence: inside each exported `Table` there are `<Indexes>` blocks with `<Index ... type="9e750647-3679-0000-0100-2529de263960">` children.
- Direct evidence: the isolated export `XPZExemploIndiceVazioA.xpz` came back empty, with no `Objects` or `Attributes`.
- Strong inference: on this IDE trail, `Table` exists as its own top-level family, while `Index` appears subordinate to `Table`, not as an isolated top-level set.
- Direct evidence: the export `XPZExemploTabelaIndiceA.xpz` repeated exactly the same `Table` behavior: `228` top-level objects of type `857ca50e-7905-0000-0007-c5d9ff2975ec` and no additional top-level `Index` object.
- Strong inference: explicitly requesting `Table + Index` in the IDE does not change the observed serialization; `Index` stays consolidated inside `Table`.
- Direct evidence: in a real `WorkWithForWeb`, the attribute references inside the pattern's `CDATA` use the fixed structural prefix `adbb33c9-0906-4971-833c-998de27e0676-AttributeName`.
- Strong inference: for `WorkWithForWeb`, this format should be read as the pattern's own structural convention, not as a reflection of the top-level `Attribute` GUID nor of the `Transaction`'s `Level` inline GUID.
- Direct evidence: the export `XPZExemploTabelaTRNWWPatternA.xpz` came with `596` objects: `228` `Table`, `183` `Transaction`, `183` `WorkWithForWeb`, and `2` `PatternSettings`, with no `Attributes`.
- Direct evidence: the export `XPZExemploTabelaTRNDataSelectorA.xpz` came with `413` objects: `228` `Table`, `183` `Transaction`, and `2` `DataSelector`, also with no `Attributes`.
- Direct evidence: in the combined export with `WorkWithForWeb`, the `Transaction` keeps the property `Apply:78cecefe-be7d-4980-86ce-8d6e91fba04b=True`.
- Direct evidence: in the same export, `PatternSettings 'WorkWith'` materializes `ContextVariable`, `LoadProcedure`, `Security Check`, and `NotAuthorized` in its internal XML.
- Strong inference: the real operational bridge of the observed web pattern is distributed across `Transaction` (pattern application), `WorkWithForWeb` (per-object instance), `PatternSettings` (global pattern configuration), and `Table` (physical layer with internal indexes).
- Direct evidence: the export pair `XPZExemploTRNWWComparacaoSemWW.xpz` and `XPZExemploTRNWWComparacaoComWW.xpz` provided a minimal, comparable cut of the same `Transaction 'TRNExemploMinPaisA'`.
- Direct evidence: `XPZExemploTRNWWComparacaoSemWW` came with `7` objects, `10` top-level attributes, and `25` identities; `XPZExemploTRNWWComparacaoComWW` came with `8` objects, the same `10` attributes, and `49` identities.
- Direct evidence: the only object-level difference between the two cuts was the addition of `WWExemploMinPaisA`.
- Direct evidence: despite that, adding `WWExemploMinPaisA` nearly doubled the total context identities in `ObjectsIdentityMapping`, including additional references to `DomainExemploUfA`, `WPExemploRelacionamentoA`, `WPExemploAtualizacaoServidorA`, and related attributes.
- Strong inference: in the compared minimal export, the `WorkWithForWeb` object added little to the `<Objects>` block while its presence coincided with a substantially larger context graph in `ObjectsIdentityMapping`.

## Later complement - combined export of `API` and the visual stack

### `Table + Domain + Transaction + SDT + API + Procedure + DataProvider`

- Direct evidence: the export `XPZExemploCadeiaAPIA.xpz` came with `3904` objects and `0` top-level attributes.
- Direct evidence: the observed distribution was `2282` `Procedure`, `594` `SDT`, `593` `Domain`, `228` `Table`, `183` `Transaction`, `24` `DataProvider`, and `1` `API`.
- Direct evidence: the `API` exported in that package is `APIExemploIntegracaoA`.
- Direct evidence: this same package proves that the IDE's real export trail for a business-relevant `API` already pulls in a large mass of `Procedure`, `SDT`, `Domain`, `Table`, `Transaction`, and `DataProvider`.
- Direct evidence: the package lists a `Domain` such as `DomainExemploTipoA`, with distinct business values in the same exported set.
- Direct evidence: in the same cut, an `SDT` such as `SDTExemploProdutoBasicoA` and a `Procedure` such as `PRCExemploListaA` appear in the same exported set.
- Strong inference: for this observed `API` case and IDE export, the best reverse-engineering cut is no longer the isolated object; it becomes this broader functional combination.
- Strong inference: this reinforces the reading that this case's remaining gap is not envelope serialization, but a business functional subtree dependency; it does not establish that profile for all `API`s.

### `Table + Transaction + ColorPalette + DesignSystem + Theme + WebTheme + Category + ThemeClass + ThemeColor`

- Direct evidence: the export `XPZExemploTemaA.xpz` came with `947` objects and `0` top-level attributes.
- Direct evidence: the observed distribution was `501` `ThemeClass`, `228` `Table`, `183` `Transaction`, `24` `ThemeColor`, `7` `Theme`, `2` `DesignSystem`, `1` `Folder`, and `1` `ColorPalette`.
- Direct evidence: the package contains an organizational folder `GAM_Samples-web`, reinforcing that the visual family can also carry its structural grouping along with it.
- Direct evidence: the same package showed `ThemeClass` objects such as `ActionAttribute`, `ActionButtons`, and `ActionButtonsHovered`, plus several real `ThemeColor` and `Theme` objects.
- Direct evidence: in that export, `Theme`, `ThemeClass`, `DesignSystem`, `ColorPalette`, and `ThemeColor` appear together in the same IDE-exported cut.
- Strong inference: the full visual stack can and should be studied as a combined family, not as fully independent types.
- Strong inference: this cut reduces the risk of interpreting `Theme`, `ThemeClass`, `DesignSystem`, `ColorPalette`, and `ThemeColor` outside the visual context in which the IDE actually serializes them.

### `Attribute + Domain + Transaction + SubtypeGroup`

- Direct evidence: the export `XPZExemploFamiliaMistaA.xpz` came with `1117` objects, `7646` top-level attributes, and `1576` identities in `ObjectsIdentityMapping`.
- Direct evidence: this package's container used `KMW`, `Source`, `Objects`, `Attributes`, `Dependencies`, and `ObjectsIdentityMapping`.
- Direct evidence: the simultaneous presence of top-level `Objects` and `Attributes` in the same `.xpz` confirms that the IDE's normal export trail can also export a mixed family of real objects and attributes, not only packages with `Objects` and no `Attributes` block.
- Strong inference: for reverse-engineering top-level `Attribute` and its relation to `Transaction`, `Domain`, and `SubtypeGroup`, this cut is more informative than packages without `Attributes`.

### `Attribute + Domain + Transaction + SubtypeGroup + Table + Index`

- Direct evidence: the export `XPZExemploFamiliaMistaB.xpz` came with `1712` objects, the same `7646` top-level attributes, and `1611` identities.
- Direct evidence: this package also used the `KMW`, `Source`, `Objects`, `Attributes`, `Dependencies`, and `ObjectsIdentityMapping` container.
- Direct evidence: the difference from `1117` to `1712` objects between the two packages matches the addition of the `Table` physical layer, while the `Attributes` block stayed stable at `7646`.
- Strong inference: this reinforces that `Table`/`Index` come in as an expansion of the earlier logical family, without moving top-level `Attribute` into `Objects` or removing the `Attributes` block.

### Provisional operational synthesis for `Table`/`Index`

- Direct evidence: on the observed trail, `Table` appears as an exportable top-level object, while `Index` appears embedded inside `Table`.
- Direct evidence: requesting `Table + Index` in the IDE created no additional top-level `Index` objects; the observed serialization stayed centered on `Table`.
- Direct evidence: `Table`'s top-level names follow the names of their corresponding `Transaction`s.
- Direct evidence: in a later private comparison of real simple and dense pairs from the source KB, this `Transaction` -> `Table` naming correspondence also repeated outside the packages already summarized in this base.
- Direct evidence: in the same private comparison, `Index`es kept appearing only inside the physical object's `<Indexes>` block, never as a separate top-level object.
- Direct evidence: in that same private sample, the key-attribute list of the `Transaction`'s first `Level` matched the `Table`'s `<Key>` block list, for both simple and composite keys.
- Direct evidence: in the compared private sample, every observed `Table` carried exactly `1` automatic `Unique` index for the key and a variable set of `Duplicate` indexes, mixing `Automatic` and `User` cases.
- Direct evidence: in the same private pairs, every observed `Automatic`-index member was already present in the corresponding `Transaction`'s first `Level`.
- Direct evidence: in the analyzed KB, the `I` prefix identifies an index GeneXus automatically created from a modeler-defined PK or FK.
- Direct evidence: in the same KB, the `U` prefix identifies an index the human operator created manually.
- Direct evidence: when an automatic `I...` index gets a more descriptive name in this KB, the change is purely editorial; the fields and their order stay exactly the same as the GeneXus-created index.
- Direct evidence: GeneXus's default naming for these automatic indexes is not very descriptive, usually centered on the `Table` name with incremental numbering in the following cases.
- Direct evidence: in automatic FK indexes, the fields follow the same order the modeler defined in the `Transaction`'s relation and reflected in the `Table`.
- Direct evidence: in the same private sample, `Automatic` `Duplicate` indexes mostly appeared in two recurring shapes: a single `...Id` attribute, and pairs `...EmpresaExemploId + ...Id|...Codigo`.
- Direct evidence: in the same private investigation, many `...Id` and `...Codigo` attributes present in the first `Level` did not reappear in `Automatic` indexes, even on denser objects.
- Direct evidence: the friendly names observed for several `Duplicate` indexes reflect the analyzed KB's own editorial/local convention, and should not be treated as GeneXus's default pattern.
- Direct evidence: the friendlier names, abbreviations, and descriptive forms observed in several indexes in this KB come from human renaming to ease maintenance, error reading, and log reading; they should not be read as GeneXus automatic naming nor as a normal response to the 63-character limit.
- Direct evidence: in a later expansion of the private sample to the full local `Table` set, the most recurring `Automatic` `Duplicate` index shapes were `...EmpresaExemploId + ...Id|...Codigo`, then single user-audit attributes (`...InclusaoUsuarioId`, `...UltimaAtualizacaoUsuarioId`), then an isolated `...EmpresaExemploId`, and only then other, less frequent single `...Id`s.
- Direct evidence: in that same expansion, `101/228` local `Table`s combined both some `...EmpresaExemploId + ...Id|...Codigo` pair and some automatic user-audit index; `41/228` showed neither signal in this reading.
- Direct evidence: in a later re-read of the full local set with direct parsing of the `<Indexes>` block, `143/228` `Table`s had at least one `User` index, while `85/228` had none.
- Direct evidence: in that same cut, among the `Table`s without `User`, `69/85` had only `1` or `2` `Automatic` `Duplicate` indexes, and only `16/85` had more than `2`.
- Direct evidence: in the complementary cut, among the `Table`s with `User`, `124/143` fell in the range of `1` to `3` `User` indexes, and only `19/143` had more than `3`.
- Direct evidence: the broad re-read found only `3` `Table`s with no `Automatic` `Duplicate` index at all: `OperacaoFiscal`, `Pais`, and `TipoDocumento`; all three still had at least one `User` index.
- Direct evidence: in those three exceptional cases, the observed `User` index covered ordering or search on a simple business attribute, such as `Descricao`, `Nome`, or `Id Descendente`.
- Strong inference: these three cases are a local exception in the observed KB distribution, where a simple business-attribute `User` index co-occurs with no `Automatic` `Duplicate` index; they do not establish a general structural pattern.
- Direct evidence: in the same broad cut, the corpus totaled `429` `User` indexes; `239/429` contained at least one `Descending` `Member`, and `229/429` ended with their last `Member` `Descending`.
- Direct evidence: in the same cut, `190/429` `User` indexes were entirely `Ascending`, showing that not every manual index in this KB exists for descending order; part of them cover navigation/lookup for specific business combinations.
- Strong inference: within this sample, `Automatic` indexes appear as recombinations of attributes already materialized in the `Transaction` itself, not as the introduction of physical attributes foreign to the first `Level`.
- Strong inference: within this sample, the `...EmpresaExemploId + ...Id|...Codigo` pattern looks like one of the strongest signals of an additional automatic index in the physical layer.
- Strong inference: at the same time, this name pattern alone is not enough to predict an automatic index by itself; it works as a structural clue, not a deterministic rule.
- Strong inference: in the analyzed KB, the combination of the main relationship (`...EmpresaExemploId + ...Id|...Codigo`) and the user-audit trail seems to form the most recurring core of additional `Automatic` indexes.
- Strong inference: the observed automatic audit indexes should be read as just another case of an automatic FK friendlily renamed, not as a special family created by a separate rule.
- Strong inference: the presence of a `User` (`U...`) index should be read as manual, empirical tuning driven by real volume and ordering, not as a mandatory structural offshoot of the `Transaction`.
- Strong inference: in the analyzed KB, a `User` index tends to appear when a grid's, report's, or procedure's real ordering diverges from the available automatic indexes and record volume already justifies a dedicated index.
- Strong inference: a recurring `User` index case reuses almost the same base as an automatic index, but adjusts the sort direction, especially with the last field `Descending` to fetch the most recent record.
- Strong inference: the absence of a `User` index on several `Table`s should be read as a valid, conscious modeler decision, when the expected volume is small and the index's maintenance cost does not pay off.
- Strong inference: outside the heaviest `User` core, the most common residual family is not a total absence of indexes, but a `Table` resolved with just the PK and a few `Automatic` `Duplicate`s, with no need for further manual tuning.
- Strong inference: the rare cases with no `Automatic` `Duplicate` form an exception of a very simple table, where a single `User` index can fill the search/order role with no relevant automatic FK mesh.
- Strong inference: in this observed read-side distribution, `User` indexes are present on `143/228` `Table`s and absent on `85/228`; among the former, `124/143` have `1` to `3` and `19/143` have more than `3`. This describes empirical frequency, not a recommendation for generating or selecting package contents.
- Strong inference: to read this base's physical layer, the primary correlation axis should be `Transaction -> Table`, treating `Index` as `Table`'s internal structure.
- Strong inference: in this base's empirical sample, `Index` observations are structurally informative when considered alongside related object types; recurring co-occurrences include `Transaction + Table`, `Transaction + Table + WorkWithForWeb + PatternSettings`, and `Attribute + Domain + Transaction + SubtypeGroup + Table`. These are read-side correlations, not package-selection instructions.
