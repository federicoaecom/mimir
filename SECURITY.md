See also: [Español](SECURITY.es.md)

# Security Policy

This repository contains documentation, scripts, and methodological examples for reading and understanding a GeneXus Knowledge Base from XPZ/XML exports. Security reports must protect people, customers, real KBs, and private artifacts.

## What counts

Relevant to this policy:

- A vulnerability in a script or workflow (e.g. one that could write outside its documented scope, or that could be tricked into an unsafe action against a KB).
- Accidental exposure of credentials, customer data, or unsanitized real-KB artifacts anywhere in this repository (code, examples, fixtures, or documentation).
- Leaked real GeneXus KB content — names, GUIDs, source code, or structure — in a committed file.
- Instructions that would induce an unsafe change to a KB, database, or XPZ package.
- A gap that lets a critical operational-safety validation return a false pass.

An ordinary bug report, a documentation error with no sensitive impact, or a general improvement suggestion can go through the normal issue/pull-request flow instead of this policy.

## Data sent to external services

Mimir Lite itself makes no network calls. The optional `mimir-delegate` skill can send prompt content, including KB content if the agent includes it, to external LLM CLIs (opencode and the providers it is configured with, Codex, Claude Code, GitHub Copilot CLI, Gemini CLI, Antigravity CLI), and only when a user asks for delegation or a peer review. Its confidentiality gate (`Resolve-LlmDelegateAuthorization.ps1`) decides allow, ask, or deny from the destination's locality and a per-KB policy, but the agent, not the script, judges whether a payload is `public` or `kb-sensitive`. The gate is therefore procedural: it cannot detect sensitive content that the agent labels `public`. Never run delegation on material you are not allowed to disclose to the destination provider. Consent for `kb-sensitive` content is per destination and per invocation, and a sent prompt cannot be recalled.

Locations written outside the repository (full list in [`README.md`](README.md#delegation-and-files-written-outside-the-repository)): `%LOCALAPPDATA%\mimir-delegate` on Windows, `~/.local/share/mimir-delegate` on Linux, or on macOS, typically `~/Library/Application Support/mimir-delegate`, falling back to the Linux location when that folder does not exist (capability manifest, preferred reviewers, circuit-breaker state), job folders in the system temporary folder (`%TEMP%` on Windows) that hold delegated prompts and outputs, the KB workspace that the **setup** workflow creates next to your KB (with an optional Claude Code `.claude/settings.json` holding allow rules), the global instruction files of your agent tools after your confirmation, and, when installing, the skills directories of your agent tools. Report a script that writes anywhere else, or that leaves sensitive prompts behind, through the private channel below.

## How to report

- Do not open a public issue with credentials, sensitive customer names, real KB content, or exploitable steps.
- Report privately through GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**. The report is visible only to the maintainers until they decide how to disclose it. Do this before publishing any sensitive detail.
- Do not send credentials, a real XPZ, or real KB content by any channel without prior agreement on how it will be handled.

## What to include

When possible, include: the problem observed, affected script/skill/document, a minimal reproduction with sanitized data only, and the potential impact. Do not include the real sensitive artifact itself in the initial report — describe it and offer to share it through an agreed private channel if truly needed for triage.
