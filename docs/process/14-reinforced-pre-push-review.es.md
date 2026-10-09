# 14 — Revisión pre-push reforzada (panel multi-modelo)

> **Flujo de mantenedores.** Este documento describe el flujo de revisión de quienes mantienen este repositorio. Es opcional para quienes contribuyen: las únicas verificaciones que debe pasar una contribución son las verificaciones mecánicas que ejecuta la CI, listadas en [`CONTRIBUTING.es.md`](../../CONTRIBUTING.es.md).

## Función de este documento

Este es el nivel reforzado y opcional de la revisión pre-push. [`13-pre-push-review.md`](13-pre-push-review.md) define la rutina que ejecuta cada revisor: paso mecánico más fase semántica. Este documento aplica la metodología de revisión por pares en [`15-peer-review.md`](15-peer-review.md) al pre-push: orquesta un panel diverso de revisores sobre la rutina del `13` y aplica la regla de convergencia que decide cuándo un estado es push-ready.

El mecanismo de delegación —backends de revisión, adapters, archivos de revisores preferidos, registros y scripts de closeout— pertenece a [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md). Este documento solo gobierna la política del panel pre-push. La metodología genérica y la regla de convergencia son normativas en [`15`](15-peer-review.md).

La revisión reforzada siempre requiere activación humana, como toda delegación. La rutina normal del `13` alcanza para el flujo ordinario; este panel es una escalación cuando se desea diversidad de modelos. Gobierna la rutina pre-push del repositorio Mimir Lite.

## La regla de convergencia aplicada a pre-push

En [`15`](15-peer-review.md), una versión de manuscrito converge solo después de que todo el panel diverso válido informa cero brechas sobre la versión final. En pre-push, la “versión” revisada es un commit/estado HEAD, y “listo” significa **push-ready**, no permiso para hacer push.

- **Prompt por capacidad, no por persona.** Un revisor `git-capable` recibe el prompt mínimo `execute a rotina pre push, sem push` y ejecuta la rutina completa del `13`. Un revisor `semantic-only` recibe el dossier del `13` y realiza solo la fase semántica en modo read-only. No asigne personas ni lentes por revisor.
- **Detenerse ante la primera brecha.** El primer revisor que informe una brecha detiene la ronda. El agente informa el veredicto y su propia recomendación de triaje; el humano decide si el hallazgo es real, convención local o falso positivo. Solo después de que el humano autorice expresamente tanto la corrección como el commit, el agente puede aplicar la corrección; entonces se commitea de inmediato. Esa autorización también permite que el agente reinicie el panel completo sobre el nuevo HEAD sin otra activación inicial. El humano puede detener el ciclo en cualquier momento; ninguna edición ni commit es automático.
- **Cada nuevo commit vuelve obsoleto el panel.** Las aprobaciones anteriores aplican solo al HEAD exacto revisado. Después de un commit de corrección expresamente autorizado, reinicie el panel completo sobre el nuevo HEAD sin exigir otra activación inicial de “ejecuta la revisión reforzada”, salvo que el humano detenga el ciclo.
- **El ciclo no se detiene a mitad de camino.** Brecha → triaje humano → autorización expresa de la corrección y el commit → commit inmediato de la corrección → panel completo sobre el nuevo HEAD → repetir hasta el cierre o hasta que el humano detenga el ciclo. “No push” solo prohíbe el push final; no detiene el ciclo de revisión.
- **Estado push-ready.** Después del último cambio del repositorio, todo el panel válido debe informar que no hay brechas sobre ese estado final. Un pase parcial, un pase solo del disidente o un pase de revisores que revisaron un commit anterior no cuenta. El push en sí sigue requiriendo autorización humana explícita según el `13`.
- **Congelar diseño vs prueba en código.** La regla genérica de congelar el papel está en `15`. En pre-push, la prueba ya es el código y la rutina del `13`; ningún agente puede declarar convergencia ni hacer push unilateralmente.

## Roles: montaje y opinión por el agente; decisiones por el humano

