#requires -Version 7.4
<#
.SYNOPSIS
    Transactionally prepares the artifacts for a peer-review round: receives the
    manuscript content and the reviewer list, validates structure/safety,
    and publishes the artifacts into a stable directory under <TempDir>\<RoundId>.
.DESCRIPTION
    Part of the mimir-delegate skill mechanism; consumed by Invoke-LlmDelegatePanelDispatch.ps1
    when the orchestrator passes -ManuscriptText instead of -ManuscriptPath.

    Preparation is TRANSACTIONAL: it creates a temporary staging area (.prepare-<guid>), validates
    everything (non-empty manuscript, non-empty reviewers JSON array with at least backend+invokeArgs,
    absence of a BOM, strict UTF-8 re-read, SHA256 hashes), and only publishes the final directory
    (<TempDir>\<RoundId>) via rename/move after complete validation. On failure, it cleans up the
    staging area and leaves no final directory.

    THIS SCRIPT DOES NOT CALL THE DISPATCHER OR ADAPTERS. It is purely a file preparer.
    Invoking the dispatcher is the next step, done by the caller.

    stdout discipline: exactly one JSON line (Kind/SchemaVersion PascalCase).
    Human-readable text goes to [Console]::Error.
.PARAMETER ManuscriptText
    Manuscript text (UTF-8). Mutually exclusive with -ManuscriptPath. For a large payload,
    use -ManuscriptPath to avoid Windows' command-line length limit.
.PARAMETER ManuscriptPath
    Path to the manuscript (UTF-8). Mutually exclusive with -ManuscriptText.
.PARAMETER ReviewersJson
    JSON array [{backend, targetModelKey, invokeArgs, family?, rank?, fallbackChain?}] inline OR a file path.
    Minimal validation: non-empty array; each item must have backend and invokeArgs.
.PARAMETER RoundId
    Round identifier (final staging subfolder). Default: [guid]::NewGuid().ToString('N').
    Validated as safe: letters, digits, dot, hyphen and underscore; no path traversal.
.PARAMETER TempDir
    Staging root. Default: <system temp>\mimir-panel-dispatch.
    The final staging area lives at <TempDir>\<RoundId>\.
.PARAMETER FailAt
    (TEST ONLY) Injects a controlled failure: afterManuscript | beforePublish.
    afterManuscript: fails after writing manuscript.md, before publishing.
    beforePublish: fails after writing all artifacts, before the final rename.
.EXAMPLE
    .\New-LlmDelegatePeerReviewArtifacts.ps1 -ManuscriptText "# Plan review" -ReviewersJson '[{"backend":"opencode","invokeArgs":{}}]' -RoundId rodada-001
