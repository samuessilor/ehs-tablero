/* ===========================================================================
   02_vistas.sql - puerto a Postgres (Neon) de todas las vistas del schema ehs

   Fuente: migraciones\0001 a \0021 (SQL Server). Varias vistas se redefinen
   mas de una vez con "create or alter view" - aqui se porta SIEMPRE la
   version de la migracion MAS RECIENTE que toca cada vista, nunca una
   intermedia. El listado completo, vista por vista, esta al final del
   archivo en un comentario.

   Ninguna regla de negocio cambia en la traduccion. Las tres reglas de
   ehs\CLAUDE.md ("Tres reglas que no se negocian") siguen literales:
     1. YTD = suma de numeradores / suma de denominadores, enero a corte.
     2. Los agregados suman magnitudes crudas de TODOS los sitios del
        ambito y dividen al final.
     3. Un mes cuenta para un ambito solo si TODOS los sitios de ese ambito
        que reportaron ESE ANIO lo reportaron (ehs.v_lectura_ambito).

   Supuestos de tipos (decididos aqui porque esta vista-file no crea tablas,
   solo las consulta; si 01_tablas.sql elige otro tipo para alguna columna,
   ajustar el punto marcado abajo):
     - Las columnas bit de SQL Server (activo, en_nacional, en_nacional_labs,
       en_colombia_peru, requerida_colombia, vigente, resuelto) se asumen
       mapeadas a boolean en Postgres. Donde el original comparaba "= 1"/"= 0"
       contra una de estas columnas de TABLA, aqui se usa la columna como
       boolean (where activo / where not resuelto). Donde el "0"/"1" es un
       valor calculado por la propia vista (tiene_lectura, es_pico, completo)
       se deja como entero literal: ahi no hay una columna bit de por medio,
       es el mismo contrato que ya consume el API del tablero.
     - capturado_en/modificado_en/reemplazado_en/confirmado_en (datetime2 sin
       zona horaria = hora de pared de Colombia) se leen tal cual de las
       tablas; ninguna vista de aqui construye una columna de hora nueva, asi
       que no hay timestamptz que evitar en este archivo (si se agrega una
       vista que SI calcule una marca de tiempo, usar timestamp, nunca
       timestamptz - ver ehs\CLAUDE.md regla 6).

   Conversion de sintaxis aplicada:
     - create or alter view  -> create or replace view
     - alias de columna "col = expr" (T-SQL) -> "expr as col" (todas las
       vistas de 0006/0010/0011/0015 la usan en alguna columna)
     - isnull(x,y)                    -> coalesce(x,y)
     - 'texto' + expr                 -> concat(...) o || (ya varias vistas
       usaban concat(), que es identico en Postgres; solo v_estado_agua_diaria
       concatenaba con + y pasa a ||)
     - cast(x as varchar(n))          -> x::varchar(n)
     - year(fecha) / month(fecha)     -> extract(year|month from fecha)::int
     - datediff(day, a, b)            -> resta de date (entero de dias)
     - sysdatetime()/getdate()        -> now() / current_date (no hace falta
       en ninguna vista de este archivo: no crean columnas de hora nuevas)
     - tinyint                        -> smallint (Postgres no tiene tinyint)
     - format(n, '#,0')               -> to_char(n, 'FM999,999,999')
     - percentile_cont(...) OVER(...) -> Postgres NO permite agregados de
       conjunto ordenado (percentile_cont) como funcion de ventana (OVER).
       v_agua_diaria se reescribe calculando la mediana con GROUP BY en vez
       de windowing + distinct: mismo resultado (una mediana por sitio-mes),
       sintaxis que Postgres si soporta.
   =========================================================================== */

set search_path = ehs, ref, ops, public;

/* ---------------------------------------------------------------- ambitos ---
   Expande cada sitio a los ambitos a los que pertenece, para que un solo
   group by produzca sitio y agregado sin duplicar logica.
   Version final: migracion 0011 (agrega el ambito 'colombia_peru' y
   renombra la etiqueta de 'nacional' a 'Colombia'). */
