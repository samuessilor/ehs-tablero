/* ============================================================================
   EHS — esquema Postgres (destino: Neon, free tier)

   DDL VIGENTE de las tablas de los tres esquemas (ehs, ref, ops), reconstruido
   leyendo las 21 migraciones de SQL Server completas
   (app\migraciones\0001_esquemas.sql .. 0021_ehs_mes_completo_por_ambito.sql),
   tomando para cada tabla su version MAS RECIENTE (columnas, defaults,
   constraints, indices) y no la de su migracion de creacion.

   Alcance: SOLO tablas. Vistas, triggers, procedimientos, tipos de tabla
   (ehs.lote_lectura) y roles/logins NO estan en este archivo — no se pidieron
   aqui y dependen de que estas tablas ya existan. Ver el bloque final para lo
   que falta portar y las dudas abiertas.

   Reglas de negocio que este archivo no toca (viven en vistas/procedimientos,
   no en la forma de las tablas) pero que hay que preservar al portar lo que
   falta — ver ehs\CLAUDE.md y entrega-reunion\CLAUDE.md:
     1. YTD = suma de numeradores / suma de denominadores (ehs.v_kpi_ytd).
     2. Los agregados suman magnitudes crudas y dividen al final (ehs.v_kpi_mensual).
     3. Un mes cuenta para un ambito solo si TODOS los sitios de ese ambito que
        reportaron ESE ANIO lo reportaron (ehs.v_lectura_ambito, migracion 0021).
     4. ehs.tr_lectura_mensual_hist archiva valor_anterior/estado_anterior SOLO
        cuando valor o estado cambian, nunca en cada UPDATE.
     5. sp_capturar_lote / sp_corregir_lectura / sp_confirmar_aviso son la UNICA
        puerta de escritura — ehs_app no tiene INSERT/UPDATE/DELETE directo.
     6. Las columnas de hora son TIMESTAMP SIN zona horaria (hora de pared de
        Colombia, no UTC) — ver nota sobre los DEFAULT mas abajo.
     7. Las claves de los logins/roles nunca van literales en un .sql versionado.
   ============================================================================ */

begin;

-- ---------------------------------------------------------------------------
-- Migracion 0001 — los tres esquemas
-- ---------------------------------------------------------------------------
create schema if not exists ref;
create schema if not exists ops;
create schema if not exists ehs;


-- =============================================================================
-- ESQUEMA ref — dimensiones compartidas
-- =============================================================================

-- ref.dim_sitio
--   Creada en 0002. Columna en_colombia_peru agregada en 0011.
create table if not exists ref.dim_sitio (
    sitio_id            varchar(20)  not null,
    sitio               varchar(60)  not null,
    sitio_corto         varchar(20)  not null,
    nombre_corporativo  varchar(60)  not null,
    tipo                varchar(20)  not null,
    ciudad              varchar(40)  null,
    en_nacional_labs    boolean      not null constraint df_sitio_labs   default false,
    en_nacional         boolean      not null constraint df_sitio_nal    default false,
    activo              boolean      not null constraint df_sitio_act    default true,
    en_colombia_peru    boolean      not null constraint df_sitio_colper default false,  -- 0011
    constraint pk_dim_sitio primary key (sitio_id)
);

-- ref.dim_fecha
--   Creada en 0002, sin alteraciones de columna en migraciones posteriores
--   (0010 solo agrega filas hasta 2035, no toca la forma de la tabla).
create table if not exists ref.dim_fecha (
    -- grano mensual: siempre dia 1
    fecha      date         not null,
    anio       smallint     not null,
    num_mes    smallint     not null,   -- tinyint -> smallint (Postgres no tiene tinyint)
    mes        varchar(12)  not null,
    mes_corto  char(3)      not null,
    anio_mes   char(7)      not null,
    trimestre  char(2)      not null,
    constraint pk_dim_fecha primary key (fecha),
    constraint ck_dim_fecha_dia1 check (extract(day from fecha) = 1),
    constraint ck_dim_fecha_mes  check (num_mes between 1 and 12)
);

