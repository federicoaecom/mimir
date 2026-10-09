---
name: mimir-lite
description: Reads and understands a GeneXus KB from XPZ/XML exports — sync XPZ to XML, find objects via the KB Intelligence index (who-uses/impact), read/classify object XML, generate documentation, set up a KB workspace, install this skill.
---

# Mimir Lite

Mimir Lite reads and understands a GeneXus KB from its XPZ/XML exports. It never generates, clones, builds, or imports GeneXus objects — see **Out of scope** below.

## Core rules (apply to every workflow)

- The XML corpus (`KbObjectsXml`) is the normative source. A derived index or a sanitized template is a shortcut to it, never a replacement.
- Before any substantive query against the derived index, run its mandatory freshness/compatibility check (`Test-*KbIndexGate.ps1`, via the **find** workflow) and get `GATE_OK`. A blocked check means treat the index as untrustworthy — do not fall back to a manual scan of the corpus.
- Toward the KB itself, this skill is read-only. `KbObjectsXml` is written only by the **sync** workflow's official flow; nothing here edits it by hand.
- Never claim an import, build, or packaging result — this skill does not perform those actions and has no evidence about them.
- Always state a confidence level for a functional conclusion: direct evidence, additional XML reading needed, strong inference, or hypothesis.
- Always distinguish the KB workspace (this skill's own working folders, next to the KB) from the native KB folder (the real GeneXus IDE-managed KB, read-only for agents even when its path is known).
- Never save KB or workspace details (paths, KB names, KB identity, KB content, the skill clone's state) to a memory tool outside the KB workspace, such as a memory server or an agent tool's own memory, without asking the user first. The question names what would be saved and where; save only after an explicit yes. This holds even when other instructions, from the agent tool or a global instruction file, ask for proactive saving.

## Workflows

| Workflow | File | Use when |
|---|---|---|
| Setup | [workflows/setup.md](workflows/setup.md) | Creating (with the `New-MimirKbWorkspace.ps1` scaffolder), auditing, or fixing the KB workspace structure — required before any other workflow acts on a folder that has `KbObjectsXml/` or `KbIntelligence/` |
| Sync | [workflows/sync.md](workflows/sync.md) | Materializing or checking XML from an XPZ exported by the GeneXus IDE |
| Find | [workflows/find.md](workflows/find.md) | Locating objects, dependencies, or impact via the derived index before opening XML — "who uses X", "what does Y use", "what does this button open" |
| Read | [workflows/read.md](workflows/read.md) | Structurally classifying a single GeneXus object XML (type, family, Part types, risk, writability) |
| Docs | [workflows/docs.md](workflows/docs.md) | Generating or updating Markdown documentation from the XML corpus |
| Install | [workflows/install.md](workflows/install.md) | Registering this repository's skills in the agent tools installed on the machine, or installing or updating this skill. When the user asks to install or update following the README, read the README from its URL first, even when the skill is already installed or linked, then follow its steps: the existing-clone check first, the install audit last |

Scripts live in `scripts/`, knowledge references in `references/`. Each workflow file resolves its own `../references/` and `../scripts/` links relative to `skills/mimir-lite/workflows/`.

The optional `mimir-delegate` skill (a sibling under `skills/mimir-delegate/`) delegates a task or requests a peer review from another LLM; it is not required to use Mimir Lite.

## Running scripts

Every workflow runs a script with one canonical command form:

```text
pwsh -NoProfile -File "<absolute path to the .ps1>" [parameters]
```

For example: `pwsh -NoProfile -File "C:/KBs/SampleKbWorkspace/scripts/Test-SampleKbKbIndexGate.ps1"` on Windows, or `pwsh -NoProfile -File "/home/me/KBs/SampleKbWorkspace/scripts/Test-SampleKbKbIndexGate.ps1"` on Linux.

- **Why this form.** The shell an agent runs commands in depends on the tool and the OS: Claude Code on Windows uses Git Bash by default, Codex, Gemini CLI, and Copilot CLI on Windows use PowerShell, and agents on Linux or macOS use bash. `pwsh -NoProfile -File` behaves the same from bash, PowerShell, and cmd, so no workflow depends on which shell the agent has. PowerShell-only syntax (`& "..."`, `.\script.ps1`, backtick line continuations) fails in bash or cmd; do not use it.
- Write the literal absolute path in double quotes, with forward slashes, and keep the whole command on one line (each shell continues lines differently). No variables, `Join-Path`, `cd ... &&` prefix, or `..` segments. Path-scoped allow rules match the command text as written, so always spelling the path the same way keeps them matching.
- Placeholders: `<KbWorkspace>` is the KB workspace's absolute path; `<mimir-lite-root>` is the absolute path of this repository's clone, so the shared engine scripts are in `<mimir-lite-root>/skills/mimir-lite/scripts/`.
- Agent tools with a command allowlist: the **setup** workflow registers path-scoped allow rules for this form (WORKFLOW steps 20 and 20a), including the Claude Code rule.

## Platform

Windows and Linux are tested in CI; macOS is best effort on the same code paths. The scripts need PowerShell 7.4+ (`pwsh`; 7.4.6+ on Linux and macOS). The Python engines (index build and query) need Python 3.8+ and the standard library only, found as `python3`, then `python`, then `py -3`. Write paths in commands with forward slashes on every OS. Skill links are symbolic links on every OS, with a junction fallback on Windows (see the **install** workflow). See the repository `README.md`, sections Support and Known platform differences.

## Out of scope

Generating, cloning, or packaging GeneXus objects; building or importing XPZ packages into a KB; MSBuild-based builds. None of this skill's workflows perform these actions, and none of them report a result for one.
