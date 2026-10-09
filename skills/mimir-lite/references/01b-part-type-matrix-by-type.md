# 01b - Part Type Matrix by Type

## Document role
Structural empirical

## Purpose
Concentrate the observed `Part type` frequency by extracted type and support reading of apparent structural mandatoriness.

## Incorporated origin - pre-repository "Part Type Matrix" document

## Document role
Empirical

## Predominant confidence level
Medium

## Depends on
`09-script-inventory.md`, `01-empirical-base-overview.md`

## Used by
`02-operational-rules.md`, `03-risk-and-decision-by-type.md`

## Purpose
Catalog the `Part type`s observed per object type, with frequency and examples.
Separate direct observation from preliminary heuristic reading.

- Direct evidence: frequencies computed from the XMLs extracted in `C:\SANITIZED\KbObjectsXml`.
- Strong inference: the preliminary classification below uses presence and recurring emptiness as a corpus heuristic, not an import test.

## API

- Direct evidence: `Object/@type` = `36e32e2d-023e-4188-95df-d13573bac2e0` in 1 object.
- Direct evidence: average Part count per object: 5.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 9f577ec2-27f4-4cf4-8ad5-f3f50c9d69b5 | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 1 | 100 | 100 | apparently mandatory (very small sample) | sanitized examples |
| c44bd5ff-f918-415b-98e6-aca44fed84fa | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| e4c4ade7-53f0-4a56-bdfd-843735b66f47 | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |

## Attribute

- Direct evidence: own envelope — root `<Attributes><Attribute>`; no `Object/@type`.
- Direct evidence: 7685 objects read in the SampleKb corpus (`Attribute/`).
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 7685 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 7685 | 100 | 0 | apparently mandatory | sanitized examples |

## ColorPalette

- Direct evidence: `Object/@type` = `3affc0b3-494b-4d84-9ec1-3a6ab8349cda` in 1 object.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 5d481862-64bc-4e88-8af2-e21c276dab77 | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 1 | 100 | 100 | apparently mandatory (very small sample) | sanitized examples |

## Dashboard

- Direct evidence: `Object/@type` = `526aba9f-a725-4bc7-b1db-0b9f92ac9550` in 1 object.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| a51ced48-7bee-0001-ab12-04e9e32123d1 | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 1 | 100 | 100 | apparently mandatory (very small sample) | sanitized examples |

## DataProvider

- Direct evidence: `Object/@type` = `2a9e9aba-d2de-4801-ae7f-5e3819222daf` in 24 objects.
- Direct evidence: average Part count per object: 5.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 1d8aeb5a-6e98-45a7-92d2-d8de7384e432 | 24 | 100 | 0 | apparently mandatory | sanitized examples |
| 9b0a32a3-de6d-4be1-a4dd-1b85d3741534 | 24 | 100 | 8.3 | apparently mandatory | sanitized examples |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 24 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 24 | 100 | 100 | apparently mandatory | sanitized examples |
| e4c4ade7-53f0-4a56-bdfd-843735b66f47 | 24 | 100 | 4.2 | apparently mandatory | sanitized examples |

## DataView

- Direct evidence: `Object/@type` = `19abc6ff-2cd2-0000-0006-6d172bc2333b` in 1 object (KB `SampleKb18`, GX 18 U13, `SampleAudit` workstream; sanitized template `dvExemploMultiDbms` in `01e`).
- Direct evidence: average Part count per object: 3.
- Direct evidence: the indexes Part (`7706bd3b-212a-1000-0006-8aaeb59068b9`) carries a nested index `Object` (`fc1b76c4-95c5-0000-0101-44f9543121bd`) with its own members Part (`fe47b55c-ea2a-1000-0101-5b38901e24f7`); object-level properties: `Name`, `DVAssocTable` (attributes as `<Attribute-type-GUID>-<Name>`, `;`, primary-key order), `DVDataStore`, `IsDefault`.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 19abc6ff-2cd2-1000-0006-6d172bc2333b | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| 7706bd3b-212a-1000-0006-8aaeb59068b9 | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 1 | 100 | 100 | apparently mandatory (very small sample) | sanitized examples |

## DataSelector

