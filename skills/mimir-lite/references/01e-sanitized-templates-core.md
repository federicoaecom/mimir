# 01e - Sanitized Templates: Core

## Document role
empirical structural reference

## Purpose
Bring together sanitized XML examples as structural evidence for core types and recurring contracts observed in the XPZ trail. These examples support reading and comparison; they are not instructions to create, clone, package, import, or build GeneXus objects. The separate sync workflow may materialize an IDE-exported XPZ into the XML corpus; that read-side corpus synchronization is distinct from materializing GeneXus objects from these examples.

## Complete sanitized Procedure and DataProvider templates

- Direct evidence: this base now contains 2 complete sanitized `Procedure` XML templates and 2 `DataProvider` ones.
- Strong inference: this set complements the already-existing `WebPanel` and `Transaction` examples, providing additional structural evidence for these two types alongside queries against the raw corpus.
- Hypothesis: for a very dense `Procedure` or a `DataProvider` with a very specialized output, a further comparable raw template may still be needed.

### Sanitized Procedure template 1 - `PRCExemploMinimo`

- Profile: a minimal `Procedure`, with the recurring `Part` inventory and almost no internal content.
- Structural observation: its minimal content makes the type's recurring `Part` inventory and structural envelope easy to inspect.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="624fa1ae-7a20-4d68-bc8a-b54254fa3ce7" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-03-27T22:31:45.0000000Z" checksum="ac868db7f602aeb0f9d9f1c51a919527" fullyQualifiedName="PRCExemploMinimo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="d6ecd738-8c9a-4361-9a4e-f638fbd98067" name="PRCExemploMinimo" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="Procedure Exemplo Minima" parent="PastaExemploProcedure" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Properties />
  </Part>
  <Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
    <Properties />
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Properties />
  </Part>
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Properties />
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Properties />
  </Part>
  <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
    <Help>
      <HelpItem>
        <Language>88313f43-5eb2-0000-0028-e8d9f5bf9588-Portuguese</Language>
        <Content />
      </HelpItem>
    </Help>
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
      <Value>PRCExemploMinimo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>

```

### Sanitized Procedure template 2 - `PRCExemploParm`

- Profile: a short `Procedure` with `parm(out:...)` and a domain-based variable.
- Structural observation: the example pairs a simple `parm(out:...)` signature with its domain-based variable.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="988004e2-6090-42c3-9603-c073172b75a6" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2017-11-30T13:14:40.0000000Z" checksum="f03125659ba83a8972206dfeb9b0dfc8" fullyQualifiedName="PRCExemploParm" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="96caabbb-924a-4d2b-83f9-62e5e192608a" name="PRCExemploParm" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="Procedure Exemplo Parm" parent="PastaExemploProcedure" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Properties />
  </Part>
  <Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
    <Properties />
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[parm(out:&DomainExemploTipoOperacaoA);
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Properties />
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="DomainExemploTipoOperacaoA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>DomainExemploTipoOperacaoA</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:DomainExemploTipoOperacaoA</Value>
        </Property>
      </Properties>
    </Variable>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
    <Help>
      <HelpItem>
        <Language>88313f43-5eb2-0000-0028-e8d9f5bf9588-Portuguese</Language>
        <Content />
      </HelpItem>
    </Help>
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
      <Value>PRCExemploParm</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized excerpt of a large Procedure - `PRCExemploRelatorioGrande`

- Profile: the full dense `Procedure` contains `if/endif`, `do case/endcase`, and structural `//if` comments in its `Source`; this displayed excerpt preserves only `if/endif` and `//if`.
- Structural observation: the excerpt preserves human structural comments that support IDE readability and inherited legibility.
- Direct evidence: in the real object examined in the KB, the `//if` comments appear as reading support in blocks with relevant nesting and visual closing.
- Structural reading note: the excerpt shows why a block's closing and its immediate visual outline are useful context when assessing inherited structural comments.
- Structural observation: this excerpt visibly illustrates an `If/EndIf` pair and structural `//if` comments; the full Procedure, beyond this excerpt, also contains a `Do Case/EndCase` pair.
- Structural observation: the sample shows the conservative syntax and nearby-block comparison useful when analyzing how a large `Source` is organized.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="3fd96d57-5faf-4631-a0d8-af1d7a4fcee1" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-04-16T18:05:46.0000000Z" checksum="SANITIZEDCHECKSUM" fullyQualifiedName="PRCExemploRelatorioGrande" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="SANITIZED-GUID" name="PRCExemploRelatorioGrande" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="Procedure Exemplo Relatorio Grande" parent="Volume" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Source><![CDATA[//if &ComSubmit
if &ComSubmit

    procExemploAbreContexto(&EmpresaExemploId, "")
    procExemploAbreContextoUsuario(&UsuarioId, "")

endif

&AgoraNaEmpresa = procExemploAgora(&EmpresaExemploId)

//if &Finalizando
if not &Finalizando

    //if &ComPrecoDeEntrada or &ComPrecoDeVenda
    if &ComPrecoDeEntrada or &ComPrecoDeVenda
        &Aviso = "Exemplo de bloco com comentario estrutural preservado"
    endif

endif]]></Source>
  </Part>
