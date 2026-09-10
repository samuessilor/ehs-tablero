# Tablero EHS — aplicación Node

La versión del tablero construida sobre el stack que exige `ESTANDARINTEGRACION.md`:
Node, EJS, CSS y JavaScript planos, y ECharts para las gráficas. Sustituye al HTML
autocontenido de `web\propuesta-1\index.html`, que se queda como referencia visual.

La diferencia de fondo no es la tecnología: es **dónde se calcula**. Antes el navegador
recalculaba los KPI al filtrar. Ahora pide `/api/ehs/*` y solo dibuja.

---

## Arrancar

```powershell
cd app
npm install
node servidor.js            # http://localhost:3000
$env:PUERTO = 3210; node servidor.js   # si el 3000 esta ocupado
```

## Actualizar el dato cuando llegue el Excel del mes

Un solo camino, y ninguno de sus pasos es manual:

```powershell
cd ..
python analisis\construir_datos.py       # lee el .xlsx y aplica correcciones autorizadas
python analisis\construir_referencia.py
python analisis\calcular_kpi.py          # 12 puntos de control: aborta si algo no cuadra
python analisis\estrella.py
python analisis\web_json.py              # arma la vista materializada
python analisis\agua_detalle.py
python analisis\publicar_a_app.py        # copia a app\datos y deja bitacora
cd app
npx vercel --prod
```

`publicar_a_app.py` es la única puerta: verifica el corte, la marca de tiempo y el bloque
`contraMeta` antes de copiar, y escribe una línea en `datos\bitacora.jsonl` con lo que
movió. Si el Excel trae un número distinto al que espera una corrección autorizada, la
corrección **no se aplica** y el pipeline lo dice en pantalla.

Detalle del ciclo completo: `docs\proceso-actualizacion.md`.

## Qué hay dentro