create or replace view ehs.v_ambito
as
    select sitio_id, sitio_id::varchar(20) as ambito_id,
           sitio_corto as ambito, 1 as orden
      from ref.dim_sitio
     where activo
    union all
    select sitio_id, 'nacional_labs', 'Nacional Labs', 2
      from ref.dim_sitio
     where activo and en_nacional_labs
    union all
    select sitio_id, 'nacional', 'Colombia', 3
      from ref.dim_sitio
     where activo and en_nacional
    union all
    select sitio_id, 'colombia_peru', 'Colombia + Peru', 4
      from ref.dim_sitio
     where activo and en_colombia_peru;


/* ------------------------------------------------------- lectura por ambito ---
   La lectura cruda, repetida por cada ambito al que suma. Es el paso que hace
   que sumar magnitudes y dividir al final salga solo.
   Version final: migracion 0021 - regla de negocio 3: un mes cuenta para un
   ambito solo si TODOS los sitios de ese ambito QUE REPORTARON ESE ANIO lo
   reportaron (no "todos los sitios del ambito a secas": Peru no tiene
   lecturas de 2024 ni 2025). El NOT EXISTS anidado se porta literal. */
create or replace view ehs.v_lectura_ambito
as
    select f.anio, f.num_mes, f.fecha,
           a.ambito_id, a.ambito,
           l.magnitud_id, l.valor
      from ehs.hecho_lectura_mensual l
      join ref.dim_fecha  f on f.fecha = l.fecha
      join ehs.v_ambito   a on a.sitio_id = l.sitio_id
     /* no hay un sitio del ambito que haya reportado este anio y no este mes */
     where not exists (
            select 1
              from ehs.v_ambito am
             where am.ambito_id = a.ambito_id
               and exists (select 1
                             from ehs.hecho_lectura_mensual ly
                             join ref.dim_fecha fy on fy.fecha = ly.fecha
                            where ly.sitio_id = am.sitio_id and fy.anio = f.anio)
               and not exists (select 1
                                 from ehs.hecho_lectura_mensual lm
                                where lm.sitio_id = am.sitio_id and lm.fecha = l.fecha));


/* ------------------------------------------------------------ KPI mensual ---
   REGLA 2: se suman las magnitudes crudas del numerador y del denominador y
   se divide al final. Nunca se promedia un ratio.
   Version final: migracion 0010 - un KPI solo se trata como conteo (sin
   dividir) si ref.kpi_magnitud dice que no tiene denominador; si el KPI SI
   tiene denominador pero este mes falta, el resultado es NULL ("sin dato"),
   nunca el numerador crudo. */
create or replace view ehs.v_kpi_mensual
as
    with numerador as (
        select la.anio, la.num_mes, la.ambito_id, km.kpi_id,
               sum(la.valor) as valor
          from ehs.v_lectura_ambito la
          join ref.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id and km.rol = 'numerador'
         group by la.anio, la.num_mes, la.ambito_id, km.kpi_id
    ),
    denominador as (
        select la.anio, la.num_mes, la.ambito_id, km.kpi_id,
               sum(la.valor) as valor
          from ehs.v_lectura_ambito la
          join ref.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id and km.rol = 'denominador'
         group by la.anio, la.num_mes, la.ambito_id, km.kpi_id
    )
    select n.anio,
           n.num_mes,
           n.ambito_id,
           n.kpi_id,
           n.valor                                as numerador,
           d.valor                                as denominador,
           case when not exists (select 1 from ref.kpi_magnitud c
                                  where c.kpi_id = n.kpi_id and c.rol = 'denominador')
                     then n.valor * k.factor
                when d.valor is null or d.valor = 0 then null
                /* el cast antes de dividir no es decorativo: sin el, la division
                   trunca el septimo decimal en vez de redondearlo (ver el
                   comentario original en la migracion 0006). */
                else (n.valor * k.factor)::decimal(24,6) / d.valor
           end                                    as valor
      from numerador n
      join ref.dim_kpi k on k.kpi_id = n.kpi_id
      left join denominador d
             on d.anio = n.anio and d.num_mes = n.num_mes
            and d.ambito_id = n.ambito_id and d.kpi_id = n.kpi_id;


