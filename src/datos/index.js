/**
 * Selector de adaptador de datos.
 *
 * ORIGEN_DATOS=json  -> el interinato: rebanadas de la vista materializada del pipeline.
 * ORIGEN_DATOS=sql   -> SQL Server (el motor local, contenedor o nativo).
 * ORIGEN_DATOS=pg    -> Postgres (el destino: Neon), mismas vistas y reglas, otro motor.
 *
 * El contrato de las funciones es identico en los tres. Migrar es cambiar esta
 * variable de entorno, no tocar rutas ni front.
 */
const origen = require('./configuracion').obtener('ORIGEN_DATOS') || 'json';

const ADAPTADORES = { sql: './adaptador_sql', pg: './adaptador_pg', json: './adaptador_json' };
module.exports = require(ADAPTADORES[origen] || ADAPTADORES.json);
