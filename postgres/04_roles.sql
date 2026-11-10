/* =============================================================================
   04_roles.sql — provision de los dos ROLES de Postgres para EHS
   -----------------------------------------------------------------------------
   Puerto de instalacion/crear-logins.sql (SQL Server) a Postgres/Neon. Misma
   intencion: dos identidades, una para migrar/crear objetos y otra de minimo
   privilegio para la app en ejecucion (R.4.1 del estandar: quien implementa el
   esquema no es quien lo despliega en ejecucion normal).

     ehs_migrador  equivalente a db_owner de 'analitica' en el original: DDL +
                   lectura/escritura + capacidad de otorgar permisos sobre lo
                   que crea, para que instalacion/actualizar.ps1 (o el proceso
                   que lo reemplace en Postgres) pueda aplicar una migracion
                   nueva y completar sus GRANT sin volver a pedir una clave de
                   superusuario cada vez. Solo lo usan el proceso de migracion
                   y de instalacion, nunca la app en ejecucion.
     ehs_app       equivalente a db_datareader + EXECUTE puntual del original:
                   SELECT en ehs/ref/ops (todo el dato es de lectura publica
                   dentro de la app — ver crear-logins.sql original) y EXECUTE
                   SOLO en los 3 procedimientos de escritura
                   (ehs.sp_capturar_lote, ehs.sp_corregir_lectura,
                   ehs.sp_confirmar_aviso). SIN GRANT INSERT/UPDATE/DELETE
                   directo sobre ninguna tabla — ese es el nucleo de seguridad
                   del diseno (regla 5 del contexto EHS) y este script no lo
                   relaja "por simplicidad".

   Que SI cambia respecto al original (ver el comentario de cierre al final del
   archivo para el resumen corto y las dudas reales sin resolver):

     - "LOGIN de servidor" (SQL Server) se traduce a "ROLE ... LOGIN" de
       Postgres. Postgres no distingue login-de-servidor vs usuario-de-base:
       un ROLE con LOGIN es, a la vez, la identidad de conexion Y el titular
       de permisos sobre los objetos de la base a la que se conecte — no hace
       falta el paso separado "create user ... for login ..." del original.
     - db_owner/db_datareader (roles FIJOS de SQL Server, ligados a una base
       en particular) no existen en Postgres. Se reconstruye el mismo efecto
       con GRANT explicito sobre la base de datos y los 3 esquemas, mas
       ALTER DEFAULT PRIVILEGES para que las tablas que una migracion futura
       cree bajo ehs_migrador queden legibles por ehs_app sin un GRANT nuevo
       a mano (el mismo problema que el original resuelve haciendo a
       ehs_migrador db_owner).

   Uso (psql; el instalador genera las claves, nunca las escribe a mano, igual
   que el original con sqlcmd -v). Se asume conectado YA a la base de destino
   (p. ej. 'analitica' en el string de conexion de Neon) porque las claves de
   Postgres son del CLUSTER/proyecto Neon completo, pero los GRANT de este
   script se aplican a la base a la que esta conectado psql en ese momento:

     psql "$NEON_CONNECTION_STRING" `
          -v clave_migrador="<clave generada, 20+ caracteres>" `
          -v clave_app="<clave generada, 20+ caracteres>" `
          -f postgres\04_roles.sql

   Las dos claves resultantes las escribe el instalador en config\ehs.env
   (igual que SQL_MIGRADOR_CLAVE / SQL_CLAVE en el original) — nunca en este
   archivo, nunca en el repositorio.

   Idempotente: se puede correr de nuevo sin romper nada (CREATE ROLE y los
   GRANT de esquema/tabla estan guardados con existencia; los GRANT puntuales
   sobre los 3 procedimientos y el tipo de tabla avisan en vez de fallar si el
   objeto todavia no existe, igual que el original). A diferencia del SQL
   Server original, este archivo numerado 04 corre DESPUES de los que crean
   esquemas/tablas/vistas/procedimientos (01-03 en esta carpeta): por eso no
   deberia necesitar la "segunda pasada" que crear-logins.sql si necesitaba
   (ver el comentario de cierre).
   ============================================================================= */

