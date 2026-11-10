/**
 * Selector del adaptador de ESCRITURA. Espejo exacto de datos/index.js, que hace lo
 * mismo con la lectura y con la misma variable.
 *
 *   ORIGEN_DATOS=sql   -> escritura_sql: graba de verdad, via ehs.sp_capturar_lote.
 *   ORIGEN_DATOS=pg    -> escritura_pg: igual, contra Postgres (Neon).
 *   cualquier otro     -> escritura_simulada: valida y no guarda.
 *
 * Que el interinato sea el caso por defecto, y no el que hay que pedir, es deliberado:
 * un despliegue mal configurado se queda sin escribir, que es el fallo inocuo. Al
 * reves —que por defecto intentara grabar— un error de configuracion se convertiria en
 * dato operativo en un sitio equivocado.
 *
 * Los tres require() quedan literales por el mismo motivo que en datos/index.js:
 * un require(variable) es invisible para el trazador de dependencias de Vercel.
 */
const origen = require('./configuracion').obtener('ORIGEN_DATOS') || 'json';

function cargar(origenDatos) {
  if (origenDatos === 'sql') return require('./escritura_sql');
  if (origenDatos === 'pg') return require('./escritura_pg');
  return require('./escritura_simulada');
}

module.exports = cargar(origen);
