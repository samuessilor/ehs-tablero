/* =============================================================================
   06_paises_latam.sql -- estructura generica de ambito (pais/region/LATAM) +
   los 10 paises nuevos de LATAM bajo la MISMA estructura de datos que Colombia
   y Peru, mas las metas 2026 que trae la hoja TARGETS de "EHS BD LATAM".

   Patron: jerarquia irregular (bridge table), no columnas booleanas por
   ambito. Celta/Estrella/Agencias/Peru/Colombia/Colombia+Peru NO se tocan --
   siguen viviendo en ref.dim_sitio (columnas en_nacional... & en_colombia_peru) y
   en las primeras 3 ramas de ehs.v_ambito, exactamente como estaban. Este
   archivo SOLO agrega una cuarta rama a esa vista, generica, para todo lo
   que entra por este archivo. Ningun resultado existente cambia.

   Fuente de los datos: Excel "EHS BD LATAM", hoja TARGETS, columna
   "Target 2026" -- version final entregada por Samuel el 10-nov-2026.
   Alcance: SOLO metas 2026 y la lista de sitios/paises vigente. NO se carga
   el historico 2019-2023 de las hojas por pais (KPI General / MEX / BRA /
   ...): es dato operativo real de la empresa, misma decision aparte que ya
   esta pendiente para el historico de Colombia/Peru.

   Idempotente (insert ... on conflict), se corre con ehs_migrador despues de
   01-05.
   ============================================================================= */

begin;

-- ---------------------------------------------------------------------------
-- ref.dim_ambito / ref.bridge_ambito_sitio -- la jerarquia generica
-- ---------------------------------------------------------------------------
create table if not exists ref.dim_ambito (
    ambito_id      varchar(40)  not null,
    ambito         varchar(80)  not null,
    nivel          varchar(20)  not null,
    ambito_padre_id varchar(40) null,
    activo         boolean      not null default true,
    constraint pk_dim_ambito primary key (ambito_id),
    constraint ck_dim_ambito_nivel check (nivel in ('latam', 'region', 'pais')),
    constraint fk_dim_ambito_padre foreign key (ambito_padre_id) references ref.dim_ambito (ambito_id)
);

-- ref.bridge_ambito_sitio -- UNA fila por sitio x cada ambito ancestro (pais,
-- region si tiene, LATAM). No es "padre inmediato": v_ambito necesita el
-- camino completo para que un solo group by agregue en cualquier nivel.
create table if not exists ref.bridge_ambito_sitio (
    ambito_id  varchar(40) not null,
    sitio_id   varchar(20) not null,
    constraint pk_bridge_ambito_sitio primary key (ambito_id, sitio_id),
    constraint fk_bridge_ambito foreign key (ambito_id) references ref.dim_ambito (ambito_id),
    constraint fk_bridge_sitio  foreign key (sitio_id)  references ref.dim_sitio (sitio_id)
);

-- ---------------------------------------------------------------- ref.dim_ambito
insert into ref.dim_ambito (ambito_id, ambito, nivel, ambito_padre_id) values
    ('latam', 'LATAM', 'latam', null),
    ('andina', 'Andina', 'region', 'latam'),
    ('ca_caribe', 'Centroamérica y Caribe', 'region', 'latam'),
    ('mexico', 'México', 'pais', 'latam'),
    ('brasil', 'Brasil', 'pais', 'latam'),
    ('argentina', 'Argentina', 'pais', 'andina'),
    ('chile', 'Chile', 'pais', 'andina'),
    ('costa_rica', 'Costa Rica', 'pais', 'ca_caribe'),
    ('nicaragua', 'Nicaragua', 'pais', 'ca_caribe'),
    ('rep_dominicana', 'República Dominicana', 'pais', 'ca_caribe'),
    ('guatemala', 'Guatemala', 'pais', 'ca_caribe'),
    ('honduras', 'Honduras', 'pais', 'ca_caribe'),
    ('ecuador', 'Ecuador', 'pais', 'latam'),
    ('eua', 'Estados Unidos', 'pais', 'latam')
on conflict (ambito_id) do update set
    ambito = excluded.ambito, nivel = excluded.nivel, ambito_padre_id = excluded.ambito_padre_id;

