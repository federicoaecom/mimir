#requires -Version 7.4
<#! Tests the mechanical report when the advisory registry cannot be loaded. #>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('mimir-registry-envelope-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
try {
    $tools = Join-Path $tempRoot 'tools'
    $registryDir = Join-Path $tempRoot 'skills/mimir-delegate/scripts'
    $bin = Join-Path $tempRoot 'bin'
    foreach ($dir in @($tools, $registryDir, $bin)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    foreach ($name in @('Invoke-PrePushMechanicalChecks.ps1', 'PrePushGitSupport.ps1', 'Test-PrePushBackendEnumerationParity.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repo "tools/$name") -Destination $tools
    }
    # An isolated, deterministic Git command fixture: the interval has no changes.
    if ($IsWindows) {
        $shim = Join-Path $bin 'git.cmd'
        $gitScript = @'
@echo off
if "%3 %4"=="rev-parse --show-toplevel" echo %~2
if "%3 %4"=="rev-parse --git-dir" echo .git
if "%3 %4"=="rev-parse --abbrev-ref" if "%5"=="HEAD" echo main
if "%3 %4"=="rev-parse --abbrev-ref" if not "%5"=="HEAD" exit /b 1
if "%3 %4"=="rev-parse --verify" echo 0123456789012345678901234567890123456789
if "%3 %4"=="rev-list --count" echo 0
exit /b 0
'@
    } else {
        $shim = Join-Path $bin 'git'
        $gitScript = @'
#!/bin/sh
case "$3 $4" in
  'rev-parse --show-toplevel') printf '%s\n' "$2" ;;
  'rev-parse --git-dir') echo .git ;;
  'rev-parse --abbrev-ref') if [ "$5" = HEAD ]; then echo main; else exit 1; fi ;;
  'rev-parse --verify') echo 0123456789012345678901234567890123456789 ;;
  'rev-list --count') echo 0 ;;
