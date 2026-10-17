# 06 - Object patterns and naming

## Document role
Conceptual

## Predominant confidence level
Medium

## Depends on
`01-empirical-base-overview.md`

## Used by
`08-agent-guide.md`

## Purpose
Gather observed naming, organization, and cross-reference patterns from the corpus, without promoting them to a structural guarantee.

## Scope

This document records patterns observed in the raw inventory and in the XML extracted from the main analyzed KB, complemented by a comparative full export from an independent KB used only as a counter-check for generic GeneXus-ecosystem names. It does not prescribe mandatory conventions with no visible support in the corpus.

## Later comparative evidence

- Direct evidence: a comparative full export from an independent KB confirmed the presence of names shared across the GeneXus ecosystem, such as `Main Programs`, `ToBeDefined`, `UI`, `GAM_Frontend`, `GeneXusSecurity`, `GeneXusReporting`, and `SidebarItemsDP`.
- Strong inference: when a name appears in both the main corpus and that independent KB, confidence grows that it belongs to the generic/community GeneXus repertoire, not just to the main KB's own business domain.

## Naming patterns by group

### `Procedure`

- Direct evidence: many objects carry the `proc` prefix, e.g. `PRCExemploA`, `PRCExemploB`, `PRCExemploC`, referenced from XML read as `APIExemploIntegracaoA.xml` and `MODExemploAMenu.xml`.
- Direct evidence: procedures without the `proc` prefix also exist, e.g. `ctodUTC` and `curvalSTRZERO`.
- Strong inference: the `proc` prefix is common but neither exclusive nor mandatory in this corpus.

### `DataProvider`

- Direct evidence: several names start with `dp`, e.g. `DPExemploA`, `DPExemploB`, `DPExemploC`, `DPExemploD`.
- Direct evidence: exceptions with other shapes also exist, e.g. `DPRegions`, `DPSampleInfinityScrollGrid`, `GAM_GetTotalUsers`, `SidebarItemsDP`.
- Direct evidence: the comparative full export also carried `SidebarItemsDP`, reinforcing that this name is not exclusive to the main KB analyzed.
- Strong inference: the `DataProvider` group favors function-identifiable names, with a strong `dp` prefix presence, but accepts legacy variants and third-party module names.

### `SDT`

- Direct evidence: names with the `sdt` prefix appear in the corpus, e.g. `SDTExemploTribSelecaoA`, `SDTExemploDadosA`, `SDTExemploFaturaA`.
- Strong inference: the `sdt` prefix looks like a frequent convention for data structures, though capitalization varies.

### `WebPanel`

- Direct evidence: the corpus includes names such as `wpEntradaMODExemploA`, `wpEscolhaItemMODExemploA`, `WWEntradaMODExemploA`, `VWExemploA`, `MODExemploAMenu`.
- Strong inference: there is no single stable prefix for every `WebPanel`; `wp`, `WW`, `View`, and prefix-free conceptual names coexist.

### `WorkWithForWeb`

- Direct evidence: observed file names include `WorkWithWebTRNExemploB`, `WWExemploB`, and `WWExemploBPadrao`.
- Direct evidence: the observed names are inconsistent: one uses the `WorkWithWeb` prefix, while the examples `WWExemploB` and `WWExemploBPadrao` use `WW`.
- Strong inference: this source corpus does not establish one consistent naming signature for `WorkWithForWeb`; the difference between `WorkWithWeb` and `WW` is source ambiguity, not evidence that one form is canonical.

### `Transaction`, `Domain`, and `Module`

- Direct evidence: prefix-free conceptual names exist, e.g. `TRNExemploA`, `TRNExemploB`, `TRNExemploC`, `TRNExemploD`, `MODExemploA`, `MODExemploB`, `MODExemploC`.
- Direct evidence: the comparative full export also showed shared containers such as the Categories `Main Programs` and `ToBeDefined` (type `00000000-0000-0000-0000-000000000006`, folder `Module/`) and `UI`, `GAM_Frontend`, `GeneXusReporting`.
- Strong inference: in these groups, the dominant pattern is a business or technical concept name, not a prefix.

