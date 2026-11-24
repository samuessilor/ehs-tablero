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

   ADVERTENCIA para quien cargue la primera lectura real de cualquiera de estas
   7 (ya habilitadas en Capturar/Corregir desde que existe esta fila): la regla
   de negocio 3 de ehs/CLAUDE.md ("un mes cuenta para un ambito solo si TODOS
   sus sitios reportantes lo reportaron") mira todo el anio. Si el primer dato
   que llega es, por ejemplo, solo diciembre, los meses de enero a noviembre
   de ese PAIS (y de 'latam') dejan de contar -- no porque se borre nada, sino
   porque ahora ese sitio tambien cuenta y no los reporto. Cargar un anio
   completo de una vez (o esperar a tenerlo) evita que aparezca un retroceso
   en los demas KPI del pais el mismo dia que esto deja de estar vacio.

   Pendiente de decidir con EHS (no corregido aqui, ver postgres/06_paises_latam.sql
   y postgres/08_lecturas_latam.sql, ya aplicados): estas 7 filas se puentean
   solo a su pais y a 'latam', igual que las 3 agencias existentes
   (chile_megalux_ag, honduras_popular_ag, brasil_unilab_ag) -- ninguna de las
   10 esta puenteada tambien a su region (andina/ca_caribe), aunque
   ref.bridge_ambito_sitio documenta ese tercer nivel para el resto de sitios
   LATAM. Mientras no tengan lectura no afecta a nadie; el dia que la tengan,
   Andina/CA y Caribe quedarian incompletos frente a LATAM.
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
