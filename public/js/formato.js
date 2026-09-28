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

  /**
   * Una META, con los decimales del KPI pero sin esconder los suyos: la meta de
   * accidentes de Celta es 1,9 y con los 0 decimales del KPI se leia "2", mientras el
   * estado se calculaba contra 1,9 ("1 · meta 2 · -47 %" no cuadraba a ojo). Hasta 2
   * decimales propios, que es lo que traen las metas del scorecard (228,45).
   */
  function meta(v, dec) {
    if (v === null || v === undefined || (typeof v === 'number' && !isFinite(v))) return '—';
    var d = dec === undefined ? 0 : dec;
    return Number(v).toLocaleString('es-CO', {
      minimumFractionDigits: d,
      maximumFractionDigits: Math.max(d, 2),
    });
  }

  /** La brecha contra la meta (0,097 -> -9,7 %), con el signo invertido a proposito:
   *  los cinco KPI del area son TECHO (menos es mejor), y v=(valor-meta)/meta viene
   *  positivo cuando se supera el techo (malo) y negativo cuando se queda por debajo
   *  (bueno). Mostrado tal cual se leia al reves de la intuicion de quien lo mira:
   *  bueno con signo negativo, malo con signo positivo. Aqui se invierte SOLO para
   *  pantalla, para que quedar por debajo de la meta se lea en positivo y superarla
   *  en negativo - el calculo de estado (cumple/riesgo/incumple) no usa esta funcion
   *  y sigue igual. */
  function pct(v, dec) {
    if (v === null || v === undefined) return '—';
    var n = -v * 100;
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

  /* Una hora que la base manda como ISO sin zona (sysdatetime(), hora de Colombia) o
   * que el driver serializa con una 'Z' que no le corresponde (mssql: un datetime2
   * SIN zona sale como Date, y JSON.stringify le pega una 'Z' de mas). Las dos formas
   * traen los mismos digitos de pared; se leen tal cual, sin pasar por new Date() -
   * eso fue justo el bug que corrio el header 5 horas en Vercel (paginas.js,
   * fechaLegible). Antes vivia solo en corregir.js; ahora aca para que tablero.js
   * (confirmacion de avisos) no la duplique otra vez. */
  function fechaHora(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(iso || ''));
    return m ? m[3] + '/' + m[2] + '/' + m[1] + ' ' + m[4] + ':' + m[5] : String(iso || '—');
  }

  return {
    mesCorto: CORTO,
    mesLargo: LARGO,
    mesMini: MINI,
    num: num,
    meta: meta,
    pct: pct,
    pctDirecto: pctDirecto,
    esc: esc,
    fechaHora: fechaHora,
  };
})();
