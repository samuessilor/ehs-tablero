# Backlog de solicitudes de Samuel sobre el tablero

Un solo lugar donde se acumula **todo** lo que Samuel pide sobre el tablero web (`app/`),
organizado por tema en vez de por orden cronológico de los mensajes. Cada solicitud
nueva se agrega aquí antes o mientras se ejecuta; cuando queda implementada, probada en
`C:\EHS` (servidor local de prueba) y confirmada visualmente, pasa a `[x]` con el commit
que la cerró. Así, en cualquier momento, este archivo solo por su cuenta responde: "¿qué
se pidió y qué de eso ya está hecho de verdad?" — sin tener que releer la conversación.

**Regla de esta lista**: nada se marca `[x]` solo porque el código se escribió. Se marca
`[x]` cuando además se verificó en el navegador (screenshot o inspección en vivo) que se
ve/funciona como se pidió. Si algo se implementó pero no se pudo verificar, queda `[~]`
con la razón.

**Este archivo es solo sobre diseño/UX del tablero.** Para la auditoría de la parte de
ingesta (Excel → SQL → tablero) y de Calidad del dato — qué se corrigió, qué quedó
documentado para depurar después con la persona encargada, y la reconciliación completa
de 175 valores contra `KPI's EHS 2026-julio_versionfinal.xlsx` — ver
`docs/auditoria-ingesta-27-sep-2026.md`.

---

## Pendiente ahora mismo

- [x] **Confirmar que el PDF ya no se sobrepone al imprimir, ni se ven recuadros
      unidos, ni el crédito queda solo en la última hoja** — verificado con emulación
      real de medio "print" (Playwright, no una captura ni un supuesto): las gráficas
      se redibujan (`beforeprint`), los 4 espacios entre bloques de KPI miden 30px
      exactos sin superposición, y el crédito del pie mide 1512px de 1528px de ancho
      de página (antes 421px, pegado a la izquierda por heredar `max-width:74ch` de
      `.pie-nota`) — sección 12, `877de75`. Sigue pendiente que Samuel confirme contra
      un PDF real descargado, como último control, pero ya no es solo "el mecanismo
      es el correcto": se midió el render real de impresión.
- Nota sobre el metadato Autor del PDF: no es solucionable vía `window.print()` — ver
  el detalle en la sección 7. El crédito visible en el pie del reporte ya cumple el
  mismo propósito.

**Al 28-sep-2026:**
- [x] `deploy-web1.vercel.app` desplegado con las secciones 24-26 (cuenta confirmada por
  Samuel: `specifinance-7412` / `_deploy-web1`) — verificado con comparación exhaustiva
  contra la producción real: **614 llamadas y páginas, 0 diferencias**.
- [x] **Decisión de Samuel: el libro de SharePoint se retira** — "el sharepoint se
  descarta ya todo será por este medio y esta interfaz". `KPI´s EHS 2026.xlsx` deja de
  ser la fuente de captura; la copia corregida
  (`ehs\KPIs EHS 2026-julio_versionfinal_corregido.xlsx`) queda solo como referencia del
  histórico auditado, no como algo por reemplazar en SharePoint. El texto de "cómo
  resolver" de los hallazgos del libro (sección 25) se actualizó en consecuencia en
  `datos.json` (fuera de git). Ver sección 27.
- [x] 2023 borrado de la base (sección 19, migración 0016) — pedido explícito de
  Samuel, ya aplicado y verificado.

**Reconciliación completa contra `git log`, 27-sep-2026** (pedida explícitamente por
Samuel: "corrobora que todos los requisitos y solicitudes están completadas"). Recorridos
los 20 commits desde que existe este archivo (`40c74c5` en adelante): cada commit de
código tiene su cita de hash en alguna entrada de este documento, salvo `8975909`
("Restaura el clic normal de leyenda"), que no tiene cita propia porque quedó
completamente superado por `2443e92` el mismo día — la sección 11 ya narra ese arco
completo (`9f15dfd` → `2443e92`) sin necesitar citar el paso intermedio. 59 solicitudes
marcadas `[x]`, 2 en `[~]` (ambas con su razón documentada, sección 7), **0 sin marcar**.
No hay huecos.

---

## 1. Header y marca

- [x] Logo real de Servióptica (fondo removido) en el header — `ea7e842`
- [x] Logo más grande (26px → 40px) — `efb7824`
- [x] Logo es el botón para volver a la página inicial en las 4 pantallas
      (tablero/captura/corregir/reporte) — `efb7824`
- [x] Quitar el subtítulo técnico "Stack de integración · Node + EJS + ECharts · 2026"
      del header — `efb7824`
- [x] "Mes de corte" movido a la esquina superior derecha, junto a "Última
      actualización" — `b3b9abd`
- [x] "Última actualización" en formato legible ("24 sep 2026 · 21:52") en vez del ISO
      crudo — `efb7824`
- [x] Quitar el texto "META TECHO · CUMPLIR ES QUEDAR POR DEBAJO" de la franja de
      contexto — `b3b9abd`
- [x] Selector de Sitio con subsecciones (Consolidados / Laboratorios y agencias) —
      `ea7e842`

## 2. Tipografía y colores

- [x] Tipografía menos "genérica de IA" (Inter) y más empresarial: IBM Plex Sans,
      cargada como webfont real en las 4 vistas — `b3b9abd`
- [x] Colores de gráficos alineados a la marca: `graficos.js` tenía el azul marino viejo
      mientras `ehs.css` ya había pasado a negro corporativo desde la reunión del
      24-sep-2026; quedaron alineados — `b3b9abd`
- [x] Etiquetas "Residuo peligroso"/"Residuo aprovechable" que se veían mal en amarillo:
      era `var(--riesgo)` (~2.6:1 de contraste) en el estado "fuera de rango" de
      captura/corrección; se oscureció solo el texto — `b3b9abd`
