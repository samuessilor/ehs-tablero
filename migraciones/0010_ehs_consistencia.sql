/* ===========================================================================
   Migracion 0010 — lo que encontro la revision final, en la base

   La revision de punta a punta antes de entregar (fuente contra base, base
   contra API y pantallas, 9.827 cifras recalculadas: 0 diferencias) encontro
   que las cifras publicadas estaban bien, pero que los CAMINOS para cambiarlas
   o para publicar el mes siguiente tenian huecos. Los que viven en la base se
   corrigen aqui. No se edita ninguna migracion anterior: migrar.js guarda el
   checksum de cada una, y editarlas chocaria con una base ya instalada.

     1. El calendario terminaba en diciembre de 2026 y vivia en la semilla
        opcional (0008): en febrero de 2027 la captura de enero se habria
        rechazado entera ("El mes no existe en ref.dim_fecha").
     2. sp_corregir_lectura escribia origen = 'correccion manual: ' + motivo
        en una columna varchar(120): un motivo de mas de 101 caracteres fallaba
        con error de truncamiento y la pantalla decia solo "no pudo responder".
     3. v_correcciones mostraba como valor corregido el valor ACTUAL de la
        lectura: con dos correcciones seguidas, la primera salia con el valor
        de la segunda.
     4. v_kpi_mensual y v_kpi_ytd trataban como conteo cualquier KPI al que le
        faltara el denominador: agua capturada sin unidades buenas publicaba
        cientos de miles de litros por lente en lugar de "sin dato".
     5. v_kpi_contra_meta usaba otra regla de semaforo (+5 % sobre la meta) que
        la API del tablero (90 % bajo la meta): marcaba 'en riesgo' valores por
        encima del techo. Queda la misma regla y los mismos codigos que usa el
        tablero; la banda sigue siendo decision de EHS, ahora en un solo sentido.
     6. v_corte_publicado publicaba hasta el ultimo mes completo aunque un mes
        ANTERIOR estuviera incompleto (el YTD se habria calculado con el hueco),
        contaba lecturas de cualquier sitio activo y magnitudes de cualquier
        area. Ahora el corte es el ultimo mes M tal que 1..M estan completos,
        solo con los sitios que capturan cada mes y las magnitudes de EHS.
     7. v_captura_estado contaba magnitudes de cualquier area y listaba sitios
        que no capturan (peru, colombia_peru).
   =========================================================================== */

/* ------------------------------------------------------ 1. calendario 2023-2035 */

/* Por rango y no por lista: la semilla 0008 escribe 2023-2026 a mano, y cualquier
   instalacion sin semilla quedaba sin calendario. merge solo inserta lo que falta,
   asi que es inocuo sobre una base que ya tiene los meses de la semilla. */
