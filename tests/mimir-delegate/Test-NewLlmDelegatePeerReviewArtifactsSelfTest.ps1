#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for the transactional preparer New-LlmDelegatePeerReviewArtifacts.ps1 (mimir-delegate skill).
.DESCRIPTION
    Deterministic, no real backends or network. Covers: success with -ManuscriptText inline and -ManuscriptPath;
    single-line JSON output; artifacts, manifest, hashes, UTF-8 without BOM, pt-BR accents; manuscript source
    missing/ambiguous; large -ManuscriptText; empty/whitespace manuscript;
    malformed JSON; reviewers missing backend/invokeArgs; array root preserved with a single reviewer;
    invalid UTF-8 in input files; unsafe RoundId; final-directory collision;
    injected afterManuscript/beforePublish failure with no final directory and clean staging;
    proof that the preparer does NOT call the dispatcher or the adapters.

    The preparer is invoked as a CHILD PROCESS (pwsh -File) with stdout/stderr redirected to files.

    Success sentinel: OK: Test-NewLlmDelegatePeerReviewArtifactsSelfTest.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-delegate/scripts')
$preparer = Join-Path $scriptsDir 'New-LlmDelegatePeerReviewArtifacts.ps1'
if (-not (Test-Path -LiteralPath $preparer -PathType Leaf)) { throw "BLOCK: target not found: $preparer" }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name]) { return $Obj.PSObject.Properties[$Name].Value }
    return $null
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('gx-artifacts-selftest-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tmp) | Out-Null
$ledgerRoot = Join-Path $tmp 'ledger'

function Invoke-Preparer {
    param(
        [hashtable] $ArgsHashtable,
        [switch] $NoRoundId,
        [switch] $FromFile
    )
    $rid = if ($ArgsHashtable.ContainsKey('RoundId')) { $ArgsHashtable['RoundId'] } else { [guid]::NewGuid().ToString('N') }
    # Sanitize rid for use in file paths in the harness (avoids .. \ /)
    $ridSafe = $rid -replace '[\\/.:*?"<>|]', '_'
    $oFile = Join-Path $tmp "out-$ridSafe.txt"
    $eFile = Join-Path $tmp "err-$ridSafe.txt"

    $argList = @('-NoProfile', '-File', $preparer)

    if (-not $NoRoundId) {
        $argList += @('-RoundId', $rid)
    }

    # ProcessStartInfo.ArgumentList preserves arguments with spaces/newlines/quotes.
    # ReviewersJson stays file-based to keep the test harness readable and focused.
    if ($ArgsHashtable.ContainsKey('ManuscriptText')) {
        $argList += @('-ManuscriptText', $ArgsHashtable['ManuscriptText'])
    }
    if ($ArgsHashtable.ContainsKey('ManuscriptPath')) {
        $argList += @('-ManuscriptPath', $ArgsHashtable['ManuscriptPath'])
    }
    if ($ArgsHashtable.ContainsKey('ReviewersJson')) {
        $revTemp = Join-Path $tmp "rev-$ridSafe.json"
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($revTemp, $ArgsHashtable['ReviewersJson'], $utf8NoBom)
        $argList += @('-ReviewersJson', $revTemp)
    }
    if ($ArgsHashtable.ContainsKey('ReviewersJsonPath')) {
        $argList += @('-ReviewersJson', $ArgsHashtable['ReviewersJsonPath'])
    }
    if ($ArgsHashtable.ContainsKey('TempDir')) {
        $argList += @('-TempDir', $ArgsHashtable['TempDir'])
    }
    if ($ArgsHashtable.ContainsKey('FailAt')) {
        $argList += @('-FailAt', $ArgsHashtable['FailAt'])
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'pwsh'
    foreach ($arg in $argList) {
        [void]$psi.ArgumentList.Add([string]$arg)
    }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = [System.Diagnostics.Process]::new()
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdoutTask = $p.StandardOutput.ReadToEndAsync()
    $stderrTask = $p.StandardError.ReadToEndAsync()
    [void]$p.WaitForExit(60000)
    $stdoutTask.Wait()
    $stderrTask.Wait()
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    [System.IO.File]::WriteAllText($oFile, $stdout, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($eFile, $stderr, [System.Text.UTF8Encoding]::new($false))
    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($stdout)) { try { $json = ($stdout.Trim() -split "`r?`n" | Select-Object -Last 1) | ConvertFrom-Json } catch { } }
    return [pscustomobject]@{ stdout = $stdout; stderr = $stderr; exit = $p.ExitCode; json = $json; roundId = $rid }
}

# =======================================================================================
# 1) SUCCESS WITH INLINE -ManuscriptText
# =======================================================================================
$manuscriptPt = "# Revisão de plano de teste`n`nConteúdo com acentuação pt-BR: revisão, dedução, ação."  # lang-allow: pt-BR payload that verifies accent preservation
$reviewersValid = '[{"backend":"opencode","invokeArgs":{}},{"backend":"codex","invokeArgs":{"model":"gpt-5.5"}}]'

$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
}
Assert-True ($null -ne $r.json) 'inline success: should emit JSON on stdout'
Assert-True ($r.json.Kind -eq 'mimir-peer-review-artifacts-result') 'inline success: Kind PascalCase'
Assert-True ([int]$r.json.SchemaVersion -eq 1) 'inline success: SchemaVersion=1'
Assert-True ($r.json.success -eq $true) 'inline success: success=true'
Assert-True ($r.json.roundStarted -eq $false) 'inline success: roundStarted=false'
Assert-True ($r.json.dispatchStarted -eq $false) 'inline success: dispatchStarted=false'
Assert-True ([int]$r.json.reviewersDispatched -eq 0) 'inline success: reviewersDispatched=0'
Assert-True ($r.exit -eq 0) 'inline success: exit 0'

# stderr should not contain BLOCK
Assert-True ($r.stderr -notmatch 'BLOCK') 'inline success: stderr without BLOCK'

# Check files
$artifactDir = Join-Path $ledgerRoot $r.roundId
Assert-True (Test-Path -LiteralPath $artifactDir -PathType Container) 'inline success: final directory exists'

$msPath = Join-Path $artifactDir 'manuscript.md'
$revPath = Join-Path $artifactDir 'reviewers.json'
$maniPath = Join-Path $artifactDir 'preparation-manifest.json'
Assert-True (Test-Path -LiteralPath $msPath -PathType Leaf) 'inline success: manuscript.md exists'
Assert-True (Test-Path -LiteralPath $revPath -PathType Leaf) 'inline success: reviewers.json exists'
Assert-True (Test-Path -LiteralPath $maniPath -PathType Leaf) 'inline success: preparation-manifest.json exists'

# ---------------------------------------------------------------------------------------
# 1a) UTF-8 without BOM in manuscript.md
# ---------------------------------------------------------------------------------------
$msBytes = [System.IO.File]::ReadAllBytes($msPath)
if ($msBytes.Length -ge 3) {
    Assert-True (-not ($msBytes[0] -eq 0xEF -and $msBytes[1] -eq 0xBB -and $msBytes[2] -eq 0xBF)) 'manuscript.md: no UTF-8 BOM'
}

# ---------------------------------------------------------------------------------------
# 1b) Content preserved with pt-BR accents
# ---------------------------------------------------------------------------------------
$msContent = Get-Content -LiteralPath $msPath -Raw -Encoding utf8
Assert-True ($msContent -eq $manuscriptPt) "manuscript.md: content preserved; expected '$manuscriptPt'; got '$msContent'"
Assert-True ($msContent -match 'revisão') 'manuscript.md: pt-BR accent preserved (revisão)'  # lang-allow: pt-BR payload that verifies accent preservation
Assert-True ($msContent -match 'dedução') 'manuscript.md: pt-BR accent preserved (dedução)'  # lang-allow: pt-BR payload that verifies accent preservation
Assert-True ($msContent -match 'ação') 'manuscript.md: pt-BR accent preserved (ação)'  # lang-allow: pt-BR payload that verifies accent preservation

# ---------------------------------------------------------------------------------------
# 1c) reviewers.json valid and without BOM
# ---------------------------------------------------------------------------------------
$revBytes = [System.IO.File]::ReadAllBytes($revPath)
if ($revBytes.Length -ge 3) {
    Assert-True (-not ($revBytes[0] -eq 0xEF -and $revBytes[1] -eq 0xBB -and $revBytes[2] -eq 0xBF)) 'reviewers.json: no UTF-8 BOM'
}
$revContent = Get-Content -LiteralPath $revPath -Raw -Encoding utf8
$revParsed = $revContent | ConvertFrom-Json -NoEnumerate
Assert-True ($revParsed -is [System.Array]) 'reviewers.json: array root preserved'
Assert-True (@($revParsed).Count -eq 2) 'reviewers.json: 2 reviewers'
Assert-True ($revParsed[0].backend -eq 'opencode') 'reviewers.json: backend=opencode'

# ---------------------------------------------------------------------------------------
# 1d) Manifest
# ---------------------------------------------------------------------------------------
$mani = Get-Content -LiteralPath $maniPath -Raw -Encoding utf8 | ConvertFrom-Json
Assert-True ($mani.Kind -eq 'mimir-peer-review-artifacts-manifest') 'manifest: Kind PascalCase'
Assert-True ([int]$mani.SchemaVersion -eq 1) 'manifest: SchemaVersion=1'
Assert-True ($mani.roundId -eq $r.roundId) 'manifest: roundId matches'
Assert-True ($mani.encoding -eq 'utf-8-no-bom') 'manifest: encoding=utf-8-no-bom'
Assert-True ($mani.manuscriptSource -eq 'inline') 'manifest: manuscriptSource=inline'
Assert-True ([int]$mani.reviewerCount -eq 2) 'manifest: reviewerCount=2'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$mani.artifacts.manuscript.sha256)) 'manifest: manuscript sha256 populated'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$mani.artifacts.reviewers.sha256)) 'manifest: reviewers sha256 populated'
Assert-True ($mani.artifacts.manuscript.filename -eq 'manuscript.md') 'manifest: manuscript filename'
Assert-True ($mani.artifacts.reviewers.filename -eq 'reviewers.json') 'manifest: reviewers filename'
Assert-True ([int]$mani.artifacts.manuscript.size -gt 0) 'manifest: manuscript size > 0'
Assert-True ([int]$mani.artifacts.reviewers.size -gt 0) 'manifest: reviewers size > 0'