/* ------------------------------------------------- las claves son obligatorias --- */

/* Igual que el original NO declara un :setvar por defecto para que sqlcmd
   rechace la corrida si falta -v: aqui, si -v clave_migrador/clave_app no se
   pasaron, se corta ANTES de tocar el servidor en vez de crear un rol con
   clave vacia o con el texto literal ":'clave_migrador'" sin interpolar. */
\set ON_ERROR_STOP on

\if :{?clave_migrador}
\else
  \echo 'ERROR: falta -v clave_migrador=<clave>. No se crea ningun rol. Ver encabezado de 04_roles.sql.'
  \quit
\endif

\if :{?clave_app}
\else
  \echo 'ERROR: falta -v clave_app=<clave>. No se crea ningun rol. Ver encabezado de 04_roles.sql.'
  \quit
\endif

/* --------------------------------------------------------- rol ehs_migrador --- */

/* CREATE ROLE no admite IF NOT EXISTS en Postgres (a diferencia de CREATE
   TABLE/SCHEMA) y la clave no puede viajar como literal fuera de una cadena
   dinamica si queremos reusar el mismo bloque para crear o, si ya existe,
   no tocarlo — por eso EXECUTE + format(), igual de guardado que el
   "if not exists ... begin create login ... end" del original. %L deja que
   format() escape la clave con las reglas de un literal SQL (comillas
   simples incluidas), que es ademas lo mismo que psql ya hace al interpolar
   :'clave_migrador' como texto antes de que esta linea llegue al servidor.

   HALLAZGO DE LA PRUEBA LOCAL (ver bitacora): lo de arriba es cierto fuera de un
   bloque dolar-comillado, pero DENTRO de uno (do $$ ... $$) psql NO interpola
   :'variable' — es a proposito, para que el cuerpo de una funcion/bloque PL/pgSQL
   pueda contener literalmente un caracter ':' sin que psql lo confunda con su
   propia sintaxis. El EXECUTE format(..., :'clave_migrador') de mas abajo llegaba
   al servidor con el texto ":'clave_migrador'" sin sustituir, y Postgres fallaba
   con "syntax error at or near ':'". Se evita el bloque DO por completo: se arma
   el DDL como texto en una variable psql (\gset, que SI interpola fuera de un
   $$) y se ejecuta esa variable como sentencia aparte. */
select exists(select 1 from pg_roles where rolname = 'ehs_migrador') as ya_existe_migrador \gset
\if :ya_existe_migrador
  \echo 'Rol ehs_migrador ya existia, no se toca su clave.'
\else
  select format('create role ehs_migrador with login password %L', :'clave_migrador') as _ddl_migrador \gset
  :_ddl_migrador;
  \echo 'Rol ehs_migrador creado.'
\endif

/* --------------------------------------------------------------- rol ehs_app --- */

select exists(select 1 from pg_roles where rolname = 'ehs_app') as ya_existe_app \gset
\if :ya_existe_app
  \echo 'Rol ehs_app ya existia, no se toca su clave.'
\else
  select format('create role ehs_app with login password %L', :'clave_app') as _ddl_app \gset
  :_ddl_app;
  \echo 'Rol ehs_app creado.'
\endif

/* ------------------------------------------- endurecimiento del schema public --- */

/* Buena practica de Postgres (no existe un equivalente en el original porque
   SQL Server no tiene un esquema 'public' compartido por defecto con CREATE
   abierto): por defecto CUALQUIER rol puede crear objetos en 'public' y
   conectarse a la base. Como todo EHS vive en ehs/ref/ops (regla del
   contexto: no aplanar a un solo esquema), 'public' no deberia usarse nunca
   aqui — se le quita CREATE a PUBLIC y se cierra CONNECT a PUBLIC para que
   solo los roles con GRANT explicito (ehs_migrador, ehs_app, y el rol de
   administracion de Neon) puedan conectarse. Esto es ademas la mitigacion
   recomendada para el problema de "schema shadowing" de search_path
   (CVE-2018-1058): con 'public' sin CREATE abierto, nadie mas puede plantar
   un objeto que un search_path confiado resuelva antes que el de ehs/ref/ops. */
