/**
 * Una sola ruta: confirmar un aviso automatico de calidad (migracion 0017).
 *
 *   POST /api/ehs/aviso/confirmar   alguien del area ya reviso la tabla y da su veredicto
 *
 * Distinta de rutas_correccion.js a propósito: esto no cambia ningún valor capturado,
 * solo deja constancia de que un salto atípico ya se revisó y se dio por bueno. El
 * grid con los datos para decidir tampoco es una ruta nueva: ya lo trae la ficha del
 * propio aviso (fichaAviso en tablero.js, /api/ehs/datos por debajo).
 */
const escritura = require('./datos/escritura');
const errores = require('./errores');
const { SITIOS, MAGNITUDES, CODIGOS_AVISO_CONFIRMABLE } = require('./validacion');

function json(res, codigo, cuerpo) {
  res.statusCode = codigo;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(cuerpo));
}

const SITIO_IDS = new Set(SITIOS.map((s) => s.id));
const MAG_IDS = new Set(MAGNITUDES.map((m) => m.id));

function normalizarConfirmacion(cuerpo) {
  let d;
  try {
    d = JSON.parse(cuerpo);
  } catch {
    return { error: 'El cuerpo no es JSON válido.' };
  }
  if (!d || typeof d !== 'object' || Array.isArray(d)) {
    return { error: 'El cuerpo tiene que ser un objeto.' };
  }

  const anio = Number(d.anio);
  const mes = Number(d.mes);
  if (!Number.isInteger(anio) || anio < 2024 || anio > 2100) {
    return { error: `Año inválido: ${d.anio}.` };
  }
  if (!Number.isInteger(mes) || mes < 1 || mes > 12) {
    return { error: `Mes inválido: ${d.mes}.` };
  }
  if (!SITIO_IDS.has(d.sitio)) {
    return { error: `Sitio desconocido: ${d.sitio}.` };
  }
  if (!MAG_IDS.has(d.magnitud)) {
    return { error: `Magnitud desconocida: ${d.magnitud}.` };
  }
  if (!CODIGOS_AVISO_CONFIRMABLE.includes(d.codigo)) {
    return {
      error:
        'Solo se confirman avisos de salto atípico. Un valor negativo, un denominador ' +
        'en cero o un mes incompleto no se confirma: se corrige, con "Consultar y corregir".',
    };
  }

  const confirmadoPor = typeof d.confirmadoPor === 'string' ? d.confirmadoPor.trim() : '';
  if (!confirmadoPor) {
    return { error: 'Falta quién confirma. La bitácora tiene que poder nombrarlo.' };
  }
  if (confirmadoPor.length > 60) {
    return { error: 'El nombre de quien confirma no puede pasar de 60 caracteres.' };
  }

  const nota = typeof d.nota === 'string' ? d.nota.trim() : '';
  if (nota.length > 300) {
    return { error: 'La nota no puede pasar de 300 caracteres.' };
  }

  return {
    anio,
    mes,
    sitio: String(d.sitio),
    magnitud: String(d.magnitud),
    codigo: String(d.codigo),
    confirmadoPor,
    nota: nota || null,
  };
}

/** Atiende una peticion de confirmacion de aviso. Devuelve true si la ruta era suya. */
async function atender(req, res, url) {
  const ruta = url.pathname.replace(/\/+$/, '');

  if (ruta === '/api/ehs/aviso/confirmar' && req.method === 'POST') {
    let cuerpo = '';
    try {
      cuerpo = await new Promise((resolve, reject) => {
        let total = 0;
        const trozos = [];
        req.on('data', (t) => {
          total += t.length;
          if (total > 4 * 1024) {
            const e = new Error('El cuerpo de la petición es demasiado grande.');
            req.destroy();
            reject(e);
            return;
          }
          trozos.push(t);
        });
        req.on('end', () => resolve(Buffer.concat(trozos).toString('utf8')));
        req.on('error', reject);
      });
    } catch (err) {
      json(res, 413, { error: 'cuerpo_invalido', mensaje: err.message, detalle: null });
      return true;
    }

    const c = normalizarConfirmacion(cuerpo);
    if (c.error) {
      errores.parametroInvalido(res, c.error);
      return true;
    }

    try {
      json(res, 200, await escritura.confirmarAviso(c));
    } catch (err) {
      errores.interno(res, err);
    }
    return true;
  }

  if (ruta === '/api/ehs/aviso/confirmar') {
    res.statusCode = 405;
    res.setHeader('Allow', 'POST');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.end(
      JSON.stringify({
        error: 'metodo_no_permitido',
        mensaje: `${req.method} no se admite en ${ruta}.`,
        detalle: null,
      })
    );
    return true;
  }

  return false;
}

module.exports = { atender };
