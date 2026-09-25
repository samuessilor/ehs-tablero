/**
 * Cliente de "Descargar reporte". Un bloque "01 mensual/YTD/meta + 02 contra el
 * año anterior" por KPI, con el mismo formato visual que ya usa el tablero
 * (Graficos.aguaCombo/energiaCombo/serieKpi/trayectoria) — la referencia es
 * INDICADORES A CORTE JULIO DE 2026.docx, que Samuel armó a mano pantallazo por
 * pantallazo del propio tablero antes de que existiera este botón. Aquí no se
 * calcula ningún indicador (R.5.2.1/R.5.2.2): solo se pide y se dibuja.
 */
/* global Graficos, Fmt */
(function () {
  'use strict';

  function $(sel) {
    return document.querySelector(sel);
  }
  function $all(sel) {
    return Array.prototype.slice.call(document.querySelectorAll(sel));
  }

  function ambitoElegido() {
    return new URLSearchParams(location.search).get('ambito') || 'nacional';
  }

  async function api(ruta, params) {
    var qs = new URLSearchParams(params || {});
    var r = await fetch('/api/ehs/' + ruta + (qs.toString() ? '?' + qs.toString() : ''));
    if (!r.ok) return null;
    return r.json();
  }

  var COMBO = {
    agua_por_lente: { endpoint: 'agua-mensual', dibujar: Graficos.aguaCombo, campoConsumo: 'consumo_m3' },
    energia_por_lente: {
      endpoint: 'energia-mensual',
      dibujar: Graficos.energiaCombo,
      campoConsumo: 'consumo_kwh',
    },
  };

  /** Texto del panel 01: mismo tono que textoVariacion/textoContraMeta del tablero,
   * reescrito aquí porque tablero.js no expone sus funciones internas y este
   * reporte es un documento aparte, no una vista más del SPA. */
  function textoMensual(k, filas) {
    if (COMBO[k.kpi_id] && filas && filas.length >= 2) {
      var ult = filas[filas.length - 1];
      var prev = filas[filas.length - 2];
      if (ult.var_por_lente_pct != null) {
        return (
          'El consumo por lente ' +
          (ult.var_por_lente_pct < 0 ? 'baja' : ult.var_por_lente_pct > 0 ? 'sube' : 'se mantiene') +
          ' ' +
          Fmt.pctDirecto(Math.abs(ult.var_por_lente_pct)).replace('+', '') +
          ' contra ' +
          (prev.nombre_mes || 'el mes anterior') +
          ', con el consumo total en ' +
          Fmt.pctDirecto(ult.var_total_pct) +
          '.'
        );
      }
    }
    if (k.meta == null) return 'Este ámbito no tiene meta propia publicada para ' + k.kpi + '.';
    var brecha = k.brecha_pct == null ? null : Math.abs(k.brecha_pct * 100);
    return (
      'Acumulado del año: ' +
      Fmt.num(k.valor, k.dec) +
      ' ' +
      k.unidad +
      ', ' +
      (k.estado === 'cumple' ? 'dentro de la meta de ' : 'por encima de la meta de ') +
      Fmt.meta(k.meta, k.dec) +
      (brecha == null ? '.' : ' (' + Fmt.num(brecha, 1) + ' % ' + (k.estado === 'cumple' ? 'por debajo' : 'por encima') + ').')
    );
  }

  function textoTrayectoria(t) {
    var cerrados = t.anios.filter(function (a) {
      return a.cerrado;
    });
    if (!cerrados.length) return 'Sin cierres anteriores cargados todavía para este ámbito.';
    var ult = cerrados[cerrados.length - 1];
    var pri = cerrados[0];
    var txt = '';
    if (cerrados.length >= 2) {
      txt +=
        'Entre ' +
        pri.anio +
        ' y ' +
        ult.anio +
        ' ' +
        (ult.real > pri.real ? 'subió' : ult.real < pri.real ? 'bajó' : 'se mantuvo') +
        ' de ' +
        Fmt.num(pri.real, t.dec) +
        ' a ' +
        Fmt.num(ult.real, t.dec) +
        '. ';
    }
    if (t.en_curso) {
      txt +=
        'El acumulado de ' +
        t.en_curso.hasta_mes +
        ' meses de ' +
        t.en_curso.anio +
        ' va en ' +
        Fmt.num(t.en_curso.ytd, t.dec) +
        '; no es un cierre, no se compara de igual a igual contra años completos.';
    }
    return txt || 'Sin cierres anteriores cargados todavía para este ámbito.';
  }

  async function pintarBloque(kpiId, ambito) {
    var cfg = COMBO[kpiId];
    var filas = null;

    if (cfg) {
      var r = await api(cfg.endpoint, { ambito: ambito });
      filas = r ? r.filas : null;
      if (filas && filas.length) {
        $('#sub1-' + kpiId).textContent = (r.ambito && r.ambito.nombre) || '';
        cfg.dibujar('g1-' + kpiId, filas);
      }
    } else {
      var serie = await api('serie-mensual', { ambito: ambito, kpi: kpiId });
      if (serie) {
        $('#sub1-' + kpiId).textContent = (serie.ambito && serie.ambito.nombre) || '';
        Graficos.serieKpi('g1-' + kpiId, serie);
      }
    }

    var tray = await api('trayectoria-anual', { kpi: kpiId, ambito: ambito });
    var textoTray = '';
    if (tray) {
      $('#sub2-' + kpiId).textContent = tray.perimetro || '';
      Graficos.trayectoria('g2-' + kpiId, tray);
      textoTray = textoTrayectoria(tray);
    } else {
      $('#g2-' + kpiId).parentElement.style.display = 'none';
    }

    var kTarjeta = window.__repKpis[kpiId];
    var partes = [textoMensual(kTarjeta, filas)];
    if (textoTray) partes.push(textoTray);
    $('#texto-' + kpiId).innerHTML = partes.map(Fmt.esc).join(' ');
  }

  /* -------------------------------------------------------- modal de seleccion */
  function abrirModal() {
    $('#modalDescarga').classList.add('abierto');
  }
  function cerrarModal() {
    $('#modalDescarga').classList.remove('abierto');
  }
  function confirmarDescarga() {
    $all('#listaCheck input[type=checkbox]').forEach(function (cb) {
      var bloque = $('#bloque-' + cb.dataset.kpi);
      if (!bloque) return;
      if (cb.checked) bloque.removeAttribute('data-excluido');
      else bloque.setAttribute('data-excluido', '');
    });
    cerrarModal();
    window.print();
  }

  async function iniciar() {
    var ambito = ambitoElegido();
    var bloques = $all('.rep-kpi');
    if (!bloques.length) return;

    // los datos de las tarjetas ya vinieron server-side en la tabla de arriba; se
    // vuelven a pedir aqui porque reporte.ejs no expone pan.kpi como JSON al cliente
    var pan = await api('panorama', { ambito: ambito });
    window.__repKpis = {};
    (pan ? pan.kpi : []).forEach(function (k) {
      window.__repKpis[k.kpi_id] = k;
    });

    for (var i = 0; i < bloques.length; i++) {
      await pintarBloque(bloques[i].dataset.kpi, ambito);
    }

    var btn = $('#btnDescargar');
    if (btn) btn.addEventListener('click', abrirModal);
    var cancelar = $('#btnCancelar');
    if (cancelar) cancelar.addEventListener('click', cerrarModal);
    var confirmar = $('#btnConfirmar');
    if (confirmar) confirmar.addEventListener('click', confirmarDescarga);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