-- ref.dim_magnitud
--   Creada en 0002. requerida_colombia agregada en 0011. forma_residuo
--   agregada en 0015.
create table if not exists ref.dim_magnitud (
    magnitud_id         varchar(40)    not null,
    magnitud            varchar(60)    not null,
    -- unidad de CAPTURA, no de reporte: el agua se captura en m3 y se reporta en litros
    unidad               varchar(12)    not null,
    area                 varchar(20)    not null constraint df_magnitud_area default 'ehs',
    valor_min            numeric(18,4)  null,
    valor_max            numeric(18,4)  null,
    orden                smallint       not null constraint df_magnitud_orden default 0,  -- tinyint -> smallint
    requerida_colombia   boolean        not null constraint df_magnitud_requerida default true,   -- 0011
    forma_residuo        varchar(10)    null,                                                       -- 0015
    constraint pk_dim_magnitud primary key (magnitud_id),
    constraint ck_magnitud_rango check (valor_min is null or valor_max is null
                                        or valor_min <= valor_max),
    constraint ck_dim_magnitud_forma_residuo check (forma_residuo in ('desglose', 'total'))  -- 0015
);

-- ref.dim_kpi
--   Creada en 0002, sin alteraciones de columna en migraciones posteriores
--   (0011 solo actualiza datos de formato, no la forma de la tabla).
create table if not exists ref.dim_kpi (
    kpi_id    varchar(40)    not null,
    kpi       varchar(60)    not null,
    -- unidad de REPORTE
    unidad    varchar(20)    not null,
    familia   varchar(20)    not null,
    area      varchar(20)    not null constraint df_kpi_area default 'ehs',
    -- conversion de unidad: 1000 para m3 -> l y para kg -> g, 1000000 para el
    -- frequency rate (accidentes por millon de horas), 1 para un conteo
    factor    numeric(18,6)  not null constraint df_kpi_factor default 1,
    -- los cinco KPI de EHS son techo: cumplir es quedar por debajo
    mejor_es  varchar(6)     not null constraint df_kpi_mejor default 'menor',
    formato   varchar(12)    not null constraint df_kpi_formato default '0.000',
    orden     smallint       not null constraint df_kpi_orden default 0,  -- tinyint -> smallint
    constraint pk_dim_kpi primary key (kpi_id),
    constraint ck_kpi_mejor check (mejor_es in ('menor', 'mayor'))
);

-- ref.kpi_magnitud
--   Creada en 0002, sin alteraciones de columna.
create table if not exists ref.kpi_magnitud (
    kpi_id       varchar(40) not null,
    magnitud_id  varchar(40) not null,
    rol          varchar(12) not null,
    constraint pk_kpi_magnitud primary key (kpi_id, magnitud_id, rol),
    constraint fk_kpi_magnitud_kpi      foreign key (kpi_id)      references ref.dim_kpi (kpi_id),
    constraint fk_kpi_magnitud_magnitud foreign key (magnitud_id) references ref.dim_magnitud (magnitud_id),
    constraint ck_kpi_magnitud_rol      check (rol in ('numerador', 'denominador'))
);


-- =============================================================================
-- ESQUEMA ops — maquinaria de auditoria del sistema
-- =============================================================================

-- ops.carga_log
--   Creada en 0003, sin alteraciones de columna en migraciones posteriores.
create table if not exists ops.carga_log (
    carga_id       bigint        generated always as identity,
    proceso        varchar(60)   not null,
    inicio         timestamp(0)  not null,
    fin            timestamp(0)  null,
    filas          int           null,
    resultado      varchar(20)   null,
    detalle        varchar(400)  null,
    ejecutado_por  varchar(60)   null,
    rechazos       int           null,
    constraint pk_carga_log primary key (carga_id),
    constraint ck_carga_resultado check (resultado in ('ok', 'error'))
);

-- ops.lectura_rechazada
--   Creada en 0003, sin alteraciones de columna.
--   Las columnas del rechazo son TEXTO a proposito: si la fila se rechazo
--   justamente porque su fecha no era una fecha o su valor no era un numero,
--   tipar la columna haria imposible guardar lo que llego.
create table if not exists ops.lectura_rechazada (
    rechazo_id     bigint        generated always as identity,
    carga_id       bigint        null,
    fecha_texto    varchar(40)   null,
    sitio_texto    varchar(60)   null,
    magnitud_texto varchar(60)   null,
    valor_texto    varchar(60)   null,
    fila_cruda     text          null,   -- nvarchar(max) -> text
    motivo         varchar(200)  not null,
    origen         varchar(120)  not null,
    detectado_en   timestamp(0)  not null constraint df_rechazo_cuando default localtimestamp(0),
    resuelto       boolean       not null constraint df_rechazo_resuelto default false,
    resuelto_en    timestamp(0)  null,
    constraint pk_lectura_rechazada primary key (rechazo_id),
    constraint fk_rechazo_carga foreign key (carga_id) references ops.carga_log (carga_id)
);

