# 05b - Procedure and Report Families and Templates

## Document role
empirical and read-side

## Predominant confidence level
medium

## Depends on
01-empirical-base-overview.md, 02-operational-rules.md, 03-risk-and-decision-by-type.md

## Used by
08-agent-guide.md, 09-script-inventory.md

## Purpose
Describe structural families of report `Procedure` objects observed in the corpus and provide read-side criteria for comparing their `Source`, `Rules`, and layout.

---

## Sanitization of this document

- Direct evidence: the real names of the objects used as representatives do not appear here.
- Direct evidence: every representative template received a public alias, such as `PRCRelatorioExemploF1`, `PRCRelatorioExemploF2`, and so on.
- Historical note: earlier internal use associated each representative alias with the listed structural criterion; this is not an instruction to locate or reuse a template.
- Hypothesis: this strategy preserves operational usefulness without exposing the KB's business names.

---

## Method

- Direct evidence: 77 report `Procedure` XMLs were analyzed, all with a name starting with the report prefix observed in the KB's corpus.
- Direct evidence: all 77 objects use the same `Object/@type` (`84a12160-f59b-4ad7-a683-ea4481ac23e9`) and the same recurring inventory of 7 `Part` elements.
- Direct evidence: the source-code `Part` uses `type="528d1c06-a9c2-420d-bd35-21dca83f12ff"`.
- Direct evidence: the layout `Part` uses `type="c414ed00-8cc4-4f44-8820-4baf93547173"`, always with a `<Bands><PrintBlock>` structure.
- Direct evidence: none of the 77 objects showed an internal subroutine (`Sub`) in the observed `Source`.
- Direct evidence: the grouping below uses the `PrintBlock` count in the layout `Part`, the presence of `Header`/`Footer` in the source `Part`, and the `For each` count in the `Source`.
- Direct evidence: file sizes in the observed corpus range from 7,161 bytes to 1,115,994 bytes.
- Strong inference: for a report `Procedure`, the structural family is more discriminating than the object's name.
- Editorial rule: this document covers the **modern** report `Procedure` (`Object/@type` `84a12160-...`). The **legacy GeneXus 9** `Report` object (an element identified by name, with no type GUID) was **absorbed** by Procedure and is tracked separately as `orphan` in the `scripts/gx-legacy-export-element-registry.json` registry (`modernSuccessor: Procedure`, owner doc `01k-legacy-element-registry.md`) — do not confuse it with the report-Procedure families described here.

---

## Overview

- Direct evidence: 3 of the 77 objects show neither `Header` nor `Footer` in the `Source` and no `For each` — the embryonic family.
- Direct evidence: 6 of the 77 objects show no `For each` but do have `Header` and/or `Footer` — the base-template family.
- Direct evidence: approximately 29 of the 77 objects have 1 or 2 `For each` — the simple linear-listing family.
- Direct evidence: approximately 22 of the 77 objects have 3 to 6 `For each` with up to 24 `PrintBlock` — the grouping-and-totaling family.
- Direct evidence: approximately 17 of the 77 objects have 7 or more `For each`, or 25 or more `PrintBlock` — the high-volume, high-complexity family.
- Strong inference: the most useful structural split is not business semantics but the presence of iteration, grouping complexity, and layout size.
- Historical inference: earlier generation-oriented notes warned that F4/F5 and F1/F2 differ in `Source` and `PrintBlock` inventory; use that observation only to recognize structural differences, not as cloning guidance.

---

## Family 1 — Embryo with no active layout

- Direct evidence: 3 objects with no `For each`, no `Header`, and no `Footer` in the `Source`.
- Direct evidence: approximate average size 26,759 bytes; minimum 7,161; maximum 65,924.
- Direct evidence: `PrintBlock` count ranges from 1 to 5 across the observed representatives.
- Strong inference: these objects are pre-initialized shells or stubs with no active print body defined yet.
- Historical sanitized representative alias: `PRCRelatorioExemploF1`.
- Historical representative-selection note: smallest observed XML within the range with no `For each` + no `Header` + no `Footer`.
- Historical representative rationale: this alias represented the leanest observed shell with no iteration or page header.

