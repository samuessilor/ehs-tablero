/**
 * Adaptador Postgres — el destino. Puerto literal de adaptador_sql.js
 * (driver 'mssql' -> 'pg'), MISMA logica de negocio y MISMAS claves de salida:
 * el front (public/js/tablero.js) y las rutas API consumen estas funciones tal
 * cual, y un cambio de forma de la respuesta rompe el front sin que se note en
 * el codigo SQL.
 *
 * Cada funcion consulta las vistas del esquema ehs (postgres/02_vistas.sql),
 * que implementan las dos reglas del area una sola vez. Aqui no se calcula
 * ningun indicador (R.5.2.1): lo que no sale de una vista sale de una
 * agregacion SQL, y lo unico que hace JavaScript es dar forma a la respuesta.
 *
 * DIFERENCIAS MECANICAS DE TRADUCCION APLICADAS EN TODO EL ARCHIVO (ver el
 * encargo de esta tarea):
 *   - parametros con nombre (.input('anio', sql.SmallInt, anio)) -> placeholders
 *     posicionales $1, $2, ... de 'pg'. 'pg' es estrictamente posicional (no
 *     reutiliza un nombre), asi que cada consulta recibe su propio arreglo de
 *     parametros en el orden exacto de sus $N.
 *   - ISNULL -> COALESCE; TOP N -> LIMIT N al final; CONVERT(varchar,x,120/23)
 *     -> to_char(...); YEAR()/MONTH() -> EXTRACT(...); 'a' + 'b' -> 'a' || 'b'
 *     o CONCAT(...).
 *   - DECLARE @tabla (tabla variable T-SQL compartida entre varios SELECT del
 *     mismo batch) -> CTE (WITH ... AS (...)). Como 'pg' obliga a correr cada
 *     SELECT como una consulta SEPARADA (ver el punto siguiente), la MISMA CTE
 *     se repite textualmente en cada consulta que la necesita (son lecturas
 *     baratas: un ano de datos mensuales) en vez de usar una tabla temporal
 *     real — una tabla temporal vive en la conexion que la crea, y el pool de
 *     'pg' no garantiza que dos llamadas a pool.query() sucesivas usen la
 *     MISMA conexion, así que una tabla temporal real se habria podido crear
 *     en una conexion y consultar en otra sin ningun error visible, dando
 *     "la tabla no existe" de forma intermitente. La CTE repetida evita ese
 *     riesgo sin tener que fijar un cliente exclusivo del pool para cada
 *     funcion.
 *   - 'select ... ; select ... ; select ...' (un mismo request.query de mssql
 *     devolviendo varios recordsets por indice) -> una llamada a pool.query()
 *     por cada select, combinadas en JavaScript en el mismo orden que el
 *     original esperaba (exactamente como las desestructuraba de
 *     r.recordsets[0], r.recordsets[1], ...).
 *
 * Mismo modulo que no se apoya en la vista que le correspondia — ver el
 * encabezado de adaptador_sql.js para el detalle completo; esos tres puntos
 * (vista corregida en vez de rodeo en el adaptador, +5%/90% de v_kpi_contra_meta,
 * texto de v_calidad_avisos) aplican igual aqui porque las vistas Postgres
 * (postgres/02_vistas.sql) ya portan esas mismas correcciones.
 */
const fs = require('fs');
const path = require('path');
const { pool } = require('./conexion_pg');

const RUTA_METADATOS = path.join(__dirname, '..', '..', 'datos', 'datos.json');

let metadatosCache = null;
function metadatos() {
  if (metadatosCache) return metadatosCache;
  if (!fs.existsSync(RUTA_METADATOS)) {
    const e = new Error(
      'Falta datos.json en app/datos. Guarda los metadatos del corte publicado ' +
        '(hallazgos, correcciones y procedencia) y no viaja en el repositorio: ' +
        'publicalo con "python scripts/publicar_a_app.py".'
    );
    e.codigo = 'sin_datos_publicados';
    throw e;
  }
  const d = JSON.parse(fs.readFileSync(RUTA_METADATOS, 'utf-8'));
  metadatosCache = {
    actualizadoEn: d.actualizadoEn,
    fuente: d.fuente,
    origen: (d.calidad || {}).origen,
    hallazgos: d.hallazgos || [],
    correcciones: d.correcciones || [],
  };
  return metadatosCache;
}

/** Un numero, nunca la cadena con la que el driver a veces devuelve un decimal
 * (pg devuelve 'numeric' como string por defecto, igual de ambiguo que el caso
 * que este helper ya resolvia para 'mssql'). */
const num = (v) => (v === null || v === undefined ? null : Number(v));

/**
 * Cuantos decimales publica cada KPI. El JSON lo trae dado; en SQL se lee del
 * formato de presentacion de dim_kpi: '0.000' son tres decimales, '0.0' uno y
 * '0' ninguno.
 */
function decimales(formato) {
  const f = String(formato || '');
  const punto = f.indexOf('.');
  return punto === -1 ? 0 : f.length - punto - 1;
}

/** De donde saca su meta cada ambito — ver adaptador_sql.js para la razon
 * completa de cada caso; literal, no se traduce nada aqui. */
const META_DE_AMBITO = {
  celta: 'celta',
  estrella: 'estrella',
  agencias: 'agencias',
  nacional: 'nacional',
  nacional_labs: null,
  peru: 'peru',
  colombia_peru: 'colombia_peru',
};

/* El valor tal como lo publica la vista: redondeado a 6 decimales, igual que
 * el motor validado lo publica. 'v.valor' es numeric en las vistas Postgres,
 * round(numeric,int) existe nativo. */
const VALOR_RECUPERADO = `case when v.valor is null then null
                               else round(v.valor, 6) end`;

/**
 * La brecha y el semaforo, tal como los define el contrato publicado. Igual
 * que en el original, van en SQL (parametrizadas por el alias de meta/valor)
 * para que este adaptador no sea una segunda implementacion del calculo.
 */
const brechaSql = (metaCol, valorCol) =>
  `case when ${metaCol} is null or ${metaCol} = 0 or ${valorCol} is null then null
        else round((${valorCol} - ${metaCol}) / ${metaCol}, 6) end`;

const estadoSql = (metaCol, valorCol) =>
  `case when ${metaCol} is null then 'sin_meta'
        when ${valorCol} is null then 'sin_dato'
        when ${metaCol} = 0 then case when ${valorCol} <= 0
                                    then 'cumple' else 'incumple' end
        when ${valorCol} > ${metaCol} then 'incumple'
        when ${valorCol} >= ${metaCol} * 0.90 then 'riesgo'
        else 'cumple' end`;

/** El nombre largo del ambito: el del sitio si lo es, y el del agregado si no.
 * 'pAmbito' es el placeholder posicional ($N) de ESA consulta — ver la nota de
 * CTEs repetidas al inicio del archivo: esta funcion no liga a un numero de
 * parametro fijo porque cada consulta que la usa tiene su propio orden de $N. */
const nombreAmbitoSql = (
  pAmbito
) => `(select case when a.ambito_id = a.sitio_id then s.sitio else a.ambito end
                                          from ehs.v_ambito a
                                          join ref.dim_sitio s on s.sitio_id = a.sitio_id
                                         where a.ambito_id = ${pAmbito}
                                         order by a.sitio_id
                                         limit 1)`;

/**
 * Los valores YTD y mensuales del ambito, ya recuperados, como par de CTEs.
 * Equivalente de VALORES_DEL_AMBITO (DECLARE @ytd/@mensual + INSERT) del
 * original: aqui se recibe como texto parametrizado por los placeholders
 * posicionales de la consulta que la usa (pAnio/pAmbito/pCorte), para poder
 * repetirla igual en varias consultas separadas sin perder los mismos nombres.
 */
