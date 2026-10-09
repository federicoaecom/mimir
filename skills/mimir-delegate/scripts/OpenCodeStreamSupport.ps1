#requires -Version 7.4
<#
.SYNOPSIS
    Shared functions to parse the opencode JSON stream (mimir-delegate skill).
.DESCRIPTION
    Dot-source module consumed by Invoke-OpenCode.ps1 that keeps the stream extraction
    logic in one place. Does not invoke opencode (the parsing is pure; the only external
    read is the provider-limit resolver, which only READS the opencode log).

    Events from `opencode run --format json`: one JSON object per line, with `type`
    (`step_start`, `text`, `tool_use`, `step_finish`, `error`) and `part`. Each `text` event
    belongs to a message (`part.messageID`); the final response is the last message.

    Contract validated by Test-OpenCodeStreamSupportSelfTest.ps1.
#>

Set-StrictMode -Version Latest

function Get-OcProp {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function ConvertFrom-OpenCodeStreamLines {
    # Converts the JSONL lines into events; ignores empty/non-parseable lines.
    param([string[]]$Lines)
    $events = [System.Collections.Generic.List[object]]::new()
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $events.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return $events
}

function Get-OpenCodeStreamErrorMessage {
    # Message from the last type=error event, or $null if there is no error.
    param([object[]]$Events)
    $errs = @(@($Events) | Where-Object { (Get-OcProp $_ 'type') -eq 'error' })
    if ($errs.Count -eq 0) { return $null }
    $last = $errs[$errs.Count - 1]
    $msg = Get-OcProp (Get-OcProp (Get-OcProp $last 'error') 'data') 'message'
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = ($last | ConvertTo-Json -Compress) }
    return [string]$msg
}

function Get-OpenCodeTextParts {
    # List of [pscustomobject]{ mid; text } for text events with non-empty text, in order.
    param([object[]]$Events)
    $parts = [System.Collections.Generic.List[object]]::new()
    foreach ($e in @($Events)) {
        if ((Get-OcProp $e 'type') -ne 'text') { continue }
        $part = Get-OcProp $e 'part'
        $text = [string](Get-OcProp $part 'text')
        if ([string]::IsNullOrEmpty($text)) { continue }
        $parts.Add([pscustomobject]@{ mid = [string](Get-OcProp $part 'messageID'); text = $text })
    }
    return $parts
}

function Get-OpenCodeFinalText {
    # Final response = concatenation of the text parts of the LAST message (messageID).
    # Robust to a final message fragmented across multiple parts; without messageID, uses the last part.
    param([object[]]$TextParts)
    $tp = @(@($TextParts) | Where-Object { $null -ne $_ })
    if ($tp.Count -eq 0) { return '' }
    $lastMid = [string]$tp[$tp.Count - 1].mid
    if ([string]::IsNullOrEmpty($lastMid)) { return [string]$tp[$tp.Count - 1].text }
    return (@($tp | Where-Object { [string]$_.mid -eq $lastMid } | ForEach-Object { [string]$_.text }) -join '')
}

function Get-OpenCodeAllText {
    # All narration (step preambles + final response), in order.
    param([object[]]$TextParts)
    return (@(@($TextParts) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.text }) -join "`n`n")
}

