/* =====================================================================
   Migracion 0020 - corte de agosto de 2026 (30-sep-2026)
   ---------------------------------------------------------------------
   GENERADO desde datos/hechos_mensual_2026.csv, que construir_datos.py arma
   leyendo la hoja cruda 'indicadores mensuales LABS' y 'AT 2026' de
   "KPI's EHS 2026 - agosto.xlsx". No editar a mano.

   Agrega agosto de 2026 para Celta, La Estrella y Agencias: 27 lecturas (3 sitios
   por las 9 magnitudes crudas, igual que enero a julio). Con eso
   ehs.v_corte_publicado pasa a dar agosto: el corte es el ultimo mes en que los
   tres sitios traen todas las magnitudes que Colombia captura.

   Por que una migracion y no la pantalla de captura: una instalacion nueva debe
   dar el mismo dato que la instalacion de referencia (0018 y 0019), y las
   capturas hechas desde la pantalla viven solo en la base en la que se hicieron.
   Mismo camino que 0012 (historico y Peru).

   Solo inserta (nunca actualiza): si alguien ya capturo agosto desde el tablero,
   esos valores no se pisan. Es idempotente.

   capturado_en va fijo, no con la hora de aplicacion: el encabezado "Actualizado"
   sale de max(coalesce(modificado_en, capturado_en)), y con la hora de cada
   instalacion dos instalaciones con el mismo dato dirian cosas distintas (el
   problema que resolvio 0019).

   Lo que el libro de agosto trae y NO se carga tal cual:
   - Celta, mayo: el libro sigue con 1 accidente con dias perdidos. Ya esta en 0
     en la base (0012/0018, confirmado por el manager de la implementacion el
     24-sep-2026: el unico accidente del ano fue en julio). Esta migracion no
     toca meses anteriores.
   - Celta, julio: el libro de agosto ya trae 1, igual que la base. La
     correccion de julio de datos/correcciones.csv caduco sola. */

set nocount on;
go

merge ehs.hecho_lectura_mensual as d
using (values
    ('2026-08-01', 'celta', 'residuo_peligroso_kg', 10138.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'residuo_aprovechable_kg', 17088.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'residuo_ordinario_kg', 390.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'agua_m3', 454.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'energia_kwh', 181677.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'accidentes_dafw', 0.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'unidades_buenas', 107937.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'horas_fijos', 84571.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'celta', 'horas_temp', 0.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'residuo_peligroso_kg', 951.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'residuo_aprovechable_kg', 958.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'residuo_ordinario_kg', 6790.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'agua_m3', 560.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'energia_kwh', 106304.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'accidentes_dafw', 0.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'unidades_buenas', 60198.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'horas_fijos', 41866.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'estrella', 'horas_temp', 0.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'residuo_peligroso_kg', 35.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'residuo_aprovechable_kg', 1200.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'residuo_ordinario_kg', 1250.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'agua_m3', 270.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'energia_kwh', 45620.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'accidentes_dafw', 0.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'unidades_buenas', 61844.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'horas_fijos', 100922.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado'),
    ('2026-08-01', 'agencias', 'horas_temp', 9394.0, 'KPI''s EHS 2026 - agosto.xlsx / indicadores mensuales LABS', 'validado')) as o (fecha, sitio_id, magnitud_id, valor, origen, estado)
   on d.fecha = o.fecha and d.sitio_id = o.sitio_id and d.magnitud_id = o.magnitud_id
 when not matched then insert
      (fecha, sitio_id, magnitud_id, valor, origen, estado, capturado_en)
      values (o.fecha, o.sitio_id, o.magnitud_id, o.valor, o.origen, o.estado,
              '2026-09-30T15:55:00');
go
