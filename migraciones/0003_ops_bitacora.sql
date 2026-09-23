/* ===========================================================================
   Migracion 0003 — la maquinaria de auditoria del sistema, en ops

   Va ANTES que los hechos de ehs a proposito: ehs.lectura_rechazada (en la
   migracion 0004) referencia ops.carga_log por llave foranea, y el objeto
   referenciado tiene que existir antes. Es la misma leccion que ya costo un
   defecto real en app/sql/02-vistas.sql: el orden de creacion importa en SQL
   Server, no es una sugerencia.
   =========================================================================== */

if object_id('ops.carga_log') is null
create table ops.carga_log (
    carga_id       bigint        not null identity(1,1) constraint pk_carga_log primary key,
    proceso        varchar(60)   not null,
    inicio         datetime2(0)  not null,
    fin            datetime2(0)  null,
    filas          int           null,
    resultado      varchar(20)   null,
    detalle        varchar(400)  null,
    ejecutado_por  varchar(60)   null,
    rechazos       int           null,
    constraint ck_carga_resultado check (resultado in ('ok', 'error'))
);
go

/* --------------------------------------------------- lo que NO paso validacion */

/* R.5.3.5: lo que no pasa validacion no entra, y tampoco se pierde. Se aparta aqui con
   su motivo y con la fila cruda tal como llego, para que se pueda diagnosticar sin
   volver al origen. Nunca se corrige a mano en el destino: se arregla en la fuente y
   se vuelve a cargar, que es idempotente. */
if object_id('ops.lectura_rechazada') is null
create table ops.lectura_rechazada (
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
    constraint fk_rechazo_carga foreign key (carga_id) references ops.carga_log (carga_id)
);
go

/* Las columnas del rechazo son TEXTO a proposito: si la fila se rechazo justamente
   porque su fecha no era una fecha o su valor no era un numero, tipar la columna haria
   imposible guardar lo que llego. Se guarda lo que vino, no lo que deberia haber venido. */

if not exists (select 1 from sys.indexes
               where name = 'ix_rechazo_pendiente'
                 and object_id = object_id('ops.lectura_rechazada'))
create index ix_rechazo_pendiente
    on ops.lectura_rechazada (resuelto, detectado_en) include (motivo, origen);
go

/* --------------------------------------------------- registro de migraciones */

/* El propio ejecutor de migraciones (scripts/migrar.js) crea esta tabla ANTES de
   correr la migracion 0001, porque sin ella no hay donde anotar que 0001 corrio.
   Se declara tambien aqui, con 'if object_id is null', para que este archivo se
   pueda leer como la fuente de verdad completa del esquema sin tener que abrir
   el codigo del ejecutor para saber que existe esta tabla. */
if object_id('ops.migracion_aplicada') is null
create table ops.migracion_aplicada (
    archivo      varchar(200)  not null constraint pk_migracion_aplicada primary key,
    aplicada_en  datetime2(0)  not null constraint df_migracion_cuando default sysdatetime(),
    aplicada_por varchar(60)   not null constraint df_migracion_quien  default suser_sname(),
    checksum     char(64)      not null
);
go

print 'Migracion 0003: ops.carga_log, ops.lectura_rechazada y ops.migracion_aplicada creadas o ya existentes.';
go
