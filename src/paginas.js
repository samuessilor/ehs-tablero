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

module.exports = { dashboard };
