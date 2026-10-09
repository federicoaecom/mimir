# 01d - Structural Diffs by Type

## Document role
Comparative empirical

## Purpose
Concentrate simple-vs-dense comparisons by type and support reading of the structural difference between close profiles.

## Incorporated origin - pre-repository "Structural Diffs by Type" document

## Document role
Empirical

## Predominant confidence level
Medium

## Depends on
`09-script-inventory.md`, `01b-part-type-matrix-by-type.md`, `01c-stable-vs-variable-fields.md`

## Used by
`02-operational-rules.md`, `03-risk-and-decision-by-type.md`

## Purpose
Compare simple and complex samples for priority types.
Highlight observed structural differences and uncertainty in read-side comparisons; these observations do not assess editing or cloning risk.

- Direct evidence: simple/complex samples were chosen by the smallest/largest combination of PartCount and file size.
- Strong inference: "simple" and "complex" here mean structural complexity in the extracted XML, not guaranteed functional complexity.

## API

- Direct evidence: real case observed: sanitized alias `APIExemploIntegracaoA.xml` with 5 `Part` and a size of 25844 bytes.
- Direct evidence: the sanitized alias `APIExemploMinA.xml` should be read only as a simplified editorial cut of the same structural profile, not as a second real `API` observed in the KB.
- Direct evidence: Part type in the simple samples: 9f577ec2-27f4-4cf4-8ad5-f3f50c9d69b5; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c44bd5ff-f918-415b-98e6-aca44fed84fa; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type in the complex samples: 9f577ec2-27f4-4cf4-8ad5-f3f50c9d69b5; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c44bd5ff-f918-415b-98e6-aca44fed84fa; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## DataProvider

- Direct evidence: simple sample: sanitized alias `DPExemploLista.xml` with 5 `Part` and 3 non-empty `Part`(s).
- Direct evidence: simple sample: sanitized alias `DPExemploParm.xml` with 5 `Part` and 4 non-empty `Part`(s).
- Direct evidence: complex sample: sanitized alias `DPExemploTribSelecaoA.xml` with 5 `Part` and a size of 12558 bytes.
- Direct evidence: complex sample: sanitized alias `DPExemploSidebarA.xml` with 5 `Part` and a size of 10713 bytes.
- Direct evidence: Part type in the simple samples: 1d8aeb5a-6e98-45a7-92d2-d8de7384e432; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type in the complex samples: 1d8aeb5a-6e98-45a7-92d2-d8de7384e432; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## DesignSystem

- Direct evidence: simple sample: sanitized alias in DesignSystem\SANITIZED-EXAMPLE.xml with 4 Part and 3 non-empty Part(s).
- Direct evidence: simple sample: sanitized alias in DesignSystem\SANITIZED-EXAMPLE.xml with 4 Part and 4 non-empty Part(s).
- Direct evidence: complex sample: sanitized alias in DesignSystem\SANITIZED-EXAMPLE.xml with 4 Part and a size of 31240 bytes.
- Direct evidence: complex sample: sanitized alias in DesignSystem\SANITIZED-EXAMPLE.xml with 4 Part and a size of 2255 bytes.
- Direct evidence: Part type in the simple samples: 36982745-cb77-47a3-bc04-9d0d764ff532; 75e52d99-6edd-4bad-a1d7-dcc9b7f000ef; babf62c5-0111-49e9-a1c3-cc004d90900a; c6b14574-4f5f-4e35-aaa7-e322e88a9a10.
- Direct evidence: Part type in the complex samples: 36982745-cb77-47a3-bc04-9d0d764ff532; 75e52d99-6edd-4bad-a1d7-dcc9b7f000ef; babf62c5-0111-49e9-a1c3-cc004d90900a; c6b14574-4f5f-4e35-aaa7-e322e88a9a10.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## PackagedModule

