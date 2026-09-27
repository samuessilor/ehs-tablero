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

- [ ] **Desplegar a Vercel** — todo lo de abajo está commiteado en `master` pero el sitio
      público (`deploy-web1.vercel.app`) sigue en una versión de antes de esta ronda de
      cambios. Varios de los reportes de Samuel fueron sobre esa versión vieja (el rombo,
      la leyenda en teal, "TOPSA") y ya estaban resueltos en local sin que se notara.
      Pendiente de la confirmación de cuenta/equipo de Vercel antes de correr el deploy
      (regla del área, `EssilorLuxottica/CLAUDE.md` punto 6). Cuenta detectada:
      `specifinance-7412`, equipo `specifinance-7412's projects` — falta que Samuel la
      confirme.
- [ ] **Verdes y rojos: misma gama entre gráficas de barras y el mapa de calor, tomando
      la del mapa de calor** — probablemente ya resuelto (heatmap y `C.cumple`/
      `C.incumple` ya comparten los mismos hex desde antes de este pedido), pero la
      captura que lo mostraba era del sitio viejo de Vercel. Re-revisar después del
      deploy antes de tocar nada más aquí.

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
- [ ] Verdes/rojos con la misma gama entre todas las gráficas y el mapa de calor — ver
      "Pendiente ahora mismo"

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
      "Cierre del año" (mismo término que ya usa el tooltip), y la barra del año en
      curso ahora dice "en curso" encima suyo, no solo en la nota de abajo — `efb7824`

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
