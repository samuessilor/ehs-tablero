/* ===========================================================================
   Migracion 0002 — las dimensiones compartidas, en ref

   Idempotente: se puede correr de nuevo sin romper nada. Portado de
   app/sql/01-esquema.sql sin cambiar una columna, solo de esquema.
   =========================================================================== */

if object_id('ref.dim_sitio') is null
create table ref.dim_sitio (
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

if object_id('ref.dim_fecha') is null
create table ref.dim_fecha (
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

if object_id('ref.dim_magnitud') is null
create table ref.dim_magnitud (
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

if object_id('ref.dim_kpi') is null
create table ref.dim_kpi (
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
if object_id('ref.kpi_magnitud') is null
create table ref.kpi_magnitud (
    kpi_id       varchar(40) not null,
    magnitud_id  varchar(40) not null,
    rol          varchar(12) not null,
    constraint pk_kpi_magnitud primary key (kpi_id, magnitud_id, rol),
    constraint fk_kpi_magnitud_kpi      foreign key (kpi_id)      references ref.dim_kpi (kpi_id),
    constraint fk_kpi_magnitud_magnitud foreign key (magnitud_id) references ref.dim_magnitud (magnitud_id),
    constraint ck_kpi_magnitud_rol      check (rol in ('numerador', 'denominador'))
);
go

print 'Migracion 0002: dimensiones en ref creadas o ya existentes.';
go
