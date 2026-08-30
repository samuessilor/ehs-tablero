# El ciclo de actualización: qué pasa cuando llega el Excel del mes

Un solo camino, siete pasos, ninguno manual. Lo que se pide del área es exactamente una
cosa: dejar el libro nuevo en su sitio. Todo lo demás lo hace el pipeline, y si algo no
cuadra se detiene en vez de publicar un número dudoso.

```
Excel del mes                                     el area lo deja en  ehs\
      |
      v
construir_datos.py        lee las 9 magnitudes crudas por sitio y mes
      |                   aplica las correcciones autorizadas de datos\correcciones.csv
      |                   >>> si el Excel ya no trae el valor que la correccion esperaba,
      |                       NO la aplica y lo dice. La correccion caduca sola.
      v
construir_referencia.py   metas, scorecard e historico
      v
calcular_kpi.py           los 5 KPI, mensual y YTD, por sitio y por agregado
      |                   >>> 12 puntos de control contra el propio Excel.
      |                       Si uno falla, ABORTA. No hay publicacion a medias.
      v
estrella.py               modelo en estrella (hechos y dimensiones) para BI
      v
web_json.py               la vista materializada: contraMeta, calidad, detalleCrudo
      v
agua_detalle.py           la hoja de agua del area
      v
publicar_a_app.py         copia a app\datos\  +  linea en app\datos\bitacora.jsonl
      v
npx vercel --prod         el mismo proyecto, el mismo enlace
```

## El comando, entero

```powershell
cd C:\Users\samuel\EssilorLuxottica\ehs\entrega-reunion
python scripts\construir_datos.py
python scripts\construir_referencia.py
python scripts\calcular_kpi.py
python scripts\estrella.py
python scripts\web_json.py
python scripts\agua_detalle.py
python scripts\publicar_a_app.py
cd app
npx vercel --prod
```

## Dónde se apunta el archivo nuevo

Una línea, en `scripts\construir_datos.py`:

```python
XLSX = os.path.join(RAIZ, "ehs", "KPI´s EHS 2026-julio_versionfinal.xlsx")
```

Es lo único que cambia de mes a mes. El resto del pipeline no sabe cómo se llama el libro.

## Las tres compuertas que pueden detenerlo

**1. La guarda de correcciones.** Una corrección autorizada declara qué valor tenía el
Excel y a qué se corrige. Antes de aplicarla se comprueba que el Excel siga trayendo el
valor de partida. Si el área ya corrigió el origen, la corrección deja de tener sentido y
se anuncia en pantalla en vez de aplicarse a ciegas y desviar el número al otro lado.

**2. Los doce puntos de control.** `calcular_kpi.py` recalcula doce cifras del corte de
junio y las compara contra lo que el propio Excel muestra. Si una sola difiere, termina
con error. Es deliberado: un pipeline que publica pase lo que pase no sirve de nada.

**3. La verificación previa a publicar.** `publicar_a_app.py` revisa que el JSON traiga
corte, marca de tiempo y bloque `contraMeta` antes de copiar nada.

## La bitácora

Cada publicación escribe una línea en `app\datos\bitacora.jsonl`: cuándo corrió, qué corte
publicó, qué archivos movió, cuántas correcciones venían aplicadas. Es lo que exige
R.5.3.4 y es lo primero que se mira cuando alguien pregunta «¿esto está actualizado?».

El tablero también lo dice de cara al usuario: la barra superior muestra la marca de
`actualizadoEn`, que sale del dato, no del reloj del navegador.

## Cuando el mes no trae dato

No se rellena con ceros. El mes sin captura viaja como `null`, el selector lo deshabilita
y el gráfico deja el hueco. Es la regla R.5.3.6 y es justamente el defecto del libro
heredado que este trabajo vino a corregir: en agosto, julio estaba capturado y el reporte
lo mostraba en cero.

## Verificar después de actualizar

```powershell
python scripts\validar_sin_hallazgos.py        # ninguna cifra escrita a mano
python scripts\verificar_sql_contra_motor.py   # el SQL y el motor siguen dando lo mismo
cd app; npm run lint; npm run format:check
```

Los tres tienen que salir en verde. `validar_sin_hallazgos.py` regenera las cifras
prohibidas del dato recién publicado, así que se adapta solo al corte nuevo.
