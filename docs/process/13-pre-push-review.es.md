# 13 — Rutina de revisión pre-push

> **Flujo de mantenedores.** Este documento describe el flujo de revisión de quienes mantienen este repositorio. Es opcional para quienes contribuyen: las únicas verificaciones que debe pasar una contribución son las verificaciones mecánicas que ejecuta la CI, listadas en [`CONTRIBUTING.es.md`](../../CONTRIBUTING.es.md).

## Función de este documento

Esta es la rutina pre-push autoritativa de este repositorio. `AGENTS.md` apunta aquí; agentes y mantenedores deben seguir este documento antes de considerar que un push está listo.

Para el nivel reforzado y opcional —panel multi-modelo diverso y regla de convergencia en la que el estado final es push-ready solo cuando todo el panel válido informa que no hay brechas— consulte [`14-reinforced-pre-push-review.md`](14-reinforced-pre-push-review.md).

## Alcance

La rutina pre-push es análisis, búsqueda de coherencia e informe al usuario. No autoriza ediciones, commits, staging ni push. Si la rutina encuentra brechas, el agente las informa y puede proponer un diff o una lista de cambios, pero escribe solo después de aprobación explícita del usuario posterior al informe. Una sola aprobación explícita puede cubrir todo el conjunto propuesto, salvo que el usuario solicite aprobación item por item; la misma excepción rige para la revisión reforzada.