/* ---------------------------------------------------------------- KPI YTD ---
   REGLA 1: acumulado de enero al mes de corte, sumando numeradores y
   denominadores y dividiendo al final. Un mes de baja produccion pesa menos,
   que es justamente lo correcto.
   Version final: migracion 0010 (mismo ajuste "sin denominador = sin dato"
   que v_kpi_mensual). */
create or replace view ehs.v_kpi_ytd
as
    select m.anio,
           corte.num_mes                          as num_mes_corte,
           m.ambito_id,
           m.kpi_id,
           sum(m.numerador)                       as numerador,
           sum(m.denominador)                     as denominador,
           case when max(k.factor) is null then null
                when not exists (select 1 from ref.kpi_magnitud c
                                  where c.kpi_id = m.kpi_id and c.rol = 'denominador')
                     then sum(m.numerador) * max(k.factor)
                when sum(m.denominador) is null or sum(m.denominador) = 0 then null
                else (sum(m.numerador) * max(k.factor))::decimal(24,6)
                     / sum(m.denominador)
           end                                    as valor
      from ehs.v_kpi_mensual m
      join ref.dim_kpi k on k.kpi_id = m.kpi_id
      cross join (select distinct num_mes from ref.dim_fecha) corte
     where m.num_mes <= corte.num_mes
     group by m.anio, corte.num_mes, m.ambito_id, m.kpi_id;


/* ----------------------------------------------------- cual es el corte publicado ---
   Un mes es corte cuando TODOS los sitios que capturan cada mes (en_nacional = 1)
   tienen TODAS las magnitudes que son parte del reporte regular de Colombia
   (requerida_colombia = 1). El corte es el ultimo mes M tal que 1..M estan
   completos (un hueco en un mes anterior frena la publicacion aunque meses
   posteriores si esten completos).
   Version final: migracion 0011 (agrega el filtro requerida_colombia: Peru y
   el historico reportan residuo_total_kg, que Celta/Estrella/Agencias jamas
   capturan, y sin este filtro ningun mes de Colombia volveria a verse
   completo). */
create or replace view ehs.v_corte_publicado
as
    with esperadas as (
        select (select count(*) from ref.dim_sitio
                 where activo and en_nacional)
             * (select count(*) from ref.dim_magnitud
                 where area = 'ehs' and requerida_colombia)          as total
    ),
    por_mes as (
        select f.anio,
               f.num_mes,
               count(*)                                               as lecturas,
               case when count(*) >= (select total from esperadas)
                    then 1 else 0 end                                 as completo
          from ehs.hecho_lectura_mensual l
          join ref.dim_fecha f    on f.fecha = l.fecha
          join ref.dim_sitio s    on s.sitio_id = l.sitio_id
                                 and s.activo and s.en_nacional
          join ref.dim_magnitud g on g.magnitud_id = l.magnitud_id
                                 and g.area = 'ehs' and g.requerida_colombia
         group by f.anio, f.num_mes
    ),
    /* el primer mes del anio que NO esta completo: el corte es el mes anterior. */
    primer_hueco as (
        select a.anio, min(m.num_mes) as primero
          from (select distinct anio from por_mes) a
         cross join (select distinct num_mes from ref.dim_fecha) m
          left join por_mes p
                 on p.anio = a.anio and p.num_mes = m.num_mes and p.completo = 1
         where p.num_mes is null
         group by a.anio
    )
    select p.anio,
           case when coalesce(h.primero, 13) > 1
                then (coalesce(h.primero, 13) - 1)::smallint end      as corte,
           max(p.num_mes)                                             as ultimo_visto,
           case when max(p.num_mes) > coalesce(h.primero, 13) - 1
                then max(p.num_mes) end                                as en_curso,
           (select total from esperadas)                               as esperadas_por_mes
      from por_mes p
      left join primer_hueco h on h.anio = p.anio
     group by p.anio, h.primero;