-- ----------------------------------------------------------------- ref.dim_sitio (sitios nuevos)
insert into ref.dim_sitio
    (sitio_id, sitio, sitio_corto, nombre_corporativo, tipo, ciudad,
     en_nacional_labs, en_nacional, en_colombia_peru, activo) values
    ('mexico_norte', 'Norte', 'Norte', 'EMEX Norte', 'Laboratorio', null, false, false, false, true),
    ('mexico_occidente', 'Occidente', 'Occidente', 'EMEX Occidente', 'Laboratorio', null, false, false, false, true),
    ('brasil_tecnolens', 'Tecnolens', 'Tecnolens', 'Tecnolens Sao Paulo', 'Laboratorio', 'Sao Paulo', false, false, false, true),
    ('brasil_multi_bras', 'Multi Bras', 'Multi Bras', 'Multi Bras', 'Laboratorio', 'Sao Paulo', false, false, false, true),
    ('brasil_optilab', 'Optilab Curitiba', 'Optilab Curitiba', 'Optilab Curitiba', 'Laboratorio', 'Curitiba', false, false, false, true),
    ('brasil_embrapol', 'Embrapol Pinhais', 'Embrapol Pinhais', 'Embrapol Pinhais', 'Laboratorio', 'Pinhais', false, false, false, true),
    ('brasil_unilab', 'Unilab Fortaleza', 'Unilab Fortaleza', 'Unilab Fortaleza', 'Laboratorio', 'Fortaleza', false, false, false, true),
    ('brasil_digitop', 'Digitop Pinhais', 'Digitop Pinhais', 'Digitop Pinhais', 'Laboratorio', 'Pinhais', false, false, false, true),
    ('brasil_lab_repro', 'Lab Repro', 'Lab Repro', 'Lab Repro', 'Laboratorio', null, false, false, false, true),
    ('brasil_multi_pr', 'Multi PR', 'Multi PR', 'Multi PR', 'Laboratorio', null, false, false, false, true),
    ('brasil_grown', 'Grown', 'Grown', 'Grown Optical Sao Paulo', 'Laboratorio', 'Sao Paulo', false, false, false, true),
    ('brasil_comprol', 'Comprol Brasilia', 'Comprol Brasilia', 'Comprol Brasilia', 'Laboratorio', 'Brasilia', false, false, false, true),
    ('brasil_minas_gerais', 'Minas Gerais / Belo Horizonte', 'Minas Gerais', 'Minas Gerais / Belo Horizonte', 'Laboratorio', 'Belo Horizonte', false, false, false, true),
    ('brasil_porto_alegre', 'Multi Porto Alegre', 'Multi Porto Alegre', 'Multi Porto Alegre', 'Laboratorio', 'Porto Alegre', false, false, false, true),
    ('brasil_psa_nilo_bh', 'PSA Nilo Belo Horizonte', 'PSA Nilo BH', 'PSA Nilo Belo Horizonte', 'Laboratorio', 'Belo Horizonte', false, false, false, true),
    ('brasil_lab_rio', 'Lab Rio', 'Lab Rio', 'Lab Rio de Janeiro', 'Laboratorio', 'Rio de Janeiro', false, false, false, true),
    ('brasil_visolab', 'Visolab', 'Visolab', 'Visolab Sergipe', 'Laboratorio', 'Sergipe', false, false, false, true),
    ('brasil_ceditop', 'Ceditop', 'Ceditop', 'Ceditop Porto Alegre', 'Laboratorio', 'Porto Alegre', false, false, false, true),
    ('brasil_riachuelo', 'Riachuelo', 'Riachuelo', 'Riachuelo Sao Paulo', 'Laboratorio', 'Sao Paulo', false, false, false, true),
    ('brasil_m_fortaleza', 'Multi Fortaleza', 'Multi Fortaleza', 'Multi Fortaleza', 'Laboratorio', 'Fortaleza', false, false, false, true),
    ('brasil_rx_optical', 'RX Optical', 'RX Optical', 'RX Optical Solutions Recife', 'Laboratorio', 'Recife', false, false, false, true),
    ('brasil_technopark', 'Technopark', 'Technopark', 'Technopark Sao Paulo', 'Laboratorio', 'Sao Paulo', false, false, false, true),
    ('arg_optovision', 'Optovision', 'Optovision', 'Optovision Buenos Aires', 'Laboratorio', 'Buenos Aires', false, false, false, true),
    ('arg_essilor', 'Essilor Argentina', 'Essilor Argentina', 'Essilor Argentina Buenos Aires', 'Laboratorio', 'Buenos Aires', false, false, false, true),
    ('arg_mas_vision', 'Mas Vision', 'Mas Vision', 'Mas Vision Buenos Aires', 'Laboratorio', 'Buenos Aires', false, false, false, true),
    ('chile_megalux', 'Megalux Chile', 'Megalux', 'Megalux Chile', 'Laboratorio', null, false, false, false, true),
    ('costa_rica_san_jose', 'Vision Costa Rica', 'Vision CR', 'Vision Costa Rica San Jose', 'Laboratorio', 'San Jose', false, false, false, true),
    ('nicaragua_managua', 'Vision Rx Managua', 'Vision Rx', 'Vision Rx Lab Managua', 'Laboratorio', 'Managua', false, false, false, true),
    ('rd_santo_domingo', 'Opti-Express Santo Domingo', 'Opti-Express SD', 'Opti-Express Santo Domingo', 'Laboratorio', 'Santo Domingo', false, false, false, true),
    ('rd_santiago', 'Opti-Express Santiago', 'Opti-Express Stgo', 'Opti-Express Santiago', 'Laboratorio', 'Santiago', false, false, false, true),
    ('guatemala_express', 'Lab Express Guatemala', 'Lab Express', 'Lab Express Guatemala', 'Laboratorio', 'Guatemala', false, false, false, true),
    ('guatemala_central_oe', 'Lab Central OE Guatemala', 'Lab Central OE', 'Lab Central OE Guatemala', 'Laboratorio', 'Guatemala', false, false, false, true),
    ('honduras_popular', 'Optica Popular Honduras', 'Optica Popular', 'Optica Popular Honduras', 'Laboratorio', null, false, false, false, true),
    ('ecuador_quito', 'Indulentes Quito', 'Indulentes Quito', 'Indulentes Quito', 'Laboratorio', 'Quito', false, false, false, true),
    ('ecuador_guayaquil', 'Indulentes Guayaquil', 'Indulentes GYE', 'Indulentes Guayaquil', 'Laboratorio', 'Guayaquil', false, false, false, true),
    ('ecuador_quito_gyq', 'Indulentes Quito Express GYQ', 'Indulentes Express', 'Indulentes Quito Express GYQ', 'Laboratorio', 'Quito', false, false, false, true),
    ('ecuador_sto_dgo', 'Indulentes Quito Santo Domingo', 'Indulentes Sto Dgo', 'Indulentes Quito Santo Domingo', 'Laboratorio', 'Santo Domingo', false, false, false, true),
    ('ecuador_cuenca', 'Indulentes Quito Cuenca', 'Indulentes Cuenca', 'Indulentes Quito Cuenca', 'Laboratorio', 'Cuenca', false, false, false, true),
    ('eua_elac', 'Warehouse ELAC', 'ELAC', 'Warehouse ELAC', 'Laboratorio', null, false, false, false, true)