### Structural signature

- 0 `For each` in the `Source`
- no `Header` and no `Footer` in the `Source`
- 1 to 5 `PrintBlock` in the layout
- source and layout `Part` present (7 `Part` total, uniform)
- compact XML, under 70,000 bytes

---

## Family 2 — No iteration with page header/footer

- Direct evidence: 6 objects with no `For each` but with at least one of the `Header` or `Footer` blocks in the `Source`.
- Direct evidence: approximate average size 50,000 bytes; minimum 15,148; maximum 90,389.
- Direct evidence: `PrintBlock` count ranges from 4 to 8.
- Direct evidence: two observed representatives explicitly indicate orientation in the name or in the layout content (portrait and landscape); the rest are neutral.
- Historical inference: earlier notes characterized this family as a starting point for new reports with page headers/footers and no iteration; retain this only as historical context, not a creation recommendation.
- Historical sanitized representative alias: `PRCRelatorioExemploF2`.
- Historical representative-selection note: smallest observed XML within the range with no `For each` + at least one of the `Header`/`Footer` blocks.
- Historical representative rationale: this alias represented a simple page structure without iteration.

### Structural signature

- 0 `For each` in the `Source`
- `Header` and/or `Footer` present in the `Source`
- 4 to 8 `PrintBlock` in the layout
- source and layout `Part` present (7 `Part` total)
- size between 15,000 and 90,000 bytes
- do not confuse with F1: the presence of `Header`/`Footer` distinguishes the two families

---

## Family 3 — Simple linear listing

- Direct evidence: approximately 29 objects with 1 or 2 `For each` in the `Source`.
- Direct evidence: approximate average size 200,000 bytes; minimum 30,819; maximum 580,000.
- Direct evidence: `PrintBlock` count typically ranges from 2 to 16.
- Direct evidence: most have a page `Header` and `Footer`; a minority in this range lacks one or both blocks.
- Strong inference: the main `For each` iterates over the data table with no secondary groups or relevant structural subtotals.
- Historical sanitized representative alias: `PRCRelatorioExemploF3`.
- Historical representative-selection note: smallest observed XML within the 1-to-2 `For each` range.
- Historical representative rationale: this alias represented a lean listing with simple iteration and no grouping.

### Structural signature

- 1 or 2 `For each` in the `Source`
- typically `Header` and `Footer` present in the `Source`
- 2 to 16 `PrintBlock` in the layout
- source and layout `Part` present (7 `Part` total)
- no apparent structural subtotal blocks (inference to confirm by inspecting the representative)
- size varies; the representative is under 35,000 bytes

---

## Family 4 — Report with grouping and totaling

- Direct evidence: approximately 22 objects with 3 to 6 `For each` and up to 24 `PrintBlock`.
- Direct evidence: approximate average size 310,000 bytes; minimum 84,489; maximum 872,615.
- Strong inference: the presence of multiple `For each` indicates grouping with distinct levels, or parallel iterations over related data.
- Direct evidence: `Header` and `Footer` are present in almost all objects of this family.
- Direct evidence: some representatives indicate landscape orientation in the name or content; most are neutral or portrait.
- Historical sanitized representative alias: `PRCRelatorioExemploF4`.
- Historical representative-selection note: smallest observed XML within the 3-to-6 `For each` range with up to 24 `PrintBlock`.
- Historical representative rationale: this alias represented a compact grouping case with multiple iterations, H+F, and explicit landscape orientation.

### Structural signature

- 3 to 6 `For each` in the `Source`
- `Header` and `Footer` present in the `Source`
- 5 to 24 `PrintBlock` in the layout
- source and layout `Part` present (7 `Part` total)
- size typically above 84,000 bytes

---

## Family 5 — Complex, high-volume report

