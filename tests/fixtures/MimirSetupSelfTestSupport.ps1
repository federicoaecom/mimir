#requires -Version 7.4
<#
.SYNOPSIS
  Support (dot-source) for the setup and index-gate self-tests: invokes a target
  script in a child pwsh while isolating its `exit`.

.DESCRIPTION
  The setup audit and index gate engines end with `exit <code>`, so the self-tests run
  them in a child pwsh (so the engine's `exit` does not bring down the self-test) and
  read back the exit code, stdout, and the parsed JSON.

  Not a self-test itself; emits no sentinel. Dot-sourced by the Test-*SelfTest.ps1 files.
#>

Set-StrictMode -Version Latest

function Invoke-MimirSelfTestScript {
  <#
    Runs a target script in a child pwsh (isolates the `exit`), capturing stdout and exit.
    Returns { exit, stdout, json } (json = parsed stdout, or $null if not JSON).
    Args are passed as a positional/named list already assembled by the caller.
  #>
  param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [string[]]$ScriptArgs = @()
  )
  $stdout = & pwsh -NoProfile -File $ScriptPath @ScriptArgs 2>$null | Out-String
  $code = $LASTEXITCODE
  $json = $null
  if ($stdout -and $stdout.Trim()) {
    try { $json = $stdout | ConvertFrom-Json } catch { $json = $null }
  }
  return [pscustomobject]@{ exit = $code; stdout = $stdout; json = $json }
}
