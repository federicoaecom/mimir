# 01g - Sanitized Templates: Components and Physical Layer

## Document role
Empirical, read-side structural evidence from sanitized XPZ/XML corpus materialized into XML files by the sync workflow. “Materialized” describes corpus extraction only; it does not mean GeneXus objects are created, cloned, imported into a KB, built, or packaged.

## Purpose
Record observed component, auxiliary structural-type, and physical-layer XML shapes for structural reading and comparison. These examples are evidence, not executable templates or instructions to produce objects.

## Complete sanitized ExternalObject, UserControl, and Module templates

- Direct evidence: the corpus used in this base contains 18 ExternalObject, 7 UserControl, and 279 Module objects.
- Strong inference: for these types, it is worth separating a minimal profile from a richer one whenever there is enough declarative contract or script to justify the difference.

### Sanitized ExternalObject template 1 - ObjetoExternoGenerico

- Profile: a minimal ExternalObject, with no declared methods, just namespace and external-type metadata.
- Read-side structural evidence: illustrates the observed metadata shape of a native external object or small wrapper; it does not prescribe creating one.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="620303f9-3859-4530-9c0a-4bd9f092cc07" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2016-07-18T22:08:38.0000000Z" checksum="b7c4fb30d26f475130a01fd8fb48f2d2" fullyQualifiedName="ObjetoExternoGenerico" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="30e2e748-7c30-434a-b7dc-b32a0224caa2" name="ObjetoExternoGenerico" type="c163e562-42c6-4158-ad83-5b21a14cf30e" description="Objeto Externo Generico" parent="PastaExemploExterno" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="00000000-0000-0000-0002-000000000005">
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
      <Value>ObjetoExternoGenerico</Value>
    </Property>
    <Property>
      <Name>ExoType</Name>
      <Value>Native Object</Value>
    </Property>
    <Property>
      <Name>ObjNamespace</Name>
      <Value>SANITIZED</Value>
    </Property>
    <Property>
      <Name>ExoName</Name>
      <Value>ObjetoExternoGenerico</Value>
    </Property>
    <Property>
      <Name>ExoNameCSHARP</Name>
      <Value>ObjetoExternoGenerico</Value>
    </Property>
    <Property>
      <Name>AssemblyName</Name>
      <Value />
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized ExternalObject template 2 - ServicoEnderecoExemplo

- Profile: an ExternalObject with several ExternalMethod entries, parameters, external types, and a service address.
- Read-side structural evidence: illustrates observed SOAP/RPC method and parameter declarations in this corpus; it does not direct integration creation or import.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="9ae73ae9-0f41-4b5e-9397-1231c481b8f3" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2016-02-16T18:13:55.0000000Z" checksum="48449c43470858ba4dd744d9a3a260c3" fullyQualifiedName="ServicoEnderecoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="9645286e-74c7-4223-bd68-a5b7d15696d9" name="ServicoEnderecoExemplo" type="c163e562-42c6-4158-ad83-5b21a14cf30e" description="Servico Endereco Exemplo" parent="ServicoEnderecoExemplo" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="00000000-0000-0000-0002-000000000005">
    <ExternalMethods>
      <ExternalMethod>
        <Properties>
          <Property>
            <Name>IntName</Name>
            <Value>obterVersaoServico</Value>
          </Property>
          <Property>
            <Name>ExoItemType</Name>
            <Value>bas:Character</Value>
          </Property>
          <Property>
            <Name>ExoItemLength</Name>
            <Value>9999</Value>
          </Property>
          <Property>
            <Name>ExoMethodStyle</Name>
            <Value>idRPC</Value>
          </Property>
          <Property>
            <Name>ExoMethodInputUse</Name>
            <Value>idEncoded</Value>
          </Property>
          <Property>
            <Name>ExoMethodAddress</Name>
            <Value>https://example.org/ws/address</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeName</Name>
            <Value>ServicoEnderecoExemploPort</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeNamespace</Name>
            <Value>urn:ServicoEnderecoExemplo</Value>
          </Property>
          <Property>
            <Name>ExoMethodAction</Name>
            <Value>urn:ServicoEnderecoExemploAction</Value>
          </Property>
          <Property>
            <Name>ExoName</Name>
            <Value>obterVersaoServico</Value>
          </Property>
          <Property>
            <Name>ExoMethodRequestNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseElementName</Name>
            <Value>obterVersaoServicoResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmName</Name>
            <Value>obterVersaoServicoResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmNamespace</Name>
            <Value />
          </Property>
          <Property>
            <Name>ExoItemExtType</Name>
            <Value>http://www.w3.org/2001/XMLSchema.string</Value>
          </Property>
        </Properties>
      </ExternalMethod>
      <ExternalMethod>
        <Parameters>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>codigo</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>codigo</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
        </Parameters>
        <Properties>
          <Property>
            <Name>IntName</Name>
            <Value>obterEndereco</Value>
          </Property>
          <Property>
            <Name>ExoItemType</Name>
            <Value>bas:Character</Value>
          </Property>
          <Property>
            <Name>ExoItemLength</Name>
            <Value>9999</Value>
          </Property>
          <Property>
            <Name>ExoMethodStyle</Name>
            <Value>idRPC</Value>
          </Property>
          <Property>
            <Name>ExoMethodInputUse</Name>
            <Value>idEncoded</Value>
          </Property>
          <Property>
            <Name>ExoMethodAddress</Name>
            <Value>https://example.org/ws/address</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeName</Name>
            <Value>ServicoEnderecoExemploPort</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeNamespace</Name>
            <Value>urn:ServicoEnderecoExemplo</Value>
          </Property>
          <Property>
            <Name>ExoMethodAction</Name>
            <Value>urn:ServicoEnderecoExemploAction</Value>
          </Property>
          <Property>
            <Name>ExoName</Name>
            <Value>obterEndereco</Value>
          </Property>
          <Property>
            <Name>ExoMethodRequestNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseElementName</Name>
            <Value>obterEnderecoResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmName</Name>
            <Value>obterEnderecoResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmNamespace</Name>
            <Value />
          </Property>
          <Property>
            <Name>ExoItemExtType</Name>
            <Value>http://www.w3.org/2001/XMLSchema.string</Value>
          </Property>
        </Properties>
      </ExternalMethod>
      <ExternalMethod>
        <Parameters>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>codigo</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>codigo</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>login</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>login</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>segredo</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>segredo</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
        </Parameters>
        <Properties>
          <Property>
            <Name>IntName</Name>
            <Value>obterEnderecoAuth</Value>
          </Property>
          <Property>
            <Name>ExoItemType</Name>
            <Value>bas:Character</Value>
          </Property>
          <Property>
            <Name>ExoItemLength</Name>
            <Value>9999</Value>
          </Property>
          <Property>
            <Name>ExoMethodStyle</Name>
            <Value>idRPC</Value>
          </Property>
          <Property>
            <Name>ExoMethodInputUse</Name>
            <Value>idEncoded</Value>
          </Property>
          <Property>
            <Name>ExoMethodAddress</Name>
            <Value>https://example.org/ws/address</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeName</Name>
            <Value>ServicoEnderecoExemploPort</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeNamespace</Name>
            <Value>urn:ServicoEnderecoExemplo</Value>
          </Property>
          <Property>
            <Name>ExoMethodAction</Name>
            <Value>urn:ServicoEnderecoExemploAction</Value>
          </Property>
          <Property>
            <Name>ExoName</Name>
            <Value>obterEnderecoAuth</Value>
          </Property>
          <Property>
            <Name>ExoMethodRequestNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseElementName</Name>
            <Value>obterEnderecoAuthResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmName</Name>
            <Value>obterEnderecoAuthResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmNamespace</Name>
            <Value />
          </Property>
          <Property>
            <Name>ExoItemExtType</Name>
            <Value>http://www.w3.org/2001/XMLSchema.string</Value>
          </Property>
        </Properties>
      </ExternalMethod>
      <ExternalMethod>
        <Parameters>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>logradouro</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>logradouro</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>localidade</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>localidade</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>UF</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>UF</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
        </Parameters>
        <Properties>
          <Property>
            <Name>IntName</Name>
            <Value>obterCEP</Value>
          </Property>
          <Property>
            <Name>ExoItemType</Name>
            <Value>bas:Character</Value>
          </Property>
          <Property>
            <Name>ExoItemLength</Name>
            <Value>9999</Value>
          </Property>
          <Property>
            <Name>ExoItemIsCollection</Name>
            <Value>True</Value>
          </Property>
          <Property>
            <Name>ExoMethodStyle</Name>
            <Value>idRPC</Value>
          </Property>
          <Property>
            <Name>ExoMethodInputUse</Name>
            <Value>idEncoded</Value>
          </Property>
          <Property>
            <Name>ExoMethodAddress</Name>
            <Value>https://example.org/ws/address</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeName</Name>
            <Value>ServicoEnderecoExemploPort</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeNamespace</Name>
            <Value>urn:ServicoEnderecoExemplo</Value>
          </Property>
          <Property>
            <Name>ExoMethodAction</Name>
            <Value>urn:ServicoEnderecoExemploAction</Value>
          </Property>
          <Property>
            <Name>ExoName</Name>
            <Value>obterCEP</Value>
          </Property>
          <Property>
            <Name>ExoMethodRequestNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseElementName</Name>
            <Value>obterCEPResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmName</Name>
            <Value>obterCEPResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmNamespace</Name>
            <Value />
          </Property>
          <Property>
            <Name>ExoItemExtType</Name>
            <Value>urn:ServicoEnderecoExemplo.ArrayOfstring</Value>
          </Property>
          <Property>
            <Name>ExoItemWRAPPEDCOLLECTION</Name>
            <Value>idXmlCollectionWrapped</Value>
          </Property>
          <Property>
            <Name>ExoItemCollectionItemName</Name>
            <Value>item</Value>
          </Property>
        </Properties>
      </ExternalMethod>
      <ExternalMethod>
        <Parameters>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>logradouro</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>logradouro</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>localidade</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>localidade</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>UF</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>UF</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>login</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>login</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
          <Parameter>
            <Properties>
              <Property>
                <Name>ExoParamAccessType</Name>
                <Value>in</Value>
              </Property>
              <Property>
                <Name>IntName</Name>
                <Value>segredo</Value>
              </Property>
              <Property>
                <Name>ExoItemType</Name>
                <Value>bas:Character</Value>
              </Property>
              <Property>
                <Name>ExoItemLength</Name>
                <Value>9999</Value>
              </Property>
              <Property>
                <Name>ExoName</Name>
                <Value>segredo</Value>
              </Property>
              <Property>
                <Name>ExoNamespace</Name>
                <Value />
              </Property>
              <Property>
                <Name>ExoItemExtType</Name>
                <Value>http://www.w3.org/2001/XMLSchema.string</Value>
              </Property>
            </Properties>
          </Parameter>
        </Parameters>
        <Properties>
          <Property>
            <Name>IntName</Name>
            <Value>obterCEPAuth</Value>
          </Property>
          <Property>
            <Name>ExoItemType</Name>
            <Value>bas:Character</Value>
          </Property>
          <Property>
            <Name>ExoItemLength</Name>
            <Value>9999</Value>
          </Property>
          <Property>
            <Name>ExoItemIsCollection</Name>
            <Value>True</Value>
          </Property>
          <Property>
            <Name>ExoMethodStyle</Name>
            <Value>idRPC</Value>
          </Property>
          <Property>
            <Name>ExoMethodInputUse</Name>
            <Value>idEncoded</Value>
          </Property>
          <Property>
            <Name>ExoMethodAddress</Name>
            <Value>https://example.org/ws/address</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeName</Name>
            <Value>ServicoEnderecoExemploPort</Value>
          </Property>
          <Property>
            <Name>ExoMethodPortTypeNamespace</Name>
            <Value>urn:ServicoEnderecoExemplo</Value>
          </Property>
          <Property>
            <Name>ExoMethodAction</Name>
            <Value>urn:ServicoEnderecoExemploAction</Value>
          </Property>
          <Property>
            <Name>ExoName</Name>
            <Value>obterCEPAuth</Value>
          </Property>
          <Property>
            <Name>ExoMethodRequestNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseElementName</Name>
            <Value>obterCEPAuthResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodResponseNamespace</Name>
            <Value>urn:https://example.org</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmName</Name>
            <Value>obterCEPAuthResponse</Value>
          </Property>
          <Property>
            <Name>ExoMethodReturnParmNamespace</Name>
            <Value />
          </Property>
          <Property>
            <Name>ExoItemExtType</Name>
            <Value>urn:ServicoEnderecoExemplo.ArrayOfstring</Value>
          </Property>
          <Property>
            <Name>ExoItemWRAPPEDCOLLECTION</Name>
            <Value>idXmlCollectionWrapped</Value>
          </Property>
          <Property>
            <Name>ExoItemCollectionItemName</Name>
            <Value>item</Value>
          </Property>
        </Properties>
      </ExternalMethod>
    </ExternalMethods>
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
      <Value>ServicoEnderecoExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Servico Endereco Exemplo</Value>
    </Property>
    <Property>
      <Name>ExoType</Name>
      <Value>WSDL</Value>
    </Property>
    <Property>
      <Name>ExoImporterVersion</Name>
      <Value>GX WSDL Tool version 2.0</Value>
    </Property>
    <Property>
      <Name>ExoSourceURI</Name>
      <Value>https://example.org/ws/address?WSDL</Value>
    </Property>
    <Property>
      <Name>ExoName</Name>
      <Value>ServicoEnderecoExemplo</Value>
    </Property>
    <Property>
      <Name>AssemblyName</Name>
      <Value>https://example.org/ws/address?WSDL</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized UserControl template 1 - UCNavegacaoExemplo