- Direct evidence: approximately 17 objects with 7 or more `For each`, or 25 or more `PrintBlock`.
- Direct evidence: estimated average size above 400,000 bytes; maximum observed 1,115,994 bytes.
- Direct evidence: `PrintBlock` ranges from 5 to 51; some representatives with a high `For each` count have a surprisingly compact layout (5 to 13 `PrintBlock`), indicating heavy reuse of print blocks.
- Strong inference: the density of `For each` in this range suggests multiple grouping levels, cross iterations, or non-trivial accumulators; inspect the complete `Source` before drawing conclusions about the family.
- Historical sanitized representative alias: `PRCRelatorioExemploF5`.
- Historical representative-selection note: smallest observed XML with at least 10 `For each` and at least 20 `PrintBlock`, prioritizing the most compact representative still meeting both criteria at once.
- Historical representative rationale: this alias represented the high-complexity range without being the largest observed XML.

### Structural signature

- 7 or more `For each` in the `Source`, OR 25 or more `PrintBlock` in the layout
- `Header` and `Footer` present in almost all cases
- `PrintBlock` from 5 to 51 (high internal variability)
- source and layout `Part` present (7 `Part` total)
- size above 100,000 bytes; typically above 250,000 bytes

---

## How to choose the family

| Primary criterion | Recommended family |
|---|---|
| No `For each`, no `Header`/`Footer` | F1 |
| No `For each`, with `Header`/`Footer` | F2 |
| 1 or 2 `For each` | F3 |
| 3 to 6 `For each`, up to 24 `PrintBlock` | F4 |
| 7+ `For each` or 25+ `PrintBlock` | F5 |

- Compare the object under review with the family signature closest to its observed structure; the family is a classification aid, not a prescription to create or alter an object.
- When the available object does not establish a structural detail, seek comparable real XML as additional reading evidence and label its source KB; do not infer unobserved structure from sanitized examples.
- Import, build, packaging, and materialization outcomes cannot be assessed by this read-side document.
- Never assume a simply-named object belongs to F1 or F2 without checking `For each` and `Header`/`Footer` in the `Source`.

---

## Historical sanitized examples for structural comparison

- Historical note: previous guidance treated complete sanitized examples as a primary source for materialization; that guidance is retired.
- Read-side rule: label evidence as current-KB XML, other-KB XML, sanitized historical example, or inference, and distinguish observed facts from hypotheses.
- Direct evidence: family `F2` already represents the smallest profile with a working page and no iteration.
- Direct evidence: family `F3` already represents the smallest linear listing with simple iteration.
- Historical inference: earlier notes characterized these two profiles as covering a common simple-report request; this is retained as context, not a recommendation.

### Separate empirical description from example payloads

- Family tables, summaries, frequencies, and risk alerts support structural classification only.
- The complete sanitized XML blocks below are preserved as historical examples of observed shapes; they are not ready-to-use templates and do not authorize cloning or materialization.
- Compare each relevant `Part` with the actual object XML; do not promote an example or family description into a proposed object.

### Observed layer structure

- `Source`: compare the observed print flow, `Header`/`Footer` blocks, `print printBlock...` commands, `For each`, and any `Output_file` call.
- `Rules`: compare observed `parm(...)` and rules, without treating this summary as a syntax prescription.
- Layout `Part c414ed00-8cc4-4f44-8820-4baf93547173`: inspect observed `Bands`, `PrintBlock`, `ReportLabel`, `ReportAttribute`, and structural metadata.
- In comparisons, distinguish observed `Bands`/`PrintBlock` structure from assumptions; note whether `RPT_INTERNAL_NAME`, `PrintBlock` names, and `print printBlock...` references agree across the observed layers.

### Explicit grammar per `Part`

- Observed separation: `Source` contains procedural report and print commands; `Rules` contains `parm(...)` and rules; layout contains `Bands`, `PrintBlock`, `ReportLabel`, `ReportAttribute`, and visual metadata. Compare these layers independently in the actual XML.
- Historical diagnostic observation: semicolon-related reports were previously associated with `Rules` or `Source` respectively; they are not import troubleshooting instructions.
- Do not present invented `GXML`, unobserved controls, or plausible-looking shapes as empirical evidence.