/* ------------------------------------------------------ KPI contra su meta ---
   La meta se resuelve en tres casos: sin meta, meta = 0 (solo cumple en 0 o
   menos) y el semaforo normal (techo: incumple por encima, riesgo del 90% al
   100%, cumple por debajo). Version final: migracion 0010 - mismo semaforo y
   mismos codigos que usa el API del tablero (src/datos/adaptador_sql.js). */
create or replace view ehs.v_kpi_contra_meta
as
    select y.anio,
           y.num_mes_corte,
           y.ambito_id,
           y.kpi_id,
           y.valor,
           mt.valor                               as meta,
           case when mt.valor is null or mt.valor = 0 or y.valor is null then null
                else round((y.valor - mt.valor) / mt.valor, 6)
           end                                    as brecha_pct,
           case when mt.valor is null then 'sin_meta'
                when mt.valor = 0 then case when coalesce(y.valor, 0) <= 0
                                            then 'cumple' else 'incumple' end
                when y.valor is null then 'sin_dato'
                when y.valor > mt.valor then 'incumple'
                when y.valor >= mt.valor * 0.90 then 'riesgo'
                else 'cumple'
           end                                    as estado
      from ehs.v_kpi_ytd y
      left join ehs.meta mt
             on mt.anio      = y.anio
            and mt.ambito_id = y.ambito_id
            and mt.kpi_id    = y.kpi_id
            and mt.vigente;


/* --------------------------------------------------- avisos automaticos de calidad ---
   Corre sobre cualquier corte y avisa si algo del dato de ESTE mes se ve
   raro: valores negativos, denominadores en cero, saltos atipicos (lag()
   contra el mes anterior DENTRO DEL MISMO ANIO) y sitios que no reportaron
   un mes que otros si.
   Version final: migracion 0015 - agrega 'anio' a la particion del lag(): sin
   esto, desde que hay historico 2023-2025 cargado, enero de 2026 comparaba
   contra diciembre de otro anio. */
create or replace view ehs.v_calidad_avisos
as
    with valores as (
        select f.anio, f.num_mes as mes, s.sitio_id, m.magnitud_id, l.valor,
               lag(l.valor) over (partition by s.sitio_id, m.magnitud_id, f.anio
                                   order by f.num_mes)               as valor_anterior,
               lag(f.num_mes) over (partition by s.sitio_id, m.magnitud_id, f.anio
                                     order by f.num_mes)             as mes_anterior
          from ehs.hecho_lectura_mensual l
          join ref.dim_fecha f on f.fecha = l.fecha
          join ref.dim_sitio s on s.sitio_id = l.sitio_id
          join ref.dim_magnitud m on m.magnitud_id = l.magnitud_id
    )
    select anio, mes, sitio_id, magnitud_id,
           'error'            as gravedad, 'valor_negativo' as codigo,
           concat(sitio_id, ', mes ', mes, ': ', magnitud_id, ' viene en ',
                  valor, ', y esta magnitud no puede ser negativa.')     as mensaje
      from valores
     where valor < 0
    union all
    select anio, mes, sitio_id, magnitud_id,
           'error'            as gravedad, 'denominador_invalido' as codigo,
           concat(sitio_id, ', mes ', mes, ': ', magnitud_id, ' en cero; los ',
                  'indicadores que dividen por esta magnitud no se pueden calcular.') as mensaje
      from valores
     where valor = 0 and magnitud_id in ('unidades_buenas', 'horas_fijos')
    union all
    select anio, mes, sitio_id, magnitud_id,
           'aviso'            as gravedad, 'salto_atipico' as codigo,
           concat(sitio_id, ', mes ', mes, ': ', magnitud_id, ' paso de ',
                  valor_anterior, ' (mes ', mes_anterior, ') a ', valor, ' (',
                  case when valor > valor_anterior then '+' else '' end,
                  round((valor - valor_anterior) / nullif(valor_anterior, 0) * 100, 0)::int,
                  '%). Conviene confirmar el dato.')                     as mensaje
      from valores
     where valor_anterior is not null
       and magnitud_id <> 'accidentes_dafw'  -- pasar de 0 a 1 es lo esperado, no una anomalia
       /* nullif y no 'valor_anterior <> 0' delante: el motor no garantiza evaluar
          los predicados del where en el orden en que estan escritos. */
       and abs((valor - valor_anterior) / nullif(valor_anterior, 0)) > 0.4
    union all
    select f.anio, f.num_mes as mes, s.sitio_id, null::varchar(40) as magnitud_id,
           'error'            as gravedad, 'mes_incompleto' as codigo,
           concat(s.sitio_id, ' no reporto el mes ', f.num_mes,
                  ', pero otros sitios si. El consolidado de ese mes queda sesgado.') as mensaje
      from ref.dim_fecha f
     cross join ref.dim_sitio s
     where s.activo
       and s.en_nacional
       and f.num_mes <= coalesce((select c.corte from ehs.v_corte_publicado c
                                   where c.anio = f.anio), 0)
       and exists (select 1 from ehs.hecho_lectura_mensual l2
                    join ref.dim_fecha f2 on f2.fecha = l2.fecha
                   where f2.num_mes = f.num_mes and f2.anio = f.anio and l2.sitio_id <> s.sitio_id)
       and not exists (select 1 from ehs.hecho_lectura_mensual l3
                        join ref.dim_fecha f3 on f3.fecha = l3.fecha
                       where f3.num_mes = f.num_mes and f3.anio = f.anio and l3.sitio_id = s.sitio_id);


