# 01j - WorkWithWeb: CDATA Patterns and Surgical Anchoring

## Document role
Empirical, read-side structural interpretation

## Predominant confidence level
Direct evidence (Gx_SampleKb: 184 objects; Gx_SampleKb2: smaller sample)

## Depends on
`01-empirical-base-overview.md`, `02-operational-rules.md`

## Used by
None currently; not yet linked from any workflow or other reference

## Purpose

Document the internal CDATA hierarchy of existing `WorkWithForWeb` objects as a read-side aid for identifying which `<actions>` block corresponds to list, detail, or child-grid context. The lack of this map led to real regex mistakes that matched `<actions>` at two or more distinct levels inside the same CDATA, corrupting the transformation's target. This reference supports structural interpretation only: it does not prescribe adding missing actions, editing CDATA, or importing anything into a KB. Any insertion-oriented wording or fenced snippets below are retained historical illustrations, not instructions to perform those operations.

---

## CDATA container

The `WorkWithForWeb`'s configuration content sits in:

- **Part type**: `a51ced48-7bee-0001-ab12-04e9e32123d1`
- **Internal element**: `<Data Pattern="78cecefe-be7d-4980-86ce-8d6e91fba04b" Version="1.0"><![CDATA[...]]></Data>`

Inside the CDATA there is a complete XML document starting with `<?xml version="1.0" encoding="utf-16"?>`.

Note: the main CDATA can contain internal `<![CDATA[...]]>` blocks inside `<variable>` elements. Those internal blocks hold GeneXus code the pattern applies to the generated object. They are not CDATA nested in the XML sense — the parser treats them as literal text inside the outer CDATA.

---

## CDATA structural hierarchy

```
<instance webFormDefaults="..." updateTransaction="...">
  <transaction transaction="GUID-EntityName" />
  <level id="GUID-level:1" name="EntityName">
    <descriptionAttribute attribute="GUID-Attribute" description="..." />

    <selection description="..." page="..." customStartEventCode="...">
      <modes Insert="..." Delete="..." Display="..." Export="..." />
      <attributes>
        <attribute attribute="GUID-Attr" ... />
        <variable name="IconeUpdate" domain="..." ...><![CDATA[GeneXus code]]></variable>
        ...
      </attributes>
      <actions>                  <!-- LEVEL 1 -- LIST actions -->
        <action name="LimpaEstadoExemplo" .../>
        <action name="Insert" />
        <action name="RelatorioX" .../>
        ...
      </actions>
      <filter>                   <!-- main listing's filter -->
        <attributes>
          <filterAttribute name="AttrName" description="..." default="..." />
        </attributes>
        <conditions>
          <condition value="..." />
        </conditions>
      </filter>
    </selection>

    <view caption="..." description="..." backToSelection="..." masterPage="...">
      <parameters>
        <parameter name="EntityNameEmpresaId" null="True" />
        <parameter name="EntityNameId" null="True" />
      </parameters>
      <fixedData>
        <attributes>...</attributes>
      </fixedData>
      <tabs>

        <tab name="Geral" code="General" type="Tabular" wcname="EntityNameGeneral">
          <attributes>...</attributes>
          <actions>              <!-- LEVEL 2a -- DETAIL (current record) actions -->
            <action name="Update" />
            <action name="Delete" />
            <action name="CustomAction" .../>
          </actions>
        </tab>

        <tab name="Itens" code="EntityNameItens" type="Grid" wcname="EntityNameItensWC"
             page="..." condition="...">
          <transaction transaction="GUID-EntityNameItens" />
          <modes Insert="..." Update="..." Export="..." />
          <attributes>...</attributes>
          <actions>              <!-- LEVEL 2b -- CHILD GRID actions -->
            <action name="NovoItem" .../>
            <action name="RelatorioY" .../>
          </actions>
          <orders>...</orders>
          <filter>               <!-- child grid's filter -- independent of the selection's filter -->
            <attributes>
              <filterAttribute name="AttrName" description="..." />
            </attributes>
            <conditions>
              <condition value="..." />
            </conditions>
          </filter>
        </tab>

        <tab name="Documentos" code="EntityNameDocs" type="UserDefined" wcname="EntityNameDocsWC">
          <!-- UserDefined tabs typically have no <actions> -->
        </tab>

      </tabs>
    </view>
  </level>
</instance>
```

---

## Elements that appear at multiple levels