### Observed recurring `Part` shell for report `Procedure`

- Direct evidence: the comparable real representatives observed in this trail repeat the same minimal `Part` order: `528d1c06...` (`Source`), `c414ed00...` (layout), `9b0a32a3...` (`Rules`), `763f0d8b...` (empty auxiliary source), `e4c4ade7...` (variables), `ad3ca970...` (help), and `babf62c5...` (final properties).
- Historical note: the examples below show parts of this recurring shell; they do not define a cloning procedure or authorize object generation.

```xml
<Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">...</Part>
<Part type="c414ed00-8cc4-4f44-8820-4baf93547173">...</Part>
<Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">...</Part>
<Part type="763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9"><Source><![CDATA[]]></Source></Part>
<Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">...</Part>
<Part type="ad3ca970-19d0-44e1-a7b7-db05556e820c"><Help>...</Help></Part>
<Part type="babf62c5-0111-49e9-a1c3-cc004d90900a"><Properties /></Part>
```

### Sanitized historical examples preserved below (not templates)

- `F2-retrato` (portrait): no `For each`, with `Header` and/or `Footer`, portrait orientation, `Output_file` optional.
- `F2-paisagem` (landscape): no `For each`, with `Header` and/or `Footer`, landscape orientation, same minimum structural shape.
- `F3-atributos-diretos` (direct attributes): simple `For each`, `ReportAttribute` pointing at direct attributes of the main cursor.
- `F3-variaveis` (variables): simple `For each` or short pre-processing, `ReportAttribute` pointing at previously loaded variables.

### Historical sanitized example 1 — `F2-retrato` (not for materialization)

- Comparable empirical basis: `procExemploRelatorioBaseA.xml` + `procExemploRelatorioRetratoA.xml`.
- Structural observation: this example shows no iteration, with header/footer blocks and a message or summary block.

```xml
<Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
  <Source><![CDATA[Header
    print printBlockCabecalho
End

Footer
    print printBlockRodape
End

&arquivodesaidanome = 'RelatorioSimples_' + &EmpresaExemploId.ToString();
Output_file(&arquivodesaidanome, 'PDF');

print printBlockMensagem
]]></Source>
  <Properties>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Part>
<Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
  <Layout>
    <Bands>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelTitulo</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>Titulo do relatorio</Value></Property>
              <Property><Name>RPT_X</Name><Value>20</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockCabecalho</Value></Property>
          <Property><Name>RPT_ID</Name><Value>1</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>90</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportAttribute>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>Mensagem</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>AttID</Name><Value>&amp;Mensagem</Value></Property>
              <Property><Name>RPT_X</Name><Value>20</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
              <Property><Name>RPT_WIDTH</Name><Value>760</Value></Property>
            </Properties>
          </ReportAttribute>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockMensagem</Value></Property>
          <Property><Name>RPT_ID</Name><Value>2</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>25</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelPagina</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>{{Pages}}</Value></Property>
              <Property><Name>RPT_X</Name><Value>740</Value></Property>
              <Property><Name>RPT_Y</Name><Value>5</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockRodape</Value></Property>
          <Property><Name>RPT_ID</Name><Value>3</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>20</Value></Property>
        </Properties>
      </PrintBlock>
    </Bands>
    <Properties>
      <Property><Name>RPT_PAPER_SIZE</Name><Value>A4</Value></Property>
      <Property><Name>RPT_RIGHT_MARGIN</Name><Value>20</Value></Property>
    </Properties>
  </Layout>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
<Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
  <Source><![CDATA[parm(in:&EmpresaExemploId, in:&DataInicial);]]></Source>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
<Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
  <Variable Name="arquivodesaidanome">
    <Documentation />
    <Properties>
      <Property><Name>Name</Name><Value>arquivodesaidanome</Value></Property>
      <Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property>
      <Property><Name>Length</Name><Value>255</Value></Property>
      <Property><Name>AttMaxLen</Name><Value>255</Value></Property>
    </Properties>
  </Variable>
  <Variable Name="EmpresaExemploId">
    <Documentation />
    <Properties>
      <Property><Name>Name</Name><Value>EmpresaExemploId</Value></Property>
      <Property><Name>idBasedOn</Name><Value>Attribute:EmpresaExemploId</Value></Property>
    </Properties>
  </Variable>
  <Variable Name="DataInicial">
    <Documentation />
    <Properties>
      <Property><Name>Name</Name><Value>DataInicial</Value></Property>
      <Property><Name>ATTCUSTOMTYPE</Name><Value>bas:Date</Value></Property>
    </Properties>
  </Variable>
  <Variable Name="Mensagem">
    <Documentation />
    <Properties>
      <Property><Name>Name</Name><Value>Mensagem</Value></Property>
      <Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property>
      <Property><Name>Length</Name><Value>255</Value></Property>
      <Property><Name>AttMaxLen</Name><Value>255</Value></Property>
    </Properties>
  </Variable>
</Part>
```