/* --------------------------------------------------------- calidad del dato ---
   Que mes trae lectura, de que magnitud, de que sitio y de que origen. Hace
   visible un mes que falta como hueco, no como cero.
   Version final: migracion 0006 (nunca redefinida despues). */
create or replace view ehs.v_calidad_dato
as
    select f.anio, f.num_mes, f.mes, f.mes_corto,
           s.sitio_id, s.sitio_corto,
           m.magnitud_id, m.magnitud, m.unidad,
           l.valor, l.origen, l.estado,
           l.capturado_por, l.capturado_en,
           case when l.lectura_id is null then 0 else 1 end as tiene_lectura
      from ref.dim_fecha f
     cross join ref.dim_sitio s
     cross join ref.dim_magnitud m
      left join ehs.hecho_lectura_mensual l
             on l.fecha = f.fecha and l.sitio_id = s.sitio_id
            and l.magnitud_id = m.magnitud_id
     where s.activo
       and m.area = 'ehs';


/* ------------------------------------------------------- estado de la captura ---
   Lo que falta por capturar del mes en curso: cuantas de las magnitudes
   esperadas ya tiene cada sitio.
   Version final: migracion 0011 (esperadas cuenta solo magnitudes con
   requerida_colombia = 1, mismo ajuste que v_corte_publicado). */
create or replace view ehs.v_captura_estado
as
    select f.anio,
           f.num_mes,
           s.sitio_id,
           s.sitio                        as sitio_nombre,
           count(l.lectura_id)            as capturadas,
           (select count(*) from ref.dim_magnitud
             where area = 'ehs' and requerida_colombia)  as esperadas,
           max(l.capturado_en)            as ultima_captura,
           max(l.capturado_por)           as ultimo_capturador
      from ref.dim_fecha f
     cross join ref.dim_sitio s
      left join ehs.hecho_lectura_mensual l
             on l.fecha = f.fecha and l.sitio_id = s.sitio_id
     where s.activo and s.en_nacional
     group by f.anio, f.num_mes, s.sitio_id, s.sitio;


/* ------------------------------------------ el valor que dejo CADA correccion ---
   Cada fila de la historia guarda el valor ANTERIOR a un cambio. El valor que
   ese cambio dejo es el anterior de la version siguiente, o el valor actual
   de la lectura si fue el ultimo cambio.
   Version final: migracion 0010 (antes de este arreglo, con dos correcciones
   seguidas la primera salia con el valor de la segunda). */