#>
[CmdletBinding()]
param(
    [AllowEmptyString()] [string] $ManuscriptText,
    [string] $ManuscriptPath,
    [Parameter(Mandatory)] [string] $ReviewersJson,
    [string] $RoundId,
    [string] $TempDir,
    [ValidateSet('afterManuscript', 'beforePublish')] [string] $FailAt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8StrictNoBom = [System.Text.UTF8Encoding]::new($false, $true)
$MaxInlineManuscriptChars = 30000

# ---------------------------------------------------------------------------------------
# 1) Mutually-exclusive parameter validation
# ---------------------------------------------------------------------------------------
$useInline = $PSBoundParameters.ContainsKey('ManuscriptText')
$useFile = $PSBoundParameters.ContainsKey('ManuscriptPath')
if (-not ($useInline -xor $useFile)) {
    $missingSource = (-not $useInline -and -not $useFile)
    $failureCode = if ($missingSource) { 'manuscript-source-missing' } else { 'manuscript-source-ambiguous' }
    $message = if ($missingSource) {
        'Provide one of -ManuscriptText or -ManuscriptPath.'
    } else {
        'Provide exactly one of -ManuscriptText or -ManuscriptPath.'
    }
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $null
        failureStage      = 'parameter-validation'
        failureCode       = $failureCode
        message           = $message
        cleanup           = 'nada a limpar'
    }
    [Console]::Error.WriteLine("BLOCK: ${failureCode}: $message")
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}
if ($useInline -and $ManuscriptText.Length -gt $MaxInlineManuscriptChars) {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $null
        failureStage      = 'parameter-validation'
        failureCode       = 'manuscript-text-too-large'
        message           = "-ManuscriptText exceeds $MaxInlineManuscriptChars characters; use -ManuscriptPath for a large payload."
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine("BLOCK: manuscript-text-too-large: -ManuscriptText exceeds $MaxInlineManuscriptChars characters; use -ManuscriptPath.")
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

# ---------------------------------------------------------------------------------------
# 2) Resolve the manuscript (in-memory text)
# ---------------------------------------------------------------------------------------
$manuscriptContent = $null
$manuscriptSource = $null
if ($useInline) {
    $manuscriptContent = $ManuscriptText
    $manuscriptSource = 'inline'
} else {
    if (-not (Test-Path -LiteralPath $ManuscriptPath -PathType Leaf)) {
        $result = [ordered]@{
            Kind              = 'mimir-peer-review-artifacts-result'
            SchemaVersion     = 1
            success           = $false
            roundStarted      = $false
            dispatchStarted   = $false
            reviewersDispatched = 0
            roundId           = $null
            failureStage      = 'parameter-validation'
            failureCode       = 'manuscript-path-not-found'
            message           = "-ManuscriptPath not found: $ManuscriptPath"
            cleanup           = 'nothing to clean up'
        }
        [Console]::Error.WriteLine("BLOCK: manuscript-path-not-found: -ManuscriptPath not found: $ManuscriptPath")
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 1
    }
    try {
        $manuscriptContent = [System.IO.File]::ReadAllText($ManuscriptPath, $utf8StrictNoBom)
    } catch {
        $result = [ordered]@{
            Kind              = 'mimir-peer-review-artifacts-result'
            SchemaVersion     = 1
            success           = $false
            roundStarted      = $false
            dispatchStarted   = $false
            reviewersDispatched = 0
            roundId           = $null
            failureStage      = 'manuscript-validation'
            failureCode       = 'manuscript-utf8-invalid'
            message           = "Manuscript is not valid UTF-8: $($_.Exception.Message)"
            cleanup           = 'nothing to clean up'
        }
        [Console]::Error.WriteLine("BLOCK: manuscript-utf8-invalid: $($_.Exception.Message)")
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 1
    }
    $manuscriptSource = 'file'
}

# ---------------------------------------------------------------------------------------
# 3) Validate that the manuscript is non-empty (after trim)
# ---------------------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($manuscriptContent)) {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $null
        failureStage      = 'manuscript-validation'
        failureCode       = 'manuscript-empty'
        message           = 'Manuscript is empty or whitespace only.'
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine('BLOCK: manuscript-empty: manuscript is empty or whitespace only.')
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

# ---------------------------------------------------------------------------------------
# 4) Resolve RoundId
# ---------------------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($RoundId)) {
    $RoundId = [guid]::NewGuid().ToString('N')
}

