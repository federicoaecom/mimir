### opencode

<!-- backend-parity: ignore -->
`Invoke-OpenCode` is stdin-based, blocks until a response, default
`-TimeoutSec 1200` per attempt, validated range `1..3600`; `-AllText` returns
full narration, otherwise final answer; `-Raw` bypasses normal classification
where documented. `-MessagePath` is mutually exclusive with `-Message` and keeps
the prompt out of argv. `-MaxAttempts` default 1, range 1..3; retry only happens
on `truncated`/`no-completion`, never on timeout, exit non-zero, stream error,
clean `empty`, or `-Raw`. Before actually retrying, it re-checks the usage/rate
limit in the attempt's window; a hit is terminal (no retry) to avoid re-burning
quota. Each retry writes
`OPENCODE_RETRY: attempt=N status=… reason=…` to stderr. `-TimeoutSec` is per
attempt, so wall-clock can multiply.

No default agent is applied. Without `-Agent`, opencode uses its own config
(typically `build`). With explicit `-Agent`, the adapter verifies it resolves in
`opencode agent list` and scans stderr for fallback warnings. Anyone needing
least privilege must provision and name a restricted agent.

Use provider/model ids accepted by opencode; for Ollama Cloud use
`ollama-cloud/deepseek-v4-pro`, not a short name. Catalog presence is not proof
of availability: HTTP 410 model-gone is permanent and should be recorded as
`unavailable`/`model-gone`, not timeout/quota. Log-based 429/quota detection is
time-window based and machine-shared; concurrent runs can misattribute orphan
log lines. `Format-OpenCodeLimitBlock` is evidence, not exclusive proof.

### Codex

<!-- backend-parity: ignore -->
`Invoke-Codex` is stdin-based, fixed read-only sandbox, default `-TimeoutSec
1200`, range `1..3600`. Omitting `-Model` lets Codex/config choose. Final answer
comes from `output-last-message`, persisted to `<TempDir>/<GUID>.lastmsg.txt`;
JSONL stream goes to `<GUID>.stream.jsonl`; `TempDir` cascade is bound value →
`MIMIR_CODEX_JOBS_DIR` → `%TEMP%\codex-jobs` (no param default). Request metadata
contains no prompt on sync. Timeout without lastmsg throws (`exceeded` +
`was terminated` literal fragments); timeout with lastmsg recovers success and
emits `MIMIR_CODEX_RECOVERED_AFTER_TIMEOUT=1` on stderr unless test hook
`MIMIR_TEST_CODEX_FORCE_TIMEOUT=1` forces the timeout throw. Non-zero exit
with nonblank lastmsg returns the verdict; otherwise errors are extracted from
JSON/`ERROR:` prefixes and rate/auth/service sentinels.

Sentinels `MIMIR_CODEX_LASTMSG=` and `MIMIR_CODEX_REQUEST=` are written on stderr in
`finally`; success stdout is only the verdict. In `kb-sensitive`, successful
lastmsg/stream artifacts are deleted; failure may include lastmsg evidence in
the throw.

<!-- backend-parity: ignore --> `Invoke-OpenCode.ps1` and `Invoke-Codex.ps1`
share the model-default contract: omitted `-Model` leaves the tool/config default
in place. `gpt-5.5` is an example/suggested Codex reviewer, not adapter-pinned.

<!-- backend-parity: ignore --> Durable Codex capture in the panel uses a
per-reviewer `%TEMP%\mimir-panel-codex\<RoundId>\<NN>` directory. Panel default
`TimeoutSec=1200` is injected for all sync adapters when omitted; invalid
`invokeArgs.timeoutSec` errors only that reviewer. `recoveredAfterTimeout` is
projected when lastmsg matches `request.json`; in `kb-sensitive`, success deletes
artifacts so the field stays `null` (unknown), never `false`. Fallback dispatcher
timeout has 120s overhead and opencode ×2 attempts; `ContentionKeys['codex']` is
empty.

### Claude Code

<!-- backend-parity: ignore -->
`Invoke-ClaudeCode` is stdin-based; defaults are restricted short-query posture:
`PermissionMode=plan`, `Tools=Read,Glob,Grep`, no session persistence. `-Tools ""`
disables all tools; `-Tools default` releases the CLI default set. Default
`-TimeoutSec 1200`, range `1..3600`. There is no `-MaxTurns`: the adapter does
not pass `--max-turns`.

