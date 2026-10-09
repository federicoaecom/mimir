# Ideas descartadas y exclusiones

Esta página registra ideas que no deben confundirse con trabajo de Mimir Lite, con el motivo para no reintroducir cada una. Reabrir cualquiera de ellas requiere una decisión explícita y evidencia nueva.

## Exclusiones de producto

Son decisiones de alcance (ver [ADR 0001](../adr/0001-read-only-scope-and-non-goals.md)), no preguntas de diseño abiertas.

| Exclusión | Decisión y motivo |
|---|---|
| Generar, clonar o empaquetar objetos GeneXus | Fuera del propósito de lectura del producto; una herramienta de lectura, indexación y documentación no se convierte en productora de objetos o paquetes. Ver [README — Fuera de alcance](../../README.es.md#fuera-de-alcance). |
| Compilar o importar XPZ en una KB; compilación, especificación o generación mediante MSBuild | No forma parte de Mimir Lite. El producto lee exports XPZ/XML; no aplica paquetes ni opera el flujo de compilación GeneXus. |
| Procesamiento desatendido | El trabajo lo solicita una persona; no hay daemon ni procesamiento en segundo plano de una KB. |

## Fuera de alcance

Los siguientes enfoques quedan comprendidos en las exclusiones anteriores y no se registran por separado:

- **Automatización de pre-push para una KB.** La salida procesada de una KB es trabajo local; Mimir Lite no la envía.
- **Hooks o daemons de aprobación de comandos para herramientas de agente** (por ejemplo un hook `PreToolUse` de Claude Code), tanto si deniegan como si aprueban automáticamente los comandos. Un hook que bloquea no reduce los avisos de autorización, puede rechazar comandos válidos configurados por el usuario y depende de la máquina local. La alternativa abierta es el ítem «Facilidad de permisos para agentes» del backlog.
- **Utilidades de compilación y empaquetado:** copias de seguridad con `BulkCopyKnowledgeBase` (restaurar su salida BCP requiere GeneXus Server; copiar la carpeta de la KB o respaldar SQL es más sencillo), un wrapper MSBuild para `UpdateWorkingModel` (la IDE ya ofrece la operación), exigir `SpecifyGenerate` antes de cada `BuildAll` (`SpecifyAll` puede activar una reorganización no deseada de la base de datos) y un único ejecutor para todas las verificaciones de empaquetado.

## Descartes de lectura

Se conservan únicamente como motivo para no reintroducir un enfoque específico. No prohíben trabajo de lectura distinto que cuente con evidencia nueva.

| Enfoque descartado | Motivo del rechazo |
|---|---|
| Verificador genérico de pérdida de acentos en payloads de objetos de KB | Requiere vocabulario específico de cada KB y generaría falsos positivos; es distinto de verificar la documentación de este repositorio. |
| Consulta dedicada de invocadores («¿quién llama a X?», «¿qué call sites siguen usando el objeto anterior?») | Ya la cubre la consulta existente `who-uses` (junto con `what-uses`, `impact-basic` y `functional-trace-basic`); los invocadores de un objeto anterior son `who-uses` sobre su nombre. Comparar invocadores entre snapshots de la KB a lo largo del tiempo no está cubierto y requeriría un índice versionado; solo se reabre ante un caso concreto que lo necesite. |
| Consulta de migración (Origen → Destino) | Los datos devueltos son exactamente `who-uses Source`; el par solo rotula la intención del usuario. El ángulo estructural sigue vigente como el ítem «Huellas de ubicación de referencias» del backlog. No se reabre en su forma original. |
| Consulta por familia funcional («objetos de composición de e-mail», «bridges de envío») como capacidad propia | Misma clase de pregunta e infraestructura que el ítem «Descubrimiento semántico» del backlog (intención en lenguaje natural sobre el corpus XML), con el mismo límite: no reemplaza la lectura del XML. Entra en el alcance de ese ítem si alguna vez se implementa. |

## Límite

La [lista de ideas pendientes](backlog.es.md) presenta por separado las ideas abiertas de lectura y proceso. Nada en esta página es trabajo pendiente, y una entrada del backlog no prevalece sobre las exclusiones anteriores.
