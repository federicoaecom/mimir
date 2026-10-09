# Translation policy

- **Related:** [glossary](glossary.md), [ADR 0003: Language](../adr/0003-language.md)

English is the canonical language of Mimir Lite. This page states how translations are kept.

## What is translated

- Root and human documentation (`README`, `CONTRIBUTING`, `SECURITY`, the guides under `docs/`) has an English canonical file and a Spanish copy next to it, named `<name>.es.md`.
- The skill payload (`skills/*/SKILL.md`, `workflows/`, `references/`), code, comments, messages, and machine-readable tokens are English only.
- ADRs and the license text are English only.

## Rules

1. **Same change.** A change to an English file updates its `.es.md` copy in the same change, so the two say the same thing. A Spanish copy is a faithful rendering of the English file: same rules, same constraints, same order, nothing added and nothing dropped.
2. **Glossary first.** Use the term mappings in [glossary.md](glossary.md). Before a new term appears translated anywhere, add it to the glossary so every file reuses the same mapping.
3. **GeneXus names stay.** GeneXus object types and API names (Transaction, Web Panel, Procedure, SDT, Data Provider, …) are never translated. Neither are script, file, parameter, and folder names, environment variables, status values, or reason codes.
4. **Register.** Spanish copies use a neutral, professional register.
5. **Review.** A reviewer checks the Spanish copy's meaning against the English file, then its register.

## Checks

`tools/Test-CodeLanguage.ps1` flags pt-BR words in the comments and string literals of `.ps1`/`.py` files, so new code stays English. Spanish `.es.md` files are the intended translations and are not checked by it.
