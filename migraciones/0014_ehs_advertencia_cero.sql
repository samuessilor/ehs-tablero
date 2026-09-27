/* =====================================================================
   Migracion 0014 — un cero tecleado por error tambien es "lo improbable"
   ---------------------------------------------------------------------
   Encontrado en la auditoria de codigo del 27-sep-2026 (revision adversarial
   de la parte de ingesta, pedida por Samuel).

   ehs.sp_capturar_lote (migracion 0007) avisa cuando un valor queda por
   debajo del minimo historico de su magnitud, PERO excluia el cero de ese
   aviso con una condicion "v.valor_num > 0" — la idea original era no avisar
   de un cero legitimo en accidentes_dafw/horas_temp (0 accidentes es lo
   normal, no un error de tecleo). El problema: accidentes_dafw y horas_temp
   tienen valor_min = 0.0 en la semilla de ref.dim_magnitud (migracion 0008),
   asi que la comparacion "valor_num < valor_min" (0 < 0.0) ya era falsa para
   ellas SIN necesitar el ">0" — el negativo ya se rechaza aparte, mas arriba
   en el mismo procedimiento. La condicion nunca protegia el caso para el que
   se escribio.

   Su UNICO efecto real era silenciar el aviso justo donde si importa: un
   cero tecleado por error en agua_m3, energia_kwh, unidades_buenas u
   horas_fijos (las cuatro magnitudes con valor_min > 0) se capturaba sin
   ninguna advertencia — exactamente el defecto que R.5.3.6 ("una celda vacia
   no es un cero") existe para evitar, solo que aqui el cero si estaba
   tecleado, no vacio, asi que esa regla no lo atrapaba.

   No se toca 0007_ehs_ingesta.sql: una migracion ya aplicada no se edita
   (mismo criterio que uso la migracion 0009 con el trigger de historia).
   Esta migracion vuelve a crear el procedimiento completo, identico al de
   0007, con esa unica condicion corregida.
   ===================================================================== */

set nocount on;
go

if object_id('ehs.sp_capturar_lote') is not null
    drop procedure ehs.sp_capturar_lote;
go

create procedure ehs.sp_capturar_lote
    @lote                ehs.lote_lectura readonly,
    @capturado_por       varchar(60),
    @origen              varchar(120) = 'formulario de captura EHS',
    @confirmar_atipicos  bit = 0,
    @carga_id            bigint = null output
