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

---

## Pendiente ahora mismo

- [~] **Confirmar que el PDF ya no se sobrepone al imprimir** — el fix (sección 7) quedó
      implementado con el mecanismo correcto y verificado que se dispara, pero no se
      pudo probar contra una impresión real desde aquí. Falta que Samuel descargue el
      reporte de nuevo y confirme.
- [~] **Confirmar que ya no se ven recuadros unidos ni el crédito solo en la última
      hoja** — fix nuevo (sección 11), mismo motivo: requiere una impresión/PDF real
      para verse, no simulable desde aquí.
- Nota sobre el metadato Autor del PDF: no es solucionable vía `window.print()` — ver
  el detalle en la sección 7. El crédito visible en el pie del reporte ya cumple el
  mismo propósito.

El sitio (`deploy-web1.vercel.app`) todavía NO tiene los cambios de la sección 11 — el
último despliegue es anterior a esta ronda. Pendiente de que Samuel confirme
`vercel whoami`/`vercel teams ls` antes del próximo `vercel deploy` (regla del área).

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
