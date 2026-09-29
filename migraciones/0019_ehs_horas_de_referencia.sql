/* =====================================================================
   Migracion 0019 - horas de referencia (29-sep-2026)
   ---------------------------------------------------------------------
   Continuacion de 0018. Con 0018, una instalacion nueva ya tiene los mismos
   DATOS que la instalacion de referencia de Samuel, pero el encabezado del
   tablero ("Actualizado: ...") seguia distinto: sale de
   max(coalesce(modificado_en, capturado_en)) (adaptador_sql.js), y en una
   instalacion nueva esas horas son las de la propia instalacion, no las de
   la carga de referencia. Se midio con el diff de las 605 respuestas de la API
   y las paginas: la unica diferencia que quedaba era esa linea, "24 sep 2026
   21:52" en la instalacion de referencia contra la fecha de instalacion en la
   nueva.

   Esta migracion fija esas horas en las filas de la carga de referencia, para
   que "Actualizado" diga lo mismo en todas las instalaciones hechas con este
   paquete: la hora en que el dato de referencia se cargo o se corrigio por
   ultima vez, que es lo que ese encabezado quiere decir. Es lo mismo que
   hace restaurar un respaldo: conserva las horas originales.

   CUIDADO, y por eso cada sentencia se limita a las filas de la carga de
   referencia (por su origen o su autor, nunca por "todas las filas"): una
   instalacion que ya tenga capturas reales y reciba esta migracion con
   actualizar.ps1 no debe ver reescrita la hora de sus capturas. Las capturas
   hechas desde el tablero tienen otro origen y no se tocan.

   Idempotente: en la instalacion de referencia no cambia nada (las horas ya
   son esas). El trigger de historia se apaga solo dentro de la transaccion,
   igual que en 0018, porque estas sentencias no cambian ningun valor. */

set nocount on;
go

begin try
    begin transaction;

    disable trigger ehs.tr_lectura_mensual_hist on ehs.hecho_lectura_mensual;

    /* 1. Carga del corte 2026 de Colombia (y las dos lecturas del accidente de Celta,
          cuyo origen 0018 dejo como 'correccion manual'). */
    update ehs.hecho_lectura_mensual
       set capturado_en = '2026-09-24T12:18:53'
     where capturado_en <> '2026-09-24T12:18:53'
       and (origen = N'KPI''s EHS 2026.xlsx / indicadores mensuales LABS'
            or (sitio_id = 'celta' and magnitud_id = 'accidentes_dafw'
                and fecha in ('2026-05-01', '2026-07-01')
                and modificado_por = N'migracion 0012 (confirmado en reunion 24-sep-2026)'));

    /* 2. Historico 2024-2025 y Peru. */
    update ehs.hecho_lectura_mensual
       set capturado_en = '2026-09-24T21:52:12'
     where capturado_en <> '2026-09-24T21:52:12'
       and origen in (N'KPI''s EHS 2024.xlsx / KPI''s 2024',
                      N'KPI''s EHS 2025.xlsx / KPI''s 2025',
                      N'KPI''s EHS Colombia Y Peru.xlsx / KPIs 2026 (Lab Topsa Peru)');

    /* 3. Cuando se confirmo la correccion del accidente (reunion del 24-sep-2026). */
    update ehs.hecho_lectura_mensual
       set modificado_en = '2026-09-24T21:52:12'
     where modificado_por = N'migracion 0012 (confirmado en reunion 24-sep-2026)'
       and (modificado_en is null or modificado_en <> '2026-09-24T21:52:12');

    update ehs.hecho_lectura_mensual_hist
       set reemplazado_en = '2026-09-24T21:52:12'
     where reemplazado_por = N'migracion 0012 (confirmado en reunion 24-sep-2026)'
       and reemplazado_en <> '2026-09-24T21:52:12';

    enable trigger ehs.tr_lectura_mensual_hist on ehs.hecho_lectura_mensual;

    commit;
end try
begin catch
    if @@trancount > 0 rollback;
    throw;
end catch;
go

/* 4. Las 10 confirmaciones de avisos del 28-sep-2026 (las mismas que inserta 0018). */
update ehs.aviso_confirmado
   set confirmado_en = '2026-09-28T14:16:10'
 where codigo = 'salto_atipico'
   and confirmado_por = N'Samuel Galeano'
   and nota = N'Verificados y aprobados por Samuel Galeano en el chat del tablero (revision del corte de julio 2026, 28-sep-2026).'
   and confirmado_en <> '2026-09-28T14:16:10';
go
