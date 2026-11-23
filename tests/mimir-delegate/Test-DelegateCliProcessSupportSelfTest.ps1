#requires -Version 7.4
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../../skills/mimir-delegate/scripts/DelegateCliProcessSupport.ps1')

$work = Join-Path ([IO.Path]::GetTempPath()) ('mimir-process-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$fixture = Join-Path $work 'fake.ps1'
$pidFile = Join-Path $work 'descendant.pid'
$pwsh = (Get-Process -Id $PID).Path
$fake = @'
param($Mode, $Value, $Executable, $PidFile)
# Match the helper's UTF-8 decoding on both redirected native output streams.
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
switch ($Mode) {
    'normal' {
        $inputText = [Console]::In.ReadToEnd()
        [Console]::Out.Write("out:$Value|eof:$($inputText.Length)")
        [Console]::Error.Write(('err:' + [char]0x00E9 + [char]0x6F22))
    }
    'nonzero' { [Console]::Out.Write('nonzero'); [Console]::Error.Write('failure'); exit 23 }
    'cwd' { [Console]::Out.Write([Environment]::CurrentDirectory) }
    'descendant' { [IO.File]::WriteAllText($PidFile, [string]$PID); Start-Sleep -Seconds 60 }
    { $_ -in @('parent', 'parent-exit') } {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $Executable
        $info.UseShellExecute = $false
        foreach ($arg in @('-NoProfile', '-NonInteractive', '-File', $PSCommandPath, 'descendant', 'x', $Executable, $PidFile)) { $info.ArgumentList.Add($arg) }
        $child = [Diagnostics.Process]::Start($info)
        $child.Dispose()
        while (-not [IO.File]::Exists($PidFile)) { Start-Sleep -Milliseconds 20 }
        [Console]::Out.Write('started')
        if ($Mode -eq 'parent') { Start-Sleep -Seconds 60 }
    }
}
'@
[IO.File]::WriteAllText($fixture, $fake, [Text.UTF8Encoding]::new($false))
$fail = 0
function Assert-Equal($Label, $Got, $Expected) {
    if ($Got -ceq $Expected) { Write-Host "PASS $Label" }
    else { $script:fail++; Write-Host "FAIL $Label : got [$Got], expected [$Expected]" }
}
function Run-Fake($Mode, $Value = 'x', $Seconds = 10) {
    Invoke-DelegateCliProcess -Executable $pwsh -Arguments @('-NoProfile', '-NonInteractive', '-File', $fixture, $Mode, $Value, $pwsh, $pidFile) -TimeoutSeconds $Seconds
}
try {
    $argument = 'space ' + [char]0x00E9 + ' "quoted"'
    $r = Run-Fake 'normal' $argument
    Assert-Equal 'success state' $r.State 'Exited'
    Assert-Equal 'success exit' $r.ExitCode 0
    Assert-Equal 'success reason' $r.Reason ''
    Assert-Equal 'stdin EOF, argv, UTF-8 stdout' $r.Stdout "out:$argument|eof:0"
    Assert-Equal 'separate UTF-8 stderr' $r.Stderr ('err:' + [char]0x00E9 + [char]0x6F22)
    $r = Invoke-DelegateCliProcess -Executable $pwsh -Arguments @('-NoProfile', '-NonInteractive', '-File', $fixture, 'cwd') -WorkingDirectory $work
    Assert-Equal 'explicit working directory' $r.Stdout $work
    $r = Run-Fake 'nonzero'
    Assert-Equal 'nonzero state' $r.State 'Exited'
    Assert-Equal 'nonzero exit' $r.ExitCode 23
    Assert-Equal 'nonzero stdout' $r.Stdout 'nonzero'
    Assert-Equal 'nonzero stderr' $r.Stderr 'failure'
    $r = Invoke-DelegateCliProcess -Executable (Join-Path $work 'missing-executable') -Arguments @() -TimeoutSeconds 2
    Assert-Equal 'startup state' $r.State 'StartFailed'
    Assert-Equal 'startup exit' ($null -eq $r.ExitCode) $true
    Assert-Equal 'startup reason' ([string]::IsNullOrWhiteSpace($r.Reason)) $false
    Assert-Equal 'startup stdout' $r.Stdout ''
    Assert-Equal 'startup stderr' $r.Stderr ''
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $r = Run-Fake 'parent' 'x' 3
    $clock.Stop()
    Assert-Equal 'timeout state' $r.State 'TimedOut'
    Assert-Equal 'timeout exit' ($null -eq $r.ExitCode) $true
    Assert-Equal 'timeout prompt' ($clock.Elapsed.TotalSeconds -lt 10) $true
    Assert-Equal 'timeout fixture started' ([IO.File]::Exists($pidFile)) $true
    if ([IO.File]::Exists($pidFile)) {
        $childId = [int][IO.File]::ReadAllText($pidFile)
        $gone = $false
        for ($i = 0; $i -lt 50; $i++) {
            if (-not (Get-Process -Id $childId -ErrorAction SilentlyContinue)) { $gone = $true; break }
            Start-Sleep -Milliseconds 100
        }
        Assert-Equal 'owned descendant terminated' $gone $true
    }
    [IO.File]::Delete($pidFile)
    $clock.Restart()
    $r = Run-Fake 'parent-exit' 'x' 3
    $clock.Stop()
    Assert-Equal 'exited root with inherited streams times out' $r.State 'TimedOut'
    Assert-Equal 'inherited streams remain bounded' ($clock.Elapsed.TotalSeconds -lt 10) $true
    Assert-Equal 'orphan fixture started' ([IO.File]::Exists($pidFile)) $true
    if ($fail) { throw "$fail assertions failed" }
    Write-Host 'OK: Test-DelegateCliProcessSupportSelfTest.ps1'
} finally {
    if ([IO.File]::Exists($pidFile)) {
        $childId = [int][IO.File]::ReadAllText($pidFile)
        $child = Get-Process -Id $childId -ErrorAction SilentlyContinue
        if ($child) { $child.Kill($true); $child.Dispose() }
    }
    [IO.Directory]::Delete($work, $true)
}
