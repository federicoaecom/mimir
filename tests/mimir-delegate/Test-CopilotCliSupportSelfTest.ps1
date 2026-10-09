#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the pure functions in CopilotCliSupport.ps1.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'CopilotCliSupport.ps1')

$fail = 0
function Assert-Equal {
    param([string]$Label, $Got, $Expected)
    if ([string]$Got -eq [string]$Expected) {
        Write-Host ("PASS  {0}" -f $Label) -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host ("FAIL  {0} -> '{1}' (expected '{2}')" -f $Label, $Got, $Expected) -ForegroundColor Red
    }
}

Assert-Equal 'parse version' (ConvertFrom-CopilotVersionText 'copilot 1.0.12') ([version]'1.0.12')
Assert-Equal 'parse invalid -> null' (ConvertFrom-CopilotVersionText 'no version') $null

$helpOk = @'
--prompt
--output-format
--stream
--no-custom-instructions
--disable-builtin-mcps
--available-tools
--allow-all-tools
--model
'@
Assert-Equal 'help with required flags' (Test-CopilotHelpSupportsContract $helpOk) $true
Assert-Equal 'help incomplete' (Test-CopilotHelpSupportsContract '--prompt --model') $false

$lines = @(
    '{"type":"assistant.message","data":{"content":"primeira"}}',
    '{"type":"tool.call","data":{}}',
    'line-not-json',
    '{"type":"assistant.message","data":{"content":"final"}}',
    '{"type":"result","exitCode":0}'
)
Assert-Equal 'jsonl last assistant.message wins' (Get-CopilotJsonlFinalText -Lines $lines) 'final'
Assert-Equal 'jsonl exitCode from result event' (Get-CopilotJsonlExitCode -Lines $lines) 0

$linesSemResposta = @('{"type":"tool.call","data":{}}', 'ruido')
Assert-Equal 'jsonl without assistant.message -> empty' (Get-CopilotJsonlFinalText -Lines $linesSemResposta) ''
Assert-Equal 'jsonl without result -> null' (Get-CopilotJsonlExitCode -Lines $linesSemResposta) $null

$linesErroExit = @('{"type":"result","exitCode":2}')
Assert-Equal 'jsonl non-zero exitCode' (Get-CopilotJsonlExitCode -Lines $linesErroExit) 2

$err = Get-CopilotErrorMessage -StdoutText '' -StderrText 'Error: not available'
Assert-Equal 'extracts simple error' $err 'Error: not available'
$semErr = Get-CopilotErrorMessage -StdoutText 'tudo certo' -StderrText ''
Assert-Equal 'no error -> null' $semErr $null

if ($fail -gt 0) { throw "BLOCK: $fail case(s) failed in Test-CopilotCliSupportSelfTest.ps1" }
Write-Host 'OK: Test-CopilotCliSupportSelfTest.ps1' -ForegroundColor Cyan
