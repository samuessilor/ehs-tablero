/* =====================================================================
   Migracion 0017 — confirmar avisos automaticos de calidad (28-sep-2026)
   ---------------------------------------------------------------------
   Pedido de Samuel sobre los 10 "salto_atipico" del corte de julio 2026 (los
   pego en el chat, uno por uno): "todos estan verificados y aprobados".

   Un aviso de gravedad 'aviso' (hoy solo 'salto_atipico') no corrige nada: solo
   pregunta si un salto brusco mes a mes es un evento real (parada, pico de
   produccion) o un error de captura, y quien lo sabe es el area. Hasta ahora la
   respuesta se quedaba en la cabeza de quien miraba la tabla — el mismo aviso
   volvia a salir "a revisar" en cada visita al tablero, sin dejar constancia de
   que alguien ya lo miro y lo dio por bueno. El boton ya decia "dar un
   veredicto"; no habia donde guardarlo.

   ehs.aviso_confirmado es solo eso: quien confirmo cual aviso, cuando y con que
   nota. NO re-verifica el salto — esa cuenta ya la hace, una sola vez, la
   consulta de calidadDato en adaptador_sql.js (el mismo lag() que arma
   ehs.v_calidad_avisos). Si el dato de origen cambia despues (una correccion,
   por ejemplo), esta fila deja de coincidir con ningun aviso vigente —
   calidadDato lo recalcula en cada corte — y la confirmacion vieja simplemente
   deja de aplicarse, sin que haga falta borrarla a mano: no hay nada que
   revalidar activamente, el JOIN mismo la vuelve irrelevante.

   codigo esta restringido a 'salto_atipico' a proposito (constraint + el
   procedimiento de abajo): los avisos de gravedad 'error' (valor_negativo,
   denominador_invalido, mes_incompleto) son defectos estructurales del dato,
   no un juicio que alguien del area pueda avalar — esos se corrigen (Consultar
   y corregir), no se confirman.

   Misma disciplina de escritura que 0009 (ehs.sp_corregir_lectura): la unica
   puerta es un procedimiento, ehs_app no tiene db_datawriter y el GRANT vive en
   instalacion/crear-logins.sql, no aqui (R.4.1). */

set nocount on;
go

/* -------------------------------------------------- 1. la bitacora de confirmaciones */
if object_id('ehs.aviso_confirmado') is null
    create table ehs.aviso_confirmado (
        fecha           date          not null,
        sitio_id        varchar(20)   not null,
        magnitud_id     varchar(40)   not null,
        codigo          varchar(40)   not null
            constraint ck_aviso_confirmado_codigo check (codigo in ('salto_atipico')),
        confirmado_por  varchar(60)   not null,
        nota            varchar(300)  null,
        confirmado_en   datetime2(0)  not null
            constraint df_aviso_confirmado_cuando default sysdatetime(),
        constraint pk_aviso_confirmado primary key (fecha, sitio_id, magnitud_id, codigo),
        constraint fk_aviso_confirmado_fecha
            foreign key (fecha)       references ref.dim_fecha (fecha),
        constraint fk_aviso_confirmado_sitio
            foreign key (sitio_id)    references ref.dim_sitio (sitio_id),
        constraint fk_aviso_confirmado_magnitud
            foreign key (magnitud_id) references ref.dim_magnitud (magnitud_id)
    );
go

/* --------------------------------------------------------- 2. la puerta de escritura */
create or alter procedure ehs.sp_confirmar_aviso
    @fecha          date,
    @sitio_id       varchar(20),
    @magnitud_id    varchar(40),
    @codigo         varchar(40),
    @confirmado_por varchar(60),
    @nota           varchar(300) = null
as
begin
    set nocount on;

    if @codigo <> 'salto_atipico'
        throw 50000, N'Solo se confirman avisos de salto atipico. Un valor negativo, un denominador en cero o un mes incompleto no se confirma: se corrige, con "Consultar y corregir".', 1;

    if @confirmado_por is null or ltrim(rtrim(@confirmado_por)) = ''
        throw 50000, N'Falta quien confirma. La bitacora tiene que poder nombrarlo.', 1;

    if not exists (
        select 1 from ehs.hecho_lectura_mensual
         where fecha = @fecha and sitio_id = @sitio_id and magnitud_id = @magnitud_id
    )
        throw 50000, N'No existe esa lectura: no hay nada que confirmar.', 1;

    -- idempotente: confirmar de nuevo el mismo aviso actualiza quien/cuando/nota en
    -- vez de duplicar o fallar por la llave primaria.
    merge ehs.aviso_confirmado as destino
    using (select @fecha as fecha, @sitio_id as sitio_id,
                  @magnitud_id as magnitud_id, @codigo as codigo) as origen
       on destino.fecha = origen.fecha and destino.sitio_id = origen.sitio_id
      and destino.magnitud_id = origen.magnitud_id and destino.codigo = origen.codigo
    when matched then
        update set confirmado_por = @confirmado_por, nota = @nota, confirmado_en = sysdatetime()
    when not matched then
        insert (fecha, sitio_id, magnitud_id, codigo, confirmado_por, nota)
        values (@fecha, @sitio_id, @magnitud_id, @codigo, @confirmado_por, @nota);

    select filas_confirmadas = @@rowcount;
end;
go
