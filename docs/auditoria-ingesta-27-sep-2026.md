# Auditoría de la ingesta y Calidad del dato — 27-sep-2026

Pedida por Samuel en dos mensajes: primero una revisión de código y lógica funcional
"hasta la parte de ingesta"; después, específicamente, por qué había valores en la
vista **Calidad del dato** que no reconocía, con instrucción de guiarse por
`KPI's EHS 2026-julio_versionfinal.xlsx` (hoja **indicadores mensuales LABS**) como
referencia — y de dejar documentado con detalle lo que no fuera viable arreglar de una
vez, para depurarlo después con la persona encargada.

Este documento tiene tres partes: (1) la reconciliación completa contra el Excel, (2) lo
que se encontró y **ya se corrigió**, con su commit, y (3) lo que se encontró y **queda
documentado, no corregido todavía** — con el archivo exacto, por qué importa, y cómo
debería quedar.

---

## 1. Reconciliación completa contra el Excel fuente

Se leyó `KPI's EHS 2026-julio_versionfinal.xlsx`, hoja `indicadores mensuales LABS`,
con la MISMA lógica de búsqueda por etiqueta que usa `analisis/construir_datos.py` (no
coordenadas fijas), para Celta/Estrella/Agencias × Enero-Julio × las 7 magnitudes
crudas de esa hoja (peligroso/aprovechable/ordinario/agua/luz/accidentes/unidades) más
horas-hombre de la hoja `AT 2026`. Se comparó, celda por celda, contra lo que
`/api/ehs/detalle` devuelve de la base de datos real.

**Resultado: 173 de 175 valores coinciden exactos.** Las únicas 2 diferencias:

| Sitio | Mes | Magnitud | Excel | Base de datos | Por qué |
|---|---|---|---|---|---|
| Celta | Mayo | accidentes_dafw | 1 | 0 | Corrección verbal confirmada con el manager (reunión 24-sep-2026): el accidente fue en julio, no mayo. El Excel `AT 2026!L9` sigue sin corregir. Documentado en `ehs/CLAUDE.md` y aplicado en la migración `0012_ehs_historico_peru_accidente.sql`. |
| Celta | Julio | accidentes_dafw | 0 | 1 | Misma corrección, contraparte. |

Las otras "diferencias" que aparecieron en el script de verificación (`horas_temp = 0`
en la base para Celta/Estrella en los 7 meses, sin valor correspondiente en el Excel)
**no son un defecto**: la columna de horas temporales viene en blanco en el Excel para
esos dos sitios (ninguno tiene personal temporal), y el sistema interpreta
correctamente "blanco" como "0 horas temporales reales" — no como "sin capturar" — tal
como documenta `ehs/CLAUDE.md`: *"Hoy solo Agencias reporta horas de personal temporal.
En Celta y Estrella la columna de temporales viene vacía, así que su total de horas
equivale al de fijos."*

**Conclusión honesta para Samuel:** los números del tablero SÍ trazan de vuelta al
Excel, prácticamente exactos, con la única excepción de la corrección de fecha del
accidente que tú mismo confirmaste con tu manager. El problema real que encontraste no
era que los datos estuvieran mal — era que la vista **Calidad del dato** tenía un bug
propio (sección 2 de abajo) que hacía que sus números NO cuadraran entre sí en la misma
pantalla, lo cual es exactamente la clase de cosa que hace desconfiar de todo lo demás
aunque lo demás esté bien.

---

## 2. Encontrado y corregido

