/**
 * Selector del adaptador de ESCRITURA. Espejo exacto de datos/index.js, que hace lo
 * mismo con la lectura y con la misma variable.
 *
 *   ORIGEN_DATOS=sql   -> escritura_sql: graba de verdad, via ehs.sp_capturar_lote.
 *   cualquier otro     -> escritura_simulada: valida y no guarda.
 *
 * Que el interinato sea el caso por defecto, y no el que hay que pedir, es deliberado:
 * un despliegue mal configurado se queda sin escribir, que es el fallo inocuo. Al
 * reves —que por defecto intentara grabar— un error de configuracion se convertiria en
 * dato operativo en un sitio equivocado.
 */
const origen = require('./configuracion').obtener('ORIGEN_DATOS') || 'json';

module.exports = origen === 'sql' ? require('./escritura_sql') : require('./escritura_simulada');
