#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for the Invoke-LlmDelegatePanelDispatch.ps1 harness (mimir-delegate skill).
.DESCRIPTION
    Deterministic, with no real backends or network: injects a fake-exe per backend via
    -BackendExeMap (on the REAL adapter) and drives the REAL gate with synthetic configs/policy.
    Covers the v11 self-test list: effective model + fail-closeds; codex gate with oss; general
    gate (fixture, kb-sensitive fail-closed, a gate that THROWS); opencode kb-sensitive -> unavailable;
    splat + containment; durable Codex capture in the panel (TempDir/RetentionMode Bound,
    invokeArgs.tempdir→droppedArgs, strip MIMIR_CODEX_ with 429 on the path); parallelism (occupancy
    <= OllamaConcurrency for ollama-cloud, others free, a block that throws does not abort the rest,
    OllamaConcurrency=0 -> validation, Dispose after capture); no single-flight (fake NOT
    re-invoked + concurrencySaturationWarning); mechanical classification (responded even off-task);
    -Cd (precedence + fail-closed); contract (stdout 1 JSON line Kind/SchemaVersion PascalCase,
    accents intact, stderr separate, state subset, empty targetModelKey->null, ledger per state,
    unavailableCount, quotaCount, ReviewersJson inline/file/invalid, missing RoundId->guid,
    Windows-safe slug).

    The harness is invoked as a CHILD PROCESS (pwsh -File) with stdout/stderr redirected to
    files — faithful to real-world consumption and the stdout discipline (the JSON is the only
    line of stdout).

    Success sentinel: OK: Test-InvokeLlmDelegatePanelDispatchSelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptsDir = Join-Path $repoRoot 'skills/mimir-delegate/scripts'
$testsDir = Join-Path $repoRoot 'tests/mimir-delegate'
$harness = Join-Path $scriptsDir 'Invoke-LlmDelegatePanelDispatch.ps1'
if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) { throw "BLOCK: target not found: $harness" }
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}
function Get-Reviewer {
    param($Json, [int]$Index)
    return @($Json.reviewers | Where-Object { [int]$_.index -eq $Index })[0]
}
function Get-ReviewerByTarget {
    param($Json, [string]$TargetModelKey)
    return @($Json.reviewers | Where-Object { [string]$_.targetModelKey -eq $TargetModelKey })[0]
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-panel-dispatch-selftest-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tmp) | Out-Null
$ledgerRoot = Join-Path $tmp 'ledger'
$concLog = Join-Path $tmp 'conc.log'
$mutexName = 'panel-fake-mtx-' + [guid]::NewGuid().ToString('N')

# Env shared with the child process (and with the fake-exe via inherited Start-Process)
$env:PANEL_FAKE_LOG = $concLog
$env:PANEL_FAKE_MUTEX = $mutexName
# Isolates Invoke-Codex's KeepDays (the harness's Bound TempDir splat wins over env; DISABLE avoids cleanup).
$script:prevCodexDisableKeepDays = $env:MIMIR_CODEX_DISABLE_KEEPDAYS
$env:MIMIR_CODEX_DISABLE_KEEPDAYS = '1'
$repoRoot = Split-Path -Parent $scriptsDir

# Deterministic cwd at the repo root (harness in-process AND child).
Push-Location $repoRoot
try {
    # ---------------------------------------------------------------------------------------
    # Fixtures: fakes + synthetic configs
    # ---------------------------------------------------------------------------------------
    # fake-opencode: reads stdin (prompt), parses --model, logs ENTER/EXIT (mutex) and emits
    # opencode's minimal JSON stream. Behavior by model substring: 'sleep' sleeps 8 s, long
    # enough that the parallelism check sees overlapping windows even when concurrent process
    # starts are seconds apart on a slow hosted runner ('sleep' reviewers run with the default
    # timeout, never a short one);
    # 'empty' emits only step_finish (no text) -> Invoke-OpenCode classifies 'empty' (terminal);
    # others -> emit text (responded), with pt-BR accents.
    $fakeOcCmd = New-FakeCli -Directory $tmp -Name 'fake-opencode' -PwshBody @'
$model = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--model') { $model = [string]$args[$i + 1]; break } }
# `--version` probes do not get a prompt on stdin; reading it would hang whenever the parent's stdin is an open pipe.
if ($args -notcontains '--version') { $null = [Console]::In.ReadToEnd() }
$fam = @($model -split '/', 2)[0]
$log = $env:PANEL_FAKE_LOG
$mtxName = $env:PANEL_FAKE_MUTEX
function Append-Log([string]$line) {
    if ([string]::IsNullOrEmpty($log)) { return }
    $mtx = [System.Threading.Mutex]::new($false, $mtxName)
    [void]$mtx.WaitOne()
    try { [System.IO.File]::AppendAllText($log, $line + "`n") } finally { $mtx.ReleaseMutex(); $mtx.Dispose() }
}
Append-Log("$fam`tENTER`t$([DateTime]::UtcNow.Ticks)`t$model")
if ($model -match 'sleep') { Start-Sleep -Milliseconds 8000 }
if ($model -match 'timeout') { Start-Sleep -Milliseconds 5000 }
Append-Log("$fam`tEXIT`t$([DateTime]::UtcNow.Ticks)`t$model")
if ($model -match 'cota') {
    # stream error event with 402/quota/balance -> Invoke-OpenCode throws BLOCK; harness -> quota
    '{"type":"error","error":{"data":{"message":"Payment Required: insufficient coding plan balance (HTTP 402) sem quota livre"}}}'
} elseif ($model -match 'exausto') {
    # GENERIC error that contains the word "exhausted" without being quota -> must become error, NOT quota
    '{"type":"error","error":{"data":{"message":"stream failed: retries exhausted after 3 attempts"}}}'
} elseif ($model -match 'empty') {
    '{"type":"step_finish","part":{"reason":"stop"}}'
} else {
    '{"type":"text","part":{"messageID":"m1","text":"PARECER de ' + $model + ' — revisão, dedução, ação (acentos pt-BR)."}}'  # lang-allow: pt-BR payload that verifies accent preservation
    '{"type":"step_finish","part":{"reason":"stop"}}'
}
exit 0
'@

    # fake-codex: scans args for -o/-C/-m, reads stdin, writes "CD=<C> MODEL=<m>" (raw text) to -o.
    $fakeCxCmd = New-FakeCli -Directory $tmp -Name 'fake-codex' -PwshBody @'
$o = $null; $cd = ''; $m = ''
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '-o') { $o = [string]$args[$i + 1] }
    if ($args[$i] -eq '-C') { $cd = [string]$args[$i + 1] }
    if ($args[$i] -eq '-m') { $m = [string]$args[$i + 1] }
}
# `--version` probes do not get a prompt on stdin; reading it would hang whenever the parent's stdin is an open pipe.
if ($args -notcontains '--version') { $null = [Console]::In.ReadToEnd() }
if ($o) { Set-Content -LiteralPath $o -Value ("CD=$cd MODEL=$m revisão") -Encoding utf8 -NoNewline }  # lang-allow: pt-BR payload that verifies accent preservation
exit 0
'@

    # fake-claude: stdin-based (prompt via stdin; argv with flags only), so launcher+body is safe.
    # Responds to --version (>=2.1.118) and --help (flag contract) required by Resolve-ClaudeCodeExe;
    # on execution emits stdout "CLAUDE cwd=<pwd> model=<m>" (no error words). -Cd becomes the
    # process's WorkingDirectory, so (Get-Location) proves the pass-through.
    $fakeClCmd = New-FakeCli -Directory $tmp -Name 'fake-claude' -PwshBody @'
$model = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--model') { $model = [string]$args[$i + 1] } }
if ($args -contains '--version') { '2.1.118 (Claude Code fake)'; exit 0 }
if ($args -contains '--help') {
    '--model --print --output-format --no-session-persistence --permission-mode --tools'
    exit 0
}
if ($model -eq 'claude-untrusted-workspace') {
    [Console]::Error.WriteLine('Claude Code refused to run because this workspace is not trusted. Mark this workspace as trusted to continue.')
    exit 1
}
$null = [Console]::In.ReadToEnd()
if ($model -eq 'claude-sensitive-ledger') {
    [Console]::Error.WriteLine('stderr bruto sensivel')
    [pscustomobject]@{
        type = 'content_block_delta'
        delta = [ordered]@{
            type = 'text_delta'
            text = "sensitive VERDICT`n"
        }
    } | ConvertTo-Json -Compress -Depth 5
    [pscustomobject]@{
        type = 'result'
        subtype = 'success'
        is_error = $false
    } | ConvertTo-Json -Compress -Depth 5
    exit 0
}
$text = 'CLAUDE cwd=' + (Get-Location).Path + ' model=' + $model + ' revisao'
[pscustomobject]@{
    type = 'assistant'
    message = [ordered]@{
        content = @([ordered]@{ text = $text })
    }
} | ConvertTo-Json -Compress -Depth 5
[pscustomobject]@{
    type = 'result'
    subtype = 'success'
    is_error = $false
    result = 'NAO_E_VEREDITO'
} | ConvertTo-Json -Compress -Depth 5
exit 0
'@

    # fake-copilot/fake-gemini: argument-based; the adapter invokes them via `& `$exe @args` (pwsh
    # runner), so a DIRECT .ps1 avoids re-parsing cmd %* with a multi-line prompt. Responds to
    # --version/--help and, on execution, emits the JSON each adapter parses. cwd with forward
    # slashes for valid JSON.
    $fakeCopilot = Join-Path $tmp 'fake-copilot.ps1'
    @'
