#requires -Version 7.4
<#
.SYNOPSIS
    Generator for the legacy GeneXus 9 (iso-8859-1) export fixture used by self-tests.

.DESCRIPTION
    This file is versioned as UTF-8/LF (versions cleanly). The function writes the fixture in
    iso-8859-1 (Latin-1) to a temporary folder supplied by the caller, with real Latin-1 accent
    bytes — instead of versioning an iso-8859-1 .xml (fragile: editors/git can
    transcode it to UTF-8 and break the encoding test). The self-tests generate the fixture
    in Temp on-the-fly and consume it.

    Fixture coverage:
    - equivalent with LastUpdate (Transaction), WorkPanel (tag fix), Procedure WITHOUT
      LastUpdate (sentinel);
    - orphan Report; Menubar stays in the GX9 fixture (not in the registry and
      equivalent→Menubar);
    - Attributes block with 2 GXAtt (accented Title);
    - adversarial payload: <Objects>/<Object> and <Attribute> nested in Structure (>=2 levels),
      to prove XPath-does-not-leak;
    - Latin-1 accents (Configuracao, Parametros, Relatorio, Endereco).
#>

Set-StrictMode -Version Latest

function New-GeneXusLegacyExportFixtureFile {
    <# Writes the iso-8859-1 fixture to -Path and returns the path. #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('CRLF', 'LF')][string]$Eol = 'CRLF'
    )

    $content = @'
<?xml version='1.0' encoding='iso-8859-1'?>
<ExportFile>
  <Model>
    <Name>SampleKb7</Name>
  </Model>
  <KMW>
    <MajorVersion>2</MajorVersion>
    <MinorVersion>2</MinorVersion>
    <Path>C:\Models\SampleKb7</Path>
    <MaxGxBuildSaved>2601</MaxGxBuildSaved>
  </KMW>
  <GXObject>
    <Transaction>
      <Info>
        <Name>Cliente</Name>
        <Description>Configuração de clientes</Description>
        <Folder>FIN</Folder>
      </Info>
      <LastUpdate>2001-01-15 12:28:00GMT</LastUpdate>
      <Structure>
        <Source><![CDATA[ClienteId*
ClienteNome]]></Source>
        <Objects>
          <Object type="aninhado-nao-deve-vazar" name="NaoDeveVazar"/>
        </Objects>
        <Attribute>colSpanInternoNaoDeveVazar</Attribute>
      </Structure>
    </Transaction>
  </GXObject>
  <GXObject>
    <WorkPanel>
      <Info>
        <Name>CbCdPmF</Name>
        <Description>Cadastro de Parâmetros</Description>
      </Info>
    </WorkPanel>
  </GXObject>
  <GXObject>
    <Procedure>
      <Info>
        <Name>RelConfig</Name>
        <Description>Relatório sem data declarada</Description>
      </Info>
    </Procedure>
  </GXObject>
  <GXObject>
    <Report>
      <Info>
        <Name>RelMov</Name>
        <Description>Relatório de Movimentação</Description>
      </Info>
      <LastUpdate>2003-05-10 09:00:00GMT</LastUpdate>
    </Report>
  </GXObject>
  <GXObject>
    <Menubar>
      <Info>
        <Name>MenuPrincipal</Name>
      </Info>
      <LastUpdate>2003-05-10 09:00:00GMT</LastUpdate>
    </Menubar>
  </GXObject>
  <Attributes>
    <GXAtt>
      <Attribute>
        <Id>237</Id>
        <Name>Usrsnh</Name>
        <Title>Senha</Title>
        <LastUpdate>2001-01-15 12:28:00GMT</LastUpdate>
      </Attribute>
    </GXAtt>
    <GXAtt>
      <Attribute>
        <Id>238</Id>
        <Name>Endereco</Name>
        <Title>Endereço de cobrança</Title>
        <LastUpdate>2001-01-15 12:28:00GMT</LastUpdate>
      </Attribute>
    </GXAtt>
  </Attributes>
</ExportFile>
'@

    $newLine = if ($Eol -eq 'CRLF') { "`r`n" } else { "`n" }
    $normalized = (($content -replace "`r`n", "`n") -replace "`n", $newLine)

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir)
    }
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.Encoding]::GetEncoding('iso-8859-1'))
    return $Path
}
