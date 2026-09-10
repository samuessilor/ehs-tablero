/* ===========================================================================
   EHS · vistas analiticas

   Aqui viven las DOS REGLAS DE CALCULO del area, una sola vez:

     1. YTD = suma de numeradores / suma de denominadores, de enero al mes de corte.
        Nunca el promedio de las razones mensuales.
     2. Los agregados se construyen sumando magnitudes crudas y dividiendo AL FINAL.
        El ratio nacional NO es el promedio de los ratios de los sitios.

   Hoy esas reglas estan implementadas tres veces: en Python (el motor de
   validacion), en DAX (el modelo de Power BI) y en JavaScript (las webs). Tres
   implementaciones de la misma regla son tres oportunidades de divergir. Estas
   vistas existen para que quede una, y para que las otras lean de ella.
   =========================================================================== */

/* ---------------------------------------------------------------- ambitos ---
   Expande cada sitio a los ambitos a los que pertenece, para que un solo
   group by produzca sitio y agregado sin duplicar logica. */
create or alter view ehs.v_ambito
as
    select sitio_id, cast(sitio_id as varchar(20)) as ambito_id,
           sitio_corto as ambito, 1 as orden
      from ehs.dim_sitio
     where activo = 1
    union all
    select sitio_id, 'nacional_labs', 'Nacional Labs', 2
      from ehs.dim_sitio
     where activo = 1 and en_nacional_labs = 1
    union all
    select sitio_id, 'nacional', 'Nacional Labs + Agencias', 3
      from ehs.dim_sitio
     where activo = 1 and en_nacional = 1;
go

/* ------------------------------------------------------- lectura por ambito ---
   La lectura cruda, repetida por cada ambito al que suma. Es el paso que hace
   que sumar magnitudes y dividir al final salga solo. */
create or alter view ehs.v_lectura_ambito
as
    select f.anio, f.num_mes, f.fecha,
           a.ambito_id, a.ambito,
           l.magnitud_id, l.valor
      from ehs.hecho_lectura_mensual l
      join ehs.dim_fecha  f on f.fecha = l.fecha
      join ehs.v_ambito   a on a.sitio_id = l.sitio_id;
go

/* ------------------------------------------------------------ KPI mensual ---
   REGLA 2: se suman las magnitudes crudas del numerador y del denominador y se
   divide al final. Nunca se promedia un ratio. */
create or alter view ehs.v_kpi_mensual
as
    with numerador as (
        select la.anio, la.num_mes, la.ambito_id, km.kpi_id,
               sum(la.valor) as valor
          from ehs.v_lectura_ambito la
          join ehs.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id and km.rol = 'numerador'
         group by la.anio, la.num_mes, la.ambito_id, km.kpi_id
    ),
    denominador as (
        select la.anio, la.num_mes, la.ambito_id, km.kpi_id,
               sum(la.valor) as valor
          from ehs.v_lectura_ambito la
          join ehs.kpi_magnitud km
            on km.magnitud_id = la.magnitud_id and km.rol = 'denominador'
         group by la.anio, la.num_mes, la.ambito_id, km.kpi_id
    )
    select n.anio,
           n.num_mes,
           n.ambito_id,
           n.kpi_id,
           n.valor                                as numerador,
           d.valor                                as denominador,
           /* un KPI sin denominador es un conteo (accidentes DAFW): su valor es
              el numerador por el factor. Con denominador cero el ratio se
              indefine y se devuelve NULL, jamas infinito ni cero. */
           case when d.valor is null then n.valor * k.factor
                when d.valor = 0     then null
                /* El cast NO es decorativo, y sin el la vista publica un numero
                   distinto al del motor validado.

                   n.valor es decimal(18,4) y k.factor es decimal(18,6), asi que el
                   producto sale decimal(38,10). Al dividir eso entre decimal(18,4),
                   SQL Server recorta la escala del resultado a 6 y TRUNCA el septimo
                   digito en vez de redondearlo. El agua de nacional en marzo vale
                   5,5946509678...; la vista publicaba 5,594650, que redondeado a los
                   cuatro decimales del reporte da 5,5946 en vez de 5,5947.

                   Casteando el producto a (24,6) queda sitio para 16 decimales en el
                   cociente y el redondeo final cae del lado correcto. Los factores
                   son 1, 1000 y 1000000 —enteros—, asi que el cast no pierde nada
                   del producto.

                   Eran 4 valores de 350 en el corte de julio. Ninguno cambia una
                   decision, y aun asi hay que arreglarlo: el compromiso del proyecto
                   es que la vista y el motor den lo MISMO, no algo parecido. */
                else cast(n.valor * k.factor as decimal(24,6)) / d.valor
           end                                    as valor
      from numerador n
      join ehs.dim_kpi k on k.kpi_id = n.kpi_id
      left join denominador d
             on d.anio = n.anio and d.num_mes = n.num_mes
            and d.ambito_id = n.ambito_id and d.kpi_id = n.kpi_id;