on conflict (sitio_id) do update set
    sitio = excluded.sitio, sitio_corto = excluded.sitio_corto,
    nombre_corporativo = excluded.nombre_corporativo, ciudad = excluded.ciudad;

-- --------------------------------------------------------- ref.bridge_ambito_sitio
insert into ref.bridge_ambito_sitio (ambito_id, sitio_id) values
    ('mexico', 'mexico_norte'),
    ('latam', 'mexico_norte'),
    ('mexico', 'mexico_occidente'),
    ('latam', 'mexico_occidente'),
    ('brasil', 'brasil_tecnolens'),
    ('latam', 'brasil_tecnolens'),
    ('brasil', 'brasil_multi_bras'),
    ('latam', 'brasil_multi_bras'),
    ('brasil', 'brasil_optilab'),
    ('latam', 'brasil_optilab'),
    ('brasil', 'brasil_embrapol'),
    ('latam', 'brasil_embrapol'),
    ('brasil', 'brasil_unilab'),
    ('latam', 'brasil_unilab'),
    ('brasil', 'brasil_digitop'),
    ('latam', 'brasil_digitop'),
    ('brasil', 'brasil_lab_repro'),
    ('latam', 'brasil_lab_repro'),
    ('brasil', 'brasil_multi_pr'),
    ('latam', 'brasil_multi_pr'),
    ('brasil', 'brasil_grown'),
    ('latam', 'brasil_grown'),
    ('brasil', 'brasil_comprol'),
    ('latam', 'brasil_comprol'),
    ('brasil', 'brasil_minas_gerais'),
    ('latam', 'brasil_minas_gerais'),
    ('brasil', 'brasil_porto_alegre'),
    ('latam', 'brasil_porto_alegre'),
    ('brasil', 'brasil_psa_nilo_bh'),
    ('latam', 'brasil_psa_nilo_bh'),
    ('brasil', 'brasil_lab_rio'),
    ('latam', 'brasil_lab_rio'),
    ('brasil', 'brasil_visolab'),
    ('latam', 'brasil_visolab'),
    ('brasil', 'brasil_ceditop'),
    ('latam', 'brasil_ceditop'),
    ('brasil', 'brasil_riachuelo'),
    ('latam', 'brasil_riachuelo'),
    ('brasil', 'brasil_m_fortaleza'),
    ('latam', 'brasil_m_fortaleza'),
    ('brasil', 'brasil_rx_optical'),
    ('latam', 'brasil_rx_optical'),
    ('brasil', 'brasil_technopark'),
    ('latam', 'brasil_technopark'),
    ('argentina', 'arg_optovision'),
    ('andina', 'arg_optovision'),
    ('latam', 'arg_optovision'),
    ('argentina', 'arg_essilor'),
    ('andina', 'arg_essilor'),
    ('latam', 'arg_essilor'),
    ('argentina', 'arg_mas_vision'),
    ('andina', 'arg_mas_vision'),
    ('latam', 'arg_mas_vision'),
    ('chile', 'chile_megalux'),
    ('andina', 'chile_megalux'),
    ('latam', 'chile_megalux'),
    ('costa_rica', 'costa_rica_san_jose'),
    ('ca_caribe', 'costa_rica_san_jose'),
    ('latam', 'costa_rica_san_jose'),
    ('nicaragua', 'nicaragua_managua'),
    ('ca_caribe', 'nicaragua_managua'),
    ('latam', 'nicaragua_managua'),
    ('rep_dominicana', 'rd_santo_domingo'),
    ('ca_caribe', 'rd_santo_domingo'),
    ('latam', 'rd_santo_domingo'),
    ('rep_dominicana', 'rd_santiago'),
    ('ca_caribe', 'rd_santiago'),
    ('latam', 'rd_santiago'),
    ('guatemala', 'guatemala_express'),
    ('ca_caribe', 'guatemala_express'),
    ('latam', 'guatemala_express'),
    ('guatemala', 'guatemala_central_oe'),
    ('ca_caribe', 'guatemala_central_oe'),
    ('latam', 'guatemala_central_oe'),
    ('honduras', 'honduras_popular'),
    ('ca_caribe', 'honduras_popular'),
    ('latam', 'honduras_popular'),
    ('ecuador', 'ecuador_quito'),
    ('latam', 'ecuador_quito'),
    ('ecuador', 'ecuador_guayaquil'),
    ('latam', 'ecuador_guayaquil'),
    ('ecuador', 'ecuador_quito_gyq'),
    ('latam', 'ecuador_quito_gyq'),
    ('ecuador', 'ecuador_sto_dgo'),
    ('latam', 'ecuador_sto_dgo'),
    ('ecuador', 'ecuador_cuenca'),
    ('latam', 'ecuador_cuenca'),
    ('eua', 'eua_elac'),
    ('latam', 'eua_elac')
