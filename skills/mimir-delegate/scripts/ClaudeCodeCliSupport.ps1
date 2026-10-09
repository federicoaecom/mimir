#requires -Version 7.4
<#
.SYNOPSIS
    Shared functions for the claude-code backend of the mimir-delegate skill.
.DESCRIPTION
    Resolves the `claude` executable, validates the minimum flag contract used by the adapters, and extracts
    error messages from Claude Code output. Before classifying, discards environment warnings
    that Claude Code emits on stderr even when the call succeeds. No network access on its own,
    except when Resolve-ClaudeCodeExe needs to call `claude --version` / `claude --help` on the
    candidate.
#>

Set-StrictMode -Version Latest

function Get-ClaudeCodeProp {
    param([AllowNull()] $Obj, [string]$Name)
    if ($null -ne $Obj -and -not [string]::IsNullOrEmpty($Name) -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function ConvertFrom-ClaudeCodeVersionText {
    param([string]$Text)
    $m = [regex]::Match([string]$Text, '(\d+)\.(\d+)\.(\d+)')
    if (-not $m.Success) { return $null }
    return [version]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
}

function Get-ClaudeCodeErrorMessage {
    param([string]$StdoutText, [string]$StderrText)

    # Claude Code emits environment warnings on stderr that appear EVEN when the call ends
    # with exit 0 and a valid response (measured on 2026-07-25: same stderr, byte for byte, in a
    # successful run and in a failed run). That is why they cannot classify failure: they are
    # removed before any decision.
    $cleanStderr = Remove-ClaudeCodeEnvironmentNoise -Text $StderrText
    $combined = @($cleanStderr, $StdoutText) -join "`n"
    if ([string]::IsNullOrWhiteSpace($combined)) { return $null }

    # Real failure observed empirically; precedes the heuristic confidence detector.
    if (Test-ClaudeCodeMaxTurnsExhausted -Text $combined) {
        return New-ClaudeCodeMaxTurnsExhaustedEvidenceMessage -EvidenceText $combined
    }

    if (Test-ClaudeCodeWorkspaceNotTrusted -Text $StderrText) {
        return New-ClaudeCodeWorkspaceNotTrustedEvidenceMessage -StderrText $StderrText
    }

    $lines = @($combined -split "`r?`n")
    $interesting = @($lines | Where-Object {
        $_ -match '(?i)\b(error|failed|unauthorized|forbidden|not\s+available|requires|login|auth|spend\s+limit|monthly\s+limit|session\s+limit|rate\s*limit|usage\s*limit|quota)\b' -or
        $_ -match '(?i)claude\.ai/settings/usage'
    })
    if ($interesting.Count -gt 0) {
        return (($interesting | Select-Object -First 8) -join "`n").Trim()
    }
    return $null
}

function New-ClaudeCodeWorkspaceNotTrustedEvidenceMessage {
    param([AllowNull()] [string] $StderrText)

    $rawStderr = ([string]$StderrText).Trim()
    return @"
Claude Code workspace-not-trusted: this workspace has not yet been marked as trusted in the Claude Code environment.

To improve the skill's compatibility, tell the user not to mark the trust automatically. Ask them to send the maintainer: (1) the raw stderr below, after removing any secret; (2) the output of `claude --version`; and (3) whether the refusal happened in Claude Code Desktop or in the CLI.

--- RAW CLAUDE CODE STDERR ---
$rawStderr
--- END RAW CLAUDE CODE STDERR ---
"@.Trim()
}

function New-ClaudeCodeMaxTurnsExhaustedEvidenceMessage {
    param([AllowNull()] [string] $EvidenceText)

    $evidence = ([string]$EvidenceText).Trim()
    return @"
Claude Code max-turns-exhausted: the call spent all its agentic turns without finishing. There may have been partial text before the cutoff — in that case the response exists, but it is truncated.

When there is a turn limit, the first tool call can consume the only turn and leave none to finish. This repository's adapters do not pass --max-turns, so an active limit comes from the CLI itself or from external configuration: investigate where. Immediate alternative: run without tools when the query does not need to read the workspace. This is NOT a workspace-trust problem nor model unavailability.

--- EVIDENCE (stdout + stderr, without environment noise) ---
$evidence
--- END EVIDENCE ---
"@.Trim()
}

function Test-ClaudeCodeMaxTurnsExhausted {
    param([AllowNull()] [string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    # Three triggers, all measured on 2026-07-25: `Reached max turns` (--output-format text mode),
    # `Reached maximum number of turns (N)` (errors[] field of the stream-json final event), and
    # the `error_max_turns` subtype of the same event. The second does NOT match the first
    # pattern — without it, detection depended only on the subtype being prefixed in the evidence.
    return ($Text -match '(?i)(reached\s+max(imum\s+number\s+of)?\s+turns|\berror_max_turns\b)')
}

<#
.SYNOPSIS
    Extracts the error text from a JSONL stream event (`--output-format stream-json`).
.DESCRIPTION
    The stream's outcome does not come in a `type=error` event: measured on 2026-07-25 (claude
    2.1.220), the last line is `type=result` with `subtype` (`success`, `error_max_turns`, ...) and
    `is_error`. Watching only `type=error` left turn exhaustion and execution failure invisible
    to the async path. Returns an empty string when the event carries no failure.

    The human-readable message is NOT guaranteed in `result`: in the measured turn-exhaustion
    event (`subtype=error_max_turns`) the `result` field does not even exist, and the text lives
    in `errors[]` ("Reached maximum number of turns (1)"), with `terminal_reason=max_turns`
    alongside it. That is why the extraction reads all four fields: without `errors[]` the
    preserved evidence would be just the subtype.
#>
function Get-ClaudeCodeStreamEventErrorText {
    param([AllowNull()] $StreamEvent)

    if ($null -eq $StreamEvent) { return '' }
    $props = $StreamEvent.PSObject.Properties

    $type = ''
    if ($props['type']) { $type = [string]$props['type'].Value }

    if ($type -eq 'error') { return ($StreamEvent | ConvertTo-Json -Compress -Depth 10) }
    if ($type -ne 'result') { return '' }

    $isError = $false
    if ($props['is_error']) { $isError = [bool]$props['is_error'].Value }
    if (-not $isError) { return '' }

    $subtype = ''
    if ($props['subtype']) { $subtype = [string]$props['subtype'].Value }
    $terminalReason = ''
    if ($props['terminal_reason']) { $terminalReason = [string]$props['terminal_reason'].Value }
    $resultText = ''
    if ($props['result']) { $resultText = [string]$props['result'].Value }
    $errorsText = ''
    if ($props['errors']) {
        $errorsText = ((@($props['errors'].Value) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim() }) -join ' | ')
    }

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($subtype)) { $parts += "subtype=$subtype" }
    if (-not [string]::IsNullOrWhiteSpace($terminalReason)) { $parts += "terminal_reason=$terminalReason" }
    if (-not [string]::IsNullOrWhiteSpace($resultText)) { $parts += $resultText.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($errorsText)) { $parts += $errorsText }
    if ($parts.Count -eq 0) { return ($StreamEvent | ConvertTo-Json -Compress -Depth 10) }
    return ($parts -join ': ')
}

function Get-ClaudeCodeStreamEventText {
    param([AllowNull()] $StreamEvent)

    $type = [string](Get-ClaudeCodeProp $StreamEvent 'type')
    if ($type -eq 'content_block_delta') {
        $delta = Get-ClaudeCodeProp $StreamEvent 'delta'
        $txt = Get-ClaudeCodeProp $delta 'text'
        if ($null -ne $txt) { return [string]$txt }
        return ''
    }

    if ($type -eq 'assistant') {
        $message = Get-ClaudeCodeProp $StreamEvent 'message'
        $content = @(Get-ClaudeCodeProp $message 'content')
        $parts = @()
        foreach ($c in $content) {
            $txt = Get-ClaudeCodeProp $c 'text'
            if ($null -ne $txt -and -not [string]::IsNullOrEmpty([string]$txt)) {
                $parts += [string]$txt
            }
        }
        return ($parts -join '')
    }

    # The terminal `type=result` event may contain `result.result`, but that field is not text
    # accepted by the panel's contract: it is technical CLI metadata and never becomes a verdict.
    return ''
}

function Get-ClaudeCodeStreamAcceptedTextFromEvents {
    param([AllowNull()] [object[]]$StreamEvents)

    $deltaParts = [System.Collections.Generic.List[string]]::new()
    $assistantParts = [System.Collections.Generic.List[string]]::new()
    foreach ($ev in @($StreamEvents)) {
        $type = [string](Get-ClaudeCodeProp $ev 'type')
        if ($type -eq 'content_block_delta') {
            $txt = Get-ClaudeCodeStreamEventText -StreamEvent $ev
            if (-not [string]::IsNullOrEmpty($txt)) { $deltaParts.Add($txt) }
            continue
        }
        if ($type -eq 'assistant') {
            $txt = Get-ClaudeCodeStreamEventText -StreamEvent $ev
            if (-not [string]::IsNullOrEmpty($txt)) { $assistantParts.Add($txt) }
        }
    }
    if ($deltaParts.Count -gt 0) { return ($deltaParts -join '') }
    return ($assistantParts -join '')
}

function ConvertTo-ClaudeCodeUtcFromUnixSeconds {
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    $seconds = [double]0
    if (-not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$seconds)) {
        return $null
    }
    if ($seconds -le 0) { return $null }
    try {
        return ([System.DateTimeOffset]::FromUnixTimeSeconds([int64][math]::Floor($seconds))).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
    } catch {
        return $null
    }
}

