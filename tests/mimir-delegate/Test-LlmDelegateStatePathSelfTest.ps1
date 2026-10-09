#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for LlmDelegateStatePath.ps1 (Get-LlmDelegateStateRoot).
.DESCRIPTION
    The machine-level mimir-delegate state lives under <LocalApplicationData>/mimir-delegate on every OS:
      - Windows: %LOCALAPPDATA%\mimir-delegate (unchanged).
      - Off Windows: $XDG_DATA_HOME/mimir-delegate, else $HOME/.local/share/mimir-delegate. There,
        [Environment]::GetFolderPath('LocalApplicationData') returns an empty string until that folder
        exists; the helper must still return a path under the same base (never a temporary folder)
        and must not create it.
    Cases that cannot run on the current OS print a SKIP line.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
$helperPath = Join-Path $scriptsDir 'LlmDelegateStatePath.ps1'

$script:failures = 0
function Assert-Equal {
    param([string]$Label, $Actual, $Expected)
    if ($Actual -ceq $Expected) {
        Write-Host "PASS  $Label" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL  $Label (expected '$Expected'; got '$Actual')" -ForegroundColor Red
        $script:failures++
    }
}

if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    Write-Host "FAIL  helper exists: $helperPath" -ForegroundColor Red
    exit 1
}
. $helperPath

Assert-Equal 'Get-LlmDelegateStateRoot is defined' ([bool](Get-Command Get-LlmDelegateStateRoot -CommandType Function -ErrorAction SilentlyContinue)) $true

