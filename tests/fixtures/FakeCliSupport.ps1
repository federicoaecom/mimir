#requires -Version 7.4
<#
.SYNOPSIS
    Shared helper for self-tests that need a fake command-line tool.
.DESCRIPTION
    New-FakeCli writes the fake's behavior as a PowerShell script (<Name>.body.ps1) plus a launcher
    the adapters can start as a native executable:
      - Windows: <Name>.cmd, which runs `pwsh -File <Name>.body.ps1 %*` and propagates its exit code.
      - Elsewhere: an extensionless `#!/bin/sh` file <Name> with the exec bit set, which
        `exec`s `pwsh -File <Name>.body.ps1 "$@"`.
    The Unix launcher has no `.ps1` extension on purpose: invoking a `.ps1` with `&` would run it
    inside the calling session instead of as a child process. The body is not named <Name>.ps1
    for the same reason: a PATH lookup of <Name> (Get-Command) must find only the launcher.
    Stdin, stdout, stderr and the exit code pass through on both systems, and each argument
    reaches the body's $args as one element even when it contains spaces.
    Dot-source this file; it defines functions only and sets no strict mode or preference
    variables, so the calling test keeps its own settings.
#>

function New-FakeCli {
    <#
        Writes <Directory>/<Name>.body.ps1 with -PwshBody and a launcher next to it; returns the
        launcher's full path (the value to pass as an adapter's -...Exe override or to put on
        PATH). The directory is created when missing. The body reads its arguments from $args.
    #>
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $PwshBody
    )

    [System.IO.Directory]::CreateDirectory($Directory) | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    $bodyPath = Join-Path $Directory ($Name + '.body.ps1')
    [System.IO.File]::WriteAllText($bodyPath, (($PwshBody -replace "`r`n", "`n").TrimEnd("`n") + "`n"), $utf8NoBom)

    if ($IsWindows) {
        $launcherPath = Join-Path $Directory ($Name + '.cmd')
        $lines = @(
            '@echo off'
            ('pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0{0}.body.ps1" %*' -f $Name)
            'exit /b %errorlevel%'
        )
        [System.IO.File]::WriteAllText($launcherPath, (($lines -join "`r`n") + "`r`n"), $utf8NoBom)
    }
    else {
        $launcherPath = Join-Path $Directory $Name
        $lines = @(
            '#!/bin/sh'
            ('exec pwsh -NoProfile -NonInteractive -File "$(dirname -- "$0")/{0}.body.ps1" "$@"' -f $Name)
        )
        [System.IO.File]::WriteAllText($launcherPath, (($lines -join "`n") + "`n"), $utf8NoBom)
        [System.IO.File]::SetUnixFileMode($launcherPath, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
    }

    return $launcherPath
}
