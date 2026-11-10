/* =============================================================================
   03_trigger_y_procedimientos.sql
   -----------------------------------------------------------------------------
   Porte a PL/pgSQL de:

     1. ehs.tr_lectura_mensual_hist   (trigger de historia)
     2. ehs.sp_capturar_lote          (la puerta de escritura para el mes completo)
     3. ehs.sp_corregir_lectura       (la puerta de escritura para UNA correccion)
     4. ehs.sp_confirmar_aviso        (la puerta de escritura para un aviso revisado)

   Fuente: C:\Users\samuel\EssilorLuxottica\ehs\entrega-reunion\app\migraciones\
   0001 a 0021 (SQL Server 2022). Para cada objeto se uso la version de la
   migracion MAS RECIENTE que lo redefine ('create or alter' / 'drop + create'
   son la misma cosa a efectos de "cual es la version vigente"). El detalle de
   que migracion dio la version final de cada objeto esta al final de este
   archivo, en un solo bloque de comentario.

   FUERA DE ALCANCE DE ESTE ARCHIVO (se asume que ya existen, portados en otros
   archivos del mismo porte a Postgres):
     - los esquemas ehs / ref / ops (CREATE SCHEMA) y sus tablas: en particular
       ehs.hecho_lectura_mensual, ehs.hecho_lectura_mensual_hist,
       ehs.aviso_confirmado, ops.carga_log, ops.lectura_rechazada,
       ref.dim_fecha, ref.dim_sitio, ref.dim_magnitud.
     - la restriccion unica uq_lectura_mensual (fecha, sitio_id, magnitud_id)
       sobre ehs.hecho_lectura_mensual y la llave primaria compuesta
       (fecha, sitio_id, magnitud_id, codigo) sobre ehs.aviso_confirmado: las
       tres rutinas de este archivo dependen de que existan (se usan como
       target de ON CONFLICT).
     - el rol ehs_app y su login/clave: se crean en un script de provision
       aparte (equivalente Postgres de instalacion/crear-logins.sql), nunca
       aqui. Este archivo solo le otorga (GRANT) lo minimo sobre los objetos
       que si crea.

   REGLAS DE NEGOCIO QUE ESTE ARCHIVO NO PUEDE ROMPER (ver CLAUDE.md del area,
   seccion "Tres reglas que no se negocian", y el encargo de esta tarea):
     1. YTD = suma de numeradores / suma de denominadores (no aplica a este
        archivo directamente: lo implementan las vistas, no el trigger ni los
        procedimientos; se menciona porque sp_capturar_lote/sp_corregir_lectura
        son la unica puerta hacia los datos que esas vistas despues agregan).
     2. Los agregados se construyen sumando magnitudes crudas (idem, en vistas).
     3. Un mes cuenta para un ambito solo si todos sus sitios lo reportaron
        (idem, en ehs.v_lectura_ambito, migracion 0021 - no vive en este archivo).
     4. El trigger de historia archiva SOLO si valor o estado cambiaron, nunca
        en cada UPDATE. Implementado abajo con IS DISTINCT FROM.
     5. Los 3 procedimientos son la UNICA puerta de escritura: ehs_app no tiene
        GRANT INSERT/UPDATE/DELETE directo sobre ninguna tabla, solo EXECUTE en
        estos 3. En Postgres esto se replica con SECURITY DEFINER (el
        equivalente al "ownership chaining" de SQL Server, donde el
        procedimiento corre con los privilegios del dueno del esquema, no con
        los del que lo llama) + REVOKE de PUBLIC + GRANT puntual a ehs_app.
     6. Las columnas de hora (capturado_en, modificado_en, reemplazado_en,
        confirmado_en) son TIMESTAMP SIN zona horaria: hora de pared de
        Colombia, no UTC. Por eso en todo este archivo se usa el tipo
        'timestamp' (nunca 'timestamptz') y clock_timestamp()::timestamp(0)
        como equivalente de sysdatetime(). ADVERTENCIA: clock_timestamp()
        devuelve timestamptz; el cast a timestamp lo convierte a la hora de
        pared de la ZONA DEL SESSION/SERVIDOR (parametro "timezone" de
        Postgres). Para que el resultado sea la hora de Colombia igual que en
        SQL Server, la base/el rol de conexion tiene que tener
        'timezone' = 'America/Bogota' (o equivalente) configurado - esto no lo
        puede garantizar este archivo por si solo, queda como nota para quien
        instale la base Postgres. Ver duda final.
     7. Ninguna clave se escribe aqui. Las dos rutinas de GRANT al final no
        necesitan clave (GRANT no la pide); la clave del rol ehs_app se crea en
        un script de provision aparte, con placeholder de variable (igual que
        instalacion/crear-logins.sql usa $(ClaveApp) con sqlcmd -v), nunca aqui.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   0. helpers de conversion "segura" (equivalentes de TRY_CONVERT)
   -----------------------------------------------------------------------------
   T-SQL tiene TRY_CONVERT como primitiva del motor: devuelve NULL si la
   conversion falla, en vez de lanzar un error. Postgres no tiene equivalente
   nativo, asi que sp_capturar_lote (que arma su tabla de "tipado" en un solo
   INSERT ... SELECT por fila, igual que el original) necesita estas dos
   funciones auxiliares. No existen en el T-SQL original porque alla no hacian
   falta; se agregan aqui porque sin ellas el porte del procedimiento no se
   puede escribir como un SELECT de conjunto (tendria que volverse un cursor
   fila por fila, que es exactamente lo que el diseno original evita). */

