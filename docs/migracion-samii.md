# Migrar a SAMII: qué se lleva, qué se adapta, qué se sustituye

Este documento existe para que la implementación real **no empiece de cero**. Lo que hoy
corre en Vercel no es un prototipo desechable: es la misma arquitectura que pide el
estándar, construida con el mismo stack, con el cálculo detrás de un adaptador y el dato
en un contrato explícito. Migrar consiste en cambiar de dónde salen los datos y dónde se
sirve la página. La lógica del área ya está escrita, verificada y probada en negativo.

Fecha: 30 de agosto de 2026 · Contra `ESTANDARINTEGRACION.md` y el hilo con IT del 3 de
julio al 26 de agosto.

---

## 1. El resumen en una tabla

| Pieza que existe hoy | Destino | Acción |
|---|---|---|
| `sql\01-esquema.sql` — 11 tablas del esquema `ehs` | DWH / SAMII | **Se lleva tal cual**, salvo dimensiones que IT ya tenga (§4.1) |
| `sql\02-vistas.sql` — 8 vistas analíticas | DWH / SAMII | **Se lleva tal cual.** Es la única implementación definitiva del cálculo |
| `sql\03-carga-inicial.sql` — el histórico 2026 | DWH / SAMII | **Se lleva**, previa conciliación con el DBA |
| `app\src\rutas_api.js` — los 9 GET del contrato | Módulo Dashboards de SAMII | **Se lleva tal cual.** No calcula: valida y sirve |
| `app\src\datos\adaptador_sql.js` | Módulo Dashboards | **Se completa.** El esqueleto y las 9 firmas ya están |
| `app\src\datos\adaptador_json.js` | — | **Se retira** cuando el SQL responda. Es el interinato |
| `app\views\`, `app\public\` — plantilla, CSS y ECharts | Módulo Dashboards | **Se adapta** al armazón de SAMII (§3) |
| `scripts\*.py` — el pipeline desde Excel | JOB del DWH | **Se sustituye** por el JOB, salvo `verificar_sql_contra_motor.py`, que se queda de oráculo |
| `datos\correcciones.csv` y su guarda | Tabla `ehs.correccion` | **Se adapta**: el mecanismo se conserva, el archivo se vuelve tabla |
| `app\datos\bitacora.jsonl` | `ehs.carga_log` | **Se sustituye.** La tabla ya está escrita en el esquema |
| Despliegue en Vercel | Servidor corporativo | **Se retira.** Es el punto 9 del checklist y la única regla que hoy se incumple |

**Lo que no se lleva a ninguna parte:** las tres implementaciones paralelas del cálculo.
Hoy quedan dos escritas (el motor Python y las vistas SQL) atadas por una compuerta de 17
puntos con diferencia cero. Al migrar, la vista SQL es la que manda y el motor Python pasa
a ser **oráculo de verificación**, no una segunda fuente de verdad.

---

## 2. Lo que se lleva tal cual, y por qué se puede

### 2.1 El cálculo, ya escrito en T-SQL

Las dos reglas del área están implementadas una sola vez en `ehs.v_kpi_ytd` y
`ehs.v_kpi_mensual`:

- YTD como **suma de numeradores dividida por suma de denominadores**, nunca el promedio
  de las razones mensuales.
- Los agregados suman **magnitudes crudas** y dividen al final. El ratio nacional no es el
  promedio de los ratios de los sitios.

Verificado con `verificar_sql_contra_motor.py`: **17 puntos, diferencia cero**. Esa es la
compuerta de migración que exige R.5.5.2, y ya está en verde antes de que exista el
servidor.

### 2.2 El contrato de la API

Nueve GET, con parámetros validados contra lista blanca y errores en español con forma
fija. No calculan: piden al adaptador y serializan. Portarlos a SAMII no cambia una línea
de lógica de negocio.

### 2.3 El interruptor

```js
// app\src\datos\index.js
module.exports = origen === 'sql' ? require('./adaptador_sql') : require('./adaptador_json');
```

El día que el esquema `ehs` exista y `adaptador_sql.js` esté completo, la migración de la
capa de datos es **una variable de entorno**. No hay que tocar rutas, plantilla ni cliente.
La correspondencia función a vista ya está escrita en la cabecera de `adaptador_sql.js`.

---

## 3. Lo que se adapta

| Qué | Por qué no va tal cual |
|---|---|
| Plantilla y CSS | SAMII tendrá su propio armazón, su cabecera y su navegación. Lo que se conserva es el **cuerpo**: las cinco vistas, el orden de lectura y las siete distinciones de `REFERENCIA-TABLERO-VERCEL.md` |
| Servidor HTTP | `servidor.js` y `api\servidor.js` son dos envolturas del mismo enrutador. En SAMII se sustituyen por su punto de entrada; `src\aplicacion.js` sobrevive |
| Gráficas | ECharts 5.6.0 vendorizado. Si SAMII ya estandarizó Chart.js, `public\js\graficos.js` es el **único** archivo a reescribir: es una fábrica, no está mezclado con la lógica |
| Correcciones | El CSV pasa a tabla `ehs.correccion` con las mismas columnas y la misma guarda. El mecanismo no cambia: se declara qué valor se esperaba y si el origen ya no lo trae, no se aplica |

---

## 4. Lo que hay que añadir, y hoy no existe

### 4.1 Reutilizar lo que el DWH ya tenga

`ehs.dim_fecha` y `ehs.dim_sitio` están escritas, pero puede que el DWH ya tenga una
dimensión fecha y una dimensión centro corporativas. **Si existen, se usan esas** y las
propias se retiran: crear una segunda dimensión fecha es exactamente el tipo de duplicado
que el estándar quiere evitar. Es una decisión del DBA, no del área.

### 4.2 La puerta de ingesta

Hoy el dato entra por lectura local de un `.xlsx`, que no es ninguna de las tres puertas
del estándar. Falta decidir cuál será: Lista de SharePoint leída por un JOB, o captura
directa por el módulo de Formularios de SAMII. Es el punto 6 del checklist y no se decide
por defecto.

### 4.3 El histórico anterior a 2026

`hecho_lectura_mensual_hist` está creada y vacía. El scorecard corporativo trae 2023-2025
y no está cargado. Requiere el contrato de exportación con el dueño del dato.

### 4.4 El desglose de residuos ya no necesita nada

`residuosComposicion` no consulta una tabla nueva: las tres magnitudes de residuo ya son
filas de `ehs.hecho_lectura_mensual`. Agrupar por magnitud es una consulta, no un modelo.
Es un ejemplo de por qué la tabla de hechos guarda magnitudes crudas y no ratios: el día
que alguien pregunta «¿de qué está hecho?», la respuesta ya está en la base.

### 4.5 Las lecturas diarias de agua

El área lleva el registro y la vista ya está construida para leerlo: `ehs.v_agua_diaria`,
`ehs.v_estado_agua_diaria`, el endpoint `/api/ehs/agua-diaria` y el panel que hoy se rotula
**«próximamente»**. Con cero lecturas devuelve cero filas, que es lo correcto. Se enciende
solo en cuanto el registro entre; no hay que programar nada más.

---

## 5. El orden, con compuertas

Cada paso tiene una condición de salida verificable. Ninguno empieza sin que el anterior
esté en verde.

| # | Paso | Compuerta |
|---|---|---|
| 1 | Esquema `ehs` creado en el servidor que indique el DBA | `01-esquema.sql` corre sin error; las dimensiones compartidas están resueltas |
| 2 | Carga inicial del 2026 | El conteo de filas coincide con `hechos_mensual_2026.csv` |
| 3 | Vistas desplegadas | `verificar_sql_contra_motor.py` apuntando al servidor real: **17 de 17, diferencia cero** |
| 4 | `adaptador_sql.js` completo | Los 9 endpoints devuelven **byte a byte** lo mismo con `ORIGEN_DATOS=sql` que con `json` |
| 5 | JOB de ingesta programado | Dos ejecuciones seguidas no duplican filas (idempotencia, R.5.3.3) y `ehs.carga_log` registra ambas |
| 6 | Tablero servido desde SAMII | Las cinco vistas cargan, sin errores de consola, y el dato coincide con el interinato |
| 7 | Retiro de Vercel | El proyecto `_deploy-web1` se elimina. Cierra el punto 9 del checklist |

El paso 4 es el que convierte esto en una migración y no en una construcción: la
comparación byte a byte contra el interinato es posible **porque el interinato sirve el
mismo contrato**. Sin ese diseño, el paso 4 sería «volver a probarlo todo a mano».

---

## 6. Las preguntas

No se responden por suposición (sección 8 del estándar). Están ordenadas por lo que
bloquean.

### 6.1 Bloquean el paso 1 — el esquema

1. ¿EHS tiene base propia, esquema dentro de una base compartida, o entra en la de Supply?
2. ¿Los permisos son DML y DDL, o solo lectura sobre vistas?
3. ¿Existen dimensión fecha y dimensión sitio o centro corporativas que deba reutilizar en
   vez de crear las mías?
4. ¿Cómo se organizan las capas internas del DWH y qué convención de nombres siguen?
5. ¿Cuál es el paso de objetos de base de datos de desarrollo a producción?

### 6.2 Bloquean el paso 4 — el adaptador

6. ¿Qué driver aprueba IT para conectar Node con SQL Server? No se elige por cuenta propia
   (R.3.4): sería introducir una dependencia fuera de la tabla del estándar.
7. ¿SAMII ya tiene una capa de consulta propia que sustituya entero a `adaptador_sql.js`?
8. ¿Servidor, base y credenciales de solo lectura para la aplicación?

### 6.3 Bloquean el paso 5 — la ingesta

9. ¿La Lista de SharePoint es un origen aceptable para un JOB, o IT prefiere que la
   captura entre directamente por el módulo de Formularios?
10. ¿Cómo resuelve IT hoy la extracción desde SharePoint: Graph API, Power Automate,
    lectura programada?
11. ¿Qué ventanas de ejecución están libres para un JOB de EHS?
12. ¿Con qué se orquestan los ETL, y hay bitácora de cargas estándar que deba usar en vez
    de `ehs.carga_log`?
13. ¿Qué datos de laboratorio ya viven en el DWH: producción, horas-hombre, consumos? Si
    producción ya está, el denominador de todos los KPI deja de depender del Excel.

### 6.4 Bloquean el paso 6 — la superficie

14. ¿Cuál es el camino para que EHS tenga una rama en SAMII, y quién acompaña?
15. ¿La rama es sobre el repositorio completo de SAMII o hay repos separados por módulo?
16. ¿Cómo se levanta SAMII en local? ¿Es `PRUEBAS SAMII` ese ambiente?
17. ¿SAMII usa Chart.js o ECharts, y hay un componente de gráfico ya estandarizado?
18. ¿Hay plantillas de dashboard ya hechas para reutilizar?
19. ¿Power BI y SAMII conviven, o SAMII es el destino de los tableros nuevos? ¿Hay ya un
    patrón de Power BI leyendo del DWH, o EHS sería el primero?

### 6.5 Para el histórico

20. ¿Dónde aterriza un histórico migrado: esquema dentro del DWH, base propia, o SAMII?
21. ¿Se puede fijar un contrato de exportación (columnas, grano, formato, corte anual) con
    el dueño del dato?
22. ¿La migración la ejecuta el implementador con credenciales, o se entregan los scripts?

### 6.6 Para el área de EHS, no para IT

23. **La banda de «en riesgo» no significa lo mismo en los dos sitios donde está escrita**,
    y hay que decidir cuál queda:
    - El tablero marca *en riesgo* lo que está **hasta 10 % por debajo** del techo: aún
      cumple, pero se está acercando. Es una alerta temprana.
    - `ehs.v_kpi_contra_meta` marca *en riesgo* lo que está **hasta 5 % por encima**: ya
      incumplió, pero por poco. Es una atenuación.

    No es un error de cálculo: los valores y las brechas coinciden en los 17 puntos de
    control, solo difiere la etiqueta. Pero son dos lecturas opuestas y no pueden convivir.
    Hoy manda la del tablero, que es la que el área aprobó. Se decide y se iguala en el
    lugar que quede.
24. ¿El juego de metas vigente es el que visualiza el libro (`KPIs 2026!F14:H14`) o el de
    `indicadores!C41:C43`, que ninguna fórmula referencia? Está pendiente desde la
    auditoría del Excel.
25. ¿`AT 2026!L9` se corrige en el origen? Es el accidente de mayo en Celta escrito a mano
    como 0 cuando la hoja cruda registra 1. El total del año coincide; el mes no.

---

## 7. Lo que este interinato deja probado

No es una lista de intenciones. Es lo que ya funciona y se puede enseñar en la reunión:

- **El cálculo en un solo lugar.** El cliente no calcula: pide y dibuja. Verificable
  abriendo `public\js\tablero.js` y buscando una fórmula de KPI: no hay ninguna.
- **La compuerta de migración, en verde antes de migrar.** 17 puntos, diferencia cero.
- **Los guardarraíles, probados en negativo.** Con una cifra inyectada en la plantilla o en
  el cliente, `validar_sin_hallazgos.py` falla. Y sus cifras no están escritas: se
  regeneran del dato publicado.
- **La corrección autorizada, con su ciclo entero.** Se declaró, se aplicó, el área
  corrigió el origen, la guarda lo detectó y la corrección se retiró. La franja de la
  interfaz se apagó sola.
- **«Sin dato» no es cero.** En ningún punto del recorrido.
- **El incumplimiento declarado.** Vercel está fuera del tenant, se dice en el checklist,
  lleva `noindex` y tiene fecha de retiro.