# ---------------------------------------------------------------------------------------
# 1e) stdout hashes match the real files
# ---------------------------------------------------------------------------------------
$msRealHash = (Get-FileHash -LiteralPath $msPath -Algorithm SHA256).Hash
$revRealHash = (Get-FileHash -LiteralPath $revPath -Algorithm SHA256).Hash
Assert-True ($r.json.hashes.manuscript -eq $msRealHash) 'stdout manuscript hash matches the real file'
Assert-True ($r.json.hashes.reviewers -eq $revRealHash) 'stdout reviewers hash matches the real file'

# ---------------------------------------------------------------------------------------
# 1f) Artifact paths in stdout
# ---------------------------------------------------------------------------------------
Assert-True ($r.json.artifactPaths.manuscript -eq $msPath) 'stdout artifactPaths.manuscript correct'
Assert-True ($r.json.artifactPaths.reviewers -eq $revPath) 'stdout artifactPaths.reviewers correct'
Assert-True ($r.json.artifactPaths.manifest -eq $maniPath) 'stdout artifactPaths.manifest correct'

# =======================================================================================
# 1g) REVIEWERS WITH A SINGLE ITEM STAYS AN ARRAY
# =======================================================================================
$reviewersSingle = '[{"backend":"opencode","invokeArgs":{}}]'
$rSingle = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersSingle
    TempDir        = $ledgerRoot
}
Assert-True ($rSingle.json.success -eq $true) 'single-reviewer: success=true'
$singleRevPath = Join-Path (Join-Path $ledgerRoot $rSingle.roundId) 'reviewers.json'
$singleRevContent = Get-Content -LiteralPath $singleRevPath -Raw -Encoding utf8
Assert-True ($singleRevContent.TrimStart().StartsWith('[')) 'single-reviewer: reviewers.json should start with an array'
$singleRevParsed = $singleRevContent | ConvertFrom-Json -NoEnumerate
Assert-True ($singleRevParsed -is [System.Array]) 'single-reviewer: array root preserved'
Assert-True (@($singleRevParsed).Count -eq 1) 'single-reviewer: array with 1 item'
Assert-True ($singleRevParsed[0].backend -eq 'opencode') 'single-reviewer: backend preserved'

