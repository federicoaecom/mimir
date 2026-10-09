# Install workflow

Audits and maintains the global registration of this repository's skills (`mimir-lite`, `mimir-delegate`) across the agent tools installed on the machine, with a post-`git pull` check and an offer to resolve gaps. Codex, Claude Code, Cursor, OpenCode, and Antigravity have built-in support (automatic detection and per-tool rules); any other agent tool that reads `SKILL.md` from a skills directory is covered by the **OTHER TOOLS** section.

This workflow operates on the skills repository itself, not on a GeneXus KB. Run it after a `git pull` on this repository, and on a new user's first environment setup.

---

## PURPOSE

- Inventory every immediate subfolder with a `SKILL.md` under the skills inventory root (`<repo>/skills`) — these are the skills this workflow manages.
- For each tool, check whether its global skills directory exists before trying to register anything.
- Detect which tools are installed on the machine — never assume all of them are present (see **Installation detection**).
- Consider cross-tool compatibility before classifying a skill as missing in Cursor (see **Registration strategy**).
- Before classifying a skill as **missing** in Codex, check absence in **both** USER directories Codex indexes (`~/.codex/skills/` and `~/.agents/skills/`); presence in either counts as available for Codex (see **Skill paths per tool**).
- The raw per-skill `tools[].skills[].status` values are exactly `OK`, `covered_by_compatibility`, `missing`, `broken`, and `skipped_by_choice`. In user-facing prose, describe these as **OK**, **covered by compatibility**, **missing**, **broken**, and **not linked by choice**; report orphaned registrations separately in `orphans[]`, not as a per-skill status.
- Declare what the user chose not to link: pass each such tool with `-SkipTool <name>` (the `tools[].name`, for example `Cursor`) and each such skill with `-SkipSkill <name>` (for example `mimir-delegate` when the user did not want delegation). A link that would be **missing** or **covered by compatibility** there is reported `skipped_by_choice`, which is not a gap, so `overall` is not `REGISTRATION_GAPS` because of a declared choice alone; an existing link keeps its status, so a **broken** one is still a gap. Declare only what the user said; never declare a skip to turn a result into `REGISTRATION_OK`.
- Present a consolidated report per tool before any action.
- Offer to resolve every identified gap — never act silently.
- Wait for explicit user confirmation before creating or removing any skill link.
- On Windows, try a **symlink** as the preferred mechanism; if it fails on permissions, automatically fall back to a **junction** and tell the user which one was used and why.
- On Linux and macOS, create a **symlink** (`ln -s <target> <link>` in bash, or `New-Item -ItemType SymbolicLink` in `pwsh`); it needs no special rights, and there is no junction fallback.
- Never copy files as an alternative to a symlink/junction — a copy silently goes stale after `git pull`.
- Do not install the agent tools themselves (for example Codex, Claude Code, Cursor, OpenCode, Antigravity) — only manage skill registration inside them.
- Do not register skills from other repositories — out of scope.
- Do not change a tool's general configuration outside this workflow's scope.
- Check directory existence with an individual `Test-Path` per tool — never group them into a hashtable or a single collective check.
- **Optional (non-blocking): preferred-reviewer calibration.** During a machine setup, offer (no pressure) to calibrate the **preferred reviewers** list for peer review, by running `Set-LlmDelegatePreferredReviewers.ps1` (owned by the `mimir-delegate` skill; this workflow only offers to run it, it does not own the contract; if `mimir-delegate` is not installed, skip this offer with a short notice — it is optional and non-blocking). **Before offering scope**, run `Resolve-LlmDelegatePreferredReviewers.ps1 -Orchestrator <session harness>` (also from `mimir-delegate`) and show `preferenceSource` / `effectivePreferredPath` / whether an orchestrator-specific file already exists. Do not sell the machine-scope list as "the" list when `cascadeOrchestratorExists=true` — ask whether the user wants (a) a list **for this harness** (`-Scope orchestrator`) or (b) the **machine** list (the fallback when no orchestrator file exists). A first-use offer with **no** orchestrator file can still write to machine scope; if the harness already has `preferred-reviewers.<orchestrator>.json`, this session's calibration should go to orchestrator scope unless the user asks for machine. **A native subagent identity does not fit machine scope** — the script refuses (`native-machine-scope-forbidden`), because a native subagent belongs to the harness that runs it; if the calibration includes one, it goes under `-Scope orchestrator` in that tool's session. Never write without confirmation.

