/**
 * La instantanea: las respuestas del adaptador SQL, guardadas tal cual, para que el
 * modo JSON (Vercel, sin base de datos) muestre EXACTAMENTE lo mismo que la
 * instalacion con SQL Server.
 *
 * Antes el modo JSON reconstruia cada respuesta a partir de un manifiesto propio
 * (datos.json), con su propia logica: sin querer, una segunda implementacion. Con el
 * tiempo divergio de la de SQL en decenas de detalles (medidos: 521 diferencias en
 * 129 llamadas), algunos de ellos de dato real — el accidente de Celta seguia en
 * mayo, la seguridad de Peru aparecia "cumple" en vez de "sin dato". Guardar lo que
 * SQL respondio y devolverlo intacto hace que las dos no puedan diferir.
 *
 * Este modulo define una sola cosa: la clave con que cada respuesta se guarda (en
 * analisis/exportar_instantanea_sql.js) y se busca (en adaptador_json.js). Si cada
 * lado la armara a su manera, la busqueda fallaria en silencio y el modo JSON
 * volveria al manifiesto viejo sin que nadie lo notara.
 */

/** Que argumentos distinguen una respuesta de otra, por funcion del adaptador. */
const CAMPOS = {
  panorama: ['anio', 'mes', 'ambito'],
  kpiPorSitio: ['anio', 'mes', 'kpi'],
  serieMensual: ['anio', 'ambito', 'kpi'],
  aguaMensual: ['anio', 'ambito'],
  energiaMensual: ['anio', 'ambito'],
  aguaDiaria: ['anio', 'mes', 'sitio'],
  residuosComposicion: ['anio', 'ambito'],
  trayectoriaAnual: ['kpi', 'ambito'],
  contrasteMensual: ['ambito', 'kpi', 'anioA', 'anioB'],
  calidadDato: ['anio'],
  detalle: ['anio'],
  datosTabulados: ['anio', 'ambito'],
};

/**
 * anio/mes ausentes significan "el corte publicado" en los dos adaptadores (alCorte),
 * y trayectoriaAnual usa 'nacional' si no se le dice ambito: se normalizan igual aqui,
 * para que pedir /panorama sin mes y pedirlo con el mes del corte den la misma clave.
 */
function clave(funcion, args, ctx) {
  const campos = CAMPOS[funcion];
  const a = Object.assign({}, args);
  if (a.anio == null) a.anio = ctx.anio;
  if (a.mes == null) a.mes = ctx.corte;
  if (funcion === 'trayectoriaAnual' && a.ambito == null) a.ambito = 'nacional';
  return funcion + '|' + campos.map((c) => c + '=' + (a[c] == null ? '' : String(a[c]))).join('&');
}

module.exports = { CAMPOS, clave };
