# 01k - Legacy Element Registry (GeneXus 8 and 9 export)

## Document role
Operational and governance

## Predominant confidence level
High for the 11 elements observed in a real GeneXus 9 export (sample `SampleKb7`) and for the 5 elements observed in a public GeneXus 8.0 export (export header `KMW` 2.1, `MaxGxBuildSaved` 1595: `WebPanel`, `Report`, `Theme`, `Group`, `Folder`): classification, mapping, tag, and casing confirmed by direct inspection. Every one of those 13 elements has now been observed in at least one of the two exports; `Theme` was observed only in the GeneXus 8 one (see "Known gaps"). Medium for the 3 orphans `Menu`, `Prompt`, and `Formula`: observed in GeneXus 6 and 7.0 `.xpw` text exports (structure only), and their classic XML tags are what the `.xpw` translator emits, not tags read from a GeneXus 7.5 to 9 XML export (see "Known gaps").

## Depends on
`01a-catalog-and-empirical-patterns.md`

## Used by
`scripts/Test-GeneXusLegacyRegistrySchemaSelfTest.ps1`, `scripts/Test-GeneXusLegacyRegistryDisjointSelfTest.ps1` (validate the registry). `scripts/Build-KbIntelligenceIndex.py` (registry-aware indexer: indexes an orphan flagged `indexedByKbIntelligence` as its own type, and content-aware-skips the other orphan `gxlegacy/*` folders) and `scripts/Test-MimirKbObjectsXmlNaming.ps1` (naming audit: classifies an orphan by `materializedFolderName`) already consume `scripts/gx-legacy-export-element-registry.json`. The legacy **parser/converter** `scripts/GeneXusLegacyExportFileSupport.ps1` (with its own isolated self-test `scripts/Test-GeneXusLegacyExportFileSupportSelfTest.ps1`) also consumes the registry. **Integration into the sync/inventory flow** is already in production: `scripts/Sync-GeneXusXpzToXml.ps1` (materialization into the corpus via the legacy branch) and `scripts/Get-GeneXusXpzObjectInventory.ps1` (`known-legacy` items) consume the registry through the shared engine, with self-tests `scripts/Test-GeneXusXpzSyncLegacyExportFullSnapshotSelfTest.ps1`, `scripts/Test-MimirKbSourceMetadataLegacySelfTest.ps1`, and `scripts/Test-GeneXusXpzObjectInventoryLegacyExportSelfTest.ps1`.

## Purpose

Document the **representation and governance layer** of GeneXus 9 legacy export elements — without polluting the modern catalog `scripts/gx-object-type-catalog.json`.

A GeneXus 8 or 9 export is an `ExportFile` whose objects appear as `<GXObject><Element>...`, identified by the **element name** (e.g. `<Report>`, `<Menubar>`), **without** the `Object/@type` (type GUID) that the modern GeneXus 18 export carries. Because of that, these elements have no place in the modern catalog, whose key is the type GUID. A GeneXus 7.0 and earlier `.xpw` text export is translated into the same `<ExportFile><GXObject><Element>` shape, so its elements go through this same registry. The **registry** `scripts/gx-legacy-export-element-registry.json` is the executable technical source for this classification; this document is the explanatory, normative reference.

> Scope: this document and the registry define **representation and governance** (how each legacy element relates to the modern world). The **export engine** (parsing the GeneXus 9 `ExportFile`, materializing it into `KbObjectsXml`, and integrating it into sync/inventory) **already exists** — in `scripts/GeneXusLegacyExportFileSupport.ps1` and in the legacy branches of `Sync-GeneXusXpzToXml.ps1`/`Get-GeneXusXpzObjectInventory.ps1` — but its **internal behavior** is not described here: this document is the representation/governance reference, not the engine spec.

## Model: equivalent vs orphan

Every legacy element belongs to one of two classes:

- **`equivalent`** — the legacy element has a **real modern type** in the catalog (`catalogType`). It materializes exactly as the corresponding modern type; it **reuses the catalog's `folderName`** (it defines no folder of its own). The `modernSuccessor` field does not apply: there is no succession, there is type identity.
- **`orphan`** — the legacy element has **no** direct modern equivalent. It materializes into its own folder (`materializedFolderName`) under a synthetic type token, `typeToken`, in the format `gxlegacy/<Element>`, which unambiguously distinguishes it from any modern catalog type.