| # | Qué | Dónde | Commit |
|---|---|---|---|
| 1 | **"01 Lecturas cargadas por mes" mostraba 40/mes fijo (sitios × magnitudes-constante), en vez del conteo real** — no cuadraba contra la tarjeta "Lecturas cargadas: 217" de la misma pantalla (40×7=280 ≠ 217). Corregido a un conteo real (`count(*)`), que ahora da 31/mes y suma 217. Mismo bug, independiente, en `analisis/web_json.py` (el generador del JSON para Vercel). | `adaptador_sql.js` (`calidadDato`), `analisis/web_json.py` | `9f7b8ce`* |
| 2 | **`residuosComposicion` mezclaba el total agregado del mes con la parte "total" de Perú** — en el ámbito Colombia + Perú, el tooltip de "03 De qué está hecho el residuo" mostraba un "Total" incorrecto (solo la parte de Perú, no la suma real). | `adaptador_sql.js`, `adaptador_json.js`, `graficos.js` | `abdae58` |
| 3 | **La marca de "Meta del sitio" desaparecía del todo** cuando la meta de un sitio superaba por mucho las demás barras (La Estrella, 6,20 acc/MHH). | `graficos.js` (`porSitio`) | `abdae58` |
| 4 | **`sp_capturar_lote` no avisaba un cero tecleado por error** en agua/energía/unidades/horas_fijos — la condición que debía protegerlo excluía justo el caso que importaba. | `migraciones/0014_ehs_advertencia_cero.sql` | `3edd1b6` |
| 5 | **Corregir una lectura rechazaba valores válidos** (p. ej. 8,076) con "Número ambiguo" por una doble validación — y el mensaje real de cualquier error de validación de escritura se perdía en un 500 genérico. | `escritura_simulada.js`, `errores.js` | `1920cd9` |
| 6 | Tres filtros defensivos ya redundantes, tres comentarios con información incorrecta (historial de un color, código HTTP, una tilde). | `graficos.js`, `tablero.js`, `reporte.js` | `abdae58` |

\* *commit de esta sección — ver el hash real en el historial, esta tabla se completa al
cerrar el documento.*

---

## 3. Encontrado, documentado, NO corregido todavía

Organizado por archivo. Cada uno dice: qué está mal, de qué documento/línea sale la
lógica actual, por qué importa, y cómo debería quedar — para depurar con calma, no para
que se pierda.

### 3.1 — `analisis/generar_sql_carga.py` (genera `sql/03-carga-inicial.sql`)

**Qué está mal:** las listas `MAGNITUDES` (línea ~55) y `KPI_MAGNITUD` (línea ~68) no
incluyen `residuo_total_kg` — la magnitud que `ehs/CLAUDE.md` documenta explícitamente
como el numerador de `residuos_por_lente` para Perú y el histórico. Este script dice en
su propio encabezado que es la ÚNICA fuente regenerable de `ref.dim_magnitud`/
`ref.kpi_magnitud` ("No editar a mano: se regenera").

**Por qué importa:** hoy no importa — esas tablas ya están correctas en la base de
datos, cargadas por las migraciones `0011`/`0012` directamente. Pero SI alguien vuelve
a correr este script para regenerar `sql/03-carga-inicial.sql` (su propósito
declarado), Perú y el histórico pierden su única magnitud de residuo sin ningún error —
un reporte silencioso de cero, justo lo que el proyecto se construyó para evitar.

**Cómo debería quedar:** agregar una fila a `MAGNITUDES` (`residuo_total_kg`, kg, con
`valor_min`/`valor_max` del histórico de Perú) y otra a `KPI_MAGNITUD`
(`residuos_por_lente`, `residuo_total_kg`, `numerador`), con el mismo criterio que ya
usa la migración `0011` para estas mismas dos tablas.

### 3.2 — `analisis/construir_datos.py` (lee el Excel de 2026, genera `hechos_mensual_2026.csv`)

**Qué está mal, en tres puntos:**

1. **Línea ~71**: `isinstance(v, (int, float))` descarta en silencio cualquier celda no
   numérica (vacía, texto, error de fórmula) para una magnitud que SÍ se encontró por
   etiqueta; la línea ~95 rellena lo que falta con `0.0`. Una celda de AGUA/LUZ/RESIDUOS
   temporalmente vacía o con texto se vuelve un 0 silencioso.
2. **Líneas ~76-86**: las horas-hombre de la hoja `AT 2026` se leen por posición fija de
   columna (`COLS_H = {"celta": (2,3), "estrella": (4,5), "agencias": (6,7)}`), sin
   verificar la etiqueta — al contrario que la búsqueda por bloque que sí usa el resto
   del archivo. `ehs/CLAUDE.md` documenta VARIOS incidentes reales de exactamente este
   patrón en este mismo libro (`AT 2026!C22` tomaba `C7` en vez de `E7`, etc.).
3. **Línea ~70**: el comentario de la línea 40 dice que los bloques se ubican "por
   etiqueta (no por coordenada)", pero el valor mensual se lee de `column=col+1` — un
   desplazamiento fijo de +1 desde la columna del mes, sin verificar que esa sea
   realmente la sub-columna "real" (no "meta"). La garantía que el comentario promete no
   la aplica el código.

