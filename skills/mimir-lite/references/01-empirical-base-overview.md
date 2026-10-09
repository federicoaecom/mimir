# 01 - Empirical base overview

## Document role
Empirical index

## Predominant confidence level
Medium

## Depends on
`09-script-inventory.md`

## Used by
`02-operational-rules.md`, `03-risk-and-decision-by-type.md`, `08-agent-guide.md`

## Purpose
Short entry point for the `01` series, split into smaller per-purpose files to reduce read cost and improve routing. Sanitized templates in the series are reading aids, not instructions or authorization to generate, clone, package, import, or materialize objects.

## Reason for the split

- Direct evidence: the former single `01-base-empirica-geral` concentrated the structural catalog, the `Part type` matrix, field variability, structural diffs, and the full sanitized templates in one file.
- Strong inference: that monolithic format raised context cost for simple queries and pushed the agent to open a file far larger than needed.
- Editorial rule: the `01` series is now consulted by layer, not as a mandatory single block.

## Map of the `01` series

| File | Main role | Load when |
|---|---|---|
| `01-empirical-base-overview.md` | Master index of the series | First step for a general empirical query |
| `01a-catalog-and-empirical-patterns.md` | Corpus overview, type catalog, patterns and limits | Identifying a type, reading the structural overview, validating empirical scope |
| `01b-part-type-matrix-by-type.md` | `Part type` frequency by type | Confirming the recurring inventory, suspecting structural mandatoriness |
| `01c-stable-vs-variable-fields.md` | Fields that tend to be stable or variable, by type | Deciding what tends to be preserved vs. editable |
| `01d-structural-diffs-by-type.md` | Structural contrasts by type | Comparing observed profiles and structural density |
| `01e-sanitized-templates-core.md` | Core sanitized templates for `Procedure`, `DataProvider`, `Panel`, `API`, `WorkWithForWeb`, mixed package, and `SDT` | Reading representative core-type structures and frequent contracts |
| `01f-sanitized-templates-data-and-design.md` | Sanitized templates for `Domain`, `Theme`, `PackagedModule`, `DesignSystem`, and `ColorPalette` | Declarative-data and design-system cases |
| `01g-sanitized-templates-components-and-physical.md` | Sanitized templates for `ExternalObject`, `UserControl`, `Module`, `SubTypeGroup`, `ThemeClass`, `Image`, and `Table` | Components, the physical layer, and visual/material structure |
| `01h-sanitized-templates-metadata-and-artifacts.md` | Sanitized templates for `ThemeColor`, `Document`, `DataSelector`, `Generator`, `PatternSettings`, `DataStore`, `Dashboard`, `DeploymentUnit`, `Language`, `Folder`, identity/`Source` examples, `Stencil`, and `File` | Metadata, auxiliary artifacts, and structural-identity examples |

> `01k` (legacy element registry) is a **governance** doc, not an empirical template: it shares the `01` prefix but stays outside this empirical map, indexed in the Operational layer of `00-index.md`.

## Recommended reading order

1. Read this index.
2. Open `01a-catalog-and-empirical-patterns.md` when the doubt is still "what exists and what does this type look like".
3. Open `01b-part-type-matrix-by-type.md` when the doubt involves `Part type`.
4. Open `01c-stable-vs-variable-fields.md` when the doubt involves preservation, noise, or editability.
5. Open `01d-structural-diffs-by-type.md` when the doubt involves comparison or structural density.
6. Open only the sanitized-template block that best fits the case's actual type.

## Quick routing by question

- "What is the observed `Object/@type` or catalog?" -> `01a-catalog-and-empirical-patterns.md`
- "Which `Part type`s are recurring for this type?" -> `01b-part-type-matrix-by-type.md`
- "What tends to stay stable and what varies?" -> `01c-stable-vs-variable-fields.md`
- "Which structural profile is closest?" -> `01d-structural-diffs-by-type.md`
- "I need a sanitized example to understand a structure" -> `01e` through `01h`, per the type's family; it is not a source for reconstructing or materializing an object

## Usage rules

- Operational rule: do not open `01e` through `01h` by default when the question can be resolved with `01a` through `01d`.
- Evidence boundary: for structural claims, official object XML is normative; a sanitized example can aid reading but cannot replace it. Before reading any official corpus XML, including at a known path, clear the **find** workflow gate and obtain `GATE_OK`. A separately supplied isolated XML may be structurally read with the **read** workflow without that gate.
- Operational rule: when the answer cites the empirical base, prefer naming the most specific file in the `01` series, not just this index.
- Operational rule: when a new type gets a sanitized template or a relevant methodological cut, fit it into the closest family file instead of re-expanding this index.
- Editorial rule: this file does not replace its children's detailed content; it only organizes the entry point and routing.

## Split traceability

- Direct evidence: this series' content came from the former single block `01-base-empirica-geral`, which also incorporated the material now consolidated into `01b-part-type-matrix-by-type.md`, `01c-stable-vs-variable-fields.md`, and `01d-structural-diffs-by-type.md`.
- Direct evidence: the current split preserves the empirical content but redistributes reading by operational function.
- Editorial rule: old references to `01-base-empirica-geral` remain valid as an entry point, but efficient consumption should descend to the right child file.
