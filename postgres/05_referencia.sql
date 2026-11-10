/* =============================================================================
   05_referencia.sql — dimensiones de referencia (ref.*), estado final

   Metadato de catalogo, no dato operativo: sitios, calendario, magnitudes, KPI
   y la formula de cada KPI (ref.kpi_magnitud). Sin esto las 3 funciones de
   escritura rechazan cualquier lote con "El mes no existe en ref.dim_fecha" o
   "El sitio/magnitud no existe" — es la pieza que faltaba para que la ingesta
   funcione de verdad contra Neon, no solo que el motor conecte.

   Porte del ESTADO FINAL (no de una migracion sola) de las tablas ref.* en el
   SQL Server original, reconstruido leyendo en orden migraciones/0008
   (carga inicial), 0010 (calendario 2023-2035), 0011 (Peru operativo, Colombia
   como sitio virtual, residuo_total_kg, maximo 2 decimales), 0013 (Peru se
   rotula como pais) y 0015 (forma_residuo). Las migraciones 0012/0018/0019 son
   dato operativo (lecturas, correcciones, avisos) y quedan fuera a proposito:
   ese es el histórico real de la empresa, pendiente de una decision aparte
   sobre si entra a esta base publica.

   Idempotente (insert ... on conflict), igual que 01-04. Se corre con
   ehs_migrador, despues de 01-04. */

/* ------------------------------------------------------------------ sitios */
insert into ref.dim_sitio
    (sitio_id, sitio, sitio_corto, nombre_corporativo, tipo, ciudad,
     en_nacional_labs, en_nacional, en_colombia_peru, activo)
values
    ('celta', 'Laboratorio Celta', 'Celta', 'SERVIOPTICA/Bogota', 'Laboratorio', 'Bogota',
     true, true, true, true),
    ('estrella', 'Laboratorio La Estrella', 'La Estrella', 'SERVIOPTICA/Medellin', 'Laboratorio', 'Medellin',
     true, true, true, true),
    ('agencias', 'Consolidado Agencias', 'Agencias', 'SERVIOPTICA/Agencias Bogota', 'Agencias', 'Bogota',
     false, true, true, true),
    -- 'TOPSA (Peru)' en la carga inicial (0008); 0011 lo vuelve operativo
    -- (tipo Laboratorio, miembro de colombia_peru); 0013 lo rotula como pais.
    ('peru', 'Perú', 'Perú', 'Perú', 'Laboratorio', 'Peru',
     false, false, true, true),
    -- 'colombia_peru' y 'nacional' son sitios virtuales: nunca capturan una
    -- lectura propia, solo le dan a ehs.meta/ehs.scorecard_anual un FK donde
    -- apuntar. activo=false los saca de la rama de ehs.v_ambito que auto-mapea
    -- cada sitio activo a su propio ambito (ver migracion 0011).
    ('colombia_peru', 'Colombia y Peru', 'Colombia y Peru', 'COLOMBIA y PERU', 'Consolidado', '-',
     false, false, false, false),
    ('nacional', 'Colombia', 'Colombia', 'Colombia (Celta + Estrella + Agencias)', 'Consolidado', '-',
     false, false, false, false)
on conflict (sitio_id) do update set
    sitio = excluded.sitio,
    sitio_corto = excluded.sitio_corto,
    nombre_corporativo = excluded.nombre_corporativo,
    tipo = excluded.tipo,
    ciudad = excluded.ciudad,
    en_nacional_labs = excluded.en_nacional_labs,
    en_nacional = excluded.en_nacional,
    en_colombia_peru = excluded.en_colombia_peru,
    activo = excluded.activo;

/* ------------------------------------------------------------------ fechas
   Grano mensual 2023-01 a 2035-12 (mismo rango que la migracion 0010). */
insert into ref.dim_fecha (fecha, anio, num_mes, mes, mes_corto, anio_mes, trimestre)
select
    f::date,
    extract(year from f)::smallint,
    extract(month from f)::smallint,
    (array['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto',
           'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'])[extract(month from f)::int],
    (array['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'])
        [extract(month from f)::int],
    to_char(f, 'YYYY-MM'),
    'T' || ((extract(month from f)::int + 2) / 3)::text
from generate_series('2023-01-01'::date, '2035-12-01'::date, interval '1 month') as f
on conflict (fecha) do nothing;

/* -------------------------------------------------------------- magnitudes
   valor_min/valor_max: +-50% sobre el historico real 2026, el cinturon contra
   el error de tecleo (no es regla de negocio). requerida_colombia/forma_residuo
   agregadas en 0011/0015: residuo_total_kg es la forma de Peru y del historico
   2023-2025 (sin desglose); las tres de siempre son la forma de Colombia 2026. */
