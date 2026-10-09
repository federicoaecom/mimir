# ADR 0001: Read-only scope and non-goals

- **Status:** Accepted
- **Date:** 2026-10-05

## Context

GeneXus knowledge bases (KBs) can be exported from the GeneXus IDE as XPZ packages. Those exports hold the full XML of every object, which makes them a reliable source for understanding a KB: what an object is, what it uses, what uses it, and how a change would ripple through the model. Tools that also write back to a KB (generating objects, packaging them, importing them, or building the KB) carry far more risk, depend on the GeneXus IDE and MSBuild toolchain, and need evidence an agent working on exports does not have.

## Decision

Mimir Lite reads and understands a GeneXus KB from its XPZ/XML exports, on human request. Its capabilities are:

- synchronize XPZ exports into the XML corpus (`KbObjectsXml`);
- build and query a derived index over that corpus (who uses an object, what it uses, impact);
- read and structurally classify a single object's XML;
- document the corpus in Markdown;
- set up and audit the KB workspace next to the KB, and install the skills into agent tools.

The XML corpus is the normative source; the derived index is a shortcut to it, never a replacement. Toward the KB itself the product is read-only: the native KB folder managed by the GeneXus IDE is never written.

The following are out of scope:

- generating, cloning, or packaging GeneXus objects;
- building XPZ packages or importing them into a KB;
- MSBuild-based builds;
- deployment, hosting, or packaging of a KB's generated application; the setup workflow prepares the KB workspace only and does not cover these;
- unattended or background processing of a KB.

## Consequences

- No workflow reports an import, build, packaging, or deployment result, because none of them performs those actions or has evidence about them.
- The setup audit checks only what the read-side workflows need (workspace structure, corpus materialization, index freshness, KB metadata); it has no deployment or packaging dimensions.
- A proposal that adds any out-of-scope capability needs an explicit decision recorded as a new ADR before any change lands.

## References

- [README](../../README.md)
- [`skills/mimir-lite/SKILL.md`](../../skills/mimir-lite/SKILL.md), section "Out of scope"
