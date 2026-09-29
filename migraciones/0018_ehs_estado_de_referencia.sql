/* =====================================================================
   Migracion 0018 — estado de referencia (29-sep-2026)
   ---------------------------------------------------------------------
   Una instalacion nueva (migraciones 0001 a 0017 con datos semilla) NO daba el
   mismo dato que la instalacion de referencia de Samuel. Se midio comparando las
   dos base contra base, fila por fila (822 filas): tres tablas difieren, y la
   estructura es igual. Dos causas, las dos por dato y no por esquema:

   1. La migracion 0012 se edito DESPUES de aplicarse en la instalacion de
      referencia (ver la nota de migrar.js: no compara checksum), asi que las dos
      lecturas del accidente con dias perdidos de Celta (mayo y julio de 2026)
      quedaron distintas: alla en estado 'corregido', con su motivo y su
      etiqueta de origen; en una instalacion nueva, en 'validado' y sin motivo.
      El valor es el mismo (mayo 0, julio 1); cambia lo que dice la trazabilidad.
   2. Las 10 confirmaciones de avisos 'salto_atipico' del corte de julio de 2026
      (pedido de Samuel el 28-sep-2026: "todos estan verificados y aprobados") se
      dieron desde el tablero, con ehs.sp_confirmar_aviso, y ninguna migracion las
      trae: una instalacion nueva mostraba esos 10 avisos otra vez "a revisar".

   Esta migracion lleva una instalacion nueva a ese estado. En la instalacion de
   referencia no cambia nada: cada sentencia solo actua si la fila todavia no
   esta como debe (idempotente). NO se edita la 0012: ya esta aplicada en
   instalaciones reales, y editar una migracion aplicada es justo lo que causo
   el punto 1.

   Las columnas de fecha-hora de auditoria (capturado_en, modificado_en,
   reemplazado_en, confirmado_en) NO se copian: dicen cuando cada instalacion
   recibio el cambio, y eso es distinto en cada una a proposito.

   El trigger de historia se apaga solo mientras dura el UPDATE: sin eso, pasar
   estado de 'validado' a 'corregido' archivaria dos filas de historia que no
   existen en la instalacion de referencia (alla el cambio fue una sola operacion
   que el trigger ya habia archivado). Todo va en una transaccion: si algo falla,
   el trigger vuelve a quedar encendido. */

set nocount on;
go

/* ------------------------------ 1. las dos lecturas del accidente de Celta */
begin try
    begin transaction;

    disable trigger ehs.tr_lectura_mensual_hist on ehs.hecho_lectura_mensual;

    update ehs.hecho_lectura_mensual
       set estado            = 'corregido',
           origen            = N'correccion manual: Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta no ',
           modificado_por    = N'migracion 0012 (confirmado en reunion 24-sep-2026)',
           motivo_correccion = N'Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta no fue en mayo, fue en julio, y es el unico del ano.'
     where fecha = '2026-05-01' and sitio_id = 'celta' and magnitud_id = 'accidentes_dafw'
       and (estado <> 'corregido' or origen <> N'correccion manual: Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta no ' or modificado_por <> N'migracion 0012 (confirmado en reunion 24-sep-2026)'
            or isnull(motivo_correccion, N'') <> N'Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta no fue en mayo, fue en julio, y es el unico del ano.');

    update ehs.hecho_lectura_mensual
       set estado            = 'corregido',
           origen            = N'correccion manual: Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta fue',
           modificado_por    = N'migracion 0012 (confirmado en reunion 24-sep-2026)',
           motivo_correccion = N'Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta fue en julio, no en mayo.'
     where fecha = '2026-07-01' and sitio_id = 'celta' and magnitud_id = 'accidentes_dafw'
       and (estado <> 'corregido' or origen <> N'correccion manual: Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta fue' or modificado_por <> N'migracion 0012 (confirmado en reunion 24-sep-2026)'
            or isnull(motivo_correccion, N'') <> N'Reunion con el manager de la implementacion, 24-sep-2026: el accidente con dias perdidos de Celta fue en julio, no en mayo.');

    update h
       set h.reemplazado_por = N'migracion 0012 (confirmado en reunion 24-sep-2026)'
      from ehs.hecho_lectura_mensual_hist h
     where h.sitio_id = 'celta' and h.magnitud_id = 'accidentes_dafw'
       and h.fecha in ('2026-05-01', '2026-07-01')
       and h.reemplazado_por = N'migracion 0012';

    enable trigger ehs.tr_lectura_mensual_hist on ehs.hecho_lectura_mensual;

    commit;
end try
begin catch
    if @@trancount > 0 rollback;
    throw;
end catch;
go

/* -------------------------------- 2. los 10 avisos confirmados el 28-sep-2026 */
insert into ehs.aviso_confirmado (fecha, sitio_id, magnitud_id, codigo, confirmado_por, nota)
select v.fecha, v.sitio_id, v.magnitud_id, 'salto_atipico', N'Samuel Galeano',
       N'Verificados y aprobados por Samuel Galeano en el chat del tablero (revision del corte de julio 2026, 28-sep-2026).'
  from (values
        ('2026-02-01', 'agencias', 'residuo_aprovechable_kg'),
        ('2026-03-01', 'celta', 'residuo_peligroso_kg'),
        ('2026-04-01', 'estrella', 'residuo_peligroso_kg'),
        ('2026-05-01', 'estrella', 'residuo_ordinario_kg'),
        ('2026-05-01', 'estrella', 'residuo_peligroso_kg'),
        ('2026-06-01', 'celta', 'residuo_peligroso_kg'),
        ('2026-06-01', 'estrella', 'residuo_ordinario_kg'),
        ('2026-06-01', 'estrella', 'residuo_peligroso_kg'),
        ('2026-07-01', 'celta', 'residuo_peligroso_kg'),
        ('2026-07-01', 'estrella', 'residuo_peligroso_kg')
       ) as v (fecha, sitio_id, magnitud_id)
 where exists (select 1 from ehs.hecho_lectura_mensual l
                where l.fecha = v.fecha and l.sitio_id = v.sitio_id and l.magnitud_id = v.magnitud_id)
   and not exists (select 1 from ehs.aviso_confirmado a
                    where a.fecha = v.fecha and a.sitio_id = v.sitio_id
                      and a.magnitud_id = v.magnitud_id and a.codigo = 'salto_atipico');
go