create or replace function ehs._try_convert_fecha(p_texto varchar(40))
returns date
language plpgsql
as $$
begin
    return p_texto::date;
exception
    when others then
        return null;
end;
$$;

create or replace function ehs._try_convert_valor(p_texto varchar(60))
returns numeric(18,4)
language plpgsql
as $$
begin
    return p_texto::numeric(18,4);
exception
    when others then
        return null;
end;
$$;


/* =============================================================================
   1. ehs.tr_lectura_mensual_hist
   -----------------------------------------------------------------------------
   Version vigente: migracion 0009 (la de 0004 quedo reemplazada: 0009 saca del
   trigger el UPDATE que pisaba modificado_por/modificado_en con suser_sname(),
   y agrega la columna 'motivo' a la fila de historia). 0012 y posteriores NO
   redefinen el trigger, solo lo usan (deshabilitado/habilitado) para cargas de
   datos puntuales - ver la nota de "disable/enable" mas abajo.

   AFTER UPDATE, FOR EACH ROW: compara OLD contra NEW y archiva solo si
   valor o estado cambiaron (regla de negocio 4). reemplazado_por lee
   NEW.modificado_por (lo que el PROPIO procedimiento que hizo el update ya
   puso ahi) y cae a session_user solo si un UPDATE directo por SQL no paso por
   ningun procedimiento y no dejo modificado_por - mismo papel que suser_sname()
   como respaldo en el original. ============================================= */

create or replace function ehs.tr_lectura_mensual_hist()
returns trigger
language plpgsql
as $$
begin
    if new.valor is distinct from old.valor or new.estado is distinct from old.estado then
        insert into ehs.hecho_lectura_mensual_hist
            (lectura_id, fecha, sitio_id, magnitud_id,
             valor_anterior, estado_anterior, reemplazado_por, reemplazado_en, motivo)
        values
            (old.lectura_id, old.fecha, old.sitio_id, old.magnitud_id,
             old.valor, old.estado,
             coalesce(new.modificado_por, session_user),
             clock_timestamp()::timestamp(0),
             new.motivo_correccion);
    end if;
    return new;
end;
$$;

/* En Postgres el nombre del trigger NO lleva prefijo de esquema (toma el
   esquema de la tabla a la que esta pegado); solo la funcion que ejecuta
   queda schema-calificada como ehs.tr_lectura_mensual_hist(). No es perdida de
   fidelidad, es como Postgres nombra los triggers. */
drop trigger if exists tr_lectura_mensual_hist on ehs.hecho_lectura_mensual;

create trigger tr_lectura_mensual_hist
after update on ehs.hecho_lectura_mensual
for each row
execute function ehs.tr_lectura_mensual_hist();

/* -----------------------------------------------------------------------------
   Nota de migraciones de DATOS (0018/0019), no de ESTRUCTURA: en SQL Server
   esas migraciones hacen

       disable trigger ehs.tr_lectura_mensual_hist on ehs.hecho_lectura_mensual;
       ... updates puntuales que no deben archivarse como correccion normal ...
       enable trigger ehs.tr_lectura_mensual_hist on ehs.hecho_lectura_mensual;

   dentro de una transaccion, para que un UPDATE que deja la base en el mismo
   estado que la instalacion de referencia no genere una fila de historia que
   alla no existe. El equivalente exacto en Postgres, para cuando se porten
   0018/0019 (no es parte de este archivo, que es solo estructura):

       alter table ehs.hecho_lectura_mensual disable trigger tr_lectura_mensual_hist;
       ... los mismos updates ...
       alter table ehs.hecho_lectura_mensual enable trigger tr_lectura_mensual_hist;

   igual, dentro de una transaccion (begin / ... / commit, con rollback si algo
   falla) para que el trigger quede garantizado de vuelta encendido. */


