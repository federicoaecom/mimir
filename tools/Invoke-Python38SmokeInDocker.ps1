#requires -Version 7.4
<#
.SYNOPSIS
    Runs the Python engines on a real Python 3.8, the product's minimum, in a local Docker
    container.
.DESCRIPTION
    tools/Test-PyScriptsParse.ps1 rejects most syntax added after Python 3.8 (best effort: some
    newer constructs still parse), and it cannot see standard-library APIs added after 3.8. This script closes that gap: it runs
    tools/docker/Python38Smoke.py (index build from tests/fixtures/sample-kb, a fixed set of
    queries, and every tests/**/Test*.py) inside the official python:3.8-slim image.
    The repository is mounted read-only and the run uses the working tree as it is, including
    uncommitted changes; nothing is written to the repository.
    Needs Docker (Docker Desktop on Windows) running.
    Exit code: the smoke run's exit code (0 when every step passed, 1 otherwise); 2 when the
    docker command is missing; otherwise Docker's own code (for example 125 when the Docker
    daemon is not running).
.PARAMETER Image
    Image to run. Default: python:3.8-slim.
#>
[CmdletBinding()]
param(
    [string]$Image = 'python:3.8-slim'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Output 'Docker was not found. Install and start Docker (Docker Desktop on Windows), then run this script again.'
    exit 2
}

& docker run --rm --volume "${repoRoot}:/src:ro" --env PYTHONDONTWRITEBYTECODE=1 $Image `
    python -B /src/tools/docker/Python38Smoke.py --repo-root /src
exit $LASTEXITCODE
