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
  // Dos subgrupos, tal como se pidio ("vistas individuales y grupales junto a
  // Colombia"): arriba los agregados de pais/region (Colombia+Peru, Colombia, Peru
  // -al lado de Colombia-, Nacional Labs), abajo los sitios propios de Colombia.
  // AMBITOS sigue siendo la lista plana de siempre — el mismo orden de antes — para
  // no tocar leerUrl/escribirUrl ni el resto de los usos existentes.
  var GRUPOS_AMBITO = [
    {
      titulo: 'Consolidados',
      items: [
        { id: 'colombia_peru', rotulo: 'Colombia + Perú' },
        { id: 'nacional', rotulo: 'Colombia' },
        { id: 'peru', rotulo: 'Perú' },
        { id: 'nacional_labs', rotulo: 'Nacional Labs' },
      ],
    },
    {
      titulo: 'Laboratorios y agencias',
      items: [
        { id: 'celta', rotulo: 'Celta' },
        { id: 'estrella', rotulo: 'La Estrella' },
        { id: 'agencias', rotulo: 'Agencias' },
      ],
    },
    // Expansion LATAM (postgres/06_paises_latam.sql): metas 2026 ya cargadas, sin
    // lecturas todavia — por eso se ven con estado "Sin dato" hasta que cada pais
    // empiece a capturar. Mismo patron: un consolidado primero, los paises despues.
    {
      titulo: 'LATAM',
      items: [{ id: 'latam', rotulo: 'LATAM' }],
    },
    {
      titulo: 'Andina',
      items: [
        { id: 'andina', rotulo: 'Andina' },
        { id: 'argentina', rotulo: 'Argentina' },
        { id: 'chile', rotulo: 'Chile' },
      ],
    },
    {
      titulo: 'Centroamérica y Caribe',
      items: [
        { id: 'ca_caribe', rotulo: 'CA y Caribe' },
        { id: 'costa_rica', rotulo: 'Costa Rica' },
        { id: 'nicaragua', rotulo: 'Nicaragua' },
        { id: 'rep_dominicana', rotulo: 'Rep. Dominicana' },
        { id: 'guatemala', rotulo: 'Guatemala' },
        { id: 'honduras', rotulo: 'Honduras' },
      ],
    },
    {
      titulo: 'México, Brasil y otros',
      items: [
        { id: 'mexico', rotulo: 'México' },
        { id: 'brasil', rotulo: 'Brasil' },
        { id: 'ecuador', rotulo: 'Ecuador' },
        { id: 'eua', rotulo: 'EUA' },
      ],
    },
  ];
  var AMBITOS = GRUPOS_AMBITO.reduce(function (acc, g) {
    return acc.concat(g.items);
  }, []);
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
  function $all(sel) {
    return Array.prototype.slice.call(document.querySelectorAll(sel));
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
  function filaFicha(etiqueta, valor, comoCodigo) {
    if (valor === undefined || valor === null || valor === '') return '';
    var v = Fmt.esc(valor);
    return '<dt>' + etiqueta + '</dt><dd>' + (comoCodigo ? '<code>' + v + '</code>' : v) + '</dd>';
  }
  // Detalle para depurar: de donde sale el dato, que celda es, que trae hoy y que
  // deberia traer. Colapsado por defecto (details.infodato) para no alargar la lista.
  function fichaHallazgo(h) {
    var filas =
      filaFicha('Libro', h.libro) +
      filaFicha('Celda', h.celda, true) +
      filaFicha('Valor actual', h.valor_actual) +
      filaFicha('Debería ir', h.valor_esperado) +
      filaFicha('Posible causa', h.posible_causa) +
      filaFicha('Cómo resolver', h.como_resolver);
    if (!filas) return '';
    return (
      '<details class="infodato"><summary>Ficha para depurar</summary>' +
      '<dl class="ficha">' +
      filas +
      '</dl></details>'
    );
  }
  // Los avisos son automaticos (ehs.v_calidad_avisos), no un texto a mano por caso: la
  // causa/resolucion es una por TIPO de chequeo, no por instancia.
  var CAUSA_AVISO = {
    valor_negativo: {
      causa:
        'La magnitud no puede ser negativa: probablemente un signo de menos o una resta mal puesta al capturar.',
      resolucion: 'Revisar la celda de origen en el libro y volver a capturar el valor correcto.',
    },
    denominador_invalido: {
      causa:
        'unidades_buenas u horas_fijos llegó en cero ese mes/sitio, y los indicadores que dividen por esa magnitud no se pueden calcular.',
      resolucion:
        'Confirmar con el área si el sitio realmente no operó ese mes o si falta cargar el dato.',
    },
    salto_atipico: {
      causa:
        'El valor cambió de forma brusca contra el mes anterior: puede ser un evento real (parada, pico de producción) o un error de captura.',
      resolucion: 'Contrastar con el área si el salto es real; si no, corregir el dato de origen.',
    },
    mes_incompleto: {
      causa: 'No todos los sitios/magnitudes tienen lectura ese mes.',
      resolucion: 'Completar la captura de las lecturas que faltan.',
    },
  };
  function fichaAviso(a) {
    var sitio = AMBITOS.filter(function (s) {
      return s.id === a.sitio;
    })[0];
    var causa = CAUSA_AVISO[a.codigo];
    var filas =
      filaFicha('Código', a.codigo, true) +
      filaFicha('Mes', a.mes ? 'Mes ' + a.mes : '') +
      filaFicha('Sitio', sitio ? sitio.rotulo : a.sitio) +
      filaFicha('Métrica', a.metrica, true) +
      filaFicha('Posible causa', causa ? causa.causa : '') +
      filaFicha('Cómo resolver', causa ? causa.resolucion : '');
    if (!filas && !a.sitio) return '';
    // La ficha (codigo/mes/sitio/metrica/causa) dice QUE se detecto; la tabla de abajo
    // -las lecturas crudas del sitio completo, no solo la celda senalada- es lo que
    // hace falta para dar un veredicto sin saltar a otra pantalla. Se carga sola
    // (perezosa, ver wireTablasAviso) porque puede haber muchos avisos en un mismo
    // corte y no tiene sentido pedirle al servidor las 9 magnitudes de cada uno antes
    // de que alguien vaya a mirarlas.
    return (
      '<details class="infodato aviso-detalle" data-sitio="' +
      Fmt.esc(a.sitio || '') +
      '" data-mes="' +
      (a.mes || '') +
      '" data-metrica="' +
      Fmt.esc(a.metrica || '') +
      '"><summary>Ver la tabla completa y dar un veredicto</summary>' +
      '<dl class="ficha">' +
      filas +
      '</dl>' +
      (a.sitio
        ? '<div class="aviso-tabla" data-cargada="0"><p class="aviso-tabla-cargando">' +
          'Cargando las lecturas de ' +
          (sitio ? Fmt.esc(sitio.rotulo) : Fmt.esc(a.sitio)) +
          '…</p></div>'
        : '') +
      // el veredicto en si (confirmar o ya confirmado): solo los avisos de gravedad
      // 'aviso' lo tienen — un 'error' (valor_negativo, mes_incompleto...) no se
      // avala, se corrige, y bloqueVeredicto devuelve '' para esos.
      bloqueVeredicto(a) +
      '</details>'
    );
  }
  /**
   * El veredicto de un aviso de salto atipico (migracion 0017): ya confirmado (con
   * quien y cuando) o un formulario minimo para confirmarlo ahora. Nunca para
   * gravedad 'error' — ese no es un juicio que se pueda avalar.
   */
  function bloqueVeredicto(a) {
    if (a.gravedad === 'error') return '';
    if (a.confirmado) {
      return (
        '<p class="aviso-confirmado-nota">✓ Confirmado por ' +
        Fmt.esc(a.confirmadoPor) +
        (a.confirmadoEn ? ', ' + Fmt.esc(Fmt.fechaHora(a.confirmadoEn)) : '') +
        (a.nota ? '<i>' + Fmt.esc(a.nota) + '</i>' : '') +
        '</p>'
      );
    }
    return (
      '<div class="aviso-confirmar" data-mes="' +
      (a.mes || '') +
      '" data-sitio="' +
      Fmt.esc(a.sitio || '') +
      '" data-metrica="' +
      Fmt.esc(a.metrica || '') +
      '" data-codigo="' +
      Fmt.esc(a.codigo || '') +
      '">' +
      '<label class="conf-campo"><span>Confirmado por</span>' +
      '<input type="text" class="conf-quien" maxlength="60" placeholder="Nombre"></label>' +
      '<label class="conf-campo conf-nota"><span>Nota (opcional)</span>' +
      '<input type="text" class="conf-nota-i" maxlength="300"></label>' +
      '<button type="button" class="conf-boton">Ya lo revisé, es correcto</button>' +
      '<p class="conf-error" hidden></p>' +
      '</div>'
    );
  }
  /**
   * Trae /api/ehs/datos del sitio del aviso (las mismas 9 magnitudes de "06 Datos",
   * un sitio a la vez) y las dibuja completas: el mes y la magnitud que dispararon el
   * aviso resaltados, el resto de la fila/columna visible alrededor para dar contexto
   * y poder decidir si es un error de captura o un mes de verdad atipico.
   */
  async function cargarTablaAviso(cont, sitioId, mes, metricaId) {
    try {
      var d = await api('datos', { ambito: sitioId });
      cont.innerHTML =
        '<div class="tablabox"><table class="matriz datos-tabla aviso-tabla-t"><tr><th>Mes</th>' +
        d.magnitudes
          .map(function (g) {
            return (
              '<th class="num' +
              (g.id === metricaId ? ' aviso-foco' : '') +
              '">' +
              Fmt.esc(g.nombre) +
              '<small>' +
              Fmt.esc(g.unidad) +
              '</small></th>'
            );
          })
          .join('') +
        '</tr>' +
        d.meses
          .map(function (m) {
            return (
              '<tr' +
              (m.mes === mes ? ' class="datos-sel"' : '') +
              '><th>' +
              Fmt.mesLargo[m.mes - 1] +
              '</th>' +
              d.magnitudes
                .map(function (g) {
                  return (
                    '<td class="num' +
                    (g.id === metricaId ? ' aviso-foco' : '') +
                    '">' +
                    crudo(m.lecturas[g.id]) +
                    '</td>'
                  );
                })
                .join('') +
              '</tr>'
            );
          })
          .join('') +
        '</table></div>';
    } catch (err) {
      // 'sin_implementar' (ver src/datos/adaptador_json.js: /api/ehs/datos a
      // proposito no calcula nada en modo interinato/Vercel, solo en ORIGEN_DATOS=sql)
      // es permanente para este despliegue - reintentar nunca va a funcionar, y
      // "Intenta de nuevo" ahi era un mensaje falso. Descubierto probando esta misma
      // funcion en el despliegue de Vercel (donde SIEMPRE falla asi), no en la
      // instalacion local (que corre contra SQL Server y nunca lo pisaba).
      var permanente = err.codigo === 'sin_implementar';
      cont.innerHTML =
        '<p class="aviso-tabla-error">' +
        (permanente
          ? 'Esta tabla necesita la instalación con base de datos. No está disponible ' +
            'en este despliegue interinato (sin SQL Server detrás).'
          : 'No se pudo cargar la tabla. Intenta de nuevo.') +
        '</p>';
      // en cont, no en cont.parentElement (el <details>): wireTablasAviso lee
      // cont.dataset.cargada para decidir si reintenta al volver a abrir. Con el
      // flag puesto en el elemento equivocado, "Intenta de nuevo" no reintentaba
      // nada - colapsar y reabrir el desplegable no volvia a pedir el dato. Para el
      // caso permanente se deja en '1' a propósito: reintentar un 'sin_implementar'
      // solo repetiria el mismo error.
      cont.dataset.cargada = permanente ? '1' : '0';
      console.error(err);
    }
  }
  /** Perezoso a proposito (ver el comentario de fichaAviso): solo pide /api/ehs/datos
   *  del sitio la primera vez que alguien abre ESE desplegable en concreto. */
  function wireTablasAviso() {
    document.querySelectorAll('#cajaAvisos details.aviso-detalle').forEach(function (det) {
      det.addEventListener('toggle', function () {
        if (!det.open) return;
        var cont = det.querySelector('.aviso-tabla');
        if (!cont || cont.dataset.cargada === '1') return;
        cont.dataset.cargada = '1';
        cargarTablaAviso(
          cont,
          det.dataset.sitio,
          parseInt(det.dataset.mes, 10) || null,
          det.dataset.metrica || null
        );
      });
    });
  }
  // Cache por URL, vigente mientras dure la pagina: cambiar de vista no vuelve a pedir
  // lo mismo (ej. 'panorama' lo piden cuatro vistas con los mismos parametros), y dos
  // llamadas identicas en paralelo comparten la misma promesa en vez de duplicar el
  // viaje de red. Una correccion real recarga la pagina (/corregir es otra pantalla).
  // Confirmar un aviso (migracion 0017) es la unica escritura que ocurre SIN salir de
  // este tablero: invalidarCacheApi de abajo le hace falta a ella sola.
  var cacheApi = {};
  async function api(recurso, params) {
    var q = new URLSearchParams();
    if (S.anio) q.set('anio', S.anio);
    Object.keys(params || {}).forEach(function (k) {
      if (params[k] !== null && params[k] !== undefined) q.set(k, params[k]);
    });
    var url = '/api/ehs/' + recurso + (q.toString() ? '?' + q.toString() : '');
    if (!cacheApi[url]) {
      cacheApi[url] = fetch(url).then(function (r) {
        if (r.ok) return r.json();
        // el cuerpo del error ({error,mensaje,detalle}, ver src/errores.js) se
        // adjunta al Error en vez de descartarse: sin esto, un 501
        // 'sin_implementar' (ej. /api/ehs/datos en modo JSON, que a proposito
        // nunca calcula esa vista) y una caida de red se veian identicos para
        // quien llama - no hay forma de mostrar un mensaje distinto para "esto
        // nunca va a funcionar en este despliegue" contra "intenta de nuevo".
        return r
          .json()
          .catch(function () {
            return null;
          })
          .then(function (cuerpo) {
            var err = new Error(recurso + ' -> ' + r.status);
            if (cuerpo && cuerpo.error) {
              err.codigo = cuerpo.error;
              err.mensaje = cuerpo.mensaje;
              err.detalle = cuerpo.detalle;
            }
            throw err;
          });
      });
      cacheApi[url].catch(function () {
        delete cacheApi[url];
      });
    }
    return cacheApi[url];
  }
  /** Olvida lo cacheado de un recurso (todas sus variantes de query string), para que
   *  la proxima llamada a api() vuelva a pedirlo. Solo la usa enviarConfirmacionAviso. */
  function invalidarCacheApi(recurso) {
    var prefijo = '/api/ehs/' + recurso;
    Object.keys(cacheApi).forEach(function (url) {
      if (url === prefijo || url.indexOf(prefijo + '?') === 0) delete cacheApi[url];
    });
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
  // Los meses que tiene el ambito elegido. Peru y Colombia + Peru pueden ir un mes atras
  // de Colombia (migracion 0021), asi que la fila de meses se vuelve a pintar cada vez
  // que cambia el ambito y no solo al cargar.
  function pintarMeses() {
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
  }

  // El ambito para el que ya se resolvieron sus meses y su corte propio. El servidor
  // contesta con el ultimo mes que el ambito si tiene, asi que pedir Peru en agosto da
  // julio y corte.mes lo dice: el mes elegido se ajusta a ese antes de pintar nada.
  var ambitoResuelto = null;
  async function resolverAmbito() {
    var pan = await api('panorama', { mes: S.mes, ambito: S.ambito });
    mesesConDato = pan.corte.mesesConDato;
    if (mesesConDato.indexOf(S.mes) < 0) S.mes = pan.corte.mes;
    pintarMeses();
    ambitoResuelto = S.ambito;
  }

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
    // Dos subgrupos con su propio rotulo chiquito arriba (consolidados / sitios),
    // en vez de una sola fila de 7 botones sin distincion — pedido explicito: "en
    // el filtro de sitio meter sub secciones de las opciones".
    $('#segSitio').innerHTML = GRUPOS_AMBITO.map(function (g) {
      return (
        '<div class="seg-grupo">' +
        '<span class="seg-grupo-titulo">' +
        g.titulo +
        '</span>' +
        '<div class="seg" role="radiogroup" aria-label="' +
        g.titulo +
        '">' +
        g.items
          .map(function (a) {
            return (
              '<button type="button" role="radio" data-ambito="' +
              a.id +
              '">' +
              a.rotulo +
              '</button>'
            );
          })
          .join('') +
        '</div></div>'
      );
    }).join('');
    pintarMeses();

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
    // aria-checked, no aria-pressed: ehs.css solo estiliza ".seg button[aria-checked]"
    // (son controles de radiogroup, no botones de si/no) — con aria-pressed el botón
    // elegido de Sitio o Mes nunca se veía resaltado, aunque el estado sí cambiara.
    document.querySelectorAll('#segSitio button').forEach(function (b) {
      b.setAttribute('aria-checked', String(b.dataset.ambito === S.ambito));
    });
    document.querySelectorAll('#segMes button').forEach(function (b) {
      b.setAttribute('aria-checked', String(parseInt(b.dataset.mes, 10) === S.mes));
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

    // De aqui en adelante todo depende solo de pan/S.kpi/S.mes, ya resueltos: se pide
    // en paralelo en vez de en fila (eran cuatro viajes de red uno detras de otro).
    // trayectoria-anual se captura aparte (igual que ya hace pintarTrayectoriaPropia):
    // sin esto, un ambito/kpi sin cierre anual (scorecard_anual vacio para el, por
    // ejemplo cualquiera de los paises LATAM nuevos o un ambiente recien migrado)
    // hacia fallar el Promise.all entero y con el se perdian serie/porSitio/matriz,
    // que SI habian respondido bien.
    var previos = await Promise.all([
      api('serie-mensual', { ambito: S.ambito, kpi: S.kpi }),
      api('kpi-por-sitio', { mes: S.mes, kpi: S.kpi }),
      api('trayectoria-anual', { kpi: S.kpi, ambito: 'colombia_peru' }).catch(function () {
        return null;
      }),
      pintarMatrizSitios(pan),
    ]);
    var serie = previos[0];
    var porSitio = previos[1];
    var tray = previos[2];

    serie.dec = foco.dec;
    $('#hFoco').textContent = foco.kpi + ' en el tiempo';
    $('#subFoco').textContent = pan.ambito.nombre + ' · acumulado a ' + mesElegido(pan);
    Graficos.serieKpi('gFoco', serie, S.mes);
    $('#notaFoco').innerHTML = nota(textoContraMeta(foco));

    $('#subSitios').textContent = foco.kpi + ' · acumulado a ' + mesElegido(pan);
    Graficos.porSitio('gSitios', porSitio, foco.dec);
    var fuera = porSitio.sitios.filter(function (s) {
      return s.estado === 'incumple';
    });
    $('#notaSitios').innerHTML = nota(
      'Cada sitio se mide contra <b>su propia meta</b> (la marca vertical). Las metas por sitio son muy ' +
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
    // este tablero"). tray ya se pidio arriba, en paralelo con serie/porSitio; puede
    // venir null (scorecard_anual sin cierres para este kpi todavia, ver el catch de
    // arriba) y este panel se vacia solo, sin tumbar el resto de pintarPanorama.
    if (!tray) {
      $('#subTray').textContent = '';
      $('#gTray').innerHTML = '';
      $('#notaTray').innerHTML = nota(
        'El scorecard corporativo no publica cierres anteriores de este indicador todavía.'
      );
    } else {
      $('#subTray').textContent = tray.kpi + ' · perímetro ' + tray.perimetro;
      Graficos.trayectoria('gTray', tray);
      $('#notaTray').innerHTML = nota(textoTrayectoria(tray));
    }
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
    if (!cerrados.length) return 'Sin cierres anteriores cargados todavía para este ámbito.';
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

  /** Panel "Histórico" (cierres año contra año) de un recurso, para el ámbito elegido.
   *  Nacional Labs nunca tuvo historia propia cargada (es un agregado sin meta ni
   *  serie anual, ver AMBITOS_CON_HISTORIA en rutas_api.js): la API responde 400 en
   *  vez de un JSON vacio, y sin capturarlo aqui la excepcion se comia el resto de la
   *  funcion que llama a esta - el panel de abajo (contraste mensual) tampoco pintaba. */
  async function pintarTrayectoriaPropia(ids, kpi) {
    var tray;
    try {
      tray = await api('trayectoria-anual', { kpi: kpi, ambito: S.ambito });
    } catch {
      tray = null;
    }
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

  /* ------------------------------------------------------------ contraste mensual ---
   * Dos años elegidos, mes a mes, para el ámbito de arriba (pedido en la reunión del
   * 24-sep-2026: "yo pueda colocar aquí el año que yo quiera confrontar"). Los
   * selectores de año se llenan una sola vez (ANIOS_CONTRASTE, fijo: es el rango que
   * carga la migración 0012); cambiar cualquiera de los dos vuelve a pedir y repintar
   * solo esa tabla, no toda la vista.
   *
   * Sin 2023: regla del área (27-sep-2026), "solo datos desde 2024 en adelante" en
   * base de datos y visualización. 2023 SÍ tiene datos reales en la base — 144
   * lecturas mensuales (agua, energía, unidades y residuo total de los tres sitios,
   * migración 0012) y su cierre en ehs.scorecard_anual —, así que se excluye por la
   * regla, no por falta de dato. Nada de 2023 se borró de la base (trayectoriaAnual,
   * en ambos adaptadores, lo filtra al leer): borrarlo es una decisión aparte,
   * irreversible, que le corresponde a Samuel.
   */
  var ANIOS_CONTRASTE = [2024, 2025, 2026];

  function selectsContraste(kpi) {
    return $all('select.contraste-anio[data-kpi="' + kpi + '"]');
  }

  function prepararSelectsContraste(kpi, tablaId) {
    var selects = selectsContraste(kpi);
    if (!selects.length || selects[0].dataset.listo) return;
    selects.forEach(function (sel) {
      sel.innerHTML = ANIOS_CONTRASTE.map(function (a) {
        return '<option value="' + a + '">' + a + '</option>';
      }).join('');
      // A = el año anterior al último, B = el último: lo que se pidió en la reunión
      // ("2025 contra 2026, como hoy") sin fijar el año en el código.
      sel.value =
        sel.dataset.cual === 'A'
          ? ANIOS_CONTRASTE[ANIOS_CONTRASTE.length - 2]
          : ANIOS_CONTRASTE[ANIOS_CONTRASTE.length - 1];
      sel.dataset.listo = '1';
      sel.addEventListener('change', function () {
        pintarContraste(kpi, tablaId);
      });
    });
  }

  async function pintarContraste(kpi, tablaId) {
    var selects = selectsContraste(kpi);
    if (!selects.length) return;
    var anioA = Number(
      selects.filter(function (s) {
        return s.dataset.cual === 'A';
      })[0].value
    );
    var anioB = Number(
      selects.filter(function (s) {
        return s.dataset.cual === 'B';
      })[0].value
    );
    var tabla = $(tablaId);
    // gContrasteAgua a partir de tContrasteAgua: mismo sufijo, el chart vive junto a
    // la tabla que ya existia (ver dashboard.ejs).
    var graficoIdRaw = tablaId.slice(1).replace(/^t/, 'g');
    var grafico = $('#' + graficoIdRaw);

    if (anioA === anioB) {
      tabla.innerHTML = '<div class="vacio"><p>Elige dos años distintos para comparar.</p></div>';
      if (grafico) grafico.innerHTML = '';
      return;
    }

    // Nacional Labs nunca tuvo historia propia (ver pintarTrayectoriaPropia arriba):
    // la API responde 400 en vez de un JSON vacio, y sin capturarlo la excepcion se
    // comia el resto de la funcion que llama a esta.
    var r;
    try {
      r = await api('contraste-mensual', {
        ambito: S.ambito,
        kpi: kpi,
        anioA: anioA,
        anioB: anioB,
      });
    } catch {
      r = null;
    }
    if (
      !r ||
      r.meses.every(function (m) {
        return m.valorA === null && m.valorB === null;
      })
    ) {
      tabla.innerHTML =
        '<div class="vacio"><span class="chip sinmeta">sin dato</span>' +
        '<p>Este ámbito no tiene lecturas de ' +
        Fmt.esc(r ? r.kpi : kpi) +
        ' en ' +
        anioA +
        ' ni en ' +
        anioB +
        '.</p></div>';
      if (grafico) grafico.innerHTML = '';
      return;
    }

    if (grafico) Graficos.contraste(graficoIdRaw, r, anioA, anioB);

    var dec = r.dec;
    tabla.innerHTML =
      '<table class="matriz"><tr><th>Mes</th>' +
      '<th class="num">' +
      anioA +
      '</th><th class="num">YTD ' +
      anioA +
      '</th>' +
      '<th class="num">' +
      anioB +
      '</th><th class="num">YTD ' +
      anioB +
      '</th>' +
      '<th class="num">Δ mensual</th></tr>' +
      r.meses
        .map(function (m) {
          var delta =
            m.valorA != null && m.valorB != null && m.valorA !== 0
              ? ((m.valorB - m.valorA) / m.valorA) * 100
              : null;
          return (
            '<tr><th>' +
            Fmt.esc(m.nombre_mes || Fmt.mesLargo[m.mes - 1]) +
            '</th><td class="num">' +
            Fmt.num(m.valorA, dec) +
            '</td><td class="num">' +
            Fmt.num(m.ytdA, dec) +
            '</td><td class="num">' +
            Fmt.num(m.valorB, dec) +
            '</td><td class="num">' +
            Fmt.num(m.ytdB, dec) +
            '</td><td class="num ' +
            signoClase(delta) +
            '">' +
            Fmt.pctDirecto(delta) +
            '</td></tr>'
          );
        })
        .join('') +
      '</table>';
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
    cfg.dibujarCombo(ids.comboRaw, datos.filas, cfg.meta, S.mes);
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
    // Los meses sin lectura todavia se dejan como fila de referencia (sin dato, no
    // ausentes): el año completo se ve de una vez, igual que ya hace el grafico combo.
    var filasTabla = Fmt.mesLargo.map(function (nombreMes, i) {
      var mes = i + 1;
      var real = datos.filas.filter(function (x) {
        return x.mes === mes;
      })[0];
      return real || { mes: mes, nombre_mes: nombreMes };
    });
    $(ids.tabla).innerHTML =
      '<table class="matriz"><tr><th>Mes</th><th class="num">' +
      cfg.colConsumo +
      '</th><th class="num">Lentes</th>' +
      '<th class="num">' +
      cfg.colRatio +
      '</th><th class="num">Δ total</th><th class="num">Δ por lente</th></tr>' +
      filasTabla
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
    // Las cinco peticiones de esta vista solo dependen de S.mes/S.ambito, ninguna del
    // resultado de otra: se piden todas en paralelo (eran hasta 5 viajes en fila).
    var previos = await Promise.all([
      api('agua-mensual', { ambito: S.ambito }),
      api('agua-diaria', { mes: S.mes, sitio: S.ambito }),
      api('panorama', { mes: S.mes, ambito: S.ambito }),
      api('energia-mensual', { ambito: S.ambito }),
      api('kpi-por-sitio', { mes: S.mes, kpi: 'energia_por_lente' }),
    ]);
    var agua = previos[0];
    var diario = previos[1];
    var pan = previos[2];
    var energia = previos[3];
    var porSitioEnergia = previos[4];

    var kAgua = pan.kpi.filter(function (k) {
      return k.kpi_id === 'agua_por_lente';
    })[0];
    var kEne = pan.kpi.filter(function (k) {
      return k.kpi_id === 'energia_por_lente';
    })[0];

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
        meta: kAgua ? kAgua.meta : null,
        notaCombo:
          'Las barras son el consumo total del mes; la línea es lo que le toca a cada lente ' +
          'producido, con el máximo y el mínimo anotados dentro del propio gráfico. Un total ' +
          'más alto no siempre es peor: si la producción también subió, el consumo por lente ' +
          'puede bajar igual — los lentes procesados de cada mes están en la tabla de abajo. ' +
          'La punteada es una referencia mensual, no la meta oficial: esa se mide acumulada y ' +
          'se ve en la ficha de Agua en Panorama.',
        colConsumo: 'Consumo m³',
        colRatio: 'l/lente',
        campoConsumo: 'consumo_m3',
        decConsumo: 0,
        campoRatio: 'l_por_lente',
        decRatio: 2,
      }
    );

    // Panel opcional: solo ocupa espacio cuando hay registro diario real que mostrar.
    // Se enciende solo en cuanto el area empiece a cargarlo, sin placeholder de "proximamente".
    $('#panelAguaDiario').toggleAttribute('hidden', !diario.disponible);
    if (diario.disponible) {
      $('#subAguaDiario').textContent = diario.dias.length + ' lecturas';
      $('#cajaAguaDiario').innerHTML = '';
    }

    // --------------------------------------------------------------- energía ---
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
        meta: kEne ? kEne.meta : null,
        notaCombo:
          'Igual que con el agua: las barras son el consumo total del mes y la línea es el ' +
          'consumo por lente. La producción de cada mes, que explica buena parte del vaivén, ' +
          'está en la tabla de abajo. La punteada es una referencia mensual, no la meta ' +
          'oficial: esa se mide acumulada y se ve en la ficha de Energía en Panorama.',
        colConsumo: 'Consumo kWh',
        colRatio: 'kWh/lente',
        campoConsumo: 'consumo_kwh',
        decConsumo: 0,
        campoRatio: 'kwh_por_lente',
        decRatio: 2,
      }
    );

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
      {
        sub: '#subAguaTray',
        grafico: '#gAguaTray',
        graficoRaw: 'gAguaTray',
        nota: '#notaAguaTray',
      },
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

    prepararSelectsContraste('agua_por_lente', '#tContrasteAgua');
    prepararSelectsContraste('energia_por_lente', '#tContrasteEnergia');
    await pintarContraste('agua_por_lente', '#tContrasteAgua');
    await pintarContraste('energia_por_lente', '#tContrasteEnergia');
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
    Graficos.serieKpi('gResiduos', res, S.mes);
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

    // consumo total (comboProduccion): 'residuos-composicion' ya trae suma_kg/
    // suma_g_lente por mes (se calculan para la grafica de composicion) - reusar esa
    // misma peticion evita pedirle al servidor un endpoint que ya tiene el dato.
    $('#subResCombo').textContent = comp.ambito.nombre + ' · ' + comp.meses.length + ' meses';
    Graficos.residuosCombo('gResCombo', comp.meses, kRes.meta, S.mes);
    $('#notaResCombo').innerHTML = nota(
      'Las barras son el consumo total de residuos del mes, en kilos; la línea es lo que le ' +
        'toca a cada lente producido. Un total más alto no siempre es peor si la producción ' +
        'también subió. De qué está hecho ese total está en el gráfico de abajo. La punteada ' +
        'es una referencia mensual, no la meta oficial: esa se mide acumulada y se ve en ' +
        '"Residuos en el tiempo", arriba.'
    );

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

    prepararSelectsContraste('residuos_por_lente', '#tContrasteResiduos');
    await pintarContraste('residuos_por_lente', '#tContrasteResiduos');
  }

  function pintarAcumuladoComp(comp) {
    // 'total' es la unica parte que trae Peru (residuo sin desglose): con nombre y
    // color propios en vez de filtrarse, para no dejar la lista vacia y sin poder
    // calcular "mayor" (reduce sobre un arreglo vacio revienta). El 'total' fantasma
    // que SI hay que descartar en Colombia/Celta/Estrella/Agencias ya no llega desde
    // la SQL (adaptador_sql.js, residuosComposicion).
    var nombre = {
      peligroso: 'Peligroso',
      aprovechable: 'Aprovechable',
      ordinario: 'Ordinario',
      total: 'Total',
    };
    // 'total' en su propio tono (no el mismo que "Aprovechable"): en Colombia + Peru
    // las cuatro partes aparecen juntas en esta misma lista.
    var color = {
      peligroso: Graficos.colores.incumple,
      aprovechable: Graficos.colores.amb,
      ordinario: Graficos.colores.inst,
      total: Graficos.colores.tenue,
    };
    // Sin filtro de nombre[a.parte]: adaptador_sql.js ya garantiza que comp.acumulado
    // solo trae magnitudes con dato real para el ambito, y el mapa de arriba ya cubre
    // las 4 posibles - filtrar aqui era una defensa que nunca se activaba.
    var acumulado = comp.acumulado;
    var mayor = acumulado.reduce(function (a, b) {
      return b.part > a.part ? b : a;
    });
    $('#subAcumComp').textContent = 'acumulado del año';
    $('#cajaAcumComp').innerHTML =
      acumulado
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
    // 'total' es la unica parte que trae Peru (residuo sin desglose): con nombre
    // propio para poder compararla, en vez de filtrarla y dejar comp.partes vacio
    // (reduce sobre un arreglo vacio revienta). El 'total' fantasma que SI hay que
    // descartar en Colombia/Celta/Estrella/Agencias ya no llega desde la SQL
    // (adaptador_sql.js, residuosComposicion).
    var nombre = {
      peligroso: 'el peligroso',
      aprovechable: 'el aprovechable',
      ordinario: 'el ordinario',
      total: 'el total',
    };
    // Sin filtro de nombre[p]: adaptador_sql.js ya garantiza que comp.partes solo trae
    // magnitudes con dato real para el ambito, y el mapa de arriba ya cubre las 4
    // posibles - filtrar aqui era una defensa que nunca se activaba.
    var salto = comp.partes
      .map(function (p) {
        return { parte: p, delta: (ult[p + '_g_lente'] || 0) - (ant[p + '_g_lente'] || 0) };
      })
      .reduce(function (a, b) {
        return Math.abs(b.delta) > Math.abs(a.delta) ? b : a;
      });
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
    Graficos.serieKpi('gFR', fr, S.mes);
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
    Graficos.serieKpi('gAcc', acc, S.mes);
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
    // Solo los abiertos: un hallazgo ya corregido en el libro no "altera un número"
    // hoy, y contarlo aquí haría ver el libro peor de lo que está.
    var errores = cal.hallazgos.filter(function (h) {
      return h.gravedad === 'error' && !h.resuelto;
    }).length;
    $('#tarjetasCal').innerHTML = [
      ['Meses con dato', cal.meses_con_dato.length + '<small>de 12</small>'],
      ['Lecturas cargadas', String(cal.lecturas)],
      ['Lecturas diarias de agua', String(cal.lecturas_diarias)],
      ['Hallazgos del libro', errores + '<small>abiertos que alteran un número</small>'],
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
      'Descargar el detalle crudo en CSV</a><span>Todas las magnitudes tal como se ' +
      // "nueve" quedo fijo cuando solo Colombia capturaba; Peru suma una decima
      // (residuo_total_kg, sin desglose) que este CSV ya trae en su propia columna —
      // ver ehs\CLAUDE.md. Sin numero fijo aqui para no volver a quedar mal si el area
      // agrega otro sitio u otra magnitud.
      'capturaron, sin ningún cálculo encima.</span></p>';

    // 'resuelto' separa lo que YA se corrigio (en el libro fuente, no solo en el
    // tablero) de lo que sigue abierto: sin la separacion, un hallazgo ya cerrado se
    // lee igual de urgente que uno vigente, y la lista entera se ve peor de lo que
    // esta. Se queda documentado (nunca se borra: es la bitacora de la auditoria),
    // solo se colapsa fuera del camino.
    var activos = cal.hallazgos.filter(function (h) {
      return !h.resuelto;
    });
    var resueltos = cal.hallazgos.filter(function (h) {
      return h.resuelto;
    });
    $('#subHallazgos').textContent =
      activos.length +
      (activos.length === 1 ? ' abierto · ' : ' abiertos · ') +
      errores +
      ' alteran un número' +
      (resueltos.length ? ' · ' + resueltos.length + ' ya corregidos' : '');
    var filaHallazgo = function (h) {
      return (
        '<li class="' +
        (h.gravedad === 'error' && !h.resuelto ? 'grave' : '') +
        '">' +
        (h.resuelto
          ? chip('cumple', 'ya corregido')
          : chip(
              h.gravedad === 'error' ? 'incumple' : 'riesgo',
              h.gravedad === 'error' ? 'altera un número' : 'confunde'
            )) +
        '<div><b>' +
        Fmt.esc(h.titulo) +
        '</b><p>' +
        Fmt.esc(h.detalle) +
        ' ' +
        Fmt.esc(h.impacto) +
        '</p>' +
        fichaHallazgo(h) +
        '</div></li>'
      );
    };
    $('#cajaHallazgos').innerHTML =
      '<ul class="hall">' +
      activos.map(filaHallazgo).join('') +
      '</ul>' +
      (resueltos.length
        ? '<details class="infodato resueltos-detalle"><summary>' +
          resueltos.length +
          (resueltos.length === 1 ? ' hallazgo ya corregido' : ' hallazgos ya corregidos') +
          '</summary><ul class="hall">' +
          resueltos.map(filaHallazgo).join('') +
          '</ul></details>'
        : '');

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
    // 'confirmado' (migracion 0017) separa lo que el area ya reviso y dio por bueno
    // de lo que sigue esperando un veredicto — mismo criterio que 'resuelto' ya usa
    // arriba para los hallazgos del libro.
    var confirmados = suaves.filter(function (a) {
      return a.confirmado;
    });
    var pendientes = suaves.filter(function (a) {
      return !a.confirmado;
    });
    $('#subAvisos').textContent = avisos.length
      ? avisos.length +
        ' · ' +
        errores.length +
        (errores.length === 1 ? ' bloqueante' : ' bloqueantes') +
        (confirmados.length ? ' · ' + confirmados.length + ' ya confirmados' : '')
      : 'ninguno';

    if (!avisos.length) {
      $('#cajaAvisos').innerHTML =
        '<div class="vacio"><span class="chip cumple">sin avisos</span>' +
        '<p>Ningún duplicado, valor negativo, denominador en cero, mes incompleto ni salto ' +
        'atípico mes a mes en los datos de este corte.</p></div>';
      $('#notaAvisos').innerHTML = '';
      return;
    }
    var filaAviso = function (a) {
      return (
        '<li class="' +
        (a.gravedad === 'error' ? 'grave' : '') +
        '">' +
        (a.confirmado
          ? chip('cumple', 'confirmado')
          : chip(
              a.gravedad === 'error' ? 'incumple' : 'riesgo',
              a.gravedad === 'error' ? 'bloqueante' : 'a revisar'
            )) +
        '<div><p>' +
        Fmt.esc(a.mensaje) +
        '</p>' +
        fichaAviso(a) +
        '</div></li>'
      );
    };
    $('#cajaAvisos').innerHTML =
      '<ul class="hall">' +
      errores.concat(pendientes).map(filaAviso).join('') +
      '</ul>' +
      (confirmados.length
        ? '<details class="infodato resueltos-detalle"><summary>' +
          confirmados.length +
          (confirmados.length === 1 ? ' aviso ya confirmado' : ' avisos ya confirmados') +
          '</summary><ul class="hall">' +
          confirmados.map(filaAviso).join('') +
          '</ul></details>'
        : '');
    $('#notaAvisos').innerHTML = nota(
      'Un aviso <b>no corrige nada ni bloquea la publicación</b>: señala. Un dato raro puede ser un ' +
        'error de captura o un mes de verdad atípico, y quien lo sabe es el área. Lo que no puede pasar ' +
        'es que nadie se entere.'
    );
    wireTablasAviso();
    wireConfirmarAvisos();
  }
  /** Cablea el boton "Ya lo revisé, es correcto" de cada aviso pendiente. Igual que
   *  wireTablasAviso, se vuelve a llamar cada vez que #cajaAvisos se repinta entero. */
  function wireConfirmarAvisos() {
    document.querySelectorAll('#cajaAvisos .aviso-confirmar').forEach(function (cont) {
      cont.querySelector('.conf-boton').addEventListener('click', function () {
        enviarConfirmacionAviso(cont);
      });
    });
  }
  /** Manda el veredicto a /api/ehs/aviso/confirmar. Al confirmar, invalida el cache de
   *  calidad-dato (la unica escritura que ocurre sin salir de este tablero) y vuelve a
   *  pintar la seccion entera con el estado real que devuelve la base. */
  async function enviarConfirmacionAviso(cont) {
    var campoQuien = cont.querySelector('.conf-quien');
    var errorEl = cont.querySelector('.conf-error');
    var boton = cont.querySelector('.conf-boton');
    errorEl.hidden = true;
    var quien = String(campoQuien.value || '').trim();
    if (!quien) {
      errorEl.textContent = 'Falta escribir quién confirma.';
      errorEl.hidden = false;
      campoQuien.focus();
      return;
    }
    var notaTexto = String(cont.querySelector('.conf-nota-i').value || '').trim();
    boton.disabled = true;
    boton.textContent = 'Confirmando…';
    // El reset del boton va en finally y no al final del try: dos de las tres salidas
    // de error (!r.ok, persistido===false) hacian return antes de llegar ahi y dejaban
    // el boton pegado en "Confirmando…" para siempre. Resetear un boton que
    // pintarCalidad() ya reemplazo (el camino sin error) no hace nada — el elemento
    // esta desconectado del documento — asi que es seguro hacerlo siempre.
    try {
      var r = await fetch('/api/ehs/aviso/confirmar', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          anio: S.anio,
          mes: parseInt(cont.dataset.mes, 10) || null,
          sitio: cont.dataset.sitio,
          magnitud: cont.dataset.metrica,
          codigo: cont.dataset.codigo,
          confirmadoPor: quien,
          nota: notaTexto || undefined,
        }),
      });
      var cuerpo = await r.json().catch(function () {
        return null;
      });
      if (!r.ok) {
        errorEl.textContent = (cuerpo && cuerpo.mensaje) || 'El servidor rechazó la confirmación.';
        errorEl.hidden = false;
        return;
      }
      if (cuerpo && cuerpo.persistido === false) {
        // interinato/Vercel: validado pero sin base de datos donde guardarlo (ver
        // escritura_simulada.js). Mismo mensaje que ya usan captura.js y corregir.js.
        errorEl.textContent = cuerpo.aviso || 'Interinato sin base de datos: no se guardó nada.';
        errorEl.hidden = false;
        return;
      }
      invalidarCacheApi('calidad-dato');
      await pintarCalidad();
    } catch (e) {
      errorEl.textContent = 'No se pudo hablar con el servidor: ' + e.message;
      errorEl.hidden = false;
    } finally {
      boton.disabled = false;
      boton.textContent = 'Ya lo revisé, es correcto';
    }
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

    // Una magnitud que JAMAS trae dato en ningun mes de este ambito no es un hueco de
    // captura: es estructural. residuo_total_kg es el caso real - lo reporta Peru (que
    // no desglosa peligroso/aprovechable/ordinario), nunca Celta/Estrella/Agencias (ver
    // ehs/CLAUDE.md). En un ambito SIN Peru (p. ej. 'nacional') esa columna queda vacia
    // en LAS DOS tablas de esta pantalla, a proposito: lo dice aqui para que no se lea
    // como un hueco, y en sumar() (tabla 02) para que no tumbe la comprobacion.
    var noAplica = {};
    d.magnitudes.forEach(function (g) {
      var apareceAlgunMes = d.meses.some(function (m) {
        return m.lecturas[g.id] !== undefined && m.lecturas[g.id] !== null;
      });
      if (!apareceAlgunMes) noAplica[g.id] = true;
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
            '<th class="num">' +
            Fmt.esc(g.nombre) +
            '<small>' +
            (noAplica[g.id] ? 'no la reporta ningún sitio de este ámbito' : Fmt.esc(g.unidad)) +
            '</small></th>'
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
                var titulo = noAplica[g.id]
                  ? 'No aplica a este ámbito: ningún sitio de aquí reporta esta magnitud (no es un hueco)'
                  : parcial
                    ? 'Falta la lectura de algún sitio: la suma es parcial'
                    : '';
                var editar =
                  unSitio && !noAplica[g.id]
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
                  (noAplica[g.id] ? ' datos-noaplica' : parcial ? ' datos-parcial' : '') +
                  '"' +
                  (titulo ? ' title="' + titulo + '"' : '') +
                  '>' +
                  (noAplica[g.id] ? '<span aria-hidden="true">n/a</span>' : crudo(v)) +
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
    // residuos_por_lente suma las 4 magnitudes de residuo porque en un ambito con Peru
    // cada sitio aporta la suya sin pisar la de otro (verificado con datos reales:
    // Colombia+Peru trae los 4 valores, cada uno identico al de su sitio de origen -
    // cero duplicado). noAplica (arriba) es lo que evita que sumar() corte a null en
    // cuanto toca una magnitud estructuralmente ausente de este ambito - sin eso, TODA
    // fila de residuos daba "no cuadra" sin que hubiera ningun error real.
    var sumar = function (m, lista) {
      if (!lista.length) return null;
      var s = 0;
      var huboValor = false;
      for (var i = 0; i < lista.length; i++) {
        var v = m.lecturas[lista[i]];
        if (v === undefined || v === null) {
          if (noAplica[lista[i]]) continue;
          return null;
        }
        s += Number(v);
        huboValor = true;
      }
      // Si TODAS las magnitudes de la lista son estructuralmente ajenas a este ambito
      // (frequency_rate/accidentes_dafw en Peru, que no reporta horas ni accidentes:
      // ver ehs/CLAUDE.md), el KPI entero es "sin dato" para este ambito, no cero -
      // null, igual que lo que ya responde la API. Sin esto, una lista de UNA sola
      // magnitud noAplica sumaba 0 (bucle vacio) y "0" nunca es igual a "sin dato":
      // toda fila de ese KPI, en ese ambito, daba "no cuadra" sin que hubiera ningun
      // error real. Distinto del caso de residuos (CUATRO magnitudes, solo UNA
      // noAplica): ahi SI hubo valor real que sumar, y el resultado se queda como esta.
      return huboValor ? s : null;
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
    // Misma lista que nombreDe, pero como HTML con cada nombre envuelto para el badge
    // ① / ② de la formula y de los encabezados — escapando cada nombre y unidad por
    // separado, nunca la cadena entera (los conectores '+', '×', '÷' son fijos).
    var nombreDeHtml = function (lista) {
      return lista
        .map(function (id) {
          var g = porMagnitud[id];
          return g
            ? Fmt.esc(g.nombre) + ' <small>(' + Fmt.esc(g.unidad) + ')</small>'
            : Fmt.esc(id);
        })
        .join(' + ');
    };
    var fallas = 0;
    // unidad representativa de numerador/denominador: la de su primera magnitud. En
    // la practica todas las de una misma lista comparten unidad (las 4 de
    // residuos_por_lente son todas kg) - es la unidad ANTES del factor y la
    // division, no la del KPI (k.unidad), que es la de despues.
    var unidadDe = function (lista) {
      if (!lista.length) return '';
      var g = porMagnitud[lista[0]];
      return g ? g.unidad : '';
    };
    $('#cajaDatosKpi').innerHTML = d.kpis
      .map(function (k) {
        var unidadNum = unidadDe(k.numerador);
        var unidadDen = unidadDe(k.denominador);
        // La misma formula, dos veces: en texto plano (para el 'title' de los badges de
        // los encabezados, que no acepta HTML) y en HTML (para pintarla arriba de la
        // tabla con los badges ① ② que tambien llevan los encabezados — asi se ve, sin
        // adivinar, que magnitudes entran en cada columna).
        var formulaTexto =
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
        var formulaHtml =
          '<span class="datos-badge n" title="① numerador: ' +
          Fmt.esc(nombreDe(k.numerador)) +
          '">①</span> ' +
          (k.numerador.length > 1 ? '(' : '') +
          nombreDeHtml(k.numerador) +
          (k.numerador.length > 1 ? ')' : '') +
          (k.factor !== 1 ? ' × ' + Fmt.num(k.factor) : '') +
          (k.denominador.length
            ? ' ÷ <span class="datos-badge d" title="② denominador: ' +
              Fmt.esc(nombreDe(k.denominador)) +
              '">②</span> ' +
              (k.denominador.length > 1 ? '(' : '') +
              nombreDeHtml(k.denominador) +
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
              '</td><td class="num fuerte clave">' +
              Fmt.num(x.valor, k.dec) +
              '</td><td class="num">' +
              crudo(x.ytd_numerador) +
              '</td><td class="num">' +
              (k.denominador.length ? crudo(x.ytd_denominador) : '—') +
              '</td><td class="num fuerte clave">' +
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
          formulaHtml +
          (k.denominador.length ? '' : ' · es un conteo: no divide') +
          '</p><div class="tablabox"><table class="matriz datos-tabla"><tr><th>Mes</th>' +
          '<th class="num" title="① numerador: ' +
          Fmt.esc(formulaTexto) +
          '"><span class="datos-badge n">①</span> Numerador<small>lo que se suma este mes' +
          (unidadNum ? ', en ' + Fmt.esc(unidadNum) : '') +
          '</small></th>' +
          '<th class="num"' +
          (k.denominador.length
            ? ' title="② denominador: ' + Fmt.esc(nombreDe(k.denominador)) + '"'
            : '') +
          '>' +
          (k.denominador.length
            ? '<span class="datos-badge d">②</span> Denominador'
            : 'Denominador') +
          '<small>' +
          (k.denominador.length
            ? 'contra qué se divide, ' + Fmt.esc(unidadDen)
            : 'no aplica: es un conteo') +
          '</small></th>' +
          '<th class="num clave">Indicador del mes<small>① ÷ ②' +
          (k.factor !== 1 ? ' × ' + Fmt.num(k.factor) : '') +
          ', en ' +
          Fmt.esc(k.unidad) +
          ' — solo este mes</small></th>' +
          '<th class="num">① acumulado<small>el mismo numerador, sumado de enero al mes' +
          (unidadNum ? ', ' + Fmt.esc(unidadNum) : '') +
          '</small></th>' +
          '<th class="num">' +
          (k.denominador.length ? '② acumulado' : 'Denominador acum.') +
          '<small>' +
          (k.denominador.length
            ? 'el mismo denominador, sumado de enero al mes, ' + Fmt.esc(unidadDen)
            : 'no aplica: es un conteo') +
          '</small></th>' +
          '<th class="num clave">★ Acumulado (YTD)<small>el número que muestra la ficha del ' +
          'tablero, arriba de esta pantalla</small></th>' +
          '<th>Verificación<small>¿sumar la tabla 01 a mano da este ① y este ②?</small></th></tr>' +
          filas +
          '</table></div></div>'
        );
      })
      .join('');
    $('#subDatosKpi').textContent = fallas
      ? fallas + (fallas === 1 ? ' fila no cuadra' : ' filas no cuadran')
      : 'todo cuadra con las lecturas de la tabla 01';
    $('#notaDatosKpi').innerHTML = nota(
      'Esta tabla prueba, con los números crudos, cómo se arma cada ficha del tablero — nada se ' +
        'escribe a mano. Arriba de cada tabla, la fórmula dice qué magnitudes de la tabla 01 son ' +
        '<b>① el numerador</b> (lo que se mide) y <b>② el denominador</b> (contra qué se mide, casi ' +
        'siempre los lentes producidos). <b>① y ②</b> son esa suma, del mes o acumulada; ' +
        '<b>indicador del mes</b> y <b>★ acumulado (YTD)</b> son el resultado de dividirlos — y el ' +
        '★ es, columna por columna, el mismo número que muestra la ficha de arriba. ' +
        '<b>Verificación</b> dice si sumar a mano las lecturas de la tabla 01 da exactamente ese ' +
        '① y ese ②; si una magnitud de la fórmula nunca trae dato en ningún mes de este ámbito ' +
        '(p. ej. el residuo sin desglose en un ámbito sin Perú — ver la tabla 01, esa columna ' +
        'queda vacía ahí a propósito), no cuenta como un hueco: no le corresponde a este ámbito y ' +
        'se trata como cero, no como dato faltante.' +
        ' <a href="/api/ehs/detalle?formato=csv">Descargar las lecturas en CSV</a>.'
    );

    // --- 03 y 04: metas registradas e historico por anio, del mismo /api/ehs/datos —
    // ningun viaje de red aparte.
    pintarDatosMetas(d);
    pintarDatosHistorico(d);
  }

  /**
   * 03 · todas las metas 2026 registradas para este ambito, no solo la vigente: el
   * libro heredado trajo tres juegos de metas distintos para Colombia (ver
   * ehs/CLAUDE.md) y solo uno quedo vigente. Mostrar los descartados, con su fuente,
   * es lo que le da credibilidad a la meta que si se usa — se ve que no se eligio a
   * ciegas. Un ambito sin meta propia (Nacional Labs: nadie la publica y no se
   * hereda, ver META_DE_AMBITO en adaptador_sql.js) lo dice explicito, no lo esconde.
   */
  function pintarDatosMetas(d) {
    var conMeta = d.kpis.filter(function (k) {
      return k.metas.length;
    });
    if (!conMeta.length) {
      $('#subDatosMetas').textContent = 'sin meta propia';
      $('#cajaDatosMetas').innerHTML =
        '<div class="vacio"><span class="chip sinmeta">sin meta</span>' +
        '<p><b>' +
        Fmt.esc(d.ambito.nombre) +
        '</b> no tiene meta propia en ningún KPI: nadie la publica para este ámbito y no ' +
        'se hereda de otro — heredarla sería inventarla.</p></div>';
      $('#notaDatosMetas').innerHTML = '';
      return;
    }
    var vigentes = 0;
    var otras = [];
    var filas = d.kpis
      .map(function (k) {
        var v = k.metas.filter(function (m) {
          return m.vigente;
        })[0];
        if (v) vigentes++;
        k.metas
          .filter(function (m) {
            return !m.vigente;
          })
          .forEach(function (m) {
            otras.push({
              kpi: k.nombre,
              unidad: k.unidad,
              dec: k.dec,
              valor: m.valor,
              fuente: m.fuente,
            });
          });
        return (
          '<tr><th>' +
          Fmt.esc(k.nombre) +
          '</th><td class="num fuerte">' +
          (v ? Fmt.meta(v.valor, k.dec) + ' <small>' + Fmt.esc(k.unidad) + '</small>' : '—') +
          '</td></tr>'
        );
      })
      .join('');
    $('#subDatosMetas').textContent =
      vigentes + (vigentes === 1 ? ' meta vigente' : ' metas vigentes') + ' de ' + d.kpis.length;
    $('#cajaDatosMetas').innerHTML =
      '<div class="tablabox"><table class="matriz datos-tabla"><tr><th>Indicador</th>' +
      '<th class="num">Meta vigente</th></tr>' +
      filas +
      '</table></div>' +
      (otras.length
        ? '<details class="infodato"><summary>' +
          otras.length +
          (otras.length === 1
            ? ' meta registrada, no vigente'
            : ' metas registradas, no vigentes') +
          '</summary><div class="tablabox"><table class="matriz datos-tabla"><tr><th>Indicador</th>' +
          '<th class="num">Valor</th><th>Fuente</th></tr>' +
          otras
            .map(function (o) {
              return (
                '<tr><th>' +
                Fmt.esc(o.kpi) +
                '</th><td class="num">' +
                Fmt.meta(o.valor, o.dec) +
                ' <small>' +
                Fmt.esc(o.unidad) +
                '</small></td><td>' +
                Fmt.esc(o.fuente) +
                '</td></tr>'
              );
            })
            .join('') +
          '</table></div></details>'
        : '');
    $('#notaDatosMetas').innerHTML = nota(
      'La <b>meta vigente</b> es la que usa todo el tablero para calcular brecha y estado, en ' +
        'esta vista y en todas las demás. Cuando un indicador tiene más de una meta registrada ' +
        '— el libro heredado trajo varios juegos para Colombia — las demás quedan aquí, ' +
        'colapsadas, con su propia fuente: así se ve que la vigente no se eligió a ciegas.'
    );
  }

  /**
   * 04 · el cierre de cada año anterior (scorecard corporativo, desde 2024 — regla del
   * área) y el año en curso, calculado en vivo al mismo corte que el resto de esta
   * vista — una sola fila por año, misma forma para los dos casos. Un ambito sin fila
   * propia en el scorecard (Nacional Labs) lo dice, no deja una tabla vacía sin
   * explicación.
   */
  function pintarDatosHistorico(d) {
    var conHistorico = d.kpis.filter(function (k) {
      return k.historico.length;
    });
    if (!conHistorico.length) {
      $('#subDatosHistorico').textContent = 'sin histórico publicado';
      $('#cajaDatosHistorico').innerHTML =
        '<div class="vacio"><span class="chip sinmeta">sin histórico</span>' +
        '<p><b>' +
        Fmt.esc(d.ambito.nombre) +
        '</b> no tiene fila propia en el scorecard corporativo: no hay ningún año, cerrado ' +
        'ni en curso, que tabular para este ámbito.</p></div>';
      $('#notaDatosHistorico').innerHTML = '';
      return;
    }
    var anios = [];
    conHistorico.forEach(function (k) {
      k.historico.forEach(function (h) {
        if (anios.indexOf(h.anio) === -1) anios.push(h.anio);
      });
    });
    anios.sort();
    var celda = function (k, anio) {
      var h = k.historico.filter(function (x) {
        return x.anio === anio;
      })[0];
      if (!h) return '<td class="num">—</td>';
      return (
        '<td class="num">' +
        '<b>' +
        (h.real === null ? '—' : Fmt.num(h.real, k.dec)) +
        '</b>' +
        (h.meta === null ? '' : '<br><small>meta ' + Fmt.meta(h.meta, k.dec) + '</small>') +
        (h.brecha_pct === null ? '' : '<br><small>' + Fmt.pct(h.brecha_pct) + '</small>') +
        '<br>' +
        chip(h.estado) +
        (h.cerrado ? '' : '<br><small>en curso</small>') +
        '</td>'
      );
    };
    $('#subDatosHistorico').textContent = anios.join(' · ');
    $('#cajaDatosHistorico').innerHTML =
      '<div class="tablabox"><table class="matriz datos-tabla"><tr><th>Indicador</th>' +
      anios
        .map(function (a) {
          return '<th class="num">' + a + '</th>';
        })
        .join('') +
      '</tr>' +
      d.kpis
        .map(function (k) {
          return (
            '<tr><th>' +
            Fmt.esc(k.nombre) +
            ' <small>' +
            Fmt.esc(k.unidad) +
            '</small></th>' +
            anios
              .map(function (a) {
                return celda(k, a);
              })
              .join('') +
            '</tr>'
          );
        })
        .join('') +
      '</table></div>';
    $('#notaDatosHistorico').innerHTML = nota(
      'Cada celda es el <b>real acumulado (YTD)</b> del año contra su propia <b>meta</b>, con la ' +
        '<b>brecha</b> y el mismo semáforo del resto del tablero. Los años cerrados salen del ' +
        'scorecard corporativo; el año <b>en curso</b> se calcula en vivo, al mismo corte que ' +
        'toda esta vista — no es un valor congelado. Un año sin celda es un año sin publicar ' +
        'para este ámbito, no un cero.'
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
      if (ambitoResuelto !== S.ambito) await resolverAmbito();
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
        '</b></span>';

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
      ambitoResuelto = S.ambito;
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
