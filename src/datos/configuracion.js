/**
 * Configuracion por archivo, no por variables de shell sueltas.
 *
 * El interinato de esta sesion (Docker local, Vercel) siempre configuro la conexion
 * con variables de entorno puestas a mano en la terminal o en el panel de Vercel. Eso
 * deja de alcanzar en cuanto la aplicacion se instala en el equipo del area: no hay
 * terminal, no hay panel, no hay quien exporte nada — el instalador es lo unico que
 * toca esa maquina, y lo hace una vez.
 *
 * Este modulo no reemplaza las variables de entorno, las complementa: si una variable
 * ya viene puesta en el proceso (como en Docker/Vercel), esa gana. Si no, se busca en
 * el archivo que el instalador dejo escrito. Ningun valor por defecto sustituye a
 * ninguno de los dos: una variable ausente en ambos sigue siendo un error explicito
 * donde ya lo era (ver conexion_sql.js).
 *
 * No se anade una dependencia como 'dotenv' para esto: el formato que hace falta leer
 * es CLAVE=valor por linea, y cubrirlo entero son menos lineas que las que costaria
 * justificar una dependencia nueva ante R.3.4.
 */
const fs = require('fs');
const path = require('path');

let cache = null;
let cacheRuta = null;

/** Donde el instalador deja el archivo, salvo que EHS_CONFIG_ARCHIVO diga otra cosa. */
function rutaConfig() {
  if (process.env.EHS_CONFIG_ARCHIVO) return process.env.EHS_CONFIG_ARCHIVO;
  return path.join(__dirname, '..', '..', 'config', 'ehs.env');
}

/** CLAVE=valor por linea. '#' al inicio de linea comenta. Comillas alrededor del
 * valor son opcionales y se retiran si estan, para poder guardar valores con
 * espacios sin ambiguedad. */
function parsear(contenido) {
  const variables = {};
  for (const lineaCruda of contenido.split(/\r?\n/)) {
    const linea = lineaCruda.trim();
    if (!linea || linea.startsWith('#')) continue;
    const igual = linea.indexOf('=');
    if (igual === -1) continue;
    const clave = linea.slice(0, igual).trim();
    let valor = linea.slice(igual + 1).trim();
    if (
      (valor.startsWith('"') && valor.endsWith('"')) ||
      (valor.startsWith("'") && valor.endsWith("'"))
    ) {
      valor = valor.slice(1, -1);
    }
    if (clave) variables[clave] = valor;
  }
  return variables;
}

function archivo() {
  const ruta = rutaConfig();
  if (cache && cacheRuta === ruta) return cache;
  cacheRuta = ruta;
  try {
    cache = parsear(fs.readFileSync(ruta, 'utf8'));
  } catch {
    cache = {}; // sin archivo no es error: puede que todo llegue por el entorno
  }
  return cache;
}

/** El entorno del proceso manda; el archivo es el respaldo para la instalacion
 * de escritorio, donde no hay quien exporte nada. */
function obtener(nombre) {
  if (process.env[nombre] !== undefined && process.env[nombre] !== '') {
    return process.env[nombre];
  }
  const valor = archivo()[nombre];
  return valor === undefined || valor === '' ? undefined : valor;
}

/** Las pruebas cambian EHS_CONFIG_ARCHIVO entre casos; sin esto seguirian viendo
 * el archivo del primer caso que se leyo. */
function limpiarCache() {
  cache = null;
  cacheRuta = null;
}

module.exports = { obtener, rutaConfig, limpiarCache };
