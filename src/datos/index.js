/**
 * Selector de adaptador de datos.
 *
 * ORIGEN_DATOS=json  -> el interinato: rebanadas de la vista materializada del pipeline.
 * ORIGEN_DATOS=sql   -> SQL Server (el motor local, contenedor o nativo).
 * ORIGEN_DATOS=pg    -> Postgres (el destino: Neon), mismas vistas y reglas, otro motor.
 *
 * El contrato de las funciones es identico en los tres. Migrar es cambiar esta
 * variable de entorno, no tocar rutas ni front.
 *
 * Los tres require() quedan escritos literal (no como lookup en un objeto):
 * el empaquetado de Vercel traza dependencias por analisis estatico del
 * codigo fuente, y un require(variable) le queda invisible — ni el archivo
 * ni lo que ese archivo a su vez requiere (node_modules incluido) llega al
 * deploy. Con los tres literales presentes, los tres se empaquetan siempre,
 * sin importar cual elige ORIGEN_DATOS en tiempo de ejecucion.
 */
const origen = require('./configuracion').obtener('ORIGEN_DATOS') || 'json';

function cargar(origenDatos) {
  if (origenDatos === 'sql') return require('./adaptador_sql');
  if (origenDatos === 'pg') return require('./adaptador_pg');
  return require('./adaptador_json');
}

module.exports = cargar(origen);