/* =============================================================================
   2. ehs.lote_lectura (tipo) + ehs.sp_capturar_lote
   -----------------------------------------------------------------------------
   El tipo es el equivalente del tipo de tabla (TVP) 'ehs.lote_lectura' de la
   migracion 0007: un lote es el mes completo de un sitio, se manda entero. En
   Postgres un parametro de procedimiento no puede ser "una tabla", pero si
   puede ser un ARRAY de un tipo compuesto - es la traduccion mas directa del
   mismo contrato (una fila por magnitud, todo texto, por la misma razon que en
   el original: una fila se puede rechazar justo porque su valor no era un
   numero, y un parametro ya tipado no podria transportarla para contar por que).

   Version vigente de sp_capturar_lote: migracion 0014 (redefine por completo a
   la de 0007; la unica diferencia real es que la condicion de advertencia por
   "por debajo del minimo" ya no excluye el cero con "and v.valor_num > 0" - ver
   el porque en el encabezado de 0014_ehs_advertencia_cero.sql). Se porto la
   version de 0014.

   FUNCTION vs PROCEDURE: PROCEDURE. Dos razones:
     a. El original necesita poder registrar en ops.carga_log que el lote
        FALLO (resultado = 'error', con el mensaje) incluso cuando el resto de
        la operacion se deshace por completo - en SQL Server eso funciona
        porque la fila de "inicio" se inserta en autocommit ANTES del
        'begin transaction', y el UPDATE que marca el error corre fuera de esa
        transaccion explicita (en su propio autocommit) justo antes del THROW.
        En Postgres eso exige control de transaccion explicito (COMMIT) en dos
        puntos (arrancar el log, y de nuevo si hay que marcarlo como error) -
        y COMMIT/ROLLBACK solo existen en PROCEDURE (o en un bloque DO), nunca
        en FUNCTION.
     b. Lo que el original devuelve no es un valor escalar tabular: son tres
        cosas distintas (el resumen, la lista de filas rechazadas con su
        motivo, la lista de advertencias) que la pantalla de captura tiene que
        poder distinguir de un vistazo - el propio comentario original lo dice
        explicitamente. En Postgres eso se expresa con parametros OUT (que al
        llamar con CALL vuelven como una sola fila de resultado): los conteos
        como enteros, y las dos listas como jsonb (un arreglo de objetos cada
        una) en vez de dos recordsets separados.
   ============================================================================= */

create type ehs.lote_lectura as (
    fecha_texto     varchar(40),
    sitio_texto     varchar(60),
    magnitud_texto  varchar(60),
    valor_texto     varchar(60)
);

/* HALLAZGO REAL, probado en vivo contra un Postgres 16 desechable antes de tocar
   cualquier cuenta real: un procedimiento SECURITY DEFINER NO PUEDE ejecutar COMMIT
   ni ROLLBACK, bajo ninguna circunstancia ("invalid transaction termination") —
   a diferencia de T-SQL, donde un procedimiento puede mezclar BEGIN TRAN/COMMIT con
   EXECUTE AS OWNER sin problema. El diseno original (una fila de "arranco" que
   sobrevive en la bitacora aunque todo lo demas se deshaga) dependia exactamente de
   eso: un COMMIT a mitad del procedimiento.

   La solucion correcta en Postgres no es "quitar el commit y perder la garantia" ni
   usar una extension (dblink/pg_background) para una transaccion autonoma — es
   partir la operacion en DOS llamadas de nivel superior, cada una su propia
   transaccion implicita que se confirma sola al terminar sin error, igual que
   cualquier sentencia CALL unica en modo autocommit:

     1. ehs.sp_iniciar_carga   — solo abre la fila en ops.carga_log y devuelve su id.
        Si el paso 2 revienta por completo, esta fila YA quedo confirmada por su
        cuenta: sigue sobreviviendo, que era el punto del diseno original.
     2. ehs.sp_capturar_lote   — recibe ese carga_id ya existente (en vez de crearlo)
        y hace el resto, SIN ningun COMMIT interno.

   Lo que se deja de tener, a conciencia: si sp_capturar_lote revienta por un error
   no previsto (el 'exception when others' interno ya atrapa los casos esperados),
   el UPDATE que marca esa fila como 'error' se deshace junto con todo lo demas — la
   fila de carga_log queda sin 'fin'/'resultado' en vez de con 'error' explicito. No
   se agrega una tercera llamada solo para cerrar ese caso raro con un tablero de
   trafico casi nulo (R.5.3.4 ya queda cubierto por la fila que SI sobrevive: queda
   registrado que alguien intento capturar y cuando). Si mas adelante se necesita esa
   garantia completa, la tercera llamada (ehs.sp_marcar_carga_fallida) es sencilla de
   agregar sin tocar nada de lo de aqui. */
