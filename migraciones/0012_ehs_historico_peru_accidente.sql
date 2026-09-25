/* ===========================================================================
   Migracion 0012 — historico 2023-2025, Peru 2026, correccion del accidente
   y meta 2026 de Colombia

   GENERADO por analisis/generar_historico_peru.py desde los Excel ya
   validados en la sesion (ver ehs/entrega-reunion/CLAUDE.md si se regenera).
   No editar a mano.

   Opcional, igual que 0008: el ejecutor de migraciones la deja fuera de la
   corrida por defecto y solo la aplica con --con-datos-semilla, porque es
   dato propio de este sitio (Servioptica), no esquema generico. Requiere que
   0011 ya haya corrido (Peru operativo, 'colombia_peru' real, 'nacional' con
   fila propia en ref.dim_sitio) y que 0008 ya haya cargado el 2026 de
   Celta/Estrella/Agencias (el accidente de mayo que aqui se corrige vino de
   ahi).

   Que trae:
   1. Historico 2023-2025 de Celta/Estrella/Agencias: agua, energia, un total
      de residuos (esos anios no traen el desglose peligroso/aprovechable/
      ordinario, solo el total — de ahi la magnitud residuo_total_kg que
      agrego la 0011) y unidades buenas. 432 lecturas (3 sitios x 3 anios x
      12 meses x 4 magnitudes).
   2. Peru (TOPSA) 2026, enero a julio: mismas 4 magnitudes, 28 lecturas.
      Accidentes y horas-hombre de Peru siguen sin llegar (el manager lo dijo
      en la reunion) — no se inventan, sencillamente no hay fila.
   3. La correccion del accidente: AT 2026 (la hoja del Excel vigente) dice
      mayo. El manager de la implementacion confirmo por escrito y en la
      reunion del 24-sep-2026 que el accidente real fue en julio, y que no
      hay ningun otro en el ano — se corrige con ehs.sp_corregir_lectura
      (migracion 0009), no con un UPDATE silencioso, para que quede en
      ehs.v_correcciones como cualquier otra correccion.
   4. La meta 2026 de Colombia (Celta+Estrella+Agencias, sin Peru): el libro
      de Excel sigue en 7,5 / 1,5 / 126 (KPIs 2026!F14:H14). El manager dio
      una cifra distinta en la reunion — 5,18 / 1,27 / 134,9 — que no esta en
      ningun Excel de los que Samuel envio. Se carga igual, confirmada por
      Samuel, con su fuente marcada como lo que es: una confirmacion verbal,
      no una celda de Excel. La meta anterior se deja cargada mas no vigente
      — mismo patron que ehs.meta ya usa para no perder de vista que se
      estaba usando antes.
   5. La trayectoria historica de Colombia (ehs.scorecard_anual, sitio
      'nacional'): 2023/2024/2025 sin meta (el libro nunca publico una meta
      propia para este agregado esos anios — no se inventa), con el cierre
      real de cada ano; 2026 con la meta nueva confirmada arriba.
   =========================================================================== */

set nocount on;
begin transaction;

