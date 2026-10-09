# 00 - Index of the GeneXus XPZ/XML knowledge base

## Document role
Index

## Predominant confidence level
High

## Depends on
`09-script-inventory.md`

## Used by
The whole reference set

## Purpose
Entry point for this reference set: reading order, methodological limits, and absolute rules for any agent using this documentation.

## Purpose of this reference set

Operational and empirical knowledge for reading GeneXus XML and understanding structures found in GeneXus 18 `XPZ` exports. It supports structural analysis and cautious interpretation; it does not authorize object generation, cloning, packaging, import, or builds.

## Scope

- Reading internal XML extracted from `XPZ`
- Structural analysis of GeneXus objects
- Catalogs of observed `Object/@type` and `Part/@type`
- Cautious evaluation of structural risk and the limits of available evidence
- The XPZ envelope observed in a real KB export

## Layers of this reference set

### Conceptual

- `00-index.md`
- `06-object-patterns-and-naming.md`
- `09-script-inventory.md`

### Empirical

- `01-empirical-base-overview.md`
- `01a-catalog-and-empirical-patterns.md`
- `01b-part-type-matrix-by-type.md`
- `01c-stable-vs-variable-fields.md`
- `01d-structural-diffs-by-type.md`
- `01e-sanitized-templates-core.md`
- `01f-sanitized-templates-data-and-design.md`
- `01g-sanitized-templates-components-and-physical.md`
- `01h-sanitized-templates-metadata-and-artifacts.md`
- `04-webpanel-families-and-templates.md`
- `04b-ucw-gxcontroltype-reference.md`
- `05-transaction-families-and-templates.md`
- `05b-procedure-and-report-families-and-templates.md`

### Operational

- `01k-legacy-element-registry.md`
- `02-operational-rules.md`
- `03-risk-and-decision-by-type.md`
- `08-agent-guide.md`

## Recommended reading order

1. `00-index.md`
2. `01-empirical-base-overview.md`
3. Open whichever `01a`-`01h` empirical child is most relevant
4. `02-operational-rules.md`
5. `03-risk-and-decision-by-type.md`
6. `04-webpanel-families-and-templates.md`
7. `05-transaction-families-and-templates.md`
8. `05b-procedure-and-report-families-and-templates.md`
9. `08-agent-guide.md`
10. `09-script-inventory.md`

`06-object-patterns-and-naming.md`: supplementary reading — read it when the doubt is about object naming, type prefixes, or `Folder` vs `Module` behavior inside `fullyQualifiedName`.

## Absolute rules for any agent

- Never invent a `Part type`.
- Never assume an import or build succeeded without external verification.
- Keep structural conclusions within the available evidence and stated confidence level.
- Never promote `Hypothesis` to `Strong inference`.
- Never promote `Strong inference` to `Direct evidence`.
- `Strong inference — evidence from an inspected external KB` is a valid, traceable level; always state the source KB, its version, and the reference object. Full taxonomy in `02-operational-rules.md`.
- For small or new KBs with no comparable local XML, treat the type's sample as small (see `03-risk-and-decision-by-type.md`) and answer with the corresponding extra caution — Mimir Lite does not generate a replacement object from an external source.

## Operational flow summary

1. For work in a KB workspace, use the **setup** workflow first when its structure is not yet validated; before any read of an official KB corpus object XML—including an already-known path—or any lookup/search/query against the corpus or derived index, clear the mandatory **find** gate with `GATE_OK`.
2. Identify the object's type and, for an already supplied isolated XML, classify its structure using the **read** workflow.
3. Check risk and indications of required elements in `03-risk-and-decision-by-type.md`.
4. Check applicable operational and runtime rules in `02-operational-rules.md`.
5. Keep conclusions within the XML evidence and stated confidence level. The read-side workflows do not generate, clone, package, import, or build objects.

## About the observed XPZ

- Direct evidence: in the real export inspected in this trail, the `.xpz` file held a single main XML with root `<ExportFile>`.
- Direct evidence: in the observed full/special export, the top-level blocks were `KMW`, `Source`, a special KB block, `Objects`, `Attributes`, and `Dependencies`.
- Direct evidence: in the most frequent normal object-export format, that special KB block is exceptional, not a mandatory part of the container.
- Direct evidence: the `KMW` block carried `MajorVersion`, `MinorVersion`, and `Build`.
- The original empirical notes' generation-oriented inference about starting from `<Object>` and then the observed XPZ envelope is historical context, not a current Mimir Lite instruction or capability.

## Current limits of this reference set

- Direct evidence: this reference set derives mainly from XML extracted from `XPZ`. The original empirical notes also recorded tests of importing externally assembled XPZs; those historical tests do not describe a current Mimir Lite capability.
- Hypothesis: some patterns may repeat across other GeneXus 18 KBs, but that still needs external validation.
- Operational rule: this reference set supports reading and cautious interpretation of exported XML; it does not define or verify XPZ import contracts, rejections, packaging, generation, or build behavior. Correct use of GeneXus rules, triggers, and language belongs to product documentation and dedicated language guidance; this reference set does not attempt to catalog every possible incorrect use of the language.

## Dependencies between documents

- `01` and `02` ground the conceptual reading.
- `04` and `05` back the more detailed structural families.
- `06` and `09` help with naming, traceability, and separate historical context.
- `08` explains how an agent should consume this reference set.

## Referral rule

- Direct evidence: detailed agent-consumption guidance is centralized in `08-agent-guide.md`.
- Strong inference: this `00` document should stay a short, stable entry point and avoid duplicating operational rules that are already maintained and kept current in `08`.

- The original empirical notes record historical import and rename-test outcomes (including an `Import File Load` error and an `Object/@guid` observation). These are not current Mimir Lite capabilities or verified read-side contracts; do not use them to guide an import, package, or object edit.

## Minimal additional rules

- When reading a large `Source` block with relevant closures or nesting, re-read the saved excerpt and preserve structural comments that aid interpretation; do not remove useful visual scaffolding.
- These read-side rules do not prescribe packaging, cloning, import validation, or final materialization.

## Evidence boundaries

- Before any read of an official KB corpus object XML—including a read using an already-known path—or lookup, search, or substantive query against the official corpus or derived index, follow the **find** workflow and obtain `GATE_OK`. Do not open official object XML before the gate clears.
- A separately supplied isolated XML may be structurally read with the **read** workflow; it is not an official corpus read and does not require the **find** gate.
- For structural claims, raw XML is the normative source. In this reference set, its Markdown, incomplete or merely illustrative sanitized templates, and free reconstructions from tables, frequencies, or descriptions are not source evidence. Complete sanitized examples can aid reading but cannot replace the underlying XML for structural claims. The derived index may guide triage; it does not replace the official XML when the question depends on its content.
- Do not infer import, build, runtime, or packaging success from structural inspection.
