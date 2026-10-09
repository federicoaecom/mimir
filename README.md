See also: [Español](README.es.md)

<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/mimir-lockup-dark.svg">
    <img src="docs/brand/mimir-lockup.svg" alt="Mimir Lite" height="72">
  </picture>
</h1>

Mimir Lite is an agent skill that reads and understands a GeneXus Knowledge Base (KB) from its XPZ/XML exports: it syncs an XPZ export into an XML corpus and a derived index, helps an agent find objects and their dependencies through that index, reads and classifies individual object XML, and generates Markdown documentation. It never generates, builds, or imports GeneXus objects.

## Status

Current release: `0.3.0`; the first public release was `0.1.0` (see [`CHANGELOG.md`](CHANGELOG.md)). Licensed under the [MIT License](LICENSE.md); the authors are listed in [`AUTHORS.md`](AUTHORS.md).

## Support

Runs on Windows 10/11 and Linux, both tested in CI, with PowerShell 7.4+ (7.4.6+ on Linux and macOS) and Python 3.8+; macOS is best effort.

| Platform or tool | Status | Skills folder | Notes |
|---|---|---|---|
| Windows 10/11 | Tested | — | CI runs on `windows-latest`; scripts run from any shell through `pwsh -NoProfile -File` |
| Linux | Tested (CI) | — | CI runs on `ubuntu-latest`; needs PowerShell 7.4.6+; see [Known platform differences](#known-platform-differences) |
| macOS | Best effort | — | Same code paths as Linux, not run in CI; needs PowerShell 7.4.6+ |
| Claude Code (CLI, VS Code extension, desktop) | Tested | `~/.claude/skills` | One folder shared by the three variants; the **setup** workflow can write folder-prefix allow rules |
| Codex (CLI, IDE extension, app) | Tested | `~/.agents/skills` or `~/.codex/skills` | |
| Cursor | Audited | `~/.cursor/skills` | Cursor also reads `~/.agents/skills`, but the audit passes only with a link in `~/.cursor/skills` |
| OpenCode | Audited | `~/.config/opencode/skills` or `~/.agents/skills` | |
| Antigravity (IDE, CLI) | Audited | `~/.gemini/config/skills` (IDE), `~/.agents/skills` (CLI) | |
| Pi, GitHub Copilot, Gemini CLI | Expected to work, untested | `~/.agents/skills` | Audit with `-AdditionalSkillsRoot .agents/skills` |
| `mimir-delegate` backends | Tested on Windows; Linux in CI with fake CLIs | — | Drives the CLIs listed in [Delegation](#delegation-and-files-written-outside-the-repository); the maintainer runs the real CLIs on Windows; see [Known platform differences](#known-platform-differences) |

**Tested** means the maintainer runs the skill with that tool on Windows. For a platform, **Tested (CI)** means CI runs the full test suite and checks there; **Best effort** means the same code paths, with nothing run there. **Audited** means the **install** workflow ([`install.md`](skills/mimir-lite/workflows/install.md)) checks the tool's registration, but it is not reported as tested. A copy of the skill folder is not supported: it goes stale after `git pull`, and the audit cannot tell a stale copy from a current one; use a symbolic link or a junction.

### GeneXus versions

| GeneXus version | Status | Evidence |
|---|---|---|
| GeneXus 18 | Tested | The object type catalog and the reading references come from real GeneXus 18 exports (upgrades 9 and 13) |
| GeneXus 9 | Tested | Its `ExportFile` format is detected and synced with no extra configuration (see [legacy exports](skills/mimir-lite/workflows/sync.md#legacy-exports-genexus-9)); 11 of the 12 known elements were confirmed on a real export |
| GeneXus 15 to 17 | Tested with public samples | Public training and wiki exports (export header 4.0) sync, index, and answer queries |
| GeneXus X Evolution 2 and 3 | Tested with public samples | Public wiki exports (export headers 3.1 and 3.3) sync, index, and answer queries |
| GeneXus 8 and earlier, X, X Evolution 1, GeneXus Next | Unknown | No export has been read |

An object type the skill does not know stops the sync before anything is written; the skill does not guess it. An export that mixes the GeneXus 9 and the modern formats is rejected the same way.

Calls made from mobile objects (Smart Devices and Native Mobile panels and their Work With, the Offline Database object) and from GXflow business process diagrams are not indexed yet: a "who uses" answer can miss those callers, and it says so when the KB contains such objects.

## Use it with an AI agent

### For the user

Give your agent the repository URL and your XPZ, for example with this prompt (replace the angle-bracket parts):

```text
Install the Mimir Lite skill from https://github.com/federicoaecom/mimir following its README, then set up a KB workspace for my GeneXus KB <KbName> in <folder> and sync this XPZ: <path>.
```

For the first sync, give it a full export of the KB from the GeneXus IDE, not only the objects you changed. Give the XPZ as a file path when you can: a file attached in the chat may not exist on disk for the agent's scripts.

### For the agent

Follow these steps in order. The command blocks below are PowerShell 7, except the one marked for Linux and macOS, which is bash; when your shell is bash, run each PowerShell block through `pwsh -NoProfile -Command '<block>'`. Ask the user before installing software or creating links.

1. **Check the prerequisites** (see [Support](#support)): `pwsh --version` (7.4+ on Windows, 7.4.6+ on Linux and macOS), a Python 3.8+ that answers as `python3 --version`, `python --version`, or `py -3 --version` (the Microsoft Store stub under `WindowsApps` does not count), `git --version`. Offer to install what is missing, then open a new terminal so `PATH` picks it up. On Linux, install `python3` and `git` with the distribution's package manager, and PowerShell as described in [Microsoft's installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell). On Windows, the `winget` lines run in any shell, so they work before `pwsh` is installed:

   ```powershell
   winget install --id Microsoft.PowerShell -e
   winget install --id Python.Python.3.12 -e
   winget install --id Git.Git -e
   ```

2. **Clone the repository outside the user's project**, never into the project folder: its root `AGENTS.md` and `CLAUDE.md` are instructions for contributors to this repository, and an agent working in the project would load them as project instructions. The clone path is `<mimir-lite-root>` in every workflow.

   Cloning is installing software: ask the user first, naming the target path (for example `$HOME/mimir-lite`), and clone only after an explicit yes. Read this README from its URL instead of cloning the repository somewhere else to read it; clone once, into the approved path.

   ```powershell
   git clone https://github.com/federicoaecom/mimir "$HOME/mimir-lite"
   ```

   This line runs unchanged in bash too.

   Without Git, a ZIP download extracted to the same place works, but Windows marks the downloaded scripts as blocked; unblock them with `Get-ChildItem -Recurse "$HOME\mimir-lite" | Unblock-File`.

3. **Link the skill folder into the agent tool's skills folder.** `~/.agents/skills` is read by Codex, Cursor, OpenCode, Pi, GitHub Copilot, Gemini CLI, and the Antigravity CLI; Claude Code (CLI, VS Code extension, desktop) reads `~/.claude/skills`; the Antigravity IDE reads `~/.gemini/config/skills` (see [Support](#support)). Linking into both of the first two is fine. Cursor users also link into `~/.cursor/skills`, or the audit reports a gap. A copy of the skill folder is not supported: it goes stale after `git pull`, and the audit cannot tell a stale copy from a current one; use a symbolic link or a junction.

   Ask before linking. Name each link you would create, as the link path and its target (for example `~/.claude/skills/mimir-lite` pointing to `<mimir-lite-root>/skills/mimir-lite`), and create only the links the user approves. A request to install the skill, or to follow this README, is not consent to create links. Keep in the blocks below only the skills folders the user approved.

   On Windows, a symbolic link needs Developer Mode or an elevated shell; the block falls back to a directory junction, which needs neither, and skips a link that already exists:

   ```powershell
   $repo = "$HOME\mimir-lite"
   foreach ($skills in "$HOME\.agents\skills", "$HOME\.claude\skills") {
       New-Item -ItemType Directory -Force -Path $skills | Out-Null
       if (Test-Path "$skills\mimir-lite") { continue }
       try   { New-Item -ItemType SymbolicLink -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" -ErrorAction Stop | Out-Null }
       catch { New-Item -ItemType Junction -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" | Out-Null }
   }
   ```

   On Linux and macOS, a symbolic link needs no special rights. This bash block creates one with `ln -s` and skips a link that already exists:

   ```bash
   repo="$HOME/mimir-lite"
   for skills in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
       mkdir -p "$skills"
       if [ -e "$skills/mimir-lite" ] || [ -L "$skills/mimir-lite" ]; then continue; fi
       ln -s "$repo/skills/mimir-lite" "$skills/mimir-lite"
   done
   ```

   Link `skills/mimir-delegate` the same way only if the user wants delegation, after the same question.

   After linking, run the install audit and tell the user its `overall` result (`REGISTRATION_OK` or `REGISTRATION_GAPS`). The **install** workflow ([`install.md`](skills/mimir-lite/workflows/install.md)) explains the result and how to fix a gap, again only after the user approves. Declare what the user chose not to link: `-SkipSkill mimir-delegate` when the user did not want delegation, and `-SkipTool <name>` for each installed tool the user did not want linked (for example `-SkipTool Cursor`); the audit reports them as `skipped_by_choice`, which is not a gap. Add `-SkipSkill mimir-delegate` to the command below only when the user did not want delegation; never add it when the user asked for delegation, so a missing link still shows as a gap. The audit covers Claude Code, Codex, Cursor, OpenCode, and Antigravity, and other tools with `-AdditionalSkillsRoot`:

   ```powershell
   pwsh -NoProfile -File "$HOME/mimir-lite/skills/mimir-lite/scripts/Test-MimirSkillsRegistration.ps1" -AsJson
   ```

4. **Start a new agent session if needed.** Most tools load skills when a session starts, so the current session may not see the new skill yet; some tools load a newly linked skill in the running session. Check whether the skill is available before asking the user to restart. If it is not and restarting is not possible, read `<mimir-lite-root>/skills/mimir-lite/SKILL.md` directly and follow it.

5. **Set up the KB workspace, then sync.** Follow the **setup** workflow ([`setup.md`](skills/mimir-lite/workflows/setup.md)), which creates the workspace with the scaffolder in one command, for example `pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1" -WorkspaceRoot "<KbWorkspace>" -KbName <KbName>`. Then follow the **sync** workflow ([`sync.md`](skills/mimir-lite/workflows/sync.md)), including its [first sync guidance](skills/mimir-lite/workflows/sync.md#first-sync-of-a-new-workspace): where to put a chat-attached XPZ, why the first load must be a full export, and why the run can outlast a command timeout.

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10/11 or Linux | Both tested in CI; macOS is best effort (see [Support](#support)) |
| PowerShell 7.4+ (`pwsh`); 7.4.6+ on Linux and macOS | Scripts under `skills/` and `tools/` declare `#requires -Version 7.4`, except `skills/mimir-lite/scripts/Test-MimirPowerShellRuntime.ps1` and its template `Test-KbPowerShellRuntime.example.ps1`, which omit it by design so they can report an older host; the test runner (`tests/Invoke-Tests.ps1`) and its self-test declare 7.0. On Linux and macOS, 7.4.6 is the first version tested: 7.4.2 loses a native command's stderr when stdout and stderr are redirected to separate files |
| Python 3.8+ (stdlib only, including `sqlite3`) | Needed to build the SQLite index and to run every index query, plus the transaction-writability check; no third-party packages. Found as `python3`, then `python`, then `py -3`. 3.8 is the minimum the code's syntax allows (an assignment expression in the query engine) and was verified by running the index build and a query on 3.8, 3.10 and 3.11; older versions are not supported |

Not needed: a GeneXus IDE installation, MSBuild, or any GeneXus build/specify/generate tooling. Building, packaging, or importing XPZ into a KB is out of scope for this skill.

### Platform

Windows and Linux are tested in CI; macOS runs the same code paths as Linux, best effort ([Support](#support)). The PowerShell layer finds the user's home folder through `HOME` or `USERPROFILE`, registers skills with symbolic links (with a junction fallback on Windows), and on Windows skips the Microsoft Store Python stub (`WindowsApps`). The Python engines (index build and query, writability) and the SQLite index use only the standard library. The index stores the corpus path relative to the index folder, so an index built on Windows can be read on Linux.

### Known platform differences

- **PowerShell version.** Linux and macOS need PowerShell 7.4.6 or later (see [Requirements](#requirements)).
- <!-- backend-parity: ignore --> **Prompt on stdin.** On Linux and macOS, the `mimir-delegate` adapters that send the prompt on stdin (opencode, Codex, Claude Code) deliver it with one extra trailing newline, because PowerShell copies the redirected file line by line. It is harmless for an LLM CLI.
- **State folder.** `mimir-delegate` keeps its state under `%LOCALAPPDATA%\mimir-delegate` on Windows and `~/.local/share/mimir-delegate` on Linux (`$XDG_DATA_HOME/mimir-delegate` when that variable is set). On macOS it uses the .NET local application data folder, typically `~/Library/Application Support/mimir-delegate`, or the Linux location when `~/Library/Application Support` does not exist; this is not tested in CI.
- <!-- backend-parity: ignore --> **CLI discovery.** An explicit `-<Tool>Exe` parameter wins on every system. Without it, on Windows, Codex is taken from the Codex desktop app's binaries under `%LOCALAPPDATA%\OpenAI\Codex\bin` (the npm shim on `PATH` is ignored), and opencode and the Antigravity CLI from `PATH`, then from their Windows install folders (`%APPDATA%\npm`, `%LOCALAPPDATA%\agy`). On Linux and macOS every CLI comes from `PATH`; for Codex, the first `codex` that answers `codex --version`.

## Installation

1. Clone this repository outside any project folder (see [Use it with an AI agent](#use-it-with-an-ai-agent), step 2).
2. Run the **install** workflow ([`skills/mimir-lite/workflows/install.md`](skills/mimir-lite/workflows/install.md)) to register `skills/mimir-lite/` and, optionally, `skills/mimir-delegate/` as skills in the agent tools installed on your machine (built-in support: Codex, Claude Code, Cursor, OpenCode, Antigravity; any other tool that reads `SKILL.md` from a skills directory can be linked the same way, see the workflow's "Other tools" section). It creates a symlink or junction per tool, detects which tools are actually installed, and changes nothing without explicit confirmation.

Re-run the install workflow after every `git pull`, since it also detects skill registrations that went stale or orphaned. After an update that changes the setup contract, the first KB task in each existing workspace reports `AUDIT_REQUIRED` once; run the setup audit and approve the timestamp re-stamp.

## Quick start

Run these from the repository root in PowerShell 7.4+ (7.4.6+ on Linux and macOS). Each command below was run as shown against the synthetic fixture.

**1. Register the skill in an agent tool** (skip this step if you followed [Use it with an AI agent](#use-it-with-an-ai-agent)). The example links `mimir-lite` into Claude Code's skills folder; [Support](#support) lists the folder of every other tool. The block is for Windows, where a symbolic link needs Developer Mode or an elevated shell; it falls back to a directory junction, which needs neither, and skips a link that already exists. On Linux and macOS, run `mkdir -p ~/.claude/skills && { [ -e ~/.claude/skills/mimir-lite ] || [ -L ~/.claude/skills/mimir-lite ] || ln -s "$PWD/skills/mimir-lite" ~/.claude/skills/mimir-lite; }` in bash instead, which also skips a link that already exists. A copy of the skill folder is not supported: it goes stale after `git pull`, and the audit cannot tell a stale copy from a current one; use a symbolic link or a junction. Link `skills/mimir-delegate` the same way only if you want delegation.

```powershell
$repo   = (Get-Location).Path
$skills = "$HOME\.claude\skills"
New-Item -ItemType Directory -Force -Path $skills | Out-Null
if (-not (Test-Path "$skills\mimir-lite")) {
    try   { New-Item -ItemType SymbolicLink -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" -ErrorAction Stop | Out-Null }
    catch { New-Item -ItemType Junction -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" | Out-Null }
}
```

**2. Check the registration.** The audit is read-only and covers Claude Code, Codex, Cursor, OpenCode, and Antigravity; `mimir-lite` should show `OK` (`mimir-delegate` shows `missing` unless you linked it, or `skipped_by_choice` with `-SkipSkill mimir-delegate`, which is not a gap). For another tool, add its skills folder with `-AdditionalSkillsRoot <dir>`; it is reported as `Custom:<dir>`.

```powershell
$audit = pwsh -NoProfile -File skills/mimir-lite/scripts/Test-MimirSkillsRegistration.ps1 -AsJson | ConvertFrom-Json
($audit.tools | Where-Object name -eq 'ClaudeCode').skills | Select-Object name, status, linkType
```

**3. First run against the synthetic fixture.** This builds the derived SQLite index from `tests/fixtures/sample-kb/` into a temporary folder (nothing is written inside the repository) and asks who uses the `Customer` table. The build needs Python (see [Requirements](#requirements)) and prints a JSON validation report; the query prints a short result.

```powershell
$work = Join-Path ([IO.Path]::GetTempPath()) 'mimir-quickstart'
New-Item -ItemType Directory -Force -Path $work | Out-Null
pwsh -NoProfile -File skills/mimir-lite/scripts/Build-KbIntelligenceIndex.ps1 -SourceRoot tests/fixtures/sample-kb -OutputPath "$work/kb-index.sqlite"
pwsh -NoProfile -File skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1 -IndexPath "$work/kb-index.sqlite" -Query who-uses -ObjectType Table -ObjectName Customer -Format text
```

Expected query output:

```text
who-uses: Table:Customer
results: 1/1
- #21 Transaction:Customer -> Table:Customer [has_level_table, direct]
  Transaction/Customer.xml:3 Level Type via transaction_level_table
  <Level name="Customer" Type="Customer">
```

This shows the two engines the **find** workflow relies on. It deliberately skips the KB workspace, the XPZ sync, and the mandatory freshness gate, which need a real KB workspace; the **setup** workflow creates one in one command with `New-MimirKbWorkspace.ps1`. An agent always passes that gate before trusting an index. For a real KB, the first sync takes a full KB export (see the **sync** workflow's [first sync guidance](skills/mimir-lite/workflows/sync.md#first-sync-of-a-new-workspace)).

## Workflows

Each step below names the workflow that handles it; see the linked workflow file for the full contract.

| Step | Workflow | What it does |
|---|---|---|
| 1. Set up the KB workspace | [`workflows/setup.md`](skills/mimir-lite/workflows/setup.md) | Creates the folder structure next to your GeneXus KB in one command with `New-MimirKbWorkspace.ps1` (`KbObjectsXml`, `KbIntelligence`, local wrappers), or audits an existing one |
| 2. Sync an XPZ | [`workflows/sync.md`](skills/mimir-lite/workflows/sync.md) | Materializes an XPZ exported from the GeneXus IDE into the XML corpus, one file per object |
| 3. Find via the index | [`workflows/find.md`](skills/mimir-lite/workflows/find.md) | Queries the derived SQLite index for who-uses/what-uses/impact before opening XML, after its mandatory freshness gate passes |
| 4. Read an object | [`workflows/read.md`](skills/mimir-lite/workflows/read.md) | Structurally classifies a single object's XML (type, family, parts, risk) |
| 5. (Optional) Generate docs | [`workflows/docs.md`](skills/mimir-lite/workflows/docs.md) | Produces Markdown documentation from the XML corpus |

The XML corpus (`KbObjectsXml`) is the normative source; the index is always a shortcut to it, never a replacement, and every substantive index query must pass its freshness gate first.

## Repository layout

```
skills/
├── mimir-lite/       # core skill (installed into agent tools)
│   ├── SKILL.md       # entry point + router to workflows
│   ├── workflows/      # sync, find, read, docs, setup, install
│   ├── references/     # agent-facing knowledge base
│   └── scripts/        # PowerShell + Python engines
└── mimir-delegate/    # optional skill: delegation and peer review
    ├── SKILL.md
    ├── references/
    └── scripts/
tests/                 # self-tests and parity tests, one runner
tools/                 # contributor-only checks (parse, encoding, links, pre-push)
docs/                  # human documentation (see below)
```

## Running tests and checks

All commands run from the repository root with `pwsh` 7.4+ (7.4.6+ on Linux and macOS).

| Command | What it checks |
|---|---|
| `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1` | Runs every `*SelfTest.ps1` and Python `Test*.py` under `tests/` (add `-AsJson` for a structured report) |
| `pwsh -NoProfile -File tools/Test-TextEncoding.ps1` | Tracked text files are UTF-8 without BOM, LF line endings |
| `pwsh -NoProfile -File tools/Test-PsScriptsParse.ps1` | Every `*.ps1` under `skills/`, `tools/`, `tests/` parses cleanly |
| `pwsh -NoProfile -File tools/Test-PyScriptsParse.ps1` | Every `*.py` under the same roots parses cleanly (no bytecode written) |
| `pwsh -NoProfile -File tools/Test-MarkdownFences.ps1` | Markdown code fences are balanced and well formed |
| `pwsh -NoProfile -File tools/Test-MarkdownLinks.ps1` | Relative Markdown links and bare `NN-*.md` mentions resolve to a real file |
| `pwsh -NoProfile -File tools/Test-ScriptInventory.ps1` | Every script is listed in the script inventory |
| `pwsh -NoProfile -File tools/Test-CodeLanguage.ps1` | Code comments and messages are in English |

CI runs all of the checks above on Windows and Linux (see [`CONTRIBUTING.md`](CONTRIBUTING.md)). Maintainers also run the mechanical pre-push checks (git context, parse, whitespace) with `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson`; see [`docs/process/13-pre-push-review.md`](docs/process/13-pre-push-review.md).

## Documentation map

| Folder | Contents |
|---|---|
| [`docs/README.md`](docs/README.md) | Index of human documentation |
| `docs/process/` | Team working methods (pre-push review, reinforced review, peer review) |
| [`docs/adr/`](docs/adr/README.md) | Decision records |
| `docs/ideas/` | Curated [backlog](docs/ideas/backlog.md) and [discarded ideas](docs/ideas/discarded.md) |
| [`docs/i18n/`](docs/i18n/README.md) | Translation policy and [glossary](docs/i18n/glossary.md) |

Skill payload (`SKILL.md`, `workflows/`, `references/`) is agent-facing and lives inside `skills/`, not in `docs/`.

## Out of scope

Generating, cloning, or packaging GeneXus objects; building or importing XPZ packages into a KB; MSBuild-based builds. See each workflow's own "Do NOT use this workflow for" section for detail.

## Delegation and files written outside the repository

`mimir-lite` never sends anything to an external service. The optional `mimir-delegate` skill can, and only when you ask an agent to delegate a task or run a peer review: it sends prompt content to an external LLM CLI (opencode, including the model providers it is configured with; Codex; Claude Code; GitHub Copilot CLI; Gemini CLI; Antigravity CLI) or to a local model. Before sending, the agent classifies the payload as `public` or `kb-sensitive` and runs `Resolve-LlmDelegateAuthorization.ps1`, which returns allow, ask, or deny from the destination's locality and your policy. The agent judges the payload's sensitivity, so this gate is procedural, not technical: it does not inspect the content. If you do not want any KB content to leave your machine, do not ask for delegation, or answer "deny" when asked. See [`SECURITY.md`](SECURITY.md) and [`skills/mimir-delegate/SKILL.md`](skills/mimir-delegate/SKILL.md).

The tools write outside this repository in these places:

| Location | What | Written by |
|---|---|---|
| `<KB workspace>` | The new workspace next to your KB: `scripts` (local wrappers), `README.md`, `AGENTS.md`, `kb-source-metadata.md`, `.gitignore`, and the folders `Temp`, `IdeXpzExports`, `KbObjectsXml`, `KbIntelligence` | `mimir-lite` **setup** workflow, with the `New-MimirKbWorkspace.ps1` scaffolder |
| `<KB workspace>\KbObjectsXml`, `<KB workspace>\KbIntelligence` | The XML corpus and the derived index, next to your KB | `mimir-lite` **sync** and **setup** workflows |
| `<KB workspace>\.claude\settings.json` | Claude Code allow rules for the workspace's `scripts` folder and the shared engine scripts | **setup** workflow (steps 20 and 20a), Claude Code only; you can decline |
| Agent-tool skills directories (for example `~/.claude/skills/`) | One link per skill, never a copy | **install** workflow, after your confirmation |
| Global instruction files of your agent tools | The "KB workspace" trigger section | **setup** workflow, only after your explicit confirmation |
| `%LOCALAPPDATA%\mimir-delegate` (Windows), `~/.local/share/mimir-delegate` (Linux), typically `~/Library/Application Support/mimir-delegate` (macOS, not tested in CI; the Linux location when `~/Library/Application Support` does not exist) | `capabilities.json`, `preferred-reviewers.json` (and per-tool `preferred-reviewers.<tool>.json`), circuit-breaker state | `mimir-delegate` |
| `<KB workspace>\llm-delegation-policy.json` | Per-KB external-delivery policy | `mimir-delegate`, when you record a policy |
| The system temp folder, `%TEMP%` on Windows, `$TMPDIR` or `/tmp` elsewhere (`claude-code-async`, `codex-jobs`, `mimir-panel-dispatch`, `mimir-panel-codex`, `mimir-agy-public-review`, and temporary files) | Prompts, outputs, and job state of delegated runs; adapters that accept `-KeepDays` clean up old job folders | `mimir-delegate` |

## Contributing and security

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for how to contribute and [`SECURITY.md`](SECURITY.md) for how to report a security issue. Participation is governed by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md), and changes are recorded in [`CHANGELOG.md`](CHANGELOG.md).
