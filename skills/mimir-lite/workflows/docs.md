# Docs workflow

Generates, recomposes, and updates Markdown documentation from the repository's XML corpus and sanitized templates. Uses the shipped documentation engines, or an explicitly supplied and validated KB-local wrapper, without private absolute paths.

---

## PURPOSE

Identify the repository root from context, locate the shipped shared documentation scripts at `../scripts/` relative to this workflow, resolve input/output paths from the current scenario, and delegate generation or updates to the appropriate script. This is an analytical/read-side workflow: it creates or updates Markdown only; it does not generate or clone GeneXus objects, build packages, or import them. Avoid manually editing long `.md` files when an automated flow exists. If there is no suitable documentation script for the kind of contract, script, or example to record, a small manual Markdown edit is acceptable; the edit must be local, anchored to a section, never a broad rewrite of a long `.md`, and followed by re-reading the file's start, the changed section, and the following transition. When documenting the XML corpus, distinguish the official snapshot from a local working artifact.

If the documentation depends on the KB workspace and that structure is not yet mounted or validated, stop and use the **setup** workflow before generating or updating documentation.

## PATH RESOLUTION

- Resolve every `../references/<file>.md` reference relative to the directory of this file (`skills/mimir-lite/workflows/`), not relative to the current working directory.
- Resolve the shipped shared documentation scripts under `../scripts/` relative to this workflow (`skills/mimir-lite/scripts/`), not under `<repo_root>\scripts\`.
- Use a KB-local wrapper only when the user explicitly supplies its path and the wrapper has been validated; do not assume a default wrapper exists in the KB workspace's `scripts/`.

---

## TRIGGERS

Use this workflow for:
- The user wants to generate a documentary inventory of the KB from the XML corpus
- The user wants to produce analytical documentation or matrices from the XMLs
- The user wants to recompose a Markdown section with complete sanitized templates
- The user wants to update documentation from a KB's real examples
- The user wants to maintain the documentation base that feeds humans and other workflows
- The user wants to generate documentation from validated KB Intelligence source data, preserving the distinction between direct evidence and inference

Do NOT use this workflow for:
- Syncing XMLs from an XPZ exported by the IDE (use **sync**)
- Analyzing a single XML with no intent to update documentation (use **read**)
- Generating, cloning, or packaging GeneXus objects; building or importing XPZ packages — out of scope for this skill
- Treating the KB Intelligence SQLite as a normative source in place of the official XMLs
- Locating objects in the KB corpus by name or type (use **find** first when a `KbIntelligence` index is available)

---

## MODES

| Mode | When to use |
|---|---|
| `inventory` | Generate a raw inventory of the XML corpus |
| `advanced-docs` | Produce analytical documentation, matrices, and structural catalogs |
| `update-section` | Recreate or update a Markdown section with complete XML examples |

KB Intelligence can feed documentation at a later stage, but the SQLite index is a derived artifact. When using it, label the source as a derived technical index and preserve links to the official XML and evidence where possible.

The shipped `advanced-docs` engine writes exactly five analytical reports (numbered 10, 11, 12, 14, and 16). It creates the output root if needed, rewrites those five reports in place, and never clears or edits other files in an existing output root.

---

## EXPECTED SCRIPTS

The shipped shared scripts are under `../scripts/` relative to this workflow (`skills/mimir-lite/scripts/`):

| Script | Role |
|---|---|
| `generate-kb-inventory.ps1` | Generates a raw KB inventory from the XML corpus |
| `generate-kb-advanced-docs.ps1` | Generates analytical documentation from the XML corpus |
| `Update-MimirDocSection.ps1` | Recomposes a Markdown section with XML examples and editorial notes |

A KB-local wrapper is a compatibility path, not the default interface; use it only when its path is explicitly supplied and the wrapper has been validated.

---

## LOCATING THE REPOSITORY

1. Use the current working directory as the starting point.
2. If needed, walk up to the Git root (`git rev-parse --show-toplevel`).
3. Resolve `../scripts/` relative to this workflow file; this points to `skills/mimir-lite/scripts/`, not `<repo_root>\scripts\`.
4. Confirm the expected shared documentation scripts exist. Use a KB-local wrapper only if its path was explicitly supplied and the wrapper was validated.
5. If the required shared script is unavailable and no explicitly supplied, validated KB-local wrapper can serve the operation, report the problem before attempting a manual alternative.

---

## COMMON PARAMETERS

### Inventory generation
- `-SourceRoot` *(required)* — the XML corpus root
- `-OutputPath` *(required)* — the output Markdown file

### Analytical generation
- `-SourceRoot` *(required)* — the XML corpus root
- `-OutputRoot` *(required)* — the folder where the Markdown files will be generated

### Section update
- `-TargetMarkdown` *(required)* — the Markdown file to update
- `-SectionTitle` *(required)* — the exact title of the section to recompose
- `-IntroLines` *(optional)* — the section's introductory lines
- `-XmlExamplePaths` *(required)* — the list of XMLs to embed
- `-ExampleTitles` *(optional)* — a title per example
- `-ExampleNotes` *(optional)* — a note per example

---

## WORKFLOW

1. Identify whether the request is `inventory`, `advanced-docs`, or `update-section`.
2. If the KB workspace is not yet mounted, validated, or mapped for this repository → **ABORT** and use the **setup** workflow.
   - When a `KbIntelligence` index is available and the task requires selecting or locating corpus objects to document, invoke the **find** workflow before opening XMLs, to guide the selection.
3. Resolve the repository root from context.
4. Resolve the shared scripts at `../scripts/` relative to this workflow and confirm the right script exists; use a KB-local wrapper only when explicitly supplied and validated.
5. Confirm or derive the input/output paths.
6. Run the script with explicit parameters, in the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`).
7. When using KB Intelligence-derived validation cases, first identify the case's format before choosing the executor:
   - cases with `source`, `target`, and `expected_rule` → validate in the generator/indexer with `Build-KbIntelligenceIndex.ps1 -ValidationCasesPath`
   - cases with `query` → validate in the query executor with `Test-KbIntelligenceQueries.ps1 -ValidationCasesPath`
