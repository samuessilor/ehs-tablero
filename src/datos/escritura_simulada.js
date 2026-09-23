/**
 * Adaptador de escritura SIN persistencia. El que corre en el interinato.
 *
 * Valida el lote completo con las mismas reglas que la base de datos y devuelve dos
 * cosas: lo que habria entrado y lo que no, y el T-SQL exacto que se habria ejecutado.
 * No guarda nada. No puede guardar nada: no tiene a donde.
 *
 * POR QUE ESTO NO ES UNA MAQUETA
 *
 * R.5.4.2 dice que el dato real no sale del tenant corporativo. El tablero ya vive en
 * Vercel como interinato declarado y con fecha de retiro, y eso se sostiene porque solo
 * PUBLICA cifras ya reportadas. Un formulario que escribiera seria otra cosa: seria
 * capturar dato operativo directamente en un servicio externo, y eso no tiene version
 * transitoria aceptable.
 *
 * La salida no es prometer que no se usara. Es que no exista el camino. En el
 * interinato el adaptador de escritura no sabe escribir, asi que el incumplimiento no
 * depende de que nadie se equivoque: es imposible. Ademas el sistema de archivos de una
 * funcion de Vercel es de solo lectura, o sea que aunque este archivo quisiera, no
 * podria.
 *
 * Y sirve para algo real en la reunion: EHS ve el formulario que va a usar y comprueba
 * que sus validaciones atrapan lo que el Excel dejaba pasar; IT ve, en la misma
 * pantalla, la sentencia que se ejecutaria contra su servidor. Las dos audiencias
 * miran la misma pieza.
 */
const { MAGNITUDES, SITIOS, examinarLote, examinarCorreccion } = require('../validacion');

