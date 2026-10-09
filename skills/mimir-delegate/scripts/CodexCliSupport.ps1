#requires -Version 7.4
<#
.SYNOPSIS
    Shared functions for the codex backend of the mimir-delegate skill: discovery of
    the Codex CLI binary, absolute TempDir, per-class KeepDays, and process identity.
.DESCRIPTION
    Dot-source module consumed by Invoke-Codex.ps1.
    No side effects besides invoking `codex --version` on candidates (discovery)
    and local IO under the jobs' TempDir when KeepDays/TempDir are used.

    DISCOVERY (fail-closed): -CodexExe (Override) always wins. Without it:
    - Windows: the npm shim on PATH (Roaming\npm) can be outdated and is rejected by the
      server for newer models. That is why discovery ignores PATH and uses the OpenAI Codex
      desktop app's binaries under %LOCALAPPDATA%\OpenAI\Codex\bin. The canonical
      bin\codex.exe executable prevails when it responds to --version. backup-* directories
      never participate. Only when the canonical one is missing or invalid does discovery fall
      back to the non-backup subdirectories and pick the highest usable version.
    - Linux and macOS: there is no app-binaries folder; discovery takes the
      `codex` executables on PATH, in PATH order, and returns the first one that answers
      `codex --version`.
    With no usable candidate -> BLOCK with instructions. -BasePath (self-test seam) always
    selects the app-binaries discovery under that folder, on every OS.

    TempDir: Resolve-CodexJobTempDir -Override (null/blank = unbound) -> env
    MIMIR_CODEX_JOBS_DIR -> <system temp folder>/codex-jobs ([IO.Path]::GetTempPath(): %TMP%/%TEMP% on
    Windows, $TMPDIR or /tmp elsewhere); always GetFullPath and creates the folder.
    KeepDays: classes A/B/C-codex/C-shared; best-effort (does not throw to Invoke-Codex).
    Resolve-CodexPidAndStartTime: field-by-field merge; never throws.

    Contract validated by Test-CodexCliSupportSelfTest.ps1 and Test-CodexDurableCaptureSelfTest.ps1.

.PARAMETER TempDir
    In the adapters, -TempDir has no default in param(); the effective default lives in this
    helper (-Override null/blank -> env -> <system temp folder>/codex-jobs).
#>

Set-StrictMode -Version Latest

function Get-CodexExeVersion {
    # Reads 'codex-cli X.Y.Z[-alpha.N]' and returns [version] X.Y.Z (ignores pre-release suffix).
    param([string]$ExePath)
    try {
        $raw = & $ExePath --version 2>$null
        $line = @($raw)[0]
        $m = [regex]::Match([string]$line, '(\d+)\.(\d+)\.(\d+)')
        if ($m.Success) {
            return [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
        }
    } catch { }
    return $null
}

function Get-CodexExeCandidatePaths {
    param([Parameter(Mandatory)] [string] $BasePath)

    $paths = [System.Collections.Generic.List[string]]::new()
    $canonical = Join-Path $BasePath 'codex.exe'
    if (Test-Path -LiteralPath $canonical -PathType Leaf) {
        $paths.Add($canonical)
    }

    $fallbackDirs = @(Get-ChildItem -LiteralPath $BasePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Name.StartsWith('backup-', [System.StringComparison]::OrdinalIgnoreCase) })
    foreach ($dir in $fallbackDirs) {
        $nested = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -Filter 'codex.exe' -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
        foreach ($candidate in $nested) {
            $paths.Add([string]$candidate)
        }
    }

    return @($paths)
}

function Resolve-CodexExeFromPath {
    # Off-Windows discovery: the `codex` executables on PATH, in PATH order; the
    # first one whose `codex --version` yields a version wins. Fails closed with a BLOCK.
    $candidates = @(Get-Command codex -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -and (Test-Path -LiteralPath $_.Source -PathType Leaf) } |
        ForEach-Object { [string]$_.Source } |
        Select-Object -Unique)
    if ($candidates.Count -eq 0) {
        throw "BLOCK: codex not found on PATH. Install the Codex CLI or pass -CodexExe <path>."
    }
    foreach ($c in $candidates) {
        if ($null -ne (Get-CodexExeVersion $c)) { return $c }
    }
    throw ("BLOCK: no codex on PATH responded to 'codex --version' (checked: {0}). Install/update the Codex CLI or pass -CodexExe <path>." -f ($candidates -join '; '))
}