esac
'@
    }
    [IO.File]::WriteAllText($shim, $gitScript.Replace("`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
    if (-not $IsWindows) { & chmod +x $shim; if ($LASTEXITCODE -ne 0) { throw 'Could not make Git fixture executable.' } }
    $env:PATH = $bin + [IO.Path]::PathSeparator + $oldPath
    $registry = Join-Path $registryDir 'LlmDelegateBackendRegistry.psd1'
    $valid = [IO.File]::ReadAllText((Join-Path $repo 'skills/mimir-delegate/scripts/LlmDelegateBackendRegistry.psd1'))
    [IO.File]::WriteAllText($registry, $valid, [Text.UTF8Encoding]::new($false))
    $mechanical = Join-Path $tools 'Invoke-PrePushMechanicalChecks.ps1'
    $parity = Join-Path $tools 'Test-PrePushBackendEnumerationParity.ps1'
    $stdout = Join-Path $tempRoot 'stdout.txt'
    $stderr = Join-Path $tempRoot 'stderr.txt'

    function Invoke-Report {
        & pwsh -NoProfile -NonInteractive -File $mechanical -RootPath $tempRoot -BaseRef main -SkipParse -AsJson 1> $stdout 2> $stderr
        $code = $LASTEXITCODE
        $out = [IO.File]::ReadAllText($stdout)
        $err = [IO.File]::ReadAllText($stderr)
        if ($code -ne 0 -or $err -ne '') { throw "Report expected exit 0 and empty stderr: exit=$code stderr=$err stdout=$out" }
        try { return ($out | ConvertFrom-Json -ErrorAction Stop) } catch { throw "Report must be JSON: $out" }
    }
    $good = Invoke-Report
    if ($good.status -ne 'pass' -or $good.pushReadiness -ne 'ok' -or $good.gates.backendEnumerationParity.status -ne 'pass') { throw 'Valid registry changed the prior report behavior.' }
    $invalid = $valid -replace "ExeParam\s*=\s*'OpenCodeExe'", 'ExeParam = 123'
    if ($invalid -eq $valid) { throw 'Fixture did not replace ExeParam.' }
    [IO.File]::WriteAllText($registry, $invalid, [Text.UTF8Encoding]::new($false))
    & pwsh -NoProfile -NonInteractive -File $parity -RootPath $tempRoot -AsJson 1> $stdout 2> $stderr
    if ($LASTEXITCODE -eq 0 -or [IO.File]::ReadAllText($stdout) -ne '' -or [IO.File]::ReadAllText($stderr) -notmatch 'invalid backend registry') { throw 'Raw gate must reject numeric ExeParam on stderr, with nonzero exit and empty stdout.' }
    $bad = Invoke-Report
    foreach ($field in @('status', 'pushReadiness', 'intervalDiffDiagnosticOnly', 'rootPath', 'git', 'gates', 'mechanicalFailures', 'agentOperationalReminders', 'agentWarnings', 'agentSemanticChecklist', 'nonProseVerdictRequired')) {
        if ($null -eq $bad.PSObject.Properties[$field]) { throw "Report missing $field." }
    }
    $gate = $bad.gates.backendEnumerationParity
    if ($bad.status -ne 'pass' -or $bad.pushReadiness -ne $good.pushReadiness -or @($bad.mechanicalFailures).Count -ne 0 -or $gate.status -ne 'warn' -or @($gate.findings).Count -ne 1 -or $gate.findings[0].code -ne 'BACKEND_ENUMERATION_PARITY_SCRIPT_ERROR' -or $gate.findings[0].severity -ne 'warn' -or $gate.findings[0].message -notmatch 'invalid backend registry' -or @($bad.agentWarnings | Where-Object { $_ -match 'BACKEND_ENUMERATION_PARITY_SCRIPT_ERROR' }).Count -ne 1) { throw 'Invalid registry must be an advisory warning in the complete report.' }
    # A malformed early gate must not prevent a later successful gate or the report.
    [IO.File]::WriteAllText($registry, $valid, [Text.UTF8Encoding]::new($false))
    $early = Join-Path $tools 'Test-PrePushTraceabilityCoverage.ps1'
    [IO.File]::WriteAllText($early, "param(`$RootPath, `$BaseRef, `$ChangedFiles, [switch]`$AsJson)`nWrite-Output '{invalid json'`nexit 0`n", [Text.UTF8Encoding]::new($false))
    $malformed = Invoke-Report
    foreach ($field in @('status', 'pushReadiness', 'intervalDiffDiagnosticOnly', 'rootPath', 'git', 'gates', 'mechanicalFailures', 'agentOperationalReminders', 'agentWarnings', 'agentSemanticChecklist', 'nonProseVerdictRequired')) {
        if ($null -eq $malformed.PSObject.Properties[$field]) { throw "Malformed report missing $field." }
    }
    $earlyGate = $malformed.gates.traceabilityCoverage
    if ($malformed.status -ne 'pass' -or @($malformed.mechanicalFailures).Count -ne 0 -or $earlyGate.status -ne 'warn' -or @($earlyGate.findings).Count -ne 1 -or $earlyGate.findings[0].code -ne 'TRACEABILITY_COVERAGE_SCRIPT_ERROR' -or $earlyGate.findings[0].severity -ne 'warn' -or $earlyGate.findings[0].path -ne 'tools/Test-PrePushTraceabilityCoverage.ps1' -or $earlyGate.findings[0].message -ne 'Advisory failure while running Test-PrePushTraceabilityCoverage.ps1: {invalid json' -or $malformed.gates.backendEnumerationParity.status -ne 'pass' -or @($malformed.agentWarnings | Where-Object { $_ -match 'TRACEABILITY_COVERAGE_SCRIPT_ERROR' }).Count -ne 1) { throw 'Malformed JSON must warn and allow the later gate to pass.' }
    # Existing nonzero diagnostics and optional new-token defaults remain unchanged.
    [IO.File]::WriteAllText($early, "param(`$RootPath, `$BaseRef, `$ChangedFiles, [switch]`$AsJson)`nWrite-Output '{`"status`":`"pass`",`"findings`":[]}'`nexit 7`n", [Text.UTF8Encoding]::new($false))
    $token = Join-Path $tools 'Test-PrePushNewTokenPropagation.ps1'
    [IO.File]::WriteAllText($token, "param(`$RootPath, `$BaseRef, `$ChangedFiles, [switch]`$AsJson)`nWrite-Output '{`"status`":`"pass`",`"findings`":[]}'`nexit 0`n", [Text.UTF8Encoding]::new($false))
    $preserved = Invoke-Report
    if ($preserved.gates.traceabilityCoverage.status -ne 'warn' -or $preserved.gates.traceabilityCoverage.findings[0].message -ne 'Advisory failure while running Test-PrePushTraceabilityCoverage.ps1: {"status":"pass","findings":[]}' -or $preserved.gates.newTokenPropagation.status -ne 'pass' -or $preserved.gates.newTokenPropagation.candidateCount -ne 0 -or $null -ne $preserved.gates.newTokenPropagation.classCounts -or $preserved.gates.newTokenPropagation.truncated -or $preserved.gates.newTokenPropagation.truncatedProseCount -ne 0 -or $preserved.gates.unexpectedChar.status -ne 'skipped') { throw 'Nonzero, optional-field defaults or missing-gate behavior changed.' }
    & pwsh -NoProfile -NonInteractive -File $mechanical -RootPath $tempRoot -BaseRef main -SkipParse 1> $stdout 2> $stderr
    $text = [IO.File]::ReadAllText($stdout)
    if ($LASTEXITCODE -ne 0 -or [IO.File]::ReadAllText($stderr) -ne '' -or $text -notmatch 'TRACEABILITY_COVERAGE=warn' -or $text -notmatch 'BACKEND_ENUMERATION_PARITY_GATE=pass') { throw 'Text report or standalone exit changed.' }
    # Syntactically valid input that PowerShell cannot project retains its original failure.
    $tooDeep = '{"status":"pass","findings":[],"metadata":' + ('[' * 1025) + '0' + (']' * 1025) + '}'
    foreach ($case in @(
        @{ Json = '{"status":"pass","findings":[],"metadata":{"Key":1,"key":2}}'; Diagnostic = 'AsHashTable' }
        @{ Json = $tooDeep; Diagnostic = 'MaxDepth' }
    )) {
        [IO.File]::WriteAllText($early, "param(`$RootPath, `$BaseRef, `$ChangedFiles, [switch]`$AsJson)`nWrite-Output '$($case.Json)'`nexit 0`n", [Text.UTF8Encoding]::new($false))
        foreach ($format in @('json', 'text')) {
            if ($format -eq 'json') {
                & pwsh -NoProfile -NonInteractive -File $mechanical -RootPath $tempRoot -BaseRef main -SkipParse -AsJson 1> $stdout 2> $stderr
            } else {
                & pwsh -NoProfile -NonInteractive -File $mechanical -RootPath $tempRoot -BaseRef main -SkipParse 1> $stdout 2> $stderr
            }
            $code = $LASTEXITCODE
            $out = [IO.File]::ReadAllText($stdout)
            $err = [IO.File]::ReadAllText($stderr)
            if ($code -ne 1 -or $out -ne '' -or $err -notmatch $case.Diagnostic) {
                throw "Valid JSON must retain the baseline failure ($($case.Diagnostic), $format): exit=$code, stdout length=$($out.Length), stderr=$err"
            }
        }
    }
    Write-Output 'OK: Test-PrePushBackendRegistryEnvelopeSelfTest.ps1'
} finally {
    $env:PATH = $oldPath
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
