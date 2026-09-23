/**
 * El respaldo de la base, disparado desde la propia aplicacion.
 *
 * instalacion/respaldar.ps1 hace el trabajo (BACKUP DATABASE y copia a OneDrive). Este
 * modulo decide CUANDO: despues de cada captura o correccion, y una vez al dia. Lo
 * diario vive aqui y no en una tarea programada de Windows porque registrar una tarea
 * exige un PowerShell elevado, y la instalacion en modo contenedor tiene que poder
 * hacerse sin administrador. Mientras el tablero corre (desde que la persona inicia
 * sesion), el respaldo del dia sale.
 *
 * Solo actua en una instalacion real: EHS_CARPETA_RESPALDO la escribe instalar.ps1 en
 * config\ehs.env. En desarrollo no existe y todo esto no hace nada.
 */
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { setTimeout, setInterval } = require('timers');
const { obtener } = require('./datos/configuracion');

const SCRIPT = path.join(__dirname, '..', 'instalacion', 'respaldar.ps1');
const HORAS_ENTRE_RESPALDOS = 20;
let ultimoDisparo = 0;

/** Cuando se tomo el ultimo .bak; undefined sin carpeta configurada, null si no hay. */
function fechaUltimoRespaldo() {
  const carpeta = obtener('EHS_CARPETA_RESPALDO');
  // undefined (y no null) sin carpeta configurada: JSON.stringify omite la clave, y la
  // franja de estado distingue "no aplica aqui" de "aplica y no hay ningun respaldo".
  if (!carpeta) return undefined;
  try {
    let ultima = 0;
    for (const nombre of fs.readdirSync(carpeta)) {
      if (!/^ehs-analitica-.*\.bak$/.test(nombre)) continue;
      const t = fs.statSync(path.join(carpeta, nombre)).mtimeMs;
      if (t > ultima) ultima = t;
    }
    return ultima ? new Date(ultima).toISOString() : null;
  } catch {
    return null;
  }
}

/**
 * Lanza respaldar.ps1 en segundo plano, sin ventana y sin esperarlo: su fallo no puede
 * afectar la respuesta que ya se le dio a quien capturo. Si queda mal, lo registra en
 * ultimo-respaldo.log y la franja de estado lo muestra (el ultimo .bak envejece).
 * Varias capturas seguidas no lanzan varios respaldos a la vez: uno por minuto basta.
 */
function disparar() {
  if (!obtener('EHS_CARPETA_RESPALDO') || !fs.existsSync(SCRIPT)) return;
  if (Date.now() - ultimoDisparo < 60 * 1000) return;
  ultimoDisparo = Date.now();
  try {
    // SIN detached: en Windows, detached lanza el hijo sin consola (DETACHED_PROCESS),
    // y powershell.exe 5.1 asi sale con codigo 0 sin correr el script. Probado en la
    // primera instalacion real: ni el respaldo de despues de capturar ni el diario
    // salian nunca, y no quedaba ni el log. Sin detached hereda la consola invisible
    // del tablero (conhost --headless), asi que tampoco abre ventana. El precio: si el
    // tablero se cierra a mitad de un respaldo, ese respaldo se corta; el siguiente
    // lo repone.
    const hijo = spawn(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT],
      {
        stdio: 'ignore',
        windowsHide: true,
      }
    );
    hijo.unref();
    hijo.on('error', () => {});
  } catch {
    // mejor esfuerzo: el respaldo del dia lo vuelve a intentar programarDiario()
  }
}

/** Al arrancar y cada hora: si el ultimo respaldo tiene mas de 20 h (o no hay), uno nuevo. */
function programarDiario() {
  if (!obtener('EHS_CARPETA_RESPALDO')) return;
  const revisar = () => {
    const ultimo = fechaUltimoRespaldo();
    const horas = ultimo ? (Date.now() - new Date(ultimo).getTime()) / 36e5 : Infinity;
    if (horas >= HORAS_ENTRE_RESPALDOS) disparar();
  };
  // unos minutos despues de arrancar: al iniciar sesion el motor puede estar subiendo
  setTimeout(revisar, 3 * 60 * 1000).unref();
  setInterval(revisar, 60 * 60 * 1000).unref();
}

module.exports = { disparar, programarDiario, fechaUltimoRespaldo };
