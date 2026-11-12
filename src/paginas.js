/**
 * Render de la pagina del tablero. Una sola vista EJS; el dato llega por fetch a
 * /api/ehs/* desde el cliente — la pagina solo lleva la cabecera (corte, fuente).
 */
const path = require('path');
const ejs = require('ejs');
const datos = require('./datos');
const { obtener } = require('./datos/configuracion');

const VISTAS = path.join(__dirname, '..', 'views');
/* 'sql' y 'pg' graban de verdad (ver escritura.js); cualquier otro valor cae en el
   interinato sin persistencia. captura.ejs/corregir.ejs usan este modo para decidir
   si muestran el aviso de "no guarda nada". */
const ORIGEN = obtener('ORIGEN_DATOS');
const MODO = ORIGEN === 'sql' || ORIGEN === 'pg' ? ORIGEN : 'simulado';

const MESES_CORTO = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];
const MESES_LARGO = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/* "24 sep 2026 · 21:52" en vez del ISO crudo que manda la base
   ("2026-09-24T21:52:12"): mismo dato, legible sin tener que parsearlo. Se arman
   las partes a mano (no toLocaleString) porque el "de sept de" que agrega Intl en
   es-CO estorba en un rotulo compacto de header. */
function fechaLegible(iso) {
  if (!iso) return null;
  // La base guarda la hora de pared de Colombia y la manda SIN zona
  // ("2026-09-24T21:52:12"). new Date() lee un texto sin zona en la zona del
  // SERVIDOR: en el equipo del area (hora de Colombia) daba bien, pero en Vercel
  // (UTC) le restaba 5 horas — el header de Vercel decia 11:58 para un dato de las
  // 16:58. Sin zona, los componentes YA son la hora de Colombia: se leen tal cual.
  const sinZona = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(:\d{2}(\.\d+)?)?$/.exec(String(iso));
  if (sinZona) {
    return (
      Number(sinZona[3]) +
      ' ' +
      MESES_CORTO[Number(sinZona[2]) - 1] +
      ' ' +
      sinZona[1] +
      ' · ' +
      sinZona[4] +
      ':' +
      sinZona[5]
    );
  }
  const f = new Date(iso);
  if (isNaN(f)) return iso;
  const partes = {};
  new Intl.DateTimeFormat('es-CO', {
    timeZone: 'America/Bogota',
    day: 'numeric',
    month: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
    .formatToParts(f)
    .forEach((p) => (partes[p.type] = p.value));
  return (
    partes.day +
    ' ' +
    MESES_CORTO[Number(partes.month) - 1] +
    ' ' +
    partes.year +
    ' · ' +
    partes.hour +
    ':' +
    partes.minute
  );
}

/* "28 de septiembre de 2026, 12:57 p. m." para el pie del reporte impreso — hora de
   Colombia, legible en el papel que se reparte. NO toLocaleString(dateStyle/timeStyle):
   la plantilla que arma esas opciones cambia de un ICU/CLDR a otro (el mismo defecto que
   fechaLegible ya evita arriba) — un servidor daba "12:57 p. m." (espacio angosto) y
   otro "a las 12:57 p. m.", mismo instante, dos textos distintos. Solo se piden partes
   numericas (2-digit/hour12:false, siempre estables) y se arma el texto a mano. */
function fechaLargaBogota() {
  const partes = {};
  new Intl.DateTimeFormat('es-CO', {
    timeZone: 'America/Bogota',
    day: 'numeric',
    month: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
    .formatToParts(new Date())
    .forEach((p) => (partes[p.type] = p.value));
  const h24 = Number(partes.hour) % 24;
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  const meridiano = h24 < 12 ? 'a. m.' : 'p. m.';
  return (
    Number(partes.day) +
    ' de ' +
    MESES_LARGO[Number(partes.month) - 1] +
    ' de ' +
    partes.year +
    ', ' +
    h12 +
    ':' +
    partes.minute +
    ' ' +
    meridiano
  );
}

async function dashboard(_req, res) {
  // sin anio ni mes: el adaptador resuelve el corte publicado
  const pan = await datos.panorama({ ambito: 'nacional' });
  const html = await ejs.renderFile(
    path.join(VISTAS, 'dashboard.ejs'),
    {
      titulo: 'Tablero EHS 2026 · Servioptica',
      anio: pan ? pan.anio : new Date().getFullYear(),
      corte: pan ? pan.corte : { mes: null, nombre: '—', mesesConDato: [] },
      actualizadoEn: pan ? fechaLegible(pan.actualizado_en) : null,
      fuente: pan ? pan.fuente || '' : '',
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
  const modo = MODO;

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
  const modo = MODO;

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

  // con el mes en el titulo: es lo que Chrome sugiere como nombre de archivo al
  // guardar el PDF ("Reporte EHS · Servioptica · Julio 2026.pdf" en vez de un
  // nombre generico igual mes a mes, que se presta a sobrescribir el anterior sin
  // darse cuenta.
  const titulo = pan
    ? 'Reporte EHS · Servióptica · ' + pan.corte.nombre + ' ' + pan.anio
    : 'Reporte EHS · Servióptica';

  const html = await ejs.renderFile(
    path.join(VISTAS, 'reporte.ejs'),
    {
      titulo,
      ambito,
      pan,
      // hora de Colombia y legible: es lo que queda impreso en el papel que se reparte
      generadoEn: fechaLargaBogota(),
    },
    { rmWhitespace: false }
  );
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.end(html);
}

module.exports = { dashboard, captura, corregir, reporte };