go

/* ---------------------------------------------------------------- KPI YTD ---
   REGLA 1: acumulado de enero al mes de corte, sumando numeradores y
   denominadores y dividiendo al final. Un mes de baja produccion pesa menos,
   que es justamente lo correcto. */
create or alter view ehs.v_kpi_ytd
as
    select m.anio,
           corte.num_mes                          as num_mes_corte,
           m.ambito_id,
           m.kpi_id,
           sum(m.numerador)                       as numerador,
           sum(m.denominador)                     as denominador,
           case when max(k.factor) is null then null
                when sum(m.denominador) is null then sum(m.numerador) * max(k.factor)
                when sum(m.denominador) = 0     then null
                /* Mismo cast y por lo mismo que en ehs.v_kpi_mensual: sin el, la
                   division trunca el septimo decimal en vez de redondearlo. */
                else cast(sum(m.numerador) * max(k.factor) as decimal(24,6))
                     / sum(m.denominador)
           end                                    as valor
      from ehs.v_kpi_mensual m
      join ehs.dim_kpi k on k.kpi_id = m.kpi_id
      cross join (select distinct num_mes from ehs.dim_fecha) corte
     where m.num_mes <= corte.num_mes
     group by m.anio, corte.num_mes, m.ambito_id, m.kpi_id;
go

/* ------------------------------------------------------ KPI contra su meta ---
   La meta se resuelve en tres casos, y el tercero importa: el scorecard publica
   meta por sitio y una consolidada de COLOMBIA y PERU, pero NINGUNA para un
   subconjunto como Nacional Labs. En ese caso no hay meta y se dice, no se
   hereda la del consolidado ni se inventa. */
create or alter view ehs.v_kpi_contra_meta
as
    select y.anio,
           y.num_mes_corte,
           y.ambito_id,
           y.kpi_id,
           y.valor,
           mt.valor                               as meta,
           case when mt.valor is null or mt.valor = 0 then null
                else (y.valor - mt.valor) / mt.valor
           end                                    as brecha_pct,
           case when mt.valor is null            then 'sin meta'
                when y.valor <= mt.valor         then 'cumple'
                when y.valor <= mt.valor * 1.05  then 'en riesgo'
                else 'incumple'
           end                                    as estado
      from ehs.v_kpi_ytd y
      left join ehs.meta mt
             on mt.anio      = y.anio
            and mt.ambito_id = y.ambito_id
            and mt.kpi_id    = y.kpi_id
            and mt.vigente   = 1;
go

/* --------------------------------------------------------- calidad del dato ---
   Que mes trae lectura, de que magnitud, de que sitio y de que origen. Es la
   vista que hace VISIBLE el defecto original: un mes que falta se ve como hueco,
   no como cero. */
