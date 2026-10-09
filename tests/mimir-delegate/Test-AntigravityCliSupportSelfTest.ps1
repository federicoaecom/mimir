#requires -Version 7.4
<#
.SYNOPSIS
    Self-test of the AntigravityCliSupport.ps1 module and behavioral proof of Invoke-Antigravity.ps1.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'AntigravityCliSupport.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

$passed = 0
$failed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) {
        $script:passed++
        Write-Host "[PASS] $Message" -ForegroundColor Green
    } else {
        $script:failed++
        Write-Host "[FAIL] $Message" -ForegroundColor Red
    }
}

# 1. Test-AntigravityHelpSupportsContract
$helpValid = "Usage of agy: -p Run a prompt --mode Set agent mode"
Assert-True (Test-AntigravityHelpSupportsContract -HelpText $helpValid) "Recognizes help with -p and --mode"

$helpSubstringOnly = "Usage of agy: --project Add project --prompt-interactive Run prompt"
Assert-True (-not (Test-AntigravityHelpSupportsContract -HelpText $helpSubstringOnly)) "Rejects help with -p only as a substring in --project"

# 2. Get-AntigravityErrorMessage
$errText = Get-AntigravityErrorMessage -StdoutText "" -StderrText "Error 429: rate limit exceeded for resource"
Assert-True ($errText -like "*429*") "Extracts quota/rate limit error message"

# 2b. Inflected forms of auth. An isolated `\bauth\b` does NOT match "authentication"/"authenticating" —
# the exact words of the two real failures measured on 2026-08-06 in the sibling CLI (Gemini). Here the
# cost of a false negative remains high: auth text must become unauthenticated, never look like a response (case 8).
$authPrompt = Get-AntigravityErrorMessage -StdoutText "Opening authentication page in your browser. Do you want to continue? [Y/n]:" -StderrText ""
Assert-True ($null -ne $authPrompt) "Recognizes interactive authentication prompt in stdout"
$authErr = Get-AntigravityErrorMessage -StdoutText "" -StderrText "Error authenticating: IneligibleTierError: client no longer supported"
Assert-True ($null -ne $authErr) "Recognizes authentication error in stderr"
$semRuido = Get-AntigravityErrorMessage -StdoutText "Loaded cached credentials" -StderrText ""
Assert-True ($null -eq $semRuido) "Does NOT treat 'Loaded cached credentials' (normal-execution informational line) as an error"

# 3. Quota failure pattern (support — different from the dispatcher by design; do not assert parity/total order)
Assert-True ("quota exceeded" -match $quotaFailurePattern) "Quota regex recognizes 'quota exceeded'"
Assert-True ("Individual Quota Reached" -match $quotaFailurePattern) "Quota regex recognizes mixed-case 'Individual Quota Reached'"
Assert-True ("429 Too Many Requests" -match $quotaFailurePattern) "Quota regex recognizes 429 / Too Many Requests"
Assert-True ("Payment Required" -match $quotaFailurePattern) "Quota regex recognizes Payment Required"
Assert-True ("insufficient coding plan balance" -match $quotaFailurePattern) "Quota regex recognizes insufficient coding plan balance"
Assert-True ("weekly usage limit" -match $quotaFailurePattern) "Quota regex recognizes weekly usage limit"
Assert-True ("limite de uso" -match $quotaFailurePattern) "Quota regex recognizes limite de uso"
Assert-True ("sem quota" -match $quotaFailurePattern) "Quota regex recognizes sem quota"
Assert-True ("saldo insuficiente" -match $quotaFailurePattern) "Quota regex recognizes saldo insuficiente"
Assert-True ("HTTP 402" -match $quotaFailurePattern) "Quota regex recognizes 402 with word-boundary"
Assert-True ("resource_exhausted" -match $quotaFailurePattern) "Quota regex recognizes resource_exhausted"
Assert-True ("credits exhausted for this billing cycle" -match $quotaFailurePattern) "Quota regex recognizes 'credits exhausted'"

# NEGATIVE cases: bare `exhausted` and numeric/word-boundary false positives.
Assert-True (-not ("retries exhausted after 3 attempts" -match $quotaFailurePattern)) "Does NOT treat 'retries exhausted' (network) as quota"
Assert-True (-not ("connection pool exhausted" -match $quotaFailurePattern)) "Does NOT treat 'connection pool exhausted' as quota"
Assert-True (-not ("context window exhausted" -match $quotaFailurePattern)) "Does NOT treat 'context window exhausted' as quota"
Assert-True (-not ("quotation marks" -match $quotaFailurePattern)) "Does NOT treat 'quotation' as quota"
Assert-True (-not ("error 14029" -match $quotaFailurePattern)) "Does NOT treat 14029 as 429"
Assert-True (-not ("error 1402" -match $quotaFailurePattern)) "Does NOT treat 1402 as 402"
Assert-True (-not ("error 4020" -match $quotaFailurePattern)) "Does NOT treat 4020 as 402"

