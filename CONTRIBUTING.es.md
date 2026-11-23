Ver también: [English](CONTRIBUTING.md)

# Contribuir a Mimir Lite

Gracias por considerar una contribución. Las contribuciones se aceptan bajo la [licencia MIT](LICENSE.md) del proyecto. El mismo cuidado aplica en todo momento: rigor técnico, trazabilidad y ningún dato real de KB o de cliente en ninguna parte del repositorio.

## Antes de empezar

- Leer primero [`README.es.md`](README.es.md) y [`AGENTS.md`](AGENTS.md), además de la documentación directamente relacionada con el cambio.
- Revisar [`docs/ideas/`](docs/ideas/) para ver ideas pendientes y enfoques ya descartados antes de reinvestigar un tema que puede estar ya evaluado.
- Nunca incluir credenciales, datos de clientes ni contenido de una KB real de GeneXus en un ejemplo, fixture o prueba. Usar el fixture sintético en `tests/fixtures/sample-kb/` como patrón de referencia para cualquier cosa que necesite forma de KB.
- Preferir cambios pequeños, locales y fáciles de revisar.

## Preparar el entorno

1. Clonar el repositorio.
2. Instalar `pwsh` 7.4+ (7.4.6+ en Linux y macOS) y Python 3.8+ (alcanza con la librería estándar), que se busca como `python3`, `python` o `py -3`. La CI corre en Windows y en Linux; macOS es de mejor esfuerzo (ver [Plataforma](README.es.md#plataforma) y [Diferencias conocidas entre plataformas](README.es.md#diferencias-conocidas-entre-plataformas)).
3. Ejecutar la suite de pruebas una vez para confirmar que el entorno quedó bien configurado:
   ```
   pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1
   ```

## Ejecutar pruebas y verificaciones

Se espera que un cambio pase las verificaciones de abajo en Windows y en Linux. `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools/Invoke-CiChecks.ps1` las ejecuta todas en orden, igual que la CI, y `pwsh -NoProfile -File tools/Invoke-LinuxTestsInDocker.ps1` ejecuta el mismo script en Linux dentro de un contenedor Docker local (Docker Desktop en Windows), sobre el HEAD commiteado. `pwsh -NoProfile -File tools/Invoke-Python38SmokeInDocker.ps1` ejecuta los motores de Python sobre un Python 3.8 real, la versión mínima, en un contenedor `python:3.8-slim`; conviene ejecutarlo cuando un cambio toca código Python, porque la verificación de parseo de Python solo rechaza sintaxis más nueva, no llamadas más nuevas a la biblioteca estándar. Para medir el build del índice sobre una KB grande sin contenido real, se genera un corpus sintético con `tools/benchmark/New-SyntheticKbCorpus.py` y se mide con `tools/benchmark/Measure-KbIntelligenceBuild.py`; los dos usan solo la biblioteca estándar, escriben solo bajo la carpeta temporal del sistema (o una carpeta indicada fuera del repositorio) e informan el tiempo total, el perfil, la memoria máxima, el tamaño del índice y los tiempos de las queries. Para un refactor que no debe cambiar el comportamiento, `tools/benchmark/Compare-KbIntelligenceBuilds.py` construye cada corpus con una copia base y una copia candidata de `skills/mimir-lite/scripts/`, compara todas las tablas del índice y las respuestas de un conjunto fijo de consultas, y sale con 1 ante cualquier diferencia. `pwsh -NoProfile -File tools/Invoke-StaticAnalysis.ps1` ejecuta un análisis estático consultivo con las herramientas de desarrollo opcionales ruff y PSScriptAnalyzer: los hallazgos nunca lo hacen fallar y una herramienta que no está instalada se omite. La CI (`.github/workflows/ci.yml`) ejecuta ese script en Windows y en Linux a pedido (Actions > CI > Run workflow) y con cada etiqueta de versión `v*`, no en cada push: los minutos de los runners alojados son limitados en el plan del repositorio, así que las verificaciones diarias se hacen en local. Una corrida disparada por una etiqueta empieza cuando la etiqueta ya está publicada, así que conviene ejecutar la CI a pedido sobre el commit de la versión antes de etiquetarlo. Son las únicas verificaciones que debe ejecutar quien contribuye.

| Comando | Qué hace |
|---|---|
| `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1` | Suite de pruebas completa (`-ThrottleLimit <n>` ejecuta n archivos a la vez, cada uno con su propio `TEMP`; 1 por defecto, y la CI sigue siendo secuencial; 2 es el valor probado) |
| `pwsh -NoProfile -File tools/Test-TextEncoding.ps1` | Verificación UTF-8 sin BOM, LF |
| `pwsh -NoProfile -File tools/Test-PsScriptsParse.ps1` | Verificación de parseo de PowerShell |
| `pwsh -NoProfile -File tools/Test-PyScriptsParse.ps1` | Verificación de parseo de Python |
| `pwsh -NoProfile -File tools/Test-MarkdownFences.ps1` | Verificación de bloques de código Markdown |
| `pwsh -NoProfile -File tools/Test-MarkdownLinks.ps1` | Verificación de enlaces Markdown / menciones sueltas |
| `pwsh -NoProfile -File tools/Test-ScriptInventory.ps1` | Completitud del inventario de scripts |
| `pwsh -NoProfile -File tools/Test-CodeLanguage.ps1` | Verificación de idioma del código (comentarios y mensajes en inglés) |

Además, quienes mantienen el proyecto siguen un flujo de revisión opcional antes de un push: la rutina pre-push de [`docs/process/13-pre-push-review.es.md`](docs/process/13-pre-push-review.es.md), con sus niveles reforzado y de revisión por pares. Es práctica de los mantenedores, no un requisito para quien contribuye; `tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson` está disponible si se quiere ejecutar su paso mecánico.

## Ramas y commits

- Trabajar en una rama de feature; no hacer commit directo a `main` salvo una corrección trivial.
- [Conventional Commits](https://www.conventionalcommits.org/), en inglés (ej.: `feat: add impact query for Business Component`, `fix: repoint stale wrapper path`).
- Sin líneas de atribución de IA en los mensajes de commit.
- Mantener cada commit enfocado en una unidad de trabajo coherente; las pruebas y la documentación de un cambio de comportamiento van en el mismo commit que el comportamiento, no en uno posterior.

## Desarrollo guiado por pruebas

Los cambios de comportamiento siguen TDD estricto: escribir o extender la prueba primero, observar que falla (RED) por la razón correcta, implementar el cambio (GREEN) y luego refactorizar con la prueba todavía en verde. No afirmar un paso RED/GREEN que no se haya observado realmente.

Una regla nueva del extractor lleva una prueba unitaria de Python para su función de parseo (cargar el motor con `tests/mimir-lite/_engine_loader.py`, como lo hace `tests/mimir-lite/TestBuildKbIntelligenceIndexParsingFunctions.py`) y una autoprueba de extremo a extremo, en lugar de varios casos que inician un proceso. Un extractor nuevo es un elemento de `EXTRACTOR_RECORDS` en `skills/mimir-lite/scripts/GeneXusKbIntelligenceCore.py`, su llamada en `EXTRACTOR_CALLS` de `Build-KbIntelligenceIndex.py` y su función; `main` ejecuta los elementos en orden.

Las pruebas de PowerShell cargan `tests/fixtures/AssertSupport.ps1` con dot-source para sus aserciones y no definen funciones `Assert*` locales: `tests/Test-LocalAssertGuardSelfTest.ps1` falla ante una nueva en `tests/` o `tools/`, salvo en los archivos listados en `tests/fixtures/local-assert-baseline.txt`. Cuando se modifica un archivo listado por otro motivo, se migra a las aserciones compartidas y se quita su entrada en el mismo cambio.

Para probar una interrupción o una superposición de la sincronización XPZ, la construcción del índice o una consulta, se usan los puntos de parada exclusivos de prueba en lugar de cronometrar una terminación: se define `MIMIR_TEST_STOP_AT` con un punto (`sync:after-mark-incomplete`, `sync:after-xml:<n>`, `sync:before-publish`, `build:before-publish` o `query:after-lock`) y `MIMIR_TEST_STOP_MODE` con `kill` (el proceso termina en el acto, sin limpieza) o `pause` (escribe `MIMIR_TEST_PAUSED <point>` en stderr y espera una línea en stdin mientras mantiene el bloqueo del corpus). `tests/mimir-lite/TestCorpusInterruptionAndOverlap.py` muestra ambos modos. Sin definir, los puntos de parada no hacen nada.

## Taxonomía de documentación

| Carpeta | Qué va ahí |
|---|---|
| `docs/adr/` | Registros de decisiones |
| `docs/ideas/` | Backlog curado de nuevas capacidades e ideas descartadas con su justificación |
| `docs/process/` | Métodos de trabajo del equipo (revisión pre-push, revisión reforzada, revisión por pares) |
| `docs/i18n/` | Política de traducción y glosario |

Al mover o renombrar un archivo, hacerlo en un commit propio, sin cambios de contenido, de modo que el historial de git siga al archivo.

## Política de idioma y traducciones

El inglés es el idioma canónico para el código, el contenido de las skills (`SKILL.md`, `workflows/`, `references/`) y la documentación humana de la raíz. La documentación humana y de la raíz también recibe una traducción al español (`<nombre>.es.md`). Ver [`docs/i18n/README.md`](docs/i18n/README.md) para la política de traducción y [`docs/i18n/glossary.md`](docs/i18n/glossary.md) para los mapeos de términos. Fijar o agregar un término del glosario antes de que aparezca traducido en cualquier otro lugar; los tipos de objeto y nombres de API de GeneXus nunca se traducen.

## Reportar un problema

Describir el problema observado, el comportamiento esperado, los pasos para reproducirlo (solo con datos saneados) y el script, skill o documento afectado. Abrir un issue en el rastreador de issues del repositorio con la plantilla de reporte de error o de solicitud de funcionalidad. Todo lo sensible (credenciales, datos de clientes, contenido real de KB, pasos explotables) se reporta en privado, como se describe en [`SECURITY.es.md`](SECURITY.es.md).

## Pull requests

Al abrir un cambio para revisión, describir: qué cambió y por qué, qué quedó explícitamente fuera de alcance, qué pruebas y verificaciones se ejecutaron (y su resultado), si `CHANGELOG.md` necesita una entrada (ver [`docs/process/13-pre-push-review.es.md`](docs/process/13-pre-push-review.es.md) §4) o por qué no aplica, y si hace falta actualizar la documentación. Mantener la descripción en inglés.