create or replace procedure ehs.sp_iniciar_carga(
    in  p_capturado_por  varchar(60),
    out p_carga_id       bigint
)
language plpgsql
security definer
set search_path = ehs, ref, ops, pg_temp
as $$
begin
    if p_capturado_por is null or btrim(p_capturado_por) = '' then
        raise exception 'Falta capturado_por. La bitacora tiene que decir quien capturo (R.5.3.4).';
    end if;
    insert into ops.carga_log (proceso, inicio, ejecutado_por)
    values ('captura manual', clock_timestamp()::timestamp(0), p_capturado_por)
    returning carga_id into p_carga_id;
end;
$$;

create or replace procedure ehs.sp_capturar_lote(
    -- ORDEN REAL QUE EXIGE POSTGRES (probado en vivo contra un Postgres 16 desechable;
    -- ver la nota al final del archivo): un OUT no puede ir despues de un IN con
    -- valor por defecto, asi que los OUT van ENTRE los IN obligatorios y los IN con
    -- defecto — nunca todos al principio (eso rompe el CALL posicional: la primera
    -- version de este archivo tenia los 6 OUT al frente y NINGUNA llamada, ni
    -- posicional ni con nombre, lograba resolver el procedimiento).
    --
    -- CALL debe ser POSICIONAL y traer un valor para CADA parametro en este orden,
    -- incluidos los OUT (de relleno, se ignoran): Postgres no permite notacion con
    -- nombre (=>) en un CALL si el procedimiento tiene algun OUT — probado tambien,
    -- falla siempre con "procedure ... does not exist" aunque los nombres y tipos
    -- sean correctos. Ver adaptador de escritura (escritura_pg.js) para la forma
    -- exacta de la llamada.
    in  p_carga_id            bigint,
    in  p_lote                ehs.lote_lectura[],
    in  p_capturado_por       varchar(60),
    out p_grabadas            int,
    out p_rechazos            int,
    out p_pendientes          int,
    out p_rechazadas          jsonb,
    out p_advertencias        jsonb,
    in  p_origen              varchar(120) default 'formulario de captura EHS',
    in  p_confirmar_atipicos  boolean      default false
)
language plpgsql
security definer
set search_path = ehs, ref, ops, pg_temp
as $$
declare
    v_error_msg text := null;