- [x] Verde de la matriz de control (mapa de calor) y de la lista de Calidad del dato,
      más transparente y con tono de "aprobado" en vez de un verde suelto — `b3b9abd`
      (ajuste de opacidad revisado dos veces: primero a partir de la solicitud "verde
      más intenso" de una ronda anterior, después hacia más transparente en esta)
- [x] Verde de "cumple" muy oscuro, no se entendía como "algo bien o correcto" —
      `--cumple`/`C.cumple` pasa de `#2e7d5b` a un verde vivo de aprobación
      (`#16a34a`), con todos los `rgba()` que lo referenciaban a mano (chips, bordes,
      franja de estado, mapa de calor) actualizados en el mismo cambio para que sea
      una sola gama en todos lados — `6677b13`
- [x] Verdes/rojos con la misma gama entre todas las gráficas y el mapa de calor —
      ya comparten los mismos valores base desde antes; con el ajuste de arriba
      además comparten el mismo verde vivo — `6677b13`

## 3. Gráficas — ejes, metas, leyendas y color por dato

- [x] Más uso de ECharts / animaciones más profesionales: entrada escalonada
      (`animationDelay`) y transición suave al actualizar una gráfica ya pintada
      (`animationDurationUpdate`) — `b3b9abd`
- [x] Línea de meta/target en "Producción contra consumo por lente" (Agua y Energía),
      que no la tenía — `b3b9abd`
- [x] Gráficas reales (no solo tabla) en "Contraste mensual" (Agua/Energía/Residuos):
      barras por año + líneas YTD, con variación % del mes y del YTD en el tooltip —
      `b3b9abd`
- [x] Mayor relevancia visual al YTD contra años anteriores (la lectura gerencial de
      "cómo vamos") — resuelto vía el punto anterior — `b3b9abd`
- [x] Mes de corte resaltado en las barras "por mes"; el resto atenuado — `b3b9abd`
- [x] Ese resaltado ajustado a **tres niveles**: mes de corte (color fuerte), meses ya
      publicados hasta el corte (color normal), meses que ya llegaron pero el corte
      todavía no reconoce (mucho más tenues) — para no confundir datos crudos
      adelantados con datos oficialmente publicados — `efb7824`
- [x] Diamante blanco de "Meta del sitio" (Cada sitio contra su propia meta), poco
      profesional y confuso — reemplazado por una marca vertical delgada del mismo gris
      que la meta en el resto del tablero; texto actualizado ("la marca vertical" en vez
      de "el rombo") — `efb7824`
- [x] Banda roja de incumplimiento sobre la meta, demasiado prominente cuando el dato
      está cómodamente por debajo — opacidad bajada dos veces en esta ronda
      (.055 → .03) — `efb7824`
- [x] "Trayectoria en el scorecard": la leyenda decía teal pero las barras eran negro/
      naranja — la serie no tenía `itemStyle` propio y ECharts tomaba el color del tema
      para la leyenda. Corregido; además "Real del año" (no explicaba de qué) pasó a
      "Cierre del año" (mismo término que ya usa el tooltip) — `efb7824`
- [x] Esa misma barra rayada del año en curso: el rótulo "en curso" encima de la barra
      se veía raro y no decía por qué era distinta — se quita de la barra y pasa a ser
      su propia entrada de leyenda ("Año en curso"), con el mismo color que tiene la
      barra en ese momento (serie fantasma sin datos, solo para el swatch) — `6677b13`
- [x] La brecha (%) junto a cada barra se entendía al revés: lo bueno (bajo la meta)
      salía en negativo y lo malo (sobre la meta) en positivo — `Fmt.pct` (compartida
      por tarjetas, matriz, porSitio y trayectoria) invierte el signo solo para
      pantalla: bueno = positivo, malo = negativo en todos lados a la vez — `6677b13`
- [x] "Meta del sitio" (Cada sitio contra su propia meta) no decía en ningún lado que
      esa marca era la meta, y el gris quedaba desapercibido contra las barras de
      color — se agrega su propia leyenda y la marca pasa a negro corporativo, mucho
      más visible — `6677b13`

## 4. Navegación y estructura de las vistas

- [x] Selector Agua/Energía/Histórico/Contraste arriba de la vista 02, para que Energía
      no quede perdida al final del scroll — `b3b9abd`
- [x] Quitar el placeholder "04 Detalle diario del mes — próximamente": el panel se
      oculta hasta que haya lectura diaria real en vez de mostrar una caja vacía —
      `b3b9abd`
- [x] Desplegable detallado en "03 Hallazgos del libro heredado" y "04 Avisos
      automáticos": libro, celda, valor actual, valor esperado — `6a7347b` — y después
      ampliado con posible causa y cómo resolver — `b3b9abd`

## 5. Rendimiento

- [x] Investigar por qué el paso entre vistas se sentía lento — causa real encontrada y
      confirmada con evidencia de código: cero caché (4 de 6 vistas repetían la misma
      petición `panorama`) + peticiones encadenadas con `await` en vez de en paralelo
      (hasta 9 viajes de red en fila en una sola vista). Se agregó caché de peticiones
      por URL en el cliente y se paralelizaron las llamadas independientes de Panorama
      y Agua y Energía — `b3b9abd`

## 6. Datos: Perú y calidad del dato

- [x] Perú se trata solo como el país completo, sin desglose por sub-sitios — verificado
      en el modelo de datos (un solo `sitio_id='peru'`, sin sub-división) — sin cambios
      de código necesarios
- [x] "TOPSA (Perú)" pasa a verse solo como "Perú" en pantalla — migración
      `0013_ehs_peru_nombre_pais.sql` (renombra `sitio`/`sitio_corto`/
      `nombre_corporativo` en `ref.dim_sitio`; `sitio_id` sigue siendo `'peru'`) +
      etiqueta del botón en `tablero.js` + los 3 JSON estáticos (`datos.json` en app y
      en `C:\EHS`, `datos-ehs.json`) — `efb7824`

## 7. Reporte descargable (PDF)

Samuel descargó `Reporte EHS · Servióptica.pdf` y encontró varios defectos reales.

- [~] Texto y ejes de las gráficas se sobreponen con el párrafo de análisis de abajo en
      varias páginas del PDF — causa real: las gráficas se dibujan una sola vez contra
      el tamaño de PANTALLA y `reporte.js` no tenía ningún listener de
      `beforeprint`/resize (a diferencia del tablero), así que ninguna instancia de
      ECharts se volvía a medir para el layout de impresión. Se agregó el listener
      (`Graficos.redibujar()` en `beforeprint`) más `overflow:hidden` en `.grafico`
      como red de seguridad adicional — `9f15dfd`. **Verificado que el listener se
      dispara y el mecanismo es el correcto (patrón estándar para este problema con
      ECharts); no se pudo verificar visualmente contra una impresión real** —
      `window.print()` abre un diálogo nativo que no se puede automatizar de forma
      segura desde aquí. Pendiente de que Samuel confirme descargando el PDF de nuevo.
- [x] El icono de "guardar imagen" (⬇, del toolbox de ECharts) quedaba dibujado dentro
      de cada gráfica impresa — sin nada con que interactuar en un PDF/papel. Nuevo modo
      "impresión" en `graficos.js` (`Graficos.activarModoImpresion()`) que omite el
      toolbox en todo lo que se dibuje después; `reporte.js` lo activa antes de pintar
      la primera gráfica — verificado, ya no aparece — `9f15dfd`
- [x] Nombre del archivo/documento sin el mes — el título ahora incluye el corte:
      "Reporte EHS · Servióptica · Julio 2026" en vez de un nombre fijo — verificado en
      la pestaña del navegador — `9f15dfd`
- [~] Autor del documento (metadato PDF) = Samuel Galeano — **limitación real, no
      solucionable con este mecanismo**: el PDF sale del "Guardar como PDF" del propio
      navegador (`window.print()`), y Chrome no expone ninguna forma de fijar el campo
      Autor de un PDF impreso desde una página HTML (sí toma el `<title>` como Título
      del documento — eso sí quedó resuelto arriba —, pero no hay equivalente para
      Autor). El crédito visible en el pie del reporte (punto siguiente) cumple el
      mismo propósito de forma confiable y sí es 100% verificable.

## 8. Créditos / atribución

- [x] Pie del reporte descargable: "Reporte generado por el Dashboard EHS · Elaborado
      por Samuel Galeano", discreto (9.5px, opacidad reducida) — verificado — `9f15dfd`
- [x] Header del tablero (front, pantalla principal únicamente): crédito pequeño bajo el
      título ("Hecho por Samuel Galeano", 8px, muy tenue) — verificado, sin
      protagonismo visual — `9f15dfd`

## 9. Selector de sitio

- [x] Perú movido de "Laboratorios y agencias" a "Consolidados" — cambio puramente de
      agrupación visual, el id/cálculo/etiqueta de Perú no cambian — `9f15dfd`
- [x] Perú reordenado al lado de Colombia (antes quedaba último del grupo) —
      `5918fc4`
- [x] Bug real en la leyenda de "Trayectoria en el scorecard": la entrada fantasma "Año
      en curso" se podía deseleccionar con un clic sin que nada cambiara en la gráfica,
      dejando su propio ícono y el de "Meta del año" con aspecto de deseleccionado —
      `legend.selectedMode:false` en esa gráfica, ninguna de las tres entradas necesita
      filtrarse — `9f15dfd`

## 10. Verificaciones de calidad del dato

- [x] "¿De dónde sale ese 4 de la barra de Frequency rate?" — verificado con los datos
      crudos: julio, Colombia, 1 accidente / 241.735 horas-hombre de SOLO julio × 1e6 =
      4,14 (coincide exacto con la API). El 0,61 de la tarjeta es el mismo accidente
      dividido entre las ~1,69 millones de horas ACUMULADAS de los 7 meses. Mismo
      accidente, denominador distinto (mensual vs. YTD) — no es un error de cálculo.
- [x] "Soluciona el hallazgo del YTD desplazado ('KPIs 2026'!I12:K13) e implementa todo
      por código bajo buenas prácticas de ingeniería de datos, para todo el proyecto" —
      verificado en el código (no supuesto) que el tablero YA sigue ese patrón para los
      5 hallazgos que "alteran un número": `construir_datos.py` lee únicamente la hoja
      cruda (`indicadores mensuales LABS`) y las columnas de horas *crudas* por sitio de
      `AT 2026` — nunca las celdas resumen donde viven estos defectos (`I12:K13`,
      `H38:H47`, `M21:M32`, `D22`, `C22`). El acumulado se recalcula por código en los
      dos motores (`ehs.v_kpi_ytd` en SQL con `where num_mes <= corte.num_mes`;
      `calcular_kpi.py` en Python con `range(1, m+1)`), ninguno copia una fórmula de
      Excel, y `calcular_kpi.py` además valida el resultado contra el propio Excel en
      12 puntos de control y **aborta la generación** si alguno no cuadra. El tablero
      nunca reprodujo estos defectos — no había nada que corregir en el código. Se
      actualizó el campo "Cómo resolver" de esos 5 hallazgos para decir esto
      explícitamente, con la cita exacta del código, en vez de dejarlo como pendiente.
- [x] "Corrobora TODOS los hallazgos de Calidad del dato contra el código y la base de
      datos, no contra el Excel — ese no es el motor de backend del proyecto" —
      corroborados los 9, cada uno con su propia evidencia verificada (no una nota
      genérica repetida). Actualización de datos (`datos.json`, no versionado en git,
      igual que el resto del contenido de los hallazgos):
  - `residuos-estrella-marzo`: dato real de marzo (hechos_mensual_2026.csv y
    `/api/ehs/detalle`) para La Estrella = 979,1 + 1.183 + 4.333 kg, exactamente el
    total correcto (6.495,1 kg), no los 6.495,0 kg del Excel — el tablero suma los
    tres componentes el mismo, nunca lee el total ya escrito en `E60`.
  - `horas-temporales-agencias`: ya verificado antes (0,613272 YTD, coincide con
    "con todas las horas es 0,613").
  - `horas-agencias`: Agencias tiene horas reales y no nulas los 12 meses y 0
    accidentes todo el año — el frequency rate da 0 porque el numerador es 0 (real),
    no porque el denominador esté vacío (si lo estuviera, la vista SQL daría
    `null`/"sin dato", nunca un 0).
  - `fr-mensual-cruzado`: verificación **estructural**, no solo del dato de hoy —
    `ehs.v_lectura_ambito` une cada lectura de horas por `sitio_id`
    (`join ... on a.sitio_id = l.sitio_id`), nunca por posición de celda. Cruzar
    las horas de un sitio con los accidentes de otro (como en el Excel) no es
    posible en esta estructura sin importar qué valores traiga el mes.
  - `grafica-6` y `doble-mecanismo`: no aplican al tablero — son un objeto gráfico
    embebido en el propio libro de Excel, y una inconsistencia de proceso dentro
    del libro (meses a mano vs. enlazados), respectivamente. El tablero construye
    sus propias gráficas (ECharts) desde los valores ya calculados, y lee los 12
    meses con el mismo código sin distinguir "a mano" de "enlazado" — esa
    distinción solo existe dentro del Excel.
  - `julio-en-cero` y `accidente-mes-equivocado`: ya verificados en rondas
    anteriores (lectura de hoja cruda y migración 0012, respectivamente).
  - Se le indicó a Samuel de guiarse por `KPI's EHS 2026-julio_versionfinal.xlsx`
    como la versión más respaldada, sin confiar en ella del todo — la corroboración
    de cada punto se hizo contra el dato real ingresado (CSV/API/SQL), no contra
    ninguna versión del Excel.

## 11. Gráficas de histórico/contraste, tablas de referencia y composición de residuos

Ronda de revisión visual del 27-sep-2026, a partir de una serie de capturas de pantalla
y observaciones puntuales de Samuel sobre el tablero ya en uso.

- [x] "Cuando se opriman los colores [de la leyenda] se debe desaparecer ese elemento
      de la gráfica como estaba antes, y así con todos los gráficos" — el fix anterior
      (sección 9, `9f15dfd`) solo arregló el aspecto visual de "deseleccionado" de la
      leyenda fantasma "Año en curso"; dejaba `selectedMode:false` en TODA la leyenda,
      así que "Cierre del año" y "Meta del año" tampoco se podían ocultar con un clic,
      que es justo lo contrario de lo pedido. Se revirtió eso y se dejó un listener que
      intercepta solo el clic en "Año en curso" — verificado con `dispatchAction` +
      inspección de `getOption()`: las otras dos entradas alternan su propio
      `selected` con normalidad, sin efectos secundarios entre ellas — `2443e92`
- [x] "La barra que no desaparece son las barras de las gráficas del año en curso" —
      bug real distinto del anterior: la entrada "Año en curso" era una serie fantasma
      sin datos (solo para el color de la leyenda), completamente desconectada de la
      barra real del año en curso (que vive dentro de la serie "Cierre del año"). Un
      clic en la leyenda nunca podía afectar algo que no controlaba. Se reescribió el
      listener para que reescriba el dato real vía `setOption` (merge por nombre) —
      verificado en el navegador: la barra roja rayada de 2026 desaparece y reaparece
      exactamente con el clic, con el mismo valor (138,226297) intacto al restaurar —
      `2443e92`
- [x] "Las gráficas están corridas con respecto a la base de los números" (barras no
      alineadas al cero) — verificado con lectura de píxeles del canvas
      (`getImageData` + `convertToPixel`), no a ojo sobre una captura: en `gAguaCombo`
      (ya verificado en una ronda anterior) y ahora también en `gAguaTray`, las cuatro
      barras (2023-2026) tienen su borde inferior exactamente en el píxel del valor
      cero, sin ningún corrimiento. No hay bug de alineación en estas gráficas — la
      impresión de "corrida" venía de la compresión/escala de la captura de pantalla,
      no del render real.
- [x] "Mejorar la estructura y la parte visual de las gráficas de históricos, que están
      confusas y poco funcionales, y dejar por aparte Agua y Energía" — Agua y Energía
      ya no comparten un subgrupo "Histórico"/"Contraste mensual" aparte: cada recurso
      tiene sus propios paneles "· contra el año anterior" y "· contraste mensual"
      justo después de su propio detalle, con índices renumerados de corrido
      (Agua 01-06, Energía 07-12) — `4f89ab7`. Sumado a los tres puntos de abajo
      (colores YTD, aclaración de la meta, leyenda funcional), que eran la parte
      "confusa" de la lectura, no solo el acomodo.
- [x] "En el contraste mensual los YTD son del mismo color y confunden; dar una
      referencia visual interesante para diferenciar los dos años" — YTD del año A
      pasa a gris tenue punteado (línea de referencia/pasado) y YTD del año B se queda
      en negro sólido (el año que importa), con rótulo numérico solo en el último mes
      con dato de cada serie en vez de un número encima de cada punto — `2443e92`
- [x] "El YTD de 2026 en amarillo no se ve bien, cambia el color a uno más empresarial,
      visible pero no tan llamativo" — se probó ámbar (`C.riesgo`) primero y Samuel lo
      rechazó explícitamente; color final: negro corporativo (`C.tinta`), el mismo tono
      que ya usa el resto del tablero para "la serie que importa" — `2443e92`
- [x] "Revisar la gráfica de aprovechables: se ven dos barras de aprovechables, o por
      qué se ve así, y al señalar se seleccionan como si fueran diferentes" — bug real
      de raíz confirmado: `residuo_total_kg` (magnitud propia de Perú, sin desglose
      peligroso/aprovechable/ordinario) se registra en `ref.kpi_magnitud` para todo el
      KPI, no por ámbito, así que la consulta SQL de `residuosComposicion` devolvía una
      cuarta "parte" `total` en 0 para Colombia, que nunca la captura. Sin nombre ni
      color propio en el cliente, heredaba el color por defecto del tema — el mismo
      teal que "Aprovechable" — y al ser una serie distinta se seleccionaba aparte al
      pasar el mouse. Corregido en los tres niveles: la SQL (`adaptador_sql.js`, ahora
      filtra por `exists` contra los kilos realmente capturados en el ámbito), el
      gráfico (`graficos.js`, filtro defensivo adicional) y el texto generado
      (`tablero.js`, `textoComposicion`/`pintarAcumuladoComp`) — verificado con
      `curl` a la API (ya no aparece `"total"` en `partes` ni en `acumulado`) y en el
      navegador: exactamente 3 categorías en la gráfica y en la lista, sin la palabra
      "undefined" en el texto — `2443e92`
- [x] "Acá qué es Brecha, ¿lo mismo que Meta? Dejar siempre los mismos términos para
      las mismas cosas" (reporte descargable) — columna "Brecha" del resumen renombrada
      a "Brecha vs. meta" — `643e55d`
- [x] "Dejar también los meses que aún no están, visuales en tablas pero sin datos,
      solo de referencia" — la tabla "contraste mensual" ya traía los 12 meses desde el
      servidor; la tabla "mes a mes" de Agua/Energía solo mostraba los meses con dato
      real (7 de 12). Ahora completa el año con filas de referencia en blanco (`—`)
      para los meses sin lectura, sin tocar la etiqueta "N meses con dato" (que sigue
      contando solo los reales) — verificado en el navegador para Agua y Energía —
      `2443e92`
- [x] "Todo esto corrobora que [el archivo] sea basado en KPI's EHS 2026-julio_versionfinal.xlsx"
      (12 avisos automáticos de salto atípico, con cifras exactas de
      residuo_peligroso/aprovechable/ordinario para Celta/Estrella/Agencias en varios
      meses) — corroborados uno por uno con un script Python (`openpyxl`) que replica
      exactamente la búsqueda por etiqueta de `construir_datos.py` contra el Excel
      real, sin asumir coordenadas fijas. Los 12 coinciden de forma exacta. Son saltos
      operativos reales para revisar con el área, no errores de ingesta — sin cambios
      de código.
- [x] "Revisa los datos y cómo está la gráfica [Frequency rate], parece que se subiera
      pasado de la meta por mucho y sería una alerta grave" — verificado con datos
      crudos (sección 10, mismo caso, reconfirmado): la barra "Del mes" de julio
      (4,14 acc/MHH) divide 1 accidente entre solo las horas de julio; el techo de
      1,60 se traza sobre "Acumulado del año" (0,61 acc/MHH, con ~1,69 millones de
      horas acumuladas), que sí cumple con holgura. No es una alerta real ni un error
      de cálculo — la gráfica ya lo distinguía en el tooltip, pero como esta es la
      segunda vez que la misma gráfica genera la misma confusión al verla sin pasar el
      mouse, se agregó "(acum.)" al rótulo de la meta directamente sobre la línea
      punteada, en las cinco gráficas "X en el tiempo" (agua, energía, residuos,
      frequency rate, accidentes) — verificado en el navegador — `2443e92`

## 12. Auditoría final de cierre (27-sep-2026)

Samuel pidió explícitamente, al cerrar la ronda de la sección 11: corroborar que
**todo** lo pedido está en este backlog, que todo lo marcado `[x]` tiene visto bueno
real, y que el código funciona, sigue buenas prácticas y no tiene sobreingeniería —
ejecutando de una vez cualquier ajuste que saliera de esa revisión.

Se hizo una revisión adversarial (agente aparte, con instrucción explícita de buscar
fallas, no confirmar el propio trabajo) de los 4 commits de la sección 11. Encontró un
regresión real que el propio fix de la sección 11 había introducido:

- [x] **Perú se rompía al abrir Ambiental** — el filtro de `'total'` agregado para que
      Colombia no viera la categoría fantasma (sección 11) dejaba a Perú, cuya única
      magnitud de residuo ES `'total'` (sin desglose), sin ninguna parte que mostrar:
      `pintarAcumuladoComp`/`textoComposicion` hacían `.reduce()` sobre un arreglo
      vacío, que **revienta con `TypeError`** — confirmado en vivo
      (`curl .../residuos-composicion?ambito=peru` → `partes:['total']`, con datos
      reales) antes de tocar código. Corregido agregando `'total': 'Total'` a los
      mapas nombre/color en los tres lugares (composicionResiduos en `graficos.js`,
      pintarAcumuladoComp y textoComposicion en `tablero.js`), en vez de filtrarlo:
      así Colombia sigue sin ver la categoría fantasma y Perú ve la suya real, con
      nombre y color propios. Verificado en el navegador para ambos ámbitos, sin
      errores de consola — `877de75`
- [x] **El reporte descargable perdía el panel "02 · contra el año anterior" de
      Frequency rate y Accidentes DAFW** — `reporte.js` pedía el histórico con el
      ámbito propio del reporte, pero ese histórico de seguridad solo existe con
      perímetro fijo `colombia_peru` (la misma regla que Panorama y Seguridad ya
      aplican en `tablero.js`). El 404 resultante se ocultaba solo (el panel
      desaparecía sin avisar), encontrado con `browser_console_messages`, no a
      simple vista. Corregido usando `colombia_peru` para esos dos KPI — verificado:
      cero errores de consola, panel visible con "COLOMBIA y PERU" — `877de75`
- [x] **El crédito fijo del reporte no quedaba centrado al imprimir** — hallazgo de
      la propia revisión de la sección 11 (ver arriba, "Pendiente ahora mismo"),
      confirmado con emulación de medio "print" y corregido en el mismo commit —
      `877de75`

Verificaciones adicionales de la auditoría, sin hallazgos:

- La corrección SQL (`exists` contra `@kg`) distingue bien "nunca capturado" de "capturado
  en cero real" — revisado el `insert @kg` completo, agrupa por fila real, no por suma
  filtrada, así que un cero real no se pierde.
- Las referencias de `id` entre `dashboard.ejs` y `tablero.js`/`graficos.js`
  (`gAguaTray`, `gEnergiaTray`, `tContrasteAgua`, `tContrasteEnergia`,
  `gContrasteAgua`, `gContrasteEnergia`) están todas exactamente una vez a cada lado,
  sin huérfanos ni duplicados.
- El patrón de "completar los 12 meses" nuevo en `tablero.js` usa el mismo idioma
  (`.filter(...)[0]`) que ya usa el resto del archivo unas líneas arriba — consistente,
  no una reinvención.
- Estilo de código (`var`/`function(){}`, comentarios sin tildes ni ñ) consistente con
  el resto de los archivos tocados.

Un cuarto hallazgo, de la re-verificación manual de lo anterior (no de la auditoría
adversarial, que no llegó a probar este ámbito combinado):

- [x] **"Total" (Perú) quedó con el mismo color que "Aprovechable"** — el fix de arriba
      le dio a `'total'` su propio nombre pero heredó `C.amb`, el mismo teal de
      "Aprovechable". Invisible con Colombia o Perú solos (nunca aparecen las dos
      partes juntas), pero en el ámbito combinado "Colombia + Perú" las cuatro partes
      se pintan en la misma gráfica y en la misma lista — recreando ahí mismo el bug
      de "dos barras idénticas" que originó toda la sección 11. Color propio
      (`C.tenue`) en `composicionResiduos` (`graficos.js`) y `pintarAcumuladoComp`
      (`tablero.js`) — verificado en el navegador con `sitio=colombia_peru`, las
      cuatro categorías se ven y se seleccionan por separado — `27e3e2c`
- [x] **"Nacional Labs" dejaba en blanco, sin aviso, seis paneles del tablero** (Agua y
      Energía "· contra el año anterior" y "· contraste mensual", más los mismos dos
      de Residuos) — hallazgo propio, no de la auditoría adversarial, encontrado
      revisando en el navegador el fix de arriba. Causa: Nacional Labs nunca tuvo
      historia anual cargada (exclusión a propósito, `AMBITOS_CON_HISTORIA` en
      `rutas_api.js`, de antes de esta sesión) y las dos API responden 400 en vez de
      un JSON vacío; `pintarTrayectoriaPropia`/`pintarContraste` no atrapaban ese
      rechazo, así que la excepción se comía el resto del `await` secuencial que las
      llama — panel en blanco y error de consola, sin ningún mensaje. Ambas funciones
      ahora atrapan el rechazo y caen al mismo "sin dato" que ya usan para una
      respuesta vacía. Verificado en el navegador para los tres recursos: cero
      errores de consola, los seis paneles muestran su aviso — `41f13be`

## 13. Segunda corroboración final (27-sep-2026, ronda 2)

Samuel pidió, tras la sección 12: solucionar que un subagente (fork) hubiera corrido
comandos y hecho commits ignorando instrucciones explícitas de no hacerlo, y repetir la
corroboración final una vez más, a fondo. Lo primero es un cambio de proceso (registrado
en memoria, `ehs_arsenal_subagentes.md` — no toca código del tablero). Lo segundo:

- [x] **Reconciliación completa contra `git log`** — recorridos los 20 commits desde que
      existe este archivo; 59 `[x]`, 2 `[~]` documentados, 0 sin marcar, sin huecos —
      ver la nota fija arriba de "Pendiente ahora mismo" — `f162a0f`
- [x] **Perú mostraba "Cumple" en Frequency Rate y Accidentes DAFW sin tener ningún
      dato** — hallazgo propio del barrido de Seguridad por los 7 ámbitos (no estaba
      cubierto en las rondas anteriores). La constante SQL `ESTADO`
      (`adaptador_sql.js`, compartida por `panorama`, `kpiPorSitio` y dos usos más)
      resolvía "meta = 0" antes que "sin lectura acumulada": Agencias (meta 0, pero con
      datos reales) entraba bien a esa rama, pero Perú (meta 0, sin ningún dato, per
      `ehs/CLAUDE.md`) también entraba ahí con `y.valor = null`, y
      `coalesce(y.valor, 0) <= 0` daba `'cumple'` antes de llegar al
      `when y.valor is null then 'sin_dato'` que ya existía más abajo, inalcanzable
      para este caso — el tablero afirmaba el cumplimiento de una meta de seguridad sin
      tener ningún dato que lo respalde. Reordenado para que `sin_dato` se evalúe
      primero, igual que ya hace `BRECHA` con el mismo caso. Verificado: Perú ahora
      `sin_dato` en ambos KPI, Agencias sigue `cumple` con datos reales sin cambio,
      Colombia + Perú (agregado) sin regresión, cero errores de consola en los 7
      ámbitos de Seguridad — `8dd1e21`
- [x] **Barrido de Seguridad y Calidad del dato en los 7 ámbitos** — Calidad del dato no
      depende del ámbito elegido (una sola vista global, verificado leyendo
      `pintarCalidad()`), así que se revisó una vez; Seguridad se revisó en los 7 —
      cero errores de consola, sin más hallazgos.
- [x] **Revisión de calidad de código con agentes de solo-reporte** (`schema`, sin
      `Edit`/`Write`/`Bash` de escritura) sobre los archivos tocados en toda la
      sesión — 3 agentes en paralelo (correctness/overengineering/consistency).
      Cada hallazgo se verificó de forma independiente (diff real, `curl` a la API
      con datos en vivo, navegador) antes de aplicarlo — dos resultaron ser bugs
      reales, no solo observaciones de estilo:
  - **`residuosComposicion` mezclaba el total agregado del mes con la parte "total"
    de Perú** — el campo `total_kg`/`total_g_lente` (la suma de TODAS las partes)
    y el campo por-parte de Perú (cuya parte se llama literalmente `total`) tenían
    el mismo nombre, así que en el ámbito combinado Colombia + Perú el segundo
    pisaba al primero en cualquier mes donde ambos aportan. Verificado con datos
    reales de julio: el tooltip mostraba "Total 9000 kg" cuando la suma real de
    las 4 partes es 41214 kg. Renombrado a `suma_kg`/`suma_g_lente` (un nombre que
    nunca puede coincidir con ningún valor real de "parte") en los dos
    adaptadores — `abdae58`
  - **La marca de "Meta del sitio" desaparecía del todo** cuando la meta de un
    sitio superaba por mucho el resto de las barras (el caso real: La Estrella,
    6,20 acc/MHH de frequency rate, contra otros sitios muy por debajo de 1) — el
    tope nuevo del eje (`maxBarra*1.18`, para que una meta alta no aplastara las
    demás barras) no consideraba las metas, y ECharts simplemente deja de dibujar
    un punto fuera del rango del eje en vez de "quedar en el borde" como decía el
    comentario. Verificado en el navegador antes (marca invisible) y después
    (marca visible al borde, tooltip sigue mostrando 6,20 sin recortar) — `abdae58`
  - 3 filtros defensivos ya redundantes (`graficos.js` y `tablero.js` x2, todos el
    mismo patrón copiado) que el propio comentario admitía inalcanzables desde que
    la SQL se corrigió — removidos, restaurando el uso directo de las listas —
    `abdae58`
  - 3 comentarios corregidos para que digan la verdad (uno atribuía un color a
    "ámbar" cuando nunca se comiteó así; otro decía 404 cuando el servidor
    devuelve 400; un tercero tenía una tilde faltante que cambiaba el significado
    de la palabra) — `abdae58`
- [x] **Exportes CSV/Excel (Perú, Colombia + Perú) y modal de selección del reporte** —
      el parámetro `ambito` de `/api/ehs/detalle` no filtra nada (el endpoint siempre
      exporta los cuatro sitios reales: celta, estrella, agencias, peru — es un dump
      completo por diseño, no una vista filtrada por el sitio elegido en pantalla; los
      agregados como "Colombia + Perú" no aplican aquí). Perú sí está incluido, con sus
      campos propios en blanco (no reporta peligroso/aprovechable/ordinario/accidentes/
      horas) y `residuo_total_kg` poblado — igual en CSV y Excel (mismo endpoint,
      separador `;` en vez de `,`). El modal "Qué incluir" abre con los 5 KPI
      pre-marcados; destildar uno (probado con Agua) marca `data-excluido` solo en ese
      bloque, sin tocar los demás — confirmado inspeccionando el DOM directamente, sin
      llegar a disparar `window.print()` (diálogo nativo, no automatizable con
      seguridad). Cero errores de consola.
      **Hallazgo real, sin corregir todavía** — no estaba en el alcance de esta ronda,
      así que se deja documentado en vez de improvisar una solución: la exportación
      **no incluye histórico**, pese a que el plan original de Perú lo pedía
      explícitamente ("que incluyan Perú e histórico"). No es un problema de datos — el
      histórico 2023-2025 vive en la MISMA tabla que lee el export
      (`ehs.hecho_lectura_mensual`, migración 0012) — sino de la función
      `detalle({anio})` en `adaptador_sql.js`, que fuerza `anio === ctx.anio` (el año
      del corte actual, 2026) y devuelve `null` para cualquier otro año; y de que ni
      `reporte.ejs` ni sus botones de descarga exponen ningún selector de año. Pendiente
      de decidir con Samuel: ¿un año a la vez con selector, o todos los años en un solo
      archivo?

## 14. Auditoría de ingesta y Calidad del dato (27-sep-2026)

Samuel: "revisa también la escritura en cuanto código y el proyecto en general hasta la
parte de ingesta", seguido de "hay valores en calidad de datos que no comprendo bien de
dónde sacaste esos datos" (con captura del Excel fuente adjunta) y la instrucción de
solucionar lo viable y dejar especificado con amplio detalle lo que no.

- [x] **Reconciliación completa contra el Excel fuente** — 173 de 175 valores crudos de
      Celta/Estrella/Agencias (Enero-Julio) coinciden exactos contra
      `KPI's EHS 2026-julio_versionfinal.xlsx`, hoja "indicadores mensuales LABS"
      (leída por etiqueta, no por coordenada). Las 2 diferencias son la corrección ya
      documentada del accidente (mayo→julio). Sin hallazgos nuevos de dato — el tablero
      sí traza de vuelta al Excel.
- [x] **Bug real encontrado y corregido**: "01 Lecturas cargadas por mes" mostraba un
      número fijo (sitios × magnitudes) que no cuadraba contra la tarjeta "Lecturas
      cargadas" de la misma pantalla — `8180f8e`
- [x] **Workflow de 4 agentes en paralelo** sobre `analisis/` (Python), `sql/`/
      `migraciones/` y el flujo de captura/validación/escritura (JS) — dos bugs reales
      corregidos (advertencia de cero en `sp_capturar_lote`, doble validación al
      corregir una lectura + mensajes de error tragados) — `3edd1b6`, `1920cd9`
- [x] **Todo el resto** (fragilidad de los scripts de Python ante un Excel
      reformateado, seguridad transaccional de una migración ya aplicada, scripts de
      verificación desactualizados frente a Perú/Colombia+Peru, documentación
      desactualizada sobre qué SQL se ejecuta en una instalación real) queda
      catalogado con detalle completo — archivo, por qué importa, cómo debería quedar
      — en `docs/auditoria-ingesta-27-sep-2026.md`, para depurar con calma y
      corroborar con la persona encargada.

## 15. Barras corridas en "contra el año anterior" (27-sep-2026, ronda 3)

- [x] **Barras corridas respecto a los rótulos del eje cuando el año en curso está
      visible** — Samuel mandó dos capturas comparando el mismo panel con y sin el año
      en curso activo. Causa real, verificada con lectura de píxeles: la serie
      fantasma "Año en curso" (solo para el color de la leyenda, sin dato que dibujar)
      es `type:'bar'` en el mismo eje que "Cierre del año", y ECharts reparte el ancho
      disponible entre las dos series aunque la fantasma no tenga nada que pintar —
      desplazaba la barra real ~31px a la izquierda del centro de cada categoría.
      `barWidth:0` y `barGap:'-100%'` no lo resuelven (los dos probados y descartados,
      verificado que no cambian nada); el fix real es el mismo `stack` en ambas series.
      Como `Graficos.trayectoria` es una única función compartida por "04 Trayectoria
      en el scorecard" y cada "0X · contra el año anterior" (Agua/Energía/Residuos/
      Seguridad), un solo cambio corrige las 7+ instancias. Verificado con lectura de
      píxeles antes/después en dos paneles distintos (`gTray`, `gAguaTray`): el
      desfase de ~31px baja a ~0,5px (redondeo). El toggle de la leyenda sigue
      funcionando igual — `030809c`