on conflict (ambito_id, sitio_id) do nothing;

-- --------------------------------------------------------------------- ehs.meta
insert into ehs.meta (anio, ambito_id, kpi_id, valor, fuente, vigente) values
    (2026, 'latam', 'agua_por_lente', 7.85, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'latam', 'energia_por_lente', 2.15, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'latam', 'residuos_por_lente', 129.4, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'latam', 'frequency_rate', 2.6, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'latam', 'accidentes_dafw', 27.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'andina', 'agua_por_lente', 12.34, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'andina', 'energia_por_lente', 2.33, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'andina', 'residuos_por_lente', 139.9, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'andina', 'frequency_rate', 2.57, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'andina', 'accidentes_dafw', 3.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ca_caribe', 'agua_por_lente', 9.14, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ca_caribe', 'energia_por_lente', 2.79, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ca_caribe', 'residuos_por_lente', 134.5, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ca_caribe', 'frequency_rate', 1.27, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ca_caribe', 'accidentes_dafw', 2.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico', 'agua_por_lente', 4.07, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico', 'energia_por_lente', 0.97, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico', 'residuos_por_lente', 83.23, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico', 'frequency_rate', 5.65, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico', 'accidentes_dafw', 5.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil', 'agua_por_lente', 8.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil', 'energia_por_lente', 2.4, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil', 'residuos_por_lente', 136.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil', 'frequency_rate', 2.52, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil', 'accidentes_dafw', 12.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica', 'agua_por_lente', 11.04, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica', 'energia_por_lente', 2.97, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica', 'residuos_por_lente', 189.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica', 'frequency_rate', 4.43, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua', 'agua_por_lente', 17.38, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua', 'energia_por_lente', 3.87, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'rep_dominicana', 'agua_por_lente', 6.4, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'rep_dominicana', 'energia_por_lente', 3.05, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'rep_dominicana', 'residuos_por_lente', 12.51, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'rep_dominicana', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'rep_dominicana', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'guatemala', 'agua_por_lente', 5.78, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'guatemala', 'energia_por_lente', 2.53, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'guatemala', 'residuos_por_lente', 100.9, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'guatemala', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'guatemala', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'honduras', 'agua_por_lente', 5.16, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'honduras', 'energia_por_lente', 1.96, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'honduras', 'residuos_por_lente', 94.67, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'honduras', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'honduras', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ecuador', 'agua_por_lente', 12.8, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ecuador', 'energia_por_lente', 2.12, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ecuador', 'residuos_por_lente', 83.4, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ecuador', 'frequency_rate', 9.8, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'ecuador', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile', 'agua_por_lente', 10.3, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile', 'energia_por_lente', 1.74, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile', 'residuos_por_lente', 186.4, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile', 'frequency_rate', 3.47, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_norte', 'agua_por_lente', 6.02, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_norte', 'energia_por_lente', 1.3, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_norte', 'residuos_por_lente', 112.4, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_norte', 'frequency_rate', 6.37, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_norte', 'accidentes_dafw', 4.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_occidente', 'agua_por_lente', 1.26, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_occidente', 'energia_por_lente', 0.45, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_occidente', 'residuos_por_lente', 36.47, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_occidente', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'mexico_occidente', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_tecnolens', 'agua_por_lente', 8.52, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_tecnolens', 'energia_por_lente', 3.06, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_tecnolens', 'residuos_por_lente', 143.2, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_tecnolens', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_tecnolens', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_bras', 'agua_por_lente', 10.49, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_bras', 'energia_por_lente', 3.15, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_bras', 'residuos_por_lente', 28.42, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_bras', 'frequency_rate', 10.15, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_bras', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_optilab', 'agua_por_lente', 2.62, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_optilab', 'energia_por_lente', 0.51, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_optilab', 'residuos_por_lente', 21.7, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_optilab', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_optilab', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_embrapol', 'agua_por_lente', 5.3, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_embrapol', 'energia_por_lente', 0.56, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_embrapol', 'residuos_por_lente', 30.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_embrapol', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_embrapol', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_unilab', 'agua_por_lente', 4.2, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_unilab', 'energia_por_lente', 1.39, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_unilab', 'residuos_por_lente', 175.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_unilab', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_unilab', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_digitop', 'agua_por_lente', 2.49, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_digitop', 'energia_por_lente', 0.67, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_digitop', 'residuos_por_lente', 97.8, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_digitop', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_digitop', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_repro', 'agua_por_lente', 11.34, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_repro', 'energia_por_lente', 2.82, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_repro', 'residuos_por_lente', 151.68, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_repro', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_repro', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_pr', 'agua_por_lente', 8.76, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_pr', 'energia_por_lente', 1.62, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_pr', 'residuos_por_lente', 30.15, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_pr', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_multi_pr', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_grown', 'agua_por_lente', 10.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_grown', 'energia_por_lente', 1.81, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_grown', 'residuos_por_lente', 121.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_grown', 'frequency_rate', 6.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_grown', 'accidentes_dafw', 4.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_comprol', 'agua_por_lente', 3.98, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_comprol', 'energia_por_lente', 1.07, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_comprol', 'residuos_por_lente', 64.57, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_comprol', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_comprol', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_porto_alegre', 'agua_por_lente', 9.63, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_porto_alegre', 'energia_por_lente', 2.99, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_porto_alegre', 'residuos_por_lente', 15.1, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_porto_alegre', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_porto_alegre', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_psa_nilo_bh', 'agua_por_lente', 2.61, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_psa_nilo_bh', 'energia_por_lente', 0.43, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_psa_nilo_bh', 'residuos_por_lente', 68.18, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_psa_nilo_bh', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_psa_nilo_bh', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_rio', 'agua_por_lente', 6.99, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_rio', 'energia_por_lente', 2.51, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_rio', 'residuos_por_lente', 198.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_rio', 'frequency_rate', 1.49, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_lab_rio', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_visolab', 'agua_por_lente', 9.97, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_visolab', 'energia_por_lente', 5.28, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_visolab', 'residuos_por_lente', 83.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_visolab', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_visolab', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_ceditop', 'agua_por_lente', 0.94, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_ceditop', 'energia_por_lente', 1.32, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_ceditop', 'residuos_por_lente', 117.5, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_ceditop', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_ceditop', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_riachuelo', 'agua_por_lente', 3.29, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_riachuelo', 'energia_por_lente', 0.81, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_riachuelo', 'residuos_por_lente', 56.57, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_riachuelo', 'frequency_rate', 23.98, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_riachuelo', 'accidentes_dafw', 3.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_m_fortaleza', 'agua_por_lente', 10.93, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_m_fortaleza', 'energia_por_lente', 2.42, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_m_fortaleza', 'residuos_por_lente', 16.35, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_m_fortaleza', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_m_fortaleza', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_rx_optical', 'agua_por_lente', 4.63, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_rx_optical', 'energia_por_lente', 0.96, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_rx_optical', 'residuos_por_lente', 149.6, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_rx_optical', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_rx_optical', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_technopark', 'agua_por_lente', 10.39, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_technopark', 'energia_por_lente', 3.21, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_technopark', 'residuos_por_lente', 289.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_technopark', 'frequency_rate', 1.95, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'brasil_technopark', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_optovision', 'agua_por_lente', 10.56, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_optovision', 'energia_por_lente', 1.65, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_optovision', 'residuos_por_lente', 93.45, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_optovision', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_optovision', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_essilor', 'agua_por_lente', 10.96, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_essilor', 'energia_por_lente', 3.68, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_essilor', 'residuos_por_lente', 282.21, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_essilor', 'frequency_rate', 4.41, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_essilor', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_mas_vision', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'arg_mas_vision', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile_megalux', 'agua_por_lente', 10.3, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile_megalux', 'energia_por_lente', 1.74, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile_megalux', 'residuos_por_lente', 186.4, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile_megalux', 'frequency_rate', 3.47, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'chile_megalux', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica_san_jose', 'agua_por_lente', 11.04, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica_san_jose', 'energia_por_lente', 2.97, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica_san_jose', 'residuos_por_lente', 189.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica_san_jose', 'frequency_rate', 4.43, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'costa_rica_san_jose', 'accidentes_dafw', 1.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua_managua', 'agua_por_lente', 17.38, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua_managua', 'energia_por_lente', 3.87, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua_managua', 'frequency_rate', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true),
    (2026, 'nicaragua_managua', 'accidentes_dafw', 0.0, 'TARGETS LATAM 2026 (Excel "EHS BD LATAM", hoja TARGETS)', true)
on conflict (anio, ambito_id, kpi_id, fuente) do update set valor = excluded.valor, vigente = excluded.vigente;

-- ---------------------------------------------------------------------------
-- ehs.v_ambito -- se agrega una CUARTA rama, generica, sobre el bridge nuevo.
-- Las primeras 3 ramas (sitio, nacional_labs, nacional, colombia_peru) NO se
-- tocan: ningun resultado existente de Celta/Estrella/Agencias/Peru/Colombia
-- cambia. La rama nueva cubre cualquier ambito que venga de
-- ref.bridge_ambito_sitio (los 10 paises de este archivo, y cualquier pais
-- futuro que se agregue solo insertando filas, sin tocar esta vista otra vez).
-- ---------------------------------------------------------------------------
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
     where activo and en_colombia_peru
    union all
    select b.sitio_id, b.ambito_id, a.ambito, 5 as orden
      from ref.bridge_ambito_sitio b
      join ref.dim_ambito a on a.ambito_id = b.ambito_id
      join ref.dim_sitio  s on s.sitio_id = b.sitio_id and s.activo;

commit;

\echo 'Paises LATAM cargados: 14 ambitos (LATAM/2 regiones/11 paises), 39 sitios, metas 2026 donde el Excel las trae.'
