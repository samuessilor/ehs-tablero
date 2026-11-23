/* =============================================================================
   09_octubre_colombia_peru.sql -- octubre 2026 de Celta, Estrella, Agencias y
   Peru, desde las hojas COL y PER de "EHS BD LATAM (3).xlsx" (hojas CELTA
   BOGOTA, ESTRELLA MEDELLIN, CELTA BOGOTA AGENCIES (29), TOPSA PERU).

   Celta/Estrella/Agencias: residuo desglosado (peligroso/ordinario/aprovechable),
   igual que sus meses anteriores. Peru: residuo_total_kg (sin desglose), igual
   forma que ya tiene cargada en sus meses 1-9 -- ehs.tr_lectura_mensual_residuo_una_forma
   rechaza mezclar las dos formas en el mismo sitio.

   Sin desglose de horas fijas/temporales en esta hoja (una sola columna "Horas
   trabajadas"): horas_fijos = el total, horas_temp = 0, mismo criterio que ya
   usa Peru en sus meses anteriores.

   Idempotente (insert ... on conflict ... do update).
   ============================================================================= */

begin;

insert into ehs.hecho_lectura_mensual (fecha, sitio_id, magnitud_id, valor, origen) values
('2026-10-01','celta','horas_fijos',85105,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','horas_temp',0,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','unidades_buenas',110998,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','accidentes_dafw',0,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','agua_m3',437,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','energia_kwh',181133,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','residuo_peligroso_kg',10430,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','residuo_ordinario_kg',400,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','celta','residuo_aprovechable_kg',15740,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),

('2026-10-01','estrella','horas_fijos',40905,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','horas_temp',0,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','unidades_buenas',61028,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','accidentes_dafw',0,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','agua_m3',636,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','energia_kwh',102154,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','residuo_peligroso_kg',1260,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','residuo_ordinario_kg',4000,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','estrella','residuo_aprovechable_kg',950,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),

('2026-10-01','agencias','horas_fijos',110272,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','horas_temp',0,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','unidades_buenas',68536,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','accidentes_dafw',0,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','agua_m3',250,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','energia_kwh',46520,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','residuo_peligroso_kg',30,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','residuo_ordinario_kg',1200,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),
('2026-10-01','agencias','residuo_aprovechable_kg',1150,'Excel "EHS BD LATAM (3).xlsx", hoja COL'),

('2026-10-01','peru','horas_fijos',51357,'Excel "EHS BD LATAM (3).xlsx", hoja PER'),
('2026-10-01','peru','horas_temp',0,'Excel "EHS BD LATAM (3).xlsx", hoja PER'),
('2026-10-01','peru','unidades_buenas',86399,'Excel "EHS BD LATAM (3).xlsx", hoja PER'),
('2026-10-01','peru','accidentes_dafw',0,'Excel "EHS BD LATAM (3).xlsx", hoja PER'),
('2026-10-01','peru','agua_m3',862.5,'Excel "EHS BD LATAM (3).xlsx", hoja PER'),
('2026-10-01','peru','energia_kwh',250275.92,'Excel "EHS BD LATAM (3).xlsx", hoja PER'),
('2026-10-01','peru','residuo_total_kg',12410,'Excel "EHS BD LATAM (3).xlsx", hoja PER')
on conflict (fecha, sitio_id, magnitud_id) do update set
    valor = excluded.valor
    where ehs.hecho_lectura_mensual.valor <> excluded.valor;

commit;