revoke create on schema public from public;

/* GRANT/REVOKE ... ON DATABASE exige un identificador, no una llamada a
   funcion: current_database() no se puede escribir directo despues de "on
   database" (error de sintaxis). Se resuelve con SQL dinamico, tomando el
   nombre de la base a la que psql esta conectado en este momento — asi el
   script no depende de que el nombre sea literalmente 'analitica' y sirve
   igual si Neon la llama distinto. */
do $$
begin
    execute format('revoke connect on database %I from public', current_database());
end
$$;

/* ------------------------------------------------------------- ehs_migrador --- */

/* Equivalente de "alter role db_owner add member ehs_migrador" del original,
   pero database-scoped en vez de via un rol fijo: CREATE para poder crear los
   esquemas ehs/ref/ops y sus objetos (las migraciones 01-03 corren como este
   rol), CONNECT/TEMPORARY para operar con normalidad. Al ser quien CREA cada
   esquema y cada objeto, Postgres lo deja automaticamente como propietario
   (ownership), y un propietario puede otorgar permisos sobre lo suyo sin
   necesitar WITH GRANT OPTION ni volver a pedir una clave mas alta — el mismo
   motivo por el que el original elige db_owner en vez de una coleccion de
   roles mas angostos (ver crear-logins.sql, bloque de "roles"). */
do $$
begin
    execute format(
        'grant connect, create, temporary on database %I to ehs_migrador',
        current_database()
    );
end
$$;

/* -------------------------------------------------------------------- ehs_app --- */

/* Equivalente de "alter role db_datareader add member ehs_app": lectura en
   TODO lo que hay bajo ehs/ref/ops (coincide con el comentario del original,
   "todo el dato es de lectura publica dentro de la app"). Se guarda con
   existencia del esquema porque, a diferencia de un rol fijo de SQL Server
   (que aplica a la base entera sin importar que exista todavia o no), un
   GRANT sobre un esquema puntual de Postgres SI exige que el esquema ya este
   creado. */
do $$
begin
    execute format('grant connect on database %I to ehs_app', current_database());
end
$$;

do $$
declare
    nombre_esquema text;
begin
    foreach nombre_esquema in array array['ehs', 'ref', 'ops'] loop
        if exists (select 1 from pg_namespace where nspname = nombre_esquema) then
            execute format('grant usage on schema %I to ehs_app', nombre_esquema);
            execute format('grant select on all tables in schema %I to ehs_app', nombre_esquema);
        else
            raise notice 'Aviso: esquema % todavia no existe. Volver a correr este script '
                'despues de aplicar las migraciones de esquema/tablas para completar el '
                'SELECT de ehs_app.', nombre_esquema;
        end if;
    end loop;
end
$$;

/* Para que una tabla NUEVA que una migracion futura cree (corriendo como
   ehs_migrador) quede legible por ehs_app sin un GRANT manual adicional —
   el equivalente exacto a por que db_datareader es comodo en el original:
   cubre tablas que todavia no existen el dia que se otorga el permiso. Solo
   cubre TABLAS/VISTAS (no funciones/procedimientos): la puerta de escritura
   sigue siendo manual y explicita por objeto, a proposito, para que un
   procedimiento nuevo NO quede ejecutable por ehs_app hasta que alguien lo
   decida (ver el bloque de los 3 procedimientos mas abajo). */
do $$
declare
    nombre_esquema text;
begin
    foreach nombre_esquema in array array['ehs', 'ref', 'ops'] loop
        if exists (select 1 from pg_namespace where nspname = nombre_esquema) then
            execute format(
                'alter default privileges for role ehs_migrador in schema %I grant select on tables to ehs_app',
                nombre_esquema
            );
        end if;
    end loop;
end
$$;

/* search_path explicito para los dos roles: ademas de comodidad (evita tener
   que calificar ehs./ref./ops. en cada sentencia que no lo haga ya), es la
   otra mitad recomendada de la mitigacion de CVE-2018-1058 junto con el
   revoke de 'public' de arriba — ningun rol de esta app depende de que
   'public' aparezca primero en su search_path. */