insert into ref.dim_magnitud
    (magnitud_id, magnitud, unidad, area, valor_min, valor_max, orden,
     requerida_colombia, forma_residuo)
values
    ('residuo_peligroso_kg', 'Residuo peligroso', 'kg', 'ehs', 15.0, 21060.0, 1,
     true, 'desglose'),
    ('residuo_aprovechable_kg', 'Residuo aprovechable', 'kg', 'ehs', 400.0, 28701.0, 2,
     true, 'desglose'),
    ('residuo_ordinario_kg', 'Residuo ordinario', 'kg', 'ehs', 133.0, 6744.0, 3,
     true, 'desglose'),
    ('agua_m3', 'Agua', 'm3', 'ehs', 110.0, 913.5, 4,
     true, null),
    ('energia_kwh', 'Energia', 'kWh', 'ehs', 21827.0, 282792.0, 5,
     true, null),
    ('accidentes_dafw', 'Accidentes DAFW', 'casos', 'ehs', 0.0, 1.5, 6,
     true, null),
    ('unidades_buenas', 'Unidades buenas producidas', 'lentes', 'ehs', 29258.5, 165361.5, 7,
     true, null),
    ('horas_fijos', 'Horas hombre fijos', 'h', 'ehs', 19423.5, 161880.0, 8,
     true, null),
    ('horas_temp', 'Horas hombre temporales', 'h', 'ehs', 0.0, 14982.0, 9,
     true, null),
    ('residuo_total_kg', 'Residuo total (sin desglose)', 'kg', 'ehs', 500.0, 41760.0, 10,
     false, 'total')
on conflict (magnitud_id) do update set
    magnitud = excluded.magnitud,
    unidad = excluded.unidad,
    valor_min = excluded.valor_min,
    valor_max = excluded.valor_max,
    orden = excluded.orden,
    requerida_colombia = excluded.requerida_colombia,
    forma_residuo = excluded.forma_residuo;

/* -------------------------------------------------------------------- KPI
   formato: maximo 2 decimales (regla del area, 24-sep-2026) — agua/energia/
   frequency_rate bajaron de 3 a 2; residuos ya estaba en 1 y no se toca. */
insert into ref.dim_kpi (kpi_id, kpi, unidad, familia, area, factor, mejor_es, formato, orden)
values
    ('agua_por_lente', 'Agua', 'l/lente', 'Ambiental', 'ehs', 1000.0, 'menor', '0.00', 1),
    ('energia_por_lente', 'Energía', 'kWh/lente', 'Ambiental', 'ehs', 1.0, 'menor', '0.00', 2),
    ('residuos_por_lente', 'Residuos', 'g/lente', 'Ambiental', 'ehs', 1000.0, 'menor', '0.0', 3),
    ('frequency_rate', 'Frequency rate', 'acc/MHH', 'Seguridad', 'ehs', 1000000.0, 'menor', '0.00', 4),
    ('accidentes_dafw', 'Accidentes DAFW', 'casos', 'Seguridad', 'ehs', 1.0, 'menor', '0', 5)
on conflict (kpi_id) do update set
    kpi = excluded.kpi,
    unidad = excluded.unidad,
    familia = excluded.familia,
    factor = excluded.factor,
    mejor_es = excluded.mejor_es,
    formato = excluded.formato,
    orden = excluded.orden;

/* ------------------------------------------- la formula de cada KPI, como dato
   Residuos suma cuatro magnitudes numeradoras (tres si el sitio-mes desglosa,
   una si reporta total — nunca las dos, ver el trigger de 03). */
insert into ref.kpi_magnitud (kpi_id, magnitud_id, rol)
values
    ('agua_por_lente', 'agua_m3', 'numerador'),
    ('agua_por_lente', 'unidades_buenas', 'denominador'),
    ('energia_por_lente', 'energia_kwh', 'numerador'),
    ('energia_por_lente', 'unidades_buenas', 'denominador'),
    ('residuos_por_lente', 'residuo_peligroso_kg', 'numerador'),
    ('residuos_por_lente', 'residuo_aprovechable_kg', 'numerador'),
    ('residuos_por_lente', 'residuo_ordinario_kg', 'numerador'),
    ('residuos_por_lente', 'residuo_total_kg', 'numerador'),
    ('residuos_por_lente', 'unidades_buenas', 'denominador'),
    ('frequency_rate', 'accidentes_dafw', 'numerador'),
    ('frequency_rate', 'horas_fijos', 'denominador'),
    ('frequency_rate', 'horas_temp', 'denominador'),
    ('accidentes_dafw', 'accidentes_dafw', 'numerador')
on conflict (kpi_id, magnitud_id, rol) do nothing;

\echo 'Referencia cargada: sitios, calendario 2023-2035, magnitudes, KPI y su formula.'