- [~] **Scroll animado al oprimir los botones "Agua"/"Energía" del subnav** —
      `scroll-margin-top` ya dejaba el título a la altura correcta bajo el header
      fijo; faltaba `scroll-behavior:smooth`, agregado en `<html>` (respeta
      `prefers-reduced-motion`). No se pudo confirmar la animación visualmente: el
      navegador automatizado de esta sesión no ejecuta `scroll-behavior:smooth` ni
      `scrollIntoView({behavior:'smooth'})` — probados los dos, cero movimiento en
      1,5s, mientras que un scroll instantáneo sí funciona — una limitación conocida
      de entornos de automatización con el compositor de la pestaña. Es la propiedad
      CSS estándar; pendiente que Samuel lo confirme en un navegador real — `df1bb17`
      **Segundo intento (27-sep-2026, ronda 4), más aislado**: se repitió la prueba
      limpiando el hash de la URL primero (para no repetir un clic sobre un ancla que
      ya era el hash vigente, que algunos navegadores ignoran) y con un clic real del
      mouse, no sintético — mismo resultado, cero movimiento incluso después de 1s. Se
      aisló la causa: un scroll por rueda del mouse (`computer.scroll`, evento nativo)
      sí mueve `window.scrollY` con normalidad en la misma pestaña; es específicamente
      el scroll disparado por navegación de ancla o por JS (`scrollIntoView`/
      `scrollTo`) el que no se mueve nada, ni instantáneo ni animado. Refuerza que es
      una restricción del navegador controlado por CDP/la extensión (probablemente
      falta de "activación de usuario" para ese tipo de scroll en pestañas
      automatizadas), no un defecto del CSS — que es exactamente la técnica estándar
      de la plataforma y no tiene por qué comportarse distinto en un navegador real.

