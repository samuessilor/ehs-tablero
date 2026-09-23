/* =============================================================================
   crear-logins.sql — provision de la base y las dos identidades de EHS
   -----------------------------------------------------------------------------
   Esto NO es una migracion. Vive fuera de migraciones/ a proposito: corre una
   sola vez por instalacion (o al rotar una clave), con una identidad MAS
   elevada que la que usa scripts/migrar.js (sysadmin de la instancia, no el
   login migrador), y hace algo que ninguna migracion deberia poder hacer por
   si sola: crear logins a nivel de servidor. Mezclarlo con las migraciones
   numeradas habria hecho que "reconstruir el esquema con un comando" y
   "otorgar acceso al servidor" fueran la misma operacion, y son dos cosas
   que un DBA de IT puede querer separar.

   R.4.1 del estandar exige que quien implementa el esquema no sea quien lo
   despliega en ejecucion normal. Aqui se traduce en DOS logins:

     ehs_migrador  DDL (db_ddladmin) + lectura/escritura. Solo lo usa
                   scripts/migrar.js, solo al instalar o actualizar.
     ehs_app       db_datareader (todo el dato es de lectura publica dentro de
                   la app: tablero, captura, reportes) + EXECUTE en
                   ehs.sp_capturar_lote — sin db_datawriter. src/datos/
                   escritura_sql.js nunca hace insert/update por su cuenta
                   (esta documentado en su propio encabezado); toda escritura
                   pasa por ese unico procedimiento. Sin db_datawriter, esa
                   disciplina de la capa de aplicacion queda respaldada por
                   el motor: aunque un fallo en el codigo intentara un insert
                   directo a ehs.hecho_lectura_mensual, el permiso no existe.
                   NO es sa, NO es db_owner: no puede crear ni alterar una
                   sola tabla.

   Uso (PowerShell, con sqlcmd; el instalador genera las claves, nunca las
   escribe a mano). DOS PASADAS, con migrar.js en medio: la primera crea la base,
   los logins y los roles; para entonces ehs.sp_capturar_lote todavia no existe,
   asi que el permiso EXECUTE queda pendiente (el script avisa, no falla). La
   segunda pasada, identica, ya lo completa porque migrar.js ya lo creo:

     $claveMigrador = ... # generada, 20+ caracteres, cumple la politica de Windows
     $claveApp      = ...

     sqlcmd -S 127.0.0.1,14330 -U sa -P "<clave de instalacion>" `
            -v ClaveMigrador="$claveMigrador" ClaveApp="$claveApp" `
            -i instalacion\crear-logins.sql              # pasada 1

     node scripts\migrar.js                               # crea el esquema

     sqlcmd -S 127.0.0.1,14330 -U sa -P "<clave de instalacion>" `
            -v ClaveMigrador="$claveMigrador" ClaveApp="$claveApp" `
            -i instalacion\crear-logins.sql              # pasada 2: completa el grant

   Las dos claves resultantes las escribe el instalador en config\ehs.env
   (SQL_MIGRADOR_CLAVE y SQL_CLAVE) — nunca en este script, nunca en el
   repositorio. Ver config\ehs.env.ejemplo.

   Idempotente: se puede correr de nuevo (por ejemplo tras `actualizar.ps1`)
   sin romper nada. NO rota una clave ya creada — para eso existe
   `rotar-clave.sql` (rotacion de credenciales, fuera del alcance de esta
   sesion; ver docs de Fase D).
   ============================================================================= */

/* NO se declaran :setvar por defecto para ClaveMigrador/ClaveApp aqui a proposito:
   un :setvar en el script SIEMPRE gana sobre el valor que -v pasa por linea de
   comandos (sqlcmd lo re-evalua al leer esta linea y pisa lo que vino de afuera).
   Con un default en blanco, create login recibiria una clave vacia en silencio en
   vez de fallar. Sin :setvar aqui, si alguien corre este script sin pasar -v
   ClaveMigrador/ClaveApp, sqlcmd lo rechaza de entrada ("ClaveMigrador scripting
   variable not defined") en vez de crear un login con clave vacia. */

/* --------------------------------------------------------------- la base --- */

/* SQL_Latin1_General_CP1_CI_AS es la collation por defecto de la imagen de
   contenedor usada en esta sesion (mcr.microsoft.com/mssql/server:2022-latest) y
   nunca se habia fijado de forma explicita — hallazgo de la auditoria de Fase A.
   Se fija aqui a proposito, para que el modo nativo (SQL Server Express) y el modo
   contenedor terminen en la MISMA collation sin depender de cual sea el default de
   cada instalacion. */
if db_id('analitica') is null
    create database analitica collate SQL_Latin1_General_CP1_CI_AS;
go

/* --------------------------------------------------------- login migrador --- */