# Validate that RoundId is safe
if ($RoundId -match '[^A-Za-z0-9._-]') {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $RoundId
        failureStage      = 'roundId-validation'
        failureCode       = 'roundId-unsafe-chars'
        message           = "RoundId contains unsafe characters: '$RoundId'. Use only letters, digits, dot, hyphen and underscore."
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine("BLOCK: roundId-unsafe-chars: '$RoundId' contains unsafe characters.")
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

# Path traversal check
if ($RoundId -match '\.\.' -or $RoundId -match '[/\\]') {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $RoundId
        failureStage      = 'roundId-validation'
        failureCode       = 'roundId-path-traversal'
        message           = "RoundId has path traversal detected: '$RoundId'."
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine("BLOCK: roundId-path-traversal: '$RoundId'.")
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

# ---------------------------------------------------------------------------------------
# 5) Resolve TempDir and paths
# ---------------------------------------------------------------------------------------
$tempRoot = $TempDir
if ([string]::IsNullOrWhiteSpace($tempRoot)) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'mimir-panel-dispatch'
}

$finalDir = Join-Path $tempRoot $RoundId

# Collision with an existing final directory -> failure
if (Test-Path -LiteralPath $finalDir -PathType Container) {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $RoundId
        failureStage      = 'staging-collision'
        failureCode       = 'final-dir-exists'
        message           = "Final directory already exists: $finalDir. Not overwriting."
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine("BLOCK: final-dir-exists: '$finalDir' already exists.")
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

# ---------------------------------------------------------------------------------------
# 6) Validate ReviewersJson (minimum: non-empty array, each item with backend + invokeArgs)
# ---------------------------------------------------------------------------------------
$reviewersRaw = $null
if (Test-Path -LiteralPath $ReviewersJson -PathType Leaf) {
    try {
        $reviewersRaw = [System.IO.File]::ReadAllText($ReviewersJson, $utf8StrictNoBom)
    } catch {
        $result = [ordered]@{
            Kind              = 'mimir-peer-review-artifacts-result'
            SchemaVersion     = 1
            success           = $false
            roundStarted      = $false
            dispatchStarted   = $false
            reviewersDispatched = 0
            roundId           = $RoundId
            failureStage      = 'reviewers-validation'
            failureCode       = 'reviewers-utf8-invalid'
            message           = "ReviewersJson is not valid UTF-8: $($_.Exception.Message)"
            cleanup           = 'nothing to clean up'
        }
        [Console]::Error.WriteLine("BLOCK: reviewers-utf8-invalid: $($_.Exception.Message)")
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 1
    }
} else {
    $reviewersRaw = $ReviewersJson
}

$reviewersParsed = $null
try {
    $reviewersParsed = $reviewersRaw | ConvertFrom-Json -NoEnumerate
} catch {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $RoundId
        failureStage      = 'reviewers-validation'
        failureCode       = 'reviewers-json-invalid'
        message           = "ReviewersJson is not valid JSON: $($_.Exception.Message)"
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine("BLOCK: reviewers-json-invalid: $($_.Exception.Message)")
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

$reviewersIsArray = $reviewersParsed -is [System.Array]
if (-not $reviewersIsArray) {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $RoundId
        failureStage      = 'reviewers-validation'
        failureCode       = 'reviewers-root-not-array'
        message           = 'ReviewersJson must have a JSON array root.'
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine('BLOCK: reviewers-root-not-array.')
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

$reviewers = @($reviewersParsed)
if ($reviewers.Count -eq 0) {
    $result = [ordered]@{
        Kind              = 'mimir-peer-review-artifacts-result'
        SchemaVersion     = 1
        success           = $false
        roundStarted      = $false
        dispatchStarted   = $false
        reviewersDispatched = 0
        roundId           = $RoundId
        failureStage      = 'reviewers-validation'
        failureCode       = 'reviewers-empty'
        message           = 'ReviewersJson is an empty array.'
        cleanup           = 'nothing to clean up'
    }
    [Console]::Error.WriteLine('BLOCK: reviewers-empty.')
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}

for ($i = 0; $i -lt $reviewers.Count; $i++) {
    $r = $reviewers[$i]
    $backend = $null
    if ($null -ne $r -and $r.PSObject.Properties['backend']) {
        $backend = [string]$r.backend
    }
    $invokeArgs = $null
    if ($null -ne $r -and $r.PSObject.Properties['invokeArgs']) {
        $invokeArgs = $r.invokeArgs
    }
    if ([string]::IsNullOrWhiteSpace($backend)) {
        $result = [ordered]@{
            Kind              = 'mimir-peer-review-artifacts-result'
            SchemaVersion     = 1
            success           = $false
            roundStarted      = $false
            dispatchStarted   = $false
            reviewersDispatched = 0
            roundId           = $RoundId
            failureStage      = 'reviewers-validation'
            failureCode       = 'reviewer-missing-backend'
            message           = "Reviewer [$i]: 'backend' field missing or empty."
            cleanup           = 'nothing to clean up'
        }
        [Console]::Error.WriteLine("BLOCK: reviewer-missing-backend: reviewer [$i].")
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 1
    }
    if ($null -eq $invokeArgs) {
        $result = [ordered]@{
            Kind              = 'mimir-peer-review-artifacts-result'
            SchemaVersion     = 1
            success           = $false
            roundStarted      = $false
            dispatchStarted   = $false
            reviewersDispatched = 0
            roundId           = $RoundId
            failureStage      = 'reviewers-validation'
            failureCode       = 'reviewer-missing-invokeArgs'
            message           = "Reviewer [$i]: 'invokeArgs' field missing."
            cleanup           = 'nothing to clean up'
        }
        [Console]::Error.WriteLine("BLOCK: reviewer-missing-invokeArgs: reviewer [$i].")
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 1
    }
    if ($invokeArgs -isnot [pscustomobject]) {
        $result = [ordered]@{
            Kind              = 'mimir-peer-review-artifacts-result'
            SchemaVersion     = 1
            success           = $false
            roundStarted      = $false
            dispatchStarted   = $false
            reviewersDispatched = 0
            roundId           = $RoundId
            failureStage      = 'reviewers-validation'
            failureCode       = 'reviewer-invalid-invokeArgs'
            message           = "Reviewer [$i]: 'invokeArgs' field must be a JSON object."
            cleanup           = 'nothing to clean up'
        }
        [Console]::Error.WriteLine("BLOCK: reviewer-invalid-invokeArgs: reviewer [$i].")
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 1
    }
}

# ---------------------------------------------------------------------------------------
# 7) Create transactional staging
# ---------------------------------------------------------------------------------------
$stagingGuid = [guid]::NewGuid().ToString('N')
$stagingDir = Join-Path $tempRoot ".prepare-$stagingGuid"
try {
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    $cleanStage = $true

    try {
        # -------------------------------------------------------------------------------
        # 7a) Write manuscript.md (UTF-8 without BOM)
        # -------------------------------------------------------------------------------
        $manuscriptPath = Join-Path $stagingDir 'manuscript.md'
        [System.IO.File]::WriteAllText($manuscriptPath, $manuscriptContent, $utf8NoBom)

        # Verify no BOM is present
        $bomBytes = [System.IO.File]::ReadAllBytes($manuscriptPath)
        if ($bomBytes.Length -ge 3 -and $bomBytes[0] -eq 0xEF -and $bomBytes[1] -eq 0xBB -and $bomBytes[2] -eq 0xBF) {
            throw "UTF-8 BOM detected after writing manuscript.md"
        }

        # Strict UTF-8 re-read
        $reRead = [System.IO.File]::ReadAllText($manuscriptPath, $utf8StrictNoBom)
        if ($reRead -ne $manuscriptContent) {
            throw "Mismatch re-reading manuscript.md (round-trip)"
        }

        $manuscriptHash = (Get-FileHash -LiteralPath $manuscriptPath -Algorithm SHA256).Hash
        $manuscriptSize = $bomBytes.Length

        # -------------------------------------------------------------------------------
        # 7b) Write reviewers.json (UTF-8 without BOM, pretty for readability)
        # -------------------------------------------------------------------------------
        $reviewersJsonOut = Join-Path $stagingDir 'reviewers.json'
        $reviewersPretty = ($reviewers | ConvertTo-Json -Depth 8 -AsArray)
        [System.IO.File]::WriteAllText($reviewersJsonOut, $reviewersPretty, $utf8NoBom)

        $reviewersBytes = [System.IO.File]::ReadAllBytes($reviewersJsonOut)
        if ($reviewersBytes.Length -ge 3 -and $reviewersBytes[0] -eq 0xEF -and $reviewersBytes[1] -eq 0xBB -and $reviewersBytes[2] -eq 0xBF) {
            throw "UTF-8 BOM detected after writing reviewers.json"
        }
        $reviewersReRead = [System.IO.File]::ReadAllText($reviewersJsonOut, $utf8StrictNoBom)
        if ($reviewersReRead -ne $reviewersPretty) {
            throw "Mismatch re-reading reviewers.json (round-trip)"
        }

        $reviewersHash = (Get-FileHash -LiteralPath $reviewersJsonOut -Algorithm SHA256).Hash
        $reviewersSize = $reviewersBytes.Length

        # -------------------------------------------------------------------------------
        # 7c) Inject a failure (test only) after writing the manuscript
        # -------------------------------------------------------------------------------
        if ($FailAt -eq 'afterManuscript') {
            throw "INJECTED FAILURE (afterManuscript): staging must not be published."
        }

        # -------------------------------------------------------------------------------
        # 7d) Assemble and write preparation-manifest.json
        # -------------------------------------------------------------------------------
        $createdAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $manifestObj = [ordered]@{
            Kind          = 'mimir-peer-review-artifacts-manifest'
            SchemaVersion = 1
            roundId       = $RoundId
            createdAt     = $createdAt
            encoding      = 'utf-8-no-bom'
            manuscriptSource = $manuscriptSource
            artifacts     = [ordered]@{
                manuscript = [ordered]@{
                    filename = 'manuscript.md'
                    sha256   = $manuscriptHash
                    size     = $manuscriptSize
                }
                reviewers  = [ordered]@{
                    filename = 'reviewers.json'
                    sha256   = $reviewersHash
                    size     = $reviewersSize
                }
            }
            reviewerCount = $reviewers.Count
        }
        $manifestPath = Join-Path $stagingDir 'preparation-manifest.json'
        $manifestJson = ($manifestObj | ConvertTo-Json -Compress -Depth 6)
        [System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8NoBom)

        # -------------------------------------------------------------------------------
        # 7e) Inject a failure (test only) before publishing
        # -------------------------------------------------------------------------------
        if ($FailAt -eq 'beforePublish') {
            throw "INJECTED FAILURE (beforePublish): staging must not be published."
        }

        # -------------------------------------------------------------------------------
        # 7f) Publish: atomic rename from staging -> final
        # -------------------------------------------------------------------------------
        [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
        [System.IO.Directory]::Move($stagingDir, $finalDir)
        $cleanStage = $false

        # -------------------------------------------------------------------------------
        # 8) Success: emit the result
        # -------------------------------------------------------------------------------
        $result = [ordered]@{
            Kind                = 'mimir-peer-review-artifacts-result'
            SchemaVersion       = 1
            success             = $true
            roundStarted        = $false
            dispatchStarted     = $false
            reviewersDispatched = 0
            roundId             = $RoundId
            artifactPaths       = [ordered]@{
                manuscript = Join-Path $finalDir 'manuscript.md'
                reviewers  = Join-Path $finalDir 'reviewers.json'
                manifest   = Join-Path $finalDir 'preparation-manifest.json'
            }
            hashes = [ordered]@{
                manuscript = $manuscriptHash
                reviewers  = $reviewersHash
            }
            encoding     = 'utf-8-no-bom'
            cleanup      = 'staging published successfully'
        }
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 0
    } catch {
        # Clean up staging on failure
        if ($cleanStage) {
            try { Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        }

        $errMsg = [string]$_.Exception.Message
        $failureCode = 'preparation-error'
        $failureStage = 'artifact-preparation'
        if ($errMsg -match 'INJECTED FAILURE') {
            $failureCode = 'injected-failure'
            $failureStage = 'injected-failure'
        } elseif ($errMsg -match 'BOM') {
            $failureCode = 'bom-detected'
        } elseif ($errMsg -match 'round-trip') {
            $failureCode = 'round-trip-mismatch'
        }

        $result = [ordered]@{
            Kind                = 'mimir-peer-review-artifacts-result'
            SchemaVersion       = 1
            success             = $false
            roundStarted        = $false
            dispatchStarted     = $false
            reviewersDispatched = 0
            roundId             = $RoundId
            failureStage        = $failureStage
            failureCode         = $failureCode
            message             = $errMsg
            cleanup             = 'staging removed'
        }
        [Console]::Error.WriteLine("BLOCK: $failureCode ($failureStage): $errMsg")
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
        exit 1
    }
} catch {
    # Failure creating the staging dir
    $result = [ordered]@{
        Kind                = 'mimir-peer-review-artifacts-result'
        SchemaVersion       = 1
        success             = $false
        roundStarted        = $false
        dispatchStarted     = $false
        reviewersDispatched = 0
        roundId             = $RoundId
        failureStage        = 'staging-creation'
        failureCode         = 'staging-dir-error'
        message             = "Failed to create staging: $($_.Exception.Message)"
        cleanup             = 'nothing to clean up'
    }
    [Console]::Error.WriteLine("BLOCK: staging-dir-error: $($_.Exception.Message)")
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
    exit 1
}