function Resolve-CodexExe {
    # Returns the path of the codex.exe to use. -Override forces an explicit path.
    # -BasePath is a deterministic seam for self-tests; adapters use the app's default.
    param(
        [string] $Override,
        [string] $BasePath
    )

    if ($Override) {
        if (Test-Path -LiteralPath $Override -PathType Leaf) { return $Override }
        throw "BLOCK: -CodexExe given does not exist: $Override"
    }

    if (-not $BasePath -and -not $IsWindows) {
        return (Resolve-CodexExeFromPath)
    }

    $base =if ($BasePath) { $BasePath } else { Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin' }
    if (-not (Test-Path -LiteralPath $base -PathType Container)) {
        throw "BLOCK: OpenAI Codex app binaries folder not found: $base. Install/update the app or the Codex CLI (the npm shim is rejected for gpt-5.5)."
    }

    $candidates = @(Get-CodexExeCandidatePaths -BasePath $base)
    if ($candidates.Count -eq 0) {
        throw "BLOCK: no codex.exe found under $base. Update the Codex app/CLI."
    }

    $canonical = Join-Path $base 'codex.exe'
    if ($candidates -contains $canonical) {
        $canonicalVersion = Get-CodexExeVersion $canonical
        if ($null -ne $canonicalVersion) {
            return $canonical
        }
    }

    $best = $null; $bestVer = $null
    foreach ($c in $candidates) {
        if ([string]::Equals($c, $canonical, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $v = Get-CodexExeVersion $c
        if ($null -eq $v) { continue }
        if ($null -eq $bestVer -or $v -gt $bestVer) { $bestVer = $v; $best = $c }
    }
    if (-not $best) {
        throw "BLOCK: no usable codex.exe responded to --version under $base. Update the Codex app/CLI."
    }
    return $best
}

function Get-CodexExecErrorMessage {
    # Extracts an error message from `codex exec`'s stdout/stderr when the server rejects the
    # request (e.g. unsupported model, quota/rate-limit, authentication). Supports:
    # 1. 'ERROR: {json}' lines, or native API error JSON without an 'ERROR:' prefix
    # 2. 'ERROR: <text>' lines
    # 3. Quota, rate, balance, authentication, and service-unavailable sentinels in stdout/stderr.
    param([string]$StdoutText, [string]$StderrText)
    $combined = @($StdoutText, $StderrText) -join "`n"
    if ([string]::IsNullOrWhiteSpace($combined)) { return $null }

    # 1. Lines with the ERROR: prefix and JSON
    $jsonMatches = [regex]::Matches($combined, 'ERROR:\s*(\{.*\})')
    if ($jsonMatches.Count -gt 0) {
        $jsonText = $jsonMatches[$jsonMatches.Count - 1].Groups[1].Value
        try {
            $obj = $jsonText | ConvertFrom-Json
            $msg = $null
            if ($obj.PSObject.Properties['error']) {
                if ($obj.error -is [string]) { $msg = [string]$obj.error }
                elseif ($obj.error.PSObject.Properties['message']) { $msg = [string]$obj.error.message }
            } elseif ($obj.PSObject.Properties['message']) {
                $msg = [string]$obj.message
            }
            if (-not [string]::IsNullOrWhiteSpace($msg)) { return $msg.Trim() }
        } catch { }
        return $jsonText.Trim()
    }

    # 2. Native API error JSON without the ERROR: prefix
    $rawJsonMatches = [regex]::Matches($combined, '(?m)^\s*(\{.*"error".*\})\s*$')
    if ($rawJsonMatches.Count -gt 0) {
        $jsonText = $rawJsonMatches[$rawJsonMatches.Count - 1].Groups[1].Value
        try {
            $obj = $jsonText | ConvertFrom-Json
            $msg = $null
            if ($obj.PSObject.Properties['error']) {
                if ($obj.error -is [string]) { $msg = [string]$obj.error }
                elseif ($obj.error.PSObject.Properties['message']) { $msg = [string]$obj.error.message }
            } elseif ($obj.PSObject.Properties['message']) {
                $msg = [string]$obj.message
            }
            if (-not [string]::IsNullOrWhiteSpace($msg)) { return $msg.Trim() }
        } catch { }
        return $jsonText.Trim()
    }

    # 3. Fallback: 'ERROR: <text>' line without JSON
    $lineMatch = [regex]::Match($combined, 'ERROR:\s*(\S.*)')
    if ($lineMatch.Success) { return $lineMatch.Groups[1].Value.Trim() }

    # 4. Quota, rate, authentication, and service sentinels in lines of the combined text
    $lines = @($combined -split "`r?`n")
    $interesting = @($lines | Where-Object {
        $_ -match '(?i)\b(429|rate[_\s-]?limit(?:ed|exceeded)?|insufficient_quota|quota|credit\s+balance|token\s+limit|too\s+many\s+requests|usage\s*limit|unauthorized|authentication|auth\s+error|invalid_api_key|token\s+expired|session\s+expired|forbidden|overloaded|service\s+unavailable|does\s+not\s+exist|not\s+supported|not\s+available|not\s+found)\b' -or
        $_ -match '(?i)model.{0,60}\b(does\s+not\s+exist|not\s+found|not\s+supported|unavailable|not\s+available)\b'
    })
    if ($interesting.Count -gt 0) {
        return (($interesting | Select-Object -First 8) -join "`n").Trim()
    }

    return $null
}

function Format-CodexUtcTimestamp {
    param([Parameter(Mandatory)] [datetime] $Value)
    $utc = if ($Value.Kind -eq [DateTimeKind]::Utc) { $Value } else { $Value.ToUniversalTime() }
    return $utc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

function ConvertTo-CodexUtcDateTime {
    param([AllowNull()] $Raw)
    if ($null -eq $Raw) { return $null }
    if ($Raw -is [datetime]) {
        $dt = [datetime]$Raw
        if ($dt.Kind -ne [DateTimeKind]::Utc) { $dt = $dt.ToUniversalTime() }
        return $dt
    }
    if ($Raw -is [datetimeoffset]) {
        return ([datetimeoffset]$Raw).UtcDateTime
    }
    $s = [string]$Raw
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $dto = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse(
            $s,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$dto)) {
        return $dto.UtcDateTime
    }
    return $null
}

function Test-CodexProcessStartTimeMatch {
    param(
        $Process,
        [Parameter(Mandatory)] [datetime] $ExpectedStartTimeUtc
    )
    if ($null -eq $Process) { return $false }
    try {
        if ($Process.HasExited) { return $false }
        $st = $Process.StartTime
        if ($st.Kind -ne [DateTimeKind]::Utc) { $st = $st.ToUniversalTime() }
        $exp = $ExpectedStartTimeUtc
        if ($exp.Kind -ne [DateTimeKind]::Utc) { $exp = $exp.ToUniversalTime() }
        return ([Math]::Abs(($st - $exp).TotalMilliseconds) -lt 1000)
    } catch {
        return $false
    }
}

function Resolve-CodexJobTempDir {
    <#
    .SYNOPSIS
        Resolves the absolute Codex jobs folder.
    .PARAMETER Override
        Bound value from the caller. Null or blank = unbound (falls back to env / default).
    .PARAMETER TempDir
        Documentation: the effective default does NOT live in the adapters' param(); it lives
        here (env MIMIR_CODEX_JOBS_DIR or <system temp folder>/codex-jobs, from
        [IO.Path]::GetTempPath()).
    #>
    param([AllowNull()] [string] $Override)

    $candidate = $null
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        $candidate = $Override.Trim()
    } elseif (-not [string]::IsNullOrWhiteSpace($env:MIMIR_CODEX_JOBS_DIR)) {
        $candidate = ([string]$env:MIMIR_CODEX_JOBS_DIR).Trim()
    } else {
        $candidate = Join-Path ([System.IO.Path]::GetTempPath()) 'codex-jobs'
    }

    try {
        $full = [System.IO.Path]::GetFullPath($candidate)
    } catch {
        throw 'BLOCK: failed to create TempDir.'
    }

    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        try {
            New-Item -Path $full -ItemType Directory -Force | Out-Null
        } catch {
            throw 'BLOCK: failed to create TempDir.'
        }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw 'BLOCK: failed to create TempDir.'
    }
    return $full
}

function Get-CodexJobFileProp {
    param($Obj, [string] $Name)
    if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name]) {
        return $Obj.PSObject.Properties[$Name].Value
    }
    return $null
}

