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
const {
  MAGNITUDES,
  SITIOS,
  MENSAJE_MILES,
  aNumero,
  esMilesAmbiguo,
  advertenciaCero,
} = require('../validacion');
const { cargarDriver, pool, cerrar } = require('./conexion_sql');
const respaldo = require('../respaldo');

const SITIO_IDS = new Set(SITIOS.map((s) => s.id));

// La fecha viaja SIEMPRE en ISO. Mandar '01/08/2026' dejaria que el idioma del
// servidor decida si es enero o agosto, y las dos lecturas son plausibles.
const fechaIso = (f) => `${String(f.anio).padStart(4, '0')}-${String(f.mes).padStart(2, '0')}-01`;

/**
 * Graba un lote. Devuelve el mismo objeto que el adaptador simulado, para que la
 * ruta y el cliente no sepan cual de los dos esta detras.
 *
 * Antes del procedimiento se decide aqui lo que la revision final encontro que se
 * colaba (el procedimiento sigue siendo quien valida rango, negativos y texto):
 *   - una lectura YA capturada con otro valor no se sobrescribe: se aparta con
 *     "usa Consultar y corregir". El merge del procedimiento la reemplazaba en
 *     silencio, sin motivo y sin salir en el historial de correcciones. Con el mismo
 *     valor no pasa nada (reenviar el mes no cambia nada), y se cuenta aparte;
 *   - el numero se normaliza (coma decimal) y el punto de miles ambiguo se rechaza:
 *     el procedimiento leia "9.614" como 9,614 horas y "979,1" como texto invalido;
 *   - solo capturan Celta, La Estrella y Agencias (peru y colombia_peru existen en la
 *     base para el scorecard anual y el procedimiento los aceptaba);
 *   - un cero donde nunca ha habido cero pide confirmacion, como cualquier atipico.
 * Lo apartado aqui no pasa por ops.lectura_rechazada: no es un dato malo del origen,
 * es una lectura que ya existe o un numero escrito de forma ambigua en la pantalla.
 */