$model = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--model') { $model = [string]$args[$i + 1] } }
if ($args -contains '--version') { '1.0.12'; exit 0 }
if ($args -contains '--help') {
    '--prompt --output-format --stream --no-custom-instructions --disable-builtin-mcps --available-tools --allow-all-tools --model'
    exit 0
}
$c = 'COPILOT cwd=' + (Get-Location).Path.Replace('\', '/') + ' model=' + $model + ' revisao'
'{"type":"assistant.message","data":{"content":"' + $c + '"}}'
'{"type":"result","exitCode":0}'
exit 0
'@ | Set-Content -LiteralPath $fakeCopilot -Encoding utf8

    $fakeGemini = Join-Path $tmp 'fake-gemini.ps1'
    @'
$model = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--model') { $model = [string]$args[$i + 1] } }
if ($args -contains '--version') { '0.35.3'; exit 0 }
if ($args -contains '--help') { '--prompt --approval-mode --output-format --model'; exit 0 }
$c = 'GEMINI cwd=' + (Get-Location).Path.Replace('\', '/') + ' model=' + $model + ' revisao'
'{"response":"' + $c + '"}'
exit 0
'@ | Set-Content -LiteralPath $fakeGemini -Encoding utf8

    # fake-antigravity: argument-based like Gemini/Copilot; --help must expose -p/--print and --mode
    # (Resolve-AntigravityExe's contract). Response in agy's {status,response} envelope.
    $fakeAntigravity = Join-Path $tmp 'fake-antigravity.ps1'
    @'
$model = ''
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '--model') { $model = [string]$args[$i + 1] } }
if ($args -contains '--version') { 'agy 1.1.19'; exit 0 }
if ($args -contains '--help') {
    'Usage of agy: -p Run a prompt --mode Set agent mode --output-format json --model'
    exit 0
}
$args -join ' ' | Add-Content -LiteralPath (Join-Path $PSScriptRoot 'antigravity.calls.log') -Encoding utf8
$joined = $args -join ' '
if ($joined -match 'FORCE_AGY_QUOTA') {
    # Write-Output (stdout): the PowerShell runner's `2>` does not capture [Console]::Error from a direct .ps1.
    Write-Output 'Individual quota reached for forced panel self-test'
    exit 1
}
$c = 'AGY cwd=' + (Get-Location).Path.Replace('\', '/') + ' model=' + $model + ' revisao'
(@{ status = 'SUCCESS'; response = $c } | ConvertTo-Json -Compress)
exit 0
'@ | Set-Content -LiteralPath $fakeAntigravity -Encoding utf8

    # Fake-exe map (file) — active backends (canonical list in skills/mimir-delegate/SKILL.md)
    $exeMapFile = Join-Path $tmp 'exemap.json'
    ([ordered]@{
        opencode      = $fakeOcCmd
        codex         = $fakeCxCmd
        'claude-code' = $fakeClCmd
        copilot       = $fakeCopilot
        gemini        = $fakeGemini
        antigravity   = $fakeAntigravity
    } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $exeMapFile -Encoding utf8

    # synthetic opencode config (loopback for ollama; used only where the gate consults config)
    $ocCfg = Join-Path $tmp 'opencode.json'
    @'
{ "provider": { "ollama": { "options": { "baseURL": "http://127.0.0.1:11434/v1" } } } }
'@ | Set-Content -LiteralPath $ocCfg -Encoding utf8

    # synthetic codex config.toml (default openai/gpt-5.5)
    $cxCfg = Join-Path $tmp 'config.toml'
    @'
model = "gpt-5.5"
'@ | Set-Content -LiteralPath $cxCfg -Encoding utf8
    $cxCfgMissing = Join-Path $tmp 'nope-config.toml'   # does NOT exist ('no config' case)

    # synthetic policy: openai/* allow-external (for allow paths in kb-sensitive)
    $pol = Join-Path $tmp 'llm-delegation-policy.json'
    @'
{ "schemaVersion": 1, "defaultExternal": "ask", "models": { "openai/*": "allow-external" } }
'@ | Set-Content -LiteralPath $pol -Encoding utf8

    $polAnthropic = Join-Path $tmp 'llm-delegation-policy-anthropic.json'
    @'
{ "schemaVersion": 1, "defaultExternal": "ask", "models": { "anthropic/*": "allow-external" } }
'@ | Set-Content -LiteralPath $polAnthropic -Encoding utf8

    $polAntigravity = Join-Path $tmp 'llm-delegation-policy-antigravity.json'
    @'
{ "schemaVersion": 1, "defaultExternal": "ask", "models": { "antigravity/*": "allow-external" } }
'@ | Set-Content -LiteralPath $polAntigravity -Encoding utf8

    # manuscript (accents)
    $manuscript = Join-Path $tmp 'manuscript-input.md'
    @'
# Manuscrito de teste

Conteúdo com acentuação pt-BR: revisão, dedução, ação. Avalie e emita parecer.  # lang-allow: pt-BR payload that verifies accent preservation
'@ | Set-Content -LiteralPath $manuscript -Encoding utf8

    # ---------------------------------------------------------------------------------------
    # Invocation helper (child process, stdout/stderr split into files)
    # ---------------------------------------------------------------------------------------
    $defaultClaudeCircuitRoot = Join-Path $tmp 'claude-circuit'
    function Invoke-Harness {
        param(
            [Parameter(Mandatory)] [object[]] $Reviewers,
            [string] $Sensitivity = 'public',
            [hashtable] $Extra = @{},
            [switch] $NoRoundId,
            [switch] $NoExeMap,
            [switch] $UseManuscriptText,
            [switch] $OmitManuscriptSource,
            [switch] $BothManuscriptSources,
            [AllowEmptyString()] [string] $ManuscriptText = ''
        )
        $rid = [guid]::NewGuid().ToString('N')
        $revFile = Join-Path $tmp "rev-$rid.json"
        (@($Reviewers) | ConvertTo-Json -Depth 8 -AsArray) | Set-Content -LiteralPath $revFile -Encoding utf8
        $oFile = Join-Path $tmp "out-$rid.txt"
        $eFile = Join-Path $tmp "err-$rid.txt"

        $argList = @(
            '-NoProfile', '-File', $harness,
            '-ReviewersJson', $revFile,
            '-PayloadSensitivity', $Sensitivity,
            '-TempDir', $ledgerRoot
        )
        if ($OmitManuscriptSource) {
            # Intentional: exercises structured validation of a missing source.
        } elseif ($BothManuscriptSources) {
            $argList += @('-ManuscriptPath', $manuscript, '-ManuscriptText', $ManuscriptText)
        } elseif ($UseManuscriptText) {
            $argList += @('-ManuscriptText', $ManuscriptText)
        } else {
            $argList += @('-ManuscriptPath', $manuscript)
        }
        if (-not $NoRoundId) { $argList += @('-RoundId', $rid) }
        if (-not $NoExeMap) { $argList += @('-BackendExeMap', $exeMapFile) }
        if (-not $Extra.ContainsKey('ClaudeCircuitStateRoot')) { $argList += @('-ClaudeCircuitStateRoot', $defaultClaudeCircuitRoot) }
        foreach ($k in $Extra.Keys) { $argList += @("-$k", [string]$Extra[$k]) }

        $p = Start-Process -FilePath 'pwsh' -ArgumentList $argList -NoNewWindow -PassThru `
            -RedirectStandardOutput $oFile -RedirectStandardError $eFile
        [void]$p.WaitForExit(180000)
        $stdout = Get-Content -LiteralPath $oFile -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $eFile -Raw -Encoding utf8 -ErrorAction SilentlyContinue
        if ($null -eq $stdout) { $stdout = '' }
        if ($null -eq $stderr) { $stderr = '' }
        $json = $null
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { try { $json = $stdout | ConvertFrom-Json } catch { } }
        return [pscustomobject]@{
            stdout    = $stdout
            stderr    = $stderr
            exit      = $p.ExitCode
            json      = $json
            roundId   = $rid
            ledgerDir = Join-Path $ledgerRoot $rid
        }
    }

    # =======================================================================================
    # 1) EFFECTIVE MODEL + FAIL-CLOSEDS
    # =======================================================================================
    # opencode without model -> uses the INPUT targetModelKey (same value to gate and adapter)
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/no-model'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True ($null -ne $r.json) 'opencode without model: should emit a summary'
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'responded') "opencode without model+public: expected responded; got $($rv.state)"
    Assert-True ($rv.effectiveModel -eq 'openai/no-model') "opencode without model: effectiveModel should be the input targetModelKey; got '$($rv.effectiveModel)'"

    # opencode without model AND without targetModelKey -> error
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; invokeArgs = @{} }) -Sensitivity 'public'
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'error') "opencode without model and without targetModelKey: expected error; got $($rv.state)"

    # unknown backend -> defensive error with an English reason
    $r = Invoke-Harness -Reviewers @(@{ backend = 'no-such-backend'; targetModelKey = 'openai/gpt-5.6'; invokeArgs = @{} }) -Sensitivity 'public'
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'error' -and [string]$rv.reason -match "unknown backend: 'no-such-backend'") "unknown backend: expected error with an English reason; got state=$($rv.state) reason=$($rv.reason)"

    # codex without model WITH config -> the gate without -Model returns targetModelKey; the harness derives the last segment
    $r = Invoke-Harness -Reviewers @(@{ backend = 'codex'; invokeArgs = @{} }) `
        -Sensitivity 'kb-sensitive' -Extra @{ CodexConfigPath = $cxCfg }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.effectiveModel -eq 'gpt-5.5') "codex without model+config: effectiveModel should be 'gpt-5.5' (bare); got '$($rv.effectiveModel)'"
    Assert-True ($rv.targetModelKey -eq 'openai/gpt-5.5') "codex without model+config: targetModelKey should be 'openai/gpt-5.5'; got '$($rv.targetModelKey)'"
    Assert-True ($rv.state -eq 'gateAsk') "codex without model+config kb-sensitive without policy: expected gateAsk; got $($rv.state)"

    # codex without model WITHOUT config -> fail-closed error
    $r = Invoke-Harness -Reviewers @(@{ backend = 'codex'; invokeArgs = @{} }) `
        -Sensitivity 'kb-sensitive' -Extra @{ CodexConfigPath = $cxCfgMissing }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'error') "codex without model and without config: expected error; got $($rv.state)"

    # claude-code/copilot/gemini/antigravity without model -> error
    foreach ($b in @('claude-code', 'copilot', 'gemini', 'antigravity')) {
        $r = Invoke-Harness -Reviewers @(@{ backend = $b; invokeArgs = @{} }) -Sensitivity 'public'
        $rv = Get-Reviewer $r.json 0
        Assert-True ($rv.state -eq 'error') "$b without model: expected fail-closed error; got $($rv.state)"
        Assert-True ($null -eq $rv.effectiveModel) "$b without model: effectiveModel should be null"
    }

    # =======================================================================================
    # 2) CODEX GATE WITH OSS (-Oss/-LocalProvider reach the gate -> local -> allow -> dispatches)
    # =======================================================================================
    # explicit -Cd to satisfy the fail-closed (codex is cd-capable in kb-sensitive, even with a local model)
    $r = Invoke-Harness -Reviewers @(@{ backend = 'codex'; invokeArgs = @{ model = 'qwen2.5-coder'; oss = $true; localProvider = 'ollama' } }) `
        -Sensitivity 'kb-sensitive' -Extra @{ CodexConfigPath = $cxCfgMissing; Cd = $tmp }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.gateVerdict -eq 'allow') "codex oss local kb-sensitive: gate should return allow (oss/localProvider reached the gate); got '$($rv.gateVerdict)'"
    Assert-True ($rv.state -eq 'responded') "codex oss local: should dispatch and respond via the fake; got $($rv.state)"

    # =======================================================================================
    # 3) GENERAL GATE: kb-sensitive fail-closed without policy; a gate that THROWS
    # =======================================================================================
    # external claude-code kb-sensitive without policy -> ask
    $r = Invoke-Harness -Reviewers @(@{ backend = 'claude-code'; invokeArgs = @{ model = 'claude-opus-4-8' } }) -Sensitivity 'kb-sensitive'
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'gateAsk') "claude-code kb-sensitive without policy: expected gateAsk; got $($rv.state)"

    # a gate that THROWS: a nonexistent -KbWorkspaceRoot makes the policy resolver throw (the gate does not catch it)
    $ghost = Join-Path $tmp 'missing-folder-xyz'
    $r = Invoke-Harness -Reviewers @(@{ backend = 'claude-code'; invokeArgs = @{ model = 'claude-opus-4-8' } }) `
        -Sensitivity 'public' -Extra @{ KbWorkspaceRoot = $ghost }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'error') "gate that throws: expected error; got $($rv.state)"
    Assert-True ($null -eq $rv.gateVerdict) "gate that throws: gateVerdict should be null"
    Assert-True ($null -ne $r.json) 'gate that throws: the harness should still emit a summary'

    # =======================================================================================
    # 4) OPENCODE IN KB-SENSITIVE -> unavailable (no gate/adapter); fake NOT invoked
    # =======================================================================================
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'ollama-cloud/x'; invokeArgs = @{ model = 'ollama-cloud/x' } }) `
        -Sensitivity 'kb-sensitive'
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'unavailable') "opencode kb-sensitive: expected unavailable; got $($rv.state)"
    Assert-True ($null -eq $rv.gateVerdict) 'opencode kb-sensitive: gateVerdict should be null'
    Assert-True ([int]$r.json.unavailableCount -ge 1) 'opencode kb-sensitive: unavailableCount >= 1'
    Assert-True ($null -ne $rv.statePath) 'opencode kb-sensitive: should have .state.txt in the ledger'

    # =======================================================================================
    # 5) SPLAT + CONTAINMENT (per-backend) — no dispatch (kb-sensitive -> gateAsk)
    # =======================================================================================
    # claude-code: permissionMode/tools and internal keys -> securityBlockedArgs; maxTurns (no such adapter parameter) -> droppedArgs
    $r = Invoke-Harness -Reviewers @(@{ backend = 'claude-code'; invokeArgs = @{
                    model = 'claude-opus-4-8'
                    permissionMode = 'bypassPermissions'
                    tools = 'Bash'
                    maxTurns = 9
                    SidecarPath = 'C:\tmp\roubar-sidecar.json'
                    RetentionMode = 'public'
                    TempDir = 'C:\tmp\roubar-ledger'
                    CircuitStateRoot = 'C:\tmp\roubar-circuito'
                    ClaudeExe = 'C:\tmp\fake-claude.exe'
                    MessagePath = 'C:\tmp\outro-prompt.txt'
                } }) -Sensitivity 'kb-sensitive'
    $rv = Get-Reviewer $r.json 0
    $sb = @($rv.securityBlockedArgs)
    Assert-True (($sb -contains 'permissionMode') -and ($sb -contains 'tools')) "claude-code containment: securityBlockedArgs should contain permissionMode/tools; got [$($sb -join ',')]"
    Assert-True (($sb -notcontains 'maxTurns') -and (@($rv.droppedArgs) -contains 'maxTurns')) "claude-code maxTurns: should be a dropped key, not a containment key; blocked=[$($sb -join ',')] dropped=[$(@($rv.droppedArgs) -join ',')]"
    foreach ($blockedInternalArg in @('SidecarPath', 'RetentionMode', 'TempDir', 'CircuitStateRoot', 'ClaudeExe', 'MessagePath')) {
        Assert-True ($sb -contains $blockedInternalArg) "claude-code internal keys: securityBlockedArgs should contain $blockedInternalArg; got [$($sb -join ',')]"
    }

    # opencode: agent -> securityBlockedArgs (even in kb-sensitive: classification precedes unavailable)
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'ollama-cloud/x'; invokeArgs = @{ model = 'ollama-cloud/x'; agent = 'build' } }) -Sensitivity 'kb-sensitive'
    $rv = Get-Reviewer $r.json 0
    Assert-True (@($rv.securityBlockedArgs) -contains 'agent') "opencode containment: securityBlockedArgs should contain agent"

    # gemini approvalMode=plan -> droppedArgs ; approvalMode=yolo -> securityBlockedArgs
    $r = Invoke-Harness -Reviewers @(
        @{ backend = 'gemini'; invokeArgs = @{ model = 'gemini-3-flash-preview'; approvalMode = 'plan' } },
        @{ backend = 'gemini'; invokeArgs = @{ model = 'gemini-3-flash-preview'; approvalMode = 'yolo' } }
    ) -Sensitivity 'kb-sensitive'
    $rvPlan = Get-Reviewer $r.json 0
    $rvYolo = Get-Reviewer $r.json 1
    Assert-True (@($rvPlan.droppedArgs) -contains 'approvalMode') 'gemini approvalMode=plan -> droppedArgs'
    Assert-True (@($rvPlan.securityBlockedArgs).Count -eq 0) 'gemini approvalMode=plan -> NOT securityBlocked'
    Assert-True (@($rvYolo.securityBlockedArgs) -contains 'approvalMode') 'gemini approvalMode=yolo -> securityBlockedArgs'

    # antigravity public-review: no profile/cwd/containment override or internal seam gets through.
    $r = Invoke-Harness -Reviewers @(@{ backend = 'antigravity'; invokeArgs = @{
        model = 'gemini-3.6-flash-high'; mode = 'plan'; profile = 'public-review'; cd = $tmp
        agent = 'custom'; approvalMode = 'plan'; scratchPath = $tmp; receiptPath = 'x.json'
        simulateCleanupFailure = 'failed'; antigravityExe = 'x'; message = 'x'; messagePath = 'x'
    } }) -Sensitivity 'public'
    $rvAgBlocked = Get-Reviewer $r.json 0
    $agyBlocked = @($rvAgBlocked.securityBlockedArgs)
    foreach ($key in @('mode','profile','cd','agent','approvalMode','scratchPath','receiptPath','simulateCleanupFailure','antigravityExe','message','messagePath')) {
        Assert-True ($agyBlocked -contains $key) "antigravity containment: $key must end up in securityBlockedArgs"
    }

    # codex / copilot: an unknown key -> droppedArgs ; a non-codex backend with profile -> droppedArgs
    $r = Invoke-Harness -Reviewers @(
        @{ backend = 'codex'; invokeArgs = @{ model = 'gpt-5.5'; foobar = 'x' } },
        @{ backend = 'copilot'; invokeArgs = @{ model = 'gpt-5-mini'; foobar = 'y' } },
        @{ backend = 'claude-code'; invokeArgs = @{ model = 'claude-opus-4-8'; profile = 'p' } }
    ) -Sensitivity 'kb-sensitive' -Extra @{ CodexConfigPath = $cxCfg }
    Assert-True (@((Get-Reviewer $r.json 0).droppedArgs) -contains 'foobar') 'codex unknown key -> droppedArgs'
    Assert-True (@((Get-Reviewer $r.json 1).droppedArgs) -contains 'foobar') 'copilot unknown key -> droppedArgs'
    Assert-True (@((Get-Reviewer $r.json 2).droppedArgs) -contains 'profile') 'claude-code with profile -> droppedArgs (profile is codex-only)'

    # =======================================================================================
    # 5b) DURABLE CODEX CAPTURE IN THE PANEL: Bound splat + droppedArgs + strip MIMIR_CODEX_
    # =======================================================================================
    # (a)+(b) TempDir Bound at %TEMP%\mimir-panel-codex\<RoundId>\<NN> (outside the ledger/Cd),
    # with a subdirectory PER REVIEWER so recoveredAfterTimeout pairing is not ambiguous
    # when two codex primary reviewers return the same text in the same round;
    # invokeArgs.tempdir/retentionMode -> droppedArgs. Bound wins.
    $stolenCodexLedger = Join-Path $tmp 'roubar-codex-ledger'
    [IO.Directory]::CreateDirectory($stolenCodexLedger) | Out-Null
    $r = Invoke-Harness -Reviewers @(@{
            backend = 'codex'
            invokeArgs = @{
                model          = 'gpt-5.5'
                tempdir        = $stolenCodexLedger
                retentionMode  = 'kb-sensitive'
            }
        }) -Sensitivity 'public' -Extra @{ CodexConfigPath = $cxCfg }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'responded') "codex durable splat: expected responded; got $($rv.state)"
    $droppedCodex = @($rv.droppedArgs)
    Assert-True ($droppedCodex -contains 'tempdir') "codex durable: tempdir should fall into droppedArgs; got [$($droppedCodex -join ',')]"
    Assert-True ($droppedCodex -contains 'retentionMode') "codex durable: retentionMode should fall into droppedArgs; got [$($droppedCodex -join ',')]"
    $secCodex = @($rv.securityBlockedArgs)
    Assert-True ($secCodex -notcontains 'tempdir' -and $secCodex -notcontains 'retentionMode') "codex durable: tempdir/retentionMode are NOT securityBlockedArgs; got [$($secCodex -join ',')]"
    Assert-True (@(Get-ChildItem -LiteralPath $stolenCodexLedger -Filter '*.request.json' -File -ErrorAction SilentlyContinue).Count -eq 0) 'codex durable: invokeArgs.tempdir must NOT receive request.json (Bound wins)'
    $codexRoundDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'mimir-panel-codex') ([string]$r.json.roundId)
    Assert-True (Test-Path -LiteralPath $codexRoundDir -PathType Container) "codex durable: TempDir Bound at mimir-panel-codex/<RoundId>; missing $codexRoundDir"
    $codexCaptureDir = Join-Path $codexRoundDir '00'
    Assert-True (Test-Path -LiteralPath $codexCaptureDir -PathType Container) "codex durable: capture should sit in the PER-REVIEWER subdirectory <RoundId>\00; missing $codexCaptureDir"
    Assert-True (@(Get-ChildItem -LiteralPath $codexRoundDir -Filter '*.request.json' -File -ErrorAction SilentlyContinue).Count -eq 0) 'codex durable: request.json cannot sit loose at the round root (pairing ambiguity between primary reviewers)'
    $boundReqs = @(Get-ChildItem -LiteralPath $codexCaptureDir -Filter '*.request.json' -File -ErrorAction SilentlyContinue)
    $boundMsgs = @(Get-ChildItem -LiteralPath $codexCaptureDir -Filter '*.lastmsg.txt' -File -ErrorAction SilentlyContinue)
    Assert-True ($boundReqs.Count -ge 1) "codex durable splat TempDir: request.json under Bound mimir-panel-codex; got $($boundReqs.Count)"
    Assert-True ($boundMsgs.Count -ge 1) 'codex durable RetentionMode=public Bound: lastmsg stays in the capture dir (invokeArgs kb-sensitive was dropped)'
    Assert-True (@(Get-ChildItem -LiteralPath $r.ledgerDir -Filter '*.request.json' -File -ErrorAction SilentlyContinue).Count -eq 0) 'codex durable: request.json does NOT stay in the ledger (only verdict/error)'
    $cap = (Get-Content -LiteralPath $boundReqs[0].FullName -Raw -Encoding utf8 | ConvertFrom-Json).captureOutcome
    Assert-True ($cap -eq 'success') "codex durable: captureOutcome=success; got '$cap'"

    # (c) strip MIMIR_CODEX_ in Parallel: a path/RoundId with 429 in the sentinels does NOT become quota
    $prevForceTimeout = $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT
    $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT = '1'
    try {
        $rid429 = 'panel-strip-429-' + [guid]::NewGuid().ToString('N')
        $r = Invoke-Harness -Reviewers @(@{ backend = 'codex'; invokeArgs = @{ model = 'gpt-5.5'; timeoutSec = 2 } }) `
            -Sensitivity 'public' -NoRoundId -Extra @{ RoundId = $rid429; CodexConfigPath = $cxCfg }
        $rv = Get-Reviewer $r.json 0
        Assert-True ($rv.state -eq 'timeout') "codex strip 429: expected timeout (not quota); got $($rv.state)"
        Assert-True ([int]$r.json.quotaCount -eq 0) "codex strip 429: quotaCount should be 0; got $($r.json.quotaCount)"
        Assert-True ($null -ne $rv.errorPath) 'codex strip 429: should write .error.txt with the complete errText'
        $errLedger = Get-Content -LiteralPath $rv.errorPath -Raw -Encoding utf8
        Assert-True ($errLedger -match '429') 'codex strip 429: errorPath preserves path/429 (complete errText)'
        Assert-True ($errLedger -match 'exceeded' -and $errLedger -match 'was terminated') 'codex strip 429: timeout evidence in errorPath'
    } finally {
        if ($null -eq $prevForceTimeout) {
            Remove-Item Env:\MIMIR_TEST_CODEX_FORCE_TIMEOUT -ErrorAction SilentlyContinue
        } else {
            $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT = $prevForceTimeout
        }
    }

    # (d) GAP-2: invalid timeoutSec -> error only for that reviewer; the other responds
    $r = Invoke-Harness -Reviewers @(
        @{ backend = 'codex'; invokeArgs = @{ model = 'gpt-5.5'; timeoutSec = '600s' } },
        @{ backend = 'codex'; invokeArgs = @{ model = 'gpt-5.5' } }
    ) -Sensitivity 'public' -Extra @{ CodexConfigPath = $cxCfg }
    Assert-True ((Get-Reviewer $r.json 0).state -eq 'error') "GAP-2: timeoutSec '600s' -> error; got $((Get-Reviewer $r.json 0).state)"
    Assert-True ((Get-Reviewer $r.json 0).reason -match 'timeoutSec invalid:') 'GAP-2: reason cites the invalid timeoutSec'
    Assert-True ((Get-Reviewer $r.json 1).state -eq 'responded') "GAP-2: the second reviewer should not go down with the panel; got $((Get-Reviewer $r.json 1).state)"
    Assert-True ([int]$r.json.respondedCount -eq 1 -and [int]$r.json.errorCount -eq 1) 'GAP-2: the panel completes with 1 responded + 1 error'

    # =======================================================================================
    # 6) PARALLELISM: occupancy <= OllamaConcurrency for ollama-cloud; others free; a throw does not abort
    # =======================================================================================
    Set-Content -LiteralPath $concLog -Value '' -NoNewline -Encoding utf8
    $revs = @()
    1..5 | ForEach-Object { $revs += @{ backend = 'opencode'; targetModelKey = "ollama-cloud/sleep-$_"; invokeArgs = @{} } }
    1..5 | ForEach-Object { $revs += @{ backend = 'opencode'; targetModelKey = "openai/sleep-$_"; invokeArgs = @{} } }
    $r = Invoke-Harness -Reviewers $revs -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg; OllamaConcurrency = 2 }
    Assert-True ($null -ne $r.json) 'parallelism: should emit a summary'
    Assert-True ([int]$r.json.respondedCount -eq 10) "parallelism: expected 10 responded; got $($r.json.respondedCount)"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$r.json.ollamaQuotaWarning)) 'parallelism: ollamaQuotaWarning should be present (5 ollama-cloud dispatched in the batch)'
    Assert-True ($r.stderr -match 'ollamaQuotaWarning') 'parallelism: ollamaQuotaWarning should go out via stderr'

    $logLines = @(Get-Content -LiteralPath $concLog -ErrorAction SilentlyContinue | Where-Object { $_ })
    function Get-MaxOverlap {
        param([string[]]$Lines, [string]$Family)
        $events = @()
        foreach ($ln in $Lines) {
            $parts = @($ln -split "`t")
            if ($parts.Count -lt 3 -or $parts[0] -ne $Family) { continue }
            if ($parts[1] -eq 'ENTER') { $events += [pscustomobject]@{ t = [long]$parts[2]; d = 1 } }
            elseif ($parts[1] -eq 'EXIT') { $events += [pscustomobject]@{ t = [long]$parts[2]; d = -1 } }
        }
        $sorted = @($events | Sort-Object t, d)   # on a tie, EXIT(-1) before ENTER(+1)
        $cur = 0; $max = 0
        foreach ($e in $sorted) { $cur += $e.d; if ($cur -gt $max) { $max = $cur } }
        return $max
    }
    $ollamaMax = Get-MaxOverlap -Lines $logLines -Family 'ollama-cloud'
    $openaiMax = Get-MaxOverlap -Lines $logLines -Family 'openai'
    Assert-True ($ollamaMax -le 2) "ollama-cloud: max occupancy should be <= 2 (OllamaConcurrency); measured $ollamaMax"
    Assert-True ($openaiMax -ge 3) "openai (no semaphore): occupancy should exceed the ollama ceiling (>=3); measured $openaiMax — signal that the semaphore does NOT limit other providers"

    # a block that throws does not abort the rest: one 'empty' (throws in the adapter -> error) + one responded
    $r = Invoke-Harness -Reviewers @(
        @{ backend = 'opencode'; targetModelKey = 'openai/empty-iso'; invokeArgs = @{} },
        @{ backend = 'opencode'; targetModelKey = 'openai/ok-iso'; invokeArgs = @{} }
    ) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True ((Get-Reviewer $r.json 0).state -eq 'error') 'block that throws: the empty one should become error'
    Assert-True ((Get-Reviewer $r.json 1).state -eq 'responded') 'block that throws: the other reviewer should NOT be aborted'

    # OllamaConcurrency=0 -> validation error (no summary)
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/x'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg; OllamaConcurrency = 0 }
    Assert-True ($r.exit -ne 0) 'OllamaConcurrency=0: validation should fail (exit != 0)'
    Assert-True ($null -eq $r.json) 'OllamaConcurrency=0: should not emit a summary'

    # =======================================================================================
    # 7) NO SINGLE-FLIGHT: empty ollama-cloud in a batch -> error; fake NOT re-invoked; saturation
    # =======================================================================================
    Set-Content -LiteralPath $concLog -Value '' -NoNewline -Encoding utf8
    $r = Invoke-Harness -Reviewers @(
        @{ backend = 'opencode'; targetModelKey = 'ollama-cloud/empty-1'; invokeArgs = @{} },
        @{ backend = 'opencode'; targetModelKey = 'ollama-cloud/empty-2'; invokeArgs = @{} }
    ) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True ((Get-Reviewer $r.json 0).state -eq 'error') 'single-flight: ollama empty-1 -> error'
    Assert-True ((Get-Reviewer $r.json 1).state -eq 'error') 'single-flight: ollama empty-2 -> error'
    Assert-True ([int]$r.json.errorCount -ge 2) 'single-flight: errorCount >= 2'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$r.json.concurrencySaturationWarning)) 'single-flight: concurrencySaturationWarning should be present (2+ ollama in error)'
    Assert-True ($r.stderr -match 'concurrencySaturationWarning') 'single-flight: the saturation warning should go out via stderr'
    # each empty was invoked ONCE (no re-dispatch)
    $logLines = @(Get-Content -LiteralPath $concLog -ErrorAction SilentlyContinue | Where-Object { $_ })
    $entries1 = @($logLines | Where-Object { ($_ -split "`t")[3] -eq 'ollama-cloud/empty-1' -and ($_ -split "`t")[1] -eq 'ENTER' }).Count
    Assert-True ($entries1 -eq 1) "single-flight: the empty-1 fake should be invoked ONCE; measured $entries1"

    # =======================================================================================
    # 8) MECHANICAL CLASSIFICATION: responded for non-empty text even off-task
    # =======================================================================================
    # the fake returns text that is NOT a verdict; the harness does NOT reclassify -> responded
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/offtask'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'responded') "mechanical classification: non-empty off-task text -> responded; got $($rv.state)"
    Assert-True ($null -ne $rv.verdictPath) 'mechanical classification: should write .verdict.txt'
    $vtext = Get-Content -LiteralPath $rv.verdictPath -Raw -Encoding utf8
    Assert-True ($vtext -match 'revisão') 'accents: the verdict text should preserve pt-BR accents (revisão)'  # lang-allow: pt-BR payload that verifies accent preservation

    # =======================================================================================
    # 8b) DISPATCH CLASSIFICATION: quota -> quota; timeout -> timeout
    # =======================================================================================
    # quota: fake-opencode emits a stream error with 402/quota/balance -> the adapter throws BLOCK -> quota
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'ollama-cloud/cota-1'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'quota') "quota: 402/quota/balance on dispatch should become quota; got $($rv.state)"
    Assert-True ([int]$r.json.quotaCount -ge 1) 'quota: quotaCount >= 1'
    Assert-True ($null -ne $rv.statePath) 'quota: should write .state.txt in the ledger'
    $quotaLedger = Get-Content -LiteralPath $rv.statePath -Raw -Encoding utf8
    Assert-True ($quotaLedger -match 'Payment Required' -and $quotaLedger -match 'insufficient coding plan balance' -and $quotaLedger -match '402' -and $quotaLedger -match 'sem quota') 'quota: .state.txt should preserve the raw quota/balance/402 evidence'

    # NOT quota: a generic error containing "exhausted" (network/context) must not become quota. Locks
    # in the regression of the widened $quotaFailurePattern, which classified "retries exhausted" as
    # quota on ALL backends and would send the operator to wait for a cycle reset over a non-quota failure.
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/exausto-1'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'error') "not-quota: 'retries exhausted' should become error, not quota; got $($rv.state)"
    Assert-True ([int]$r.json.quotaCount -eq 0) "not-quota: quotaCount should stay 0; got $($r.json.quotaCount)"

    # timeout: the fake sleeps beyond -TimeoutSec (via invokeArgs.timeoutSec) -> adapter "exceeded...terminated" -> timeout
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/timeout-1'; invokeArgs = @{ timeoutSec = 2 } }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'timeout') "timeout: should classify timeout; got $($rv.state)"
    Assert-True ([int]$r.json.timeoutCount -ge 1) 'timeout: timeoutCount >= 1'
    Assert-True ($null -ne $rv.errorPath) 'timeout: should write .error.txt'

    # =======================================================================================
    # 8d) FALLBACK: auditable activation, skip on success and pre-dispatch divergence
    # =======================================================================================
    $r = Invoke-Harness -Reviewers @(@{
            backend = 'opencode'; targetModelKey = 'openai/primary-ok'; invokeArgs = @{}
            fallbackChain = @(
                @{ backend = 'opencode'; targetModelKey = 'openai/fallback-skip'; invokeArgs = @{ backend = 'opencode'; model = 'openai/fallback-skip' } }
            )
        }) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True (@($r.json.reviewers).Count -eq 2) 'fallback skip: should register primary + fallback.'
    $rv0 = Get-Reviewer $r.json 0
    $rv1 = Get-Reviewer $r.json 1
    Assert-True ($rv0.state -eq 'responded') 'fallback skip: the primary should respond.'
    Assert-True ($rv1.state -eq 'skippedAfterSuccess') "fallback skip: the fallback should end up skippedAfterSuccess; got $($rv1.state)"
    Assert-True ($rv1.countsForDiversity -eq $false) 'fallback skip: skippedAfterSuccess does not count toward diversity.'
    Assert-True ($rv1.fallbackOf -eq 'openai/primary-ok') 'fallback skip: fallbackOf should point to the primary.'

    $r = Invoke-Harness -Reviewers @(@{
            backend = 'opencode'; targetModelKey = 'openai/empty-primary'; invokeArgs = @{}
            fallbackChain = @(
                @{ backend = 'opencode'; targetModelKey = 'openai/fallback-ok'; invokeArgs = @{ backend = 'opencode'; model = 'openai/fallback-ok' } }
            )
        }) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True (@($r.json.reviewers).Count -eq 2) 'fallback activated: should register primary + fallback.'
    $rv0 = Get-Reviewer $r.json 0
    $rv1 = Get-Reviewer $r.json 1
    Assert-True ($rv0.state -eq 'error') 'fallback activated: the empty primary should become error.'
    Assert-True ($rv1.state -eq 'responded') "fallback activated: the fallback should respond; got $($rv1.state)"
    Assert-True ($rv1.attemptRole -eq 'fallback') 'fallback activated: attemptRole=fallback.'
    Assert-True ($rv1.activationReason -eq 'error') 'fallback activated: activationReason should be error.'
    Assert-True ($rv1.countsForDiversity -eq $true) 'a responded fallback should count toward diversity.'

    # =======================================================================================
    # 8e) NATIVE LEAK (V40): orchestrator-native in the harness -> defensive error + suppressed chain
    # =======================================================================================
    Set-Content -LiteralPath $concLog -Value '' -NoNewline -Encoding utf8
    $r = Invoke-Harness -Reviewers @(
        @{
            backend = 'orchestrator-native'
            targetModelKey = 'moonshot/kimi-k3-max'
            harnessModelId = 'kimi-k3-max'
            invokeArgs = @{}
            fallbackChain = @(
                @{ backend = 'opencode'; targetModelKey = 'openai/native-fallback-skip'; invokeArgs = @{ model = 'openai/native-fallback-skip' } }
            )
        },
        @{
            backend = 'opencode'
            targetModelKey = 'openai/parallel-after-native'
            invokeArgs = @{}
        }
    ) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True (@($r.json.reviewers).Count -eq 3) 'native leak: should register the native primary + suppressed fallback + parallel CLI reviewer.'
    $rvNative = Get-Reviewer $r.json 0
    Assert-True ($rvNative.state -eq 'error') "native leak: state should be error; got $($rvNative.state)"
    Assert-True ($rvNative.reason -eq 'orchestrator-native-leaked-to-dispatch') "native leak: expected reason orchestrator-native-leaked-to-dispatch; got '$($rvNative.reason)'"
    Assert-True ($rvNative.dispatchAttempted -eq $false) 'native leak: dispatchAttempted should be false.'
    Assert-True ([int]$rvNative.attempts -eq 0) 'native leak: attempts should be 0.'
    Assert-True ($rvNative.countsForDiversity -eq $false) 'native leak: does not count toward diversity.'
    Assert-True ([int]$rvNative.ledgerIndex -eq 0) 'native leak: ledgerIndex at creation should be 0.'
    Assert-True (@($rvNative.fallbackChain).Count -eq 0) "native leak: the primary's fallbackChain should be empty."
    Assert-True (@($rvNative.suppressedFallbackChain).Count -eq 1) 'native leak: suppressedFallbackChain should preserve the original chain.'
    Assert-True ($rvNative.suppressedFallbackChain[0].targetModelKey -eq 'openai/native-fallback-skip') 'native leak: suppressedFallbackChain should contain the original fallback.'
    $rvNativeSkip = Get-ReviewerByTarget $r.json 'openai/native-fallback-skip'
    Assert-True ($null -ne $rvNativeSkip) 'native leak: a suppressed-fallback record should exist.'
    Assert-True ($rvNativeSkip.state -eq 'skippedByPolicy') "native leak: the fallback should be skippedByPolicy; got $($rvNativeSkip.state)"
    Assert-True ($rvNativeSkip.attemptRole -eq 'fallback') 'native leak: the suppressed record should be attemptRole=fallback.'
    Assert-True ($rvNativeSkip.fallbackSuppressedReason -eq 'primary-native-leaked') "native leak: expected fallbackSuppressedReason primary-native-leaked; got '$($rvNativeSkip.fallbackSuppressedReason)'"
    Assert-True ($rvNativeSkip.fallbackOf -eq 'moonshot/kimi-k3-max') 'native leak: fallbackOf should point to the native primary.'
    Assert-True ($rvNativeSkip.dispatchAttempted -eq $false) 'native leak: the suppressed fallback should not dispatch.'
    $rvParallel = Get-ReviewerByTarget $r.json 'openai/parallel-after-native'
    Assert-True ($rvParallel.state -eq 'responded') "native leak: the parallel CLI reviewer should respond; got $($rvParallel.state)"
    $logLinesLeak = @(Get-Content -LiteralPath $concLog -ErrorAction SilentlyContinue | Where-Object { $_ })
    $parallelEnters = @($logLinesLeak | Where-Object {
        $parts = @($_ -split "`t")
        $parts.Count -ge 4 -and $parts[1] -eq 'ENTER' -and $parts[3] -eq 'openai/parallel-after-native'
    }).Count
    $fallbackEnters = @($logLinesLeak | Where-Object {
        $parts = @($_ -split "`t")
        $parts.Count -ge 4 -and $parts[1] -eq 'ENTER' -and $parts[3] -eq 'openai/native-fallback-skip'
    }).Count
    Assert-True ($parallelEnters -eq 1) "native leak: the parallel CLI reviewer should be invoked once; measured $parallelEnters"
    Assert-True ($fallbackEnters -eq 0) "native leak: the suppressed fallback should not invoke the adapter; measured $fallbackEnters"

    $r = Invoke-Harness -Reviewers @(
        @{
            backend = 'orchestrator-native'
            targetModelKey = 'moonshot/kimi-k3-max'
            harnessModelId = 'kimi-k3-max'
            invokeArgs = @{}
        }
    ) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True (@($r.json.reviewers).Count -eq 1) 'native leak without fallback: should register only the primary.'
    $rvNativeOnly = Get-Reviewer $r.json 0
    Assert-True ($rvNativeOnly.reason -eq 'orchestrator-native-leaked-to-dispatch') 'native leak without fallback: expected the leak reason.'
    Assert-True (@($rvNativeOnly.suppressedFallbackChain).Count -eq 0) 'native leak without fallback: suppressedFallbackChain should be empty.'

    $r = Invoke-Harness -Reviewers @(@{
            backend = 'opencode'; targetModelKey = 'openai/empty-primary-timeout-fallback'; invokeArgs = @{}
            fallbackChain = @(
                @{ backend = 'opencode'; targetModelKey = 'openai/timeout-fallback'; invokeArgs = @{ backend = 'opencode'; model = 'openai/timeout-fallback'; timeoutSec = 2 } }
            )
        }) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    Assert-True (@($r.json.reviewers).Count -eq 2) 'fallback timeout: should register primary + fallback.'
    $rv1 = Get-Reviewer $r.json 1
    Assert-True ($rv1.state -eq 'timeout') "fallback timeout: the fallback should register timeout; got $($rv1.state)"
    Assert-True ($rv1.countsForDiversity -eq $false) 'fallback timeout must not count toward diversity.'

    $harnessText = Get-Content -LiteralPath $harness -Raw -Encoding utf8
    Assert-True ($harnessText -match 'Get-FallbackDispatcherTimeoutMs') "fallback dispatcher: the child process's timeout must derive from invokeArgs.timeoutSec."
    $parserErrors = $null
    $tokens = $null
    $harnessAst = [System.Management.Automation.Language.Parser]::ParseFile($harness, [ref]$tokens, [ref]$parserErrors)
    Assert-True (@($parserErrors).Count -eq 0) "fallback dispatcher: the harness should parse without error; errors=$(@($parserErrors).Count)"
    $functionAsts = @($harnessAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $getPropAst = @($functionAsts | Where-Object { $_.Name -eq 'Get-Prop' })[0]
    $timeoutAst = @($functionAsts | Where-Object { $_.Name -eq 'Get-FallbackDispatcherTimeoutMs' })[0]
    Assert-True ($null -ne $getPropAst -and $null -ne $timeoutAst) 'fallback dispatcher: the Get-Prop/Get-FallbackDispatcherTimeoutMs functions should exist.'
    $timeoutMapAssign = @($harnessAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text.Trim() -eq '$AdapterDefaultTimeoutSec'
    }, $true))[0]
    Assert-True ($null -ne $timeoutMapAssign) 'fallback dispatcher: the $AdapterDefaultTimeoutSec declaration should exist in the AST.'
    $timeoutProbe = @"
