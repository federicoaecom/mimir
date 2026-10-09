#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
$scriptUnderTest = Join-Path $scriptsDir 'Invoke-ClaudeCodeAsync.ps1'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-TestSha256Text {
    param([AllowNull()] [string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash($bytes)).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-NoRawCaptureFiles {
    param([string]$Path, [string]$Message)
    $rawFiles = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*.stream.jsonl' -or $_.Name -like '*.stderr.txt' })
    $rawFileNames = @($rawFiles | ForEach-Object { $_.Name })
    Assert-True ($rawFiles.Count -eq 0) ("{0}: raw stream/stderr files remained: {1}" -f $Message, ($rawFileNames -join ', '))
}

function Assert-RawCaptureFilesExist {
    param([string]$Path, [string]$Message)
    $rawFiles = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*.stream.jsonl' -or $_.Name -like '*.stderr.txt' })
    Assert-True ($rawFiles.Count -gt 0) ("{0}: expected raw stream/stderr to simulate a cleanup failure." -f $Message)
}

function New-FakeClaudeCodeExe {
    param([string]$TempRoot)
    $argsFile = Join-Path $TempRoot 'args.txt'
    # Every non-probe call appends one line "<mode> <args>" to the args file; the stream each mode
    # emits is fixed below. Sleeps keep the process alive past short adapter timeouts.
    $body = @'
if ($args.Count -ge 1 -and $args[0] -eq '--version') { '2.1.118'; exit 0 }
if ($args.Count -ge 1 -and $args[0] -eq '--help') { '--model --print --output-format --no-session-persistence --permission-mode --tools'; exit 0 }
$mode = [string]$env:FAKE_CLAUDE_MODE
Add-Content -LiteralPath '__ARGS_FILE__' -Value ((@($mode) + @($args)) -join ' ') -Encoding utf8
switch ($mode) {
    'success-delta' {
        '{"type":"assistant","message":{"content":[{"text":"texto duplicado"}]}}'
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"A"}}'
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"B"}}'
        '{"type":"result","subtype":"success","is_error":false,"result":"NAO_E_VEREDITO"}'
        exit 0
    }
    'success-assistant' {
        '{"type":"assistant","message":{"content":[{"text":"verdict accepted"}]}}'
        '{"type":"result","subtype":"success","is_error":false}'
        exit 0
    }
    'success-newline' {
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"linha\n"}}'
        '{"type":"result","subtype":"success","is_error":false}'
        exit 0
    }
    'success-stderr' {
        '{"type":"assistant","message":{"content":[{"text":"verdict with stderr"}]}}'
        [Console]::Error.WriteLine('detalhe bruto sensivel')
        '{"type":"result","subtype":"success","is_error":false}'
        exit 0
    }
    'success-slow' {
        [Console]::Out.WriteLine('{"type":"content_block_delta","delta":{"type":"text_delta","text":"SONDA"}}')
        [Console]::Out.Flush()
        Start-Sleep -Seconds 3
        '{"type":"result","subtype":"success","is_error":false}'
        exit 0
    }
    'success-no-terminal' {
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"text-without-terminal"}}'
        exit 0
    }
    'success-incomplete-terminal' {
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"texto-terminal-incompleto"}}'
        '{"type":"result","subtype":"success"}'
        exit 0
    }
    'quota-after-text' {
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"parcial"}}'
        '{"type":"result","is_error":true,"terminal_reason":"api_error","api_error_status":429,"rateLimitType":"weekly","reportedLimitScope":"subscription","resetsAt":1893456000,"result":"rate limit"}'
        exit 1
    }
    'timeout-after-text' {
        [Console]::Out.WriteLine('{"type":"content_block_delta","delta":{"type":"text_delta","text":"parcial-timeout"}}')
        [Console]::Out.Flush()
        # Outlives the adapter's -TimeoutSec, which kills this process.
        Start-Sleep -Seconds 30
        exit 0
    }
    'exit-after-text' {
        '{"type":"content_block_delta","delta":{"type":"text_delta","text":"parcial-exit"}}'
        exit 1
    }
    'untrusted' {
        [Console]::Error.WriteLine('Claude Code refused to run because this workspace is not trusted. Mark this workspace as trusted to continue.')
        exit 1
    }
    'sleep' {
        Start-Sleep -Seconds 5
        exit 0
    }
}
'{"type":"result","subtype":"success","is_error":false}'
exit 0
'@
    $fakeExe = New-FakeCli -Directory $TempRoot -Name 'claude' -PwshBody $body.Replace('__ARGS_FILE__', $argsFile.Replace("'", "''"))
    [pscustomobject]@{ Exe = $fakeExe; ArgsFile = $argsFile }
}

function Invoke-AdapterCase {
    param(
        [string]$TempRoot,
        [string]$Mode,
        [string]$ClaudeExe,
        [string]$CircuitRoot,
        [string]$RetentionMode = 'public',
        [int]$TimeoutSec = 30,
        [switch]$ForceRetentionCleanupFailure,
        [switch]$ForceIdentityUnverifiable,
        [switch]$ForceQuotaStateWriteLock,
        [string]$TestStartedAtUtc
    )
    $env:FAKE_CLAUDE_MODE = $Mode
    $previousForceCleanup = $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_RETENTION_CLEANUP_FAIL
    $previousForceIdentity = $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_IDENTITY_UNVERIFIABLE
    $previousForceQuotaLock = $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_QUOTA_STATE_WRITE_LOCK
    $previousTestStartedAtUtc = $env:MIMIR_TEST_CLAUDE_ASYNC_STARTED_AT_UTC
    if ($ForceRetentionCleanupFailure) { $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_RETENTION_CLEANUP_FAIL = '1' }
    else { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_RETENTION_CLEANUP_FAIL -ErrorAction SilentlyContinue }
    if ($ForceIdentityUnverifiable) { $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_IDENTITY_UNVERIFIABLE = '1' }
    else { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_IDENTITY_UNVERIFIABLE -ErrorAction SilentlyContinue }
    if ($ForceQuotaStateWriteLock) { $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_QUOTA_STATE_WRITE_LOCK = '1' }
    else { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_QUOTA_STATE_WRITE_LOCK -ErrorAction SilentlyContinue }
    if (-not [string]::IsNullOrWhiteSpace($TestStartedAtUtc)) { $env:MIMIR_TEST_CLAUDE_ASYNC_STARTED_AT_UTC = $TestStartedAtUtc }
    else { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_STARTED_AT_UTC -ErrorAction SilentlyContinue }
    $caseId = [guid]::NewGuid().ToString('N')
    $prompt = Join-Path $TempRoot "prompt-$Mode-$caseId.md"
    Set-Content -LiteralPath $prompt -Value "prompt $Mode" -Encoding utf8
    $sidecar = Join-Path $TempRoot "$Mode-$caseId.sidecar.json"
    $adapterTemp = Join-Path $TempRoot "adapter-$Mode-$caseId"
    New-Item -ItemType Directory -Path $adapterTemp -Force | Out-Null
    try {
        # An empty -CircuitRoot leaves -CircuitStateRoot unbound, so the adapter uses its default state root.
        $circuitArgs = @{}
        if (-not [string]::IsNullOrWhiteSpace($CircuitRoot)) { $circuitArgs['CircuitStateRoot'] = $CircuitRoot }
        $stdout = & $scriptUnderTest -MessagePath $prompt -SidecarPath $sidecar -Model 'claude-opus-4-8' `
            -ClaudeExe $ClaudeExe -TempDir $adapterTemp `
            -RetentionMode $RetentionMode -TimeoutSec $TimeoutSec -Cd $TempRoot @circuitArgs
        $sidecarJson = Get-Content -LiteralPath $sidecar -Raw -Encoding utf8 | ConvertFrom-Json
        [pscustomobject]@{
            stdout      = if ($null -eq $stdout) { '' } elseif ($stdout -is [array]) { $stdout -join "`n" } else { [string]$stdout }
            sidecar     = $sidecarJson
            path        = $sidecar
            adapterTemp = $adapterTemp
        }
    }
    finally {
        if ($null -eq $previousForceCleanup) { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_RETENTION_CLEANUP_FAIL -ErrorAction SilentlyContinue }
        else { $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_RETENTION_CLEANUP_FAIL = $previousForceCleanup }
        if ($null -eq $previousForceIdentity) { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_IDENTITY_UNVERIFIABLE -ErrorAction SilentlyContinue }
        else { $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_IDENTITY_UNVERIFIABLE = $previousForceIdentity }
        if ($null -eq $previousForceQuotaLock) { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_QUOTA_STATE_WRITE_LOCK -ErrorAction SilentlyContinue }
        else { $env:MIMIR_TEST_CLAUDE_ASYNC_FORCE_QUOTA_STATE_WRITE_LOCK = $previousForceQuotaLock }
        if ($null -eq $previousTestStartedAtUtc) { Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_STARTED_AT_UTC -ErrorAction SilentlyContinue }
        else { $env:MIMIR_TEST_CLAUDE_ASYNC_STARTED_AT_UTC = $previousTestStartedAtUtc }
    }
}

