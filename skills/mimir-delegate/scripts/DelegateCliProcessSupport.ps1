#requires -Version 7.4
<#
.SYNOPSIS
    Internal process lifecycle for delegate CLI adapters.
.DESCRIPTION
    Starts one executable with an argument array, closes stdin and captures UTF-8 output
    separately. The deadline includes process exit and both stream drains. On timeout the
    owned process tree is terminated when its root is still alive; if the root already
    exited, descendants holding its streams cannot reliably be identified or terminated.
    In either case stream reads are cancelled rather than waiting indefinitely. No backend
    response, authentication, quota or shell command interpretation is performed.
#>

enum DelegateCliProcessState { Exited; TimedOut; StartFailed }

class DelegateCliProcessResult {
    [DelegateCliProcessState] $State
    [Nullable[int]] $ExitCode
    [string] $Reason = ''
    [string] $Stdout = ''
    [string] $Stderr = ''
}

function Invoke-DelegateCliProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [AllowEmptyCollection()][string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        [ValidateRange(1, 2147483)][int]$TimeoutSeconds = 60
    )

    $result = [DelegateCliProcessResult]::new()
    $process = [Diagnostics.Process]::new()
    $cancel = [Threading.CancellationTokenSource]::new()
    $started = $false
    try {
        $info = $process.StartInfo
        $info.FileName = $Executable
        if ($WorkingDirectory) { $info.WorkingDirectory = $WorkingDirectory }
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.StandardOutputEncoding = [Text.Encoding]::UTF8
        $info.StandardErrorEncoding = [Text.Encoding]::UTF8
        foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
        try {
            $started = $process.Start()
            if (-not $started) { throw 'Process could not be started.' }
        } catch {
            $result.State = [DelegateCliProcessState]::StartFailed
            $result.Reason = $_.Exception.Message
            return $result
        }
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync($cancel.Token)
        $stderr = $process.StandardError.ReadToEndAsync($cancel.Token)
        $exit = $process.WaitForExitAsync($cancel.Token)
        $all = [Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout, $stderr, $exit))
        if ($all.Wait($TimeoutSeconds * 1000)) {
            $result.State = [DelegateCliProcessState]::Exited
            $result.ExitCode = $process.ExitCode
            $result.Stdout = $stdout.Result
            $result.Stderr = $stderr.Result
        } else {
            $result.State = [DelegateCliProcessState]::TimedOut
            $result.Reason = 'Process or output streams exceeded the deadline.'
            if (-not $process.HasExited) {
                try { $process.Kill($true) } catch [InvalidOperationException] { }
            }
            $cancel.Cancel()
            if ($stdout.IsCompletedSuccessfully) { $result.Stdout = $stdout.Result }
            if ($stderr.IsCompletedSuccessfully) { $result.Stderr = $stderr.Result }
        }
        return $result
    } finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true) } catch [InvalidOperationException] { }
        }
        $cancel.Cancel()
        $process.Dispose()
        $cancel.Dispose()
    }
}