/** Literal de cadena en T-SQL: la comilla simple se duplica. */
function txt(v) {
  if (v === null || v === undefined) return 'null';
  return "'" + String(v).replace(/'/g, "''") + "'";
}

/**
 * Reconstruye la llamada que se habria hecho. No es decorativo: es lo que se le
 * enseña al DBA para que diga si le sirve, antes de pedirle un esquema.
 */
function sentenciaEquivalente({ filas, capturadoPor, origen, confirmarAtipicos }) {
  const valores = filas
    .map((f) => {
      const fecha = `${String(f.anio).padStart(4, '0')}-${String(f.mes).padStart(2, '0')}-01`;
      return `  (${txt(fecha)}, ${txt(f.sitio)}, ${txt(f.magnitud)}, ${txt(f.valor)})`;
    })
    .join(',\n');

  return [
    'declare @lote ehs.lote_lectura;',
    'insert @lote (fecha_texto, sitio_texto, magnitud_texto, valor_texto) values',
    valores + ';',
    '',
    'declare @carga_id bigint;',
    'exec ehs.sp_capturar_lote',
    `     @lote               = @lote,`,
    `     @capturado_por      = ${txt(capturadoPor)},`,
    `     @origen             = ${txt(origen || 'formulario de captura EHS')},`,
    `     @confirmar_atipicos = ${confirmarAtipicos ? 1 : 0},`,
    '     @carga_id           = @carga_id output;',
  ].join('\n');
}

async function capturarLote({ filas, capturadoPor, origen, confirmarAtipicos }) {
  if (!capturadoPor || !String(capturadoPor).trim()) {
    const e = new Error('Falta quién captura. La bitácora tiene que poder nombrarlo (R.5.3.4).');
    e.codigo = 'falta_capturador';
    throw e;
  }

  const { validas, rechazadas, advertidas } = examinarLote(filas);

  // Mismo criterio que el procedimiento: lo advertido entra solo si se confirma.
  const entrarian = confirmarAtipicos ? validas.length + advertidas.length : validas.length;
  const pendientes = confirmarAtipicos ? 0 : advertidas.length;

  return {
    modo: 'simulado',
    persistido: false,
    cargaId: null,
    grabadas: entrarian,
    rechazadas: rechazadas.map((f) => ({
      sitio: f.sitio,
      magnitud: f.magnitud,
      valor: f.valor,
      motivo: f.motivo,
    })),
    advertidas: advertidas.map((f) => ({
      sitio: f.sitio,
      magnitud: f.magnitud,
      valor: f.valor,
      advertencia: f.advertencia,
    })),
    pendientes,
    sentencia: sentenciaEquivalente({ filas, capturadoPor, origen, confirmarAtipicos }),
    aviso:
      'Interinato sin base de datos: no se guardó nada, y no se puede. La validación ' +
      'que acabas de ver es la real, y el T-SQL de abajo es exactamente el que se ' +
      'ejecutaría contra el servidor de IT.',
  };
}

/**
 * En el interinato el estado se deduce del JSON ya publicado: es lo unico que hay y
 * dice la verdad sobre que meses tienen dato. No se inventa un calendario vacio.
 */
async function estadoCaptura({ anio }) {
  const json = require('./adaptador_json');
  let publicado = null;
  try {
    publicado = await json.calidadDato({ anio });
  } catch {
    publicado = null;
  }

  const filas = [];
  const porMes = (publicado && publicado.porMes) || [];
  for (const m of porMes) {
    for (const s of SITIOS) {
      filas.push({
        mes: m.mes,
        sitio: s.id,
        sitioNombre: s.etiqueta,
        // El JSON publicado cuenta lecturas del mes en todos los sitios a la vez;
        // repartirlas por sitio seria inventar. Se declara lo que se sabe.
        capturadas: null,
        esperadas: MAGNITUDES.length,
        ultimaCaptura: null,
        ultimoCapturador: null,
      });
    }
  }

  return {
    modo: 'simulado',
    anio: (publicado && publicado.anio) || anio,
    magnitudes: MAGNITUDES,
    mesesConDato: porMes.map((m) => m.mes),
    filas,
    aviso:
      'Sin base de datos no hay estado de captura por sitio. Se listan los meses que ' +
      'el corte publicado ya trae.',
  };
}

/**
 * Igual que capturarLote: valida con la misma regla que ehs.sp_corregir_lectura y no
 * guarda nada, porque no tiene donde.
 */
async function corregirLectura({ anio, mes, sitio, magnitud, valor, motivo, corregidoPor }) {
  if (!corregidoPor || !String(corregidoPor).trim()) {
    const e = new Error('Falta quién corrige. La bitácora tiene que poder nombrarlo (R.5.3.4).');
    e.codigo = 'falta_corrector';
    throw e;
  }

  const r = examinarCorreccion({ magnitud, valor, motivo });
  if (r.motivoInvalido) {
    const e = new Error(r.motivoInvalido);
    e.codigo = 'motivo_invalido';
    throw e;
  }
  if (r.error) {
    const e = new Error(r.error);
    e.codigo = 'valor_invalido';
    throw e;
  }

  const fecha = `${String(anio).padStart(4, '0')}-${String(mes).padStart(2, '0')}-01`;
  return {
    modo: 'simulado',
    persistido: false,
    corregida: false,
    advertencia: r.advertencia || null,
    sentencia:
      `exec ehs.sp_corregir_lectura @fecha = ${txt(fecha)}, @sitio_id = ${txt(sitio)}, ` +
      `@magnitud_id = ${txt(magnitud)}, @valor_nuevo = ${txt(valor)}, ` +
      `@motivo = ${txt(motivo)}, @corregido_por = ${txt(corregidoPor)};`,
    aviso:
      'Interinato sin base de datos: no se guardó nada, y no se puede. El T-SQL de ' +
      'abajo es exactamente el que se ejecutaría contra el servidor de IT.',
  };
}

/** Sin base de datos no hay historial que mostrar: se declara vacio, no se inventa. */
async function historialCorrecciones({ anio }) {
  return {
    modo: 'simulado',
    anio,
    correcciones: [],
    aviso: 'Sin base de datos no hay historial de correcciones que mostrar.',
  };
}

module.exports = {
  capturarLote,
  estadoCaptura,
  corregirLectura,
  historialCorrecciones,
  sentenciaEquivalente,
};
