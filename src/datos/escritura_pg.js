/**
 * Adaptador de escritura contra Postgres (Neon). Puerto de escritura_sql.js
 * (driver 'mssql' -> 'pg'), MISMA logica de negocio y MISMAS claves de salida.
 *
 * La captura queda partida en DOS llamadas donde el original usaba una sola
 * (ehs.sp_iniciar_carga + ehs.sp_capturar_lote, en vez de un solo
 * ehs.sp_capturar_lote que generaba su propio carga_id). No es una preferencia de
 * estilo: un procedimiento SECURITY DEFINER no puede ejecutar COMMIT en Postgres
 * ("invalid transaction termination", probado en vivo contra un Postgres 16
 * desechable antes de tocar cualquier cuenta real — ver postgres/
 * 03_trigger_y_procedimientos.sql), y el diseno original necesitaba exactamente eso
 * para que la fila de la bitacora sobreviviera aunque el resto de la captura se
 * deshaga. Partir en dos llamadas de nivel superior logra lo mismo sin pelear con
 * esa restriccion: cada CALL es su propia transaccion implicita.
 *
 * CALL con parametros OUT en Postgres exige notacion POSICIONAL (la notacion con
 * nombre => no resuelve si el procedimiento tiene algun OUT, sin importar su
 * posicion — tambien probado en vivo) y un valor para CADA parametro declarado,
 * incluidos los OUT (de relleno: se ignoran, el valor real vuelve en la fila que
 * devuelve la sentencia). Por eso cada CALL de aqui trae placeholders $N::tipo
 * explicitos en las posiciones OUT — nunca el valor real del parametro que importa.
 */
const {
  MAGNITUDES,
  SITIOS,
  MENSAJE_MILES,
  aNumero,
  esMilesAmbiguo,
  advertenciaCero,
} = require('../validacion');
const { pool, cerrar } = require('./conexion_pg');
const respaldo = require('../respaldo');

const SITIO_IDS = new Set(SITIOS.map((s) => s.id));

// La fecha viaja SIEMPRE en ISO, igual que en escritura_sql.js: mandar '01/08/2026'
// dejaria que el idioma del servidor decida si es enero o agosto.
const fechaIso = (f) => `${String(f.anio).padStart(4, '0')}-${String(f.mes).padStart(2, '0')}-01`;

async function consulta(texto, params = []) {
  const p = await pool();
  return p.query(texto, params);
}

/**
 * Graba un lote. Devuelve el mismo objeto que el adaptador simulado y que
 * escritura_sql.js, para que la ruta y el cliente no sepan cual motor hay detras.
 *
 * Mismas reglas aplicadas ANTES del procedimiento que en escritura_sql.js (ver su
 * encabezado para el porque de cada una): no sobrescribir una lectura ya capturada
 * con otro valor, normalizar coma decimal y rechazar punto de miles ambiguo, solo
 * Celta/Estrella/Agencias capturan mes a mes, un cero atipico pide confirmacion.
 */
async function capturarLote({ filas, capturadoPor, origen, confirmarAtipicos }) {
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
    const e = await p.query(
      'select fecha::text as fecha, sitio_id, magnitud_id, valor::float8 as valor ' +
        'from ehs.hecho_lectura_mensual where fecha between $1 and $2',
      [fechasValidas[0], fechasValidas[fechasValidas.length - 1]]
    );
    for (const x of e.rows) existentes.set(`${x.fecha}|${x.sitio_id}|${x.magnitud_id}`, x.valor);
  }

  const apartadas = [];
  const advertidasAqui = [];
  let sinCambios = 0;
  // Filas del tipo compuesto ehs.lote_lectura, como literales ROW(...) dentro de un
  // ARRAY[...] en la propia sentencia — 'pg' no tiene un equivalente directo del
  // sql.Table de 'mssql' (table-valued parameter) para un tipo definido por el
  // usuario, asi que el arreglo se arma como texto SQL con cada valor como
  // parametro posicional aparte (nunca interpolado crudo).
  const filasLote = [];
  const paramsLote = [];

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
    // +4: los 4 primeros placeholders de la sentencia final son cargaId,
    // capturadoPor, origen y confirmarAtipicos (ver mas abajo) — paramsLote se
    // concatena DESPUES de esos en el arreglo de parametros real, asi que su
    // numeracion de $N tiene que arrancar en 5, no en 1.
    const base = 4 + paramsLote.length;
    paramsLote.push(
      fechaIso(f),
      f.sitio == null ? null : String(f.sitio),
      f.magnitud == null ? null : String(f.magnitud),
      // normalizado si es numero; si no, el texto tal cual, para que el procedimiento
      // lo rechace y deje en la bitacora exactamente lo que se escribio
      n !== null ? String(n) : f.valor == null ? null : String(f.valor)
    );
    filasLote.push(`ROW($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4})::ehs.lote_lectura`);
  }

  let cargaId = null;
  let grabadas = 0;
  let pendientesProc = 0;
  let rechazosProc = [];
  let advertenciasProc = [];

  if (filasLote.length) {
    // Paso 1: abre la bitacora en su propia llamada (sobrevive sola, ver el
    // encabezado de este archivo). El placeholder OUT lleva el tipo explicito —
    // 'pg' no puede inferir el tipo de un NULL literal sin contexto.
    const i = await consulta('call ehs.sp_iniciar_carga($1, null::bigint)', [capturadoPor]);
    cargaId = i.rows[0].p_carga_id;

    // Paso 2: el resto, con el carga_id ya abierto. Los 5 placeholders OUT
    // (p_grabadas, p_rechazos, p_pendientes, p_rechazadas, p_advertencias) van en
    // null::TIPO exacto, en el mismo orden que la firma de 03_trigger_y_procedimientos.sql.
    const r = await consulta(
      `call ehs.sp_capturar_lote(
         $1::bigint,
         array[${filasLote.join(', ')}],
         $2::varchar,
         null::int, null::int, null::int, null::jsonb, null::jsonb,
         $3::varchar, $4::boolean
       )`,
      [
        cargaId,
        capturadoPor,
        origen || 'formulario de captura EHS',
        Boolean(confirmarAtipicos),
        ...paramsLote,
      ]
    );
    const fila = r.rows[0] || {};
    grabadas = fila.p_grabadas ?? 0;
    pendientesProc = fila.p_pendientes ?? 0;
    rechazosProc = fila.p_rechazadas || [];
    advertenciasProc = fila.p_advertencias || [];
  }

  if (grabadas > 0) respaldo.disparar();

  return {
    modo: 'pg',
    persistido: true,
    cargaId,
    grabadas,
    sinCambios,
    rechazadas: apartadas.concat(
      rechazosProc.map((x) => ({
        sitio: x.sitio,
        magnitud: x.magnitud,
        valor: x.valor,
        motivo: x.motivo,
      }))
    ),
    advertidas: advertidasAqui.concat(
      advertenciasProc.map((x) => ({
        sitio: x.sitio,
        magnitud: x.magnitud,
        valor: x.valor,
        advertencia: x.advertencia,
      }))
    ),
    pendientes: pendientesProc + advertidasAqui.length,
  };
}

