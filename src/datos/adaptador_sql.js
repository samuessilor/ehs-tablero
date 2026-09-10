/**
 * Adaptador SQL — el destino. Mismas nueve firmas que adaptador_json.js.
 *
 * Cada funcion consulta las vistas del esquema ehs (app/sql/02-vistas.sql), que
 * implementan las dos reglas del area una sola vez. Aqui no se calcula ningun
 * indicador (R.5.2.1): lo que no sale de una vista sale de una agregacion SQL, y lo
 * unico que hace JavaScript es dar forma a la respuesta.
 *
 * Correspondencia funcion -> vista:
 *   panorama            -> ehs.v_kpi_ytd + ehs.v_kpi_mensual + ehs.meta
 *   kpiPorSitio         -> ehs.v_kpi_ytd por sitio + ehs.meta de cada sitio
 *   serieMensual        -> ehs.v_kpi_mensual + ehs.v_kpi_ytd
 *   aguaMensual         -> ehs.v_lectura_ambito, con las variaciones por lag()
 *   aguaDiaria          -> ehs.v_agua_diaria + ehs.v_estado_agua_diaria
 *   residuosComposicion -> ehs.v_lectura_ambito agregado por magnitud de residuo
 *   trayectoriaAnual    -> ehs.scorecard_anual del perimetro consolidado
 *   calidadDato         -> ehs.hecho_lectura_mensual + ehs.v_estado_agua_diaria
 *   detalle             -> ehs.hecho_lectura_mensual (solo lectura)
 *
 * DONDE ESTE MODULO NO SE APOYA EN LA VISTA QUE LE CORRESPONDIA, Y POR QUE.
 *
 * Al escribir este adaptador aparecieron tres divergencias entre las vistas y el
 * contrato publicado. Dos eran defectos de las vistas y se corrigieron alli, que es
 * donde tenian que corregirse; queda una, y no es tecnica.
 *
 *   1. RESUELTO. v_kpi_mensual y v_kpi_ytd truncaban el sexto decimal de la division
 *      donde el motor validado redondea: 4 de 350 valores del corte de julio caian al
 *      otro lado del cuarto decimal. Corregido con un cast en app/sql/02-vistas.sql, y
 *      el rodeo que este adaptador llevaba se retiro.
 *
 *   2. ABIERTO, Y LO DECIDE EHS, NO EL CODIGO. v_kpi_contra_meta rotula 'cumple' /
 *      'en riesgo' / 'incumple' / 'sin meta' con una banda de +5 % SOBRE la meta; el
 *      contrato publicado (analisis/web_json.py, estado_de) rotula 'cumple' / 'riesgo' /
 *      'incumple' / 'sin_meta' / 'sin_dato' con una banda del 90 % POR DEBAJO. No son
 *      dos escrituras de la misma regla: son dos reglas, y un valor entre el 90 % y el
 *      100 % de la meta sale 'riesgo' en una y 'cumple' en la otra. Aqui manda el
 *      contrato porque es lo que el area ve hoy. En cuanto EHS diga cual vale, la que
 *      sobre se borra y esta nota con ella.
 *
 *   3. RESUELTO. v_calidad_avisos no se podia consultar: dividia entre valor_anterior
 *      sin proteger el cero y reventaba con "Divide by zero" en cuanto una magnitud
 *      valia 0 —las horas de temporales de Celta y La Estrella, todos los meses—.
 *      Ademas denunciaba 14 meses incompletos que no existian: contaba 'peru' y
 *      'colombia_peru', que solo alimentan el scorecard anual. Las dos cosas se
 *      corrigieron en la vista. Lo que este modulo sigue haciendo suyo es el TEXTO del
 *      aviso: la vista nombra el sitio por su id y publica magnitud_id donde el
 *      contrato publica metrica. Es forma, no calculo — el que decide que es un salto
 *      atipico es la vista.
 *
 * METADATOS DEL PROYECTO. Los hallazgos del libro heredado, las correcciones
 * autorizadas y el rotulo del archivo del que salio la captura no son dato operativo:
 * describen el informe, se escriben a mano y no tienen tabla porque no la necesitan.
 * Viven en app/datos/datos.json, el manifiesto del corte publicado, y de ahi los lee
 * este adaptador para que las dos rutas cuenten la misma historia sobre el mismo corte.
 *
 * La excepcion es actualizado_en, que SI sale de la base. Describe cuando cambio el
 * DATO, no cuando se escribio el informe, y leerlo del manifiesto hacia que el tablero
 * dijera "corte agosto" junto a una fecha anterior a la captura que lo habia movido.
 * Es el unico campo de la cabecera que puede diferir legitimamente entre los dos
 * adaptadores, y comparar_adaptadores.py lo excluye de la comparacion por eso.
 */
