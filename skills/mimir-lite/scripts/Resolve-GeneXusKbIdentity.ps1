#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KbNativePath,

    [PSCredential]$SqlCredential,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-PathValue {
    param([string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Read-IniSection {
    param(
        [string]$Path,
        [string]$SectionName
    )

    $section = [ordered]@{}
    $inSection = $false
    $headerPattern = '^\s*\[(?<name>[^\]]+)\]\s*$'

    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $header = [regex]::Match($line, $headerPattern)
        if ($header.Success) {
            $inSection = ($header.Groups['name'].Value.Trim() -ieq $SectionName)
            continue
        }

        if (-not $inSection) {
            continue
        }

        if ($line -notmatch '^\s*(?<key>[^=;#][^=]*?)\s*=\s*(?<value>.*)\s*$') {
            continue
        }

        $key = $Matches['key'].Trim()
        $value = $Matches['value'].Trim()
        $section[$key] = $value
    }

    return $section
}

function Read-ConnectionSettings {
    param(
        [string]$Path,
        [string]$DefaultDatabase
    )

    $raw = [System.IO.File]::ReadAllText($Path)
    $result = [ordered]@{}
    $parsedXml = $false

    try {
        [xml]$xml = $raw
        if ($null -ne $xml.DocumentElement) {
            $parsedXml = $true
            $leafNodes = @($xml.DocumentElement.SelectNodes('//*[not(*)]'))
            foreach ($node in $leafNodes) {
                if (-not [string]::IsNullOrWhiteSpace($node.LocalName)) {
                    $result[$node.LocalName] = $node.InnerText.Trim()
                }
            }
        }
    } catch {
        $parsedXml = $false
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($raw -split "\r?\n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) {
            continue
        }

        if ($trimmed -match '^\s*(?<key>[^=]+?)\s*=\s*(?<value>.+?)\s*$') {
            $key = $Matches['key'].Trim()
            $value = $Matches['value'].Trim()
            $result[$key] = $value
        }

        if ($trimmed -match '(?i)(Data Source|Server|Database|Initial Catalog)\s*=') {
            $candidates.Add($trimmed) | Out-Null
        }
    }

    foreach ($candidate in $candidates) {
        try {
            $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($candidate)
            if (-not [string]::IsNullOrWhiteSpace([string]$builder['Initial Catalog'])) {
                return [pscustomobject]@{
                    ConnectionString = $candidate
                    Database = [string]$builder['Initial Catalog']
                    DataSource = [string]$builder['Data Source']
                    IntegratedSecurity = [bool]$builder['Integrated Security']
                    IntegratedSecuritySource = 'connection-string'
                    ParsedFrom = 'connection-string'
                    Settings = [pscustomobject]$result
                }
            }
        } catch {
            continue
        }
    }

    $database = $null
    foreach ($key in @('Database', 'Initial Catalog', 'DB', 'DbName', 'DBName')) {
        if ($result.Contains($key) -and -not [string]::IsNullOrWhiteSpace($result[$key])) {
            $database = $result[$key]
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($database)) {
        $database = $DefaultDatabase
    }

    $server = 'localhost'
    foreach ($key in @('HostName', 'Server', 'Data Source', 'DataSource', 'ServerInstance')) {
        if ($result.Contains($key) -and -not [string]::IsNullOrWhiteSpace($result[$key])) {
            $server = $result[$key]
            break
        }
    }

    $integratedSecurity = $true
    $integratedSecuritySource = 'default'
    foreach ($key in @('IntegratedSecurity', 'Integrated Security', 'Trusted_Connection')) {
        if ($result.Contains($key)) {
            $rawFlag = $result[$key].Trim()
            if ($rawFlag -match '^(?i:true|sspi|yes|1)$') {
                $integratedSecurity = $true
                $integratedSecuritySource = $key
            } elseif ($rawFlag -match '^(?i:false|no|0)$') {
                $hasSqlUser = $false
                foreach ($userKey in @('User ID', 'UserID', 'User Id', 'UID', 'UserName', 'Username')) {
                    if ($result.Contains($userKey) -and -not [string]::IsNullOrWhiteSpace($result[$userKey])) {
                        $hasSqlUser = $true
                        break
                    }
                }

                if ($parsedXml -and -not $hasSqlUser) {
                    $integratedSecurity = $true
                    $integratedSecuritySource = "$key=false-in-gx-xml-without-sql-user"
                } else {
                    $integratedSecurity = $false
                    $integratedSecuritySource = $key
                }
            } else {
                throw "BLOCK: unrecognized IntegratedSecurity value in knowledgebase.connection: '$rawFlag'"
            }
            break
        }
    }

    return [pscustomobject]@{
        ConnectionString = $null
        Database = $database
        DataSource = $server
        IntegratedSecurity = [bool]$integratedSecurity
        IntegratedSecuritySource = $integratedSecuritySource
        ParsedFrom = if ($parsedXml) { 'xml' } else { 'key-values' }
        Settings = [pscustomobject]$result
    }
}

function New-KbSqlConnectionString {
    param(
        [string]$DataSource,
        [string]$Database,
        [bool]$IntegratedSecurity,
        [PSCredential]$Credential
    )

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = if ([string]::IsNullOrWhiteSpace($DataSource)) { 'localhost' } else { $DataSource }
    $builder['Initial Catalog'] = $Database
    $builder['Encrypt'] = $false
    $builder['TrustServerCertificate'] = $true

    if ($IntegratedSecurity) {
        $builder['Integrated Security'] = $true
        return $builder.ConnectionString
    }

    if ($null -eq $Credential) {
        throw 'BLOCK: knowledgebase.connection does not use IntegratedSecurity; provide -SqlCredential (Get-Credential).'
    }

    $builder['User ID'] = $Credential.UserName
    $builder['Password'] = $Credential.GetNetworkCredential().Password
    return $builder.ConnectionString
}

function Get-KbGuidFromDatabase {
    param([string]$ConnectionString)

    $connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT EntityGuid FROM Entity WHERE EntityTypeId = 9'
        $rows = New-Object System.Collections.Generic.List[string]
        $reader = $command.ExecuteReader()
        try {
            while ($reader.Read()) {
                $rows.Add($reader.GetValue(0).ToString()) | Out-Null
            }
        } finally {
            $reader.Dispose()
        }

        if ($rows.Count -ne 1) {
            throw "BLOCK: EntityTypeId=9 query returned $($rows.Count) rows; expected exactly 1."
        }

        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($rows[0], [ref]$parsed)) {
            throw "BLOCK: KB EntityGuid is not in GUID format: '$($rows[0])'."
        }

        return $parsed.ToString()
    } finally {
        $connection.Dispose()
    }
}

function Convert-LocalPathToAdminUnc {
    param([string]$Path)

    $root = [System.IO.Path]::GetPathRoot($Path)
    if ([string]::IsNullOrWhiteSpace($root) -or $root -notmatch '^(?<drive>[A-Za-z]):\\$') {
        return $Path
    }

    $drive = $Matches['drive'].ToUpperInvariant()
    $rest = $Path.Substring($root.Length).TrimStart('\')
    $hostName = [System.Net.Dns]::GetHostName()
    if ([string]::IsNullOrWhiteSpace($rest)) {
        return "\\$hostName\$drive$"
    }

    return "\\$hostName\$drive$\" + $rest
}

$resolvedKbPath = Normalize-PathValue -Path $KbNativePath
$modelIniPath = Join-Path $resolvedKbPath 'model.ini'
$connectionPath = Join-Path $resolvedKbPath 'knowledgebase.connection'

if (-not (Test-Path -LiteralPath $resolvedKbPath -PathType Container)) {
    throw "BLOCK: native KB folder not found: $resolvedKbPath"
}

if (-not (Test-Path -LiteralPath $modelIniPath -PathType Leaf)) {
    throw "BLOCK: model.ini not found: $modelIniPath"
}

if (-not (Test-Path -LiteralPath $connectionPath -PathType Leaf)) {
    throw "BLOCK: knowledgebase.connection not found: $connectionPath"
}

$model = Read-IniSection -Path $modelIniPath -SectionName 'MODEL 001'
foreach ($requiredKey in @('___GUID')) {
    if (-not $model.Contains($requiredKey) -or [string]::IsNullOrWhiteSpace($model[$requiredKey])) {
        throw "BLOCK: model.ini missing required key in [MODEL 001]: $requiredKey"
    }
}

$resolvedKbName = $null
foreach ($nameKey in @('PWFProcessesNamespace', 'ExternalNamespace')) {
    if ($model.Contains($nameKey) -and -not [string]::IsNullOrWhiteSpace($model[$nameKey])) {
        $resolvedKbName = $model[$nameKey]
        break
    }
}

if ([string]::IsNullOrWhiteSpace($resolvedKbName)) {
    $resolvedKbName = Split-Path -Path $resolvedKbPath -Leaf
}

$modelName = if ($model.Contains('Name') -and -not [string]::IsNullOrWhiteSpace($model['Name'])) { $model['Name'] } else { $null }

$versionGuid = $model['___GUID']
$parsedVersionGuid = [guid]::Empty
if (-not [guid]::TryParse($versionGuid, [ref]$parsedVersionGuid)) {
    throw "BLOCK: [MODEL 001].___GUID is not in GUID format: '$versionGuid'"
}

$defaultDatabase = 'GX_KB_' + (Split-Path -Path $resolvedKbPath -Leaf)
$connectionInfo = Read-ConnectionSettings -Path $connectionPath -DefaultDatabase $defaultDatabase
$connectionString = New-KbSqlConnectionString `
    -DataSource $connectionInfo.DataSource `
    -Database $connectionInfo.Database `
    -IntegratedSecurity $connectionInfo.IntegratedSecurity `
    -Credential $SqlCredential

$kbGuid = Get-KbGuidFromDatabase -ConnectionString $connectionString
$userDomain = if ([string]::IsNullOrWhiteSpace($env:USERDOMAIN)) { [System.Net.Dns]::GetHostName() } else { $env:USERDOMAIN }
$userName = if ([string]::IsNullOrWhiteSpace($env:USERNAME)) { [System.Environment]::UserName } else { $env:USERNAME }

$result = [ordered]@{
    kbGuid = $kbGuid
    kbName = $resolvedKbName
    versionGuid = $parsedVersionGuid.ToString()
    versionName = $resolvedKbName
    modelName = $modelName
    uncPath = Convert-LocalPathToAdminUnc -Path $resolvedKbPath
    username = "$userDomain\$userName"
    kbNativePath = $resolvedKbPath
    database = $connectionInfo.Database
    dataSource = $connectionInfo.DataSource
    integratedSecurity = [bool]$connectionInfo.IntegratedSecurity
    integratedSecuritySource = $connectionInfo.IntegratedSecuritySource
    connectionParsedFrom = $connectionInfo.ParsedFrom
    versionGuidSemanticCaveat = 'Sourced from [MODEL 001].___GUID; validate against an IDE export with Source populated when comparable evidence is available.'
}

if ($AsJson) {
    [pscustomobject]$result | ConvertTo-Json -Depth 5
} else {
    [pscustomobject]$result
}
