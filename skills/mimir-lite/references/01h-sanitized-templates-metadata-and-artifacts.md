# 01h - Sanitized Templates: Metadata and Artifacts

## Document role
Read-side structural evidence and labeled historical observations. These sanitized XML specimens describe exported corpus records; they are not instructions or payloads for creating, cloning, importing, packaging, or building GeneXus objects.

## Purpose
Bring together sanitized templates for metadata, auxiliary artifacts, structural identity, and minimal `Source` compatibility examples.

## Sanitized read-side ThemeColor templates

### Sanitized ThemeColor template 1 - `CorAcaoExemplo`

- Profile: an extremely lean root ThemeColor, with no additional internal `Part`.
- Structural evidence: this exported specimen illustrates simple theme-palette entries.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2014-03-12T17:40:30.0000000Z" checksum="b17ddaa4991114c1378fcb07dc0c2475" fullyQualifiedName="CorAcaoExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="ce3a249f-a6aa-4ab3-9a13-9663409d441b" name="CorAcaoExemplo" type="5592de59-d30a-499d-9100-a7006d3674f2" description="CorAcaoExemplo">
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>CorAcaoExemplo</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized ThemeColor template 2 - `CorAlertaExemplo`

- Profile: a root ThemeColor parallel to the first template, changing only nominal identity.
- Structural evidence: the two exported records share a structural signature while their nominal identities differ; this is an observation, not a duplication instruction.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2014-03-21T15:49:40.0000000Z" checksum="0f7c966ebc90a770da7aaac3a5c86ed3" fullyQualifiedName="CorAlertaExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="08bbf1e9-a441-45a3-abeb-5288e07b0b76" name="CorAlertaExemplo" type="5592de59-d30a-499d-9100-a7006d3674f2" description="CorAlertaExemplo">
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>CorAlertaExemplo</Value>
    </Property>
  </Properties>
</Object>
```


## Sanitized read-side Document templates

### Sanitized Document template 1 - `DocumentoReferenciaExemplo`

- Profile: a lean Document, with a single short `InnerHtml` block and a simple textual reference.
- Structural evidence: this exported specimen illustrates annotation documents, links, or short technical reminders.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2019-11-23T15:47:23.0000000Z" checksum="" fullyQualifiedName="DocumentoReferenciaExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="b8f276b6-f342-4740-901a-94eda21fa7c4" name="DocumentoReferenciaExemplo" type="faeb588c-dcce-4dad-9af3-cdd11b961a32" description="Documento Referencia Exemplo">
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <InnerHtml><![CDATA[https://example.org/tools/xsd-generator]]></InnerHtml>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>DocumentoReferenciaExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized Document template 2 - `DocumentoNotasExemplo`

- Profile: a richer Document, with larger HTML and several internal annotations.
- Structural evidence: this exported specimen illustrates documents holding remarks, instructions, and item lists in embedded HTML.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-03-09T01:02:26.0000000Z" checksum="0895e8d40b56f1d73cabc8531bbfc84e" fullyQualifiedName="DocumentoNotasExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="f412243c-32fb-4945-9112-bdd66d0e31d6" name="DocumentoNotasExemplo" type="faeb588c-dcce-4dad-9af3-cdd11b961a32" description="DocumentoNotasExemplo">
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <InnerHtml><![CDATA[<P>AMBIENTE DE EXEMPLO:</P>
<P>DIRECTORY: SANITIZED-DIRECTORY-ID</P>
<P>USER ID: SANITIZED-USER-ID</P>
<P>repository id: SANITIZED-REPOSITORY-ID</P>
<P>&nbsp;</P>
<P>Bibliotecas externas que exigem revisao na migracao:</P>
<P>BibliotecaA.dll e BibliotecaB.dll</P>
<P>&nbsp;</P>
<P>&nbsp;</P>
<P>Classes e estilos ajustados em uma revisao de tema:<BR>Attribute, ActionButtons, ActiunButtonsHovered, BtnLogin, WorkWith, PromptGrid, ViewGrid, WWColumn, FormCell, WWGridCell, ViewGridCellAdvanced, WWGridCellExpanded, HeaderContainer, WWAdvancedContainer, WWTabPage, WWTabePageHovered, Label, TextBlockHeader, nav, col-sm-8, col-sm-offset-2, col-xs-offset-1, control-label, Rules, ExtraSmall, Small, form-control-static, form-group, form-horizontal, gx-button, P e WWAdvancedContainer.container-fluid.</P>]]></InnerHtml>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>DocumentoNotasExemplo</Value>
    </Property>
    <Property>
      <Name>IsDocumentoNotasExemplo</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```


## Sanitized read-side DataSelector templates

### Sanitized DataSelector template 1 - `dsMovimentoAtivoOuCanceladoExemplo`