const fs = require('fs');
const path = require('path');
const { cargarDriver, pool } = require('./conexion_sql');

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

/** Un numero, nunca la cadena con la que el driver a veces devuelve un decimal. */
const num = (v) => (v === null || v === undefined ? null : Number(v));

/**
 * Cuantos decimales publica cada KPI. El JSON lo trae dado; en SQL se lee del formato
 * de presentacion de dim_kpi, que es donde el modelo guarda esa decision: '0.000' son
 * tres decimales, '0.0' uno y '0' ninguno.
 */
function decimales(formato) {
  const f = String(formato || '');
  const punto = f.indexOf('.');
  return punto === -1 ? 0 : f.length - punto - 1;
}

/**
 * De donde saca su meta cada ambito. Reproduce AMBITO_META de analisis/web_json.py:
 * cada sitio usa la suya; el consolidado nacional toma PRESTADA la del perimetro
 * corporativo COLOMBIA y PERU —y por eso se marca es_referencia—; y Nacional Labs no
 * tiene meta y no hereda ninguna, porque el scorecard no publica objetivo para ese
 * subconjunto y heredar el del consolidado seria inventarlo.
 */
const META_DE_AMBITO = {
  celta: 'celta',
  estrella: 'estrella',
  agencias: 'agencias',
  nacional: 'colombia_peru',
  nacional_labs: null,
};

/* El valor tal como lo publica la vista.
 *
 * Aqui hubo un rodeo y ya no hace falta. v_kpi_mensual y v_kpi_ytd truncaban el sexto
 * decimal de la division donde el motor redondea, y este adaptador rehacia la ultima
 * division para recuperarlo. El defecto se corrigio donde vivia —un cast en
 * app/sql/02-vistas.sql— asi que el rodeo se retiro: mantenerlo seria conservar una
 * segunda forma de calcular el indicador esperando a divergir de la primera.
 *
 * Queda el round(,6) porque el motor validado publica seis decimales y la igualdad se
 * comprueba contra el, no contra la precision maxima del tipo. */
const VALOR_RECUPERADO = `case when v.valor is null then null
                               else round(v.valor, 6) end`;

/**
 * La brecha y el semaforo, tal como los define el contrato publicado. Van en SQL y no
 * en JavaScript para que el adaptador no sea una segunda implementacion del calculo.
 * `y` trae el valor acumulado y `mt` la meta del ambito.
 */
const BRECHA = `case when mt.valor is null or mt.valor = 0 or y.valor is null then null
                          else round((y.valor - mt.valor) / mt.valor, 6) end`;
const ESTADO = `case when mt.valor is null then 'sin_meta'
                          when mt.valor = 0 then case when coalesce(y.valor, 0) <= 0
                                                      then 'cumple' else 'incumple' end
                          when y.valor is null then 'sin_dato'
                          when y.valor > mt.valor then 'incumple'
                          when y.valor >= mt.valor * 0.90 then 'riesgo'
                          else 'cumple' end`;

/** El nombre largo del ambito: el del sitio si lo es, y el del agregado si no. */
const NOMBRE_AMBITO = `(select top 1 case when a.ambito_id = a.sitio_id then s.sitio else a.ambito end
                          from ehs.v_ambito a
                          join ehs.dim_sitio s on s.sitio_id = a.sitio_id
                         where a.ambito_id = @ambito
                         order by a.sitio_id)`;

/**
 * Los valores del ambito, ya recuperados, en dos tablas que el resto del lote reusa.
 * Se materializan aqui porque un CTE solo vive para la sentencia siguiente y estas
 * consultas devuelven varios recordsets.
 *
 * Nada pasa del corte publicado: v_kpi_ytd repite el ultimo acumulado hasta diciembre,
 * y un mes a medias que ya estuviera capturandose no es un mes del informe.
 */
const VALORES_DEL_AMBITO = `
    declare @ytd table (kpi_id varchar(40) not null, num_mes tinyint not null,
                        valor decimal(38,6) null, primary key (kpi_id, num_mes));
    declare @mensual table (kpi_id varchar(40) not null, num_mes tinyint not null,
                            valor decimal(38,6) null, primary key (kpi_id, num_mes));

    insert @ytd (kpi_id, num_mes, valor)
    select v.kpi_id, v.num_mes_corte, ${VALOR_RECUPERADO}
      from ehs.v_kpi_ytd v
      join ehs.dim_kpi k on k.kpi_id = v.kpi_id
     where v.anio = @anio and v.ambito_id = @ambito and v.num_mes_corte <= @corte;

    insert @mensual (kpi_id, num_mes, valor)
    select v.kpi_id, v.num_mes, ${VALOR_RECUPERADO}
      from ehs.v_kpi_mensual v
      join ehs.dim_kpi k on k.kpi_id = v.kpi_id
     where v.anio = @anio and v.ambito_id = @ambito and v.num_mes <= @corte;
`;