`Invoke-ClaudeCodeAsync` is the panel path only: `stream-json`, atomic sidecar
`claude-code-async-sidecar` schema 1, stdout only after accepted final text.
Param default `-TimeoutSec 300`; dispatcher injects 1200 when omitted. The panel
validates sidecar states: `completed+true→responded`, `completed+false→error`,
`timeout→timeout`, `quota→quota`, `unavailable→unavailable`, `internalError→error`,
unexpected `cancelled→error`. In `kb-sensitive`, partial raw text is not
persisted; only accepted `.verdict.txt` raw text remains.

`Invoke-ClaudeCodeAsync` reads both `type=error` and final `type=result` with
`is_error=true` from the stream. The adapters report turn exhaustion as
`max-turns-exhausted` and an untrusted-workspace refusal as
`workspace-not-trusted`/`unavailable`. Partial text followed by a failure goes to
`failureAfterText`; orchestrator decides whether to use or
reclassify it. Noise warnings about ignored permission allow/deny entries are
discarded before classification. Usage-limit evidence remains raw in technical
fields; the human receipt must say only: `Claude Code returned a usage limit;
type/period not determined`. Do not infer monthly/weekly/5-hour windows or other
billing periods from CLI text.

Official Claude Code exit-code sources do not publish a general table. Treat
`0` as documented success where documented, `1` as generic failure without
classifiable evidence, `2` as hook-block only, and `137` as killed/terminated
possibly OOM. Do not infer quota/auth/workspace/model from a number alone.

`Invoke-ClaudeCode.ps1` and `Invoke-ClaudeCodeAsync.ps1`
refuse `PermissionMode=bypassPermissions` outright; that mode is not part of Mimir
delegation.

### Copilot CLI

<!-- backend-parity: ignore -->
`Invoke-Copilot` is sync only, argument-based, external
`github-copilot/<model>`. It uses `--no-custom-instructions`,
`--disable-builtin-mcps`, `--available-tools=`, JSONL, and `--allow-all-tools`
(required for non-interactive auto-approval even though no tools are exposed).
Default model is `auto`; concrete ids can retire (e.g. `gpt-5-mini` on CLI
1.0.78), so caller-supplied ids must be known-good. `-MessagePath` removes
caller-side command substitution but the prompt still goes through argv; the
30000-char fail-closed guard remains.

### Gemini CLI

<!-- backend-parity: ignore -->
`Invoke-Gemini` is sync only, argument-based, external `google/<model>`. It uses
`--approval-mode plan` and `--output-format json`; modes other than `plan` are
blocked. `-MessagePath` does not raise the argv cap; 30000-char guard applies.

### Antigravity CLI

<!-- backend-parity: ignore -->
`Invoke-Antigravity` is sync only, external `antigravity/<model>`, fixed to
`Profile=public-review`, `Mode=plan`, semantic-only/public-only. It creates a
short empty scratch cwd, refuses `.git`, reparse points, repo roots, KB-workspace
roots or ancestors, and does not accept operational `-Cd`. It redirects user/home
and XDG variables only in the child process; this is state hygiene, not a
sandbox, and does not isolate keyrings, absolute paths, MCP, browser, or network.
`ScratchPath` and `SimulateCleanupFailure` are self-test-only and blocked by the
dispatcher. It requires the JSON envelope's `.response`; non-JSON stdout with
exit 0 is `invalidOutput`, interactive auth is `unauthenticated`, typed quota is
`quota`, timeout kills descendants and may promote quota/auth residuals. Receipt
schema `antigravity-public-review-receipt` v1 records CLI version, posture,
scratch, and cleanup `clean|degraded|failed`. Baseline version changes require a
new probe/smoke test before promoted evidence.

Observed `agy.exe` success envelope, 2026-08-04:

```json
{"conversation_id":"…","status":"SUCCESS","response":"OK\n","duration_seconds":42.6,"num_turns":1,"usage":{"input_tokens":17125,"output_tokens":43,"thinking_tokens":39,"cache_read_tokens":0,"total_tokens":17168}}
```

`AntigravityCliSupport.ps1` has a support quota pattern deliberately different
from the dispatcher; there is no regex parity. `auth` wins over quota. Prompt
echoes containing quota/auth terms can cause false classifications; the panel
projects them as technical states, not reviewer verdicts.

<!-- backend-parity: ignore --> External OAuth backends can exceed 180 seconds;
adjust `-TimeoutSec`. Antigravity is slow and expensive even on a trivial prompt
(42.6s and 17,125 input tokens measured), so review timeout/cost before panels.