/* ------------------------------------------------- historico + Peru, hechos */
merge ehs.hecho_lectura_mensual as d
using (values
    ('2023-01-01', 'celta', 'agua_m3', 727.21, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'celta', 'energia_kwh', 123400.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'celta', 'residuo_total_kg', 17600.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'celta', 'unidades_buenas', 81568.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'celta', 'agua_m3', 561.81, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'celta', 'energia_kwh', 168551.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'celta', 'residuo_total_kg', 13240.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'celta', 'unidades_buenas', 83539.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'celta', 'agua_m3', 541.43, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'celta', 'energia_kwh', 170500.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'celta', 'residuo_total_kg', 14210.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'celta', 'unidades_buenas', 85142.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'celta', 'agua_m3', 474.09, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'celta', 'energia_kwh', 176560.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'celta', 'residuo_total_kg', 13040.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'celta', 'unidades_buenas', 72380.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'celta', 'agua_m3', 651.99, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'celta', 'energia_kwh', 172740.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'celta', 'residuo_total_kg', 14990.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'celta', 'unidades_buenas', 81860.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'celta', 'agua_m3', 600.75, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'celta', 'energia_kwh', 199580.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'celta', 'residuo_total_kg', 12720.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'celta', 'unidades_buenas', 78178.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'celta', 'agua_m3', 665.04, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'celta', 'energia_kwh', 222980.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'celta', 'residuo_total_kg', 17910.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'celta', 'unidades_buenas', 94370.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'celta', 'agua_m3', 726.39, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'celta', 'energia_kwh', 176330.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'celta', 'residuo_total_kg', 13350.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'celta', 'unidades_buenas', 90908.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'celta', 'agua_m3', 503.24, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'celta', 'energia_kwh', 173616.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'celta', 'residuo_total_kg', 18550.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'celta', 'unidades_buenas', 77608.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'celta', 'agua_m3', 498.5, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'celta', 'energia_kwh', 157149.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'celta', 'residuo_total_kg', 16133.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'celta', 'unidades_buenas', 83983.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'celta', 'agua_m3', 520.05, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'celta', 'energia_kwh', 172650.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'celta', 'residuo_total_kg', 18200.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'celta', 'unidades_buenas', 92111.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'celta', 'agua_m3', 410.12, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'celta', 'energia_kwh', 158650.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'celta', 'residuo_total_kg', 17080.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'celta', 'unidades_buenas', 92262.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'estrella', 'agua_m3', 420.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'estrella', 'energia_kwh', 90930.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'estrella', 'residuo_total_kg', 4540.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'estrella', 'unidades_buenas', 49691.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'estrella', 'agua_m3', 527.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'estrella', 'energia_kwh', 95301.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'estrella', 'residuo_total_kg', 4180.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'estrella', 'unidades_buenas', 53252.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'estrella', 'agua_m3', 460.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'estrella', 'energia_kwh', 92060.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'estrella', 'residuo_total_kg', 4370.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'estrella', 'unidades_buenas', 49092.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'estrella', 'agua_m3', 367.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'estrella', 'energia_kwh', 67444.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'estrella', 'residuo_total_kg', 4000.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'estrella', 'unidades_buenas', 43330.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'estrella', 'agua_m3', 421.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'estrella', 'energia_kwh', 80857.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'estrella', 'residuo_total_kg', 3900.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'estrella', 'unidades_buenas', 48252.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'estrella', 'agua_m3', 405.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'estrella', 'energia_kwh', 93609.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'estrella', 'residuo_total_kg', 3830.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'estrella', 'unidades_buenas', 50044.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'estrella', 'agua_m3', 773.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'estrella', 'energia_kwh', 110473.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'estrella', 'residuo_total_kg', 5050.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'estrella', 'unidades_buenas', 54537.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'estrella', 'agua_m3', 710.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'estrella', 'energia_kwh', 95688.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'estrella', 'residuo_total_kg', 6530.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'estrella', 'unidades_buenas', 52654.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'estrella', 'agua_m3', 706.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'estrella', 'energia_kwh', 97702.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'estrella', 'residuo_total_kg', 3740.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'estrella', 'unidades_buenas', 52212.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'estrella', 'agua_m3', 649.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'estrella', 'energia_kwh', 80951.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'estrella', 'residuo_total_kg', 3880.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'estrella', 'unidades_buenas', 52142.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'estrella', 'agua_m3', 547.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'estrella', 'energia_kwh', 88546.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'estrella', 'residuo_total_kg', 4150.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'estrella', 'unidades_buenas', 51798.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'estrella', 'agua_m3', 675.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'estrella', 'energia_kwh', 89465.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'estrella', 'residuo_total_kg', 5530.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'estrella', 'unidades_buenas', 56623.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'agencias', 'agua_m3', 279.11, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'agencias', 'energia_kwh', 45420.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'agencias', 'residuo_total_kg', 1900.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-01-01', 'agencias', 'unidades_buenas', 72323.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'agencias', 'agua_m3', 281.04, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'agencias', 'energia_kwh', 44420.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'agencias', 'residuo_total_kg', 2360.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-02-01', 'agencias', 'unidades_buenas', 71755.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'agencias', 'agua_m3', 266.04, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'agencias', 'energia_kwh', 45927.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'agencias', 'residuo_total_kg', 2490.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-03-01', 'agencias', 'unidades_buenas', 76133.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'agencias', 'agua_m3', 270.68, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'agencias', 'energia_kwh', 45510.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'agencias', 'residuo_total_kg', 2090.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-04-01', 'agencias', 'unidades_buenas', 60000.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'agencias', 'agua_m3', 285.39, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'agencias', 'energia_kwh', 45421.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'agencias', 'residuo_total_kg', 2020.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-05-01', 'agencias', 'unidades_buenas', 71289.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'agencias', 'agua_m3', 426.73, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'agencias', 'energia_kwh', 44508.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'agencias', 'residuo_total_kg', 2130.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-06-01', 'agencias', 'unidades_buenas', 69352.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'agencias', 'agua_m3', 398.74, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'agencias', 'energia_kwh', 46039.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'agencias', 'residuo_total_kg', 2150.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-07-01', 'agencias', 'unidades_buenas', 67816.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'agencias', 'agua_m3', 280.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'agencias', 'energia_kwh', 44508.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'agencias', 'residuo_total_kg', 1770.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-08-01', 'agencias', 'unidades_buenas', 68099.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'agencias', 'agua_m3', 278.66, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'agencias', 'energia_kwh', 52335.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'agencias', 'residuo_total_kg', 2230.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-09-01', 'agencias', 'unidades_buenas', 60133.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'agencias', 'agua_m3', 273.6, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'agencias', 'energia_kwh', 46040.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'agencias', 'residuo_total_kg', 2400.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-10-01', 'agencias', 'unidades_buenas', 64531.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'agencias', 'agua_m3', 275.57, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'agencias', 'energia_kwh', 46164.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'agencias', 'residuo_total_kg', 2150.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-11-01', 'agencias', 'unidades_buenas', 65722.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'agencias', 'agua_m3', 267.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'agencias', 'energia_kwh', 44418.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'agencias', 'residuo_total_kg', 2410.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2023-12-01', 'agencias', 'unidades_buenas', 59073.0, 'KPI''s EHS 2024.xlsx / KPI''s 2023', 'validado'),
    ('2024-01-01', 'celta', 'agua_m3', 569.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'celta', 'energia_kwh', 162896.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'celta', 'residuo_total_kg', 17300.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'celta', 'unidades_buenas', 103240.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'celta', 'agua_m3', 572.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'celta', 'energia_kwh', 185524.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'celta', 'residuo_total_kg', 16430.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'celta', 'unidades_buenas', 109554.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'celta', 'agua_m3', 501.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'celta', 'energia_kwh', 179474.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'celta', 'residuo_total_kg', 16780.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'celta', 'unidades_buenas', 86752.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'celta', 'agua_m3', 436.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'celta', 'energia_kwh', 198508.8, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'celta', 'residuo_total_kg', 16300.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'celta', 'unidades_buenas', 101017.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'celta', 'agua_m3', 445.5, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'celta', 'energia_kwh', 179681.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'celta', 'residuo_total_kg', 16940.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'celta', 'unidades_buenas', 99342.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'celta', 'agua_m3', 483.63, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'celta', 'energia_kwh', 179331.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'celta', 'residuo_total_kg', 17810.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'celta', 'unidades_buenas', 88361.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'celta', 'agua_m3', 460.51, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'celta', 'energia_kwh', 176653.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'celta', 'residuo_total_kg', 16890.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'celta', 'unidades_buenas', 106873.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'celta', 'agua_m3', 475.2, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'celta', 'energia_kwh', 104651.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'celta', 'residuo_total_kg', 16710.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'celta', 'unidades_buenas', 104651.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'celta', 'agua_m3', 573.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'celta', 'energia_kwh', 163626.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'celta', 'residuo_total_kg', 16790.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'celta', 'unidades_buenas', 92982.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'celta', 'agua_m3', 595.53, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'celta', 'energia_kwh', 172942.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'celta', 'residuo_total_kg', 16810.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'celta', 'unidades_buenas', 99414.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'celta', 'agua_m3', 558.52, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'celta', 'energia_kwh', 162963.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'celta', 'residuo_total_kg', 20030.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'celta', 'unidades_buenas', 90537.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'celta', 'agua_m3', 554.89, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'celta', 'energia_kwh', 175639.6, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'celta', 'residuo_total_kg', 27840.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'celta', 'unidades_buenas', 101053.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'estrella', 'agua_m3', 728.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'estrella', 'energia_kwh', 96318.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'estrella', 'residuo_total_kg', 4980.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'estrella', 'unidades_buenas', 63070.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'estrella', 'agua_m3', 716.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'estrella', 'energia_kwh', 101447.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'estrella', 'residuo_total_kg', 3130.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'estrella', 'unidades_buenas', 60239.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'estrella', 'agua_m3', 538.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'estrella', 'energia_kwh', 102936.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'estrella', 'residuo_total_kg', 3890.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'estrella', 'unidades_buenas', 48387.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'estrella', 'agua_m3', 636.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'estrella', 'energia_kwh', 97505.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'estrella', 'residuo_total_kg', 3910.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'estrella', 'unidades_buenas', 45863.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'estrella', 'agua_m3', 417.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'estrella', 'energia_kwh', 97505.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'estrella', 'residuo_total_kg', 2784.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'estrella', 'unidades_buenas', 54429.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'estrella', 'agua_m3', 375.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'estrella', 'energia_kwh', 90604.56, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'estrella', 'residuo_total_kg', 2820.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'estrella', 'unidades_buenas', 51088.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'estrella', 'agua_m3', 492.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'estrella', 'energia_kwh', 90604.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'estrella', 'residuo_total_kg', 2940.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'estrella', 'unidades_buenas', 62334.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'estrella', 'agua_m3', 493.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'estrella', 'energia_kwh', 102428.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'estrella', 'residuo_total_kg', 3080.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'estrella', 'unidades_buenas', 55482.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'estrella', 'agua_m3', 544.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'estrella', 'energia_kwh', 97367.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'estrella', 'residuo_total_kg', 2710.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'estrella', 'unidades_buenas', 54632.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'estrella', 'agua_m3', 514.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'estrella', 'energia_kwh', 93616.76, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'estrella', 'residuo_total_kg', 3630.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'estrella', 'unidades_buenas', 57692.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'estrella', 'agua_m3', 514.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'estrella', 'energia_kwh', 81865.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'estrella', 'residuo_total_kg', 3520.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'estrella', 'unidades_buenas', 48952.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'estrella', 'agua_m3', 511.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'estrella', 'energia_kwh', 98069.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'estrella', 'residuo_total_kg', 6380.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'estrella', 'unidades_buenas', 62119.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'agencias', 'agua_m3', 274.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'agencias', 'energia_kwh', 45420.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'agencias', 'residuo_total_kg', 1000.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-01-01', 'agencias', 'unidades_buenas', 129865.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'agencias', 'agua_m3', 267.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'agencias', 'energia_kwh', 44420.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'agencias', 'residuo_total_kg', 2410.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-02-01', 'agencias', 'unidades_buenas', 123958.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'agencias', 'agua_m3', 274.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'agencias', 'energia_kwh', 45927.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'agencias', 'residuo_total_kg', 2080.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-03-01', 'agencias', 'unidades_buenas', 62520.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'agencias', 'agua_m3', 267.54, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'agencias', 'energia_kwh', 45510.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'agencias', 'residuo_total_kg', 2540.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-04-01', 'agencias', 'unidades_buenas', 123934.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'agencias', 'agua_m3', 275.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'agencias', 'energia_kwh', 45421.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'agencias', 'residuo_total_kg', 2050.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-05-01', 'agencias', 'unidades_buenas', 67658.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'agencias', 'agua_m3', 267.54, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'agencias', 'energia_kwh', 44508.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'agencias', 'residuo_total_kg', 2710.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-06-01', 'agencias', 'unidades_buenas', 86372.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'agencias', 'agua_m3', 280.87, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'agencias', 'energia_kwh', 46039.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'agencias', 'residuo_total_kg', 2310.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-07-01', 'agencias', 'unidades_buenas', 82973.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'agencias', 'agua_m3', 237.54, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'agencias', 'energia_kwh', 44508.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'agencias', 'residuo_total_kg', 1850.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-08-01', 'agencias', 'unidades_buenas', 76105.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'agencias', 'agua_m3', 268.86, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'agencias', 'energia_kwh', 52335.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'agencias', 'residuo_total_kg', 2170.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-09-01', 'agencias', 'unidades_buenas', 80087.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'agencias', 'agua_m3', 273.6, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'agencias', 'energia_kwh', 46040.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'agencias', 'residuo_total_kg', 2160.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-10-01', 'agencias', 'unidades_buenas', 76656.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'agencias', 'agua_m3', 274.49, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'agencias', 'energia_kwh', 46164.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'agencias', 'residuo_total_kg', 2280.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-11-01', 'agencias', 'unidades_buenas', 60978.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'agencias', 'agua_m3', 267.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'agencias', 'energia_kwh', 44418.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'agencias', 'residuo_total_kg', 2410.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2024-12-01', 'agencias', 'unidades_buenas', 60765.0, 'KPI''s EHS 2024.xlsx / KPI''s 2024', 'validado'),
    ('2025-01-01', 'celta', 'agua_m3', 571.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'celta', 'energia_kwh', 175882.25, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'celta', 'residuo_total_kg', 21510.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'celta', 'unidades_buenas', 103556.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'celta', 'agua_m3', 502.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'celta', 'energia_kwh', 171885.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'celta', 'residuo_total_kg', 20230.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'celta', 'unidades_buenas', 103092.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'celta', 'agua_m3', 501.97, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'celta', 'energia_kwh', 185621.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'celta', 'residuo_total_kg', 19240.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'celta', 'unidades_buenas', 100404.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'celta', 'agua_m3', 534.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'celta', 'energia_kwh', 174531.8, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'celta', 'residuo_total_kg', 21840.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'celta', 'unidades_buenas', 89219.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'celta', 'agua_m3', 465.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'celta', 'energia_kwh', 179642.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'celta', 'residuo_total_kg', 21040.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'celta', 'unidades_buenas', 105779.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'celta', 'agua_m3', 484.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'celta', 'energia_kwh', 157492.31, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'celta', 'residuo_total_kg', 18290.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'celta', 'unidades_buenas', 88875.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'celta', 'agua_m3', 550.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'celta', 'energia_kwh', 181582.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'celta', 'residuo_total_kg', 24900.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'celta', 'unidades_buenas', 122640.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'celta', 'agua_m3', 477.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'celta', 'energia_kwh', 158504.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'celta', 'residuo_total_kg', 18820.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'celta', 'unidades_buenas', 106791.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'celta', 'agua_m3', 495.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'celta', 'energia_kwh', 163915.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'celta', 'residuo_total_kg', 23010.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'celta', 'unidades_buenas', 99150.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'celta', 'agua_m3', 485.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'celta', 'energia_kwh', 170718.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'celta', 'residuo_total_kg', 23680.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'celta', 'unidades_buenas', 97961.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'celta', 'agua_m3', 448.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'celta', 'energia_kwh', 166520.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'celta', 'residuo_total_kg', 21320.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'celta', 'unidades_buenas', 86599.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'celta', 'agua_m3', 559.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'celta', 'energia_kwh', 185143.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'celta', 'residuo_total_kg', 21991.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'celta', 'unidades_buenas', 103254.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'estrella', 'agua_m3', 506.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'estrella', 'energia_kwh', 96743.23, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'estrella', 'residuo_total_kg', 3400.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'estrella', 'unidades_buenas', 60547.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'estrella', 'agua_m3', 434.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'estrella', 'energia_kwh', 93043.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'estrella', 'residuo_total_kg', 4680.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'estrella', 'unidades_buenas', 61871.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'estrella', 'agua_m3', 480.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'estrella', 'energia_kwh', 99526.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'estrella', 'residuo_total_kg', 4280.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'estrella', 'unidades_buenas', 62378.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'estrella', 'agua_m3', 501.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'estrella', 'energia_kwh', 89840.49, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'estrella', 'residuo_total_kg', 4290.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'estrella', 'unidades_buenas', 58394.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'estrella', 'agua_m3', 606.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'estrella', 'energia_kwh', 94501.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'estrella', 'residuo_total_kg', 4260.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'estrella', 'unidades_buenas', 62161.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'estrella', 'agua_m3', 445.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'estrella', 'energia_kwh', 84084.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'estrella', 'residuo_total_kg', 4500.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'estrella', 'unidades_buenas', 51664.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'estrella', 'agua_m3', 691.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'estrella', 'energia_kwh', 106253.68, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'estrella', 'residuo_total_kg', 5630.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'estrella', 'unidades_buenas', 71966.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'estrella', 'agua_m3', 593.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'estrella', 'energia_kwh', 92968.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'estrella', 'residuo_total_kg', 5920.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'estrella', 'unidades_buenas', 59283.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'estrella', 'agua_m3', 594.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'estrella', 'energia_kwh', 96341.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'estrella', 'residuo_total_kg', 5310.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'estrella', 'unidades_buenas', 59636.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'estrella', 'agua_m3', 581.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'estrella', 'energia_kwh', 92469.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'estrella', 'residuo_total_kg', 5620.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'estrella', 'unidades_buenas', 59592.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'estrella', 'agua_m3', 486.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'estrella', 'energia_kwh', 86359.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'estrella', 'residuo_total_kg', 6880.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'estrella', 'unidades_buenas', 51492.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'estrella', 'agua_m3', 501.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'estrella', 'energia_kwh', 93573.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'estrella', 'residuo_total_kg', 7261.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'estrella', 'unidades_buenas', 62930.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'agencias', 'agua_m3', 268.8, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'agencias', 'energia_kwh', 45519.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'agencias', 'residuo_total_kg', 2000.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-01-01', 'agencias', 'unidades_buenas', 85084.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'agencias', 'agua_m3', 268.86, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'agencias', 'energia_kwh', 46050.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'agencias', 'residuo_total_kg', 2230.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-02-01', 'agencias', 'unidades_buenas', 84779.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'agencias', 'agua_m3', 260.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'agencias', 'energia_kwh', 50335.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'agencias', 'residuo_total_kg', 2050.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-03-01', 'agencias', 'unidades_buenas', 80458.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'agencias', 'agua_m3', 272.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'agencias', 'energia_kwh', 53853.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'agencias', 'residuo_total_kg', 1950.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-04-01', 'agencias', 'unidades_buenas', 74298.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'agencias', 'agua_m3', 267.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'agencias', 'energia_kwh', 48939.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'agencias', 'residuo_total_kg', 1940.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-05-01', 'agencias', 'unidades_buenas', 75873.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'agencias', 'agua_m3', 274.49, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'agencias', 'energia_kwh', 45440.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'agencias', 'residuo_total_kg', 1760.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-06-01', 'agencias', 'unidades_buenas', 64529.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'agencias', 'agua_m3', 270.5, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'agencias', 'energia_kwh', 47939.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'agencias', 'residuo_total_kg', 2040.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-07-01', 'agencias', 'unidades_buenas', 93783.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'agencias', 'agua_m3', 269.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'agencias', 'energia_kwh', 48726.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'agencias', 'residuo_total_kg', 2060.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-08-01', 'agencias', 'unidades_buenas', 75876.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'agencias', 'agua_m3', 279.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'agencias', 'energia_kwh', 45853.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'agencias', 'residuo_total_kg', 2220.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-09-01', 'agencias', 'unidades_buenas', 82312.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'agencias', 'agua_m3', 272.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'agencias', 'energia_kwh', 47506.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'agencias', 'residuo_total_kg', 2090.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-10-01', 'agencias', 'unidades_buenas', 83990.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'agencias', 'agua_m3', 275.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'agencias', 'energia_kwh', 46852.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'agencias', 'residuo_total_kg', 2080.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-11-01', 'agencias', 'unidades_buenas', 62263.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'agencias', 'agua_m3', 269.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'agencias', 'energia_kwh', 47853.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'agencias', 'residuo_total_kg', 2230.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2025-12-01', 'agencias', 'unidades_buenas', 73597.0, 'KPI''s EHS 2025.xlsx / KPI''s 2025', 'validado'),
    ('2026-01-01', 'peru', 'agua_m3', 1900.8, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-01-01', 'peru', 'energia_kwh', 231607.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-01-01', 'peru', 'residuo_total_kg', 12260.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-01-01', 'peru', 'unidades_buenas', 97708.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-02-01', 'peru', 'agua_m3', 1330.6, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-02-01', 'peru', 'energia_kwh', 242071.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-02-01', 'peru', 'residuo_total_kg', 8830.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-02-01', 'peru', 'unidades_buenas', 95366.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-03-01', 'peru', 'agua_m3', 1510.5, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-03-01', 'peru', 'energia_kwh', 213845.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-03-01', 'peru', 'residuo_total_kg', 8820.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-03-01', 'peru', 'unidades_buenas', 106146.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-04-01', 'peru', 'agua_m3', 1194.8, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-04-01', 'peru', 'energia_kwh', 243395.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-04-01', 'peru', 'residuo_total_kg', 9980.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-04-01', 'peru', 'unidades_buenas', 96608.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-05-01', 'peru', 'agua_m3', 1394.1, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-05-01', 'peru', 'energia_kwh', 226670.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-05-01', 'peru', 'residuo_total_kg', 8640.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-05-01', 'peru', 'unidades_buenas', 94834.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-06-01', 'peru', 'agua_m3', 1807.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-06-01', 'peru', 'energia_kwh', 230945.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-06-01', 'peru', 'residuo_total_kg', 8940.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-06-01', 'peru', 'unidades_buenas', 91358.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-07-01', 'peru', 'agua_m3', 1465.5, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-07-01', 'peru', 'energia_kwh', 233670.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-07-01', 'peru', 'residuo_total_kg', 9000.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado'),
    ('2026-07-01', 'peru', 'unidades_buenas', 86328.0, 'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)', 'validado')) as o (fecha, sitio_id, magnitud_id, valor, origen, estado)
   on d.fecha = o.fecha and d.sitio_id = o.sitio_id and d.magnitud_id = o.magnitud_id
 when matched then update set
      d.valor = o.valor, d.origen = o.origen, d.estado = o.estado
 when not matched then insert
      (fecha, sitio_id, magnitud_id, valor, origen, estado)
      values (o.fecha, o.sitio_id, o.magnitud_id, o.valor, o.origen, o.estado);
go

/* --------------------------------------------------- correccion del accidente
   Ver el punto 3 del encabezado. Se corrige con el mismo procedimiento que
   usaria cualquier persona desde "Consultar y corregir": queda en
   ehs.v_correcciones con motivo, quien y cuando, igual que cualquier otra
   correccion — nunca un UPDATE silencioso sobre un dato que se reporta a
   corporativo. */
exec ehs.sp_corregir_lectura
    @fecha = '2026-05-01',
    @sitio_id = 'celta',
    @magnitud_id = 'accidentes_dafw',
    @valor_nuevo = 0,
    @motivo = 'Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta no fue en mayo, fue en julio, y es el unico del ano.',
    @corregido_por = 'migracion 0012 (confirmado en reunion 24-sep-2026)';
go

/* Julio ya tiene una fila en 0 (parte de la carga inicial 2026, migracion
   0008: la hoja AT 2026 de donde salio tambien decia cero) — no se inserta,
   se corrige, con el mismo procedimiento de arriba. */
exec ehs.sp_corregir_lectura
    @fecha = '2026-07-01',
    @sitio_id = 'celta',
    @magnitud_id = 'accidentes_dafw',
    @valor_nuevo = 1,
    @motivo = 'Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta fue en julio, no en mayo.',
    @corregido_por = 'migracion 0012 (confirmado en reunion 24-sep-2026)';
go

/* -------------------------------------------------------- meta 2026 Colombia
   Ver el punto 4 del encabezado. */
merge ehs.meta as d
using (values
    (2026, 'nacional', 'agua_por_lente', 5.18, 'confirmado verbalmente por el manager, reunion 24-sep-2026'),
    (2026, 'nacional', 'energia_por_lente', 1.27, 'confirmado verbalmente por el manager, reunion 24-sep-2026'),
    (2026, 'nacional', 'residuos_por_lente', 134.9, 'confirmado verbalmente por el manager, reunion 24-sep-2026')
) as o (anio, ambito_id, kpi_id, valor, fuente)
   on d.anio = o.anio and d.ambito_id = o.ambito_id
  and d.kpi_id = o.kpi_id and d.fuente = o.fuente
 when matched then update set d.valor = o.valor
 when not matched then insert (anio, ambito_id, kpi_id, valor, fuente, vigente)
      values (o.anio, o.ambito_id, o.kpi_id, o.valor, o.fuente, 0);
go

/* La meta anterior (Excel KPIs 2026!F14:H14) se deja cargada, pero deja de
   ser la vigente: la reemplaza la confirmada en la reunion. */
update ehs.meta set vigente = 0
 where ambito_id = 'nacional' and fuente = 'Excel KPIs 2026!F14:H14'
   and kpi_id in ('agua_por_lente', 'energia_por_lente', 'residuos_por_lente');

update ehs.meta set vigente = 1
 where ambito_id = 'nacional' and fuente = 'confirmado verbalmente por el manager, reunion 24-sep-2026';
go

/* ---------------------------------------------- trayectoria de Colombia ---
   Ver el punto 5 del encabezado. Cierres reales 2023-2025 calculados del
   propio Excel (fila YTD de diciembre, columnas Ratio Agua/energia/
   Residuos del bloque "Nacional Labs + Agencias"); sin meta esos anios
   porque el libro nunca publico una propia para este agregado. */
merge ehs.scorecard_anual as d
using (values
    (2023, 'nacional', 'agua_por_lente', null, 7.04, -0.02, 'KPI''s EHS 2024.xlsx / KPI''s 2023'),
    (2024, 'nacional', 'agua_por_lente', null, 5.53, -0.02, 'KPI''s EHS 2024.xlsx / KPI''s 2024'),
    (2025, 'nacional', 'agua_por_lente', null, 5.49, -0.02, 'KPI''s EHS 2025.xlsx / KPI''s 2025'),
    (2026, 'nacional', 'agua_por_lente', 5.18, null, -0.02, 'confirmado verbalmente por el manager, reunion 24-sep-2026'),
    (2023, 'nacional', 'energia_por_lente', null, 1.52, -0.02, 'KPI''s EHS 2024.xlsx / KPI''s 2023'),
    (2024, 'nacional', 'energia_por_lente', null, 1.30, -0.02, 'KPI''s EHS 2024.xlsx / KPI''s 2024'),
    (2025, 'nacional', 'energia_por_lente', null, 1.32, -0.02, 'KPI''s EHS 2025.xlsx / KPI''s 2025'),
    (2026, 'nacional', 'energia_por_lente', 1.27, null, -0.02, 'confirmado verbalmente por el manager, reunion 24-sep-2026'),
    (2023, 'nacional', 'residuos_por_lente', null, 109.63, -0.02, 'KPI''s EHS 2024.xlsx / KPI''s 2023'),
    (2024, 'nacional', 'residuos_por_lente', null, 99.44, -0.02, 'KPI''s EHS 2024.xlsx / KPI''s 2024'),
    (2025, 'nacional', 'residuos_por_lente', null, 119.52, -0.02, 'KPI''s EHS 2025.xlsx / KPI''s 2025'),
    (2026, 'nacional', 'residuos_por_lente', 134.9, null, -0.02, 'confirmado verbalmente por el manager, reunion 24-sep-2026')
) as o (anio, sitio_id, kpi_id, meta, real_ytd, premisa_anual, fuente)
   on d.anio = o.anio and d.sitio_id = o.sitio_id and d.kpi_id = o.kpi_id
 when matched then update set
      d.meta = o.meta, d.real_ytd = o.real_ytd, d.premisa_anual = o.premisa_anual, d.fuente = o.fuente
 when not matched then insert
      (anio, sitio_id, kpi_id, meta, real_ytd, premisa_anual, fuente)
      values (o.anio, o.sitio_id, o.kpi_id, o.meta, o.real_ytd, o.premisa_anual, o.fuente);
go

commit transaction;

select 'lecturas nuevas (historico + Peru)', count(*) from ehs.hecho_lectura_mensual
 where origen like 'KPI''s EHS 202[45].xlsx%' or origen like '%Lab Topsa Peru%'
union all select 'scorecard Colombia', count(*) from ehs.scorecard_anual where sitio_id = 'nacional'
union all select 'meta Colombia 2026 vigente', count(*) from ehs.meta
 where ambito_id = 'nacional' and anio = 2026 and vigente = 1
   and kpi_id in ('agua_por_lente', 'energia_por_lente', 'residuos_por_lente');
go

print 'Migracion 0012: historico 2023-2025, Peru 2026, accidente corregido a julio, meta Colombia 2026 confirmada.';
go
