See also: [Español](2026-10-24-codex-public-samples.es.md)

# Codex CLI: public-sample validation

On 2026-10-24, interactive Codex CLI sessions on Windows completed Mimir Lite's **setup**, **sync**, and **find** workflows with the public Kafka and MyCinema samples. This is observed use of the skill, not just a registration audit. It does not validate every Codex integration, platform, or GeneXus export.

## Scope and method

- Skill checkout: `4141e28dae2bf1edf69ed794acb86cb6f4bc98df`.
- Inputs: `KafkaSampleU12.xpz` (80,148 bytes) and `MyCinema.xpz` (2,920,032 bytes). Copies were checked against the existing trial inputs with SHA-256 before use.
- Each sample used a fresh XPZ-only workspace, a project-local `.agents/skills/mimir-lite` junction, and no previously materialized corpus or index. The skill checkout stayed outside the workspaces.
- Automatic discovery was distinguished from manually reading `SKILL.md`. Setup included an export pre-scan and user confirmation of the KB name before scaffolding. The MyCinema export identifies its source KB as `TestAdvamced`; the public sample name was not substituted for that identity.
- The official scripts materialized XML and rebuilt the derived index. The sessions reported operational audits and `GATE_OK`, then ran the gate again before the bounded **find** queries and selected XML reads.
- A separate observing Codex session read the trial conversations, inspected the persisted materialization/index reports, and checked the XML passages cited below. It did not independently rerun the operational gates.
- Only Mimir Lite was selected. No `mimir-delegate` panel was used, and this was not peer review. No Git repository was initialized in either workspace.

## Observed results

| Check | Kafka | MyCinema |
|---|---|---|
| Automatic skill discovery | Confirmed in the session's injected skill inventory | Reported by the trial session through its project-local link |
| First materialization | 8 objects; 0 attributes | 90 objects and 37 attributes |
| XML files created | 8 | 127 |
| Materialization discrepancies / warnings | 0 / 0 | 0 / 0 |
| Indexed elements / relations | 8 / 25 | 127 / 235 |
| Index inventory semantics | `OK` | `OK` |
| Session-reported operational state | `materialized_and_index_validated` | `materialized_and_index_validated` |
| Fresh gate before **find** | `GATE_OK` reported by the session | `GATE_OK` recorded in tool output |

The index count includes attributes; the MyCinema value of 127 is not a claim that the export has 127 non-attribute objects.

## Functional evidence

**Kafka:** the session identified three Procedures, four ExternalObjects, and one PackagedModule, without inventing Transactions or a business UI. It followed `ProducerTest → PrintResponse` through `what-uses` and `show-evidence`. The observer checked `KbObjectsXml/Procedure/ProducerTest.xml:11–16` (message production, response collection, and call) and `KbObjectsXml/Procedure/PrintResponse.xml:4–7,15` (collection processing and input parameter). Candidates for human authorship were presented as inference, not proven by a not-generated flag.

**MyCinema:** the session listed 9 Transactions, 5 Procedures, and 2 WebPanels without a generation filter. It explained the `Movie` Transaction and followed `CheckMovieActors → IsStarring` through the index. The observer checked the call at `KbObjectsXml/Procedure/CheckMovieActors.xml:4–11` and the callee's matching logic at `KbObjectsXml/Procedure/IsStarring.xml:4–17`.

For `MovieYear`, the session used `attribute-info` before reading XML and did not invent a type or length absent from the export. The observer checked `KbObjectsXml/Attribute/MovieYear.xml:15`, its structural use at `KbObjectsXml/Transaction/Movie.xml:8`, and the assignment at `KbObjectsXml/DataProvider/Movie_DataProvider.xml:8`. The answer disclosed incomplete `attribute_references` coverage: the two returned consumers are not necessarily all consumers, and a DataProvider assignment does not by itself prove a database write.

The XML paths above are evidence locators inside the generated workspaces, not repository files. Local conversations, reports, and exports are not published by this record; the record summarizes what was inspected without linking to private working notes.

## Environment issues and limits

- Initial sandbox bootstrap failed while updating filesystem permissions in a workspace created by the sandbox account. The successful trials used new workspaces created from the maintainer's terminal. No sandbox disabling or manual permission changes were used as a workaround.
- PowerShell 7.6.8 from Microsoft Store worked in the maintainer's terminal but initially failed to execute from the sandbox. An official MSI installation was recommended; subsequent workflow commands succeeded. The observing session did not establish the exact executable selected on those successful commands, so this is not proof that MSI installation universally resolves the problem.
- Kafka's materialization report records extraction under the user's system temporary directory, outside its workspace. Strict workspace-only temporary writes were **not** validated for that run.
- Before MyCinema execution, `TEMP`, `TMP`, and `TMPDIR` were set to `workspace/Temp`. Its report records extraction there; the extracted directory was removed afterward. This confirms that extraction location and cleanup, not host-wide filesystem isolation.
- No GeneXus business objects, Kafka services, builds, imports, or object generation were executed. No additional `FullSnapshot` verification was run.
- These positive public-sample runs do not establish exhaustive extractor coverage, failure-case handling, a fresh end-to-end test of the Codex IDE extension or app, or live support on Linux/macOS.

## Conclusion

The two cases provide empirical Windows Codex CLI evidence for automatic skill discovery and the setup → sync → gate → indexed query → selected XML reading flow. Keep the environment conditions and coverage limits with that conclusion; registration alone, or a passing gate alone, would not establish the same result.
