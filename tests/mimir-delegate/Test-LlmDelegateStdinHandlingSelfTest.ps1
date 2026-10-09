#requires -Version 7.4

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Self-test for stdin handling in the mimir-delegate skill's adapters.
#
# Bug covered: an agentic CLI (opencode/gemini/copilot/antigravity) called from a headless
# shell without a TTY HANGS reading the inherited stdin (open pipe, no EOF).
#
# Two adapter regimes, both give the CLI an EOF (anti-hang):
#  - stdin-based (Invoke-Codex, Invoke-ClaudeCode,
#    Invoke-OpenCode): deliver the prompt VIA stdin through
#    Start-Process -RedirectStandardInput <file>; the end of the file gives EOF. The prompt
#    stays OUT of argv (resolves Windows' ~32KB command-line limit).
#  - argument-based (Invoke-Gemini/Invoke-Copilot/Invoke-Antigravity): pass the prompt as an ARGUMENT and
#    close stdin in the runner with "$null | & ([string]$req.exe)" (pure EOF, no bytes).
#
# Layers:
#  (A) Behavioral proof of EOF: a fake-detector reads stdin; with stdin closed
#      ($null = EOF) it returns and exits 7; with stdin open it blocks.
#  (B) Static anti-regression guard: every stdin-based adapter uses -RedirectStandardInput and
#      does NOT close stdin with "$null | & ..."; every argument-based one closes it with "$null | & ...".
#  (C) Behavioral proof of the stdin-based opencode adapter + the ~32KB limit: calls the REAL
#      adapter (Invoke-OpenCode) with an injected fake-exe (-OpenCodeExe) and a prompt > 32KB via
#      -MessagePath; the prompt arrives through stdin (argv would overflow at ~32KB) and the adapter returns
#      the parsed response from the stream. Scope: proves the delivery MECHANISM (stdin, outside
#      argv); the REAL opencode's ability to consume stdin was verified empirically
#      outside this self-test.

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# --- (A) Behavioral proof of the EOF mechanism -------------------------------

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-llm-stdin-selftest-' + [System.Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

