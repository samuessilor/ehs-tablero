/**
 * Adaptador SQL — el destino. Mismas firmas que adaptador_json.js.
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
 *                          (hojaMensualRecurso, compartida con energiaMensual)
 *   energiaMensual      -> igual que aguaMensual, para energia_por_lente
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
 *   2. RESUELTO EN LA MIGRACION 0010. v_kpi_contra_meta usaba otra regla (+5 % SOBRE
 *      la meta, 'en riesgo') que el contrato publicado (90 % POR DEBAJO, 'riesgo') y
 *      marcaba 'en riesgo' valores por encima del techo. Ahora la vista usa la misma
 *      regla, los mismos codigos y el mismo redondeo que ESTADO y BRECHA de este
 *      archivo. La banda en si sigue siendo decision de EHS: si cambia, se cambia aqui
 *      y en esa vista, que ya dicen lo mismo.
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
 * De donde saca su meta cada ambito: cada uno usa la suya, la vigente en ehs.meta.
 *
 * Nacional Labs + Agencias usa SU meta (7,5 L · 1,5 kWh · 126 g · 1,6 · 5, de
 * 'KPIs 2026'!F14:H14 e indicadores!C39:C40), que es la que fija ehs/CLAUDE.md y la que
 * el libro del area grafica como "Meta". Antes tomaba prestada la del perimetro
 * corporativo COLOMBIA y PERU (8,39 · 1,67 · 126 · 1,76 · 5), heredado de
 * analisis/web_json.py de cuando la base no tenia meta nacional vigente: el estado
 * salia igual, pero cada brecha contra una meta que el area no usa (agua -39 % en vez
 * de -32 %). La del perimetro corporativo sigue donde corresponde: la trayectoria en
 * el scorecard (trayectoriaAnual). Nacional Labs no tiene meta y no hereda ninguna:
 * nadie publica un objetivo para ese subconjunto, y heredarlo seria inventarlo.
 */