- Profile: a lean DataSelector with two `Condition` entries, a boolean variable, and a short supporting `InnerHtml`.
- Structural evidence: this exported specimen illustrates simple binary filters and selectors with a single input variable.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="702d2e19-b267-4c25-ae37-0e2ef9e330a6" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2020-12-23T03:16:25.0000000Z" checksum="faa11acd91e9338faa49bd9fd6cd07ea" fullyQualifiedName="dsMovimentoAtivoOuCanceladoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="438f9146-d6c2-4427-ab41-bf1ed620b571" name="dsMovimentoAtivoOuCanceladoExemplo" type="ffd44be7-3bb4-4d01-9e7e-d1c1a3c095af" description="Movimento Ativo ou Cancelado Exemplo" parent="RegistroMovimento" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="a2bc65a1-999f-4e9b-b837-72285cc9bb16">
    <Level>
      <Condition>
        <Source><![CDATA[RegistroMovimentoCancelado 		= false or RegistroMovimentoCancelado.IsNull() when not &SomenteCancelados
	
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[RegistroMovimentoCancelado 		= true when &SomenteCancelados
]]></Source>
      </Condition>
    </Level>
    <Variables type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
      <Variable Name="SomenteCancelados">
        <Documentation />
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>SomenteCancelados</Value>
          </Property>
          <Property>
            <Name>idBasedOn</Name>
            <Value>Domain:Logico</Value>
          </Property>
        </Properties>
      </Variable>
      <Properties>
        <Property>
          <Name>IsDefault</Name>
          <Value>False</Value>
        </Property>
      </Properties>
    </Variables>
    <Parameters>
      <Parameter>
        <Type>Variable</Type>
        <Name>SomenteCancelados</Name>
        <Description>Somente Cancelados</Description>
      </Parameter>
    </Parameters>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <InnerHtml><![CDATA[https://example.org/docs/data-selector-note]]></InnerHtml>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>dsMovimentoAtivoOuCanceladoExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Movimento Ativo ou Cancelado Exemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized DataSelector template 2 - `dsRegistrosPorMovimentoExemplo`

- Profile: a dense DataSelector, with many `Condition` entries, custom `Variables`, and a richer parametric filter.
- Structural evidence: this exported specimen illustrates selectors based on several combined conditions and a parameter SDT.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="988004e2-6090-42c3-9603-c073172b75a6" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-12-23T13:38:47.0000000Z" checksum="70d20e81967466e858649307c9e679f3" fullyQualifiedName="dsRegistrosPorMovimentoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="3e3c9034-b9dd-44cf-9d5a-97b37c606153" name="dsRegistrosPorMovimentoExemplo" type="ffd44be7-3bb4-4d01-9e7e-d1c1a3c095af" description="ds Registros Por Movimento Exemplo" parent="Registro" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="a2bc65a1-999f-4e9b-b837-72285cc9bb16">
    <Level>
      <Condition>
        <Source><![CDATA[MovimentoEmpresaId = &sdtExemploFiltros.EmpresaExemploId when not &sdtExemploFiltros.EmpresaExemploId.IsEmpty() and not &sdtExemploFiltros.FiltrarPelaEntidadeEmpresaId
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoEmpresaId in &sdtExemploFiltros.listaEmpresasExemploId when &sdtExemploFiltros.EmpresaExemploId.IsEmpty() and not &sdtExemploFiltros.FiltrarPelaEntidadeEmpresaId
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroEntidadeEmpresaId = &sdtExemploFiltros.EntidadeEmpresaId
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroEntidadeLocalExemploId = &sdtExemploFiltros.LocalExemploId when not &sdtExemploFiltros.LocalExemploId.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoCancelado = false or MovimentoCancelado.IsNull()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroCancelado = false or MovimentoRegistroCancelado.IsNull()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroTipo = &sdtExemploFiltros.TipoRegistro when not &sdtExemploFiltros.TipoRegistro.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoProcessoTipo = TipoProcesso.Composicao or MovimentoProcessoTipo = TipoProcesso.Acrescimo or MovimentoProcessoTipo = TipoProcesso.Reducao when &sdtExemploFiltros.VisaoExemploA <> VisaoExemploA.PorProcesso and (&sdtExemploFiltros.SituacaoRegistro = SituacaoRegistro.Pendente or &sdtExemploFiltros.SituacaoRegistro = SituacaoRegistro.Entrada);
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoProcessoTipo = TipoProcesso.Baixa when &sdtExemploFiltros.VisaoExemploA <> VisaoExemploA.PorProcesso and &sdtExemploFiltros.SituacaoRegistro = SituacaoRegistro.Baixado;
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroCodigoHistoricoExterno = &sdtExemploFiltros.codigoHistoricoExterno when not &sdtExemploFiltros.codigoHistoricoExterno.IsEmpty() and &sdtExemploFiltros.codigoHistoricoExterno > 0
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroCodigoHistoricoExterno.IsEmpty() when not &sdtExemploFiltros.codigoHistoricoExterno.IsEmpty() and &sdtExemploFiltros.codigoHistoricoExterno < 0
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroEntidadeId = &sdtExemploFiltros.EntidadeId when not &sdtExemploFiltros.EntidadeId.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[procExemploDocumentoFormatado(MovimentoRegistroEntidadeDocumentoA) = &sdtExemploFiltros.EntidadeDocumentoA when not &sdtExemploFiltros.EntidadeDocumentoA.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroDocumentoOperacionalSaidaId.IsEmpty() or MovimentoRegistroDocumentoOperacionalSaidaId.IsNull() or MovimentoRegistroTipoDocumentoSaida <> &sdtExemploFiltros.aIgnorarTipoDocumentoSaida when not &sdtExemploFiltros.aIgnorarTipoDocumentoSaida.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroTipoDocumentoSaida = &sdtExemploFiltros.TipoDocumentoSaida when not &sdtExemploFiltros.TipoDocumentoSaida.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroDocumentoOperacionalSaidaId = &sdtExemploFiltros.DocumentoSaidaId when &sdtExemploFiltros.DocumentoSaidaId > 0
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[PRCExemploAgenteDocumentoSaidaA(MovimentoRegistroDocumentoOperacionalSaidaEmpresaId, MovimentoRegistroDocumentoOperacionalSaidaId) = &sdtExemploFiltros.AgenteId when not &sdtExemploFiltros.AgenteId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[(not MovimentoRegistroDocumentoOperacionalId.IsEmpty() and not MovimentoRegistroDocumentoOperacionalId.IsNull() and 
	MovimentoRegistroDocumentoOperacionalResponsavelId = &sdtExemploFiltros.DFResponsavelId
) or
(	(MovimentoRegistroDocumentoOperacionalId.IsEmpty() or MovimentoRegistroDocumentoOperacionalId.IsNull()) and
	not MovimentoRegistroDocumentoOperacionalSaidaTipo.IsEmpty() and not MovimentoRegistroDocumentoOperacionalSaidaTipo.IsNull() and
	not MovimentoRegistroPedidoId.IsEmpty() and not MovimentoRegistroPedidoId.IsNull() and
	PRCExemploResponsavelPedidoA(MovimentoRegistroDocumentoOperacionalSaidaTipo, MovimentoRegistroPedidoExemploEmpresaId, MovimentoRegistroPedidoId, MovimentoRegistroPedidoTipo) = &sdtExemploFiltros.DFResponsavelId
)
when not &sdtExemploFiltros.DFResponsavelId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroEntidadeResponsavelId = &sdtExemploFiltros.EntidadeResponsavelId or
(	MovimentoRegistroEntidadeResponsavelBId = &sdtExemploFiltros.EntidadeResponsavelId and
	(MovimentoRegistroEntidadeResponsavelId.IsEmpty() or MovimentoRegistroEntidadeResponsavelId.IsNull())
)
when not &sdtExemploFiltros.EntidadeResponsavelId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroDocumentoOperacionalId > 0 and MovimentoRegistroDocumentoOperacionalResponsavelId in &sdtExemploFiltros.ResponsaveisExemploB when not &sdtExemploFiltros.DFResponsavelNivelBId.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroEntidadeResponsavelId in &sdtExemploFiltros.ResponsaveisExemploB or
(	MovimentoRegistroEntidadeResponsavelBId in &sdtExemploFiltros.ResponsaveisExemploB and
	(MovimentoRegistroEntidadeResponsavelId.IsEmpty() or MovimentoRegistroEntidadeResponsavelId.IsNull())
)
when not &sdtExemploFiltros.EntidadeResponsavelNivelBId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoData >= &sdtExemploFiltros.DataInicial when not &sdtExemploFiltros.DataInicial.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoData <= &sdtExemploFiltros.DataFinal when not &sdtExemploFiltros.DataFinal.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroData >= &sdtExemploFiltros.RegistroDataInicial when not &sdtExemploFiltros.RegistroDataInicial.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroData <= &sdtExemploFiltros.RegistroDataFinal when not &sdtExemploFiltros.RegistroDataFinal.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroVencimento >= &sdtExemploFiltros.VencimentoExemploInicial  when not &sdtExemploFiltros.VencimentoExemploInicial.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroVencimento <= &sdtExemploFiltros.VencimentoExemploFinal when not &sdtExemploFiltros.VencimentoExemploFinal.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoProcessoId = &sdtExemploFiltros.ProcessoId when &sdtExemploFiltros.VisaoExemploA <> VisaoExemploA.PorProcesso and not &sdtExemploFiltros.ProcessoId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[not MovimentoRegistroSaldoValor.IsEmpty() or not MovimentoRegistroDiferencaExemploA.IsEmpty() when &sdtExemploFiltros.SituacaoRegistro = SituacaoRegistro.Pendente;
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroDiferencaExemploA.IsEmpty() when &sdtExemploFiltros.SituacaoRegistro = SituacaoRegistro.Entrada
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[procExemploEntidadeTemPapel(MovimentoRegistroEntidadeEmpresaId, MovimentoRegistroEntidadeId, &sdtExemploFiltros.EntidadePapel) when not &sdtExemploFiltros.EntidadePapel.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroEntidadeSetorId = &sdtExemploFiltros.SetorExemploId when not &sdtExemploFiltros.SetorExemploId.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoProcessoGrupoId = &sdtExemploFiltros.ProcessoGrupoId when &sdtExemploFiltros.VisaoExemploA <> VisaoExemploA.PorProcesso and not &sdtExemploFiltros.ProcessoGrupoId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroDocumentoOperacionalResponsavelId in &sdtExemploFiltros.ResponsaveisDoUsuario or
MovimentoRegistroEntidadeResponsavelId in &sdtExemploFiltros.ResponsaveisDoUsuario or
(	MovimentoRegistroEntidadeResponsavelBId in &sdtExemploFiltros.ResponsaveisDoUsuario and
	(MovimentoRegistroEntidadeResponsavelId.IsEmpty() or MovimentoRegistroEntidadeResponsavelId.IsNull())
)
when not &sdtExemploFiltros.LiberaTodosResponsaveisExemplo and not &sdtExemploFiltros.semControleResponsaveisDoUsuario;
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroCondicaoOperacional = &sdtExemploFiltros.CondicaoOperacional when not &sdtExemploFiltros.CondicaoOperacional.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroTipoDocumentoOperacionalId = &sdtExemploFiltros.TipoDocumentoExemploId when not &sdtExemploFiltros.TipoDocumentoExemploId.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroDocumentoOperacionalSaidaEmpresaId > 0 and MovimentoRegistroDocumentoOperacionalSaidaId > 0 and MovimentoRegistroTipoDocumentoSaida = TipoDocumentoSaida.DocumentoOperacionalA			 
when not &sdtExemploFiltros.AgenteFlagExemploA.IsEmpty() or not &sdtExemploFiltros.ObservacaoFlagExemploB.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoAgenteId = &sdtExemploFiltros.MovimentoAgenteId when not &sdtExemploFiltros.MovimentoAgenteId.IsEmpty()
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroContaExemploBEmpresaId = &sdtExemploFiltros.RegistroContaExemploBEmpresaId 
when not &sdtExemploFiltros.RegistroContaExemploBEmpresaId.IsEmpty() and not &sdtExemploFiltros.RegistroContaExemploBId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroContaExemploBId = &sdtExemploFiltros.RegistroContaExemploBId 
when not &sdtExemploFiltros.RegistroContaExemploBId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroEntidadeTitularExemploId = &sdtExemploFiltros.EntidadeTitularExemploId or MovimentoRegistroEntidadeId = &sdtExemploFiltros.EntidadeTitularExemploId
when not &sdtExemploFiltros.EntidadeTitularExemploId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroIncluiExemploRelatorioA when &sdtExemploFiltros.RegistroIncluiExemploRelatorioA
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoProcessoIncluiExemploRelatorioB when &sdtExemploFiltros.VisaoExemploA <> VisaoExemploA.PorProcesso and &sdtExemploFiltros.IncluiExemploRelatorioB;
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[procExemploProcessoTemContaA(MovimentoProcessoEmpresaId, MovimentoProcessoId, &sdtExemploFiltros.ProcessoContaExemploEmpresaId, &sdtExemploFiltros.ProcessoContaExemploId, &sdtExemploFiltros.ProcessoContaExemploClassificacao, &sdtExemploFiltros.ProcessoContaExemploReduzido) 
when &sdtExemploFiltros.VisaoExemploA <> VisaoExemploA.PorProcesso and (not &sdtExemploFiltros.ProcessoContaExemploId.IsEmpty() or not &sdtExemploFiltros.ProcessoContaExemploClassificacao.IsEmpty() or not &sdtExemploFiltros.ProcessoContaExemploReduzido.IsEmpty());
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroTipoDocumentoOperacionalFormularioOperacional = FormularioOperacional.DocumentoExemploBancario and procExemploDocumentoIdDoRegistro(MovimentoRegistroEmpresaId, MovimentoRegistroId, false, false) > 0 
when &sdtExemploFiltros.ComDocumentoExemplo = DomainExemploSimNao.Sim;
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroTipoDocumentoOperacionalFormularioOperacional <> FormularioOperacional.DocumentoExemploBancario or procExemploDocumentoIdDoRegistro(MovimentoRegistroEmpresaId, MovimentoRegistroId, false, false) = 0 
when &sdtExemploFiltros.ComDocumentoExemplo = DomainExemploSimNao.Nao;
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoCentroResultadoId = &sdtExemploFiltros.CentroResultadoId when &sdtExemploFiltros.VisaoExemploA <> VisaoExemploA.PorProcesso and not &sdtExemploFiltros.CentroResultadoId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroDocumentoOperacionalId.IsEmpty() or MovimentoRegistroDocumentoOperacionalId.IsNull() or MovimentoRegistroDocumentoOperacionalResponsavelId <> &sdtExemploFiltros.aIgnorarDFResponsavelId when not &sdtExemploFiltros.aIgnorarDFResponsavelId.IsEmpty();
]]></Source>
      </Condition>
      <Condition>
        <Source><![CDATA[MovimentoRegistroAgrupadorOperacional = &sdtExemploFiltros.AgrupadorOperacional when not &sdtExemploFiltros.AgrupadorOperacional.IsEmpty();
]]></Source>
      </Condition>
    </Level>
    <Variables type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
      <Variable Name="sdtExemploFiltros">
        <Documentation />
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>sdtExemploFiltros</Value>
          </Property>
          <Property>
            <Name>ATTCUSTOMTYPE</Name>
            <Value>sdt:sdtExemploFiltros</Value>
          </Property>
        </Properties>
      </Variable>
      <Properties>
        <Property>
          <Name>IsDefault</Name>
          <Value>False</Value>
        </Property>
      </Properties>
    </Variables>
    <Parameters>
      <Parameter>
        <Type>Variable</Type>
        <Name>sdtExemploFiltros</Name>
        <Description>sdt Exemplo Filtros</Description>
      </Parameter>
    </Parameters>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>dsRegistrosPorMovimentoExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>ds Registros Por Movimento Exemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Sanitized read-side Generator templates

### Sanitized Generator template 1 - `GeneratorPadraoExemplo`

- Profile: a minimal `Generator` with a default category and no `DefaultType`.
- Structural evidence: this exported specimen illustrates basic standard-generator definitions.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-09-05T17:09:46.0000000Z" checksum="4cecd62b7d1aa14890e7e98e0df97a46" fullyQualifiedName="GeneratorPadraoExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="5953b12e-71f1-4020-a9b9-254085cb7061" name="GeneratorPadraoExemplo" type="ecececec-dfe0-4a57-ae8f-c6e31b0dcbc0" description="Generator Padrao Exemplo">
  <Properties>
    <Property>
      <Name>IsReorg</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>IsDefaultCategory</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>Name</Name>
      <Value>GeneratorPadraoExemplo</Value>
    </Property>
    <Property>
      <Name>IsGeneratedObject</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized Generator template 2 - `GeneratorFrontendExemplo`

- Profile: a custom, user-defined `Generator`, with no default category.
- Structural evidence: this exported specimen illustrates additional generators defined in the KB.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2023-04-17T21:48:48.0000000Z" checksum="bc1ad3de3f7892e3ac7f7afc41a65044" fullyQualifiedName="GeneratorFrontendExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="1082669b-8306-4b74-8964-552d1c688e05" name="GeneratorFrontendExemplo" type="ecececec-dfe0-4a57-ae8f-c6e31b0dcbc0" description="Generator Frontend Exemplo">
  <Properties>
    <Property>
      <Name>IsUser</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefaultCategory</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>Name</Name>
      <Value>GeneratorFrontendExemplo</Value>
    </Property>
    <Property>
      <Name>IsGeneratedObject</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized Generator template 3 - `GeneratorMobileExemplo`

- Profile: a `Generator` with `DefaultType`, representing a platform-oriented variant.
- Structural evidence: this exported Generator record carries numeric `DefaultType`; this is not guidance to define or create a Generator.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-09-05T17:09:46.0000000Z" checksum="9acc5ae74e2b862e3010bd733afae29e" fullyQualifiedName="GeneratorMobileExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="d8a1a11c-3259-4d3b-8769-76776bb25ec7" name="GeneratorMobileExemplo" type="ecececec-dfe0-4a57-ae8f-c6e31b0dcbc0" description="Generator Mobile Exemplo">
  <Properties>
    <Property>
      <Name>IsUser</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>IsDefaultCategory</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>DefaultType</Name>
      <Value>28</Value>
    </Property>
    <Property>
      <Name>Name</Name>
      <Value>GeneratorMobileExemplo</Value>
    </Property>
    <Property>
      <Name>IsGeneratedObject</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Sanitized read-side PatternSettings templates

### Sanitized PatternSettings template 1 - `PatternWebExemplo`

- Profile: a lean `PatternSettings` configuration for `Work With for Web`, with `StandardActions`, `Context`, and `Security`.
- Structural evidence: this exported specimen illustrates centralized web patterns that preserve the `<Config>` hierarchy.
- Direct evidence: later validation against the real corpus confirmed that `PatternSettings` depends on `Pattern="..."`, `ContextVariable`, `LoadProcedure`, and security references present in the environment.
- Strong inference: this template must not be treated as a self-contained object; it only produces working behavior when the corresponding pattern is registered at the target.
- Historical observation / strong inference: the earlier import-oriented note expected no useful change or an unregistered-pattern warning when the target did not recognize the cited pattern. This records a historical expectation, not an instruction or a claim that this skill imports objects.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-10-28T12:27:41.0000000Z" checksum="8fd2b9f45a2b8a0bd391eb086dfb7235" fullyQualifiedName="PatternWebExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="4bb38735-7288-3760-86ce-8d6e91fba04b" name="PatternWebExemplo" type="83476c1e-fa72-4229-9930-f51b954fca2d" description="Pattern Web Exemplo">
  <Part type="3c89746e-54b1-441a-8f3f-97cc81be06bd">
    <Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b" Version="15.0.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<Config>
  <Template />
  <Objects />
  <Theme OptionalColumn="WWOptionalColumn" GridAction="ActionAttribute" />
  <Labels WorkWithTitle="Work With &lt;Object&gt;" ViewDescription="&lt;Object&gt; - Informacao" OrderedBy="Ordenado por" PreviousTab="Tab Anterior" NextTab="Proxima Tab" RecordNotFound="Registro Nao Encontrado" />
  <Grid CellSpacing="1" CellPadding="2" />
  <MasterPages />
  <StandardActions>
    <Insert Caption="GXM_insert" Tooltip="GXM_insert" Image="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionInsert" DisabledImage="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionDisabled" ButtonClass="BtnEnter" />
    <Update Caption="GXM_update" Tooltip="GXM_update" Image="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionUpdate" DisabledImage="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionUpdateDisabled" DisabledClass="DisabledActionAttribute" ButtonClass="BtnEnter" InGridClass="UpdateAttribute" />
    <Delete Caption="GX_BtnDelete" Tooltip="GX_BtnDelete" DefaultMode="False" Image="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionDelete" DisabledImage="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionDeleteDisabled" DisabledClass="DisabledActionAttribute" ButtonClass="BtnDelete" InGridClass="DeleteAttribute" />
    <Display Caption="GXM_display" Tooltip="GXM_display" DefaultMode="False" Image="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionDisplay" DisabledImage="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionDisplayDisabled" DisabledClass="DisabledActionAttribute" InGridClass="DisplayAttribute" />
    <Export Caption="Planilha" Tooltip="Exporta como Planilha" DefaultMode="False" Image="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionExport" DisabledImage="9fb193d9-64a4-4d30-b129-ff7c76830f7e-ActionDisabled" />
    <Search Caption="GX_BtnSearch" Tooltip="GX_BtnSearch" />
  </StandardActions>
  <Context>
    <ContextVariable Name="Context" Type="447527b5-9210-4523-898b-5dccb17be60a-Context" LoadProcedure="84a12160-f59b-4ad7-a683-ea4481ac23e9-procCarregaContextoExemplo" />
  </Context>
  <Security Check="84a12160-f59b-4ad7-a683-ea4481ac23e9-procAutorizacaoExemplo" NotAuthorized="c9584656-94b6-4ccd-890f-332d11fc2c25-PainelNaoAutorizadoExemplo">
    <Parameters />
  </Security>
</Config>]]></Data>
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>PatternWebExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Pattern Web Exemplo</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized PatternSettings template 2 - `PatternDevicesExemplo`

- Profile: a `PatternSettings` configuration aimed at multiple platforms, with a dense `Platforms` block.
- Structural evidence: this exported specimen illustrates mobile/web patterns segmented by device and theme.
- Direct evidence: the `Pattern` and `Theme` references in the platforms block identify environment-specific context in the exported record; `import` here describes the recorded dependency, not an allowed action.
- Strong inference: a hypothetical names/platforms-only edit without validating `Pattern` GUIDs and `Theme` references could leave well-formed XML unusable at a target. This is a caveat about evidence, not editing guidance.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2023-04-17T22:18:24.0000000Z" checksum="567e74ca5f88b8ff29214d2163bea9da" fullyQualifiedName="PatternDevicesExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="d0f701a5-7288-3760-91b5-395d02d79889" name="PatternDevicesExemplo" type="83476c1e-fa72-4229-9930-f51b954fca2d" description="Pattern Devices Exemplo">
  <Part type="3c89746e-54b1-441a-8f3f-97cc81be06bd">
    <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="18.5.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<Config>
  <Template />
  <Platforms>
    <Platform Name="Any Platform" OS="Any Platform" Theme="78b3fa0e-174c-4b2b-8716-718167a428b5-TemaUnificadoExemplo" Predefined="True" />
    <Platform Name="Any Phone" OS="Any Platform" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="Phone" MaximumShortestBound="599" />
    <Platform Name="Any Tablet 7&quot;" OS="Any Platform" DeviceKind="Phone or Tablet" Size="Medium" Predefined="True" BoundsName="Tablet 7" MinimumShortestBound="600" MaximumShortestBound="719" />
    <Platform Name="Any Tablet 10&quot;" OS="Any Platform" DeviceKind="Phone or Tablet" Size="Large" Predefined="True" BoundsName="Tablet 10" MinimumShortestBound="720" />
    <Platform Name="Any TV" DeviceKind="TV" Size="Large" Predefined="True" />
    <Platform Name="Any Watch" DeviceKind="Watch" Size="Small" Predefined="True" />
    <Platform Name="Any Android Device" OS="Android" Theme="c804fdbd-7c0b-440d-8527-4316c92649a6-TemaAndroidExemplo" NavigationStyle="Slide" Predefined="True" />
    <Platform Name="Android Phone" OS="Android" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="Phone" MaximumShortestBound="599" />
    <Platform Name="Android Tablet 7&quot;" OS="Android" DeviceKind="Phone or Tablet" Size="Medium" Predefined="True" BoundsName="Tablet 7" MinimumShortestBound="600" MaximumShortestBound="719" />
    <Platform Name="Android Tablet 10&quot;" OS="Android" DeviceKind="Phone or Tablet" Size="Large" Predefined="True" BoundsName="Tablet 10" MinimumShortestBound="720" />
    <Platform Name="Any Apple Device" OS="Apple" NavigationStyle="Slide" Predefined="True" />
    <Platform Name="iPad" OS="Apple" DeviceKind="Phone or Tablet" Size="Large" Predefined="True" BoundsName="iPad" MinimumShortestBound="768" />
    <Platform Name="iPhone" OS="Apple" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="iPhone" MaximumShortestBound="767" />
    <Platform Name="iPhone 4&quot;" OS="Apple" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="iPhone 4&quot;" MinimumShortestBound="320" MaximumShortestBound="320" MinimumLongestBound="568" MaximumLongestBound="568" />
    <Platform Name="iPhone 3.5&quot;" OS="Apple" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="iPhone 3.5&quot;" MinimumShortestBound="320" MaximumShortestBound="320" MinimumLongestBound="480" MaximumLongestBound="480" />
    <Platform Name="iPhone 4.7&quot;" OS="Apple" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="iPhone 4.7&quot;" MinimumShortestBound="375" MaximumShortestBound="375" MinimumLongestBound="667" MaximumLongestBound="667" />
    <Platform Name="iPhone 5.5&quot; &amp; 6.1&quot;" OS="Apple" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="iPhone 5.5&quot;" MinimumShortestBound="414" MaximumShortestBound="414" MinimumLongestBound="736" MaximumLongestBound="736" />
    <Platform Name="iPhone 5.8&quot;" OS="Apple" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="iPhone 5.8&quot;" MinimumShortestBound="375" MaximumShortestBound="375" MinimumLongestBound="812" MaximumLongestBound="812" />
    <Platform Name="iPhone 6.5&quot;" OS="Apple" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="iPhone 6.5&quot;" MinimumShortestBound="414" MaximumShortestBound="414" MinimumLongestBound="896" MaximumLongestBound="896" />
    <Platform Name="Apple TV" OS="Apple" DeviceKind="TV" Size="Large" Predefined="True" />
    <Platform Name="Apple Watch" OS="Apple" DeviceKind="Watch" Size="Small" Predefined="True" />
    <Platform Name="Apple Watch 38mm" OS="Apple" DeviceKind="Watch" Size="Small" Predefined="True" BoundsName="Apple Watch 38mm" MinimumShortestBound="136" MaximumShortestBound="136" />
    <Platform Name="Apple Watch 42mm" OS="Apple" DeviceKind="Watch" Size="Small" Predefined="True" BoundsName="Apple Watch 42mm" MinimumShortestBound="156" MaximumShortestBound="156" />
    <Platform Name="Apple Watch 40mm" OS="Apple" DeviceKind="Watch" Size="Small" Predefined="True" BoundsName="Apple Watch 40mm" MinimumShortestBound="162" MaximumShortestBound="162" />
    <Platform Name="Apple Watch 44mm" OS="Apple" DeviceKind="Watch" Size="Small" Predefined="True" BoundsName="Apple Watch 44mm" MinimumShortestBound="184" MaximumShortestBound="184" />
    <Platform Name="Any Web Screen" OS="Web" Predefined="True" />
    <Platform Name="Web Phone" OS="Web" DeviceKind="Phone or Tablet" Size="Small" Predefined="True" BoundsName="Web Phone" MaximumLongestBound="599" />
    <Platform Name="Web Small" OS="Web" Size="Medium" Predefined="True" BoundsName="Web Small" MinimumLongestBound="600" MaximumLongestBound="719" />
    <Platform Name="Web Desktop" OS="Web" Size="Large" Predefined="True" BoundsName="Web Desktop" MinimumLongestBound="720" MaximumLongestBound="1199" />
    <Platform Name="Web Big Screen" OS="Web" Size="Large" Predefined="True" BoundsName="Web Big Screen" MinimumLongestBound="1200" />
  </Platforms>
  <Labels />
  <StandardActions>
    <Insert Caption="GXM_insert" />
    <Update Caption="GXM_update" />
    <Delete Caption="GX_BtnDelete" />
    <Search Caption="GX_BtnSearch" />
  </StandardActions>
</Config>]]></Data>
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>PatternDevicesExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Pattern Devices Exemplo</Value>
    </Property>
  </Properties>
</Object>
```

## Sanitized read-side DataStore templates

### Sanitized DataStore template 1 - `DataStorePadraoExemplo`

- Profile: a minimal `DataStore` with default-category properties.
- Structural evidence: this exported specimen illustrates simple datastore definitions with no extra metadata.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-09-05T17:09:46.0000000Z" checksum="fc8ae8c25e3951dcd60d9bec160667f5" fullyQualifiedName="DataStorePadraoExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="05dfb0e3-dfc1-478d-82cc-8517bebb2485" name="DataStorePadraoExemplo" type="dcdcdcdc-dfe0-4a57-ae8f-c6e31b0dcbc0" description="DataStore Padrao Exemplo">
  <Properties>
    <Property>
      <Name>IsDefaultCategory</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>Name</Name>
      <Value>DataStorePadraoExemplo</Value>
    </Property>
    <Property>
      <Name>IsGeneratedObject</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized DataStore template 2 - `DataStoreSegurancaExemplo`

- Profile: a simple `DataStore` with no default category, useful as a minimal property variation.
- Structural evidence: this exported specimen illustrates secondary or specialized datastores.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2023-04-03T11:38:41.0000000Z" checksum="3647285ee867f5d77a3101085168ed18" fullyQualifiedName="DataStoreSegurancaExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="c54239e9-16ff-40e9-ba98-b97cf2ac2ba4" name="DataStoreSegurancaExemplo" type="dcdcdcdc-dfe0-4a57-ae8f-c6e31b0dcbc0" description="DataStore Seguranca Exemplo">
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>DataStoreSegurancaExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Sanitized read-side Dashboard templates

### Sanitized Dashboard template 1 - `DashboardAtividadeExemplo`

- Profile: a `Dashboard` with `Parameters`, `Layout`, `Card`, `Chart`, and a top filter.
- Structural evidence: this exported specimen illustrates dashboards made up of indicators and charts in a main table.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="5fa995f2-62aa-4d92-8aeb-197abdd13e89" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-04-28T23:29:54.0000000Z" checksum="f647498b2bf609c1667f0a415f2fab27" fullyQualifiedName="DashboardAtividadeExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="1d0eb41a-7bcf-447e-91dc-75c207e4c2ff" name="DashboardAtividadeExemplo" type="526aba9f-a725-4bc7-b1db-0b9f92ac9550" description="Dashboard Atividade Exemplo" parent="PainelExemplo" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1">
    <Data Pattern="526aba9f-a725-4bc7-b1db-0b9f92ac9550" Version="17.0.1"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<Dashboard>
  <Parameters>
    <Parameter Name="From" DataType="Date" />
    <Parameter Name="To" DataType="Date" />
  </Parameters>
  <Layout FiltersPosition="Top">
    <MainTable>
      <Row ElementId="32">
        <Cell ElementId="4">
          <Object ElementId="5" ControlName="NovosRegistros" FrameVisible="True" FrameTitle="CHAVE_NOVOS_REGISTROS" Object="2a9e9aba-d2de-4801-ae7f-5e3819222daf-procExemploPainelTotalRegistros" OutputType="Card">
            <ObjectElement Name="CountItems" Type="Datum" Title=" " />
          </Object>
        </Cell>
        <Cell ElementId="53">
          <Object ElementId="54" ControlName="TotalSessoes" FrameVisible="True" FrameTitle="CHAVE_TOTAL_SESSOES" Object="2a9e9aba-d2de-4801-ae7f-5e3819222daf-procExemploPainelTotalSessoes" OutputType="Card">
            <ObjectElement Name="TotalSessions" Type="Datum" Title=" " />
          </Object>
        </Cell>
      </Row>
      <Row ElementId="42">
        <Cell ElementId="47">
          <Object ElementId="48" ControlName="SessoesPorAplicacao" FrameVisible="True" FrameTitle="CHAVE_SESSOES_POR_APLICACAO" Object="2a9e9aba-d2de-4801-ae7f-5e3819222daf-procExemploPainelSessoesPorAplicacao" OutputType="Chart">
            <ObjectElement Name="ApplicationId" />
            <ObjectElement Name="Sessions" Type="Datum" />
            <ObjectElement Name="ApplicationName" />
          </Object>
        </Cell>
        <Cell ElementId="43">
          <Object ElementId="44" ControlName="SessoesPorDia" FrameVisible="True" FrameTitle="CHAVE_SESSOES_POR_DIA" Object="2a9e9aba-d2de-4801-ae7f-5e3819222daf-procExemploPainelSessoesPorDia" OutputType="Chart" ChartType="Timeline" XAxisTitle="Date" YAxisTitle="Sessions">
            <ObjectElement Name="Date" />
            <ObjectElement Name="Sessions" Type="Datum" />
          </Object>
        </Cell>
      </Row>
      <Row ElementId="49">
        <Cell ElementId="51">
          <Object ElementId="52" ControlName="UsuariosRegistrados" FrameVisible="True" FrameTitle="CHAVE_USUARIOS_REGISTRADOS" Object="2a9e9aba-d2de-4801-ae7f-5e3819222daf-procExemploPainelUsuariosRegistrados" OutputType="Card">
            <ObjectElement Name="TotalUsers" Type="Datum" Title=" " />
          </Object>
        </Cell>
        <Cell ElementId="39">
          <Object ElementId="40" ControlName="SessoesAtivas" FrameVisible="True" FrameTitle="CHAVE_SESSOES_ATIVAS" Object="2a9e9aba-d2de-4801-ae7f-5e3819222daf-procExemploPainelSessoesAtivas" OutputType="Card">
            <ObjectElement Name="ActiveSessions" Type="Datum" Title=" " />
          </Object>
        </Cell>
      </Row>
    </MainTable>
    <FiltersTable>
      <Row ElementId="34">
        <Cell ElementId="35">
          <Filter ElementId="36" ControlName="FiltroPeriodo" FilterType="Range" DataType="Date" Name="From" NameLowerValue="From" NameUpperValue="To" Caption="CHAVE_PERIODO" Modified="True" />
        </Cell>
      </Row>
    </FiltersTable>
  </Layout>
</Dashboard>]]></Data>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>DashboardAtividadeExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Dashboard Atividade Exemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
  <Categories>PainelExemplo-web</Categories>
</Object>
```

## Sanitized read-side DeploymentUnit templates

### Sanitized DeploymentUnit template 1 - `DeploymentUnitExemplo`

- Profile: a `DeploymentUnit` with a few `Member` entries and one declarative main `Part`.
- Structural evidence: this exported specimen illustrates deployment units that only aggregate already-existing objects.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-02-15T14:07:19.0000000Z" checksum="a97c0da3de76a832806f0606ac08aac4" fullyQualifiedName="DeploymentUnitExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="7665e34c-f52d-430c-b113-e76e9cbdf635" name="DeploymentUnitExemplo" type="bf08dfb1-361c-4e7e-ad54-391e56e60b49" description="Deployment Unit Exemplo">
  <Part type="122ea32d-7ffa-4c47-9cbf-0829c2f060fe">
    <Definition>
      <Member object="84a12160-f59b-4ad7-a683-ea4481ac23e9-procServicoExemploA" />
      <Member object="84a12160-f59b-4ad7-a683-ea4481ac23e9-procServicoExemploB" />
      <Member object="84a12160-f59b-4ad7-a683-ea4481ac23e9-procServicoExemploC" />
      <Member object="84a12160-f59b-4ad7-a683-ea4481ac23e9-procServicoExemploD" />
    </Definition>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>DeploymentUnitExemplo</Value>
    </Property>
  </Properties>
</Object>
```


## Sanitized read-side Language templates

### Sanitized Language template 1 - `IdiomaExemploPT`

- Profile: a complete `Language` with an extensive `Translations` block.
- Structural evidence: this exported specimen illustrates language objects that centralize interface messages and translations.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="0001-01-01T00:00:00.0000000" checksum="cb04c786ee9f23279149b0a430455587" fullyQualifiedName="IdiomaExemploPT" moduleGuid="00000000-0000-0000-0000-000000000000" guid="6cc49ef5-e1eb-459c-aefd-331de0d9fa8c" name="IdiomaExemploPT" type="88313f43-5eb2-0000-0028-e8d9f5bf9588" description="Idioma Exemplo PT">
  <Part type="c23f3bb5-1e43-4c6b-b219-4717979df76a">
    <Translations>
      <Entry>
        <Message>Hide Filters</Message>
        <Type>User</Type>
        <Translation>Esconder Filtros</Translation>
      </Entry>
      <Entry>
        <Message>MORE</Message>
        <Type>User</Type>
        <Translation>MAIS</Translation>
      </Entry>
      <Entry>
        <Message>HIDE FILTERS</Message>
        <Type>User</Type>
        <Translation>Esconder Filtros</Translation>
      </Entry>
      <Entry>
        <Message>Hide</Message>
        <Type>User</Type>
        <Translation>Esconder</Translation>
      </Entry>
      <Entry>
        <Message>Show Filters</Message>
        <Type>User</Type>
        <Translation>Mostrar Filtros</Translation>
      </Entry>
      <Entry>
        <Message>SHOW FILTERS</Message>
        <Type>User</Type>
        <Translation>MOSTRAR FILTROS</Translation>
      </Entry>
      <Entry>
        <Message>ShowHide</Message>
        <Type>User</Type>
        <Translation>MostrarEsconder</Translation>
      </Entry>
      <Entry>
        <Message>Users</Message>
        <Type>User</Type>
        <Translation>Usuários</Translation>
      </Entry>
      <Entry>
        <Message>USERS</Message>
        <Type>User</Type>
        <Translation>USUÁRIOS</Translation>
      </Entry>
      <Entry>
        <Message>Users permissions</Message>
        <Type>User</Type>
        <Translation>Permissões de usuários</Translation>
      </Entry>
      <Entry>
        <Message>User</Message>
        <Type>User</Type>
        <Translation>Usuário</Translation>
      </Entry>
      <Entry>
        <Message>User Name</Message>
        <Type>User</Type>
        <Translation>Nome de Usuário</Translation>
      </Entry>
      <Entry>
        <Message>User name</Message>
        <Type>User</Type>
        <Translation>Nome de usuário</Translation>
      </Entry>
      <Entry>
        <Message>First name</Message>
        <Type>User</Type>
        <Translation>Nome</Translation>
      </Entry>
      <Entry>
        <Message>First Name</Message>
        <Type>User</Type>
        <Translation>Nome</Translation>
      </Entry>
      <Entry>
        <Message>Last name</Message>
        <Type>User</Type>
        <Translation>Sobrenome</Translation>
      </Entry>
      <Entry>
        <Message>Last Name</Message>
        <Type>User</Type>
        <Translation>Sobrenome</Translation>
      </Entry>
      <Entry>
        <Message>Authentication</Message>
        <Type>User</Type>
        <Translation>Autenticação</Translation>
      </Entry>
      <Entry>
        <Message>Authorization</Message>
        <Type>User</Type>
        <Translation>Autorização</Translation>
      </Entry>
      <Entry>
        <Message>Authorize</Message>
        <Type>User</Type>
        <Translation>Autorize</Translation>
      </Entry>
      <Entry>
        <Message>Role</Message>
        <Type>User</Type>
        <Translation>Papel</Translation>
      </Entry>
      <Entry>
        <Message>Roles</Message>
        <Type>User</Type>
        <Translation>Papéis</Translation>
      </Entry>
      <Entry>
        <Message>ROLES</Message>
        <Type>User</Type>
        <Translation>PAPÉIS</Translation>
      </Entry>
      <Entry>
        <Message>Security Policies</Message>
        <Type>User</Type>
        <Translation>Políticas de Segurança</Translation>
      </Entry>
      <Entry>
        <Message>Security policies</Message>
        <Type>User</Type>
        <Translation>Políticas de Segurança</Translation>
      </Entry>
      <Entry>
        <Message>Security policy</Message>
        <Type>User</Type>
        <Translation>Política de Segurança</Translation>
      </Entry>
      <Entry>
        <Message>Security Policy</Message>
        <Type>User</Type>
        <Translation>Política de Segurança</Translation>
      </Entry>
      <Entry>
        <Message>Connection</Message>
        <Type>User</Type>
        <Translation>Conexão</Translation>
      </Entry>
      <Entry>
        <Message>Connections</Message>
        <Type>User</Type>
        <Translation>Conexões</Translation>
      </Entry>
      <Entry>
        <Message>Authentication Types</Message>
        <Type>User</Type>
        <Translation>Tipos de Autenticação</Translation>
      </Entry>
      <Entry>
        <Message>Authentication types</Message>
        <Type>User</Type>
        <Translation>Tipos de autenticação</Translation>
      </Entry>
      <Entry>
        <Message>Event subscriptions</Message>
        <Type>User</Type>
        <Translation>Subscrição de eventos</Translation>
      </Entry>
      <Entry>
        <Message>Event Subscriptions</Message>
        <Type>User</Type>
        <Translation>Subscrição de Eventos</Translation>
      </Entry>
      <Entry>
        <Message>Repositories</Message>
        <Type>User</Type>
        <Translation>Repositórios</Translation>
      </Entry>
      <Entry>
        <Message>GAM configuration</Message>
        <Type>User</Type>
        <Translation>Configuração do GAM</Translation>
      </Entry>
      <Entry>
        <Message>GAM Configuration</Message>
        <Type>User</Type>
        <Translation>Configuração do GAM</Translation>
      </Entry>
      <Entry>
        <Message>Dashboard</Message>
        <Type>User</Type>
        <Translation>Painel</Translation>
      </Entry>
      <Entry>
        <Message>Role name</Message>
        <Type>User</Type>
        <Translation>Nome do papel</Translation>
      </Entry>
      <Entry>
        <Message>Role Name</Message>
        <Type>User</Type>
        <Translation>Nome do Papel</Translation>
      </Entry>
      <Entry>
        <Message>EDIT</Message>
        <Type>User</Type>
        <Translation>EDITAR</Translation>
      </Entry>
      <Entry>
        <Message>Edit</Message>
        <Type>User</Type>
        <Translation>Editar</Translation>
      </Entry>
      <Entry>
        <Message>Copy</Message>
        <Type>User</Type>
        <Translation>Copia</Translation>
      </Entry>
      <Entry>
        <Message>COPY</Message>
        <Type>User</Type>
        <Translation>COPIA</Translation>
      </Entry>
      <Entry>
        <Message>Active</Message>
        <Type>User</Type>
        <Translation>Ativo</Translation>
      </Entry>
      <Entry>
        <Message>Add</Message>
        <Type>User</Type>
        <Translation>Adicionar</Translation>
      </Entry>
      <Entry>
        <Message>Application Name</Message>
        <Type>User</Type>
        <Translation>Nome do Aplicativo</Translation>
      </Entry>
      <Entry>
        <Message>New User</Message>
        <Type>User</Type>
        <Translation>Novo Usuário</Translation>
      </Entry>
      <Entry>
        <Message>New users</Message>
        <Type>User</Type>
        <Translation>Novos usuários</Translation>
      </Entry>
      <Entry>
        <Message>Gender</Message>
        <Type>User</Type>
        <Translation>Gênero</Translation>
      </Entry>
      <Entry>
        <Message>Gender:</Message>
        <Type>User</Type>
        <Translation>Gênero:</Translation>
      </Entry>
      <Entry>
        <Message>Authentication type</Message>
        <Type>User</Type>
        <Translation>Tipo de autenticação</Translation>
      </Entry>
      <Entry>
        <Message>Authentication Type</Message>
        <Type>User</Type>
        <Translation>Tipo de Autenticação</Translation>
      </Entry>
      <Entry>
        <Message>Rol</Message>
        <Type>User</Type>
        <Translation>Papéls</Translation>
      </Entry>
      <Entry>
        <Message>Show users status</Message>
        <Type>User</Type>
        <Translation>Status dos Usuários</Translation>
      </Entry>
      <Entry>
        <Message>Authenticated date from</Message>
        <Type>User</Type>
        <Translation>Autenticado desde</Translation>
      </Entry>
      <Entry>
        <Message>Authenticated date to</Message>
        <Type>User</Type>
        <Translation>Autenticado até</Translation>
      </Entry>
      <Entry>
        <Message>Register date from</Message>
        <Type>User</Type>
        <Translation>Registro desde</Translation>
      </Entry>
      <Entry>
        <Message>Register date to</Message>
        <Type>User</Type>
        <Translation>Registro até</Translation>
      </Entry>
      <Entry>
        <Message>Clear</Message>
        <Type>User</Type>
        <Translation>Limpar</Translation>
      </Entry>
      <Entry>
        <Message>ClearFilters</Message>
        <Type>User</Type>
        <Translation>LimparFiltros</Translation>
      </Entry>
      <Entry>
        <Message>Apply</Message>
        <Type>User</Type>
        <Translation>Aplicar</Translation>
      </Entry>
      <Entry>
        <Message>Try a Search</Message>
        <Type>User</Type>
        <Translation>Digite Texto a Pesquisar</Translation>
      </Entry>
      <Entry>
        <Message>External Id</Message>
        <Type>User</Type>
        <Translation>Id Externo</Translation>
      </Entry>
      <Entry>
        <Message>External ID</Message>
        <Type>User</Type>
        <Translation>ID Externo</Translation>
      </Entry>
      <Entry>
        <Message>Application GUID</Message>
        <Type>User</Type>
        <Translation>GUID do Aplicativo</Translation>
      </Entry>
      <Entry>
        <Message>Company name</Message>
        <Type>User</Type>
        <Translation>Nome da Companhia</Translation>
      </Entry>
      <Entry>
        <Message>description</Message>
        <Type>User</Type>
        <Translation>descrição</Translation>
      </Entry>
      <Entry>
        <Message>Description</Message>
        <Type>User</Type>
        <Translation>Descrição</Translation>
      </Entry>
      <Entry>
        <Message>Client ID</Message>
        <Type>User</Type>
        <Translation>ID da Companhia</Translation>
      </Entry>
      <Entry>
        <Message>Client Id.</Message>
        <Type>User</Type>
        <Translation>Id da Companhia.</Translation>
      </Entry>
      <Entry>
        <Message>Client Id: Tag</Message>
        <Type>User</Type>
        <Translation>Id da Companhia: Marcação</Translation>
      </Entry>
      <Entry>
        <Message>Filters</Message>
        <Type>User</Type>
        <Translation>Filtros</Translation>
      </Entry>
      <Entry>
        <Message>Filter by</Message>
        <Type>User</Type>
        <Translation>Filtrado por</Translation>
      </Entry>
      <Entry>
        <Message>Filter User Gender</Message>
        <Type>User</Type>
        <Translation>Filtro de Gênero do Usuário</Translation>
      </Entry>
      <Entry>
        <Message>Hide filters</Message>
        <Type>User</Type>
        <Translation>Esconder filtros</Translation>
      </Entry>
      <Entry>
        <Message>Applications</Message>
        <Type>User</Type>
        <Translation>Aplicativos</Translation>
      </Entry>
      <Entry>
        <Message>Application</Message>
        <Type>User</Type>
        <Translation>Aplicativo</Translation>
      </Entry>
      <Entry>
        <Message>name</Message>
        <Type>User</Type>
        <Translation>nome</Translation>
      </Entry>
      <Entry>
        <Message>Name</Message>
        <Type>User</Type>
        <Translation>Nome</Translation>
      </Entry>
      <Entry>
        <Message>Connection name</Message>
        <Type>User</Type>
        <Translation>Nome da conexão</Translation>
      </Entry>
      <Entry>
        <Message>Connection Name</Message>
        <Type>User</Type>
        <Translation>Nome da Conexão</Translation>
      </Entry>
      <Entry>
        <Message>Keys</Message>
        <Type>User</Type>
        <Translation>Chaves</Translation>
      </Entry>
      <Entry>
        <Message>Enabled?</Message>
        <Type>User</Type>
        <Translation>Habilitado ?</Translation>
      </Entry>
      <Entry>
        <Message>type</Message>
        <Type>User</Type>
        <Translation>tipo</Translation>
      </Entry>
      <Entry>
        <Message>Type</Message>
        <Type>User</Type>
        <Translation>Tipo</Translation>
      </Entry>
      <Entry>
        <Message>Event Description</Message>
        <Type>User</Type>
        <Translation>Descrição do Evento</Translation>
      </Entry>
      <Entry>
        <Message>Event</Message>
        <Type>User</Type>
        <Translation>Evento</Translation>
      </Entry>
      <Entry>
        <Message>File name</Message>
        <Type>User</Type>
        <Translation>Nome do arquivo</Translation>
      </Entry>
      <Entry>
        <Message>File Name</Message>
        <Type>User</Type>
        <Translation>Nome do Arquivo</Translation>
      </Entry>
      <Entry>
        <Message>ClassName</Message>
        <Type>User</Type>
        <Translation>Nome da Classe</Translation>
      </Entry>
      <Entry>
        <Message>Class name</Message>
        <Type>User</Type>
        <Translation>Nome da classe</Translation>
      </Entry>
      <Entry>
        <Message>Class Name</Message>
        <Type>User</Type>
        <Translation>Nome da Classe</Translation>
      </Entry>
      <Entry>
        <Message>Method name</Message>
        <Type>User</Type>
        <Translation>Nome do método</Translation>
      </Entry>
      <Entry>
        <Message>Method Name</Message>
        <Type>User</Type>
        <Translation>Nome do Método</Translation>
      </Entry>
      <Entry>
        <Message>Delete</Message>
        <Type>User</Type>
        <Translation>Apagar</Translation>
      </Entry>
      <Entry>
        <Message>DELETE</Message>
        <Type>User</Type>
        <Translation>APAGAR</Translation>
      </Entry>
      <Entry>
        <Message>Delete permanently</Message>
        <Type>User</Type>
        <Translation>Apagar permanentemente</Translation>
      </Entry>
      <Entry>
        <Message>Deleted</Message>
        <Type>User</Type>
        <Translation>Apagado</Translation>
      </Entry>
      <Entry>
        <Message>Database version</Message>
        <Type>User</Type>
        <Translation>Versão do banco de dados</Translation>
      </Entry>
      <Entry>
        <Message>API version</Message>
        <Type>User</Type>
        <Translation>Versão da API</Translation>
      </Entry>
      <Entry>
        <Message>Default repository</Message>
        <Type>User</Type>
        <Translation>Repositório padrão</Translation>
      </Entry>
      <Entry>
        <Message>Custom email regular expression</Message>
        <Type>User</Type>
        <Translation>Expressão regular personalizada de email</Translation>
      </Entry>
      <Entry>
        <Message>Enable tracing</Message>
        <Type>User</Type>
        <Translation>Ativar rastreamento</Translation>
      </Entry>
      <Entry>
        <Message>confirm</Message>
        <Type>User</Type>
        <Translation>confirmar</Translation>
      </Entry>
      <Entry>
        <Message>Confirm</Message>
        <Type>User</Type>
        <Translation>Confirmar</Translation>
      </Entry>
    </Translations>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <InnerHtml><![CDATA[<P>&nbsp;</P>]]></InnerHtml>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>IdiomaExemploPT</Value>
    </Property>
    <Property>
      <Name>ISOLangCode</Name>
      <Value>PT</Value>
    </Property>
    <Property>
      <Name>ISOCountryCode</Name>
      <Value>BR</Value>
    </Property>
    <Property>
      <Name>Codepage</Name>
      <Value>1252</Value>
    </Property>
    <Property>
      <Name>LangDateFormat</Name>
      <Value>POR</Value>
    </Property>
    <Property>
      <Name>LangTimeFormat</Name>
      <Value>24</Value>
    </Property>
    <Property>
      <Name>LangDecimalPoint</Name>
      <Value>,</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Sanitized read-side Folder templates

### Sanitized Folder template 1 - `PastaRefinamentoExemplo`

- Profile: a minimal `Folder` with just `Name` and basic properties.
- Structural evidence: this exported specimen illustrates simple organizational folders with no extra metadata.
- Direct evidence: later validation against the real corpus confirmed that this minimal shape is consistent with real `Folder` examples.
- Strong inference: the divergence observed in the battery, where the IDE displayed the object as `Category`, does not invalidate this template; for now it should be read as an IDE semantic-recognition/naming difference.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-03-27T23:17:35.0000000Z" checksum="66a8ea763f94ed342bd2726191bed7a0" fullyQualifiedName="PastaRefinamentoExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="91314acb-c530-4e3e-9b94-db33281c99bf" name="PastaRefinamentoExemplo" type="00000000-0000-0000-0000-000000000006" description="Pasta Refinamento Exemplo">
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>PastaRefinamentoExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized Folder template 2 - `PastaProgramasPrincipaisExemplo`

- Profile: a `Folder` with additional properties such as `ShowInModelTree`, `Query`, and textual flags.
- Structural evidence: this exported specimen illustrates functional folders and grouping visible in the model tree.
- Direct evidence: this profile remains consistent with the real `Folder` examples consulted after the battery.
- Strong inference: the minimal specimen has fewer properties than specimen 2. This is a structural comparison only; neither specimen instructs creating or modifying a Folder.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2014-09-03T20:49:42.0000000Z" checksum="55629d2ccd74c89a2b72536ff9c3b4c2" fullyQualifiedName="PastaProgramasPrincipaisExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="a7ccc3ad-5574-4898-9a1d-c6b74633f3d1" name="PastaProgramasPrincipaisExemplo" type="00000000-0000-0000-0000-000000000006" description="Pasta Programas Principais Exemplo">
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>PastaProgramasPrincipaisExemplo</Value>
    </Property>
    <Property>
      <Name>ShowInModelTree</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>Query</Name>
      <Value />
    </Property>
    <Property>
      <Name>Properties</Name>
      <Value>main_program=true</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Sanitized structural-identity examples for Folder and Module

- Direct evidence: in a `Procedure` under a `Folder`, the folder's name appears in `parent`, but does not enter `fullyQualifiedName`.
- Direct evidence: in a `WebPanel` under a `Folder`, the observed pattern is the same.
- Direct evidence: in a `Module`, `fullyQualifiedName` can be qualified by the module's name.
- Direct evidence: in an object under a `Folder` inside a `Module`, the module can remain in `fullyQualifiedName`, but the folder stays restricted to `parent`.
- Strong inference: the correct choice between `Folder` and `Module` depends on reading `fullyQualifiedName`, `name`, `parent`, `parentGuid`, `parentType`, and `moduleGuid` together.

### Sanitized example 1 - `PRCExemploFolderA`

- Profile: a `Procedure` in a `Folder`, with no folder prefix in `fullyQualifiedName`.
- Structural evidence: an exported specimen showing why the observed structure does not serialize the `Folder.Procedure` type as if the real container were only a `Folder`.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="GUID_PASTA_PROCEDURES" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2016-09-30T03:43:09.0000000Z" checksum="8b29660f938eb825e90dbc5b42faa4d0" fullyQualifiedName="PRCExemploFolderA" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="GUID_PRC_EXEMPLO_FOLDER_A" name="PRCExemploFolderA" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="Procedure Exemplo Folder A" parent="PastaProceduresExemplo" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Source><![CDATA[&Data = ctod(&DatetimeTexto)]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
</Object>
```

### Sanitized example 2 - `WPExemploFolderA`

- Profile: a `WebPanel` in a `Folder`, with no folder prefix in `fullyQualifiedName`.
- Structural evidence: an exported specimen illustrating that a folder organizes the object through `parent`, not through an automatic namespace.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="GUID_PASTA_EXEMPLO_A" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-04-09T11:18:17.0000000Z" checksum="1accc2250b948d6c23384fccaccbcc3f" fullyQualifiedName="WPExemploFolderA" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="GUID_WP_EXEMPLO_FOLDER_A" name="WPExemploFolderA" type="c9584656-94b6-4ccd-890f-332d11fc2c25" description="WebPanel Exemplo Folder A" parent="PastaExemploA" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
    <Source><![CDATA[<GxMultiForm rootId="2"><Form id="2" type="layout"><detail /></Form></GxMultiForm>]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
</Object>
```

### Sanitized example 3 - `PRCExemploModuloA`

- Profile: a `Procedure` directly under a `Module`, with module qualification in `fullyQualifiedName`.
- Structural evidence: an exported contrast showing that module-based qualification cannot be extrapolated to `Folder`.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="GUID_MODULE_GENERAL_SERVICES" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2019-07-26T18:37:24.0000000Z" checksum="ca9dbb87d6d7a0949fb671454d480699" fullyQualifiedName="ModuloExemplo.Services.PRCExemploModuloA" moduleGuid="GUID_MODULE_GENERAL_SERVICES" guid="GUID_PRC_EXEMPLO_MODULO_A" name="PRCExemploModuloA" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="Procedure Exemplo Modulo A" parent="ModuloExemplo.Services" parentType="c88fffcd-b6f8-0000-8fec-00b5497e2117">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Source><![CDATA[Do case
Endcase]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
</Object>
```

### Sanitized example 4 - `PRCExemploFolderDentroModuloA`

- Profile: a `Procedure` in a `Folder` inside a `Module`; the module remains in `fullyQualifiedName`, but the folder stays in `parent`.
- Structural evidence: an exported counter-example showing why promoting a folder name into the qualified name would be incorrect here.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="GUID_PASTA_SYNC_EXEMPLO" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2016-01-04T13:40:16.0000000Z" checksum="19894cc8d64aaf194ad4af2e684da9c6" fullyQualifiedName="ModuloExemplo.Services.PRCExemploFolderDentroModuloA" moduleGuid="GUID_MODULE_GENERAL_SERVICES" guid="GUID_PRC_EXEMPLO_FOLDER_DENTRO_MODULO_A" name="PRCExemploFolderDentroModuloA" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="Procedure Exemplo Folder Dentro Modulo A" parent="ModuloExemplo.Services.PastaSyncExemplo" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Source><![CDATA[]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
</Object>
```

## Minimal sanitized `Source` compatibility examples

- `Purpose`: record minimal `Source` patterns that this trail already supports methodologically, with no dependence on a large KB corpus.
- Read-side rule: these examples document only the `Source` patterns visible in this trail; they do not authorize creating or changing objects in a new or sparsely populated KB. A local corpus may provide confirmation or a tiebreaker when reading.
- Read-side observation: when analyzing an operator, function, conversion, or string/numeric pattern in a `Source`, compare it with these documented patterns or another example in this base; this does not prescribe editing a `Source`.
- Read-side qualification: absence of an operator, function, or conversion here does not prove an absolute ban, but it also does not make a pattern ready to rely on without another explicit methodological basis from this trail, and it does not establish any authorization to materialize or import a snippet.

### Minimal pattern 1 - a simple input/output `parm(...)`

- `Structural evidence`: the minimal form already documented in this trail for a simple `Procedure` signature.

```geneXus
parm(out:&DomainExemploTipoOperacaoA);
parm(in:ContextoAId, in:ContextoBId);
```

### Minimal pattern 2 - numeric-to-text conversion with explicit adjustment

- `Structural evidence`: numeric-to-text conversion and string assembly, already documented in this base through a sanitized `DataProvider` template.

```geneXus
Chave = RegistroId.ToString()
Valor = "CtxA:" + RegistroEmpresaId.ToString().Trim() +
" Chave: " + RegistroId.ToFormattedString() +
"| Seq:" + SequenciaExemplo.ToString()
```

### Minimal pattern 3 - string and enumeration in textual composition

- `Structural evidence`: textual composition with `Trim()` and `EnumerationDescription()` already appears in a sanitized template documented in this base.

```geneXus
" | B:" + procRightExemplo(PessoaBId.ToString()," ",10) +
"-" + PessoaBNome.Trim() + " (" + TipoRegistro.EnumerationDescription() + ")"
```

### Minimal pattern 4 - a boolean condition with `IsNull()` and a `when` guard

- `Structural evidence`: a filter/condition pattern already documented in this base for a materialized condition's `Source`.

```geneXus
RegistroMovimentoCancelado = false or RegistroMovimentoCancelado.IsNull() when not &SomenteCancelados
MovimentoEmpresaId = &sdtExemploFiltros.EmpresaExemploId when not &sdtExemploFiltros.EmpresaExemploId.IsEmpty()
```

### Current methodological limit

- `Direct evidence`: this section only anchors a minimal set of patterns already documented within this trail itself.
- Read-side qualification: an operator, function, or conversion absent from an explicit rule, sanitized example, or documented template here lacks evidence for a conclusion based on plausibility alone; no consolidation or object change is directed.

## Sanitized read-side Stencil templates

### Sanitized Stencil template 1 - `StencilCardResumoExemplo`

- Profile: a `Stencil` with a `Source` rich in `Controls`, an embedded `Screenshot`, and a visual card block. The `Screenshot` attribute holds two `@`-separated base64 PNG payloads; the image data is omitted here.
- Structural evidence: this exported specimen illustrates declarative stencils that embed a complete visual layout in `CDATA`.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="fdf9baf8-1249-463c-b803-76e914f87c2d" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-04-28T23:33:55.0000000Z" checksum="5c96cea3449e70000bfeb99a5623d2fa" fullyQualifiedName="StencilCardResumoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="744d7301-c4c1-46af-afdf-5e55bcb4ae80" name="StencilCardResumoExemplo" type="624a8b31-36f0-4292-adba-2d270d1e3537" description="Stencil Card Resumo Exemplo" parent="ColecaoStencilExemplo" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="3dd92fe7-b095-44d3-9fa0-8488fa3f0c68">
    <Source><![CDATA[<Root Screenshot="data:image/png;base64,(omitted)@data:image/png;base64,(omitted)"><Controls><table class="card" tableType="Responsive" responsiveSizes="[]" layoutType="SD"><row><cell><table controlName="TableGeneralTitle" class="card-heading" tableType="Responsive"><row><cell><textblock controlName="TBTitleGeneral" caption="Resumo" class="attribute-label" /></cell></row></table></cell></row><row><cell><table controlName="TableDataGeneral" class="card-body" tableType="Responsive" IsSlot="True" /></cell></row></table><table class="card bg-white" tableType="Responsive" responsiveSizes="[]" layoutType="Web"><row><cell><table controlName="TableGeneralTitle" class="card-heading" tableType="Responsive"><row><cell><textblock controlName="TBTitleGeneral" caption="EXEMPLO_General" class="" /></cell></row></table></cell></row><row><cell><table controlName="TableDataGeneral" class="card-body" tableType="Responsive" IsSlot="True" /></cell></row></table></Controls></Root>]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>EXEMPLO_DataCard</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>GAM Data  Card</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
  <Categories>ColecaoStencilExemplo-web</Categories>
</Object>
```

### Sanitized Stencil template 2 - `StencilCabecalhoListaExemplo`

- Profile: a header `Stencil` with actions, search, an image, and a declared variable. Its `Screenshot` image data is omitted here, as in template 1.
- Structural evidence: this exported specimen illustrates stencils with interactive controls and embedded `Variables`.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="fdf9baf8-1249-463c-b803-76e914f87c2d" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-04-28T23:34:41.0000000Z" checksum="9d5d14b2efafae0b5b00b33d3e8ec0a1" fullyQualifiedName="StencilCabecalhoListaExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="39ae3b48-9e9f-4ae8-ae2c-94a0ac238a4b" name="StencilCabecalhoListaExemplo" type="624a8b31-36f0-4292-adba-2d270d1e3537" description="Stencil Cabecalho Lista Exemplo" parent="ColecaoStencilExemplo" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="3dd92fe7-b095-44d3-9fa0-8488fa3f0c68">
    <Source><![CDATA[<Root Screenshot="data:image/png;base64,(omitted)@data:image/png;base64,(omitted)"><Controls><table class="Flex" tableType="Responsive" responsiveSizes="[]" layoutType="SD"><row><cell cellClass="stack-bottom-xxl"><table controlName="TableActions" tableType="Flex" justifyContent="Flex End"><row rowHeightWeb="61px"><cell><textblock controlName="Title" caption="Title" class="Title" /></cell><cell cellClass="inline-right-xl" hAlign="Right" flexGrow="0"><action controlName="AddNew" onClickEvent="'AddNew'" caption="Adicionar" class="button" /></cell><cell cellClass="inline-right-xl" hAlign="Right" flexGrow="0"><data attribute="&amp;Search" labelPosition="None" labelCaption="" class="AttributeSearch" inviteMessage="Tente uma busca" controlNameForStencil="&amp;Search" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;AutoResize&lt;/Name&gt;&lt;Value&gt;False&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;GxWidth&lt;/Name&gt;&lt;Value&gt;30chr&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" /></cell><cell hAlign="Right" flexGrow="0" alignSelf="Center"><image controlName="ToggleFilters" image="9fb193d9-64a4-4d30-b129-ff7c76830f7e-PageLast" class="Image-20" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;eventGX&lt;/Name&gt;&lt;Value&gt;'Hide'&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;width&lt;/Name&gt;&lt;Value /&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;title&lt;/Name&gt;&lt;Value&gt;GXM_first&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" /></cell></row></table></cell></row></table><table class="" tableType="Responsive" responsiveSizes="[]" layoutType="Web"><row><cell cellClass="stack-bottom-xxl"><table controlName="TableActions" tableType="Flex" flexWrap="Wrap" justifyContent="Flex End" alignItems="Center"><row rowHeightWeb="61px"><cell minHeight="30"><textblock controlName="Title" caption="EXEMPLO_Titulo" class="Title" /></cell><cell cellClass="inline-right-xl" hAlign="Right" flexGrow="0" minHeight="30"><action controlName="AddNew" onClickEvent="'AddNew'" caption="EXEMPLO_Adicionar" class="button Primary" /></cell><cell cellControlName="CellSearch" cellClass="" hAlign="Right" flexGrow="0" minHeight="30"><data attribute="&amp;Search" labelPosition="None" labelCaption="" class="AttributeSearch" inviteMessage="EXEMPLO_TenteUmaBusca" controlNameForStencil="&amp;Search" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;AutoResize&lt;/Name&gt;&lt;Value&gt;False&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;GxWidth&lt;/Name&gt;&lt;Value&gt;30chr&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" /></cell><cell cellClass="inline-left-xl" hAlign="Right" flexGrow="0" minHeight="30"><image controlName="ToggleFilters" image="9fb193d9-64a4-4d30-b129-ff7c76830f7e-TemaExemplo.filter" class="Image-20 color-primary" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;eventGX&lt;/Name&gt;&lt;Value&gt;'Hide'&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;width&lt;/Name&gt;&lt;Value /&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;title&lt;/Name&gt;&lt;Value&gt;Filters&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" /></cell></row></table></cell></row></table></Controls><Variables><Variable Name="Search"><Properties><Property><Name>Name</Name><Value>Search</Value></Property><Property><Name>OBJ_TYPE</Name><Value>id_OTYPE_VAR</Value></Property><Property><Name>idBasedOn</Name><Value>Domain:GAMUserIdentification, SegurancaExemplo</Value></Property></Properties></Variable></Variables></Root>]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>EXEMPLO_HeaderWW</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>GAM Header WW</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
  <Categories>ColecaoStencilExemplo-web</Categories>
</Object>
```

## Sanitized read-side File templates

### Sanitized File template 1 - `ArquivoImagemExemplo_gif`

- Profile: a short `File` with a small `base64Binary` and extraction properties in `Resources`.
- Historical observation: the exported File record contains a compact binary asset and extraction properties. This describes the record; it is not an instruction to attach or package an asset.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2024-09-28T20:51:45.0000000Z" checksum="b667dcf6150444093ca6130acc038fd1" fullyQualifiedName="ArquivoImagemExemplo_gif" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="f33ac53a-282e-491b-b748-79f213e2dbe6" name="ArquivoImagemExemplo_gif" type="1132ac08-290f-4fd1-bd18-64777b7329d1" description="Arquivo Imagem Exemplo">
  <Part type="9b6155f9-f286-4ed5-bd15-67672e8ea320">
    <Data>
      <base64Binary>R0lGODlhCgBQAIAAAAAAAP///yH5BAUUAAEALAAAAAAKAFAAAAIahI+py+0Po5y02ouz3rz7D4biSJbmiabqihUAOw==</base64Binary>
    </Data>
    <Properties>
      <Property>
        <Name>FileName</Name>
        <Value>imagem-exemplo.gif</Value>
      </Property>
      <Property>
        <Name>FileExtension</Name>
        <Value>.gif</Value>
      </Property>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>ArquivoImagemExemplo_gif</Value>
    </Property>
    <Property>
      <Name>NetExtract</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>NetExtractFolder</Name>
      <Value>Resources\\arquivo-exemplo</Value>
    </Property>
    <Property>
      <Name>NetCoreExtract</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>NetCoreExtractFolder</Name>
      <Value>Resources\\arquivo-exemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized File template 2 - `ArquivoConfiguracaoExemplo_props`

- Profile: a small textual `File` in `.props`, still stored via `base64Binary`.
- Historical observation: the exported File record contains configuration/build-support file content and extraction properties. This is corpus evidence, not a build, packaging, extraction, or object-creation instruction.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-05-14T20:38:37.0000000Z" checksum="c60dc61999093d19c1b8571fb805f188" fullyQualifiedName="ArquivoConfiguracaoExemplo_props" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="f818bc6d-1bb8-4459-88f4-4c781953252f" name="ArquivoConfiguracaoExemplo_props" type="1132ac08-290f-4fd1-bd18-64777b7329d1" description="ArquivoConfiguracaoExemplo.props">
  <Part type="9b6155f9-f286-4ed5-bd15-67672e8ea320">
    <Data>
      <base64Binary>PFByb2plY3Q+DQoJPEl0ZW1Hcm91cD4NCgkJPFBhY2thZ2VSZWZlcmVuY2UgSW5jbHVkZT0iQm91bmN5Q2FzdGxlLkNyeXB0b2dyYXBoeSIgVmVyc2lvbj0iMi40LjAiLz4NCgkJPFBhY2thZ2VSZWZlcmVuY2UgSW5jbHVkZT0iU3lzdGVtLlNlY3VyaXR5LkNyeXB0b2dyYXBoeS5YbWwiIFZlcnNpb249IjguMC4wIi8+DQoJPC9JdGVtR3JvdXA+DQo8L1Byb2plY3Q+</base64Binary>
    </Data>
    <Properties>
      <Property>
        <Name>FileName</Name>
        <Value>ArquivoConfiguracaoExemplo.props</Value>
      </Property>
      <Property>
        <Name>FileExtension</Name>
        <Value>.props</Value>
      </Property>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>ArquivoConfiguracaoExemplo_props</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>SignXml.props</Value>
    </Property>
    <Property>
      <Name>NetCoreExtract</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>NetCoreExtractFolder</Name>
      <Value>..\\build-exemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```