function Start-AdapterProcessCase {
    param(
        [string]$TempRoot,
        [string]$Mode,
        [string]$ClaudeExe,
        [string]$CircuitRoot,
        [string]$RetentionMode = 'public',
        [int]$TimeoutSec = 30
    )

    $env:FAKE_CLAUDE_MODE = $Mode
    $caseId = [guid]::NewGuid().ToString('N')
    $prompt = Join-Path $TempRoot "prompt-$Mode-$caseId.md"
    Set-Content -LiteralPath $prompt -Value "prompt $Mode" -Encoding utf8
    $sidecar = Join-Path $TempRoot "$Mode-$caseId.sidecar.json"
    $adapterTemp = Join-Path $TempRoot "adapter-$Mode-$caseId"
    $stdoutPath = Join-Path $TempRoot "$Mode-$caseId.stdout.txt"
    $stderrPath = Join-Path $TempRoot "$Mode-$caseId.harness-stderr.txt"
    New-Item -ItemType Directory -Path $adapterTemp -Force | Out-Null

    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $arguments = @(
        '-NoProfile',
        '-File', $scriptUnderTest,
        '-MessagePath', $prompt,
        '-SidecarPath', $sidecar,
        '-Model', 'claude-opus-4-8',
        '-ClaudeExe', $ClaudeExe,
        '-CircuitStateRoot', $CircuitRoot,
        '-TempDir', $adapterTemp,
        '-RetentionMode', $RetentionMode,
        '-TimeoutSec', [string]$TimeoutSec,
        '-Cd', $TempRoot
    )
    $process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    [pscustomobject]@{
        Process     = $process
        stdoutPath  = $stdoutPath
        stderrPath  = $stderrPath
        sidecarPath = $sidecar
        adapterTemp = $adapterTemp
    }
}

function Receive-AdapterProcessCase {
    param([object]$Case, [int]$WaitMs = 20000)

    if (-not $Case.Process.WaitForExit($WaitMs)) {
        try { $Case.Process.Kill($true) } catch { }
        throw "Self-test process did not finish in $WaitMs ms: $($Case.sidecarPath)"
    }
    if (Test-Path -LiteralPath $Case.stdoutPath -PathType Leaf) {
        $stdout = Get-Content -LiteralPath $Case.stdoutPath -Raw -Encoding utf8
    }
    else {
        $stdout = ''
    }
    $stdoutText = if ($null -eq $stdout) { '' } else { [string]$stdout }
    $sidecarJson = Get-Content -LiteralPath $Case.sidecarPath -Raw -Encoding utf8 | ConvertFrom-Json
    [pscustomobject]@{
        stdout      = $stdoutText.TrimEnd("`r", "`n")
        sidecar     = $sidecarJson
        path        = $Case.sidecarPath
        adapterTemp = $Case.adapterTemp
        exitCode    = $Case.Process.ExitCode
    }
}

