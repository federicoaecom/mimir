#requires -Version 7.4
<#
.SYNOPSIS
    Deterministic self-test of the Antigravity public-review profile, without a real CLI or network.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'fixtures/FakeCliSupport.ps1')

$passed = 0
$failed = 0
function Assert-True([bool] $Condition, [string] $Message) {
    if ($Condition) { $script:passed++; Write-Host "[PASS] $Message" -ForegroundColor Green }
    else { $script:failed++; Write-Host "[FAIL] $Message" -ForegroundColor Red }
}

# Timing budgets. The limit covers two cold `pwsh` starts (runner + fake agy
# through its New-FakeCli launcher), which can take many seconds on a loaded machine.
# Non-timeout cases get a generous limit they never approach when idle; the
# timeout cases keep a real limit but make the fake outlast it by a wide
# margin, and TIMEOUT_QUOTA's limit leaves room for the fake to start and
# write its quota text before the limit fires.
$script:DefaultTimeoutSec = 60
$script:TimeoutCaseSec = 10
$script:TimeoutQuotaCaseSec = 15

function Invoke-CapturedPublicReview {
    param(
        [string] $Prompt,
        [string] $ReceiptPath,
        [string] $FakeExe,
        [hashtable] $Extra = @{}
    )
    $args = @{
        Message = $Prompt
        Model = 'gemini-3.6-flash-high'
        Profile = 'public-review'
        AntigravityExe = $FakeExe
        ReceiptPath = $ReceiptPath
        TimeoutSec = $script:DefaultTimeoutSec
    }
    foreach ($key in $Extra.Keys) { $args[$key] = $Extra[$key] }
    $output = $null
    $errorText = $null
    try { $output = & $script:invokeScript @args } catch { $errorText = $_.Exception.Message }
    $receipt = if (Test-Path -LiteralPath $ReceiptPath -PathType Leaf) {
        Get-Content -LiteralPath $ReceiptPath -Raw -Encoding utf8 | ConvertFrom-Json
    } else { $null }
    return [pscustomobject]@{ output = $output; error = $errorText; receipt = $receipt }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agy-public-review-selftest-' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempRoot)
$invokeScript = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts') 'Invoke-Antigravity.ps1'

try {
    # The body writes its logs next to itself ($PSScriptRoot is $tempRoot).
    $fakeCmd = New-FakeCli -Directory $tempRoot -Name 'fake-agy' -PwshBody @'
param()
if ($args -contains '--help') { 'Usage: agy -p prompt --mode plan --output-format json --print-timeout 5s --model model'; exit 0 }
if ($args -contains '--version') { 'agy 1.1.19'; exit 0 }
$promptIndex = [array]::IndexOf($args, '-p')
$prompt = if ($promptIndex -ge 0) { [string]$args[$promptIndex + 1] } else { '' }
$safe = [regex]::Replace($prompt, '[^A-Za-z0-9_-]', '-')
$log = [ordered]@{
    prompt = $prompt
    cwd = (Get-Location).Path
    args = @($args)
    env = [ordered]@{
        USERPROFILE = $env:USERPROFILE; HOME = $env:HOME; APPDATA = $env:APPDATA
        LOCALAPPDATA = $env:LOCALAPPDATA; TEMP = $env:TEMP; TMP = $env:TMP
        XDG_CONFIG_HOME = $env:XDG_CONFIG_HOME; XDG_DATA_HOME = $env:XDG_DATA_HOME
        XDG_CACHE_HOME = $env:XDG_CACHE_HOME; ANTIGRAVITY_HOME = $env:ANTIGRAVITY_HOME; AGY_HOME = $env:AGY_HOME
    }
    # Folder names the adapter created under the scratch profile (HOME), with their parent's name.
    # Only for SUCCESS: the scan must not change the timing of the process-tree cases.
    profileDirs = if ($prompt -eq 'SUCCESS') {
        @(Get-ChildItem -LiteralPath $env:HOME -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { '{0}|{1}' -f $_.Parent.Name, $_.Name })
    } else { @() }
}
$log | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $PSScriptRoot "invoke-$safe.json") -Encoding utf8NoBOM
switch ($prompt) {
    'AUTH0' { 'Opening authentication page in your browser'; exit 0 }
    'AUTH1' { [Console]::Error.WriteLine('Error authenticating: unauthorized'); exit 7 }
    'AUTH_QUOTA' {
        [Console]::Error.WriteLine('Error authenticating: unauthorized while Individual quota reached nearby')
        exit 1
    }
    'QUOTA429' {
        [Console]::Error.WriteLine('Individual quota reached for antigravity model gemini-3.6-flash-high')
        exit 1
    }
    'RETRIES' {
        [Console]::Error.WriteLine('retries exhausted after 3 attempts')
        exit 1
    }
    'ERR_OBJ_QUOTA' {
        @{ status='ERROR'; response=''; error=@{ message='HTTP 429: rate limit exceeded' } } | ConvertTo-Json -Compress -Depth 5
        exit 0
    }
    'BADJSON' { 'not-json'; exit 0 }
    'STATUSERROR' { @{ status='ERROR'; response=''; error='backend failed' } | ConvertTo-Json -Compress; exit 0 }
    'TIMEOUT' { Start-Sleep -Seconds 120; @{ status='SUCCESS'; response='late' } | ConvertTo-Json -Compress; exit 0 }
    'TIMEOUT_QUOTA' {
        # Write and flush BEFORE the sleep: the timeout's Kill can cut off unsynced buffers.
        [Console]::Error.WriteLine('Individual quota reached before timeout residual')
        [Console]::Error.Flush()
        [Console]::Out.WriteLine('Individual quota reached before timeout residual')
        [Console]::Out.Flush()
        Start-Sleep -Milliseconds 400
        Start-Sleep -Seconds 30
        exit 0
    }
    'CHILD' {
        $child = Start-Process pwsh -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 30') -PassThru
        Set-Content -LiteralPath (Join-Path $PSScriptRoot 'child.pid') -Value $child.Id -Encoding ascii
        @{ status='SUCCESS'; response='CHILD_OK' } | ConvertTo-Json -Compress
        exit 0
    }
    default { @{ status='SUCCESS'; response="OK:$prompt" } | ConvertTo-Json -Compress; exit 0 }
}
'@

    # Success, fixed flags, receipt, version, and isolation of the parent environment.
    $parentEnvBefore = [ordered]@{}
    foreach ($name in @('USERPROFILE','HOME','APPDATA','LOCALAPPDATA','TEMP','TMP','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_CACHE_HOME','ANTIGRAVITY_HOME','AGY_HOME')) {
        $parentEnvBefore[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $okReceipt = Join-Path $tempRoot 'ok.receipt.json'
    $ok = Invoke-CapturedPublicReview -Prompt 'SUCCESS' -ReceiptPath $okReceipt -FakeExe $fakeCmd
    Assert-True ($ok.output -eq 'OK:SUCCESS' -and -not $ok.error) 'returns response from the SUCCESS envelope'
    Assert-True ($ok.receipt.Kind -eq 'antigravity-public-review-receipt' -and $ok.receipt.Profile -eq 'public-review') 'writes typed receipt for the fixed profile'
    Assert-True ($ok.receipt.CliVersion -eq '1.1.19' -and $ok.receipt.CliVersionMatchesBaseline) 'receipt records cliVersion and promoted baseline'
    Assert-True ($ok.receipt.CleanupStatus -eq 'clean' -and $ok.receipt.ScratchRemoved) 'nominal cleanup is classified as clean'
    Assert-True ($ok.receipt.KeyringIsolation -eq 'not-isolated-global-keyring') 'receipt declares global keyring not isolated'
    $okLog = Get-Content -LiteralPath (Join-Path $tempRoot 'invoke-SUCCESS.json') -Raw -Encoding utf8 | ConvertFrom-Json
    $argv = @($okLog.args)
    Assert-True (($argv -join ' ') -match '--mode plan' -and ($argv -join ' ') -match '--model gemini-3.6-flash-high') 'propagates only mode plan and the explicit model'
    Assert-True (-not (($argv -join ' ') -match '--project|--add-dir|accept-edits|dangerously-skip-permissions|approval-mode|--agent')) 'does not forward forbidden options'
    Assert-True ([string]$okLog.cwd -ne (Get-Location).Path) 'child process uses scratch, not the repository root'
    $childEnvValues = @($okLog.env.PSObject.Properties | ForEach-Object { [string]$_.Value })
    Assert-True (@($childEnvValues | Where-Object { $_ -notlike "$($ok.receipt.ScratchPath)*" }).Count -eq 0) 'redirected environment points entirely to scratch'
    $parentUnchanged = $true
    foreach ($name in $parentEnvBefore.Keys) {
        if ($parentEnvBefore[$name] -ne [Environment]::GetEnvironmentVariable($name, 'Process')) { $parentUnchanged = $false }
    }
    Assert-True $parentUnchanged 'redirection does not change the parent process environment'
    # The scratch profile is built one segment per folder: no folder name contains a backslash (off
    # Windows a backslash join creates a single folder literally named 'AppData\Roaming').
    $profileDirs = @($okLog.profileDirs | ForEach-Object { [string]$_ })
    Assert-True (@($profileDirs | Where-Object { ($_ -split '\|', 2)[1].Contains('\') }).Count -eq 0) "scratch profile has no folder name with a backslash ($($profileDirs -join ', '))"
    foreach ($pair in @('AppData|Roaming', 'AppData|Local', '.local|share')) {
        Assert-True ($profileDirs -contains $pair) "scratch profile nests '$pair' as parent|child ($($profileDirs -join ', '))"
    }

    # Concurrent scratch: two simultaneous calls receive a unique, disposable cwd.
    $parallel = 1,2 | ForEach-Object -Parallel {
        $receipt = Join-Path $using:tempRoot ("parallel-$_.receipt.json")
        $out = & $using:invokeScript -Message "RUN$_" -Model gemini-3.6-flash-high -Profile public-review -AntigravityExe $using:fakeCmd -ReceiptPath $receipt -TimeoutSec $using:DefaultTimeoutSec
        [pscustomobject]@{ output=$out; receipt=(Get-Content $receipt -Raw | ConvertFrom-Json) }
    } -ThrottleLimit 2
    Assert-True (@($parallel).Count -eq 2 -and @($parallel | Where-Object { $_.output -match '^OK:RUN' }).Count -eq 2) 'two concurrent calls complete'
    Assert-True ($parallel[0].receipt.ScratchPath -ne $parallel[1].receipt.ScratchPath) 'concurrent scratch is exclusive per call'
    Assert-True ($parallel[0].receipt.ScratchRemoved -and $parallel[1].receipt.ScratchRemoved) 'concurrent scratch is removed in both'

    # Inputs and typed failures.
    $large = Invoke-CapturedPublicReview -Prompt ('x' * 30001) -ReceiptPath (Join-Path $tempRoot 'large.json') -FakeExe $fakeCmd
    Assert-True ($large.error -match 'reason=inputTooLarge') 'prompt above 30000 is rejected without truncating'
    $missing = Invoke-CapturedPublicReview -Prompt 'X' -ReceiptPath (Join-Path $tempRoot 'missing.json') -FakeExe (Join-Path $tempRoot 'missing.exe')
    Assert-True ($missing.error -match 'reason=cliMissing') 'missing CLI uses reason cliMissing'
    $auth0 = Invoke-CapturedPublicReview -Prompt 'AUTH0' -ReceiptPath (Join-Path $tempRoot 'auth0.json') -FakeExe $fakeCmd
    Assert-True ($auth0.error -match 'reason=unauthenticated') 'interactive authentication with exit 0 uses unauthenticated'
    $auth1 = Invoke-CapturedPublicReview -Prompt 'AUTH1' -ReceiptPath (Join-Path $tempRoot 'auth1.json') -FakeExe $fakeCmd
    Assert-True ($auth1.error -match 'reason=unauthenticated') 'authentication failure with non-zero exit uses unauthenticated'
    $authQuota = Invoke-CapturedPublicReview -Prompt 'AUTH_QUOTA' -ReceiptPath (Join-Path $tempRoot 'auth-quota.json') -FakeExe $fakeCmd
    Assert-True ($authQuota.error -match 'reason=unauthenticated') 'auth+quota in raw resolves to unauthenticated'
    Assert-True ($authQuota.error -notmatch '(?i)(^|[^0-9])(402|429)([^0-9]|$)|Payment Required|insufficient coding plan balance|quota|rate limit|resource_exhausted|(?:credits?|balance|saldo)\s+exhausted|too many requests|weekly usage limit|limite de uso|sem quota|saldo insuficiente') 'auth+quota Detail does not feed back into the dispatcher probe'
    $quota429 = Invoke-CapturedPublicReview -Prompt 'QUOTA429' -ReceiptPath (Join-Path $tempRoot 'quota429.json') -FakeExe $fakeCmd
    Assert-True ($quota429.error -match 'reason=quota') '429/Individual quota reached becomes reason=quota'
    Assert-True ($quota429.error -match 'quota' -and $quota429.error.Length -le 500) 'quota Detail preserves evidence and stays short'
    Assert-True ($quota429.receipt.Reason -eq 'quota') 'typed receipt records Reason=quota'
    $retries = Invoke-CapturedPublicReview -Prompt 'RETRIES' -ReceiptPath (Join-Path $tempRoot 'retries.json') -FakeExe $fakeCmd
    Assert-True ($retries.error -match 'reason=processFailure' -and $retries.error -notmatch 'reason=quota') 'retries exhausted does NOT become quota'
    $errObj = Invoke-CapturedPublicReview -Prompt 'ERR_OBJ_QUOTA' -ReceiptPath (Join-Path $tempRoot 'err-obj.json') -FakeExe $fakeCmd
    Assert-True ($errObj.error -match 'reason=quota') '.error object with rate limit becomes quota'
    $bad = Invoke-CapturedPublicReview -Prompt 'BADJSON' -ReceiptPath (Join-Path $tempRoot 'bad.json') -FakeExe $fakeCmd
    Assert-True ($bad.error -match 'reason=invalidOutput') 'invalid JSON uses invalidOutput'
    $statusError = Invoke-CapturedPublicReview -Prompt 'STATUSERROR' -ReceiptPath (Join-Path $tempRoot 'status.json') -FakeExe $fakeCmd
    Assert-True ($statusError.error -match 'reason=processFailure') 'status ERROR uses processFailure'
    $timeout = Invoke-CapturedPublicReview -Prompt 'TIMEOUT' -ReceiptPath (Join-Path $tempRoot 'timeout.json') -FakeExe $fakeCmd -Extra @{ TimeoutSec=$script:TimeoutCaseSec }
    Assert-True ($timeout.error -match 'reason=timeout' -and $timeout.error -match "limit of $($script:TimeoutCaseSec)s") 'timeout without quota preserves timeout Detail'
    $timeoutQuota = Invoke-CapturedPublicReview -Prompt 'TIMEOUT_QUOTA' -ReceiptPath (Join-Path $tempRoot 'timeout-quota.json') -FakeExe $fakeCmd -Extra @{ TimeoutSec=$script:TimeoutQuotaCaseSec }
    Assert-True ($timeoutQuota.error -match 'reason=quota') 'timeout with quota residue promotes to quota'
    # The profile always creates its own scratch cwd: the script declares no -Cd, so a caller cannot choose the cwd.
    Assert-True (-not (Get-Command -Name $script:invokeScript).Parameters.ContainsKey('Cd')) 'the script declares no -Cd parameter'
    $cdOverride = Invoke-CapturedPublicReview -Prompt 'X' -ReceiptPath (Join-Path $tempRoot 'cd.json') -FakeExe $fakeCmd -Extra @{ Cd=$tempRoot }
    Assert-True ($null -ne $cdOverride.error -and $null -eq $cdOverride.output) 'binding -Cd is refused before any invocation'

    # Workspace: empty and safe was already proven by the success case; now .git, repo root, KB root, and reparse points.
    $gitScratch = Join-Path $tempRoot 'git-scratch'; [void][IO.Directory]::CreateDirectory((Join-Path $gitScratch '.git'))
    $gitCase = Invoke-CapturedPublicReview -Prompt 'X' -ReceiptPath (Join-Path $tempRoot 'git.json') -FakeExe $fakeCmd -Extra @{ ScratchPath=$gitScratch }
    Assert-True ($gitCase.error -match 'reason=unsafeWorkspace' -and $gitCase.receipt.Workspace.hasGit) 'scratch with .git is refused'
    $repoCase = Invoke-CapturedPublicReview -Prompt 'X' -ReceiptPath (Join-Path $tempRoot 'repo.json') -FakeExe $fakeCmd -Extra @{ ScratchPath=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
    Assert-True ($repoCase.error -match 'reason=unsafeWorkspace' -and $repoCase.receipt.Workspace.insideRepository) 'repository root is refused'
    $kbScratch = Join-Path $tempRoot 'kb-root'; [void][IO.Directory]::CreateDirectory((Join-Path $kbScratch 'KbObjectsXml'))
    $kbCase = Invoke-CapturedPublicReview -Prompt 'X' -ReceiptPath (Join-Path $tempRoot 'kb.json') -FakeExe $fakeCmd -Extra @{ ScratchPath=$kbScratch }
    Assert-True ($kbCase.error -match 'reason=unsafeWorkspace' -and $kbCase.receipt.Workspace.insideKbWorkspace) 'KB workspace root is refused'
    $junctionTarget = Join-Path $tempRoot 'junction-target'; [void][IO.Directory]::CreateDirectory($junctionTarget)
    $junctionPath = Join-Path $tempRoot 'junction-scratch'
    try {
        # Windows: a junction (no privilege needed). Elsewhere: a directory symlink, which .NET
        # also reports with the ReparsePoint attribute.
        $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $junctionPath -Target $junctionTarget -ErrorAction Stop
        $junctionCase = Invoke-CapturedPublicReview -Prompt 'X' -ReceiptPath (Join-Path $tempRoot 'junction.json') -FakeExe $fakeCmd -Extra @{ ScratchPath=$junctionPath }
        Assert-True ($junctionCase.error -match 'reason=unsafeWorkspace' -and $junctionCase.receipt.Workspace.hasReparsePoint) 'reparse-point scratch is refused'
    } catch {
        Write-Host "[SKIP] $linkType unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Descendant process and clean/degraded/failed semantics.
    $childCase = Invoke-CapturedPublicReview -Prompt 'CHILD' -ReceiptPath (Join-Path $tempRoot 'child.json') -FakeExe $fakeCmd
    Assert-True ($childCase.output -eq 'CHILD_OK' -and @($childCase.receipt.AliveDescendantsAfterCleanup).Count -eq 0 -and $childCase.receipt.CleanupStatus -ne 'failed') 'observed descendant does not stay alive after cleanup'
    $degraded = Invoke-CapturedPublicReview -Prompt 'DEGRADED' -ReceiptPath (Join-Path $tempRoot 'degraded.json') -FakeExe $fakeCmd -Extra @{ SimulateCleanupFailure='degraded' }
    Assert-True ($degraded.output -eq 'OK:DEGRADED' -and $degraded.receipt.CleanupStatus -eq 'degraded' -and $degraded.receipt.Reason -eq 'cleanupIncomplete') 'degraded cleanup preserves the response but does not promote a clean smoke test'
    $failedCleanup = Invoke-CapturedPublicReview -Prompt 'FAILED' -ReceiptPath (Join-Path $tempRoot 'failed.json') -FakeExe $fakeCmd -Extra @{ SimulateCleanupFailure='failed' }
    Assert-True ($failedCleanup.error -match 'reason=cleanupIncomplete' -and $failedCleanup.receipt.CleanupStatus -eq 'failed' -and -not $failedCleanup.receipt.ResponseAccepted) 'failed cleanup invalidates acceptance and uses cleanupIncomplete'

} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Self-test result: $passed passed, $failed failed."
if ($failed -gt 0) { exit 1 }
Write-Host 'ANTIGRAVITY_PUBLIC_REVIEW_SELFTEST_OK'
