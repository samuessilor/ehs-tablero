/**
 * Las dos rutas de "Consultar y corregir": arreglar UN valor ya capturado, con un
 * motivo que quede escrito. Distinta de src/rutas_captura.js a propósito — esa es la
 * puerta del mes completo; esta es la puerta de un valor puntual que alguien nota
 * después que está mal.
 *
 *   GET  /api/ehs/correccion/historial?anio=2026   las correcciones ya hechas
 *   POST /api/ehs/correccion                       corrige un valor, con motivo
 *
 * El grid con los valores actuales para elegir qué corregir no es una ruta nueva:
 * es /api/ehs/detalle, que ya existe y ya lee lo mismo.
 */
const escritura = require('./datos/escritura');
const errores = require('./errores');
const {
  MAGNITUDES,
  SITIOS,
  MOTIVO_MINIMO_CORRECCION,
  examinarCorreccion,
} = require('./validacion');

function json(res, codigo, cuerpo) {
  res.statusCode = codigo;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(cuerpo));
}

const MAG_IDS = new Set(MAGNITUDES.map((m) => m.id));
const SITIO_IDS = new Set(SITIOS.map((s) => s.id));

function normalizarCorreccion(cuerpo) {
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
  if (d.valor === null || d.valor === undefined || String(d.valor).trim() === '') {
    return {
      error:
        'Falta el valor nuevo. Para borrar una lectura, pide a IT que la borre — esta puerta corrige, no elimina.',
    };
  }

  const corregidoPor = typeof d.corregidoPor === 'string' ? d.corregidoPor.trim() : '';
  if (!corregidoPor) {
    return { error: 'Falta quién corrige. La bitácora tiene que poder nombrarlo (R.5.3.4).' };
  }
  if (corregidoPor.length > 60) {
    return { error: 'El nombre de quien corrige no puede pasar de 60 caracteres.' };
  }

  const motivo = typeof d.motivo === 'string' ? d.motivo.trim() : '';
  if (motivo.length < MOTIVO_MINIMO_CORRECCION) {
    return {
      error: `El motivo tiene que explicar algo, no solo llenar el campo (mínimo ${MOTIVO_MINIMO_CORRECCION} caracteres).`,
    };
  }
  if (motivo.length > 300) {
    return { error: 'El motivo no puede pasar de 300 caracteres.' };
  }

  /* El valor se examina y se NORMALIZA aqui, con las mismas reglas que la captura
     (src/validacion.js). Antes viajaba como texto hasta el driver, que lo convierte
     con parseFloat: "979,1" se grababa 979 y "108.543" (punto de miles) 108,543, sin
     aviso y con "Correccion grabada" en pantalla. Ahora la coma es decimal, el punto
     de miles ambiguo se rechaza con un mensaje que dice como escribirlo, un negativo
     o un texto vuelven como 400 legible, y un atipico pide confirmacion (409). */
  const r = examinarCorreccion({ magnitud: String(d.magnitud), valor: d.valor, motivo });
  if (r.error) return { error: r.error };
  if (r.advertencia && d.confirmarAtipico !== true) {
    return { atipico: r.advertencia, valor: r.valor };
  }

  return {
    anio,
    mes,
    sitio: String(d.sitio),
    magnitud: String(d.magnitud),
    valor: r.valor,
    motivo,
    corregidoPor,
  };
}

/** Atiende una peticion de correccion. Devuelve true si la ruta era suya. */
async function atender(req, res, url) {
  const ruta = url.pathname.replace(/\/+$/, '');

  if (ruta === '/api/ehs/correccion/historial' && req.method === 'GET') {
    const crudo = url.searchParams.get('anio');
    const anio = crudo ? Number(crudo) : new Date().getFullYear();
    if (!Number.isInteger(anio) || anio < 2024 || anio > 2100) {
      errores.parametroInvalido(res, `Año inválido: ${crudo}.`);
      return true;
    }
    try {
      json(res, 200, await escritura.historialCorrecciones({ anio }));
    } catch (err) {
      errores.interno(res, err);
    }
    return true;
  }

  if (ruta === '/api/ehs/correccion' && req.method === 'POST') {
    let cuerpo = '';
    try {
      cuerpo = await new Promise((resolve, reject) => {
        let total = 0;
        const trozos = [];
        req.on('data', (t) => {
          total += t.length;
          if (total > 8 * 1024) {
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

    const c = normalizarCorreccion(cuerpo);
    if (c.error) {
      errores.parametroInvalido(res, c.error);
      return true;
    }
    if (c.atipico) {
      // no se graba: la pantalla muestra la advertencia y un boton para confirmar
      json(res, 409, { error: 'atipico', mensaje: c.atipico, detalle: { valor: c.valor } });
      return true;
    }

    try {
      json(res, 200, await escritura.corregirLectura(c));
    } catch (err) {
      errores.interno(res, err);
    }
    return true;
  }

  if (ruta === '/api/ehs/correccion' || ruta.startsWith('/api/ehs/correccion/')) {
    res.statusCode = 405;
    res.setHeader('Allow', ruta === '/api/ehs/correccion' ? 'POST' : 'GET');
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
