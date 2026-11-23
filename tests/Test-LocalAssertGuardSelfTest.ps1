#requires -Version 7.4
<#
.SYNOPSIS
    Keeps new PowerShell tests on the shared assertions in tests/fixtures/AssertSupport.ps1.
.DESCRIPTION
    Finds every .ps1 file under tests/ and tools/ that defines a function whose name starts with
    "Assert" (parsed, so text in strings and comments does not count) and compares the set with
    tests/fixtures/local-assert-baseline.txt, the files that defined one when the shared helper
    was added. A file outside the baseline fails: dot-source AssertSupport.ps1 instead. A
    baseline entry that no longer defines one fails too, so the baseline only shrinks as files
    are migrated when they are touched for another reason.
    Success sentinel: LOCAL_ASSERT_GUARD_SELFTEST_OK
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'fixtures/AssertSupport.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$baselinePath = Join-Path $PSScriptRoot 'fixtures/local-assert-baseline.txt'

function Get-LocalAssertDefinitionFile {
    param([string] $Root)
    $rootPath = (Resolve-Path -LiteralPath $Root).Path
    foreach ($folder in 'tests', 'tools') {
        $folderPath = Join-Path $rootPath $folder
        if (-not (Test-Path -LiteralPath $folderPath)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File -Recurse) {
            $relative = [System.IO.Path]::GetRelativePath($rootPath, $file.FullName).Replace('\', '/')
            if ($relative -ceq 'tests/fixtures/AssertSupport.ps1') { continue }
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $null)
            $definesAssert = $ast.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -like 'Assert*'
                }, $true)
            if ($definesAssert) { $relative }
        }
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('local-assert-guard-' + [guid]::NewGuid().ToString('N'))
try {
    Invoke-AssertCase 'only parsed Assert function definitions count' {
        foreach ($folder in 'tests/fixtures', 'tests/domain', 'tools') { New-Item -ItemType Directory -Path (Join-Path $scratch $folder) -Force | Out-Null }
        Set-Content -LiteralPath (Join-Path $scratch 'tests/fixtures/AssertSupport.ps1') -Value 'function Assert-True { }'
        Set-Content -LiteralPath (Join-Path $scratch 'tests/domain/Test-NewSelfTest.ps1') -Value 'function Assert-Thing { }'
        Set-Content -LiteralPath (Join-Path $scratch 'tests/domain/Test-TextSelfTest.ps1') -Value "'function Assert-Thing { }'`n# function Assert-Other { }"
        Set-Content -LiteralPath (Join-Path $scratch 'tools/Check-Thing.ps1') -Value 'function Test-Thing { function Assert-Inner { } }'
        $found = @(Get-LocalAssertDefinitionFile -Root $scratch | Sort-Object)
        Assert-Equal ($found -join '|') 'tests/domain/Test-NewSelfTest.ps1|tools/Check-Thing.ps1' 'files that define an Assert function'
    }

    $baseline = @(Get-Content -LiteralPath $baselinePath | Where-Object { $_ -and -not $_.StartsWith('#') })
    $actual = @(Get-LocalAssertDefinitionFile -Root $repoRoot)

    Invoke-AssertCase 'no file outside the baseline defines a local Assert function' {
        $new = @($actual | Where-Object { $_ -cnotin $baseline } | Sort-Object)
        Assert-True ($new.Count -eq 0) ("dot-source tests/fixtures/AssertSupport.ps1 instead of defining Assert functions in: " + ($new -join ', '))
    }

    Invoke-AssertCase 'every baseline entry still defines a local Assert function' {
        $stale = @($baseline | Where-Object { $_ -cnotin $actual } | Sort-Object)
        Assert-True ($stale.Count -eq 0) ("remove from tests/fixtures/local-assert-baseline.txt, they no longer define Assert functions: " + ($stale -join ', '))
    }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-AssertRun
Write-Host 'LOCAL_ASSERT_GUARD_SELFTEST_OK' -ForegroundColor Cyan
