#requires -Version 7.4
<#
.SYNOPSIS
    Self-test for tests/fixtures/AssertSupport.ps1.
.DESCRIPTION
    Checks that each shared assertion passes and fails as specified, with a stable message, and
    that Invoke-AssertCase and Complete-AssertRun count, report and reset cases. It does not use
    the assertions under test to check themselves.
    Success sentinel: ASSERT_SUPPORT_SELFTEST_OK
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'fixtures/AssertSupport.ps1')

$failures = [System.Collections.Generic.List[string]]::new()

function Get-ThrownMessage {
    param([scriptblock] $Body)
    try { & $Body; return $null }
    catch { return $_.Exception.Message }
}

function Test-Passes {
    param([string] $Case, [scriptblock] $Body)
    $message = Get-ThrownMessage $Body
    if ($null -eq $message) { Write-Host "PASS  $Case" -ForegroundColor Green }
    else { $failures.Add("$Case -> threw '$message'"); Write-Host "FAIL  $Case -> threw '$message'" -ForegroundColor Red }
}

function Test-FailsWith {
    param([string] $Case, [scriptblock] $Body, [string] $ExpectedMessage)
    $message = Get-ThrownMessage $Body
    if ($message -ceq $ExpectedMessage) { Write-Host "PASS  $Case" -ForegroundColor Green }
    else {
        $failures.Add("$Case -> expected '$ExpectedMessage', got '$message'")
        Write-Host "FAIL  $Case -> expected '$ExpectedMessage', got '$message'" -ForegroundColor Red
    }
}

Test-Passes 'Assert-True passes on $true' { Assert-True $true 'flag set' }
Test-FailsWith 'Assert-True fails on $false' { Assert-True $false 'flag set' } 'ASSERT FAILED: flag set'

Test-Passes 'Assert-Equal passes on equal strings' { Assert-Equal 'abc' 'abc' 'name' }
Test-FailsWith 'Assert-Equal is case-sensitive' { Assert-Equal 'abc' 'ABC' 'name' } "ASSERT FAILED: name (expected 'ABC', got 'abc')"
Test-Passes 'Assert-Equal passes on two nulls' { Assert-Equal $null $null 'value' }
Test-FailsWith 'Assert-Equal tells null from empty' { Assert-Equal '' $null 'value' } "ASSERT FAILED: value (expected <null>, got '')"
Test-FailsWith 'Assert-Equal fails on null actual' { Assert-Equal $null 'x' 'value' } "ASSERT FAILED: value (expected 'x', got <null>)"
Test-Passes 'Assert-Equal compares numbers across integer types' { Assert-Equal ([long] 2) ([int] 2) 'count' }
Test-FailsWith 'Assert-Equal rejects a collection' { Assert-Equal @('a', 'b') 'a' 'items' } 'Assert-Equal compares single values, not collections: items'

Test-Passes 'Assert-Match passes when the pattern matches' { Assert-Match 'exit code 0' 'code \d' 'output' }
Test-FailsWith 'Assert-Match is case-sensitive' { Assert-Match 'abc' 'B' 'output' } "ASSERT FAILED: output (pattern 'B' not found in 'abc')"
Test-FailsWith 'Assert-Match fails on null text' { Assert-Match $null 'a' 'output' } "ASSERT FAILED: output (pattern 'a' not found in <null>)"
Test-Passes 'Assert-NotMatch passes when the pattern is absent' { Assert-NotMatch 'abc' 'x' 'output' }
Test-Passes 'Assert-NotMatch passes on null text' { Assert-NotMatch $null 'a' 'output' }
Test-FailsWith 'Assert-NotMatch fails when the pattern matches' { Assert-NotMatch 'abc' 'b' 'output' } "ASSERT FAILED: output (pattern 'b' found in 'abc')"

Test-Passes 'Assert-Contains passes on a literal substring' { Assert-Contains 'a.b[c]' '.b[' 'text' }
Test-FailsWith 'Assert-Contains is ordinal' { Assert-Contains 'abc' 'B' 'text' } "ASSERT FAILED: text ('B' not found in 'abc')"
Test-FailsWith 'Assert-Contains fails on null text' { Assert-Contains $null 'a' 'text' } "ASSERT FAILED: text ('a' not found in <null>)"

$passOutput = @(Invoke-AssertCase 'passing case' { Assert-True $true 'ok' } 6>&1 | ForEach-Object { [string] $_ })
$failOutput = @(Invoke-AssertCase 'failing case' { Assert-Equal 1 2 'number' } 6>&1 | ForEach-Object { [string] $_ })
$errorOutput = @(Invoke-AssertCase 'erroring case' { throw 'boom' } 6>&1 | ForEach-Object { [string] $_ })
if (($passOutput -join '|') -ceq 'PASS  passing case') { Write-Host 'PASS  Invoke-AssertCase reports a passing case' -ForegroundColor Green }
else { $failures.Add("Invoke-AssertCase pass output: '$($passOutput -join '|')'") }
if (($failOutput -join '|') -ceq "FAIL  failing case: ASSERT FAILED: number (expected '2', got '1')") { Write-Host 'PASS  Invoke-AssertCase reports a failing case and continues' -ForegroundColor Green }
else { $failures.Add("Invoke-AssertCase fail output: '$($failOutput -join '|')'") }
if (($errorOutput -join '|') -ceq 'FAIL  erroring case: boom') { Write-Host 'PASS  Invoke-AssertCase counts any error as a failure' -ForegroundColor Green }
else { $failures.Add("Invoke-AssertCase error output: '$($errorOutput -join '|')'") }

Test-FailsWith 'Complete-AssertRun fails when a case failed' { Complete-AssertRun } 'BLOCK: 2 of 3 case(s) failed'
Test-Passes 'Complete-AssertRun resets its counts' { Complete-AssertRun }
$null = Invoke-AssertCase 'only case' { Assert-True $true 'ok' } 6>&1
Test-Passes 'Complete-AssertRun passes when every case passed' { Complete-AssertRun }

if ($failures.Count -gt 0) { throw "BLOCK: $($failures.Count) case(s) failed in Test-AssertSupportSelfTest.ps1: $($failures -join '; ')" }
Write-Host 'ASSERT_SUPPORT_SELFTEST_OK' -ForegroundColor Cyan
