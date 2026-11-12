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

**Estados Unidos (EUA)** -- tiene un sitio operativo (Warehouse ELAC, hoja `EUA` del Excel con historico 2019-2023) pero la hoja TARGETS no trae ninguna fila para EUA, de ningun KPI. Se cargo el sitio y el ambito `eua` para que la estructura ya lo soporte, pero sin ninguna fila en `ehs.meta` -- el tablero lo mostrara como `sin_meta` en los 5 KPI hasta que EHS entregue el target.

## 4. A confirmar con EHS (no es un vacio, es una posible actualizacion)

**Peru - frequency rate / accidentes DAFW.** La version vigente de `ehs.meta` tiene estos dos KPI de Peru en `sin dato` (Peru todavia no reporta horas-hombre ni accidentes). La hoja TARGETS de este Excel nuevo SI trae una meta 2026 para ambos (0 y 0). No se sobrescribio la meta vigente de Peru con este archivo -- se deja igual que estaba hasta que EHS confirme si ese 0/0 es la meta real o un valor por defecto del libro.

## 5. Resumen de lo que SI quedo cargado

- 14 ambitos nuevos: LATAM, 2 regiones (Andina, Centroamerica y Caribe), 11 paises.
- 39 sitios/laboratorios nuevos (ver `ref.dim_sitio`).
- 190 filas de meta 2026 cargadas en `ehs.meta` (fuente: hoja TARGETS).
- Celta, Estrella, Agencias, Peru y Colombia+Peru: **sin ningun cambio** -- mismas filas, mismas vistas, mismo resultado que antes de este archivo.