## Organization patterns

- Direct evidence: several objects carry `parent` pointing at a logical container, e.g. `MODExemploAMenu` with `parent="MODExemploA"` and `APIExemploIntegracaoA` with `parent="MODExemploD"`.
- Strong inference: modules and containers act as an important organizing axis for the corpus.
- Direct evidence: the raw inventory also records `moduleGuid` and `parentGuid`, reinforcing an explicit link-based organization.

## Structural identity patterns

- Direct evidence: in this KB, objects under a `Folder` can carry `parent` filled in without repeating that name in `fullyQualifiedName`.
- Direct evidence: in a `Procedure` under a `Folder`, the observed pattern was `fullyQualifiedName="ObjectName"` with `parent="FolderName"`.
- Direct evidence: in a `WebPanel` under a `Folder`, the same pattern held — the folder organizes the object via `parent` but does not qualify `fullyQualifiedName`.
- Direct evidence: in objects under a `Module`, `fullyQualifiedName` can appear qualified by the module.
- Direct evidence: there is also a case of an object under a `Folder` inside a `Module`; in that profile, the module qualification stays in `fullyQualifiedName` while the folder still only appears in `parent`.
- Strong inference: in this trail, treat `Folder` first as an organizational container; do not automatically promote it to a namespace prefix in `fullyQualifiedName`.
- Strong inference: correctly telling `Folder` apart from `Module` requires reading `fullyQualifiedName`, `name`, `parent`, `parentGuid`, `parentType`, and `moduleGuid` together — not a text heuristic on the container's name.

## Cross-object reference patterns

- Direct evidence: in `WebPanel\MODExemploAMenu.xml`, the code references other objects by name, such as `wpEntradaMODExemploA`, `WWEntradaMODExemploA`, `WWItemMODExemploA`, `wpEscolhaItemMODExemploA`.
- Direct evidence: in the one real `API` case observed in this KB, represented here by the sanitized alias `APIExemploIntegracaoA.xml`, calls appear to procedures such as `PRCExemploA`, `procSdtSampleTaxBasicDataSelectionByParameters`, `PRCExemploB`.
- Strong inference: object names in the corpus are not just labels — they also show up as explicit coupling points between artifacts.

## Operational rule: qualify by type when referencing objects

- Operational rule: when referencing any GeneXus object in analysis, operation, or agent-to-agent communication, always qualify it with type and name together — never the name alone.
- Operational rule: the type determines the repository's physical folder (`Procedure\`, `Transaction\`, `WebPanel\`, `Attribute\`, etc.) and is required to locate the file in the corpus unambiguously.
- Operational rule: the same name can exist simultaneously under different types in the same KB; a name match proves neither uniqueness nor object identity.
- Operational rule: before any operation on an object (search, read, sync check, manifest reference), explicitly confirm the folder and type where the file actually exists in the repository. Before any lookup or search against the official KB workspace corpus or its XML, first obtain `GATE_OK` through the mandatory compatibility/freshness gate in the **find** workflow; this applies to object lookup and corpus searches as well as index queries. Type-and-name qualification does not bypass that gate. The gate does not apply to structural reading of a separately supplied isolated XML that is not being used as a search of, or lookup against, the official corpus.
- Operational rule: never infer an object's type, folder, or identity from its name alone, from conversation context, or by analogy with other artifacts.

## Use these patterns with caution

- Strong inference: for documentation and analysis, it is valid to record these patterns as KB recurrences.
- Hypothesis: these recurrences are not a structural guarantee for any other use of the object's name or shape. The source's tentative suggestion that they could guide new-object creation pending validation with the team or the KB IDE is deliberately omitted from this read-side target; it is not a retained or endorsed convention.