- **Montaje del panel.** Tras la activación humana inicial, el agente despacha revisores diversos elegibles mediante [`mimir-delegate`](../../skills/mimir-delegate/SKILL.md) y/o mecanismos de revisión nativos, usando el prompt determinado por capacidad. El agente omite manualmente opencode del conjunto in-panel según la política siguiente; el dispatcher no aplica esta omisión. Después de un commit de corrección expresamente autorizado, el agente reinicia el panel completo sobre el nuevo HEAD sin otra activación inicial, salvo que el humano detenga el ciclo.
- **Opinión del agente.** El agente debe recomendar triaje para cada hallazgo: qué parece brecha real, convención o falso positivo, y por qué.
- **Decisión humana.** El humano decide el triaje y la convergencia, autoriza expresamente tanto cada corrección como su commit y autoriza el push. Sin esa autorización expresa para corregir y commitear, el agente no edita ni commitea. No debe declarar convergencia por su cuenta, hacer staging ni commitear cambios ajenos a la corrección autorizada, hacer push ni fingir que una revisión individual es el panel reforzado.
- **Rol de revisor.** Un revisor, humano o agente, ejecuta la rutina aplicable del `13` según su capacidad.

## Composición del panel

Use revisores de creadores de modelo distintos cuando sea posible. El eje de diversidad es el creador de `targetModelKey`, no el nombre de la herramienta local. Revisores nativos cuentan por el creador declarado en su `targetModelKey` y no heredan la familia de la herramienta orquestadora.

Se prefieren modelos con fuerte seguimiento de instrucciones en el núcleo. Modelos más débiles pueden ser voces adicionales, nunca el único revisor decisivo. Mistral Large 3 y Nemotron 3 Ultra siguen vetados con dureza por débil fundamentación observada. Nemotron 3 Super no tiene veto duro, pero usos previos en la revisión pre-push reforzada produjeron afirmaciones fabricadas sobre el repositorio; verifique cada cita de archivo/línea antes de aceptar cualquier hallazgo o justificación de esa línea.

Descubra backends disponibles con el inventario de capacidades en [`Build-LlmDelegateCapabilityManifest.ps1`](../../skills/mimir-delegate/scripts/Build-LlmDelegateCapabilityManifest.ps1), en lugar de re-sondear cada vez. Actualice el descubrimiento de opencode con `opencode models` al refrescar ese inventario.

Inventario actual de backends desde el dispatcher y la compuerta:

- `opencode`
- `codex`
- `claude-code`
- `copilot`
- `gemini`
- `antigravity`

El conjunto de backends pertenece a [`skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1`](../../skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1) y se verifica con [`tools/Test-PrePushBackendEnumerationParity.ps1`](../../tools/Test-PrePushBackendEnumerationParity.ps1). No trate este documento como fuente de verdad de adapters.

Las familias recomendadas para el panel in-panel son ejemplos, no una regla fija: Codex / OpenAI, Claude Code / Anthropic cuando el orquestador no sea Anthropic, y Copilot, Gemini, Antigravity `public-review` o revisores nativos adicionales cuando estén disponibles. El principio y el piso de diversidad del `15` prevalecen sobre cualquier lista de ejemplo. Aunque opencode sigue disponible como backend y su adapter directo sigue disponible, no es una ruta in-panel elegible ni recomendada hasta que exista una postura de solo lectura y sin shell que sea exigible. El montaje del panel debe omitirlo manualmente; el dispatcher no aplica esta restricción de forma automática.

Un panel reforzado pre-push válido debe satisfacer, en este orden:

1. **Al menos un revisor `git-capable`** que reproduzca la Sección A del dossier de forma independiente. Sin uno, la Sección A no está verificada y la ronda no puede concluir.
2. **El piso de diversidad del `15`**: al menos dos creadores de modelo efectivamente consultados. Por debajo de ese piso, etiquete el resultado como `solo opinion` o `second opinion (N)`, no revisión por pares.
3. **Reglas de transporte y omisión**: los revisores omitidos quedan registrados con estados y razones auditables; luego se reevalúan el piso y el invariante `git-capable`.

El ancla `git-capable` preferida es un Codex-delegate externo cuando está disponible. Como la cuota puede ser limitante, el fallback frecuente es un subagente nativo bajo el harness del orquestador. Eso está permitido, pero debe registrarse como garantía reducida (`gitCapableAnchorFamily=orchestrator-native` en los recibos). Aceptar la asimetría en la que revisores `semantic-only` confían en el dossier del orquestador es una decisión humana registrada como `asymmetryAcceptedBy`.