## 16. Consumo total visible mes a mes + meta del combo (27-sep-2026, ronda 4)

- [x] **El consumo absoluto (agua/energía/residuos) solo vivía en el tooltip, no se
      veía en la gráfica** — Samuel pidió poder ver visualmente cómo fue el consumo
      mes a mes (no solo el ratio por lente) para poder analizar qué lo movió, en los
      tres recursos. `comboProduccion` (agua/energía) ya traía el dato de consumo
      total en cada fila (`consumo_m3`/`consumo_kwh`) pero solo lo mostraba en el
      tooltip; la barra dibujaba "Lentes procesados" (un proxy de producción, no el
      consumo). Cambio: la barra ahora dibuja el consumo total; "Lentes procesados"
      sigue disponible en el tooltip y en la tabla "Mes a mes" de cada panel, sin
      perder ese dato. Para residuos no existía ningún gráfico de consumo absoluto —
      se agregó `Graficos.residuosCombo` (mismo `comboProduccion`, reusando
      `suma_kg`/`suma_g_lente` que `residuos-composicion` ya calculaba para el gráfico
      de composición — cero endpoints nuevos), como panel nuevo "03 Consumo total
      contra consumo por lente" en la vista Ambiental. Verificado en navegador:
      Colombia y Perú, agua/energía/residuos, valores de barras y tooltip coinciden
      con la tabla, cero errores de consola.