async function capturarLote({ filas, capturadoPor, origen, confirmarAtipicos }) {
  const sql = cargarDriver();
  const p = await pool();

  // lo que ya esta en la base para los meses del lote
  const fechasValidas = [
    ...new Set(
      filas
        .filter(
          (f) => Number.isInteger(f.anio) && Number.isInteger(f.mes) && f.mes >= 1 && f.mes <= 12
        )
        .map(fechaIso)
    ),
  ].sort();
  const existentes = new Map();
  if (fechasValidas.length) {
    const e = await p
      .request()
      .input('desde', sql.Date, fechasValidas[0])
      .input('hasta', sql.Date, fechasValidas[fechasValidas.length - 1])
      .query(
        'select fecha = convert(char(10), fecha, 23), sitio_id, magnitud_id, ' +
          'valor = cast(valor as float) from ehs.hecho_lectura_mensual ' +
          'where fecha between @desde and @hasta'
      );
    for (const x of e.recordset)
      existentes.set(`${x.fecha}|${x.sitio_id}|${x.magnitud_id}`, x.valor);
  }

  const apartadas = [];
  const advertidasAqui = [];
  let sinCambios = 0;
  const tabla = new sql.Table('ehs.lote_lectura');
  tabla.columns.add('fecha_texto', sql.VarChar(40), { nullable: true });
  tabla.columns.add('sitio_texto', sql.VarChar(60), { nullable: true });
  tabla.columns.add('magnitud_texto', sql.VarChar(60), { nullable: true });
  tabla.columns.add('valor_texto', sql.VarChar(60), { nullable: true });

  for (const f of filas) {
    const fila = { sitio: f.sitio, magnitud: f.magnitud, valor: f.valor };
    if (f.sitio != null && !SITIO_IDS.has(String(f.sitio))) {
      apartadas.push({
        ...fila,
        motivo: 'Ese sitio no captura mes a mes: solo Celta, La Estrella y Agencias.',
      });
      continue;
    }
    if (esMilesAmbiguo(f.valor)) {
      apartadas.push({ ...fila, motivo: MENSAJE_MILES });
      continue;
    }
    const n = aNumero(f.valor);
    const previo = existentes.get(`${fechaIso(f)}|${f.sitio}|${f.magnitud}`);
    if (previo !== undefined && n !== null) {
      if (Math.abs(previo - n) < 1e-9) {
        sinCambios++;
      } else {
        apartadas.push({
          ...fila,
          motivo:
            `Ya está capturada con ${String(previo).replace('.', ',')}. Para cambiarla usa ` +
            'Consultar y corregir: pide el motivo y deja el valor anterior en el historial.',
        });
      }
      continue;
    }
    const cero = n !== null ? advertenciaCero(String(f.magnitud), n) : null;
    if (cero && !confirmarAtipicos) {
      advertidasAqui.push({ ...fila, advertencia: cero });
      continue;
    }
    tabla.rows.add(
      fechaIso(f),
      f.sitio == null ? null : String(f.sitio),
      f.magnitud == null ? null : String(f.magnitud),
      // normalizado si es numero; si no, el texto tal cual, para que el procedimiento
      // lo rechace y deje en la bitacora exactamente lo que se escribio
      n !== null ? String(n) : f.valor == null ? null : String(f.valor)
    );
  }

  let cab = {};
  let rechazos = [];
  let advertencias = [];
  let cargaId = null;
  if (tabla.rows.length) {
    const r = await p
      .request()
      .input('lote', tabla)
      .input('capturado_por', sql.VarChar(60), capturadoPor)
      .input('origen', sql.VarChar(120), origen || 'formulario de captura EHS')
      .input('confirmar_atipicos', sql.Bit, confirmarAtipicos ? 1 : 0)
      .output('carga_id', sql.BigInt)
      .execute('ehs.sp_capturar_lote');
    [[cab = {}] = [], rechazos = [], advertencias = []] = r.recordsets;
    cargaId = cab.carga_id ?? r.output.carga_id ?? null;
  }

  if ((cab.grabadas ?? 0) > 0) respaldo.disparar();

  return {
    modo: 'sql',
    persistido: true,
    cargaId,
    grabadas: cab.grabadas ?? 0,
    sinCambios,
    rechazadas: apartadas.concat(
      rechazos.map((x) => ({
        sitio: x.sitio,
        magnitud: x.magnitud,
        valor: x.valor,
        motivo: x.motivo,
      }))
    ),
    advertidas: advertidasAqui.concat(
      advertencias.map((x) => ({
        sitio: x.sitio,
        magnitud: x.magnitud,
        valor: x.valor,
        advertencia: x.advertencia,
      }))
    ),
    pendientes: (cab.pendientes ?? 0) + advertidasAqui.length,
  };
}

/**
 * Que hay capturado ya, por mes y sitio. Lo pide el formulario al abrirse para no
 * pedir dos veces lo mismo ni dejar un mes a medias sin que se note.
 *
 * Con `mes`, ademas las celdas de ESE mes que ya tienen lectura, con su valor: el
 * formulario las marca como ya capturadas y nombra las que faltan. Sin eso, volver a
 * completar un mes a medias era abrir una rejilla vacia sin saber que faltaba.
 */
