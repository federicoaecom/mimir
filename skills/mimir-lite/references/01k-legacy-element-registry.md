# 01k - Legacy Element Registry (GeneXus 9 export)

## Document role
Operational and governance

## Predominant confidence level
High for the 11 elements observed in a real GeneXus 9 export (sample `SampleKb7`): classification, mapping, tag, and casing confirmed by direct inspection. `Theme` is the only classified element **not observed** in this sample (kept for coverage reasons — see "Known gaps"); its exact tag/casing will be confirmed once the legacy export engine parses, via sync, a GX9 export that contains it (the parser **and** the sync/inventory integration already exist; only a GX9 export containing the element is missing).

## Depends on
`01a-catalog-and-empirical-patterns.md`

## Used by
`scripts/Test-GeneXusLegacyRegistrySchemaSelfTest.ps1`, `scripts/Test-GeneXusLegacyRegistryDisjointSelfTest.ps1` (validate the registry). `scripts/Build-KbIntelligenceIndex.py` (registry-aware indexer: recognizes and content-aware-skips orphan `gxlegacy/*` folders) and `scripts/Test-MimirKbObjectsXmlNaming.ps1` (naming audit: classifies an orphan by `materializedFolderName`) already consume `scripts/gx-legacy-export-element-registry.json`. The legacy **parser/converter** `scripts/GeneXusLegacyExportFileSupport.ps1` (with its own isolated self-test `scripts/Test-GeneXusLegacyExportFileSupportSelfTest.ps1`) also consumes the registry. **Integration into the sync/inventory flow** is already in production: `scripts/Sync-GeneXusXpzToXml.ps1` (materialization into the corpus via the legacy branch) and `scripts/Get-GeneXusXpzObjectInventory.ps1` (`known-legacy` items) consume the registry through the shared engine, with self-tests `scripts/Test-GeneXusXpzSyncLegacyExportFullSnapshotSelfTest.ps1`, `scripts/Test-MimirKbSourceMetadataLegacySelfTest.ps1`, and `scripts/Test-GeneXusXpzObjectInventoryLegacyExportSelfTest.ps1`.

## Purpose

Document the **representation and governance layer** of GeneXus 9 legacy export elements — without polluting the modern catalog `scripts/gx-object-type-catalog.json`.

A GeneXus 9 export is an `ExportFile` whose objects appear as `<GXObject><Element>...`, identified by the **element name** (e.g. `<Report>`, `<Menubar>`), **without** the `Object/@type` (type GUID) that the modern GeneXus 18 export carries. Because of that, these elements have no place in the modern catalog, whose key is the type GUID. The **registry** `scripts/gx-legacy-export-element-registry.json` is the executable technical source for this classification; this document is the explanatory, normative reference.

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
| `successorRelation` | Relation to the successor. The enum covers **only the known corpus**: `absorbed` (the concept was absorbed by the successor) and `none` (no successor; requires `modernSuccessor: null`). New values only with explicit criteria and a real case. |

## Inventory of the 12 elements

Peer-validated table, **confirmed by a real GeneXus 9 export** (sample `SampleKb7`, KB "SampleKb7": 11 of the 12 elements observed; only `Theme` not observed). `equivalent` (11):

| GX9 element | `catalogType` (modern) |
| --- | --- |
| `Transaction` | `Transaction` |
| `StructureDataType` | `SDT` |
| `Language` | `Language` |
| `Table` | `Table` |
| `Procedure` | `Procedure` |
| `DataView` | `DataView` |
| `WorkPanel` | `WorkPanel` |
| `Folder` | `Folder` |
| `Group` | `SubTypeGroup` |
| `Theme` | `Theme` (not observed in the sample — see "Known gaps") |
| `Menubar` | `Menubar` |