Esta rutina se aplica al **repositorio Mimir Lite**. No es una rutina de validación de un espacio de trabajo de KB de GeneXus. Mimir Lite lee exportaciones XPZ/XML e índices derivados; generar, construir, empaquetar o importar XPZ y los flujos MSBuild quedan fuera de alcance (ver [`README.es.md`](../../README.es.md#fuera-de-alcance)), y la mecánica de pre-push de este documento nunca los trata como rutas vigentes.

## Paso mecánico inicial

Ejecute el orquestador desde la raíz del repositorio con PowerShell 7.4+ (7.4.6+ en Linux y macOS):

```powershell
pwsh -NoProfile -File tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson
```

El script mecánico usa `origin/main` como `-BaseRef` predeterminado; commits pendientes, conteo, archivos cambiados y `git diff --check` usan el mismo intervalo efectivo, `BaseRef..HEAD`. Si falta el `origin/main` predeterminado y existe `main` local, usa `main` como fallback y lo registra; un `-BaseRef` explícito inexistente falla. El builder del dossier tiene su propio `-BaseRef` predeterminado `origin/main` y no aplica ese fallback: cuando la verificación mecánica haya elegido otra base, pase el mismo `-BaseRef` explícito y válido a ambos, o las secciones A y B describirán intervalos distintos.

`git diff --check` se ejecuta sobre ese mismo intervalo y todo diagnóstico hace fallar la verificación de espacios en blanco; no se suprime nada, y los informes JSON y de texto conservan el código de salida bruto de Git y los diagnósticos restantes. Algunos archivos de referencia contienen bloques de payload de plantillas sanitizadas dentro de bloques cercados con espacios finales a propósito. Un intervalo que no toque esas líneas no se ve afectado (con `commitsAhead=0` no hay diff del intervalo). Cuando un cambio deba tocarlas, el fallo de espacios en blanco es esperable: confirme que los bytes del payload son intencionales y dígalo en el informe de revisión en lugar de normalizar el payload.

El orquestador delega el parse PowerShell a [`tools/Test-PsScriptsParse.ps1`](../../tools/Test-PsScriptsParse.ps1), que escanea todos los `*.ps1` bajo `skills/`, `tools/` y `tests/`, además de cada `*.example.ps1`. Delega sintaxis Python a [`tools/Test-PyScriptsParse.ps1`](../../tools/Test-PyScriptsParse.ps1), que escanea `*.py` bajo `skills/`, `tools/` y `tests/` con `ast.parse` y no escribe bytecode. Estas verificaciones no reemplazan la fase semántica.

### Formas canónicas de invocación

Use una de estas formas:

- Desde la raíz del repositorio: `pwsh -NoProfile -File tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson`
- Desde otro directorio: `pwsh -NoProfile -File "<ruta-absoluta-del-repo>/tools/Invoke-PrePushMechanicalChecks.ps1" -AsJson`

### Límites del paso mecánico

- **Parse PowerShell** es de todo el repositorio sobre `skills/`, `tools/`, `tests/` y `*.example.ps1`; no se limita al diff del intervalo.
- **Parse Python** usa `ast.parse`; la validación no debe depender de escribir `__pycache__`.
- **Working tree** se informa, pero el intervalo solo cubre cambios commiteados. Con `commitsAhead=0`, no hay diff del intervalo ni carga de `git diff --check`.
- **`exit 0` no autoriza push.** Lea `PUSH_READINESS` / `pushReadiness`. Si es `blocked`, el push queda prohibido hasta integrar el remoto.
- **`pushReadiness=blocked`** vuelve diagnóstico el diff del intervalo, pero la fase semántica sobre los commits locales pendientes sigue siendo obligatoria.
- **Verificaciones consultivas** señalan riesgos candidatos; no reemplazan la fase semántica ni autorizan cerrar la revisión por sí solas.

### Referencia remota fresca

Cuando el usuario quiera comparar con el remoto actual, ejecute `git fetch origin` antes del paso mecánico. Una referencia ausente y una `origin/main` local desactualizada son casos distintos: el script diagnostica la primera, pero una referencia desactualizada puede distorsionar lo pendiente.

### Remoto adelantado (`commitsBehind`)

Cuando `commitsBehind > 0`, `BaseRef..HEAD` ya no significa limpiamente “solo lo que falta enviar”. El orquestador emite `pushReadiness=blocked` sin tratar parse o whitespace como fallidos. La revisión puede continuar para informar coherencia, pero el push queda prohibido hasta que el remoto sea integrado con una acción aprobada por el usuario, como rebase o merge.

## Modo asistido por dossier para revisores semantic-only

En el nivel reforzado ([`14`](14-reinforced-pre-push-review.md)), algunos revisores no pueden ejecutar comandos de shell. El builder [`tools/Build-PrePushReviewDossier.ps1`](../../tools/Build-PrePushReviewDossier.ps1) tiene capacidad git y construye el paquete; es distinto del revisor `semantic-only`, que lo recibe y realiza solo la fase semántica read-only. Un revisor `git-capable` ejecuta la rutina completa y reproduce la Sección A por su cuenta; un panel válido conserva al menos uno. Los revisores `semantic-only` no ejecutan el paso mecánico.

El dossier contiene:

- **Sección A — datos de git sin procesar (hecho):** `rev-parse HEAD`, `log BaseRef..HEAD`, `diff BaseRef..HEAD` y `status --porcelain`.
- **Sección B — diagnóstico mecánico, no fuente de verdad:** el contenedor JSON completo de `Invoke-PrePushMechanicalChecks.ps1 -AsJson`, bajo el encabezado literal del script `=== SECTION B — ORCHESTRATOR MECHANICAL DIAGNOSTIC (candidates to verify, NOT truth) ===`. El script mecánico es dueño de la política `pushReadiness`; el builder referencia ese diagnóstico, no reimplementa la política.
- **Sentinelas:** líneas finales `HEAD:` y `END_DOSSIER sha256=`. El SHA-256 cubre el cuerpo UTF-8 sin BOM normalizado a LF, excluyendo las sentinelas. Una respuesta on-task sin eco de sentinelas es `responded` + `noEchoSentinel`, no `noResponse`.

Si el JSON mecánico no está disponible o no se puede parsear, el dossier aún puede estar listo con `mechanicalStatus=failed`; en ese modo degradado, el builder solo reafirma el `commitsBehind` bruto desde git y deja `pushReadiness` / `intervalDiffDiagnosticOnly` como desconocidos.

El despacho `semantic-only` se bloquea cuando el working tree está sucio: esos revisores leen el árbol vivo pero no pueden distinguir contenido commiteado de cambios sin commit. El orquestador informa las rutas sucias y pide commit o stash antes de despacharlos. Los revisores `git-capable` pueden continuar porque pueden inspeccionar git por sí mismos.

Transporte y capacidad son ejes separados. Los adapters `stdin-dossier-capable`, como opencode y Claude Code, pueden recibir dossiers grandes por stdin. Los adapters `argv-limited`, como Copilot, Gemini y Antigravity, tienen guard alrededor de 30000 caracteres; por encima del límite, el revisor se omite como `unavailable` + `dossier-too-large`, nunca con truncado silencioso. Para Antigravity `public-review`, primero se ejecuta la compuerta de confidencialidad: `gateAsk` y `gateDeny` conservan sus resultados; solo `allow` para `kb-sensitive` se rechaza después por la postura fija public-review como `unavailable` + `refusedSensitivity`. El adapter no reclasifica el payload. El recibo public-review registra versión CLI, workspace, redirección del entorno y limpieza; el keyring global del sistema no queda aislado y esa limitación debe permanecer explícita.

Un panel reforzado válido sigue necesitando al menos un revisor `git-capable` que reproduzca la Sección A de forma independiente; consulte [`14`](14-reinforced-pre-push-review.md).

## Fase semántica — por frente de trabajo cambiada

### 1. Inventario de la frente de trabajo

Enumere términos, scripts, wrappers, parámetros, estados, rutas, tokens públicos y reglas operativas introducidos o modificados por la frente de trabajo.

### 2. Búsqueda en el repositorio

Busque esos términos en todo el repositorio. No se detenga en el primer archivo.

Cuando una frente de trabajo cambie versión, firma, código de evidencia, regla de extracción, nombre de estado, parámetro, alias, flag, opción, backend, verificación, exit code o cualquier conjunto enumerado, busque tanto los términos antiguos como los nuevos. Buscar solo el término nuevo no detecta enumeraciones cerradas obsoletas que listan solo los miembros anteriores.

[`tools/Test-PrePushNewTokenPropagation.ps1`](../../tools/Test-PrePushNewTokenPropagation.ps1) ayuda cuando un hunk co-localiza un token introducido con un token antiguo. Emite candidatos por `mentionClass`:

- Los candidatos `prose` pueden recibir una justificación colectiva cuando la omisión es intencionalmente no contractual.
- Los candidatos `param-list-item`, `param-table-cell` y `command-example` requieren un registro item por item: archivo:línea, lista/tabla/ejemplo gemelo, y `gap` o `justified`. El informe debe incluir el registro no-prosa completo; no se detenga al encontrar una brecha ni agrupe elementos bajo una justificación de prosa. Complételo antes de concluir siempre que haya candidatos no-prosa.

El orquestador proyecta `candidateCount`, `classCounts`, `truncated`, `truncatedProseCount` y `nonProseVerdictRequired`. `-MaxFindings` limita solo `prose`; los candidatos no-prosa nunca se truncan. Si se truncó prosa, `truncatedProseCount` informa el número descartado y el diagnóstico mecánico del dossier advierte que la lista de prosa no es exhaustiva (la salida de texto usa `NEW_TOKEN_PROPAGATION_PROSE_TRUNCATED=`). `pairsConsidered` registra pares de tokens, no hallazgos omitidos. Cuando los candidatos no-prosa superan el umbral documentado por el orquestador (> 5), se recomienda una segunda pasada semántica por un modelo distinto antes de cerrar el veredicto.

Las enumeraciones cerradas también tienen verificaciones consultivas:

- [`tools/Test-PrePushGateEnumerationParity.ps1`](../../tools/Test-PrePushGateEnumerationParity.ps1) deriva el conjunto actual de verificaciones consultivas desde el orquestador.
- [`tools/Test-PrePushBackendEnumerationParity.ps1`](../../tools/Test-PrePushBackendEnumerationParity.ps1) deriva el conjunto de backends de delegación desde `$AdapterScript` en [`skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1`](../../skills/mimir-delegate/scripts/Invoke-LlmDelegatePanelDispatch.ps1).

Use `<!-- backend-parity: ignore -->` solo para subconjuntos intencionales, fechados por fecha o por eje, como una medición, registro de incidente o comparación de dos backends específicos. No lo use en contratos vivos como ramas del dispatcher, matrices de capacidad, conjuntos de verificaciones o enumeraciones de adapters. Ante la duda, haga triaje de la advertencia en lugar de silenciarla.

### 3. Comparación documental

Compare la documentación afectada con documentos y código relacionados, incluyendo:

- skills y workflows relacionados, también documentos transversales que describen un script compartido aunque estén fuera del diff;
- [`README.md`](../../README.md);
- [`skills/mimir-lite/references/02-operational-rules.md`](../../skills/mimir-lite/references/02-operational-rules.md);
- [`skills/mimir-lite/references/08-agent-guide.md`](../../skills/mimir-lite/references/08-agent-guide.md);
- [`skills/mimir-lite/references/09-script-inventory.md`](../../skills/mimir-lite/references/09-script-inventory.md) cuando cambie un script compartido, contrato metodológico, skill, nombre operativo, estado, parámetro, wrapper o ítem de trazabilidad pública. Es un índice de punteros (una línea por script: función, dueño normativo, puntero de validación); compruebe que los punteros sean correctos y que el resumen de función siga siendo válido, no que duplique el contrato detallado del dueño;
- ejemplos canónicos `*.example.ps1` bajo workflows afectados, hoy principalmente [`skills/mimir-lite/workflows/setup/examples/`](../../skills/mimir-lite/workflows/setup/examples/);
- motores compartidos bajo `skills/mimir-lite/scripts/`, `skills/mimir-delegate/scripts/` y herramientas bajo `tools/`.

[`tools/Test-PrePushSharedScriptSkillCoverage.ps1`](../../tools/Test-PrePushSharedScriptSkillCoverage.ps1) lista documentos SKILL/workflow/checklist que citan un script compartido cambiado pero no están en el diff. Es consultivo: compare el contrato o justifique por qué el cambio no afecta ese documento.

Cuando cambia una regla operativa compartida, `02-operational-rules.md` debe contener la regla o el informe debe justificar su ausencia. Cobertura solo en `08`, `09`, una skill o `README` no alcanza.

Para motores compartidos consumidos por wrappers locales u otros consumidores, un cambio incompatible de salida o consumo debe ir acompañado por detección de consumidores desactualizados en el workflow de auditoría. Una nota en changelog no basta si existe una verificación de drift y sigue ciega.

Antes de informar que un término, self-test, script, regla o evidencia está ausente de un documento, reconcilie todas las búsquedas y fragmentos ya recopilados. Si hay conflicto, vuelva a abrir el archivo objetivo en el punto citado antes de confirmar la brecha.

### 4. `CHANGELOG.md`

Para cada frente de trabajo cambiado, decida si hay comportamiento visible para usuarios, cambio de contrato operativo, cambio público de script/skill/gobernanza/seguridad/contribución, remoción, rename o incompatibilidad relevante. Si lo hay, `CHANGELOG.md` necesita una entrada en `Unreleased` antes de la publicación. Si no se actualiza, el informe pre-push debe clasificar explícitamente la flag del changelog como descartada y justificar la omisión.

### 5. Paridad motor/documento

Cuando la documentación nombre un motor, parámetro, exit code, estado o regla, lea el código `.ps1` / `.py` citado. Si el documento cita dos artefactos en una regla, ambos deben existir en el motor o wrapper. Si un motor par toma la misma decisión, debe exponer el mismo contrato salvo asimetría justificada en el informe.

Señales objetivas de alerta:

- docs que prometen un catálogo efectivo mientras `Query-KbIntelligenceIndex` no resuelve overrides de catálogo;
- `Build-KbIntelligenceIndex.ps1` expone `-KbWorkspaceRoot` mientras `Query-KbIntelligenceIndex.ps1` carece de equivalente cuando la misma decisión lo requiere;
- cambios de versión de firma del extractor con docs operativas obsoletas;
- cambios de reglas de extracción del índice sin que `02-operational-rules.md` explique qué materializa el índice y qué sigue requiriendo lectura XML.

Cuando una frente de trabajo introduce un bloqueo, rechazo, validación, `Stop-WithReason`, `BLOCK: ...`, `ValidateSet`, `ValidateRange` o predicado similar, enumere explícitamente los ejes vecinos y dé un veredicto para cada uno: cerrado, intencionalmente abierto con justificación o residual. Ejes comunes: escritor vs lector, parámetro alternativo que llega al mismo estado, grafía alternativa de la misma clave, titular vs enlace de `fallbackChain`, y modo `public` vs `kb-sensitive`.

### 6. Regla para skills largas y satélites

Al alinear un nombre o contrato en una skill o workflow largo, escanee los satélites que el propio archivo indica cargar antes de considerar cerrada la frente de trabajo. Los tres cortes son checklist final/verificaciones de cierre, flujo operativo y captura de resultado, e inventario de scripts/contratos.

### 7. Checklist de brechas

Verifique:

- docs antiguas que contradicen el nuevo comportamiento;
- ejemplos canónicos obsoletos;
- scripts cuyo contrato diverge de su descripción;
- checklists que prometen validación que el script no ejecuta;
- docs satélite obsoletas;
- una herramienta nueva documentada en un lugar pero ausente en skills/workflows correlacionados;
- trazabilidad obsoleta o demasiado agregada en `09-script-inventory.md`;
- un nuevo contrato documentado sin cobertura de self-test, o un informe de que esa cobertura falta;
- un nuevo bloqueo/validación sin el veredicto por eje vecino requerido;
- cambios de impacto público sin entrada en `CHANGELOG.md` ni justificación explícita de omisión.

Use el reporte de brechas candidatas para huecos de trazabilidad adyacentes y preexistentes: separe atribución (“no fue introducido por esta frente”) de mérito (“puede valer la pena registrarlo”). No incline automáticamente al usuario hacia el descarte.

### 8. Informe antes de editar

La fase semántica produce un informe con las brechas confirmadas (o su ausencia), las flags descartadas con justificación y las áreas no cubiertas por la búsqueda, haya o no brechas. Entre ese informe y cualquier edición, commit, staging o push hay un punto obligatorio de validación humana. Si se encuentran brechas:

1. Informe las correcciones propuestas.
2. Deténgase. No edite archivos.
3. Espere aprobación explícita para los cambios propuestos.
4. Solo entonces aplique correcciones.

No existe excepción de “lo bastante pequeño para corregir sin preguntar” dentro de la revisión pre-push.

### 9. Veredicto

Termine con exactamente una línea fija:

`VERDICT: no confirmed gaps`

o

`VERDICT: N confirmed gap(s)`

Advertencias, flags descartados y áreas no cubiertas no cuentan como brechas confirmadas. Si falta el veredicto, la revisión pre-push está incompleta.

## Conclusión

La rutina pre-push no está completa hasta que la fase semántica haya sido ejecutada e informada, aunque `git diff --check`, parse checks y tests locales estén limpios. No trate el paso mecánico como autorización de push, especialmente cuando `PUSH_READINESS=blocked`.

## Patrones de búsqueda por tipo de frente de trabajo

### Catálogo efectivo / KbIntelligence

- Términos positivos en los motores citados: `merge`, `override`, `KbWorkspaceRoot`, `catalog-override-path`, `GeneXusObjectTypeCatalogCore`, `resolve_effective`.
- Señal negativa: una ruta fija a `gx-object-type-catalog.json` en el mismo flujo que aplica `queryableByKbIntelligence` o un bloqueo semántico, sin merge/override.

## Scripts del orquestador

| Script | Función |
|---|---|
| [`tools/Invoke-PrePushMechanicalChecks.ps1`](../../tools/Invoke-PrePushMechanicalChecks.ps1) | Orquestador mecánico: contexto git, compuertas de parse, `git diff --check`, advertencias consultivas y push readiness. |
| [`tools/Build-PrePushReviewDossier.ps1`](../../tools/Build-PrePushReviewDossier.ps1) | Construye el dossier de git bruto + diagnóstico mecánico para revisores reforzados `semantic-only`. |
| [`tools/Test-PsScriptsParse.ps1`](../../tools/Test-PsScriptsParse.ps1) | Parsea archivos PowerShell bajo `skills/`, `tools/`, `tests/`, más `*.example.ps1`. |
| [`tools/Test-PyScriptsParse.ps1`](../../tools/Test-PyScriptsParse.ps1) | Parsea archivos Python bajo `skills/`, `tools/` y `tests/` con `ast.parse`, sin bytecode. |
| [`tools/Test-PrePushTraceabilityCoverage.ps1`](../../tools/Test-PrePushTraceabilityCoverage.ps1) | Candidatos consultivos de trazabilidad y paridad motor/doc, incluidos riesgos del índice de punteros `09-script-inventory.md`. |
| [`tools/Test-GeneXusUnexpectedCharacter.ps1`](../../tools/Test-GeneXusUnexpectedCharacter.ps1) | Detección consultiva de Unicode inesperado en líneas añadidas `.md` / `.ps1`. |
| [`tools/Test-PrePushNewTokenPropagation.ps1`](../../tools/Test-PrePushNewTokenPropagation.ps1) | Candidatos consultivos de propagación de términos nuevos a partir de transiciones co-localizadas en el diff. |
| [`tools/Test-PrePushSharedScriptSkillCoverage.ps1`](../../tools/Test-PrePushSharedScriptSkillCoverage.ps1) | Candidatos consultivos de scripts compartidos cuyos documentos de skill/workflow no fueron tocados. |
| [`tools/Test-PrePushGateEnumerationParity.ps1`](../../tools/Test-PrePushGateEnumerationParity.ps1) | Paridad consultiva de enumeración de verificaciones frente a las verificaciones consultivas actuales del orquestador. |
| [`tools/Test-PrePushBackendEnumerationParity.ps1`](../../tools/Test-PrePushBackendEnumerationParity.ps1) | Paridad consultiva de enumeración de backends frente a `$AdapterScript` en el dispatcher del panel. |

## Reflejos en otros documentos

- [`skills/mimir-lite/references/08-agent-guide.md`](../../skills/mimir-lite/references/08-agent-guide.md): resumen operativo para agentes. En caso de divergencia, este archivo (`13`) prevalece para la rutina pre-push completa.
- [`skills/mimir-lite/references/09-script-inventory.md`](../../skills/mimir-lite/references/09-script-inventory.md): inventario de scripts y punteros de dueño para los scripts anteriores.
