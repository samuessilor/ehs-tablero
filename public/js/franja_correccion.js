/**
 * Franja de "valor corregido": pinta las correcciones autorizadas que el servidor
 * entrega. Con la lista vacia no renderiza nada.
 *
 * El texto sale del registro de la correccion, no esta escrito aqui (R.5.2.6): quien
 * autorizo, cuando y por que son columnas del CSV, no literales de este archivo.
 */
/* global Fmt */
var FranjaCorreccion = (function () {
  'use strict';

  return {
    pintar: function (contenedorId, correcciones, nombres) {
      var cont = document.getElementById(contenedorId);
      if (!cont) return;
      if (!correcciones || !correcciones.length) {
        cont.innerHTML = '';
        return;
      }
      cont.innerHTML = correcciones
        .map(function (c) {
          var kpi = (nombres && nombres[c.magnitud]) || c.magnitud;
          return (
            '<div class="correccion">' +
            '<span class="et">Valor corregido</span>' +
            '<span class="cambio"><s>' +
            Fmt.esc(c.valorExcel) +
            '</s> → <i>' +
            Fmt.esc(c.valorCorregido) +
            '</i></span>' +
            '<span class="cuerpo"><b>' +
            Fmt.esc(kpi) +
            '</b> de <b>' +
            Fmt.esc(c.sitio) +
            '</b> en <b>' +
            Fmt.esc(Fmt.mesLargo[c.mes - 1]) +
            ' ' +
            c.anio +
            '</b>. ' +
            Fmt.esc(c.motivo) +
            '<div class="quien">Autorizado por ' +
            Fmt.esc(c.autorizadoPor) +
            ' el ' +
            Fmt.esc(c.fecha) +
            '. Todo lo que depende de este valor esta recalculado.</div></span>' +
            '</div>'
          );
        })
        .join('');
    },
  };
})();
