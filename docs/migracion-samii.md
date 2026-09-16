# Migrar al servidor de la empresa: qué se lleva, qué se adapta, qué se sustituye

Este documento existe para que la implementación real **no empiece de cero**. Lo que hoy
corre en Vercel no es un prototipo desechable: es la misma arquitectura que pide el
estándar, construida con el mismo stack, con el cálculo detrás de un adaptador y el dato
en un contrato explícito. Migrar consiste en cambiar de dónde salen los datos y dónde se
sirve la página. La lógica del área ya está escrita, verificada y probada en negativo.

Fecha: 30 de agosto de 2026 · Contra `ESTANDARINTEGRACION.md` y el hilo con IT del 3 de
julio al 26 de agosto.

> **Actualizado el 10 de septiembre de 2026 — decisión de despliegue tomada.** El destino
> de la fase 1 es el **servidor propio de la empresa**, no el módulo Dashboards de SAMII.
> El tablero se despliega **tal como está hoy**, sin adaptarlo a ningún otro armazón: las
> mismas pantallas, el mismo enrutador, las mismas gráficas. Lo único que cambia entre el
> interinato de Vercel y esta fase 1 es **dónde corre** la misma aplicación.
>
> Eso hace que la sección 3 de abajo («lo que se adapta a SAMII») quede en suspenso para
> esta fase: nada de eso aplica mientras el destino sea un servidor propio. Se conserva
> escrita porque una integración con SAMII sigue siendo una evolución posible más
> adelante, no porque sea el plan actual. El resto del documento —el esquema, las vistas,
> el contrato de la API, la puerta de ingesta— no cambia con esta decisión: es exactamente
> lo mismo, sirva el front desde donde sirva.

---

## 1. El resumen en una tabla