GUID-based reconciliation (`reconcilableByGuid`) is a **class invariant**, not a registry field. Note the **two distinct GUIDs**: the **type GUID** (`Object/@type`) — which legacy elements lack, and which is why they sit outside the modern catalog — is **not** the one used by `Sync-GeneXusXpzToXml.ps1`'s GUID-aware rename, which reconciles by the **object root node's `guid`** (instance identity). The **legacy export engine** materializes items with an **empty** object `guid` (`guid=""`) — the `SampleKb7` sample confirms the GeneXus 9 export carries no object `guid` — so they **do not participate** in GUID-based rename (`Test-IsMeaningfulGuid("")==false`); whether/how they would participate in the future would depend on a legacy export that carried a stable instance identity. This holds for both classes and does not need repeating per element.

### Fields by class

`equivalent`:

| Field | Meaning |
| --- | --- |
| `class` | Always `"equivalent"`. |
| `catalogType` | The modern type's name in `scripts/gx-object-type-catalog.json`. Defines materialization and the reused `folderName`. |

`orphan`:

| Field | Meaning |
| --- | --- |
| `class` | Always `"orphan"`. |
| `materializedFolderName` | Its own folder in `KbObjectsXml` where the orphan materializes. Never collides with any catalog `folderName`/type. |
| `typeToken` | Synthetic type token, locked format `^gxlegacy/[A-Za-z][A-Za-z0-9]*$`. It is the orphan artifact's internal identifier; **trivially extensible** if a future legacy element has `_`/`-` in its tag (revisit the regex against a real case). |
| `modernSuccessor` | **Migration metadata**, not identity: the modern type that absorbed or succeeded the concept. **Never** becomes the materialized artifact's `type` (the orphan artifact is represented by its `typeToken`, not by the successor). `null` when there is no successor. |
| `indexedByKbIntelligence` | Optional boolean, default `false`. When `true`, KB Intelligence indexes the orphan as its own type, named after `materializedFolderName` (`Report`), and the queries answer for it. Any other value (absent, `false`, a string) keeps the orphan skipped, and the skip is audited in `legacy_orphan_directories_skipped`. |
| `successorRelation` | Relation to the successor. The enum covers **only the known corpus**: `absorbed` (the concept was absorbed by the successor) and `none` (no successor; requires `modernSuccessor: null`). New values only with explicit criteria and a real case. |

## Inventory of the 16 elements

Peer-validated table of the first 12 elements, **confirmed by a real GeneXus 9 export** (sample `SampleKb7`, KB "SampleKb7": 11 of those 12 observed; `Theme` not observed). `WebPanel` was added, and `Theme` observed, from the public GeneXus 8.0 export. `equivalent` (12):

| Legacy element | `catalogType` (modern) |
| --- | --- |
| `Transaction` | `Transaction` |
| `StructureDataType` | `SDT` |
| `Language` | `Language` |
| `Table` | `Table` |
| `Procedure` | `Procedure` |
| `DataView` | `DataView` |
| `WorkPanel` | `WorkPanel` |
| `WebPanel` | `WebPanel` (GeneXus 8 export) |
| `Folder` | `Folder` |
| `Group` | `SubTypeGroup` (a blank-name `Group` splits per subtype — see below) |
| `Theme` | `Theme` (observed in the GeneXus 8 export only — see "Known gaps") |
| `Menubar` | `Menubar` |

Note on `Group`: in GeneXus naming, the **Subtype Group** is called "Group" (the wiki describes it as *"A Group can be viewed as a 'virtual' transaction"*); that is why the legacy `Group` element maps to the modern `SubTypeGroup` type. The legacy `Folder` element (organizational folder) is separate and maps to the `Folder` type. Both are confirmed in the sample (`Group` carries `<Subtype><Name>/<Supertype>`; `Folder` is an organizational folder).

Note on ungrouped subtypes: every package of the GeneXus 8 export carries one `<Group>` whose `Info/Name` is blank (`<Name> </Name>`) and that has no `LastUpdate`; it holds the subtypes that belong to no group (e.g. `SubC`→`SuperC`). A modern GeneXus subtype always belongs to a named group, so this container has no modern equivalent of its own. The engine **splits it into one `SubTypeGroup` item per `<Subtype>`**, named after the subtype, whose payload keeps only that `<Subtype>` and the blank `Info/Name` (the marker that it was ungrouped). A single item under a fixed name would be unsafe: the sync overwrites a file when the incoming `lastUpdate` is not older, so a later package carrying fewer subtypes would silently drop the others. Fail-closed: a blank-name `Group` with no `<Subtype>`, an ungrouped `<Subtype>` without a `Name`, and two `Group` items (named or ungrouped) with the same name in one package.

