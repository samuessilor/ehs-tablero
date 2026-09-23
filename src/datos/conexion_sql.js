/**
 * La conexion a SQL Server, una sola vez para lectura y escritura.
 *
 * Antes este bloque vivia entero dentro de escritura_sql.js. Cuando adaptador_sql.js
 * dejo de ser un esqueleto hubo dos modulos que necesitaban el mismo pool, la misma
 * configuracion y la misma carga perezosa del driver; copiarlo habria dejado dos
 * verdades sobre como se conecta esta aplicacion, y la segunda se enteraria tarde de
 * cualquier cambio en la primera.
 *
 * EL DRIVER. 'mssql' es la unica dependencia de ejecucion que este proyecto anade a
 * la tabla del estandar, y R.3.4 obliga a acordarla con IT antes de usarla en
 * produccion. Por eso se carga aqui dentro y no arriba del archivo: el interinato
 * (ORIGEN_DATOS=json) nunca lo toca, sigue con las mismas dos dependencias de
 * siempre, y un despliegue sin el driver instalado arranca igual en vez de caerse.
 */
const { obtener, rutaConfig } = require('./configuracion');

let mssql = null;
let poolPrometido = null;

function cargarDriver() {
  if (mssql) return mssql;
  try {
    mssql = require('mssql');
  } catch {
    const e = new Error(
      "Falta el driver 'mssql'. Es la unica dependencia nueva del proyecto y esta " +
        'pendiente de acordarse con IT (R.3.4). Sin el, usa ORIGEN_DATOS=json.'
    );
    e.codigo = 'driver_ausente';
    throw e;
  }
  return mssql;
}

/**
 * Configuracion desde el entorno o, si no esta ahi, desde el archivo que dejo el
 * instalador (ver configuracion.js). Ninguna credencial vive en el repositorio.
 *
 * @param {object} [opciones]
 * @param {string} [opciones.prefijoUsuario] 'SQL' de forma predeterminada, lee
 *   SQL_USUARIO/SQL_CLAVE — la identidad de la aplicacion (solo DML). El ejecutor de
 *   migraciones pasa 'SQL_MIGRADOR' para conectarse con la identidad que tiene DDL,
 *   sin duplicar servidor/base/puerto/cifrado, que son iguales para las dos.
 */
function configuracion(opciones = {}) {
  const prefijoUsuario = opciones.prefijoUsuario || 'SQL';
  const claveUsuario = `${prefijoUsuario}_USUARIO`;
  const claveClave = `${prefijoUsuario}_CLAVE`;

  const requeridas = ['SQL_SERVIDOR', 'SQL_BASE', claveUsuario, claveClave];
  const faltan = requeridas.filter((v) => !obtener(v));
  if (faltan.length) {
    const e = new Error(
      `Faltan variables de conexion: ${faltan.join(', ')} (entorno o ${rutaConfig()}).`
    );
    e.codigo = 'configuracion_incompleta';
    throw e;
  }
  return {
    server: obtener('SQL_SERVIDOR'),
    database: obtener('SQL_BASE'),
    user: obtener(claveUsuario),
    password: obtener(claveClave),
    port: Number(obtener('SQL_PUERTO') || 1433),
    options: {
      // El contenedor local y muchos servidores internos usan certificado propio.
      // En produccion esto lo decide IT, no este archivo.
      trustServerCertificate: obtener('SQL_CONFIAR_CERT') === '1',
      encrypt: obtener('SQL_CIFRAR') !== '0',
    },
    pool: { max: 4, min: 0, idleTimeoutMillis: 30000 },
    /* Sin esto, un motor caido o inalcanzable tarda mas de 25 segundos en fallar
       (el timeout por defecto del driver es mucho mas laxo) y el tablero se queda
       "cargando" en vez de mostrar el mensaje entendible que errores.js ya sabe dar
       para otros casos. Cinco segundos alcanza sobrado dentro de 127.0.0.1. */
    connectionTimeout: Number(obtener('SQL_TIMEOUT_CONEXION_MS') || 5000),
    requestTimeout: Number(obtener('SQL_TIMEOUT_CONSULTA_MS') || 15000),
  };
}

/**
 * @param {object} [opciones] Se reenvia tal cual a configuracion(). Un mismo proceso
 *   solo usa una identidad (la app o el migrador, nunca las dos), asi que un solo
 *   pool en cache alcanza — no hace falta una cache por prefijo.
 */
async function pool(opciones = {}) {
  if (!poolPrometido) {
    const sql = cargarDriver();
    poolPrometido = new sql.ConnectionPool(configuracion(opciones)).connect().catch((err) => {
      poolPrometido = null; // que un fallo no deje el pool envenenado para siempre
      throw err;
    });
  }
  return poolPrometido;
}

/** Cierra el pool. Lo usan las pruebas para que el proceso pueda terminar. */
async function cerrar() {
  if (!poolPrometido) return;
  const p = await poolPrometido.catch(() => null);
  poolPrometido = null;
  if (p) await p.close();
}

module.exports = { cargarDriver, configuracion, pool, cerrar };