function Get-ClaudeCodeStreamEventQuotaEvidence {
    param([AllowNull()] $StreamEvent)

    if ($null -eq $StreamEvent) { return $null }
    $type = [string](Get-ClaudeCodeProp $StreamEvent 'type')
    $evidenceType = $null
    $apiErrorStatus = Get-ClaudeCodeProp $StreamEvent 'api_error_status'
    $terminalReason = [string](Get-ClaudeCodeProp $StreamEvent 'terminal_reason')
    $rateLimitType = [string](Get-ClaudeCodeProp $StreamEvent 'rateLimitType')
    if ([string]::IsNullOrWhiteSpace($rateLimitType)) { $rateLimitType = [string](Get-ClaudeCodeProp $StreamEvent 'rate_limit_type') }
    $reportedLimitScope = [string](Get-ClaudeCodeProp $StreamEvent 'reportedLimitScope')
    if ([string]::IsNullOrWhiteSpace($reportedLimitScope)) { $reportedLimitScope = [string](Get-ClaudeCodeProp $StreamEvent 'limit_scope') }
    $resetsAtUtc = ConvertTo-ClaudeCodeUtcFromUnixSeconds (Get-ClaudeCodeProp $StreamEvent 'resetsAt')

    $rateLimitInfo = Get-ClaudeCodeProp $StreamEvent 'rate_limit_info'
    if ($null -ne $rateLimitInfo) {
        if ([string]::IsNullOrWhiteSpace($rateLimitType)) { $rateLimitType = [string](Get-ClaudeCodeProp $rateLimitInfo 'type') }
        if ([string]::IsNullOrWhiteSpace($reportedLimitScope)) { $reportedLimitScope = [string](Get-ClaudeCodeProp $rateLimitInfo 'scope') }
        if ([string]::IsNullOrWhiteSpace($resetsAtUtc)) { $resetsAtUtc = ConvertTo-ClaudeCodeUtcFromUnixSeconds (Get-ClaudeCodeProp $rateLimitInfo 'resetsAt') }
    }

    if ($type -eq 'rate_limit_event') {
        $status = [string](Get-ClaudeCodeProp $StreamEvent 'status')
        if ($status -eq 'rejected') { $evidenceType = 'rate-limit-event-rejected' }
    }
    elseif ($type -eq 'assistant') {
        $assistantError = [string](Get-ClaudeCodeProp $StreamEvent 'error')
        if ([string]::IsNullOrWhiteSpace($assistantError)) {
            $message = Get-ClaudeCodeProp $StreamEvent 'message'
            $assistantError = [string](Get-ClaudeCodeProp $message 'error')
        }
        if ($assistantError -match '(?i)rate[_\s-]?limit') { $evidenceType = 'assistant-rate-limit-error' }
    }
    elseif ($type -eq 'result') {
        $resultText = [string](Get-ClaudeCodeProp $StreamEvent 'result')
        $errorsText = ''
        if ($null -ne (Get-ClaudeCodeProp $StreamEvent 'errors')) {
            $errorsText = ((@(Get-ClaudeCodeProp $StreamEvent 'errors') | ForEach-Object { [string]$_ }) -join ' ')
        }
        $combined = @($terminalReason, $resultText, $errorsText) -join ' '
        if ([string]$apiErrorStatus -eq '429') { $evidenceType = 'result-api-error-429' }
        elseif ($terminalReason -eq 'api_error' -and $combined -match '(?i)(429|quota|rate\s*limit|usage\s*limit)') {
            $evidenceType = 'result-api-error-rate-limit'
        }
    }

    if ([string]::IsNullOrWhiteSpace($evidenceType)) { return $null }
    return [pscustomobject]@{
        evidenceType       = $evidenceType
        apiErrorStatus     = if ($null -ne $apiErrorStatus) { [string]$apiErrorStatus } else { $null }
        terminalReason     = if ([string]::IsNullOrWhiteSpace($terminalReason)) { $null } else { $terminalReason }
        rateLimitType      = if ([string]::IsNullOrWhiteSpace($rateLimitType)) { $null } else { $rateLimitType }
        reportedLimitScope = if ([string]::IsNullOrWhiteSpace($reportedLimitScope)) { $null } else { $reportedLimitScope }
        resetsAtUtc        = if ([string]::IsNullOrWhiteSpace($resetsAtUtc)) { $null } else { $resetsAtUtc }
    }
}