</Object>
```

### Sanitized DataProvider template 1 - `DPExemploLista`

- Profile: a simple `DataProvider` with a collection output declared right in the `Source`.
- Structural observation: the sample shows a small collection output based on a repeated structure.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="fbf65a0f-f5fe-40b5-9328-ac966656d448" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2009-07-22T19:06:02.0000000Z" checksum="2c78d22a9661e372b2cefb9d31d6018c" fullyQualifiedName="DPExemploLista" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="9fed987b-56be-4e31-9e9f-09f7c9b959c3" name="DPExemploLista" type="2a9e9aba-d2de-4801-ae7f-5e3819222daf" description="DPExemploLista" parent="PastaExemploDP" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="1d8aeb5a-6e98-45a7-92d2-d8de7384e432">
    <Source><![CDATA[SdtExemploLista
{
	SdtExemploListaItem
	{
		RValnum =1
		RValtext = 'RegiaoA'
		RCountry = 'PaisA'
	}
	SdtExemploListaItem
	{
		RValnum =1
		RValtext = 'RegiaoB'
		RCountry = 'PaisB'
	}
	SdtExemploListaItem
	{
		RValnum =1
		RValtext = 'RegiaoC'
		RCountry = 'PaisC'
	}
	SdtExemploListaItem
	{
		RValnum =4
		RValtext = 'RegiaoD'
		RCountry = 'PaisD'
	}
	SdtExemploListaItem
	{
		RValnum =1
		RValtext = 'RegiaoE'
		RCountry = 'PaisE'
	}
	SdtExemploListaItem
	{
		RValnum =2
		RValtext = 'RegiaoF'
		RCountry = 'PaisF'
	}
	SdtExemploListaItem
	{
		RValnum =1
		RValtext = 'RegiaoG'
		RCountry = 'PaisG'
	}
	SdtExemploListaItem
	{
		RValnum =1
		RValtext = 'RegiaoH'
		RCountry = 'PaisH'
	}
	SdtExemploListaItem
	{
		RValnum =1
		RValtext = 'RegiaoI'
		RCountry = 'PaisI'
	}
}
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Properties />
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
    <Help>
      <HelpItem>
        <Language>88313f43-5eb2-0000-0028-e8d9f5bf9588-Portuguese</Language>
        <Content />
      </HelpItem>
    </Help>
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
      <Value>DPExemploLista</Value>
    </Property>
    <Property>
      <Name>OutputSDT</Name>
      <Value>447527b5-9210-4523-898b-5dccb17be60a-SdtExemploLista</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized DataProvider template 2 - `DPExemploParm`

- Profile: a `DataProvider` with `parm(in:...)`, `OutputCollection=True`, and richer textual composition in the `Source`.
- Structural observation: the sample shows a parameter-driven `DataProvider` with collection output.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="79a956f5-e947-44fb-9165-5914625207c6" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2019-11-18T18:35:14.0000000Z" checksum="d7d87280290ffc92084066e33abd7c51" fullyQualifiedName="DPExemploParm" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="1ee0e754-a66a-47bf-a7aa-3af9a0da28c0" name="DPExemploParm" type="2a9e9aba-d2de-4801-ae7f-5e3819222daf" description="DataProvider Exemplo Parm" parent="PastaExemploDP" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="1d8aeb5a-6e98-45a7-92d2-d8de7384e432">
    <Source><![CDATA[SdtExemploChaveValor order ContextoAId, ContextoBId, SequenciaExemplo, RegistroId
{
	Chave = RegistroId.ToString()
	
	Valor = "CtxA:" + RegistroEmpresaId.ToString().Trim() + 
	" Chave: " + RegistroId.ToFormattedString() +
	"| Seq:" + SequenciaExemplo.ToString() + 
	" | A:" + procLeftExemplo(PessoaAId.ToString()," ",10) +
	" | B:" + procRightExemplo(PessoaBId.ToString()," ",10) +
	"-" + PessoaBNome.Trim() + " (" + TipoRegistro.EnumerationDescription() + ")"
	
}
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[parm(in:ContextoAId, in:ContextoBId);
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
    <Help>
      <HelpItem>
        <Language>88313f43-5eb2-0000-0028-e8d9f5bf9588-Portuguese</Language>
        <Content />
      </HelpItem>
    </Help>
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
      <Value>DPExemploParm</Value>
    </Property>
    <Property>
      <Name>OutputSDT</Name>
      <Value>447527b5-9210-4523-898b-5dccb17be60a-SdtExemploChaveValor</Value>
    </Property>
    <Property>
      <Name>OutputCollection</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Complete sanitized Panel and API templates

- Direct evidence: the corpus used in this base contains 7 Panel objects and 1 API object.
- Strong inference: given the low cardinality, it makes more sense to document complete representative templates than to try opening many fine-grained families.
- Structural observation: the annexes show `Object/@type`, the `Part` inventory, and internal hierarchy in the sampled Panel and API objects.

### Sanitized Panel template 1 - `PanelExemploNaoAutorizado`

- Profile: a lean mobile Panel, with a PatternPart, a simple layout, and few events.
- Structural observation: the sample shows a short message/input Panel with a PatternPart structure.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="d8c5213a-038e-4c3d-8cad-c4f38c6c10ff" user="SANITIZED" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-08-03T13:19:24.0000000Z" checksum="05f72ad114b0959c3b1154503e4e7ada" fullyQualifiedName="PanelExemploNaoAutorizado" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="0492a00a-5a72-44bb-8fe5-6468b143a1db" name="PanelExemploNaoAutorizado" type="d82625fd-5892-40b0-99c9-5c8559c197fc" description="Nao Autorizado" parent="PastaExemploPanel" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="b4378a97-f9b2-4e05-b2f8-c610de258402">
    <PatternPart type="a51ced48-7bee-0001-ab12-04e9e32123d1">
      <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="17.11.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <notifications />
  <level id="9c3fa622-c8e3-419b-be3f-659de559bbd2" name="Level">
    <detail variables="&lt;Variables&gt;&lt;Variable Id=&quot;9&quot; Name=&quot;Password&quot; Description=&quot;Password&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Password&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Description&lt;/Name&gt;&lt;Value&gt;Password&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;idBasedOn&lt;/Name&gt;&lt;Value&gt;Domain:AuthPassword, SANITIZEDSecurityCommon&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/Variable&gt;&lt;Variable Id=&quot;10&quot; Name=&quot;UserName&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;UserName&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;idBasedOn&lt;/Name&gt;&lt;Value&gt;Domain:AuthUserIdentification, SANITIZEDSecurityCommon&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/Variable&gt;&lt;Variable Id=&quot;11&quot; Name=&quot;AuthRepository&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;AuthRepository&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;exo:AuthRepository, SANITIZEDSecurity&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/Variable&gt;&lt;StandardVariable Id=&quot;4&quot; Name=&quot;Pgmdesc&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Pgmdesc&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Character&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Length&lt;/Name&gt;&lt;Value&gt;256&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;AttMaxLen&lt;/Name&gt;&lt;Value&gt;256&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;StandardVariable Id=&quot;3&quot; Name=&quot;Pgmname&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Pgmname&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Character&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Length&lt;/Name&gt;&lt;Value&gt;128&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;AttMaxLen&lt;/Name&gt;&lt;Value&gt;128&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;StandardVariable Id=&quot;2&quot; Name=&quot;Time&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Time&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Character&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Length&lt;/Name&gt;&lt;Value&gt;8&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;AttMaxLen&lt;/Name&gt;&lt;Value&gt;8&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;StandardVariable Id=&quot;1&quot; Name=&quot;Today&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Today&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Date&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;/Variables&gt;" events="Event Start&#xA;&#x9;&amp;AuthRepository = AuthRepository.Get()&#xA;&#x9;Do Case&#xA;&#x9;Case &amp;AuthRepository.UserIdentification = AuthRepositoryUserIdentifications.Name&#xA;&#x9;&#x9;&amp;UserName.Caption = AuthRepositoryUserIdentifications.EnumerationDescription(AuthRepositoryUserIdentifications.Name)&#xA;&#x9;Case &amp;AuthRepository.UserIdentification = AuthRepositoryUserIdentifications.EMail&#xA;&#x9;&#x9;&amp;UserName.Caption = AuthRepositoryUserIdentifications.EnumerationDescription(AuthRepositoryUserIdentifications.EMail)&#xA;&#x9;Case &amp;AuthRepository.UserIdentification = AuthRepositoryUserIdentifications.NameEmail&#xA;&#x9;&#x9;&amp;UserName.Caption = AuthRepositoryUserIdentifications.EnumerationDescription(AuthRepositoryUserIdentifications.NameEmail)&#xA;&#x9;EndCase&#xA;Endevent&#xA;&#xA;&#xA;Event 'BtnEntrar'&#xA;&#x9;Composite&#xA;&#x9;&#x9;SANITIZED.Common.UI.Progress.ShowWithTitle(&quot;Conectando...&quot;)&#xA;&#x9;&#x9;SANITIZED.SD.Actions.Entrar(&amp;UserName, &amp;Password)&#xA;&#x9;&#x9;SANITIZED.Common.UI.Progress.Hide()&#xA;&#x9;&#x9;Return&#xA;&#x9;EndComposite&#xA;EndEvent&#xA;&#xA;&#xA;Event 'Back'&#xA;&#x9;Return&#xA;Endevent&#xA;">
      <layout id="78852907-2ff5-5ed0-aaf2-079ff7de3e65" Type="View">
        <table id="b32d02f2-0dd3-4ff1-ab64-a3e660c6d75e" controlName="MainTable" columnsStyle="10dip;100%;10dip" responsiveSizes="[]">
          <row id="9c151a94-80d2-46f8-96c6-9116c7daabd3" rowHeight="50dip">
            <cell id="4ca3501c-1d5f-44c0-9a2f-d35dc46d120b" />
            <cell id="a6049a5b-7a80-4dbf-be0e-823046c2135b" hAlign="Center" vAlign="Middle">
              <textblock controlName="TBMsg" caption="Nao autorizado: acesso negado." enabled="False" />
            </cell>
            <cell id="4eb8110b-d034-4ff5-b1e6-52437c4e7d96" />
          </row>
          <row id="d752f865-4ff5-421f-86be-611fe83c74cb" rowHeight="15dip" />
          <row id="fe634880-d9ac-4961-925d-b5af54956e19" rowHeight="pd">
            <cell id="8852d807-ce19-43b1-b14b-9d87331132d6" />
            <cell id="6b999592-fc89-46e3-8f85-e51d86bfb41f">
              <data attribute="&amp;UserName" labelCaption="Name" inviteMessage="" />
            </cell>
          </row>
          <row id="761dbdcc-a547-4dae-9d08-a1cfd3f46eaf" rowHeight="pd">
            <cell id="43d045c0-a1e1-4ddb-ae47-10dbaf4bb4b3" />
            <cell id="32839ce6-9945-47b0-a77f-06af61e9d68b">
              <data attribute="&amp;Password" inviteMessage="" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;idEnableShowPasswordHint&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" />
            </cell>
          </row>
          <row id="f65f348a-0497-412e-8a47-c406ced202cc" rowHeight="15dip" />
          <row id="cd2a293a-0b52-46a4-933a-74e67e355b2e" rowHeight="pd">
            <cell id="9d22a783-969c-4a9a-8254-a92485853853" />
            <cell id="af4ba31d-e944-4544-a51c-ac5f43a4c47d" hAlign="Center" vAlign="Middle">
              <action controlName="BtnEntrar" onClickEvent="'BtnEntrar'" caption="ENTRAR" class="button-primary" />
            </cell>
          </row>
        </table>
      </layout>
    </detail>
  </level>
</instance>]]></Data>
      <Properties>
        <Property>
          <Name>IsDefault</Name>
          <Value>False</Value>
        </Property>
      </Properties>
    </PatternPart>
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
      <Value>PanelExemploNaoAutorizado</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Nao Autorizado</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>AndroidBaseStyle</Name>
      <Value>AndroidBaseStyleDark</Value>
    </Property>
    <Property>
      <Name>CacheEnabled</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>IntegratedSecurityLevel</Name>
      <Value>SecurityNone</Value>
    </Property>
    <Property>
      <Name>IntegratedSecurityPermissionPrefix</Name>
      <Value>PanelExemploNaoAutorizado</Value>
    </Property>
  </Properties>
  <Categories>Panel_Samples-sd</Categories>
</Object>

```

### Sanitized Panel template 2 - `PanelExemploAcesso`

