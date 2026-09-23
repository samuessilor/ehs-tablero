/**
 * Las dos rutas de la captura. Es la unica superficie de ESCRITURA de la aplicacion.
 *
 *   GET  /api/ehs/captura/estado?anio=2026   que meses y sitios ya estan capturados
 *   POST /api/ehs/captura                    graba (o simula) un lote
 *
 * Que sea una sola ruta la que escribe es la razon de que se pueda razonar sobre la
 * seguridad de esto: hay un punto donde entra el dato, y esta aqui.
 */
const escritura = require('./datos/escritura');
const errores = require('./errores');
const { MAGNITUDES, SITIOS } = require('./validacion');

/* Un mes son 9 magnitudes x 3 sitios = 27 filas. El tope deja sitio a capturar varios
   meses de una vez sin abrir la puerta a que alguien mande un cuerpo de 50 MB. */
const MAX_FILAS = 500;
const MAX_CUERPO = 256 * 1024;

function json(res, codigo, cuerpo) {
  res.statusCode = codigo;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(cuerpo));
}

/**
 * Lee el cuerpo con tope. Sin el tope, un cuerpo sin fin mantiene viva la conexion y
 * consume memoria del proceso: es la forma mas barata de tumbar un servidor pequeño.
 */
function leerCuerpo(req) {
  return new Promise((resolve, reject) => {
    let total = 0;
    const trozos = [];
    req.on('data', (t) => {
      total += t.length;
      if (total > MAX_CUERPO) {
        const e = new Error('El cuerpo de la peticion es demasiado grande.');
        e.codigo = 'cuerpo_grande';
        req.destroy();
        reject(e);
        return;
      }
      trozos.push(t);
    });
    req.on('end', () => resolve(Buffer.concat(trozos).toString('utf8')));
    req.on('error', reject);
  });
}

/**
 * Comprueba la FORMA de lo que llego, no su contenido: que sea un objeto, que traiga
 * las claves esperadas y que las filas sean filas. El contenido lo examina
 * src/validacion.js, y despues otra vez el procedimiento. Son tres cosas distintas y
 * ninguna sustituye a la otra.
 */
function normalizarLote(cuerpo) {
  let d;
  try {
    d = JSON.parse(cuerpo);
  } catch {
    return { error: 'El cuerpo no es JSON valido.' };
  }
  if (!d || typeof d !== 'object' || Array.isArray(d)) {
    return { error: 'El cuerpo tiene que ser un objeto.' };
  }
  if (!Array.isArray(d.filas)) {
    return { error: 'Falta la lista de filas.' };
  }
  if (d.filas.length === 0) {
    return { error: 'No hay ninguna lectura que capturar.' };
  }
  if (d.filas.length > MAX_FILAS) {
    return { error: `Un lote no puede traer mas de ${MAX_FILAS} lecturas.` };
  }
  const capturadoPor = typeof d.capturadoPor === 'string' ? d.capturadoPor.trim() : '';
  if (!capturadoPor) {
    return { error: 'Falta quién captura. La bitácora tiene que poder nombrarlo (R.5.3.4).' };
  }
  if (capturadoPor.length > 60) {
    return { error: 'El nombre de quien captura no puede pasar de 60 caracteres.' };
  }

  const filas = [];
  for (const [i, f] of d.filas.entries()) {
    if (!f || typeof f !== 'object' || Array.isArray(f)) {
      return { error: `La fila ${i + 1} no es un objeto.` };
    }
    filas.push({
      anio: Number(f.anio),
      mes: Number(f.mes),
      sitio: f.sitio == null ? null : String(f.sitio),
      magnitud: f.magnitud == null ? null : String(f.magnitud),
      // el valor viaja como texto a proposito: si no es un numero, hay que poder
      // decir QUE se escribio, y un Number() prematuro lo convertiria en NaN
      valor: f.valor == null ? null : String(f.valor),
    });
  }

  return {
    filas,
    capturadoPor,
    origen: typeof d.origen === 'string' ? d.origen.slice(0, 120) : undefined,
    confirmarAtipicos: d.confirmarAtipicos === true,
  };
}

/** Atiende una peticion de captura. Devuelve true si la ruta era suya. */
async function atender(req, res, url) {
  const ruta = url.pathname.replace(/\/+$/, '');

  if (ruta === '/api/ehs/captura/estado' && req.method === 'GET') {
    const crudo = url.searchParams.get('anio');
    const anio = crudo ? Number(crudo) : new Date().getFullYear();
    if (!Number.isInteger(anio) || anio < 2023 || anio > 2100) {
      errores.parametroInvalido(res, `Año invalido: ${crudo}.`);
      return true;
    }
    // mes es opcional: con el, la respuesta trae ademas las celdas ya capturadas de ese mes
    const crudoMes = url.searchParams.get('mes');
    const mes = crudoMes ? Number(crudoMes) : undefined;
    if (crudoMes && (!Number.isInteger(mes) || mes < 1 || mes > 12)) {
      errores.parametroInvalido(res, `Mes invalido: ${crudoMes}.`);
      return true;
    }
    try {
      json(res, 200, await escritura.estadoCaptura({ anio, mes }));
    } catch (err) {
      errores.interno(res, err);
    }
    return true;
  }

  if (ruta === '/api/ehs/captura/formulario' && req.method === 'GET') {
    // Lo que el formulario necesita para dibujarse. Viene del servidor y no del
    // cliente para que la lista de magnitudes tenga UNA definicion (src/validacion.js)
    // y no dos que puedan separarse.
    json(res, 200, { magnitudes: MAGNITUDES, sitios: SITIOS, modo: escritura.modo || undefined });
    return true;
  }

  if (ruta === '/api/ehs/captura' && req.method === 'POST') {
    let cuerpo;
    try {
      cuerpo = await leerCuerpo(req);
    } catch (err) {
      json(res, 413, {
        error: err.codigo || 'cuerpo_invalido',
        mensaje: err.message,
        detalle: null,
      });
      return true;
    }

    const lote = normalizarLote(cuerpo);
    if (lote.error) {
      errores.parametroInvalido(res, lote.error);
      return true;
    }

    try {
      const r = await escritura.capturarLote(lote);
      // 200 aunque haya rechazos: la peticion se atendio bien y el resultado es
      // justamente el reparto entre lo que entro y lo que no. Un 4xx aqui haria creer
      // al cliente que no se grabo nada, y si se grabo.
      json(res, 200, r);
    } catch (err) {
      errores.interno(res, err);
    }
    return true;
  }

  // La ruta existe pero con otro metodo: decirlo explicitamente evita que parezca que
  // no existe, que manda a buscar el problema al sitio equivocado.
  if (ruta === '/api/ehs/captura' || ruta.startsWith('/api/ehs/captura/')) {
    res.statusCode = 405;
    res.setHeader('Allow', ruta === '/api/ehs/captura' ? 'POST' : 'GET');
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

module.exports = { atender, MAX_FILAS, MAX_CUERPO };