Note on `WorkPanel` and `WebPanel`: the legacy `WorkPanel` element maps to the modern **`WorkPanel`** type (the desktop/Windows generator object, deprecated since GeneXus 15, with its own catalog GUID), and the legacy `WebPanel` element to the modern **`WebPanel`** type (a web page, a distinct runtime). They are two different tags. An earlier registry version mapped GX9's desktop objects to `WebPanel` without a sample; `SampleKb7`, a desktop-profile KB, showed their real tag is `WorkPanel` (169 occurrences). The `WebPanel` tag itself was confirmed later by the GeneXus 8 export, a web KB.

Note on `Menubar`: the legacy `<Menubar>` element maps to the modern **`Menubar`** type (GUID `28eca899-...`, folder `Menubar`), residual in converted KBs / Win generators; wiki [Menu Bar](https://docs.genexus.com/en/wiki?7610%2CMenu+Bar=) (deprecated since GeneXus 15). Until 2026-08-12 it was classified as `orphan` (`gxlegacy/Menubar`) under the hypothesis of "no modern successor"; evidence from a GeneXus 18 export (KB `SampleKb6`, objects `BbInfo`/`Bbinfo2`) reclassified it to `equivalent`, following the same pattern as `WorkPanel`. Distinct from Native Mobile's `Menu` and from the `K2BMenu` addon.

**Corpus migration (mandatory if the orphan was already materialized):** with the reclassification, `Menubar/` **stops** being an orphan folder `Build-KbIntelligenceIndex.py` skips (the skipped orphan folders are now only those of `Menu`, `Prompt`, and `Formula`; `Report` is indexed). XMLs still carrying `type="gxlegacy/Menubar"` under `Menubar/` become an unknown GUID/token → the index rebuild **fails** (`SystemExit` / unknown type), it does not silently mask them as an orphan. Before rebuilding: re-sync the legacy package (materializes the real GUID) or manually clean up those files.

`orphan` (4):

| Legacy element | `materializedFolderName` | `typeToken` | `modernSuccessor` | `successorRelation` | Indexed by KB Intelligence |
| --- | --- | --- | --- | --- | --- |
| `Report` | `Report` | `gxlegacy/Report` | `Procedure` | `absorbed` | yes |
| `Menu` | `Menu` | `gxlegacy/Menu` | `null` | `none` | no (skipped and audited) |
| `Prompt` | `Prompt` | `gxlegacy/Prompt` | `WorkPanel` | `absorbed` | no (skipped and audited) |
| `Formula` | `Formula` | `gxlegacy/Formula` | `Attribute` | `absorbed` | no (skipped and audited) |

`Report` carries `indexedByKbIntelligence: true`: the index and its queries name it `Report` (owner decision 2026-10-15), not Procedure. `Menu`, `Prompt`, and `Formula` carry no flag (owner decision 2026-10-15): they sync, so a `.xpw` that holds them no longer aborts on an unknown tag, but KB Intelligence skips their folders and lists them in `legacy_orphan_directories_skipped`. None of the three names, folders, or tokens collides with a modern catalog type or folder (the catalog has `Menubar`, `K2BMenu`, and `K2BPrompt`, which are distinct names), so each folder is named after its element.

Note on naming: every element is named by `Info/Name`, except `Formula`. A `.xpw` formula is a top-level block `:Formula` with `Name` (the attribute it computes) and `Type` plus a `Source`, with no `Info` block; the engine names it from its direct `Name` child, so `Formula/<attribute>.xml`. Only `Formula` takes that fallback: any other element without `Info/Name` still fails closed, and a `Formula` with a blank `Name` fails closed too.

### Orphan discontinuation (prose)

- **`Report`**: the classic GeneXus Report object was **absorbed** by the modern Procedure (output generation via a procedure with a print layout). `modernSuccessor` records `Procedure` only as a migration trail — the legacy artifact is still represented by `gxlegacy/Report`, not as a Procedure.
- **`Menu`**: the classic menu object (`Info` plus a `MenuOptions` list of `OptionCode`, `PgmType`, `PgmName`, `Description`) is a list of options that call programs. It has **no** modern successor in the catalog: `Menubar` is a different object with its own tag, and the Native Mobile `Menu` and the `K2BMenu` addon are unrelated concepts. Hence `none`.
- **`Prompt`**: the classic prompt object (`Info`, `PromptInfo` with `Name`, `Description`, `Table`, plus `Events` and `Rules`) is a selection list over a table. Later GeneXus versions generate prompts as ordinary panels (Work Panels in a desktop KB) instead of a separate object type, so the concept was **absorbed** by `WorkPanel`. This successor is presumed from GeneXus knowledge, not observed in an export that shows the migration.
- **`Formula`**: the classic formula block (`Name` of the attribute, `Type`, and its `Source`) defines the formula of one attribute outside the attribute itself. In later versions the formula is a property of the attribute, so the concept was **absorbed** by `Attribute`. Presumed from GeneXus knowledge, like `Prompt`.

## `.xpw` text exports (GeneXus 7.0 and earlier)

`scripts/GeneXusXpwExportFileSupport.ps1` translates a `.xpw` text export (one file, or every `.xpw` entry of a `.zip` merged) in memory into the classic shape this registry governs, so the sync, the inventory, and the index treat it as a classic XML export:

- a block `:Tag` ... `:eTag` becomes `<Tag>` with the same name (the only renamings are the qualified tags and `:Doc`, below), and each top-level block other than `:KMW` becomes one `<GXObject><Tag/></GXObject>`; a qualified tag such as `:Att:Font` becomes `<Att_Font>`; `Key=Value` becomes `<Key>Value</Key>`, and a bare `Key` becomes `<Key>Y</Key>`;
- `Source`, `Rules`, `Events`, `Conditions`, and `Subroutines` keep their text as CDATA, line for line;
- the three sibling blocks `:Attribute`, `:AttInfo`, `:Doc` of one attribute become `<Attributes><GXAtt><Attribute/><AttInfo/><AttDoc/></GXAtt></Attributes>`;
- a top-level `:Formula` written between an attribute's `:AttInfo` and `:Doc` becomes its own `<GXObject><Formula/></GXObject>` (named after the attribute, see "Note on naming"), and the following `:Doc` still joins that attribute;
- the header `Model=` line becomes `Model/Name`, and a `:KMW` block (`KMW` 1.x: `MajorVersion`, `MinorVersion`, no `Build`) becomes `/ExportFile/KMW`.

A tag the `.xpw` emits that is not in the registry fails closed like any classic tag. The translator's grammar and its fail-closed cases are in the script's own header.

## Known gaps (do not block representation)

- 11 of the registry's 16 elements were **confirmed by direct inspection of a real GeneXus 9 export** (sample `SampleKb7`, KB "SampleKb7", GeneXus 9.0 export): tag, casing (`Menubar` lowercase after the first letter; `WorkPanel`, `DataView`, `StructureDataType`, `Procedure`, etc.), and structure match the classification. Should tag/casing ever diverge in another GX9 KB, that is a registry correction, not a class or mapping change.
- **`Theme` was not observed** in the `SampleKb7` sample (a desktop/Windows-profile KB — 169 `WorkPanel`s, no web pages → no Themes). The GeneXus 8.0 export confirms the tag and casing `<Theme>` (a Theme object with `Info`, `ObjInfo`, `LastUpdate`, `Xml`). For GeneXus 9 the tag stays **presumed** from that GeneXus 8 evidence and from official documentation (the Theme object exists since 8.0 and 9.0 supports it); if a GX9 export ever diverges, the parser fails closed on an unknown tag (a registry fix, not an engine fix).
- **`WebPanel` was not observed in GeneXus 9** (the GX9 sample is a desktop KB). Its tag comes from the GeneXus 8 export only.
- **GeneXus 7.5** is assumed to share this format (the 7.5 release notes introduced the XML export), but no 7.5 export has been read.
- **`Menu`, `Prompt`, and `Formula` come from GeneXus 6 and 7.0 `.xpw` text exports** (a mapping of public samples and one real export, structure only: `Menu` and `Formula` in the samples, `Prompt` in the real export). Their tags in a GeneXus 7.5 to 9 XML export are **presumed**, not observed: the registry keys are the tags the `.xpw` translator emits. If a classic XML export ever carries a different tag for them, the parser fails closed on the unknown tag (a registry fix, not an engine fix).

## Cross-flow modern↔legacy detection (`dataSource` origin divergence)

Corpus identity is only `FolderType|NormalizedName`. If the **same** object is materialized first by a **modern** export and then by a **legacy GeneXus 9** export (or vice versa) under the same folder/name, the envelopes differ (`dataSource="gx-legacy-export"` + `GxLegacyPayload` + `guid=""` in the legacy one vs. the modern envelope) but the identity does not — without detection, the second sync would silently **overwrite** the first by `lastUpdate`. It is **rare** (a real KB is usually modern **or** legacy, not both). The sync handles it as follows:

- **`Sync-GeneXusXpzToXml.ps1` detects** the origin divergence before writing metadata/XML (`Get-GeneXusCrossFlowDataSourceCollisions`, pre-rename): it compares the incoming node's `dataSource` against the already-materialized file's. Default posture is **fail-soft** — a `Summary.CrossFlowCollisions` field in stdout, a `Writes[].CrossFlowCollision` boolean in the report, and the collision also on stderr (`CROSSFLOW_COLLISION:` JSONL); `lastUpdate` still decides the overwrite, but the collision is no longer silent. The **opt-in** `-BlockCrossFlowDataSource` block aborts before touching metadata/XML (distinct from the **mixed**-package fail-closed, which is within a single `ExportFile`; this collision is **between sync runs**).
- **Secondary signal (Decision E.2):** when the existing file has **no** `dataSource`, a direct `<GxLegacyPayload>` child is the (legacy-exclusive) legacy signal; `guid=""` is only corroborating.
- **Residual limitation (Decision E):** (a) a **modern** XML missing the `dataSource` attribute / with `dataSource=""` is modern origin **by design** (intended); (b) a **legacy** file dropped in by hand **with no signal at all** (no `dataSource`, no `<GxLegacyPayload>`, no `guid=""`) is treated as modern and **does not** trigger a collision — a marginal case, since the legacy engine always stamps `dataSource="gx-legacy-export"`.
- **Residual risk (Decision G):** for an existing XML that is **not parseable**, detection cannot produce a reliable origin: it **neither raises a collision nor blocks** (even under `-BlockCrossFlowDataSource`), it only emits a warning (`CROSSFLOW_WARNING:`). This **does not guarantee overwriting** the file: sync can still fail further along while processing a corrupted existing file (the existing parse stages — `Get-LastUpdateInfoFromFile`/`Test-PackageMaterialization` —, which this detection does not cover).

## Invariants validated by self-test

- `Test-GeneXusObjectTypeCatalogPuritySelfTest.ps1` — purity of the modern catalog: `objectTypeGuid: null` is accepted only for an entry with `rootKind: "Attribute"` (its own envelope); every other `rootKind` requires a valid UUID; fail-safe for a new `rootKind` (any `rootKind` outside `Object`/`Virtual`/`Attribute` fails, forcing a conscious review of the purity rule). Does not use a "looks synthetic" heuristic — GUIDs with a repeating pattern (`dcdcdcdc-...` DataStore, `ecececec-...` Generator) are real. Token: `GENEXUS_CATALOG_PURITY_SELFTEST_OK`.
- `Test-GeneXusLegacyRegistrySchemaSelfTest.ps1` — intra-registry shape: `schemaVersion: 1`; `class` in `{equivalent, orphan}`; `equivalent` has exactly `class`+`catalogType`; `orphan` has `materializedFolderName`/`typeToken`/`modernSuccessor`/`successorRelation`, plus the optional boolean `indexedByKbIntelligence`; `typeToken` matches the regex; `successorRelation` in `{absorbed, none}` with the `none` ⟺ `modernSuccessor null` coherence. Token: `GENEXUS_LEGACY_REGISTRY_SCHEMA_SELFTEST_OK`.
- `Test-GeneXusLegacyRegistryDisjointSelfTest.ps1` — registry × catalog disjointness: an orphan's name, `typeToken`, and `materializedFolderName` never collide with any catalog type/`folderName`; every `equivalent`'s `catalogType` exists in the catalog; a non-null `modernSuccessor` exists in the catalog. Token: `GENEXUS_LEGACY_REGISTRY_DISJOINT_SELFTEST_OK`.