- Profile: a mobile Panel with PatternPart, authentication actions, an actionBar, and a richer entry flow.
- Structural observation: the sample shows a Panel with events, actions, and pattern dependencies.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="d8c5213a-038e-4c3d-8cad-c4f38c6c10ff" user="SANITIZED" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-08-04T13:50:26.0000000Z" checksum="7bff8a381959f9267b8a4be2f92c03d5" fullyQualifiedName="PanelExemploAcesso" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="865ab616-d866-4c90-9110-d352975022b5" name="PanelExemploAcesso" type="d82625fd-5892-40b0-99c9-5c8559c197fc" description="Acesso" parent="PastaExemploPanel" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="b4378a97-f9b2-4e05-b2f8-c610de258402">
    <PatternPart type="a51ced48-7bee-0001-ab12-04e9e32123d1">
      <Data Pattern="15cf49b5-fc38-4899-91b5-395d02d79889" Version="17.11.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance>
  <notifications />
  <level id="45969122-dc02-4641-8055-f127e24fef52" name="Level">
    <detail variables="&lt;Variables&gt;&lt;Variable Id=&quot;13&quot; Name=&quot;AuthRepository&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;AuthRepository&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;exo:AuthRepository, SANITIZEDSecurity&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/Variable&gt;&lt;Variable Id=&quot;12&quot; Name=&quot;Password&quot; Description=&quot;Password&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Password&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Description&lt;/Name&gt;&lt;Value&gt;Password&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;idBasedOn&lt;/Name&gt;&lt;Value&gt;Domain:AuthPassword, SANITIZEDSecurityCommon&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/Variable&gt;&lt;Variable Id=&quot;10&quot; Name=&quot;UserName&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;UserName&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;idBasedOn&lt;/Name&gt;&lt;Value&gt;Domain:AuthUserIdentification, SANITIZEDSecurityCommon&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/Variable&gt;&lt;StandardVariable Id=&quot;4&quot; Name=&quot;Pgmdesc&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Pgmdesc&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Character&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Length&lt;/Name&gt;&lt;Value&gt;256&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;AttMaxLen&lt;/Name&gt;&lt;Value&gt;256&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;StandardVariable Id=&quot;3&quot; Name=&quot;Pgmname&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Pgmname&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Character&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Length&lt;/Name&gt;&lt;Value&gt;128&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;AttMaxLen&lt;/Name&gt;&lt;Value&gt;128&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;StandardVariable Id=&quot;2&quot; Name=&quot;Time&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Time&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Character&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Length&lt;/Name&gt;&lt;Value&gt;8&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;AttMaxLen&lt;/Name&gt;&lt;Value&gt;8&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;StandardVariable Id=&quot;1&quot; Name=&quot;Today&quot;&gt;&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;Name&lt;/Name&gt;&lt;Value&gt;Today&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;OBJ_TYPE&lt;/Name&gt;&lt;Value&gt;id_OTYPE_VAR&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;IsStandardVariable&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;ATTCUSTOMTYPE&lt;/Name&gt;&lt;Value&gt;bas:Date&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;&lt;Documentation&gt;&amp;lt;WikiPage&amp;gt;&amp;lt;Modified&amp;gt;0001-01-01T00:00:00&amp;lt;/Modified&amp;gt;&amp;lt;Revision&amp;gt;0&amp;lt;/Revision&amp;gt;&amp;lt;/WikiPage&amp;gt;&lt;/Documentation&gt;&lt;/StandardVariable&gt;&lt;/Variables&gt;" events="Event Start&#xA;&#x9;&amp;AuthRepository = AuthRepository.Get()&#xA;&#x9;Do Case&#xA;&#x9;Case &amp;AuthRepository.UserIdentification = AuthRepositoryUserIdentifications.Name&#xA;&#x9;&#x9;&amp;UserName.Caption = AuthRepositoryUserIdentifications.EnumerationDescription(AuthRepositoryUserIdentifications.Name)&#xA;&#x9;Case &amp;AuthRepository.UserIdentification = AuthRepositoryUserIdentifications.EMail&#xA;&#x9;&#x9;&amp;UserName.Caption = AuthRepositoryUserIdentifications.EnumerationDescription(AuthRepositoryUserIdentifications.EMail)&#xA;&#x9;Case &amp;AuthRepository.UserIdentification = AuthRepositoryUserIdentifications.NameEmail&#xA;&#x9;&#x9;&amp;UserName.Caption = AuthRepositoryUserIdentifications.EnumerationDescription(AuthRepositoryUserIdentifications.NameEmail)&#xA;&#x9;EndCase&#xA;Endevent&#xA;&#xA;Event 'BtnAcesso'&#xA;&#x9;Composite&#xA;&#x9;&#x9;SANITIZED.Common.UI.Progress.ShowWithTitle(&quot;Conectando...&quot;)&#xA;&#x9;&#x9;SANITIZED.SD.Actions.Autenticar(&amp;UserName, &amp;Password)&#xA;&#x9;&#x9;SANITIZED.Common.UI.Progress.Hide()&#xA;&#x9;&#x9;Return&#xA;&#x9;EndComposite&#xA;EndEvent&#xA;&#xA;&#xA;//Event 'Facebook'&#xA;//&#x9;Composite&#xA;//&#x9;&#x9;&amp;AcessoExternalAdditionalParameters = new()&#xA;//      &amp;AcessoExternalAdditionalParameters.AuthenticationTypeName&#x9;= !&quot;facebook&quot;  //Use only when more than one Facebook authentication type is defined&#xA;//      SANITIZED.SD.Actions.AutenticarExternal(AuthAuthenticationTypes.Facebook, &amp;UserName, &amp;Password, &amp;AcessoExternalAdditionalParameters)&#xA;//      Return&#xA;//&#x9;EndComposite&#xA;//EndEvent&#xA;&#xA;//Event 'Google'&#xA;//&#x9;Composite&#xA;//&#x9;&#x9;&amp;AcessoExternalAdditionalParameters = new()&#xA;//      &amp;AcessoExternalAdditionalParameters.AuthenticationTypeName&#x9;= !&quot;google&quot;  //Use only when more than one Google authentication type is defined&#xA;//      SANITIZED.SD.Actions.AutenticarExternal(AuthAuthenticationTypes.Google, &amp;UserName, &amp;Password, &amp;AcessoExternalAdditionalParameters)&#xA;//&#x9;&#x9;Return&#xA;//&#x9;EndComposite&#xA;//EndEvent&#xA;&#xA;//Event 'Twitter'&#xA;//&#x9;Composite&#xA;//&#x9;&#x9;SANITIZED.SD.Actions.AutenticarExternal(AuthAuthenticationTypes.Twitter, &amp;UserName, &amp;Password)&#xA;//&#x9;&#x9;Return&#xA;//&#x9;EndComposite&#xA;//EndEvent&#xA;&#xA;//Event 'AuthRemote'&#xA;//&#x9;Composite&#xA;//&#x9;&#x9;&amp;AcessoExternalAdditionalParameters = new()&#xA;//&#x9;&#x9;&amp;AcessoExternalAdditionalParameters.Repository&#x9;&#x9;&#x9;&#x9;= &amp;RepositoryGUID&#x9;//Use only when more than one Repository is defined in the Identity Provider (multi-tenant)&#xA;//&#x9;&#x9;&amp;AcessoExternalAdditionalParameters.AuthenticationTypeName&#x9;= !&quot;idp_name&quot;  &#x9;&#x9;//Use only when more than one AuthRemote authentication type is defined&#xA;//      SANITIZED.SD.Actions.AutenticarExternal(AuthAuthenticationTypes.AuthRemote, &amp;UserName, &amp;Password, &amp;AcessoExternalAdditionalParameters)&#xA;//&#x9;&#x9;Return&#xA;//&#x9;EndComposite&#xA;//Endevent&#xA;&#xA;&#xA;&#xA;Event 'Register'&#xA;&#x9;Composite&#xA;&#x9;&#x9;PanelExemploRegistrar()&#xA;&#x9;&#x9;Return&#xA;&#x9;&#x9;If 1=0&#xA;&#x9;&#x9;&#x9;Do 'Dummy'&#xA;&#x9;&#x9;Endif&#xA;&#x9;EndComposite&#xA;EndEvent&#xA;&#xA;&#xA;Sub 'Dummy'&#xA;&#x9;//To include in build references&#xA;&#x9;PanelExemploAtualizar()&#xA;&#x9;PanelExemploAlterarSenha()&#xA;&#x9;PanelExemploNaoAutorizado()&#xA;Endsub&#xA;&#xA;&#xA;" rules="&#xD;&#xA;">
      <layout id="3448c091-227a-50bb-a80a-dfbc08086458" Type="View">
        <table id="ab58fa72-dc00-4426-b898-f29b04c920a8" controlName="MainTable" columnsStyle="10dip;100%;10dip" responsiveSizes="[]">
          <row id="f906596b-4aad-4521-8da4-80aafbabdfbb" rowHeight="50dip" />
          <row id="b020ea6f-2c5c-4a01-9474-913934e181b0" rowHeight="pd">
            <cell id="365aba11-c77f-4c3d-a0a6-eacb08e3dc44" />
            <cell id="2b8f0168-0df7-4de1-bbf8-ffb295d36429">
              <data attribute="&amp;UserName" labelCaption="Name" readonly="False" inviteMessage="" />
            </cell>
            <cell id="da5e96b9-3aff-4aab-b89e-39d7be52ad7a" />
          </row>
          <row id="b99ef45d-712d-4945-85c3-7c017cf00d05" rowHeight="pd">
            <cell id="7b01445f-554a-482d-9363-f71b40761bf4" />
            <cell id="2a9b93b9-c15b-426a-b3e2-3372642b075d">
              <data attribute="&amp;Password" labelCaption="Password" readonly="False" inviteMessage="" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;idEnableShowPasswordHint&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" />
            </cell>
          </row>
          <row id="91340143-cf76-4a5a-9536-2328d1d7c7e4" rowHeight="15dip" />
          <row id="f36e98c0-93a9-4fc7-8b6f-99a81f196b01" rowHeight="pd">
            <cell id="c4da8518-eb92-45c4-8c5f-6169048318a7" />
            <cell id="de0e3236-6940-41b2-9b10-c01b64bb2dbf" hAlign="Center" vAlign="Middle">
              <action controlName="BtnAcesso" onClickEvent="'BtnAcesso'" caption="Acesso" class="button-primary" />
            </cell>
          </row>
        </table>
        <actionBar>
          <item priority="High">
            <action controlName="BtnRegister" onClickEvent="'Register'" />
          </item>
        </actionBar>
      </layout>
    </detail>
  </level>
</instance>]]></Data>
      <Properties>
        <Property>
          <Name>IsDefault</Name>
          <Value>False</Value>
        </Property>
      </Properties>
    </PatternPart>
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
      <Value>PanelExemploAcesso</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Acesso</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>idConnectivitySupport</Name>
      <Value>idOnline</Value>
    </Property>
    <Property>
      <Name>AndroidBaseStyle</Name>
      <Value>AndroidBaseStyleDark</Value>
    </Property>
    <Property>
      <Name>CacheEnabled</Name>
      <Value>False</Value>
    </Property>
    <Property>
      <Name>IntegratedSecurityLevel</Name>
      <Value>SecurityNone</Value>
    </Property>
    <Property>
      <Name>IntegratedSecurityPermissionPrefix</Name>
      <Value>PanelExemploAcesso</Value>
    </Property>
  </Properties>
  <Categories>Panel_Samples-sd</Categories>
</Object>

