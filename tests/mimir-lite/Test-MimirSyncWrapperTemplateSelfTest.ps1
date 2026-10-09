#requires -Version 7.4
<#
.SYNOPSIS
    End-to-end self-test for the sync wrapper template (Update-KbFromXpz.example.ps1).

.DESCRIPTION
    Scaffolds a synthetic KB workspace with New-MimirKbWorkspace.ps1 (shared root = this
    repository), then runs the generated sync wrapper as a child process
    (pwsh -NoProfile -File) against synthetic export packages:
      (a) a successful sync with the chained index rebuild: the wrapper's WHOLE stdout must
          be exactly one JSON line (Kind = mimir-sync-result); the rebuild report must not
          reach stdout.
      (b) a package with an object type the catalog does not map: the wrapper's pre-scan
          blocks before materializing, and its error names the type GUID with the type name
          and package from the package's Dependencies block, the count, and the object name.
    No real KB; the packages are written inline. Requires Python 3.8+ for the index rebuild,
    like the other index self-tests.
#>
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scaffolder = Join-Path $repoRoot 'skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mimir-sync-wrapper-{0}' -f [guid]::NewGuid().ToString('N'))
$utf8 = [System.Text.UTF8Encoding]::new($false)

$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $failures.Add($Message) }
}

function Invoke-ChildSeparated {
    param([string]$Path, [string[]]$Arguments)
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $stdout = & pwsh -NoProfile -NonInteractive -File $Path @Arguments 2>$errFile
        $exit = $LASTEXITCODE
        $stderr = [System.IO.File]::ReadAllText($errFile)
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{
        ExitCode = $exit
        StdOut   = (@($stdout | ForEach-Object { "$_" }) -join "`n")
        StdErr   = $stderr
    }
}

function New-SampleWorkspace {
    param([string]$Name)
    $ws = Join-Path $tempRoot $Name
    $output = & pwsh -NoProfile -NonInteractive -File $scaffolder -WorkspaceRoot $ws -KbName 'Sample' -SharedSkillsRoot $repoRoot -AsJson 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "scaffold failed for ${Name}: exit=$LASTEXITCODE output=$($output -join ' | ')"
    }
    return $ws
}

$attributeTypePart = 'ad3ca970-19d0-44e1-a7b7-db05556e820c'

try {
    [void](New-Item -ItemType Directory -Path $tempRoot -Force)

    # (a) Successful sync: stdout carries only the sync result JSON.
    $wsA = New-SampleWorkspace -Name 'ws-a'
    $packageA = Join-Path $wsA 'IdeXpzExports/package-a.xml'
    [System.IO.File]::WriteAllText($packageA, @"
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <Objects />
  <Attributes>
    <Attribute lastUpdate="2026-01-01T00:00:00.0000000Z" guid="11111111-1111-1111-1111-111111111111" name="CustomerName" description="Customer name"><Part type="$attributeTypePart" /></Attribute>
  </Attributes>
</ExportFile>
"@, $utf8)
    $wrapperA = Join-Path $wsA 'scripts/Update-SampleKbFromXpz.ps1'
    $runA = Invoke-ChildSeparated -Path $wrapperA -Arguments @('-InputPath', $packageA, '-NoGitSummary')
    Assert-True ($runA.ExitCode -eq 0) "(a) wrapper must exit 0; exit=$($runA.ExitCode) stderr=$($runA.StdErr)"
    $stdoutA = $runA.StdOut.Trim()
    $linesA = @($stdoutA -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-True ($linesA.Count -eq 1) "(a) wrapper stdout must be exactly one JSON line; got $($linesA.Count) line(s): $stdoutA"
    $resultA = $null
    try { $resultA = $stdoutA | ConvertFrom-Json } catch { $failures.Add("(a) whole wrapper stdout must parse as JSON: $($_.Exception.Message)") }
    if ($null -ne $resultA) {
        Assert-True ($resultA.Kind -eq 'mimir-sync-result') "(a) stdout JSON Kind must be mimir-sync-result; got '$($resultA.Kind)'"
        Assert-True ($resultA.Created -eq 1) "(a) Created must be 1; got $($resultA.Created)"
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $wsA 'KbIntelligence/kb-intelligence.sqlite') -PathType Leaf) '(a) the chained index rebuild must produce the SQLite index'

    # (b) Unknown type: the wrapper error names it instead of a generic message.
    $wsB = New-SampleWorkspace -Name 'ws-b'
    $unknownGuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    $packageB = Join-Path $wsB 'IdeXpzExports/package-b.xml'
    [System.IO.File]::WriteAllText($packageB, @"
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <Objects>
    <Object type="$unknownGuid" name="NewThing" guid="22222222-2222-2222-2222-222222222222"><Part type="$attributeTypePart" /></Object>
  </Objects>
  <Attributes />
  <Dependencies>
    <Reference Package="99999999-9999-9999-9999-999999999999" Type="Object" Id="$unknownGuid">
      <Properties Name="Sample Type" PackageName="SampleBL" />
    </Reference>
  </Dependencies>
</ExportFile>
"@, $utf8)
    $wrapperB = Join-Path $wsB 'scripts/Update-SampleKbFromXpz.ps1'
    $runB = Invoke-ChildSeparated -Path $wrapperB -Arguments @('-InputPath', $packageB, '-NoGitSummary')
    $outputB = $runB.StdOut + "`n" + $runB.StdErr
    Assert-True ($runB.ExitCode -ne 0) "(b) wrapper must fail on an unknown type; exit=$($runB.ExitCode)"
    Assert-True ($outputB -match 'Pre-scan blocked') "(b) wrapper error must say the pre-scan blocked; output=$outputB"
    Assert-True ($outputB -match [regex]::Escape("$unknownGuid type=`"Sample Type`" package=`"SampleBL`" [1] names=NewThing")) "(b) wrapper error must name the GUID, type name, package, count, and object name; output=$outputB"
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $wsB 'KbObjectsXml') -Recurse -File -Filter '*.xml').Count -eq 0) '(b) a blocked pre-scan must not materialize any XML'
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw ("Sync wrapper template self-test failed:`n - " + ($failures -join "`n - "))
}
Write-Output 'MIMIR_SYNC_WRAPPER_TEMPLATE_SELFTEST_OK'
