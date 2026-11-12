/* =============================================================================
   07_meta_colombia.sql -- meta 2026 de Colombia y Peru en ehs.meta.

   05_referencia.sql cargo dimensiones (sitios, calendario, magnitudes, KPI) pero
   NUNCA las metas de Colombia/Peru en si -- ehs.meta quedo vacia para celta,
   estrella, agencias, nacional, colombia_peru y peru hasta este archivo. Se
   descubrio el 12-nov-2026 verificando visualmente la expansion LATAM: cada KPI
   de Colombia mostraba "Sin meta" en el tablero real contra Neon.

   Fuente de cada valor: ehs\CLAUDE.md, seccion "Metas 2026" (ya documentada y
   fechada ahi, no es un valor nuevo):
     - celta / estrella / agencias / colombia_peru (los 5 KPI de cada uno):
       scorecard corporativo 2026, vigente desde la carga inicial.
     - nacional (Colombia) agua/energia/residuos (5.18 / 1.27 / 134.9):
       confirmados verbalmente por el manager de la implementacion en la
       reunion del 24-sep-2026 -- NO estan en ningun Excel que EHS haya
       enviado (el libro "KPIs 2026!F14:H14" seguia en 7.5/1.5/126, la meta
       anterior; esa version vieja NO se carga aqui a proposito).
     - nacional frequency_rate/accidentes_dafw (1.6 / 5): "Excel
       indicadores!C39:C43 (sin referencia)" -- correccion del 28-sep-2026:
       estos dos NUNCA fueron del scorecard corporativo, aunque el valor
       siempre fue correcto.
     - peru agua/energia/residuos (14.23 / 2.58 / 95.8): hoja 'Lab Topsa
       Peru', "KPI's EHS Colombia Y Peru.xlsx". Peru NO tiene fila de
       frequency_rate ni accidentes_dafw -- todavia no reporta esa
       magnitud (ausencia de meta, no un cero), igual que en el Excel.
     - nacional_labs: sin meta a proposito -- nadie publica un objetivo
       para ese subconjunto (ver el comentario ya existente en
       adaptador_sql.js, META_DE_AMBITO).

   NO se cargan aqui los otros dos juegos de metas que ehs\CLAUDE.md deja
   "pendientes de confirmar con EHS" (el bloque A94 de residuo del ano
   pasado, y indicadores!C41:C43 con 5.3/1.27/90.4) -- esos siguen sin
   confirmar, cargarlos seria inventar cual es la vigente.

   Idempotente (insert ... on conflict), se corre con ehs_migrador despues de
   01-06.
   ============================================================================= */

begin;

insert into ehs.meta (anio, ambito_id, kpi_id, valor, fuente, vigente) values
    (2026, 'celta', 'agua_por_lente', 7.23, 'scorecard corporativo 2026', true),
    (2026, 'celta', 'energia_por_lente', 1.96, 'scorecard corporativo 2026', true),
    (2026, 'celta', 'residuos_por_lente', 228.45, 'scorecard corporativo 2026', true),
    (2026, 'celta', 'frequency_rate', 2.03, 'scorecard corporativo 2026', true),
    (2026, 'celta', 'accidentes_dafw', 1.9, 'scorecard corporativo 2026', true),

    (2026, 'estrella', 'agua_por_lente', 8.71, 'scorecard corporativo 2026', true),
    (2026, 'estrella', 'energia_por_lente', 1.53, 'scorecard corporativo 2026', true),
    (2026, 'estrella', 'residuos_por_lente', 84.2, 'scorecard corporativo 2026', true),
    (2026, 'estrella', 'frequency_rate', 6.2, 'scorecard corporativo 2026', true),
    (2026, 'estrella', 'accidentes_dafw', 2.85, 'scorecard corporativo 2026', true),

    (2026, 'agencias', 'agua_por_lente', 3.4, 'scorecard corporativo 2026', true),
    (2026, 'agencias', 'energia_por_lente', 0.59, 'scorecard corporativo 2026', true),
    (2026, 'agencias', 'residuos_por_lente', 25.8, 'scorecard corporativo 2026', true),
    (2026, 'agencias', 'frequency_rate', 0, 'scorecard corporativo 2026', true),
    (2026, 'agencias', 'accidentes_dafw', 0, 'scorecard corporativo 2026', true),

    (2026, 'colombia_peru', 'agua_por_lente', 8.39, 'scorecard corporativo 2026', true),
    (2026, 'colombia_peru', 'energia_por_lente', 1.67, 'scorecard corporativo 2026', true),
    (2026, 'colombia_peru', 'residuos_por_lente', 126, 'scorecard corporativo 2026', true),
    (2026, 'colombia_peru', 'frequency_rate', 1.76, 'scorecard corporativo 2026', true),
    (2026, 'colombia_peru', 'accidentes_dafw', 5, 'scorecard corporativo 2026', true),

    (2026, 'nacional', 'agua_por_lente', 5.18,
     'reunion 24-sep-2026 (confirmado verbalmente por el manager de la implementacion)', true),
    (2026, 'nacional', 'energia_por_lente', 1.27,
     'reunion 24-sep-2026 (confirmado verbalmente por el manager de la implementacion)', true),
    (2026, 'nacional', 'residuos_por_lente', 134.9,
     'reunion 24-sep-2026 (confirmado verbalmente por el manager de la implementacion)', true),
    (2026, 'nacional', 'frequency_rate', 1.6, 'Excel indicadores!C39:C43 (sin referencia)', true),
    (2026, 'nacional', 'accidentes_dafw', 5, 'Excel indicadores!C39:C43 (sin referencia)', true),

    (2026, 'peru', 'agua_por_lente', 14.23, 'hoja ''Lab Topsa Peru'', KPI''s EHS Colombia Y Peru.xlsx', true),
    (2026, 'peru', 'energia_por_lente', 2.58, 'hoja ''Lab Topsa Peru'', KPI''s EHS Colombia Y Peru.xlsx', true),
    (2026, 'peru', 'residuos_por_lente', 95.8, 'hoja ''Lab Topsa Peru'', KPI''s EHS Colombia Y Peru.xlsx', true)
on conflict (anio, ambito_id, kpi_id, fuente) do update set
    valor = excluded.valor, vigente = excluded.vigente;

commit;

\echo 'Meta 2026 de Colombia y Peru cargada: 28 filas (celta/estrella/agencias/colombia_peru: 5 c/u, nacional: 5, peru: 3).'
