#requires -Version 7.4
Set-StrictMode -Version Latest

# UTF-8-safe git helpers shared by the pre-push mechanical checks.
# Invoke-PrePushGitUtf8 runs git, decodes its output as strict UTF-8 (flagging
# malformed bytes instead of silently replacing them), and returns the lines
# with blank lines preserved so paired `git diff --check` diagnostics stay intact.

function ConvertFrom-PrePushGitOutputText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text.Length -eq 0) { return @() }
    $lines = $Text.Split([char]10)
    if ($Text.EndsWith("`n")) {
        if ($lines.Length -eq 1) { return @() }
        $lines = $lines[0..($lines.Length - 2)]
    }
    return $lines
}

function Invoke-PrePushGitUtf8 {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string[]]$Arguments)
    $info = [Diagnostics.ProcessStartInfo]::new('git')
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    [void]$info.ArgumentList.Add('-C'); [void]$info.ArgumentList.Add($RepositoryRoot)
    foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    $stream = [IO.MemoryStream]::new()
    $process.StandardOutput.BaseStream.CopyTo($stream)
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $bytes = $stream.ToArray()
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $malformedUtf8 = $false
    try { $text = $utf8.GetString($bytes) } catch {
        $malformedUtf8 = $true
        $text = [Text.UTF8Encoding]::new($false, $false).GetString($bytes)
    }
    $lines = @(ConvertFrom-PrePushGitOutputText -Text $text)
    if ($malformedUtf8) { $lines += 'Malformed UTF-8 from git diff --check output.' }
    if ($process.ExitCode -ne 0 -and $stderr.Length -gt 0) { $lines += $stderr.TrimEnd("`r", "`n") }
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Lines = $lines; Text = ($lines -join [Environment]::NewLine) }
}
