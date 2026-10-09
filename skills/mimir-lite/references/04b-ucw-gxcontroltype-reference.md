# 04b - UCW gxControlType: User Control reference in WebPanel

## Document role
Empirical reference (serialized structure and observed behavior)

## Predominant confidence level
mixed — see level per UC

## Depends on
04-webpanel-families-and-templates.md, 02-operational-rules.md

## Used by
04-webpanel-families-and-templates.md

## Purpose
Record observed `UserControl` serialization inside `GxMultiForm` (responsive `WebPanel` layout): numeric `gxControlType`, serialized `PATTERN_ELEMENT_CUSTOM_PROPERTIES`, event-related evidence, and historical file-upload observations by GeneXus object context. Examples and descriptions below explain evidence in exported XML; they are not instructions to create, configure, edit, generate, or package GeneXus objects.

---

## How UCW appears in the XML

In a `WebPanel`'s layout with `GxMultiForm`, each User Control occupies a `<ucw>` element inside the CDATA of `Part type d24a58ad-57ba-41b7-9e6e-eaca3543c778`:

```xml
<ucw gxControlType="NUMERO" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;...&lt;/Properties&gt;" />
```

The `PATTERN_ELEMENT_CUSTOM_PROPERTIES` attribute holds an escaped XML fragment with the UC's list of `<Property>` entries. The number in `gxControlType` identifies the UC's type — it is a fixed negative integer, not a GUID.

---

> **Versioned data and catalog governance:** this document records the meanings evidenced for `scripts/gx-ucw-gxcontroltype-catalog.json`, consumed by `scripts/Get-GeneXusObjectSummary.ps1` to resolve the `gxControlType` of every `<ucw>` in the `webpanel` block. The extractor reports an unrecognized `gxControlType` as unknown (`unknownUcwControlTypes`), never silently drops it. When an independently authorized new UC entry is documented here, add its corresponding entry under its `gxControlType` key to `scripts/gx-ucw-gxcontroltype-catalog.json` at the same time. This lockstep requirement does not authorize autonomous catalog edits; catalog maintenance still requires independent authorization, and this reference does not authorize editing or materializing GeneXus objects.

## gxControlType catalog

### Button — `-2133704903`

- Confidence level: **Direct evidence** (WP0004.xml from this base, SampleKb)
- Observed role: clickable button associated with a named GeneXus event in the inspected serialization
- Alternative form: Button can also appear as `<action controlName= onClickEvent=>` in the layout (same semantics, different serialization). For the single-declaration rule and the disambiguation between a layout button, a pattern's `<actions>` entry (see `01j`), and `.Visible`/`.Icon` references in code, see [02a-runtime-notes-and-known-issues.md](02a-runtime-notes-and-known-issues.md#webpanel-and-pattern-generation-quirks).

Properties in `PATTERN_ELEMENT_CUSTOM_PROPERTIES` (presence in this inspected example; not a required-property contract):

| Property | Evidence note | Serialized value described |
|-------------|-------------|-----------|
| `ControlName` | Present in example | Control name (e.g. `ButtonOpcaoA`) |
| `Enabled` | Present in example | `True` or `False` |
| `Event` | Present in example | Event name in single quotes (e.g. `'AbrirOpcaoA'`) |
| `CaptionExpression` | Present in example | Text shown on the button |
| `Class` | Optional in prior notes; present in example | Applied CSS classes (e.g. `button-tertiary Altura_100px`) |

