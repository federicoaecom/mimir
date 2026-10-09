# ADR 0003: Language

- **Status:** Accepted
- **Date:** 2026-10-05

## Context

Mimir Lite is read by agents and by people. Agents need one consistent language in the skill payload and in every machine-readable value they match on. The people who use and maintain the project read English and Spanish.

## Decision

- English is the canonical language for code identifiers, comments, log and error messages, commits, pull requests, and issues.
- The skill payload (`skills/*/SKILL.md`, `workflows/`, `references/`) is English only.
- Root and human documentation is written in English, with a Spanish translation kept next to it as `<name>.es.md`. ADRs and the license text are English only.
- Machine-readable tokens are English: status values, reason codes, report headers and keys, folder names in the KB workspace, `Kind` values, and environment variable names.
- Translations follow the [glossary](../i18n/glossary.md). GeneXus object types and API names (Transaction, Web Panel, Procedure, SDT, …) are never translated.

## Consequences

- A Spanish copy changes in the same change as its English file, so the two never drift.
- Scripts, wrapper templates, workflows, and tests match on English literals only; there is no list of foreign-language tokens to preserve.
- `tools/Test-CodeLanguage.ps1` flags pt-BR words in code comments and string literals, so new code stays English.

## References

- [Translation policy](../i18n/README.md)
- [Glossary](../i18n/glossary.md)
- [AGENTS.md, language policy](../../AGENTS.md)