create or alter view ehs.v_calidad_dato
as
    select f.anio, f.num_mes, f.mes, f.mes_corto,
           s.sitio_id, s.sitio_corto,
           m.magnitud_id, m.magnitud, m.unidad,
           l.valor, l.origen, l.estado,
           l.capturado_por, l.capturado_en,
           case when l.lectura_id is null then 0 else 1 end as tiene_lectura
      from ehs.dim_fecha f
     cross join ehs.dim_sitio s
     cross join ehs.dim_magnitud m
      left join ehs.hecho_lectura_mensual l
             on l.fecha = f.fecha and l.sitio_id = s.sitio_id
            and l.magnitud_id = m.magnitud_id
     where s.activo = 1
       and m.area = 'ehs';
go

/* --------------------------------------------------- avisos automaticos de calidad ---
   Distinto de un "hallazgo" del libro heredado (que describe un hecho puntual y va
   escrito a mano, porque un validador no puede redescubrir que una celda especifica
   se escribio a mano): esto corre sobre CUALQUIER corte y avisa si algo del dato de
   ESTE mes se ve raro. Portado del validador que traia el tablero anterior del area
   (kpi-dashboard\app\src\motor\validacion.ts), que lo tenia y la primera version de
   este no.

   Lo que "medicion_duplicada" comprobaba en TypeScript aqui no hace falta: la
   restriccion uq_lectura_mensual (fecha, sitio_id, magnitud_id) de 01-esquema.sql ya
   hace estructuralmente imposible que exista. Una regla que la base impone no necesita
   una vista que la vigile. */
create or alter view ehs.v_calidad_avisos
as
    with valores as (
        select f.anio, f.num_mes as mes, s.sitio_id, m.magnitud_id, l.valor,
               lag(l.valor) over (partition by s.sitio_id, m.magnitud_id
                                   order by f.num_mes)               as valor_anterior,
               lag(f.num_mes) over (partition by s.sitio_id, m.magnitud_id
                                     order by f.num_mes)             as mes_anterior
          from ehs.hecho_lectura_mensual l
          join ehs.dim_fecha f on f.fecha = l.fecha
          join ehs.dim_sitio s on s.sitio_id = l.sitio_id
          join ehs.dim_magnitud m on m.magnitud_id = l.magnitud_id
    )
    select anio, mes, sitio_id, magnitud_id,
           gravedad = 'error', codigo = 'valor_negativo',
           mensaje = concat(sitio_id, ', mes ', mes, ': ', magnitud_id, ' viene en ',
                             valor, ', y esta magnitud no puede ser negativa.')
      from valores
     where valor < 0
    union all
    select anio, mes, sitio_id, magnitud_id,
           gravedad = 'error', codigo = 'denominador_invalido',
           mensaje = concat(sitio_id, ', mes ', mes, ': ', magnitud_id, ' en cero; los ',
                             'indicadores que dividen por esta magnitud no se pueden calcular.')
      from valores
     where valor = 0 and magnitud_id in ('unidades_buenas', 'horas_fijos')
    union all
    select anio, mes, sitio_id, magnitud_id,
           gravedad = 'aviso', codigo = 'salto_atipico',
           mensaje = concat(sitio_id, ', mes ', mes, ': ', magnitud_id, ' paso de ',
                             valor_anterior, ' (mes ', mes_anterior, ') a ', valor, ' (',
                             case when valor > valor_anterior then '+' else '' end,
                             cast(round((valor - valor_anterior) / nullif(valor_anterior, 0) * 100, 0) as int),
                             '%). Conviene confirmar el dato.')
      from valores
     where valor_anterior is not null
       and magnitud_id <> 'accidentes_dafw'  -- pasar de 0 a 1 caso es lo esperado, no una anomalia
       /* nullif y no 'valor_anterior <> 0' delante, aunque parezca que basta.
          SQL Server NO garantiza que evalue los predicados del where en el orden en
          que estan escritos: puede resolver la division antes que el filtro. Con
          'valor_anterior <> 0' aqui, la vista lanzaba «Divide by zero error
          encountered» al consultarla, porque horas_temp vale 0 todos los meses en
          Celta y La Estrella. Estuvo asi desde que se escribio y no se vio porque
          nadie la habia ejecutado: la prueba en DuckDB no reproduce esa evaluacion.
          Con nullif la division devuelve null, y null > 0.4 es falso, que es
          justamente lo que se queria decir. */
       and abs((valor - valor_anterior) / nullif(valor_anterior, 0)) > 0.4
    union all
    select f.anio, f.num_mes as mes, s.sitio_id, magnitud_id = cast(null as varchar(40)),
           gravedad = 'error', codigo = 'mes_incompleto',
           mensaje = concat(s.sitio_id, ' no reporto el mes ', f.num_mes,
                             ', pero otros sitios si. El consolidado de ese mes queda sesgado.')
      from ehs.dim_fecha f
     cross join ehs.dim_sitio s
     where s.activo = 1
       /* en_nacional = 1, no solo activo. dim_sitio guarda ademas 'peru' y
          'colombia_peru', que existen para el scorecard corporativo anual y no
          capturan magnitudes mensuales. Sin este filtro la vista denunciaba que
          'peru no reporto el mes 1' catorce veces —dos sitios por siete meses— y
          los rotulaba como ERROR. Eran el 58% de los avisos y ninguno era real.
          Un panel de calidad que grita en falso es un panel que se deja de mirar. */
       and s.en_nacional = 1
       /* Solo hasta el corte publicado. Un mes que se esta capturando AHORA tiene
          sitios sin reportar por definicion —alguien lleva tres de los nueve numeros
          de Celta— y eso no es un defecto de calidad: es trabajo en curso. Sin este
          filtro, abrir el formulario el dia 2 llenaria la vista de Calidad de errores
          rojos que solo dicen que el mes acaba de empezar. Lo que falta por capturar
          se mira en ehs.v_captura_estado, que existe para eso. */
       and f.num_mes <= isnull((select c.corte from ehs.v_corte_publicado c
                                 where c.anio = f.anio), 0)
       and exists (select 1 from ehs.hecho_lectura_mensual l2
                    join ehs.dim_fecha f2 on f2.fecha = l2.fecha
                   where f2.num_mes = f.num_mes and f2.anio = f.anio and l2.sitio_id <> s.sitio_id)
       and not exists (select 1 from ehs.hecho_lectura_mensual l3
                        join ehs.dim_fecha f3 on f3.fecha = l3.fecha
                       where f3.num_mes = f.num_mes and f3.anio = f.anio and l3.sitio_id = s.sitio_id);
