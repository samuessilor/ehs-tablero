/**
 * Formato de numeros, meses y texto. Vive aparte porque lo usan los tres modulos del
 * cliente y tenerlo tres veces era la unica duplicacion real que quedaba.
 *
 * Ninguna funcion de aqui decide nada sobre el dato: solo lo escribe.
 */
var Fmt = (function () {
  'use strict';

  var CORTO = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];
  var LARGO = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  var MINI = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  function num(v, dec) {
    if (v === null || v === undefined || (typeof v === 'number' && !isFinite(v))) return '—';
    return Number(v).toLocaleString('es-CO', {
      minimumFractionDigits: dec === undefined ? 0 : dec,
      maximumFractionDigits: dec === undefined ? 0 : dec,
    });
  }

  /** Una fraccion (0,097) escrita como porcentaje con signo (+9,7 %). */
  function pct(v, dec) {
    if (v === null || v === undefined) return '—';
    var n = v * 100;
    return (n > 0 ? '+' : '') + num(n, dec === undefined ? 1 : dec) + ' %';
  }

  /** Un porcentaje que ya viene en unidades de porcentaje (1,61 -> +1,61 %). */
  function pctDirecto(v, dec) {
    return v === null || v === undefined
      ? '—'
      : (v > 0 ? '+' : '') + num(v, dec === undefined ? 2 : dec) + ' %';
  }

  function esc(t) {
    return String(t).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  return {
    mesCorto: CORTO,
    mesLargo: LARGO,
    mesMini: MINI,
    num: num,
    pct: pct,
    pctDirecto: pctDirecto,
    esc: esc,
  };
})();
