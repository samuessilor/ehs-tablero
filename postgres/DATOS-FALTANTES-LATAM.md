# Datos faltantes - expansion LATAM (10 paises nuevos)
Generado automaticamente al cargar `postgres/06_paises_latam.sql` desde el Excel "EHS BD LATAM", hoja TARGETS (version entregada 10-nov-2026). Todo lo de aqui NO se inventa: se deja sin fila en `ehs.meta` (ausencia = sin meta, nunca un cero) y se lista abajo para que EHS lo confirme.

## 1. Sitios que existen operativamente pero sin meta propia en el Excel

TARGETS solo trae meta a nivel de PAIS para estos; sus sitios reales (varios por pais) quedan sin meta individual hasta que EHS la desglose:

| Sitio | Pais | Nota |
|---|---|---|
| Opti-Express Santo Domingo | Republica Dominicana | Meta solo existe a nivel pais (Republica Dominicana) |
| Opti-Express Santiago | Republica Dominicana | Meta solo existe a nivel pais (Republica Dominicana) |
| Lab Express Guatemala | Guatemala | Meta solo existe a nivel pais (Guatemala) |
| Lab Central OE Guatemala | Guatemala | Meta solo existe a nivel pais (Guatemala) |
| Optica Popular Honduras | Honduras | Meta solo existe a nivel pais (Honduras) |
| Indulentes Quito | Ecuador | Meta solo existe a nivel pais (Ecuador) |
| Indulentes Guayaquil | Ecuador | Meta solo existe a nivel pais (Ecuador) |
| Indulentes Quito Express GYQ | Ecuador | Meta solo existe a nivel pais (Ecuador) |
| Indulentes Quito Santo Domingo | Ecuador | Meta solo existe a nivel pais (Ecuador) |
| Indulentes Quito Cuenca | Ecuador | Meta solo existe a nivel pais (Ecuador) |
| Warehouse ELAC | Estados Unidos | Meta solo existe a nivel pais (Estados Unidos) |

## 2. Metas puntuales faltantes (fila existe, dato en blanco en el Excel)

| Ambito | KPI | Nota |
|---|---|---|
| Nicaragua (nicaragua) | residuos_por_lente | Celda vacia en TARGETS |
| Minas Gerais / Belo Horizonte (brasil_minas_gerais) | agua_por_lente | Celda vacia en TARGETS |
| Minas Gerais / Belo Horizonte (brasil_minas_gerais) | energia_por_lente | Celda vacia en TARGETS |
| Minas Gerais / Belo Horizonte (brasil_minas_gerais) | residuos_por_lente | Celda vacia en TARGETS |
| Minas Gerais / Belo Horizonte (brasil_minas_gerais) | frequency_rate | Celda vacia en TARGETS |
| Minas Gerais / Belo Horizonte (brasil_minas_gerais) | accidentes_dafw | Celda vacia en TARGETS |
| Mas Vision (arg_mas_vision) | agua_por_lente | Celda vacia en TARGETS |
| Mas Vision (arg_mas_vision) | energia_por_lente | Celda vacia en TARGETS |
| Mas Vision (arg_mas_vision) | residuos_por_lente | Celda vacia en TARGETS |
| Vision Rx Managua (nicaragua_managua) | residuos_por_lente | Celda vacia en TARGETS |

## 3. Pais sin ninguna meta 2026 en el Excel

**Estados Unidos (EUA)** -- tenia un sitio operativo (Warehouse ELAC, hoja `EUA` del Excel con historico 2019-2023), pero la hoja TARGETS no trae ninguna fila para EUA, de ningun KPI, ni tampoco lecturas 2026. Se retiro el pais/sitio/ambito de la estructura (código y base) en vez de dejarlo cargado y en `sin_meta` permanente; si EHS entrega target y lecturas 2026 para ELAC, se vuelve a dar de alta igual que cualquier sitio nuevo.

## 4. A confirmar con EHS (no es un vacio, es una posible actualizacion)

**Peru - frequency rate / accidentes DAFW.** La version vigente de `ehs.meta` tiene estos dos KPI de Peru en `sin dato` (Peru todavia no reporta horas-hombre ni accidentes). La hoja TARGETS de este Excel nuevo SI trae una meta 2026 para ambos (0 y 0). No se sobrescribio la meta vigente de Peru con este archivo -- se deja igual que estaba hasta que EHS confirme si ese 0/0 es la meta real o un valor por defecto del libro.

## 5. Resumen de lo que SI quedo cargado

- 14 ambitos nuevos: LATAM, 2 regiones (Andina, Centroamerica y Caribe), 11 paises.
- 39 sitios/laboratorios nuevos (ver `ref.dim_sitio`).
- 190 filas de meta 2026 cargadas en `ehs.meta` (fuente: hoja TARGETS).
- Celta, Estrella, Agencias, Peru y Colombia+Peru: **sin ningun cambio** -- mismas filas, mismas vistas, mismo resultado que antes de este archivo.

## 6. Lecturas mensuales 2026 (postgres/08_lecturas_latam.sql, 17-nov-2026)

Carga de lecturas reales enero-octubre 2026 para los paises LATAM (Mexico, Argentina,
Chile, Costa Rica, Nicaragua, Guatemala, Honduras, Ecuador, Republica Dominicana,
Brasil), desde `EHS BD LATAM (3).xlsx`. Noviembre/diciembre 2026 NO se cargan: el Excel
los trae pre-llenados con ceros de plantilla (ej. accidentes_dafw=0), no un dato
reportado -- un mes que no ha cerrado no se confirma (R.5).

**6 sitios nuevos, sin meta propia todavia** (entran a la cuenta agregada de su pais,
`sin_meta` en solitario hasta que EHS la fije):

| Sitio | Pais | Nota |
|---|---|---|
| `chile_megalux_ag` (Agencias Megalux Chile) | Chile | Ya anticipado en `src/validacion.js`; faltaba en `ref.dim_sitio` |
| `honduras_popular_ag` (Agencias Optica Popular Honduras) | Honduras | Idem |
| `brasil_unilab_ag` (Agencias Unilab Fortaleza) | Brasil | Idem -- solo reporta enero/febrero 2026 |
| `ecuador_quito_versalles` (Indulentes Quito Versalles) | Ecuador | Descubierto en esta carga: fila separada de "Indulentes Quito" con dato propio distinto, no estaba en la estructura |
| `brasil_duque_caxias` (Multioptica Duque de Caxias) | Brasil | Descubierto en esta carga. 0 lentes producidos pero si consume agua/energia/residuos -- perfil de agencia, no de laboratorio |
| `brasil_sumare` (Lab Sumare) | Brasil | Descubierto en esta carga, producción real (600+ lentes/mes) |

Ciudad en `null` donde no se pudo verificar contra el Excel ni contra ningun otro
documento del area -- no se inventa.

**La mayoria de las filas "... AGENCIES (N)" de LATAM siguen sin sitio propio**
(confirmado de nuevo, celda por celda, para las 13 que aparecen en MEX/ARG/BRA): todos
los meses de 2026 en blanco o en cero. Si alguna reporta dato real en el futuro, se
agrega entonces.