if not exists (select 1 from sys.server_principals where name = 'ehs_migrador')
begin
    declare @sql_migrador nvarchar(max) = N'
        create login ehs_migrador
            with password = ''$(ClaveMigrador)'',
                 check_policy = on, check_expiration = off,
                 default_database = analitica;';
    exec (@sql_migrador);
end
go

/* ------------------------------------------------------------- login app --- */

if not exists (select 1 from sys.server_principals where name = 'ehs_app')
begin
    declare @sql_app nvarchar(max) = N'
        create login ehs_app
            with password = ''$(ClaveApp)'',
                 check_policy = on, check_expiration = off,
                 default_database = analitica;';
    exec (@sql_app);
end
go

use analitica;
go

/* --------------------------------------------------- usuarios de base de datos --- */

if not exists (select 1 from sys.database_principals where name = 'ehs_migrador')
    create user ehs_migrador for login ehs_migrador;
go

if not exists (select 1 from sys.database_principals where name = 'ehs_app')
    create user ehs_app for login ehs_app;
go

/* ------------------------------------------------------------------ roles --- */

/* db_ddladmin: puede crear, alterar y borrar objetos (tablas, vistas, procedimientos,
   tipos, esquemas via EXEC) — exactamente lo que migrar.js necesita para aplicar los
   archivos numerados de migraciones, y nada de administracion de servidor.
   db_datareader + db_datawriter porque el migrador tambien corre la migracion de
   datos de ejemplo (opcional, con --con-datos-semilla) y necesita leer/escribir
   ops.migracion_aplicada. */
if not exists (select 1 from sys.database_role_members rm
               join sys.database_principals r on r.principal_id = rm.role_principal_id
               join sys.database_principals m on m.principal_id = rm.member_principal_id
               where r.name = 'db_ddladmin' and m.name = 'ehs_migrador')
    alter role db_ddladmin add member ehs_migrador;
go

if not exists (select 1 from sys.database_role_members rm
               join sys.database_principals r on r.principal_id = rm.role_principal_id
               join sys.database_principals m on m.principal_id = rm.member_principal_id
               where r.name = 'db_datareader' and m.name = 'ehs_migrador')
    alter role db_datareader add member ehs_migrador;
go

if not exists (select 1 from sys.database_role_members rm
               join sys.database_principals r on r.principal_id = rm.role_principal_id
               join sys.database_principals m on m.principal_id = rm.member_principal_id
               where r.name = 'db_datawriter' and m.name = 'ehs_migrador')
    alter role db_datawriter add member ehs_migrador;
go

/* ehs_app: solo lectura de datos. Ni db_datawriter ni db_ddladmin. */
if not exists (select 1 from sys.database_role_members rm
               join sys.database_principals r on r.principal_id = rm.role_principal_id
               join sys.database_principals m on m.principal_id = rm.member_principal_id
               where r.name = 'db_datareader' and m.name = 'ehs_app')
    alter role db_datareader add member ehs_app;
go

/* La UNICA puerta de escritura que ehs_app tiene: permiso para EJECUTAR el
   procedimiento de captura. Ownership chaining (todos los esquemas de analitica
   quedan con dueno dbo por defecto) hace que ejecutar el procedimiento alcance
   para que este escriba en ehs.hecho_lectura_mensual, ops.carga_log y
   ops.lectura_rechazada sin que ehs_app tenga permiso directo de escritura sobre
   esas tablas por fuera del procedimiento. No es una convencion de la capa de
   aplicacion: sin este grant y sin db_datawriter, un insert directo a esas tablas
   falla por permisos aunque el codigo lo intentara.

   El procedimiento recibe el lote como parametro con valores de tabla
   (ehs.lote_lectura, un TIPO, no una tabla). SQL Server exige EXECUTE sobre ESE
   TIPO por separado del EXECUTE sobre el procedimiento — sin el, la llamada falla
   con "EXECUTE permission was denied on the object 'lote_lectura'" aunque el
   permiso sobre sp_capturar_lote este bien. No es intuitivo y esta app lo
   descubrio probando el flujo real de escritura contra un contenedor limpio con
   ehs_app conectado (no con sa): confirmar con el login real que va a usar la
   aplicacion, no solo con el que instala, es lo que lo hizo visible.

   En la PRIMERA pasada (antes de migrar.js) ni el procedimiento ni el tipo
   existen todavia: este bloque lo detecta y no falla, solo avisa. Por eso el
   instalador corre este script DOS VECES — ver "Uso" al inicio del archivo. */
if object_id('ehs.sp_capturar_lote') is not null
begin
    grant execute on ehs.sp_capturar_lote to ehs_app;
    grant execute on type::ehs.lote_lectura to ehs_app;
end
else
    print 'Aviso: ehs.sp_capturar_lote todavia no existe. Correr migrar.js y '
        + 'volver a correr este script para completar el permiso de ehs_app.';
go

print 'Base analitica y logins ehs_migrador / ehs_app listos.';
go