8. When the documentation generates or preserves line links to GeneXus XML, label the cited fragment's role: `effective Source`, `Rules/parm`, `XML metadata`, `call in caller`, or `signature in callee`.
9. If the documentation claims object A calls object B, validate that the line link points to A's effective `Source` or an explicit call metadata in A; a `parm(...)` line in B must be described only as the callee's signature.
10. When using KB Intelligence output, state that the immediate source is a derived technical index and that the normative source remains the official XML in `KbObjectsXml`; when citing evidence, preserve the reference to the official XML, the cited fragment's role, and the confidence level.
11. When the documentation is functional in nature, explicitly separate `Direct evidence`, `Additional XML reading`, `Strong inference`, and `Hypothesis`.
12. Re-read the generated or changed file's start, the modified section, and the following transition.
13. Report what was created, updated, or replaced.

---

## CONSTRAINTS

- NEVER assume private absolute paths.
- NEVER generate documentation that depends on the KB workspace while that structure is still undefined or unvalidated.
- NEVER manually edit long `.md` files when a suitable script exists.
- NEVER rewrite a section without correctly identifying the target title.
- NEVER hide that content was generated from sanitized XML or from a real corpus when that is relevant.
- NEVER edit `KbObjectsXml` expecting documentation or packaging to use that version; the corpus is read-only for agents (see `02-operational-rules.md`, anti-pattern "editing the corpus expecting the package to catch it").
- NEVER document a `parm(...)` line from the called object as if it were the call site in the calling object.
- NEVER treat the KB Intelligence SQLite as functional or runtime proof; it is a derived technical index of extracted evidence.
- NEVER pick the KB Intelligence validation executor by phase name alone; the case's format (`expected_rule` vs. `query`) is what defines the compatible executor.
- If the expected script does not exist, report the problem before improvising a broad manual edit.