- Direct evidence: simple sample: sanitized alias `PackagedModuleExemploExtensoesA.xml` with 2 `Part` and 2 non-empty `Part`(s).
- Direct evidence: simple sample: sanitized alias `PackagedModuleExemploSegurancaA.xml` with 2 `Part` and 2 non-empty `Part`(s).
- Direct evidence: complex sample: sanitized alias `PackagedModuleExemploUIA.xml` with 3 `Part` and a size of 998 bytes.
- Direct evidence: complex sample: sanitized alias `PackagedModuleExemploServicesA.xml` with 3 `Part` and a size of 990 bytes.
- Direct evidence: Part type in the simple samples: babf62c5-0111-49e9-a1c3-cc004d90900a; ed1b7b1c-2aaf-46eb-9ec5-db348f6fa3fc.
- Direct evidence: Part type in the complex samples: a5e6a251-2df0-44d8-adab-1da237574326; babf62c5-0111-49e9-a1c3-cc004d90900a; ed1b7b1c-2aaf-46eb-9ec5-db348f6fa3fc.
- Direct evidence: Part type only in the complex samples: a5e6a251-2df0-44d8-adab-1da237574326.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## Panel

- Direct evidence: simple sample: sanitized alias `PanelExemploNaoAutorizadoA.xml` with 2 `Part` and 1 non-empty `Part`(s).
- Direct evidence: simple sample: sanitized alias `PanelExemploLoginA.xml` with 2 `Part` and 1 non-empty `Part`(s).
- Direct evidence: complex sample: sanitized alias `PanelExemploTrocaSenhaA.xml` with 2 `Part` and a size of 16930 bytes.
- Direct evidence: complex sample: sanitized alias `PanelExemploAtualizacaoUsuarioA.xml` with 2 `Part` and a size of 15516 bytes.
- Direct evidence: Part type in the simple samples: b4378a97-f9b2-4e05-b2f8-c610de258402; babf62c5-0111-49e9-a1c3-cc004d90900a.
- Direct evidence: Part type in the complex samples: b4378a97-f9b2-4e05-b2f8-c610de258402; babf62c5-0111-49e9-a1c3-cc004d90900a.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## Procedure

- Direct evidence: simple sample: sanitized alias `PRCExemploMinimo.xml` with 7 `Part` and 1 non-empty `Part`(s).
- Direct evidence: simple sample: sanitized alias `PRCExemploParm.xml` with 7 `Part` and 3 non-empty `Part`(s).
- Direct evidence: complex sample: sanitized alias `PRCExemploRelatorioA.xml` with 7 `Part` and a size of 1114792 bytes.
- Direct evidence: complex sample: sanitized alias `PRCExemploRelatorioB.xml` with 7 `Part` and a size of 1060772 bytes.
- Direct evidence: Part type in the simple samples: 528d1c06-a9c2-420d-bd35-21dca83f12ff; 763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c414ed00-8cc4-4f44-8820-4baf93547173; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type in the complex samples: 528d1c06-a9c2-420d-bd35-21dca83f12ff; 763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c414ed00-8cc4-4f44-8820-4baf93547173; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## SDT

- Direct evidence: simple sample: sanitized alias `SDTExemploEstadoTelaA.xml` with 2 `Part` and 1 non-empty `Part`(s).
- Direct evidence: simple sample: sanitized alias `SDTExemploEstoqueA.xml` with 2 `Part` and 1 non-empty `Part`(s).
- Direct evidence: complex sample: sanitized alias `SDTExemploDocumentoA.xml` with 2 `Part` and a size of 1101872 bytes.
- Direct evidence: complex sample: sanitized alias `SDTExemploDocumentoB.xml` with 2 `Part` and a size of 1054406 bytes.
- Direct evidence: Part type in the simple samples: 5c2aa9da-8fc4-4b6b-ae02-8db4fa48976a; babf62c5-0111-49e9-a1c3-cc004d90900a.
- Direct evidence: Part type in the complex samples: 5c2aa9da-8fc4-4b6b-ae02-8db4fa48976a; babf62c5-0111-49e9-a1c3-cc004d90900a.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## Theme

- Direct evidence: simple sample: sanitized alias `ThemeExemploMobileB.xml` with 3 `Part` and 2 non-empty `Part`(s).
- Direct evidence: simple sample: sanitized alias `ThemeExemploMobileC.xml` with 3 `Part` and 2 non-empty `Part`(s).
- Direct evidence: complex sample: sanitized alias `ThemeExemploPrincipalA.xml` with 3 `Part` and a size of 323724 bytes.
- Direct evidence: complex sample: sanitized alias `ThemeExemploSegurancaA.xml` with 3 `Part` and a size of 304258 bytes.
- Direct evidence: Part type in the simple samples: 43b86e51-163f-44af-ac5a-e101541b1a71; babf62c5-0111-49e9-a1c3-cc004d90900a; c31007a6-01d3-4788-95b3-425921d47758.
- Direct evidence: Part type in the complex samples: 43b86e51-163f-44af-ac5a-e101541b1a71; babf62c5-0111-49e9-a1c3-cc004d90900a; c31007a6-01d3-4788-95b3-425921d47758.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## Transaction