### Historical sanitized example 2 — `F2-paisagem` (not for materialization)

- Comparable empirical basis: `procExemploRelatorioPaisagemA.xml`.
- Structural observation: this `F2` example has landscape-oriented paper size and layout width.
- Structural observation: its layout properties and control widths/coordinates differ from the portrait example.

```xml
<Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
  <Layout>
    <Bands>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelTitulo</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>Titulo do relatorio</Value></Property>
              <Property><Name>RPT_X</Name><Value>20</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockCabecalho</Value></Property>
          <Property><Name>RPT_ID</Name><Value>1</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>90</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportAttribute>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>Mensagem</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>AttID</Name><Value>&amp;Mensagem</Value></Property>
              <Property><Name>RPT_X</Name><Value>20</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
              <Property><Name>RPT_WIDTH</Name><Value>1160</Value></Property>
            </Properties>
          </ReportAttribute>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockMensagem</Value></Property>
          <Property><Name>RPT_ID</Name><Value>2</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>25</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelPagina</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>{{Pages}}</Value></Property>
              <Property><Name>RPT_X</Name><Value>1140</Value></Property>
              <Property><Name>RPT_Y</Name><Value>5</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockRodape</Value></Property>
          <Property><Name>RPT_ID</Name><Value>3</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>20</Value></Property>
        </Properties>
      </PrintBlock>
    </Bands>
    <Properties>
      <Property><Name>RPT_PAPER_SIZE</Name><Value>Custom</Value></Property>
      <Property><Name>RPT_PAPER_ORIENTATION</Name><Value>Landscape</Value></Property>
      <Property><Name>RPT_PAPER_WIDTH</Name><Value>1229</Value></Property>
      <Property><Name>RPT_PAPER_HEIGHT</Name><Value>827</Value></Property>
      <Property><Name>RPT_RIGHT_MARGIN</Name><Value>0</Value></Property>
    </Properties>
  </Layout>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
```

### Historical sanitized example 3 — `F3-atributos-diretos` (not for materialization)

- Comparable empirical basis: `procExemploRelatorioListagemA.xml`.
- Structural observation: this example shows a short linear listing, a simple `For each`, and `ReportAttribute` bound to the main cursor.

