#requires -Version 7.4
<#
.SYNOPSIS
    Regression test for the typed provider usage/rate-limit resolver in the opencode log.
.DESCRIPTION
    Covers Resolve-OpenCodeProviderLimitHit / Get-OpenCodeUsageLimitError (typed object).
    Sentinel: OK: Test-OpenCodeUsageLimitDetectionSelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'skills/mimir-delegate/scripts'
. (Join-Path $scriptDir 'OpenCodeStreamSupport.ps1')

function Get-Utf8NoBomEncoding { return [System.Text.UTF8Encoding]::new($false) }

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("opencode-usagelimit-selftest-" + [guid]::NewGuid().ToString('N'))
try {
    $logDir = Join-Path $tempRoot 'log'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $line429 = '{"level":"ERROR","service":"provider","statusCode":429,"responseBody":"{\"error\":\"you (example-user) have reached your weekly usage limit, upgrade for higher limits: https://ollama.com/upgrade\"}"}'
    $lineOk  = '{"level":"INFO","service":"session","message":"step_finish reason=stop"}'
    $sinceTime = ([DateTime]::UtcNow).AddSeconds(-10)

    $log429 = Join-Path $logDir '2026-06-21T000001.log'
    [System.IO.File]::WriteAllText($log429, $line429 + "`n", (Get-Utf8NoBomEncoding))
    $hit = Get-OpenCodeUsageLimitError -SinceTime $sinceTime -LogDir $logDir
    if ($null -eq $hit) { throw "ASSERT_FAILED: (a) 429+usage in the log should be detected" }
    if ((Get-OcProp $hit 'kind') -ne 'usage-limit') { throw "ASSERT_FAILED: (a) kind should be usage-limit: $(Get-OcProp $hit 'kind')" }
    if ([string](Get-OcProp $hit 'message') -notmatch 'weekly usage limit') {
        throw "ASSERT_FAILED: (a) message does not contain weekly usage limit"
    }

    $logDirOk = Join-Path $tempRoot 'log-ok'
    New-Item -ItemType Directory -Path $logDirOk -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $logDirOk '2026-06-21T000002.log'), $lineOk + "`n", (Get-Utf8NoBomEncoding))
    $miss = Get-OpenCodeUsageLimitError -SinceTime $sinceTime -LogDir $logDirOk
    if ($null -ne $miss) { throw "ASSERT_FAILED: (b) a log without a limit should return `$null" }

    $logDirOld = Join-Path $tempRoot 'log-old'
    New-Item -ItemType Directory -Path $logDirOld -Force | Out-Null
    $oldLog = Join-Path $logDirOld '2026-06-20T000001.log'
    [System.IO.File]::WriteAllText($oldLog, $line429 + "`n", (Get-Utf8NoBomEncoding))
    (Get-Item -LiteralPath $oldLog).LastWriteTime = [DateTime]::Now.AddHours(-1)
    $outOfWindow = Get-OpenCodeUsageLimitError -SinceTime ([DateTime]::UtcNow).AddSeconds(-10) -LogDir $logDirOld
    if ($null -ne $outOfWindow) { throw "ASSERT_FAILED: (c) a 429 outside the window should return `$null" }

    $logSpace = Join-Path $tempRoot 'log-space'
    New-Item -ItemType Directory -Path $logSpace -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $logSpace 's.log'), '{"statusCode": 429,"msg":"Too Many Requests"}' + "`n", (Get-Utf8NoBomEncoding))
    $rateHit = Get-OpenCodeUsageLimitError -SinceTime $sinceTime -LogDir $logSpace
    if ((Get-OcProp $rateHit 'kind') -ne 'rate-limit') { throw "ASSERT_FAILED: statusCode with a space and no quota phrase should be rate-limit" }

    $stepFinish = '{"type":"step_finish","part":{"cost":0.402,"tokens":{"total":429}}}'
    $sfKind = Get-OpenCodeProviderLimitKindFromText -Text $stepFinish
    if ($null -ne $sfKind) { throw "ASSERT_FAILED: step_finish cost/tokens must not classify as a limit" }

    $combo = '{"statusCode":429,"msg":"weekly usage limit"}'
    if ((Get-OpenCodeProviderLimitKindFromText -Text $combo) -ne 'usage-limit') {
        throw "ASSERT_FAILED: structural 429 + weekly usage limit should be usage-limit"
    }
    if ((Get-OpenCodeProviderLimitKindFromText -Text '{"statusCode":429}') -ne 'rate-limit') {
        throw "ASSERT_FAILED: structural 429 without a quota phrase should be rate-limit"
    }

    'OK: Test-OpenCodeUsageLimitDetectionSelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