create index if not exists ix_rechazo_pendiente
    on ops.lectura_rechazada (resuelto, detectado_en) include (motivo, origen);

-- ops.migracion_aplicada
--   Creada en 0003, sin alteraciones de columna. El propio ejecutor de
--   migraciones la crea antes de correr 0001; se declara igual aqui para que
--   este archivo sea la fuente de verdad completa del esquema.
create table if not exists ops.migracion_aplicada (
    archivo      varchar(200)  not null,
    aplicada_en  timestamp(0)  not null constraint df_migracion_cuando default localtimestamp(0),
    aplicada_por varchar(60)   not null constraint df_migracion_quien  default current_user,
    checksum     char(64)      not null,
    constraint pk_migracion_aplicada primary key (archivo)
);


-- =============================================================================
-- ESQUEMA ehs — el negocio del area
-- =============================================================================

-- ehs.hecho_lectura_mensual
--   Creada en 0004. motivo_correccion agregada en 0009. Revisada tambien en
--   0014/0015/0021 (procedimientos y vistas que la leen) y 0016/0018/0019/0020
--   (solo datos) — ninguna de esas cambia la forma de la tabla.
create table if not exists ehs.hecho_lectura_mensual (
    lectura_id      bigint         generated always as identity,
    fecha           date           not null,
    sitio_id        varchar(20)    not null,
    magnitud_id     varchar(40)    not null,
    valor           numeric(18,4)  not null,
    origen          varchar(120)   not null,
    estado          varchar(20)    not null constraint df_lectura_estado default 'capturado',
    capturado_por   varchar(60)    not null constraint df_lectura_quien  default current_user,
    capturado_en    timestamp(0)   not null constraint df_lectura_cuando default localtimestamp(0),
    modificado_por  varchar(60)    null,
    modificado_en   timestamp(0)   null,
    motivo_correccion varchar(300) null,  -- 0009

    constraint pk_hecho_lectura_mensual primary key (lectura_id),

    -- EL CORAZON DEL PROYECTO: impide capturar dos veces el mismo hecho o
    -- pisar uno existente sin pasar por una correccion con motivo.
    constraint uq_lectura_mensual unique (fecha, sitio_id, magnitud_id),

    constraint fk_lectura_fecha    foreign key (fecha)       references ref.dim_fecha (fecha),
    constraint fk_lectura_sitio    foreign key (sitio_id)    references ref.dim_sitio (sitio_id),
    constraint fk_lectura_magnitud foreign key (magnitud_id) references ref.dim_magnitud (magnitud_id),
    constraint ck_lectura_estado   check (estado in ('capturado', 'validado', 'corregido'))
);

-- Un mes sin captura es la AUSENCIA de filas, nunca un cero.

create index if not exists ix_lectura_sitio_magnitud
    on ehs.hecho_lectura_mensual (sitio_id, magnitud_id) include (fecha, valor);

-- ehs.hecho_lectura_mensual_hist
--   Creada en 0004. motivo agregada en 0009. Sin FK a hecho_lectura_mensual en
--   el original (preservado tal cual: lectura_id es bigint not null, sin
--   constraint de llave foranea).
create table if not exists ehs.hecho_lectura_mensual_hist (
    hist_id         bigint         generated always as identity,
    lectura_id      bigint         not null,
    fecha           date           not null,
    sitio_id        varchar(20)    not null,
    magnitud_id     varchar(40)    not null,
    valor_anterior  numeric(18,4)  not null,
    estado_anterior varchar(20)    not null,
    reemplazado_por varchar(60)    not null,
    reemplazado_en  timestamp(0)   not null,
    motivo          varchar(300)   null,  -- 0009
    constraint pk_lectura_hist primary key (hist_id)
);

-- ehs.hecho_lectura_diaria_agua
--   Creada en 0004, sin alteraciones de columna. Vacia a proposito: el area
--   todavia no entrega el dato diario.
create table if not exists ehs.hecho_lectura_diaria_agua (
    fecha        date           not null,
    sitio_id     varchar(20)    not null,
    consumo_m3   numeric(18,4)  not null,
    observacion  varchar(200)   null,
    constraint pk_lectura_diaria_agua primary key (fecha, sitio_id),
    constraint fk_lectura_diaria_sitio foreign key (sitio_id) references ref.dim_sitio (sitio_id)
);