## PATH RESOLUTION

- This workflow is shipped under the `mimir-lite` skill at `<repo>/skills/mimir-lite/workflows/install.md`; its companion scripts live under `<repo>/skills/mimir-lite/scripts/`. Relative references such as `../scripts/<file>.ps1` resolve from `skills/mimir-lite/workflows/`.
- The registration engine's inventory root is `<repo>/skills`, two directory levels above `skills/mimir-lite/workflows/` (not the repository root or the `mimir-lite` skill/script root). The engine infers this root by default; pass `-RepoRoot <repo>/skills` when specifying it explicitly.
- Resolve every `../references/<file>.md` reference relative to the directory of this file (`skills/mimir-lite/workflows/`), not relative to the current working directory.

---

## FIRST INSTALL FROM THE REPOSITORY URL

When a user asks an agent to install the skill from the repository URL, the repository `README.md` section "Use it with an AI agent" is the step-by-step bootstrap; this workflow takes over for auditing and fixing registrations. When the user asks to install or update the skill following the README, read the README from its URL first, even when the skill is already installed or linked, and follow its steps in order: the existing-clone check first, the install audit last. The bootstrap rules that matter here:

- **Git consent.** Any network or git write on the skill checkout (clone, fetch, pull, reset) needs the user's explicit yes first. A request to install or update the skill, or to follow the README, is not that yes.
- **Clone location.** Clone into a folder of its own outside any user project (for example `$HOME/mimir-lite`); never into a project folder. The repository's root `AGENTS.md` and `CLAUDE.md` are for contributors to this repository, and an agent working in the project would load them as project instructions. Cloning is installing software: the question (see **Git consent**) names the target path; read the README from its URL instead of cloning the repository elsewhere to read it, and clone once, into the approved path. A ZIP download works too, but Windows marks the downloaded scripts as blocked: unblock them with `Get-ChildItem -Recurse "<mimir-lite-root>" | Unblock-File` before running anything.
- **Existing clone.** When `<mimir-lite-root>` already exists, do not clone again and do not update it yet. Inspect it read-only (`git -C "<mimir-lite-root>" status`, `git -C "<mimir-lite-root>" log -1 --oneline`, `git -C "<mimir-lite-root>" remote get-url origin`) and tell the user its state, its current commit, and whether `origin` is the README's URL. Ask before updating. With a yes, fetch, then update by fast-forward only (`git -C "<mimir-lite-root>" fetch origin`, then `git -C "<mimir-lite-root>" pull --ff-only`). If it cannot fast-forward (unrelated history, local commits, or uncommitted changes), stop and explain why in plain words; never reset, delete, or overwrite the existing clone. Offer a fresh clone into a new approved path instead, and remove or rename the old clone only after an explicit yes and only when its `git status` is clean.
- **Skills folders.** `~/.agents/skills/` is the shared folder for most tools: Codex, Cursor, OpenCode, Pi, GitHub Copilot, Gemini CLI, and the Antigravity CLI read it. Claude Code (CLI, VS Code extension, desktop) reads `~/.claude/skills/`, and the Antigravity IDE reads `~/.gemini/config/skills/`. Link into the folders of the tools the user actually uses; linking into both `~/.agents/skills/` and `~/.claude/skills/` is fine. The audit below is stricter for Cursor than Cursor itself: it still asks for a native link under `~/.cursor/skills/` (see **Classification when auditing**).
- **Link, never copy.** A copy of the skill folder is not supported: it goes stale after `git pull`, and the audit cannot tell a stale copy from a current one. Use a symbolic link: on Windows `New-Item -ItemType SymbolicLink`, which needs Developer Mode or an elevated shell, with a directory junction (`New-Item -ItemType Junction`) as the fallback; on Linux and macOS `ln -s`, which needs no special rights. See **PURPOSE**.
- **Ask before linking.** A request to install the skill, or to follow the README, is not consent to create links. Before creating any link, name each link path and its target and wait for the user's explicit approval; create only the approved links (see **PURPOSE**).
- **Audit after linking.** Run the audit engine (**WORKFLOW** step 2) once the links exist, with `-SkipTool`/`-SkipSkill` for the tools and skills the user chose not to link (see **PURPOSE**), and report its `overall` result to the user, naming what was skipped by choice. For example, pass `-SkipSkill mimir-delegate` when the user did not want delegation.
- **New session if needed.** Most agent tools load skills when a session starts; some load a newly linked skill in the running session. Check whether the skill is available before asking the user to start a new session; until it is, the agent can read `<mimir-lite-root>/skills/mimir-lite/SKILL.md` directly.
- **Audit coverage.** The audit engine has built-in rules for Claude Code, Codex, Cursor, OpenCode, and Antigravity. Other tools that read `~/.agents/skills/` (Pi, GitHub Copilot, Gemini CLI) are audited by declaring that folder with `-AdditionalSkillsRoot .agents/skills` (see **OTHER TOOLS**).