- [x] **La meta del combo se comparaba contra el ratio del mes suelto, no contra el
      acumulado — inconsistente con "X en el tiempo"** — Samuel mandó dos capturas
      comparando "Residuos en el tiempo" (rótulo `meta 134,9 (acum.)`, correcto: la
      meta ahí se traza contra el acumulado del año, como manda la regla de YTD del
      área) contra "Producción contra consumo por lente" (rótulo `meta 5,18 l`, sin
      aclarar). Verificado en el SQL (`hojaMensualRecurso`): `ratio` ahí es
      `consumo del mes / lentes del mes`, nunca se acumula — comparar eso contra una
      meta anual es un defecto preexistente en agua/energía (no introducido en esta
      ronda), y estaba a punto de replicarlo una tercera vez en el nuevo combo de
      residuos. Ya había un patrón resuelto para esto mismo en `serieKpi`
      (frequency rate: "un solo accidente en un mes de pocas horas dispara la barra
      mensual muy por encima de la meta aunque el acumulado la cumpla"). Con Samuel
      se evaluaron 3 opciones (aclarar el rótulo, quitar la meta del combo, o graficar
      el ratio acumulado en vez del mensual) y eligió aclarar el rótulo: ahora dice
      `meta X (mensual, ref.)` en los tres combos, y la nota de cada panel dice
      explícitamente dónde se ve la meta oficial acumulada (la ficha de Panorama para
      agua/energía, "Residuos en el tiempo" para residuos).

## 17. Calidad del dato: desplegable grande en avisos + depurar lo ya corregido (27-sep-2026, ronda 4)

- [x] **"Ficha para depurar" de un aviso automático solo traía 6 pares clave-valor, no
      la tabla completa** — Samuel pidió, para los "puntos a revisar" de "04 Avisos
      automáticos de este corte", un desplegable más grande que muestre la tabla
      completa (qué datos, cómo está estructurada) para poder dar un veredicto sin
      saltar de pantalla. `fichaAviso` ahora abre un botón bordeado ("Ver la tabla
      completa y dar un veredicto", no el texto chiquito genérico de `.infodato`) que,
      al expandirse por primera vez, carga perezosamente `/api/ehs/datos` del sitio del
      aviso (la misma fuente que "06 Datos") y dibuja las 9 magnitudes × todos los
      meses, con la fila del mes y la columna de la métrica que dispararon el aviso
      resaltadas — donde se cruzan es exactamente la celda señalada. Perezoso a
      propósito: un corte puede traer varias decenas de avisos y pedirle al servidor
      las 9 magnitudes de cada uno antes de que alguien abra ese desplegable en
      concreto sería puro desperdicio. Verificado en navegador: la tabla carga, los
      valores coinciden con el mensaje del aviso (Agencias, residuo_aprovechable_kg:
      800 en enero → 1.200 en febrero, exactamente el "+50 %" que dice el aviso), sin
      errores de consola.
- [x] **2 de los 9 "hallazgos del libro heredado" ya estaban corregidos y se seguían
      mostrando igual de urgentes que los 7 abiertos** — Samuel pidió depurar lo ya
      corregido en las demás secciones de Calidad del dato. Se agregó un campo
      `resuelto` a los hallazgos `julio-en-cero` y `accidente-mes-equivocado` (los dos
      que ya traían "(ya corregido)" en su propio título); el panel ahora separa
      "N abiertos" de "M ya corregidos" y los resueltos quedan en un desplegable propio
      colapsado por defecto — nunca se borran (son la bitácora de la auditoría), solo
      salen del camino.
- [x] **Hallazgo real, no cosmético, encontrado al verificar lo anterior**: el texto
      corregido de `accidente-mes-equivocado` (mayo → julio, confirmado por el manager
      de la implementación el 24-sep-2026, migración 0012) vive hoy en
      `app/datos/datos.json` y en `datos/datos-ehs.json`, pero **no** en
      `analisis/web_json.py` — el script que genera `datos-ehs.json` seguía con el
      texto viejo, anterior a la reunión ("el accidente vigente es en mayo, en
      Celta"). Alguien corrigió el JSON publicado a mano sin actualizar su generador.
      La próxima vez que alguien corra `python analisis/web_json.py` (para publicar
      cualquier mes nuevo) habría vuelto a escribir el mes equivocado sobre el dato
      corregido, sin que nadie se enterara — justo el tipo de defecto silencioso que
      este proyecto existe para evitar. Corregido el texto en `web_json.py` para que
      coincida con el ya publicado, con el campo `resuelto=True` agregado también ahí
      y en los dos JSON. `app/datos/datos.json` está fuera de git (`.gitignore:
      datos/*.json`, dato operativo no versionado) así que este fix no tiene commit
      propio en `app/` — la fuente (`analisis/web_json.py`, fuera del repo `app/`)
      queda corregida en disco.

## 18. Brecha % en `porSitio` no se dibujaba (27-sep-2026, ronda 4, cierre de la tarea #94)

- [x] **La columna fija de brecha (Imagen #45, "02 Cada sitio contra su propia meta")
      quedó con la posición X correcta pero sin texto** — la sesión anterior ya había
      movido el ancla de la serie 'Brecha' a una coordenada fija (`ejeMax`, el mismo
      borde derecho del eje), pero el punto se dibujaba con `symbol:'none'` para no
      mostrar un dato visual de más, y quedó sin verificar si el rótulo seguía
      apareciendo. No aparecía. Causa raíz, verificada en vivo con `getOption()` y
      pruebas controladas: en ECharts, el label de una serie se cuelga del elemento
      gráfico del símbolo — sin símbolo (`symbol:'none'`) o con el símbolo
      completamente transparente (`itemStyle.opacity:0`, probado aparte, mismo
      resultado) no hay dónde colgar el texto y no se dibuja nada, aunque el dato sea
      perfecto. Se probaron los dos por separado antes de encontrar lo que sí
      funciona: un símbolo real, pintado del mismo blanco fijo del fondo del panel
      (`--sup`, sin variante oscura) — visualmente invisible, pero sigue siendo un
      símbolo de verdad. De paso se alinearon las tres brechas de cada sitio en una
      sola columna de borde derecho parejo (`align:'right'`), en vez de solo compartir
      la misma `distance`. Verificado en navegador en las tres instancias que
      comparten esta función (`gSitios` en Panorama, `gEnergiaSitios` en Agua y
      Energía, `gResSitios` en Ambiental): los tres muestran el porcentaje correcto
      (contrastado contra `/api/ehs/kpi-por-sitio`), en la esquina, cerca del ícono de
      descargar imagen, sin errores de consola.

## 19. Regla: solo datos desde 2024 en adelante (27-sep-2026, ronda 4)

- [x] **Investigado antes de tocar nada** — ⚠️ **corregido el 28-sep-2026: la
      versión original de este punto era falsa.** Decía que no existía ninguna lectura
      mensual real de 2023 y que "Contraste mensual" devolvía meses en blanco para
      2023. En realidad `ehs.hecho_lectura_mensual` tiene **144 lecturas de 2023**
      (agua, energía, unidades buenas y residuo total de Celta, La Estrella y
      Agencias, 12 meses; migración 0012), igual que 2024 y 2025, y
      `ehs.scorecard_anual` tiene 23 filas de 2023. La regla se aplicó igual, pero
      por esa premisa falsa quedó a medias: ver sección 26.
- [x] **Filtrado en los tres puntos donde 2023 podía aparecer o pedirse**:
      `ANIOS_CONTRASTE` en `tablero.js` pasa de `[2023,2024,2025,2026]` a
      `[2024,2025,2026]` (ya no se puede elegir en el selector); `trayectoriaAnual` en
      **los dos adaptadores** (`adaptador_sql.js` con `and sc.anio >= 2024` en el SQL,
      `adaptador_json.js` con un `.filter()` equivalente sobre el mismo JSON) deja de
      devolver el cierre de 2023; y `/api/ehs/contraste-mensual` sube su mínimo
      aceptado de `anioA`/`anioB` de 2023 a 2024, así que pedirlo a mano por URL ahora
      responde `400 parametro_invalido` en vez de devolver silenciosamente un mes a
      mes vacío. Verificado: `curl` al endpoint de trayectoria confirma que `anios[0]`
      ya es 2024; `curl` con `anioA=2023` devuelve el error; en el navegador, "Agua ·
      contra el año anterior" muestra tres barras (2024/2025/2026, no cuatro) y el
      selector de "Contraste mensual" solo ofrece 2024/2025/2026 — sin errores de
      consola. El adaptador JSON se corrigió por paridad de código (mismo cambio que
      el SQL) pero no se probó en vivo en esta ronda: esta instalación de prueba corre
      contra SQL Server, no hay un servidor en modo JSON levantado para contrastar.
- [x] **Borrado de la base, pedido expresamente por Samuel el 28-sep-2026** ("borra
      2023 de la base") — migración `0016_ehs_borrar_2023.sql`, acotada a `anio = 2023`
      en `ehs.hecho_lectura_mensual` (144 filas) y `ehs.scorecard_anual` (23 filas), sin
      tocar nada más. Verificado antes de escribirla: sin llaves foráneas hacia ninguna
      de las dos tablas, y `ehs.tr_lectura_mensual_hist` solo archiva `UPDATE` (no
      `DELETE`), así que el registro de este borrado es la propia migración — mismo
      patrón que la 0012 con la corrección del accidente. Aplicada contra la base real;
      verificado antes/después que 2024/2025/2026 quedaron intactos en las dos tablas y
      2023 en cero. La API no cambió ningún resultado (ya filtraba desde la sección 26);
      confirmado con la comparación exhaustiva de siempre, local y contra
      `deploy-web1.vercel.app` real: 614 llamadas y páginas, 0 diferencias. — `b0d4dcb`

## 20. Auditoría de calidad de esta ronda (27-sep-2026, ronda 4, cierre)

- [x] **Revisión propia del diff completo de las 5 secciones anteriores** (`80aa844`
      a `59f7015`, 8 archivos) antes de cerrar la ronda. Un hallazgo real: en
      `cargarTablaAviso` (sección 17), el `catch` reseteaba
      `cont.parentElement.dataset.cargada = '0'` — el `<details>`, no el `<div
      class="aviso-tabla">` que `wireTablasAviso` en verdad revisa
      (`cont.dataset.cargada`). Efecto: si la tabla de un aviso fallaba al cargar,
      "Intenta de nuevo" no reintentaba nada — colapsar y reabrir el desplegable se
      quedaba mostrando el mismo error para siempre, sólo un reload de página lo
      arreglaba. Corregido (`cont.dataset.cargada`, no `cont.parentElement...`) y
      verificado con un fallo de red simulado en el navegador: primera apertura falla
      y muestra el error, cerrar y reabrir sí reintenta y esta vez carga la tabla real
      — sin errores de consola ajenos a la prueba.
- [x] **Resto de la ronda revisado sin más hallazgos**: `graficos.js` (comboProduccion,
      porSitio, residuosCombo), `ehs.css` (variables usadas todas existen), los dos
      adaptadores y `rutas_api.js` (filtro de 2024 consistente en los tres), y
      `dashboard.ejs` (numeración de paneles reconciliada tras insertar el panel 03 de
      residuos).

## 21. Primer despliegue a Vercel de la ronda + hallazgos del propio despliegue (28-sep-2026)

- [x] **"Hecho por Samuel Galeano" del header, invisible** — `rgba(255,255,255,.28)`
      contra el fondo oscuro del header prácticamente no se leía. Subido a `.62` en
      `views/parciales/cabecera.ejs` — verificado en navegador, legible sin competir
      con el título.
- [x] **`/api/ehs/datos` (la tabla completa de un aviso, sección 17) siempre falla en
      el despliegue interinato de Vercel** — al verificar el deploy en producción (no
      solo contra la instalación local con SQL Server), el primer aviso que se abrió
      dio `501 sin_implementar`. Causa: `adaptador_json.js` nunca implementó
      `datosTabulados` a propósito ("esta vista necesita SQL Server"; ver el propio
      comentario del archivo) — una limitación real y ya existente antes de esta
      ronda, que la función nueva de la sección 17 recién puso a prueba por primera
      vez porque antes nada llamaba a `/api/ehs/datos` desde fuera de la instalación
      con base de datos. El bug de UX real: `cargarTablaAviso` mostraba "Intenta de
      nuevo" para esto, un mensaje falso — reintentar un `sin_implementar` nunca va a
      funcionar. Arreglado en dos partes: `api()` ahora adjunta `{codigo, mensaje,
      detalle}` del cuerpo del error al `Error` que lanza en vez de descartarlo
      (cambio retrocompatible: los demás llamadores que no miran `err.codigo` siguen
      igual), y `cargarTablaAviso` distingue el caso permanente (mensaje honesto,
      "no disponible en este despliegue interinato", sin permitir reintento) del
      transitorio (mensaje de reintento, como antes). Verificado en el propio deploy
      de Vercel tras el fix.
- [x] **Dato del despliegue interinato desactualizado (31-ago-2026), no julio** —
      confirmado en pantalla ("Actualizado 2026-08-31T16:58:43" contra el
      "2026-09-24T21:52:12" de la instalación con SQL Server): el snapshot
      `datos/datos-ehs.json` no se ha vuelto a generar desde agosto. Los textos de
      hallazgos sí están al día (se parchearon a mano esta misma sesión, sección 18),
      pero las cifras operativas (KPIs, lecturas) no. **No es un defecto de esta
      ronda ni se corrigió aquí** — corresponde a correr de nuevo el pipeline
      (`analisis/construir_datos.py` → `web_json.py` → `publicar_a_app.py`) con el
      Excel de julio, una decisión y un paso aparte que le toca al área/a Samuel, no
      algo que este cambio de UI deba disparar solo.
- [x] **Deploy verificado en `https://deploy-web1.vercel.app`** (cuenta
      `specifinance-7412's projects`, confirmada explícitamente por Samuel en el
      chat antes de tocar nada — ver la conversación). Agua/Energía, Ambiental y
      Calidad del dato revisados en el navegador contra la URL real de producción,
      sin errores de consola tras los dos arreglos de arriba.

## 22. Pin del máximo/mínimo montado sobre la leyenda (28-sep-2026)

- [x] **El pin del pico (markPoint) del combo de consumo se montaba encima de la
      leyenda** — reportado con "178,3" (residuos, junio) tapando "Consumo total
      (kg)". Causa real: `ejeValorConTecho` solo forzaba colchón arriba del eje
      contra la **meta**; cuando el dato YA supera la meta (frecuente, es lo que
      "incumple" significa), la condición de colchón se saltaba entera y ECharts
      elegía su propio máximo "redondo" sin ningún margen deliberado — a veces ese
      redondeo dejaba casi cero aire arriba del pico real (180 de eje contra un pico
      de 178,3), y el pin (que se dibuja hacia arriba desde el dato) quedaba
      literalmente encima de la leyenda. Arreglado: `ejeValorConTecho` ahora acepta
      un tercer parámetro opcional (el pico real de la serie) y calcula el colchón
      contra el mayor de los dos — meta o pico —, forzándolo siempre que el techo sea
      el pico (comparar el pico contra sí mismo nunca habría disparado el margen).
      Solo `comboProduccion` lo usa (es la única función con `markPoint` en todo el
      archivo); `serieKpi` y `composicionResiduos` siguen exactamente igual que
      antes. Verificado en navegador: el mismo gráfico de residuos que mostraba la
      superposición ahora tiene separación clara entre leyenda y pin, sin errores de
      consola.
- [x] **"Hecho por Samuel Galeano" del header, invisible** — mismo defecto que la
      sección 21, subido de `.28` a `.62` de opacidad — verificado en navegador.

## 23. "No cuadra" en TODAS las filas de Residuos, en "06 Datos" (28-sep-2026)

- [x] **Investigado antes de tocar nada, como pidió Samuel**: la fórmula mostrada
      —`(aprovechable + ordinario + peligroso + residuo total sin desglose) × 1.000 ÷
      unidades buenas`— SÍ es la correcta, verificada contra `ehs/CLAUDE.md` (la
      fórmula base documentada del área) y contra los datos reales de
      `/api/ehs/datos`: para Celta/Estrella/Agencias/Nacional Labs (sin Perú) el
      numerador del servidor coincide exacto con la suma de los tres desglosados
      (ej. Celta julio: 16.844 + 354 + 6.768 = 23.966, igual al numerador servido);
      para Perú coincide exacto con el residuo total solo (9.000 = 9.000); para
      Colombia + Perú coincide con los cuatro sumados sin pisarse. **Tampoco hay
      duplicado**, la otra sospecha de Samuel: confirmado con los datos crudos que
      Perú JAMÁS reporta peligroso/aprovechable/ordinario (esas claves ni existen en
      sus lecturas) y Celta/Estrella/Agencias JAMÁS reportan el residuo sin desglose
      — cada sitio aporta su parte una sola vez, nunca las dos a la vez.
- [x] **El bug real estaba en la comprobación del navegador, no en el cálculo**: la
      función `sumar()` de "02 De dónde salen las gráficas" cortaba a `null` la suma
      completa en cuanto tocaba **cualquier** magnitud ausente en `m.lecturas` — sin
      distinguir "esta magnitud no le corresponde a este ámbito" (residuo total sin
      desglose en un ámbito sin Perú, que JAMÁS trae dato, en ningún mes) de "esta
      magnitud sí aplica pero falta capturarla este mes" (un hueco real). Como
      residuos_por_lente siempre incluye esa cuarta magnitud en su numerador,
      cualquier ámbito sin Perú (Celta, Estrella, Agencias, Nacional Labs) daba
      "NO CUADRA" en el 100% de los meses, siempre, sin que hubiera ningún error que
      corregir. Arreglado: antes de sumar, se calcula qué magnitudes nunca aparecen
      en ningún mes de los datos ya cargados para este ámbito, y esas se tratan como
      cero (no le corresponden) en vez de invalidar la suma entera. Verificado en
      navegador: Celta/Estrella/Agencias/Nacional Labs/Colombia (`nacional`) ahora
      muestran "cuadra" los 7 meses de Residuos; Colombia + Perú (donde la cuarta
      magnitud sí aplica de verdad) también cuadra, con un numerador mayor que el de
      Colombia sola — confirma que el fix no empieza a ignorar huecos reales, solo
      los estructurales.
- [x] **Pedido aparte: nombrar bien cada columna** — "Numerador"/"Denominador"/"Del
      mes"/"Numerador acum."/"Denominador acum."/"Acumulado (YTD)"/"Comprobación"
      ahora traen un subtítulo bajo el título (mismo patrón que ya usa la tabla "01
      Las lecturas") diciendo qué es cada una: de qué magnitudes es la suma, en qué
      unidad, y contra qué se compara. La nota de abajo de toda la sección también se
      reescribió para explicar el concepto una sola vez y mencionar explícitamente
      que una magnitud sin dato en ningún mes de un ámbito no cuenta como hueco.

## 24. Vercel igual a local: copia exacta de la base (28-sep-2026)

Pedido: "actualízalo basado en todo lo que está en local, esa es la última versión"
(Vercel mostraba `actualizadoEn: 31 ago 2026 · 11:58` y cifras del manifiesto del
pipeline, no las de la base).

- [x] **Instantánea exacta de las respuestas SQL** — `analisis/exportar_instantanea_sql.js`
      (fuera de `app/`) llama al adaptador SQL con todas las combinaciones que usa el
      tablero (605 respuestas) y escribe `datos/instantanea.json`; en modo JSON,
      `adaptador_json.js` responde primero desde ahí (`src/datos/instantanea.js` define
      la llave) y solo cae al manifiesto si una llave no está. — `b9c634e`
- [x] **Hora del header 5 horas corrida en Vercel** — la base manda la hora de Colombia
      sin zona y `new Date()` en un servidor UTC le restaba 5 horas; `fechaLegible` lee
      los componentes tal cual. — `b9c634e`
- [x] **Franja de estado del modo JSON** — el texto lo pone el servidor ("copia exacta
      de la instalación con base de datos"), no una cadena fija. — `b9c634e`
- [x] **Verificado** con una instancia JSON corriendo como Vercel (TZ=UTC, Node 22)
      contra la SQL local: 605 respuestas de la API + páginas HTML, 614 comparaciones,
      0 diferencias.
- [x] **Desplegado y verificado contra la producción real** — Samuel confirmó la cuenta
      (`specifinance-7412` / `_deploy-web1`), se desplegó (`vercel deploy --prod`) y se
      corrió la comparación exhaustiva contra `https://deploy-web1.vercel.app`: **614
      llamadas y páginas, 0 diferencias**. Encontró de paso el hallazgo de la sección 27
      (formato de fecha dependiente del ICU del servidor), corregido y verificado con un
      segundo despliegue.

## 25. Los cinco hallazgos del libro que alteran un número (28-sep-2026)

Pedido: corregirlos, "dejarlo estructurado en la base de datos para evitar que estos
errores vuelvan a presentarse", guiándose por `KPI´s EHS 2026-julio_versionfinal.xlsx`,
y "corroborar que todo funcione y tenga lógica".

- [x] **Verificado primero que la base nunca tuvo ninguno** — recálculo completo desde
      la hoja cruda del libro contra `/api/ehs/datos`: 980 comparaciones, 0 diferencias.
      Ninguno de los cinco puede existir como tal en la base: no hay fórmulas por celda,
      el acumulado es una sola vista desde enero, las horas se unen por `sitio_id` y un
      mes solo se publica con las 27 lecturas de Colombia.
- [x] **Migración 0015, aplicada en la base local** — `ref.dim_magnitud.forma_residuo`
      + trigger `ehs.tr_lectura_mensual_residuo_una_forma`: un sitio-mes no puede tener
      el residuo desglosado y a la vez un total (la forma en que E60 podría repetirse en
      el dato; residuos por lente lo contaría dos veces). Probado con 6 casos dentro de
      transacciones revertidas (3 bloqueados, incluido por `sp_capturar_lote`; 3
      permitidos; conteos intactos). — `ec2177e`
- [x] **`ehs.v_calidad_avisos` comparaba contra otro año** — el `lag()` de "salto
      atípico" no particionaba por año; desde que hay 2023-2025, enero de 2026 se
      comparaba con otro año. 42 → 23 avisos (19 falsas alarmas); los de 2026 son los
      mismos 10 del tablero. El tablero no lo sufría (su consulta filtra el año antes
      del `lag()`); la vista es la que usaría IT o Power BI. — `ec2177e`
- [x] **Libro corregido** — `ehs\KPIs EHS 2026-julio_versionfinal_corregido.xlsx`
      (copia hecha con el propio Excel para no perder las 48 gráficas; el original no se
      tocó): los 12 meses de los tres sitios enlazados a la hoja cruda, YTD anclado a
      enero, frequency rate por sitio con las horas de su propio sitio, consolidados con
      horas temporales, accidentes de `AT 2026` enlazados, y el accidente de Celta en
      julio (O10 = 0, U10 = 1, con comentario). Verificado: solo cambiaron de valor E60,
      L9 y L11; **202 comparaciones libro corregido contra la base, 0 diferencias**.
- [x] **Hallazgos cerrados en el tablero** — los cinco + "dos mecanismos" pasan a "ya
      corregidos" con su ficha reescrita (valor original → valor corregido, qué se hizo,
      qué impide que se repita); la tarjeta cuenta solo los abiertos que alteran un
      número (0) y un hallazgo corregido deja de pintarse en rojo. Queda abierto solo
      "gráfica 6" (confunde, no altera un número). Verificado en navegador en `C:\EHS`,
      sin errores de consola. — `ec2177e` (el texto de los hallazgos vive en
      `datos.json`, fuera de git)
- [x] **`datos/correcciones.csv`** — registra la corrección del accidente (mayo 1 → 0,
      julio 0 → 1) para que el pipeline Excel → JSON la aplique igual que la base, con
      una columna `visible_en_tablero = no`: no se pinta como franja, como pidió Samuel
      el 24-sep (migración 0012). `analisis/web_json.py` respeta esa columna.
- [ ] **Pendiente de Samuel, fuera del tablero**: reemplazar el libro de SharePoint por
      la copia corregida. Hasta entonces, quien abra el de SharePoint sigue viendo los
      cinco errores.

## 26. Regla 2024 completa y corrección de una afirmación falsa (28-sep-2026)

- [x] **La razón que se dio en la sección 19 era falsa** (2023 sí tiene 144 lecturas
      mensuales reales) y por eso la regla quedó a medias: `/api/ehs/*` aceptaba
      `anio=2023` por URL y servía datos reales de 2023, y captura / consultar y
      corregir aceptaban 2023. Ahora el mínimo es 2024 en la API, en el servidor de
      captura y corrección, en `validacion.js` y en los dos formularios; los comentarios
      dicen la razón verdadera. Verificado con `curl`: todos los endpoints con año
      responden 400 para 2023 y 200 para 2026; `/captura` y `/corregir` cargan con
      `min="2024"`. — `f65a958`

## 27. "Generado" del reporte, encontrado al comparar contra Vercel real (28-sep-2026)

La comparación exhaustiva de la sección 24 se había corrido hasta ahora contra una
instancia JSON local simulando Vercel, nunca contra la producción real. La primera vez
que corrió contra `deploy-web1.vercel.app` de verdad salió una diferencia real:

- [x] **El pie del reporte descargable daba un texto distinto en cada servidor para el
      mismo instante** — `generadoEn` usaba `toLocaleString('es-CO', {dateStyle:'long',
      timeStyle:'short'})`; esa plantilla (espacio angosto entre "p." y "m." en un Node,
      "a las" en otro) la decide el ICU/CLDR de cada servidor, no el código — mismo
      defecto que ya se había encontrado y evitado en `fechaLegible` (cabecera del
      tablero, sección 21). `fechaLargaBogota()` sigue el mismo patrón: solo pide a
      `Intl.DateTimeFormat` partes numéricas (siempre estables) y arma el texto a mano.
      Verificado con tres instantes (mediodía, medianoche, cruce de día) y redesplegado:
      comparación exhaustiva contra la producción real, 614 llamadas y páginas, 0
      diferencias. — `196a4b4`

---

## Cómo se usa este archivo de aquí en adelante

1. Cuando llegue una solicitud nueva, se agrega como `- [ ]` bajo la sección que le
   corresponda (o una sección nueva si no encaja en ninguna).
2. Se implementa, se sincroniza a `C:\EHS`, se reinicia el servidor de prueba y se
   verifica en el navegador — nunca se marca `[x]` sin ese paso.
3. Al marcar `[x]` se anota el hash corto del commit que la cerró.
4. Si algo queda a medias o depende de que Samuel confirme una decisión (como el
   deploy a Vercel), se deja en "Pendiente ahora mismo" con la razón exacta, no
   simplemente sin marcar.
