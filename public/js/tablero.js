/**
 * Cliente del tablero EHS. Su unico trabajo es PEDIR y DIBUJAR:
 *   - pide rebanadas a /api/ehs/* (el calculo tiene una sola implementacion y vive en
 *     la capa de datos, R.5.2.1 y R.5.2.2),
 *   - las convierte en fichas, tablas y graficas ECharts,
 *   - y redacta el texto analitico por ramas sobre los valores servidos (R.5.2.6).
 *
 * Aqui no hay ninguna formula de KPI ni ninguna comparacion contra meta: los estados y
 * las brechas llegan resueltos del servidor. Si manana cambia la banda de "en riesgo",
 * se cambia en la capa de datos y este archivo no se toca.
 */
/* global Graficos, FranjaCorreccion, Fmt */
var Tablero = (function () {
  'use strict';

  var VISTAS = [
    { id: 'panorama', rotulo: '01 Panorama' },
    { id: 'agua', rotulo: '02 Agua y Energía' },
    { id: 'ambiental', rotulo: '03 Ambiental' },
    { id: 'seguridad', rotulo: '04 Seguridad' },
    { id: 'calidad', rotulo: '05 Calidad del dato' },
    { id: 'datos', rotulo: '06 Datos' },
  ];
  var AMBITOS = [
    { id: 'colombia_peru', rotulo: 'Colombia + Perú' },
    { id: 'nacional', rotulo: 'Colombia' },
    { id: 'nacional_labs', rotulo: 'Nacional Labs' },
    { id: 'celta', rotulo: 'Celta' },
    { id: 'estrella', rotulo: 'La Estrella' },
    { id: 'peru', rotulo: 'TOPSA (Perú)' },
    { id: 'agencias', rotulo: 'Agencias' },
  ];
  var ROTULO_ESTADO = {
    cumple: 'Cumple',
    riesgo: 'En riesgo',
    incumple: 'Incumple',
    sin_meta: 'Sin meta',
    sin_dato: 'Sin dato',
  };
  var CHIP = {
    cumple: 'cumple',
    riesgo: 'riesgo',
    incumple: 'incumple',
    sin_meta: 'sinmeta',
    sin_dato: 'pend',
  };

  var S = {
    vista: 'panorama',
    ambito: 'nacional',
    mes: null,
    kpi: 'residuos_por_lente',
    anio: null,
  };
  var mesesConDato = [];
  var pintando = false;
  var pendiente = false;

  function $(sel) {
    return document.querySelector(sel);
  }
  function chip(estado, texto) {
    return (
      '<span class="chip ' +
      (CHIP[estado] || 'pend') +
      '">' +
      (texto || ROTULO_ESTADO[estado] || estado) +
      '</span>'
    );
  }
  function nota(html) {
    return '<div class="nota">' + html + '</div>';
  }
  async function api(recurso, params) {
    var q = new URLSearchParams();
    if (S.anio) q.set('anio', S.anio);
    Object.keys(params || {}).forEach(function (k) {
      if (params[k] !== null && params[k] !== undefined) q.set(k, params[k]);
    });
    var r = await fetch('/api/ehs/' + recurso + (q.toString() ? '?' + q.toString() : ''));
    if (!r.ok) throw new Error(recurso + ' -> ' + r.status);
    return r.json();
  }

  /* --------------------------------------------------------- el estado en la URL --- */
  function leerUrl() {
    var q = new URLSearchParams(location.search);
    if (
      VISTAS.some(function (v) {
        return v.id === q.get('vista');
      })
    )
      S.vista = q.get('vista');
    if (
      AMBITOS.some(function (a) {
        return a.id === q.get('sitio');
      })
    )
      S.ambito = q.get('sitio');
    var m = parseInt(q.get('mes'), 10);
    if (m >= 1 && m <= 12) S.mes = m;
    if (q.get('kpi')) S.kpi = q.get('kpi');
  }
  function escribirUrl() {
    history.replaceState(
      null,
      '',
      '?' +
        new URLSearchParams({ vista: S.vista, sitio: S.ambito, mes: S.mes, kpi: S.kpi }).toString()
    );
  }

  /* ------------------------------------------------------------------ controles --- */
  function construirControles() {
    // class="tab" y los dos span: ehs.css estiliza '.nav-in .tab', con el numero (.n)
    // y el rotulo (.l) por separado. Sin ellos las pestañas salian como botones
    // blancos del navegador sobre el rail oscuro.
    $('#navVistas').innerHTML = VISTAS.map(function (v) {
      var i = v.rotulo.indexOf(' ');
      return (
        '<button type="button" class="tab" id="tab-' +
        v.id +
        '" role="tab" data-vista="' +
        v.id +
        '"><span class="n">' +
        v.rotulo.slice(0, i) +
        '</span><span class="l">' +
        v.rotulo.slice(i + 1) +
        '</span></button>'
      );
    }).join('');
    $('#segSitio').innerHTML = AMBITOS.map(function (a) {
      return '<button type="button" data-ambito="' + a.id + '">' + a.rotulo + '</button>';
    }).join('');
    $('#segMes').innerHTML = Fmt.mesCorto
      .map(function (m, i) {
        var hay = mesesConDato.indexOf(i + 1) >= 0;
        return (
          '<button type="button" data-mes="' +
          (i + 1) +
          '"' +
          (hay
            ? ' title="' + Fmt.mesLargo[i] + '"'
            : ' disabled title="' + Fmt.mesLargo[i] + ' · próximamente"') +
          '>' +
          m +
          '</button>'
        );
      })
      .join('');

    document.body.addEventListener('click', function (e) {
      var b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.vista) S.vista = b.dataset.vista;
      else if (b.dataset.ambito) S.ambito = b.dataset.ambito;
      else if (b.dataset.mes) S.mes = parseInt(b.dataset.mes, 10);
      else if (b.dataset.kpi) S.kpi = b.dataset.kpi;
      else return;
      render();
    });
  }

  function marcarControles() {
    document.querySelectorAll('#navVistas button').forEach(function (b) {
      b.setAttribute('aria-selected', String(b.dataset.vista === S.vista));
    });
    document.querySelectorAll('#segSitio button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.ambito === S.ambito));
    });
    document.querySelectorAll('#segMes button').forEach(function (b) {
      b.setAttribute('aria-pressed', String(parseInt(b.dataset.mes, 10) === S.mes));
    });
    VISTAS.forEach(function (v) {
      var sec = document.getElementById('v-' + v.id);
      if (sec) sec.hidden = v.id !== S.vista;
    });
  }

  /* -------------------------------------------------------------------- fichas --- */
  function ficha(k, pref) {
    var pie =
      k.meta === null
        ? 'Sin meta publicada para este ámbito'
        : (k.es_referencia ? 'Referencia ' : 'Meta ') +
          Fmt.meta(k.meta, k.dec) +
          (k.es_referencia ? ' · COLOMBIA y PERÚ' : ' · techo');
    return (
      '<button type="button" class="kcard" data-kpi="' +
      k.kpi_id +
      '" aria-pressed="' +
      String(k.kpi_id === S.kpi) +
      '" title="Poner ' +
      Fmt.esc(k.kpi) +
      ' en foco">' +
      '<div class="khead"><span class="kn">' +
      Fmt.esc(k.kpi) +
      '</span><span class="ku">' +
      Fmt.esc(k.unidad) +
      '</span></div>' +
      '<div class="kv num">' +
      Fmt.num(k.valor, k.dec) +
      '<small>YTD</small></div>' +
      '<div class="krow">' +
      chip(k.estado) +
      (k.brecha_pct === null
        ? ''
        : '<span class="kmeta"><b>' + Fmt.pct(k.brecha_pct) + '</b> vs meta</span>') +
      '</div><div class="kmeta">' +
      Fmt.esc(pie) +
      '</div>' +
      '<div class="kspark" id="spark-' +
      pref +
      '-' +
      k.kpi_id +
      '"></div></button>'
    );
  }

  function pintarFichas(sel, lista, pref) {
    $(sel).innerHTML = lista
      .map(function (k) {
        return ficha(k, pref);
      })
      .join('');
    lista.forEach(function (k) {
      Graficos.sparkline('spark-' + pref + '-' + k.kpi_id, k.serie_ytd, k.estado, k.meta);
    });
  }

  /* El mes al que estan acumuladas las cifras en pantalla: el elegido arriba, o el
     corte si no se eligio ninguno. Los rotulos decian siempre el corte ("acumulado a
     Julio") aunque las fichas mostraran el YTD de marzo. */
  function mesElegido(pan) {
    return S.mes ? Fmt.mesLargo[S.mes - 1] : pan.corte.nombre;
  }

  /* ------------------------------------------------- texto analitico, calculado --- */
  function textoContraMeta(k) {
    if (k.meta === null) {
      return (
        '<b>Sin meta asignada.</b> El scorecard corporativo no publica meta para este ámbito. ' +
        'No se compara contra la de otro: se dice.'
      );
    }
    // solo hasta el mes elegido: con marzo elegido, el rumbo es febrero -> marzo, no
    // junio -> julio (que es lo que decia antes, sobre el YTD de marzo)
    var serie = k.serie_ytd.filter(function (p) {
      return p.valor !== null && (!S.mes || p.mes <= S.mes);
    });
    var ult = serie[serie.length - 1];
    var ant = serie[serie.length - 2];
    var rumbo = '';
    if (ult && ant && ult.brecha_pct !== null && ant.brecha_pct !== null) {
      // todos los KPI son techo: la brecha que BAJA es margen que se gana, este el
      // acumulado por encima o por debajo del techo
      var delta = ult.brecha_pct - ant.brecha_pct;
      rumbo =
        delta < 0
          ? ' Gana margen contra el techo respecto del mes anterior.'
          : delta > 0
            ? ' Pierde margen contra el techo respecto del mes anterior.'
            : '';
    }
    return (
      '<b>' +
      ROTULO_ESTADO[k.estado] +
      '.</b> Acumulado ' +
      Fmt.num(k.valor, k.dec) +
      ' ' +
      Fmt.esc(k.unidad) +
      ' contra ' +
      (k.es_referencia ? 'la referencia ' : 'la meta ') +
      Fmt.meta(k.meta, k.dec) +
      ' —es techo: cumplir es quedar por debajo—, brecha ' +
      Fmt.pct(k.brecha_pct) +
      '.' +
      rumbo
    );
  }

  /* ----------------------------------------------------------------- panorama --- */
  async function pintarPanorama() {
    var pan = await api('panorama', { mes: S.mes, ambito: S.ambito });
    mesesConDato = pan.corte.mesesConDato;

    pintarFichas('#tarjetas', pan.kpi, 'p');
    var nombres = {};
    pan.kpi.forEach(function (k) {
      nombres[k.kpi_id] = k.kpi;
    });
    FranjaCorreccion.pintar('correcciones', pan.correcciones, nombres);

    var foco =
      pan.kpi.filter(function (k) {
        return k.kpi_id === S.kpi;
      })[0] || pan.kpi[2];
    S.kpi = foco.kpi_id;

    var serie = await api('serie-mensual', { ambito: S.ambito, kpi: S.kpi });
    serie.dec = foco.dec;
    $('#hFoco').textContent = foco.kpi + ' en el tiempo';
    $('#subFoco').textContent = pan.ambito.nombre + ' · acumulado a ' + mesElegido(pan);
    Graficos.serieKpi('gFoco', serie);
    $('#notaFoco').innerHTML = nota(textoContraMeta(foco));

    var porSitio = await api('kpi-por-sitio', { mes: S.mes, kpi: S.kpi });
    $('#subSitios').textContent = foco.kpi + ' · acumulado a ' + mesElegido(pan);
    Graficos.porSitio('gSitios', porSitio, foco.dec);
    var fuera = porSitio.sitios.filter(function (s) {
      return s.estado === 'incumple';
    });
    $('#notaSitios').innerHTML = nota(
      'Cada sitio se mide contra <b>su propia meta</b> (el rombo). Las metas por sitio son muy ' +
        'distintas entre sí, así que las barras no se comparan entre ellas; la brecha de la derecha sí. ' +
        (fuera.length === 0
          ? 'Ninguno supera su techo al corte.'
          : (fuera.length === 1 ? 'Lo supera: ' : 'Lo superan: ') +
            '<b>' +
            fuera
              .map(function (s) {
                return Fmt.esc(s.sitio);
              })
              .join(', ') +
            '</b>.')
    );

    Graficos.matrizCalor('gMatriz', pan.kpi, pan.corte.mesesConDato);
    var cambios = 0;
    var desdeSiempre = [];
    pan.kpi.forEach(function (k) {
      var s = k.serie_ytd;
      for (var i = 1; i < s.length; i++) if (s[i].estado !== s[i - 1].estado) cambios++;
      if (
        s.length &&
        s.every(function (p) {
          return p.estado === 'incumple';
        })
      )
        desdeSiempre.push(k.kpi);
    });
    $('#subMatriz').textContent =
      pan.corte.mesesConDato.length +
      ' cortes · ' +
      cambios +
      (cambios === 1 ? ' cambio de estado' : ' cambios de estado');
    $('#notaMatriz').innerHTML = nota(
      'Cada celda es el <b>acumulado al cierre de ese mes</b>, no el valor del mes, y el color es la ' +
        '<b>brecha contra la meta</b>: por eso cinco indicadores con unidades distintas se leen en la ' +
        'misma escala, donde el cero es la meta. ' +
        (desdeSiempre.length
          ? 'Viene incumpliendo desde enero: <b>' +
            desdeSiempre.map(Fmt.esc).join(', ') +
            '</b>. No es un mes malo, es el año.'
          : 'Ningún indicador incumple todos los meses del año.')
    );

    // perimetro fijo en colombia_peru a proposito, no S.ambito: este panel siempre
    // referencia el scorecard mas amplio (Colombia + Peru), nunca el ambito elegido
    // arriba — asi lo explica textoTrayectoria ("perímetro más amplio que el de
    // este tablero").
    var tray = await api('trayectoria-anual', { kpi: S.kpi, ambito: 'colombia_peru' });
    $('#subTray').textContent = tray.kpi + ' · perímetro ' + tray.perimetro;
    Graficos.trayectoria('gTray', tray);
    $('#notaTray').innerHTML = nota(textoTrayectoria(tray));

    await pintarMatrizSitios(pan);
  }

  function textoTrayectoria(t) {
    var cerrados = t.anios.filter(function (a) {
      return a.cerrado;
    });
    if (!cerrados.length)
      return 'El scorecard corporativo no publica cierres anteriores de este indicador.';
    var ult = cerrados[cerrados.length - 1];
    var pri = cerrados[0];
    var txt =
      'Cierres del scorecard corporativo, perímetro <b>' +
      Fmt.esc(t.perimetro) +
      '</b>, que es más amplio ' +
      'que el de este tablero. ';
    if (ult.meta !== null) {
      txt +=
        'El cierre de ' +
        ult.anio +
        ' (' +
        Fmt.num(ult.real, t.dec) +
        ') ' +
        (ult.real > ult.meta ? 'quedó por encima de su meta de ' : 'cumplió su meta de ') +
        Fmt.meta(ult.meta, t.dec) +
        '. ';
    }
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
        '<b>La barra rayada no es un cierre</b>: son ' +
        t.en_curso.hasta_mes +
        ' meses de ' +
        t.en_curso.anio +
        ', ' +
        Fmt.num(t.en_curso.ytd, t.dec) +
        ', y no se compara de igual a igual contra años completos.';
    }
    return txt;
  }

  /* Igual que textoTrayectoria, pero para los paneles "Histórico" de cada recurso
   * (Agua/Energía/Residuos): ahi el perímetro ES el ámbito elegido arriba, no uno
   * más amplio — la frase de textoTrayectoria ("más amplio que este tablero") no
   * aplicaría y confundiría en vez de aclarar. */
  function textoTrayectoriaPropia(t) {
    var cerrados = t.anios.filter(function (a) {
      return a.cerrado;
    });
    if (!cerrados.length)
      return 'Sin cierres anteriores cargados todavía para este ámbito.';
    var ult = cerrados[cerrados.length - 1];
    var pri = cerrados[0];
    var txt = '';
    if (ult.meta !== null) {
      txt +=
        'El cierre de ' +
        ult.anio +
        ' (' +
        Fmt.num(ult.real, t.dec) +
        ') ' +
        (ult.real > ult.meta ? 'quedó por encima de su meta de ' : 'cumplió su meta de ') +
        Fmt.meta(ult.meta, t.dec) +
        '. ';
    }
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
        '<b>La barra rayada no es un cierre</b>: son ' +
        t.en_curso.hasta_mes +
        ' meses de ' +
        t.en_curso.anio +
        ', ' +
        Fmt.num(t.en_curso.ytd, t.dec) +
        ', y no se compara de igual a igual contra años completos.';
    }
    return txt || 'Sin cierres anteriores cargados todavía para este ámbito.';
  }

  /** Panel "Histórico" (cierres año contra año) de un recurso, para el ámbito elegido. */
  async function pintarTrayectoriaPropia(ids, kpi) {
    var tray = await api('trayectoria-anual', { kpi: kpi, ambito: S.ambito });
    if (!tray) {
      $(ids.sub).textContent = '';
      $(ids.grafico).innerHTML = '';
      $(ids.nota).innerHTML = nota('Sin cierres anteriores cargados todavía para este ámbito.');
      return;
    }
    $(ids.sub).textContent = tray.perimetro;
    Graficos.trayectoria(ids.graficoRaw, tray);
    $(ids.nota).innerHTML = nota(textoTrayectoriaPropia(tray));
  }

  async function pintarMatrizSitios(pan) {
    // Siempre los cinco ambitos y en el mismo orden. Antes era [el elegido] + los tres
    // sitios: con Celta elegido, Celta salia dos veces y faltaban los agregados.
    var filas = await Promise.all(
      AMBITOS.map(function (a) {
        return a.id === S.ambito ? pan : api('panorama', { mes: S.mes, ambito: a.id });
      })
    );
    var cab =
      '<tr><th>Ámbito</th>' +
      pan.kpi
        .map(function (k) {
          return (
            '<th class="num">' +
            Fmt.esc(k.kpi) +
            '<br><small>' +
            Fmt.esc(k.unidad) +
            '</small></th>'
          );
        })
        .join('') +
      '</tr>';
    var cuerpo = filas
      .map(function (f) {
        return (
          '<tr><th>' +
          Fmt.esc(f.ambito.nombre) +
          '</th>' +
          f.kpi
            .map(function (k) {
              return (
                '<td class="celda"><b class="num">' +
                Fmt.num(k.valor, k.dec) +
                '</b>' +
                // con meta cero la brecha no existe (dividir por cero): se rotula el
                // estado, que si esta resuelto, en vez de dejar un guion mudo
                chip(
                  k.estado,
                  k.meta === null
                    ? 'sin meta'
                    : k.brecha_pct === null
                      ? ROTULO_ESTADO[k.estado]
                      : Fmt.pct(k.brecha_pct)
                ) +
                '</td>'
              );
            })
            .join('') +
          '</tr>'
        );
      })
      .join('');
    $('#tMatrizSitios').innerHTML = '<table class="matriz">' + cab + cuerpo + '</table>';
    var celdas = [];
    filas.forEach(function (f) {
      f.kpi.forEach(function (k) {
        if (k.estado === 'incumple') celdas.push(f.ambito.nombre + ' / ' + k.kpi);
      });
    });
    $('#subMatrizSitios').textContent = celdas.length + ' celdas por encima del techo';
    $('#notaMatrizSitios').innerHTML = nota(
      (celdas.length
        ? 'Por encima del techo: <b>' + celdas.map(Fmt.esc).join(' · ') + '</b>. '
        : 'Ninguna celda supera su techo al corte. ') +
        'Nacional Labs no tiene fila propia en el scorecard: su columna va sin meta y no se le presta una.'
    );
  }

  /* ------------------------------------------------------------ agua y energía --- */

  function signoClase(v) {
    return v === null || v === undefined ? '' : v < 0 ? 'baja' : 'sube';
  }

  /* Generico a proposito: no nombra "agua" ni "energia" en ningun texto, asi que sirve
     igual para las dos hojas mensuales (pintarHojaMensual la llama para ambas). */
  function textoVariacion(f) {
    if (f.var_por_lente_pct === null)
      return 'Primer mes con dato: no hay mes anterior contra el que comparar.';
    var lente = f.var_por_lente_pct;
    var total = f.var_total_pct;
    var txt =
      'El consumo por lente ' +
      (lente < 0 ? 'baja ' : 'sube ') +
      Fmt.num(Math.abs(lente), 2) +
      ' % contra el mes anterior';
    if (total === null) return txt + '.';
    txt += ', con el consumo total en ' + Fmt.pctDirecto(total) + ': ';
    if (lente < 0 && total >= 0)
      return txt + 'la mejora del ratio viene de la producción, no de gastar menos.';
    if (lente < 0 && total < 0) return txt + 'baja el gasto y además baja el ratio.';
    if (lente > 0 && total < 0) return txt + 'se gastó menos, pero se produjo aún menos.';
    return txt + 'sube el gasto y el ratio lo acusa.';
  }

  /**
   * La hoja "producción contra consumo por lente" de un recurso simple (agua o
   * energía): gráfico combo, variación contra el mes anterior y tabla mes a mes.
   * Agua y energía comparten exactamente este formato — solo cambian las unidades,
   * los campos de la respuesta y en qué elementos del DOM se pinta cada uno —, así
   * que hay una sola implementación en vez de dos copias que podrían separarse.
   *
   * @param {object} ids   los '#id' de cada elemento (ver las dos llamadas abajo)
   * @param {object} datos lo que devuelve /api/ehs/agua-mensual o /energia-mensual
   * @param {object} cfg   nombreRecurso, dibujarCombo, notaCombo, etiquetas y
   *                       nombres de campo/columna/decimales propios del recurso
   */
  function pintarHojaMensual(ids, datos, cfg) {
    if (!datos.filas.length) {
      $(ids.subCombo).textContent = datos.ambito.nombre;
      $(ids.combo).innerHTML =
        '<div class="vacio"><span class="chip sinmeta">sin fila en el reporte del área</span>' +
        '<p><b>' +
        Fmt.esc(datos.ambito.nombre) +
        '</b> no es una fila del reporte de ' +
        cfg.nombreRecurso +
        ' que publica el área. No se dibuja una serie que el origen no trae.</p></div>';
      $(ids.notaCombo).innerHTML = '';
      $(ids.cajasVar).innerHTML = '';
      $(ids.subVar).textContent = '—';
      $(ids.notaVar).innerHTML = '';
      $(ids.tabla).innerHTML = '';
      $(ids.subTabla).textContent = '—';
      return;
    }

    $(ids.subCombo).textContent = datos.ambito.nombre + ' · ' + datos.anio;
    cfg.dibujarCombo(ids.comboRaw, datos.filas);
    $(ids.notaCombo).innerHTML = nota(cfg.notaCombo);

    var f =
      datos.filas.filter(function (x) {
        return x.mes === S.mes;
      })[0] || datos.filas[datos.filas.length - 1];
    $(ids.subVar).textContent =
      Fmt.mesLargo[f.mes - 1] + ' contra ' + (f.mes >= 2 ? Fmt.mesLargo[f.mes - 2] : '—');
    $(ids.cajasVar).innerHTML = [
      ['Consumo total', f.var_total_pct],
      ['Consumo por lente', f.var_por_lente_pct],
    ]
      .map(function (par) {
        return (
          '<div class="varbox ' +
          signoClase(par[1]) +
          '"><span class="et">' +
          par[0] +
          '</span>' +
          '<span class="num vv">' +
          Fmt.pctDirecto(par[1]) +
          '</span></div>'
        );
      })
      .join('');
    $(ids.notaVar).innerHTML = nota(textoVariacion(f));

    $(ids.subTabla).textContent = datos.filas.length + ' meses con dato';
    $(ids.tabla).innerHTML =
      '<table class="matriz"><tr><th>Mes</th><th class="num">' +
      cfg.colConsumo +
      '</th><th class="num">Lentes</th>' +
      '<th class="num">' +
      cfg.colRatio +
      '</th><th class="num">Δ total</th><th class="num">Δ por lente</th></tr>' +
      datos.filas
        .map(function (r) {
          return (
            '<tr><th>' +
            Fmt.esc(r.nombre_mes) +
            '</th>' +
            '<td class="num">' +
            Fmt.num(r[cfg.campoConsumo], cfg.decConsumo) +
            '</td>' +
            '<td class="num">' +
            Fmt.num(r.lentes, 0) +
            '</td>' +
            '<td class="num">' +
            Fmt.num(r[cfg.campoRatio], cfg.decRatio) +
            '</td>' +
            '<td class="num ' +
            signoClase(r.var_total_pct) +
            '">' +
            Fmt.pctDirecto(r.var_total_pct) +
            '</td>' +
            '<td class="num ' +
            signoClase(r.var_por_lente_pct) +
            '">' +
            Fmt.pctDirecto(r.var_por_lente_pct) +
            '</td></tr>'
          );
        })
        .join('') +
      '</table>';
  }

  async function pintarAgua() {
    var agua = await api('agua-mensual', { ambito: S.ambito });
    var diario = await api('agua-diaria', { mes: S.mes, sitio: S.ambito });

    pintarHojaMensual(
      {
        subCombo: '#subAguaCombo',
        combo: '#gAguaCombo',
        comboRaw: 'gAguaCombo',
        notaCombo: '#notaAguaCombo',
        subVar: '#subAguaVar',
        cajasVar: '#cajasAguaVar',
        notaVar: '#notaAguaVar',
        tabla: '#tAgua',
        subTabla: '#subAguaTabla',
      },
      agua,
      {
        nombreRecurso: 'agua',
        dibujarCombo: Graficos.aguaCombo,
        notaCombo:
          'Dos causas distintas mueven el consumo por lente: lo que se gasta y lo que se produce. ' +
          'El eje doble deja ver cuál de las dos manda en cada mes, y el máximo y el mínimo quedan ' +
          'anotados dentro del propio gráfico.',
        colConsumo: 'Consumo m³',
        colRatio: 'l/lente',
        campoConsumo: 'consumo_m3',
        decConsumo: 0,
        campoRatio: 'l_por_lente',
        decRatio: 2,
      }
    );

    $('#subAguaDiario').textContent = diario.disponible
      ? diario.dias.length + ' lecturas'
      : 'próximamente';
    $('#cajaAguaDiario').innerHTML = diario.disponible
      ? ''
      : '<div class="vacio"><span class="chip pend">próximamente</span>' +
        '<p>El área sí lleva el registro diario y esta vista ya está construida para leerlo: ' +
        'se enciende sola en cuanto el registro entre. Estado que informa el servidor: ' +
        '<b>' +
        Fmt.esc(diario.estado) +
        '</b>.</p></div>';

    // --------------------------------------------------------------- energía ---
    var pan = await api('panorama', { mes: S.mes, ambito: S.ambito });
    var kEne = pan.kpi.filter(function (k) {
      return k.kpi_id === 'energia_por_lente';
    })[0];

    var energia = await api('energia-mensual', { ambito: S.ambito });
    pintarHojaMensual(
      {
        subCombo: '#subEnergiaCombo',
        combo: '#gEnergiaCombo',
        comboRaw: 'gEnergiaCombo',
        notaCombo: '#notaEnergiaCombo',
        subVar: '#subEnergiaVar',
        cajasVar: '#cajasEnergiaVar',
        notaVar: '#notaEnergiaVar',
        tabla: '#tEnergia',
        subTabla: '#subEnergiaTabla',
      },
      energia,
      {
        nombreRecurso: 'energía',
        dibujarCombo: Graficos.energiaCombo,
        notaCombo:
          'Igual que con el agua: lo que sube o baja el consumo por lente puede ser el gasto o ' +
          'la producción, y el eje doble separa cuál de las dos manda cada mes.',
        colConsumo: 'Consumo kWh',
        colRatio: 'kWh/lente',
        campoConsumo: 'consumo_kwh',
        decConsumo: 0,
        campoRatio: 'kwh_por_lente',
        decRatio: 2,
      }
    );

    var porSitioEnergia = await api('kpi-por-sitio', { mes: S.mes, kpi: 'energia_por_lente' });
    $('#subEnergiaSitios').textContent = 'acumulado a ' + mesElegido(pan);
    Graficos.porSitio('gEnergiaSitios', porSitioEnergia, kEne ? kEne.dec : 3);
    var fueraEne = porSitioEnergia.sitios.filter(function (s) {
      return s.estado === 'incumple';
    });
    $('#notaEnergiaSitios').innerHTML = nota(
      'Las metas de energía por sitio son distintas entre sí y no son comparables entre ellas. ' +
        (fueraEne.length
          ? 'Superan la suya: <b>' +
            fueraEne
              .map(function (s) {
                return Fmt.esc(s.sitio);
              })
              .join(', ') +
            '</b>.'
          : 'Ninguno supera la suya al corte.')
    );

    await pintarTrayectoriaPropia(
      { sub: '#subAguaTray', grafico: '#gAguaTray', graficoRaw: 'gAguaTray', nota: '#notaAguaTray' },
      'agua_por_lente'
    );
    await pintarTrayectoriaPropia(
      {
        sub: '#subEnergiaTray',
        grafico: '#gEnergiaTray',
        graficoRaw: 'gEnergiaTray',
        nota: '#notaEnergiaTray',
      },
      'energia_por_lente'
    );
  }

  /* ---------------------------------------------------------------- ambiental --- */
  async function pintarAmbiental() {
    var pan = await api('panorama', { mes: S.mes, ambito: S.ambito });
    var kRes = pan.kpi.filter(function (k) {
      return k.kpi_id === 'residuos_por_lente';
    })[0];

    var res = await api('serie-mensual', { ambito: S.ambito, kpi: 'residuos_por_lente' });
    res.dec = kRes.dec;
    $('#subResiduos').textContent = pan.ambito.nombre;
    Graficos.serieKpi('gResiduos', res);
    $('#notaResiduos').innerHTML = nota(textoContraMeta(kRes));

    var porSitio = await api('kpi-por-sitio', { mes: S.mes, kpi: 'residuos_por_lente' });
    $('#subResSitios').textContent = 'acumulado a ' + mesElegido(pan);
    Graficos.porSitio('gResSitios', porSitio, 1);
    var fuera = porSitio.sitios.filter(function (s) {
      return s.estado === 'incumple';
    });
    $('#notaResSitios').innerHTML = nota(
      'Las metas de residuos por sitio son muy distintas y no son comparables entre sí. ' +
        (fuera.length
          ? 'Superan la suya: <b>' +
            fuera
              .map(function (s) {
                return Fmt.esc(s.sitio);
              })
              .join(', ') +
            '</b>.'
          : 'Ninguno supera la suya al corte.')
    );

    var comp = await api('residuos-composicion', { ambito: S.ambito });
    $('#subComp').textContent = comp.ambito.nombre + ' · ' + comp.meses.length + ' meses';
    Graficos.composicionResiduos('gComp', comp, kRes.meta);
    $('#notaComp').innerHTML = nota(textoComposicion(comp, kRes));
    pintarAcumuladoComp(comp);

    await pintarTrayectoriaPropia(
      {
        sub: '#subResiduosTray',
        grafico: '#gResiduosTray',
        graficoRaw: 'gResiduosTray',
        nota: '#notaResiduosTray',
      },
      'residuos_por_lente'
    );
  }

  function pintarAcumuladoComp(comp) {
    var nombre = { peligroso: 'Peligroso', aprovechable: 'Aprovechable', ordinario: 'Ordinario' };
    var color = {
      peligroso: Graficos.colores.incumple,
      aprovechable: Graficos.colores.amb,
      ordinario: Graficos.colores.inst,
    };
    var mayor = comp.acumulado.reduce(function (a, b) {
      return b.part > a.part ? b : a;
    });
    $('#subAcumComp').textContent = 'acumulado del año';
    $('#cajaAcumComp').innerHTML =
      comp.acumulado
        .map(function (a) {
          return (
            '<div class="parte">' +
            '<div class="pcab"><span class="ppunto" style="background:' +
            color[a.parte] +
            '"></span>' +
            '<b>' +
            nombre[a.parte] +
            '</b>' +
            '<span class="num ppct">' +
            Fmt.num(a.part * 100, 0) +
            ' %</span></div>' +
            '<div class="pbarra"><i style="width:' +
            (a.part * 100).toFixed(1) +
            '%;background:' +
            color[a.parte] +
            '"></i></div>' +
            '<div class="pdet num">' +
            Fmt.num(a.g_lente, 1) +
            ' g/lente · ' +
            Fmt.num(a.kg, 0) +
            ' kg</div>' +
            '</div>'
          );
        })
        .join('') +
      nota(
        'El indicador dice <b>cuánto</b>; esto dice <b>de qué</b>. El ' +
          Fmt.num(mayor.part * 100, 0) +
          ' % del residuo del año es <b>' +
          nombre[mayor.parte].toLowerCase() +
          '</b>, así que es donde una ' +
          'acción mueve la aguja. Las tres partes en g/lente suman exactamente el indicador del mes: mismo ' +
          'numerador, mismo denominador.'
      );
  }

  function textoComposicion(comp, kRes) {
    var n = comp.meses.length;
    if (n < 2) return 'Un solo mes con dato: todavía no hay contra qué comparar la composición.';
    var ult = comp.meses[n - 1];
    var ant = comp.meses[n - 2];
    var salto = comp.partes
      .map(function (p) {
        return { parte: p, delta: (ult[p + '_g_lente'] || 0) - (ant[p + '_g_lente'] || 0) };
      })
      .reduce(function (a, b) {
        return Math.abs(b.delta) > Math.abs(a.delta) ? b : a;
      });
    var nombre = {
      peligroso: 'el peligroso',
      aprovechable: 'el aprovechable',
      ordinario: 'el ordinario',
    };
    return (
      'La altura total de cada barra <b>es</b> el indicador de ese mes, así que la gráfica no acompaña ' +
      'al KPI: lo explica. Entre ' +
      Fmt.esc(ant.nombre_mes) +
      ' y ' +
      Fmt.esc(ult.nombre_mes) +
      ' el que más se movió fue <b>' +
      nombre[salto.parte] +
      '</b>, ' +
      Fmt.num(salto.delta, 1) +
      ' g/lente' +
      (kRes.meta === null
        ? '.'
        : ', con el techo del ámbito en ' + Fmt.meta(kRes.meta, 1) + ' g/lente.')
    );
  }

  /* ---------------------------------------------------------------- seguridad --- */
  async function pintarSeguridad() {
    var pan = await api('panorama', { mes: S.mes, ambito: S.ambito });
    var seg = pan.kpi.filter(function (k) {
      return k.familia === 'Seguridad';
    });
    var nombres = {};
    pan.kpi.forEach(function (k) {
      nombres[k.kpi_id] = k.kpi;
    });
    FranjaCorreccion.pintar('correccionesSeg', pan.correcciones, nombres);
    pintarFichas('#tarjetasSeg', seg, 's');

    var fr = await api('serie-mensual', { ambito: S.ambito, kpi: 'frequency_rate' });
    fr.dec = seg[0].dec;
    $('#subFR').textContent = pan.ambito.nombre;
    Graficos.serieKpi('gFR', fr);
    $('#notaFR').innerHTML = nota(
      textoContraMeta(seg[0]) +
        ' El denominador son las horas-hombre de personal fijo más temporal.'
    );

    var porSitio = await api('kpi-por-sitio', { mes: S.mes, kpi: 'frequency_rate' });
    $('#subSegTabla').textContent = 'frequency rate · acumulado a ' + mesElegido(pan);
    $('#tSeguridad').innerHTML =
      '<table class="matriz"><tr><th>Sitio</th><th class="num">FR acumulado</th><th class="num">Meta</th>' +
      '<th>Estado</th></tr>' +
      porSitio.sitios
        .map(function (s) {
          return (
            '<tr><th>' +
            Fmt.esc(s.sitio) +
            '</th><td class="num">' +
            Fmt.num(s.valor, 3) +
            '</td>' +
            '<td class="num">' +
            (s.meta === null ? '—' : Fmt.meta(s.meta, 2)) +
            '</td>' +
            '<td>' +
            chip(s.estado) +
            '</td></tr>'
          );
        })
        .join('') +
      '</table>';

    var acc = await api('serie-mensual', { ambito: S.ambito, kpi: 'accidentes_dafw' });
    acc.dec = 0;
    var conCaso = acc.meses.filter(function (m) {
      return m.valor !== null && m.valor > 0;
    });
    $('#notaSegSitios').innerHTML = nota(
      conCaso.length === 0
        ? 'Ningún mes del año registra accidentes con días perdidos en este ámbito.'
        : 'Meses con caso en el año: <b>' +
            conCaso
              .map(function (m) {
                return Fmt.mesLargo[m.mes - 1];
              })
              .join(', ') +
            '</b>.'
    );

    $('#subAcc').textContent = pan.ambito.nombre;
    Graficos.serieKpi('gAcc', acc);
    $('#notaAcc').innerHTML = nota(
      'Los accidentes son un conteo acumulado del año: la línea solo puede subir o sostenerse. ' +
        'Un mes en cero no borra un caso anterior.'
    );

    // mismo criterio que gTray en Panorama: perimetro fijo, no el ambito elegido
    var tray = await api('trayectoria-anual', { kpi: 'frequency_rate', ambito: 'colombia_peru' });
    $('#subTraySeg').textContent = tray.kpi + ' · perímetro ' + tray.perimetro;
    Graficos.trayectoria('gTraySeg', tray);
    $('#notaTraySeg').innerHTML = nota(textoTrayectoria(tray));
  }

  /* ------------------------------------------------------------------ calidad --- */
  async function pintarCalidad() {
    var cal = await api('calidad-dato', {});
    var errores = cal.hallazgos.filter(function (h) {
      return h.gravedad === 'error';
    }).length;
    $('#tarjetasCal').innerHTML = [
      ['Meses con dato', cal.meses_con_dato.length + '<small>de 12</small>'],
      ['Lecturas cargadas', String(cal.lecturas)],
      ['Lecturas diarias de agua', String(cal.lecturas_diarias)],
      ['Hallazgos del libro', errores + '<small>alteran un número</small>'],
    ]
      .map(function (t) {
        return (
          '<div class="kcard estatica"><div class="khead"><span class="kn">' +
          t[0] +
          '</span></div>' +
          '<div class="kv num">' +
          t[1] +
          '</div></div>'
        );
      })
      .join('');

    $('#subCalMes').textContent = cal.meses_con_dato.length + ' meses con lectura';
    $('#tCalidad').innerHTML =
      '<table class="matriz"><tr><th>Mes</th><th class="num">Sitios</th><th class="num">Magnitudes</th>' +
      '<th class="num">Lecturas</th></tr>' +
      cal.por_mes
        .map(function (m) {
          return (
            '<tr><th>' +
            Fmt.mesLargo[m.mes - 1] +
            '</th><td class="num">' +
            m.sitios +
            '</td>' +
            '<td class="num">' +
            m.magnitudes +
            '</td><td class="num">' +
            m.lecturas +
            '</td></tr>'
          );
        })
        .join('') +
      '</table>';
    $('#notaCalidad').innerHTML = nota(
      'Un mes que no aparece es un mes <b>sin captura</b>, no un cero: no se dibuja ni se promedia ' +
        'lo que no existe. Es exactamente el defecto que traía el libro heredado.'
    );

    $('#cajaOrigen').innerHTML =
      '<div class="kv2">' +
      '<span class="et">Origen</span><b>' +
      Fmt.esc(cal.origen) +
      '</b>' +
      '<span class="et">Meta vigente</span><b>' +
      Fmt.esc(cal.meta_vigente) +
      '</b>' +
      '<span class="et">Corte</span><b>' +
      Fmt.esc(cal.corte.nombre) +
      ' ' +
      cal.anio +
      '</b>' +
      '<span class="et">Actualizado</span><b>' +
      Fmt.esc(cal.actualizado_en) +
      '</b>' +
      '<span class="et">Estado</span><b>' +
      Fmt.esc(cal.estado) +
      '</b>' +
      '</div><p class="descarga"><a class="btn-desc" href="/api/ehs/detalle?formato=csv">' +
      'Descargar el detalle crudo en CSV</a><span>Las nueve magnitudes tal como se capturaron, ' +
      'sin ningún cálculo encima.</span></p>';

    $('#subHallazgos').textContent =
      cal.hallazgos.length + ' documentados · ' + errores + ' alteran un número';
    $('#cajaHallazgos').innerHTML =
      '<ul class="hall">' +
      cal.hallazgos
        .map(function (h) {
          return (
            '<li class="' +
            (h.gravedad === 'error' ? 'grave' : '') +
            '">' +
            chip(
              h.gravedad === 'error' ? 'incumple' : 'riesgo',
              h.gravedad === 'error' ? 'altera un número' : 'confunde'
            ) +
            '<div><b>' +
            Fmt.esc(h.titulo) +
            '</b><p>' +
            Fmt.esc(h.detalle) +
            ' ' +
            Fmt.esc(h.impacto) +
            '</p></div></li>'
          );
        })
        .join('') +
      '</ul>';

    pintarAvisosAutomaticos(cal.avisos_automaticos || []);
  }

  /**
   * A diferencia de los hallazgos de arriba —hechos puntuales del libro heredado,
   * escritos a mano porque describen una celda concreta—, esto se recalcula en cada
   * corte: duplicados, valores negativos, denominadores en cero, meses sin un sitio y
   * saltos atípicos mes a mes. Ver app/sql/02-vistas.sql, ehs.v_calidad_avisos.
   */
  function pintarAvisosAutomaticos(avisos) {
    var errores = avisos.filter(function (a) {
      return a.gravedad === 'error';
    });
    var suaves = avisos.filter(function (a) {
      return a.gravedad !== 'error';
    });
    $('#subAvisos').textContent = avisos.length
      ? avisos.length +
        ' · ' +
        errores.length +
        (errores.length === 1 ? ' bloqueante' : ' bloqueantes')
      : 'ninguno';

    if (!avisos.length) {
      $('#cajaAvisos').innerHTML =
        '<div class="vacio"><span class="chip cumple">sin avisos</span>' +
        '<p>Ningún duplicado, valor negativo, denominador en cero, mes incompleto ni salto ' +
        'atípico mes a mes en los datos de este corte.</p></div>';
      $('#notaAvisos').innerHTML = '';
      return;
    }
    $('#cajaAvisos').innerHTML =
      '<ul class="hall">' +
      errores
        .concat(suaves)
        .map(function (a) {
          return (
            '<li class="' +
            (a.gravedad === 'error' ? 'grave' : '') +
            '">' +
            chip(
              a.gravedad === 'error' ? 'incumple' : 'riesgo',
              a.gravedad === 'error' ? 'bloqueante' : 'a revisar'
            ) +
            '<div><p>' +
            Fmt.esc(a.mensaje) +
            '</p></div></li>'
          );
        })
        .join('') +
      '</ul>';
    $('#notaAvisos').innerHTML = nota(
      'Un aviso <b>no corrige nada ni bloquea la publicación</b>: señala. Un dato raro puede ser un ' +
        'error de captura o un mes de verdad atípico, y quien lo sabe es el área. Lo que no puede pasar ' +
        'es que nadie se entere.'
    );
  }

  /* -------------------------------------------------------------- 06 · datos --- */

  /* Una lectura o una suma tal como esta en la base: 979,1 y no 979. Fmt.num redondea a
     los decimales que se le pidan, y aqui no se quiere esconder ninguno. */
  function crudo(v) {
    return v === null || v === undefined
      ? '—'
      : Number(v).toLocaleString('es-CO', { maximumFractionDigits: 4 });
  }

  /**
   * Los datos detras de las graficas. Todo llega de /api/ehs/datos, que lee las mismas
   * vistas que alimentan las fichas y las graficas (ehs.v_kpi_mensual y v_kpi_ytd): aqui
   * no se calcula ningun indicador.
   *
   * Lo unico que se hace en el navegador es la COMPROBACION: sumar las lecturas de la
   * tabla 01 que, segun ref.kpi_magnitud (servido tambien), forman cada numerador y
   * denominador, y confirmar que dan lo mismo que usa la vista. Es una suma de cifras
   * servidas, no una formula de KPI, y es justo lo que permite a quien mira el tablero
   * ver con sus ojos que la grafica sale de estas lecturas y no de otras.
   */
  async function pintarDatos() {
    var d = await api('datos', { ambito: S.ambito });
    var unSitio = d.ambito.sitios.length === 1;
    var sitio = unSitio ? d.ambito.sitios[0].id : null;
    var nombres = d.ambito.sitios.map(function (s) {
      return s.nombre;
    });
    var porMagnitud = {};
    d.magnitudes.forEach(function (g) {
      porMagnitud[g.id] = g;
    });

    // --- 01 · las lecturas
    $('#subDatosLect').textContent = unSitio
      ? d.ambito.nombre + ' · ' + d.corte.nombre + ' ' + d.anio
      : 'suma de ' + nombres.join(' + ') + ' · al corte de ' + d.corte.nombre;
    $('#tDatosLect').innerHTML =
      '<table class="matriz datos-tabla"><tr><th>Mes</th>' +
      d.magnitudes
        .map(function (g) {
          return (
            '<th class="num">' + Fmt.esc(g.nombre) + '<small>' + Fmt.esc(g.unidad) + '</small></th>'
          );
        })
        .join('') +
      '</tr>' +
      d.meses
        .map(function (m) {
          return (
            '<tr' +
            (m.mes === S.mes ? ' class="datos-sel"' : '') +
            '><th>' +
            Fmt.mesLargo[m.mes - 1] +
            '</th>' +
            d.magnitudes
              .map(function (g) {
                var v = m.lecturas[g.id];
                var parcial =
                  v !== undefined && (m.sitiosConLectura[g.id] || 0) < d.ambito.sitios.length;
                var editar = unSitio
                  ? ' <a class="datos-editar" title="Corregir este valor" href="/corregir?' +
                    new URLSearchParams({
                      anio: d.anio,
                      mes: m.mes,
                      sitio: sitio,
                      magnitud: g.id,
                    }).toString() +
                    '">✎</a>'
                  : '';
                return (
                  '<td class="num' +
                  (parcial ? ' datos-parcial' : '') +
                  '"' +
                  (parcial ? ' title="Falta la lectura de algún sitio: la suma es parcial"' : '') +
                  '>' +
                  crudo(v) +
                  editar +
                  '</td>'
                );
              })
              .join('') +
            '</tr>'
          );
        })
        .join('') +
      '</table>';
    $('#notaDatosLect').innerHTML = nota(
      unSitio
        ? 'Cada número es la lectura tal como está en la base. Para cambiar uno, el lápiz ✎ ' +
            'abre <b>Consultar y corregir</b> con ese valor ya elegido: pide el motivo, guarda el ' +
            'valor anterior en el historial y el tablero se recalcula solo.'
        : 'En un agregado cada número es la <b>suma</b> de las lecturas de ' +
            Fmt.esc(nombres.join(', ')) +
            '. Para ver o corregir la lectura de un sitio, elígelo arriba en <b>Sitio</b>.'
    );

    // --- 02 · de donde salen las graficas
    var sumar = function (m, lista) {
      if (!lista.length) return null;
      var s = 0;
      for (var i = 0; i < lista.length; i++) {
        var v = m.lecturas[lista[i]];
        if (v === undefined || v === null) return null;
        s += Number(v);
      }
      return s;
    };
    var igual = function (a, b) {
      var faltaA = a === null || a === undefined;
      var faltaB = b === null || b === undefined;
      if (faltaA || faltaB) return faltaA && faltaB;
      return Math.abs(a - b) <= 1e-6 * Math.max(1, Math.abs(a), Math.abs(b));
    };
    var nombreDe = function (lista) {
      return lista
        .map(function (id) {
          var g = porMagnitud[id];
          return g ? g.nombre + ' (' + g.unidad + ')' : id;
        })
        .join(' + ');
    };
    var fallas = 0;
    $('#cajaDatosKpi').innerHTML = d.kpis
      .map(function (k) {
        var formula =
          (k.numerador.length > 1 ? '(' : '') +
          nombreDe(k.numerador) +
          (k.numerador.length > 1 ? ')' : '') +
          (k.factor !== 1 ? ' × ' + Fmt.num(k.factor) : '') +
          (k.denominador.length
            ? ' ÷ ' +
              (k.denominador.length > 1 ? '(' : '') +
              nombreDe(k.denominador) +
              (k.denominador.length > 1 ? ')' : '')
            : '');
        var filas = d.meses
          .map(function (m) {
            var x = m.kpis[k.id] || {};
            var ok =
              igual(sumar(m, k.numerador), x.numerador) &&
              (k.denominador.length ? igual(sumar(m, k.denominador), x.denominador) : true);
            if (!ok) fallas++;
            return (
              '<tr' +
              (m.mes === S.mes ? ' class="datos-sel"' : '') +
              '><th>' +
              Fmt.mesLargo[m.mes - 1] +
              '</th><td class="num">' +
              crudo(x.numerador) +
              '</td><td class="num">' +
              (k.denominador.length ? crudo(x.denominador) : '—') +
              '</td><td class="num fuerte">' +
              Fmt.num(x.valor, k.dec) +
              '</td><td class="num">' +
              crudo(x.ytd_numerador) +
              '</td><td class="num">' +
              (k.denominador.length ? crudo(x.ytd_denominador) : '—') +
              '</td><td class="num fuerte">' +
              Fmt.num(x.ytd, k.dec) +
              '</td><td class="datos-ok">' +
              (ok
                ? '<span class="chip cumple" title="La suma de las lecturas de la tabla 01 da este numerador y este denominador">cuadra</span>'
                : '<span class="chip incumple" title="La suma de las lecturas no coincide con lo que usa el cálculo">no cuadra</span>') +
              '</td></tr>'
            );
          })
          .join('');
        return (
          '<div class="datos-kpi"><h3>' +
          Fmt.esc(k.nombre) +
          ' <small>' +
          Fmt.esc(k.unidad) +
          '</small></h3><p class="datos-formula">' +
          Fmt.esc(formula) +
          (k.denominador.length ? '' : ' · es un conteo: no divide') +
          '</p><div class="tablabox"><table class="matriz datos-tabla"><tr><th>Mes</th>' +
          '<th class="num">Numerador</th><th class="num">Denominador</th><th class="num">Del mes</th>' +
          '<th class="num">Numerador acum.</th><th class="num">Denominador acum.</th>' +
          '<th class="num">Acumulado (YTD)</th><th>Comprobación</th></tr>' +
          filas +
          '</table></div></div>'
        );
      })
      .join('');
    $('#subDatosKpi').textContent = fallas
      ? fallas + (fallas === 1 ? ' fila no cuadra' : ' filas no cuadran')
      : 'todo cuadra con las lecturas de la tabla 01';
    $('#notaDatosKpi').innerHTML = nota(
      'Estas son las cifras exactas que dibujan las fichas y las gráficas: numerador y ' +
        'denominador del mes, y los mismos sumados de enero al mes (el acumulado se divide al ' +
        'final, nunca se promedia). <b>Cuadra</b> quiere decir que sumar las lecturas de la ' +
        'tabla 01 da exactamente lo que usa el cálculo.' +
        ' <a href="/api/ehs/detalle?formato=csv">Descargar las lecturas en CSV</a>.'
    );
  }

  /* ------------------------------------------------------------------- render --- */
  async function render() {
    // Un clic mientras se dibuja NO se descarta: se recuerda y se atiende al terminar.
    // Descartarlo dejaba al usuario mirando el filtro que acaba de pulsar sin que la
    // pantalla lo siguiera, y sin nada que se lo explicara.
    if (pintando) {
      pendiente = true;
      return;
    }
    pintando = true;
    document.body.classList.add('cargando');
    try {
      escribirUrl();
      marcarControles();
      var amb = AMBITOS.filter(function (a) {
        return a.id === S.ambito;
      })[0];
      $('#tiraEstado').innerHTML =
        '<span>SITIO <b>' +
        Fmt.esc(amb ? amb.rotulo : S.ambito) +
        '</b></span>' +
        '<span>CORTE <b>' +
        Fmt.mesLargo[S.mes - 1] +
        ' ' +
        S.anio +
        '</b></span>' +
        '<span>META <b>TECHO · CUMPLIR ES QUEDAR POR DEBAJO</b></span>';

      if (S.vista === 'panorama') await pintarPanorama();
      else if (S.vista === 'agua') await pintarAgua();
      else if (S.vista === 'ambiental') await pintarAmbiental();
      else if (S.vista === 'seguridad') await pintarSeguridad();
      else if (S.vista === 'calidad') await pintarCalidad();
      else if (S.vista === 'datos') await pintarDatos();

      Graficos.redibujar();
      $('#viva').textContent =
        'Vista ' + S.vista + ', ' + Fmt.mesLargo[S.mes - 1] + ' ' + S.anio + '.';
    } catch (err) {
      console.error(err);
      $('#tiraEstado').innerHTML =
        '<span class="chip incumple">no se pudo leer el dato del servidor</span>';
    } finally {
      pintando = false;
      if (pendiente) {
        pendiente = false;
        render();
      } else {
        document.body.classList.remove('cargando');
      }
    }
  }

  var reTimer = null;
  window.addEventListener('resize', function () {
    if (reTimer) clearTimeout(reTimer);
    reTimer = setTimeout(Graficos.redibujar, 140);
  });

  leerUrl();
  // La primera peticion va SIN mes: la resuelve el servidor al corte publicado. Pedirla
  // con el mes de la URL hacia que un enlace a un mes todavia sin publicar (?mes=8)
  // recibiera 404 y el tablero dijera "el servidor de datos no responde".
  api('panorama', { ambito: S.ambito })
    .then(function (pan) {
      // el corte lo fija el dato, no el codigo: si el mes pedido no tiene captura se
      // cae al ultimo publicado, en vez de dibujar un vacio
      mesesConDato = pan.corte.mesesConDato;
      S.anio = pan.anio;
      if (mesesConDato.indexOf(S.mes) < 0) S.mes = pan.corte.mes;
      construirControles();
      return render();
    })
    .catch(function (err) {
      console.error(err);
      document.getElementById('tiraEstado').innerHTML =
        '<span class="chip incumple">el servidor de datos no responde</span>';
    });

  return { estado: S, render: render };
})();
