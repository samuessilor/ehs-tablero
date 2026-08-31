/**
 * Adaptador JSON — el origen de datos del interinato.
 *
 * Lee la vista materializada que produce el pipeline (datos/datos.json y
 * datos/agua-detalle.json) y devuelve REBANADAS. No calcula ningun indicador:
 * el calculo tiene una sola implementacion (R.5.2.2) y vive en la capa de datos,
 * cuyo algebra reproduce el motor validado en 17 puntos y es la misma de
 * app/sql/02-vistas.sql. Cuando exista el esquema ehs en SQL Server, este modulo se
 * sustituye por adaptador_sql.js con estas MISMAS firmas.
 */
const fs = require('fs');
const path = require('path');

const CARPETA = path.join(__dirname, '..', '..', 'datos');

let cache = null;
function leer(nombre) {
  const ruta = path.join(CARPETA, nombre);
  if (!fs.existsSync(ruta)) {
    // el dato no se versiona (es informacion operativa de la empresa), asi que un clon
    // limpio no lo trae. Sin este aviso, la app moriria con un ENOENT de Node y quien
    // clone no sabria que lo unico que falta es correr el pipeline
    const e = new Error(
      `Falta ${nombre} en app/datos. El dato no viaja en el repositorio: publicalo con ` +
        `"python scripts/publicar_a_app.py" (ver docs/proceso-actualizacion.md).`
    );
    e.codigo = 'sin_datos_publicados';
    throw e;
  }
  return JSON.parse(fs.readFileSync(ruta, 'utf-8'));
}

function base() {
  if (!cache) {
    cache = { d: leer('datos.json'), agua: leer('agua-detalle.json') };
  }
  return cache;
}

/** anio y mes ausentes significan "el corte publicado". Fijarlos en el codigo obliga a
 *  editar dos archivos cada vez que avanza el mes; el dato ya sabe cual es. */
function alCorte(d, anio, mes) {
  return { anio: anio == null ? d.anio : anio, mes: mes == null ? d.corte : mes };
}

/** Que sitios componen cada ambito. Los agregados suman crudo y dividen al final. */
const SITIOS_DE = {
  celta: ['celta'],
  estrella: ['estrella'],
  agencias: ['agencias'],
  nacional_labs: ['celta', 'estrella'],
  nacional: ['celta', 'estrella', 'agencias'],
};

function cabecera(d) {
  return {
    anio: d.anio,
    corte: { mes: d.corte, nombre: d.corteNombre, mesesConDato: d.calidad.mesesConDato },
    actualizado_en: d.actualizadoEn,
    fuente: d.fuente,
    meta_vigente: d.metaVigente,
  };
}

function puntoSerie(d, ambito, mes) {
  const serie = d.serie[ambito] || [];
  return serie.find((p) => p.mes === mes) || null;
}

function contraMetaDe(d, ambito, mes) {
  const filas = d.contraMeta[ambito] || [];
  const f = filas.find((x) => x.mes === mes);
  return f ? f.kpis : null;
}