begin
    /* -------------------------------------------------- @capturado_por obligatorio */
    if p_capturado_por is null or btrim(p_capturado_por) = '' then
        raise exception 'Falta capturado_por. La bitacora tiene que decir quien capturo (R.5.3.4).';
    end if;

    p_grabadas   := 0;
    p_rechazos   := 0;
    p_pendientes := 0;
    p_rechazadas   := '[]'::jsonb;
    p_advertencias := '[]'::jsonb;

    /* bloque "try": nada aqui puede hacer commit/rollback (Postgres no lo permite
       dentro de un bloque con manejador de excepcion) - por eso el commit/rollback
       de verdad pasa DESPUES, en el bloque exterior, segun si v_error_msg quedo
       puesto o no. */
    begin
        drop table if exists pg_temp.tipado;
        create temp table tipado (
            fecha_texto    varchar(40),
            sitio_texto    varchar(60),
            magnitud_texto varchar(60),
            valor_texto    varchar(60),
            fecha          date,
            sitio_id       varchar(20),
            magnitud_id    varchar(40),
            valor          numeric(18,4),
            motivo         varchar(200),
            advertencia    varchar(200)
        );

        /* ---------------------------------------------------------- 1. tipar */
        insert into tipado
        select l.fecha_texto, l.sitio_texto, l.magnitud_texto, l.valor_texto,
               f.valor_fecha, s.sitio_id, m.magnitud_id, v.valor_num,
               /* motivo: lo imposible. No entra nunca. */
               case
                 when l.valor_texto is null or btrim(l.valor_texto) = ''
                      then 'Celda vacia. Una celda vacia no es un cero (R.5.3.6): no se captura.'
                 when f.valor_fecha is null
                      then 'La fecha no es una fecha valida: ' || coalesce(l.fecha_texto, '(nula)')
                 when extract(day from f.valor_fecha) <> 1
                      then 'La lectura mensual se ancla al dia 1 del mes.'
                 when not exists (select 1 from ref.dim_fecha d where d.fecha = f.valor_fecha)
                      then 'El mes no existe en ref.dim_fecha: ' || to_char(f.valor_fecha, 'YYYY-MM-DD')
                 when s.sitio_id is null
                      then 'Sitio desconocido: ' || coalesce(l.sitio_texto, '(nulo)')
                 when m.magnitud_id is null
                      then 'Magnitud desconocida: ' || coalesce(l.magnitud_texto, '(nula)')
                 when v.valor_num is null
                      then 'El valor no es un numero: ' || coalesce(l.valor_texto, '(nulo)')
                 when v.valor_num < 0
                      then 'Valor negativo. Ninguna de las nueve magnitudes puede serlo.'
                 else null
               end,
               /* advertencia: lo improbable. Entra solo si quien captura lo sostiene.
                  Version 0014: sin "and v.valor_num > 0" en la rama del minimo. */
               case
                 when v.valor_num is null then null
                 when m.valor_max is not null and v.valor_num > m.valor_max
                      then 'Supera el maximo historico de ' || m.magnitud_id || ' con holgura ('
                           || m.valor_max::numeric(18,1)::varchar(40)
                           || '). Confirma que es correcto.'
                 when m.valor_min is not null and v.valor_num < m.valor_min
                      then 'Queda por debajo del minimo historico de ' || m.magnitud_id || ' ('
                           || m.valor_min::numeric(18,1)::varchar(40)
                           || '). Confirma que es correcto.'
                 else null
               end
        from unnest(p_lote) as l
        cross join lateral (select ehs._try_convert_fecha(l.fecha_texto) as valor_fecha) f
        cross join lateral (select ehs._try_convert_valor(l.valor_texto) as valor_num) v
        left join ref.dim_sitio    s on s.sitio_id    = l.sitio_texto and s.activo = true
        left join ref.dim_magnitud m on m.magnitud_id = l.magnitud_texto;

        /* ------------------------------------------------------- 2. apartar */
        insert into ops.lectura_rechazada
            (carga_id, fecha_texto, sitio_texto, magnitud_texto, valor_texto,
             fila_cruda, motivo, origen)
        select p_carga_id, t.fecha_texto, t.sitio_texto, t.magnitud_texto, t.valor_texto,
               jsonb_build_object(
                   'fecha',     coalesce(t.fecha_texto, ''),
                   'sitio',     coalesce(t.sitio_texto, ''),
                   'magnitud',  coalesce(t.magnitud_texto, ''),
                   'valor',     coalesce(t.valor_texto, '')
               )::text,
               t.motivo, p_origen
        from tipado t
        where t.motivo is not null;

        get diagnostics p_rechazos = row_count;

        /* --------------------------------------------------------- 3. grabar */
        /* Equivalente del MERGE original: INSERT ... ON CONFLICT, con la MISMA
           condicion 'and d.valor <> s.valor' puesta como WHERE del DO UPDATE -
           sin eso, reenviar un lote identico archivaria en la historia filas
           que no cambian nada (misma razon que en el original). */
        insert into ehs.hecho_lectura_mensual
            (fecha, sitio_id, magnitud_id, valor, origen, estado, capturado_por, capturado_en)
        select t.fecha, t.sitio_id, t.magnitud_id, t.valor,
               case when t.advertencia is null then p_origen
                    else p_origen || ' [atipico confirmado]' end,
               'capturado', p_capturado_por, clock_timestamp()::timestamp(0)
        from tipado t
        where t.motivo is null
          and (t.advertencia is null or p_confirmar_atipicos)
        on conflict (fecha, sitio_id, magnitud_id) do update
           set valor          = excluded.valor,
               estado         = 'corregido',
               origen         = excluded.origen,
               modificado_por = p_capturado_por,
               modificado_en  = clock_timestamp()::timestamp(0)
         where ehs.hecho_lectura_mensual.valor <> excluded.valor;

        get diagnostics p_grabadas = row_count;

        select count(*) into p_pendientes
          from tipado
         where motivo is null and advertencia is not null and not p_confirmar_atipicos;

        select coalesce(jsonb_agg(jsonb_build_object(
                   'sitio', t.sitio_texto, 'magnitud', t.magnitud_texto,
                   'valor', t.valor_texto, 'motivo', t.motivo)), '[]'::jsonb)
          into p_rechazadas
          from tipado t
         where t.motivo is not null;

        select coalesce(jsonb_agg(jsonb_build_object(
                   'sitio', t.sitio_texto, 'magnitud', t.magnitud_texto,
                   'valor', t.valor_texto, 'advertencia', t.advertencia)), '[]'::jsonb)
          into p_advertencias
          from tipado t
         where t.motivo is null and t.advertencia is not null;

        drop table tipado;
    exception
        when others then
            v_error_msg := sqlerrm;
    end;

    if v_error_msg is not null then
        -- Este UPDATE se deshace junto con el RAISE (no hay commit aqui: SECURITY
        -- DEFINER no lo permite, ver la nota junto a sp_iniciar_carga). La fila de
        -- sp_iniciar_carga YA esta confirmada por su cuenta y sigue sobreviviendo.
        update ops.carga_log
           set fin = clock_timestamp()::timestamp(0), resultado = 'error',
               detalle = left(v_error_msg, 400)
         where carga_id = p_carga_id;
        raise exception '%', v_error_msg;
    end if;

    update ops.carga_log
       set fin = clock_timestamp()::timestamp(0), filas = p_grabadas, rechazos = p_rechazos,
           resultado = 'ok',
           detalle = concat(p_grabadas, ' grabadas, ', p_rechazos, ' apartadas, ',
                            p_pendientes, ' esperando confirmacion')
     where carga_id = p_carga_id;
    -- sin commit: esta es la ultima sentencia, el CALL se confirma solo al volver.
