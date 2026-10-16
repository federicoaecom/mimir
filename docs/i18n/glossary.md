# Glossary — English ↔ Spanish

- **Related:** [translation policy](README.md)

Term mappings used across the documentation. Add a term here before translating it anywhere else, so every file reuses the same mapping. GeneXus object types and API names (Transaction, Web Panel, Procedure, SDT, DataView, WorkWithForWeb, BC methods, etc.) are never translated — they stay exactly as GeneXus names them.

## KB and corpus

| English | Spanish | Notes |
|---|---|---|
| KB workspace | espacio de trabajo de KB | The folder tree next to (not inside) the native KB, holding XPZ input (`IdeXpzExports`), the XML corpus (`KbObjectsXml`), the derived index (`KbIntelligence`), and local wrappers. |
| native KB folder | carpeta nativa de la KB | The real GeneXus IDE-managed KB folder; read-only for agents. |
| corpus | corpus | Short for the XML corpus when the context is clear. |
| XML corpus | corpus XML | `KbObjectsXml`: the official, read-only-for-agents snapshot of materialized object XML; the normative source. |
| official snapshot | instantánea oficial | The XML corpus as the single read-only source of truth for agents. |
| index / KB Intelligence index | índice | Keep `KbIntelligence` as the literal folder/script/product name; say "index" in prose. |
| derived index | índice derivado | The SQLite index built from the XML corpus; never a substitute for it. |
| initial load | carga inicial | First-time materialization of a KB into the KB workspace. |
| materialization | materialización | Writing XPZ content into individual object XML files in the corpus. |
| full check / full verification | verificación completa | Comparing a complete KB export against the corpus without rewriting it. |
| full KB export / full export | exportación completa de la KB / exportación completa | An XPZ exported from the GeneXus IDE with every object of the KB; required for the first sync. |
| partial export / delta export | exportación parcial / exportación delta | An XPZ with only some objects (usually the recently changed ones); fine for daily updates, never for the first sync. |
| text export (`.xpw`) | exportación de texto (`.xpw`) | A GeneXus 7.0-and-earlier export written as `.xpw` text (`:Tag` blocks); Mimir Lite translates it into the legacy export format. |
| legacy export | exportación heredada | A GeneXus 9 `ExportFile` export: objects appear by element name, with no type GUID. |
| public sample | ejemplo público | A sample KB export published by GeneXus (training courses, wiki); used to test versions. |
| export header | cabecera de exportación | The `KMW` block of an XPZ (major, minor, build) that identifies the GeneXus generation. |
| upgrade | upgrade | A GeneXus release within a version (e.g. GeneXus 18 upgrade 13); not translated. |
| envelope | envoltorio | The outer XML wrapper of an object (`<Object>`/`<Attribute>`, legacy `<GxLegacyPayload>`). |
| Pattern | Pattern | The GeneXus Pattern feature (e.g. Work With, WorkWithForWeb); "pattern-generated" describes its output. |
| pattern instance | instancia de Pattern | An object that applies a Pattern to a base object (for example a `WorkWithForWeb` instance of a Transaction); the objects it generates are its output. "Pattern" keeps its capital, as in the row above. |
| order (pattern instance) | orden | A sort order defined in a pattern instance, for example `<orders>` in a `WorkWithForWeb` grid. |
| view (pattern instance) | vista | The view part of a pattern instance (`<view>` in a `WorkWithForWeb`), with its tabs and fixed data. |
| tab (pattern instance) | pestaña | A tab of a pattern instance view (`<tab>` in a `WorkWithForWeb`); a tab condition is its `condition` attribute (condición de pestaña). |
| caption (pattern instance) | título | The `caption` expression of a pattern instance view or action, shown to the user. |
| filter condition | condición de filtro | A `<condition value="...">` expression of a pattern instance filter (selection or Grid tab). |
| attribute read (code) | lectura (de atributo) | An attribute named in GeneXus code (`code_references_attribute`, read role); an assignment is reported as a read unless its target is unambiguous (write role). |
| write role | rol de escritura | The role of a code use that assigns an attribute where the target is unambiguous: `Attribute = expression` inside `for each`/`new` blocks, a Transaction assignment rule, the attributes a Transaction `Default`, `Equal`, or `Serial` rule assigns, or an item of a Transaction-output DataProvider. |
| Business Component member | miembro de Business Component | An attribute reached through a Business Component variable (`&bc.Attribute`); "Business Component" is not translated. |
| writability | capacidad de escritura | Whether a Transaction attribute is physically stored (`own-physical`, `extended-fk-key`, etc.); a read-only classification. |

## Reading and evidence

| English | Spanish | Notes |
|---|---|---|
| triage | triaje | Initial, index-based narrowing of which XML files to open. |
| trail / path | ruta | The sequence of steps or evidence a workflow follows. |
| escalate / escalation | escalar / escalación | Moving from a lighter-weight source (index, template) to a heavier one (official XML) when evidence requires it. |
| disambiguation | desambiguación | Resolving more than one plausible candidate before acting. |
| caller | invocador | The object or skill invoking another. |
| sanitized template | plantilla sanitizada | A privacy-scrubbed structural example used as reference material. |
| ready-to-use template | plantilla lista para usar | A template block explicitly marked as complete, as opposed to a descriptive/classification-only block; a literal marker in the family/template references. |
| part type matrix | matriz de tipos de Part | The table of which Part types each object type carries. |
| risk map | mapa de riesgo | The relative structural-risk table per object type. |
| Direct evidence | Evidencia directa | Highest confidence level. Keep the English literal when it is used as a label. |
| Additional XML reading | Lectura adicional de XML | Confidence level meaning the conclusion needs more XML read before it holds. Keep the English literal when it is used as a label. |
| Strong inference | Inferencia fuerte | Middle confidence level. Keep the English literal when it is used as a label. |
| Hypothesis | Hipótesis | Lowest confidence level. Keep the English literal when it is used as a label. |