```xml
<Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
  <Source><![CDATA[Header
    print printBlockCabecalho
End

&arquivodesaidanome = 'RelatorioDireto_' + &EmpresaExemploId.ToString();
Output_file(&arquivodesaidanome, 'PDF');

For each
    where EmpresaExemploId = &EmpresaExemploId
    order ClienteNome
    print printBlockDetalhe
Endfor

Footer
    print printBlockRodape
End
]]></Source>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
<Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
  <Layout>
    <Bands>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelCabecalho</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>Clientes por empresa</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockCabecalho</Value></Property>
          <Property><Name>RPT_ID</Name><Value>1</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>35</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportAttribute>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>ClienteNome</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>AttID</Name><Value>ClienteNome</Value></Property>
              <Property><Name>RPT_X</Name><Value>20</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
              <Property><Name>RPT_WIDTH</Name><Value>420</Value></Property>
            </Properties>
          </ReportAttribute>
          <ReportAttribute>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>ClienteSaldo</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>AttID</Name><Value>ClienteSaldo</Value></Property>
              <Property><Name>RPT_X</Name><Value>460</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
              <Property><Name>RPT_WIDTH</Name><Value>120</Value></Property>
            </Properties>
          </ReportAttribute>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockDetalhe</Value></Property>
          <Property><Name>RPT_ID</Name><Value>2</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>18</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelRodape</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>{{Pages}}</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockRodape</Value></Property>
          <Property><Name>RPT_ID</Name><Value>3</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>18</Value></Property>
        </Properties>
      </PrintBlock>
    </Bands>
    <Properties>
      <Property><Name>RPT_PAPER_SIZE</Name><Value>A4</Value></Property>
      <Property><Name>RPT_RIGHT_MARGIN</Name><Value>20</Value></Property>
    </Properties>
  </Layout>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
<Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
  <Source><![CDATA[parm(in:&EmpresaExemploId);]]></Source>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
```

### Historical sanitized example 4 — `F3-variaveis` (not for materialization)

- Comparable empirical basis: `procExemploRelatorioListagemA.xml`, in the short pre-processing-before-`print` pattern.
- Structural observation: in this example, the printed line uses variables loaded within the flow rather than the cursor's `AttID` directly.

```xml
<Part type="528d1c06-a9c2-420d-bd35-21dca83f12ff">
  <Source><![CDATA[Header
    print printBlockCabecalho
End

&arquivodesaidanome = 'RelatorioVariaveis_' + &EmpresaExemploId.ToString();
Output_file(&arquivodesaidanome, 'PDF');

For each
    where EmpresaExemploId = &EmpresaExemploId
    &NomeCliente = ClienteNome
    &TotalLiquido = PedidoValorLiquido
    print printBlockDetalhe
Endfor

Footer
    print printBlockRodape
End
]]></Source>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
<Part type="c414ed00-8cc4-4f44-8820-4baf93547173">
  <Layout>
    <Bands>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelCabecalho</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>Resumo por variaveis</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockCabecalho</Value></Property>
          <Property><Name>RPT_ID</Name><Value>1</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>35</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportAttribute>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>NomeCliente</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>AttID</Name><Value>&amp;NomeCliente</Value></Property>
              <Property><Name>RPT_X</Name><Value>20</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
              <Property><Name>RPT_WIDTH</Name><Value>420</Value></Property>
            </Properties>
          </ReportAttribute>
          <ReportAttribute>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>TotalLiquido</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>AttID</Name><Value>&amp;TotalLiquido</Value></Property>
              <Property><Name>RPT_X</Name><Value>460</Value></Property>
              <Property><Name>RPT_Y</Name><Value>0</Value></Property>
              <Property><Name>RPT_WIDTH</Name><Value>120</Value></Property>
            </Properties>
          </ReportAttribute>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockDetalhe</Value></Property>
          <Property><Name>RPT_ID</Name><Value>2</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>18</Value></Property>
        </Properties>
      </PrintBlock>
      <PrintBlock>
        <Controls>
          <ReportLabel>
            <Properties>
              <Property><Name>RPT_INTERNAL_NAME</Name><Value>gxReportLabelRodape</Value></Property>
              <Property><Name>RPT_VISIBLE</Name><Value>True</Value></Property>
              <Property><Name>RPT_TEXT</Name><Value>{{Pages}}</Value></Property>
            </Properties>
          </ReportLabel>
        </Controls>
        <Properties>
          <Property><Name>RPT_INTERNAL_NAME</Name><Value>printBlockRodape</Value></Property>
          <Property><Name>RPT_ID</Name><Value>3</Value></Property>
          <Property><Name>RPT_HEIGHT</Name><Value>18</Value></Property>
        </Properties>
      </PrintBlock>
    </Bands>
    <Properties>
      <Property><Name>RPT_PAPER_SIZE</Name><Value>A4</Value></Property>
      <Property><Name>RPT_RIGHT_MARGIN</Name><Value>20</Value></Property>
    </Properties>
  </Layout>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
<Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
  <Source><![CDATA[parm(in:&EmpresaExemploId);]]></Source>
  <Properties>
    <Property><Name>IsDefault</Name><Value>False</Value></Property>
  </Properties>
</Part>
<Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
  <Variable Name="NomeCliente">
    <Documentation />
    <Properties>
      <Property><Name>Name</Name><Value>NomeCliente</Value></Property>
      <Property><Name>ATTCUSTOMTYPE</Name><Value>bas:VarChar</Value></Property>
      <Property><Name>Length</Name><Value>120</Value></Property>
    </Properties>
  </Variable>
  <Variable Name="TotalLiquido">
    <Documentation />
    <Properties>
      <Property><Name>Name</Name><Value>TotalLiquido</Value></Property>
      <Property><Name>ATTCUSTOMTYPE</Name><Value>bas:Numeric</Value></Property>
      <Property><Name>Decimals</Name><Value>2</Value></Property>
    </Properties>
  </Variable>
</Part>
```