end;
$$;


/* =============================================================================
   3. ehs.sp_corregir_lectura
   -----------------------------------------------------------------------------
   Version vigente: migracion 0010 (redefine a la de 0009: la unica diferencia
   es que 'origen' se recorta con LEFT(..., 120) antes de escribirse, porque es
   varchar(120) y un motivo largo lo desbordaba - ver el punto 2 del encabezado
   de 0010_ehs_consistencia.sql). Se porto la version de 0010.

   FUNCTION vs PROCEDURE: PROCEDURE. No hay nada tabular que devolver mas alla
   de un resumen de una sola fila (cuantas filas corrigio, y los mismos datos de
   entrada de vuelta) - igual que el 'select filas_corregidas = @@rowcount' del
   original. Se expresa como un solo parametro OUT entero; fecha/sitio_id/
   magnitud_id/valor_nuevo el que llama ya los tiene, porque son los mismos que
   mando. No necesita COMMIT intermedio como sp_capturar_lote porque aqui no hay
   ninguna bitacora que deba sobrevivir a un error: si falla, no queda nada que
   conservar y el rollback automatico de la transaccion de nivel superior (la
   del propio CALL) ya hace exactamente lo que el 'rollback transaction' del
   original hacia. */

create or replace procedure ehs.sp_corregir_lectura(
    in  p_fecha            date,
    in  p_sitio_id         varchar(20),
    in  p_magnitud_id      varchar(40),
    in  p_valor_nuevo      numeric(18,4),
    in  p_motivo           varchar(300),
    in  p_corregido_por    varchar(60),
    out p_filas_corregidas int
)
language plpgsql
security definer
set search_path = ehs, ref, ops, pg_temp
as $$
begin
    if p_corregido_por is null or btrim(p_corregido_por) = '' then
        raise exception 'Falta corregido_por. Igual que al capturar (R.5.3.4), la correccion tiene que decir quien la hizo.';
    end if;

    /* Un motivo de una palabra no es un motivo: 10 caracteres es el piso mas
       bajo que ya obliga a escribir algo con sentido. */
    if p_motivo is null or length(btrim(p_motivo)) < 10 then
        raise exception 'El motivo de la correccion tiene que explicar algo, no solo llenar el campo (minimo 10 caracteres).';
    end if;

    if p_valor_nuevo < 0 then
        raise exception 'Valor negativo. Ninguna de las nueve magnitudes puede serlo.';
    end if;

    if not exists (
        select 1 from ehs.hecho_lectura_mensual
         where fecha = p_fecha and sitio_id = p_sitio_id and magnitud_id = p_magnitud_id
    ) then
        raise exception 'Esa lectura no existe todavia. Se captura, no se corrige.';
    end if;

    update ehs.hecho_lectura_mensual
       set valor              = p_valor_nuevo,
           estado             = 'corregido',
           motivo_correccion  = p_motivo,
           /* origen es varchar(120): el motivo completo ya queda en
              motivo_correccion y en la historia; aqui solo el comienzo. */
           origen             = left('correccion manual: ' || p_motivo, 120),
           modificado_por     = p_corregido_por,
           modificado_en      = clock_timestamp()::timestamp(0)
     where fecha = p_fecha and sitio_id = p_sitio_id and magnitud_id = p_magnitud_id
       /* sin cambio real no hay correccion que archivar. */
       and valor <> p_valor_nuevo;

    get diagnostics p_filas_corregidas = row_count;
    -- sin commit: SECURITY DEFINER no lo permite, y esta ya es la ultima sentencia.