---

## TRIGGERS

Use this workflow for:
- Checking whether every skill in this repository is globally registered after `git pull`, in any installed tool (built-in support: Codex, Claude Code, Cursor, OpenCode, Antigravity; other tools via **OTHER TOOLS**)
- Setting up the environment for a new user who cloned this skills repository
- Detecting a missing, orphaned, broken, or compatibility-only-covered skill link in the installed tools
- Registering a newly added skill
- Removing the registration of a skill removed from the repository

Do NOT use this workflow for:
- Installing any agent tool (Codex, Claude Code, Cursor, OpenCode, Antigravity, or another) on the machine
- Registering skills from other repositories
- Preparing or auditing a GeneXus KB workspace (use the **setup** workflow)
- Syncing a KB's XPZ (use the **sync** workflow)

---

## SKILL PATHS PER TOOL

The paths below are the expected ones on Windows, Linux, and macOS. Check each path's existence before using it — never assume it already exists. The "also reads from" column lists paths where a tool detects skills through official cross-compatibility, even with no native registration of its own there. For OpenCode, require a native registration in this workflow to avoid depending on optional compatibility with Claude Code.

| Tool | Native path (USER) | Also reads from (compatibility) |
|---|---|---|
| Codex | `~/.codex/skills/` (`$CODEX_HOME/skills/` by default — the built-in `$skill-installer`'s target; includes a product-shipped `.system/`) | `~/.agents/skills/` — a second USER scope Codex also indexes (per OpenAI's own docs); it does not replace `.codex/skills/` as the installer's home |
| Claude Code | `~/.claude/skills/` | — |
| Cursor | `~/.cursor/skills/` (native, required by this workflow) | `~/.agents/skills/`, `~/.claude/skills/`, `~/.codex/skills/` |
| OpenCode | `~/.config/opencode/skills/` or `~/.agents/skills/` | — |
| Antigravity | `~/.gemini/config/skills/` (global) or `~/.agents/skills/` (shared) | — |

`~` resolves to `%USERPROFILE%` on Windows and to `$HOME` on Linux and macOS. Do not confuse `~/.config/opencode/` (OpenCode's official config path, including on Windows) with `%APPDATA%/opencode/` (the desktop app's Edge WebView cache, not a skills directory). Do not confuse `~/.cursor/skills/` (the user's own custom skills) with `~/.cursor/skills-cursor/` (Cursor's internal directory for native skills shipped by the Cursor team).

## REGISTRATION STRATEGY

This workflow offers two strategies and defaults to **compact** (`-Strategy compact`). Use **expansive** only when the user asks (`-Strategy expansive`); these are the only accepted `-Strategy` values.

### Compact (default)

These native directories cover the installed tools:

- `~/.claude/skills/` → Claude Code (native); Cursor only by compatibility
- `~/.codex/skills/` → Codex (native, via `$CODEX_HOME/skills/`/the installer); Cursor only by compatibility
- `~/.cursor/skills/` → Cursor (**native, mandatory** when Cursor is installed)
- `~/.config/opencode/skills/` → OpenCode (native)
- `~/.gemini/config/skills/` → Antigravity (native, global)

**Optional:** `~/.agents/skills/` — Codex's second USER scope, and a native product path for Cursor/OpenCode; it does **not** replace `~/.cursor/skills/` in this workflow. If a skill only exists under `.agents`/`.claude`/`.codex` and Cursor is installed, its Cursor classification is **covered by compatibility** and this **flags `REGISTRATION_GAPS`** — the fix must create the link under `~/.cursor/skills/`.

