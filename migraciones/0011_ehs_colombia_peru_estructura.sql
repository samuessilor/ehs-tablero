/* ===========================================================================
   Migracion 0011 — estructura para Peru operativo, Colombia+Peru real y el
   ambito "Colombia" con su propia trayectoria historica

   Contexto (reunion con el manager de la implementacion, 24-sep-2026): Peru
   (TOPSA) deja de ser un sitio "solo scorecard" y pasa a tener captura mensual
   real (agua, energia, residuos, unidades buenas — accidentes y horas-hombre
   siguen pendientes de envio, el manager lo dijo explicitamente en la
   reunion). 'Colombia + Peru' deja de ser solo una meta consolidada y pasa a
   ser un ambito operativo real (suma de sus cuatro miembros). La etiqueta
   'Nacional Labs + Agencias' pasa a llamarse 'Colombia' en pantalla — el id
   interno sigue siendo 'nacional' para no romper URLs ni el resto del codigo
   que ya lo usa.

   Esta migracion es solo estructura (DDL + dimensiones pequenas), siempre se
   aplica. Los datos en si (historico 2023-2025, Peru 2026, la correccion del
   accidente y la meta nueva de Colombia) viven en la 0012, opcional, igual
   que la 0008 — porque son datos propios de este sitio, no esquema generico.
   =========================================================================== */

/* ------------------------------------------------ ambito Colombia + Peru ---
   Igual que en_nacional_labs/en_nacional ya deciden que suma en cada agregado,
   esta columna nueva decide quien suma en 'colombia_peru'. Celta, Estrella y
   Agencias ya sumaban 'nacional' (Colombia); Peru se agrega solo aqui, porque
   el manager fue explicito: Colombia (sin Peru) sigue siendo solo los tres de
   siempre. */
if not exists (select 1 from sys.columns
               where object_id = object_id('ref.dim_sitio') and name = 'en_colombia_peru')
    alter table ref.dim_sitio add en_colombia_peru bit not null constraint df_sitio_colper default 0;
go

update ref.dim_sitio set en_colombia_peru = 1 where sitio_id in ('celta', 'estrella', 'agencias', 'peru');
go

/* ------------------------------------ Colombia y Peru no se auto-mapean ---
   ehs.v_ambito (mas abajo) tiene una rama que mapea cada sitio activo a si
   mismo como su propio ambito (para que Celta, Peru, etc. funcionen como
   ambito de una sola linea). 'colombia_peru' y el 'nacional' que se agrega
   abajo NUNCA capturan una lectura propia — son solo el soporte para que
   ehs.meta/ehs.scorecard_anual tengan donde apuntar (FK a ref.dim_sitio).
   Si quedan activo=1, esa rama los auto-mapea IGUAL que a un sitio real y
   ehs.v_ambito termina publicando dos filas para 'colombia_peru' con dos
   etiquetas distintas (la del propio dim_sitio y la del ambito real) — un
   "top 1 ... where ambito_id=@x" sin order by se vuelve no determinista.
   activo=0 los saca de esa rama sin afectar el FK (las claves foraneas no
   miran esta columna) ni la rama que si les corresponde (la del ambito real,
   mas abajo). */
update ref.dim_sitio set activo = 0 where sitio_id = 'colombia_peru';
go

/* ---------------------------------------------------- Peru, sitio operativo
   Antes tipo='Pais' (solo scorecard, migracion 0008). Ahora es un laboratorio
   mas: tiene lecturas mensuales reales desde 2026 (migracion 0012). No se le
   marca en_nacional ni en_nacional_labs — Peru NO es parte de Colombia, solo
   de 'Colombia + Peru' (en_colombia_peru, arriba). */
update ref.dim_sitio
   set tipo = 'Laboratorio',
       sitio = 'TOPSA (Peru)',
       sitio_corto = 'TOPSA',
       nombre_corporativo = 'TOPSA'
 where sitio_id = 'peru';
go

