# Discarded Ideas and Exclusions

This page records ideas that should not be mistaken for Mimir Lite work, with the reason not to reintroduce each one. Reopening any of them needs an explicit decision and new evidence.

## Product exclusions

These are scope decisions (see [ADR 0001](../adr/0001-read-only-scope-and-non-goals.md)), not open design questions.

| Exclusion | Decision and rationale |
|---|---|
| Generate, clone, or package GeneXus objects | Outside the product's read-side purpose; a reader, index, and documentation skill does not become a writer or package producer. See [README — Out of scope](../../README.md#out-of-scope). |
| Build or import XPZ into a KB; MSBuild build/specify/generate | Not part of Mimir Lite. The product reads exported XPZ/XML; it does not apply packages or operate the GeneXus build pipeline. |
| Unattended processing | Work is human-requested; there is no daemon or background processing of a KB. |

## Out of scope

The following approaches fall under the exclusions above and are not tracked individually:

- **KB-specific pre-push automation.** Processed KB output is local work; Mimir Lite does not push it.
- **Command-approval hooks or daemons for agent tools** (for example a Claude Code `PreToolUse` hook), whether they deny or auto-allow commands. A blocking hook does not reduce authorization prompts, can reject valid user-maintained commands, and is machine-local. The open alternative is the backlog's "Agent permission friendliness" item.
- **Build- and packaging-side helpers:** `BulkCopyKnowledgeBase` backups (its BCP output needs GeneXus Server to restore; copying the KB folder or a SQL backup is simpler), an MSBuild wrapper around `UpdateWorkingModel` (the IDE already exposes it), a mandatory `SpecifyGenerate` before every `BuildAll` (`SpecifyAll` can trigger an unwanted database reorganization), and a single runner for every packaging check.

## Read-side discards

These are kept only as rationale against reintroducing a specific approach. They do not prohibit unrelated, newly evidenced read-side work.

| Discarded approach | Why it was rejected |
|---|---|
| Generic accent-loss gate over KB object payloads | It requires KB-specific vocabulary and would create false positives; this is distinct from checks on this repository's own documentation. |
| Dedicated callers query ("who calls X?", "which call sites still use the old object?") | Already covered by the existing `who-uses` query (with `what-uses`, `impact-basic`, `functional-trace-basic`); callers of an old object are `who-uses` on its name. Comparing callers across KB snapshots over time is not covered and would need a versioned index; reopen only for a concrete case that requires it. |
| Migration query (Source → Target) | The data returned is exactly `who-uses Source`; the pair only labels the user's intent. The structural angle lives on as the backlog's "Call-site fingerprints" item. Not to be reopened in its original form. |
| Functional-family query ("e-mail composition objects", "sending bridges") as its own capability | Same question class and infrastructure as the backlog's "Semantic discovery" item (natural-language intent over the XML corpus), with the same limit: it does not replace reading the XML. It enters that item's scope if it is ever implemented. |

## Boundary

The [backlog](backlog.md) lists the open read-side and process ideas separately. Nothing on this page is pending work, and an entry in the backlog does not override the exclusions above.