create or replace view ehs.v_correcciones
as
    with versiones as (
        select h.hist_id, h.lectura_id, h.fecha, h.sitio_id, h.magnitud_id,
               h.valor_anterior, h.motivo, h.reemplazado_por, h.reemplazado_en,
               lead(h.valor_anterior)
                   over (partition by h.lectura_id
                         order by h.reemplazado_en, h.hist_id)        as siguiente
          from ehs.hecho_lectura_mensual_hist h
    )
    select v.hist_id,
           v.fecha, f.anio, f.num_mes as mes,
           v.sitio_id, s.sitio_corto,
           v.magnitud_id, m.magnitud,
           v.valor_anterior,
           coalesce(v.siguiente, l.valor)          as valor_corregido,
           v.motivo,
           v.reemplazado_por                       as autorizado_por,
           v.reemplazado_en                        as corregido_en
      from versiones v
      join ehs.hecho_lectura_mensual l on l.lectura_id = v.lectura_id
      join ref.dim_fecha f    on f.fecha = v.fecha
      join ref.dim_sitio s    on s.sitio_id = v.sitio_id
      join ref.dim_magnitud m on m.magnitud_id = v.magnitud_id
     where v.motivo is not null;


/* ------------------------------------------------------------- agua diaria ---
   Marca los dias fuera de banda contra la MEDIANA DEL PROPIO MES (sitio x
   anio x mes), no contra una constante.
   Version final: migracion 0006 (nunca redefinida despues). Reescrita para
   Postgres: el original calculaba la mediana con percentile_cont(...) OVER
   (partition by ...) y luego hacia select distinct para quedarse con una
   fila por grupo. Postgres no permite un agregado de conjunto ordenado
   (percentile_cont) como funcion de ventana (OVER); aqui se calcula la misma
   mediana por sitio-mes con GROUP BY directo, sin el distinct intermedio.
   Resultado identico: una mediana por sitio-anio-mes. */
create or replace view ehs.v_agua_diaria
as
    with mediana as (
        select sitio_id,
               extract(year  from fecha)::int as anio,
               extract(month from fecha)::int as num_mes,
               percentile_cont(0.5) within group (order by consumo_m3) as mediana_m3
          from ehs.hecho_lectura_diaria_agua
         group by sitio_id, extract(year from fecha), extract(month from fecha)
    )
    select d.fecha, d.sitio_id, s.sitio_corto, d.consumo_m3, d.observacion,
           u.mediana_m3,
           case when u.mediana_m3 is null or u.mediana_m3 = 0 then null
                else (d.consumo_m3 - u.mediana_m3) / u.mediana_m3
           end                                    as desviacion,
           case when u.mediana_m3 is null or u.mediana_m3 = 0 then 0
                when abs(d.consumo_m3 - u.mediana_m3) / u.mediana_m3 > 0.15 then 1
                else 0
           end                                    as es_pico
      from ehs.hecho_lectura_diaria_agua d
      join ref.dim_sitio s on s.sitio_id = d.sitio_id
      left join mediana u
             on u.sitio_id = d.sitio_id
            and u.anio     = extract(year  from d.fecha)::int
            and u.num_mes  = extract(month from d.fecha)::int;


/* ----------------------------------------------------------- estado diario ---
   El rotulo de pendiente lo decide el conteo de filas, no una constante.
   Version final: migracion 0006 (nunca redefinida despues). */
create or replace view ehs.v_estado_agua_diaria
as
    select count(*)                                                       as filas,
           case when count(*) = 0
                then '0 lecturas diarias'
                else to_char(count(*), 'FM999,999,999') || ' lecturas diarias' end as estado
      from ehs.hecho_lectura_diaria_agua;


/* ------------------------------------------------ lo rechazado, a la vista ---
   Que se quedo fuera, por que, y desde cuando. Con la tabla vacia devuelve
   cero filas, que es lo correcto.
   Version final: migracion 0006 (nunca redefinida despues). */
