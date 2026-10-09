#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of Codex's durable capture (TempDir, KeepDays, sentinels, kb-sensitive).
.DESCRIPTION
    Deterministic with a fake-exe. Never touches the user's real %TEMP%\codex-jobs.
    Sentinel: OK: Test-CodexDurableCaptureSelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptsDir = Join-Path $repoRoot 'skills/mimir-delegate/scripts'
$invoke = Join-Path $scriptsDir 'Invoke-Codex.ps1'
. (Join-Path $scriptsDir 'CodexCliSupport.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('codex-durable-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$jobs = Join-Path $tmp 'jobs'
[IO.Directory]::CreateDirectory($jobs) | Out-Null

$prevDisable = $env:MIMIR_CODEX_DISABLE_KEEPDAYS
$env:MIMIR_CODEX_DISABLE_KEEPDAYS = '1'
$prevJobsDir = $env:MIMIR_CODEX_JOBS_DIR

try {
    # --- fake readers ---
    $okCmd = New-FakeCli -Directory $tmp -Name 'fake-ok' -PwshBody @'
$o = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '-o') { $o = $args[$i + 1]; break } }
$s = [Console]::In.ReadToEnd()
# Off Windows, pwsh's Start-Process -RedirectStandardInput copies the file line by line and adds a
# final newline (observed on pwsh 7.4.2, 7.4.6 and 7.5.0); count the prompt without that transport byte.
if (-not $IsWindows -and $s.EndsWith("`n")) { $s = $s.Substring(0, $s.Length - 1) }
if ($o) { Set-Content -LiteralPath $o -Value ('OPINION=' + $s.Length) -Encoding utf8 -NoNewline }
exit 0
'@

    $emptyCmd = New-FakeCli -Directory $tmp -Name 'fake-empty' -PwshBody @'
$o = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '-o') { $o = $args[$i + 1]; break } }
[void][Console]::In.ReadToEnd()
if ($o) { Set-Content -LiteralPath $o -Value '' -Encoding utf8 -NoNewline }
exit 0
'@

    $timeoutCmd = New-FakeCli -Directory $tmp -Name 'fake-timeout' -PwshBody @'
$o = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '-o') { $o = $args[$i + 1]; break } }
[void][Console]::In.ReadToEnd()
if ($o) { Set-Content -LiteralPath $o -Value 'PARTIAL-BYTES' -Encoding utf8 -NoNewline }
exit 0
'@

    $timeoutEmptyCmd = New-FakeCli -Directory $tmp -Name 'fake-timeout-empty' -PwshBody @'
