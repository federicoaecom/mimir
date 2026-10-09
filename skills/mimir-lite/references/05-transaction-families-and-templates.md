# 05 - Transaction Families and Templates

## Document role
empirical and operational

## Predominant confidence level
medium

## Depends on
01-empirical-base-overview.md, 02-operational-rules.md, 03-risk-and-decision-by-type.md

## Used by
08-agent-guide.md

## Purpose
Bring together the observed structural families of Transaction, read-side comparison guidance, and internal consistency signals.

## Consolidated sources
- pre-repository "Transaction Structural Families" document

## Incorporated origin - pre-repository "Transaction Structural Families" document

## Document role
empirical and operational

## Predominant confidence level
medium

## Depends on
01-empirical-base-overview.md, 01b-part-type-matrix-by-type.md, 01c-stable-vs-variable-fields.md, 01d-structural-diffs-by-type.md, 03-risk-and-decision-by-type.md, 02-operational-rules.md

## Used by
02-operational-rules.md, 08-agent-guide.md

## Purpose
Describe structural families of `Transaction` observed in the analyzed XML corpus.
Use family descriptions and sanitized examples to compare XML structure and interpret risk; they do not select or authorize templates for object creation.

## Sanitization of this document

- Direct evidence: the real names of the objects used as representatives do not appear here.
- Direct evidence: every representative template received a public alias, such as `TRNExemploF1`, `TRNExemploF2`, and so on.
- Strong inference: for internal use, the corresponding template can be found again through the structural criterion listed for each family.
- Hypothesis: this strategy preserves operational usefulness without exposing the KB's business names.

## Method

- Direct evidence: 183 `Transaction` XMLs were analyzed.
- Direct evidence: all 183 objects use the same `Object/@type` (`1db606f2-af09-4cf9-a3b5-b481519d28f6`) and the same recurring inventory of 8 `Part type` entries.
- Direct evidence: the 8 `Part type` entries present in 100% of the observed corpus are `264be5fb-1b28-4b25-a598-6ca900dd059f`, `d24a58ad-57ba-41b7-9e6e-eaca3543c778`, `4c28dfb9-f83b-46f0-9cf3-f7e090b525d5`, `9b0a32a3-de6d-4be1-a4dd-1b85d3741534`, `c44bd5ff-f918-415b-98e6-aca44fed84fa`, `e4c4ade7-53f0-4a56-bdfd-843735b66f47`, `ad3ca970-19d0-44e1-a7b7-db05556e820c`, and `babf62c5-0111-49e9-a1c3-cc004d90900a`.
- Direct evidence: all 183 observed objects have `parent` filled in.
- Direct evidence: 169 of the 183 objects have at least one `DescriptionAttribute` block.
- Direct evidence: the grouping below uses the `Level` count, `AttributeProperties` density, presence of sub-levels, and XML size.
- Strong inference: for `Transaction`, the structural family is more discriminating than the object's name.

## Overview

- Direct evidence: 162 of the 183 observed `Transaction` objects have exactly 1 `Level`.
- Direct evidence: 12 of the 183 observed `Transaction` objects have exactly 2 `Level`.
- Direct evidence: 9 of the 183 observed `Transaction` objects have 3 or more `Level`.
- Direct evidence: the overall average of `Part` per object is 8; the overall average of `AttributeProperties` in this slice is approximately 18.
- Strong inference: for read-side comparison, a useful split is the main `Level`'s complexity and the presence of child structure, rather than business semantics.
- Strong inference: a key interpretive risk is treating structurally different `Transaction` families as interchangeable.

## Family 1 - Lean single level

- Direct evidence: 59 objects with `1 Level` and up to 6 `AttributeProperties` blocks.
- Direct evidence: approximate average size 16990 bytes; minimum 7222; maximum 38961.
- Strong inference: low internal variability.
- Public representative: `TRNExemploF1`.
- Private selection criterion: smallest observed XML within the `1 Level` + `0..6 AttributeProperties` range.
- Rationale for the choice: represents the simplest shell of a single-level `Transaction`.

### Structural signature

- 1 main `Level`
- no sub-level
- few `AttributeProperties`
- `DescriptionAttribute` may or may not exist, but when it does it points to an attribute on the same level

### Structural interpretation

- Direct evidence: the central structure is concentrated in the first `Part` with `Level` and `Attribute`.
- Strong inference: object name, description, level attribute names, and `DescriptionAttribute` are identifiable fields; this does not assess edit safety.
- Strong inference: `Part` count, block order, `parent*`, `moduleGuid`, and general `Level` shape are comparison dimensions.
- Hypothesis: this family has the lowest observed structural complexity in this corpus; that does not establish generation safety.

### Read-side interpretation

- Strong inference: this signature describes a simple entity and basic record with no detail.
- Strong inference: the `Level`'s shape and attribute relationships are useful structural comparison features.
- Hypothesis: a sub-level, item grouping, or many derived attributes would be a substantial difference from this observed family.

### Validated case - minimal `Transaction` with 2 attributes

- Historical import evidence (controlled test): a package containing `2` top-level `Attribute` elements, `1` `Transaction`, and `1` `Level` with both attributes was imported successfully. This records a past test outcome, not a current capability or instruction.
- Direct evidence: in this controlled case, the attributes used were one key attribute and one non-key attribute, with no sub-level, no `DescriptionAttribute`, and no `AttributeProperties`.
- Historical import evidence (controlled test): GeneXus ran `Updating table information` after import, indicating physical table materialization in that tested case only.
- Historical import evidence (later test battery): another minimal variant of this slice was also tested with `DescriptionAttribute` and `AttributeProperties`.
- Historical import evidence (later test battery): `AttributeProperties` was accepted both alone and combined with `DescriptionAttribute`.
- Historical import evidence (later test battery): `DescriptionAttribute` was accepted when it pointed to an attribute on the same `Level`.
- Historical error evidence: `Level is empty` appeared in an attempt with attributes present when the main `Part` did not follow the observed structural shape.

### Signature of the validated case

- `1 Level`
- `2 attributes`
- `1` key (`key="True"`)
- `1` non-key (`key="False"`)
- no sub-level
- no `DescriptionAttribute`
- no `AttributeProperties`

### Minimum shape validated in this controlled case

```xml
<Level>
  <Properties />
  <Attribute key="True">AtributoExemploId</Attribute>
  <Attribute key="False">AtributoExemploDescricao</Attribute>
</Level>
```

- Historical import evidence: this shape was accepted by the importer in that case when attributes existed as top-level `Attribute` elements in the same package and the main `Part` preserved the observed structure. This is not an import recipe or authorization.

### Minimal variants validated later

- Direct evidence: family `F1` already has a validated minimal variant with no `DescriptionAttribute` and no `AttributeProperties`.
- Direct evidence: family `F1` already has a validated minimal variant with `DescriptionAttribute`.
- Direct evidence: family `F1` already has a validated minimal variant with `AttributeProperties`.
- Direct evidence: family `F1` already has a validated minimal variant with `DescriptionAttribute` and `AttributeProperties` combined.
- Strong inference: the absence of `DescriptionAttribute` in this trail's first validated minimal case should no longer be read as the family's general pattern, but as a conservative simplification of that initial experiment.

### Structural observations from the `F1` test cases

- Historical import observation: an inline `Attribute` in `Level` did not replace a top-level `Attribute` in the tested package.
- Historical import observation: the tested package supplied absent `Level` attributes as top-level `Attribute` elements; this records test setup, not guidance for assembling a package.
- Structural observation: `DescriptionAttribute` was optional in the tested minimal cases and, when present, pointed to an attribute on the same `Level`.
- Historical import observation: `AttributeProperties` was optional in the tested minimal cases and appeared both alone and combined with `DescriptionAttribute` in accepted test variants.
- Strong inference: in the expanded minimal case, acceptance of the `Level` depended both on the real availability of the attributes and on preserving the main `Part`'s structural shape.

### Historical test setup for the first minimal `F1` package

- Historical test setup: the first minimal `F1` package omitted `DescriptionAttribute`, `AttributeProperties`, and context variables such as `Context` and `TrnContext` until its first successful import.
- Strong inference: that test sequence isolated the minimal shape before adding other structures; it does not prescribe staged import experiments.

### Historical package-shape observations (not current instructions)