## Workflow and tooling

| English | Spanish | Notes |
|---|---|---|
| local wrapper | wrapper local | The workspace-specific `.ps1` script that calls a shared engine; "wrapper" stays untranslated since it is also a script-naming convention. |
| shared engine | motor compartido | The reusable script/module a local wrapper delegates to. |
| routine | rutina | A documented operational procedure. |
| workstream | frente de trabajo | A scoped, named unit of work (e.g. a subfolder `ShortName_GUID_YYYYMMDD`). |
| gate | compuerta | A mandatory automated precondition script; keep literal script names (`Test-*Gate.ps1`) unchanged. |
| check | verificación | An automated or manual verification step. |
| block | bloqueo | A hard stop raised by a gate or check; keep the literal `BLOCK:`/`GATE_OK` tokens unchanged. |
| blocked | bloqueado | A status value; keep the literal token unchanged in code and output. |
| error | error | A status value; keep the literal token unchanged in code and output. |
| global trigger | disparador global | The precondition path invoked automatically before normal KB tasks. |
| stale / staleness | desactualizado / desactualización | An artifact (index, wrapper, metadata) that has fallen behind its source of truth. |
| skill | skill (feminine: la skill, las skills) | An agent skill (a folder with a `SKILL.md`); stays untranslated and always takes the feminine gender, with matching adjectives ("la skill opcional", "las skills registradas"). |
| skills folder / skills directory | carpeta de skills / directorio de skills | The folder an agent tool scans for `SKILL.md` subfolders (for example `~/.agents/skills`); "skill" stays untranslated. |
| scaffolder | scaffolder | `New-MimirKbWorkspace.ps1`, which creates a KB workspace from the setup examples; kept in English as a technical term. |
| support / supported | soporte / soportado | What the project runs on and with which confidence (README section "Support"). |
| tested / audited / expected to work | probado / auditado / se espera que funcione | Support levels: run by the maintainer; registration checked by the install workflow but not reported as tested; reads a standard skills folder but untested and not audited. |
| tested (CI) | probado (CI) | Platform support level: CI runs the full test suite and checks on that platform (Linux). |
| best effort | mejor esfuerzo | Platform support level: same code paths as a tested platform, but nothing runs there (macOS). |
| not supported yet | todavía sin soporte | A platform with known gaps; no platform has this level today. |
| fake CLI | CLI simulada | A test stand-in for an external CLI (`tests/fixtures/FakeCliSupport.ps1`); never a real backend. |
| symbolic link | enlace simbólico | A symlink: on Windows `New-Item -ItemType SymbolicLink`, which needs Developer Mode or an elevated shell; on Linux and macOS `ln -s`, with no special rights. |
| junction / directory junction | junction / junction de directorio | A Windows directory junction (`New-Item -ItemType Junction`); kept in English, needs no special rights. |
| agent session | sesión de agente | One run of an agent tool; tools load skills when a session starts. |
| command timeout | tiempo límite del comando | The maximum time an agent tool lets one command run before stopping it. |

## Review and delegation

| English | Spanish | Notes |
|---|---|---|
| peer review | revisión por pares | The reserved operational term for a real multi-model panel review (see `docs/process/15-peer-review.md`). |
| second opinion | segunda opinión | A single reviewer's opinion; never labeled as a peer review. |
| primary reviewer | revisor principal | A reviewer named in the preferred-reviewer list, as opposed to a fallback. |
| pre-push review | revisión pre-push | The routine that checks a state before push; keep the compound `pre-push` literal. |
| reinforced pre-push review | revisión pre-push reforzada | Optional multi-model panel application of the pre-push routine. |
| dossier | dossier | The raw-git plus mechanical-diagnostic packet given to `semantic-only` reviewers. |
| manuscript | manuscrito | The plan/design text submitted to reviewers; it is review input, not truth. |
| receipt | recibo | The mandatory auditable summary required before using the peer-review label. |
| ledger | registro | Append-only or auditable record of manuscript versions, prompts, reviewer states and closeout evidence. |
| resubmission | resubmisión | Sending a revised manuscript back to the panel after author changes; keep script tokens such as `pendingResubmission` unchanged. |
| unknown backend | backend desconocido | A dispatch backend the delegation skill does not recognize; reported as an error. |

## Placeholders

Placeholders inside inline code — angle-bracket tokens standing in for a name the reader must supply, such as `<tool>` in `preferred-reviewers.<tool>.json` — may be translated along with the surrounding prose (`<herramienta>`). Literal GeneXus identifiers (the actual `Name`, `type`, `guid`, property values, and any real object or attribute name used as-is) are never translated.

## Adding a term

1. Add a row when a term recurs in more than one file; a one-off word can be translated in place.
2. Pick the Spanish term that best matches the concept, not a literal word-for-word rendering.
3. GeneXus object types, method names, and literal script, file, parameter, and folder names are never translated and do not belong in this table.