function Get-ClaudeCodeStreamQuotaEvidence {
    param([AllowNull()] [object[]]$StreamEvents)

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($ev in @($StreamEvents)) {
        $item = Get-ClaudeCodeStreamEventQuotaEvidence -StreamEvent $ev
        if ($null -ne $item) { $items.Add($item) }
    }
    if ($items.Count -eq 0) {
        return [pscustomobject]@{
            isQuota            = $false
            evidenceTypes      = @()
            apiErrorStatus     = $null
            terminalReason     = $null
            rateLimitType      = $null
            reportedLimitScope = $null
            resetsAtUtc        = $null
        }
    }

    $apiErrorStatus = @($items | ForEach-Object { $_.apiErrorStatus } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
    $terminalReason = @($items | ForEach-Object { $_.terminalReason } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
    $rateLimitType = @($items | ForEach-Object { $_.rateLimitType } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
    $reportedLimitScope = @($items | ForEach-Object { $_.reportedLimitScope } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -First 1)
    $resetsAtUtc = @($items | ForEach-Object { $_.resetsAtUtc } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object | Select-Object -Last 1)
    return [pscustomobject]@{
        isQuota            = $true
        evidenceTypes      = @($items | ForEach-Object { $_.evidenceType } | Select-Object -Unique)
        apiErrorStatus     = if ($apiErrorStatus.Count -gt 0) { [string]$apiErrorStatus[0] } else { $null }
        terminalReason     = if ($terminalReason.Count -gt 0) { [string]$terminalReason[0] } else { $null }
        rateLimitType      = if ($rateLimitType.Count -gt 0) { [string]$rateLimitType[0] } else { $null }
        reportedLimitScope = if ($reportedLimitScope.Count -gt 0) { [string]$reportedLimitScope[0] } else { $null }
        resetsAtUtc        = if ($resetsAtUtc.Count -gt 0) { [string]$resetsAtUtc[0] } else { $null }
    }
}

# Claude Code environment warnings: appear on stderr regardless of the call's outcome
# (including on exit 0 with a valid response), so they are not evidence of failure.
function Test-ClaudeCodeEnvironmentNoiseLine {
    param([AllowNull()] [string] $Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    return (
        $Line -match '(?i)^\s*ignoring\s+\d+\s+permissions\.(allow|deny)\s+entries\b' -or
        $Line -match '(?i)^\s*permission\s+(allow|deny)\s+rule\s*\('
    )
}

function Remove-ClaudeCodeEnvironmentNoise {
    param([AllowNull()] [string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $kept = @(@([string]$Text -split "`r?`n") | Where-Object { -not (Test-ClaudeCodeEnvironmentNoiseLine -Line $_) })
    return (($kept -join "`n").Trim())
}

function Test-ClaudeCodeWorkspaceNotTrusted {
    param([AllowNull()] [string] $Text)
    # Detects ONLY an execution refusal. The "this workspace has not been trusted" warning that
    # accompanies the discarding of allow rules is environment noise and must not trigger this detector.
    $Text = Remove-ClaudeCodeEnvironmentNoise -Text $Text
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return (
        $Text -match '(?i)workspace.{0,80}\b(not|nao|não)\b.{0,80}(trusted|confiavel|confiável)' -or  # lang-allow: matches localized pt-BR output of the external Claude Code CLI
        $Text -match '(?i)\b(not|nao|não)\b.{0,80}(trusted|confiavel|confiável).{0,80}workspace' -or  # lang-allow: matches localized pt-BR output of the external Claude Code CLI
        $Text -match '(?i)mark(ed)? this workspace as trusted' -or
        $Text -match '(?i)marc(ar|ado).{0,80}workspace.{0,80}confi'
    )
}

function Test-ClaudeCodeHelpSupportsContract {
    param([string]$HelpText)
    $required = @(
        '--model',
        '--print',
        '--output-format',
        '--no-session-persistence',
        '--permission-mode',
        '--tools'
    )
    foreach ($flag in $required) {
        if ($HelpText -notmatch [regex]::Escape($flag)) { return $false }
    }
    return $true
}

function Resolve-ClaudeCodeExe {
    param(
        [string]$Override,
        [version]$MinimumVersion = ([version]'2.1.118'),
        [switch]$SkipContractCheck
    )

    if ($Override) {
        if (-not (Test-Path -LiteralPath $Override -PathType Leaf)) {
            throw "BLOCK: the claude executable given in -ClaudeExe does not exist: $Override"
        }
        $exe = (Resolve-Path -LiteralPath $Override).Path
    } else {
        $cmd = Get-Command claude -ErrorAction SilentlyContinue
        if (-not $cmd -or -not $cmd.Source) {
            throw 'BLOCK: claude not found on PATH. Install/authenticate Claude Code or pass -ClaudeExe.'
        }
        $exe = $cmd.Source
    }

    $versionText = ''
    try { $versionText = (& $exe --version 2>&1 | Out-String).Trim() } catch { $versionText = '' }
    $version = ConvertFrom-ClaudeCodeVersionText $versionText
    if ($null -eq $version) {
        throw "BLOCK: could not read the Claude Code version at $exe. Output: $versionText"
    }
    if ($version -lt $MinimumVersion) {
        throw "BLOCK: Claude Code $version is older than the minimum validated version $MinimumVersion for this adapter."
    }

    if (-not $SkipContractCheck) {
        $helpText = ''
        try { $helpText = (& $exe --help 2>&1 | Out-String) } catch { $helpText = '' }
        if (-not (Test-ClaudeCodeHelpSupportsContract -HelpText $helpText)) {
            throw 'BLOCK: Claude Code found, but does not expose the flags required by the adapter (--model, -p, --output-format, --no-session-persistence, --permission-mode, --tools).'
        }
    }

    return $exe
}