# =======================================================================================
# 1h) SUCCESS WITH -ManuscriptPath (file)
# =======================================================================================
$msFile = Join-Path $tmp 'manuscript-utf8.md'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($msFile, $manuscriptPt, $utf8NoBom)
$r2 = Invoke-Preparer -ArgsHashtable @{
    ManuscriptPath = $msFile
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
}
Assert-True ($r2.json.success -eq $true) 'ManuscriptPath: success=true'
Assert-True ($r2.exit -eq 0) 'ManuscriptPath: exit 0'
$artifactDir2 = Join-Path $ledgerRoot $r2.roundId
$msPath2 = Join-Path $artifactDir2 'manuscript.md'
$msContent2 = Get-Content -LiteralPath $msPath2 -Raw -Encoding utf8
Assert-True ($msContent2 -eq $manuscriptPt) 'ManuscriptPath: content preserved'
$mani2 = Get-Content -LiteralPath (Join-Path $artifactDir2 'preparation-manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
Assert-True ($mani2.manuscriptSource -eq 'file') 'ManuscriptPath: manuscriptSource=file'

# =======================================================================================
# 1i) INVALID UTF-8 IN INPUT FILES -> FAILURE
# =======================================================================================
$badUtf8Manuscript = Join-Path $tmp 'manuscript-invalid-utf8.md'
[System.IO.File]::WriteAllBytes($badUtf8Manuscript, [byte[]](0x61, 0xFF, 0x62))
$rBadMs = Invoke-Preparer -ArgsHashtable @{
    ManuscriptPath = $badUtf8Manuscript
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
}
Assert-True ($rBadMs.json.success -eq $false) 'utf8-manuscript: success=false'
Assert-True ($rBadMs.json.failureCode -eq 'manuscript-utf8-invalid') "utf8-manuscript: manuscript-utf8-invalid; got $($rBadMs.json.failureCode)"
Assert-True ($rBadMs.exit -eq 1) 'utf8-manuscript: exit 1'

$badUtf8Reviewers = Join-Path $tmp 'reviewers-invalid-utf8.json'
[System.IO.File]::WriteAllBytes($badUtf8Reviewers, [byte[]](0x5B, 0x7B, 0xFF, 0x7D, 0x5D))
$rBadRev = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText     = $manuscriptPt
    ReviewersJsonPath  = $badUtf8Reviewers
    TempDir            = $ledgerRoot
}
Assert-True ($rBadRev.json.success -eq $false) 'utf8-reviewers: success=false'
Assert-True ($rBadRev.json.failureCode -eq 'reviewers-utf8-invalid') "utf8-reviewers: reviewers-utf8-invalid; got $($rBadRev.json.failureCode)"
Assert-True ($rBadRev.exit -eq 1) 'utf8-reviewers: exit 1'

