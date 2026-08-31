/**
 * Adaptador SQL — el destino. ESQUELETO: se completa cuando IT conceda el esquema.
 *
 * Mismas nueve firmas que adaptador_json.js. Cada funcion consultara las vistas del
 * esquema ehs (app/sql/02-vistas.sql), que implementan las dos reglas del area una sola
 * vez y estan verificadas contra el motor en 17 puntos (verificar_sql_contra_motor.py).
 *
 * Correspondencia funcion -> vista:
 *   panorama      -> ehs.v_kpi_contra_meta (anio, num_mes_corte, ambito_id)
 *   kpiPorSitio   -> ehs.v_kpi_contra_meta filtrada por kpi_id, un ambito por sitio
 *   serieMensual  -> ehs.v_kpi_mensual + ehs.v_kpi_ytd
 *   aguaMensual   -> ehs.v_kpi_mensual filtrada a agua + variaciones en la vista
 *   aguaDiaria    -> ehs.v_agua_diaria + ehs.v_estado_agua_diaria
 *   calidadDato   -> ehs.v_calidad_dato + ehs.v_calidad_avisos (avisos_automaticos)
 *   detalle       -> ehs.hecho_lectura_mensual (solo lectura)
 *   residuosComposicion -> ehs.hecho_lectura_mensual agrupado por magnitud de residuo
 *                          (las tres magnitudes ya son filas: no hace falta vista nueva)
 *   trayectoriaAnual    -> ehs.scorecard_anual
 *
 * Pendiente de la reunion con el DBA (docs/migracion-samii.md):
 *   - driver aprobado por IT para Node -> SQL Server (no se elige unilateralmente: R.3.4)
 *   - servidor, base y credenciales de solo lectura
 *   - si SAMII ya tiene una capa de consulta que sustituya este modulo entero
 */

function pendiente(nombre) {
  const e = new Error(
    `adaptador_sql.${nombre}: sin implementar. Requiere el esquema ehs en SQL Server ` +
      `y el driver acordado con IT. Interinato: ORIGEN_DATOS=json.`
  );
  e.codigo = 'sin_implementar';
  throw e;
}

module.exports = {
  async panorama(_params) {
    pendiente('panorama');
  },
  async kpiPorSitio(_params) {
    pendiente('kpiPorSitio');
  },
  async serieMensual(_params) {
    pendiente('serieMensual');
  },
  async aguaMensual(_params) {
    pendiente('aguaMensual');
  },
  async aguaDiaria(_params) {
    pendiente('aguaDiaria');
  },
  async residuosComposicion(_params) {
    pendiente('residuosComposicion');
  },
  async trayectoriaAnual(_params) {
    pendiente('trayectoriaAnual');
  },
  async calidadDato(_params) {
    pendiente('calidadDato');
  },
  async detalle(_params) {
    pendiente('detalle');
  },
};
