#requires -Version 7.4
<#
.SYNOPSIS
    Shared functions for the antigravity backend of the mimir-delegate skill.
.DESCRIPTION
    Resolves the agy executable (PATH, then %LOCALAPPDATA%\agy\bin\agy.exe on Windows only), validates the minimum discovery contract (--print/--prompt
    and --mode), obtains the CLI's observed version, and classifies typed public-review profile
    failures (quota / unauthenticated) from the raw stderr+stdout. Additional adapter flags
    (--output-format, --print-timeout, --model) are not part of this probe: they are proven via
    fake-exe in Invoke-Antigravity's self-tests.

    The support's $quotaFailurePattern is deliberately different from the dispatcher's — there is
    no total order: stricter on \bquota\b / \b402\b / \b429\b and without a bare exhausted; more
    permissive on rate\s*limit / too\s*many\s*requests (matches variants the dispatcher's literal
    does not match). Do not assert regex parity. The $DispatcherQuotaProbePattern probe is a
    literal copy of the dispatcher's and serves ONLY to sanitize the auth Detail — never to
    classify quota in the adapter.
#>

Set-StrictMode -Version Latest

# Quota classification in the adapter (strict). Do not use `quota` without \b nor a bare `exhausted`.
$quotaFailurePattern = '(?i)\bquota\b|rate\s*limit|too\s*many\s*requests|\b429\b|\b402\b|resource_exhausted|(?:credits?|balance|saldo)\s+exhausted|Payment Required|insufficient coding plan balance|weekly usage limit|limite de uso|sem quota|saldo insuficiente'

# Literal copy of Invoke-LlmDelegatePanelDispatch.ps1:$quotaFailurePattern — ONLY to shrink the auth Detail.
$DispatcherQuotaProbePattern = '(?i)(^|[^0-9])(402|429)([^0-9]|$)|Payment Required|insufficient coding plan balance|quota|rate limit|resource_exhausted|(?:credits?|balance|saldo)\s+exhausted|too many requests|weekly usage limit|limite de uso|sem quota|saldo insuficiente'

$DetailWindowRadiusChars = 200
$DetailMaxChars = 400

function Test-AntigravityHelpSupportsContract {
    param([string]$HelpText)
    if ([string]::IsNullOrWhiteSpace($HelpText)) { return $false }
    $hasPrint = $HelpText -match '(?i)(--print|(?<=\s|^|[\s,\(])-p(?=[\s,\)]|$)|--prompt)'
    $hasMode = $HelpText -match '(?i)--mode'
    return ($hasPrint -and $hasMode)
}

function Resolve-AntigravityExe {
    param(
        [string]$Override,
        [switch]$SkipContractCheck
    )

    $exe = $null
    if ($Override) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) {
            throw "BLOCK: agy given in -AntigravityExe does not exist: $Override"
        }
        $exe = (Resolve-Path -LiteralPath $Override).Path
    } else {
        $cmd = Get-Command agy -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            $exe = $cmd.Source
        } elseif ($IsWindows) {
            # %LOCALAPPDATA%\agy\bin\agy.exe is a Windows-only install location; off Windows, PATH only.
            $defaultPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'agy\bin\agy.exe'
            if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
                $exe = (Resolve-Path -LiteralPath $defaultPath).Path
            }
        }
    }

    if (-not $exe) {
        if ($IsWindows) {
            throw 'BLOCK: Antigravity CLI (agy) not found on PATH nor at %LOCALAPPDATA%\agy\bin\agy.exe. Install agy or pass -AntigravityExe.'
        }
        throw 'BLOCK: Antigravity CLI (agy) not found on PATH. Install agy or pass -AntigravityExe.'
    }

    if (-not $SkipContractCheck) {
        $helpText = ''
        try { $helpText = (& $exe --help 2>&1 | Out-String) } catch { $helpText = '' }
        if (-not (Test-AntigravityHelpSupportsContract -HelpText $helpText)) {
            throw "BLOCK: Antigravity CLI at '$exe' does not expose the required flags (--print/--prompt and --mode)."
        }
    }

    return $exe
}