Note on `Group`: in GeneXus naming, the **Subtype Group** is called "Group" (the wiki describes it as *"A Group can be viewed as a 'virtual' transaction"*); that is why the legacy `Group` element maps to the modern `SubTypeGroup` type. The legacy `Folder` element (organizational folder) is separate and maps to the `Folder` type. Both are confirmed in the sample (`Group` carries `<Subtype><Name>/<Supertype>`; `Folder` is an organizational folder).

Note on `WorkPanel`: the legacy `WorkPanel` element maps to the modern **`WorkPanel`** type (the desktop/Windows generator object, deprecated since GeneXus 15, with its own catalog GUID) — **not** to `WebPanel` (a web page, a distinct runtime). The registry's earlier `WebPanel` entry was a tag/type error from the version validated without a sample; `SampleKb7` confirms the real tag is `WorkPanel` (169 occurrences).

Note on `Menubar`: the legacy `<Menubar>` element maps to the modern **`Menubar`** type (GUID `28eca899-...`, folder `Menubar`), residual in converted KBs / Win generators; wiki [Menu Bar](https://docs.genexus.com/en/wiki?7610%2CMenu+Bar=) (deprecated since GeneXus 15). Until 2026-08-12 it was classified as `orphan` (`gxlegacy/Menubar`) under the hypothesis of "no modern successor"; evidence from a GeneXus 18 export (KB `SampleKb6`, objects `BbInfo`/`Bbinfo2`) reclassified it to `equivalent`, following the same pattern as `WorkPanel`. Distinct from Native Mobile's `Menu` and from the `K2BMenu` addon.

**Corpus migration (mandatory if the orphan was already materialized):** with the reclassification, `Menubar/` **stops** being an orphan folder `Build-KbIntelligenceIndex.py` skips (only `Report` remains `orphan`). XMLs still carrying `type="gxlegacy/Menubar"` under `Menubar/` become an unknown GUID/token → the index rebuild **fails** (`SystemExit` / unknown type), it does not silently mask them as an orphan. Before rebuilding: re-sync the legacy package (materializes the real GUID) or manually clean up those files.

`orphan` (1):

| GX9 element | `materializedFolderName` | `typeToken` | `modernSuccessor` | `successorRelation` |
| --- | --- | --- | --- | --- |
| `Report` | `Report` | `gxlegacy/Report` | `Procedure` | `absorbed` |

### Orphan discontinuation (prose)

- **`Report`**: the classic GeneXus Report object was **absorbed** by the modern Procedure (output generation via a procedure with a print layout). `modernSuccessor` records `Procedure` only as a migration trail — the legacy artifact is still represented by `gxlegacy/Report`, not as a Procedure.

## Known gaps (do not block representation)

- 11 of the registry's 12 elements were **confirmed by direct inspection of a real GeneXus 9 export** (sample `SampleKb7`, KB "SampleKb7", GeneXus 9.0 export): tag, casing (`Menubar` lowercase after the first letter; `WorkPanel`, `DataView`, `StructureDataType`, `Procedure`, etc.), and structure match the classification. Should tag/casing ever diverge in another GX9 KB, that is a registry correction, not a class or mapping change.
- **`Theme` is the only element not observed** in the `SampleKb7` sample (a desktop/Windows-profile KB — 169 `WorkPanel`s, no web pages → no Themes). It is kept in the registry as a **coverage decision**, not on sample evidence: the Theme object has existed in GeneXus since 8.0 (codename Olimar, 2003), and GeneXus 9.0 (Yi, 2005) supported it — a fact from **official GeneXus documentation**, not verified against this sample or against the repository. The exact tag/casing of `<Theme>` in a GX9 export remains **presumed** until the (already existing) legacy export engine materializes, via sync, a GX9 export that contains it; if the real tag diverges, the parser fails closed on an unknown tag (a registry fix, not an engine fix).

## Cross-flow modern↔legacy detection (`dataSource` origin divergence)

Corpus identity is only `FolderType|NormalizedName`. If the **same** object is materialized first by a **modern** export and then by a **legacy GeneXus 9** export (or vice versa) under the same folder/name, the envelopes differ (`dataSource="gx-legacy-export"` + `GxLegacyPayload` + `guid=""` in the legacy one vs. the modern envelope) but the identity does not — without detection, the second sync would silently **overwrite** the first by `lastUpdate`. It is **rare** (a real KB is usually modern **or** legacy, not both). The sync handles it as follows:

- **`Sync-GeneXusXpzToXml.ps1` detects** the origin divergence before writing metadata/XML (`Get-GeneXusCrossFlowDataSourceCollisions`, pre-rename): it compares the incoming node's `dataSource` against the already-materialized file's. Default posture is **fail-soft** — a `Summary.CrossFlowCollisions` field in stdout, a `Writes[].CrossFlowCollision` boolean in the report, and the collision also on stderr (`CROSSFLOW_COLLISION:` JSONL); `lastUpdate` still decides the overwrite, but the collision is no longer silent. The **opt-in** `-BlockCrossFlowDataSource` block aborts before touching metadata/XML (distinct from the **mixed**-package fail-closed, which is within a single `ExportFile`; this collision is **between sync runs**).
- **Secondary signal (Decision E.2):** when the existing file has **no** `dataSource`, a direct `<GxLegacyPayload>` child is the (legacy-exclusive) legacy signal; `guid=""` is only corroborating.
- **Residual limitation (Decision E):** (a) a **modern** XML missing the `dataSource` attribute / with `dataSource=""` is modern origin **by design** (intended); (b) a **legacy** file dropped in by hand **with no signal at all** (no `dataSource`, no `<GxLegacyPayload>`, no `guid=""`) is treated as modern and **does not** trigger a collision — a marginal case, since the legacy engine always stamps `dataSource="gx-legacy-export"`.
- **Residual risk (Decision G):** for an existing XML that is **not parseable**, detection cannot produce a reliable origin: it **neither raises a collision nor blocks** (even under `-BlockCrossFlowDataSource`), it only emits a warning (`CROSSFLOW_WARNING:`). This **does not guarantee overwriting** the file: sync can still fail further along while processing a corrupted existing file (the existing parse stages — `Get-LastUpdateInfoFromFile`/`Test-PackageMaterialization` —, which this detection does not cover).

## Invariants validated by self-test

- `Test-GeneXusObjectTypeCatalogPuritySelfTest.ps1` — purity of the modern catalog: `objectTypeGuid: null` is accepted only for an entry with `rootKind: "Attribute"` (its own envelope); every other `rootKind` requires a valid UUID; fail-safe for a new `rootKind` (any `rootKind` outside `Object`/`Virtual`/`Attribute` fails, forcing a conscious review of the purity rule). Does not use a "looks synthetic" heuristic — GUIDs with a repeating pattern (`dcdcdcdc-...` DataStore, `ecececec-...` Generator) are real. Token: `GENEXUS_CATALOG_PURITY_SELFTEST_OK`.
- `Test-GeneXusLegacyRegistrySchemaSelfTest.ps1` — intra-registry shape: `schemaVersion: 1`; `class` in `{equivalent, orphan}`; `equivalent` has exactly `class`+`catalogType`; `orphan` has `materializedFolderName`/`typeToken`/`modernSuccessor`/`successorRelation`; `typeToken` matches the regex; `successorRelation` in `{absorbed, none}` with the `none` ⟺ `modernSuccessor null` coherence. Token: `GENEXUS_LEGACY_REGISTRY_SCHEMA_SELFTEST_OK`.
- `Test-GeneXusLegacyRegistryDisjointSelfTest.ps1` — registry × catalog disjointness: an orphan's name, `typeToken`, and `materializedFolderName` never collide with any catalog type/`folderName`; every `equivalent`'s `catalogType` exists in the catalog; a non-null `modernSuccessor` exists in the catalog. Token: `GENEXUS_LEGACY_REGISTRY_DISJOINT_SELFTEST_OK`.
