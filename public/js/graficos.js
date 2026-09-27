/**
 * Fabrica de graficas ECharts (R.3.1).
 *
 * Solo dibuja. Recibe series con el estado y la brecha YA resueltos por la capa de
 * datos y los convierte en opciones de ECharts. Aqui no hay ni una formula de KPI ni
 * una comparacion contra meta.
 *
 * Dos decisiones de lectura que se aplican en todas las graficas:
 *
 *   1. Los cinco KPI son TECHO. La meta no se dibuja como una linea cualquiera: se
 *      sombrea la zona de incumplimiento por encima de ella. Asi el ojo ve la region
 *      prohibida antes de leer un solo numero.
 *   2. Un mes sin captura no es un cero. La serie lleva null y la linea se corta.
 */
/* global echarts, Fmt */
var Graficos = (function () {
  'use strict';

  var C = {
    // Negro corporativo Servioptica (reunion 24-sep-2026): ehs.css ya cambio --tinta/
    // --inst de azul marino a negro, esta paleta se habia quedado con los valores
    // viejos y las graficas seguian en azul mientras el resto del tablero ya no.
    tinta: '#14161A',
    inst: '#1C1F24',
    amb: '#21A0A0',
    ambSuave: '#8FCACA',
    cumple: '#16A34A',
    riesgo: '#D98324',
    incumple: '#C0392B',
    meta: '#5B6B7F',
    tenue: '#7A8899',
    borde: '#E2E8EE',
    papel: '#FFFFFF',
  };
  var COLOR_ESTADO = {
    cumple: C.cumple,
    riesgo: C.riesgo,
    incumple: C.incumple,
    sin_meta: C.tenue,
    sin_dato: C.tenue,
  };
  var SANS = "'Segoe UI',system-ui,-apple-system,sans-serif";
  var MONO = "'Cascadia Mono','Consolas',ui-monospace,monospace";

  echarts.registerTheme('ehs', {
    color: [C.amb, C.tinta, C.inst, C.riesgo, C.cumple],
    backgroundColor: 'transparent',
    textStyle: { fontFamily: SANS, fontSize: 11, color: C.tinta },
    title: { textStyle: { color: C.tinta, fontWeight: 600 } },
    legend: { textStyle: { color: C.tenue, fontSize: 10 }, itemHeight: 8, itemWidth: 14 },
    categoryAxis: {
      axisLine: { lineStyle: { color: C.borde } },
      axisTick: { show: false },
      axisLabel: { color: C.tenue, fontSize: 10, fontFamily: MONO },
      splitLine: { show: false },
    },
    valueAxis: {
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { color: C.tenue, fontSize: 10, fontFamily: MONO },
      splitLine: { lineStyle: { color: C.borde, type: [3, 4] } },
      nameTextStyle: { color: C.tenue, fontSize: 9, fontFamily: MONO, padding: [0, 0, 4, 0] },
    },
  });

  var instancias = {};
  // el reporte descargable activa esto antes de dibujar nada: en un PDF/papel el
  // icono de "guardar imagen" no tiene con que interactuarse.
  var modoImpresion = false;

  function pintar(id, opcion) {
    var el = document.getElementById(id);
    if (!el) return null;
    // un render que reemplaza el nodo deja huerfana la instancia cacheada: se detecta
    // comparando contra el DOM vivo y se vuelve a crear sobre el nodo nuevo
    if (instancias[id] && instancias[id].getDom() !== el) {
      instancias[id].dispose();
      delete instancias[id];
    }
    if (!instancias[id]) instancias[id] = echarts.init(el, 'ehs', { renderer: 'canvas' });
    instancias[id].setOption(opcion, true);
    return instancias[id];
  }

  function redibujar() {
    Object.keys(instancias).forEach(function (k) {
      var el = document.getElementById(k);
      if (!el || !el.offsetParent) return; // en una vista oculta el resize mide cero
      instancias[k].resize();
    });
  }

  /** Caja comun: rejilla, tooltip y el boton de guardar imagen para llevar a una lamina. */
  function base(extra, sinToolbox) {
    var o = {
      grid: { left: 8, right: 14, top: 34, bottom: 6, containLabel: true },
      tooltip: {
        trigger: 'axis',
        confine: true,
        backgroundColor: 'rgba(11,34,57,.95)',
        borderWidth: 0,
        padding: [8, 11],
        textStyle: { color: '#EAF2F7', fontSize: 11.5, fontFamily: SANS },
        axisPointer: { type: 'shadow', shadowStyle: { color: 'rgba(11,34,57,.05)' } },
      },
      animationDuration: 480,
      animationEasing: 'cubicOut',
      // cada barra/punto entra con un pequeño retraso en cascada en vez de saltar
      // toda la serie de una vez: mismo dato, se lee mas cuidado.
      animationDelay: function (idx) {
        return idx * 16;
      },
      // las instancias de grafica se reusan (setOption sobre la misma instancia al
      // cambiar de sitio/mes, ver pintar()): sin esto la actualizacion salta sin
      // transicion. Mismo timing que la entrada, para que se sienta igual de cuidado.
      animationDurationUpdate: 380,
      animationEasingUpdate: 'cubicOut',
    };
    if (!sinToolbox && !modoImpresion) {
      o.toolbox = {
        right: 2,
        top: -2,
        itemSize: 12,
        iconStyle: { borderColor: C.tenue },
        emphasis: { iconStyle: { borderColor: C.tinta } },
        feature: {
          saveAsImage: { title: 'Guardar imagen', pixelRatio: 2, backgroundColor: '#fff' },
        },
      };
    }
    return Object.assign(o, extra || {});
  }

  /** El eje tiene que llegar hasta el techo aunque el dato no llegue: si no, un KPI que
   *  cumple con holgura pierde de vista su propia meta. */
  function ejeValorConTecho(unidad, meta) {
    var eje = { type: 'value', name: unidad };
    if (meta !== null && meta !== undefined) {
      eje.max = function (v) {
        // devolver null deja que ECharts elija sus propios cortes redondos; solo se
        // fuerza el maximo cuando el techo queda por encima del dato, y entonces se
        // redondea, porque un eje rotulado "4.251863" delata la formula
        if (meta <= v.max) return null;
        var alto = meta * 1.08;
        var paso = Math.pow(10, Math.floor(Math.log(alto) / Math.LN10)) / 2;
        return Math.ceil(alto / paso) * paso;
      };
    }
    return eje;
  }

  function ejeMeses(meses) {
    return { type: 'category', data: meses || Fmt.mesMini, boundaryGap: true };
  }

  /**
   * La meta, dibujada como techo: una linea y la banda de incumplimiento encima.
   * Se devuelve para fusionarlo con la serie que corresponda.
   */
  function techo(meta, rotulo) {
    if (meta === null || meta === undefined) return {};
    return {
      markLine: {
        silent: true,
        symbol: 'none',
        precision: 6,
        lineStyle: { color: C.meta, type: [5, 4], width: 1.3 },
        label: {
          formatter: rotulo,
          position: 'insideEndTop',
          color: C.meta,
          fontSize: 9.5,
          fontFamily: MONO,
          backgroundColor: 'rgba(255,255,255,.82)',
          padding: [2, 4],
        },
        data: [{ yAxis: meta }],
      },
      markArea: {
        silent: true,
        // .055 ya era baja, pero contra un eje corto (meta cerca del techo del grafico)
        // la franja ocupa buena parte del alto visible y se lee como alarma aunque el
        // dato este comodo por debajo. Mas tenue: sigue marcando donde esta el limite
        // sin competir con una serie que no lo esta tocando.
        itemStyle: { color: 'rgba(192,57,43,.03)' },
        emphasis: { disabled: true },
        data: [[{ yAxis: meta }, { yAxis: 'max' }]],
      },
    };
  }

  /** El mes elegido arriba (MES DE CORTE) se destaca en la barra. Los meses hasta ahi
   *  ya son parte del corte publicado y se ven con el color normal; los que vienen
   *  despues son datos crudos que ya llegaron pero que el corte todavia no reconoce, y
   *  se atenuan mucho mas para que no se lean como si tuvieran el mismo peso. */
  function colorMesBarra(mesActivo) {
    if (!mesActivo) return C.ambSuave;
    return function (p) {
      var mes = p.dataIndex + 1;
      if (mes === mesActivo) return C.amb;
      if (mes > mesActivo) return 'rgba(143,202,202,.18)';
      return C.ambSuave;
    };
  }

  /** El ultimo mes de `campo` que trae dato real (no null), para rotular solo ahi el
   *  cierre YTD de una linea en vez de encimar un numero en cada punto. */
  function ultimoConDato(meses, campo) {
    for (var i = meses.length - 1; i >= 0; i--) {
      if (meses[i][campo] !== null && meses[i][campo] !== undefined) return i;
    }
    return -1;
  }

  function filaTooltip(color, etiqueta, valor) {
    return (
      '<div style="display:flex;align-items:center;gap:7px;margin-top:3px">' +
      '<span style="width:7px;height:7px;border-radius:50%;background:' +
      color +
      '"></span>' +
      '<span style="opacity:.75">' +
      etiqueta +
      '</span>' +
      '<b style="margin-left:auto;font-family:' +
      MONO +
      '">' +
      valor +
      '</b></div>'
    );
  }

  /**
   * "Producción contra consumo por lente" para un recurso simple (agua o energía):
   * lentes procesados en barra, el ratio por lente en línea con eje propio, y el
   * pico anotado dentro del gráfico. Agua y energía son la misma lectura con otras
   * unidades, así que comparten esta única implementación (aguaCombo/energiaCombo
   * abajo solo dicen de qué campos y qué unidades leer).
   */
  function comboProduccion(id, filas, cfg) {
    var porMes = {};
    filas.forEach(function (f) {
      porMes[f.mes] = f;
    });
    // el consumo absoluto es la barra (antes era 'lentes procesados': un proxy, no el
    // consumo en si). Con solo el ratio por lente, el consumo real quedaba enterrado en
    // el tooltip - habia que pasar el mouse mes a mes para verlo. Los lentes procesados
    // siguen en el tooltip y en la tabla de abajo, solo dejan de ser lo que se dibuja.
    var consumo = Fmt.mesMini.map(function (_, i) {
      return porMes[i + 1] ? porMes[i + 1][cfg.campoConsumo] : null;
    });
    var ratio = Fmt.mesMini.map(function (_, i) {
      return porMes[i + 1] ? porMes[i + 1][cfg.campoRatio] : null;
    });
    // meta es opcional: sin ella la grafica se ve igual que siempre, con ella el ratio
    // suma su propio techo, igual que serieKpi. A diferencia de serieKpi (que compara
    // la meta contra el ACUMULADO del año, rotulado '(acum.)'), aqui el ratio es del
    // mes suelto: un mes de baja produccion puede disparar el ratio muy por encima de
    // la meta aunque el acumulado del año la cumpla sin problema. '(mensual, ref.)'
    // dice explicitamente que esto NO es la cifra de cumplimiento oficial.
    var rotuloMeta =
      'meta ' + Fmt.meta(cfg.meta, cfg.decRatio) + ' ' + cfg.unidadRatio + ' (mensual, ref.)';
    pintar(
      id,
      base({
        legend: { top: 0, left: 'center', icon: 'roundRect' },
        xAxis: ejeMeses(),
        yAxis: [
          { type: 'value', name: cfg.unidadConsumo },
          Object.assign(
            { splitLine: { show: false }, scale: true },
            ejeValorConTecho(cfg.unidadRatio, cfg.meta)
          ),
        ],
        tooltip: {
          trigger: 'axis',
          confine: true,
          backgroundColor: 'rgba(11,34,57,.95)',
          borderWidth: 0,
          padding: [8, 11],
          textStyle: { color: '#EAF2F7', fontSize: 11.5 },
          formatter: function (ps) {
            var f = porMes[ps[0].dataIndex + 1];
            if (!f)
              return (
                '<b>' +
                Fmt.mesLargo[ps[0].dataIndex] +
                '</b><div style="opacity:.7">sin captura</div>'
              );
            return (
              '<b>' +
              f.nombre_mes +
              '</b>' +
              filaTooltip(C.ambSuave, 'Lentes procesados', Fmt.num(f.lentes, 0)) +
              filaTooltip(
                C.tinta,
                'Consumo por lente',
                Fmt.num(f[cfg.campoRatio], cfg.decRatio) + ' ' + cfg.unidadRatio
              ) +
              filaTooltip(
                'transparent',
                'Consumo total',
                Fmt.num(f[cfg.campoConsumo], 0) + ' ' + cfg.unidadConsumo
              ) +
              // == suelto (no ===) a proposito: en residuos este campo ni siquiera
              // viaja en la fila (no es undefined por falta de mes anterior, es
              // undefined porque esa fuente no lo calcula) y === null lo dejaba pasar
              // igual, mostrando 'Contra el mes anterior: —' donde no aplica.
              (f.var_por_lente_pct == null
                ? ''
                : filaTooltip(
                    'transparent',
                    'Contra el mes anterior',
                    Fmt.pctDirecto(f.var_por_lente_pct)
                  ))
            );
          },
        },
        series: [
          {
            name: 'Consumo total (' + cfg.unidadConsumo + ')',
            type: 'bar',
            data: consumo,
            itemStyle: { color: colorMesBarra(cfg.mesActivo), borderRadius: [2, 2, 0, 0] },
            barMaxWidth: 24,
          },
          Object.assign(
            {
              name: 'Consumo por lente (' + cfg.unidadRatio + '/lente)',
              type: 'line',
              yAxisIndex: 1,
              data: ratio,
              symbol: 'circle',
              symbolSize: 6,
              itemStyle: { color: C.tinta, borderColor: '#fff', borderWidth: 1.5 },
              lineStyle: { color: C.tinta, width: 2.2 },
              z: 5,
              // el pico se anota DENTRO del grafico: es la lectura que el area busca
              markPoint: {
                symbol: 'pin',
                symbolSize: 46,
                label: {
                  fontSize: 9,
                  color: '#fff',
                  fontFamily: MONO,
                  formatter: function (p) {
                    return Fmt.num(p.value, cfg.decRatio);
                  },
                },
                data: [
                  { type: 'max', name: 'maximo', itemStyle: { color: C.riesgo } },
                  { type: 'min', name: 'minimo', itemStyle: { color: C.cumple } },
                ],
              },
            },
            // como vamos contra la meta: la misma linea+banda de techo que usa serieKpi
            techo(cfg.meta, rotuloMeta)
          ),
        ],
      })
    );
  }

  return {
    colores: C,
    redibujar: redibujar,
    /** Para el reporte descargable: sin toolbox en ninguna grafica que se dibuje de
     *  aqui en adelante (nada que "guardar imagen" en un PDF/papel). Se llama una
     *  sola vez, antes de pintar la primera grafica. */
    activarModoImpresion: function () {
      modoImpresion = true;
    },

    /**
     * El KPI en el tiempo: barras del mes, linea del acumulado y el techo sombreado.
     * Es la grafica principal y la unica que responde la pregunta de si una desviacion
     * es de un mes o viene de atras.
     */
    serieKpi: function (id, r, mesActivo) {
      var dec = r.dec === undefined ? 2 : r.dec;
      // "(acum.)" porque el techo se traza sobre "Acumulado del año", no sobre "Del
      // mes": en frequency rate un solo accidente en un mes de pocas horas dispara la
      // barra mensual muy por encima de la meta aunque el acumulado la cumpla, y sin
      // esta aclaracion en el propio grafico se leia como una alerta grave que no era.
      var rotulo = (r.es_referencia ? 'referencia ' : 'meta ') + Fmt.meta(r.meta, dec) + ' (acum.)';
      pintar(
        id,
        base({
          legend: { top: 0, left: 'center', icon: 'roundRect' },
          xAxis: ejeMeses(),
          yAxis: ejeValorConTecho(r.unidad, r.meta),
          tooltip: {
            trigger: 'axis',
            confine: true,
            backgroundColor: 'rgba(11,34,57,.95)',
            borderWidth: 0,
            padding: [8, 11],
            textStyle: { color: '#EAF2F7', fontSize: 11.5 },
            formatter: function (ps) {
              var i = ps[0].dataIndex;
              var html = '<b>' + Fmt.mesLargo[i] + ' ' + r.anio + '</b>';
              ps.forEach(function (p) {
                html += filaTooltip(
                  p.color,
                  p.seriesName,
                  p.value === null || p.value === undefined
                    ? 'sin dato'
                    : Fmt.num(p.value, dec) + ' ' + r.unidad
                );
              });
              if (r.meta !== null && ps.length) {
                var ytd = ps[ps.length - 1].value;
                if (ytd !== null && ytd !== undefined) {
                  html +=
                    '<div style="margin-top:5px;padding-top:4px;border-top:1px solid rgba(255,255,255,.16);opacity:.8">' +
                    (r.es_referencia ? 'Referencia ' : 'Meta ') +
                    Fmt.meta(r.meta, dec) +
                    // con meta 0 (Agencias en accidentes y FR) la brecha no existe:
                    // dividir por cero imprimia "— %"
                    (r.meta ? ' · brecha ' + Fmt.pct((ytd - r.meta) / r.meta) : '') +
                    '</div>';
                }
              }
              return html;
            },
          },
          series: [
            {
              name: 'Del mes',
              type: 'bar',
              data: r.meses.map(function (m) {
                return m.valor;
              }),
              itemStyle: { color: colorMesBarra(mesActivo), borderRadius: [2, 2, 0, 0] },
              barMaxWidth: 24,
              emphasis: { itemStyle: { color: C.amb } },
            },
            Object.assign(
              {
                name: 'Acumulado del año',
                type: 'line',
                data: r.meses.map(function (m) {
                  return m.valor_ytd;
                }),
                symbol: 'circle',
                symbolSize: 6,
                itemStyle: { color: C.tinta, borderColor: '#fff', borderWidth: 1.5 },
                lineStyle: { color: C.tinta, width: 2.2 },
                connectNulls: false,
                z: 5,
              },
              techo(r.meta, rotulo)
            ),
          ],
        })
      );
    },

    /**
     * Cada sitio contra SU meta. Las metas por sitio son muy distintas entre si y no se
     * pueden comparar: la barra es el valor, el rombo es la meta de ESE sitio, y el
     * rotulo de la derecha es la brecha, que si es comparable.
     */
    porSitio: function (id, r, dec) {
      var nombres = r.sitios.map(function (s) {
        return s.sitio.replace('Laboratorio ', '').replace('Consolidado ', '');
      });
      // El eje se calcula SOLO con las barras (el dato real), nunca con la meta: una
      // meta muy alta en un solo sitio (ej. 6,20 de La Estrella en frequency rate)
      // estiraba el eje y aplastaba el resto de las barras contra el cero. Antes esto
      // solo se notaba al apagar "Meta del sitio" desde la leyenda (ahi si se
      // recalculaba sin la meta); ahora la vista con la meta activa es la misma que
      // con la meta apagada, tal como se pidio - una marca fuera de este rango queda
      // en el borde, no estira todo el grafico para que quepa.
      var maxBarra = Math.max.apply(
        null,
        r.sitios.map(function (s) {
          return s.valor || 0;
        })
      );
      // "queda en el borde" hay que forzarlo: ECharts no recorta un scatter fuera del
      // rango del eje contra el borde, lo deja de dibujar - sin este tope, la marca de
      // La Estrella (6,20) sencillamente desaparecia en vez de quedar visible al borde.
      var ejeMax = maxBarra > 0 ? maxBarra * 1.18 : null;
      pintar(
        id,
        base({
          // sin esto no habia forma de saber, con solo mirar la grafica, que esa
          // marca vertical era la meta - no aparecia en ningun lado.
          // legend.data explicito: sin el, ECharts lista TODAS las series con nombre,
          // y 'Brecha' (de mas abajo) es solo un ancla para el rotulo, no algo que
          // alguien deba poder ocultar desde la leyenda.
          legend: { top: 0, left: 'center', icon: 'roundRect', data: [r.kpi, 'Meta del sitio'] },
          grid: { left: 4, right: 74, top: 34, bottom: 4, containLabel: true },
          xAxis: { type: 'value', name: r.unidad, max: ejeMax || undefined },
          yAxis: {
            type: 'category',
            data: nombres,
            axisLabel: { color: C.tinta, fontSize: 11, fontFamily: SANS, fontWeight: 600 },
          },
          tooltip: {
            trigger: 'item',
            confine: true,
            backgroundColor: 'rgba(11,34,57,.95)',
            borderWidth: 0,
            padding: [8, 11],
            textStyle: { color: '#EAF2F7', fontSize: 11.5 },
            formatter: function (p) {
              var s = r.sitios[p.dataIndex];
              return (
                '<b>' +
                s.sitio +
                '</b>' +
                filaTooltip(
                  COLOR_ESTADO[s.estado] || C.inst,
                  r.kpi,
                  Fmt.num(s.valor, dec) + ' ' + r.unidad
                ) +
                filaTooltip(
                  C.meta,
                  'Meta del sitio',
                  s.meta === null ? 'sin meta' : Fmt.meta(s.meta, dec)
                ) +
                (s.brecha_pct === null
                  ? ''
                  : filaTooltip('transparent', 'Brecha', Fmt.pct(s.brecha_pct)))
              );
            },
          },
          series: [
            {
              name: r.kpi,
              type: 'bar',
              data: r.sitios.map(function (s) {
                return {
                  value: s.valor,
                  itemStyle: {
                    color: COLOR_ESTADO[s.estado] || C.inst,
                    borderRadius: [0, 2, 2, 0],
                  },
                };
              }),
              barMaxWidth: 20,
              label: {
                show: true,
                position: 'right',
                distance: 8,
                fontSize: 10.5,
                fontFamily: MONO,
                color: C.tinta,
                // solo el valor: la brecha se movio a su propia columna fija a la
                // derecha (serie 'Brecha' mas abajo), en vez de ir pegada al numero -
                // antes quedaba a una x distinta segun el largo de cada barra, un
                // desorden que se pidio arreglar.
                formatter: function (p) {
                  var s = r.sitios[p.dataIndex];
                  return s.valor === null ? '' : Fmt.num(s.valor, dec);
                },
              },
            },
            {
              // columna de brecha, siempre a la misma x (el borde derecho del eje,
              // igual que el icono de descargar imagen), sin importar cuanto mida
              // cada barra. 'max' como STRING solo es un valor especial para
              // markPoint/markLine, no para el data de una serie normal - ahi
              // ECharts lo toma como categoria literal y no dibuja nada (verificado:
              // el punto nunca se resolvia, ningun rotulo aparecia). Se usa el mismo
              // numero ya calculado para el eje (ejeMax). symbol:'none' porque este
              // punto es solo un ancla para el rotulo, no un dato mas que mostrar.
              name: 'Brecha',
              type: 'scatter',
              symbol: 'none',
              silent: true,
              data: r.sitios.map(function (s, i) {
                if (s.brecha_pct === null) return null;
                return { value: [ejeMax !== null ? ejeMax : maxBarra, i] };
              }),
              label: {
                show: true,
                position: 'right',
                distance: 4,
                fontSize: 10.5,
                fontFamily: MONO,
                color: C.tinta,
                formatter: function (p) {
                  return Fmt.pct(r.sitios[p.dataIndex].brecha_pct, 0);
                },
              },
            },
            {
              // antes un rombo blanco: se leia como un punto de dato mas, no como una
              // marca de referencia. C.meta (gris) quedaba desapercibido contra las
              // barras de colores: C.tinta (negro corporativo) sostiene el contraste
              // contra cualquier color de barra, y ahora tiene su propia entrada en
              // la leyenda de arriba, asi que no depende de que alguien adivine que
              // esa marca es la meta.
              name: 'Meta del sitio',
              type: 'scatter',
              symbol: 'rect',
              symbolSize: [4, 26],
              itemStyle: { color: C.tinta },
              z: 6,
              data: r.sitios.map(function (s, i) {
                if (s.meta === null) return null;
                // recorta SOLO el punto dibujado: el tooltip de arriba sigue leyendo
                // s.meta sin recortar, asi que la cifra real no se pierde al pasar el
                // mouse aunque la marca quede pegada al borde derecho.
                var x = ejeMax !== null ? Math.min(s.meta, ejeMax) : s.meta;
                return { value: [x, i] };
              }),
            },
          ],
        })
      );
    },

    /**
     * La matriz de control como mapa de calor: KPI en filas, mes en columnas y el color
     * puesto por la BRECHA contra la meta, no por el valor. Es lo que permite comparar
     * de un vistazo cinco indicadores con unidades distintas: el 0 es la meta.
     */
    matrizCalor: function (id, kpis, meses) {
      var celdas = [];
      var etiquetas = [];
      kpis.forEach(function (k, fila) {
        k.serie_ytd.forEach(function (p, col) {
          celdas.push([col, fila, p.brecha_pct === null ? '-' : p.brecha_pct * 100]);
          etiquetas.push(Fmt.num(p.valor, k.dec));
        });
      });
      // un solo -100 % (un KPI en cero contra su techo) aplastaba a blanco todo el
      // resto de la matriz. La escala se fija en el percentil 75 y se acota a [10, 40]:
      // los extremos saturan, que es exactamente lo que deben hacer
      var absolutos = celdas
        .map(function (c) {
          return typeof c[2] === 'number' ? Math.abs(c[2]) : null;
        })
        .filter(function (x) {
          return x !== null;
        })
        .sort(function (a, b) {
          return a - b;
        });
      var p75 = absolutos.length ? absolutos[Math.floor(absolutos.length * 0.75)] : 15;
      var maximo = Math.min(40, Math.max(10, Math.ceil(p75)));
      pintar(
        id,
        base(
          {
            grid: { left: 4, right: 8, top: 8, bottom: 30, containLabel: true },
            xAxis: {
              type: 'category',
              data: meses.map(function (m) {
                return Fmt.mesCorto[m - 1];
              }),
              splitArea: { show: true, areaStyle: { color: ['transparent'] } },
            },
            yAxis: {
              type: 'category',
              inverse: true,
              data: kpis.map(function (k) {
                return k.kpi;
              }),
              axisLabel: { color: C.tinta, fontSize: 10.5, fontFamily: SANS, fontWeight: 600 },
            },
            visualMap: {
              min: -maximo,
              max: maximo,
              calculable: false,
              orient: 'horizontal',
              left: 'center',
              bottom: 0,
              itemWidth: 9,
              itemHeight: 76,
              precision: 0,
              text: ['por encima del techo', 'con margen'],
              textStyle: { color: C.tenue, fontSize: 9, fontFamily: MONO },
              // el verde del extremo "excelente" estaba casi blanco (#DCEEE4, apenas se
              // distinguia de la celda vecina) y el rojo del otro extremo si se notaba
              // fuerte — se sube la saturacion del verde para que la escala se lea pareja
              // en los dos sentidos, sin tocar el rojo ni el centro. Ajuste posterior: un
              // verde solido (#7FD1A3) se leia plano — se pasa a un verde de aprobacion
              // (el mismo tono de --cumple) con transparencia, para que se note que es un
              // estado bueno sin tapar el numero que trae encima.
              inRange: { color: ['rgba(22,163,74,.42)', '#F2F6F8', '#F6DCD8', '#C0392B'] },
              formatter: function (v) {
                return Fmt.num(v, 0) + ' %';
              },
            },
            tooltip: {
              confine: true,
              backgroundColor: 'rgba(11,34,57,.95)',
              borderWidth: 0,
              padding: [8, 11],
              textStyle: { color: '#EAF2F7', fontSize: 11.5 },
              formatter: function (p) {
                var k = kpis[p.data[1]];
                var punto = k.serie_ytd[p.data[0]];
                return (
                  '<b>' +
                  k.kpi +
                  ' · ' +
                  Fmt.mesLargo[meses[p.data[0]] - 1] +
                  '</b>' +
                  filaTooltip(
                    C.amb,
                    'Acumulado al cierre del mes',
                    Fmt.num(punto.valor, k.dec) + ' ' + k.unidad
                  ) +
                  filaTooltip(
                    C.meta,
                    k.es_referencia ? 'Referencia' : 'Meta',
                    k.meta === null ? 'sin meta' : Fmt.meta(k.meta, k.dec)
                  ) +
                  filaTooltip(
                    'transparent',
                    'Brecha',
                    punto.brecha_pct === null ? 'sin meta' : Fmt.pct(punto.brecha_pct)
                  )
                );
              },
            },
            series: [
              {
                type: 'heatmap',
                data: celdas,
                label: {
                  show: true,
                  fontSize: 10,
                  fontFamily: MONO,
                  color: C.tinta,
                  formatter: function (p) {
                    return etiquetas[p.dataIndex];
                  },
                },
                itemStyle: { borderColor: '#fff', borderWidth: 2 },
                emphasis: { itemStyle: { borderColor: C.tinta, borderWidth: 2 } },
              },
            ],
          },
          true
        )
      );
    },

    /** El agua: consumo total en barras y consumo por lente en linea, con los picos marcados. */
    aguaCombo: function (id, filas, meta, mesActivo) {
      comboProduccion(id, filas, {
        campoConsumo: 'consumo_m3',
        campoRatio: 'l_por_lente',
        unidadConsumo: 'm³',
        unidadRatio: 'l',
        decRatio: 2,
        meta: meta,
        mesActivo: mesActivo,
      });
    },

    /** Lo mismo que aguaCombo, para energía. */
    energiaCombo: function (id, filas, meta, mesActivo) {
      comboProduccion(id, filas, {
        campoConsumo: 'consumo_kwh',
        campoRatio: 'kwh_por_lente',
        unidadConsumo: 'kWh',
        unidadRatio: 'kWh',
        decRatio: 2,
        meta: meta,
        mesActivo: mesActivo,
      });
    },

    /**
     * Lo mismo que aguaCombo/energiaCombo, para residuos: consumo total en kg (suma de
     * las tres partes, o del total sin desglose en Peru) contra el g/lente. Reusa los
     * mismos campos que ya trae residuos-composicion (suma_kg/suma_g_lente) - no hace
     * falta un endpoint nuevo.
     */
    residuosCombo: function (id, meses, meta, mesActivo) {
      comboProduccion(id, meses, {
        campoConsumo: 'suma_kg',
        campoRatio: 'suma_g_lente',
        unidadConsumo: 'kg',
        unidadRatio: 'g',
        decRatio: 1,
        meta: meta,
        mesActivo: mesActivo,
      });
    },

    /**
     * De que esta hecho el residuo, mes a mes, en g/lente. Apilado: la altura total ES
     * el KPI del mes, asi que la grafica explica el indicador en vez de acompanarlo.
     */
    composicionResiduos: function (id, r, meta) {
      // 'total' es la unica parte que trae Peru (residuo sin desglose): necesita su
      // propio nombre/color para no quedar sin mapear (antes se filtraba junto con el
      // 'total' fantasma que SI hay que descartar en Colombia/Estrella/Celta/Agencias
      // - ver adaptador_sql.js -, dejando a Peru con una gráfica vacia).
      var nombre = {
        peligroso: 'Peligroso',
        aprovechable: 'Aprovechable',
        ordinario: 'Ordinario',
        total: 'Total',
      };
      // 'total' en su propio tono (no C.amb): en Colombia + Peru las cuatro partes
      // aparecen juntas en la misma grafica, y compartiendo color con "Aprovechable"
      // se recreaba el mismo bug de "dos barras identicas" que origino este arreglo.
      var color = {
        peligroso: C.incumple,
        aprovechable: C.amb,
        ordinario: C.inst,
        total: C.tenue,
      };
      // Sin filtro de nombre[p]: adaptador_sql.js ya garantiza que r.partes solo trae
      // magnitudes con dato real para el ambito (ver el 'exists' de residuosComposicion),
      // y el mapa de arriba ya cubre las 4 posibles - filtrar aqui era una defensa que
      // nunca se activaba, sobre un fix que ya resolvio el problema en la raiz.
      var partes = r.partes;
      var meses = r.meses.map(function (m) {
        return m.mes;
      });
      pintar(
        id,
        base({
          legend: { top: 0, left: 'center', icon: 'roundRect' },
          xAxis: ejeMeses(
            meses.map(function (m) {
              return Fmt.mesMini[m - 1];
            })
          ),
          yAxis: ejeValorConTecho('g/lente', meta),
          tooltip: {
            trigger: 'axis',
            confine: true,
            backgroundColor: 'rgba(11,34,57,.95)',
            borderWidth: 0,
            padding: [8, 11],
            textStyle: { color: '#EAF2F7', fontSize: 11.5 },
            formatter: function (ps) {
              var m = r.meses[ps[0].dataIndex];
              var html = '<b>' + m.nombre_mes + '</b>';
              partes.forEach(function (p) {
                html += filaTooltip(
                  color[p],
                  nombre[p],
                  Fmt.num(m[p + '_g_lente'], 1) +
                    ' g/lente · ' +
                    Fmt.num(m[p + '_part'] * 100, 0) +
                    ' %'
                );
              });
              html +=
                '<div style="margin-top:5px;padding-top:4px;border-top:1px solid rgba(255,255,255,.16)">' +
                '<b>Total ' +
                Fmt.num(m.suma_g_lente, 1) +
                ' g/lente</b>' +
                (meta ? ' · techo ' + Fmt.meta(meta, 1) : '') +
                '</div>';
              return html;
            },
          },
          series: partes.map(function (p, i) {
            var s = {
              name: nombre[p],
              type: 'bar',
              stack: 'residuo',
              data: r.meses.map(function (m) {
                return m[p + '_g_lente'];
              }),
              itemStyle: { color: color[p] },
              barMaxWidth: 30,
              emphasis: { focus: 'series' },
            };
            if (i === partes.length - 1) {
              s.itemStyle = { color: color[p], borderRadius: [2, 2, 0, 0] };
              Object.assign(s, techo(meta, 'techo ' + Fmt.meta(meta, 1)));
            }
            return s;
          }),
        })
      );
    },

    /**
     * La trayectoria del KPI en el scorecard corporativo. El anio en curso NO se dibuja
     * como si estuviera cerrado: va en una barra rayada y rotulada como acumulado.
     */
    trayectoria: function (id, r) {
      var dec = r.dec;
      var anios = r.anios.map(function (a) {
        return String(a.anio);
      });
      var idxEnCurso = -1;
      var datoEnCurso = null;
      var reales = r.anios.map(function (a, i) {
        if (a.real !== null) return { value: a.real };
        if (r.en_curso && a.anio === r.en_curso.anio) {
          idxEnCurso = i;
          datoEnCurso = {
            value: r.en_curso.ytd,
            itemStyle: {
              color: COLOR_ESTADO[r.en_curso.estado] || C.amb,
              borderRadius: [2, 2, 0, 0],
              decal: {
                symbol: 'rect',
                dashArrayX: [1, 0],
                dashArrayY: [2, 4],
                rotation: -Math.PI / 4,
                color: 'rgba(255,255,255,.45)',
              },
            },
          };
          return datoEnCurso;
        }
        return null;
      });
      var series = [
        {
          // "Real del año" no decia de que: quien mira la leyenda sola, sin el
          // encabezado del panel al lado, no sabe real de que. "Cierre del año"
          // es lo mismo que ya dice el tooltip de esta misma grafica.
          name: 'Cierre del año',
          type: 'bar',
          data: reales,
          // color a nivel de serie: es lo que ECharts usa para el swatch de la
          // leyenda. Sin esto, la leyenda tomaba el color del tema (teal) mientras
          // las barras se pintaban por punto (negro/naranja) - colores que no
          // coincidian con lo que decia la leyenda.
          itemStyle: { color: C.inst, borderRadius: [2, 2, 0, 0] },
          // mismo stack que la serie fantasma 'Año en curso' (mas abajo): sin esto,
          // dos series type:'bar' en el mismo eje se agrupan lado a lado y ECharts
          // les reparte el ancho ENTRE LAS DOS aunque la fantasma no tenga ni un dato
          // que dibujar - empujaba esta barra ~31px a la izquierda del centro real de
          // cada categoria (verificado con lectura de pixeles). Con el mismo stack,
          // ECharts las trata como una sola barra que ocupa el carril completo;
          // 'Año en curso' nunca aporta altura porque su data siempre esta vacia.
          stack: 'anioTrayectoria',
          barMaxWidth: 46,
          label: {
            show: true,
            position: 'top',
            fontSize: 10.5,
            fontFamily: MONO,
            color: C.tinta,
            formatter: function (p) {
              return Fmt.num(p.value, dec);
            },
          },
        },
        {
          name: 'Meta del año',
          type: 'line',
          data: r.anios.map(function (a) {
            return a.meta;
          }),
          symbol: 'rect',
          symbolSize: 9,
          itemStyle: { color: C.meta },
          lineStyle: { color: C.meta, width: 1.6, type: [5, 4] },
          connectNulls: false,
          z: 5,
        },
      ];
      if (r.en_curso) {
        // serie fantasma (sin datos: no dibuja nada) solo para que la barra rayada
        // tenga su propia entrada en la leyenda, con el mismo color que la
        // caracteriza, en vez de depender de un rotulo metido dentro del grafico o
        // de que alguien lea la nota de texto de abajo. Mismo 'stack' que 'Cierre
        // del año' (ver su comentario): sin el, esta barra vacia igual reclamaba su
        // propio carril y desplazaba la barra real.
        series.push({
          name: 'Año en curso',
          type: 'bar',
          data: [],
          stack: 'anioTrayectoria',
          itemStyle: { color: COLOR_ESTADO[r.en_curso.estado] || C.amb },
        });
      }
      var inst = pintar(
        id,
        base({
          legend: { top: 0, left: 'center', icon: 'roundRect' },
          xAxis: { type: 'category', data: anios },
          yAxis: { type: 'value', name: r.unidad },
          tooltip: {
            trigger: 'axis',
            confine: true,
            backgroundColor: 'rgba(11,34,57,.95)',
            borderWidth: 0,
            padding: [8, 11],
            // el texto de "en curso" se salia de la caja: extraCssText fuerza el
            // ancho maximo y el salto de linea en el contenedor real del tooltip,
            // no solo en el div de adentro (que por si solo no bastaba)
            extraCssText: 'max-width:220px;white-space:normal;line-height:1.4',
            textStyle: { color: '#EAF2F7', fontSize: 11.5 },
            formatter: function (ps) {
              var a = r.anios[ps[0].dataIndex];
              var enCurso = r.en_curso && a.anio === r.en_curso.anio && a.real === null;
              return (
                '<b>' +
                a.anio +
                (enCurso ? ' · en curso' : '') +
                '</b>' +
                filaTooltip(
                  enCurso ? C.amb : C.inst,
                  enCurso ? 'Acumulado a ' + r.en_curso.hasta : 'Cierre del año',
                  Fmt.num(enCurso ? r.en_curso.ytd : a.real, dec) + ' ' + r.unidad
                ) +
                filaTooltip(
                  C.meta,
                  'Meta',
                  a.meta === null ? 'no publicada' : Fmt.meta(a.meta, dec)
                ) +
                (enCurso
                  ? '<div style="margin-top:5px;opacity:.75">Van ' +
                    r.en_curso.hasta_mes +
                    ' meses, no es un cierre.</div>'
                  : '')
              );
            },
          },
          series: series,
        })
      );
      // "Año en curso" es una serie fantasma (sin datos propios) solo para tener su
      // propio icono en la leyenda - la barra rayada en si vive dentro de "Cierre
      // del año" (es su ultimo punto). Apagar el icono fantasma no ocultaba esa
      // barra real: quedaba la sensacion de "esto no funciona, la barra sigue ahi".
      // Ahora el clic reescribe el punto de "Cierre del año" que le corresponde
      // (a null para ocultarlo, al dato original para devolverlo) via setOption con
      // merge por nombre de serie, asi el icono SI controla la barra que promete.
      // .off() antes de .on() evita apilar handlers: pintar() reusa la instancia.
      if (inst && r.en_curso && idxEnCurso !== -1) {
        inst.off('legendselectchanged');
        inst.on('legendselectchanged', function (e) {
          if (e.name !== 'Año en curso') return;
          var nuevaReales = reales.slice();
          nuevaReales[idxEnCurso] = e.selected['Año en curso'] ? datoEnCurso : null;
          inst.setOption({ series: [{ name: 'Cierre del año', data: nuevaReales }] });
        });
      }
    },

    /** Mini tendencia para la ficha de un KPI, con el techo marcado. */
    sparkline: function (id, serie, estado, meta) {
      var color = COLOR_ESTADO[estado] || C.cumple;
      var valores = serie.map(function (p) {
        return p.valor;
      });
      var ultimo = valores.length - 1;
      pintar(id, {
        grid: { left: 1, right: 1, top: 5, bottom: 2 },
        xAxis: {
          type: 'category',
          show: false,
          data: valores.map(function (_, i) {
            return i;
          }),
        },
        yAxis: { type: 'value', show: false, scale: true },
        tooltip: { show: false },
        animation: false,
        series: [
          Object.assign(
            {
              type: 'line',
              data: valores,
              symbol: 'circle',
              symbolSize: function (_, p) {
                return p.dataIndex === ultimo ? 5 : 0;
              },
              itemStyle: { color: color, borderColor: '#fff', borderWidth: 1.2 },
              lineStyle: { color: color, width: 1.8 },
              areaStyle: { color: color, opacity: 0.13 },
              smooth: 0.25,
            },
            meta === null || meta === undefined
              ? {}
              : {
                  markLine: {
                    silent: true,
                    symbol: 'none',
                    label: { show: false },
                    lineStyle: { color: C.meta, type: [2, 3], width: 1 },
                    data: [{ yAxis: meta }],
                  },
                }
          ),
        ],
      });
    },

    /**
     * Contraste mensual: dos años elegidos, mes a mes, del mismo ámbito y KPI — "cómo
     * vamos este año contra el anterior", con la misma vara. Barras lado a lado para el
     * mes puntual y una línea de YTD por año para el acumulado, que es como se evalúa
     * de verdad a nivel gerencial: no el mes suelto, el año hasta donde vamos.
     */
    contraste: function (id, r, anioA, anioB) {
      var dec = r.dec;
      pintar(
        id,
        base({
          legend: { top: 0, left: 'center', icon: 'roundRect' },
          xAxis: ejeMeses(
            r.meses.map(function (m) {
              return (m.nombre_mes || '').slice(0, 3) || Fmt.mesCorto[m.mes - 1];
            })
          ),
          yAxis: { type: 'value', name: r.unidad },
          tooltip: {
            trigger: 'axis',
            confine: true,
            backgroundColor: 'rgba(11,34,57,.95)',
            borderWidth: 0,
            padding: [8, 11],
            textStyle: { color: '#EAF2F7', fontSize: 11.5 },
            formatter: function (ps) {
              var m = r.meses[ps[0].dataIndex];
              var html = '<b>' + (m.nombre_mes || Fmt.mesLargo[m.mes - 1]) + '</b>';
              html += filaTooltip(
                C.ambSuave,
                String(anioA),
                m.valorA === null ? 'sin dato' : Fmt.num(m.valorA, dec) + ' ' + r.unidad
              );
              html += filaTooltip(
                C.amb,
                String(anioB),
                m.valorB === null ? 'sin dato' : Fmt.num(m.valorB, dec) + ' ' + r.unidad
              );
              if (m.valorA !== null && m.valorB !== null && m.valorA !== 0) {
                html += filaTooltip(
                  'transparent',
                  'Δ del mes',
                  Fmt.pctDirecto(((m.valorB - m.valorA) / m.valorA) * 100)
                );
              }
              html += filaTooltip(
                C.tenue,
                'YTD ' + anioA,
                m.ytdA === null ? 'sin dato' : Fmt.num(m.ytdA, dec)
              );
              html += filaTooltip(
                C.tinta,
                'YTD ' + anioB,
                m.ytdB === null ? 'sin dato' : Fmt.num(m.ytdB, dec)
              );
              if (m.ytdA !== null && m.ytdB !== null && m.ytdA !== 0) {
                html += filaTooltip(
                  'transparent',
                  'Δ YTD, como vamos',
                  Fmt.pctDirecto(((m.ytdB - m.ytdA) / m.ytdA) * 100)
                );
              }
              return html;
            },
          },
          series: [
            {
              name: String(anioA),
              type: 'bar',
              data: r.meses.map(function (m) {
                return m.valorA;
              }),
              itemStyle: { color: C.ambSuave, borderRadius: [2, 2, 0, 0] },
              barMaxWidth: 16,
            },
            {
              name: String(anioB),
              type: 'bar',
              data: r.meses.map(function (m) {
                return m.valorB;
              }),
              itemStyle: { color: C.amb, borderRadius: [2, 2, 0, 0] },
              barMaxWidth: 16,
            },
            {
              // gris tenue + linea punteada: el anio de referencia. Antes usaba
              // C.tinta, casi identico a C.inst de la otra linea - no se distinguian.
              name: 'YTD ' + anioA,
              type: 'line',
              data: r.meses.map(function (m) {
                return m.ytdA;
              }),
              symbol: 'circle',
              symbolSize: 5,
              itemStyle: { color: C.tenue },
              lineStyle: { color: C.tenue, width: 1.6, type: [5, 4] },
              connectNulls: false,
              z: 5,
              // el ultimo YTD real de cada linea queda rotulado en el propio grafico:
              // es la comparacion que importa (como vamos), sin depender de pasar el
              // mouse por encima.
              label: {
                show: true,
                formatter: function (p) {
                  return p.dataIndex === ultimoConDato(r.meses, 'ytdA')
                    ? Fmt.num(p.value, dec)
                    : '';
                },
                position: 'top',
                fontSize: 10,
                fontFamily: MONO,
                color: C.tenue,
              },
            },
            {
              // negro corporativo solido: el mismo color que usa el resto del
              // tablero para "la linea que importa" (Acumulado del año en
              // serieKpi/comboProduccion). Antes usaba C.inst, casi identico al
              // C.tinta que traia la otra linea (ver comentario arriba) - se probo
              // ambar de camino a esta version, pero quedaba muy llamativo para un
              // reporte serio y nunca llego a comitearse.
              name: 'YTD ' + anioB,
              type: 'line',
              data: r.meses.map(function (m) {
                return m.ytdB;
              }),
              symbol: 'circle',
              symbolSize: 6,
              itemStyle: { color: C.tinta, borderColor: '#fff', borderWidth: 1.5 },
              lineStyle: { color: C.tinta, width: 2.4 },
              connectNulls: false,
              z: 6,
              label: {
                show: true,
                formatter: function (p) {
                  return p.dataIndex === ultimoConDato(r.meses, 'ytdB')
                    ? Fmt.num(p.value, dec)
                    : '';
                },
                position: 'bottom',
                fontSize: 10,
                fontFamily: MONO,
                fontWeight: 700,
                color: C.tinta,
              },
            },
          ],
        })
      );
    },
  };
})();