```

### Sanitized API template 1 - `APIExemploIntegracao`

- Profile: an API with a Service block, multiple RestMethods, .Before/.After events, and a dense set of variables.
- Structural observation: this is the only real API case observed in this KB; its REST services are coordinated by events and internal helper logic.
- Direct structural evidence: later comparison with the real corpus found that `API` uses concrete `ATTCUSTOMTYPE` values for `EXO` and `SDT`, such as `exo:GAMSession, GeneXusSecurity` and `sdt:Messages, GeneXus.Common`.
- Structural caveat: interpretation of this observed API depends on its referenced `Procedure`, `EXO`, and `SDT` being present in the source KB.
- Structural observation: the `ATTCUSTOMTYPE` values and `Source` dependencies carry semantic relationships that are not evident from the outer XML envelope alone.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="74e9b5f3-f6b7-4421-b895-d960d6b1078b" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-03-12T15:02:57.0000000Z" checksum="2ca44baa29aabb01a13db31a19ad40b3" fullyQualifiedName="APIExemploIntegracao" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="854bf450-73b9-4472-bbcc-24ddcb983022" name="APIExemploIntegracao" type="36e32e2d-023e-4188-95df-d13573bac2e0" description="API Exemplo Integracao" parent="PastaExemploAPI" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="9f577ec2-27f4-4cf4-8ad5-f3f50c9d69b5">
    <Source><![CDATA[Service
{	
	[RestMethod(POST)]
	[Description("Obter a lista de itens conforme parametros.")]
	ObterItens(
		in:&ItemEmpresaId, 
		in:&ItemCodigo, 
		in:&AlteradoDesdeExemplo, 
		in:&FiltroExemploAEmpresaId, 
		in:&FiltroExemploADesde, 
		in:&SemDadosExemploB, 
		in:&ItemMarcaId, 
		in:&GrupoDeItemId, 
		out:&ListaSDTExemploItemBasicoA, 
		out:&MensagensRetorno
	)
	=> PRCExemploListaItensA(
		"", 
		&ItemEmpresaId, 
		&ItemTipoExemploA, 
		&ItemCodigo, 
		&AlteradoDesdeExemplo, 
		&FiltroExemploAEmpresaId, 
		&FiltroExemploADesde, 
		&SemDadosExemploB, 
		&SemDadosExemploC, 
		&SemDadosExemploD, 
		&DomainExemploGrupoA, 
		&ItemMarcaId, 
		&ComExemploE, 
		&DomainExemploCorteA, 
		&DomainExemploLocalA, 
		&GrupoDeItemId, 
		&ListaSDTExemploItemBasicoA, 
		&MensagensRetorno
	);

	[RestMethod(POST)]
	[Description("Obter a lista de regras conforme parametros.")]
	ObterRegras(
		in:&RegraExemploEmpresaId, 
		in:&RegraExemploId,
		in:&DocumentoExemploEmpresaId,
		in:&DomainExemploTipoOperacaoA,
		in:&AlteradoDesdeExemplo, 
		out:&SDTExemploRegraSelecaoA, 
		out:&MensagensRetorno
	)
	=> PRCExemploRegraSelecaoA(
		&RegraExemploEmpresaId, 
		&RegraExemploId,
		&DocumentoExemploEmpresaId,
		&DomainExemploTipoOperacaoA,
		&AlteradoDesdeExemplo, 
		&SDTExemploRegraSelecaoA, 
		&MensagensRetorno
	);
	
	[RestMethod(POST)]
	[Description("enviar um documento em Base64 para processamento.")]
	EnviarDocumento(
		in:&NomeArquivoExemploA, 
		in:&ConteudoBase64ExemploA,
		in:&DocumentoExemploEmpresaId,
		out:&OperacaoExemploSucessoA, 
		out:&MensagensRetorno
	)
	=> PRCExemploImportaDocumentoBase64A(
		&NomeArquivoExemploA, 
		&ConteudoBase64ExemploA,
		&DocumentoExemploEmpresaId,
		&OperacaoExemploSucessoA, 
		&MensagensRetorno
	);
	
}]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[Event ObterItens.Before
	
	&ItemTipoExemploA = DomainExemploTipoA.Item
	
Endevent
Event ObterItens.After
	
	do 'CompletaMensagensRetorno'	
	
Endevent	

Event ObterRegras.Before
	
	&ContextoExemploId = procExemploContextoId(&DocumentoExemploEmpresaId)		
	if &ContextoExemploId.IsEmpty()
	
		&ContextoExemploId = &DocumentoExemploEmpresaId
			
	endif	
	
	do 'CompletaLogin'
	
Endevent
Event ObterRegras.After
	
	do 'CompletaMensagensRetorno'	
	
Endevent	


Event EnviarDocumento.Before

	&ContextoExemploId = procExemploContextoId(&DocumentoExemploEmpresaId)		
	if &ContextoExemploId.IsEmpty()
	
		&ContextoExemploId = &DocumentoExemploEmpresaId
			
	endif	
	
	do 'CompletaLogin'

Endevent
Event EnviarDocumento.After
	
	if &OperacaoExemploSucessoA
		
		&MensagensRetorno =
		procExemploRemoveMensagensTipo(&MensagensRetorno, TiposMensagemExemplo.Warning, -1)
		
	endif

	&MensagensRetorno =
	procExemploRemoveMensagensTipo(&MensagensRetorno, TiposMensagemExemplo.Info, 0)

	do 'CompletaMensagensRetorno'
	
Endevent	
	
	
//Sub 'CompletaMensagensRetorno'
Sub 'CompletaMensagensRetorno'
	
	PRCExemploJuntaMensagensA(&MensagensRetorno, &MensagensInicio)
	
Endsub	

	
//Sub 'CompletaLogin'
Sub 'CompletaLogin'

	&AbortarInicio = false
	
	&AuthSession = AuthSession.Get(&AuthErrors)
	
	&SessionValid = AuthSession.IsValid(&AuthSession, &AuthErrors)
	
	Do Case
		Case &AuthErrors.Count > 0
			
			procExemploJuntaErrosAuth(&MensagensInicio, &AuthErrors)
			
			//procExemploNovaMensagem(&MensagensInicio, "", TiposMensagemExemplo.Error,
			//"Erro: (Falha na autenticacao) " + &AuthErrors.ToJson())
			//"Erro: Falha na autenticacao. Com " + &AuthErrors.Count.ToString().Trim() + " erros.")
			
			&RestCode = 403  // Forbidden (ou 401 se for "não autenticado")
			&AbortarInicio = true
			
		Case not &SessionValid
			
			procExemploNovaMensagem(&MensagensInicio,"", TiposMensagemExemplo.Error, 
			'Erro: sessao de autenticacao invalida.')
			
			&RestCode = 403  // Forbidden (ou 401 se for "não autenticado")
			&AbortarInicio = true
			
		Case &ContextoExemploId.IsEmpty()

			procExemploNovaMensagem(&MensagensInicio,"", TiposMensagemExemplo.Error, 
			'Erro: contexto de login nao definido.')
			
			&RestCode = 403  // Forbidden (ou 401 se for "não autenticado")
			&AbortarInicio = true
		
		Otherwise

			&AuthUser    = &AuthSession.User
			&UserName  = &AuthUser.GetName()
			
			&loginExemploUsuarioId = procUsuarioPorLogin(&UserName.ToString().Trim())
			
			//if &loginExemploUsuarioId.IsEmpty()
			if &loginExemploUsuarioId.IsEmpty()
				
				procExemploNovaMensagem(&MensagensInicio,"", TiposMensagemExemplo.Error, 
				'Erro: usuario nao identificado para o login ' + &UserName + ".")
	
				&RestCode = 403  // Forbidden (ou 401 se for "não autenticado")
				&AbortarInicio = true
				
			else
				
				procAbreContextoUsuarioExemplo(&loginExemploUsuarioId,"")
				
				//if procSampleCompanyEnabledForUserExemplo(&ContextoExemploId)
				if procSampleCompanyEnabledForUserExemplo(&ContextoExemploId)
					
					procAbreContextoExemplo(&ContextoExemploId, "")
					
				else
					
					procExemploNovaMensagem(&MensagensInicio,"", TiposMensagemExemplo.Error, 
					'Erro: Usuário Id ' + &loginExemploUsuarioId.ToString().Trim() + 
					' sem permissao para a empresa id ' + &ContextoExemploId.ToString().Trim() +
					".")
		
					&RestCode = 403  // Forbidden (ou 401 se for "não autenticado")
					&AbortarInicio = true
					
				endif
				
			endif
		
	Endcase

	//if &AbortarInicio
	if &AbortarInicio
		
		do 'CompletaMensagensRetorno'
		Return
		
	endif

Endsub
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="AbortarInicio">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AbortarInicio</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:Boolean</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="FiltroExemploADesde">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>FiltroExemploADesde</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Data</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="FiltroExemploAEmpresaId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>FiltroExemploAEmpresaId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Empresa Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:EmpresaExemploId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ComExemploE">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ComExemploE</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:DomainExemploSimNao</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ConteudoBase64ExemploA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ConteudoBase64ExemploA</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:LongVarChar</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="DomainExemploCorteA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>DomainExemploCorteA</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Corte Tipo</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:DomainExemploCorteA</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="DocumentoExemploEmpresaId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>DocumentoExemploEmpresaId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Documento Exemplo Empresa Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:DocumentoExemploEmpresaId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="loginExemploUsuarioId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>loginExemploUsuarioId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Usuario Id</Value>
        </Property>
        <Property>
          <Name>idIsAutoDefinedVariable</Name>
          <Value>False</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:UsuarioId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="emptyAuthSession">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>emptyAuthSession</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>exo:AuthSession, SanitizedSecurity</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AuthError">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AuthError</Value>
        </Property>
        <Property>
          <Name>idIsAutoDefinedVariable</Name>
          <Value>False</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>exo:AuthError, SanitizedSecurity</Value>
        </Property>
        <Property>
          <Name>Length</Name>
          <Value>4</Value>
        </Property>
        <Property>
          <Name>Decimals</Name>
          <Value>0</Value>
        </Property>
        <Property>
          <Name>AttMaxLen</Name>
          <Value>4</Value>
        </Property>
        <Property>
          <Name>AttAvgLen</Name>
          <Value>0</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AuthErrors">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AuthErrors</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>exo:AuthError, SanitizedSecurity</Value>
        </Property>
        <Property>
          <Name>AttCollection</Name>
          <Value>True</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AuthLoginAdditionalParameters">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AuthLoginAdditionalParameters</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>exo:AuthLoginAdditionalParameters, SanitizedSecurity</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AuthSession">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AuthSession</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>exo:AuthSession, SanitizedSecurity</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AuthUser">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AuthUser</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>exo:AuthUser, SanitizedSecurity</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="GrupoDeItemId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>GrupoDeItemId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Grupo De Item Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:GrupoDeItemId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="DomainExemploGrupoA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>DomainExemploGrupoA</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:DomainExemploGrupoA</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="MensagensInicio">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>MensagensInicio</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:Messages, Sanitized.Common</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ListaSDTExemploItemBasicoA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ListaSDTExemploItemBasicoA</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:sdtExemploItemBasico</Value>
        </Property>
        <Property>
          <Name>AttCollection</Name>
          <Value>True</Value>
        </Property>
        <Property>
          <Name>idVarServiceExtName</Name>
          <Value>ListaExemploItemBasico</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="NomeArquivo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>NomeArquivo</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:VarChar</Value>
        </Property>
        <Property>
          <Name>Length</Name>
          <Value>512</Value>
        </Property>
        <Property>
          <Name>AttMaxLen</Name>
          <Value>512</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="NomeArquivoExemploA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>NomeArquivoExemploA</Value>
        </Property>
        <Property>
          <Name>idIsAutoDefinedVariable</Name>
          <Value>False</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:VarChar</Value>
        </Property>
        <Property>
          <Name>Length</Name>
          <Value>256</Value>
        </Property>
        <Property>
          <Name>AttMaxLen</Name>
          <Value>256</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ContextoExemploId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ContextoExemploId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Empresa Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:EmpresaExemploId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ItemCodigo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ItemCodigo</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Item Código</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:ItemCodigo</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ItemEmpresaId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ItemEmpresaId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Item Empresa Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:ItemEmpresaId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ItemMarcaId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ItemMarcaId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Item Marca Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:ItemMarcaId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ItemTipoExemploA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ItemTipoExemploA</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Item Tipo</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:ItemTipoExemploA</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="ProgressIndicator_Title">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>ProgressIndicator_Title</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:VarChar</Value>
        </Property>
        <Property>
          <Name>Length</Name>
          <Value>256</Value>
        </Property>
        <Property>
          <Name>AttMaxLen</Name>
          <Value>256</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="MensagensRetorno">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>MensagensRetorno</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:Messages, Sanitized.Common</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="SDTExemploRegraSelecaoA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>SDTExemploRegraSelecaoA</Value>
        </Property>
        <Property>
          <Name>idIsAutoDefinedVariable</Name>
          <Value>False</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:SDTExemploRegraSelecaoA</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="SemDadosExemploB">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>SemDadosExemploB</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Logico</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="SemDadosExemploC">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>SemDadosExemploC</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Logico</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="SemDadosExemploD">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>SemDadosExemploD</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Logico</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="SessionValid">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>SessionValid</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:Boolean</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="OperacaoExemploSucessoA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>OperacaoExemploSucessoA</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:Boolean</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="tipodeconteudo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>tipodeconteudo</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:VarChar</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="DomainExemploLocalA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>DomainExemploLocalA</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:DomainExemploLocalA</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="RegraExemploEmpresaId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>RegraExemploEmpresaId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Regra Empresa Id</Value>
        </Property>
        <Property>
          <Name>idIsAutoDefinedVariable</Name>
          <Value>False</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:RegraExemploEmpresaId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="RegraExemploId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>RegraExemploId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Regra Id</Value>
        </Property>
        <Property>
          <Name>idIsAutoDefinedVariable</Name>
          <Value>False</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:RegraExemploId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AlteradoDesdeExemplo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AlteradoDesdeExemplo</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Data</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="UserLogin">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>UserLogin</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="UserName">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>UserName</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:AuthUserIdentification, SanitizedSecurityCommon</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="DomainExemploTipoOperacaoA">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>DomainExemploTipoOperacaoA</Value>
        </Property>
        <Property>
          <Name>idIsAutoDefinedVariable</Name>
          <Value>False</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:DomainExemploTipoOperacaoA</Value>
        </Property>
      </Properties>
    </Variable>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
    <Help>
      <HelpItem>
        <Language>88313f43-5eb2-0000-0028-e8d9f5bf9588-Portuguese</Language>
        <Content />
      </HelpItem>
    </Help>
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
      <Value>APIExemploIntegracao</Value>
    </Property>
    <Property>
      <Name>GENERATE_OPEN_API</Name>
      <Value>Yes</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>

```