- Historical package-shape observation: one tested minimal package placed the `Transaction` in `<Objects>` and referenced attributes in `<Attributes>`; this is a record of the test, not packaging guidance.
- Historical package-shape observation: the tested minimal shape included its key and description/display attributes in `<Attributes>` where used.
- Historical import observation: an inline `Attribute` in `Level` did not replace the matching top-level `Attribute` in that package.
- Historical corpus observation: `TransactionOrObject` appeared as a helper within `<Objects>` in a comparable export, alongside the `<Attributes>` block; this does not define package requirements.
- Historical consistency checks used in the test: `Level/Attribute` GUIDs and names were compared with top-level attributes; `DescriptionAttribute` was checked against the same `Level`. These checks document the past test analysis and do not authorize package creation or import.

### Historical import errors and interpretations

- `Cannot convert Domain to Attribute`
  - operational reading: an attribute required by the `Transaction` was packaged with the wrong top-level type
  - historical interpretation: an attribute was supplied with a different top-level type than expected in that test
- `Attribute 'TesteId' in 'Teste' does not exist`
  - operational reading: the `Level` references an attribute absent from the target KB and absent from `<Attributes>`
  - historical interpretation: the referenced attribute was absent from the destination and tested package
- `DescriptionAttribute ... could not be found in level attributes`
  - operational reading: `DescriptionAttribute` points to an attribute that is not on the same `Level` and/or was not delivered in `<Attributes>`
  - historical interpretation: `DescriptionAttribute` did not resolve to an attribute on the same `Level` or supplied package

## Family 2 - Single level with moderate structural support

- Direct evidence: 41 objects with `1 Level` and between 7 and 11 `AttributeProperties` blocks.
- Direct evidence: approximate average size 33051 bytes; minimum 19543; maximum 55508.
- Strong inference: low-to-medium internal variability.
- Public representative: `TRNExemploF2`.
- Private selection criterion: smallest observed XML within the `1 Level` + `7..11 AttributeProperties` range.
- Rationale for the choice: preserves the same simple single-level design, but with more attributes controlled by properties.

### Structural signature

- 1 main `Level`
- no sub-level
- an intermediate number of `AttributeProperties`
- a greater presence of supporting, audit, or controlled-display attributes

### Structural interpretation

- Strong inference: attribute names, description, and `DescriptionAttribute` occur alongside related `AttributeProperties`; the source does not establish their editability.
- Strong inference: `Level` attributes and corresponding `AttributeProperties` blocks are structurally linked in this family.
- Hypothesis: an attribute/property mismatch is a notable structural inconsistency in this family.

### Read-side interpretation

- Strong inference: this signature describes a simple entity with additional form controls.
- Strong inference: compare observed `AttributeProperties` density with this range and Family 1 before classifying.
- Hypothesis: two levels or substantially higher property density indicate a mismatch with this family.

## Family 3 - Dense single level

- Direct evidence: 42 objects with `1 Level` and between 12 and 30 `AttributeProperties` blocks.
- Direct evidence: approximate average size 53395 bytes; minimum 24510; maximum 149206.
- Strong inference: medium internal variability.
- Public representative: `TRNExemploF3`.
- Private selection criterion: smallest observed XML within the `1 Level` + `12..30 AttributeProperties` range.
- Rationale for the choice: shows a still-single-level `Transaction`, but already with a high number of attributes and related properties.

### Structural signature

- 1 main `Level`
- no sub-level
- many `AttributeProperties`
- strong coupling between declared attributes and internal properties

### Structural interpretation

- Strong inference: consistency among `Attribute`, `AttributeProperties`, and `DescriptionAttribute` is a key structural concern.
- Strong inference: occurrences in the `Level`, properties, and rules help interpret an attribute's relationships.
- Hypothesis: this family describes a `Transaction` with no detail but several auxiliary or controlled columns.

### Read-side interpretation

- Strong inference: this observed family has more `AttributeProperties` than the lean single-level family while retaining one level.
- Strong inference: a short structural diff with no unexplained residual names supports a clearer comparison.
- Hypothesis: a smaller family match or substantial `Level` reordering indicates structural divergence that should be reported.

## Family 4 - Very dense single level

- Direct evidence: 20 objects with `1 Level` and 31 or more `AttributeProperties` blocks.
- Direct evidence: approximate average size 160126 bytes; minimum 52433; maximum 521796.
- Strong inference: high internal variability.
- Public representative: `TRNExemploF4`.
- Private selection criterion: smallest observed XML within the `1 Level` + `31+ AttributeProperties` range.
- Rationale for the choice: represents the ceiling of observed complexity while still having no sub-level.

### Structural signature

- 1 main `Level`
- no sub-level
- very high `AttributeProperties` density
- extensive rule and event blocks usually accompany the structure

### Structural interpretation

- Strong inference: this family represents very dense single-level shapes in the observed corpus.
- Strong inference: the `Level` skeleton, attribute order, and related property inventory are key comparison dimensions.
- Hypothesis: substantial simplification relative to this specimen raises the possibility of residual attributes or metadata.

### Read-side interpretation

- Strong inference: this signature describes many auxiliary, calculated, or controlled attributes without child detail.
- Strong inference: the representative is the smallest observed specimen within this family.
- Hypothesis: a structure resembling Families 2 or 3 may be a closer classification than this denser family.

## Family 5 - Parent-child with two levels

- Direct evidence: 12 objects with exactly `2 Level`.
- Direct evidence: approximate average size 23236 bytes; minimum 8400; maximum 63405.
- Strong inference: medium-to-high internal variability.
- Public representative: `TRNExemploF5`.
- Private selection criterion: smallest observed XML among objects with exactly `2 Level`.
- Rationale for the choice: the smallest observed shape of a header + detail, or parent + item.

### Structural signature

- 1 parent `Level`
- 1 child `Level`
- attributes distributed between header and detail
- `DescriptionAttribute` may appear on the parent level, the child, or both

### Structural interpretation

- Direct evidence: the child level appears nested inside the parent level in the first `Part`.
- Strong inference: level hierarchy, nesting order, and parent/child key relationships are key structural evidence.
- Strong inference: an attribute assigned to a different level without a comparable observed parallel is a significant structural discrepancy.
- Hypothesis: this family requires high caution when drawing conclusions from a comparison.

### Read-side interpretation

- Strong inference: this signature describes a simple header + items structure.
- Strong inference: child detail is the defining structural signal in this family.
- Hypothesis: an object with one level is a poor structural match for this family.

## Family 6 - Multi-level

- Direct evidence: 9 objects with `3` or more `Level`.
- Direct evidence: approximate average size 55436 bytes; minimum 14768; maximum 137656.
- Direct evidence: the maximum observed in this slice was 14 `Level`.
- Strong inference: very high internal variability.
- Public representative: `TRNExemploF6`.
- Private selection criterion: smallest observed XML among objects with `3+ Level`.
- Rationale for the choice: represents the smallest observed shape of a multi-level `Transaction`, avoiding an extreme case as the reference.

### Structural signature

- 3 or more `Level`
- a combination of parent and multiple children
- higher density of attributes, rules, and events tied to transactional context

### Structural interpretation

- Strong inference: this family has the greatest observed level complexity and variability in the sample.
- Strong inference: number of levels, order, nesting, and distribution of attributes across levels are key comparison dimensions.
- Strong inference: creating, removing, or merging levels would depart substantially from the observed structure.
- Hypothesis: interpretation risk is much higher here than in the single-level families.

### Read-side interpretation

- Strong inference: this family describes detail across several blocks or parallel substructures.
- Strong inference: the listed representative is the smallest observed structurally comparable specimen.
- Hypothesis: limited structural similarity to the available specimen leaves substantial uncertainty.

## Per-family structural comparison notes

- Historical practice recorded in the source: materialization used raw XML with the same `Object/@type`; this is not a current instruction or capability.
- Strong inference: a read-side comparison can `identify a likely family -> inspect the object's own XML -> compare Part inventory, order, metadata, and clear parallels -> report uncertainty`; it does not prescribe editing.
- Strong inference: families 1–3 have simpler observed structures than families 5–6; compare their signatures without treating this ordering as a creation workflow.
- Historical risk interpretation: the source described residual base-template data in `Level`, `Attribute`, `AttributeProperties`, and `DescriptionAttribute` as a materialization risk; read these as structural areas to inspect, not a materialization instruction.
- Historical import evidence: a `Transaction` failed despite a correct envelope when its `Level` attributes did not exist in the target KB.
- Direct evidence: a later query against the real corpus confirmed the recurring use of context variables with an `ATTCUSTOMTYPE` such as `sdt:Context`, `sdt:TransactionContext`, and `sdt:TransactionContext.Attribute`
- Strong inference: context-type references are relevant dependencies when interpreting a `Transaction`'s structural evidence.

