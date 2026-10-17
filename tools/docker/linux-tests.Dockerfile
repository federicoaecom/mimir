# Linux image for running the CI checks locally (tools/Invoke-LinuxTestsInDocker.ps1).
# The official PowerShell 7.4 image on Ubuntu 22.04 (pwsh 7.4.6 or later, the minimum outside
# Windows) plus the Python 3 and git the suite needs, like the ubuntu-latest CI job.
FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 git \
    && rm -rf /var/lib/apt/lists/*