# =======================================================================================
# 2) JSON OUTPUT = EXACTLY 1 LINE
# =======================================================================================
# (already validated in the success case's stdout)
$stdoutTrim = $r.stdout.TrimEnd("`r", "`n")
Assert-True (@($stdoutTrim -split "`n").Count -eq 1) 'stdout: exactly 1 line'

# =======================================================================================
# 2a) MISSING / AMBIGUOUS MANUSCRIPT SOURCE AND LARGE INLINE -> STRUCTURED JSON
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ReviewersJson = $reviewersValid
    TempDir       = $ledgerRoot
}
Assert-True ($null -ne $r.json) 'no-source: should emit JSON on stdout'
Assert-True ($r.json.success -eq $false) 'no-source: success=false'
Assert-True ($r.json.failureCode -eq 'manuscript-source-missing') "no-source: manuscript-source-missing; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'no-source: exit 1'
Assert-True (@($r.stdout.TrimEnd("`r", "`n") -split "`n").Count -eq 1) 'no-source: stdout exactly 1 line'

$bothMsFile = Join-Path $tmp 'manuscript-both.md'
[System.IO.File]::WriteAllText($bothMsFile, $manuscriptPt, [System.Text.UTF8Encoding]::new($false))
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ManuscriptPath = $bothMsFile
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
}
Assert-True ($null -ne $r.json) 'ambiguous-source: should emit JSON on stdout'
Assert-True ($r.json.success -eq $false) 'ambiguous-source: success=false'
Assert-True ($r.json.failureCode -eq 'manuscript-source-ambiguous') "ambiguous-source: manuscript-source-ambiguous; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'ambiguous-source: exit 1'
Assert-True (@($r.stdout.TrimEnd("`r", "`n") -split "`n").Count -eq 1) 'ambiguous-source: stdout exactly 1 line'