function Read-CodexJsonObject {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-CodexJsonAtomic {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Path,
        [switch] $Force
    )
    $json = $Object | ConvertTo-Json -Depth 8
    $tmp = "$Path.tmp"
    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and -not $Force) {
        if (Test-Path -LiteralPath $tmp -PathType Leaf) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        throw [System.InvalidOperationException]::new('CODEX_RESULT_CLOBBER')
    }
    Set-Content -LiteralPath $tmp -Value $json -Encoding utf8
    try {
        if ($Force) {
            Move-Item -LiteralPath $tmp -Destination $Path -Force
        } else {
            Move-Item -LiteralPath $tmp -Destination $Path
        }
    } catch {
        if (Test-Path -LiteralPath $tmp -PathType Leaf) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        if (-not $Force -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw [System.InvalidOperationException]::new('CODEX_RESULT_CLOBBER')
        }
        throw
    }
}

function Resolve-CodexPidAndStartTime {
    # Field-by-field merge of request.json + identity.json. Never throws.
    # Returns { pid; processStartTimeUtc; divergence }.
    param(
        [Parameter(Mandatory)] [string] $TempDir,
        [Parameter(Mandatory)] [string] $JobId
    )

    $base = Join-Path $TempDir $JobId
    $req = Read-CodexJsonObject -Path "$base.request.json"
    $ident = Read-CodexJsonObject -Path "$base.identity.json"

    $reqPid = $null
    $reqTimeRaw = $null
    if ($null -ne $req) {
        $rp = Get-CodexJobFileProp $req 'pid'
        if ($null -ne $rp -and "$rp" -match '^\d+$') { $reqPid = [int]$rp }
        $reqTimeRaw = Get-CodexJobFileProp $req 'processStartTimeUtc'
    }
    $idPid = $null
    $idTimeRaw = $null
    if ($null -ne $ident) {
        $ip = Get-CodexJobFileProp $ident 'pid'
        if ($null -ne $ip -and "$ip" -match '^\d+$') { $idPid = [int]$ip }
        $idTimeRaw = Get-CodexJobFileProp $ident 'processStartTimeUtc'
    }

    $reqTime = ConvertTo-CodexUtcDateTime -Raw $reqTimeRaw
    $idTime = ConvertTo-CodexUtcDateTime -Raw $idTimeRaw

    $divergence = $false
    $effPid = $null
    $effTime = $null

    if ($null -ne $reqPid -and $null -ne $idPid) {
        if ($reqPid -ne $idPid) {
            $divergence = $true
            $effPid = $reqPid
        } else {
            $effPid = $reqPid
        }
    } elseif ($null -ne $reqPid) {
        $effPid = $reqPid
    } elseif ($null -ne $idPid) {
        $effPid = $idPid
    }

    if ($null -ne $reqTime -and $null -ne $idTime) {
        $rt = $reqTime
        $it = $idTime
        if ($rt.Kind -ne [DateTimeKind]::Utc) { $rt = $rt.ToUniversalTime() }
        if ($it.Kind -ne [DateTimeKind]::Utc) { $it = $it.ToUniversalTime() }
        if ([Math]::Abs(($rt - $it).TotalMilliseconds) -ge 1000) {
            $divergence = $true
            $effTime = $reqTime
        } else {
            $effTime = $reqTime
        }
    } elseif ($null -ne $reqTime) {
        $effTime = $reqTime
    } elseif ($null -ne $idTime) {
        $effTime = $idTime
    }

    $effTimeStr = $null
    if ($null -ne $effTime) {
        $effTimeStr = Format-CodexUtcTimestamp -Value $effTime
    }

    return [pscustomobject]@{
        pid                 = $effPid
        processStartTimeUtc = $effTimeStr
        divergence          = [bool]$divergence
    }
}