### Sanitized API template 2 - a minimal, self-contained triad (`ApiExemploMinima` + `procExemploApiList` + `SdtExemploApiResponse`)

- Profile: a **minimal, self-contained** observed from-spec `API` shape with GAM security, complementing the dense `APIExemploIntegracao` case above. It is the **closed triad** `API` → implementation `Procedure` → response `SDT`.
- Dependency boundary ("self-contained"): the **only** external `ATTCUSTOMTYPE` is `sdt:SdtExemploApiResponse` (the triad's own SDT). It does **not** use `exo:GAMSession, GeneXusSecurity` (that is the 4th mode — manual auth via an event; real GAM enforcement is through the `[SecurityLevel]` annotation) nor `sdt:Messages, GeneXus.Common` (the response carries `Found/Code/Message` inline).
- Security: uses `[SecurityLevel(Authorization)]` (the spelling **proven** against the parser; `Authorize` is rejected). GAM runtime is a precondition; verifying it end-to-end is out of scope for this reading skill.
- Historical import evidence: this shape passed a **real import** (not a preview) on GeneXus 18 / KMW 4.0.187794 + GAM 3.15.78. The recorded import sequence packaged the API with the Procedure or staged the Procedure first; this is evidence for the observed `API => Proc` reference, not a current import recipe.
- Structural observation: the Procedure body is self-contained and builds a literal item without `For each` over a real Transaction, so the example has no business dependency.
- Sanitization applied: `user=SANITIZED\USER`, an empty `checksum`, `guid`/`parentGuid`/`moduleGuid` neutralized; `type`/`parentType` and the part-type GUIDs are canonical (type identity, the same across KBs) and **preserved**.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="55555555-5555-4555-8555-555555555555" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-01-01T00:00:00.0000000Z" checksum="" fullyQualifiedName="SdtExemploApiResponse" moduleGuid="44444444-4444-4444-8444-444444444444" guid="11111111-1111-4111-8111-111111111111" name="SdtExemploApiResponse" type="447527b5-9210-4523-898b-5dccb17be60a" description="Sdt Exemplo Api Response" parent="PastaExemploApi" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="5c2aa9da-8fc4-4b6b-ae02-8db4fa48976a">
    <Level Name="SdtExemploApiResponse">
      <LevelInfo guid="11111111-1111-4111-8111-111111111112" name="SdtExemploApiResponse" type="a76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Sdt Exemplo Api Response" user="SANITIZED\\USER">
        <Properties><Property><Name>Name</Name><Value>SdtExemploApiResponse</Value></Property><Property><Name>AttCollection</Name><Value>False</Value></Property></Properties>
      </LevelInfo>
      <Item guid="11111111-1111-4111-8111-111111111113" name="Id" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Id" user="SANITIZED\\USER">
        <Properties><Property><Name>Name</Name><Value>Id</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:Numeric</Value></Property><Property><Name>Length</Name><Value>7</Value></Property><Property><Name>Decimals</Name><Value>0</Value></Property><Property><Name>AttMaxLen</Name><Value>7</Value></Property></Properties>
      </Item>
      <Item guid="11111111-1111-4111-8111-111111111114" name="Nome" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Nome" user="SANITIZED\\USER">
        <Properties><Property><Name>Name</Name><Value>Nome</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property><Property><Name>Length</Name><Value>60</Value></Property><Property><Name>Decimals</Name><Value>0</Value></Property><Property><Name>AttMaxLen</Name><Value>60</Value></Property></Properties>
      </Item>
      <Item guid="11111111-1111-4111-8111-111111111115" name="Found" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Found" user="SANITIZED\\USER">
        <Properties><Property><Name>Name</Name><Value>Found</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:Boolean</Value></Property></Properties>
      </Item>
      <Item guid="11111111-1111-4111-8111-111111111116" name="Code" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Code" user="SANITIZED\\USER">
        <Properties><Property><Name>Name</Name><Value>Code</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property><Property><Name>Length</Name><Value>20</Value></Property><Property><Name>Decimals</Name><Value>0</Value></Property><Property><Name>AttMaxLen</Name><Value>20</Value></Property></Properties>
      </Item>
      <Item guid="11111111-1111-4111-8111-111111111117" name="Message" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Message" user="SANITIZED\\USER">
        <Properties><Property><Name>Name</Name><Value>Message</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property><Property><Name>Length</Name><Value>200</Value></Property><Property><Name>Decimals</Name><Value>0</Value></Property><Property><Name>AttMaxLen</Name><Value>200</Value></Property></Properties>
      </Item>
    </Level>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties><Property><Name>Name</Name><Value>SdtExemploApiResponse</Value></Property><Property><Name>Description</Name><Value>Sdt Exemplo Api Response</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
</Object>
```

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="55555555-5555-4555-8555-555555555555" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-01-01T00:00:00.0000000Z" checksum="" fullyQualifiedName="procExemploApiList" moduleGuid="44444444-4444-4444-8444-444444444444" guid="22222222-2222-4222-8222-222222222222" name="procExemploApiList" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" description="proc Exemplo Api List" parent="PastaExemploApi" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
    <Source><![CDATA[&SdtExemploApiResponseCollection.Clear()

&SdtExemploApiResponse = new()
&SdtExemploApiResponse.Id = 1
&SdtExemploApiResponse.Nome = !"Exemplo"
&SdtExemploApiResponse.Found = true
&SdtExemploApiResponse.Code = !"OK"
&SdtExemploApiResponse.Message = !"Registro de exemplo."
&SdtExemploApiResponseCollection.Add(&SdtExemploApiResponse)
]]></Source>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
    <Properties />
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[parm(out:&SdtExemploApiResponseCollection);
]]></Source>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9">
    <Properties />
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="SdtExemploApiResponse">
      <Documentation />
      <Properties><Property><Name>Name</Name><Value>SdtExemploApiResponse</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>sdt:SdtExemploApiResponse</Value></Property></Properties>
    </Variable>
    <Variable Name="SdtExemploApiResponseCollection">
      <Documentation />
      <Properties><Property><Name>Name</Name><Value>SdtExemploApiResponseCollection</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>sdt:SdtExemploApiResponse</Value></Property><Property><Name>AttCollection</Name><Value>True</Value></Property></Properties>
    </Variable>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
    <Help>
      <HelpItem>
        <Language>88313f43-5eb2-0000-0028-e8d9f5bf9588-Portuguese</Language>
        <Content />
      </HelpItem>
    </Help>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties><Property><Name>Name</Name><Value>procExemploApiList</Value></Property><Property><Name>Description</Name><Value>proc Exemplo Api List</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
</Object>
```

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="55555555-5555-4555-8555-555555555555" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-01-01T00:00:00.0000000Z" checksum="" fullyQualifiedName="ApiExemploMinima" moduleGuid="44444444-4444-4444-8444-444444444444" guid="33333333-3333-4333-8333-333333333333" name="ApiExemploMinima" type="36e32e2d-023e-4188-95df-d13573bac2e0" description="Api Exemplo Minima" parent="PastaExemploApi" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="9f577ec2-27f4-4cf4-8ad5-f3f50c9d69b5">
    <Source><![CDATA[Service
{
	[SecurityLevel(Authorization)]
	[RestMethod(GET)]
	[RestPath("/itens")]
	List(out:&SdtExemploApiResponseCollection)
	=> procExemploApiList(&SdtExemploApiResponseCollection);
}
]]></Source>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[]]></Source>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="SdtExemploApiResponseCollection">
      <Documentation />
      <Properties><Property><Name>Name</Name><Value>SdtExemploApiResponseCollection</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>sdt:SdtExemploApiResponse</Value></Property><Property><Name>AttCollection</Name><Value>True</Value></Property></Properties>
    </Variable>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
    <Help>
      <HelpItem>
        <Language>88313f43-5eb2-0000-0028-e8d9f5bf9588-Portuguese</Language>
        <Content />
      </HelpItem>
    </Help>
    <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties />
  </Part>
  <Properties><Property><Name>Name</Name><Value>ApiExemploMinima</Value></Property><Property><Name>Description</Name><Value>Api Exemplo Minima</Value></Property><Property><Name>GENERATE_OPEN_API</Name><Value>Yes</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
</Object>
```

#### Historical functional-listing evidence — SampleKb (2026-07-23)

- Historical end-to-end evidence: in the local test KB SampleKb, the triad `ApiCategory` + `procCategoryApiList` + `SdtCategoryApiResponse` exposed `GET /categories`; it was imported and built, synced to the full corpus, and responded `HTTP 200` in served environment `SampleKbNETSQLServer` with a JSON collection of categories. This records a past result, not a current operational instruction or guarantee.
- Structural contrast with the minimal example: the observed Procedure body uses real `For each <Transaction>` navigation to fill the SDT item and collection variable. This shape depends on the `Transaction`, its attributes, and the KB in which it was observed; it is not an instruction to replace code.
- Collection contract: the item SDT stays `AttCollection=False`; the output variables in the API and in the Procedure use `ATTCUSTOMTYPE=sdt:<SdtItem>` with `AttCollection=True`.
- **SDT collection conventions within the same KB**:
  - *Convention A (dominant in the observed KB)*: the SDT object is a plain structured item (`AttCollection=False`), with collection declared on the variable (`AttCollection=True` on the `<Variable>` node). The variable references the plain type `sdt:MeuSdt`.
  - *Convention B (collection on the SDT object)*: this observed alternative marks the SDT object `AttCollection=True` on the `<Object>` node itself; its variable reference uses `sdt:MeuSdt.MeuSdtItem`.
  - *Observed consequence*: mixing conventions within the same KB, or typing a variable from one convention with the other's syntax, results in a collection type mismatch and a typing error at generator compile time.
- Terminology note: this observed listing profile is a `For each` over the `Transaction`'s base table/attributes, not "via BC"; BC use is evidenced by a Procedure variable `ATTCUSTOMTYPE=bc:<Transaction>` or another explicit BC use. In the SampleKb case, the `Transaction` also had `idISBUSINESSCOMPONENT=True` and `idIsDynTrn=False`; these are dated coexistence observations, not a universal initialization/loading recipe.
- Historical functional evidence reports the method, route, status, summarized payload, and served environment. `HTTP 200`, OpenAPI, or `[SecurityLevel]` do not prove GAM enforcement; verifying GAM enforcement end-to-end is out of scope for this reading skill. An OpenAPI document generated in that historical context can complement evidence of the observed public contract when its file, environment, and freshness are declared.

#### Structural `Source` example for a `For each` listing

The following historical variant illustrates a `For each` over a Transaction and the associated SDT collection shape. Its placeholder identifiers and dependency assumptions are shown for structural comparison only; it is not a template to apply or a recipe for modifying or creating objects. In the minimal triad above, `Found`, `Code`, and `Message` live in the SDT item.

```genexus
&SdtExemploApiResponseCollection.Clear()

For each <Transaction>
    &SdtExemploApiResponse = new()
    &SdtExemploApiResponse.Id = <TransactionId>
    &SdtExemploApiResponse.Nome = <TransactionNome>
    &SdtExemploApiResponse.Found = true
    &SdtExemploApiResponse.Code = !"OK"
    &SdtExemploApiResponse.Message = !"Registro listado."
    &SdtExemploApiResponseCollection.Add(&SdtExemploApiResponse)