**Two junctions to the same target:** registering `skill-name` as a junction in both `~/.codex/skills/` and `~/.agents/skills/`, both pointing at the same repository folder, does not duplicate content on disk — they are two redundant entry points. Useful when explicit exposure in both Codex USER scopes is wanted; otherwise, one link per skill under the compact strategy is enough (except Cursor, which requires its own native link under `~/.cursor/skills/`).

Advantage: fewer symlinks/junctions to maintain (except Cursor's native one). Disadvantage: uninstalling a skill from a single tool without affecting the others requires the expansive strategy.

### Expansive (opt-in)

A dedicated path per configured tool:

- `~/.codex/skills/` (Codex — the `$skill-installer`'s default path, `$CODEX_HOME/skills/`; optional coexistence with `~/.agents/skills/` when both Codex USER scopes should be indexed)
- `~/.claude/skills/` (Claude Code)
- `~/.cursor/skills/` (Cursor — also mandatory under compact)
- `~/.config/opencode/skills/` (OpenCode)
- `~/.gemini/config/skills/` (Antigravity)

Advantage: independent control per tool. Disadvantage: multiplies the links per tool (one per native directory), increasing the maintenance and post-`git pull` verification surface.

### Classification when auditing

For **Cursor** with the tool installed: the only required native path is `~/.cursor/skills/`. If a skill only exists under `~/.agents/skills/`, `~/.claude/skills/`, or `~/.codex/skills/`, classify it as **covered by compatibility** — and treat this as a **registration gap** (`REGISTRATION_GAPS`): offer to create a symlink/junction under `~/.cursor/skills/` pointing at the same target (this repository). Never leave it as "optional, no pressure".

For **OpenCode**, require a link under `~/.config/opencode/skills/` or `~/.agents/skills/`. Do not classify it as **covered by compatibility** just because a link exists under `~/.claude/skills/` — compatibility with Claude Code can be disabled by environment configuration.

For **Codex**, do not use that label between `.codex/skills/` and `.agents/skills/`: both are USER scopes Codex indexes in parallel. If the skill exists in either one, declare **OK** for Codex; only **missing** when it is absent from both (and there is no other valid link under a `$CODEX_HOME` changed via environment variable).

## INSTALLATION DETECTION

Consider a tool installed when at least one of these is true:

- Its CLI executable is available on `PATH` (`Get-Command codex`, `claude`, `cursor`, `opencode`, `agy`, or `antigravity` returns something, ignoring `WindowsApps` stubs via the `Test-UsableCliOnPath` helper), **or**
- Its main config file exists:
  - Codex: `~/.codex/config.toml`
  - Claude Code: `~/.claude/settings.json` or `~/.claude/CLAUDE.md`
  - Cursor: `~/.cursor/` with any internal config (e.g. `mcp.json`, `skills-cursor/`, `rules/`)
  - OpenCode: `~/.config/opencode/opencode.json` or `~/.config/opencode/opencode.jsonc`
  - Antigravity: `~/.gemini/config/config.json`, `~/.gemini/config/AGENTS.md`, `~/.gemini/config/GEMINI.md`, `~/.gemini/AGENTS.md`, or `~/.gemini/GEMINI.md`

A cache subdirectory alone does not count as an installation. In particular, `%APPDATA%/opencode/EBWebView/` is only the desktop app's Edge WebView cache — it is not evidence of a configured OpenCode CLI.

Tools without built-in support are never auto-detected; the user declares them (see **OTHER TOOLS**).

> **Conceptual note:** this workflow's Antigravity support is about registering skills for the Antigravity agent tool on the machine. Do not confuse this with the Gemini (`gemini -p`) and Antigravity CLI (`agy -p`) execution backends used, in isolation, as LLM delegation engines by the `mimir-delegate` skill.

---

## OTHER TOOLS

Any agent tool that reads `SKILL.md` from a skills directory can use these skills, even without built-in support in the audit engine. The mechanism is the same as for the built-in tools: link (symlink, or junction on Windows — **never copy**) each `<repo>/skills/<skill>` folder into that tool's skills directory, after confirming with the user.

- **First choice:** `~/.agents/skills/`. Codex, OpenCode, and Antigravity already read it natively in this workflow's rules, and Pi, GitHub Copilot, and Gemini CLI read it according to their own documentation; for any other tool, confirm in its documentation that it reads this folder.
- **Otherwise:** the tool's own skills directory, as stated in that tool's documentation. Do not guess a path; if the documentation does not state one, ask the user.
- **Verify** by running the audit engine with the directory declared, in the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`): `pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Test-MimirSkillsRegistration.ps1" -AdditionalSkillsRoot <dir>` (repeatable; relative paths resolve against the user profile, absolute paths are used as is). Each directory appears in `tools[]` as `Custom:<dir>`, treated as installed and audited with the same statuses (`OK`, `missing`, `broken`); a missing skill flags `REGISTRATION_GAPS`. The engine stays read-only, and the directory also joins the orphan scan.

---

## WORKFLOW

1. Locate the skills inventory root, `<repo>/skills` (two directory levels above `skills/mimir-lite/workflows/`); this is not the repository root or the shipped `skills/mimir-lite` workflow/script root.
2. Run the **audit engine** `../scripts/Test-MimirSkillsRegistration.ps1` (`-AsJson` for agents) in the canonical command form (see [Running scripts](../SKILL.md#running-scripts) in `SKILL.md`). It inventories immediate skill folders containing `SKILL.md` under `<repo>/skills`, inferred from the engine's own path by default or supplied explicitly as `-RepoRoot <repo>/skills`. It reports per-skill statuses exactly as `OK`, `covered_by_compatibility`, `missing`, `broken`, or `skipped_by_choice` (with `-SkipTool`/`-SkipSkill`, see **PURPOSE**); orphan registrations are reported separately in `orphans[]`. It applies the rules in **Skill paths per tool** and **Classification when auditing** (Codex indexes `.codex` + `.agents`; OpenCode requires native; Cursor is **OK only** with a native link under `~/.cursor/skills/` — a link only under `.agents`/`.claude`/`.codex` is compat-only and **flags `REGISTRATION_GAPS`**; Antigravity reads `.gemini/config` and `.agents`). The engine deduplicates shared directories (`.agents/skills/`) via a canonicalized `(Resolve-Path).Path`. The engine is **read-only**: it neither creates nor removes links. This file remains the source of the rules the engine implements. The inventory only audits this repository's own skills (`mimir-lite`, `mimir-delegate`).
3. Read the engine's result:
   - `overall` → `REGISTRATION_OK` (registration is sound) or `REGISTRATION_GAPS` (there are missing, broken, or orphaned links, or **`coveredByCompat` in Cursor** when installed with no native link under `~/.cursor/skills/`). `skipped_by_choice` never makes a gap.
   - `tools[].skills[].status` carries exactly one of `OK`, `covered_by_compatibility`, `missing`, `broken`, or `skipped_by_choice`; `orphans[]` separately lists links pointing inside the skills inventory root with no matching skill.
   - `skippedByChoice` (`tools`, `skills`) echoes the declared choices, `tools[].skippedByChoice` marks a declared tool, and an unknown `-SkipTool`/`-SkipSkill` name stops the engine with `BLOCK:`.
   - `summary` (ok / coveredByCompat / missing / broken / skippedByChoice / orphans) feeds the report.
4. Present a consolidated report per tool, explicitly stating which registration strategy is in use (**compact** by default, passed as `-Strategy compact`; **expansive** only if the user indicated it, passed as `-Strategy expansive`) — see **Registration strategy**.
5. For each identified gap, offer a fix:
   - **Missing** → create a symlink (on Windows, a junction if the symlink fails on permissions) at the active strategy's path
   - **Covered by compatibility (Cursor)** → **gap**: create a symlink/junction at `~/.cursor/skills/<skill>` pointing at the same target already used under `.claude`/`.codex`/`.agents` (this repository). Do not treat it as an optional "no pressure" item.
   - **Orphaned** → remove the directory's link
   - **Broken** → recreate the link
   - **Not linked by choice** → no fix to offer; name it in the report as the user's choice
6. Wait for explicit user confirmation.
7. Run the approved fixes.
8. Confirm the result per tool.