- Direct evidence: `Object/@type` = `ffd44be7-3bb4-4d01-9e7e-d1c1a3c095af` in 2 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| a2bc65a1-999f-4e9b-b837-72285cc9bb16 | 2 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 2 | 100 | 50 | apparently mandatory (very small sample) | sanitized examples |

## DataStore

- Direct evidence: `Object/@type` = `dcdcdcdc-dfe0-4a57-ae8f-c6e31b0dcbc0` in 2 objects.
- Direct evidence: none contains a `<Part type="...">`.
- Conclusion: this type uses no Parts; the Part-type matrix does not apply.

## DeploymentUnit

- Direct evidence: `Object/@type` = `bf08dfb1-361c-4e7e-ad54-391e56e60b49` in 1 object.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 122ea32d-7ffa-4c47-9cbf-0829c2f060fe | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 1 | 100 | 100 | apparently mandatory (very small sample) | sanitized examples |

## DesignSystem

- Direct evidence: `Object/@type` = `78b3fa0e-174c-4b2b-8716-718167a428b5` in 2 objects.
- Direct evidence: average Part count per object: 4.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 36982745-cb77-47a3-bc04-9d0d764ff532 | 2 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| 75e52d99-6edd-4bad-a1d7-dcc9b7f000ef | 2 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 2 | 100 | 50 | apparently mandatory (very small sample) | sanitized examples |
| c6b14574-4f5f-4e35-aaa7-e322e88a9a10 | 2 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |

## Document

- Direct evidence: `Object/@type` = `faeb588c-dcce-4dad-9af3-cdd11b961a32` in 3 objects.
- Direct evidence: average Part count per object: 1.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 3 | 100 | 0 | apparently mandatory | sanitized examples |

## Domain

- Direct evidence: `Object/@type` = `00972a17-9975-449e-aab1-d26165d51393` in 593 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 593 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 593 | 100 | 100 | apparently mandatory | sanitized examples |

## ExternalObject

- Direct evidence: `Object/@type` = `c163e562-42c6-4158-ad83-5b21a14cf30e` in 18 objects.
- Direct evidence: average Part count per object: 3.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 00000000-0000-0000-0002-000000000005 | 18 | 100 | 5.6 | apparently mandatory | sanitized examples |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 18 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 18 | 100 | 77.8 | apparently mandatory | sanitized examples |

## File

- Direct evidence: `Object/@type` = `1132ac08-290f-4fd1-bd18-64777b7329d1` in 81 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 9b6155f9-f286-4ed5-bd15-67672e8ea320 | 81 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 81 | 100 | 100 | apparently mandatory | sanitized examples |

## Module

Note: the upstream pt-BR original had this heading and the next one swapped (labeled "Folder" for GUID `...0006` and "Module/Folder" for GUID `...0008`); the catalog (`scripts/gx-object-type-catalog.json`) identifies `...0006` as `Module` and `...0008` as `Folder` — fixed here, content unchanged.

- Direct evidence: `Object/@type` = `00000000-0000-0000-0000-000000000006` in 7 objects.
- Direct evidence: average Part count per object: 1.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 7 | 100 | 100 | apparently mandatory | sanitized examples |

## Folder

- Direct evidence: `Object/@type` = `00000000-0000-0000-0000-000000000008` — container created by the user; the IDE shows it as "Module/Folder" in the Properties panel.
- Direct evidence: 279 objects read in the SampleKb corpus (`Folder/`); none contains a `<Part type="...">`.
- Direct evidence: properties sit directly under `<Properties>` inside `<Object>`, with no Part wrapper.
- Conclusion: this type uses no Parts; the Part-type matrix does not apply.

## Generator

- Direct evidence: `Object/@type` = `ecececec-dfe0-4a57-ae8f-c6e31b0dcbc0` in 5 objects.
- Direct evidence: none contains a `<Part type="...">`.
- Conclusion: this type uses no Parts; the Part-type matrix does not apply.

## Image

- Direct evidence: `Object/@type` = `9fb193d9-64a4-4d30-b129-ff7c76830f7e` in 250 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 36f350de-f768-425f-ac20-773749f331bf | 250 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 250 | 100 | 79.2 | apparently mandatory | sanitized examples |

## Table

