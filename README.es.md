Ver también: [English](README.md)

<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/brand/mimir-lockup-dark.svg">
    <img src="docs/brand/mimir-lockup.svg" alt="Mimir Lite" height="72">
  </picture>
</h1>

Mimir Lite es una skill de agente que lee y entiende una Base de Conocimiento (KB) de GeneXus a partir de sus exportaciones XPZ/XML: sincroniza una exportación XPZ hacia un corpus XML y un índice derivado, ayuda a un agente a encontrar objetos y sus dependencias a través de ese índice, lee y clasifica el XML de objetos individuales, y genera documentación en Markdown. Nunca genera, construye ni importa objetos de GeneXus.

## Estado

Versión actual: `0.5.0`; la primera versión pública fue `0.1.0` (ver [`CHANGELOG.md`](CHANGELOG.md)). Distribuido bajo la [licencia MIT](LICENSE.md); los autores figuran en [`AUTHORS.md`](AUTHORS.md).

## Soporte

Funciona en Windows 10/11 y en Linux, ambos probados en la CI, con PowerShell 7.4+ (7.4.6+ en Linux y macOS) y Python 3.8+; macOS es de mejor esfuerzo.

| Plataforma o herramienta | Estado | Carpeta de skills | Notas |
|---|---|---|---|
| Windows 10/11 | Probado | — | La CI corre en `windows-latest`; los scripts se ejecutan desde cualquier shell mediante `pwsh -NoProfile -File` |
| Linux | Probado (CI) | — | La CI corre en `ubuntu-latest`; requiere PowerShell 7.4.6+; ver [Diferencias conocidas entre plataformas](#diferencias-conocidas-entre-plataformas) |
| macOS | Mejor esfuerzo | — | Los mismos caminos de código que en Linux, sin ejecutarse en la CI; requiere PowerShell 7.4.6+ |
| Claude Code (CLI, extensión de VS Code, escritorio) | Probado | `~/.claude/skills` | Una carpeta compartida por las tres variantes; el flujo **setup** puede escribir reglas de permiso por prefijo de carpeta |
| Codex (CLI, extensión de IDE, aplicación) | Probado | `~/.agents/skills` o `~/.codex/skills` | |
| Cursor | Auditado | `~/.cursor/skills` | Cursor también lee `~/.agents/skills`, pero la auditoría pasa solo con un enlace en `~/.cursor/skills` |
| OpenCode | Auditado | `~/.config/opencode/skills` o `~/.agents/skills` | |
| Antigravity (IDE, CLI) | Auditado | `~/.gemini/config/skills` (IDE), `~/.agents/skills` (CLI) | |
| Pi, GitHub Copilot, Gemini CLI | Se espera que funcione, sin probar | `~/.agents/skills` | Auditar con `-AdditionalSkillsRoot .agents/skills` |
| Backends de `mimir-delegate` | Probado en Windows; Linux en la CI con CLIs simuladas | — | Maneja las CLIs listadas en [Delegación](#delegación-y-archivos-escritos-fuera-del-repositorio); quien mantiene el proyecto ejecuta las CLIs reales en Windows; ver [Diferencias conocidas entre plataformas](#diferencias-conocidas-entre-plataformas) |

**Probado** significa que quien mantiene el proyecto usa la skill con esa herramienta en Windows. Para una plataforma, **Probado (CI)** significa que la CI ejecuta allí la suite de pruebas completa y las verificaciones; **Mejor esfuerzo** significa los mismos caminos de código, sin ejecutar nada allí. **Auditado** significa que el flujo **install** ([`install.md`](skills/mimir-lite/workflows/install.md)) verifica el registro de la herramienta, pero no se informa como probada. Una copia de la carpeta de la skill no está soportada: queda desactualizada después de `git pull`, y la auditoría no puede distinguir una copia desactualizada de una al día; usar un enlace simbólico o una junction.

### Versiones de GeneXus

| Versión de GeneXus | Estado | Evidencia |
|---|---|---|
| GeneXus 18 | Probado | El catálogo de tipos de objeto y las referencias de lectura salen de exportaciones reales de GeneXus 18 (upgrades 9 y 13) |
| GeneXus 9 | Probado | Su formato `ExportFile` se detecta y se sincroniza sin configuración adicional (ver [exportaciones heredadas](skills/mimir-lite/workflows/sync.md#legacy-exports-genexus-9)); 11 de los 12 elementos conocidos se confirmaron en una exportación real |
| GeneXus 15 a 17 | Probado con ejemplos públicos | Exportaciones públicas de training y de la wiki (cabecera de exportación 4.0) se sincronizan, se indexan y responden consultas; corridas completas con un agente (instalación, preparación, sincronización, preguntas) pasaron sobre un ejemplo de GeneXus 15 y uno de GeneXus 17 |
| GeneXus X Evolution 2 y 3 | Probado con ejemplos públicos | Exportaciones públicas de la wiki (cabeceras de exportación 3.1 y 3.3) se sincronizan, se indexan y responden consultas; una corrida completa con un agente pasó sobre un ejemplo de X Evolution 3 |
| GeneXus 8 y anteriores, X, X Evolution 1, GeneXus Next | Desconocido | No se leyó ninguna exportación |

Un tipo de objeto que la skill no conoce detiene la sincronización antes de escribir nada; la skill no lo adivina. Una exportación que mezcla el formato de GeneXus 9 con el moderno se rechaza de la misma forma.

Las llamadas hechas desde objetos móviles (paneles de Smart Devices y Native Mobile y su Work With, el objeto Offline Database) y desde los diagramas de procesos de negocio de GXflow todavía no se indexan: una respuesta de "quién usa" puede omitir esos invocadores, y lo advierte cuando la KB contiene esos objetos. Para un atributo se indexan sus relaciones estructurales (niveles de Transaction, claves e índices de Table), sus usos en los grids, filtros, órdenes, vistas y condiciones de filtro de los objetos WorkWithForWeb, y sus lecturas y escrituras en el código de los objetos Procedure (Source y reglas), WebPanel y Transaction (reglas y eventos) y DataProvider (Source y reglas); una escritura se informa solo donde la asignación no es ambigua (dentro de bloques `for each` y `new`, reglas de asignación de Transaction e ítems de un DataProvider cuya salida es una Transaction), las demás asignaciones se informan como lecturas, y sus usos en los títulos, parámetros, condiciones de pestaña y código de WorkWithForWeb, en condiciones, layouts, WebForms y miembros de Business Component, y en las fórmulas, grids y filtros de otros objetos no se indexan, y una respuesta de "quién usa" sobre un atributo lo advierte.

## Usarlo con un agente de IA

### Para el usuario

Darle al agente la URL del repositorio y el XPZ, por ejemplo con este prompt (reemplazar las partes entre ángulos):

```text
Instala la skill Mimir Lite desde https://github.com/federicoaecom/mimir siguiendo su README; luego prepara un espacio de trabajo de KB para mi KB de GeneXus <NombreKb> en <carpeta> y sincroniza este XPZ: <ruta>.
```

Para la primera sincronización, darle una exportación completa de la KB desde el IDE de GeneXus, no solo los objetos que se modificaron. Indicar el XPZ como ruta de archivo cuando sea posible: un archivo adjuntado en el chat puede no existir en disco para los scripts del agente. Si solo se tiene el XPZ y no la carpeta nativa de la KB, indicarlo: el espacio de trabajo de KB se puede preparar solo a partir del XPZ.

### Para el agente

Seguir estos pasos en orden. Los bloques de comandos son de PowerShell 7, salvo el indicado para Linux y macOS, que es de bash; cuando el shell es bash, ejecutar cada bloque de PowerShell mediante `pwsh -NoProfile -Command '<bloque>'`. Preguntar al usuario antes de instalar software o crear enlaces.

1. **Verificar los requisitos previos** (ver [Soporte](#soporte)): `pwsh --version` (7.4+ en Windows, 7.4.6+ en Linux y macOS), un Python 3.8+ que responda como `python3 --version`, `python --version` o `py -3 --version` (el stub de Microsoft Store bajo `WindowsApps` no cuenta), `git --version`. Ofrecer instalar lo que falte y después abrir una terminal nueva para que `PATH` lo tome. En Linux, instalar `python3` y `git` con el gestor de paquetes de la distribución, y PowerShell según la [guía de instalación de Microsoft](https://learn.microsoft.com/powershell/scripting/install/installing-powershell). En Windows, las líneas de `winget` funcionan en cualquier shell, así que sirven antes de tener `pwsh` instalado:

   ```powershell
   winget install --id Microsoft.PowerShell -e
   winget install --id Python.Python.3.12 -e
   winget install --id Git.Git -e
   ```

2. **Clonar el repositorio fuera del proyecto del usuario**, nunca dentro de la carpeta del proyecto: su `AGENTS.md` y su `CLAUDE.md` de la raíz son instrucciones para quienes contribuyen a este repositorio, y un agente que trabaja en el proyecto los cargaría como instrucciones del proyecto. La ruta del clon es `<mimir-lite-root>` en todos los flujos de trabajo.

   Clonar es instalar software, y un fetch, pull o reset modifica el clon: preguntar al usuario antes de cualquier clone, fetch, pull o reset de la copia de la skill, y ejecutarlo solo después de un sí explícito. Para un clon, nombrar la ruta de destino (por ejemplo `$HOME/mimir-lite`). Leer este README desde su URL en lugar de clonar el repositorio en otro lugar para leerlo; clonar una sola vez, en la ruta aprobada.

   Si `<mimir-lite-root>` ya existe, no clonar de nuevo y todavía no actualizarlo. Inspeccionarlo en modo de solo lectura, ejecutando cada comando siguiente en una llamada propia (sin `&&`, `;`, pipes ni `cd`), para que cada uno coincida con una regla de permiso simple. Después, antes de preguntar por una actualización, informar al usuario en texto visible si el clon está limpio, su commit actual y si `origin` es la URL de este README, en un mensaje breve propio o en las primeras líneas del mensaje que hace la pregunta de actualización; un informe que aparece solo en la salida de una herramienta o en el razonamiento del agente no se dio:

   ```powershell
   git -C "$HOME/mimir-lite" status
   git -C "$HOME/mimir-lite" log -1 --oneline
   git -C "$HOME/mimir-lite" remote get-url origin
   ```

   Preguntar antes de actualizarlo. Con un sí, hacer fetch y después actualizar solo por fast-forward, también un comando por llamada:

   ```powershell
   git -C "$HOME/mimir-lite" fetch origin
   git -C "$HOME/mimir-lite" pull --ff-only
   ```

   Después de actualizar, volver a leer los archivos de flujo ya leídos en esta sesión, al menos [`install.md`](skills/mimir-lite/workflows/install.md), antes de continuar: la actualización puede haberlos cambiado. Si el usuario rechaza la actualización, tomar los comandos del propio `README.md` y del `install.md` de ese clon, no de este README: un clon más antiguo puede no tener opciones más nuevas (por ejemplo `-OnlyTool`).

   Si la actualización no puede hacerse por fast-forward (historial no relacionado, commits locales o cambios sin confirmar), detenerse y explicar el motivo en palabras simples. Nunca hacer reset, borrar ni sobrescribir el clon existente; ofrecer en su lugar un clon nuevo en una ruta nueva aprobada. Eliminar o renombrar el clon anterior solo después de un sí explícito, y solo cuando su `git status` esté limpio.

   Cuando `<mimir-lite-root>` no existe, clonar en la ruta aprobada:

   ```powershell
   git clone https://github.com/federicoaecom/mimir "$HOME/mimir-lite"
   ```

   Las líneas de `git` de este paso también funcionan sin cambios en bash.

   Sin Git, sirve una descarga ZIP extraída en el mismo lugar, pero Windows marca los scripts descargados como bloqueados; desbloquearlos con `Get-ChildItem -Recurse "$HOME\mimir-lite" | Unblock-File`.

3. **Enlazar la carpeta de la skill en la carpeta de skills de la herramienta de agente.** `~/.agents/skills` la leen Codex, Cursor, OpenCode, Pi, GitHub Copilot, Gemini CLI y la Antigravity CLI; Claude Code (CLI, extensión de VS Code, escritorio) lee `~/.claude/skills`; el IDE de Antigravity lee `~/.gemini/config/skills` (ver [Soporte](#soporte)). Enlazar en las dos primeras está bien. Quienes usan Cursor también enlazan en `~/.cursor/skills`; si no, la auditoría informa una brecha. Una copia de la carpeta de la skill no está soportada: queda desactualizada después de `git pull`, y la auditoría no puede distinguir una copia desactualizada de una al día; usar un enlace simbólico o una junction.

   Preguntar antes de enlazar. Nombrar cada enlace que se crearía, con la ruta del enlace y su destino (por ejemplo `~/.claude/skills/mimir-lite` apuntando a `<mimir-lite-root>/skills/mimir-lite`), y crear solo los enlaces que el usuario apruebe. Un pedido de instalar la skill, o de seguir este README, no es consentimiento para crear enlaces. Dejar en los bloques siguientes solo las carpetas de skills que el usuario aprobó. Cuando la pregunta ofrece una opción "ningún enlace nuevo", esa opción excluye todas las demás: con ella, no crear ningún enlace.

   En Windows, un enlace simbólico requiere el modo desarrollador o un shell elevado; el bloque recurre a una junction de directorio, que no requiere ninguno de los dos, y omite un enlace que ya existe:

   ```powershell
   $repo = "$HOME\mimir-lite"
   foreach ($skills in "$HOME\.agents\skills", "$HOME\.claude\skills") {
       New-Item -ItemType Directory -Force -Path $skills | Out-Null
       if (Test-Path "$skills\mimir-lite") { continue }
       try   { New-Item -ItemType SymbolicLink -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" -ErrorAction Stop | Out-Null }
       catch { New-Item -ItemType Junction -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" | Out-Null }
   }
   ```

   En Linux y macOS, un enlace simbólico no requiere permisos especiales. Este bloque de bash crea uno con `ln -s` y omite un enlace que ya existe:

   ```bash
   repo="$HOME/mimir-lite"
   for skills in "$HOME/.agents/skills" "$HOME/.claude/skills"; do
       mkdir -p "$skills"
       if [ -e "$skills/mimir-lite" ] || [ -L "$skills/mimir-lite" ]; then continue; fi
       ln -s "$repo/skills/mimir-lite" "$skills/mimir-lite"
   done
   ```

   `skills/mimir-delegate` es opcional: delega una tarea o pide una revisión por pares a otro LLM. Ofrecerla como opción en la pregunta de enlace, y enlazarla de la misma forma solo después de un sí. Nunca decidirlo por el usuario, en ningún sentido.

   Después de enlazar, ejecutar la auditoría de la instalación una sola vez e informar al usuario su resultado `overall` (`REGISTRATION_OK` o `REGISTRATION_GAPS`). El flujo **install** ([`install.md`](skills/mimir-lite/workflows/install.md)) explica el resultado y cómo corregir una brecha, de nuevo solo después de que el usuario lo apruebe. Pasar `-OnlyTool` con las herramientas que atienden las carpetas de skills que el usuario aprobó, como una sola lista separada por comas: `~/.claude/skills` atiende a `ClaudeCode`; `~/.agents/skills` atiende a `Codex`, `OpenCode` y `Antigravity`; `~/.cursor/skills` atiende a `Cursor`; `~/.gemini/config/skills` atiende a `Antigravity`. Toda otra herramienta se informa como `skipped_by_choice`, que no es una brecha. Cuando, en cambio, el usuario nombra herramientas a excluir, pasarlas con `-SkipTool` (por ejemplo `-SkipTool Cursor`, o `-SkipTool Codex,OpenCode`); las dos no se pueden combinar. Agregar `-SkipSkill mimir-delegate` solo cuando el usuario no quiso delegación; nunca agregarlo cuando el usuario pidió delegación, para que un enlace faltante siga apareciendo como brecha. La auditoría cubre Claude Code, Codex, Cursor, OpenCode y Antigravity; Pi, GitHub Copilot y Gemini CLI se auditan con `-AdditionalSkillsRoot .agents/skills`, que `-OnlyTool` nunca omite. El comando siguiente es para las dos carpetas de los bloques anteriores; reemplazar `<mimir-lite-root>` por la ruta absoluta literal del clon, con barras `/`:

   ```powershell
   pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/Test-MimirSkillsRegistration.ps1" -OnlyTool ClaudeCode,Codex,OpenCode,Antigravity -AsJson
   ```

4. **Iniciar una sesión de agente nueva si hace falta.** La mayoría de las herramientas cargan las skills al iniciar una sesión, así que la sesión actual puede no ver la skill nueva todavía; algunas herramientas cargan una skill recién enlazada en la sesión en curso. Verificar si la skill está disponible antes de pedirle al usuario que reinicie. Si no lo está y no es posible reiniciar, leer `<mimir-lite-root>/skills/mimir-lite/SKILL.md` directamente y seguirlo.

5. **Preparar el espacio de trabajo de KB y después sincronizar.** Seguir el flujo **setup** ([`setup.md`](skills/mimir-lite/workflows/setup.md)), que crea el espacio de trabajo con el scaffolder en un solo comando, por ejemplo `pwsh -NoProfile -File "<mimir-lite-root>/skills/mimir-lite/scripts/New-MimirKbWorkspace.ps1" -WorkspaceRoot "<KbWorkspace>" -KbName <KbName>`. Después seguir el flujo **sync** ([`sync.md`](skills/mimir-lite/workflows/sync.md)), incluida su [guía para la primera sincronización](skills/mimir-lite/workflows/sync.md#first-sync-of-a-new-workspace): dónde guardar un XPZ adjuntado en el chat, por qué la primera carga debe ser una exportación completa y por qué la ejecución puede superar el tiempo límite del comando.

## Requisitos

| Requisito | Notas |
|---|---|
| Windows 10/11 o Linux | Ambos probados en la CI; macOS es de mejor esfuerzo (ver [Soporte](#soporte)) |
| PowerShell 7.4+ (`pwsh`); 7.4.6+ en Linux y macOS | Los scripts bajo `skills/` y `tools/` declaran `#requires -Version 7.4`, salvo `skills/mimir-lite/scripts/Test-MimirPowerShellRuntime.ps1` y su plantilla `Test-KbPowerShellRuntime.example.ps1`, que lo omiten por diseño para poder informar sobre un host más antiguo; el ejecutor de pruebas (`tests/Invoke-Tests.ps1`) y su autoprueba declaran 7.0. En Linux y macOS, 7.4.6 es la primera versión probada: 7.4.2 pierde el stderr de un comando nativo cuando stdout y stderr se redirigen a archivos separados |
| Python 3.8+ (solo librería estándar, incluido `sqlite3`) | Necesario para construir el índice SQLite y para ejecutar cada consulta al índice, además de la verificación de escritura de transacciones; sin paquetes de terceros. Se busca como `python3`, después `python` y después `py -3`. 3.8 es el mínimo que permite la sintaxis del código (una expresión de asignación en el motor de consultas) y se verificó ejecutando la construcción del índice y una consulta en 3.8, 3.10 y 3.11; las versiones anteriores no están soportadas |

No se necesita: una instalación del IDE de GeneXus, MSBuild, ni ninguna herramienta de build/specify/generate de GeneXus. Construir, empaquetar o importar XPZ en una KB queda fuera del alcance de esta skill.

### Plataforma

Windows y Linux se prueban en la CI; macOS ejecuta los mismos caminos de código que Linux, con mejor esfuerzo ([Soporte](#soporte)). La capa de PowerShell encuentra la carpeta personal del usuario mediante `HOME` o `USERPROFILE`, registra las skills con enlaces simbólicos (con una junction como alternativa en Windows) y, en Windows, descarta el stub de Python de Microsoft Store (`WindowsApps`). Los motores de Python (construcción y consulta del índice, verificación de escritura) y el índice SQLite usan solo la librería estándar. El índice guarda la ruta del corpus relativa a la carpeta del índice, así que un índice construido en Windows se puede leer en Linux.

### Diferencias conocidas entre plataformas

- **Versión de PowerShell.** Linux y macOS requieren PowerShell 7.4.6 o posterior (ver [Requisitos](#requisitos)).
- <!-- backend-parity: ignore --> **Prompt por stdin.** En Linux y macOS, los adaptadores de `mimir-delegate` que envían el prompt por stdin (opencode, Codex, Claude Code) lo entregan con un salto de línea final adicional, porque PowerShell copia el archivo redirigido línea por línea. No afecta a una CLI de LLM.
- **Carpeta de estado.** `mimir-delegate` guarda su estado en `%LOCALAPPDATA%\mimir-delegate` en Windows y en `~/.local/share/mimir-delegate` en Linux (`$XDG_DATA_HOME/mimir-delegate` cuando esa variable está definida). En macOS usa la carpeta de datos locales de aplicación de .NET, normalmente `~/Library/Application Support/mimir-delegate`, o la ubicación de Linux cuando `~/Library/Application Support` no existe; esto no se prueba en la CI.
- <!-- backend-parity: ignore --> **Descubrimiento de las CLIs.** Un parámetro `-<Herramienta>Exe` explícito tiene prioridad en todos los sistemas. Sin él, en Windows, Codex se toma de los binarios de la aplicación de escritorio de Codex bajo `%LOCALAPPDATA%\OpenAI\Codex\bin` (se ignora el shim de npm en `PATH`), y opencode y la Antigravity CLI de `PATH` y después de sus carpetas de instalación de Windows (`%APPDATA%\npm`, `%LOCALAPPDATA%\agy`). En Linux y macOS, cada CLI se toma de `PATH`; para Codex, el primer `codex` que responde a `codex --version`.

## Instalación

1. Clonar este repositorio fuera de cualquier carpeta de proyecto (ver [Usarlo con un agente de IA](#usarlo-con-un-agente-de-ia), paso 2).
2. Ejecutar el flujo de trabajo **install** ([`skills/mimir-lite/workflows/install.md`](skills/mimir-lite/workflows/install.md)) para registrar `skills/mimir-lite/` y, opcionalmente, `skills/mimir-delegate/` como skills en las herramientas de agente instaladas en la máquina (soporte integrado: Codex, Claude Code, Cursor, OpenCode, Antigravity; cualquier otra herramienta que lea `SKILL.md` desde un directorio de skills puede enlazarse igual, ver la sección "Other tools" del flujo de trabajo). Crea un enlace simbólico o una junction por herramienta, detecta cuáles están realmente instaladas y no cambia nada sin confirmación explícita.

Volver a ejecutar el flujo de instalación después de cada `git pull`, ya que también detecta registros de skill que quedaron desactualizados o huérfanos. Después de una actualización que cambia el contrato del setup, la primera tarea de KB en cada espacio de trabajo de KB existente informa `AUDIT_REQUIRED` una vez; ejecutar la auditoría del setup y aprobar el nuevo sellado de la marca de tiempo.

## Guía rápida

Ejecutar desde la raíz del repositorio, en PowerShell 7.4+ (7.4.6+ en Linux y macOS). Cada comando se ejecutó tal como aparece contra el fixture sintético.

**1. Registrar la skill en una herramienta de agente** (omitir este paso si se siguió [Usarlo con un agente de IA](#usarlo-con-un-agente-de-ia)). El ejemplo enlaza `mimir-lite` en la carpeta de skills de Claude Code; [Soporte](#soporte) lista la carpeta de cada una de las demás herramientas. El bloque es para Windows, donde un enlace simbólico requiere el modo desarrollador o un shell elevado; recurre a una junction de directorio, que no requiere ninguno de los dos, y omite un enlace que ya existe. En Linux y macOS, ejecutar en su lugar `mkdir -p ~/.claude/skills && { [ -e ~/.claude/skills/mimir-lite ] || [ -L ~/.claude/skills/mimir-lite ] || ln -s "$PWD/skills/mimir-lite" ~/.claude/skills/mimir-lite; }` en bash, que también omite un enlace que ya existe. Una copia de la carpeta de la skill no está soportada: queda desactualizada después de `git pull`, y la auditoría no puede distinguir una copia desactualizada de una al día; usar un enlace simbólico o una junction. Enlazar `skills/mimir-delegate` de la misma forma solo si se quiere delegación.

```powershell
$repo   = (Get-Location).Path
$skills = "$HOME\.claude\skills"
New-Item -ItemType Directory -Force -Path $skills | Out-Null
if (-not (Test-Path "$skills\mimir-lite")) {
    try   { New-Item -ItemType SymbolicLink -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" -ErrorAction Stop | Out-Null }
    catch { New-Item -ItemType Junction -Path "$skills\mimir-lite" -Target "$repo\skills\mimir-lite" | Out-Null }
}
```

**2. Verificar el registro.** La auditoría es de solo lectura y cubre Claude Code, Codex, Cursor, OpenCode y Antigravity; `mimir-lite` debería mostrar `OK` (`mimir-delegate` muestra `missing` salvo que se haya enlazado, o `skipped_by_choice` con `-SkipSkill mimir-delegate`, que no es una brecha). Para otra herramienta, agregar su carpeta de skills con `-AdditionalSkillsRoot <dir>`; se reporta como `Custom:<dir>`.

```powershell
$audit = pwsh -NoProfile -File skills/mimir-lite/scripts/Test-MimirSkillsRegistration.ps1 -AsJson | ConvertFrom-Json
($audit.tools | Where-Object name -eq 'ClaudeCode').skills | Select-Object name, status, linkType
```

**3. Primera ejecución contra el fixture sintético.** Construye el índice SQLite derivado a partir de `tests/fixtures/sample-kb/` en una carpeta temporal (no se escribe nada dentro del repositorio) y consulta quién usa la tabla `Customer`. La construcción necesita Python (ver [Requisitos](#requisitos)) e imprime un reporte de validación en JSON; la consulta imprime un resultado corto.

```powershell
$work = Join-Path ([IO.Path]::GetTempPath()) 'mimir-quickstart'
New-Item -ItemType Directory -Force -Path $work | Out-Null
pwsh -NoProfile -File skills/mimir-lite/scripts/Build-KbIntelligenceIndex.ps1 -SourceRoot tests/fixtures/sample-kb -OutputPath "$work/kb-index.sqlite"
pwsh -NoProfile -File skills/mimir-lite/scripts/Query-KbIntelligenceIndex.ps1 -IndexPath "$work/kb-index.sqlite" -Query who-uses -ObjectType Table -ObjectName Customer -Format text
```

Salida esperada de la consulta:

```text
who-uses: Table:Customer
results: 1/1
- #21 Transaction:Customer -> Table:Customer [has_level_table, direct]
  Transaction/Customer.xml:3 Level Type via transaction_level_table
  <Level name="Customer" Type="Customer">
```

Esto muestra los dos motores en los que se apoya el flujo **find**. Omite a propósito el espacio de trabajo de KB, la sincronización de XPZ y la compuerta obligatoria de frescura, que requieren un espacio de trabajo de KB real; el flujo **setup** crea uno en un solo comando con `New-MimirKbWorkspace.ps1`. Un agente siempre pasa esa compuerta antes de confiar en un índice. Para una KB real, la primera sincronización requiere una exportación completa de la KB (ver la [guía para la primera sincronización](skills/mimir-lite/workflows/sync.md#first-sync-of-a-new-workspace) del flujo **sync**).

## Flujos de trabajo

Cada paso indica el flujo de trabajo que lo resuelve; ver el archivo del flujo enlazado para el contrato completo.

| Paso | Flujo de trabajo | Qué hace |
|---|---|---|
| 1. Preparar el espacio de trabajo de la KB | [`workflows/setup.md`](skills/mimir-lite/workflows/setup.md) | Crea la estructura de carpetas junto a la KB de GeneXus en un solo comando con `New-MimirKbWorkspace.ps1` (`KbObjectsXml`, `KbIntelligence`, wrappers locales), o solo a partir del XPZ cuando la carpeta nativa de la KB no está disponible, o audita una existente |
| 2. Sincronizar un XPZ | [`workflows/sync.md`](skills/mimir-lite/workflows/sync.md) | Materializa un XPZ exportado desde el IDE de GeneXus en el corpus XML, un archivo por objeto |
| 3. Buscar mediante el índice | [`workflows/find.md`](skills/mimir-lite/workflows/find.md) | Consulta el índice SQLite derivado para quién-usa/qué-usa/impacto antes de abrir el XML, una vez que pasa su compuerta obligatoria de frescura |
| 4. Leer un objeto | [`workflows/read.md`](skills/mimir-lite/workflows/read.md) | Clasifica estructuralmente el XML de un objeto (tipo, familia, partes, riesgo) |
| 5. (Opcional) Generar documentación | [`workflows/docs.md`](skills/mimir-lite/workflows/docs.md) | Genera documentación en Markdown a partir del corpus XML |

El corpus XML (`KbObjectsXml`) es la fuente normativa; el índice siempre es un atajo hacia él, nunca un reemplazo, y toda consulta sustantiva al índice debe pasar primero su compuerta de frescura.

## Estructura del repositorio

```
skills/
├── mimir-lite/       # skill principal (se instala en las herramientas de agente)
│   ├── SKILL.md       # punto de entrada + enrutador hacia los flujos de trabajo
│   ├── workflows/      # sync, find, read, docs, setup, install
│   ├── references/     # base de conocimiento orientada al agente
│   └── scripts/        # motores en PowerShell + Python
└── mimir-delegate/    # skill opcional: delegación y revisión por pares
    ├── SKILL.md
    ├── references/
    └── scripts/
tests/                 # self-tests y pruebas de paridad, un único runner
tools/                 # verificaciones solo para contribuidores (parse, encoding, links, pre-push)
docs/                  # documentación humana (ver más abajo)
```

## Ejecutar pruebas y verificaciones

Todos los comandos se ejecutan desde la raíz del repositorio con `pwsh` 7.4+ (7.4.6+ en Linux y macOS).

| Comando | Qué verifica |
|---|---|
| `pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1` | Ejecuta cada `*SelfTest.ps1` y cada `Test*.py` de Python bajo `tests/` (agregar `-AsJson` para un reporte estructurado) |
| `pwsh -NoProfile -File tools/Test-TextEncoding.ps1` | Los archivos de texto versionados son UTF-8 sin BOM, con finales de línea LF |
| `pwsh -NoProfile -File tools/Test-PsScriptsParse.ps1` | Cada `*.ps1` bajo `skills/`, `tools/`, `tests/` parsea sin errores |
| `pwsh -NoProfile -File tools/Test-PyScriptsParse.ps1` | Cada `*.py` bajo las mismas raíces parsea sin errores (sin generar bytecode) |
| `pwsh -NoProfile -File tools/Test-MarkdownFences.ps1` | Los bloques de código de Markdown están balanceados y bien formados |
| `pwsh -NoProfile -File tools/Test-MarkdownLinks.ps1` | Los enlaces relativos de Markdown y las menciones sueltas `NN-*.md` resuelven a un archivo real |
| `pwsh -NoProfile -File tools/Test-ScriptInventory.ps1` | Cada script figura en el inventario de scripts |
| `pwsh -NoProfile -File tools/Test-CodeLanguage.ps1` | Los comentarios y mensajes del código están en inglés |

La CI ejecuta todas las verificaciones anteriores en Windows y en Linux (ver [`CONTRIBUTING.es.md`](CONTRIBUTING.es.md)). Quienes mantienen el proyecto también ejecutan las verificaciones mecánicas de pre-push (contexto de git, parse, espacios en blanco) con `pwsh -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-PrePushMechanicalChecks.ps1 -AsJson`; ver [`docs/process/13-pre-push-review.es.md`](docs/process/13-pre-push-review.es.md).

## Mapa de documentación

| Carpeta | Contenido |
|---|---|
| [`docs/README.es.md`](docs/README.es.md) | Índice de la documentación humana |
| `docs/process/` | Métodos de trabajo del equipo (revisión pre-push, revisión reforzada, revisión por pares) |
| [`docs/adr/`](docs/adr/README.md) | Registros de decisiones |
| `docs/ideas/` | [Backlog](docs/ideas/backlog.es.md) curado e [ideas descartadas](docs/ideas/discarded.es.md) |
| [`docs/i18n/`](docs/i18n/README.md) | Política de traducción y [glosario](docs/i18n/glossary.md) |

El contenido orientado al agente (`SKILL.md`, `workflows/`, `references/`) vive dentro de `skills/`, no en `docs/`.

## Fuera de alcance

Generar, clonar o empaquetar objetos de GeneXus; construir o importar paquetes XPZ en una KB; builds basados en MSBuild. Ver la sección "Do NOT use this workflow for" de cada flujo de trabajo para el detalle.

## Delegación y archivos escritos fuera del repositorio

`mimir-lite` nunca envía nada a un servicio externo. La skill opcional `mimir-delegate` sí puede, y solo cuando se le pide a un agente delegar una tarea o hacer una revisión por pares: envía contenido del prompt a una CLI de LLM externa (opencode, incluidos los proveedores de modelos con los que esté configurado; Codex; Claude Code; GitHub Copilot CLI; Gemini CLI; Antigravity CLI) o a un modelo local. Antes de enviar, el agente clasifica el contenido como `public` o `kb-sensitive` y ejecuta `Resolve-LlmDelegateAuthorization.ps1`, que devuelve allow, ask o deny según la localidad del destino y la política. El agente juzga la sensibilidad del contenido, por lo que esta compuerta es procedimental, no técnica: no inspecciona el contenido. Si no se desea que ningún contenido de la KB salga de la máquina, no solicitar delegación, o responder "deny" cuando se pregunte. Ver [`SECURITY.es.md`](SECURITY.es.md) y [`skills/mimir-delegate/SKILL.md`](skills/mimir-delegate/SKILL.md).

Las herramientas escriben fuera de este repositorio en estos lugares:

| Ubicación | Qué | Lo escribe |
|---|---|---|
| `<espacio de trabajo de KB>` | El espacio de trabajo nuevo junto a la KB: `scripts` (wrappers locales), `README.md`, `AGENTS.md`, `kb-source-metadata.md`, `.gitignore` y las carpetas `Temp`, `IdeXpzExports`, `KbObjectsXml`, `KbIntelligence` | Flujo **setup** de `mimir-lite`, con el scaffolder `New-MimirKbWorkspace.ps1` |
| `<espacio de trabajo de KB>\KbObjectsXml`, `<espacio de trabajo de KB>\KbIntelligence` | El corpus XML y el índice derivado, junto a la KB | Flujos **sync** y **setup** de `mimir-lite` |
| `<espacio de trabajo de KB>\.claude\settings.json` | Reglas de permiso de Claude Code para la carpeta `scripts` del espacio de trabajo y los scripts del motor compartido, y reglas de lectura para la carpeta `skills` del clon y los enlaces de la skill en `~/.claude/skills` | Flujo **setup** (pasos 20 y 20a), solo Claude Code; se puede rechazar |
| Directorios de skills de las herramientas de agente (por ejemplo `~/.claude/skills/`) | Un enlace por skill, nunca una copia | Flujo **install**, tras la confirmación |
| Archivos de instrucciones globales de las herramientas de agente | La sección de activación "KB workspace" | Flujo **setup**, solo tras confirmación explícita |
| `%LOCALAPPDATA%\mimir-delegate` (Windows), `~/.local/share/mimir-delegate` (Linux), normalmente `~/Library/Application Support/mimir-delegate` (macOS, sin pruebas en la CI; la ubicación de Linux cuando `~/Library/Application Support` no existe) | `capabilities.json`, `preferred-reviewers.json` (y `preferred-reviewers.<herramienta>.json` por herramienta), estado del circuit breaker | `mimir-delegate` |
| `<espacio de trabajo de KB>\llm-delegation-policy.json` | Política de entrega externa por KB | `mimir-delegate`, cuando se registra una política |
| La carpeta temporal del sistema, `%TEMP%` en Windows, `$TMPDIR` o `/tmp` en los demás sistemas (`claude-code-async`, `codex-jobs`, `mimir-panel-dispatch`, `mimir-panel-codex`, `mimir-agy-public-review` y archivos temporales) | Prompts, salidas y estado de los trabajos delegados; los adaptadores que aceptan `-KeepDays` limpian las carpetas de trabajos antiguos | `mimir-delegate` |

## Contribuir y seguridad

Ver [`CONTRIBUTING.es.md`](CONTRIBUTING.es.md) para cómo contribuir y [`SECURITY.es.md`](SECURITY.es.md) para cómo reportar un problema de seguridad. La participación se rige por [`CODE_OF_CONDUCT.es.md`](CODE_OF_CONDUCT.es.md), y los cambios se registran en [`CHANGELOG.md`](CHANGELOG.md).