| Ruta | Qué es |
|---|---|
| `servidor.js` | Servidor local. `node:http` y nada más. |
| `api\servidor.js` | El mismo tablero como función de Vercel. Cero lógica propia. |
| `src\aplicacion.js` | El enrutador. Solo GET, salvo la única ruta que escribe. |
| `src\rutas_api.js` | Los nueve GET del contrato. Validan y sirven; no calculan. |
| `src\rutas_captura.js` | La **única** superficie de escritura: un POST y dos GET. |
| `src\validacion.js` | Las reglas de frontera de la captura, como datos, en un solo sitio. |
| `src\datos\index.js` | Elige origen de **lectura** según `ORIGEN_DATOS` (`json` por defecto). |
| `src\datos\escritura.js` | Elige destino de **escritura** con la misma variable. |
| `src\datos\adaptador_json.js` | Rebana la vista materializada del pipeline. |
| `src\datos\adaptador_sql.js` | El destino: mismas nueve firmas contra las vistas `ehs.v_*`. |
| `src\datos\escritura_sql.js` | Graba vía `ehs.sp_capturar_lote`. Nunca hace `insert` por su cuenta. |
| `src\datos\escritura_simulada.js` | Valida y **no guarda**. Devuelve el T-SQL que se ejecutaría. |
| `src\paginas.js` | Renderiza `views\dashboard.ejs` y `views\captura.ejs`. |
| `views\` | La plantilla y sus parciales. Marcado, sin cifras. |
| `public\css\ehs.css` | El sistema visual, extraído tal cual de la propuesta aprobada. |
| `public\js\formato.js` | Números, meses y escapado. Lo usan los otros tres. |
| `public\js\tablero.js` | Pide, dibuja y redacta el texto analítico por ramas sobre el dato servido. |
| `public\js\graficos.js` | Fábrica de gráficas ECharts: tema propio, techo sombreado, mapa de calor. |
| `public\js\franja_correccion.js` | La franja de «valor corregido». Con la lista vacía no pinta nada. |
| `public\js\captura.js` | La rejilla de 27 celdas: avisa al teclear, arma el lote y muestra el reparto. |
| `public\vendor\echarts.min.js` | ECharts 5.6.0, servido desde el propio dominio. |
| `datos\` | El dato publicado. No se versiona. |
| `sql\01` `02` `03` | Esquema, vistas y carga: la superficie de **lectura**. |
| `sql\04-ingesta.sql` | La superficie de **escritura**, aparte a propósito: se aprueba por separado. |
| `docs\` | El estándar, el checklist 7.2, el proceso y el plan de migración. |

## El contrato

Nueve GET. Todos devuelven JSON con la misma cabecera (`anio`, `corte`, `actualizado_en`,
`fuente`, `meta_vigente`) y errores en español con la forma `{error, mensaje, detalle}`.
**`anio` y `mes` son opcionales**: sin ellos, el adaptador resuelve el corte publicado.
Así el mes que avanza no obliga a editar código.

| Ruta | Parámetros | Devuelve |
|---|---|---|
| `/api/ehs/panorama` | `anio`, `mes`, `ambito` | Los cinco KPI con meta, brecha y estado resueltos |
| `/api/ehs/kpi-por-sitio` | `anio`, `mes`, `kpi` | Cada sitio contra **su** meta |
| `/api/ehs/serie-mensual` | `anio`, `ambito`, `kpi` | Doce meses; sin dato es `null`, nunca `0` |
| `/api/ehs/agua-mensual` | `anio`, `ambito` | Consumo, lentes, ratio y variaciones |
| `/api/ehs/agua-diaria` | `anio`, `mes`, `sitio` | Hoy: `disponible:false`, y lo dice |
| `/api/ehs/calidad-dato` | `anio` | Qué mes trae lectura, cuántas y de dónde |
| `/api/ehs/residuos-composicion` | `anio`, `ambito` | Peligroso, aprovechable y ordinario; las tres suman el KPI |
| `/api/ehs/trayectoria-anual` | `kpi` | Cierres 2023-2025 del scorecard y el año en curso, aparte |
| `/api/ehs/detalle` | `anio`, `formato=csv` | Las nueve magnitudes crudas |

## La captura

`/captura` es la pantalla donde EHS ingresa los 27 números del mes: nueve magnitudes por
tres sitios. Reemplaza el trasiego entre hojas del libro heredado, que es de donde salen
los seis defectos documentados.

Escribe por **una sola ruta**, `POST /api/ehs/captura`. Todo lo demás de la aplicación
sigue rechazando cualquier método que no sea GET, así que la superficie que escribe se
lee entera en un archivo.

**Lo que aparta y lo que solo avisa, que no es lo mismo.** Un residuo de −5 kg es
imposible: se rechaza siempre y se arregla en el origen (R.5.3.5). Un consumo del doble
del máximo histórico es improbable: puede ser un cero de más al teclear, y puede ser la
fuga que el indicador existe para detectar. Ése vuelve como **advertencia** y no se
graba hasta que quien captura lo confirma; la confirmación queda escrita en el origen de
la fila. Rechazarlo dejaría el mes sin capturar y sin nada que corregir.

**Una celda vacía no es un cero** (R.5.3.6). En blanco significa «todavía no llegó» y no
viaja en el lote. `0` significa que el valor medido fue cero.

**Dos destinos, misma pantalla:**

| `ORIGEN_DATOS` | Qué hace la captura |
|---|---|
| `sql` | Graba de verdad, vía `ehs.sp_capturar_lote`: idempotente, con rechazos y bitácora |
| cualquier otro | Valida con las mismas reglas, **no guarda**, y muestra el T-SQL que se ejecutaría |

El interinato usa el segundo, y eso no es una promesa de no escribir: es que **no existe
el camino**. El adaptador de escritura del interinato no sabe grabar, así que R.5.4.2 no
depende de que nadie se equivoque.

**La validación está escrita tres veces** —navegador, servidor y motor— porque las tres
hacen falta: el motor es la única que no se puede rodear, el servidor responde antes de
grabar medio mes, y el navegador avisa mientras se teclea. Que no se separen lo comprueba
`analisis\verificar_validacion_pareja.py`.

Para probarlo en local contra SQL Server de verdad:

```powershell
python ..\analisis\verificar_vistas_motor_real.py --levantar
$env:ORIGEN_DATOS="sql"; $env:SQL_SERVIDOR="localhost"; $env:SQL_BASE="EHS"
$env:SQL_USUARIO="sa"; $env:SQL_CLAVE="EhsLocal_2026#dev"
$env:SQL_CONFIAR_CERT="1"; $env:SQL_CIFRAR="0"
npm run dev
```

## Comprobaciones

```powershell
npm run lint                              # ESLint
npm run format:check                      # Prettier
cd ..
python analisis\verificar_todo.py                  # los siete de disco, en segundos
python analisis\verificar_todo.py --con-sql        # + ejecuta el SQL en SQL Server real
```

Las dos que importan para la migración:

| Script | Qué prueba |
|---|---|
| `verificar_vistas_motor_real.py` | Ejecuta `sql\*.sql` **sin modificar** en SQL Server 2022 y consulta las vistas resultantes: 17 de 17 |
| `comparar_adaptadores.py` | Levanta el tablero contra JSON y contra SQL y exige que las nueve rutas devuelvan lo mismo |

La segunda es la que convierte «migrar es cambiar una variable de entorno» de promesa en
comprobación. La primera existe porque `verificar_sql_contra_motor.py` prueba el
**álgebra** en DuckDB, no el archivo — y la primera vez que se ejecutó el archivo de
verdad, apareció en `03-carga-inicial.sql` un accidente de julio que el área ya había
corregido a cero.

`validar_sin_hallazgos.py` no lleva las cifras escritas: las **regenera** del dato
publicado. Vigila el HTML, las plantillas EJS fuera de `<% %>` y los módulos del cliente.
Está probado en negativo: con una cifra inyectada en la plantilla o en el JS, falla.

## Al clonar el repositorio

El dato **no viaja en el repositorio**: es información operativa de la empresa y queda
fuera de git. Un clon limpio trae la carpeta `datos` vacía, y la aplicación lo dice en vez
de reventar: responde **503** con el mensaje de qué falta y qué comando lo genera. Se
arregla corriendo el pipeline y `publicar_a_app.py`, como en el ciclo de cada mes.

## Dos cosas que conviene saber

**Node local contra Node de Vercel.** El estándar fija Node 22.19.0 y así está declarado
en `.nvmrc` y en `engines`. La máquina de desarrollo tiene la 24.14.1, por eso
`.npmrc` lleva `engine-strict=false`: si no, `npm install` se niega a instalar. Vercel sí
construye con 22. La diferencia está aquí escrita a propósito, no escondida.

**Vercel es interinato.** Publicar dato de EHS fuera del tenant incumple R.5.4.2. Es una
decisión tomada a conciencia mientras no exista la superficie interna, con `noindex` y con
fecha de retiro: la migración a SAMII. Está declarado en `docs\checklist-7.2.md` (punto 9)
y es lo primero que resuelve `docs\migracion-samii.md`.