Complete `ucw` example (properties already escaped for the layout's CDATA):

```xml
<ucw gxControlType="-2133704903" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;ControlName&lt;/Name&gt;&lt;Value&gt;ButtonOpcaoA&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Enabled&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Event&lt;/Name&gt;&lt;Value&gt;'AbrirOpcaoA'&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;CaptionExpression&lt;/Name&gt;&lt;Value&gt;Opcao A&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;Class&lt;/Name&gt;&lt;Value&gt;button-tertiary&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" />
```

---

### FileUpload — `-1987551761`

- Confidence level: **Strong inference — evidence from an inspected external KB** (wpExemploImportacao.xml, SampleKb and SampleKb3, GeneXus 18 U9 Build 187794)
- Observed role: file-upload control in an inspected `WebPanel` with responsive layout (`GxMultiForm`)
- Evidence is from an inspected external KB; the serialized form is not a target-KB configuration prescription. Mimir Lite reads the target KB's official XML and does not materialize objects.

Properties in `PATTERN_ELEMENT_CUSTOM_PROPERTIES` (presence in this inspected example; not a required-property contract):

| Property | Evidence note | Serialized value described |
|-------------|-------------|-----------|
| `ControlName` | Present in example | Control name (e.g. `FileUpload1`) |
| `UploadedFiles` | Present in example | SDT collection variable associated with the files (e.g. `&UploadedFiles`) |
| `AutoUpload` | Optional in prior notes; present in example | `True` for automatic upload on file selection |
| `CustomFileTypes` | Optional in prior notes; present in example | Accepted extensions, comma-separated (e.g. `*.jpg,*.png`) |

Complete `ucw` example:

```xml
<ucw gxControlType="-1987551761" PATTERN_ELEMENT_CUSTOM_PROPERTIES="&lt;Properties&gt;&lt;Property&gt;&lt;Name&gt;ControlName&lt;/Name&gt;&lt;Value&gt;FileUpload1&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;UploadedFiles&lt;/Name&gt;&lt;Value&gt;&amp;amp;UploadedFiles&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;AutoUpload&lt;/Name&gt;&lt;Value&gt;True&lt;/Value&gt;&lt;/Property&gt;&lt;Property&gt;&lt;Name&gt;CustomFileTypes&lt;/Name&gt;&lt;Value&gt;*.jpg,*.png&lt;/Value&gt;&lt;/Property&gt;&lt;/Properties&gt;" />
```

Note on `UploadedFiles`: the value is a reference to a GeneXus variable prefixed with `&`; in the layout's CDATA it appears double-escaped (`&amp;amp;`).

---

### ProgressIndicator — `-1269900845`

- Confidence level: **Strong inference — evidence from an inspected external KB** (SampleKb, GeneXus 18 U9)
- Observed role: visual progress indicator
- Properties: not documented in this base — consult real XML from the target KB

---

### WebNotification — `-1946546103`

- Confidence level: **Strong inference — evidence from an inspected external KB** (SampleKb, GeneXus 18 U9)
- Observed role: on-screen visual notification
- Properties: not documented in this base — consult real XML from the target KB

---

## UC event rule

- **Direct evidence**: the `Event UCName.EventName` syntax in a `WebPanel`'s `Source` is invalid and raises error `src0265: Invalid attribute` in GeneXus 18.
- **Observed behavior / documented limitation**: the inspected GeneXus 18 evidence indicates User Control events are not reachable via `Event UCName.EventName` in the `WebPanel`'s `Source`.
- **Strong inference — evidence from an inspected external KB**: the observed flow used a plain button (event `'SAVE'` or equivalent) to read the `UploadedFiles` collection after upload; the UC trigger was implicit rather than an explicit named event. This is a report of the inspected behavior, not an implementation recommendation.
- **Historical behavior observed in inspected external-KB evidence**: `Event FileUpload1.UploadComplete` (or similar) was not the observed trigger; the inspected flow processed the collection after upload from a plain button event. This records that evidence, not a direction to generate or edit `Source`.

---

## FileUploadData SDT

- Confidence level: **Strong inference — evidence from an inspected external KB** (SampleKb, GeneXus 18 U9 Build 187794)
- This is a strong inference from inspected external-KB XML, not a definitive or prescribed template.

### Member structure observed in the inspected evidence

| Member | Type | Note |
|--------|------|------|
| `FullName` | `bas:Character` | Full file path |
| `Name` | `bas:Character` | File name without path |
| `Extension` | `bas:Character` | File extension |
| `Size` | `bas:Numeric` (Length=10, AttMaxLen=10) | Size in bytes |
| `File` | `bas:Blob` | Binary file content |

### Location observed in the KB

- In the inspected external-KB evidence, the `FileUploadData` SDT was located inside the `FileUploadUserControl` Folder rather than at the KB root. This is a contextual observation, not an instruction to create or move an SDT.
- The same evidence shows the receiving collection variable with `AttCollection=True` (see the serialized property below); it does not authorize changing a target KB.

---

## Observed SDT-collection property

- **Direct evidence** (sanitized examples in this base at `01e-sanitized-templates-core.md` and `04-webpanel-families-and-templates.md`): variable XML in those examples contains `AttCollection=True`. This reports serialized structure and is not an instruction to configure a target object.
- In the cited templates, `Collection=True` and `IsCollection=True` are absent; this reference does not establish an instruction to edit variables. The observed property occurs in variable XML for `WebPanel`, `Procedure`, and `DataProvider`.
- **Historical source record** (operational rule in the original): `Collection=True` and `IsCollection=True` are invalid spellings that GeneXus rejects. This reference set does not verify import rejections (see `00-index.md`, "Current limits of this reference set"); when either spelling appears in a KB's XML, report it as a likely invalid property rather than a confirmed failure.

Serialized form observed in a variable's XML:

```xml
<Property>
  <Name>AttCollection</Name>
  <Value>True</Value>
</Property>
```

---

## File-upload observations by GeneXus object context

| Context | Observed serialized form or behavior | Confidence level |
|----------|-------------------|--------------------|
| `Transaction` form (native Insert/Update) | Automatic — an attribute of type `Image` or `Blob` natively renders a multimedia-upload control | Direct evidence from this base |
| `WebPanel` with Responsive Layout (`GxMultiForm`) | Inspected external-KB XML contains `<ucw gxControlType="-1987551761">` (FileUpload UC) and a `FileUploadData` collection variable with `AttCollection=True` | Strong inference — evidence from an inspected external KB |
| `WebPanel` with Abstract Layout | `<Control Type="FileUpload">` was considered but not successfully tested as a safe path | Hypothesis — no validated evidence |

- **Observed failed experiments**: in a `WebPanel` with `GxMultiForm`, replacing the FileUpload UC with a `Blob` attribute using `controlType="Blob"`, or with `PATTERN_ELEMENT_CUSTOM_PROPERTIES` using `ControlType=Upload`, did not succeed in the cited experiments. This is historical evidence, not a recommendation to try either path.
- Abstract Layout upload remains unvalidated in this evidence set; no safe implementation path is established here.

---

## Technical hypothesis: observed `Rows` candidate for a long `Character` in `GxMultiForm`

- **Measured problem** (SampleAudit workstream, 2026-08-17): a `Character(254)` variable in a `WebPanel` with responsive layout (`GxMultiForm`) renders as a three-line `textarea`; declaring `ControlType = Edit` in the variable's properties did **not** convert it to a single-line input.
- **Technical hypothesis (unvalidated)**: the control equivalent to the `textarea`'s row-height in the `GxMultiForm` layout may be controlled by a layout property (candidate: `Rows=1` on the corresponding control inside the layout's CDATA) rather than a variable property.
- **Evidence limit**: the `Rows` property is only a candidate, not a confirmed standard. The hypothesis has not been validated by checking generated `.cs` and confirming visual rendering; this reference therefore makes no claim that the property is suitable for use or packaging. The maintainers' pending-ideas archive (not published; the `Rows` hypothesis entry) holds the tracking and measurement provenance.
