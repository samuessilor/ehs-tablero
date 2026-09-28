/* =====================================================================
   Migracion 0016 — borrar 2023 de la base (decision de Samuel, 28-sep-2026)
   ---------------------------------------------------------------------
   La seccion 19 del backlog (27-sep-2026) ya habia sacado 2023 de toda
   consulta y visualizacion (API, tablero, ANIOS_CONTRASTE) por regla del
   area: "solo datos desde 2024 en adelante". Eso dejaba el dato de 2023 en
   la base, sin leerse, con la decision de borrarlo fisicamente pendiente de
   que Samuel lo pidiera de forma expresa (operacion destructiva e
   irreversible sobre la base real, regla del repo). Lo pidio: "borra 2023
   de la base".

   Dos tablas, no una:
   - ehs.hecho_lectura_mensual: 144 filas de 2023 (agua_m3, energia_kwh,
     residuo_total_kg, unidades_buenas x Celta/La Estrella/Agencias x 12
     meses — el historico cargado en la migracion 0012, sin desglose de
     residuo porque esos anios no lo traian).
   - ehs.scorecard_anual: 23 filas de 2023 (Celta/La Estrella/Agencias/
     Colombia+Peru x 5 KPI, mas Nacional x 3 KPI de seguridad).

   Nada mas depende de este dato: ehs.tr_lectura_mensual_hist solo archiva
   UPDATE (no DELETE), asi que no hay nada que archivar ahi — el registro de
   que este borrado paso, por que y cuando es este archivo, igual que la
   migracion 0012 es el registro de la correccion del accidente. Sin llaves
   foraneas que referencien ninguna de las dos tablas (verificado contra
   sys.foreign_keys). El trigger de residuo-una-forma (migracion 0015) es
   AFTER INSERT, UPDATE: un DELETE no lo dispara.

   Acotado a anio = 2023 en las dos tablas, nada mas. Idempotente: correrlo
   dos veces borra 0 filas la segunda vez. */

set nocount on;
go

declare @antes_lecturas int = (select count(*) from ehs.hecho_lectura_mensual where year(fecha) = 2023);
declare @antes_scorecard int = (select count(*) from ehs.scorecard_anual where anio = 2023);

delete from ehs.hecho_lectura_mensual where year(fecha) = 2023;
delete from ehs.scorecard_anual where anio = 2023;

declare @msg nvarchar(200) = concat(
    'migracion 0016: borradas ', @antes_lecturas, ' filas de hecho_lectura_mensual y ',
    @antes_scorecard, ' de scorecard_anual (anio = 2023).');
raiserror(@msg, 0, 1) with nowait;
go
