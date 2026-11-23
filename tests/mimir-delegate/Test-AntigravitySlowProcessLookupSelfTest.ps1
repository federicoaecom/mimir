#requires -Version 7.4
<#
.SYNOPSIS
    Self-test: a slow descendant-process lookup must not turn a finished Antigravity run into a timeout.

.DESCRIPTION
    Invoke-Antigravity.ps1 polls for the runner's descendant processes while it waits. On Windows that
    lookup once went through WMI (Get-CimInstance Win32_Process), which has no timeout and was seen to
    stall for minutes under load; a lookup that returned after the deadline made a run whose child had
    already exited report "reason=timeout". This test makes every lookup slow with the test-only
    variable MIMIR_TEST_ANTIGRAVITY_LOOKUP_DELAY_MS and checks that:
      - a fake agy that answers at once still returns its response with a short -TimeoutSec;
      - the adapter's own descendant lookup (Get-Process parents, no WMI) finds a grandchild process
        on this OS.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tests/fixtures/FakeCliSupport.ps1')
$invokeScript = Join-Path $repoRoot 'skills/mimir-delegate/scripts/Invoke-Antigravity.ps1'

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Host "PASS  $Message" } else { Write-Host "FAIL  $Message"; $failures.Add($Message) }
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agy-slow-lookup-' + [Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempDir)
$previousDelay = $env:MIMIR_TEST_ANTIGRAVITY_LOOKUP_DELAY_MS
try {
    $fake = New-FakeCli -Directory $tempDir -Name 'fake-agy' -PwshBody @'
if ($args -contains '--version') { 'agy 1.1.19'; exit 0 }
if ($args -contains '--help') { "Usage of agy: -p Run a prompt --mode Set agent mode --output-format json"; exit 0 }
@{ status = 'SUCCESS'; response = 'FAKE_FAST_RESPONSE' } | ConvertTo-Json -Compress
exit 0
'@

    # Each lookup takes longer than the whole timeout: the old loop checked the deadline right after a
    # lookup without looking at HasExited again, so the finished run was reported as a timeout.
    # 10 s leaves the runner and the fake (nested pwsh starts) ample time to exit on a loaded machine.
    $env:MIMIR_TEST_ANTIGRAVITY_LOOKUP_DELAY_MS = '10000'
    $output = $null
    $errorText = ''
    try {
        $output = & $invokeScript -AntigravityExe $fake -Message 'slow lookup probe' -Model 'gemini-3.6-flash-high' -Mode plan -TimeoutSec 5
    } catch {
        $errorText = $_.Exception.Message
    }
    Assert-True ($output -eq 'FAKE_FAST_RESPONSE') "a finished run is not reported as a timeout when the process lookup is slow (got '$output'; error '$errorText')"

    $env:MIMIR_TEST_ANTIGRAVITY_LOOKUP_DELAY_MS = $previousDelay

    # The lookup itself must still find descendants on this OS: load the adapter's own
    # Get-DescendantProcessIds and point it at a pwsh that starts a sleeping grandchild.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($invokeScript, [ref]$null, [ref]$null)
    $lookup = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-DescendantProcessIds' }, $true) | Select-Object -First 1
    Assert-True ($null -ne $lookup) 'the adapter defines Get-DescendantProcessIds'
    if ($null -ne $lookup) {
        . ([scriptblock]::Create($lookup.Extent.Text))
        $pidFile = Join-Path $tempDir 'grandchild.pid'
        $outerCommand = "`$c = Start-Process -FilePath pwsh -ArgumentList '-NoProfile','-NonInteractive','-Command','Start-Sleep 30' -PassThru; Set-Content -LiteralPath '$pidFile' -Value `$c.Id; Start-Sleep 30"
        $outer = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', $outerCommand) -PassThru
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while (-not (Test-Path -LiteralPath $pidFile) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
            $grandchildId = if (Test-Path -LiteralPath $pidFile) { [int](Get-Content -LiteralPath $pidFile -Raw).Trim() } else { -1 }
            $found = @(Get-DescendantProcessIds -RootProcessId $outer.Id)
            Assert-True ($grandchildId -gt 0 -and $found -contains $grandchildId) "the lookup finds a grandchild process (grandchild $grandchildId; found: $($found -join ', '))"
        }
        finally {
            try { $outer.Kill($true) } catch { }
        }
    }
}
finally {
    $env:MIMIR_TEST_ANTIGRAVITY_LOOKUP_DELAY_MS = $previousDelay
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) { throw "BLOCK: $($failures.Count) case(s) failed in Test-AntigravitySlowProcessLookupSelfTest.ps1" }
Write-Host 'OK: Test-AntigravitySlowProcessLookupSelfTest.ps1'
