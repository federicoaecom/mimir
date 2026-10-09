#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$generatorScript = Join-Path $repoRoot 'skills/mimir-lite/scripts/generate-kb-advanced-docs.ps1'
$sampleKbRoot = Join-Path $repoRoot 'tests/fixtures/sample-kb'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-ContractFailure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Add-AdviceFindings {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $recommendationPattern = [regex]::new(
        '\b(?:recommend(?:ed|ation)?|suggest(?:ed|ion)?|candidate for|should(?!\s+not\b)|must|prefer(?:red)?|ready for|priority preservation|preservation)\b.{0,120}\b(?:clon(?:e|ing)|generat(?:e|ion)|import(?:ing)?|packag(?:e|ing))\b',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    $recommendedTemplatePattern = [regex]::new('\brecommended template:\s*choose\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $directActionPattern = [regex]::new('^\s*(?:[-*]\s*)?(?:clone\s+(?:from|with)|generate\b|import\b|package\b)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $findings = [System.Collections.Generic.List[string]]::new()
    $sectionOperation = $null
    $tableHeaders = @()
    $lines = $Content -split "`r?`n"

    foreach ($line in $lines) {
        if ($line -match '^\s*#{1,6}\s+(.+)$') {
            $heading = $Matches[1]
            if ($heading -match '(?i)^\s*(?:suggested|recommended)\b.*\b(?:clon(?:e|ing)|generat(?:e|ion)|import|packag(?:e|ing))\b' -or
                $heading -match '(?i)^\s*when to accept\b.*\b(?:clon(?:e|ing)|generat(?:e|ion)|import|packag(?:e|ing))\b') {
                $findings.Add("operational recommendation heading: $($heading.Trim())") | Out-Null
            }

            $sectionOperation = $null
            if ($heading -match '(?i)\bclon(?:e|ing)\b') {
                $sectionOperation = 'cloning'
            } elseif ($heading -match '(?i)\bgenerat(?:e|ion)\b') {
                $sectionOperation = 'generation'
            } elseif ($heading -match '(?i)\bimport\b') {
                $sectionOperation = 'import'
            } elseif ($heading -match '(?i)\bpackag(?:e|ing)\b') {
                $sectionOperation = 'packaging'
            }
            $tableHeaders = @()
            continue
        }

        if ($line -match '^\s*\|.*\|\s*$') {
            if ($line -match '^\s*\|\s*:?-{3,}') { continue }
            $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
            if (@($cells | Where-Object { $_ -in @('FolderType', 'PartType', 'Attribute', 'Classification', 'PracticalRecommendation') }).Count -gt 0) {
                $tableHeaders = $cells
                continue
            }

            $recommendationColumn = [Array]::IndexOf($tableHeaders, 'PracticalRecommendation')
            if ($recommendationColumn -ge 0 -and $recommendationColumn -lt $cells.Count) {
                $recommendation = $cells[$recommendationColumn]
                if ($directActionPattern.IsMatch($recommendation) -or $recommendationPattern.IsMatch($recommendation)) {
                    $findings.Add("actionable table recommendation: $recommendation") | Out-Null
                }
            }
            # Other table columns are evidence or taxonomy (for example, a readiness classification),
            # not prose recommendations; only the explicitly named recommendation column is inspected.
            continue
        }

        if ($sectionOperation -and $line -match '^\s*\d+\.\s*(?:Select|Choose|Prefer|Preserve|Change|Use|Start|Clone|Generate|Import|Package|Export)\b') {
            $findings.Add("numbered $sectionOperation instruction: $($line.Trim())") | Out-Null
        }
        if ($directActionPattern.IsMatch($line) -or $recommendationPattern.IsMatch($line) -or $recommendedTemplatePattern.IsMatch($line)) {
            $findings.Add("affirmative operational recommendation: $($line.Trim())") | Out-Null
        }
    }

    foreach ($finding in $findings) {
        Add-ContractFailure "${FileName}: $finding"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('kb-advanced-docs-read-only-selftest-{0}' -f ([guid]::NewGuid().ToString('N')))
try {
    if (-not (Test-Path -LiteralPath $generatorScript -PathType Leaf)) {
        throw "Advanced docs generator not found: $generatorScript"
    }
    if (-not (Test-Path -LiteralPath $sampleKbRoot -PathType Container)) {
        throw "Synthetic sample-kb fixture not found: $sampleKbRoot"
    }

    $fixtureFiles = @(Get-ChildItem -LiteralPath $sampleKbRoot -Recurse -File -Filter '*.xml' | Sort-Object FullName)
    if ($fixtureFiles.Count -eq 0) {
        throw "Synthetic sample-kb fixture contains no XML objects: $sampleKbRoot"
    }
    $objectRootCount = 0
    foreach ($fixtureFile in $fixtureFiles) {
        try {
            $fixtureXml = [System.Xml.XmlDocument]::new()
            $fixtureXml.Load($fixtureFile.FullName)
        } catch {
            throw "Synthetic sample-kb fixture XML is invalid: $($fixtureFile.FullName): $($_.Exception.Message)"
        }
        if ($null -ne $fixtureXml.SelectSingleNode('/Object')) {
            $objectRootCount++
        }
    }
    if ($objectRootCount -eq 0) {
        throw "Synthetic sample-kb fixture contains no generator-readable /Object XML files: $sampleKbRoot"
    }

    $sourceRoot = Join-Path $tempRoot 'corpus'
    $outputRoot = Join-Path $tempRoot 'output'
    [void](New-Item -ItemType Directory -Path $sourceRoot -Force)
    [void](New-Item -ItemType Directory -Path $outputRoot -Force)
    Get-ChildItem -LiteralPath $sampleKbRoot -Force | Copy-Item -Destination $sourceRoot -Recurse

    $copiedFixtureFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Filter '*.xml')
    if ($copiedFixtureFiles.Count -ne $fixtureFiles.Count) {
        throw "Synthetic corpus copy is incomplete: copied $($copiedFixtureFiles.Count) XML files; expected $($fixtureFiles.Count)."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'Transaction/Invoice.xml') -PathType Leaf)) {
        throw "Synthetic corpus copy is missing the expected Transaction/Invoice.xml object."
    }
    if (@(Get-ChildItem -LiteralPath $outputRoot -Force).Count -ne 0) {
        throw "Fresh output directory is not empty: $outputRoot"
    }

    $generatorOutput = @(& pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $generatorScript -SourceRoot $sourceRoot -OutputRoot $outputRoot 2>&1)
    $generatorExitCode = $LASTEXITCODE
    if ($generatorExitCode -ne 0) {
        throw "Advanced docs generator should succeed on the synthetic sample-kb fixture; exit $generatorExitCode. Output: $($generatorOutput -join "`n")"
    }
    $matrixPath = Join-Path $outputRoot '10-part-type-matrix-by-type.md'
    $matrixContent = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8
    if ($matrixContent -notmatch '(?m)^## Transaction\s*$') {
        throw "Advanced docs generator exited successfully but did not analyze the synthetic Transaction corpus. Matrix: $matrixContent Output: $($generatorOutput -join "`n")"
    }

    $expectedNames = @(
        '10-part-type-matrix-by-type.md',
        '11-stable-vs-variable-fields.md',
        '12-structural-diffs-by-type.md',
        '14-mandatoriness-indications.md',
        '16-risk-map-by-type.md'
    )
    $actualFiles = @(Get-ChildItem -LiteralPath $outputRoot -Recurse -File | Sort-Object FullName)
    $actualNames = @($actualFiles | ForEach-Object { $_.Name })
    $expectedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $actualSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($name in $expectedNames) { [void]$expectedSet.Add($name) }
    foreach ($name in $actualNames) { [void]$actualSet.Add($name) }

    $extraNames = @($actualNames | Where-Object { -not $expectedSet.Contains($_) } | Sort-Object)
    $missingNames = @($expectedNames | Where-Object { -not $actualSet.Contains($_) } | Sort-Object)
    if ($extraNames.Count -gt 0 -or $missingNames.Count -gt 0 -or $actualFiles.Count -ne $expectedNames.Count) {
        Add-ContractFailure ("Expected exactly five read-side files; found {0}. Extra: [{1}]. Missing: [{2}]. Actual: [{3}]." -f `
            $actualFiles.Count, ($extraNames -join ', '), ($missingNames -join ', '), ($actualNames -join ', '))
    }

    # A reused output root is regenerated in place: files the generator does not own, even one
    # named like a former report (13, 15, 17, 18), neither block the run nor get deleted or edited.
    $foreignName = '13-guia-de-clonagem-segura.md'
    $foreignPath = Join-Path $outputRoot $foreignName
    [System.IO.File]::WriteAllText($foreignPath, 'A file the generator does not own.', [System.Text.UTF8Encoding]::new($false))
    $foreignHash = (Get-FileHash -LiteralPath $foreignPath -Algorithm SHA256).Hash

    $rerunOutput = @(& pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $generatorScript -SourceRoot $sourceRoot -OutputRoot $outputRoot 2>&1)
    $rerunExitCode = $LASTEXITCODE
    if ($rerunExitCode -ne 0) {
        Add-ContractFailure "Generator should rerun over a reused output root holding a file it does not own ('$foreignName'); exit $rerunExitCode. Output: $($rerunOutput -join "`n")"
    }
    if (-not (Test-Path -LiteralPath $foreignPath -PathType Leaf)) {
        Add-ContractFailure "Generator removed a file it does not own: $foreignName"
    } elseif ((Get-FileHash -LiteralPath $foreignPath -Algorithm SHA256).Hash -ne $foreignHash) {
        Add-ContractFailure "Generator modified a file it does not own: $foreignName"
    }
    foreach ($name in $expectedNames) {
        if (-not (Test-Path -LiteralPath (Join-Path $outputRoot $name) -PathType Leaf)) {
            Add-ContractFailure "Rerun over a reused output root lost the report: $name"
        }
    }

    $partSourceRoot = Join-Path $tempRoot 'part-corpus'
    $partOutputRoot = Join-Path $tempRoot 'part-output'
    $partFixtureReady = $false
    try {
        [void](New-Item -ItemType Directory -Path $partSourceRoot)
        Get-ChildItem -LiteralPath $sourceRoot -Force | Copy-Item -Destination $partSourceRoot -Recurse
        [void](New-Item -ItemType Directory -Path $partOutputRoot)
        $partFixturePath = Join-Path $partSourceRoot 'Transaction/Invoice.xml'
        $partFixtureXml = [System.Xml.XmlDocument]::new()
        $partFixtureXml.Load($partFixturePath)
        $partObjectNode = $partFixtureXml.SelectSingleNode('/Object[@name="Invoice"]')
        if ($null -eq $partObjectNode) {
            Add-ContractFailure 'Temporary Part-coverage fixture has no /Object[@name="Invoice"] node.'
        } else {
            foreach ($duplicateIndex in 1..2) {
                $partNode = $partFixtureXml.CreateElement('Part')
                $partNode.SetAttribute('type', 'Rules')
                $sourceNode = $partFixtureXml.CreateElement('Source')
                [void]$sourceNode.AppendChild($partFixtureXml.CreateCDataSection('Error("Negative invoice total") if InvoiceTotal < 0;'))
                [void]$partNode.AppendChild($sourceNode)
                [void]$partObjectNode.AppendChild($partNode)
            }
            $partFixtureXml.Save($partFixturePath)

            $validatedPartXml = [System.Xml.XmlDocument]::new()
            $validatedPartXml.Load($partFixturePath)
            $validatedPartNodes = @($validatedPartXml.SelectNodes('/Object[@name="Invoice"]/Part[@type="Rules"]/Source'))
            if ($validatedPartNodes.Count -ne 2 -or @($validatedPartNodes | Where-Object { [string]::IsNullOrWhiteSpace($_.InnerText) }).Count -gt 0) {
                Add-ContractFailure 'Temporary Part-coverage fixture did not retain two non-empty, parseable Rules Parts.'
            } else {
                $partFixtureReady = $true
            }
        }
    } catch {
        Add-ContractFailure "Could not prepare or parse the temporary Part-coverage fixture: $($_.Exception.Message)"
    }

    if ($partFixtureReady) {
        $partGeneratorOutput = @(& pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $generatorScript -SourceRoot $partSourceRoot -OutputRoot $partOutputRoot 2>&1)
        $partGeneratorExitCode = $LASTEXITCODE
        if ($partGeneratorExitCode -ne 0) {
            Add-ContractFailure "Advanced docs generator failed on the temporary Part-coverage fixture; exit $partGeneratorExitCode. Output: $($partGeneratorOutput -join "`n")"
        } else {
            try {
                $partMatrixPath = Join-Path $partOutputRoot '10-part-type-matrix-by-type.md'
                $partMatrixContent = Get-Content -LiteralPath $partMatrixPath -Raw -Encoding UTF8
                $rulesRow = [regex]::Match($partMatrixContent, '(?m)^\| Rules \| (\d+) \|')
                if (-not $rulesRow.Success) {
                    Add-ContractFailure 'Part-coverage report omitted the nonzero Rules Part frequency row.'
                } else {
                    $objectsWithRules = [int]$rulesRow.Groups[1].Value
                    if ($objectsWithRules -le 0) {
                        Add-ContractFailure 'Part-coverage report recorded zero objects with Rules despite non-empty Rules Parts in the fixture.'
                    }
                    if ($objectsWithRules -ne 1) {
                        Add-ContractFailure ("Part-coverage report counted {0} Rules occurrences as objects; expected one distinct object despite duplicate Rules Parts." -f $objectsWithRules)
                    }
                }
                if ($partMatrixContent -notmatch '(?m)^- Direct evidence: average Part per object: 0[.,]67\.\r?$') {
                    Add-ContractFailure 'Part-coverage report omitted the nonzero average-Part summary (expected 0.67 for two Rules Parts across three Transaction objects).'
                }
            } catch {
                Add-ContractFailure "Could not inspect generated Part-coverage reports: $($_.Exception.Message)"
            }
        }
    }

    # A relative -SourceRoot (resolved against the working directory) yields the same object
    # types as an absolute one: relative paths are computed from the resolved root, and the
    # type folder is the first segment whichever separator the platform uses.
    $relativeOutputRoot = Join-Path $tempRoot 'relative-output'
    [void](New-Item -ItemType Directory -Path $relativeOutputRoot)
    Push-Location -LiteralPath $tempRoot
    try {
        $relativeOutput = @(& pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $generatorScript -SourceRoot 'corpus' -OutputRoot $relativeOutputRoot 2>&1)
        $relativeExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($relativeExitCode -ne 0) {
        Add-ContractFailure "Generator failed with a relative -SourceRoot; exit $relativeExitCode. Output: $($relativeOutput -join "`n")"
    } else {
        $relativeMatrix = Get-Content -LiteralPath (Join-Path $relativeOutputRoot '10-part-type-matrix-by-type.md') -Raw -Encoding UTF8
        $relativeTypes = @([regex]::Matches($relativeMatrix, '(?m)^## (.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
        $absoluteTypes = @([regex]::Matches($matrixContent, '(?m)^## (.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
        if (($relativeTypes -join ',') -ne ($absoluteTypes -join ',')) {
            Add-ContractFailure ("A relative -SourceRoot produced different object types: [{0}]; expected [{1}]." -f ($relativeTypes -join ', '), ($absoluteTypes -join ', '))
        }
    }
    foreach ($typeHeading in @([regex]::Matches($matrixContent, '(?m)^## (.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })) {
        if ($typeHeading -match '[\\/]') {
            Add-ContractFailure "Object type heading carries a path separator: '$typeHeading'"
        }
    }

    foreach ($markdownFile in (Get-ChildItem -LiteralPath $outputRoot -Recurse -File -Filter '*.md' | Sort-Object FullName)) {
        Add-AdviceFindings -FileName $markdownFile.Name -Content (Get-Content -LiteralPath $markdownFile.FullName -Raw -Encoding UTF8)
    }

    if ($failures.Count -gt 0) {
        throw "Read-side output contract failed:`n - $($failures -join "`n - ")"
    }

    Write-Output 'OK: Test-GenerateKbAdvancedDocsReadOnlySelfTest.ps1'
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
        $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
        if ($resolvedTempRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
