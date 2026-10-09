# ADR 0002: Skill packaging and transaction attributes

- **Status:** Accepted
- **Date:** 2026-10-05

## Context

The KB-reading workflows (setup, sync, find, read, docs, install) share references and script engines. Delegation to another LLM serves a different purpose and depends on optional external CLIs (opencode, Codex, Claude Code, GitHub Copilot CLI, Gemini CLI, Antigravity CLI) that many users do not have. Separately, classifying a Transaction's attributes as stored or derived helps a reader understand a data model, but the same analysis could be mistaken for permission to change the model.

## Decision

Package the KB-reading workflows as one core skill, `mimir-lite`, with verb-named workflows. Package delegation, second opinions, and multi-model peer review as a separate, optional skill, `mimir-delegate`.

Keep transaction attribute classification and its index queries as read-only analysis: stored versus derived attributes, including formula and foreign-key inference. The classification describes the exported model; it never authorizes modifying or generating GeneXus objects.

## Consequences

- `mimir-lite` is the single entry point for reading a KB; users install one skill rather than several.
- Users who do not need delegation need not install `mimir-delegate` or any external LLM CLI.
- Each skill is self-contained under `skills/`: its runtime payload does not depend on files outside its own directory.
- Attribute classification appears in the read and find workflows as structural evidence, with the same confidence levels as any other functional conclusion.

## References

- [`skills/mimir-lite/SKILL.md`](../../skills/mimir-lite/SKILL.md)
- [`skills/mimir-delegate/SKILL.md`](../../skills/mimir-delegate/SKILL.md)
- [ADR 0001: Read-only scope and non-goals](0001-read-only-scope-and-non-goals.md)
