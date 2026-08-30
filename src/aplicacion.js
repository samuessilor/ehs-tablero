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
const errores = require('./errores');

async function atender(req, res) {
  const url = new URL(req.url, 'http://interno');

  if (req.method !== 'GET') {
    errores.parametroInvalido(res, 'Este tablero solo responde consultas (GET).');
    return;
  }

  if (await api.atender(req, res, url)) return;

  const ruta = url.pathname.replace(/\/+$/, '') || '/';
  if (ruta === '/' || ruta === '/index.html') {
    try {
      await paginas.dashboard(req, res);
    } catch (err) {
      errores.interno(res, err);
    }
    return;
  }

  errores.noEncontrado(res, `No existe la pagina ${ruta}.`);
}

module.exports = { atender };
