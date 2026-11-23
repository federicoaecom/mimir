#requires -Version 7.4
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')
$adapter = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts/Invoke-Gemini.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('gemini diagnostics ' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
try {
    $help = '--prompt --approval-mode --output-format --model'
    $fake = New-FakeCli -Directory $root -Name 'fake-gemini' -ProbeOutput @{ '--version' = '0.35.3'; '--help' = $help } -PwshBody @'
$expected = @('-p', 'prompt with spaces', '--approval-mode', 'plan', '--output-format', 'json', '--model', 'fake model')
if (($args | ConvertTo-Json -Compress) -cne ($expected | ConvertTo-Json -Compress)) { exit 19 }
if ([Console]::In.ReadToEnd() -ne '') { exit 20 }
if ((Get-Location).Path -cne $env:TEST_GEMINI_CWD) { exit 21 }
'{"response":"synthetic response"}'
'@
    function Invoke-TestAdapter([string]$exe) {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = 'pwsh'
        $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        foreach ($arg in @('-NoProfile', '-NonInteractive', '-File', $adapter, '-GeminiExe', $exe, '-Message', 'prompt with spaces', '-Model', 'fake model', '-Cd', $root, '-TimeoutSec', '30')) { $info.ArgumentList.Add($arg) }
        $info.Environment['TMPDIR'] = $root
        $info.Environment['TEMP'] = $root
        $info.Environment['TMP'] = $root
        $info.Environment['TEST_GEMINI_CWD'] = $root
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

    # POSIX: probes pass before the runner encounters a missing interpreter.
    if (-not $IsWindows) {
        $broken = New-FakeCli -Directory $root -Name 'broken-gemini' -PwshBody @'
if ($args[0] -eq '--version') { '0.35.3'; exit 0 }
if ($args[0] -eq '--help') {
    '#!/nonexistent-mimir-test-interpreter' | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'broken-gemini') -Encoding utf8
    '--prompt --approval-mode --output-format --model'
    exit 0
}
exit 99
'@
        $failure = Invoke-TestAdapter $broken
        if ($failure.Exit -ne 1 -or $failure.Out -ne '' -or $failure.Err -notmatch 'An error occurred trying to start process' -or $failure.Err -notmatch [regex]::Escape($broken) -or $failure.Err -notmatch 'BLOCK: Gemini CLI exited with code 1 without a response\.') {
            throw "Runner diagnostic regression: exit=$($failure.Exit), stdout=$($failure.Out), stderr=$($failure.Err)"
        }
    } else {
        Write-Output 'SKIP: POSIX missing-interpreter runner diagnostic (Windows); spaced temp/argv case ran.'
    }
    Write-Output 'OK: Test-GeminiRunnerDiagnosticsSelfTest.ps1'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
