#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the process and temp-file cleanup of the mimir-delegate adapters.
.DESCRIPTION
    Two behavioral checks against fake CLIs (tests/fixtures/FakeCliSupport.ps1), no real CLI:

    1. Timeout kills the whole process tree (Copilot, Gemini, Claude Code). The fake CLI records
       its own process ID and sleeps past a short timeout. After the adapter reports the timeout,
       the recorded process must no longer exist. The fake is a launcher (cmd.exe on Windows, sh
       elsewhere) that starts a pwsh body, and Copilot and Gemini add a pwsh runner in between,
       so the recorded process is always a grandchild or deeper.

    2. A run leaves nothing in the temp folder (Copilot, Gemini, Claude Code, Antigravity). TEMP,
       TMP and TMPDIR point at an empty scratch folder for the adapter call, and the folder must
       be empty afterwards. Antigravity gets an explicit -ScratchPath outside that folder: its
       default isolated workspace lives under a reused 'mimir-agy-public-review' parent folder in
       the temp path by design, which is not the per-call leak this test pins.

    Every scratch path is created under the system temp path, outside the repository, and removed
    at the end. Surviving fake processes are stopped in the finally block.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

$scriptsDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts'

$fail = 0
function Assert-True {
    param([bool]$Condition, [string]$Label)
    if ($Condition) {
        Write-Host ("PASS  {0}" -f $Label) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0}" -f $Label) -ForegroundColor Red
    }
}

$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-adapter-cleanup-selftest-' + [guid]::NewGuid().ToString('N'))
$fakeDir = Join-Path $scratchRoot 'fakes'
[void][System.IO.Directory]::CreateDirectory($fakeDir)
$recordedPids = [System.Collections.Generic.List[int]]::new()

# Help text that satisfies every adapter's contract check (each one only looks for its own flags).
$helpText = 'Usage: -p --prompt --model --output-format --stream --no-custom-instructions --disable-builtin-mcps --available-tools --allow-all-tools --approval-mode --print --no-session-persistence --permission-mode --tools --mode'

function New-AdapterFake {
    <#
        A fake CLI that answers --version/--help for the resolvers and, on a real call, either
        records its PID and sleeps (-SleepSec > 0) or prints -Response and exits 0.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Version,
        [string] $PidFile = '',
        [int] $SleepSec = 0,
        [string] $Response = ''
    )
    $body = @'
if ($args -contains '--version') { '__VERSION__'; exit 0 }
if ($args -contains '--help') { '__HELP__'; exit 0 }
if (__SLEEP__ -gt 0) {
    Set-Content -LiteralPath '__PIDFILE__' -Value $PID -Encoding utf8
    Start-Sleep -Seconds __SLEEP__
    exit 0
}
Write-Output '__RESPONSE__'
exit 0
'@
    $body = $body.Replace('__VERSION__', $Version).Replace('__HELP__', $helpText).
        Replace('__SLEEP__', [string]$SleepSec).Replace('__PIDFILE__', $PidFile.Replace("'", "''")).
        Replace('__RESPONSE__', $Response.Replace("'", "''"))
    return New-FakeCli -Directory $fakeDir -Name $Name -PwshBody $body
}