if ($IsWindows) {
    # Windows: unchanged location, %LOCALAPPDATA%\mimir-delegate.
    $expectedWindows = Join-Path $env:LOCALAPPDATA 'mimir-delegate'
    Assert-Equal 'Windows: state root is %LOCALAPPDATA%\mimir-delegate' (Get-LlmDelegateStateRoot) $expectedWindows

    # A process-level LOCALAPPDATA override is honored when it is a full path; a relative value is
    # ignored and the known folder is used. The known-folder API does not read the environment.
    $savedLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    $overrideRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('llm-delegate-state-path-selftest-' + [guid]::NewGuid().ToString('N'))
    try {
        $env:LOCALAPPDATA = $overrideRoot
        $rootOverride = $null
        try { $rootOverride = Get-LlmDelegateStateRoot } catch { $rootOverride = "threw: $($_.Exception.Message)" }
        Assert-Equal 'Windows: a LOCALAPPDATA override gives <it>\mimir-delegate' $rootOverride (Join-Path $overrideRoot 'mimir-delegate')
        Assert-Equal 'Windows: the helper does not create the LOCALAPPDATA override folder' (Test-Path -LiteralPath $overrideRoot) $false

        $env:LOCALAPPDATA = 'relative\appdata'
        $rootRelative = $null
        try { $rootRelative = Get-LlmDelegateStateRoot } catch { $rootRelative = "threw: $($_.Exception.Message)" }
        $knownFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        Assert-Equal 'Windows: a relative LOCALAPPDATA is ignored (known folder)' $rootRelative (Join-Path $knownFolder 'mimir-delegate')
    }
    finally {
        $env:LOCALAPPDATA = $savedLocalAppData
        Remove-Item -LiteralPath $overrideRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'SKIP: off-Windows XDG_DATA_HOME / HOME cases (Windows host)' -ForegroundColor Yellow
}
else {
    Write-Host 'SKIP: Windows %LOCALAPPDATA% case (non-Windows host)' -ForegroundColor Yellow

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('llm-delegate-state-path-selftest-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($tempRoot)
    $savedXdg = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME')
    $savedHome = [Environment]::GetEnvironmentVariable('HOME')
    $tempFallback = Join-Path ([System.IO.Path]::GetTempPath()) 'mimir-delegate'
    try {
        # (1) XDG_DATA_HOME points to an existing folder: <it>/mimir-delegate.
        $xdgExisting = Join-Path $tempRoot 'xdg-existing'
        [void][System.IO.Directory]::CreateDirectory($xdgExisting)
        $env:XDG_DATA_HOME = $xdgExisting
        Assert-Equal 'off Windows: existing XDG_DATA_HOME gives <it>/mimir-delegate' (Get-LlmDelegateStateRoot) (Join-Path $xdgExisting 'mimir-delegate')

        # (2) XDG_DATA_HOME points to a folder that does not exist yet: GetFolderPath returns '' and
        #     the helper still answers under that base, without creating anything.
        $xdgMissing = Join-Path $tempRoot 'xdg-missing'
        $env:XDG_DATA_HOME = $xdgMissing
        Assert-Equal 'precondition: GetFolderPath(LocalApplicationData) is empty for a missing XDG_DATA_HOME' ([Environment]::GetFolderPath('LocalApplicationData')) ''
        $rootMissing = $null
        try { $rootMissing = Get-LlmDelegateStateRoot } catch { $rootMissing = "threw: $($_.Exception.Message)" }
        Assert-Equal 'off Windows: missing XDG_DATA_HOME still gives <it>/mimir-delegate' $rootMissing (Join-Path $xdgMissing 'mimir-delegate')
        Assert-Equal 'off Windows: the helper does not create the XDG_DATA_HOME folder' (Test-Path -LiteralPath $xdgMissing) $false

        # (3) No XDG_DATA_HOME and a HOME without .local/share: $HOME/.local/share/mimir-delegate,
        #     never the temporary folder.
        $homeBare = Join-Path $tempRoot 'home-bare'
        [void][System.IO.Directory]::CreateDirectory($homeBare)
        Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue
        $env:HOME = $homeBare
        Assert-Equal 'precondition: GetFolderPath(LocalApplicationData) is empty for a HOME without .local/share' ([Environment]::GetFolderPath('LocalApplicationData')) ''
        $rootHome = $null
        try { $rootHome = Get-LlmDelegateStateRoot } catch { $rootHome = "threw: $($_.Exception.Message)" }
        $expectedHome = Join-Path (Join-Path (Join-Path $homeBare '.local') 'share') 'mimir-delegate'
        Assert-Equal 'off Windows: HOME without .local/share gives $HOME/.local/share/mimir-delegate' $rootHome $expectedHome
        Assert-Equal 'off Windows: the state root is not the temporary folder' ($rootHome -eq $tempFallback) $false
        Assert-Equal 'off Windows: the helper does not create $HOME/.local' (Test-Path -LiteralPath (Join-Path $homeBare '.local')) $false

        # (4) A relative XDG_DATA_HOME is ignored (XDG base directory spec, same as .NET): HOME wins.
        $env:XDG_DATA_HOME = 'relative/data'
        $rootRelative = $null
        try { $rootRelative = Get-LlmDelegateStateRoot } catch { $rootRelative = "threw: $($_.Exception.Message)" }
        Assert-Equal 'off Windows: a relative XDG_DATA_HOME is ignored' $rootRelative $expectedHome

        # (5) XDG_DATA_HOME takes precedence over HOME.
        $env:XDG_DATA_HOME = $xdgMissing
        $rootPrecedence = $null
        try { $rootPrecedence = Get-LlmDelegateStateRoot } catch { $rootPrecedence = "threw: $($_.Exception.Message)" }
        Assert-Equal 'off Windows: XDG_DATA_HOME wins over HOME' $rootPrecedence (Join-Path $xdgMissing 'mimir-delegate')
    }
    finally {
        if ($null -eq $savedXdg) { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue } else { $env:XDG_DATA_HOME = $savedXdg }
        if ($null -eq $savedHome) { Remove-Item Env:\HOME -ErrorAction SilentlyContinue } else { $env:HOME = $savedHome }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:failures -gt 0) {
    Write-Host "$($script:failures) failure(s)" -ForegroundColor Red
    exit 1
}
Write-Output 'OK: Test-LlmDelegateStatePathSelfTest.ps1'
