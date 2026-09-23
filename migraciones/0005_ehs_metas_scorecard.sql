/* ===========================================================================
   Migracion 0005 — metas y scorecard corporativo

   Portado de app/sql/01-esquema.sql, sin cambios de columna.
   =========================================================================== */

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
    constraint fk_meta_kpi foreign key (kpi_id) references ref.dim_kpi (kpi_id)
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
    constraint fk_scorecard_sitio foreign key (sitio_id) references ref.dim_sitio (sitio_id),
    constraint fk_scorecard_kpi   foreign key (kpi_id)   references ref.dim_kpi (kpi_id)
);
go

print 'Migracion 0005: ehs.meta y ehs.scorecard_anual creadas o ya existentes.';
go