/**
 * El valor tal como lo escribe un humano: 800 y no 800.0000, 979.1 y no 979.1000. Lo
 * necesitan los mensajes de aviso, que citan la lectura dentro de una frase.
 */
const comoTexto = (
  c
) => `case when ${c} = floor(${c}) then convert(varchar(30), convert(bigint, ${c}))
                                      else convert(varchar(30), convert(float, ${c})) end`;

async function peticion() {
  const sql = cargarDriver();
  const p = await pool();
  return { sql, req: p.request() };
}

/**
 * El corte publicado: que anio y hasta que mes hay dato COMPLETO, y que juego de metas
 * esta marcado vigente. No se fija en el codigo porque el dato ya sabe cual es, y
 * fijarlo obligaria a editar el modulo cada vez que avanza el mes.
 *
 * Lo decide ehs.v_corte_publicado, no el ultimo mes que aparezca en la tabla. Mientras
 * el dato entraba en lotes mensuales completos las dos cosas coincidian; con la puerta
 * de captura dejan de coincidir el primer dia que alguien teclee cuatro numeros del mes
 * siguiente, y el tablero entero se republicaria contra un mes a medias: los YTD se
 * moverian y los estados contra meta cambiarian por un dato que todavia no esta.
 *
 * La vista tambien publica `en_curso`, el mes a medias cuando lo hay. Aqui no se expone
 * porque el contrato no lo tiene, pero es lo que necesitaria la barra de contexto del
 * tablero para decir "septiembre, 4 de 27" en vez de callarlo.
 */
async function contexto() {
  const { req } = await peticion();
  const r = await req.query(`
    declare @anio smallint = (select max(anio) from ehs.v_corte_publicado
                               where corte is not null);
    declare @corte tinyint = (select corte from ehs.v_corte_publicado where anio = @anio);
    select anio = @anio,
           corte = @corte,
           corte_nombre = (select top 1 mes from ehs.dim_fecha
                            where anio = @anio and num_mes = @corte),
           meta_vigente = (select max(fuente) from ehs.meta
                            where anio = @anio and vigente = 1),
           /* Cuando cambio por ultima vez el dato que se esta publicando.
              Sale de la base y NO del manifiesto, aunque el manifiesto traiga un
              campo con ese nombre: el manifiesto dice cuando publico el pipeline por
              ultima vez, que en modo SQL no tiene nada que ver. Con el manifiesto, el
              tablero decia "corte agosto" y "ultima actualizacion 31 de agosto" a la
              vez, con una fecha ANTERIOR a la captura que acababa de moverlo. */
           actualizado_en = (select max(coalesce(l.modificado_en, l.capturado_en))
                               from ehs.hecho_lectura_mensual l
                               join ehs.dim_fecha f on f.fecha = l.fecha
                              where f.anio = @anio and f.num_mes <= @corte);
    select num_mes = f.num_mes
      from ehs.hecho_lectura_mensual l
      join ehs.dim_fecha f on f.fecha = l.fecha
     where f.anio = @anio and f.num_mes <= @corte
     group by f.num_mes
     order by f.num_mes;
  `);
  const c = r.recordsets[0][0] || {};
  return {
    anio: c.anio ?? null,
    corte: c.corte ?? null,
    corteNombre: c.corte_nombre ?? null,
    metaVigente: c.meta_vigente ?? null,
    // el mismo formato que publica el pipeline: 'AAAA-MM-DDTHH:MM:SS', sin zona
    actualizadoEn: c.actualizado_en ? new Date(c.actualizado_en).toISOString().slice(0, 19) : null,
    mesesConDato: r.recordsets[1].map((x) => x.num_mes),
  };
}