EndFor
```

These `<...>` identifiers are placeholders in this historical example, not instructions to replace them. The `For each` navigation is structurally distinct from "via BC": the BC classification applies when the Procedure declares a variable `ATTCUSTOMTYPE=bc:<Transaction>` or otherwise explicitly uses BC. Historical `HTTP 200` evidence confirms only the observed method, route, payload, and served environment; it does not prove GAM enforcement. An observed OpenAPI YAML may document the public contract, but is not proof of security.

## Complete sanitized WorkWithForWeb templates

- Direct evidence: the corpus used in this base contains 183 WorkWithForWeb objects.
- Strong inference: the type shows a strong dependency on Pattern, the transactional parent, and the declarative structure of the `<Data Pattern=...>` block.
- Strong inference: it makes sense to document at least one lean template and one dense template to cover the extremes of real use without inventing structure.

### Sanitized WorkWithForWeb template 1 - `WorkWithWebGrupoExemplo`

- Profile: a lean WorkWithForWeb with a simple selection, few attributes, and a basic tabular tab.
- Structural observation: the sample exposes a web pattern tied to a simple transaction, with visible selection, filter, and view sections.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="098e2fb8-c338-4e2d-901b-061d18a3ee68" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-08-06T11:20:21.0000000Z" checksum="2453cba7e236b417113f4c8a3a1e97d3" fullyQualifiedName="WorkWithWebGrupoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="7140e146-7d45-07ad-16d5-8b7389584e23" name="WorkWithWebGrupoExemplo" type="78cecefe-be7d-4980-86ce-8d6e91fba04b" description="Work With Web Grupo Exemplo" parent="GrupoExemplo" parentType="1db606f2-af09-4cf9-a3b5-b481519d28f6">
  <Part type="a51ced48-7bee-0001-ab12-04e9e32123d1">
    <Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b" Version="1.0"><![CDATA[<?xml version="1.0" encoding="utf-16"?>
<instance webFormDefaults="Responsive Web Design" updateTransaction="Apply WW Style">
  <transaction transaction="1db606f2-af09-4cf9-a3b5-b481519d28f6-GrupoExemplo" />
  <level id="098e2fb8-c338-4e2d-901b-061d18a3ee68:1" name="GrupoExemplo">
    <descriptionAttribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploDescricao" description="Descricao" />
    <selection description="Grupos de Exemplo" page="&lt;unlimited&gt;">
      <modes />
      <attributes>
        <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploEmpresaId" description="Empresa Id" autolink="True" visible="True" />
        <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploId" description="Id" autolink="True" visible="True" />
        <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploDescricao" description="Descricao" autolink="True" visible="True" />
      </attributes>
      <filter>
        <attributes>
          <filterAttribute name="GrupoExemploDescricao" description="Descricao" default="" />
        </attributes>
        <conditions>
          <condition value="GrupoExemploEmpresaId = procEmpresaGrupoExemplo() or GrupoExemploEmpresaId = procExemploLeContexto()" />
          <condition value="GrupoExemploDescricao.IndexOf(&amp;GrupoExemploDescricao) &gt; 0 when not &amp;GrupoExemploDescricao.IsEmpty()" />
        </conditions>
      </filter>
    </selection>
    <view caption="GrupoExemploDescricao.ToString()" description="Grupo de Exemplo" backToSelection="True" masterPage="&lt;default&gt;">
      <parameters>
        <parameter name="GrupoExemploEmpresaId" null="True" />
        <parameter name="GrupoExemploId" null="True" />
      </parameters>
      <fixedData>
        <attributes>
          <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploDescricao" description="Descricao" autolink="True" visible="True" />
        </attributes>
      </fixedData>
      <tabs>
        <tab name="Geral" code="General" description="Grupo de Exemplo" type="Tabular" wcname="GrupoExemploGeneral">
          <attributes>
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploEmpresaId" description="Emp.Id" autolink="True" visible="True" />
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploId" description="GrupoExemplo Id" autolink="True" visible="True" />
            <attribute attribute="adbb33c9-0906-4971-833c-998de27e0676-GrupoExemploDescricao" description="Descricao" autolink="True" visible="True" />
          </attributes>
          <actions>
            <action name="Update" />
            <action name="Delete" />
          </actions>
        </tab>
      </tabs>
    </view>
  </level>
</instance>]]></Data>
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
      <Value>WorkWithWebGrupoExemplo</Value>
    </Property>
    <Property>
      <Name>KBObject</Name>
      <Value>1db606f2-af09-4cf9-a3b5-b481519d28f6-GrupoExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>

```

### Sanitized WorkWithForWeb template 2 - `WWExemploOperacionalDensoA`

Editorial note:
- this case represents a dense `WorkWithForWeb` family, with strong transactional context and a high volume of business names in the raw XML
- the public version was reduced to a structural skeleton for technical reading
- the technical value of this case lies in the coexistence of `selection`, `attributes`, `orders`, `filters`, `conditions`, `actions`, and properties such as `Apply` and `Transaction` in the pattern

Public structural skeleton:

```xml
<Object guid="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        id="00000000-0000-0000-0000-000000000000"
        moduleGuid="00000000-0000-0000-0000-000000000000"
        name="WWExemploOperacionalDensoA"
        type="78cecefe-be7d-4980-86ce-8d6e91fba04b"
        parent="TRNExemploOperacionalDensoA"
        parentId="00000000-0000-0000-0000-000000000000"
        parentType="d109e56e-cf2a-11d5-b200-000629b4905c"
        description="WWExemploOperacionalDensoA"
        isMain="false"
        folderName="WWExemploOperacionalDensoA">
  <source><![CDATA[]]></source>
  <Part type="a51f55f2-248f-4d9e-b6bd-170c23cbf498">
    <Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b">
      <instance name="WorkWith">
        <web>
          <transaction transaction="00000000-0000-0000-0000-000000000000-TRNExemploOperacionalDensoA" />
          <level name="TRNExemploOperacionalDensoA"
                 description="TRNExemploOperacionalDensoA"
                 order="1"
                 baseTable="TRNExemploOperacionalDensoA"
                 title="TRNExemploOperacionalDensoA">
            <descriptionAttribute>AtributoExemploDescricaoA</descriptionAttribute>
            <selection>
              <levels>
                <level name="TRNExemploOperacionalDensoA">
                  <modes>
                    <mode name="Insert" enabled="True" />
                    <mode name="Update" enabled="True" />
                    <mode name="Delete" enabled="True" />
                    <mode name="Display" enabled="True" />
                  </modes>
                  <attributes>
                    <attribute>AtributoExemploEmpresaId</attribute>
                    <attribute>AtributoExemploSituacao</attribute>
                    <attribute>AtributoExemploDescricaoA</attribute>
                  </attributes>
                  <orders>
                    <order orderType="Ascending">AtributoExemploDescricaoA</order>
                  </orders>
                  <filters>
                    <filterAttribute>Integer(4)</filterAttribute>
                    <filterAttribute>Character(80)</filterAttribute>
                  </filters>
                  <conditions>
                    <condition enabled="True">AtributoExemploEmpresaId = &amp;EmpresaExemploId</condition>
                  </conditions>
                  <actions>
                    <action objectName="PRCExemploAcaoA"
                            type="UserDefined"
                            enabled="True"
                            onlyselected="False" />
                  </actions>
                </level>
              </levels>
            </selection>
          </level>
        </web>
      </instance>
    </Data>
  </Part>
  <Part type="babfa2b2-19a0-4ef1-b5f4-81b7c7be79dc">
    <Source>
      <Properties>
        <Property>
          <Name>Apply</Name>
          <Value>True</Value>
        </Property>
        <Property>
          <Name>Name</Name>
          <Value>WorkWith</Value>
        </Property>
        <Property>
          <Name>Transaction</Name>
          <Value>TRNExemploOperacionalDensoA</Value>
        </Property>
        <Property>
          <Name>IsDefault</Name>
          <Value>False</Value>
        </Property>
      </Properties>
    </Source>
  </Part>
</Object>
```

## Historical mixed-import-package evidence

- Historical import evidence: at least two mixed-package profiles in this trail were successfully imported in the GeneXus IDE.
- Historical import evidence: a mixed case with a top-level `Attribute`, a `Transaction`, and a `WorkWithForWeb` was accepted, with valid coexistence between `Objects`, `Attributes`, `Dependencies`, and `ObjectsIdentityMapping`.
- Historical import evidence: a later case with `4` `Transaction`, `4` `WorkWithForWeb`, and `3` `Procedure` passed `Import File Load`, `Import`, `Updating table information`, and `Pattern generation`.
- Structural conclusion from those historical cases: there is no single universal mixed-package shape; observed formats varied with object composition and the comparable IDE-exported template.
- Private reference: the complete cases are mapped in the maintainers' private notes (not published), highlighting a comparable embedded case of the `Transaction + WorkWithForWeb + Procedure` profile.

### Historical mixed-package example 1 - `XPZExemploTRNWWAtributosA`

- Observed profile: an import package with `Transaction`, `WorkWithForWeb`, and a top-level `Attribute` in the same envelope.
- Structural observation: the case records how these elements coexisted in one observed envelope.
- Methodological limit: this is one historical profile, not a current package template or universal format.

Technical reading of the case:
- Historical structural observation: `Transaction` and `WorkWithForWeb` coexisted in `<Objects>`.
- Historical structural observation: the attributes coexisted in `<Attributes>`.
- Historical structural observation: the `WorkWithForWeb`'s `Pattern` reference was present in the `Dependencies` block.
- Historical import evidence: the package passed `Load`, `Import`, and `Pattern generation`.

### Historical mixed-package example 2 - `XPZExemploTRNWWPRCEmbutidoA`

- Observed profile: an embedded import package with `Transaction`, `WorkWithForWeb`, and `Procedure`, with no new top-level `Attribute` in the same envelope.
- Structural observation: the case documents one accepted historical envelope with complete objects embedded in `<Objects>`; it is not current guidance for packaging or importing objects.

Editorial note:
- Historical record: the complete case was exported and re-imported from a real, comparable composition from the IDE.
- the public version preserves only the structural learning from the envelope
- business names, real GUIDs, and the complete private mappings stay outside this public base

Public structural skeleton:

```xml
<?xml version="1.0" encoding="utf-8"?>
<ExportFile>
  <KMW>
    <MajorVersion>...</MajorVersion>
    <MinorVersion>...</MinorVersion>
    <Build>...</Build>
  </KMW>
  <Source kb="GUID_VALIDO" username="USUÁRIO" UNCPath="\\SERVIDOR\KB">
    <Version guid="GUID_VALIDO" name="KB" />
  </Source>
  <Objects>
    <Object name="TRNExemploA" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" ...>
      <Part ... />
    </Object>
    <Object name="TRNExemploB" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" ...>
      <Part ... />
    </Object>
    <Object name="WorkWithWebTRNExemploA" type="78cecefe-be7d-4980-86ce-8d6e91fba04b" ...>
      <Part ... />
    </Object>
    <Object name="WorkWithWebTRNExemploB" type="78cecefe-be7d-4980-86ce-8d6e91fba04b" ...>
      <Part ... />
    </Object>
    <Object name="procExemploPlanilhaA" type="84a12160-f59b-4ad7-a683-ea4481ac23e9" ...>
      <Part ... />
    </Object>
  </Objects>
  <Dependencies>
    <Reference Package="..." Type="..." Id="..." />
  </Dependencies>
  <ObjectsIdentityMapping>
    <ObjectIdentity Type="..." Name="..." parent="...">
      <Guid>...</Guid>
    </ObjectIdentity>
  </ObjectsIdentityMapping>
</ExportFile>
```

Technical reading of the case:
- Historical import evidence: `Import File Load` failed with `Value cannot be null. Parameter name: g` while the workstream used a light envelope via `FilePath`.
- Historical import evidence: the same workstream passed after it had been rebuilt as an embedded package, with complete objects inside `<Objects>`.
- Historical structural observation: the successful case contained `4` `Transaction`, `4` `WorkWithForWeb`, and `3` `Procedure`.
- Historical import evidence: the package passed `Load`, `Import`, `Updating table information`, and `Pattern generation` for the `WorkWithForWeb` objects.
- Structural conclusion from this historical comparison: the successful mixed profile was represented by a real, comparable IDE export rather than the attempted light envelope with `FilePath`.

### Sanitized SDT template 1 - `sdtPeriodoExemplo`

- Profile: a lean SDT with a single level and two simple domain-based items.
- Structural observation: this SDT shows a small input/output shape with scalar fields.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="aca52e78-bfbb-4177-8884-c10d48d1fff1" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2019-05-19T17:55:24.0000000Z" checksum="1c526a33a1f679abfc3a2746ccdeb52b" fullyQualifiedName="sdtPeriodoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="f50cac7f-5ce6-42e9-af89-7f4a9ebb7fdf" name="sdtPeriodoExemplo" type="447527b5-9210-4523-898b-5dccb17be60a" description="sdt Periodo Exemplo" parent="PastaExemploSDT" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="5c2aa9da-8fc4-4b6b-ae02-8db4fa48976a">
    <Level Name="sdtPeriodoExemplo">
      <LevelInfo guid="d288f3d0-3834-46af-a65f-5b3fb5308060" name="sdtPeriodoExemplo" type="a76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="sdt Periodo Exemplo" user="SANITIZED\\USER">
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>sdtPeriodoExemplo</Value>
          </Property>
        </Properties>
      </LevelInfo>
      <Item guid="4cedcb11-83cc-4f9b-8367-d93215f5ce1c" name="DataInicial" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Inicial Data" user="SANITIZED\\USER">
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>DataInicial</Value>
          </Property>
          <Property>
            <Name>idBasedOn</Name>
            <Value>Domain:Data</Value>
          </Property>
        </Properties>
      </Item>
      <Item guid="093d4eb3-5f4a-44d5-b0c3-2953dae0d8ab" name="DataFinal" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Final Data" user="SANITIZED\\USER">
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>DataFinal</Value>
          </Property>
          <Property>
            <Name>idBasedOn</Name>
            <Value>Domain:Data</Value>
          </Property>
        </Properties>
      </Item>
    </Level>
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
      <Value>sdtPeriodoExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized SDT template 2 - `sdtAgrupamentoExemplo`

- Profile: an SDT with a composite item, a collection, and external serialization metadata (ExternalName, ExternalNamespace, idXmlNamespace, soaptype).
- Structural observation: this SDT illustrates integration metadata, namespaces, and declared hierarchical structure.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="5ea9cdc4-1809-4bae-adfa-8e4183dab2f7" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2014-10-07T11:36:33.0000000Z" checksum="8da196d5696215a0956129a0223fc22a" fullyQualifiedName="sdtAgrupamentoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="da01d928-4061-4b6a-b92f-bc76dddd7397" name="sdtAgrupamentoExemplo" type="447527b5-9210-4523-898b-5dccb17be60a" description="sdt Agrupamento Exemplo" parent="PastaExemploSDT" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="5c2aa9da-8fc4-4b6b-ae02-8db4fa48976a">
    <Level Name="sdtAgrupamentoExemplo">
      <LevelInfo guid="ae2f592a-c84e-4081-b9f0-558ab1a49369" name="sdtAgrupamentoExemplo" type="a76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="sdt Agrupamento Exemplo" user="SANITIZED\\USER">
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>sdtAgrupamentoExemplo</Value>
          </Property>
        </Properties>
      </LevelInfo>
      <Item guid="a8f1c0e4-c0b4-4f7c-afb9-6a120e5cdbe9" name="Grupo" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Grupo" user="SANITIZED\\USER">
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>Grupo</Value>
          </Property>
          <Property>
            <Name>ATTCUSTOMTYPE</Name>
            <Value>sdt:PastaExemploSDTServicetGrupo</Value>
          </Property>
          <Property>
            <Name>idXmlName</Name>
            <Value>Grupo</Value>
          </Property>
          <Property>
            <Name>idXmlNamespace</Name>
            <Value>http://example.org/sdt</Value>
          </Property>
          <Property>
            <Name>soaptype</Name>
            <Value>http://example.org/sdt.tGrupo</Value>
          </Property>
        </Properties>
      </Item>
      <Item guid="0d086759-eb3c-47e4-820b-e1665e63d1f4" name="Itens" type="f76e9340-bdb9-445d-8f81-cfd4ddd0b0f3" description="Country Code And Names" user="SANITIZED\\USER">
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>Itens</Value>
          </Property>
          <Property>
            <Name>ATTCUSTOMTYPE</Name>
            <Value>sdt:PastaExemploSDTServiceItemExemplo</Value>
          </Property>
          <Property>
            <Name>AttCollection</Name>
            <Value>True</Value>
          </Property>
          <Property>
            <Name>idCollectionItemName</Name>
            <Value>ItemExemplo</Value>
          </Property>
          <Property>
            <Name>idXmlName</Name>
            <Value>Itens</Value>
          </Property>
          <Property>
            <Name>idXmlNamespace</Name>
            <Value>http://example.org/sdt</Value>
          </Property>
          <Property>
            <Name>soaptype</Name>
            <Value>http://example.org/sdt.ItemExemplo</Value>
          </Property>
        </Properties>
      </Item>
    </Level>
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
      <Value>sdtAgrupamentoExemplo</Value>
    </Property>
    <Property>
      <Name>ExternalName</Name>
      <Value>ItemExemploGroupedByGrupo</Value>
    </Property>
    <Property>
      <Name>ExternalNamespace</Name>
      <Value>http://example.org/sdt</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Complete sanitized DataView structural examples

### Sanitized DataView example 1 - `dvExemploMultiDbms` (observed set: Attribute + structural Transaction + DataView)

- Profile: a `DataView` over an external table, with the observed pieces (`Attribute` + associated structural `Transaction` + `DataView` with a multi-DBMS `<DataViewStructurePlatform>` + `DVAssocTable`/`DVDataStore` properties), one structure platform per DBMS across the environments, and an index platform only where the physical name was stable.
- Historical validation evidence: KB `SampleKb18`, GX 18 U13, SampleAudit workstream (2026-08-15/17); sanitized from an XPZ exported by the IDE; it passed import and build with `-FailIfReorg true` on PostgreSQL and SQL Server (`reorgDetected: None`, zero `CREATE`/`ALTER TABLE`). This records a past result, not an instruction to import or build.
- Structural observation: this example represents a table reported as **already existing** in the database and not to be created or altered by GeneXus. See `03-risk-and-decision-by-type.md` for the documented multi-DBMS and `NAME` observations; this example is not a generation checklist.

#### Piece 1 — Observed Attribute structures (`<Attribute>`, a top-level root for each column)

In this observed XPZ structure, each column mapped in the DataView and structural Transaction had an individual top-level `<Attribute>` element:

1. `ExemploRepId` (numeric primary key / partition):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Attribute parentGuid="00000000-0000-0000-0000-000000000000" user="{DOMINIO\USUARIO}" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="{ISO-UTC}" checksum="" fullyQualifiedName="ExemploRepId" moduleGuid="00000000-0000-0000-0000-000000000000" guid="{GUID-DO-ATRIBUTO-REPID}" name="ExemploRepId" description="Exemplo Rep Id">
      <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
        <Help><HelpItem><Language>{GUID-IDIOMA}-Portuguese</Language><Content /></HelpItem></Help>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a"><Properties /></Part>
      <Properties><Property><Name>Name</Name><Value>ExemploRepId</Value></Property><Property><Name>Description</Name><Value>Exemplo Rep Id</Value></Property><Property><Name>ContextualTitle</Name><Value>Repositório</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:Numeric</Value></Property><Property><Name>Length</Name><Value>4</Value></Property><Property><Name>AttMaxLen</Name><Value>4</Value></Property><Property><Name>Decimals</Name><Value>0</Value></Property><Property><Name>Signed</Name><Value>False</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Attribute>
```

2. `ExemploId` (numeric primary key / identifier):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Attribute parentGuid="00000000-0000-0000-0000-000000000000" user="{DOMINIO\USUARIO}" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="{ISO-UTC}" checksum="" fullyQualifiedName="ExemploId" moduleGuid="00000000-0000-0000-0000-000000000000" guid="{GUID-DO-ATRIBUTO-ID}" name="ExemploId" description="Exemplo Id">
      <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
        <Help><HelpItem><Language>{GUID-IDIOMA}-Portuguese</Language><Content /></HelpItem></Help>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a"><Properties /></Part>
      <Properties><Property><Name>Name</Name><Value>ExemploId</Value></Property><Property><Name>Description</Name><Value>Exemplo Id</Value></Property><Property><Name>ContextualTitle</Name><Value>Identificador</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:Numeric</Value></Property><Property><Name>Length</Name><Value>10</Value></Property><Property><Name>AttMaxLen</Name><Value>10</Value></Property><Property><Name>Decimals</Name><Value>0</Value></Property><Property><Name>Signed</Name><Value>False</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Attribute>
```

3. `ExemploNome` (textual description / VarChar):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Attribute parentGuid="00000000-0000-0000-0000-000000000000" user="{DOMINIO\USUARIO}" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="{ISO-UTC}" checksum="" fullyQualifiedName="ExemploNome" moduleGuid="00000000-0000-0000-0000-000000000000" guid="{GUID-DO-ATRIBUTO-NOME}" name="ExemploNome" description="Exemplo Nome">
      <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
        <Help><HelpItem><Language>{GUID-IDIOMA}-Portuguese</Language><Content /></HelpItem></Help>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a"><Properties /></Part>
      <Properties><Property><Name>Name</Name><Value>ExemploNome</Value></Property><Property><Name>Description</Name><Value>Exemplo Nome</Value></Property><Property><Name>ContextualTitle</Name><Value>Nome</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property><Property><Name>Length</Name><Value>250</Value></Property><Property><Name>AttMaxLen</Name><Value>250</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Attribute>