const cteYtdMensual = (pAnio, pAmbito, pCorte) => `with ytd as (
        select v.kpi_id, v.num_mes_corte as num_mes, ${VALOR_RECUPERADO} as valor
          from ehs.v_kpi_ytd v
          join ref.dim_kpi k on k.kpi_id = v.kpi_id
         where v.anio = ${pAnio} and v.ambito_id = ${pAmbito} and v.num_mes_corte <= ${pCorte}
    ),
    mensual as (
        select v.kpi_id, v.num_mes, ${VALOR_RECUPERADO} as valor
          from ehs.v_kpi_mensual v
          join ref.dim_kpi k on k.kpi_id = v.kpi_id
         where v.anio = ${pAnio} and v.ambito_id = ${pAmbito} and v.num_mes <= ${pCorte}
    )`;

/**
 * El valor tal como lo escribe un humano: 800 y no 800.0000, 979.1 y no
 * 979.1000. Lo necesitan los mensajes de aviso, que citan la lectura dentro de
 * una frase. 'c' ya llega como float8 en las CTE que lo usan (ver 'valores' en
 * calidadDato), asi que basta ::text para la version "humana" del float (sin
 * ceros de relleno) y bigint::text para el caso entero.
 */
const comoTexto = (c) => `case when ${c} = floor(${c}) then floor(${c})::bigint::text
                                else (${c})::text end`;

async function consulta(texto, params = []) {
  const p = await pool();
  return p.query(texto, params);
}

/**
 * La hoja mensual "consumo, produccion y ratio" de un KPI de razon simple (un
 * numerador, un denominador): agua y energia comparten exactamente esta forma.
 * Que magnitud es el numerador y cual el denominador lo dice ref.kpi_magnitud.
 */
async function hojaMensualRecurso({ ctx, anio, ambito, kpiId }) {
  const { rows: filasNombre } = await consulta(`select ${nombreAmbitoSql('$1')} as nombre`, [
    ambito,
  ]);
  const general = filasNombre[0] || {};

  const { rows: filas } = await consulta(
    `
    with mensual as (
        select f.num_mes, f.mes as nombre_mes,
               sum(case when km.rol = 'numerador' then la.valor::float8 end) as num,
               sum(case when km.rol = 'denominador' then la.valor::float8 end) as den
          from ehs.v_lectura_ambito la
          join ref.dim_fecha f on f.fecha = la.fecha
          join ref.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id and km.kpi_id = $4
         where la.anio = $1 and la.ambito_id = $3 and f.num_mes <= $2
         group by f.num_mes, f.mes
    ),
    con_previo as (
        select *,
               lag(num) over (order by num_mes) as num_prev,
               lag(den) over (order by num_mes) as den_prev,
               lag(num_mes) over (order by num_mes) as mes_prev
          from mensual
    )
    select num_mes as mes, nombre_mes,
           round(num::numeric, 2) as consumo,
           den::bigint as lentes,
           round((num * (select factor from ref.dim_kpi where kpi_id = $4)
                  / nullif(den, 0))::numeric, 4) as ratio,
           case when mes_prev = num_mes - 1 and num_prev <> 0
                then round(((num - num_prev) / num_prev * 100)::numeric, 2) end as var_total_pct,
           -- el factor de conversion se cancela en un cambio porcentual: no hace
           -- falta traerlo aqui otra vez
           case when mes_prev = num_mes - 1 and num_prev <> 0
                     and den_prev <> 0 and den <> 0
                then round(((num / den - num_prev / den_prev) / (num_prev / den_prev) * 100)::numeric, 2)
           end as var_por_lente_pct
      from con_previo
     order by num_mes
    `,
    [anio, ctx.corte, ambito, kpiId]
  );

  return { nombre: general.nombre, filas };
}

/**
 * El corte publicado: que anio y hasta que mes hay dato COMPLETO, y que juego
 * de metas esta marcado vigente. Lo decide ehs.v_corte_publicado, no el ultimo
 * mes que aparezca en la tabla (ver adaptador_sql.js para el porque completo).
 */
async function contexto() {
  const { rows: base } = await consulta(
    `select anio, corte
       from ehs.v_corte_publicado
      where corte is not null
      order by anio desc
      limit 1`
  );
  const b = base[0] || {};
  const anio = b.anio ?? null;
  const corte = b.corte ?? null;

  const { rows: detalleRows } = await consulta(
    `select (select mes from ref.dim_fecha where anio = $1 and num_mes = $2 limit 1) as corte_nombre,
            case
                when exists (select 1 from ehs.meta
                              where anio = $1 and vigente and ambito_id = 'nacional')
                then 'Nacional: libro KPIs ' || $1::text || ' · sitios: '
                     || coalesce((select max(fuente) from ehs.meta
                                   where anio = $1 and vigente and ambito_id <> 'nacional'),
                                 'sin meta')
                else (select max(fuente) from ehs.meta where anio = $1 and vigente)
            end as meta_vigente,
            -- hora de pared de Colombia (timestamp sin zona); sin recortar aqui,
            -- .toISOString() mas abajo le pegaria una 'Z' que el cliente leeria
            -- como UTC
            (select max(coalesce(l.modificado_en, l.capturado_en))
               from ehs.hecho_lectura_mensual l
               join ref.dim_fecha f on f.fecha = l.fecha
              where f.anio = $1 and f.num_mes <= $2) as actualizado_en`,
    [anio, corte]
  );
  const c = detalleRows[0] || {};

  const { rows: meses } = await consulta(
    `select f.num_mes
       from ehs.hecho_lectura_mensual l
       join ref.dim_fecha f on f.fecha = l.fecha
      where f.anio = $1 and f.num_mes <= $2
      group by f.num_mes
      order by f.num_mes`,
    [anio, corte]
  );

  return {
    anio,
    corte,
    corteNombre: c.corte_nombre ?? null,
    metaVigente: c.meta_vigente ?? null,
    actualizadoEn: c.actualizado_en ? new Date(c.actualizado_en).toISOString().slice(0, 19) : null,
    mesesConDato: meses.map((x) => x.num_mes),
  };
}

function cabecera(ctx) {
  const m = metadatos();
  return {
    anio: ctx.anio,
    corte: { mes: ctx.corte, nombre: ctx.corteNombre, mesesConDato: ctx.mesesConDato },
    actualizado_en: ctx.actualizadoEn ?? m.actualizadoEn,
    fuente: m.fuente,
    meta_vigente: ctx.metaVigente,
  };
}

/**
 * Las correcciones hechas desde "Consultar y corregir" que tocan el ambito,
 * para la franja "Valor corregido" del tablero.
 */
async function correccionesDelAmbito(anio, ambito) {
  const { rows } = await consulta(
    `select c.anio, c.mes, c.sitio_corto, c.magnitud,
            c.valor_anterior::float8 as valor_anterior,
            c.valor_corregido::float8 as valor_corregido,
            c.motivo, c.autorizado_por,
            to_char(c.corregido_en, 'YYYY-MM-DD HH24:MI') as corregido_en
       from ehs.v_correcciones c
       join ehs.v_ambito a on a.sitio_id = c.sitio_id and a.ambito_id = $2
      where c.anio = $1
      order by c.corregido_en desc, c.hist_id desc
      limit 10`,
    [anio, ambito]
  );
  const texto = (v) => (v === null || v === undefined ? '—' : String(v).replace('.', ','));
  return rows.map((x) => ({
    anio: x.anio,
    mes: x.mes,
    sitio: x.sitio_corto,
    magnitud: x.magnitud,
    valorExcel: texto(x.valor_anterior),
    valorCorregido: texto(x.valor_corregido),
    motivo: x.motivo,
    autorizadoPor: x.autorizado_por,
    fecha: x.corregido_en,
  }));
}