function Get-AntigravityCliVersion {
    param([Parameter(Mandatory)] [string] $AntigravityExe)
    $text = ''
    try { $text = (& $AntigravityExe --version 2>&1 | Out-String).Trim() } catch {
        throw "BLOCK: agy --version failed: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'BLOCK: agy --version returned empty.' }
    $match = [regex]::Match($text, '(?i)(?:agy\s+)?v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)')
    if (-not $match.Success) { throw "BLOCK: unrecognized agy version: $text" }
    return $match.Groups[1].Value
}

function Test-AntigravityAuthenticationFailure {
    param([AllowNull()] [string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match '(?i)unauthoriz|forbidden|login|sign\s*in|authenticat\w*|authoriz\w*|ineligibletier|opening\s+authentication\s+page')
}

function Test-AntigravityQuotaFailure {
    param([AllowNull()] [string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -match $script:quotaFailurePattern)
}

function Get-AntigravityClassificationRaw {
    param(
        [AllowNull()] [string] $StdoutText,
        [AllowNull()] [string] $StderrText
    )
    $raw = ($StderrText ?? '') + "`n" + ($StdoutText ?? '')
    $raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
    return $raw
}

function Normalize-AntigravityErrorField {
    param([AllowNull()] $ErrorField)
    if ($null -eq $ErrorField) { return $null }
    if ($ErrorField -is [string]) {
        $trimmed = $ErrorField.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }
        return $trimmed
    }
    if ($ErrorField -is [System.Management.Automation.PSObject]) {
        foreach ($name in @('message', 'Message')) {
            $prop = $ErrorField.PSObject.Properties[$name]
            if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
                return ([string]$prop.Value).Trim()
            }
        }
        try {
            $compact = ($ErrorField | ConvertTo-Json -Compress -Depth 6)
            if (-not [string]::IsNullOrWhiteSpace($compact)) { return $compact.Trim() }
        } catch { }
        return $null
    }
    $asString = [string]$ErrorField
    if ([string]::IsNullOrWhiteSpace($asString)) { return $null }
    return $asString.Trim()
}

function Get-AntigravityErrorMessage {
    param([string]$StdoutText, [string]$StderrText)
    $combined = @($StderrText, $StdoutText) -join "`n"
    if ([string]::IsNullOrWhiteSpace($combined)) { return $null }
    $lines = @($combined -split "`r?`n")
    $interesting = @($lines | Where-Object {
        $_ -match '(?i)\b(error|failed|unauthorized|forbidden|not\s+available|requires|login|sign\s*in|auth|authenticat\w*|authoriz\w*|invalid|quota|rate\s*limit|exhausted)\b'
    })
    if ($interesting.Count -gt 0) {
        return (($interesting | Select-Object -First 8) -join "`n").Trim()
    }
    return $null
}

function Get-AntigravityDetailWindowAtRadius {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [System.Text.RegularExpressions.Match] $Match,
        [Parameter(Mandatory)] [int] $Radius
    )
    if ($Match.Length -gt $script:DetailMaxChars) {
        return $Match.Value.Substring(0, $script:DetailMaxChars)
    }
    $center = $Match.Index + [int]([math]::Floor($Match.Length / 2))
    $start = [math]::Max(0, $center - $Radius)
    $end = [math]::Min($Text.Length, $center + $Radius)
    # Include the whole match when the window fits within MaxChars.
    $start = [math]::Min($start, $Match.Index)
    $end = [math]::Max($end, $Match.Index + $Match.Length)
    $start = [math]::Max(0, $start)
    $end = [math]::Min($Text.Length, $end)
    $window = $Text.Substring($start, $end - $start)
    if ($window.Length -le $script:DetailMaxChars) { return $window }
    $matchOffset = $Match.Index - $start
    $pad = [math]::Max(0, $script:DetailMaxChars - $Match.Length)
    $keepStart = [math]::Max(0, $matchOffset - [int]([math]::Floor($pad / 2)))
    if (($keepStart + $script:DetailMaxChars) -gt $window.Length) {
        $keepStart = [math]::Max(0, $window.Length - $script:DetailMaxChars)
    }
    return $window.Substring($keepStart, [math]::Min($script:DetailMaxChars, $window.Length - $keepStart))
}

function Get-AntigravityDetailWindow {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [string] $Pattern,
        [int] $Radius = -1,
        [switch] $SanitizeAgainstDispatcherQuotaProbe
    )
    if ($Radius -lt 0) { $Radius = $script:DetailWindowRadiusChars }
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) { return $null }

    $currentRadius = $Radius
    $window = Get-AntigravityDetailWindowAtRadius -Text $Text -Match $match -Radius $currentRadius
    if ($SanitizeAgainstDispatcherQuotaProbe) {
        while (($window -match $script:DispatcherQuotaProbePattern) -and $currentRadius -gt 0) {
            $currentRadius = [math]::Max(0, $currentRadius - 50)
            $window = Get-AntigravityDetailWindowAtRadius -Text $Text -Match $match -Radius $currentRadius
        }
        if ($window -match $script:DispatcherQuotaProbePattern) {
            return 'authentication failure'
        }
    }
    return $window
}

function Resolve-AntigravityPublicReviewFailureReason {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Raw,
        [AllowNull()] [string] $ErrorField
    )
    $errorPresent = -not [string]::IsNullOrWhiteSpace($ErrorField)
    $authCandidate = if ($errorPresent) { $ErrorField } else { $Raw }

    $authInputEfetivo = $null
    if (Test-AntigravityAuthenticationFailure -Text $authCandidate) {
        $authInputEfetivo = $authCandidate
    } elseif (Test-AntigravityAuthenticationFailure -Text $Raw) {
        $authInputEfetivo = $Raw
    }

    if ($null -ne $authInputEfetivo) {
        $authPattern = '(?i)unauthoriz|forbidden|login|sign\s*in|authenticat\w*|authoriz\w*|ineligibletier|opening\s+authentication\s+page'
        $detail = Get-AntigravityDetailWindow -Text $authInputEfetivo -Pattern $authPattern -SanitizeAgainstDispatcherQuotaProbe
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'authentication failure' }
        return [pscustomobject]@{ Reason = 'unauthenticated'; Detail = $detail }
    }

    if (Test-AntigravityQuotaFailure -Text $Raw) {
        $detail = Get-AntigravityDetailWindow -Text $Raw -Pattern $script:quotaFailurePattern
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = 'quota'
        }
        return [pscustomobject]@{ Reason = 'quota'; Detail = $detail }
    }

    return $null
}