alter role ehs_migrador set search_path = ehs, ref, ops;
alter role ehs_app set search_path = ehs, ref, ops;

/* CRITICO, hallado en la revision cruzada de este porte: clock_timestamp()::timestamp
   (el equivalente de sysdatetime() en el trigger de historia y en los 3 procedimientos
   de escritura) solo da hora de pared de Colombia si la SESION tiene esa zona horaria.
   Neon usa UTC por defecto. Sin esto, el TIPO de columna (timestamp sin zona, regla 6
   de ehs/CLAUDE.md) seria correcto pero el VALOR grabado en CADA fila que la app
   escriba estaria en UTC, no en hora de pared de Colombia — exactamente lo que la
   regla 6 prohibe. Equivalente al TZ=America/Bogota que ya trae el contenedor de
   SQL Server (ver instalar.ps1, 'docker run ... -e "TZ=America/Bogota"'). */
alter role ehs_migrador set timezone = 'America/Bogota';
alter role ehs_app set timezone = 'America/Bogota';

/* ------------------------------------- las 3 puertas de escritura de ehs_app --- */

/* Regla 5 del contexto EHS, el nucleo de seguridad del diseno: ehs_app NUNCA
   recibe INSERT/UPDATE/DELETE directo sobre ninguna tabla. Las 3 unicas
   puertas de escritura son EXECUTE en estos procedimientos. Igual que el
   original (object_id(...) is not null), cada bloque se guarda por si este
   script corre antes de que el procedimiento exista todavia: avisa, no
   falla. GRANT EXECUTE ON PROCEDURE sin lista de parametros funciona en
   Postgres mientras el nombre no este sobrecargado (no hay dos versiones de
   sp_capturar_lote con distinta firma) — si una migracion futura lo
   sobrecarga, este GRANT hay que calificarlo con la firma exacta. */
/* sp_iniciar_carga es el primero de los dos pasos de la captura (ver la nota junto a
   su CREATE en 03_trigger_y_procedimientos.sql: SECURITY DEFINER no admite COMMIT, asi
   que la fila de la bitacora que debe sobrevivir sola se abrio en su propia llamada). */
do $$
begin
    if exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'ehs' and p.proname = 'sp_iniciar_carga' and p.prokind = 'p'
    ) then
        execute 'grant execute on procedure ehs.sp_iniciar_carga to ehs_app';
    else
        raise notice 'Aviso: ehs.sp_iniciar_carga todavia no existe. Volver a correr este '
            'script despues de crearlo para completar el permiso de ehs_app.';
    end if;
end
$$;

do $$
begin
    if exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'ehs' and p.proname = 'sp_capturar_lote' and p.prokind = 'p'
    ) then
        execute 'grant execute on procedure ehs.sp_capturar_lote to ehs_app';
    else
        raise notice 'Aviso: ehs.sp_capturar_lote todavia no existe. Volver a correr este '
            'script despues de crearlo para completar el permiso de ehs_app.';
    end if;
end
$$;

/* Tipo de tabla (table-valued parameter) que sp_capturar_lote recibe como
   lote en el original (ehs.lote_lectura). Si la version portada a Postgres
   sigue representando el lote como un tipo compuesto (en vez de, por
   ejemplo, jsonb o un arreglo de una fila de columnas sueltas), Postgres
   exige el mismo tipo de permiso separado que SQL Server: USAGE sobre el
   TYPE, independiente del EXECUTE sobre el procedimiento — el mismo
   descubrimiento que el original documenta haber hecho probando con ehs_app
   real y no con el login de instalacion. Si la version portada NO usa un
   tipo compuesto para esto, este bloque simplemente nunca encuentra el tipo
   y solo avisa; no hace falta borrarlo a mano. */