create or replace view ehs.v_rechazo_pendiente
as
    select r.rechazo_id,
           r.detectado_en,
           r.origen,
           r.motivo,
           r.sitio_texto                              as sitio,
           r.magnitud_texto                            as magnitud,
           r.fecha_texto                               as fecha,
           r.valor_texto                               as valor,
           (current_date - r.detectado_en::date)       as dias_abierto
      from ops.lectura_rechazada r
     where not r.resuelto;


/* ===========================================================================
   Procedencia de cada vista (migracion cuya version es la que quedo arriba)
   ---------------------------------------------------------------------------
   ehs.v_ambito              -> 0011_ehs_colombia_peru_estructura.sql
                                 (definida en 0006, redefinida en 0011)
   ehs.v_lectura_ambito      -> 0021_ehs_mes_completo_por_ambito.sql
                                 (definida en 0006, redefinida en 0021)
   ehs.v_kpi_mensual         -> 0010_ehs_consistencia.sql
                                 (definida en 0006, redefinida en 0010)
   ehs.v_kpi_ytd             -> 0010_ehs_consistencia.sql
                                 (definida en 0006, redefinida en 0010)
   ehs.v_corte_publicado     -> 0011_ehs_colombia_peru_estructura.sql
                                 (definida en 0006, redefinida en 0010 y 0011)
   ehs.v_kpi_contra_meta     -> 0010_ehs_consistencia.sql
                                 (definida en 0006, redefinida en 0010)
   ehs.v_calidad_avisos      -> 0015_ehs_residuo_una_forma.sql
                                 (definida en 0006, redefinida en 0015)
   ehs.v_calidad_dato        -> 0006_ehs_vistas.sql (nunca redefinida)
   ehs.v_captura_estado      -> 0011_ehs_colombia_peru_estructura.sql
                                 (definida en 0007, redefinida en 0010 y 0011)
   ehs.v_correcciones        -> 0010_ehs_consistencia.sql
                                 (definida en 0009, redefinida en 0010)
   ehs.v_agua_diaria         -> 0006_ehs_vistas.sql (nunca redefinida)
   ehs.v_estado_agua_diaria  -> 0006_ehs_vistas.sql (nunca redefinida)
   ehs.v_rechazo_pendiente   -> 0006_ehs_vistas.sql (nunca redefinida)

   Dudas reales sin resolver
   ---------------------------------------------------------------------------
   1. Tipo de las columnas "bit" en Postgres (activo, en_nacional,
      en_nacional_labs, en_colombia_peru, requerida_colombia, vigente,
      resuelto). Este archivo asume boolean y escribe "where activo" /
      "where not resuelto" en vez de "= 1" / "= 0". Si 01_tablas.sql las deja
      como smallint (0/1) en vez de boolean, hay que revertir estas
      comparaciones a "= 1" / "= 0" en las vistas marcadas arriba
      (v_ambito, v_corte_publicado, v_kpi_contra_meta, v_calidad_avisos,
      v_calidad_dato, v_captura_estado, v_rechazo_pendiente).
   2. to_char(count(*), 'FM999,999,999') en v_estado_agua_diaria asume coma
      como separador de miles fijo (igual que el '#,0' original). Si Neon
      corre con un lc_numeric distinto esto no cambia, porque el patron usa
      la coma literal y no "G" (que si seria sensible al locale) - lo dejo
      anotado por si se prefiere confirmar con una fila real una vez
      cargados los datos.
   3. v_agua_diaria quedo reescrita (window -> GROUP BY) porque Postgres no
      soporta percentile_cont(...) OVER(...). El resultado matematico es el
      mismo (una mediana por sitio-anio-mes), pero no es un calco literal del
      SQL Server como el resto del archivo: vale la pena que alguien la
      revise una vez con datos reales de ehs.hecho_lectura_diaria_agua (hoy
      vacia en todos los ambientes vistos) antes de confiar en ella en
      produccion.
   =========================================================================== */
