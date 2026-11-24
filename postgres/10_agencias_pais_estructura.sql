/* =============================================================================
   10_agencias_pais_estructura.sql -- estructura de "Agencias <Pais>" para los 7
   paises LATAM que todavia no la tienen (Mexico, Argentina, Costa Rica,
   Nicaragua, Republica Dominicana, Guatemala, Ecuador). Mismo patron que las
   3 agencias ya existentes (chile_megalux_ag, honduras_popular_ag,
   brasil_unilab_ag, ver 08_lecturas_latam.sql).

   SIN lecturas (ehs.hecho_lectura_mensual) ni metas (ehs.meta) todavia: no
   existen en el Excel ni en ningun documento del area -- se dejan "sin dato"/
   "sin_meta" hasta que EHS las entregue, igual que cualquier sitio LATAM
   nuevo (R.5 de EssilorLuxottica/CLAUDE.md, no se inventa).

   No hay nombre de operador real que fijar para estas 7 (a diferencia de
   Megalux/Optica Popular/Unilab), por eso el id y el rotulo son genericos:
   "Agencias <Pais>". Idempotente (insert ... on conflict ... do update),
   se puede re-correr sin duplicar.

   Decidido en docs/superpowers/specs/2026-11-24-agencias-por-pais-y-mapa-general-design.md.
   ============================================================================= */

begin;

insert into ref.dim_sitio
    (sitio_id, sitio, sitio_corto, nombre_corporativo, tipo, ciudad,
     en_nacional_labs, en_nacional, en_colombia_peru, activo) values
    ('mexico_agencias', 'Agencias Mexico', 'Agencias', 'Agencias Mexico', 'Agencia', null, false, false, false, true),
    ('argentina_agencias', 'Agencias Argentina', 'Agencias', 'Agencias Argentina', 'Agencia', null, false, false, false, true),
    ('costa_rica_agencias', 'Agencias Costa Rica', 'Agencias', 'Agencias Costa Rica', 'Agencia', null, false, false, false, true),
    ('nicaragua_agencias', 'Agencias Nicaragua', 'Agencias', 'Agencias Nicaragua', 'Agencia', null, false, false, false, true),
    ('rd_agencias', 'Agencias Republica Dominicana', 'Agencias', 'Agencias Republica Dominicana', 'Agencia', null, false, false, false, true),
    ('guatemala_agencias', 'Agencias Guatemala', 'Agencias', 'Agencias Guatemala', 'Agencia', null, false, false, false, true),
    ('ecuador_agencias', 'Agencias Ecuador', 'Agencias', 'Agencias Ecuador', 'Agencia', null, false, false, false, true)
on conflict (sitio_id) do update set
    sitio = excluded.sitio, sitio_corto = excluded.sitio_corto,
    nombre_corporativo = excluded.nombre_corporativo, ciudad = excluded.ciudad;

insert into ref.bridge_ambito_sitio (ambito_id, sitio_id) values
    ('mexico', 'mexico_agencias'),
    ('latam', 'mexico_agencias'),
    ('argentina', 'argentina_agencias'),
    ('latam', 'argentina_agencias'),
    ('costa_rica', 'costa_rica_agencias'),
    ('latam', 'costa_rica_agencias'),
    ('nicaragua', 'nicaragua_agencias'),
    ('latam', 'nicaragua_agencias'),
    ('rep_dominicana', 'rd_agencias'),
    ('latam', 'rd_agencias'),
    ('guatemala', 'guatemala_agencias'),
    ('latam', 'guatemala_agencias'),
    ('ecuador', 'ecuador_agencias'),
    ('latam', 'ecuador_agencias')
on conflict (ambito_id, sitio_id) do nothing;

commit;