do $$
begin
    if exists (
        select 1 from pg_type t
        join pg_namespace n on n.oid = t.typnamespace
        where n.nspname = 'ehs' and t.typname = 'lote_lectura'
    ) then
        execute 'grant usage on type ehs.lote_lectura to ehs_app';
    else
        raise notice 'Aviso: no existe (todavia, o ya no aplica) el tipo ehs.lote_lectura. '
            'Si la version portada de sp_capturar_lote usa otro mecanismo para el lote '
            '(jsonb, arreglo, etc.), este aviso es esperado y no requiere accion.';
    end if;
end
$$;

/* migracion 0009 — corregir una lectura ya capturada. Sin parametro de
   tabla, asi que no hace falta un GRANT de TYPE como el de arriba. */
do $$
begin
    if exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'ehs' and p.proname = 'sp_corregir_lectura' and p.prokind = 'p'
    ) then
        execute 'grant execute on procedure ehs.sp_corregir_lectura to ehs_app';
    else
        raise notice 'Aviso: ehs.sp_corregir_lectura todavia no existe. Volver a correr este '
            'script despues de crearlo para completar el permiso de ehs_app.';
    end if;
end
$$;

/* migracion 0017 — confirmar un aviso automatico de salto atipico. Mismo
   patron que las dos de arriba. */
do $$
begin
    if exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'ehs' and p.proname = 'sp_confirmar_aviso' and p.prokind = 'p'
    ) then
        execute 'grant execute on procedure ehs.sp_confirmar_aviso to ehs_app';
    else
        raise notice 'Aviso: ehs.sp_confirmar_aviso todavia no existe. Volver a correr este '
            'script despues de crearlo para completar el permiso de ehs_app.';
    end if;
end
$$;

\echo 'Roles ehs_migrador / ehs_app listos (ver los avisos "NOTICE" arriba para lo pendiente).'

/* =============================================================================
   Que cambia respecto al original, en una frase: los dos LOGIN de servidor de
   SQL Server (ehs_migrador, ehs_app) se vuelven dos ROLE ... LOGIN de
   Postgres, y los roles FIJOS db_owner/db_datareader (que no existen en
   Postgres) se reconstruyen con GRANT explicito sobre la base y los 3
   esquemas mas ALTER DEFAULT PRIVILEGES, en vez de una simple membresia de
   rol — el permiso puntual (EXECUTE en los 3 procedimientos, sin
   INSERT/UPDATE/DELETE directo en ninguna tabla) queda idéntico en espíritu.

   Dudas reales sin resolver (no inventadas para parecer exhaustivo):

   1. check_policy = on del original (politica de contraseñas de Windows) no
      tiene equivalente en Postgres core. Si la politica de clave importa de
      verdad en Neon, hay que decidir si se resuelve con la extension
      'passwordcheck' (exige compilarla/activarla, Neon no la ofrece por
      defecto que yo pueda confirmar) o simplemente generando las claves con
      la misma politica desde el instalador, como ya se hace hoy, y
      confiando en el proceso de generacion en vez del motor.
   2. 'revoke connect on database current_database() from public' asume que
      ningun otro rol (p. ej. el rol de servicio que usa el panel de Neon, o
      un rol de solo lectura para BI que todavia no existe) necesita
      conectarse sin un GRANT explicito nuevo. Si Neon ya usa un rol propio
      para su consola que depende de CONNECT via PUBLIC, este revoke
      podria romperlo — no pude confirmarlo sin acceso a la cuenta de Neon.
   3. GRANT EXECUTE ON PROCEDURE sin lista de parametros asume que la
      version portada de los 3 procedimientos no esta sobrecargada (una sola
      firma por nombre). No pude confirmarlo porque la version Postgres de
      los procedimientos todavia no existe en este repositorio.
   4. CREATE DATABASE (la mitad del original que crea 'analitica' si no
      existe) queda fuera de este archivo a proposito: en Neon la base se
      aprovisiona por su consola/API/CLI, no con un 'create database'
      corrido por psql dentro de un script transaccional como este. Falta
      confirmar el nombre exacto de la base en Neon (si se crea una llamada
      'analitica' o se reusa la que Neon da por defecto) antes de que el
      comando de uso del encabezado sea copiar-y-pegar.
   ============================================================================= */