function Get-OpenCodeCompletionSignal {
    # Stream completion signal, derived from the LAST step_finish event and its part.reason.
    # Finding D: agentic reading that exhausts steps ends a step with reason != 'stop' (or
    # no step_finish at all), and the adapter used to return the preamble as if it were the final response.
    # Returns [pscustomobject]{ hasStepFinish; reason; completionVerdict; finalText; lastError; totalCost; tokens }:
    #   hasStepFinish=$false           -> no step_finish in the stream (completion absent)
    #   hasStepFinish=$true; reason=''  -> step_finish present but without a reason field (treat as absent)
    #   hasStepFinish=$true; reason='stop'|'length'|'tool-calls'|... -> explicit reason
    param([object[]]$Events)
    $steps = @(@($Events) | Where-Object { (Get-OcProp $_ 'type') -eq 'step_finish' })
    $parts = @(Get-OpenCodeTextParts -Events $Events)
    $finalText = Get-OpenCodeFinalText -TextParts $parts
    $lastError = Get-OpenCodeStreamErrorMessage -Events $Events
    $totalCost = [double]0
    $lastTokens = 0
    foreach ($step in $steps) {
        $part = Get-OcProp $step 'part'
        $cost = Get-OcProp $part 'cost'
        if ($null -ne $cost) { $totalCost += [double]$cost }
        $tok = Get-OcProp $part 'tokens'
        $tot = Get-OcProp $tok 'total'
        if ($null -ne $tot) { $lastTokens = [int]$tot }
    }
    if ($steps.Count -eq 0) {
        $verdict = Get-OpenCodeCompletionVerdict -HasStepFinish $false -Reason '' -FinalText $finalText
        return [pscustomobject]@{
            hasStepFinish = $false; reason = ''; finishReason = ''
            completionVerdict = [string]$verdict.status; finalText = $finalText; lastError = $lastError
            totalCost = $totalCost; tokens = $lastTokens; verdictMessage = [string]$verdict.message
        }
    }
    $last = $steps[$steps.Count - 1]
    $reason = [string](Get-OcProp (Get-OcProp $last 'part') 'reason')
    $verdict = Get-OpenCodeCompletionVerdict -HasStepFinish $true -Reason $reason -FinalText $finalText
    return [pscustomobject]@{
        hasStepFinish = $true; reason = $reason; finishReason = $reason
        completionVerdict = [string]$verdict.status; finalText = $finalText; lastError = $lastError
        totalCost = $totalCost; tokens = $lastTokens; verdictMessage = [string]$verdict.message
    }
}

function Get-OpenCodeCompletionVerdict {
    # FIXED precedence for Finding D (does NOT handle an explicit stream error; that is handled
    # separately, with priority, by Get-OpenCodeStreamErrorMessage in the caller):
    #   (1) step_finish with reason != 'stop' (includes 'length','tool-calls') -> truncated
    #   (2) no step_finish OR empty reason (completion signal absent)          -> no-completion
    #   (3) empty final text, after a clean completion (reason='stop')         -> empty
    #   otherwise                                                              -> ok
    # Each case is disjoint -> one deterministic message per scenario (self-test fixtures).
    # A null/absent 'reason' is treated as an empty string (falls into (2)); NEVER throws under StrictMode.
    #
    # Reason vocabulary: ONLY 'stop' is success. ANY other value ('length', 'tool-calls',
    # 'content_filter', 'unknown', 'max_tokens', ...) falls into (1) truncated BY DESIGN — including
    # 'tool-calls' with a textual preamble already present, which is exactly the Finding D leak
    # (the turn would become a tool call and the preamble is not the final response). Do NOT "fix"
    # this precedence. Risk to watch: if opencode renames 'stop' upstream (e.g. 'done'), every
    # legitimate call would become truncated -> review here and in skills/mimir-delegate/SKILL.md (KNOWN
    # LIMITATION opencode), which records the opencode version this was mapped against.
    param([bool]$HasStepFinish, [string]$Reason, [string]$FinalText)
    if ($HasStepFinish -and -not [string]::IsNullOrEmpty($Reason) -and $Reason -ne 'stop') {
        return [pscustomobject]@{ status = 'truncated'; reason = $Reason; message = "BLOCK: truncated response (reason=$Reason). Use -Raw to inspect." }
    }
    if (-not $HasStepFinish -or [string]::IsNullOrEmpty($Reason)) {
        return [pscustomobject]@{ status = 'no-completion'; reason = ''; message = 'BLOCK: response with no completion signal (step_finish/reason absent). Use -Raw to inspect.' }
    }
    if ([string]::IsNullOrWhiteSpace($FinalText)) {
        return [pscustomobject]@{ status = 'empty'; reason = $Reason; message = 'BLOCK: no text event in the response. Use -Raw to inspect.' }
    }
    return [pscustomobject]@{ status = 'ok'; reason = $Reason; message = '' }
}

function Get-OpenCodeDefaultProviderLogDir {
    # Without XDG_DATA_HOME: %USERPROFILE% on Windows; HOME elsewhere (Linux and macOS have no
    # USERPROFILE), with the session's $HOME when the HOME variable is not set.
    $userHome = if ($IsWindows) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { $HOME }
    $base = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $userHome '.local/share' }
    return (Join-Path $base 'opencode/log')
}