<!-- backend-parity: ignore -->
### Transporte de Codex frente a ancla nativa

La captura durable del adapter Codex (`Invoke-Codex` / `codex-jobs` en disco) no mejora la garantía reducida del camino con ancla nativa. Un subagente nativo no pasa por `Invoke-Codex` ni por el almacenamiento durable de Codex; es un ancla por el harness del orquestador, no por el transporte recuperable del adapter Codex.

## Matriz operativa — capacidad × transporte

Capacidad y transporte del dossier son ejes independientes. Una herramienta fuerte no es automáticamente `git-capable` dentro de este panel.

| Backend / ruta | Rol en el panel | Fuera del panel (adapter) | Transporte del dossier | Notas |
|---|---|---|---|---|
| Codex-delegate | `git-capable` | `git-capable` | N/A | Sandbox read-only en uso de panel. |
| Subagente nativo (`orchestrator-native`) | `git-capable` | N/A típico | N/A | Ancla frecuente; no es clave de `$AdapterScript`. |
| Claude Code (async / panel) | `semantic-only` | `git-capable` vía `Invoke-ClaudeCode.ps1` síncrono con `-Tools default -PermissionMode dontAsk` | `stdin-dossier-capable` | El uso directo del adapter no cuenta como revisor `git-capable` in-panel del `14`; el perfil in-panel `git-capable` sigue como trabajo futuro. |
| opencode | Omitido manualmente del conjunto de revisores in-panel; no despachar ni contar hasta que exista una postura exigible de solo lectura y sin shell | El adapter directo sigue disponible; sin `-Agent` usa el default configurado de opencode, que puede ser agéntico. Nombrar explícitamente un agente restringido no es automáticamente seguro ni garantiza un límite exigible sin shell. | `stdin-dossier-capable` | El dispatcher todavía enumera opencode y no aplica la omisión de montaje del panel; rechaza `invokeArgs.agent`, por lo que un opencode in-panel seleccionado no recibe agente explícito. Vea las notas de cwd/worktree y secretos locales. |
| Copilot CLI | `semantic-only` | `semantic-only` | `argv-limited` (~30000 caracteres) | Omitir si el dossier supera el límite. |
| Gemini CLI | `semantic-only` | `semantic-only` (`ApprovalMode=plan`) | `argv-limited` (~30000 caracteres) | Omitir si el dossier supera el límite. |
| Antigravity `public-review` | `semantic-only` | siempre `semantic-only` | `argv-limited` (~30000 caracteres) | Nunca es ancla `git-capable`; crea su propio scratch; rechaza `-Cd`; acepta solo payload `public`. |

Regla de mantenimiento: esta tabla es una enumeración cerrada por eje. La compuerta de paridad de backends no puede inferir una fila nueva faltante cuando cada fila cita un solo backend. Cuando se agregue un backend al dispatcher, actualice esta matriz en el mismo cambio.

## Omisión y etiquetas degradadas

Un revisor `semantic-only` se omite cuando `dossierReady=false`, el dossier supera un límite de transporte `argv-limited`, el working tree está sucio o el perfil público de Antigravity rechaza la sensibilidad. Registre `unavailable` más la razón declarada aplicable (`dossier-unavailable`, `dossier-too-large`, `working-tree-dirty`, `refusedSensitivity` o la razón vigente del dispatcher). El closeout no usa estado `excluded`.

Para opencode, el montaje del panel debe omitirlo manualmente del `ReviewersJson` del dispatcher. Si fue seleccionado para el panel, el cierre puede representar esa omisión mediante `SelectedReviewersJson` y una entrada correspondiente en `PreferredReviewerStatesJson` con `state=unavailable` y `countsForDiversity=false`. Registre por separado la explicación legible por personas en el recibo obligatorio del panel destinado al usuario; no existe un campo `reason` por revisor para alguien ausente de la entrada del dispatcher ni en el cierre. No invente un token de razón ni afirme que el cierre registra la explicación. El dispatcher todavía contiene opencode y puede despacharlo para payloads `public`; esta política documentada no se aplica automáticamente allí. Su bloqueo actual de payloads `kb-sensitive` no aplica la omisión in-panel más amplia.