function cabecera(ctx) {
  const m = metadatos();
  return {
    anio: ctx.anio,
    corte: { mes: ctx.corte, nombre: ctx.corteNombre, mesesConDato: ctx.mesesConDato },
    /* Del dato, no del manifiesto. Es el unico campo de la cabecera que puede
       diferir legitimamente entre los dos adaptadores, y por eso la compuerta lo
       excluye de la comparacion: describe CUANDO cambio el dato en cada sistema, no
       QUE dice el dato. El JSON publica cuando corrio el pipeline; SQL publica
       cuando se capturo por ultima vez. Las dos respuestas son correctas y son
       distintas porque las dos fuentes se alimentan distinto. */
    actualizado_en: ctx.actualizadoEn ?? m.actualizadoEn,
    fuente: m.fuente,
    meta_vigente: ctx.metaVigente,
  };
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

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, anio)
      .input('mes', sql.TinyInt, mes)
      .input('corte', sql.TinyInt, ctx.corte)
      .input('ambito', sql.VarChar(20), ambito)
      .input('ambito_meta', sql.VarChar(20), META_DE_AMBITO[ambito] ?? null).query(`
        ${VALORES_DEL_AMBITO}

        select nombre = ${NOMBRE_AMBITO},
               hay_dato = case when exists (select 1 from @mensual where num_mes = @mes)
                               then 1 else 0 end;

        select k.kpi_id, k.kpi, k.unidad, k.familia, k.formato,
               valor = y.valor,
               valor_mes = m.valor,
               meta = mt.valor,
               es_referencia = case when @ambito_meta is not null and @ambito_meta <> @ambito
                                    then 1 else 0 end,
               brecha_pct = ${BRECHA},
               estado = ${ESTADO}
          from ehs.dim_kpi k
          left join @ytd y on y.kpi_id = k.kpi_id and y.num_mes = @mes
          left join @mensual m on m.kpi_id = k.kpi_id and m.num_mes = @mes
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito_meta and mt.kpi_id = k.kpi_id
         where k.area = 'ehs'
         order by k.orden;

        -- solo los meses que alguien reporto completos: dibujar los demas seria dibujar
        -- meses que el informe no publica
        select y.kpi_id, mes = y.num_mes, y.valor,
               brecha_pct = ${BRECHA},
               estado = ${ESTADO}
          from @ytd y
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito_meta and mt.kpi_id = y.kpi_id
         where exists (select 1 from @mensual d where d.num_mes = y.num_mes)
         order by y.kpi_id, y.num_mes;
      `);

    const [[general = {}], kpis, serie] = r.recordsets;
    if (!general.hay_dato || !kpis.length) return null;

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
      correcciones: metadatos().correcciones.filter((c) => c.anio === anio),
    };
  },

  /** Cada sitio contra SU meta para un KPI. Las metas por sitio no son comparables. */
  async kpiPorSitio({ anio, mes, kpi }) {
    const ctx = await contexto();
    ({ anio, mes } = alCorte(ctx, anio, mes));
    if (anio !== ctx.anio) return null;

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, anio)
      .input('mes', sql.TinyInt, mes)
      .input('kpi', sql.VarChar(40), kpi).query(`
        declare @ytd table (ambito_id varchar(20) not null primary key,
                            valor decimal(38,6) null);
        insert @ytd (ambito_id, valor)
        select v.ambito_id, ${VALOR_RECUPERADO}
          from ehs.v_kpi_ytd v
          join ehs.dim_kpi k on k.kpi_id = v.kpi_id
          join ehs.dim_sitio s on s.sitio_id = v.ambito_id and s.activo = 1 and s.en_nacional = 1
         where v.anio = @anio and v.num_mes_corte = @mes and v.kpi_id = @kpi;

        select k.kpi, k.unidad from ehs.dim_kpi k where k.kpi_id = @kpi and k.area = 'ehs';

        select s.sitio_id, s.sitio, corporativo = s.nombre_corporativo,
               valor = y.valor,
               meta = mt.valor,
               brecha_pct = ${BRECHA},
               estado = ${ESTADO}
          from ehs.dim_sitio s
          left join @ytd y on y.ambito_id = s.sitio_id
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = s.sitio_id and mt.kpi_id = @kpi
         where s.activo = 1 and s.en_nacional = 1
         -- los dos laboratorios primero y Agencias despues: el orden del reporte del area
         order by s.en_nacional_labs desc, s.sitio_id;
      `);

    const [[def], sitios] = r.recordsets;
    if (!def) return null;

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

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, anio)
      .input('corte', sql.TinyInt, ctx.corte)
      .input('ambito', sql.VarChar(20), ambito)
      .input('ambito_meta', sql.VarChar(20), META_DE_AMBITO[ambito] ?? null)
      .input('kpi', sql.VarChar(40), kpi).query(`
        ${VALORES_DEL_AMBITO}

        select k.kpi, k.unidad, k.formato,
               nombre_ambito = ${NOMBRE_AMBITO},
               hay_serie = case when exists (select 1 from @mensual) then 1 else 0 end,
               meta = mt.valor,
               es_referencia = case when @ambito_meta is not null and @ambito_meta <> @ambito
                                    then 1 else 0 end
          from ehs.dim_kpi k
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito_meta and mt.kpi_id = k.kpi_id
         where k.kpi_id = @kpi and k.area = 'ehs';

        select mes = f.num_mes,
               valor = m.valor,
               -- el acumulado solo existe donde hay mes reportado; mas alla del corte
               -- v_kpi_ytd repite el ultimo y eso no es un dato del mes
               valor_ytd = case when exists (select 1 from @mensual d where d.num_mes = f.num_mes)
                                then y.valor end
          from ehs.dim_fecha f
          left join @mensual m on m.num_mes = f.num_mes and m.kpi_id = @kpi
          left join @ytd y on y.num_mes = f.num_mes and y.kpi_id = @kpi
         where f.anio = @anio
         order by f.num_mes;
      `);

    const [[def], meses] = r.recordsets;
    if (!def || !def.hay_serie) return null;

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

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, anio)
      .input('corte', sql.TinyInt, ctx.corte)
      .input('ambito', sql.VarChar(20), ambito).query(`
        select nombre = ${NOMBRE_AMBITO};

        -- que magnitud es el consumo y cual el denominador lo dice ehs.kpi_magnitud, que
        -- ya guarda la formula del agua como dato: repetir 'agua_m3' aqui seria una
        -- segunda copia de la misma definicion
        with mensual as (
            select f.num_mes, nombre_mes = f.mes,
                   agua = sum(case when km.rol = 'numerador' then cast(la.valor as float) end),
                   lbp  = sum(case when km.rol = 'denominador' then cast(la.valor as float) end)
              from ehs.v_lectura_ambito la
              join ehs.dim_fecha f on f.fecha = la.fecha
              join ehs.kpi_magnitud km
                on km.magnitud_id = la.magnitud_id and km.kpi_id = 'agua_por_lente'
             where la.anio = @anio and la.ambito_id = @ambito and f.num_mes <= @corte
             group by f.num_mes, f.mes
        ),
        con_previo as (
            select *,
                   agua_prev = lag(agua) over (order by num_mes),
                   lbp_prev  = lag(lbp)  over (order by num_mes),
                   mes_prev  = lag(num_mes) over (order by num_mes)
              from mensual
        )
        select mes = num_mes, nombre_mes,
               consumo_m3 = round(agua, 2),
               lentes = cast(lbp as bigint),
               l_por_lente = round(agua * 1000 / nullif(lbp, 0), 4),
               -- la variacion se mide contra el mes inmediatamente anterior; si ese mes
               -- no se reporto no hay contra que compararlo y se dice, no se salta al
               -- ultimo que haya
               var_total_pct = case when mes_prev = num_mes - 1 and agua_prev <> 0
                                    then round((agua - agua_prev) / agua_prev * 100, 2) end,
               var_por_lente_pct = case when mes_prev = num_mes - 1 and agua_prev <> 0
                                         and lbp_prev <> 0 and lbp <> 0
                                    then round((agua * 1000 / lbp - agua_prev * 1000 / lbp_prev)
                                               / (agua_prev * 1000 / lbp_prev) * 100, 2) end
          from con_previo
         order by num_mes;
      `);

    const [[general = {}], filas] = r.recordsets;

    // el reporte de agua del area publica cada sitio y el consolidado nacional; Nacional
    // Labs es un subconjunto que ese reporte no tiene, y se dice, no se inventa (R.5.5.1)
    if (ambito === 'nacional_labs' || !filas.length) {
      return {
        ...cabecera(ctx),
        ambito: { id: ambito, nombre: general.nombre },
        filas: [],
        nota: 'sin_fila_en_reporte_area',
      };
    }

    return {
      ...cabecera(ctx),
      ambito: { id: ambito, nombre: general.nombre },
      filas: filas.map((f) => ({
        mes: f.mes,
        nombre_mes: f.nombre_mes,
        consumo_m3: num(f.consumo_m3),
        lentes: num(f.lentes),
        l_por_lente: num(f.l_por_lente),
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

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, anio)
      .input('mes', sql.TinyInt, mes ?? null)
      .input('sitio', sql.VarChar(20), sitio ?? null).query(`
        select filas, estado from ehs.v_estado_agua_diaria;

        select fecha = convert(varchar(10), d.fecha, 23),
               d.sitio_id, d.sitio_corto, d.consumo_m3, d.observacion,
               d.mediana_m3, d.desviacion, d.es_pico
          from ehs.v_agua_diaria d
         where year(d.fecha) = @anio
           and (@mes is null or month(d.fecha) = @mes)
           and (@sitio is null or d.sitio_id = @sitio)
         order by d.fecha, d.sitio_id;
      `);

    const [[estado = {}], dias] = r.recordsets;
    return {
      ...cabecera(ctx),
      sitio: sitio || null,
      mes: mes || null,
      disponible: estado.filas > 0,
      // el rotulo lo decide el conteo de filas dentro de la vista, no una constante: el
      // dia que el area entregue el registro diario cambia solo
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
   * De que esta hecho el residuo: peligroso, aprovechable y ordinario, mes a mes.
   *
   * El KPI dice CUANTO; esto dice DE QUE. Las tres partes en g/lente suman exactamente
   * el KPI del mes porque comparten denominador: se suman los kilos crudos, se suman
   * los lentes, y se divide AL FINAL (regla 2 del area).
   */
  async residuosComposicion({ anio, ambito }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, anio)
      .input('corte', sql.TinyInt, ctx.corte)
      .input('ambito', sql.VarChar(20), ambito).query(`
        declare @kg table (num_mes tinyint, nombre_mes varchar(12), magnitud_id varchar(40),
                           orden tinyint, kg float);
        declare @lentes table (num_mes tinyint primary key, lbp float);

        -- cuales son las tres magnitudes de residuo y cual el denominador no se teclea:
        -- lo dice ehs.kpi_magnitud, que guarda la formula del KPI como dato
        insert @kg (num_mes, nombre_mes, magnitud_id, orden, kg)
        select f.num_mes, f.mes, la.magnitud_id, g.orden, sum(cast(la.valor as float))
          from ehs.v_lectura_ambito la
          join ehs.dim_fecha f on f.fecha = la.fecha
          join ehs.dim_magnitud g on g.magnitud_id = la.magnitud_id
          join ehs.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id
           and km.kpi_id = 'residuos_por_lente' and km.rol = 'numerador'
         where la.anio = @anio and la.ambito_id = @ambito and f.num_mes <= @corte
         group by f.num_mes, f.mes, la.magnitud_id, g.orden;

        -- solo los meses que traen residuo: un mes con lentes y sin pesaje no puede
        -- entrar al denominador del acumulado, o el g/lente del anio saldria diluido
        insert @lentes (num_mes, lbp)
        select f.num_mes, sum(cast(la.valor as float))
          from ehs.v_lectura_ambito la
          join ehs.dim_fecha f on f.fecha = la.fecha
          join ehs.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id
           and km.kpi_id = 'residuos_por_lente' and km.rol = 'denominador'
         where la.anio = @anio and la.ambito_id = @ambito and f.num_mes <= @corte
           and exists (select 1 from @kg x where x.num_mes = f.num_mes)
         group by f.num_mes;

        declare @kg_anio float  = (select sum(kg) from @kg);
        declare @lbp_anio float = (select sum(lbp) from @lentes);

        select nombre = ${NOMBRE_AMBITO};

        select mes = k.num_mes, k.nombre_mes,
               parte = replace(replace(k.magnitud_id, 'residuo_', ''), '_kg', ''),
               lentes = l.lbp,
               total_kg = t.total_kg,
               total_g_lente = case when t.total_kg = 0 then 0
                                    else t.total_kg * 1000 / nullif(l.lbp, 0) end,
               kg = k.kg,
               g_lente = case when l.lbp = 0 then null else k.kg * 1000 / l.lbp end,
               part = case when t.total_kg = 0 then null else k.kg / t.total_kg end
          from @kg k
          join @lentes l on l.num_mes = k.num_mes
          join (select num_mes, total_kg = sum(kg) from @kg group by num_mes) t
            on t.num_mes = k.num_mes
         order by k.num_mes, k.orden;

        -- acumulado del anio: suma kilos, suma lentes, divide al final
        select parte = replace(replace(km.magnitud_id, 'residuo_', ''), '_kg', ''),
               kg = coalesce(sum(k.kg), 0),
               g_lente = case when coalesce(@lbp_anio, 0) = 0 then null
                              else coalesce(sum(k.kg), 0) * 1000 / @lbp_anio end,
               part = case when coalesce(@kg_anio, 0) = 0 then null
                           else coalesce(sum(k.kg), 0) / @kg_anio end
          from ehs.kpi_magnitud km
          join ehs.dim_magnitud g on g.magnitud_id = km.magnitud_id
          left join @kg k on k.magnitud_id = km.magnitud_id
         where km.kpi_id = 'residuos_por_lente' and km.rol = 'numerador'
         group by km.magnitud_id, g.orden
         order by g.orden;
      `);

    const [[general = {}], largo, acumulado] = r.recordsets;

    const porMes = new Map();
    for (const f of largo) {
      let fila = porMes.get(f.mes);
      if (!fila) {
        fila = {
          mes: f.mes,
          nombre_mes: f.nombre_mes,
          lentes: num(f.lentes),
          total_kg: num(f.total_kg),
          total_g_lente: num(f.total_g_lente),
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
   * La trayectoria del KPI en el scorecard corporativo: 2023 a 2026, meta y real.
   *
   * El cierre de 2026 todavia no existe, y no se inventa: se devuelve aparte el YTD al
   * corte, rotulado como lo que es. Comparar un acumulado de siete meses contra cierres
   * de anio completo sin decirlo seria el error clasico de este tipo de tabla.
   */
  async trayectoriaAnual({ kpi }) {
    const ctx = await contexto();

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, ctx.anio)
      .input('mes', sql.TinyInt, ctx.corte)
      .input('ambito', sql.VarChar(20), 'nacional')
      .input('ambito_meta', sql.VarChar(20), META_DE_AMBITO.nacional)
      .input('kpi', sql.VarChar(40), kpi).query(`
        -- el perimetro del scorecard es el sitio de tipo Consolidado (COLOMBIA y PERU):
        -- no es un laboratorio ni una agencia, es la suma que reporta corporativo
        declare @perimetro varchar(20) = (select top 1 sitio_id from ehs.dim_sitio
                                           where tipo = 'Consolidado' order by sitio_id);

        declare @ytd table (kpi_id varchar(40) not null primary key, valor decimal(38,6) null);
        insert @ytd (kpi_id, valor)
        select v.kpi_id, ${VALOR_RECUPERADO}
          from ehs.v_kpi_ytd v
          join ehs.dim_kpi k on k.kpi_id = v.kpi_id
         where v.anio = @anio and v.ambito_id = @ambito
           and v.num_mes_corte = @mes and v.kpi_id = @kpi;

        select k.kpi, k.unidad, k.formato,
               perimetro = (select nombre_corporativo from ehs.dim_sitio
                             where sitio_id = @perimetro)
          from ehs.dim_kpi k where k.kpi_id = @kpi and k.area = 'ehs';

        select sc.anio, sc.meta, sc.real_ytd
          from ehs.scorecard_anual sc
         where sc.sitio_id = @perimetro and sc.kpi_id = @kpi
         order by sc.anio;

        select ytd = y.valor,
               meta = mt.valor,
               estado = ${ESTADO},
               ambito = ${NOMBRE_AMBITO}
          from @ytd y
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito_meta and mt.kpi_id = y.kpi_id;
      `);

    const [[def], anios, [curso] = []] = r.recordsets;
    if (!def || !anios.length) return null;

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

  /** Que mes trae lectura, cuantas y de que origen. */
  async calidadDato({ anio }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { sql, req } = await peticion();
    const r = await req.input('anio', sql.SmallInt, anio).input('corte', sql.TinyInt, ctx.corte)
      .query(`
        declare @magnitudes int = (select count(*) from ehs.dim_magnitud where area = 'ehs');

        -- todo cuenta hasta el corte publicado. Un mes que se este capturando ahora mismo
        -- no es un defecto de calidad, es un mes a medias, y quien lo dice es
        -- ehs.v_corte_publicado.en_curso, no un aviso de "mes incompleto"
        select lecturas = count(*),
               estado = case when count(distinct l.estado) = 1 then min(l.estado)
                             else 'mixto' end
          from ehs.hecho_lectura_mensual l
          join ehs.dim_fecha f on f.fecha = l.fecha
         where f.anio = @anio and f.num_mes <= @corte;

        select mes = f.num_mes,
               sitios = count(distinct l.sitio_id),
               magnitudes = @magnitudes,
               lecturas = count(distinct l.sitio_id) * @magnitudes
          from ehs.hecho_lectura_mensual l
          join ehs.dim_fecha f on f.fecha = l.fecha
         where f.anio = @anio and f.num_mes <= @corte
         group by f.num_mes
         order by f.num_mes;

        select filas from ehs.v_estado_agua_diaria;

        with valores as (
            select mes = f.num_mes,
                   s.sitio_id,
                   -- el aviso nombra al sitio como lo hace el reporte: su id capitalizado
                   sitio = upper(left(s.sitio_id, 1)) + substring(s.sitio_id, 2, 40),
                   l.magnitud_id, g.orden,
                   valor = cast(l.valor as float),
                   valor_anterior = cast(lag(l.valor) over (partition by l.sitio_id, l.magnitud_id
                                                                order by f.num_mes) as float),
                   mes_anterior = lag(f.num_mes) over (partition by l.sitio_id, l.magnitud_id
                                                           order by f.num_mes)
              from ehs.hecho_lectura_mensual l
              join ehs.dim_fecha f on f.fecha = l.fecha
              join ehs.dim_sitio s
                on s.sitio_id = l.sitio_id and s.activo = 1 and s.en_nacional = 1
              join ehs.dim_magnitud g on g.magnitud_id = l.magnitud_id and g.area = 'ehs'
             where f.anio = @anio and f.num_mes <= @corte
        ),
        avisos as (
            select rango = 0, paso = 0, orden, gravedad = 'error', codigo = 'valor_negativo',
                   mes, sitio_id, magnitud_id = cast(magnitud_id as varchar(40)),
                   mensaje = concat(sitio, ', mes ', mes, ': ', magnitud_id, ' viene en ',
                                    ${comoTexto('valor')},
                                    ', y esta magnitud no puede ser negativa.')
              from valores
             where valor < 0
            union all
            -- horas_temp tambien divide, pero un sitio sin personal temporal reporta cero
            -- con toda razon: solo avisa el denominador que nunca puede valer cero
            select 0, 1, orden, 'error', 'denominador_invalido',
                   mes, sitio_id, cast(magnitud_id as varchar(40)),
                   concat(sitio, ', mes ', mes, ': ', magnitud_id, ' en cero; los indicadores ',
                          'que dividen por esta magnitud no se pueden calcular.')
              from valores
             where valor = 0 and magnitud_id in ('unidades_buenas', 'horas_fijos')
            union all
            select 1, 0, 0, 'error', 'mes_incompleto',
                   f.num_mes, s.sitio_id, cast(null as varchar(40)),
                   concat(upper(left(s.sitio_id, 1)) + substring(s.sitio_id, 2, 40),
                          ' no reporto el mes ', f.num_mes,
                          ', pero otros sitios si. El consolidado de ese mes queda sesgado.')
              from ehs.dim_fecha f
             cross join ehs.dim_sitio s
             where f.anio = @anio and f.num_mes <= @corte
               and s.activo = 1 and s.en_nacional = 1
               and exists (select 1 from valores v where v.mes = f.num_mes)
               and not exists (select 1 from valores v
                                where v.mes = f.num_mes and v.sitio_id = s.sitio_id)
            union all
            -- nullif protege el cero: sin el, las horas de temporales en cero revientan
            -- la consulta con "Divide by zero" antes de llegar al filtro
            select 2, 0, orden, 'aviso', 'salto_atipico',
                   mes, sitio_id, cast(magnitud_id as varchar(40)),
                   concat(sitio, ', mes ', mes, ': ', magnitud_id, ' paso de ',
                          ${comoTexto('valor_anterior')}, ' (mes ', mes_anterior, ') a ',
                          ${comoTexto('valor')}, ' (',
                          case when valor > valor_anterior then '+' else '' end,
                          cast(round((valor - valor_anterior)
                                     / nullif(valor_anterior, 0) * 100, 0) as int),
                          '%). Conviene confirmar el dato.')
              from valores
             where valor_anterior is not null and valor_anterior <> 0
               -- pasar de 0 a 1 accidente es lo esperado, no una anomalia de captura
               and magnitud_id <> 'accidentes_dafw'
               and abs((valor - valor_anterior) / nullif(valor_anterior, 0)) > 0.4
        )
        select gravedad, codigo, mes, sitio_id, magnitud_id, mensaje
          from avisos
         order by mes, sitio_id, rango, orden, paso;
      `);

    const [[resumen = {}], porMes, [diaria = {}], avisos] = r.recordsets;
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
      // a diferencia de "hallazgos" (defectos puntuales del libro heredado, escritos a
      // mano porque describen un hecho historico), esto se recalcula en cada corte:
      // valores negativos, denominadores en cero, meses sin un sitio y saltos atipicos
      // mes a mes. Lo que en Python era "medicion_duplicada" aqui no hace falta: la
      // restriccion uq_lectura_mensual lo hace estructuralmente imposible.
      avisos_automaticos: avisos.map((a) => {
        const salida = { gravedad: a.gravedad, codigo: a.codigo, mes: a.mes, sitio: a.sitio_id };
        if (a.magnitud_id) salida.metrica = a.magnitud_id;
        salida.mensaje = a.mensaje;
        return salida;
      }),
    };
  },

  /** El crudo exportable: las magnitudes tal como se capturaron. */
  async detalle({ anio }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { sql, req } = await peticion();
    const r = await req.input('anio', sql.SmallInt, anio).input('corte', sql.TinyInt, ctx.corte)
      .query(`
        select magnitud_id from ehs.dim_magnitud where area = 'ehs' order by orden;

        select sitio = l.sitio_id,
               anio = cast(f.anio as varchar(4)),
               mes = cast(f.num_mes as varchar(2)),
               num_mes = f.num_mes,
               l.magnitud_id,
               valor = cast(l.valor as float)
          from ehs.hecho_lectura_mensual l
          join ehs.dim_fecha f on f.fecha = l.fecha
          join ehs.dim_magnitud g on g.magnitud_id = l.magnitud_id and g.area = 'ehs'
         where f.anio = @anio and f.num_mes <= @corte
         order by l.sitio_id, f.num_mes, g.orden;
      `);

    const [magnitudes, lecturas] = r.recordsets;
    const columnas = magnitudes.map((x) => x.magnitud_id);

    const filas = [];
    const porClave = new Map();
    for (const l of lecturas) {
      const clave = `${l.sitio}|${l.num_mes}`;
      let fila = porClave.get(clave);
      if (!fila) {
        // una magnitud sin captura es la AUSENCIA de la lectura y se publica como null:
        // un cero seria decir que se midio y dio cero
        fila = { anio: l.anio, mes: l.mes, sitio: l.sitio };
        for (const c of columnas) fila[c] = null;
        porClave.set(clave, fila);
        filas.push(fila);
      }
      fila[l.magnitud_id] = num(l.valor);
    }

    return { ...cabecera(ctx), filas };
  },
};
