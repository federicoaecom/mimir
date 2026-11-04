Ver también: [English](2026-10-24-codex-public-samples.md)

# Codex CLI: validación con ejemplos públicos

El 24 de octubre de 2026, sesiones interactivas de Codex CLI en Windows completaron los flujos **setup**, **sync** y **find** de Mimir Lite con los ejemplos públicos Kafka y MyCinema. Es uso observado de la skill, no solo una auditoría de registro. No valida todas las integraciones de Codex, plataformas o exportaciones de GeneXus.

## Alcance y método

- Checkout de la skill: `4141e28dae2bf1edf69ed794acb86cb6f4bc98df`.
- Entradas: `KafkaSampleU12.xpz` (80.148 bytes) y `MyCinema.xpz` (2.920.032 bytes). Antes de usarlas, las copias se compararon mediante SHA-256 con las entradas de las pruebas existentes.
- Cada ejemplo usó un espacio de trabajo de KB nuevo, solo con XPZ, una junction `.agents/skills/mimir-lite` por proyecto y ningún corpus ni índice previamente materializado. El checkout de la skill permaneció fuera de los espacios de trabajo.
- Se distinguió el descubrimiento automático de la lectura manual de `SKILL.md`. El setup incluyó un análisis previo de la exportación y la confirmación del nombre de la KB por el usuario antes de crear la estructura. La exportación de MyCinema identifica su KB de origen como `TestAdvamced`; no se sustituyó esa identidad por el nombre público del ejemplo.
- Los scripts oficiales materializaron XML y reconstruyeron el índice derivado. Las sesiones informaron auditorías operacionales y `GATE_OK`, y volvieron a ejecutar la compuerta antes de las consultas acotadas de **find** y las lecturas de XML seleccionados.
- Otra sesión observadora de Codex leyó las conversaciones de las pruebas, inspeccionó los informes persistidos de materialización e índice y contrastó los fragmentos XML citados abajo. No volvió a ejecutar de forma independiente las compuertas operacionales.
- Solo se seleccionó Mimir Lite. No se usó un panel de `mimir-delegate` y esto no fue una revisión por pares. No se inicializó un repositorio Git en ninguno de los espacios de trabajo.

## Resultados observados

| Verificación | Kafka | MyCinema |
|---|---|---|
| Descubrimiento automático de la skill | Confirmado en el inventario de skills inyectado en la sesión | Informado por la sesión de prueba mediante su enlace por proyecto |
| Primera materialización | 8 objetos; 0 atributos | 90 objetos y 37 atributos |
| Archivos XML creados | 8 | 127 |
| Discrepancias de materialización / advertencias | 0 / 0 | 0 / 0 |
| Elementos indexados / relaciones | 8 / 25 | 127 / 235 |
| Semántica del inventario del índice | `OK` | `OK` |
| Estado operacional informado por la sesión | `materialized_and_index_validated` | `materialized_and_index_validated` |
| Nueva compuerta antes de **find** | `GATE_OK` informado por la sesión | `GATE_OK` registrado en la salida de herramientas |

El recuento del índice incluye atributos; el valor 127 de MyCinema no afirma que la exportación tenga 127 objetos sin contar atributos.

## Evidencia funcional

**Kafka:** la sesión identificó tres Procedures, cuatro ExternalObjects y un PackagedModule, sin inventar Transactions ni una interfaz de negocio. Siguió `ProducerTest → PrintResponse` mediante `what-uses` y `show-evidence`. La sesión observadora contrastó `KbObjectsXml/Procedure/ProducerTest.xml:11–16` (producción de mensajes, colección de respuestas y llamada) y `KbObjectsXml/Procedure/PrintResponse.xml:4–7,15` (procesamiento de la colección y parámetro de entrada). Los candidatos de autoría humana se presentaron como inferencia, no como algo probado por un indicador de objeto no generado.

**MyCinema:** la sesión enumeró 9 Transactions, 5 Procedures y 2 WebPanels sin un filtro de generación. Explicó la Transaction `Movie` y siguió `CheckMovieActors → IsStarring` mediante el índice. La sesión observadora contrastó la llamada en `KbObjectsXml/Procedure/CheckMovieActors.xml:4–11` y la lógica de coincidencia del procedimiento invocado en `KbObjectsXml/Procedure/IsStarring.xml:4–17`.

Para `MovieYear`, la sesión usó `attribute-info` antes de leer XML y no inventó un tipo ni una longitud ausentes de la exportación. La sesión observadora contrastó `KbObjectsXml/Attribute/MovieYear.xml:15`, su uso estructural en `KbObjectsXml/Transaction/Movie.xml:8` y la asignación en `KbObjectsXml/DataProvider/Movie_DataProvider.xml:8`. La respuesta declaró cobertura incompleta de `attribute_references`: los dos consumidores devueltos no son necesariamente todos los consumidores, y una asignación en un DataProvider no prueba por sí sola una escritura en la base de datos.

Las rutas XML anteriores son localizadores de evidencia dentro de los espacios de trabajo generados, no archivos del repositorio. Este registro no publica conversaciones locales, informes ni exportaciones; resume lo inspeccionado sin enlazar notas de trabajo privadas.

## Problemas de entorno y límites

- El arranque inicial del sandbox falló al actualizar permisos del sistema de archivos en un espacio de trabajo creado por la cuenta del sandbox. Las pruebas exitosas usaron espacios nuevos creados desde la terminal de quien mantiene el proyecto. No se desactivó el sandbox ni se cambiaron permisos manualmente para sortear el problema.
- PowerShell 7.6.8 de Microsoft Store funcionaba en la terminal de quien mantiene el proyecto, pero inicialmente no se podía ejecutar desde el sandbox. Se recomendó una instalación MSI oficial; los comandos posteriores de los flujos se ejecutaron correctamente. La sesión observadora no estableció el ejecutable exacto seleccionado en esos comandos exitosos, por lo que esto no prueba que instalar el MSI resuelva universalmente el problema.
- El informe de materialización de Kafka registra la extracción en el directorio temporal del sistema del usuario, fuera de su espacio de trabajo. **No** se validaron escrituras temporales limitadas al espacio de trabajo en esa ejecución.
- Antes de ejecutar MyCinema, se configuraron `TEMP`, `TMP` y `TMPDIR` con `workspace/Temp`. Su informe registra la extracción allí; después se eliminó el directorio extraído. Esto confirma esa ubicación y su limpieza, no el aislamiento del sistema de archivos de todo el entorno.
- No se ejecutaron objetos de negocio GeneXus, servicios Kafka, builds, importaciones ni generación de objetos. No se ejecutó una verificación adicional `FullSnapshot`.
- Estas ejecuciones positivas con ejemplos públicos no establecen cobertura exhaustiva del extractor, manejo de casos de fallo, una nueva prueba de extremo a extremo de la extensión de IDE o la aplicación de Codex, ni soporte observado en Linux/macOS.

## Conclusión

Los dos casos aportan evidencia empírica de Codex CLI en Windows para el descubrimiento automático de la skill y el flujo setup → sync → compuerta → consulta al índice → lectura de XML seleccionados. Las condiciones del entorno y los límites de cobertura forman parte de esa conclusión; el registro por sí solo, o una compuerta aprobada por sí sola, no demostrarían el mismo resultado.