# String parity of the probe (literal copy of the dispatcher) — do NOT use to classify quota.
$dispatcherLiteral = '(?i)(^|[^0-9])(402|429)([^0-9]|$)|Payment Required|insufficient coding plan balance|quota|rate limit|resource_exhausted|(?:credits?|balance|saldo)\s+exhausted|too many requests|weekly usage limit|limite de uso|sem quota|saldo insuficiente'
Assert-True ($DispatcherQuotaProbePattern -ceq $dispatcherLiteral) "DispatcherQuotaProbePattern is a literal copy of the dispatcher"

# Typed resolve: auth wins over quota; quota Detail comes from raw; the extractor is not the body.
$q1 = Resolve-AntigravityPublicReviewFailureReason -Raw "prefix`nIndividual quota reached for model X`nsuffix"
Assert-True ($q1.Reason -eq 'quota' -and $q1.Detail -match 'quota' -and $q1.Detail.Length -le 400) "Resolve classifies Individual quota reached as quota with a short Detail"
$authWins = Resolve-AntigravityPublicReviewFailureReason -Raw "quota exceeded and also unauthorized token" -ErrorField "Error authenticating: unauthorized"
Assert-True ($authWins.Reason -eq 'unauthenticated') "Resolve: auth in ErrorField wins over quota in raw"
Assert-True ($authWins.Detail -notmatch $DispatcherQuotaProbePattern) "Sanitized auth Detail does not match the dispatcher probe"
$authFromRaw = Resolve-AntigravityPublicReviewFailureReason -Raw "Opening authentication page in your browser" -ErrorField "generic failure"
Assert-True ($authFromRaw.Reason -eq 'unauthenticated') "Generic ErrorField does not hide auth in raw"
$objErr = Normalize-AntigravityErrorField -ErrorField ([pscustomobject]@{ message = 'Opening authentication page' })
Assert-True ($objErr -eq 'Opening authentication page') "Normalize-AntigravityErrorField reads .message from object"
$retries = Resolve-AntigravityPublicReviewFailureReason -Raw "retries exhausted after 3 attempts"
Assert-True ($null -eq $retries) "Resolve does NOT classify retries exhausted as quota"


# 4. Resolve-AntigravityExe - deterministic (no real agy): a fake agy launcher is found via PATH, and an
#    explicit override wins or fails closed. The real installed binary is never probed.
$resolveDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agy-resolve-test-' + [System.Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($resolveDir)
$savedPath = $env:PATH
try {
    $fakeOnPath = New-FakeCli -Directory $resolveDir -Name 'agy' -PwshBody "'agy 0.0.0'"
    $env:PATH = $resolveDir
    $exe = Resolve-AntigravityExe -SkipContractCheck
    Assert-True ($exe -eq $fakeOnPath) "Resolve-AntigravityExe discovers a fake agy on PATH ($exe)"
    $env:PATH = $savedPath
    $overridden = Resolve-AntigravityExe -Override $fakeOnPath -SkipContractCheck
    Assert-True ($overridden -eq $fakeOnPath) "Resolve-AntigravityExe honors -Override with an existing file"
    $threw = $false
    try { Resolve-AntigravityExe -Override (Join-Path $resolveDir 'missing-agy.exe') -SkipContractCheck | Out-Null } catch { $threw = ($_.Exception.Message -match '^BLOCK:') }
    Assert-True $threw "Resolve-AntigravityExe fails closed (BLOCK) when -Override does not exist"
} finally {
    $env:PATH = $savedPath
    Remove-Item -LiteralPath $resolveDir -Recurse -Force -ErrorAction SilentlyContinue
}

