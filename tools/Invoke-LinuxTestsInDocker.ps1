#requires -Version 7.4
<#
.SYNOPSIS
    Runs the CI checks (tools/Invoke-CiChecks.ps1) on Linux in a local Docker container, so the
    Linux side of CI can be checked without spending hosted-runner minutes.

.DESCRIPTION
    Builds (or reuses) a local image from tools/docker/linux-tests.Dockerfile: the official
    PowerShell 7.4 image on Ubuntu 22.04 plus Python 3 and git. Then it mounts the repository
    read-only, clones it inside the container (so the run sees the committed HEAD with LF line
    endings, as a CI checkout does, and never writes to the repository), and runs
    tools/Invoke-CiChecks.ps1 there. Uncommitted changes are not part of the run; the script
    warns when the working tree has any.

    Needs Docker (Docker Desktop on Windows) running, and a regular clone (from a linked git
    worktree the clone inside the container fails, because its .git file points to a host path).
    The image tag is not pinned to a digest, so a rebuild may pick a newer PowerShell 7.4 patch.
    Exit code: the CI checks' exit code (0 when every step passed, 1 otherwise); 2 when the docker
    command is missing or the image build fails; 3 when the clone inside the container fails;
    otherwise Docker's own code (for example 125 when the Docker daemon is not running).

.PARAMETER Image
    Local image tag to build and run. Default: mimir-lite-linux-tests:pwsh7.4-ubuntu22.04.

.PARAMETER NoBuild
    Run the existing image without rebuilding it (the build is cached by Docker anyway).
#>
[CmdletBinding()]
param(
    [string]$Image = 'mimir-lite-linux-tests:pwsh7.4-ubuntu22.04',
    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dockerDir = Join-Path $PSScriptRoot 'docker'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Output 'Docker was not found. Install and start Docker (Docker Desktop on Windows), then run this script again.'
    exit 2
}

# Without git on the host the warning is skipped; the clone happens inside the container.
$pending = @(if (Get-Command git -ErrorAction SilentlyContinue) { & git -C $repoRoot status --porcelain 2>$null })
if ($pending.Count -gt 0) {
    Write-Output "WARNING: the working tree has $($pending.Count) uncommitted change(s); the container runs the committed HEAD only."
}

if (-not $NoBuild) {
    & docker build --quiet --tag $Image --file (Join-Path $dockerDir 'linux-tests.Dockerfile') $dockerDir | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Docker image build failed (exit $LASTEXITCODE)."
        exit 2
    }
}

# Inside the container: trust the mounted repository, clone it (HEAD, LF endings per
# .gitattributes), stop with exit 3 when the clone fails, and run the CI checks from the clone.
$inner = @(
    "git config --global --add safe.directory '*'",
    'git clone --quiet /src /work',
    "if (`$LASTEXITCODE -ne 0) { Write-Output 'git clone of the repository failed inside the container.'; exit 3 }",
    'Set-Location /work',
    'pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools/Invoke-CiChecks.ps1',
    'exit $LASTEXITCODE'
) -join '; '
& docker run --rm --volume "${repoRoot}:/src:ro" $Image pwsh -NoProfile -NonInteractive -Command $inner
exit $LASTEXITCODE