## Interpreting the historical decision hierarchy

- Historical test evidence: the controlled battery encountered semantic errors involving missing attributes and types despite a valid envelope.
- Strong inference: interpret `Transaction` XML by distinguishing structural family, referenced attributes, context variables, and rules/events; this ordering supports analysis, not target validation.
- Strong inference: missing KB attributes or unresolved context types cannot be confirmed from an isolated XML specimen; report them as unverified dependencies.

## Read-side consistency review

When inspecting a `Transaction` XML, compare each `Level`'s attributes with its `DescriptionAttribute` and `AttributeProperties`; note context variables and their `ATTCUSTOMTYPE` as dependencies requiring separate evidence. These observations describe the inspected XML only and do not verify the destination KB or authorize editing/import.

For interpretation of `Rules` or `Events`, see the "Transaction anti-patterns (GeneXus error catalog)" section in [02a-runtime-notes-and-known-issues.md](02a-runtime-notes-and-known-issues.md#transaction-anti-patterns-genexus-error-catalog).

## Interpreting historical error evidence

- a null `Field: name` on load tends to indicate an invalid shape or an incomplete element, before semantic validation
- the error `Attribute 'X' in 'Transaction Y' does not exist` indicates the XML was structurally accepted, but the declared attributes do not exist at the target
- an `ATTCUSTOMTYPE` error with `sdt:Context`, `sdt:TransactionContext`, or `sdt:TransactionContext.Attribute` indicates those types are missing or unresolved in the target KB
- a simultaneous error of a missing attribute and an invalid `ATTCUSTOMTYPE` should be read as a KB context failure, not an envelope failure
- Historical interpretation: the original notes recommended replacing the template with target-specific attributes and types; that recommendation is retained as historical evidence, not current guidance.

## Structural consistency signals

### When inspecting a `Transaction` XML

- Observe whether the XML is well-formed and has a single `<Object>` root.
- Compare the 8 recurring `Part type` entries, `Level` names, and internal attribute names against this corpus evidence.
- Check whether `DescriptionAttribute` and `AttributeProperties` refer to attributes represented in the inspected structure.
- Record `Context`, `TrnContext`, and `TrnContextAtt` `ATTCUSTOMTYPE` references as dependencies; this document cannot verify that their types exist in a target KB.
- Treat residual names that recur across `Level`, `Attribute`, rules, or events as evidence of coupling or incomplete understanding, not a cloning defect to repair.

### Classic error signals

- `DescriptionAttribute` points to a non-existent attribute
- an attribute appears in the `Level` but has no expected match in the internal properties
- `AttributeProperties` references a missing attribute
- a context variable points to a non-existent or unresolved `sdt` in the KB
- a residual name from the base template remains in `Level`, `Attribute`, rules, or events

## Limits of interpretation

- If an object resembles `F1`, `F2`, or `F3` more than `F5` or `F6`, state the closest observed family and remaining uncertainty; do not treat family labels as template-selection instructions.
- Missing attributes or unresolved `Context`/`TrnContext` types are dependencies that this XML-only evidence cannot validate.
- Redistribution of attributes across levels or an unobserved sub-level is a substantial structural difference; describe it and qualify the conclusion rather than choosing another template.

## Historical XPZ serialization observations

The source recorded use of raw objects and envelopes, preservation of `Part` order and `CDATA`, and consistency checks before packaging. These are historical implementation notes, not current Mimir Lite capability or instructions. Current sync materializes the exported XPZ into the XML corpus; that is distinct from package creation, modification, or import.

## Summary table

| Observed family | Structural pattern | Observed risk | Representative specimen |
| --- | --- | --- | --- |
| Lean single level | simple entity and basic record | medium-high | `TRNExemploF1` |
| Single level with moderate structural support | simple entity with extra properties | high | `TRNExemploF2` |
| Dense single level | simple entity with many attributes and controls | high | `TRNExemploF3` |
| Very dense single level | single-level case with a heavy structural load | very high | `TRNExemploF4` |
| Parent-child with two levels | simple header + detail | very high | `TRNExemploF5` |
| Multi-level | real detail across several blocks | very high | `TRNExemploF6` |

## Final synthesis

- Direct evidence: the `Transaction` corpus is dominated by single-level objects, but is not homogeneous enough to treat everything as a single mold.
- Direct evidence: segmenting by `Level` count and `AttributeProperties` density splits the type into much more stable operational groups.
- Strong inference: Families 1, 2, and 3 account for most of the observed single-level structures.
- Strong inference: Families 5 and 6 have high structural complexity and variability in this sample; interpret comparisons with correspondingly greater caution.
- Hypothesis: the catalog supports structural comparison, while sanitized Markdown/XML examples cannot replace inspected corpus XML as evidence for claims about an actual object.

## Sanitized Transaction XML examples

- Direct evidence: this base now contains 4 complete sanitized `Transaction` XML templates, covering families `F1`, `F2`, `F5`, and `F6`.
- Strong inference: these examples illustrate structures for the represented families, but cannot substitute for inspecting relevant source XML when making structural claims.
- Hypothesis: families `F3` and `F4` lack complete annexes in this document; their structure requires evidence from inspected corpus XML.

### Sanitized template 1 - `TRNExemploF1`

- Family covered: `F1` (`Lean single level`).
- Private selection source: smallest observed XML in the `1 Level` + `0..6 AttributeProperties` range.
- Sanitization applied: the object's name, folder name, visible text, and nominal references were anonymized; `Object/@type`, `Part type`, hierarchy, `parent*`, `moduleGuid`, and the XML structure were preserved.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="89a12723-9ec2-4b97-968b-8e064608788c" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-02-13T11:36:07.0000000Z" checksum="d812a25d493e5088d9bff2b6ca8f2ece" fullyQualifiedName="TRNExemploF1" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="052afbac-555f-4617-a9f5-fe128e0dbbbf" name="TRNExemploF1" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" description="Transacao Exemplo Simples" parent="PastaExemploF1" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="264be5fb-1b28-4b25-a598-6ca900dd059f">
    <Level Name="TRNExemploF1" Type="TRNExemploF1" Description="Transacao Exemplo Simples" Guid="052afbac-555f-4617-a9f5-fe128e0dbbbf">
      <Properties />
      <Attribute key="True" guid="9ede93e1-6f83-4777-a699-59b52f454057">TRNExemploF1Id</Attribute>
      <Attribute key="False" guid="33e5fe1d-8e0d-4761-8120-3363556d7227" isNullable="True">TRNExemploF1Descricao</Attribute>
      <Attribute key="False" guid="a39f2c52-e17e-4ed1-a284-81a44c7829b7" isNullable="True">TRNExemploF1FormularioA</Attribute>
      <Attribute key="False" guid="9af6e684-9665-4b27-8e11-f2d89df2bfc3" isNullable="True">TRNExemploF1MeioDePagamentoNaNFe</Attribute>
    </Level>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWebForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="4c28dfb9-f83b-46f0-9cf3-f7e090b525d5">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWinForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[/* Generated by Work With Pattern [Start] - Do not change */
[web]
{
parm(in:&Mode, in:&TRNExemploF1Id);

TRNExemploF1Id = &TRNExemploF1Id if not &TRNExemploF1Id.IsEmpty();
noaccept(TRNExemploF1Id) if not &TRNExemploF1Id.IsEmpty();
noprompt(TRNExemploF1Id);
}
/* Generated by Work With Pattern [End] - Do not change */

Error("Somente usuário da EquipeExemplo pode editar transacoes de exemplo.") 
	if (Insert or Update or Delete) and not procUsuarioAtualDaEquipeExemplo();


[web]
{
	
	default(TRNExemploF1Id, procTRNExemploF1IdUltimo()+1);
	
}

error("Descricao obrigatoria") 
	if (TRNExemploF1Descricao.IsEmpty()) and
	(Insert or Update);
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[Event Start
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If not IsAuthorized(&PgmName)
		NotAuthorized(&PgmName)
	Endif
	
	&TrnContext.FromXml(&WebSession.Get(!"TrnContext"))
	
	If &Mode = TrnMode.Delete
		btn_Enter.Caption = "GX_BtnDelete"
		btn_Enter.TooltipText = "GX_BtnDelete"
	EndIf
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

Event After Trn
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If (&Mode = TrnMode.Delete and not &TrnContext.CallerOnDelete)
		WWTRNExemploF1()
	Endif
	
	Return
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="TRNExemploF1Id">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TRNExemploF1Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:TRNExemploF1Id</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="Context">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>Context</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:Context</Value>
        </Property>
        <Property>
          <Name>ATT_INITIAL_VALUE</Name>
          <Value>LoadContext.udp()</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="IsAuthorized">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>IsAuthorized</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:Boolean</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TrnContext">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TrnContext</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:TransactionContext</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="WebSession">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>WebSession</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>ext:WebSession</Value>
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
      <Value>TRNExemploF1</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Transacao Exemplo Simples</Value>
    </Property>
    <Property>
      <Name>idISBUSINESSCOMPONENT</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>MasterPage</Name>
      <Value>MasterPageExemplo</Value>
    </Property>
    <Property>
      <Name>SEARCH_VIEWER</Name>
      <Value>c9584656-94b6-4ccd-890f-332d11fc2c25-ViewTRNExemploF1</Value>
    </Property>
    <Property>
      <Name>Apply:78cecefe-be7d-4980-86ce-8d6e91fba04b</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>


```

### Sanitized template 2 - `TRNExemploF2`

- Family covered: `F2` (`Single level with moderate structural support`).
- Private selection source: smallest observed XML in the `1 Level` + `7..11 AttributeProperties` range.
- Sanitization applied: the object's name, rule text, and nominal references were anonymized; the `AttributeProperties` density, `Part` order, `CDATA`, and internal attributes were preserved.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="ce54ed93-ebec-4ed1-b829-873e61f7f6d5" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-02-03T22:38:17.0000000Z" checksum="d06eda3df45da93addccad8d0e0ca531" fullyQualifiedName="TRNExemploF2" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="faf9b44d-1180-4a9a-89b2-d850d82b3ad1" name="TRNExemploF2" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" description="TRNExemploF2" parent="TRNExemploF2" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="264be5fb-1b28-4b25-a598-6ca900dd059f">
    <Level Name="TRNExemploF2" Type="TRNExemploF2" Description="TRNExemploF2" Guid="faf9b44d-1180-4a9a-89b2-d850d82b3ad1">
      <Properties />
      <DescriptionAttribute>TRNExemploF2Id</DescriptionAttribute>
      <AttributeProperties Attribute="TRNExemploF2NomeOriginal">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>True</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2Extensao">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>True</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2NomeOriginalComExtensao">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2Tipo">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>True</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2InclusaoDataHora">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2InclusaoUsuarioId">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2UltimaAtualizacaoDataHora">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2UltimaAtualizacaoUsuarioId">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF2UltimaAtualizacaoUsuarioNome">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <Attribute key="True" guid="2f16f4c6-1aa8-4793-9dd2-7ff2d3d8eddd">TRNExemploF2EmpresaId</Attribute>
      <Attribute key="True" guid="a6c12314-f6b2-47d4-a2a7-4bc5bf6bf921">TRNExemploF2Id</Attribute>
      <Attribute key="False" guid="fa420182-017c-43df-b3c3-ab70c2fd42d1" isNullable="True">TRNExemploF2Conteudo</Attribute>
      <Attribute key="False" guid="4fb14d48-1f8e-408a-82ef-f58a3e796497" isNullable="True">TRNExemploF2ConteudoTexto</Attribute>
      <Attribute key="False" guid="36479911-3b69-4688-a119-7bfd162bf7d4" isNullable="True">TRNExemploF2NomeOriginal</Attribute>
      <Attribute key="False" guid="76001e54-afa1-4d5c-8754-c960fc2d6ee6" isNullable="True">TRNExemploF2Extensao</Attribute>
      <Attribute key="False" guid="61ba4a32-c73c-4ae0-9463-7952694a8378">TRNExemploF2NomeOriginalComExtensao</Attribute>
      <Attribute key="False" guid="263a4e88-1a7e-4214-bc9e-19540b2b9ab8" isNullable="True">TRNExemploF2Tipo</Attribute>
      <Attribute key="False" guid="1468c5ba-7ea6-487c-a78f-854d05e83b32" isNullable="True">TRNExemploF2NomeFormatado</Attribute>
      <Attribute key="False" guid="6cb156f6-5ae6-493e-93a4-19ab13ffc668" isNullable="True">TRNExemploF2ReferenciaDeRegistroDeOutraTabela</Attribute>
      <Attribute key="False" guid="58330f24-6223-498f-b81e-4419b49805c5" isNullable="True">TRNExemploF2InclusaoDataHora</Attribute>
      <Attribute key="False" guid="b0f83946-81b3-4f8e-8711-65266928be0b" isNullable="True">TRNExemploF2InclusaoUsuarioId</Attribute>
      <Attribute key="False" guid="fb723a61-d540-47c0-96b8-f346a9bdf210" isNullable="True">TRNExemploF2UltimaAtualizacaoDataHora</Attribute>
      <Attribute key="False" guid="5d60ee34-7cf5-43ff-9706-5bbebe1aa0c4" isNullable="True">TRNExemploF2UltimaAtualizacaoUsuarioId</Attribute>
      <Attribute key="False" guid="1204b80f-77a8-45ff-a3dc-dcfa6cf71a5f">TRNExemploF2UltimaAtualizacaoUsuarioNome</Attribute>
      <Attribute key="False" guid="2e0075a8-198c-4e25-8dec-8ca1c7031680">TRNExemploF2ResumoExemplo</Attribute>
    </Level>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWebForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="4c28dfb9-f83b-46f0-9cf3-f7e090b525d5">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWinForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[/* Generated by Work With Pattern [Start] - Do not change */
[web]
{
parm(in:&Mode, in:&TRNExemploF2EmpresaId, in:&TRNExemploF2Id);

TRNExemploF2EmpresaId = &TRNExemploF2EmpresaId if not &TRNExemploF2EmpresaId.IsEmpty();
noaccept(TRNExemploF2EmpresaId) if not &TRNExemploF2EmpresaId.IsEmpty();
TRNExemploF2Id = &TRNExemploF2Id if not &TRNExemploF2Id.IsEmpty();
noaccept(TRNExemploF2Id) if not &TRNExemploF2Id.IsEmpty();

TRNExemploF2UltimaAtualizacaoUsuarioId = &Insert_TRNExemploF2UltimaAtualizacaoUsuarioId if &Mode = TrnMode.Insert and not &Insert_TRNExemploF2UltimaAtualizacaoUsuarioId.IsEmpty();
noaccept(TRNExemploF2UltimaAtualizacaoUsuarioId) if &Mode = TrnMode.Insert and not &Insert_TRNExemploF2UltimaAtualizacaoUsuarioId.IsEmpty();}
/* Generated by Work With Pattern [End] - Do not change */

&AgoraExemplo = PRCExemploObtemAgoraA();
&UsuarioExemploAtualId = PRCExemploObtemUsuarioA();

&EmpresaExemploBId = PRCExemploObtemContextoA();

&UsuarioAtualDaEquipeExemplo = procUsuarioAtualDaEquipeExemplo();

error("Não pode alterar. Registro de Empresa diferente da prevista na sessão.") 
	if not (display or insert) and TRNExemploF2EmpresaId <> PRCExemploLeEmpresaAtualA() and
	PRCExemploEmpresaVinculadaA(TRNExemploF2EmpresaId, &EmpresaExemploBId) = false and
	TRNExemploF2EmpresaId <> PRCExemploEmpresaDoUsuarioA() and
	PRCExemploObtemContextoB(TRNExemploF2EmpresaId) <> PRCExemploLeEmpresaAtualA();

[web]
{

	TRNExemploF2Id.Enabled = false;

	//Esconder para nao ser manualmente copiado e para não atrapalhar a deleção
	TRNExemploF2ConteudoTexto.Visible = false 
		if (not TRNExemploF2Conteudo.IsEmpty() and not TRNExemploF2Conteudo.IsNull()) or
		(not insert and not TRNExemploF2ConteudoTexto.IsEmpty() and not TRNExemploF2ConteudoTexto.IsNull() and
		(TRNExemploF2Tipo.ToLower() = ".xml" or TRNExemploF2Extensao.ToLower() = "xml"));
		
	//desligar para nao estragar, se for usado o blob (TRNExemploF2Conteudo)	
	TRNExemploF2NomeOriginal.Enabled = false 
		if not TRNExemploF2Conteudo.IsEmpty() and not TRNExemploF2Conteudo.IsNull();
	TRNExemploF2Extensao.Enabled = false
		if not TRNExemploF2Conteudo.IsEmpty() and not TRNExemploF2Conteudo.IsNull();
	TRNExemploF2Tipo.Enabled = &UsuarioAtualDaEquipeExemplo
		if not TRNExemploF2Conteudo.IsEmpty() and not TRNExemploF2Conteudo.IsNull();
	
	TRNExemploF2NomeFormatado.Enabled = false
		if not TRNExemploF2Conteudo.IsEmpty() and not TRNExemploF2Conteudo.IsNull();

	&modificado = modified() on BeforeUpdate;
	
}

[bc]
{
	
	//em bc nao funciona modified()
	//falta observar cada campo.
	&modificado = true
	 if update 
		on BeforeUpdate;
		
}

//Define as empresas escondidas
Default(TRNExemploF2EmpresaId, PRCExemploLeEmpresaAtualA());


Default(TRNExemploF2InclusaoDataHora, &AgoraExemplo);
Default(TRNExemploF2InclusaoUsuarioId, &UsuarioExemploAtualId);
Default(TRNExemploF2UltimaAtualizacaoDataHora, &AgoraExemplo);
Default(TRNExemploF2UltimaAtualizacaoUsuarioId, &UsuarioExemploAtualId);

TRNExemploF2UltimaAtualizacaoDataHora = &AgoraExemplo if update and &modificado on BeforeUpdate;
TRNExemploF2UltimaAtualizacaoUsuarioId = &UsuarioExemploAtualId if update and &modificado on BeforeUpdate;

Error("Erro: Data e hora de contexto nao foi determinada. ") 
	if (insert or update) and &AgoraExemplo.IsEmpty();
	
Error("Erro: Data e hora de inclusao nao foi determinada. Contexto atual: " + &AgoraExemplo.ToString()) 
	if insert and not &AgoraExemplo.IsEmpty() and
		(TRNExemploF2InclusaoDataHora.IsEmpty() or TRNExemploF2InclusaoDataHora.IsNull());

Error("Erro: Usuario da sessao nao foi determinado. ") 
	if (insert or update) and &UsuarioExemploAtualId.IsEmpty();
	
Error("Erro: Usuario da inclusao nao foi determinado. Usuario da sessao: " + &UsuarioExemploAtualId.ToString()) 
	if insert and not &UsuarioExemploAtualId.IsEmpty() and 
		(TRNExemploF2InclusaoUsuarioId.IsEmpty() or TRNExemploF2InclusaoUsuarioId.IsNull());

Error("Erro: Nenhuma alteracao detectada para salvar.") 
	if update and not &modificado on BeforeUpdate;


TRNExemploF2Tipo = "." + TRNExemploF2Extensao.ToLower() 
	if (insert or update) and (TRNExemploF2Tipo.IsEmpty() or TRNExemploF2Tipo.IsNull());
	
error("Nome original do registro e obrigatorio.") 
	if (TRNExemploF2NomeOriginal.IsEmpty() or TRNExemploF2NomeOriginal.IsNull()) and (insert or update);

error("Extensao do registro e obrigatoria. Nome original: " + TRNExemploF2NomeOriginal) 
	if (TRNExemploF2Extensao.IsEmpty() or TRNExemploF2Extensao.IsNull()) and (insert or update);

error("Tipo do registro e obrigatorio.") 
	if (TRNExemploF2Tipo.IsEmpty() or TRNExemploF2Tipo.IsNull()) and (insert or update);

error("Nao pode usar os dois campos de conteudo ao mesmo tempo.") 
	if (insert or update) and not TRNExemploF2Conteudo.IsEmpty() and TRNExemploF2Conteudo.IsNull() and
	not TRNExemploF2ConteudoTexto.IsEmpty() and not TRNExemploF2ConteudoTexto.IsNull();
	
//Enquanto não houver garantia de que a gravação não mude nada, invalidando a assinatura, é proibido usar xml no campo de texto
error("Nao pode colocar XML no campo de conteudo textual.") 
	if (insert or update) and not TRNExemploF2ConteudoTexto.IsEmpty() and not TRNExemploF2ConteudoTexto.IsNull() and
	(TRNExemploF2Tipo.ToLower() = ".xml" or TRNExemploF2Extensao.ToLower() = "xml");

msg("Delecao do registro Id " + TRNExemploF2Id.ToString() + ", da Empresa Exemplo Id " + TRNExemploF2EmpresaId.ToString() + ".") 
	on BeforeDelete;
	
TRNExemploF2Id = procTRNExemploF2IdUltimo(TRNExemploF2EmpresaId)+1 
	on BeforeInsert;
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[//Event Start
Event Start
	
	[web]
	{
		
		//if &Mode = TrnMode.Insert
		if &Mode = TrnMode.Insert
			
			TRNExemploF2ResumoExemplo.Visible = false
			
		endif

	}
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If not IsAuthorized(&PgmName)
		NotAuthorized(&PgmName)
	Endif
	
	&TrnContext.FromXml(&WebSession.Get(!"TrnContext"))
	&Insert_TRNExemploF2UltimaAtualizacaoUsuarioId.SetEmpty()
	
	If (&TrnContext.TransactionName = &Pgmname and &Mode = TrnMode.Insert)
		For &TrnContextAtt in &TrnContext.Attributes
			Do Case
				// When inserting with instantiated TRNExemploF2UltimaAtualizacaoUsuarioId
				Case &TrnContextAtt.AttributeName = !"TRNExemploF2UltimaAtualizacaoUsuarioId"
					&Insert_TRNExemploF2UltimaAtualizacaoUsuarioId.FromString(&TrnContextAtt.AttributeValue)
			Endcase
		Endfor
	Endif
	
	If &Mode = TrnMode.Delete
		btn_Enter.Caption = "GX_BtnDelete"
		btn_Enter.TooltipText = "GX_BtnDelete"
	EndIf
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

Event After Trn
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If (&Mode = TrnMode.Delete and not &TrnContext.CallerOnDelete)
		WWTRNExemploF2()
	Endif
	
	Return
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="TRNExemploF2EmpresaId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TRNExemploF2EmpresaId</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:TRNExemploF2EmpresaId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TRNExemploF2Id">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TRNExemploF2Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:TRNExemploF2Id</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="EmpresaExemploBId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>EmpresaExemploBId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Empresa Exemplo B Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:EmpresaExemploBId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="Context">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>Context</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:Context</Value>
        </Property>
        <Property>
          <Name>ATT_INITIAL_VALUE</Name>
          <Value>LoadContext.udp()</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AgoraExemplo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AgoraExemplo</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Agora Exemplo</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:DomainExemploDataHora</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="Insert_TRNExemploF2UltimaAtualizacaoUsuarioId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>Insert_TRNExemploF2UltimaAtualizacaoUsuarioId</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:TRNExemploF2UltimaAtualizacaoUsuarioId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="IsAuthorized">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>IsAuthorized</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:Boolean</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="modificado">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>modificado</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Logico</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="UsuarioExemploAtualId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>UsuarioExemploAtualId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Usuario Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:UsuarioId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TrnContext">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TrnContext</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:TransactionContext</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TrnContextAtt">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TrnContextAtt</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:TransactionContext.Attribute</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="UsuarioAtualDaEquipeExemplo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>UsuarioAtualDaEquipeExemplo</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Logico</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="WebSession">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>WebSession</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>ext:WebSession</Value>
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
    <InnerHtml><![CDATA[]]></InnerHtml>
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
      <Value>TRNExemploF2</Value>
    </Property>
    <Property>
      <Name>idISBUSINESSCOMPONENT</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>MasterPage</Name>
      <Value>MasterPageExemplo</Value>
    </Property>
    <Property>
      <Name>SEARCH_VIEWER</Name>
      <Value>c9584656-94b6-4ccd-890f-332d11fc2c25-ViewTRNExemploF2</Value>
    </Property>
    <Property>
      <Name>Apply:78cecefe-be7d-4980-86ce-8d6e91fba04b</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>


```

### Sanitized template 3 - `TRNExemploF5`

- Family covered: `F5` (`Parent-child with two levels`).
- Private selection source: smallest observed XML among objects with exactly `2 Level`.
- Sanitization applied: the object's name, folder, visible text, and nominal references were anonymized; the parent-child relationship, `Level` nesting, `Part type`, and event blocks were preserved.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="58642553-5027-46f1-87ff-1bc58bd199bb" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-02-13T11:36:51.0000000Z" checksum="bfa712cf324ee53b4c42659a99af770d" fullyQualifiedName="TRNExemploF5" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="7e90ece0-aa8a-4729-b8df-fa881162ac23" name="TRNExemploF5" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" description="Transacao Exemplo Pai Filho" parent="PastaExemploF5" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="264be5fb-1b28-4b25-a598-6ca900dd059f">
    <Level Name="TRNExemploF5" Type="TRNExemploF5" Description="Transacao Exemplo Pai Filho" Guid="7e90ece0-aa8a-4729-b8df-fa881162ac23">
      <Properties />
      <DescriptionAttribute>TRNExemploF5UsuarioId</DescriptionAttribute>
      <Attribute key="True" guid="4ffc68ce-31c0-4686-927f-39b89968ed1b">TRNExemploF5Id</Attribute>
      <Attribute key="False" guid="986b9d7d-c12f-4169-a53a-90890a21fd21">TRNExemploF5UsuarioId</Attribute>
      <Attribute key="False" guid="16e5f1ed-2dbc-4ce5-a9b4-98357563f9ac">TRNExemploF5UsuarioNome</Attribute>
      <Level Name="Item" Type="Item" Description="Item" Guid="3d935da8-ed64-4b27-9a1c-d69bd389065c">
        <Properties />
        <Attribute key="True" guid="415730e5-7a99-4c9f-a189-cad861edf8af">TRNExemploF5ItemId</Attribute>
        <Attribute key="False" guid="3be62149-638d-466c-9b9c-c8348e43a57b" isNullable="True">TRNExemploF5ItemCodigo</Attribute>
      </Level>
    </Level>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWebForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="4c28dfb9-f83b-46f0-9cf3-f7e090b525d5">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWinForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[/* Generated by Work With Pattern [Start] - Do not change */
[web]
{
parm(in:&Mode, in:&TRNExemploF5Id);

TRNExemploF5Id = &TRNExemploF5Id if not &TRNExemploF5Id.IsEmpty();
noaccept(TRNExemploF5Id);
noprompt(TRNExemploF5Id);

TRNExemploF5UsuarioId = &Insert_TRNExemploF5UsuarioId if &Mode = TrnMode.Insert and not &Insert_TRNExemploF5UsuarioId.IsEmpty();
noaccept(TRNExemploF5UsuarioId) if &Mode = TrnMode.Insert and not &Insert_TRNExemploF5UsuarioId.IsEmpty();}
/* Generated by Work With Pattern [End] - Do not change */
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[Event Start
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If not IsAuthorized(&PgmName)
		NotAuthorized(&PgmName)
	Endif
	
	&TrnContext.FromXml(&WebSession.Get(!"TrnContext"))
	&Insert_TRNExemploF5UsuarioId.SetEmpty()
	
	If (&TrnContext.TransactionName = &Pgmname and &Mode = TrnMode.Insert)
		For &TrnContextAtt in &TrnContext.Attributes
			Do Case
				// When inserting with instantiated TRNExemploF5UsuarioId
				Case &TrnContextAtt.AttributeName = !"TRNExemploF5UsuarioId"
					&Insert_TRNExemploF5UsuarioId.FromString(&TrnContextAtt.AttributeValue)
			Endcase
		Endfor
	Endif
	
	If &Mode = TrnMode.Delete
		btn_Enter.Caption = "GX_BtnDelete"
		btn_Enter.TooltipText = "GX_BtnDelete"
	EndIf
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

Event After Trn
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If (&Mode = TrnMode.Delete and not &TrnContext.CallerOnDelete)
		WWTRNExemploF5()
	Endif
	
	Return
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="TRNExemploF5Id">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TRNExemploF5Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:TRNExemploF5Id</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="Context">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>Context</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:Context</Value>
        </Property>
        <Property>
          <Name>ATT_INITIAL_VALUE</Name>
          <Value>LoadContext.udp()</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="IsAuthorized">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>IsAuthorized</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:Boolean</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TrnContext">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TrnContext</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:TransactionContext</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="WebSession">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>WebSession</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>ext:WebSession</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="Insert_TRNExemploF5UsuarioId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>Insert_TRNExemploF5UsuarioId</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:TRNExemploF5UsuarioId</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TrnContextAtt">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TrnContextAtt</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:TransactionContext.Attribute</Value>
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
      <Value>TRNExemploF5</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Transacao Exemplo Pai Filho</Value>
    </Property>
    <Property>
      <Name>MasterPage</Name>
      <Value>MasterPageExemplo</Value>
    </Property>
    <Property>
      <Name>Apply:78cecefe-be7d-4980-86ce-8d6e91fba04b</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>

```

### Sanitized template 4 - `TRNExemploF6`

- Family covered: `F6` (`Multi-level`).
- Private selection source: smallest observed XML among objects with `3+ Level`, chosen for better public readability.
- Sanitization applied: the object's name, sub-level names, business text, and nominal references were anonymized; the number of levels, nesting order, `Part type`, `CDATA`, and structural density were preserved.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Object parentGuid="6d11a7a7-ec1e-4146-a117-13ebbfee039d" user="SANITIZED\\USER" versionDate="0001-01-01T00:00:00.0000000" lastUpdate="2026-02-13T12:44:01.0000000Z" checksum="424d6aabdc4b36acc0cb4bf6ae7a4201" fullyQualifiedName="TRNExemploF6" moduleGuid="afa47377-41d5-4ae8-9755-6f53150aa361" guid="97c85899-a22a-48de-9109-6e0f02e24e45" name="TRNExemploF6" type="1db606f2-af09-4cf9-a3b5-b481519d28f6" description="Transacao Exemplo Multinivel" parent="TRNExemploF6" parentType="00000000-0000-0000-0000-000000000008">
  <Part type="264be5fb-1b28-4b25-a598-6ca900dd059f">
    <Level Name="TRNExemploF6" Type="TRNExemploF6" Description="Transacao Exemplo Multinivel" Guid="97c85899-a22a-48de-9109-6e0f02e24e45">
      <Properties />
      <AttributeProperties Attribute="TRNExemploF6Resumo">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF6ResumoDeTiposDeEnvios">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF6ResumoDeTiposDePedidos">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF6ResumoB">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF6InclusaoDataHora">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF6InclusaoUsuarioId">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF6UltimaAtualizacaoDataHora">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <AttributeProperties Attribute="TRNExemploF6UltimaAtualizacaoUsuarioId">
        <Properties>
          <Property>
            <Name>IncludeInForms</Name>
            <Value>False</Value>
          </Property>
        </Properties>
      </AttributeProperties>
      <Attribute key="True" guid="13f1e8b6-5e12-4ce8-bb0d-07af1c18b1d4">TRNExemploF6Codigo</Attribute>
      <Attribute key="False" guid="4bb34dd1-98b0-4506-aa0b-688bf1feda44" isNullable="True">TRNExemploF6Descricao</Attribute>
      <Attribute key="False" guid="fa5fc72d-6dab-47bc-bfd2-b19c436414cd" isNullable="True">TRNExemploF6Aplicacao</Attribute>
      <Attribute key="False" guid="8b99f008-12ee-4d5c-a771-de51f375cf4d" isNullable="True">TRNExemploF6TipoMovimento</Attribute>
      <Attribute key="False" guid="c8d211d3-155a-4ada-b50b-13f4087326e6" isNullable="True">TRNExemploF6IndicadorB</Attribute>
      <Attribute key="False" guid="ca4f5723-dc5b-44ec-9aea-41d36c4c5da3" isNullable="True">TRNExemploF6IndicadorC</Attribute>
      <Attribute key="False" guid="991c58ee-4ad8-4b9c-8505-62580a27dafa" isRedundant="True">TRNExemploF6Resumo</Attribute>
      <Level Name="SubNivelA" Type="SubNivelA" Description="Subnivel A" Guid="64a917e1-93c6-41b2-98c0-bfbbd8f3534a">
        <Properties />
        <DescriptionAttribute>(None)</DescriptionAttribute>
        <AttributeProperties Attribute="TRNExemploF6SubNivelATipoMovimento">
          <Properties>
            <Property>
              <Name>IncludeInForms</Name>
              <Value>False</Value>
            </Property>
          </Properties>
        </AttributeProperties>
        <Attribute key="True" guid="cd66d50c-e7db-49e6-b3b8-687c5a866bc4">TRNExemploF6SubNivelA</Attribute>
        <Attribute key="False" guid="f3328569-f769-4168-b132-c07378397aa9">TRNExemploF6SubNivelATipoMovimento</Attribute>
        <Attribute key="False" guid="3162b24d-b74b-4329-82af-c875415ba99c" isNullable="True">TRNExemploF6SubNivelATipoPedido</Attribute>
        <Attribute key="False" guid="e7bf312d-abad-4459-886f-a3466a06351d" isNullable="True">TRNExemploF6SubNivelATipoPedido2</Attribute>
        <Attribute key="False" guid="766673d6-f021-476f-8dfd-6aa5ae568402" isNullable="True">TRNExemploF6SubNivelATipoPedido3</Attribute>
      </Level>
      <Attribute key="False" guid="93d11b4f-fc89-4baa-916c-a5e9dee8df0b">TRNExemploF6ResumoDeTiposDeEnvios</Attribute>
      <Attribute key="False" guid="15f5b4da-4853-4458-9879-9d83df9591a2">TRNExemploF6ResumoDeTiposDePedidos</Attribute>
      <Attribute key="False" guid="849d555e-de5f-4e7c-a72d-e460421fbc62" isNullable="True">TRNExemploF6CompoeTotalGeral</Attribute>
      <Attribute key="False" guid="c3509e0d-73ea-4f94-90bb-9a7bc9dd22a7" isNullable="True">TRNExemploF6DFeAdicionalCFOP</Attribute>
      <Attribute key="False" guid="cfd6b6df-d1e0-4abc-831f-caa560469fa7" isNullable="True">TRNExemploF6IndicadorA</Attribute>
      <Attribute key="False" guid="7b319304-8db8-4773-b520-f6b3596e0eef" isNullable="True">TRNExemploF6ParaSemTransitoNoEstabelecimento</Attribute>
      <Level Name="SubNivelB" Type="SubNivelB" Description="Subnivel B" Guid="659c7bf9-81a7-43a9-ad6a-95777d322fb5">
        <Properties />
        <DescriptionAttribute>(None)</DescriptionAttribute>
        <Attribute key="True" guid="f7f07145-7537-4ade-b26c-609f4ca4a6e4">TRNExemploF6SubNivelB</Attribute>
        <Attribute key="False" guid="107ee86e-7bbc-48e4-9548-c9e25b8d6868" isNullable="True">TRNExemploF6SubNivelBObservacao</Attribute>
      </Level>
      <Attribute key="False" guid="eec831fb-63b4-4ce3-a72c-649389b6bf15">TRNExemploF6ResumoB</Attribute>
      <Attribute key="False" guid="0129eda9-58d2-4379-b328-b2e6861bfb05" isNullable="True">TRNExemploF6InclusaoDataHora</Attribute>
      <Attribute key="False" guid="25c9e71f-fa83-4dad-b734-34d2cd94daf5" isNullable="True">TRNExemploF6InclusaoUsuarioId</Attribute>
      <Attribute key="False" guid="b02f55f1-03f3-428e-8f9e-521972d418ab" isNullable="True">TRNExemploF6UltimaAtualizacaoDataHora</Attribute>
      <Attribute key="False" guid="be935771-6841-4066-8da0-ad1134649b5f" isNullable="True">TRNExemploF6UltimaAtualizacaoUsuarioId</Attribute>
      <Attribute key="False" guid="3a01706f-0ed2-4388-98ab-6aed2dd77627">TRNExemploF6ResumoExemplo</Attribute>
    </Level>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="d24a58ad-57ba-41b7-9e6e-eaca3543c778">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWebForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="4c28dfb9-f83b-46f0-9cf3-f7e090b525d5">
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>True</Value>
      </Property>
      <Property>
        <Name>Defaults</Name>
        <Value>gx:TrnDefaultWinForm.dkt</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="9b0a32a3-de6d-4be1-a4dd-1b85d3741534">
    <Source><![CDATA[/* Generated by Work With Pattern [Start] - Do not change */
[web]
{
parm(in:&Mode, in:&TRNExemploF6Codigo);

TRNExemploF6Codigo = &TRNExemploF6Codigo if not &TRNExemploF6Codigo.IsEmpty();
noaccept(TRNExemploF6Codigo) if not &TRNExemploF6Codigo.IsEmpty();
noprompt(TRNExemploF6Codigo);
}
/* Generated by Work With Pattern [End] - Do not change */

&AgoraExemplo = PRCExemploObtemAgoraA();

&UsuarioExemploAtualId = PRCExemploObtemUsuarioA();

[web]
{

	GridTRNExemploF6_SubNivelA.Rows = 1;
	GridTRNExemploF6_SubNivelB.Rows = 0;

	&modificado = modified() on BeforeUpdate;
	
}

[bc]
{

//	TRNExemploF6SubNivelA = SubNivelA.ValorA
//		if (TRNExemploF6SubNivelA.IsEmpty() or TRNExemploF6SubNivelA.IsNull()) and
//			not TRNExemploF6SubNivelATipoPedido.IsEmpty() and not TRNExemploF6SubNivelATipoPedido.IsNull();
	
	//em bc nao funciona modified()
	//falta observar cada campo.
	&modificado = true
	 if update 
		on BeforeUpdate;
		
}


Default(TRNExemploF6InclusaoDataHora, &AgoraExemplo);
Default(TRNExemploF6InclusaoUsuarioId, &UsuarioExemploAtualId);
Default(TRNExemploF6UltimaAtualizacaoDataHora, &AgoraExemplo);
Default(TRNExemploF6UltimaAtualizacaoUsuarioId, &UsuarioExemploAtualId);

TRNExemploF6UltimaAtualizacaoDataHora = &AgoraExemplo if update and &modificado on BeforeUpdate;
TRNExemploF6UltimaAtualizacaoUsuarioId = &UsuarioExemploAtualId if update and &modificado on BeforeUpdate;

Error("Erro: Data e hora de contexto nao foi determinada. ") 
	if (insert or update) and &AgoraExemplo.IsEmpty();
	
Error("Erro: Data e hora de inclusao nao foi determinada. Contexto atual: " + &AgoraExemplo.ToString()) 
	if insert and not &AgoraExemplo.IsEmpty() and
		(TRNExemploF6InclusaoDataHora.IsEmpty() or TRNExemploF6InclusaoDataHora.IsNull());

Error("Erro: Usuario da sessao nao foi determinado. ") 
	if (insert or update) and &UsuarioExemploAtualId.IsEmpty();
	
Error("Erro: Usuario da inclusao nao foi determinado. Usuario da sessao: " + &UsuarioExemploAtualId.ToString()) 
	if insert and not &UsuarioExemploAtualId.IsEmpty() and 
		(TRNExemploF6InclusaoUsuarioId.IsEmpty() or TRNExemploF6InclusaoUsuarioId.IsNull());

Error("Erro: Nenhuma alteracao detectada para salvar.") 
	if update and not &modificado on BeforeUpdate;


error("Erro: Codigo obrigatorio.") 
	if (insert or update) and 
	(TRNExemploF6Codigo.IsEmpty() or TRNExemploF6Codigo.IsNull());

msg("Alerta: Para ValorA de Saida ou Devolução de Saida, normalmente se define o Tipo de Pedido para DF.") 
	if (TRNExemploF6SubNivelA = SubNivelA.ValorA or
	TRNExemploF6SubNivelA = SubNivelA.ValorB) and
	TRNExemploF6SubNivelATipoPedido.IsEmpty();

error("Erro: Subnivel A é obrigatório.")
	if TRNExemploF6SubNivelA.IsEmpty() or TRNExemploF6SubNivelA.IsNull();

error("Erro: Subnivel A com um Tipo de Movimento ( " + TRNExemploF6SubNivelATipoMovimento.ToString() + 
	" ) diferente do Tipo de Movimento ( " + TRNExemploF6TipoMovimento.ToString() + " ) indicado na Transacao Exemplo Multinivel.") 
	if not TRNExemploF6TipoMovimento.IsEmpty() and not TRNExemploF6TipoMovimento.IsNull() and
	not TRNExemploF6SubNivelA.IsEmpty() and not TRNExemploF6SubNivelA.IsNull() and
	TRNExemploF6SubNivelATipoMovimento <> TRNExemploF6TipoMovimento;

msg('Alerta Extremo: "Envio de ValorA de Saida" não deverá realmente ser criado para "Valor02 de Entrega Futura".')
	if TRNExemploF6SubNivelA = SubNivelA.ValorA and
	TRNExemploF6SubNivelATipoPedido = EnumTipoPedidoExemplo.Valor01;
	
error("Erro: Tipo de Pedido ( " + TRNExemploF6SubNivelATipoPedido.ToString() + 
	" ) é inválido para Envio de ValorA de Saida.")
	if TRNExemploF6SubNivelA = SubNivelA.ValorA and
	not TRNExemploF6SubNivelATipoPedido.IsEmpty() and not TRNExemploF6SubNivelATipoPedido.IsNull() and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor02 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor01 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor03 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor04 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor05 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor06 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor07 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor08 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor09 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor10 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor11 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor12 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor13 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor14 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor15;

error("Erro: Tipo de Pedido 2 ( " + TRNExemploF6SubNivelATipoPedido2.ToString() + 
	" ) é inválido para Envio de ValorA de Saida.")
	if TRNExemploF6SubNivelA = SubNivelA.ValorA and
	not TRNExemploF6SubNivelATipoPedido2.IsEmpty() and not TRNExemploF6SubNivelATipoPedido2.IsNull() and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor02 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor03 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor04 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor05 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor06 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor07 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor08 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor09 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor10 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor11 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor12 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor13 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor14 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor15;
error("Erro: Tipo de Pedido 3 ( " + TRNExemploF6SubNivelATipoPedido3.ToString() + 
	" ) é inválido para Envio de ValorA de Saida.")
	if TRNExemploF6SubNivelA = SubNivelA.ValorA and
	not TRNExemploF6SubNivelATipoPedido3.IsEmpty() and not TRNExemploF6SubNivelATipoPedido3.IsNull() and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor02 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor03 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor04 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor05 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor06 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor07 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor08 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor09 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor10 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor11 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor12 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor13 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor14 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor15;

error("Erro: Tipo de Pedido ( " + TRNExemploF6SubNivelATipoPedido.ToString() + 
	" ) é inválido para Envio de Devolução de Saida.")
	if TRNExemploF6SubNivelA = SubNivelA.ValorB and
	not TRNExemploF6SubNivelATipoPedido.IsEmpty() and not TRNExemploF6SubNivelATipoPedido.IsNull() and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor02 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor10 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor13 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor14 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor06 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor04 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor03 and
	TRNExemploF6SubNivelATipoPedido <> EnumTipoPedidoExemplo.Valor05;
error("Erro: Tipo de Pedido 2 ( " + TRNExemploF6SubNivelATipoPedido2.ToString() + 
	" ) é inválido para Envio de Devolução de Saida.")
	if TRNExemploF6SubNivelA = SubNivelA.ValorB and
	not TRNExemploF6SubNivelATipoPedido2.IsEmpty() and not TRNExemploF6SubNivelATipoPedido2.IsNull() and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor02 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor10 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor13 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor14 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor06 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor04 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor03 and
	TRNExemploF6SubNivelATipoPedido2 <> EnumTipoPedidoExemplo.Valor05;
error("Erro: Tipo de Pedido 3 ( " + TRNExemploF6SubNivelATipoPedido3.ToString() + 
	" ) é inválido para Envio de Devolução de Saida.")
	if TRNExemploF6SubNivelA = SubNivelA.ValorB and
	not TRNExemploF6SubNivelATipoPedido3.IsEmpty() and not TRNExemploF6SubNivelATipoPedido3.IsNull() and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor02 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor10 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor13 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor14 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor06 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor04 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor03 and
	TRNExemploF6SubNivelATipoPedido3 <> EnumTipoPedidoExemplo.Valor05;

error("Erro: Pedido de Compra vale apenas para Envio de Entrada ou de Devolução de Compra.") 
	if TRNExemploF6SubNivelATipoPedido = EnumTipoPedidoExemplo.Valor16 and
		TRNExemploF6SubNivelA <> SubNivelA.Valor17 and
		TRNExemploF6SubNivelA <> SubNivelA.Valor18 and
		TRNExemploF6SubNivelA <> SubNivelA.Valor19 and
		TRNExemploF6SubNivelA <> SubNivelA.DevolucaoValor19;

//default(TRNExemploF6SubNivelB, EnumSubNivelBExemplo.SemFiltro);
]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="c44bd5ff-f918-415b-98e6-aca44fed84fa">
    <Source><![CDATA[//Event Start
Event Start
	
	[web]
	{
		
		//if &Mode = TrnMode.Insert
		if &Mode = TrnMode.Insert
			
			TRNExemploF6ResumoExemplo.Visible = false
			
		endif
		
	}
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If not IsAuthorized(&PgmName)
		NotAuthorized(&PgmName)
	Endif
	
	&TrnContext.FromXml(&WebSession.Get(!"TrnContext"))
	
	If &Mode = TrnMode.Delete
		btn_Enter.Caption = "GX_BtnDelete"
		btn_Enter.TooltipText = "GX_BtnDelete"
	EndIf
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

Event After Trn
	/* Generated by Work With Pattern [Start] - Do not change */
	[web]
	{
	If (&Mode = TrnMode.Delete and not &TrnContext.CallerOnDelete)
		WWTRNExemploF6()
	Endif
	
	Return
	}
	/* Generated by Work With Pattern [End] - Do not change */
EndEvent

]]></Source>
    <Properties>
      <Property>
        <Name>IsDefault</Name>
        <Value>False</Value>
      </Property>
    </Properties>
  </Part>
  <Part type="e4c4ade7-53f0-4a56-bdfd-843735b66f47">
    <Variable Name="Context">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>Context</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:Context</Value>
        </Property>
        <Property>
          <Name>ATT_INITIAL_VALUE</Name>
          <Value>LoadContext.udp()</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="IsAuthorized">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>IsAuthorized</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>bas:Boolean</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TRNExemploF6Codigo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TRNExemploF6Codigo</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:TRNExemploF6Codigo</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="TrnContext">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>TrnContext</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>sdt:TransactionContext</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="WebSession">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>WebSession</Value>
        </Property>
        <Property>
          <Name>ATTCUSTOMTYPE</Name>
          <Value>ext:WebSession</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="AgoraExemplo">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>AgoraExemplo</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Agora Exemplo</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:DomainExemploDataHora</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="modificado">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>modificado</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Domain:Logico</Value>
        </Property>
      </Properties>
    </Variable>
    <Variable Name="UsuarioExemploAtualId">
      <Documentation />
      <Properties>
        <Property>
          <Name>Name</Name>
          <Value>UsuarioExemploAtualId</Value>
        </Property>
        <Property>
          <Name>Description</Name>
          <Value>Usuario Id</Value>
        </Property>
        <Property>
          <Name>idBasedOn</Name>
          <Value>Attribute:UsuarioId</Value>
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
    <InnerHtml><![CDATA[]]></InnerHtml>
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
      <Value>TRNExemploF6</Value>
    </Property>
    <Property>
      <Name>Description</Name>
      <Value>Transacao Exemplo Multinivel</Value>
    </Property>
    <Property>
      <Name>idISBUSINESSCOMPONENT</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>MasterPage</Name>
      <Value>MasterPageExemplo</Value>
    </Property>
    <Property>
      <Name>SEARCH_VIEWER</Name>
      <Value>c9584656-94b6-4ccd-890f-332d11fc2c25-ViewTRNExemploF6</Value>
    </Property>
    <Property>
      <Name>Apply:78cecefe-be7d-4980-86ce-8d6e91fba04b</Name>
      <Value>True</Value>
    </Property>
    <Property>
      <Name>IsDefault</Name>
      <Value>False</Value>
    </Property>
  </Properties>
</Object>


```
