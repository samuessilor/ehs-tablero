/**
 * El enrutador unico, compartido por el servidor local (servidor.js) y la funcion
 * de Vercel (api/servidor.js). Una sola implementacion de rutas.
 *
 * En Vercel los archivos de public/ los sirve la plataforma como estaticos; en
 * local los sirve servidor.js. Aqui solo viven la pagina y la API.
 */
const { URL } = require('url');
const paginas = require('./paginas');
const api = require('./rutas_api');
const captura = require('./rutas_captura');
const correccion = require('./rutas_correccion');
const errores = require('./errores');

/* La aplicacion nacio siendo de solo lectura y rechazaba todo lo que no fuera GET. La
   captura obliga a abrir el paso a POST, y se abre por el hueco mas estrecho posible:
   dos rutas, resueltas antes de cualquier otra cosa. Todo lo demas sigue rechazando
   igual que antes, asi que la superficie que escribe se puede leer entera en dos
   archivos (src/rutas_captura.js, src/rutas_correccion.js) en vez de estar repartida. */
const RUTAS_QUE_ESCRIBEN = ['/api/ehs/captura', '/api/ehs/correccion'];

async function atender(req, res) {
  const url = new URL(req.url, 'http://interno');
  const ruta = url.pathname.replace(/\/+$/, '') || '/';

  if (ruta === '/api/ehs/captura' || ruta.startsWith('/api/ehs/captura/')) {
    if (await captura.atender(req, res, url)) return;
  }

  if (ruta === '/api/ehs/correccion' || ruta.startsWith('/api/ehs/correccion/')) {
    if (await correccion.atender(req, res, url)) return;
  }

  if (req.method !== 'GET') {
    errores.parametroInvalido(
      res,
      `Este tablero solo responde consultas (GET). Lo unico que admite escritura es ${RUTAS_QUE_ESCRIBEN.join(', ')}.`
    );
    return;
  }

  if (await api.atender(req, res, url)) return;

  if (ruta === '/' || ruta === '/index.html') {
    try {
      await paginas.dashboard(req, res);
    } catch (err) {
      errores.pagina(res, err);
    }
    return;
  }

  if (ruta === '/captura' || ruta === '/captura.html') {
    try {
      await paginas.captura(req, res);
    } catch (err) {
      errores.pagina(res, err);
    }
    return;
  }

  if (ruta === '/corregir' || ruta === '/corregir.html') {
    try {
      await paginas.corregir(req, res);
    } catch (err) {
      errores.pagina(res, err);
    }
    return;
  }

  if (ruta === '/reporte' || ruta === '/reporte.html') {
    try {
      await paginas.reporte(req, res, url);
    } catch (err) {
      errores.pagina(res, err);
    }
    return;
  }

  errores.noEncontrado(res, `No existe la pagina ${ruta}.`);
}

module.exports = { atender };