/* -------------------------------------------------- Colombia, sitio virtual
   'nacional' (Colombia = Celta+Estrella+Agencias) ya existe como ambito en
   ehs.v_ambito, pero nunca tuvo fila en ref.dim_sitio — no hacia falta hasta
   ahora. La necesita para poder tener su propia fila en ehs.scorecard_anual
   (FK a ref.dim_sitio) y asi la vista "Anual" pueda mostrar su trayectoria
   2023-2026, igual que ya se hace con 'colombia_peru' y 'peru'. Mismo patron,
   mismo tipo 'Consolidado': un sitio que no captura nada por si mismo — por
   eso activo=0 de una vez (ver el comentario de 'colombia_peru' arriba: sin
   esto, ehs.v_ambito lo auto-mapearia ademas como su propio ambito, encima
   de la rama que ya lo arma sumando Celta+Estrella+Agencias). El FK de
   ehs.scorecard_anual/ehs.meta sigue funcionando igual, activo o no. */
if not exists (select 1 from ref.dim_sitio where sitio_id = 'nacional')
insert ref.dim_sitio
    (sitio_id, sitio, sitio_corto, nombre_corporativo, tipo, ciudad,
     en_nacional_labs, en_nacional, en_colombia_peru, activo)
values
    ('nacional', 'Colombia', 'Colombia', 'Colombia (Celta + Estrella + Agencias)',
     'Consolidado', '-', 0, 0, 0, 0);
go

/* ------------------------------------------------------- residuo sin desglose
   Peru y el historico 2023-2025 de Celta/Estrella/Agencias solo traen un
   total de residuos, no el desglose peligroso/aprovechable/ordinario que si
   trae la captura 2026 de Colombia (hoja "indicadores mensuales LABS"). En
   vez de inventar un desglose que no existe, se declara una cuarta magnitud
   numeradora de residuos_por_lente: el mismo mecanismo generico de
   ref.kpi_magnitud que ya evita que "residuos suma tres magnitudes" sea un
   caso especial en el codigo — aqui simplemente suma una mas, donde exista. */
merge ref.dim_magnitud as d
using (values
    ('residuo_total_kg', 'Residuo total (sin desglose)', 'kg', 'ehs', 500.0, 41760.0, 10)
) as o (magnitud_id, magnitud, unidad, area, valor_min, valor_max, orden)
   on d.magnitud_id = o.magnitud_id
 when matched then update set
      d.magnitud = o.magnitud, d.unidad = o.unidad,
      d.valor_min = o.valor_min, d.valor_max = o.valor_max, d.orden = o.orden
 when not matched then insert
      (magnitud_id, magnitud, unidad, area, valor_min, valor_max, orden)
      values (o.magnitud_id, o.magnitud, o.unidad, o.area, o.valor_min, o.valor_max, o.orden);
go

merge ref.kpi_magnitud as d
using (values
    ('residuos_por_lente', 'residuo_total_kg', 'numerador')
) as o (kpi_id, magnitud_id, rol)
   on d.kpi_id = o.kpi_id and d.magnitud_id = o.magnitud_id and d.rol = o.rol
 when not matched then insert (kpi_id, magnitud_id, rol)
      values (o.kpi_id, o.magnitud_id, o.rol);
go

/* --------------------------------------------------------------- v_ambito ---
   Misma vista de la migracion 0006, con dos cambios: la etiqueta de 'nacional'
   pasa a 'Colombia' (el id no cambia), y se agrega la rama de 'colombia_peru'
   como ambito operativo real — antes solo vivia en ehs.meta/scorecard_anual,
   nunca sumaba lecturas propias. */
create or alter view ehs.v_ambito
as
    select sitio_id, cast(sitio_id as varchar(20)) as ambito_id,
           sitio_corto as ambito, 1 as orden
      from ref.dim_sitio
     where activo = 1
    union all
    select sitio_id, 'nacional_labs', 'Nacional Labs', 2
      from ref.dim_sitio
     where activo = 1 and en_nacional_labs = 1
    union all
    select sitio_id, 'nacional', 'Colombia', 3
      from ref.dim_sitio
     where activo = 1 and en_nacional = 1
    union all
    select sitio_id, 'colombia_peru', 'Colombia + Peru', 4
      from ref.dim_sitio
     where activo = 1 and en_colombia_peru = 1;
go

print 'Migracion 0011: Peru operativo, Colombia + Peru real, Colombia con fila propia para su trayectoria.';
go
