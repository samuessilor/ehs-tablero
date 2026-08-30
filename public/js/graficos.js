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
    tinta: '#0B2239',
    inst: '#0B3C5D',
    amb: '#21A0A0',
    ambSuave: '#8FCACA',
    cumple: '#2E7D5B',
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
      animationDuration: 420,
      animationEasing: 'cubicOut',
    };
    if (!sinToolbox) {
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
        itemStyle: { color: 'rgba(192,57,43,.055)' },
        emphasis: { disabled: true },
        data: [[{ yAxis: meta }, { yAxis: 'max' }]],
      },
    };
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

  return {
    colores: C,
    redibujar: redibujar,

    /**
     * El KPI en el tiempo: barras del mes, linea del acumulado y el techo sombreado.
     * Es la grafica principal y la unica que responde la pregunta de si una desviacion
     * es de un mes o viene de atras.
     */
    serieKpi: function (id, r) {
      var dec = r.dec === undefined ? 2 : r.dec;
      var rotulo = (r.es_referencia ? 'referencia ' : 'meta ') + Fmt.num(r.meta, dec);
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
                    Fmt.num(r.meta, dec) +
                    ' · brecha ' +
                    Fmt.pct((ytd - r.meta) / r.meta) +
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
              itemStyle: { color: C.ambSuave, borderRadius: [2, 2, 0, 0] },
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
      pintar(
        id,
        base({
          grid: { left: 4, right: 74, top: 16, bottom: 4, containLabel: true },
          xAxis: { type: 'value', name: r.unidad },
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
                  s.meta === null ? 'sin meta' : Fmt.num(s.meta, dec)
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
                formatter: function (p) {
                  var s = r.sitios[p.dataIndex];
                  return s.valor === null
                    ? ''
                    : Fmt.num(s.valor, dec) +
                        (s.brecha_pct === null ? '' : '  ' + Fmt.pct(s.brecha_pct, 0));
                },
              },
            },
            {
              name: 'Meta del sitio',
              type: 'scatter',
              symbol: 'diamond',
              symbolSize: 12,
              itemStyle: { color: '#fff', borderColor: C.tinta, borderWidth: 1.8 },
              z: 6,
              data: r.sitios.map(function (s, i) {
                return s.meta === null ? null : { value: [s.meta, i] };
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
              inRange: { color: ['#DCEEE4', '#F2F6F8', '#F6DCD8', '#C0392B'] },
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
                    k.meta === null ? 'sin meta' : Fmt.num(k.meta, k.dec)
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

    /** El agua: produccion en barras y consumo por lente en linea, con los picos marcados. */
    aguaCombo: function (id, filas) {
      var porMes = {};
      filas.forEach(function (f) {
        porMes[f.mes] = f;
      });
      var lentes = Fmt.mesMini.map(function (_, i) {
        return porMes[i + 1] ? porMes[i + 1].lentes : null;
      });
      var ratio = Fmt.mesMini.map(function (_, i) {
        return porMes[i + 1] ? porMes[i + 1].l_por_lente : null;
      });
      pintar(
        id,
        base({
          legend: { top: 0, left: 'center', icon: 'roundRect' },
          xAxis: ejeMeses(),
          yAxis: [
            { type: 'value', name: 'lentes' },
            { type: 'value', splitLine: { show: false }, scale: true },
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
                filaTooltip(C.tinta, 'Consumo por lente', Fmt.num(f.l_por_lente, 2) + ' l') +
                filaTooltip('transparent', 'Consumo total', Fmt.num(f.consumo_m3, 0) + ' m³') +
                (f.var_por_lente_pct === null
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
              name: 'Lentes procesados',
              type: 'bar',
              data: lentes,
              itemStyle: { color: C.ambSuave, borderRadius: [2, 2, 0, 0] },
              barMaxWidth: 24,
            },
            {
              name: 'Consumo por lente (l/lente)',
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
                    return Fmt.num(p.value, 2);
                  },
                },
                data: [
                  { type: 'max', name: 'maximo', itemStyle: { color: C.riesgo } },
                  { type: 'min', name: 'minimo', itemStyle: { color: C.cumple } },
                ],
              },
            },
          ],
        })
      );
    },

    /**
     * De que esta hecho el residuo, mes a mes, en g/lente. Apilado: la altura total ES
     * el KPI del mes, asi que la grafica explica el indicador en vez de acompanarlo.
     */
    composicionResiduos: function (id, r, meta) {
      var nombre = { peligroso: 'Peligroso', aprovechable: 'Aprovechable', ordinario: 'Ordinario' };
      var color = { peligroso: C.incumple, aprovechable: C.amb, ordinario: C.inst };
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
              r.partes.forEach(function (p) {
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
                Fmt.num(m.total_g_lente, 1) +
                ' g/lente</b>' +
                (meta ? ' · techo ' + Fmt.num(meta, 1) : '') +
                '</div>';
              return html;
            },
          },
          series: r.partes.map(function (p, i) {
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
            if (i === r.partes.length - 1) {
              s.itemStyle = { color: color[p], borderRadius: [2, 2, 0, 0] };
              Object.assign(s, techo(meta, 'techo ' + Fmt.num(meta, 0)));
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
      var reales = r.anios.map(function (a) {
        if (a.real !== null)
          return { value: a.real, itemStyle: { color: C.inst, borderRadius: [2, 2, 0, 0] } };
        if (r.en_curso && a.anio === r.en_curso.anio) {
          return {
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
        }
        return null;
      });
      pintar(
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
                  a.meta === null ? 'no publicada' : Fmt.num(a.meta, dec)
                ) +
                (enCurso
                  ? '<div style="margin-top:5px;opacity:.75;max-width:230px">No es un cierre: son ' +
                    r.en_curso.hasta_mes +
                    ' meses. No se compara de igual a igual.</div>'
                  : '')
              );
            },
          },
          series: [
            {
              name: 'Real del año',
              type: 'bar',
              data: reales,
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
          ],
        })
      );
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
  };
})();