[void][Console]::In.ReadToEnd()
exit 0
'@

    $prompt = Join-Path $tmp 'prompt.txt'
    Set-Content -LiteralPath $prompt -Value 'hello-durable' -Encoding utf8 -NoNewline

    # ===== Resolve-CodexJobTempDir unit =====
    $resolvedTd = Resolve-CodexJobTempDir -Override $jobs
    Assert-True ([IO.Path]::IsPathRooted($resolvedTd)) 'TempDir: absolute'
    Assert-True ($resolvedTd -eq [IO.Path]::GetFullPath($jobs)) 'TempDir: Bound'
    Write-Host 'PASS Resolve-CodexJobTempDir' -ForegroundColor Green

    # ===== 1 in-process public success =====
    $j1 = Join-Path $jobs 't1'
    $ans = [string](& $invoke -CodexExe $okCmd -MessagePath $prompt -TempDir $j1 -TimeoutSec 60 -RetentionMode public)
    Assert-True ($ans -eq 'OPINION=13') "1: stdout is response only; got '$ans'"
    $files1 = @(Get-ChildItem -LiteralPath $j1 -File)
    Assert-True ($null -eq (@($files1 | Where-Object { $_.Name -like '*.invoke-*' }) | Select-Object -First 1)) '1: invoke-* deleted'
    Assert-True (@($files1 | Where-Object { $_.Name -like '*.lastmsg.txt' }).Count -eq 1) '1: lastmsg remains'
    $req1File = @($files1 | Where-Object { $_.Name -like '*.request.json' })[0]
    $req1 = Get-Content -LiteralPath $req1File.FullName -Raw | ConvertFrom-Json
    Assert-True ($req1.captureOutcome -eq 'success') '1: captureOutcome=success'
    Write-Host 'PASS 1 public success' -ForegroundColor Green
    # 12k: same success path — finally does not throw; response via successText
    Assert-True ($ans.Length -gt 0) '12k: text returned without throwing'
    Write-Host 'PASS 12k success without throw' -ForegroundColor Green

    # ===== 1b out-of-process stderr =====
    $j1b = Join-Path $jobs 't1b'
    [IO.Directory]::CreateDirectory($j1b) | Out-Null
    $stdout1b = Join-Path $tmp '1b-out.txt'
    $stderr1b = Join-Path $tmp '1b-err.txt'
    $p1b = Start-Process -FilePath pwsh -ArgumentList @(
        '-NoProfile', '-File', $invoke,
        '-CodexExe', $okCmd, '-MessagePath', $prompt, '-TempDir', $j1b,
        '-TimeoutSec', '60', '-RetentionMode', 'public'
    ) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout1b -RedirectStandardError $stderr1b
    Assert-True ($p1b.ExitCode -eq 0) "1b: exit 0 got $($p1b.ExitCode)"
    $out1b = (Get-Content -LiteralPath $stdout1b -Raw).Trim()
    $err1b = Get-Content -LiteralPath $stderr1b -Raw -ErrorAction SilentlyContinue
    Assert-True ($out1b -eq 'OPINION=13') "1b: stdout is response only; got '$out1b'"
    Assert-True ($err1b -match 'MIMIR_CODEX_LASTMSG=') '1b: LASTMSG sentinel in stderr'
    Assert-True ($err1b -match 'MIMIR_CODEX_REQUEST=') '1b: REQUEST sentinel in stderr'
    Assert-True ($out1b -notmatch 'MIMIR_CODEX_') '1b: stdout without a sentinel'
    Write-Host 'PASS 1b out-of-process' -ForegroundColor Green

    # ===== 2a timeout with bytes, RetentionMode=public =====
    $j2a = Join-Path $jobs 't2a'
    $threw2a = $false; $msg2a = $null
    $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT = '1'
    try {
        & $invoke -CodexExe $timeoutCmd -MessagePath $prompt -TempDir $j2a -TimeoutSec 2 -RetentionMode public | Out-Null
    } catch {
        $threw2a = $true
        $msg2a = [string]$_.Exception.Message
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_FORCE_TIMEOUT -ErrorAction SilentlyContinue
    Assert-True $threw2a '2a: should throw'
    Assert-True ($msg2a -match 'exceeded' -and $msg2a -match 'was terminated') '2a: exceeded+was terminated'
    Assert-True ($msg2a -match 'MIMIR_CODEX_LASTMSG=') '2a: sentinel'
    $req2aPath = @(Get-ChildItem -LiteralPath $j2a -Filter '*.request.json')[0].FullName
    $req2a = Get-Content -LiteralPath $req2aPath -Raw | ConvertFrom-Json
    Assert-True ($req2a.captureOutcome -eq 'timeout') '2a: captureOutcome=timeout on disk'
    Write-Host 'PASS 2a timeout with bytes' -ForegroundColor Green

    # ===== 2b timeout without bytes =====
    $j2b = Join-Path $jobs 't2b'
    $threw2b = $false; $msg2b = $null
    $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT = '1'
    try {
        & $invoke -CodexExe $timeoutEmptyCmd -MessagePath $prompt -TempDir $j2b -TimeoutSec 2 -RetentionMode public | Out-Null
    } catch {
        $threw2b = $true
        $msg2b = [string]$_.Exception.Message
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_FORCE_TIMEOUT -ErrorAction SilentlyContinue
    Assert-True $threw2b '2b: should throw'
    Assert-True ($msg2b -match 'exceeded' -and $msg2b -match 'was terminated') '2b: markers'
    $req2b = Get-Content -LiteralPath (@(Get-ChildItem -LiteralPath $j2b -Filter '*.request.json')[0].FullName) -Raw | ConvertFrom-Json
    Assert-True ($req2b.captureOutcome -eq 'timeout') '2b: captureOutcome=timeout'
    Write-Host 'PASS 2b timeout without bytes' -ForegroundColor Green

    # ===== 2d: REAL timeout (without FORCE_TIMEOUT) with lastmsg -> recovers the response =====
    $hangCmd = New-FakeCli -Directory $tmp -Name 'fake-hang-after-lastmsg' -PwshBody @'
$o = $null
for ($i = 0; $i -lt $args.Count; $i++) { if ($args[$i] -eq '-o') { $o = $args[$i + 1]; break } }
[void][Console]::In.ReadToEnd()
if ($o) { Set-Content -LiteralPath $o -Value 'RECOVERED-AFTER-KILL' -Encoding utf8 -NoNewline }
# Outlives the adapter's -TimeoutSec, which kills this process.
Start-Sleep -Seconds 60
exit 0
'@
    $j2d = Join-Path $jobs 'j2d-recover'
    [IO.Directory]::CreateDirectory($j2d) | Out-Null
    # The fake starts a fresh pwsh before it writes lastmsg; on a slow hosted runner that startup can
    # take seconds, so the timeout leaves room for the write and the kill still lands mid-sleep.
    $ans2d = $null; $err2d = $null
    try {
        $ans2d = [string](& $invoke -CodexExe $hangCmd -MessagePath $prompt -TempDir $j2d -TimeoutSec 10 -RetentionMode public)
    } catch {
        $err2d = [string]$_.Exception.Message
    }
    Assert-True ($null -eq $err2d) "2d: the fake did not write lastmsg before the 10s timeout; it started too slowly. Adapter error: $err2d"
    Assert-True ($ans2d -eq 'RECOVERED-AFTER-KILL') "2d: should recover lastmsg after Kill; got '$ans2d'"
    $req2d = Get-Content -LiteralPath (@(Get-ChildItem -LiteralPath $j2d -Filter '*.request.json')[0].FullName) -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($req2d.captureOutcome -eq 'success') '2d: captureOutcome=success after recovery'
    Assert-True ([bool]$req2d.recoveredAfterTimeout) '2d: recoveredAfterTimeout=true in request.json'
    Write-Host 'PASS 2d recover after timeout' -ForegroundColor Green

    # ===== 3 invalid MessagePath =====
    $j3 = Join-Path $jobs 't3'
    [IO.Directory]::CreateDirectory($j3) | Out-Null
    $before3 = @(Get-ChildItem -LiteralPath $j3 -File -ErrorAction SilentlyContinue).Count
    $threw3 = $false
    try { & $invoke -CodexExe $okCmd -MessagePath (Join-Path $tmp 'nope.txt') -TempDir $j3 -TimeoutSec 10 | Out-Null } catch { $threw3 = $true }
    Assert-True $threw3 '3: throw'
    Assert-True (@(Get-ChildItem -LiteralPath $j3 -File -ErrorAction SilentlyContinue).Count -eq $before3) '3: zero new files'
    Write-Host 'PASS 3 invalid MessagePath' -ForegroundColor Green

    # ===== 3b broken exe =====
    $j3b = Join-Path $jobs 't3b'
    [IO.Directory]::CreateDirectory($j3b) | Out-Null
    $before3b = @(Get-ChildItem -LiteralPath $j3b -File -ErrorAction SilentlyContinue).Count
    $threw3b = $false
    try { & $invoke -CodexExe (Join-Path $tmp 'missing-codex.exe') -MessagePath $prompt -TempDir $j3b -TimeoutSec 10 | Out-Null } catch { $threw3b = $true }
    Assert-True $threw3b '3b: throw'
    Assert-True (@(Get-ChildItem -LiteralPath $j3b -File -ErrorAction SilentlyContinue).Count -eq $before3b) '3b: zero files'
    Write-Host 'PASS 3b broken exe' -ForegroundColor Green

    # ===== 12i empty =====
    $j12i = Join-Path $jobs 't12i'
    $threw12i = $false; $msg12i = $null
    try { & $invoke -CodexExe $emptyCmd -MessagePath $prompt -TempDir $j12i -TimeoutSec 60 -RetentionMode public | Out-Null } catch {
        $threw12i = $true
        $msg12i = [string]$_.Exception.Message
    }
    Assert-True $threw12i '12i: throw'
    $firstLine = ($msg12i -replace "`r`n", "`n" -split "`n")[0]
    Assert-True ($firstLine -eq 'BLOCK: codex did not produce a response (output-last-message empty).') "12i: exact first line; got '$firstLine'"
    Assert-True ($msg12i -match 'MIMIR_CODEX_') '12i: sentinels'
    $req12i = Get-Content -LiteralPath (@(Get-ChildItem -LiteralPath $j12i -Filter '*.request.json')[0].FullName) -Raw | ConvertFrom-Json
    Assert-True ($req12i.captureOutcome -eq 'empty') '12i: captureOutcome=empty'
    Write-Host 'PASS 12i empty' -ForegroundColor Green

    # ===== 12m kb-sensitive timeout =====
    $j12m = Join-Path $jobs 't12m'
    $threw12m = $false; $msg12m = $null
    $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT = '1'
    try {
        & $invoke -CodexExe $timeoutCmd -MessagePath $prompt -TempDir $j12m -TimeoutSec 2 -RetentionMode 'kb-sensitive' | Out-Null
    } catch {
        $threw12m = $true
        $msg12m = [string]$_.Exception.Message
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_FORCE_TIMEOUT -ErrorAction SilentlyContinue
    Assert-True $threw12m '12m: throw'
    Assert-True ($msg12m -match 'MIMIR_CODEX_CAPTURED_TEXT_BEGIN') '12m: CAPTURED_TEXT_BEGIN'
    Assert-True ($msg12m -match 'PARTIAL-BYTES') '12m: captured text'
    Assert-True (@(Get-ChildItem -LiteralPath $j12m -Filter '*.lastmsg.txt' -ErrorAction SilentlyContinue).Count -eq 0) '12m: lastmsg absent'
    Assert-True (@(Get-ChildItem -LiteralPath $j12m -Filter '*.invoke-in.txt' -ErrorAction SilentlyContinue).Count -eq 0) '12m: invoke-in absent'
    Write-Host 'PASS 12m kb-sensitive timeout' -ForegroundColor Green

    # ===== 12n kb-sensitive success =====
    $j12n = Join-Path $jobs 't12n'
    $ans12n = [string](& $invoke -CodexExe $okCmd -MessagePath $prompt -TempDir $j12n -TimeoutSec 60 -RetentionMode 'kb-sensitive')
    Assert-True ($ans12n -eq 'OPINION=13') '12n: stdout response'
    Assert-True (@(Get-ChildItem -LiteralPath $j12n -Filter '*.lastmsg.txt' -ErrorAction SilentlyContinue).Count -eq 0) '12n: lastmsg absent'
    Assert-True (@(Get-ChildItem -LiteralPath $j12n -Filter '*.invoke-*' -ErrorAction SilentlyContinue).Count -eq 0) '12n: invoke-* absent'
    Write-Host 'PASS 12n kb-sensitive success' -ForegroundColor Green

    # ===== 12p kb-sensitive success + rewrite fail =====
    $j12p = Join-Path $jobs 't12p'
    $env:MIMIR_TEST_CODEX_INVOKE_FAIL_REWRITE = '1'
    $threw12p = $false; $msg12p = $null
    try {
        & $invoke -CodexExe $okCmd -MessagePath $prompt -TempDir $j12p -TimeoutSec 60 -RetentionMode 'kb-sensitive' | Out-Null
    } catch {
        $threw12p = $true
        $msg12p = [string]$_.Exception.Message
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_INVOKE_FAIL_REWRITE -ErrorAction SilentlyContinue
    Assert-True $threw12p '12p: throw'
    Assert-True ($msg12p -match 'failed to write request.json') '12p: BLOCK rewrite'
    Assert-True ($msg12p -notmatch 'MIMIR_CODEX_CAPTURED_TEXT_BEGIN') '12p: no lastmsg capture'
    Assert-True (@(Get-ChildItem -LiteralPath $j12p -Filter '*.lastmsg.txt').Count -eq 1) '12p: lastmsg intact'
    Assert-True (@(Get-ChildItem -LiteralPath $j12p -Filter '*.invoke-err.txt').Count -eq 1) '12p: invoke-err kept with the group'
    Assert-True (@(Get-ChildItem -LiteralPath $j12p -Filter '*.invoke-out.txt').Count -eq 0) '12p: no invoke-out file is created (stdout goes to stream.jsonl)'
    Write-Host 'PASS 12p rewrite fail on success' -ForegroundColor Green

    # ===== 12o unexpected =====
    $j12o = Join-Path $jobs 't12o'
    $env:MIMIR_TEST_CODEX_INVOKE_UNEXPECTED = '1'
    $threw12o = $false; $msg12o = $null
    try {
        & $invoke -CodexExe $okCmd -MessagePath $prompt -TempDir $j12o -TimeoutSec 60 -RetentionMode public | Out-Null
    } catch {
        $threw12o = $true
        $msg12o = [string]$_.Exception.Message
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_INVOKE_UNEXPECTED -ErrorAction SilentlyContinue
    Assert-True $threw12o '12o: throw'
    Assert-True ($msg12o -match 'BLOCK:') '12o: BLOCK'
    $req12oFiles = @(Get-ChildItem -LiteralPath $j12o -Filter '*.request.json' -ErrorAction SilentlyContinue)
    if ($req12oFiles.Count -gt 0) {
        $req12o = Get-Content -LiteralPath $req12oFiles[0].FullName -Raw | ConvertFrom-Json
        Assert-True ($req12o.captureOutcome -eq 'error') '12o: captureOutcome=error'
    }
    Write-Host 'PASS 12o unexpected' -ForegroundColor Green

    # ===== 12q exit != 0 with unclassified stdout and stderr =====
    $j12q = Join-Path $jobs 't12q'
    $errCmd = New-FakeCli -Directory $tmp -Name 'fake-exit1' -PwshBody @'
[Console]::Out.WriteLine('stdout line 1')
[Console]::Error.WriteLine('stderr line 1')
exit 1
'@
    $threw12q = $false; $msg12q = $null
    try {
        & $invoke -CodexExe $errCmd -MessagePath $prompt -TempDir $j12q -TimeoutSec 60 -RetentionMode public | Out-Null
    } catch {
        $threw12q = $true
        $msg12q = [string]$_.Exception.Message
    }
    Assert-True $threw12q '12q: throw'
    Assert-True ($msg12q -match 'BLOCK: codex exited with code 1\.') '12q: BLOCK with code 1.'
    Assert-True ($msg12q -match 'stdout:\r?\nstdout line 1') '12q: preserves stdout'
    Assert-True ($msg12q -match 'stderr:\r?\nstderr line 1') '12q: preserves stderr'
    Assert-True ($msg12q -notmatch 'without a response') '12q: does not claim no response'
    Write-Host 'PASS 12q exit 1 with stdout/stderr preserved' -ForegroundColor Green

    # ===== 12h Bound empty TempDir =====
    $j12h = Join-Path $jobs 't12h-env'
    $env:MIMIR_CODEX_JOBS_DIR = $j12h
    $ans12h = [string](& $invoke -CodexExe $okCmd -MessagePath $prompt -TempDir '' -TimeoutSec 60 -RetentionMode public)
    Remove-Item Env:\MIMIR_CODEX_JOBS_DIR -ErrorAction SilentlyContinue
    Assert-True ($ans12h -eq 'OPINION=13') '12h: success via env'
    Assert-True (Test-Path -LiteralPath $j12h) '12h: used env'
    $req12h = @(Get-ChildItem -LiteralPath $j12h -Filter '*.request.json')[0]
    Assert-True ([IO.Path]::IsPathRooted($req12h.DirectoryName)) '12h: absolute path'
    Write-Host 'PASS 12h empty TempDir -> env' -ForegroundColor Green

    # ===== KeepDays C-codex / C-shared =====
    Remove-Item Env:\MIMIR_CODEX_DISABLE_KEEPDAYS -ErrorAction SilentlyContinue
    $jk = Join-Path $jobs 'keep'
    [IO.Directory]::CreateDirectory($jk) | Out-Null
    $gOld = [guid]::NewGuid().ToString('N')
    $oldLast = Join-Path $jk "$gOld.lastmsg.txt"
    $oldStream = Join-Path $jk "$gOld.stream.jsonl"
    Set-Content -LiteralPath $oldLast -Value 'old' -Encoding utf8
    Set-Content -LiteralPath $oldStream -Value '{}' -Encoding utf8
    $oldTime = (Get-Date).AddDays(-20)
    [IO.File]::SetLastWriteTime($oldLast, $oldTime)
    [IO.File]::SetLastWriteTime($oldStream, $oldTime)

    $gShared = [guid]::NewGuid().ToString('N')
    $sharedStream = Join-Path $jk "$gShared.stream.jsonl"
    Set-Content -LiteralPath $sharedStream -Value '{}' -Encoding utf8
    [IO.File]::SetLastWriteTime($sharedStream, $oldTime)

    Invoke-CodexJobsKeepDaysCleanup -TempDir $jk -KeepDays 3
    Assert-True (-not (Test-Path -LiteralPath $oldLast)) 'KeepDays: orphaned lastmsg removed'
    Assert-True (-not (Test-Path -LiteralPath $oldStream)) 'KeepDays: stream for the same GUID removed'
    Assert-True (Test-Path -LiteralPath $sharedStream) 'KeepDays: C-shared survives'
    $env:MIMIR_CODEX_DISABLE_KEEPDAYS = '1'
    Write-Host 'PASS KeepDays C-codex/C-shared' -ForegroundColor Green

    # ===== Resolve helpers 4g mixed =====
    $jm = Join-Path $jobs 'mixed'
    [IO.Directory]::CreateDirectory($jm) | Out-Null
    $gm = [guid]::NewGuid().ToString('N')
    @{ schemaVersion = 1; source = 'start-job'; pid = 12345 } | ConvertTo-Json | Set-Content (Join-Path $jm "$gm.request.json") -Encoding utf8
    @{ processStartTimeUtc = '2026-08-30T12:00:00.000Z' } | ConvertTo-Json | Set-Content (Join-Path $jm "$gm.identity.json") -Encoding utf8
    $rm = Resolve-CodexPidAndStartTime -TempDir $jm -JobId $gm
    Assert-True ($rm.divergence -eq $false) '4g: mixed with no divergence'
    Assert-True ([int]$rm.pid -eq 12345) '4g: pid from request'
    Assert-True ($rm.processStartTimeUtc -eq '2026-08-30T12:00:00.000Z') '4g: time from identity'
    Write-Host 'PASS 4g mixed' -ForegroundColor Green

    # ===== 2c: path with 429 in the sentinels; the classifier uses the prefix (timeout, not quota) =====
    # Locks the CUTOFF ALGORITHM (prefix before MIMIR_CODEX_). The Parallel integration in the
    # dispatcher is case 5b of Test-InvokeLlmDelegatePanelDispatchSelfTest.ps1.
    $j2c = Join-Path $jobs 'ledger-with-429-in-name'
    [IO.Directory]::CreateDirectory($j2c) | Out-Null
    $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT = '1'
    $threw2c = $false; $msg2c = $null
    try {
        & $invoke -CodexExe $timeoutCmd -MessagePath $prompt -TempDir $j2c -TimeoutSec 2 -RetentionMode public | Out-Null
    } catch {
        $threw2c = $true
        $msg2c = [string]$_.Exception.Message
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_FORCE_TIMEOUT -ErrorAction SilentlyContinue
    Assert-True $threw2c '2c: throw'
    Assert-True ($msg2c -match '429') '2c: errorPath/message contains 429 from the path'
    $errNorm2c = $msg2c -replace "`r`n", "`n"
    $cut2c = -1
    if ($errNorm2c.StartsWith('MIMIR_CODEX_')) { $cut2c = 0 }
    else {
        $idx2c = $errNorm2c.IndexOf("`nMIMIR_CODEX_")
        if ($idx2c -ge 0) { $cut2c = $idx2c }
    }
    $classifiedMsg2c = if ($cut2c -eq 0) { '' } elseif ($cut2c -gt 0) { $errNorm2c.Substring(0, $cut2c) } else { $errNorm2c }
    Assert-True ($classifiedMsg2c -match 'exceeded' -and $classifiedMsg2c -match 'was terminated') '2c: prefix is still timeout'
    Assert-True ($classifiedMsg2c -notmatch '429') '2c: classified message has no path/429'
    $quotaPat = '(?i)(^|[^0-9])(402|429)([^0-9]|$)|quota|rate limit'
    Assert-True (-not ($classifiedMsg2c -match 'BLOCK:' -and $classifiedMsg2c -match $quotaPat)) '2c: does not classify as quota'
    Write-Host 'PASS 2c strip 429 in path -> timeout' -ForegroundColor Green

    # ===== 12g: timeout + rewrite failed; exceeded/was terminated survive =====
    $j12g = Join-Path $jobs 't12g'
    $env:MIMIR_TEST_CODEX_FORCE_TIMEOUT = '1'
    $env:MIMIR_TEST_CODEX_INVOKE_FAIL_REWRITE = '1'
    $threw12g = $false; $msg12g = $null
    try {
        & $invoke -CodexExe $timeoutCmd -MessagePath $prompt -TempDir $j12g -TimeoutSec 2 -RetentionMode public | Out-Null
    } catch {
        $threw12g = $true
        $msg12g = [string]$_.Exception.Message
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_FORCE_TIMEOUT -ErrorAction SilentlyContinue
    Remove-Item Env:\MIMIR_TEST_CODEX_INVOKE_FAIL_REWRITE -ErrorAction SilentlyContinue
    Assert-True $threw12g '12g: throw'
    Assert-True ($msg12g -match 'exceeded' -and $msg12g -match 'was terminated') '12g: timeout preserved after rewrite fail'
    Assert-True ($msg12g -match 'failed to write request.json') '12g: BLOCK rewrite appended'
    Write-Host 'PASS 12g timeout+rewrite fail' -ForegroundColor Green

    # ===== 12e: fallback RoundId uses the -fb-* suffix (glob recovery) =====
    $dispSrc = Get-Content -LiteralPath (Join-Path $scriptsDir 'Invoke-LlmDelegatePanelDispatch.ps1') -Raw -Encoding utf8
    Assert-True ($dispSrc -match 'RoundId\s*=\s*"\$RoundId-fb-\$\(\$rec\.index\)-\$fbIdx"') '12e: RoundId-fb-i-j in the dispatcher'
    Write-Host 'PASS 12e fallback path -fb-*' -ForegroundColor Green

    # ===== 12f: backend-parity marker isolates the unit; the next bullet is another one =====
    $probeMd = Join-Path $tmp 'parity-probe.md'
    @(
        '<!-- backend-parity: ignore -->',
        'Paragrafo novo cita Codex e Claude Code nesta unidade isolada.',
        '',
        '- Bullet seguinte cita Codex e Gemini e e outra unidade.'
    ) -join "`n" | Set-Content -LiteralPath $probeMd -Encoding utf8 -NoNewline
    # Minimal parser aligned with the check: a blank line closes a unit; a bullet starts a new one.
    $probeLines = [System.IO.File]::ReadAllLines($probeMd)
    $units = [System.Collections.Generic.List[object]]::new()
    $buf = [System.Collections.Generic.List[string]]::new()
    $startU = 1
    for ($pi = 0; $pi -lt $probeLines.Count; $pi++) {
        $pl = $probeLines[$pi]
        if ([string]::IsNullOrWhiteSpace($pl)) {
            if ($buf.Count -gt 0) {
                $units.Add([pscustomobject]@{ RawLines = @($buf) })
                $buf.Clear()
            }
            continue
        }
        if ($pl -match '^\s*[-*+]\s+') {
            if ($buf.Count -gt 0) {
                $units.Add([pscustomobject]@{ RawLines = @($buf) })
                $buf.Clear()
            }
        }
        if ($buf.Count -eq 0) { $startU = $pi + 1 }
        $buf.Add($pl)
    }
    if ($buf.Count -gt 0) { $units.Add([pscustomobject]@{ RawLines = @($buf) }) }
    Assert-True ($units.Count -ge 2) "12f: expected >=2 units, got $($units.Count)"
    $u0 = ($units[0].RawLines -join "`n")
    $u1 = ($units[1].RawLines -join "`n")
    Assert-True ($u0 -match 'backend-parity:\s*ignore') '12f: marker on the 1st unit'
    Assert-True ($u1 -notmatch 'backend-parity:\s*ignore') '12f: next bullet has no marker'
    $tr14 = Select-String -Path (Join-Path $repoRoot 'docs/process/14-reinforced-pre-push-review.md') `
        -Pattern '^### Codex transport vs native anchor$' |
        Select-Object -First 1
    Assert-True ($null -ne $tr14) '12f: English-only Codex transport heading in 14'
    $lineBefore14 = (Get-Content -LiteralPath $tr14.Path -Encoding utf8)[$tr14.LineNumber - 2]
    Assert-True ($lineBefore14 -match 'backend-parity:\s*ignore') '12f: marker on the paragraph 14 unit'
    Write-Host 'PASS 12f parity marker' -ForegroundColor Green

    Write-Output 'OK: Test-CodexDurableCaptureSelfTest.ps1'
}
finally {
    if ($null -eq $prevDisable) {
        Remove-Item Env:\MIMIR_CODEX_DISABLE_KEEPDAYS -ErrorAction SilentlyContinue
    } else {
        $env:MIMIR_CODEX_DISABLE_KEEPDAYS = $prevDisable
    }
    if ($null -eq $prevJobsDir) {
        Remove-Item Env:\MIMIR_CODEX_JOBS_DIR -ErrorAction SilentlyContinue
    } else {
        $env:MIMIR_CODEX_JOBS_DIR = $prevJobsDir
    }
    Remove-Item Env:\MIMIR_TEST_CODEX_INVOKE_FAIL_REWRITE -ErrorAction SilentlyContinue
    Remove-Item Env:\MIMIR_TEST_CODEX_INVOKE_UNEXPECTED -ErrorAction SilentlyContinue
    Remove-Item Env:\MIMIR_TEST_CODEX_FORCE_TIMEOUT -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tmp) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
