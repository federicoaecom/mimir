# 03 - Risk and decision by type

## Document role
Operational and heuristic

## Predominant confidence level
Medium

## Depends on
`01-empirical-base-overview.md`, `02-operational-rules.md`

## Used by
`08-agent-guide.md`

## Purpose
Gather Part-type obligatoriness heuristics and a relative structural-risk map per object type, to support cautious reading and classification of GeneXus objects. This document does not cover generation, cloning, packaging, or import — Mimir Lite is read-only (see `skills/mimir-lite/SKILL.md`); the readiness-for-generation classification and the import test battery that used to live here were dropped as out of scope.

## Part-type obligatoriness by type

- Direct evidence: the counts and Part-type GUIDs below come from Part-type frequency per extracted type, drawn from the empirical corpus (see `01-empirical-base-overview.md`, `01b-part-type-matrix-by-type.md`).
- Strong inference: "strong mandatory indication" means presence in ~100% of that type's samples in this KB.
- Hypothesis: only an external test could turn this into a confirmed requirement; Mimir Lite performs no such test.
- Strong inference: a Part type present in every sampled object of a type deserves priority attention when reading or comparing objects of that type — its absence is worth flagging as a structural anomaly.
- Hypothesis: a Part type that is almost always empty may still be structurally required even when it carries no useful content.

| Type | Objects analyzed | Strong mandatory indication (Part-type GUIDs) | Optional indication | Empty/structural indication |
| --- | --- | --- | --- | --- |
| API | 1 | `9f577ec2-27f4-4cf4-8ad5-f3f50c9d69b5`; `ad3ca970-19d0-44e1-a7b7-db05556e820c`; `babf62c5-0111-49e9-a1c3-cc004d90900a`; `c44bd5ff-f918-415b-98e6-aca44fed84fa`; `e4c4ade7-53f0-4a56-bdfd-843735b66f47` | none | `babf62c5-0111-49e9-a1c3-cc004d90900a` |
| DataProvider | 24 | `1d8aeb5a-6e98-45a7-92d2-d8de7384e432`; `9b0a32a3-de6d-4be1-a4dd-1b85d3741534`; `ad3ca970-19d0-44e1-a7b7-db05556e820c`; `babf62c5-0111-49e9-a1c3-cc004d90900a`; `e4c4ade7-53f0-4a56-bdfd-843735b66f47` | none | `babf62c5-0111-49e9-a1c3-cc004d90900a` |
| DesignSystem | 2 | `36982745-cb77-47a3-bc04-9d0d764ff532`; `75e52d99-6edd-4bad-a1d7-dcc9b7f000ef`; `babf62c5-0111-49e9-a1c3-cc004d90900a`; `c6b14574-4f5f-4e35-aaa7-e322e88a9a10` | none | none |
| PackagedModule | 16 | `babf62c5-0111-49e9-a1c3-cc004d90900a`; `ed1b7b1c-2aaf-46eb-9ec5-db348f6fa3fc` | none | `a5e6a251-2df0-44d8-adab-1da237574326` |
| Panel | 7 | `b4378a97-f9b2-4e05-b2f8-c610de258402`; `babf62c5-0111-49e9-a1c3-cc004d90900a` | none | `babf62c5-0111-49e9-a1c3-cc004d90900a` |
| Procedure | 2281 | `528d1c06-a9c2-420d-bd35-21dca83f12ff`; `763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9`; `9b0a32a3-de6d-4be1-a4dd-1b85d3741534`; `ad3ca970-19d0-44e1-a7b7-db05556e820c`; `babf62c5-0111-49e9-a1c3-cc004d90900a`; `c414ed00-8cc4-4f44-8820-4baf93547173`; `e4c4ade7-53f0-4a56-bdfd-843735b66f47` | none | `babf62c5-0111-49e9-a1c3-cc004d90900a`; `c414ed00-8cc4-4f44-8820-4baf93547173` |
| SDT | 594 (snapshot — see `01a-catalog-and-empirical-patterns.md` for current aggregate totals; not recalculated here) | `5c2aa9da-8fc4-4b6b-ae02-8db4fa48976a`; `babf62c5-0111-49e9-a1c3-cc004d90900a` | none | `babf62c5-0111-49e9-a1c3-cc004d90900a` |
| Theme | 7 | `43b86e51-163f-44af-ac5a-e101541b1a71`; `babf62c5-0111-49e9-a1c3-cc004d90900a`; `c31007a6-01d3-4788-95b3-425921d47758` | none | none |
| Transaction | 183 | `264be5fb-1b28-4b25-a598-6ca900dd059f`; `4c28dfb9-f83b-46f0-9cf3-f7e090b525d5`; `9b0a32a3-de6d-4be1-a4dd-1b85d3741534`; `ad3ca970-19d0-44e1-a7b7-db05556e820c`; `babf62c5-0111-49e9-a1c3-cc004d90900a`; `c44bd5ff-f918-415b-98e6-aca44fed84fa`; `d24a58ad-57ba-41b7-9e6e-eaca3543c778`; `e4c4ade7-53f0-4a56-bdfd-843735b66f47` | none | none |
| WebPanel | 1196 | `763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9`; `9b0a32a3-de6d-4be1-a4dd-1b85d3741534`; `ad3ca970-19d0-44e1-a7b7-db05556e820c`; `babf62c5-0111-49e9-a1c3-cc004d90900a`; `c44bd5ff-f918-415b-98e6-aca44fed84fa`; `d24a58ad-57ba-41b7-9e6e-eaca3543c778`; `e4c4ade7-53f0-4a56-bdfd-843735b66f47` | none | `babf62c5-0111-49e9-a1c3-cc004d90900a` |
| WorkWithForWeb | 183 | `a51ced48-7bee-0001-ab12-04e9e32123d1`; `babf62c5-0111-49e9-a1c3-cc004d90900a` | none | `babf62c5-0111-49e9-a1c3-cc004d90900a` |