/** anio y mes ausentes significan "el corte publicado", igual que en el adaptador JSON. */
function alCorte(ctx, anio, mes) {
  return { anio: anio == null ? ctx.anio : anio, mes: mes == null ? ctx.corte : mes };
}

module.exports = {
  /** Los cinco KPI del ambito al corte, con meta, brecha y estado ya resueltos. */
  async panorama({ anio, mes, ambito }) {
    const ctx = await contexto();
    ({ anio, mes } = alCorte(ctx, anio, mes));
    if (anio !== ctx.anio) return null;

    const ambitoMeta = META_DE_AMBITO[ambito] ?? null;

    const { rows: generalRows } = await consulta(
      `${cteYtdMensual('$1', '$4', '$3')}
      , mes_ef_calc as (
          select case
                   when exists (select 1 from mensual where num_mes = $2) then $2
                   when $2 <= $3 then (select max(num_mes) from mensual where num_mes < $2)
                 end as mes_ef
      )
      select ${nombreAmbitoSql('$4')} as nombre,
             case when mec.mes_ef is not null then 1 else 0 end as hay_dato,
             mec.mes_ef as mes_ef,
             (select mes from ref.dim_fecha where anio = $1 and num_mes = mec.mes_ef limit 1) as nombre_mes
        from mes_ef_calc mec`,
      [anio, mes, ctx.corte, ambito]
    );
    const general = generalRows[0] || {};
    if (!general.hay_dato) return null;
    const mesEf = general.mes_ef;

    const { rows: kpis } = await consulta(
      `${cteYtdMensual('$1', '$3', '$2')}
      select k.kpi_id, k.kpi, k.unidad, k.familia, k.formato,
             y.valor as valor,
             m.valor as valor_mes,
             mt.valor as meta,
             case when $4::varchar is not null and $4 <> $3 then 1 else 0 end as es_referencia,
             ${brechaSql('mt.valor', 'y.valor')} as brecha_pct,
             ${estadoSql('mt.valor', 'y.valor')} as estado
        from ref.dim_kpi k
        left join ytd y on y.kpi_id = k.kpi_id and y.num_mes = $5
        left join mensual m on m.kpi_id = k.kpi_id and m.num_mes = $5
        left join ehs.meta mt
               on mt.anio = $1 and mt.vigente
              and mt.ambito_id = $4 and mt.kpi_id = k.kpi_id
       where k.area = 'ehs'
       order by k.orden`,
      [anio, ctx.corte, ambito, ambitoMeta, mesEf]
    );
    if (!kpis.length) return null;

    const { rows: serie } = await consulta(
      `${cteYtdMensual('$1', '$3', '$2')}
      select y.kpi_id, y.num_mes as mes, y.valor,
             ${brechaSql('mt.valor', 'y.valor')} as brecha_pct,
             ${estadoSql('mt.valor', 'y.valor')} as estado
        from ytd y
        left join ehs.meta mt
               on mt.anio = $1 and mt.vigente
              and mt.ambito_id = $4 and mt.kpi_id = y.kpi_id
       where exists (select 1 from mensual d where d.num_mes = y.num_mes)
       order by y.kpi_id, y.num_mes`,
      [anio, ctx.corte, ambito, ambitoMeta]
    );

    const { rows: mesesAmbito } = await consulta(
      `${cteYtdMensual('$1', '$3', '$2')}
      select num_mes from mensual group by num_mes order by num_mes`,
      [anio, ctx.corte, ambito]
    );

    const porKpi = new Map();
    for (const s of serie) {
      if (!porKpi.has(s.kpi_id)) porKpi.set(s.kpi_id, []);
      porKpi.get(s.kpi_id).push({
        mes: s.mes,
        valor: num(s.valor),
        estado: s.estado,
        brecha_pct: num(s.brecha_pct),
      });
    }

    return {
      ...cabecera(ctx),
      corte: {
        mes: general.mes_ef,
        nombre: general.nombre_mes,
        mesesConDato: mesesAmbito.map((x) => x.num_mes),
      },
      ambito: { id: ambito, nombre: general.nombre },
      kpi: kpis.map((k) => ({
        kpi_id: k.kpi_id,
        kpi: k.kpi,
        unidad: k.unidad,
        familia: k.familia,
        dec: decimales(k.formato),
        valor: num(k.valor),
        valor_mes: num(k.valor_mes),
        meta: num(k.meta),
        es_referencia: Boolean(k.es_referencia),
        brecha_pct: num(k.brecha_pct),
        estado: k.estado,
        serie_ytd: porKpi.get(k.kpi_id) || [],
      })),
      correcciones: metadatos()
        .correcciones.filter((c) => c.anio === anio)
        .concat(await correccionesDelAmbito(anio, ambito)),
    };
  },

  /** Cada sitio contra SU meta para un KPI. Las metas por sitio no son comparables. */
  async kpiPorSitio({ anio, mes, kpi }) {
    const ctx = await contexto();
    ({ anio, mes } = alCorte(ctx, anio, mes));
    if (anio !== ctx.anio || mes > ctx.corte) return null;

    const { rows: defRows } = await consulta(
      `select k.kpi, k.unidad from ref.dim_kpi k where k.kpi_id = $1 and k.area = 'ehs'`,
      [kpi]
    );
    const def = defRows[0];
    if (!def) return null;

    const { rows: sitios } = await consulta(
      `with ytd as (
          select v.ambito_id, ${VALOR_RECUPERADO} as valor
            from ehs.v_kpi_ytd v
            join ref.dim_kpi k on k.kpi_id = v.kpi_id
            join ref.dim_sitio s on s.sitio_id = v.ambito_id and s.activo and s.en_nacional
           where v.anio = $1 and v.num_mes_corte = $2 and v.kpi_id = $3
      )
      select s.sitio_id, s.sitio, s.nombre_corporativo as corporativo,
             y.valor as valor,
             mt.valor as meta,
             ${brechaSql('mt.valor', 'y.valor')} as brecha_pct,
             ${estadoSql('mt.valor', 'y.valor')} as estado
        from ref.dim_sitio s
        left join ytd y on y.ambito_id = s.sitio_id
        left join ehs.meta mt
               on mt.anio = $1 and mt.vigente and mt.ambito_id = s.sitio_id and mt.kpi_id = $3
       where s.activo and s.en_nacional
       -- los dos laboratorios primero y Agencias despues: el orden del reporte del area
       order by s.en_nacional_labs desc, s.sitio_id`,
      [anio, mes, kpi]
    );

    return {
      ...cabecera(ctx),
      kpi_id: kpi,
      kpi: def.kpi,
      unidad: def.unidad,
      sitios: sitios.map((s) => ({
        sitio_id: s.sitio_id,
        sitio: s.sitio,
        corporativo: s.corporativo,
        valor: num(s.valor),
        meta: num(s.meta),
        brecha_pct: num(s.brecha_pct),
        estado: s.estado || 'sin_dato',
      })),
    };
  },

  /** Los doce meses del anio: mensual y YTD. Sin dato = null, nunca ausente. */
  async serieMensual({ anio, ambito, kpi }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const ambitoMeta = META_DE_AMBITO[ambito] ?? null;

    const { rows: defRows } = await consulta(
      `${cteYtdMensual('$1', '$3', '$2')}
      select k.kpi, k.unidad, k.formato,
             ${nombreAmbitoSql('$3')} as nombre_ambito,
             case when exists (select 1 from mensual) then 1 else 0 end as hay_serie,
             mt.valor as meta,
             case when $4::varchar is not null and $4 <> $3 then 1 else 0 end as es_referencia
        from ref.dim_kpi k
        left join ehs.meta mt
               on mt.anio = $1 and mt.vigente and mt.ambito_id = $4 and mt.kpi_id = k.kpi_id
       where k.kpi_id = $5 and k.area = 'ehs'`,
      [anio, ctx.corte, ambito, ambitoMeta, kpi]
    );
    const def = defRows[0];
    if (!def || !def.hay_serie) return null;

    const { rows: meses } = await consulta(
      `${cteYtdMensual('$1', '$3', '$2')}
      select f.num_mes as mes,
             m.valor as valor,
             -- el acumulado solo existe donde hay mes reportado; mas alla del
             -- corte v_kpi_ytd repite el ultimo y eso no es un dato del mes
             case when exists (select 1 from mensual d where d.num_mes = f.num_mes)
                  then y.valor end as valor_ytd
        from ref.dim_fecha f
        left join mensual m on m.num_mes = f.num_mes and m.kpi_id = $4
        left join ytd y on y.num_mes = f.num_mes and y.kpi_id = $4
       where f.anio = $1
       order by f.num_mes`,
      [anio, ctx.corte, ambito, kpi]
    );

    return {
      ...cabecera(ctx),
      ambito: { id: ambito, nombre: def.nombre_ambito },
      kpi_id: kpi,
      kpi: def.kpi,
      unidad: def.unidad,
      dec: decimales(def.formato),
      meta: num(def.meta),
      es_referencia: Boolean(def.es_referencia),
      meses: meses.map((m) => ({
        mes: m.mes,
        valor: num(m.valor),
        valor_ytd: num(m.valor_ytd),
      })),
    };
  },

  /** La hoja de agua del area: consumo, lentes, ratio y variaciones, por ambito. */
  async aguaMensual({ anio, ambito }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { nombre, filas } = await hojaMensualRecurso({
      ctx,
      anio,
      ambito,
      kpiId: 'agua_por_lente',
    });

    // el reporte de agua del area publica cada sitio y el consolidado nacional;
    // Nacional Labs es un subconjunto que ese reporte no tiene, y se dice, no se
    // inventa (R.5.5.1)
    if (ambito === 'nacional_labs' || !filas.length) {
      return {
        ...cabecera(ctx),
        ambito: { id: ambito, nombre },
        filas: [],
        nota: 'sin_fila_en_reporte_area',
      };
    }

    return {
      ...cabecera(ctx),
      ambito: { id: ambito, nombre },
      filas: filas.map((f) => ({
        mes: f.mes,
        nombre_mes: f.nombre_mes,
        consumo_m3: num(f.consumo),
        lentes: num(f.lentes),
        l_por_lente: num(f.ratio),
        var_total_pct: num(f.var_total_pct),
        var_por_lente_pct: num(f.var_por_lente_pct),
      })),
    };
  },

  /**
   * La misma hoja que aguaMensual, para energia. A diferencia del agua, el
   * area no publica un reporte externo de energia que excluya Nacional Labs.
   */
  async energiaMensual({ anio, ambito }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { nombre, filas } = await hojaMensualRecurso({
      ctx,
      anio,
      ambito,
      kpiId: 'energia_por_lente',
    });

    if (!filas.length) {
      return {
        ...cabecera(ctx),
        ambito: { id: ambito, nombre },
        filas: [],
        nota: 'sin_fila_en_reporte_area',
      };
    }

    return {
      ...cabecera(ctx),
      ambito: { id: ambito, nombre },
      filas: filas.map((f) => ({
        mes: f.mes,
        nombre_mes: f.nombre_mes,
        consumo_kwh: num(f.consumo),
        lentes: num(f.lentes),
        kwh_por_lente: num(f.ratio),
        var_total_pct: num(f.var_total_pct),
        var_por_lente_pct: num(f.var_por_lente_pct),
      })),
    };
  },

  /** El diario de agua. Hoy: construido y vacio, y lo dice. */
  async aguaDiaria({ anio, mes, sitio }) {
    const ctx = await contexto();
    ({ anio, mes } = alCorte(ctx, anio, mes));
    if (anio !== ctx.anio) return null;

    const { rows: estadoRows } = await consulta(
      `select filas, estado from ehs.v_estado_agua_diaria`
    );
    const estado = estadoRows[0] || {};

    const { rows: dias } = await consulta(
      `select to_char(d.fecha, 'YYYY-MM-DD') as fecha,
              d.sitio_id, d.sitio_corto, d.consumo_m3, d.observacion,
              d.mediana_m3, d.desviacion, d.es_pico
         from ehs.v_agua_diaria d
        where extract(year from d.fecha)::int = $1
          and ($2::smallint is null or extract(month from d.fecha)::int = $2)
          and ($3::varchar is null or d.sitio_id = $3)
        order by d.fecha, d.sitio_id`,
      [anio, mes ?? null, sitio ?? null]
    );

    return {
      ...cabecera(ctx),
      sitio: sitio || null,
      mes: mes || null,
      disponible: estado.filas > 0,
      // el rotulo lo decide el conteo de filas dentro de la vista, no una
      // constante: el dia que el area entregue el registro diario cambia solo
      estado: estado.estado,
      dias: dias.map((d) => ({
        fecha: d.fecha,
        sitio_id: d.sitio_id,
        sitio: d.sitio_corto,
        consumo_m3: num(d.consumo_m3),
        mediana_m3: num(d.mediana_m3),
        desviacion: num(d.desviacion),
        es_pico: Boolean(d.es_pico),
        observacion: d.observacion,
      })),
    };
  },

  /**
   * De que esta hecho el residuo: peligroso, aprovechable y ordinario, mes a
   * mes. El KPI dice CUANTO; esto dice DE QUE. Se suman los kilos crudos, se
   * suman los lentes, y se divide AL FINAL (regla 2 del area).
   */
  async residuosComposicion({ anio, ambito }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const cteKgLentes = `with kg as (
          select f.num_mes, f.mes as nombre_mes, la.magnitud_id, g.orden,
                 sum(la.valor::float8) as kg
            from ehs.v_lectura_ambito la
            join ref.dim_fecha f on f.fecha = la.fecha
            join ref.dim_magnitud g on g.magnitud_id = la.magnitud_id
            join ref.kpi_magnitud km
              on km.magnitud_id = la.magnitud_id
             and km.kpi_id = 'residuos_por_lente' and km.rol = 'numerador'
           where la.anio = $1 and la.ambito_id = $3 and f.num_mes <= $2
           group by f.num_mes, f.mes, la.magnitud_id, g.orden
      ),
      -- solo los meses que traen residuo: un mes con lentes y sin pesaje no
      -- puede entrar al denominador del acumulado, o el g/lente del anio
      -- saldria diluido
      lentes as (
          select f.num_mes, sum(la.valor::float8) as lbp
            from ehs.v_lectura_ambito la
            join ref.dim_fecha f on f.fecha = la.fecha
            join ref.kpi_magnitud km
              on km.magnitud_id = la.magnitud_id
             and km.kpi_id = 'residuos_por_lente' and km.rol = 'denominador'
           where la.anio = $1 and la.ambito_id = $3 and f.num_mes <= $2
             and exists (select 1 from kg x where x.num_mes = f.num_mes)
           group by f.num_mes
      ),
      kg_total_mes as (
          select num_mes, sum(kg) as total_kg from kg group by num_mes
      )`;

    const { rows: nombreRows } = await consulta(`select ${nombreAmbitoSql('$1')} as nombre`, [
      ambito,
    ]);
    const general = nombreRows[0] || {};

    const { rows: largo } = await consulta(
      `${cteKgLentes}
      -- suma_kg/suma_g_lente (no total_kg/total_g_lente): 'total' es tambien un
      -- valor real de "parte" (residuo_total_kg de Peru, sin desglose), y el
      -- cliente guarda cada parte como fila[parte + '_kg']
      select k.num_mes as mes, k.nombre_mes,
             replace(replace(k.magnitud_id, 'residuo_', ''), '_kg', '') as parte,
             l.lbp as lentes,
             t.total_kg as suma_kg,
             case when t.total_kg = 0 then 0
                  else t.total_kg * 1000 / nullif(l.lbp, 0) end as suma_g_lente,
             k.kg as kg,
             case when l.lbp = 0 then null else k.kg * 1000 / l.lbp end as g_lente,
             case when t.total_kg = 0 then null else k.kg / t.total_kg end as part
        from kg k
        join lentes l on l.num_mes = k.num_mes
        join kg_total_mes t on t.num_mes = k.num_mes
       order by k.num_mes, k.orden`,
      [anio, ctx.corte, ambito]
    );

    const { rows: acumulado } = await consulta(
      `${cteKgLentes}
      -- acumulado del anio: suma kilos, suma lentes, divide al final. El
      -- exists de abajo evita que un ambito que nunca captura
      -- 'residuo_total_kg' (p.ej. Colombia) reciba una cuarta "parte" en kg=0
      select replace(replace(km.magnitud_id, 'residuo_', ''), '_kg', '') as parte,
             coalesce(sum(k.kg), 0) as kg,
             case when coalesce((select sum(lbp) from lentes), 0) = 0 then null
                  else coalesce(sum(k.kg), 0) * 1000 / (select sum(lbp) from lentes) end as g_lente,
             case when coalesce((select sum(kg) from kg), 0) = 0 then null
                  else coalesce(sum(k.kg), 0) / (select sum(kg) from kg) end as part
        from ref.kpi_magnitud km
        join ref.dim_magnitud g on g.magnitud_id = km.magnitud_id
        left join kg k on k.magnitud_id = km.magnitud_id
       where km.kpi_id = 'residuos_por_lente' and km.rol = 'numerador'
         and exists (select 1 from kg k2 where k2.magnitud_id = km.magnitud_id)
       group by km.magnitud_id, g.orden
       order by g.orden`,
      [anio, ctx.corte, ambito]
    );

    const porMes = new Map();
    for (const f of largo) {
      let fila = porMes.get(f.mes);
      if (!fila) {
        fila = {
          mes: f.mes,
          nombre_mes: f.nombre_mes,
          lentes: num(f.lentes),
          suma_kg: num(f.suma_kg),
          suma_g_lente: num(f.suma_g_lente),
        };
        porMes.set(f.mes, fila);
      }
      fila[f.parte + '_kg'] = num(f.kg);
      fila[f.parte + '_g_lente'] = num(f.g_lente);
      fila[f.parte + '_part'] = num(f.part);
    }

    return {
      ...cabecera(ctx),
      ambito: { id: ambito, nombre: general.nombre },
      partes: acumulado.map((a) => a.parte),
      meses: [...porMes.values()],
      acumulado: acumulado.map((a) => ({
        parte: a.parte,
        kg: num(a.kg),
        g_lente: num(a.g_lente),
        part: num(a.part),
      })),
    };
  },

  /**
   * La trayectoria del KPI en el scorecard corporativo: 2024 (regla del area)
   * en adelante, meta y real. El cierre del anio en curso todavia no existe y
   * no se inventa: se devuelve aparte el YTD al corte, rotulado como lo que es.
   */
  async trayectoriaAnual({ kpi, ambito = 'nacional' }) {
    const ctx = await contexto();

    const { rows: defRows } = await consulta(
      `select k.kpi, k.unidad, k.formato,
              (select s.nombre_corporativo from ref.dim_sitio s where s.sitio_id = $2) as perimetro
         from ref.dim_kpi k
        where k.kpi_id = $1 and k.area = 'ehs'`,
      [kpi, ambito]
    );
    const def = defRows[0];

    const { rows: anios } = await consulta(
      `select sc.anio, sc.meta, sc.real_ytd
         from ehs.scorecard_anual sc
        where sc.sitio_id = $1 and sc.kpi_id = $2 and sc.anio >= 2024
        order by sc.anio`,
      [ambito, kpi]
    );
    if (!def || !anios.length) return null;

    const { rows: cursoRows } = await consulta(
      `with ytd as (
          select v.kpi_id, ${VALOR_RECUPERADO} as valor
            from ehs.v_kpi_ytd v
            join ref.dim_kpi k on k.kpi_id = v.kpi_id
           where v.anio = $1 and v.ambito_id = $3 and v.num_mes_corte = $2 and v.kpi_id = $4
      )
      select y.valor as ytd,
             mt.valor as meta,
             ${estadoSql('mt.valor', 'y.valor')} as estado,
             ${nombreAmbitoSql('$3')} as ambito
        from ytd y
        -- la barra del ano en curso se mide contra la meta vigente del MISMO
        -- ambito, igual que los cierres historicos de esta misma grafica
        left join ehs.meta mt
               on mt.anio = $1 and mt.vigente and mt.ambito_id = $3 and mt.kpi_id = y.kpi_id`,
      [ctx.anio, ctx.corte, ambito, kpi]
    );
    const curso = cursoRows[0];

    return {
      ...cabecera(ctx),
      kpi_id: kpi,
      kpi: def.kpi,
      unidad: def.unidad,
      dec: decimales(def.formato),
      perimetro: def.perimetro,
      anios: anios.map((a) => ({
        anio: a.anio,
        meta: num(a.meta),
        real: num(a.real_ytd),
        cerrado: a.real_ytd !== null,
      })),
      en_curso: curso
        ? {
            anio: ctx.anio,
            hasta_mes: ctx.corte,
            hasta: ctx.corteNombre,
            ytd: num(curso.ytd),
            meta: num(curso.meta),
            estado: curso.estado,
            ambito: curso.ambito,
          }
        : null,
    };
  },

  /**
   * Contraste mes a mes entre dos anios elegidos, para el mismo ambito y KPI.
   * No se inventa el mes que todavia no tiene lectura: si un anio no llega
   * hasta diciembre, esos meses quedan null.
   */
  async contrasteMensual({ ambito, kpi, anioA, anioB }) {
    const { rows: filas } = await consulta(
      `with meses as (
          select distinct num_mes, mes as nombre_mes from ref.dim_fecha
      )
      select mes.num_mes, mes.nombre_mes, anios.anio,
             case when mm.valor is null then null else round(mm.valor::numeric, 6) end as mensual,
             case when yy.valor is null then null else round(yy.valor::numeric, 6) end as ytd
        from meses mes
       cross join (values ($3::smallint), ($4::smallint)) as anios(anio)
        left join ehs.v_kpi_mensual mm
               on mm.anio = anios.anio and mm.num_mes = mes.num_mes
              and mm.ambito_id = $1 and mm.kpi_id = $2
        left join ehs.v_kpi_ytd yy
               on yy.anio = anios.anio and yy.num_mes_corte = mes.num_mes
              and yy.ambito_id = $1 and yy.kpi_id = $2
       order by mes.num_mes, anios.anio`,
      [ambito, kpi, anioA, anioB]
    );

    const { rows: defRows } = await consulta(
      `select k.kpi, k.unidad, k.formato from ref.dim_kpi k where k.kpi_id = $1 and k.area = 'ehs'`,
      [kpi]
    );
    const def = defRows[0];
    if (!def) return null;

    const porMes = new Map();
    for (const f of filas) {
      if (!porMes.has(f.num_mes))
        porMes.set(f.num_mes, { mes: f.num_mes, nombre_mes: f.nombre_mes });
      const fila = porMes.get(f.num_mes);
      const sufijo = f.anio === anioA ? 'A' : 'B';
      const valor = num(f.mensual);
      fila['valor' + sufijo] = valor;
      /* ehs.v_kpi_ytd no sabe cual es "el corte": para un anio que solo capturo
         hasta julio, sigue publicando un YTD para agosto..diciembre (el mismo
         acumulado de julio, repetido) porque matematicamente nada nuevo se
         sumo. Aqui se recorta a null en cuanto el mes ya no tiene su propio
         valor mensual. */
      fila['ytd' + sufijo] = valor === null ? null : num(f.ytd);
    }

    return {
      ambito,
      kpi_id: kpi,
      kpi: def.kpi,
      unidad: def.unidad,
      dec: decimales(def.formato),
      anioA,
      anioB,
      meses: [...porMes.values()].sort((a, b) => a.mes - b.mes),
    };
  },

  /** Que mes trae lectura, cuantas y de que origen. */
  async calidadDato({ anio }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { rows: resumenRows } = await consulta(
      `select count(*) as lecturas,
              case when count(distinct l.estado) = 1 then min(l.estado) else 'mixto' end as estado
         from ehs.hecho_lectura_mensual l
         join ref.dim_fecha f on f.fecha = l.fecha
        where f.anio = $1 and f.num_mes <= $2`,
      [anio, ctx.corte]
    );
    const resumen = resumenRows[0] || {};

    const { rows: porMes } = await consulta(
      `select f.num_mes as mes,
              count(distinct l.sitio_id) as sitios,
              count(distinct l.magnitud_id) as magnitudes,
              count(*) as lecturas
         from ehs.hecho_lectura_mensual l
         join ref.dim_fecha f on f.fecha = l.fecha
        where f.anio = $1 and f.num_mes <= $2
        group by f.num_mes
        order by f.num_mes`,
      [anio, ctx.corte]
    );

    const { rows: diariaRows } = await consulta(`select filas from ehs.v_estado_agua_diaria`);
    const diaria = diariaRows[0] || {};

    const { rows: avisos } = await consulta(
      `with valores as (
            select f.num_mes as mes, s.sitio_id,
                   -- el aviso nombra al sitio como lo hace el reporte: su id capitalizado
                   upper(left(s.sitio_id, 1)) || substr(s.sitio_id, 2, 40) as sitio,
                   l.magnitud_id, g.orden,
                   l.valor::float8 as valor,
                   lag(l.valor::float8) over (partition by s.sitio_id, l.magnitud_id
                                               order by f.num_mes) as valor_anterior,
                   lag(f.num_mes) over (partition by s.sitio_id, l.magnitud_id
                                         order by f.num_mes) as mes_anterior
              from ehs.hecho_lectura_mensual l
              join ref.dim_fecha f on f.fecha = l.fecha
              join ref.dim_sitio s on s.sitio_id = l.sitio_id and s.activo and s.en_nacional
              join ref.dim_magnitud g on g.magnitud_id = l.magnitud_id and g.area = 'ehs'
             where f.anio = $1 and f.num_mes <= $2
        ),
        avisos as (
            select 0 as rango, 0 as paso, orden, 'error' as gravedad, 'valor_negativo' as codigo,
                   mes, sitio_id, magnitud_id,
                   concat(sitio, ', mes ', mes, ': ', magnitud_id, ' viene en ', ${comoTexto('valor')},
                          ', y esta magnitud no puede ser negativa.') as mensaje
              from valores
             where valor < 0
            union all
            -- horas_temp tambien divide, pero un sitio sin personal temporal
            -- reporta cero con toda razon: solo avisa el denominador que nunca
            -- puede valer cero
            select 0, 1, orden, 'error', 'denominador_invalido',
                   mes, sitio_id, magnitud_id,
                   concat(sitio, ', mes ', mes, ': ', magnitud_id, ' en cero; los indicadores ',
                          'que dividen por esta magnitud no se pueden calcular.')
              from valores
             where valor = 0 and magnitud_id in ('unidades_buenas', 'horas_fijos')
            union all
            select 1, 0, 0, 'error', 'mes_incompleto',
                   f.num_mes, s.sitio_id, null::varchar(40),
                   concat(upper(left(s.sitio_id, 1)) || substr(s.sitio_id, 2, 40),
                          ' no reporto el mes ', f.num_mes,
                          ', pero otros sitios si. El consolidado de ese mes queda sesgado.')
              from ref.dim_fecha f
             cross join ref.dim_sitio s
             where f.anio = $1 and f.num_mes <= $2
               and s.activo and s.en_nacional
               and exists (select 1 from valores v where v.mes = f.num_mes)
               and not exists (select 1 from valores v
                                where v.mes = f.num_mes and v.sitio_id = s.sitio_id)
            union all
            -- nullif protege el cero: sin el, las horas de temporales en cero
            -- reventarian la consulta con division por cero antes de llegar al filtro
            select 2, 0, orden, 'aviso', 'salto_atipico',
                   mes, sitio_id, magnitud_id,
                   concat(sitio, ', mes ', mes, ': ', magnitud_id, ' paso de ',
                          ${comoTexto('valor_anterior')}, ' (mes ', mes_anterior, ') a ',
                          ${comoTexto('valor')}, ' (',
                          case when valor > valor_anterior then '+' else '' end,
                          round(((valor - valor_anterior) / nullif(valor_anterior, 0) * 100)::numeric)::int,
                          '%). Conviene confirmar el dato.')
              from valores
             where valor_anterior is not null and valor_anterior <> 0
               -- pasar de 0 a 1 accidente es lo esperado, no una anomalia de captura
               and magnitud_id <> 'accidentes_dafw'
               and abs((valor - valor_anterior) / nullif(valor_anterior, 0)) > 0.4
        )
        -- avisos.mes es num_mes, no una fecha: se reconstruye para el join contra
        -- ehs.aviso_confirmado, que guarda fecha, no anio+mes sueltos.
        select av.gravedad, av.codigo, av.mes, av.sitio_id, av.magnitud_id, av.mensaje,
               case when ac.fecha is not null then 1 else 0 end as confirmado,
               ac.confirmado_por, ac.confirmado_en, ac.nota as nota_confirmacion
          from avisos av
          left join ehs.aviso_confirmado ac
            on ac.fecha = make_date($1::int, av.mes::int, 1)
           and ac.sitio_id = av.sitio_id
           and ac.magnitud_id = av.magnitud_id
           and ac.codigo = av.codigo
         order by av.mes, av.sitio_id, av.rango, av.orden, av.paso`,
      [anio, ctx.corte]
    );

    const m = metadatos();

    return {
      ...cabecera(ctx),
      lecturas: resumen.lecturas,
      meses_con_dato: ctx.mesesConDato,
      por_mes: porMes.map((x) => ({
        mes: x.mes,
        sitios: x.sitios,
        magnitudes: x.magnitudes,
        lecturas: x.lecturas,
      })),
      origen: m.origen,
      estado: resumen.estado,
      lecturas_diarias: diaria.filas ?? 0,
      hallazgos: m.hallazgos,
      // a diferencia de "hallazgos" (defectos puntuales del libro heredado,
      // escritos a mano), esto se recalcula en cada corte: valores negativos,
      // denominadores en cero, meses sin un sitio y saltos atipicos mes a mes.
      avisos_automaticos: avisos.map((a) => {
        const salida = { gravedad: a.gravedad, codigo: a.codigo, mes: a.mes, sitio: a.sitio_id };
        if (a.magnitud_id) salida.metrica = a.magnitud_id;
        salida.mensaje = a.mensaje;
        salida.confirmado = Boolean(a.confirmado);
        if (a.confirmado) {
          salida.confirmadoPor = a.confirmado_por;
          salida.confirmadoEn = new Date(a.confirmado_en).toISOString().slice(0, 19);
          if (a.nota_confirmacion) salida.nota = a.nota_confirmacion;
        }
        return salida;
      }),
    };
  },

  /** El crudo exportable: las magnitudes tal como se capturaron. */
  async detalle({ anio }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { rows: magnitudes } = await consulta(
      `select magnitud_id from ref.dim_magnitud where area = 'ehs' order by orden`
    );
    const columnas = magnitudes.map((x) => x.magnitud_id);

    const { rows: lecturas } = await consulta(
      `select l.sitio_id as sitio,
              f.anio::varchar(4) as anio,
              f.num_mes::varchar(2) as mes,
              f.num_mes as num_mes,
              l.magnitud_id,
              l.valor::float8 as valor
         from ehs.hecho_lectura_mensual l
         join ref.dim_fecha f on f.fecha = l.fecha
         join ref.dim_magnitud g on g.magnitud_id = l.magnitud_id and g.area = 'ehs'
        where f.anio = $1 and f.num_mes <= $2
        order by l.sitio_id, f.num_mes, g.orden`,
      [anio, ctx.corte]
    );

    const filas = [];
    const porClave = new Map();
    for (const l of lecturas) {
      const clave = `${l.sitio}|${l.num_mes}`;
      let fila = porClave.get(clave);
      if (!fila) {
        // una magnitud sin captura es la AUSENCIA de la lectura y se publica
        // como null: un cero seria decir que se midio y dio cero
        fila = { anio: l.anio, mes: l.mes, sitio: l.sitio };
        for (const c of columnas) fila[c] = null;
        porClave.set(clave, fila);
        filas.push(fila);
      }
      fila[l.magnitud_id] = num(l.valor);
    }

    return { ...cabecera(ctx), filas };
  },

  /**
   * Los datos detras de las graficas, para la vista "Datos" del tablero. No
   * calcula nada nuevo: pone a la vista de donde sale cada numero.
   */
  async datosTabulados({ anio, ambito }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { rows: nombreRows } = await consulta(`select ${nombreAmbitoSql('$1')} as nombre`, [
      ambito,
    ]);
    const def = nombreRows[0];

    const { rows: sitios } = await consulta(
      `select a.sitio_id, s.sitio
         from ehs.v_ambito a
         join ref.dim_sitio s on s.sitio_id = a.sitio_id
        where a.ambito_id = $1
        order by a.sitio_id`,
      [ambito]
    );

    const { rows: magnitudes } = await consulta(
      `select magnitud_id, magnitud, unidad
         from ref.dim_magnitud where area = 'ehs' order by orden`
    );

    const { rows: kpis } = await consulta(
      `select k.kpi_id, k.kpi, k.unidad, k.formato, k.factor::float8 as factor
         from ref.dim_kpi k where k.area = 'ehs' order by k.orden`
    );

    const { rows: mapa } = await consulta(
      `select km.kpi_id, km.magnitud_id, km.rol
         from ref.kpi_magnitud km
         join ref.dim_kpi k on k.kpi_id = km.kpi_id and k.area = 'ehs'`
    );

    const { rows: lecturas } = await consulta(
      `select la.num_mes, la.magnitud_id,
              sum(la.valor)::float8 as valor, count(*) as lecturas
         from ehs.v_lectura_ambito la
        where la.anio = $1 and la.ambito_id = $2 and la.num_mes <= $3
        group by la.num_mes, la.magnitud_id`,
      [anio, ambito, ctx.corte]
    );
    if (!def || !lecturas.length) return null;

    const { rows: valores } = await consulta(
      `select m.num_mes, m.kpi_id,
              m.numerador::float8 as numerador,
              m.denominador::float8 as denominador,
              round(m.valor::numeric, 6)::float8 as valor,
              y.numerador::float8 as ytd_numerador,
              y.denominador::float8 as ytd_denominador,
              round(y.valor::numeric, 6)::float8 as ytd
         from ehs.v_kpi_mensual m
         left join ehs.v_kpi_ytd y
                on y.anio = m.anio and y.num_mes_corte = m.num_mes
               and y.ambito_id = m.ambito_id and y.kpi_id = m.kpi_id
        where m.anio = $1 and m.ambito_id = $2 and m.num_mes <= $3`,
      [anio, ambito, ctx.corte]
    );

    const { rows: metas } = await consulta(
      `select mt.kpi_id, mt.valor::float8 as valor, mt.fuente, mt.vigente
         from ehs.meta mt
        where mt.anio = $1 and mt.ambito_id = $2
        order by mt.kpi_id, mt.vigente desc, mt.fuente`,
      [anio, ambito]
    );

    const { rows: historico } = await consulta(
      `select sc.kpi_id, sc.anio,
              sc.meta::float8 as meta, sc.real_ytd::float8 as real,
              ${brechaSql('sc.meta', 'sc.real_ytd')}::float8 as brecha_pct,
              ${estadoSql('sc.meta', 'sc.real_ytd')} as estado,
              true as cerrado
         from ehs.scorecard_anual sc
        where sc.sitio_id = $1 and sc.anio >= 2024 and sc.anio < $2
       union all
       select y.kpi_id, $2 as anio,
              mt.valor::float8 as meta, round(y.valor::numeric, 6)::float8 as real,
              ${brechaSql('mt.valor', 'y.valor')}::float8 as brecha_pct,
              ${estadoSql('mt.valor', 'y.valor')} as estado,
              false as cerrado
         from ehs.v_kpi_ytd y
         left join ehs.meta mt
                on mt.anio = $2 and mt.vigente and mt.ambito_id = $1 and mt.kpi_id = y.kpi_id
        where y.anio = $2 and y.ambito_id = $1 and y.num_mes_corte = $3
       order by kpi_id, anio`,
      [ambito, anio, ctx.corte]
    );

    const meses = new Map();
    const mesDe = (n) => {
      if (!meses.has(n)) meses.set(n, { mes: n, lecturas: {}, sitiosConLectura: {}, kpis: {} });
      return meses.get(n);
    };
    for (const l of lecturas) {
      const mesRow = mesDe(l.num_mes);
      mesRow.lecturas[l.magnitud_id] = num(l.valor);
      mesRow.sitiosConLectura[l.magnitud_id] = l.lecturas;
    }
    for (const v of valores) {
      mesDe(v.num_mes).kpis[v.kpi_id] = {
        numerador: num(v.numerador),
        denominador: num(v.denominador),
        valor: num(v.valor),
        ytd_numerador: num(v.ytd_numerador),
        ytd_denominador: num(v.ytd_denominador),
        ytd: num(v.ytd),
      };
    }

    return {
      ...cabecera(ctx),
      ambito: {
        id: ambito,
        nombre: def.nombre,
        sitios: sitios.map((s) => ({ id: s.sitio_id, nombre: s.sitio })),
      },
      magnitudes: magnitudes.map((g) => ({
        id: g.magnitud_id,
        nombre: g.magnitud,
        unidad: g.unidad,
      })),
      kpis: kpis.map((k) => ({
        id: k.kpi_id,
        nombre: k.kpi,
        unidad: k.unidad,
        dec: decimales(k.formato),
        factor: num(k.factor),
        numerador: mapa
          .filter((x) => x.kpi_id === k.kpi_id && x.rol === 'numerador')
          .map((x) => x.magnitud_id),
        denominador: mapa
          .filter((x) => x.kpi_id === k.kpi_id && x.rol === 'denominador')
          .map((x) => x.magnitud_id),
        metas: metas
          .filter((mt) => mt.kpi_id === k.kpi_id)
          .map((mt) => ({ valor: num(mt.valor), fuente: mt.fuente, vigente: Boolean(mt.vigente) })),
        historico: historico
          .filter((h) => h.kpi_id === k.kpi_id)
          .map((h) => ({
            anio: h.anio,
            meta: num(h.meta),
            real: num(h.real),
            brecha_pct: num(h.brecha_pct),
            estado: h.estado,
            cerrado: Boolean(h.cerrado),
          })),
      })),
      meses: [...meses.values()].sort((a, b) => a.mes - b.mes),
    };
  },

  /**
   * Lo que la franja de estado necesita: si el motor responde, y en cuanto.
   * No pasa por contexto()/consulta() de la manera habitual: aqui el fallo ES
   * la respuesta que se quiere mostrar, asi que se atrapa aqui mismo.
   */
  async salud() {
    const inicio = Date.now();
    const { fechaUltimoRespaldo } = require('../respaldo');
    const ultimoRespaldo = fechaUltimoRespaldo();
    try {
      await consulta('select 1 as ok');
      const ctx = await contexto();
      return {
        modo: 'sql',
        motor: 'arriba',
        disponible: true,
        tardoMs: Date.now() - inicio,
        corte: { mes: ctx.corte, anio: ctx.anio },
        ultimoRespaldo,
      };
    } catch (err) {
      // 'pg' no tiene una clase ConnectionError como 'mssql': un motor
      // inalcanzable llega como un error de red de Node (ECONNREFUSED,
      // ENOTFOUND, ETIMEDOUT) o con el SQLSTATE de clase 08 (connection
      // exception) de Postgres.
      const esConexion =
        ['ECONNREFUSED', 'ENOTFOUND', 'ETIMEDOUT', 'EHOSTUNREACH'].includes(err.code) ||
        (typeof err.code === 'string' && err.code.startsWith('08'));
      return {
        modo: 'sql',
        motor: 'abajo',
        disponible: false,
        tardoMs: Date.now() - inicio,
        ultimoRespaldo,
        mensaje: esConexion ? 'No se pudo conectar al motor de base de datos.' : err.message,
      };
    }
  },
};