function Test-ProcessGone {
    # Polls briefly: tree termination is asynchronous.
    param([int]$ProcessId)
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return ($null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

$adapters = @(
    [pscustomobject]@{ Name = 'Copilot'; Script = 'Invoke-Copilot.ps1'; ExeParam = 'CopilotExe'; Version = '1.0.78'; Extra = @{}
        Response = '{"type":"assistant.message","data":{"content":"FAKE_OK"}}' }
    [pscustomobject]@{ Name = 'Gemini'; Script = 'Invoke-Gemini.ps1'; ExeParam = 'GeminiExe'; Version = '0.54.0'; Extra = @{}
        Response = '{"response":"FAKE_OK"}' }
    [pscustomobject]@{ Name = 'ClaudeCode'; Script = 'Invoke-ClaudeCode.ps1'; ExeParam = 'ClaudeExe'; Version = '2.1.118'; Extra = @{}
        Response = 'FAKE_OK' }
)

try {
    # -----------------------------------------------------------------------------------------
    # 1. Timeout kills the process tree.
    # -----------------------------------------------------------------------------------------
    foreach ($a in $adapters) {
        $pidFile = Join-Path $scratchRoot ("{0}.pid" -f $a.Name)
        $fake = New-AdapterFake -Name ("sleep-{0}" -f $a.Name.ToLowerInvariant()) -Version $a.Version -PidFile $pidFile -SleepSec 60
        $invokeArgs = @{ Message = 'timeout probe'; TimeoutSec = 4; $a.ExeParam = $fake }
        $msg = ''
        try { $null = & (Join-Path $scriptsDir $a.Script) @invokeArgs } catch { $msg = [string]$_.Exception.Message }
        Assert-True ($msg -match 'exceeded 4s and was terminated') ("{0}: reports the timeout ({1})" -f $a.Name, $msg)

        if (-not (Test-Path -LiteralPath $pidFile)) {
            Assert-True $false ("{0}: fake CLI recorded its PID before the timeout (inconclusive)" -f $a.Name)
            continue
        }
        $fakePid = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
        $recordedPids.Add($fakePid)
        Assert-True (Test-ProcessGone -ProcessId $fakePid) ("{0}: fake CLI process {1} no longer exists after the timeout" -f $a.Name, $fakePid)
    }

    # -----------------------------------------------------------------------------------------
    # 2. A run leaves nothing in the temp folder.
    # -----------------------------------------------------------------------------------------
    $agyScratch = Join-Path $scratchRoot 'agy-workspace'
    $tempRuns = @($adapters) + @(
        [pscustomobject]@{ Name = 'Antigravity'; Script = 'Invoke-Antigravity.ps1'; ExeParam = 'AntigravityExe'; Version = 'agy 1.1.19'
            Extra = @{ Model = 'gemini-3.6-flash-high'; Mode = 'plan'; ScratchPath = $agyScratch }
            Response = '{"status":"SUCCESS","response":"FAKE_OK"}' }
    )
    foreach ($a in $tempRuns) {
        $fake = New-AdapterFake -Name ("ok-{0}" -f $a.Name.ToLowerInvariant()) -Version $a.Version -Response $a.Response
        $tempDir = Join-Path $scratchRoot ("temp-{0}" -f $a.Name)
        [void][System.IO.Directory]::CreateDirectory($tempDir)
        if ($a.Name -eq 'Antigravity') {
            if (Test-Path -LiteralPath $agyScratch) { Remove-Item -LiteralPath $agyScratch -Recurse -Force }
            [void][System.IO.Directory]::CreateDirectory($agyScratch)
        }
        $invokeArgs = @{ Message = 'temp probe'; TimeoutSec = 60; $a.ExeParam = $fake } + $a.Extra

        $saved = @{ TEMP = $env:TEMP; TMP = $env:TMP; TMPDIR = $env:TMPDIR }
        $output = $null
        $msg = ''
        try {
            $env:TEMP = $tempDir; $env:TMP = $tempDir; $env:TMPDIR = $tempDir
            $output = & (Join-Path $scriptsDir $a.Script) @invokeArgs
        } catch {
            $msg = [string]$_.Exception.Message
        } finally {
            $env:TEMP = $saved.TEMP; $env:TMP = $saved.TMP; $env:TMPDIR = $saved.TMPDIR
        }
        Assert-True (([string]($output | Select-Object -Last 1)) -eq 'FAKE_OK') ("{0}: run returns the fake response ({1})" -f $a.Name, $msg)

        $left = @(Get-ChildItem -LiteralPath $tempDir -Force -Recurse | ForEach-Object { $_.Name })
        Assert-True ($left.Count -eq 0) ("{0}: temp folder is empty after the run (left: {1})" -f $a.Name, ($left -join ', '))
    }
}
finally {
    foreach ($id in $recordedPids) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 200
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-DelegateAdapterProcessCleanupSelfTest.ps1" }
Write-Host 'OK: Test-DelegateAdapterProcessCleanupSelfTest.ps1' -ForegroundColor Cyan