### DataView (added after the original snapshot)

- Direct evidence: 1 object analyzed (KB `SampleKb18`, GX 18 U13); the type was not part of the original count snapshot — this is a later empirical addition, not a recount.
- Direct evidence: observed GUIDs — `DataView` object `19abc6ff-2cd2-0000-0006-6d172bc2333b`, structure part `19abc6ff-2cd2-1000-0006-6d172bc2333b`, index part `7706bd3b-212a-1000-0006-8aaeb59068b9`, index object `fc1b76c4-95c5-0000-0101-44f9543121bd`, index-members part `fe47b55c-ea2a-1000-0101-5b38901e24f7`; properties `DVDataStore` and `DVAssocTable` (they reference attributes as `<Attribute-type-GUID>-<Name>`, separated by `;`, in primary-key order).
- Direct evidence: a `DataView` needs four required pieces to read as coherent — an `Attribute` with an exclusive prefix, a structural `Transaction` with no screen/rules, the `DataView` itself with `<DataViewStructurePlatform Dbms="NN">` plus `NAME`/`SCHEMA`, and `DVDataStore` + `DVAssocTable`. Without `DVAssocTable`, GeneXus specification fails with `spc0031: No relationship found among attributes`.
- Direct evidence: without a `<DataViewStructurePlatform>` block for every DBMS in the target environments, the underlying `Transaction` reads as a plain model table again, and any impact analysis reports a pending `CREATE TABLE` — including for a client/production install. A validated case with one platform block per DBMS (PostgreSQL 15, SQL Server 12, Oracle 7) reported `reorgDetected: None` and no `CREATE`/`ALTER TABLE`.
- Strong inference: the high structural risk of a DataView comes from its multi-DBMS dependency (an omitted platform) and from asymmetric identifier quoting (`NAME` quoted on PostgreSQL, unquoted on SQL Server) — not from the XML's own complexity.
- Strong inference: physical indexes (`<DataViewIndexesPlatform>`) should only be treated as stable where the name itself is stable across installs (PostgreSQL `_pkey`); on SQL Server the generated PK suffix changes per install.

## Structural risk map

- Direct evidence: the risk levels below combine `Part` volume, `parent`/`module` dependency, `pattern` presence, and observed sample size.
- Strong inference: this map is an operational reading-caution guide, not a formal success-probability scale for any action.

