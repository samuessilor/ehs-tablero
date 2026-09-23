/**
 * Selector de adaptador de datos.
 *
 * ORIGEN_DATOS=json  -> el interinato: rebanadas de la vista materializada del pipeline.
 * ORIGEN_DATOS=sql   -> el destino: consultas a las vistas ehs.v_* en SQL Server.
 *
 * El contrato de las siete funciones es identico en ambos. Migrar es cambiar esta
 * variable de entorno, no tocar rutas ni front.
 */
const origen = require('./configuracion').obtener('ORIGEN_DATOS') || 'json';

module.exports = origen === 'sql' ? require('./adaptador_sql') : require('./adaptador_json');
