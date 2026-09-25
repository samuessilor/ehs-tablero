#!/usr/bin/env node
/**
 * Ejecutor de migraciones — el unico camino para llevar `analitica` de vacia a
 * su estado actual, y el unico camino para actualizarla despues.
 *
 * Aplica cada archivo de migraciones/*.sql en orden de nombre, una sola vez, y dejar
 * constancia en ops.migracion_aplicada. Correrlo dos veces no hace nada la segunda
 * vez: es la misma idempotencia que R.5.3.3 exige de sp_capturar_lote, aplicada aqui
 * a la estructura en vez de al dato.
 *
 * Por que existe como script aparte y no como codigo dentro de servidor.js: la
 * identidad que necesita (DDL) es justo la que la aplicacion NUNCA debe tener en
 * ejecucion normal (R.4.1, implementador != desplegador). Se conecta con
 * SQL_MIGRADOR_USUARIO/SQL_MIGRADOR_CLAVE, no con SQL_USUARIO/SQL_CLAVE.
 *
 * Uso:
 *   node scripts/migrar.js                    aplica lo pendiente (sin datos de ejemplo)
 *   node scripts/migrar.js --con-datos-semilla incluye 0008_carga_inicial.sql
 *   node scripts/migrar.js --estado            solo informa que esta aplicado, sin tocar nada
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const conexion = require('../src/datos/conexion_sql');

const DIR_MIGRACIONES = path.join(__dirname, '..', 'migraciones');
/* Datos propios de este sitio (Servioptica), no esquema generico: una
   instalacion nueva en un sitio real no debe arrancar con ellos ya cargados.
   0012 se suma a 0008 con el mismo criterio — historico y Peru son del mismo
   tipo de dato que la carga inicial 2026, solo que llegaron despues. */
const ARCHIVOS_DATOS_SEMILLA = new Set(['0008_carga_inicial.sql', '0012_ehs_historico_peru_accidente.sql']);

/* Separador de lotes al estilo sqlcmd/SSMS: 'go' solo en su propia linea (con
   espacio opcional alrededor). No es T-SQL: el driver nunca veria ese token si se
   enviara tal cual, por eso el archivo se corta aqui antes de mandar nada. */
const SEPARADOR_LOTE = /^\s*go\s*$/im;

function listarMigraciones({ conDatosSemilla }) {
  return fs
    .readdirSync(DIR_MIGRACIONES)
    .filter((f) => f.endsWith('.sql'))
    .filter((f) => conDatosSemilla || !ARCHIVOS_DATOS_SEMILLA.has(f))
    .sort();
}

function partirEnLotes(contenidoSql) {
  return contenidoSql
    .split(SEPARADOR_LOTE)
    .map((lote) => lote.trim())
    .filter((lote) => lote.length > 0);
}

function checksum(contenidoSql) {
  return crypto.createHash('sha256').update(contenidoSql, 'utf8').digest('hex');
}

/* El propio ops.migracion_aplicada (definido en la migracion 0003) es donde se
   anota que 0001..0003 ya corrieron. Sin este bootstrap no habria donde escribir
   esa primera fila: el objeto que registra el progreso no puede depender de que
   el progreso ya haya llegado hasta el. Es SQL crudo e idempotente, no una
   migracion mas — vive aqui y no en migraciones/ a proposito. */
async function bootstrap(cx) {
  const req = cx.request();
  await req.batch(`
    if schema_id('ops') is null exec ('create schema ops');
  `);
  await cx.request().batch(`
    if object_id('ops.migracion_aplicada') is null
    create table ops.migracion_aplicada (
        archivo      varchar(200)  not null constraint pk_migracion_aplicada primary key,
        aplicada_en  datetime2(0)  not null constraint df_migracion_cuando default sysdatetime(),
        aplicada_por varchar(60)   not null constraint df_migracion_quien  default suser_sname(),
        checksum     char(64)      not null
    );
  `);
}

async function aplicadas(cx) {
  const r = await cx.request().query('select archivo, checksum from ops.migracion_aplicada');
  const mapa = new Map();
  for (const fila of r.recordset) mapa.set(fila.archivo, fila.checksum);
  return mapa;
}

async function aplicarMigracion(cx, sql, archivo, contenidoSql) {
  const lotes = partirEnLotes(contenidoSql);
  const tx = new sql.Transaction(cx);
  await tx.begin();
  try {
    for (const lote of lotes) {
      await new sql.Request(tx).batch(lote);
    }
    await new sql.Request(tx)
      .input('archivo', sql.VarChar(200), archivo)
      .input('checksum', sql.Char(64), checksum(contenidoSql))
      .query(
        `insert ops.migracion_aplicada (archivo, checksum) values (@archivo, @checksum)`
      );
    await tx.commit();
  } catch (err) {
    await tx.rollback().catch(() => {});
    throw err;
  }
}

async function main() {
  const argumentos = process.argv.slice(2);
  const conDatosSemilla = argumentos.includes('--con-datos-semilla');
  const soloEstado = argumentos.includes('--estado');

  const sql = conexion.cargarDriver();
  const cx = await conexion.pool({ prefijoUsuario: 'SQL_MIGRADOR' });

  await bootstrap(cx);
  const yaAplicadas = await aplicadas(cx);
  const disponibles = listarMigraciones({ conDatosSemilla });

  if (soloEstado) {
    console.log('Migraciones disponibles y su estado:\n');
    for (const archivo of disponibles) {
      const estado = yaAplicadas.has(archivo) ? 'aplicada' : 'pendiente';
      console.log(`  [${estado.padEnd(9)}] ${archivo}`);
    }
    const pendientes = disponibles.filter((a) => !yaAplicadas.has(a));
    console.log(`\n${pendientes.length} pendiente(s) de ${disponibles.length}.`);
    await conexion.cerrar();
    return;
  }

  const pendientes = disponibles.filter((a) => !yaAplicadas.has(a));
  if (pendientes.length === 0) {
    console.log('Nada que aplicar: la base ya esta al dia.');
    await conexion.cerrar();
    return;
  }

  console.log(`Aplicando ${pendientes.length} migracion(es):`);
  for (const archivo of pendientes) {
    const ruta = path.join(DIR_MIGRACIONES, archivo);
    const contenidoSql = fs.readFileSync(ruta, 'utf8');
    process.stdout.write(`  ${archivo} ... `);
    try {
      await aplicarMigracion(cx, sql, archivo, contenidoSql);
      console.log('ok');
    } catch (err) {
      console.log('FALLO');
      console.error(`\n${archivo} se revirtio entera (transaccion unica). Detalle:`);
      console.error(err.message || err);
      await conexion.cerrar();
      process.exitCode = 1;
      return;
    }
  }
  console.log('\nListo. Base al dia.');
  await conexion.cerrar();
}

main().catch((err) => {
  console.error('Fallo inesperado del migrador:', err.message || err);
  process.exitCode = 1;
});