function Get-CodexJobSuffixMap {
    return [ordered]@{
        'request.json'     = 'request'
        'stdin.txt'        = 'stdin'
        'stream.jsonl'     = 'stream'
        'lastmsg.txt'      = 'lastmsg'
        'stderr.txt'       = 'stderr'
        'result.json'      = 'result'
        'identity.json'    = 'identity'
        'invoke-in.txt'    = 'invoke-in'
        'invoke-err.txt'   = 'invoke-err'
        'request.json.tmp' = 'request-tmp'
        'result.json.tmp'  = 'result-tmp'
        'identity.json.tmp'= 'identity-tmp'
    }
}

function Get-CodexExclusiveMarkerSuffixes {
    return @(
        'lastmsg.txt',
        'identity.json',
        'invoke-in.txt',
        'invoke-err.txt'
    )
}

function Get-CodexCCodexSuffixes {
    $markers = @(Get-CodexExclusiveMarkerSuffixes)
    return @(
        $markers + @(
            'stdin.txt',
            'result.json',
            'request.json.tmp',
            'result.json.tmp',
            'identity.json.tmp'
        ) | ForEach-Object { $_ }
    )
}

function Test-CodexJobProcessAlive {
    param([AllowNull()] $PidValue)
    if ($null -eq $PidValue) { return $false }
    try {
        $p = Get-Process -Id ([int]$PidValue) -ErrorAction Stop
        return (-not $p.HasExited)
    } catch {
        return $false
    }
}

