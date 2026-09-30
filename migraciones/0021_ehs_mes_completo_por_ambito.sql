/* =====================================================================
   Migracion 0021 - un mes cuenta para un ambito solo si todos sus sitios lo
   reportaron (30-sep-2026)
   ---------------------------------------------------------------------
   El problema apareció al cargar agosto (0020). Los cuatro sitios de
   'colombia_peru' reportaban siempre los mismos meses, asi que nadie se
   habia preguntado que pasa cuando no: Colombia trae agosto y Peru todavia no.
   ehs.v_lectura_ambito repite cada lectura por cada ambito al que suma, y
   todo lo demas (v_kpi_mensual, v_kpi_ytd, el tablero) suma lo que encuentre.
   Con agosto, 'Colombia + Peru' sumaba los tres sitios de Colombia y ninguno de
   Peru: el mes de agosto era Colombia sola con otro nombre, y el acumulado
   mezclaba Colombia a agosto con Peru a julio. Un numero que parece consolidado
   y no lo es, que es peor que un numero faltante (regla 5 de ehs/CLAUDE.md).

   La regla, en una frase: un mes cuenta para un ambito solo si todos los sitios
   del ambito que reportaron ESE ANIO lo reportaron. Se mira "que reportaron ese
   anio" y no "todos los sitios del ambito" porque Peru no tiene lecturas de 2024
   ni 2025 (solo el scorecard anual): con "todos", 'Colombia + Peru' quedaria
   vacio en esos dos anios, y lo que muestra hoy (Colombia sola, comparada contra
   si misma) no cambia.

   Medido antes de escribirla, sobre TODOS los datos existentes (1904 filas de
   la vista): la regla saca exactamente 27 filas, las de Colombia en agosto de
   2026 dentro de 'colombia_peru', y agrega ninguna. Ningun otro ambito, mes ni
   anio cambia. Cuando Peru reporte agosto, esas 27 filas vuelven solas.

   Consecuencia visible: 'Colombia + Peru' y 'Peru' terminan en julio mientras
   Colombia sigue en agosto. El tablero lo dice con su propio corte por ambito
   (panorama devuelve el ultimo mes que el ambito si tiene).

   Una vista, no dato: nada que migrar, y volver atras es volver a correr el
   create or alter de 0006. */

set nocount on;
go

create or alter view ehs.v_lectura_ambito
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
go
