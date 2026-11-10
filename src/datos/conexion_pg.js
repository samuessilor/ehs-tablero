/**
 * La conexion a Postgres (destino: Neon), una sola vez para lectura y escritura.
 *
 * Puerto literal de conexion_sql.js (driver 'mssql' -> 'pg'), mismo contrato:
 * exporta pool()/cerrar() con la misma firma y lee las MISMAS variables de
 * entorno que la version SQL Server (SQL_SERVIDOR, SQL_PUERTO, SQL_BASE,
 * SQL_USUARIO, SQL_CLAVE, SQL_MIGRADOR_USUARIO, SQL_MIGRADOR_CLAVE,
 * SQL_TIMEOUT_CONEXION_MS, SQL_TIMEOUT_CONSULTA_MS, SQL_CONFIAR_CERT,
 * SQL_CIFRAR), para que config/ehs.env y el instalador no necesiten saber cual
 * de los dos motores hay detras.
 *
 * EL DRIVER. 'pg' reemplaza a 'mssql' como la unica dependencia de ejecucion
 * nueva (R.3.4). Se carga perezosamente, igual que el original: el interinato
 * (ORIGEN_DATOS=json) nunca lo toca.
 *
 * DIFERENCIA DELIBERADA CON EL ORIGINAL — TLS siempre activo. SQL_CIFRAR
 * existia para apagar el cifrado contra un SQL Server interno sin TLS
 * configurado; Neon EXIGE sslmode=require en toda conexion (lo dice la tarea
 * de porte y lo confirma la documentacion de Neon), asi que aqui ssl no se
 * apaga nunca, sin importar el valor de SQL_CIFRAR. La variable se sigue
 * leyendo (no se borra del contrato de entorno) pero no apaga nada: se deja
 * constancia en vez de fallar en silencio si alguien la pone en '0' esperando
 * el efecto que tenia en SQL Server.
 * SQL_CONFIAR_CERT conserva su intencion original (confiar en un certificado
 * no validado — util para un Postgres local/contenedor con TLS autofirmado) y
 * se traduce a `ssl.rejectUnauthorized`. Contra Neon su certificado es
 * publico y valido, asi que lo normal es NO ponerla.
 */
const { obtener, rutaConfig } = require('./configuracion');

let pgDriver = null;
let poolPrometido = null;

function cargarDriver() {
  if (pgDriver) return pgDriver;
  try {
    pgDriver = require('pg');
  } catch {
    const e = new Error(
      "Falta el driver 'pg'. Es la unica dependencia nueva del proyecto para Postgres y " +
        'esta pendiente de acordarse con IT (R.3.4). Sin el, usa ORIGEN_DATOS=json.'
    );
    e.codigo = 'driver_ausente';
    throw e;
  }
  return pgDriver;
}

/**
 * Configuracion desde el entorno o, si no esta ahi, desde el archivo que dejo el
 * instalador (ver configuracion.js). Ninguna credencial vive en el repositorio.
 *
 * @param {object} [opciones]
 * @param {string} [opciones.prefijoUsuario] 'SQL' de forma predeterminada, lee
 *   SQL_USUARIO/SQL_CLAVE — la identidad de la aplicacion (ehs_app: solo lectura +
 *   EXECUTE en los 3 procedimientos, ver postgres/04_roles.sql). El ejecutor de
 *   migraciones pasa 'SQL_MIGRADOR' para conectarse como ehs_migrador (DDL), sin
 *   duplicar servidor/base/puerto, que son iguales para los dos roles.
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

  const timeoutConexion = Number(obtener('SQL_TIMEOUT_CONEXION_MS') || 5000);
  const timeoutConsulta = Number(obtener('SQL_TIMEOUT_CONSULTA_MS') || 15000);

  return {
    host: obtener('SQL_SERVIDOR'),
    database: obtener('SQL_BASE'),
    user: obtener(claveUsuario),
    password: obtener(claveClave),
    port: Number(obtener('SQL_PUERTO') || 5432),
    max: 4,
    idleTimeoutMillis: 30000,
    /* Equivalente de connectionTimeout/requestTimeout del original: sin esto, un
       motor caido o inalcanzable tarda mucho mas en fallar que lo que el tablero
       puede esperar antes de mostrar el mensaje entendible que errores.js ya sabe
       dar para otros casos. */
    connectionTimeoutMillis: timeoutConexion,
    query_timeout: timeoutConsulta,
    statement_timeout: timeoutConsulta,
    // Neon exige TLS siempre — ver nota de arriba. SQL_CONFIAR_CERT sigue siendo
    // el escape para un certificado no validado (contenedor local), nunca para
    // apagar TLS por completo.
    ssl: { require: true, rejectUnauthorized: obtener('SQL_CONFIAR_CERT') !== '1' },
  };
}

/**
 * @param {object} [opciones] Se reenvia tal cual a configuracion(). Un mismo proceso
 *   solo usa una identidad (la app o el migrador, nunca las dos), asi que un solo
 *   pool en cache alcanza — no hace falta una cache por prefijo.
 */
async function pool(opciones = {}) {
  if (!poolPrometido) {
    const pg = cargarDriver();
    const nuevoPool = new pg.Pool(configuracion(opciones));
    // pg.Pool no valida la conexion hasta la primera consulta (a diferencia de
    // mssql.ConnectionPool().connect()); se saca y se suelta un cliente aqui
    // mismo para que un motor caido o credenciales malas fallen AHORA, en el
    // await pool() de quien llama, y no en la primera consulta silenciosamente
    // mas adelante — el mismo contrato que tenia el original.
    poolPrometido = nuevoPool
      .connect()
      .then((cliente) => {
        cliente.release();
        return nuevoPool;
      })
      .catch((err) => {
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
  if (p) await p.end();
}

module.exports = { cargarDriver, configuracion, pool, cerrar };
