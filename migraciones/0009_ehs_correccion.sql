/* ===========================================================================
   Migracion 0009 — corregir una lectura ya capturada, con motivo obligatorio

   La captura (migracion 0007) resuelve "entrar el dato del mes". Esto resuelve
   algo distinto: alguien nota DESPUES que un numero ya capturado esta mal, y
   tiene que poder arreglarlo sin volver a mandar el lote entero del mes — y sin
   que el arreglo quede silencioso. El encargo pide dos cosas para eso: razon
   escrita obligatoria, y el valor anterior archivado. La segunda ya existe
   (ehs.hecho_lectura_mensual_hist + su trigger, migracion 0004). La primera
   NO: el trigger archiva el valor de antes pero no tenia donde guardar el
   porque. Esta migracion le agrega esa columna al hecho, a la historia, y al
   trigger, y anade el UNICO procedimiento que puede escribir una correccion.

   Por que no se reutiliza sp_capturar_lote para esto: ese procedimiento existe
   para el mes completo (27 filas, motivo implicito = "asi vino el reporte") y
   su UPDATE silencioso (when matched and d.valor <> s.valor) es para reenviar
   un Excel corregido, no para que una persona corrija UN valor con una razon
   que quede escrita. Mezclar los dos casos en un procedimiento habria hecho
   que el motivo fuera opcional en la practica: bastaba reenviar el lote.
   =========================================================================== */

/* --------------------------------------------------- el motivo, en el hecho */

if not exists (select 1 from sys.columns
               where object_id = object_id('ehs.hecho_lectura_mensual') and name = 'motivo_correccion')
    alter table ehs.hecho_lectura_mensual add motivo_correccion varchar(300) null;
go

/* --------------------------------------------------- el motivo, en la historia */

if not exists (select 1 from sys.columns
               where object_id = object_id('ehs.hecho_lectura_mensual_hist') and name = 'motivo')
    alter table ehs.hecho_lectura_mensual_hist add motivo varchar(300) null;
go

/* ------------------------------------------------------- el trigger, corregido */

/* DEFECTO REAL que esta migracion tambien corrige, no solo el trigger de la
   migracion 0004 tal cual: ese trigger recalculaba modificado_por = suser_sname()
   DESPUES del update original, pisando en el mismo instante lo que
   sp_capturar_lote ya habia puesto con cuidado (d.modificado_por = @capturado_por,
   en su rama "when matched and d.valor <> s.valor"). suser_sname() con la
   aplicacion conectada siempre es 'ehs_app' — la cuenta de servicio, nunca la
   persona — asi que ninguna correccion hecha por la app quedaba con quien la hizo
   de verdad, exactamente el dato que R.5.3.4 pide conservar. Se via al construir
   sp_corregir_lectura (abajo): su @corregido_por llegaba bien hasta el UPDATE, y
   el historial igual mostraba 'ehs_app' en vez de la persona.

   La correccion: el propio UPDATE de cada procedimiento pone modificado_por (ya
   lo hacia sp_capturar_lote; sp_corregir_lectura lo hace abajo tambien), y el
   trigger SOLO archiva lo que ya quedo en la fila — nunca vuelve a escribir
   modificado_por con su propia idea de quien fue. reemplazado_por en el
   historial lee inserted.modificado_por, con suser_sname() como respaldo unico
   para el caso de un UPDATE directo por SQL que no paso por un procedimiento
   (un DBA arreglando algo a mano no tiene @corregido_por que ofrecer). */
if object_id('ehs.tr_lectura_mensual_hist') is not null
    drop trigger ehs.tr_lectura_mensual_hist;
go
create trigger ehs.tr_lectura_mensual_hist
on ehs.hecho_lectura_mensual
after update
as
begin
    set nocount on;
    insert ehs.hecho_lectura_mensual_hist
        (lectura_id, fecha, sitio_id, magnitud_id,
         valor_anterior, estado_anterior, reemplazado_por, reemplazado_en, motivo)
    select d.lectura_id, d.fecha, d.sitio_id, d.magnitud_id,
           d.valor, d.estado, isnull(i.modificado_por, suser_sname()), sysdatetime(),
           i.motivo_correccion
    from deleted d
    join inserted i on i.lectura_id = d.lectura_id
    where i.valor <> d.valor or i.estado <> d.estado;