| Pieza que existe hoy | Destino | Acción |
|---|---|---|
| `app\sql\01-esquema.sql` — 12 tablas del esquema `ehs` | Instancia SQL Server que asigne IT | **Se lleva tal cual**, salvo dimensiones que IT ya tenga (§4.1) |
| `app\sql\02-vistas.sql` — 10 vistas analíticas | Misma instancia | **Se lleva tal cual.** Es la única implementación definitiva del cálculo |
| `app\sql\03-carga-inicial.sql` — el histórico 2026 | Misma instancia | **Se lleva**, previa conciliación con el DBA. No se versiona: son cifras, y se genera |
| `app\sql\04-ingesta.sql` — la puerta de escritura | Misma instancia | **Se lleva tal cual.** Probado ejecutando contra SQL Server real (§4.2) |
| `app\src\rutas_api.js` — los 9 GET del contrato | Servidor propio (fase 1) | **Se lleva tal cual, sin adaptar.** No calcula: valida y sirve |
| `app\src\datos\adaptador_sql.js` | Servidor propio | **Ya está completo** y verificado: 38 de 38 rutas dan lo mismo que el interinato |
| `app\src\datos\adaptador_json.js` | — | **Se retira** cuando el SQL responda. Es el interinato |
| `app\views\`, `app\public\` — plantilla, CSS y ECharts | Servidor propio | **Se lleva tal cual, sin adaptar.** No hay armazón ajeno que absorber en fase 1 |
| `analisis\*.py` — el pipeline desde Excel | JOB del DWH (cuando exista) | **Se sustituye** por el JOB, salvo `verificar_sql_contra_motor.py` y `verificar_vistas_motor_real.py`, que quedan de oráculo |
| `datos\correcciones.csv` y su guarda | Tabla `ehs.correccion` | **Se adapta**: el mecanismo se conserva, el archivo se vuelve tabla |
| `app\datos\bitacora.jsonl` | `ehs.carga_log` | **Se sustituye.** La tabla ya está escrita en el esquema |
| Despliegue en Vercel | Servidor corporativo (fase 1) | **Se retira.** Es el punto 9 del checklist y la única regla que hoy se incumple |

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
fija. No calculan: piden al adaptador y serializan. Llevarlos al servidor propio no
cambia una línea de lógica de negocio, y tampoco lo haría llevarlos a SAMII el día que
esa integración exista.

### 2.3 El interruptor

```js
// app\src\datos\index.js
module.exports = origen === 'sql' ? require('./adaptador_sql') : require('./adaptador_json');
```

El día que el esquema `ehs` exista y `adaptador_sql.js` esté completo, la migración de la
capa de datos es **una variable de entorno**. No hay que tocar rutas, plantilla ni cliente.
La correspondencia función a vista ya está escrita en la cabecera de `adaptador_sql.js`.
**Ya está completo** desde el 10 de septiembre: las 38 peticiones que cubren las 9 rutas
dan exactamente lo mismo con `ORIGEN_DATOS=json` que con `ORIGEN_DATOS=sql`
(`comparar_adaptadores.py`).

### 2.4 Cómo se ejecuta en el servidor propio

`servidor.js` es el artefacto de esta fase: un servidor HTTP autocontenido
(`node servidor.js`), sin nada de Vercel de por medio. Es literalmente el mismo comando
con el que se ha probado toda esta arquitectura durante esta sesión, apuntando a un SQL
Server real. Lo que hace falta del lado de IT, cuando exista el servidor:

| Variable de entorno | Para qué |
|---|---|
| `PUERTO` | El puerto donde escucha (por defecto 3000) |
| `ORIGEN_DATOS=sql` | Activa `adaptador_sql.js` en vez del interinato JSON |
| `SQL_SERVIDOR`, `SQL_BASE` | Host y nombre de la base con el esquema `ehs` |
| `SQL_USUARIO`, `SQL_CLAVE` | Credenciales de la aplicación. Solo lectura para servir el tablero; escritura solo si la puerta de captura se activa en este servidor (R.5.3.1) |
| `SQL_CIFRAR`, `SQL_CONFIAR_CERT` | Según la política TLS de la instancia que asigne IT |

Nada de esto exige un proceso especial: es Node 22.19.0, el driver `mssql` (la única
dependencia nueva, pendiente de acordar con IT por R.3.4 — ver `docs/09-…`, sección 6.3),
y un proceso que IT mantenga vivo con lo que ya use para sus otros servicios —Windows
Service, un administrador de procesos, o lo que sea su estándar. No hay nada de esta
aplicación que exija una plataforma en particular; por eso la fila 12 del formulario de
levantamiento («Sistema operativo») queda abierta a lo que IT ya tenga.

---

## 3. Lo que se adapta

**En fase 1 (servidor propio), nada de esta sección aplica.** El tablero se despliega tal
como está: `servidor.js` es exactamente el punto de entrada que hace falta —ya es un
servidor HTTP autocontenido, sin depender de la función serverless de Vercel
(`api\servidor.js`, que solo existía para ese despliegue concreto y se retira con él—.
Esta tabla queda escrita para el día en que una integración con SAMII sea el plan, no
antes:

| Qué | Por qué no iría tal cual, si algún día se integra en SAMII |
|---|---|
| Plantilla y CSS | SAMII tendría su propio armazón, su cabecera y su navegación. Lo que se conservaría es el **cuerpo**: las cinco vistas, el orden de lectura y las siete distinciones de `docs/referencia-tablero-vercel.md` |
| Servidor HTTP | `servidor.js` es el punto de entrada para el servidor propio. Si en el futuro el destino fuera SAMII, se sustituiría por el suyo; `src\aplicacion.js` (el enrutador) sobreviviría igual |
| Gráficas | ECharts 5.6.0 vendorizado. Si algún día SAMII exige Chart.js, `public\js\graficos.js` es el **único** archivo a reescribir: es una fábrica, no está mezclado con la lógica |
| Correcciones | El CSV pasa a tabla `ehs.correccion` con las mismas columnas y la misma guarda. El mecanismo no cambia: se declara qué valor se esperaba y si el origen ya no lo trae, no se aplica |

---

## 4. Lo que hay que añadir, y hoy no existe

### 4.1 Reutilizar lo que el DWH ya tenga

`ehs.dim_fecha` y `ehs.dim_sitio` están escritas, pero puede que el DWH ya tenga una
dimensión fecha y una dimensión centro corporativas. **Si existen, se usan esas** y las
propias se retiran: crear una segunda dimensión fecha es exactamente el tipo de duplicado
que el estándar quiere evitar. Es una decisión del DBA, no del área.

### 4.2 La tabla de rechazos ya está, y desde septiembre la validación que la llena también

`ehs.lectura_rechazada` y `ehs.v_rechazo_pendiente` existían desde el principio, pero
vacías de sentido: nada las llenaba. Ahora sí. **`app\sql\04-ingesta.sql`** trae
`ehs.sp_capturar_lote`, que valida, graba lo válido, aparta lo inválido con su motivo y
deja bitácora, todo en la misma transacción.

Lo importante es que esa validación **no depende de qué puerta de ingesta elija IT**. Si
el dato entra por formulario de SAMII, el formulario llama al procedimiento. Si entra por
un JOB desde SharePoint, el JOB llama al procedimiento. Si entra por el formulario propio
de esta aplicación, igual. Es el mismo movimiento que ya funcionó con las nueve vistas:
escribir la pieza que sobrevive a las tres respuestas posibles, y dejar reversible lo que
depende de la que llegue.

Probado ejecutando contra SQL Server 2022, no solo escrito:

| Regla | Prueba |
|---|---|
| R.5.3.3 idempotencia | Reenviar el mismo lote graba 0 filas |
| R.5.3.4 bitácora | `carga_log` con quién, cuándo, cuántas, cuántas apartadas |
| R.5.3.5 rechazos | 7 apartadas con motivo; las otras 3 entraron igual |
| R.5.3.6 vacío ≠ cero | La celda en blanco se rechaza con ese motivo exacto |

**Y trae una distinción que el diseño anterior no hacía.** Un residuo negativo es
imposible y se rechaza siempre. Un consumo del doble del máximo histórico es solo
improbable: puede ser un cero de más al teclear y puede ser una fuga real. Ése vuelve como
**advertencia** y entra solo si quien captura lo confirma, y la confirmación queda escrita
en el origen de la fila. Rechazarlo dejaría el mes sin capturar y sin nada que corregir en
el origen.

### 4.3 La puerta de ingesta

Hoy el dato entra por lectura local de un `.xlsx`, que no es ninguna de las tres puertas
del estándar. Falta decidir cuál será, y **es la decisión con más consecuencias de todo el
proyecto** — más que dónde vive la base de datos, que a este volumen es casi indiferente.
La lección de Supply Chain, en el propio estándar, dice por qué: el cuello de botella fue
la extracción y la dependencia de que una persona actualizara su archivo, no el
procesamiento.

Lo que ya no falta es la pieza de destino: el procedimiento de 4.2 está escrito y probado,
y una pantalla de captura funcionando (`/captura`) demuestra el flujo de punta a punta. Lo
que falta es la respuesta de IT a la pregunta 8.3 del estándar.

El análisis completo de las opciones —incluido el hecho de que la API `/workbook/` de
Microsoft Graph **no admite permisos de aplicación**, que invierte la respuesta obvia—
está en `..\..\docs\09-evaluacion-y-arquitectura-objetivo.md`, sección 4.

### 4.4 El histórico anterior a 2026

`hecho_lectura_mensual_hist` está creada y vacía. El scorecard corporativo trae 2023-2025
y no está cargado. Requiere el contrato de exportación con el dueño del dato.

### 4.5 El desglose de residuos ya no necesita nada

`residuosComposicion` no consulta una tabla nueva: las tres magnitudes de residuo ya son
filas de `ehs.hecho_lectura_mensual`. Agrupar por magnitud es una consulta, no un modelo.
Es un ejemplo de por qué la tabla de hechos guarda magnitudes crudas y no ratios: el día
que alguien pregunta «¿de qué está hecho?», la respuesta ya está en la base.

### 4.6 Las lecturas diarias de agua

El área lleva el registro y la vista ya está construida para leerlo: `ehs.v_agua_diaria`,
`ehs.v_estado_agua_diaria`, el endpoint `/api/ehs/agua-diaria` y el panel que hoy se rotula
**«próximamente»**. Con cero lecturas devuelve cero filas, que es lo correcto. Se enciende
solo en cuanto el registro entre; no hay que programar nada más.

---

## 5. El orden, con compuertas

Cada paso tiene una condición de salida verificable. Ninguno empieza sin que el anterior
esté en verde.

| # | Paso | Compuerta | Ensayada |
|---|---|---|---|
| 1 | Esquema `ehs` creado en el servidor que indique el DBA | `01-esquema.sql` corre sin error; las dimensiones compartidas están resueltas | **Sí** |
| 2 | Carga inicial del 2026 | El conteo de filas coincide con `hechos_mensual_2026.csv` | **Sí** |
| 3 | Vistas desplegadas | `verificar_vistas_motor_real.py` contra el motor: **17 de 17, diferencia cero** | **Sí** |
| 4 | `adaptador_sql.js` completo | `comparar_adaptadores.py`: las 9 rutas dan lo mismo con `ORIGEN_DATOS=sql` que con `json` | En curso |
| 5 | JOB de ingesta programado | Dos ejecuciones seguidas no duplican filas (R.5.3.3) y `ehs.carga_log` registra ambas | **Sí**, vía `sp_capturar_lote` |
| 6 | Tablero servido desde el servidor de la empresa | Las cinco vistas cargan, sin errores de consola, y el dato coincide con el interinato | No: requiere el servidor y las credenciales de IT |
| 7 | Retiro de Vercel | El proyecto `_deploy-web1` se elimina. Cierra el punto 9 del checklist | No |

**La columna «Ensayada» es nueva, y es el cambio de fondo de septiembre de 2026.** Los
pasos 1, 2, 3 y 5 ya se ejecutaron de principio a fin sobre **SQL Server 2022 real**, en
un contenedor local, con los archivos de `app\sql\` sin modificar una coma. No es una
simulación del plan: es el plan corrido. Lo que falta en el servidor de IT es la
infraestructura, no la verificación.

Ese ensayo encontró algo que ninguna comprobación anterior podía encontrar:
`03-carga-inicial.sql` traía **un accidente en julio que el área ya había corregido a
cero**. El archivo se generó antes de la corrección y nunca se regeneró, y la prueba en
DuckDB no lo veía porque construye sus tablas desde los CSV, no desde el archivo de carga.
Regenerado, los 17 puntos coinciden. Un guardarraíl que solo prueba el álgebra no prueba
el archivo que alguien va a ejecutar.

El paso 4 es el que convierte esto en una migración y no en una construcción: la
comparación contra el interinato es posible **porque el interinato sirve el mismo
contrato**. Sin ese diseño, el paso 4 sería «volver a probarlo todo a mano».

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

### 6.2 Bloquean el paso 4 y el paso 6 — el adaptador y el servidor propio

6. ¿Qué driver aprueba IT para conectar Node con SQL Server? No se elige por cuenta propia
   (R.3.4): sería introducir una dependencia fuera de la tabla del estándar.
7. **El servidor propio en sí** (fase 1, decidido): ¿qué servidor —físico, VM o
   contenedor— se asigna para correr `servidor.js`, con qué sistema operativo, y quién lo
   administra? Es la pregunta que de verdad bloquea el paso 6 ahora.
8. Servidor, base y credenciales de SQL Server para la aplicación: de solo lectura para
   servir el tablero, y de escritura si la puerta de captura (`04-ingesta.sql`) se activa
   ahí mismo.

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

### 6.4 Para una futura integración con SAMII — no bloquean el plan actual

Con la fase 1 decidida en servidor propio, estas preguntas dejan de ser urgentes. Se
conservan porque una integración con SAMII sigue siendo una evolución posible, y el día
que se retome, la conversación ya está preparada:

14. ¿Cuál sería el camino para que EHS tenga una rama en SAMII, y quién acompaña?
15. ¿La rama sería sobre el repositorio completo de SAMII o hay repos separados por módulo?
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
