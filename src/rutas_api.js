/**
 * Los nueve GET del contrato /api/ehs/*. Cada uno valida parametros, llama al
 * adaptador y serializa. NO calcula: el calculo tiene una sola implementacion y
 * vive en la capa de datos (R.5.2.1, R.5.2.2).
 */
const datos = require('./datos');
const errores = require('./errores');

const AMBITOS = ['celta', 'estrella', 'agencias', 'nacional_labs', 'nacional'];
const KPIS = [
  'agua_por_lente',
  'energia_por_lente',
  'residuos_por_lente',
  'frequency_rate',
  'accidentes_dafw',
];

function entero(q, nombre, defecto, min, max) {
  const crudo = q.get(nombre);
  if (crudo === null || crudo === '') return defecto;
  const n = Number(crudo);
  if (!Number.isInteger(n) || n < min || n > max) return NaN;
  return n;
}

function json(res, cuerpo) {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(cuerpo));
}

/* excel: separador ';' y coma decimal, que es lo que espera Excel con la configuracion
   regional de Colombia. Con ',' y punto decimal, el doble clic abria todo el archivo en
   una sola columna, justo en el paso de "verificar los datos". El CSV normal (',' y
   punto) se queda para cualquier otra herramienta. */
function csv(res, filas, nombre, excel) {
  const cols = Object.keys(filas[0] || {});
  const sep = excel ? ';' : ',';
  const esc = (v) => {
    let s = v === null || v === undefined ? '' : String(v);
    if (excel && typeof v === 'number') s = s.replace('.', ',');
    return /[",;\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const cuerpo = [cols.join(sep)]
    .concat(filas.map((f) => cols.map((c) => esc(f[c])).join(sep)))
    .join('\n');
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${nombre}"`);
  res.end('﻿' + cuerpo);
}

/** Atiende una peticion /api/ehs/*. Devuelve true si la ruta era suya. */
async function atender(req, res, url) {
  const ruta = url.pathname.replace(/\/+$/, '');
  const q = url.searchParams;
  if (!ruta.startsWith('/api/ehs/')) return false;

  // La salud no necesita anio/mes, y sobre todo no debe fallar si el motor esta
  // abajo: es justo lo que esta ruta tiene que poder decir. Se resuelve antes de
  // cualquier otra validacion o try, para que un motor inalcanzable nunca deje sin
  // franja de estado a quien esta viendo el problema.
  if (ruta === '/api/ehs/salud') {
    const r = await datos.salud();
    return (json(res, r), true);
  }

  // sin parametro, null: el adaptador resuelve el corte publicado. Fijar 2026 y 7 aqui
  // obligaria a editar codigo cada mes, que es justo lo que este trabajo vino a quitar.
  const anio = entero(q, 'anio', null, 2023, 2100);
  const mes = entero(q, 'mes', null, 1, 12);
  if (Number.isNaN(anio) || Number.isNaN(mes)) {
    errores.parametroInvalido(res, 'El anio o el mes no son validos.', {
      anio: q.get('anio'),
      mes: q.get('mes'),
    });
    return true;
  }

  try {
    if (ruta === '/api/ehs/panorama') {
      const ambito = q.get('ambito') || 'nacional';
      if (!AMBITOS.includes(ambito)) {
        errores.parametroInvalido(res, `Ambito desconocido: ${ambito}.`, { validos: AMBITOS });
        return true;
      }
      const r = await datos.panorama({ anio, mes, ambito });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/kpi-por-sitio') {
      const kpi = q.get('kpi') || 'residuos_por_lente';
      if (!KPIS.includes(kpi)) {
        errores.parametroInvalido(res, `KPI desconocido: ${kpi}.`, { validos: KPIS });
        return true;
      }
      const r = await datos.kpiPorSitio({ anio, mes, kpi });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/serie-mensual') {
      const ambito = q.get('ambito') || 'nacional';
      const kpi = q.get('kpi') || 'residuos_por_lente';
      if (!AMBITOS.includes(ambito) || !KPIS.includes(kpi)) {
        errores.parametroInvalido(res, 'Ambito o KPI desconocido.', { ambito, kpi });
        return true;
      }
      const r = await datos.serieMensual({ anio, ambito, kpi });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/agua-mensual') {
      const ambito = q.get('ambito') || 'nacional';
      if (!AMBITOS.includes(ambito)) {
        errores.parametroInvalido(res, `Ambito desconocido: ${ambito}.`, { validos: AMBITOS });
        return true;
      }
      const r = await datos.aguaMensual({ anio, ambito });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/agua-diaria') {
      const r = await datos.aguaDiaria({ anio, mes, sitio: q.get('sitio') });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/residuos-composicion') {
      const ambito = q.get('ambito') || 'nacional';
      if (!AMBITOS.includes(ambito)) {
        errores.parametroInvalido(res, `Ambito desconocido: ${ambito}.`, { validos: AMBITOS });
        return true;
      }
      const r = await datos.residuosComposicion({ anio, ambito });
      if (!r) return (errores.noEncontrado(res, `Sin composicion de residuos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/trayectoria-anual') {
      const kpi = q.get('kpi') || 'residuos_por_lente';
      if (!KPIS.includes(kpi)) {
        errores.parametroInvalido(res, `KPI desconocido: ${kpi}.`, { validos: KPIS });
        return true;
      }
      const r = await datos.trayectoriaAnual({ kpi });
      if (!r) return (errores.noEncontrado(res, `El scorecard no publica ${kpi}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/calidad-dato') {
      const r = await datos.calidadDato({ anio });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/datos') {
      // los datos detras de las graficas, para la vista "Datos" del tablero
      const ambito = q.get('ambito') || 'nacional';
      if (!AMBITOS.includes(ambito)) {
        errores.parametroInvalido(res, `Ambito desconocido: ${ambito}.`, { validos: AMBITOS });
        return true;
      }
      const r = await datos.datosTabulados({ anio, ambito });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      return (json(res, r), true);
    }

    if (ruta === '/api/ehs/detalle') {
      const r = await datos.detalle({ anio });
      if (!r) return (errores.noEncontrado(res, `Sin datos para ${anio}.`), true);
      if (q.get('formato') === 'csv') return (csv(res, r.filas, `ehs_detalle_${r.anio}.csv`), true);
      if (q.get('formato') === 'excel') {
        return (csv(res, r.filas, `ehs_detalle_${r.anio}_excel.csv`, true), true);
      }
      return (json(res, r), true);
    }

    errores.noEncontrado(res, `No existe el recurso ${ruta}.`);
    return true;
  } catch (err) {
    errores.interno(res, err);
    return true;
  }
}

module.exports = { atender };
