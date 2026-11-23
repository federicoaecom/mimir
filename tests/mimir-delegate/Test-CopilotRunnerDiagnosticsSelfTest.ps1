#requires -Version 7.4
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')
$adapter = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts/Invoke-Copilot.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('copilot diagnostics ' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
try {
    $help = '--prompt --output-format --stream --no-custom-instructions --disable-builtin-mcps --available-tools --allow-all-tools --model'
    $fake = New-FakeCli -Directory $root -Name 'fake-copilot' -ProbeOutput @{ '--version' = '1.0.78'; '--help' = $help } -PwshBody @'
if ($args[0] -ne '-p' -or $args[1] -ne 'prompt with spaces') { exit 19 }
'{"type":"assistant.message","data":{"content":"synthetic response"}}'
'@
    function Invoke-TestAdapter([string]$exe) {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = 'pwsh'
        $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($arg in @('-NoProfile', '-NonInteractive', '-File', $adapter, '-CopilotExe', $exe, '-Message', 'prompt with spaces', '-TimeoutSec', '30')) { $info.ArgumentList.Add($arg) }
        $info.Environment['TMPDIR'] = $root
        $info.Environment['TEMP'] = $root
        $info.Environment['TMP'] = $root
        $process = [Diagnostics.Process]::Start($info)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            return @{ Exit = $process.ExitCode; Out = $stdout.Result; Err = $stderr.Result }
        } finally { $process.Dispose() }
    }
    $success = Invoke-TestAdapter $fake
    if ($success.Exit -ne 0 -or $success.Out.TrimEnd("`r", "`n") -cne 'synthetic response' -or $success.Err -ne '') {
        throw "Spaced temp/argv regression: exit=$($success.Exit), stdout=$($success.Out), stderr=$($success.Err)"
    }

    # POSIX only: pass both probes, then replace the interpreter with a nonexistent one.
    # This makes the runner itself report a native launch failure, not fake CLI stderr.
    if (-not $IsWindows) {
        $broken = New-FakeCli -Directory $root -Name 'broken-copilot' -PwshBody @'
if ($args[0] -eq '--version') { '1.0.78'; exit 0 }
if ($args[0] -eq '--help') {
    '#!/nonexistent-mimir-test-interpreter' | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'broken-copilot') -Encoding utf8
    '--prompt --output-format --stream --no-custom-instructions --disable-builtin-mcps --available-tools --allow-all-tools --model'
    exit 0
}
exit 99
'@
        $failure = Invoke-TestAdapter $broken
        if ($failure.Exit -ne 1 -or $failure.Out -ne '' -or $failure.Err -notmatch 'An error occurred trying to start process' -or $failure.Err -notmatch [regex]::Escape($broken) -or $failure.Err -notmatch 'BLOCK: Copilot CLI exited with code 1 without a response\.') {
            throw "Runner diagnostic regression: exit=$($failure.Exit), stdout=$($failure.Out), stderr=$($failure.Err)"
        }
    } else {
        Write-Output 'SKIP: POSIX missing-interpreter runner diagnostic (Windows); spaced temp/argv case ran.'
    }
    Write-Output 'OK: Test-CopilotRunnerDiagnosticsSelfTest.ps1'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
