/**
 * Render de la pagina del tablero. Una sola vista EJS; el dato llega por fetch a
 * /api/ehs/* desde el cliente — la pagina solo lleva la cabecera (corte, fuente).
 */
const path = require('path');
const ejs = require('ejs');
const datos = require('./datos');

const VISTAS = path.join(__dirname, '..', 'views');

async function dashboard(_req, res) {
  // sin anio ni mes: el adaptador resuelve el corte publicado
  const pan = await datos.panorama({ ambito: 'nacional' });
  const html = await ejs.renderFile(
    path.join(VISTAS, 'dashboard.ejs'),
    {
      titulo: 'Tablero EHS 2026 · Servioptica',
      anio: pan ? pan.anio : new Date().getFullYear(),
      corte: pan ? pan.corte : { mes: null, nombre: '—', mesesConDato: [] },
      actualizadoEn: pan ? pan.actualizado_en : null,
      fuente: pan ? pan.fuente : '',
      metaVigente: pan ? pan.meta_vigente : '',
    },
    { rmWhitespace: false }
  );
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(html);
}

/**
 * La pagina de captura. Se dibuja desde el servidor con la lista de magnitudes y
 * sitios ya dentro: si el formulario los pidiera por fetch, una red lenta enseñaria
 * una rejilla vacia justo cuando la persona viene a teclear.
 */
async function captura(_req, res) {
  const { MAGNITUDES, SITIOS } = require('./validacion');
  const modo = process.env.ORIGEN_DATOS === 'sql' ? 'sql' : 'simulado';

  const html = await ejs.renderFile(
    path.join(VISTAS, 'captura.ejs'),
    {
      titulo: 'Captura mensual EHS · Servioptica',
      magnitudes: MAGNITUDES,
      sitios: SITIOS,
      modo,
      anio: new Date().getFullYear(),
    },
    { rmWhitespace: false }
  );
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(html);
}

/**
 * La pantalla "Consultar y corregir". Se dibuja con año/sitio/magnitud fijos como en
 * captura.ejs; el cliente pide /api/ehs/detalle para mostrar el valor actual y manda
 * la correccion a /api/ehs/correccion. No es la misma pantalla que captura: aquella
 * entra dato nuevo del mes, esta arregla un dato que ya entró, con un motivo que
 * queda escrito y archivado (R.5.3.4, ver migración 0009).
 */
async function corregir(_req, res) {
  const { MAGNITUDES, SITIOS, MOTIVO_MINIMO_CORRECCION } = require('./validacion');
  const modo = process.env.ORIGEN_DATOS === 'sql' ? 'sql' : 'simulado';

  const html = await ejs.renderFile(
    path.join(VISTAS, 'corregir.ejs'),
    {
      titulo: 'Consultar y corregir · EHS · Servióptica',
      magnitudes: MAGNITUDES,
      sitios: SITIOS,
      modo,
      anio: new Date().getFullYear(),
      motivoMinimo: MOTIVO_MINIMO_CORRECCION,
    },
    { rmWhitespace: false }
  );
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(html);
}

/**
 * La pantalla "Descargar reporte": un resumen imprimible del corte publicado, sin los
 * graficos interactivos del tablero. R.5.2.1/R.5.2.2 siguen mandando aquí: los
 * cinco valores y sus estados los calcula la misma capa de datos, nunca la plantilla.
 */
async function reporte(_req, res, url) {
  const ambito = (url && url.searchParams.get('ambito')) || 'nacional';
  const pan = await datos.panorama({ ambito });

  const html = await ejs.renderFile(
    path.join(VISTAS, 'reporte.ejs'),
    {
      titulo: 'Reporte EHS · Servióptica',
      ambito,
      pan,
      generadoEn: new Date().toISOString(),
    },
    { rmWhitespace: false }
  );
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(html);
}

module.exports = { dashboard, captura, corregir, reporte };
