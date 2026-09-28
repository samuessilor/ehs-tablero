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
const avisos = require('./rutas_avisos');
const errores = require('./errores');
const { obtener } = require('./datos/configuracion');

/* La aplicacion nacio siendo de solo lectura y rechazaba todo lo que no fuera GET. La
   captura obliga a abrir el paso a POST, y se abre por el hueco mas estrecho posible:
   dos rutas, resueltas antes de cualquier otra cosa. Todo lo demas sigue rechazando
   igual que antes, asi que la superficie que escribe se puede leer entera en dos
   archivos (src/rutas_captura.js, src/rutas_correccion.js) en vez de estar repartida. */
const RUTAS_QUE_ESCRIBEN = ['/api/ehs/captura', '/api/ehs/correccion', '/api/ehs/aviso'];

/* Solo el propio tablero puede escribir. Sin esto, cualquier pagina web abierta en el
   mismo equipo podia mandar un POST 'text/plain' (el navegador no pregunta antes) a
   127.0.0.1 y grabar o corregir lecturas. Se exige JSON, que un Origin, si viene, sea
   el mismo del tablero, y en la instalacion con base de datos que el Host sea local
   (eso corta tambien el truco de un dominio ajeno que resuelve a 127.0.0.1). */
function motivoParaNoEscribir(req) {
  const tipo = String(req.headers['content-type'] || '').toLowerCase();
  if (!tipo.startsWith('application/json')) {
    return 'Las escrituras solo aceptan JSON (Content-Type: application/json).';
  }
  const host = String(req.headers.host || '').toLowerCase();
  if (obtener('ORIGEN_DATOS') === 'sql' && !/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(host)) {
    return 'Solo el tablero instalado en este equipo puede escribir.';
  }
  const origen = req.headers.origin;
  if (origen && !['http://' + host, 'https://' + host].includes(String(origen).toLowerCase())) {
    return 'Origen no permitido: solo el propio tablero puede escribir.';
  }
  return null;
}

async function atender(req, res) {
  const url = new URL(req.url, 'http://interno');
  const ruta = url.pathname.replace(/\/+$/, '') || '/';

  if (req.method === 'POST' && RUTAS_QUE_ESCRIBEN.some((r) => ruta.startsWith(r))) {
    const motivo = motivoParaNoEscribir(req);
    if (motivo) {
      res.statusCode = 403;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(JSON.stringify({ error: 'escritura_no_permitida', mensaje: motivo, detalle: null }));
      return;
    }
  }

  if (ruta === '/api/ehs/captura' || ruta.startsWith('/api/ehs/captura/')) {
    if (await captura.atender(req, res, url)) return;
  }

  if (ruta === '/api/ehs/correccion' || ruta.startsWith('/api/ehs/correccion/')) {
    if (await correccion.atender(req, res, url)) return;
  }

  if (ruta === '/api/ehs/aviso' || ruta.startsWith('/api/ehs/aviso/')) {
    if (await avisos.atender(req, res, url)) return;
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
