#requires -Version 7.4
<#
.SYNOPSIS
    Self-test (behavior lock) for the single source Normalize-FileBaseName.

.DESCRIPTION
    Dot-sources GeneXusFileBaseNameNormalizationSupport.ps1 and locks the output of Normalize-FileBaseName
    against a table of problematic names (invalid filesystem characters, trailing dot, etc.). Since
    Sync-GeneXusXpzToXml.ps1 and (in the future) the legacy export converter dot-source the SAME
    function, this table guarantees identical normalization across both paths (parity) and protects
    against regression in extraction.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$supportScript = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'skills/mimir-lite/scripts') 'GeneXusFileBaseNameNormalizationSupport.ps1'
if (-not (Test-Path -LiteralPath $supportScript -PathType Leaf)) {
    throw "Support script not found: $supportScript"
}
. $supportScript

function Assert-Equal {
    param([string]$Actual, [string]$Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "ASSERT FAILED: $Message (expected='$Expected', got='$Actual')"
    }
}

# Lock cases. '/' '\' ':' '*' '?' '<' '>' '|' '"' are invalid -> '_'; trailing dot -> removed;
# internal dot preserved.
$cases = @(
    @{ In = 'Cliente';        Out = 'Cliente' }
    @{ In = 'a/b';            Out = 'a_b' }
    @{ In = 'a\b';            Out = 'a_b' }
    @{ In = 'a:b*c?d';        Out = 'a_b_c_d' }
    @{ In = 'a<b>c|d';        Out = 'a_b_c_d' }
    @{ In = 'with"quote';     Out = 'with_quote' }
    @{ In = 'report.';        Out = 'report' }
    @{ In = 'ends...';        Out = 'ends' }
    @{ In = 'a.b.c';          Out = 'a.b.c' }
    @{ In = '';               Out = '' }
    # Characters valid in Linux/macOS file names but invalid on Windows: the result must be the
    # Windows one on every OS (control characters included), so the same object gets the same name.
    @{ In = "a`tb";           Out = 'a_b' }
    @{ In = "a$([char]0x1F)b"; Out = 'a_b' }
    @{ In = 'A:b';            Out = 'A_b' }
)

foreach ($case in $cases) {
    $actual = Normalize-FileBaseName -LogicalName $case.In
    Assert-Equal -Actual $actual -Expected $case.Out -Message ("Normalize-FileBaseName('{0}')" -f $case.In)
}

# The invalid set is fixed (the Windows set: control characters 0-31 plus " < > | : * ? \ /),
# never [IO.Path]::GetInvalidFileNameChars(), which is only '/' and NUL on Linux and macOS.
$expectedInvalidCodes = @(34, 60, 62, 124) + (0..31) + @(58, 42, 63, 92, 47)
$invalidSet = Get-GeneXusInvalidFileNameChars
$actualInvalidCodes = @($invalidSet | ForEach-Object { [int]$_ })
Assert-Equal -Actual ($actualInvalidCodes -join ',') -Expected ($expectedInvalidCodes -join ',') -Message 'Get-GeneXusInvalidFileNameChars returns the fixed Windows set'
if ($IsWindows) {
    $windowsCodes = @([System.IO.Path]::GetInvalidFileNameChars() | ForEach-Object { [int]$_ })
    Assert-Equal -Actual ($actualInvalidCodes -join ',') -Expected ($windowsCodes -join ',') -Message 'the fixed set equals the Windows platform set'
}

Write-Output 'OK: Test-GeneXusFileBaseNameNormalizationSelfTest.ps1'
exit 0
