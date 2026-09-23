/* ===========================================================================
   Migracion 0001 — los tres esquemas de la base `analitica`

   ref   dimensiones compartidas: sitio, fecha, magnitud, KPI. Datos maestros
         que otra area (Supply Chain, la que siga) podria reutilizar el dia
         que entre a la misma base. No son negocio de EHS: son vocabulario.

   ops   lo operativo del propio sistema: bitacora de carga, rechazos,
         registro de migraciones aplicadas. No es un hecho que reporte el
         area — es la maquinaria que garantiza que el hecho se cargo bien.

   ehs   el negocio de esta area: los hechos mensuales, las metas, el
         scorecard, las vistas que calculan los indicadores, y el
         procedimiento de captura. Lo unico que un consumidor de fuera
         del area necesita ver.

   Por que tres y no uno: separar "el vocabulario compartido" de "el negocio
   de un area" de "la maquinaria de auditoria del sistema" es lo que permite
   que una segunda area entre a la misma base reutilizando ref y ops sin
   arrastrar las tablas de EHS, y sin que un permiso de lectura sobre ehs.*
   exponga sin querer la bitacora de carga de todas las areas.
   =========================================================================== */

if schema_id('ref') is null
    exec ('create schema ref');
go

if schema_id('ops') is null
    exec ('create schema ops');
go

if schema_id('ehs') is null
    exec ('create schema ehs');
go

print 'Migracion 0001: esquemas ref, ops y ehs creados o ya existentes.';
go
