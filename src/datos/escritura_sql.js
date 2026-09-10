/**
 * Adaptador de escritura contra SQL Server. El destino real.
 *
 * Todo lo que escribe pasa por ehs.sp_capturar_lote (app/sql/04-ingesta.sql). Este
 * modulo NO hace insert ni update por su cuenta, y no es una preferencia de estilo:
 *
 *   - El procedimiento es idempotente por construccion (merge sobre uq_lectura_mensual).
 *     Un insert desde aqui tendria que comprobar antes si existe, y entre la
 *     comprobacion y el insert cabe otra carga.
 *   - El procedimiento aparta los rechazos y escribe la bitacora en la MISMA
 *     transaccion que graba. Partido en dos viajes, una caida entre ellos deja
 *     lecturas sin bitacora o rechazos sin lectura.
 *   - Si manana el dato entra por un JOB en vez de por este formulario, la validacion
 *     y la traza son las mismas sin escribirlas de nuevo.
 *
 * La conexion (driver, configuracion y pool) vive en conexion_sql.js, compartida con
 * el adaptador de lectura: una sola forma de conectarse a la base para toda la app.
 */
const { MAGNITUDES } = require('../validacion');
const { cargarDriver, pool, cerrar } = require('./conexion_sql');

/**
 * Graba un lote. Devuelve el mismo objeto que el adaptador simulado, para que la
 * ruta y el cliente no sepan cual de los dos esta detras.
 */
async function capturarLote({ filas, capturadoPor, origen, confirmarAtipicos }) {
  const sql = cargarDriver();
  const p = await pool();

  const tabla = new sql.Table('ehs.lote_lectura');
  tabla.columns.add('fecha_texto', sql.VarChar(40), { nullable: true });
  tabla.columns.add('sitio_texto', sql.VarChar(60), { nullable: true });
  tabla.columns.add('magnitud_texto', sql.VarChar(60), { nullable: true });
  tabla.columns.add('valor_texto', sql.VarChar(60), { nullable: true });

  for (const f of filas) {
    // La fecha viaja SIEMPRE en ISO. Mandar '01/08/2026' dejaria que el idioma del
    // servidor decida si es enero o agosto, y las dos lecturas son plausibles.
    const fecha = `${String(f.anio).padStart(4, '0')}-${String(f.mes).padStart(2, '0')}-01`;
    tabla.rows.add(
      fecha,
      f.sitio == null ? null : String(f.sitio),
      f.magnitud == null ? null : String(f.magnitud),
      f.valor == null ? null : String(f.valor)
    );
  }

  const r = await p
    .request()
    .input('lote', tabla)
    .input('capturado_por', sql.VarChar(60), capturadoPor)
    .input('origen', sql.VarChar(120), origen || 'formulario de captura EHS')
    .input('confirmar_atipicos', sql.Bit, confirmarAtipicos ? 1 : 0)
    .output('carga_id', sql.BigInt)
    .execute('ehs.sp_capturar_lote');

  const [resumen = [], rechazos = [], advertencias = []] = r.recordsets;
  const cab = resumen[0] || {};

  return {
    modo: 'sql',
    persistido: true,
    cargaId: cab.carga_id ?? r.output.carga_id ?? null,
    grabadas: cab.grabadas ?? 0,
    rechazadas: rechazos.map((x) => ({
      sitio: x.sitio,
      magnitud: x.magnitud,
      valor: x.valor,
      motivo: x.motivo,
    })),
    advertidas: advertencias.map((x) => ({
      sitio: x.sitio,
      magnitud: x.magnitud,
      valor: x.valor,
      advertencia: x.advertencia,
    })),
    pendientes: cab.pendientes ?? 0,
  };
}

/**
 * Que hay capturado ya, por mes y sitio. Lo pide el formulario al abrirse para no
 * pedir dos veces lo mismo ni dejar un mes a medias sin que se note.
 */
async function estadoCaptura({ anio }) {
  const sql = cargarDriver();
  const p = await pool();
  const r = await p
    .request()
    .input('anio', sql.SmallInt, anio)
    .query(
      'select anio, num_mes, sitio_id, sitio_nombre, capturadas, esperadas, ' +
        'ultima_captura, ultimo_capturador ' +
        'from ehs.v_captura_estado where anio = @anio order by num_mes, sitio_id'
    );

  return {
    modo: 'sql',
    anio,
    magnitudes: MAGNITUDES,
    filas: r.recordset.map((x) => ({
      mes: x.num_mes,
      sitio: x.sitio_id,
      sitioNombre: x.sitio_nombre,
      capturadas: x.capturadas,
      esperadas: x.esperadas,
      ultimaCaptura: x.ultima_captura,
      ultimoCapturador: x.ultimo_capturador,
    })),
  };
}

module.exports = { capturarLote, estadoCaptura, cerrar };