go

/* ------------------------------------------------------------- agua diaria ---
   Marca los dias fuera de banda contra la MEDIANA DEL PROPIO MES, no contra una
   constante: si el mes entero sube, el pico sigue siendo relativo a ese mes.
   Con la tabla vacia la vista devuelve cero filas, que es lo correcto. */
create or alter view ehs.v_agua_diaria
as
    with mediana as (
        select sitio_id,
               year(fecha)  as anio,
               month(fecha) as num_mes,
               mediana_m3 = percentile_cont(0.5) within group (order by consumo_m3)
                                over (partition by sitio_id, year(fecha), month(fecha))
          from ehs.hecho_lectura_diaria_agua
    ),
    unico as (
        select distinct sitio_id, anio, num_mes, mediana_m3 from mediana
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
      join ehs.dim_sitio s on s.sitio_id = d.sitio_id
      left join unico u
             on u.sitio_id = d.sitio_id
            and u.anio     = year(d.fecha)
            and u.num_mes  = month(d.fecha);
go

/* ----------------------------------------------------------- estado diario ---
   El rotulo de pendiente lo decide el conteo de filas, no una constante. El dia
   que llegue el archivo, la vista cambia sola. */
create or alter view ehs.v_estado_agua_diaria
as
    select filas = count(*),
           estado = case when count(*) = 0
                         then '0 lecturas diarias'
                         else format(count(*), '#,0') + ' lecturas diarias' end
      from ehs.hecho_lectura_diaria_agua;
go

/* ------------------------------------------------------ lo rechazado, a la vista ---
   Una tabla de rechazos que nadie mira es un cajon. Esta vista es la que consulta el
   area: que se quedo fuera, por que, y desde cuando. Con la tabla vacia devuelve cero
   filas, que es lo correcto. */
create or alter view ehs.v_rechazo_pendiente
as
    select r.rechazo_id,
           r.detectado_en,
           r.origen,
           r.motivo,
           sitio      = r.sitio_texto,
           magnitud   = r.magnitud_texto,
           fecha      = r.fecha_texto,
           valor      = r.valor_texto,
           dias_abierto = datediff(day, r.detectado_en, sysdatetime())
      from ehs.lectura_rechazada r
     where r.resuelto = 0;
go

/* ----------------------------------------------------- cual es el corte publicado */

/* QUE MES ES "EL CORTE", Y POR QUE NO ES SIMPLEMENTE EL ULTIMO CON DATO.

   Mientras el dato llego solo en lotes mensuales completos —el pipeline leia el Excel
   entero y publicaba— la distincion no existia: el ultimo mes con alguna lectura era
   siempre un mes entero. Con una puerta de captura eso deja de ser cierto. El primer
   dia que alguien teclee cuatro numeros de septiembre, "el ultimo mes con dato" pasa a
   ser septiembre, y el tablero se republicaria entero contra un mes de cuatro lecturas:
   los YTD se moverian, los estados contra meta cambiarian y el gerente veria cifras que
   no significan nada.

   Es exactamente la familia de errores que este trabajo vino a quitar. En el libro
   heredado, julio estaba capturado en la hoja cruda y el reporte lo mostraba en cero;
   aqui seria al reves, un mes a medias presentado como cerrado. El dano es el mismo:
   el reporte dice algo que el dato no sostiene.

   Un mes es corte cuando TODOS los sitios activos tienen TODAS las magnitudes. No se
   cuenta contra un 27 escrito a mano: se cuenta contra las dimensiones, para que anadir
   un sitio o una magnitud no deje esta regla mintiendo en silencio.

   El mes en curso, incompleto, no desaparece: sigue en ehs.v_calidad_dato y en
   ehs.v_captura_estado, que es donde se mira lo que falta por capturar. Lo que no hace
   es gobernar lo que se publica. */
create or alter view ehs.v_corte_publicado
as
    with esperadas as (
        /* en_nacional = 1 son los tres sitios que capturan cada mes: Celta, La Estrella
           y Agencias. dim_sitio guarda ademas 'colombia_peru' y 'peru', que existen
           para el scorecard corporativo anual y no capturan magnitudes mensuales;
           contarlos aqui haria que ningun mes fuera nunca completo. */
        select total = (select count(*) from ehs.dim_sitio
                         where activo = 1 and en_nacional = 1)
                     * (select count(*) from ehs.dim_magnitud)
    ),
    por_mes as (
        select f.anio,
               f.num_mes,
               lecturas = count(*),
               completo = case when count(*) >= (select total from esperadas)
                               then 1 else 0 end
          from ehs.hecho_lectura_mensual l
          join ehs.dim_fecha f on f.fecha = l.fecha
         group by f.anio, f.num_mes
    )
    select p.anio,
           corte        = max(case when p.completo = 1 then p.num_mes end),
           ultimo_visto = max(p.num_mes),
           /* Si los dos no coinciden, hay un mes en curso a medias. Se expone en vez de
              esconderse: el tablero puede decir "septiembre, 4 de 27" en su barra de
              contexto en lugar de callarlo. */
           en_curso     = case when max(p.num_mes) >
                                    isnull(max(case when p.completo = 1 then p.num_mes end), 0)
                               then max(p.num_mes) end,
           esperadas_por_mes = (select total from esperadas)
      from por_mes p
     group by p.anio;
go

print 'Vistas de ehs creadas.';
go
