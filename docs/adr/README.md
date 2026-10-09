# Architecture Decision Records

This directory records the decisions that shape Mimir Lite. Each record states its context, the decision, and its consequences.

| ADR | Decision |
|---|---|
| [0001 — Read-only scope and non-goals](0001-read-only-scope-and-non-goals.md) | Read and understand a KB from its XPZ/XML exports; generating, packaging, importing, building, and deploying are out of scope. |
| [0002 — Skill packaging and transaction attributes](0002-skill-packaging-and-transaction-attributes.md) | Core `mimir-lite` skill plus optional `mimir-delegate` skill; transaction attribute classification stays read-only. |
| [0003 — Language](0003-language.md) | English canonical; Spanish `.es.md` translations for root and human docs; English-only skill payload and machine-readable tokens. |
| [0004 — License](0004-license.md) | MIT License, copyright "The Mimir Lite authors", authors listed in `AUTHORS.md`. |

New records use the next free number and the `NNNN-kebab-title.md` file name. ADRs are written in English only (see [ADR 0003](0003-language.md)).
