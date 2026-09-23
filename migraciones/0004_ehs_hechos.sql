/* ===========================================================================
   Migracion 0004 — los hechos mensuales de EHS

   Portado de app/sql/01-esquema.sql, con las llaves foraneas apuntando a
   ref.* en vez de a si misma. El default de capturado_por sigue siendo
   suser_sname(): es correcto para quien inserta directo con su propia
   identidad, y es exactamente por lo que ehs.sp_capturar_lote (migracion
   0006) exige @capturado_por explicito en vez de confiar en el default —
   con la cuenta de servicio del login de aplicacion, suser_sname() diria
   el nombre del login, no el de la persona.
   =========================================================================== */

if object_id('ehs.hecho_lectura_mensual') is null
create table ehs.hecho_lectura_mensual (
    lectura_id      bigint         not null identity(1,1)
                        constraint pk_hecho_lectura_mensual primary key,
    fecha           date           not null,
    sitio_id        varchar(20)    not null,
    magnitud_id     varchar(40)    not null,
    valor           decimal(18,4)  not null,
    origen          varchar(120)   not null,
    estado          varchar(20)    not null constraint df_lectura_estado default 'capturado',
    capturado_por   varchar(60)    not null constraint df_lectura_quien  default suser_sname(),
    capturado_en    datetime2(0)   not null constraint df_lectura_cuando default sysdatetime(),
    modificado_por  varchar(60)    null,
    modificado_en   datetime2(0)   null,

    /* EL CORAZON DEL PROYECTO. El reporte de EHS perdio un mes entero y un accidente
       porque una celda se escribio a mano encima de una formula. Esta restriccion es
       lo que hace imposible capturar dos veces el mismo hecho o pisar uno existente. */
    constraint uq_lectura_mensual unique (fecha, sitio_id, magnitud_id),

    constraint fk_lectura_fecha    foreign key (fecha)       references ref.dim_fecha (fecha),
    constraint fk_lectura_sitio    foreign key (sitio_id)    references ref.dim_sitio (sitio_id),
    constraint fk_lectura_magnitud foreign key (magnitud_id) references ref.dim_magnitud (magnitud_id),
    constraint ck_lectura_estado   check (estado in ('capturado', 'validado', 'corregido'))
);
go

/* Un mes sin captura es la AUSENCIA de filas, nunca un cero: un cero es una lectura
   de valor cero. Por eso no hay filas precargadas en blanco. */

if not exists (select 1 from sys.indexes
               where name = 'ix_lectura_sitio_magnitud'
                 and object_id = object_id('ehs.hecho_lectura_mensual'))
create index ix_lectura_sitio_magnitud
    on ehs.hecho_lectura_mensual (sitio_id, magnitud_id) include (fecha, valor);
go

/* Una correccion no borra el valor anterior: lo archiva. */
if object_id('ehs.hecho_lectura_mensual_hist') is null
create table ehs.hecho_lectura_mensual_hist (
    hist_id         bigint         not null identity(1,1)
                        constraint pk_lectura_hist primary key,
    lectura_id      bigint         not null,
    fecha           date           not null,
    sitio_id        varchar(20)    not null,
    magnitud_id     varchar(40)    not null,
    valor_anterior  decimal(18,4)  not null,
    estado_anterior varchar(20)    not null,
    reemplazado_por varchar(60)    not null,
    reemplazado_en  datetime2(0)   not null
);
go

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
         valor_anterior, estado_anterior, reemplazado_por, reemplazado_en)
    select d.lectura_id, d.fecha, d.sitio_id, d.magnitud_id,
           d.valor, d.estado, suser_sname(), sysdatetime()
    from deleted d
    join inserted i on i.lectura_id = d.lectura_id
    where i.valor <> d.valor or i.estado <> d.estado;

    update l
       set modificado_por = suser_sname(),
           modificado_en  = sysdatetime()
      from ehs.hecho_lectura_mensual l
      join inserted i on i.lectura_id = l.lectura_id;
end;
go

/* Consumo diario de agua. La tabla existe y esta VACIA a proposito: el area lleva el
   dato y todavia no lo ha entregado. La vista se enciende sola cuando lleguen filas.
   No se dibuja ni un valor diario inventado. */
if object_id('ehs.hecho_lectura_diaria_agua') is null
create table ehs.hecho_lectura_diaria_agua (
    fecha        date           not null,
    sitio_id     varchar(20)    not null,
    consumo_m3   decimal(18,4)  not null,
    observacion  varchar(200)   null,
    constraint pk_lectura_diaria_agua primary key (fecha, sitio_id),
    constraint fk_lectura_diaria_sitio foreign key (sitio_id) references ref.dim_sitio (sitio_id)
);
go

print 'Migracion 0004: hechos de ehs creados o ya existentes.';
go