/**
 * Que hay capturado ya, por mes y sitio. Puerto literal de escritura_sql.js —
 * mismas dos consultas (ehs.v_captura_estado y ehs.v_calidad_dato), solo con
 * placeholders posicionales.
 */
async function estadoCaptura({ anio, mes }) {
  const r = await consulta(
    'select anio, num_mes, sitio_id, sitio_nombre, capturadas, esperadas, ' +
      'ultima_captura, ultimo_capturador ' +
      'from ehs.v_captura_estado where anio = $1 order by num_mes, sitio_id',
    [anio]
  );

  let celdas;
  if (mes) {
    // tiene_lectura quedo portada como entero 0/1 (case when ... then 0 else 1 end,
    // igual que el bit de SQL Server), no booleana - probado en vivo: compararla con
    // 'true' revienta con "operator does not exist: integer = boolean".
    const c = await consulta(
      'select sitio_id, magnitud_id, valor from ehs.v_calidad_dato ' +
        'where anio = $1 and num_mes = $2 and tiene_lectura = 1',
      [anio, mes]
    );
    celdas = c.rows.map((x) => ({
      sitio: x.sitio_id,
      magnitud: x.magnitud_id,
      valor: x.valor == null ? null : Number(x.valor),
    }));
  }

  return {
    modo: 'pg',
    anio,
    mes: mes || undefined,
    celdas,
    magnitudes: MAGNITUDES,
    filas: r.rows.map((x) => ({
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
 * Corrige UN valor ya capturado, via ehs.sp_corregir_lectura. Puerto literal:
 * sin cambios de logica, solo placeholders posicionales y el OUT de relleno.
 */
async function corregirLectura({ anio, mes, sitio, magnitud, valor, motivo, corregidoPor }) {
  const fecha = `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}-01`;
  const r = await consulta(
    'call ehs.sp_corregir_lectura($1::date, $2::varchar, $3::varchar, $4::numeric, ' +
      '$5::varchar, $6::varchar, null::int)',
    [fecha, sitio, magnitud, valor, motivo, corregidoPor]
  );

  const fila = r.rows[0] || {};
  const corregida = (fila.p_filas_corregidas ?? 0) > 0;
  if (corregida) respaldo.disparar();

  return {
    modo: 'pg',
    persistido: true,
    corregida,
  };
}

/**
 * Confirma UN aviso automatico de salto atipico, via ehs.sp_confirmar_aviso.
 * Puerto literal, mismo motivo que arriba.
 */
async function confirmarAviso({ anio, mes, sitio, magnitud, codigo, confirmadoPor, nota }) {
  const fecha = `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}-01`;
  const r = await consulta(
    'call ehs.sp_confirmar_aviso($1::date, $2::varchar, $3::varchar, $4::varchar, ' +
      '$5::varchar, null::int, $6::varchar)',
    [fecha, sitio, magnitud, codigo, confirmadoPor, nota || null]
  );

  const fila = r.rows[0] || {};
  return {
    modo: 'pg',
    persistido: true,
    confirmado: (fila.p_filas_confirmadas ?? 0) > 0,
  };
}

/**
 * El historial de correcciones. Puerto literal de escritura_sql.js.
 */
async function historialCorrecciones({ anio }) {
  const r = await consulta(
    'select fecha, anio, mes, sitio_id, sitio_corto, magnitud_id, magnitud, ' +
      'valor_anterior, valor_corregido, motivo, autorizado_por, corregido_en ' +
      'from ehs.v_correcciones where anio = $1 order by corregido_en desc',
    [anio]
  );

  return {
    modo: 'pg',
    anio,
    correcciones: r.rows.map((x) => ({
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