### Structural comparison limits

- The F2 examples show no iteration; the F3 examples show a simple linear listing with a print `For each`.
- Grouping, structural subtotals, multiple print `For each` loops, uncovered controls, and KB-specific dialects require direct evidence from comparable real XML; these examples cannot settle those questions.

### Evidence escalation for structural questions

- First compare the observed object with the empirical family signatures and identify which `Source`, `Rules`, or layout evidence is present.
- If a detail is not established or a KB-specific dialect is suspected, read comparable real XML (preferably from the target KB) and record that provenance.
- This workflow does not diagnose import failures, attempt corrective packages, or prescribe retries.

### Typical dialect/localism signals

- a `parm(...)` signature or report rule outside the simple documented pattern
- an internal naming convention for bands or `PrintBlock` not covered by the canonical templates
- use of a layout feature, property, or shape absent from this base's sanitized representatives
- an unresolved structural difference that may reflect KB-specific conventions; confirm it against comparable real XML

### Historical diagnostic observations (not import guidance)

- Historical reports associated `src0212 invalid control` with layout elements such as `Bands`, `PrintBlock`, and control types.
- Historical reports associated `src0201 output_file invalid type` with `Output_file` in `Source`.
- Historical reports associated `src0119 ';' not longer supported` with `Source`, and `src0056 Missed ';' at the end of the rule` with `Rules`.
- Historical reports associated an error mentioning `parm`, a rule, or rule closure with `Rules`.
- Historical reports associated an error mentioning `For each`, `Header`, `Footer`, `Output_file`, or a procedural function with `Source`.
- These error associations are retained as observations only; this document makes no import diagnosis or corrective prescription.

### Read-side use

- Treat aliases, family tables, descriptions, and the preserved XML examples as structural evidence for comparison only.
- Base conclusions about a specific report on its observed XML; use comparable XML to resolve material gaps and label its provenance.
- This document does not authorize materialization, cloning, packaging, or import.

---

## Structural differences worth checking

- Historical inference: an F2-shaped `Source` and `PrintBlock` inventory may differ substantially from F4; compare those layers rather than assuming family interchangeability.
- Historical inference: an F5 may contain more blocks and iterations than an F3; verify the observed references and iteration structure before drawing conclusions.
- Historical hypothesis: most production reports in this KB belong to F3 or F4; this unverified distribution claim does not imply a template recommendation.
- Read-side rule: do not infer an unseen structure by analogy; inspect comparable real XML and state any remaining uncertainty.