end;
$$;


/* =============================================================================
   4. ehs.sp_confirmar_aviso
   -----------------------------------------------------------------------------
   Version vigente: migracion 0017 (es la unica que lo define; 0018/0019 solo lo
   USAN - insertan filas en ehs.aviso_confirmado para una instalacion nueva -
   nunca lo redefinen). Se porto la version de 0017 tal cual.

   FUNCTION vs PROCEDURE: PROCEDURE, por la misma razon que sp_corregir_lectura:
   un solo resultado escalar ('select filas_confirmadas = @@rowcount'), ningun
   resultado tabular que una FUNCTION devolveria mejor. */

create or replace procedure ehs.sp_confirmar_aviso(
    -- Mismo orden real que sp_capturar_lote (ver su comentario): el OUT va entre
    -- los IN obligatorios y el IN con defecto (p_nota), nunca antes de todos.
    in  p_fecha              date,
    in  p_sitio_id           varchar(20),
    in  p_magnitud_id        varchar(40),
    in  p_codigo             varchar(40),
    in  p_confirmado_por     varchar(60),
    out p_filas_confirmadas  int,
    in  p_nota               varchar(300) default null
)
language plpgsql
security definer
set search_path = ehs, ref, ops, pg_temp
as $$
begin
    if p_codigo <> 'salto_atipico' then
        raise exception 'Solo se confirman avisos de salto atipico. Un valor negativo, un denominador en cero o un mes incompleto no se confirma: se corrige, con "Consultar y corregir".';
    end if;

    if p_confirmado_por is null or btrim(p_confirmado_por) = '' then
        raise exception 'Falta quien confirma. La bitacora tiene que poder nombrarlo.';
    end if;

    if not exists (
        select 1 from ehs.hecho_lectura_mensual
         where fecha = p_fecha and sitio_id = p_sitio_id and magnitud_id = p_magnitud_id
    ) then
        raise exception 'No existe esa lectura: no hay nada que confirmar.';
    end if;

    /* idempotente: confirmar de nuevo el mismo aviso actualiza quien/cuando/nota
       en vez de duplicar o fallar por la llave primaria - mismo comportamiento
       que el MERGE original. */
    insert into ehs.aviso_confirmado (fecha, sitio_id, magnitud_id, codigo, confirmado_por, nota, confirmado_en)
    values (p_fecha, p_sitio_id, p_magnitud_id, p_codigo, p_confirmado_por, p_nota, clock_timestamp()::timestamp(0))
    on conflict (fecha, sitio_id, magnitud_id, codigo) do update
       set confirmado_por = excluded.confirmado_por,
           nota           = excluded.nota,
           confirmado_en  = excluded.confirmado_en;

    get diagnostics p_filas_confirmadas = row_count;
    -- sin commit: SECURITY DEFINER no lo permite, y esta ya es la ultima sentencia.
end;
$$;


/* =============================================================================
   5. privilegio minimo (regla de negocio 5), con ROLES de Postgres
   -----------------------------------------------------------------------------
   Equivalente de instalacion/crear-logins.sql (que NO se porta en este
   archivo: la creacion del rol ehs_app y su clave pertenece a un script de
   provision aparte, con la clave pasada por variable, nunca literal - regla 7).
   Esto asume que el rol ehs_app ya existe para cuando este archivo se aplique.

   Postgres otorga EXECUTE sobre toda funcion/procedimiento/tipo NUEVO a PUBLIC
   por default - justo lo que ownership chaining + GRANT puntual evita en SQL
   Server. Por eso el REVOKE explicito de abajo no es opcional ni paranoia: sin
   el, cualquier rol con permiso de conexion a la base podria ejecutar estos
   tres procedimientos, aunque no se le haya otorgado nada. */

-- Firmas exactas confirmadas en vivo (select oid::regprocedure from pg_proc ...):
-- Postgres identifica un procedimiento solo por sus tipos IN, en orden — los OUT no
-- cuentan para esto, por eso la lista de abajo es mas corta que los parametros reales.
revoke all on procedure ehs.sp_iniciar_carga(
    varchar(60)
) from public;
revoke all on procedure ehs.sp_capturar_lote(
    bigint, ehs.lote_lectura[], varchar(60), varchar(120), boolean
) from public;
revoke all on procedure ehs.sp_corregir_lectura(
    date, varchar(20), varchar(40), numeric(18,4), varchar(300), varchar(60)
) from public;
revoke all on procedure ehs.sp_confirmar_aviso(
    date, varchar(20), varchar(40), varchar(40), varchar(60), varchar(300)
) from public;
revoke all on type ehs.lote_lectura from public;