async function estadoCaptura({ anio, mes }) {
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

  let celdas;
  if (mes) {
    const c = await p
      .request()
      .input('anio', sql.SmallInt, anio)
      .input('mes', sql.TinyInt, mes)
      .query(
        'select sitio_id, magnitud_id, valor from ehs.v_calidad_dato ' +
          'where anio = @anio and num_mes = @mes and tiene_lectura = 1'
      );
    celdas = c.recordset.map((x) => ({
      sitio: x.sitio_id,
      magnitud: x.magnitud_id,
      valor: x.valor == null ? null : Number(x.valor),
    }));
  }

  return {
    modo: 'sql',
    anio,
    mes: mes || undefined,
    celdas,
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

/**
 * Corrige UN valor ya capturado, via ehs.sp_corregir_lectura (migracion 0009). Puerta
 * de escritura distinta de capturarLote a proposito: exige un motivo escrito, y solo
 * toca una fila que ya existe — no crea nada nuevo.
 */
async function corregirLectura({ anio, mes, sitio, magnitud, valor, motivo, corregidoPor }) {
  const sql = cargarDriver();
  const p = await pool();

  const fecha = `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}-01`;
  const r = await p
    .request()
    .input('fecha', sql.Date, fecha)
    .input('sitio_id', sql.VarChar(20), sitio)
    .input('magnitud_id', sql.VarChar(40), magnitud)
    .input('valor_nuevo', sql.Decimal(18, 4), valor)
    .input('motivo', sql.VarChar(300), motivo)
    .input('corregido_por', sql.VarChar(60), corregidoPor)
    .execute('ehs.sp_corregir_lectura');

  const fila = (r.recordset || [])[0] || {};
  const corregida = (fila.filas_corregidas ?? 0) > 0;
  if (corregida) respaldo.disparar();

  return {
    modo: 'sql',
    persistido: true,
    corregida,
  };
}

/**
 * Confirma UN aviso automatico de salto atipico, via ehs.sp_confirmar_aviso
 * (migracion 0017): alguien del area miro la tabla completa y da su veredicto — el
 * dato es real, no un error de captura. No toca ehs.hecho_lectura_mensual (por eso,
 * a diferencia de capturarLote/corregirLectura, no dispara respaldo.disparar(): esta
 * funcion existe para "despues de un cambio de dato", y una confirmacion no lo es —
 * el respaldo diario ya la cubre).
 */
async function confirmarAviso({ anio, mes, sitio, magnitud, codigo, confirmadoPor, nota }) {
  const sql = cargarDriver();
  const p = await pool();

  const fecha = `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}-01`;
  const r = await p
    .request()
    .input('fecha', sql.Date, fecha)
    .input('sitio_id', sql.VarChar(20), sitio)
    .input('magnitud_id', sql.VarChar(40), magnitud)
    .input('codigo', sql.VarChar(40), codigo)
    .input('confirmado_por', sql.VarChar(60), confirmadoPor)
    .input('nota', sql.VarChar(300), nota || null)
    .execute('ehs.sp_confirmar_aviso');

  const fila = (r.recordset || [])[0] || {};
  return {
    modo: 'sql',
    persistido: true,
    confirmado: (fila.filas_confirmadas ?? 0) > 0,
  };
}

/**
 * El historial de correcciones (pantalla "Consultar y corregir" y, en el futuro, la
 * franja que hoy pinta franja_correccion.js desde un CSV estatico del modo JSON).
 */
async function historialCorrecciones({ anio }) {
  const sql = cargarDriver();
  const p = await pool();
  const r = await p
    .request()
    .input('anio', sql.SmallInt, anio)
    .query(
      'select fecha, anio, mes, sitio_id, sitio_corto, magnitud_id, magnitud, ' +
        'valor_anterior, valor_corregido, motivo, autorizado_por, corregido_en ' +
        'from ehs.v_correcciones where anio = @anio order by corregido_en desc'
    );

  return {
    modo: 'sql',
    anio,
    correcciones: r.recordset.map((x) => ({
      fecha: x.fecha,
      anio: x.anio,
      mes: x.mes,
      sitio: x.sitio_id,
      sitioCorto: x.sitio_corto,
      magnitud: x.magnitud_id,
      magnitudNombre: x.magnitud,
      valorAnterior: x.valor_anterior,
      valorCorregido: x.valor_corregido,
      motivo: x.motivo,
      autorizadoPor: x.autorizado_por,
      corregidoEn: x.corregido_en,
    })),
  };
}

module.exports = {
  capturarLote,
  estadoCaptura,
  corregirLectura,
  confirmarAviso,
  historialCorrecciones,
  cerrar,
};