-- ehs.meta
--   Creada en 0005, sin alteraciones de columna.
create table if not exists ehs.meta (
    anio       smallint       not null,
    ambito_id  varchar(20)    not null,
    kpi_id     varchar(40)    not null,
    valor      numeric(18,4)  not null,
    fuente     varchar(120)   not null,
    -- el libro trae mas de un juego de metas y EHS no siempre ha confirmado
    -- cual manda: se cargan todas y se marca la vigente.
    vigente    boolean        not null constraint df_meta_vigente default false,
    constraint pk_meta primary key (anio, ambito_id, kpi_id, fuente),
    constraint fk_meta_kpi foreign key (kpi_id) references ref.dim_kpi (kpi_id)
    -- ambito_id NO tiene FK a ref.dim_sitio a proposito: incluye ambitos
    -- virtuales ('nacional_labs') que nunca tienen fila propia en dim_sitio.
);

-- ehs.scorecard_anual
--   Creada en 0005, sin alteraciones de columna.
create table if not exists ehs.scorecard_anual (
    anio           smallint       not null,
    sitio_id       varchar(20)    not null,
    kpi_id         varchar(40)    not null,
    -- NULL de verdad: una meta que no se publico no es una meta de cero.
    meta           numeric(18,4)  null,
    real_ytd       numeric(18,4)  null,
    premisa_anual  numeric(9,4)   null,
    fuente         varchar(120)   not null,
    constraint pk_scorecard primary key (anio, sitio_id, kpi_id),
    constraint fk_scorecard_sitio foreign key (sitio_id) references ref.dim_sitio (sitio_id),
    constraint fk_scorecard_kpi   foreign key (kpi_id)   references ref.dim_kpi (kpi_id)
);

-- ehs.aviso_confirmado
--   Creada en 0017, sin alteraciones de columna.
create table if not exists ehs.aviso_confirmado (
    fecha           date          not null,
    sitio_id        varchar(20)   not null,
    magnitud_id     varchar(40)   not null,
    codigo          varchar(40)   not null,
    confirmado_por  varchar(60)   not null,
    nota            varchar(300)  null,
    confirmado_en   timestamp(0)  not null constraint df_aviso_confirmado_cuando default localtimestamp(0),
    constraint pk_aviso_confirmado primary key (fecha, sitio_id, magnitud_id, codigo),
    constraint ck_aviso_confirmado_codigo check (codigo in ('salto_atipico')),
    constraint fk_aviso_confirmado_fecha
        foreign key (fecha)       references ref.dim_fecha (fecha),
    constraint fk_aviso_confirmado_sitio
        foreign key (sitio_id)    references ref.dim_sitio (sitio_id),
    constraint fk_aviso_confirmado_magnitud
        foreign key (magnitud_id) references ref.dim_magnitud (magnitud_id)
);

commit;