```

4. `ExemploCreDate` (creation date/time, domain-based):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Attribute parentGuid="00000000-0000-0000-0000-000000000000" user="{DOMINIO\USUARIO}" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="{ISO-UTC}" checksum="" fullyQualifiedName="ExemploCreDate" moduleGuid="00000000-0000-0000-0000-000000000000" guid="{GUID-DO-ATRIBUTO-CREDATE}" name="ExemploCreDate" description="Exemplo Cre Date">
      <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
        <Help><HelpItem><Language>{GUID-IDIOMA}-Portuguese</Language><Content /></HelpItem></Help>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a"><Properties /></Part>
      <Properties><Property><Name>Name</Name><Value>ExemploCreDate</Value></Property><Property><Name>Description</Name><Value>Exemplo Cre Date</Value></Property><Property><Name>ContextualTitle</Name><Value>Criado em</Value></Property><Property><Name>idBasedOn</Name><Value>Domain:{DOMINIO-DE-DATA-HORA}</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Attribute>
```

5. `ExemploCreUser` (creation user / VarChar):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Attribute parentGuid="00000000-0000-0000-0000-000000000000" user="{DOMINIO\USUARIO}" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="{ISO-UTC}" checksum="" fullyQualifiedName="ExemploCreUser" moduleGuid="00000000-0000-0000-0000-000000000000" guid="{GUID-DO-ATRIBUTO-CREUSER}" name="ExemploCreUser" description="Exemplo Cre User">
      <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
        <Help><HelpItem><Language>{GUID-IDIOMA}-Portuguese</Language><Content /></HelpItem></Help>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a"><Properties /></Part>
      <Properties><Property><Name>Name</Name><Value>ExemploCreUser</Value></Property><Property><Name>Description</Name><Value>Exemplo Cre User</Value></Property><Property><Name>ContextualTitle</Name><Value>Criado por</Value></Property><Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property><Property><Name>Length</Name><Value>100</Value></Property><Property><Name>AttMaxLen</Name><Value>100</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Attribute>
```

> **Observed Attribute details**:
> - In this example `parentGuid` and `moduleGuid` are zeroed (`00000000-0000-0000-0000-000000000000`); the source indicates `Attribute` does not live in a folder.
> - `ContextualTitle` is the label shown in grids/forms.
> - The date/time example uses `idBasedOn` with a domain.
> - The numeric examples use `ATTCUSTOMTYPE=bas:Numeric`, `Length`, `AttMaxLen`, `Decimals=0`, and `Signed=False`.

#### Piece 2 — Structural Transaction template (model association and table)

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="{GUID-DA-PASTA}" user="{DOMINIO\USUARIO}" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="{ISO-UTC}" checksum="" fullyQualifiedName="Exemplo" moduleGuid="{GUID-DO-MODULO-RAIZ}" guid="{GUID-DO-OBJETO-TRANSACTION}" name="Exemplo" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" description="Exemplo (estrutura do DataView dvExemploMultiDbms)" parent="{NOME-DA-PASTA}" parentType="00000000-0000-0000-0000-000000000008">
      <Part type="264be5fb-1b28-4b25-a598-6ca900dd059f">
        <Level Name="Exemplo" Type="Exemplo" Description="Exemplo (estrutura do DataView dvExemploMultiDbms)" Guid="{MESMO-GUID-DO-OBJETO-TRANSACTION}">
          <Properties />
          <Attribute key="True" guid="{GUID-DO-ATRIBUTO-REPID}">ExemploRepId</Attribute>
          <Attribute key="True" guid="{GUID-DO-ATRIBUTO-ID}">ExemploId</Attribute>
          <Attribute key="False" guid="{GUID-DO-ATRIBUTO-NOME}" isNullable="True">ExemploNome</Attribute>
          <Attribute key="False" guid="{GUID-DO-ATRIBUTO-CREDATE}" isNullable="True">ExemploCreDate</Attribute>
          <Attribute key="False" guid="{GUID-DO-ATRIBUTO-CREUSER}" isNullable="True">ExemploCreUser</Attribute>
        </Level>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
        <Properties><Property><Name>IsDefault</Name><Value>True</Value></Property><Property><Name>Defaults</Name><Value>gx:TrnDefaultWebForm.dkt</Value></Property></Properties>
      </Part>
      <Part type="4c28dfb9-f83b-46f0-9cf3-f7e090b525d5">
        <Properties><Property><Name>IsDefault</Name><Value>True</Value></Property><Property><Name>Defaults</Name><Value>gx:TrnDefaultWinForm.dkt</Value></Property></Properties>
      </Part>
      <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
        <Source><![CDATA[]]></Source>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
        <Source><![CDATA[]]></Source>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c">
        <Help>
          <HelpItem>
            <Language>{GUID-IDIOMA}-Portuguese</Language>
            <Content />
          </HelpItem>
        </Help>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
        <Properties />
      </Part>
      <Properties><Property><Name>Name</Name><Value>Exemplo</Value></Property><Property><Name>Description</Name><Value>Exemplo (estrutura do DataView dvExemploMultiDbms)</Value></Property><Property><Name>IntegratedSecurityPermissionPrefix</Name><Value>Exemplo</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Object>
```

> **Observed structural Transaction details**:
> - Rules (`9b0a32a3`), Events (`c44bd5ff`), and Variables (`e4c4ade7`) are **empty** (empty CDATA); Web/Win Forms use defaults (`IsDefault=True`).
> - The `<Level>` tag's `Guid` repeats the Transaction object's GUID.
> - The description (`"Exemplo (estrutura do DataView dvExemploMultiDbms)"`) documents the dependency.
> - Every non-key attribute uses `isNullable="True"`.
> - In this observed case, the Transaction represents a Table in the GeneXus model that does **not** generate a physical database table because the DataView associates it as external via `DVAssocTable` (`reorgDetected: None`).
> - In `<Level>`, the `<Attribute key="..." guid="...">` tag uses **each Attribute object's own individual GUID**; the DataView's `DVAssocTable` property uses the **constant GUID of the Attribute type** (`adbb33c9-0906-4971-833c-998de27e0676`) concatenated with a hyphen to the attribute's **name**.

#### Piece 3 — DataView template (`<Object type="19abc6ff-2cd2-0000-0006-6d172bc2333b">`)

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="{GUID-DA-PASTA}" user="{DOMINIO\USUARIO}" versionDate="0001-01-01T00:00:00.0000000"
        lastUpdate="{ISO-UTC}" checksum="" fullyQualifiedName="dvExemploMultiDbms"
        moduleGuid="{GUID-DO-MODULO-RAIZ}" guid="{GUID-DO-OBJETO-DATAVIEW}" name="dvExemploMultiDbms"
        type="19abc6ff-2cd2-0000-0006-6d172bc2333b" description="dv Exemplo Multi Dbms"
        parent="{NOME-DA-PASTA}" parentType="00000000-0000-0000-0000-000000000008">
      <Part type="19abc6ff-2cd2-1000-0006-6d172bc2333b">
        <Attributes>
          <DataViewAttribute InternalName="ExemploRepId"   ExternalName="repid" />
          <DataViewAttribute InternalName="ExemploId"      ExternalName="exemploid" />
          <DataViewAttribute InternalName="ExemploNome"    ExternalName="exemplonome" />
          <DataViewAttribute InternalName="ExemploCreDate" ExternalName="credate" />
          <DataViewAttribute InternalName="ExemploCreUser" ExternalName="creuser" />
        </Attributes>
        <Platforms>
          <!-- um bloco por DBMS presente nos environments da KB -->
          <DataViewStructurePlatform Dbms="15">
            <PlatformProperties>
              <Properties><Property><Name>NAME</Name><Value>exemplo</Value></Property><Property><Name>SCHEMA</Name><Value>meuschema</Value></Property></Properties>
            </PlatformProperties>
          </DataViewStructurePlatform>
          <DataViewStructurePlatform Dbms="12">
            <PlatformProperties>
              <Properties><Property><Name>NAME</Name><Value>Exemplo</Value></Property><Property><Name>SCHEMA</Name><Value>meuschema</Value></Property></Properties>
            </PlatformProperties>
          </DataViewStructurePlatform>
        </Platforms>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="7706bd3b-212a-1000-0006-8aaeb59068b9">
        <Indexes>
          <Object Type="Unique" parentGuid="{GUID-DO-MODULO-RAIZ}" user="{DOMINIO\USUARIO}"
                  versionDate="0001-01-01T00:00:00.0000000" lastUpdate="{ISO-UTC}" checksum=""
                  fullyQualifiedName="IdvExemploPK" moduleGuid="{GUID-DO-MODULO-RAIZ}" guid="{GUID-NOVO}"
                  name="IdvExemploPK" type="fc1b76c4-95c5-0000-0101-44f9543121bd" description="Idv Exemplo PK">
            <Platforms>
              <!-- declarar só onde o nome do índice é estável entre instalações -->
              <DataViewIndexesPlatform Dbms="15">
                <PlatformProperties>
                  <Properties><Property><Name>NAME</Name><Value>exemplo_pkey</Value></Property><Property><Name>SCHEMA</Name><Value>meuschema</Value></Property></Properties>
                </PlatformProperties>
              </DataViewIndexesPlatform>
            </Platforms>
            <Part type="fe47b55c-ea2a-1000-0101-5b38901e24f7">
              <Members>
                <Member Order="Ascending">ExemploRepId</Member>
                <Member Order="Ascending">ExemploId</Member>
              </Members>
              <Properties />
            </Part>
            <Properties><Property><Name>Name</Name><Value>IdvExemploPK</Value></Property></Properties>
          </Object>
        </Indexes>
        <Properties><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
      </Part>
      <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
        <Properties />
      </Part>
      <Properties><Property><Name>Name</Name><Value>dvExemploMultiDbms</Value></Property><Property><Name>DVAssocTable</Name><Value>adbb33c9-0906-4971-833c-998de27e0676-ExemploRepId;adbb33c9-0906-4971-833c-998de27e0676-ExemploId</Value></Property><Property><Name>DVDataStore</Name><Value>{NOME-DO-DATASTORE}</Value></Property><Property><Name>IsDefault</Name><Value>False</Value></Property></Properties>
    </Object>
```

### Historical negative case - `dvExemploSingleDbmsMissingPlatform`

- Observed profile: a `dvExemploMultiDbms`-like structure with a **single** `<DataViewStructurePlatform>` (only `Dbms="15"`, PostgreSQL), despite a SQL Server environment also being present in the KB.
- Measured historical consequence: in the environment with no platform block, the `Transaction` reverted to a plain model table, and impact analysis requested `CREATE TABLE <schema>.<TransactionName> (...)` — including on a client install, in production. In the recorded follow-up with the `Dbms="12"` block, both environments closed with `reorgDetected: None` and zero `CREATE`/`ALTER TABLE`.
- Structural observation: this case documents a platform-coverage discrepancy and its measured consequence; it is not a direction to generate, alter, or package a DataView.
