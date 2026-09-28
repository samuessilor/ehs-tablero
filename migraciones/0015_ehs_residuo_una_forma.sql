/* =====================================================================
   Migracion 0015 — el residuo de un sitio-mes se reporta de una sola forma,
   y los saltos atipicos se comparan dentro del mismo anio
   ---------------------------------------------------------------------
   Pedido por Samuel el 28-sep-2026: resolver los hallazgos del libro heredado
   que alteran un numero y "dejarlo estructurado en la base para que estos
   errores no vuelvan a presentarse".

   Primero se verifico (recalculo completo desde la hoja cruda del Excel contra
   /api/ehs/datos: 980 comparaciones, 0 diferencias) que la base NUNCA tuvo
   ninguno de esos cinco errores, porque ninguno puede existir como tal aqui: no
   hay formulas por celda (el acumulado es una sola vista desde enero), los KPI se
   calculan siempre de las partes (nunca de un total escrito a mano), las horas se
   unen por sitio_id (no por columna) y un mes solo se publica con las 27 lecturas
   de Colombia completas. Lo que SI podia repetirse, por el lado del dato, era el
   error de 'KPIs 2026'!E60: un total tecleado encima de sus partes.

   1. ref.dim_magnitud.forma_residuo: residuos_por_lente suma cuatro magnitudes
      porque Celta/La Estrella/Agencias desglosan el residuo (peligroso,
      aprovechable, ordinario) y Peru solo reporta el total. En un ambito que los
      junta, cada sitio aporta su forma sin pisar la del otro — pero NADA impedia
      que un mismo sitio-mes tuviera las dos: el total sin desglose MAS sus partes,
      que residuos_por_lente contaria dos veces. La columna dice que forma es cada
      magnitud; el trigger de abajo prohibe mezclarlas en un mismo sitio-mes.

   2. ehs.tr_lectura_mensual_residuo_una_forma: la regla vive en la tabla, no en
      un procedimiento, para que la cumplan TODOS los caminos que escriben
      lecturas (captura, correccion, migraciones, un UPDATE a mano). Es
      mutuamente excluyente y nada mas: no fija que forma usa cada sitio, porque
      el historico 2023-2025 de Celta/La Estrella/Agencias trae solo el total (esos
      anios no tenian desglose) y 2026 trae solo el desglose — las dos son
      legitimas, lo que no puede pasar es tener las dos el mismo mes.

   3. ehs.v_calidad_avisos: el lag() de "salto_atipico" particionaba por sitio y
      magnitud pero no por anio, y ordenaba solo por numero de mes. Desde que la
      migracion 0012 cargo 2023-2025, agua/energia/unidades de 2026 comparaban
      contra un "mes anterior" de otro anio (medido: 27 de 217 lecturas de 2026).
      El tablero no lo sufria — calcula sus avisos con su propia consulta,
      filtrada al anio antes del lag() (adaptador_sql.js, calidadDato) — pero esta
      vista es la que usaria cualquiera que consulte la base directamente (IT,
      Power BI). Misma vista, con 'anio' en la particion.

   Se verifica antes de instalar el trigger que ningun sitio-mes existente mezcle
   las dos formas: si alguno lo hiciera, la migracion se detiene aqui en vez de
   dejar una regla que los datos ya violan.
   ===================================================================== */

set nocount on;
go

/* ---------------------------------------------- 1. la forma de cada magnitud */
if col_length('ref.dim_magnitud', 'forma_residuo') is null
    alter table ref.dim_magnitud
        add forma_residuo varchar(10) null
            constraint ck_dim_magnitud_forma_residuo
                check (forma_residuo in ('desglose', 'total'));
go

update ref.dim_magnitud
   set forma_residuo = case
           when magnitud_id in ('residuo_peligroso_kg', 'residuo_aprovechable_kg',
                                'residuo_ordinario_kg') then 'desglose'
           when magnitud_id = 'residuo_total_kg' then 'total'
       end
 where magnitud_id in ('residuo_peligroso_kg', 'residuo_aprovechable_kg',
                       'residuo_ordinario_kg', 'residuo_total_kg');