$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = ('x' * 30001)
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
}
Assert-True ($null -ne $r.json) 'large-inline: should emit JSON on stdout'
Assert-True ($r.json.success -eq $false) 'large-inline: success=false'
Assert-True ($r.json.failureCode -eq 'manuscript-text-too-large') "large-inline: manuscript-text-too-large; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'large-inline: exit 1'
Assert-True (@($r.stdout.TrimEnd("`r", "`n") -split "`n").Count -eq 1) 'large-inline: stdout exactly 1 line'

# =======================================================================================
# 3) EMPTY / WHITESPACE MANUSCRIPT -> FAILURE
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = ''
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
}
Assert-True ($r.json.success -eq $false) 'empty: success=false'
Assert-True ($r.json.failureCode -eq 'manuscript-empty') "empty: manuscript-empty; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'empty: exit 1'
Assert-True ($r.stderr -match 'BLOCK') 'empty: stderr with BLOCK'

$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = '   '
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
}
Assert-True ($r.json.success -eq $false) 'whitespace: success=false'
Assert-True ($r.json.failureCode -eq 'manuscript-empty') 'whitespace: manuscript-empty'

# =======================================================================================
# 4) MALFORMED JSON -> FAILURE
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = '{garbage-not-json'
    TempDir        = $ledgerRoot
}
Assert-True ($r.json.success -eq $false) 'invalid-json: success=false'
Assert-True ($r.json.failureCode -eq 'reviewers-json-invalid') "invalid-json: reviewers-json-invalid; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'invalid-json: exit 1'

# =======================================================================================
# 5) REVIEWERS MISSING BACKEND -> FAILURE
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = '[{"invokeArgs":{}}]'
    TempDir        = $ledgerRoot
}
Assert-True ($r.json.success -eq $false) 'missing-backend: success=false'
Assert-True ($r.json.failureCode -eq 'reviewer-missing-backend') "missing-backend: reviewer-missing-backend; got $($r.json.failureCode)"

# =======================================================================================
# 6) REVIEWERS WITH A NON-ARRAY ROOT -> FAILURE
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = '{"backend":"opencode","invokeArgs":{}}'
    TempDir        = $ledgerRoot
}
Assert-True ($r.json.success -eq $false) 'root-not-array: success=false'
Assert-True ($r.json.failureCode -eq 'reviewers-root-not-array') "root-not-array: reviewers-root-not-array; got $($r.json.failureCode)"

# =======================================================================================
# 7) REVIEWERS MISSING invokeArgs -> FAILURE
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = '[{"backend":"opencode"}]'
    TempDir        = $ledgerRoot
}
Assert-True ($r.json.success -eq $false) 'missing-invokeargs: success=false'
Assert-True ($r.json.failureCode -eq 'reviewer-missing-invokeArgs') "missing-invokeargs: reviewer-missing-invokeArgs; got $($r.json.failureCode)"

# =======================================================================================
# 8) REVIEWERS WITH A NON-OBJECT invokeArgs -> FAILURE
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = '[{"backend":"opencode","invokeArgs":"not-an-object"}]'
    TempDir        = $ledgerRoot
}
Assert-True ($r.json.success -eq $false) 'invokeargs-not-object: success=false'
Assert-True ($r.json.failureCode -eq 'reviewer-invalid-invokeArgs') "invokeargs-not-object: reviewer-invalid-invokeArgs; got $($r.json.failureCode)"

# =======================================================================================
# 9) UNSAFE ROUNDID -> FAILURE
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
    RoundId        = 'bad$round!'
}
Assert-True ($r.json.success -eq $false) 'unsafe-roundid: success=false'
Assert-True ($r.json.failureCode -eq 'roundId-unsafe-chars') "unsafe-roundid: roundId-unsafe-chars; got $($r.json.failureCode)"

$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
    RoundId        = '../escape'
}
Assert-True ($r.json.success -eq $false) 'roundid-traversal: success=false'
Assert-True ($r.json.failureCode -eq 'roundId-unsafe-chars') "roundid-traversal: roundId-unsafe-chars; got $($r.json.failureCode)"

$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
    RoundId        = 'a\b'
}
Assert-True ($r.json.success -eq $false) 'roundid-backslash: success=false'
Assert-True ($r.json.failureCode -eq 'roundId-unsafe-chars') "roundid-backslash: roundId-unsafe-chars; got $($r.json.failureCode)"

