/* ===========================================================================
   Migracion 0013 — Peru se nombra como el pais, no como el laboratorio

   Contexto: la migracion 0011 puso sitio='TOPSA (Peru)', sitio_corto='TOPSA' y
   nombre_corporativo='TOPSA' porque asi lo trae el Excel de origen (hoja "Lab
   Topsa Peru"). Samuel pidio (27-sep-2026) que en pantalla se vea solo como el
   pais: 'Peru' en los tres campos, igual que Celta/Estrella/Agencias se ven
   por su propio nombre. Es solo el ROTULO: sitio_id sigue siendo 'peru', asi
   que no rompe URLs, JSON ni el resto del codigo que ya lo usa.
   =========================================================================== */

update ref.dim_sitio
   set sitio = 'Perú',
       sitio_corto = 'Perú',
       nombre_corporativo = 'Perú'
 where sitio_id = 'peru';
go