end;
go

/* ---------------------------------------------------- el procedimiento --- */

if object_id('ehs.sp_corregir_lectura') is not null
    drop procedure ehs.sp_corregir_lectura;
go

create procedure ehs.sp_corregir_lectura
    @fecha          date,
    @sitio_id       varchar(20),
    @magnitud_id    varchar(40),
    @valor_nuevo    decimal(18,4),
    @motivo         varchar(300),
    @corregido_por  varchar(60)
as
begin
    set nocount on;
    set xact_abort on;

    if @corregido_por is null or ltrim(rtrim(@corregido_por)) = ''
    begin
        raiserror('Falta @corregido_por. Igual que al capturar (R.5.3.4), la correccion tiene que decir quien la hizo.', 16, 1);
        return;
    end;

    /* Un motivo de una palabra no es un motivo. 10 caracteres es "se corrigio el
       dato", el piso mas bajo que todavia obliga a escribir algo con sentido en
       vez de rellenar el campo para que el formulario lo deje pasar. */
    if @motivo is null or len(ltrim(rtrim(@motivo))) < 10
    begin
        raiserror('El motivo de la correccion tiene que explicar algo, no solo llenar el campo (minimo 10 caracteres).', 16, 1);
        return;
    end;

    if @valor_nuevo < 0
    begin
        raiserror('Valor negativo. Ninguna de las nueve magnitudes puede serlo.', 16, 1);
        return;
    end;

    if not exists (select 1 from ehs.hecho_lectura_mensual
                    where fecha = @fecha and sitio_id = @sitio_id and magnitud_id = @magnitud_id)
    begin
        raiserror('Esa lectura no existe todavia. Se captura, no se corrige.', 16, 1);
        return;
    end;

    begin try
        begin transaction;

        update ehs.hecho_lectura_mensual
           set valor              = @valor_nuevo,
               estado             = 'corregido',
               motivo_correccion  = @motivo,
               origen             = 'correccion manual: ' + @motivo,
               modificado_por     = @corregido_por,
               modificado_en      = sysdatetime()
         where fecha = @fecha and sitio_id = @sitio_id and magnitud_id = @magnitud_id
           /* Sin cambio real no hay correccion que archivar (misma razon que en
              sp_capturar_lote): reenviar el mismo valor no tiene que ensuciar la
              bitacora con una version que no cambia nada. */
           and valor <> @valor_nuevo;

        declare @filas int = @@rowcount;

        commit transaction;

        select filas_corregidas = @filas,
               fecha = @fecha, sitio_id = @sitio_id, magnitud_id = @magnitud_id,
               valor_nuevo = @valor_nuevo;
    end try
    begin catch
        if @@trancount > 0 rollback transaction;
        throw;
    end catch;
end;
go

/* ------------------------------------------------- historial de correcciones --- */

/* Lo que la pantalla "Consultar y corregir" muestra como historial, y lo que
   remplaza a la franja de correccion que el modo JSON pintaba desde un CSV
   estatico (public/js/franja_correccion.js): aqui la lista sale de la propia
   base, se actualiza sola con cada correccion nueva. */
create or alter view ehs.v_correcciones
as
    select h.hist_id,
           h.fecha, f.anio, f.num_mes as mes,
           h.sitio_id, s.sitio_corto,
           h.magnitud_id, m.magnitud,
           valor_anterior = h.valor_anterior,
           valor_corregido = l.valor,
           h.motivo,
           autorizado_por = h.reemplazado_por,
           corregido_en = h.reemplazado_en
      from ehs.hecho_lectura_mensual_hist h
      join ehs.hecho_lectura_mensual l on l.lectura_id = h.lectura_id
      join ref.dim_fecha f    on f.fecha = h.fecha
      join ref.dim_sitio s    on s.sitio_id = h.sitio_id
      join ref.dim_magnitud m on m.magnitud_id = h.magnitud_id
     where h.motivo is not null;  -- una correccion de verdad, no una carga masiva reenviada
go

print 'Migracion 0009: correccion con motivo obligatorio (ehs.sp_corregir_lectura, ehs.v_correcciones).';
go