| Element | Where it appears | Role |
|---|---|---|
| `<actions>` | `<selection>` | **List** actions — no specific-record context (e.g. Insert, reports, LimpaEstadoExemplo, batch exports) |
| `<actions>` | `<tab type="Tabular">` | **Detail** actions — apply to the current record (e.g. Update, Delete, per-record actions) |
| `<actions>` | `<tab type="Grid">` | **Child grid** actions — specific to that tab (e.g. NovoItem, that tab's reports) |
| `<filter>` | `<selection>` | Main listing's filter |
| `<filter>` | `<tab type="Grid">` | Child grid's filter (independent) |

---

## Empirical distribution (Gx_SampleKb, 184 objects)

| Pattern | Count |
|---|---|
| `<actions>` in BOTH `<selection>` and `<tab>` | 122 |
| `<actions>` only in `<tab>` (no `<selection>/<actions>`) | 62 |
| `<actions>` only in `<selection>` | 0 |
| No `<actions>` | 0 |

- Strong inference: the dominant pattern in this KB is `<actions>` present at both levels simultaneously. A generic regex over `<actions>` will **always match at multiple points** for 2/3 of the objects.
- Direct evidence: objects with up to 14 tabs were observed; a single object can have `<actions>` in `<selection>` + `<tab type="Tabular">` + multiple `<tab type="Grid">` = 4 or more distinct `<actions>` blocks.

---

## Structural reading: anchors and scope

The patterns below identify structural locations in an existing CDATA document; they are not a procedure for modifying it. In particular, absence of an `<actions>` block is an observed structural state, not a request or instruction to create one. The fenced snippets are preserved verbatim as examples of anchors and unsafe matching patterns.

### LIST (`<selection>`) scope

Reliable anchor: the `<selection>` element is unique in the CDATA and precedes `<view>`.

```
opening anchor:  <selection[^>]*>   (the selection element itself)
closing anchor:  </selection>
search for <actions> only within that scope
```

If `<selection>` has no `<actions>`, record that absence; do not infer that an action block should be added. The observed canonical order inside `<selection>` is: `<modes>`, `<attributes>`, `<actions>`, `<filter>`, where present.

### DETAIL (`<tab type="Tabular">`) scope

Reliable anchor: `code="General"` (the main Tabular tab has `code="General"` by pattern convention).

```
anchor:  <tab [^>]*code="General"[^>]*>
search for <actions> only within that scope (up to the matching </tab>)
```

If the KB uses a different `code` for the Tabular tab, check the real XML.

### Specific Grid tab scope

Reliable anchor: `code="X"`, where X is that tab's internal GeneXus code.

```
anchor:  <tab [^>]*code="EntityNameItens"[^>]*>
search for <actions> only within that scope
```

The `code` attribute is the stable identifier the WorkWithForWeb pattern generates. The `name` attribute can vary by locale; `code` does not.

### Ambiguous matches to avoid when interpreting structure

```
# Dangerous regexes -- match at multiple levels with no discrimination:
<actions>
<actions>[\s\S]*?</actions>

# An occurrence limit (e.g. only the 1st) depends on sibling order
# and is fragile whenever the selection/view order can vary.
```

---

## Sanitized example 1 - Simple (1 Tabular tab, no Grid)

Based on 4-6 KB objects. `<actions>` exists only in the Tabular tab (no `<selection>/<actions>`).

```xml
<?xml version="1.0" encoding="utf-16"?>
<instance webFormDefaults="Responsive Web Design" updateTransaction="Apply WW Style">
  <transaction transaction="GUID-Entidade" />
  <level id="GUID-Level:1" name="Entidade">
    <descriptionAttribute attribute="GUID-EntidadeDescricao" description="Descrição" />

    <selection description="Lista de Registros" page="&lt;default&gt;">
      <modes />
      <attributes>
        <attribute attribute="GUID-EntidadeEmpresaId" description="Empresa Id"
                   autolink="True" visible="True" />
        <attribute attribute="GUID-EntidadeId" description="Id"
                   autolink="True" visible="True" />
        <attribute attribute="GUID-EntidadeDescricao" description="Descrição"
                   autolink="True" visible="True" />
      </attributes>
      <!-- No <actions> at this level in this example -->
      <filter>
        <attributes>
          <filterAttribute name="EntidadeDescricao" description="Descrição" default="" />
        </attributes>
        <conditions>
          <condition value="EntidadeDescricao.IndexOf(&amp;EntidadeDescricao) &gt; 0
                            when not &amp;EntidadeDescricao.IsEmpty()" />
        </conditions>
      </filter>
    </selection>

    <view caption="EntidadeDescricao.ToString()" description="Registro"
          backToSelection="True" masterPage="&lt;default&gt;">
      <parameters>
        <parameter name="EntidadeEmpresaId" null="True" />
        <parameter name="EntidadeId" null="True" />
      </parameters>
      <fixedData>
        <attributes>
          <attribute attribute="GUID-EntidadeDescricao" description="Descrição"
                     autolink="True" visible="True" />
        </attributes>
      </fixedData>
      <tabs>
        <!-- Tabular tab: code="General" is the pattern's convention -->
        <tab name="Geral" code="General" description="Registro"
             type="Tabular" wcname="EntidadeGeneral">
          <attributes>
            <attribute attribute="GUID-EntidadeEmpresaId" description="Emp.Id"
                       autolink="True" visible="True" />
            <attribute attribute="GUID-EntidadeId" description="Id"
                       autolink="True" visible="True" />
            <attribute attribute="GUID-EntidadeDescricao" description="Descrição"
                       autolink="True" visible="True" />
          </attributes>
          <!-- LEVEL 2a: DETAIL actions -->
          <actions>
            <action name="LimpaEstadoExemplo" caption="#"
                    gxobject="GUID-procSampleClearGridState"
                    tooltip="Limpa Filtros na Sessao">
              <parameters>
                <parameter name="&quot;WWExemploEntidade&quot;" />
                <parameter name="false" />
              </parameters>
            </action>
            <action name="Update" />
            <action name="Delete" />
          </actions>
        </tab>
      </tabs>
    </view>
  </level>
</instance>
```

---

## Sanitized example 2 - Complex (1 Tabular tab + Grid tabs + UserDefined tab)

Based on 80-115 KB objects. `<actions>` exists at THREE distinct levels.

```xml
<?xml version="1.0" encoding="utf-16"?>
<instance webFormDefaults="Responsive Web Design" updateTransaction="Apply WW Style">
  <transaction transaction="GUID-Pedido" />
  <level id="GUID-Level:1" name="Pedido">
    <descriptionAttribute attribute="GUID-PedidoNumero" description="Número" />

    <selection description="Pedidos" page="&lt;default&gt;">
      <modes Display="false" Export="false" />
      <attributes>
        <attribute attribute="GUID-PedidoExemploEmpresaId" description="Empresa Id"
                   autolink="True" visible="True" />
        <attribute attribute="GUID-PedidoId" description="Id"
                   autolink="True" visible="True" />
        <attribute attribute="GUID-PedidoNumero" description="Número"
                   autolink="True" visible="True" />
        <!-- inline GeneXus-code variables (removed in this sanitized example) -->
      </attributes>
      <!-- LEVEL 1: LIST actions (reports, exports, batch operations) -->
      <actions>
        <action name="LimpaEstadoExemplo" caption="#"
                gxobject="GUID-procSampleClearGridState"
                tooltip="Limpa Filtros na Sessao">
          <parameters>
            <parameter name="&quot;WWExemploPedido&quot;" />
            <parameter name="false" />
          </parameters>
        </action>
        <action name="RelatorioX" caption="Relatório X"
                gxobject="GUID-procRelatorioX" />
        <action name="ExportaPlanilha" caption="Baixar Planilha"
                gxobject="GUID-procExportaPlanilha" />
      </actions>
      <filter>
        <attributes>
          <filterAttribute name="PedidoData" description="Data" default="" />
          <filterAttribute name="PedidoNumero" description="Número" default="" />
        </attributes>
        <conditions>
          <condition value="PedidoData &gt;= &amp;PedidoDataDe
                            when not &amp;PedidoDataDe.IsEmpty()" />
          <condition value="PedidoData &lt; &amp;PedidoDataAte + 1
                            when not &amp;PedidoDataAte.IsEmpty()" />
        </conditions>
      </filter>
    </selection>

    <view caption="PedidoNumero.ToString()" description="Pedido"
          backToSelection="True" masterPage="&lt;default&gt;">
      <parameters>
        <parameter name="PedidoExemploEmpresaId" null="True" />
        <parameter name="PedidoId" null="True" />
      </parameters>
      <fixedData>
        <attributes>
          <attribute attribute="GUID-PedidoNumero" description="Número"
                     autolink="True" visible="True" />
        </attributes>
      </fixedData>
      <tabs>

        <!-- LEVEL 2a: Tabular tab -- code="General" by pattern convention -->
        <tab name="Geral" code="General" description="Pedido"
             type="Tabular" wcname="PedidoGeneral">
          <attributes>
            <attribute attribute="GUID-PedidoNumero" description="Número"
                       autolink="True" visible="True" />
          </attributes>
          <actions>
            <action name="Update" />
            <action name="Delete" />
            <action name="RelatorioX" caption="Relatório X"
                    gxobject="GUID-procRelatorioX" />
          </actions>
        </tab>

        <!-- LEVEL 2b: Grid tab -- code is the stable identifier for anchoring -->
        <tab name="Itens" code="PedidoItens" type="Grid"
             wcname="PedidoPedidoItensWC" page="&lt;unlimited&gt;"
             condition="procSampleCompanyEnabledForUser(&amp;PedidoExemploEmpresaId)">
          <transaction transaction="GUID-PedidoItens" />
          <modes Insert="false" Update="false" Export="false" />
          <attributes>
            <attribute attribute="GUID-PedidoItensEmpresaId" description="Emp.Id"
                       autolink="True" visible="True" />
            <attribute attribute="GUID-PedidoItensId" description="Id"
                       autolink="True" visible="True" />
          </attributes>
          <!-- LEVEL 2b: actions specific to the child grid -->
          <actions>
            <action name="NovoItem" caption="Novo Item"
                    gxobject="GUID-procNovoItem" />
            <action name="RelatorioY" caption="Relatório Y"
                    gxobject="GUID-procRelatorioY" />
          </actions>
          <orders>
            <order name="Código" isDefault="True">
              <attribute attribute="GUID-PedidoItensCodigo" descending="False" />
            </order>
          </orders>
          <!-- child grid's filter -- independent of the selection's filter -->
          <filter>
            <attributes>
              <filterAttribute name="PedidoItensCodigo" description="Código" default="" />
            </attributes>
            <conditions>
              <condition value="PedidoItensCodigo = &amp;PedidoItensCodigo
                                when not &amp;PedidoItensCodigo.IsEmpty()" />
            </conditions>
          </filter>
        </tab>

        <!-- UserDefined tab: typically no <actions> -->
        <tab name="Documentos Fiscais" code="PedidoDocsFiscais"
             type="UserDefined" wcname="PedidoDocsFiscaisWC">
          <!-- custom content, no <actions> in this example -->
        </tab>

      </tabs>
    </view>
  </level>
</instance>
```

---

## Sanitization applied to the examples

- Real GUIDs replaced with `GUID-DescriptiveName`
- KB attribute names replaced with generic names (`Entidade`, `Pedido`, etc.)
- Inline GeneXus code from `<variable>` removed (replaced with a comment)
- `customStartEventCode` removed
- XML structure, `name`/`code`/`type`/`wcname` attributes, element order, and the `<filter>` pattern preserved

---

## Variability across KBs

- Direct evidence (Gx_SampleKb2): some objects have no `<actions>` in `<selection>` — the block exists only in `<tab>`.
- Direct evidence (Gx_SampleKb): 122/184 have `<actions>` at both levels; 62/184 have it only in `<tab>`.
- Strong inference: the presence or absence of `<actions>` in `<selection>` depends on each object's WorkWithForWeb pattern configuration, not on a universal rule.
- Read-side rule: **always inspect the real XML before drawing a structural conclusion**; do not assume structure from file size or object name. This is not an instruction to perform textual insertion.

---

## Attribute GUID prefix observed in existing CDATA

- Confidence level: **Strong inference — evidence from an inspected external KB** (SampleKb, GeneXus 18 U9 Build 187794)
- In this document's sanitized examples, attribute GUIDs inside the CDATA are represented as `GUID-AttributeName` for clarity.
- In real KBs inspected externally, the `attribute="..."` attribute values inside a `WorkWithForWeb`'s CDATA follow the format `adbb33c9-0906-4971-833c-998de27e0676-AttributeName`, where `adbb33c9-0906-4971-833c-998de27e0676` is the pattern's fixed prefix and `AttributeName` is the GeneXus attribute name.
- Read-side interpretation: when this prefix is encountered in existing CDATA, the suffix is reported as the GeneXus attribute name. This remains a strong inference from the inspected external KB, not a universal guarantee; verify against the real XML before making a claim about a particular KB. This reference does not direct construction or editing of CDATA or import into a KB.
