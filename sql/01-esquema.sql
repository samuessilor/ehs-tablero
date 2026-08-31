/* ===========================================================================
   EHS · esquema de captura y modelo analitico
   SQL Server · nomenclatura snake_case, segun la instruccion de IT del 27-jul-2026

   Se ejecuta una sola vez, en el servidor de desarrollo, el dia que IT conceda
   permisos DDL. Es idempotente: se puede correr de nuevo sin romper nada.

   Diseno: lo generico abajo (sitio, fecha, magnitud, lectura) y lo especifico
   del area arriba, como DATO y no como codigo (dim_kpi, kpi_magnitud, meta).
   Anadir Calidad o Produccion es cargar filas, no alterar tablas.
   =========================================================================== */

if schema_id('ehs') is null
    exec ('create schema ehs');
go

/* ---------------------------------------------------------------- dimensiones */

if object_id('ehs.dim_sitio') is null
create table ehs.dim_sitio (
    sitio_id            varchar(20)  not null constraint pk_dim_sitio primary key,
    sitio               varchar(60)  not null,
    -- el nombre largo se trunca en un eje de categoria y deja de distinguir
    -- Celta de La Estrella; el corto es para ejes y cabeceras
    sitio_corto         varchar(20)  not null,
    nombre_corporativo  varchar(60)  not null,
    tipo                varchar(20)  not null,
    ciudad              varchar(40)  null,
    en_nacional_labs    bit          not null constraint df_sitio_labs default 0,
    en_nacional         bit          not null constraint df_sitio_nal  default 0,
    activo              bit          not null constraint df_sitio_act  default 1
);
go

if object_id('ehs.dim_fecha') is null
create table ehs.dim_fecha (
    -- grano mensual: siempre dia 1
    fecha      date         not null constraint pk_dim_fecha primary key,
    anio       smallint     not null,
    num_mes    tinyint      not null,
    mes        varchar(12)  not null,
    mes_corto  char(3)      not null,
    anio_mes   char(7)      not null,
    trimestre  char(2)      not null,
    constraint ck_dim_fecha_dia1 check (day(fecha) = 1),
    constraint ck_dim_fecha_mes  check (num_mes between 1 and 12)
);
go

if object_id('ehs.dim_magnitud') is null
create table ehs.dim_magnitud (
    magnitud_id  varchar(40)    not null constraint pk_dim_magnitud primary key,
    magnitud     varchar(60)    not null,
    -- unidad de CAPTURA, no de reporte: el agua se captura en m3 y se reporta en litros
    unidad       varchar(12)    not null,
    area         varchar(20)    not null constraint df_magnitud_area default 'ehs',
    valor_min    decimal(18,4)  null,
    valor_max    decimal(18,4)  null,
    orden        tinyint        not null constraint df_magnitud_orden default 0,
    constraint ck_magnitud_rango check (valor_min is null or valor_max is null
                                        or valor_min <= valor_max)
);
go

if object_id('ehs.dim_kpi') is null
create table ehs.dim_kpi (
    kpi_id    varchar(40)    not null constraint pk_dim_kpi primary key,
    kpi       varchar(60)    not null,
    -- unidad de REPORTE
    unidad    varchar(20)    not null,
    familia   varchar(20)    not null,
    area      varchar(20)    not null constraint df_kpi_area default 'ehs',
    -- conversion de unidad: 1000 para m3 -> l y para kg -> g, 1000000 para el
    -- frequency rate (accidentes por millon de horas), 1 para un conteo
    factor    decimal(18,6)  not null constraint df_kpi_factor default 1,
    -- los cinco KPI de EHS son techo: cumplir es quedar por debajo
    mejor_es  varchar(6)     not null constraint df_kpi_mejor default 'menor',
    formato   varchar(12)    not null constraint df_kpi_formato default '0.000',
    orden     tinyint        not null constraint df_kpi_orden default 0,
    constraint ck_kpi_mejor check (mejor_es in ('menor', 'mayor'))
);
go

/* La formula de cada KPI es DATO, no codigo. Residuos suma tres magnitudes en el
   numerador; con esta tabla puente deja de ser un caso especial en cada consulta. */
if object_id('ehs.kpi_magnitud') is null
create table ehs.kpi_magnitud (
    kpi_id       varchar(40) not null,
    magnitud_id  varchar(40) not null,
    rol          varchar(12) not null,
    constraint pk_kpi_magnitud primary key (kpi_id, magnitud_id, rol),
    constraint fk_kpi_magnitud_kpi      foreign key (kpi_id)      references ehs.dim_kpi (kpi_id),
    constraint fk_kpi_magnitud_magnitud foreign key (magnitud_id) references ehs.dim_magnitud (magnitud_id),
    constraint ck_kpi_magnitud_rol      check (rol in ('numerador', 'denominador'))
);
go