function Convert-OpenCodeSinceTimeUtc {
    param([datetime]$SinceTime)
    if ($SinceTime.Kind -eq [DateTimeKind]::Utc) { return $SinceTime }
    return $SinceTime.ToUniversalTime()
}

function Convert-OpenCodeLineTimestampUtc {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        $dt = [datetime]$Value
        if ($dt.Kind -eq [DateTimeKind]::Utc) { return $dt }
        if ($dt.Kind -eq [DateTimeKind]::Unspecified) {
            return [DateTime]::SpecifyKind($dt, [DateTimeKind]::Utc)
        }
        return $dt.ToUniversalTime()
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $dto = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$dto)) {
        return $dto.UtcDateTime
    }
    return $null
}

function Get-OpenCodeProviderLimitKindFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $usagePhrase = '(?i)usage limit|Monthly usage limit|weekly usage limit|Insufficient balance|limite de uso|insufficient coding plan balance|resource_exhausted|Payment Required'
    $usageRx = @(
        '(?i)insufficient\s+balance',
        '(?i)insufficient\s+coding\s+plan\s+balance',
        '(?i)(?:credits?|balance|saldo)\s+exhausted',
        '(?i)saldo\s+insuficiente',
        '(?i)sem\s+quota'
    )
    $isUsage = ($Text -match $usagePhrase)
    if (-not $isUsage) {
        foreach ($rx in $usageRx) {
            if ($Text -match $rx) { $isUsage = $true; break }
        }
    }
    if (-not $isUsage) {
        if ($Text -match '"statusCode"\s*:\s*402') { $isUsage = $true }
        elseif ($Text -match '(?i)(?:^|\s)statusCode=402(?:\s|$)') { $isUsage = $true }
    }
    if ($isUsage) { return 'usage-limit' }
    if ($Text -match '"statusCode"\s*:\s*429') { return 'rate-limit' }
    if ($Text -match '(?i)(?:^|\s)statusCode=429(?:\s|$)') { return 'rate-limit' }
    if ($Text -match '(?i)Too Many Requests|rate limit|rate_limit') { return 'rate-limit' }
    return $null
}

function Get-OpenCodeProviderLimitLevelRank {
    param([string]$Level)
    if ([string]::IsNullOrWhiteSpace($Level)) { return 1 }
    if ($Level -match '(?i)^(ERROR|WARN|WARNING)$') { return 0 }
    if ($Level -match '(?i)^INFO$') { return 2 }
    return 1
}

function Get-OpenCodeStreamErrorCandidates {
    param([string[]]$Lines)
    $list = [System.Collections.Generic.List[object]]::new()
    $i = -1
    foreach ($line in @($Lines)) {
        $i++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $evt = $null
        try { $evt = $line | ConvertFrom-Json } catch { continue }
        if ((Get-OcProp $evt 'type') -ne 'error') { continue }
        $text = Get-OcProp (Get-OcProp (Get-OcProp $evt 'error') 'data') 'message'
        if ([string]::IsNullOrWhiteSpace($text)) { $text = ($evt | ConvertTo-Json -Compress) }
        $list.Add([pscustomobject]@{ lineIndex = $i; text = [string]$text })
    }
    return @($list)
}

