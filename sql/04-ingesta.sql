/* =====================================================================
   04-ingesta.sql — la puerta de escritura del esquema ehs
   ---------------------------------------------------------------------
   Los archivos 01, 02 y 03 construyen la superficie de LECTURA: el modelo,
   las vistas que implementan las dos reglas del area, y la carga del
   historico. Este archivo es la superficie de ESCRITURA, y va aparte a
   proposito: son dos decisiones distintas y IT puede tomarlas en momentos
   distintos. Un tablero que solo lee no necesita nada de aqui.

   Que resuelve, en una frase: que capturar el dato del mes deje de ser
   copiar veintisiete numeros entre tres hojas de un libro.

   Las cuatro reglas del estandar que este archivo tiene que cumplir, y
   donde se cumplen:

     R.5.3.3  idempotencia — sp_capturar_lote se puede correr dos veces con
              la misma entrada y el estado final es el mismo. Lo garantiza
              el merge sobre uq_lectura_mensual, no una comprobacion previa
              que podria correr en paralelo con otra carga.

     R.5.3.4  bitacora — cada lote deja fila en ehs.carga_log con quien lo
              ejecuto, cuando, cuantas filas entraron y cuantas se apartaron.

     R.5.3.5  rechazos — lo que no pasa validacion no entra y tampoco se
              pierde: va a ehs.lectura_rechazada con su motivo y su valor
              tal como llego. El resto del lote SI entra. Un numero mal
              tecleado no puede bloquear los otros veintiseis.

     R.5.3.6  una celda vacia no es un cero — el tipo de @valor es
              decimal NULL y una fila con valor nulo se descarta ANTES de
              llegar aqui, en el cliente y en el servidor. Aqui no llega.

   ---------------------------------------------------------------------
   POR QUE EL PROCEDIMIENTO EXIGE @capturado_por Y NO USA EL DEFAULT

   ehs.hecho_lectura_mensual.capturado_por tiene default suser_sname().
   Ese default es correcto para una carga masiva que un DBA ejecuta con su
   propia cuenta nominal. Es ENGANOSO para una aplicacion: la app se
   conecta con una cuenta de servicio, asi que suser_sname() devolveria
   'svc_ehs_app' en las veintisiete filas y la bitacora diria quien es el
   programa, no quien es la persona. Se perderia exactamente el dato que
   R.5.3.4 pide conservar.

   Por eso @capturado_por es obligatorio, no tiene default, y el
   procedimiento rechaza el lote entero si viene vacio. La identidad la
   pone quien conoce a la persona — la capa de aplicacion, contra el
   directorio corporativo — no el motor, que solo conoce la conexion.
   ===================================================================== */

set nocount on;
go

/* -------------------------------------------- traza de quien ejecuta el lote */

/* carga_log nacio para procesos automaticos, donde el 'quien' es el nombre del
   proceso. Con captura manual hay una persona detras y hay que poder nombrarla. */
if not exists (select 1 from sys.columns
               where object_id = object_id('ehs.carga_log') and name = 'ejecutado_por')
    alter table ehs.carga_log add ejecutado_por varchar(60) null;
go

if not exists (select 1 from sys.columns
               where object_id = object_id('ehs.carga_log') and name = 'rechazos')
    alter table ehs.carga_log add rechazos int null;
go

/* ------------------------------------------------- el tipo del lote de entrada */

/* Un lote es el mes completo de un sitio: nueve magnitudes. Se envia entero y se
   resuelve entero, en una transaccion. Enviarlas de a una abriria la puerta a que
   un mes quede a medias si se cae la red en la quinta, que es una forma nueva del
   mismo problema que este trabajo vino a quitar. */
if type_id('ehs.lote_lectura') is null
    create type ehs.lote_lectura as table (
        fecha_texto     varchar(40)   null,
        sitio_texto     varchar(60)   null,
        magnitud_texto  varchar(60)   null,
        valor_texto     varchar(60)   null
    );
go

/* Los cuatro campos son TEXTO, igual que en ehs.lectura_rechazada y por la misma
   razon: si una fila se rechaza porque su valor no era un numero, un parametro
   decimal no habria podido transportarla hasta aqui para contar por que fallo.
   La conversion y su fracaso son parte de lo que este procedimiento examina. */

/* ------------------------------------------------------ el unico procedimiento
   de escritura */

if object_id('ehs.sp_capturar_lote') is not null
    drop procedure ehs.sp_capturar_lote;
go