- Direct evidence: `Object/@type` = `857ca50e-7905-0000-0007-c5d9ff2975ec` in 228 top-level `Table` objects.
- Direct evidence: average Part count per object: 2.
- Direct evidence: in these objects, `Index` appears embedded in the `Table`'s structural block, not as a separate top-level object.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 00000000-0000-0000-0002-000000000004 | 228 | 100 | 0 | apparently mandatory | sanitized examples |
| a5c0e770-560d-0001-0001-7fe71c260de3 | 228 | 100 | 0 | apparently mandatory | sanitized examples |

## Language

- Direct evidence: `Object/@type` = `88313f43-5eb2-0000-0028-e8d9f5bf9588` in 1 object.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |
| c23f3bb5-1e43-4c6b-b219-4717979df76a | 1 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |

## PackagedModule

- Direct evidence: `Object/@type` = `c88fffcd-b6f8-0000-8fec-00b5497e2117` in 16 objects.
- Direct evidence: average Part count per object: 2.38.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| a5e6a251-2df0-44d8-adab-1da237574326 | 6 | 37.5 | 100 | apparently empty/structural | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 16 | 100 | 37.5 | apparently mandatory | sanitized examples |
| ed1b7b1c-2aaf-46eb-9ec5-db348f6fa3fc | 16 | 100 | 37.5 | apparently mandatory | sanitized examples |

## Panel

- Direct evidence: `Object/@type` = `d82625fd-5892-40b0-99c9-5c8559c197fc` in 7 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| b4378a97-f9b2-4e05-b2f8-c610de258402 | 7 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 7 | 100 | 100 | apparently mandatory | sanitized examples |

## PatternSettings

- Direct evidence: `Object/@type` = `83476c1e-fa72-4229-9930-f51b954fca2d` in 2 objects.
- Direct evidence: average Part count per object: 1.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.
- Hypothesis: since this type's sample has fewer than 3 objects, the mandatory/optional reading should be treated with extra caution.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 3c89746e-54b1-441a-8f3f-97cc81be06bd | 2 | 100 | 0 | apparently mandatory (very small sample) | sanitized examples |

## Procedure

- Direct evidence: `Object/@type` = `84a12160-f59b-4ad7-a683-ea4481ac23e9` in 2281 objects.
- Direct evidence: average Part count per object: 7.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 528d1c06-a9c2-420d-bd35-21dca83f12ff | 2281 | 100 | 0.4 | apparently mandatory | sanitized examples |
| 763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9 | 2281 | 100 | 52.5 | apparently mandatory | sanitized examples |
| 9b0a32a3-de6d-4be1-a4dd-1b85d3741534 | 2281 | 100 | 0.1 | apparently mandatory | sanitized examples |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 2281 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 2281 | 100 | 93 | apparently mandatory | sanitized examples |
| c414ed00-8cc4-4f44-8820-4baf93547173 | 2281 | 100 | 95.7 | apparently mandatory | sanitized examples |
| e4c4ade7-53f0-4a56-bdfd-843735b66f47 | 2281 | 100 | 0.1 | apparently mandatory | sanitized examples |

## SDT

- Direct evidence: `Object/@type` = `447527b5-9210-4523-898b-5dccb17be60a` in 594 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 5c2aa9da-8fc4-4b6b-ae02-8db4fa48976a | 594 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 594 | 100 | 98.3 | apparently mandatory | sanitized examples |

## Stencil

- Direct evidence: `Object/@type` = `624a8b31-36f0-4292-adba-2d270d1e3537` in 11 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 3dd92fe7-b095-44d3-9fa0-8488fa3f0c68 | 11 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 11 | 100 | 100 | apparently mandatory | sanitized examples |

## SubTypeGroup

- Direct evidence: `Object/@type` = `87313f43-5eb2-41d7-9b8c-e8d9f5bf9588` in 709 objects.
- Direct evidence: average Part count per object: 1.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 74203da2-41b1-402c-0001-d8d564a2c2fa | 709 | 100 | 0 | apparently mandatory | sanitized examples |

## Theme

- Direct evidence: `Object/@type` = `c804fdbd-7c0b-440d-8527-4316c92649a6` in 7 objects.
- Direct evidence: average Part count per object: 3.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 43b86e51-163f-44af-ac5a-e101541b1a71 | 7 | 100 | 14.3 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 7 | 100 | 71.4 | apparently mandatory | sanitized examples |
| c31007a6-01d3-4788-95b3-425921d47758 | 7 | 100 | 0 | apparently mandatory | sanitized examples |