with meses as (
    select cast('2023-01-01' as date) as fecha
    union all
    select dateadd(month, 1, fecha) from meses where fecha < '2035-12-01'
)
merge ref.dim_fecha as d
using (select fecha,
              anio      = year(fecha),
              num_mes   = month(fecha),
              mes       = choose(month(fecha), 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                                 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'),
              mes_corto = choose(month(fecha), 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
                                 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'),
              anio_mes  = convert(char(7), fecha, 126),
              trimestre = 'T' + cast((month(fecha) + 2) / 3 as char(1))
         from meses) as o
   on d.fecha = o.fecha
 when not matched then insert (fecha, anio, num_mes, mes, mes_corto, anio_mes, trimestre)
      values (o.fecha, o.anio, o.num_mes, o.mes, o.mes_corto, o.anio_mes, o.trimestre)
option (maxrecursion 200);
go

/* ------------------------------------------------ 2. corregir con motivo largo */

create or alter procedure ehs.sp_corregir_lectura
    @fecha          date,
    @sitio_id       varchar(20),
    @magnitud_id    varchar(40),
    @valor_nuevo    decimal(18,4),
    @motivo         varchar(300),
    @corregido_por  varchar(60)
as
begin
    set nocount on;
    set xact_abort on;

    if @corregido_por is null or ltrim(rtrim(@corregido_por)) = ''
    begin
        raiserror('Falta @corregido_por. Igual que al capturar (R.5.3.4), la correccion tiene que decir quien la hizo.', 16, 1);
        return;
    end;

    if @motivo is null or len(ltrim(rtrim(@motivo))) < 10
    begin
        raiserror('El motivo de la correccion tiene que explicar algo, no solo llenar el campo (minimo 10 caracteres).', 16, 1);
        return;
    end;

    if @valor_nuevo < 0
    begin
        raiserror('Valor negativo. Ninguna de las nueve magnitudes puede serlo.', 16, 1);
        return;
    end;

    if not exists (select 1 from ehs.hecho_lectura_mensual
                    where fecha = @fecha and sitio_id = @sitio_id and magnitud_id = @magnitud_id)
    begin
        raiserror('Esa lectura no existe todavia. Se captura, no se corrige.', 16, 1);
        return;
    end;

    begin try
        begin transaction;

        update ehs.hecho_lectura_mensual
           set valor              = @valor_nuevo,
               estado             = 'corregido',
               motivo_correccion  = @motivo,
               /* origen es varchar(120): el motivo completo ya queda en
                  motivo_correccion y en la historia; aqui solo el comienzo. */
               origen             = left('correccion manual: ' + @motivo, 120),
               modificado_por     = @corregido_por,
               modificado_en      = sysdatetime()
         where fecha = @fecha and sitio_id = @sitio_id and magnitud_id = @magnitud_id
           and valor <> @valor_nuevo;

        declare @filas int = @@rowcount;

        commit transaction;

        select filas_corregidas = @filas,
               fecha = @fecha, sitio_id = @sitio_id, magnitud_id = @magnitud_id,
               valor_nuevo = @valor_nuevo;
    end try
    begin catch
        if @@trancount > 0 rollback transaction;
        throw;
    end catch;
end;
go

/* ------------------------------------- 3. el valor que dejo CADA correccion */

/* Cada fila de la historia guarda el valor ANTERIOR a un cambio. El valor que ese
   cambio dejo es el anterior de la version siguiente, o el valor actual si fue el
   ultimo cambio. */
create or alter view ehs.v_correcciones
as
    with versiones as (
        select h.hist_id, h.lectura_id, h.fecha, h.sitio_id, h.magnitud_id,
               h.valor_anterior, h.motivo, h.reemplazado_por, h.reemplazado_en,
               siguiente = lead(h.valor_anterior)
                               over (partition by h.lectura_id
                                     order by h.reemplazado_en, h.hist_id)
          from ehs.hecho_lectura_mensual_hist h
    )
    select v.hist_id,
           v.fecha, f.anio, f.num_mes as mes,
           v.sitio_id, s.sitio_corto,
           v.magnitud_id, m.magnitud,
           valor_anterior  = v.valor_anterior,
           valor_corregido = coalesce(v.siguiente, l.valor),
           v.motivo,
           autorizado_por  = v.reemplazado_por,
           corregido_en    = v.reemplazado_en
      from versiones v
      join ehs.hecho_lectura_mensual l on l.lectura_id = v.lectura_id
      join ref.dim_fecha f    on f.fecha = v.fecha
      join ref.dim_sitio s    on s.sitio_id = v.sitio_id
      join ref.dim_magnitud m on m.magnitud_id = v.magnitud_id
     where v.motivo is not null;
go

/* --------------------------- 4. un ratio sin denominador es "sin dato", no un conteo */

/* Si un KPI es conteo lo dice ref.kpi_magnitud (no tiene ninguna magnitud con rol
   'denominador'), no el hecho de que en un mes falte el denominador. */
create or alter view ehs.v_kpi_mensual
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
                /* el cast antes de dividir: ver 0006, sin el SQL Server trunca
                   el septimo decimal en vez de redondearlo */
                else cast(n.valor * k.factor as decimal(24,6)) / d.valor
           end                                    as valor
      from numerador n
      join ref.dim_kpi k on k.kpi_id = n.kpi_id
      left join denominador d
             on d.anio = n.anio and d.num_mes = n.num_mes
            and d.ambito_id = n.ambito_id and d.kpi_id = n.kpi_id;
go

create or alter view ehs.v_kpi_ytd
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
                else cast(sum(m.numerador) * max(k.factor) as decimal(24,6))
                     / sum(m.denominador)
           end                                    as valor
      from ehs.v_kpi_mensual m
      join ref.dim_kpi k on k.kpi_id = m.kpi_id
      cross join (select distinct num_mes from ref.dim_fecha) corte
     where m.num_mes <= corte.num_mes
     group by m.anio, corte.num_mes, m.ambito_id, m.kpi_id;
go

/* ------------------------------------------ 5. un solo semaforo, el del tablero */

/* La misma regla, los mismos codigos y el mismo redondeo de brecha que la API del
   tablero (src/datos/adaptador_sql.js, ESTADO y BRECHA). La meta es techo:
   por encima incumple; del 90 % al 100 % de la meta, riesgo; por debajo, cumple. */
create or alter view ehs.v_kpi_contra_meta
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
            and mt.vigente   = 1;
go

/* ------------------------------------------------- 6. que mes se publica */

create or alter view ehs.v_corte_publicado
as
    with esperadas as (
        select total = (select count(*) from ref.dim_sitio
                         where activo = 1 and en_nacional = 1)
                     * (select count(*) from ref.dim_magnitud where area = 'ehs')
    ),
    por_mes as (
        select f.anio,
               f.num_mes,
               lecturas = count(*),
               completo = case when count(*) >= (select total from esperadas)
                               then 1 else 0 end
          from ehs.hecho_lectura_mensual l
          join ref.dim_fecha f    on f.fecha = l.fecha
          join ref.dim_sitio s    on s.sitio_id = l.sitio_id
                                 and s.activo = 1 and s.en_nacional = 1
          join ref.dim_magnitud g on g.magnitud_id = l.magnitud_id and g.area = 'ehs'
         group by f.anio, f.num_mes
    ),
    /* el primer mes del anio que NO esta completo: el corte es el mes anterior.
       Asi un hueco en agosto frena la publicacion aunque septiembre este completo,
       en vez de publicar agosto (y el acumulado) con el hueco adentro. */
    primer_hueco as (
        select a.anio, primero = min(m.num_mes)
          from (select distinct anio from por_mes) a
         cross join (select distinct num_mes from ref.dim_fecha) m
          left join por_mes p
                 on p.anio = a.anio and p.num_mes = m.num_mes and p.completo = 1
         where p.num_mes is null
         group by a.anio
    )
    select p.anio,
           corte        = case when isnull(h.primero, 13) > 1
                               then cast(isnull(h.primero, 13) - 1 as tinyint) end,
           ultimo_visto = max(p.num_mes),
           en_curso     = case when max(p.num_mes) > isnull(h.primero, 13) - 1
                               then max(p.num_mes) end,
           esperadas_por_mes = (select total from esperadas)
      from por_mes p
      left join primer_hueco h on h.anio = p.anio
     group by p.anio, h.primero;
go

/* ------------------------------------------------- 7. estado de la captura */

create or alter view ehs.v_captura_estado
as
    select f.anio,
           f.num_mes,
           s.sitio_id,
           s.sitio                        as sitio_nombre,
           count(l.lectura_id)            as capturadas,
           (select count(*) from ref.dim_magnitud where area = 'ehs') as esperadas,
           max(l.capturado_en)            as ultima_captura,
           max(l.capturado_por)           as ultimo_capturador
      from ref.dim_fecha f
     cross join ref.dim_sitio s
      left join ehs.hecho_lectura_mensual l
             on l.fecha = f.fecha and l.sitio_id = s.sitio_id
     where s.activo = 1 and s.en_nacional = 1
     group by f.anio, f.num_mes, s.sitio_id, s.sitio;
go

print 'Migracion 0010: calendario a 2035, correccion con motivo largo, historial exacto, semaforo unico y corte sin huecos.';
go