/* =============================================================================
   FUNCIONES PORTADAS (todas las de module.exports de adaptador_sql.js; es el
   alcance completo de esta tarea — capturarLote/estadoCaptura/corregirLectura/
   confirmarAviso/historialCorrecciones viven en escritura_sql.js, que esta
   tarea pidio LEER para entender el modelo de conexion y permisos, pero no
   portar: no hay un "escritura_pg.js" en el encargo)
   -----------------------------------------------------------------------------
   panorama, kpiPorSitio, serieMensual, aguaMensual, energiaMensual, aguaDiaria,
   residuosComposicion, trayectoriaAnual, contrasteMensual, calidadDato,
   detalle, datosTabulados, salud.
   Internas (no exportadas en el original tampoco): metadatos, decimales,
   contexto, cabecera, correccionesDelAmbito, alCorte, hojaMensualRecurso.

   DUDAS REALES SIN RESOLVER (no se inventa comportamiento donde el original
   no es claro)
   -----------------------------------------------------------------------------
   1. Tablas variable -> CTE repetida, no tabla temporal. VALORES_DEL_AMBITO
      (@ytd/@mensual) y el par @kg/@lentes de residuosComposicion se portaron
      como una CTE de texto (cteYtdMensual / cteKgLentes) que se REPITE en cada
      consulta separada que la necesita, en vez de una tabla temporal real.
      Es deliberado (ver el comentario del encabezado: pool.query() de 'pg' no
      garantiza la misma conexion entre dos llamadas sucesivas, así que una
      tabla temporal real se podria crear en una conexion y consultarse desde
      otra), pero significa que cada funcion que antes era "1 round-trip con 2-4
      recordsets" ahora es "N round-trips", repitiendo el calculo de la CTE en
      cada uno. Funcionalmente equivalente; mas lento bajo carga alta — no se
      midio contra un volumen real de Neon.
   2. nombreAmbitoSql(): el ORDER BY ... LIMIT 1 original (top 1 ... order by
      a.sitio_id) asume que a lo sumo puede haber mas de una fila cuando
      ambito_id = ambito "propio" de un sitio (nunca pasa, es 1 a 1) y que para
      un agregado real basta cualquier sitio miembro para resolver el nombre
      del agregado (todas las filas de ese ambito_id comparten el mismo
      'a.ambito'). Se tradujo literal; no se revisito esa suposicion porque ya
      era asi en el original.
   3. contexto(): la expresion meta_vigente usa `$1::text` para concatenar el
      anio (smallint) dentro de un string. Se asumio que el casteo smallint ->
      text de Postgres no necesita formato especial (el original usaba
      cast(@anio as nvarchar(4)), que tampoco tenia relleno); no se probo
      contra una fila real con anio de 4 digitos distinto a 2026.
   4. calidadDato(): el calculo del aviso 'salto_atipico' usa
      round(x::numeric)::int para el porcentaje (equivalente de
      cast(round(x,0) as int) en T-SQL). round(numeric) sin segundo argumento
      redondea al entero mas cercano igual que round(numeric,0); no se verifico
      el comportamiento exacto en el caso extremo x = n.5 (bancaria vs. "half
      away from zero") contra una fila real de SQL Server para los mismos
      datos — ambos motores documentan "round half away from zero" para
      numeric, asi que deberian coincidir, pero no se corrio la comparacion.
   5. detalle()/datosTabulados(): l.valor::float8 y sum(la.valor)::float8 asumen
      que ehs.hecho_lectura_mensual.valor y ehs.v_lectura_ambito.valor son
      numeric (lo son, segun postgres/01_esquema.sql) — igual que el original
      hacia cast(... as float). Sin cambios de comportamiento esperados.
   6. salud(): la deteccion de "motor abajo" por codigo de error (ECONNREFUSED/
      ENOTFOUND/ETIMEDOUT/EHOSTUNREACH o SQLSTATE clase 08) es una aproximacion
      razonable al "err.name === 'ConnectionError'" que usaba 'mssql', pero no
      se probo contra una caida real de un Neon (p. ej. el proyecto pausado
      por inactividad del free tier, que puede tardar varios segundos en
      "despertar" en vez de fallar de inmediato) — vale la pena confirmarlo con
      el proyecto Neon real antes de confiar en el mensaje "No se pudo
      conectar" para ese caso particular.
   7. No se tocaron ni se portaron escritura_sql.js (capturarLote y las otras
      cuatro funciones de escritura) ni conexion_sql.js en si: siguen intactos.
      El modelo de permisos de DOS roles (ehs_app via SQL_USUARIO/SQL_CLAVE,
      ehs_migrador via SQL_MIGRADOR_USUARIO/SQL_MIGRADOR_CLAVE) se preservo en
      conexion_pg.js via el mismo parametro 'prefijoUsuario', pero
      adaptador_pg.js (como adaptador_sql.js) solo usa el prefijo por defecto
      ('SQL' -> ehs_app): es correcto, porque la lectura del tablero nunca
      necesito el migrador en el original tampoco.
   ============================================================================= */
