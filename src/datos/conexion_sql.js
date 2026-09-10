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

/** Configuracion desde el entorno. Ninguna credencial vive en el repositorio. */
function configuracion() {
  const faltan = ['SQL_SERVIDOR', 'SQL_BASE', 'SQL_USUARIO', 'SQL_CLAVE'].filter(
    (v) => !process.env[v]
  );
  if (faltan.length) {
    const e = new Error(`Faltan variables de entorno de conexion: ${faltan.join(', ')}.`);
    e.codigo = 'configuracion_incompleta';
    throw e;
  }
  return {
    server: process.env.SQL_SERVIDOR,
    database: process.env.SQL_BASE,
    user: process.env.SQL_USUARIO,
    password: process.env.SQL_CLAVE,
    port: Number(process.env.SQL_PUERTO || 1433),
    options: {
      // El contenedor local y muchos servidores internos usan certificado propio.
      // En produccion esto lo decide IT, no este archivo.
      trustServerCertificate: process.env.SQL_CONFIAR_CERT === '1',
      encrypt: process.env.SQL_CIFRAR !== '0',
    },
    pool: { max: 4, min: 0, idleTimeoutMillis: 30000 },
  };
}

async function pool() {
  if (!poolPrometido) {
    const sql = cargarDriver();
    poolPrometido = new sql.ConnectionPool(configuracion()).connect().catch((err) => {
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