/* --------------------------------------------------------------------------
   IMPOSIBLE NO ES LO MISMO QUE IMPROBABLE

   La primera version de este procedimiento rechazaba por igual un valor
   negativo y un valor alto. Son dos cosas distintas y tratarlas igual es un
   error de diseno con consecuencias:

     Un residuo de -5 kg es IMPOSIBLE. No existe. Hay que arreglarlo en el
     origen y volver a cargar, que es lo que R.5.3.5 describe.

     Un consumo de agua del doble del maximo historico es IMPROBABLE. Puede
     ser un cero de mas al teclear, y puede ser una fuga real que es justo lo
     que el indicador existe para detectar. Rechazarlo deja a la persona sin
     salida: no hay nada que corregir en el origen porque el dato es correcto,
     y el mes se queda sin capturar.

   Los limites de ehs.dim_magnitud son el minimo y el maximo historicos con
   50% de holgura. Son una referencia estadistica, no una ley fisica, y no
   pueden bloquear un mes excepcional.

   Por eso hay dos caminos. Lo imposible se rechaza siempre. Lo improbable se
   devuelve como advertencia y NO se graba, hasta que quien captura lo
   confirme con @confirmar_atipicos = 1. La confirmacion queda escrita en el
   origen de la fila, asi que despues se puede saber que ese numero raro se
   miro y se sostuvo, en vez de que se colo.

   Es la misma distincion que el tablero ya hace entre error y aviso.
   -------------------------------------------------------------------------- */

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

    insert ehs.carga_log (proceso, inicio, ejecutado_por)
    values ('captura manual', sysdatetime(), @capturado_por);
    set @carga_id = scope_identity();

    begin try
        begin transaction;

        /* ---------------------------------------------------------- 1. tipar */

        /* Se resuelve todo lo dudoso de una vez y se etiqueta el motivo del
           primer fallo encontrado. El orden importa: se comprueba que la fecha
           sea fecha antes de comprobar que exista en el calendario, porque el
           segundo mensaje no significa nada si el primero fallo. */
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
                 when not exists (select 1 from ehs.dim_fecha d where d.fecha = f.valor_fecha)
                      then 'El mes no existe en ehs.dim_fecha: ' + convert(varchar(10), f.valor_fecha)
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
               /* advertencia: lo improbable. Entra solo si quien captura lo sostiene. */
               case
                 when v.valor_num is null then null
                 when m.valor_max is not null and v.valor_num > m.valor_max
                      then 'Supera el maximo historico de ' + m.magnitud_id + ' con holgura ('
                           + cast(cast(m.valor_max as decimal(18,1)) as varchar(40))
                           + '). Confirma que es correcto.'
                 when m.valor_min is not null and v.valor_num > 0 and v.valor_num < m.valor_min
                      then 'Queda por debajo del minimo historico de ' + m.magnitud_id + ' ('
                           + cast(cast(m.valor_min as decimal(18,1)) as varchar(40))
                           + '). Confirma que es correcto.'
                 else null
               end
        from @lote l
        cross apply (select try_convert(date, l.fecha_texto) as valor_fecha) f
        cross apply (select try_convert(decimal(18,4), l.valor_texto) as valor_num) v
        left join ehs.dim_sitio    s on s.sitio_id    = l.sitio_texto and s.activo = 1
        left join ehs.dim_magnitud m on m.magnitud_id = l.magnitud_texto;

        /* ------------------------------------------------------- 2. apartar */

        insert ehs.lectura_rechazada
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

        /* --------------------------------------------------------- 3. grabar */

        /* El merge es lo que hace idempotente la operacion (R.5.3.3). Reenviar el
           mismo lote no duplica ni una fila: uq_lectura_mensual lo impide y el
           merge lo aprovecha en vez de pelearse con el.

           La condicion 'and d.valor <> s.valor' del when matched no es una
           optimizacion: sin ella, reenviar un lote identico dispararia el update
           en las veintisiete filas y el trigger de historia archivaria veintisiete
           versiones que no cambian nada. La bitacora se volveria ilegible en dos
           meses. */
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

        update ehs.carga_log
           set fin = sysdatetime(), filas = @grabadas, rechazos = @rechazos,
               resultado = 'ok',
               detalle = concat(@grabadas, ' grabadas, ', @rechazos, ' apartadas, ',
                                @pendientes, ' esperando confirmacion')
         where carga_id = @carga_id;

        commit transaction;

        /* Tres resultados, porque son tres cosas distintas que la persona tiene que
           poder distinguir de un vistazo: cuanto entro, que es imposible y hay que
           arreglar en el origen, y que es solo raro y hay que mirar. */
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
        update ehs.carga_log
           set fin = sysdatetime(), resultado = 'error',
               detalle = left(error_message(), 400)
         where carga_id = @carga_id;
        throw;
    end catch;
end;
go

/* --------------------------------------------- lo que la captura necesita leer */

/* El formulario tiene que saber que ya hay capturado para no pedir dos veces lo
   mismo ni dejar un hueco. Sin esta vista, el cliente tendria que deducirlo del
   tablero, que es una fuente distinta y podria discrepar. */
create or alter view ehs.v_captura_estado as
select f.anio,
       f.num_mes,
       s.sitio_id,
       s.sitio                        as sitio_nombre,
       count(l.lectura_id)            as capturadas,
       (select count(*) from ehs.dim_magnitud) as esperadas,
       max(l.capturado_en)            as ultima_captura,
       max(l.capturado_por)           as ultimo_capturador
  from ehs.dim_fecha f
 cross join ehs.dim_sitio s
  left join ehs.hecho_lectura_mensual l
         on l.fecha = f.fecha and l.sitio_id = s.sitio_id
 where s.activo = 1
 group by f.anio, f.num_mes, s.sitio_id, s.sitio;
go

/* Un mes sin ninguna captura aparece con capturadas = 0, no ausente: el formulario
   necesita poder ofrecerlo. Es el mismo criterio del tablero al reves — alli un mes
   sin dato no se dibuja porque no hay nada que mostrar; aqui si se ofrece porque es
   justamente lo que falta por hacer. */

print 'Puerta de escritura de ehs creada: sp_capturar_lote, lote_lectura, v_captura_estado.';
go
