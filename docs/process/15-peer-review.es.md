# 15 — Revisión por pares (validación de plan/diseño mediante panel multimodelo)

> **Flujo de mantenedores.** Este documento describe el flujo de revisión de quienes mantienen este repositorio. Es opcional para quienes contribuyen: las únicas verificaciones que debe pasar una contribución son las verificaciones mecánicas que ejecuta la CI, listadas en [`CONTRIBUTING.es.md`](../../CONTRIBUTING.es.md).

## Función de este documento

Esta es la metodología genérica de revisión por pares del repositorio. Un autor presenta su lectura de un problema y una solución propuesta a un panel de revisores independientes, de creadores de modelos distintos. Cada revisor piensa por su cuenta, verifica las fuentes citadas y devuelve un dictamen. Luego el autor revisa y vuelve a someter el manuscrito hasta llegar al estado de cierre definido aquí.

Tres documentos, tres capas:

- [`13-pre-push-review.md`](13-pre-push-review.md): la rutina pre-push que ejecuta cada revisor antes de un push.
- [`14-reinforced-pre-push-review.md`](14-reinforced-pre-push-review.md): la aplicación reforzada de esta metodología al caso pre-push; el panel revisa la rutina del `13` y hereda esta regla de convergencia.
- este `15`: la metodología general para validar un plan o diseño antes o durante la implementación, no solo antes de push.

El mecanismo de delegación — backends de revisores, transporte del prompt, despacho del panel, registros y scripts de cierre — pertenece a [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md). Este documento define la metodología y la regla de convergencia.

La revisión por pares siempre requiere activación humana. El agente puede sugerir un panel, pero no debe montarlo ni despacharlo sin pedido del usuario o acuerdo explícito. Esta traducción del documento no es en sí misma una revisión por pares.

## Qué es la revisión por pares

El autor, normalmente el agente principal, prepara un manuscrito breve con:

1. la lectura del problema;
2. la solución propuesta;
3. las fuentes que respaldan o contradicen la propuesta;
4. las decisiones abiertas.

El manuscrito se somete a un panel de pares. Cada revisor:

- piensa de forma independiente y devuelve su propio veredicto (`agree`, `revise` o `reject`) con justificación y recomendaciones priorizadas;
- verifica directamente las fuentes citadas — el repositorio y, cuando esté autorizado, un espacio de trabajo de la KB o experimento con el `-Cd`/cwd más restringido posible — para confirmar, ajustar o refutar las afirmaciones del autor; el manuscrito es insumo de evaluación, no verdad;
- permite que el autor lleve adelante una versión mejorada: v1 → v2 → ... hasta el cierre final.

## Regla general

