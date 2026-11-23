<#
.SYNOPSIS
    Shared assertions for PowerShell self-tests. Dot-source it; do not define local Assert-* functions.
.DESCRIPTION
    Every assertion throws on failure with a stable message that starts with "ASSERT FAILED: ".
    A self-test that stops at the first failure calls the assertions directly. A self-test that
    reports every case wraps each one in Invoke-AssertCase and ends with Complete-AssertRun.
    Comparisons are case-sensitive; Assert-Contains is ordinal.
    Self-test: tests/Test-AssertSupportSelfTest.ps1
#>

$script:AssertSupportCases = 0
$script:AssertSupportFailures = 0

function Format-AssertValue {
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return '<null>' }
    return "'$Value'"
}

function Assert-True {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Assert-Equal {
    param([AllowNull()] $Actual, [AllowNull()] $Expected, [string] $Message)
    foreach ($value in @($Actual, $Expected)) {
        if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            throw [System.ArgumentException]::new("Assert-Equal compares single values, not collections: $Message")
        }
    }
    $equal = if ($null -eq $Expected -or $null -eq $Actual) { $null -eq $Expected -and $null -eq $Actual }
    else { $Expected -ceq $Actual }
    if (-not $equal) {
        throw ("ASSERT FAILED: {0} (expected {1}, got {2})" -f $Message, (Format-AssertValue $Expected), (Format-AssertValue $Actual))
    }
}

function Assert-Match {
    param([AllowNull()] $Text, [string] $Pattern, [string] $Message)
    if ($null -eq $Text -or [string] $Text -cnotmatch $Pattern) {
        throw ("ASSERT FAILED: {0} (pattern '{1}' not found in {2})" -f $Message, $Pattern, (Format-AssertValue $Text))
    }
}

function Assert-NotMatch {
    param([AllowNull()] $Text, [string] $Pattern, [string] $Message)
    if ($null -ne $Text -and [string] $Text -cmatch $Pattern) {
        throw ("ASSERT FAILED: {0} (pattern '{1}' found in {2})" -f $Message, $Pattern, (Format-AssertValue $Text))
    }
}

function Assert-Contains {
    param([AllowNull()] $Text, [string] $Substring, [string] $Message)
    if ($null -eq $Text -or -not ([string] $Text).Contains($Substring, [System.StringComparison]::Ordinal)) {
        throw ("ASSERT FAILED: {0} ('{1}' not found in {2})" -f $Message, $Substring, (Format-AssertValue $Text))
    }
}

function Invoke-AssertCase {
    param([string] $Name, [scriptblock] $Body)
    $script:AssertSupportCases++
    try {
        & $Body
        Write-Host "PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:AssertSupportFailures++
        Write-Host "FAIL  ${Name}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Complete-AssertRun {
    $cases = $script:AssertSupportCases
    $failed = $script:AssertSupportFailures
    $script:AssertSupportCases = 0
    $script:AssertSupportFailures = 0
    if ($failed -gt 0) { throw "BLOCK: $failed of $cases case(s) failed" }
}
