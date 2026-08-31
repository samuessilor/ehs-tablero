# Checklist 7.2 del estándar — aplicado al tablero EHS

Regla R.7.2.1: el checklist se aplica **antes** de tocar código y su resultado se
escribe. Columna **Antes** = el tablero desplegado hoy (HTML único autocontenido,
`web\propuesta-1\index.html`). Columna **Después** = la aplicación `app\` bajo el stack
del DBA. La columna Después se llena al terminar la construcción, no antes.

Evaluado: 30 de agosto de 2026, contra `ehs\ESTANDARINTEGRACION.md`.

| # | Comprobación | Regla | Antes (HTML autocontenido) | Después (app Node) |
|---|---|---|---|---|
| 1 | ¿El cálculo vive en la base de datos, y en un solo lugar? | R.5.2.1, R.5.2.2 | **Incumple.** El cálculo está CUATRO veces: motor Python (oráculo), vistas SQL (escritas, sin servidor aún), DAX (Power BI) y el JavaScript del cliente, que recalcula KPIs al filtrar | **Parcial, y mejor.** El cliente ya no calcula: pide a `/api/ehs/*` y dibuja. El adaptador rebana una vista materializada; ni una formula de KPI en `public/js`. Siguen escritas dos implementaciones del algebra (motor Python y `app\sql-vistas.sql`), atadas por la compuerta de 17 puntos. Queda **una sola** el dia que `adaptador_sql.js` sustituya al JSON: es un cambio de una linea (`ORIGEN_DATOS`) |
| 2 | ¿La tabla de hechos guarda magnitudes crudas, no ratios? | R.5.2.3 | **Cumple.** `hechos_mensual_2026.csv` guarda las 9 magnitudes crudas; los ratios se derivan | **Cumple.** Igual, y ahora ademas expuesto: `/api/ehs/detalle?formato=csv` devuelve las 9 magnitudes crudas tal como se capturaron |
| 3 | ¿Metas y parámetros están en tabla editable, no en código? | R.5.2.4 | **Cumple.** `datos\metas.csv` y scorecard; el front las lee del JSON, no las trae escritas | **Cumple.** Las metas viajan en el dato servido (`contraMeta`), no en la plantilla ni en el cliente. El validador lo comprueba: una meta escrita a mano en el EJS lo hace fallar |
| 4 | ¿La nomenclatura es snake_case, sin tildes ni ñ? | R.5.1.1, R.5.1.2 | **Parcial.** El SQL escrito sí; los CSV canónicos mezclan (`Dim_Sitio.csv` PascalCase). Sin tildes ni ñ en identificadores: cumple | **Cumple en la app.** Rutas en kebab-case, campos del contrato en snake_case (`kpi_id`, `valor_mes`, `brecha_pct`, `serie_ytd`), archivos sin tildes ni ñ. El pendiente heredado (`Dim_Sitio.csv`) sigue fuera de `app\` |
| 5 | ¿El stack coincide con la sección 3? ¿Gráficas en Chart.js o ECharts? | R.3.1, R.3.4 | **Incumple.** HTML+JS sin Node, sin EJS; gráficas en SVG dibujado a mano | **Cumple.** Node 22 declarado (`engines` y `.nvmrc`), EJS, CSS y JS planos, ECharts 5.6.0 servido desde el propio dominio. Una sola dependencia de ejecucion: `ejs`. ESLint y Prettier en verde. Sin Express: no esta en la tabla del estandar y el enrutador propio son 60 lineas |
| 6 | ¿Cada fuente entra por una sola de las tres puertas? | R.5.3.1 | **Parcial.** Una sola fuente (el Excel), pero entra por lectura local del pipeline, no por ninguna de las tres puertas del estándar. Transitorio declarado: la puerta SharePoint/formulario es la Fase 1-3 del plan | **Parcial, sin cambio.** Sigue siendo el mismo Excel leido en local. La puerta del estandar (SharePoint o formulario) es la Fase 1-3 del plan, no este interinato. Declarado, no disimulado |
| 7 | ¿La carga es idempotente y deja bitácora? | R.5.3.3, R.5.3.4 | **Parcial.** Idempotente sí (regenerar produce lo mismo); bitácora no hay — el pipeline imprime a consola y no persiste cuándo corrió ni cuántas filas movió | **Cumple.** `publicar_a_app.py` publica y deja `app\datos\bitacora.jsonl`: cuando corrio, que corte, que archivos, cuantas correcciones. Reejecutar produce lo mismo |
| 8 | ¿Se distingue «sin dato» de «cero»? | R.5.3.6 | **Cumple.** Meses sin captura no producen fila; el front deja hueco; agua diaria vacía se rotula «próximamente» | **Cumple.** Los meses sin captura viajan como `null`, nunca como 0; el mes sin lectura sale deshabilitado en el selector; el diario de agua se rotula «proximamente» con el estado que informa el servidor |
| 9 | ¿El dato real está dentro del tenant? | R.5.4.2 | **Incumple.** Desplegado en Vercel (fuera del tenant) por instrucción expresa del responsable como interinato. Con `noindex`. Fecha de retiro: la migración a SAMII | **Incumple, transitorio y con fecha.** Sin cambio de fondo: el dato sigue saliendo del tenant. Se mantiene la decision del responsable, con `X-Robots-Tag: noindex, nofollow` declarado en `vercel.json` y verificado tras desplegar. Fecha de retiro: la migracion a SAMII |
| 10 | ¿Hay datos personales expuestos? | R.5.4.3 | **Cumple.** El dato es agregado operativo (magnitudes por sitio/mes); no hay cédulas ni personas naturales | **Cumple.** Igual: magnitudes agregadas por sitio y mes |
| 11 | ¿Cada cifra publicada vive en un solo lugar? | R.5.5.3 | **Parcial.** El dato vive en el JSON generado, pero está EMBEBIDO en dos HTML (propuesta-1 y 2) y hubo un episodio real de desincronización (JSON congelado del 25-ago). `embeber_datos.py` lo mitiga; no lo elimina | **Cumple.** Se acabo el embebido. El dato vive en `app\datos\*.json` y la pagina lo pide; no hay una segunda copia dentro del HTML que pueda quedarse atras. El episodio de desincronizacion de agosto ya no tiene donde ocurrir |
| 12 | ¿La migración, si la hay, tiene compuerta que pase sin diferencias? | R.5.5.2 | **Cumple.** `verificar_sql_contra_motor.py`: 17 puntos, diferencia cero. Pendiente actualizar 2 valores por el Excel final (accidentes julio) | **Cumple.** 17 de 17, diferencia cero, con los dos valores de julio ya actualizados al Excel final (`frequency_rate` 0,6133 y accidentes 1) |
| 13 | ¿Los guardarraíles están probados en negativo? | R.5.5.4 | **Cumple.** `validar_tmdl` (comentario reinyectado), `validar_sin_hallazgos` (veredicto inyectado), `validar_texto` (se pilló a sí mismo). La guarda de correcciones se prueba en negativo en este mismo trabajo: detecta que la corrección de julio ya no aplica | **Cumple, con uno nuevo.** `validar_sin_hallazgos.py` ahora vigila tambien plantillas y cliente, y sus cifras **se regeneran del dato publicado** en vez de estar escritas. Probado en negativo hoy: cifra inyectada en el EJS y en el JS, salida 1 en ambos; retiradas, salida 0 |
| 14 | ¿El SQL está versionado como archivos? | R.4.3 | **Cumple.** `app\sql\01-esquema.sql`, `02-vistas.sql`, `03-carga-inicial.sql` (generado, no tecleado) | **Cumple, y ahora de verdad.** El SQL vivia FUERA del repositorio que se entrega: lo que llega a IT es `app\`, y el esquema y las vistas se quedaban atras. Ahora estan en `app\sql\`. La carga inicial no se versiona: son cifras de la empresa (R.5.4.1) y se genera |
| 15 | ¿La solución sirve para otra área, o tiene el área incrustada? | R.1.2 | **Parcial.** El modelo separa genérico de específico (magnitud/KPI en tabla), pero el front tiene los 5 KPI de EHS en su estructura de vistas. Aceptable: la vista ES del área; el modelo no | **Parcial, sin cambio.** El contrato de la API es generico (ambito, kpi, mes); las cinco vistas si son de EHS. La vista ES del area; el modelo no |

## Resumen despues

- **Cumple:** 11 (2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14) · **Parcial:** 3 (1, 6, 15) ·
  **Incumple:** 1 (9, transitorio aceptado con fecha de retiro).
- Los dos incumplimientos que este trabajo se propuso atacar quedan cerrados: **#5** con el
  stack completo del estandar y **#1** a medias por construccion, no por descuido — el
  cliente dejo de calcular y el algebra quedo detras de un adaptador con nueve firmas; la
  ultima mitad la cierra el `adaptador_sql` cuando exista el esquema, sin tocar la vista.
- **#9 sigue rojo a proposito.** Es la unica regla que este interinato no puede cumplir, y
  se declara en el propio tablero, en este checklist y en el documento de migracion.
- Lo que quedo *Parcial* no es deuda oculta: **#6** espera la puerta de ingesta que decide
  IT y **#15** es una eleccion, no un defecto.

## Resumen antes

- **Cumple:** 6 (2, 3, 8, 10, 13, 14) · **Parcial:** 5 (4, 6, 7, 11, 15) · **Incumple:** 3 (1, 5, 9) · Compuerta (12) verde con 2 valores por refrescar.
- Los tres incumplimientos son exactamente lo que este trabajo ataca: #1 y #5 se corrigen
  con la app (una implementación del cálculo en la capa de datos, stack del DBA, ECharts);
  **#9 no se corrige aquí**: queda como incumplimiento transitorio aceptado por decisión
  del responsable, con fecha de retiro = migración a SAMII. No se silencia.