# =======================================================================================
# 10) COLLISION WITH AN EXISTING FINAL DIRECTORY -> FAILURE
# =======================================================================================
$collisionRid = 'collision-' + [guid]::NewGuid().ToString('N')
$collisionDir = Join-Path $ledgerRoot $collisionRid
[System.IO.Directory]::CreateDirectory($collisionDir) | Out-Null

$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
    RoundId        = $collisionRid
}
Assert-True ($r.json.success -eq $false) 'collision: success=false'
Assert-True ($r.json.failureCode -eq 'final-dir-exists') "collision: final-dir-exists; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'collision: exit 1'

Remove-Item -LiteralPath $collisionDir -Recurse -Force -ErrorAction SilentlyContinue

# =======================================================================================
# 11) INJECTED afterManuscript FAILURE -> NO FINAL DIRECTORY, CLEAN STAGING
# =======================================================================================
$failRid = 'fail-am-' + [guid]::NewGuid().ToString('N')
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
    RoundId        = $failRid
    FailAt         = 'afterManuscript'
}
Assert-True ($r.json.success -eq $false) 'afterManuscript: success=false'
Assert-True ($r.json.failureCode -eq 'injected-failure') "afterManuscript: injected-failure; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'afterManuscript: exit 1'

# Final directory must NOT exist
$finalAfterAM = Join-Path $ledgerRoot $failRid
Assert-True (-not (Test-Path -LiteralPath $finalAfterAM -PathType Container)) 'afterManuscript: final directory does NOT exist'

# No .prepare-* staging should remain
$stagingLeftovers = @(Get-ChildItem -LiteralPath $ledgerRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.prepare-*' })
Assert-True ($stagingLeftovers.Count -eq 0) "afterManuscript: no leftover staging; found=$($stagingLeftovers.Count)"

# =======================================================================================
# 12) INJECTED beforePublish FAILURE -> NO FINAL DIRECTORY, CLEAN STAGING
# =======================================================================================
$failRid = 'fail-bp-' + [guid]::NewGuid().ToString('N')
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
    RoundId        = $failRid
    FailAt         = 'beforePublish'
}
Assert-True ($r.json.success -eq $false) 'beforePublish: success=false'
Assert-True ($r.json.failureCode -eq 'injected-failure') "beforePublish: injected-failure; got $($r.json.failureCode)"
Assert-True ($r.exit -eq 1) 'beforePublish: exit 1'

$finalAfterBP = Join-Path $ledgerRoot $failRid
Assert-True (-not (Test-Path -LiteralPath $finalAfterBP -PathType Container)) 'beforePublish: final directory does NOT exist'

$stagingLeftovers = @(Get-ChildItem -LiteralPath $ledgerRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.prepare-*' })
Assert-True ($stagingLeftovers.Count -eq 0) "beforePublish: no leftover staging; found=$($stagingLeftovers.Count)"

# =======================================================================================
# 13) PROOF THAT THE PREPARER DOES NOT CALL THE DISPATCHER OR THE ADAPTERS
# =======================================================================================
# Statically checks that the script does not reference the adapters or the dispatcher
$preparerText = Get-Content -LiteralPath $preparer -Raw -Encoding utf8
Assert-True ($preparerText -notmatch 'Invoke-OpenCode') 'does not call adapters: no Invoke-OpenCode'
Assert-True ($preparerText -notmatch 'Invoke-Codex') 'does not call adapters: no Invoke-Codex'
Assert-True ($preparerText -notmatch 'Invoke-ClaudeCode') 'does not call adapters: no Invoke-ClaudeCode'
Assert-True ($preparerText -notmatch 'Invoke-Copilot') 'does not call adapters: no Invoke-Copilot'
Assert-True ($preparerText -notmatch 'Invoke-Gemini') 'does not call adapters: no Invoke-Gemini'
Assert-True ($preparerText -notmatch '& .*Invoke-LlmDelegatePanelDispatch') 'does not call dispatcher: no call to PanelDispatch'

# =======================================================================================
# 14) DEFAULT ROUNDID (guid when omitted)
# =======================================================================================
$r = Invoke-Preparer -ArgsHashtable @{
    ManuscriptText = $manuscriptPt
    ReviewersJson  = $reviewersValid
    TempDir        = $ledgerRoot
} -NoRoundId
Assert-True ($r.json.roundId -match '^[0-9a-f]{32}$') "RoundId default: should generate guid 'N'; got '$($r.json.roundId)'"

Write-Output 'OK: Test-NewLlmDelegatePeerReviewArtifactsSelfTest.ps1'
