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
| `src\aplicacion.js` | El enrutador. Solo GET. |
| `src
utas_api.js` | Los nueve GET del contrato. Validan y sirven; no calculan. |
| `src\datos\index.js` | Elige origen según `ORIGEN_DATOS` (`json` por defecto, `sql` cuando exista). |
| `src\datos\adaptador_json.js` | Rebana la vista materializada del pipeline. |
| `src\datos\adaptador_sql.js` | Esqueleto del destino: mismas nueve firmas contra las vistas `ehs.v_*`. |
| `src\paginas.js` | Renderiza `views\dashboard.ejs`. |
| `views\` | La plantilla y sus parciales. Marcado, sin cifras. |
| `public\css\ehs.css` | El sistema visual, extraído tal cual de la propuesta aprobada. |
| `public\js\formato.js` | Números, meses y escapado. Lo usan los otros tres. |
| `public\js	ablero.js` | Pide, dibuja y redacta el texto analítico por ramas sobre el dato servido. |
| `public\js\graficos.js` | Fábrica de gráficas ECharts: tema propio, techo sombreado, mapa de calor. |
| `public\js\franja_correccion.js` | La franja de «valor corregido». Con la lista vacía no pinta nada. |
| `public\vendor\echarts.min.js` | ECharts 5.6.0, servido desde el propio dominio. |
| `datos\` | El dato publicado. No se versiona. |
| `sql\` | El esquema y las vistas. Pasar a producción es ejecutar estos scripts. |
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

## Comprobaciones

```powershell
npm run lint                              # ESLint
npm run format:check                      # Prettier
cd ..
python analisis\validar_sin_hallazgos.py   # ninguna cifra escrita a mano
python analisis\verificar_sql_contra_motor.py   # 17 puntos, diferencia cero
```

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