Assert-True (Test-Path -LiteralPath $scriptUnderTest -PathType Leaf) "Script under test missing: $scriptUnderTest"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-code-async-selftest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$previousMode = $env:FAKE_CLAUDE_MODE
try {
    $fake = New-FakeClaudeCodeExe -TempRoot $tmp

    $circuitOk = Join-Path $tmp 'circuit-ok'
    $ok = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitOk
    Assert-True ($ok.stdout -eq 'AB') "accepted stdout should be only concatenated deltas; got '$($ok.stdout)'."
    Assert-True ($ok.sidecar.Kind -eq 'claude-code-async-sidecar') 'sidecar: invalid Kind.'
    Assert-True ([int]$ok.sidecar.SchemaVersion -eq 1) 'sidecar: SchemaVersion should be 1.'
    Assert-True ($ok.sidecar.technicalStatus -eq 'completed') 'sidecar: technicalStatus completed expected.'
    Assert-True ($ok.sidecar.resultAccepted -eq $true) 'sidecar: resultAccepted=true expected.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$ok.sidecar.acceptedFinalTextSha256)) 'sidecar: hash of accepted text missing.'
    Assert-True ($ok.sidecar.promptTransmission -eq 'stdin-file') 'sidecar: promptTransmission should be stdin-file.'
    Assert-True ($ok.sidecar.processCreated -eq $true) 'sidecar: processCreated=true expected.'
    Assert-True ($ok.sidecar.quotaCircuitDecision -eq 'closed') 'sidecar: circuit without state should be closed.'

    $newline = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-newline' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-newline')
    Assert-True ($newline.stdout -eq 'linha') 'terminal newline: stdout should strip only the trailing line break.'
    Assert-True ($newline.sidecar.acceptedFinalTextSha256 -eq (Get-TestSha256Text -Text $newline.stdout)) 'terminal newline: sidecar hash should match captured stdout.'
    Assert-True ([int]$newline.sidecar.acceptedFinalTextBytes -eq [System.Text.Encoding]::UTF8.GetByteCount($newline.stdout)) 'terminal newline: sidecar bytes should match captured stdout.'

    $noTerminal = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-no-terminal' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-no-terminal')
    Assert-True ([string]::IsNullOrWhiteSpace($noTerminal.stdout)) 'no terminal event: stdout should be empty.'
    Assert-True ($noTerminal.sidecar.technicalStatus -eq 'internalError') 'no terminal event: technicalStatus should be internalError.'
    Assert-True ($noTerminal.sidecar.resultAccepted -eq $false) 'no terminal event: resultAccepted should be false.'
    Assert-True ($noTerminal.sidecar.failureAfterText.reason -eq 'process-exit-after-partial-text') 'no terminal event: partial text should become failureAfterText.'

    $incompleteTerminal = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-incomplete-terminal' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-incomplete-terminal')
    Assert-True ([string]::IsNullOrWhiteSpace($incompleteTerminal.stdout)) 'incomplete terminal: stdout should be empty.'
    Assert-True ($incompleteTerminal.sidecar.technicalStatus -eq 'internalError') 'incomplete terminal: technicalStatus should be internalError.'
    Assert-True ($incompleteTerminal.sidecar.resultAccepted -eq $false) 'incomplete terminal: resultAccepted should be false.'
    Assert-True ($incompleteTerminal.sidecar.failureAfterText.reason -eq 'process-exit-after-partial-text') 'incomplete terminal: partial text should become failureAfterText.'

    $kb = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-stderr' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-kb') -RetentionMode 'kb-sensitive'
    Assert-True ($kb.stdout -eq 'verdict with stderr') 'kb-sensitive: accepted stdout should contain the final response.'
    Assert-True ($null -eq $kb.sidecar.streamSha256) 'kb-sensitive: streamSha256 must be omitted/null.'
    Assert-True ($null -eq $kb.sidecar.stderrSha256) 'kb-sensitive: stderrSha256 must be omitted/null.'
    Assert-True ($kb.sidecar.retentionCleanupFailed -eq $false) 'kb-sensitive: stream/stderr cleanup should complete.'
    Assert-NoRawCaptureFiles -Path $kb.adapterTemp -Message 'kb-sensitive success'

    $cleanupFail = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-stderr' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-cleanup-fail') -RetentionMode 'kb-sensitive' -ForceRetentionCleanupFailure
    Assert-True ([string]::IsNullOrWhiteSpace($cleanupFail.stdout)) 'kb-sensitive cleanup failed: stdout should be empty.'
    Assert-True ($cleanupFail.sidecar.technicalStatus -eq 'internalError') 'kb-sensitive cleanup failed: technicalStatus should be internalError.'
    Assert-True ($cleanupFail.sidecar.resultAccepted -eq $false) 'kb-sensitive cleanup failed: resultAccepted should be false.'
    Assert-True ($cleanupFail.sidecar.acceptanceRejectionReason -eq 'retention-cleanup-failed') 'kb-sensitive cleanup failed: reason should be retention-cleanup-failed.'
    Assert-True ($cleanupFail.sidecar.retentionCleanupFailed -eq $true) 'kb-sensitive cleanup failed: retentionCleanupFailed should be true.'
    Assert-True ($cleanupFail.sidecar.failureAfterText.reason -eq 'retention-cleanup-after-accepted-text') 'kb-sensitive cleanup failed: must preserve redacted metadata of the blocked accepted text.'
    Assert-True ($null -eq $cleanupFail.sidecar.failureAfterText.textSha256) 'kb-sensitive cleanup failed: textSha256 should be null.'
    Assert-RawCaptureFilesExist -Path $cleanupFail.adapterTemp -Message 'kb-sensitive cleanup failed'

    $circuitQuota = Join-Path $tmp 'circuit-quota'
    $quota = Invoke-AdapterCase -TempRoot $tmp -Mode 'quota-after-text' -ClaudeExe $fake.Exe -CircuitRoot $circuitQuota
    Assert-True ([string]::IsNullOrWhiteSpace($quota.stdout)) 'quota: stdout should be empty.'
    Assert-True ($quota.sidecar.technicalStatus -eq 'quota') 'quota: technicalStatus should be quota.'
    Assert-True ($quota.sidecar.resultAccepted -eq $false) 'quota: resultAccepted=false expected.'
    Assert-True ($quota.sidecar.failureAfterText.reason -eq 'quota-after-text') 'quota: failureAfterText should record failure after text.'
    $quotaStatePath = Join-Path (Join-Path $circuitQuota 'claude-code-quota-circuit') "$($quota.sidecar.quotaEvidence.baseKeyHash).weekly.state.json"
    $quotaStateRaw = Get-Content -LiteralPath $quotaStatePath -Raw -Encoding utf8
    $quotaState = $quotaStateRaw | ConvertFrom-Json
    Assert-True ($quotaState.provider -eq 'anthropic') 'quota state: provider missing/incorrect.'
    Assert-True ($quotaState.modelKey -eq 'claude-opus-4-8') 'quota state: modelKey missing/incorrect.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$quotaState.credentialContextFingerprint)) 'quota state: credentialContextFingerprint missing.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$quotaState.observedAtUtc)) 'quota state: observedAtUtc missing.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$quotaState.lastHitAtUtc)) 'quota state: lastHitAtUtc missing.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$quotaState.updatedAtUtc)) 'quota state: updatedAtUtc missing.'
    Assert-True ($quotaStateRaw -match '"observedAtUtc":"[^"]*\.\d{7}Z"') 'quota state: observedAtUtc should preserve sub-second precision.'
    Assert-True ($quotaStateRaw -match '"updatedAtUtc":"[^"]*\.\d{7}Z"') 'quota state: updatedAtUtc should preserve sub-second precision.'
    Assert-True ([int]$quotaState.hitCount -ge 1) 'quota state: hitCount should be >= 1.'
    Assert-True ($quotaState.effectiveLimitScope -eq 'subscription') 'quota state: effectiveLimitScope should reflect the reported scope.'
    Assert-True ($quotaState.scopeAssumed -eq $false) 'quota state: scopeAssumed should be false when a scope is reported.'
    Assert-True ($null -eq $quotaState.scopeAssumptionReason) 'quota state: scopeAssumptionReason should be null when a scope is reported.'
    Assert-True ($null -ne $quotaState.sourceEvidence) 'quota state: sourceEvidence missing.'
    Assert-True (@($quotaState.sourceEvidence.evidenceTypes) -contains 'result-api-error-429') 'quota state: sourceEvidence did not preserve the evidence type.'
    Assert-True ($quotaState.sourceEvidence.terminalReason -eq 'api_error') 'quota state: sourceEvidence did not preserve terminalReason.'
    Assert-True ([string]$quotaState.sourceEvidence.apiErrorStatus -eq '429') 'quota state: sourceEvidence did not preserve apiErrorStatus.'
    $argsBeforeBlock = @(Get-Content -LiteralPath $fake.ArgsFile)
    $blocked = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitQuota
    $argsAfterBlock = @(Get-Content -LiteralPath $fake.ArgsFile)
    Assert-True ([string]::IsNullOrWhiteSpace($blocked.stdout)) 'open circuit: stdout should be empty.'
    Assert-True ($blocked.sidecar.spawnAttempted -eq $false) 'open circuit: must not attempt to spawn.'
    Assert-True ($null -eq $blocked.sidecar.exitCode) 'open circuit: exitCode must be null when there is no process.'
    Assert-True ($blocked.sidecar.promptTransmission -eq 'none') 'open circuit: must not transmit the prompt.'
    Assert-True ($blocked.sidecar.quotaCircuitDecision -eq 'open') "open circuit: decision should be open; got $($blocked.sidecar.quotaCircuitDecision)."
    Assert-True ($argsAfterBlock.Count -eq $argsBeforeBlock.Count) 'open circuit: fake CLI should not be called.'
    $baseHash = $blocked.sidecar.quotaEvidence.baseKeyHash

    # Default circuit root off Windows: without -CircuitStateRoot the quota state lands
    # under the shared mimir-delegate state root ($XDG_DATA_HOME/mimir-delegate), not in the temporary
    # folder. XDG_DATA_HOME points to a folder that does not exist yet, where
    # GetFolderPath('LocalApplicationData') returns an empty string.
    if ($IsWindows) {
        Write-Host 'SKIP: off-Windows default circuit root case (Windows host; the real %LOCALAPPDATA% is not redirected)' -ForegroundColor Yellow
    }
    else {
        $savedXdg = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
        $xdgDefault = Join-Path $tmp 'xdg-default'
        try {
            $env:XDG_DATA_HOME = $xdgDefault
            $quotaDefault = Invoke-AdapterCase -TempRoot $tmp -Mode 'quota-after-text' -ClaudeExe $fake.Exe -CircuitRoot ''
            Assert-True ($quotaDefault.sidecar.technicalStatus -eq 'quota') "default circuit root: technicalStatus should be quota; got $($quotaDefault.sidecar.technicalStatus)."
            $defaultStateDir = Join-Path (Join-Path $xdgDefault 'mimir-delegate') 'claude-code-quota-circuit'
            $defaultStatePath = Join-Path $defaultStateDir "$($quotaDefault.sidecar.quotaEvidence.baseKeyHash).weekly.state.json"
            Assert-True (Test-Path -LiteralPath $defaultStatePath -PathType Leaf) "default circuit root: quota state should be under XDG_DATA_HOME/mimir-delegate ($defaultStatePath)."
        }
        finally {
            if ($null -eq $savedXdg) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdg }
        }
    }

    # Unresolvable default circuit root off Windows: no XDG_DATA_HOME, no usable HOME and an empty
    # GetFolderPath('LocalApplicationData'). The CLI still runs and keeps its classification; the
    # circuit check proceeds without state, quota recording is skipped, and the sidecar says so
    # (quotaCircuitDecision=state-root-unavailable). HOME is blank: the helper treats it as unset and
    # .NET does not fall back to the passwd home folder, so GetFolderPath is empty on any host.
    # PowerShell's own $HOME (read-only, taken from HOME at startup) is blanked too and restored.
    # A child pwsh started with the blank HOME (the fake CLI's --version probe) creates
    # ' /.local/share' under its working folder, which would make GetFolderPath non-empty for the
    # next case; each case therefore runs from a fresh process working folder under $tmp.
    if ($IsWindows) {
        Write-Host 'SKIP: off-Windows unresolvable circuit root case (Windows host)' -ForegroundColor Yellow
    }
    else {
        $savedXdgNoRoot = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
        $savedHomeEnvNoRoot = [Environment]::GetEnvironmentVariable('HOME')
        $savedHomeVarNoRoot = $HOME
        $savedCwdNoRoot = [Environment]::CurrentDirectory
        $invokeNoRootCase = {
            param([string]$Mode)
            $caseCwd = Join-Path $tmp ('no-root-cwd-' + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($caseCwd)
            # Both: .NET resolves the blank home against the process folder, and native commands
            # (the probe) start in the PowerShell location.
            [Environment]::CurrentDirectory = $caseCwd
            Push-Location -LiteralPath $caseCwd
            try {
                Assert-True ([Environment]::GetFolderPath('LocalApplicationData') -eq '') "no state root ($Mode): precondition GetFolderPath(LocalApplicationData) should be empty."
                Invoke-AdapterCase -TempRoot $tmp -Mode $Mode -ClaudeExe $fake.Exe -CircuitRoot ''
            }
            finally {
                Pop-Location
            }
        }
        try {
            Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue
            $env:HOME = ' '
            Set-Variable -Name HOME -Value '' -Scope Global -Force

            $okNoRoot = & $invokeNoRootCase 'success-delta'
            Assert-True ($okNoRoot.sidecar.technicalStatus -eq 'completed') "no state root: success should stay completed; got $($okNoRoot.sidecar.technicalStatus) ($($okNoRoot.sidecar.acceptanceRejectionReason))."
            Assert-True ($okNoRoot.sidecar.resultAccepted -eq $true) 'no state root: success should stay accepted.'
            Assert-True ($okNoRoot.stdout -eq 'AB') "no state root: accepted stdout should be 'AB'; got '$($okNoRoot.stdout)'."
            Assert-True ($okNoRoot.sidecar.quotaCircuitDecision -eq 'state-root-unavailable') "no state root: decision should be state-root-unavailable; got $($okNoRoot.sidecar.quotaCircuitDecision)."
            $noRootVariant = @($okNoRoot.sidecar.quotaEvidence.variantDecisions) | Select-Object -First 1
            Assert-True ($null -ne $noRootVariant -and $noRootVariant.decision -eq 'state-root-unavailable') 'no state root: variantDecisions should carry the state-root-unavailable warning.'
            Assert-True ([string]$noRootVariant.evidence -match 'XDG_DATA_HOME and HOME') "no state root: the warning should carry the helper's reason; got '$($noRootVariant.evidence)'."

            $quotaNoRoot = & $invokeNoRootCase 'quota-after-text'
            Assert-True ($quotaNoRoot.sidecar.technicalStatus -eq 'quota') "no state root: quota should stay quota; got $($quotaNoRoot.sidecar.technicalStatus) ($($quotaNoRoot.sidecar.acceptanceRejectionReason))."
            Assert-True ($quotaNoRoot.sidecar.acceptanceRejectionReason -eq 'quota-signal') "no state root: quota reason should be quota-signal; got $($quotaNoRoot.sidecar.acceptanceRejectionReason)."
            Assert-True ($quotaNoRoot.sidecar.quotaCircuitDecision -eq 'state-root-unavailable') "no state root: quota decision should be state-root-unavailable; got $($quotaNoRoot.sidecar.quotaCircuitDecision)."
            Assert-True ($quotaNoRoot.sidecar.quotaEvidence.quotaCircuitStateWriteStatus -eq 'state-not-written') "no state root: quota state write should be state-not-written; got $($quotaNoRoot.sidecar.quotaEvidence.quotaCircuitStateWriteStatus)."
            Assert-True ($quotaNoRoot.sidecar.quotaEvidence.quotaCircuitStateWriteReason -eq 'state-root-unavailable') "no state root: quota state write reason should be state-root-unavailable; got $($quotaNoRoot.sidecar.quotaEvidence.quotaCircuitStateWriteReason)."
        }
        finally {
            [Environment]::CurrentDirectory = $savedCwdNoRoot
            Set-Variable -Name HOME -Value $savedHomeVarNoRoot -Scope Global -Force
            if ($null -eq $savedHomeEnvNoRoot) { Remove-Item Env:\HOME -ErrorAction SilentlyContinue } else { $env:HOME = $savedHomeEnvNoRoot }
            if ($null -eq $savedXdgNoRoot) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdgNoRoot }
        }
    }

    $circuitQuotaWriteContended = Join-Path $tmp 'circuit-quota-write-contended'
    $quotaWriteContended = Invoke-AdapterCase -TempRoot $tmp -Mode 'quota-after-text' -ClaudeExe $fake.Exe `
        -CircuitRoot $circuitQuotaWriteContended -ForceQuotaStateWriteLock
    Assert-True ($quotaWriteContended.sidecar.technicalStatus -eq 'quota') 'quota with contended write: current call should be quota.'
    Assert-True ($quotaWriteContended.sidecar.quotaEvidence.quotaCircuitStateWriteStatus -eq 'open-written-lock-free-conservative') 'quota with contended write: should record durable conservative evidence.'
    $contendedDir = Join-Path $circuitQuotaWriteContended 'claude-code-quota-circuit'
    $contendedBaseHash = $quotaWriteContended.sidecar.quotaEvidence.baseKeyHash
    $contendedStates = @(Get-ChildItem -LiteralPath $contendedDir -Filter "$contendedBaseHash.*.state.json" -File -ErrorAction SilentlyContinue)
    Assert-True ($contendedStates.Count -eq 1) 'quota with contended write: exactly one conservative state should exist.'
    $contendedState = Get-Content -LiteralPath $contendedStates[0].FullName -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($contendedState.circuitState -eq 'open') 'conservative state: circuit should stay open.'
    Assert-True ($contendedState.sourceEvidence.persistenceMode -eq 'lock-free-conservative') 'conservative state: persistenceMode should mark lock-free fallback.'
    Assert-True ($contendedState.sourceEvidence.persistenceReason -eq 'circuit-lock-timeout') 'conservative state: persistenceReason should preserve the contention.'
    $argsBeforeContendedBlock = @(Get-Content -LiteralPath $fake.ArgsFile)
    $blockedByContendedWrite = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitQuotaWriteContended
    $argsAfterContendedBlock = @(Get-Content -LiteralPath $fake.ArgsFile)
    Assert-True ($blockedByContendedWrite.sidecar.quotaCircuitDecision -eq 'open') "conservative state: next call should block as open; got $($blockedByContendedWrite.sidecar.quotaCircuitDecision)."
    Assert-True ($blockedByContendedWrite.sidecar.spawnAttempted -eq $false) 'conservative state: next call must not spawn.'
    Assert-True ($argsAfterContendedBlock.Count -eq $argsBeforeContendedBlock.Count) 'conservative state: fake CLI should not be called on the next call.'

    $circuitInvalid = Join-Path $tmp 'circuit-invalid'
    $ctxDir = Join-Path $circuitInvalid 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
    $baseHash = $blocked.sidecar.quotaEvidence.baseKeyHash
    Set-Content -LiteralPath (Join-Path $ctxDir "$baseHash.hourly.state.json") -Value '{ invalid json' -Encoding utf8
    $invalid = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitInvalid
    Assert-True ($invalid.sidecar.quotaCircuitDecision -eq 'closed-with-invalid-state-ignored') "invalid state: unexpected aggregate decision $($invalid.sidecar.quotaCircuitDecision)."
    Assert-True ($invalid.stdout -eq 'AB') 'invalid state ignored: call should proceed and accept text.'
    Assert-True (Test-Path -LiteralPath (Join-Path $ctxDir "$baseHash.hourly.state.json") -PathType Leaf) 'invalid state must not be automatically deleted.'

    $circuitNewerFence = Join-Path $tmp 'circuit-newer-fence'
    $fenceDir = Join-Path $circuitNewerFence 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $fenceDir -Force | Out-Null
    $fencePath = Join-Path $fenceDir "$baseHash.weekly.state.json"
    $newerEvidenceState = [ordered]@{
        Kind          = 'claude-code-quota-circuit-state'
        SchemaVersion = 1
        circuitState  = 'open'
        baseKeyHash   = $baseHash
        backend       = 'claude-code'
        model         = 'claude-opus-4-8'
        rateLimitType = 'weekly'
        openedAtUtc   = '2020-01-01T00:00:00Z'
        updatedAtUtc  = '2020-01-01T00:00:00Z'
        observedAtUtc = '2030-01-01T00:00:00Z'
        resetsAtUtc   = '2020-01-01T00:00:01Z'
    }
    $newerEvidenceState | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath $fencePath -Encoding utf8
    $fenced = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitNewerFence
    Assert-True ($fenced.sidecar.quotaCircuitDecision -eq 'half-open') "state with newer evidence: should probe half-open; got $($fenced.sidecar.quotaCircuitDecision)."
    Assert-True ($fenced.stdout -eq 'AB') 'state with newer evidence: call should proceed and accept text.'
    Assert-True (Test-Path -LiteralPath $fencePath -PathType Leaf) 'state with newer evidence must not be deleted by stale-probe cleanup.'

    $circuitSameSecondFence = Join-Path $tmp 'circuit-same-second-fence'
    $sameSecondFenceDir = Join-Path $circuitSameSecondFence 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $sameSecondFenceDir -Force | Out-Null
    $sameSecondFencePath = Join-Path $sameSecondFenceDir "$baseHash.weekly.state.json"
    $sameSecondLegacyState = [ordered]@{
        Kind          = 'claude-code-quota-circuit-state'
        SchemaVersion = 1
        circuitState  = 'open'
        baseKeyHash   = $baseHash
        backend       = 'claude-code'
        model         = 'claude-opus-4-8'
        rateLimitType = 'weekly'
        openedAtUtc   = '2026-07-29T15:09:47Z'
        updatedAtUtc  = '2026-07-29T15:09:47Z'
        observedAtUtc = '2026-07-29T15:09:47Z'
        resetsAtUtc   = '2020-01-01T00:00:01Z'
    }
    $sameSecondLegacyState | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath $sameSecondFencePath -Encoding utf8
    $sameSecondFenced = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe `
        -CircuitRoot $circuitSameSecondFence -TestStartedAtUtc '2026-07-29T15:09:47.5000000Z'
    Assert-True ($sameSecondFenced.sidecar.quotaCircuitDecision -eq 'half-open') "legacy state in the same second: should probe half-open; got $($sameSecondFenced.sidecar.quotaCircuitDecision)."
    Assert-True ($sameSecondFenced.stdout -eq 'AB') 'legacy state in the same second: call should proceed and accept text.'
    Assert-True (Test-Path -LiteralPath $sameSecondFencePath -PathType Leaf) 'legacy state in the same second must not be deleted by sub-second truncation.'

    $circuitInvalidAndOpen = Join-Path $tmp 'circuit-invalid-and-open'
    $mixedDir = Join-Path $circuitInvalidAndOpen 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $mixedDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $mixedDir "$baseHash.hourly.state.json") -Value '{ invalid json' -Encoding utf8
    $futureOpen = [ordered]@{
        Kind          = 'claude-code-quota-circuit-state'
        SchemaVersion = 1
        circuitState  = 'open'
        baseKeyHash   = $baseHash
        backend       = 'claude-code'
        model         = 'claude-opus-4-8'
        rateLimitType = 'daily'
        openedAtUtc   = '2029-12-31T00:00:00Z'
        resetsAtUtc   = '2030-01-01T00:00:00Z'
    }
    $futureOpen | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $mixedDir "$baseHash.daily.state.json") -Encoding utf8
    $mixedBlocked = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitInvalidAndOpen
    Assert-True ($mixedBlocked.sidecar.quotaCircuitDecision -eq 'open') "invalid + open state: aggregate decision should be open; got $($mixedBlocked.sidecar.quotaCircuitDecision)."
    Assert-True ([string]::IsNullOrWhiteSpace($mixedBlocked.stdout)) 'invalid + open state: stdout should be empty.'
    Assert-True (@($mixedBlocked.sidecar.quotaEvidence.variantDecisions | ForEach-Object { $_.decision }) -contains 'state-json-invalid') 'invalid + open state: per-variant evidence should preserve state-json-invalid.'

    $circuitReadInconclusiveAndOpen = Join-Path $tmp 'circuit-read-inconclusive-and-open'
    $inconclusiveDir = Join-Path $circuitReadInconclusiveAndOpen 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $inconclusiveDir -Force | Out-Null
    $futureOpen | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $inconclusiveDir "$baseHash.daily.state.json") -Encoding utf8
    $lockedStatePath = Join-Path $inconclusiveDir "$baseHash.hourly.state.json"
    $futureOpen | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath $lockedStatePath -Encoding utf8
    $lockedState = [System.IO.File]::Open($lockedStatePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $inconclusiveBlocked = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitReadInconclusiveAndOpen
    }
    finally {
        $lockedState.Dispose()
    }
    Assert-True ($inconclusiveBlocked.sidecar.quotaCircuitDecision -eq 'state-read-inconclusive') "inconclusive read + open: aggregate decision should be state-read-inconclusive; got $($inconclusiveBlocked.sidecar.quotaCircuitDecision)."
    Assert-True ([string]::IsNullOrWhiteSpace($inconclusiveBlocked.stdout)) 'inconclusive read + open: stdout should be empty.'
    Assert-True (@($inconclusiveBlocked.sidecar.quotaEvidence.variantDecisions | ForEach-Object { $_.decision }) -contains 'open') 'inconclusive read + open: per-variant evidence should preserve open.'

    $circuitLease = Join-Path $tmp 'circuit-lease'
    $leaseDir = Join-Path $circuitLease 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null
    $expired = [ordered]@{
        Kind          = 'claude-code-quota-circuit-state'
        SchemaVersion = 1
        circuitState  = 'open'
        baseKeyHash   = $baseHash
        backend       = 'claude-code'
        model         = 'claude-opus-4-8'
        rateLimitType = 'weekly'
        openedAtUtc   = '2020-01-01T00:00:00Z'
        resetsAtUtc   = '2020-01-01T00:00:01Z'
    }

    $circuitExpiredAndOpen = Join-Path $tmp 'circuit-expired-and-open'
    $expiredAndOpenDir = Join-Path $circuitExpiredAndOpen 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $expiredAndOpenDir -Force | Out-Null
    $expired | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $expiredAndOpenDir "$baseHash.five_hour.state.json") -Encoding utf8
    $futureOpen | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $expiredAndOpenDir "$baseHash.daily.state.json") -Encoding utf8
    $argsBeforeExpiredAndOpen = @(Get-Content -LiteralPath $fake.ArgsFile)
    $expiredAndOpenBlocked = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitExpiredAndOpen
    $argsAfterExpiredAndOpen = @(Get-Content -LiteralPath $fake.ArgsFile)
    Assert-True ($expiredAndOpenBlocked.sidecar.quotaCircuitDecision -eq 'open') "multi-type expired+open: decision should be open; got $($expiredAndOpenBlocked.sidecar.quotaCircuitDecision)."
    Assert-True ($expiredAndOpenBlocked.sidecar.spawnAttempted -eq $false) 'multi-type expired+open: must not transmit the prompt.'
    Assert-True ($argsAfterExpiredAndOpen.Count -eq $argsBeforeExpiredAndOpen.Count) 'multi-type expired+open: fake CLI should not be called.'
    $expiredAndOpenDecisions = @($expiredAndOpenBlocked.sidecar.quotaEvidence.variantDecisions | ForEach-Object { $_.decision })
    Assert-True ($expiredAndOpenDecisions -contains 'open') 'multi-type expired+open: should preserve the open variant.'
    Assert-True ($expiredAndOpenDecisions -contains 'expired-open') 'multi-type expired+open: should preserve the expired variant.'

    $circuitTwoOpen = Join-Path $tmp 'circuit-two-open'
    $twoOpenDir = Join-Path $circuitTwoOpen 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $twoOpenDir -Force | Out-Null
    $futureOpen | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $twoOpenDir "$baseHash.daily.state.json") -Encoding utf8
    $futureOpenWeekly = [ordered]@{
        Kind          = 'claude-code-quota-circuit-state'
        SchemaVersion = 1
        circuitState  = 'open'
        baseKeyHash   = $baseHash
        backend       = 'claude-code'
        model         = 'claude-opus-4-8'
        rateLimitType = 'weekly'
        openedAtUtc   = '2029-12-31T00:00:00Z'
        resetsAtUtc   = '2030-01-01T00:00:00Z'
    }
    $futureOpenWeekly | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $twoOpenDir "$baseHash.weekly.state.json") -Encoding utf8
    $twoOpenBlocked = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitTwoOpen
    $twoOpenDecisions = @($twoOpenBlocked.sidecar.quotaEvidence.variantDecisions | Where-Object { $_.decision -eq 'open' })
    Assert-True ($twoOpenBlocked.sidecar.quotaCircuitDecision -eq 'open') "two open variants: decision should be open; got $($twoOpenBlocked.sidecar.quotaCircuitDecision)."
    Assert-True ($twoOpenBlocked.sidecar.spawnAttempted -eq $false) 'two open variants: must not transmit the prompt.'
    Assert-True ($twoOpenDecisions.Count -eq 2) "two open variants: should record two open variants; recorded $($twoOpenDecisions.Count)."

    $circuitInvalidAndExpired = Join-Path $tmp 'circuit-invalid-and-expired'
    $invalidAndExpiredDir = Join-Path $circuitInvalidAndExpired 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $invalidAndExpiredDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $invalidAndExpiredDir "$baseHash.hourly.state.json") -Value '{ invalid json' -Encoding utf8
    $expired | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $invalidAndExpiredDir "$baseHash.daily.state.json") -Encoding utf8
    $invalidAndExpired = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitInvalidAndExpired
    Assert-True ($invalidAndExpired.sidecar.quotaCircuitDecision -eq 'closed-with-invalid-state-ignored') "invalid+expired: decision should be closed-with-invalid-state-ignored; got $($invalidAndExpired.sidecar.quotaCircuitDecision)."
    Assert-True ($invalidAndExpired.sidecar.quotaEvidence.quotaCircuitLeaseOwned -eq $true) 'invalid+expired: should acquire a half-open lease per base key before transmitting.'
    Assert-True ($invalidAndExpired.stdout -eq 'AB') 'invalid+expired: owning probe should accept text.'
    Assert-True (Test-Path -LiteralPath (Join-Path $invalidAndExpiredDir "$baseHash.hourly.state.json") -PathType Leaf) 'invalid+expired: invalid state must not be automatically deleted.'

    $circuitReadInconclusiveAndExpired = Join-Path $tmp 'circuit-read-inconclusive-and-expired'
    $inconclusiveExpiredDir = Join-Path $circuitReadInconclusiveAndExpired 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $inconclusiveExpiredDir -Force | Out-Null
    $expired | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $inconclusiveExpiredDir "$baseHash.daily.state.json") -Encoding utf8
    $lockedExpiredPeerPath = Join-Path $inconclusiveExpiredDir "$baseHash.hourly.state.json"
    $futureOpen | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath $lockedExpiredPeerPath -Encoding utf8
    $lockedExpiredPeer = [System.IO.File]::Open($lockedExpiredPeerPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $inconclusiveAndExpired = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitReadInconclusiveAndExpired
    }
    finally {
        $lockedExpiredPeer.Dispose()
    }
    Assert-True ($inconclusiveAndExpired.sidecar.quotaCircuitDecision -eq 'state-read-inconclusive') "inconclusive read+expired: decision should be state-read-inconclusive; got $($inconclusiveAndExpired.sidecar.quotaCircuitDecision)."
    Assert-True ($inconclusiveAndExpired.sidecar.spawnAttempted -eq $false) 'inconclusive read+expired: must not transmit the prompt.'
    Assert-True (@($inconclusiveAndExpired.sidecar.quotaEvidence.variantDecisions | ForEach-Object { $_.decision }) -contains 'expired-open') 'inconclusive read+expired: should preserve evidence of the expired variant.'

    $expired | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $leaseDir "$baseHash.weekly.state.json") -Encoding utf8
    $lease = [ordered]@{
        Kind              = 'claude-code-quota-half-open-lease'
        SchemaVersion     = 1
        baseKeyHash       = $baseHash
        probeStartedAtUtc = '2029-12-31T00:00:00Z'
        probeExpiresAtUtc = '2030-01-01T00:00:00Z'
    }
    $lease | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $leaseDir "$baseHash.lease.json") -Encoding utf8
    $observed = Invoke-AdapterCase -TempRoot $tmp -Mode 'success-delta' -ClaudeExe $fake.Exe -CircuitRoot $circuitLease
    Assert-True ($observed.sidecar.quotaCircuitDecision -eq 'half-open-observed') "lease: decision should be half-open-observed; got $($observed.sidecar.quotaCircuitDecision)."
    Assert-True ($observed.sidecar.spawnAttempted -eq $false) 'lease: must not spawn when an active half-open probe exists.'

    $circuitConcurrentLease = Join-Path $tmp 'circuit-concurrent-lease'
    $concurrentDir = Join-Path $circuitConcurrentLease 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $concurrentDir -Force | Out-Null
    $expired | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $concurrentDir "$baseHash.weekly.state.json") -Encoding utf8
    $expiredDaily = [ordered]@{
        Kind          = 'claude-code-quota-circuit-state'
        SchemaVersion = 1
        circuitState  = 'open'
        baseKeyHash   = $baseHash
        backend       = 'claude-code'
        model         = 'claude-opus-4-8'
        rateLimitType = 'daily'
        openedAtUtc   = '2020-01-01T00:00:00Z'
        resetsAtUtc   = '2020-01-01T00:00:01Z'
    }
    $expiredDaily | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $concurrentDir "$baseHash.daily.state.json") -Encoding utf8
    if (Test-Path -LiteralPath $fake.ArgsFile -PathType Leaf) {
        $argsBeforeConcurrent = @(Get-Content -LiteralPath $fake.ArgsFile)
    }
    else {
        $argsBeforeConcurrent = @()
    }
    $concurrentA = Start-AdapterProcessCase -TempRoot $tmp -Mode 'success-slow' -ClaudeExe $fake.Exe -CircuitRoot $circuitConcurrentLease
    $concurrentB = Start-AdapterProcessCase -TempRoot $tmp -Mode 'success-slow' -ClaudeExe $fake.Exe -CircuitRoot $circuitConcurrentLease
    $concurrentResultA = Receive-AdapterProcessCase -Case $concurrentA
    $concurrentResultB = Receive-AdapterProcessCase -Case $concurrentB
    $concurrentResults = @($concurrentResultA, $concurrentResultB)
    $spawnedConcurrent = @($concurrentResults | Where-Object { $_.sidecar.spawnAttempted -eq $true })
    $blockedConcurrent = @($concurrentResults | Where-Object { $_.sidecar.quotaCircuitDecision -eq 'half-open-observed' })
    $argsAfterConcurrent = @(Get-Content -LiteralPath $fake.ArgsFile)
    Assert-True ($spawnedConcurrent.Count -eq 1) "half-open concurrency: exactly one probe should spawn; spawned $($spawnedConcurrent.Count)."
    Assert-True ($blockedConcurrent.Count -eq 1) "half-open concurrency: exactly one probe should observe the lease; observed $($blockedConcurrent.Count)."
    Assert-True ($spawnedConcurrent[0].sidecar.quotaCircuitDecision -eq 'half-open') "half-open concurrency: the owning probe should record half-open; got $($spawnedConcurrent[0].sidecar.quotaCircuitDecision)."
    Assert-True ($spawnedConcurrent[0].sidecar.resultAccepted -eq $true) 'half-open concurrency: the owning probe should accept the final result.'
    Assert-True ($spawnedConcurrent[0].stdout -eq 'SONDA') "half-open concurrency: owning probe's stdout should contain the accepted text."
    Assert-True ($blockedConcurrent[0].sidecar.spawnAttempted -eq $false) 'half-open concurrency: the blocked call must not spawn.'
    Assert-True ([string]::IsNullOrWhiteSpace($blockedConcurrent[0].stdout)) 'half-open concurrency: the blocked call must not write stdout.'
    Assert-True (($argsAfterConcurrent.Count - $argsBeforeConcurrent.Count) -eq 1) 'half-open concurrency: fake CLI should receive exactly one call.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $concurrentDir "$baseHash.lease.json") -PathType Leaf)) "half-open concurrency: its own lease should be removed after success."
    $remainingConcurrentStates = @(Get-ChildItem -LiteralPath $concurrentDir -Filter "$baseHash.*.state.json" -File -ErrorAction SilentlyContinue)
    Assert-True ($remainingConcurrentStates.Count -eq 0) "half-open concurrency: expired states should be closed under the owning probe's lock."

    $circuitProbeLease = Join-Path $tmp 'circuit-probe-lease'
    $probeLeaseDir = Join-Path $circuitProbeLease 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $probeLeaseDir -Force | Out-Null
    $expired | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $probeLeaseDir "$baseHash.weekly.state.json") -Encoding utf8
    # The fake CLI starts a fresh pwsh before its first text line; on a slow hosted runner that
    # startup alone can exceed one second, so the timeout leaves room for the partial text.
    $probeTimeout = Invoke-AdapterCase -TempRoot $tmp -Mode 'timeout-after-text' -ClaudeExe $fake.Exe `
        -CircuitRoot $circuitProbeLease -TimeoutSec 5 -RetentionMode 'kb-sensitive'
    Assert-True ($probeTimeout.sidecar.quotaCircuitDecision -eq 'half-open') "new lease: decision should be half-open; got $($probeTimeout.sidecar.quotaCircuitDecision)."
    Assert-True ([string]::IsNullOrWhiteSpace($probeTimeout.stdout)) 'timeout after text: stdout should be empty.'
    Assert-True ($probeTimeout.sidecar.technicalStatus -eq 'timeout') 'timeout after text: technicalStatus should be timeout.'
    Assert-True ($null -ne $probeTimeout.sidecar.failureAfterText) "timeout after text: no partial text was captured before the timeout (durationMs=$($probeTimeout.sidecar.durationMs)); the fake CLI started too slowly."
    Assert-True ($probeTimeout.sidecar.failureAfterText.reason -eq 'timeout-after-partial-text') 'timeout after text: failureAfterText should record timeout-after-partial-text.'
    Assert-True ([int]$probeTimeout.sidecar.failureAfterText.textBytes -gt 0) 'timeout after text: textBytes should be greater than zero.'
    Assert-True ($null -eq $probeTimeout.sidecar.failureAfterText.textSha256) 'timeout after text kb-sensitive: textSha256 should be null.'
    Assert-True ($probeTimeout.sidecar.retentionCleanupFailed -eq $false) 'timeout after text kb-sensitive: stream/stderr cleanup should complete.'
    Assert-NoRawCaptureFiles -Path $probeTimeout.adapterTemp -Message 'kb-sensitive timeout after text'
    $newLease = Get-Content -LiteralPath (Join-Path $probeLeaseDir "$baseHash.lease.json") -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($newLease.probeOwner.jobId -eq $newLease.probeAttemptId) "new lease: probeOwner/probeAttemptId should share the attempt's job."
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$newLease.probeAttemptId)) 'new lease: probeAttemptId missing.'
    Assert-True ([int]$newLease.probeLeaseSeconds -eq 120) 'new lease: TimeoutSec=5 should generate probeLeaseSeconds=120.'
    $leaseSeconds = [int](([datetime]$newLease.probeExpiresAtUtc - [datetime]$newLease.probeStartedAtUtc).TotalSeconds)
    Assert-True ($leaseSeconds -eq 120) 'new lease: persisted window should be 120 seconds.'

    $circuitProbeLeaseLong = Join-Path $tmp 'circuit-probe-lease-long'
    $probeLeaseLongDir = Join-Path $circuitProbeLeaseLong 'claude-code-quota-circuit'
    New-Item -ItemType Directory -Path $probeLeaseLongDir -Force | Out-Null
    $expired | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath (Join-Path $probeLeaseLongDir "$baseHash.weekly.state.json") -Encoding utf8
    $exitPartial = Invoke-AdapterCase -TempRoot $tmp -Mode 'exit-after-text' -ClaudeExe $fake.Exe `
        -CircuitRoot $circuitProbeLeaseLong -TimeoutSec 180
    Assert-True ([string]::IsNullOrWhiteSpace($exitPartial.stdout)) 'process exit after text: stdout should be empty.'
    Assert-True ($exitPartial.sidecar.technicalStatus -eq 'internalError') 'process exit after text: technicalStatus should be internalError.'
    Assert-True ($exitPartial.sidecar.failureAfterText.reason -eq 'process-exit-after-partial-text') 'process exit after text: failureAfterText should record process-exit-after-partial-text.'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$exitPartial.sidecar.failureAfterText.textSha256)) 'process exit after text public: textSha256 should exist.'
    $longLease = Get-Content -LiteralPath (Join-Path $probeLeaseLongDir "$baseHash.lease.json") -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ([int]$longLease.probeLeaseSeconds -eq 210) 'long lease: TimeoutSec=180 should generate probeLeaseSeconds=210.'

    $sensitiveExitPartial = Invoke-AdapterCase -TempRoot $tmp -Mode 'exit-after-text' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-exit-kb') -RetentionMode 'kb-sensitive'
    Assert-True ([string]::IsNullOrWhiteSpace($sensitiveExitPartial.stdout)) 'process exit after text kb-sensitive: stdout should be empty.'
    Assert-True ($sensitiveExitPartial.sidecar.failureAfterText.reason -eq 'process-exit-after-partial-text') 'process exit after text kb-sensitive: failureAfterText should record process-exit-after-partial-text.'
    Assert-True ($null -eq $sensitiveExitPartial.sidecar.failureAfterText.textSha256) 'process exit after text kb-sensitive: textSha256 should be null.'
    Assert-True ($sensitiveExitPartial.sidecar.retentionCleanupFailed -eq $false) 'process exit after text kb-sensitive: stream/stderr cleanup should complete.'
    Assert-NoRawCaptureFiles -Path $sensitiveExitPartial.adapterTemp -Message 'kb-sensitive process exit after text'

    $timeout = Invoke-AdapterCase -TempRoot $tmp -Mode 'sleep' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-timeout') -TimeoutSec 1
    Assert-True ($timeout.sidecar.technicalStatus -eq 'timeout') 'timeout: technicalStatus should be timeout.'
    Assert-True ($timeout.sidecar.cancelRequested -eq $true) 'timeout: cancelRequested=true expected.'
    Assert-True ($timeout.sidecar.processIdentity.startTimeUtc -ne $null) 'timeout: real StartTime should be captured.'
    Assert-True ($timeout.sidecar.acceptanceRejectionReason -eq 'timeout') 'normal timeout must not become cancelled.'
    Assert-True ($timeout.sidecar.processIdentityVerified -eq $true) 'timeout: real identity should be verifiable on the normal path.'
    Assert-True ($timeout.sidecar.cancelIssued -eq $true) 'timeout: process with verifiable identity should receive cancellation.'

    $unverifiableTimeout = Invoke-AdapterCase -TempRoot $tmp -Mode 'sleep' -ClaudeExe $fake.Exe `
        -CircuitRoot (Join-Path $tmp 'circuit-timeout-unverifiable') -TimeoutSec 1 -ForceIdentityUnverifiable
    Assert-True ($unverifiableTimeout.sidecar.technicalStatus -eq 'timeout') 'timeout unverifiable identity: technicalStatus should be timeout.'
    Assert-True ($unverifiableTimeout.sidecar.cancelRequested -eq $true) 'timeout unverifiable identity: cancelRequested=true expected.'
    Assert-True ($unverifiableTimeout.sidecar.processIdentityVerified -eq $false) 'timeout unverifiable identity: processIdentityVerified should be false.'
    Assert-True ($unverifiableTimeout.sidecar.cancelIdentityUnverifiable -eq $true) 'timeout unverifiable identity: must record the inability to validate identity.'
    Assert-True ($unverifiableTimeout.sidecar.cancelIssued -eq $false) 'timeout unverifiable identity: must not kill a process without verifiable identity.'

    Write-Output 'OK: Test-ClaudeCodeAsyncSelfTest.ps1'
}
finally {
    if ($null -eq $previousMode) { Remove-Item Env:\FAKE_CLAUDE_MODE -ErrorAction SilentlyContinue }
    else { $env:FAKE_CLAUDE_MODE = $previousMode }
    Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_IDENTITY_UNVERIFIABLE -ErrorAction SilentlyContinue
    Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_FORCE_QUOTA_STATE_WRITE_LOCK -ErrorAction SilentlyContinue
    Remove-Item Env:\MIMIR_TEST_CLAUDE_ASYNC_STARTED_AT_UTC -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