# 4b. Resolve-AntigravityExe off Windows: PATH only. An agy.exe under the local application data
#     folder (~/.local/share, here redirected through XDG_DATA_HOME) is not a candidate, and the
#     BLOCK message names no Windows-only location.
if ($IsWindows) {
    Write-Host 'SKIP: off-Windows agy discovery cases (Windows host)' -ForegroundColor Yellow
} else {
    $unixDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agy-resolve-unix-test-' + [System.Guid]::NewGuid().ToString('N'))
    $emptyPathDir = Join-Path $unixDir 'empty-path'
    $xdgData = Join-Path $unixDir 'xdg-data'
    [void][System.IO.Directory]::CreateDirectory($emptyPathDir)
    $savedEnv = @{}
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'USERPROFILE', 'XDG_DATA_HOME')) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
    $savedPath = $env:PATH
    try {
        foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'USERPROFILE')) { [Environment]::SetEnvironmentVariable($name, $null) }
        $env:XDG_DATA_HOME = $xdgData
        $planted = Join-Path $xdgData 'agy/bin/agy.exe'
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $planted))
        [System.IO.File]::WriteAllText($planted, '')
        # GetFolderPath returns '' for a folder that does not exist, so check after creating it.
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        Assert-True ($localAppData -eq $xdgData) "precondition: LocalApplicationData follows XDG_DATA_HOME ($localAppData)"

        $env:PATH = $emptyPathDir
        $resolved = $null
        $msg = ''
        try { $resolved = Resolve-AntigravityExe -SkipContractCheck } catch { $msg = $_.Exception.Message }
        Assert-True ($null -eq $resolved) "off Windows: an agy.exe under LocalApplicationData is not a candidate ($resolved)"
        Assert-True ($msg -match '^BLOCK:' -and $msg -notmatch 'LOCALAPPDATA|agy\.exe') "off Windows: no agy on PATH blocks without Windows-only locations ($msg)"
    } finally {
        $env:PATH = $savedPath
        foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnv[$name]) }
        Remove-Item -LiteralPath $unixDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 5. Behavioral proof: fake-exe injection (JSON) via -AntigravityExe for Invoke-Antigravity.ps1
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('agy-fake-test-' + [System.Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempDir)

try {
    $fakeCmd = New-FakeCli -Directory $tempDir -Name 'fake-agy' -PwshBody @'
param()
if ($args -contains '--version') { 'agy 1.1.19'; exit 0 }
if ($args -contains '--help') {
    "Usage of agy: -p Run a prompt --mode Set agent mode --output-format json"
    exit 0
}
$promptIdx = [array]::IndexOf($args, '-p')
$promptVal = if ($promptIdx -ge 0 -and $promptIdx + 1 -lt $args.Count) { $args[$promptIdx + 1] } else { '' }
$resp = @{
    status = "SUCCESS"
    response = "FAKE_AGY_RESPONSE: $promptVal"
} | ConvertTo-Json -Compress
Write-Output $resp
exit 0
'@

    $invokeScript = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-Antigravity.ps1'
    $promptFile = Join-Path $tempDir 'prompt.txt'
    Set-Content -LiteralPath $promptFile -Value 'Teste de prompt via MessagePath' -Encoding utf8

    $output = & $invokeScript -AntigravityExe $fakeCmd -MessagePath $promptFile -Model 'gemini-3.6-flash-high' -Mode plan
    Assert-True ($output -eq 'FAKE_AGY_RESPONSE: Teste de prompt via MessagePath') "Invoke-Antigravity.ps1 via fake-exe parsed JSON and returned response (.response)"

    # 6. Behavioral proof: fake-exe injection that returns PLAIN TEXT (non-JSON) to validate fail-closed rejection as invalidOutput
    $fakeRawCmd = New-FakeCli -Directory $tempDir -Name 'fake-agy-raw' -PwshBody @'
param()
if ($args -contains '--version') { 'agy 1.1.19'; exit 0 }
if ($args -contains '--help') {
    "Usage of agy: -p Run a prompt --mode Set agent mode"
    exit 0
}
Write-Output "RESPOSTA_EM_TEXTO_BRUTO_SEM_JSON"
exit 0
'@

    $rawBlocked = $false
    try { $null = & $invokeScript -AntigravityExe $fakeRawCmd -Message 'Teste texto puro' -Model 'gemini-3.6-flash-high' -Mode plan }
    catch { $rawBlocked = ($_.Exception.Message -match 'reason=invalidOutput') }
    Assert-True $rawBlocked "public-review rejects plain text without a JSON envelope with invalidOutput"

    # 7. Behavioral proof: fake-exe injection that returns JSON with status != SUCCESS (N5 fix validation)
    $fakeErrCmd = New-FakeCli -Directory $tempDir -Name 'fake-agy-err' -PwshBody @'
param()
if ($args -contains '--version') { 'agy 1.1.19'; exit 0 }
if ($args -contains '--help') {
    "Usage of agy: -p Run a prompt --mode Set agent mode"
    exit 0
}
@{
    status = "ERROR"
    response = "should not be used"
} | ConvertTo-Json -Compress
exit 0
'@

    $n5ErrorCaught = $false
    try {
        $null = & $invokeScript -AntigravityExe $fakeErrCmd -Message 'Teste status ERROR' -Model 'gemini-3.6-flash-high' -Mode plan
    } catch {
        if ($_.Exception.Message -match 'reason=processFailure' -and $_.Exception.Message -like "*status 'ERROR'*") {
            $n5ErrorCaught = $true
        }
    }
    Assert-True $n5ErrorCaught "Invoke-Antigravity.ps1 throws a BLOCK exception with status ERROR without being swallowed by the catch"

    # 8. Behavioral proof: REJECTION OF NON-JSON TEXT AND CLASSIFICATION OF AN AUTHENTICATION ERROR.
    # Reproduces the state measured on 2026-08-06 in the Gemini CLI (same family, no cached credential):
    # an interactive login prompt on STDOUT and exit 0. Without the guard, this text was returned as the
    # model's RESPONSE and, since `responded` in the dispatcher is mechanical (any non-empty text suffices),
    # the auth failure entered the panel receipt as a reviewer that RESPONDED. Case 6 above proves that
    # generic non-JSON text becomes invalidOutput; this case distinguishes auth as unauthenticated.
    $fakeAuthCmd = New-FakeCli -Directory $tempDir -Name 'fake-agy-auth' -PwshBody @'
param()
if ($args -contains '--version') { 'agy 1.1.19'; exit 0 }
if ($args -contains '--help') {
    "Usage of agy: -p Run a prompt --mode Set agent mode"
    exit 0
}
Write-Output "Opening authentication page in your browser. Do you want to continue? [Y/n]:"
exit 0
'@

    $authBlockCaught = $false
    $authReturned = $null
    try {
        $authReturned = & $invokeScript -AntigravityExe $fakeAuthCmd -Message 'ping' -Model 'gemini-3.6-flash-high' -Mode plan
    } catch {
        if ($_.Exception.Message -match 'reason=unauthenticated') { $authBlockCaught = $true }
    }
    Assert-True $authBlockCaught "Auth stdout with exit 0 must become BLOCK unauthenticated, not a response"
    Assert-True ([string]::IsNullOrEmpty([string]$authReturned)) "Auth stdout must not be returned as the model's response"

    # --- Get-AntigravityCliVersion: the three branches ---
    # The version became a hard dependency of the public-review receipt, and failing here brings down the
    # whole backend (cliMissing -> unavailable). The self-test's fake-exes for this profile
    # always return 'agy 1.1.19', so the error branches had no coverage at all.
    $fakeVerOk = New-FakeCli -Directory $tempDir -Name 'fake-agy-ver-ok' -PwshBody "'agy 1.1.19'"
    Assert-True ((Get-AntigravityCliVersion -AntigravityExe $fakeVerOk) -eq '1.1.19') "Get-AntigravityCliVersion extracts the version from 'agy 1.1.19'"

    $fakeVerEmpty = New-FakeCli -Directory $tempDir -Name 'fake-agy-ver-empty' -PwshBody 'exit 0'
    $verEmptyBlocked = $false
    try { [void](Get-AntigravityCliVersion -AntigravityExe $fakeVerEmpty) } catch { $verEmptyBlocked = ($_.Exception.Message -match 'returned empty') }
    Assert-True $verEmptyBlocked "Get-AntigravityCliVersion blocks empty output from --version"

    $fakeVerJunk = New-FakeCli -Directory $tempDir -Name 'fake-agy-ver-junk' -PwshBody "'garbage'"
    $verJunkBlocked = $false
    try { [void](Get-AntigravityCliVersion -AntigravityExe $fakeVerJunk) } catch { $verJunkBlocked = ($_.Exception.Message -match 'unrecognized') }
    Assert-True $verJunkBlocked "Get-AntigravityCliVersion blocks output that does not match the version"

    # --- Test-AntigravityAuthenticationFailure: positive and negative ---
    # The negative case guards against regressing to classifying a normal-execution informational line
    # as an authentication failure.
    Assert-True (Test-AntigravityAuthenticationFailure -Text 'Error authenticating: token expired') "Auth detector matches authentication message"
    Assert-True (-not (Test-AntigravityAuthenticationFailure -Text 'Loaded cached credentials')) "Auth detector does NOT match cached-credential informational line"

} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Self-test result: $passed passed, $failed failed."
if ($failed -gt 0) { exit 1 }
Write-Host "OK: Test-AntigravityCliSupportSelfTest.ps1"