const META_DE_AMBITO = {
  celta: 'celta',
  estrella: 'estrella',
  agencias: 'agencias',
  nacional: 'nacional',
  nacional_labs: null,
  peru: 'peru',
  colombia_peru: 'colombia_peru',
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
 * Funciones y no una constante de texto: la logica es siempre la misma, pero el alias
 * de la meta y del valor acumulado cambia segun la consulta (mt.valor/y.valor en la
 * mayoria; sc.meta/sc.real_ytd en el historico anual de datosTabulados) — parametrizar
 * las columnas evita copiar el CASE a mano cada vez que aparece un alias nuevo.
 */
const brechaSql = (metaCol, valorCol) =>
  `case when ${metaCol} is null or ${metaCol} = 0 or ${valorCol} is null then null
                          else round((${valorCol} - ${metaCol}) / ${metaCol}, 6) end`;
/* El caso 'sin_dato' va ANTES del especial de meta=0 (Agencias en FR/accidentes: meta
   0 incidentes, y de verdad reporta 0 real cuando no pasa nada - nunca null). Con el
   orden viejo, un ambito sin ninguna lectura (Peru en FR/accidentes: "todavia no
   llegan", ver ehs/CLAUDE.md) y una meta tambien en 0 caia en la rama de meta=0, que
   hacia coalesce(y.valor, 0) <= 0 y volvia 'cumple' - un ambito sin ningun dato
   mostraba una insignia verde de "cumple la meta", lo mas parecido a afirmar algo sin
   verificarlo que puede mostrar este tablero. */
const estadoSql = (metaCol, valorCol) =>
  `case when ${metaCol} is null then 'sin_meta'
                          when ${valorCol} is null then 'sin_dato'
                          when ${metaCol} = 0 then case when ${valorCol} <= 0
                                                      then 'cumple' else 'incumple' end
                          when ${valorCol} > ${metaCol} then 'incumple'
                          when ${valorCol} >= ${metaCol} * 0.90 then 'riesgo'
                          else 'cumple' end`;

/** El nombre largo del ambito: el del sitio si lo es, y el del agregado si no. */
const NOMBRE_AMBITO = `(select top 1 case when a.ambito_id = a.sitio_id then s.sitio else a.ambito end
                          from ehs.v_ambito a
                          join ref.dim_sitio s on s.sitio_id = a.sitio_id
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
      join ref.dim_kpi k on k.kpi_id = v.kpi_id
     where v.anio = @anio and v.ambito_id = @ambito and v.num_mes_corte <= @corte;

    insert @mensual (kpi_id, num_mes, valor)
    select v.kpi_id, v.num_mes, ${VALOR_RECUPERADO}
      from ehs.v_kpi_mensual v
      join ref.dim_kpi k on k.kpi_id = v.kpi_id
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

const { fechaUltimoRespaldo } = require('../respaldo');

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
           corte_nombre = (select top 1 mes from ref.dim_fecha
                            where anio = @anio and num_mes = @corte),
           /* Las metas vigentes vienen de dos fuentes, y el pie las nombra a las dos: la
              nacional del libro del area y la de cada sitio del scorecard. Antes era un
              max(fuente) sobre todas, que por orden alfabetico decia "scorecard" aunque
              los cinco numeros de arriba se midieran contra el libro. */
           meta_vigente = case
               when exists (select 1 from ehs.meta
                             where anio = @anio and vigente = 1 and ambito_id = 'nacional')
               then N'Nacional: libro KPIs ' + cast(@anio as nvarchar(4)) + N' · sitios: '
                    + isnull((select max(fuente) from ehs.meta
                               where anio = @anio and vigente = 1 and ambito_id <> 'nacional'),
                             N'sin meta')
               else (select max(fuente) from ehs.meta where anio = @anio and vigente = 1)
           end,
           /* Cuando cambio por ultima vez el dato que se esta publicando.
              Sale de la base y NO del manifiesto, aunque el manifiesto traiga un
              campo con ese nombre: el manifiesto dice cuando publico el pipeline por
              ultima vez, que en modo SQL no tiene nada que ver. Con el manifiesto, el
              tablero decia "corte agosto" y "ultima actualizacion 31 de agosto" a la
              vez, con una fecha ANTERIOR a la captura que acababa de moverlo. */
           actualizado_en = (select max(coalesce(l.modificado_en, l.capturado_en))
                               from ehs.hecho_lectura_mensual l
                               join ref.dim_fecha f on f.fecha = l.fecha
                              where f.anio = @anio and f.num_mes <= @corte);
    select num_mes = f.num_mes
      from ehs.hecho_lectura_mensual l
      join ref.dim_fecha f on f.fecha = l.fecha
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

/**
 * Las correcciones hechas desde "Consultar y corregir" (migracion 0009) que tocan el
 * ambito, para la franja "Valor corregido" del tablero. Antes la franja solo leia las
 * correcciones del manifiesto (datos.json, estatico y vacio), asi que una correccion
 * hecha en la app recalculaba todo pero no se lo decia a quien miraba el tablero.
 * Mismas claves que las del manifiesto (valorExcel = el valor anterior).
 */
async function correccionesDelAmbito(anio, ambito) {
  const { sql, req } = await peticion();
  const r = await req.input('anio', sql.SmallInt, anio).input('ambito', sql.VarChar(20), ambito)
    .query(`
      select top 10 c.anio, c.mes, c.sitio_corto, c.magnitud,
             valor_anterior = cast(c.valor_anterior as float),
             valor_corregido = cast(c.valor_corregido as float),
             c.motivo, c.autorizado_por,
             corregido_en = convert(varchar(16), c.corregido_en, 120)
        from ehs.v_correcciones c
        join ehs.v_ambito a on a.sitio_id = c.sitio_id and a.ambito_id = @ambito
       where c.anio = @anio
       order by c.corregido_en desc, c.hist_id desc;
    `);
  const texto = (v) => (v === null || v === undefined ? '—' : String(v).replace('.', ','));
  return r.recordset.map((x) => ({
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

/**
 * La hoja mensual "consumo, producción y ratio" de un KPI de razón simple (un
 * numerador, un denominador): agua y energía comparten exactamente esta forma.
 * Que magnitud es el numerador y cual el denominador lo dice ref.kpi_magnitud, que
 * ya guarda esa definición como dato — repetir 'agua_m3'/'energia_kwh' aquí sería
 * una segunda copia de la misma fórmula, la misma razón por la que v_kpi_mensual
 * tampoco la hardcodea.
 *
 * La variación se mide contra el mes INMEDIATAMENTE anterior; si ese mes no se
 * reportó no hay contra qué compararlo y se dice (null), no se salta al último que
 * haya. El factor de conversión (agua ×1000 de m³ a L, energía ×1) sale de
 * ref.dim_kpi: no se hardcodea aquí tampoco.
 */
async function hojaMensualRecurso({ ctx, anio, ambito, kpiId }) {
  const { sql, req } = await peticion();
  const r = await req
    .input('anio', sql.SmallInt, anio)
    .input('corte', sql.TinyInt, ctx.corte)
    .input('ambito', sql.VarChar(20), ambito)
    .input('kpi', sql.VarChar(40), kpiId).query(`
      select nombre = ${NOMBRE_AMBITO};

      with mensual as (
          select f.num_mes, nombre_mes = f.mes,
                 num = sum(case when km.rol = 'numerador' then cast(la.valor as float) end),
                 den = sum(case when km.rol = 'denominador' then cast(la.valor as float) end)
            from ehs.v_lectura_ambito la
            join ref.dim_fecha f on f.fecha = la.fecha
            join ref.kpi_magnitud km
              on km.magnitud_id = la.magnitud_id and km.kpi_id = @kpi
           where la.anio = @anio and la.ambito_id = @ambito and f.num_mes <= @corte
           group by f.num_mes, f.mes
      ),
      con_previo as (
          select *,
                 num_prev = lag(num) over (order by num_mes),
                 den_prev = lag(den) over (order by num_mes),
                 mes_prev = lag(num_mes) over (order by num_mes)
            from mensual
      )
      select mes = num_mes, nombre_mes,
             consumo = round(num, 2),
             lentes = cast(den as bigint),
             ratio = round(num * (select factor from ref.dim_kpi where kpi_id = @kpi)
                           / nullif(den, 0), 4),
             var_total_pct = case when mes_prev = num_mes - 1 and num_prev <> 0
                                  then round((num - num_prev) / num_prev * 100, 2) end,
             -- el factor de conversion se cancela en un cambio porcentual: no hace
             -- falta traerlo aqui otra vez
             var_por_lente_pct = case when mes_prev = num_mes - 1 and num_prev <> 0
                                       and den_prev <> 0 and den <> 0
                                  then round((num / den - num_prev / den_prev)
                                             / (num_prev / den_prev) * 100, 2) end
        from con_previo
       order by num_mes;
    `);

  const [[general = {}], filas] = r.recordsets;
  return { nombre: general.nombre, filas };
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

        /* El corte es del ambito, no solo de Colombia: 'Peru' y 'Colombia + Peru' pueden ir
           un mes atras (0021). Si el mes pedido esta dentro del corte publicado pero el
           ambito todavia no lo tiene, se responde el ultimo que si tiene, y el mes real
           va en corte.mes. Un mes posterior al corte sigue siendo "sin dato". */
        declare @mes_ef tinyint = case
            when exists (select 1 from @mensual where num_mes = @mes) then @mes
            when @mes <= @corte then (select max(num_mes) from @mensual where num_mes < @mes)
        end;

        select nombre = ${NOMBRE_AMBITO},
               hay_dato = case when @mes_ef is not null then 1 else 0 end,
               mes_ef = @mes_ef,
               nombre_mes = (select top 1 mes from ref.dim_fecha
                              where anio = @anio and num_mes = @mes_ef);

        select k.kpi_id, k.kpi, k.unidad, k.familia, k.formato,
               valor = y.valor,
               valor_mes = m.valor,
               meta = mt.valor,
               es_referencia = case when @ambito_meta is not null and @ambito_meta <> @ambito
                                    then 1 else 0 end,
               brecha_pct = ${brechaSql('mt.valor', 'y.valor')},
               estado = ${estadoSql('mt.valor', 'y.valor')}
          from ref.dim_kpi k
          left join @ytd y on y.kpi_id = k.kpi_id and y.num_mes = @mes_ef
          left join @mensual m on m.kpi_id = k.kpi_id and m.num_mes = @mes_ef
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito_meta and mt.kpi_id = k.kpi_id
         where k.area = 'ehs'
         order by k.orden;

        -- solo los meses que alguien reporto completos: dibujar los demas seria dibujar
        -- meses que el informe no publica
        select y.kpi_id, mes = y.num_mes, y.valor,
               brecha_pct = ${brechaSql('mt.valor', 'y.valor')},
               estado = ${estadoSql('mt.valor', 'y.valor')}
          from @ytd y
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito_meta and mt.kpi_id = y.kpi_id
         where exists (select 1 from @mensual d where d.num_mes = y.num_mes)
         order by y.kpi_id, y.num_mes;

        -- los meses que ESTE ambito tiene: el selector de mes del tablero se arma con ellos
        select num_mes from @mensual group by num_mes order by num_mes;
      `);

    const [[general = {}], kpis, serie, mesesAmbito] = r.recordsets;
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
      // el corte del ambito: igual al publicado para Colombia y sus sitios; un mes atras
      // para 'Peru' y 'Colombia + Peru' mientras Peru no reporte el mes nuevo
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
    // nada pasa del corte publicado: ?mes=8 devolvia en silencio los valores de julio
    if (anio !== ctx.anio || mes > ctx.corte) return null;

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
          join ref.dim_kpi k on k.kpi_id = v.kpi_id
          join ref.dim_sitio s on s.sitio_id = v.ambito_id and s.activo = 1 and s.en_nacional = 1
         where v.anio = @anio and v.num_mes_corte = @mes and v.kpi_id = @kpi;

        select k.kpi, k.unidad from ref.dim_kpi k where k.kpi_id = @kpi and k.area = 'ehs';

        select s.sitio_id, s.sitio, corporativo = s.nombre_corporativo,
               valor = y.valor,
               meta = mt.valor,
               brecha_pct = ${brechaSql('mt.valor', 'y.valor')},
               estado = ${estadoSql('mt.valor', 'y.valor')}
          from ref.dim_sitio s
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
          from ref.dim_kpi k
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
          from ref.dim_fecha f
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

    const { nombre, filas } = await hojaMensualRecurso({
      ctx,
      anio,
      ambito,
      kpiId: 'agua_por_lente',
    });

    // el reporte de agua del area publica cada sitio y el consolidado nacional; Nacional
    // Labs es un subconjunto que ese reporte no tiene, y se dice, no se inventa (R.5.5.1)
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
   * La misma hoja que aguaMensual, para energía. A diferencia del agua, el área no
   * publica un reporte externo de energía que excluya Nacional Labs: aquí los cinco
   * ámbitos se sirven igual, sin la salvedad de R.5.5.1 de arriba.
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
        -- lo dice ref.kpi_magnitud, que guarda la formula del KPI como dato
        insert @kg (num_mes, nombre_mes, magnitud_id, orden, kg)
        select f.num_mes, f.mes, la.magnitud_id, g.orden, sum(cast(la.valor as float))
          from ehs.v_lectura_ambito la
          join ref.dim_fecha f on f.fecha = la.fecha
          join ref.dim_magnitud g on g.magnitud_id = la.magnitud_id
          join ref.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id
           and km.kpi_id = 'residuos_por_lente' and km.rol = 'numerador'
         where la.anio = @anio and la.ambito_id = @ambito and f.num_mes <= @corte
         group by f.num_mes, f.mes, la.magnitud_id, g.orden;

        -- solo los meses que traen residuo: un mes con lentes y sin pesaje no puede
        -- entrar al denominador del acumulado, o el g/lente del anio saldria diluido
        insert @lentes (num_mes, lbp)
        select f.num_mes, sum(cast(la.valor as float))
          from ehs.v_lectura_ambito la
          join ref.dim_fecha f on f.fecha = la.fecha
          join ref.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id
           and km.kpi_id = 'residuos_por_lente' and km.rol = 'denominador'
         where la.anio = @anio and la.ambito_id = @ambito and f.num_mes <= @corte
           and exists (select 1 from @kg x where x.num_mes = f.num_mes)
         group by f.num_mes;

        declare @kg_anio float  = (select sum(kg) from @kg);
        declare @lbp_anio float = (select sum(lbp) from @lentes);

        select nombre = ${NOMBRE_AMBITO};

        -- suma_kg/suma_g_lente (no total_kg/total_g_lente): 'total' es tambien un
        -- valor real de "parte" (residuo_total_kg de Peru, sin desglose), y el cliente
        -- guarda cada parte como fila[parte + '_kg'] - con el nombre viejo, la fila del
        -- mes de un ambito combinado (Colombia + Peru) pisaba esta suma agregada con el
        -- kg de la sola parte 'total' de Peru en cuanto esa parte tambien aparecia.
        select mes = k.num_mes, k.nombre_mes,
               parte = replace(replace(k.magnitud_id, 'residuo_', ''), '_kg', ''),
               lentes = l.lbp,
               suma_kg = t.total_kg,
               suma_g_lente = case when t.total_kg = 0 then 0
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
        -- 'residuo_total_kg' es numerador legitimo de residuos_por_lente (Peru no
        -- trae el desglose peligroso/aprovechable/ordinario, solo un total), pero
        -- ref.kpi_magnitud lo registra para el KPI entero, no por ambito: sin el
        -- exists de abajo, Colombia (que nunca captura esa magnitud) igual recibia
        -- una cuarta "parte" en kg=0 - sin nombre ni color propio en el cliente,
        -- que se apilaba como una barra extra encima de "Aprovechable".
        select parte = replace(replace(km.magnitud_id, 'residuo_', ''), '_kg', ''),
               kg = coalesce(sum(k.kg), 0),
               g_lente = case when coalesce(@lbp_anio, 0) = 0 then null
                              else coalesce(sum(k.kg), 0) * 1000 / @lbp_anio end,
               part = case when coalesce(@kg_anio, 0) = 0 then null
                           else coalesce(sum(k.kg), 0) / @kg_anio end
          from ref.kpi_magnitud km
          join ref.dim_magnitud g on g.magnitud_id = km.magnitud_id
          left join @kg k on k.magnitud_id = km.magnitud_id
         where km.kpi_id = 'residuos_por_lente' and km.rol = 'numerador'
           and exists (select 1 from @kg k2 where k2.magnitud_id = km.magnitud_id)
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
   * La trayectoria del KPI en el scorecard corporativo: 2023 a 2026, meta y real.
   *
   * El cierre de 2026 todavia no existe, y no se inventa: se devuelve aparte el YTD al
   * corte, rotulado como lo que es. Comparar un acumulado de siete meses contra cierres
   * de anio completo sin decirlo seria el error clasico de este tipo de tabla.
   */
  async trayectoriaAnual({ kpi, ambito = 'nacional' }) {
    const ctx = await contexto();

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, ctx.anio)
      .input('mes', sql.TinyInt, ctx.corte)
      .input('ambito', sql.VarChar(20), ambito)
      .input('kpi', sql.VarChar(40), kpi).query(`
        /* El perimetro de la trayectoria es el propio @ambito: cada uno que puede
           tenerla (celta, estrella, agencias, peru, nacional/Colombia,
           colombia_peru) tiene su propia fila en ref.dim_sitio con ese mismo id,
           exactamente para esto — ehs.scorecard_anual y ehs.meta cuelgan de ese
           id via FK. Antes esto adivinaba el perimetro buscando el UNICO sitio de
           tipo 'Consolidado', que dejo de ser unico en cuanto 'nacional' (Colombia)
           gano su propia fila (migracion 0011): con dos Consolidado, "top 1 order
           by sitio_id" solo acertaba por alfabeto. */
        declare @ytd table (kpi_id varchar(40) not null primary key, valor decimal(38,6) null);
        insert @ytd (kpi_id, valor)
        select v.kpi_id, ${VALOR_RECUPERADO}
          from ehs.v_kpi_ytd v
          join ref.dim_kpi k on k.kpi_id = v.kpi_id
         where v.anio = @anio and v.ambito_id = @ambito
           and v.num_mes_corte = @mes and v.kpi_id = @kpi;

        select k.kpi, k.unidad, k.formato,
               perimetro = (select nombre_corporativo from ref.dim_sitio
                             where sitio_id = @ambito)
          from ref.dim_kpi k where k.kpi_id = @kpi and k.area = 'ehs';

        -- anio >= 2024: regla del area (27-sep-2026), solo datos desde 2024 en
        -- adelante en base de datos y visualizacion. La fila de 2023 sigue en
        -- ehs.scorecard_anual (borrarla es una decision aparte e irreversible); esto
        -- solo la saca de lo que se muestra.
        select sc.anio, sc.meta, sc.real_ytd
          from ehs.scorecard_anual sc
         where sc.sitio_id = @ambito and sc.kpi_id = @kpi and sc.anio >= 2024
         order by sc.anio;

        select ytd = y.valor,
               meta = mt.valor,
               estado = ${estadoSql('mt.valor', 'y.valor')},
               ambito = ${NOMBRE_AMBITO}
          from @ytd y
          -- la barra del ano en curso se mide contra la meta vigente del MISMO
          -- ambito, igual que los cierres historicos de esta misma grafica
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito and mt.kpi_id = y.kpi_id;
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

  /**
   * Contraste mes a mes entre dos anios elegidos, para el mismo ambito y KPI: el
   * valor de cada mes (ehs.v_kpi_mensual) y el acumulado hasta ese mes
   * (ehs.v_kpi_ytd), lado a lado. No se inventa el mes que todavia no tiene
   * lectura: si un anio no llega hasta diciembre, esos meses quedan null.
   */
  async contrasteMensual({ ambito, kpi, anioA, anioB }) {
    const { sql, req } = await peticion();
    const r = await req
      .input('ambito', sql.VarChar(20), ambito)
      .input('kpi', sql.VarChar(40), kpi)
      .input('anioA', sql.SmallInt, anioA)
      .input('anioB', sql.SmallInt, anioB).query(`
        declare @meses table (num_mes tinyint primary key, nombre_mes varchar(12));
        insert @meses select distinct num_mes, mes from ref.dim_fecha;

        select mes.num_mes, mes.nombre_mes, anios.anio,
               mensual = case when mm.valor is null then null else round(mm.valor, 6) end,
               ytd     = case when yy.valor is null then null else round(yy.valor, 6) end
          from @meses mes
         cross join (values (@anioA), (@anioB)) as anios(anio)
          left join ehs.v_kpi_mensual mm
                 on mm.anio = anios.anio and mm.num_mes = mes.num_mes
                and mm.ambito_id = @ambito and mm.kpi_id = @kpi
          left join ehs.v_kpi_ytd yy
                 on yy.anio = anios.anio and yy.num_mes_corte = mes.num_mes
                and yy.ambito_id = @ambito and yy.kpi_id = @kpi
         order by mes.num_mes, anios.anio;

        select k.kpi, k.unidad, k.formato from ref.dim_kpi k
         where k.kpi_id = @kpi and k.area = 'ehs';
      `);

    const [filas, [def]] = r.recordsets;
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
         acumulado de julio, repetido) porque matematicamente nada nuevo se sumo.
         Aqui se recorta a null en cuanto el mes ya no tiene su propio valor
         mensual, para no dar a entender que agosto tiene un cierre que no tiene. */
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

    const { sql, req } = await peticion();
    const r = await req.input('anio', sql.SmallInt, anio).input('corte', sql.TinyInt, ctx.corte)
      .query(`
        -- todo cuenta hasta el corte publicado. Un mes que se este capturando ahora mismo
        -- no es un defecto de calidad, es un mes a medias, y quien lo dice es
        -- ehs.v_corte_publicado.en_curso, no un aviso de "mes incompleto"
        select lecturas = count(*),
               estado = case when count(distinct l.estado) = 1 then min(l.estado)
                             else 'mixto' end
          from ehs.hecho_lectura_mensual l
          join ref.dim_fecha f on f.fecha = l.fecha
         where f.anio = @anio and f.num_mes <= @corte;

        -- 'lecturas' es el conteo real de filas (una lectura = un sitio + una magnitud
        -- + un mes), no sitios x @magnitudes: esa multiplicacion asumia que TODO sitio
        -- captura TODAS las magnitudes del area, lo cual nunca fue cierto (Peru captura
        -- 4 de las 10 - agua/energia/unidades/residuo_total, no el desglose de residuos
        -- ni accidentalidad) y por mes daba un numero fijo (40) que ni siquiera sumaba
        -- contra el total real de la tarjeta de arriba (217, no 280 = 40 x 7 meses).
        select mes = f.num_mes,
               sitios = count(distinct l.sitio_id),
               magnitudes = count(distinct l.magnitud_id),
               lecturas = count(*)
          from ehs.hecho_lectura_mensual l
          join ref.dim_fecha f on f.fecha = l.fecha
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
              join ref.dim_fecha f on f.fecha = l.fecha
              join ref.dim_sitio s
                on s.sitio_id = l.sitio_id and s.activo = 1 and s.en_nacional = 1
              join ref.dim_magnitud g on g.magnitud_id = l.magnitud_id and g.area = 'ehs'
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
              from ref.dim_fecha f
             cross join ref.dim_sitio s
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
        -- avisos.mes es num_mes, no una fecha: se reconstruye para el join contra
        -- ehs.aviso_confirmado (migracion 0017), que guarda fecha, no anio+mes sueltos.
        -- Solo importa la confirmacion para 'aviso' (hoy: salto_atipico) -- los de
        -- 'error' nunca se confirman, asi que el join da null y listo.
        select av.gravedad, av.codigo, av.mes, av.sitio_id, av.magnitud_id, av.mensaje,
               confirmado = case when ac.fecha is not null then 1 else 0 end,
               confirmado_por = ac.confirmado_por,
               confirmado_en = ac.confirmado_en,
               nota_confirmacion = ac.nota
          from avisos av
          left join ehs.aviso_confirmado ac
            on ac.fecha = datefromparts(@anio, av.mes, 1)
           and ac.sitio_id = av.sitio_id
           and ac.magnitud_id = av.magnitud_id
           and ac.codigo = av.codigo
         order by av.mes, av.sitio_id, av.rango, av.orden, av.paso;
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
        // confirmado (migracion 0017): alguien del area ya vio esta tabla y dio su
        // veredicto. Solo puede venir en 1 para 'aviso' -- el join de arriba nunca
        // encuentra fila para 'error', que no se confirma.
        salida.confirmado = Boolean(a.confirmado);
        if (a.confirmado) {
          salida.confirmadoPor = a.confirmado_por;
          // igual que actualizadoEn arriba: la base guarda hora de pared sin zona
          // (sysdatetime()); .toISOString() sin este recorte le pegaria una 'Z' que
          // el cliente leeria como UTC y correria 5 horas (el mismo bug de fechaLegible).
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

    const { sql, req } = await peticion();
    const r = await req.input('anio', sql.SmallInt, anio).input('corte', sql.TinyInt, ctx.corte)
      .query(`
        select magnitud_id from ref.dim_magnitud where area = 'ehs' order by orden;

        select sitio = l.sitio_id,
               anio = cast(f.anio as varchar(4)),
               mes = cast(f.num_mes as varchar(2)),
               num_mes = f.num_mes,
               l.magnitud_id,
               valor = cast(l.valor as float)
          from ehs.hecho_lectura_mensual l
          join ref.dim_fecha f on f.fecha = l.fecha
          join ref.dim_magnitud g on g.magnitud_id = l.magnitud_id and g.area = 'ehs'
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

  /**
   * Los datos detras de las graficas, para la vista "Datos" del tablero.
   *
   * Dos cosas, las dos del corte publicado y del ambito elegido:
   *   - las lecturas crudas mes a mes (sumadas por magnitud si el ambito agrega sitios),
   *     de ehs.v_lectura_ambito;
   *   - por cada KPI, el numerador, el denominador y el valor mensual y acumulado TAL
   *     COMO los publican ehs.v_kpi_mensual y ehs.v_kpi_ytd, que son las vistas de las
   *     que salen las graficas y las fichas.
   * No calcula nada nuevo: pone a la vista de donde sale cada numero, con que
   * magnitudes (ref.kpi_magnitud) y con que factor, para que se pueda comprobar a mano.
   */
  async datosTabulados({ anio, ambito }) {
    const ctx = await contexto();
    ({ anio } = alCorte(ctx, anio, null));
    if (anio !== ctx.anio) return null;

    const { sql, req } = await peticion();
    const r = await req
      .input('anio', sql.SmallInt, anio)
      .input('corte', sql.TinyInt, ctx.corte)
      .input('ambito', sql.VarChar(20), ambito).query(`
        select nombre = ${NOMBRE_AMBITO};

        select a.sitio_id, s.sitio
          from ehs.v_ambito a
          join ref.dim_sitio s on s.sitio_id = a.sitio_id
         where a.ambito_id = @ambito
         order by a.sitio_id;

        select magnitud_id, magnitud, unidad
          from ref.dim_magnitud where area = 'ehs' order by orden;

        select k.kpi_id, k.kpi, k.unidad, k.formato, factor = cast(k.factor as float)
          from ref.dim_kpi k where k.area = 'ehs' order by k.orden;

        select km.kpi_id, km.magnitud_id, km.rol
          from ref.kpi_magnitud km
          join ref.dim_kpi k on k.kpi_id = km.kpi_id and k.area = 'ehs';

        select la.num_mes, la.magnitud_id,
               valor = cast(sum(la.valor) as float), lecturas = count(*)
          from ehs.v_lectura_ambito la
         where la.anio = @anio and la.ambito_id = @ambito and la.num_mes <= @corte
         group by la.num_mes, la.magnitud_id;

        select m.num_mes, m.kpi_id,
               numerador = cast(m.numerador as float),
               denominador = cast(m.denominador as float),
               valor = cast(round(m.valor, 6) as float),
               ytd_numerador = cast(y.numerador as float),
               ytd_denominador = cast(y.denominador as float),
               ytd = cast(round(y.valor, 6) as float)
          from ehs.v_kpi_mensual m
          left join ehs.v_kpi_ytd y
                 on y.anio = m.anio and y.num_mes_corte = m.num_mes
                and y.ambito_id = m.ambito_id and y.kpi_id = m.kpi_id
         where m.anio = @anio and m.ambito_id = @ambito and m.num_mes <= @corte;

        -- todas las metas registradas de este ambito para el anio del corte, vigente o
        -- no: el libro trajo tres juegos de metas 2026 y solo una quedo vigente (ver
        -- migracion 0005) -- mostrar tambien las descartadas, con su fuente, es
        -- exactamente lo que le da credibilidad a la meta que si se usa: se ve que no
        -- se eligio a ciegas.
        select mt.kpi_id, valor = cast(mt.valor as float), mt.fuente, mt.vigente
          from ehs.meta mt
         where mt.anio = @anio and mt.ambito_id = @ambito
         order by mt.kpi_id, mt.vigente desc, mt.fuente;

        -- el cierre de cada anio anterior (regla del area: 2024 en adelante, migracion
        -- 0016 borro 2023 de la base) MAS el anio en curso, calculado en vivo desde
        -- v_kpi_ytd al mismo corte que el resto de esta funcion -- una sola fila por
        -- (kpi, anio), misma forma para los dos casos, para que el cliente no necesite
        -- un camino aparte para "el anio que todavia no cerro". Nacional Labs no tiene
        -- fila propia en el scorecard corporativo (nunca la tuvo, ver META_DE_AMBITO
        -- mas arriba) y esta consulta simplemente no devuelve nada para ese ambito -- el
        -- cliente lo dice, no lo inventa.
        select sc.kpi_id, sc.anio,
               meta = cast(sc.meta as float), real = cast(sc.real_ytd as float),
               brecha_pct = cast(${brechaSql('sc.meta', 'sc.real_ytd')} as float),
               estado = ${estadoSql('sc.meta', 'sc.real_ytd')},
               cerrado = cast(1 as bit)
          from ehs.scorecard_anual sc
         -- < @anio, no solo >= 2024: el scorecard corporativo YA trae una fila para
         -- @anio con la meta puesta y real_ytd en null (el anio todavia no cierra) --
         -- 'nacional'/agua_por_lente/2026 es el caso real, encontrado probando esta
         -- misma consulta. Sin este limite esa fila duplicaba el anio en curso, con
         -- la union de abajo, que SI trae el valor real via v_kpi_ytd.
         where sc.sitio_id = @ambito and sc.anio >= 2024 and sc.anio < @anio
        union all
        select y.kpi_id, anio = @anio,
               meta = cast(mt.valor as float), real = cast(round(y.valor, 6) as float),
               brecha_pct = cast(${brechaSql('mt.valor', 'y.valor')} as float),
               estado = ${estadoSql('mt.valor', 'y.valor')},
               cerrado = cast(0 as bit)
          from ehs.v_kpi_ytd y
          left join ehs.meta mt
                 on mt.anio = @anio and mt.vigente = 1
                and mt.ambito_id = @ambito and mt.kpi_id = y.kpi_id
         where y.anio = @anio and y.ambito_id = @ambito and y.num_mes_corte = @corte
         order by kpi_id, anio;
      `);

    const [[def], sitios, magnitudes, kpis, mapa, lecturas, valores, metas, historico] =
      r.recordsets;
    if (!def || !lecturas.length) return null;

    const meses = new Map();
    const mesDe = (n) => {
      if (!meses.has(n)) meses.set(n, { mes: n, lecturas: {}, sitiosConLectura: {}, kpis: {} });
      return meses.get(n);
    };
    for (const l of lecturas) {
      const m = mesDe(l.num_mes);
      m.lecturas[l.magnitud_id] = num(l.valor);
      // cuantos sitios aportaron a la suma: con menos de los del ambito, la suma es parcial
      m.sitiosConLectura[l.magnitud_id] = l.lecturas;
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
        // todas las metas 2026 registradas para este KPI en este ambito, vigente
        // primero (metas.order by ya las trae asi); normalmente una sola, a veces mas
        // (ver el comentario de la consulta).
        metas: metas
          .filter((m) => m.kpi_id === k.kpi_id)
          .map((m) => ({ valor: num(m.valor), fuente: m.fuente, vigente: Boolean(m.vigente) })),
        // el cierre de cada anio anterior de ESTE kpi (2024 en adelante) mas el anio en
        // curso (cerrado:false); [] si el ambito no tiene scorecard propio (Nacional
        // Labs).
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
   * Lo que la franja de estado necesita: si el motor responde, y en cuanto. No pasa
   * por contexto()/peticion() (que asumen que la conexion ya funciona y fallan con el
   * error generico de la consulta que estaban resolviendo): aqui el fallo ES la
   * respuesta que se quiere mostrar, asi que se atrapa aqui mismo en vez de dejar que
   * suba hasta errores.interno (que ya sabe convertir un ConnectionError en 503, pero
   * esta ruta necesita el detalle "motor abajo" en el propio cuerpo 200, para que la
   * franja lo pinte sin tener que distinguir codigos de error).
   */
  async salud() {
    const inicio = Date.now();
    const ultimoRespaldo = fechaUltimoRespaldo();
    try {
      const { req } = await peticion();
      await req.query('select 1 as ok');
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
      return {
        modo: 'sql',
        motor: 'abajo',
        disponible: false,
        tardoMs: Date.now() - inicio,
        ultimoRespaldo,
        mensaje:
          err && err.name === 'ConnectionError'
            ? 'No se pudo conectar al motor de base de datos.'
            : err.message,
      };
    }
  },
};