module.exports = {
  /** Los cinco KPI del ambito al corte, con meta, brecha y estado ya resueltos. */
  async panorama({ anio, mes, ambito }) {
    const { d } = base();
    ({ anio, mes } = alCorte(d, anio, mes));
    if (anio !== d.anio) return null;
    const cm = contraMetaDe(d, ambito, mes);
    const p = puntoSerie(d, ambito, mes);
    if (!cm || !p) return null;
    return {
      ...cabecera(d),
      ambito: { id: ambito, nombre: d.ambitos[ambito] },
      kpi: Object.keys(d.kpis).map((k) => ({
        kpi_id: k,
        kpi: d.kpis[k].nombre,
        unidad: d.kpis[k].unidad,
        familia: d.kpis[k].familia,
        dec: d.kpis[k].dec,
        valor: cm[k].valor,
        valor_mes: p.mensual[k],
        meta: cm[k].meta,
        es_referencia: cm[k].esReferencia,
        brecha_pct: cm[k].brecha_pct,
        estado: cm[k].estado,
        serie_ytd: (d.contraMeta[ambito] || []).map((x) => ({
          mes: x.mes,
          valor: x.kpis[k].valor,
          estado: x.kpis[k].estado,
          brecha_pct: x.kpis[k].brecha_pct,
        })),
      })),
      correcciones: (d.correcciones || []).filter((c) => c.anio === anio),
    };
  },

  /** Cada sitio contra SU meta para un KPI. Las metas por sitio no son comparables. */
  async kpiPorSitio({ anio, mes, kpi }) {
    const { d } = base();
    ({ anio, mes } = alCorte(d, anio, mes));
    if (anio !== d.anio || !d.kpis[kpi]) return null;
    const sitios = ['celta', 'estrella', 'agencias'];
    return {
      ...cabecera(d),
      kpi_id: kpi,
      kpi: d.kpis[kpi].nombre,
      unidad: d.kpis[kpi].unidad,
      sitios: sitios.map((s) => {
        const cm = contraMetaDe(d, s, mes) || {};
        const fila = cm[kpi] || {};
        return {
          sitio_id: s,
          sitio: d.ambitos[s],
          corporativo: d.mapaSitios[s],
          valor: fila.valor ?? null,
          meta: fila.meta ?? null,
          brecha_pct: fila.brecha_pct ?? null,
          estado: fila.estado || 'sin_dato',
        };
      }),
    };
  },

  /** Los doce meses del anio: mensual y YTD. Sin dato = null, nunca ausente. */
  async serieMensual({ anio, ambito, kpi }) {
    const { d } = base();
    ({ anio } = alCorte(d, anio, null));
    if (anio !== d.anio || !d.kpis[kpi] || !d.serie[ambito]) return null;
    const cm = d.contraMeta[ambito] || [];
    const meta = cm.length ? cm[cm.length - 1].kpis[kpi].meta : null;
    const esRef = cm.length ? cm[cm.length - 1].kpis[kpi].esReferencia : false;
    const porMes = new Map(d.serie[ambito].map((p) => [p.mes, p]));
    return {
      ...cabecera(d),
      ambito: { id: ambito, nombre: d.ambitos[ambito] },
      kpi_id: kpi,
      kpi: d.kpis[kpi].nombre,
      unidad: d.kpis[kpi].unidad,
      dec: d.kpis[kpi].dec,
      meta,
      es_referencia: esRef,
      meses: Array.from({ length: 12 }, (_, i) => {
        const p = porMes.get(i + 1);
        return {
          mes: i + 1,
          valor: p ? p.mensual[kpi] : null,
          valor_ytd: p ? p.ytd[kpi] : null,
        };
      }),
    };
  },

  /** La hoja de agua del area: consumo, lentes, ratio y variaciones, por ambito. */
  async aguaMensual({ anio, ambito }) {
    const { d, agua } = base();
    ({ anio } = alCorte(d, anio, null));
    if (anio !== d.anio) return null;
    // agua-detalle publica celta/estrella/agencias/nacional; nacional_labs no existe
    // en el reporte del area y se dice, no se inventa (R.5.5.1).
    const clave = ambito === 'nacional' ? 'nacional' : ambito;
    const filas = agua.mensual.filter((r) => r.anio === anio && r.sitio === clave);
    if (!filas.length) {
      return {
        ...cabecera(d),
        ambito: { id: ambito, nombre: d.ambitos[ambito] },
        filas: [],
        nota: 'sin_fila_en_reporte_area',
      };
    }
    return {
      ...cabecera(d),
      ambito: { id: ambito, nombre: d.ambitos[ambito] },
      filas: filas.map((r) => ({
        mes: r.mes,
        nombre_mes: r.nombre_mes,
        consumo_m3: r.consumo_total_m3,
        lentes: r.lentes_procesados,
        l_por_lente: r.consumo_por_lente_l,
        var_total_pct: r.var_total_pct === '' ? null : r.var_total_pct,
        var_por_lente_pct: r.var_por_lente_pct === '' ? null : r.var_por_lente_pct,
      })),
    };
  },

  /** El diario de agua. Hoy: construido y vacio, y lo dice. */
  async aguaDiaria({ anio, mes, sitio }) {
    const { d, agua } = base();
    ({ anio, mes } = alCorte(d, anio, mes));
    if (anio !== d.anio) return null;
    return {
      ...cabecera(d),
      sitio: sitio || null,
      mes: mes || null,
      disponible: Boolean(agua.diarioDisponible),
      estado: agua.diarioDisponible ? 'lecturas cargadas' : '0 lecturas diarias',
      dias: [],
    };
  },

  /**
   * De que esta hecho el residuo: peligroso, aprovechable y ordinario, mes a mes.
   *
   * El KPI dice CUANTO; esto dice DE QUE. Un incumplimiento de residuos no se corrige
   * igual si viene del peligroso que si viene del ordinario, y hasta ahora el dato
   * estaba en el archivo sin que nadie lo mirara. Las tres partes en g/lente suman
   * exactamente el KPI del mes: misma algebra, mismo denominador.
   */
  async residuosComposicion({ anio, ambito }) {
    const { d } = base();
    ({ anio } = alCorte(d, anio, null));
    const sitios = SITIOS_DE[ambito];
    if (anio !== d.anio || !sitios) return null;
    const porMes = new Map();
    for (const r of d.desgloseResiduos) {
      if (!sitios.includes(r.sitio)) continue;
      const a = porMes.get(r.mes) || {
        mes: r.mes,
        nombre_mes: r.nombreMes,
        peligroso: 0,
        aprovechable: 0,
        ordinario: 0,
        lbp: 0,
      };
      a.peligroso += r.peligroso;
      a.aprovechable += r.aprovechable;
      a.ordinario += r.ordinario;
      a.lbp += r.lbp;
      porMes.set(r.mes, a);
    }
    const partes = ['peligroso', 'aprovechable', 'ordinario'];
    const meses = [...porMes.values()]
      .sort((a, b) => a.mes - b.mes)
      .map((m) => {
        const total = m.peligroso + m.aprovechable + m.ordinario;
        const fila = {
          mes: m.mes,
          nombre_mes: m.nombre_mes,
          lentes: m.lbp,
          total_kg: total,
          total_g_lente: total ? (total * 1000) / m.lbp : 0,
        };
        for (const p of partes) {
          fila[p + '_kg'] = m[p];
          fila[p + '_g_lente'] = m.lbp ? (m[p] * 1000) / m.lbp : null;
          fila[p + '_part'] = total ? m[p] / total : null;
        }
        return fila;
      });
    // acumulado del anio: suma kilos, suma lentes, divide al final (regla 2 del area)
    const acum = partes.map((p) => {
      const kg = meses.reduce((t, m) => t + m[p + '_kg'], 0);
      const lentes = meses.reduce((t, m) => t + m.lentes, 0);
      const totalKg = meses.reduce((t, m) => t + m.total_kg, 0);
      return {
        parte: p,
        kg,
        g_lente: lentes ? (kg * 1000) / lentes : null,
        part: totalKg ? kg / totalKg : null,
      };
    });
    return {
      ...cabecera(d),
      ambito: { id: ambito, nombre: d.ambitos[ambito] },
      partes,
      meses,
      acumulado: acum,
    };
  },

  /**
   * La trayectoria del KPI en el scorecard corporativo: 2023 a 2026, meta y real.
   *
   * El cierre de 2026 todavia no existe, y no se inventa: se devuelve aparte el YTD al
   * corte, rotulado como lo que es. Comparar un acumulado de siete meses contra cierres
   * de anio completo sin decirlo seria el error clasico de este tipo de tabla.
   */
  async trayectoriaAnual({ kpi }) {
    const { d } = base();
    if (!d.kpis[kpi]) return null;
    const sc = (d.scorecard || {}).colombia_peru || {};
    const serie = sc[kpi];
    if (!serie) return null;
    const cmNacional = d.contraMeta.nacional || [];
    const ultimo = cmNacional[cmNacional.length - 1];
    return {
      ...cabecera(d),
      kpi_id: kpi,
      kpi: d.kpis[kpi].nombre,
      unidad: d.kpis[kpi].unidad,
      dec: d.kpis[kpi].dec,
      perimetro: 'COLOMBIA y PERU',
      anios: Object.keys(serie)
        .sort()
        .map((a) => ({
          anio: Number(a),
          meta: serie[a].meta,
          real: serie[a].real,
          cerrado: serie[a].real !== null,
        })),
      en_curso: ultimo
        ? {
            anio: d.anio,
            hasta_mes: d.corte,
            hasta: d.corteNombre,
            ytd: ultimo.kpis[kpi].valor,
            meta: ultimo.kpis[kpi].meta,
            estado: ultimo.kpis[kpi].estado,
            ambito: d.ambitos.nacional,
          }
        : null,
    };
  },

  /** Que mes trae lectura, cuantas y de que origen. */
  async calidadDato({ anio }) {
    const { d } = base();
    ({ anio } = alCorte(d, anio, null));
    if (anio !== d.anio) return null;
    return {
      ...cabecera(d),
      lecturas: d.calidad.lecturas,
      meses_con_dato: d.calidad.mesesConDato,
      por_mes: d.calidad.porMes,
      origen: d.calidad.origen,
      estado: d.calidad.estado,
      lecturas_diarias: 0,
      hallazgos: d.hallazgos,
    };
  },

  /** El crudo exportable: las magnitudes tal como se capturaron. */
  async detalle({ anio }) {
    const { d } = base();
    ({ anio } = alCorte(d, anio, null));
    if (anio !== d.anio) return null;
    return { ...cabecera(d), filas: d.detalleCrudo };
  },
};