go

/* --------------------------- 2a. ningun dato existente puede violar la regla */
if exists (
    select 1
      from ehs.hecho_lectura_mensual l
      join ref.dim_magnitud m on m.magnitud_id = l.magnitud_id
     where m.forma_residuo is not null
     group by l.sitio_id, l.fecha
    having count(distinct m.forma_residuo) > 1
)
    throw 50000, 'Hay sitio-mes con el residuo desglosado Y como total a la vez: corregir esos datos antes de instalar la regla.', 1;
go

/* ------------------------------------------------- 2b. la regla en la tabla */
create or alter trigger ehs.tr_lectura_mensual_residuo_una_forma
on ehs.hecho_lectura_mensual
after insert, update
as
begin
    set nocount on;
    if not exists (select 1 from inserted) return;

    declare @sitio nvarchar(80), @mes char(7);

    -- solo los sitio-mes que esta sentencia toco: la regla ya se cumple en el resto
    select top 1 @sitio = s.sitio, @mes = convert(char(7), l.fecha, 120)
      from ehs.hecho_lectura_mensual l
      join ref.dim_magnitud m on m.magnitud_id = l.magnitud_id
      join ref.dim_sitio s    on s.sitio_id = l.sitio_id
     where m.forma_residuo is not null
       and exists (select 1 from inserted i
                    where i.fecha = l.fecha and i.sitio_id = l.sitio_id)
     group by s.sitio, l.fecha
    having count(distinct m.forma_residuo) > 1;

    if @sitio is not null
    begin
        declare @msg nvarchar(600) = concat(
            @sitio, ', ', @mes, ': el residuo de ese mes ya esta capturado de una forma ',
            '(desglosado en peligroso, aprovechable y ordinario, o como total sin desglose) ',
            'y esta lectura lo agrega de la otra. Residuos por lente contaria el mismo ',
            'residuo dos veces. Un sitio reporta el residuo de una sola forma por mes.');
        -- THROW y no raiserror + rollback: el error llega intacto (numero 50000) a
        -- quien escribio, y la API lo muestra como regla de la base (src/errores.js)
        throw 50000, @msg, 1;
    end;
end;
go

/* ------------------------ 3. saltos atipicos dentro del mismo anio, no entre anios */
create or alter view ehs.v_calidad_avisos
as
    with valores as (
        select f.anio, f.num_mes as mes, s.sitio_id, m.magnitud_id, l.valor,
               -- 'f.anio' en la particion: sin el, desde que hay 2023-2025 cargados,
               -- el "mes anterior" de enero 2026 podia ser cualquier mes de otro anio
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
       /* nullif y no 'valor_anterior <> 0' delante, aunque parezca que basta. SQL
          Server NO garantiza que evalue los predicados del where en el orden en que
          estan escritos: puede resolver la division antes que el filtro. */
       and abs((valor - valor_anterior) / nullif(valor_anterior, 0)) > 0.4
    union all
    select f.anio, f.num_mes as mes, s.sitio_id, magnitud_id = cast(null as varchar(40)),
           gravedad = 'error', codigo = 'mes_incompleto',
           mensaje = concat(s.sitio_id, ' no reporto el mes ', f.num_mes,
                             ', pero otros sitios si. El consolidado de ese mes queda sesgado.')
      from ref.dim_fecha f
     cross join ref.dim_sitio s
     where s.activo = 1
       and s.en_nacional = 1
       and f.num_mes <= isnull((select c.corte from ehs.v_corte_publicado c
                                 where c.anio = f.anio), 0)
       and exists (select 1 from ehs.hecho_lectura_mensual l2
                    join ref.dim_fecha f2 on f2.fecha = l2.fecha
                   where f2.num_mes = f.num_mes and f2.anio = f.anio and l2.sitio_id <> s.sitio_id)
       and not exists (select 1 from ehs.hecho_lectura_mensual l3
                        join ref.dim_fecha f3 on f3.fecha = l3.fecha
                       where f3.num_mes = f.num_mes and f3.anio = f.anio and l3.sitio_id = s.sitio_id);
go