function Invoke-CodexJobsKeepDaysCleanup {
    # Best-effort: internal catch; never throws to Invoke-Codex. divergence -> age.
    param(
        [Parameter(Mandatory)] [string] $TempDir,
        [Parameter(Mandatory)] [ValidateRange(1, 3650)] [int] $KeepDays
    )

    if ($env:MIMIR_CODEX_DISABLE_KEEPDAYS -eq '1') { return }

    try {
        $keepDaysLegacy = [Math]::Max(14, $KeepDays)
        $now = Get-Date
        $limitA = $now.AddDays(-$KeepDays)
        $limitLegacy = $now.AddDays(-$keepDaysLegacy)
        $suffixMap = Get-CodexJobSuffixMap
        $exclusive = @(Get-CodexExclusiveMarkerSuffixes)
        $cCodex = @(Get-CodexCCodexSuffixes)

        $files = @(Get-ChildItem -LiteralPath $TempDir -File -ErrorAction SilentlyContinue)
        $byGuid = @{}
        foreach ($f in $files) {
            $matched = $false
            foreach ($suf in $suffixMap.Keys) {
                if ($f.Name.EndsWith('.' + $suf, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $guidPart = $f.Name.Substring(0, $f.Name.Length - $suf.Length - 1)
                    if ($guidPart -match '^[0-9a-fA-F]{32}$') {
                        if (-not $byGuid.ContainsKey($guidPart)) {
                            $byGuid[$guidPart] = [System.Collections.Generic.List[object]]::new()
                        }
                        $byGuid[$guidPart].Add([pscustomobject]@{
                                File   = $f
                                Suffix = $suf
                            })
                        $matched = $true
                    }
                    break
                }
            }
            # A file that matches no class is never deleted (includes a name without GUID.suffix).
            if (-not $matched) { continue }
        }

        foreach ($guid in @($byGuid.Keys)) {
            $entries = @($byGuid[$guid])
            $reqEntry = @($entries | Where-Object { $_.Suffix -eq 'request.json' }) | Select-Object -First 1
            $hasExclusive = $false
            foreach ($e in $entries) {
                if ($exclusive -contains $e.Suffix) { $hasExclusive = $true; break }
            }

            $class = $null
            $source = $null
            $captureOutcome = $null
            $reqReadable = $false
            if ($null -ne $reqEntry) {
                $reqObj = Read-CodexJsonObject -Path $reqEntry.File.FullName
                if ($null -ne $reqObj) {
                    $reqReadable = $true
                    $source = [string](Get-CodexJobFileProp $reqObj 'source')
                    $captureOutcome = [string](Get-CodexJobFileProp $reqObj 'captureOutcome')
                }
                if ($reqReadable -and ($source -eq 'start-job' -or $source -eq 'invoke-sync')) {
                    $class = 'A'
                } else {
                    $class = 'B'
                }
            } elseif ($hasExclusive) {
                $class = 'C-codex'
            } else {
                $hasShared = $false
                foreach ($e in $entries) {
                    if ($e.Suffix -eq 'stream.jsonl' -or $e.Suffix -eq 'stderr.txt') {
                        $hasShared = $true
                        break
                    }
                }
                if ($hasShared) {
                    # C-shared: never delete stream/stderr without an exclusive Codex marker.
                    continue
                }
                # No request, no marker, no stream/stderr: only unclassified suffixes
                # in the group — do not delete.
                continue
            }

            $examFiles = @()
            if ($class -eq 'A' -or $class -eq 'B') {
                $examFiles = @($entries | ForEach-Object { $_.File })
            } elseif ($class -eq 'C-codex') {
                foreach ($e in $entries) {
                    if ($cCodex -contains $e.Suffix) {
                        $examFiles += $e.File
                    } elseif ($hasExclusive -and ($e.Suffix -eq 'stream.jsonl' -or $e.Suffix -eq 'stderr.txt')) {
                        $examFiles += $e.File
                    }
                }
            }
            if ($examFiles.Count -eq 0) { continue }

            $age = ($examFiles | Measure-Object -Property LastWriteTime -Maximum).Maximum
            $resolved = Resolve-CodexPidAndStartTime -TempDir $TempDir -JobId $guid
            $alive = Test-CodexJobProcessAlive -PidValue $resolved.pid
            $timeDt = ConvertTo-CodexUtcDateTime -Raw $resolved.processStartTimeUtc

            $useAge = $false
            if ($alive -and ($null -ne $timeDt) -and (-not $resolved.divergence)) {
                $proc = $null
                try { $proc = Get-Process -Id ([int]$resolved.pid) -ErrorAction Stop } catch { $proc = $null }
                if (Test-CodexProcessStartTimeMatch -Process $proc -ExpectedStartTimeUtc $timeDt) {
                    continue
                }
                # alive + valid time that does not match -> age
                $useAge = $true
            } elseif ($alive -and ($null -eq $timeDt)) {
                # alive + inconclusive identity -> skip
                continue
            } elseif ($alive -and $resolved.divergence) {
                $useAge = $true
            } elseif ((-not $alive) -and $class -eq 'A' -and $source -eq 'invoke-sync' `
                    -and [string]::IsNullOrWhiteSpace($captureOutcome) `
                    -and $null -eq $resolved.pid `
                    -and $age -gt $now.AddHours(-1)) {
                # no pid + invoke-sync without captureOutcome and mtime < 1 h -> skip
                continue
            } else {
                $useAge = $true
            }

            if (-not $useAge) { continue }

            $limit = if ($class -eq 'A') { $limitA } else { $limitLegacy }
            if ($age -ge $limit) { continue }

            foreach ($f in $examFiles) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # best-effort: never propagates to Invoke-Codex
    }
}