/* ---------------------------------------------------------------------- hechos */

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

    constraint fk_lectura_fecha    foreign key (fecha)       references ehs.dim_fecha (fecha),
    constraint fk_lectura_sitio    foreign key (sitio_id)    references ehs.dim_sitio (sitio_id),
    constraint fk_lectura_magnitud foreign key (magnitud_id) references ehs.dim_magnitud (magnitud_id),
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
    constraint fk_lectura_diaria_sitio foreign key (sitio_id) references ehs.dim_sitio (sitio_id)
);
go

/* ------------------------------------------------------- metas y scorecard */

if object_id('ehs.meta') is null
create table ehs.meta (
    anio       smallint       not null,
    ambito_id  varchar(20)    not null,
    kpi_id     varchar(40)    not null,
    valor      decimal(18,4)  not null,
    fuente     varchar(120)   not null,
    /* El libro trae TRES juegos de metas 2026 distintos y EHS no ha confirmado cual
       manda. Se cargan los tres y se marca el vigente; asi se decide despues sin
       perder de vista cual se estaba usando. */
    vigente    bit            not null constraint df_meta_vigente default 0,
    constraint pk_meta primary key (anio, ambito_id, kpi_id, fuente),
    constraint fk_meta_kpi foreign key (kpi_id) references ehs.dim_kpi (kpi_id)
);
go

if object_id('ehs.scorecard_anual') is null
create table ehs.scorecard_anual (
    anio           smallint       not null,
    sitio_id       varchar(20)    not null,
    kpi_id         varchar(40)    not null,
    /* NULL de verdad: de las 90 combinaciones, el scorecard solo publica 65.
       Una meta que no se publico no es una meta de cero. */
    meta           decimal(18,4)  null,
    real_ytd       decimal(18,4)  null,
    premisa_anual  decimal(9,4)   null,
    fuente         varchar(120)   not null,
    constraint pk_scorecard primary key (anio, sitio_id, kpi_id),
    constraint fk_scorecard_sitio foreign key (sitio_id) references ehs.dim_sitio (sitio_id),
    constraint fk_scorecard_kpi   foreign key (kpi_id)   references ehs.dim_kpi (kpi_id)
);
go

/* ------------------------------------------------------ traza de las cargas */

if object_id('ehs.carga_log') is null
create table ehs.carga_log (
    carga_id     bigint        not null identity(1,1) constraint pk_carga_log primary key,
    proceso      varchar(60)   not null,
    inicio       datetime2(0)  not null,
    fin          datetime2(0)  null,
    filas        int           null,
    resultado    varchar(20)   null,
    detalle      varchar(400)  null,
    constraint ck_carga_resultado check (resultado in ('ok', 'error'))
);
go

/* --------------------------------------------------- lo que NO paso validacion */

/* R.5.3.5: lo que no pasa validacion no entra, y tampoco se pierde. Se aparta aqui con
   su motivo y con la fila cruda tal como llego, para que se pueda diagnosticar sin
   volver al origen. Nunca se corrige a mano en el destino: se arregla en la fuente y
   se vuelve a cargar, que es idempotente.

   Sin esta tabla, una fila rechazada solo existe como una linea de consola que nadie
   vuelve a leer, y el reporte queda con un hueco que nadie sabe explicar. */
if object_id('ehs.lectura_rechazada') is null
create table ehs.lectura_rechazada (
    rechazo_id     bigint        not null identity(1,1)
                       constraint pk_lectura_rechazada primary key,
    carga_id       bigint        null,
    fecha_texto    varchar(40)   null,
    sitio_texto    varchar(60)   null,
    magnitud_texto varchar(60)   null,
    valor_texto    varchar(60)   null,
    fila_cruda     nvarchar(max) null,
    motivo         varchar(200)  not null,
    origen         varchar(120)  not null,
    detectado_en   datetime2(0)  not null
                       constraint df_rechazo_cuando default sysdatetime(),
    resuelto       bit           not null constraint df_rechazo_resuelto default 0,
    resuelto_en    datetime2(0)  null,
    constraint fk_rechazo_carga foreign key (carga_id) references ehs.carga_log (carga_id)
);
go

/* Las columnas del rechazo son TEXTO a proposito: si la fila se rechazo justamente
   porque su fecha no era una fecha o su valor no era un numero, tipar la columna haria
   imposible guardar lo que llego. Se guarda lo que vino, no lo que deberia haber venido. */

if not exists (select 1 from sys.indexes
               where name = 'ix_rechazo_pendiente'
                 and object_id = object_id('ehs.lectura_rechazada'))
create index ix_rechazo_pendiente
    on ehs.lectura_rechazada (resuelto, detectado_en) include (motivo, origen);
go

print 'Esquema ehs creado o ya existente.';
go