- Direct evidence: simple sample: sanitized alias in Transaction\SANITIZED-EXAMPLE.xml with 8 Part and 7 non-empty Part(s).
- Direct evidence: simple sample: sanitized alias in Transaction\SANITIZED-EXAMPLE.xml with 8 Part and 7 non-empty Part(s).
- Direct evidence: complex sample: sanitized alias in Transaction\SANITIZED-EXAMPLE.xml with 8 Part and a size of 521796 bytes.
- Direct evidence: complex sample: sanitized alias in Transaction\SANITIZED-EXAMPLE.xml with 8 Part and a size of 294785 bytes.
- Direct evidence: Part type in the simple samples: 264be5fb-1b28-4b25-a598-6ca900dd059f; 4c28dfb9-f83b-46f0-9cf3-f7e090b525d5; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c44bd5ff-f918-415b-98e6-aca44fed84fa; d24a58ad-57ba-41b7-9e6e-eaca3543c778; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type in the complex samples: 264be5fb-1b28-4b25-a598-6ca900dd059f; 4c28dfb9-f83b-46f0-9cf3-f7e090b525d5; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c44bd5ff-f918-415b-98e6-aca44fed84fa; d24a58ad-57ba-41b7-9e6e-eaca3543c778; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## WebPanel

- Direct evidence: simple sample: sanitized alias in WebPanel\SANITIZED-EXAMPLE.xml with 7 Part and 2 non-empty Part(s).
- Direct evidence: simple sample: sanitized alias in WebPanel\SANITIZED-EXAMPLE.xml with 7 Part and 2 non-empty Part(s).
- Direct evidence: complex sample: sanitized alias in WebPanel\SANITIZED-EXAMPLE.xml with 7 Part and a size of 530462 bytes.
- Direct evidence: complex sample: sanitized alias in WebPanel\SANITIZED-EXAMPLE.xml with 7 Part and a size of 403121 bytes.
- Direct evidence: Part type in the simple samples: 763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c44bd5ff-f918-415b-98e6-aca44fed84fa; d24a58ad-57ba-41b7-9e6e-eaca3543c778; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type in the complex samples: 763f0d8b-d8ac-4db4-8dd4-de8979f2b5b9; 9b0a32a3-de6d-4be1-a4dd-1b85d3741534; ad3ca970-19d0-44e1-a7b7-db05556e820c; babf62c5-0111-49e9-a1c3-cc004d90900a; c44bd5ff-f918-415b-98e6-aca44fed84fa; d24a58ad-57ba-41b7-9e6e-eaca3543c778; e4c4ade7-53f0-4a56-bdfd-843735b66f47.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.

## WorkWithForWeb

- Direct evidence: simple sample: sanitized alias in WorkWithForWeb\SANITIZED-EXAMPLE.xml with 2 Part and 1 non-empty Part(s).
- Direct evidence: simple sample: sanitized alias in WorkWithForWeb\SANITIZED-EXAMPLE.xml with 2 Part and 1 non-empty Part(s).
- Direct evidence: complex sample: sanitized alias in WorkWithForWeb\SANITIZED-EXAMPLE.xml with 2 Part and a size of 188770 bytes.
- Direct evidence: complex sample: sanitized alias in WorkWithForWeb\SANITIZED-EXAMPLE.xml with 2 Part and a size of 151944 bytes.
- Direct evidence: Part type in the simple samples: a51ced48-7bee-0001-ab12-04e9e32123d1; babf62c5-0111-49e9-a1c3-cc004d90900a.
- Direct evidence: Part type in the complex samples: a51ced48-7bee-0001-ab12-04e9e32123d1; babf62c5-0111-49e9-a1c3-cc004d90900a.
- Direct evidence: Part type only in the complex samples: none.
- Direct evidence: Part type only in the simple samples: none.
- Read-side comparison: recurring and sample-exclusive Part types describe the observed structural overlap; recurrence alone does not establish stability, editability, or lower risk.
