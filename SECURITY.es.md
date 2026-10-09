Ver también: [English](SECURITY.md)

# Política de seguridad

Este repositorio contiene documentación, scripts y ejemplos metodológicos para leer y entender una Base de Conocimiento de GeneXus a partir de exportaciones XPZ/XML. Los reportes de seguridad deben proteger a las personas, los clientes, las KBs reales y los artefactos privados.

## Qué cuenta

Relevante para esta política:

- Una vulnerabilidad en un script o flujo de trabajo (por ejemplo, uno que pudiera escribir fuera de su alcance documentado, o que pudiera inducirse a una acción insegura contra una KB).
- Exposición accidental de credenciales, datos de clientes o artefactos de una KB real sin sanear, en cualquier parte de este repositorio (código, ejemplos, fixtures o documentación).
- Contenido real de una KB de GeneXus filtrado — nombres, GUIDs, código fuente o estructura — en un archivo versionado.
- Instrucciones que induzcan un cambio inseguro en una KB, base de datos o paquete XPZ.
- Una brecha que permita que una validación crítica de seguridad operativa devuelva un falso positivo.

Un reporte de bug común, un error de documentación sin impacto sensible o una sugerencia de mejora general pueden seguir el flujo normal de issues/pull requests en lugar de esta política.

## Datos enviados a servicios externos

Mimir Lite en sí no realiza llamadas de red. La skill opcional `mimir-delegate` puede enviar contenido de prompts, incluido contenido de la KB si el agente lo incluye, a CLIs de LLM externas (opencode y los proveedores con los que esté configurado, Codex, Claude Code, GitHub Copilot CLI, Gemini CLI, Antigravity CLI), y solo cuando un usuario pide una delegación o una revisión por pares. Su compuerta de confidencialidad (`Resolve-LlmDelegateAuthorization.ps1`) decide allow, ask o deny según la localidad del destino y una política por KB, pero quien juzga si un contenido es `public` o `kb-sensitive` es el agente, no el script. La compuerta es por lo tanto procedimental: no puede detectar contenido sensible que el agente etiquete como `public`. No usar la delegación con material que no esté permitido divulgar al proveedor de destino. El consentimiento para contenido `kb-sensitive` es por destino y por invocación, y un prompt enviado no se puede recuperar.

Ubicaciones escritas fuera del repositorio (lista completa en [`README.es.md`](README.es.md#delegación-y-archivos-escritos-fuera-del-repositorio)): `%LOCALAPPDATA%\mimir-delegate` en Windows, `~/.local/share/mimir-delegate` en Linux o, en macOS, normalmente `~/Library/Application Support/mimir-delegate`, con la ubicación de Linux como alternativa cuando esa carpeta no existe (manifiesto de capacidades, revisores preferidos, estado del circuit breaker), carpetas de trabajos en la carpeta temporal del sistema (`%TEMP%` en Windows) que contienen prompts y salidas delegados, el espacio de trabajo de KB que el flujo **setup** crea junto a la KB (con un `.claude/settings.json` opcional de Claude Code con reglas de permiso), los archivos de instrucciones globales de las herramientas de agente tras la confirmación y, al instalar, los directorios de skills de las herramientas de agente. Reportar por el canal privado indicado abajo un script que escriba en cualquier otro lugar o que deje prompts sensibles sin limpiar.

## Cómo reportar

- No abrir una issue pública con credenciales, nombres sensibles de clientes, contenido de KB real o pasos explotables.
- Reportar en privado mediante el reporte privado de vulnerabilidades de GitHub: abrir la pestaña **Security** del repositorio y elegir **Report a vulnerability**. El reporte solo lo ven quienes mantienen el proyecto hasta que decidan cómo divulgarlo. Hacerlo antes de publicar cualquier detalle sensible.
- No enviar credenciales, un XPZ real ni contenido de KB real por ningún canal sin un acuerdo previo sobre cómo se va a manejar.

## Qué incluir

Cuando sea posible, incluir: el problema observado, el script/skill/documento afectado, una reproducción mínima solo con datos saneados y el impacto potencial. No incluir el artefacto sensible real en el reporte inicial — describirlo y ofrecer compartirlo por un canal privado acordado si realmente hace falta para el triaje.