function Get-OpenCodeProviderLimitLogLines {
    param(
        [Parameter(Mandatory)][datetime]$SinceTime,
        [string]$LogDir,
        [datetime]$NowUtc = [datetime]::UtcNow
    )
    if ([string]::IsNullOrWhiteSpace($LogDir)) { $LogDir = Get-OpenCodeDefaultProviderLogDir }
    $result = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) { return @($result) }
    $t0 = Convert-OpenCodeSinceTimeUtc -SinceTime $SinceTime
    if ($NowUtc.Kind -ne [DateTimeKind]::Utc) { $NowUtc = $NowUtc.ToUniversalTime() }
    $fileStart = $t0.AddSeconds(-5)
    $logs = @(Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -ge $fileStart -and $_.LastWriteTimeUtc -le $NowUtc })
    foreach ($log in $logs) {
        $rawLines = @(Get-Content -LiteralPath $log.FullName -Encoding utf8 -ErrorAction SilentlyContinue)
        $li = -1
        foreach ($raw in $rawLines) {
            $li++
            $lineTs = $null
            $level = ''
            $obj = $null
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                try { $obj = $raw | ConvertFrom-Json } catch { $obj = $null }
            }
            if ($null -ne $obj) {
                foreach ($name in @('time', 'timestamp', 'ts')) {
                    $lineTs = Convert-OpenCodeLineTimestampUtc (Get-OcProp $obj $name)
                    if ($null -ne $lineTs) { break }
                }
                $level = [string](Get-OcProp $obj 'level')
            } elseif ($raw -match 'timestamp=([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+(?:Z|[+-][0-9]{2}:[0-9]{2}))') {
                $lineTs = Convert-OpenCodeLineTimestampUtc $Matches[1]
                if ($raw -match '(?i)(?:^|\s)level=([A-Za-z]+)') { $level = [string]$Matches[1] }
            }
            if ($null -ne $lineTs) {
                if ($lineTs -lt $t0 -or $lineTs -gt $NowUtc) { continue }
            }
            $result.Add([pscustomobject]@{
                path = [string]$log.FullName
                lineIndex = $li
                raw = [string]$raw
                lineTimestampUtc = $lineTs
                lastWriteTimeUtc = $log.LastWriteTimeUtc
                level = $level
            })
        }
    }
    return @($result)
}

function Select-OpenCodeProviderLimitHit {
    param([object[]]$Candidates)
    $usage = @($Candidates | Where-Object { $_.kind -eq 'usage-limit' })
    $rate = @($Candidates | Where-Object { $_.kind -eq 'rate-limit' })
    $pool = $usage
    if ($pool.Count -eq 0) { $pool = $rate }
    if ($pool.Count -eq 0) { return $null }
    $withTs = @($pool | Where-Object { $null -ne $_.lineTimestampUtc })
    if ($withTs.Count -gt 0) {
        $maxTs = ($withTs | Measure-Object -Property lineTimestampUtc -Maximum).Maximum
        $pool = @($withTs | Where-Object { $_.lineTimestampUtc -eq $maxTs })
    }
    $bestLevel = ($pool | ForEach-Object { [int]$_.levelRank } | Measure-Object -Minimum).Minimum
    $pool = @($pool | Where-Object { [int]$_.levelRank -eq $bestLevel })
    $bestSrc = ($pool | ForEach-Object { [int]$_.sourceRank } | Measure-Object -Minimum).Minimum
    $pool = @($pool | Where-Object { [int]$_.sourceRank -eq $bestSrc })
    $logPool = @($pool | Where-Object { $_.source -eq 'log' })
    if ($logPool.Count -gt 0 -and $pool.Count -eq $logPool.Count) {
        $maxMtime = ($logPool | Measure-Object -Property lastWriteTimeUtc -Maximum).Maximum
        $pool = @($logPool | Where-Object { $_.lastWriteTimeUtc -eq $maxMtime })
    }
    $ord = @($pool | Sort-Object @{ Expression = { [string]$_.sourceFile }; Ascending = $true }, @{ Expression = { [int]$_.lineIndex }; Ascending = $true })
    $win = $ord[0]
    return [pscustomobject]@{
        kind = [string]$win.kind
        message = [string]$win.message
        lineTimestampUtc = $win.lineTimestampUtc
        sourceFile = [string]$win.sourceFile
        lineIndex = [int]$win.lineIndex
        source = [string]$win.source
    }
}