/* ============================================================================
   DE QUE MIGRACION SALE LA VERSION FINAL DE CADA TABLA

   ref.dim_sitio              0002 (create) + 0011 (add en_colombia_peru)
   ref.dim_fecha               0002 (create). 0010 solo agrega filas (2023-2035),
                                no cambia columnas.
   ref.dim_magnitud            0002 (create) + 0011 (add requerida_colombia)
                                + 0015 (add forma_residuo, check)
   ref.dim_kpi                 0002 (create). 0011 solo UPDATE de datos (formato).
   ref.kpi_magnitud            0002 (create)
   ops.carga_log                0003 (create)
   ops.lectura_rechazada        0003 (create)
   ops.migracion_aplicada       0003 (create)
   ehs.hecho_lectura_mensual    0004 (create) + 0009 (add motivo_correccion).
                                0014/0015/0021 solo tocan procedimientos/vistas
                                que la leen, no su forma. 0016 borra filas de
                                2023 (DELETE, no DDL). 0018/0019/0020 solo datos.
   ehs.hecho_lectura_mensual_hist 0004 (create) + 0009 (add motivo)
   ehs.hecho_lectura_diaria_agua  0004 (create)
   ehs.meta                     0005 (create)
   ehs.scorecard_anual          0005 (create). 0016 borra filas de 2023 (DELETE).
   ehs.aviso_confirmado          0017 (create)

   NO SON TABLAS Y QUEDAN FUERA DE ESTE ARCHIVO A PROPOSITO:
   - ehs.lote_lectura (0007): es un TABLE TYPE de SQL Server (parametro de
     sp_capturar_lote), no una tabla con datos propios. En Postgres el
     equivalente mas cercano es un tipo compuesto o simplemente pasar los
     valores como arrays/JSON al traducir el procedimiento — se decide al
     portar sp_capturar_lote, no aqui.
   - Vistas: ehs.v_ambito, ehs.v_lectura_ambito, ehs.v_kpi_mensual,
     ehs.v_kpi_ytd, ehs.v_kpi_contra_meta, ehs.v_calidad_dato,
     ehs.v_corte_publicado, ehs.v_calidad_avisos, ehs.v_agua_diaria,
     ehs.v_estado_agua_diaria, ehs.v_rechazo_pendiente, ehs.v_captura_estado,
     ehs.v_correcciones (0006/0009/0010/0011/0015/0021).
   - Triggers: ehs.tr_lectura_mensual_hist (0004, reescrito en 0009) y
     ehs.tr_lectura_mensual_residuo_una_forma (0015).
   - Procedimientos: ehs.sp_capturar_lote (0007, reescrito en 0014),
     ehs.sp_corregir_lectura (0009, reescrito en 0010), ehs.sp_confirmar_aviso (0017).
   - Roles/logins y sus GRANT (instalacion/crear-logins.sql, fuera de
     migraciones/): el modelo de minimo privilegio (regla 5) se replica con
     ROLES de Postgres (CREATE ROLE ehs_app; GRANT EXECUTE ON FUNCTION ... TO
     ehs_app; sin GRANT INSERT/UPDATE/DELETE directo sobre tablas) al portar
     esos tres procedimientos — no se intento aqui porque todavia no hay
     funciones/procedimientos Postgres a los que apuntar el EXECUTE.

   DUDAS REALES QUE NO PUDE RESOLVER LEYENDO SOLO LAS MIGRACIONES (no las
   invento; quedan para decidir antes de aplicar esto en Neon):

   1. DEFAULT de las columnas de hora (capturado_en, detectado_en, aplicada_en,
      confirmado_en, etc.): usan LOCALTIMESTAMP(0) como equivalente de
      sysdatetime(). En SQL Server esto daba la hora de pared de Colombia
      porque el SERVIDOR estaba en esa zona horaria (regla 6 del contexto).
      LOCALTIMESTAMP en Postgres devuelve la hora sin zona del `timezone` de
      la SESION/servidor — en Neon eso por defecto es UTC, no
      America/Bogota. Si no se fija `timezone = 'America/Bogota'` en la
      conexion (o en el rol de la app), estos defaults quedarian en hora UTC
      de pared, no en hora de Colombia, rompiendo la regla 6 en la practica
      aunque el TIPO de columna sea el correcto. En el codigo original los
      procedimientos de escritura (sp_capturar_lote, sp_corregir_lectura,
      sp_confirmar_aviso) siempre pasan la hora explicita y no dependen de
      este default salvo para un INSERT/UPDATE manual — pero sigue siendo una
      decision pendiente de confirmar con quien instale la base en Neon.

   2. DEFAULT de capturado_por/aplicada_por (CURRENT_USER): en SQL Server
      suser_sname() es el login de conexion. En Neon/Postgres el usuario de
      conexion normalmente seria el rol de servicio de la app (ehs_app), no
      una persona — exactamente la misma razon por la que sp_capturar_lote
      (migracion 0007) exige @capturado_por explicito en vez de confiar en
      este default. El default se preserva por fidelidad estructural, pero
      en la practica (igual que en SQL Server) nunca deberia ser lo que
      registra quien capturo algo via la app.

   3. ehs.tr_lectura_mensual_residuo_una_forma (migracion 0015) depende de
      ref.dim_magnitud.forma_residuo para saber que magnitudes son
      mutuamente excluyentes por sitio-mes. No hay ninguna tabla nueva que
      portar por esto (la columna ya esta en ref.dim_magnitud, arriba), pero
      al portar el trigger hay que decidir si Postgres lo implementa igual
      como AFTER INSERT OR UPDATE (mismo comportamiento) o si conviene una
      constraint de nivel mas bajo (EXCLUDE) — no se decide aqui sin ver los
      datos reales de produccion.

   4. No encontre ningun INDEX ni CHECK adicional sobre ehs.scorecard_anual o
      ehs.meta en ninguna migracion mas alla de 0005: si el area pidio algo
      mas (por ejemplo, un indice para la consulta de "Anual" por sitio) no
      quedo registrado en las migraciones y no lo inclui por no inventarlo.
   ============================================================================ */
