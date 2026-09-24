/**
 * Servidor LOCAL de desarrollo: node servidor.js
 *
 * node:http nativo — Express no esta en la tabla del estandar y R.3.4 prohibe
 * introducir dependencias sin acuerdo con IT. Para una pagina y nueve GET, un
 * enrutador propio de sesenta lineas basta. En Vercel el punto de entrada es
 * api/servidor.js; ambos delegan en src/aplicacion.js.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');
const aplicacion = require('./src/aplicacion');
const { obtener } = require('./src/datos/configuracion');
const respaldo = require('./src/respaldo');
const { asegurarDockerDesktop } = require('./src/arranque_motor');

// Por configuracion y no solo por entorno: la tarea programada que arranca el
// tablero en el equipo del area no le pasa ninguna variable, asi que todo tiene que
// poder salir de config\ehs.env (ver src/datos/configuracion.js).
const PUERTO = Number(obtener('PUERTO')) || 3000;
// 127.0.0.1 por defecto, no todas las interfaces: sin host explicito, listen() abre
// el puerto hacia la red y Windows pide una excepcion de firewall la primera vez —
// justo la ventana que quien usa el tablero nunca debe ver. El servidor propio de la
// fase 1 si necesitara escuchar en la red; para eso se fija HOST en su config.
const HOST = obtener('HOST') || '127.0.0.1';
const PUBLICO = path.join(__dirname, 'public');
const MIME = {
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
};

function estatico(req, res, url) {
  // en produccion esto lo hace Vercel; aqui se imita para probar igual
  const limpio = path.normalize(url.pathname).replace(/^([.]{2}[/\\])+/, '');
  const archivo = path.join(PUBLICO, limpio);
  if (!archivo.startsWith(PUBLICO) || !fs.existsSync(archivo) || !fs.statSync(archivo).isFile()) {
    return false;
  }
  res.statusCode = 200;
  res.setHeader('Content-Type', MIME[path.extname(archivo)] || 'application/octet-stream');
  fs.createReadStream(archivo).pipe(res);
  return true;
}

http
  .createServer((req, res) => {
    const url = new URL(req.url, 'http://interno');
    if (estatico(req, res, url)) return;
    aplicacion.atender(req, res).catch((err) => {
      console.error(err);
      if (!res.headersSent) {
        res.statusCode = 500;
        res.end('{"error":"error_interno"}');
      }
    });
  })
  .listen(PUERTO, HOST, () => {
    console.log(`Tablero EHS en http://${HOST}:${PUERTO}`);
    respaldo.programarDiario();
    // en la instalacion en contenedor, abre Docker Desktop si nadie lo abrio al iniciar sesion
    asegurarDockerDesktop().then((r) => {
      if (r === 'abierto') console.log('Docker Desktop estaba cerrado: se abrio.');
    });
  });