function Resolve-OpenCodeProviderLimitHit {
    param(
        [object[]]$StreamErrors,
        [string]$StderrText = '',
        [object[]]$LogLines,
        [datetime]$SinceTime,
        [string]$LogDir,
        [datetime]$NowUtc = [datetime]::UtcNow
    )
    $cands = [System.Collections.Generic.List[object]]::new()
    foreach ($se in @($StreamErrors)) {
        $text = [string](Get-OcProp $se 'text')
        $kind = Get-OpenCodeProviderLimitKindFromText -Text $text
        if ($null -eq $kind) { continue }
        $idx = 0
        $idxVal = Get-OcProp $se 'lineIndex'
        if ($null -ne $idxVal) { $idx = [int]$idxVal }
        $cands.Add([pscustomobject]@{
            kind = $kind; message = $text; lineTimestampUtc = $null
            sourceFile = 'stream'; lineIndex = $idx; source = 'stream'
            sourceRank = 0; levelRank = 1; lastWriteTimeUtc = [datetime]::MinValue
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($StderrText)) {
        $kind = Get-OpenCodeProviderLimitKindFromText -Text $StderrText
        if ($null -ne $kind) {
            $cands.Add([pscustomobject]@{
                kind = $kind; message = [string]$StderrText; lineTimestampUtc = $null
                sourceFile = 'stderr'; lineIndex = 0; source = 'stderr'
                sourceRank = 1; levelRank = 1; lastWriteTimeUtc = [datetime]::MinValue
            })
        }
    }
    if (-not $PSBoundParameters.ContainsKey('LogLines')) {
        if ($PSBoundParameters.ContainsKey('SinceTime')) {
            $LogLines = @(Get-OpenCodeProviderLimitLogLines -SinceTime $SinceTime -LogDir $LogDir -NowUtc $NowUtc)
        } else {
            $LogLines = @()
        }
    }
    foreach ($ll in @($LogLines)) {
        $raw = [string](Get-OcProp $ll 'raw')
        $kind = Get-OpenCodeProviderLimitKindFromText -Text $raw
        if ($null -eq $kind) { continue }
        $cands.Add([pscustomobject]@{
            kind = $kind; message = $raw
            lineTimestampUtc = (Get-OcProp $ll 'lineTimestampUtc')
            sourceFile = [string](Get-OcProp $ll 'path')
            lineIndex = [int](Get-OcProp $ll 'lineIndex')
            source = 'log'; sourceRank = 2
            levelRank = (Get-OpenCodeProviderLimitLevelRank -Level ([string](Get-OcProp $ll 'level')))
            lastWriteTimeUtc = $(if ($null -ne (Get-OcProp $ll 'lastWriteTimeUtc')) { Get-OcProp $ll 'lastWriteTimeUtc' } else { [datetime]::MinValue })
        })
    }
    return (Select-OpenCodeProviderLimitHit -Candidates @($cands))
}

function Format-OpenCodeLimitBlock {
    param(
        [Parameter(Mandatory)][ValidateSet('usage-limit', 'rate-limit')][string]$Kind,
        [string]$Message = ''
    )
    $fixed = if ($Kind -eq 'usage-limit') {
        'BLOCK: opencode reached the provider usage limit. This is NOT a technical timeout; wait for the usage cycle to reset (usage quota).'
    } else {
        'BLOCK: opencode reached the provider rate limit. Do not retry immediately (rate limit / too many requests).'
    }
    if ([string]::IsNullOrWhiteSpace($Message)) { return $fixed }
    return ($fixed + ' ' + $Message)
}

function Get-OpenCodeUsageLimitError {
    # Wrapper around the resolver (log source only, T0 window). Returns the typed object or $null.
    param(
        [Parameter(Mandatory)][datetime]$SinceTime,
        [string]$LogDir,
        [datetime]$NowUtc = [datetime]::UtcNow
    )
    return Resolve-OpenCodeProviderLimitHit -StreamErrors @() -StderrText '' -SinceTime $SinceTime -LogDir $LogDir -NowUtc $NowUtc
}

function Get-OpenCodeAgentFallbackWarningPattern {
    <# Single logical pattern for the silent-fallback warning emitted by opencode when an
       explicit -Agent does not resolve and the CLI falls back to the default agent. #>
    return 'not found\. Falling back to default agent'
}

function Test-OpenCodeAgentFallbackWarning {
    <#
        Post-check (defense-in-depth): $true if the text contains opencode's generic silent
        fallback warning (`agent "..." not found. Falling back to default agent`),
        a signal that an explicit `--agent` fell back to the default agent.
    #>
    param([string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    return ($Text -match (Get-OpenCodeAgentFallbackWarningPattern))
}