as
begin
    set nocount on;
    set xact_abort on;

    if @capturado_por is null or ltrim(rtrim(@capturado_por)) = ''
    begin
        raiserror('Falta @capturado_por. La bitacora tiene que decir quien capturo (R.5.3.4).', 16, 1);
        return;
    end;

    insert ops.carga_log (proceso, inicio, ejecutado_por)
    values ('captura manual', sysdatetime(), @capturado_por);
    set @carga_id = scope_identity();

    begin try
        begin transaction;

        declare @tipado table (
            fecha_texto    varchar(40),
            sitio_texto    varchar(60),
            magnitud_texto varchar(60),
            valor_texto    varchar(60),
            fecha          date,
            sitio_id       varchar(20),
            magnitud_id    varchar(40),
            valor          decimal(18,4),
            motivo         varchar(200),
            advertencia    varchar(200)
        );

        insert @tipado
        select l.fecha_texto, l.sitio_texto, l.magnitud_texto, l.valor_texto,
               f.valor_fecha, s.sitio_id, m.magnitud_id, v.valor_num,
               /* motivo: lo imposible. No entra nunca. */
               case
                 when l.valor_texto is null or ltrim(rtrim(l.valor_texto)) = ''
                      then 'Celda vacia. Una celda vacia no es un cero (R.5.3.6): no se captura.'
                 when f.valor_fecha is null
                      then 'La fecha no es una fecha valida: ' + isnull(l.fecha_texto, '(nula)')
                 when day(f.valor_fecha) <> 1
                      then 'La lectura mensual se ancla al dia 1 del mes.'
                 when not exists (select 1 from ref.dim_fecha d where d.fecha = f.valor_fecha)
                      then 'El mes no existe en ref.dim_fecha: ' + convert(varchar(10), f.valor_fecha)
                 when s.sitio_id is null
                      then 'Sitio desconocido: ' + isnull(l.sitio_texto, '(nulo)')
                 when m.magnitud_id is null
                      then 'Magnitud desconocida: ' + isnull(l.magnitud_texto, '(nula)')
                 when v.valor_num is null
                      then 'El valor no es un numero: ' + isnull(l.valor_texto, '(nulo)')
                 when v.valor_num < 0
                      then 'Valor negativo. Ninguna de las nueve magnitudes puede serlo.'
                 else null
               end,
               /* advertencia: lo improbable. Entra solo si quien captura lo sostiene.
                  Migracion 0014: se quita "and v.valor_num > 0" de la rama de abajo -
                  ver el encabezado de este archivo. */
               case
                 when v.valor_num is null then null
                 when m.valor_max is not null and v.valor_num > m.valor_max
                      then 'Supera el maximo historico de ' + m.magnitud_id + ' con holgura ('
                           + cast(cast(m.valor_max as decimal(18,1)) as varchar(40))
                           + '). Confirma que es correcto.'
                 when m.valor_min is not null and v.valor_num < m.valor_min
                      then 'Queda por debajo del minimo historico de ' + m.magnitud_id + ' ('
                           + cast(cast(m.valor_min as decimal(18,1)) as varchar(40))
                           + '). Confirma que es correcto.'
                 else null
               end
        from @lote l
        cross apply (select try_convert(date, l.fecha_texto) as valor_fecha) f
        cross apply (select try_convert(decimal(18,4), l.valor_texto) as valor_num) v
        left join ref.dim_sitio    s on s.sitio_id    = l.sitio_texto and s.activo = 1
        left join ref.dim_magnitud m on m.magnitud_id = l.magnitud_texto;

        insert ops.lectura_rechazada
            (carga_id, fecha_texto, sitio_texto, magnitud_texto, valor_texto,
             fila_cruda, motivo, origen)
        select @carga_id, t.fecha_texto, t.sitio_texto, t.magnitud_texto, t.valor_texto,
               concat('{"fecha":"', isnull(t.fecha_texto, ''),
                      '","sitio":"', isnull(t.sitio_texto, ''),
                      '","magnitud":"', isnull(t.magnitud_texto, ''),
                      '","valor":"', isnull(t.valor_texto, ''), '"}'),
               t.motivo, @origen
        from @tipado t
        where t.motivo is not null;

        declare @rechazos int = @@rowcount;

        merge ehs.hecho_lectura_mensual with (holdlock) as d
        using (select fecha, sitio_id, magnitud_id, valor,
                      case when advertencia is null then @origen
                           else @origen + ' [atipico confirmado]' end as origen_fila
                 from @tipado
                where motivo is null
                  and (advertencia is null or @confirmar_atipicos = 1)) as s
           on d.fecha = s.fecha
          and d.sitio_id = s.sitio_id
          and d.magnitud_id = s.magnitud_id
        when matched and d.valor <> s.valor then
            update set d.valor  = s.valor,
                       d.estado = 'corregido',
                       d.origen = s.origen_fila,
                       d.modificado_por = @capturado_por,
                       d.modificado_en  = sysdatetime()
        when not matched by target then
            insert (fecha, sitio_id, magnitud_id, valor, origen, estado,
                    capturado_por, capturado_en)
            values (s.fecha, s.sitio_id, s.magnitud_id, s.valor, s.origen_fila, 'capturado',
                    @capturado_por, sysdatetime());

        declare @grabadas int = @@rowcount;

        declare @pendientes int =
            (select count(*) from @tipado
              where motivo is null and advertencia is not null and @confirmar_atipicos = 0);

        update ops.carga_log
           set fin = sysdatetime(), filas = @grabadas, rechazos = @rechazos,
               resultado = 'ok',
               detalle = concat(@grabadas, ' grabadas, ', @rechazos, ' apartadas, ',
                                @pendientes, ' esperando confirmacion')
         where carga_id = @carga_id;

        commit transaction;

        select @carga_id as carga_id, @grabadas as grabadas,
               @rechazos as rechazos, @pendientes as pendientes;

        select t.sitio_texto as sitio, t.magnitud_texto as magnitud,
               t.valor_texto as valor, t.motivo
          from @tipado t
         where t.motivo is not null;

        select t.sitio_texto as sitio, t.magnitud_texto as magnitud,
               t.valor_texto as valor, t.advertencia
          from @tipado t
         where t.motivo is null and t.advertencia is not null;
    end try
    begin catch
        if @@trancount > 0 rollback transaction;
        update ops.carga_log
           set fin = sysdatetime(), resultado = 'error',
               detalle = left(error_message(), 400)
         where carga_id = @carga_id;
        throw;
    end catch;
end;
go

print 'Migracion 0014: sp_capturar_lote ya avisa un cero por debajo del minimo historico.';
go