/* Descomentar cuando el rol ehs_app ya exista en esta base (lo crea el script
   de provision, no este archivo):

   grant usage on type ehs.lote_lectura to ehs_app;
   grant execute on procedure ehs.sp_capturar_lote(
       ehs.lote_lectura[], varchar(60), varchar(120), boolean
   ) to ehs_app;
   grant execute on procedure ehs.sp_corregir_lectura(
       date, varchar(20), varchar(40), numeric(18,4), varchar(300), varchar(60)
   ) to ehs_app;
   grant execute on procedure ehs.sp_confirmar_aviso(
       date, varchar(20), varchar(40), varchar(40), varchar(60), varchar(300)
   ) to ehs_app;

   ehs_app NO necesita (y no debe recibir) INSERT/UPDATE/DELETE directo sobre
   ehs.hecho_lectura_mensual, ehs.hecho_lectura_mensual_hist, ehs.aviso_confirmado,
   ops.carga_log ni ops.lectura_rechazada: SECURITY DEFINER en los tres
   procedimientos hace que corran con los privilegios de quien los creo (el
   rol migrador/owner del esquema), no con los de ehs_app - el mismo papel que
   el ownership chaining de dbo cumple en SQL Server. */


/* =============================================================================
   PROVENIENCIA DE CADA OBJETO (migracion de la que se tomo la version final)
   -----------------------------------------------------------------------------
   ehs.tr_lectura_mensual_hist  -> 0009_ehs_correccion.sql (reemplaza a 0004;
                                    0012/0018/0019 solo lo mencionan o lo
                                    deshabilitan temporalmente, no lo redefinen)
   ehs.lote_lectura (tipo)      -> 0007_ehs_ingesta.sql (sin cambios despues)
   ehs.sp_capturar_lote         -> 0014_ehs_advertencia_cero.sql (reemplaza a 0007)
   ehs.sp_corregir_lectura      -> 0010_ehs_consistencia.sql (reemplaza a 0009)
   ehs.sp_confirmar_aviso       -> 0017_ehs_avisos_confirmados.sql (unica version)

   Revisadas y descartadas por no ser ninguno de los 7 objetos pedidos:
   ehs.tr_lectura_mensual_residuo_una_forma (0015, un trigger DISTINTO, sobre
   otra regla - "residuo desglosado o total, nunca las dos cosas" - no es
   tr_lectura_mensual_hist y no estaba en el encargo).

   DUDAS REALES SIN RESOLVER:
   1. El parametro de tipo tabla (TVP) se tradujo como ARRAY de un tipo
      COMPUESTO (ehs.lote_lectura[]) en vez de, por ejemplo, un parametro
      jsonb. Es la traduccion mas directa del contrato original, pero conviene
      confirmar que el driver de Postgres que use la app en Node (reemplazo de
      'mssql') pueda serializar un arreglo de tipo compuesto sin friccion -
      si no, jsonb con un CAST interno a esta misma tabla temporal 'tipado'
      seria la alternativa, sin cambiar nada de la logica de negocio de este
      archivo.
   2. La "fila de resultado" de sp_capturar_lote quedo como 6 parametros OUT
      (2 jsonb para las listas) en vez de los 3 resultsets separados que el
      driver 'mssql' leia como recordsets independientes. Falta confirmar que
      el codigo de la aplicacion (fuera del alcance de esta tarea) se adapte a
      leer una sola fila con esas 6 columnas en vez de 3 recordsets.
   3. clock_timestamp()::timestamp depende de que el 'timezone' de la sesion/
      base Postgres este fijado a America/Bogota para seguir siendo hora de
      pared de Colombia (regla 6). Falta confirmar que la base Neon (o el
      servidor Postgres de destino) se configure con ese timezone de sesion
      por default - de lo contrario estos tres procedimientos (y el trigger)
      quedarian escribiendo la hora de pared del timezone que tenga la sesion,
      no necesariamente la de Colombia, aunque la COLUMNA siga siendo
      'timestamp' (sin zona) como pide la regla.
   4. No existe en este archivo (esta fuera de su alcance) la version Postgres
      de ops.carga_log, ops.lectura_rechazada, ehs.hecho_lectura_mensual,
      ehs.hecho_lectura_mensual_hist ni ehs.aviso_confirmado: este archivo
      asume que ya fueron portadas con los mismos nombres de columna que aqui
      se referencian. Si esas tablas quedan con otro nombre de columna, los
      tres procedimientos y el trigger no van a compilar.
   ============================================================================= */