**Por qué importa:** este script SÍ se re-ejecuta cada vez que llega un Excel nuevo
(es el pipeline mensual). Si el layout de la hoja cambia un poco (columna insertada,
target/real intercambiados), estos tres puntos fallan en silencio, no con un error.

**Cómo debería quedar:** (1) que una celda encontrada-pero-no-numérica levante un error
explícito en vez de rellenar con 0; (2) que la lectura de horas-hombre también busque
la columna por etiqueta, igual que el resto del archivo; (3) verificar contra la
etiqueta de encabezado (p. ej. "REAL" vs "META") antes de leer `column+1`, no asumirlo.

### 3.3 — `analisis/generar_historico_peru.py` (histórico 2023-2025 + Perú)

**Qué está mal:**

1. **Línea ~63**: `col_mes` arranca en `1` y solo cambia si encuentra un nombre de mes
   en la fila justo después del encabezado "LBP"; si no lo encuentra, se queda en `1`
   en silencio — todo el bloque de ese sitio queda leído con un desplazamiento de
   columna incorrecto, sin error.
2. **Línea ~74**: el bucle que lee los 12 meses hace `break` (no `continue`) en cuanto
   una fila no tiene un nombre de mes válido — una sola fila mal formada corta el resto
   del año en silencio, contradiciendo lo que su propio docstring promete ("lee los
   meses Enero..hasta_mes").
3. **Línea ~83**: si CUALQUIERA de lbp/agua/energía/residuos falta, se descartan LOS
   CUATRO — un mes que sí reportó producción/agua/energía pero todavía no tenía el dato
   de residuos pierde también las unidades buenas, sin registro de qué se descartó.
4. **Línea ~86**: los valores crudos históricos se redondean a 2 decimales AL
   CARGARLOS, antes de llegar a la base — `ehs/CLAUDE.md` reserva explícitamente la
   capa cruda/de auditoría como el único lugar SIN redondeo.

**Por qué importa:** este script ya corrió una vez (migración `0012`, ya aplicada) y
los datos que cargó SÍ se verificaron contra el Excel (sección 1 de este documento). El
riesgo es si se vuelve a correr sobre un Excel histórico distinto o reformateado.

**Cómo debería quedar:** (1) que `col_mes` no encontrado levante error, no se quede en
1; (2) `continue` en vez de `break`, con un registro de qué mes se saltó; (3) no
descartar las 4 magnitudes por una sola faltante — guardar lo que sí hay y dejar la
faltante en `NULL`; (4) no redondear al cargar, solo al mostrar (mismo patrón que ya
usa el resto del proyecto).

### 3.4 — `migraciones/0012_ehs_historico_peru_accidente.sql` (ya aplicada)

**Qué está mal:** ~600 líneas entre `begin transaction`/`commit transaction` sin
`set xact_abort on` ni `try/catch` con `rollback` — a diferencia de `sp_capturar_lote`,
`sp_corregir_lectura` y la migración `0010`, que sí lo usan. Además, los dos `UPDATE`
que corrigen el accidente de Celta (mayo→0, julio→1) no verifican `@@rowcount`: si la
migración `0008` (opcional) no corrió antes, ambos `UPDATE` afectan 0 filas sin error
ni aviso, y el script igual termina imprimiendo un mensaje de éxito.

**Por qué importa:** esta migración YA está aplicada y verificada (sección 1). El riesgo
es solo para una instalación FUTURA en el computador nuevo, si alguien aplica las
migraciones fuera de orden o se salta la `0008`.

**Cómo debería quedar:** no se edita (una migración aplicada no se toca, mismo criterio
que ya usa el proyecto). Si se necesita mayor seguridad transaccional para la
instalación nueva, sería una migración `0015` nueva con `set xact_abort on` +
`try/catch` envolviendo la misma lógica, más una verificación explícita de
`@@rowcount` después de los dos `UPDATE` del accidente que levante error si da 0.

### 3.5 — `sql/01-esquema.sql` y la documentación de despliegue

**Qué está mal:** este archivo (y sus hermanos `02-vistas.sql`/`03-carga-inicial.sql`/
`04-ingesta.sql`) tienen el trigger `ehs.tr_lectura_mensual_hist` en su versión VIEJA
(pisa `modificado_por` con la cuenta de servicio después de cada corrección) — el mismo
defecto que la migración `0009` ya corrigió, pero la corrección nunca se replicó aquí.
`CONTEXTO.md` (línea ~78) dice que "el SQL vive en `app\sql\`... porque pasar a
producción es ejecutar esos scripts" — **pero eso ya no es cierto**: verificado que el
instalador real (`instalacion/instalar.ps1` → `scripts/migrar.js`) ejecuta EXCLUSIVAMENTE
`migraciones/*.sql`, nunca `sql/*.sql`. `sql/` quedó como un snapshot de una fase
anterior del proyecto, ya superado por el sistema de migraciones con checksum.

**Por qué importa:** verificado que NO es un riesgo activo (la instalación real no toca
estos archivos), pero es una fuente real de confusión — alguien (Samuel, IT, un futuro
colaborador) que lea `CONTEXTO.md` y mire `sql/01-esquema.sql` pensando que es la
versión vigente, encontraría un trigger con el defecto ya corregido en otro lado.

**Cómo debería quedar:** decisión de Samuel, dos caminos razonables — (a) actualizar
`CONTEXTO.md` para que diga que la instalación real usa `migraciones/` +
`scripts/migrar.js`, y mover `sql/*.sql` a `_descartado/` o marcarlo explícitamente
como snapshot histórico; o (b) si `sql/` todavía sirve para algo (p. ej. que un DBA lea
el esquema completo de un vistazo sin recorrer 14 archivos), regenerarlo desde las
migraciones vigentes y dejar dicho en el propio archivo que se regenera, no se edita a
mano.

### 3.6 — `analisis/comparar_adaptadores.py` y `analisis/construir_json_desde_sql.js`

**Qué está mal:**

1. `comparar_adaptadores.py` (línea ~46): la lista `AMBITOS` no incluye `peru` ni
   `colombia_peru` — los dos ámbitos reales que la corrección de "sin_dato" de esta
   sesión (commit `8dd1e21`) más necesitaba verificar. La "compuerta" de paridad
   JSON-vs-SQL nunca pregunta por ellos.
2. `construir_json_desde_sql.js` (línea ~140): el `CASE` de `estado` que escribe sigue
   con el orden VIEJO (revisa `meta = 0` antes que `sin lectura`) — el mismo bug que
   esta sesión corrigió en `adaptador_sql.js` — aunque su propio comentario en la línea
   136 dice que es "la misma regla EXACTA que ESTADO en adaptador_sql.js".

**Por qué importa:** este es el pipeline que regenera `datos.json` para Vercel
(interinato). Si alguien lo vuelve a correr para publicar Perú/Colombia+Perú en
Vercel (su propósito declarado), reintroduce en silencio el bug de "Cumple" falso con
cero datos que esta sesión corrigió en SQL — y el comentario que afirma paridad exacta
es precisamente lo que haría que alguien confiara en el archivo sin volver a revisarlo.

**Cómo debería quedar:** (1) agregar `peru`/`colombia_peru` a `AMBITOS` en
`comparar_adaptadores.py`; (2) reordenar el `CASE` de `construir_json_desde_sql.js`
para que revise `sin lectura` antes que `meta = 0`, exactamente como quedó
`adaptador_sql.js` (commit `8dd1e21`).

### 3.7 — `src/datos/escritura_sql.js` (verificado, riesgo menor al reportado inicialmente)

La revisión adversarial marcó esto como "bug", pero al leer el procedimiento
`sp_capturar_lote` completo (migración `0007`) se confirma que la mayoría de lo que
`escritura_sql.js` no valida en JS SÍ lo valida el propio procedimiento del lado del
servidor (magnitud desconocida, fecha inválida, sitio desconocido) — la fila
simplemente se aparta con su motivo en vez de tirar un error, que es el comportamiento
correcto. La única brecha real confirmada: si `f.sitio` llega `null`, el guardia
`if (f.sitio != null && !SITIO_IDS.has(...))` no lo detecta ANTES de mandarlo al
procedimiento (aunque el procedimiento sí lo rechaza después, con su propio mensaje).
Bajo impacto, documentado para no perderlo, no urgente.

---

## Cómo se usa este documento

Cuando se resuelva alguno de los puntos de la sección 3, se mueve a la sección 2 con su
commit, igual que ya hace `docs/backlog-solicitudes.md` con las solicitudes de diseño.
Este documento es específicamente sobre la ingesta y la calidad del dato — las
solicitudes de UX/visuales del tablero siguen en `docs/backlog-solicitudes.md`.
