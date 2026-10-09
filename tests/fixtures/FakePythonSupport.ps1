#requires -Version 7.4
<#
.SYNOPSIS
    Shared helpers for self-tests that control which Python a child process finds on PATH.
.DESCRIPTION
    New-OldPythonFake writes a fake `python3` that reports Python 3.6, to prove that Python
    discovery skips an interpreter older than 3.8.
    New-PwshOnlyPathDirectory writes a folder that holds only a `pwsh` launcher for the running
    pwsh, to use as the whole PATH of a child that must find no Python. The pwsh install folder is
    not used for this on purpose: it can be a shared `bin` that also holds a Python.
    Invoke-PwshScriptWithExactPath runs a script in a child pwsh whose PATH is exactly the given
    value. Setting PATH before starting pwsh is not enough, because pwsh puts its own install
    folder ($PSHOME) in front of PATH at startup.
    Dot-source this file; it defines functions only and sets no strict mode or preference
    variables, so the calling test keeps its own settings.
#>

function New-OldPythonFake {
    <#
        Writes a fake `python3` into -Directory (created when missing) and returns its full path.
        The fake prints `Python 3.6.15` on `--version` and exits 0; on any other call it writes
        -MarkerPath and exits 0, as a real 3.6 would for a major-version check, so the marker
        proves a caller ran it beyond the version probe. A `.cmd` file on Windows, an executable
        `#!/bin/sh` script elsewhere.
    #>
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [string] $MarkerPath
    )

    [System.IO.Directory]::CreateDirectory($Directory) | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if ($IsWindows) {
        $path = Join-Path $Directory 'python3.cmd'
        $lines = @(
            '@echo off'
            'if "%~1"=="--version" (echo Python 3.6.15& exit /b 0)'
            ('echo ran> "{0}"' -f $MarkerPath)
            'exit /b 0'
        )
        [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), $utf8NoBom)
    } else {
        $path = Join-Path $Directory 'python3'
        $lines = @(
            '#!/bin/sh'
            'if [ "$1" = "--version" ]; then echo "Python 3.6.15"; exit 0; fi'
            ('echo ran > "{0}"' -f $MarkerPath)
            'exit 0'
        )
        [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), $utf8NoBom)
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
    }
    return $path
}

function New-PwshOnlyPathDirectory {
    <#
        Creates -Directory (it should be new and empty) holding only a `pwsh` launcher for the
        running pwsh, and returns the directory's full path, to set as the whole PATH of a child
        process. On Windows the launcher is `pwsh.cmd`, which runs the running `pwsh.exe` and
        propagates its exit code; elsewhere it is a symbolic link `pwsh` to the running pwsh.
    #>
    param(
        [Parameter(Mandatory)] [string] $Directory
    )

    [System.IO.Directory]::CreateDirectory($Directory) | Out-Null
    $pwshPath = (Get-Process -Id $PID).Path
    if ($IsWindows) {
        $lines = @(
            '@echo off'
            ('"{0}" %*' -f $pwshPath.Replace('%', '%%'))
            'exit /b %ERRORLEVEL%'
        )
        [System.IO.File]::WriteAllText((Join-Path $Directory 'pwsh.cmd'), (($lines -join "`r`n") + "`r`n"), [System.Text.UTF8Encoding]::new($false))
    } else {
        New-Item -ItemType SymbolicLink -Path (Join-Path $Directory 'pwsh') -Target $pwshPath | Out-Null
    }
    return (Resolve-Path -LiteralPath $Directory).Path
}

function Invoke-PwshScriptWithExactPath {
    <#
        Runs -ScriptPath with the named -Parameters in a child of the running pwsh whose PATH is
        exactly -PathValue, and returns the child's output; $LASTEXITCODE holds its exit code.
        The child sets PATH first and then runs the script in its own session, because pwsh puts
        $PSHOME in front of PATH at startup. Parameter values are passed as single-quoted string
        literals; a [bool] value is passed as $true or $false (use $true for a switch).
    #>
    param(
        [Parameter(Mandatory)] [string] $PathValue,
        [Parameter(Mandatory)] [string] $ScriptPath,
        [hashtable] $Parameters = @{}
    )

    $quote = { param([string]$Value) "'" + $Value.Replace("'", "''") + "'" }
    $entries = foreach ($name in $Parameters.Keys) {
        $value = $Parameters[$name]
        if ($value -is [bool]) {
            '{0} = ${1}' -f $name, $value.ToString().ToLowerInvariant()
        } else {
            '{0} = {1}' -f $name, (& $quote ([string]$value))
        }
    }
    $command = '$env:PATH = {0}; $scriptParameters = @{{ {1} }}; & {2} @scriptParameters; exit $LASTEXITCODE' -f (& $quote $PathValue), (@($entries) -join '; '), (& $quote $ScriptPath)
    & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command
}