- **Independencia.** Todos los revisores reciben el mismo manuscrito y un prompt mínimo, sin enriquecimiento que filtre lo que el autor ya sabe o hizo. No se deben asignar personas ni lentes a cada revisor; esa cuestión queda como trabajo futuro. Una división por capacidad no es una persona: si un revisor no puede ejecutar comandos de shell, puede recibir un dossier equivalente de hechos en lugar de comandos crudos. El contenido revisado y la tarea son los mismos; solo cambia cómo llegan los hechos. La aplicación pre-push de esa división está en [`14`](14-reinforced-pre-push-review.md) / [`13`](13-pre-push-review.md), en el modo asistido por dossier.
- **Diversidad de modelos.** Se debe dar preferencia a revisores de creadores de modelos distintos del autor y entre sí. Pueden participar subagentes nativos y LLM secundarios mediante [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md). El piso mínimo para revisión por pares es de al menos dos creadores de modelos distintos entre los revisores efectivamente consultados. Por debajo de ese piso no hay panel de revisión por pares; véase [Composición del panel](#composición-del-panel). El piso aplica a toda la composición, aunque combine subagentes nativos, LLM delegados o ambos.
- **Detenerse ante el primer gap informado.** Cualquier gap informado por un revisor detiene de inmediato la decisión de la ronda, a la espera del triaje humano; no es necesario aceptarlo primero como un gap real. El triaje humano determina si el hallazgo es un gap real, una convención local o un falso positivo. Si un gap real requiere corrección, el autor actualiza el manuscrito y crea una versión nueva. Esta regla gobierna la convergencia, no el transporte. Las llamadas paralelas ya despachadas pueden terminar, pero la decisión no se reanuda hasta que concluya el triaje; véase [Composición del panel](#composición-del-panel).
- **El panel queda desactualizado con cada versión nueva.** Cada versión nueva invalida los veredictos anteriores porque revisaron otro artefacto. Un resultado “sin gaps” solo aplica a la versión exacta revisada.
- **Regresión autoinfligida.** “Desactualizado con cada versión” obliga a revisar de nuevo, pero no garantiza que revisores externos detecten que vN+1 cambió sutilmente una decisión ya aprobada. En sesiones de contexto largo, el autor debe comparar vN+1 contra vN en decisiones cerradas y especificación, no en todo el texto, antes de volver a someter. El ítem “relay auditable” en el backlog de ideas de los mantenedores (no publicado) especifica, aunque todavía no mecaniza, un checklist `newClaim` / `reordered` / `resolvedConflict` en esa dirección.
- **Volver al disidente.** Después de corregir, el manuscrito debe volver a someterse al revisor que formuló la objeción y se debe confirmar que la corrección la resuelve en sus propios términos. El éxito no debe declararse solo porque hayan aprobado revisores más permisivos.
- **El ciclo no se detiene a medias.** Una vez iniciada, la revisión por pares es un ciclo: gap → triaje humano → nueva versión → recomponer el panel sobre la nueva versión → repetir hasta el cierre.
- **La convergencia es el estado listo.** Un plan converge solo cuando todo el panel diverso válido informa cero gaps sobre la versión final. Las aprobaciones parciales no cuentan, incluida la aprobación solo del disidente o de revisores que aprobaron una versión anterior. Un panel de una sola familia converge trivialmente y no es revisión por pares. Si el autor crea vN+1 a partir de los dictámenes, esa versión todavía no fue revisada. Entregarla como “terminada” sin volver a someterla constituye una falsa convergencia; el estado debe indicarse como “vN+1 propuesta, pendiente de resubmisión”. Como mínimo, la nueva versión debe volver a someterse a todos los disidentes, pero la convergencia final exige el panel completo sobre la versión final.
- **“De acuerdo con reservas” no es convergencia.** Un veredicto como “de acuerdo con reservas” o “aprobado con sugerencias” declara gaps. El orquestador informa el gap y no cierra la ronda, no lo clasifica por su cuenta ni declara convergencia por cuenta propia.
- **El estado de vN+1 se registra al redactarla.** Cuando el agente redacta vN+1, registra `-VNextState pendingResubmission` en [`Resolve-LlmDelegatePeerReviewCloseout.ps1`](../../skills/mimir-delegate/scripts/Resolve-LlmDelegatePeerReviewCloseout.ps1). El cierre bloquea (`closeoutReady=false`) hasta que vN+1 sea `resubmitted` o el humano decline la resubmisión de forma auditable con `resubmissionDeclinedByHuman`, quién decidió, por qué y el `RoundId`. El script de cierre es sin estado: el estado llega por parámetro y se reevalúa en cada llamada. La ruta append-only por `RoundId` y la monotonicidad entre llamadas pertenecen al orquestador más recibo/registro, no al script. La única transición válida desde `pendingResubmission` a un estado terminal es una nueva invocación de cierre con el `-VNextState` terminal; cambiar el recibo por otra vía evita la compuerta. Límite honesto: este eje evita el silencio, pero no prueba fabricación porque el script no lee la conversación.
- **La ejecución sigue siendo una decisión humana.** La convergencia deja el plan liberable para ejecución, pero el humano decide si ejecutar. En el caso pre-push del `14`, el equivalente es “push-ready”; el push sigue requiriendo autorización explícita.

## Cuando el diseño se estabiliza: congelar el papel y mover la prueba al código

La regla anterior indica cuándo el panel está de acuerdo; no indica cuándo dejar de iterar en papel. Si las rondas dejan de reabrir arquitectura y las objeciones restantes tratan precisión de implementación — especificación, telemetría, self-tests — y no gaps de diseño, el agente puede proponer al humano congelar el diseño, cerrar el ciclo en papel y transferir la prueba a la implementación. Es una decisión humana. La regla es un disparador de decisión, no permiso para que el agente cierre el debate solo.

- **Congelar no es converger.** Congelar es la decisión humana auditada de detener el ciclo de diseño en papel y transferir la prueba a implementación/self-test. No es convergencia ni convergencia débil. Se deben usar expresiones como “el diseño está estable” o “la arquitectura ya no se reabre”, nunca “convergió”.
- **Cómo lo propone el agente.** Se debe enumerar cada objeción restante y clasificarla como “no reabre arquitectura” o “todavía discute diseño”, con justificación. El humano acepta, rechaza o pide otra ronda.
- **La regla sigue activa hasta que el humano congele.** Hasta esa decisión, siguen vigentes desactualización por versión, retorno al disidente y panel completo sobre la versión final.
- **Registro auditable.** La decisión debe registrarse en [`Resolve-LlmDelegatePeerReviewCloseout.ps1`](../../skills/mimir-delegate/scripts/Resolve-LlmDelegatePeerReviewCloseout.ps1) como `resubmissionDeclinedByHuman`, con decisor, razón como “prueba transferida a implementación/self-test” y `RoundId`; no debe marcarse como `resubmitted`. “Declinar la resubmisión en papel” cubre dos subcasos: prueba transferida a implementación/self-test, y abandono sin prueba sustituta. La razón los distingue.
- **Salvedad.** Si el disidente todavía identifica un defecto real de diseño, el papel permanece abierto. Solo migra la precisión de implementación. La frontera entre diseño y precisión requiere triaje humano.
- **Ortogonal a la composición del panel.** Congelar controla cuántas versiones iterar en el tiempo. No autoriza reducir el panel, detenerse en el piso de familias ni saltar la lista de revisores preferidos; la composición se rige por [Composición del panel](#composición-del-panel) y por los ítems de alcance del backlog de ideas de los mantenedores (no publicado).

## Roles: montaje y opinión del agente, decisiones del humano

- **Montaje del panel.** El agente puede, como manos del humano y solo después de activación humana, despachar revisores diversos mediante [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md) y subagentes nativos, enviar a cada uno el manuscrito más el prompt mínimo y recoger veredictos. Antes de usar la etiqueta revisión por pares, el agente valida el piso de diversidad sobre la lista completa de revisores. Los subagentes nativos entran con el creador del modelo de su `targetModelKey`; no heredan como creador la herramienta orquestadora. El despacho/recogida mecánico de revisores delegados puede usar `Invoke-LlmDelegatePanelDispatch.ps1`, pero el harness es estrictamente mecánico: inyección de nativos, piso de diversidad, cierre, triaje y convergencia permanecen con el orquestador/humano.
- **Nodos de decisión.** El humano decide si un hallazgo es un gap real, declara convergencia y autoriza ejecución. Se espera que el agente dé su opinión y recomendación sobre cada punto antes de la decisión humana. El agente no debe decidir y actuar solo: no clasifica por su cuenta seguido de ediciones, no convergencia unilateral, no ejecución.
- **Rol de revisor.** Un revisor, humano o agente, evalúa el manuscrito contra las fuentes.

Guardrail: un agente no debe (1) decidir y actuar en lugar del humano, ni (2) fingir que una única opinión es revisión por pares. Triaje, convergencia y ejecución son nodos de decisión humana.

### Recibo obligatorio

Antes de usar la etiqueta `revisión por pares`, el orquestador informa:

- archivos metodológicos leídos;
- manuscrito/prompt enviado;
- revisores efectivamente consultados;
- creador/familia de modelo de cada revisor;
- resultado del piso de diversidad;
- veredicto/estado de cada revisor;
- `vNextState`;
- cuando se usó `mimir-delegate`, el `receiptAddendum` de `Resolve-LlmDelegatePeerReviewCloseout.ps1`.

Si existía una lista de revisores preferidos, el recibo también lista cada titular y fallback aplicable con estado final auditable: respondió con dictamen, consultado sin dictamen útil (`noResponse`), timeout, cuota, error, resultado de verificación (`ask`/`deny`), no disponible, saltado tras éxito del titular, saltado por política, no intentado, excluido por decisión humana o detenido por primer gap. Los estados saltados llevan `countsForDiversity=false`.

Si el recibo está ausente, incompleto, es incompatible con al menos dos creadores efectivamente consultados, está marcado como `insufficientDiversityAfterFallback` o incluye `closeoutReady=false`, el resultado debe etiquetarse honestamente como `solo opinion`, `second opinion (N)` o ronda inconclusa. Una respuesta fuera de tarea, o dentro de tarea pero sustancialmente vacía porque no toma posición sobre el manuscrito, es `noResponse` y no cuenta para el piso. El criterio es sustancia frente al manuscrito, no cantidad de caracteres; un dictamen breve y auditable puede ser útil.

### Tiempo mínimo como evidencia negativa

Una respuesta casi inmediata es incompatible con esta metodología. Leer la documentación, montar un panel, consultar al menos dos creadores y recoger veredictos toma tiempo material. Operativamente, una respuesta producida en menos de 30 segundos desde el pedido no debe etiquetarse como `revisión por pares`, salvo que el agente solo esté informando un panel previamente completado e identificable por recibo/registro. El umbral no prueba que respuestas más largas sean válidas; solo invalida la etiqueta cuando el flujo real sería físicamente imposible.

## Composición del panel

Principio: usar revisores independientes de creadores de modelos distintos del autor. En el núcleo se prefieren modelos con fuerte adherencia a instrucciones. Modelos menos fuertes pueden ser voces adicionales, nunca el único revisor decisivo; toda objeción pasa por triaje humano. Mistral Large 3 y Nemotron 3 Ultra están vetados por bajo grounding observado.

Los modelos y backends se deben descubrir mediante [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md), sin volver a sondear en cada uso. Si existe una lista de revisores preferidos (`preferred-reviewers.<orchestrator>.json` → `preferred-reviewers.json` de la máquina, schema 3), esa lista aporta la composición/candidatos preferidos. No es un pool opcional del que el agente pueda elegir silenciosamente el mínimo, ni autorización de envío. Los revisores titulares tienen `rank` positivo y único; los titulares CLI pueden tener `fallbackChain[]` ordenado; los nativos no pueden tener cadenas de fallback. Un fallback se activa solo cuando el titular falla o queda no disponible, debe tener estado auditable al saltarse o activarse, nunca sustituye la verificación de autorización por destino y nunca reduce el piso de diversidad. La única política de fallback persistida que admite el mecanismo de despacho es `ordered-chain`, activada en `quota`, `timeout`, `error` o `unavailable`; las variantes no admitidas bloquean antes del despacho. `noResponse` es la reclasificación post-hoc del orquestador cuando no hay dictamen útil, no un disparador mecánico primario.

En el primer uso sin lista, se debe preguntar al usuario qué herramientas/modelos tiene y cuáles prefiere, con ejemplos reconocibles (`Claude Code`, `opencode/Ollama Cloud`, `Codex`, `Copilot`, `Gemini`, `Antigravity` o el subagente nativo de la herramienta actual); la calibración o el guardado de la lista solo se ofrecen después de que el usuario elija. Las preferencias están subordinadas a esta política de roles y a la verificación de autorización por destino.

### Piso mecánico de diversidad

Una revisión por pares requiere al menos dos creadores de modelos distintos. En el código, `family` de `Get-LlmDelegateTargetFamily` significa creador del modelo, no la línea o serie del modelo. En la mayoría de claves directas `provider/model`, el creador es el prefijo antes de `/`: `google/gemini-*` → `google`, `anthropic/claude-*` → `anthropic`, `openai/gpt-*` → `openai`, `github-copilot/*` → `github-copilot`.

Reglas de agregadores de `LlmDelegateTargetFamilySupport.ps1`:

- `nvidia/<creator>/<model>` extrae el segundo segmento y normaliza creadores conocidos: `deepseek-ai` → `deepseek`, `mistralai` → `mistral`, `qwen` → `alibaba`, `meta-llama`/`facebook` → `meta`, `thudm`/`glm` → `z-ai`, `minimax`/`minimaxai` → `minimaxai`, `moonshotai` → `moonshot`, `nvidia` → `nvidia`; suborganizaciones desconocidas usan el segundo segmento tal cual. Las claves `nvidia` de dos niveles resuelven `nemotron-*` → `nvidia`, `llama-*` → `meta`, o `nvidia` en otro caso.
- `antigravity/*` resuelve `antigravity/gemini-*` o desconocido/default → `google`, `antigravity/claude-*` → `anthropic`, y `antigravity/gpt-*` → `openai`.
- Los slugs nativos de Cursor resuelven por creador del modelo: `cursor-grok-*` / `cursor/grok-*` → `xai`; `cursor-composer-*` / `cursor/composer-*` → `anysphere`. No deben contarse como `cursor`, porque el eje es quién entrenó los pesos.
- Los agregadores de dos niveles sin creador en la ruta, como `ollama-cloud/*`, `opencode-go/*` y `atlas-cloud/*`, se cuentan por prefijo de proveedor de destino como subconteo documentado que preserva la gobernanza de endpoint y la semántica de concurrencia del mecanismo de despacho.

| Término | Significado | Gobernado por | Ejemplos |
|---|---|---|---|
| Backend / Harness | Herramienta o CLI local que transporta el prompt. | Adaptadores y mecanismo de despacho. | `opencode`, `codex`, `claude-code`, `copilot`, `gemini`, `antigravity` |
| Proveedor de destino | Servicio/servidor cloud que recibe la solicitud de red. | Verificación de confidencialidad y política por KB. | `openai`, `anthropic`, `nvidia`, `ollama-cloud`, `antigravity` |
| Creador del modelo | Organización que entrenó la arquitectura/pesos; eje de diversidad. | `Get-LlmDelegateTargetFamily`. | `openai`, `anthropic`, `google`, `deepseek`, `z-ai`, `moonshot`, `alibaba`, `meta`, `minimaxai`, `mistral`, `microsoft`, `nvidia`, `xai`, `anysphere` |
| Familia del modelo | Línea de modelos dentro del portafolio de un creador. | Identificador de catálogo del creador. | Gemini vs Gemma; GPT vs o1; Mistral vs Codestral; Qwen vs Qwen-Coder |

Se debe construir el array completo de candidatos para `Resolve-LlmDelegatePanelDiversity.ps1 -CandidatesJson <json>`. Antes del despacho, debe incluirse cada revisor principal de la lista de preferencias resuelta y todos los subagentes nativos que inyectará el orquestador; nunca se debe seleccionar solo el subconjunto necesario para alcanzar el piso. Cada objeto debe incluir `targetModelKey`, `backend` cuando esté disponible y, en `verdict`, el resultado de `Resolve-LlmDelegateAuthorization.ps1` para ese destino (`allow`, `ask` o `deny`). Por ejemplo, `Resolve-LlmDelegatePanelDiversity.ps1 -CandidatesJson '[{"targetModelKey":"openai/gpt-5.5","backend":"codex","verdict":"allow"},{"targetModelKey":"google/gemini-3-flash-preview","backend":"orchestrator-native","verdict":"ask"}]'` ilustra solo la forma de los objetos; se debe pasar la lista completa, no solo estas dos entradas. El resolvedor deriva la familia de `targetModelKey`; es consultivo y emite `panelReady`, `needsBatchAuthorization`, `insufficientDiversity` o `insufficientDiversityAfterFallback`. `panelReady` significa al menos dos creadores conocidos permitidos. `needsBatchAuthorization` significa que los destinos `ask` listados cerrarían el piso si se autorizan; esos pedidos se deben presentar conjuntamente al humano, con el destino y la sensibilidad de cada uno. `insufficientDiversity` significa que ni con autorización se alcanza el piso; no debe denominarse revisión por pares. Tras el despacho, se debe evaluar el conjunto completo de intentos y estados, incluidos los fallbacks aplicables; las entradas con `countsForDiversity=false` (`skippedAfterSuccess`, `skippedByPolicy`, `notAttempted`) no cuentan. Si el fallback no recupera al menos dos creadores, `insufficientDiversityAfterFallback` bloquea la etiqueta. Un caso con cero preautorizados es solo un pedido para intentar montar un panel. El resolvedor de diversidad no decide la autorización; `Resolve-LlmDelegateAuthorization.ps1` conserva la autoridad por destino.

Esto aplica a cualquier forma de montar el panel. Antes de usar la etiqueta, se debe materializar la lista completa de revisores, asignar un creador a cada uno, incluidos los subagentes nativos, y validar el piso sobre esa lista completa. Solo cuentan los creadores conocidos por `Test-LlmDelegateFamilyKnown`; los desconocidos van a `droppedUnknownFamilies` hasta ampliar la allowlist. Un panel solo con nativos de un creador es `second opinion`, no revisión por pares.

La curaduría de revisores nativos es por orquestador, nunca de toda la máquina. Un titular `orchestrator-native-subagent` existe solo dentro del harness que lo ejecuta; persistirlo en `preferred-reviewers.json` de máquina haría que otro harness lo resuelva como su propio nativo. `Set-LlmDelegatePreferredReviewers.ps1` rechaza `native-machine-scope-forbidden` y rechaza titulares nativos cuya clave identifica otro harness (`native-harness-orchestrator-mismatch`). Los archivos antiguos siguen siendo legibles, pero `Resolve-` marca diagnósticos para confirmación.

Antes de editar preferencias, estas se deben resolver primero y luego se deben leer `preferenceSource`, `effectivePreferredPath` y `cascadeOrchestratorExists`. Un pedido genérico en esta sesión modifica el alcance del orquestador cuando su archivo existe o es efectivo; el alcance de máquina se usa solo para pedidos explícitos de máquina/todos los harnesses. Escribir preferencias de máquina mientras un archivo de orquestador las sombrea no afecta al harness actual.

Límite conocido: la comparación harness-vs-orquestador solo es exigible cuando la propia clave trae el harness, actualmente `cursor/*` y `cursor-*`. Una clave nativa neutra como `moonshot/kimi-k3-max` no identifica su harness; la calibración sigue siendo responsable de esa curaduría.

Los identificadores de orquestador son una lista abierta: cualquier slug que cumpla `^[a-z0-9][a-z0-9-]{0,39}$` (en minúsculas) nombra un orquestador, con `cursor`, `claude-code`, `codex` y `opencode` como los harnesses que este repositorio sabe identificar. Bajo un orquestador que no puede identificar, `Resolve-LlmDelegatePreferredReviewers.ps1` marca cada titular nativo como no verificable en `diagnostics`; el orquestador no debe contarlo para el piso de diversidad (`countsForDiversity=false`) hasta confirmar que el harness ofrece ese modelo. Un slug mal formado se rechaza (`orchestrator-invalid`).

Los subagentes nativos deben usarse cuando la herramienta actual los ofrece. Añaden revisión independiente con el creador declarado en `targetModelKey`, pero no satisfacen solos el piso de diversidad si son el único creador.

### Despacho: serial para pre-push, paralelo para revisión de plan

“Detenerse ante el primer gap informado” gobierna la convergencia, no el despacho. En la validación de plan/diseño, la decisión debe pausarse en cuanto cualquier revisor informe un gap y mantenerse a la espera del triaje humano, incluso si ya hay llamadas paralelas en curso. Esas llamadas pueden terminar, pero sus resultados no reanudan la decisión ni cuentan como convergencia mientras el triaje siga pendiente. Si el triaje conduce a modificar el manuscrito, la nueva versión debe volver a someterse; la convergencia final exige el panel completo y volver a consultar a los disidentes sobre la versión final. En pre-push (`14`), el despacho es serial por costo/control: el revisor con git ejecuta la rutina completa del `13`, mientras el revisor solo semántico usa un dossier.

## Confidencialidad

Antes de enviar cualquier contenido, se debe clasificar el manuscrito como `public` (texto del repositorio, plantilla sanitizada, diff público) o `kb-sensitive` (contenido de un espacio de trabajo de KB real). Para cada revisor, se debe ejecutar `Resolve-LlmDelegateAuthorization.ps1`; el contenido sensible solo va a un modelo externo con autorización. La verificación reevalúa el destino y la sensibilidad de forma determinista y no depende del inventario de capacidades.

Los revisores agénticos se ejecutan con el directorio más restringido necesario cuando el adaptador admite `-Cd` (Codex, Claude Code, Copilot, Gemini). El adaptador directo genérico `Invoke-OpenCode` sigue disponible para la delegación habitual y la revisión de plan/diseño, sujeto a la autorización por destino y a la evaluación del operador sobre la configuración local y el cwd. opencode no admite `-Cd`: sin `-Agent`, usa la configuración predeterminada local (normalmente `build`), que puede ser agéntica; seleccionar explícitamente un agente en el adaptador directo tampoco garantiza confinamiento de solo lectura y sin acceso a shell. El mecanismo de despacho del panel es una ruta distinta: rechaza `invokeArgs.agent`, por lo que el revisor opencode del panel no recibe un agente explícito y usa el que resuelva la configuración local; esta ruta no puede garantizar solo lectura ni ausencia de acceso a shell. Solo para el panel reforzado pre-push, [`14`](14-reinforced-pre-push-review.md) exige que el orquestador omita opencode manualmente hasta que exista un confinamiento exigible de solo lectura y sin shell. El mecanismo de despacho sigue enumerando opencode y no aplica esta omisión. Es una política humana específica para el montaje del panel pre-push, no una prohibición general de opencode ni de su adaptador directo. Antigravity está fijado deliberadamente a `public-review`, solo semántico y payloads `public`: si una política permite `kb-sensitive`, el adaptador igualmente lo convierte en `unavailable` con `refusedSensitivity` antes de invocar. Su scratch y redirección de entorno son higiene de estado, no sandbox; los keyrings globales siguen compartidos y esa limitación debe constar en el recibo.

La validación de plan/diseño en el repositorio de desarrollo suele ser `public`, el caso ideal para diversidad de modelos. Elegir un cwd seguro sigue siendo responsabilidad del operador. Si el cwd contiene secretos no versionados, logs, cachés o archivos `.env`, un revisor agéntico podría leerlos; los señuelos de self-test no sustituyen la revisión del directorio real.

## Recibo y registro

El recibo mínimo es obligatorio antes de usar la etiqueta `revisión por pares`. Debe incluir los campos de [Recibo obligatorio](#recibo-obligatorio) y siempre debe incluir `vNextState` (`notProduced`, `pendingResubmission`, `resubmitted` o `resubmissionDeclinedByHuman`) para que el campo nunca esté ausente en silencio. Cuando se use `mimir-delegate`, debe incluir el `receiptAddendum` del cierre mecánico. Cuando se hayan resuelto revisores preferidos (`hasPreferences=true`), debe incluir el estado de cada titular y fallback con `attemptRole`, `fallbackOf` y `countsForDiversity`.

Si `Resolve-LlmDelegatePeerReviewCloseout.ps1` devuelve `closeoutReady=false`, incluso por `insufficient-diversity-after-fallback`, `vnext-pending-resubmission` o `vnext-resubmission-decline-unaudited`, se debe presentar su `requiredUserPrompt` y la ronda no debe cerrarse como completa. `vNextState` evita silencio, no fabricación.

Para ciclos reforzados o de alto riesgo, se debe guardar un registro auditable con versiones del manuscrito, prompts, veredictos por revisor/versión y resumen de convergencia bajo `<temp del sistema>\mimir-panel-dispatch\<id-de-ronda>\`, la raíz de registro por defecto de `Invoke-LlmDelegatePanelDispatch.ps1` (`-TempDir` cambia la raíz; `-RoundId` es un GUID por defecto). El registro en archivo es opcional para uso liviano, efímero y queda fuera del repositorio.

## Prompt mínimo

Para validación de plan/diseño, el prompt mínimo indica al revisor que lea el manuscrito y las fuentes citadas, que no trate el manuscrito como verdad, que confirme o refute cada afirmación contra fuentes y que informe gaps más recomendaciones priorizadas. No debe enriquecer al revisor con la conclusión del autor.

El rol para backends agénticos debe quedar protegido: el destinatario es revisor y debe emitir su propio veredicto (`agree`, `revise` o `reject`). No debe ejecutar el plan, conducir su propia revisión por pares ni delegar. Una respuesta que asume la tarea en lugar de opinar no es dictamen y cuenta como ausencia de respuesta útil.

## Relación con otros documentos

| Documento | Función |
|---|---|
| [`13-pre-push-review.md`](13-pre-push-review.md) | Rutina que cada revisor ejecuta antes de un push. |
| [`14-reinforced-pre-push-review.md`](14-reinforced-pre-push-review.md) | Aplicación reforzada pre-push de la revisión por pares; panel sobre la rutina del `13`. |
| este `15` | Metodología general de revisión por pares de plan/diseño y regla normativa de convergencia. |
| [`mimir-delegate/SKILL.md`](../../skills/mimir-delegate/SKILL.md) | Mecanismo de delegación a LLM secundario; la revisión de panel es un caso de uso dirigido por humanos. |

Papel vs código: este `15` revisa diseño/plan mientras las decisiones todavía son maleables. `13` valida el estado de código antes de un push, y `14` aplica esta metodología de revisión por pares a esa rutina pre-push. El código congela lo que el papel deja maleable; los self-tests prueban lo que el papel solo puede debatir.

## Trabajo futuro

- Backends one-shot (`llm`, `mods` o equivalente) que envíen solo el prompt sin capa agéntica.
- Personas o lentes de revisión, que siguen en tensión con la regla de prompt mínimo independiente.
- Recuperación automática single-flight fuera de `fallbackChain` para adapters distintos del camino `ordered-chain` soportado; todavía requiere decisión humana explícita.