try {
    # fake-detector: on the --version/--help probe prints and exits 0; otherwise reads stdin
    # until EOF (returns right away if closed; blocks if open) and exits 7.
    $detector = Join-Path $tempRoot 'fake-detector.ps1'
    @'
param()
if ($args -contains '--version' -or $args -contains '--help') { 'fake 1.0'; exit 0 }
[void][Console]::In.ReadToEnd()
exit 7
'@ | Set-Content -LiteralPath $detector -Encoding utf8

    # Positive: "$null |" delivers a pure EOF -> the detector returns and exits 7, fast.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null | & pwsh -NoProfile -File $detector 1> $null 2> $null
    $closedCode = $LASTEXITCODE
    $closedSecs = $sw.Elapsed.TotalSeconds
    Assert-True ($closedCode -eq 7) "With stdin closed (`$null |), the detector should exit 7; exited $closedCode."
    Assert-True ($closedSecs -lt 20) "With stdin closed, the detector should return fast; took $([math]::Round($closedSecs,1))s."

    # Negative (control): with stdin OPEN (RedirectStandardInput not closed), the
    # detector blocks on ReadToEnd -> proves the positive test is not vacuous.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'pwsh'
    $psi.Arguments = "-NoProfile -File `"$detector`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        # stdin open with no data: the detector should keep blocking.
        $exitedBlocked = $proc.WaitForExit(4000)
        Assert-True (-not $exitedBlocked) 'With stdin OPEN, the detector should block reading stdin (proves the fix is not vacuous).'
    }
    finally {
        # Process-tree cleanup (the native child doesn't die by killing just the parent).
        try { $proc.Kill($true) } catch { }
        try { $proc.Dispose() } catch { }
    }

    # --- (B) Static anti-regression guard on the real adapters --------------

    # argument-based: prompt in argv + stdin closed with "$null | & ([string]$req.exe)".
    $argumentBased = @(
        'Invoke-Gemini.ps1'
        'Invoke-Copilot.ps1'
        'Invoke-Antigravity.ps1'
    )
    foreach ($name in $argumentBased) {
        $path = Join-Path $scriptsDir $name
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing argument-based adapter: $name"
        $text = [System.IO.File]::ReadAllText($path)
        Assert-True ($text -match '\$null\s*\|\s*&\s*\(\[string\]\$req\.exe\)') `
            "Argument-based adapter '$name' should close the CLI's stdin in the runner with '`$null | & ([string]`$req.exe)' (regression of the headless-stdin fix)."
    }

    # stdin-based: prompt via -RedirectStandardInput (file); does NOT close stdin with "$null | & ...".
    $stdinBased = @(
        'Invoke-Codex.ps1'
        'Invoke-ClaudeCode.ps1'
        'Invoke-OpenCode.ps1'
    )
    foreach ($name in $stdinBased) {
        $path = Join-Path $scriptsDir $name
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing stdin-based adapter: $name"
        $text = [System.IO.File]::ReadAllText($path)
        Assert-True ($text -match '-RedirectStandardInput') `
            "Stdin-based adapter '$name' should deliver the prompt via Start-Process -RedirectStandardInput."
        Assert-True (-not ($text -match '\$null\s*\|\s*&\s*\(\[string\]\$req\.exe\)')) `
            "Stdin-based adapter '$name' must NOT close the CLI's stdin with '`$null | & ([string]`$req.exe)': the prompt is delivered VIA stdin."
    }

    # The opencode adapter must not pass the prompt in argv (~32KB command-line limit):
    # the prompt goes through stdin and the args stay literal, without the prompt.
    foreach ($name in @('Invoke-OpenCode.ps1')) {
        $path = Join-Path $scriptsDir $name
        $text = [System.IO.File]::ReadAllText($path)
        Assert-True (-not $text.Contains('$req.prompt')) `
            "Adapter '$name' must not reference `$req.prompt (the prompt goes through stdin, never argv)."
        Assert-True ($text.Contains("@('run', '--format', 'json')")) `
            "Adapter '$name' should assemble the opencode args without the prompt: @('run', '--format', 'json')."
    }

    # --- (C) Behavioral proof: stdin-based opencode + prompt > 32KB -----

    # REAL fake-exe (an executable that Start-Process -FilePath can invoke): a New-FakeCli launcher
    # that runs a pwsh reader. The reader consumes all of stdin, measures its size, and emits the minimal opencode
    # JSON stream (text + step_finish reason=stop) that OpenCodeStreamSupport knows how to parse.
    $fakeCmd = New-FakeCli -Directory $tempRoot -Name 'fake-opencode' -PwshBody @'
$a = @($args)
# Guard D1/D2: opt-out -Agent reviewer-fake -> the adapter calls `agent list` to confirm it
# resolves; respond without reading stdin (does not interfere with the >32KB stdin proof on the run branch).
if ($a.Count -ge 2 -and $a[0] -eq 'agent' -and $a[1] -eq 'list') {
    'reviewer-fake (all)'
    '['
    '{"permission":"*","action":"deny","pattern":"*"},'
    '{"permission":"read","action":"allow","pattern":"*"},'
    '{"permission":"grep","action":"allow","pattern":"*"},'
    '{"permission":"glob","action":"allow","pattern":"*"},'
    '{"permission":"list","action":"allow","pattern":"*"},'
    '{"permission":"external_directory","action":"deny","pattern":"*"}'
    ']'
    exit 0
}
$s = [Console]::In.ReadToEnd()
$n = $s.Length
'{"type":"text","part":{"messageID":"m1","text":"FAKELEN=' + $n + '"}}'
'{"type":"step_finish","part":{"reason":"stop"}}'
'@

    # Prompt > 32KB (Windows command-line limit ~32767). Via argv it would overflow;
    # via stdin (what the adapter does) it passes.
    $bigLen = 40000
    $bigPrompt = ('A' * $bigLen)
    $bigFile = Join-Path $tempRoot 'big-prompt.txt'
    Set-Content -LiteralPath $bigFile -Value $bigPrompt -Encoding utf8 -NoNewline

    $invoke = Join-Path $scriptsDir 'Invoke-OpenCode.ps1'
    $answer = & $invoke -OpenCodeExe $fakeCmd -Agent 'reviewer-fake' -MessagePath $bigFile -Model 'fake/model' -TimeoutSec 60
    $answer = [string]$answer

    Assert-True ($answer -match 'FAKELEN=(\d+)') `
        "The opencode adapter should return the fake-exe's parsed response (FAKELEN=<n>); returned: '$answer'."
    $seen = [int]$Matches[1]
    Assert-True ($seen -ge 32768) `
        "The prompt > 32KB should arrive whole through stdin; the fake-exe read $seen chars (expected >= 32768) — a sign the prompt did not go through stdin."

    # --- (D) Static -MessagePath guard on the $messagePathAdapters adapters (Front 1) ---
    # WITHOUT a count in the text, on purpose: a count in prose doesn't track a new backend and no
    # search for a backend name finds it ("four" doesn't contain "Antigravity"). The list below is the
    # only source; the text refers to it, never to a number.
    # By independent TOKENS (not a fixed substring, since the -Raw/-Encoding order can vary):
    # the -MessagePath parameter in the 'FromFile' set, the Get-Content -LiteralPath $MessagePath
    # -Raw -Encoding utf8 read, and the Test-Path -LiteralPath $MessagePath -PathType Leaf guard. Mirrors
    # Invoke-OpenCode.ps1:61-89. There is NO >32KB behavioral proof here for the stdin-based ones
    # (case C already proves the principle for opencode) nor for the argument-based ones (it would be misleading:
    # Gemini/Copilot/Antigravity keep it in argv). Only Invoke-Codex has a dedicated behavioral proof (section E).
    $messagePathAdapters = @(
        'Invoke-Codex.ps1'
        'Invoke-ClaudeCode.ps1'
        'Invoke-Gemini.ps1'
        'Invoke-Copilot.ps1'
        'Invoke-Antigravity.ps1'
    )
    foreach ($name in $messagePathAdapters) {
        $mpPath = Join-Path $scriptsDir $name
        Assert-True (Test-Path -LiteralPath $mpPath -PathType Leaf) "Missing adapter: $name"
        $mpText = [System.IO.File]::ReadAllText($mpPath)
        $mpLines = @($mpText -split "`r?`n")

        Assert-True ($mpText -match "ParameterSetName\s*=\s*'FromFile'") `
            "Adapter '$name' should declare -MessagePath in the 'FromFile' ParameterSet."
        Assert-True ($mpText -match '\[string\]\s*\$MessagePath') `
            "Adapter '$name' should declare the [string] `$MessagePath parameter."

        $mpReadLine = @($mpLines | Where-Object { $_ -match 'Get-Content' -and $_ -match '\$MessagePath' }) | Select-Object -First 1
        Assert-True ($mpReadLine -and $mpReadLine -match '-LiteralPath' -and $mpReadLine -match '-Raw' -and $mpReadLine -match '-Encoding\s+utf8') `
            "Adapter '$name' should read -MessagePath with 'Get-Content -LiteralPath `$MessagePath -Raw -Encoding utf8' (tokens in any order)."

        $mpGuardLine = @($mpLines | Where-Object { $_ -match 'Test-Path' -and $_ -match '\$MessagePath' }) | Select-Object -First 1
        Assert-True ($mpGuardLine -and $mpGuardLine -match '-LiteralPath' -and $mpGuardLine -match '-PathType\s+Leaf') `
            "Adapter '$name' should guard -MessagePath with 'Test-Path -LiteralPath `$MessagePath -PathType Leaf'."
    }

    # Argument-based adapters (Gemini/Copilot/Antigravity): fail-closed size guard (prompt goes in argv).
    foreach ($name in @('Invoke-Gemini.ps1', 'Invoke-Copilot.ps1', 'Invoke-Antigravity.ps1')) {
        $agText = [System.IO.File]::ReadAllText((Join-Path $scriptsDir $name))
        Assert-True ($agText -match '\$MaxArgvPromptChars\s*=\s*30000') `
            "Argument-based adapter '$name' should define the size guard `$MaxArgvPromptChars = 30000."
        Assert-True ($agText -match '\$Message\.Length\s*-gt\s*\$MaxArgvPromptChars') `
            "Argument-based adapter '$name' should compare `$Message.Length to `$MaxArgvPromptChars (covers -Message and -MessagePath)."
        Assert-True ($agText -match 'exceeds the \$MaxArgvPromptChars ceiling') `
            "Argument-based adapter '$name' should throw a fail-closed BLOCK citing the margin above the limit."
    }

    # --- (E) Behavioral proof: Invoke-Codex -MessagePath -> $Message -> stdin -> -o -> return ---
    # Goal (distinct from case C, which proves >32KB on opencode): prove the -MessagePath CHAIN in
    # Codex. This is NOT a 32KB test (Codex is stdin-based, already immune). The fake-exe scans $args for '-o',
    # reads stdin (what the adapter delivered from $Message), and writes CODEXFAKE=<stdin-len> as
    # RAW TEXT into the -o file (the adapter returns the literal content of output-last-message, without
    # JSON parsing — unlike opencode's fake). New-FakeCli launcher + pwsh body because
    # Start-Process -FilePath does not invoke a .ps1 directly; the launcher forwards every argument
    # to the body so it sees the '-o'.
    $fakeCodexCmd = New-FakeCli -Directory $tempRoot -Name 'fake-codex' -PwshBody @'