`$script:AdapterDefaultTimeoutSec = $($timeoutMapAssign.Right.Extent.Text)
$($getPropAst.Extent.Text)
$($timeoutAst.Extent.Text)
[pscustomobject]@{
    ClaudeDefault = Get-FallbackDispatcherTimeoutMs -Backend 'claude-code' -InvokeArgs ([pscustomobject]@{})
    OpenCodeDefault = Get-FallbackDispatcherTimeoutMs -Backend 'opencode' -InvokeArgs ([pscustomobject]@{})
    SmallExplicit = Get-FallbackDispatcherTimeoutMs -Backend 'claude-code' -InvokeArgs ([pscustomobject]@{ timeoutSec = 2 })
    InvalidClaude = Get-FallbackDispatcherTimeoutMs -Backend 'claude-code' -InvokeArgs ([pscustomobject]@{ timeoutSec = 'abc' })
}
"@
    $timeoutResult = & ([scriptblock]::Create($timeoutProbe))
    Assert-True ([int]$timeoutResult.ClaudeDefault -eq 1320000) "fallback dispatcher: claude-code without timeoutSec should wait 1200s+120s; got $($timeoutResult.ClaudeDefault)"
    Assert-True ([int]$timeoutResult.InvalidClaude -eq 1320000) "fallback dispatcher: claude-code with an invalid timeoutSec should fall back to the 1200s+120s default; got $($timeoutResult.InvalidClaude)"
    Assert-True ([int]$timeoutResult.OpenCodeDefault -eq 2520000) "fallback dispatcher: opencode without timeoutSec should wait 2*1200s+120s; got $($timeoutResult.OpenCodeDefault)"
    Assert-True ([int]$timeoutResult.SmallExplicit -eq 180000) "fallback dispatcher: a small timeoutSec should keep the conservative 180s floor; got $($timeoutResult.SmallExplicit)"
    Assert-True ($harnessText -match "Get-FallbackDispatcherTimeoutMs\s+-Backend") 'fallback dispatcher: the real call should pass the backend to pick the right default.'
    Assert-True ($harnessText -match "extraSplat\.ContainsKey\('TimeoutSec'\)") 'panel: TimeoutSec from AdapterDefaultTimeoutSec should be injected into the splat when invokeArgs omits timeoutSec'
    Assert-True ($harnessText -notmatch "backend -in @\('codex', 'opencode'\)") 'panel: TimeoutSec injection must not stay restricted to codex/opencode'
    Assert-True ($harnessText -match 'invokeArgs\.timeoutSec invalid:') 'panel: an invalid timeoutSec should become a local error (GAP-2)'
    Assert-True ($harnessText -match 'recoveredAfterTimeout') 'panel: should project recoveredAfterTimeout (GAP-3)'
    Assert-True ($harnessText -match "codexRetention -ne 'kb-sensitive'") 'panel: in kb-sensitive, pairing by lastmsg is impossible (the adapter deletes it on success) — recoveredAfterTimeout should stay $null, never a silent false'
    Assert-True ($harnessText -notmatch 'WaitForExit\(180000\)') 'fallback dispatcher: there must be no fixed 180000ms timeout on the child process.'
    Assert-True ($harnessText -match 'Get-CurrentPowerShellExecutable') 'fallback dispatcher: the child process must use the current/validated PowerShell executable, not rely on a raw pwsh on PATH.'
    Assert-True ($harnessText -notmatch "Start-Process\s+-FilePath\s+'pwsh'") 'fallback dispatcher: must not resolve a raw pwsh via PATH.'
    Assert-True ($harnessText -notmatch "return\s+'pwsh'") 'fallback dispatcher: must not have a silent fallback to a raw pwsh on PATH.'

    # =======================================================================================
    # AST Guard: strict key parity across the dispatcher's 5 maps, ValidateSet and preferences
    # =======================================================================================
    function Get-AstHashtableKeys {
        param($Ast, [string]$VarName)
        $assign = @($Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text.Trim() -eq "`$$VarName"
        }, $true))[0]
        Assert-True ($null -ne $assign) "AST Guard: `$$VarName declaration not found in the AST"
        $ht = if ($assign.Right -is [System.Management.Automation.Language.HashtableAst]) {
            $assign.Right
        } else {
            @($assign.Right.FindAll({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true))[0]
        }
        Assert-True ($null -ne $ht) "AST Guard: HashtableAst not found for `$$VarName"
        $keys = [System.Collections.Generic.List[string]]::new()
        foreach ($pair in $ht.KeyValuePairs) {
            $keys.Add($pair.Item1.Extent.Text.Trim("'", '"', ' '))
        }
        return @($keys)
    }

    function Get-AstBackendValidateSet {
        param([string]$FilePath)
        $pErrors = $null
        $pTokens = $null
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$pTokens, [ref]$pErrors)
        Assert-True (@($pErrors).Count -eq 0) "AST Guard: error parsing $FilePath"
        $paramAst = @($fileAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ParameterAst] -and
            $node.Name.VariablePath.UserPath -eq 'Backend'
        }, $true))[0]
        Assert-True ($null -ne $paramAst) "AST Guard: Backend parameter not found in $FilePath"
        $valSetAttr = @($paramAst.Attributes | Where-Object {
            $_.TypeName.FullName -eq 'ValidateSet' -or $_.TypeName.Name -eq 'ValidateSet'
        })[0]
        Assert-True ($null -ne $valSetAttr) "AST Guard: ValidateSet attribute not found on the Backend parameter in $FilePath"
        $vals = [System.Collections.Generic.List[string]]::new()
        foreach ($arg in $valSetAttr.PositionalArguments) {
            $vals.Add($arg.Extent.Text.Trim("'", '"', ' '))
        }
        return @($vals)
    }

    function Get-AstArrayAssignmentValues {
        param([string]$FilePath, [string]$VarName)
        $pErrors = $null
        $pTokens = $null
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$pTokens, [ref]$pErrors)
        Assert-True (@($pErrors).Count -eq 0) "AST Guard: error parsing $FilePath"
        $assign = @($fileAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left.Extent.Text.Trim() -eq "`$$VarName"
        }, $true))[0]
        Assert-True ($null -ne $assign) "AST Guard: `$$VarName declaration not found in $FilePath"
        $vals = [System.Collections.Generic.List[string]]::new()
        $elements = @($assign.Right.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true))
        foreach ($el in $elements) {
            $vals.Add($el.Value)
        }
        return @($vals)
    }

    $mapAdapterScriptKeys = @(Get-AstHashtableKeys $harnessAst 'AdapterScript')
    $canonicalSorted = @($mapAdapterScriptKeys | Sort-Object)
    Assert-True ($canonicalSorted.Count -eq 6) "AST Guard: expected exactly 6 canonical backends; got $($canonicalSorted.Count)"

    $authValidateSet = @(Get-AstBackendValidateSet (Join-Path $scriptsDir 'Resolve-LlmDelegateAuthorization.ps1'))
    $authDispatchOnly = @($authValidateSet | Where-Object { $_ -ne 'orchestrator-native' } | Sort-Object)

    $collectionsToCompare = [ordered]@{
        'Invoke-LlmDelegatePanelDispatch.ps1 ($ExeParam)'                = @(Get-AstHashtableKeys $harnessAst 'ExeParam' | Sort-Object)
        'Invoke-LlmDelegatePanelDispatch.ps1 ($ContentionKeys)'          = @(Get-AstHashtableKeys $harnessAst 'ContentionKeys' | Sort-Object)
        'Invoke-LlmDelegatePanelDispatch.ps1 ($AdapterDefaultTimeoutSec)'= @(Get-AstHashtableKeys $harnessAst 'AdapterDefaultTimeoutSec' | Sort-Object)
        'Invoke-LlmDelegatePanelDispatch.ps1 ($AdapterCdCapable)'        = @(Get-AstHashtableKeys $harnessAst 'AdapterCdCapable' | Sort-Object)
        'Resolve-LlmDelegateAuthorization.ps1 (ValidateSet -Backend, without orchestrator-native)' = $authDispatchOnly
        'Set-LlmDelegatePreferredReviewers.ps1 ($allowedDispatchBackends)' = @(Get-AstArrayAssignmentValues (Join-Path $scriptsDir 'Set-LlmDelegatePreferredReviewers.ps1') 'allowedDispatchBackends' | Sort-Object)
    }
    Assert-True ($authValidateSet -contains 'orchestrator-native') "AST Guard: Authorization's ValidateSet should include orchestrator-native"
    foreach ($entry in $collectionsToCompare.GetEnumerator()) {
        $name = $entry.Key
        $keys = $entry.Value
        Assert-True ($keys.Count -eq $canonicalSorted.Count) "AST Guard: key count mismatch in $name ($($keys.Count) vs $($canonicalSorted.Count))"
        for ($i = 0; $i -lt $canonicalSorted.Count; $i++) {
            Assert-True ($keys[$i] -eq $canonicalSorted[$i]) "AST Guard: key mismatch at position $i in $name ('$($keys[$i])' vs '$($canonicalSorted[$i])')"
        }
    }

    $localityPascalTable = [ordered]@{
        'opencode'    = 'OpenCode'
        'codex'       = 'Codex'
        'claude-code' = 'ClaudeCode'
        'copilot'     = 'Copilot'
        'gemini'      = 'Gemini'
        'antigravity' = 'Antigravity'
    }
    $tableKeysSorted = @($localityPascalTable.Keys | Sort-Object)
    Assert-True ($tableKeysSorted.Count -eq $canonicalSorted.Count) "AST Guard: the locality PascalCase table should contain $($canonicalSorted.Count) entries; got $($tableKeysSorted.Count)"
    for ($i = 0; $i -lt $canonicalSorted.Count; $i++) {
        Assert-True ($tableKeysSorted[$i] -eq $canonicalSorted[$i]) "AST Guard: PascalCase table key mismatch at position $i ('$($tableKeysSorted[$i])' vs '$($canonicalSorted[$i])')"
    }
    foreach ($b in $localityPascalTable.Keys) {
        $pascal = $localityPascalTable[$b]
        $resolverScript = Join-Path $scriptsDir "Resolve-${pascal}ModelLocality.ps1"
        $selfTestScript = Join-Path $testsDir "Test-${pascal}ModelLocalitySelfTest.ps1"
        Assert-True (Test-Path -LiteralPath $resolverScript -PathType Leaf) "AST Guard: locality script $resolverScript not found"
        Assert-True (Test-Path -LiteralPath $selfTestScript -PathType Leaf) "AST Guard: locality self-test $selfTestScript not found"
    }
    $nativeLocality = Join-Path $scriptsDir 'Resolve-OrchestratorNativeModelLocality.ps1'
    Assert-True (Test-Path -LiteralPath $nativeLocality -PathType Leaf) "AST Guard: locality script $nativeLocality not found"

    Set-Content -LiteralPath $concLog -Value '' -NoNewline -Encoding utf8
    $r = Invoke-Harness -Reviewers @(@{
            backend = 'opencode'; targetModelKey = 'openai/bad-primary'; invokeArgs = @{ backend = 'opencode'; model = 'openai/bad-primary' }
            fallbackChain = @(
                @{ backend = 'opencode'; targetModelKey = 'openai/fb-0'; invokeArgs = @{ backend = 'opencode'; model = 'openai/fb-0' } },
                @{ backend = 'codex'; targetModelKey = 'openai/fb-1'; invokeArgs = @{ backend = 'opencode'; model = 'gpt-5.5' } }
            )
        }) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }
    $rv0 = Get-Reviewer $r.json 0
    Assert-True ($rv0.state -eq 'error') 'divergent fallback: should fail in pre-dispatch.'
    Assert-True ([string]$rv0.reason -match 'invokeArgs.backend') 'divergent fallback: reason should cite invokeArgs.backend.'
    $logAfterBad = @(Get-Content -LiteralPath $concLog -ErrorAction SilentlyContinue | Where-Object { $_ })
    $badCalls = @($logAfterBad | Where-Object { $_ -match 'bad-primary|fb-0|fb-1' })
    Assert-True ($badCalls.Count -eq 0) "divergent fallback: the fake executor should not be called for the invalid entry; calls=[$($badCalls -join ' | ')]"

    # =======================================================================================
    # 8c) REAL DISPATCH of claude-code / copilot / gemini / antigravity (model, cwd and receipt)
    # =======================================================================================
    $r = Invoke-Harness -Reviewers @(
        @{ backend = 'claude-code'; invokeArgs = @{ model = 'claude-opus-4-8' } },
        @{ backend = 'copilot';     invokeArgs = @{ model = 'gpt-5-mini' } },
        @{ backend = 'gemini';      invokeArgs = @{ model = 'gemini-3-flash-preview' } },
        @{ backend = 'antigravity'; invokeArgs = @{ model = 'gemini-3.6-flash-high' } }
    ) -Sensitivity 'public' -Extra @{ Cd = $tmp }
    $tmpFwd = $tmp.Replace('\', '/')

    $rvCl = Get-Reviewer $r.json 0
    Assert-True ($rvCl.state -eq 'responded') "claude-code dispatch: expected responded; got $($rvCl.state)"
    Assert-True ($rvCl.sidecarAccepted -eq $true) 'claude-code dispatch: the sidecar should be accepted.'
    Assert-True ($rvCl.resultAccepted -eq $true) 'claude-code dispatch: expected resultAccepted=true.'
    Assert-True ($rvCl.technicalStatus -eq 'completed') 'claude-code dispatch: expected technicalStatus completed.'
    Assert-True (Test-Path -LiteralPath ([string]$rvCl.sidecarPath) -PathType Leaf) 'claude-code dispatch: sidecarPath should exist.'
    $sidecarCl = Get-Content -LiteralPath ([string]$rvCl.sidecarPath) -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$rvCl.acceptedFinalTextSha256)) 'claude-code dispatch: acceptedFinalTextSha256 should be preserved in the reviewer record.'
    Assert-True ($rvCl.acceptedFinalTextSha256 -eq $sidecarCl.acceptedFinalTextSha256) "claude-code dispatch: the reviewer's acceptedFinalTextSha256 should match the sidecar."
    Assert-True ([int]$rvCl.acceptedFinalTextBytes -eq [int]$sidecarCl.acceptedFinalTextBytes) "claude-code dispatch: the reviewer's acceptedFinalTextBytes should match the sidecar."
    $tCl = Get-Content -LiteralPath $rvCl.verdictPath -Raw -Encoding utf8
    Assert-True ($tCl -match 'model=claude-opus-4-8') 'claude-code dispatch: -Model should reach the adapter'
    Assert-True ($tCl -match [regex]::Escape($tmp)) 'claude-code dispatch: -Cd should become the WorkingDirectory (cwd)'
    Assert-True ([int]$r.json.reviewersDispatchAttempted -eq 4) 'v2 counters: expected reviewersDispatchAttempted=4.'
    Assert-True ([int]$r.json.reviewersProcessCreated -eq 1) 'v2 counters: only async Claude declares processCreated=true.'
    Assert-True ([int]$r.json.processCreatedUnknownCount -eq 3) 'v2 counters: copilot/gemini/antigravity end up with processCreated unknown.'
    Assert-True ([int]$r.json.sidecarAcceptedCount -eq 1) 'v2 counters: expected sidecarAcceptedCount=1.'

    $rvCp = Get-Reviewer $r.json 1
    Assert-True ($rvCp.state -eq 'responded') "copilot dispatch: expected responded; got $($rvCp.state)"
    $tCp = Get-Content -LiteralPath $rvCp.verdictPath -Raw -Encoding utf8
    Assert-True ($tCp -match 'model=gpt-5-mini') 'copilot dispatch: -Model should reach the adapter'
    Assert-True ($tCp -match [regex]::Escape($tmpFwd)) 'copilot dispatch: -Cd should become the WorkingDirectory (cwd)'

    $rvGm = Get-Reviewer $r.json 2
    Assert-True ($rvGm.state -eq 'responded') "gemini dispatch: expected responded; got $($rvGm.state)"
    $tGm = Get-Content -LiteralPath $rvGm.verdictPath -Raw -Encoding utf8
    Assert-True ($tGm -match 'model=gemini-3-flash-preview') 'gemini dispatch: -Model should reach the adapter'
    Assert-True ($tGm -match [regex]::Escape($tmpFwd)) 'gemini dispatch: -Cd should become the WorkingDirectory (cwd)'

    $rvAg = Get-Reviewer $r.json 3
    Assert-True ($rvAg.state -eq 'responded') "antigravity dispatch: expected responded; got $($rvAg.state)"
    $tAg = Get-Content -LiteralPath $rvAg.verdictPath -Raw -Encoding utf8
    Assert-True ($tAg -match 'model=gemini-3.6-flash-high') 'antigravity dispatch: -Model should reach the adapter'
    Assert-True ($tAg -notmatch [regex]::Escape($tmpFwd)) 'antigravity public-review must not inherit -Cd from the dispatcher'
    Assert-True ($rvAg.publicReviewProfile -eq 'public-review') 'antigravity dispatch: expected the fixed public-review profile'
    Assert-True ($rvAg.cliVersion -eq '1.1.19' -and $rvAg.cliVersionMatchesBaseline) 'antigravity dispatch: the receipt should record cliVersion'
    Assert-True ($rvAg.cleanupStatus -eq 'clean' -and $rvAg.keyringIsolation -eq 'not-isolated-global-keyring') 'antigravity dispatch: clean cleanup and keyring limit should be recorded'
    Assert-True (Test-Path -LiteralPath ([string]$rvAg.adapterReceiptPath) -PathType Leaf) 'antigravity dispatch: a technical receipt should exist in the ledger'

    # public-review never receives kb-sensitive: the gate runs first and the adapter is never invoked.
    $agyCallLog = Join-Path $tmp 'antigravity.calls.log'
    $agyCallsBefore = if (Test-Path $agyCallLog) { @(Get-Content $agyCallLog).Count } else { 0 }
    $r = Invoke-Harness -Reviewers @(@{
        backend = 'antigravity'; targetModelKey = 'antigravity/gemini-3.6-flash-high'
        invokeArgs = @{ model = 'gemini-3.6-flash-high' }
    }) -Sensitivity 'kb-sensitive'
    $rvAgGateAsk = Get-Reviewer $r.json 0
    $agyCallsAfterGateAsk = if (Test-Path $agyCallLog) { @(Get-Content $agyCallLog).Count } else { 0 }
    Assert-True ($rvAgGateAsk.gateVerdict -eq 'ask' -and $rvAgGateAsk.state -eq 'gateAsk') "antigravity kb-sensitive without policy preserves the gate's gateAsk"
    Assert-True (-not $rvAgGateAsk.dispatchAttempted -and $agyCallsAfterGateAsk -eq $agyCallsBefore) "antigravity's gateAsk blocks before the adapter"

    # With a durable allow policy, the fixed posture still refuses kb-sensitive via refusedSensitivity.
    $r = Invoke-Harness -Reviewers @(@{
        backend = 'antigravity'; targetModelKey = 'antigravity/gemini-3.6-flash-high'
        invokeArgs = @{ model = 'gemini-3.6-flash-high' }
    }) -Sensitivity 'kb-sensitive' -Extra @{ PolicyPath = $polAntigravity }
    $rvAgSensitive = Get-Reviewer $r.json 0
    $agyCallsAfter = if (Test-Path $agyCallLog) { @(Get-Content $agyCallLog).Count } else { 0 }
    Assert-True ($rvAgSensitive.gateVerdict -eq 'allow') 'antigravity kb-sensitive: the gate should remain the owner of confidentiality and run before the profile refusal'
    Assert-True ($rvAgSensitive.state -eq 'unavailable' -and $rvAgSensitive.reason -eq 'refusedSensitivity') 'antigravity kb-sensitive uses unavailable + refusedSensitivity'
    Assert-True (-not $rvAgSensitive.dispatchAttempted -and $agyCallsAfter -eq $agyCallsBefore) 'the profile gate blocks kb-sensitive before the adapter'

    # Typed adapter Reason=quota + dispatcher state=quota => clean reason (no adapterReason=processFailure).
    # ManuscriptText with no spaces: the harness's Start-Process -ArgumentList fragments values with spaces.
    $r = Invoke-Harness -Reviewers @(@{
        backend = 'antigravity'; targetModelKey = 'antigravity/gemini-3.6-flash-high'
        invokeArgs = @{ model = 'gemini-3.6-flash-high' }
    }) -Sensitivity 'public' -UseManuscriptText -ManuscriptText 'FORCE_AGY_QUOTA'
    Assert-True ($null -ne $r.json -and @($r.json.reviewers).Count -ge 1) 'antigravity typed quota: expected a summary with a reviewer'
    $rvAgQuota = Get-Reviewer $r.json 0
    Assert-True ($rvAgQuota.state -eq 'quota') "antigravity typed quota: expected state=quota; got $($rvAgQuota.state)"
    Assert-True ([string]$rvAgQuota.reason -eq 'quota') "antigravity typed quota: expected clean reason 'quota'; got '$($rvAgQuota.reason)'"
    Assert-True ([int]$r.json.quotaCount -ge 1) 'antigravity typed quota: quotaCount >= 1'

    $r = Invoke-Harness -Reviewers @(@{
            backend = 'claude-code'
            targetModelKey = 'anthropic/claude-sensitive-ledger'
            invokeArgs = @{ model = 'claude-sensitive-ledger' }
        }) -Sensitivity 'kb-sensitive' -Extra @{ Cd = $tmp; PolicyPath = $polAnthropic }
    $rvClSensitive = Get-Reviewer $r.json 0
    Assert-True ($rvClSensitive.state -eq 'responded') "claude-code kb-sensitive ledger: expected responded; got $($rvClSensitive.state)"
    Assert-True ($rvClSensitive.sidecarAccepted -eq $true) 'claude-code kb-sensitive ledger: the sidecar should be accepted.'
    Assert-True ($rvClSensitive.resultAccepted -eq $true) 'claude-code kb-sensitive ledger: expected resultAccepted=true.'
    Assert-True (Test-Path -LiteralPath ([string]$rvClSensitive.verdictPath) -PathType Leaf) 'claude-code kb-sensitive ledger: .verdict.txt should exist.'
    $rawLedgerFiles = @(Get-ChildItem -LiteralPath $r.ledgerDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*.stream.jsonl' -or $_.Name -like '*.stderr.txt' })
    $rawLedgerFileNames = @($rawLedgerFiles | ForEach-Object { $_.Name })
    Assert-True ($rawLedgerFiles.Count -eq 0) ("claude-code kb-sensitive ledger: raw stream/stderr should not remain in the ledger; remained: {0}" -f ($rawLedgerFileNames -join ', '))
    $sensitiveSidecar = Get-Content -LiteralPath ([string]$rvClSensitive.sidecarPath) -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($sensitiveSidecar.retentionMode -eq 'kb-sensitive') 'claude-code kb-sensitive ledger: retentionMode should be kb-sensitive.'
    Assert-True ($sensitiveSidecar.retentionCleanupFailed -eq $false) 'claude-code kb-sensitive ledger: stream/stderr cleanup should complete.'
    Assert-True ($null -eq $sensitiveSidecar.streamSha256) 'claude-code kb-sensitive ledger: streamSha256 should be omitted/null.'
    Assert-True ($null -eq $sensitiveSidecar.stderrSha256) 'claude-code kb-sensitive ledger: stderrSha256 should be omitted/null.'

    # An untrusted Claude Code workspace -> unavailable, to allow panel fallback.
    $r = Invoke-Harness -Reviewers @(@{ backend = 'claude-code'; invokeArgs = @{ model = 'claude-untrusted-workspace' } }) `
        -Sensitivity 'public' -Extra @{ Cd = $tmp }
    $rvClUntrusted = Get-Reviewer $r.json 0
    Assert-True ($rvClUntrusted.state -eq 'unavailable') "claude-code workspace-not-trusted: expected unavailable; got $($rvClUntrusted.state)"
    Assert-True ([string]$rvClUntrusted.reason -match 'workspace-not-trusted') 'claude-code workspace-not-trusted: reason should cite the canonical code'

    # A primary reviewer's workspace-not-trusted should activate fallback like any other technical unavailable.
    $r = Invoke-Harness -Reviewers @(@{
            backend = 'claude-code'; targetModelKey = 'anthropic/claude-opus-4-8'; invokeArgs = @{ model = 'claude-untrusted-workspace' }
            fallbackChain = @(
                @{ backend = 'opencode'; targetModelKey = 'openai/fallback-after-unavailable'; invokeArgs = @{ backend = 'opencode'; model = 'openai/fallback-after-unavailable' } }
            )
        }) -Sensitivity 'public' -Extra @{ Cd = $tmp; OpenCodeConfigPath = $ocCfg }
    Assert-True (@($r.json.reviewers).Count -eq 2) 'fallback workspace-not-trusted: should register primary reviewer + fallback.'
    $rvClUntrusted = Get-Reviewer $r.json 0
    $rvFallbackUntrusted = Get-Reviewer $r.json 1
    Assert-True ($rvClUntrusted.state -eq 'unavailable') "fallback workspace-not-trusted: the primary reviewer should end up unavailable; got $($rvClUntrusted.state)"
    Assert-True ($rvFallbackUntrusted.state -eq 'responded') "fallback workspace-not-trusted: the fallback should respond; got $($rvFallbackUntrusted.state)"
    Assert-True ($rvFallbackUntrusted.attemptRole -eq 'fallback') 'fallback workspace-not-trusted: attemptRole=fallback.'
    Assert-True ($rvFallbackUntrusted.activationReason -eq 'unavailable') 'fallback workspace-not-trusted: activationReason should be unavailable.'
    Assert-True ($rvFallbackUntrusted.countsForDiversity -eq $true) 'a responded fallback workspace-not-trusted should count toward diversity.'

    # =======================================================================================
    # 9) -Cd: precedence (explicit / cwd / KbWorkspaceRoot) + fail-closed
    # =======================================================================================
    # explicit (public): -Cd wins -> fake-codex writes CD=<explicit>
    $explicitCd = $tmp
    $r = Invoke-Harness -Reviewers @(@{ backend = 'codex'; invokeArgs = @{ model = 'gpt-5.5' } }) `
        -Sensitivity 'public' -Extra @{ CodexConfigPath = $cxCfg; Cd = $explicitCd }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'responded') "explicit Cd: should dispatch; got $($rv.state)"
    $vtext = Get-Content -LiteralPath $rv.verdictPath -Raw -Encoding utf8
    Assert-True ($vtext -match ([regex]::Escape("CD=$explicitCd"))) "explicit Cd: the fake should receive -C $explicitCd; got '$vtext'"

    # kb-sensitive + KbWorkspaceRoot + allow policy -> -Cd = KbWorkspaceRoot
    $kbRoot = Join-Path $tmp 'kb-root'
    New-Item -ItemType Directory -Path $kbRoot -Force | Out-Null
    Copy-Item -LiteralPath $pol -Destination (Join-Path $kbRoot 'llm-delegation-policy.json')
    $r = Invoke-Harness -Reviewers @(@{ backend = 'codex'; invokeArgs = @{ model = 'gpt-5.5' } }) `
        -Sensitivity 'kb-sensitive' -Extra @{ CodexConfigPath = $cxCfg; KbWorkspaceRoot = $kbRoot }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.gateVerdict -eq 'allow') "Cd/KbWorkspaceRoot: the gate should allow via the openai/* policy; got '$($rv.gateVerdict)'"
    Assert-True ($rv.state -eq 'responded') 'Cd/KbWorkspaceRoot: should dispatch'
    $vtext = Get-Content -LiteralPath $rv.verdictPath -Raw -Encoding utf8
    Assert-True ($vtext -match ([regex]::Escape("CD=$kbRoot"))) "Cd/KbWorkspaceRoot: the fake should receive -C $kbRoot; got '$vtext'"

    # fail-closed: kb-sensitive + allow (policy) + no -Cd + no -KbWorkspaceRoot -> error
    $r = Invoke-Harness -Reviewers @(@{ backend = 'codex'; invokeArgs = @{ model = 'gpt-5.5' } }) `
        -Sensitivity 'kb-sensitive' -Extra @{ CodexConfigPath = $cxCfg; PolicyPath = $pol }
    $rv = Get-Reviewer $r.json 0
    Assert-True ($rv.state -eq 'error') "Cd fail-closed: kb-sensitive allow without -Cd/-KbWorkspaceRoot should error; got $($rv.state)"
    Assert-True ($rv.reason -match 'fail-closed') 'Cd fail-closed: reason should cite fail-closed'

    # =======================================================================================
    # 10) OUTPUT CONTRACT
    # =======================================================================================
    $r = Invoke-Harness -Reviewers @(
        @{ backend = 'opencode'; targetModelKey = 'openai/contract'; invokeArgs = @{} },
        @{ backend = 'claude-code'; invokeArgs = @{} }   # no model -> error, null targetModelKey
    ) -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg }

    # stdout = exactly 1 line
    $stdoutTrim = $r.stdout.TrimEnd("`r", "`n")
    Assert-True (@($stdoutTrim -split "`n").Count -eq 1) 'contract: stdout should have exactly 1 line'
    Assert-True ($r.json.Kind -eq 'mimir-panel-dispatch-result') 'contract: PascalCase Kind'
    Assert-True ([int]$r.json.SchemaVersion -eq 3) 'contract: PascalCase SchemaVersion=3'
    # state subset
    $validStates = @('responded', 'error', 'quota', 'unavailable', 'timeout', 'gateAsk', 'gateDeny', 'skippedAfterSuccess', 'skippedByPolicy', 'notAttempted')
    foreach ($rev in $r.json.reviewers) { Assert-True ($validStates -contains $rev.state) "contract: state '$($rev.state)' should be in the valid subset" }
    # empty targetModelKey -> null (claude-code without model)
    $rvClaude = Get-Reviewer $r.json 1
    Assert-True ($null -eq $rvClaude.targetModelKey) 'contract: an empty targetModelKey should become null'
    # Windows-safe slug (no / : etc.)
    $rvOc = Get-Reviewer $r.json 0
    $base = Split-Path -Leaf $rvOc.verdictPath
    Assert-True ($base -match '^[0-9A-Za-z._-]+\.verdict\.txt$') "contract: the ledger name should be Windows-safe; got '$base'"

    # missing RoundId -> guid
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/x'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg } -NoRoundId
    Assert-True ($r.json.roundId -match '^[0-9a-f]{32}$') "missing RoundId: should generate a guid 'N'; got '$($r.json.roundId)'"

    # ManuscriptText -> transactional preparer before dispatch
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/texto-inline'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg } -UseManuscriptText `
        -ManuscriptText 'manuscript-inline'
    Assert-True ($r.exit -eq 0) 'ManuscriptText: expected exit 0'
    Assert-True ($r.json.success -eq $true) 'ManuscriptText: success=true'
    Assert-True ($r.json.roundStarted -eq $true) 'ManuscriptText: roundStarted=true'
    Assert-True ($r.json.dispatchStarted -eq $true) 'ManuscriptText: dispatchStarted=true'
    Assert-True ([int]$r.json.reviewersDispatched -eq 1) 'ManuscriptText: reviewersDispatched=1'
    Assert-True ($null -eq $r.json.preparationError) 'ManuscriptText: preparationError=null'
    Assert-True ((Get-Reviewer $r.json 0).state -eq 'responded') 'ManuscriptText: the reviewer should respond'
    $prepManifest = Join-Path $ledgerRoot $r.roundId 'preparation-manifest.json'
    Assert-True (Test-Path -LiteralPath $prepManifest -PathType Leaf) 'ManuscriptText: preparation-manifest.json should exist'

    # Oversized ManuscriptText -> structured block before preparing/dispatching
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/texto-grande'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg } -UseManuscriptText `
        -ManuscriptText ('x' * 30001)
    Assert-True ($r.exit -eq 1) 'oversized ManuscriptText: expected exit 1'
    Assert-True ($r.json.Kind -eq 'mimir-panel-dispatch-result') "oversized ManuscriptText: expected the dispatcher's Kind"
    Assert-True ([int]$r.json.SchemaVersion -eq 3) 'oversized ManuscriptText: SchemaVersion=3'
    Assert-True ($r.json.roundStarted -eq $false) 'oversized ManuscriptText: roundStarted=false'
    Assert-True ($r.json.dispatchStarted -eq $false) 'oversized ManuscriptText: dispatchStarted=false'
    Assert-True ([int]$r.json.reviewersDispatched -eq 0) 'oversized ManuscriptText: zero dispatches'
    Assert-True ($r.json.preparationError.failureCode -eq 'manuscript-text-too-large') 'oversized ManuscriptText: failureCode manuscript-text-too-large'

    # Missing/ambiguous source -> structured block before preparing/dispatching
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/missing-origin'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg } -OmitManuscriptSource
    Assert-True ($r.exit -eq 1) 'missing source: expected exit 1'
    Assert-True ($r.json.Kind -eq 'mimir-panel-dispatch-result') "missing source: expected the dispatcher's Kind"
    Assert-True ([int]$r.json.SchemaVersion -eq 3) 'missing source: SchemaVersion=3'
    Assert-True ($r.json.roundStarted -eq $false) 'missing source: roundStarted=false'
    Assert-True ($r.json.dispatchStarted -eq $false) 'missing source: dispatchStarted=false'
    Assert-True ([int]$r.json.reviewersDispatched -eq 0) 'missing source: zero dispatches'
    Assert-True ($r.json.preparationError.failureCode -eq 'manuscript-source-missing') 'missing source: failureCode manuscript-source-missing'

    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/ambiguous-origin'; invokeArgs = @{} }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg } -BothManuscriptSources -ManuscriptText 'manuscript-inline'
    Assert-True ($r.exit -eq 1) 'ambiguous source: expected exit 1'
    Assert-True ($r.json.Kind -eq 'mimir-panel-dispatch-result') "ambiguous source: expected the dispatcher's Kind"
    Assert-True ([int]$r.json.SchemaVersion -eq 3) 'ambiguous source: SchemaVersion=3'
    Assert-True ($r.json.roundStarted -eq $false) 'ambiguous source: roundStarted=false'
    Assert-True ($r.json.dispatchStarted -eq $false) 'ambiguous source: dispatchStarted=false'
    Assert-True ([int]$r.json.reviewersDispatched -eq 0) 'ambiguous source: zero dispatches'
    Assert-True ($r.json.preparationError.failureCode -eq 'manuscript-source-ambiguous') 'ambiguous source: failureCode manuscript-source-ambiguous'

    # Preparation failure -> the dispatcher's own summary, without starting a round/dispatch
    $r = Invoke-Harness -Reviewers @(@{ backend = 'opencode'; targetModelKey = 'openai/invalid-text'; invokeArgs = 'not-an-object' }) `
        -Sensitivity 'public' -Extra @{ OpenCodeConfigPath = $ocCfg } -UseManuscriptText -ManuscriptText 'manuscript-inline'
    Assert-True ($r.exit -eq 1) 'invalid ManuscriptText: expected exit 1'
    Assert-True ($r.json.Kind -eq 'mimir-panel-dispatch-result') "invalid ManuscriptText: expected the dispatcher's Kind"
    Assert-True ([int]$r.json.SchemaVersion -eq 3) 'invalid ManuscriptText: SchemaVersion=3'
    Assert-True ($r.json.roundStarted -eq $false) 'invalid ManuscriptText: roundStarted=false'
    Assert-True ($r.json.dispatchStarted -eq $false) 'invalid ManuscriptText: dispatchStarted=false'
    Assert-True ([int]$r.json.reviewersDispatched -eq 0) 'invalid ManuscriptText: zero dispatches'
    Assert-True ($r.json.preparationError.failureCode -eq 'reviewer-invalid-invokeArgs') 'invalid ManuscriptText: failureCode reviewer-invalid-invokeArgs'

    # ReviewersJson INLINE (not a file) + INVALID — tested IN-PROCESS by reading the ledger
    $ridInline = [guid]::NewGuid().ToString('N')
    $inlineJson = '[{"backend":"opencode","targetModelKey":"openai/inline","invokeArgs":{}}]'
    & $harness -ManuscriptPath $manuscript -ReviewersJson $inlineJson -PayloadSensitivity public `
        -RoundId $ridInline -TempDir $ledgerRoot -BackendExeMap $exeMapFile -OpenCodeConfigPath $ocCfg 1> $null
    $inlineSummary = Join-Path $ledgerRoot $ridInline 'panel-summary.json'
    Assert-True (Test-Path -LiteralPath $inlineSummary -PathType Leaf) 'inline ReviewersJson: should write panel-summary.json'
    $inlineObj = Get-Content -LiteralPath $inlineSummary -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ((Get-Reviewer $inlineObj 0).state -eq 'responded') 'inline ReviewersJson: the reviewer should respond'

    $threw = $false
    try { & $harness -ManuscriptPath $manuscript -ReviewersJson '{invalid-garbage' -PayloadSensitivity public -TempDir $ledgerRoot 1> $null 2> $null }
    catch { $threw = $true }
    Assert-True $threw 'invalid ReviewersJson: should throw (BLOCK)'

    # No default agent: the opencode adapter no longer loads the reviewer-ro guard nor assigns
    # 'reviewer-ro' as -Agent when the panel does not supply an explicit one (the agent key is
    # always refused by the dispatcher, so opencode runs with whatever agent config resolves).
    $invokeOcSrc = Get-Content -LiteralPath (Join-Path $scriptsDir 'Invoke-OpenCode.ps1') -Raw -Encoding utf8
    Assert-True ($invokeOcSrc -notmatch 'OpenCodeReviewerRoGuard') "Invoke-OpenCode.ps1 without a dot-source of the reviewer-ro guard"
    Assert-True ($invokeOcSrc -notmatch "Agent\s*=\s*'reviewer-ro'") 'Invoke-OpenCode.ps1 without a default -Agent reviewer-ro'

    Write-Output 'OK: Test-InvokeLlmDelegatePanelDispatchSelfTest.ps1'
}
finally {
    Pop-Location -ErrorAction SilentlyContinue
    Remove-Item Env:\PANEL_FAKE_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:\PANEL_FAKE_MUTEX -ErrorAction SilentlyContinue
    if ($null -eq $script:prevCodexDisableKeepDays) {
        Remove-Item Env:\MIMIR_CODEX_DISABLE_KEEPDAYS -ErrorAction SilentlyContinue
    } else {
        $env:MIMIR_CODEX_DISABLE_KEEPDAYS = $script:prevCodexDisableKeepDays
    }
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