- Profile: a small UserControl with a few navigation/reload utility scripts.
- Read-side structural evidence: illustrates embedded JavaScript in the observed UserControl XML; it is not a control-creation recipe.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="eabf2595-127f-4740-beee-048c9da4cc9a" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2023-05-17T14:08:16.0000000Z" checksum="60441b9eb2f8ca3e38d163f099b653b9" fullyQualifiedName="UCNavegacaoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="deb7eb7a-747d-4e58-b6e0-0f6077bc5993" name="UCNavegacaoExemplo" type="562f4793-aabe-449f-8821-fc77e550698e" description="Componente para forÃ§ar refresh da pÃ¡gina. Simula F5." parent="UserControls" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="3dd92fe7-b095-44d3-9fa0-8488fa3f0c67">
    <Source><![CDATA[]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="8e9e4a7c-a4d3-4c36-8e8e-fb6702402f63">
    <Source><![CDATA[<Definition auto="false">
	<script name="ReloadPage">
		document.location.reload();
	</script>
	<script name="ReloadPageTo" Parameters = "urlString">
		document.location.href = urlString;
	</script>
	<script name="ReloadPageToAfter" Parameters = "urlString,milliseconds">
		setTimeout(function(){document.location.href = urlString;return false;}, milliseconds);
	</script>
</Definition>
]]></Source>
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
      <Value>UCNavegacaoExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Componente para forÃ§ar refresh da pÃ¡gina. Simula F5.</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized UserControl template 2 - UCDialogoExemplo

- Profile: a richer UserControl, with definitions, properties, events, and extensive scripts.
- Read-side structural evidence: illustrates a declared API and client-side behavior recorded in the observed UserControl XML; it is not a component-creation recipe.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="26b65cc7-db83-4347-9d57-5c92b5890620" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2020-06-06T14:29:32.0000000Z" checksum="2af1f45c1583606b8178e4c0c3902137" fullyQualifiedName="UCDialogoExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="955e9b8d-b768-4228-9d39-9e137e172746" name="UCDialogoExemplo" type="562f4793-aabe-449f-8821-fc77e550698e" description="UC Dialogo Exemplo" parent="PastaExemploUserControl" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="3dd92fe7-b095-44d3-9fa0-8488fa3f0c67">
    <Source><![CDATA[]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="8e9e4a7c-a4d3-4c36-8e8e-fb6702402f63">
    <Source><![CDATA[<Definition auto="false">

<Property Name="DismissReason" Type="string" Default="" />
<Property Name="Position" Type="enum" Default="center">
	<Value>top</Value>
    <Value>top-start</Value>
    <Value>top-end</Value>
    <Value>center</Value>
	<Value>center-start</Value>		
	<Value>center-end</Value>			
	<Value>bottom</Value>		
	<Value>bottom-start</Value>		
	<Value>bottom-end</Value>		
</Property>
  
<Property Name="EventName" Type="string" Default="" />
<Property Name="ConvertGxMessages" Type="Boolean" Default="false" />

<Property Name="IconHTML" Type="string" Default="" />

<Property Name="IconMsg" Type="enum" Default="warning">
    <Value>success</Value>
    <Value>error</Value>
    <Value>warning</Value>
    <Value>info</Value>
	<Value>question</Value>
</Property>

<Property Name="IconError" Type="enum" Default="error">
    <Value>success</Value>
    <Value>error</Value>
    <Value>warning</Value>
    <Value>info</Value>
	<Value>question</Value>		
</Property>

<Property Name="TimeoutError" Type="Numeric" Default="3000" />
<Property Name="TimeoutMsg" Type="Numeric" Default="3000" />

<script name="getDialogAPI" when="BeforeShow">
	mythis   = this;
	gx.fx.obs.addObserver('gx.onmessages', this, this._showMessages);
	//cria uma variavel Global mythis para ser acessado em qualquer script
</script>

<script Name="_showMessages" Parameters="messages">

	
		//Precisa habilitar o parametro
		if(!mythis.ConvertGxMessages)
			return;
			
		//process messages	
		for (var key in messages) {
			if (key != undefined) {
				mythis._renderDialogAPI(messages[key]);
			}
		}
</script>
<script Name="_renderDialogAPI" Parameters="messages">

//process messages
var container = messages;
if (messages.msgs) container = messages.msgs;

jQuery.each(container, function (index, msg) {
	
	if (!msg || !msg.text)
	return;
	
	//Conflito com UC da Exemplo
	var _isJson = (msg.text.substr(0, 1) == "{") ? true : false;
	
	if(_isJson)
		return;
		
	if(msg.type == 1)
    	mythis.FireToast2(msg.text,'',mythis.IconError,mythis.TimeoutError);
	else
		mythis.FireToast2(msg.text,'',mythis.IconMsg,mythis.TimeoutMsg);
		
	var errViewers = gx.dom.byClass('gx_ev', 'span')
	$(errViewers).remove();
	
});

</script>
<script Name="Fire" Parameters="Titulo,Texto,DialogAPIIcon,TextoBotaoConfirmar,CorBotaoConfirmar">
DialogAPI.fire({
  title: Titulo,
  text: Texto,
  icon: DialogAPIIcon,
  confirmButtonText: TextoBotaoConfirmar,
  confirmButtonColor: CorBotaoConfirmar,
  position: mythis.Position
})     
</script>

<script Name="FireWithTimer" Parameters="Titulo,Texto,DialogAPIIcon,TextoBotaoConfirmar,CorBotaoConfirmar,Timer">
DialogAPI.fire({
  title: Titulo,
  text: Texto,
  icon: DialogAPIIcon,
  confirmButtonText: TextoBotaoConfirmar,
  confirmButtonColor: CorBotaoConfirmar,
  timer: Timer,
  timerProgressBar: true
})     
</script>

<script Name="FireToast" Parameters="Titulo,Texto,DialogAPIIcon,Timer">
DialogAPI.fire({
  title: Titulo,
  text: Texto,
  icon: DialogAPIIcon,
  position: mythis.Position,
  showConfirmButton: false,  
  timer: Timer,
  timerProgressBar: true,
  toast: true
}).then((result) => {
  /* Read more about handling dismissals below */
  if (result.dismiss === DialogAPI.DismissReason.timer) {
    console.log('I was closed by the timer');
    mythis.DismissReason = result.dismiss;
    
	try {
	mythis.ClosedTimer();	
	}
	catch (e) {
	// declaraÃ§Ãµes para manipular quaisquer exceÃ§Ãµes
	//logMyErrors(e); // passa o objeto de exceÃ§Ã£o para o manipulador de erro
	}	
    	
  }
})     
</script>

<script Name="FireToast2" Parameters="Titulo,Texto,DialogAPIIcon,Timer">
DialogAPI.fire({
  title: Titulo,
  text: Texto,
  icon: DialogAPIIcon,
  iconHtml: mythis.IconHTML,
  position: mythis.Position,
  showConfirmButton: false,  
  timer: Timer,
  timerProgressBar: true
}).then((result) => {
  /* Read more about handling dismissals below */
  if (result.dismiss === DialogAPI.DismissReason.timer) {
    console.log('I was closed by the timer');
    mythis.DismissReason = result.dismiss;
    
	try {
	mythis.ClosedTimer();	
	}
	catch (e) {
	// declaraÃ§Ãµes para manipular quaisquer exceÃ§Ãµes
	//logMyErrors(e); // passa o objeto de exceÃ§Ã£o para o manipulador de erro
	}	
    		
  }
})     
</script>

<script Name="Confirm" Parameters="Titulo,Texto,DialogAPIIcon,TextoBotaoConfirmar">

const swalWithBootstrapButtons = DialogAPI.mixin({
  customClass: {
	    confirmButton: 'btn btn-success',
	    cancelButton: 'btn btn-danger'
  },
  buttonsStyling: false
})

swalWithBootstrapButtons.fire({
  title: Titulo,
  text: Texto,
  icon: DialogAPIIcon,
  confirmButtonText: TextoBotaoConfirmar,
  cancelButtonText: 'Fechar',
  position: mythis.Position,
  showCancelButton: true,
  reverseButtons: false
}).then((result) => {
  if (result.value) {
	  //Responseu Sim	  
	  mythis.Confirmed();
    
  } else {
    mythis.DismissReason = result.dismiss;
    
	try {
	mythis.Cancel();
	}
	catch (e) {
	// declaraÃ§Ãµes para manipular quaisquer exceÃ§Ãµes
	//logMyErrors(e); // passa o objeto de exceÃ§Ã£o para o manipulador de erro
	}	    		
  }
})     
</script>

<Event Name="Confirmed" On="Click"/>
<Event Name="Cancel" On="Click"/>
<Event Name="ClosedTimer" On="Click"/>

</Definition>]]></Source>
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
      <Value>UCDialogoExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>UC Dialogo Exemplo</Value>
    </Property>
    <Property>
      <Name>FileReferences</Name>
      <Value />
    </Property>
    <Property>
      <Name>BaseStyle</Name>
      <Value>dialogo-exemplo-base</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized Module template - IntegracoesExemplo

- Profile: a lean Module, with no complex internal parts, functioning as a declarative organizational unit.
- Read-side structural evidence: illustrates a lean Module's recorded organization and naming; it does not prescribe creating modules.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2019-11-23T15:47:54.0000000Z" checksum="" fullyQualifiedName="IntegracoesExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="cb061c3d-a2eb-4335-bb1a-feacbc4a9c6f" name="IntegracoesExemplo" type="00000000-0000-0000-0000-000000000008" description="IntegracoesExemplo">
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>IntegracoesExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

## Complete sanitized SubTypeGroup templates

### Sanitized SubTypeGroup template 1 - `EntidadeProcessoEmpresaExemplo`

- Profile: a lean SubTypeGroup with few subtypes, focused on simple nominal equivalences.
- Read-side structural evidence: illustrates a small declarative SubTypeGroup as recorded in XML, not instructions to create one.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="e058c0a2-a969-478b-9f81-77cf1202d227" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2024-10-07T00:25:35.0000000Z" checksum="b43b48a724160626fffcf54236c09d27" fullyQualifiedName="EntidadeProcessoEmpresaExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="ac55b810-d079-4bc2-af29-2625936bb8d0" name="EntidadeProcessoEmpresaExemplo" type="87313f43-5eb2-41d7-9b8c-e8d9f5bf9588" description="Entidade Processo Empresa Exemplo" parent="Processos" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="74203da2-41b1-402c-0001-d8d564a2c2fa">
    <Subtype guid="3a50f42a-458a-4cce-bd6f-40e9cdadf076">
      <Name>EntidadeProcessoEmpresaExemploId</Name>
      <Supertype guid="5668cdba-5e23-4a6c-80b3-ef2a2a97ce24">EntidadeEmpresaId</Supertype>
    </Subtype>
    <Subtype guid="27da01a9-97b6-4873-85d2-cd1863af1429">
      <Name>EntidadeProcessoEmpresaExemploRegraQuantidadeA</Name>
      <Supertype guid="faecb545-ec39-4194-896a-88becd5abf73">EntidadeEmpresaRegraQuantidade</Supertype>
    </Subtype>
    <Subtype guid="88122744-548c-4148-b52c-206954dc8018">
      <Name>EntidadeProcessoEmpresaExemploRegraDestinoNotaRegistroBase</Name>
      <Supertype guid="7627fe2e-8041-4ee5-892f-024e49efbeef">EntidadeEmpresaRegraExemploA</Supertype>
    </Subtype>
    <Subtype guid="9af5a4ab-fd5b-414c-b7db-99ee42abdcab">
      <Name>EntidadeProcessoEmpresaExemploRegraDestinoDocumento</Name>
      <Supertype guid="bd5e04ed-c996-4523-8088-110780fe1861">EntidadeEmpresaRegraExemploB</Supertype>
    </Subtype>
    <Subtype guid="5da64b87-4aac-4487-8c04-eea8b3ea4fc9">
      <Name>EntidadeProcessoEmpresaExemploSiglaA</Name>
      <Supertype guid="1c047235-db58-46fa-8ede-6687bc121fe6">EntidadeEmpresaExemploSiglaA</Supertype>
    </Subtype>
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
      <Value>EntidadeProcessoEmpresaExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>

```

### Sanitized SubTypeGroup template 2 - `ProcessoRegistroItemExemplo`

- Profile: a denser SubTypeGroup, with multiple subtype keys and derived entity, partner, and supplementary-data names.
- Read-side structural evidence: empirically illustrates multiple subtype keys and their derived names and relationships as recorded in XML; it does not instruct readers to create a group.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="e058c0a2-a969-478b-9f81-77cf1202d227" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-02-03T09:57:23.0000000Z" checksum="37282ebb9397103f8b7023648fa4ec5b" fullyQualifiedName="ProcessoRegistroItemExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="e595a90f-3320-4292-bb5f-d88f6cebecfb" name="ProcessoRegistroItemExemplo" type="87313f43-5eb2-41d7-9b8c-e8d9f5bf9588" description="Processo Compra Item Exemplo" parent="Processos" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="74203da2-41b1-402c-0001-d8d564a2c2fa">
    <Subtype guid="136730e0-5e9c-42ea-a3a0-40c4c598945c">
      <Name>ProcessoRegistroItemExemploEmpresaId</Name>
      <Supertype guid="e612571c-8abc-49d4-ae77-e34a3dade15d">RegistroItemEmpresaId</Supertype>
    </Subtype>
    <Subtype guid="883cab39-f6a4-48e4-9830-3361cc323dfb">
      <Name>ProcessoRegistroItemExemploId</Name>
      <Supertype guid="813c8384-4a41-48df-a5f3-ce518b1a8882">RegistroItemId</Supertype>
    </Subtype>
    <Subtype guid="51875e8b-0ba0-420e-a91e-0836eb2ed28f">
      <Name>ProcessoRegistroItemExemploDataProcesso</Name>
      <Supertype guid="89587d85-1590-4d2e-b701-3dec2418ea37">RegistroItemDataProcesso</Supertype>
    </Subtype>
    <Subtype guid="7a3c0c3c-c574-4b81-be62-402999ba0219">
      <Name>ProcessoRegistroItemExemploParceiroEmpresaId</Name>
      <Supertype guid="4743ca97-a219-4644-bb2e-44cc660a5f98">RegistroItemParceiroEmpresaId</Supertype>
    </Subtype>
    <Subtype guid="47cc16d4-5bf6-42c0-9c67-866775083a80">
      <Name>ProcessoRegistroItemExemploParceiroId</Name>
      <Supertype guid="e03e95ce-7e88-422e-83b6-b76f20316f8a">RegistroItemParceiroId</Supertype>
    </Subtype>
    <Subtype guid="a4f15a63-5aba-401d-af15-ca0b7499afff">
      <Name>ProcessoRegistroItemExemploParceiroNome</Name>
      <Supertype guid="aa07a9c5-b6eb-4141-9717-2db5b17f656c">RegistroItemParceiroNome</Supertype>
    </Subtype>
    <Subtype guid="d147b60e-4a1c-4567-a05b-1b520b5188b9">
      <Name>ProcessoRegistroItemExemploParceiroRazao</Name>
      <Supertype guid="a9ddfa43-f5f1-4cdc-9272-71bfe99be547">RegistroItemParceiroRazao</Supertype>
    </Subtype>
    <Subtype guid="7fa2112d-69cb-4583-b4b2-2eaf4ab3c868">
      <Name>ProcessoRegistroItemExemploParceiroPrincipalDocumentoId</Name>
      <Supertype guid="a8e2757b-48dd-4dd6-ab63-cf4afaedb190">RegistroItemParceiroDocumentoId</Supertype>
    </Subtype>
    <Subtype guid="75c9f57d-5388-4bce-bc44-844fe532a220">
      <Name>ProcessoRegistroItemExemploParceiroTipoA</Name>
      <Supertype guid="c9718595-0328-4439-bf54-9ff1c9077a96">RegistroItemParceiroTipoA</Supertype>
    </Subtype>
    <Subtype guid="d816cafc-0c47-4dc9-8a94-0cf33a71c2a8">
      <Name>ProcessoRegistroItemExemploParceiroPrincipalEnderecosId</Name>
      <Supertype guid="45022f34-f0c7-4151-b5fa-e60eeedf2d1b">RegistroItemParceiroEnderecoId</Supertype>
    </Subtype>
    <Subtype guid="acec979c-7a22-4ba9-b94b-a3839884365b">
      <Name>ProcessoRegistroItemExemploParceiroPrincipalUfId</Name>
      <Supertype guid="5899b6e3-eae9-47bd-911e-b6f0a99bdb46">RegistroItemParceiroUfId</Supertype>
    </Subtype>
    <Subtype guid="38a0a27c-86b6-4f5d-99ce-73371e4eb376">
      <Name>ProcessoRegistroItemExemploParceiroEndereco</Name>
      <Supertype guid="696457e2-160b-40a7-91c1-828a81e5005a">RegistroItemParceiroMapaEndereco</Supertype>
    </Subtype>
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
      <Value>ProcessoRegistroItemExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>

```



## Complete sanitized ThemeClass templates

### Sanitized ThemeClass template 1 - `BotoesAcaoExemplo`

- Profile: historically described as a simple root ThemeClass, with a web marker and an internal visual-class type; its XML records `parent="BotaoBaseExemplo"`.
- Read-side structural evidence: empirically illustrates the recorded web marker and internal visual-class type; although historically described as root, the XML records a parent. It does not prescribe creating theme classes.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="abd2de3e-1c96-5681-b52b-bbe33c0dca49" user="SANITIZED" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2014-04-10T14:23:17.0000000Z" checksum="2ef0f3b954ab655aefa1a5f9af5100e0" fullyQualifiedName="BotoesAcaoExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="2d749abc-7cbe-5cd1-b251-f1b289e851ef" name="BotoesAcaoExemplo" type="d4876646-98dd-419b-8c1c-896f83c48368" description="Botoes Acao Exemplo" parent="BotaoBaseExemplo" parentType="d4876646-98dd-419b-8c1c-896f83c48368">
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>BotoesAcaoExemplo</Value>
    </Property>
    <Property>
      <Name>ThemeElementThemeTypes</Name>
      <Value>idWeb</Value>
    </Property>
    <Property>
      <Name>ThemeElementInternalType</Name>
      <Value>GxClass</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized ThemeClass template 2 - `BotoesAcaoHoverExemplo`

- Profile: a derived ThemeClass, inheriting from another visual class of the same type.
- Read-side structural evidence: empirically illustrates ThemeClass inheritance and the shared `ThemeElementThemeTypes` and `ThemeElementInternalType` property signature of visual variants; it does not instruct readers to create a variant.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="2d749abc-7cbe-5cd1-b251-f1b289e851ef" user="SANITIZED" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2016-03-05T05:44:22.0000000Z" checksum="b99af3293f67839c80125bcf62ad7c05" fullyQualifiedName="BotoesAcaoHoverExemplo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="ef7af9e8-a021-4745-befb-1edded115e19" name="BotoesAcaoHoverExemplo" type="d4876646-98dd-419b-8c1c-896f83c48368" description="Botoes Acao Hover Exemplo" parent="BotoesAcaoExemplo" parentType="d4876646-98dd-419b-8c1c-896f83c48368">
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>BotoesAcaoHoverExemplo</Value>
    </Property>
    <Property>
      <Name>ThemeElementThemeTypes</Name>
      <Value>idWeb</Value>
    </Property>
    <Property>
      <Name>ThemeElementInternalType</Name>
      <Value>GxClass</Value>
    </Property>
  </Properties>
</Object>
```


## Complete sanitized Image templates

### Sanitized Image template 1 - `AcaoCancelarExemplo`

- Profile: a simple Image with a single item referencing a theme and a sanitized original path.
- Read-side structural evidence: illustrates one Image's embedded resource and references as observed; it does not prescribe adding an image to a KB.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2023-01-28T23:24:21.0000000Z" checksum="da2989de4847257741d0fecb8cb7d90b" fullyQualifiedName="AcaoCancelarExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="ec7bc09c-00fb-486b-9566-4b67fdc76464" name="AcaoCancelarExemplo" type="9fb193d9-64a4-4d30-b129-ff7c76830f7e" description="Acao Cancelar Exemplo">
  <Part type="36f350de-f768-425f-ac20-773749f331bf">
    <Images>
      <ImageItem>
        <Image name="CancelarExemplo.png" description="CancelarExemplo.png">
          <Data>
            <base64Binary>
iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMBAMAAACkW0HUAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3Cc
ulE8AAAAGFBMVEW4BUW4BUW4BUW4BUW4BUW4BUW4BUX///+GCYqeAAAAB3RSTlMAqT9C60FAQxIVCgAAAAFiS0dEBxZhiOsAAABFSURBVAjXYxBiAAJFBhMF
BgYmVwZmJwYGlQAGIBfIYQByQRwgF8RhYEhxApFsziEKII4BqxOIw8AA5KYYMDAAucIg+UAAJ4MHj0vqGQkAAAAldEVYdGRhdGU6Y3JlYXRlADIwMTUtMDct
MDlUMTU6MDg6MTgrMDA6MDDKB3HyAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDE1LTA3LTA5VDE1OjA4OjE4KzAwOjAwu1rJTgAAAABJRU5ErkJggg==
</base64Binary>
          </Data>
        </Image>
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>CancelarExemplo.png</Value>
          </Property>
          <Property>
            <Name>Description</Name>
            <Value>CancelarExemplo.png</Value>
          </Property>
          <Property>
            <Name>ThemeReference</Name>
            <Value>c804fdbd-7c0b-440d-8527-4316c92649a6-7</Value>
          </Property>
          <Property>
            <Name>LanguageReference</Name>
            <Value>NULL</Value>
          </Property>
          <Property>
            <Name>ImageOriginalFullPath</Name>
            <Value>C:\\SANITIZED\\Assets\\ImagemExemplo.png</Value>
          </Property>
        </Properties>
        <ThemeReference>c804fdbd-7c0b-440d-8527-4316c92649a6-TemaExemplo</ThemeReference>
      </ImageItem>
    </Images>
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
      <Value>AcaoCancelarExemplo</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized Image template 2 - `AcaoExcluirExemplo`

- Profile: an Image with several `ImageItem` entries, mixing references with and without a theme.
- Read-side structural evidence: empirically illustrates multiple `ImageItem` variants of the same visual asset, with differing references as recorded; it does not prescribe creating or packaging image assets.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2023-01-28T23:24:16.0000000Z" checksum="1a5af35131c431e837e5ec7110ab9612" fullyQualifiedName="AcaoExcluirExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="7695fe89-52c9-4b7e-871e-0e11548f823e" name="AcaoExcluirExemplo" type="9fb193d9-64a4-4d30-b129-ff7c76830f7e" description="Acao Excluir Exemplo">
  <Part type="36f350de-f768-425f-ac20-773749f331bf">
    <Images>
      <ImageItem>
        <Image name="AcaoExcluirExemplo.gif" description="Acao Excluir Exemplo.gif">
          <Data>
            <base64Binary>
R0lGODlhEAAQAMQYAMQzM8AyMn4hIXYfH4EiInEeHnMeHnQeHre3t9XV1eTk5MTExLkwMIgkJL29va8uLszMzMg0NHkgIKcrK58pKW8dHZcnJ78yMv///wAA
AAAAAAAAAAAAAAAAAAAAAAAAACH5BAEAABgALAAAAAAQABAAAAVaICaOZGmeaFWVqmlcVzEWsFEelhUM2BDkB5OEQgFIAEQJSjCZNAITAUpEaDAYhCn18Yhk
p8wJgCk9DYvHpAmn4/mApVdsVjO1SHeRIgFZOBCACA4LEAkKWichADs=
</base64Binary>
          </Data>
        </Image>
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>AcaoExcluirExemplo.gif</Value>
          </Property>
          <Property>
            <Name>Description</Name>
            <Value>Acao Excluir Exemplo.gif</Value>
          </Property>
          <Property>
            <Name>IsExternalImage</Name>
            <Value>False</Value>
          </Property>
          <Property>
            <Name>ThemeReference</Name>
            <Value>NULL</Value>
          </Property>
          <Property>
            <Name>LanguageReference</Name>
            <Value>NULL</Value>
          </Property>
        </Properties>
      </ImageItem>
      <ImageItem>
        <Image name="AcaoExcluirExemplo.png" description="Acao Excluir Exemplo.png">
          <Data>
            <base64Binary>
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAK8AAACvABQqw0mAAAABh0RVh0U29mdHdhcmUAQWRv
YmUgRmlyZXdvcmtzT7MfTgAAAjdJREFUOI2lkktsTHEUxn/nf+/M6IjUq4JUyHgsBOl4NEKiRCRExcaCSEREIhZdaMOKVnVJJVZ0x9LCRnRjQS0Qj4QwoR4x
iEZKlYiOeztz57PoDNPBQpzkLP7f+c53Xn+TxP+Yq3y83rBy26umdNffyNmm9MHs+hWHxoGSkMTzTY07Mw0L9WjxPD1ds/RKGS97/7qGzsdL5+vxkpT6m9Ld
utFjkjBJPNmyNpl7NzhSGAkA8OIeiam1vctuPWoGyKxLdwbDX9sLuVJ8QoLYpGRjw53MPZPE1eRES8ycchJnbQAUi7iYT3Ja7UUX9zPfh750jeZCzLly233k
o+amt+9HrHKJVxfM6ZbUaoCKwk/4OM8jzAU45xBg0PcxEd+0+8mrAoBVX+FySaRUCQnMGYwlXxuuqdm8N/MiX+b/JgBwcX79bcTqKvhzcnrdjG13HxQqQVdF
4kKq/nhY1KpQosqnDA99uFTNH9dBT6q+06T2nycukyoShPUeuPmymdkTfgmcWTQPy+ePIzoqk83sisHTonS4UgSj13x/R8uLN4EDiMySgdQRIMoeor6h2uT2
luy7I6PG6e8VsUDaGkTRsp87aH2Wzcnz94UYoSDErrekl2888fB5EeBwdqAtj50KBaEg77xzu1Jz7wOYN9bU5AiiPbPqWic5W3V+8NPRkUJU8CABEEEEfNk/
q+5YzDn/7MBgGzAq6atJwjfzgFhBChibvcYDv3LsCCTpWyke9yAqSNEf/8G/2A9gpCdJVtr5yQAAAABJRU5ErkJggg==
</base64Binary>
          </Data>
        </Image>
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>AcaoExcluirExemplo.png</Value>
          </Property>
          <Property>
            <Name>Description</Name>
            <Value>Acao Excluir Exemplo.png</Value>
          </Property>
          <Property>
            <Name>IsExternalImage</Name>
            <Value>False</Value>
          </Property>
          <Property>
            <Name>ThemeReference</Name>
            <Value>c804fdbd-7c0b-440d-8527-4316c92649a6-1</Value>
          </Property>
          <Property>
            <Name>LanguageReference</Name>
            <Value>NULL</Value>
          </Property>
          <Property>
            <Name>ImageOriginalFullPath</Name>
            <Value>C:\\SANITIZED\\Assets\\ImagemExemplo.png</Value>
          </Property>
        </Properties>
        <ThemeReference>c804fdbd-7c0b-440d-8527-4316c92649a6-TemaExemplo</ThemeReference>
      </ImageItem>
      <ImageItem>
        <Image name="editdeleteM.png" description="Acao Excluir Exemplo.gif">
          <Data>
            <base64Binary>
iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAAB3RJTUUH2AkJDxIdUg9CLgAAAAlwSFlzAAAK8AAACvABQqw0mAAACX9JREFUeNrNWGtsVGUa
fs9l7p3pTG/MUGhpaaUQQVZQWFBQVowRf+wmGjaRBgiJWTdh2V1iFEwMvyAo7mo3Lqs/JAYSg/whIUtEuUQqwWigG9vCECy90Ja2Yzvt3M/Muezznpkp7XTK
Qthk9yRf5pzzfed9n+99n/fyjWAYBv0/XeL/GkDhJT+sAENVSdc0wdydJBmC/HAiH/hrQ9cpEw7b4sFgTeLmzaZUf38gHQqV8Jy1sjJmnzfvjrOxMehqauqz
+HyKID6YE4QH4ZAyNOQYPHr01+ELF36lj4wskUZHq6R43E2KYiFWbLVmNKczqpWXj4hVVdd8zz57bm5z80mb35/8rwJSJyakoRMn1gx8+umfhK6ude5Mxu2s
rrbYGhsFed48EktKSJAk0hMJUkdGSAkGjUR3dyYiSVGjvv5i9Y4df/G/8splubRUeyhA4IcQu3ZtTu/7778ePX369z5RLPc+9phgX7+e5PnziQCi6AW3akND
lGptpfD33xthTRt1v/ji32t37z5csmTJMHg2q9JZATGYSFtbXe+BA7uV8+e3lAcCHs+GDWR74gkw7z6pp2mkXL1KkbNnaXRgIGLbsOFY7d69hzzLl/fMBkra
t29fUVmpW7cqet5558/KhQs7Kurq3KWbNpH10UfJ5AosYO5GELLP+cHP2CATn8GYCqqqyFJZSdLYmC3W1rYkcfu25HnyySuWsrJEMb1FQ8CAsIGPPtqSPHdu
m2/uXFfJM8+QBK7omUxWIf+m00QuFwkFg9/xnJFby99I1dXEMnyBgAsyt7JsQytOp6KARr/+uib0+ee73G53mXPlShIhkPkisjII0jo7Sb99m4zx8bzfzWFu
Bu94jtdwjjK/4W/nziUn3F3idpezbNZxX4C0VEoYPHz4dVsyWeNYuJAsjY0kOZ0kcSRBqfrjj+TasoWY2Hp3NyH8yUilzMH3ek+POedqbiatvZ0EuI+/ZRmW
hgZyYrBs1sG6CvXPYGf47NlFyba233o9HtH2+OOEUCXZbjd3ngkGybN7N8l1dWQGg8VCqS+/JPL7s9YZHibHCy+Qdc0a4oQolZVR5NAhkpuaSGZLQZYdMl29
veI4dEDXZxUvvRSc1ULs18j58+ulWMxrrakh65w5JEOpMTFBmY4Ocm3daoJh8rJC29q1ZN+4kfSBAdIHB8n2/POTYMzdYq1r+3bKsPuwIZZlAclt9fXEOlhX
IZemWUgLhazJjo5fyprmtC9eTBarlQRFISMeJ9FmIx1C2TJmdDF3GNS6ddl8xPcMRrjrBY42LRIhAd+aMrCGZdoXLSL56lVnqrNzNXQekf3+dFFAyuCgF1m5
Vi4psdjhBiGdXcdZmHmQOnWKCO6zP/XUpBVMUHieTANTwCQvX6bkyZNkAX9Ezl3JJPEKW3k5yV6vJQNdrBOARopbKJXyIYpcMKtggSIBRDUV8YC5Zew0eeKE
qcwBy0yCEqZzk62YuHSJEsePkxVrRHYxygpbkVda8IxCLCRV1WXqJCoOCJcdH8hWj8d01YyQhKX4g8QXX5AB4c6nn54VTPTDD8kKknNW1xgQLCsGAiT4fOZG
LG43pSIRFme/V5Rl2FASLCDEYlT0AlCdOTNbHcsFB+cgglUmAYNL+ugoibW1JFRUkJQls5bTWRwQ3DIO9El1eNiAAIHDeuqlAkzS4SDXq6+Ss4DAkzLwzgXL
oWmj2AcfkAO5Ss6DZ5CISPN2dNRAZk+yzlkBWQOBMYvHM6D09GhGb68sgnzoccwwz4BPSRDbtW0buQqjKZelp0afG6WCORPbv58cyNzWPChYioEpoZBmCQQG
WOc0WkwDNGdOyv7IIz8oup7Q2P99fUT9/ZTBruIQ7kAeck3JMyYYuDfy7bcUuXgxW1TzlmJQIL5z1y6KI/ewdQUAEVDbtHCYFE1LsC7WeS+X8c6+CZ86NRGN
xTxl7GfsiNVncC8y2QvATABI/ODBbCHFGi8sMzX6RJA4Ay4xZ/L1LorwNxyOCff69d8IBbSYUctKn3uuw75gQesYSJ3mXWFHMobvzh36+c03KQlOTIKBZWIH
DpDn+nXyoKzEAGwcTZlpKY62W7co9NZbVB4KkcyBAguxTJbNOqCrcwYHizVo4ePHm3pee+2SXRDK5iGpWXP5Q4PQOyiOFe++S+rYGCUAwHvzpjnPVxrzYcy7
AELyeimEDVR3dZGEeSM33w9rpQxjbMEnn6z1bd4cvC9A6I2F3ubm/aNffbWzRBRdfhDbyaDgAgVjBK0ElwAfLGAriDSFQaFWMWcq0cbauH9ia+H9EDJ/TNfj
5Rs3/q322LG9otNp3BcgvhLt7dV9O3cejF658jIyl60SCa6UExpHXE6JdZYjDluCs7OcWzuB5xDcBfYqnhUrTsxvadnjXLasv9i3s7awks8Xt9XUdKnd3f5Y
f/+CcU2z8C6ZH7xrpqLIipkbUwa3tyLm2b1o7ukOxgjAIPslvKtWnQ68/fZB54oVP6E+FrXEPU8duqLI8dbWRaH33vtD+LvvNidU1cOdM+d6B3bvxC+yFOXj
hFMul2NulpOQy/HM9HbKcsS3evXxyjfeaEHSvIHOQZ1N5388lxnptJDu7q4cPXLkN2NHj/4xNj7elFOULbq5Ya6dMtiZDLzE6w2WNTf/tXz79pPWurqQYLXe
U+E0QCqbFiGeRJ7gew3mTqHNzK8ZDwa9rZs3/65BVTfBQvUA4hK4eMPDOUAaRgYjDgvd+kmW/7ns44//Ubt69WR5sNvthgw+cm/kQBmycNOGMZnlGcAAMnE/
MnJfX584ODgodHZ2iqFQSIpEIuKNGzckRVFYIXKbJsaiUbmSyLNEFBc3iuIvqkVxvlcQzLP9uGHEBnT99k1d/1enrl//GWnVZrerAMEG5UKqNTY2alVVVTrA
aMuXL9f9fr9eX19v4J2BORJG0Jjv2bNHOHPmjIR7SzqdlnK0kHO/U5+l3G/+niuULGXvBS17GtPo7lBzI1/V1YKRgbVUj8eTWbVqldbS0qLLVuSTlStXGjab
zejo6NAYYFdXl2m5AmroORBGTkHWalxV7lIpv06n2YGZ93BTZuHChWopzvsNDQ06ABkuPtvpCE/mywQa+WEU1Hg8zlZDlleFaDQqBINBdLJp5qjY3t4uYp2Q
42whpws3YA4oNJYuXZoHqUM5u0cHINNNzKkynE4qcbpl48yIMiOX9MywB9gUn7dyVZzJrk0/JcxsiKYDg08lk7xTSE1y7r8BJnJhT/Vv0A/SNDwfB8sAAAAA
SUVORK5CYII=
</base64Binary>
          </Data>
        </Image>
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>editdeleteM.png</Value>
          </Property>
          <Property>
            <Name>Description</Name>
            <Value>Acao Excluir Exemplo.gif</Value>
          </Property>
          <Property>
            <Name>IsExternalImage</Name>
            <Value>False</Value>
          </Property>
          <Property>
            <Name>ThemeReference</Name>
            <Value>NULL</Value>
          </Property>
          <Property>
            <Name>LanguageReference</Name>
            <Value>NULL</Value>
          </Property>
        </Properties>
      </ImageItem>
      <ImageItem>
        <Image name="ExcluirExemplo.png" description="ExcluirExemplo.png">
          <Data>
            <base64Binary>
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAA2hpVFh0WE1MOmNvbS5hZG9i
ZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6
bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMy1jMDExIDY2LjE0NTY2MSwgMjAxMi8wMi8wNi0xNDo1NjoyNyAgICAgICAgIj4gPHJkZjpS
REYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIg
eG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0UmVmPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5
cGUvUmVzb3VyY2VSZWYjIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRp
ZDoxNDMxREE2MEUwMjE2ODExODIyQUI5QkRBMkI3MTQ0MCIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo0OTdBM0Y3M0E4NzkxMUUzOENFQkM4Qzk2MzBB
MkRBRCIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDo0OTdBM0Y3MkE4NzkxMUUzOENFQkM4Qzk2MzBBMkRBRCIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQ
aG90b3Nob3AgQ1M2IChNYWNpbnRvc2gpIj4gPHhtcE1NOkRlcml2ZWRGcm9tIHN0UmVmOmluc3RhbmNlSUQ9InhtcC5paWQ6RTYxMzM1RDgxRTIwNjgxMThB
NkRCMUM2QTNGM0FGRDciIHN0UmVmOmRvY3VtZW50SUQ9InhtcC5kaWQ6MTQzMURBNjBFMDIxNjgxMTgyMkFCOUJEQTJCNzE0NDAiLz4gPC9yZGY6RGVzY3Jp
cHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz6k7EfoAAAAnklEQVR42sSTMQqAMAxFq4KXceqip3bVzaOoCIIIgjeo
X2wl1MQMDgbe0JD/oA1NnHPmS6XmY1FBB2ZgX+ZLsIDm7pxX8Mzuqg1Y0g+UYPczQ+jTAevDnISGV1BwAklSSWFOwEnEsCSIJWL4RFpjDjJyznzvWYw1vvP2
th0tXCjbMVpYXTEVLMqDUcnICVrQS69NJBOoQy/5/TceAgwAjxchrJKTLJQAAAAASUVORK5CYII=
</base64Binary>
          </Data>
        </Image>
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>ExcluirExemplo.png</Value>
          </Property>
          <Property>
            <Name>Description</Name>
            <Value>ExcluirExemplo.png</Value>
          </Property>
          <Property>
            <Name>IsExternalImage</Name>
            <Value>False</Value>
          </Property>
          <Property>
            <Name>ThemeReference</Name>
            <Value>NULL</Value>
          </Property>
          <Property>
            <Name>LanguageReference</Name>
            <Value>NULL</Value>
          </Property>
          <Property>
            <Name>ImageOriginalFullPath</Name>
            <Value>C:\\SANITIZED\\Assets\\ImagemExemplo.png</Value>
          </Property>
        </Properties>
      </ImageItem>
      <ImageItem>
        <Image name="RemoverExemplo.png" description="RemoverExemplo.png">
          <Data>
            <base64Binary>
iVBORw0KGgoAAAANSUhEUgAAAB4AAAAeCAQAAACROWYpAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3Cc
ulE8AAAAAmJLR0QA/4ePzL8AAAJsSURBVDjLjZW9T1NRGMZ/vShBYigECm2iCZAiwZiQqA1Rk8bF1joZBiZdykTQxDhoZKCrwAD/BYSFCRNxcYCQgLAYo6EN
C0s/INciid5Y8zjQlt5zy8dzl3vPeX553/uec97jkzD1l498YpNdfgKt9BLhEXEue5xyy1ZKnYpqSqvKypGjrFY1ragCSsl2m93wvEJKKq16SiupkObrwyWN
qUcbOksb6tGYSiZc0rAeqqDzVFBUwxW8Ar9QTM65qCQ5imu8Fl5Qvw4vhErSL/VroQLbCnn+Na2wKD9hTwk3FJItWcAcCSLGCi6RqLA8Zd6YjfCEOfDJ4Tpr
hKsTUwB85g+PyyMn72+rrgwP2LNYYaAGBZsJDhhkCLv8DDLEARPYNa4wA6z49JJrvHEl1cVXOo1E89wi7xqZZs9im/uGsZ080ITDe97h0ATk6TBc99i22KHP
GA6SA1o4BOCQFiBH0HDdIG1RpK1uZDe8T7vhaqNo4VUXOcBPsQbOeqoAWPhdVQQIsO+JXCBguGz8Fn2kjeEOsh4464F36LO4w7on7UINXMQPFOgyXOvctoix
7CmYN3LOU7APxCxifCNjLJX3n/eNyBl+EEdSSqOuM5NXs+cYNivn+h5VSroEvOImX7hbk3aJ165IOUquHbbFMt/BAlqZ5TlHNcu3RGP1WNjYNLLEyY444hmz
tFJtveNKXLgNJSptyFdu+v8Y4TeLXOVsHTHCFRZpOE7xWA0s0k2ErTPRLSJ0V1Awm35QSWXqpptRUsHTmv6xbE0qoKhmtFa9btY0o6gCmjSvG98pF90Km+xi
A230EiFGjEbT+B+hOOps9fyhsgAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAxNS0wNy0wM1QxNDozODozNCswMDowMP9FGVMAAAAldEVYdGRhdGU6bW9kaWZ5ADIw
MTUtMDctMDNUMTQ6Mzg6MzQrMDA6MDCOGKHvAAAAAElFTkSuQmCC
</base64Binary>
          </Data>
        </Image>
        <Properties>
          <Property>
            <Name>Name</Name>
            <Value>RemoverExemplo.png</Value>
          </Property>
          <Property>
            <Name>Description</Name>
            <Value>RemoverExemplo.png</Value>
          </Property>
          <Property>
            <Name>IsExternalImage</Name>
            <Value>False</Value>
          </Property>
          <Property>
            <Name>ThemeReference</Name>
            <Value>c804fdbd-7c0b-440d-8527-4316c92649a6-7</Value>
          </Property>
          <Property>
            <Name>LanguageReference</Name>
            <Value>NULL</Value>
          </Property>
          <Property>
            <Name>ImageOriginalFullPath</Name>
            <Value>C:\\SANITIZED\\Assets\\ImagemExemplo.png</Value>
          </Property>
        </Properties>
        <ThemeReference>c804fdbd-7c0b-440d-8527-4316c92649a6-TemaExemplo</ThemeReference>
      </ImageItem>
    </Images>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="babf62c5-0111-49e9-a1c3-cc004d90900a">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
    </Properties>
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>AcaoExcluirExemplo</Value>
    </Property>
    <Property>
      <Name>DefaultImage</Name>
      <Value>,,</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>
```



## Complete sanitized Table templates with embedded Indexes

### Sanitized Table template 1 - `CadastroModeloExemplo`

- Profile: a lean Table, with a simple key, one unique index, and a few embedded auxiliary indexes.
- Read-side structural evidence: empirically illustrates the simple Table key, basic ascending ordering, and a supporting descending index (`Order="Descending"`) in the recorded declarations; it is not a table-creation, build, or database-materialization recipe.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2025-09-28T12:19:09.0000000Z" checksum="2584cdc993d184b2df1c342335f093f4" fullyQualifiedName="CadastroModeloExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="a8113c94-a85c-47a7-a55c-798e19e16354" name="CadastroModeloExemplo" type="857ca50e-7905-0000-0007-c5d9ff2975ec" description="Cadastro Modelo Exemplo">
  <Part type="00000000-0000-0000-0002-000000000004">
    <Key>
      <Item guid="25fd8782-c70b-477a-beb3-8f61f15cafac">CadastroModeloExemploId</Item>
    </Key>
    <Properties />
  </Part>
  <Part type="a5c0e770-560d-0001-0001-7fe71c260de3">
    <Indexes>
      <TableIndex>
        <Index Type="Unique" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2021-12-25T04:06:21.0000000Z" checksum="be575917c1e8cc588b26f7399062ab90" fullyQualifiedName="ICadastroModeloExemploPK" moduleGuid="00000000-0000-0000-0000-000000000000" guid="6a639120-0521-48ca-b127-74b2a3d611ff" name="ICadastroModeloExemploPK" type="9e750647-3679-0000-0100-2529de263960" description="ICadastro Modelo Exemplo PK">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">CadastroModeloExemploId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>ICadastroModeloExemploPK</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2021-12-25T04:06:21.0000000Z" checksum="8371bc8d6a80e4970855604882e87a0f" fullyQualifiedName="UCadastroModeloExemploIdDesc" moduleGuid="00000000-0000-0000-0000-000000000000" guid="a1bb2e2f-22bb-40c6-9c97-1494f3921e9c" name="UCadastroModeloExemploIdDesc" type="9e750647-3679-0000-0100-2529de263960" description="UCadastro Modelo Exemplo Id Desc">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Descending">CadastroModeloExemploId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>UCadastroModeloExemploIdDesc</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2021-12-25T04:06:21.0000000Z" checksum="51b7e5a2cb9e3a49b1e54bb3f9ef7ac9" fullyQualifiedName="ICadastroModeloExemploUltimaRevisaoUsuario" moduleGuid="00000000-0000-0000-0000-000000000000" guid="4f646fed-c8c4-48d4-ba68-897095940226" name="ICadastroModeloExemploUltimaRevisaoUsuario" type="9e750647-3679-0000-0100-2529de263960" description="ICadastro Modelo Exemplo Ultima Revisao Usuario">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">CadastroModeloExemploUltimaRevisaoUsuarioId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>ICadastroModeloExemploUltimaRevisaoUsuario</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
    </Indexes>
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>CadastroModeloExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Cadastro Modelo Exemplo</Value>
    </Property>
  </Properties>
</Object>
```

### Sanitized Table template 2 - `RegistroBaseExemplo`

- Profile: a dense index, with a composite key and several automatic and user `TableIndex` entries.
- Read-side structural evidence: empirically illustrates one composite key and automatic/user indexes with recorded ascending and descending sort-direction combinations; it does not prescribe table or index creation.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="afa47377-41d5-4ae8-9755-6f53150aa361" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-03-22T12:57:46.0000000Z" checksum="2c02a143c62b21b5d16952bd6d4caaca" fullyQualifiedName="RegistroBaseExemplo" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="82d08ad9-d6c9-4bf0-bcaa-65f016c35569" name="RegistroBaseExemplo" type="857ca50e-7905-0000-0007-c5d9ff2975ec" description="RegistroBaseExemplo">
  <Part type="00000000-0000-0000-0002-000000000004">
    <Key>
      <Item guid="2135d656-21ac-49ae-9e5c-6a6dc6d59239">RegistroBaseExemploEmpresaId</Item>
      <Item guid="9a687eb2-9094-4ae2-9b58-aeb873203ed3">RegistroBaseExemploId</Item>
    </Key>
    <Properties />
  </Part>
  <Part type="a5c0e770-560d-0001-0001-7fe71c260de3">
    <Indexes>
      <TableIndex>
        <Index Type="Unique" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="1236216bdc4adaed69f269062be11a6d" fullyQualifiedName="IRegistroBaseExemploPK" moduleGuid="00000000-0000-0000-0000-000000000000" guid="57af3161-b819-4f17-8b4f-871b05f150a1" name="IRegistroBaseExemploPK" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo PK">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploPK</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="f381b5caefe2c1a317247864ef99271a" fullyQualifiedName="IRegistroBaseExemploClassificacaoTipo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="811ded12-9d79-415d-93fd-ed8f31acfe83" name="IRegistroBaseExemploClassificacaoTipo" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Classificacao Tipo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploClassificacaoTipoEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploClassificacaoTipoId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploClassificacaoTipo</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="103e69ca0edee88e341c4890052ff5e8" fullyQualifiedName="IRegistroBaseExemploParceiro" moduleGuid="00000000-0000-0000-0000-000000000000" guid="e66b21f9-c4ab-46c5-b7f6-8ce0a05a5edf" name="IRegistroBaseExemploParceiro" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Parceiro">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploParceiroEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploParceiroId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploParceiro</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="d74efbbcba5b464067b8e3338c469536" fullyQualifiedName="IRegistroBaseExemploGrupoA" moduleGuid="00000000-0000-0000-0000-000000000000" guid="8f889307-839f-4525-bc3d-2163dea0328f" name="IRegistroBaseExemploGrupoA" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Grupo A">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploGrupoAEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploGrupoAId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploGrupoA</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="5b4e10ec2ee4889e3e732c779be4c95c" fullyQualifiedName="IRegistroBaseExemploGrupoB" moduleGuid="00000000-0000-0000-0000-000000000000" guid="75a2d805-45fe-4008-ad3d-53b3db5a1eb9" name="IRegistroBaseExemploGrupoB" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Grupo B">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploGrupoBEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploGrupoBId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploGrupoB</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="6a6b876fc990bec5e147d4560fd10755" fullyQualifiedName="IRegistroBaseExemploEmpresa" moduleGuid="00000000-0000-0000-0000-000000000000" guid="6a3e1e95-d4bc-43e8-b0d9-89c7a5f06eb2" name="IRegistroBaseExemploEmpresa" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Empresa">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploEmpresa</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="6bc7ce7e233b4a2abe65f52765d2bf84" fullyQualifiedName="IRegistroBaseExemploRegistroBaseExemploParaProcesso" moduleGuid="00000000-0000-0000-0000-000000000000" guid="0ca977f1-e761-41d8-be32-1485062a9245" name="IRegistroBaseExemploRegistroBaseExemploParaProcesso" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo RegistroBaseExemplo Para Processo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoCodigo</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploRegistroBaseExemploParaProcesso</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="45129fbd516e664245969240a4bfba9b" fullyQualifiedName="IRegistroBaseExemploLocalBase" moduleGuid="00000000-0000-0000-0000-000000000000" guid="19ac6f5d-0149-4e18-8b25-64fe4e001866" name="IRegistroBaseExemploLocalBase" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Local Base">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploLocalBaseEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploLocalBaseId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploLocalBase</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="06dc81be242add07034266c28591542c" fullyQualifiedName="IRegistroBaseExemploCompraItem" moduleGuid="00000000-0000-0000-0000-000000000000" guid="7a71ebff-91fe-44d6-9625-a7ea688943ad" name="IRegistroBaseExemploCompraItem" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Compra Item">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCompraItemEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploCompraItemId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCompraItem</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="f54919dfc3f7b3810a8106b0b69c5874" fullyQualifiedName="URegistroBaseExemploDataProcessoDescendenteMaisNumeroControle" moduleGuid="00000000-0000-0000-0000-000000000000" guid="1fe056bf-e620-42be-bd2a-16ea805d0a27" name="URegistroBaseExemploDataProcessoDescendenteMaisNumeroControle" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Data Processo Descendente Mais Numero Serie">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Descending">RegistroBaseExemploDataProcesso</Member>
              <Member Order="Ascending">RegistroBaseExemploNumeroControle</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploDataProcessoDescendenteMaisNumeroControle</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="aa6c9529e6b99d4c47db369dba73d102" fullyQualifiedName="URegistroBaseExemploIdDesc" moduleGuid="00000000-0000-0000-0000-000000000000" guid="1fc78f59-17b7-48b4-94c7-dbe065c0344a" name="URegistroBaseExemploIdDesc" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Id Desc">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Descending">RegistroBaseExemploId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploIdDesc</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="14e430e335d8e8f947ea6a961d9bfa2a" fullyQualifiedName="URegistroBaseExemploCompraItemRegistroBaseExemploParaProcessoPesoDescendente" moduleGuid="00000000-0000-0000-0000-000000000000" guid="6cf7590a-bad6-467b-ac31-258bc70dfeba" name="URegistroBaseExemploCompraItemRegistroBaseExemploParaProcessoPesoDescendente" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Compra Item RegistroBaseExemplo Para Processo Peso Descendente">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCompraItemEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploCompraItemId</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoCodigo</Member>
              <Member Order="Descending">RegistroBaseExemploPeso</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploCompraItemRegistroBaseExemploParaProcessoPesoDescendente</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="73e51bd537287a6c8ebad47e60316b0e" fullyQualifiedName="IRegistroBaseExemploCampoAValor" moduleGuid="00000000-0000-0000-0000-000000000000" guid="2584071d-d819-46e8-b91f-87109d50b5e3" name="IRegistroBaseExemploCampoAValor" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo A Valor">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoAValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoAValor</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="28347480611903a30792c32ee2b9853f" fullyQualifiedName="IRegistroBaseExemploCampoBValor" moduleGuid="00000000-0000-0000-0000-000000000000" guid="cb23b419-5c73-408f-9fad-e37d877ed44f" name="IRegistroBaseExemploCampoBValor" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo B Valor">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoBValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoBValor</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="8030c82be87003dbf55a22840d17e889" fullyQualifiedName="IRegistroBaseExemploCampoCValor" moduleGuid="00000000-0000-0000-0000-000000000000" guid="2fffe9c7-9bab-4e8a-a699-ee0e5720d7b2" name="IRegistroBaseExemploCampoCValor" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo C Valor">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoCValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoCValor</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="4a2722acd92374c36a644ec77f34d53b" fullyQualifiedName="IRegistroBaseExemploCampoD" moduleGuid="00000000-0000-0000-0000-000000000000" guid="838be330-4456-446f-9c54-a12a6285def6" name="IRegistroBaseExemploCampoD" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo D">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoDValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoD</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="b1e777f1aaf9ea71c5d674e7582fc016" fullyQualifiedName="URegistroBaseExemploDataProcessoRegistroBaseExemploParaProcessoCodigoParceiroId" moduleGuid="00000000-0000-0000-0000-000000000000" guid="c1702177-088e-4482-b1d3-9ec5e35d3a7f" name="URegistroBaseExemploDataProcessoRegistroBaseExemploParaProcessoCodigoParceiroId" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Data Processo RegistroBaseExemplo Para Processo Codigo Parceiro Id">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploDataProcesso</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoCodigo</Member>
              <Member Order="Ascending">RegistroBaseExemploParceiroId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploDataProcessoRegistroBaseExemploParaProcessoCodigoParceiroId</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="c7e54afe25a85c7bfd14209f129fe838" fullyQualifiedName="URegistroBaseExemploRegistroBaseExemploParaProcessoCodigoParceiroIdDataProcesso" moduleGuid="00000000-0000-0000-0000-000000000000" guid="8cc6c7c1-7c86-48be-8a2b-97575bcc3745" name="URegistroBaseExemploRegistroBaseExemploParaProcessoCodigoParceiroIdDataProcesso" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo RegistroBaseExemplo Para Processo Codigo Parceiro Id Data Processo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoCodigo</Member>
              <Member Order="Ascending">RegistroBaseExemploParceiroId</Member>
              <Member Order="Ascending">RegistroBaseExemploDataProcesso</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploRegistroBaseExemploParaProcessoCodigoParceiroIdDataProcesso</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="916b78fa8107336acad48977d096e686" fullyQualifiedName="URegistroBaseExemploCGEmp_CGId_Inat_AACod_AAEmp_AAnaCompra_CGPeso_Tolerado" moduleGuid="00000000-0000-0000-0000-000000000000" guid="59ebd83e-4332-4006-a47f-569b49e68821" name="URegistroBaseExemploCGEmp_CGId_Inat_AACod_AAEmp_AAnaCompra_CGPeso_Tolerado" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo CGEmp_CGId_Inat_AACod_AAEmp_AAna Compra_CGPeso_Tolerado">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCompraItemEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploCompraItemId</Member>
              <Member Order="Ascending">RegistroBaseExemploInativo</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoCodigo</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoEmUso</Member>
              <Member Order="Ascending">RegistroBaseExemploClassificacaoTipoId</Member>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploId</Member>
              <Member Order="Ascending">RegistroBaseExemploPeso</Member>
              <Member Order="Ascending">RegistroBaseExemploToleradoA</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploCGEmp_CGId_Inat_AACod_AAEmp_AAnaCompra_CGPeso_Tolerado</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="85b29ea997a09ba19d7ec7467d4b4e7b" fullyQualifiedName="IRegistroBaseExemploSubgrupoA" moduleGuid="00000000-0000-0000-0000-000000000000" guid="851d0268-c94e-40a6-97bf-7e8d3134ec24" name="IRegistroBaseExemploSubgrupoA" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Subgrupo A">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploSubgrupoAValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploSubgrupoA</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="fb76a70438b34401e79f6b6f093f50f2" fullyQualifiedName="URegistroBaseExemploGrupoBMaisRegistroBaseExemploIdDesc" moduleGuid="00000000-0000-0000-0000-000000000000" guid="67e7d7db-965b-48a4-9d88-afa0c993abae" name="URegistroBaseExemploGrupoBMaisRegistroBaseExemploIdDesc" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Grupo B Mais RegistroBaseExemplo Id Desc">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploGrupoBEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploGrupoBId</Member>
              <Member Order="Descending">RegistroBaseExemploId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploGrupoBMaisRegistroBaseExemploIdDesc</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="8119957896bd159d829e7afa1877d6bc" fullyQualifiedName="URegistroBaseExemploCodigoOrigemUnicoMaisEmpresaIdMaisNumeroControle" moduleGuid="00000000-0000-0000-0000-000000000000" guid="25318cc8-7f0c-41bf-8757-60da5410bf3a" name="URegistroBaseExemploCodigoOrigemUnicoMaisEmpresaIdMaisNumeroControle" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Codigo Origem Unico Mais Empresa Id Mais Numero Serie">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCodigoOrigemUnico</Member>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploNumeroControle</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploCodigoOrigemUnicoMaisEmpresaIdMaisNumeroControle</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="b21e435a6e63ae0dea69d7b81da36afb" fullyQualifiedName="URegistroBaseExemploEmpresaParceiroDataProcesso" moduleGuid="00000000-0000-0000-0000-000000000000" guid="dedbccd9-fc66-4749-9d72-d1ce8d4d1444" name="URegistroBaseExemploEmpresaParceiroDataProcesso" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Empresa Parceiro Data Processo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploParceiroId</Member>
              <Member Order="Ascending">RegistroBaseExemploDataProcesso</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpresaParceiroDataProcesso</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="2c151b7d4662c9737ad6f06cf9cc732f" fullyQualifiedName="URegistroBaseExemploRegistroBaseExemploParaProcessoCodidoMaisDataProcesso" moduleGuid="00000000-0000-0000-0000-000000000000" guid="1a91c07f-be02-409b-b155-59b16911ae6d" name="URegistroBaseExemploRegistroBaseExemploParaProcessoCodidoMaisDataProcesso" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo RegistroBaseExemplo Para Processo Codido Mais Data Processo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploRegistroBaseExemploParaProcessoCodigo</Member>
              <Member Order="Ascending">RegistroBaseExemploDataProcesso</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploRegistroBaseExemploParaProcessoCodidoMaisDataProcesso</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="776c51050fc952e7df72bcbfbd304aba" fullyQualifiedName="IRegistroBaseExemploCampoE" moduleGuid="00000000-0000-0000-0000-000000000000" guid="b13c3acf-7727-4443-afb1-d0faaaedf85d" name="IRegistroBaseExemploCampoE" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo E">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoEValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoE</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="2228d3921c557e6b3db8ae12fc9c5897" fullyQualifiedName="IRegistroBaseExemploCampoL" moduleGuid="00000000-0000-0000-0000-000000000000" guid="2ae2bc31-d7bf-4dee-9a5d-ad1ddf65a076" name="IRegistroBaseExemploCampoL" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo L">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoLEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploCampoLId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoL</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="be01045508d62d99e872bd8aa229fd24" fullyQualifiedName="URegistroBaseExemploEmpresaMaisNumeroControleMaisInativo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="7289e48d-3b98-489e-8e51-06ec0a3d8789" name="URegistroBaseExemploEmpresaMaisNumeroControleMaisInativo" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Empresa Mais Numero Serie Mais Inativo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploNumeroControle</Member>
              <Member Order="Ascending">RegistroBaseExemploInativo</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpresaMaisNumeroControleMaisInativo</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="735e790f59ddc5bc92e5062384843bdc" fullyQualifiedName="URegistroBaseExemploEmpresaGrupoBCampoL" moduleGuid="00000000-0000-0000-0000-000000000000" guid="2af006ef-8896-4068-9dc3-7c67c6211e19" name="URegistroBaseExemploEmpresaGrupoBCampoL" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Empresa Grupo B Campo L">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploGrupoBId</Member>
              <Member Order="Ascending">RegistroBaseExemploCampoLId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpresaGrupoBCampoL</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="23a06bfac183f9c34b3f44b90e9673a1" fullyQualifiedName="URegistroBaseExemploEmpresaParceiroCampoL" moduleGuid="00000000-0000-0000-0000-000000000000" guid="584c0cb9-35c6-4b67-962b-2edea20fcaa5" name="URegistroBaseExemploEmpresaParceiroCampoL" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Empresa Parceiro Campo L">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploParceiroId</Member>
              <Member Order="Ascending">RegistroBaseExemploCampoLId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpresaParceiroCampoL</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="841f30e5f08ddbeba891c533a98422ad" fullyQualifiedName="IRegistroBaseExemploCampoFValor" moduleGuid="00000000-0000-0000-0000-000000000000" guid="4b0f36bc-b2f3-4eb0-984b-e66da19a0542" name="IRegistroBaseExemploCampoFValor" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo F Valor">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoFValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoFValor</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="fd9a0bb5a7cf17206800143e527d336c" fullyQualifiedName="IRegistroBaseExemploCampoGValor" moduleGuid="00000000-0000-0000-0000-000000000000" guid="04926593-5c0c-4ddd-b0c8-c5d37c05a7ea" name="IRegistroBaseExemploCampoGValor" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo G Valor">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoGValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoGValor</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="1e1231ed94947dfca5d19a125b3cfc20" fullyQualifiedName="URegistroBaseExemploEmpresaMaisGrupoA" moduleGuid="00000000-0000-0000-0000-000000000000" guid="6e807d28-0a8c-4ce2-8ed2-c5356afbabd1" name="URegistroBaseExemploEmpresaMaisGrupoA" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Empresa Mais Grupo A">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploGrupoAId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpresaMaisGrupoA</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="8427084e89f2eb5926473ded223f2a6b" fullyQualifiedName="URegistroBaseExemploEmpMaisSeqExDescMaisNrSerieDescMaisIdDesc" moduleGuid="00000000-0000-0000-0000-000000000000" guid="b64260f5-bdc7-4a56-b319-94864ac24df0" name="URegistroBaseExemploEmpMaisSeqExDescMaisNrSerieDescMaisIdDesc" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Emp Mais Seq Ex Desc Mais Nr Serie Desc Mais Id Desc">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Descending">RegistroBaseExemploSequenciaExemplo</Member>
              <Member Order="Descending">RegistroBaseExemploNumeroControle</Member>
              <Member Order="Descending">RegistroBaseExemploId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpMaisSeqExDescMaisNrSerieDescMaisIdDesc</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="9e165780556a03ceb19fc7f572369176" fullyQualifiedName="URegistroBaseExemploEmpresaIdMaisParceiroIdMaisInativoMaisDataProcesso" moduleGuid="00000000-0000-0000-0000-000000000000" guid="2123feea-503e-4e78-8a70-79500b8cb946" name="URegistroBaseExemploEmpresaIdMaisParceiroIdMaisInativoMaisDataProcesso" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Empresa Id Mais Parceiro Id Mais Inativo Mais Data Processo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploParceiroId</Member>
              <Member Order="Ascending">RegistroBaseExemploInativo</Member>
              <Member Order="Ascending">RegistroBaseExemploDataProcesso</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpresaIdMaisParceiroIdMaisInativoMaisDataProcesso</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="ec2cc3f4ee7571b788e56264370009b5" fullyQualifiedName="URegistroBaseExemploCompraItemMaisInativo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="f71f7c15-5e4e-4057-9b34-d1a7e02e8994" name="URegistroBaseExemploCompraItemMaisInativo" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Compra Item Mais Inativo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCompraItemEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploCompraItemId</Member>
              <Member Order="Ascending">RegistroBaseExemploInativo</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploCompraItemMaisInativo</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="1a9ca256528b1a074c4c2b2d9ae8ae29" fullyQualifiedName="URegistroBaseExemploEmpresaMaisInativo" moduleGuid="00000000-0000-0000-0000-000000000000" guid="2ed367f7-c110-43da-8bb7-bc9274214ddf" name="URegistroBaseExemploEmpresaMaisInativo" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Empresa Mais Inativo">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploEmpresaId</Member>
              <Member Order="Ascending">RegistroBaseExemploInativo</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploEmpresaMaisInativo</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="52f24ab1b7b83cd50ad3983e4eddd85b" fullyQualifiedName="IRegistroBaseExemploCampoHValor" moduleGuid="00000000-0000-0000-0000-000000000000" guid="935ca714-9c55-4d11-a16b-05aaf7363ccb" name="IRegistroBaseExemploCampoHValor" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo H Valor">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoHValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoHValor</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="e888b5ff60e31abbdacfd56b0260752a" fullyQualifiedName="URegistroBaseExemploDataProcessoDescendenteMaisSequenciaExemploDescendente" moduleGuid="00000000-0000-0000-0000-000000000000" guid="8ac74c63-7797-425c-94e4-1fcc84ba55a9" name="URegistroBaseExemploDataProcessoDescendenteMaisSequenciaExemploDescendente" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Data Processo Descendente Mais Sequencia Exemplo Descendente">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Descending">RegistroBaseExemploDataProcesso</Member>
              <Member Order="Descending">RegistroBaseExemploSequenciaExemplo</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploDataProcessoDescendenteMaisSequenciaExemploDescendente</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="User" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="e13990225fed074737612ed50ad1b2b9" fullyQualifiedName="URegistroBaseExemploDataProcessoDescendenteMaisIdDesc" moduleGuid="00000000-0000-0000-0000-000000000000" guid="8342ff82-2c7d-424e-ab49-6f029fcdc4a8" name="URegistroBaseExemploDataProcessoDescendenteMaisIdDesc" type="9e750647-3679-0000-0100-2529de263960" description="URegistroBaseExemplo Data Processo Descendente Mais Id Desc">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Descending">RegistroBaseExemploDataProcesso</Member>
              <Member Order="Descending">RegistroBaseExemploId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>URegistroBaseExemploDataProcessoDescendenteMaisIdDesc</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="17cc926555649856c4e57304c95621be" fullyQualifiedName="IRegistroBaseExemploCampoIValor" moduleGuid="00000000-0000-0000-0000-000000000000" guid="b6533850-36d6-4336-8c98-4206ecb5d3ba" name="IRegistroBaseExemploCampoIValor" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo I Valor">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoIValorId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoIValor</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="98db97e3f9edab4274813961d406e67b" fullyQualifiedName="IRegistroBaseExemploUltimaRevisaoUsuario" moduleGuid="00000000-0000-0000-0000-000000000000" guid="c771277d-2771-4f15-8d31-fd169dc07f50" name="IRegistroBaseExemploUltimaRevisaoUsuario" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Ultima Revisao Usuario">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploUltimaRevisaoUsuarioId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploUltimaRevisaoUsuario</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="7c3c3460e5f4ace653451b99c63c0912" fullyQualifiedName="IRegistroBaseExemploCampoJ" moduleGuid="00000000-0000-0000-0000-000000000000" guid="f0b4226c-9851-4742-b8c6-c759dc62da2b" name="IRegistroBaseExemploCampoJ" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo J">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoJId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoJ</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
      <TableIndex>
        <Index Type="Duplicate" Source="Automatic" parentGuid="00000000-0000-0000-0000-000000000000" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2022-11-10T17:41:27.0000000Z" checksum="22e6c4b810478f0791a7cdbaad734c5d" fullyQualifiedName="IRegistroBaseExemploCampoK" moduleGuid="00000000-0000-0000-0000-000000000000" guid="aaeae5bc-4d82-44b0-9b4c-db41fd58d27e" name="IRegistroBaseExemploCampoK" type="9e750647-3679-0000-0100-2529de263960" description="IRegistroBaseExemplo Campo K">
          <Part type="62cfa789-c127-0001-0100-77676175e433">
            <Members>
              <Member Order="Ascending">RegistroBaseExemploCampoKId</Member>
            </Members>
            <Properties />
          </Part>
          <Properties>
            <Property>
              <Name>Name</Name>
              <Value>IRegistroBaseExemploCampoK</Value>
            </Property>
          </Properties>
        </Index>
      </TableIndex>
    </Indexes>
    <Properties />
  </Part>
  <Properties>
    <Property>
      <Name>Name</Name>
      <Value>RegistroBaseExemplo</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>RegistroBaseExemplo</Value>
    </Property>
  </Properties>
</Object>
```