Después de omisiones, reevalúe el invariante `git-capable` y el piso de diversidad. Con árbol sucio, todos los revisores `semantic-only` quedan bloqueados; si Codex no está disponible y solo queda el ancla nativa, el resultado tiene como máximo una familia y debe degradar a `solo opinion` o `second opinion (N)`.

Para Antigravity, la compuerta de confidencialidad corre primero. `ask` y `deny` conservan sus estados de compuerta. Solo un `allow` de la compuerta para `kb-sensitive` queda bloqueado por la postura fija `public-review` como `unavailable` + `refusedSensitivity`. El adapter no reclasifica el payload.

## Estabilidad de HEAD

Regenerar el dossier en cada nuevo HEAD. Inmediatamente antes de cada despacho, compare `git rev-parse HEAD` vivo con el HEAD del dossier y revalide la precondición de árbol limpio. Una divergencia regenera el dossier. La revisión presupone HEAD estable durante cada despacho serial; el siguiente despacho detecta cualquier cambio.

## Orden de despacho

Cuando el usuario diga “ejecuta la revisión pre-push reforzada”, despache revisores en serie y pause ante la primera brecha. Esta es una elección de costo/control para pre-push: un revisor `git-capable` ejecuta la rutina completa del `13`. Los revisores `semantic-only` son más baratos porque leen el dossier, pero el despacho serial mantiene auditable el flujo de detenerse ante la primera brecha. Una optimización futura puede agrupar revisores `semantic-only`; la regla de convergencia sigue siendo la del `15`.

Mantenga el informe conciso: veredicto, triaje recomendado y evidencia necesaria para la decisión humana. No vuelva a resumir todo el estado del repositorio después de cada revisor.

## Notas de operación

### opencode en un git worktree en Windows

`opencode run` puede fallar desde un cwd de Git worktree por el gitlink `.git`. Para uso directo del adapter, materialice el HEAD en un directorio plano, por ejemplo con `git archive HEAD`, y ejecútelo allí. Esta solución no habilita opencode para la ruta in-panel reforzada, que sigue omitiéndolo manualmente. El dossier se entrega por stdin y no depende de ese cwd. Codex, Claude Code, Copilot y Gemini soportan `-Cd`; Antigravity `public-review` rechaza `-Cd` y usa su propio scratch.

### opencode en un cwd con secretos locales

opencode no tiene `-Cd`; hereda cwd. `external_directory[*]=deny` no protege `.env`, logs, cachés u otros secretos no versionados dentro de ese cwd, y una regla custom de agente puede permitir lecturas amplias por accidente. Para uso directo del adapter, el operador puede provisionar y pasar explícitamente un agente con `-Agent`, pero ni ese parámetro ni un cwd seguro garantizan automáticamente una postura exigible de solo lectura y sin shell. El adapter directo sigue disponible; evalúe su configuración real y el cwd, y no lo despache desde un directorio que contenga secretos. Para el panel reforzado, omita opencode sin importar el cwd hasta que la postura requerida sea exigible y registre la omisión en el recibo del orquestador.

## Prohibición

Un agente no debe:

1. decidir y actuar en lugar del humano — sin auto-triaje seguido de ediciones, sin editar ni commitear sin autorización humana expresa tanto para la corrección como para su commit, sin convergencia unilateral ni push, y sin hacer staging ni commitear cambios ajenos a la corrección autorizada; ni
2. fingir que un revisor individual es el panel reforzado.

El agente debe montar el panel y dar su opinión. Las decisiones siguen siendo nodos humanos.

## Relación con otros documentos

| Documento | Función |
|---|---|
| [`15-peer-review.md`](15-peer-review.md) | Metodología genérica de revisión por pares y regla normativa de convergencia. |
| [`13-pre-push-review.md`](13-pre-push-review.md) | La rutina que ejecuta cada revisor. |
| [`mimir-delegate/SKILL.md`](../../skills/mimir-delegate/SKILL.md) | Mecanismo de delegación a LLM secundario y contratos de adapters. |
| Backlog de ideas de los mantenedores (no publicado) | Trabajo futuro, como dossiers compactos y perfiles in-panel `git-capable`. |