| Type | Structural risk | Parent/module dependency | Pattern dependency | Current confidence | Reading caution |
| --- | --- | --- | --- | --- | --- |
| API | High | 1/1 | 0/1 | Low | Single real sample; read any other API object as part of a large business-object family (`Procedure`, `DataProvider`, `Domain`, `Transaction`, `Table`, `SDT`), not in isolation. |
| DataProvider | High | 24/24 | 0/24 | Low | `parent` present in 100% of observed samples; an isolated DataProvider XML is incomplete without its parent context. |
| DataView | High | 0/0 | 0/0 | Medium (small sample: 1 real DataView, validated by build in two environments) | Expect the four required pieces (`Attribute` + structural `Transaction` + `DataView` + `DVAssocTable`/`DVDataStore`) and one platform block per DBMS in the target environments; check `NAME` quoting per DBMS. |
| DesignSystem | High | 1/2 | 0/2 | Low | Small sample; avoid extrapolating. |
| PackagedModule | Medium | 2/16 | 0/16 | Medium-low | Needs careful structural diffing and manual review before trusting an interpretation. |
| Panel | High | 7/7 | 7/7 | Low | Simultaneous `parent` and `pattern` dependency in 100% of samples; read as tightly coupled to both. |
| Procedure | High | 2281/2281 | 0/2281 | Low | Strong recurring structure, but 100% `parent` dependency and high internal fragmentation — read the full parent chain before concluding. |
| SDT | Medium | 591/594 | 0/594 | Medium-low | Low `Part` count does not remove `parent` dependency. |
| Table | Low-contextual | 0/228 | 0/228 | High | `ParentModuleDependency = 0/228` reflects the absence of a named `parent` attribute (Table uses only `parentGuid`/`moduleGuid`), not the absence of context — always read together with the `Transaction` of the same name. Part types are fixed and confirmed across all 228 objects. |
| Theme | Medium | 0/7 | 0/7 | Medium-low | Use only for closely diffed, careful reading; depends on a coherent `ThemeClass` graph. |
| Transaction | Very high | 183/183 | 0/183 | Medium | Strong sample size removes "insufficient evidence" as a blocker, but attribute/context dependency stays high — read via structural family and treat anomalies incrementally. |
| WebPanel | Very high | 1195/1196 | 0/1196 | Medium-low | Read via the nearest internal template family; do not treat WebPanel as one uniform structure. |
| WorkWithForWeb | Very high | 183/183 | 183/183 | Medium | Needs full pattern context and a comparable `Transaction` to interpret correctly. |

## Additional type notes

- Direct evidence: `Table` has exactly 2 Part types in 100% of 228 objects: `00000000-0000-0000-0002-000000000004` (key) and `a5c0e770-560d-0001-0001-7fe71c260de3` (indexes). Embedded indexes use `type="9e750647-3679-0000-0100-2529de263960"` with internal Part type `62cfa789-c127-0001-0100-77676175e433`.
- Direct evidence: `Table` is its own top-level family (`857ca50e-7905-0000-0007-c5d9ff2975ec`); `Index` appears embedded inside `Table` in this export trail, not as an independent top-level family.
- Strong inference: for reading the web pattern, the most informative unit is the combination `Transaction + Table + WorkWithForWeb + PatternSettings`.
- Direct evidence: `DataView`'s `0/0` in the structural risk map reflects the absence of counts in the original snapshot (the type was added later, not sampled with the rest), not zero `parent`/`pattern` dependency — do not read it as evidence of low risk.
- Direct evidence: `Folder` is a structurally valid XML type; `Category` is only the label the IDE/importer displays — the two are not rival envelope types.
- Direct evidence: the `Attribute` top-level shape is proven; residual risk sits in semantic properties such as `ControlItemDescription` and `idBasedOn`, which reference real attributes by name.
- Direct evidence: in Panel SD, a mismatched pair — only the `layout id` changed relative to a real IDE export — can leave a lingering `Layout com identificador incorreto` warning; a coherent `level id` + `layout id` pair taken from a real IDE-exported Panel SD does not show it. Read the pair as coupled, not independent.

## Relative runtime-risk note

- Strong inference: without replacing the structural risk above, relative runtime risk tends to be low-to-medium for simple, isolated shells; medium for objects with code but low context dependency; and high when `grid`, `events`, multiple `Level`s, a strong `parent`, or a `pattern` accumulate.
- Hypothesis: this relative runtime reading is only an operational tie-breaker and should be confirmed against `02-operational-rules.md` before it drives any conclusion or reply.