## ThemeClass

- Direct evidence: `Object/@type` = `d4876646-98dd-419b-8c1c-896f83c48368` in 501 objects.
- Direct evidence: none contains a `<Part type="...">`.
- Conclusion: this type uses no Parts; the Part-type matrix does not apply.

## ThemeColor

- Direct evidence: `Object/@type` = `5592de59-d30a-499d-9100-a7006d3674f2` in 24 objects.
- Direct evidence: none contains a `<Part type="...">`.
- Conclusion: this type uses no Parts; the Part-type matrix does not apply.

## Transaction

- Direct evidence: `Object/@type` = `1db606f2-af09-4cf9-a3b5-b481519d28f6` in 183 objects.
- Direct evidence: average Part count per object: 8.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 264be5fb-1b28-4b25-a598-6ca900dd059f | 183 | 100 | 0 | apparently mandatory | sanitized examples |
| 4c28dfb9-f83b-46f0-9cf3-f7e090b525d5 | 183 | 100 | 0 | apparently mandatory | sanitized examples |
| 9b0a32a3-de6d-4be1-a4dd-1b85d3741534 | 183 | 100 | 0 | apparently mandatory | sanitized examples |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 183 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 183 | 100 | 56.8 | apparently mandatory | sanitized examples |
| c44bd5ff-f918-415b-98e6-aca44fed84fa | 183 | 100 | 0 | apparently mandatory | sanitized examples |
| d24a58ad-57ba-41b7-9e6e-eaca3543c778 | 183 | 100 | 0 | apparently mandatory | sanitized examples |
| e4c4ade7-53f0-4a56-bdfd-843735b66f47 | 183 | 100 | 0 | apparently mandatory | sanitized examples |

## UserControl

- Direct evidence: `Object/@type` = `562f4793-aabe-449f-8821-fc77e550698e` in 7 objects.
- Direct evidence: average Part count per object: 3.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 3dd92fe7-b095-44d3-9fa0-8488fa3f0c67 | 7 | 100 | 0 | apparently mandatory | sanitized examples |
| 8e9e4a7c-a4d3-4c36-8e8e-fb6702402f63 | 7 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 7 | 100 | 85.7 | apparently mandatory | sanitized examples |

## WebPanel

- Direct evidence: `Object/@type` = `c9584656-94b6-4ccd-890f-332d11fc2c25` in 1196 objects.
- Direct evidence: average Part count per object: 7.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| 763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9 | 1196 | 100 | 13.1 | apparently mandatory | sanitized examples |
| 9b0a32a3-de6d-4be1-a4dd-1b85d3741534 | 1196 | 100 | 0.8 | apparently mandatory | sanitized examples |
| ad3ca970-19d0-44e1-a7b7-db05556e820c | 1196 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 1196 | 100 | 95.7 | apparently mandatory | sanitized examples |
| c44bd5ff-f918-415b-98e6-aca44fed84fa | 1196 | 100 | 0.2 | apparently mandatory | sanitized examples |
| d24a58ad-57ba-41b7-9e6e-eaca3543c778 | 1196 | 100 | 0 | apparently mandatory | sanitized examples |
| e4c4ade7-53f0-4a56-bdfd-843735b66f47 | 1196 | 100 | 0.4 | apparently mandatory | sanitized examples |

## WorkWithForWeb

- Direct evidence: `Object/@type` = `78cecefe-be7d-4980-86ce-8d6e91fba04b` in 183 objects.
- Direct evidence: average Part count per object: 2.
- Strong inference: the apparently-mandatory/optional/rare/empty classifications depend on the recurrence observed in this KB.

| PartType | ObjectsWithPart | PresencePct | EmptyPct | PreliminaryClass | Sanitized examples |
| --- | --- | --- | --- | --- | --- |
| a51ced48-7bee-0001-ab12-04e9e32123d1 | 183 | 100 | 0 | apparently mandatory | sanitized examples |
| babf62c5-0111-49e9-a1c3-cc004d90900a | 183 | 100 | 100 | apparently mandatory | sanitized examples |