$o = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '-o') { $o = $args[$i + 1]; break } }
$s = [Console]::In.ReadToEnd()
# Off Windows, pwsh's Start-Process -RedirectStandardInput copies the file line by line and adds a
# final newline (observed on pwsh 7.4.2, 7.4.6 and 7.5.0); count the prompt without that transport byte.
if (-not $IsWindows -and $s.EndsWith("`n")) { $s = $s.Substring(0, $s.Length - 1) }
if ($o) { Set-Content -LiteralPath $o -Value ('CODEXFAKE=' + $s.Length) -Encoding utf8 -NoNewline }
exit 0
'@

    $codexPromptText = 'Test prompt -MessagePath for Codex, with pt-BR accents: cao, revisao, deducao.'
    $codexFile = Join-Path $tempRoot 'codex-mp-prompt.txt'
    Set-Content -LiteralPath $codexFile -Value $codexPromptText -Encoding utf8 -NoNewline
    $codexExpectedLen = $codexPromptText.Length

    $invokeCodex = Join-Path $scriptsDir 'Invoke-Codex.ps1'
    $codexTempDir = Join-Path $tempRoot 'codex-jobs-isolated'
    [System.IO.Directory]::CreateDirectory($codexTempDir) | Out-Null
    $prevCodexDisableKeepDays = $env:MIMIR_CODEX_DISABLE_KEEPDAYS
    $env:MIMIR_CODEX_DISABLE_KEEPDAYS = '1'
    try {
        $codexAnswer = [string](& $invokeCodex -CodexExe $fakeCodexCmd -MessagePath $codexFile -TimeoutSec 60 -TempDir $codexTempDir)
    } finally {
        if ($null -eq $prevCodexDisableKeepDays) {
            Remove-Item Env:\MIMIR_CODEX_DISABLE_KEEPDAYS -ErrorAction SilentlyContinue
        } else {
            $env:MIMIR_CODEX_DISABLE_KEEPDAYS = $prevCodexDisableKeepDays
        }
    }

    Assert-True ($codexAnswer -match 'CODEXFAKE=(\d+)') `
        "Invoke-Codex -MessagePath should return the fake's literal output-last-message content (CODEXFAKE=<n>); returned: '$codexAnswer'."
    $codexSeen = [int]$Matches[1]
    Assert-True ($codexSeen -eq $codexExpectedLen) `
        "-MessagePath should reach `$Message and Codex via stdin: expected $codexExpectedLen chars, the fake read $codexSeen from stdin."

    Write-Output 'OK: Test-LlmDelegateStdinHandlingSelfTest.ps1'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
